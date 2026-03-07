# Plan: Parallel Ralph Loops via Worktrees

**Status:** In progress
**Created:** 2026-03-06

## Requirements

- Multiple ralph loops can run simultaneously on different exec plans
- Each loop runs in its own git worktree (isolated working directory)
- No tmux session name conflicts between parallel loops
- Worktree lifecycle: create on loop start, cleanup on loop exit (or keep if changes exist)
- State files remain per-task-slug so parallel loops don't clobber each other

## Discovery Answers

1. **Branch strategy:** One branch per worktree, named `ralph/<slug>` (e.g.
   `ralph/20260306-docs-update`). Industry standard for parallel AI-agent
   development. Each branch merges back via PR after the loop SHIPs.

2. **Worktree location:** Use `.claude/worktrees/` — same directory Claude Code
   already uses for its own worktrees. No reason to diverge.

3. **Claude Code built-in support:** Use the Agent tool's `isolation: "worktree"`
   parameter when possible. It handles worktree creation and cleanup automatically.
   ralph-loop.sh will manage worktrees directly with `git worktree add` since
   it runs outside Claude sessions (shell script).

4. **Terminal multiplexing:** Simplest implementation for now — one tmux session
   per loop (separate terminals). Future: single orchestrator dashboard that
   aggregates all loop states and lets you drill into each one.

5. **Resource limits:** No cost cap for now. Future task.

## Approach

Worktree lifecycle wrapper around ralph-loop.sh. The loop script itself stays
mostly unchanged — the wrapper creates the worktree, starts the loop inside it,
and cleans up on exit.

### New script: `scripts/ralph-worktree.sh`

```
Usage: ralph-worktree.sh <task-slug>

1. git worktree add .claude/worktrees/<slug> -b ralph/<slug>
   (or reattach if worktree/branch already exists)
2. Copy exec plan directory into worktree
3. Run ralph-loop.sh <slug> inside worktree (cd into worktree first)
4. On exit:
   - If SHIP: report branch name for PR/merge
   - If clean (no changes): remove worktree and branch
   - If changes exist but not SHIP: keep worktree, report location
```

### Changes to ralph-loop.sh

- Accept optional `--workdir` flag to override working directory
- Use `ralph-<slug>` as tmux/session name instead of hardcoded name
- No other changes — state management already works per-slug

### Exec plan access

The plan directory (`docs/exec-plans/active/<slug>/`) is copied into the
worktree so the worker has a local copy. On SHIP, changes are committed to
the `ralph/<slug>` branch. The orchestrator (or user) merges the branch back.

## Files to touch

| File | Change |
|------|--------|
| `scripts/ralph-worktree.sh` | New — worktree lifecycle wrapper |
| `scripts/ralph-loop.sh` | Add `--workdir` flag, slug-based session names |
| `commands/apply-core.md` | Add ralph-worktree.sh to install manifest |

## Risks and open questions

- Git worktree add fails if the branch already exists. Need idempotency
  (reattach to existing worktree if present).
- Cleanup of abandoned worktrees if a loop crashes without cleanup.
  Mitigation: `git worktree prune` on startup.
- Exec plan state (review-result.txt, work-summary.txt) lives in the worktree
  copy. Need to sync final state back to main repo on SHIP.

## Progress log

- [x] Resolve discovery questions
- [ ] Write `scripts/ralph-worktree.sh` — create worktree, run loop, cleanup
- [ ] Update `scripts/ralph-loop.sh` — add `--workdir` flag, slug-based session names
- [ ] Handle exec plan sync: copy into worktree, sync back on SHIP
- [ ] Add idempotency: reattach to existing worktree if branch exists
- [ ] Add cleanup: remove worktree on clean exit, keep on changes
- [ ] Add `git worktree prune` call on startup to clean stale entries
- [ ] Add ralph-worktree.sh to `commands/apply-core.md` install manifest
- [ ] Test: two parallel loops on different plans, verify no conflicts
- [ ] Test: loop crash recovery — verify worktree can be resumed

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Wrapper script, not fork of ralph-loop.sh | Modify ralph-loop.sh directly | Keep ralph-loop.sh simple. Worktree management is orthogonal to iteration logic. |
| Per-worktree branches (`ralph/<slug>`) | Shared branch | Industry standard. Isolates parallel work, merges via PR. No conflicts. |
| `.claude/worktrees/` location | Plan-adjacent directory | Consistent with Claude Code's own worktree location. No fragmentation. |
| One tmux session per loop (for now) | Aggregated dashboard | Simplest implementation. Orchestrator is a future task. |
| `git worktree add` in shell script | Agent tool `isolation: "worktree"` | ralph-loop.sh runs outside Claude sessions. Agent tool only works inside sessions. |

## Completion criteria

- [ ] `scripts/ralph-worktree.sh` exists and creates worktree + branch
- [ ] Two ralph loops can run simultaneously on different exec plans
- [ ] Worktrees are created on start and cleaned up on clean exit
- [ ] No state file conflicts between parallel loops
- [ ] Stale worktrees from crashed loops can be pruned
