// bpg_survival_riotshieldfix.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-20.
// Live errors: "in call to builtin method moveshieldmodel" / "detachshieldmodel" at function
// trackriotshield in maps/mp/gametypes/_class.gsc.
// ROOT CAUSE: lethalbeats\survival\utility::player_hide() (called on EVERY dog knockdown) does
// self.player_take_all_weapons(true) to strip weapons for the pin animation, which fires a
// "weapon_change" notify. trackriotshield()'s infinite waittill("weapon_change") loop catches
// that strip-event and calls self hasweapon("riotshield_mp") to decide whether to move or detach
// the shield model — but at that exact instant the weapon WAS JUST STRIPPED, so hasweapon() reads
// false even for a player who still logically owns a shield, driving the mod's own
// hasriotshield/hasriotshieldequipped bookkeeping out of sync with what's actually attached
// in-engine. The next real moveshieldmodel/detachshieldmodel call (on restore, or a later real
// weapon switch) then fails against state that no longer matches.
// FIX: skip shield-state handling entirely while self.dogKnockdown is true (the same, already-
// established signal every other dog-related fix in this project uses for "player is currently
// pinned/hidden"). bpg_dog_freeplayer() clears dogKnockdown to false BEFORE calling player_show(),
// so by the time weapons are actually restored the flag is already clear and the real restore
// event is handled normally, with the pre-hide hasriotshield/hasriotshieldequipped flags untouched
// (never corrupted) — exactly as if the strip/restore cycle never happened.
// ⚠️ NEVER copy to the live <MP-PORT> server (self.dogKnockdown only exists on survival).

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( maps\mp\gametypes\_class::trackriotshield, ::bpg_trackriotshield );
}

// 2026-07-27 (task #67): dedup guard for every shield attach in this file.
// WHY: the engine does NOT dedupe attachments — attachshieldmodel() called twice for the same
// tag leaves TWO weapon_riot_shield_mp models on the player's DObj. A DObj's bone count is the
// base model plus EVERY attached model, and the client hard-errors past 192 with
// "dobj for xmodel '%s' has more than 192 bones". At 4 bones each
// a shield leak is slow, but unlike the null_head case it is genuinely UNBOUNDED.
// The leak path: a failing detachshieldmodel (the documented error family this file was written
// for) sets hasriotshield = 0 while the model stays attached, so the next attach adds a second.
// ⚠️ WHY THIS IS A SURVIVAL-SPECIFIC BUG EVEN THOUGH STOCK HAS THE SAME CODE: stock's own
// trackRiotShield (_class.gsc:1334) also calls attachshieldmodel raw, and the guarded helpers
// tryAttach/tryDetach (_class.gsc:1404/1424) have ZERO callers anywhere in the raw-file tree —
// they are dead code. Stock gets away with it because _detachAll() (_class.gsc:1212, the only
// thing that ever clears the attach list) runs from spawnPlayer, and stock players respawn
// constantly. SURVIVORS ARE REVIVED, NOT RESPAWNED, so _detachAll() never runs and a leak
// persists for the player's entire life.
// Reimplemented locally instead of calling _class::tryAttach directly, precisely because that
// function is never called by anything shipped — relying on unreferenced stock code to be
// linked at runtime is the kind of assumption that produces a silent no-op.
// Per-TAG dedup (stock's exact semantics) is deliberate: it still allows the legitimate
// two-shield case below (one on tag_weapon_left, one on tag_shield_back) while capping the
// total at 2 instead of letting it grow without bound.
bpg_tryattachshield( tag )
{
	attachSize = self getattachsize();

	for ( i = 0; i < attachSize; i++ )
	{
		if ( self getattachtagname( i ) == tag && self getattachmodelname( i ) == "weapon_riot_shield_mp" )
			return;
	}

	self attachshieldmodel( "weapon_riot_shield_mp", tag );
}

bpg_trackriotshield()
{
	self endon( "death" );
	self endon( "disconnect" );
	self endon( "faux_spawn" );
	self.hasriotshield = self hasweapon( "riotshield_mp" );
	self.hasriotshieldequipped = self.currentweaponatspawn == "riotshield_mp";
	self thread maps\mp\gametypes\_class::watchoffhanduse();

	if ( self.hasriotshield )
	{
		if ( self.primaryweapon == "riotshield_mp" && self.secondaryweapon == "riotshield_mp" )
		{
			self bpg_tryattachshield( "tag_weapon_left" );
			self bpg_tryattachshield( "tag_shield_back" );
		}
		else if ( self.hasriotshieldequipped )
			self bpg_tryattachshield( "tag_weapon_left" );
		else
			self bpg_tryattachshield( "tag_shield_back" );
	}

	for ( ;; )
	{
		self waittill( "weapon_change", newWeapon );

		// skip entirely while pinned in a dog knockdown — see header comment.
		if ( isDefined( self.dogKnockdown ) && self.dogKnockdown )
			continue;

		if ( newWeapon == "riotshield_mp" || newWeapon == "iw5_riotshieldjugg_mp" )
		{
			if ( self.hasriotshieldequipped )
				continue;

			if ( self.primaryweapon == newWeapon && self.secondaryweapon == newWeapon )
				continue;
			else if ( self.hasriotshield )
				self moveshieldmodel( "weapon_riot_shield_mp", "tag_shield_back", "tag_weapon_left" );
			else
				self bpg_tryattachshield( "tag_weapon_left" );

			self.hasriotshield = 1;
			self.hasriotshieldequipped = 1;
			continue;
		}

		if ( self ismantling() && newWeapon == "none" )
			continue;

		if ( self.hasriotshieldequipped )
		{
			self.hasriotshield = self hasweapon( "riotshield_mp" ) || self hasweapon( "iw5_riotshieldjugg_mp" );

			if ( self.hasriotshield )
				self moveshieldmodel( "weapon_riot_shield_mp", "tag_weapon_left", "tag_shield_back" );
			else
				self detachshieldmodel( "weapon_riot_shield_mp", "tag_weapon_left" );

			self.hasriotshieldequipped = 0;
			continue;
		}

		if ( self.hasriotshield )
		{
			if ( !self hasweapon( "riotshield_mp" ) && !self hasweapon( "iw5_riotshieldjugg_mp" ) )
			{
				self detachshieldmodel( "weapon_riot_shield_mp", "tag_shield_back" );
				self.hasriotshield = 0;
			}
		}
	}
}
