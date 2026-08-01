# mw3-error-collector.ps1 — auto-detect + triage GSC script errors for the Your Server MW3 server.
# Continuously tails %LOCALAPPDATA%\Plutonium\console.log, parses "script runtime error" blocks,
# deduplicates them by (message + top stack frame), correlates each with the map/gametype that was
# loaded at the time, and writes a compact digest to C:\Ops\script-errors.md.
#
# The digest turns a multi-thousand-line error flood into a handful of unique signatures with counts,
# first/last-seen, map context, and the call stack — ready to hand to Claude for diagnosis/repair.
# Known-benign signatures are tagged [KNOWN] so genuinely NEW errors stand out as [NEW].
#
# Runs continuously; started by a scheduled task at logon (mirrors mw3-watchdog.ps1). Single-instance.

$ErrorActionPreference = 'SilentlyContinue'

# 2026-08-01: was a single log ("$env:LOCALAPPDATA\Plutonium\console.log" = <MP-PORT> only), so
# errors on the survival fleet and both main clones were INVISIBLE to the digest - six of the
# seven servers. Now tails all seven. Each signature records which server(s) it came from, so
# a survival-only fault is not mistaken for a fleet-wide one.
$servers = @(
  @{ Name = 'main-<MP-PORT>';  Path = "$env:LOCALAPPDATA\Plutonium\console.log" },
  @{ Name = 'surv-<SURV-PORT-1>';  Path = 'C:\Survival\appdata\Plutonium\console.log'  },
  @{ Name = 'surv-<SURV-PORT-2>';  Path = 'C:\Survival2\appdata\Plutonium\console.log' },
  @{ Name = 'surv-<SURV-PORT-3>';  Path = 'C:\Survival3\appdata\Plutonium\console.log' },
  @{ Name = 'surv-<SURV-PORT-4>';  Path = 'C:\Survival4\appdata\Plutonium\console.log' },
  @{ Name = 'main2-<MP-PORT-2>'; Path = 'C:\Main2\appdata\Plutonium\console.log' },
  @{ Name = 'main3-<MP-PORT-3>'; Path = 'C:\Main3\appdata\Plutonium\console.log' }
)
$digest  = 'C:\Ops\script-errors.md'
$crashLog = 'C:\Ops\crash-log.md'      # chronological, append-only: crashes / boot-fatals / restarts
$wdLog   = 'C:\Ops\watchdog.log'
$stateF  = 'C:\Ops\.script-errors.state.json'
$pollSec = 10

# Single-instance guard.
$mtx = New-Object System.Threading.Mutex($false,'Global\YourServerMW3ErrorCollector')
try { $acquired = $mtx.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }
if (-not $acquired) { exit 0 }

