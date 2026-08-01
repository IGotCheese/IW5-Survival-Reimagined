/*
============================
|   Lethal Beats Team	   |
============================
|Game : IW5                |
|Script : IW5_VoteSystem   |
|Creator : LastDemon99	   |
|Type : Addon              |
============================
yourserver.gg SURVIVAL-SERVER ADAPTATION (2026-07-16) of LastDemon99's IW5_VoteSystem:
 - Trigger: the stock hook (waittillFinalKillcamDone) never fires in the survival
   gametype, so init() instead replaceFunc's the survival mod's own
   lethalbeats\survival\utility::level_rotate_map -> vote first, then rotate.
 - Map/mode pools are HARDCODED GSC TABLES (survival_vote_pool / survival_dsr_pool)
   instead of the vote_maps/vote_dsr dvars: 86 maps won't fit dvar plumbing safely.
 - Failsafe: if the vote doesn't rotate (disabled/empty/wedged), ServerControl's
   rotate() runs after vote_time + 30s. The server can never sit on a dead map.
 ⚠️ SURVIVAL SERVER ONLY - never copy to the live <MP-PORT> server (references
   lethalbeats\* scripts that only exist here -> LinkFile boot death).
*/

#include maps\mp\gametypes\_hud_util;
#include common_scripts\utility;
#include maps\mp\_utility;

init()
{
	loadData();

	level thread voteInit();
	level thread credits();

	// Survival-only trigger (this server always runs survival; the guard is belt & braces).
	// level_rotate_map is only CALLED at game end, so a detour placed at init always
	// catches it - unlike onEndLevel, which is already running as a thread by now.
	if ( getDvar( "g_gametype" ) == "survival" )
		replacefunc( lethalbeats\survival\utility::level_rotate_map, ::survival_rotate_with_vote );
}

survival_rotate_with_vote( delay )
{
	if ( !isDefined( delay ) )
		delay = 1;
	wait delay;

	if ( getDvarInt( "vote_enable" ) != 1 || playersCount() < 1 )
	{
		// voting off or nobody human to vote: original behavior
		lethalbeats\servercontrol\commands::rotate( "Level has been rotated." );
		return;
	}

	level thread survival_vote_failsafe();
	level notify( "vote_start" );
}

survival_vote_failsafe()
{
	wait ( getDvarInt( "vote_time" ) + 30 );
	lethalbeats\servercontrol\commands::rotate( "Level has been rotated." );
}

