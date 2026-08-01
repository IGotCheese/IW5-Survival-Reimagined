// bpg_survival_stuckbots.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-22.
// User: "add a feature to kill all stuck bots when bots get stuck for all maps."
// Researched existing solutions first, per request, before writing anything:
//  - Community script Plutonium-IW5-Scripts/small_scripts/kill_stuck_bots.gsc
//    (git.alterware.dev/Future/Plutonium-IW5-Scripts) kills any bot that goes 30s
//    with no kill AND no death. Wrong signal for THIS mod: several survival enemy
//    types legitimately go >30s without a kill/death while doing nothing wrong
//    (a reaper/sentry waiting for line of sight, a bot parked at the vehicle-
//    limit wait, one just standing near a shop) — that heuristic would kill
//    perfectly healthy bots, not just stuck ones.
//  - Bot Warfare's OWN maps/mp/bots/_bot_internal.gsc::movetowards() already
//    detects real movement-stuck (near-zero position delta for 3s), tries a
//    knife+strafe recovery itself, and fires `self BotNotifyBotEvent("stuck")`
//    when that's happening. That's the precise, purpose-built signal, so this
//    file hooks it instead of reinventing detection - it only fires after the
//    bot's own movement code already tried and failed to get unstuck.
// Escalation: 3 stuck events within a 20s rolling window = the built-in recovery
// isn't working either -> genuinely wedged.
// ⚠️ HARD RULE (user, 2026-07-22): never touch dogs. Reads self.botType directly
// (bot_is_dog() is just `self.botType == "dog"`, confirmed via source) instead of
// calling the function, to avoid any namespace/qualification risk near dogs.
// ⚠️ 2026-07-22 CORRECTED: first deploy used `self waittill("stuck")`, which
// silently never fired - BotNotifyBotEvent(msg) always notifies "bot_event"
// (msg passed as the first param), never `msg` itself. Confirmed live: bots
// piled up all over the map with zero auto-kills. Fixed to wait on the real
// event name and filter by the msg param instead.
// ⚠️ 2026-07-22 CHANGED per user feedback: originally killed the wedged bot via
// bot_kill(), but that registered the kill (bookkeeping fired) while the actual
// bot model stayed frozen on the map — the same class of "kill fired but no
// visible cleanup" issue this project has hit before with bot corpses. User
// asked for a rescue instead, "similar to an !stuck sort of command" (the
// player-facing bpg_survival_morecmds.gsc bpg_stuck_cmd). Switched to that: pick
// a random real waypoint a real distance away and teleport the bot there
// instead of killing it — same proven waypoint-selection logic as !stuck, no
// death/cleanup pipeline involved at all, so there's nothing to leave behind.
// Also resets the bot's own next-waypoint cache (self.bot.last_next_wp /
// last_second_next_wp = -1, the exact reset Bot Warfare's own strafe-recovery
// does after a stuck event) so it doesn't immediately try to re-path into the
// same failure from the new spot.
// ⚠️ Not yet behaviorally confirmed live — same headless-testing wall as every
// other survival gameplay-sequence fix this project has hit (bots don't path
// meaningfully with zero real players connected). Ask for a live report on
// whether the piles now clear via teleport instead of a lingering corpse.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

#include lethalbeats\survival\utility;

#define STUCK_WINDOW_MS 20000
#define STUCK_STRIKES 3

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	level thread bpg_stuckbot_watch();
}

bpg_stuckbot_watch()
{
	level endon( "game_ended" );

	for ( ;; )
	{
		level waittill( "connected", bot );
		if ( isSubStr( bot getGuid() + "", "bot" ) )
			bot thread bpg_stuckbot_monitor();
	}
}

bpg_stuckbot_monitor()
{
	self endon( "disconnect" );
	level endon( "game_ended" );

	strikes = 0;
	windowStart = getTime();

	for ( ;; )
	{
		// BotNotifyBotEvent(msg) always notifies "bot_event" with msg as the
		// first param, never `msg` itself - confirmed via source
		// (maps/mp/bots/_bot_utility.gsc::BotNotifyBotEvent_).
		self waittill( "bot_event", msg );
		if ( !isDefined( msg ) || msg != "stuck" )
			continue;

		if ( !isDefined( self ) || !isDefined( self.origin ) )
			return;
		if ( !isAlive( self ) )
			continue;
		if ( isDefined( self.botType ) && self.botType == "dog" )
			continue; // HARD RULE: never touch dogs, no matter how "stuck" they report

		now = getTime();
		if ( now - windowStart > STUCK_WINDOW_MS )
		{
			strikes = 0;
			windowStart = now;
		}
		strikes++;

		if ( strikes >= STUCK_STRIKES )
		{
			bpg_free_stuck_bot();
			strikes = 0;
			windowStart = getTime();
		}
	}
}

// Same waypoint-selection logic as bpg_survival_morecmds.gsc's !stuck: a random
// real waypoint a real distance away (not just the nearest one, which can be
// the exact spot the bot is wedged against), falling back to the first valid
// waypoint if the map is tiny.
bpg_free_stuck_bot()
{
	if ( !isDefined( level.waypoints ) || level.waypoints.size <= 0 )
		return;

	dest = undefined;
	for ( tries = 0; tries < 25 && !isDefined( dest ); tries++ )
	{
		wp = level.waypoints[ randomInt( level.waypoints.size ) ];
		if ( !isDefined( wp ) || !isDefined( wp.origin ) )
			continue;
		if ( distance( self.origin, wp.origin ) < 120 )
			continue;
		dest = wp;
	}
	if ( !isDefined( dest ) )
	{
		for ( i = 0; i < level.waypoints.size; i++ )
		{
			if ( isDefined( level.waypoints[ i ] ) && isDefined( level.waypoints[ i ].origin ) )
			{
				dest = level.waypoints[ i ];
				break;
			}
		}
	}
	if ( !isDefined( dest ) )
		return;

	println( "bpg_stuckbot: freeing genuinely-wedged bot " + self.name + " (" + STUCK_STRIKES + " stuck events in " + ( STUCK_WINDOW_MS / 1000 ) + "s) on " + getDvar( "mapname" ) );
	self setOrigin( dest.origin + ( 0, 0, 40 ) );

	// Force a fresh path recalculation from the new spot instead of immediately
	// trying to resume the old (failing) route - the same reset Bot Warfare's
	// own strafe-recovery does after a stuck event (_bot_internal.gsc).
	if ( isDefined( self.bot ) )
	{
		self.bot.last_next_wp = -1;
		self.bot.last_second_next_wp = -1;
	}
}
