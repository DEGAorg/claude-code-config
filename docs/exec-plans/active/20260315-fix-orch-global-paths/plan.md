# Plan: Fix orch scripts to work when installed globally

**Status:** In progress
**Created:** 2026-03-15

## Requirements

The orchestrator scripts can be installed globally to `~/.claude/scripts/`
via `/apply-core`. But they derive `REPO_ROOT` from `SCRIPT_DIR/..`, which
resolves to `~/.claude/` instead of the target project root. This breaks
plan discovery, config loading, git operations, and worktree creation.

The Ralph Loop already handles this correctly — it uses `pwd`-relative paths
for project files and `SCRIPT_DIR` only for sourcing sibling scripts. Apply
the same pattern to all orch scripts.

## How Ralph Loop does it (the correct pattern)

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/orch-state.sh"     # SCRIPT_DIR for sibling scripts

# Project paths are relative to pwd (the project root)
TASK_DIR="docs/exec-plans/active/${TASK_SLUG}"
```

Ralph Loop never derives a REPO_ROOT from SCRIPT_DIR. It trusts that the
caller runs it from the project root directory, and uses relative paths.

## The fix

### orch-state.sh (the root cause)

Line 26 sets the default for all orch scripts:
```bash
: "${ORCH_REPO_ROOT:="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"}"
```

Change to use `git rev-parse --show-toplevel` (works in worktrees too) with
`pwd` as fallback:
```bash
: "${ORCH_REPO_ROOT:="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"}"
```

This single fix propagates to every script that sources orch-state.sh,
since they all read ORCH_REPO_ROOT from there.

### orch-run.sh, orch-engine.sh, orch-review.sh, orch-verify.sh, planner-loop.sh

Each has its own `REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"`. Change to:
```bash
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
```

These scripts also set `ORCH_REPO_ROOT` implicitly by sourcing orch-state.sh
after setting REPO_ROOT, but some override it. Ensure ORCH_REPO_ROOT is set
consistently from the same git-toplevel logic.

### orch-engine.sh tmux command

Line 240 in orch-run.sh launches the engine with `cd '${REPO_ROOT}'`. This
is fine — it passes the resolved REPO_ROOT to the tmux command. But when the
engine starts in the tmux pane, it re-derives REPO_ROOT from SCRIPT_DIR.
The engine should inherit REPO_ROOT via the cd in the tmux command, so fixing
its own REPO_ROOT derivation is sufficient.

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-state.sh` | Fix ORCH_REPO_ROOT default to git-toplevel or pwd |
| `scripts/orch-run.sh` | Fix REPO_ROOT to git-toplevel or pwd |
| `scripts/orch-engine.sh` | Fix REPO_ROOT to git-toplevel or pwd |
| `scripts/orch-review.sh` | Fix REPO_ROOT to git-toplevel or pwd |
| `scripts/orch-verify.sh` | Fix REPO_ROOT to git-toplevel or pwd |
| `scripts/planner-loop.sh` | Fix REPO_ROOT to git-toplevel or pwd |

## Progress log

- [x] Fix `scripts/orch-state.sh` line 26 — change ORCH_REPO_ROOT default from SCRIPT_DIR-based to git-toplevel with pwd fallback (deps: none)
- [x] Fix `scripts/orch-run.sh` — change REPO_ROOT from SCRIPT_DIR-based to git-toplevel with pwd fallback (deps: none)
- [x] Fix `scripts/orch-engine.sh` — change REPO_ROOT from SCRIPT_DIR-based to git-toplevel with pwd fallback (deps: none)
- [x] Fix `scripts/orch-review.sh` — change REPO_ROOT from SCRIPT_DIR-based to git-toplevel with pwd fallback (deps: none)
- [x] Fix `scripts/orch-verify.sh` — change REPO_ROOT from SCRIPT_DIR-based to git-toplevel with pwd fallback (deps: none)
- [x] Fix `scripts/planner-loop.sh` — change REPO_ROOT from SCRIPT_DIR-based to git-toplevel with pwd fallback (deps: none)
- [x] Run shellcheck on all 6 modified files (deps: 1-6)
- [ ] Verify orch-run.sh works from a different project directory by checking REPO_ROOT resolves correctly (deps: 1-6)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| `git rev-parse --show-toplevel` | `pwd`, env var | Works in worktrees, submodules, and nested dirs. pwd only works if run from root. |
| `pwd` as fallback | Error if not in git repo | Graceful degradation for non-git usage |
| Fix each script individually | Only fix orch-state.sh | Some scripts set REPO_ROOT before sourcing orch-state.sh, so ORCH_REPO_ROOT inherits wrong value |

## Completion criteria

- [ ] All 6 scripts use git-toplevel instead of SCRIPT_DIR-based REPO_ROOT
- [ ] `shellcheck` passes on all modified files
- [ ] Running `bash ~/.claude/scripts/orch-run.sh <slug>` from a project dir resolves REPO_ROOT to that project, not ~/.claude
