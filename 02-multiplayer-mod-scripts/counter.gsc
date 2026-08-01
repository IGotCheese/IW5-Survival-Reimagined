#include maps\mp\gametypes\_hud_util;

init()
{
    level thread onPlayerConnect();
}

onPlayerConnect()
{
    for(;;)
    {
        level waittill("connected", player);

        player thread onPlayerSpawned();
    }
}

onPlayerSpawned()
{
	self endon("disconnect");
	level endon("game_ended");

	for(;;)
	{
		self waittill("spawned_player");

		if(!issubstr(self getguid() + "", "bot"))
		{
			self thread killstreakCounter();
			self thread gunstreakCounter();
			self thread moabCounter();
			self thread destroyCounterOnGameEnd();
			self thread resetOnDeath();
		}

		break;
	}
}

killstreakCounter()
{
    self endon("disconnect");
    level endon("game_ended");

    self.killStreak = createFontString("Objective", 1);
    self.killStreak setPoint("TOPRIGHT", "TOPERIGHT", -10, 305);
    self.killStreak.label = &"^2K-STREAK: ^7";
    self.killStreak.sort = -3;
    self.killStreak.alpha = 0.9;
    self.killStreak.hideWhenInMenu = true;
    self.killStreak setValue(0);

    killStreak = 0;
    self.savedAssists = 0;
    self.savedKills = 0;

    for(;;)
    {
        if (maps\mp\_utility::_hasperk("specialty_hardline"))
        {
            if(killStreak != maps\mp\_utility::getpersstat( "kills" ) - self.savedKills + floor((self.pers["assistsToKill"] - self.savedAssists) / 2))
            {
                killStreak = maps\mp\_utility::getpersstat( "kills" ) - self.savedKills + floor((self.pers["assistsToKill"] - self.savedAssists) / 2);
                self.killStreak setValue(killStreak);
            }
        } else {
            if(killStreak != maps\mp\_utility::getpersstat( "kills" ) - self.savedKills)
            {
                killStreak = maps\mp\_utility::getpersstat( "kills" ) - self.savedKills;
                self.killStreak setValue(killStreak);
            }
        }

        wait 0.25;
    }
}

gunstreakCounter()
{
    self endon("disconnect");
    level endon("game_ended");

    self.gunStreak = createFontString("Objective", 1);
    self.gunStreak setPoint("TOPRIGHT", "TOPRIGHT", -10, 315);
    self.gunStreak.label = &"^5G-STREAK: ^7";
    self.gunStreak.sort = -3;
    self.gunStreak.alpha = 0.9;
    self.gunStreak.hideWhenInMenu = true;
	self.gunStreak setValue(0);

	gunStreak = 0;

    for (;;)
    {
        if(gunStreak != self.pers["cur_kill_streak_for_nuke"])
        {
			if(gunStreak > self.pers["cur_kill_streak_for_nuke"])
			{
				self iPrintln("^1Died on " + gunStreak);
			}
			gunStreak = self.pers["cur_kill_streak_for_nuke"];
			self.gunStreak setValue(gunStreak);
        }

        wait 0.25;
    }
}

moabCounter()
{
	self endon("disconnect");
    level endon("game_ended");

	self.moabcounter = createFontString("Objective", 1);
    self.moabcounter setPoint("TOPRIGHT", "TOPERIGHT", -10, 325);
    self.moabcounter.label = &"^1MOABs: ^7";
    self.moabcounter.sort = -3;
    self.moabcounter.alpha = 0.9;
    self.moabcounter.hideWhenInMenu = true;
    self.moabcounter setValue(0);

	moabs = 0;
	self.moabAdded = false;

    for(;;)
    {
		moabWith = 25;

        if (maps\mp\_utility::_hasperk("specialty_hardline"))
        {
            moabWith--;
        }

		if (self.pers["cur_kill_streak_for_nuke"] >= moabWith && !self.moabAdded)
		{
			moabs += 1;
			self.moabAdded = true;
			self.moabcounter setValue(moabs);
		}

		wait 0.25;
    }
}

destroyCounterOnGameEnd()
{
	self endon("disconnect");
	level waittill("game_ended");

    if (isDefined(self.killStreak))
		self.killStreak hudFadenDestroy(0, .1);
	if (isDefined(self.gunStreakDisplay))
		self.gunStreak hudFadenDestroy(0, .1);
	if (isDefined(self.moabcounter))
		self.moabcounter hudFadenDestroy(0, .1);
}

hudFadenDestroy(alpha,time)
{
	self fadeOverTime(time);
	self.alpha = alpha;
	wait time;
    self destroy();
}

resetOnDeath()
{
    self endon("disconnect");

    for (;;)
    {
        self waittill("death");
		self.savedKills = maps\mp\_utility::getpersstat( "kills" );
		self.moabAdded = false;
		self.savedAssists = self.pers["assistsToKill"];
		if (self.pers["assistsToKill"] % 2 == 1) {
		    self.savedAssists -= 1;
		}
    }
}
