// yourserver.gg destructible explode() error-storm fix -- runtime replaceFunc, NOT a file
// override. A loose common_scripts/_destructible.gsc override is IMPOSSIBLE here:
// Plutonium's live fastfile is newer than every public decompile (it has
// destructible_setdot_ontick, which _destructible_types links against -> instant
// LinkFile boot-death; proven on the <SIDETEST-PORT> side-test 2026-07-05). Instead this
// replaces just the two broken functions at runtime, same mechanism the mapvote
// script already uses for _animatedmodels::animatemodel. The fastfile stays intact.
//
// What it fixes (the ~10-signature error cascade, 76 NEW digest sigs on 07-05):
// broken/ported destructibles + chained re-explosions at very high weapon damage
// reach explode()/physics_launch() with missing part tables or model tags; every
// tag lookup then errors and undefined vectors flow into OP_minus/vectornormalize/
// spawn/physicslaunchclient/physicsexplosionsphere -> error spam, multi-second
// hitches, and the mp_six_ss-style populated-server freezes.

init()
{
    replaceFunc( common_scripts\_destructible::explode, ::bpg_explode_safe );
    replaceFunc( common_scripts\_destructible::physics_launch, ::bpg_physics_launch_safe );
    replaceFunc( common_scripts\_destructible::destructible_fx_think, ::bpg_destructible_fx_think_safe );
    setdvar( "bpg_destfix_active", 1 );
}

// stock destructible_fx_think() + one guard: gettagorigin on a missing tag returns
// undefined -> the stock code then errors on OP_minus + playfx(undefined). Skip that
// fx instead (x27 in the 07-05 digest, same broken-model class as explode()).
bpg_destructible_fx_think_safe( var_0, var_1, var_2, var_3, var_4 )
{
    if ( !isdefined( var_0["fx"] ) )
        return undefined;

    if ( !isdefined( var_4 ) )
        var_4 = randomint( var_0["fx_filename"].size );

    if ( !isdefined( var_0["fx"][var_4] ) )
        var_4 = randomint( var_0["fx_filename"].size );

    var_5 = var_0["fx_filename"][var_4].size;

    for ( var_6 = 0; var_6 < var_5; var_6++ )
    {
        if ( !common_scripts\_destructible::is_valid_damagetype( var_2, var_0, var_6, var_4 ) )
            continue;

        var_7 = var_0["fx"][var_4][var_6];

        if ( isdefined( var_0["fx_tag"][var_4][var_6] ) )
        {
            var_8 = var_0["fx_tag"][var_4][var_6];
            self notify( "FX_State_Change" + var_3 );

            if ( var_0["fx_useTagAngles"][var_4][var_6] )
                playfxontag( var_7, var_1, var_8 );
            else
            {
                var_9 = var_1 gettagorigin( var_8 );

                if ( !isdefined( var_9 ) )
                    continue;

                var_10 = var_9 + ( 0.0, 0.0, 100.0 ) - var_9;
                playfx( var_7, var_9, var_10 );
            }

            continue;
        }

        var_9 = var_1.origin;
        var_10 = var_9 + ( 0.0, 0.0, 100.0 ) - var_9;
        playfx( var_7, var_9, var_10 );
    }

    return var_4;
}

