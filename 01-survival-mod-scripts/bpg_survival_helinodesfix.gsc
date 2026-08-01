// bpg_survival_helinodesfix.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-31.
//
// ROOT CAUSE of the "1 leftover enemy" that survived five rounds of type-specific wave-counter
// fixes, and of the stranded juggernaut mi17, and (compounding) of bots stuck in the vehicle
// queue. All one bug.
//
// ── THE EARLY RETURN ─────────────────────────────────────────────────────────────────────────
// Stock maps\mp\killstreaks\_helicopter::init opens with:
//     var_0 = getentarray( "heli_start", "targetname" );
//     var_1 = getentarray( "heli_loop_start", "targetname" );
//     if ( !var_0.size && !var_1.size )
//         return;                      <-- bails before setting ANY of its globals
// None of our maps have those entities - custom ports, and stock maps never built for the
// Chopper Gunner killstreak. This is the same early return that already forced
// bpg_survival_chopperfxinit.gsc to build level.chopper_fx by hand; what was missed then is that
// it also skips level.heli_start_nodes, level.heli_leave_nodes, level.heli_maxhealth and the
// rest of the tuning constants.
//
// ── WHAT IT BREAKS, MEASURED FROM THE LIVE LOG ON <SURV-PORT-4> (mp_geometric, waves 20-22) ──────────
//   18x  "size cannot be applied to undefined"  at heli_leave  <- _juggerdrop
//   12x  "size cannot be applied to undefined"  at _starthelicopter <- _tryusehelicopter
//                                                  <- tryusepavelow <- giveability
//
// 1. PAVELOW - THE LEFTOVER ENEMY.
//    lethalbeats\Survival\abilities\_pavelow::_startHelicopter:
//        maps\mp\_utility::incrementFauxVehicleCount();          <-- runs
//        ...
//        startNode = level.heli_start_nodes[randomInt(level.heli_start_nodes.size)];   <-- ERRORS
//    The error kills the thread, so giveAbility()
//        level_wait_vehicle_limit();
//        self [[level.killStreakFuncs["pavelow_survival"]]]();   <-- dies in here
//        self suicide();                                        <-- never reached
//    never finishes. No helicopter is ever spawned - and pavelow is in BOTS_ABILITIES_KS, so
//    botHandler::onBotKilled:251 refuses to count it and its only counting path is the
//    HELICOPTER's damage handler (_pavelow.gsc:209). No helicopter means no counter, ever.
//    That is one permanently outstanding enemy per pavelow bot, invisible because
//    level_wait_vehicle_limit:1893 already hid it.
//
// 2. THE COMPOUNDING FAILURE - a jammed vehicle queue.
//    incrementFauxVehicleCount() ran BEFORE the error, and nothing ever decrements it. Every
//    failed pavelow leaves level.fauxvehiclecount one higher forever. utility::
//    level_airspace_is_crowded() returns true at `level.fauxvehiclecount >= 4`, and
//    level_vehicle_monitor:1741 skips every tick that is true. After four failures the airspace
//    is permanently "crowded", so NOTHING is ever released from level.vehicleWaiting again and
//    every later chopper / pavelow / reaper / tank / juggernaut / airstrike / predator bot waits
//    forever. 12 errors in one map means this was long past the threshold. This is why fixing
//    the individually leaking types never made the symptom go away.
//
// 3. THE STRANDED mi17.
//    _juggernaut.gsc::_juggerDrop reaches frame 230 and calls `mi17 thread heli_leave()`, which
//    reads level.heli_leave_nodes and errors the same way. It is threaded, so the drop itself
//    still completes - but the helicopter never flies off, which is the one the user could see.
//    bpg_survival_juggerdropfix.gsc removes it; this is why it always had to.
//
// ── THE FIX ──────────────────────────────────────────────────────────────────────────────────
// (1) Populate the globals _helicopter::init would have set, with its own literal values. The
//     node arrays become EMPTY ARRAYS - which is exactly what stock would have assigned had it
//     not bailed, since the getentarray calls it bailed on returned empty. That alone converts
//     a hard "size cannot be applied to undefined" into ordinary empty-array behaviour
//     everywhere, including heli_leave.
//     Only plain assignments and loadfx are replicated. The precacheModel/precacheItem/
//     precacheVehicle/precacheHelicopter calls in stock init are deliberately NOT replicated:
//     no loose script on this box has ever precached at init time, so there is no evidence it
//     is legal this late, and a bad precache is a crash rather than an error line. Nothing here
//     needs them, because (2) makes sure the assets are never used.
//
// (2) An empty node array still cannot fly a helicopter - randomInt(0) has nothing to index. So
//     _startHelicopter is guarded: on a map with no start nodes the pavelow cannot exist, and
//     the honest outcome is to COUNT THE BOT OUT rather than error. The wave stays correct, the
//     faux-vehicle counter is never incremented, and the queue never jams. Players lose a
//     pavelow that was never going to appear on these maps anyway - it has never once spawned.
//
//     Hooked the same way as the tank fix in bpg_survival_wavestallfix.gsc: _pavelow::init does
//         replacefunc(maps\mp\killstreaks\_helicopter::startHelicopter, ::_startHelicopter);
//     so this claims the STOCK symbol afterwards and calls the mod's _startHelicopter BY NAME,
//     which cannot recurse into the replacement. Nothing of the mod's logic is duplicated.
//     ⚠️ Mod init runs AFTER loose scripts, so the replaceFunc is re-asserted on a delay.
//
// ⚠️ NEVER copy to the live <MP-PORT> server - survival gametype only.

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	bpg_populate_heli_globals();

	level thread bpg_starthelicopter_hook();
}

