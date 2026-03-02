# Plan: Add date prefix to exec-plan slugs

**Status:** In progress
**Created:** 2026-03-02

## Requirements

- Exec-plan directory names must include a time reference so ordering is visible at a glance
- Not incremental numbering (parallel work makes incrementing fragile)
- Must sort chronologically in filesystem listings (`ls`, `fd`)
- Existing completed plans are not renamed — convention starts going forward

## Approach

Prefix every plan slug with `YYYYMMDD-`, e.g. `20260302-ralph-loop-sounds`.

- **8-digit date** sorts lexicographically = chronologically
- Parallel plans on the same day share the date prefix; the slug part disambiguates
- The ralph-loop still receives the full slug as its argument (`bash ralph-loop.sh 20260302-ralph-loop-sounds`), so no script logic changes

Update the `/plan` command template and the `/fix-issue` command to generate
slugs with the date prefix. Update CLAUDE.md examples. No changes to
`ralph-loop.sh` or other scripts — they already treat the slug as an opaque
string.

## Files to touch

| File | Change |
|------|--------|
| `commands/plan.md` | Slug format `YYYYMMDD-$SLUG`, example update |
| `commands/fix-issue.md` | Plan path from `issue-$N-plan.md` to `YYYYMMDD-issue-$N/plan.md` (also fixes flat-file inconsistency — should be a directory like `/plan`) |
| `CLAUDE.md` | Update ralph-loop example to show dated slug |

## Risks and open questions

- None blocking. The format is straightforward and backward-compatible.

## Progress log

- [ ] Update `commands/plan.md` slug generation to `YYYYMMDD-$SLUG`
- [ ] Update `commands/fix-issue.md` to use `YYYYMMDD-issue-$N/plan.md` directory format
- [ ] Update `CLAUDE.md` ralph-loop example with dated slug
- [ ] Verify no other files hardcode slug format assumptions

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| `YYYYMMDD-slug` prefix | `YYMMDD-slug`, `YYYYMMDD-HHMM-slug`, ISO `2026-03-02-slug` | 8-digit compact, sorts naturally, no ambiguity. HHMM is overkill (plans aren't created that frequently). ISO hyphens add visual noise and make the slug longer. |
| Don't rename existing completed plans | Batch rename all | Historical artifacts — renaming them adds noise to git history for no functional gain. Convention starts now. |
| Fix `fix-issue.md` flat-file format too | Leave as-is | It currently writes `active/issue-$N-plan.md` (flat file) instead of `active/issue-$N/plan.md` (directory). Since we're touching it, align it with the `/plan` directory convention. |

## Completion criteria

- [ ] `commands/plan.md` generates `YYYYMMDD-$SLUG` directory names
- [ ] `commands/fix-issue.md` uses dated directory format
- [ ] `CLAUDE.md` examples reflect new format
- [ ] Linting clean (`shellcheck`, `shfmt -d` on any touched scripts)
