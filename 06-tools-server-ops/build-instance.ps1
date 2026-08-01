# build-instance.ps1 - clone the WORKING survival server into an additional isolated
# instance. Idempotent: safe to re-run, skips anything that already exists.
#
#   .\build-instance.ps1 -Instance 2 -Port <SURV-PORT-2>
#
# Differs from build-tree.ps1 on purpose: that one builds a survival tree from scratch
# out of the LIVE <MP-PORT> server's storage. This one clones the ALREADY-CONFIGURED
# survival instance (mod installed, loose scripts, rotation, vote pool, waypoints), so a
# new server comes up behaving identically instead of needing the whole setup redone.
#
# WHAT IS SHARED vs COPIED (this is the whole design):
#   junction  bin/ games/ launcher/  -> the one real Plutonium install (read-only use)
#   junction  storage\iw5\usermaps   -> the shared usermap pool. This is the big win:
#                                       ~12GB of custom maps referenced, zero bytes copied.
#   hardlink  game\ data archives    -> same physical bytes as the Steam MW3 install,
#                                       so a "15GB game dir" costs ~0 real disk.
#   COPY      storage\iw5 (the rest) -> ~0.65GB. MUST be a real copy, never shared:
#                                       every instance writes its own games_mp.log
#                                       (IW4MAdmin tails one log per server), console.log,
#                                       players\ stats and demonware user\ state. Sharing
#                                       any of those would have two servers fighting over
#                                       the same files.
#
# ⚠️ Each instance needs its OWN sv_authtoken from platform.plutonium.pw/serverkeys.
#    Reusing a key makes duplicate heartbeats knock the OTHER servers off the browser.
#    This script writes a PLACEHOLDER; the launcher refuses to start until it is replaced.

param(
    [Parameter(Mandatory=$true)][int]$Instance,
    [Parameter(Mandatory=$true)][int]$Port
)
$ErrorActionPreference = 'Stop'

$live    = "$env:USERPROFILE\AppData\Local\Plutonium"
$srcRoot = 'C:\Survival'
$srcSt   = "$srcRoot\appdata\Plutonium\storage\iw5"
$game    = 'C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Modern Warfare 3'

$root = "C:\Survival$Instance"
$ad   = "$root\appdata\Plutonium"
$st   = "$ad\storage\iw5"
$sg   = "$root\game"

if (-not (Test-Path $srcSt)) { throw "source survival storage not found: $srcSt" }