# ── Known-benign signature notes (Claude-maintained). Matched as substrings of the signature. ──
# Keeps the diagnosed, non-fatal, pre-existing noise from masking genuinely new problems.
# Keys are "fragment|fragment" pairs; ALL fragments must appear somewhere in (message + full stack).
$known = @{
  'clonebrushmodeltoscriptmodel|createairdropcrate' = 'RESOLVED 2026-07-04: guarded in grnd.gsc::randomdrops (skips care-package drop when no crate-collision brush). Should no longer appear.'
  'getent|_airdrop'                                 = 'RESOLVED 2026-07-04: guarded _airdrop.gsc::init (both crate-collision lookups now check level.airdropcrates[0]/.target exists). Verified 0 errors on custom shortdust. Should not reappear.'
  'field object|_airdrop'                           = 'RESOLVED 2026-07-04: guarded _airdrop.gsc::init (empty airdropcrates array on custom maps). Verified 0 errors on custom shortdust. Should not reappear.'
  'unmatching types|_escortairdrop'                 = 'RESOLVED 2026-07-04: _escortairdrop.gsc::init now defaults level.heli_maxhealth=2000 when undefined (custom maps). Verified 0 errors on custom shortdust. Should not reappear.'
  'setexpfog|mp_shipmentlong'                       = "Shipmentlong's own fog script bug. Cosmetic, map-side."
  'playsound|_breakexplosion'                       = 'Breakable-window sound alias missing on some ports. Cosmetic.'
  'giveweapon|botgiveloadout'                       = 'RESOLVED 2026-07-04: bots now get the BARE base weapon (no attachments/camo) in botGiveLoadout -- attachments do nothing for script-aimed bots and un-precached variants were the #1 error source (~382/window). Verified on live: weaponfix ACTIVE + 0 botgiveloadout errors. Should not reappear.'
  'giveweapon|giveloadout'                          = 'HUMAN custom-class variant not precached on this map (stack: giveloadout@_class.gsc <- menuclass). Stock Plutonium path, NOT bpg-rescued and left alone (humans keep their real attachments). Rare + cosmetic (player still spawns).'
  'setspawnweapon|giveloadout'                      = 'Precache-miss -> rescued. Working as designed.'
  'switchtoweapon|giveloadout'                      = 'Precache-miss -> rescued. Working as designed.'
  'givemaxammo|bpg_ss'                               = 'RESOLVED 2026-07-04: Sharpshooter bad gun name (iw5_desert->iw5_deserteagle) + hasweapon guard. Should not reappear.'
  'switchtoweaponimmediate|bpg_ss'                   = 'RESOLVED 2026-07-04: Sharpshooter guard added. Should not reappear.'
  'play_sound|_destructible'                         = 'Ported-map destructible prop sound alias missing. Cosmetic; whole-file _destructible override = PROVEN boot-death (setdot_ontick LinkFile); sound part left alone.'
  'gettagorigin|explode'                             = 'RESOLVED 2026-07-05: scripts/bpg_destructible_fix.gsc replaceFunc-guards explode/physics_launch/fx_think (broken destructible tags + forced re-explosions). Should fade out.'
  'OP_minus|explode'                                 = 'RESOLVED 2026-07-05: bpg_destructible_fix. Should fade out.'
  'vectornormalize|explode'                          = 'RESOLVED 2026-07-05: bpg_destructible_fix. Should fade out.'
  'physicsexplosionsphere|explode'                   = 'RESOLVED 2026-07-05: bpg_destructible_fix (explosion origin can no longer be undefined). Should fade out.'
  'radiusdamage|explode'                             = 'RESOLVED 2026-07-05: bpg_destructible_fix. Should fade out.'
  'earthquake|explode'                               = 'RESOLVED 2026-07-05: bpg_destructible_fix. Should fade out.'
  'unmatching types|explode'                         = 'RESOLVED 2026-07-05: bpg_destructible_fix. Should fade out.'
  'spawn|physics_launch'                             = 'RESOLVED 2026-07-05: bpg_destructible_fix. Should fade out.'
  'gettagorigin|physics_launch'                      = 'RESOLVED 2026-07-05: bpg_destructible_fix. Should fade out.'
  'gettagangles|physics_launch'                      = 'RESOLVED 2026-07-05: bpg_destructible_fix. Should fade out.'
  'setmodel|physics_launch'                          = 'RESOLVED 2026-07-05: bpg_destructible_fix. Should fade out.'
  'physicslaunchclient|physics_launch'               = 'RESOLVED 2026-07-05: bpg_destructible_fix. Should fade out.'
  'field object|physics_launch'                      = 'RESOLVED 2026-07-05: bpg_destructible_fix. Should fade out.'
  'hidepart|hideapart'                               = 'RESOLVED 2026-07-05: bpg_destructible_fix (part-toss skipped when tag missing). Should fade out.'
  'gettagorigin|destructible_fx_think'               = 'RESOLVED 2026-07-05: bpg_destructible_fix. Should fade out.'
  'OP_minus|destructible_fx_think'                   = 'RESOLVED 2026-07-05: bpg_destructible_fix. Should fade out.'
  'unmatching types|destructible_fx_think'           = 'RESOLVED 2026-07-05: bpg_destructible_fix. Should fade out.'
  'playfx|destructible_fx_think'                     = 'RESOLVED 2026-07-05: bpg_destructible_fix. Should fade out.'
  'OP_vector|finishsupportescortusage'               = 'RESOLVED 2026-07-05: _escortairdrop finish* guards (custom maps lack airstrikeheight/heli nodes -> killstreak fizzles cleanly).'
  'spawnhelicopter|createairship'                    = 'RESOLVED 2026-07-05: _escortairdrop finish* guards. Should not reappear.'
  'field object|drown'                               = 'RESOLVED 2026-07-10: scripts/bpg_drown_fix.gsc no-ops maps\mp\_drown::drown (was error-storming ~130k/5min on mp_poolday - bots drowning, newClientHudElem undefined cascade). Should not reappear.'
  'newclienthudelem|drown'                           = 'RESOLVED 2026-07-10: bpg_drown_fix (drown no-op). Should not reappear.'
  'setshader|drown'                                  = 'RESOLVED 2026-07-10: bpg_drown_fix. Should not reappear.'
  'istouching|drown'                                 = 'RESOLVED 2026-07-10: bpg_drown_fix. Should not reappear.'
  'destroy|drown'                                    = 'RESOLVED 2026-07-10: bpg_drown_fix. Should not reappear.'
  'scaleovertime|drown'                              = 'RESOLVED 2026-07-10: bpg_drown_fix. Should not reappear.'
  'undefined to bool|drown'                          = 'RESOLVED 2026-07-10: bpg_drown_fix. Should not reappear.'
  'OP_SetSelfFieldVariableField|drown'               = 'RESOLVED 2026-07-10: bpg_drown_fix. Should not reappear.'
  'cast undefined to bool|playsoundseeee'            = 'mp_lockout_h2 map-author custom ambient-sound fn error-storm (~7.5k/11min, distance2d/istouching on undefined/dead ents). Map-side (in the usermap fastfile), lower severity than drown. Not yet fixed - replaceFunc-ing a per-map fn from a global script is fragile (ref fails to link on other maps).'
  'distance2d|playsoundseeee'                        = 'mp_lockout_h2 map-author ambient-sound bug. Map-side. See cast-undefined|playsoundseeee note.'
  'istouching|playsoundseeee'                        = 'mp_lockout_h2 map-author ambient-sound bug. Map-side.'
  'playsound|pipefx'                                 = 'mp_cargoship_sh pipe fx sound alias missing. Map-side, cosmetic.'
  'setexpfog|mp_efa_lake'                            = "efa_lake's own fog script call. Map-side, cosmetic."
  'OP_inc|doairstrike'                               = 'Airstrike on a custom map without bounds (same family as selectairstrikelocation). Cosmetic; airstrike no-ops.'
  'OP_dec|doairstrike'                               = 'Airstrike on a custom map without bounds. Cosmetic.'
  'playdeathsound|_utility'                          = 'Ported-map death sound alias missing. Cosmetic; core _utility override too risky (M75q only).'
  'selectairstrikelocation|_airstrike'               = 'Custom map lacks airstrike bounds. Cosmetic; airstrike no-op there (M75q only).'
  'beginlocationselection|_airstrike'                = 'Same as selectairstrikelocation - custom-map airstrike bounds. Cosmetic.'
  'photo_copier_init|_dynamic_world'                 = "Custom map's own dynamic-world prop init (e.g. checkpoint). Map-side, cosmetic."
  'setexpfog|_art'                                   = "Ported map's own art-script fog call (bo2cove/broadcast). Map-side, cosmetic."
}

