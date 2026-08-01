// bpg_survival_uavreaperbounds.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-23.
// User report: on non-stock (custom) maps, the counter-UAV and reaper (remote_mortar)
// enemy "vehicles" orbit outside the map's actual play volume / invisible collision wall,
// making them impossible to target — roughly twice the distance a pavelow/littlebird ever
// operates at.
//
// ROOT CAUSE (verified against public decompile, github.com/SkyN9ne/Plutonium-IW5-GSC, and
// RawFiles — these two stock functions are UNTOUCHED by the survival mod itself, which
// only replaceFunc's OTHER sub-functions in the same files, see conflict note below):
//   * maps\mp\killstreaks\_uav.gsc::launchuav() links every uav-type model (regular uav,
//     double/triple uav, counter-uav) to level.uavrig at a flat, hardcoded
//     randomintrange(6000, 7000) unit 3D distance from map center, no matter the map.
//   * maps\mp\killstreaks\_remotemortar.gsc::spawnremote() links the reaper drone to the
//     same rig at a flat, hardcoded 6100 unit distance.
//   level.uavrig sits at the map's minimap-corner box center (set in both _uav.gsc's own
//   init() and maps\mp\gametypes\survival.gsc). Stock MP maps are large enough that a
//   6000-7000 unit orbit stays inside the map. maps\mp\gametypes\survival.gsc ALSO computes
//   level.mapRadius = half the distance between the map's two minimap_corner points (or
//   3000 if the map defines none) — the SAME metric the mod's own littlebird/pavelow AI
//   already uses to keep its flight nodes inside the map
//   (lethalbeats\Survival\abilities\_chopper.gsc::_nodeFilter:
//   "distance2D(node.origin, level.mapCenter) < level.mapRadius"). Ported/custom maps are
//   frequently much smaller than the stock 6000-7000 assumption, so the fixed-distance orbit
//   puts the counter-UAV / reaper well past the map's real bounds and its kill-collision
//   wall, out of weapon range entirely.
//
// FIX: byte-for-byte copies of both functions (renamed locals for readability, matching this
// project's existing convention — see bpg_survival_reaperuavfix.gsc), with ONLY the final
// orbit-distance multiplier clamped to a safe fraction of level.mapRadius when the map is
// smaller than stock. On stock/large maps (mapRadius >= ~7780) the clamp never engages and
// behaviour is byte-identical to the original — this cannot regress any map already working
// today. Everything else (uavtype tagging, adduavmodel/removeuavmodel bookkeeping,
// active-uav/counter-uav counters, damagetracker/handledeath threads, wave-relevant bot_kill
// routing) is untouched, so this cannot affect wave-end detection or double-count deaths —
// see bpg_survival_clearwave.gsc's header note for how those are separately verified safe.
//
// 2026-07-23 REPLACEFUNC-CONFLICT CHECK (see gsc-code-quality-practices memory): searched
// both lethalbeats\Survival\killstreaks\_uav.gsc::init() and
// lethalbeats\Survival\abilities\_reaper.gsc::init() — neither replaceFunc's launchuav() or
// spawnremote() (they only touch updateUAVModelVisibility/damageTracker/_getRadarStrength and
// handletimeout/damagetracker/remotefiring/tryuseremotemortar respectively). No other loose
// script in this tree claims these two symbols either. So this file is the ONLY claimant on
// maps\mp\killstreaks\_uav::launchuav and maps\mp\killstreaks\_remotemortar::spawnremote —
// no "mod beats loose" ordering race applies here.
//
// ⚠️ SIDE-TEST before it reaches the live rotation, specifically on a SMALL custom map (to
//    confirm the orbit now stays inside the collision wall) AND a large stock map (to confirm
//    the clamp doesn't engage and nothing regresses there).
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats-adjacent stock killstreak
//    internals this mod depends on being present in this exact form).

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( maps\mp\killstreaks\_uav::launchuav, ::bpg_launchuav_bounded );
	replaceFunc( maps\mp\killstreaks\_remotemortar::spawnremote, ::bpg_spawnremote_bounded );
}

