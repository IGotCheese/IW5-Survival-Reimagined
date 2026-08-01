/*
    mapvote.gsc â€” bot management
    Map/mode voting is handled by IW5_MapVote.iwd
    Bot [BOT] tag comes from bots.txt name prefixes
*/

init()
{
    // OSPREY / ESCORT AIRDROP CRASH FIX â€” must run FIRST and synchronously.
    // _helicopter::init() early-returns on node-less maps (shipment, pool maps,
    // rust_long, most ports) and never sets the heli config the Osprey reuses, so
    // createairship() -> missile_createattractorent(undefined) -> the airship has no
    // view rig -> Com_ERROR G_GetPlayerViewOrigin "tag_player" -> ShutdownGame. The
    // earlier wait'd-thread version of this never ran on those maps because the
    // nav-light loadfx() block below used to sit ABOVE it and aborted init() first.
    // Set the vars here, unconditionally, before anything downstream can fail.
    applyHeliConfig();

    // Silence the maps\mp\_animatedmodels::animatemodel error spam (see
    // animatemodel_safe below). Registered here in init() so it lands BEFORE
    // _animatedmodels::main's frame-end array_thread spawns the animatemodel threads.
    replaceFunc( maps\mp\_animatedmodels::animatemodel, ::animatemodel_safe );

    // Override DSR time limits â€” DSR files run after server.cfg and reset
    // timelimits to their defaults, so we must override here from GSC (0 = unlimited)
    setDvar("scr_war_timelimit",        0);
    setDvar("scr_dm_timelimit",         0);
    setDvar("scr_dom_timelimit",        0);
    setDvar("scr_conf_timelimit",       0);
    setDvar("scr_koth_timelimit",       0);
    setDvar("scr_sab_timelimit",        0);
    setDvar("scr_ctf_timelimit",        0);
    setDvar("scr_sd_timelimit",         0);
    setDvar("scr_tdef_timelimit",       0);
    setDvar("scr_dd_timelimit",         0);
    setDvar("scr_dropzone_timelimit",   0);
    setDvar("scr_gun_timelimit",        0);
    setDvar("scr_oic_timelimit",        0);
    // Juggernaut (jugg), Team Juggernaut (teamjugg) and Infected (infect) removed
    // from the server â€” their time/score limits are no longer set.

    // Score limits (DSR files reset these too)
    // scr_dm_scorelimit (FFA): the DSR's commonOption.scoreLimit does NOT
    // reliably map to this dvar in Plutonium (same mapping bug as respawnDelay),
    // so without this line it drifts to the engine default (~unlimited) and FFA
    // runs forever. FFA awards 50 pts/kill, so 5000 = 100 kills. Do NOT use 50 â€”
    // that's 1 kill (the original bug).
    setDvar("scr_dm_scorelimit",        5000);  // FFA (100 kills @ 50 pts/kill)
    setDvar("scr_war_scorelimit",       10000); // TDM
    setDvar("scr_dom_scorelimit",       220);   // Domination
    setDvar("scr_conf_scorelimit",      100);   // Kill Confirmed
    setDvar("scr_koth_scorelimit",      275);   // Headquarters
    setDvar("scr_tdef_scorelimit",      8250);  // Team Defender
    setDvar("scr_dropzone_scorelimit",  5500);  // Drop Zone
    setDvar("scr_gun_scorelimit",       30);    // Gun Game
    setDvar("scr_oic_scorelimit",       0);     // One In The Chamber â€” STOCK = 0 (no score limit; ends by elimination: 2 lives, last man standing). 33 ended the match on the first kill, since kills score points.

    // FFA respawn delay. The DSR's commonOption.respawnDelay "0" does NOT map to
    // this dvar in Plutonium, so it sits at the game default of 7.5 seconds â€”
    // that's the "death timer" in FFA. Force it to 0 for instant respawns.
    setDvar("scr_dm_playerrespawndelay", 0);

    // FastDL (also in autoexec.cfg but Com_Restart can wipe it)
    setDvar("sv_wwwBaseURL",     "https://your-fastdl-host.example/");
    setDvar("sv_allowDownload",  1);
    setDvar("sv_wwwDlDisabled",  0);

    // Mapvote pool (HQ removed: bot mod has fixkoth bug that hangs the script VM)
    setDvar("mapvote_maps",        "mp_bootleg,mp_carbon,mp_dome,mp_hardhat,mp_interchange,mp_lambeth,mp_mogadishu,mp_paris,mp_plaza2,mp_radar,mp_seatown,mp_nuked,mp_favela,mp_highrise,mp_nightshift,mp_rust,mp_alpha,mp_bravo,mp_exchange,mp_underground,mp_village,mp_aground_ss,mp_courtyard_ss,mp_terminal_cls,mp_raid,mp_afghan,mp_firingrange,mp_boardwalk,mp_burn_ss,mp_cement,mp_crosswalk_ss,mp_hillside_ss,mp_italy,mp_meteora,mp_moab,mp_nola,mp_overwatch,mp_park,mp_qadeem,mp_restrepo_ss,mp_roughneck,mp_shipbreaker,mp_six_ss,mp_killhouse,mp_estate,mp_mountain,mp_boomtown,mp_melee_resort,mp_lockout_h2,mp_gulag,mp_bog_sh,mp_bo2cove,mp_bo2frost,mp_bo2grind,mp_bo2paintball,mp_brecourt,mp_broadcast,mp_burgundy,mp_checkpoint,mp_csgo_mirage,mp_csgo_stmarc,mp_efa_lake,mp_geometric,mp_gob_aim_snow,mp_minecraft,mp_minecraft_3,mp_osg_hijacked,mp_osg_mirage_n,mp_overpass,mp_safehouse,mp_shipmentlong,mp_shortdust,mp_showdown_sh,mp_toujane,mp_cargoship_sh,mp_strike_sh,mp_prison,mp_tunisia,mp_bloc_2,mp_crash");
    setDvar("mapvote_customMaps",  "mp_shipment,mp_poolday,mp_poolday_v2,mp_poolday_reunion,mp_poolparty,mp_rust_long,mp_morningwood");
    // DD_default removed: DSR file missing from admin/ folder. To restore,
    // add a valid DD_default.dsr to the MW3 admin/ directory and put DD_default back here.
    setDvar("mapvote_modes",       "TDM_default,FFA_default,DOM_default,KC_default,SAB_default,CTF_default,TDEF_default,DZ_default,OIC_default,GG_default,Crank_default,SS_default");
    setDvar("mapvote_timer",       15);
    setDvar("mapvote_optionsCount", 10);

    // LOOP FIX: clear rotation dvars during map load so the bootstrapper's
    // mod-download-restart can't trigger another map_rotate (which loops).
    setDvar("sv_maprotation",        "");
    setDvar("sv_maprotationcurrent", "");

    level thread monitorFirstPlayer();
    level thread restoreRotationOnFirstSpawn();
    level thread tuneBotKnife();
    level thread enforceScoreLimits();
    // OSPREY/ESCORT RE-ENABLED 2026-06-28 (confirmed working in-game). Stripping off;
    // the Osprey final-killcam crash is handled by dofinalkillcam_hook in _mapvote.gsc
    // (skips the killcam on osprey_player_minigun_mp kills).
    // level thread watchOspreyStrip();
    level thread harrierAirstrike();  // MW2 harrier (forum function-hijack via finishAirstrikeUsage; bypasses buggy tryUseAirstrike)

    // Osprey/Escort belly+tail nav-lights for node-less maps. loadfx() must run in
    // the precache window (init), but we do it LAST so that if it misbehaves on this
    // build it cannot block the crash fix, the hooks, or the threads above.
    if ( !getentarray( "heli_start", "targetname" ).size && !getentarray( "heli_loop_start", "targetname" ).size )
    {
        level.chopper_fx["light"]["belly"] = loadfx( "misc/aircraft_light_red_blink" );
        level.chopper_fx["light"]["tail"]  = loadfx( "misc/aircraft_light_white_blink" );
    }
}

