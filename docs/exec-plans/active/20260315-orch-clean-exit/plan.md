# Plan: Orch clean dashboard exit on SHIP

**Status:** In progress
**Created:** 2026-03-15

## Requirements

- On SHIP, the dashboard shows a final "SHIP" screen before the tmux session is killed
- The terminal doesn't leave broken shell residue after the session ends
- The engine waits long enough for the dashboard to render the final state

## Approach

Two changes:

1. **Engine side** (`orch-engine.sh`): on SHIP, write a `status: "completed"` field to state.json, then `sleep 5` before killing the tmux session. This gives the dashboard time to detect the completed status and render a final screen.

2. **Dashboard side** (`orchestrator-app.tsx`): detect when state has `status: "completed"` (or when the state file shows all items done + finalReview SHIP). Render a "SHIP" banner. The dashboard's infinite restart loop in the tmux command already keeps it alive — it just needs to show the right thing.

The terminal cleanup (exec, clean close) is handled by the separate fullscreen-terminal plan.

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-engine.sh` | Write completed status to state.json, sleep 5 before kill-session |
| `scripts/terminal-ui/src/orchestrator-app.tsx` | Detect completed status, render SHIP banner |

## Risks and open questions

- None

## Progress log

- [ ] Write completed status to state.json on SHIP path in orch-engine.sh, add sleep before kill
- [ ] Detect completed status in orchestrator-app.tsx and render SHIP banner

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Write status to existing state.json | Separate signal file | Dashboard already watches state.json, no new watcher needed |
| Sleep 5s before kill | Don't kill, let user close | Clean automated cleanup; 5s is enough for render |

## Completion criteria

- [ ] Dashboard renders SHIP banner when engine completes
- [ ] Engine waits before killing session
- [ ] `shellcheck scripts/orch-engine.sh` clean
- [ ] `tsc --noEmit` passes for terminal-ui
