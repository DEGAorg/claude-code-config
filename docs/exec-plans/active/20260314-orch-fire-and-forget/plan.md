# Plan: Fire-and-Forget Orchestrator Launch

**Status:** In progress
**Created:** 2026-03-14

## Requirements

- `orch-run.sh` returns immediately after launching the tmux session
- The calling terminal shows only a one-line success/error message
- All orchestrator logging happens inside the tmux session, not stdout
- The poll loop runs inside tmux, not in the calling shell
- User experience: type command, see "launched", terminal is free

## Current state

`orch-run.sh` runs the entire poll loop in the foreground of the calling
terminal. Every poll cycle prints status lines (`orch-run: [poll] done=3
running=2 ...`). The calling terminal is blocked until all items complete
and the review finishes. The tmux session exists but the real work
coordination happens in the caller's shell.

This means:
- The user's terminal is locked for the entire run
- Closing the terminal kills the orchestrator
- Verbose output clutters the terminal that triggered the run
- No way to launch multiple plans from the same terminal

## Approach

Split `orch-run.sh` into two parts:

1. **Launcher (orch-run.sh):** Validates inputs, initializes state,
   creates the tmux session with the dashboard window, registers in
   master.json, creates the worktree, then starts the poll loop
   *inside a tmux window* and exits. Returns 0 with a one-line
   message: `orch: launched <slug> — attach with: tmux attach -t orch-<slug>`

2. **Engine (orch-engine.sh):** The poll loop, worker spawning, review
   invocation, and cleanup. Runs inside a tmux window named `engine`
   in the orchestrator session. All logging goes to this window (and
   optionally to a log file). This is the long-running process.

The engine window is hidden from the user by default (dashboard is the
selected window). The user can switch to it to see raw orchestrator
logs if needed.

### Terminal layout after launch

```
tmux session: orch-<slug>
├── window 0: dashboard     ← user sees this (Ink app)
├── window 1: engine        ← poll loop, hidden by default
├── window 2: worker-1      ← spawned by engine
├── window 3: worker-2      ← spawned by engine
└── ...
```

### Error handling

If initialization fails (plan not found, parse error, tmux unavailable),
`orch-run.sh` prints the error to stderr and exits non-zero. The tmux
session is never created. Clean failure.

If the engine crashes after launch, stale worker detection handles
recovery on next run (resume from state.json).

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-run.sh` | Extract poll loop and everything after into engine invocation. Launch engine as tmux window. Print one-line result and exit. |
| `scripts/orch-engine.sh` | New file. Contains the poll loop, spawn_worker, build_worker_prompt, review invocation, cleanup. Sourced from orch-state.sh. |
| `scripts/orch-state.sh` | Add `orch_plan_log_file()` helper for engine log path. |

## Risks and open questions

- **Engine crash recovery:** If the engine tmux window dies, the
  orchestrator stops but workers may keep running. On next
  `orch-run.sh <slug>`, it resumes from state.json — running workers
  are detected as stale (panes alive but no engine polling). Decision:
  acceptable for v1. The stale detection handles this.
- **Multiple launches of same slug:** `orch-run.sh` already checks for
  an existing tmux session and resumes. With fire-and-forget, it should
  detect the running engine and print "already running" instead of
  double-launching.

## Progress log

- [ ] Create `orch-engine.sh` with the poll loop, spawn_worker, build_worker_prompt, review call, and cleanup logic extracted from orch-run.sh. (deps: none)
- [ ] Refactor `orch-run.sh` to launcher-only: validate, init state, create tmux session, start engine as tmux window, open display, print one-line result, exit. (deps: 1)
- [ ] Add already-running detection: if tmux session exists and engine window is alive, print status and exit. (deps: 1)
- [ ] Add `orch_plan_log_file()` to orch-state.sh. Engine writes its log to `plans/<slug>/engine.log`. (deps: none)
- [ ] Test: launch plan, verify terminal returns immediately, verify engine runs inside tmux, verify workers spawn correctly. (deps: 2, 3, 4)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Separate engine script in tmux window | nohup/disown, background subshell | tmux window is visible for debugging, survives terminal close, consistent with worker pattern |
| Engine as hidden tmux window | Engine as background process | User can switch to engine window to inspect logs, tmux manages lifecycle |
| One-line output on launch | No output, JSON output | Clear feedback that launch succeeded, includes attach command for manual inspection |

## Completion criteria

- [ ] `orch-run.sh` returns in under 5 seconds after printing launch message
- [ ] Closing the calling terminal does not kill the orchestrator
- [ ] Engine runs inside tmux and drives workers to completion
- [ ] Multiple plans can be launched from the same terminal sequentially
- [ ] Already-running plan detected with helpful message
- [ ] shellcheck clean
