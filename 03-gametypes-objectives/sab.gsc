// IW5 GSC SOURCE
// Decompiled by https://github.com/xensik/gsc-tool

main()
{
    if ( getdvar( "mapname" ) == "mp_background" )
        return;

    maps\mp\gametypes\_globallogic::init();
    maps\mp\gametypes\_callbacksetup::setupcallbacks();
    maps\mp\gametypes\_globallogic::setupcallbacks();
    level.teambased = 1;

    if ( isusingmatchrulesdata() )
    {
        level.initializematchrules = ::initializematchrules;
        [[ level.initializematchrules ]]();
        level thread maps\mp\_utility::reinitializematchrulesonmigration();
    }
    else
    {
        maps\mp\_utility::registerroundswitchdvar( level.gametype, 0, 0, 9 );
        maps\mp\_utility::registertimelimitdvar( level.gametype, 10 );
        maps\mp\_utility::registerscorelimitdvar( level.gametype, 0 );
        maps\mp\_utility::registerroundlimitdvar( level.gametype, 1 );
        maps\mp\_utility::registerwinlimitdvar( level.gametype, 1 );
        maps\mp\_utility::registernumlivesdvar( level.gametype, 0 );
        maps\mp\_utility::registerhalftimedvar( level.gametype, 0 );
        level.matchrules_damagemultiplier = 0;
        level.matchrules_vampirism = 0;
    }

    maps\mp\_utility::setovertimelimitdvar( 2 );
    setspecialloadouts();
    level.onprecachegametype = ::onprecachegametype;
    level.onstartgametype = ::onstartgametype;
    level.getspawnpoint = ::getspawnpoint;
    level.onspawnplayer = ::onspawnplayer;
    level.ononeleftevent = ::ononeleftevent;
    level.ontimelimit = ::ontimelimit;
    level.onnormaldeath = ::onnormaldeath;
    level.initgametypeawards = ::initgametypeawards;

    if ( level.matchrules_damagemultiplier || level.matchrules_vampirism )
        level.modifyplayerdamage = maps\mp\gametypes\_damage::gamemodemodifyplayerdamage;

    game["dialog"]["gametype"] = "sabotage";

    if ( getdvarint( "g_hardcore" ) )
        game["dialog"]["gametype"] = "hc_" + game["dialog"]["gametype"];
    else if ( getdvarint( "camera_thirdPerson" ) )
        game["dialog"]["gametype"] = "thirdp_" + game["dialog"]["gametype"];
    else if ( getdvarint( "scr_diehard" ) )
        game["dialog"]["gametype"] = "dh_" + game["dialog"]["gametype"];
    else if ( getdvarint( "scr_" + level.gametype + "_promode" ) )
        game["dialog"]["gametype"] += "_pro";

    game["dialog"]["offense_obj"] = "capture_obj";
    game["dialog"]["defense_obj"] = "capture_obj";
    var_0 = getent( "sab_bomb_defuse_allies", "targetname" );

    if ( isdefined( var_0 ) )
        var_0 delete();

    var_0 = getent( "sab_bomb_defuse_axis", "targetname" );

    if ( isdefined( var_0 ) )
        var_0 delete();

    makedvarserverinfo( "ui_bomb_timer_endtime", -1 );
}

initializematchrules()
{
    maps\mp\_utility::setcommonrulesfrommatchrulesdata();
    setdynamicdvar( "scr_sab_bombtimer", getmatchrulesdata( "sabData", "bombTimer" ) );
    setdynamicdvar( "scr_sab_planttime", getmatchrulesdata( "sabData", "plantTime" ) );
    setdynamicdvar( "scr_sab_defusetime", getmatchrulesdata( "sabData", "defuseTime" ) );
    setdynamicdvar( "scr_sab_hotpotato", getmatchrulesdata( "sabData", "sharedBombTimer" ) );
    setdynamicdvar( "scr_sab_roundswitch", 1 );
    maps\mp\_utility::registerroundswitchdvar( "sab", 1, 0, 9 );
    setdynamicdvar( "scr_sab_roundlimit", 1 );
    maps\mp\_utility::registerroundlimitdvar( "sab", 1 );
    setdynamicdvar( "scr_sab_winlimit", 1 );
    maps\mp\_utility::registerwinlimitdvar( "sab", 1 );
    setdynamicdvar( "scr_sab_halftime", 0 );
    maps\mp\_utility::registerhalftimedvar( "sab", 0 );
    setdynamicdvar( "scr_sab_promode", 0 );
}

onprecachegametype()
{
    game["bomb_dropped_sound"] = "mp_war_objective_lost";
    game["bomb_recovered_sound"] = "mp_war_objective_taken";
    precacheshader( "waypoint_bomb" );
    precacheshader( "waypoint_kill" );
    precacheshader( "waypoint_bomb_enemy" );
    precacheshader( "waypoint_defend" );
    precacheshader( "waypoint_defuse" );
    precacheshader( "waypoint_target" );
    precacheshader( "waypoint_escort" );
    precacheshader( "waypoint_bomb" );
    precacheshader( "waypoint_defend" );
    precacheshader( "waypoint_defuse" );
    precacheshader( "waypoint_target" );
    precacheshader( "hud_suitcase_bomb" );
    precachestring( &"MP_EXPLOSIVES_RECOVERED_BY" );
    precachestring( &"MP_EXPLOSIVES_DROPPED_BY" );
    precachestring( &"MP_EXPLOSIVES_PLANTED_BY" );
    precachestring( &"MP_EXPLOSIVES_DEFUSED_BY" );
    precachestring( &"MP_YOU_HAVE_RECOVERED_THE_BOMB" );
    precachestring( &"PLATFORM_HOLD_TO_PLANT_EXPLOSIVES" );
    precachestring( &"PLATFORM_HOLD_TO_DEFUSE_EXPLOSIVES" );
    precachestring( &"MP_PLANTING_EXPLOSIVE" );
    precachestring( &"MP_DEFUSING_EXPLOSIVE" );
    precachestring( &"MP_TARGET_DESTROYED" );
    precachestring( &"MP_NO_RESPAWN" );
    precachestring( &"MP_TIE_BREAKER" );
    precachestring( &"MP_NO_RESPAWN" );
    precachestring( &"MP_SUDDEN_DEATH" );
}

onstartgametype()
{
    if ( !isdefined( game["switchedsides"] ) )
        game["switchedsides"] = 0;

    setclientnamemode( "auto_change" );
    game["strings"]["target_destroyed"] = &"MP_TARGET_DESTROYED";
    game["strings"]["target_defended"] = &"MP_TARGET_DEDEFEND";
    maps\mp\_utility::setobjectivetext( "allies", &"OBJECTIVES_SAB" );
    maps\mp\_utility::setobjectivetext( "axis", &"OBJECTIVES_SAB" );

    if ( level.splitscreen )
    {
        maps\mp\_utility::setobjectivescoretext( "allies", &"OBJECTIVES_SAB" );
        maps\mp\_utility::setobjectivescoretext( "axis", &"OBJECTIVES_SAB" );
    }
    else
    {
        maps\mp\_utility::setobjectivescoretext( "allies", &"OBJECTIVES_SAB_SCORE" );
        maps\mp\_utility::setobjectivescoretext( "axis", &"OBJECTIVES_SAB_SCORE" );
    }

    maps\mp\_utility::setobjectivehinttext( "allies", &"OBJECTIVES_SAB_HINT" );
    maps\mp\_utility::setobjectivehinttext( "axis", &"OBJECTIVES_SAB_HINT" );
    level.spawnmins = ( 0.0, 0.0, 0.0 );
    level.spawnmaxs = ( 0.0, 0.0, 0.0 );
    sab_fixtunisia();
    sab_fix_mirage_n();
    sab_fix_toujane();
    sab_fix_boomtown();
    sab_fix_gulag();
    maps\mp\gametypes\_spawnlogic::placespawnpoints( "mp_sab_spawn_allies_start" );
    maps\mp\gametypes\_spawnlogic::placespawnpoints( "mp_sab_spawn_axis_start" );
    maps\mp\gametypes\_spawnlogic::addspawnpoints( "allies", "mp_sab_spawn_allies" );
    maps\mp\gametypes\_spawnlogic::addspawnpoints( "axis", "mp_sab_spawn_axis" );
    maps\mp\gametypes\_spawnlogic::addspawnpoints( "allies", "mp_sab_spawn_allies_planted", 1 );
    maps\mp\gametypes\_spawnlogic::addspawnpoints( "axis", "mp_sab_spawn_axis_planted", 1 );
    level.mapcenter = maps\mp\gametypes\_spawnlogic::findboxcenter( level.spawnmins, level.spawnmaxs );
    setmapcenter( level.mapcenter );
    level.spawn_axis = maps\mp\gametypes\_spawnlogic::getspawnpointarray( "mp_sab_spawn_axis" );
    level.spawn_axis_planted = maps\mp\gametypes\_spawnlogic::getspawnpointarray( "mp_sab_spawn_axis_planted" );
    level.spawn_axis_planted = common_scripts\utility::array_combine( level.spawn_axis_planted, level.spawn_axis );
    level.spawn_allies = maps\mp\gametypes\_spawnlogic::getspawnpointarray( "mp_sab_spawn_allies" );
    level.spawn_allies_planted = maps\mp\gametypes\_spawnlogic::getspawnpointarray( "mp_sab_spawn_allies_planted" );
    level.spawn_allies_planted = common_scripts\utility::array_combine( level.spawn_allies_planted, level.spawn_allies );
    level.spawn_axis_start = maps\mp\gametypes\_spawnlogic::getspawnpointarray( "mp_sab_spawn_axis_start" );
    level.spawn_allies_start = maps\mp\gametypes\_spawnlogic::getspawnpointarray( "mp_sab_spawn_allies_start" );
    maps\mp\gametypes\_rank::registerscoreinfo( "plant", 200 );
    maps\mp\gametypes\_rank::registerscoreinfo( "destroy", 1000 );
    maps\mp\gametypes\_rank::registerscoreinfo( "defuse", 150 );
    var_0[0] = "sab";
    maps\mp\gametypes\_gameobjects::main( var_0 );
    thread updategametypedvars();
    thread sabotage();
}

