// bpg_survival_clearwave.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-22.
// Adds the admin command  !clear  (power 70) to the lethalbeats ServerControl
// framework. It clears the CURRENT wave (kills every enemy) and lets the mod's
// own wave-counter finish the wave cleanly.
//
// WHY IT IS BUILT THIS WAY (verified against LB_Survival.iwd, md5-matched dump):
//   The wave counter lives in lethalbeats\survival\utility::bot_kill — it does
//   level.bots_deaths++ and fires  level notify("wave_end")  when
//   level.bots_deaths == level.bots_total_count. Who CALLS bot_kill depends on
//   the bot type:
//     * normal / martyrdom / chemical / DOG / already-DROPPED juggernaut:
//         onBotKilled() calls bot_kill for us  ->  a plain  suicide()  counts it.
//         (dog is NOT in BOTS_ABILITIES_KS, and suicide also triggers the mod's
//          onDogDeath cleanup which releases any survivor caught in a knockdown.)
//     * killstreak / vehicle bots  (chopper, pavelow, reaper, tank, airstrike,
//       predator, counteruav, emp)  AND the juggernaut still being delivered by
//       its MI-17:  onBotKilled SKIPS bot_kill on the owner. Their bot_kill is
//       fired by the VEHICLE's own damage handler, so we must destroy the
//       script_vehicle (notify "damage" 9999999) — killing the owner alone would
//       leave level.bots_deaths short and the wave would never end.
//   This is exactly the mod author's own dev/test.gsc::clearWave() (the full
//   version they commented out in favour of the dog-skipping clearWave2). We use
//   the full version + a fail-safe iteration cap so it can never spin forever.
//
// 2026-07-23 ADDED — counter-UAV / reaper (NOT classname script_vehicle):
//   Verified against maps\mp\killstreaks\_uav.gsc, _remotemortar.gsc and the
//   mod's lethalbeats\Survival\abilities\_killstreaks.gsc / _reaper.gsc:
//     * counteruav bot: giveCounterUAV() calls bot_kill() IMMEDIATELY (the wave
//       counter is already satisfied the instant the bot uses the ability) and
//       then spawns a classname "script_model" radar-jam prop (uavtype=="counter",
//       team "axis", owner ALWAYS undefined) that lives up to ~2.7h untouched.
//       It was never destroyed by !clear because it isn't classname
//       script_vehicle, so the radar jam (level.radarStrength==-3) and the
//       leftover model outlived every previous wave clear.
//     * reaper bot: giveAbility() does NOT suicide/bot_kill immediately (unlike
//       pavelow/chopper/tank) — the bot enters a remote-ride state and bot_kill
//       only fires from the remote_mortar drone's OWN damage handler
//       (abilities\_reaper.gsc::_handleDamage) once destroyed. That drone is
//       also classname "script_model" (uavtype=="remote_mortar"), stored in the
//       single global level.remote_mortar slot (shared by bots AND any human
//       who might use it — see _remotemortar.gsc::tryuseremotemortar's
//       "airspace too crowded" singleton check). Since it was never matched by
//       the script_vehicle loop, a reaper wave could hang forever on !clear.
//   Filtered tightly so this NEVER touches:
//     - the 2 permanent radar-visualization UAV props the mod launches at map
//       init (owner undefined, uavtype=="standard" — excluded, we only match
//       "counter"/"remote_mortar").
//     - a REAL SURVIVOR'S own counter-UAV, if that path is ever exposed (a
//       player-triggered counter_uav uses the player's own team via the stock
//       useuav() flow, never team "axis" — excluded by the team=="axis" check;
//       giveCounterUAV() ALWAYS launches with team "axis" hardcoded).
//     - a REAL SURVIVOR'S own reaper ride (level.remote_mortar.owner.isHuman
//       check — bots always have isHuman==false, set in botHandler.gsc).
//   Destroying these feeds the same synthetic "damage" notify already used for
//   script_vehicle above, matching the exact waittill("damage", ...) signature
//   both damage handlers expect (verified against source). Counter-UAV's damage
//   handler does NOT call bot_kill on destroy (bot_kill already fired at cast
//   time) so this cannot double-count; reaper's DOES call bot_kill on destroy,
//   which is required for a reaper wave to ever reach wave_end.
//
// 2026-07-23 FIXED — juggernaut MI-17 heli left "stuck" by !clear:
//   Verified against lethalbeats\Survival\abilities\_juggernaut.gsc. Before the
//   MI-17 even exists, giveAbility() parks the jugger bot INSIDE
//   level_wait_vehicle_limit() (hidden, blocked on a "vehicle_release" wait) —
//   so it can sit in bots() alive for an arbitrary time with no vehicle to its
//   name yet. Once released, the REAL bot entity (self) stays hidden/frozen
//   (self.isDropped == false) for the whole fly-by/rope-drop; the visible thing
//   on the rope is a separate decorative script_model (sp_jugger), not self.
//   _mi17_handleDamage() is the ONLY thing meant to call bot_kill() for this bot
//   while !self.owner.isDropped — and bot_kill() itself is what calls
//   suicide() on the owner, exactly like chopper/pavelow/tank already do.
//   We were unconditionally suiciding EVERY bot in the loop below, including a
//   still-undelivered juggernaut. That suicide is a no-op for the wave counter
//   (onBotKilled already skips bot_kill here, as documented above) but it also
//   kills the real entity that abilities\_juggernaut.gsc::_juggerDrop() is still
//   driving via `self show(); self setOrigin(...); self player_enable_weapons();
//   self.isDropped = true; self freezeControls(false);` around frame 115 of its
//   335-frame sequence (that thread has no `self endon("death")` guard). Calling
//   those on an already-dead entity throws a runtime error and aborts the thread
//   before it ever reaches `case 230: mi17 thread heli_leave()` — and if !clear
//   fires before the MI-17 even spawns (bot still parked on vehicle_release),
//   the MI-17 that eventually appears has an owner already dead with isDropped
//   permanently stuck false, and nothing is left to destroy it once clearwave's
//   own 20s window has passed: it flies its whole course untouched, forever —
//   the reported "stuck helicopter".
//   FIX: skip direct suicide() for a juggernaut still being delivered
//   (isjuggernaut && !isDropped) and let the vehicle loop below destroy its
//   MI-17 instead (classname script_vehicle, already unconditionally matched) —
//   exactly the path _mi17_handleDamage() expects, which calls bot_kill() (and
//   therefore suicide()) on the owner itself, correctly sequenced, once the
//   vehicle actually exists. An ALREADY-DROPPED juggernaut is a normal ground
//   bot again (onBotKilled calls bot_kill for it directly) so it is still
//   suicided normally, unchanged from before.
//
// Side effects (inherited from the mod's real death path, NOT bugs):
//   - explosive bots (martyrdom/chemical) detonate on death and can hurt nearby
//     survivors; choppers/pavelows crash. This is normal "they died" behaviour.
//   - the caller (self) is passed as the attacker for the vehicle/model damage,
//     so the admin who runs !clear is credited for destroyed vehicles (and, for
//     counter-UAV, its small score bonus).
//
// ⚠️ SIDE-TEST before it reaches the live rotation (loose GSC compiles on the next
//    map load). Test the dog path, a vehicle wave, a counter-UAV wave, and a
//    reaper wave specifically.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

