// bpg_skyprobe.gsc — READ-ONLY diagnostic. INERT unless `set bpg_skyprobe 1`.
// 2026-07-26: user reports UAV/reaper flying outside the map on mp_waw_castle and asks
// to "raise the map ceiling past the height of drones".
//
// Before changing anything, measure. The drone orbit in
// scripts/bpg_survival_uavreaperbounds.gsc is clamped to a fraction of level.mapRadius,
// but that clamp is guarded by `isdefined(level.mapRadius)` - so if a ported map never
// sets it, the clamp silently FAILS OPEN and the stock 6000-7000u orbit is used, which
// on a small map puts the drone well outside the playable volume.
// This prints the real numbers (map metrics + the height the stock and clamped maths
// actually produce) so the fix is chosen from data instead of assumption.
//
// Prints nothing and changes nothing unless the dvar is set. Safe to leave installed.

init()
{
	if ( getDvarInt( "bpg_skyprobe" ) != 1 )
		return;

	level thread bpg_skyprobe_run();
}

bpg_skyprobe_run()
{
	level endon( "game_ended" );

	wait 10; // let survival.gsc / _uav.gsc init finish setting the level vars

	mapname = getDvar( "mapname" );
	println( "[SKYPROBE] ===== " + mapname + " =====" );

	if ( isDefined( level.mapRadius ) )
		println( "[SKYPROBE] level.mapRadius = " + level.mapRadius );
	else
		println( "[SKYPROBE] level.mapRadius = UNDEFINED  <-- orbit clamp FAILS OPEN" );

	if ( isDefined( level.mapCenter ) )
		println( "[SKYPROBE] level.mapCenter = " + level.mapCenter );
	else
		println( "[SKYPROBE] level.mapCenter = UNDEFINED" );

	if ( isDefined( level.uavrig ) )
		println( "[SKYPROBE] uavrig origin  = " + level.uavrig.origin );
	else
		println( "[SKYPROBE] uavrig         = UNDEFINED" );

	// Ground reference: lowest spawn point, i.e. roughly the playable floor.
	if ( isDefined( level.spawnpoints ) )
		spawns = level.spawnpoints;
	else
		spawns = level.startspawnpoints;

	if ( isDefined( spawns ) && spawns.size )
	{
		lowest = spawns[ 0 ];
		highest = spawns[ 0 ];
		for ( i = 0; i < spawns.size; i++ )
		{
			if ( spawns[ i ].origin[ 2 ] < lowest.origin[ 2 ] )  lowest = spawns[ i ];
			if ( spawns[ i ].origin[ 2 ] > highest.origin[ 2 ] ) highest = spawns[ i ];
		}
		println( "[SKYPROBE] spawn Z range  = " + lowest.origin[ 2 ] + " .. " + highest.origin[ 2 ] + "  (" + spawns.size + " spawns)" );

		// How high is the actual ceiling above the playable floor? Trace straight up
		// from the lowest spawn; where it stops is the sky/clip the drones must stay under.
		up = bulletTrace( lowest.origin + ( 0, 0, 32 ), lowest.origin + ( 0, 0, 20000 ), false, undefined );
		if ( up[ "fraction" ] >= 1 )
			println( "[SKYPROBE] ceiling above lowest spawn = NONE HIT within 20000u (open sky)" );
		else
			println( "[SKYPROBE] ceiling above lowest spawn = " + ( up[ "position" ][ 2 ] - lowest.origin[ 2 ] ) + "u  (abs Z " + up[ "position" ][ 2 ] + ")" );
	}
	else
		println( "[SKYPROBE] no spawnpoints found" );

	// Reproduce the orbit maths for both drone types so we can see the height each
	// produces, stock vs clamped, without waiting for a real killstreak to spawn.
	bpg_skyprobe_report_uav();
	bpg_skyprobe_report_reaper();
	bpg_skyprobe_report_clamped();

	println( "[SKYPROBE] ===== end =====" );
}

// Verifies the real altitude clamp in bpg_survival_uavreaperbounds.gsc: feeds it the
// same offsets the stock maths produces and reports the ABSOLUTE Z that results, next
// to the measured ceiling. This is the pass/fail line - final Z must sit below ceiling.
bpg_skyprobe_report_clamped()
{
	if ( !isDefined( level.uavrig ) )
	{
		println( "[SKYPROBE] CLAMP: no uavrig, skipped" );
		return;
	}
	rigZ = level.uavrig.origin[ 2 ];

	ceil = scripts\bpg_survival_uavreaperbounds::bpg_drone_ceiling( 2830 );
	if ( isDefined( ceil ) )
		println( "[SKYPROBE] CLAMP: measured ceiling abs Z = " + ceil );
	else
	{
		println( "[SKYPROBE] CLAMP: open sky (no ceiling) - clamp is a no-op here" );
		return;
	}

	uavDir = vectornormalize( ( 6000, 0, 4000 ) ) * 2830;
	uavOut = scripts\bpg_survival_uavreaperbounds::bpg_clamp_offset_to_ceiling( uavDir, 2830 );
	println( "[SKYPROBE] CLAMP: UAV    abs Z " + ( rigZ + uavDir[ 2 ] ) + " -> " + ( rigZ + uavOut[ 2 ] ) );

	repDir = vectornormalize( ( 6100, 0, 6300 ) ) * 3060;
	repOut = scripts\bpg_survival_uavreaperbounds::bpg_clamp_offset_to_ceiling( repDir, 3060 );
	println( "[SKYPROBE] CLAMP: REAPER abs Z " + ( rigZ + repDir[ 2 ] ) + " -> " + ( rigZ + repOut[ 2 ] ) );
}

bpg_skyprobe_report_uav()
{
	// stock: altitudeOffset 3000-5000, horizontal 5000-7000, orbit 6000-7000
	alt = 4000;          // mid of stock range
	horiz = 6000;        // mid of stock range
	dir = vectornormalize( ( horiz, 0, alt ) );

	stockDist = 6500;    // mid of stock orbit range
	println( "[SKYPROBE] UAV stock   : orbit " + stockDist + "u -> height above rig = " + ( dir[ 2 ] * stockDist ) );

	if ( isDefined( level.mapRadius ) && level.mapRadius > 0 )
	{
		safeMax = int( level.mapRadius * 0.9 );
		if ( safeMax < 7000 )
		{
			clamped = int( ( safeMax + int( safeMax * 0.85 ) ) / 2 );
			println( "[SKYPROBE] UAV clamped : orbit " + clamped + "u -> height above rig = " + ( dir[ 2 ] * clamped ) );
		}
		else
			println( "[SKYPROBE] UAV clamped : NO-OP (map large enough)" );
	}
	else
		println( "[SKYPROBE] UAV clamped : NOT APPLIED (mapRadius undefined)" );
}

bpg_skyprobe_report_reaper()
{
	// stock: zWeight 6300, horizontal 6100, orbit 6100
	dir = vectornormalize( ( 6100, 0, 6300 ) );
	println( "[SKYPROBE] REAPER stock: orbit 6100u -> height above rig = " + ( dir[ 2 ] * 6100 ) );

	if ( isDefined( level.mapRadius ) && level.mapRadius > 0 )
	{
		safeDist = int( level.mapRadius * 0.9 );
		if ( safeDist < 6100 )
			println( "[SKYPROBE] REAPER clamp: orbit " + safeDist + "u -> height above rig = " + ( dir[ 2 ] * safeDist ) );
		else
			println( "[SKYPROBE] REAPER clamp: NO-OP (map large enough)" );
	}
	else
		println( "[SKYPROBE] REAPER clamp: NOT APPLIED (mapRadius undefined)" );
}