// ── survival vote pools (name, alias) ────────────────────────────────────────
survival_vote_pool()
{
	m = [];
	m[m.size] = ["mp_dome", "[MW3] Dome"];
	m[m.size] = ["mp_dwarf_sh", "Dwarf"];
	m[m.size] = ["mp_sd_jardin", "Royal Garden"];
	m[m.size] = ["mp_abandon", "[MW2] Carnival"];
	m[m.size] = ["mp_bootleg", "[MW3] Bootleg"];
	m[m.size] = ["mp_hardhat", "[MW3] Hardhat"];
	m[m.size] = ["mp_carbon", "[MW3] Carbon"];
	m[m.size] = ["mp_interchange", "[MW3] Interchange"];
	m[m.size] = ["mp_lambeth", "[MW3] Fallen"];
	m[m.size] = ["mp_mogadishu", "[MW3] Bakaara"];
	m[m.size] = ["mp_paris", "[MW3] Resistance"];
	m[m.size] = ["mp_plaza2", "[MW3] Arkaden"];
	m[m.size] = ["mp_radar", "[MW3] Outpost"];
	m[m.size] = ["mp_seatown", "[MW3] Seatown"];
	m[m.size] = ["mp_nuked", "[BO2] Nuketown"];
	// 2026-07-22: dropped again, still broken (texture fix wasn't sufficient).
	// m[m.size] = ["mp_nightshift", "[MW2] Skidrow"];
	m[m.size] = ["mp_rust", "[MW2] Rust"];
	m[m.size] = ["mp_alpha", "[MW3] Lockdown"];
	m[m.size] = ["mp_bravo", "[MW3] Mission"];
	m[m.size] = ["mp_exchange", "[MW3] Downturn"];
	m[m.size] = ["mp_underground", "[MW3] Underground"];
	m[m.size] = ["mp_village", "[MW3] Village"];
	m[m.size] = ["mp_aground_ss", "[MW3] Aground"];
	m[m.size] = ["mp_courtyard_ss", "[MW3] Erosion"];
	m[m.size] = ["mp_terminal_cls", "[MW3] Terminal"];
	m[m.size] = ["mp_raid", "[MW3] Raid"];
	m[m.size] = ["mp_afghan", "[MW2] Afghan"];
	m[m.size] = ["mp_firingrange", "[BO1] Firing Range"];
	m[m.size] = ["mp_boardwalk", "[MW3] Boardwalk"];
	m[m.size] = ["mp_burn_ss", "[MW3] U-Turn"];
	m[m.size] = ["mp_cement", "[MW3] Foundation"];
	m[m.size] = ["mp_crosswalk_ss", "[MW3] Intersection"];
	m[m.size] = ["mp_hillside_ss", "[MW3] Getaway"];
	m[m.size] = ["mp_italy", "[MW3] Piazza"];
	m[m.size] = ["mp_meteora", "[MW3] Sanctuary"];
	m[m.size] = ["mp_moab", "[MW3] Gulch"];
	m[m.size] = ["mp_nola", "[MW3] Parish"];
	m[m.size] = ["mp_overwatch", "[MW3] Overwatch"];
	m[m.size] = ["mp_park", "[MW3] Liberation"];
	m[m.size] = ["mp_qadeem", "[MW3] Oasis"];
	m[m.size] = ["mp_restrepo_ss", "[MW3] Lookout"];
	m[m.size] = ["mp_roughneck", "[MW3] Off Shore"];
	m[m.size] = ["mp_shipbreaker", "[MW3] Decommission"];
	m[m.size] = ["mp_six_ss", "[MW3] Vortex"];
	m[m.size] = ["mp_killhouse", "Killhouse"];
	m[m.size] = ["mp_estate", "Estate"];
	m[m.size] = ["mp_mountain", "Summit"];
	m[m.size] = ["mp_boomtown", "Western Paradise"];
	m[m.size] = ["mp_melee_resort", "Melee Resort"];
	m[m.size] = ["mp_lockout_h2", "Lockout - Halo 2"];
	// 2026-07-22: temporarily pulled from rotation + vote pool per user request.
	// m[m.size] = ["mp_gulag", "Gulag"];
	m[m.size] = ["mp_bog_sh", "[COD4] Bog"];
	m[m.size] = ["mp_bo2cove", "[BO2] Cove"];
	m[m.size] = ["mp_bo2frost", "[BO2] Frost"];
	m[m.size] = ["mp_bo2grind", "[BO2] Grind"];
	m[m.size] = ["mp_bo2paintball", "[BO2] Rush"];
	m[m.size] = ["mp_brecourt", "Wasteland"];
	m[m.size] = ["mp_broadcast", "Broadcast"];
	m[m.size] = ["mp_burgundy", "Burgundy"];
	m[m.size] = ["mp_checkpoint", "Karachi"];
	m[m.size] = ["mp_csgo_mirage", "[CS:GO] Mirage"];
	m[m.size] = ["mp_csgo_stmarc", "[CS:GO] St. Marc"];
	m[m.size] = ["mp_efa_lake", "Lake"];
	m[m.size] = ["mp_geometric", "Geometric"];
	m[m.size] = ["mp_gob_aim_snow", "Gob Aim Snow"];
	m[m.size] = ["mp_minecraft", "C4S Minecraft"];
	m[m.size] = ["mp_minecraft_3", "Minecraft City"];
	m[m.size] = ["mp_osg_freight", "Freight"];
	m[m.size] = ["mp_osg_hijacked", "Hijacked"];
	m[m.size] = ["mp_osg_mirage_n", "Mirage Night"];
	m[m.size] = ["mp_overpass", "Overpass"];
	m[m.size] = ["mp_safehouse", "Safehouse"];
	m[m.size] = ["mp_shipmentlong", "Shipment Long"];
	m[m.size] = ["mp_shortdust", "Short Dust"];
	m[m.size] = ["mp_toujane", "Toujane"];
	m[m.size] = ["mp_cargoship_sh", "Snow Wetwork"];
	m[m.size] = ["mp_strike_sh", "Strike"];
	m[m.size] = ["mp_prison", "Prison"];
	m[m.size] = ["mp_tunisia", "Tunisia"];
	m[m.size] = ["mp_shipment", "[COD4] Shipment"];
	m[m.size] = ["mp_poolday", "[Custom] Pool Day"];
	m[m.size] = ["mp_poolday_v2", "[Custom] Pool Day V2"];
	m[m.size] = ["mp_poolday_reunion", "[Custom] Pool Day Reunion"];
	m[m.size] = ["mp_poolparty", "[Custom] Pool Party"];
	m[m.size] = ["mp_rust_long", "[MW2] Rust Long"];
	m[m.size] = ["mp_morningwood", "[Custom] Black Box"];
	m[m.size] = ["mp_backlot_sh", "[COD:OL] Backlot"];
	m[m.size] = ["mp_bloc_2_night", "[COD4] Bloc 2 Night"];
	m[m.size] = ["mp_bo2nuketown2", "[BO2] Nuketown 2025"];
	m[m.size] = ["mp_bo2plaza", "[BO2] Plaza"];
	m[m.size] = ["mp_bo2slums", "[BO2] Slums"];
	// bpg 2026-07-30: added alongside the map itself. Display name taken from the map's
	// own .arena longname ("Town") and prefixed [BO2] to match its six siblings here.
	// It was NOT added until waypoints existed - the map shipped none, and a survival
	// map without a bot graph leaves the enemies bunched at spawn (the mp_crossfire
	// symptom). 700 nodes now ship in zz_bpg_waypoints.iwd.
	m[m.size] = ["mp_bo2_town", "[BO2] Town"];
	m[m.size] = ["mp_boneyard", "[MW2] Scrapyard"];
	m[m.size] = ["mp_convoy", "[COD4] Ambush"];
	m[m.size] = ["mp_countdown", "[COD4] Countdown"];
	m[m.size] = ["mp_creek", "[COD4] Creek"];
	m[m.size] = ["mp_cross_fire", "[COD4] Crossfire"];
	m[m.size] = ["mp_csgo_assault", "[CS:GO] Assault"];
	m[m.size] = ["mp_csgo_office", "[CS:GO] Office"];
	m[m.size] = ["mp_derail", "[MW2] Derail"];
	m[m.size] = ["mp_fuel2", "[MW2] Fuel"];
	m[m.size] = ["mp_invasion", "[MW2] Invasion"];
	m[m.size] = ["mp_pipeline", "[COD4] Pipeline"];
	m[m.size] = ["mp_quarry", "[MW2] Quarry"];
	m[m.size] = ["mp_storm", "[MW2] Storm"];
	m[m.size] = ["mp_subbase", "[MW2] Sub Base"];
	m[m.size] = ["mp_trailerpark", "[MW2] Trailer Park"];
	m[m.size] = ["mp_underpass", "[MW2] Underpass"];
	m[m.size] = ["mp_vacant", "[MW2] Vacant"];
	m[m.size] = ["mp_waw_castle", "[WaW] Castle"];
	m[m.size] = ["mp_sharqi_day", "[BF3] Sharqi Peninsula"];
	m[m.size] = ["mp_complex", "[MW2] Bailout"];
	m[m.size] = ["mp_cha_quad", "[COD:OL] Monastery"];
	m[m.size] = ["mp_compact", "[MW2] Salvage"];
	m[m.size] = ["mp_factory_sh", "[WaW] Der Riese"];
	m[m.size] = ["mp_farm", "[COD4] Downpour"];
	m[m.size] = ["mp_kejland", "[COD4] Kejland"];
	m[m.size] = ["mp_mideast", "[COD:OL] Oasis V2"];
	m[m.size] = ["mp_nukearena_sh", "[COD:OL] Nuke Arena"];
	m[m.size] = ["mp_offshore_sh", "[COD:OL] Doomsday Drilling"];
	m[m.size] = ["mp_overgrown", "[MW2] Overgrown"];
	m[m.size] = ["mp_tundra_depot", "Tundra Depot"];
	m[m.size] = ["mp_village_sh", "[BO1] Standoff"];
	m[m.size] = ["mp_wasteland_sh", "[COD:OL] Short Wasteland"];
	m[m.size] = ["mp_bootleg_sh", "[COD:OL] Bootleg Snow"];
	m[m.size] = ["mp_base", "Base"];
	m[m.size] = ["mp_crash", "[MW2] Crash"];
	m[m.size] = ["mp_bloc_2", "[MW2] Bloc"];
	m[m.size] = ["mp_fav_tropical", "Favela Tropical"];
	m[m.size] = ["mp_highrise_sh", "Highrise"];
	return m;
}

