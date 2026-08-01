// bpg_survival_c4fix.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-16.
// Fixes upstream OPEN issue #13 ("C4 of dog model gets stuck after death").
// ROOT CAUSE: _martyrdom::giveAbility attaches two weapon_c4 script_models to the
// carrier (dog hips or bot back); the ONLY delete path is watchMartyrdomDetonation's
// "detonate" sequence. A carrier that dies without detonating (dog shot early, corpse
// swept by cleanup) leaves both C4 models floating in the world forever.
// FIX: replaceFunc giveAbility with a copy that also starts a level-context janitor:
// once the carrier is dead/gone (or after a 120s cap), wait 8s so a real detonation
// sequence can finish its own unlink+delete, then delete whatever C4 models remain.
// _martyrdom.gsc loads on every survival map -> replaceFunc always resolves.
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( lethalbeats\survival\abilities\_martyrdom::giveAbility, ::martyrdom_giveability_safe );
	replaceFunc( lethalbeats\survival\abilities\_martyrdom::watchMartyrdomDetonation, ::bpg_watchmartyrdomdetonation_safe );
}

// Copy of _martyrdom::giveAbility + the janitor thread. attachC4/playc4Fx/
// watchMartyrdomDetonation are the mod's own functions, called cross-file.
martyrdom_giveability_safe()
{
	c4_attach = [];
	if ( isDefined( self.dog ) )
	{
		c4_attach[ 0 ] = lethalbeats\survival\abilities\_martyrdom::attachC4( c4_attach, self.dog, "j_hip_base_ri", ( 6, 6, -3 ), ( 0, 0, 0 ) );
		c4_attach[ 1 ] = lethalbeats\survival\abilities\_martyrdom::attachC4( c4_attach, self.dog, "j_hip_base_le", ( -6, -6, 3 ), ( 0, 0, 0 ) );
	}
	else
	{
		c4_attach[ 0 ] = lethalbeats\survival\abilities\_martyrdom::attachC4( c4_attach, self, "j_spine4", ( 0, 6, 0 ), ( 0, 0, -90 ) );
		c4_attach[ 1 ] = lethalbeats\survival\abilities\_martyrdom::attachC4( c4_attach, self, "tag_stowed_back", ( 0, 1, 5 ), ( 80, 90, 0 ) );
	}
	self thread lethalbeats\survival\abilities\_martyrdom::playc4Fx( c4_attach );
	self thread lethalbeats\survival\abilities\_martyrdom::watchMartyrdomDetonation( c4_attach );
	level thread bpg_c4_janitor( self, c4_attach );
}

bpg_c4_janitor( carrier, c4_attach )
{
	level endon( "game_ended" );

	for ( t = 0; t < 120; t++ )
	{
		wait 1;
		if ( !isDefined( carrier ) || !isAlive( carrier ) )
			break;
	}
	// LIVE REGRESSION 2026-07-16: with dog-carried C4 the detonate notify can fire
	// long after the OWNER dies (the dog lives on) — an 8s grace deleted models the
	// detonation sequence still needed (playsound/bullettrace on dead entity).
	// 45s comfortably outlives any legitimate detonation window; the guarded
	// watcher below tolerates whatever remains.
	wait 45;

	for ( i = 0; i < c4_attach.size; i++ )
	{
		if ( isDefined( c4_attach[ i ] ) )
		{
			c4_attach[ i ] unlink();
			c4_attach[ i ] delete();
		}
	}
}

// Guarded copy of _martyrdom::watchMartyrdomDetonation — the original assumes
// c4_attach[0] is alive at detonate time (playsound / .origin reads / bullettrace).
// This version finds the first surviving C4 for positioning, skips dead entries,
// and aborts quietly if nothing remains.
bpg_watchmartyrdomdetonation_safe( c4_attach )
{
	self waittill( "detonate", attacker );

	self.detonate = 1;

	anchor = undefined;
	for ( i = 0; i < c4_attach.size; i++ )
	{
		if ( isDefined( c4_attach[ i ] ) && isDefined( c4_attach[ i ].origin ) )
		{
			anchor = c4_attach[ i ];
			break;
		}
	}

	if ( !isDefined( anchor ) )
	{
		self.detonate = undefined;
		return; // every C4 model is already gone — nothing to blow up
	}

	anchor playSound( "semtex_warning" );

	traceStart = anchor.origin + ( 0, 0, 32 );
	traceEnd = anchor.origin - ( 0, 0, 32 );
	trace = bulletTrace( traceStart, traceEnd, false, undefined );

	upangles = vectorToAngles( trace[ "normal" ] );
	forward = anglesToForward( upangles );
	right = anglesToRight( upangles );

	wait 0.25;
	fxEnt = undefined;
	if ( isDefined( anchor ) && isDefined( anchor.origin ) )
	{
		fxEnt = spawnFx( level._effect[ "laserTarget" ], getGroundPosition( anchor.origin, 12, 0, 32 ), forward, right );
		triggerFx( fxEnt );
	}
	wait 0.25;
	fxEnt2 = undefined;
	if ( isDefined( anchor ) && isDefined( anchor.origin ) )
	{
		fxEnt2 = spawnFx( level._effect[ "laserTarget" ], getGroundPosition( anchor.origin, 12, 0, 32 ), forward, right );
		triggerFx( fxEnt2 );
	}

	wait 1.5;
	for ( i = 0; i < c4_attach.size; i++ )
	{
		if ( !isDefined( c4_attach[ i ] ) || !isDefined( c4_attach[ i ].origin ) )
			continue;

		playFx( level._effect[ "martyrdom_c4_explosion" ], c4_attach[ i ].origin );
		playSoundAtPos( c4_attach[ i ].origin, "detpack_explo_main" );
		earthquake( 0.4, 0.8, c4_attach[ i ].origin, 600 );

		radiusDamage( c4_attach[ i ].origin, 192, 100, 50, attacker, "MOD_EXPLOSIVE" );
		if ( isDefined( c4_attach[ i ] ) )
		{
			c4_attach[ i ] unlink();
			c4_attach[ i ] delete();
		}
		wait 0.5;
	}

	wait 1.5;
	if ( isDefined( fxEnt ) )
		fxEnt delete();
	if ( isDefined( fxEnt2 ) )
		fxEnt2 delete();
	self.detonate = undefined;
}