// Values are stock _helicopter::init's own, in its order. Guarded so that a map which DOES have
// heli nodes - where stock ran properly - keeps everything stock built.
bpg_populate_heli_globals()
{
	if ( !isDefined( level.heli_types ) )            level.heli_types = [];

	// Empty is the correct value here, not a placeholder: these are the getentarray results
	// stock bailed on, and they were empty. Callers that check .size now behave instead of
	// erroring.
	if ( !isDefined( level.heli_start_nodes ) )      level.heli_start_nodes = getEntArray( "heli_start", "targetname" );
	if ( !isDefined( level.heli_loop_nodes ) )       level.heli_loop_nodes = getEntArray( "heli_loop_start", "targetname" );
	if ( !isDefined( level.heli_leave_nodes ) )      level.heli_leave_nodes = getEntArray( "heli_leave", "targetname" );
	if ( !isDefined( level.heli_crash_nodes ) )      level.heli_crash_nodes = getEntArray( "heli_crash_start", "targetname" );

	if ( !isDefined( level.heli_missile_rof ) )              level.heli_missile_rof = 5;
	if ( !isDefined( level.heli_maxhealth ) )                level.heli_maxhealth = 2000;
	if ( !isDefined( level.heli_debug ) )                    level.heli_debug = 0;
	if ( !isDefined( level.heli_targeting_delay ) )          level.heli_targeting_delay = 0.5;
	if ( !isDefined( level.heli_turretreloadtime ) )         level.heli_turretreloadtime = 1.5;
	if ( !isDefined( level.heli_turretclipsize ) )           level.heli_turretclipsize = 40;
	if ( !isDefined( level.heli_visual_range ) )             level.heli_visual_range = 3700;
	if ( !isDefined( level.heli_target_spawnprotection ) )   level.heli_target_spawnprotection = 5;
	if ( !isDefined( level.heli_target_recognition ) )       level.heli_target_recognition = 0.5;
	if ( !isDefined( level.heli_missile_friendlycare ) )     level.heli_missile_friendlycare = 256;
	if ( !isDefined( level.heli_missile_target_cone ) )      level.heli_missile_target_cone = 0.3;
	if ( !isDefined( level.heli_armor_bulletdamage ) )       level.heli_armor_bulletdamage = 0.3;
	if ( !isDefined( level.heli_attract_strength ) )         level.heli_attract_strength = 1000;
	if ( !isDefined( level.heli_attract_range ) )            level.heli_attract_range = 4096;
	if ( !isDefined( level.heli_angle_offset ) )             level.heli_angle_offset = 90;
	if ( !isDefined( level.heli_forced_wait ) )              level.heli_forced_wait = 0;
	if ( !isDefined( level.lasthelidialogtime ) )            level.lasthelidialogtime = 0;

	// loadfx at loose-init time is already proven safe by bpg_survival_chopperfxinit.gsc.
	if ( !isDefined( level.fx_heli_dust ) )   level.fx_heli_dust = loadfx( "treadfx/heli_dust_default" );
	if ( !isDefined( level.fx_heli_water ) )  level.fx_heli_water = loadfx( "treadfx/heli_water" );

	if ( level.heli_start_nodes.size == 0 )
		bpg_synthesize_heli_nodes();

	// quiet 2026-08-01: routine per-map summary. Synthesis notice + the no-nodes warning below still log.
}

