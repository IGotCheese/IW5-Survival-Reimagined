// bpg_expfog_probe.gsc — empirically tests setExpFog argument variants to determine if
// mp_tundra_depot's load-time error is a fixable arg-count/type mismatch or a deeper
// engine-level MP limitation. INERT unless bpg_expfog_probe=1.

init()
{
	if ( getDvarInt( "bpg_expfog_probe" ) != 1 )
		return;

	level thread bpg_expfog_probe_run();
}

bpg_expfog_probe_run()
{
	wait 3;

	println( "[EXPFOG] test A: 6 args (map's exact original call)" );
	setExpFog( 1000, 3000, 0.6, 0.6, 0.6, 0 );
	println( "[EXPFOG] test A: survived (no error thrown before this line)" );

	wait 0.5;
	println( "[EXPFOG] test B: 5 args (no trailing 0)" );
	setExpFog( 1000, 3000, 0.6, 0.6, 0.6 );
	println( "[EXPFOG] test B: survived" );

	wait 0.5;
	println( "[EXPFOG] test C: floats instead of ints for distances" );
	setExpFog( 1000.0, 3000.0, 0.6, 0.6, 0.6, 0.0 );
	println( "[EXPFOG] test C: survived" );

	println( "[EXPFOG] ALL TESTS COMPLETE" );
}
