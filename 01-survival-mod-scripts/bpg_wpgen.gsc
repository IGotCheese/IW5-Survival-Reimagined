// bpg_wpgen.gsc — HEADLESS WAYPOINT DENSIFIER (side-test tool, survival storage).
// INERT unless the dvar is set: rcon set bpg_wpgen 1 -> then load/restart the target
// map on the <SIDETEST-PORT> side-test. Takes the map's existing waypoints as seeds (or spawn
// points if none), subdivides long links, grid-expands outward with trace-validated
// ground + clearance + void checks, then writes waypoints/<mapname>_wp.csv via Bot
// Warfare's own file builtin. Bot Warfare's loader PREFERS that CSV over the compiled
// wps_*.gsc script, so the result goes live automatically at the map's next load.
// Never set bpg_wpgen on a populated server: the generation pass costs ~10-20k traces.

init()
{
	if ( getDvarInt( "bpg_wpgen" ) != 1 )
		return;

	level thread bpg_wpgen_run();
}

bpg_wpgen_run()
{
	level endon( "game_ended" );

	wait 8; // let Bot Warfare's load_waypoints populate level.waypoints first

	println( "bpg_wpgen: starting on " + getDvar( "mapname" ) );

	// bpg 2026-07-27: maxTotal was hardcoded at 500 and big maps hit it with the far side
	// still uncovered - mp_crossfire's first pass stopped at X 3088..6595 having consumed the
	// whole budget, and several shipped sets (melee_resort, burgundy, crash, highrise_sh) sit
	// at exactly 500, i.e. they were truncated too. Tunable per run via bpg_wpgen_max; 500
	// remains the default so nothing changes unless the dvar is set. mp_bloc_2 already ships
	// 622 nodes in production, so above-500 graphs are proven fine for Bot Warfare's pathing.
	maxTotal = 500;
	if ( getDvarInt( "bpg_wpgen_max" ) > 0 )
		maxTotal = getDvarInt( "bpg_wpgen_max" );
	step = 144;
	linkMax = 240;

	// ── working copy of the existing graph ──────────────────────────────────
	wps = [];
	if ( isDefined( level.waypoints ) && level.waypoints.size )
	{
		for ( i = 0; i < level.waypoints.size; i++ )
		{
			s = spawnStruct();
			s.origin = level.waypoints[ i ].origin;
			s.type = "stand";
			if ( isDefined( level.waypoints[ i ].type ) )
				s.type = level.waypoints[ i ].type;
			s.children = [];
			if ( isDefined( level.waypoints[ i ].children ) )
			{
				for ( h = 0; h < level.waypoints[ i ].children.size; h++ )
					s.children[ s.children.size ] = level.waypoints[ i ].children[ h ];
			}
			wps[ wps.size ] = s;
		}
	}
	else
	{
		spawns = getEntArray( "mp_tdm_spawn", "classname" );
		if ( !spawns.size ) spawns = getEntArray( "mp_dm_spawn", "classname" );
		for ( i = 0; i < spawns.size; i++ )
		{
			g = bpg_ground_at( spawns[ i ].origin );
			if ( !isDefined( g ) ) continue;
			s = spawnStruct();
			s.origin = g;
			s.type = "stand";
			s.children = [];
			wps[ wps.size ] = s;
		}
	}

	seedCount = wps.size;
	println( "bpg_wpgen: seeds = " + seedCount );
	if ( !seedCount )
	{
		println( "bpg_wpgen: ABORT - no seeds" );
		return;
	}

	// ── pass 0: heal existing seed links (bots getting caught on obstacles = a
	//    pre-existing graph edge cuts through a wall/prop with no real sightline;
	//    wpgen previously copied the seed graph as-is without validating it).
	//    Only prune on an actual obstacle signal (blocked sightline, or a void
	//    under a long link) - do NOT reuse bpg_can_link's tight 260u/48u caps
	//    here, those would also prune long-but-clear corridors that are fine.
	toUnlink = [];
	for ( i = 0; i < seedCount; i++ )
	{
		for ( h = 0; h < wps[ i ].children.size; h++ )
		{
			c = wps[ i ].children[ h ];
			if ( c <= i || c >= wps.size ) continue; // each pair once, sane index
			budget += 4;
			if ( budget > 24 ) { budget = 0; wait 0.05; }
			if ( !bpg_link_is_healthy( wps[ i ].origin, wps[ c ].origin ) )
			{
				pair = spawnStruct();
				pair.a = i;
				pair.b = c;
				toUnlink[ toUnlink.size ] = pair;
			}
		}
	}
	for ( k = 0; k < toUnlink.size; k++ )
		bpg_unlink( wps, toUnlink[ k ].a, toUnlink[ k ].b );
	println( "bpg_wpgen: pass0 healed (pruned obstacle-crossing) links = " + toUnlink.size );

	// ── pass 1: subdivide long existing links ───────────────────────────────
	added = 0;
	budget = 0;
	for ( i = 0; i < seedCount; i++ )
	{
		for ( h = 0; h < wps[ i ].children.size; h++ )
		{
			c = wps[ i ].children[ h ];
			if ( c <= i || c >= wps.size ) continue; // each pair once, sane index
			if ( distance( wps[ i ].origin, wps[ c ].origin ) < 260 ) continue;

			mid = ( wps[ i ].origin + wps[ c ].origin ) * 0.5;
			g = bpg_ground_at( mid );
			budget += 2;
			if ( budget > 24 ) { budget = 0; wait 0.05; }
			if ( !isDefined( g ) ) continue;
			if ( isDefined( bpg_find_near( wps, g, 80 ) ) ) continue;
			if ( !bpg_can_link( wps[ i ].origin, g ) || !bpg_can_link( g, wps[ c ].origin ) ) continue;

			s = spawnStruct();
			s.origin = g;
			s.type = "stand";
			s.children = [];
			wps[ wps.size ] = s;
			n = wps.size - 1;
			bpg_link( wps, i, n );
			bpg_link( wps, c, n );
			added++;
		}
	}
	println( "bpg_wpgen: pass1 midpoints added = " + added );

	// ── pass 2: outward grid expansion (BFS) ────────────────────────────────
	dirs = [];
	dirs[ 0 ] = ( step, 0, 0 );
	dirs[ 1 ] = ( 0, step, 0 );
	dirs[ 2 ] = ( 0 - step, 0, 0 );
	dirs[ 3 ] = ( 0, 0 - step, 0 );
	dirs[ 4 ] = ( 102, 102, 0 );
	dirs[ 5 ] = ( 102, 0 - 102, 0 );
	dirs[ 6 ] = ( 0 - 102, 102, 0 );
	dirs[ 7 ] = ( 0 - 102, 0 - 102, 0 );

	head = 0;
	queue = [];
	for ( i = 0; i < wps.size; i++ )
		queue[ queue.size ] = i;

	while ( head < queue.size && wps.size < maxTotal )
	{
		idx = queue[ head ];
		head++;

		for ( d = 0; d < dirs.size; d++ )
		{
			if ( wps.size >= maxTotal )
				break;

			g = bpg_ground_at( wps[ idx ].origin + dirs[ d ] );
			budget += 1;
			if ( budget > 24 ) { budget = 0; wait 0.05; }
			if ( !isDefined( g ) ) continue;
			if ( isDefined( bpg_find_near( wps, g, 90 ) ) ) continue;
			if ( !bpg_can_link( wps[ idx ].origin, g ) ) continue;
			budget += 4;

			s = spawnStruct();
			s.origin = g;
			s.type = "stand";
			s.children = [];
			wps[ wps.size ] = s;
			n = wps.size - 1;
			bpg_link( wps, idx, n );
			queue[ queue.size ] = n;
		}
	}
	println( "bpg_wpgen: pass2 total = " + wps.size );

	// ── pass 3: cross-link new nodes to nearby visible nodes ────────────────
	for ( i = seedCount; i < wps.size; i++ )
	{
		links = wps[ i ].children.size;
		for ( j = 0; j < wps.size && links < 4; j++ )
		{
			if ( j == i ) continue;
			if ( bpg_has_child( wps[ i ], j ) ) continue;
			if ( distance( wps[ i ].origin, wps[ j ].origin ) > linkMax ) continue;
			budget += 4;
			if ( budget > 24 ) { budget = 0; wait 0.05; }
			if ( !bpg_can_link( wps[ i ].origin, wps[ j ].origin ) ) continue;
			bpg_link( wps, i, j );
			links++;
		}
	}

	// ── dump to CONSOLE for harvesting (Plutonium's bots adapter has STUB file
	//    builtins — do_filewrite is a no-op — so console.log is the only channel).
	//    Format per line: BPGWP;index;x y z;child child child;type
	println( "BPGWPBEGIN;" + getDvar( "mapname" ) + ";" + wps.size );

	for ( i = 0; i < wps.size; i++ )
	{
		str = "BPGWP;" + i + ";" + wps[ i ].origin[ 0 ] + " " + wps[ i ].origin[ 1 ] + " " + wps[ i ].origin[ 2 ] + ";";
		for ( h = 0; h < wps[ i ].children.size; h++ )
		{
			str += wps[ i ].children[ h ];
			if ( h < wps[ i ].children.size - 1 )
				str += " ";
		}
		str += ";" + wps[ i ].type;
		println( str );
		if ( i % 40 == 0 )
			wait 0.05; // don't flood the console buffer in one frame
	}

	println( "BPGWPEND;" + wps.size );
	println( "bpg_wpgen: DONE - dumped " + wps.size + " waypoints to console" );
}

