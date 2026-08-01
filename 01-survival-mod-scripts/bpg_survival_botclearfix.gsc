// bpg_survival_botclearfix.gsc — SURVIVAL SERVER ONLY (isolated storage). v3 2026-07-16.
// History: the mod's bot_clear_models (called from bot_kill on EVERY bot death) errored
// constantly. v1 kept the original loop shape and inherited its fatal flaw: the weapon pass
// deletes the weapon INSIDE the per-survivor loop with no break, so the next iteration reads
// weapon.origin on the just-deleted entity ("distancesquared parameter 1 undefined" — engine
// params are 0-indexed), compares undefined>250000, and calls delete() twice ("dead entity").
// PROVEN FACTS from the mod source (globallogic.gsc):
//   - Every dropped weapon already gets _deletePickupAfterAWhile threaded on its trigger:
//     bot drops die after 10-20s, survivor drops after 120s, and it deletes BOTH the model
//     and the trigger. The wave-cleanup weapon pass is REDUNDANT.
//   - Worse, the cleanup pass deleted only the MODEL and left the pickup trigger alive —
//     a player using the orphaned trigger caused the weaponpickupmonitor "dead entity" error.
//   - level.droppedWeapons accumulates stale refs (droppedIndex goes stale after every
//     array_remove_index — the array reindexes, stored indices don't). array_remove_index
//     itself is out-of-range safe, so resetting the list is harmless.
// v3 therefore: keep the bot-BODY cleanup (the real perf need — ~28 bodies/wave) with
// evaluate-first/delete-once structure; DO NOT touch dropped weapons at all (the mod's own
// timed deleter handles model+trigger correctly); still reset level.droppedWeapons (only this
// function ever read it; reset bounds its growth). Side effect players will like: guns no
// longer vanish off the ground when a wave ends.
// player_can_see guard kept (dead/downed survivor has no eye/angles -> return false).
// Both replaceFunc targets load on every survival map -> safe.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

#include common_scripts\utility;
#include maps\mp\_utility;
#include lethalbeats\array;
#include lethalbeats\player;
#include lethalbeats\survival\utility;

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( lethalbeats\player::player_can_see,          ::player_can_see_safe );
	replaceFunc( lethalbeats\survival\utility::bot_clear_models, ::bot_clear_models_safe );
}

// Guarded copy of lethalbeats\player::player_can_see. Original errors when the caller
// (a survivor) has no eye/angles (dead/downed) or when targetOrigin is undefined.
player_can_see_safe( targetOrigin, cos )
{
	if ( !isDefined( cos ) ) cos = 0.7;
	if ( !isDefined( targetOrigin ) ) return false;

	eyePos = self getEye();
	if ( !isDefined( eyePos ) || !isDefined( self.angles ) ) return false;

	toTargetDir = vectorNormalize( targetOrigin - eyePos );
	forward = anglesToForward( self.angles );
	return vectorDot( toTargetDir, forward ) > cos;
}

// Bodies only. Evaluate-first, delete-once. Weapons are managed by the mod's own
// _deletePickupAfterAWhile (10-20s bot drops / 120s survivor drops, model+trigger together).
bot_clear_models_safe()
{
	level endon( "wave_start" );

	survivors = survivors();

	foreach ( bot in bots() )
	{
		if ( !isDefined( bot ) || !isDefined( bot.body ) )
			continue;
		bodyOrg = bot.body.origin; // undefined for a dead-entity ref -> filtered below
		if ( !isDefined( bodyOrg ) )
			continue;

		seen = false;
		foreach ( survivor in survivors )
		{
			if ( !isDefined( survivor ) || !isDefined( survivor.origin ) )
				continue;
			if ( survivor player_can_see_safe( bodyOrg ) )
			{
				seen = true;
				break;
			}
		}

		if ( !seen && isDefined( bot.body ) )
			bot.body delete(); // exactly once, after all reads are done
	}

	level.droppedWeapons = [];
}
