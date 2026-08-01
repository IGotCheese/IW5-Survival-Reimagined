// bpg_survival_pay.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-16.
// MONEY SHARING: !pay <player> <amount>  (alias !give is taken by dev cmds -> !share too)
// No such feature exists in the mod or anywhere on GitHub (searched 2026-07-16).
// Uses ONLY mechanisms already proven live here: ServerControl setCommand with
// argsIsMessage dispatch (same as !feedback) and the mod's survivor_set_score
// (pers["score"] + .score + ui_money dvar — same call the shop cooldown charges with).
// No bots, no engine overrides, no replaceFunc — pure player-to-player plumbing.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	lethalbeats\servercontrol\commands::setCommand( "pay", ::bpg_pay_cmd, 0, 2, "^7Usage: ^3!pay <player> <amount>", undefined, undefined, true );
	lethalbeats\servercontrol\commands::setCommandAlias( "pay", "share" );
	lethalbeats\servercontrol\commands::setCommandAlias( "pay", "p" );

	level thread bpg_pay_announce();
}

// argsIsMessage dispatch signature: (validMsg, invalidMsg, args[])
bpg_pay_cmd( validMsg, invalidMsg, args )
{
	if ( self isTestClient() )
		return;

	if ( isDefined( self.bpg_pay_next ) && getTime() < self.bpg_pay_next )
	{
		self tell( "^1Easy there ^7- one payment every 5 seconds" );
		return;
	}

	if ( !isDefined( args ) || args.size < 2 )
	{
		self tell( "^7Usage: ^3!pay <player> <amount>" );
		return;
	}

	// last token = amount, everything before = the (possibly spaced) player name
	amount = int( args[ args.size - 1 ] );
	query = "";
	for ( i = 0; i < args.size - 1; i++ )
	{
		if ( query != "" )
			query += " ";
		query += args[ i ];
	}

	if ( amount < 50 )
	{
		self tell( "^1Minimum payment is ^3$50" );
		return;
	}

	if ( !isDefined( self.pers[ "score" ] ) || self.pers[ "score" ] < amount )
	{
		self tell( "^1You don't have that much cash" );
		return;
	}

	// partial, case-insensitive name match among human players
	matches = [];
	lquery = toLower( query );
	foreach ( p in level.players )
	{
		if ( !isDefined( p ) || p isTestClient() || p == self )
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
	if ( !isDefined( target.pers[ "score" ] ) )
	{
		self tell( "^1That player can't receive cash right now" );
		return;
	}

	self.bpg_pay_next = getTime() + 5000;

	// deterministic transfer through the mod's own setter (updates pers, .score, ui_money)
	self lethalbeats\survival\utility::survivor_set_score( int( self.pers[ "score" ] - amount ) );
	target lethalbeats\survival\utility::survivor_set_score( int( target.pers[ "score" ] + amount ) );

	self tell( "^2You sent ^3$" + amount + " ^2to ^7" + target.name );
	target tell( "^2" + self.name + " ^7sent you ^3$" + amount );
	target playLocalSound( "mp_killconfirm_tags_pickup" );

	println( "[BPGPAY] " + self.name + " -> " + target.name + " : " + amount );
}

bpg_pay_announce()
{
	level endon( "game_ended" );

	level waittill( "wave_start" );
	wait 35;
	iprintln( "^7Share cash with a teammate: ^3!pay <player> <amount>" );
}
