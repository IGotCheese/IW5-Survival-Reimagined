// bpg_survival_wavestallfix.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-31. v2.
//
// USER REPORT: "geometric shows 2 enemies remaining i dont see remaining enemies",
//              then "check all enemy types for issues instead of just what i tell you to check".
// v1 fixed predator only. This is the full audit of every enemy type. THREE types leak.
//
// ── HOW A WAVE ENDS ──────────────────────────────────────────────────────────────────────────
// lethalbeats\Survival\utility::bot_kill:918-919 is the ONLY thing that ends a wave:
//     level.bots_deaths++;
//     if (level.bots_total_count == level.bots_deaths) level notify("wave_end");
// No timeout, no other notifier. "N enemies remaining" IS bots_total_count - bots_deaths, so any
// bot counted in but never reaching bot_kill() hangs the wave for the rest of the map.
//
// botHandler::onBotKilled:251 refuses to count two classes, which must count themselves:
//     if (!self bot_is_killstreak() && !(self bot_is_jugger() && !self.isDropped)) self bot_kill(eAttacker);
// BOTS_ABILITIES_KS (utility.gsc:52) = chopper, pavelow, reaper, tank, airstrike, predator,
// counteruav, emp — plus the undropped juggernaut.
//
// ── FULL AUDIT OF EVERY ENEMY TYPE ───────────────────────────────────────────────────────────
//   dog, martyrdom, chemical, riotshield, generic  – not in KS list, onBotKilled counts them  OK
//   ims, sentry     – giveStreak() has no bot_kill, but neither type is in BOTS_ABILITIES_KS,
//                     so onBotKilled counts them normally. Looks wrong, is fine.             OK
//   emp             – killstreak, then bot_kill()                                            OK
//   counteruav      – bot_kill(), then the UAV                                               OK
//   airstrike       – bot_kill(), then the airstrike                                         OK
//   reaper          – _reaper.gsc:58 bot_kill() sits OUTSIDE the isplayer(attacker) branch    OK
//   chopper/pavelow – call bot_kill on the VEHICLE, not the bot. Deliberate: _chopper.gsc:83
//                     `lb.botPrice = self.botPrice` and _pavelow.gsc:81 `heli.botPrice =
//                     owner.botPrice` copy the price onto the vehicle precisely so this works.
//                     bots_deaths++ runs; only `if (isPlayer(self)) suicide()` is skipped, so
//                     the bot entity lingers hidden until the wave recycles it. Counts fine.  OK
//   predator        – givePredator() never calls bot_kill AT ALL                          ✗ LEAK A
//   tank            – bot_kill is INSIDE `if (isplayer(attacker))`                        ✗ LEAK B
//   jugger          – never counted when the drop aborts before isDropped is set          ✗ LEAK C
//
// ── LEAK A: givePredator() never counts ──────────────────────────────────────────────────────
// abilities\_killstreaks.gsc — the four handlers side by side:
//     giveEmp()        killstreak, then bot_kill()                    ✔
//     giveCounterUAV() bot_kill(), then the UAV                       ✔
//     giveAirstrike()  bot_kill(), then the airstrike                 ✔
//     givePredator()   level_wait_vehicle_limit(); killstreak; sound;   ← no bot_kill, ever
// Unconditional: every predator bot on every wave leaks one from the count.
// Not a hang — stock _remotemissile::tryusepredatormissile (the registered
// killStreakFuncs["predator_missile"], _remotemissile.gsc:31) threads _fire() and RETURNS.
// Fixed by replacing givePredator with the stock body plus a trailing bot_kill(), ordered like
// giveEmp: the killstreak calls setUsingRemote/initRideKillstreak ON the bot, so it must still be
// alive. giveAirstrike/giveCounterUAV can kill first only because their killstreaks take the bot
// as an owner reference, not a rider.
//
// ── LEAK B: the tank only counts when a PLAYER lands the kill ────────────────────────────────
// abilities\_tank.gsc:100-111:
//     if (vehicle.damagetaken < vehicle.maxhealth) return;
//     if (isplayer(attacker) && (!isdefined(vehicle.owner) || attacker != vehicle.owner))
//     {
//         vehicle.alreadydead = 1;
//         vehicle.owner bot_kill(attacker);      <-- INSIDE the isplayer branch
//         ...
//     }
//     vehicle notify("death");                   <-- outside: the tank dies either way
// So a tank finished off by a sentry gun, an IMS, a claymore, an airstrike, or any non-player
// attacker dies without ever being counted. That is not an exotic path — the damage switch above
// it has an explicit `case "ims_projectile_mp"`, and sentry guns are a staple of survival.
//
// FIX WITHOUT COPYING THE DAMAGE LOGIC. _tank::init does
//     replacefunc(maps\mp\killstreaks\_remotetank::tank_handledeath, ::_handleDamage);
// so this wraps the STOCK symbol instead: call the mod's _handleDamage directly (unaffected by
// what the stock slot points at, so there is no recursion), then compare level.bots_deaths
// before and after. If the tank is dead and the counter did not move, count it here. Not one line
// of the mod's 90-line weapon-damage switch is duplicated, so it cannot drift out of sync with
// the mod.
// ⚠️ Timing: mod init runs AFTER loose scripts, so a replaceFunc issued from init() would be
// overwritten by _tank::init. This re-asserts on a short delay and then a few more times, the
// same pattern bpg_survival_dialogkeys.gsc needed.
//
// ── LEAK C: the juggernaut that never gets dropped ──────────────────────────────────────────
// abilities\_juggernaut.gsc sets self.isDropped = false at :25 and true at :160 — frame 115 of
// the 335-frame loop inside _juggerDrop, which is guarded by `mi17 endon("death")` (:118).
// The two count paths are:
//     onBotKilled:251        counts a jugger only once isDropped is true
//     _juggernaut.gsc:242    counts an undropped jugger only from the mi17 DAMAGE loop
// A stock watchtimeout() firing notify("death") at 25s is not damage, so if the drop aborts
// before frame 115 NEITHER path runs: the jugger stays frozen, linked, invisible, alive and
// uncounted, and the wave can never end. This is the same mp_geometric strand as
// bpg_survival_juggerdropfix.gsc — that fix removes the abandoned helicopter but does not count
// the juggernaut that was still hanging off it, so on its own it cannot unstick the wave.
// Watchdog below: .isDropped is set ONLY by _juggernaut.gsc, so `isDefined(.isDropped) &&
// !.isDropped` is an exact discriminator for "juggernaut still riding". A real drop reaches
// frame 115 in roughly 15-25s from spawn (wait 2 + flight + wait 3 + 5.75s of loop), so the 150s
// threshold is ~6x margin and cannot catch a healthy drop.
//
// No double-counting anywhere: every path here either routes through bot_kill exactly once, or
// leaves the counting to a handler it then wakes up. bot_kill's own suicide re-enters
// onBotKilled, which skips all of these types by construction.
//
// ⚠️ NEVER copy to the live <MP-PORT> server — survival gametype only.

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( lethalbeats\Survival\abilities\_killstreaks::givePredator, ::bpg_givepredator_counted );

	level thread bpg_tank_hook();
	level thread bpg_jugger_watchdog();
	level thread bpg_queue_watchdog();
	level thread bpg_stall_reconciler();
}

