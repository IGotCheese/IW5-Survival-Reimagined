// bpg_survival_remoteweaponfix.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-30.
//
// ✅ ACTIVE AND VERIFIED — status corrected 2026-08-01. It does NOT ship as .gsc.PENDING;
// it is a plain .gsc and Plutonium loads it. Verified: ZERO "switchtoweapon ... undefined"
// errors across all 4 survival instances. It replaces a
// STOCK function that Pave Low, Reaper and the bot fire-fix all call, so it gets a side-test on
// an isolated port before it goes anywhere near the live fleet. Activate by dropping .PENDING.
//
// Fixes, seen live on mp_raid from two different call paths:
//     in call to builtin method "switchtoweapon": cannot cast parameter 0 from undefined to string
//         at clearusingremote / remoteendride / handledeath        (_remotemortar - real player)
//         at clearusingremote / patch_missileeyes / _firefix       (_bot_utility  - a BOT)
//
// ── ROOT CAUSE ───────────────────────────────────────────────────────────────────────────────
// Stock maps\mp\_utility::clearusingremote:1740-1754 ends a remote killstreak with:
//     var_0 = self getcurrentweapon();
//     if ( var_0 == "none" || iskillstreakweapon( var_0 ) )
//         self switchtoweapon( common_scripts\utility::getlastweapon() );
// getlastweapon() is just `return self.saved_lastweapon` (common_scripts\utility.gsc:1492).
// That field is only ever written by maps\mp\gametypes\_weapons::updatesavedlastweapon
// (:2310-2337), a per-player thread started from _weapons.gsc:345 and seeded from
// self.currentweaponatspawn. Any entity that never ran that thread has saved_lastweapon
// undefined, and stock switches to it WITHOUT a guard.
//
// That is why the two stacks look unrelated but are the same bug: bots never run the thread at
// all, and a player coming off a remote killstreak can reach here before/after the thread's
// endon("faux_spawn") window. Both land on switchToWeapon(undefined).
//
// ── WHY THIS IS NOT COSMETIC ─────────────────────────────────────────────────────────────────
// The failed call is the one that hands the player their gun back. When it errors the player is
// left holding "none" or a spent killstreak weapon - the "glitched out" state players describe.
// So the guard is not just silencing a log line, it restores the weapon.
//
// ── SAFETY ───────────────────────────────────────────────────────────────────────────────────
// Body is a byte-faithful copy of stock with ONLY isDefined/validity guards added; every side
// effect stock performs (carryicon alpha, usingremote clear, _enableoffhandweapons,
// freezecontrolswrapper(0), the "stopped_using_remote" notify) is preserved in stock's order.
// Verified unclaimed before hooking: nothing in LB_Survival or any loose script replaceFuncs
// clearusingremote, so there is no init-order fight with the mod (mod init runs after loose,
// and would otherwise win - see the IW5 replaceFunc ordering note).
// Callers that depend on it: _pavelow.gsc:288/295/301, _reaper.gsc:219, globallogic.gsc:1684.

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( maps\mp\_utility::clearUsingRemote, ::bpg_clearusingremote_safe );
	replaceFunc( maps\mp\killstreaks\_remotemortar::remoteEndRide, ::bpg_remoteendride_safe );
}

// ── SECOND CALL SITE, found 2026-07-30 from a LIVE play session ──────────────────────────────
// After the clearUsingRemote guard shipped, the error came back on <SURV-PORT-4> with a SHORTER stack:
//     before:  switchtoweapon <- clearusingremote <- remoteendride <- handledeath
//     after:   switchtoweapon <-                     remoteendride <- handledeath
// The vanished clearusingremote frame proves the first guard works. But _remotemortar.gsc calls
// switchToWeapon TWICE - once inside clearUsingRemote (:328) and once DIRECTLY at :333 - and
// both feed it the same unguarded getLastWeapon(). Patching the shared helper closed only half.
// LESSON: when a builtin fails through a helper, check the caller for direct duplicate calls.
// Body is stock _remotemortar.gsc:310-339 verbatim; the ONLY change is the guarded switch.
bpg_remoteendride_safe( owner )
{
	if ( !maps\mp\_utility::isUsingRemote() )
		return;

	if ( isDefined( owner ) )
		owner notify( "helicopter_done" );

	self thermalVisionOff();
	self thermalVisionFOFOverlayOff();
	self visionSetThermalForPlayer( game[ "thermal_vision" ], 0 );

	if ( isDefined( level.nukeDetonated ) )
		self visionSetNakedForPlayer( level.nukeVisionSet, 0 );
	else
		self visionSetNakedForPlayer( "", 0 );

	self unlink();
	self maps\mp\_utility::clearUsingRemote();

	if ( getDvarInt( "camera_thirdPerson" ) )
		maps\mp\_utility::setThirdPersonDOF( 1 );

	// THE FIX - stock switched here unguarded, exactly as clearUsingRemote did.
	want = common_scripts\utility::getLastWeapon();
	if ( !isDefined( want ) || want == "none" || !( self hasWeapon( want ) ) )
		want = self bpg_first_real_primary();
	if ( isDefined( want ) )
		self switchToWeapon( want );

	mortar = maps\mp\killstreaks\_killstreaks::getKillstreakWeapon( "remote_mortar" );
	self takeWeapon( mortar );
	self takeWeapon( "mortar_remote_zoom_mp" );
	self takeWeapon( "mortar_remote_mp" );
	common_scripts\utility::_enableWeaponSwitch();
}

bpg_clearusingremote_safe()
{
	if ( isDefined( self.carryicon ) )
		self.carryicon.alpha = 1;

	self.usingremote = undefined;
	common_scripts\utility::_enableOffhandWeapons();

	cur = self getCurrentWeapon();

	if ( cur == "none" || maps\mp\_utility::isKillstreakWeapon( cur ) )
	{
		want = common_scripts\utility::getLastWeapon();

		// THE FIX. Stock switches to `want` unguarded here.
		if ( !isDefined( want ) || want == "none" || !( self hasWeapon( want ) ) )
			want = self bpg_first_real_primary();

		// Still nothing usable: leave the current weapon alone rather than switch to junk.
		// Stock would have errored; doing nothing is strictly closer to correct.
		if ( isDefined( want ) )
			self switchToWeapon( want );
	}

	maps\mp\_utility::freezeControlsWrapper( 0 );
	self notify( "stopped_using_remote" );
}

// First primary the player actually holds that is not itself a killstreak weapon - switching
// back to a killstreak would re-enter the state clearusingremote exists to leave.
bpg_first_real_primary()
{
	foreach ( w in self getWeaponsListPrimaries() )
	{
		if ( !isDefined( w ) || w == "none" )
			continue;

		if ( maps\mp\_utility::isKillstreakWeapon( w ) )
			continue;

		return w;
	}

	return undefined;
}
