# collect-feedback.ps1 - archives player !feedback lines from the survival console logs
# into C:\Survival\FEEDBACK.md before log rotation can eat them.
# Runs every 30 min via the "MW3 Survival Feedback" scheduled task.
# (Plutonium IW5 GSC has no file I/O, so the GSC prints tagged lines instead.)
# ASCII ONLY - scheduled tasks run Windows PowerShell 5.1 which reads this as ANSI.
#
# 2026-08-01: now reads ALL FOUR survival instances. It previously read only
# C:\Survival (port <SURV-PORT-1>), but bpg_survival_feedback.gsc registers !feedback and !fb on
# every instance - so any feedback left on <SURV-PORT-2>/<SURV-PORT-3>/<SURV-PORT-4> was never collected and was lost
# the next time that server restarted and truncated its log. Each entry is now tagged with the
# port it came from, which also tells us which server a complaint refers to.

$ErrorActionPreference = 'SilentlyContinue'

$logs = @(
    @{ Port = <SURV-PORT-1>; Path = 'C:\Survival\appdata\Plutonium\console.log'  },
    @{ Port = <SURV-PORT-2>; Path = 'C:\Survival2\appdata\Plutonium\console.log' },
    @{ Port = <SURV-PORT-3>; Path = 'C:\Survival3\appdata\Plutonium\console.log' },
    @{ Port = <SURV-PORT-4>; Path = 'C:\Survival4\appdata\Plutonium\console.log' }
)
$out = 'C:\Survival\FEEDBACK.md'

if (-not (Test-Path $out)) {
    Set-Content -LiteralPath $out -Value "# Player feedback (via !feedback on the survival servers)"
}
$existing = @(Get-Content $out)

$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
$new = 0

foreach ($srv in $logs) {
    if (-not (Test-Path $srv.Path)) { continue }

    $lines = Select-String -LiteralPath $srv.Path -Pattern '[BPGFEEDBACK]' -SimpleMatch | ForEach-Object { $_.Line.Trim() }
    if (-not $lines) { continue }

    foreach ($l in $lines) {
        # strip console prefix noise before the tag
        $idx = $l.IndexOf('[BPGFEEDBACK]')
        if ($idx -lt 0) { continue }
        $clean = $l.Substring($idx + 14).Trim()
        if ($clean -eq '') { continue }

        $needle = '- [' + $srv.Port + '] ' + $clean

        # Dedupe on the content portion, ignoring the collection stamp. The same line is
        # re-read on every run until the log rotates, so without this the file would grow
        # a duplicate every 30 minutes.
        $dupe = $false
        foreach ($e in $existing) { if ($e -like ($needle + '*')) { $dupe = $true; break } }
        if ($dupe) { continue }

        $entry = $needle + "  (collected $stamp)"
        Add-Content -LiteralPath $out -Value $entry
        $existing += $entry
        $new++
    }
}
