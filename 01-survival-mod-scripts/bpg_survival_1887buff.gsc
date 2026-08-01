// bpg_survival_1887buff.gsc — SURVIVAL SERVER ONLY (isolated storage). 2026-07-16.
// User: "copy the 1887 buffs from the other server."
// Main server (C:\Ops\storage-overrides\...\_callbacksetup.gsc): Model 1887 =
// damage x3.50 + a distance-weighted range boost (x(1 + 2.50*distfactor), distfactor
// ramps 0->1 between 300 and 1200 units) so the gun stays lethal further out.
// Survival's bot damage doesn't go through callbackPlayerDamage — the mod scales it in
// botHandler::weaponDamageModifier (its stock 1887 case is a flat x1.5). This is a
// byte-copy of that MOD function with the 1887 case swapped to main's formula.
// Detouring a MOD symbol has no init-order race (nothing re-replaces mod functions —
// proven by the bot_kill scoreboard detour).
// Tune live:  set bpg_1887_dmgmult 3.5   /  set bpg_1887_rangemult 2.5
//
// 2026-07-19: also owns "increase shotgun damage against dogs by 120 percent" (+120% = x2.2).
// This is the ONLY file that may replaceFunc lethalbeats\survival\bothandler::weaponDamageModifier
// (see gsc-code-quality-practices memory — only one replaceFunc per target wins; a second
// competing file would silently do nothing) so any future weaponDamageModifier tweak belongs
// HERE, not in a new file. Tune live: set bpg_shotgun_vs_dog_mult 2.2
// ⚠️ NEVER copy to the live <MP-PORT> server (references lethalbeats\* scripts).

#include lethalbeats\survival\utility;

init()
{
	if ( getDvar( "g_gametype" ) != "survival" )
		return;

	if ( getDvar( "bpg_1887_dmgmult" ) == "" )
		setDvar( "bpg_1887_dmgmult", "3.5" );
	if ( getDvar( "bpg_1887_rangemult" ) == "" )
		setDvar( "bpg_1887_rangemult", "2.5" );
	if ( getDvar( "bpg_shotgun_vs_dog_mult" ) == "" )
		setDvar( "bpg_shotgun_vs_dog_mult", "2.2" );

	replaceFunc( lethalbeats\survival\bothandler::weaponDamageModifier, ::bpg_weaponDamageModifier_1887 );
}

// Copy of the mod's weaponDamageModifier — ONLY change: the iw5_1887 case uses the
// main server's damage+range formula instead of the mod's flat x1.5.
bpg_weaponDamageModifier_1887( weapon, damage, meansOfDeath, attacker, isExplosiveDamage )
{
	if ( weapon == "artillery_mp" || isExplosiveDamage )
		return damage * 3;
	if ( meansOfDeath == "MOD_HEAD_SHOT" )
		damage *= 1.5;

	weaponClass = lethalbeats\weapon::weapon_get_class( weapon );

	// user: "increase shotgun damage against dogs by 120 percent" - +120% = x2.2. Scales the
	// INPUT damage before any of the per-weapon branches below, so it stacks on top of
	// whatever multiplier a specific shotgun (1887/KSG/alt-fire) already gets, rather than
	// replacing it - a SPAS-12/USAS-12/Striker (currently unbuffed, falls to default) still
	// gets the full +120% against dogs even though it has no other special case here.
	if ( weaponClass == "shotgun" && self bot_is_dog() )
		damage *= getDvarFloat( "bpg_shotgun_vs_dog_mult" );

	if ( weaponClass == "riot" )
		return damage;
	if ( weaponClass == "sniper" )
		return self bot_is_jugger() ? damage * 1.5 : damage * 4;

	if ( lethalbeats\string::string_starts_with( weapon, "alt_" ) && isSubStr( weapon, "shotgun" ) )
		return damage * 4;

	switch ( lethalbeats\weapon::weapon_get_baseName( weapon ) )
	{
		case "iw5_deserteagle":
		case "iw5_44magnum":
			return damage * 4;
		case "iw5_mp412":
		case "iw5_ksg":
			return damage * 2.5;
		case "iw5_mk14":
			return damage * 2;
		case "iw5_1887":
			return self bpg_1887_damage( damage, attacker );
		default:
			return damage;
	}
}

// Main-server 1887 formula, ported. self = the bot taking the hit.
bpg_1887_damage( damage, attacker )
{
	dmgmult = getDvarFloat( "bpg_1887_dmgmult" );
	rangemult = getDvarFloat( "bpg_1887_rangemult" );
	if ( dmgmult <= 0 )
		dmgmult = 1;

	newdmg = damage * dmgmult;

	// range buff: ~0 up close, full boost at long range (counters shotgun falloff)
	if ( isDefined( attacker ) && isDefined( attacker.origin ) && isDefined( self.origin ) )
	{
		dist = distance( attacker.origin, self.origin );
		distfactor = ( dist - 300 ) / 900;

		if ( distfactor < 0 )
			distfactor = 0;
		else if ( distfactor > 1 )
			distfactor = 1;

		newdmg = newdmg * ( 1 + rangemult * distfactor );
	}

	return int( newdmg + 0.5 );
}
