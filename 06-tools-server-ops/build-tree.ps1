# build-tree.ps1 - builds the isolated file tree for the SURVIVAL server instance.
# Idempotent: safe to re-run; skips anything that already exists.
#
# Layout:
#   C:\Survival\appdata\Plutonium   <- isolated %LOCALAPPDATA%\Plutonium for this instance
#       bin/ games/ launcher/           <- junctions to the real Plutonium install (shared, read-only use)
#       storage\iw5\                    <- ISOLATED storage (the whole point: the survival mod's
#                                          root iwds / loose scripts / zone .ff replacements must
#                                          NEVER load on the live <MP-PORT> server)
#           usermaps                    <- junction to live storage usermaps (all custom maps, zero copy)
#           zone\                       <- plutonium core .ff hardlinked; the 3 files the mod
#                                          replaces are real COPIES (never hardlink a file that
#                                          will be overwritten - it would clobber the live copy)
#   C:\Survival\game                <- hardlink clone of the 15GB MW3 install; real dirs for
#                                          main\ admin\ zone\english (mod replaces localized_code_post_gfx_mp.ff)
$ErrorActionPreference = 'Stop'

$live   = "$env:USERPROFILE\AppData\Local\Plutonium"
$liveSt = "$live\storage\iw5"
$root   = 'C:\Survival'
$ad     = "$root\appdata\Plutonium"
$st     = "$ad\storage\iw5"
$game   = 'C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Modern Warfare 3'
$sg     = "$root\game"
$srvSrc = 'C:\Ops'

function Mk($p)  { if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null } }
function Junc($p, $t) {
    if (-not (Test-Path $p)) { New-Item -ItemType Junction -Path $p -Target $t | Out-Null; Write-Host "JUNC $p -> $t" }
}
function HL($p, $t) {
    if (-not (Test-Path $p)) { New-Item -ItemType HardLink -Path $p -Target $t | Out-Null }
}
function CpOnce($s, $d) {
    if (-not (Test-Path $d)) { Copy-Item -LiteralPath $s -Destination $d; Write-Host "COPY $d" }
}

# ── appdata\Plutonium ────────────────────────────────────────────────────────
Mk $ad
Junc "$ad\bin"      "$live\bin"
Junc "$ad\games"    "$live\games"
Junc "$ad\launcher" "$live\launcher"
CpOnce   "$live\info.json"   "$ad\info.json"
CpOnce   "$live\config.json" "$ad\config.json"

# ── demonware publisher files (2026-07-16) ──────────────────────────────────
# Plutonium's DW emulator serves "publisher files" from storage\demonware\18409\pub
# (18409 = MW3 title id). Without them every lobby tick spams
# "[DW][Lobby] ERROR: Could not find publisher file ...". Real copies, own user\ dir
# (user\ holds per-instance DW state - never share it with the live instance).
Mk "$ad\storage\demonware\18409\pub"
Mk "$ad\storage\demonware\18409\user"
Get-ChildItem -LiteralPath "$live\storage\demonware\18409\pub" -File -EA SilentlyContinue | ForEach-Object {
    CpOnce $_.FullName "$ad\storage\demonware\18409\pub\$($_.Name)"
}

# ── isolated storage\iw5 ─────────────────────────────────────────────────────
Mk $st
Mk "$st\players"
Mk "$st\scripts"
Mk "$st\zone"
Mk "$st\mods"
Junc "$st\usermaps" "$liveSt\usermaps"

# Per user 2026-07-15: bring over ONLY the maps + the map vote - none of the live
# server's other customizations (no welcome/chat scripts, no weapon patch, no bots.txt,
# no patched Bot Warfare - the patched iwd depends on live's loose _class.gsc override
# and crash-loops without it: "botgiveloadout referenced unknown function isvalidcombination").
CpOnce "$srvSrc\mods\Waypoints.iwd"  "$st\Waypoints.iwd"    # map-support: waypoints so survival enemies can navigate custom maps
# IW5_MapVote.iwd NOT copied (2026-07-16): its endGame hook never fires in the survival
# gametype; replaced by LastDemon's VoteSystem (scripts\bpg_survival_votesystem.gsc).
CpOnce "$srvSrc\mods\z_svr_bots.iwd.pre-botweaponfix-bak" "$st\z_svr_bots.iwd"  # closest-to-vanilla Bot Warfare (survival mod prerequisite); replace with fresh vanilla if it misbehaves

