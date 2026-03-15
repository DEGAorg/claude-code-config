# Plan: Orch UX improvements

**Status:** In progress
**Created:** 2026-03-15

## Requirements

1. **Persist engine output** — engine logs are lost when the tmux session is killed on SHIP. The engine tee's to a log file (`orch_plan_log_file`) but the tmux session kill also kills the dashboard. Ensure the engine log file survives and is findable after completion.
2. **Full-screen terminal window** — the `.command` file opens a default-sized Terminal.app window. It should open maximized/full-screen so the dashboard has room.
3. **Clean dashboard exit** — on SHIP, `tmux kill-session` kills the tmux session, which kills the attached terminal's shell, leaving it in a broken state with tmux output residue. Instead: show a final "SHIP" message on the dashboard, wait a few seconds, then close cleanly.
4. **Reliable done-file tracking** — workers signal completion by writing done-files and checking plan.md checkboxes, but the sync relies on polling. The ralph loop uses `plan-advance.sh` and `review-advance.sh` as structural gates. The orch needs an equally trustworthy mechanism: done-files should be validated (not just existence-checked) and the state.json should be the single source of truth.

## Approach

### 1. Persist engine output

The engine already tee's to a log file (line 220 of orch-run.sh: `tee '${LOG_FILE}'`). The log persists in `.orchestrator/plans/<slug>/logs/engine.log`. However, `orch_cleanup_worktree` doesn't touch logs. Verify the log file survives SHIP. If it does, just add a message at the end pointing to it:

```
orch-engine: log saved to .orchestrator/plans/<slug>/logs/engine.log
```

Also: on SHIP, copy the final `state.json` to `completed/<slug>/state.json` so the full run history is preserved alongside the plan.

### 2. Full-screen terminal window

In `orch-display.sh`, the `.command` file just runs `tmux attach`. Modify the `.command` file to resize the Terminal.app window to full screen using `printf '\e[9;1t'` (xterm maximize escape) before attaching. This works in Terminal.app and most terminal emulators. Alternative: use AppleScript to set the window to full screen after opening.

### 3. Clean dashboard exit

Current flow: engine SHIP → `tmux kill-session` → dashboard dies → attached Terminal left in broken state.

New flow:
1. Engine writes a `status: "completed"` marker to state.json before killing the session
2. Dashboard Ink app detects `status: "completed"` and renders a final "SHIP" screen
3. Engine sleeps 5 seconds (dashboard has time to render)
4. Engine kills the tmux session
5. The `.command` file's shell exits cleanly (tmux attach returns 0 when session ends)

To fix the broken terminal: the `.command` file should have `exec tmux attach...` so when tmux exits, the terminal window closes automatically (no leftover shell).

### 4. Reliable done-file validation

Current: `orch_sync_done_files` checks if `item-N.txt` exists and has worktree changes. This is good but has gaps:
- A worker could write a done-file without checking the plan.md checkbox
- The done-file content isn't validated (could be empty)

Add:
- Minimum done-file size check (reject files < 20 bytes — real summaries are longer)
- Log a warning if the plan.md checkbox for this item isn't checked (non-blocking but visible)

The current approach is already trustworthy for the orch's parallel model. The ralph loop's `plan-advance.sh` is sequential (one item at a time) — it doesn't apply to parallel workers. State.json IS the single source of truth already. The gap is validation quality, not architecture.

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-engine.sh` | Add log path message on SHIP, write completed status before kill, sleep before kill, copy state to completed dir |
| `scripts/orch-display.sh` | Add maximize escape to .command file, use exec for clean exit |
| `scripts/terminal-ui/src/orchestrator-app.tsx` | Detect completed status, render final SHIP screen |
| `scripts/orch-state.sh` | Add minimum done-file size validation in `orch_sync_done_files` |

## Risks and open questions

- **P2:** `\e[9;1t` maximize escape may not work in all terminal emulators. It works in Terminal.app and iTerm2 on macOS. Linux terminals vary. Acceptable — fallback is default window size (current behavior).

## Progress log

- [ ] Persist engine output: verify log survives SHIP, add log path message, copy state.json to completed dir
- [ ] Full-screen terminal: add maximize escape to .command file, use `exec` for clean exit
- [ ] Clean dashboard exit: write completed status to state.json, dashboard renders final screen, sleep before kill
- [ ] Done-file validation: add minimum size check, warn on unchecked checkbox (deps: 3)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| xterm maximize escape | AppleScript resize | Works cross-platform, no permissions needed, single printf |
| `exec tmux attach` in .command | trap EXIT cleanup | exec replaces the shell process — when tmux exits, the terminal window closes. Zero cleanup needed. |
| Write completed status to state.json | Separate signal file | state.json is already watched by the dashboard. No new file, no new watcher. |
| Minimum 20-byte done-file check | Parse done-file structure | Simple, catches empty/trivial files. Strict parsing is fragile and unnecessary. |

## Completion criteria

- [ ] Engine log file exists at `.orchestrator/plans/<slug>/logs/engine.log` after SHIP
- [ ] Terminal window opens maximized on macOS
- [ ] Dashboard shows "SHIP" message before terminal closes
- [ ] Terminal window closes cleanly (no broken shell residue)
- [ ] Empty done-files are rejected by `orch_sync_done_files`
- [ ] `shellcheck scripts/orch-engine.sh scripts/orch-display.sh scripts/orch-state.sh` clean
