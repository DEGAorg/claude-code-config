# Plan: Add ralph loop command hint to /plan hand-off

**Status:** In progress
**Created:** 2026-02-24

## Requirements

- After writing the plan file, `/plan` outputs the exact bash command to run the
  ralph loop for that plan.
- The output is shown to the agent (and visible to the user) as part of the hand-off
  step — not buried in prose.
- The command uses the slug derived during the plan, so it is always correct without
  manual substitution.
- Output format:

  ```
  To run the ralph loop for this plan:

      bash scripts/ralph-loop.sh <slug>
  ```

## Approach

Single sentence appended to the **Step 4 Hand off** section of `commands/plan.md`.
No structural changes — just add the output instruction after the existing "stop" line.

## Files to touch

| File | Change |
|------|--------|
| `commands/plan.md` | Append ralph loop command hint to Step 4 Hand off |

## Risks and open questions

- None blocking.

## Progress log

- [x] Edit `commands/plan.md`: append ralph loop command hint to Step 4 Hand off section

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Append to Step 4, not a new step | New Step 5 | It's part of hand-off, not a separate action |
| Output as fenced code block | Inline prose | Code block is unambiguous and copy-paste ready |

## Completion criteria

- [x] `commands/plan.md` Step 4 includes the ralph loop command hint with `<slug>` placeholder
- [x] No TODOs or FIXMEs introduced
- [x] `shellcheck scripts/*.sh hooks/*.sh` passes
- [x] `shfmt -i 2 -d scripts/ hooks/` passes

---

To run the ralph loop for this plan:

    bash scripts/ralph-loop.sh plan-ralph-hint
