# Plan: Fix SHIP flow — don't close issue until PR merges

**Status:** In progress
**Created:** 2026-03-20

## Requirements

- On SHIP, the orchestrator creates a PR but does NOT close the issue
- Issue label changes to `plan:pr-review` (new label, already created)
- Issue body status changes to `**Status:** PR Review`
- The PR body contains `Closes #N` so GitHub auto-closes the issue when the PR merges
- When the issue auto-closes (PR merge), label should be `plan:completed` — this can be handled by a GitHub Action or left manual for now
- `close_on_ship` config option in dega-core.yaml is removed or repurposed — closing is always deferred to PR merge

## Approach

1. In `gh-plan-sync.sh` `handle_ship`: change label to `plan:pr-review` instead of `plan:completed`, set body status to "PR Review", do NOT call `gh issue close`
2. In `update_body_on_ship`: change target status from "Completed" to "PR Review"
3. Add `handle_pr_merged` event handler: sets label to `plan:completed`, updates body status to "Completed" — called when PR merge is detected (future: GitHub webhook or Action; for now: manual or `/sync` command)
4. The `plan:completed` label and "Completed" status happen at PR merge, not at SHIP

## Files to touch

| File | Change |
|------|--------|
| `scripts/gh-plan-sync.sh` | Change `handle_ship` to use `plan:pr-review` label, status "PR Review", remove `gh issue close`. Add `pr_merged` event handler. |
| `hooks/orch-lifecycle/01-gh-plan-sync.sh` | Update ship event handling (label change only, no close) |

## Progress log

- [x] Update `handle_ship` in `scripts/gh-plan-sync.sh` — label `plan:pr-review`, body status "PR Review", remove `gh issue close`
- [x] Update `update_body_on_ship` — rename to `update_body_on_pr` and set status to "PR Review" instead of "Completed" (deps: 1)
- [x] Add `pr_merged` event handler to `scripts/gh-plan-sync.sh` — sets `plan:completed`, body status "Completed", verifies issue is closed (deps: 1)
- [ ] Test: run a plan through SHIP, verify issue stays open with `plan:pr-review` label and "PR Review" status (deps: 1, 2, 3)

## Completion criteria

- [ ] SHIP sets label to `plan:pr-review` (not `plan:completed`)
- [ ] SHIP sets body status to "PR Review" (not "Completed")
- [ ] SHIP does NOT close the issue
- [ ] `pr_merged` event sets `plan:completed` and "Completed"
- [ ] shellcheck and shfmt clean