// ── BACKSTOP ─────────────────────────────────────────────────────────────────────────────────
// Three named leaks were found and fixed above, and a wave STILL hung on mp_geometric with one
// enemy left. So there is at least one more path, and enumerating them one at a time has cost
// five rounds of the user's time. This does not care which type leaked: if the wave cannot
// finish, it finishes it.
//
// The trigger has to be narrow enough that it can never cut a live wave short. Two conditions
// together, both required:
//   1. level.bots_deaths has not moved for 120s. Not "no kills" - specifically the wave counter
//      being frozen, which is the actual failure.
//   2. At most 3 enemies outstanding. This is what separates a leak from players simply playing
//      cautiously: a genuine lull happens with a wave full of enemies left, while a leak always
//      strands the last handful. A group hiding from 12 enemies is untouched; a group staring at
//      a counter stuck on 1 is rescued.
// Wave-active is `bots_total_count > 0` - survival.gsc:292 sets it at wave start and :330 clears
// it after wave end, so this cannot fire during the between-wave pause.
//
// Ordering is deliberate: bots_deaths is raised to bots_total_count BEFORE the notify, so the
// mod's own state stays consistent. If a stranded bot dies for real afterwards, bot_kill pushes
// the counter one past total, the `==` test at utility.gsc:919 fails, and no second wave_end can
// fire. survival.gsc:292-294 resets both counters at the next wave start, so the overshoot is
// wiped either way.
//
// It logs every live axis bot before acting. That is the point of this block as much as the
// rescue is: the next stall names its own culprit in the console instead of costing another
// round of guessing. Grep [BPG-WAVESTALL].
bpg_stall_reconciler()
{
	level endon( "game_ended" );

	stallMs = 120000;
	if ( getDvarInt( "bpg_stall_ms" ) > 0 )
		stallMs = getDvarInt( "bpg_stall_ms" );

	maxOutstanding = 3;
	if ( getDvarInt( "bpg_stall_max" ) > 0 )
		maxOutstanding = getDvarInt( "bpg_stall_max" );

	lastDeaths = -1;
	lastChange = getTime();

	for ( ;; )
	{
		wait 5;

		if ( !isDefined( level.bots_total_count ) || !isDefined( level.bots_deaths ) )
			continue;

		now = getTime();

		if ( level.bots_deaths != lastDeaths )
		{
			lastDeaths = level.bots_deaths;
			lastChange = now;
			continue;
		}

		// wave not running - nothing to rescue
		if ( level.bots_total_count == 0 )
		{
			lastChange = now;
			continue;
		}

		outstanding = level.bots_total_count - level.bots_deaths;

		if ( outstanding <= 0 || outstanding > maxOutstanding )
		{
			lastChange = now;
			continue;
		}

		if ( now - lastChange < stallMs )
			continue;

		// ⚠️ THE DECIDING TEST, added 2026-07-31 after this fired on a HEALTHY wave.
		// The original guard was "at most 3 outstanding", on the theory that a leak always
		// strands the last handful. That is not a leak test at all - it fired on wave 1 with
		// bots_deaths 11/14 while its own dump showed three enemies alive and well:
		//     health=7 state=playing / health=56 state=playing / health=63 state=playing
		// Nobody had killed them for two minutes, which is ordinary play, and the wave got
		// skipped. Counting outstanding enemies says nothing about whether they EXIST.
		// So ask the question that actually matters: are there enough living, playing enemies
		// to account for the outstanding count? If yes, the wave is winnable and must be left
		// alone no matter how long the counter has sat still. Only when live enemies fall SHORT
		// of the outstanding count is something being counted that cannot be killed - which is
		// the leak, exactly.
		alive = bpg_live_enemy_count();

		if ( alive >= outstanding )
		{
			// Healthy but slow. Reset the clock so a genuinely stuck wave later still gets its
			// own full stallMs of observation rather than firing the instant one bot dies.
			lastChange = now;
			continue;
		}

		println( "[BPG-WAVESTALL] WAVE STUCK: " + outstanding + " outstanding but only " + alive + " live enemies, bots_deaths frozen at " + level.bots_deaths + "/" + level.bots_total_count + " for " + ( ( now - lastChange ) / 1000 ) + "s - forcing wave_end" );

		bpg_dump_live_bots();

		level.bots_deaths = level.bots_total_count;
		level notify( "wave_end" );

		lastChange = getTime();
		lastDeaths = level.bots_deaths;

		// Free the slots. Done AFTER the notify so a bot that does still have a working
		// bot_kill path cannot race the counter we just set.
		level thread bpg_sweep_leftovers();
	}
}

