// bpg_survival_afk.gsc — SURVIVAL SERVER ONLY (isolated storage).
// !afk — 600 seconds of AFK protection. Toggle: !afk again to return early.
// ANTI-ABUSE: weapons + usability disabled and controls frozen while AFK (protected but
// harmless), 60s cooldown after it ends, denied while downed.
//
// ⚠️⚠️ 2026-07-27 — DO NOT REINTRODUCE `self.sessionstate = "spectator"` IN THIS FILE.
// The 2026-07-26 refactor moved AFK onto the engine spectator state (allowSpectateTeam
// "freelook" + sessionstate), the same toggle found in lethalbeats\Survival\dev\test.gsc
// lines 654-664 — which is a DEV tool, not production code. Entering spectator tears down
// the client's weapon and viewmodel state, and there was no matching rebuild on the way
// back: the return path simply assigned sessionstate = "playing" again, with no respawn
// and no loadout restore. Stock GSC never does that — spawnPlayer()/spawnSpectator() BOTH
// follow the assignment with `self spawn(origin, angles)`, and the mod author documents the
// same engine behaviour on the equivalent function in utility.gsc: player_hide() is
// "only reversible after respawn". Live symptom (user report 2026-07-27):
//     "after coming back from afk mode you get invisible hands and loose your guns"
// This file is back to the pre-refactor mechanism, which ran live 2026-07-16 -> 07-26 with
// no weapon loss: a bpg_afk flag + disableWeapons/disableUsability + setContents(0) +
// freezeControls(true). Nothing is ever taken away from the player, so nothing has to be
// given back — which is exactly why this version cannot lose a weapon.
//
// ⚠️ DAMAGE IMMUNITY LIVES IN bpg_survival_ah6nerf.gsc, NOT HERE. Only ONE replaceFunc of
// survivorHandler::onPlayerDamage can be active at a time (last-loaded-wins, proven live
// 2026-07-19 when a second file's replaceFunc silently won and never fired), and
// ah6nerf.gsc owns it. The AFK early-return is merged into that copy — see the bpg_afk
// check at the top of bpg_onPlayerDamage_ah6nerf(). Do NOT add a second replaceFunc here.
// While AFK was a spectator the engine granted immunity for free; with the spectator
// mechanism gone that hook check is load-bearing again.
//
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

#include lethalbeats\survival\utility;
#include lethalbeats\player;
#include lethalbeats\hud;

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	if ( getDvar( "bpg_afk_seconds" ) == "" )
		setDvar( "bpg_afk_seconds", "600" );

	// MUST be precached at init or CLIENTS error when the icon is set (live report
	// 2026-07-17: "!afk gives a survival error" — the server log stayed clean because the
	// failure is client-side rendering of an un-precached material)
	precacheStatusIcon( "hud_status_connecting" ); // scoreboard marker

	lethalbeats\servercontrol\commands::setCommand( "afk", ::bpg_afk_cmd );
}

