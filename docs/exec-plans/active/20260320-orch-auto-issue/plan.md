# Plan: Orchestrator auto-creates GitHub Issue for local plans

**Status:** In progress
**Created:** 2026-03-20

## Requirements

- When `github.sync: true` in `dega-core.yaml`, `orch-run.sh` auto-creates a GitHub Issue for any local plan that doesn't already have a linked issue
- The issue is created before workers start, so lifecycle hooks have an `issue_number` from the beginning
- `plan-meta.json` is written to `.orchestrator/plans/<slug>/` with the issue number
- Labels update through the full lifecycle: `plan:draft` at creation, `plan:active` at start, `plan:review`/`plan:completed`/`plan:failed` at milestones
- If `github.sync` is false or missing, behavior is unchanged (local-only, no issue)
- If `gh` is not authenticated, log a warning and continue without sync (don't block execution)

## Approach

In `orch-run.sh`, after resolving the plan but before initializing state:

1. Read `dega-core.yaml` for `github.sync`
2. If sync enabled and no `plan-meta.json` exists for this slug:
   a. Extract plan title from `plan.md` (first `# Plan: ...` line)
   b. Call `plan-create.sh --title "..." --body-file plan.md`
   c. Write `plan-meta.json` with the returned issue number
3. Copy `plan-meta.json` into the worktree so lifecycle hooks can find it

The lifecycle hooks (`01-gh-plan-sync.sh`) already handle all the label/comment logic — they just need `plan-meta.json` to exist.

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-run.sh` | Add auto-issue creation block after plan resolution, before state init |
| `scripts/gh-plan-sync.sh` | Fix: look for plan-meta.json in both `.orchestrator/plans/<slug>/` and the worktree plan dir |

## Progress log

- [x] Add auto-issue creation to `scripts/orch-run.sh` — read dega-core.yaml, create issue via plan-create.sh if sync enabled and no meta exists, write plan-meta.json
- [x] Fix `scripts/gh-plan-sync.sh` to search both `.orchestrator/plans/<slug>/` and worktree for plan-meta.json (deps: 1)
- [x] Test: run orchestrator on a local plan with `github.sync: true`, verify issue created, labels updated through lifecycle, issue closed on SHIP (deps: 1, 2)

## Completion criteria

- [ ] Running `orch-run.sh <slug>` with `github.sync: true` creates a GitHub Issue automatically
- [ ] Issue gets `plan:draft` label at creation, `plan:active` at start
- [ ] SHIP updates label to `plan:completed`, posts summary comment, closes issue
- [ ] Without `github.sync`, no issue is created (backward compatible)
- [ ] If `gh` auth fails, orchestrator continues without sync (warning only)
- [ ] shellcheck and shfmt clean
