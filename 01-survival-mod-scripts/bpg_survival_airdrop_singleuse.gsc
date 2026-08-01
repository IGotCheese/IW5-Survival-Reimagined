// bpg_survival_airdrop_singleuse.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-16 (v3).
// THE care-package infinite fix. Root cause (confirmed against mod + stock source):
//   The mod does replacefunc(_airdrop::watchairdropmarker, ::_watchairdropmarker), and
//   the mod's _watchairdropmarker loops for(;;) forever, NEVER removing the marker and
//   NEVER ending. Stock's consumption lived in watchairdropweaponchange, which the mod
//   dropped: stock takes maps\mp\killstreaks\_killstreaks::getkillstreakweapon(streakname)
//   — the HELD launcher — on throw. So one purchase = throw the marker forever = infinite
//   crates / red smoke.
//
// My v1/v2 were wrong twice: v1 replaced the mod's own symbol (dead — the active path is
// the stock symbol the mod redirected); v2 replaced the stock symbol but took `weapname`
// (the thrown SMOKE projectile), not the held launcher — so nothing was disarmed.
//
// FIX (no replaceFunc, no ordering race): an independent always-on per-player watcher.
// On each airdrop-marker throw it waits 0.05s (so the mod's loop has already threaded the
// crate for THIS throw), then removes the HELD killstreak weapon exactly like stock and
// notifies "markerDetermined" to end the mod's now-idle loop. One purchase -> one crate;
// a second crate requires re-buying (which the cooldown / wave cap then paces).
// _airdrop + _killstreaks load on every survival map -> the ::function refs always resolve.
// ⚠️ NEVER copy to the live <MP-PORT> server (survival-only assumptions).

#include maps\mp\_utility;
#include maps\mp\killstreaks\_airdrop;
#include maps\mp\killstreaks\_killstreaks;
#include lethalbeats\player;

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	level thread bpg_airdrop_singleuse_connect();
}

bpg_airdrop_singleuse_connect()
{
	level endon( "game_ended" );

	for ( ;; )
	{
		level waittill( "connected", player );

		// Bots never buy airdrops; only real players can trigger the exploit.
		if ( isDefined( player ) && !player isTestClient() )
			player thread bpg_airdrop_singleuse_watch();
	}
}

// One persistent watcher per connected player (survives spawns/downs; ends on disconnect).
bpg_airdrop_singleuse_watch()
{
	self endon( "disconnect" );
	level endon( "game_ended" );

	for ( ;; )
	{
		self waittill( "grenade_fire", grenade, weapname );

		if ( !maps\mp\killstreaks\_airdrop::isairdropmarker( weapname ) )
			continue;

		// Let the mod's watch loop thread the crate activation for THIS throw first.
		// (The crate is threaded on the grenade entity synchronously on the same frame
		//  as this notify; a small wait guarantees ordering before we disarm.)
		wait 0.05;

		// Remove the HELD killstreak marker weapon (stock consumption target) so it
		// can't be re-thrown. weapname is the smoke projectile — NOT what you keep.
		ksWeapon = self bpg_current_airdrop_weapon();
		if ( isDefined( ksWeapon ) && self hasWeapon( ksWeapon ) )
			self takeWeapon( ksWeapon );

		// End the mod's idle for(;;) loop (crate already threaded; safe — see notes).
		self notify( "markerDetermined" );

		// Don't leave the player empty-handed if the engine didn't auto-switch.
		if ( isAlive( self ) && self getCurrentWeapon() == "none" )
		{
			pri = self lethalbeats\player::player_get_primary();
			if ( isDefined( pri ) && pri != "none" && self hasWeapon( pri ) )
				self switchToWeaponImmediate( pri );
		}
	}
}

// Mirrors stock watchairdropweaponchange's target:
// getkillstreakweapon( pers["killstreaks"][killstreakindexweapon].streakname ).
bpg_current_airdrop_weapon()
{
	if ( !isDefined( self.pers[ "killstreaks" ] ) || !isDefined( self.killstreakindexweapon ) )
		return undefined;

	ks = self.pers[ "killstreaks" ][ self.killstreakindexweapon ];
	if ( !isDefined( ks ) || !isDefined( ks.streakname ) )
		return undefined;

	return maps\mp\killstreaks\_killstreaks::getkillstreakweapon( ks.streakname );
}