// Snap a position to walkable ground; undefined if none / too steep.
bpg_ground_at( pos )
{
	tr = bulletTrace( pos + ( 0, 0, 60 ), pos - ( 0, 0, 400 ), false, undefined );
	if ( tr[ "fraction" ] >= 1 )
		return undefined;
	n = tr[ "normal" ];
	if ( n[ 2 ] < 0.7 )
		return undefined;
	return tr[ "position" ];
}

// Corner-clip check: a straight sightline trace along the exact link centerline
// can read "clear" even when a real bot (which has body width, not a zero-width
// ray) would clip a nearby wall corner while walking that line - this is exactly
// the "bots get stuck on a couple corners" failure mode after the centerline-only
// checks already pruned the obvious cases. Trace two more lines offset sideways
// by a bot-radius-ish amount (18u) on each side of the direct path, both heights.
bpg_corner_clear( a, b )
{
	dir = b - a;
	flat = ( dir[ 0 ], dir[ 1 ], 0 );
	if ( distanceSquared( flat, ( 0, 0, 0 ) ) < 4 )
		return true; // near-vertical link (e.g. ladder-ish) - no meaningful sideways corner to clip

	// bpg 2026-07-30: made tunable via bpg_wpgen_corner. 18 stays the default so every
	// previously-generated graph is reproducible, but 18 is NARROWER than a real IW5 player
	// bounding box (~30u across), so a link can pass this check and still let a bot clip the
	// corner it walks past - the reported "lots of bots getting stuck" on mp_bo2_town, a map
	// dense with cars, fences and doorframes. Raising it to ~28 traces closer to the volume the
	// bot actually occupies. Trade-off: too high prunes legitimate doorways and can disconnect
	// the graph, so check the orphan count after regenerating, not just the node count.
	cornerR = 18;
	if ( getDvarInt( "bpg_wpgen_corner" ) > 0 )
		cornerR = getDvarInt( "bpg_wpgen_corner" );

	perp = vectornormalize( ( 0 - flat[ 1 ], flat[ 0 ], 0 ) ) * cornerR;

	if ( !sightTracePassed( a + perp + ( 0, 0, 42 ), b + perp + ( 0, 0, 42 ), false, undefined ) )
		return false;
	if ( !sightTracePassed( a - perp + ( 0, 0, 42 ), b - perp + ( 0, 0, 42 ), false, undefined ) )
		return false;
	if ( !sightTracePassed( a + perp + ( 0, 0, 14 ), b + perp + ( 0, 0, 14 ), false, undefined ) )
		return false;
	if ( !sightTracePassed( a - perp + ( 0, 0, 14 ), b - perp + ( 0, 0, 14 ), false, undefined ) )
		return false;

	return true;
}

