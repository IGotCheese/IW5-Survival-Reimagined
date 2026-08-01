// bpg_unblock_probe.gsc — survival.gsc's waitPlayers() blocks forever on level waittill
// ("bots_connected") in headless side-tests (nothing ever fires it), which means wave_start
// never notifies and NO enemy bots ever spawn — explains why the dog/heli probes found nothing
// no matter how long they waited. Manually firing the notify to unblock wave progression for
// testing. INERT unless bpg_unblock_probe=1 (side-test cfg only).

#include lethalbeats\survival\utility;

init()
{
	if ( getDvarInt( "bpg_unblock_probe" ) != 1 ) return;
	level thread bpg_unblock_run();
}

bpg_unblock_run()
{
	wait 5;
	println( "[UNBLOCK] firing bots_connected manually" );
	level notify( "bots_connected" );

	wait 3; // let waitPlayers() react; if it has its own further gate (e.g. survivors(true).size),
	        // go straight for what actually matters instead of chasing every internal condition
	println( "[UNBLOCK] firing wave_start directly as a fallback" );
	if ( !isDefined( level.wave_num ) )
		level.wave_num = level_get_wave();
	level notify( "wave_start" );
	println( "[UNBLOCK] done" );

	// 2026-07-19: DO NOT also force "wave_end" here. Tried it (loop forcing wave_end every 45s
	// to drive wave_num past the armory-unlock thresholds) and it crash-looped the side-test:
	// lethalbeats\Survival\killstreaks\_airdrop.gsc's _killstreakCrateThink -> _clearSurvivorAirdrop
	// -> array_remove_index went into a genuine infinite loop (hundreds of runtime errors/frame,
	// "potential infinite loop... Killing thread", then the whole bootstrapper process died).
	// Root cause not isolated - likely killstreak crate entities/self.owner.airdrops state that's
	// only ever valid when real bots/players exist to spawn and capture crates naturally; forcing
	// wave_end with no real players desyncs something upstream of _clearSurvivorAirdrop. Whether
	// this is reachable under real live play (natural wave_end, real bots) is UNKNOWN - flagged
	// separately, not chased further here. Keep this probe to ONLY the safe bots_connected/
	// wave_start unblock; do not resurrect the forced wave_end loop without root-causing that bug
	// first.
}
