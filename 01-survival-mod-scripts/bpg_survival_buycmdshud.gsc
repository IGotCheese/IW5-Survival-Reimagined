// bpg_survival_buycmdshud.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-19.
// User: "show the ammo, bank, armor, and revive buy commands on the top of the screen
// centered in red." Persistent reminder of the four paid commands (confirmed exact command
// strings via lethalbeats\servercontrol\commands::setCommand registrations in
// scripts/bpg_survival_bankcmds.gsc: !buyammo, !bank, !buyarmor, !buyrevive).
// Same createFontString+setPoint+setText pattern as scripts/bpg_survival_killlog.gsc's
// enemies-remaining counter, and the same red (1,0,0) convention as
// scripts/bpg_survival_scorepopup_red.gsc. Position is dvar-tunable live:
//   set bpg_buycmdshud_x 0 / set bpg_buycmdshud_y 4
//
// 2026-07-19: built idempotent from the start (destroy-then-recreate before assigning new
// elements) — this exact same "connected re-fires across map changes, player-vars don't
// reliably survive the transition, boolean build-once guard leaks a hudElem/configstring per
// surviving player per map change" bug was just found and fixed in bpg_survival_killlog.gsc
// (see that file's history + the gsc-code-quality-practices memory) — no reason to reintroduce
// it here just because this element is static text with no render loop.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

#include maps\mp\gametypes\_hud_util;
#include common_scripts\utility;

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	if ( getDvar( "bpg_buycmdshud_x" ) == "" ) setDvar( "bpg_buycmdshud_x", "0" );
	if ( getDvar( "bpg_buycmdshud_y" ) == "" ) setDvar( "bpg_buycmdshud_y", "4" );

	level thread bpg_buycmdshud_watcher();

	// 2026-07-27: user - "do not delete these as these are the in match huds. just make it so
	// these dont show after the match ends". The four buy commands are dead weight once the
	// round is over, and the element was printing straight through the vote screen's CLUB
	// SERVER header. Armed per map because init() re-runs on every map load.
	level thread bpg_buycmdshud_matchend( "vote_start" );
	level thread bpg_buycmdshud_matchend( "game_ended" );
}

// Tears the HUD down at match end. Driven from level scope rather than per-player so there is
// a single owner doing the destroy - a player-side thread waiting on the same notify it also
// endon'd would be killed before it could clean up.
// "vote_start" is what actually raises the vote screen (bpg_survival_votesystem.gsc:215);
// "game_ended" covers a match that ends without a vote. Both are idempotent - whichever fires
// first clears the element and the other finds nothing to do.
bpg_buycmdshud_matchend( notifyName )
{
	level waittill( notifyName );

	foreach ( player in level.players )
	{
		// kill that player's position watcher FIRST, otherwise its next setPoint lands on a
		// destroyed element and throws
		player notify( "bpg_buycmdshud_restart" );

		if ( isDefined( player.bpg_buycmdshud ) )
		{
			player.bpg_buycmdshud destroy();
			player.bpg_buycmdshud = undefined;
		}
	}
}

bpg_buycmdshud_watcher()
{
	level endon( "game_ended" );

	for ( ;; )
	{
		level waittill( "connected", player );
		if ( !player isTestClient() )
			player thread bpg_buycmdshud_player();
	}
}

bpg_buycmdshud_player()
{
	self notify( "bpg_buycmdshud_restart" );
	self endon( "bpg_buycmdshud_restart" );
	self endon( "disconnect" );
	level endon( "game_ended" );

	self waittill( "spawned_player" );
	wait 2;

	if ( isDefined( self.bpg_buycmdshud ) )
		self.bpg_buycmdshud destroy();

	h = self createFontString( "hudsmall", 1.2 );
	h setPoint( "TOP", "TOP", getDvarInt( "bpg_buycmdshud_x" ), getDvarInt( "bpg_buycmdshud_y" ) );
	h.color = ( 1, 0, 0 );
	h.alpha = 1;
	h.hidewheninmenu = true;
	h.archived = false;
	h setText( "buyammo=!ba   bank=!b   buyarmor=!bar   buyrevive=!br" );
	self.bpg_buycmdshud = h;

	self thread bpg_buycmdshud_position_watch();
}

// keeps the position live-tunable without a restart, matching the killlog HUD's convention
bpg_buycmdshud_position_watch()
{
	self endon( "bpg_buycmdshud_restart" );
	self endon( "disconnect" );
	level endon( "game_ended" );

	for ( ;; )
	{
		self.bpg_buycmdshud setPoint( "TOP", "TOP", getDvarInt( "bpg_buycmdshud_x" ), getDvarInt( "bpg_buycmdshud_y" ) );
		wait 1;
	}
}
