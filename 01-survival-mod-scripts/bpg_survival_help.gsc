// bpg_survival_help.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-16.
// User: "add a !help command to see a list of all available commands."
// (Live log showed players typing !help and getting nothing.) Registers !help
// (alias !commands) through the mod's own command registry, power 0 = everyone.
// Output via tell() so only the asker sees it (no chat spam).
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	lethalbeats\servercontrol\commands::setCommand( "help", ::bpg_help_cmd, 0, 0 );
	lethalbeats\servercontrol\commands::setCommand( "commands", ::bpg_help_cmd, 0, 0 );
	lethalbeats\servercontrol\commands::setCommandAlias( "help", "h" );
}

// The client DROPS tell() messages sent in the same frame beyond the first ~2
// (live report: "!help only shows 2"; the mod's own !players waits 1s per line
// for the same reason). Trickle the lines out, two commands per line.
bpg_help_cmd( a, b, c ) // optional args: dispatcher passes trailing words as args (checkclearparams guard)
{
	self endon( "disconnect" );
	level endon( "game_ended" );

	if ( self isTestClient() )
		return;

	lines = [];
	lines[ 0 ] = "^3== yourserver.gg Your Server - Commands ==";
	lines[ 1 ] = "^2!pay <name> <amt> ^7send money  ^2!undo ^7undo shop buys";
	lines[ 2 ] = "^2!afk ^7safe mode 10min  ^2!stuck ^7escape geometry";
	lines[ 3 ] = "^2!stats ^7your stats  ^2!suicide ^7respawn yourself";
	lines[ 4 ] = "^2!votekick <name> ^7+ ^2!yes ^7kick vote  ^2!feedback <msg> ^7report bug";
	lines[ 5 ] = "^2!rules  !discord  ^2!pm <name> <msg>  !players  !admins";
	lines[ 6 ] = "^3[F5] ^7skips intermission - vote maps + difficulty at round end";

	for ( i = 0; i < lines.size; i++ )
	{
		self tell( lines[ i ] );
		wait 0.4;
	}
}
