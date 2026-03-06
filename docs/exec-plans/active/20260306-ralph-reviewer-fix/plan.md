# Plan: Fix Ralph Loop Reviewer Not Writing review-result.txt

**Status:** In progress
**Created:** 2026-03-06

## Problem Statement

The ralph loop for `20260306-post-demo-cleanup` completed all work in iteration 1
(all checkboxes checked, all completion criteria met) but the loop never exited
with SHIP. Instead it ran 3 iterations and exited as stagnated/exhausted.

**Root cause:** The reviewer agent never wrote `review-result.txt`. The loop
treats a missing file as REVISE (line 248 of ralph-loop.sh), which sent the
worker back with nothing to do, triggering stagnation detection.

**Evidence from the failed run:**
- `.ralph-state.json`: `last_result: null`, `stagnation_count: 2`
- `iterations/001/`: contains `work-summary.txt` and `context-handoff.txt` but
  no `review-result.txt` or `review-feedback.txt`
- `iterations/002/`: contains only `work-summary.txt` — reviewer still not writing

## Requirements

- Reviewer agent reliably writes `review-result.txt` on every invocation
- Root cause identified: is this a prompt issue, a tool permission issue, or
  a claude -p execution issue?
- Ralph loop has a fallback if the reviewer fails to write the file
- Regression test: run the loop on a plan where all criteria are already met
  and confirm it SHIPs in iteration 1

## Approach

Three-pronged investigation, then fixes:

### Investigation

1. **Prompt analysis** — The reviewer prompt at `scripts/ralph-reviewer-prompt.md`
   tells the agent to write `{TASK_DIR}/review-result.txt`. The `{TASK_DIR}`
   placeholder is substituted by ralph-loop.sh line 241:
   ```bash
   REVIEWER_CONTEXT=$(sed "s|{TASK_DIR}|${TASK_DIR}|g" "${REVIEWER_PROMPT}")
   ```
   This produces a relative path like `docs/exec-plans/active/20260306-post-demo-cleanup/review-result.txt`.
   The reviewer runs via `claude -p` which should have Write tool access. But:
   - Does `--dangerously-skip-permissions` apply to `-p` mode?
   - Is the reviewer's context window too large for it to follow instructions?
   - Does the reviewer see `git diff HEAD` as empty (worker already committed)?

2. **Git diff timing** — The reviewer prompt says to read `git diff HEAD`.
   But ralph-loop.sh doesn't commit the worker's changes before running the
   reviewer. If the worker used Write/Edit tools, changes ARE on disk but may
   or may not show in `git diff HEAD` depending on whether the worker staged them.
   However — the cleanup plan's worker checked boxes in plan.md and edited
   QUALITY.md. These should show in `git diff HEAD` since they're unstaged.

3. **Reproduce locally** — Run the reviewer prompt manually against the
   completed plan to see what it actually does. Capture its output.

### Fixes

1. **Prompt hardening** — Make the write instruction more prominent. Add a
   mandatory first action: "Before doing anything else, create the output file."
   Move the file write instruction from step 3 to step 1.

2. **Fallback in ralph-loop.sh** — If `review-result.txt` is missing after
   the reviewer runs, check if all completion criteria checkboxes are checked
   in plan.md. If yes, treat as SHIP with a warning. This prevents infinite
   loops when the reviewer fails but the work is done.

3. **Reviewer validation** — After `claude -p` returns, check if the file
   exists. If not, log a specific error and retry the reviewer once before
   falling back to REVISE.

## Files to touch

| File | Change |
|------|--------|
| `scripts/ralph-reviewer-prompt.md` | Restructure: file write as first action, explicit path, redundant instruction |
| `scripts/ralph-loop.sh` | Add reviewer retry on missing file, add checkbox-based fallback |

## Risks and open questions

- **Q: Is `-p` mode limiting the reviewer's tool access?**
  Need to test. If `claude -p` with `--dangerously-skip-permissions` doesn't
  have Write tool access, the reviewer literally cannot create the file.

- **Q: Is the reviewer running out of context?**
  The prompt + plan + work-summary + git diff might be large. If the reviewer
  truncates or fails silently, no file gets written.

- **Q: Should the reviewer use Bash `echo > file` instead of Write tool?**
  More reliable for a single-line file, but goes against the tool preference
  conventions. Could be a pragmatic exception.

## Progress log

- [ ] Reproduce: run reviewer prompt manually against completed cleanup plan, capture behavior
- [ ] Check if `claude -p --dangerously-skip-permissions` has Write tool access
- [ ] Identify which of the three causes (prompt, permissions, context) is the actual failure
- [ ] Fix reviewer prompt — make file write the first and most prominent instruction
- [ ] Add reviewer retry logic to ralph-loop.sh (retry once on missing file)
- [ ] Add checkbox-based fallback to ralph-loop.sh (if all criteria checked and reviewer fails, treat as SHIP with warning)
- [ ] Test: run ralph loop on a trivial already-complete plan, confirm SHIP in iteration 1

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| (Pending) Fix approach | Prompt-only vs loop-level fallback vs both | Need reproduction results first |

## Completion criteria

- [ ] Root cause identified with evidence (not speculation)
- [ ] Reviewer writes `review-result.txt` on a clean test run
- [ ] Ralph loop on an already-complete plan exits SHIP in iteration 1
- [ ] Fallback exists in ralph-loop.sh so a missing file doesn't cause infinite loops
