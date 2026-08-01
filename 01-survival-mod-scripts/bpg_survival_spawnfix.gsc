// bpg_survival_spawnfix.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-16.
// User: "spawn under map on minecraft" (mp_minecraft). Custom-map ports can carry
// broken spawn entities that place players below the walkable floor (same class as
// the tunisia under-map spawns on main, and bots-in-the-ocean on osg_hijacked).
// GENERIC FIX: bot WAYPOINTS are on walkable ground by definition and every rotation
// map ships them. Shortly after each spawn, if there is NO waypoint near the player's
// level and the nearest one is well ABOVE them, they spawned under the map -> snap
// them up to the nearest waypoint. Applies to humans AND wave bots (under-map bots
// = unkillable stragglers that stall waves). Checks at 0.1s and 1.1s after spawn
// (the second catches slow fall-through after physics settles). No-ops on maps with
// healthy spawns. Tune/disable live: set bpg_spawnfix 0
// ⚠️ NEVER copy to the live <MP-PORT> server (waypoint layout assumptions differ).

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	if ( getDvar( "bpg_spawnfix" ) == "" )
		setDvar( "bpg_spawnfix", "1" );

	level thread bpg_spawnfix_watcher();
	level thread bpg_install_spawnpicker_guard();
}

// v2 2026-07-16: mp_minecraft_3 LIVE showed the spawn picker can return NOTHING
// (map has no usable spawn ents) -> stock spawnplayer errors on an undefined
// spawnpoint ("spawn: parameter 0 ... should be a vector"), the spawn thread DIES
// before "spawned_player" ever fires (so the post-spawn validator below can't help),
// and players drop into the void. FIX one level deeper: stock _playerlogic gets the
// spawn from `[[level.getspawnpoint]]()` (VERIFIED in the decomp: the RETURN value's
// .origin/.angles feed `self spawn(...)`; level.onSpawnPlayer is only a side-effect
// hook). Wrap that function-ref (race-free level-var wrap, same pattern as the
// killfeed hook) and fabricate a waypoint-based spawn struct whenever the real
// picker comes back empty (fake spawn structs with .origin/.angles are the proven
// technique from the CTF/SAB spawn injection work).
bpg_install_spawnpicker_guard()
{
	level endon( "game_ended" );

	while ( !isDefined( level.getspawnpoint ) )
		wait 0.25;
	wait 0.05;

	level.bpg_orig_getspawnpoint = level.getspawnpoint;
	level.getspawnpoint = ::bpg_getspawnpoint_guard;
}

// v3 HOTFIX 2026-07-16: the mod's getSpawnPoint() takes ZERO parameters and this
// engine hard-errors (OP_checkclearparams) when a GSC function receives extra args
// — v2's 4-arg passthrough error-stormed and KILLED spawnplayer on every live spawn
// (mp_morningwood). Stock calls [[level.getspawnpoint]]() with no args; forward none.
bpg_getspawnpoint_guard()
{
	sp = self [[ level.bpg_orig_getspawnpoint ]]();

	if ( isDefined( sp ) )
		return sp;
	if ( !getDvarInt( "bpg_spawnfix" ) )
		return sp;
	if ( !isDefined( level.waypoints ) || level.waypoints.size <= 0 )
		return sp;

	// real picker found nothing: fabricate a spawn on walkable ground
	wp = level.waypoints[ randomInt( level.waypoints.size ) ];
	if ( !isDefined( wp ) || !isDefined( wp.origin ) )
		wp = level.waypoints[ 0 ];
	if ( !isDefined( wp ) || !isDefined( wp.origin ) )
		return sp;

	fake = spawnStruct();
	fake.origin = wp.origin + ( 0, 0, 24 );
	fake.angles = ( 0, randomInt( 360 ), 0 );
	logPrint( "[BPGSPAWNFIX] fabricated waypoint spawn on " + getDvar( "mapname" ) + "\n" );
	return fake;
}

bpg_spawnfix_watcher()
{
	level endon( "game_ended" );

	for ( ;; )
	{
		level waittill( "connected", player );
		player thread bpg_spawnfix_on_spawn();
	}
}

bpg_spawnfix_on_spawn()
{
	self endon( "disconnect" );
	level endon( "game_ended" );

	for ( ;; )
	{
		self waittill( "spawned_player" );

		if ( !getDvarInt( "bpg_spawnfix" ) )
			continue;

		self thread bpg_spawnfix_check_twice();
	}
}

bpg_spawnfix_check_twice()
{
	self endon( "disconnect" );
	self endon( "death" );
	level endon( "game_ended" );

	// idempotent per spawn
	self notify( "bpg_spawnfix_check" );
	self endon( "bpg_spawnfix_check" );

	wait 0.1;
	if ( self bpg_spawnfix_validate() )
		return;
	wait 1.0;
	self bpg_spawnfix_validate();
}

// returns true if a relocation happened
bpg_spawnfix_validate()
{
	if ( !isDefined( level.waypoints ) || level.waypoints.size <= 0 )
		return false;
	if ( !isAlive( self ) )
		return false;

	wpcount = level.waypoints.size;
	if ( isDefined( level.waypointCount ) && level.waypointCount > 0 && level.waypointCount <= wpcount )
		wpcount = level.waypointCount;

	org = self.origin;
	nearest = undefined;
	nearestDist = 999999;
	hasLevelGround = false;

	for ( i = 0; i < wpcount; i++ )
	{
		wp = level.waypoints[ i ];
		if ( !isDefined( wp ) || !isDefined( wp.origin ) )
			continue;

		d = distance( org, wp.origin );
		if ( d < nearestDist )
		{
			nearestDist = d;
			nearest = wp;
		}

		// a waypoint reasonably close AND roughly at our height = we're on the
		// walkable layer; nothing to fix
		if ( d < 300 && abs( wp.origin[ 2 ] - org[ 2 ] ) < 96 )
		{
			hasLevelGround = true;
			break;
		}
	}

	if ( hasLevelGround || !isDefined( nearest ) )
		return false;

	// nearest walkable ground is well ABOVE us with nothing at our level -> we're
	// under the map. Snap up onto that waypoint.
	if ( nearest.origin[ 2 ] - org[ 2 ] > 96 )
	{
		self setOrigin( nearest.origin + ( 0, 0, 24 ) );
		if ( !self isTestClient() )
			self iPrintLnBold( "^3Bad spawn fixed ^7- moved to solid ground" );
		logPrint( "[BPGSPAWNFIX] relocated " + self.name + " from under the map on " + getDvar( "mapname" ) + "\n" );
		return true;
	}

	return false;
}
