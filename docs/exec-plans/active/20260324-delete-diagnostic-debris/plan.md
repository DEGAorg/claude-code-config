# Plan: Delete diagnostic debris and stale worktrees

**Status:** In progress
**Created:** 2026-03-24

## Requirements

- Remove `scripts/dev-test/` directory (test-sound.sh — not a real test, just a manual debugging script)
- Clean up stale `.claude/worktrees/` directories left from old orchestrator runs
- Clean up stale `.orchestrator/worktrees/` directories from completed plans
- No production scripts reference these files

## Approach

Delete the dev-test directory and prune stale worktrees. Verify no references exist before deleting.

## Files to touch

| File | Change |
|------|--------|
| `scripts/dev-test/test-sound.sh` | Delete |
| `scripts/dev-test/` | Delete directory |
| `.claude/worktrees/*/` | Prune stale worktrees via `git worktree prune` |
| `.orchestrator/worktrees/*/` | Remove completed plan worktrees |

## Risks and open questions

- Stale worktrees may have uncommitted work. Check with `git worktree list` before pruning.

## Questions for reviewer

No blocking questions.

## Progress log

- [x] Verify no references to `dev-test/` exist, delete the directory, and prune stale git worktrees

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Delete dev-test/ entirely | Move to tests/ | It's a manual debugging script, not a test. No value keeping it. |
| Prune worktrees | Leave them | Stale worktrees waste disk and clutter `git worktree list` |

## Completion criteria

- [ ] `ls scripts/dev-test/ 2>/dev/null` returns "No such file or directory"
- [ ] `git worktree list` shows only the main worktree (no stale entries)