// Enemies that actually exist and can be shot. A leaked bot is always a corpse or a hidden
// non-entity - sessionstate "spectator" and health 0 - so requiring BOTH playing and health > 0
// separates "the wave is slow" from "the wave is counting something that isn't there".
bpg_live_enemy_count()
{
	n = 0;

	foreach ( bot in lethalbeats\Survival\utility::bots() )
	{
		if ( !isDefined( bot ) )
			continue;

		if ( !isDefined( bot.sessionstate ) || bot.sessionstate != "playing" )
			continue;

		if ( !isDefined( bot.health ) || bot.health <= 0 )
			continue;

		n++;
	}

	return n;
}

// The diagnostic that makes the next stall self-identifying.
bpg_dump_live_bots()
{
	foreach ( bot in lethalbeats\Survival\utility::bots() )
	{
		if ( !isDefined( bot ) )
			continue;

		println( "[BPG-WAVESTALL]   live axis bot: type=" + bpg_str( bot.botType ) + " isHuman=" + bpg_str( bot.isHuman ) + " isDropped=" + bpg_str( bot.isDropped ) + " health=" + bpg_str( bot.health ) + " state=" + bpg_str( bot.sessionstate ) + " origin=" + bpg_str( bot.origin ) );
	}
}

bpg_sweep_leftovers()
{
	wait 1;

	foreach ( bot in lethalbeats\Survival\utility::bots() )
	{
		if ( !isDefined( bot ) )
			continue;

		if ( !isPlayer( bot ) )
			continue;

		if ( isDefined( bot.sessionstate ) && bot.sessionstate != "playing" )
			continue;

		bot suicide();
	}
}