// ===== MW2 Harrier airstrike (replaces the Airstrike killstreak) =====
// harrier_airstrike is a complete native IW5 killstreak that MW3 never exposed in
// the killstreak menu. It runs on the stock airstrike PLANE system, NOT the
// createairship() view-rig that crashed the Osprey/Escort, so it is safe on every
// map. We point the regular Airstrike killstreak at it. Must run AFTER
// _airstrike::init registers level.killstreakfuncs (gametype start), so we wait.
harrierAirstrike()
{
    tries = 0;
    while ( ( !isdefined( level.killstreakfuncs ) || !isdefined( level.killstreakfuncs["precision_airstrike"] ) ) && tries < 200 )
    {
        wait 0.05;
        tries++;
    }
    if ( !isdefined( level.killstreakfuncs ) || !isdefined( level.killstreakfuncs["precision_airstrike"] ) )
        return;
    // Forum "function hijack": point the airstrike reward at our own handler that calls
    // _airstrike::finishairstrikeusage() DIRECTLY with the harrier_airstrike plane type.
    // This BYPASSES tryUseAirstrike(), whose level.planes>1 / level.planes++ (array-as-int)
    // is the engine bug that threw MP_AIR_SPACE_TOO_CROWDED and closed the client last time.
    level.killstreakfuncs["precision_airstrike"] = ::tryUseHarrierStrike;
    level.killstreakfuncs["airstrike"]           = ::tryUseHarrierStrike;
}

