# Plan: Ralph S2 — Enforcement

**Status:** In progress
**Created:** 2026-02-25
**Sequence:** Step 2 of 4 — requires S1 complete (state file must exist)

## Context

S1 gives the agent a per-item loop with a state file. But nothing yet prevents the
agent from: ignoring `task-complete.sh`, running destructive commands, or pushing
code mid-loop. Prompt instructions for these constraints are forgotten in large
contexts. This step adds hook-level enforcement — below the LLM, unchallengeable.

## Requirements

- `scripts/task-complete.sh` is the only way to advance `current_task` in state;
  it validates evidence before transitioning
- `scripts/ralph-check.sh` blocks Stop if files changed but task not claimed complete
- `hooks/enforce-loop-mode.sh` blocks commands at two levels:
  - **Level 1 (hard stop):** `rm -rf`, `git reset --hard`, `git push --force` →
    exit 2, terse message, no recovery path
  - **Level 2 (soft block):** `git push`, `git commit` when `RALPH_MODE=local-only`
    → exit 2, constructive message explaining why and what to do instead
- `settings.json` wires `hooks/enforce-loop-mode.sh` as the PreToolUse/Bash handler;
  removes the two equivalent inline hook entries

## Approach

### task-complete.sh

The agent calls this when it believes the current item is done:

```bash
#!/usr/bin/env bash
# Signal that current_task is complete. Advances state to next item.
# Usage: bash scripts/task-complete.sh <state-file>
# Called by the worker agent. Validated by PreToolUse hook before running.
```

The script:
1. Reads `current_task.text` from state
2. Sets `current_task.claimed_complete = true`
3. Calls `scripts/plan-advance.sh` to write the next item into `current_task`
4. Prints confirmation: `✓ task complete: <text> → next: <next text or "all done">`

### PreToolUse validation of task-complete.sh

`hooks/enforce-loop-mode.sh` already fires on every Bash PreToolUse. It intercepts
calls where the command contains `task-complete.sh` and validates:

- `git diff HEAD --name-only | wc -l` > 0 — at least one file changed since the
  last state transition (evidence of work)
- If check fails: exit 2 with `"BLOCKED: no file changes detected — complete actual
  work before calling task-complete.sh"`

This is the evidence gate. It's weak (any file change passes) but meaningful: the
agent cannot claim completion without having touched at least one file.

### Stop hook (ralph-check.sh)

Add one check after existing checks:

```bash
STATE_FILE=$(find docs/exec-plans/active -name '.ralph-state.json' 2>/dev/null | head -1)
if [[ -n "$STATE_FILE" ]]; then
  CLAIMED=$(jq -r '.current_task.claimed_complete // true' "$STATE_FILE")
  CHANGES=$(git diff HEAD --name-only 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$CHANGES" -gt 0 && "$CLAIMED" == "false" ]]; then
    echo "FAIL: files changed but current task not marked complete"
    echo "  run: bash scripts/task-complete.sh $STATE_FILE"
    exit 1
  fi
fi
```

The agent cannot stop if it has done work without signaling. This makes calling
`task-complete.sh` structurally mandatory — not a prompt suggestion.

### enforce-loop-mode.sh

```bash
#!/usr/bin/env bash
# PreToolUse/Bash hook. Two-level command enforcement.
# Level 1: hard stop — destructive commands, always blocked.
# Level 2: soft block — mode-restricted commands, blocked with recovery guidance.
# Mode read from RALPH_MODE env (set by ralph-loop.sh). Default: "full" (nothing blocked).
```

Level 1 patterns (always blocked regardless of mode):
- `rm -rf`, `rm -fr`
- `git reset --hard`
- `git push --force`, `git push -f`

Level 2 patterns (blocked when `RALPH_MODE=local-only`):
- `git push` (without --force — already caught above)
- `git commit` — blocked in loop; agent should call `task-complete.sh` instead

Level 2 message for `git commit`:
```
BLOCKED [local-only]: git commit is not allowed inside a ralph loop.
The orchestrator commits after SHIP. Focus on the current task.
```