function Note($msg, $stack) {
  $hay = "$msg $stack".ToLower()
  foreach ($k in $known.Keys) {
    $ok = $true
    foreach ($p in ($k.ToLower() -split '\|')) { if ($hay -notlike "*$p*") { $ok = $false; break } }
    if ($ok) { return $known[$k] }
  }
  return $null
}

function Clean($line) {
  # strip ANSI colour codes and the repeated "[2KPlutonium r5334 > " console-prompt noise
  $l = $line -replace '\x1b\[[0-9;]*m',''
  $l = $l -replace '\[2K',''
  $l = $l -replace 'Plutonium r5334 > ?',''
  return $l.Trim()
}

# ── Persistent dedup state across collector restarts ──
$sigs = @{}   # signature -> ordered hashtable {msg, frame, stack, count, first, last, firstCtx, lastCtx}
if (Test-Path $stateF) {
  try {
    $raw = Get-Content $stateF -Raw | ConvertFrom-Json
    foreach ($p in $raw.PSObject.Properties) {
      $v = $p.Value
      $sigs[$p.Name] = @{ msg=$v.msg; frame=$v.frame; stack=$v.stack; count=[int]$v.count; first=$v.first; last=$v.last; firstCtx=$v.firstCtx; lastCtx=$v.lastCtx }
    }
  } catch {}
}

# ── Per-server tail state (2026-08-01) ──
# Everything below used to be a single scalar. With seven logs it MUST be per-server: an error
# block can span two polls, so parser state kept globally would splice one server's message onto
# another server's stack frames and invent signatures that never happened.
$st = @{}
foreach ($s in $servers) {
  $st[$s.Name] = @{
    pos    = 0
    map    = '(unknown)'
    gt     = '?'
    inErr  = $false
    msg    = ''
    frames = @()
    sawMsg = $false
    pend   = $null   # multi-line 0xC0000005 exception block
  }
}

# crash-log state
# (the 0xC0000005 accumulator now lives per-server as $st[<srv>].pend)
$wdPos = if (Test-Path $wdLog) { (Get-Item $wdLog).Length } else { 0 }   # start at end: only capture NEW restarts

