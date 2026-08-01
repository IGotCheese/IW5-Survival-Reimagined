// bpg_survival_dogfix.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-16.
// User: "dogs dont attack; suicide dogs dont attack or blow up in your proximity."
// UPSTREAM (author-acknowledged, still broken in 3.1.5): dog attacks depend on the
// bot AI physically landing a MELEE hit — survivorhandler::onPlayerDamage then routes
// dog attackers into _dog::onDogPlayerDamage (bite/knockdown). When the bot AI jams
// (dogs "get stuck and behave strangely"), no melee ever lands -> dogs are harmless,
// and C4 dogs only ever explode on death (onBotKilled notify "detonate").
// FIX: a per-dog PROXIMITY BRAIN (no replaceFunc; additive watcher).
// v3 2026-07-16 — STOCK MW3 SURVIVAL BEHAVIOR (researched: CoD wiki Dog page,
// Steam Complete Spec-Ops Survival guide, GameFAQs):
//   - dogs "run fast towards you in an attempt to push you over" -> TACKLE ON
//     CONTACT (stock knockdown w/ the mod's melee-mash struggle), NOT after 3 bites;
//   - "dogs will not tackle the player until the armor is fully depleted" -> with
//     body armor up, a dog BITES (shellshock) and CHIPS ARMOR instead of tackling;
//   - C4 dogs fight exactly like regular dogs and "explode when killed - doing
//     splash damage" (timed, so the blast can land after death) -> the mod's
//     death-detonation is untouched; NO proximity-detonate (v1 mistake, removed).
// Delivery: both paths go through the MOD's OWN onDogPlayerDamage (its
// attackAmount==2 branch is the stock knockdown; ==0 is the bite) so anims,
// struggle, and state flags stay stock.
// AFK players (bpg_afk), downed players, and players already in a knockdown are
// never targeted (matches upstream v3.1.2 targeting rules + our !afk contract).
// Tune live: bpg_dog_bite_range 80 / bpg_dog_bite_cooldown 1500 / bpg_dog_bite_armor_dmg 50
//
// 2026-07-20 MAJOR SIMPLIFICATION (user: "you shouldn't have a bunch of code in with the
// dogs, you need to allow it to handle naturally"). Over several iterations this file grew
// its own PARALLEL release system (bpg_dog_death_release/bpg_dog_do_release/entity-guard
// replaceFuncs on the anim functions) to work around one broken stock guard. That parallel
// system then raced against stock's OWN release path whenever stock wasn't actually broken
// for a given case, which is what caused "still stuck / animation still broken" to survive
// an otherwise-correct-looking fix. Root cause was always ONE line: stock onDogDeath's
// `self endon("dog_melee")` can die long before the dog actually dies (any time the victim
// has ever melee-escaped a PREVIOUS knockdown from that bot's life), so its own release
// branch (`dog.victim playerStandUp(dog)`) sometimes just never runs. Removing only that one
// line lets stock's own release code — already correct, already doing the reground+flourish,
// already the sole entity-cleanup owner — run reliably every time, which is what let all of
// the custom parallel machinery below be deleted instead of extended further. The other real
// stock bug, player_show()'s broken attach order/tag (see bpg_player_show_fixed below), is
// fixed once at its source instead of being reimplemented at every call site.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

#include common_scripts\utility;
#include lethalbeats\survival\utility;
#include lethalbeats\player;

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	if ( getDvar( "bpg_dog_bite_range" ) == "" )
		setDvar( "bpg_dog_bite_range", "80" );
	if ( getDvar( "bpg_dog_bite_cooldown" ) == "" )
		setDvar( "bpg_dog_bite_cooldown", "1500" );
	if ( getDvar( "bpg_dog_bite_armor_dmg" ) == "" )
		setDvar( "bpg_dog_bite_armor_dmg", "50" );

	level thread bpg_dogfix_watcher();
	level thread bpg_dog_orphan_watch();

	replaceFunc( lethalbeats\survival\abilities\_dog::onDogDeath, ::bpg_onDogDeath_safe );
	replaceFunc( lethalbeats\survival\utility::player_show, ::bpg_player_show_fixed );
	replaceFunc( lethalbeats\survival\abilities\_dog::dogClear, ::bpg_dogClear_safe );
	replaceFunc( lethalbeats\survival\abilities\_dog::playerDogKnockdown, ::bpg_playerDogKnockdown_safe );
	replaceFunc( lethalbeats\survival\abilities\_dog::playerStandUp, ::bpg_playerStandUp_safe );
	replaceFunc( lethalbeats\survival\abilities\_dog::attackEffectMonitor, ::bpg_attackEffectMonitor_safe );
	replaceFunc( lethalbeats\survival\abilities\_dog::attackEffectLoop, ::bpg_attackEffectLoop_safe );
}

