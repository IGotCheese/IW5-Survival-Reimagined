// bpg_survival_triggerorphanfix.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-30.
//
// ✅ ACTIVE AND VERIFIED — status corrected 2026-08-01.
// This file IS loaded: plain .gsc, no .PENDING sibling, so Plutonium runs it. The header
// claimed "STAGED, NOT ACTIVE" for two days while it was live on the trigger hot path — worse
// than either state, because a reader would believe the fix was inert and either re-fix the
// same bug or "activate" a no-op.
// Verified 2026-08-01 on all four survival instances: ZERO trigger_is_touching /
// _trigger_link_to / triggerMainLoop errors in the live logs. The storm below is gone.
// (Originally staged pending a <SIDETEST-PORT> side-test that never happened; it reached production
// without one. The checklist at the bottom still applies if this is ever modified.)
//
// replaceFuncs two functions on the trigger hot path - every shop, armory, revive and
// objective interaction runs through these.
//
// Fixes the error storm that took survival <SURV-PORT-2> down on 2026-07-30 with FOUR players on it.
// 10,300 script runtime errors / 4.4 MB of console.log, no Sys_Error and no minidump - the
// server was simply drowned. Log preserved at C:\Ops\crash-logs\<SURV-PORT-2>-console-*.log.
// Error histogram from that log:
//     _triggermainloop        10287
//     pointinsphere            3962   <- trigger_is_touching
//     trigger_is_touching      3962
//     _isenableto              2364
//     survivor_trigger_filter  2364
// i.e. essentially 100% of it was this one bug, repeating every frame.
//
// ── ROOT CAUSE ───────────────────────────────────────────────────────────────────────────────
// lethalbeats\trigger::_trigger_link_to keeps a trigger glued to an entity:
//     for(;;) { self.origin = isDefined(offset) ? entity.origin + offset : entity.origin;
//               wait 0.02; }
// It endons "unlink" and "death" - but never checks that `entity` still EXISTS. When the linked
// entity is deleted, `entity.origin` is undefined, so the loop writes UNDEFINED into the
// trigger's own .origin and keeps doing so forever.
//
// The trigger is never removed from level.triggers either, because trigger_delete() is only
// called on the TRIGGER; here it was the OWNER that died. So _triggerMainLoop keeps iterating it
// every frame, for every player, and both consumers blow up on the undefined origin:
//     trigger_is_touching  -> collider::pointInSphere( center, self.origin, self.radius )
//                             -> distanceSquared( undefined, .. ) and 'undefined' vs 3600 (60^2)
//     survivor_trigger_filter (survival\utility.gsc:1520) -> distanceSquared( self.origin,
//                             trigger.origin ) -> 'undefined' vs 4225 (65^2)
// _triggerMainLoop's own guard is `if (!isDefined(trigger) || trigger.disabled) continue;` which
// only proves the ARRAY SLOT is populated - it says nothing about the trigger's fields being
// usable. A struct-backed trigger stays isDefined forever no matter how broken its contents are.
//
// This is the same failure family as the orphaned dropped weapons in
// bpg_survival_droppedweaponleak.gsc: something gets deleted, and the structure still tracking
// it is never cleaned up.
//
// ── THE FIX ──────────────────────────────────────────────────────────────────────────────────
// (1) ROOT CAUSE - _trigger_link_to stops and DELETES the trigger once its anchor is gone. A
//     trigger welded to a deleted entity has no meaning; deleting it both ends the error and
//     removes it from level.triggers, so it stops costing a slot and an iteration every frame.
//     Entities never come back from deleted in GSC, so there is no "temporarily undefined" case
//     to worry about - this cannot fire early.
// (2) CONTAINMENT - trigger_is_touching returns false when origin/radius are unusable instead of
//     calling into the collider with garbage. (1) should mean this never triggers; it exists so
//     that ANY future variant of this bug degrades to "that trigger does not respond" rather
//     than 10,000 errors a frame. Cheap insurance on a path that already proved it can kill a
//     server full of people.
//
// Everything is called FULLY QUALIFIED so this file needs no #include at all - an unresolved
// function in GSC is a compile-time failure that kills the whole file, and the fewer symbols
// this depends on resolving, the smaller that risk.
//
// NOT fixed here: survival\utility::survivor_trigger_filter dereferences trigger.origin too and
// lives in the mod. With (1) in place an orphaned trigger no longer exists for it to walk, so it
// should go quiet on its own. If it ever reappears in the logs alone, guard it separately rather
// than pre-emptively replacing more mod code than necessary.

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( lethalbeats\trigger::_trigger_link_to,     ::bpg_trigger_link_to_safe );
	replaceFunc( lethalbeats\trigger::trigger_is_touching,  ::bpg_trigger_is_touching_safe );
}

// (1) root cause. Byte-faithful copy of stock plus the anchor-alive check.
bpg_trigger_link_to_safe( entity, offset )
{
	self endon( "unlink" );
	self endon( "death" );

	for ( ;; )
	{
		// THE FIX. Stock dereferenced entity.origin unconditionally.
		if ( !isDefined( entity ) )
		{
			// removes us from level.triggers, disables us, and notifies "death"
			self lethalbeats\trigger::trigger_delete();
			return;
		}

		self.origin = isDefined( offset ) ? entity.origin + offset : entity.origin;
		wait 0.02;
	}
}

// (2) containment. Same logic as stock, but refuses to hand the collider an undefined origin.
bpg_trigger_is_touching_safe( player )
{
	if ( !isDefined( self.origin ) || !isDefined( self.radius ) )
		return false;

	if ( !isDefined( player ) )
		return false;

	if ( isDefined( self.height ) )
		return lethalbeats\collider::pointInCylinder( player maps\mp\_utility::getStanceCenter(), self.origin, self.radius, self.height );

	return lethalbeats\collider::pointInSphere( player maps\mp\_utility::getStanceCenter(), self.origin, self.radius );
}

// ── SIDE-TEST CHECKLIST (<SIDETEST-PORT>, never with the live authtoken) ────────────────────────────────
// Triggers are how the player touches almost everything, so test the INTERACTIONS, not just the
// absence of errors:
// 1. Buy stations / armories open and close normally, on more than one map.
// 2. Reviving a downed teammate still works (the "revive" tag has its own priority path through
//    survivor_trigger_filter).
// 3. Killstreak and airdrop crates can still be picked up - those are linked triggers, which is
//    exactly the code path being replaced.
// 4. Kill a crate/turret that owns a linked trigger and confirm: no error storm, and
//    level.triggers does NOT keep growing across waves.
// 5. Play several waves and confirm _triggermainloop errors stay at zero.
// Then drop .PENDING and sync to Survival2/3/4.