// ─────────────────────────────────────────────────────────────────────────────
// 2026-07-26 ALTITUDE CLAMP (the horizontal clamp above was not enough)
//
// User: "uav and reaper fly outside the map ... raise the map ceiling past the
// height of drones". The ceiling cannot be raised from script - it is baked
// geometry inside each map's compiled .ff, and rebuilding ~130 fastfiles is
// exactly the kind of change that has crashed this server before. So instead of
// raising the roof, we keep the drones under it, measured per map at runtime.
//
// MEASURED on mp_waw_castle (scripts/bpg_skyprobe.gsc, side-test <SIDETEST-PORT>):
//     ceiling absolute Z            = 1600     (uavrig sits at Z 64)
//     UAV    stock   -> abs Z 3670  = 2070u OUTSIDE
//     UAV    h-clamp -> abs Z 1634  =   34u outside   (borderline)
//     REAPER stock   -> abs Z 4446  = 2846u OUTSIDE
//     REAPER h-clamp -> abs Z 2262  =  662u OUTSIDE   <-- still broken
// The existing horizontal clamp scales height only indirectly (the offset vector
// is normalised then scaled), so a steep Z component still punches through the
// roof on small maps. This clamps Z directly against the real ceiling.
//
// Self-calibrating: samples the ceiling by tracing UP at 8 bearings around the
// actual orbit ring and takes the LOWEST hit, so it adapts to every custom map
// with no per-map data and no map edits. Open-sky maps (no hit) are left alone,
// which is why stock maps are unaffected.
// ─────────────────────────────────────────────────────────────────────────────

// Absolute world Z of the lowest ceiling around the orbit ring, or undefined for
// open sky. Cached per level+radius: this is 8 traces, and killstreaks can spawn
// in bursts, so we do not want to redo it on every single launch.
bpg_drone_ceiling( radius )
{
	if ( isDefined( level.bpg_droneCeiling_r ) && level.bpg_droneCeiling_r == radius )
		return level.bpg_droneCeiling;   // may legitimately be undefined = open sky

	center = ( 0, 0, 0 );
	if ( isDefined( level.uavrig ) )
		center = level.uavrig.origin;
	else if ( isDefined( level.mapCenter ) )
		center = level.mapCenter;

	// ⚠️ 2026-07-26 v2, corrected by a 10-map sweep. v1 took the LOWEST hit around the
	// orbit ring, which is wrong on any map with buildings: the ray stops on the first
	// ROOFTOP it meets, not the sky, so the "ceiling" came back far too low and the
	// clamp then fought its own floor. Measured failures:
	//     mp_crash        "ceiling" 352   (a rooftop - Crash is an outdoor map)
	//     mp_bo2nuketown2 "ceiling" -28   (below ground - ray started inside geometry)
	//     mp_killhouse    "ceiling" 477   (reaper ended 32u over)
	// Correct reading is the HIGHEST overhead surface found: the sky/hull is above every
	// building, so max-of-hits approximates the true volume ceiling while rooftops (which
	// a drone should fly OVER) are correctly ignored as the lower samples.
	// Also: if ANY ray reaches 20000u without hitting anything, the map is genuinely open
	// above and no clamp should apply at all - clamping there would drag drones down into
	// a map that never had a roof to begin with.
	// Samples are taken INSIDE the play area (several radii) rather than only out at the
	// orbit ring, because on ported maps the ring can sit outside the map entirely and
	// trace against void/backfaces - this project's standing lesson that traces lie on
	// map ports (see the custom-map-ground-truth memory).
	highest = undefined;
	anyOpenSky = false;

	radii = [];
	radii[ 0 ] = 0;                  // straight up from the rig
	radii[ 1 ] = int( radius * 0.35 );
	radii[ 2 ] = int( radius * 0.7 );
	radii[ 3 ] = radius;

	for ( r = 0; r < radii.size; r++ )
	{
		step = 90;
		if ( radii[ r ] == 0 )
			step = 360;              // one sample at the centre
		for ( a = 0; a < 360; a += step )
		{
			p = center + ( cos( a ) * radii[ r ], sin( a ) * radii[ r ], 0 );
			tr = bulletTrace( p + ( 0, 0, 32 ), p + ( 0, 0, 20000 ), false, undefined );
			if ( tr[ "fraction" ] >= 1 )
			{
				anyOpenSky = true;
				continue;
			}
			z = tr[ "position" ][ 2 ];
			if ( !isDefined( highest ) || z > highest )
				highest = z;
		}
	}

	if ( anyOpenSky )
		highest = undefined;         // open above somewhere -> treat as unbounded

	level.bpg_droneCeiling_r = radius;
	level.bpg_droneCeiling = highest;
	return highest;
}