// 2026-07-20 ROOT-CAUSE FIX. Byte-for-byte copy of stock onDogDeath (_dog.gsc) with ONE
// line removed: `self endon("dog_melee")`. That guard is meant to stop this thread once the
// dog is gone for good, but "dog_melee" is also notified on a melee-ESCAPE from a PREVIOUS
// knockdown this same bot's life ever had — so on a bot whose victim has escaped once
// before, this whole thread (and the release logic inside it) was silently dead well before
// the bot actually died. Removing it is the entire fix: everything else, including calling
// stock's own playerStandUp() for the release (reground + flourish + entity cleanup, all
// still stock, all still correct), is unchanged.
// 2026-07-21 LIVE FIX: this function can run for several seconds in total (knockdown_end
// wait, the state-3 branch's own 0.5s wait, then dogClear's internal 6s wait on top) - if
// `dog` (self.dog, the script_model) gets deleted by something external anywhere in that
// window (most likely a fast bot respawn/recycle once the underlying bot is confirmed
// dead), every later touch throws "attempt to call a method on 'dead entity'". Confirmed
// live: scriptModelPlayAnim errors here + a delete error inside dogClear (see
// bpg_dogClear_safe below - that one was previously misdiagnosed as a dog.spot double-
// delete without ever reading dogClear's real source; corrected now). Fix: the same
// isDefined(x.origin) pattern already proven in this codebase (bpg_survival_botclearfix.gsc)
// before every touch - a deleted entity's handle still passes plain isDefined(), only a
// property read like .origin correctly returns undefined for one.
bpg_onDogDeath_safe()
{
	level endon( "game_ended" );
	self endon( "disconnect" );

	self waittill( "death" );
	waittillframeend;

	self allowJump( true );
	dog = self.dog;

	if ( !isDefined( dog ) || !isDefined( dog.origin ) )
		return;

	dog unlink();
	dog scriptModelPlayAnim( "german_shepherd_death_front" );   // DOG_PREFIX + DEATH from _dog.gsc

	if ( isDefined( dog.knockdownState ) )
	{
		if ( dog.knockdownState == 0 )
		{
			if ( isDefined( dog.victim ) && isDefined( dog.victim.origin ) )
				dog.victim unlink();
			if ( isDefined( dog.spot ) && isDefined( dog.spot.origin ) )
				dog.spot delete();
		}
		else if ( dog.knockdownState == 1 || dog.knockdownState == 2 )
		{
			dog waittill( "knockdown_end" );
			if ( isDefined( dog.origin ) && isDefined( dog.victim ) && isDefined( dog.victim.origin ) )
				dog.victim bpg_playerStandUp_safe( dog );
		}
		else if ( dog.knockdownState == 3 )
		{
			if ( isDefined( dog.victim ) && isDefined( dog.victim.origin ) )
				dog.victim notify( "dog_late", false );
			if ( isDefined( dog.body ) && isDefined( dog.body.origin ) )
				dog.body scriptModelPlayAnim( "player_3rd_dog_knockdown_saved" );
			if ( isDefined( dog.hands ) && isDefined( dog.hands.origin ) )
				dog.hands scriptModelPlayAnim( "player_view_dog_knockdown_saved" );
			wait 0.5;
			if ( isDefined( dog.origin ) && isDefined( dog.victim ) && isDefined( dog.victim.origin ) )
				dog.victim bpg_playerStandUp_safe( dog );
		}
	}

	if ( isDefined( dog.origin ) )
		dog bpg_dogClear_safe();
}

