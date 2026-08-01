// bpg_survival_juggerdropfix.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-30.
// USER REPORT: "yes i have seen the juggernaut stall a wave".
//
// THE BUG (traced in lethalbeats\Survival\abilities\_juggernaut.gsc):
//   giveAbility() reserves a drop zone at :37
//       level.juggerDropInUse[level.juggerDropInUse.size] = dropZone;
//   and before that it SPINS until it finds a free one (:32-36):
//       while ( array_contains( level.juggerDropInUse, dropZone ) ) { dropZone = random(dropZones); wait 0.5; }
//   The reservation is released on exactly TWO paths:
//       :170  _juggerDrop()        - the normal, successful drop
//       :224  _mi17_handleDamage() - the heli is shot down
//   There is a THIRD way the mi17 dies and it releases NOTHING. _mi17_setup() :103 threads the
//   stock maps\mp\killstreaks\_airdrop::watchtimeout(), which waits 25.0s and then does
//   `self notify("death")`. _juggerDrop() opens with `mi17 endon("death")` (:118), so that notify
//   KILLS the drop thread before it can reach the :169-170 cleanup — the zone stays reserved for
//   the rest of the map and the rope script_model is orphaned.
//
// WHY IT ACTUALLY HAPPENS (the margin is small): from mi17 spawn the drop costs
//   wait 2 (:120) + flight to the goal (:126 waittill "goal") + wait 3 (:127)
//   + 335 frames of the drop loop (:135, wait_frame() at 20Hz = 16.75s)
//   = ~21.75s + flight, against a 25.0s timeout. Any drop zone far enough from the spawn edge,
//   or any server hitch, eats the ~3s of slack. So this is not a rare corner case.
//
// WHY IT ENDS THE MATCH: level.juggDrop[mapname] holds a FINITE list of zones. Once every zone
// has been leaked, the while() at :32 can never find a free one. It has a `wait 0.5` so it does
// not hang the server — it spins forever, the juggernaut bot never spawns, and the wave can
// never complete. That is the stall.
//
// THE FIX — deliberately NOT a replaceFunc.
// Rewriting _mi17_setup/_doFlyBy/giveAbility would put our code directly in the juggernaut spawn
// path, and those functions call file-private helpers (_mi17_handleDamage, _doFlyBy) plus
// unqualified stock ones (watchtimeout, heli_existence) that would all need re-qualifying by
// hand. Getting any one of them wrong breaks the juggernaut outright — a far worse outcome than
// the occasional stall we are fixing. Instead this is a passive watchdog that cannot affect the
// spawn path at all:
//   * The mi17 is registered in level.littlebirds at _juggernaut.gsc:91 and removed from it on
//     death by stock removefromlittlebirdlistondeath() (_helicopter.gsc:1981-1986), which is
//     keyed on getentitynumber() and therefore always accurate.
//   * `.dropSite` is set ONLY on the juggernaut mi17 (_juggernaut.gsc:69). No other littlebird
//     carries it, so it is an exact discriminator.
// Therefore: if NO live littlebird has a .dropSite, no juggernaut drop is in flight, and any
// surviving reservation in level.juggerDropInUse is provably stale. That is a strictly safe
// condition — it cannot be true while a legitimate drop is in progress.
//
// Conservative by construction: it requires the condition to hold for THREE consecutive polls
// (~15s) before acting, which comfortably covers the gap between giveAbility() reserving a zone
// and _mi17_setup() registering the heli, so an in-flight drop can never be cleared out from
// under itself.
//
// NOT FIXED HERE: the orphaned `rope_test_ri` script_model that the same timeout leaks (one per
// occurrence, ~58 joints). It costs a model, not a match, and deleting it needs the mi17 handle
// this watchdog deliberately does not hold. Worth a separate pass if model pressure matters.
//
// ⚠️ NEVER copy to the live <MP-PORT> server (survival-only paths).

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	level thread bpg_juggerdrop_watchdog();
}

