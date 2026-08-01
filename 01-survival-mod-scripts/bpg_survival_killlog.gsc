// bpg_survival_killlog.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-16.
// User: "show a kill log and a remaining enemy count."
//   (1) ENEMIES-REMAINING counter — the mod only flashes a transient "HOSTILES"
//       notify at wave start; there's no persistent count. This shows how many
//       enemies are left in the wave: level.bots_total_count - level.bots_deaths
//       (matches the wave model in maps\mp\gametypes\survival.gsc onWaveStart/End).
//   (2) KILL LOG — a rolling feed of the last few kills ("Name <enemy type>", type
//       in red; user 2026-07-16: type instead of weapon). Wraps the mod's
//       level.prevCallbackPlayerKilled function-ref (onBotKilled chains it with the
//       full killed signature) — a level-var wrap, NO replaceFunc, no ordering race,
//       and it also sees special enemies (jugg etc.) that bypass bot_kill. Types use
//       the OFFICIAL MW3 Survival enemy names (user-supplied roster): ability tokens
//       in self.botType tag specials ("martyrdom_dog" -> "C4 Dog"); plain troops are
//       tiered by carried weapon (1887=Light Troop ... FAD=Heavy Commando).
// Uses the SAME proven HUD pattern as bpg_survival_helpbar.gsc (client createFontString
// + setText; the vote HUD already proves dynamic setText works here). Positions are
// dvar-tunable live so they can be nudged while watching the screen:
//   set bpg_enemyhud_x -8  / set bpg_enemyhud_y 4
//   set bpg_feed_x    -8   / set bpg_feed_y    22   (feed stacks downward from here)
// ⚠️ NEVER copy to the live <MP-PORT> server (survival wave vars + scoreboard notify).

#include maps\mp\gametypes\_hud_util;
#include common_scripts\utility;

// Tunables (GSC has no file-scope constants, so they live as locals where used):
//   feed lines visible = 4 ; line lifetime = 6000ms ; fade tail = 1000ms.

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	// TOP-RIGHT CORNER of the screen (user request): counter on the first line,
	// kill feed stacking directly beneath it.
	if ( getDvar( "bpg_enemyhud_x" ) == "" ) setDvar( "bpg_enemyhud_x", "-8" );
	if ( getDvar( "bpg_enemyhud_y" ) == "" ) setDvar( "bpg_enemyhud_y", "4" );
	if ( getDvar( "bpg_feed_x" ) == "" )     setDvar( "bpg_feed_x", "-8" );
	if ( getDvar( "bpg_feed_y" ) == "" )     setDvar( "bpg_feed_y", "22" );
	// column gaps for the split (name | label) HUD elements - see the configstring
	// notes below. Tunable live if the spacing looks off on someone's resolution.
	if ( getDvar( "bpg_feed_namegap" ) == "" )  setDvar( "bpg_feed_namegap", "120" );
	if ( getDvar( "bpg_enemyhud_gap" ) == "" )  setDvar( "bpg_enemyhud_gap", "34" );

	level thread bpg_killlog_watcher();
	level thread bpg_install_kill_hook();
}

// Wrap the mod's saved stock killed-callback so we see every kill WITH its weapon.
// onBotKilled (and the survivor path) call self [[level.prevCallbackPlayerKilled]]
// (eInflictor, eAttacker, iDamage, sMeansOfDeath, sWeapon, ...). Poll until the mod
// has stored it (its init order vs ours doesn't matter), then splice ourselves in.
bpg_install_kill_hook()
{
	level endon( "game_ended" );

	while ( !isDefined( level.prevCallbackPlayerKilled ) )
		wait 0.25;
	wait 0.05;

	level.bpg_prev_cbk = level.prevCallbackPlayerKilled;
	level.prevCallbackPlayerKilled = ::bpg_callback_killed_feed;
}

