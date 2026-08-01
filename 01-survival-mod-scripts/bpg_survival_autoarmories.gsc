// bpg_survival_autoarmories.gsc — SURVIVAL SERVER ONLY (isolated storage). v5 2026-07-16.
// The mod's survivalMaps.gsc ships armory/jugg coordinates for only 41 maps; on any
// other map armories\_spawn::init() silently spawns NO shops (user hit it on mp_raid).
// HISTORY: v2 = spawn-entity placement via the level.armories table at init (the mod's
// own spawn path; positions players liked). v3 added physics-layer GROUND SNAP (fixes
// shops sunk/floating on custom maps like rust_long) + the spawnShopModel collision
// guard. v4 added terrain quality filters + delayed direct spawning — USER VERDICT:
// "messed the armories up even more" (relocated every map's shops away from the known
// layout). v5 = REVERT to the v2 algorithm exactly, keeping only the two proven fixes:
//   - bpg_ground_snap on every placement (playerPhysicsTrace + getGroundPosition —
//     bullet clip is the WRONG layer on custom maps)
//   - spawnShopModel replaceFunc guard (missing care_package brush on custom maps
//     killed the spawn thread mid-way -> broken/invisible shops)
// Table is filled at init SYNCHRONOUSLY (the mod's _spawn::init reads it one frame
// later via waittillframeend). Waypoint fallback stays delayed+direct for maps with
// too few spawn entities (tunisia). Hand-made entries always win.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	// missing "care_package" brush on many custom maps kills spawnShopModel at the
	// collision clone -> guard it (shop stays functional, crate non-solid there)
	replaceFunc( lethalbeats\survival\armories\_spawn::spawnShopModel, ::bpg_spawnshopmodel_safe );

	map = getDvar( "mapname" );

	if ( !isDefined( level.armories ) )
		level.armories = [];

	// bpg 2026-07-17: mp_fnrp_futurama_v3's zombie-escape spawn points push the
	// auto-placed shops out of the map boundary. Pin 3 shops to spread, player-
	// walkable waypoint origins instead (HAND-MADE wins over spawn placement).
	if ( map == "mp_fnrp_futurama_v3" && !isDefined( level.armories[ map ] ) )
	{
		level.armories[ map ] = [];
		level.armories[ map ][ 0 ] = [ "weapon",    ( -44.9, 231.4, -39.9 ),   ( 0, 0, 0 ) ];
		level.armories[ map ][ 1 ] = [ "equipment", ( -96.7, 1567, -39.9 ),    ( 0, 0, 0 ) ];
		level.armories[ map ][ 2 ] = [ "support",   ( -452.5, 2814.8, -47.9 ), ( 0, 0, 0 ) ];
	}

	// Waypoint-derived armory placements for 85 maps used to live here. Baked into
	// survivalMaps.gsc on 2026-08-01 so they are plain data in the stock table alongside
	// the original 43, rather than script logic in this file. The isDefined check below
	// picks them up exactly the same way. Auto-placement remains only as the fallback for
	// maps in NEITHER table (currently just mp_overgrown, which has no waypoint pack).

	spawns = bpg_gather_spawns();

	// audit bookkeeping (published via the bpg_audit dvar for the rcon-based map
	// audit — the shared console.log can't be parsed with two writer processes)
	level.bpg_verdict = "PENDING";
	level.bpg_src_wp = 0;
	level.bpg_src_snap = 0;
	level.bpg_zfix = 0;
	level thread bpg_audit_report( map );

	if ( isDefined( level.armories[ map ] ) )
	{
		// quiet 2026-08-01: routine success. Data now lives in survivalMaps.gsc; nothing to report.
		level.bpg_verdict = "HAND-MADE";
	}
	else if ( spawns.size >= 3 )
	{
		picks = bpg_pick_spread_3( spawns );
		level.armories[ map ] = [];
		level.armories[ map ][ 0 ] = [ "weapon", picks[ 0 ].origin, picks[ 0 ].angles ];
		level.armories[ map ][ 1 ] = [ "equipment", picks[ 1 ].origin, picks[ 1 ].angles ];
		level.armories[ map ][ 2 ] = [ "support", picks[ 2 ].origin, picks[ 2 ].angles ];
		println( "bpg_autoarmories: NO TABLE ENTRY for " + map + " - guessing from spawns (add it to survivalMaps.gsc)" );
		level.bpg_verdict = "AUTO-SPAWNS";
	}

	if ( !isDefined( level.juggDrop ) )
		level.juggDrop = [];

	if ( !isDefined( level.juggDrop[ map ] ) && spawns.size )
	{
		level.juggDrop[ map ] = [];
		stride = int( spawns.size / 5 );
		if ( stride < 1 )
			stride = 1;
		for ( i = 0; i < spawns.size && level.juggDrop[ map ].size < 5; i += stride )
			level.juggDrop[ map ][ level.juggDrop[ map ].size ] = bpg_jugg_point( spawns[ i ].origin );
	}

	level thread bpg_late_fallback( map );
}