// 2026-07-21: stock dogClear() (_dog.gsc) guards self.hitBox/self.icon with isDefined
// before deleting them, but NOT its own final `self delete()` - which only runs after an
// unconditional 6-SECOND wait. Given onDogDeath's whole sequence can already run several
// seconds before even calling this, `dog` (self here) can easily be gone by the time that
// wait elapses, and the caller's own guard (isDefined(dog.origin) before calling dogClear)
// can never protect against a failure that happens INSIDE dogClear, after its own wait.
// This is the actual, previously-misdiagnosed cause of the "delete: dead entity in
// dogclear" error - not a dog.spot double-delete (dogClear never touches dog.spot at all;
// confirmed by reading the real source this time). Byte-for-byte copy otherwise.
bpg_dogClear_safe()
{
	if ( isDefined( self.hitBox ) )
		self.hitBox delete();
	if ( isDefined( self.icon ) )
		self.icon delete();
	wait 6;
	if ( isDefined( self ) && isDefined( self.origin ) )
		self delete();
}

// 2026-07-21 (user request, relayed from the map author LastDemon99's own diagnosis of a
// separate report: players ending up stuck inside walls/props after a dog-pin release).
// Stock playerStandUp (see bpg_playerStandUp_safe below) regrounds the player using the
// TACKLE ANIMATION's own math (dog.body's final position, ground-traced) - which depends
// on the attacking dog's position/angle at the moment of the attack, and can land inside
// geometry on plenty of maps. Fix: remember where the player was ACTUALLY standing right
// before the pin started (a location we know is walkable, since they were already moving
// through it) and restore that instead, once released. Byte-for-byte copy of stock
// playerDogKnockdown with exactly one line added: the origin capture, placed AFTER the two
// early-return guards (so a rejected duplicate call can't clobber a real in-progress
// knockdown's saved origin) and BEFORE anything else touches the player.
bpg_playerDogKnockdown_safe( dog )
{
	if ( self.dogKnockdown || isDefined( dog.knockdownState ) )
		return;
	if ( !isDefined( dog ) || !isDefined( dog.owner ) )
		return;

	self.bpg_dog_attack_origin = self.origin;

	self setStance( "stand" );
	waittillframeend;

	self.dogKnockdown = true;
	dog.owner disableWeapons();
	dog.owner freezeControls( true );
	dog unlink();

	self lethalbeats\player::player_disable_weapons();
	self lethalbeats\player::player_disable_usability();

	dog.spot = self lethalbeats\survival\abilities\_dog::spawnKnockdownSpot();

	forward = anglesToForward( dog.angles );
	dog.spot rotateTo( vectorToAngles( -forward ), 0.1 );
	dog moveTo( self.origin - ( forward * 30 ), 0.1 );
	dog.owner setOrigin( dog.origin );
	dog.knockdownState = 0;
	wait 0.15;

	if ( !isDefined( dog.spot ) )
		return;

	dog.hands = self lethalbeats\survival\abilities\_dog::spawnKnockdownHands( dog.spot );
	dog.body = self lethalbeats\survival\abilities\_dog::spawnKnockdownBody( dog.spot );

	self lethalbeats\survival\abilities\_dog::playKnockdownAnim( dog );

	self thread lethalbeats\survival\abilities\_dog::playerDogAttackLate( dog );
	self thread lethalbeats\survival\abilities\_dog::playerDogMeleeDeath( dog );
	self thread bpg_playerShowHintstring_safe();
}

// 2026-07-21: stock playerShowHintstring()/pulseEffect() (_dog.gsc) store the melee-escape
// hint HUD element on `self.hintString` - a field name ALSO used, independently, by the
// mod's generic trigger/interaction-hint system (lethalbeats\LB_Utility\trigger.gsc,
// lethalbeats\survival\utility.gsc) for completely unrelated prompts (pickups, doors, etc).
// Confirmed live: "attempt to call a method on a undefined instead of an object" at
// pulseEffect, called from playerShowHintstring. Root cause: if a player is mid-knockdown
// (pulseEffect looping every 0.35s reading self.hintString) and ALSO near/leaving any
// trigger that uses the generic system, that system's own cleanup does
// `self.hintString = undefined;` (both trigger.gsc and survival\utility.gsc do this
// explicitly) - clobbering the dog-hint's reference out from under the still-running loop.
// Not a dead-entity race like the others in this file; a genuine shared-field-name collision
// between two unrelated stock systems. Fix: byte-for-byte copies with the field renamed to
// a private one only this pair ever touches, eliminating the collision at its source -
// playerShowHintstring is only ever called from playerDogKnockdown (confirmed via grep), so
// no replaceFunc is needed here, just pointing our own knockdown thread at these instead.
bpg_playerShowHintstring_safe()
{
	self.bpg_dogHintString = lethalbeats\hud::hud_create_string( self, "^3[[{+melee_zoom}]]", "hudbig", 2 );
	self.bpg_dogHintString lethalbeats\hud::hud_set_point( "center", "center", 0, 0 );
	self.bpg_dogHintString.alpha = 1;
	self bpg_pulseEffect_safe();
	if ( isDefined( self.bpg_dogHintString ) )
		self.bpg_dogHintString lethalbeats\hud::hud_destroy();
	self.bpg_dogHintString = undefined;
}