// Clamp a rig-relative offset vector so the drone sits below the ceiling.
// Only the Z component is touched - the orbit stays the same shape/width, it just
// flies lower. Returns the offset unchanged on open-sky maps.
bpg_clamp_offset_to_ceiling( offset, radius )
{
	ceil = bpg_drone_ceiling( radius );
	if ( !isDefined( ceil ) )
		return offset;                   // open sky, nothing to duck under

	rigZ = 0;
	if ( isDefined( level.uavrig ) )
		rigZ = level.uavrig.origin[ 2 ];

	// keep clear of the roof itself so the model/collision does not clip it
	maxOffsetZ = ceil - 192 - rigZ;

	// ...but never drag a drone down into the playfield where it would collide with
	// buildings or be unreachable-by-design. Floor it above the highest spawn.
	minOffsetZ = 400;
	if ( isDefined( level.spawnpoints ) && level.spawnpoints.size )
	{
		highest = level.spawnpoints[ 0 ].origin[ 2 ];
		for ( i = 0; i < level.spawnpoints.size; i++ )
		{
			if ( level.spawnpoints[ i ].origin[ 2 ] > highest )
				highest = level.spawnpoints[ i ].origin[ 2 ];
		}
		minOffsetZ = ( highest - rigZ ) + 400;
	}
	if ( maxOffsetZ < minOffsetZ )
		maxOffsetZ = minOffsetZ;         // pathologically low roof: prefer flyable over tidy

	if ( offset[ 2 ] <= maxOffsetZ )
		return offset;

	return ( offset[ 0 ], offset[ 1 ], maxOffsetZ );
}

