# Guard inventory — what is a guard, what is a feature, and what the real fix is

Generated 2026-07-31. 52 `replaceFunc` hooks on survival, 6 on main.

A **guard** suppresses an error caused by missing data. A **feature replacement** changes
behaviour on purpose. Only the first group is in scope for "fix it properly" — the second
group is working as intended.

## A. Guards with a KNOWN real fix (do these)

| hook | what's missing | the real fix |
|---|---|---|
| ~~`maps\mp\bots\_bot_script::bot_cap`~~ **RESOLVED 07-31** | `level.teamflags[team]` / `capzones[team]` — map had no CTF flags | **Real fix shipped: `ctf_fix_bo2frost()` in loose `ctf.gsc`**, live on all 3 main trees. Guard deleted — it was redundant *and* broken (see below). ~75 other maps remain exposed to the same class; each needs its own `ctf_fix_<map>`. |
| `lethalbeats\survival\utility::survivor_switch_to_weapon` | nothing — wrong layer entirely | `weapon_build` emits `base_mp_` / `base_mp__camo`. Fix the name builder. Diagnostic now live to capture the exact string. |
| `lethalbeats\player::player_give_weapon` | give silently fails | Same root cause as above. This hook is the damage-control layer *and* the instrument that will produce the fix. |
| `lethalbeats\survival\armories\_spawn::spawnShopModel` | `care_package` brush absent on custom maps | Ship the brush, or accept — see section C. |
| `maps\mp\_animatedmodels::animatemodel` *(main)* **CAUSE FOUND 07-31 — not GSC-fixable** | `_animatedmodels::main` starts `level.anim_prop_models` **empty** and never fills it. Registration belongs in the map's own script chain — confirmed by `mp_dome.gsc` calling `mp_dome_precache::main()` **before** `_load::main()` (which runs `_animatedmodels`). Custom ports ship the `animated_model` entities without that registration. | Not fixable from a server script — see the research note below. Guard now names the offending model once per map (`[BPG-ANIM]`) so we learn exactly which map/model to target. |
| `lethalbeats\DynamicMenus\dynamic_shop::updateLabels` **CAUSE FOUND 07-31** | `closeShop` (dynamic_shop.gsc:126-131) sets **both** `menuPages = []` and `shop = undefined`; an update queued before the close lands after it, `getPage` returns undefined, and stock feeds that straight into `tableLookup` | Guard is genuinely correct — there is no page to draw on a closed shop. Upgraded to tell the two cases apart: benign close-race is now **silent**, while an **open** shop with a broken `menuPages` stack is logged loudly as a real navigation bug. |

## B. Backstops that should become unnecessary

| hook | why it exists | how it retires |
|---|---|---|
| shop `isMenuBusy` watchdog | an error inside `onMenuResponse` kills the per-player loop forever | Retires by itself once the give-path errors stop. |
| wave-stall backstop | uncounted kills leave a wave unable to end | Find the remaining uncounted paths. Two already fixed for real (`givePredator`, tank). **2 counts still leaking, type unidentified.** |
| wave-end sweep | chopper/pavelow call `bot_kill` on the VEHICLE and leave the owner bot alive | Requires changing that contract in the mod — deliberate upstream design, so the sweep is arguably correct. |

## C. Legitimately permanent guards

Keep these. The missing thing genuinely does not matter, and no upstream fix exists:

- **Waypoint `.angles` fill** — not a guard at all; it fills the one field `load_waypoints`
  forgets to normalize. The permanent fix is repaired packs (staged).
- **Heli node synthesis** — maps ship no `heli_start` nodes; synthesizing them is the only
  option short of editing every map's entities.
- **Destructible guards** — `_destructible` whole-file override is PROVEN boot-death;
  `replaceFunc` is the only safe way to patch those.

## D. Not guards — features (out of scope)

Dog behaviour, martyrdom, chemical, sentry, airdrop/perk delivery, AH6 nerf, bank/vault,
`!afk`, riot shield, difficulty, damage modifiers, `logPrintPlayerDeath` (stats), gun game.
These replace behaviour on purpose.

## Method note

