// yourserver.gg 2026-07-17 — fix the favela/highrise red "ribbons": they are the engine's
// red 3D "Fx" PLACEHOLDER for effects whose assets aren't in any loaded fastfile.
// The survival mod loads spec-ops assets (smoke/so_chemical_* etc.) that exist in
// LAUNCH-map fastfiles but NOT in DLC map ffs (favela/highrise never shipped a
// survival mode) — so every Chemical Agent's back-tank gas stream, chemical death
// burst and chemical mine ran as red Fx (= the "ribbons"; CH22's map files are
// byte-identical to ours, proving it was never the maps).
// Substitutes VERIFIED PRESENT in both maps' zones (zone-string diff 2026-07-17):
//   chemical tank burst  -> explosions/oxygen_tank_explosion (white gas burst)
//   chemical gas stream  -> smoke/hallway_smoke_light
//   chemical mine spew   -> smoke/room_smoke_200
// ⚠️ 2026-07-19 CORRECTION: user still saw the red ribbon on THEIR OWN character
// (the chemical agent's tag_shield_back gas stream) after this "fix" was live on
// highrise. Root cause: the original v1 approach overwrote the SHARED
// level._effect[...]/level.breakables_fx[...] tables 1s after init, betting that
// was later than the mod's own _chemical.gsc::init() (which sets those same keys
// back to the broken originals). That's a race, not a fix — on a slower map-load
// (more scripts compiling) the mod's init can still land after our 1s mark and
// silently re-clobber the keys back to the missing DLC assets. FIX: stop touching
// the shared tables at all — replaceFunc the 3 chemical-ability functions that
// actually READ them (smokeFx/detonation/mineMonitor) with copies that read ONLY
// our own level.bpg_fxsub table, which nothing but this file ever writes. No race
// possible.
// ⚠️ 2026-07-19: barrel breakables_fx substitution MOVED OUT of this file entirely,
// into bpg_survival_barrelfxfix.gsc - a report of the SAME red-fx-placeholder on
// mp_sharqi_day's oil barrels (task #41) proved barrels aren't favela/highrise-
// specific, so that fix is now map-generic (not gated to these two maps) and uses
// the race-free watcher pattern instead of this file's old one-shot delayed write.
// Keeping a second barrel-fx writer here would just race against that file.

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	map = getDvar( "mapname" );
	if ( map != "mp_favela" && map != "mp_highrise" )
		return;

	// init phase: register substitute fx now (loadfx is only legal at init)
	level.bpg_fxsub = [];
	level.bpg_fxsub[ "chem_burst" ]  = loadfx( "explosions/oxygen_tank_explosion" );
	level.bpg_fxsub[ "chem_stream" ] = loadfx( "smoke/hallway_smoke_light" );
	level.bpg_fxsub[ "chem_spew" ]   = loadfx( "smoke/room_smoke_200" );

	// race-free: detour the 3 functions directly, bypass the shared tables entirely
	replaceFunc( lethalbeats\survival\abilities\_chemical::smokeFx, ::bpg_chem_smokeFx_fixed );
	replaceFunc( lethalbeats\survival\abilities\_chemical::detonation, ::bpg_chem_detonation_fixed );
	replaceFunc( lethalbeats\survival\abilities\_chemical::mineMonitor, ::bpg_chem_mineMonitor_fixed );

}

// byte-for-byte copies of _chemical.gsc's functions, reading level.bpg_fxsub
// instead of the shared level._effect table (see CORRECTION above).
bpg_chem_smokeFx_fixed()
{
	level endon( "game_ended" );
	self endon( "detonate" );

	for ( ;; )
	{
		wait 0.1;
		playFXOnTag( level.bpg_fxsub[ "chem_stream" ], self, "tag_shield_back" );
	}
}

bpg_chem_detonation_fixed( tank, origin )
{
	tank playsound( "detpack_explo_main" );
	earthquake( 0.2, 0.4, origin, 600 );
	playfx( level.bpg_fxsub[ "chem_burst" ], origin );
	tank unlink();
	wait 0.05;
	tank delete();

	for ( i = 0; i < 10; i++ )
	{
		foreach ( player in level.players )
			if ( lethalbeats\collider::pointInSphere( player.origin, origin, 70 ) )
			{
				player shellshock( "radiation_low", 0.45 );
				player viewKick( 3, origin );
			}

		radiusdamage( origin, 70, 200, 20, self, "MOD_TRIGGER_HURT" );
		wait 0.5;
	}
}

bpg_chem_mineMonitor_fixed()
{
	level endon( "game_ended" );
	self endon( "death" );

	for ( ;; )
	{
		self waittill( "claymore_stuck", claymore );

		claymore hide();

		mine = spawn( "script_model", claymore.origin + ( 0, 0, 3 ) );
		mine setModel( "ims_scorpion_explosive1" );
		mine setCanDamage( false );
		mine notSolid();
		mine setContents( 0 );

		fxEnt = SpawnFx( level.bpg_fxsub[ "chem_spew" ], mine.origin );
		triggerFx( fxEnt );

		// mineDeathMonitor itself doesn't touch any fx table (just waits on
		// "death" then calls self detonation(...)), and replaceFunc above
		// already globally redirects that detonation call to our fixed
		// version - safe to reuse the original unmodified.
		self thread lethalbeats\survival\abilities\_chemical::mineDeathMonitor( claymore, mine, fxEnt );
	}
}