#include common_scripts\utility;
#include maps\mp\_utility;
#include lethalbeats\survival\utility;

#define CLEAR_POWER   70
#define CLEAR_MAX_PASSES 40   // fail-safe: 40 * 0.5s = 20s hard ceiling

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	// dev/test.gsc ALSO registers "clear" (::clearWave2, power 0) on frame 0, and
	// its init order vs ours is not guaranteed. Register now AND re-assert on a
	// short delay so OUR handler at power 70 deterministically wins the last write.
	// ("clear" was removed from bpg_survival_servercontrolfix.gsc's power-100
	//  lockdown list so it no longer gets force-bumped to 100.)
	registerClear();
	level thread reassertClear();
}

registerClear()
{
	// cmd, functionPointer, power, min_arguments
	lethalbeats\servercontrol\commands::setCommand( "clear", ::bpg_clear_cmd, CLEAR_POWER, 0 );
	lethalbeats\servercontrol\commands::setCommandAlias( "clear", "cw" );
}

reassertClear()
{
	level endon( "game_ended" );

	for ( pass = 0; pass < 3; pass++ )
	{
		wait 0.5 + pass;
		registerClear();
	}
}

// Handler. Takes up to 3 optional args so trailing chat words never trip the
// engine's OP_checkclearparams overflow (see bpg_survival_morecmds.gsc note).
bpg_clear_cmd( a, b, c )
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	// Nothing to clear outside an active wave / when no enemies exist.
	if ( !isDefined( level.wave_num ) || !level.wave_num )
		return;
	if ( !bots().size && !getEntArray( "script_vehicle", "classname" ).size && !bpg_has_enemy_uav_or_reaper() )
		return;

	self thread bpg_clear_worker();
}

