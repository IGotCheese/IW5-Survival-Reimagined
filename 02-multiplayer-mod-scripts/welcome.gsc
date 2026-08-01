/*
    welcome.gsc - Your Server persistent server description.
    Static 3-line HUD message anchored top-left, stays on screen the whole match.
    Position/size driven by dvars and applied AT CREATION (reliable). To retune:
        rcon set welcome_x N   (negative = further left, past the safe area)
        rcon set welcome_y N   (smaller = higher)
        rcon set welcome_gap N (line spacing)
        rcon set welcome_scale N
    then die once so the HUD rebuilds at the new position.
    Auto-loaded by the Plutonium IW5 GSC loader via init().
    Save UTF-8 WITHOUT BOM or GSC compilation breaks.
*/

init()
{
    // Loadscreen MOTD (shows below the loading bar). Re-applied here EVERY map
    // because Com_Restart wipes sv_motd on map load (same reason mapvote.gsc
    // re-applies sv_wwwBaseURL) -> without this it falls back to the default tips.
    setDvar( "sv_motd", "Join discord: ^5yourserver.gg^7   |   Type ^3#help^7 for commands" );

    if ( getDvar( "welcome_x" )     == "" ) setDvar( "welcome_x",     "-60" );
    if ( getDvar( "welcome_y" )     == "" ) setDvar( "welcome_y",     "70" );
    if ( getDvar( "welcome_gap" )   == "" ) setDvar( "welcome_gap",   "18"  );
    if ( getDvar( "welcome_scale" ) == "" ) setDvar( "welcome_scale", "1.4" );

    level thread onPlayerConnect();
}

onPlayerConnect()
{
    for ( ;; )
    {
        level waittill( "connected", player );
        player thread welcomeOnSpawn();
    }
}

welcomeOnSpawn()
{
    self endon( "disconnect" );

    for ( ;; )
    {
        self waittill( "spawned_player" );
        self buildWelcomeHud();
    }
}

buildWelcomeHud()
{
    if ( isDefined( self.welcomeHud ) )
    {
        for ( i = 0; i < self.welcomeHud.size; i++ )
            if ( isDefined( self.welcomeHud[i] ) )
                self.welcomeHud[i] destroy();
    }
    self.welcomeHud = [];

    x     = getDvarInt( "welcome_x" );
    y     = getDvarInt( "welcome_y" );
    gap   = getDvarInt( "welcome_gap" );
    scale = getDvarFloat( "welcome_scale" );

    lines = [];
    lines[0] = "Join ^5yourserver.gg^7 for discord";
    lines[1] = "Have Fun";
    for ( i = 0; i < lines.size; i++ )
    {
        hud = newClientHudElem( self );
        hud.horzAlign  = "left";
        hud.vertAlign  = "top";
        hud.alignX     = "left";
        hud.alignY     = "top";
        hud.x          = x;
        hud.y          = y + ( i * gap );
        hud.font       = "default";
        hud.fontScale  = scale;
        hud.foreground = true;
        hud.alpha      = 1;
        hud setText( lines[i] );
        self.welcomeHud[i] = hud;
    }
}