// ── SYNTHESIZING THE NODES A STOCK MAP SHIPS ─────────────────────────────────────────────────
// Reverse-engineered from how stock actually consumes them, which is a much smaller contract
// than it looks. From maps\mp\killstreaks\_helicopter.gsc:
//     heli_fly_simple_path( n )  /  heli_fly_loop_path( n ):
//         for ( cur = n; isdefined( cur.target ); cur = next )
//         {
//             next = getent( cur.target, "targetname" );
//             self setvehgoalpos( next.origin + self.zoffset, .. );
//             self waittill( "near_goal" );
//             self setgoalyaw( next.angles[1] );
//             self waittillmatch( "goal" );
//         }
// So a node needs exactly THREE things: .origin, .angles, and an optional .target naming the
// next node. Optional .script_airspeed/.script_accel just override a random 30-50 speed, and
// .script_delay only adds a pause - stock defaults both, so neither is needed.
//
// The chain is walked with getent( .., "targetname" ), NOT by array index, so the nodes have to
// be real entities carrying a targetname - a spawnstruct cannot be found by getent. script_origin
// is the right entity type: it is what stock heli_leave itself spawns (:1879) for the heli to
// look at, so a runtime-spawned script_origin is already proven to work in this exact system.
//
// The mod itself confirms the fallback approach is legitimate - lethalbeats\Survival\abilities\
// _chopper.gsc:65-80 already does this for the chopper, which is why choppers fly on our maps and
// pavelows do not:
//     if ( !isDefined( goal ) ) goal = level.mapcenter + (( randomfloat(1)*2-1, randomfloat(1)*2-1, 0 ) * 500 );
//     pathStart = maps\mp\killstreaks\_airdrop::getPathStart( goal, randomInt( 360 ) );
//     yaw = vectorToAngles( goal - pathStart );
// This is that same idea, generalised into the node arrays so EVERY consumer benefits rather than
// just the one killstreak whose author happened to add a fallback.
//
// ⚠️ ALTITUDE IS NOT OPTIONAL. survival.gsc:184 does
//     level.mapcenter = ( level.mapcenter[0], level.mapcenter[1], 0 );
// - it deliberately flattens Z to zero. Copying _chopper's fallback verbatim would therefore
// spawn a helicopter at world Z=0, which on mp_geometric (playable space is Z ~100-390, measured
// from the live bot dump) is underground. Height is taken from the bot waypoints instead, which
// are real sampled positions on the playable surface and are present on every map we run.
bpg_synthesize_heli_nodes()
{
	ref = bpg_map_reference();

	center = ref[ "center" ];
	radius = ref[ "radius" ];

	// ── loop path: a closed ring the helicopter can orbit forever ───────────────────────────
	// Closed on purpose: heli_fly_loop_path walks .target until one is missing, so a ring that
	// points back to its first node keeps flying instead of stopping dead at the last waypoint.
	// 7 nodes: measured from mp_dome, whose ring is auto476-477-478-479-480-481-483 and back to
	// auto476 (bpg_helinode_probe.gsc dump, 2026-07-31). Stock's ring IS closed, confirming the
	// original assumption here.
	count = 7;
	ring = [];

	for ( i = 0; i < count; i++ )
	{
		yaw = i * ( 360 / count );
		pos = center + ( anglesToForward( ( 0, yaw, 0 ) ) * radius );

		e = spawn( "script_origin", pos );
		e.angles = ( 0, yaw + 90, 0 );        // +90 = tangent to the circle, i.e. facing along travel
		e.targetname = "bpg_heli_loop_" + i;
		ring[ ring.size ] = e;
	}

	for ( i = 0; i < count; i++ )
		ring[ i ].target = "bpg_heli_loop_" + ( ( i + 1 ) % count );

	level.heli_loop_nodes = ring;

	// ── start nodes: offset outside the ring, aimed at it ───────────────────────────────────
	// Stock start nodes sit off the playable area and target the first path node; these do the
	// same, so heli_fly_simple_path flies the helicopter in rather than returning immediately.
	starts = [];

	// 3 nodes at 15000 units, MEASURED from mp_dome rather than guessed:
	//     heli_start[0] (13608, -1816, 1431)   [1] (-1712, 15079, 1113)   [2] (-2498, -12370, 1577)
	// against a playable area of only mins(-1521,-653,-451) maxs(1743,2489,-179). So stock start
	// nodes sit 12000-15000 out - roughly four map-widths - not just outside the play space. My
	// first pass used radius*2.5 (~4000 here), which would have had the helicopter appear almost
	// on top of the players instead of flying in. 15000 is also exactly the constant stock
	// maps\mp\killstreaks\_airdrop::getPathStart uses, so the two agree.
	for ( i = 0; i < 3; i++ )
	{
		yaw = i * 120;
		pos = center + ( anglesToForward( ( 0, yaw, 0 ) ) * 15000 );
		pos = ( pos[ 0 ], pos[ 1 ], center[ 2 ] + 300 );

		e = spawn( "script_origin", pos );
		e.angles = ( 0, yaw + 180, 0 );       // face back toward the middle of the map
		e.targetname = "bpg_heli_start_" + i;
		e.target = "bpg_heli_loop_" + ( i * 2 );
		starts[ starts.size ] = e;
	}

	level.heli_start_nodes = starts;

	// ── leave nodes: far outside, so heli_leave() has somewhere to fly off to ───────────────
	// 15000 is stock's own path distance (maps\mp\killstreaks\_airdrop::getPathStart uses it).
	leaves = [];

	// mp_dome ships 4, at 13000-17000 out and Z 1471-2952 - noticeably HIGHER than its start
	// nodes - and with no .target at all, so a leave node is a single point, not a path. Angles
	// are (0,0,0) on all four, i.e. unused.
	for ( i = 0; i < 4; i++ )
	{
		yaw = 45 + i * 90;
		pos = center + ( anglesToForward( ( 0, yaw, 0 ) ) * 15000 );
		pos = ( pos[ 0 ], pos[ 1 ], center[ 2 ] + 900 );

		e = spawn( "script_origin", pos );
		e.angles = ( 0, 0, 0 );
		e.targetname = "bpg_heli_leave_" + i;
		leaves[ leaves.size ] = e;
	}

	level.heli_leave_nodes = leaves;

	println( "[BPG-HELINODES] synthesized heli nodes for " + getDvar( "mapname" ) + " - center=" + center + " radius=" + radius );
}

