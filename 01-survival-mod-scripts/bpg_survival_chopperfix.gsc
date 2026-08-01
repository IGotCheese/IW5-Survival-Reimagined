// bpg_survival_chopperfix.gsc — SURVIVAL SERVER ONLY (isolated storage).
// 2026-07-16: support-chopper (Pave Low) error FLOOD — hundreds of
//   "attempt to call a method on undefined" / "cannot cast undefined to bool"
//   at followplayer_dynamic in lethalbeats/survival/abilities/_chopper.gsc.
// Cause: the fast follow loop reads self.mgTurretLeft/Right getturrettarget(false)
//   and immediately calls player_is_valid_target() on the result. When a turret
//   has no target (getturrettarget -> undefined) or the turret itself is undefined
//   (setup failed), the method call hits `undefined` and errors EVERY 0.2s loop.
// Fix: replaceFunc followPlayer_Dynamic with a byte-for-byte copy of the mod's
//   function, adding only isDefined guards on the two turret-target read sites.
//   _chopper.gsc loads on every survival map (this server is always survival), so
//   the replaceFunc target resolves everywhere -> safe. Same #include + #define set
//   as the original, so every unqualified helper (survivors, sortByDistance,
//   player_is_valid_target, array_remove, waittill_any_timeout ...) resolves the
//   same way it does inside _chopper.gsc.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

#include maps\mp\_utility;
#include common_scripts\utility;
#include lethalbeats\array;
#include lethalbeats\survival\utility;

#define MIN_HELI_SEPARATION 1500
#define BLIND_SPOT_DOT_PRODUCT 0.95
#define AGGRESSIVE_RADIUS_MIN 700
#define AGGRESSIVE_RADIUS_MAX 1400
#define AGGRESSIVE_DECISION_TIME_MIN 2
#define AGGRESSIVE_DECISION_TIME_MAX 4

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( lethalbeats\survival\abilities\_chopper::followPlayer_Dynamic, ::followPlayer_Dynamic_safe );

	// 2026-07-17: error STORM on ported maps with no care-package collision brush
	// (mp_csgo_assault etc.). utility::level_wait_vehicle_limit parks a waiting
	// (hidden) vehicle enemy at level.airDropCrateCollision.origin — but that level
	// var is only set from a map's care_package brush, so on maps lacking one it's
	// undefined -> ".origin on undefined" + "setOrigin(undefined)" every chopper /
	// juggernaut / pavelow spawn (onbotspawn -> giveability -> level_wait_vehicle_limit).
	// Guard the move; the enemy is hidden while waiting, so skipping it is harmless.
	replaceFunc( lethalbeats\survival\utility::level_wait_vehicle_limit, ::level_wait_vehicle_limit_safe );

	// 2026-07-17: the little-bird DEATH crash flies the wreck to a bullet-traced spot via
	// setVehGoalPos. On maps with no air-node mesh that builtin errors every shoot-down
	// (and "goal" never fires), storming the log. Skip only the flight on no-node maps; the
	// far-away crash damage/fx are unchanged, so nothing else about the death changes.
	replaceFunc( lethalbeats\survival\abilities\_chopper::lbSurvivalDeathCrash, ::lbSurvivalDeathCrash_safe );
}

lbSurvivalDeathCrash_safe()
{
	level endon( "game_ended" );
	self endon( "gone" );
	self endon( "leaving" );

	self waittill( "death" );

	if ( isDefined( self.currentGoalPos ) )
		level.activeHeliGoals = array_remove( level.activeHeliGoals, self.currentGoalPos );

	self thread maps\mp\killstreaks\_helicopter::heli_spin( 180 );
	self notify( "crashing" );
	self clearLookAtEnt();

	yaw = self.angles[1];
	direction = self.origin + anglesToForward( ( 0, yaw + ( coinToss() ? 90 : -90 ), 0 ) ) * 1500;
	trace = bulletTrace( self.origin, direction - ( 0, 0, 2000 ), false, self );
	crashPos = trace["position"];

	// only navigate to the crash point when the map has an air-node system; otherwise let
	// it spin a beat and detonate where it is (chopper dies airborne, so this is safe).
	if ( isDefined( self.hasNodeSystem ) && self.hasNodeSystem )
	{
		self setVehGoalPos( crashPos );
		self Vehicle_SetSpeed( 100, 60 );
		self setTargetYaw( self.angles[1] + randomIntRange( 180, 220 ) );
		self waittill( "goal" );
	}
	else
		wait 1.5;

	earthquake( 0.75, 2.0, crashPos, 2000 );
	self radiusDamage( crashPos, 512, 100, 20, self, "MOD_EXPLOSIVE", "bomb_site_mp" );

	rot = randomfloat( 360 );
	explosionEffect = spawnFx( level._effect["bombexplosion"], crashPos + ( 0, 0, 50 ), ( 0, 0, 1 ), ( cos( rot ), sin( rot ), 0 ) );
	triggerFx( explosionEffect );

	self maps\mp\killstreaks\_helicopter_guard::lbExplode();
	explosionEffect delete();
}

