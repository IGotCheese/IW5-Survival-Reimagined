// yourserver.gg CRANKED -- dvar-gated overlay on a stock gametype (the vote runs it on TDM).
// Rebuilt from LastDemon99's TestModes crank.gsc (a private-match-only custom
// gametype; custom gametype codes never engage on a Plutonium dedicated server).
// Rules: get a kill -> a fuse starts (bpg_crank_time, default 30s) and you move
// faster; every kill refreshes the fuse; if it hits zero you explode.
// Activation: seta bpg_mode_cranked 1 before map load (the mapvote sets/clears it).
// Kill detection: per-player "killed_enemy" notify -- the same hook the proven
// gun_game overlay on this server uses (no gametype callback wrapping needed).
#include common_scripts\utility;
#include maps\mp\_utility;

init()
{
    if ( getdvarint( "bpg_mode_cranked" ) != 1 )
        return;

    // one-shot: consume the flag so the mode NEVER leaks into the next map if the
    // rotation advances without a vote (manual rcon loads, map_restart, crashes)
    setdvar( "bpg_mode_cranked", 0 );

    if ( getdvar( "bpg_crank_time" ) == "" )
        setdvar( "bpg_crank_time", 30 );

    level thread bpg_crank_connects();
    level thread bpg_crank_announce();
    level thread bpg_crank_modelabel();
}

bpg_crank_announce()
{
    level endon( "game_ended" );
    level waittill( "prematch_over" );
    iprintlnbold( "^3CRANKED^7: a kill arms your fuse -- keep killing or ^1EXPLODE" );
}

bpg_crank_connects()
{
    level endon( "game_ended" );

    for (;;)
    {
        level waittill( "connected", player );
        player thread bpg_crank_onkill();
        player thread bpg_crank_ondeath();
    }
}

bpg_crank_onkill()
{
    self endon( "disconnect" );
    level endon( "game_ended" );

    for (;;)
    {
        self waittill( "killed_enemy" );

        if ( !isalive( self ) )
            continue;

        // collapse the running fuse (if any) and start a fresh one
        self notify( "bpg_crank_refresh" );
        self thread bpg_crank_fuse();
        bpg_crank_diag( "bpg_crank: " + self.name + " armed/refreshed" );
    }
}

bpg_crank_ondeath()
{
    self endon( "disconnect" );
    level endon( "game_ended" );

    for (;;)
    {
        self waittill( "death" );

        if ( isdefined( self.bpg_crank_hudtimer ) )
            self.bpg_crank_hudtimer.alpha = 0;

        if ( isdefined( self.bpg_crank_hudlabel ) )
            self.bpg_crank_hudlabel.alpha = 0;
    }
}

bpg_crank_fuse()
{
    self endon( "disconnect" );
    self endon( "death" );
    self endon( "bpg_crank_refresh" );
    level endon( "game_ended" );

    // cranked players move faster; giveLoadout resets the scaler on next spawn
    self.moveSpeedScaler = 1.12;
    self maps\mp\gametypes\_weapons::updateMoveSpeedScale();

    if ( !self bpg_crank_isbot() )
        self thread bpg_crank_hud();

    self bpg_crank_localsound( "recondrone_tag" );
    time = getdvarint( "bpg_crank_time" );

    while ( time > 0 )
    {
        if ( time <= 5 )
            self bpg_crank_localsound( "scrambler_beep" );

        wait 1;
        time--;
    }

    // fuse expired -> boom
    if ( isdefined( self.bpg_crank_hudtimer ) )
        self.bpg_crank_hudtimer.alpha = 0;

    if ( isdefined( self.bpg_crank_hudlabel ) )
        self.bpg_crank_hudlabel.alpha = 0;

    if ( soundexists( "detpack_explo_default" ) )
        playsoundatpos( self.origin, "detpack_explo_default" );

    earthquake( 0.4, 1, self.origin, 800 );
    bpg_crank_diag( "bpg_crank: " + self.name + " EXPLODED (fuse expired)" );
    self suicide();
}

bpg_crank_hud()
{
    self endon( "disconnect" );
    self endon( "death" );
    self endon( "bpg_crank_refresh" );
    level endon( "game_ended" );

    // create the two elems ONCE per player and toggle alpha afterwards --
    // per-spawn hud churn has broken other per-player trackers on this server
    if ( !isdefined( self.bpg_crank_hudlabel ) )
    {
        self.bpg_crank_hudlabel = maps\mp\gametypes\_hud_util::createFontString( "objective", 0.9 );
        self.bpg_crank_hudlabel maps\mp\gametypes\_hud_util::setPoint( "CENTER", "CENTER", -150, 52 );
        self.bpg_crank_hudlabel settext( "^3CRANKED" );
        self.bpg_crank_hudlabel.sort = 10000;
        self.bpg_crank_hudlabel.hidewheninmenu = 1;
    }

    if ( !isdefined( self.bpg_crank_hudtimer ) )
    {
        self.bpg_crank_hudtimer = maps\mp\gametypes\_hud_util::createFontString( "objective", 1.5 );
        self.bpg_crank_hudtimer maps\mp\gametypes\_hud_util::setPoint( "CENTER", "CENTER", -150, 34 );
        self.bpg_crank_hudtimer.sort = 10000;
        self.bpg_crank_hudtimer.hidewheninmenu = 1;
    }

    self.bpg_crank_hudtimer settenthstimer( getdvarint( "bpg_crank_time" ) );
    self.bpg_crank_hudtimer.color = ( 1, 0.4, 0.2 );
    self.bpg_crank_hudtimer.alpha = 1;
    self.bpg_crank_hudlabel.alpha = 1;
}

bpg_crank_localsound( alias )
{
    if ( soundexists( alias ) )
        self playlocalsound( alias );
}

bpg_crank_isbot()
{
    return ( isdefined( self.pers["isBot"] ) && self.pers["isBot"] );
}

bpg_crank_diag( s )
{
	if ( isdefined( level.bot_builtins ) && isdefined( level.bot_builtins["printconsole"] ) )
		[[ level.bot_builtins["printconsole"] ]]( s );
}
bpg_crank_modelabel()
{
	level endon( "game_ended" );

	// the LOADING screen says "Team Deathmatch" (the engine names the underlying
	// war ruleset; client-side text we can't reach) -- so brand everything after
	// load: scoreboard team names + a persistent on-screen mode tag for everyone.
	game["strings"]["allies_name"] = "CRANKED";
	game["strings"]["axis_name"] = "CRANKED";

	level waittill( "prematch_over" );

	label = newhudelem();
	label.horzalign = "right";
	label.vertalign = "top";
	label.alignx = "right";
	label.aligny = "top";
	label.x = -12;
	label.y = 104;
	label.font = "objective";
	label.fontscale = 1.0;
	label.color = ( 1, 0.75, 0.2 );
	label.alpha = 0.75;
	label.sort = 9999;
	label.hidewheninmenu = 1;
	label settext( "CRANKED" );

	level waittill( "game_ended" );
	label destroy();
}