// bpg_survival_waveendsweep.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-31.
//
// USER REPORT: "sometimes the round is over but you have leftover enemies and helis on the break
// between rounds".
//
// ── WHY IT HAPPENS ───────────────────────────────────────────────────────────────────────────
// The wave counter and the actual entities are two different things. A wave ends the instant
// bots_deaths == bots_total_count (utility.gsc:919) - that says nothing about whether anything is
// still standing. And the mod's own onWaveEnd (survival.gsc:312-341) cleans up exactly ONE kind
// of leftover:
//     foreach ( uav in level.uavmodels["axis"] )
//         if ( uav.uavtype == "counter" ) { playFx( .. ); uav notify( "death" ); }
// Counter-UAVs, and nothing else. No choppers, no pavelows, no MI-17s, no tanks, no reaper
// drones, and no bots.
//
// Several types are counted WITHOUT dying, which is what leaves live enemies on the field:
//   * chopper / pavelow  – call bot_kill on the VEHICLE (deliberately: _chopper.gsc:83 and
//     _pavelow.gsc:81 copy botPrice onto it). Since `isPlayer(self)` is false there, the
//     `self suicide()` inside bot_kill never runs, so the OWNING BOT is counted but stays alive.
//   * counteruav / airstrike – call bot_kill at cast time, before the killstreak resolves.
//   * anything the wave-stall backstop counts out – by definition never died.
// So a wave can legitimately reach its target with bots and vehicles still in the world, and
// nothing in the mod removes them. They then sit through the ~38s intermission
// (onWaveEnd: wait 8 -> waitIntermission(30) -> wave_start) in plain view.
//
// ── THE FIX ──────────────────────────────────────────────────────────────────────────────────
// Sweep on "wave_end" using the SAME per-type destruction the admin !clear command already uses
// (bpg_survival_clearwave.gsc), which is proven and was side-tested against the dog, vehicle,
// counter-UAV and reaper paths. Nothing new is invented here:
//   * bots            -> suicide()
//   * script_vehicle  -> notify "damage" 9999999   (littlebird / pavelow / tank / MI-17)
//   * script_model    -> same, filtered to uavtype=="counter" && team=="axis"
//   * level.remote_mortar -> same, only when its owner is a bot
//
// ⚠️ An UNDROPPED juggernaut is skipped, for the reason clearwave documents: _juggerDrop is still
// driving that entity through a 335-frame sequence with no endon("death") guard, so killing it
// directly throws and strands its MI-17 forever. Destroying the MI-17 (matched by the vehicle
// loop) is the correct path - _mi17_handleDamage then calls bot_kill on the owner itself.
//
// ⚠️ The attacker argument must be a real entity. _pavelow.gsc's damage loop opens with
// `if (isdefined(attacker.class) && attacker.class == "worldspawn")` - reading .class on an
// undefined attacker throws. So a survivor is used, and if there are none the vehicle sweep is
// skipped entirely (with nobody on the server there is nothing to look at anyway).
//
// ⚠️ DOGS ARE DELIBERATELY SKIPPED - standing instruction is not to touch dog behaviour without
// explicit approval. A leftover dog will therefore still persist into the break; the count is
// logged so the gap is visible rather than silent. Say the word and the exclusion comes out.
//
// Counter safety: onWaveEnd sets bots_total_count = 0 (survival.gsc:330) before this runs, while
// bots_deaths keeps the finished wave's value, so the `total == deaths` test in bot_kill cannot
// re-fire. endon("wave_start") guarantees the sweep is finished long before the next wave, so a
// suicide here can never be charged against it.
//
// ⚠️ NEVER copy to the live <MP-PORT> server - survival gametype only.

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	level thread bpg_waveend_listener();
}

bpg_waveend_listener()
{
	level endon( "game_ended" );

	for ( ;; )
	{
		level waittill( "wave_end" );
		level thread bpg_waveend_sweep();
	}
}

bpg_waveend_sweep()
{
	level endon( "wave_start" );
	level endon( "game_ended" );

	// Let the mod's own onWaveEnd cleanup and any in-flight death handling settle first.
	wait 2;

	attacker = undefined;
	survs = lethalbeats\Survival\utility::survivors();

	if ( isDefined( survs ) && survs.size > 0 )
		attacker = survs[ 0 ];

	bots = 0;
	dogs = 0;
	vehicles = 0;
	models = 0;

	foreach ( bot in lethalbeats\Survival\utility::bots() )
	{
		if ( !isDefined( bot ) || !isAlive( bot ) )
			continue;

		// See header: killing an undropped juggernaut directly strands its MI-17.
		if ( isDefined( bot.isjuggernaut ) && bot.isjuggernaut && isDefined( bot.isDropped ) && !bot.isDropped )
			continue;

		// Dogs: excluded by standing instruction, counted so the gap is visible.
		if ( isDefined( bot.botType ) && isSubStr( bot.botType, "dog" ) )
		{
			dogs++;
			continue;
		}

		bot suicide();
		bots++;
	}

	if ( isDefined( attacker ) )
	{
		foreach ( v in getEntArray( "script_vehicle", "classname" ) )
		{
			if ( !isDefined( v ) )
				continue;

			v notify( "damage", 9999999, attacker, ( 0, 0, 0 ), v.origin, "MOD_PROJECTILE_SPLASH", undefined, undefined, undefined, undefined, "artillery_mp" );
			vehicles++;
		}

		foreach ( m in getEntArray( "script_model", "classname" ) )
		{
			if ( !isDefined( m ) || !isDefined( m.uavtype ) || m.uavtype != "counter" )
				continue;

			if ( !isDefined( m.team ) || m.team != "axis" )
				continue;

			m notify( "damage", 9999999, attacker, ( 0, 0, 0 ), m.origin, "MOD_PROJECTILE_SPLASH", undefined, undefined, undefined, undefined, "artillery_mp" );
			models++;
		}

		if ( isDefined( level.remote_mortar ) && isDefined( level.remote_mortar.owner )
			&& isDefined( level.remote_mortar.owner.isHuman ) && !level.remote_mortar.owner.isHuman )
		{
			level.remote_mortar notify( "damage", 9999999, attacker, ( 0, 0, 0 ), level.remote_mortar.origin, "MOD_PROJECTILE_SPLASH", undefined, undefined, undefined, undefined, "artillery_mp" );
			models++;
		}
	}

	// Logs UNCONDITIONALLY, including the all-zero case. The first version only printed when it
	// swept something, which made a clean wave and a listener that never fired look identical -
	// exactly the "silence is not success" trap. One line per wave end is cheap; being able to
	// tell "nothing to clean" from "not running" is not.
	println( "[BPG-WAVEEND] wave " + ( isDefined( level.wave_num ) ? level.wave_num : "?" ) + " swept: bots=" + bots + " vehicles=" + vehicles + " models=" + models + " dogs-skipped=" + dogs );
}