bpg_juggerdrop_watchdog()
{
	level endon( "game_ended" );

	// consecutive polls that agreed "no drop is in flight"
	streak = 0;

	for ( ;; )
	{
		wait 5;

		// Runs BEFORE the stale-zone check on purpose: a stranded heli keeps live_count() above
		// zero forever, which would otherwise reset `streak` on every poll and stop the block
		// below from ever firing. Clearing the strand first lets the original logic work again.
		bpg_juggerdrop_sweep_stranded();

		if ( !isDefined( level.juggerDropInUse ) || level.juggerDropInUse.size == 0 )
		{
			streak = 0;
			continue;
		}

		if ( bpg_juggerdrop_live_count() > 0 )
		{
			streak = 0;
			continue;
		}

		streak++;

		if ( streak < 3 )
			continue;

		// Nothing has been in flight for ~15s yet zones are still reserved -> all stale.
		println( "[BPG-JUGGER] releasing " + level.juggerDropInUse.size + " stale juggernaut drop zone(s) - no mi17 in flight" );
		level.juggerDropInUse = [];
		streak = 0;
	}
}

// Number of juggernaut drop helicopters currently alive. Counts only littlebirds carrying
// .dropSite, which _juggernaut.gsc:69 sets on the mi17 and nothing else sets.
bpg_juggerdrop_live_count()
{
	if ( !isDefined( level.littlebirds ) )
		return 0;

	n = 0;

	foreach ( lb in level.littlebirds )
	{
		if ( !isDefined( lb ) )
			continue;

		if ( isDefined( lb.dropSite ) )
			n++;
	}

	return n;
}

// ── STRANDED-HELICOPTER SWEEP (added 2026-07-30 from a user screenshot on mp_geometric) ──────
// A juggernaut mi17 was left hovering permanently, having already delivered its juggernaut.
// Cause: _juggerDrop() only calls heli_leave() at frame 230 of a 335-frame loop that starts
// AFTER `mi17 waittill("goal")` (:126). Two ways it never gets there:
//   * the heli never reaches its goal (custom maps whose flight path the vehicle cannot make),
//     so the waittill never returns; or
//   * stock watchtimeout() fires notify("death") at 25.0s first and `mi17 endon("death")` (:118)
//     kills the drop thread mid-loop. The header arithmetic shows only ~3s of slack.
//
// ⚠️ THIS IS NOT COSMETIC, and that is why it is worth fixing rather than tolerating.
// A stranded heli is still ALIVE and still carries .dropSite, so bpg_juggerdrop_live_count()
// counts it, the watchdog's `streak` resets on every poll, and the stale reservation above is
// NEVER released. One hovering helicopter permanently disables the very stall fix this file
// exists to provide - the drop-zone list can still be exhausted and still end the match.
//
// Still deliberately NOT a replaceFunc on the drop path (see the header): this only touches
// helicopters it has already positively identified, long after any legitimate drop has finished.
// 90s is enormous next to the ~21.75s + flight a real drop needs, so a healthy drop can never
// be caught by it.
// ⚠️ v2 2026-07-31 - v1 DID NOT WORK and the reason is worth keeping.
// v1 walked level.littlebirds looking for .dropSite. That list is exactly the wrong place:
// _juggernaut.gsc:92 threads stock removefromlittlebirdlistondeath(), which is
//     var_0 = self getentitynumber(); self waittill("death"); level.littlebirds[var_0] = undefined;
// so the very notify("death") that watchtimeout() fires - the event that CAUSES the strand -
// also delists the heli. The entity is NOT deleted (a death notify is a script signal, not a
// delete), so it keeps hovering while being invisible to anything iterating level.littlebirds.
// v1 therefore could never see the helicopters it existed to catch: 0 [BPG-JUGGER] lines while
// one sat in the sky. Enumerate real entities instead, the way the mod itself does at
// patch\globallogic.gsc:1905 and dev\test.gsc:691.
bpg_juggerdrop_sweep_stranded()
{
	// 2026-07-31: was 90000. The user reported the helicopter "still showing" AFTER this fix was
	// confirmed working in the log - it was not failing, it was taking ~110s (90 here + 20 in
	// bpg_jugger_force_home) to act, which reads as broken from inside the game. A healthy drop
	// is finished in ~22s + flight (wait 2 + flight + wait 3 + 335 frames at 20Hz), and stock
	// ⚠️ 2026-08-01 v4 - THE THRESHOLD WAS THE BUG.
	// The old comment here claimed "watchTimeOut() fires notify("death") at 25.0s, so anything
	// still hanging at 30s is provably aborted". Both halves were wrong:
	//
	//   1. watchTimeOut is _a10.gsc:261 and waits **35.0** seconds, not 25:
	//          waitLongDurationWithHostMigrationPause( 35.0 ); self notify( "death" );
	//      So a 30s limit fired BEFORE the mod's own cleanup every single time.
	//   2. "Provably stranded" was never proven. _juggernaut.gsc:164 calls heli_leave() with NO
	//      destination, so it picks one from level.heli_leave_nodes. On mp_dome those four real
	//      nodes sit 13,000-17,000 units out and heli_leave flies at speed 100 - about 2.5
	//      MINUTES in transit. A helicopter alive at 30s is perfectly healthy and still flying.
	//
	// Measured cost of that mistake: 6 "stranded" reports out of 9 juggernaut drops on <SURV-PORT-2> -
	// i.e. almost every drop was falsely flagged and force-deleted mid-departure, which is what
	// produced the heli_leave double-delete errors.
	//
	// 60s gives the mod's own 35s watchTimeOut room to run first. Anything still present after
	// that genuinely did not get cleaned up, which is the case this file exists for.
	limit = 60000;   // ms alive before a juggernaut heli is treated as genuinely stuck
	if ( getDvarInt( "bpg_jugger_strand_ms" ) > 0 )
		limit = getDvarInt( "bpg_jugger_strand_ms" );

	now = getTime();

	// .dropSite is set ONLY on the juggernaut mi17 (_juggernaut.gsc:69), so among vehicles it
	// remains an exact discriminator - and unlike level.littlebirds it cannot be revoked.
	foreach ( v in getEntArray( "script_vehicle", "classname" ) )
	{
		if ( !isDefined( v ) || !isDefined( v.dropSite ) )
			continue;

		// first sighting - stamp it and let it do its job
		if ( !isDefined( v.bpg_firstSeen ) )
		{
			v.bpg_firstSeen = now;
			continue;
		}

		if ( now - v.bpg_firstSeen < limit )
			continue;

		// act once, never repeatedly
		if ( isDefined( v.bpg_leaveSent ) )
			continue;

		v.bpg_leaveSent = true;

		println( "[BPG-JUGGER] mi17 stranded " + ( ( now - v.bpg_firstSeen ) / 1000 ) + "s - releasing zone, clearing models, sending it home" );

		// Release the reservation FIRST, while .dropSite is still readable.
		if ( isDefined( level.juggerDropInUse ) )
			level.juggerDropInUse = lethalbeats\array::array_remove( level.juggerDropInUse, v.dropSite );

		// The rope/jugger script_models the aborted drop orphaned. _juggernaut.gsc:82 parks both
		// on mi17.models, so the handles the drop thread lost are still reachable from here.
		// This is the leak the v1 header listed as "NOT FIXED HERE".
		if ( isDefined( v.models ) )
		{
			foreach ( m in v.models )
			{
				if ( isDefined( m ) )
					m delete();
			}
			v.models = undefined;
		}

		v thread bpg_jugger_force_home();
	}
}

