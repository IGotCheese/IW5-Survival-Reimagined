// bpg_survival_botfix.gsc — SURVIVAL SERVER ONLY (isolated storage).
// 2026-07-16: console flood "in call to builtin method gettagorigin" at
// checktraceforbone <- patch_target_loop (the mod's bot targeting calls Bot
// Warfare's checkTraceForBone on entities that lack humanoid bones — e.g. the
// player's purchased minigun/GL turrets, or model-less dead survivors). The
// error is INSIDE the builtin and cannot be caught in GSC; at 300+/sec it
// floods the console and its thread-kills break other scripts (stuck red
// overlays, dead revive monitors).
//
// This is the LIVE <MP-PORT> server's battle-tested "safe-bone" fix (from its
// patched z_svr_bots.iwd _bot_internal.gsc), ported as a loose replaceFunc.
// The full fixed _bot_internal (which also guards the aim_loop sites) lands
// via the z_svr_bots.iwd.new swap in LAUNCH-SURVIVAL.bat at the next process
// restart; this loose copy is then redundant but harmless (identical logic).
// ⚠️ NEVER copy to the live <MP-PORT> server (it already has the fix in its iwd).

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( maps\mp\bots\_bot_internal::checkTraceForBone, ::checktraceforbone_safe );
}

checktraceforbone_safe( myEye, bone )
{
	boneLoc = bpg_safebonepos( self, bone );

	if ( !isDefined( boneLoc ) )
		return false;

	trace = bullettrace( myEye, boneLoc, false, undefined );

	return ( sighttracepassed( myEye, boneLoc, false, undefined ) && ( trace[ "fraction" ] >= 1.0 || trace[ "surfacetype" ] == "glass" ) );
}

// gettagorigin throws an uncatchable console script error when the model lacks
// the bone. Guaranteed-safe reference points instead: head/chest ~= eye position,
// anything else ~= entity origin. Vision behaves the same for all practical purposes.
bpg_safebonepos( ent, bone )
{
	if ( !isDefined( ent ) )
		return undefined;

	if ( isPlayer( ent ) )
	{
		if ( bone == "j_head" || bone == "j_spine4" || bone == "j_spineupper" )
			return ent getEye();

		return ent.origin;
	}

	if ( isDefined( ent.origin ) )
		return ent.origin;

	return undefined;
}