survival_dsr_pool()
{
	d = [];
	d[d.size] = ["survival_easy", "Survival - Easy"];
	d[d.size] = ["survival_normal", "Survival - Normal"];
	d[d.size] = ["survival_hard", "Survival - Hard"];
	return d;
}

voteInit()
{
	level endon( "end_game" );
	level waittill("vote_start");

	level.votation = createVote();
	if(level.votation["hasEnabled"])
	{
		level.voteTime = level.votation["time"];
		level.voteMaps = level.votation["maps"];
		level.voteDsr = level.votation["dsr"];
		level.voteMapsEnabled = level.votation["mapsEnabled"];
		level.voteDsrEnabled = level.votation["dsrEnabled"];
	}
	else
	{
		level notify("vote_end");
		return;
	}

	createVoteHud();

	foreach(player in level.players)
		player thread playerVoteInit();

	level waittill("vote_end");

	winMap = [level.voteMaps[randomIntRange(0, level.voteMaps.size)], getDvar("g_gametype"), 0];
	MapRepeats = [];

	winDSR = [level.voteDsr[randomIntRange(0, level.voteDsr.size)], getDvar("g_gametype"), 0];
	DSRRepeats = [];

	if(level.voteMapsEnabled)
	{
		for (i = 0; i < level.voteMaps.size; i++)
			if(winMap[2] < level.voteMaps[i][2])
				winMap = level.voteMaps[i];

		for (i = 0; i < level.voteMaps.size; i++)
			if(winMap[2] == level.voteMaps[i][2])
				MapRepeats[MapRepeats.size] = level.voteMaps[i];

		if(MapRepeats.size > 0) winMap = MapRepeats[randomIntRange(0, MapRepeats.size)];
	}

	if(level.voteDsrEnabled)
	{
		for (i = 0; i < level.voteDsr.size; i++)
			if(winDSR[2] < level.voteDsr[i][2])
				winDSR = level.voteDsr[i];

		for (i = 0; i < level.voteDsr.size; i++)
			if(winDSR[2] == level.voteDsr[i][2])
				DSRRepeats[DSRRepeats.size] = level.voteDsr[i];

		if(DSRRepeats.size > 0) winDSR = DSRRepeats[randomIntRange(0, DSRRepeats.size)];
	}

	// bpg 2026-07-16: STICKY difficulty. With zero difficulty votes the original
	// picked a RANDOM dsr every rotation (server kept drifting off Easy). Now:
	// no votes = keep the last-loaded difficulty (dvar-persisted across maps).
	dsrVotesTotal = 0;
	for (i = 0; i < level.voteDsr.size; i++)
		dsrVotesTotal += level.voteDsr[i][2];

	if (dsrVotesTotal < 1)
	{
		sticky = getDvar("bpg_last_dsr");
		if (sticky == "") sticky = "survival_easy";
		cmdexec("load_dsr " + sticky);
	}
	else
	{
		setDvar("bpg_last_dsr", winDSR[0]);
		cmdexec("load_dsr " + winDSR[0]);
	}
	wait(3);
	cmdexec("map " + winMap[0]);
}

