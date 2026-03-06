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

**Eliminated causes:**
- Permissions: not the issue — ralph uses `--dangerously-skip-permissions`
- Empty git diff: not the issue — changes exist and the loop has flagged them

**Actual cause:** The write instruction is buried in step 3 of the reviewer
prompt. The agent loses it in the noise of reading the plan, work-summary,
and diff. The prompt alone is not a reliable enforcement mechanism.

## Requirements

- Reviewer agent reliably writes `review-result.txt` on every invocation
- Enforcement via Claude hook, not just prompt instructions
- Ralph loop has a fallback if the reviewer still fails to write the file
- Regression test: run the loop on a plan where all criteria are already met
  and confirm it SHIPs in iteration 1

## Approach

### Fix 1: Stop hook — enforce review-result.txt before reviewer exit

Add a Stop hook that fires when the reviewer agent tries to exit. The hook
checks if `review-result.txt` exists in the task directory. If not, it blocks
the exit and tells the agent to write the file.

The hook activates only during ralph loop reviewer sessions. Detection: the
reviewer prompt sets an env var (e.g. `RALPH_ROLE=reviewer`) and the hook
checks for it.

**New file: `hooks/ralph-reviewer-stop.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Only active for reviewer sessions
[[ "${RALPH_ROLE:-}" == "reviewer" ]] || exit 0

TASK_DIR="${RALPH_TASK_DIR:-}"
[[ -n "${TASK_DIR}" ]] || exit 0

RESULT_FILE="${TASK_DIR}/review-result.txt"
if [[ ! -f "${RESULT_FILE}" ]]; then
  echo "STOP BLOCKED: You must write ${RESULT_FILE} before exiting."
  echo "First line must be exactly: SHIP, REVISE, or BLOCKED."
  exit 2
fi
```

The hook uses exit code 2 to block the stop. The agent gets the message
and is forced to write the file before it can exit.

### Fix 2: Pass env vars from ralph-loop.sh to reviewer

Update the reviewer invocation in ralph-loop.sh to set `RALPH_ROLE=reviewer`
and `RALPH_TASK_DIR` so the Stop hook can detect reviewer sessions:

```bash
RALPH_ROLE=reviewer RALPH_TASK_DIR="${TASK_DIR}" \
  env -u CLAUDECODE RALPH_LOOP=1 claude -p --dangerously-skip-permissions "${REVIEWER_CONTEXT}"
```

Also set `RALPH_ROLE=worker` for the worker invocation (no stop hook needed
for workers, but consistent labeling).

### Fix 3: Fallback in ralph-loop.sh

If `review-result.txt` is still missing after the reviewer exits (hook
failed, agent crashed, etc.), check plan.md checkboxes as a last resort:
- All completion criteria checked → treat as SHIP with a warning log
- Otherwise → REVISE as before

This prevents infinite stagnation loops.

### Fix 4: Prompt adjustment (minor)

Move the file write instruction higher in the reviewer prompt — from step 3
to a prominent callout at the top. Belt and suspenders with the hook.

## Files to touch

| File | Change |
|------|--------|
| `hooks/ralph-reviewer-stop.sh` | New — Stop hook that blocks reviewer exit if review-result.txt missing |
| `settings.json` | Add ralph-reviewer-stop.sh to Stop hooks |
| `scripts/ralph-loop.sh` | Pass `RALPH_ROLE` and `RALPH_TASK_DIR` env vars to reviewer; add checkbox fallback |
| `scripts/ralph-reviewer-prompt.md` | Move file write instruction to top-level callout |
| `commands/apply-core.md` | Add hook to install manifest |

## Risks and open questions

- **Q: Does the Stop hook receive env vars from the parent process?**
  `claude -p` is spawned by ralph-loop.sh which sets the env vars. The hook
  runs inside that Claude session, so it should inherit them. Need to verify.

- **Q: Can the Stop hook block exit in `-p` mode?**
  In interactive mode, exit code 2 blocks the stop. Need to confirm this
  also works for `claude -p` sessions (prompt mode may behave differently).

## Progress log

- [x] Write `hooks/ralph-reviewer-stop.sh` — Stop hook enforcing review-result.txt
- [x] Add hook to `settings.json` Stop hooks array
- [x] Update `scripts/ralph-loop.sh` — pass RALPH_ROLE and RALPH_TASK_DIR env vars to reviewer and worker
- [x] Update `scripts/ralph-reviewer-prompt.md` — move write instruction to prominent top callout
- [x] Add checkbox-based fallback to ralph-loop.sh (all criteria checked + no file → SHIP with warning)
- [x] Add hook to `commands/apply-core.md` install manifest
- [x] Test: verify Stop hook blocks exit when review-result.txt missing
- [ ] Test: run ralph loop on a trivial already-complete plan, confirm SHIP in iteration 1

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Stop hook as primary enforcement | Prompt-only, retry logic, bash echo fallback | Hooks are structural — they fire regardless of what the agent decides to do. Prompts are suggestions the agent can ignore. |
| Checkbox fallback as safety net | No fallback (rely on hook only) | Defense in depth. If the hook fails (env var missing, -p mode edge case), the loop still exits instead of stagnating. |
| Env var detection for hook scope | Always-on hook, file-based flag | Env vars are clean — no temp files to manage, no stale state. The hook is a no-op outside ralph sessions. |

## Completion criteria

- [x] `hooks/ralph-reviewer-stop.sh` exists and is wired in settings.json
- [ ] Reviewer writes `review-result.txt` on a test run
- [ ] Ralph loop on an already-complete plan exits SHIP in iteration 1
- [x] Fallback exists in ralph-loop.sh so a missing file can't cause infinite loops