bpg_pulseEffect_safe()
{
	self endon( "disconnect" );
	self endon( "dog_melee" );
	self endon( "dog_saved" );
	self endon( "dog_late" );

	interval = 0.35;
	duration = 2;
	elapsed = 0;

	for ( ;; )
	{
		if ( !isDefined( self.bpg_dogHintString ) )
			return;
		self.bpg_dogHintString lethalbeats\hud::hud_effect_font_pulse( self );
		elapsed += interval;
		wait interval;
	}
}

// 2026-07-21: release counterpart to bpg_playerDogKnockdown_safe above. Same stock logic
// (hands cleanup, spot flourish, weapons/usability re-enable, body/spot cleanup) but the
// reground step now prefers the pre-attack origin saved at knockdown start over the tackle
// animation's own computed position - see the comment on bpg_playerDogKnockdown_safe for
// why. Falls back to the original ground-traced logic only if no saved origin exists
// (shouldn't normally happen, since every release implies a prior knockdown start). Also
// tightened every entity touch to the isDefined(x.origin) pattern (same reasoning as
// bpg_onDogDeath_safe) since this now runs as a replaceFunc instead of being called
// directly - previously any dead-entity risk here was masked by never having been
// independently guarded.
bpg_playerStandUp_safe( dog )
{
	if ( isDefined( dog.hands ) && isDefined( dog.hands.origin ) )
		dog.hands delete();
	if ( !isDefined( dog.spot ) || !isDefined( dog.spot.origin ) )
		return;

	spot = dog.spot;
	forward = anglesToForward( spot.angles );

	spot rotatePitch( 45, 0.3 );
	spot moveTo( spot.origin + ( 0, 0, 60 ) - ( forward * 45 ), 0.3 );

	wait 0.3;

	if ( isDefined( self ) && isDefined( self.origin ) )
	{
		if ( isDefined( self.bpg_dog_attack_origin ) )
		{
			self setOrigin( self.bpg_dog_attack_origin );
			self.bpg_dog_attack_origin = undefined;
		}
		else if ( isDefined( dog.body ) && isDefined( dog.body.origin ) )
		{
			bodyOrigin = dog.body.origin;
			ground = getGroundPosition( bodyOrigin, 50 );
			if ( isDefined( ground ) )
				self setOrigin( ( bodyOrigin[ 0 ], bodyOrigin[ 1 ], ground[ 2 ] + 5 ) );
		}
		self setStance( "stand" );
		self lethalbeats\player::player_enable_weapons();
		self lethalbeats\player::player_enable_usability();
		self unlink();
		self.dogKnockdown = false;
		self lethalbeats\survival\utility::player_show();
	}

	dog.isAttacking1 = false;

	if ( isDefined( dog.body ) && isDefined( dog.body.origin ) )
	{
		if ( isDefined( dog.body.head ) && isDefined( dog.body.head.origin ) )
			dog.body.head delete();
		dog.body delete();
	}

	if ( isDefined( spot ) && isDefined( spot.origin ) )
		spot delete();
}