// self = the killed entity. Feed only axis (enemy) deaths credited to a human
// player (directly, or via an owned entity like a sentry/dog), then chain stock.
bpg_callback_killed_feed( eInflictor, eAttacker, iDamage, sMeansOfDeath, sWeapon, vDir, sHitLoc, timeOffset, deathAnimDuration )
{
	if ( isDefined( self.team ) && self.team == "axis" && isDefined( eAttacker ) )
	{
		// 2026-07-24: pass the killer ENTITY, not just their name string. The feed now
		// renders names via setPlayerNameString() (zero configstrings) instead of baking
		// the name into a setText() string - see the configstring note in the render loop.
		killer = undefined;
		if ( isPlayer( eAttacker ) && !eAttacker isTestClient() && isDefined( eAttacker.name ) )
			killer = eAttacker;
		else if ( isDefined( eAttacker.owner ) && isPlayer( eAttacker.owner ) && !eAttacker.owner isTestClient() && isDefined( eAttacker.owner.name ) )
			killer = eAttacker.owner;

		if ( isDefined( killer ) )
			level notify( "bpg_enemy_killed", killer, self bpg_enemy_type_label() );
	}

	// 2026-07-24: emit the stock "K;" kill line into games_mp.log ourselves.
	// WHY HERE instead of restoring the stock logger: the survival mod does
	//   replaceFunc( maps\mp\gametypes\_damage::logPrintPlayerDeath, ::blank )
	// in lethalbeats/Survival/patch/globallogic.gsc, which is what kills IW4MAdmin
	// stats (it parses exactly these lines). A separate script tried to replaceFunc
	// that symbol BACK - it compiled, ran, and re-applied 30+ times with no error,
	// but its function was never once called: **replaceFunc appears to be
	// FIRST-writer-wins on a given symbol, not last**, so the mod's ::blank (set at
	// its own init) is permanent and cannot be overridden that way. Proven live via a
	// one-shot diagnostic that never fired while the player was actively getting kills.
	// This callback, by contrast, is spliced in via the level.prevCallbackPlayerKilled
	// VARIABLE (see bpg_install_kill_hook) - a plain reassignment, no replaceFunc - and
	// is demonstrably called for every kill, since the kill feed above works. So we
	// just write the line here.
	// Format is byte-identical to stock logprintplayerdeath, field-verified against a
	// real line from the MAIN server's log:
	//   K;guid;entNum;team;name;attGuid;attEntNum;attTeam;attName;weapon;damage;mod;hitLoc
	bpg_log_kill_line( eAttacker, iDamage, sMeansOfDeath, sWeapon, sHitLoc );

	self [[ level.bpg_prev_cbk ]]( eInflictor, eAttacker, iDamage, sMeansOfDeath, sWeapon, vDir, sHitLoc, timeOffset, deathAnimDuration );
}

// self = the killed entity. Writes one stock-format "K;" line to games_mp.log so
// IW4MAdmin can build stats. Every field is guarded: this runs for bots, survivors,
// and world/suicide deaths (attacker undefined), and a malformed line is worse than
// no line - IW4M would mis-parse it. Stock uses team "world" / entNum -1 / empty
// guid+name when there's no player attacker, so we match that exactly.
bpg_log_kill_line( eAttacker, iDamage, sMeansOfDeath, sWeapon, sHitLoc )
{
	if ( !isDefined( self ) )
		return;

	guid    = isDefined( self.guid ) ? self.guid : "";
	name    = isDefined( self.name ) ? self.name : "";
	team    = isDefined( self.team ) ? self.team : "world";
	entNum  = self getEntityNumber();

	if ( isDefined( eAttacker ) && isPlayer( eAttacker ) )
	{
		attGuid   = isDefined( eAttacker.guid ) ? eAttacker.guid : "";
		attName   = isDefined( eAttacker.name ) ? eAttacker.name : "";
		attTeam   = isDefined( eAttacker.team ) ? eAttacker.team : "world";
		attEntNum = eAttacker getEntityNumber();
	}
	else
	{
		attGuid   = "";
		attName   = "";
		attTeam   = "world";
		attEntNum = -1;
	}

	dmg = isDefined( iDamage ) ? iDamage : 0;
	mod = isDefined( sMeansOfDeath ) ? sMeansOfDeath : "MOD_UNKNOWN";
	wep = isDefined( sWeapon ) ? sWeapon : "none";
	loc = isDefined( sHitLoc ) ? sHitLoc : "none";

	logPrint( "K;" + guid + ";" + entNum + ";" + team + ";" + name + ";" + attGuid + ";" + attEntNum + ";" + attTeam + ";" + attName + ";" + wep + ";" + dmg + ";" + mod + ";" + loc + "\n" );
}