# Bot Warfare per-map waypoint scripts (pool maps etc.)
if ((Test-Path "$liveSt\scripts\mp") -and -not (Test-Path "$st\scripts\mp")) {
    Copy-Item -Recurse "$liveSt\scripts\mp" "$st\scripts\mp"
    Write-Host "COPY $st\scripts\mp (waypoint scripts)"
}

# Stock-remake maps installed at storage root on the live server (favela/highrise/
# nightshift/nuked/rust) + plutonium's cheytac weapon iwd.
# REAL COPIES, not hardlinks: a future Plutonium update could rewrite storage files
# in place, and a write through a hardlink would corrupt the live server's copy.
foreach ($f in 'mp_favela.iwd','mp_highrise.iwd','mp_nightshift.iwd','mp_nuked.iwd','mp_rust.iwd','plutonium_cheytac.iwd') {
    CpOnce "$liveSt\$f" "$st\$f"
}

# zone: plutonium core + team skins + remake-map fastfiles -> hardlink.
# EXCLUDED on purpose: common_mp.ff / patch_mp.ff (the beamxrz weapon patch - survival
# runs vanilla stats + its own balancing), mod.ff (live-server stray), mp_test.ff (removed map).
$zoneHL = @(
    'mp_favela.ff','mp_favela_load.ff','mp_highrise.ff','mp_highrise_load.ff',
    'mp_nightshift.ff','mp_nightshift_load.ff','mp_nuked.ff','mp_nuked_load.ff',
    'mp_rust.ff','mp_rust_load.ff',
    'plutonium_common_map.ff','plutonium_common_mp.ff','plutonium_controller_mp.ff',
    'plutonium_dlc01_ui_mp.ff','plutonium_ui_mp.ff',
    'team_delta_multicam.ff','team_opforce_air.ff','team_opforce_henchmen.ff',
    'team_opforce_snow.ff','team_sas_urban.ff'
)
foreach ($f in $zoneHL) { CpOnce "$liveSt\zone\$f" "$st\zone\$f" }   # copies, not hardlinks (see above)

# The 3 zone files the survival mod REPLACES: real copies (placeholder = live's
# current plutonium versions; the mod install overwrites these copies later).
foreach ($f in 'localized_code_post_gfx_mp.ff','plutonium_code_post_gfx_mp.ff','plutonium_patch_mp.ff') {
    CpOnce "$liveSt\zone\$f" "$st\zone\$f"
}

# ── cloned game dir ──────────────────────────────────────────────────────────
Mk $sg
Junc "$sg\Redist" "$game\Redist"
Junc "$sg\miles"  "$game\miles"

# root files (skip: launcher bat, zonetool, dump/zone_source, Thumbs.db)
$skipRoot = @('!start_mp_server.bat','Thumbs.db','zonetool.dll','zonetool_iw5.exe')
Get-ChildItem -LiteralPath $game -File | Where-Object { $skipRoot -notcontains $_.Name } | ForEach-Object {
    HL "$sg\$($_.Name)" $_.FullName
}

# main\: hardlink the iwd data archives + 0.sdm; junction video; own cfgs (written separately)
Mk "$sg\main"
Get-ChildItem -LiteralPath "$game\main" -File | Where-Object { $_.Extension -in '.iwd','.sdm' } | ForEach-Object {
    HL "$sg\main\$($_.Name)" $_.FullName
}
Junc "$sg\main\video" "$game\main\video"

# admin\: real copies (survival .dsr recipes land here after the mod download)
Mk "$sg\admin"
Get-ChildItem -LiteralPath "$game\admin" -File | ForEach-Object { CpOnce $_.FullName "$sg\admin\$($_.Name)" }

# zone\: junction dlc; english = per-file hardlinks EXCEPT the file the mod replaces (real copy)
Mk "$sg\zone"
Junc "$sg\zone\dlc" "$game\zone\dlc"
Mk "$sg\zone\english"
Get-ChildItem -LiteralPath "$game\zone\english" -File | ForEach-Object {
    if ($_.Name -eq 'localized_code_post_gfx_mp.ff') {
        CpOnce $_.FullName "$sg\zone\english\$($_.Name)"        # mod overwrites this copy
    } else {
        HL "$sg\zone\english\$($_.Name)" $_.FullName
    }
}

Write-Host ''
Write-Host 'Tree build complete.'
