// bpg_survival_droptriggerleak.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-29.
// Leak-proofs the dropped-weapon pickup trigger so it can NEVER be stranded in the mod's
// 20 Hz level.triggers polling loop (lethalbeats\trigger::_triggerMainLoop, wait 0.05).
//
// PROVEN FACTS (LB_Survival.iwd, lethalbeats/Survival/patch/globallogic.gsc):
//   - Every dropped weapon gets ONE spawnstruct trigger + ONE script_model, and the only
//     thing that ever removes the trigger from level.triggers is trigger_delete().
//   - _deletePickupAfterAWhile is the expiry path (bot drops 10-20 s, survivor drops 120 s)
//     but it bails with `if (!isDefined(weaponModel)) return;` BEFORE trigger_delete(). Any
//     route that removes the model first therefore strands the trigger in the polling loop
//     for the rest of the map, together with its weaponPickupMonitor / ammoPickupMonitor
//     threads (both are only ended by the trigger's own "death" notify).
//   - It also dereferences weaponModel.droppedIndex unguarded on the !isSurvivorWeapon
//     branch. That branch is reached when weaponModel.owner has gone undefined (owner
//     disconnected), and a survivor-dropped model has NO droppedIndex, so the original
//     passes undefined into array_remove_index.
// The stock trigger-stranding route (bot_clear_models deleting weapon models but not their
// triggers) is already removed by bpg_survival_botclearfix.gsc v3, so this is belt-and-braces
// on the remaining latent path, not a live-leak fix. Behaviour is byte-identical otherwise:
// same isSurvivorWeapon test, same wait times, same delete order.
// Target loads on every survival map -> replaceFunc is safe.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

#include lethalbeats\survival\utility;

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( lethalbeats\survival\patch\globallogic::_deletePickupAfterAWhile, ::bpg_delete_pickup_after_a_while );
}

// Guarded copy of globallogic::_deletePickupAfterAWhile. self = the pickup trigger.
bpg_delete_pickup_after_a_while( weaponModel )
{
	level endon( "game_ended" );
	self endon( "death" );

	isSurvivorWeapon = isDefined( weaponModel )
		&& isDefined( weaponModel.owner )
		&& isPlayer( weaponModel.owner )
		&& weaponModel.owner player_is_survivor();

	if ( isSurvivorWeapon )
		wait 120;
	else
		wait randomIntRange( 10, 20 );

	if ( isDefined( weaponModel ) )
	{
		if ( !isSurvivorWeapon && isDefined( weaponModel.droppedIndex ) )
			level.droppedWeapons = lethalbeats\array::array_remove_index( level.droppedWeapons, weaponModel.droppedIndex );

		weaponModel delete();
	}

	// ALWAYS drop out of the polling loop, model or no model.
	self lethalbeats\trigger::trigger_delete();
}
