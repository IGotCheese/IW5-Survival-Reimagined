// bpg_survival_votekick.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-16.
// VOTE TO KICK: !votekick <name> starts a 45s vote; other humans type !yes (or
// repeat !votekick <name>) to agree. Passes on a majority of the OTHER human
// players (excluding the target), with a minimum of bpg_votekick_min voters
// (default 2 — so a duo can't grief-kick each other 1v1).
// PROTECTIONS: bots can't be targeted, no self-kick, server owner GUID and any
// registered ServerControl admin (group power > 0) are immune, one vote at a
// time, 120s initiator cooldown after a failed vote. Kicks are session kicks
// (Plutonium kick), not bans — the player can rejoin.
// Same safe pattern as !pay/!feedback: setCommand + no engine coupling.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	if ( getDvar( "bpg_votekick_min" ) == "" )
		setDvar( "bpg_votekick_min", "2" );
	if ( getDvar( "bpg_idle_seconds" ) == "" )
		setDvar( "bpg_idle_seconds", "180" );

	lethalbeats\servercontrol\commands::setCommand( "votekick", ::bpg_votekick_cmd, 0, 1, "^7Usage: ^3!votekick <player>", undefined, undefined, true );
	lethalbeats\servercontrol\commands::setCommandAlias( "votekick", "vk" );
	lethalbeats\servercontrol\commands::setCommand( "yes", ::bpg_yes_cmd, 0, 0 );
	lethalbeats\servercontrol\commands::setCommandAlias( "yes", "y" );

	// AFK handling: never hard-kick idle players (g_inactivity stays 0) — an
	// idle detector puts them up for a PLAYER VOTE instead. Players who
	// declared !afk are exempt (that's the polite way to idle).
	level thread bpg_idle_watcher();
}

bpg_idle_watcher()
{
	level endon( "game_ended" );

	for ( ;; )
	{
		level waittill( "connected", player );
		if ( !player isTestClient() )
			player thread bpg_idle_monitor();
	}
}

bpg_idle_monitor()
{
	self endon( "disconnect" );
	level endon( "game_ended" );

	self.bpg_idle = 0;
	lastOrg = undefined;
	lastYaw = undefined;

	for ( ;; )
	{
		wait 10;

		if ( !isAlive( self ) )
		{
			self.bpg_idle = 0;
			continue;
		}
		// declared AFK, downed, or protected players are never auto-voted
		if ( ( isDefined( self.bpg_afk ) && self.bpg_afk )
			|| ( isDefined( self.inLastStand ) && self.inLastStand )
			|| bpg_vk_is_protected( self ) )
		{
			self.bpg_idle = 0;
			continue;
		}

		org = self.origin;
		yaw = self getPlayerAngles()[ 1 ];

		moved = true;
		if ( isDefined( lastOrg ) && isDefined( lastYaw ) )
		{
			dyaw = yaw - lastYaw;
			if ( dyaw < 0 ) dyaw = 0 - dyaw;
			moved = ( distanceSquared( org, lastOrg ) > 4 || dyaw > 2 );
		}
		lastOrg = org;
		lastYaw = yaw;

		if ( moved )
		{
			self.bpg_idle = 0;
			continue;
		}

		self.bpg_idle += 10;
		if ( self.bpg_idle < getDvarInt( "bpg_idle_seconds" ) )
			continue;

		// idle threshold reached: put them up for a vote (retry later if one
		// is already running or the lobby is too small to ever pass)
		if ( isDefined( self.bpg_idle_next ) && getTime() < self.bpg_idle_next )
			continue;

		if ( isDefined( level.bpg_vk ) )
		{
			self.bpg_idle_next = getTime() + 60000;
			continue;
		}

		minv = getDvarInt( "bpg_votekick_min" );
		if ( minv < 1 ) minv = 1;
		if ( bpg_vk_eligible_count( self ) < minv )
		{
			self.bpg_idle_next = getTime() + 120000;
			continue;
		}

		self.bpg_idle_next = getTime() + 300000; // one auto-vote per 5 min per player
		self.bpg_idle = 0;

		vk = spawnStruct();
		vk.target = self;
		vk.starter = undefined; // server-started: no cooldown to assign on failure
		vk.voters = [];
		level.bpg_vk = vk;

		need = bpg_vk_needed( self );
		iprintlnBold( "^3" + self.name + " ^7appears ^1AFK" );
		iprintln( "^7Type ^3!yes ^7to kick - ^30/" + need + " ^7votes, 45s (^3!afk ^7protects you while away)" );
		self tell( "^1You look AFK - move, or type ^3!afk ^1to idle safely" );

		level thread bpg_vk_run();
	}
}

