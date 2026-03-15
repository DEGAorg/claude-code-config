# Plan: Orch worktree plan isolation

**Status:** In progress
**Created:** 2026-03-15

## Requirements

- `orch-run.sh` refuses to launch if plan.md has uncommitted changes (forces clean state)
- plan.md is copied into the worktree after creation so workers edit the worktree copy
- `PLAN_DIR` in orch-engine.sh points to the worktree copy, not the main repo
- On SHIP, the worktree plan.md (with checked boxes) is synced back to the main repo before merge
- Workers never touch main repo files — all edits happen in the worktree

## Approach

### 1. Uncommitted plan guard in orch-run.sh

After validating the plan exists, check `git status` for the plan directory. If any files are modified or untracked, print an error and exit:

```bash
plan_dirty=$(git -C "${REPO_ROOT}" status --porcelain "docs/exec-plans/active/${SLUG}/" 2>/dev/null || true)
if [[ -n "${plan_dirty}" ]]; then
    echo "error: plan has uncommitted changes — commit before running orch" >&2
    exit 1
fi
```

### 2. Copy plan into worktree

In `orch-run.sh`, after `orch_create_worktree`, copy the plan directory into the worktree:

```bash
WORKTREE_PLAN_DIR="${WORKTREE_DIR}/docs/exec-plans/active/${SLUG}"
mkdir -p "${WORKTREE_PLAN_DIR}"
cp -r "${PLAN_DIR}/"* "${WORKTREE_PLAN_DIR}/"
```

The worktree already has the committed version of plan.md (from HEAD). This copy ensures any just-committed state is there.

### 3. Point PLAN_DIR to worktree in orch-engine.sh

Change `PLAN_DIR` from `${REPO_ROOT}/docs/exec-plans/active/${SLUG}` to `${WORKTREE_DIR}/docs/exec-plans/active/${SLUG}`. Workers already `cd` into the worktree — now the plan path is also in the worktree.

### 4. Sync plan.md back on SHIP

In `orch-engine.sh` SHIP path, before merging, copy the worktree plan.md back to the main repo plan dir so checkbox state is preserved:

```bash
cp "${PLAN_DIR}/plan.md" "${REPO_ROOT}/docs/exec-plans/active/${SLUG}/plan.md"
```

This happens before `orch_merge_worktree` which will commit and merge everything.

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-run.sh` | Add uncommitted plan guard, copy plan to worktree |
| `scripts/orch-engine.sh` | Change PLAN_DIR to worktree path, sync plan.md back on SHIP |

## Risks and open questions

- None — the worktree already gets the plan from HEAD since it's a git worktree. The copy is belt-and-suspenders.

## Progress log

- [ ] Add uncommitted plan guard to orch-run.sh
- [ ] Copy plan directory into worktree after creation in orch-run.sh
- [ ] Change PLAN_DIR to worktree path in orch-engine.sh
- [ ] Sync plan.md back to main repo on SHIP path in orch-engine.sh

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Require committed plan | Auto-commit plan on launch | Explicit is better — user should control what's committed |
| Copy plan dir into worktree | Symlink | Copy is simpler, no edge cases with git tracking symlinks |
| Sync back on SHIP only | Sync on every poll | Only the final checkbox state matters; intermediate states are noise |

## Completion criteria

- [ ] `orch-run.sh` rejects plans with uncommitted changes
- [ ] Workers edit worktree copies of all files including plan.md
- [ ] Plan.md checkbox state preserved in main repo after SHIP
- [ ] `shellcheck scripts/orch-run.sh scripts/orch-engine.sh` clean
