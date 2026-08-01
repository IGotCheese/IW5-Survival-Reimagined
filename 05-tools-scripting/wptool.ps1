<#
.SYNOPSIS
    Bot Warfare waypoint tool - validate, repair, and convert waypoint packs in the
    EXACT format the mod's own editor produces.

.DESCRIPTION
    Every rule in this tool is taken from Bot Warfare's own source, not invented:

      maps/mp/bots/_wp_editor.gsc :: AddWaypoint             - what fields exist
      maps/mp/bots/_wp_editor.gsc :: watchSaveWaypointsCommand - the two output formats
      maps/mp/bots/_wp_editor.gsc :: checkForWarnings          - the official validator
      maps/mp/bots/_bot_utility.gsc :: getWaypointsOfType      - how "camp" is derived

    THE FIELD SPEC
      .origin     vector    ALWAYS
      .type       string    ALWAYS - stand|crouch|prone (from getstance) plus
                            climb|grenade|claymore|tube|javelin (from modifier keys)
      .children[] int[]     ALWAYS - indices into the waypoint array
      .angles     vector    REQUIRED for claymore, tube, climb, grenade, and
                            crouch-with-EXACTLY-ONE-child
      .jav_point  vector    REQUIRED for javelin only

    WHY crouch-with-one-child MATTERS
      "camp" is NOT a stored type. getWaypointsOfType( "camp" ) maps it to
      (type == "crouch" && children.size == 1). bot_think_camp_loop then calls
      anglestoforward( campSpot.angles ) with NO isdefined guard, so a camp node
      without angles throws on every camp attempt and kills the bot's AI thread.
      That single omission produced 1170 runtime errors in two waves on mp_geometric.

    WHY THE GSC ROUND-TRIP IS LOSSY
      AddWaypoint sets .angles on EVERY waypoint (it is the author's view angle).
      The CSV export writes .angles whenever it is defined, for any type.
      The GSC export writes .angles ONLY for the five types listed above.
      So GSC -> load -> GSC is lossy for every other type, and any generator that
      emits GSC without angles produces camp nodes that are guaranteed to throw.

.PARAMETER Path
    Waypoint pack to read. Accepts a .gsc (wps_<map>.gsc) or a .csv (<map>_wp.csv).

.PARAMETER Validate
    Run every check from checkForWarnings, plus link reciprocity and full
    connectivity. Exits 1 if any ERROR-level problem is found.

.PARAMETER Repair
    Fix what can be fixed safely and write the result to -Out:
      - fill missing .angles on the five types that require them, aimed along the
        node's first link (a real route) rather than an arbitrary compass direction
      - drop self-links and out-of-range child indices
      - with -Bidirectional, add the reverse edge for any one-way link

.PARAMETER ToCsv
    Write the mod's native CSV (waypoints/<map>_wp.csv) - the LOSSLESS format.

.PARAMETER ToGsc
    Write a wps_<map>.gsc. Emits angles for every node that has them, NOT just the
    five required types, so a pack survives a round-trip through this tool.

.EXAMPLE
    .\wptool.ps1 -Path .\wps_geometric.gsc -Validate

.EXAMPLE
    .\wptool.ps1 -Path .\wps_geometric.gsc -Repair -Out .\wps_geometric.fixed.gsc

.EXAMPLE
    .\wptool.ps1 -Path .\wps_geometric.gsc -ToCsv -Out .\mp_geometric_wp.csv
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [switch]$Validate,
    [switch]$Repair,
    [switch]$ToCsv,
    [switch]$ToGsc,
    [switch]$Bidirectional,
    [string]$Out,
    [string]$MapName
)

$ErrorActionPreference = 'Stop'

# The five types whose angles the mod dereferences without a guard.
# crouch is conditional on children.size -eq 1 (the "camp" query), handled in code.
$ANGLE_TYPES = @('claymore', 'tube', 'climb', 'grenade')
$VALID_TYPES = @('stand', 'crouch', 'prone', 'climb', 'grenade', 'claymore', 'tube', 'javelin')