playerVoteInit()
{
	if(self is_bot()) return;

	self endon( "disconnect" );
	level endon( "end_game" );
	level endon("vote_end");

	if(self.sessionteam == "spectator") return;

	self playlocalsound("elev_bell_ding");

	// bpg fix: bind ONCE per connect — playerVoteInit runs every vote, and
	// re-registering stacks duplicate command notifies (one press -> N events)
	if (!isDefined(self.bpg_votebinds))
	{
		self.bpg_votebinds = true;
		// bpg 2026-07-20: matched to main server's (scripts\mp\_mapvote.gsc)
		// buttonMonitoring() bind set so both servers' vote menus respond to the
		// same keys/buttons.
		self notifyonplayercommand("up", "+attack");
		self notifyonplayercommand("up", "+forward");
		self notifyonplayercommand("up", "+actionslot 1");
		self notifyonplayercommand("down", "+toggleads_throw");
		self notifyonplayercommand("down", "+speed_throw");
		self notifyonplayercommand("down", "+back");
		self notifyonplayercommand("down", "+actionslot 2");
		self notifyonplayercommand("select", "+activate");
		self notifyonplayercommand("select", "+gostand");
		self notifyonplayercommand("melee", "+melee_zoom");
	}

	default_y = -155;

	index = 0;
	hasVoted = false;
	selected = [];

	if(level.voteMapsEnabled)
	{
		voteType = "maps";
		default_y = -155;
		max_index = level.voteMaps.size - 1;
	}
	else
	{
		voteType = "dsr";
		if(level.voteMapsEnabled) default_y = 5;
		max_index = level.voteDsr.size - 1;
	}

	for(;;)
	{
		key = self waittill_any_return("up", "down", "select", "melee");

		// bpg fix: waittill_any_return can return undefined (death/join edge
		// cases) — comparing undefined == "up" is a runtime error that KILLS this
		// thread, leaving the player unable to vote at all (live-reported:
		// "wouldn't let me press"). Skip bad events instead of dying.
		if (!isDefined(key))
			continue;
		if (key != "up" && key != "down" && key != "select" && key != "melee")
			continue;

		if(!hasVoted)
		{
			if(key == "up")
			{
				if(index > 0) index --;
				else index = max_index;

				self selectedSwitchFX(voteType, index, (0.5, 1, 0));
				self playlocalsound("mouse_over");
			}
			else if(key == "down")
			{
				if(index < max_index) index++;
				else index = 0;

				self selectedSwitchFX(voteType, index, (0.5, 1, 0));
				self playlocalsound("mouse_over");
			}
			else if (key == "select")
			{
				if(voteType == "maps")
				{
					selected["maps"] = index;
					level.voteMaps[index][2]++;

					self selectedSwitchFX(voteType, index, (1, 0, 0));

					if(level.voteDsrEnabled)
					{
						voteType = "dsr";
						index = 0;
						// bpg: highlight the first difficulty entry immediately �
						// without this the selector looks dead until a keypress
						self selectedSwitchFX(voteType, index, (0.5, 1, 0));
					}
					else hasVoted = true;
				}
				else
				{
					selected["dsr"] = index;
					level.voteDsr[index][2]++;
					hasVoted = true;

					self selectedSwitchFX(voteType, index, (1, 0, 0));
				}
				self playlocalsound("recondrone_lockon");
			}
		}
		else self playlocalsound("elev_door_interupt");

		if (key == "melee")
		{
			if((voteType == "maps" && hasVoted) || (level.voteDsrEnabled && voteType == "dsr" && !hasVoted))
			{
				level.voteMaps[selected["maps"]][2]--;

				if(!level.voteDsrEnabled)
				{
					hasVoted = false;
					self selectedSwitchFX(voteType, index, (0.5, 1, 0));
				}
				else
				{
					self selectedSwitchFX(voteType, index, (255, 255, 255));
					voteType = "maps";
					index = selected["maps"];
					selected["maps"] = undefined;
					self selectedSwitchFX(voteType, index, (0.5, 1, 0));
				}
				self playlocalsound("mine_betty_click");
			}
			else if(voteType == "dsr" && hasVoted)
			{
				level.voteDsr[selected["dsr"]][2]--;
				index = selected["dsr"];
				selected["dsr"] = undefined;
				hasVoted = false;

				self selectedSwitchFX(voteType, index, (0.5, 1, 0));
				self playlocalsound("mine_betty_click");
			}
		}

		if(voteType == "maps")
		{
			default_y = -155;
			max_index = level.voteMaps.size - 1;
		}
		else
		{
			if(level.voteMapsEnabled) default_y = 5;
			max_index = level.voteDsr.size - 1;
		}

		self.voteHud["navbar"].y = default_y + index * 20;
		self.voteHud["navbarShadow"].y = (default_y - 10) + index * 20;
	}
}