// If neither hand-made nor spawn-based placement happened, place shops directly
// from Bot Warfare waypoints using the mod's own spawnShop (waypoints load late,
// hence the delay; this path is only for maps with too few spawn entities).
bpg_late_fallback( map )
{
	level endon( "game_ended" );
	wait 0.5;

	if ( isDefined( level.armories[ map ] ) )
		return;

	if ( !isDefined( level.waypoints ) || level.waypoints.size < 3 )
	{
		println( "bpg_autoarmories: FAILED - no placement source on " + map );
		level.bpg_verdict = "FAILED";
		return;
	}

	picks = bpg_pick_spread_3( level.waypoints );

	level.armories[ map ] = [];
	level.armories[ map ][ 0 ] = [ "weapon", picks[ 0 ].origin, ( 0, 0, 0 ) ];
	level.armories[ map ][ 1 ] = [ "equipment", picks[ 1 ].origin, ( 0, 0, 0 ) ];
	level.armories[ map ][ 2 ] = [ "support", picks[ 2 ].origin, ( 0, 0, 0 ) ];

	level thread lethalbeats\survival\armories\_spawn::spawnShop( "weapon", picks[ 0 ].origin, ( 0, 0, 0 ) );
	level thread lethalbeats\survival\armories\_spawn::spawnShop( "equipment", picks[ 1 ].origin, ( 0, 0, 0 ) );
	level thread lethalbeats\survival\armories\_spawn::spawnShop( "support", picks[ 2 ].origin, ( 0, 0, 0 ) );
	level.bpg_verdict = "AUTO-WPS";

	if ( !isDefined( level.juggDrop[ map ] ) || !level.juggDrop[ map ].size )
	{
		level.juggDrop[ map ] = [];
		stride = int( level.waypoints.size / 5 );
		if ( stride < 1 )
			stride = 1;
		for ( i = 0; i < level.waypoints.size && level.juggDrop[ map ].size < 5; i += stride )
			level.juggDrop[ map ][ level.juggDrop[ map ].size ] = level.waypoints[ i ].origin;
	}

	println( "bpg_autoarmories: NO TABLE ENTRY for " + map + " - guessing from waypoints (add it to survivalMaps.gsc)" );
}

// Byte-for-byte copy of _spawn::spawnShopModel with the collision clone guarded.
// v7: every spawned crate is registered and a one-shot corrector re-seats its
// HEIGHT on waypoint ground truth once waypoints have loaded (they load after the
// armory table is read, so init-time placement can't use them on the main path).
bpg_spawnshopmodel_safe( origin, angles )
{
	if ( !isDefined( angles ) ) angles = ( 0, 0, 0 );

	crate = spawn( "script_model", ( 0, 0, 0 ) );
	crate setModel( "com_plasticcase_friendly" );
	if ( isDefined( level.airDropCrateCollision ) )
		crate CloneBrushmodelToScriptmodel( level.airDropCrateCollision );
	else
		println( "bpg_autoarmories: no care_package collision brush on " + getDvar( "mapname" ) + " - shop crate non-solid" );
	crate.angles = ( 0, 0, 0 );

	laptop = spawn( "script_model", ( 0, 0, 14 ) );
	laptop setModel( "com_laptop_2_close" );
	laptop.angles = ( 0, 90, 0 );
	laptop linkTo( crate );

	crate.origin = origin - ( 0, 0, 2 );
	crate.angles = angles;

	if ( !isDefined( level.bpg_shopcrates ) )
	{
		level.bpg_shopcrates = [];
		level thread bpg_crate_zfix();
	}
	level.bpg_shopcrates[ level.bpg_shopcrates.size ] = crate;

	return [ crate, laptop ];
}