function AppendCrash($type, $detail, $ctx) {
  if (-not (Test-Path $crashLog)) {
    [System.IO.File]::WriteAllText($crashLog, "# MW3 Crash & Fatal-Event Log`n_Chronological, append-only. Auto-collected: server crashes (0xC0000005), boot Com_ERROR/Sys_Error, and watchdog restarts._`n`n", (New-Object System.Text.UTF8Encoding($false)))
  }
  $suffix = if ($ctx -and $ctx -ne '(unknown)/?') { " _(map $ctx)_" } else { '' }
  $entry = "- **$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')**  ``[$type]``  $detail$suffix`n"
  [System.IO.File]::AppendAllText($crashLog, $entry, (New-Object System.Text.UTF8Encoding($false)))
}

function Finalize($srv) {
  $s = $st[$srv]
  if (-not $s.sawMsg -or $s.msg -eq '') { return }
  $topFrame = if ($s.frames.Count -gt 0) { $s.frames[0] } else { '(no frame)' }
  $sig = "$($s.msg) | $topFrame"
  $now = Get-Date -Format 'yyyy-MM-dd HH:mm'
  # Context now carries the SERVER as well as the map, so a survival-only fault is not read as
  # fleet-wide. Signatures still dedupe on (message + top frame) only - the same bug on two
  # servers is one signature, with the server list showing where it has been seen.
  $ctx = "$srv $($s.map)/$($s.gt)"
  if ($sigs.ContainsKey($sig)) {
    $sigs[$sig].count++
    $sigs[$sig].last = $now
    $sigs[$sig].lastCtx = $ctx
    if ($sigs[$sig].ContainsKey('srvs')) {
      if ($sigs[$sig].srvs -notcontains $srv) { $sigs[$sig].srvs += $srv }
    } else { $sigs[$sig].srvs = @($srv) }
  } else {
    $sigs[$sig] = @{ msg=$s.msg; frame=$topFrame; stack=($s.frames -join '  <-  '); count=1; first=$now; last=$now; firstCtx=$ctx; lastCtx=$ctx; srvs=@($srv) }
  }
}

