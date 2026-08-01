// bpg_survival_ah6nerf.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-23.
// User: "nerf helicopter damage by 80 percent for enemy ah6s" + "ah6s in survival had a
// spin up time on their guns see if you can research how that works and implement that."
//
// RESEARCH FIRST (public source, LastDemon99/IW5-Survival-Reimagined on GitHub), before
// writing anything, per this project's established practice:
//
// (1) DAMAGE SOURCE IDENTIFICATION — traced the exact attacker-entity chain from
//     lethalbeats\Survival\abilities\_chopper.gsc::startLBSupport():
//       lb.heliType = "littlebird";              // set on the CHOPPER BODY only
//       mgTurret.vehicle = lb;                    // turret -> body back-reference
//       lb.mgTurretLeft = mgTurret; (and Right)
//     The turret entities (mgTurretLeft/mgTurretRight) are what actually call
//     shootturret() in lbBurstFireStart() - THEY are the attacker onPlayerDamage sees,
//     not the body, and they never get .helitype set directly. The existing (task #30,
//     "reduce helicopter damage by 50%") fix apparently checked `attacker.helitype`
//     directly per bpg_helidamage_probe.gsc's test setup - that field is never actually
//     set on the turret entity in production, only on `attacker.vehicle` (the body). This
//     file no longer exists in the loose scripts folder (confirmed via grep - the 50%
//     fix isn't currently deployed at all), so there was nothing live to preserve or
//     conflict with. The correct, verified check is `attacker.vehicle.heliType ==
//     "littlebird"`. Confirmed Pave Low uses a DIFFERENT field entirely
//     (self.helitype = "flares"/"minigun"/"flares_survial", set directly, no .vehicle
//     indirection) - so this check is AH6-specific and will not touch Pave Low.
//
// (2) SPIN-UP TIME — already exists in the mod itself, working exactly as designed:
//     lethalbeats\Survival\difficulty::difficulty_get_h6_burst_settings() returns a
//     "windUpTime" per difficulty (used by lbBurstFireStart()'s wind-up wait loop before
//     the burst starts, canceling if the target breaks LOS/cover during it):
//       Easy:   windUpTime = 1.75
//       Normal: windUpTime = 1
//       Hard:   windUpTime = 0        <-- this is why "hard" (the difficulty this
//                                          server always loads via load_dsr) has no
//                                          perceptible spin-up: it's intentionally
//                                          zeroed as part of Hard's difficulty curve
//                                          (also gets more shots/burst, faster fire
//                                          rate, shorter pause vs Normal/Easy).
//     Not a bug - a deliberate difficulty scaling choice by the mod author. Restoring a
//     nonzero value on Hard specifically is a genuine balance change, not a fix.
//
// ⚠️ REPLACEFUNC-CONFLICT CHECK: grepped all loose scripts for both
// survivorHandler::onPlayerDamage and difficulty::difficulty_get_h6_burst_settings -
// no other file replaceFunc's either. Clear to claim both.
// ⚠️ SIDE-TEST before live: this can't be behaviorally verified in a headless side-test
// (no real players -> survival's wave/enemy AI never meaningfully activates, same wall
// as every other survival gameplay fix this project has hit) - compile-check only, ask
// for a live report on whether AH6 hits feel weaker and the wind-up is visible on hard.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

#include lethalbeats\survival\utility;
#include lethalbeats\player;
#include lethalbeats\hud;

#define FRAG "frag_grenade_mp"
#define FLASH "flash_grenade_mp"
#define UI_USE_SLOT "ui_use_slot"

#define CH_HEADSHOT 0
#define CH_KILL 1
#define CH_KNIFE 2
#define CH_GRENADE 3

#define MOD_MULTIPLIER ["MOD_EXPLOSIVE", "MOD_GRENADE", "MOD_GRENADE_SPLASH", "MOD_PROJECTILE", "MOD_PROJECTILE_SPLASH", "MOD_RIFLE_BULLET"]

#define DIFFICULTY_EASY 1
#define DIFFICULTY_NORMAL 2
#define DIFFICULTY_HARD 3

