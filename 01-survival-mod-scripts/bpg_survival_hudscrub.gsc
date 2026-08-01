// bpg_survival_hudscrub.gsc — SURVIVAL SERVER ONLY (isolated storage).
// 2026-07-16, user: giant red shape glued to the view, moves with aim, survives
// vid_restart and map changes. Root cause: a sentry/GL-turret PLACEMENT HOLOGRAM
// (e.g. model "sentry_minigun_weak_obj_red") whose carry thread died (gettagorigin
// flood-era collateral) — the ghost model stays linked to the player, and the mod's
// state restore can re-arm the broken carry on later spawns. The flood itself is
// fixed (safe-bone patch); this cleans up stragglers: every 10s, if NO player is
// actively carrying a turret, delete any placement-hologram models. Placed sentries
// use different models and are never touched. ⚠️ NEVER copy to the live <MP-PORT> server.

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	level thread bpg_scrub_loop();
	level thread bpg_spawn_repair_watcher();
	level thread bpg_mapchange_repair();
}

// ── dog-knockdown aftermath repair (2026-07-16) ─────────────────────────────
// The mod's player_hide() (dog pounce) blanks the player's model + detachall,
// and by the author's own comment has NO restore except respawn. Several of the
// knockdown threads endon the dog-owner's death, so a bot dying mid-pounce
// orphans the sequence: blanked model (client "CG_CanSeePlayer: Couldn't find
// [j_head]" kicks, server bone errors), leaked link + view props. Repair every
// spawn: if hideData leaked in, restore the model, clear the state, unlink.
bpg_spawn_repair_watcher()
{
	level endon( "game_ended" );

	for ( ;; )
	{
		level waittill( "connected", player );
		if ( !isSubStr( player getGuid() + "", "bot" ) )
			player thread bpg_spawn_repair();
	}
}

bpg_spawn_repair()
{
	self endon( "disconnect" );
	level endon( "game_ended" );

	for ( ;; )
	{
		self waittill( "spawned_player" );
		wait 0.5;

		if ( isDefined( self.hideData ) )
		{
			if ( ( !isDefined( self.model ) || self.model == "" ) && isDefined( self.hideData[ "body" ] ) )
				self setModel( self.hideData[ "body" ] );
			self.hideData = undefined;
			self.dogKnockdown = false;
			self unlink();
			self iPrintLnBold( "^2Model state repaired" );
			println( "bpg_hudscrub: repaired leaked dog-knockdown state for " + self.name );
		}
	}
}

// 2026-07-22: bpg_spawn_repair_watcher only fires on a BRAND-NEW "connected" event —
// it never re-checks an already-connected player who survives a MAP CHANGE. If a dog
// knockdown got interrupted (dog killed mid-pounce) and the map changed before the
// leaked hideData was cleaned up, it carries into the next map untouched, causing
// OTHER clients to hit "CG_CanSeePlayer: Couldn't find [j_head]" and fail to load.
// Run the same repair once at map init for every player already on the level.
bpg_mapchange_repair()
{
	level endon( "game_ended" );

	wait 1;

	foreach ( player in level.players )
	{
		if ( isSubStr( player getGuid() + "", "bot" ) )
			continue;
		if ( isDefined( player.hideData ) )
		{
			if ( ( !isDefined( player.model ) || player.model == "" ) && isDefined( player.hideData[ "body" ] ) )
				player setModel( player.hideData[ "body" ] );
			player.hideData = undefined;
			player.dogKnockdown = false;
			player unlink();
			player iPrintLnBold( "^2Model state repaired" );
			println( "bpg_hudscrub: repaired leaked dog-knockdown state (map change) for " + player.name );
		}
	}
}

bpg_scrub_loop()
{
	level endon( "game_ended" );

	wait 5;

	// collect every placement-ghost model name the mod registered
	ghostModels = [];
	if ( isDefined( level.sentrysettings ) )
	{
		keys = getArrayKeys( level.sentrysettings );
		for ( i = 0; i < keys.size; i++ )
		{
			st = level.sentrysettings[ keys[ i ] ];
			if ( isDefined( st.modelplacement ) )
				ghostModels[ ghostModels.size ] = st.modelplacement;
			if ( isDefined( st.modelplacementfailed ) )
				ghostModels[ ghostModels.size ] = st.modelplacementfailed;
		}
	}
	if ( !ghostModels.size )
		return;

	for ( ;; )
	{
		wait 10;

		anyCarrying = false;
		foreach ( player in level.players )
		{
			if ( isDefined( player.iscarrying ) && player.iscarrying )
			{
				anyCarrying = true;
				break;
			}
		}
		if ( anyCarrying )
			continue;

		ents = getEntArray( "script_model", "classname" );
		foreach ( ent in ents )
		{
			if ( !isDefined( ent.model ) )
				continue;
			for ( m = 0; m < ghostModels.size; m++ )
			{
				if ( ent.model == ghostModels[ m ] )
				{
					println( "bpg_hudscrub: deleted stray placement hologram (" + ent.model + ")" );
					ent delete();
					break;
				}
			}
		}
	}
}
