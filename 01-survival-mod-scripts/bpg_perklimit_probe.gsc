// bpg_perklimit_probe.gsc — verifies bpg_survival_perklimit.gsc actually lets a player hold
// more than 3 survival perks. INERT unless bpg_perklimit_probe=1 (side-test cfg only).

init()
{
	if ( getDvarInt( "bpg_perklimit_probe" ) != 1 )
		return;

	level thread bpg_perklimit_probe_run();
}

bpg_perklimit_probe_run()
{
	wait 15;

	p = addtestclient();
	if ( !isDefined( p ) )
	{
		println( "[PERKPROBE] FAIL addtestclient undefined" );
		return;
	}
	waited = 0;
	while ( ( !isDefined( p.sessionstate ) || p.sessionstate != "playing" || !isAlive( p ) ) && waited < 60 )
	{
		wait 1;
		waited++;
	}
	if ( !isDefined( p.survivalPerks ) )
		p.survivalPerks = [];
	println( "[PERKPROBE] " + p.name + " ready after " + waited + "s, survivalPerks.size(pre)=" + p.survivalPerks.size );

	perks = [ "specialty_marathon", "specialty_sleightofhand", "specialty_bulletdamage", "specialty_holdbreath", "specialty_lightweight" ];
	foreach ( perk in perks )
		p lethalbeats\survival\utility::survivor_give_perk( perk );

	wait 0.5;

	allHeld = true;
	foreach ( perk in perks )
	{
		held = p lethalbeats\player::player_has_perk( perk );
		println( "[PERKPROBE] " + perk + " held=" + held );
		if ( !held )
			allHeld = false;
	}

	println( "[PERKPROBE] RESULT survivalPerks.size=" + p.survivalPerks.size + " (gave " + perks.size + ")" );
	if ( allHeld && p.survivalPerks.size == perks.size )
		println( "[PERKPROBE] PASS - perk limit removed, all " + perks.size + " perks held." );
	else
		println( "[PERKPROBE] FAIL - not all perks held or size mismatch." );
}
