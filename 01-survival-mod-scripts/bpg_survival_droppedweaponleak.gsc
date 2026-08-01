// bpg_survival_droppedweaponleak.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-30.
//
// ✅ ACTIVE AND VERIFIED — status corrected 2026-08-01. Plain .gsc, no .PENDING sibling.
// Verified 2026-08-01: ZERO "parent script variables" / Sys_Error across all 4 survival
// instances. The halt this targets is not recurring.
// replaceFuncs a mod function on the bot-death hot path.
// Side-test on <SIDETEST-PORT> before activating; see the checklist at the bottom.
//
// Targets the fatal halt that killed survival <SURV-PORT-3> on 2026-07-30:
//     Sys_Error: exceeded maximum number of parent script variables
// mp_raid, wave 33, TotalCount 341. Heartbeats kept succeeding afterwards, so the server looked
// alive while the game thread was dead — see internal notes.
//
// ── THE LEAK ─────────────────────────────────────────────────────────────────────────────────
// lethalbeats\survival\utility::bot_clear_models (utility.gsc:933-957) is threaded every 15 bot
// deaths (utility.gsc:920). It ends with:
//
//     foreach ( weapon in level.droppedWeapons )
//         if ( isDefined( weapon ) )
//             foreach ( survivor in survivors )
//                 if ( far && !visible ) weapon delete();
//     level.droppedWeapons = [];          <-- unconditional
//
// A weapon that is CLOSE TO or VISIBLE TO the survivors is deliberately not deleted — correct,
// you should not vanish a gun someone is walking toward. But the array is then cleared anyway,
// so that still-alive entity is now UNTRACKED: nothing holds a reference to it, no later pass can
// ever cull it, and it persists for the rest of the map. Each one owns script fields (at minimum
// .droppedIndex, assigned at patch\globallogic.gsc:1471-1472), and every field-owner consumes a
// PARENT script variable — the exact pool the Sys_Error reports.
//
// The rate fits the observed failure: bot_clear_models runs once per 15 deaths, so a 341-kill
// wave runs it ~22 times, each leaving behind however many weapons happened to be near a player.
// Slow, monotonic, and only fatal on a long single-map game — which is why it took 33 waves and
// why map rotation appears to "fix" it.
//
// Second defect, same function: `level endon("wave_start")`. If a wave starts mid-loop the thread
// dies and `level.droppedWeapons = []` never runs, so the array instead grows without bound. The
// array is therefore mismanaged in BOTH directions depending on timing.
//
// ── THE FIX ──────────────────────────────────────────────────────────────────────────────────
// Rebuild the array from the survivors instead of blanket-clearing it. Anything still alive stays
// tracked and becomes eligible for the NEXT pass, once the players have moved away. This bounds
// the set by "weapons currently near players" rather than "every weapon ever dropped", and it
// also makes the endon abort harmless — an early exit just leaves the array intact for next time.
//
// Also fixes a live runtime error in the same loop: stock calls `weapon delete()` inside the
// per-survivor loop and then keeps iterating, so the next survivor dereferences `weapon.origin`
// on a deleted entity. Breaking out after the delete removes that error too.
//
// Deliberately NOT changed: the cull distance (500u), the visibility test, the bot-body cleanup,
// and the every-15-deaths cadence. This is a lifetime fix, not a behaviour change — players
// should not be able to tell it deployed, except that the server stops dying.

// Includes are load-bearing and were verified against where each helper is actually DEFINED,
// not guessed: an unresolved function in GSC is a COMPILE-time failure that kills the whole file.
// The mod's utility.gsc gets these transitively from its own #include list (utility.gsc:1-6);
// #include does not re-export, so this file must name them itself.
//   survivors(), bots(), bot_clear_models  -> lethalbeats\survival\utility  (utility.gsc:638,974)
//   player_can_see( origin, cos )          -> lethalbeats\player            (player.gsc:821)
//   array_any_ent( ents, func, ... )       -> lethalbeats\array
#include lethalbeats\array;
#include lethalbeats\player;
#include lethalbeats\survival\utility;

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( lethalbeats\survival\utility::bot_clear_models, ::bpg_bot_clear_models_fixed );
}

bpg_bot_clear_models_fixed()
{
	level endon( "wave_start" );

	survivors = survivors();

	// unchanged from stock
	foreach ( bot in bots() )
	{
		if ( isDefined( bot.body ) && !array_any_ent( survivors, ::player_can_see, bot.body.origin ) )
			bot.body delete();
	}

	maxDist = 500 * 500;
	kept = [];

	foreach ( weapon in level.droppedWeapons )
	{
		if ( !isDefined( weapon ) )
			continue;   // already deleted elsewhere - drop the dead slot

		deleted = false;

		foreach ( survivor in survivors )
		{
			if ( distanceSquared( survivor.origin, weapon.origin ) > maxDist && !survivor player_can_see( weapon.origin ) )
			{
				weapon delete();
				deleted = true;
				break;  // stock kept iterating and read weapon.origin on a deleted entity
			}
		}

		// THE FIX: a weapon we chose NOT to delete stays tracked, so a later pass can still
		// reach it. Stock dropped it here and leaked the entity for the rest of the map.
		if ( !deleted )
			kept[ kept.size ] = weapon;
	}

	level.droppedWeapons = kept;
}

// ── SIDE-TEST CHECKLIST (<SIDETEST-PORT>, never with the live authtoken) ────────────────────────────────
// 1. Boot survival on mp_raid. Play/idle until several waves pass so bot_clear_models runs many
//    times (it fires every 15 bot deaths).
// 2. Confirm level.droppedWeapons does NOT grow without bound and does NOT sit at 0 forever -
//    it should breathe: rise while players are near dropped guns, fall once they move away.
// 3. Confirm no new runtime errors from bot_clear_models, especially none mentioning
//    weapon.origin / deleted entities.
// 4. Confirm dropped weapons are still pickable and still disappear when players walk away -
//    the cull behaviour must be indistinguishable from before.
// 5. Then drop .PENDING and sync to Survival2/3/4.
