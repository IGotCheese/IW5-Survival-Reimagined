// bpg_survival_skillfix.gsc -- SURVIVAL SERVER ONLY (isolated storage).
// 2026-07-16: the single most frequent console error on busy waves:
//   "updateskill: cannot cast parameter 2 from undefined to string"
//   at processkill (maps/mp/_skill.gsc) <- handlenormaldeath (mod damage patch)
// The mod calls maps\mp\_skill::processKill(attacker, victim) on every kill; the
// stock skill-rating code chokes on test-client bots (no stats identity). Skill
// rating is a PvP matchmaking stat -- on a co-op survival server every kill
// involves a bot, so the stat is meaningless here. Replace processKill with a
// no-op: kills 100% of this error class, loses nothing.
// _skill.gsc is stock and loads on every map -> replaceFunc always resolves.
// ⚠️ Do NOT copy to the live <MP-PORT> server -- skill ratings are real in PvP there.

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( maps\mp\_skill::processKill, ::processkill_noop );
}

processkill_noop( attacker, victim )
{
}