// println hard-errors on an undefined operand, and every field above can legitimately be unset
// on a half-initialised bot - which is exactly the bot this dump exists to catch.
bpg_str( v )
{
	if ( !isDefined( v ) )
		return "undef";

	return "" + v;
}

// ── LEAK A ───────────────────────────────────────────────────────────────────────────────────
// Stock body verbatim; the ONLY change is the trailing bot_kill().
bpg_givepredator_counted()
{
	lethalbeats\Survival\utility::level_wait_vehicle_limit();

	self [[ level.killStreakFuncs[ "predator_missile" ] ]]();

	lethalbeats\player::players_play_sound( "US_1mc_enemy_predator", "allies" );

	// THE FIX. Every sibling handler in _killstreaks.gsc counts its bot; this one never did.
	self lethalbeats\survival\utility::bot_kill();
}

// ── LEAK B ───────────────────────────────────────────────────────────────────────────────────
// Must land AFTER lethalbeats\Survival\abilities\_tank::init has claimed the stock symbol.
bpg_tank_hook()
{
	level endon( "game_ended" );

	for ( i = 0; i < 6; i++ )
	{
		wait 0.5;
		replaceFunc( maps\mp\killstreaks\_remotetank::tank_handledeath, ::bpg_tank_handledeath_counted );
	}
}

bpg_tank_handledeath_counted( inflictor, attacker, damage, iDFlags, meansOfDeath, weapon, point, dir, hitLoc, timeOffset, modelIndex, partName )
{
	before = 0;
	if ( isDefined( level.bots_deaths ) )
		before = level.bots_deaths;

	// The mod's own handler, called by name - so the stock slot pointing at us cannot recurse.
	self lethalbeats\Survival\abilities\_tank::_handleDamage( inflictor, attacker, damage, iDFlags, meansOfDeath, weapon, point, dir, hitLoc, timeOffset, modelIndex, partName );

	vehicle = isDefined( self.tank ) ? self.tank : self;

	if ( !isDefined( vehicle ) )
		return;

	// It counted itself - the ordinary player-kill path.
	if ( isDefined( level.bots_deaths ) && level.bots_deaths > before )
	{
		vehicle.bpg_counted = true;
		return;
	}

	if ( isDefined( vehicle.bpg_counted ) )
		return;

	// Still alive - nothing owed yet.
	if ( !isDefined( vehicle.damagetaken ) || !isDefined( vehicle.maxhealth ) || vehicle.damagetaken < vehicle.maxhealth )
		return;

	// Dead, and nobody counted it: the non-player-attacker path.
	vehicle.bpg_counted = true;

	if ( isDefined( vehicle.owner ) )
	{
		println( "[BPG-WAVESTALL] tank destroyed by a non-player attacker - counting it (weapon=" + ( isDefined( weapon ) ? weapon : "?" ) + ")" );
		vehicle.owner lethalbeats\survival\utility::bot_kill( attacker );
	}
}

