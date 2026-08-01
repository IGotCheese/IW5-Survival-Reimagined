// bpg_survival_vaultstore.gsc — persistence for the private !vault. 2026-07-30.
//
// ⚠️⚠️ THIS FILE IS QUARANTINE. It is the ONLY script that calls an iw5-gsc-utils-sdk builtin.
// Nothing imports it and it calls nothing in bpg_survival_bankcmds.gsc. That is load-bearing:
// in GSC an unresolved builtin is a COMPILE-time failure that kills the WHOLE file, and on
// 2026-07-17 persistence was wired straight into bankcmds, the plugin failed to load, and it
// took !buyammo/!buyarmor/!buyrevive down with it. The contract is one-way: bankcmds fires
// level notify("bpg_vault_changed", player); this file listens. If this file ever dies, the
// vault stops persisting and every command keeps working.
//
// ── TWO MODES ────────────────────────────────────────────────────────────────────────────────
// PER-PLAYER (cross-server)   set bpg_vault_dir  "C:\Vaults"     <- preferred
//     One file per player: <dir>\<guid>.txt containing just the amount. All four survival
//     servers point at the SAME directory, so savings follow the player between servers.
// SINGLE-FILE (per-server)    set bpg_vault_file "...\bpg_vault.txt"  <- fallback, no code change
//     The original one-file-per-instance behaviour. Kept so this can be reverted by config.
// bpg_vault_dir wins if both are set. Neither set = persistence disabled, loudly.
//
// ── WHY NOT ONE SHARED FILE ──────────────────────────────────────────────────────────────────
// Because it corrupts and it duplicates money. Every save is a FULL-FILE overwrite and
// writefile does no locking, so with four writers: A reads {p1}, B reads {p1}, A writes
// {p1,p2}, B writes {p1,p3} -> p2's balance is gone. A reader can also catch a half-written
// file. Worse, the write lag is an exploit: withdraw $5000 on Surv #1, hop to Surv #2 before it
// reloads, withdraw the same $5000 again.
// Per-player files remove the race BY CONSTRUCTION - the unit of writing becomes the unit of
// ownership. Two servers writing different players' files can never collide, and a player is
// only ever connected to one server, so their file has exactly one writer at a time.
// The handoff is made sequential by flushing on disconnect (see bpg_vaultstore_pp_player),
// which is what actually closes the duplication window.
//
// RESIDUAL RISK, stated honestly: if a server dies hard between a withdrawal and the disconnect
// flush, that player reverts to their last saved amount. It fails toward "keeps their savings"
// rather than toward duplication, which is the right direction to fail in.
//
// PLUGIN API (verified against iw5-gsc-utils-sdk/src/component/io.cpp and the live DLL's own
// registered strings): fileexists(path)->bool, readfile(path)->string,
// writefile(path,data)->bool, createdirectory(path)->bool. Only these four are used;
// jsonserialize/jsonparse are deliberately avoided so nothing depends on how the plugin
// marshals GSC arrays.

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	if ( getDvar( "bpg_vault_persist" ) == "" )
		setDvar( "bpg_vault_persist", "1" );

	if ( getDvarInt( "bpg_vault_persist" ) != 1 )
		return;

	if ( getDvar( "bpg_vault_dir" ) != "" )
	{
		level thread bpg_vaultstore_pp_boot();
		return;
	}

	if ( getDvar( "bpg_vault_file" ) != "" )
	{
		level thread bpg_vaultstore_single_boot();
		return;
	}

	println( "[BPG-VAULT] DISABLED - set bpg_vault_dir (per-player, cross-server) or bpg_vault_file (single file)" );
}

// ── shared helpers ───────────────────────────────────────────────────────────────────────────

// A guid becomes a FILENAME, so it must never be able to escape the vault directory.
// Real guids are hex-ish ("01000000AAAAAAAA") and bot names are ("bot13"), both safe, but this
// is the one place untrusted-ish input reaches a filesystem path so it gets checked anyway.
bpg_vault_guid_safe( g )
{
	if ( !isDefined( g ) || g == "" )
		return false;
	if ( isSubStr( g, "\\" ) || isSubStr( g, "/" ) || isSubStr( g, ":" ) || isSubStr( g, ".." ) )
		return false;
	return true;
}

// ── PER-PLAYER MODE (cross-server) ───────────────────────────────────────────────────────────

bpg_vaultstore_pp_boot()
{
	level endon( "game_ended" );

	dir = getDvar( "bpg_vault_dir" );
	createdirectory( dir );          // no-op if it already exists
	println( "[BPG-VAULT] per-player mode, dir=" + dir );

	if ( !isDefined( game[ "bpg_vault" ] ) )
		game[ "bpg_vault" ] = [];

	level thread bpg_vaultstore_pp_connect_watch();
	level thread bpg_vaultstore_pp_change_watch();
}

bpg_vaultstore_pp_path( guid )
{
	return getDvar( "bpg_vault_dir" ) + "\\" + guid + ".txt";
}

