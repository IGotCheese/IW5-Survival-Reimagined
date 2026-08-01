// bpg_survival_botspeed.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-16.
// User request: faster enemy bots. Uses the mod's own speed mechanism (the dog
// ability sets .moveSpeedScaler and calls stock _weapons::updateMoveSpeedScale —
// both proven in lethalbeats code, no new builtins).
// Applies to AXIS wave bots only (players untouched), re-applied on every spawn
// so the dvar tunes live:
//   rcon set bpg_bot_speed_scale 1.30    (1.0 = stock; dog sprint = 1.5 for scale)
// ⚠️ NEVER copy to the live <MP-PORT> server.

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	if ( getDvar( "bpg_bot_speed_scale" ) == "" )
		setDvar( "bpg_bot_speed_scale", "1.50" );

	level thread bpg_botspeed_watcher();
}

bpg_botspeed_watcher()
{
	level endon( "game_ended" );

	for ( ;; )
	{
		level waittill( "connected", player );
		if ( player isTestClient() )
			player thread bpg_botspeed_on_spawn();
	}
}

bpg_botspeed_on_spawn()
{
	self endon( "disconnect" );
	level endon( "game_ended" );

	for ( ;; )
	{
		self waittill( "spawned_player" );
		wait 0.15; // after loadout flows

		// Bot Warfare's watchers cast these to bool every tick, but the mod only
		// defines them on specific events -> "cannot cast undefined to bool"
		// storms from stance_loop / bot_watch_riot_weapons. Defining them as
		// false is a no-op behaviorally and silences the storm at the source.
		if ( !isDefined( self.lastStand ) )
			self.lastStand = false;
		if ( !isDefined( self.hasriotshieldequipped ) )
			self.hasriotshieldequipped = false;

		// enemies only — never squad bots or anything not axis
		if ( !isDefined( self.pers[ "team" ] ) || self.pers[ "team" ] != "axis" )
			continue;

		scale = getDvarFloat( "bpg_bot_speed_scale" );
		if ( scale <= 0 || scale > 3 )
			scale = 1;

		self.moveSpeedScaler = scale;
		self maps\mp\gametypes\_weapons::updateMoveSpeedScale();
	}
}