// argsIsMessage dispatch signature: (validMsg, invalidMsg, args[])
bpg_votekick_cmd( validMsg, invalidMsg, args )
{
	if ( self isTestClient() )
		return;

	if ( !isDefined( args ) || args.size < 1 )
	{
		self tell( "^7Usage: ^3!votekick <player>" );
		return;
	}

	query = "";
	for ( i = 0; i < args.size; i++ )
	{
		if ( query != "" )
			query += " ";
		query += args[ i ];
	}

	// active vote: repeating the target's name counts as a yes
	if ( isDefined( level.bpg_vk ) )
	{
		if ( isDefined( level.bpg_vk.target ) && isSubStr( toLower( level.bpg_vk.target.name ), toLower( query ) ) )
		{
			self bpg_vk_register_yes();
			return;
		}
		self tell( "^1A kick vote is already running ^7(against " + level.bpg_vk.target.name + ")" );
		return;
	}

	if ( isDefined( self.bpg_vk_next ) && getTime() < self.bpg_vk_next )
	{
		remain = int( ( self.bpg_vk_next - getTime() ) / 1000 ) + 1;
		self tell( "^1Vote-kick on cooldown: ^7" + remain + "s" );
		return;
	}

	// find the target among human players
	matches = [];
	lquery = toLower( query );
	foreach ( p in level.players )
	{
		if ( !isDefined( p ) || p isTestClient() )
			continue;
		if ( isSubStr( toLower( p.name ), lquery ) )
			matches[ matches.size ] = p;
	}

	if ( matches.size < 1 )
	{
		self tell( "^1No player matching ^7\"" + query + "\"" );
		return;
	}
	if ( matches.size > 1 )
	{
		self tell( "^1Multiple players match ^7\"" + query + "\" - be more specific" );
		return;
	}

	target = matches[ 0 ];

	if ( target == self )
	{
		self tell( "^1You can't vote-kick yourself" );
		return;
	}

	if ( bpg_vk_is_protected( target ) )
	{
		self tell( "^1That player can't be vote-kicked" );
		return;
	}

	// need at least min voters to ever pass
	eligible = bpg_vk_eligible_count( target );
	minv = getDvarInt( "bpg_votekick_min" );
	if ( minv < 1 ) minv = 1;
	if ( eligible < minv )
	{
		self tell( "^1Not enough players online for a kick vote" );
		return;
	}

	vk = spawnStruct();
	vk.target = target;
	vk.starter = self;
	vk.voters = [];
	vk.voters[ 0 ] = self.guid;
	level.bpg_vk = vk;

	need = bpg_vk_needed( target );
	iprintlnBold( "^1KICK VOTE ^7against ^3" + target.name );
	iprintln( "^7Type ^3!yes ^7to agree - ^3" + vk.voters.size + "/" + need + " ^7votes, 45s" );

	level thread bpg_vk_run();
}

bpg_yes_cmd( a, b, c ) // optional args: dispatcher passes trailing words as args (checkclearparams guard)
{
	if ( self isTestClient() )
		return;
	if ( !isDefined( level.bpg_vk ) )
	{
		self tell( "^1No kick vote is running" );
		return;
	}
	self bpg_vk_register_yes();
}

bpg_vk_register_yes()
{
	vk = level.bpg_vk;
	if ( !isDefined( vk ) || !isDefined( vk.target ) )
		return;

	if ( self == vk.target )
		return; // nice try

	for ( i = 0; i < vk.voters.size; i++ )
	{
		if ( vk.voters[ i ] == self.guid )
		{
			self tell( "^1You already voted" );
			return;
		}
	}

	vk.voters[ vk.voters.size ] = self.guid;
	need = bpg_vk_needed( vk.target );
	iprintln( "^7Kick vote: ^3" + vk.voters.size + "/" + need );

	if ( vk.voters.size >= need )
		level notify( "bpg_vk_passed" );
}

bpg_vk_run()
{
	level endon( "game_ended" );

	starter = level.bpg_vk.starter;

	result = bpg_vk_wait();

	if ( result == "passed" && isDefined( level.bpg_vk ) && isDefined( level.bpg_vk.target ) )
	{
		t = level.bpg_vk.target;
		iprintlnBold( "^1" + t.name + " was vote-kicked" );
		println( "[BPGVOTEKICK] kicked " + t.name + " (" + t.guid + "), " + level.bpg_vk.voters.size + " votes" );
		kick( t getEntityNumber() );
	}
	else if ( result == "gone" )
	{
		iprintln( "^7Kick vote cancelled - player left" );
	}
	else
	{
		iprintln( "^7Kick vote ^1failed ^7- not enough votes" );
		if ( isDefined( starter ) )
			starter.bpg_vk_next = getTime() + 120000; // 120s before starting another
	}

	level.bpg_vk = undefined;
}

bpg_vk_wait()
{
	level endon( "game_ended" );

	for ( t = 0; t < 45; t++ )
	{
		wait 1;
		if ( !isDefined( level.bpg_vk ) || !isDefined( level.bpg_vk.target ) )
			return "gone";
		if ( level.bpg_vk.voters.size >= bpg_vk_needed( level.bpg_vk.target ) )
			return "passed";
	}
	return "failed";
}

// majority of human players excluding the target, floored at bpg_votekick_min
bpg_vk_needed( target )
{
	eligible = bpg_vk_eligible_count( target );
	need = int( eligible / 2 ) + 1;
	minv = getDvarInt( "bpg_votekick_min" );
	if ( minv < 1 ) minv = 1;
	if ( need < minv )
		need = minv;
	return need;
}

bpg_vk_eligible_count( target )
{
	n = 0;
	foreach ( p in level.players )
	{
		if ( !isDefined( p ) || p isTestClient() || p == target )
			continue;
		n++;
	}
	return n;
}

bpg_vk_is_protected( target )
{
	// server owner
	if ( isDefined( target.guid ) && target.guid == "01000000CCCCCCCC" )
		return true;

	// any registered ServerControl admin (group power above guest)
	power = target lethalbeats\servercontrol\groups::getGroupPower();
	if ( isDefined( power ) && power > 0 )
		return true;

	return false;
}