// 2026-07-20 ROOT-CAUSE FIX for "no head after a dog-pin release." The mod's own
// player_show() (lethalbeats\survival\utility.gsc) does `self attach(hideData["head"], "",
// true)` BEFORE `self setmodel(hideData["body"])` — attaching the head while the model is
// still "null_body" (set by the matching player_hide()), using an empty tag instead of the
// stock "tag_head" convention every other player-head attach in the base game uses. Fixed
// once here, at the source, instead of reimplemented at every call site (bpg_dog_freeplayer,
// !stuck) — every stock caller (playerStandUp, playerDogMeleeDeath) now gets the fix for
// free. Only the attach order/tag changed; the weapon-restore loop is untouched, and
// self.hideData is now cleared after use (neither the original nor our fix ever did that,
// which let a later, unrelated !stuck silently replay stale restore data).
// 2026-07-27: added the detachall(). The matching player_hide() does `detachall()` then
// attaches "null_head", but this function re-attached the real head WITHOUT clearing, so a
// player came out of every dog knockdown carrying BOTH null_head and their real head. A
// client DObj's bone count is the base model PLUS every attached model, and the engine hard
// -errors past 192 ("dobj for xmodel '%s' has more than %d bones", a fatal CLIENT Sys_Error).
// Reproduced twice on survival, naming a DIFFERENT player body each time
// (mp_body_delta_elite_assault_ab, then mp_body_gign_paris_assault at wave 8) - two different
// bodies rules out a single bad asset and points at accumulated attachments.
// ⚠️ This is the ONLY attach() onto a player anywhere in the codebase that was not preceded by
// a detachall(); utility.gsc:473 (hide), :493 (the mod's own show) and :754 (model setup) all
// clear first. The .iwd copy at :493 was patched earlier the same day but is INERT - the
// replaceFunc at the top of this file makes THIS function the live one, so the fix only counts
// here. Nothing is lost by clearing: player_hide() already detached everything at knockdown
// time, so the only thing detachall() removes here is the stray null_head.
bpg_player_show_fixed()
{
	// 2026-07-27 (same day, second pass): MANDATORY companion to the detachall() below.
	// A double release provably happens - console.log carries the stack
	// playerdogmeleedeath -> bpg_playerstandup_safe -> bpg_player_show_fixed. BEFORE the
	// detachall() was added, a second call was harmless: hideData was already undefined, so
	// setmodel/attach each threw a non-fatal GSC error and the player simply kept the model
	// the first call gave them. WITH the detachall() that changes character - detachall()
	// SUCCEEDS before the undefined deref throws, so the second call strips the head and then
	// dies before re-attaching it, leaving the player with a body and NO HEAD.
	// Returning early keeps the restore strictly idempotent.
	if ( !isDefined( self.hideData ) )
		return;

	hideData = self.hideData;

	self detachall();
	self setmodel( hideData[ "body" ] );
	self attach( hideData[ "head" ], "tag_head", true );

	for ( i = 0; i < 2; i++ )
	{
		if ( !isDefined( hideData[ "weaponData" ][ i ] ) )
			continue;
		weapon = hideData[ "weaponData" ][ i ][ 0 ];
		self player_give_weapon( weapon, false, false, true );
		self player_set_weapon_data( weapon, hideData[ "weaponData" ][ i ] );
		self player_set_ammo_data( weapon, hideData[ "ammoData" ][ i ] );
	}
	self.hideData = undefined;
}

// 2026-07-17: a dog knockdown pins the victim with playerLinkToAbsolute + freezeControls(true)
// + disableWeapons(). Stock's own release (onDogDeath -> playerStandUp, fixed above) now
// handles the normal "dog died mid-pin" case reliably, so this is just a generic last-resort
// backstop for anything else that could leave a player pinned (e.g. some other way a dog
// vanishes without a clean "death" notify). If the flag is still set 12s after we first saw
// it (a real knockdown resolves in ~5-8s), free the player automatically.
bpg_dog_orphan_watch()
{
	level endon( "game_ended" );

	for ( ;; )
	{
		wait 2;

		foreach ( p in level.players )
		{
			if ( !isDefined( p ) || p isTestClient() || !isAlive( p ) )
				continue;

			if ( !isDefined( p.dogKnockdown ) || !p.dogKnockdown )
			{
				p.bpg_kd_since = undefined;
				continue;
			}

			if ( !isDefined( p.bpg_kd_since ) )
			{
				p.bpg_kd_since = getTime();
				continue;
			}

			if ( getTime() - p.bpg_kd_since > 12000 )
			{
				p bpg_dog_freeplayer();
				p.bpg_kd_since = undefined;
				p iPrintLnBold( "^2Freed from a stuck dog takedown" );
			}
		}
	}
}

