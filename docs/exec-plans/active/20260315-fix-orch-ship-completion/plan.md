# Plan: Clear SHIP completion — state, dashboard, and session cleanup

**Status:** In progress
**Created:** 2026-03-15

## Requirements

After SHIP, the orch is in an ambiguous state:
- The engine prints "dashboard stays open — close the terminal window when done"
- The tmux session lingers with dead worker windows
- The dashboard may not clearly show COMPLETED
- The planner loop and external tools have no clean signal to detect completion

Make SHIP a clear, unambiguous end state:
1. `state.json` gets `"status": "completed"` (already done, but verify)
2. Dashboard renders SHIP screen immediately
3. Tmux session auto-closes after a brief delay
4. Sound plays (already done)
5. Engine exits cleanly with exit code 0

## Current behavior (orch-engine.sh lines 380-567)

After all 8 SHIP steps and validation:
- Writes `"status": "completed"` to state.json (line 500-503) — good
- Prints "dashboard stays open" — bad, should auto-close
- Does NOT kill the tmux session — lingers forever
- Does NOT exit explicitly — falls through to end of script
- Worker windows are killed (line 399) but dashboard and engine stay

The dashboard (`orchestrator-app.tsx` lines 158-175) does have a
SHIP screen that renders when `state.status === "completed"`, but the
timing of the state file write vs dashboard poll may cause a brief
"no output" gap before the SHIP screen appears.

## Approach

### orch-engine.sh changes

After SHIP step 8 and validation, replace the lingering "dashboard stays
open" message with:

1. Write `"status": "completed"` to state.json (already done)
2. Print a clear SHIP summary with timing
3. Sleep 10 seconds so the dashboard can render the SHIP screen
4. Kill the tmux session (all windows including dashboard)

For FAILED outcomes, do the same but with `"status": "failed"` and a
shorter delay.

### Dashboard changes

The dashboard SHIP screen (orchestrator-app.tsx lines 158-175) currently
shows "Window will close shortly." — this is correct with the new
auto-close behavior.

Ensure the dashboard polls state frequently enough (it already polls via
chokidar file watch) to catch the `"status": "completed"` write before
the session closes.

### planner-loop.sh monitoring

The `run_monitor()` function in planner-loop.sh polls `state.json` for
`status === "completed"` or `status === "failed"`. Currently it also checks
individual item statuses. Verify this works correctly with the new clean
shutdown — the state file must be written before the tmux session is killed.

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-engine.sh` | Auto-close tmux session after SHIP delay, clean exit |
| `scripts/planner-loop.sh` | Verify monitor detects completion from state.json status field |

## Progress log

- [ ] In orch-engine.sh, replace "dashboard stays open" with auto-close after 10s delay on SHIP (deps: none)
- [ ] In orch-engine.sh, add auto-close after 5s delay on FAILED (deps: none)
- [ ] In orch-engine.sh, add SHIP summary with total elapsed time (deps: none)
- [ ] Verify planner-loop.sh run_monitor reads state.json status field correctly (deps: none)
- [ ] Run shellcheck on modified files (deps: 1-4)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| 10s delay before kill on SHIP | 5s, 30s, no delay | Enough for dashboard to render SHIP screen, not too long to wait |
| 5s delay on FAILED | Same as SHIP, no delay | Failed state needs quick feedback, less to show |
| Kill entire tmux session | Kill only engine window | Dead sessions clutter tmux, dashboard has no purpose after SHIP |

## Completion criteria

- [ ] After SHIP, tmux session auto-closes within ~15 seconds
- [ ] After FAILED, tmux session auto-closes within ~10 seconds
- [ ] `state.json` has `"status": "completed"` before session closes
- [ ] Dashboard renders SHIP screen before session closes
- [ ] `shellcheck` passes on modified files