// True if a bot-owned counter-UAV or reaper drone is currently up. See the
// 2026-07-23 header note for why these two are script_model, not script_vehicle,
// and why the filters below are what they are.
bpg_has_enemy_uav_or_reaper()
{
	if ( isDefined( level.remote_mortar ) && isDefined( level.remote_mortar.owner )
		&& isDefined( level.remote_mortar.owner.isHuman ) && !level.remote_mortar.owner.isHuman )
		return true;

	foreach ( uavEnt in getEntArray( "script_model", "classname" ) )
	{
		if ( isDefined( uavEnt ) && isDefined( uavEnt.uavtype ) && uavEnt.uavtype == "counter" && uavEnt.team == "axis" )
			return true;
	}

	return false;
}

// Kills every enemy of the current wave, looping to catch stragglers, and stops
// the instant the mod's counter fires "wave_end".
bpg_clear_worker()
{
	level endon( "wave_end" );
	level endon( "game_ended" );
	self  endon( "disconnect" );

	for ( pass = 0; pass < CLEAR_MAX_PASSES; pass++ )
	{
		// Player-entity bots: normal, martyrdom, chemical, dog, dropped jugger.
		// suicide() -> onBotKilled -> bot_kill (counts) for all of these. A
		// juggernaut still being delivered is EXCLUDED here (see 2026-07-23 header
		// note) - its own MI-17 destruction below is what must kill/count it.
		foreach ( bot in bots() )
		{
			if ( !isDefined( bot ) || !isAlive( bot ) )
				continue;
			if ( isDefined( bot.isjuggernaut ) && bot.isjuggernaut && isDefined( bot.isDropped ) && !bot.isDropped )
				continue;
			bot suicide();
		}

		// Vehicle-backed enemies (littlebird/pavelow/tank + MI-17 jugger
		// delivery). Their own damage handler runs bot_kill once destroyed.
		foreach ( vehicle in getEntArray( "script_vehicle", "classname" ) )
			if ( isDefined( vehicle ) )
				vehicle notify( "damage", 9999999, self, ( 0, 0, 0 ), vehicle.origin, "MOD_PROJECTILE_SPLASH", undefined, undefined, undefined, undefined, "artillery_mp" );

		// Counter-UAV / reaper: classname script_model, not script_vehicle (see
		// 2026-07-23 header note). Filtered to bot-owned instances only so we
		// never touch the permanent radar props or a real survivor's own item.
		foreach ( uavEnt in getEntArray( "script_model", "classname" ) )
			if ( isDefined( uavEnt ) && isDefined( uavEnt.uavtype ) && uavEnt.uavtype == "counter" && uavEnt.team == "axis" )
				uavEnt notify( "damage", 9999999, self, ( 0, 0, 0 ), uavEnt.origin, "MOD_PROJECTILE_SPLASH", undefined, undefined, undefined, undefined, "artillery_mp" );

		if ( isDefined( level.remote_mortar ) && isDefined( level.remote_mortar.owner )
			&& isDefined( level.remote_mortar.owner.isHuman ) && !level.remote_mortar.owner.isHuman )
			level.remote_mortar notify( "damage", 9999999, self, ( 0, 0, 0 ), level.remote_mortar.origin, "MOD_PROJECTILE_SPLASH", undefined, undefined, undefined, undefined, "artillery_mp" );

		wait 0.5;
	}
}