getspawnpoint()
{
    var_0 = self.pers["team"];

    if ( game["switchedsides"] )
        var_0 = maps\mp\_utility::getotherteam( var_0 );

    if ( level.usestartspawn )
    {
        if ( var_0 == "axis" )
            var_1 = maps\mp\gametypes\_spawnlogic::getspawnpoint_random( level.spawn_axis_start );
        else
            var_1 = maps\mp\gametypes\_spawnlogic::getspawnpoint_random( level.spawn_allies_start );
    }
    else if ( isdefined( level.bombplanted ) && level.bombplanted && ( isdefined( level.bombowner ) && var_0 == level.bombowner.team ) )
    {
        if ( var_0 == "axis" )
            var_1 = maps\mp\gametypes\_spawnlogic::getspawnpoint_nearteam( level.spawn_axis_planted );
        else
            var_1 = maps\mp\gametypes\_spawnlogic::getspawnpoint_nearteam( level.spawn_allies_planted );
    }
    else if ( var_0 == "axis" )
        var_1 = maps\mp\gametypes\_spawnlogic::getspawnpoint_nearteam( level.spawn_axis );
    else
        var_1 = maps\mp\gametypes\_spawnlogic::getspawnpoint_nearteam( level.spawn_allies );

    return var_1;
}

onspawnplayer()
{
    self.isplanting = 0;
    self.isdefusing = 0;
    self.isbombcarrier = 0;

    if ( maps\mp\_utility::inovertime() && !isdefined( self.otspawned ) )
        thread printothint();
}

printothint()
{
    self endon( "disconnect" );
    wait 0.25;
    thread maps\mp\gametypes\_hud_message::splashnotify( "sudden_death" );
    self.otspawned = 1;
}

updategametypedvars()
{
    level.planttime = maps\mp\_utility::dvarfloatvalue( "planttime", 5, 0, 20 );
    level.defusetime = maps\mp\_utility::dvarfloatvalue( "defusetime", 5, 0, 20 );
    level.bombtimer = maps\mp\_utility::dvarfloatvalue( "bombtimer", 45, 1, 300 );
    level.hotpotato = maps\mp\_utility::dvarintvalue( "hotpotato", 1, 0, 1 );

    // yourserver.gg: this server ships NO sabData match rules, so scr_sab_* come back empty and
    // dvarfloatvalue floors them to 0/1 - a 0s plant (instant, no hold bar) and a 1s fuse
    // (instant detonate). Restore stock SAB timing whenever the values come back broken.
    if ( level.planttime < 1 )
        level.planttime = 5;

    if ( level.defusetime < 1 )
        level.defusetime = 5;

    if ( level.bombtimer < 10 )
        level.bombtimer = 30;

    level.scoremode = maps\mp\_utility::getwatcheddvar( "scorelimit" );
}

sabotage()
{
    level.bombplanted = 0;
    level.bombexploded = 0;
    level._effect["bombexplosion"] = loadfx( "explosions/tanker_explosion" );
    var_0 = getent( "sab_bomb_pickup_trig", "targetname" );

    if ( !isdefined( var_0 ) )
    {
        common_scripts\utility::error( "No sab_bomb_pickup_trig trigger found in map." );
        return;
    }

    var_1[0] = getent( "sab_bomb", "targetname" );

    if ( !isdefined( var_1[0] ) )
    {
        common_scripts\utility::error( "No sab_bomb script_model found in map." );
        return;
    }

    precachemodel( "prop_suitcase_bomb" );
    var_1[0] setmodel( "prop_suitcase_bomb" );
    level.sabbomb = maps\mp\gametypes\_gameobjects::createcarryobject( "neutral", var_0, var_1, ( 0.0, 0.0, 32.0 ) );
    level.sabbomb maps\mp\gametypes\_gameobjects::allowcarry( "any" );
    level.sabbomb maps\mp\gametypes\_gameobjects::set2dicon( "enemy", "waypoint_bomb" );
    level.sabbomb maps\mp\gametypes\_gameobjects::set3dicon( "enemy", "waypoint_bomb" );
    level.sabbomb maps\mp\gametypes\_gameobjects::set2dicon( "friendly", "waypoint_bomb" );
    level.sabbomb maps\mp\gametypes\_gameobjects::set3dicon( "friendly", "waypoint_bomb" );
    level.sabbomb maps\mp\gametypes\_gameobjects::setcarryicon( "hud_suitcase_bomb" );
    level.sabbomb maps\mp\gametypes\_gameobjects::setvisibleteam( "any" );
    level.sabbomb.objidpingenemy = 1;
    level.sabbomb.onpickup = ::onpickup;
    level.sabbomb.ondrop = ::ondrop;
    level.sabbomb.allowweapons = 1;
    level.sabbomb.objpoints["allies"].archived = 1;
    level.sabbomb.objpoints["axis"].archived = 1;
    level.sabbomb.autoresettime = 60.0;

    if ( !isdefined( getent( "sab_bomb_axis", "targetname" ) ) )
    {
        common_scripts\utility::error( "No sab_bomb_axis trigger found in map." );
        return;
    }

    if ( !isdefined( getent( "sab_bomb_allies", "targetname" ) ) )
    {
        common_scripts\utility::error( "No sab_bomb_allies trigger found in map." );
        return;
    }

    if ( game["switchedsides"] )
    {
        level.bombzones["allies"] = createbombzone( "allies", getent( "sab_bomb_axis", "targetname" ) );
        level.bombzones["axis"] = createbombzone( "axis", getent( "sab_bomb_allies", "targetname" ) );
    }
    else
    {
        level.bombzones["allies"] = createbombzone( "allies", getent( "sab_bomb_allies", "targetname" ) );
        level.bombzones["axis"] = createbombzone( "axis", getent( "sab_bomb_axis", "targetname" ) );
    }

    if ( level.scoremode )
        level thread scorethread();

    if ( maps\mp\_utility::inovertime() )
        level thread overtimethread();
}

getclosestsite()
{
    if ( distance2d( self.origin, level.bombzones["allies"].trigger.origin ) < distance2d( self.origin, level.bombzones["axis"].trigger.origin ) )
        return "allies";
    else
        return "axis";
}

distancetosite( var_0 )
{
    return distance2d( self.origin, level.bombzones[var_0].trigger.origin );
}

scorethread()
{
    level.bombdistance = distance2d( getent( "sab_bomb_axis", "targetname" ) getorigin(), getent( "sab_bomb_allies", "targetname" ) getorigin() );
    var_0 = level.bombdistance / 2 - 384;
    var_1 = level.sabbomb.trigger;

    if ( var_0 > var_1 distancetosite( "allies" ) || var_0 > var_1 distancetosite( "axis" ) )
        var_0 = var_1 distancetosite( var_1 getclosestsite() ) - 128;

    var_2 = "";

    for (;;)
    {
        if ( isdefined( level.sabbomb.carrier ) )
            var_1 = level.sabbomb.carrier;
        else
            var_1 = level.sabbomb.trigger;

        var_3 = var_2;
        var_2 = "none";

        if ( var_1 distancetosite( "allies" ) < var_0 )
            var_2 = level.bombzones["allies"] maps\mp\gametypes\_gameobjects::getownerteam();
        else if ( var_1 distancetosite( "axis" ) < var_0 )
            var_2 = level.bombzones["axis"] maps\mp\gametypes\_gameobjects::getownerteam();
        else if ( var_1 distancetosite( "allies" ) > level.bombdistance && var_1 getclosestsite() != "allies" )
            var_2 = level.bombzones["axis"] maps\mp\gametypes\_gameobjects::getownerteam();
        else if ( var_1 distancetosite( "axis" ) > level.bombdistance && var_1 getclosestsite() != "axis" )
            var_2 = level.bombzones["allies"] maps\mp\gametypes\_gameobjects::getownerteam();

        if ( var_2 != "none" )
        {
            if ( !level.bombplanted || !maps\mp\_utility::getwatcheddvar( "scorelimit" ) || level.bombplanted && maps\mp\gametypes\_gamescore::_getteamscore( level.otherteam[var_2] ) < maps\mp\_utility::getwatcheddvar( "scorelimit" ) - 1 )
            {
                maps\mp\gametypes\_gamescore::_setteamscore( level.otherteam[var_2], maps\mp\gametypes\_gamescore::_getteamscore( level.otherteam[var_2] ) + 1 );
                maps\mp\gametypes\_gamescore::updateteamscore( level.otherteam[var_2] );
            }
        }

        if ( var_2 != var_3 && !level.bombexploded )
            setdvar( "ui_danger_team", var_2 );

        wait 2.5;
    }
}

