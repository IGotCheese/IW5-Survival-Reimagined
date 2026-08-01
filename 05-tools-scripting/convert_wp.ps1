param(
    [string]$InFile,
    [string]$OutFile,
    [string]$MapName
)

$lines = Get-Content $InFile
$sb = New-Object System.Text.StringBuilder

[void]$sb.AppendLine("/*")
[void]$sb.AppendLine(" * $MapName waypoints - auto-generated 2026-07-19 by bpg_wpgen (headless side-test densifier)")
[void]$sb.AppendLine(" * seeds=25 (tdm/dm spawns), grid-expanded to 500 (cap), cross-linked")
[void]$sb.AppendLine(" */")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("main()")
[void]$sb.AppendLine("{")
[void]$sb.AppendLine("	level.waypoints = $MapName();")
[void]$sb.AppendLine("}")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("$MapName()")
[void]$sb.AppendLine("{")
[void]$sb.AppendLine("    waypoints = [];")

foreach ($line in $lines) {
    if ($line -notmatch '^BPGWP;') { continue }
    $parts = $line -split ';'
    $idx = $parts[1]
    # GSC has no scientific-notation float literals - values near zero (e.g. "1.3113e-006")
    # print that way from the engine and crash the compiler ("unexpected identifier") if
    # passed through raw. Parse + reformat each component as plain decimal.
    $originParts = ($parts[2].Trim() -split '\s+') | ForEach-Object {
        $v = [double]::Parse($_, [System.Globalization.CultureInfo]::InvariantCulture)
        $v.ToString("0.######", [System.Globalization.CultureInfo]::InvariantCulture)
    }
    $originStr = $originParts -join ', '
    $childrenStr = $parts[3].Trim()
    $type = $parts[4].Trim()

    [void]$sb.AppendLine("    waypoints[$idx] = spawnstruct();")
    [void]$sb.AppendLine("    waypoints[$idx].origin = ($originStr);")
    [void]$sb.AppendLine("    waypoints[$idx].type = `"$type`";")
    [void]$sb.AppendLine("    waypoints[$idx].children = [];")

    if ($childrenStr -ne "") {
        $children = $childrenStr -split '\s+'
        $c = 0
        foreach ($child in $children) {
            [void]$sb.AppendLine("    waypoints[$idx].children[$c] = $child;")
            $c++
        }
    }
}

[void]$sb.AppendLine("    return waypoints;")
[void]$sb.AppendLine("}")

Set-Content -Path $OutFile -Value $sb.ToString() -Encoding ASCII
Write-Host "Wrote $OutFile"
(Get-Content $OutFile | Measure-Object -Line).Lines

# ── 2026-08-01: repair + validate before the pack is ever deployed ────────────────────────────
# This converter emits origin/type/children only. It has never emitted .angles, and Bot Warfare
# dereferences that field with NO guard for five cases: claymore, tube, climb, grenade, and
# crouch-with-exactly-one-child (which getWaypointsOfType maps to "camp"). A missing angle there
# throws inside bot_think_camp_loop and KILLS the bot's AI thread - 1170 errors in two waves on
# mp_geometric, and 132 bad waypoints across 9 of 15 live packs before this was caught.
#
# Rather than duplicate the field rules here, hand off to wptool.ps1, which derives them from
# the mod's own _wp_editor.gsc and also validates against its checkForWarnings rules. Fixing the
# pack at generation time is the real fix; the load-time angle fill on the servers is only a
# safety net for packs that predate this.
$wptool = Join-Path (Split-Path -Parent $PSCommandPath) 'wptool.ps1'
if (Test-Path $wptool) {
    Write-Host "repairing + validating via wptool..."
    & $wptool -Path $OutFile -Repair -Out $OutFile
    & $wptool -Path $OutFile -Validate
    if ($LASTEXITCODE -ne 0) {
        # Non-fatal on purpose: the usual residue is graph connectivity, which wptool will NOT
        # fake (linking by proximity would route bots through walls). Surface it and let the
        # caller decide whether the pack needs an in-game healing pass.
        Write-Host "WARNING: $OutFile still has $LASTEXITCODE validation error(s) - see output above." -ForegroundColor Yellow
    } else {
        Write-Host "pack validates clean." -ForegroundColor Green
    }
} else {
    Write-Host "WARNING: wptool.ps1 not found next to this script - pack NOT validated." -ForegroundColor Yellow
}