Level 2 message for `git push`:
```
BLOCKED [local-only]: git push is not allowed inside a ralph loop.
Changes stay local until the reviewer outputs SHIP; a human will push and open the PR.
```

### settings.json changes

Remove the two existing inline PreToolUse/Bash hooks:
- The `rm -rf` inline blocker → now handled by `enforce-loop-mode.sh` Level 1
- The `git push main/master` inline blocker → now handled by `enforce-loop-mode.sh` Level 1

Add one entry:
```json
{
  "type": "command",
  "command": "bash hooks/enforce-loop-mode.sh"
}
```

This replaces two inline rules with one maintainable script.

## Files to touch

| File | Change |
|------|--------|
| `scripts/task-complete.sh` | New: validate evidence, set claimed_complete, advance state |
| `hooks/enforce-loop-mode.sh` | New: two-level enforcement; Level 1 always, Level 2 in local-only mode |
| `scripts/ralph-check.sh` | Add Stop enforcement: block if files changed but task not claimed |
| `settings.json` | Add `enforce-loop-mode.sh` to PreToolUse/Bash; remove two equivalent inline rules |

## Risks and open questions

- **Resolved:** Both levels use exit 2 (hard block). Claude Code PreToolUse has no
  "soft warn" exit code — only exit 0 (allow) or non-zero (block). Message quality
  is the differentiator: Level 1 = terse/final, Level 2 = constructive/actionable.
- **Resolved:** `enforce-loop-mode.sh` also validates `task-complete.sh` calls (evidence
  gate). Combining both concerns in one hook is fine — it's one PreToolUse/Bash script.
- **Open:** `git commit` blocking in `local-only` mode — confirm this is desired.
  If the worker needs to commit mid-task for some workflows, this will cause friction.

## Progress log

- [x] `scripts/task-complete.sh` — new script; shellcheck + shfmt clean
- [x] `hooks/enforce-loop-mode.sh` — new script; Level 1 + Level 2 + task-complete.sh evidence gate; shellcheck + shfmt clean
- [x] `scripts/ralph-check.sh` — add Stop enforcement block for unclaimed completed work
- [x] `settings.json` — wire `hooks/enforce-loop-mode.sh`; remove two inline PreToolUse/Bash entries
- [x] Verify `shellcheck scripts/task-complete.sh hooks/enforce-loop-mode.sh scripts/ralph-check.sh` exits 0
- [x] Verify `shfmt -d scripts/task-complete.sh hooks/enforce-loop-mode.sh scripts/ralph-check.sh` exits 0
- [x] Verify `bash scripts/ralph-check.sh` exits 0

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Both enforcement levels use exit 2 | exit 1 = warn, exit 2 = block | Claude Code only distinguishes allow (0) vs block (non-zero). Message quality carries the UX difference. |
| Evidence gate = any file changed | Test suite passes, specific file exists | Language-agnostic, deterministic, zero false negatives on real work |
| Stop hook is the mandatory enforcement layer | Prompt instruction, skill | Prompt is forgotten in large contexts. Stop hook fires regardless of context state — agent cannot exit without signaling. |
| Combine enforcement + evidence gate in one hook | Separate hooks per concern | One script is simpler to maintain and test; concerns are cohesive (both are PreToolUse/Bash guards) |
| Remove inline `settings.json` rules | Keep both | Duplicate logic creates maintenance burden; enforce-loop-mode.sh is the canonical place |

## Completion criteria

- [x] All progress log items checked
- [x] `hooks/enforce-loop-mode.sh` exists and blocks `rm -rf` (Level 1) and `git push` in local-only mode (Level 2)
- [x] `scripts/ralph-check.sh` fails when files changed and `current_task.claimed_complete == false`
- [x] `settings.json` has `enforce-loop-mode.sh` in PreToolUse/Bash; inline blockers removed
- [x] `bash scripts/ralph-check.sh` exits 0 on clean state