function WriteDigest {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('# MW3 Script Error Digest - auto-collected')
  [void]$sb.AppendLine("_Updated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | sources: all $($servers.Count) server logs (main <MP-PORT>, survival <SURV-PORT-1>/<SURV-PORT-2>/<SURV-PORT-3>/<SURV-PORT-4>, main clones <MP-PORT-2>/<MP-PORT-3>)_")
  [void]$sb.AppendLine('')
  $newCount = ($sigs.Values | Where-Object { -not (Note $_.msg $_.stack) }).Count
  [void]$sb.AppendLine("**$($sigs.Count) unique error signatures | $newCount untriaged [NEW].** Sorted by frequency. [KNOWN] = previously diagnosed benign.")
  [void]$sb.AppendLine('')
  foreach ($e in ($sigs.GetEnumerator() | Sort-Object { $_.Value.count } -Descending | Select-Object -First 50)) {
    $v = $e.Value
    $note = Note $v.msg $v.stack
    $tag = if ($note) { '[KNOWN]' } else { '[NEW]' }
    [void]$sb.AppendLine("## $tag  x$($v.count)  $($v.msg)")
    [void]$sb.AppendLine("- frame: **$($v.frame)**")
    [void]$sb.AppendLine("- first: $($v.first) ($($v.firstCtx)) | last: $($v.last) ($($v.lastCtx))")
    if ($v.srvs) { [void]$sb.AppendLine("- seen on: $(($v.srvs) -join ', ')") }
    [void]$sb.AppendLine("- stack: $($v.stack)")
    if ($note) { [void]$sb.AppendLine("- note: $note") }
    [void]$sb.AppendLine('')
  }
  [System.IO.File]::WriteAllText($digest, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
  # persist dedup state
  ($sigs | ConvertTo-Json -Depth 5) | Set-Content $stateF
}

# initial digest so the file exists immediately
WriteDigest

for (;;) {
  try {
    $anyNew = $false
    foreach ($srvDef in $servers) {
      $srv     = $srvDef.Name
      $console = $srvDef.Path
      $s       = $st[$srv]

      if (-not (Test-Path $console)) { continue }
      $len = (Get-Item $console).Length
      if ($len -lt $s.pos) {
        # console.log is truncated on boot/Com_Restart. Reset the read position AND the parser,
        # otherwise a half-parsed block from the previous boot would splice onto the new log.
        $s.pos = 0; $s.inErr = $false; $s.msg = ''; $s.frames = @(); $s.sawMsg = $false; $s.pend = $null
      }
      if ($len -gt $s.pos) {
        $fs = [System.IO.File]::Open($console,'Open','Read','ReadWrite')
        [void]$fs.Seek($s.pos,'Begin')
        $sr = New-Object System.IO.StreamReader($fs)
        $chunk = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
        $s.pos = $len
        $anyNew = $true

        foreach ($raw in ($chunk -split "`n")) {
          $line = Clean $raw
          if ($line -eq '') { continue }

          # track map/gametype context (per server)
          $m = [regex]::Match($line, 'rotating to map "([^"]+)"'); if ($m.Success) { $s.map = $m.Groups[1].Value }
          $m = [regex]::Match($line, 'join our party with map (\S+) and gametype (\S+)'); if ($m.Success) { $s.map = $m.Groups[1].Value; $s.gt = $m.Groups[2].Value }

          # ── crash / fatal-event detection (chronological crash log) ──
          if ($line -match 'A critical exception occured') { $s.pend = @{ code=''; addr='' }; continue }
          if ($null -ne $s.pend) {
            $cm = [regex]::Match($line, 'Exception Code:\s*(\S+)');    if ($cm.Success) { $s.pend.code = $cm.Groups[1].Value; continue }
            $am = [regex]::Match($line, 'Exception Address:\s*(.+)$'); if ($am.Success) { $s.pend.addr = $am.Groups[1].Value.Trim(); continue }
            $dm = [regex]::Match($line, 'minidump:\s*(.+\.dmp)\s*$');  if ($dm.Success) { AppendCrash 'SERVER CRASH' "$($s.pend.code) at $($s.pend.addr)  |  dump: $($dm.Groups[1].Value.Trim())" "$srv $($s.map)/$($s.gt)"; $s.pend = $null; continue }
          }
          if ($line -match 'Com_ERROR:') { AppendCrash 'COM_ERROR (boot/link fatal)' (($line -replace '.*Com_ERROR:\s*','')) "$srv $($s.map)/$($s.gt)" }
          if ($line -match 'Sys_Error:')  { AppendCrash 'SYS_ERROR (fatal)' (($line -replace '.*Sys_Error:\s*','')) "$srv $($s.map)/$($s.gt)" }

          if ($line -match 'script runtime error') {
            if ($s.inErr) { Finalize $srv }   # back-to-back blocks
            $s.inErr = $true; $s.msg = ''; $s.frames = @(); $s.sawMsg = $false
            continue
          }
          if ($s.inErr) {
            if ($line -match '^\*{6,}') { Finalize $srv; $s.inErr = $false; continue }   # block terminator
            if ($line -match '^at (function|unknown)' -or $line -match '^\s*at ') {
              # frame line: "at function "X" in file "Y"" -> X@Y   /  "at unknown location (...)"
              $fm = [regex]::Match($line, 'at function "([^"]+)" in file "([^"]+)"')
              if ($fm.Success) {
                $file = ($fm.Groups[2].Value -split '/')[-1]
                $s.frames += "$($fm.Groups[1].Value)@$file"
              } else {
                $s.frames += ($line -replace '^\s*at\s*','')
              }
              continue
            }
            if (-not $s.sawMsg) { $s.msg = $line; $s.sawMsg = $true }   # first non-frame line = the error message
          }
        }
      }
    }
    # once per poll, not once per server - with seven logs the old placement rewrote the digest
    # (and re-serialised the whole state file) up to seven times a cycle for no benefit.
    if ($anyNew) { WriteDigest }
    # fold NEW watchdog restarts into the chronological crash log
    if (Test-Path $wdLog) {
      $wlen = (Get-Item $wdLog).Length
      if ($wlen -lt $wdPos) { $wdPos = 0 }
      if ($wlen -gt $wdPos) {
        $wfs = [System.IO.File]::Open($wdLog,'Open','Read','ReadWrite'); [void]$wfs.Seek($wdPos,'Begin')
        $wsr = New-Object System.IO.StreamReader($wfs); $wchunk = $wsr.ReadToEnd(); $wsr.Close(); $wfs.Close(); $wdPos = $wlen
        foreach ($wl in ($wchunk -split "`n")) { if ($wl -match 'RESTART:') { AppendCrash 'WATCHDOG RESTART' ($wl.Trim() -replace '^\S+ \S+\s+RESTART:\s*','') '' } }
      }
    }
  } catch {}
  Start-Sleep -Seconds $pollSec
}