// Map extents from the bot waypoints. They are sampled from the real playable surface, so they
// give both a truer centre than the Z-flattened level.mapcenter and a radius that fits the map
// instead of a guessed constant.
bpg_map_reference()
{
	out = [];

	if ( isDefined( level.waypoints ) && level.waypoints.size > 0 )
	{
		mins = level.waypoints[ 0 ].origin;
		maxs = level.waypoints[ 0 ].origin;

		foreach ( wp in level.waypoints )
		{
			if ( !isDefined( wp ) || !isDefined( wp.origin ) )
				continue;

			o = wp.origin;

			if ( o[ 0 ] < mins[ 0 ] ) mins = ( o[ 0 ], mins[ 1 ], mins[ 2 ] );
			if ( o[ 1 ] < mins[ 1 ] ) mins = ( mins[ 0 ], o[ 1 ], mins[ 2 ] );
			if ( o[ 2 ] < mins[ 2 ] ) mins = ( mins[ 0 ], mins[ 1 ], o[ 2 ] );

			if ( o[ 0 ] > maxs[ 0 ] ) maxs = ( o[ 0 ], maxs[ 1 ], maxs[ 2 ] );
			if ( o[ 1 ] > maxs[ 1 ] ) maxs = ( maxs[ 0 ], o[ 1 ], maxs[ 2 ] );
			if ( o[ 2 ] > maxs[ 2 ] ) maxs = ( maxs[ 0 ], maxs[ 1 ], o[ 2 ] );
		}

		// 1400 above the HIGHEST sampled point. MEASURED, not guessed: mp_dome's loop ring sits
		// at Z=1070 against a playable surface topping out at Z=-179, i.e. ~1250 above it, and
		// its start nodes are 1113-1577 (~1300-1750 above). The first pass used 800, which is
		// below everything stock does. Highest point rather than average, for the same reason as
		// the drone ceiling clamp - measuring off a low reference puts aircraft in the geometry.
		out[ "center" ] = ( ( mins[ 0 ] + maxs[ 0 ] ) / 2, ( mins[ 1 ] + maxs[ 1 ] ) / 2, maxs[ 2 ] + 1400 );

		dx = ( maxs[ 0 ] - mins[ 0 ] ) / 2;
		dy = ( maxs[ 1 ] - mins[ 1 ] ) / 2;
		r = dx > dy ? dx : dy;

		// 1.5x the half-extent, from mp_dome: its loop ring starts at (-920,-1197) with the map
		// centred on (200,968) - about 2437 away, against a half-extent of roughly 1600. So the
		// orbit is deliberately wider than the play space, not tight around it.
		r = r * 1.5;

		if ( r < 1800 )
			r = 1800;

		out[ "radius" ] = r;

		return out;
	}

	// No waypoints: fall back to the mod's own chopper constant, lifted off the floor.
	base = ( 0, 0, 0 );

	if ( isDefined( level.mapcenter ) )
		base = level.mapcenter;

	out[ "center" ] = ( base[ 0 ], base[ 1 ], base[ 2 ] + 900 );
	out[ "radius" ] = 2000;

	return out;
}

