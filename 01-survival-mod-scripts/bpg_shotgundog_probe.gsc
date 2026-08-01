// bpg_shotgundog_probe.gsc — verifies the shotgun-vs-dog +120% damage buff directly, without
// needing a real dog bot (headless side-tests never spawn natural enemy AI - see
// bpg_unblock_probe.gsc). bot_is_dog() is just `self.botType == "dog"` (confirmed via source:
// lethalbeats\Survival\utility.gsc's bot_has_ability), so a plain test client with that field
// set behaves identically to a real dog for this check. INERT unless bpg_shotgundog_probe=1.

init()
{
	if ( getDvarInt( "bpg_shotgundog_probe" ) != 1 )
		return;

	level thread bpg_shotgundog_probe_run();
}

bpg_shotgundog_probe_run()
{
	wait 15;

	target = addtestclient();
	if ( !isDefined( target ) )
	{
		println( "[SHOTGUNDOG] FAIL addtestclient undefined" );
		return;
	}
	waited = 0;
	while ( ( !isDefined( target.sessionstate ) || target.sessionstate != "playing" || !isAlive( target ) ) && waited < 60 )
	{
		wait 1;
		waited++;
	}

	baseDamage = 100;

	// A: dog + shotgun -> expect x2.2
	target.botType = "dog";
	dmgA = target lethalbeats\survival\bothandler::weaponDamageModifier( "iw5_spas12_mp", baseDamage, "MOD_RIFLE_BULLET", undefined, false );
	println( "[SHOTGUNDOG] A dog+shotgun(spas12) base=" + baseDamage + " result=" + dmgA + " (expect " + int( baseDamage * 2.2 ) + ")" );

	// B: dog + non-shotgun (ak47) -> expect unchanged (ak47 has no special case)
	dmgB = target lethalbeats\survival\bothandler::weaponDamageModifier( "iw5_ak47_mp", baseDamage, "MOD_RIFLE_BULLET", undefined, false );
	println( "[SHOTGUNDOG] B dog+non-shotgun(ak47) base=" + baseDamage + " result=" + dmgB + " (expect " + baseDamage + ")" );

	// C: non-dog + shotgun -> expect unchanged (no dog -> no buff)
	target.botType = undefined;
	dmgC = target lethalbeats\survival\bothandler::weaponDamageModifier( "iw5_spas12_mp", baseDamage, "MOD_RIFLE_BULLET", undefined, false );
	println( "[SHOTGUNDOG] C non-dog+shotgun(spas12) base=" + baseDamage + " result=" + dmgC + " (expect " + baseDamage + ")" );

	// tolerant compare - 2.2 isn't exactly representable in binary float
	expectA = baseDamage * 2.2;
	passA = ( dmgA > expectA - 0.5 && dmgA < expectA + 0.5 );
	passB = ( dmgB == baseDamage );
	passC = ( dmgC == baseDamage );

	println( "[SHOTGUNDOG] RESULT A=" + ( passA ? "PASS" : "FAIL" ) + " B=" + ( passB ? "PASS" : "FAIL" ) + " C=" + ( passC ? "PASS" : "FAIL" ) );
	if ( passA && passB && passC )
		println( "[SHOTGUNDOG] PASS - +120% shotgun-vs-dog damage confirmed, correctly scoped to dogs only." );
	else
		println( "[SHOTGUNDOG] FAIL - see individual results above." );
}
