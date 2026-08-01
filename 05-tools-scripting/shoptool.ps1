<#
.SYNOPSIS
    Survival buy-station (armory) placement tool - coverage report + MAP_EDIT capture.

.DESCRIPTION
    WHY THIS EXISTS

    lethalbeats\Survival\armories\_spawn::init() is the only thing that spawns buy stations:

        map = getDvar( "mapname" );
        if ( isDefined( level.armories[ map ] ) )
            foreach ( armory in level.armories[ map ] )
                level thread spawnShop( armory[0], armory[1], armory[2] );

    That is a hardcoded per-map table and there is NO fallback. A map absent from the
    table gets ZERO buy stations. survivalMaps.gsc ships 43 maps; the survival rotation
    is 125. bpg_survival_autoarmories.gsc covers the gap by auto-placing from spawn
    entities, but that is an approximation - v4 of it was reverted after the verdict
    "messed the armories up even more".

    THE CORRECT WAY (the mod's own editor, same story as bot waypoints)

      1. set survival_dev_mode 2
         - >1 enables lethalbeats\survival\dev\mapedit::init()
         - ==2 ALSO makes _spawn::init() return early, so live shops do not spawn
           while you are placing them
      2. In game: +actionslot 4 = switch tool, 5 = fly, 6 = teleport, 7 = save
      3. Save prints a block to console/games_mp.log:
             MAP_EDIT:: ==================================
             level.armories["mp_x"] = [...];
             level.juggDrop["mp_x"] = [...];
             MAP_EDIT:: ==================================
      4. Feed that log to this tool with -Capture to turn it into GSC table entries.

    Hand-placed entries always beat auto-placement, so anything captured this way
    permanently removes that map from the guessing path.

.PARAMETER Coverage
    Report which maps in the survival rotation have no hand-placed entry.

.PARAMETER Capture
    Parse MAP_EDIT:: blocks out of a log and emit ready-to-paste GSC.

.PARAMETER Path
    Log file to read for -Capture (usually console.log or games_mp.log).

.EXAMPLE
    .\shoptool.ps1 -Coverage

.EXAMPLE
    .\shoptool.ps1 -Capture -Path C:\Survival\appdata\Plutonium\console.log
#>

[CmdletBinding()]
param(
    [switch]$Coverage,
    [switch]$Capture,
    [string]$Path,
    [string]$Out
)

$ErrorActionPreference = 'Stop'

$SCRIPTS = 'C:\Survival\appdata\Plutonium\storage\iw5\scripts'
$CFGGLOB = 'C:\Survival\game\*\server.cfg'

function Get-PlacedMaps {
    $maps = New-Object System.Collections.Generic.HashSet[string]
    foreach ($f in @("$SCRIPTS\survivalMaps.gsc", "$SCRIPTS\bpg_survival_autoarmories.gsc")) {
        if (-not (Test-Path -LiteralPath $f)) { continue }
        $txt = Get-Content -LiteralPath $f -Raw
        # Form 1: level.armories[ "mp_x" ] = ...  (direct literal key, survivalMaps.gsc style)
        foreach ($m in [regex]::Matches($txt, 'armories\[\s*"(mp_[a-z0-9_]+)"\s*\]')) {
            [void]$maps.Add($m.Groups[1].Value)
        }
        # Form 2: if ( map == "mp_x" ... ) { level.armories[ map ] = ... }
        # This is the mod's own idiom (see the mp_fnrp_futurama_v3 entry) and is what the
        # waypoint-derived table uses. Counting only Form 1 under-reported coverage by 84 maps.
        # Deliberately simple: `map == "mp_x"` only ever appears inside a hand-made placement
        # block in these files. An earlier attempt tried to also match the following
        # `armories[ map ]` assignment, but the condition itself contains `)` characters
        # (`!isDefined( level.armories[ map ] )`), so a `[^)]*\)` guard terminated early and
        # matched nothing — under-reporting coverage by 84 maps.
        foreach ($m in [regex]::Matches($txt, 'map\s*==\s*"(mp_[a-z0-9_]+)"')) {
            [void]$maps.Add($m.Groups[1].Value)
        }
    }
    return $maps
}

function Get-RotationMaps {
    $maps = New-Object System.Collections.Generic.HashSet[string]
    foreach ($cfg in (Get-ChildItem -Path $CFGGLOB -ErrorAction SilentlyContinue)) {
        $txt = Get-Content -LiteralPath $cfg.FullName -Raw
        foreach ($m in [regex]::Matches($txt, 'mp_[a-z0-9_]+')) { [void]$maps.Add($m.Value) }
    }
    return $maps
}

if ($Coverage) {
    $placed = Get-PlacedMaps
    $rot    = Get-RotationMaps
    $missing = @($rot | Where-Object { -not $placed.Contains($_) } | Sort-Object)

    Write-Host "rotation maps : $($rot.Count)"
    Write-Host "hand-placed   : $($placed.Count)"
    Write-Host "auto-placed   : $($missing.Count)  <- buy stations are GUESSED on these" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Maps relying on auto-placement:" -ForegroundColor Yellow
    $missing | ForEach-Object { "  $_" }
    exit 0
}

if ($Capture) {
    if (-not $Path) { throw "-Capture needs -Path <log>" }
    if (-not (Test-Path -LiteralPath $Path)) { throw "not found: $Path" }

    $txt = Get-Content -LiteralPath $Path -Raw
    $rx = [regex]'level\.(armories|juggDrop)\["(mp_[a-z0-9_]+)"\]\s*=\s*(.+?);'
    $hits = $rx.Matches($txt)

    if ($hits.Count -eq 0) {
        Write-Host "no MAP_EDIT:: output found in $Path" -ForegroundColor Yellow
        Write-Host "Place shops in game first: set survival_dev_mode 2, then +actionslot 7 to save."
        exit 1
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("// Captured from MAP_EDIT:: output by shoptool.ps1")
    [void]$sb.AppendLine("// Paste into bpg_survival_autoarmories.gsc BEFORE the auto-placement")
    [void]$sb.AppendLine("// fallback - hand-placed entries must win.")
    [void]$sb.AppendLine("")

    $seen = @{}
    foreach ($h in $hits) {
        $kind = $h.Groups[1].Value
        $map  = $h.Groups[2].Value
        $data = $h.Groups[3].Value.Trim()
        $key  = "$kind/$map"
        # A log accumulates every save; keep only the LAST capture per map+kind.
        $seen[$key] = $data
    }

    foreach ($key in ($seen.Keys | Sort-Object)) {
        $parts = $key -split '/'
        [void]$sb.AppendLine("// $($parts[1])  ($($parts[0]))")
        [void]$sb.AppendLine("level.$($parts[0])[`"$($parts[1])`"] = $($seen[$key]);")
        [void]$sb.AppendLine("")
    }

    $text = $sb.ToString()
    if ($Out) { Set-Content -LiteralPath $Out -Value $text -Encoding ASCII; Write-Host "wrote $Out" -ForegroundColor Green }
    else { Write-Output $text }

    Write-Host "captured $($seen.Count) entry/entries" -ForegroundColor Green
    exit 0
}

Write-Host "specify -Coverage or -Capture. See Get-Help .\shoptool.ps1 -Detailed"
exit 1