createbombzone( var_0, var_1 )
{
    var_2 = getentarray( var_1.target, "targetname" );

    // mp_osg_mirage_n ships no sab_bomb_axis/allies, so we script-spawn them as
    // trigger_radius (the only scriptable trigger). But stock createuseobject routes
    // by classname - "trigger_radius" -> proximity/auto-capture, NOT the hold-[use]
    // plant. classname is engine-read-only, so we can't fake "use" on the entity;
    // instead route these spawned triggers through a forced-USE createuseobject copy.
    if ( level.script == "mp_osg_mirage_n" || level.script == "mp_toujane" || level.script == "mp_boomtown" || level.script == "mp_gulag" )
        var_3 = bpg_sab_createuseobject_use( var_0, var_1, var_2, ( 0.0, 0.0, 64.0 ) );
    else
        var_3 = maps\mp\gametypes\_gameobjects::createuseobject( var_0, var_1, var_2, ( 0.0, 0.0, 64.0 ) );

    var_3 resetbombsite();
    var_3.onuse = ::onuse;
    var_3.onbeginuse = ::onbeginuse;
    var_3.onenduse = ::onenduse;
    var_3.oncantuse = ::oncantuse;
    var_3.useweapon = "briefcase_bomb_mp";

    for ( var_4 = 0; var_4 < var_2.size; var_4++ )
    {
        if ( isdefined( var_2[var_4].script_exploder ) )
        {
            var_3.exploderindex = var_2[var_4].script_exploder;
            var_2[var_4] thread setupkillcament();
            break;
        }
    }

    return var_3;
}

setupkillcament()
{
    var_0 = spawn( "script_origin", self.origin );
    var_0.angles = self.angles;
    var_0 rotateyaw( -45, 0.05 );
    wait 0.05;
    var_1 = self.origin + ( 0.0, 0.0, 5.0 );
    var_2 = self.origin + anglestoforward( var_0.angles ) * 100 + ( 0.0, 0.0, 128.0 );
    var_3 = bullettrace( var_1, var_2, 0, self );
    self.killcament = spawn( "script_model", var_3["position"] );
    self.killcament setscriptmoverkillcam( "explosive" );
    var_0 delete();
}

onbeginuse( var_0 )
{
    if ( !maps\mp\gametypes\_gameobjects::isfriendlyteam( var_0.pers["team"] ) )
        var_0.isplanting = 1;
    else
        var_0.isdefusing = 1;
}

onenduse( var_0, var_1, var_2 )
{
    if ( !isalive( var_1 ) )
        return;

    var_1.isplanting = 0;
    var_1.isdefusing = 0;
}

onpickup( var_0 )
{
    level notify( "bomb_picked_up" );
    self.autoresettime = 60.0;
    level.usestartspawn = 0;
    var_1 = var_0.pers["team"];

    if ( var_1 == "allies" )
        var_2 = "axis";
    else
        var_2 = "allies";

    var_0 playlocalsound( "mp_suitcase_pickup" );
    var_0 maps\mp\_utility::leaderdialogonplayer( "obj_destroy", "bomb" );
    var_3[0] = var_0;
    maps\mp\_utility::leaderdialog( "bomb_taken", var_1, "bomb", var_3 );

    if ( !level.splitscreen )
    {
        maps\mp\_utility::leaderdialog( "bomb_lost", var_2, "bomb" );
        maps\mp\_utility::leaderdialog( "obj_defend", var_2, "bomb" );
    }

    var_0.isbombcarrier = 1;

    if ( isdefined( level.sab_loadouts ) && isdefined( level.sab_loadouts[var_1] ) )
        var_0 thread applybombcarrierclass();

    if ( var_1 == maps\mp\gametypes\_gameobjects::getownerteam() )
        maps\mp\_utility::playsoundonplayers( game["bomb_recovered_sound"], var_1 );
    else
        maps\mp\_utility::playsoundonplayers( game["bomb_recovered_sound"] );

    maps\mp\gametypes\_gameobjects::setownerteam( var_1 );
    maps\mp\gametypes\_gameobjects::setvisibleteam( "any" );
    maps\mp\gametypes\_gameobjects::set2dicon( "enemy", "waypoint_target" );
    maps\mp\gametypes\_gameobjects::set3dicon( "enemy", "waypoint_kill" );
    maps\mp\gametypes\_gameobjects::set2dicon( "friendly", "waypoint_escort" );
    maps\mp\gametypes\_gameobjects::set3dicon( "friendly", "waypoint_escort" );
    level.bombzones[var_1] maps\mp\gametypes\_gameobjects::setvisibleteam( "none" );
    level.bombzones[var_2] maps\mp\gametypes\_gameobjects::setvisibleteam( "any" );
    var_0 maps\mp\_utility::incplayerstat( "bombscarried", 1 );
    var_0 thread maps\mp\_matchdata::loggameevent( "pickup", var_0.origin );
}

ondrop( var_0 )
{
    if ( level.bombplanted )
        return;

    if ( isdefined( var_0 ) )
        maps\mp\_utility::printonteamarg( &"MP_EXPLOSIVES_DROPPED_BY", maps\mp\gametypes\_gameobjects::getownerteam(), var_0 );

    maps\mp\_utility::playsoundonplayers( game["bomb_dropped_sound"], maps\mp\gametypes\_gameobjects::getownerteam() );
    thread abandonmentthink( 0.0 );
    return;
}

abandonmentthink( var_0 )
{
    level endon( "bomb_picked_up" );
    wait(var_0);

    if ( isdefined( self.carrier ) )
        return;

    if ( maps\mp\gametypes\_gameobjects::getownerteam() == "allies" )
        var_1 = "axis";
    else
        var_1 = "allies";

    maps\mp\_utility::playsoundonplayers( game["bomb_dropped_sound"], var_1 );
    maps\mp\gametypes\_gameobjects::setownerteam( "neutral" );
    maps\mp\gametypes\_gameobjects::setvisibleteam( "any" );
    maps\mp\gametypes\_gameobjects::set2dicon( "enemy", "waypoint_bomb" );
    maps\mp\gametypes\_gameobjects::set3dicon( "enemy", "waypoint_bomb" );
    maps\mp\gametypes\_gameobjects::set2dicon( "friendly", "waypoint_bomb" );
    maps\mp\gametypes\_gameobjects::set3dicon( "friendly", "waypoint_bomb" );
    level.bombzones["allies"] maps\mp\gametypes\_gameobjects::setvisibleteam( "none" );
    level.bombzones["axis"] maps\mp\gametypes\_gameobjects::setvisibleteam( "none" );
}

onuse( var_0 )
{
    var_1 = var_0.pers["team"];
    var_2 = level.otherteam[var_1];

    if ( !maps\mp\gametypes\_gameobjects::isfriendlyteam( var_0.pers["team"] ) )
    {
        var_0 notify( "bomb_planted" );
        var_0 notify( "objective", "plant" );
        var_0 playsound( "mp_bomb_plant" );
        level thread maps\mp\_utility::teamplayercardsplash( "callout_bombplanted", var_0 );
        maps\mp\_utility::leaderdialog( "bomb_planted" );
        var_0 thread maps\mp\gametypes\_hud_message::splashnotify( "plant", maps\mp\gametypes\_rank::getscoreinfovalue( "plant" ) );
        var_0 thread maps\mp\gametypes\_rank::giverankxp( "plant" );
        maps\mp\gametypes\_gamescore::giveplayerscore( "plant", var_0 );
        var_0 maps\mp\_utility::incplayerstat( "bombsplanted", 1 );
        var_0 thread maps\mp\_matchdata::loggameevent( "plant", var_0.origin );
        var_0.bombplantedtime = gettime();
        var_0 maps\mp\_utility::incpersstat( "plants", 1 );
        var_0 maps\mp\gametypes\_persistence::statsetchild( "round", "plants", var_0.pers["plants"] );
        level thread bombplanted( self, var_0.pers["team"] );
        level.bombowner = var_0;

        if ( isdefined( level.sab_loadouts ) && isdefined( level.sab_loadouts[var_1] ) )
            var_0 thread removebombcarrierclass();

        level.sabbomb.autoresettime = undefined;
        level.sabbomb maps\mp\gametypes\_gameobjects::allowcarry( "none" );
        level.sabbomb maps\mp\gametypes\_gameobjects::setvisibleteam( "none" );
        level.sabbomb maps\mp\gametypes\_gameobjects::setdropped();
        self.useweapon = "briefcase_bomb_defuse_mp";
        setupfordefusing();
    }
    else
    {
        var_0 notify( "bomb_defused" );
        var_0 notify( "objective", "defuse" );
        maps\mp\_utility::leaderdialog( "bomb_defused" );
        level thread maps\mp\_utility::teamplayercardsplash( "callout_bombdefused", var_0 );

        if ( isdefined( level.bombowner ) && level.bombowner.bombplantedtime + 3000 + level.defusetime * 1000 > gettime() && maps\mp\_utility::isreallyalive( level.bombowner ) )
            var_0 thread maps\mp\gametypes\_hud_message::splashnotify( "ninja_defuse", maps\mp\gametypes\_rank::getscoreinfovalue( "defuse" ) );
        else
            var_0 thread maps\mp\gametypes\_hud_message::splashnotify( "defuse", maps\mp\gametypes\_rank::getscoreinfovalue( "defuse" ) );

        var_0 thread maps\mp\gametypes\_rank::giverankxp( "defuse" );
        maps\mp\gametypes\_gamescore::giveplayerscore( "defuse", var_0 );
        var_0 maps\mp\_utility::incpersstat( "defuses", 1 );
        var_0 maps\mp\gametypes\_persistence::statsetchild( "round", "defuses", var_0.pers["defuses"] );
        var_0 thread maps\mp\_matchdata::loggameevent( "defuse", var_0.origin );

        if ( maps\mp\_utility::inovertime() )
        {
            level.finalkillcam_winner = var_1;
            thread maps\mp\gametypes\_gamelogic::endgame( var_1, game["strings"]["target_destroyed"] );
            return;
        }

        level thread bombdefused( self );
        resetbombsite();
        level.sabbomb maps\mp\gametypes\_gameobjects::allowcarry( "any" );
        level.sabbomb maps\mp\gametypes\_gameobjects::setpickedup( var_0 );
    }
}

