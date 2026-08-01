# mw3-watchdog.ps1 - failsafe for the Your Server MW3 server.
# Polls the server via the IW "getinfo" UDP query and detects the map-rotate /
# restart LOOP failure mode. On detection it writes the last stable (played) map to
# lastmap.txt and kills the server; LAUNCH.bat's restart loop then relaunches it on
# that map (lastmap.txt is a one-shot LAUNCH consumes & deletes).
# Runs continuously; started by the "MW3 Watchdog" scheduled task at logon.
#
# Detection (any of, all conservative to avoid false restarts):
#   * rapid map cycling   : >= 4 map changes within 60s
#   * restart flapping    : >= 3 unreachable->reachable transitions within 90s
#   * hung / unresponsive : no getinfo reply for >= 90s straight
#   * OS-level hang       : Get-Process .Responding = $false for >= 40s straight
# A 120s cooldown follows every restart so a normal reboot can't be mistaken for a loop.
#
# 2026-07-07 addition: getinfo alone MISSED two real hangs the same night (a single
# stray successful UDP reply amid an otherwise-stuck process resets the 90s timer to
# zero, so a hang that lets through ~1 reply per 90s window never trips it). Verified
# live that night: Get-Process's own .Responding flag (the same "(Not Responding)"
# Task Manager uses) read $false accurately both times, independent of getinfo/network
# noise. Added as a second, independent check -- purely additive, does not touch or
# weaken the existing getinfo-based paths above.

$ErrorActionPreference = 'SilentlyContinue'

# Single-instance guard: the "MW3 Watchdog" task fires every minute to keep this
# alive; if an instance is already running, new ones exit immediately.
$mtx = New-Object System.Threading.Mutex($false,'Global\YourServerMW3Watchdog')
try { $acquired = $mtx.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }
if(-not $acquired){ exit 0 }

$ip='127.0.0.1'; $port=<MP-PORT>; $interval=12
$server='C:\Ops'; $log="$server\watchdog.log"; $lastmapF="$server\lastmap.txt"

