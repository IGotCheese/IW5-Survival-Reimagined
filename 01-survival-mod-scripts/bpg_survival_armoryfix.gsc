// bpg_survival_armoryfix.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-19.
// Investigated a report of "can't use the weapon crate on intersection" (mp_crosswalk_ss).
// ⚠️ 2026-07-19 CORRECTION #1: my FIRST diagnostic pass concluded the armory system was
// completely broken on this map (level.triggers stayed undefined) — that was a FALSE POSITIVE
// caused by my own side-test setup: forcing `+set sv_maprotation "map mp_crosswalk_ss"` silently
// dropped the leading "dsr survival_easy" entry that actually puts the server in survival
// gametype, so the probe ran the map in stock WAR mode, where the survival-only armory init
// correctly does nothing. Re-tested properly (dsr preserved, g_gametype confirmed "survival"):
// the native armory spawn works fine, level.triggers.size=3, a trigger exists at the expected
// coordinate. No real bug in the native spawn path.
// ⚠️ 2026-07-19 CORRECTION #2 (live-reported, REMOVED the repair-watcher entirely): deployed the
// "repair" mechanism anyway as a "safe, proven-no-op-when-unneeded" defensive fallback for maps
// that might genuinely lack a native trigger. That assumption was wrong — a live report showed
// duplicate stacked buy-station crates AND all stations usable from wave 1 (should be wave-gated).
// Root cause: bpg_armory_trigger_exists() only confirmed a trigger existed near the right
// coordinate, never confirmed its exact `.tag` field matched "weapon"/"equipment"/"support" -
// if the native trigger's tag uses a different convention than assumed, the "already exists"
// check always misses, so bpg_armory_repair_watch() spawns a SECOND crate+trigger on top of the
// working native one, every map, every round - and that duplicate trigger has no wave-gating
// (survivor_trigger_filter only, unlike whatever gate the native one has), making everything
// accessible immediately. Since the original "missing armory" report never actually reproduced
// (see CORRECTION #1), there was never a real problem for this mechanism to solve - removed
// entirely rather than trying to fix the tag-matching, since the native path is already proven
// to work correctly on its own.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

#include common_scripts\utility;
#include maps\mp\_utility;
#include lethalbeats\survival\utility;

// 2026-07-19: "all buy stations sit below ground, move them up by half the height of the box."
// Measured the crate model (com_plasticcase_friendly) directly (Blender, exact mesh bounds):
// height = 29.756, and its pivot sits close to the model's vertical CENTER rather than its base
// (minZ=-15.630, maxZ=14.126 relative to origin) — so the native code's `origin - (0,0,2)` sinks
// every crate roughly (2 + half-height) below the intended coordinate. Half-height = 14.878.
#define CRATE_HEIGHT_FIX 14.878

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	level thread bpg_armory_height_fix();
}

// raises every already-spawned armory crate (from the NATIVE spawn path) by the measured
// half-height, so crates sit properly instead of sunk into the ground.
bpg_armory_height_fix()
{
	level endon( "game_ended" );

	wait 4; // let the native _spawn.gsc init + its spawnShop threads finish first

	map = getDvar( "mapname" );
	if ( !isDefined( level.armories[ map ] ) )
		return;

	foreach ( armory in level.armories[ map ] )
	{
		origin = armory[ 1 ];
		crate = bpg_find_crate_near( origin );
		if ( !isDefined( crate ) )
			continue;
		if ( isDefined( crate.bpg_height_fixed ) && crate.bpg_height_fixed )
			continue; // don't double-raise if this thread somehow runs twice for the same crate

		crate.origin = crate.origin + ( 0, 0, CRATE_HEIGHT_FIX );
		crate.bpg_height_fixed = true;
	}
}

// nearest com_plasticcase_friendly script_model within 100 units of an armory's known coordinate
bpg_find_crate_near( origin )
{
	best = undefined;
	bestDist = 100;

	models = getEntArray( "script_model", "classname" );
	foreach ( m in models )
	{
		if ( !isDefined( m ) || !isDefined( m.model ) || m.model != "com_plasticcase_friendly" )
			continue;
		d = distance( m.origin, origin );
		if ( d < bestDist )
		{
			best = m;
			bestDist = d;
		}
	}
	return best;
}
