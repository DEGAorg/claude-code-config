# Plan: Verify issue body sync works end-to-end

**Status:** In progress
**Created:** 2026-03-20

## Requirements

- Confirm that progress log checkboxes get checked as items complete
- Confirm that Status field updates to Completed on SHIP
- Confirm that completion criteria checkboxes get checked on SHIP

## Approach

Simple 2-item plan that does trivial work. The real test is whether the GitHub Issue body updates correctly through the lifecycle.

## Progress log

- [x] Create a test file at `/tmp/verify-body-sync-step1.txt` with contents "step 1 done"
- [ ] Create a test file at `/tmp/verify-body-sync-step2.txt` with contents "step 2 done" (deps: 1)

## Completion criteria

- [ ] Both test files exist
- [ ] This issue's progress log checkboxes are checked
- [ ] This issue's Status field says Completed
