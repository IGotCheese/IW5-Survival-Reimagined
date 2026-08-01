// bpg_survival_bankcmds.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-17.
// User: "build a real bank system + the !ammo/!armor/!revive commands".
//
// The mod already SELLS ammo/armor/self-revive at armories, already keeps each player's cash
// across deaths (pers["score"]) AND carries it across map changes (its saveState snapshot).
// GSC has no file I/O and setPlayerData needs predefined fields, so a PRIVATE cross-map
// savings account isn't cleanly doable — but a SHARED TEAM BANK is genuinely new and fits how
// this co-op server already plays (they use !pay). So:
//   !ammo              - refill your current weapon's reserve ammo   (costs bpg_price_ammo)
//   !armor / !armour   - full body armor                            (costs bpg_price_armor)
//   !revive            - buy a self-revive                          (costs bpg_price_revive)
//   !bank              - show the shared team bank + your cash
//   !deposit <amount>  - move cash from you into the team bank
//   !withdraw <amount> - take cash from the team bank
// Prices are dvars — set any to 0 to make that command free. The team bank is a per-map
// shared pool (resets on map change; each player's OWN cash still carries over via the mod).
// All money moves ONLY through the mod's survivor_set_score (updates pers + .score + ui_money),
// exactly like !pay. NEVER copy to live <MP-PORT> (references lethalbeats\* scripts).

#include maps\mp\_utility;
#include common_scripts\utility;

