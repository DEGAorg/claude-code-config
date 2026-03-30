# Orchestrator: Tmux Rebuild Discussion

Date: 2026-03-10

## Problem

Commit `c899188` replaced the tmux-based orchestrator with Claude Agent Teams
(`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`). This couples the orchestrator to a
non-standard, experimental Claude feature — violating the agnostic principle.

The orchestrator must support parallel execution of plan items, and the
requirement is firm (not optional).

## What the last commit did

Deleted 9 tmux scripts (~800 lines) and replaced them with:
- `orch-run.sh` — Agent Teams launcher
- `agents/orch-lead.md` — uses TeamCreate (Claude-specific)
- `agents/orch-worker.md` — worker prompt

Kept (and these are clean):
- `orch-state.sh` — 100 lines, pure bash + jq, portable
- `orch-parse-items.sh` — plan parser, portable
- `orch-review.sh` — review integration

## Decision: don't revert, rebuild execution engine

The state layer improvements from `c899188` are worth keeping. The old tmux
scripts were 800+ lines of bloated bash. Instead of reverting to messy code:

- Keep the clean state layer (`orch-state.sh`, `orch-parse-items.sh`)
- Replace the Agent Teams execution engine with tmux-based spawning
- Write it fresh against the clean state API

## Architecture

**Execution is tmux (portable). Display is pluggable (optional, platform-specific).**

### Core (portable)

| Script | Purpose |
|---|---|
| `orch-run.sh` | Launcher: parse plan, init state, create tmux session, wave-based spawning |
| `orch-state.sh` | State library: state.json, done-files, status transitions (keep as-is) |
| `orch-parse-items.sh` | Plan parser (keep as-is) |
| `orch-review.sh` | Review integration (keep) |
| `agents/orch-worker.md` | Worker prompt (remove TeamCreate refs) |

### Display (optional)

| Script | Purpose |
|---|---|
| `orch-display.sh` | Opens terminal windows attached read-only to tmux panes |

macOS: `open -a Terminal` or iTerm2 AppleScript.
WSL: `wt.exe -w 0 new-tab wsl.exe -d Ubuntu -- tmux attach ...` (fragile, best-effort).

Closing a display window does NOT kill the worker — tmux is the real host.

### Execution flow

1. `orch-run.sh` creates tmux session, reads state for incomplete items
2. For each wave: spawn `claude -p` in tmux panes (one per item, up to max-workers)
3. Poll for done-files, update state.json on completion
4. When wave completes, promote newly unblocked items, start next wave
5. Dashboard shows progress (existing terminal-ui or simple status pane)
6. `orch-display.sh` (optional) opens terminal windows attached read-only

### What gets deleted

- `agents/orch-lead.md` — the bash script IS the lead now, no agent needed
- Agent Teams references in `orch-run.sh`
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var usage

## Tasks (draft, not yet an exec-plan)

1. Rewrite `orch-run.sh` — tmux session + wave-based pane spawning
2. Update `agents/orch-worker.md` — remove TeamCreate/Agent Teams references
3. Delete `agents/orch-lead.md`
4. Add `orch-display.sh` — optional terminal window opener (macOS first, WSL stretch)
5. Smoke test end-to-end with the existing `20260309-orch-smoke-test` plan
6. Update `apply-core.md` install manifest

## Decisions (from discussion)

1. **Ralph Loop integration** — The orchestrator should reuse Ralph Loop patterns
   where possible. Ralph Loop drives worker/reviewer convergence well. Not
   mandatory to call it directly, but reuse the mechanics that work (iteration
   tracking, review gating, state files). Goal: one system, not two competing ones.

2. **Worker isolation** — A single plan runs in a single worktree. Dependencies
   prevent workers from stepping on each other. Worktrees are for background
   execution (multiple plans), not for isolating workers within one plan.

3. **`.orchestrator/` is runtime state** — Add to `.gitignore`. Not committed.

4. **`orch-display.sh` is deferred but designed for** — The first plan must
   account for display hooks in the architecture (how workers expose their
   tmux panes, naming conventions, attach points). The actual `orch-display.sh`
   implementation is a separate follow-up plan.

## Resolved questions

- **Dashboard**: Reuse `scripts/terminal-ui/` (Ink). Extend to show orchestrator
  state: worker panes, wave progress, item status from state.json. Must stay
  fully updated with fresh data on each poll cycle.
- **Polling interval**: 30 seconds. Configurable in `ralph.yaml`.
