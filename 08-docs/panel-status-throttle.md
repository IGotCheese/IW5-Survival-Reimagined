# Proposed: stop the panel flooding every server console

**Status: NOT APPLIED.** This changes what your dashboard does, so it's yours to approve.

## The problem, measured

`panel.ps1:339-340` sends an rcon `status` to every configured server on every `/api/status`
sweep, and the browser refreshes every 5 s. Every rcon `status` echoes the full player/bot
table into that server's own `console.log` — one header block plus one row per player *and*
per bot (13–18 rows on a survival server full of bots).

Measured on <SURV-PORT-2> (32,047 lines of console.log):

| source | lines | share |
|---|---|---|
| player-list rows | 24,778 | 77% |
| status-dump headers | 4,389 | 14% |
| blank / other | 2,778 | 9% |
| all BPG diagnostics | 76 | 0.24% |
| actual script errors | 26 | 0.08% |

**91% of the console is this poll.** It isn't cosmetic: it burns through the log so fast that
history is lost on rotation, which is why `FEEDBACK.md` captured nothing and why error history
keeps vanishing on restart.

## Why `status` is called at all

The `getinfo` block just above it (no password, does **not** echo to the console) already
provides hostname, map, gametype, maxclients, mod and a client **count**. The rcon `status`
call adds two things on top:

1. the player **list** (names/scores/pings/bot flag) — the only source for this
2. `rconOk`, used as a health indicator

## The change

Two guards, both minimal:

```powershell
        if ($Server.rcon) {
            # 2026-08-01: only call rcon 'status' when it can actually tell us something new.
            #   * clients == 0  -> there is no player list to fetch, and getinfo already told
            #                      us the server is answering.
            #   * otherwise     -> throttle to ~30 s. A player list does not change meaningfully
            #                      every 5 s, and each call dumps 13-18 rows into that server's
            #                      console.log. This is 91% of console volume.
            $needList = ([int]$state.players -gt 0)
            $lastKey  = "statusPoll_$($Server.port)"
            $due      = (-not $script:PollClock.ContainsKey($lastKey)) -or
                        (((Get-Date) - $script:PollClock[$lastKey]).TotalSeconds -ge 30)

            if ($needList -and $due) {
                $script:PollClock[$lastKey] = Get-Date
                $st = Invoke-Rcon -RconPort $Server.port -Password $Server.rcon -Command 'status' -TimeoutMs 900
                ...existing handling unchanged...
            }
        }
```

plus, once near the top of the script:

```powershell
if (-not $script:PollClock) { $script:PollClock = @{} }
```

## What it costs you

- **Empty servers show no `rconOk` tick.** `getinfo` still proves they're alive and still
  drives hostname/map/gametype/count, so the dashboard stays accurate — but if you rely on
  `rconOk` specifically to confirm the rcon password is right, that indicator only appears
  once someone is on. If that matters, the alternative is to keep the call but throttle it to
  30 s for everyone, which still removes ~85% of the volume.
- **Player names update every ~30 s instead of every 5 s.** Counts stay live (getinfo).

## Expected result

Console volume drops by roughly 85–90%, logs retain hours-to-days of history instead of
minutes, and real errors stop being buried. Nothing else about the panel changes.