// Minimal last-resort undo for a knockdown pin (orphan watcher + !stuck only — the normal
// path is stock's own playerStandUp via the fixed onDogDeath above, which already does the
// proper reground+flourish). This is a plain, no-frills recovery: unlink, unfreeze, restore
// via the now-fixed stock player_show(), and a cheap reground so a last-resort rescue still
// doesn't leave someone floating or clipped.
bpg_dog_freeplayer()
{
	self.dogKnockdown = false;
	if ( self isLinked() )
		self unlink();
	self setStance( "stand" );
	self freezeControls( false );
	self enableWeapons();

	ground = getGroundPosition( self.origin, 50 );
	if ( isDefined( ground ) )
		self setOrigin( ( ground[ 0 ], ground[ 1 ], ground[ 2 ] + 5 ) );

	if ( isDefined( self.hideData ) )
		self lethalbeats\survival\utility::player_show();
}

bpg_dogfix_watcher()
{
	level endon( "game_ended" );

	for ( ;; )
	{
		level waittill( "connected", player );
		if ( player isTestClient() )
			player thread bpg_dogfix_on_spawn();
	}
}

bpg_dogfix_on_spawn()
{
	self endon( "disconnect" );
	level endon( "game_ended" );

	for ( ;; )
	{
		self waittill( "spawned_player" );
		wait 0.5; // botType + dog ability (self.dog model) apply after spawn

		if ( !isDefined( self.pers[ "team" ] ) || self.pers[ "team" ] != "axis" )
			continue;
		if ( !self bot_is_dog() )
			continue;

		self thread bpg_dog_brain();
	}
}

bpg_dog_brain()
{
	// idempotent per spawn: a re-fire kills the previous brain
	self notify( "bpg_dog_brain" );
	self endon( "bpg_dog_brain" );
	self endon( "disconnect" );
	self endon( "death" );
	level endon( "game_ended" );

	for ( ;; )
	{
		wait 0.25;

		if ( !isAlive( self ) )
			return;
		if ( !isDefined( self.dog ) )
			continue; // dog model not spawned yet

		// mid-knockdown sequence: let the stock flow play out
		if ( isDefined( self.dog.knockdownState ) )
			continue;

		// ALL dogs (incl. C4 dogs) attack the same; C4 explodes on death via the mod
		target = self bpg_dog_pick_target( getDvarFloat( "bpg_dog_bite_range" ) );
		if ( !isDefined( target ) )
			continue;

		// respect the mod's own attack state + our bite cooldown
		if ( isDefined( self.dog.isAttacking0 ) && self.dog.isAttacking0 )
			continue;
		if ( isDefined( self.dog.isAttacking1 ) && self.dog.isAttacking1 )
			continue;
		if ( isDefined( self.bpg_next_bite ) && getTime() < self.bpg_next_bite )
			continue;

		self.bpg_next_bite = getTime() + getDvarInt( "bpg_dog_bite_cooldown" );

		if ( isDefined( target.bodyArmor ) && target.bodyArmor > 0 )
		{
			// STOCK: no tackle while armor is up — bite (shellshock) + chip armor.
			// attackAmount=0 + victim undefined steers onDogPlayerDamage into its
			// bite branch (isAttacking0 anim), never the knockdown branch.
			self.dog.victim = undefined;
			self.dog.attackAmount = 0;
			self thread lethalbeats\survival\abilities\_dog::onDogPlayerDamage( target );

			chip = getDvarInt( "bpg_dog_bite_armor_dmg" );
			newarmor = target.bodyArmor - chip;
			if ( newarmor <= 0 )
				target survivor_take_body_armor();
			else
				target survivor_set_body_armor( newarmor );
		}
		else
		{
			// SERIALIZE knockdowns: the mod sets player.dogKnockdown only after a
			// waittillframeend, so two dogs on the same tick can BOTH pass its guard
			// and double-run the sequence (live 2026-07-16: linkto error spam in
			// spawnknockdownbody). One knockdown attempt per target per 3s.
			if ( isDefined( target.bpg_kd_lock ) && getTime() < target.bpg_kd_lock )
				continue;
			target.bpg_kd_lock = getTime() + 3000;

			// STOCK: "push you over" on contact — attackAmount=2 + victim undefined
			// steers onDogPlayerDamage straight into its knockdown branch (stock
			// tackle + melee-mash struggle; its own guards prevent double-tackles).
			self.dog.victim = undefined;
			self.dog.attackAmount = 2;
			self thread lethalbeats\survival\abilities\_dog::onDogPlayerDamage( target );
		}
	}
}