Every entry in section A was reached by reading the mod's real source.

**Update 2026-07-31: both "never investigated" gaps are now closed.** `updateLabels` was a
close/update race (guard correct, now diagnostic); `animatemodel` is unfixable from script
and is the one genuinely permanent guard in section A. Neither was guessed — both causes
were read out of the source.

What that leaves genuinely open in section A: the `weapon_build` name bug (instrumented,
waiting on one captured string), and `ctf_fix_<map>` for the ~75 maps beyond bo2frost.

---

## Post-mortem: the bot_cap guard caused an outage

`bpg_botcap_ctfguard.gsc` boot-looped **<MP-PORT-3>** on 2026-07-31:
`Com_ERROR: compiler:...:79:13: couldn't determine function call type` — line 79 was
`if ( self isusingremote() || self.bot_lock_goal )`.

**Two failures, both mine:**

1. **A method-builtin copied out of stock source does not compile in a loose script.**
   `isusingremote()` resolves fine inside `_bot_script.gsc` (shipped in `z_svr_bots.iwd`)
   but not in a loose `scripts/*.gsc`. Copying a stock function body into a loose
   `replaceFunc` is unsafe whenever that body calls method-builtins. Any loose-script
   compile error is a fatal `Com_ERROR` that boot-loops on **every** map load.

2. **The checker caught it and I shipped anyway.** `iw5gsc check` reported
   `GSC3009: No function named 'isusingremote'` before deploy. I moved on to another
   question and left the file in place. **A failed check means remove the file, not
   leave it and come back later.**

Another session recovered it (move-aside + RCON `map mp_bootleg`) and independently
wrote the correct `ctf_fix_bo2frost()`. Its base coordinates
`(-2611,-453,65)` / `(2570,291,-11)` match the farthest-apart waypoint pair computed
here `(-2703,-478,65)` / `(2666,291,-11)` — two methods, same bases, which is good
corroboration that waypoint extremes are a sound way to site CTF bases.

**⚠️ More than one session edits this box.** Read a file before writing it; this guard
would have been duplicated otherwise.

---

## Research note: how far the `animatemodel` fix actually goes

Chased the real registration rather than assuming. What was established:

1. **Where registration belongs.** `_animatedmodels::main` creates `level.anim_prop_models`
   empty and never populates it. `mp_dome.gsc` (stock, decompiled) calls
   `maps\mp\mp_dome_precache::main()` *before* `maps\mp\_load::main()` — and `_load` is what
   runs `_animatedmodels`. So the per-map precache script is the registration point.

2. **The data is not published.** `SkyN9ne/Plutonium-IW5-GSC` (branch `master`, not `main`)
   ships only the shared `maps/mp/_*.gsc` plus a single `mp_dome.gsc`. There are **no
   per-map `_precache.gsc` files**, so no public source carries the `anim_prop_models`
   registrations. Our local `RawFiles` has the same 28 shared scripts and no map scripts.

3. **The animation is an asset, not just a name.** Animations come from the
   `animated_props` animtree and must be `precachempanim`'d. Registering a name borrowed
   from another map would still fail, because the xanim has to be present in *this* map's
   loaded fastfiles. That is why no GSC-only fix exists.

4. **Verifying what a map actually ships is currently blocked.** Checking whether a failing
   map's fastfile contains the xanim needs OAT — but `mp_abandon.ff` reports
   `magic=IWffu100 version=2000`, and OAT fails with *"Could not create factory for zone"*.
   All our map fastfiles are v2000, the known block-table wall from
   internal notes.

**Path to a genuine fix, if it's ever worth it:**
patch OAT for v2000 (IW5 `XFileBlock` enum + `MAX_XFILE_COUNT`, rebuild via premake5 + VS
BuildTools) → dump the map named by `[BPG-ANIM]` → if the xanim IS present, register it in a
loose script before `_load::main()`; if it is ABSENT, the map fastfile itself has to be
rebuilt. Either way this is map-porting work, not server scripting.

**Prerequisite:** the `[BPG-ANIM]` line must first name a real map + model. Nothing has been
captured yet — the guard had been silently skipping, and logs truncate on restart.