bpg_launchuav_bounded( owner, team, duration, uavType )
{
	if ( uavType == "counter_uav" )
		isCounterUAV = 1;
	else
		isCounterUAV = 0;

	uav = spawn( "script_model", level.uavrig gettagorigin( "tag_origin" ) );
	uav.value = 1;

	if ( uavType == "double_uav" )
		uav.value = 2;
	else if ( uavType == "triple_uav" )
		uav.value = 3;

	if ( uav.value != 3 )
	{
		uav setmodel( "vehicle_uav_static_mp" );
		uav thread maps\mp\killstreaks\_uav::damagetracker( isCounterUAV, 0 );
	}
	else
	{
		uav setmodel( "vehicle_phantom_ray" );
		uav thread maps\mp\killstreaks\_uav::spawnfxdelay( level.uav_fx[ "trail" ], "tag_jet_trail" );
		uav thread maps\mp\killstreaks\_uav::damagetracker( isCounterUAV, 1 );
	}

	uav.team = team;
	uav.owner = owner;
	uav.timetoadd = 0;
	uav thread maps\mp\killstreaks\_uav::handleincomingstinger();
	uav maps\mp\killstreaks\_uav::adduavmodel();
	altitudeOffset = randomintrange( 3000, 5000 );

	if ( isdefined( level.spawnpoints ) )
		spawnPoints = level.spawnpoints;
	else
		spawnPoints = level.startspawnpoints;

	lowestSpawn = spawnPoints[0];

	foreach ( spawnPoint in spawnPoints )
	{
		if ( spawnPoint.origin[2] < lowestSpawn.origin[2] )
			lowestSpawn = spawnPoint;
	}

	lowestZ = lowestSpawn.origin[2];
	rigZ = level.uavrig.origin[2];

	if ( lowestZ < 0 )
	{
		rigZ = rigZ + lowestZ * -1;
		lowestZ = 0;
	}

	zClearance = rigZ - lowestZ;

	if ( zClearance + altitudeOffset > 8100.0 )
		altitudeOffset = altitudeOffset - ( zClearance + altitudeOffset - 8100.0 );

	angle = randomint( 360 );
	horizontalWeight = randomint( 2000 ) + 5000;
	dirX = cos( angle ) * horizontalWeight;
	dirY = sin( angle ) * horizontalWeight;
	direction = vectornormalize( ( dirX, dirY, altitudeOffset ) );

	// FIX: stock orbit distance is a flat 6000-7000 units regardless of map size. Clamp to a
	// safe fraction of level.mapRadius when the map is smaller than that. No-op on stock/large
	// maps (mapRadius >= ~7780 keeps orbitMax at 7000, identical to the original).
	orbitMax = 7000;
	orbitMin = 6000;
	if ( isdefined( level.mapRadius ) && level.mapRadius > 0 )
	{
		safeMax = int( level.mapRadius * 0.9 );
		if ( safeMax < orbitMax )
		{
			orbitMax = safeMax;
			orbitMin = int( safeMax * 0.85 );
			if ( orbitMin < 500 )
				orbitMin = 500;
		}
	}

	orbitUsed = randomintrange( orbitMin, orbitMax );
	direction = direction * orbitUsed;
	// keep it under the map's real ceiling (see the altitude-clamp block above)
	direction = bpg_clamp_offset_to_ceiling( direction, orbitUsed );
	uav linkto( level.uavrig, "tag_origin", direction, ( 0, angle - 90, 0 ) );
	uav thread maps\mp\killstreaks\_uav::updateuavmodelvisibility();

	if ( isCounterUAV )
	{
		uav.uavtype = "counter";
		uav maps\mp\killstreaks\_uav::addactivecounteruav();
	}
	else
	{
		uav maps\mp\killstreaks\_uav::addactiveuav();
		uav.uavtype = "standard";
	}

	if ( isdefined( level.activeuavs[ team ] ) )
	{
		foreach ( other in level.uavmodels[ team ] )
		{
			if ( other == uav )
				continue;

			if ( other.uavtype == "counter" && isCounterUAV )
			{
				other.timetoadd = other.timetoadd + 5;
				continue;
			}

			if ( other.uavtype == "standard" && !isCounterUAV )
				other.timetoadd = other.timetoadd + 5;
		}
	}

	level notify( "uav_update" );

	switch ( uavType )
	{
		case "uav_strike":
			duration = 2;
			break;
		default:
			duration = duration - 7;
			break;
	}

	uav maps\mp\killstreaks\_uav::waittill_notify_or_timeout_hostmigration_pause( "death", duration );

	if ( uav.damagetaken < uav.maxhealth )
	{
		uav unlink();
		leaveTarget = uav.origin + anglestoforward( uav.angles ) * 20000;
		uav moveto( leaveTarget, 60 );
		playfxontag( level._effect[ "ac130_engineeffect" ], uav, "tag_origin" );
		uav maps\mp\killstreaks\_uav::waittill_notify_or_timeout_hostmigration_pause( "death", 3 );

		if ( uav.damagetaken < uav.maxhealth )
		{
			uav notify( "leaving" );
			uav.isleaving = 1;
			uav moveto( leaveTarget, 4, 4, 0.0 );
		}

		uav maps\mp\killstreaks\_uav::waittill_notify_or_timeout_hostmigration_pause( "death", 4 + uav.timetoadd );
	}

	if ( isCounterUAV )
		uav maps\mp\killstreaks\_uav::removeactivecounteruav();
	else
		uav maps\mp\killstreaks\_uav::removeactiveuav();

	uav delete();

	// BPG 2026-07-29 ENTITY-LEAK FIX: stock maps\mp\killstreaks\_uav.gsc (and this copy of it)
	// called removeuavmodel() THROUGH the entity it had just deleted. removeuavmodel() reads
	// `self.team` in its teambased branch, so with self already freed it threw "attempt to call
	// a method on undefined" and the compaction never ran. Result: every UAV / counter-UAV left
	// a permanent dead slot in level.uavmodels[team] for the whole match, and every later
	// UNGUARDED reader of that array threw one more error per stale slot per pass - this
	// function's own timetoadd loop above (`other.uavtype`) on each new launch, and
	// maps\mp\gametypes\survival.gsc::onWaveEnd's `foreach(uav in level.uavmodels["axis"])`
	// (`uav.uavtype`) on each wave end - so the error count grows quadratically with waves.
	// Deleting FIRST is deliberate (the compaction keeps only entries that are still isDefined,
	// which is how the just-deleted UAV drops out), so keep the order and do the compaction with
	// the team we were passed instead of reading it back off the dead entity.
	bpg_uavmodels_compact( team );

	if ( uavType == "directional_uav" )
	{
		owner.radarshowenemydirection = 0;

		if ( level.teambased )
		{
			foreach ( p in level.players )
			{
				if ( p.pers[ "team" ] == team )
					p.radarshowenemydirection = 0;
			}
		}
	}

	level notify( "uav_update" );
}

