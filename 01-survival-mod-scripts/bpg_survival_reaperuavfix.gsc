// bpg_survival_reaperuavfix.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-19.
// User: "reapers and uavs dont register bullet damage" + live log confirms two SEPARATE,
// unrelated bugs already present in the compiled mod (LB_Survival.iwd), not introduced by us:
//
// (1) REAPER: lethalbeats\Survival\abilities\_reaper.gsc's _remotefiring() computes
//     `wantsToFire = self attackbuttonpressed() || isBotRemoteController;` unconditionally.
//     For a BOT-controlled reaper (isBotRemoteController=true), attackbuttonpressed() is called
//     anyway - live log confirms it returns UNDEFINED for a bot entity (no real input stream),
//     and GSC's || operator casts its LEFT operand to bool before short-circuiting, so this
//     throws "cannot cast undefined to bool" on EVERY loop iteration (0.05s), forever - the fire
//     branch is never reached, so a bot-piloted reaper NEVER actually fires. This directly
//     explains "reapers don't damage/register" - the reaper's own damage-taking logic
//     (_handleDamage) is fine; the reaper simply never fires its missile in the first place.
//
// (2) UAV: lethalbeats\Survival\killstreaks\_uav.gsc's _damageTracker(isCounterUAV, isAdvanced),
//     for the persistent radar UAVs launched at init (isCounterUAV=false - by design these are
//     meant to be a toggle-only radar mechanism, not a destroyable killstreak), returns early
//     WITHOUT ever setting self.damagetaken/self.maxhealth. The un-replaced STOCK launchUAV
//     (maps/mp/killstreaks/_uav.gsc) still unconditionally reads `if (var_5.damagetaken <
//     var_5.maxhealth)` once the UAV's lifetime ends - an undefined<undefined comparison,
//     matching the live "OP_less"/"cannot cast undefined to bool" errors (fired once per UAV
//     relaunch, i.e. roughly once per map change - matches the log's clustered-not-continuous
//     pattern). Fix is conservative: initialize the two fields so the stock comparison doesn't
//     error, WITHOUT making the radar UAV destructible by gunfire (that's the mod's existing
//     design - self.health=999999-style "can't actually die" pattern already used elsewhere in
//     this same mod for undestroyable entities, e.g. _reaper.gsc's self.health = 999999).
//
// Both replaced functions are byte-for-byte copies of the ORIGINAL mod functions (confirmed via
// public decompile, github.com/SkyN9ne/Plutonium-IW5-GSC) with only the specific fix line(s)
// added - per project convention, verified against real source rather than assumption.
//
// 2026-07-19 REPLACEFUNC-CONFLICT NOTE (see gsc-code-quality-practices memory): _reaper.gsc's own
// init() already replaceFuncs the STOCK target (_remotemortar::remoteFiring); _uav.gsc's own
// init() already replaceFuncs the STOCK target (_uav::damageTracker). Per the established
// "mod beats loose" ordering finding, a loose script CANNOT win a second replaceFunc race against
// those same stock targets. Instead this file replaceFuncs the MOD's OWN internal functions
// directly (lethalbeats\Survival\abilities\_reaper::_remotefiring and
// lethalbeats\Survival\killstreaks\_uav::_damageTracker) - nothing else claims those exact
// symbols, so no ordering conflict applies.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( lethalbeats\Survival\abilities\_reaper::_remotefiring, ::bpg_reaper_remotefiring_fixed );
	replaceFunc( lethalbeats\Survival\killstreaks\_uav::_damageTracker, ::bpg_uav_damagetracker_fixed );
}

