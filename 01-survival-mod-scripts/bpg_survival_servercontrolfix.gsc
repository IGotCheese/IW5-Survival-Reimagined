// bpg_survival_servercontrolfix.gsc -- SURVIVAL SERVER ONLY (isolated storage).
// 2026-07-16: when a player types a registered admin command without privileges
// (e.g. "!restart"), onsay -> getMisc(INSUFFICIENT_PRIVILEGES_MSG) errors:
//   "type 'undefined' cannot be indexed" + "tell: cannot cast parameter 0..."
// Root cause is an upstream LB_ServerControl bug: the loader
// (scripts/lb_servercontrol.gsc, also shipped inside LB_ServerControl.iwd) calls
// groups::init() and commands::init() but FORGOT miscellaneous::init(), so
// level.miscellaneous is never populated. The iwd copy beats any loose loader
// edit (proven precedence), so instead we just make the missing call ourselves.
// miscellaneous.gsc loads on every survival map -> the call always resolves.
// Also overrides key 12 (INSUFFICIENT_PRIVILEGES_MSG) -- the mod's default
// string is "You has insufficient privileges."
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	lethalbeats\servercontrol\miscellaneous::init();

	// key 12 = INSUFFICIENT_PRIVILEGES_MSG (see #defines in miscellaneous.gsc)
	lethalbeats\servercontrol\miscellaneous::setMisc( 12, "^1You don't have permission to use that command." );

	level thread bpg_lockdown_dev_commands();
}

// 2026-07-16 SECURITY: lethalbeats\survival\dev\test.gsc registers its dev/cheat
// commands at power 0 = USABLE BY EVERY PLAYER (!money, !fly, !wave, !give, !clear,
// !speed, !jugger, ...). Raise them all to power 100 (console/rcon still works for
// us). Delayed + re-asserted: command registration happens in other scripts' init.
bpg_lockdown_dev_commands()
{
	level endon( "game_ended" );

	cmds = [];
	cmds[ 0 ] = "play";      cmds[ 1 ] = "crate";     cmds[ 2 ] = "ammo";
	cmds[ 3 ] = "ammo2";     cmds[ 4 ] = "fly";       cmds[ 5 ] = "speed";
	cmds[ 6 ] = "money";     cmds[ 7 ] = "armor";     cmds[ 8 ] = ""; // clear = real admin cmd now (bpg_survival_clearwave.gsc, power 70) — NOT force-100'd here
	cmds[ 9 ] = "wave";      cmds[ 10 ] = "shop";     cmds[ 11 ] = "view";
	cmds[ 12 ] = "knife";    cmds[ 13 ] = "run";      cmds[ 14 ] = "streak";
	cmds[ 15 ] = "drop";     cmds[ 16 ] = "damage";   cmds[ 17 ] = "give";
	cmds[ 18 ] = "test";     cmds[ 19 ] = "jugger";   cmds[ 20 ] = "predator";
	cmds[ 21 ] = "airstrike";cmds[ 22 ] = "pavelow";  cmds[ 23 ] = "sentry";
	cmds[ 24 ] = "botstatus";cmds[ 25 ] = "music";    cmds[ 26 ] = "savemap";
	cmds[ 27 ] = "save";     cmds[ 28 ] = "restore";  cmds[ 29 ] = "revive";
	cmds[ 30 ] = "chem";     cmds[ 31 ] = "detonate"; cmds[ 32 ] = "chemmine";
	cmds[ 33 ] = "spawndog"; cmds[ 34 ] = "dog";      cmds[ 35 ] = "dogsave";
	cmds[ 36 ] = "saveMap";

	// twice: once now-ish, once after every init has definitely registered
	for ( pass = 0; pass < 2; pass++ )
	{
		wait 0.5 + pass;
		if ( !isDefined( level.commands ) )
			continue;
		for ( i = 0; i < cmds.size; i++ )
			if ( isDefined( level.commands[ cmds[ i ] ] ) )
				level.commands[ cmds[ i ] ][ 1 ] = 100; // [1] = POWER
	}
}