// AH6 minigun damage kept at 20% (80% reduction) once identified as an AH6 hit.
#define AH6_DAMAGE_MULT 0.2
// Restored wind-up time on Hard (was 0 - instant, no tell). Kept shorter than Normal's
// 1s since Hard should still be more dangerous, just no longer completely untelegraphed.
#define AH6_HARD_WINDUP 0.75

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	// bpg 2026-07-27: restored with the fall-damage nerf below. Live-tunable without a
	// restart: `set bpg_falldamage_mult 0.1` = take 10% of stock fall damage (90% off).
	if ( getDvar( "bpg_falldamage_mult" ) == "" )
		setDvar( "bpg_falldamage_mult", "0.1" );

	replaceFunc( lethalbeats\survival\survivorHandler::onPlayerDamage, ::bpg_onPlayerDamage_ah6nerf );
	replaceFunc( lethalbeats\survival\difficulty::difficulty_get_h6_burst_settings, ::bpg_h6_burst_settings_windup );
}

// Byte-for-byte copy of lethalbeats\survival\survivorHandler::onPlayerDamage - ONLY
// change: capture the AH6-hit flag from the ORIGINAL eAttacker (the turret entity)
// before the stock eAttacker=eAttacker.owner reassignment overwrites it, then apply
// AH6_DAMAGE_MULT at the same point the stock function applies its own /20 downscale.
bpg_onPlayerDamage_ah6nerf( eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, timeOffset )
{
	// bpg 2026-07-27: AFK players take nothing. This check belongs HERE and not in
	// bpg_survival_afk.gsc because only ONE replaceFunc of survivorHandler::onPlayerDamage
	// can be active at a time (last-loaded-wins, proven live 2026-07-19), and this file
	// owns it. It existed in the pre-07-26 AFK build, was dropped when that file moved AFK
	// onto the engine spectator state (a spectator has no body, so immunity came for free),
	// and is load-bearing again now that the spectator mechanism has been reverted — see
	// the header of bpg_survival_afk.gsc for why it had to go.
	if ( isDefined( self.bpg_afk ) && self.bpg_afk )
		return;

	isAH6Hit = isDefined( eAttacker ) && isDefined( eAttacker.vehicle ) && isDefined( eAttacker.vehicle.heliType ) && eAttacker.vehicle.heliType == "littlebird";

	// bpg 2026-07-27: RESTORED (task #30, "reduce helicopter damage to players by 50%").
	// Also lost in the 07-26 hook move. Captured HERE, at the top, because the stock
	// `eAttacker = eAttacker.owner` reassignment further down would otherwise swap the
	// attacker out before we can read it.
	// Verified against mod source rather than assumed: _pavelow.gsc:84 sets
	// `heli.helitype = heliType` DIRECTLY on the heli, and _pavelow.gsc:354 fires with
	// `self shootturret()` - so for Pave Low the attacker IS the entity carrying the
	// field, and this check catches it. The AH6 is structurally different: _chopper.gsc
	// puts heliType on the BODY (:120) and the attacker is the mgTurret, which only holds
	// a `.vehicle` back-reference (:151/:160) - so a turret never has .helitype and can
	// never match here. The two nerfs therefore cannot both fire on one hit; the else-if
	// below makes that guarantee structural rather than incidental.
	isHeli = isDefined( eAttacker ) && isDefined( eAttacker.helitype );

	// DIAGNOSTIC REMOVED 2026-07-30 - confirmed working on live gameplay: every AH6 minigun
	// hit logged `isAH6Hit=1 weapon=littlebird_guard_minigun_mp rawDamage=20`, i.e. the turret
	// path is matched and the 20% multiplier is applied. It fired once per bullet, so at a
	// minigun's rate of fire it was the single loudest thing in console.log. Do not re-add
	// a per-hit println here; if this needs re-checking, gate it behind a dvar.

	if ( iDamage >= self.health && isDefined( self.usingRemote ) )
	{
		switch ( self.usingRemote )
		{
			case "remotemissile":
				foreach ( rocket in level.rockets )
					if ( isDefined( rocket ) && isDefined( rocket.owner ) && rocket.owner == self )
					{
						rocket notify( "death" );
						while ( isDefined( self.usingRemote ) )
							wait 0.35;
					}
				break;
		}

		while ( isDefined( self.usingRemote ) )
			wait 0.35;
	}

	if ( sMeansOfDeath == "MOD_FALLING" )
	{
		// bpg 2026-07-27: RESTORED (task #50, "reduce survival fall damage by 90%"). This
		// lived in bpg_survival_afk.gsc's onPlayerDamage copy and was silently lost on
		// 07-26 when that copy was deleted and hook ownership moved to this file - this
		// branch had been passing iDamage through unmodified ever since, i.e. fall damage
		// was back at 100% stock. Note this branch returns early, so the /20 downscale
		// further down never applies to falls; the multiplier is the ONLY reduction here.
		iDamage = int( iDamage * getDvarFloat( "bpg_falldamage_mult" ) );
		self [[ level.prevCallbackPlayerDamage ]]( eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, timeOffset );
		return;
	}

	if ( isDefined( self.dogKnockdown ) && self.dogKnockdown )
		return;
	if ( isDefined( eAttacker ) && isDefined( eAttacker.team ) && eAttacker.team == "allies" && eAttacker != self )
		return;

	if ( lethalbeats\array::array_contains( MOD_MULTIPLIER, sMeansOfDeath ) )
	{
		iDamage *= 4;
		if ( ( sMeansOfDeath != "MOD_RIFLE_BULLET" && self player_has_perk( "_specialty_blastshield" ) ) || ( isDefined( eAttacker ) && eAttacker == self ) )
			iDamage /= 2;
	}

	if ( isDefined( sHitLoc ) && sHitLoc == "shield" )
		return;
	if ( isDefined( eAttacker ) )
	{
		if ( eAttacker bot_is_dog() )
			eAttacker lethalbeats\Survival\abilities\_dog::onDogPlayerDamage( self );
		if ( isDefined( eAttacker.owner ) )
			eAttacker = eAttacker.owner;
	}

	if ( sWeapon == "remote_mortar_missile_mp" && !self.bodyArmor )
		iDamage = self.maxHealth / 2;
	else
		iDamage /= 20;

	if ( isAH6Hit )
		iDamage *= AH6_DAMAGE_MULT;   // AH6 minigun: 20% of stock (80% reduction)
	else if ( isHeli )
		iDamage /= 2;                 // every other heli (Pave Low): 50% reduction

	self.summary[ "damagetaken" ] += iDamage;

	if ( self.inLastStand )
	{
		if ( self.lastStandBar.type == "revive" )
		{
			self.lastStandBar.frac -= 0.15;
			self.lastStandBar.frac = max( 0, self.lastStandBar.frac );
			self.lastStandBar hud_update_bar( self.lastStandBar.frac, 0 );
			self.lastStandBar.bar.color = ( 1, self.lastStandBar.frac, 0 );
		}
		return;
	}

	if ( self.bodyArmor > 0 && sMeansOfDeath != "MOD_TRIGGER_HURT" )
	{
		armor = int( self.bodyArmor - iDamage );
		if ( armor < 0 )
			self survivor_take_body_armor();
		else
		{
			if ( armor == 0 )
				self survivor_take_body_armor();
			else
				self survivor_set_body_armor( armor );
			self [[ level.prevCallbackPlayerDamage ]]( eInflictor, eAttacker, 1, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, timeOffset );
			self.health++;
			return;
		}
	}

	self [[ level.prevCallbackPlayerDamage ]]( eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, timeOffset );
}