// nearest eligible human within range and line of sight; undefined if none
bpg_dog_pick_target( range )
{
	best = undefined;
	bestdist = range;

	foreach ( p in level.players )
	{
		if ( !isDefined( p ) || !isPlayer( p ) || p isTestClient() )
			continue;
		if ( !isDefined( p.team ) || p.team != "allies" )
			continue;
		if ( !isAlive( p ) )
			continue;
		if ( isDefined( p.dogKnockdown ) && p.dogKnockdown )
			continue;
		if ( isDefined( p.inLastStand ) && p.inLastStand )
			continue;
		if ( isDefined( p.bpg_afk ) && p.bpg_afk )
			continue;

		d = distance( self.origin, p.origin );
		if ( d > bestdist )
			continue;
		if ( !sightTracePassed( self.origin + ( 0, 0, 24 ), p.origin + ( 0, 0, 24 ), false, undefined ) )
			continue;

		best = p;
		bestdist = d;
	}

	return best;
}

// 2026-07-21: two more stock functions (_dog.gsc) that can touch a disconnected PLAYER,
// found via a fresh live error dump (not guessed) - a genuinely different failure mode than
// the script_model "dead entity" races fixed above: here `self` (the victim) disconnecting
// mid-knockdown is the trigger, not an entity delete.
//
// attackEffectMonitor() specifically WAKES on "disconnect" (one of its own wait conditions)
// then unconditionally calls `self setBlurForPlayer(...)` right after - guaranteed to fail
// every single time it wakes up FOR that exact reason. Deterministic stock bug, not a race.
//
// attackEffectLoop() already has `self endon("disconnect")`, but endon only takes effect at
// the thread's NEXT wait/waittill - if disconnect fires WHILE the thread is mid-iteration
// (between the two `wait speed` calls, running its batch of self-touching effect calls),
// those calls still execute against an already-disconnected player before the endon guard
// can interrupt anything. Confirmed live: setblurforplayer/shellshock/openmenu "dead entity"
// errors from this exact function. Fix: guard `self` (the established isDefined(self) &&
// isDefined(self.origin) pattern already used in bpg_playerStandUp_safe above) at the top of
// AND partway through each iteration - i.e. right after every `wait`, since that's the only
// point where a disconnect that happened mid-iteration can actually be observed. Also guards
// `spot` the same way (same reasoning as the other fixes in this file). Byte-for-byte stock
// otherwise.
bpg_attackEffectMonitor_safe()
{
	self waittill_any( "disconnect", "dog_melee", "dog_saved", "dog_late" );
	if ( isDefined( self ) && isDefined( self.origin ) )
		self setBlurForPlayer( 0, 0.05 );
}

bpg_attackEffectLoop_safe( spot, duration, intensityYaw )
{
	self endon( "disconnect" );
	self endon( "dog_melee" );
	self endon( "dog_saved" );
	self endon( "dog_late" );

	if ( !isDefined( spot ) || !isDefined( spot.origin ) )
		return;

	prevOrigin = spot.origin;
	prevAngles = spot.angles;
	speed = 0.1;
	cycleTime = speed * 2;
	iterations = int( duration / cycleTime );
	intensity = 3;

	for ( i = 0; i < iterations; i++ )
	{
		if ( !isDefined( self ) || !isDefined( self.origin ) || !isDefined( spot ) || !isDefined( spot.origin ) )
			return;

		self shellshock( "frag_grenade_mp", 0.35 );
		self openMenu( "blood_effect_center" );
		self openMenu( "blood_effect_right" );
		self openMenu( "blood_effect_left" );
		self setBlurForPlayer( 1, 0.25 );
		spot rotateYaw( randomFloatRange( -intensityYaw, intensityYaw ), speed );
		spot rotatePitch( randomFloatRange( -intensity, intensity ), speed );
		spot rotateRoll( randomFloatRange( -intensity, intensity ), speed );
		wait speed;

		if ( !isDefined( self ) || !isDefined( self.origin ) || !isDefined( spot ) || !isDefined( spot.origin ) )
			return;

		self setBlurForPlayer( 0, 0.25 );
		spot rotateTo( prevAngles, speed );
		spot moveTo( prevOrigin, speed );
		wait speed;
	}
}
