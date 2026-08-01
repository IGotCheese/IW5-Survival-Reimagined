// bpg_coverfind_probe.gsc — tests whether bpg_find_cover_waypoint's core logic (a copy,
// since the real one is a self/bot-context method inside z_svr_bots.iwd) can actually find
// concealed waypoints on a REAL map with REAL waypoint data, independent of the bot-spawn/
// damage pipeline. Answers: is the "no new movement" report because the hook never fires,
// or because it fires but never finds anywhere to go (always falls back to old strafe())?
// INERT unless bpg_coverfind_probe=1 (side-test cfg only — never set on live).

init()
{
	if ( getDvarInt( "bpg_coverfind_probe" ) != 1 )
		return;

	level thread bpg_coverfind_probe_run();
}

bpg_coverfind_probe_run()
{
	wait 10;

	if ( !isDefined( level.waypoints ) || !level.waypoints.size )
	{
		println( "[COVERPROBE] FAIL no waypoints loaded" );
		return;
	}

	println( "[COVERPROBE] " + level.waypoints.size + " waypoints loaded on " + getDvar( "mapname" ) + ", running 15 sample cover-find tests" );

	found = 0;
	tested = 0;
	totalCandidatesChecked = 0;

	for ( i = 0; i < 15; i++ )
	{
		wpFrom = level.waypoints[ randomint( level.waypoints.size ) ];
		wpTarget = level.waypoints[ randomint( level.waypoints.size ) ];

		if ( !isDefined( wpFrom ) || !isDefined( wpFrom.origin ) || !isDefined( wpTarget ) || !isDefined( wpTarget.origin ) )
			continue;

		dist = distance( wpFrom.origin, wpTarget.origin );

		if ( dist < 300 || dist > 1500 )
			continue;

		tested++;
		result = bpg_coverfind_test( wpFrom.origin, wpTarget.origin, 800 );

		if ( isDefined( result[ "cover" ] ) )
		{
			found++;
			println( "[COVERPROBE] test " + i + " (engageDist=" + int( dist ) + "u, checked=" + result[ "checked" ] + " waypoints in radius): FOUND cover " + int( distance( wpFrom.origin, result[ "cover" ].origin ) ) + "u away" );
		}
		else
		{
			println( "[COVERPROBE] test " + i + " (engageDist=" + int( dist ) + "u, checked=" + result[ "checked" ] + " waypoints in radius): no cover found" );
		}

		totalCandidatesChecked += result[ "checked" ];
	}

	println( "[COVERPROBE] RESULT: " + found + "/" + tested + " sample engagements found nearby cover. avg candidates checked per test=" + ( tested ? ( totalCandidatesChecked / tested ) : 0 ) );

	if ( tested && found == 0 )
		println( "[COVERPROBE] CONCLUSION: cover-find NEVER succeeds from these sample points - explains 'no new movement' (always falling back to strafe())." );
	else if ( tested && found < tested / 3 )
		println( "[COVERPROBE] CONCLUSION: cover-find succeeds rarely - new movement would be infrequent/hard to notice." );
	else if ( tested )
		println( "[COVERPROBE] CONCLUSION: cover-find succeeds often - the movement-choice logic itself is more likely the actual problem, not cover availability." );
}

// exact copy of the real bpg_find_cover_waypoint logic from z_svr_bots.iwd's
// _bot_internal.gsc, minus the self/bot.moveorigin dependency (uses fromOrigin directly).
bpg_coverfind_test( fromOrigin, threatOrigin, radius )
{
	best = undefined;
	bestDist = radius * radius;
	minDist = 150 * 150;
	checked = 0;

	for ( i = 0; i < level.waypoints.size; i++ )
	{
		wp = level.waypoints[ i ];

		if ( !isDefined( wp ) || !isDefined( wp.origin ) )
			continue;

		d = distancesquared( fromOrigin, wp.origin );

		if ( d < minDist || d > bestDist )
			continue;

		checked++;

		if ( bullettracepassed( wp.origin + ( 0, 0, 16 ), threatOrigin, false, undefined ) )
			continue;

		best = wp;
		bestDist = d;
	}

	result = [];
	result[ "cover" ] = best;
	result[ "checked" ] = checked;
	return result;
}