// Byte-for-byte copy of lethalbeats\survival\difficulty::difficulty_get_h6_burst_settings
// - ONLY change: Hard's windUpTime 0 -> AH6_HARD_WINDUP. Normal/Easy untouched.
bpg_h6_burst_settings_windup()
{
	settings = [];

	switch ( lethalbeats\survival\difficulty::difficulty_get_level() )
	{
		case DIFFICULTY_HARD:
			settings[ "fireTime" ] = 0.05;
			settings[ "minShots" ] = 80;
			settings[ "maxShots" ] = 80;
			settings[ "minPause" ] = 0.5;
			settings[ "maxPause" ] = 1;
			settings[ "windUpTime" ] = AH6_HARD_WINDUP;
			println( "[AH6DBG] h6_burst_settings called (HARD) - windUpTime=" + settings[ "windUpTime" ] );
			return settings;

		case DIFFICULTY_NORMAL:
			settings[ "fireTime" ] = 0.1;
			settings[ "minShots" ] = 40;
			settings[ "maxShots" ] = 80;
			settings[ "minPause" ] = 2;
			settings[ "maxPause" ] = 3;
			settings[ "windUpTime" ] = 1;
			return settings;

		default:
			settings[ "fireTime" ] = 0.15;
			settings[ "minShots" ] = 40;
			settings[ "maxShots" ] = 80;
			settings[ "minPause" ] = 2;
			settings[ "maxPause" ] = 3;
			settings[ "windUpTime" ] = 1.75;
			return settings;
	};
}