tryUseHarrierStrike( lifeId )
{
    self endon( "disconnect" );
    self endon( "death" );
    self thread harrierCleanupOnEnd();

    if ( !maps\mp\_utility::validateusestreak() )
        return 0;

    if ( isdefined( level.civilianjetflyby ) )
    {
        self iprintlnbold( &"MP_CIVILIAN_AIR_TRAFFIC" );
        return 0;
    }

    if ( maps\mp\_utility::isusingremote() )
        return 0;

    radius = level.mapsize / 6.46875;

    if ( level.splitscreen )
        radius *= 1.5;

    maps\mp\_utility::_beginlocationselection( "airstrike", "map_artillery_selector", 0, radius );

    self endon( "stop_location_selection" );
    self waittill( "confirm_location", location, directionyaw );

    directionyaw = randomint( 360 );

    self setblurforplayer( 0, 0.3 );

    thread maps\mp\killstreaks\_airstrike::finishairstrikeusage( lifeId, location, directionyaw, "harrier_airstrike" );

    self notify( "harrier_strike_complete" );
    return 1;
}

harrierCleanupOnEnd()
{
    self.harrierCleanupPending = true;
    self thread harrierWatchEvent( "death" );
    self thread harrierWatchEvent( "disconnect" );
    self thread harrierWatchEvent( "harrier_strike_complete" );
}

harrierWatchEvent( eventName )
{
    self waittill( eventName );
    if ( !isdefined( self.harrierCleanupPending ) || !self.harrierCleanupPending )
        return;
    self.harrierCleanupPending = false;
    if ( maps\mp\_utility::isusingremote() )
        self maps\mp\_utility::clearusingremote();
}

// ===== Osprey Gunner HUD + loadout strip =====
// The cac_getkillstreak replaceFunc can't catch the loadout builder's INTERNAL
// same-file call, so the icon still came through. We post-process instead: once a
// second, for every player, blank any osprey_gunner killstreak slot AND its HUD icon
// (the same setplayerdata("icons") the game uses to draw it). Works for custom AND
// default classes; once a slot is cleared its streakname is undefined so later passes
// skip it -> near-zero overhead.
watchOspreyStrip()
{
    for ( ;; )
    {
        wait 1;
        if ( !isdefined( level.players ) )
            continue;
        foreach ( p in level.players )
        {
            if ( isdefined( p ) )
                p stripOspreyOnce();
        }
    }
}

stripOspreyOnce()
{
    if ( isdefined( self.killstreaks ) )
    {
        cleaned = [];
        foreach ( ks in self.killstreaks )
        {
            if ( ks != "osprey_gunner" && ks != "escort_airdrop" )
                cleaned[ cleaned.size ] = ks;
        }
        self.killstreaks = cleaned;
    }

    if ( !isdefined( self.pers ) || !isdefined( self.pers["killstreaks"] ) )
        return;

    for ( i = 0; i < self.pers["killstreaks"].size; i++ )
    {
        slot = self.pers["killstreaks"][i];
        if ( isdefined( slot ) && isdefined( slot.streakname ) && ( slot.streakname == "osprey_gunner" || slot.streakname == "escort_airdrop" ) )
        {
            slot.streakname = undefined;
            slot.available = 0;
            slot.earned = 0;
            self setplayerdata( "killstreaksState", "icons", i, 0 );
            self setplayerdata( "killstreaksState", "hasStreak", i, 0 );
        }
    }
}

enforceScoreLimits()
{
    // Re-apply scorelimits periodically in case DSR fallback or gametype change wipes them.
    // scr_dm_scorelimit (FFA) is intentionally NOT enforced here â€” FFA awards
    // 50 pts/kill, so setting it to 50 made first-kill-ends-match. FFA_default.dsr
    // sets commonOption.scoreLimit to 1500 (30 kills); we let that stand.
    for (;;)
    {
        wait 1;
        applyHeliConfig();   // backup: keep the Osprey heli config present every second
        setDvar("scr_dm_scorelimit",        5000);   // FFA (100 kills) â€” DSR doesn't set this reliably
        setDvar("scr_war_scorelimit",       10000);
        setDvar("scr_dom_scorelimit",       220);
        setDvar("scr_conf_scorelimit",      100);
        setDvar("scr_koth_scorelimit",      275);
        setDvar("scr_tdef_scorelimit",      8250);
        setDvar("scr_dropzone_scorelimit",  5500);
        setDvar("scr_gun_scorelimit",       30);
        setDvar("scr_oic_scorelimit",       0);     // OIC stock = 0 (was 33 -> ended on first kill)
        setDvar("scr_dm_playerrespawndelay", 0);  // FFA: kill the 7.5s default respawn delay
    }
}

