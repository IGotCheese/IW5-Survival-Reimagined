// bpg_survival_airdropcleanupfix.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-19.
// Task #39: hit a genuine infinite-loop crash during side-test wave-forcing —
// lethalbeats\Survival\killstreaks\_airdrop.gsc's _clearSurvivorAirdrop() ->
// lethalbeats\array::array_remove_index() went into hundreds of runtime errors/frame
// ("cannot cast undefined to bool", "size cannot be applied to integer/undefined") and
// the engine killed the thread as a potential infinite loop.
// ROOT CAUSE INVESTIGATION: reproducing this required forcibly firing "wave_end" on a
// timer with ZERO real players/bots ever connected (my own bpg_unblock_probe.gsc
// wave-forcing hack, since reverted - see that file's header). _clearSurvivorAirdrop
// only ever runs on a killstreak crate that a REAL player threw (self.owner is the
// throwing player; self.owner.airdrops is that player's own tracked-airdrops array,
// populated in _airdropmarkeractivate). In a real playthrough this path requires an
// actual player to have called an airdrop-type ability - the crash could not be
// independently reproduced with a normal (non-forced) wave sequence, and no live
// report of this exact error has surfaced. Verdict: LIKELY a test-harness artifact,
// not a reachable live bug - but the guard below is free and closes the whole error
// class regardless of what exactly corrupts self.owner.airdrops, so it stays in.
// FIX: replaceFunc a copy of _clearSurvivorAirdrop that bails safely if self.owner or
// self.owner.airdrops isn't in the expected shape, instead of indexing/iterating blind.

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( lethalbeats\survival\killstreaks\_airdrop::_clearSurvivorAirdrop, ::bpg_clearSurvivorAirdrop_safe );
}

bpg_clearSurvivorAirdrop_safe()
{
	if ( !isDefined( self.airdropId ) )
		return;
	if ( !isDefined( self.owner ) )
		return;

	airdrops = self.owner.airdrops;
	if ( !isDefined( airdrops ) || !isDefined( airdrops.size ) )
		return;

	airdropIndex = undefined;

	for ( i = 0; i < airdrops.size; i++ )
	{
		if ( !isDefined( airdrops[ i ] ) || !isDefined( airdrops[ i ][ 2 ] ) )
			continue;
		if ( self.airdropId == airdrops[ i ][ 2 ] )
		{
			airdropIndex = i;
			break;
		}
	}

	if ( isDefined( airdropIndex ) )
		self.owner.airdrops = lethalbeats\array::array_remove_index( self.owner.airdrops, airdropIndex );
}