// One-shot: once waypoints exist, re-seat every shop crate's z on the nearest
// waypoint (player-validated standing surface). XY untouched — stays aligned with
// the mod's use-trigger. Trace-based z survives only where no waypoint is near.
bpg_crate_zfix()
{
	level endon( "game_ended" );

	for ( t = 0; t < 24; t++ )
	{
		wait 0.5;
		if ( isDefined( level.waypoints ) && level.waypoints.size > 0 )
			break;
	}
	if ( !isDefined( level.waypoints ) || level.waypoints.size <= 0 )
		return;

	for ( i = 0; i < level.bpg_shopcrates.size; i++ )
	{
		crate = level.bpg_shopcrates[ i ];
		if ( !isDefined( crate ) )
			continue;

		wp = bpg_nearest_wp( crate.origin );
		if ( !isDefined( wp ) || distance( wp.origin, crate.origin ) > 400 )
			continue;

		newz = wp.origin[ 2 ] - 2;
		dz = newz - crate.origin[ 2 ];
		if ( dz > 3 || dz < -3 )
		{
			crate.origin = ( crate.origin[ 0 ], crate.origin[ 1 ], newz );
			// quiet 2026-08-01: routine ground-snap, 3x per map.
			if ( isDefined( level.bpg_zfix ) )
				level.bpg_zfix++;
		}
	}
}

// Publishes the placement outcome in a dvar so the map audit can read it via rcon
// (the shared console.log is unusable with the live server writing to it too).
// Format: <map>|<verdict>|wp=N,snap=N,zfix=N
bpg_audit_report( map )
{
	level endon( "game_ended" );

	wait 6; // after late_fallback (0.5s) and the crate zfix pass (~2-4s)

	setDvar( "bpg_audit", map + "|" + level.bpg_verdict
		+ "|wp=" + level.bpg_src_wp
		+ ",snap=" + level.bpg_src_snap
		+ ",zfix=" + level.bpg_zfix );
}

bpg_gather_spawns()
{
	spawns = [];
	classnames = [];
	classnames[ 0 ] = "mp_tdm_spawn";
	classnames[ 1 ] = "mp_dm_spawn";
	classnames[ 2 ] = "mp_dom_spawn";
	classnames[ 3 ] = "mp_sab_spawn_allies_start";
	classnames[ 4 ] = "mp_sab_spawn_axis_start";
	classnames[ 5 ] = "mp_ctf_spawn_allies";
	classnames[ 6 ] = "mp_ctf_spawn_axis";
	classnames[ 7 ] = "mp_sd_spawn_attacker";
	classnames[ 8 ] = "mp_sd_spawn_defender";

	for ( c = 0; c < classnames.size; c++ )
	{
		ents = getEntArray( classnames[ c ], "classname" );
		for ( i = 0; i < ents.size; i++ )
			spawns[ spawns.size ] = ents[ i ];
		if ( spawns.size >= 3 && c >= 2 )
			break; // tdm+dm+dom pooled; deeper fallbacks only if still short
	}

	return spawns;
}

// Pick 3 maximally spread entries (objects with .origin; .angles optional).
bpg_pick_spread_3( pool )
{
	bi = 0;
	bj = 1;
	best = 0;
	for ( i = 0; i < pool.size; i++ )
	{
		for ( j = i + 1; j < pool.size; j++ )
		{
			d = distanceSquared( pool[ i ].origin, pool[ j ].origin );
			if ( d > best )
			{
				best = d;
				bi = i;
				bj = j;
			}
		}
	}

	bk = undefined;
	best = 0;
	for ( k = 0; k < pool.size; k++ )
	{
		if ( k == bi || k == bj )
			continue;
		d1 = distanceSquared( pool[ k ].origin, pool[ bi ].origin );
		d2 = distanceSquared( pool[ k ].origin, pool[ bj ].origin );
		dmin = d1;
		if ( d2 < dmin )
			dmin = d2;
		if ( dmin > best )
		{
			best = dmin;
			bk = k;
		}
	}
	if ( !isDefined( bk ) )
		bk = 0;

	picks = [];
	picks[ 0 ] = bpg_pick_entry( pool[ bi ] );
	picks[ 1 ] = bpg_pick_entry( pool[ bj ] );
	picks[ 2 ] = bpg_pick_entry( pool[ bk ] );
	return picks;
}

// v7 2026-07-16 — USER INSIGHT: "on certain custom maps the ground isn't actually
// the ground" — BOTH trace layers (visual + physics clip) lie on some ports, so no
// trace-based snap can ever be right there. Bot WAYPOINTS are recorded from a player
// physically walking the map: their z IS the effective standing surface. Anchor each
// shop to the NEAREST WAYPOINT's exact origin (player-validated ground truth); the
// trace snap survives only as a fallback for the rare pick with no waypoint nearby.
bpg_pick_entry( e )
{
	s = spawnStruct();

	wp = bpg_nearest_wp( e.origin );
	if ( isDefined( wp ) && distance( wp.origin, e.origin ) < 400 )
	{
		s.origin = wp.origin;
		// quiet 2026-08-01: routine ground-snap.
		if ( isDefined( level.bpg_src_wp ) )
			level.bpg_src_wp++;
	}
	else
	{
		s.origin = bpg_ground_snap( e.origin, true );
		if ( isDefined( level.bpg_src_snap ) )
			level.bpg_src_snap++;
	}

	if ( isDefined( e.angles ) )
		s.angles = e.angles;
	else
		s.angles = ( 0, 0, 0 );
	return s;
}