// stock explode() (13 args, decompile line 1565) + guards. Changes vs stock:
//  (1) exploded-once check is UNCONDITIONAL (stock skipped it when the force flag
//      var_6 was set -> forced RE-explosion of an already-gutted model = the cascade;
//      chain reactions still work, each neighbour runs its own first explode()).
//  (2) every gettagorigin result is checked; explosion origin falls back to
//      self.origin so downstream vector math + physicsexplosionsphere never see
//      undefined.
//  (3) missing part-table entries are skipped instead of dereferenced.
bpg_explode_safe( var_0, var_1, var_2, var_3, var_4, var_5, var_6, var_7, var_8, var_9, var_10, var_11, var_12 )
{
    if ( isdefined( var_3 ) && isdefined( level.destructible_explosion_radius_multiplier ) )
        var_3 *= level.destructible_explosion_radius_multiplier;

    if ( !isdefined( var_7 ) )
        var_7 = 80;

    if ( !isdefined( var_11 ) )
        var_11 = ( 0.0, 0.0, 0.0 );

    if ( isdefined( self.exploded ) )
        return;

    self.exploded = 1;

    if ( !isdefined( var_12 ) )
        var_12 = 0;

    self notify( "exploded", var_10 );
    level notify( "destructible_exploded" );

    if ( self.code_classname == "script_vehicle" )
        self notify( "death", var_10, self.damage_type );

    if ( common_scripts\utility::issp() )
        thread common_scripts\_destructible::disconnecttraverses();

    if ( !level.fast_destructible_explode )
        wait 0.05;

    if ( !isdefined( self ) )
        return;

    if ( !isdefined( self.destructible_parts ) || !isdefined( self.destructible_parts[var_0] ) )
        return;

    var_13 = self.destructible_parts[var_0].v["currentState"];
    var_14 = undefined;

    if ( isdefined( var_13 ) && isdefined( level.destructible_type[self.destructibleinfo].parts[var_0][var_13] ) )
        var_14 = level.destructible_type[self.destructibleinfo].parts[var_0][var_13].v["tagName"];

    var_15 = undefined;

    if ( isdefined( var_14 ) )
        var_15 = self gettagorigin( var_14 );

    if ( !isdefined( var_15 ) )
        var_15 = self.origin;

    self notify( "damage", var_5, self, ( 0.0, 0.0, 0.0 ), var_15, "MOD_EXPLOSIVE", "", "" );
    self notify( "stop_car_alarm" );
    waittillframeend;

    if ( isdefined( level.destructible_type[self.destructibleinfo].parts ) )
    {
        for ( var_16 = level.destructible_type[self.destructibleinfo].parts.size - 1; var_16 >= 0; var_16-- )
        {
            if ( var_16 == var_0 )
                continue;

            if ( !isdefined( self.destructible_parts[var_16] ) )
                continue;

            var_17 = self.destructible_parts[var_16].v["currentState"];

            if ( !isdefined( var_17 ) )
                continue;

            if ( var_17 >= level.destructible_type[self.destructibleinfo].parts[var_16].size )
                var_17 = level.destructible_type[self.destructibleinfo].parts[var_16].size - 1;

            var_18 = level.destructible_type[self.destructibleinfo].parts[var_16][var_17].v["modelName"];
            var_14 = level.destructible_type[self.destructibleinfo].parts[var_16][var_17].v["tagName"];

            if ( !isdefined( var_18 ) )
                continue;

            if ( !isdefined( var_14 ) )
                continue;

            if ( isdefined( level.destructible_type[self.destructibleinfo].parts[var_16][0].v["physicsOnExplosion"] ) )
            {
                if ( level.destructible_type[self.destructibleinfo].parts[var_16][0].v["physicsOnExplosion"] > 0 )
                {
                    var_19 = level.destructible_type[self.destructibleinfo].parts[var_16][0].v["physicsOnExplosion"];
                    var_20 = self gettagorigin( var_14 );

                    if ( !isdefined( var_20 ) )
                        continue;

                    var_21 = vectornormalize( var_20 - var_15 );
                    var_21 *= ( randomfloatrange( var_1, var_2 ) * var_19 );
                    thread bpg_physics_launch_safe( var_16, var_17, var_20, var_21 );
                    continue;
                }
            }
        }
    }

    var_22 = !isdefined( var_6 ) || isdefined( var_6 ) && !var_6;

    if ( var_22 )
        self notify( "stop_taking_damage" );

    if ( !level.fast_destructible_explode )
        wait 0.05;

    if ( !isdefined( self ) )
        return;

    var_23 = var_15 + ( 0, 0, var_7 ) + var_11;
    var_24 = getsubstr( level.destructible_type[self.destructibleinfo].v["type"], 0, 7 ) == "vehicle";

    if ( var_24 )
    {
        anim.lastcarexplosiontime = gettime();
        anim.lastcarexplosiondamagelocation = var_23;
        anim.lastcarexplosionlocation = var_15;
        anim.lastcarexplosionrange = var_3;
    }

    level thread common_scripts\_destructible::set_disable_friendlyfire_value_delayed( 1 );

    if ( var_12 > 0 )
        wait(var_12);

    if ( isdefined( level.destructible_protection_func ) )
        thread [[ level.destructible_protection_func ]]();

    if ( common_scripts\utility::issp() )
    {
        if ( level.gameskill == 0 && !common_scripts\_destructible::player_touching_post_clip() )
            self radiusdamage( var_23, var_3, var_5, var_4, self, "MOD_RIFLE_BULLET" );
        else
            self radiusdamage( var_23, var_3, var_5, var_4, self );

        if ( isdefined( self.damageowner ) && var_24 )
        {
            self.damageowner notify( "destroyed_car" );
            level notify( "player_destroyed_car", self.damageowner, var_23 );
        }
    }
    else
    {
        var_25 = "destructible_toy";

        if ( var_24 )
            var_25 = "destructible_car";

        if ( !isdefined( self.damageowner ) )
            self radiusdamage( var_23, var_3, var_5, var_4, self, "MOD_EXPLOSIVE", var_25 );
        else
        {
            self radiusdamage( var_23, var_3, var_5, var_4, self.damageowner, "MOD_EXPLOSIVE", var_25 );

            if ( var_24 )
            {
                self.damageowner notify( "destroyed_car" );
                level notify( "player_destroyed_car", self.damageowner, var_23 );
            }
        }
    }

    if ( isdefined( var_8 ) && isdefined( var_9 ) )
        earthquake( var_8, 2.0, var_23, var_9 );

    level thread common_scripts\_destructible::set_disable_friendlyfire_value_delayed( 0, 0.05 );
    var_26 = 0.01;
    var_27 = var_3 * var_26;
    var_3 *= 0.99;
    physicsexplosionsphere( var_23, var_3, 0, var_27 );

    if ( var_22 )
    {
        self setcandamage( 0 );
        thread common_scripts\_destructible::cleanupvars();
    }

    self notify( "destroyed" );
}