level_wait_vehicle_limit_safe( stay )
{
	self hide();
	if ( !isDefined( stay ) && isDefined( level.airDropCrateCollision ) )
		self setOrigin( level.airDropCrateCollision.origin );
	level.vehicleWaiting[ level.vehicleWaiting.size ] = self;
	self waittill( "vehicle_release" );
}

followPlayer_Dynamic_safe()
{
	level endon("game_ended");
	self endon("death");

	self Vehicle_SetSpeed(self.followSpeed, 20, 20);
	self.timeForNextMove = gettime();

	for(;;)
	{
		// GUARDED: turrets or their targets can be undefined; never call a method on undefined.
		leftTarget = undefined;
		rightTarget = undefined;
		if (isDefined(self.mgTurretLeft))  leftTarget  = self.mgTurretLeft getturrettarget(false);
		if (isDefined(self.mgTurretRight)) rightTarget = self.mgTurretRight getturrettarget(false);

		if ((isDefined(leftTarget) && leftTarget player_is_valid_target()) || (isDefined(rightTarget) && rightTarget player_is_valid_target()))
        {
            self Vehicle_SetSpeed(0, 20, 20); // If a turret has a target, force slow down to "stabilize"
            self waittill_any_timeout(4.0, "chopper_done_shooting");  // waiting firing end
            self Vehicle_SetSpeed(self.followSpeed, 20, 20);
            self.timeForNextMove = gettime(); // force repositioning after shooting
        }

		survivors = survivors(true);
		if (!survivors.size)
		{
			wait 1;
			continue;
		}

		target = sortByDistance(survivors, self.origin)[0];

		is_in_blind_spot = false;
		vector_to_target = vectornormalize(target.origin - self.origin);
		dot = vectordot(vector_to_target, (0,0,-1));
		if (dot > BLIND_SPOT_DOT_PRODUCT)
			is_in_blind_spot = true;

		if (is_in_blind_spot || gettime() >= self.timeForNextMove)
		{
			if (isDefined(self.currentGoalPos))
			{
				level.activeHeliGoals = array_remove(level.activeHeliGoals, self.currentGoalPos);
				self.currentGoalPos = undefined;
			}

			focusPoint = target.origin + (self.focusOffsetX, self.focusOffsetY, 0);

			newGoalPos = undefined;
			for (i = 0; i < 10; i++)
			{
				altitude = self.flyHeight;
				radius = randomIntRange(AGGRESSIVE_RADIUS_MIN, AGGRESSIVE_RADIUS_MAX);

				if (is_in_blind_spot)
				{
					radius *= 1.25;
					self.attackSector = (self.attackSector + 1) % 4;
                    if (self.origin[2] > self.minFlyHeight + 100)
						altitude = max(self.origin[2] - 300, self.minFlyHeight);
				}

				angle = randomFloatRange(self.attackSector * 90, (self.attackSector * 90) + 90);
				offset = (Cos(angle) * radius, Sin(angle) * radius, 0);
				candidatePos = (focusPoint * (1,1,0)) + offset + (0,0,altitude);

				isTooClose = false;
				foreach (otherGoal in level.activeHeliGoals)
				{
					if (distanceSquared(candidatePos, otherGoal) < (MIN_HELI_SEPARATION * MIN_HELI_SEPARATION))
					{
						isTooClose = true;
						break;
					}
				}

				if (!isTooClose)
				{
					newGoalPos = candidatePos;
					break;
				}
			}

			if (!isDefined(newGoalPos))
			{
				offset = (Cos(randomint(360)) * AGGRESSIVE_RADIUS_MAX * 1.5, Sin(randomint(360)) * AGGRESSIVE_RADIUS_MAX * 1.5, 0);
				newGoalPos = (target.origin * (1,1,0)) + offset + (0,0,self.flyHeight);
			}

			self.currentGoalPos = newGoalPos;
			level.activeHeliGoals[level.activeHeliGoals.size] = self.currentGoalPos;
			self setVehGoalPos(self.currentGoalPos);

			self.timeForNextMove = gettime() + randomIntRange(AGGRESSIVE_DECISION_TIME_MIN, AGGRESSIVE_DECISION_TIME_MAX) * 1000;
		}

		// GUARDED: same undefined-turret/target protection as above.
		best_target = undefined;
		if (isDefined(self.mgTurretLeft)) best_target = self.mgTurretLeft getturrettarget(false);
		if (!isDefined(best_target) || !best_target player_is_valid_target())
			best_target = target;

		self ClearLookAtEnt();
		self SetLookAtEnt(best_target);

		wait 0.2;
	}
}
