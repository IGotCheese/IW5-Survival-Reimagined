// bpg_survival_feedback.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-16.
// !feedback <message> (alias !fb) — players leave feedback for the server owner.
// Plutonium IW5 GSC has NO file I/O (fopen is a COMPILE-FATAL unknown builtin —
// probed 2026-07-16, Com_ERROR boot loop; never probe builtins on shared storage).
// So: feedback prints tagged [BPGFEEDBACK] lines to the server console log, and
// C:\Survival\tools\collect-feedback.ps1 (scheduled) archives them into
// C:\Survival\FEEDBACK.md before log rotation can eat them.
// Registered via ServerControl setCommand with argsIsMessage=true (whole-message
// dispatch path in commands.gsc onSay). Only proven builtins used (self.guid field,
// gettime, getdvar, println, tell — all used by the mod itself).
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	lethalbeats\servercontrol\commands::setCommand( "feedback", ::bpg_feedback_cmd, 0, 1, "^7Usage: ^3!feedback <your message>", undefined, undefined, true );
	lethalbeats\servercontrol\commands::setCommandAlias( "feedback", "fb" );

	level thread bpg_feedback_announce();
}

// argsIsMessage dispatch signature: (validMsg, invalidMsg, args[])
bpg_feedback_cmd( validMsg, invalidMsg, args )
{
	if ( self isTestClient() )
		return;

	if ( isDefined( self.bpg_fb_next ) && getTime() < self.bpg_fb_next )
	{
		self tell( "^1Easy there ^7- one piece of feedback every 15 seconds" );
		return;
	}

	text = "";
	for ( i = 0; i < args.size; i++ )
	{
		if ( !isDefined( args[ i ] ) )
			continue;
		if ( text != "" )
			text += " ";
		text += args[ i ];
	}

	if ( text == "" )
	{
		self tell( "^7Usage: ^3!feedback <your message>" );
		return;
	}

	if ( text.size > 220 )
		text = getSubStr( text, 0, 220 );

	self.bpg_fb_next = getTime() + 15000;

	guid = "unknown";
	if ( isDefined( self.guid ) )
		guid = "" + self.guid;

	println( "[BPGFEEDBACK] " + self.name + " | " + guid + " | " + getDvar( "mapname" ) + " | " + text );
	self tell( "^2Feedback recorded ^7- thanks! The owner reads every message." );
}

// let players know the command exists, once per map
bpg_feedback_announce()
{
	level endon( "game_ended" );

	level waittill( "wave_start" );
	wait 20;
	iprintln( "^7Got suggestions or found a bug? ^3!feedback <message>" );
}
