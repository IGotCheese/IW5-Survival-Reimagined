// bpg_survival_groups.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-22.
// Assigns ServerControl groups (admin permissions) to specific GUIDs.
//
// WHY THIS EXISTS / the bug it fixes:
//   The real bootstrap is scripts/LB_ServerControl.gsc INSIDE LB_ServerControl.iwd
//   (the .iwd copy overrides the loose scripts/LB_ServerControl.gsc — proven, see
//   bpg_survival_servercontrolfix.gsc). That iwd bootstrap only does
//   giveGroup("01000000BBBBBBBB", DEVELOPER) — a placeholder GUID. Any
//   giveGroup added to the LOOSE LB_ServerControl.gsc NEVER RUNS, so the server owner
//   (01000000AAAAAAAA) had no group -> power 0 -> "!map: no permission".
//
//   giveGroup writes level.players_data[guid], but groups::init() does
//   `level.players_data = []` (a full reset). Running giveGroup in a normal init()
//   races the framework's groups::init and can be wiped. So we RE-ASSERT on a short
//   delay, after every synchronous init()/groups::init() has finished — the same
//   proven pattern bpg_survival_servercontrolfix.gsc uses for the dev-cmd lockdown.
//
// To add more staff: add giveGroup(<guid>, <GROUP>) lines in assignGroups().
// Groups: GUEST 0, DEVELOPER 1, OWNER 2, ADMIN 3, MODERATOR 4, VIP 5.
// Powers (groups.gsc): OWNER/DEVELOPER 100, ADMIN 70, MODERATOR 40, GUEST 0.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

#include lethalbeats\servercontrol\groups;

#define GUEST      0
#define DEVELOPER  1
#define OWNER      2
#define ADMIN      3
#define MODERATOR  4
#define VIP        5

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	level thread assignGroups();
}

assignGroups()
{
	level endon( "game_ended" );

	// Re-assert a few times so we always land AFTER the framework's groups::init()
	// reset (which happens during the init phase, on frame 0).
	for ( pass = 0; pass < 3; pass++ )
	{
		wait 0.5 + pass;
		if ( !isDefined( level.players_data ) )
			continue;

		// ── staff GUIDs ──────────────────────────────────────────────
		giveGroup( "01000000AAAAAAAA", OWNER );      // <server owner - replace with your own GUID>
	}
}
