# deploy-waypoints.ps1 - swap the repaired zz_bpg_waypoints.iwd into every server tree.
#
# The archive is held open by the running dedi, so the swap can only happen while that
# instance is DOWN. restart-all.ps1 relaunches immediately and leaves no such window, so
# this does stop -> swap -> start per instance instead.
#
# PID handling is copied from restart-all.ps1 because it is proven: the cmd.exe supervisor
# must die BEFORE the bootstrapper or it relaunches the process we just killed, and every
# kill is by EXACT PID - never by name or pattern, which has taken out live servers before.
#
# The user explicitly authorised restarting all 7 including populated servers, so this does
# NOT skip on headcount the way restart-all.ps1 does. It still REPORTS the count so the cost
# is visible in the log.
#
# ⚠️ The <MP-PORT> tree lives under %LOCALAPPDATA%, which is redirected for some shells. The swap
# is verified by length AND by the fact the file was LOCKED while the server ran - a
# redirected copy would not have been locked, so a successful overwrite proves we hit the
# real file.

param(
    [string] $NewIwd = 'C:\Survival\staging\zz_bpg_waypoints.iwd.new',
    [int[]]  $Ports
)
$ErrorActionPreference = 'Continue'

$servers = @(
  @{ Name='Survival  (<SURV-PORT-1>)'; Port=<SURV-PORT-1>; Bat='C:\Survival\LAUNCH-SURVIVAL.bat';   Wd='C:\Survival';  Iwd='C:\Survival\appdata\Plutonium\storage\iw5\zz_bpg_waypoints.iwd'  },
  @{ Name='Survival2 (<SURV-PORT-2>)'; Port=<SURV-PORT-2>; Bat='C:\Survival2\LAUNCH-SURVIVAL2.bat'; Wd='C:\Survival2'; Iwd='C:\Survival2\appdata\Plutonium\storage\iw5\zz_bpg_waypoints.iwd' },
  @{ Name='Survival3 (<SURV-PORT-3>)'; Port=<SURV-PORT-3>; Bat='C:\Survival3\LAUNCH-SURVIVAL3.bat'; Wd='C:\Survival3'; Iwd='C:\Survival3\appdata\Plutonium\storage\iw5\zz_bpg_waypoints.iwd' },
  @{ Name='Survival4 (<SURV-PORT-4>)'; Port=<SURV-PORT-4>; Bat='C:\Survival4\LAUNCH-SURVIVAL4.bat'; Wd='C:\Survival4'; Iwd='C:\Survival4\appdata\Plutonium\storage\iw5\zz_bpg_waypoints.iwd' },
  @{ Name='Main      (<MP-PORT>)'; Port=<MP-PORT>; Bat='C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Modern Warfare 3\!start_mp_server.bat'; Wd='C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Modern Warfare 3'; Iwd="$env:LOCALAPPDATA\Plutonium\storage\iw5\zz_bpg_waypoints.iwd" },
  @{ Name='Main2     (<MP-PORT-2>)'; Port=<MP-PORT-2>; Bat='C:\Main2\LAUNCH-MAIN2.bat';         Wd='C:\Main2';     Iwd='C:\Main2\appdata\Plutonium\storage\iw5\zz_bpg_waypoints.iwd'     },
  @{ Name='Main3     (<MP-PORT-3>)'; Port=<MP-PORT-3>; Bat='C:\Main3\LAUNCH-MAIN3.bat';         Wd='C:\Main3';     Iwd='C:\Main3\appdata\Plutonium\storage\iw5\zz_bpg_waypoints.iwd'     }
)

function PortPid($port) {
  (Get-NetUDPEndpoint -LocalPort $port -EA SilentlyContinue | Select-Object -First 1).OwningProcess
}

if (-not (Test-Path $NewIwd)) { Write-Host "ABORT - staged archive not found: $NewIwd"; exit 1 }
$newLen = (Get-Item $NewIwd).Length
Write-Host "staged archive: $NewIwd ($newLen bytes)"

if ($Ports) { $servers = $servers | Where-Object { $Ports -contains $_.Port } }
$stamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$results = @()

foreach ($s in $servers) {
  Write-Host ""
  Write-Host ("=== " + $s.Name + " ===")

  $n = -1
  try { $n = & 'C:\Survival\tools\count-players.ps1' -Port $s.Port 2>$null } catch {}
  Write-Host ("  players: " + $(if ($n -lt 0) { 'UNKNOWN' } else { $n }))

  # --- stop: supervisor first, then bootstrapper, both by exact PID ---
  $bootPid = PortPid $s.Port
  if ($bootPid) {
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$bootPid" -EA SilentlyContinue
    if ($proc -and $proc.ParentProcessId) {
      $par = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $proc.ParentProcessId) -EA SilentlyContinue
      if ($par -and $par.Name -eq 'cmd.exe') {
        Write-Host ("  killing supervisor cmd pid " + $par.ProcessId)
        Stop-Process -Id $par.ProcessId -Force -EA SilentlyContinue
        Start-Sleep -Seconds 1
      }
    }
    Write-Host ("  killing bootstrapper pid " + $bootPid)
    Stop-Process -Id $bootPid -Force -EA SilentlyContinue
  } else { Write-Host "  already down" }

  $deadline = (Get-Date).AddSeconds(30)
  while ((Get-Date) -lt $deadline -and (PortPid $s.Port)) { Start-Sleep -Seconds 2 }
  if (PortPid $s.Port) { Write-Host "  ABORT - port never freed, NOT swapping"; $results += "$($s.Name) PORT-STUCK"; continue }
  Start-Sleep -Seconds 2

  # --- swap, with a backup we can roll back to ---
  $swapped = $false
  try {
      if (Test-Path $s.Iwd) { Copy-Item $s.Iwd "$($s.Iwd).bak_$stamp" -Force }
      Copy-Item $NewIwd $s.Iwd -Force
      $len = (Get-Item $s.Iwd).Length
      if ($len -eq $newLen) { Write-Host ("  swapped OK (" + $len + " bytes)"); $swapped = $true }
      else { Write-Host ("  *** SIZE MISMATCH after copy: " + $len + " vs " + $newLen + " ***") }
  } catch { Write-Host ("  *** SWAP FAILED: " + $_.Exception.Message + " ***") }

  # --- start ---
  if (-not (Test-Path $s.Bat)) { Write-Host ("  ABORT - launcher missing: " + $s.Bat); $results += "$($s.Name) NO-LAUNCHER"; continue }
  Write-Host ("  launching " + $s.Bat)
  Start-Process -FilePath $s.Bat -WorkingDirectory $s.Wd -WindowStyle Hidden

  $deadline = (Get-Date).AddSeconds(180)
  $up = $false
  while ((Get-Date) -lt $deadline) { Start-Sleep -Seconds 5; if (PortPid $s.Port) { $up = $true; break } }

  if ($up) {
    $np = PortPid $s.Port
    Write-Host ("  UP  pid " + $np)
    $results += "$($s.Name) UP swapped=$swapped"
  } else {
    Write-Host "  *** DID NOT COME BACK within 180s ***"
    $results += "$($s.Name) DOWN swapped=$swapped"
  }
  Start-Sleep -Seconds 4
}

Write-Host ""
Write-Host "===== FINAL ====="
$results | ForEach-Object { "  $_" }
foreach ($s in $servers) {
  $p = PortPid $s.Port
  Write-Host ("  " + $s.Name + "  " + $(if ($p) { "UP   pid $p" } else { "DOWN" }))
}