function Mk($p)  { if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function Junc($p, $t) {
    if (-not (Test-Path $p)) { New-Item -ItemType Junction -Path $p -Target $t | Out-Null; Write-Host "  JUNC $p" }
}
function HL($p, $t) {
    if (-not (Test-Path $p)) { New-Item -ItemType HardLink -Path $p -Target $t | Out-Null }
}
function CpOnce($s, $d) { if (-not (Test-Path $d)) { Copy-Item -LiteralPath $s -Destination $d -Force } }

Write-Host "=== building instance $Instance on port $Port -> $root ==="

# ── appdata\Plutonium ────────────────────────────────────────────────────────
Mk $ad
Junc "$ad\bin"      "$live\bin"
Junc "$ad\games"    "$live\games"
Junc "$ad\launcher" "$live\launcher"
CpOnce "$live\info.json"   "$ad\info.json"
CpOnce "$live\config.json" "$ad\config.json"

# demonware: pub files shared content, but user\ state MUST be per-instance
Mk "$ad\storage\demonware\18409\pub"
Mk "$ad\storage\demonware\18409\user"
Get-ChildItem -LiteralPath "$live\storage\demonware\18409\pub" -File -EA SilentlyContinue | ForEach-Object {
    CpOnce $_.FullName "$ad\storage\demonware\18409\pub\$($_.Name)"
}

# ── storage\iw5: clone the configured survival storage ───────────────────────
Mk $st
Junc "$st\usermaps" "$srcSt\usermaps"   # shared map pool, zero copy

# Everything except usermaps (junctioned above) and per-instance runtime state.
# Logs/players are deliberately NOT copied: a fresh instance starts with its own.
$skipTop = @('usermaps','players','logs','demo')
$skipExt = @('.log')
Get-ChildItem -LiteralPath $srcSt -Force | Where-Object { $skipTop -notcontains $_.Name } | ForEach-Object {
    $dest = Join-Path $st $_.Name
    if ($_.PSIsContainer) {
        if (-not (Test-Path $dest)) {
            Copy-Item -LiteralPath $_.FullName -Destination $dest -Recurse -Force
            Write-Host "  COPY dir  $($_.Name)"
        }
    } elseif ($skipExt -notcontains $_.Extension) {
        if (-not (Test-Path $dest)) { Copy-Item -LiteralPath $_.FullName -Destination $dest -Force }
    }
}
Mk "$st\players"

# ── cloned game dir (hardlinks to the Steam install = ~0 real disk) ─────────
Mk $sg
Junc "$sg\Redist" "$game\Redist"
Junc "$sg\miles"  "$game\miles"

$skipRoot = @('!start_mp_server.bat','Thumbs.db','zonetool.dll','zonetool_iw5.exe')
Get-ChildItem -LiteralPath $game -File | Where-Object { $skipRoot -notcontains $_.Name } | ForEach-Object {
    HL "$sg\$($_.Name)" $_.FullName
}

Mk "$sg\main"
Get-ChildItem -LiteralPath "$game\main" -File | Where-Object { $_.Extension -in '.iwd','.sdm' } | ForEach-Object {
    HL "$sg\main\$($_.Name)" $_.FullName
}
Junc "$sg\main\video" "$game\main\video"

# admin\ + zone\english: copy from the SURVIVAL clone, not stock - the mod replaces
# localized_code_post_gfx_mp.ff and drops its .dsr difficulty recipes into admin\.
Mk "$sg\admin"
Get-ChildItem -LiteralPath "$srcRoot\game\admin" -File -EA SilentlyContinue | ForEach-Object {
    CpOnce $_.FullName "$sg\admin\$($_.Name)"
}

Mk "$sg\zone"
Junc "$sg\zone\dlc" "$game\zone\dlc"
Mk "$sg\zone\english"
Get-ChildItem -LiteralPath "$srcRoot\game\zone\english" -File -EA SilentlyContinue | ForEach-Object {
    CpOnce $_.FullName "$sg\zone\english\$($_.Name)"
}

# ── per-instance config ─────────────────────────────────────────────────────
# Derived from the live survival cfg so rotation/vote/mod settings match exactly;
# only identity, port and key differ.
Mk "$root\main"
$cfgSrc = "$srcRoot\main\server.cfg"
$cfgDst = "$root\main\server.cfg"
if (-not (Test-Path $cfgDst)) {
    $cfg = Get-Content $cfgSrc -Raw
    $cfg = $cfg -replace 'set sv_hostname\s+"[^"]*"', ("set sv_hostname        `"^6yourserver.gg ^3Your Server Survival #$Instance`"")
    $cfg = $cfg -replace 'set net_port\s+\d+',        ("set net_port            $Port")
    $cfg = $cfg -replace 'set sv_authtoken\s+"[^"]*"', 'set sv_authtoken       "PASTE_NEW_KEY_HERE"'
    Set-Content -Path $cfgDst -Value $cfg -Encoding ASCII
    Write-Host "  WROTE $cfgDst  (port $Port, placeholder key)"
}
CpOnce "$srcRoot\main\autoexec.cfg" "$root\main\autoexec.cfg"

# ── launcher ────────────────────────────────────────────────────────────────
$batDst = "$root\LAUNCH-SURVIVAL$Instance.bat"
if (-not (Test-Path $batDst)) {
    $bat = Get-Content "$srcRoot\LAUNCH-SURVIVAL.bat" -Raw
    $bat = $bat -replace [regex]::Escape('set "ROOT=C:\Survival"'), ("set `"ROOT=$root`"")
    $bat = $bat -replace '\+net_port <SURV-PORT-1>', "+net_port $Port"
    $bat = $bat -replace 'localport=<SURV-PORT-1>',  "localport=$Port"
    $bat = $bat -replace 'MW3 Survival Server \(<SURV-PORT-1>\)', "MW3 Survival Server #$Instance ($Port)"
    $bat = $bat -replace 'Port   : <SURV-PORT-1>', "Port   : $Port"
    $bat = $bat -replace 'LocalPort <SURV-PORT-1>', "LocalPort $Port"
    Set-Content -Path $batDst -Value $bat -Encoding ASCII
    Write-Host "  WROTE $batDst"
}

Write-Host "=== instance $Instance built ==="
Write-Host "    NEXT: put a real server key in $cfgDst  (sv_authtoken)"
