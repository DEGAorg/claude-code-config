# Plan: Orch persist engine logs on SHIP

**Status:** In progress
**Created:** 2026-03-15

## Requirements

- Engine log file survives after SHIP (already tee'd to `.orchestrator/plans/<slug>/logs/engine.log`)
- Print the log file path at the end of the engine run
- Copy final `state.json` to `docs/exec-plans/completed/<slug>/state.json` so run history is preserved alongside the archived plan

## Approach

The engine already tee's output to a log file. Verify it survives `orch_cleanup_worktree` (it should — cleanup only touches the worktree, not the logs dir). Add two things:

1. Print `orch-engine: log saved to <path>` before killing the tmux session
2. On SHIP path, after moving the plan to completed, copy `state.json` into the completed plan directory

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-engine.sh` | Add log path message on SHIP, copy state.json to completed dir |

## Risks and open questions

- None

## Progress log

- [x] Add log path message and state.json copy to SHIP path in orch-engine.sh

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Copy state.json to completed dir | Keep only in .orchestrator | Plan dirs are the permanent record; .orchestrator is ephemeral |

## Completion criteria

- [ ] Engine prints log path on SHIP
- [ ] `state.json` copied to completed plan directory on SHIP
- [ ] `shellcheck scripts/orch-engine.sh` clean