loadData()
{
	setDvarIfNotInizialized("vote_enable", 1);
	setDvarIfNotInizialized("vote_maps_count", 6);
	setDvarIfNotInizialized("vote_dsr_count", 3);
	setDvarIfNotInizialized("vote_time", 20);

	shaders = StrTok("background_image;gradient;gradient_fadein;gradient_top", ";");
    foreach(shader in shaders)
        PreCacheShader(shader);

	// yourserver.gg: vote_maps/vote_dsr dvars intentionally NOT used - pools come from
	// survival_vote_pool()/survival_dsr_pool() GSC tables above.
}

createVote()
{
	voteItems = [];

	voteItems["hasEnabled"] = true;
	voteItems["mapsEnabled"] = true;
	voteItems["dsrEnabled"] = true;
	voteItems["time"] = getDvarInt("vote_time");

	mapsCount = getDvarInt("vote_maps_count");
	dsrCount = getDvarInt("vote_dsr_count");

	if(mapsCount <= 1 && dsrCount <= 1)
	{
		voteItems["hasEnabled"] = false;
		return voteItems;
	}

	voteData = dvarVoteDataToArray();

	if(mapsCount <= 1) voteItems["mapsEnabled"] = false;
	if(dsrCount <= 1) voteItems["dsrEnabled"] = false;

	if(voteItems["mapsEnabled"])
	{
		if(mapsCount > 16) mapsCount = 16;
		if(mapsCount > voteData["maps"].size) mapsCount = voteData["maps"].size;
		if(mapsCount > 6 && voteItems["dsrEnabled"]) mapsCount = 6;

		voteItems["maps"] = []; //name, alias, votes
		mapsIndex = randomNum(mapsCount, 0, voteData["maps"].size);
		for(i = 0; i < mapsIndex.size; i++)
		{
			data = voteData["maps"][mapsIndex[i]];
			voteItems["maps"][i] = [data[0], data[1], 0];
		}
	}

	if(voteItems["dsrEnabled"])
	{
		if(dsrCount > 16) dsrCount = 16;
		if (dsrCount > voteData["dsr"].size) dsrCount = voteData["dsr"].size;
		if(dsrCount > 6 && voteItems["mapsEnabled"]) dsrCount = 6;

		voteItems["dsr"] = []; //name, alias, votes
		dsrIndex = randomNum(dsrCount, 0, voteData["dsr"].size);
		for(i = 0; i < dsrIndex.size; i++)
		{
			data = voteData["dsr"][dsrIndex[i]];
			voteItems["dsr"][i] = [data[0], data[1], 0];
		}
	}

	return voteItems;
}