// heli_leave() is NOT trusted on its own here. It picks a destination from
// level.heli_leave_nodes and then setVehGoalPos()s to it - the exact mechanism that already
// failed, since "cannot reach its goal" is one of the two ways a heli gets stranded. On a map
// where that is broken it would hover forever again, just with a different goal. So: ask
// politely, then delete if it is still hanging there. Deleting is safe - this heli has already
// been notify("death")'d and delisted, its juggernaut was delivered long ago, and it is a prop.
bpg_jugger_force_home()
{
	// ⚠️ On our maps this branch NEVER runs, and that is now proven rather than assumed.
	// level.heli_leave_nodes is set by stock maps\mp\killstreaks\_helicopter::init, which opens
	// with `if (!getentarray("heli_start","targetname").size && !getentarray("heli_loop_start",
	// "targetname").size) return;` - and none of our maps have those nodes (the same early
	// return is why bpg_survival_chopperfxinit.gsc has to build level.chopper_fx by hand).
	// So heli_leave is always skipped here and the grace period below was pure dead time.
	// Kept anyway in case a map with heli nodes is ever added; the wait is now sized for the
	// case that actually happens.
	// 2026-07-31: heli_leave takes an OPTIONAL destination (_helicopter.gsc:1862) -
	//     if ( !isdefined( var_0 ) ) { var_1 = level.heli_leave_nodes[randomint(..)]; var_0 = var_1.origin; }
	// so passing one explicitly skips the node lookup that used to error on our maps entirely.
	// That matters beyond tidiness: the real heli_leave flies the helicopter off, notifies
	// "death", and calls decrementFauxVehicleCount() before deleting itself. A bare delete()
	// skipped that decrement, permanently inflating level.fauxvehiclecount - the very counter
	// that jams level_airspace_is_crowded() and strands every later queued bot. Leaving properly
	// repairs the count instead of leaking it.
	// bpg_survival_helinodesfix.gsc now also synthesizes level.heli_leave_nodes, so the no-arg
	// path works too; this passes one anyway so the fix does not depend on load order.
	dest = undefined;

	if ( isDefined( level.heli_leave_nodes ) && level.heli_leave_nodes.size > 0 )
		dest = level.heli_leave_nodes[ 0 ].origin;
	else if ( isDefined( self.origin ) )
		dest = self.origin + ( 0, 0, 6000 );

	dispatched = false;

	if ( isDefined( dest ) )
	{
		self thread maps\mp\killstreaks\_helicopter::heli_leave( dest );
		dispatched = true;

		// ⚠️ 2026-07-31 v3 - THE DOUBLE-DELETE FIX.
		// heli_leave ends with: notify( "death" ) -> decrementFauxVehicleCount() -> delete().
		// Without this endon, BOTH that thread and the cleanup below try to delete the same
		// helicopter, and whichever loses the race throws:
		//     in call to builtin method "delete": attempt to call a method on 'dead entity'
		//         at function "heli_leave" in file "maps/mp/killstreaks/_helicopter.gsc"
		// (seen 7x live on <SURV-PORT-2> with players on the server).
		//
		// The previous comment here claimed "that thread dies the moment this entity is
		// deleted". That is FALSE - deleting an entity does not kill threads running on it;
		// they run on until they touch the dead entity and then error. endon( "death" ) is
		// what actually stands this thread down, because heli_leave notifies "death" BEFORE
		// it deletes. If heli_leave finishes the job, we never run at all - which is the
		// preferred outcome, since it does the decrement and the delete correctly itself.
		self endon( "death" );
	}

	// ⚠️ 2026-07-31: this wait was 12s and the log line called it "heli_leave did not clear it".
	// BOTH were wrong. heli_leave (_helicopter.gsc:1885-1897) does
	//     vehicle_setspeed( 100, 45 ); setvehgoalpos( <node>, 1 ); waittillmatch( "goal" );
	// against a leave node 15000 units out - well over two minutes in transit. heli_leave was
	// working fine; the old 12s timer was deleting the helicopter mid-flight and then blaming it.
	// Observed live on mp_dome, which has four REAL leave nodes, so this was never about our
	// synthesized ones.
	// ⚠️ v3: 25s was STILL wrong. The note above worked out that the flight takes over two
	// minutes, then picked a 25s timer anyway "for the eye" - which force-deleted the
	// helicopter mid-flight and caused the double-delete. Cosmetics are not worth corrupting
	// the entity out from under a running stock function.
	//
	// So: when heli_leave was dispatched this is now a pure BACKSTOP, not a timer. The endon
	// above means we normally never reach it - heli_leave completes and stands us down. We
	// only get here if heli_leave never finishes (stranded a second time), and then 180s is
	// comfortably past the real flight time so we are not racing it.
	//
	// With no destination there is nothing flying anywhere, so clean up promptly instead.
	if ( dispatched )
		wait 180;
	else
		wait 5;

	if ( isDefined( self ) )
	{
		println( "[BPG-JUGGER] mi17 is clear of the map - removing it" );

		// THE LEAK THIS PREVIOUSLY REINTRODUCED. heli_leave's LAST act before deleting itself is
		//     maps\mp\_utility::decrementFauxVehicleCount();
		// Deleting the helicopter before it gets there means that never runs, so
		// level.fauxvehiclecount stays high - and level_airspace_is_crowded() trips at >= 4,
		// which jams level_vehicle_monitor and strands every later queued bot. That is the exact
		// failure this whole file exists to stop, so cutting the flight short without doing the
		// decrement ourselves was silently keeping it alive.
		// Reaching here means heli_leave did NOT complete (no "death" notify, or it was never
		// dispatched), so its decrement never ran and doing it here is correct. If it HAD
		// completed, endon( "death" ) above stood this thread down and we are not executing.
		maps\mp\_utility::decrementFauxVehicleCount();

		// _mi17_setup threads _chopper::lbSurvivalDeathCrash on this helicopter, which keeps
		// calling playsound/setyawspeed on it; deleting underneath that thread produced live
		// "attempt to call a method on 'dead entity'" errors. It guards with endon("gone").
		self notify( "gone" );

		self delete();
	}
}
