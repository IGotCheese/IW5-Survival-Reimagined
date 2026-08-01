// bpg_survival_shopfix.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-31.
//
// USER REPORT: "cant get out of buy station also after purchasing mods".
//
// ── WHY A SHOP ERROR TRAPS THE PLAYER ────────────────────────────────────────────────────────
// lethalbeats\DynamicMenus\dynamic_shop::onMenuResponse is ONE loop per player:
//     for (;;)
//     {
//         self waittill( "menuresponse", menu, response );
//         if ( isDefined( self.isMenuBusy ) && self.isMenuBusy ) continue;
//         self.isMenuBusy = true;
//         ...
//         self [[ level.onSelectOption ]]( page, response, getPrice( response ), option_type, index );
//         if ( isDefined( self.isMenuBusy ) && self.isMenuBusy ) self.isMenuBusy = false;
//     }
// isMenuBusy is raised BEFORE dispatch and lowered only on the last line. So any runtime error
// inside onSelectOption kills the whole thread: the flag stays true forever AND the for(;;) that
// listens for "menuresponse" is gone. From then on "back" and "close" do nothing, because
// nothing is listening. That is exactly "cannot get out of the buy station" - the menu is not
// stuck, the loop behind it is dead.
//
// Measured live on <SURV-PORT-4>/mp_geometric: 46 of these, the single largest error source on the map.
//     at "onbuy"          lethalbeats/survival/armories/weapons.gsc
//     at "onselectoption" lethalbeats/survival/armories/weapons.gsc
//     at "onselectoption" lethalbeats/survival/armories/_armories.gsc
//     at "onmenuresponse" lethalbeats/dynamicmenus/dynamic_shop.gsc
//
// ── DEFECT A: every purchase ends in an unguarded table lookup ───────────────────────────────
//     in call to builtin function "tablelookup": cannot cast parameter 2 from undefined to string
//         at updatelabels <- buyitem <- onbuy
// weapons.gsc::onBuy finishes with `player buyItem(price)`, and buyItem (dynamic_shop.gsc:217)
// ends with `self updateLabels()` - no argument. updateLabels:148 then does
//     if ( !isDefined( page ) ) page = self getPage();
//     start_index = int( tablelookup( TABLE, 1, page, 0 ) ) + 1;
// and getPage:182 opens with
//     if ( !isDefined( self.menuPages ) || self.menuPages.size == 0 ) return undefined;
// menuPages is emptied by closeShop:129 (`self.menuPages = []`), so any purchase that resolves
// after the shop has closed - or on a player whose page stack is already empty - reaches
// tablelookup with an undefined page and throws. onMenuResponse dies with it.
// FIX: refuse to draw a page that does not exist instead of erroring. There is nothing to draw
// in that state anyway, so returning is the correct behaviour, not a workaround.
//
// ── DEFECT B: a THIRD unguarded switchToWeapon ───────────────────────────────────────────────
//     in call to builtin method "switchtoweapon"
//         at survivor_switch_to_weapon <- onbuy
// lethalbeats\survival\utility::survivor_switch_to_weapon:1486 is
//     self switchToWeapon( weapon );
// with no check at all. onBuy hands it a freshly assembled name:
//     buildWeapon = weapon_build( self.weaponData[BASENAME], self.weaponData[ATTACHS], self.weaponData[CAMO] );
//     player player_give_weapon( buildWeapon );
//     player survivor_switch_to_weapon( buildWeapon );   <-- throws on a bad build
//     player buyItem( price );                            <-- so this never runs
// An attachment combination that does not resolve to a real weapon therefore both traps the
// player AND silently skips the charge. This matches the report precisely - it happens "after
// purchasing mods", i.e. attachments, not on plain weapon buys.
// Same bug family as bpg_survival_remoteweaponfix.gsc, which already had to guard
// clearUsingRemote and remoteEndRide. This is the third site.
//
// ── CONTAINMENT ──────────────────────────────────────────────────────────────────────────────
// Fixing both known throws is not enough on its own: ANY future error anywhere under
// onSelectOption traps the player the same way, with no way out short of reconnecting. The
// watchdog below notices a wedged loop and rebuilds it. Restarting onMenuResponse is safe even
// if the original somehow survives - isMenuBusy is checked by every copy of the loop against the
// same player entity, so duplicates serialise on it and only one processes any given response.
//
// ⚠️ Every cross-file symbol used here was checked against a top-level definition before being
// referenced - an unresolved one is a COMPILE-time Com_ERROR that boot-loops the server, which is
// exactly how <SURV-PORT-3> was lost earlier today. Verified:
//     lethalbeats\player::player_take_all_weapon_buffs        player.gsc:685
//     lethalbeats\player::player_give_perk                    player.gsc:112
//     lethalbeats\survival\utility::player_get_weapon_data    Survival/utility.gsc:400
//     lethalbeats\DynamicMenus\dynamic_shop::getPage          dynamic_shop.gsc:182
//     lethalbeats\DynamicMenus\dynamic_shop::getOptionType    dynamic_shop.gsc:135
//     lethalbeats\DynamicMenus\dynamic_shop::updateOption     dynamic_shop.gsc:165
//     lethalbeats\DynamicMenus\dynamic_shop::closeShop        dynamic_shop.gsc:126
//     lethalbeats\DynamicMenus\dynamic_shop::onMenuResponse   dynamic_shop.gsc:28
//
// ⚠️ NEVER copy to the live <MP-PORT> server - survival gametype only.

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	level thread bpg_shop_hooks();
	level thread bpg_shop_watchdog();
}

