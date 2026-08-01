# restart-all.ps1 - restart every yourserver.gg game server, one at a time, to deploy staged changes.
#
# Order matters: the dedi runs as plutonium-bootstrapper-win32.exe under a cmd.exe supervisor.
# The supervisor must die FIRST, otherwise it relaunches the bootstrapper the moment we kill
# it and we end up fighting our own restart. Everything is killed by EXACT PID - never by
# name or command-line pattern, which has previously taken out live servers by accident.
#
# -Ports limits the run to specific servers, so a change that only affects one fleet does not
# cost the other one an outage (e.g. -Ports <SURV-PORT-1>,<SURV-PORT-2>,<SURV-PORT-3>,<SURV-PORT-4> for survival-only work).
param([int[]] $Ports)
$ErrorActionPreference = 'Continue'

$servers = @(
  @{ Name='Survival  (<SURV-PORT-1>)'; Port=<SURV-PORT-1>; Bat='C:\Survival\LAUNCH-SURVIVAL.bat';   Wd='C:\Survival'  },
  @{ Name='Survival2 (<SURV-PORT-2>)'; Port=<SURV-PORT-2>; Bat='C:\Survival2\LAUNCH-SURVIVAL2.bat'; Wd='C:\Survival2' },
  @{ Name='Survival3 (<SURV-PORT-3>)'; Port=<SURV-PORT-3>; Bat='C:\Survival3\LAUNCH-SURVIVAL3.bat'; Wd='C:\Survival3' },
  @{ Name='Survival4 (<SURV-PORT-4>)'; Port=<SURV-PORT-4>; Bat='C:\Survival4\LAUNCH-SURVIVAL4.bat'; Wd='C:\Survival4' },
  @{ Name='Main      (<MP-PORT>)'; Port=<MP-PORT>; Bat='C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Modern Warfare 3\!start_mp_server.bat'; Wd='C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Modern Warfare 3' },
  @{ Name='Main2     (<MP-PORT-2>)'; Port=<MP-PORT-2>; Bat='C:\Main2\LAUNCH-MAIN2.bat';         Wd='C:\Main2'     },
  @{ Name='Main3     (<MP-PORT-3>)'; Port=<MP-PORT-3>; Bat='C:\Main3\LAUNCH-MAIN3.bat';         Wd='C:\Main3'     }
)

function PortPid($port) {
  (Get-NetUDPEndpoint -LocalPort $port -EA SilentlyContinue | Select-Object -First 1).OwningProcess
}

if ($Ports) {
  $servers = $servers | Where-Object { $Ports -contains $_.Port }
  if (-not $servers) { Write-Host "no server matches -Ports; nothing to do"; exit 1 }
}
Write-Host ("restarting: " + (($servers | ForEach-Object { $_.Name }) -join ' | '))
Write-Host ""

foreach ($s in $servers) {
  Write-Host ("=== " + $s.Name + " ===")

  # never restart a server with real people on it
  $n = -1
  try { $n = & 'C:\Survival\tools\count-players.ps1' -Port $s.Port 2>$null } catch {}
  if ($n -gt 0) { Write-Host ("  SKIP - " + $n + " real player(s) connected"); continue }

  # -1 means UNKNOWN, not empty. 2026-07-30: count-players had the wrong rcon password, so it
  # answered 0 for every server and this guard waved through servers with people on them. It
  # now returns -1 on any reply it cannot trust, and unknown must NEVER be read as safe.
  # A genuinely DOWN server also reports -1, and that one we DO want to restart - so tell the
  # two apart by whether anything still holds the port, rather than by the headcount alone.
  if ($n -lt 0) {
    if (PortPid $s.Port) {
      Write-Host "  SKIP - server is UP but headcount is unknown (rcon unreachable/rejected); refusing to risk live players"
      continue
    }
    Write-Host "  headcount unknown, but nothing holds the port - treating as down and recovering"
  } else {
    Write-Host ("  players: " + $n)
  }

  $bootPid = PortPid $s.Port
  if ($bootPid) {
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$bootPid" -EA SilentlyContinue
    $parentPid = if ($proc) { $proc.ParentProcessId } else { $null }
    if ($parentPid) {
      $par = Get-CimInstance Win32_Process -Filter "ProcessId=$parentPid" -EA SilentlyContinue
      if ($par -and $par.Name -eq 'cmd.exe') {
        Write-Host ("  killing supervisor cmd pid " + $parentPid)
        Stop-Process -Id $parentPid -Force -EA SilentlyContinue
        Start-Sleep -Seconds 1
      }
    }
    Write-Host ("  killing bootstrapper pid " + $bootPid)
    Stop-Process -Id $bootPid -Force -EA SilentlyContinue
  } else {
    Write-Host "  already down"
  }

  # wait for the port to actually free up
  $deadline = (Get-Date).AddSeconds(30)
  while ((Get-Date) -lt $deadline -and (PortPid $s.Port)) { Start-Sleep -Seconds 2 }
  Write-Host ("  port free: " + (-not (PortPid $s.Port)))
  Start-Sleep -Seconds 3

  if (-not (Test-Path $s.Bat)) { Write-Host ("  ABORT - launcher missing: " + $s.Bat); continue }
  Write-Host ("  launching " + $s.Bat)
  Start-Process -FilePath $s.Bat -WorkingDirectory $s.Wd -WindowStyle Hidden

  # wait for it to claim the port again
  $deadline = (Get-Date).AddSeconds(180)
  $up = $false
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    if (PortPid $s.Port) { $up = $true; break }
  }
  if ($up) {
    $np = PortPid $s.Port
    $pr = Get-Process -Id $np -EA SilentlyContinue
    Write-Host ("  UP  pid " + $np + "  responding=" + $(if($pr){$pr.Responding}else{'?'}))
  } else {
    Write-Host "  *** DID NOT COME BACK within 180s ***"
  }
  Write-Host ""
  Start-Sleep -Seconds 4
}

Write-Host "===== FINAL STATE ====="
foreach ($s in $servers) {
  $p = PortPid $s.Port
  Write-Host ("  " + $s.Name + "  " + $(if ($p) { "UP   pid $p" } else { "DOWN" }))
}