#define SETVAULT_POWER 100    // owner-only; !clear (the next most dangerous) sits at 70
#define SETVAULT_MAX   999999999   // well under the 32-bit int ceiling, so no wrap

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	if ( getDvar( "bpg_price_ammo" )   == "" ) setDvar( "bpg_price_ammo",   "750" );
	if ( getDvar( "bpg_price_armor" )  == "" ) setDvar( "bpg_price_armor",  "2500" );
	if ( getDvar( "bpg_price_revive" ) == "" ) setDvar( "bpg_price_revive", "4500" );

	// PERSISTENCE: file-backed bank via iw5-gsc-utils io DISABLED 2026-07-17 for stability — the
	// plugin loads unreliably under CPU contention, so writeFile/readFile intermittently fail to
	// resolve and break this whole script (buy commands included). Per-map pool until the box's
	// respawning stray-process / contention is resolved, then re-enable file persistence.
	if ( !isDefined( game[ "bpg_bank" ] ) )
		game[ "bpg_bank" ] = 0;

	// PRIVATE PER-PLAYER VAULT (added 2026-07-30, user: "keep both"). The team bank above stays
	// exactly as it was - this is a SECOND, separate balance per player, so the co-op pooling
	// people already use is untouched.
	// WHY game[] AND NOT self.pers[]: game[] survives a map change, and pers[] does NOT survive
	// it for arbitrary keys. The mod's own carry-over (utility.gsc:1773-1872) snapshots each
	// player into game["saveState"][guid] using an EXPLICIT allowlist - kills, deaths, assists,
	// score, killstreak - and restores only those (:1612-1639). A self.pers["bpg_vault"] would
	// therefore be silently dropped on every rotation. Keying our own game[] array by guid is
	// the same mechanism the mod uses, without depending on its list.
	// NOT file-backed: that needs the iw5-gsc-utils io builtins, which were disabled here on
	// 07-17 for stability. They do register cleanly now, but a vault that survives a full server
	// restart is a separate step - this one survives map changes, not restarts.
	// The array grows by one int per distinct player per session; entries are deliberately NOT
	// dropped on disconnect (unlike the mod's saveState, which does drop them at utility.gsc:1514)
	// so a player who reconnects still has their savings.
	if ( !isDefined( game[ "bpg_vault" ] ) )
		game[ "bpg_vault" ] = [];

	// NOTE: the mod's dev/test.gsc reserves ammo/armor/revive as dev-only commands and
	// (mod init runs AFTER loose scripts) overwrites ours -> "no permission" for players.
	// Use unique names so nothing overrides them.
	lethalbeats\servercontrol\commands::setCommand( "buyammo",    ::bpg_ammo_cmd,   0, 0 );
	lethalbeats\servercontrol\commands::setCommand( "refill",     ::bpg_ammo_cmd,   0, 0 );
	lethalbeats\servercontrol\commands::setCommandAlias( "buyammo", "ba" );
	lethalbeats\servercontrol\commands::setCommand( "buyarmor",   ::bpg_armor_cmd,  0, 0 );
	lethalbeats\servercontrol\commands::setCommand( "buyarmour",  ::bpg_armor_cmd,  0, 0 );
	lethalbeats\servercontrol\commands::setCommandAlias( "buyarmor", "bar" );
	lethalbeats\servercontrol\commands::setCommand( "buyrevive",  ::bpg_revive_cmd, 0, 0 );
	lethalbeats\servercontrol\commands::setCommand( "selfrevive", ::bpg_revive_cmd, 0, 0 );
	lethalbeats\servercontrol\commands::setCommandAlias( "buyrevive", "br" );
	lethalbeats\servercontrol\commands::setCommand( "bank",   ::bpg_bank_cmd,   0, 0 );
	lethalbeats\servercontrol\commands::setCommandAlias( "bank", "b" );
	lethalbeats\servercontrol\commands::setCommand( "deposit",  ::bpg_deposit_cmd,  0, 1, "^7Usage: ^3!deposit <amount>" );
	lethalbeats\servercontrol\commands::setCommandAlias( "deposit", "d" );
	lethalbeats\servercontrol\commands::setCommand( "withdraw", ::bpg_withdraw_cmd, 0, 1, "^7Usage: ^3!withdraw <amount>" );
	lethalbeats\servercontrol\commands::setCommandAlias( "withdraw", "w" );

	// private per-player vault (separate from the shared team bank above)
	lethalbeats\servercontrol\commands::setCommand( "vault", ::bpg_vault_cmd, 0, 0 );
	lethalbeats\servercontrol\commands::setCommandAlias( "vault", "v" );
	lethalbeats\servercontrol\commands::setCommand( "vdeposit",  ::bpg_vdeposit_cmd,  0, 1, "^7Usage: ^3!vdeposit <amount>" );
	lethalbeats\servercontrol\commands::setCommandAlias( "vdeposit", "vd" );
	lethalbeats\servercontrol\commands::setCommand( "vwithdraw", ::bpg_vwithdraw_cmd, 0, 1, "^7Usage: ^3!vwithdraw <amount>" );
	lethalbeats\servercontrol\commands::setCommandAlias( "vwithdraw", "vw" );

	// ADMIN: set any connected player's vault outright. Power 100 - the highest gate in use here
	// (!clear is 70) - because this MINTS money and nothing else on this server does.
	// No alias on purpose: a two-character shortcut sitting next to !vd/!vw is a misfire waiting
	// to happen, and the misfire hands somebody an arbitrary balance.
	lethalbeats\servercontrol\commands::setCommand( "setvault", ::bpg_setvault_cmd, SETVAULT_POWER, 2, "^7Usage: ^3!setvault <player> <amount>" );

	level thread bpg_bank_announce();
}

// ── helpers ────────────────────────────────────────────────────────────────────
bpg_cash()
{
	if ( isDefined( self.pers[ "score" ] ) )
		return self.pers[ "score" ];
	return 0;
}

// charge `price` from self; returns true if paid (or free), false + tells if too poor.
bpg_charge( price )
{
	if ( price <= 0 )
		return true;
	if ( self bpg_cash() < price )
	{
		self tell( "^1Not enough cash ^7- need ^3$" + price );
		return false;
	}
	self lethalbeats\survival\utility::survivor_set_score( int( self bpg_cash() - price ) );
	return true;
}

bpg_pricetag( price )
{
	if ( price <= 0 )
		return "";
	return " ^7(^3$" + price + "^7)";
}


