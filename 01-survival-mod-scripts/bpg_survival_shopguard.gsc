// bpg_survival_shopguard.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-24.
// User: "if you are in a buy station and you get attacked while in the buy station you
// cant get out of the buy station and sometimes you loose your guns"
//
// ROOT CAUSE (read from the deployed mod, not guessed):
// The shop is only ever closed on TWO events, both in
// lethalbeats/Survival/survivorHandler.gsc:
//     onPlayerKilled()     -> if (isDefined(self.currMenu)) dynamic_shop::closeShop();
//     onPlayerLastStand()  -> same
// **A dog knockdown is neither of those.** You are not killed and not downed - you are
// pinned. So when a dog hits you mid-shop, nothing closes the menu, while the knockdown
// (lethalbeats/Survival/abilities/_dog.gsc) runs:
//     _dog.gsc:372  dog.owner disableWeapons();
//     _dog.gsc:373  dog.owner freezeControls(true);
//     _dog.gsc:318  self lethalbeats\survival\utility::player_hide();
// -> menu still up + controls frozen  = "can't get out of the buy station"
// -> player_hide() strips every weapon into self.hideData for a later player_show()
//    restore = "sometimes you lose your guns" when that restore races or never runs.
//
// SECOND, RELATED FAULT (fixed here too): the shop watcher loop in survivorHandler
// (the `waittill("trigger_use")` loop, ~line 520) carries `self endon("death")`, and it
// is the ONLY thing that clears `self.currMenu` at the end of a shop session. Die with
// the shop open and that thread is killed before the clear, leaving currMenu stale
// forever. Its own guard is `if (isDefined(self.currMenu)) continue;` - so a stale value
// makes every future buy-station use silently do nothing until the map changes.
//
// WHY A SEPARATE WATCHER instead of patching the dog or the shop:
// the user has a standing "do not change anything at all with dogs" rule, and the mod
// author has (fairly) criticised scattering patches through his code. This file touches
// NEITHER: it only reads state and calls the mod's own public closeShop(). It is a
// safety net, not a behaviour change - if the mod ever closes the shop correctly on its
// own, this never fires. Nothing here modifies _dog.gsc, bpg_survival_dogfix.gsc, or
// dynamic_shop.gsc.
//
// ⚠️ Cannot be behaviourally verified headlessly (needs a real player pinned by a real
// dog while the shop is open) - compile/static-checked only. Ask for a live retest.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

#define POLL 0.25
// openShop() sets currMenu slightly BEFORE the shop struct exists (it waits 0.07s
// internally), so a brief currMenu-without-shop window is legitimate. Only treat it as
// stale after this many consecutive polls (~2s) to avoid closing a shop that is opening.
#define STALE_POLLS 8

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	level thread bpg_shopguard_watch();
}

bpg_shopguard_watch()
{
	level endon( "game_ended" );

	for ( ;; )
	{
		level waittill( "connected", player );
		if ( !isSubStr( player getGuid() + "", "bot" ) )
			player thread bpg_shopguard_player();
	}
}

bpg_shopguard_player()
{
	self endon( "disconnect" );
	level endon( "game_ended" );

	staleCount = 0;

	for ( ;; )
	{
		wait POLL;

		if ( !isDefined( self ) || !isDefined( self.currMenu ) )
		{
			staleCount = 0;
			continue;
		}

		// (1) THE REPORTED BUG: pinned by a dog with the shop open. Nothing in the mod
		// closes it for a knockdown, so release the menu ourselves. The knockdown's own
		// weapon/control restore then proceeds normally.
		if ( isDefined( self.dogKnockdown ) && self.dogKnockdown )
		{
			self bpg_shopguard_force_close();
			staleCount = 0;
			continue;
		}

		// (2) dead or downed but still flagged as in-menu. The mod usually handles this,
		// but its handlers are conditional, so catch whatever slips through.
		if ( !isAlive( self ) )
		{
			self bpg_shopguard_force_close();
			staleCount = 0;
			continue;
		}

		// (3) stale currMenu with no shop behind it (the endon("death") leak above).
		// Clearing it is what makes the buy station usable again.
		if ( !( self lethalbeats\dynamicmenus\dynamic_shop::isShopOpen() ) )
		{
			staleCount++;
			if ( staleCount >= STALE_POLLS )
			{
				self.currMenu = undefined;
				staleCount = 0;
			}
			continue;
		}

		staleCount = 0;
	}
}

// closeShop() also resets self.isMenuBusy, which is the flag that gates ALL menu input
// (dynamic_shop::onMenuResponse early-returns while it is true) - so this is what
// actually un-sticks the player, not just hiding the UI.
bpg_shopguard_force_close()
{
	if ( self lethalbeats\dynamicmenus\dynamic_shop::isShopOpen() )
		self lethalbeats\dynamicmenus\dynamic_shop::closeShop();

	self.currMenu = undefined;
}
