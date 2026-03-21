# Plan: Orchestrator creates PR on SHIP with linked branch

**Status:** In progress
**Created:** 2026-03-20

## Requirements

- When a plan SHIPs, the orchestrator creates a Pull Request from the worktree branch to the target branch (main or develop)
- The PR links to the GitHub Issue (if one exists) via `Closes #N` in the body
- The PR body includes a summary: items completed, iterations, elapsed time
- The worktree branch is preserved (not deleted) until the PR is merged
- The PR is tagged with the plan slug for traceability
- Target branch is configurable in `dega-core.yaml` (`github.pr_target`, defaults to `main`)
- If PR creation fails (permissions, branch conflicts), log warning and continue — don't block SHIP

## Approach

Add a `create_ship_pr` step to the SHIP handling in `orch-engine.sh`:

1. After merging worktree to current branch, push the branch
2. Create PR via `gh pr create` with:
   - Title: `plan: <slug>` (or plan title from plan.md)
   - Body: SHIP summary + `Closes #N` if issue exists
   - Base: `github.pr_target` from `dega-core.yaml` (default: `main`)
   - Head: the worktree branch (`orch/<slug>`)
3. Post the PR URL as a comment on the linked issue

Also update `gh-plan-sync.sh` to handle a new `pr` event that posts the PR link.

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-engine.sh` | Add PR creation step in SHIP handling, after merge |
| `scripts/gh-plan-sync.sh` | Add `pr` event handler that posts PR URL to the linked issue |
| `dega-core.yaml` | Add `github.pr_target` config option |

## Progress log

- [x] Add `github.pr_target` to `dega-core.yaml` (default: `main`)
- [x] Add PR creation to `scripts/orch-engine.sh` SHIP handling — push branch, create PR via `gh pr create`, include SHIP summary and `Closes #N` (deps: 1)
- [ ] Update `scripts/gh-plan-sync.sh` — add `pr` event that posts PR URL as comment on linked issue (deps: 2)
- [ ] Test: run a plan through SHIP, verify PR is created targeting the configured branch, issue gets PR link comment (deps: 2, 3)

## Completion criteria

- [ ] SHIP creates a PR from the worktree branch to the target branch
- [ ] PR body includes SHIP summary and `Closes #N` reference
- [ ] PR URL is posted as a comment on the linked issue
- [ ] `github.pr_target` in `dega-core.yaml` controls the base branch
- [ ] PR creation failure logs warning but doesn't block SHIP
- [ ] shellcheck and shfmt clean