// ⚠️ v2 2026-07-31 - v1 HOOKED THE WRONG SYMBOL, and the reason is worth keeping.
// v1 replaced the STOCK maps\mp\killstreaks\_helicopter::startHelicopter, reasoning that
// _tryusehelicopter:307 calls `starthelicopter(...)` unqualified and _pavelow.gsc's line-1
// `#include maps\mp\killstreaks\_helicopter` resolves that to the stock symbol. The live stack
// says otherwise - it still ran the mod's function:
//     at "_starthelicopter" in lethalbeats/survival/abilities/_pavelow.gsc
//     at "_tryusehelicopter" in lethalbeats/survival/abilities/_pavelow.gsc
// _pavelow::init has already done replacefunc(stock::startHelicopter, ::_startHelicopter), so by
// the time this file evaluates `maps\mp\killstreaks\_helicopter::startHelicopter` there is
// nothing useful left to claim. Replacing the MOD's function directly does work - our own
// bpg_survival_chopperfix.gsc::lbsurvivaldeathcrash_safe shows up in live stack traces doing
// exactly that.
// LESSON: hook the function that the stack trace actually names, not the one you reason it
// should resolve to.
//
// Consequence: the original cannot be called (that would recurse), so the body below is a
// faithful copy of lethalbeats\Survival\abilities\_pavelow::_startHelicopter with ONLY the guard
// added. It is 12 lines of straight-line code with no branching logic of its own, so the copy is
// cheap to keep honest.
bpg_starthelicopter_hook()
{
	level endon( "game_ended" );

	for ( i = 0; i < 6; i++ )
	{
		wait 0.5;
		replaceFunc( lethalbeats\Survival\abilities\_pavelow::_startHelicopter, ::bpg_starthelicopter_guarded );
	}
}

