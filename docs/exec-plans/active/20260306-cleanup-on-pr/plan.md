# Plan: Cleanup Hook on PR Creation

**Status:** In progress
**Created:** 2026-03-06
**Depends on:** 20260306-parallel-worktrees (if worktree-based PR flow is chosen)

## Requirements

- Automated cleanup/quality gate runs before or during PR creation
- Catches drift, stale references, lint warnings before code reaches review
- Works in both direct-push-to-branch and worktree-based workflows
- Does not block PR creation on non-critical issues — warns instead

## Discovery Questions

1. **Trigger mechanism:** Where does this hook fire?
   - **Option A: Pre-push git hook** — runs `prek` hook before `git push`.
     Blocks push if critical issues found. Simple, works everywhere.
   - **Option B: Ralph Loop post-SHIP step** — after reviewer says SHIP,
     run cleanup before the final commit. Keeps it in the ralph workflow.
   - **Option C: Claude Code Stop hook** — when Claude exits after
     completing work, run cleanup as a final pass. Catches issues but
     can't block anything.
   - **Option D: PR creation command** — new `/pr` command that runs
     cleanup, then creates the PR. Most control but requires manual
     invocation.
   Which trigger(s) do we want? They're not mutually exclusive.

2. **What does "cleanup" mean here?** The existing `/cleanup` command
   does a full codebase scan and grades QUALITY.md. That's too heavy for
   a PR gate. Options:
   - **Scoped cleanup:** Only check files changed in the PR (via `git diff`)
   - **Lint + type check:** Just run the project's linter and type checker
   - **Stale reference check:** Grep for imports/paths that don't resolve
   - **All of the above** with a fast-path (skip if no code changes)

3. **Relationship to `/review-pr`:** The existing `/review-pr` command
   does multi-agent code review. Should this cleanup hook be part of that
   flow, or a separate lighter gate that runs first?

4. **Worktree PR flow:** If parallel worktrees land (20260306-parallel-worktrees),
   the PR creation happens from a feature branch in a worktree. The cleanup
   hook needs to work in that context — running inside the worktree, not
   the main repo. Is this a hard requirement for v1, or can we start with
   the non-worktree flow and add worktree support later?

5. **Ralph Loop integration:** Currently ralph-loop.sh commits on SHIP
   but doesn't create a PR. Should it? If yes, the cleanup hook naturally
   fits as a pre-PR step in the loop. If no, PR creation stays manual
   and the hook attaches to whatever triggers it.

## Approach

Two-phase implementation:

**Phase A (lightweight, no worktree dependency):**
Add a pre-push quality gate via prek that runs scoped checks on changed
files only. Fast — runs in seconds, not minutes. Blocks push on critical
issues (broken imports, type errors), warns on non-critical (lint style).

**Phase B (after worktrees land):**
Add post-SHIP cleanup step to ralph-loop.sh that runs the scoped checks
and optionally creates a PR. The worktree's feature branch becomes the
PR source.

### Pre-push hook (Phase A)

```bash
#!/usr/bin/env bash
set -euo pipefail
# .prek/pre-push/cleanup-gate.sh

CHANGED=$(git diff --name-only origin/main...HEAD)
if [[ -z "$CHANGED" ]]; then exit 0; fi

# Type check (if applicable)
if [[ -f "tsconfig.json" ]]; then
  npx tsc --noEmit || { echo "error: type check failed"; exit 1; }
fi

# Lint changed files only
echo "$CHANGED" | grep -E '\.(ts|tsx|js|jsx)$' | xargs -r npx oxlint
echo "$CHANGED" | grep -E '\.py$' | xargs -r ruff check
echo "$CHANGED" | grep -E '\.sh$' | xargs -r shellcheck

# Stale reference check
echo "$CHANGED" | while read -r f; do
  grep -n 'canon-init\.sh' "$f" 2>/dev/null && \
    echo "warn: $f references renamed canon-init.sh"
done
```

### Post-SHIP step (Phase B)

```bash
# Added to ralph-loop.sh after SHIP decision
if [[ "$RESULT" == "SHIP" ]]; then
  bash "${SCRIPT_DIR}/ralph-cleanup-gate.sh"
  # If in worktree with feature branch:
  # gh pr create --base main --head "ralph/${TASK_SLUG}" ...
fi
```

## Files to touch

| File | Change |
|------|--------|
| `hooks/cleanup-gate.sh` | New — scoped cleanup check for changed files |
| `scripts/ralph-loop.sh` | Add post-SHIP cleanup step (Phase B) |
| `.prek/pre-push/cleanup-gate.sh` | New — prek hook wiring (Phase A) |
| `commands/apply-core.md` | Add cleanup-gate to install manifest |

## Risks and open questions

- Pre-push hooks can be slow if the project has heavy type checking. Need
  to benchmark and add a timeout or skip flag.
- `prek` may not be installed in all repos — the hook needs to degrade
  gracefully or be installed by `/core-init`.
- Stale reference detection is brittle with grep. Could use ast-grep for
  import checking, but that adds a dependency.

## Progress log

- [ ] Resolve discovery questions (trigger mechanism, scope, worktree requirement)
- [ ] Write `hooks/cleanup-gate.sh` — scoped quality check on changed files
- [ ] Wire into prek as pre-push hook
- [ ] Test: push with clean code (passes), push with broken import (blocks)
- [ ] Test: push with lint warning (warns but doesn't block)
- [ ] (Phase B) Add post-SHIP cleanup step to ralph-loop.sh
- [ ] (Phase B) Add optional PR creation after cleanup passes
- [ ] Add cleanup-gate to `/apply-core` and `/core-init` install manifests

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Two-phase approach | All-at-once | Phase A works without worktree dependency. Phase B adds integration after worktrees land. Unblocks progress. |
| Scoped checks (changed files only) | Full `/cleanup` scan | Full scan is too slow for a push gate. Scoped checks run in seconds. |
| Warn on non-critical, block on critical | Block on everything / warn on everything | Developers shouldn't be blocked by style nits, but broken types must not reach review. |

## Completion criteria

- [ ] Pre-push hook runs scoped checks on changed files
- [ ] Blocks push on critical issues (type errors, broken imports)
- [ ] Warns on non-critical issues (lint style) without blocking
- [ ] Hook is installable via `/apply-core` and/or `/core-init`
- [ ] (Phase B) Ralph Loop runs cleanup before creating PR on SHIP
