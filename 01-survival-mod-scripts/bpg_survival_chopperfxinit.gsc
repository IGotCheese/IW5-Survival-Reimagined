// bpg_survival_chopperfxinit.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-19.
// Root cause of a MASSIVE, MAP-UNIVERSAL error flood: "playfxontag/playfx/stopfxontag:
// parameter 0 has type 'undefined'" + "type 'undefined' cannot be indexed" from
// lethalbeats\Survival\abilities\_chopper.gsc (lbSurvivalHandleDamage, lbSupport_lightFX
// via _helicopter_guard), lethalbeats\Survival\abilities\_juggernaut.gsc (_mi17_fx), and
// maps\mp\killstreaks\_helicopter_guard.gsc (lbSupport_lightFX/lbExplode/lbSpin/trail_fx).
// All of those read the GLOBAL level.chopper_fx table, which is normally built by stock
// maps\mp\killstreaks\_helicopter.gsc's own init() - but that init() does:
//     var_0 = getentarray("heli_start", "targetname");
//     var_1 = getentarray("heli_loop_start", "targetname");
//     if (!var_0.size && !var_1.size) return;   <-- bails BEFORE setting level.chopper_fx
// None of our survival maps (custom ports, or stock maps never built for the "Chopper
// Gunner" killstreak) have those entities, so level.chopper_fx is NEVER populated -
// yet survival's own chopper/juggernaut abilities assume it always exists and call
// playfxontag/playfx/stopfxontag against it unconditionally, firing this error on
// EVERY chopper spawn, EVERY hit on a chopper, and EVERY juggernaut MI-17 drop, on
// EVERY map. This is very likely what read as "fx issues" in the field - broken/missing
// light and damage-state fx on every chopper and juggernaut transport, constantly.
// Fix: populate level.chopper_fx ourselves at init, byte-for-byte matching stock
// _helicopter.gsc's own table (same fx paths) so nothing downstream can tell the
// difference. Guarded so a real heli_start/heli_loop_start map (if one's ever added)
// just gets its already-fine level.chopper_fx overwritten with the same values.

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	level.chopper_fx[ "explode" ][ "death" ] = [];
	level.chopper_fx[ "explode" ][ "air_death" ] = [];
	level.chopper_fx[ "explode" ][ "large" ] = loadfx( "explosions/helicopter_explosion_secondary_small" );
	level.chopper_fx[ "explode" ][ "medium" ] = loadfx( "explosions/aerial_explosion" );
	level.chopper_fx[ "smoke" ][ "trail" ] = loadfx( "smoke/smoke_trail_white_heli" );
	level.chopper_fx[ "fire" ][ "trail" ][ "medium" ] = loadfx( "fire/fire_smoke_trail_L_emitter" );
	level.chopper_fx[ "fire" ][ "trail" ][ "large" ] = loadfx( "fire/fire_smoke_trail_L" );
	level.chopper_fx[ "damage" ][ "light_smoke" ] = loadfx( "smoke/smoke_trail_white_heli_emitter" );
	level.chopper_fx[ "damage" ][ "heavy_smoke" ] = loadfx( "smoke/smoke_trail_black_heli_emitter" );
	level.chopper_fx[ "damage" ][ "on_fire" ] = loadfx( "fire/fire_smoke_trail_L_emitter" );
	level.chopper_fx[ "light" ][ "left" ] = loadfx( "misc/aircraft_light_wingtip_green" );
	level.chopper_fx[ "light" ][ "right" ] = loadfx( "misc/aircraft_light_wingtip_red" );
	level.chopper_fx[ "light" ][ "belly" ] = loadfx( "misc/aircraft_light_red_blink" );
	level.chopper_fx[ "light" ][ "tail" ] = loadfx( "misc/aircraft_light_white_blink" );

	if ( !isDefined( level.fx_heli_dust ) )
		level.fx_heli_dust = loadfx( "treadfx/heli_dust_default" );
	if ( !isDefined( level.fx_heli_water ) )
		level.fx_heli_water = loadfx( "treadfx/heli_water" );

	// per-heliType death/air-death fx (stock makeHeliType/addAirExplosion calls) -
	// littlebird is what survival's own chopper support ability actually spawns
	// (lethalbeats\Survival\abilities\_chopper::createLBSurvival -> heliType =
	// "littlebird_support", spawned model uses the "littlebird" explosion set);
	// the rest are included for completeness since _helicopter_guard's stock
	// functions are shared code and could reference any of them.
	level.chopper_fx[ "explode" ][ "death" ][ "cobra" ] = loadfx( "explosions/helicopter_explosion_cobra_low" );
	level.chopper_fx[ "explode" ][ "air_death" ][ "cobra" ] = loadfx( "explosions/aerial_explosion_cobra_low_mp" );
	level.chopper_fx[ "explode" ][ "death" ][ "pavelow" ] = loadfx( "explosions/helicopter_explosion_pavelow" );
	level.chopper_fx[ "explode" ][ "air_death" ][ "pavelow" ] = loadfx( "explosions/aerial_explosion_pavelow_mp" );
	level.chopper_fx[ "explode" ][ "death" ][ "mi28" ] = loadfx( "explosions/helicopter_explosion_mi28_flying" );
	level.chopper_fx[ "explode" ][ "air_death" ][ "mi28" ] = loadfx( "explosions/aerial_explosion_mi28_flying_mp" );
	level.chopper_fx[ "explode" ][ "death" ][ "hind" ] = loadfx( "explosions/helicopter_explosion_hind_chernobyl" );
	level.chopper_fx[ "explode" ][ "air_death" ][ "hind" ] = loadfx( "explosions/aerial_explosion_hind_chernobyl_mp" );
	level.chopper_fx[ "explode" ][ "death" ][ "apache" ] = loadfx( "explosions/helicopter_explosion_apache" );
	level.chopper_fx[ "explode" ][ "air_death" ][ "apache" ] = loadfx( "explosions/aerial_explosion_apache_mp" );
	level.chopper_fx[ "explode" ][ "death" ][ "littlebird" ] = loadfx( "explosions/aerial_explosion_littlebird_mp" );
	level.chopper_fx[ "explode" ][ "air_death" ][ "littlebird" ] = loadfx( "explosions/aerial_explosion_littlebird_mp" );

	println( "bpg_chopperfxinit: level.chopper_fx populated (stock _helicopter.gsc init never runs on our maps - no heli_start/heli_loop_start nodes)" );
}
