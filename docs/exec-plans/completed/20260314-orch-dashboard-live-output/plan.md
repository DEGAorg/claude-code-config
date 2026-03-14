# Plan: Dashboard Live Worker Output

**Status:** In progress
**Created:** 2026-03-14

## Requirements

- Dashboard detail panel shows live output from the selected worker
- Worker windows spawn in background (no auto-focus switch away from dashboard)
- Finished worker windows auto-close after done-file detected
- Works on macOS and Linux (tmux pipe-pane is cross-platform)

## Current state

The dashboard has j/k navigation, a `SessionDetail` component, and an
`outputLines` prop — but `outputLines` is always empty. Workers spawn as
tmux windows that auto-focus, pulling the user away from the dashboard.
Finished worker windows linger until their sleep expires.

## Approach

### Live output capture via tmux pipe-pane

When spawning a worker, also run:
```bash
tmux pipe-pane -t "${SESSION}:worker-${ID}" -o "cat >> ${LOG_DIR}/worker-${ID}.log"
```

This streams the worker pane's terminal output to a log file without
affecting the worker process. The `-o` flag captures only output (not input).
`pipe-pane` is a core tmux command available on all platforms since tmux 1.1.

The log files live at `.orchestrator/plans/<slug>/logs/worker-N.log`.

### Dashboard reads log files

The `OrchestratorApp` component watches the log file for the currently
selected item using chokidar (already a dependency). When the selected
item changes, swap the watcher to the new item's log file. Render the
last N lines in `SessionDetail`.

### Don't auto-focus worker windows

Change `tmux new-window` to `tmux new-window -d` in spawn_worker. The
`-d` flag creates the window without switching focus, so the user stays
on the dashboard.

### Auto-kill finished worker windows

In the poll loop, after `orch_sync_done_files` marks an item as "done",
kill the corresponding tmux window:
```bash
tmux kill-window -t "${SESSION}:worker-${ID}" 2>/dev/null
```

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-run.sh` | Create logs dir. Add `tmux pipe-pane` after spawn. Add `-d` to `tmux new-window`. Kill finished worker windows after sync. |
| `scripts/orch-state.sh` | Add `orch_plan_log_dir()` path helper. Add `orch_kill_done_workers()` function. |
| `scripts/terminal-ui/src/orchestrator-app.tsx` | Watch selected item's log file, pipe lines into `outputLines` state. Swap watcher on j/k navigation. |
| `scripts/terminal-ui/src/orch-types.ts` | Add `orchPlanLogDir()` helper. |
| `scripts/terminal-ui/src/session-detail.tsx` | Strip ANSI escape sequences from log lines for clean rendering. |

## Risks and open questions

- **ANSI escape sequences:** Worker output contains terminal control codes
  (colors, cursor movement, clearing). The dashboard needs to strip these
  before rendering. Use `strip-ansi` (already in the dependency tree via Ink)
  to clean log lines.
- **Log file size:** Long-running workers can produce large logs. The
  dashboard only reads the tail (last N lines), but the file itself grows.
  Acceptable for orchestrator lifetimes (minutes to hours). Not a concern.
- **pipe-pane on dead panes:** If a worker crashes and the pane dies,
  pipe-pane stops writing. The log file has whatever was captured up to
  that point — useful for debugging the crash.
- **chokidar on Linux:** Already used for state.json watching. Works on
  both macOS (FSEvents) and Linux (inotify). No changes needed.

## Progress log

- [x] Add `orch_plan_log_dir()` to `orch-state.sh` and `orch_ensure_plan_dirs`. (deps: none)
- [x] Add `orch_kill_done_workers()` to `orch-state.sh`: takes slug, reads state for newly-done items with tmux windows, kills them. (deps: none)
- [x] Update `orch-run.sh` spawn_worker: add `-d` flag to `tmux new-window`, add `tmux pipe-pane` after spawn to stream output to `logs/worker-N.log`. (deps: 1)
- [x] Update `orch-run.sh` poll loop: call `orch_kill_done_workers` after `orch_sync_done_files`. (deps: 2)
- [x] Add `orchPlanLogDir()` to `orch-types.ts`. (deps: none)
- [x] Update `orchestrator-app.tsx`: watch selected item's log file via chokidar, read tail on change, set `outputLines` state. Swap watcher on selection change. (deps: 5)
- [x] Update `session-detail.tsx`: strip ANSI escape sequences from output lines before rendering. (deps: none)
- [x] Rebuild terminal-ui and test with the demo plan: verify live output appears in dashboard, workers don't steal focus, finished windows auto-close. (deps: 3, 4, 6, 7)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| tmux pipe-pane to log file | tmux capture-pane polling, worker tee | Zero overhead on worker, persistent log, works on macOS and Linux since tmux 1.1 |
| chokidar to watch log files | fs.watchFile polling, tail -f child process | Already a dependency, cross-platform (FSEvents + inotify), event-driven |
| strip-ansi for rendering | Raw rendering, custom parser | Already in dependency tree via Ink, handles all ANSI sequences correctly |
| -d flag on new-window | select-window back to dashboard after spawn | Simpler, no race condition, one-line change |

## Completion criteria

- [ ] Selecting a running worker in the dashboard shows its live output in the detail panel
- [ ] Navigating away and back shows the new worker's output
- [ ] New worker windows don't steal focus from dashboard
- [ ] Finished worker windows close automatically
- [ ] Works on macOS and Linux (tmux pipe-pane + chokidar)
- [ ] shellcheck clean on bash, tsc clean on TypeScript
