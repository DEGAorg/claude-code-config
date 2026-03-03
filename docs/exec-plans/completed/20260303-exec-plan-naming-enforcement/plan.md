# Plan: Exec-Plan Naming Enforcement

**Status:** In progress
**Created:** 2026-03-03

## Requirements

- PreToolUse hook blocks creation of exec-plan directories that don't match `YYYYMMDD-slug` format
- Hook catches both `Bash` (mkdir) and `Write` (file creation) targeting `exec-plans/active/`
- Shell helper `scripts/create-exec-plan.sh` creates a correctly-named directory with today's date
- The `/plan` command instructions already specify the format — enforcement makes it machine-checked
- Hook follows existing patterns: `enforce-loop-mode.sh` style, exit 2 to block, clear error message

## Approach

### 1. PreToolUse hook (`hooks/enforce-exec-plan-naming.sh`)

Two matchers needed — `Bash` and `Write` — because the agent can create the
directory via either tool:

**Bash matcher:** Intercepts `mkdir` commands where the path contains `exec-plans/active/`.
Extracts the directory name after `active/` and validates it matches `^[0-9]{8}-`.

**Write matcher:** Intercepts file writes where `file_path` contains `exec-plans/active/`.
Extracts the first path segment after `active/` and validates the same pattern.

Both emit a clear error:
```
BLOCKED: exec-plan directory must start with YYYYMMDD- (e.g., 20260303-add-auth).
Use: bash scripts/create-exec-plan.sh <slug>
```

Single script handles both — checks `$TOOL_NAME` or inspects the input to determine
which path to extract.

### 2. Shell helper (`scripts/create-exec-plan.sh`)

Takes a slug argument, prepends today's date, creates the directory and empty `plan.md`:

```bash
scripts/create-exec-plan.sh add-auth-endpoint
# → creates docs/exec-plans/active/20260303-add-auth-endpoint/
# → creates docs/exec-plans/active/20260303-add-auth-endpoint/plan.md (empty)
# → prints the path
```

If the slug already starts with `YYYYMMDD-`, it uses it as-is (idempotent).
If the directory already exists, it prints the path without error (safe to re-run).

### 3. Wire into settings.json

Add the hook to the `PreToolUse` array with matchers for both `Bash` and `Write`.

## Files to touch

| File | Change |
|------|--------|
| `hooks/enforce-exec-plan-naming.sh` | Create — PreToolUse validation hook |
| `scripts/create-exec-plan.sh` | Create — shell helper for correct directory creation |
| `settings.json` | Add PreToolUse hook entries for Bash and Write matchers |

## Risks and open questions

- **P2:** Should the hook also validate `completed/` directories (when moving plans)?
  → No. Only enforce on `active/`. Moving to `completed/` preserves the existing name.
- **P2:** Should the helper also scaffold `plan.md` with the template? → No. The
  `/plan` command handles that. The helper just creates the directory. Keep them
  separate — single responsibility.

## Progress log

- [x] Write `hooks/enforce-exec-plan-naming.sh` (handles both Bash and Write tool inputs)
- [x] Write `scripts/create-exec-plan.sh` (date-prefixed directory creator)
- [x] Add hook to `settings.json` PreToolUse array
- [x] Test: `mkdir` without date prefix → blocked
- [x] Test: `Write` to path without date prefix → blocked
- [x] Test: `scripts/create-exec-plan.sh some-slug` → correct directory created
- [x] shellcheck and shfmt pass on both scripts

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Single hook script for both Bash and Write | Separate scripts per matcher | Less duplication. The validation logic is the same — only the path extraction differs. |
| Hook points agent to `create-exec-plan.sh` in error msg | Just block with no guidance | Actionable errors. Agent reads the message and self-corrects on retry. |
| Helper prepends date only if missing | Always prepend | Idempotent. Safe to call with or without the date prefix. |
| Only enforce on `active/` | Also `completed/` and `tech-debt/` | `completed/` gets plans moved from `active/` — already validated. `tech-debt/` has different conventions. |

## Completion criteria

- [x] Hook blocks `mkdir docs/exec-plans/active/bad-slug/` (no date prefix)
- [x] Hook blocks `Write` to `docs/exec-plans/active/bad-slug/plan.md`
- [x] Hook allows `mkdir docs/exec-plans/active/20260303-good-slug/`
- [x] Hook allows `Write` to `docs/exec-plans/active/20260303-good-slug/plan.md`
- [x] `scripts/create-exec-plan.sh my-task` creates `20260303-my-task/`
- [x] shellcheck and shfmt clean on both scripts