// self = the killed bot. Official MW3 Survival enemy names (user-supplied roster).
// Ability tags (self.botType tokens) identify special enemies; plain troops are
// classified by the weapon they carry (1887=Light, MP5=Medium, AK-47=Heavy,
// ACR=Commando, FAD=Heavy Commando, PM-9=Claymore Expert).
bpg_enemy_type_label()
{
	bt = "";
	if ( isDefined( self.botType ) )
		bt = self.botType;

	isdog = isSubStr( bt, "dog" );
	isboom = isSubStr( bt, "martyrdom" );
	isgas = isSubStr( bt, "chemical" );
	isjugg = isSubStr( bt, "jugger" );
	isshield = isSubStr( bt, "riotshield" );

	// --- ability-tagged enemies first (definitive) ---
	if ( isdog )
	{
		if ( isboom || isgas )
			return "C4 Dog";
		return "Dog";
	}
	if ( isjugg )
	{
		if ( isshield )
			return "Riot Shield Juggernaut";
		return "Juggernaut";
	}
	if ( isboom )
		return "Suicide Trooper";
	if ( isgas )
		return "Chemical Agent";
	if ( isshield )
		return "Riot Shield Trooper";
	if ( isSubStr( bt, "chopper" ) )
		return "Little Bird";
	if ( isSubStr( bt, "ims" ) || isSubStr( bt, "claymore" ) )
		return "Claymore Expert";
	if ( isSubStr( bt, "sentry" ) )
		return "Sentry";
	if ( isSubStr( bt, "pavelow" ) )
		return "Pave Low";
	if ( isSubStr( bt, "reaper" ) )
		return "Reaper";
	if ( isSubStr( bt, "tank" ) )
		return "Tank";
	if ( isSubStr( bt, "airstrike" ) )
		return "Airstrike";
	if ( isSubStr( bt, "predator" ) )
		return "Predator";
	if ( isSubStr( bt, "counteruav" ) )
		return "Counter-UAV";
	if ( isSubStr( bt, "emp" ) )
		return "EMP Trooper";

	// --- plain troops: tier by carried weapon ---
	w = self getCurrentWeapon();
	if ( !isDefined( w ) )
		w = "";

	if ( isSubStr( w, "1887" ) )
		return "Light Troop";
	if ( isSubStr( w, "mp5" ) )
		return "Medium Troop";
	if ( isSubStr( w, "ak47" ) )
		return "Heavy Troop";
	if ( isSubStr( w, "acr" ) )
		return "Commando";
	if ( isSubStr( w, "fad" ) )
		return "Heavy Commando";
	if ( isSubStr( w, "usas" ) )
		return "Suicide Trooper";
	if ( isSubStr( w, "pp90m1" ) )
		return "Chemical Agent";
	if ( isSubStr( w, "pecheneg" ) )
		return "Juggernaut";
	if ( isSubStr( w, "pm9" ) )
		return "Claymore Expert";

	return "Soldier";
}

bpg_killlog_watcher()
{
	level endon( "game_ended" );

	for ( ;; )
	{
		level waittill( "connected", player );
		if ( !player isTestClient() )
			player thread bpg_killlog_player();
	}
}