applybombcarrierclass()
{
    self endon( "death" );
    self endon( "disconnect" );
    level endon( "game_ended" );

    if ( isdefined( self.iscarrying ) && self.iscarrying == 1 )
    {
        self notify( "force_cancel_placement" );
        wait 0.05;
    }

    if ( maps\mp\_utility::isjuggernaut() )
    {
        self notify( "lost_juggernaut" );
        wait 0.05;
    }

    self.pers["gamemodeLoadout"] = level.sab_loadouts[self.team];
    var_0 = spawn( "script_model", self.origin );
    var_0.angles = self.angles;
    var_0.playerspawnpos = self.origin;
    var_0.notti = 1;
    self.setspawnpoint = var_0;
    self.gamemode_chosenclass = self.class;
    self.pers["class"] = "gamemode";
    self.pers["lastClass"] = "gamemode";
    self.class = "gamemode";
    self.lastclass = "gamemode";
    self notify( "faux_spawn" );
    self.gameobject_fauxspawn = 1;
    self.faux_spawn_stance = self getstance();
    thread maps\mp\gametypes\_playerlogic::spawnplayer( 1 );
}

removebombcarrierclass()
{
    self endon( "death" );
    self endon( "disconnect" );
    level endon( "game_ended" );

    if ( isdefined( self.iscarrying ) && self.iscarrying == 1 )
    {
        self notify( "force_cancel_placement" );
        wait 0.05;
    }

    if ( maps\mp\_utility::isjuggernaut() )
    {
        self notify( "lost_juggernaut" );
        wait 0.05;
    }

    self.pers["gamemodeLoadout"] = undefined;
    var_0 = spawn( "script_model", self.origin );
    var_0.angles = self.angles;
    var_0.playerspawnpos = self.origin;
    var_0.notti = 1;
    self.setspawnpoint = var_0;
    self notify( "faux_spawn" );
    self.faux_spawn_stance = self getstance();
    thread maps\mp\gametypes\_playerlogic::spawnplayer( 1 );
}

oncantuse( var_0 )
{
    var_0 iprintlnbold( &"MP_CANT_PLANT_WITHOUT_BOMB" );
}

bombplanted( var_0, var_1 )
{
    level endon( "overtime" );
    maps\mp\gametypes\_gamelogic::pausetimer();
    level.bombplanted = 1;
    level.timelimitoverride = 1;
    level.scorelimitoverride = 1;
    setdvar( "ui_bomb_timer", 1 );
    setgameendtime( int( gettime() + level.bombtimer * 1000 ) );
    var_0.visuals[0] thread maps\mp\gametypes\_gamelogic::playtickingsound();
    var_2 = gettime();
    bombtimerwait();
    setdvar( "ui_bomb_timer", 0 );
    var_0.visuals[0] maps\mp\gametypes\_gamelogic::stoptickingsound();

    if ( !level.bombplanted )
    {
        if ( level.hotpotato )
        {
            var_3 = ( gettime() - var_2 ) / 1000;
            level.bombtimer -= var_3;
        }

        return;
    }

    var_4 = level.sabbomb.visuals[0].origin;
    level.bombexploded = 1;
    setdvar( "ui_danger_team", "BombExploded" );

    if ( isdefined( level.bombowner ) )
    {
        var_0.visuals[0] radiusdamage( var_4, 512, 200, 20, level.bombowner, "MOD_EXPLOSIVE", "bomb_site_mp" );
        level.bombowner maps\mp\_utility::incpersstat( "destructions", 1 );
        level.bombowner maps\mp\gametypes\_persistence::statsetchild( "round", "destructions", level.bombowner.pers["destructions"] );
    }
    else
        var_0.visuals[0] radiusdamage( var_4, 512, 200, 20, undefined, "MOD_EXPLOSIVE", "bomb_site_mp" );

    var_5 = randomfloat( 360 );
    var_6 = spawnfx( level._effect["bombexplosion"], var_4 + ( 0.0, 0.0, 50.0 ), ( 0.0, 0.0, 1.0 ), ( cos( var_5 ), sin( var_5 ), 0 ) );
    triggerfx( var_6 );
    playrumbleonposition( "grenade_rumble", var_4 );
    earthquake( 0.75, 2.0, var_4, 2000 );
    thread maps\mp\_utility::playsoundinspace( "exp_suitcase_bomb_main", var_4 );

    if ( isdefined( var_0.exploderindex ) )
        common_scripts\utility::exploder( var_0.exploderindex );

    level.sabbomb maps\mp\gametypes\_gameobjects::setvisibleteam( "none" );
    level.bombzones["allies"] maps\mp\gametypes\_gameobjects::setvisibleteam( "none" );
    level.bombzones["axis"] maps\mp\gametypes\_gameobjects::setvisibleteam( "none" );
    setgameendtime( 0 );
    level.scorelimitoverride = 1;

    if ( level.scoremode )
        maps\mp\gametypes\_gamescore::_setteamscore( var_1, int( max( maps\mp\_utility::getwatcheddvar( "scorelimit" ), maps\mp\gametypes\_gamescore::_getteamscore( level.otherteam[var_1] ) + 1 ) ) );
    else
        maps\mp\gametypes\_gamescore::_setteamscore( var_1, 1 );

    maps\mp\gametypes\_gamescore::updateteamscore( var_1 );

    if ( isdefined( level.bombowner ) )
    {
        level.bombowner thread maps\mp\gametypes\_rank::giverankxp( "destroy" );
        maps\mp\gametypes\_gamescore::giveplayerscore( "destroy", level.bombowner );
        level thread maps\mp\_utility::teamplayercardsplash( "callout_destroyed_objective", level.bombowner );
    }

    wait 3;
    level.finalkillcam_winner = var_1;
    thread maps\mp\gametypes\_gamelogic::endgame( var_1, game["strings"]["target_destroyed"] );
}

bombtimerwait()
{
    level endon( "bomb_defused" );
    level endon( "overtime_ended" );
    var_0 = level.bombtimer * 1000 + gettime();
    setdvar( "ui_bomb_timer_endtime", var_0 );
    level thread handlehostmigration( var_0 );
    maps\mp\gametypes\_hostmigration::waitlongdurationwithgameendtimeupdate( level.bombtimer );
}

handlehostmigration( var_0 )
{
    level endon( "bomb_defused" );
    level endon( "overtime_ended" );
    level endon( "game_ended" );
    level endon( "disconnect" );
    level waittill( "host_migration_begin" );
    var_1 = maps\mp\gametypes\_hostmigration::waittillhostmigrationdone();

    if ( var_1 > 0 )
        setdvar( "ui_bomb_timer_endtime", var_0 + var_1 );
}

givelastonteamwarning()
{
    self endon( "death" );
    self endon( "disconnect" );
    level endon( "game_ended" );
    maps\mp\_utility::waittillrecoveredhealth( 3 );
    var_0 = maps\mp\_utility::getotherteam( self.pers["team"] );
    level thread maps\mp\_utility::teamplayercardsplash( "callout_lastteammemberalive", self, self.pers["team"] );
    level thread maps\mp\_utility::teamplayercardsplash( "callout_lastenemyalive", self, var_0 );
    level notify( "last_alive", self );
}

ontimelimit()
{
    if ( level.bombexploded )
        return;

    if ( game["teamScores"]["axis"] > game["teamScores"]["allies"] )
    {
        level.finalkillcam_winner = "axis";
        thread maps\mp\gametypes\_gamelogic::endgame( "axis", game["strings"]["time_limit_reached"] );
    }
    else if ( game["teamScores"]["axis"] < game["teamScores"]["allies"] )
    {
        level.finalkillcam_winner = "allies";
        thread maps\mp\gametypes\_gamelogic::endgame( "allies", game["strings"]["time_limit_reached"] );
    }
    else if ( game["teamScores"]["axis"] == game["teamScores"]["allies"] )
    {
        level.finalkillcam_winner = "none";

        if ( maps\mp\_utility::inovertime() )
            thread maps\mp\gametypes\_gamelogic::endgame( "tie", game["strings"]["time_limit_reached"] );
        else
            thread maps\mp\gametypes\_gamelogic::endgame( "overtime", game["strings"]["time_limit_reached"] );
    }
}