selectedSwitchFX(voteType, index, color)
{
	foreach(hud in self.voteHud[voteType])
	{
		hud.fontScale = 1.2;
		hud.color = (255, 255, 255);
	}

	self.voteHud[voteType][index].color = color;
	self.voteHud[voteType][index].fontScale += 0.2;
}

createVoteHud()
{
	level thread createVoteTimer();

	//create BG hud
	// bpg 2026-07-20: matched to main server's instruction-line format/wording
	// (scripts\mp\_mapvote.gsc) plus our extra undo bind.
	createHudText("^7Up ^2W^7/^2DPad Up ^7Down ^2S^7/^2DPad Down ^7Vote ^2[{+gostand}] ^7Undo ^2[{+melee_zoom}]", "hudsmall", 0.8, "CENTER", "CENTER", 0, 210, false);

	bg = createIconHud("background_image", "CENTER", "CENTER", 0, 0, 860, 480, (1,1,1), 1, 1, false);
	bg.hideWhenInMenu = false;

	// bpg 2026-07-27: restyle. Only the four shaders this script already precaches
	// (white / gradient / gradient_fadein / gradient_top) plus background_image are
	// available in-game - common_mp.ff and code_post_gfx_mp.ff define NO preview_* or
	// loadscreen_* MATERIALS, so per-map thumbnails are impossible without shipping a
	// custom fastfile. Everything below is built from those four.

	// Darken the LEFT column only, where the vote list sits, instead of washing the whole
	// screen. The old panel was 860 wide and dimmed the artwork and the server-info block
	// on the right along with it.
	createIconHud("white", "RIGHT", "CENTER", -125, 0, 420, 480, (0,0,0), 0.62, 2, false);
	// soft edge so the panel doesn't end in a hard vertical line over the artwork
	createIconHud("gradient", "RIGHT", "CENTER", -125, 0, 90, 480, (0,0,0), 0.45, 2, false);

	// divider + its glow, unchanged in position so the list still lines up
	createIconHud("gradient_fadein", "CENTER", "CENTER", -125, 0, 1, 480, (0.90,0.72,0.28), 1, 3, false);
	createIconHud("gradient", "CENTER", "CENTER", -119, 0, 12, 480, (0.90,0.72,0.28), 0.35, 2, false);

	// Your Server header above the list, in the gold used across the branding
	createHudText("^3YOUR SERVER", "objective", 1.5, "RIGHT", "CENTER", -151, -222, false);
	createIconHud("gradient_fadein", "RIGHT", "CENTER", -125, -205, 260, 2, (0.90,0.72,0.28), 1, 3, false);

	createIconHud("gradient_fadein", "RIGHT", "CENTER", -125, -172, 220, 1, (0.62,0.62,0.60), 1, 3, false);

	if(level.voteMapsEnabled && level.voteDsrEnabled)
		createIconHud("gradient_fadein", "RIGHT", "CENTER", -125, -12, 220, 1, (0.62,0.62,0.60), 1, 3, false);

	hudLastPosY =  -155;
	if(level.voteMapsEnabled) createHudText("^7VOTE MAP", "hudsmall", 1.4, "RIGHT", "CENTER", -151, -190, false);
	if(level.voteDsrEnabled && !level.voteMapsEnabled) createHudText("^7VOTE MODE", "hudsmall", 1.4, "RIGHT", "CENTER", -151, -190, false);
	else if (level.voteDsrEnabled) createHudText("^7VOTE MODE", "hudsmall", 1.4, "RIGHT", "CENTER", -151, -30, false);

	// community line along the bottom, clear of the artwork's own info block
	createHudText("^3discord ^7yourserver.gg    ^3stats ^7your.stats.host    ^3#help ^7for commands",
	              "hudsmall", 0.75, "CENTER", "CENTER", 0, 225, false);

	foreach(player in level.players)
		player thread createPlayerVoteHud();
}