// Conservative walkability between two ground points: distance + height delta,
// eye- and foot-level clearance both ways, sideways corner-clip clearance, and a
// mid-point ground check so links never bridge gaps/voids (blocky maps!).
bpg_can_link( a, b )
{
	if ( distance( a, b ) > 260 )
		return false;
	if ( abs( a[ 2 ] - b[ 2 ] ) > 48 )
		return false;
	if ( !sightTracePassed( a + ( 0, 0, 42 ), b + ( 0, 0, 42 ), false, undefined ) )
		return false;
	if ( !sightTracePassed( a + ( 0, 0, 14 ), b + ( 0, 0, 14 ), false, undefined ) )
		return false;
	if ( !bpg_corner_clear( a, b ) )
		return false;

	mg = bpg_ground_at( ( a + b ) * 0.5 );
	if ( !isDefined( mg ) )
		return false;
	if ( abs( mg[ 2 ] - ( ( a[ 2 ] + b[ 2 ] ) * 0.5 ) ) > 44 )
		return false;

	return true;
}

bpg_find_near( wps, pos, dist )
{
	for ( i = 0; i < wps.size; i++ )
	{
		if ( distance( wps[ i ].origin, pos ) < dist )
			return i;
	}
	return undefined;
}

bpg_has_child( wp, idx )
{
	for ( h = 0; h < wp.children.size; h++ )
	{
		if ( wp.children[ h ] == idx )
			return true;
	}
	return false;
}