overtimethread( var_0 )
{
    level endon( "game_ended" );
    level.inovertime = 1;
    wait 5.0;
    level.disablespawning = 1;
}

bombdistancethread()
{
    level endon( "game_ended" );

    if ( common_scripts\utility::cointoss() )
        level.dangerteam = "allies";
    else
        level.dangerteam = "axis";

    for (;;)
    {
        if ( isdefined( level.sabbomb.carrier ) )
            var_0 = level.sabbomb.carrier;
        else
            var_0 = level.sabbomb.visuals[0];

        if ( distance( var_0.origin, level.bombzones[maps\mp\_utility::getotherteam( level.dangerteam )].visuals[0].origin ) < distance( var_0.origin, level.bombzones[level.dangerteam].visuals[0].origin ) )
            level.dangerteam = maps\mp\_utility::getotherteam( level.dangerteam );

        wait 0.05;
    }
}

resetbombsite()
{
    maps\mp\gametypes\_gameobjects::allowuse( "enemy" );
    maps\mp\gametypes\_gameobjects::setusetime( level.planttime );
    maps\mp\gametypes\_gameobjects::setusetext( &"MP_PLANTING_EXPLOSIVE" );
    maps\mp\gametypes\_gameobjects::setusehinttext( &"PLATFORM_HOLD_TO_PLANT_EXPLOSIVES" );
    maps\mp\gametypes\_gameobjects::setkeyobject( level.sabbomb );
    maps\mp\gametypes\_gameobjects::set2dicon( "friendly", "waypoint_defend" );
    maps\mp\gametypes\_gameobjects::set3dicon( "friendly", "waypoint_defend" );
    maps\mp\gametypes\_gameobjects::set2dicon( "enemy", "waypoint_target" );
    maps\mp\gametypes\_gameobjects::set3dicon( "enemy", "waypoint_target" );
    maps\mp\gametypes\_gameobjects::setvisibleteam( "none" );
    self.useweapon = "briefcase_bomb_mp";
}

setupfordefusing()
{
    maps\mp\gametypes\_gameobjects::allowuse( "friendly" );
    maps\mp\gametypes\_gameobjects::setusetime( level.defusetime );
    maps\mp\gametypes\_gameobjects::setusetext( &"MP_DEFUSING_EXPLOSIVE" );
    maps\mp\gametypes\_gameobjects::setusehinttext( &"PLATFORM_HOLD_TO_DEFUSE_EXPLOSIVES" );
    maps\mp\gametypes\_gameobjects::setkeyobject( undefined );
    maps\mp\gametypes\_gameobjects::set2dicon( "friendly", "waypoint_defuse" );
    maps\mp\gametypes\_gameobjects::set3dicon( "friendly", "waypoint_defuse" );
    maps\mp\gametypes\_gameobjects::set2dicon( "enemy", "waypoint_defend" );
    maps\mp\gametypes\_gameobjects::set3dicon( "enemy", "waypoint_defend" );
    maps\mp\gametypes\_gameobjects::setvisibleteam( "any" );
}

bombdefused( var_0 )
{
    setdvar( "ui_bomb_timer", 0 );
    maps\mp\gametypes\_gamelogic::resumetimer();
    level.bombplanted = 0;
    level.timelimitoverride = 0;
    level.scorelimitoverride = 0;
    level notify( "bomb_defused" );
}

ononeleftevent( var_0 )
{
    if ( level.bombexploded )
        return;

    var_1 = maps\mp\_utility::getlastlivingplayer( var_0 );
    var_1 thread givelastonteamwarning();
}

// decompiler emitted a duplicate/misordered parameter list here -- the callers in
// _damage.gsc pass ( victim, attacker, lifeId ) and the body below reads var_1 as the
// victim, var_2 as the attacker, and var_0 as the lifeId, so declare them in that
// order. The published "( var_0, var_1, var_2, var_0 )" made var_2 the lifeId integer
// -> "treat a variable of type 'integer' as a field object" on line ~859 EVERY death.
onnormaldeath( var_1, var_2, var_0 )
{
    if ( var_1.isplanting )
    {
        thread maps\mp\_matchdata::logkillevent( var_0, "planting" );
        var_2 maps\mp\_utility::incpersstat( "defends", 1 );
        var_2 maps\mp\gametypes\_persistence::statsetchild( "round", "defends", var_2.pers["defends"] );
    }
    else if ( var_1.isbombcarrier )
    {
        var_2 maps\mp\_utility::incplayerstat( "bombcarrierkills", 1 );
        thread maps\mp\_matchdata::logkillevent( var_0, "carrying" );
    }
    else if ( var_1.isdefusing )
        thread maps\mp\_matchdata::logkillevent( var_0, "defusing" );

    if ( var_2.isbombcarrier )
        var_2 maps\mp\_utility::incplayerstat( "killsasbombcarrier", 1 );
}

initgametypeawards()
{
    maps\mp\_awards::initstataward( "targetsdestroyed", 0, maps\mp\_awards::highestwins );
    maps\mp\_awards::initstataward( "bombsplanted", 0, maps\mp\_awards::highestwins );
    maps\mp\_awards::initstataward( "bombsdefused", 0, maps\mp\_awards::highestwins );
    maps\mp\_awards::initstataward( "bombcarrierkills", 0, maps\mp\_awards::highestwins );
    maps\mp\_awards::initstataward( "bombscarried", 0, maps\mp\_awards::highestwins );
    maps\mp\_awards::initstataward( "killsasbombcarrier", 0, maps\mp\_awards::highestwins );
}

setspecialloadouts()
{
    if ( isusingmatchrulesdata() && getmatchrulesdata( "defaultClasses", "axis", 5, "class", "inUse" ) )
        level.sab_loadouts["axis"] = maps\mp\_utility::getmatchrulesspecialclass( "axis", 5 );

    if ( isusingmatchrulesdata() && getmatchrulesdata( "defaultClasses", "allies", 5, "class", "inUse" ) )
        level.sab_loadouts["allies"] = maps\mp\_utility::getmatchrulesspecialclass( "allies", 5 );
}


// mp_tunisia is an SD-focused port: it ships ONE sab spawn per team (+1 start each)
// and bakes the axis pair ~36u below the local floor (z=24 where the real floor is
// z=60), so axis players spawn inside the ground and fall under the map, and whole
// teams re-stack on a single point. The map's 24 mp_sd_spawn_* ents are its only
// well-placed spawns, so build the sab pools from fresh clones of those and delete
// the broken originals. Must run BEFORE placespawnpoints/addspawnpoints (they read
// level.extraspawnpoints via _spawnlogic::getspawnpointarray). Clones are always NEW
// script_origins -- never the sd ents themselves and never shared between classes --
// because placespawnpoints inits whatever it is given and addspawnpoints skips
// pre-inited ents (the empty level.spawnpoints %0 flood; see grnd.gsc).
sab_fixtunisia()
{
    if ( level.script != "mp_tunisia" )
        return;

    var_0 = getentarray( "mp_sd_spawn_defender", "classname" );
    var_1 = getentarray( "mp_sd_spawn_attacker", "classname" );

    if ( !var_0.size || !var_1.size )
        return;

    if ( !isdefined( level.extraspawnpoints ) )
        level.extraspawnpoints = [];

    level.extraspawnpoints["mp_sab_spawn_allies_start"] = sab_tunisia_clones( var_0 );
    level.extraspawnpoints["mp_sab_spawn_allies"] = sab_tunisia_clones( var_0 );
    level.extraspawnpoints["mp_sab_spawn_axis_start"] = sab_tunisia_clones( var_1 );
    level.extraspawnpoints["mp_sab_spawn_axis"] = sab_tunisia_clones( var_1 );

    var_2 = [];
    var_2[0] = "mp_sab_spawn_allies";
    var_2[1] = "mp_sab_spawn_allies_start";
    var_2[2] = "mp_sab_spawn_axis";
    var_2[3] = "mp_sab_spawn_axis_start";

    for ( var_3 = 0; var_3 < var_2.size; var_3++ )
    {
        var_4 = getentarray( var_2[var_3], "classname" );

        for ( var_5 = 0; var_5 < var_4.size; var_5++ )
            var_4[var_5] delete();
    }
}

sab_tunisia_clones( var_0 )
{
    var_1 = [];

    for ( var_2 = 0; var_2 < var_0.size; var_2++ )
    {
        var_3 = spawn( "script_origin", var_0[var_2].origin );

        if ( isdefined( var_0[var_2].angles ) )
            var_3.angles = var_0[var_2].angles;
        else
            var_3.angles = ( 0, 0, 0 );

        var_1[var_1.size] = var_3;
    }

    return var_1;
}

