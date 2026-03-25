# Plan: Complete GH audit trail with work summaries, feedback, and verify results

**Status:** In progress
**Created:** 2026-03-25
**Depends on:** 20260325-gh-mode-skip-local-artifacts (Plan A must land first)

## Requirements

When `github.sync: true`, all orchestrator state that was previously
written to local files must instead be posted as comments on the
GitHub Issue. The issue becomes a complete audit trail of the plan's
execution -- no local files needed to reconstruct what happened.

## Context

Currently posted to GH (via `01-gh-plan-sync.sh` lifecycle hook):
- `start` -- "Plan started" + item count
- `review` -- "Item N -- SHIP/REVISE" + iteration count (but NO feedback text)
- `ship` -- "Plan SHIP" summary
- `revise` -- "Plan REVISE" failure summary
- `pr` -- PR URL link
- `pr_merged` -- "Plan completed" + close issue

Missing from GH:
- **work-summary.txt** -- what the worker did for each item (written by worker agent)
- **review-feedback.txt** -- reviewer's detailed REVISE feedback (the `--feedback` flag exists in `gh-plan-sync.sh` but the lifecycle hook never reads or passes it)
- **verify result** -- no `verify` event exists; pass/fail outcome and details are not posted

All these files are short text (a few lines to a few paragraphs), well
within GitHub's 65K comment size limit.

## Approach

### 1. Work summary on review comment

The lifecycle hook's `review` handler already reads per-item state from
`state.json`. Extend it to also read the worker's `work-summary.txt`
from the worktree plan dir or `.orchestrator/` done dir, and pass it
as a new `--work-summary` flag to `gh-plan-sync.sh`. The sync script
includes it in the review comment body.

### 2. Review feedback on REVISE

The `--feedback` flag already exists in `gh-plan-sync.sh` and is included
in the comment when present. The lifecycle hook just needs to read
`review-feedback.txt` from the plan dir and pass it via `--feedback`.

### 3. Verify event

Add a new `verify` event to both `gh-plan-sync.sh` and the lifecycle
hook. The engine calls `run_lifecycle_hooks "verify"` after the verifier
completes. The comment includes pass/fail and the criteria results.

## Files to touch

| File | Change |
|------|--------|
| `scripts/gh-plan-sync.sh` | Add `--work-summary` flag to review handler; add `verify` event handler |
| `hooks/orch-lifecycle/01-gh-plan-sync.sh` | Read work-summary.txt + review-feedback.txt in review handler; add verify event dispatch |
| `scripts/orch-engine.sh` | Fire `verify` lifecycle hook after verifier completes |

## Risks and open questions

1. **work-summary.txt location** -- workers write this in the worktree
   plan dir. The lifecycle hook runs from the main repo. Need to resolve
   the path: `.orchestrator/worktrees/<slug>/docs/exec-plans/active/<slug>/work-summary.txt`
   or `.orchestrator/plans/<slug>/done/item-N.txt`. Check which exists.

2. **Comment noise** -- work summaries on every item could be verbose.
   Could collapse into a `<details>` block. Keep it simple for now;
   iterate if noisy.

## Progress log

- [x] Add `--work-summary` flag to `gh-plan-sync.sh` review handler; include in comment body
- [x] Read work-summary.txt in lifecycle hook review handler and pass via `--work-summary` (deps: 1)
- [x] Read review-feedback.txt in lifecycle hook review handler and pass via `--feedback` (deps: 1)
- [x] Add `verify` event to `gh-plan-sync.sh` with pass/fail comment (deps: 1)
- [ ] Add `verify` event dispatch to lifecycle hook (deps: 4)
- [ ] Fire `verify` lifecycle hook from `orch-engine.sh` after verifier completes (deps: 5)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Post as comments | Upload as issue file attachments | Comments are simpler, searchable, and within size limits |
| Include work summary in review comment | Separate comment per summary | One comment per item is cleaner than two |
| Use details/summary for long text | Always inline | Keeps comment thread scannable |

## Completion criteria

- [ ] With `github.sync: true`, a REVISE item's GH comment includes reviewer feedback text
- [ ] With `github.sync: true`, a SHIP item's GH comment includes work summary
- [ ] With `github.sync: true`, a verify pass/fail posts a comment on the issue
- [ ] `shellcheck -e SC1091 -S warning scripts/gh-plan-sync.sh hooks/orch-lifecycle/01-gh-plan-sync.sh scripts/orch-engine.sh` passes