// Same compaction maps\mp\killstreaks\_uav::removeuavmodel() does, but driven by an explicit
// team instead of `self`, so it can safely run after the UAV entity is gone.
bpg_uavmodels_compact( team )
{
	kept = [];

	if ( isdefined( level.teambased ) && level.teambased )
	{
		if ( !isdefined( team ) || !isdefined( level.uavmodels[ team ] ) )
			return;

		foreach ( model in level.uavmodels[ team ] )
		{
			if ( !isdefined( model ) )
				continue;

			kept[ kept.size ] = model;
		}

		level.uavmodels[ team ] = kept;
		return;
	}

	foreach ( model in level.uavmodels )
	{
		if ( !isdefined( model ) )
			continue;

		kept[ kept.size ] = model;
	}

	level.uavmodels = kept;
}

bpg_spawnremote_bounded( lifeId, owner )
{
	remote = spawnplane( owner, "script_model", level.uavrig gettagorigin( "tag_origin" ), "compass_objpoint_reaper_friendly", "compass_objpoint_reaper_enemy" );

	if ( !isdefined( remote ) )
		return undefined;

	remote setmodel( "vehicle_predator_b" );
	remote.lifeid = lifeId;
	remote.team = owner.team;
	remote.owner = owner;
	remote.numflares = 1;
	remote setcandamage( 1 );
	remote thread maps\mp\killstreaks\_remotemortar::damagetracker();
	remote.helitype = "remote_mortar";
	remote.uavtype = "remote_mortar";
	remote maps\mp\killstreaks\_uav::adduavmodel();

	zWeight = 6300;
	angle = randomint( 360 );
	horizontalWeight = 6100;
	dirX = cos( angle ) * horizontalWeight;
	dirY = sin( angle ) * horizontalWeight;
	direction = vectornormalize( ( dirX, dirY, zWeight ) );

	// FIX: stock orbit distance is a flat 6100 units regardless of map size — same issue and
	// same clamp approach as bpg_launchuav_bounded() above. No-op on stock/large maps.
	orbitDist = 6100;
	if ( isdefined( level.mapRadius ) && level.mapRadius > 0 )
	{
		safeDist = int( level.mapRadius * 0.9 );
		if ( safeDist < orbitDist )
			orbitDist = safeDist;
		if ( orbitDist < 500 )
			orbitDist = 500;
	}

	direction = direction * orbitDist;
	// keep it under the map's real ceiling (see the altitude-clamp block above).
	// This is the one that was still 662u through the roof on castle.
	direction = bpg_clamp_offset_to_ceiling( direction, orbitDist );
	remote linkto( level.uavrig, "tag_origin", direction, ( 0, angle - 90, 10 ) );
	owner setclientdvar( "ui_reaper_targetDistance", -1 );
	owner setclientdvar( "ui_reaper_ammoCount", 14 );
	remote thread maps\mp\killstreaks\_remotemortar::handledeath( owner );
	remote thread maps\mp\killstreaks\_remotemortar::handletimeout( owner );
	remote thread maps\mp\killstreaks\_remotemortar::handleownerchangeteam( owner );
	remote thread maps\mp\killstreaks\_remotemortar::handleownerdisconnect( owner );
	remote thread maps\mp\killstreaks\_remotemortar::handleincomingstinger();
	remote thread maps\mp\killstreaks\_remotemortar::handleincomingsam();
	return remote;
}