// ── convenience buys ───────────────────────────────────────────────────────────
bpg_ammo_cmd( a, b, c )
{
	if ( self isTestClient() || !isAlive( self ) )
		return;

	weap = self getCurrentWeapon();
	if ( !isDefined( weap ) || weap == "none" || weap == "riotshield_mp" )
	{
		self tell( "^1No weapon to resupply" );
		return;
	}

	// already topped up? (same check the buy station's "owned" state uses)
	if ( self lethalbeats\player::player_has_max_ammo( weap ) )
	{
		self tell( "^3Your ammo is already full" );
		return;
	}

	// EXACT buy-station price: base-by-weapon-class (+ GL/xmags/shotgun) MINUS the fraction of
	// ammo you already carry — so a near-full weapon costs a few bucks, an empty one full price.
	cost = self lethalbeats\survival\armories\weapons::getAmmoPrice( weap );
	if ( cost < 0 )
		cost = 0;

	if ( !( self bpg_charge( cost ) ) )
		return;

	self lethalbeats\player::player_give_max_ammo( weap );
	self playLocalSound( "ammo_crate_use" );
	self tell( "^2Ammo refilled" + bpg_pricetag( cost ) );
}

bpg_armor_cmd( a, b, c )
{
	if ( self isTestClient() || !isAlive( self ) )
		return;

	maxArmor = lethalbeats\survival\utility::get_max_armor();
	if ( isDefined( self.bodyArmor ) && self.bodyArmor >= maxArmor )
	{
		self tell( "^3You already have full armor" );
		return;
	}

	price = getDvarInt( "bpg_price_armor" );
	if ( !( self bpg_charge( price ) ) )
		return;

	self lethalbeats\survival\utility::survivor_set_body_armor( maxArmor );
	self tell( "^2Body armor restored" + bpg_pricetag( price ) );
}

bpg_revive_cmd( a, b, c )
{
	if ( self isTestClient() || !isAlive( self ) )
		return;

	if ( isDefined( self.hasRevive ) && self.hasRevive )
	{
		self tell( "^3You already have a self-revive" );
		return;
	}

	price = getDvarInt( "bpg_price_revive" );
	if ( !( self bpg_charge( price ) ) )
		return;

	self lethalbeats\survival\utility::survivor_give_last_stand();
	self tell( "^2Self-revive purchased" + bpg_pricetag( price ) );
}

// ── shared team bank ─────────────────────────────────────────────────────────────
bpg_bank_cmd( a, b, c )
{
	if ( self isTestClient() )
		return;
	self tell( "^3Team Bank: ^2$" + game[ "bpg_bank" ] + "   ^7Your cash: ^2$" + self bpg_cash() );
	self tell( "^3!deposit <amt> ^7/ ^3!withdraw <amt>" );
}

bpg_bank_ratelimited()
{
	if ( isDefined( self.bpg_bank_next ) && getTime() < self.bpg_bank_next )
	{
		self tell( "^1Easy there ^7- one bank move every 2s" );
		return true;
	}
	self.bpg_bank_next = getTime() + 2000;
	return false;
}

bpg_deposit_cmd( amountStr, b, c )
{
	if ( self isTestClient() )
		return;
	if ( self bpg_bank_ratelimited() )
		return;

	amount = int( amountStr );
	if ( amount < 50 )
	{
		self tell( "^1Minimum deposit is ^3$50" );
		return;
	}
	if ( self bpg_cash() < amount )
	{
		self tell( "^1You don't have that much cash" );
		return;
	}

	self lethalbeats\survival\utility::survivor_set_score( int( self bpg_cash() - amount ) );
	game[ "bpg_bank" ] += amount;
	self tell( "^2Deposited ^3$" + amount + " ^7- team bank now ^2$" + game[ "bpg_bank" ] );
}

bpg_withdraw_cmd( amountStr, b, c )
{
	if ( self isTestClient() )
		return;
	if ( self bpg_bank_ratelimited() )
		return;

	amount = int( amountStr );
	if ( amount < 50 )
	{
		self tell( "^1Minimum withdrawal is ^3$50" );
		return;
	}
	if ( game[ "bpg_bank" ] < amount )
	{
		self tell( "^1Team bank only has ^3$" + game[ "bpg_bank" ] );
		return;
	}

	game[ "bpg_bank" ] -= amount;
	self lethalbeats\survival\utility::survivor_set_score( int( self bpg_cash() + amount ) );
	self tell( "^2Withdrew ^3$" + amount + " ^7- team bank now ^2$" + game[ "bpg_bank" ] );
}

