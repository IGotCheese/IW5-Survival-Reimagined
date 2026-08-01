<#
    MW3 Server Panel — local HTTP backend (no external dependencies)
    ----------------------------------------------------------------
    Serves a web UI on http://127.0.0.1:<port> to manage the Plutonium IW5
    servers (start / stop / restart / RCON / logs).

    - Listens on 127.0.0.1 ONLY (loopback). Not reachable from the network.
    - Uses a raw TcpListener: no admin rights and no URL reservations (urlacl).
    - Every /api/* call requires the X-Panel-Token header (CSRF protection).
    - Child processes are launched with a HIDDEN window and outlive the panel.

    Usage:  pwsh -NoProfile -File C:\Panel\panel.ps1 [-Port 8787]
    Normally started through START-PANEL.vbs (no window at all).
#>
param(
    [int]$Port = 8787
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Off

# Last time rcon 'status' was polled per server port. See the throttle in the status sweep -
# every 'status' makes the GAME SERVER echo its whole player table into its own console.log.
$script:PollClock = @{}

$Root       = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $Root 'servers.json'
$UiPath     = Join-Path $Root 'web\ui.html'
$LogPath    = Join-Path $Root 'panel.log'
$TokenPath  = Join-Path $Root 'token.txt'
$PidPath    = Join-Path $Root 'panel.pid'

# The panel may be started from shells where LOCALAPPDATA is redirected (MSIX
# containers do this). The server .bat files depend on that variable, so pin it to
# the machine's real value before launching anything.
#
# Uncomment and set this to YOUR real LocalAppData path if you launch the panel from
# such a shell. Left commented out because the correct value is machine-specific.
# $env:LOCALAPPDATA = 'C:\Users\<you>\AppData\Local'

# Processes the panel is allowed to terminate. Any PID whose name is not listed
# here is ignored, no matter how well it matches the lookup.
$KillAllowList = @(
    'cmd', 'conhost', 'plutonium-bootstrapper-win32', 'dotnet', 'caddy'
)

# --------------------------------------------------------------- helpers

function Write-PanelLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -LiteralPath $LogPath -Value $line -Encoding utf8 } catch { }
}

function Get-PanelToken {
    if (Test-Path -LiteralPath $TokenPath) {
        $t = (Get-Content -LiteralPath $TokenPath -Raw).Trim()
        if ($t) { return $t }
    }
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $t = ([System.BitConverter]::ToString($bytes) -replace '-', '').ToLower()
    Set-Content -LiteralPath $TokenPath -Value $t -Encoding ascii -NoNewline
    return $t
}

function Get-Servers {
    Get-Content -LiteralPath $ConfigPath -Raw -Encoding utf8 | ConvertFrom-Json
}

function Get-ServerById {
    param([string]$Id)
    (Get-Servers) | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}

# ------------------------------------------------------------------ RCON

function Invoke-Rcon {
    <#  Quake3 protocol: 4 x 0xFF bytes + "rcon <pass> <cmd>".
        The reply may be split across several datagrams.  #>
    param(
        [int]$RconPort,
        [string]$Password,
        [string]$Command,
        [int]$TimeoutMs = 900
    )
    $udp = New-Object System.Net.Sockets.UdpClient
    try {
        $udp.Client.ReceiveTimeout = $TimeoutMs
        $udp.Connect('127.0.0.1', $RconPort)
        $head    = [byte[]](0xff, 0xff, 0xff, 0xff)
        $payload = $head + [System.Text.Encoding]::UTF8.GetBytes("rcon $Password $Command")
        [void]$udp.Send($payload, $payload.Length)

        $sb = New-Object System.Text.StringBuilder
        $ep = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any), 0
        $first = $true
        while ($true) {
            try { $data = $udp.Receive([ref]$ep) } catch { break }
            if ($data.Length -gt 4) {
                $body = [System.Text.Encoding]::UTF8.GetString($data, 4, $data.Length - 4)
                # The first packet arrives prefixed with "print\n"
                $body = $body -replace '^print\r?\n?', ''
                [void]$sb.Append($body)
            }
            # Drain tail. This timeout is ALWAYS paid in full after the last packet, so it is a
            # flat per-server cost on every refresh - profiled 2026-07-30 at 446 ms for a whole
            # rcon call, of which ~400 ms was this wait. These are loopback round-trips (a full
            # 1231-byte status replies in ~130 ms), so 120 ms is still ~6x headroom for a split
            # reply while cutting ~280 ms per server off every sweep.
            if ($first) { $udp.Client.ReceiveTimeout = 120; $first = $false }
        }
        return $sb.ToString()
    }
    catch {
        return "[panel] rcon error: $($_.Exception.Message)"
    }
    finally {
        try { $udp.Close() } catch { }
    }
}

function Invoke-GetInfo {
    <#  "getinfo" needs no password and returns the server infostring.
        (Plutonium IW5 does NOT answer "getstatus" — verified 2026-07-25.)  #>
    param([int]$QueryPort, [int]$TimeoutMs = 600)
    $udp = New-Object System.Net.Sockets.UdpClient
    try {
        $udp.Client.ReceiveTimeout = $TimeoutMs
        $udp.Connect('127.0.0.1', $QueryPort)
        $payload = [byte[]](0xff, 0xff, 0xff, 0xff) + [System.Text.Encoding]::ASCII.GetBytes('getinfo')
        [void]$udp.Send($payload, $payload.Length)
        $ep = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any), 0
        $data = $udp.Receive([ref]$ep)
        if ($data.Length -le 4) { return $null }
        return [System.Text.Encoding]::UTF8.GetString($data, 4, $data.Length - 4)
    }
    catch { return $null }
    finally { try { $udp.Close() } catch { } }
}

function ConvertFrom-InfoString {
    <#  Quake3 infostring: \key\value\key\value... on a single line. #>
    param([string]$Text)
    $info = @{}
    if (-not $Text) { return $info }
    foreach ($line in ($Text -split "\r?\n")) {
        $line = $line.Trim()
        if (-not $line.StartsWith('\')) { continue }
        $parts = $line.TrimStart('\') -split '\\'
        for ($i = 0; $i + 1 -lt $parts.Count; $i += 2) {
            $info[$parts[$i]] = $parts[$i + 1]
        }
    }
    return $info
}

function ConvertFrom-RconStatus {
    <#  "status" table: num score bot ping guid name address qport.
        Used to tell humans from bots (bot column = 0/1).  #>
    param([string]$Text)
    $players = @()
    if (-not $Text) { return $players }
    foreach ($line in ($Text -split "\r?\n")) {
        if ($line -match '^\s*(\d+)\s+(-?\d+)\s+([01])\s+(\d+)\s+(\S+)\s+(.*?)\s{2,}(\S+)\s+(\d+)\s*$') {
            $players += @{
                num   = [int]$matches[1]
                score = [int]$matches[2]
                bot   = ($matches[3] -eq '1')
                ping  = [int]$matches[4]
                guid  = $matches[5]
                name  = $matches[6].Trim()
                addr  = $matches[7]
            }
        }
    }
    return $players
}

# ------------------------------------------------------------- processes

# ── PORT->PID CACHE (2026-07-30) ─────────────────────────────────────────────────────────────
# /api/status used to take 7-11 SECONDS against a 5 s browser refresh, so refreshes permanently
# overlapped. Measured cause was NOT rcon, timeouts or the network - a single
# `Get-NetUDPEndpoint -LocalPort <p>` costs ~2000 ms on this box, and it ran once per server:
#     Get-NetUDPEndpoint -LocalPort  : 2003 ms  (x9 servers)
#     Get-CimInstance Win32_Process  :  191 ms
#     getinfo round-trip (server up) :   49 ms
# `netstat -ano` returns the whole table in ~78 ms - 20x faster than ONE filtered cmdlet call -
# and its PIDs were verified identical to Get-NetUDPEndpoint for all 7 game ports.
# Built once per /api/status sweep and reused by every server, so the cost is paid once, not 9x.
$script:PortPidCache     = $null
$script:PortPidCacheTime = [datetime]::MinValue

function Update-PortPidCache {
    param([int]$MaxAgeMs = 1000)
    if ($script:PortPidCache -and ((Get-Date) - $script:PortPidCacheTime).TotalMilliseconds -lt $MaxAgeMs) { return }
    $udp = @{}; $tcp = @{}
    try {
        foreach ($l in (netstat -ano -p UDP)) {
            if ($l -match '^\s*UDP\s+\S+:(\d+)\s+\S+\s+(\d+)\s*$') { $udp[[int]$matches[1]] = [int]$matches[2] }
        }
        foreach ($l in (netstat -ano -p TCP)) {
            if ($l -match '^\s*TCP\s+\S+:(\d+)\s+\S+\s+LISTENING\s+(\d+)\s*$') { $tcp[[int]$matches[1]] = [int]$matches[2] }
        }
    } catch { }
    $script:PortPidCache     = @{ udp = $udp; tcp = $tcp }
    $script:PortPidCacheTime = Get-Date
}

function Get-PortOwnerPid {
    param($Server)
    try {
        Update-PortPidCache
        if ($script:PortPidCache) {
            $tbl = if ($Server.kind -eq 'pluto') { $script:PortPidCache.udp } else { $script:PortPidCache.tcp }
            if ($tbl.ContainsKey([int]$Server.port)) { return $tbl[[int]$Server.port] }
            return $null
        }
        # fallback: original cmdlets, only if netstat parsing produced nothing at all
        if ($Server.kind -eq 'pluto') {
            $o = Get-NetUDPEndpoint -LocalPort $Server.port -ErrorAction SilentlyContinue
        }
        else {
            $o = Get-NetTCPConnection -LocalPort $Server.port -State Listen -ErrorAction SilentlyContinue
        }
        if ($o) { return ($o | Select-Object -First 1).OwningProcess }
    }
    catch { }
    return $null
}

function Get-SupervisorPids {
    <#  The .bat files run a "start /wait" loop: killing only the server makes
        the parent cmd relaunch it. It has to be closed first.
        Matching is a LITERAL SUBSTRING of the .bat path — never a broad regex
        over command lines (that already caused a full outage back in July).  #>
    param($Server)
    if (-not $Server.supervisorMatch) { return @() }
    $needle = [string]$Server.supervisorMatch
    $found = @()
    try {
        # Cached per sweep (2026-07-30): this CIM query costs ~191 ms and ran once PER SERVER,
        # i.e. ~1.7 s of the old 7 s refresh. The cmd.exe list cannot meaningfully change inside
        # a single /api/status pass, so one snapshot serves all of them.
        $procs = Get-CmdProcSnapshot
        foreach ($p in $procs) {
            if ($p.CommandLine -and $p.CommandLine.Contains($needle)) { $found += [int]$p.ProcessId }
        }
    }
    catch { }
    return $found
}

$script:CmdProcCache     = $null
$script:CmdProcCacheTime = [datetime]::MinValue

function Get-CmdProcSnapshot {
    param([int]$MaxAgeMs = 1000)
    if ($script:CmdProcCache -and ((Get-Date) - $script:CmdProcCacheTime).TotalMilliseconds -lt $MaxAgeMs) {
        return $script:CmdProcCache
    }
    $script:CmdProcCache     = @(Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" -ErrorAction SilentlyContinue)
    $script:CmdProcCacheTime = Get-Date
    return $script:CmdProcCache
}

function Stop-PidSafely {
    param([int]$ProcessId, [string]$Reason)
    try {
        $p = Get-Process -Id $ProcessId -ErrorAction Stop
    }
    catch {
        return "PID $ProcessId no longer exists"
    }
    if ($KillAllowList -notcontains $p.ProcessName) {
        Write-PanelLog "REFUSED kill PID $ProcessId ($($p.ProcessName)) - not on the allow-list" 'WARN'
        return "BLOCKED: PID $ProcessId is '$($p.ProcessName)', not on the allow-list"
    }
    Write-PanelLog "kill PID $ProcessId ($($p.ProcessName)) - $Reason"
    try {
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        return "PID $ProcessId ($($p.ProcessName)) terminated"
    }
    catch {
        return "failed to terminate PID $ProcessId : $($_.Exception.Message)"
    }
}

function Get-ServerState {
    param($Server)

    $state = [ordered]@{
        id       = $Server.id
        name     = $Server.name
        kind     = $Server.kind
        port     = $Server.port
        note     = $Server.note
        url      = $Server.url
        hasLog   = [bool]$Server.log
        hasRcon  = [bool]$Server.rcon
        running  = $false
        pid      = $null
        supervisors = @()
        uptime   = $null
        memMB    = $null
        hostname = $null
        map      = $null
        gametype = $null
        mod      = $null
        players  = 0
        humans   = 0
        bots     = 0
        maxPlayers = $null
        playerList = @()
        rconOk   = $false
    }

    $procId = Get-PortOwnerPid -Server $Server
    $state.supervisors = @(Get-SupervisorPids -Server $Server)

    if ($procId) {
        try {
            $p = Get-Process -Id $procId -ErrorAction Stop
            $state.running = $true
            $state.pid     = [int]$procId
            $state.memMB   = [math]::Round($p.WorkingSet64 / 1MB, 0)
            try {
                $state.uptime = [int]((Get-Date) - $p.StartTime).TotalSeconds
            } catch { }
        }
        catch { }
    }

    if ($state.running -and $Server.kind -eq 'pluto') {
        $raw = Invoke-GetInfo -QueryPort $Server.port
        if ($raw) {
            $info = ConvertFrom-InfoString -Text $raw
            $state.hostname   = $info['hostname']
            $state.map        = $info['mapname']
            $state.gametype   = $info['gametype']
            $state.maxPlayers = $info['sv_maxclients']
            $state.mod        = $info['game']
            if ($info['clients']) { $state.players = [int]$info['clients'] }
        }
        # 2026-08-01: rcon 'status' is expensive in a way that is invisible from here - the GAME
        # SERVER echoes the whole table into its own console.log every time we ask. Measured on
        # <SURV-PORT-2>: 91% of a 32,000-line console.log was this poll (24,778 player-list rows + 4,389
        # headers), versus 76 lines from every bpg_* diagnostic combined. It churned the log fast
        # enough that history was lost on rotation - why FEEDBACK.md captured nothing and error
        # history kept vanishing on restart.
        #
        # getinfo above already supplies hostname/map/gametype/maxclients and a client COUNT, and
        # does NOT echo to the console. rcon 'status' is only needed for the player LIST, so:
        #   * skip entirely when nobody is on   - there is no list to fetch
        #   * otherwise throttle to 30s          - a player list does not change every 5s
        $needList = ([int]$state.players -gt 0)
        $pollKey  = "statusPoll_$($Server.port)"
        $pollDue  = (-not $script:PollClock.ContainsKey($pollKey)) -or
                    (((Get-Date) - $script:PollClock[$pollKey]).TotalSeconds -ge 30)

        if ($Server.rcon -and $needList -and $pollDue) {
            $script:PollClock[$pollKey] = Get-Date
            $st = Invoke-Rcon -RconPort $Server.port -Password $Server.rcon -Command 'status' -TimeoutMs 900
            if ($st -and $st -notlike '*Invalid password*' -and $st -notlike '*[panel] rcon error*') {
                $state.rconOk = $true
                $list = ConvertFrom-RconStatus -Text $st
                if ($list.Count -gt 0) {
                    $state.players    = $list.Count
                    $state.bots       = @($list | Where-Object { $_.bot }).Count
                    $state.humans     = $state.players - $state.bots
                    $state.playerList = @($list | ForEach-Object {
                        [ordered]@{ name = $_.name; score = $_.score; ping = $_.ping; bot = $_.bot; num = $_.num }
                    })
                }
                else {
                    $state.players = 0; $state.bots = 0; $state.humans = 0
                }
            }
        }
    }

    return $state
}

# ------------------------------------------------------ start/stop actions

function Start-ManagedServer {
    param($Server)

    $existing = Get-PortOwnerPid -Server $Server
    if ($existing) {
        return @{ ok = $false; message = "Already running (PID $existing) on port $($Server.port)." }
    }

    # Explicit environment variables for the child process.
    $saved = @{}
    if ($Server.env) {
        foreach ($k in $Server.env.PSObject.Properties.Name) {
            $saved[$k] = [Environment]::GetEnvironmentVariable($k)
            [Environment]::SetEnvironmentVariable($k, $Server.env.$k)
        }
    }

    try {
        # launchFile is the .bat/.cmd/.exe itself — we deliberately do NOT wrap it in
        # "cmd.exe /c <path>". cmd strips the quotes around a single quoted argument, so
        # "C:\Program Files (x86)\...\!start_mp_server.bat" became "C:\Program", cmd exited
        # instantly, and the hidden window swallowed the error. Adding one layer of quotes
        # does not help: that IS the form cmd unwraps. Launching the script directly lets
        # Windows build the correct "cmd /c ""<path>" "" command line itself — the very
        # form the original hand-started supervisors use.
        $startParams = @{
            FilePath         = $Server.launchFile
            WorkingDirectory = $Server.launchCwd
            WindowStyle      = 'Hidden'
            PassThru         = $true
        }
        # Start-Process rejects an empty ArgumentList, so only pass it when there is one.
        $launchArgs = @($Server.launchArgs | Where-Object { $_ })
        if ($launchArgs.Count -gt 0) { $startParams.ArgumentList = $launchArgs }

        Write-PanelLog "START $($Server.id): $($Server.launchFile) $($launchArgs -join ' ') (cwd=$($Server.launchCwd))"
        $proc = Start-Process @startParams
    }
    catch {
        Write-PanelLog "START $($Server.id) FAILED: $($_.Exception.Message)" 'ERROR'
        return @{ ok = $false; message = "Could not launch: $($_.Exception.Message)" }
    }
    finally {
        foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }

    # A launcher that dies on the spot is the signature of a bad path or a bad command
    # line. Catch it explicitly instead of blaming a slow map load 45 seconds later.
    Start-Sleep -Milliseconds 1200
    $launcherDied = $false
    $exitCode     = $null
    try {
        if ($proc.HasExited) { $launcherDied = $true; $exitCode = $proc.ExitCode }
    } catch { }

    # Wait up to 45 s for the port to be taken.
    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Date) -lt $deadline) {
        $owner = Get-PortOwnerPid -Server $Server
        if ($owner) {
            Write-PanelLog "START $($Server.id) OK: port $($Server.port) held by PID $owner"
            return @{ ok = $true; message = "Started. Port $($Server.port) held by PID $owner." }
        }
        Start-Sleep -Milliseconds 700
    }

    # Never report success for a port that never came up — that hid a real failure before.
    if ($launcherDied) {
        $detail = "The launcher exited immediately (exit code $exitCode), so the server never started. Check the launchFile path in servers.json."
    }
    else {
        $detail = "The launcher (PID $($proc.Id)) is still running, so the server is booting or crashing. Check console.log."
    }
    Write-PanelLog "START $($Server.id) FAILED: port $($Server.port) never came up. $detail" 'ERROR'
    return @{ ok = $false; message = "Port $($Server.port) never came up within 45 s. $detail" }
}

function Stop-ManagedServer {
    param($Server)

    $report = @()

    # 1) Supervisor first (.bat loop), otherwise it would relaunch the server.
    foreach ($sPid in (Get-SupervisorPids -Server $Server)) {
        $report += Stop-PidSafely -ProcessId $sPid -Reason "supervisor .bat for $($Server.id)"
    }

    # 2) Then the process actually holding the port.
    $procId = Get-PortOwnerPid -Server $Server
    if ($procId) {
        $ok = $true
        if ($Server.kind -eq 'pluto' -and $Server.exe) {
            try {
                $path = (Get-CimInstance Win32_Process -Filter "ProcessId=$procId").ExecutablePath
                if ($path -and $path -ne $Server.exe) {
                    $ok = $false
                    $report += "BLOCKED: PID $procId on port $($Server.port) is '$path', not the expected '$($Server.exe)'"
                    Write-PanelLog "STOP $($Server.id) BLOCKED: unexpected exe on the port ($path)" 'WARN'
                }
            }
            catch { }
        }
        if ($ok) {
            $report += Stop-PidSafely -ProcessId $procId -Reason "process on port $($Server.port) ($($Server.id))"
        }
    }
    else {
        $report += "Nothing was listening on port $($Server.port)"
    }

    # 3) Confirm the port is actually free.
    $deadline = (Get-Date).AddSeconds(12)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        if (-not (Get-PortOwnerPid -Server $Server)) { break }
    }
    $still = Get-PortOwnerPid -Server $Server
    if ($still) {
        $report += "WARNING: port $($Server.port) is still held by PID $still"
        return @{ ok = $false; message = ($report -join ' | ') }
    }
    return @{ ok = $true; message = ($report -join ' | ') }
}

# ------------------------------------------------------------------ logs

function Get-LogTail {
    param([string]$Path, [int]$Bytes = 24000)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return '' }
    try {
        # The server keeps the file open, so everything has to be shared.
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open,
                                     [System.IO.FileAccess]::Read,
                                     [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
        try {
            $len   = $fs.Length
            $start = [Math]::Max(0, $len - $Bytes)
            [void]$fs.Seek($start, [System.IO.SeekOrigin]::Begin)
            $buf = New-Object byte[] ($len - $start)
            $read = $fs.Read($buf, 0, $buf.Length)
            $txt = [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
            if ($start -gt 0) { $txt = $txt.Substring([Math]::Min($txt.Length, $txt.IndexOf("`n") + 1)) }
            return $txt
        }
        finally { $fs.Dispose() }
    }
    catch {
        return "[panel] could not read the log: $($_.Exception.Message)"
    }
}

# -------------------------------------------------------------- raw HTTP

function Read-HttpRequest {
    param([System.IO.Stream]$Stream)

    $ms  = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] 8192
    $headerEnd = -1

    while ($headerEnd -lt 0) {
        $n = $Stream.Read($buf, 0, $buf.Length)
        if ($n -le 0) { return $null }
        $ms.Write($buf, 0, $n)
        $arr = $ms.ToArray()
        for ($i = 0; $i -le $arr.Length - 4; $i++) {
            if ($arr[$i] -eq 13 -and $arr[$i+1] -eq 10 -and $arr[$i+2] -eq 13 -and $arr[$i+3] -eq 10) {
                $headerEnd = $i; break
            }
        }
        if ($ms.Length -gt 1MB) { return $null }
    }

    $all        = $ms.ToArray()
    $headerText = [System.Text.Encoding]::ASCII.GetString($all, 0, $headerEnd)
    $lines      = $headerText -split "`r`n"
    $requestLine = $lines[0] -split ' '

    $headers = @{}
    foreach ($h in $lines[1..($lines.Count - 1)]) {
        $idx = $h.IndexOf(':')
        if ($idx -gt 0) {
            $headers[$h.Substring(0, $idx).Trim().ToLower()] = $h.Substring($idx + 1).Trim()
        }
    }

    $contentLength = 0
    if ($headers['content-length']) { [void][int]::TryParse($headers['content-length'], [ref]$contentLength) }

    $bodyBytes = New-Object byte[] $contentLength
    $have = $all.Length - ($headerEnd + 4)
    if ($have -gt 0) {
        [Array]::Copy($all, $headerEnd + 4, $bodyBytes, 0, [Math]::Min($have, $contentLength))
    }
    $got = [Math]::Min($have, $contentLength)
    while ($got -lt $contentLength) {
        $n = $Stream.Read($bodyBytes, $got, $contentLength - $got)
        if ($n -le 0) { break }
        $got += $n
    }

    return @{
        method  = $requestLine[0]
        target  = $requestLine[1]
        headers = $headers
        body    = [System.Text.Encoding]::UTF8.GetString($bodyBytes, 0, $got)
    }
}

function Write-HttpResponse {
    param(
        [System.IO.Stream]$Stream,
        [int]$Status = 200,
        [string]$ContentType = 'application/json; charset=utf-8',
        [byte[]]$Body = $null,
        [hashtable]$ExtraHeaders = $null
    )
    if ($null -eq $Body) { $Body = [byte[]]@() }
    $reason = switch ($Status) {
        200 { 'OK' } 400 { 'Bad Request' } 403 { 'Forbidden' }
        404 { 'Not Found' } 405 { 'Method Not Allowed' } default { 'Internal Server Error' }
    }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("HTTP/1.1 $Status $reason`r`n")
    [void]$sb.Append("Content-Type: $ContentType`r`n")
    [void]$sb.Append("Content-Length: $($Body.Length)`r`n")
    [void]$sb.Append("Cache-Control: no-store`r`n")
    [void]$sb.Append("Connection: close`r`n")
    if ($ExtraHeaders) {
        foreach ($k in $ExtraHeaders.Keys) { [void]$sb.Append("$k`: $($ExtraHeaders[$k])`r`n") }
    }
    [void]$sb.Append("`r`n")
    $head = [System.Text.Encoding]::ASCII.GetBytes($sb.ToString())
    $Stream.Write($head, 0, $head.Length)
    if ($Body.Length -gt 0) { $Stream.Write($Body, 0, $Body.Length) }
    $Stream.Flush()
}

function Write-Json {
    param([System.IO.Stream]$Stream, $Object, [int]$Status = 200)
    $json = $Object | ConvertTo-Json -Depth 8 -Compress
    Write-HttpResponse -Stream $Stream -Status $Status -Body ([System.Text.Encoding]::UTF8.GetBytes($json))
}

function Get-QueryParams {
    param([string]$Target)
    $q = @{}
    $i = $Target.IndexOf('?')
    if ($i -lt 0) { return $q }
    foreach ($pair in $Target.Substring($i + 1) -split '&') {
        $kv = $pair -split '=', 2
        if ($kv[0]) { $q[[Uri]::UnescapeDataString($kv[0])] = if ($kv.Count -gt 1) { [Uri]::UnescapeDataString($kv[1].Replace('+',' ')) } else { '' } }
    }
    return $q
}

# ------------------------------------------------------------------ main

$Token = Get-PanelToken

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
try {
    $listener.Start()
}
catch {
    # Usually this just means another instance is already listening: exit
    # quietly so START-PANEL.vbs simply opens the browser.
    Write-PanelLog "Could not bind port $Port (panel already open?): $($_.Exception.Message)" 'WARN'
    exit 1
}

Set-Content -LiteralPath $PidPath -Value $PID -Encoding ascii -NoNewline
Write-PanelLog "Panel started on http://127.0.0.1:$Port  (PID $PID)"
$script:Running = $true

while ($script:Running) {
    $client = $null
    try {
        $client = $listener.AcceptTcpClient()
        $client.ReceiveTimeout = 15000
        $client.SendTimeout    = 15000
        $stream = $client.GetStream()

        $req = Read-HttpRequest -Stream $stream
        if (-not $req) { continue }

        $path  = ($req.target -split '\?')[0]
        $query = Get-QueryParams -Target $req.target

        # --- UI ------------------------------------------------------------
        if ($path -eq '/' -or $path -eq '/index.html') {
            $html = Get-Content -LiteralPath $UiPath -Raw -Encoding utf8
            $html = $html.Replace('__PANEL_TOKEN__', $Token)
            Write-HttpResponse -Stream $stream -ContentType 'text/html; charset=utf-8' `
                               -Body ([System.Text.Encoding]::UTF8.GetBytes($html))
            continue
        }
        if ($path -eq '/favicon.ico') {
            Write-HttpResponse -Stream $stream -Status 404
            continue
        }

        # --- Auth for everything under /api/* --------------------------------
        if ($path -like '/api/*') {
            if ($req.headers['x-panel-token'] -ne $Token) {
                Write-Json -Stream $stream -Status 403 -Object @{ ok = $false; error = 'invalid token' }
                continue
            }
        }

        switch -Wildcard ($path) {

            '/api/status' {
                # TEMP INSTRUMENTATION 2026-07-30: profiling showed a pure-network sweep of all 7
                # game servers costs only ~1.7 s while this endpoint took ~7.4 s, so ~5.7 s was
                # unaccounted for. Log a per-server breakdown to find it instead of guessing.
                $swTotal = [Diagnostics.Stopwatch]::StartNew()
                $swCfg   = [Diagnostics.Stopwatch]::StartNew()
                $srvList = @(Get-Servers)
                $swCfg.Stop()
                $marks = @()
                $states = @(foreach ($s in $srvList) {
                    $swOne = [Diagnostics.Stopwatch]::StartNew()
                    $st = Get-ServerState -Server $s
                    $swOne.Stop()
                    $marks += ('{0}={1:N0}' -f $s.id, $swOne.Elapsed.TotalMilliseconds)
                    $st
                })
                $swJson = [Diagnostics.Stopwatch]::StartNew()
                Write-Json -Stream $stream -Object @{ ok = $true; time = (Get-Date -Format 'HH:mm:ss'); servers = $states }
                $swJson.Stop()
                $swTotal.Stop()
                # Gated so it is not permanent log spam (a polling browser would write ~17k
                # lines/day). Turn on with:  $env:PANEL_PROFILE = '1'  before starting the panel.
                if ($env:PANEL_PROFILE -eq '1') {
                    Write-PanelLog ("PROF /api/status total={0:N0}ms cfg={1:N0}ms json+write={2:N0}ms | {3}" -f `
                        $swTotal.Elapsed.TotalMilliseconds, $swCfg.Elapsed.TotalMilliseconds, $swJson.Elapsed.TotalMilliseconds, ($marks -join ' '))
                }
            }

            '/api/action' {
                $b  = $req.body | ConvertFrom-Json
                $s  = Get-ServerById -Id $b.id
                if (-not $s) { Write-Json -Stream $stream -Status 400 -Object @{ ok = $false; error = 'unknown server' }; break }
                switch ($b.action) {
                    'start'   { $r = Start-ManagedServer -Server $s }
                    'stop'    { $r = Stop-ManagedServer  -Server $s }
                    'restart' {
                        $r1 = Stop-ManagedServer -Server $s
                        Start-Sleep -Seconds 2
                        $r2 = Start-ManagedServer -Server $s
                        $r  = @{ ok = $r2.ok; message = "STOP: $($r1.message)  //  START: $($r2.message)" }
                    }
                    default   { $r = @{ ok = $false; message = "unknown action: $($b.action)" } }
                }
                Write-PanelLog "ACTION $($b.action) $($b.id) -> ok=$($r.ok) : $($r.message)"
                Write-Json -Stream $stream -Object $r
            }

            '/api/rcon' {
                $b = $req.body | ConvertFrom-Json
                $s = Get-ServerById -Id $b.id
                if (-not $s -or -not $s.rcon) {
                    Write-Json -Stream $stream -Status 400 -Object @{ ok = $false; error = 'that server has no rcon' }; break
                }
                $cmd = [string]$b.cmd
                # A "set" carrying a multi-KB string wedges the server's rcon
                # handler (seen back in July). Cut it off here.
                if ($cmd.Length -gt 900) {
                    Write-Json -Stream $stream -Object @{
                        ok = $false
                        output = "[panel] command rejected: $($cmd.Length) characters. Very long rcon commands (multi-KB dvars) wedge the server's rcon handler. Limit: 900."
                    }
                    break
                }
                Write-PanelLog "RCON $($s.id): $cmd"
                $out = Invoke-Rcon -RconPort $s.port -Password $s.rcon -Command $cmd
                Write-Json -Stream $stream -Object @{ ok = $true; output = $out }
            }

            '/api/log' {
                $s = Get-ServerById -Id $query['id']
                if (-not $s -or -not $s.log) {
                    Write-Json -Stream $stream -Status 400 -Object @{ ok = $false; error = 'that server has no log' }; break
                }
                $bytes = 24000
                if ($query['bytes']) { [void][int]::TryParse($query['bytes'], [ref]$bytes) }
                $bytes = [Math]::Min([Math]::Max($bytes, 1000), 400000)
                Write-Json -Stream $stream -Object @{ ok = $true; text = (Get-LogTail -Path $s.log -Bytes $bytes) }
            }

            '/api/quit' {
                Write-Json -Stream $stream -Object @{ ok = $true; message = 'panel shutting down' }
                Write-PanelLog 'Panel stopped from the UI'
                $script:Running = $false
            }

            default {
                Write-Json -Stream $stream -Status 404 -Object @{ ok = $false; error = 'route not found' }
            }
        }
    }
    catch {
        Write-PanelLog "Error handling request: $($_.Exception.Message)" 'ERROR'
        try { Write-Json -Stream $stream -Status 500 -Object @{ ok = $false; error = $_.Exception.Message } } catch { }
    }
    finally {
        try { if ($client) { $client.Close() } } catch { }
    }
}

try { $listener.Stop() } catch { }
try { Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue } catch { }
Write-PanelLog 'Panel stopped.'
