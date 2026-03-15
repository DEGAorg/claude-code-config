# Plan: Orch progress resilience on failure

**Status:** In progress
**Created:** 2026-03-15

## Requirements

- When a worker item is accepted (done-file synced), its changes are committed in the worktree immediately
- On failure/kill, the worktree is NOT deleted — it preserves committed progress
- On re-run of the same plan, the existing worktree and state are detected and resumed
- Items already marked "done" in state.json are skipped on resume
- On SHIP, all per-item commits are merged to main as before
- On REVISE, worker windows are killed but worktree and state persist for the re-exec

## Approach

### 1. Per-item commits in orch_sync_done_files

In `orch-state.sh`, after accepting a done-file and marking an item "done", commit the worktree changes:

```bash
git -C "${worktree_dir}" add -A
git -C "${worktree_dir}" commit -m "orch: item ${item_id} — ${description}"
```

This saves progress incrementally. Each completed item = one commit in the worktree branch.

### 2. Keep worktree on failure

In `orch_cleanup_worktree`, only clean up when called explicitly from the SHIP path. Currently it's called on SHIP and on unexpected review results. Remove the call from the error/unexpected path. The worktree persists with its commits.

Also: `orch-engine.sh` error path currently calls `orch_cleanup_worktree` — remove that call.

### 3. Resume from existing state in orch-run.sh

In `orch-run.sh`, when `ORCH_STATE_FILE` already exists AND the plan slug matches:
- Don't re-initialize state (skip `init_state`)
- Don't create a new worktree (skip if exists)
- Just start the engine with the existing state

Currently: if state exists and slug matches, it skips `init_state` (line 147-154). But worktree creation always runs. Fix: `orch_create_worktree` already handles "worktree already exists" (returns 0). So resume already partially works. The missing piece is that `init_state` gets called when it shouldn't.

Actually, looking at the code, resume already works for the engine — if state.json exists with the right slug, `init_state` is skipped, and done items stay done. The gap is only:
- Worktree gets deleted on failure (fix: don't delete)
- No per-item commits (fix: commit on sync)

### 4. Don't nuke state on re-run

Currently `orch-run.sh` only calls `init_state` when the state file doesn't exist or has a different slug. This is already correct for resume. No change needed.

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-state.sh` | Add per-item commit in `orch_sync_done_files`, remove worktree cleanup from error paths |
| `scripts/orch-engine.sh` | Remove `orch_cleanup_worktree` from error/unexpected path |

## Risks and open questions

- **P2:** Per-item commits mean many small commits on the worktree branch. On merge, these all get squashed into one merge commit. This is fine — the individual commits are only for resilience, not for history.

## Progress log

- [ ] Add per-item commit to `orch_sync_done_files` in orch-state.sh — commit worktree after accepting each done-file
- [ ] Remove `orch_cleanup_worktree` from error path in orch-engine.sh — keep worktree on failure
- [ ] Verify resume works: re-running a failed plan skips done items and reuses existing worktree

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Per-item commits | Single commit on SHIP | Per-item commits survive crashes. Single commit loses everything if the run dies. |
| Keep worktree on failure | Auto-cleanup with backup | Simpler — worktree IS the backup. User can inspect it, re-run resumes from it. |
| Reuse existing state.json | Fresh state every time | Already-done items shouldn't be re-run. State is the source of truth. |

## Completion criteria

- [ ] Worktree has one commit per completed item
- [ ] Killing an orch run preserves worktree and state
- [ ] Re-running the same plan resumes from where it left off
- [ ] `shellcheck scripts/orch-state.sh scripts/orch-engine.sh` clean
