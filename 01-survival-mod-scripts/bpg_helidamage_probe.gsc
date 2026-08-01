// bpg_helidamage_probe.gsc — unit-tests bpg_survival_helidamage.gsc's isHeli branch directly,
// without needing a real flying helicopter or natural enemy AI (headless side-tests never spawn
// real bots - see bpg_unblock_probe.gsc). Spawns two dummy attacker entities (one with .helitype
// set, one without) and calls the replaceFunc'd damage function directly, comparing the resulting
// self.summary["damagetaken"] delta - a precise, deterministic readout of the computed iDamage
// that sidesteps body armor / health-clamping complications. INERT unless bpg_helidamage_probe=1.

init()
{
	if ( getDvarInt( "bpg_helidamage_probe" ) != 1 )
		return;

	level thread bpg_helidamage_probe_run();
}

bpg_helidamage_probe_run()
{
	wait 15;

	victim = addtestclient();
	if ( !isDefined( victim ) )
	{
		println( "[HELIDMGPROBE] FAIL addtestclient undefined" );
		return;
	}
	waited = 0;
	while ( ( !isDefined( victim.sessionstate ) || victim.sessionstate != "playing" || !isAlive( victim ) ) && waited < 60 )
	{
		wait 1;
		waited++;
	}
	if ( !isDefined( victim.summary ) )
		victim.summary = [];
	if ( !isDefined( victim.summary[ "damagetaken" ] ) )
		victim.summary[ "damagetaken" ] = 0;
	println( "[HELIDMGPROBE] " + victim.name + " ready after " + waited + "s" );

	normalAttacker = spawn( "script_origin", victim.origin );
	heliAttacker = spawn( "script_origin", victim.origin );
	heliAttacker.helitype = "flares_survial";

	before = victim.summary[ "damagetaken" ];
	// call the ORIGINAL symbol - replaceFunc redirects this to our bpg_onPlayerDamage_helifix,
	// exercising the real hook wiring instead of just our function in isolation.
	victim lethalbeats\survival\survivorHandler::onPlayerDamage( normalAttacker, normalAttacker, 200, 0, "MOD_PISTOL_BULLET", "test_weapon_mp", victim.origin, ( 0, 0, 1 ), "none", 0 );
	normalDelta = victim.summary[ "damagetaken" ] - before;
	println( "[HELIDMGPROBE] normal (non-heli) attacker: iDamage(200) -> damagetaken delta=" + normalDelta );

	before = victim.summary[ "damagetaken" ];
	victim lethalbeats\survival\survivorHandler::onPlayerDamage( heliAttacker, heliAttacker, 200, 0, "MOD_PISTOL_BULLET", "test_weapon_mp", victim.origin, ( 0, 0, 1 ), "none", 0 );
	heliDelta = victim.summary[ "damagetaken" ] - before;
	println( "[HELIDMGPROBE] heli attacker (helitype set): iDamage(200) -> damagetaken delta=" + heliDelta );

	println( "[HELIDMGPROBE] RESULT normalDelta=" + normalDelta + " heliDelta=" + heliDelta + " ratio=" + ( normalDelta / heliDelta ) );
	if ( normalDelta > 0 && heliDelta > 0 && ( normalDelta / heliDelta ) > 1.9 && ( normalDelta / heliDelta ) < 2.1 )
		println( "[HELIDMGPROBE] PASS - heli damage is ~50% of normal damage." );
	else
		println( "[HELIDMGPROBE] FAIL - ratio not ~2.0, heli damage reduction not working as intended." );

	normalAttacker delete();
	heliAttacker delete();
}