// yourserver.gg: mp_osg_mirage_n is a port that ships NO Sabotage objectives (no bomb, no
// plant sites), so SAB errors ("No sab_bomb... found in map") and has nothing to
// play. Spawn the bomb + pickup + both plant sites (each targeting a destroy origin)
// at hand-collected coordinates. Called from onstartgametype() right after
// sab_fixtunisia() and BEFORE thread sabotage() (line ~172) reads these via getent(),
// and spawn() is synchronous so they exist in time. Guarded to this map + one-shot.
sab_fix_mirage_n()
{
    if ( level.script != "mp_osg_mirage_n" )
        return;

    precachemodel( "com_bomb_objective" );

    // The map ships SOME sab entities but not all - create only the gaps.
    bomb   = getent( "sab_bomb", "targetname" );
    pickup = getent( "sab_bomb_pickup_trig", "targetname" );
    axis   = getent( "sab_bomb_axis", "targetname" );
    allies = getent( "sab_bomb_allies", "targetname" );

    // neutral bomb (center of map) - only if the map lacks one
    if ( !isdefined( bomb ) )
    {
        bomb = spawn( "script_model", ( -409.817, -1.35648, 90.125 ) );
        bomb.angles = ( 0, -3, 0 );
        bomb.targetname = "sab_bomb";
    }

    // pickup trigger at the bomb - only if missing
    if ( !isdefined( pickup ) )
    {
        pickup = spawn( "trigger_radius", bomb.origin, 0, 48, 72 );
        pickup.targetname = "sab_bomb_pickup_trig";
    }

    // Site A -> sab_bomb_axis (+ its destroy target) - only if missing
    // The crate script_model IS the usable "trigger": script_model supports
    // makeusable + sethintstring (like the airdrop crate), whereas a script-spawned
    // trigger_radius does NOT support the use-trigger API (sethintstring /
    // setteamfortrigger / clientclaimtrigger all fail on it). A separate invisible
    // origin anchors the TARGET waypoint icon (createuseobject reads trigger.target
    // as the visuals). This matches highrise: you look at the crate to plant.
    if ( !isdefined( axis ) )
    {
        axis = spawn( "script_model", ( 93.6523, -2659.22, 0.125 ) );
        axis setmodel( "com_bomb_objective" );
        axis.angles = ( 0, 81, 0 );
        axis.targetname = "sab_bomb_axis";
        axis.target = "sab_dest_mirage_a";
        axis sab_make_plant_trigger();

        dest_a = spawn( "script_origin", ( 93.6523, -2659.22, 0.125 ) );
        dest_a.angles = ( 0, 81, 0 );
        dest_a.targetname = "sab_dest_mirage_a";
    }

    // Site B -> sab_bomb_allies (crate = usable trigger; origin = icon anchor)
    if ( !isdefined( allies ) )
    {
        allies = spawn( "script_model", ( 111.807, 2825.47, 92.9565 ) );
        allies setmodel( "com_bomb_objective" );
        allies.angles = ( 0, -88, 0 );
        allies.targetname = "sab_bomb_allies";
        allies.target = "sab_dest_mirage_b";
        allies sab_make_plant_trigger();

        dest_b = spawn( "script_origin", ( 111.807, 2825.47, 92.9565 ) );
        dest_b.angles = ( 0, -88, 0 );
        dest_b.targetname = "sab_dest_mirage_b";
    }
}

// yourserver.gg: mp_toujane - the map's native trigger_use_touch sites drive stock plant with NO
// hold bar and instant detonate on this port, and triggers can't be relocated (setorigin is
// a no-op on them - verified in-game). So use our custom hold-[use] crate sites (which DO
// give a proper plant hold) at in-bounds waypoint spots, with bomb + pickup at map center on
// the floor. mp_toujane IS in the createbombzone() gate so the crates route through the
// hold-[use] handler. Coords from the toujane Bot Warfare waypoints (real floor z).
sab_fix_toujane()
{
    if ( level.script != "mp_toujane" )
        return;

    precachemodel( "com_bomb_objective" );

    center = ( 1371.7, 1517.6, 21.6 );
    site_a = ( 1221.5, 286.0, -10.0 );
    site_b = ( 1359.3, 2811.3, 48.6 );

    // shove the map's native site triggers aside so getent() finds our crates
    old_axis = getent( "sab_bomb_axis", "targetname" );
    if ( isdefined( old_axis ) && old_axis.classname != "script_model" )
        old_axis.targetname = "sab_bomb_axis_native";

    old_allies = getent( "sab_bomb_allies", "targetname" );
    if ( isdefined( old_allies ) && old_allies.classname != "script_model" )
        old_allies.targetname = "sab_bomb_allies_native";

    if ( !isdefined( getent( "sab_bomb", "targetname" ) ) )
    {
        bomb = spawn( "script_model", center );
        bomb.angles = ( 0, 0, 0 );
        bomb.targetname = "sab_bomb";
    }

    if ( !isdefined( getent( "sab_bomb_pickup_trig", "targetname" ) ) )
    {
        pickup = spawn( "trigger_radius", center, 0, 48, 72 );
        pickup.targetname = "sab_bomb_pickup_trig";
    }

    if ( !isdefined( getent( "sab_bomb_axis", "targetname" ) ) )
    {
        axis = spawn( "script_model", site_a );
        axis setmodel( "com_bomb_objective" );
        axis.angles = ( 0, 0, 0 );
        axis.targetname = "sab_bomb_axis";
        axis.target = "sab_dest_toujane_a";
        axis sab_make_plant_trigger();

        dest_a = spawn( "script_origin", site_a );
        dest_a.angles = ( 0, 0, 0 );
        dest_a.targetname = "sab_dest_toujane_a";
    }

    if ( !isdefined( getent( "sab_bomb_allies", "targetname" ) ) )
    {
        allies = spawn( "script_model", site_b );
        allies setmodel( "com_bomb_objective" );
        allies.angles = ( 0, 0, 0 );
        allies.targetname = "sab_bomb_allies";
        allies.target = "sab_dest_toujane_b";
        allies sab_make_plant_trigger();

        dest_b = spawn( "script_origin", site_b );
        dest_b.angles = ( 0, 0, 0 );
        dest_b.targetname = "sab_dest_toujane_b";
    }
}

// yourserver.gg: mp_gulag - ships NO sab objectives and NO sab spawns at all. Spawn the neutral bomb
// + pickup at map center, a com_bomb_objective crate at each end (custom hold-[use] handler,
// mp_gulag is in the createbombzone gate), and a fan of in-bounds spawns at each end. gulag is
// a linear map along X, so the fan spreads along X. Coords from the gulag Bot Warfare waypoints.
sab_fix_gulag()
{
    if ( level.script != "mp_gulag" )
        return;

    center = ( 843.7, -414.3, 18.1 );
    site_a = ( 96.0, -416.0, 32.0 );    // far west end (map's own tdm spawn position)
    site_b = ( 1600.0, -416.0, 32.0 );  // far east end

    // ---- SPAWNS: fan at each end (axis at site A, allies at site B) ----
    if ( !isdefined( level.extraspawnpoints ) )
        level.extraspawnpoints = [];

    level.extraspawnpoints["mp_sab_spawn_axis"]           = sab_gulag_fan( site_a, 1, 0 );
    level.extraspawnpoints["mp_sab_spawn_axis_start"]     = sab_gulag_fan( site_a, 1, 0 );
    level.extraspawnpoints["mp_sab_spawn_axis_planted"]   = sab_gulag_fan( site_a, 1, 0 );
    level.extraspawnpoints["mp_sab_spawn_allies"]         = sab_gulag_fan( site_b, -1, 180 );
    level.extraspawnpoints["mp_sab_spawn_allies_start"]   = sab_gulag_fan( site_b, -1, 180 );
    level.extraspawnpoints["mp_sab_spawn_allies_planted"] = sab_gulag_fan( site_b, -1, 180 );

    // ---- OBJECTIVES: bomb + pickup at center, a crate site at each end ----
    precachemodel( "com_bomb_objective" );

    if ( !isdefined( getent( "sab_bomb", "targetname" ) ) )
    {
        bomb = spawn( "script_model", center );
        bomb.angles = ( 0, 0, 0 );
        bomb.targetname = "sab_bomb";
    }

    if ( !isdefined( getent( "sab_bomb_pickup_trig", "targetname" ) ) )
    {
        pickup = spawn( "trigger_radius", center, 0, 48, 72 );
        pickup.targetname = "sab_bomb_pickup_trig";
    }

    if ( !isdefined( getent( "sab_bomb_axis", "targetname" ) ) )
    {
        axis = spawn( "script_model", site_a );
        axis setmodel( "com_bomb_objective" );
        axis.angles = ( 0, 0, 0 );
        axis.targetname = "sab_bomb_axis";
        axis.target = "sab_dest_gulag_a";
        axis sab_make_plant_trigger();

        dest_a = spawn( "script_origin", site_a );
        dest_a.angles = ( 0, 0, 0 );
        dest_a.targetname = "sab_dest_gulag_a";
    }

    if ( !isdefined( getent( "sab_bomb_allies", "targetname" ) ) )
    {
        allies = spawn( "script_model", site_b );
        allies setmodel( "com_bomb_objective" );
        allies.angles = ( 0, 180, 0 );
        allies.targetname = "sab_bomb_allies";
        allies.target = "sab_dest_gulag_b";
        allies sab_make_plant_trigger();

        dest_b = spawn( "script_origin", site_b );
        dest_b.angles = ( 0, 180, 0 );
        dest_b.targetname = "sab_dest_gulag_b";
    }
}

