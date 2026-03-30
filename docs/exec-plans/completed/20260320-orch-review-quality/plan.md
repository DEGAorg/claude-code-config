# Plan: Fix orchestrator review quality — reject partial completions

**Status:** In progress
**Created:** 2026-03-20

## Requirements

- Reviewer agents must verify EVERY clause in an item description, not just the first one
- Items with compound requirements ("do X and Y") must have both X and Y verified — partial completion is a FAIL
- The reviewer must explicitly list each clause it verified and its result
- The done-file (worker handoff) must address every clause — if a clause is missing from the handoff, that's a FAIL
- The verifier agent (completion criteria) must also check for partial completions

## Approach

The problem is in the reviewer prompt (`scripts/ralph-item-reviewer-prompt.md`). It says "does the implementation match what the item asks for?" — this is too vague. The reviewer reads the handoff, skims the files, and PASS'es if the overall vibe is right.

### Fix 1: Reviewer prompt — clause-by-clause verification

Add a mandatory step: before deciding PASS/FAIL, the reviewer must decompose the item description into individual requirements (clauses), verify each one, and list them in the review file. Any unverified clause is a FAIL.

### Fix 2: Worker prompt — require addressing all clauses in done-file

Update the worker prompt (`agents/orch-worker.md`) to explicitly require that the done-file addresses every clause in the item description. Workers should self-check before writing the done-file.

### Fix 3: Verifier prompt — check for partial completions

Update the verifier prompt (`agents/orch-verifier.md`) to check that done-files and review results cover all clauses, not just the first one.

## Files to touch

| File | Change |
|------|--------|
| `scripts/ralph-item-reviewer-prompt.md` | Add clause decomposition step, require per-clause verification |
| `agents/orch-worker.md` | Add self-check: done-file must address every clause in item description |
| `agents/orch-verifier.md` | Add partial-completion detection to verification |

## Progress log

- [x] Rewrite reviewer prompt — add clause decomposition step: split item into clauses, verify each, list results, FAIL if any clause unverified
- [x] Update worker prompt — add done-file self-check: "list every requirement from your item description and confirm each one is addressed" (deps: 1)
- [x] Update verifier prompt — add check that done-files and reviews cover all clauses (deps: 1)
- [x] Test: create a 2-clause item, have worker complete only one clause, verify reviewer catches the gap (deps: 1, 2, 3)

## Completion criteria

- [x] Reviewer prompt includes clause decomposition step
- [x] Review files contain per-clause verification results
- [x] Worker prompt requires done-file to address every clause
- [x] Verifier prompt checks for partial completions
- [x] A test item with a deliberately partial completion gets FAIL'd by the reviewer
