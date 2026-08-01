// bpg_survival_dialogkeys.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-30.
//
// Fixes the recurring pair of runtime errors seen live on mp_raid:
//     in call to builtin function "issubstr": cannot cast parameter 0 from undefined to string
//         at playleaderdialogonplayer / leaderdialogonplayer / sentry_timeout
//     cannot cast undefined to bool in a control statement
//         (same three frames)
// Those are ONE bug printing twice: issubstr errors and returns undefined, then the `if`
// around it fails to cast that undefined to a bool.
//
// ── ROOT CAUSE ───────────────────────────────────────────────────────────────────────────────
// Stock builds the leader-dialog table in maps\mp\gametypes\_music_and_dialog::init, which the
// survival gametype never runs. The mod hand-rolls a REPLACEMENT subset in
// lethalbeats\survival\patch\globallogic.gsc:155-161 (after `level waittill("prematch_done")`):
//     game["dialog"]["lbguard_destroyed"]      game["dialog"]["remote_sentry_destroyed"]
//     game["dialog"]["sentry_destroyed"]       game["dialog"]["ims_destroyed"]
// Compare stock _music_and_dialog.gsc:120-131, where the four keys the mod copied sit directly
// alongside two it did not:
//     game["dialog"]["sentry_gone"] = "sentry_gone";
//     game["dialog"]["sam_gone"]    = "sam_gone";
// So the sentry *destroyed* path works and the sentry *timeout* path errors — which is exactly
// what the log shows, since _autosentry::sentry_timeout:951-957 is the only caller that asks
// for the "_gone" keys. Enumerated every leaderdialogonplayer key reachable from stock
// killstreak code: ims_destroyed, lbguard_destroyed, sam_gone, sentry_gone. The first two the
// mod already defines, so these two are the complete remainder — not a sample.
//
// ── WHY A LOOSE SCRIPT AND NOT AN .IWD EDIT ──────────────────────────────────────────────────
// game[] is a plain global array, so the table can be completed from outside the mod. That
// avoids repacking LB_Survival.iwd (which is held open by the running servers and would need
// the pending-swap dance plus a restart) and leaves the mod file byte-identical.
//
// Values are stock's, not invented: game["voice"] is already set by the mod at globallogic.gsc
// :155-156, so playleaderdialogonplayer composes the same <voiceprefix>1mc_sentry_gone alias the
// stock game would. Effect is that the sentry-expired callout is restored rather than silenced.
// (There is a documented way to silence one instead — playleaderdialogonplayer:1025 early-returns
// on any value containing "null" — but stock uses it for zero dialogs, so restoring the real
// line is the less surprising choice. To mute it later, set the value to "null" instead.)
//
// ⚠️ NEVER copy to the live <MP-PORT> server — survival gametype only.

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	// Set them RIGHT NOW as well as after prematch_done. v1 only did the latter and the
	// sentry_timeout errors came back in a live session on <SURV-PORT-4> - and because v1 printed
	// nothing, there was no way to tell whether it had run at all, been raced, or been wiped.
	// Writing at both points makes the outcome independent of who wakes first.
	bpg_dialogkeys_apply( "init" );
	level thread bpg_dialogkeys_fill();
}

bpg_dialogkeys_fill()
{
	level endon( "game_ended" );

	// The mod assigns its own keys immediately after this same notify, so wait a beat rather
	// than racing it - whoever wakes first would otherwise win, and this must run second.
	level waittill( "prematch_done" );
	wait 0.05;
	bpg_dialogkeys_apply( "prematch" );

	// Re-assert a few times over the first minute. Something between map load and the first
	// sentry expiry was leaving these unset despite the prematch write; rather than guess which
	// consumer resets game["dialog"], just keep putting them back while the level settles.
	// Cheap: two array writes, ten times, then the thread ends.
	for ( i = 0; i < 10; i++ )
	{
		wait 6;
		bpg_dialogkeys_apply( undefined );
	}
}

// UNGUARDED on purpose. v1 used isDefined() so it would never clobber the mod - but the mod does
// not define these two at all (verified against globallogic.gsc:157-160), and a guard cannot
// repair a key that something else has since set to undefined. These are stock's own values.
bpg_dialogkeys_apply( phase )
{
	if ( !isDefined( game[ "dialog" ] ) )
		game[ "dialog" ] = [];

	had = isDefined( game[ "dialog" ][ "sentry_gone" ] );

	game[ "dialog" ][ "sentry_gone" ] = "sentry_gone";
	game[ "dialog" ][ "sam_gone" ]    = "sam_gone";

	// Report only at the named phases, and only when something was actually missing, so this
	// stays quiet once healthy instead of adding to the console spam.
	if ( isDefined( phase ) && !had )
		println( "[BPG-DIALOGKEYS] " + phase + ": sentry_gone/sam_gone were MISSING - set now" );
}