// Jugg drop points: waypoint ground truth when available (they aren't at init on
// the spawn path — snap fallback covers that; precision matters less for drops).
bpg_jugg_point( org )
{
	wp = bpg_nearest_wp( org );
	if ( isDefined( wp ) && distance( wp.origin, org ) < 400 )
		return wp.origin;
	return bpg_ground_snap( org );
}

bpg_nearest_wp( org )
{
	if ( !isDefined( level.waypoints ) || level.waypoints.size <= 0 )
		return undefined;

	best = undefined;
	bestDist = 999999;
	for ( i = 0; i < level.waypoints.size; i++ )
	{
		wp = level.waypoints[ i ];
		if ( !isDefined( wp ) || !isDefined( wp.origin ) )
			continue;
		d = distance( org, wp.origin );
		if ( d < bestDist )
		{
			bestDist = d;
			best = wp;
		}
	}
	return best;
}

// Snap org to the surface things visibly REST on. v6 2026-07-16 (user: crates
// "still semi submerged in the ground or floating"):
//   v5's flaws: playerPhysicsTrace DRIFTS the XY (slides off ledges -> measured
//   ground isn't under the crate), and getGroundPosition's 30u radius catches
//   nearby walls/props (-> floating) while the walkable-clip layer can sit below
//   the visual floor on custom maps (-> submerged).
//   v6: keep the XY FIXED. Measure the VISUAL surface with a bulletTrace straight
//   down at the exact XY, cross-check against the physics ground, and prefer the
//   visual hit when the two roughly agree (physics-only when bullet hits fluff like
//   foliage far off the walkable layer). Global calibration knob for any constant
//   model-origin bias:  set bpg_shop_zoff <units>  (applies next map load).
// verbose (optional): per-SHOP diagnostic line for the map audit — src=vis/phy,
// visual-vs-physics gap; big gap or missing visual = SUSPECT placement.
bpg_ground_snap( org, verbose )
{
	zoff = 0;
	if ( getDvar( "bpg_shop_zoff" ) != "" )
		zoff = getDvarFloat( "bpg_shop_zoff" );

	// visual floor at the EXACT XY
	bz = undefined;
	trace = bulletTrace( org + ( 0, 0, 80 ), org - ( 0, 0, 2048 ), false, undefined );
	if ( isDefined( trace[ "fraction" ] ) && trace[ "fraction" ] < 1 && isDefined( trace[ "position" ] ) )
		bz = trace[ "position" ][ 2 ];

	// walkable (physics) ground, started at the same XY
	pz = undefined;
	starts = [];
	starts[ 0 ] = 32;
	starts[ 1 ] = 256;
	for ( i = 0; i < starts.size; i++ )
	{
		from = org + ( 0, 0, starts[ i ] );
		pos = playerPhysicsTrace( from, ( org[ 0 ], org[ 1 ], org[ 2 ] - 2048 ), 0, undefined );
		if ( !isDefined( pos ) )
			continue;
		cand = getGroundPosition( pos, 30 )[ 2 ];
		if ( cand <= org[ 2 ] + 160 && cand >= org[ 2 ] - 300 )
		{
			pz = cand;
			break;
		}
	}

	// pick: visual when sane; physics as backstop
	gz = undefined;
	src = "none";
	if ( isDefined( bz ) && bz <= org[ 2 ] + 160 && bz >= org[ 2 ] - 300 )
	{
		if ( !isDefined( pz ) || abs( bz - pz ) <= 40 )
		{
			gz = bz; // visual hit, agrees with (or replaces) physics
			src = "vis";
		}
		else
		{
			gz = pz; // bullet hit fluff far off the walkable layer
			src = "phy";
		}
	}
	else if ( isDefined( pz ) )
	{
		gz = pz;
		src = "phy";
	}

	if ( isDefined( verbose ) )
	{
		gap = "na";
		if ( isDefined( bz ) && isDefined( pz ) )
			gap = abs( bz - pz );
		tag = "SHOP-Z";
		if ( src == "none" || src == "phy" || ( isDefined( bz ) && isDefined( pz ) && abs( bz - pz ) > 24 ) )
			tag = "SUSPECT-SHOP-Z";
			// quiet 2026-08-01: routine placement detail.
	}

	if ( !isDefined( gz ) )
		return org;

	dz = gz - org[ 2 ];
	if ( dz > 4 || dz < -4 )
		// quiet 2026-08-01: routine ground-snap.
	return ( org[ 0 ], org[ 1 ], gz + zoff );
}