// Mod init runs AFTER loose scripts, so these are re-asserted on a delay.
bpg_shop_hooks()
{
	level endon( "game_ended" );

	for ( i = 0; i < 6; i++ )
	{
		wait 0.5;
		replaceFunc( lethalbeats\survival\utility::survivor_switch_to_weapon, ::bpg_survivor_switch_to_weapon );
		replaceFunc( lethalbeats\DynamicMenus\dynamic_shop::updateLabels, ::bpg_updatelabels_safe );
		replaceFunc( lethalbeats\player::player_give_weapon, ::bpg_player_give_weapon );
	}
}

// ── DEFECT A (ROOT CAUSE) ────────────────────────────────────────────────────────────────────
// This is the actual "lost my gun after the buy stations". Everything else in this file was
// downstream of it. armories\weapons.gsc:164-177 runs, in this order:
//
//     player takeWeapon( buildWeapon );                          <- old gun gone FIRST
//     buildWeapon = weapon_build( BASENAME, ATTACHS, CAMO );     <- may return a bad name
//     player player_give_weapon( buildWeapon );                  <- fails, unchecked
//     self.weaponData[ BUILD_NAME ] = buildWeapon;               <- bad name PERSISTED
//     player setWeaponData( buildWeapon, self.weaponData );      <- persisted again
//     player buyItem( price );                                   <- charged regardless
//
// weapon_build (weapon.gsc) hand-rolls the name instead of using stock buildWeaponName whenever
// there is at least one attachment:
//     fullname = baseName + "_mp_";                              <- trailing underscore
//     return fullname + string_join( "_", attachs ) + camo;
// so if attach_build maps an attachment to an empty string the result is "iw5_ak47_mp_", and with
// a camo "iw5_ak47_mp__camo". Both are names the engine rejects. giveWeapon then does nothing and
// the player is left holding air, because the take already succeeded.
//
// Stock player_give_weapon makes it worse: it records self.primaryweapon / self.pers, so the mod
// then believes you are carrying a weapon that does not exist - which is why hasWeapon passed the
// v1 guard below, and the likely source of the player_set_ammo_data errors too.
//
// This version verifies the give and refuses to record or switch to a weapon the engine did not
// actually hand over, then puts back what the shop took. It also finally LOGS the rejected name,
// which is the one piece of data needed to fix weapon_build itself rather than guess at it.
//
// Body is stock (player.gsc:57-80) other than the verification. Every symbol confirmed to be a
// resolvable top-level definition - string_contains/string_ends_with in string.gsc:128/150,
// player_is_weapon_primary/player_get_weapons in player.gsc:438/411. That check is the one whose
// absence boot-looped <SURV-PORT-3> earlier.
//
// ⚠️ Four callers inherit this (player.gsc:72,132,321,782 - spawn weapon, perks, nades, last
// stand). All of them want "do not pretend a failed give worked", so the guard is correct for
// every one; only the restore is shop-specific, and it is keyed off bpg_undo which only the shop
// path sets.
bpg_player_give_weapon( weapon, switchInmmediate, maxAmmo, spawnWeapon )
{
	if ( !isDefined( switchInmmediate ) ) switchInmmediate = 0;
	if ( !isDefined( maxAmmo ) ) maxAmmo = 0;
	if ( !isDefined( spawnWeapon ) ) spawnWeapon = 0;

	if ( !isDefined( weapon ) || weapon == "" || weapon == "none" )
	{
		println( "[BPG-GIVE] refused an undefined/empty weapon name" );
		return;
	}

	if ( !lethalbeats\string::string_contains( weapon, "_mp_" ) && !lethalbeats\string::string_ends_with( weapon, "_mp" ) )
		weapon = weapon + "_mp";

	self giveWeapon( weapon );

	// THE CHECK STOCK NEVER MAKES. Note a malformed "base_mp_" still contains "_mp_", so the
	// fixup above cannot catch it - only asking the engine works.
	if ( !self hasWeapon( weapon ) )
	{
		println( "[BPG-GIVE] ENGINE REJECTED WEAPON NAME '" + weapon + "' - give failed, state not recorded" );

		restore = undefined;

		if ( isDefined( self.bpg_undo ) && isDefined( self.bpg_undo[ "currentWeapon" ] ) )
			restore = self.bpg_undo[ "currentWeapon" ];

		if ( isDefined( restore ) && restore != "" && restore != "none" && restore != weapon )
		{
			self giveWeapon( restore );

			if ( self hasWeapon( restore ) )
			{
				self switchToWeapon( restore );
				println( "[BPG-GIVE] restored pre-purchase weapon '" + restore + "'" );
			}
			else
				println( "[BPG-GIVE] restore of '" + restore + "' ALSO rejected - player left empty-handed" );
		}

		return;
	}

	if ( self lethalbeats\player::player_is_weapon_primary( weapon ) )
	{
		self.pers[ "primaryWeapon" ] = weapon;
		self.primaryweapon = weapon;
	}
	else self.secondaryweapon = weapon;

	if ( self lethalbeats\player::player_get_weapons().size ) self switchToWeapon( weapon );
	else if ( switchInmmediate ) self switchToWeaponImmediate( weapon );

	if ( maxAmmo ) self giveMaxAmmo( weapon );
	if ( spawnWeapon ) self setSpawnWeapon( weapon );
}

