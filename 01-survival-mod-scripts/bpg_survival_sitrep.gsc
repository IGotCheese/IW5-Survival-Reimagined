// yourserver.gg 2026-07-17 — SURVIVAL: make Sitrep the REAL SitRep Pro, and make ALL air-support
// perks deliver reliably.  (user: "sitrep doesnt work" -> "fix it properly" -> "sitrep should
// do everything sitrep pro does" per https://callofduty.fandom.com/wiki/SitRep)
//
// SitRep (MW3): detect enemy explosives + tactical insertions.
// SitRep Pro:   + enemy footsteps are much louder.
// Both are behaviours of the ENGINE perk specialty_detectexplosive, and the mod already
// grants it at Pro level (survivor_give_perk -> player_give_perk -> setPerk with the upgrade
// flag on, because it's a real engine perk not a scriptPerk). So the authentic effect just
// needs to (a) actually be delivered and (b) not be overridden.
//
// WHY IT DID NOTHING BEFORE:
//   DELIVERY — every air-support perk is dropped via an airdrop CRATE
//   (giveAirDrop -> giveKillstreak("airdrop_assault")). On ported maps with no care-package
//   brush, createAirDropCrate errors at clonebrushmodeltoscriptmodel and the crate is never
//   usable, so the perk (and sentry/predator/etc.) never arrive.
//
// FIX — replaceFunc giveAirDrop: "perk_*" drops are granted INSTANTLY (perks don't need a
// physical crate; also un-breaks bulletaccuracy/stalker/longersprint/fastreload/blastshield/
// quickdraw on no-brush maps). Grant path is byte-identical to the crate pickup
// (_getCrateTypeForDropType -> getPerkFromKsPerk -> survivor_give_perk). Non-perk drops fall
// through to the original crate behaviour.
//
// giveAirDrop / survivor_give_perk live in always-loaded survival scripts, so the replaceFunc
// target resolves on EVERY map -> safe. NEVER copy to live <MP-PORT> (references lethalbeats\*).

#include maps\mp\_utility;
#include common_scripts\utility;

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( lethalbeats\survival\killstreaks\_airdrop::giveAirDrop, ::giveAirDrop_instantPerk );
}

// perks apply instantly (real SitRep Pro engine perk included); everything else keeps its
// original crate drop.
giveAirDrop_instantPerk( type )
{
	if ( isDefined( type ) && getSubStr( type, 0, 5 ) == "perk_" )
	{
		ksName = lethalbeats\survival\killstreaks\_airdrop::_getCrateTypeForDropType( type );
		perk   = lethalbeats\survival\utility::getPerkFromKsPerk( ksName );
		self lethalbeats\survival\utility::survivor_give_perk( perk );
		self playLocalSound( "ammo_crate_use" );

		if ( type == "perk_sitrep" )
		{
			level notify( "update_bombsquad" );
			self iPrintLnBold( "^3SitRep Pro ^7- enemy explosives revealed + enemy footsteps louder" );
		}
		return;
	}

	// original giveAirDrop behaviour (physical air-support crate)
	self.airdropType = type;
	self maps\mp\killstreaks\_killstreaks::giveKillstreak( "airdrop_assault" );
}
