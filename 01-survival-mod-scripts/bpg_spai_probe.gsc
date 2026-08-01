// bpg_spai_probe.gsc — checks whether the MP dedicated server binary exposes the
// singleplayer AI-actor builtins at all. isai() is the most fundamental one: nearly
// every SP AI script (aitype/*) branches on it. If the GSC COMPILER rejects this file
// outright ("couldn't determine function call type"), that's definitive proof the
// builtin isn't exposed in this binary — settles the question immediately, no need to
// go further. If it compiles, we log the runtime result and can test more (spawner
// functions, actual AI spawn) in a follow-up probe.
// INERT unless bpg_spai_probe=1 (side-test cfg only — never set on live).

init()
{
	if ( getDvarInt( "bpg_spai_probe" ) != 1 )
		return;

	level thread bpg_spai_probe_run();
}

bpg_spai_probe_run()
{
	wait 5;
	println( "[SPAIPROBE] armed - adding a test client" );

	victim = addtestclient();
	if ( !isDefined( victim ) )
	{
		println( "[SPAIPROBE] FAIL addtestclient undefined" );
		return;
	}
	waited = 0;
	while ( ( !isDefined( victim.sessionstate ) || victim.sessionstate != "playing" ) && waited < 30 )
	{
		wait 1;
		waited++;
	}

	println( "[SPAIPROBE] test client ready after " + waited + "s, calling isai() on it" );
	result = isai( victim );
	println( "[SPAIPROBE] RESULT isai(testclient) = " + result );
	println( "[SPAIPROBE] COMPILE+RUN SUCCEEDED - isai() builtin is exposed in this binary." );
}
