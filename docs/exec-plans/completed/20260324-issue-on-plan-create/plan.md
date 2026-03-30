# Plan: Create GitHub Issue when plan is written, not when orch starts

**Status:** In progress
**Created:** 2026-03-24

## Requirements

- GitHub Issue is created as soon as a plan.md is committed to `docs/exec-plans/active/<slug>/`
- Issue exists before the orchestrator runs, so the issue number is available for branch naming and tracking
- `plan-meta.json` is written alongside `plan.md` at creation time
- `orch-run.sh` skips issue creation when `plan-meta.json` already exists (current behavior — no change needed there)
- Works from: `/plan` command, `planner-loop.sh --create-plans`, and `plan-upload.sh`

## Approach

Extract the issue-creation logic from `orch-run.sh` (lines 156-199) into a standalone script `scripts/plan-issue.sh`. This script:

1. Takes a slug as argument
2. Reads `plan.md` from `docs/exec-plans/active/<slug>/`
3. Calls `plan-create.sh` to create the GH Issue
4. Writes `plan-meta.json` next to `plan.md`
5. Is idempotent — if `plan-meta.json` exists, prints the issue number and exits

Then call `plan-issue.sh` from:
- `planner-loop.sh` after the PLAN phase (before COMMIT)
- `plan-upload.sh` after committing each plan
- `/plan` command can call it too (but that's a command file edit, lower priority)

`orch-run.sh` stays unchanged — it already checks for `plan-meta.json` and skips creation if present.

## Files to touch

| File | Change |
|------|--------|
| `scripts/plan-issue.sh` | New — standalone issue creation for any plan |
| `scripts/planner-loop.sh` | Call `plan-issue.sh` after PLAN phase in `--create-plans` mode |
| `scripts/plan-upload.sh` | Call `plan-issue.sh` for each uploaded plan |

## Risks and open questions

- None. The logic already exists in `orch-run.sh` — this extracts and reuses it.

## Questions for reviewer

No blocking questions.

## Progress log

- [x] Extract issue creation from `orch-run.sh` into `scripts/plan-issue.sh` (idempotent, reads plan.md, writes plan-meta.json)
- [x] Call `plan-issue.sh` from `planner-loop.sh` after PLAN phase when `github.sync` is enabled (deps: 1)
- [x] Call `plan-issue.sh` from `plan-upload.sh` after committing each plan (deps: 1)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Standalone script | Hook on git commit, modify plan-create.sh | Script is explicit and callable from multiple places. Hook would fire on every commit, not just plan commits. |
| Keep orch-run.sh unchanged | Remove issue creation from orch-run.sh | Backward compat — orch-run.sh still handles plans that don't have plan-meta.json (manual plans, old plans) |

## Completion criteria

- [x] `shellcheck -e SC1091 -S warning scripts/plan-issue.sh` passes
- [x] `shfmt -d scripts/plan-issue.sh` passes
- [x] Running `bash scripts/plan-issue.sh <slug>` on a plan without plan-meta.json creates the issue
- [x] Running it again on the same plan prints the existing issue number without creating a duplicate