bpg_afk_cmd()
{
	if ( self isTestClient() )
		return;

	// --- TOGGLE OFF (return from AFK) ---
	// Keyed off our own flag, NOT self.sessionstate: this build never touches sessionstate.
	// This check now runs BEFORE the inLastStand guard below. In the 07-26 version the
	// order was reversed, so a player who went AFK and then somehow ended up downed was
	// answered "You can't go AFK while downed" and could never toggle back — permanently
	// stuck frozen. Returning must never be blocked by a guard that only concerns leaving.
	if ( isDefined( self.bpg_afk ) && self.bpg_afk )
	{
		// Safe to notify from here: the command handler has no "bpg_afk_end" endon, so
		// this stops the timer + death guard without terminating the current thread.
		self notify( "bpg_afk_end" );
		self bpg_afk_restore();
		self bpg_afk_announce_back();
		return;
	}

	if ( isDefined( self.inLastStand ) && self.inLastStand )
	{
		self tell( "^1You can't go AFK while downed" );
		return;
	}

	// Check cooldown before allowing the player to go AFK
	if ( isDefined( self.bpg_afk_next ) && getTime() < self.bpg_afk_next )
	{
		remain = int( ( self.bpg_afk_next - getTime() ) / 1000 ) + 1;
		self tell( "^1AFK on cooldown: ^7" + remain + "s" );
		return;
	}

	seconds = getDvarInt( "bpg_afk_seconds" );
	if ( seconds < 30 ) seconds = 30;
	if ( seconds > 3600 ) seconds = 3600;

	// --- TOGGLE ON (go AFK) ---
	// Four independent scripts read self.bpg_afk to decide whether to leave an AFK player
	// alone, so it must be set before anything else and cleared on EVERY exit path:
	//   * bpg_survival_ah6nerf.gsc  onPlayerDamage       - swallow all damage
	//   * bpg_survival_dogfix.gsc   bpg_dog_pick_target() - never target AFK players
	//   * bpg_survival_morecmds.gsc bpg_stuck_cmd()       - block !stuck while AFK
	//   * bpg_survival_votekick.gsc                       - exempt AFK from votekick
	self.bpg_afk = true;

	self setContents( 0 );      // non-solid: bullets and bodies pass straight through
	self freezeControls( true );
	self lethalbeats\player::player_disable_weapons();
	self lethalbeats\player::player_disable_usability();

	// best-effort: some Bot Warfare builds skip targeting entities flagged this way. The
	// damage hook is the actual guarantee; this just stops AFK players drawing bot fire,
	// which the spectator mechanism used to get for free by removing the body outright.
	self.ignoreme = true;

	self.statusicon = "hud_status_connecting"; // scoreboard marker

	self iPrintLnBold( "^2AFK mode: protected for " + seconds + "s ^7- type ^3!afk ^7to return" );
	iprintln( "^3" + self.name + " ^7is AFK" );

	self thread bpg_afk_timer( seconds );
	self thread bpg_afk_death_guard();
}

// Single restore path shared by all three exits (manual toggle, timer expiry, death guard)
// so they cannot drift out of sync — the 07-26 version open-coded the restore three times
// and each copy did something slightly different. Every line here is the exact inverse of
// the entry block above. Deliberately does NOT notify "bpg_afk_end": two of the three
// callers hold an endon for it and would kill themselves mid-restore, so each caller sends
// that notify itself at a point where losing the thread is harmless.
bpg_afk_restore()
{
	self.bpg_afk = false;
	self.ignoreme = undefined;

	// 100 is the players' normal contents value — the same constant the mod itself
	// restores players to in lethalbeats\Survival\botHandler.gsc:58.
	self setContents( 100 );
	self freezeControls( false );
	self lethalbeats\player::player_enable_weapons();
	self lethalbeats\player::player_enable_usability();

	self.statusicon = "";
	self.bpg_afk_next = getTime() + 60000; // 60s before !afk can be used again
}

bpg_afk_announce_back()
{
	self iPrintLnBold( "^2You're back in the fight" );
	iprintln( "^3" + self.name + " ^7is back" );
}

bpg_afk_timer( seconds )
{
	self endon( "disconnect" );
	self endon( "death" );
	self endon( "bpg_afk_end" );
	level endon( "game_ended" );

	wait seconds;

	if ( isDefined( self.bpg_afk ) && self.bpg_afk )
	{
		self bpg_afk_restore();
		self bpg_afk_announce_back();
	}

	// LAST statement on purpose: this thread holds an endon for "bpg_afk_end", so the
	// notify may terminate it right here. Nothing is left to run, and it stops the
	// death guard.
	self notify( "bpg_afk_end" );
}

// If an AFK player dies anyway (wave wipe, !suicide, MOD_TRIGGER_HURT), unwind AFK state
// so they do not respawn frozen, non-solid and unable to fire.
bpg_afk_death_guard()
{
	self endon( "disconnect" );
	self endon( "bpg_afk_end" );

	self waittill( "death" );

	if ( isDefined( self.bpg_afk ) && self.bpg_afk )
		self bpg_afk_restore();

	self notify( "bpg_afk_end" ); // LAST statement — see the note in bpg_afk_timer()
}