// ── LEAK C ───────────────────────────────────────────────────────────────────────────────────
bpg_jugger_watchdog()
{
	level endon( "game_ended" );

	// 2026-07-31: was 150000. CONFIRMED WORKING in the live log on <SURV-PORT-4> -
	//     [BPG-WAVESTALL] juggernaut never dropped after 150s - counting it out (outstanding=1)
	// and the wave immediately advanced 20 -> 21 -> 22. But 150s of a hovering helicopter and a
	// frozen counter is indistinguishable from "still broken" to anyone playing.
	// A real drop sets isDropped at frame 115 of the drop loop, ~22s after spawn including
	// flight, and stock watchTimeOut() has already fired notify("death") at 25.0s by then. 35s
	// is past both, so this cannot catch a healthy drop, and it now acts before a player has
	// time to wonder whether the wave is broken.
	limit = 35000;
	if ( getDvarInt( "bpg_jugger_undropped_ms" ) > 0 )
		limit = getDvarInt( "bpg_jugger_undropped_ms" );

	for ( ;; )
	{
		wait 5;

		now = getTime();

		foreach ( bot in lethalbeats\Survival\utility::bots() )
		{
			if ( !isDefined( bot ) )
				continue;

			// ⚠️ A DEAD juggernaut still reads isDropped == false. .isDropped is only ever
			// written by _juggernaut.gsc (false at :25, true at :160) and nothing clears it on
			// death, so a juggernaut whose mi17 was SHOT DOWN - already counted by
			// _mi17_handleDamage:242 and suicided - sits there as a corpse still advertising
			// "never dropped". Counting that again would push bots_deaths past the real total
			// and end a later wave early. The live dump showed exactly this shape:
			//     type=jugger_regular isHuman=1 isDropped=0 health=0 state=spectator
			// So require the bot to actually be alive and playing before touching it.
			if ( !isDefined( bot.sessionstate ) || bot.sessionstate != "playing" )
			{
				if ( isDefined( bot.bpg_ridingAt ) )
					bot.bpg_ridingAt = undefined;

				continue;
			}

			// .isDropped exists only on a juggernaut (set false at _juggernaut.gsc:25).
			if ( !isDefined( bot.isDropped ) || bot.isDropped )
			{
				if ( isDefined( bot.bpg_ridingAt ) )
					bot.bpg_ridingAt = undefined;

				continue;
			}

			if ( !isDefined( bot.bpg_ridingAt ) )
			{
				bot.bpg_ridingAt = now;
				continue;
			}

			if ( now - bot.bpg_ridingAt < limit )
				continue;

			if ( isDefined( bot.bpg_countedOut ) )
				continue;

			bot.bpg_countedOut = true;

			println( "[BPG-WAVESTALL] juggernaut never dropped after " + ( ( now - bot.bpg_ridingAt ) / 1000 ) + "s - counting it out (outstanding=" + bpg_wave_outstanding() + ")" );

			bot lethalbeats\survival\utility::bot_kill();

			// THE OTHER HALF OF THE RACE: if the mi17 is shot down AFTER this, its damage
			// handler runs
			//     if ( isDefined( self.owner ) && !self.owner.isDropped ) self.owner bot_kill( attacker );
			// (_juggernaut.gsc:242) and would count this same juggernaut a second time. Rather
			// than add a private flag the mod cannot see, satisfy the mod's OWN guard - marking
			// it dropped is truthful here (it is off the helicopter and out of the wave) and
			// makes both that handler and onBotKilled:251 do the right thing without knowing
			// this script exists.
			bot.isDropped = true;

			// Take the abandoned helicopter out in the SAME pass. Previously this only counted
			// the juggernaut and left the mi17 to bpg_survival_juggerdropfix.gsc's independent
			// sweep, which added its own delay on top of this one - the two fixes were solving
			// halves of one event on separate clocks, and the visible result was a helicopter
			// hovering for about two minutes. _juggernaut.gsc:83 sets mi17.owner to this bot and
			// _doFlyBy sets .dropSite on the same entity, so the pair identifies its helicopter
			// exactly, with no reliance on level.littlebirds (which stock delists on the very
			// death notify that causes the strand - the reason the first version of the
			// helicopter fix could never see its targets).
			bot thread bpg_kill_orphan_mi17();
		}
	}
}

