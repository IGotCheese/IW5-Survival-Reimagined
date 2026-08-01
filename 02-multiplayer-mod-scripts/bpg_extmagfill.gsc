/*
	bpg_extmagfill.gsc - Extended-mag weapons (e.g. Barrett .50cal + Extended Mags)
	spawn with the clip a few rounds short of what the pip display shows. Top off the
	current weapon's clip to its real clipSize on spawn (and on weapon switch, so it
	also fills a Barrett drawn as a secondary).

	setWeaponAmmoClip caps at the weapon's OWN clipSize, so it can only fill the gap -
	it can never overfill past what the weapon actually holds. Diagnostic value: if this
	makes the pips fill, the shortfall was a spawn/ammo-fill issue (fixed). If the pips
	still read short afterward, the extended-mag attachment is inflating the DISPLAY
	beyond the functional clip - that is client-side and not server-fixable.

	Loose GSC: LF, no BOM. Recompiles per map load; no restart needed.
*/

init()
{
	level thread bpg_extmag_watch();
}

bpg_extmag_watch()
{
	for ( ;; )
	{
		level waittill( "connected", player );
		player thread bpg_extmag_player();
	}
}

bpg_extmag_player()
{
	self endon( "disconnect" );

	for ( ;; )
	{
		self waittill( "spawned_player" );
		self thread bpg_extmag_fill_loop();
	}
}

bpg_extmag_fill_loop()
{
	self endon( "disconnect" );
	self endon( "death" );

	// let the loadout give settle, then fill the starting clip
	wait 0.15;
	self bpg_extmag_topoff();

	// also fill whatever weapon they switch to (bots + humans)
	for ( ;; )
	{
		self waittill( "weapon_change" );
		self bpg_extmag_topoff();
	}
}

bpg_extmag_topoff()
{
	wpn = self getcurrentweapon();

	if ( !isdefined( wpn ) || wpn == "none" || wpn == "" )
		return;

	self setweaponammoclip( wpn, 999 );
}