bpg_killlog_player()
{
	// 2026-07-19 FIX for a live-confirmed "G_FindConfigstringIndex: overflow" crash after
	// hours-long sessions: "connected" was assumed to fire once per player-connection
	// lifetime, but it refires across MAP CHANGES for clients who stay connected through the
	// transition — and self.bpg_killlog_ready (a plain player-var) doesn't reliably survive
	// that transition either, so the old "build once" boolean guard let every surviving
	// player leak 5 fresh configstring-backed hudElems (1 counter + 4 feed lines) per map
	// change, unbounded, for the life of the server. This notify+endon kills any still-running
	// render/listen threads from a stale prior instance, and any leftover hudElems from a
	// prior instance are explicitly destroyed before new ones are created — the function is
	// now idempotent and safe to re-enter regardless of how many times "connected" refires.
	self notify( "bpg_killlog_restart" );
	self endon( "bpg_killlog_restart" );
	self endon( "disconnect" );
	level endon( "game_ended" );

	// wait for a spawn so the HUD has a canvas
	self waittill( "spawned_player" );
	wait 2;

	if ( isDefined( self.bpg_enemyhud ) )
		self.bpg_enemyhud destroy();
	if ( isDefined( self.bpg_enemyhud_num ) )
		self.bpg_enemyhud_num destroy();
	if ( isDefined( self.bpg_feedlines ) )
	{
		foreach ( h in self.bpg_feedlines )
			if ( isDefined( h ) )
				h destroy();
	}
	// destroy the parented name elements too - missing these would leak one hudelem
	// per line per map change (the exact bug this file's header already warns about).
	if ( isDefined( self.bpg_feednames ) )
	{
		foreach ( h in self.bpg_feednames )
			if ( isDefined( h ) )
				h destroy();
	}

	// --- enemies-remaining counter (top-right, below the wave notify) ---
	// ⚠️ 2026-07-24 CONFIGSTRING FIX. This used to be ONE element doing
	//   setText( "^7Enemies Left: ^1" + remain )
	// every render tick. setText() allocates a CONFIGSTRING per distinct string, and
	// the engine's table is tiny (~469 slots, hard limit, inherent to the engine — no
	// setTextUnlimited on IW5, that's a Black Ops-only builtin). So every distinct
	// enemy count burned its own permanent slot: a 200-enemy wave = 200 slots gone,
	// and once the table filled the whole server threw
	//   G_FindConfigstringIndex: overflow (469): 'Enemies Left: 202'
	// and kicked players to the main menu. Confirmed as OUR bug, not the mod's —
	// LastDemon99 (mod author) correctly identified our on-screen text as a
	// contributor, and this exact string is what the error dialog quoted.
	// FIX: split into a STATIC label (setText once = exactly 1 configstring, ever)
	// plus a NUMERIC element using setValue(), which sends an int in the hudelem
	// state and allocates ZERO configstrings. setvalue() is confirmed real+used on
	// IW5 — the survival mod itself uses it for the XP popup
	// (globallogic.gsc: self.hud_xppointspopup setvalue(...)).
	ec = self createFontString( "hudsmall", 0.9 );
	ec setPoint( "TOPRIGHT", "TOPRIGHT", getDvarInt( "bpg_enemyhud_x" ) - getDvarInt( "bpg_enemyhud_gap" ), getDvarInt( "bpg_enemyhud_y" ) );
	ec.color = ( 1, 1, 1 );
	ec.alpha = 0;
	ec.hidewheninmenu = true;
	ec.archived = false;
	ec setText( "^7Enemies Left:" );   // set ONCE - never rebuilt per tick
	self.bpg_enemyhud = ec;

	en = self createFontString( "hudsmall", 0.9 );
	en setPoint( "TOPRIGHT", "TOPRIGHT", getDvarInt( "bpg_enemyhud_x" ), getDvarInt( "bpg_enemyhud_y" ) );
	en.color = ( 1, 0, 0 );
	en.alpha = 0;
	en.hidewheninmenu = true;
	en.archived = false;
	self.bpg_enemyhud_num = en;

	// --- kill-feed lines (stacked under the counter, newest at top) ---
	// ⚠️ 2026-07-24 CONFIGSTRING FIX #2. This used to be ONE element per line doing
	//   setText( "^7" + killerName + " ^1" + enemyLabel )
	// which burns a configstring per DISTINCT COMBINATION - (every player who ever
	// gets a kill) x (22 enemy-type labels) - so it grew without bound as more people
	// played, on every map. Second contributor to the G_FindConfigstringIndex
	// overflow (469) crash alongside the Enemies Left counter above.
	// FIX (the engine's own approach - this is exactly what stock's obituary/kill-feed
	// does, see maps\mp\gametypes\_hud_message.gsc which calls setplayernamestring for
	// leaderboard names): split each line into TWO elements -
	//   * NAME element  -> setPlayerNameString( player ), which renders a name by
	//     client index and allocates ZERO configstrings, no matter how many players.
	//   * LABEL element -> setText( label ), bounded by the 22 hardcoded enemy-type
	//     strings and deduped by the engine, so 22 slots TOTAL, permanently capped.
	// The label is anchored TOPRIGHT (fixed right edge) and the name is PARENTED to it
	// right-to-left, so the pair reads "Name Label" and self-positions regardless of
	// how wide either string is (GSC can't measure text width, so parenting is the
	// only way to lay this out correctly).
	feedlines = 4;
	self.bpg_feedlines = [];
	self.bpg_feednames = [];
	for ( i = 0; i < feedlines; i++ )
	{
		lbl = self createFontString( "hudsmall", 0.72 );
		lbl setPoint( "TOPRIGHT", "TOPRIGHT", getDvarInt( "bpg_feed_x" ), getDvarInt( "bpg_feed_y" ) + i * 14 );
		lbl.color = ( 1, 0, 0 );
		lbl.alpha = 0;
		lbl.hidewheninmenu = true;
		lbl.archived = false;
		self.bpg_feedlines[ i ] = lbl;

		// ⚠️ 2026-07-24 v2: the first attempt parented this to the label and used
		// setPoint("RIGHT","LEFT",...) hoping the engine would tuck it just left of
		// the label regardless of text width. It does NOT - live result was the name
		// and label drawing ON TOP of each other ("IILOVEN"+"SOLDIER" superimposed).
		// GSC can't measure text width, so the only reliable layout is FIXED COLUMNS:
		// right-align the name at its own absolute x, far enough left to clear the
		// widest label ("Riot Shield Juggernaut"). Gap is dvar-tunable live so it can
		// be nudged without a restart.
		nm = self createFontString( "hudsmall", 0.72 );
		nm setPoint( "TOPRIGHT", "TOPRIGHT", getDvarInt( "bpg_feed_x" ) - getDvarInt( "bpg_feed_namegap" ), getDvarInt( "bpg_feed_y" ) + i * 14 );
		nm.color = ( 1, 1, 1 );
		nm.alpha = 0;
		nm.hidewheninmenu = true;
		nm.archived = false;
		self.bpg_feednames[ i ] = nm;
	}
	self.bpg_feedbuf = [];

	self thread bpg_killfeed_listen();
	self thread bpg_killlog_render();
}