bpg_link( wps, a, b )
{
	if ( !bpg_has_child( wps[ a ], b ) )
		wps[ a ].children[ wps[ a ].children.size ] = b;
	if ( !bpg_has_child( wps[ b ], a ) )
		wps[ b ].children[ wps[ b ].children.size ] = a;
}

bpg_unlink( wps, a, b )
{
	newChildren = [];
	for ( h = 0; h < wps[ a ].children.size; h++ )
		if ( wps[ a ].children[ h ] != b )
			newChildren[ newChildren.size ] = wps[ a ].children[ h ];
	wps[ a ].children = newChildren;

	newChildren = [];
	for ( h = 0; h < wps[ b ].children.size; h++ )
		if ( wps[ b ].children[ h ] != a )
			newChildren[ newChildren.size ] = wps[ b ].children[ h ];
	wps[ b ].children = newChildren;
}

// Obstacle-only link validity check for pass 0 (healing pre-existing seed
// links) - deliberately more lenient than bpg_can_link: no distance/height
// caps that would also reject long-but-clear corridors, just "is there
// actually a clear path here."
bpg_link_is_healthy( a, b )
{
	if ( !sightTracePassed( a + ( 0, 0, 42 ), b + ( 0, 0, 42 ), false, undefined ) )
		return false;
	if ( !sightTracePassed( a + ( 0, 0, 14 ), b + ( 0, 0, 14 ), false, undefined ) )
		return false;
	if ( !bpg_corner_clear( a, b ) )
		return false;

	if ( distance( a, b ) > 320 )
	{
		mg = bpg_ground_at( ( a + b ) * 0.5 );
		if ( !isDefined( mg ) )
			return false;
		if ( abs( mg[ 2 ] - ( ( a[ 2 ] + b[ 2 ] ) * 0.5 ) ) > 60 )
			return false;
	}

	return true;
}
