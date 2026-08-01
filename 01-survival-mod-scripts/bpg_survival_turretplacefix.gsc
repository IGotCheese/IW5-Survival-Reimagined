// bpg_survival_turretplacefix.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-30.
//
// ✅ ACTIVE — status corrected 2026-08-01. Plain .gsc, no .PENDING sibling, so Plutonium
// loads it. The header claimed it was inert while it was live on the sentry path.
// replaceFuncs a mod function on the sentry path.
// Goes into the same <SIDETEST-PORT> side-test batch as the droppedweapon leak fix and the
// clearUsingRemote guard. Activate by dropping .PENDING.
//
// Fixes FLOATING and TILTED turrets (user screenshot 2026-07-30: a minigun sentry hanging in
// mid-air, pitched nose-down, unattached to any surface).
//
// ── ROOT CAUSE: two separate defects, one on each side of the save/restore ────────────────────
// Turrets are persisted per player and re-spawned by the player-state restore path
// (utility.gsc:1654-1658, iterating playerData["turrets"]).
//
// (1) TILT — lethalbeats\survival\killstreaks\_sentry::sentrySetPlaced, _sentry.gsc:294:
//         turretInfo["angles"] = vector_truncate( self.owner.angles, 3 );
//     That stores the OWNER'S VIEW ANGLES, not the turret's. A player's angles carry PITCH
//     (and can carry roll), so restoring them onto the turret pitches it over. A turret should
//     only ever inherit YAW - it stands upright regardless of where the player was looking.
//
// (2) FLOAT — _sentry.gsc:368-377 spawnSentryAtLocation places at the saved origin verbatim:
//         sentry = spawnTurret( "misc_turret", origin, weaponInfo );
//         sentry.origin = origin;
//     There is NO ground trace. Any saved origin that was not flush with the floor - captured
//     while carried, mid-jump, on geometry that is no longer there, or on a map where the
//     restore lands somewhere else - re-spawns the turret hanging in the air permanently.
//
// ── WHY FIX THE RESTORE SIDE ONLY ────────────────────────────────────────────────────────────
// Sanitising on restore repairs ALREADY-SAVED bad data as well as new saves. Fixing the save
// side alone would leave every existing tilted/floating entry broken and would need both halves
// changed. One replaceFunc on the restore covers everything.
//
// ⚠️ The ground trace runs BEFORE the turret is spawned, deliberately. Tracing after spawn is how
// the standalone dog ended up hovering - its ground trace hit its OWN hitbox and it climbed a bit
// every pass. With nothing spawned yet there is no own-hitbox to hit.
//
// Falls back to the saved origin untouched when the trace hits nothing (fraction >= 1), so a
// turret over a pit or outside the world stays where it was rather than being flung into the
// void. Idempotent for turrets already sitting correctly: tracing down from +32 onto flat ground
// returns the same position.

#include lethalbeats\survival\killstreaks\_sentry;

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( lethalbeats\survival\killstreaks\_sentry::spawnSentryAtLocation, ::bpg_spawnSentryAtLocation_fixed );
}

bpg_spawnSentryAtLocation_fixed( sentryType, origin, angles, owner )
{
	weaponInfo = level.sentrySettings[ sentryType ].weaponInfo;

	// (1) yaw only - discard the owner's pitch/roll that got baked in at save time
	safeAngles = ( 0, 0, 0 );
	if ( isDefined( angles ) )
		safeAngles = ( 0, angles[ 1 ], 0 );

	// (2) drop to the floor. Trace BEFORE spawning - see the own-hitbox note above.
	safeOrigin = origin;
	if ( isDefined( origin ) )
	{
		tr = bulletTrace( origin + ( 0, 0, 32 ), origin - ( 0, 0, 512 ), false, undefined );
		if ( isDefined( tr ) && isDefined( tr[ "position" ] ) && tr[ "fraction" ] < 1 )
			safeOrigin = tr[ "position" ];
	}

	sentry = spawnTurret( "misc_turret", safeOrigin, weaponInfo );
	sentry.origin = safeOrigin;
	sentry.angles = safeAngles;
	sentry sentryInitSentry( sentryType, owner );
	sentry.carriedby = owner;
	sentry.sentrytype = sentryType;
	sentry sentrySetPlaced();
	return sentry;
}