// Prepend each kill to this player's feed buffer (every client shows all kills).
bpg_killfeed_listen()
{
	self endon( "disconnect" );
	level endon( "game_ended" );

	for ( ;; )
	{
		level waittill( "bpg_enemy_killed", killer, weapLabel );

		entry = spawnStruct();
		entry.killer = killer;      // ENTITY - rendered via setPlayerNameString (0 configstrings)
		entry.label = weapLabel;    // one of exactly 22 hardcoded enemy-type strings
		entry.time = getTime();

		newbuf = [];
		newbuf[ 0 ] = entry;
		for ( i = 0; i < self.bpg_feedbuf.size; i++ )
			newbuf[ i + 1 ] = self.bpg_feedbuf[ i ];
		self.bpg_feedbuf = newbuf;
	}
}

// Single render loop: refreshes the enemy count + draws/fades the feed. Doing both
// here (instead of per-line timers) keeps expiry race-free.
bpg_killlog_render()
{
	self endon( "disconnect" );
	level endon( "game_ended" );

	lifetime = 6000; // ms a line stays before it fades
	fade = 1000;     // ms fade tail

	for ( ;; )
	{
		// re-read tunable positions so live nudges apply without a restart
		self.bpg_enemyhud setPoint( "TOPRIGHT", "TOPRIGHT", getDvarInt( "bpg_enemyhud_x" ) - getDvarInt( "bpg_enemyhud_gap" ), getDvarInt( "bpg_enemyhud_y" ) );
		self.bpg_enemyhud_num setPoint( "TOPRIGHT", "TOPRIGHT", getDvarInt( "bpg_enemyhud_x" ), getDvarInt( "bpg_enemyhud_y" ) );

		// enemies remaining this wave
		// ⚠️ NEVER call setText() here - see the configstring note at element creation.
		// The label is static; only the NUMBER changes, and it goes through setValue()
		// which costs zero configstrings no matter how many distinct values it shows.
		if ( isDefined( level.bots_total_count ) && level.bots_total_count > 0 )
		{
			deaths = 0;
			if ( isDefined( level.bots_deaths ) )
				deaths = level.bots_deaths;
			remain = level.bots_total_count - deaths;
			if ( remain < 0 )
				remain = 0;
			self.bpg_enemyhud_num setValue( remain );
			self.bpg_enemyhud.alpha = 1;
			self.bpg_enemyhud_num.alpha = 1;
		}
		else
		{
			self.bpg_enemyhud.alpha = 0;
			self.bpg_enemyhud_num.alpha = 0;
		}

		// feed: prune expired, then render survivors top-down with a fade tail
		now = getTime();
		pruned = [];
		for ( i = 0; i < self.bpg_feedbuf.size; i++ )
		{
			if ( now - self.bpg_feedbuf[ i ].time < lifetime )
				pruned[ pruned.size ] = self.bpg_feedbuf[ i ];
		}
		self.bpg_feedbuf = pruned;

		for ( i = 0; i < self.bpg_feedlines.size; i++ )
		{
			h = self.bpg_feedlines[ i ];
			nm = self.bpg_feednames[ i ];
			// both elements are positioned absolutely in fixed columns (parenting did
			// NOT work - see the note at element creation).
			h setPoint( "TOPRIGHT", "TOPRIGHT", getDvarInt( "bpg_feed_x" ), getDvarInt( "bpg_feed_y" ) + i * 14 );
			nm setPoint( "TOPRIGHT", "TOPRIGHT", getDvarInt( "bpg_feed_x" ) - getDvarInt( "bpg_feed_namegap" ), getDvarInt( "bpg_feed_y" ) + i * 14 );

			// the killer can disconnect while their kill is still on screen - a stale
			// entity would make setPlayerNameString fail, so drop the line instead.
			valid = i < self.bpg_feedbuf.size;
			if ( valid )
			{
				e = self.bpg_feedbuf[ i ];
				valid = isDefined( e.killer ) && isPlayer( e.killer );
			}

			if ( valid )
			{
				e = self.bpg_feedbuf[ i ];
				h setText( e.label );              // 22 possible values, deduped by the engine
				nm setPlayerNameString( e.killer );  // ZERO configstrings

				age = now - e.time;
				a = 1;
				if ( age > lifetime - fade )
					a = ( lifetime - age ) / ( fade + 0.0 );
				if ( a < 0 ) a = 0;
				if ( a > 1 ) a = 1;
				h.alpha = a;
				nm.alpha = a;
			}
			else
			{
				h.alpha = 0;
				nm.alpha = 0;
			}
		}

		wait 0.2;
	}
}
