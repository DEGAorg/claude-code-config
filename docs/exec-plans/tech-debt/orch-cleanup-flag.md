# Orch: no cleanup for orphaned state after crashes

**Discovered:** 2026-03-14
**Severity:** Medium

## Problem

If the orchestrator crashes (engine killed, tmux session dies, machine reboots),
orphaned artifacts persist with no cleanup mechanism:

- `.orchestrator/worktrees/<slug>/` — git worktree left on disk
- `.orchestrator/master.json` — stale plan entry with no live tmux session
- `orch/<slug>` git branch — dangling branch from the worktree

Users must manually `git worktree remove`, edit `master.json`, and delete branches.

## Proposed fix

Add `orch-run.sh --cleanup [slug]` that:

1. Lists all entries in `master.json`
2. Checks if the corresponding tmux session (`orch-<slug>`) is alive
3. For dead sessions: remove worktree, delete branch, deregister from master.json
4. Without `slug` arg: clean all dead entries. With `slug`: clean that one.

Also consider: on `orch-run.sh` startup, auto-clean stale entries from `master.json`
before registering the new plan.

## Files involved

| File | Role |
|------|------|
| `scripts/orch-run.sh` | Add `--cleanup` flag |
| `scripts/orch-state.sh` | Add `orch_cleanup_stale_entries()` |