// ── DEFECT B ─────────────────────────────────────────────────────────────────────────────────
// Stock body with the switch guarded. The rest is preserved exactly, including running the buff
// pass even when the switch is skipped - the purchase still happened and the weapon still exists,
// so its buffs must still be applied.
bpg_survivor_switch_to_weapon( weapon )
{
	// ⚠️ v2. v1 guarded with `self hasWeapon( weapon )` and STILL threw - 16 live
	// "in call to builtin method switchtoweapon" errors named THIS function. hasWeapon can
	// return true for a build the engine will not actually switch to, so it is not a sufficient
	// test. Membership in getWeaponsListPrimaries() is: that list is what the player is actually
	// holding, so switching to an entry of it cannot fail.
	prims = self getWeaponsListPrimaries();

	target = undefined;

	foreach ( w in prims )
	{
		if ( isDefined( w ) && isDefined( weapon ) && w == weapon )
			target = w;
	}

	// The requested build is not really in hand. Fall back to any real primary so the player is
	// left holding something rather than empty.
	if ( !isDefined( target ) )
	{
		foreach ( w in prims )
		{
			if ( !isDefined( w ) || w == "none" )
				continue;

			if ( maps\mp\_utility::isKillstreakWeapon( w ) )
				continue;

			target = w;
			break;
		}

		println( "[BPG-SHOP] build not switchable: '" + ( isDefined( weapon ) ? weapon : "undefined" ) + "' - primaries held: " + prims.size + ", falling back to '" + ( isDefined( target ) ? target : "NOTHING" ) + "'" );
	}

	// ── THE LOST GUN ────────────────────────────────────────────────────────────────────────
	// weapons.gsc::onBuy does `player takeWeapon( buildWeapon )` BEFORE
	// `player player_give_weapon( buildWeapon )`. When the rebuilt name is invalid the give
	// fails (8 live "in call to builtin method giveweapon" errors) and the old gun is already
	// gone - the player is left holding nothing. Guarding the switch never addressed that.
	// bpg_survival_undo.gsc snapshots the loadout at shop-open into self.bpg_undo, so the
	// weapon they walked in with is recoverable.
	if ( !isDefined( target ) )
	{
		restore = undefined;

		if ( isDefined( self.bpg_undo ) && isDefined( self.bpg_undo[ "currentWeapon" ] ) )
			restore = self.bpg_undo[ "currentWeapon" ];

		if ( isDefined( restore ) && restore != "" && restore != "none" )
		{
			println( "[BPG-SHOP] player left weaponless by a failed buy - restoring pre-purchase weapon '" + restore + "'" );
			self giveWeapon( restore );
			self switchToWeapon( restore );
			return;
		}

		println( "[BPG-SHOP] player left weaponless by a failed buy and NO snapshot exists to restore from" );
		return;
	}

	self switchToWeapon( target );

	self lethalbeats\player::player_take_all_weapon_buffs();

	weaponData = self lethalbeats\survival\utility::player_get_weapon_data( weapon );

	if ( !isDefined( weaponData ) )
		return;

	foreach ( buff in weaponData[ 3 ] )
		self lethalbeats\player::player_give_perk( buff, true );
}

