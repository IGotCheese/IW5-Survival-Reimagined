// bpg_chopperfx_probe.gsc — verifies level.chopper_fx (and its subkeys actually hit by
// the error flood) are populated after bpg_survival_chopperfxinit.gsc's init() runs.
// INERT unless bpg_chopperfx_probe=1.

init()
{
	if ( getDvarInt( "bpg_chopperfx_probe" ) != 1 )
		return;

	level thread bpg_chopperfx_probe_run();
}

bpg_chopperfx_probe_run()
{
	wait 3;

	ok = true;

	if ( !isDefined( level.chopper_fx ) )
	{
		println( "[CHOPPERFX] FAIL level.chopper_fx entirely undefined" );
		return;
	}

	checks = [];
	checks[ 0 ] = "damage.light_smoke";
	checks[ 1 ] = "damage.heavy_smoke";
	checks[ 2 ] = "damage.on_fire";
	checks[ 3 ] = "light.left";
	checks[ 4 ] = "light.right";
	checks[ 5 ] = "light.belly";
	checks[ 6 ] = "light.tail";
	checks[ 7 ] = "smoke.trail";
	checks[ 8 ] = "explode.medium";
	checks[ 9 ] = "explode.large";

	if ( !isDefined( level.chopper_fx[ "damage" ][ "light_smoke" ] ) ) { println( "[CHOPPERFX] FAIL damage.light_smoke undefined" ); ok = false; }
	if ( !isDefined( level.chopper_fx[ "damage" ][ "heavy_smoke" ] ) ) { println( "[CHOPPERFX] FAIL damage.heavy_smoke undefined" ); ok = false; }
	if ( !isDefined( level.chopper_fx[ "damage" ][ "on_fire" ] ) ) { println( "[CHOPPERFX] FAIL damage.on_fire undefined" ); ok = false; }
	if ( !isDefined( level.chopper_fx[ "light" ][ "left" ] ) ) { println( "[CHOPPERFX] FAIL light.left undefined" ); ok = false; }
	if ( !isDefined( level.chopper_fx[ "light" ][ "right" ] ) ) { println( "[CHOPPERFX] FAIL light.right undefined" ); ok = false; }
	if ( !isDefined( level.chopper_fx[ "light" ][ "belly" ] ) ) { println( "[CHOPPERFX] FAIL light.belly undefined" ); ok = false; }
	if ( !isDefined( level.chopper_fx[ "light" ][ "tail" ] ) ) { println( "[CHOPPERFX] FAIL light.tail undefined" ); ok = false; }
	if ( !isDefined( level.chopper_fx[ "smoke" ][ "trail" ] ) ) { println( "[CHOPPERFX] FAIL smoke.trail undefined" ); ok = false; }
	if ( !isDefined( level.chopper_fx[ "explode" ][ "medium" ] ) ) { println( "[CHOPPERFX] FAIL explode.medium undefined" ); ok = false; }
	if ( !isDefined( level.chopper_fx[ "explode" ][ "air_death" ][ "littlebird" ] ) ) { println( "[CHOPPERFX] FAIL explode.air_death.littlebird undefined" ); ok = false; }

	if ( ok )
		println( "[CHOPPERFX] PASS - all fx handles populated on " + getDvar( "mapname" ) );
	else
		println( "[CHOPPERFX] FAIL - see individual lines above" );
}
