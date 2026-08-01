// bpg_survival_barrelfxfix.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-19.
// Task #41: user reported exploding oil barrels on mp_sharqi_day showing a red "FX"
// text placeholder instead of the real explosion/fire effect - confirmed via direct
// question this is the SAME missing-fx-asset placeholder class as the favela/highrise
// chemical-agent bug (bpg_survival_fxsubst.gsc), not a leftover/orphaned fx loop.
// lethalbeats\Survival\patch\globallogic.gsc's own init() sets:
//     level.breakables_fx["barrel"]["explode"]    = loadfx("props/barrelExp");
//     level.breakables_fx["barrel"]["burn_start"]  = loadfx("props/barrel_fire_top");
//     level.breakables_fx["barrel"]["burn"]        = loadfx("props/barrel_fire_top");
// "props/barrelExp" and "props/barrel_fire_top" are LAUNCH-map assets (same family as
// favela/highrise's missing so_chemical_* fx) - any ported/DLC map missing them in its
// loaded zone gets the red placeholder. This isn't favela/highrise-specific: any map
// could be missing these, so this fix is NOT map-gated (unlike bpg_survival_fxsubst.gsc).
// SUBSTITUTES: reuse explosions/aerial_explosion + fire/fire_smoke_trail_L_emitter -
// these are CORE STOCK helicopter-killstreak assets (maps/mp/killstreaks/_helicopter.gsc's
// own init table), not spec-ops/DLC-exclusive content, and are already independently
// confirmed loadable with zero errors via bpg_survival_chopperfxinit.gsc's own probe on
// multiple maps (mp_dome, mp_offshore_sh, mp_highrise) - stronger evidence of universal
// availability than a single map's zone-string grep would give.
// MECHANICS: I don't have _explosive_barrels.gsc's exact IW5 source (not in any public
// decompile repo checked, and a blind full-file replaceFunc guess risks breaking barrel
// explosions on EVERY map if wrong - not worth it for a cosmetic bug). So this ONLY
// substitutes fx handles in the shared level.breakables_fx table, same risk-minimal
// approach as barrels always used, but made RACE-FREE: instead of a single delayed
// overwrite (which could still lose to a slow mod-init - the same bug that made the v1
// favela/highrise fxsubst insufficient), a short watcher keeps re-asserting our values
// for the first 10s of map life so our substitution is always the LAST write, whenever
// globallogic.gsc's own init happens to land.

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	level.bpg_barrelfxsub = [];
	level.bpg_barrelfxsub[ "explode" ] = loadfx( "explosions/aerial_explosion" );
	level.bpg_barrelfxsub[ "fire" ] = loadfx( "fire/fire_smoke_trail_L_emitter" );

	level thread bpg_barrelfx_watch();
}

bpg_barrelfx_watch()
{
	level endon( "game_ended" );

	for ( t = 0; t < 20; t++ )
	{
		if ( !isDefined( level.breakables_fx ) )
			level.breakables_fx = [];

		level.breakables_fx[ "barrel" ][ "explode" ] = level.bpg_barrelfxsub[ "explode" ];
		level.breakables_fx[ "barrel" ][ "burn_start" ] = level.bpg_barrelfxsub[ "fire" ];
		level.breakables_fx[ "barrel" ][ "burn" ] = level.bpg_barrelfxsub[ "fire" ];

		wait 0.5;
	}

	println( "bpg_barrelfxfix: barrel fx substitutes applied/held on " + getDvar( "mapname" ) );
}