bpg_starthelicopter_guarded( lifeId, heliType )
{
	// THE GUARD. An empty node array is not survivable further down: _startHelicopter does
	//     startNode = level.heli_start_nodes[randomInt(level.heli_start_nodes.size)];
	// and with size 0 that is randomInt(0) -> index 0 of an empty array -> undefined, which
	// _heli_think then feeds to spawnHelicopter as its origin. Populating the array in
	// bpg_populate_heli_globals() only moved the error from "size cannot be applied to
	// undefined" to "spawnhelicopter: parameter 1 has type 'undefined'" - it has to be stopped
	// here instead.
	//
	// Deliberately BEFORE incrementFauxVehicleCount(): that call is what leaks
	// level.fauxvehiclecount on every failure and eventually jams the whole vehicle queue.
	if ( !isDefined( level.heli_start_nodes ) || level.heli_start_nodes.size == 0 )
	{
		println( "[BPG-HELINODES] no heli_start nodes on this map - a pavelow can never spawn here; counting the bot out so the wave can finish" );

		if ( isDefined( self ) && isPlayer( self ) )
			self lethalbeats\survival\utility::bot_kill();

		return;
	}

	// ── from here down: stock mod body, verbatim ────────────────────────────────────────────
	maps\mp\_utility::incrementFauxVehicleCount();

	if ( !isDefined( heliType ) )
		heliType = "";

	switch ( heliType )
	{
		case "flares":
		case "flares_survial":
			// ⚠️ Stock has `self thread pavelowMadeSelectionVO();` here. It is DELIBERATELY not
			// reproduced. Calling it qualified as
			//     lethalbeats\Survival\abilities\_pavelow::pavelowMadeSelectionVO()
			// does not resolve across files, and an unresolved reference in IW5 GSC is a
			// COMPILE-time failure, not a runtime one:
			//     Com_ERROR: Scr_EmitFunction: function "bpg_starthelicopter_guarded" in file
			//     "scripts/bpg_survival_helinodesfix.gsc" referenced unknown function
			//     pavelowmadeselectionvo from script lethalbeats/survival/abilities/_pavelow.gsc
			// That kills the whole level load, so the server boot-loops through the rotation and
			// never comes up. It did exactly that on <SURV-PORT-3> on 2026-07-31.
			// ⚠️ `iw5gsc check` CANNOT catch this - it parses one file and does not resolve
			// cross-file mod symbols. A clean check is not proof a script will load.
			// The call is a voice-over announcing the pavelow; dropping it costs one audio cue
			// and nothing else.
			eventType = "helicopter_flares";
			break;
		case "minigun":
			eventType = "helicopter_minigun";
			break;
		default:
			eventType = "helicopter";
			break;
	}

	startNode = level.heli_start_nodes[ randomInt( level.heli_start_nodes.size ) ];

	self maps\mp\_matchdata::logKillstreakEvent( eventType, self.origin );

	// Stock calls this unqualified; the qualified stock symbol resolves through _pavelow::init's
	// replacefunc to the mod's _heli_think, which is the same function stock would have reached.
	self thread maps\mp\killstreaks\_helicopter::heli_think( lifeId, self, startNode, self.pers[ "team" ], heliType );
}
