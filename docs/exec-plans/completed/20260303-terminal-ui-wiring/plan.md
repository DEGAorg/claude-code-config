# Plan: Terminal UI Wiring (End-to-End)

**Status:** In progress
**Created:** 2026-03-03
**Parent:** `docs/research/terminal-ui-action-plan.md` (Plan 5)
**Depends on:** Plans 1-4 (state spec, Ink dashboard, tmux launcher, /canon-start)

## Requirements

- End-to-end flow: user runs `/canon-start` → sees two tmux panes → agent drives
  workflow → status updates appear in dashboard
- `/apply-core` installs `terminal-ui` and `terminal-session.sh` globally
- Ralph Loop writes state updates to terminal-ui state file during iterations
- Canon agents reference state file writes in their workflow
- All pieces from Plans 1-4 are connected and tested together

## Approach

Five integration points, each is a small edit to an existing file.

### 1. `/apply-core` — add terminal-ui to install list

Add these files to the `/apply-core` file list and install steps:

```
scripts/terminal-session.sh    → ~/.claude/scripts/terminal-session.sh
scripts/terminal-ui-write.sh   → ~/.claude/scripts/terminal-ui-write.sh
scripts/terminal-ui/           → ~/.claude/scripts/terminal-ui/
```

The Ink app needs `pnpm install` after copying. Add a post-install step:
`cd ~/.claude/scripts/terminal-ui && pnpm install --frozen-lockfile`

Add a new component to the install menu:

- **Terminal UI** — visual status dashboard for automation. Includes tmux session
  launcher (`terminal-session.sh`), state file writer (`terminal-ui-write.sh`),
  and Ink status dashboard (`terminal-ui/`). Requires Node.js.

### 2. Ralph Loop — write terminal-ui state during iterations

Add state file writes to `scripts/ralph-loop.sh` at key lifecycle points:

| Event | State update |
|-------|-------------|
| Loop start | `phase=run status=running metric.iteration=1 metric.maxIterations=$MAX` |
| Worker start | `log.info="Worker iteration $i: $CURRENT_TASK"` |
| Worker done | `log.info="Worker done" metric.iteration=$i` |
| Reviewer decision | `log.info="Reviewer: $RESULT" metric.decision=$RESULT` |
| SHIP | `status=idle log.info="SHIP — all criteria met"` |
| BLOCKED | `status=error error="Blocked — human action required"` |
| EXHAUSTED | `status=error error="Max iterations reached without SHIP"` |
| Stagnation | `status=error error="Stagnated — no changes in 2 iterations"` |

The state file path is `${TASK_DIR}/.terminal-ui-state.json` (colocated with the
exec-plan). Ralph Loop creates it at start, updates it during the loop, and the
user can point `terminal-session.sh` at it.

Guard: only write if `terminal-ui-write.sh` exists on PATH or at
`~/.claude/scripts/terminal-ui-write.sh`. Skip silently if not installed.

### 3. Canon commands — add state writes to `/develop` and `/ralph-cycle`

Add state file write instructions to `canon/commands/develop.md` and
`canon/commands/ralph-cycle.md` at phase transitions:

- `/develop` step 1 (verify scaffold): `phase=scaffold status=running`
- `/develop` step 2 (implement): `phase=develop status=running`
- `/develop` step 3 (test): `phase=test status=running`
- `/develop` step 5 (QA): `phase=qa status=running`
- `/ralph-cycle` step 1 (execute): `log.info="Iteration $N: executing..."`
- `/ralph-cycle` step 4 (SHIP): `status=idle log.info="SHIP"`

These are instructions in the command markdown — the agent runs the
`terminal-ui-write.sh` commands via Bash. If the script isn't available,
the agent skips the state writes (graceful degradation per Plan 4).

### 4. `/canon-start` — verify it references Plans 2-3 correctly

Ensure `canon/commands/canon-start.md` (Plan 4) correctly references:
- `terminal-session.sh --name canon --state .canon/state.json`
- `terminal-ui-write.sh .canon/state.json phase=... status=...`
- Correct paths after global install (`~/.claude/scripts/`)

This is a verification step — Plan 4 should already have these references.
Fix any path mismatches.

### 5. `/apply-canon` — add `/canon-start` to install list

Add `canon/commands/canon-start.md` to the canon install command so it gets
copied to `.claude/commands/canon-start.md` in target projects.

## Files to touch

| File | Change |
|------|--------|
| `commands/apply-core.md` | Add terminal-ui, terminal-session.sh, terminal-ui-write.sh to file list and install steps |
| `scripts/ralph-loop.sh` | Add terminal-ui state writes at lifecycle events (guarded) |
| `canon/commands/develop.md` | Add state file write instructions at phase transitions |
| `canon/commands/ralph-cycle.md` | Add state file write instructions at iteration events |
| `canon/commands/canon-start.md` | Verify path references are correct post-install |
| `commands/canon-init.md` | Add `canon-start.md` to the fetched commands list |

## Risks and open questions

- **P1:** Should Ralph Loop state be in `.terminal-ui-state.json` (exec-plan dir)
  or reuse `.ralph-state.json`? → Separate file. `.ralph-state.json` has its own
  schema for stagnation detection and budget tracking. The terminal-ui state file
  is the blackboard for visual display — different purpose, different schema.
  Ralph Loop writes to both.
- **P2:** `pnpm install` in `/apply-core` adds a Node.js dependency to Core.
  → Terminal UI is opt-in (separate component in the install menu). Users who
  don't want Node.js skip it. The rest of Core works without it.
- **P2:** Should we build `terminal-ui` before copying (so `dist/` exists)?
  → Yes. Add `pnpm run build` after `pnpm install` in the apply-core install step.

## Progress log

- [x] Update `commands/apply-core.md` — add Terminal UI component to file list and install steps
- [x] Update `scripts/ralph-loop.sh` — add guarded terminal-ui state writes
- [x] Update `canon/commands/develop.md` — add state write instructions
- [x] Update `canon/commands/ralph-cycle.md` — add state write instructions
- [x] Verify `canon/commands/canon-start.md` path references
- [x] Update `commands/canon-init.md` — add `canon-start.md` to fetched commands
- [x] End-to-end test: run `/canon-start` in a test project, verify tmux + dashboard + state updates

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Separate `.terminal-ui-state.json` for Ralph Loop | Reuse `.ralph-state.json` | Different schema, different purpose. Ralph state tracks iteration mechanics (stagnation, budget). Terminal UI state tracks visual display (phase, logs, metrics). Writing to both is cheap. |
| Guard state writes with file existence check | Hard dependency on terminal-ui-write.sh | Graceful degradation. Ralph Loop and Canon commands work without the dashboard. State writes are an enhancement. |
| Terminal UI as opt-in `/apply-core` component | Always install, separate install command | Fits the existing component menu pattern. No new install command needed. Users who don't want Node.js skip it. |
| `pnpm install && pnpm run build` in apply-core | Ship pre-built dist/ in repo | dist/ is a build artifact — doesn't belong in the repo. Building on install ensures the user's Node.js version is compatible. |

## Completion criteria

- [x] `/apply-core` installs terminal-ui, terminal-session.sh, terminal-ui-write.sh when selected
- [x] Ralph Loop writes terminal-ui state at lifecycle events (or skips silently if not installed)
- [x] `/develop` and `/ralph-cycle` include state write instructions
- [x] `/canon-start` references correct global paths
- [x] `/canon-init` installs `canon-start.md` to target project
