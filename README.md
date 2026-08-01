# IW5 Survival Reimagined — Reinvisioned

Server-side source for MW3 (IW5 / Plutonium) dedicated servers — Survival and Multiplayer —
plus the tooling built to keep them running.

Everything here is server-side GSC, PowerShell tooling, and data. Nothing here is a game asset
or a client download.

---

## Attribution

This builds on other people's work and does not replace it:

- **[IW5-Survival-Reimagined](https://github.com/LastDemon99/IW5-Survival-Reimagined)** by
  LastDemon99 — the Survival gametype itself. Everything in `01-survival-mod-scripts/` is a
  *fix, override or addition layered on top of it*, not a fork of it.
- **[Bot Warfare](https://github.com/ineedbots/iw5_bot_warfare)** (ineedbots) — the bot AI and
  waypoint system. `04-bot-waypoints/` uses its file format; the tooling in
  `05-tools-scripting/` implements the rules from its own `_wp_editor.gsc`.
- **Plutonium** — the platform. `maps/mp/**` names refer to stock IW5 script.

## Folder guide

### `01-survival-mod-scripts/` — Survival gametype: fixes and features
Loose GSC loaded from `storage/iw5/scripts/`. Plutonium runs each file's `init()` on every
level load, so these layer on top of the mod without modifying its `.iwd`.

Roughly three kinds of file:

| kind | examples | what it does |
|---|---|---|
| **Bug fixes** | `bpg_survival_shopfix`, `bpg_survival_juggerdropfix`, `bpg_survival_wavestallfix` | `replaceFunc` a mod/stock function with a corrected copy |
| **Features** | `bpg_survival_bankcmds`, `bpg_survival_afk`, `bpg_survival_undo`, `bpg_survival_vaultstore` | new player commands and systems |
| **Data** | `survivalMaps.gsc` | the buy-station / juggernaut-drop coordinate table (see *Entities* below) |

**`survivalMaps.gsc` is the important data file.** 128 maps × three buy stations, plus
juggernaut drop points. A buy station is **not a map asset** — `armories\_spawn::spawnShop`
builds it at runtime from two `script_model`s (`com_plasticcase_friendly` +
`com_laptop_2_open`), a trigger *struct*, and a 3D objective icon. Nothing is authored into the
`.d3dbsp`, so the only per-map variable is a coordinate. That is why a table is the whole fix.

### `02-multiplayer-mod-scripts/` — Multiplayer servers
Chat commands, map voting, welcome/rules text, and gametype overlays (`gun_game`, `bpg_cranked`,
`bpg_sharpshooter`). Also `bpg_destructible_fix` — note the comment in it: replacing
`_destructible` wholesale is *proven boot-death*, `replaceFunc` is the only safe route.

### `03-gametypes-objectives/` — Entities and objectives
Loose overrides of stock gametype scripts (`ctf.gsc`, `sab.gsc`, `dd.gsc`, `grnd.gsc`, `gun.gsc`…).

This is the **entity injection** layer. Many custom map ports ship no objective entities at all —
no CTF flags, no capture zones, no team spawns — because those are baked into the map at compile
time and cannot be created by script. The `ctf_fix_<map>()` / `sab_fix_<map>()` functions
reconstruct them at runtime:

- flags/zones via `ctf_make_flag()` — a `script_model` + a `trigger_radius`
- team spawns via `level.extraspawnpoints`, which stock `_spawnlogic::getspawnpointarray`
  merges into its own results
- bases sited on the two farthest-apart Bot Warfare waypoints, which are walkable by construction

Without these, Bot Warfare's `bot_cap` loop dereferences `level.teamflags[team]` on a map that has
none and error-storms — measured at **116,222 errors in one log, with 5.8-second frame hitches.**

### `04-bot-waypoints/` — Bot navigation data
`wps_<map>.gsc` packs. Format taken from Bot Warfare's own `_wp_editor.gsc`:

| field | required | notes |
|---|---|---|
| `.origin` | always | vector |
| `.type` | always | `stand`/`crouch`/`prone` + `climb`/`grenade`/`claymore`/`tube`/`javelin` |
| `.children[]` | always | int indices; 0 children = unreachable node |
| `.angles` | **conditionally** | `claymore`, `tube`, `climb`, `grenade`, and **`crouch` with exactly 1 child** |
| `.jav_point` | javelin only | vector |

⚠️ **`"camp"` is not a stored type.** `getWaypointsOfType("camp")` maps it to
*`crouch` with exactly one child* — and `bot_think_camp_loop` calls
`anglestoforward(campSpot.angles)` with no guard. A camp node missing `.angles` throws and kills
that bot's AI thread. That single omission produced 1,170 errors in two waves on one map, and
132 bad waypoints across 9 of 15 packs.

⚠️ **The stock GSC export is lossy.** The in-game editor sets `.angles` on *every* waypoint, and
the CSV export preserves them — but the GSC export writes them only for the five types above.
Round-tripping through GSC silently drops the rest.

### `05-tools-scripting/` — Scripting and data tools
| tool | purpose |
|---|---|
| `wptool.ps1` | Validate / repair / convert waypoint packs. Implements Bot Warfare's own `checkForWarnings` rules exactly, plus link reciprocity and full BFS connectivity. `-Validate`, `-Repair`, `-ToCsv`, `-ToGsc` |
| `convert_wp.ps1` | Turn a raw waypoint capture into a `wps_<map>.gsc`, then auto-repair and validate via `wptool` |
| `shoptool.ps1` | Buy-station coverage report, and capture of the in-game editor's `MAP_EDIT::` output into paste-ready GSC |

`wptool.ps1` deliberately **will not invent links** to fix a disconnected graph — proximity
linking would route bots through walls, which is worse than an unreachable node. It reports and
leaves it to a human.

### `06-tools-server-ops/` — Fleet operations
| tool | purpose |
|---|---|
| `restart-all.ps1` | Restart servers one at a time. Kills the `cmd.exe` supervisor **before** the bootstrapper (otherwise it relaunches what you just killed), always by **exact PID** |
| `deploy-waypoints.ps1` | stop → swap a locked `.iwd` → start, with backups |
| `mw3-error-collector.ps1` | Tails all seven console logs, dedupes runtime errors by (message + top frame), correlates map/gametype, writes a digest |
| `mw3-watchdog.ps1` | Restarts a server that has stopped answering |
| `collect-feedback.ps1` | Archives in-game `!feedback` before log rotation eats it |
| `build-instance.ps1` / `build-main-instance.ps1` | Create a new server instance from a template |

⚠️ **Never kill game-server processes by name or pattern** — a regex kill once took the whole
fleet down. Every script here kills by exact PID.

### `07-web-panel/` — Status dashboard
`panel.ps1` — a self-hosted PowerShell web dashboard. Uses `getinfo` (no password, no console
echo) for the routine sweep and rcon `status` only when a player list is actually needed, because
**every rcon `status` makes the game server echo its whole player table into its own
`console.log`** — that was 91% of one server's log volume.

### `08-docs/` — Engineering notes
`GUARD-INVENTORY.md` classifies every `replaceFunc` hook as a real fix, a temporary guard, or a
feature, and records the root cause behind each — including the ones that turned out to be
mistakes. `panel-status-throttle.md` documents why the dashboard polls the way it does.

---

## Working notes worth knowing

- **Loose GSC compiles on level load, not on file write.** Deploying a script changes nothing
  until the map reloads.
- **Validate before deploying.** A loose-script compile error is a fatal `Com_ERROR` that
  boot-loops the server on *every* map load. A method-builtin copied out of stock source (e.g.
  `isusingremote()`) compiles inside the mod but **not** in a loose script.
- **`.iwd` beats loose files.** A pack inside an archive wins over the same path on disk;
  archives load alphabetically, so `zz_`-prefixed ones win.
- **Deleting an entity does not kill threads running on it.** They continue until they touch it,
  then throw. Use `endon()` against whatever the stock function notifies before it deletes.
- **Guards can mask each other.** Two fixes here once silently cancelled a gameplay feature —
  one aborted juggernaut delivery, the other quietly wrote off the missing juggernaut. Neither
  looked broken. If two guards touch the same subsystem, correlate their firing counts.

## License / use

Provided as-is for reference. Respect the upstream licenses of IW5-Survival-Reimagined and Bot
Warfare.
