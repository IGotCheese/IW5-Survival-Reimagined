// yourserver.gg SHARPSHOOTER -- dvar-gated overlay on a stock gametype (the vote runs it
// on TDM). Rebuilt from LastDemon99's TestModes ss.gsc (private-match-only custom
// gametype). Rules: everyone fights with the SAME random weapon; it cycles every
// bpg_ss_cycle seconds (default 45). Bare guns only -- attachment/camo variants
// precache-miss on custom maps (the AA-12 invisible-hands lesson).
// Activation: seta bpg_mode_ss 1 before map load (the mapvote sets/clears it).
// Bots: init sets level.gun_guns, which trips the bpg gate in botGiveLoadout
// (z_svr_bots.iwd) so bot loadouts don't fight the shared gun.
#include common_scripts\utility;
#include maps\mp\_utility;

init()
{
    if ( getdvarint( "bpg_mode_ss" ) != 1 )
        return;

    // one-shot: consume the flag so the mode never leaks past its map
    setdvar( "bpg_mode_ss", 0 );

    if ( getdvar( "bpg_ss_cycle" ) == "" )
        setdvar( "bpg_ss_cycle", 45 );

    // trip the bots' loadout-skip gate (they get the shared gun instead)
    level.gun_guns = [];

    level.bpg_ss_pool = bpg_ss_buildpool();
    level.bpg_ss_gun = undefined;

    level thread bpg_ss_setup();
    level thread bpg_ss_modelabel();
}

bpg_ss_setup()
{
    level endon( "game_ended" );

    bpg_ss_rollgun();

    level thread bpg_ss_connects();

    level waittill( "prematch_over" );
    iprintlnbold( "^3SHARPSHOOTER^7: everyone gets the same gun -- it changes every " + getdvarint( "bpg_ss_cycle" ) + "s" );
    level thread bpg_ss_cycle();
}

bpg_ss_buildpool()
{
    // solid all-map pool: stock base weapons only (always precached)
    pool = [];
    pool[pool.size] = "iw5_m4";        pool[pool.size] = "iw5_ak47";
    pool[pool.size] = "iw5_scar";      pool[pool.size] = "iw5_g36c";
    pool[pool.size] = "iw5_acr";       pool[pool.size] = "iw5_type95";
    pool[pool.size] = "iw5_mp5";       pool[pool.size] = "iw5_ump45";
    pool[pool.size] = "iw5_p90";       pool[pool.size] = "iw5_pp90m1";
    pool[pool.size] = "iw5_mp7";       pool[pool.size] = "iw5_spas12";
    pool[pool.size] = "iw5_ksg";       pool[pool.size] = "iw5_aa12";
    pool[pool.size] = "iw5_striker";   pool[pool.size] = "iw5_1887";
    pool[pool.size] = "iw5_m60";       pool[pool.size] = "iw5_mk46";
    pool[pool.size] = "iw5_pecheneg";  pool[pool.size] = "iw5_barrett";
    pool[pool.size] = "iw5_msr";       pool[pool.size] = "iw5_rsass";
    pool[pool.size] = "iw5_dragunov";  pool[pool.size] = "iw5_usp45";
    pool[pool.size] = "iw5_deserteagle"; pool[pool.size] = "iw5_mp412";
    pool[pool.size] = "iw5_fmg9";      pool[pool.size] = "iw5_skorpion";
    pool[pool.size] = "iw5_g18";       pool[pool.size] = "iw5_mp9";
    return pool;
}

bpg_ss_rollgun()
{
    // roll a DIFFERENT gun than the current one
    for ( tries = 0; tries < 10; tries++ )
    {
        pick = level.bpg_ss_pool[ randomint( level.bpg_ss_pool.size ) ] + "_mp";

        if ( !isdefined( level.bpg_ss_gun ) || pick != level.bpg_ss_gun )
        {
            level.bpg_ss_gun = pick;
            bpg_ss_diag( "bpg_ss: new gun = " + pick );
            return;
        }
    }
}

bpg_ss_connects()
{
    level endon( "game_ended" );

    for (;;)
    {
        level waittill( "connected", player );
        player thread bpg_ss_onspawn();
        player thread bpg_ss_onkill();
    }
}

bpg_ss_onspawn()
{
    self endon( "disconnect" );
    level endon( "game_ended" );

    for (;;)
    {
        self waittill( "spawned_player" );
        wait 0.1;   // land after the loadout give
        self bpg_ss_givegun( 1 );
    }
}

bpg_ss_onkill()
{
    self endon( "disconnect" );
    level endon( "game_ended" );

    for (;;)
    {
        self waittill( "killed_enemy" );

        if ( isalive( self ) && isdefined( level.bpg_ss_gun ) && self bpg_ss_hasweapon( level.bpg_ss_gun ) )
            self givemaxammo( level.bpg_ss_gun );
    }
}

bpg_ss_cycle()
{
    level endon( "game_ended" );

    for (;;)
    {
        wait getdvarint( "bpg_ss_cycle" );

        bpg_ss_rollgun();

        if ( soundexists( "mp_killconfirm_tags_pickup" ) )
        {
            foreach ( player in level.players )
            {
                if ( isdefined( player ) )
                    player bpg_ss_localsound( "mp_killconfirm_tags_pickup" );
            }
        }

        foreach ( player in level.players )
        {
            if ( isdefined( player ) && isalive( player ) )
                player bpg_ss_givegun( 0 );
        }

        iprintlnbold( "^3New weapon!" );
    }
}

bpg_ss_givegun( onSpawn )
{
    if ( !isalive( self ) || !isdefined( level.bpg_ss_gun ) )
        return;

    self takeallweapons();
    self _giveweapon( level.bpg_ss_gun );

    // guard: if the shared gun didn't actually give (bad name or not precached on
    // this map), fall back to the USP .45 (precached everywhere) so we never
    // switchto / givemaxammo a weapon the player doesn't have -> no runtime error,
    // and the player is never left empty-handed.
    gun = level.bpg_ss_gun;
    if ( !self bpg_ss_hasweapon( gun ) )
    {
        gun = "iw5_usp45_mp";
        self _giveweapon( gun );
    }

    if ( onSpawn )
        self setspawnweapon( gun );
    else
        self switchtoweaponimmediate( gun );

    if ( self bpg_ss_hasweapon( gun ) )
        self givemaxammo( gun );

    self.pers["primaryWeapon"] = getbaseweaponname( gun );
}

// "self hasweapon(name)" throws when name isn't a valid weapon asset; getweaponslistall
// only reports what the player actually holds and never takes the suspect name as input.
bpg_ss_hasweapon( name )
{
    weapons = self getweaponslistall();

    if ( !isdefined( weapons ) )
        return false;

    for ( i = 0; i < weapons.size; i++ )
    {
        if ( weapons[i] == name )
            return true;
    }

    return false;
}

bpg_ss_localsound( alias )
{
    self playlocalsound( alias );
}

bpg_ss_diag( s )
{
	if ( isdefined( level.bot_builtins ) && isdefined( level.bot_builtins["printconsole"] ) )
		[[ level.bot_builtins["printconsole"] ]]( s );
}

bpg_ss_modelabel()
{
	level endon( "game_ended" );

	game["strings"]["allies_name"] = "SHARPSHOOTER";
	game["strings"]["axis_name"] = "SHARPSHOOTER";

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
	label settext( "SHARPSHOOTER" );

	level waittill( "game_ended" );
	label destroy();
}