// stock physics_launch() + guards: bail out instead of erroring when the part entry,
// model, tag, or tag origin is missing (skipping the cosmetic part-toss is harmless).
bpg_physics_launch_safe( var_0, var_1, var_2, var_3 )
{
    if ( !isdefined( self.destructibleinfo ) || !isdefined( level.destructible_type[self.destructibleinfo].parts[var_0] ) )
        return;

    if ( !isdefined( level.destructible_type[self.destructibleinfo].parts[var_0][var_1] ) )
        return;

    var_4 = level.destructible_type[self.destructibleinfo].parts[var_0][var_1].v["modelName"];
    var_5 = level.destructible_type[self.destructibleinfo].parts[var_0][var_1].v["tagName"];

    if ( !isdefined( var_4 ) || !isdefined( var_5 ) )
        return;

    if ( !isdefined( var_2 ) )
        var_2 = self gettagorigin( var_5 );

    if ( !isdefined( var_2 ) )
        return;

    self hidepart( var_5 );

    if ( level.destructiblespawnedents.size >= level.destructiblespawnedentslimit )
        common_scripts\_destructible::physics_object_remove( level.destructiblespawnedents[0] );

    var_6 = spawn( "script_model", var_2 );

    if ( !isdefined( var_6 ) )
        return;

    var_7 = self gettagangles( var_5 );

    if ( !isdefined( var_7 ) )
        var_7 = ( 0.0, 0.0, 0.0 );

    var_6.angles = var_7;
    var_6 setmodel( var_4 );
    level.destructiblespawnedents[level.destructiblespawnedents.size] = var_6;

    if ( isdefined( var_3 ) )
        var_6 physicslaunchclient( var_2, var_3 );
}
