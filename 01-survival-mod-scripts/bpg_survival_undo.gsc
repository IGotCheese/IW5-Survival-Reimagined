// bpg_survival_undo.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-16.
// !undo — reverses buy-station purchases from the CURRENT shop visit (misclick fix).
// The buy-station BUTTON couldn't be added (compiled menu, no source, tooling can't
// round-trip the mod's custom menu zone; a custom menu mod proved the technique but its
// menus crash on precache-overflow). This is the GSC chat-command equivalent.
//
// HOW: snapshot the player's full purchasable state when they OPEN a buy station
// (replaceFunc copy of dynamic_shop::shopInit — only snapshots on a FRESH open, not
// on page navigation), and !undo restores it. Refund + item-reversal are atomic, so
// no free money or free items. Capture/restore mirror the mod's own proven
// saveData/restoreData (dev\test.gsc) — same player_get/set_weapon_data + ammo_data
// + survivor_set_score/body_armor + perks/nades/killstreak helpers.
// Scope: undoes everything bought since the current buy-station was opened (covers
// the common "opened shop, misclicked" case). One use per visit.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

#include lethalbeats\survival\utility;
#include lethalbeats\player;

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( lethalbeats\dynamicmenus\dynamic_shop::shopInit, ::bpg_shopinit_snapshot );
	lethalbeats\servercontrol\commands::setCommand( "undo", ::bpg_undo_cmd, 0, 0 );
	lethalbeats\servercontrol\commands::setCommandAlias( "undo", "u" );
}

// Copy of dynamic_shop::shopInit + a state snapshot taken on a fresh shop open.
bpg_shopinit_snapshot( menu )
{
	self.shop = spawnStruct();
	self.shop.menu = menu;
	self.shop.page = -1;
	self.shop.owner = self;

	if ( self isTestClient() )
		return;

	self bpg_take_snapshot();
}

bpg_take_snapshot()
{
	snap = [];
	snap[ "score" ] = self.pers[ "score" ];
	snap[ "armor" ] = self.bodyArmor;
	snap[ "hasRevive" ] = self.hasRevive;
	snap[ "perks" ] = self.survivalPerks;
	snap[ "grenades" ] = self.grenades;

	snap[ "killstreak" ] = "";
	if ( isDefined( self.pers[ "killstreaks" ] ) && isDefined( self.pers[ "killstreaks" ][ 0 ] ) && isDefined( self.pers[ "killstreaks" ][ 0 ].streakname ) )
		snap[ "killstreak" ] = self.pers[ "killstreaks" ][ 0 ].streakname;
	if ( lethalbeats\string::string_starts_with( snap[ "killstreak" ], "airdrop_" ) && isDefined( self.airdropType ) )
		snap[ "killstreak" ] = "airdrop_" + self.airdropType;

	snap[ "currentWeapon" ] = self getCurrentWeapon();
	snap[ "prevWeapon" ] = self.prevWeapon;

	primary = self player_get_primary();
	if ( isDefined( primary ) )
	{
		snap[ "weaponData" ][ 0 ] = self player_get_weapon_data( primary );
		if ( bpg_weapon_has_ammo( primary ) )
			snap[ "ammoData" ][ 0 ] = self player_get_ammo_data( primary );
	}
	secondary = self player_get_secondary();
	if ( isDefined( secondary ) )
	{
		snap[ "weaponData" ][ 1 ] = self player_get_weapon_data( secondary );
		if ( bpg_weapon_has_ammo( secondary ) )
			snap[ "ammoData" ][ 1 ] = self player_get_ammo_data( secondary );
	}

	self.bpg_undo = snap;
}