function Log($m){ "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Add-Content -LiteralPath $log }

function Get-Map {
    $c=$null
    try {
        $c=New-Object System.Net.Sockets.UdpClient; $c.Client.ReceiveTimeout=3000
        $pkt=[byte[]](0xFF,0xFF,0xFF,0xFF)+[Text.Encoding]::ASCII.GetBytes("getinfo`n")
        [void]$c.Send($pkt,$pkt.Length,$ip,$port)
        $ep=New-Object Net.IPEndPoint([Net.IPAddress]::Any,0)
        $resp=[Text.Encoding]::ASCII.GetString($c.Receive([ref]$ep)); $c.Close()
        $m=[regex]::Match($resp,'mapname\\([^\\]+)')
        if($m.Success){ return $m.Groups[1].Value } else { return '__noparse__' }
    } catch { if($c){try{$c.Close()}catch{}}; return $null }
}

function Launch-Running {
    # 2026-07-15: live launcher is now the game-dir !start_mp_server.bat (the old
    # C:\Ops\LAUNCH.bat match left the watchdog DORMANT after the switch).
    # Deliberately does NOT match LAUNCH-SURVIVAL.bat (the <SURV-PORT-1> survival instance
    # has its own restart loop and is not this watchdog's job).
    [bool](Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" -EA SilentlyContinue |
           Where-Object { $_.CommandLine -like '*LAUNCH.bat*' -or $_.CommandLine -like '*start_mp_server*' })
}

# Returns $true / $false / $null (pid not found -> skip this cycle, don't count as hung)
function Test-NotResponding {
    $ep = Get-NetUDPEndpoint -LocalPort $port -EA SilentlyContinue | Select-Object -First 1
    if (-not $ep) { return $null }
    try {
        $p = Get-Process -Id $ep.OwningProcess -EA Stop
        return (-not $p.Responding)
    } catch { return $null }
}

function Restart-Server($mapToLoad,$reason){
    Log "RESTART: $reason | restoring map: $(if($mapToLoad){$mapToLoad}else{'(random - none stable yet)'})"
    if($mapToLoad -and $mapToLoad -ne '__noparse__'){
        [System.IO.File]::WriteAllText($lastmapF,$mapToLoad,(New-Object System.Text.ASCIIEncoding))
    }
    # 2026-07-15: kill ONLY the <MP-PORT> instance. A second Plutonium server (survival,
    # port <SURV-PORT-1>) runs on this box; the old name-based Get-Process kill took out every
    # bootstrapper as collateral. Endpoint owner first (works even when the process is
    # too wedged for CIM), then command-line match (works when the socket is gone but
    # the process is alive). If neither finds it, the process is already dead - nothing
    # to kill, fall through to the relaunch check.
    $killed = $false
    $epKill = Get-NetUDPEndpoint -LocalPort $port -EA SilentlyContinue | Select-Object -First 1
    if($epKill){
        Stop-Process -Id $epKill.OwningProcess -Force -EA SilentlyContinue
        $killed = $true
    }
    if(-not $killed){
        Get-CimInstance Win32_Process -Filter "Name='plutonium-bootstrapper-win32.exe'" -EA SilentlyContinue |
            Where-Object { $_.CommandLine -like "*net_port $port*" } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue; $killed = $true }
    }
    if(-not $killed){ Log "  no port-$port process found (already dead) -> relaunch only" }
    Start-Sleep -Seconds 3
    if(-not (Launch-Running)){
        Log "  launcher loop absent -> starting !start_mp_server.bat"
        $gamedir = 'C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Modern Warfare 3'
        Start-Process -FilePath 'cmd.exe' -ArgumentList '/c',"`"$gamedir\!start_mp_server.bat`"" -WorkingDirectory $gamedir
    }
}

Log "===== watchdog started (poll ${interval}s) ====="
$mapChanges=@(); $recoveries=@()
$curMap=$null; $curMapSince=Get-Date; $stableMap=$null
$failStart=$null; $wasDown=$false; $cooldownUntil=(Get-Date).AddSeconds(-1)
$notRespondingSince=$null

while($true){
    Start-Sleep -Seconds $interval
    $now=Get-Date
    if(-not (Launch-Running)){ $failStart=$null; $wasDown=$false; $notRespondingSince=$null; continue }
    if($now -lt $cooldownUntil){ continue }

    # OS-level hang check -- independent of getinfo, can't be reset by a stray UDP reply
    $notResp = Test-NotResponding
    if($notResp -eq $true){
        if($null -eq $notRespondingSince){ $notRespondingSince=$now }
        $notRespSec=[math]::Round(($now-$notRespondingSince).TotalSeconds,0)
        if($notRespSec -ge 40){
            Restart-Server $stableMap "OS-level not-responding ${notRespSec}s"
            $cooldownUntil=$now.AddSeconds(120); $failStart=$null; $wasDown=$false; $mapChanges=@(); $recoveries=@(); $notRespondingSince=$null
            continue
        }
    } elseif($notResp -eq $false){
        $notRespondingSince=$null
    }
    # $notResp -eq $null (pid not found this instant) leaves the counter untouched

    $map=Get-Map

    if($null -eq $map){
        if($null -eq $failStart){ $failStart=$now }
        $wasDown=$true
        $downSec=[math]::Round(($now-$failStart).TotalSeconds,0)
        if($downSec -ge 90){
            Restart-Server $stableMap "unresponsive ${downSec}s"
            $cooldownUntil=$now.AddSeconds(120); $failStart=$null; $wasDown=$false; $mapChanges=@(); $recoveries=@()
        }
        continue
    }

    $failStart=$null
    if($wasDown){ $recoveries+=$now; $wasDown=$false }
    $recoveries=@($recoveries | Where-Object { ($now-$_).TotalSeconds -le 90 })
    if($recoveries.Count -ge 3){
        Restart-Server $stableMap "restart flapping ($($recoveries.Count)/90s)"
        $cooldownUntil=$now.AddSeconds(120); $mapChanges=@(); $recoveries=@(); continue
    }

    if($map -eq '__noparse__'){ continue }

    if($map -ne $curMap){
        if($null -ne $curMap){ $mapChanges+=$now }
        $curMap=$map; $curMapSince=$now
    } elseif(($now-$curMapSince).TotalSeconds -ge 30){
        $stableMap=$map
    }
    $mapChanges=@($mapChanges | Where-Object { ($now-$_).TotalSeconds -le 60 })
    if($mapChanges.Count -ge 4){
        Restart-Server $stableMap "rapid map cycling ($($mapChanges.Count)/60s)"
        $cooldownUntil=$now.AddSeconds(120); $mapChanges=@(); $recoveries=@()
    }
}
