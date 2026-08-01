// bpg_survival_turretlistprune.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-29.
// SECONDARY (optional) fix for the level.turrets slot leak.
//
// WHY: the mod's lethalbeats\Survival\killstreaks\_sentry.gsc::sentrySetPlaced() registers
// EVERY sentry type unconditionally:  level.turrets[self getentitynumber()] = self;
// The only removal is stock maps\mp\killstreaks\_autosentry.gsc::sentry_setinactive()
// (reached from sentry_handledeath), and its switch SKIPS removefromturretlist() for
// "gl_turret". In stock that asymmetry is harmless because sentry_setactive() never ADDS
// gl_turret/minigun_turret in the first place; the mod broke that symmetry. So every
// GL turret bought from the air-support armory leaves a dead level.turrets slot for the
// rest of the match. Consequences: botHandler.gsc:121 gates bot sentries on
// `level.turrets.size < 6`, so bots permanently stop taking sentries once 6 dead slots
// accumulate, and maps\mp\gametypes\_spawnlogic.gsc:1167 walks the stale slots on every
// spawn-point evaluation.
//
// REPLACEFUNC-CONFLICT CHECK: _sentry.gsc's own init() replaceFuncs the STOCK symbols
// (_autosentry::sentry_initSentry / sentry_setplaced / init) — per the "mod beats loose"
// ordering finding a loose script cannot win those. This file instead claims the MOD's own
// onSentryDeath, which nothing else in this tree claims.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

#include common_scripts\utility;

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( lethalbeats\survival\killstreaks\_sentry::onSentryDeath, ::bpg_onSentryDeath );
}

bpg_onSentryDeath()
{
	level endon( "game_ended" );
	sentryID = self getentitynumber();
	self waittill_any( "death", "deleting" );

	if ( isdefined( self.owner ) && isdefined( self.owner.turrets ) )
		self.owner.turrets = lethalbeats\array::array_remove_key( self.owner.turrets, sentryID + "" );

	level.sentry--;

	// BPG: the missing half of sentrySetPlaced()'s `level.turrets[sentryID] = self`.
	// A no-op for the types stock already removes; closes the gl_turret slot leak.
	level.turrets[ sentryID ] = undefined;
}