// Osprey Gunner / Escort Airdrop crash fix (root cause).
// maps\mp\killstreaks\_helicopter::init() EARLY-RETURNS on any map that has no
// heli flight-path nodes (heli_start / heli_loop_start) â€” which is every ported
// custom map (shipment, pool maps, rust_long, most DLC ports). That early return
// skips the helicopter config block, leaving level.heli_attract_strength /
// _attract_range / _targeting_delay / _maxhealth UNDEFINED. The Osprey Gunner and
// Escort Airdrop don't need flight paths (they fly to a player-picked drop point)
// and ARE still registered + precached by _escortairdrop::init(), so a player can
// use one â€” at which point createairship() calls
// missile_createattractorent(undefined) -> the call aborts -> the half-built
// airship has no usable view rig -> Com_ERROR: G_GetPlayerViewOrigin "tag_player"
// -> ShutdownGame (whole server dies, usually on a game-winning kill).
// Fix: if the helicopter system didn't initialize (node-less map), supply the
// stock helicopter config values so the Osprey path works. We do NOT precache the
// attack-helicopter/pavelow assets or register their killstreakfuncs, so the
// flyable attack helicopter stays disabled on these maps (no new crashes/bloat).
applyHeliConfig()
{
    // Numeric config block copied verbatim from _helicopter::init() (its lines 30-45).
    // Set UNCONDITIONALLY â€” these are the exact stock values, so node-full maps (where
    // _helicopter::init also sets them) are unaffected; node-less maps finally get them.
    level.heli_missile_rof            = 5;
    level.heli_maxhealth              = 2000;
    level.heli_debug                  = 0;
    level.heli_targeting_delay        = 0.5;
    level.heli_turretreloadtime       = 1.5;
    level.heli_turretclipsize         = 40;
    level.heli_visual_range           = 3700;
    level.heli_target_spawnprotection = 5;
    level.heli_target_recognition     = 0.5;
    level.heli_missile_friendlycare   = 256;
    level.heli_missile_target_cone    = 0.3;
    level.heli_armor_bulletdamage     = 0.3;
    level.heli_attract_strength       = 1000;
    level.heli_attract_range          = 4096;
    level.heli_angle_offset           = 90;
    level.heli_forced_wait            = 0;

    // _escortairdrop::init() computed osprey maxhealth as (heli_maxhealth * 2) while
    // heli_maxhealth was still undefined; recompute now that it's set.
    if ( isdefined( level.ospreysettings ) )
    {
        if ( isdefined( level.ospreysettings["osprey_gunner"] ) )
            level.ospreysettings["osprey_gunner"].maxhealth = level.heli_maxhealth * 2;
        if ( isdefined( level.ospreysettings["escort_airdrop"] ) )
            level.ospreysettings["escort_airdrop"].maxhealth = level.heli_maxhealth * 2;
    }
}

// Guarded replacement for maps\mp\_animatedmodels::animatemodel. Some maps (e.g.
// mp_highrise's roof-vent) have an "animated_model" entity whose model has no
// registered animation set in level.anim_prop_models AND no self.animation
// fallback. Stock animatemodel then runs getarraykeys/randomint/index on undefined
// and spams 4 runtime errors per prop at map load. We skip those props (they
// weren't animating anyway); otherwise this is identical to the stock function.
animatemodel_safe()
{
    if ( isdefined( self.animation ) )
        var_0 = self.animation;
    else
    {
        if ( !isdefined( self.model ) || !isdefined( level.anim_prop_models[self.model] ) )
        {
            // CAUSE (established 2026-07-31): _animatedmodels::main starts level.anim_prop_models
            // EMPTY and never fills it - the MAP's own script is supposed to register its anim
            // sets before that runs. Stock maps do; custom ports ship the animated_model entities
            // without the registration.
            // This skip is PERMANENT and correct: playing an animation needs a valid anim name
            // from the model's set in the fastfile, which cannot be invented from script. A
            // decorative prop not animating is harmless.
            // Name the model once per map so it CAN be registered properly later if anyone wants
            // to. Once, not per prop - some maps have many and this must not become the new flood.
            if ( !isdefined( level.bpg_animwarned ) )
                level.bpg_animwarned = [];

            if ( isdefined( self.model ) && !isdefined( level.bpg_animwarned[self.model] ) )
            {
                level.bpg_animwarned[self.model] = true;
                println( "[BPG-ANIM] " + getDvar( "mapname" ) + ": model '" + self.model + "' has no registered anim set - prop left static" );
            }
            return;
        }
        var_1 = getarraykeys( level.anim_prop_models[self.model] );
        if ( !isdefined( var_1 ) || var_1.size == 0 )
            return;
        var_0 = level.anim_prop_models[self.model][var_1[randomint( var_1.size )]];
    }

    self scriptmodelplayanim( var_0 );
    self willneverchange();
}

