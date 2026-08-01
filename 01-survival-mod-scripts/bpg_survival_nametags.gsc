// yourserver.gg 2026-07-17 (v2) — overhead teammate gamertags: RED, default size, STATIC
// (no scaling with distance), readable at any range.
// v1 tried to draw names THROUGH walls via the objective-marker system, but those
// shaders render as big "CAPTURE" shields (user screenshot) - removed entirely.
// Overhead name TEXT is engine-rendered and LOS-gated; it can't be drawn through
// walls from GSC, but its size/scale/glow ARE controllable via the viewer's
// cg_overheadNames* client dvars (confirmed live: an earlier Size=1.8 test visibly
// enlarged them). We set them on every client so everyone sees all teammate names
// the same way. NOTE: if any v1 objective markers linger, they clear on map change.

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	level thread bpg_names_watch();
}

bpg_names_watch()
{
	for ( ;; )
	{
		level waittill( "connected", player );
		player thread bpg_names_apply();
	}
}

bpg_names_apply()
{
	self endon( "disconnect" );

	self waittill( "begin" );   // client is fully in
	wait 1;

	bpg_names_set( self );

	// re-assert on each spawn in case anything resets them
	for ( ;; )
	{
		self waittill( "spawned_player" );
		bpg_names_set( self );
	}
}

bpg_names_set( p )
{
	// default size (NOT enlarged) + no distance shrink (static) + visible at any range
	p setClientDvar( "cg_overheadNamesSize", "0.5" );
	p setClientDvar( "cg_overheadNamesNearDist", "100" );
	p setClientDvar( "cg_overheadNamesFarDist", "50000" );
	p setClientDvar( "cg_overheadNamesMaxDist", "50000" );
	p setClientDvar( "cg_overheadNamesFarScale", "1.0" );
	p setClientDvar( "cg_overheadNamesGlow", "1 0 0 1" ); // red glow (tints glow only)
	// RED name text via plugin bpg_setname DISABLED 2026-07-17 for stability (plugin loads
	// unreliably under CPU contention). Re-enable when the box's respawning stray-process is fixed.
}