// ── private per-player vault ──────────────────────────────────────────────────
// Deliberately a SECOND balance, not a replacement: the shared team bank above is what
// people use to fund each other's revives, so removing it would change how the server plays.
//
// PERSISTENCE HANDSHAKE - read this before touching it:
// This file NEVER calls a plugin builtin. It only sets a flag and fires a notify. The optional
// file-backed persistence lives entirely in bpg_survival_vaultstore.gsc, which listens for that
// notify. That separation is the whole point: on 2026-07-17 file persistence was wired directly
// into THIS file, and because an unresolved plugin builtin is a COMPILE error in GSC
// ("couldn't determine function call type"), a plugin that failed to load took the buy commands
// down with it. With the handshake, a broken vaultstore just means the vault stops surviving
// restarts - !buyammo/!buyarmor/!buyrevive/!bank keep working regardless.
bpg_vault_get()
{
	if ( !isDefined( game[ "bpg_vault" ] ) || !isDefined( self.guid ) )
		return 0;
	if ( !isDefined( game[ "bpg_vault" ][ self.guid ] ) )
		return 0;
	return game[ "bpg_vault" ][ self.guid ];
}

bpg_vault_set( amount )
{
	if ( !isDefined( self.guid ) )
		return;
	if ( !isDefined( game[ "bpg_vault" ] ) )
		game[ "bpg_vault" ] = [];

	game[ "bpg_vault" ][ self.guid ] = int( amount );

	// Tell the (optional) persistence layer something changed. Still a notify, never a direct
	// call - the isolation contract in the header depends on that.
	// `self` is passed so per-player mode can rewrite ONLY this player's file instead of
	// rewriting everyone's, which is what makes cross-server savings safe: two servers touching
	// two different players' files can never clobber each other. Single-file mode ignores the
	// argument and uses the dirty flag, so both modes work off this one notify.
	level.bpg_vault_dirty = true;
	level notify( "bpg_vault_changed", self );
}

bpg_vault_cmd( a, b, c )
{
	if ( self isTestClient() )
		return;

	self tell( "^3Your Vault: ^2$" + self bpg_vault_get() + "   ^7Your cash: ^2$" + self bpg_cash() );
	self tell( "^3!vdeposit <amt> ^7/ ^3!vwithdraw <amt>   ^7(private - the team pool is ^3!bank^7)" );
}

bpg_vdeposit_cmd( amountStr, b, c )
{
	if ( self isTestClient() )
		return;
	// shares the team bank's rate limiter on purpose: one money move every 2s across BOTH
	// balances, so nobody can ping-pong cash between them to spam anything.
	if ( self bpg_bank_ratelimited() )
		return;

	amount = int( amountStr );
	if ( amount < 50 )
	{
		self tell( "^1Minimum deposit is ^3$50" );
		return;
	}
	if ( self bpg_cash() < amount )
	{
		self tell( "^1You don't have that much cash" );
		return;
	}

	self lethalbeats\survival\utility::survivor_set_score( int( self bpg_cash() - amount ) );
	self bpg_vault_set( self bpg_vault_get() + amount );
	self tell( "^2Stored ^3$" + amount + " ^7- your vault now ^2$" + self bpg_vault_get() );
}

bpg_vwithdraw_cmd( amountStr, b, c )
{
	if ( self isTestClient() )
		return;
	if ( self bpg_bank_ratelimited() )
		return;

	amount = int( amountStr );
	if ( amount < 50 )
	{
		self tell( "^1Minimum withdrawal is ^3$50" );
		return;
	}

	have = self bpg_vault_get();
	if ( have < amount )
	{
		self tell( "^1Your vault only has ^3$" + have );
		return;
	}

	self bpg_vault_set( have - amount );
	self lethalbeats\survival\utility::survivor_set_score( int( self bpg_cash() + amount ) );
	self tell( "^2Took ^3$" + amount + " ^7- your vault now ^2$" + self bpg_vault_get() );
}