createVoteTimer()
{
	soundFX = spawn("script_origin", (0,0,0));
	soundFX hide();

	// bpg 2026-07-26: moved off the bottom-right corner. Anchored RIGHT/RIGHT at y=+170 it
	// sat directly on top of the server-info block baked into our background_image artwork
	// ("Type #help in chat...").
	// bpg 2026-07-27: y=-215 put it ON TOP of the YOUR SERVER header at -222 - that top strip
	// already holds header/underline/VOTE MAP between -222 and -190, so there is no room for a
	// fifth line there. Moved down into the empty part of the dimmed column, below the mode
	// list (last row lands around +50) and well inside the 480-tall panel.
	timerhud = createTimer(level.voteTime, &"Vote end in: ", "hudsmall", 1.4, "RIGHT", "CENTER", -125, 120);
	for (i = getDvarInt("vote_time"); i > 0; i--)
	{
		timerhud.Color = (1, 1, 0);
		if(i < 5)
		{
			timerhud.Color = (1, 0, 0);
			soundFX playSound( "ui_mp_timer_countdown" );
		}
		wait(1);
	}
	level notify("vote_end");
}

createPlayerVoteHud()
{
	hudLastPosY =  -155;
	self.voteHud = [];
	// bpg 2026-07-27: selection bar recoloured from pure green to the Your Server gold,
	// and given a little more presence so it reads against the darkened column.
	self.voteHud["navbar"] = self createIconHud("gradient_fadein", "RIGHT", "CENTER", -125, -155, 340, 20, (0.90,0.72,0.28), 0.42, 3, true);
	self.voteHud["navbarShadow"] = self createIconHud("gradient_top", "RIGHT", "CENTER", -125, -145, 340, 4, (0,0,0), 1, 2, true);

	if(level.voteMapsEnabled)
	{
		for (i = 0; i < level.voteMaps.size; i++)
		{
			self.voteHud["maps"][i] = self createHudText(level.voteMaps[i][1], "objective", 1.2, "RIGHT", "CENTER", -151, hudLastPosY, true);
			self.voteHud["mapsVote"][i] = self createHudText("[0/" + playersCount() + "]", "objective", 1.2, "RIGHT", "CENTER", -85, hudLastPosY, true);
			hudLastPosY += 20;
		}
		hudLastPosY = 5;
	}

	if(level.voteDsrEnabled)
	{
		self.hudDsr = [];
		for (i = 0; i < level.voteDsr.size; i++)
		{
			self.voteHud["dsr"][i] = self createHudText(level.voteDsr[i][1], "objective", 1.2, "RIGHT", "CENTER", -151, hudLastPosY, true);
			self.voteHud["dsrVote"][i] = self createHudText("[0/" + playersCount() + "]", "objective", 1.2, "RIGHT", "CENTER", -85, hudLastPosY, true);
			hudLastPosY += 20;
		}
	}

	self thread updateVotesHud();
}

