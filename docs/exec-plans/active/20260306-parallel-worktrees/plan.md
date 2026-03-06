# Plan: Parallel Ralph Loops via Worktrees

**Status:** In progress
**Created:** 2026-03-06

## Requirements

- Multiple ralph loops can run simultaneously on different exec plans
- Each loop runs in its own git worktree (isolated working directory)
- No tmux session name conflicts between parallel loops
- Worktree lifecycle: create on loop start, cleanup on loop exit (or keep if changes exist)
- State files remain per-task-slug so parallel loops don't clobber each other

## Discovery Questions

These need answers before implementation starts:

1. **Branch strategy for worktrees:** Does each worktree get its own branch
   (e.g. `ralph/20260306-docs-update`), or do they all work on the current
   branch? Own branches are safer (no merge conflicts during parallel work)
   but require a merge/PR step afterward.

2. **Worktree location:** Claude Code already creates worktrees at
   `.claude/worktrees/` (3 exist now: zealous-austin, dreamy-burnell,
   inspiring-wescoff). Should ralph loops use the same directory, or a
   separate `docs/exec-plans/active/<slug>/worktree/` location that ties
   the worktree to its plan?

3. **Claude Code's built-in worktree support:** The Agent tool has an
   `isolation: "worktree"` parameter that auto-creates worktrees. Should
   ralph-loop.sh use this (spawn via Agent tool), or manage worktrees
   directly with `git worktree add`? The Agent tool handles cleanup
   automatically but only works from inside Claude sessions.

4. **Terminal multiplexing:** With N parallel loops, the user needs N
   dashboard panes. Options:
   - One tmux session per loop (separate terminals)
   - One tmux session with 2N panes (crowded but single window)
   - Single orchestrator dashboard that aggregates all loop states
   Which UX do we want?

5. **Resource limits:** Each ralph loop spawns `claude -p` instances.
   Running 3 loops means 3+ concurrent Claude API sessions. Is there an
   API rate limit or cost concern that should cap parallelism?

## Approach

Worktree lifecycle wrapper around ralph-loop.sh. The loop script itself
stays mostly unchanged — the wrapper creates the worktree, starts the
tmux session with a unique name, runs ralph-loop.sh inside the worktree,
and cleans up on exit.

### New script: `scripts/ralph-worktree.sh`

```
Usage: ralph-worktree.sh <task-slug>

1. git worktree add .claude/worktrees/<slug> -b ralph/<slug>
2. Copy exec plan into worktree (or symlink docs/exec-plans/)
3. Launch terminal-session.sh with unique name: ralph-<slug>
4. Run ralph-loop.sh <slug> inside worktree
5. On exit: if changes exist, report branch name; if clean, remove worktree
```

### Changes to ralph-loop.sh

- Accept optional `--workdir` flag to override working directory
- Session name: use `ralph-<slug>` instead of hardcoded name
- No other changes — state management already works per-slug

### Changes to terminal-session.sh

- Already supports `--name` flag — no changes needed
- Dashboard state path needs to point to worktree's state file

## Files to touch

| File | Change |
|------|--------|
| `scripts/ralph-worktree.sh` | New — worktree lifecycle wrapper |
| `scripts/ralph-loop.sh` | Add `--workdir` flag, use slug-based session names |
| `scripts/terminal-session.sh` | Verify state path is configurable (may already work) |

## Risks and open questions

- Exec plans live in `docs/exec-plans/active/` — worktrees need access to
  the plan file. Options: copy into worktree, symlink, or have ralph-loop
  read from the main repo path regardless of workdir.
- Git worktree add fails if the branch already exists. Need idempotency
  (reattach to existing worktree if present).
- Cleanup of abandoned worktrees if a loop crashes without cleanup.

## Progress log

- [ ] Resolve discovery questions (decisions needed before coding)
- [ ] Write `scripts/ralph-worktree.sh` — create worktree, launch session, run loop
- [ ] Update `scripts/ralph-loop.sh` — add `--workdir` flag, slug-based session names
- [ ] Handle exec plan access from worktree (copy, symlink, or main-repo path)
- [ ] Add idempotency: reattach to existing worktree if branch exists
- [ ] Add cleanup: remove worktree on clean exit, keep on changes
- [ ] Add `git worktree prune` call on startup to clean stale entries
- [ ] Test: two parallel loops on different plans, verify no conflicts
- [ ] Test: loop crash recovery — verify worktree can be resumed

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Wrapper script, not fork of ralph-loop.sh | Modify ralph-loop.sh directly | Keep ralph-loop.sh simple. Worktree management is orthogonal to the iteration logic. |
| (Pending) Branch strategy | Shared branch vs per-worktree branches | Needs discovery answer |
| (Pending) Worktree location | .claude/worktrees/ vs plan-adjacent | Needs discovery answer |

## Completion criteria

- [ ] Two ralph loops can run simultaneously on different exec plans
- [ ] Each loop has its own tmux session with dashboard
- [ ] Worktrees are created on start and cleaned up on clean exit
- [ ] No state file conflicts between parallel loops
- [ ] Stale worktrees from crashed loops can be pruned