bpg_reaper_remotefiring_fixed( remote )
{
	level endon( "game_ended" );
	self endon( "disconnect" );
	remote endon( "remote_done" );
	remote endon( "death" );

	isBotRemoteController = ( isDefined( self.isHuman ) && !self.isHuman );
	reaperSettings = lethalbeats\survival\difficulty::difficulty_get_reaper_burst_settings();

	if ( isBotRemoteController )
	{
		ammo = undefined;
		waitTime = reaperSettings[ "fireTime" ] * 1000;
		windUpTime = reaperSettings[ "windUpTime" ] * 1000;
		botWasVisibleLastTick = false;
		botWindUpUntil = 0;
		botTargetId = -1;
	}
	else
	{
		ammo = 14;
		waitTime = 2200;
		windUpTime = 0;
	}

	curTime = getTime();
	lastFireTime = curTime - waitTime;
	self.firingreaper = 0;

	for ( ;; )
	{
		curTime = getTime();

		// 2026-07-19 FIX: attackbuttonpressed() returns undefined for a bot entity (no real
		// input stream) - GSC's || casts its left operand to bool BEFORE short-circuiting, so
		// calling it unconditionally threw "cannot cast undefined to bool" every 0.05s for a
		// bot-controlled reaper, forever preventing it from ever reaching the fire branch below.
		if ( isBotRemoteController )
			wantsToFire = true;
		else
			wantsToFire = self attackbuttonpressed();

		if ( wantsToFire && curTime - lastFireTime >= waitTime )
		{
			if ( !isDefined( remote ) || !isDefined( remote.targetent ) )
			{
				wait 0.05;
				continue;
			}

			targetPos = remote.targetent.origin;
			missileTargetEnt = remote.targetent;
			if ( isBotRemoteController )
			{
				botTargetEnt = self lethalbeats\Survival\abilities\_reaper::_getBotRemoteTargetEnt( remote );
				if ( !isDefined( botTargetEnt ) )
				{
					botWasVisibleLastTick = false;
					botTargetId = -1;
					botWindUpUntil = 0;
					wait 0.05;
					continue;
				}

				currentTargetId = botTargetEnt getEntityNumber();
				if ( !botWasVisibleLastTick || botTargetId != currentTargetId )
				{
					botWasVisibleLastTick = true;
					botTargetId = currentTargetId;
					botWindUpUntil = curTime + windUpTime;
				}

				if ( curTime < botWindUpUntil )
				{
					wait 0.05;
					continue;
				}

				targetPos = botTargetEnt getTagOrigin( "j_spineupper" );
				missileTargetEnt = botTargetEnt;
				remote.targetent.origin = targetPos;
				triggerfx( remote.targetent );
			}

			if ( isDefined( ammo ) )
			{
				ammo--;
				self setClientDvar( "ui_reaper_ammoCount", ammo );
			}

			lastFireTime = curTime;
			self.firingreaper = 1;
			self playLocalSound( "reaper_fire" );
			self playRumbleOnEntity( "damage_heavy" );
			origin = self getEye();
			forward = anglesToForward( self getPlayerAngles() );
			right = anglesToRight( self getPlayerAngles() );
			offset = origin + forward * 100 + right * -100;
			missile = magicBullet( "remote_mortar_missile_mp", offset, targetPos, self );
			earthquake( 0.3, 0.5, origin, 256 );
			missile missile_setTargetEnt( missileTargetEnt );
			missile missile_setFlightModeDirect();
			missile thread maps\mp\killstreaks\_remotemortar::remotemissiledistance( remote );
			missile thread maps\mp\killstreaks\_remotemortar::remotemissilelife( remote );
			missile waittill( "death" );
			self setClientDvar( "ui_reaper_targetDistance", -1 );
			self.firingreaper = 0;
			if ( isDefined( ammo ) && ammo == 0 )
				break;
		}
		else
			wait 0.05;
	}

	self notify( "removed_reaper_ammo" );
	maps\mp\killstreaks\_remotemortar::remoteendride( remote );
	remote thread maps\mp\killstreaks\_remotemortar::remoteleave();
}