function Format-Num([double]$v) {
    # GSC has no scientific-notation float literals. Values near zero print as
    # "1.3113e-006" from the engine and crash the compiler with "unexpected
    # identifier" if passed through raw, so always emit plain decimal.
    return $v.ToString('0.######', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Parse-Vector([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $parts = ($s -replace '[()]', '') -split '[,\s]+' | Where-Object { $_ -ne '' }
    if ($parts.Count -lt 3) { return $null }
    $ci = [System.Globalization.CultureInfo]::InvariantCulture
    return , @([double]::Parse($parts[0], $ci), [double]::Parse($parts[1], $ci), [double]::Parse($parts[2], $ci))
}

function Read-GscPack([string]$file) {
    $text = Get-Content -LiteralPath $file -Raw
    $wps = @{}

    # Tolerate both "waypoints[0]" and the editor's "waypoints[ 0 ]" spacing.
    $rxOrigin = [regex]'waypoints\[\s*(\d+)\s*\]\.origin\s*=\s*\(([^)]*)\)'
    $rxType   = [regex]'waypoints\[\s*(\d+)\s*\]\.type\s*=\s*"([^"]*)"'
    $rxChild  = [regex]'waypoints\[\s*(\d+)\s*\]\.children\[\s*(\d+)\s*\]\s*=\s*(\d+)'
    $rxAngles = [regex]'waypoints\[\s*(\d+)\s*\]\.angles\s*=\s*\(([^)]*)\)'
    $rxJav    = [regex]'waypoints\[\s*(\d+)\s*\]\.jav_point\s*=\s*\(([^)]*)\)'

    function Get-Node($h, $i) {
        if (-not $h.ContainsKey($i)) {
            $h[$i] = [pscustomobject]@{
                Index = $i; Origin = $null; Type = $null
                Children = New-Object System.Collections.ArrayList
                Angles = $null; JavPoint = $null
            }
        }
        return $h[$i]
    }

    foreach ($m in $rxOrigin.Matches($text)) { (Get-Node $wps ([int]$m.Groups[1].Value)).Origin = Parse-Vector $m.Groups[2].Value }
    foreach ($m in $rxType.Matches($text))   { (Get-Node $wps ([int]$m.Groups[1].Value)).Type   = $m.Groups[2].Value }
    foreach ($m in $rxAngles.Matches($text)) { (Get-Node $wps ([int]$m.Groups[1].Value)).Angles = Parse-Vector $m.Groups[2].Value }
    foreach ($m in $rxJav.Matches($text))    { (Get-Node $wps ([int]$m.Groups[1].Value)).JavPoint = Parse-Vector $m.Groups[2].Value }
    foreach ($m in $rxChild.Matches($text))  { [void](Get-Node $wps ([int]$m.Groups[1].Value)).Children.Add([int]$m.Groups[3].Value) }

    if ($wps.Count -eq 0) { return @() }
    $max = ($wps.Keys | Measure-Object -Maximum).Maximum
    return @(0..$max | ForEach-Object { if ($wps.ContainsKey($_)) { $wps[$_] } else { $null } })
}

function Read-CsvPack([string]$file) {
    $lines = Get-Content -LiteralPath $file
    if ($lines.Count -eq 0) { return @() }
    # First line is the count (BotBuiltinFileWrite writes it before the rows).
    $start = 0
    if ($lines[0] -match '^\s*\d+\s*$') { $start = 1 }

    $out = New-Object System.Collections.ArrayList
    for ($i = $start; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        # origin , children , type , angles , jav_point
        $f = $line -split ',', 5
        $children = New-Object System.Collections.ArrayList
        if ($f.Count -gt 1 -and -not [string]::IsNullOrWhiteSpace($f[1])) {
            foreach ($c in ($f[1] -split '\s+' | Where-Object { $_ -ne '' })) { [void]$children.Add([int]$c) }
        }
        [void]$out.Add([pscustomobject]@{
            Index    = $out.Count
            Origin   = Parse-Vector $f[0]
            Children = $children
            Type     = if ($f.Count -gt 2) { $f[2].Trim() } else { $null }
            Angles   = if ($f.Count -gt 3) { Parse-Vector $f[3] } else { $null }
            JavPoint = if ($f.Count -gt 4) { Parse-Vector $f[4] } else { $null }
        })
    }
    return $out.ToArray()
}

function Test-NeedsAngles($wp) {
    if ($null -eq $wp -or $null -eq $wp.Type) { return $false }
    if ($ANGLE_TYPES -contains $wp.Type) { return $true }
    # The "camp" query: getWaypointsOfType maps camp -> crouch with exactly one child.
    if ($wp.Type -eq 'crouch' -and $wp.Children.Count -eq 1) { return $true }
    return $false
}

function Invoke-Validate($wps) {
    $errors = 0; $warns = 0
    $n = $wps.Count
    Write-Host "waypoints: $n" -ForegroundColor Cyan

    if ($n -le 0) { Write-Host "ERROR: waypoint count is $n"; return 1 }

    for ($i = 0; $i -lt $n; $i++) {
        $wp = $wps[$i]
        if ($null -eq $wp) { Write-Host "ERROR: waypoint $i is undefined"; $errors++; continue }
        if ($null -eq $wp.Origin) { Write-Host "ERROR: waypoint $i origin is undefined"; $errors++ }

        if ($null -eq $wp.Type) {
            Write-Host "ERROR: waypoint $i type is undefined"; $errors++
        } elseif ($VALID_TYPES -notcontains $wp.Type) {
            Write-Host "ERROR: waypoint $i type '$($wp.Type)' is not a type the mod creates"; $errors++
        }

        if ($wp.Children.Count -le 0) {
            Write-Host "WARN : waypoint $i childCount is 0 (unreachable)"; $warns++
        } else {
            foreach ($c in $wp.Children) {
                if ($c -lt 0 -or $c -ge $n -or $null -eq $wps[$c]) {
                    Write-Host "ERROR: waypoint $i child $c is undefined"; $errors++
                } elseif ($c -eq $i) {
                    Write-Host "ERROR: waypoint $i child $c is itself"; $errors++
                }
            }
        }

        if ($wp.Type -eq 'javelin' -and $null -eq $wp.JavPoint) {
            Write-Host "ERROR: waypoint $i jav_point is undefined"; $errors++
        }

        # The one that actually bites: anglestoforward( campSpot.angles ) is unguarded.
        if ((Test-NeedsAngles $wp) -and $null -eq $wp.Angles) {
            $why = if ($wp.Type -eq 'crouch') { "crouch with 1 child = a CAMP spot" } else { $wp.Type }
            Write-Host "ERROR: waypoint $i angles is undefined ($why)"; $errors++
        }
    }

    # Link reciprocity. checkForWarnings' reachability pass says "assume bidirectional
    # graph", so a one-way link is a real defect even though the engine tolerates it.
    $oneway = 0
    for ($i = 0; $i -lt $n; $i++) {
        if ($null -eq $wps[$i]) { continue }
        foreach ($c in $wps[$i].Children) {
            if ($c -ge 0 -and $c -lt $n -and $null -ne $wps[$c]) {
                if ($wps[$c].Children -notcontains $i) { $oneway++ }
            }
        }
    }
    if ($oneway -gt 0) { Write-Host "WARN : $oneway one-way link(s) - reachability assumes a bidirectional graph"; $warns++ }

    # Connectivity: the offline equivalent of the in-game A* sweep, but from every
    # node rather than one random seed.
    $seed = -1
    for ($i = 0; $i -lt $n; $i++) { if ($null -ne $wps[$i]) { $seed = $i; break } }
    if ($seed -ge 0) {
        $seen = New-Object bool[] $n
        $queue = New-Object System.Collections.Queue
        $queue.Enqueue($seed); $seen[$seed] = $true; $count = 1
        while ($queue.Count -gt 0) {
            $cur = $queue.Dequeue()
            foreach ($c in $wps[$cur].Children) {
                if ($c -ge 0 -and $c -lt $n -and $null -ne $wps[$c] -and -not $seen[$c]) {
                    $seen[$c] = $true; $count++; $queue.Enqueue($c)
                }
            }
            # treat as bidirectional, matching checkForWarnings' stated assumption
            for ($j = 0; $j -lt $n; $j++) {
                if ($null -ne $wps[$j] -and -not $seen[$j] -and $wps[$j].Children -contains $cur) {
                    $seen[$j] = $true; $count++; $queue.Enqueue($j)
                }
            }
        }
        $live = ($wps | Where-Object { $null -ne $_ }).Count
        if ($count -lt $live) {
            Write-Host "ERROR: graph is not fully connected - $count of $live reachable from waypoint $seed"; $errors++
            $orphans = @(); for ($i = 0; $i -lt $n; $i++) { if ($null -ne $wps[$i] -and -not $seen[$i]) { $orphans += $i } }
            Write-Host "       unreachable: $($orphans -join ', ')"
        }
    }

    Write-Host ""
    if ($errors -eq 0) { Write-Host "PASS - $warns warning(s)" -ForegroundColor Green }
    else { Write-Host "FAIL - $errors error(s), $warns warning(s)" -ForegroundColor Red }
    return $errors
}

function Invoke-Repair($wps) {
    $n = $wps.Count
    $fixedAngles = 0; $droppedChildren = 0; $addedLinks = 0

    $fixedTypes = 0

    for ($i = 0; $i -lt $n; $i++) {
        $wp = $wps[$i]
        if ($null -eq $wp) { continue }

        # Salvage corrupt types. Packs pasted out of a console log can pick up console
        # text - mp_highrise_sh waypoint 8 shipped as type "standmap: mp_dome", i.e. the
        # line "map: mp_dome" spliced onto "stand". A defined-but-invalid type is worse
        # than a missing one: load_waypoints only defaults .type when it is UNDEFINED, so
        # a corrupt value survives and the node matches no type query at all.
        if ($null -ne $wp.Type -and $VALID_TYPES -notcontains $wp.Type) {
            $salvaged = $null
            foreach ($t in $VALID_TYPES) { if ($wp.Type.StartsWith($t)) { $salvaged = $t; break } }
            # "crouch" matches the loader's own default for a missing type.
            if ($null -eq $salvaged) { $salvaged = 'crouch' }
            $wp.Type = $salvaged
            $fixedTypes++
        }

        # Drop self-links and out-of-range indices (checkForWarnings flags both).
        $clean = New-Object System.Collections.ArrayList
        foreach ($c in $wp.Children) {
            if ($c -eq $i -or $c -lt 0 -or $c -ge $n -or $null -eq $wps[$c]) { $droppedChildren++; continue }
            if ($clean -notcontains $c) { [void]$clean.Add($c) }
        }
        $wp.Children = $clean
    }

    if ($Bidirectional) {
        for ($i = 0; $i -lt $n; $i++) {
            if ($null -eq $wps[$i]) { continue }
            foreach ($c in @($wps[$i].Children)) {
                if ($wps[$c].Children -notcontains $i) { [void]$wps[$c].Children.Add($i); $addedLinks++ }
            }
        }
    }

    # Fill angles AFTER link cleanup - whether a crouch node is a camp spot depends on
    # its final child count, so doing this first would classify some nodes wrongly.
    for ($i = 0; $i -lt $n; $i++) {
        $wp = $wps[$i]
        if ($null -eq $wp -or $null -ne $wp.Angles) { continue }
        if (-not (Test-NeedsAngles $wp)) { continue }

        $yaw = 0.0
        if ($wp.Children.Count -gt 0 -and $null -ne $wp.Origin) {
            $child = $wps[$wp.Children[0]]
            if ($null -ne $child -and $null -ne $child.Origin) {
                $dx = $child.Origin[0] - $wp.Origin[0]
                $dy = $child.Origin[1] - $wp.Origin[1]
                if (($dx * $dx + $dy * $dy) -gt 1) {
                    $yaw = [Math]::Atan2($dy, $dx) * 180.0 / [Math]::PI
                }
            }
        }
        # Aim along a real route rather than an arbitrary compass direction, so a
        # camping bot watches an approach that actually exists.
        $wp.Angles = @(0.0, $yaw, 0.0)
        $fixedAngles++
    }

    Write-Host "repaired: angles filled=$fixedAngles, corrupt types salvaged=$fixedTypes, bad children dropped=$droppedChildren, reverse links added=$addedLinks"
    return $wps
}

function Write-GscPack($wps, [string]$file, [string]$map) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("/*")
    [void]$sb.AppendLine(" * $map waypoints")
    [void]$sb.AppendLine(" * Written by wptool.ps1 in Bot Warfare's own format.")
    [void]$sb.AppendLine(" * NOTE: angles are emitted for EVERY node that has them, not only the five")
    [void]$sb.AppendLine(" * types the stock GSC dump keeps - the stock dump is lossy and silently")
    [void]$sb.AppendLine(" * strips the facing that camp spots (crouch + 1 child) require.")
    [void]$sb.AppendLine(" */")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("main()")
    [void]$sb.AppendLine("{")
    [void]$sb.AppendLine("`tlevel.waypoints = $map();")
    [void]$sb.AppendLine("}")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("$map()")
    [void]$sb.AppendLine("{")
    [void]$sb.AppendLine("    waypoints = [];")

    for ($i = 0; $i -lt $wps.Count; $i++) {
        $wp = $wps[$i]
        if ($null -eq $wp) { continue }
        [void]$sb.AppendLine("    waypoints[$i] = spawnstruct();")
        $o = $wp.Origin
        [void]$sb.AppendLine("    waypoints[$i].origin = ($(Format-Num $o[0]), $(Format-Num $o[1]), $(Format-Num $o[2]));")
        [void]$sb.AppendLine("    waypoints[$i].type = `"$($wp.Type)`";")
        [void]$sb.AppendLine("    waypoints[$i].children = [];")
        for ($c = 0; $c -lt $wp.Children.Count; $c++) {
            [void]$sb.AppendLine("    waypoints[$i].children[$c] = $($wp.Children[$c]);")
        }
        if ($null -ne $wp.Angles) {
            $a = $wp.Angles
            [void]$sb.AppendLine("    waypoints[$i].angles = ($(Format-Num $a[0]), $(Format-Num $a[1]), $(Format-Num $a[2]));")
        }
        if ($null -ne $wp.JavPoint) {
            $j = $wp.JavPoint
            [void]$sb.AppendLine("    waypoints[$i].jav_point = ($(Format-Num $j[0]), $(Format-Num $j[1]), $(Format-Num $j[2]));")
        }
    }

    [void]$sb.AppendLine("    return waypoints;")
    [void]$sb.AppendLine("}")
    Set-Content -LiteralPath $file -Value $sb.ToString() -Encoding ASCII
    Write-Host "wrote GSC: $file ($($wps.Count) waypoints)" -ForegroundColor Green
}

function Write-CsvPack($wps, [string]$file) {
    # Matches watchSaveWaypointsCommand's BotBuiltinFileWrite output exactly:
    # count on line 1, then "origin,children,type,angles,jav_point" per node.
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("$($wps.Count)")
    foreach ($wp in $wps) {
        if ($null -eq $wp) { [void]$sb.AppendLine(",,,,"); continue }
        $o = $wp.Origin
        $str = "$(Format-Num $o[0]) $(Format-Num $o[1]) $(Format-Num $o[2]),"
        $str += ($wp.Children -join ' ')
        $str += ",$($wp.Type),"
        if ($null -ne $wp.Angles) { $a = $wp.Angles; $str += "$(Format-Num $a[0]) $(Format-Num $a[1]) $(Format-Num $a[2])," } else { $str += "," }
        if ($null -ne $wp.JavPoint) { $j = $wp.JavPoint; $str += "$(Format-Num $j[0]) $(Format-Num $j[1]) $(Format-Num $j[2])," } else { $str += "," }
        [void]$sb.AppendLine($str)
    }
    Set-Content -LiteralPath $file -Value $sb.ToString() -Encoding ASCII
    Write-Host "wrote CSV: $file ($($wps.Count) waypoints)" -ForegroundColor Green
}

# ---- main ----------------------------------------------------------------

if (-not (Test-Path -LiteralPath $Path)) { throw "not found: $Path" }

$wps = if ($Path -match '\.csv$') { Read-CsvPack $Path } else { Read-GscPack $Path }
Write-Host "read $($wps.Count) waypoints from $Path"

if (-not $MapName) {
    $leaf = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $MapName = $leaf -replace '^wps_', '' -replace '_wp$', ''
}

if ($Repair) { $wps = Invoke-Repair $wps }

$exit = 0
if ($Validate -or (-not $Repair -and -not $ToCsv -and -not $ToGsc)) { $exit = Invoke-Validate $wps }

if ($Repair -and -not $Out) { throw "-Repair needs -Out" }
if ($ToCsv) { if (-not $Out) { throw "-ToCsv needs -Out" }; Write-CsvPack $wps $Out }
elseif ($ToGsc -or $Repair) { if ($Out) { Write-GscPack $wps $Out "wps_$MapName" -ErrorAction SilentlyContinue } }

exit $exit
