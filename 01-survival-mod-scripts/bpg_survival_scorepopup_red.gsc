// bpg_survival_scorepopup_red.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-16 (v2).
// User: "the +100 in the center of the screen should be red."
// v1 FAILED because of init ORDER: the mod's globallogic patch does
//   replacefunc(_gamescore::givePlayerScore -> patch_giveplayerscore) which threads the
//   stock _rank::xpPointsPopup symbol, and the mod ALSO detours that stock symbol to its
//   own patch_xppointspopupfinalize — with a HARDCODED pale-green (0.7,1,0.7) that
//   ignores the color argument. Mod scripts init AFTER loose scripts, so the mod's
//   detour overwrote mine and my red copy never ran. (Same ordering killed airdrop v2.)
// v2 = two belts, either one suffices:
//   (a) at init, detour the MOD's own patch_xppointspopupfinalize (nothing ever
//       re-replaces mod symbols — proven by the bot_kill scoreboard detour), and
//   (b) one server frame later (all init()s done), re-detour the stock symbol so ours
//       is deliberately LAST.
// The red copy mirrors the MOD's popup byte-for-byte (same center position + fly-to-
// money-counter animation + animate_money handoff) with (1,0,0) instead of (0.7,1,0.7).
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

#include maps\mp\_utility;
#include lethalbeats\survival\utility;

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	// belt (a): detour the mod's own popup function
	replaceFunc( lethalbeats\survival\patch\globallogic::patch_xppointspopupfinalize, ::bpg_xppointspopup_red );

	// belt (b): win the stock-symbol race by re-applying after every init has run
	level thread bpg_redetour_stock_popup();
}

bpg_redetour_stock_popup()
{
	// all script init()s (mod included) run during map load, before the first server
	// frame — waiting one frame guarantees ours is the final detour on the stock symbol
	wait 0.1;
	replaceFunc( maps\mp\gametypes\_rank::xppointspopup, ::bpg_xppointspopup_red );
}

// Copy of the mod's patch_xppointspopupfinalize — ONLY change: red instead of pale green.
bpg_xppointspopup_red( amount, bonus, hudColor, glowAlpha )
{
	if ( isDefined( self.team ) && self.team == "axis" )
		return;

	self endon( "disconnect" );
	self endon( "joined_team" );
	self endon( "joined_spectators" );

	if ( amount == 0 )
		return;
	if ( !isDefined( self ) || !isPlayer( self ) )
		return;

	if ( !isDefined( self.hud_xpPointsPopup ) )
	{
		self.hud_xpPointsPopup = self maps\mp\gametypes\_rank::createXpPointsPopup();
		self.xpupdatetotal = 0;
		self.bonusupdatetotal = 0;
	}

	self.hud_xpPointsPopup.x = 30;
	self.hud_xpPointsPopup.y = -50;

	self notify( "xpPointsPopup" );
	self endon( "xpPointsPopup" );
	self.xpupdatetotal += amount;
	self.bonusupdatetotal += bonus;
	wait 0.05;

	if ( self.xpupdatetotal < 0 )
		self.hud_xppointspopup.label = &"";
	else
		self.hud_xppointspopup.label = &"MP_PLUS";

	// THE change: bright red (mod hardcodes (0.7, 1, 0.7) pale green here)
	self.hud_xppointspopup.color = ( 1, 0, 0 );
	self.hud_xppointspopup.glowcolor = ( 1, 0, 0 );
	self.hud_xppointspopup.glowalpha = 0;
	self.hud_xppointspopup setValue( self.xpupdatetotal );
	self.hud_xppointspopup.alpha = 0.85;
	self.hud_xppointspopup thread maps\mp\gametypes\_hud::fontPulse( self );

	increment = max( int( self.bonusupdatetotal / 20 ), 1 );

	if ( self.bonusupdatetotal )
	{
		while ( self.bonusupdatetotal > 0 )
		{
			self.xpupdatetotal += min( self.bonusupdatetotal, increment );
			self.bonusupdatetotal -= min( self.bonusupdatetotal, increment );
			self.hud_xppointspopup setValue( self.xpupdatetotal );
			wait 0.05;
		}
	}
	else
		wait 1.0;

	self.hud_xpPointsPopup moveOverTime( 0.5 );
	score_str = "" + self.pers[ "score" ];
	self.hud_xpPointsPopup.x -= 400 - score_str.size * 20;
	self.hud_xpPointsPopup.y += 275;
	self.xpupdatetotal = 0;

	wait 0.75;
	self.hud_xppointspopup fadeOverTime( 0.75 );
	self.hud_xppointspopup.alpha = 0;
	self setClientDvar( "ui_money", self.pers[ "score" ] );
	self lethalbeats\survival\utility::survivor_display_hud( "animate_money" );

	self notify( "ScorePopComplete" );
}
