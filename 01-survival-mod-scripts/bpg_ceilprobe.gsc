// bpg_ceilprobe.gsc — SIDE-TEST ONLY drone-ceiling reporter. 2026-07-30.
// User: "make sure the skyblock ceiling is high enough for reapers helos and uavs and
// counter uavs" — asked while adding mp_bo2_town.
//
// INERT unless `set bpg_ceilprobe 1`. Same dvar-gate pattern as every other bpg_*_probe
// in this folder, which matters because this file lives in the LIVE <SURV-PORT-1> instance's
// scripts dir and would otherwise compile into it at the next map change.
//
// WHY A PROBE AND NOT A LOG LINE IN THE REAL CODE: bpg_survival_uavreaperbounds.gsc
// measures the ceiling at runtime (bpg_drone_ceiling, :89) but never prints it, and the
// result lives in level.bpg_droneCeiling — a level var, not a dvar, so rcon cannot read
// it. This replicates that function's algorithm EXACTLY (same 4 radii x 4 bearings, same
// bulletTrace from +32 to +20000, same max-of-hits, same any-open-sky override) and
// prints what the live clamp would compute, without touching the shipped file.
//
// Reading the output: an OPEN SKY verdict is the good one — bpg_clamp_offset_to_ceiling
// returns the offset untouched, so drones orbit at their natural altitude. A finite
// ceiling only matters if it squeezes maxOffsetZ down toward minOffsetZ.

init()
{
	if ( getDvarInt( "bpg_ceilprobe" ) != 1 )
		return;

	level thread bpg_ceilprobe_run();
}

bpg_ceilprobe_run()
{
	level endon( "game_ended" );

	wait 10; // let the rig, spawnpoints and mapRadius exist

	mapName = getDvar( "mapname" );
	println( "BPGCEIL;BEGIN;" + mapName );

	rigZ = 0;
	center = ( 0, 0, 0 );
	if ( isDefined( level.uavrig ) )
	{
		center = level.uavrig.origin;
		rigZ = level.uavrig.origin[ 2 ];
		println( "BPGCEIL;rig;" + center[ 0 ] + ";" + center[ 1 ] + ";" + center[ 2 ] );
	}
	else if ( isDefined( level.mapCenter ) )
	{
		center = level.mapCenter;
		println( "BPGCEIL;mapCenter;" + center[ 0 ] + ";" + center[ 1 ] + ";" + center[ 2 ] );
	}
	else
		println( "BPGCEIL;center;NONE-using-origin" );

	mapRadius = 0;
	if ( isDefined( level.mapRadius ) )
		mapRadius = level.mapRadius;
	println( "BPGCEIL;mapRadius;" + mapRadius );

	// highest spawn -> the clamp's floor (minOffsetZ)
	highestSpawn = 0;
	nSpawn = 0;
	if ( isDefined( level.spawnpoints ) && level.spawnpoints.size )
	{
		nSpawn = level.spawnpoints.size;
		highestSpawn = level.spawnpoints[ 0 ].origin[ 2 ];
		for ( i = 0; i < level.spawnpoints.size; i++ )
		{
			if ( level.spawnpoints[ i ].origin[ 2 ] > highestSpawn )
				highestSpawn = level.spawnpoints[ i ].origin[ 2 ];
		}
	}
	println( "BPGCEIL;spawns;" + nSpawn + ";highestZ;" + highestSpawn );

	// The two orbit radii the shipped code actually uses:
	//   reaper/UAV  : randomintrange(6000,7000), capped to mapRadius*0.85
	//   counter-UAV : 6100, capped to mapRadius*0.9
	radii = [];
	radii[ 0 ] = 6500;   // representative reaper/UAV orbit
	radii[ 1 ] = 6100;   // counter-UAV orbit
	if ( mapRadius > 0 )
	{
		safe = int( mapRadius * 0.85 );
		if ( safe < radii[ 0 ] && safe >= 500 )
			radii[ 0 ] = safe;
		safe2 = int( mapRadius * 0.9 );
		if ( safe2 < radii[ 1 ] && safe2 >= 500 )
			radii[ 1 ] = safe2;
	}

	for ( k = 0; k < radii.size; k++ )
		bpg_ceilprobe_measure( center, rigZ, highestSpawn, radii[ k ] );

	println( "BPGCEIL;END;" + mapName );
}

// Exact replica of bpg_survival_uavreaperbounds::bpg_drone_ceiling(), plus reporting.
bpg_ceilprobe_measure( center, rigZ, highestSpawn, radius )
{
	println( "BPGCEIL;radius;" + radius );

	highest = undefined;
	anyOpenSky = false;
	hits = 0;
	opens = 0;

	sub = [];
	sub[ 0 ] = 0;
	sub[ 1 ] = int( radius * 0.35 );
	sub[ 2 ] = int( radius * 0.7 );
	sub[ 3 ] = radius;

	for ( r = 0; r < sub.size; r++ )
	{
		step = 90;
		if ( sub[ r ] == 0 )
			step = 360;

		for ( a = 0; a < 360; a += step )
		{
			p = center + ( cos( a ) * sub[ r ], sin( a ) * sub[ r ], 0 );
			tr = bulletTrace( p + ( 0, 0, 32 ), p + ( 0, 0, 20000 ), false, undefined );

			if ( tr[ "fraction" ] >= 1 )
			{
				anyOpenSky = true;
				opens++;
				println( "BPGCEIL;sample;" + sub[ r ] + ";" + a + ";OPEN" );
				continue;
			}

			hits++;
			z = tr[ "position" ][ 2 ];
			println( "BPGCEIL;sample;" + sub[ r ] + ";" + a + ";" + z );
			if ( !isDefined( highest ) || z > highest )
				highest = z;
		}
	}

	println( "BPGCEIL;tally;radius;" + radius + ";hits;" + hits + ";openSky;" + opens );

	if ( anyOpenSky )
	{
		println( "BPGCEIL;VERDICT;" + radius + ";OPEN_SKY;no clamp applied - drones fly at natural altitude" );
		return;
	}

	// finite ceiling -> reproduce the clamp arithmetic
	maxOffsetZ = highest - 192 - rigZ;
	minOffsetZ = 400;
	if ( highestSpawn != 0 )
		minOffsetZ = ( highestSpawn - rigZ ) + 400;

	squeezed = 0;
	if ( maxOffsetZ < minOffsetZ )
		squeezed = 1;

	println( "BPGCEIL;VERDICT;" + radius + ";CEILING;" + highest + ";maxOffsetZ;" + maxOffsetZ + ";minOffsetZ;" + minOffsetZ + ";squeezed;" + squeezed );
}