// 2026-07-30. `player_get_ammo_data` calls getWeaponAmmoClip/getWeaponAmmoStock
// unconditionally, and both HARD-ERROR on a primary that has no clip. That produced a pair
// of runtime errors on every buy-station open for affected players. The mod's own
// `player_give_random_ammo` (utility.gsc:423) already treats `weaponClipSize(weapon) == 0` as
// the normal clipless case, so weaponClipSize is the safe, in-idiom test - it returns 0 rather
// than erroring. Skipping ammoData is safe on the restore side: player_set_ammo_data's first
// line is `if (!isDefined(ammoData) ...) return;`, and the !undo loop still restores weaponData.
//
// The println names the weapon, because the SAME unguarded call is reached from stock
// `player_hide` (utility.gsc:461) on the dog-knockdown path, which this file cannot guard.
// There it is worse than log noise: the undefined clip flows into hideData, and the later
// setWeaponAmmoClip(weapon, undefined) is exactly the error seen in bpg_player_show_fixed.
// Once the culprit weapon is named, that gets fixed at the source instead of per-caller.
bpg_weapon_has_ammo( weapon )
{
	if ( !isDefined( weapon ) || weapon == "" || weapon == "none" )
		return false;

	if ( weaponClipSize( weapon ) > 0 )
		return true;

	println( "[BPG-AMMOGUARD] skipped clipless primary: " + weapon );
	return false;
}

bpg_undo_cmd( a, b, c ) // optional args: dispatcher passes trailing words as args (checkclearparams guard)
{
	if ( self isTestClient() )
		return;

	if ( !isDefined( self.bpg_undo ) )
	{
		self tell( "^1Nothing to undo ^7- open a buy station and !undo reverses that visit's purchases" );
		return;
	}

	if ( !isAlive( self ) )
	{
		self tell( "^1Can't undo while dead" );
		return;
	}

	snap = self.bpg_undo;
	self.bpg_undo = undefined; // one use per snapshot

	// --- restore (mirrors dev\test.gsc restoreData, minus origin/kills; CLEARS
	//     perks/nades first so purchases made after the snapshot are removed) ---
	self survivor_set_score( int( snap[ "score" ] ) );
	self survivor_set_body_armor( snap[ "armor" ] );

	if ( snap[ "hasRevive" ] )
	{
		if ( !self.hasRevive )
			self survivor_give_last_stand();
	}
	else
	{
		self.hasRevive = false;
		self setClientDvar( "ui_self_revive", 0 );
		self player_give_perk( "specialty_finalstand", false );
	}

	self survivor_clear_perks();
	foreach ( perk in snap[ "perks" ] )
		self survivor_give_perk( perk );

	self player_clear_nades();
	foreach ( grenade, amount in snap[ "grenades" ] )
	{
		if ( amount ) self player_set_nades( grenade, amount );
		if ( grenade == "claymore_mp" ) self player_set_action_slot( 1, "weapon", grenade );
		else if ( grenade == "c4_mp" ) self player_set_action_slot( 5, "weapon", grenade );
	}

	self player_take_all_weapons();
	for ( i = 0; i < 2; i++ )
	{
		if ( !isDefined( snap[ "weaponData" ][ i ] ) )
			continue;
		weapon = snap[ "weaponData" ][ i ][ 0 ];
		self player_give_weapon( weapon, false, false, true );
		self player_set_weapon_data( weapon, snap[ "weaponData" ][ i ] );
		self player_set_ammo_data( weapon, snap[ "ammoData" ][ i ] );
	}

	self.prevWeapon = snap[ "prevWeapon" ];
	if ( isDefined( snap[ "currentWeapon" ] ) && maps\mp\_utility::isKillstreakWeapon( snap[ "currentWeapon" ] ) && isDefined( self.prevWeapon ) )
		self switchToWeaponImmediate( self.prevWeapon );
	else if ( isDefined( snap[ "currentWeapon" ] ) && snap[ "currentWeapon" ] != "none" )
		self switchToWeaponImmediate( snap[ "currentWeapon" ] );

	self tell( "^2Undone ^7- restored to how you were when you opened the buy station" );
	self playLocalSound( "mp_killconfirm_tags_pickup" );
}
