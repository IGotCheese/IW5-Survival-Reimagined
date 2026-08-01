// bpg_survival_airdrop_cooldown.gsc — SURVIVAL SERVER ONLY (isolated storage).
// 2026-07-16, user: "care packages ... you can call them in infinitely" -> endless
// red smoke walls. The mod's Air Support armory has NO purchase cooldown (money is
// the only limiter). This detours the shop's onSelectOption to gate CRATE purchases
// (minigun/GL turret crates + every perk care package) behind a per-player cooldown.
// Gating happens BEFORE onBuy, so a refused purchase charges nothing.
// Predator missile / precision airstrike are NOT crates and stay uncooldowned.
//
// Tune live:  rcon set survival_airdrop_cooldown <seconds>   (0 = off)
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* -> boot death).

init()
{
    if ( getDvar( "g_gametype" ) != "survival" )
        return;

    if ( getDvar( "survival_airdrop_cooldown" ) == "" )
        setDvar( "survival_airdrop_cooldown", "60" );

    replaceFunc( lethalbeats\survival\armories\air_support::onSelectOption, ::onselectoption_cooldown );
}

// Original signature: onSelectOption(page, item, price, option_type, index)
// self = the shop struct, self.owner = the buying player.
// Constants inlined from air_support.gsc: OPTION_BUY -5, OPTION_SCRIPTRESPONSE -1,
// AIR_SUPPORT_MAIN 0, AIR_SUPPORT_PERKS 1, AIR_SUPPORT_REMOVE_PERKS 2,
// MINIGUN_TURRET 3, GL_TURRET 4.
onselectoption_cooldown( page, item, price, option_type, index )
{
    if ( option_type == -5 )
    {
        // Crate-ish = turret crates (main page idx 3/4), every perk care package
        // (page 1), and any main-page killstreak whose name contains "airdrop"
        // (the plain care packages go through giveKillstreak and slipped past v1 —
        // user: "throw unlimited smokes ... unlimited care packages").
        isCrate = false;
        if ( self.page == 0 )
            isCrate = ( index == 3 || index == 4 || isSubStr( tolower( item + "" ), "airdrop" ) );
        // page 1 = PERKS: exempt from cooldown/wave-cap (user 2026-07-17). Perks now grant
        // INSTANTLY (giveAirDrop instant-perk hook) with no red-smoke care package to spam
        // — the cooldown only ever existed to stop physical crate spam. isCrate stays false.

        if ( isCrate && !self.owner bpg_airdrop_ready() )
            return;

        self lethalbeats\survival\armories\air_support::onBuy( item, price, index );

        if ( isCrate )
            self.owner bpg_airdrop_mark();
    }
    else if ( option_type == -1 )
        self lethalbeats\survival\armories\air_support::onResponse( item );
}

bpg_airdrop_ready()
{
    // v3: HARD per-wave cap on top of the cooldown — the cooldown alone only
    // PACED the spam (one crate per 60s each, forever = "still infinite").
    // Dvar bpg_airdrop_wave_cap (default 2, 0 = uncapped) tunes it live.
    cap = 2;
    if ( getDvar( "bpg_airdrop_wave_cap" ) != "" )
        cap = getDvarInt( "bpg_airdrop_wave_cap" );

    if ( cap > 0 )
    {
        wave = 0;
        if ( isDefined( level.wave_num ) )
            wave = level.wave_num;

        if ( !isDefined( self.bpg_ad_wave ) || self.bpg_ad_wave != wave )
        {
            self.bpg_ad_wave = wave;
            self.bpg_ad_count = 0;
        }

        if ( self.bpg_ad_count >= cap )
        {
            self iPrintLnBold( "^1Care package limit reached for this wave ^7(" + cap + ")" );
            self playLocalSound( "elev_door_interupt" );
            return false;
        }
    }

    cd = getDvarInt( "survival_airdrop_cooldown" );
    if ( cd <= 0 )
        return true;
    if ( !isDefined( self.bpg_nextairdroptime ) || getTime() >= self.bpg_nextairdroptime )
        return true;

    remain = int( ( self.bpg_nextairdroptime - getTime() ) / 1000 ) + 1;
    self iPrintLnBold( "^1Care package on cooldown: ^7" + remain + "s" );
    self playLocalSound( "elev_door_interupt" );
    return false;
}

bpg_airdrop_mark()
{
    cd = getDvarInt( "survival_airdrop_cooldown" );
    if ( cd > 0 )
        self.bpg_nextairdroptime = getTime() + cd * 1000;

    if ( !isDefined( self.bpg_ad_count ) )
        self.bpg_ad_count = 0;
    self.bpg_ad_count++;
}
