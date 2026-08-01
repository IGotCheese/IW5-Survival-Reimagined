// bpg_survival_selfrevivefix.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-16.
// Fixes upstream OPEN issues #15 ("Self-revive doesn't tick between waves") and #9
// ("Self-revive sometimes breaks, softlocking the match") — the user's original
// "bar never revives me" report.
// ROOT CAUSE (proven from source): survivor_revive()'s FIRST line is
// `self notify("revive")`, and lastStandWaveEndFailsafe — the thread that auto-
// revives a downed player when the wave ends — has `self endon("revive")`. So the
// failsafe calls survivor_revive(), whose first statement TERMINATES THE THREAD
// EXECUTING IT. The rest of the revive never runs: no engine laststandrevive(), no
// flag clearing, no bar cleanup → frozen bar (#15) / "partially dead" ghost (#9).
// The two paths without a "revive" endon (bar completing 10s, kill-while-down)
// work fine, which is why the bug only bites when downed across a wave end.
// FIX: replaceFunc the failsafe with a copy that runs survivor_revive on a DETACHED
// thread (no "revive" endon), so the self-notify can't kill its own executor.
// survivorhandler.gsc loads on every survival map -> replaceFunc always resolves.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( lethalbeats\survival\survivorhandler::lastStandWaveEndFailsafe, ::laststand_waveend_failsafe_safe );
}

laststand_waveend_failsafe_safe()
{
	level endon( "game_ended" );
	self endon( "disconnect" );
	self endon( "death" );
	self endon( "revive" );

	for ( ;; )
	{
		level waittill( "wave_end" );
		if ( !isDefined( self.inLastStand ) || !self.inLastStand )
			continue;
		if ( !isDefined( self.lastStandBar ) || !isDefined( self.lastStandBar.type ) )
			continue;

		if ( self.lastStandBar.type == "revive" )
		{
			self notify( "auto_revive" );
			self thread bpg_detached_revive(); // detached: survives survivor_revive's own notify("revive")
			break;
		}

		if ( self.lastStandBar.type == "death" && !lethalbeats\survival\utility::survivors( true ).size )
		{
			self maps\mp\_utility::playDeathSound();
			self lethalbeats\survival\utility::player_clear_last_stand();
			self suicide();
			break;
		}
	}
}

bpg_detached_revive()
{
	self endon( "disconnect" );
	self lethalbeats\survival\utility::survivor_revive();
}