tuneBotKnife()
{
    wait 1;
    level.bots_maxknifedistance = 50 * 50;  // 50 units (down from 128)
}

restoreRotationOnFirstSpawn()
{
    level waittill("connected", player);
    wait 10;
    setDvar("sv_maprotation", "map mp_bootleg map mp_dome map mp_hardhat map mp_carbon map mp_interchange map mp_lambeth map mp_mogadishu map mp_paris map mp_plaza2 map mp_radar map mp_seatown map mp_nuked map mp_favela map mp_highrise map mp_nightshift map mp_rust map mp_alpha map mp_bravo map mp_exchange map mp_underground map mp_village map mp_aground_ss map mp_courtyard_ss map mp_terminal_cls map mp_raid map mp_afghan map mp_firingrange map mp_boardwalk map mp_burn_ss map mp_cement map mp_crosswalk_ss map mp_hillside_ss map mp_italy map mp_meteora map mp_moab map mp_nola map mp_overwatch map mp_park map mp_qadeem map mp_restrepo_ss map mp_roughneck map mp_shipbreaker map mp_six_ss map mp_killhouse map mp_estate map mp_mountain map mp_boomtown map mp_melee_resort map mp_lockout_h2 map mp_gulag map mp_bog_sh map mp_bo2cove map mp_bo2frost map mp_bo2grind map mp_bo2paintball map mp_brecourt map mp_broadcast map mp_burgundy map mp_checkpoint map mp_csgo_mirage map mp_csgo_stmarc map mp_efa_lake map mp_geometric map mp_gob_aim_snow map mp_minecraft map mp_minecraft_3 map mp_osg_hijacked map mp_osg_mirage_n map mp_overpass map mp_safehouse map mp_shipmentlong map mp_shortdust map mp_showdown_sh map mp_toujane map mp_cargoship_sh map mp_strike_sh map mp_prison map mp_tunisia map mp_bloc_2 map mp_crash");
}

monitorFirstPlayer()
{
    // Wait for first human to connect, then enable bots
    level waittill("connected", player);
    wait 2;
    // 14 is the ceiling that reliably allows human joins. sv_maxclients is 18,
    // but IW5's party/lobby system reserves ~2 slots for connection overhead,
    // so real usable capacity is ~16. Empirically: fill 16 = "server full"
    // (0 usable free), fill 10 = fine. 14 leaves a safe ~2-slot join buffer.
    // Do NOT raise toward 16+ â€” that re-triggers the "server full" bug.
    botFill = 14;
    // yourserver.gg: osg_hijacked is a yacht ringed by ocean; bots walk off the deck into the
    // water and the bot AI hammers the server's main thread every frame -> rubber-bands
    // ALL players + bots (confirmed 2026-06-28: draining bots = smooth). Cap fill low on
    // such maps. To add another bad map: || level.script == "mp_xxx"  (tune 6 as needed).
    if ( level.script == "mp_osg_hijacked" )
        botFill = 6;
    setDvar("bots_manage_fill",      botFill);
    setDvar("bots_manage_fill_mode",  0);
    setDvar("bots_manage_fill_kick",  1);
    setDvar("bots_manage_fill_spec",  0);
    setDvar("bots_skill",             1);
    setDvar("bots_loadout_allow_op",  0);
    // Disable bot killstreaks. Bots calling airdrops/care packages on custom maps
    // (pool maps, rust_long) triggers "clonebrushmodeltoscriptmodel" errors because
    // those maps lack the brush model entity the killstreak system needs.
    // NOTE: Human players using airdrop killstreaks on pool maps will still
    // throw the same error. It's cosmetic (no crash) but logged to console.
    setDvar("bots_play_killstreak",   0);
    // Bot text chat rate. bots_main_chat controls BotDoChat in z_svr_bots.iwd.
    // 1.0 = default chatter, higher = more, 0 = silent. (Voice quickmessages are
    // a separate system, kept off via bots_play_quickmessage â€” they throw errors.)
    setDvar("bots_main_chat", 0);
}
