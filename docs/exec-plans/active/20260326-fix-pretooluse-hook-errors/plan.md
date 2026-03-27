# Fix PreToolUse hook errors

**Source:** `ace/notes/linux-issues.md` issue 4
**Analysis:** `ace/notes/linux-issues-analysis.md`

## Problem

"PreToolUse:Bash hook error" appears in both macOS and Linux when working
in the claude-code-config repo. Two hooks fire on Bash commands:

1. `hooks/enforce-loop-mode.sh` — uses `jq` to parse stdin
2. `hooks/enforce-exec-plan-naming.sh` — uses `jq` to parse stdin

Both use relative paths in `settings.json` (`bash hooks/enforce-loop-mode.sh`).
Potential failure modes:

- **jq not installed** on fresh Linux — `set -euo pipefail` causes
  immediate exit on `jq` failure, which surfaces as a hook error.
- **CWD mismatch** — if Claude Code's CWD isn't the repo root, relative
  path `hooks/enforce-loop-mode.sh` won't resolve.
- **stdin not provided** — if the hook framework doesn't pipe tool input
  to the hook's stdin, `jq` blocks or errors.

## Approach

1. Add `jq` availability check at the top of each hook — if not found,
   exit 0 (allow) with a warning rather than crashing.
2. Make hook paths robust: use `"${BASH_SOURCE[0]%/*}"` to resolve the
   hooks directory relative to the script location, or use absolute paths
   in `settings.json`.
3. Add defensive stdin handling — if stdin is empty or not JSON, exit 0.
4. Test hooks with and without `jq` installed.

## Requirements

1. Hooks must never crash — a hook failure blocks the user's work.
2. If a dependency (`jq`) is missing, hooks degrade gracefully (allow + warn).
3. Hooks must work regardless of CWD.
4. Fix must apply to both macOS and Linux.

## Progress log

- [x] Audit all hooks in `settings.json` for dependency and path issues — catalog each hook's deps and path strategy
- [x] Add defensive `jq` check to `enforce-loop-mode.sh`: if not found, warn and exit 0 (deps: 1)
- [x] Add defensive `jq` check to `enforce-exec-plan-naming.sh`: same pattern (deps: 1)
- [x] Add defensive stdin/JSON validation to both hooks: read stdin, check non-empty and valid JSON before parsing (deps: 2, 3)
- [x] Fix `settings.json` hook paths: use absolute `~/.claude/hooks/` paths or `$PROJECT_ROOT/hooks/` pattern (deps: 1)
- [x] Audit PostToolUse hooks for same issues — `orch-done-sync.sh`, inline jq in Edit|Write hook (deps: 1)
- [ ] Test hooks on macOS: verify no errors in normal operation (deps: 4, 5, 6)
- [x] Add `jq` to documented prerequisites in README or core-init (deps: 2)

## Completion criteria

- [ ] No "PreToolUse:Bash hook error" when running Claude Code in this repo
- [ ] Hooks degrade gracefully when `jq` is missing (warn + allow)
- [ ] Hooks work from any CWD within the repo
- [ ] All hooks pass shellcheck
- [ ] PostToolUse hooks also audited and fixed
