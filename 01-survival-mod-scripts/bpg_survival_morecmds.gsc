// bpg_survival_morecmds.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-16.
// User: "search github to find more commands and add them."
// GitHub findings (LastDemon99/IW5-Sripts ServerControl commands.gsc): the mod
// ALREADY ships working player commands !suicide / !players / !pm / !admins and a
// permission-aware !help — but !rules, !social, !stats and !next are EMPTY STUBS
// ("not finished"). This file implements the useful stubs bpg-style and adds !stuck:
//   !rules             - server rules
//   !discord           - yourserver.gg / Discord pointer (aliases: !social, !website)
//   !stats             - your kills / deaths / cash / current wave (GSC-only version
//                        of the stub that "required plugin SDK")
//   !stuck             - teleport to the nearest bot waypoint (60s cooldown) — for
//                        players wedged in geometry (live report: "IM GLITCHED LOL
//                        stuck in the ground")
// All handlers take 3 optional params: with no usage messages registered the
// dispatcher passes any trailing chat words as up to 3 positional args, and this
// engine hard-errors (OP_checkclearparams) on arg overflow.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	if ( getDvar( "bpg_stuck_cooldown" ) == "" )
		setDvar( "bpg_stuck_cooldown", "60" );

	lethalbeats\servercontrol\commands::setCommand( "rules", ::bpg_rules_cmd, 0, 0 );
	lethalbeats\servercontrol\commands::setCommandAlias( "rules", "r" );
	lethalbeats\servercontrol\commands::setCommand( "discord", ::bpg_discord_cmd, 0, 0 );
	lethalbeats\servercontrol\commands::setCommand( "social", ::bpg_discord_cmd, 0, 0 );
	lethalbeats\servercontrol\commands::setCommand( "website", ::bpg_discord_cmd, 0, 0 );
	lethalbeats\servercontrol\commands::setCommandAlias( "discord", "dc" );
	lethalbeats\servercontrol\commands::setCommand( "stats", ::bpg_stats_cmd, 0, 0 );
	lethalbeats\servercontrol\commands::setCommandAlias( "stats", "st" );
	lethalbeats\servercontrol\commands::setCommand( "stuck", ::bpg_stuck_cmd, 0, 0 );
	lethalbeats\servercontrol\commands::setCommand( "unstuck", ::bpg_stuck_cmd, 0, 0 );
	// NOT "s" - the base mod's own commands.gsc already aliases "s" to !suicide
	// (lethalbeats\ServerControl\commands.gsc: setCommandAlias("suicide", "s")) -
	// confirmed via the real source, not assumed. Using "sk" instead to avoid
	// silently colliding with (or overriding) the existing suicide shortcut.
	lethalbeats\servercontrol\commands::setCommandAlias( "stuck", "sk" );
}

// tell() lines must be trickled: the client drops same-frame messages beyond ~2
bpg_rules_cmd( a, b, c )
{
	self endon( "disconnect" );
	level endon( "game_ended" );

	if ( self isTestClient() )
		return;

	lines = [];
	lines[ 0 ] = "^3== Server Rules ==";
	lines[ 1 ] = "^71. No cheating, exploiting, or glitch abuse";
	lines[ 2 ] = "^72. Be respectful - no toxicity or spam. EN + ES welcome";
	lines[ 3 ] = "^73. Found a bug? Report it with ^2!feedback <message>";
	lines[ 4 ] = "^74. Have fun and survive!";

	for ( i = 0; i < lines.size; i++ )
	{
		self tell( lines[ i ] );
		wait 0.4;
	}
}

bpg_discord_cmd( a, b, c )
{
	self endon( "disconnect" );
	level endon( "game_ended" );

	if ( self isTestClient() )
		return;

	self tell( "^7Website: ^2yourserver.gg ^7- the Discord invite is on the site" );
	wait 0.4;
	self tell( "^7Come hang out, report bugs, and vote on new maps!" );
}

bpg_stats_cmd( a, b, c )
{
	if ( self isTestClient() )
		return;

	kills = 0;
	deaths = 0;
	cash = 0;
	wave = 0;
	if ( isDefined( self.pers[ "kills" ] ) )
		kills = self.pers[ "kills" ];
	if ( isDefined( self.pers[ "deaths" ] ) )
		deaths = self.pers[ "deaths" ];
	if ( isDefined( self.pers[ "score" ] ) )
		cash = self.pers[ "score" ];
	if ( isDefined( level.wave_num ) )
		wave = level.wave_num;

	self tell( "^3== Your Stats ==" );
	self tell( "^7Kills: ^2" + kills + " ^7Deaths: ^1" + deaths + " ^7Cash: ^2$" + cash + " ^7Wave: ^3" + wave );
}