bpg_vaultstore_pp_connect_watch()
{
	level endon( "game_ended" );

	// catch players already in (map change keeps them connected - "connected" will not re-fire)
	foreach ( p in level.players )
	{
		if ( isDefined( p ) && !( p isTestClient() ) )
			p thread bpg_vaultstore_pp_player();
	}

	for ( ;; )
	{
		level waittill( "connected", player );

		if ( isDefined( player ) && !( player isTestClient() ) )
			player thread bpg_vaultstore_pp_player();
	}
}

// Per-player lifecycle: load on arrival, flush on departure.
bpg_vaultstore_pp_player()
{
	// wait for a usable guid rather than assuming one exists at connect time
	tries = 0;
	while ( !isDefined( self.guid ) && tries < 40 )
	{
		wait 0.25;
		tries++;
	}

	if ( !bpg_vault_guid_safe( self.guid ) )
		return;

	self bpg_vaultstore_pp_load();

	self waittill( "disconnect" );

	// Flush IMMEDIATELY, not on the debounce. This is what makes the handoff to another
	// server sequential and closes the duplication window described in the header.
	self bpg_vaultstore_pp_save();
}

bpg_vaultstore_pp_load()
{
	guid = self.guid;
	path = bpg_vaultstore_pp_path( guid );

	if ( !fileexists( path ) )
		return;

	blob = readfile( path );
	if ( !isDefined( blob ) || blob == "" )
		return;

	amt = int( blob );
	if ( amt <= 0 )
		return;

	if ( !isDefined( game[ "bpg_vault" ] ) )
		game[ "bpg_vault" ] = [];

	game[ "bpg_vault" ][ guid ] = amt;
	println( "[BPG-VAULT] loaded $" + amt + " for a returning player" );
}

bpg_vaultstore_pp_save()
{
	guid = self.guid;
	if ( !bpg_vault_guid_safe( guid ) )
		return;

	amt = 0;
	if ( isDefined( game[ "bpg_vault" ] ) && isDefined( game[ "bpg_vault" ][ guid ] ) )
		amt = int( game[ "bpg_vault" ][ guid ] );

	// An empty vault still gets written: a player who withdraws everything on server A must not
	// find their old balance waiting on server B. Writing "0" is the correct record.
	if ( amt < 0 )
		amt = 0;

	ok = writefile( bpg_vaultstore_pp_path( guid ), "" + amt );
	println( "[BPG-VAULT] saved $" + amt + " ok=" + ok );
}

bpg_vaultstore_pp_change_watch()
{
	level endon( "game_ended" );

	for ( ;; )
	{
		// bankcmds passes the player who changed, so only THAT file is rewritten.
		level waittill( "bpg_vault_changed", player );

		if ( !isDefined( player ) )
			continue;

		player bpg_vaultstore_pp_save();
	}
}

// ── SINGLE-FILE MODE (per-server fallback, original behaviour) ───────────────────────────────

bpg_vaultstore_single_boot()
{
	level endon( "game_ended" );

	println( "[BPG-VAULT] single-file mode, file=" + getDvar( "bpg_vault_file" ) );

	bpg_vaultstore_single_load();

	level thread bpg_vaultstore_single_watch();
	level thread bpg_vaultstore_single_flush_on_end();
}

bpg_vaultstore_single_load()
{
	path = getDvar( "bpg_vault_file" );

	if ( !fileexists( path ) )
	{
		println( "[BPG-VAULT] no store at " + path + " - starting empty" );
		return;
	}

	blob = readfile( path );
	if ( !isDefined( blob ) || blob == "" )
		return;

	if ( !isDefined( game[ "bpg_vault" ] ) )
		game[ "bpg_vault" ] = [];

	lines = strtok( blob, "\n" );
	loaded = 0;

	for ( i = 0; i < lines.size; i++ )
	{
		parts = strtok( lines[ i ], " " );
		if ( !isDefined( parts ) || parts.size < 2 )
			continue;

		guid = parts[ 0 ];
		amt = int( parts[ 1 ] );
		if ( !bpg_vault_guid_safe( guid ) || amt <= 0 )
			continue;

		game[ "bpg_vault" ][ guid ] = amt;
		loaded++;
	}

	println( "[BPG-VAULT] loaded " + loaded + " vault(s) from " + path );
}

bpg_vaultstore_single_watch()
{
	level endon( "game_ended" );

	for ( ;; )
	{
		level waittill( "bpg_vault_changed" );
		wait 3;
		if ( isDefined( level.bpg_vault_dirty ) && level.bpg_vault_dirty )
			bpg_vaultstore_single_save();
	}
}

bpg_vaultstore_single_flush_on_end()
{
	level waittill( "game_ended" );

	if ( isDefined( level.bpg_vault_dirty ) && level.bpg_vault_dirty )
		bpg_vaultstore_single_save();
}

bpg_vaultstore_single_save()
{
	if ( !isDefined( game[ "bpg_vault" ] ) )
		return;

	blob = "";
	n = 0;

	foreach ( guid, amt in game[ "bpg_vault" ] )
	{
		if ( !isDefined( guid ) || !isDefined( amt ) || int( amt ) <= 0 )
			continue;

		blob = blob + guid + " " + int( amt ) + "\n";
		n++;
	}

	ok = writefile( getDvar( "bpg_vault_file" ), blob );
	level.bpg_vault_dirty = false;

	println( "[BPG-VAULT] saved " + n + " vault(s) ok=" + ok );
}
