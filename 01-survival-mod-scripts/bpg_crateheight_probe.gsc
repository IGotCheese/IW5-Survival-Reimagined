// bpg_crateheight_probe.gsc — positionally verifies bpg_survival_armoryfix.gsc's
// bpg_armory_height_fix() actually shifted crates up. Only compile-health was confirmed before;
// this checks the real in-world Z delta between the armory's raw coordinate and where the crate
// model actually ended up. INERT unless bpg_crateheight_probe=1 (side-test cfg only).

init()
{
	if ( getDvarInt( "bpg_crateheight_probe" ) != 1 )
		return;

	level thread bpg_crateheight_probe_run();
}

bpg_crateheight_probe_run()
{
	wait 6; // after armoryfix's own repair (3s) + height-fix (4s) passes

	map = getDvar( "mapname" );
	if ( !isDefined( level.armories ) || !isDefined( level.armories[ map ] ) )
	{
		println( "[CRATEHEIGHT] no level.armories defined for map " + map + " - can't verify here" );
		return;
	}

	models = getEntArray( "script_model", "classname" );
	println( "[CRATEHEIGHT] map=" + map + " armories=" + level.armories[ map ].size + " script_models=" + models.size );

	foreach ( armory in level.armories[ map ] )
	{
		type = armory[ 0 ];
		rawOrigin = armory[ 1 ];

		best = undefined;
		bestDist = 200;
		foreach ( m in models )
		{
			if ( !isDefined( m ) || !isDefined( m.model ) || m.model != "com_plasticcase_friendly" )
				continue;
			d = distance( m.origin, rawOrigin );
			if ( d < bestDist )
			{
				best = m;
				bestDist = d;
			}
		}

		if ( !isDefined( best ) )
		{
			println( "[CRATEHEIGHT] " + type + " @ " + rawOrigin + " -> NO CRATE MODEL FOUND within 200 units" );
			continue;
		}

		deltaZ = best.origin[ 2 ] - rawOrigin[ 2 ];
		fixedFlag = isDefined( best.bpg_height_fixed ) && best.bpg_height_fixed;
		println( "[CRATEHEIGHT] " + type + " raw=" + rawOrigin + " crateOrigin=" + best.origin + " deltaZ=" + deltaZ + " bpg_height_fixed=" + fixedFlag );

		// 2026-07-19: the native spawn already applies origin-(0,0,2) BEFORE our height-fix
		// watcher adds +CRATE_HEIGHT_FIX(14.878) on top of that already-placed crate, so the
		// real expected delta from the RAW armory coordinate is 14.878-2=12.878, not 14.878.
		// (Confirmed live: every armory measured exactly 12.878 - this was a probe calibration
		// bug, not a fix bug; the fix itself was already working correctly.)
		if ( deltaZ > 11.5 && deltaZ < 14.5 )
			println( "[CRATEHEIGHT] PASS(" + type + ") - crate raised by ~12.878 as intended" );
		else
			println( "[CRATEHEIGHT] FAIL(" + type + ") - expected deltaZ ~12.878, got " + deltaZ );
	}
}