// ── ADMIN: !setvault <player> <amount> ─────────────────────────────────────────
// Added 2026-07-30. Editing C:\Vaults\<guid>.txt by hand only works while that player is
// OFFLINE: the vault loads into game["bpg_vault"] on connect and flushes back to disk on
// disconnect, so a hand-edit made during a session is silently overwritten by the in-memory
// value when they leave. That happened on 2026-07-30. This command writes MEMORY, which is the
// authoritative copy, so connection state stops mattering.
//
// It deliberately routes through bpg_vault_set() rather than touching game["bpg_vault"]
// directly, so the persistence handshake is identical to !vdeposit/!vwithdraw: memory is
// updated, then level notify("bpg_vault_changed", player) fires and bpg_survival_vaultstore.gsc
// rewrites ONLY that player's file. No plugin builtin is called from here - that isolation is
// load-bearing and is documented at bpg_vault_set().
//
// ONLINE TARGETS ONLY. Setting an offline player's vault means writing their file, which needs
// the io builtins, and pulling those into this file is exactly what took the buy commands down
// on 2026-07-17. For an offline player, edit C:\Vaults\<guid>.txt directly while they are
// disconnected - which is safe precisely because they are not connected to overwrite it.
bpg_setvault_cmd( targetName, amountStr, c )
{
	if ( !isDefined( targetName ) || !isDefined( amountStr ) )
	{
		self tell( "^7Usage: ^3!setvault <player> <amount>" );
		return;
	}

	// Reject anything that is not a clean non-negative integer. int() on garbage returns 0,
	// which would silently WIPE a vault instead of erroring - so round-trip the string and
	// require it to match. Also blocks "-5" reaching bpg_vault_set as a negative balance.
	amount = int( amountStr );
	if ( ( "" + amount ) != amountStr || amount < 0 )
	{
		self tell( "^1Bad amount ^7- whole numbers only, e.g. ^3!setvault " + targetName + " 1000000" );
		return;
	}

	if ( amount > SETVAULT_MAX )
	{
		self tell( "^1Too large ^7- max is ^3$" + SETVAULT_MAX );
		return;
	}

	target = self bpg_setvault_findone( targetName );
	if ( !isDefined( target ) )
		return;   // findone already explained why

	before = target bpg_vault_get();
	target bpg_vault_set( amount );

	self tell( "^2Set ^7" + target.name + "^2's vault: ^3$" + before + " ^7-> ^2$" + target bpg_vault_get() );
	if ( target != self )
		target tell( "^2An admin set your vault to ^3$" + target bpg_vault_get() );

	// Audit trail. This mints currency, so it should never be silent - and console.log is the
	// only record that survives if someone disputes a balance later.
	println( "[BPG-SETVAULT] " + self.name + " (" + self.guid + ") set " + target.name + " (" + target.guid + ") from $" + before + " to $" + amount );
}

// Stricter than ServerControl's findPlayer(), which returns the FIRST substring match and never
// reports ambiguity. That is acceptable for !kick; it is not acceptable for a command that hands
// out money, where hitting the wrong "a"-matching player is a silent, hard-to-notice mistake.
// Exact (case-insensitive) name always wins so a player whose name is a substring of someone
// else's is still addressable.
bpg_setvault_findone( needle )
{
	want = tolower( needle );
	matches = [];

	foreach ( p in level.players )
	{
		if ( !isDefined( p ) || !isDefined( p.name ) || p isTestClient() )
			continue;

		if ( tolower( p.name ) == want )
			return p;   // exact match short-circuits ambiguity entirely

		if ( isSubStr( tolower( p.name ), want ) )
			matches[ matches.size ] = p;
	}

	if ( !matches.size )
	{
		self tell( "^1No player matching ^3" + needle );
		return undefined;
	}

	if ( matches.size > 1 )
	{
		names = "";
		foreach ( m in matches )
		{
			if ( names != "" ) names = names + "^7, ";
			names = names + "^3" + m.name;
		}
		self tell( "^1Ambiguous ^7- matches " + names );
		return undefined;
	}

	return matches[ 0 ];
}

bpg_bank_announce()
{
	level endon( "game_ended" );
	level waittill( "wave_start" );
	wait 50;
	iprintln( "^7New: ^3!buyammo ^3!buyarmor ^3!buyrevive^7, team ^3!bank ^7(^3!deposit^7/^3!withdraw^7) and your private ^3!vault ^7(^3!vdeposit^7/^3!vwithdraw^7)" );
}