updateVotesHud()
{
	self endon( "disconnect" );
	level endon( "end_game" );

	for(;;)
	{
		if(level.voteMapsEnabled)
		{
			for (i = 0; i < level.voteMaps.size; i++)
		self.voteHud["mapsVote"][i] setText("[" + level.voteMaps[i][2] + "/" + playersCount() + "]");
		}

		if(level.voteDsrEnabled)
		{
			for (i = 0; i < level.voteDsr.size; i++)
				self.voteHud["dsrVote"][i] setText("[" + level.voteDsr[i][2] + "/" + playersCount() + "]");
		}
		wait(0.1);
	}
}

randomNum(size, min, max)
{
	uniqueArray = [size];
	random = 0;

	for (i = 0; i < size; i++)
	{
		random = randomIntRange(min, max);
		for (j = i; j >= 0; j--)
			if (isDefined(uniqueArray[j]) && uniqueArray[j] == random)
			{
				random = randomIntRange(min, max);
				j = i;
			}
		uniqueArray[i] = random;
	}
	return uniqueArray;
}

createHudText(text, font, size, align, relative, x, y, isClient)
{
	if(isClient) hudText = self createFontString(font, size);
	else hudText = createServerFontString(font, size);

	hudText setpoint(align, relative, x, y);
	hudText setText(text);
	hudText.alpha = 1;
	hudText.hideWhenInMenu = true;
	hudText.foreground = true;
	return hudText;
}

createIconHud(shader, align, relative, x, y, width, height, color, alpha, sort, isClient)
{
	if(isClient) hudIcon = self createIcon(shader, width, height);
	else hudIcon = createServerIcon(shader, width, height);

	hudIcon.align = align;
    hudIcon.relative = relative;
    hudIcon.width = width;
    hudIcon.height = height;
	hudIcon.alpha = alpha;
	hudIcon.color = color;
    hudIcon.hideWhenInMenu = true;
	hudIcon.hidden = false;
    hudIcon.archived = false;
    hudIcon.sort = sort;
    hudIcon setPoint(align, relative, x, y);
	hudIcon setParent(level.uiParent);
    return hudIcon;
}

createTimer(time, label, font, size, align, relative, x, y)
{
	timer = createServerTimer(font, size);
	timer setpoint(align, relative, x, y);
	timer.label = label;
	timer.alpha = 1;
	timer.hideWhenInMenu = true;
	timer.foreground = true;
	timer setTimer(time);

	return timer;
}

setDvarIfNotInizialized(dvar, value)
{
	result = getDvar(dvar);
	if(!isDefined(result) || result == "")
		setDvar(dvar, value);
}

dvarVoteDataToArray()
{
	// yourserver.gg: pools from GSC tables, not dvars (see header).
	voteData = [];
	voteData["maps"] = survival_vote_pool();
	voteData["dsr"] = survival_dsr_pool();
	return voteData;
}

playersCount()
{
	count = 0;
	foreach(player in level.players)
		if(!(player is_bot()))
			count++;
	return count;
}

is_bot()
{
	assert( isDefined( self ) );
	assert( isPlayer( self ) );

	return ( ( isDefined( self.pers["isBot"] ) && self.pers["isBot"] ) || ( isDefined( self.pers["isBotWarfare"] ) && self.pers["isBotWarfare"] ) || isSubStr( self getguid() + "", "bot" ) );
}

credits()
{
	for(;;)
    {
		if(getDvar("vote_credits") != "Developed by LastDemon99")
			setDvar("vote_credits", "Developed by LastDemon99");
		wait(0.35);
	}
}