bpg_uav_damagetracker_fixed( isCounterUAV, isAdvanced )
{
	level endon( "game_ended" );

	if ( !isCounterUAV )
	{
		// 2026-07-19 FIX: the un-replaced stock launchUAV unconditionally reads
		// self.damagetaken < self.maxhealth once this UAV's lifetime ends, regardless of type.
		// The original code never set these for non-counter UAVs, so that comparison was
		// undefined<undefined -> "cannot cast undefined to bool"/"OP_less" runtime error once
		// per UAV relaunch. Initializing to a value gunfire can never reach preserves the
		// existing "radar UAVs aren't destructible by bullets" design while killing the error -
		// same "self.health = 999999"-style pattern this mod already uses elsewhere for
		// intentionally-undestroyable entities (e.g. _reaper.gsc's _handleDamage).
		self.damagetaken = 0;
		self.maxhealth = 999999;

		level endon( "game_ended" );
		level waittill( "disable_uav" );
		self notify( "death" );
		return;
	}

	self setCanDamage( 1 );
	self.health = 999999;
	self.maxhealth = lethalbeats\Survival\killstreaks\_uav::getBotData( 14 ); // HEALTH column, matches #define HEALTH 14
	self.damagetaken = 0;

	for ( ;; )
	{
		self waittill( "damage", damage, attacker, direction_vec, point, meansOfDeath, modelName, tagName, partName, iDFlags, weapon );

		if ( !isPlayer( attacker ) )
		{
			if ( !isDefined( self ) )
				return;
		}
		else
		{
			if ( isDefined( iDFlags ) && iDFlags & level.idflags_penetration )
				self.wasdamagedfrombulletpenetration = 1;

			self.wasdamaged = 1;
			modifiedDamage = damage;

			if ( isPlayer( attacker ) )
			{
				attacker maps\mp\gametypes\_damagefeedback::updateDamageFeedback( "" );
				if ( meansOfDeath == "MOD_RIFLE_BULLET" || meansOfDeath == "MOD_PISTOL_BULLET" )
				{
					if ( attacker lethalbeats\player::player_has_perk( "specialty_bulletpenetration" ) )
						modifiedDamage += damage * level.armorpiercingmod;
				}
			}

			if ( isDefined( weapon ) )
			{
				switch ( weapon )
				{
					case "stinger_mp":
					case "javelin_mp":
						self.largeprojectiledamage = 1;
						modifiedDamage = self.maxhealth + 1;
						break;
					case "sam_projectile_mp":
						self.largeprojectiledamage = 1;
						mult = 0.25;

						if ( isAdvanced )
							mult = 0.15;

						modifiedDamage = self.maxhealth * mult;
						break;
				}
			}

			self.damagetaken += modifiedDamage;
			if ( self.damagetaken >= self.maxhealth )
			{
				if ( isPlayer( attacker ) && ( !isDefined( self.owner ) || attacker != self.owner ) )
				{
					self hide();
					var_14 = anglesToRight( self.angles ) * 200;
					playFx( level.uav_fx[ "explode" ], self.origin, var_14 );

					if ( isDefined( self.uavtype ) && self.uavtype == "remote_mortar" )
						thread maps\mp\_utility::teamPlayerCardSplash( "callout_destroyed_remote_mortar", attacker );
					else if ( isCounterUAV )
						thread maps\mp\_utility::teamPlayerCardSplash( "callout_destroyed_counter_uav", attacker );
					else
						thread maps\mp\_utility::teamPlayerCardSplash( "callout_destroyed_uav", attacker );

					thread maps\mp\gametypes\_missions::vehicleKilled( self.owner, self, undefined, attacker, damage, meansOfDeath, weapon );
					attacker thread maps\mp\gametypes\_rank::giveRankXP( "kill", 50, weapon, meansOfDeath );
					attacker notify( "destroyed_killstreak" );

					if ( isDefined( self.uavremotemarkedby ) && self.uavremotemarkedby != attacker )
						self.uavremotemarkedby thread maps\mp\killstreaks\_remoteuav::remoteuav_processtaggedassist();

					attacker lethalbeats\survival\utility::survivor_give_score( lethalbeats\Survival\killstreaks\_uav::getBotData( 16 ) ); // PRICE column, matches #define PRICE 16
				}

				self notify( "death" );
				level.radarStrength = lethalbeats\survival\utility::bots( undefined, true ).size ? 2 : 0;
				lethalbeats\player::players_play_sound( "emp_activate", "allies" );
				lethalbeats\player::players_play_sound( "US_1mc_use_uav", "allies" );
				return;
			}
		}
	}
}