// Fan of 5 in-bounds script_origin spawns around a map end, offset toward map-center along X
// (gulag is a linear X-axis map). dir (+1/-1) flips the X offset so the fan faces inward.
sab_gulag_fan( origin, dir, yaw )
{
    out = [];

    off = [];
    off[0] = ( 100.0, 0.0, 0.0 );
    off[1] = ( 60.0, 90.0, 0.0 );
    off[2] = ( 60.0, -90.0, 0.0 );
    off[3] = ( 150.0, 90.0, 0.0 );
    off[4] = ( 150.0, -90.0, 0.0 );

    for ( i = 0; i < off.size; i++ )
    {
        o = ( off[i][0] * dir, off[i][1], off[i][2] );
        s = spawn( "script_origin", origin + o );
        s.angles = ( 0.0, yaw, 0.0 );
        out[out.size] = s;
    }

    return out;
}

// yourserver.gg: mp_boomtown (Western Paradise) SAB is doubly broken: (1) it SHIPS sab objectives
// (bomb + both plant sites) but dumped off-map at ~(-8960,8896,8), and (2) it ships only 1
// sab spawn per class, also off-map, so players fall through the world. Because the natives
// EXIST, a plain "spawn only if missing" fix no-ops and the bombs stay off-map - so we first
// rename the natives aside (like toujane), THEN spawn ours. The BPGSABDUMP tdm "ground truth"
// is useless here (its farthest pair (-72,+/-2688,~880) are just past the Y border, and its
// centroid is pulled by them); the reliable in-bounds anchors come from the map's Bot Warfare
// waypoints (wps_boomtown.gsc, 194 nodes, Y in [-2627,+2590]) - bots walk them so they are
// guaranteed walkable. Runs before placespawnpoints (line ~152, reads level.extraspawnpoints)
// and before thread sabotage() (line ~174, reads the objectives via getent):
//   SPAWNS - fan 5 in-bounds script_origins toward map-center at each end (mirrors
//     ctf_spawnfan), axis at the south end, allies at the north end, then delete the broken
//     native sab spawns so only the fan remains.
//   OBJECTIVES - mirage_n-style: neutral bomb at the map-center waypoint, a com_bomb_objective
//     crate at each end waypoint (look + hold [use] to plant) targeting a destroy origin.
//     mp_boomtown is in the createbombzone() gate (~line 370) so the crate sites route through
//     the hold-[use] handler, exactly like mirage_n / toujane.
sab_fix_boomtown()
{
    if ( level.script != "mp_boomtown" )
        return;

    // in-bounds anchors from the boomtown Bot Warfare waypoints (wps_boomtown.gsc) - bots
    // walk them, so they are guaranteed walkable. The map's own sab objects ship off-map at
    // ~(-8960,8896,8) and its farthest tdm spawns (+/-2688) sit just past the Y border
    // (waypoints end ~+/-2600), which is why every earlier coord landed out of bounds.
    center = ( 8.3, -20.7, 832.1 );      // neutral bomb - map center
    south  = ( -27.2, -1852.4, 864.1 );  // axis end  (site A)
    north  = ( 6.1, 2200.0, 831.4 );     // allies end (site B)

    // ---- shove the map's native OFF-MAP sab objectives aside so getent() finds OURS ----
    // this version of the map SHIPS sab_bomb/axis/allies dumped at ~(-8960,8896,8); without
    // renaming them our "spawn only if missing" guards below no-op and the bombs stay off-map.
    old_bomb = getent( "sab_bomb", "targetname" );
    if ( isdefined( old_bomb ) )
    {
        old_bomb.targetname = "sab_bomb_native";
        old_bomb hide();
    }

    // CRITICAL: the grabbable bomb is built by createcarryobject() from sab_bomb_pickup_trig
    // (see ~line 257), NOT from sab_bomb - so the bomb sits at the pickup trigger. Rename the
    // native (off-map) trigger aside too, or the bomb stays at (-8960,8896,8) no matter where
    // we move sab_bomb.
    old_pickup = getent( "sab_bomb_pickup_trig", "targetname" );
    if ( isdefined( old_pickup ) )
        old_pickup.targetname = "sab_bomb_pickup_trig_native";

    old_axis = getent( "sab_bomb_axis", "targetname" );
    if ( isdefined( old_axis ) )
        old_axis.targetname = "sab_bomb_axis_native";

    old_allies = getent( "sab_bomb_allies", "targetname" );
    if ( isdefined( old_allies ) )
        old_allies.targetname = "sab_bomb_allies_native";

    // ---- SPAWNS: fan of in-bounds spawns at each end; drop the broken native sab spawns ----
    if ( !isdefined( level.extraspawnpoints ) )
        level.extraspawnpoints = [];

    // axis defends the south site, allies the north site. Every sab spawn class must be
    // covered - including _planted, which SAB switches players to AFTER a bomb is planted;
    // if we leave it to the map, post-plant respawns fall back to the off-map native points.
    level.extraspawnpoints["mp_sab_spawn_axis"]           = sab_boomtown_fan( south, 1, 90 );
    level.extraspawnpoints["mp_sab_spawn_axis_start"]     = sab_boomtown_fan( south, 1, 90 );
    level.extraspawnpoints["mp_sab_spawn_axis_planted"]   = sab_boomtown_fan( south, 1, 90 );
    level.extraspawnpoints["mp_sab_spawn_allies"]         = sab_boomtown_fan( north, -1, 270 );
    level.extraspawnpoints["mp_sab_spawn_allies_start"]   = sab_boomtown_fan( north, -1, 270 );
    level.extraspawnpoints["mp_sab_spawn_allies_planted"] = sab_boomtown_fan( north, -1, 270 );

    classes = [];
    classes[0] = "mp_sab_spawn_allies";
    classes[1] = "mp_sab_spawn_allies_start";
    classes[2] = "mp_sab_spawn_allies_planted";
    classes[3] = "mp_sab_spawn_axis";
    classes[4] = "mp_sab_spawn_axis_start";
    classes[5] = "mp_sab_spawn_axis_planted";

    for ( c = 0; c < classes.size; c++ )
    {
        broke = getentarray( classes[c], "classname" );

        for ( b = 0; b < broke.size; b++ )
            broke[b] delete();
    }

    // ---- OBJECTIVES: spawn the missing bomb + both crate plant sites at the proven ends ----
    precachemodel( "com_bomb_objective" );

    // neutral bomb (map center) - gametype gives it prop_suitcase_bomb + makes it grabbable
    if ( !isdefined( getent( "sab_bomb", "targetname" ) ) )
    {
        bomb = spawn( "script_model", center );
        bomb.angles = ( 0, 0, 0 );
        bomb.targetname = "sab_bomb";
    }

    if ( !isdefined( getent( "sab_bomb_pickup_trig", "targetname" ) ) )
    {
        pickup = spawn( "trigger_radius", center, 0, 48, 72 );
        pickup.targetname = "sab_bomb_pickup_trig";
    }

    // Site A -> sab_bomb_axis crate at the south end
    if ( !isdefined( getent( "sab_bomb_axis", "targetname" ) ) )
    {
        axis = spawn( "script_model", south );
        axis setmodel( "com_bomb_objective" );
        axis.angles = ( 0, 90, 0 );
        axis.targetname = "sab_bomb_axis";
        axis.target = "sab_dest_boomtown_a";
        axis sab_make_plant_trigger();

        dest_a = spawn( "script_origin", south );
        dest_a.angles = ( 0, 90, 0 );
        dest_a.targetname = "sab_dest_boomtown_a";
    }

    // Site B -> sab_bomb_allies crate at the north end
    if ( !isdefined( getent( "sab_bomb_allies", "targetname" ) ) )
    {
        allies = spawn( "script_model", north );
        allies setmodel( "com_bomb_objective" );
        allies.angles = ( 0, 270, 0 );
        allies.targetname = "sab_bomb_allies";
        allies.target = "sab_dest_boomtown_b";
        allies sab_make_plant_trigger();

        dest_b = spawn( "script_origin", north );
        dest_b.angles = ( 0, 270, 0 );
        dest_b.targetname = "sab_dest_boomtown_b";
    }
}

// Fan of 5 in-bounds script_origin spawns around a map end, offset toward map-center.
// Mirrors ctf_spawnfan: dir (+1/-1) flips the Y offset so the fan always faces inward,
// yaw orients the spawns. Used only by sab_fix_boomtown().
sab_boomtown_fan( origin, dir, yaw )
{
    out = [];

    off = [];
    off[0] = ( 0.0, 100.0, 0.0 );
    off[1] = ( 90.0, 60.0, 0.0 );
    off[2] = ( -90.0, 60.0, 0.0 );
    off[3] = ( 90.0, 150.0, 0.0 );
    off[4] = ( -90.0, 150.0, 0.0 );

    for ( i = 0; i < off.size; i++ )
    {
        o = ( off[i][0], off[i][1] * dir, off[i][2] );
        s = spawn( "script_origin", origin + o );
        s.angles = ( 0.0, yaw, 0.0 );
        out[out.size] = s;
    }

    return out;
}

