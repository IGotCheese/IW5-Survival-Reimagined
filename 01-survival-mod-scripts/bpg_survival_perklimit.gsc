// bpg_survival_perklimit.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-19.
// User: "remove the perk limit".
// lethalbeats\Survival\utility.gsc's survivor_give_perk() hard-caps at
// `if (self.survivalPerks.size == 3) return;`. Confirmed via lethalbeats\player.gsc's
// player_give_perk -> player_set_perk -> self setPerk(perkName, isPro, useSlot=false) that
// the ENGINE has no limit on non-slotted perks (useSlot=false skips the classic 3-slot loadout
// system entirely) - the cap is a purely mod-side design choice, not an engine constraint.
// This is a full replaceFunc copy of survivor_give_perk with only that one line removed.
// Cosmetic note: _survivor_update_perks() only sets ui_perk1/2/3 client dvars (3 HUD icon
// slots) - a 4th+ perk is still fully functional (granted via setPerk immediately) but won't
// get its own HUD icon since no ui_perk4+ menu element exists to bind to. Out of scope here.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

#include lethalbeats\survival\utility;
#include lethalbeats\player;

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replacefunc( lethalbeats\survival\utility::survivor_give_perk, ::bpg_survivor_give_perk );
}

bpg_survivor_give_perk( perk )
{
	if ( self player_has_perk( perk ) )
		return;

	// ui_perks -> player_perks
	if ( perk == "specialty_steadyaim" )
		perk = "specialty_bulletaccuracy";
	else if ( perk == "specialty_blastshield" )
		perk = "_specialty_blastshield";
	else if ( perk == "specialty_bombsquad" )
		perk = "specialty_detectexplosive";

	self player_give_perk( perk, false );

	// player_perks -> ui_perks
	if ( perk == "specialty_bulletaccuracy" )
		perk = "specialty_steadyaim";
	else if ( perk == "_specialty_blastshield" )
		perk = "specialty_blastshield";
	else if ( perk == "specialty_detectexplosive" )
		perk = "specialty_bombsquad";

	self.survivalPerks[ self.survivalPerks.size ] = perk;
	self _survivor_update_perks();
}
