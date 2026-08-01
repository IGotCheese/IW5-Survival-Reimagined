// bpg_dogfix_probe.gsc — reproduces the exact stuck-takedown failure scenario headlessly.
// 2026-07-19 REWRITE: natural enemy AI never spawns in a headless side-test (survival.gsc's
// waitPlayers() blocks forever on a "bots_connected" notify nothing fires) — proven after two
// separate runs waiting 300s/480s found zero bots even with wave_start forced. So this probe now
// manufactures its OWN dog via a second test client + a direct giveAbility() call, exactly
// mirroring what botHandler.gsc's DOG case does, instead of waiting on the wave/AI system.
// Verifies TWO things: (1) the knockdown-interrupted freeze releases fast (the original bug), and
// (2) the freed player's WEAPON is actually restored — player_hide() (run on every knockdown, not
// just interrupted ones) does player_take_all_weapons(true), and only player_show() gives it back;
// this is the root cause behind "dog attacks you and your gun disappears".
// INERT unless bpg_dogfix_probe=1 (side-test cfg only — never set on live).

#include lethalbeats\survival\utility;

init()
{
	if ( getDvarInt( "bpg_dogfix_probe" ) != 1 )
		return;

	level thread bpg_dogfix_probe_run();
}

bpg_dogfix_probe_run()
{
	println( "[DOGPROBE] armed - adding victim + dog test clients in 15s" );
	wait 15;

	victim = addtestclient();
	if ( !isDefined( victim ) )
	{
		println( "[DOGPROBE] FAIL victim addtestclient undefined" );
		return;
	}
	waited = 0;
	while ( ( !isDefined( victim.sessionstate ) || victim.sessionstate != "playing" || !isAlive( victim ) ) && waited < 60 )
	{
		wait 1;
		waited++;
	}
	println( "[DOGPROBE] victim " + victim.name + " ready after " + waited + "s" );

	// onPlayerSpawn() initializes self.dogKnockdown = false on its own thread after
	// "spawned_player" - calling onDogPlayerDamage before that thread runs hits
	// `if (player.dogKnockdown)` on an undefined value = "cannot cast undefined to bool"
	// runtime error. Waiting for it to appear naturally (up to 10s) still left it
	// undefined for a test client, so set it directly - a live human player always has
	// this initialized long before ever meeting a dog, so this just removes test-harness
	// timing noise unrelated to the actual fix being verified.
	if ( !isDefined( victim.dogKnockdown ) )
		victim.dogKnockdown = false;
	println( "[DOGPROBE] victim.dogKnockdown=" + victim.dogKnockdown );

	dogClient = addtestclient();
	if ( !isDefined( dogClient ) )
	{
		println( "[DOGPROBE] FAIL dogClient addtestclient undefined" );
		return;
	}
	waited = 0;
	while ( ( !isDefined( dogClient.sessionstate ) || dogClient.sessionstate != "playing" || !isAlive( dogClient ) ) && waited < 60 )
	{
		wait 1;
		waited++;
	}
	println( "[DOGPROBE] dogClient " + dogClient.name + " ready after " + waited + "s, forcing DOG ability directly (bypassing wave/AI)" );

	dogClient.pers[ "team" ] = "axis";
	dogClient lethalbeats\survival\abilities\_dog::giveAbility();
	dogClient.isHuman = false;
	wait 1;

	if ( !isDefined( dogClient.dog ) )
	{
		println( "[DOGPROBE] FAIL giveAbility() didn't set dogClient.dog - can't proceed" );
		return;
	}
	println( "[DOGPROBE] dog ability confirmed (dogClient.dog defined)" );

	preWeapon = victim getCurrentWeapon();
	println( "[DOGPROBE] victim pre-knockdown weapon=" + preWeapon + " hasWeapon=" + victim hasWeapon( preWeapon ) );

	dog = dogClient;
	// force the SAME knockdown path bpg_dog_brain() uses (attackAmount=2, stock tackle)
	dog.dog.victim = undefined;
	dog.dog.attackAmount = 2;
	dog thread lethalbeats\survival\abilities\_dog::onDogPlayerDamage( victim );

	waited = 0;
	while ( ( !isDefined( victim.dogKnockdown ) || !victim.dogKnockdown ) && waited < 10 )
	{
		wait 0.5;
		waited += 0.5;
	}
	if ( !isDefined( victim.dogKnockdown ) || !victim.dogKnockdown )
	{
		println( "[DOGPROBE] FAIL knockdown never engaged (victim.dogKnockdown never set)" );
		return;
	}
	println( "[DOGPROBE] knockdown ENGAGED after " + waited + "s. hideData=" + isDefined( victim.hideData ) + " hasWeapon(pre)=" + victim hasWeapon( preWeapon ) );

	println( "[DOGPROBE] killing the dog MID-PIN now." );
	killedAt = getTime();
	dog suicide();

	// poll fast (0.1s) to measure release latency precisely
	freedAt = undefined;
	t = 0;
	while ( t < 15 )
	{
		if ( !isDefined( victim.dogKnockdown ) || !victim.dogKnockdown )
		{
			freedAt = getTime();
			break;
		}
		wait 0.1;
		t += 0.1;
	}

	if ( !isDefined( freedAt ) )
	{
		println( "[DOGPROBE] RESULT: STILL STUCK 15s after the dog died. FIX DID NOT WORK." );
		return;
	}

	latencyMs = freedAt - killedAt;
	wait 0.2; // let player_show()'s player_give_weapon settle a frame
	postHasWeapon = victim hasWeapon( preWeapon );
	postWeapon = victim getCurrentWeapon();
	println( "[DOGPROBE] RESULT: freed " + latencyMs + "ms after the dog died. linked=" + victim isLinked() + " postWeapon=" + postWeapon + " hasWeapon(pre)=" + postHasWeapon );

	if ( latencyMs >= 2000 )
		println( "[DOGPROBE] SLOW - released, but not instant (" + latencyMs + "ms) - check for a race." );
	else
		println( "[DOGPROBE] PASS(freeze) - instant release, freeze fix confirmed working." );

	if ( !postHasWeapon )
		println( "[DOGPROBE] FAIL(weapon) - player freed but weapon NOT restored. GUN DISAPPEARED BUG STILL PRESENT." );
	else
		println( "[DOGPROBE] PASS(weapon) - weapon restored after release. GUN DISAPPEAR BUG FIXED." );
}