// Deletes the helicopter that was carrying this juggernaut, plus the rope and juggernaut models
// parked on mi17.models by _juggernaut.gsc:82. Safe by construction: we only get here once the
// juggernaut has been counted out, so the drop is definitively over and the helicopter is a prop.
bpg_kill_orphan_mi17()
{
	owner = self;

	foreach ( v in getEntArray( "script_vehicle", "classname" ) )
	{
		if ( !isDefined( v ) || !isDefined( v.dropSite ) || !isDefined( v.owner ) )
			continue;

		if ( v.owner != owner )
			continue;

		println( "[BPG-WAVESTALL] deleting the mi17 that was carrying it" );

		if ( isDefined( level.juggerDropInUse ) )
			level.juggerDropInUse = lethalbeats\array::array_remove( level.juggerDropInUse, v.dropSite );

		if ( isDefined( v.models ) )
		{
			foreach ( m in v.models )
			{
				if ( isDefined( m ) )
					m delete();
			}

			v.models = undefined;
		}

		// _mi17_setup threads _chopper::lbSurvivalDeathCrash on this helicopter, and that thread
		// keeps calling playsound/setyawspeed on it. Deleting underneath it produced 12 live
		// "attempt to call a method on 'dead entity'" errors. It guards with endon("gone") and
		// endon("leaving"), so saying "gone" first retires it cleanly.
		v notify( "gone" );

		v delete();
	}
}

// ── The vehicle queue can strand a bot before it ever counts ─────────────────────────────────
// giveAirstrike and givePredator both call level_wait_vehicle_limit() BEFORE counting, and that
// is `waittill("vehicle_release")` with no timeout. Release comes only from level_vehicle_monitor
// (utility.gsc:1735-1745), which skips every tick level_airspace_is_crowded() is true:
//     littlebirds.size >= 4 || currentActiveVehicleCount() >= 4 || fauxvehiclecount >= 4
//     || isDefined(civilianjetflyby)
// Those count live entities, so ONE leaked vehicle jams the queue for the rest of the map — and a
// stranded juggernaut mi17 is exactly such a leak.
//
// level_wait_vehicle_limit is NOT replaced and gets no timeout: it has seven callers (_chopper:28,
// _juggernaut:27, _killstreaks:29 and :38, _pavelow:16, _reaper:11, _tank:9) and five of them
// spawn real vehicles, where releasing early would re-open the vehicle-limit error storm. Only
// airstrike and predator are force-released here — neither spawns a vehicle (doAirstrike planes
// and a magicbullet), so they cannot crowd the airspace further. They are woken rather than
// counted from here, so their own handler still does the counting exactly once.
//
// This is also why the "remaining" enemies are invisible: level_wait_vehicle_limit:1893-1894 does
// self hide() and setOrigin(level.airDropCrateCollision.origin), parking the bot inside the
// airdrop-crate brush.
bpg_queue_watchdog()
{
	level endon( "game_ended" );

	limit = 120000;
	if ( getDvarInt( "bpg_wavestall_ms" ) > 0 )
		limit = getDvarInt( "bpg_wavestall_ms" );

	for ( ;; )
	{
		wait 5;

		if ( !isDefined( level.vehicleWaiting ) || level.vehicleWaiting.size == 0 )
			continue;

		now = getTime();

		foreach ( bot in level.vehicleWaiting )
		{
			if ( !isDefined( bot ) || !isDefined( bot.botType ) )
				continue;

			if ( bot.botType != "airstrike" && bot.botType != "predator" )
				continue;

			if ( !isDefined( bot.bpg_queuedAt ) )
			{
				bot.bpg_queuedAt = now;
				continue;
			}

			if ( now - bot.bpg_queuedAt < limit )
				continue;

			if ( isDefined( bot.bpg_forceReleased ) )
				continue;

			bot.bpg_forceReleased = true;

			println( "[BPG-WAVESTALL] releasing a " + bot.botType + " bot queued " + ( ( now - bot.bpg_queuedAt ) / 1000 ) + "s - airspace never cleared (outstanding=" + bpg_wave_outstanding() + ")" );

			bot notify( "vehicle_release" );

			level.vehicleWaiting = bpg_queue_without( bot );
		}
	}
}

bpg_wave_outstanding()
{
	if ( !isDefined( level.bots_total_count ) || !isDefined( level.bots_deaths ) )
		return 0;

	return level.bots_total_count - level.bots_deaths;
}

// Rebuild rather than array_remove_index: level_vehicle_monitor always pops index 0, so removing
// by position from here would race its index arithmetic.
bpg_queue_without( bot )
{
	out = [];

	foreach ( q in level.vehicleWaiting )
	{
		if ( isDefined( q ) && q == bot )
			continue;

		out[ out.size ] = q;
	}

	return out;
}
