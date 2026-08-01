// bpg_survival_scoreboard.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-16.
// FIX: scoreboard kills undercounted. The mod's bot_kill only increments the
// scoreboard kill fields (pers["kills"] / .kills) INSIDE `if (self bot_is_killstreak())`
// — i.e. only for special enemies (jugg/chopper/pavelow/reaper/tank/airstrike/
// predator/counteruav/emp). Regular grunt kills give money but never bump the
// displayed kill count, so the scoreboard shows a tiny fraction of real kills.
// FIX = replaceFunc bot_kill with a byte-for-byte copy that increments the kill
// count on EVERY allied kill (gate removed), so the scoreboard reflects all kills.
// Everything else (money, wave_end, cleanup) is unchanged.
// (Deaths already track correctly via damage.gsc handlenormaldeath's incPlayerStat;
// survivors only register a death on a real death, not a revived down — expected.)
// utility.gsc loads on every survival map -> replaceFunc always resolves.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

#include lethalbeats\survival\utility;

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( lethalbeats\survival\utility::bot_kill, ::bpg_bot_kill_countall );
}

// Copy of lethalbeats\survival\utility::bot_kill — ONLY change: pers["kills"]++ /
// .kills++ moved OUT of the bot_is_killstreak() gate so every kill counts.
bpg_bot_kill_countall( attacker )
{
	if ( isDefined( attacker ) && isDefined( attacker.team ) && attacker.team == "allies" )
	{
		if ( isDefined( attacker.owner ) )
		{
			attacker.owner.summary[ "kills" ]++;
			attacker.owner survivor_give_score( int( self.botPrice / 2 ) );

			attacker.owner.pers[ "kills" ]++;
			attacker.owner.kills++;
		}
		else if ( isPlayer( attacker ) )
		{
			attacker.summary[ "kills" ]++;
			attacker survivor_give_score( int( self.botPrice ) );

			attacker.pers[ "kills" ]++;
			attacker.kills++;
		}
	}
	if ( isPlayer( self ) )
	{
		self suicide();
		self thread bot_delete_AfterAWhile();
	}
	level.bots_deaths++;
	if ( level.bots_total_count == level.bots_deaths ) level notify( "wave_end" );
	if ( level.bots_deaths % 15 == 0 ) thread bot_clear_models();
}