// Make a script-spawned bomb-site trigger usable like a radiant trigger_use_touch.
// makeusable() makes the engine fire "trigger" on the USE button (not on touch);
// setcursorhint lets setusehinttext's sethintstring succeed. The USE-vs-proximity
// routing is handled separately by bpg_sab_createuseobject_use() because the trigger's
// classname (which stock createuseobject routes on) is engine-read-only.
sab_make_plant_trigger()
{
    self setcursorhint( "HINT_NOICON" );
    self makeusable();
}

// A copy of maps\mp\gametypes\_gameobjects::createuseobject that FORCES the "use"
// (hold-[use]) path instead of branching on the trigger classname. Needed only for
// mp_osg_mirage_n's script-spawned trigger_radius plant sites, which the engine
// reports as classname "trigger_radius" (-> stock picks proximity/auto-capture).
// Mirrors stock field-for-field; only the triggertype branch is removed.
bpg_sab_createuseobject_use( var_0, var_1, var_2, var_3 )
{
    var_4 = spawnstruct();
    var_4.type = "useObject";
    var_4.curorigin = var_1.origin;
    var_4.ownerteam = var_0;
    var_4.entnum = var_1 getentitynumber();
    var_4.keyobject = undefined;
    var_4.triggertype = "use";
    var_4.trigger = var_1;

    for ( i = 0; i < var_2.size; i++ )
    {
        var_2[i].baseorigin = var_2[i].origin;
        var_2[i].baseangles = var_2[i].angles;
    }

    var_4.visuals = var_2;

    if ( !isdefined( var_3 ) )
        var_3 = ( 0.0, 0.0, 0.0 );

    var_4.offset3d = var_3;
    var_4.compassicons = [];
    var_4.objidallies = maps\mp\gametypes\_gameobjects::getnextobjid();
    var_4.objidaxis = maps\mp\gametypes\_gameobjects::getnextobjid();
    objective_add( var_4.objidallies, "invisible", var_4.curorigin );
    objective_add( var_4.objidaxis, "invisible", var_4.curorigin );
    objective_team( var_4.objidallies, "allies" );
    objective_team( var_4.objidaxis, "axis" );
    var_4.objpoints["allies"] = maps\mp\gametypes\_objpoints::createteamobjpoint( "objpoint_allies_" + var_4.entnum, var_4.curorigin + var_3, "allies", undefined );
    var_4.objpoints["axis"] = maps\mp\gametypes\_objpoints::createteamobjpoint( "objpoint_axis_" + var_4.entnum, var_4.curorigin + var_3, "axis", undefined );
    var_4.objpoints["allies"].alpha = 0;
    var_4.objpoints["axis"].alpha = 0;
    var_4.interactteam = "none";
    var_4.worldicons = [];
    var_4.visibleteam = "none";
    var_4.onuse = undefined;
    var_4.oncantuse = undefined;
    var_4.usetext = "default";
    var_4.usetime = 10000;
    var_4.curprogress = 0;
    var_4.userate = 1;
    var_4 thread bpg_sab_useobjectusethink();

    return var_4;
}

// Self-contained USE/hold handler for mp_osg_mirage_n's script_model plant sites,
// modeled on the airdrop crate (maps\mp\killstreaks\_airdrop). It mirrors
// _gameobjects::useobjectusethink but drives the hold with playerlinkto +
// usebuttonpressed (like the crate) instead of the networked trigger-claim API
// (clientclaimtrigger/istouching), which only works on radiant trigger_use_touch
// brushes - not script-spawned entities. On completion it calls the SAME sab
// self.onuse callback, so plant/defuse/detonate/score are 100% stock.
bpg_sab_useobjectusethink()
{
    level endon( "game_ended" );
    self endon( "deleted" );

    for (;;)
    {
        self.trigger waittill( "trigger", var_0 );

        if ( !maps\mp\_utility::isreallyalive( var_0 ) )
            continue;

        if ( !maps\mp\gametypes\_gameobjects::caninteractwith( var_0.pers["team"] ) )
            continue;

        if ( !var_0 isonground() )
            continue;

        if ( !var_0 maps\mp\_utility::isjuggernaut() && maps\mp\_utility::iskillstreakweapon( var_0 getcurrentweapon() ) )
            continue;

        if ( isdefined( self.keyobject ) && ( !isdefined( var_0.carryobject ) || var_0.carryobject != self.keyobject ) )
        {
            if ( isdefined( self.oncantuse ) )
                self [[ self.oncantuse ]]( var_0 );

            continue;
        }

        if ( !var_0 common_scripts\utility::isweaponenabled() )
            continue;

        var_1 = 1;

        if ( self.usetime > 0 )
        {
            if ( isdefined( self.onbeginuse ) )
                self [[ self.onbeginuse ]]( var_0 );

            var_2 = var_0.pers["team"];
            var_1 = bpg_sab_useholdthink( var_0 );
            self notify( "finished_use" );

            if ( isdefined( self.onenduse ) )
                self [[ self.onenduse ]]( var_2, var_0, var_1 );
        }

        if ( !var_1 )
            continue;

        if ( isdefined( self.onuse ) )
            self [[ self.onuse ]]( var_0 );
    }
}

bpg_sab_useholdthink( var_0 )
{
    var_0 notify( "use_hold" );
    var_0 playerlinkto( self.trigger );
    var_0 playerlinkedoffsetenable();

    var_1 = self.useweapon;
    var_2 = var_0 getcurrentweapon();

    if ( isdefined( var_1 ) )
    {
        if ( var_2 == var_1 )
            var_2 = var_0.lastnonuseweapon;

        var_0.lastnonuseweapon = var_2;
        var_0 maps\mp\_utility::_giveweapon( var_1 );
        var_0 setweaponammostock( var_1, 0 );
        var_0 setweaponammoclip( var_1, 0 );
        var_0 switchtoweapon( var_1 );
    }
    else
        var_0 common_scripts\utility::_disableweapon();

    self.curprogress = 0;
    self.inuse = 1;
    self.userate = 0;
    var_0 thread bpg_sab_personalusebar( self );
    var_3 = bpg_sab_useholdthinkloop( var_0, var_2 );

    if ( isdefined( var_3 ) && var_3 )
        return 1;

    if ( isdefined( var_0 ) )
    {
        if ( isdefined( var_1 ) )
        {
            if ( var_2 != "none" )
                var_0 switchtoweapon( var_2 );
            else
                var_0 takeweapon( var_1 );
        }
        else
            var_0 common_scripts\utility::_enableweapon();

        var_0 unlink();

        if ( !maps\mp\_utility::isreallyalive( var_0 ) )
            var_0.killedinuse = 1;
    }

    self.inuse = 0;
    return 0;
}

bpg_sab_useholdthinkloop( var_0, var_1 )
{
    level endon( "game_ended" );
    self endon( "disabled" );
    var_2 = self.useweapon;

    while ( maps\mp\_utility::isreallyalive( var_0 ) && var_0 usebuttonpressed() && !isdefined( var_0.throwinggrenade ) && !var_0 meleebuttonpressed() && self.curprogress < self.usetime )
    {
        if ( !isdefined( var_2 ) || var_0 getcurrentweapon() == var_2 )
        {
            self.curprogress += 50 * var_0.objectivescaler;
            self.userate = 1 * var_0.objectivescaler;
        }
        else
            self.userate = 0;

        if ( self.curprogress >= self.usetime )
        {
            self.inuse = 0;

            if ( isdefined( var_2 ) )
            {
                var_0 setweaponammostock( var_2, 1 );
                var_0 setweaponammoclip( var_2, 1 );

                if ( var_1 != "none" )
                    var_0 switchtoweapon( var_1 );
                else
                    var_0 takeweapon( var_2 );
            }
            else
                var_0 common_scripts\utility::_enableweapon();

            var_0 unlink();
            return maps\mp\_utility::isreallyalive( var_0 );
        }

        wait 0.05;
    }

    return 0;
}

bpg_sab_personalusebar( var_0 )
{
    self endon( "disconnect" );
    var_1 = maps\mp\gametypes\_hud_util::createprimaryprogressbar();
    var_2 = maps\mp\gametypes\_hud_util::createprimaryprogressbartext();
    var_2 settext( var_0.usetext );
    var_3 = -1;

    while ( maps\mp\_utility::isreallyalive( self ) && var_0.inuse && !level.gameended )
    {
        if ( var_3 != var_0.userate )
        {
            if ( var_0.curprogress > var_0.usetime )
                var_0.curprogress = var_0.usetime;

            var_1 maps\mp\gametypes\_hud_util::updatebar( var_0.curprogress / var_0.usetime, 1000 / var_0.usetime * var_0.userate );

            if ( !var_0.userate )
            {
                var_1 maps\mp\gametypes\_hud_util::hideelem();
                var_2 maps\mp\gametypes\_hud_util::hideelem();
            }
            else
            {
                var_1 maps\mp\gametypes\_hud_util::showelem();
                var_2 maps\mp\gametypes\_hud_util::showelem();
            }
        }

        var_3 = var_0.userate;
        wait 0.05;
    }

    var_1 maps\mp\gametypes\_hud_util::destroyelem();
    var_2 maps\mp\gametypes\_hud_util::destroyelem();
}