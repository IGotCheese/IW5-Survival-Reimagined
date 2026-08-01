// yourserver.gg 2026-07-17 — guard maps\mp\_animatedmodels::animatemodel for ported maps.
// Ported maps (sharqi, and likely other CoD4/BF ports) carry ents with targetname
// "animated_model" whose .model is a foreign model with NO entry in
// level.anim_prop_models -> the stock animatemodel() hits 4 runtime errors PER ENTITY
// at map load (getarraykeys/size/randomint/index on undefined) = hundreds-line storm.
// replaceFunc guard skips ents with no anim table entry (they stay visible as static
// props, which is all they can be on IW5 anyway). replaceFunc (not a whole-file
// override) per the proven _destructible lesson; _animatedmodels is in the common
// fastfile loaded on EVERY map, so the compile-time ref always links.

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	replaceFunc( maps\mp\_animatedmodels::animatemodel, ::bpg_animatemodel_safe );
}

bpg_animatemodel_safe()
{
	if ( isDefined( self.animation ) )
		anim_name = self.animation;
	else
	{
		// the guard the stock function lacks
		if ( !isDefined( level.anim_prop_models ) || !isDefined( level.anim_prop_models[ self.model ] ) )
			return;

		keys = getArrayKeys( level.anim_prop_models[ self.model ] );
		if ( keys.size == 0 )
			return;

		anim_name = level.anim_prop_models[ self.model ][ keys[ randomInt( keys.size ) ] ];
	}

	if ( !isDefined( anim_name ) )
		return;

	self scriptModelPlayAnim( anim_name );
	self willNeverChange();
}