bpg_stuck_cmd( a, b, c )
{
	if ( self isTestClient() )
		return;

	if ( !isAlive( self ) )
	{
		self tell( "^1You can't use !stuck while dead" );
		return;
	}
	if ( isDefined( self.dogKnockdown ) && self.dogKnockdown )
	{
		// A dog takedown that got interrupted (dog killed mid-anim) can leave the
		// flag stuck AND the player linked/buried (user report 2026-07-17: neck-snap
		// left them in the ground and !stuck refused). Our dogfix stamps
		// bpg_kd_lock = start+3s; if that expired >5s ago the knockdown is STALE —
		// clear it and let !stuck rescue them. Only a LIVE knockdown still blocks.
		stale = !isDefined( self.bpg_kd_lock ) || getTime() > self.bpg_kd_lock + 5000;
		if ( !stale )
		{
			self tell( "^1Not during a dog attack - fight it off!" );
			return;
		}
		self.dogKnockdown = false;
	}
	if ( isDefined( self.bpg_afk ) && self.bpg_afk )
	{
		self tell( "^1Not while AFK" );
		return;
	}
	// NO COOLDOWN (user 2026-07-17: "remove that"). If you're stuck you should be able to spam it.
	if ( !isDefined( level.waypoints ) || level.waypoints.size <= 0 )
	{
		self tell( "^1No safe spots known on this map" );
		return;
	}

	// Pick a waypoint to escape to. The OLD "nearest waypoint" logic failed when a player was
	// wedged right on top of one (e.g. lodged in a crate on shipment) — it just re-planted them
	// in the same spot. Now: a RANDOM waypoint that's a real distance away, so it actually
	// breaks them out of the geometry. Falls back to any valid waypoint if the map is tiny.
	dest = undefined;
	for ( tries = 0; tries < 25 && !isDefined( dest ); tries++ )
	{
		wp = level.waypoints[ randomInt( level.waypoints.size ) ];
		if ( !isDefined( wp ) || !isDefined( wp.origin ) )
			continue;
		if ( distance( self.origin, wp.origin ) < 120 )   // too close = maybe the stuck spot
			continue;
		dest = wp;
	}
	if ( !isDefined( dest ) )
	{
		for ( i = 0; i < level.waypoints.size; i++ )
		{
			if ( isDefined( level.waypoints[ i ] ) && isDefined( level.waypoints[ i ].origin ) )
			{
				dest = level.waypoints[ i ];
				break;
			}
		}
	}
	if ( !isDefined( dest ) )
	{
		self tell( "^1No safe spots known on this map" );
		return;
	}

	// takedown anims LINK the player to the dog; a linked player ignores setOrigin
	// (the other half of the "stuck in the ground, !stuck did nothing" report)
	if ( self isLinked() )
		self unlink();
	// an interrupted dog knockdown ALSO leaves the player frozen + weapons disabled
	// (playerDogKnockdown does freezeControls(true)+disableWeapons()); without undoing
	// those, !stuck relocates them but they stay frozen and weaponless = still stuck.
	self freezeControls( false );
	self enableWeapons();
	// 2026-07-19: player_hide() (run on every knockdown) does player_take_all_weapons(true)
	// and stashes the gun in self.hideData for player_show() to restore — enableWeapons()
	// alone only re-enables firing, it never gives the stripped weapon back.
	// 2026-07-20: player_show() itself used to be buggy too (head-attach before the body
	// model, wrong tag) — that's now fixed once at the source (bpg_survival_dogfix.gsc
	// replaceFuncs lethalbeats\survival\utility::player_show), so this just calls it
	// directly instead of duplicating the restore logic here.
	if ( isDefined( self.hideData ) )
		self lethalbeats\survival\utility::player_show();
	self setOrigin( dest.origin + ( 0, 0, 40 ) );
	self tell( "^2Unstuck ^7- moved to a safe spot" );
	logPrint( "[BPGSTUCK] " + self.name + " unstuck on " + getDvar( "mapname" ) + "\n" );
}
