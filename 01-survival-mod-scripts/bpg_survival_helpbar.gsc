// bpg_survival_helpbar.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-16.
// User request: persistent text below the minimap showing the chat commands,
// like the main server's welcome message. One rotating line per player (rotating
// because all commands don't fit on one line at readable size). Players kept
// typing "!pay 500 all" — the bar teaches the real syntax.
// Uses stock _hud_util createFontString/setPoint (the vote HUD already proves
// plain-string setText works on Plutonium). Client-owned elems die with the
// client on disconnect; "hidewheninmenu" keeps the shop screens clean.
// ⚠️ NEVER copy to the live <MP-PORT> server (references nothing live has, but still).

#include maps\mp\gametypes\_hud_util;

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	level thread bpg_helpbar_watcher();
}

bpg_helpbar_watcher()
{
	level endon( "game_ended" );

	for ( ;; )
	{
		level waittill( "connected", player );
		if ( !player isTestClient() )
			player thread bpg_helpbar_player();
	}
}

bpg_helpbar_player()
{
	self endon( "disconnect" );
	level endon( "game_ended" );

	// wait for first spawn so the HUD has a canvas
	self waittill( "spawned_player" );
	wait 2;

	if ( isDefined( self.bpg_helpbar ) )
		return; // already created (spawned_player fires every respawn)

	// whole message ORANGE via the elem color (no chat code for orange);
	// small font + short strings so nothing extends past the minimap width.
	// Position: right above the challenges list ("Multi Kill", "Shotgun Kill").
	// Its exact coords live in the mod's compiled menu, so the position is
	// dvar-tunable live:  set bpg_helpbar_x 6 / set bpg_helpbar_y 146
	// (re-read every rotation tick — nudge while watching the screen)
	if ( getDvar( "bpg_helpbar_x" ) == "" ) setDvar( "bpg_helpbar_x", "6" );
	if ( getDvar( "bpg_helpbar_y" ) == "" ) setDvar( "bpg_helpbar_y", "374" ); // just above the challenges list (SHOTGUN KILL / DOUBLE KILL)

	bar = self createFontString( "hudsmall", 0.65 );
	bar setPoint( "TOPLEFT", "TOPLEFT", getDvarInt( "bpg_helpbar_x" ), getDvarInt( "bpg_helpbar_y" ) );
	bar.color = ( 1, 0, 0 ); // bright red
	bar.alpha = 1;
	bar.hidewheninmenu = true;
	bar.archived = false;
	self.bpg_helpbar = bar;

	msgs = [];
	msgs[ 0 ] = "help=!h = all commands";
	msgs[ 1 ] = "pay=!p <name> <amount>";
	msgs[ 2 ] = "feedback=!fb <message>";
	msgs[ 3 ] = "F5 = skip intermission";
	msgs[ 4 ] = "vote map + difficulty";
	msgs[ 5 ] = "!afk = 10 min safe mode";
	msgs[ 6 ] = "stuck=!sk = escape geometry";
	msgs[ 7 ] = "discord=!dc = join us";

	i = 0;
	for ( ;; )
	{
		self.bpg_helpbar setPoint( "TOPLEFT", "TOPLEFT", getDvarInt( "bpg_helpbar_x" ), getDvarInt( "bpg_helpbar_y" ) );
		self.bpg_helpbar setText( msgs[ i ] );
		i = ( i + 1 ) % msgs.size;
		wait 8;
	}
}