// ── DEFECT A ─────────────────────────────────────────────────────────────────────────────────
// Stock body (dynamic_shop.gsc:146-163) with one guard added. TABLE is inlined because a #define
// from the mod's own file is not visible here.
bpg_updatelabels_safe( page )
{
	// ⚠️ CAUSE ESTABLISHED 2026-07-31 - this is no longer a guard against an unknown.
	// dynamic_shop::closeShop:126-131 sets BOTH `self.shop = undefined` and `self.menuPages = []`.
	// getPage:187 then returns undefined on an empty stack, and stock updateLabels fed that
	// straight into tableLookup( TABLE, 1, undefined, 0 ), which throws. So the failure is a
	// close/update RACE: an updateLabels queued before the shop closed lands after it.
	//
	// Returning is the correct behaviour, not merely the safe one - there is genuinely no page
	// to draw once the shop is shut. But the two ways we get here are NOT the same thing, and
	// logging them identically would bury a real defect inside expected noise.
	shopOpen = isDefined( self.shop );

	if ( !isDefined( page ) )
		page = self lethalbeats\DynamicMenus\dynamic_shop::getPage();

	if ( !isDefined( page ) || page == "" )
	{
		if ( !shopOpen )
		{
			// EXPECTED: the shop closed out from under a queued update. Benign, and common
			// enough that logging every one would flood. Silent by design.
			return;
		}

		// UNEXPECTED: the shop is OPEN and still has no page. That means menuPages went empty
		// while in use, or getPage's real_index fell outside the stack (getPage:189-191) - a
		// genuine navigation bug worth seeing. Loud on purpose.
		println( "[BPG-SHOP] updateLabels: shop is OPEN but getPage returned nothing - menuPages stack is broken, not a close race" );
		return;
	}

	start_index = int( tableLookup( "mp/dynamic_shop.csv", 1, page, 0 ) ) + 1;

	for ( i = 0; i < 11; i++ )
	{
		row = i + start_index;

		option_label = tableLookupByRow( "mp/dynamic_shop.csv", row, 2 );

		if ( option_label == "" )
			break;

		item = tableLookupByRow( "mp/dynamic_shop.csv", row, 6 );
		price_label = self lethalbeats\DynamicMenus\dynamic_shop::getOptionType( page, item, i );

		if ( isDefined( level.onUpdateOption ) )
			self [[ level.onUpdateOption ]]( i, item, option_label, price_label );
		else
			self lethalbeats\DynamicMenus\dynamic_shop::updateOption( i, item, option_label, price_label );
	}

	self setClientDvar( "ui_shop_display", page );
	self openMenu( "ui_shop_display" );
}

// ── CONTAINMENT ──────────────────────────────────────────────────────────────────────────────
bpg_shop_watchdog()
{
	level endon( "game_ended" );

	// A real onSelectOption completes within a frame or two. 5s means the thread is gone.
	limit = 5000;
	if ( getDvarInt( "bpg_shop_stuck_ms" ) > 0 )
		limit = getDvarInt( "bpg_shop_stuck_ms" );

	for ( ;; )
	{
		wait 2;

		now = getTime();

		foreach ( p in level.players )
		{
			if ( !isDefined( p ) || !isPlayer( p ) )
				continue;

			if ( !isDefined( p.isMenuBusy ) || !p.isMenuBusy )
			{
				p.bpg_busySince = undefined;
				continue;
			}

			if ( !isDefined( p.bpg_busySince ) )
			{
				p.bpg_busySince = now;
				continue;
			}

			if ( now - p.bpg_busySince < limit )
				continue;

			// Do not rebuild the loop over and over if something keeps re-wedging it.
			if ( isDefined( p.bpg_shopRescued ) && now - p.bpg_shopRescued < 30000 )
				continue;

			// Read the duration BEFORE clearing the stamp - using it after would put an
			// undefined straight into println, i.e. the exact class of error this file exists
			// to stop.
			stuckFor = ( now - p.bpg_busySince ) / 1000;

			p.bpg_shopRescued = now;
			p.bpg_busySince = undefined;

			println( "[BPG-SHOP] menu loop wedged for " + stuckFor + "s - closing the shop and restarting the response loop" );

			// closeShop clears isMenuBusy, drops the page stack and closes the menu client-side.
			p lethalbeats\DynamicMenus\dynamic_shop::closeShop();

			// The listener died with the error; without this the player could never use a shop
			// again for the rest of the map.
			p thread lethalbeats\DynamicMenus\dynamic_shop::onMenuResponse();
		}
	}
}
