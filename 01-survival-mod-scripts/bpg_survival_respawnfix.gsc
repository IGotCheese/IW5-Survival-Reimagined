// bpg_survival_respawnfix.gsc -- SURVIVAL SERVER ONLY (isolated storage).
// 2026-07-16: "while processing instruction OP_wait" flood at
//   botwaitrespawn <- patch_waitrespawn <- waitandspawnclient <- spawnclient
// Trigger: HARD difficulty (first voted tonight) sets botRespawnDelayMin=0, Max=1.
// The mod's botWaitRespawn does:
//   delay = randomIntRange(0, 2)            -> 0 about half the time
//   wait randomFloatRange(delay-0.5, delay+0.5)  -> NEGATIVE wait -> OP_wait error,
// killing that bot's respawn thread. Easy(3-6)/Normal(1-3) never produce delay=0,
// which is why this only appeared when hard mode first ran.
// Fix: replaceFunc with a copy that clamps the wait to >= 0.05s. bothandler.gsc
// loads on every survival map, so the detour always resolves.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( lethalbeats\survival\bothandler::botWaitRespawn, ::botwaitrespawn_safe );
}

botwaitrespawn_safe()
{
	level endon( "game_ended" );
	self endon( "disconnect" );

	for ( ;; )
	{
		if ( !level.bots_awaits ) level waittill( "release_bots" );
		if ( level.bots_awaits )
		{
			level.bots_awaits--;
			difficulty = self lethalbeats\survival\difficulty::difficulty_get_bot_settings();
			delayMin = int( difficulty[ "botRespawnDelayMin" ] );
			delayMax = int( difficulty[ "botRespawnDelayMax" ] );
			if ( delayMax < delayMin ) delayMax = delayMin;
			if ( delayMin || delayMax )
			{
				delay = randomIntRange( delayMin, delayMax + 1 );
				waitTime = randomFloatRange( delay - 0.5, delay + 0.5 );
				if ( waitTime < 0.05 ) waitTime = 0.05; // hard mode: delay can be 0 -> negative wait -> OP_wait error
				wait waitTime;
			}
			break;
		}
	}
}
