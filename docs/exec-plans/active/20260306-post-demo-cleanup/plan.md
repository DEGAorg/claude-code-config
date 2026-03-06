# Plan: Post-Demo Cleanup

**Status:** In progress
**Created:** 2026-03-06

## Requirements

- Demo-prep exec plan archived from active/ to completed/
- QUALITY.md populated with first grades for all major codebase areas
- No stale references to removed or renamed files from the demo sprint
- Completed exec plans have consistent naming (date prefix audit)

## Approach

Sequential cleanup pass: archive the finished plan, run the cleanup scan
to grade the codebase, then sweep for stale references introduced during
the fast demo sprint. The naming audit for old exec plans is a low-priority
rename — flag but don't block on it.

## Files to touch

| File | Change |
|------|--------|
| `docs/exec-plans/active/20260303-demo-prep/` | Move to `completed/` |
| `docs/QUALITY.md` | Populate grades for: Core scripts, Canon layer, hooks, commands, docs, terminal-ui |
| Various | Fix any stale file references found during sweep |

## Risks and open questions

- 26 of 33 completed plans lack date prefixes. Renaming them touches git
  history for no functional gain. Decision: leave as-is, enforce prefix on
  new plans only.

## Progress log

- [ ] Move `active/20260303-demo-prep/` to `completed/20260303-demo-prep/`
- [ ] Run `/cleanup` scan — grade Core scripts, Canon layer, hooks, commands, docs, terminal-ui
- [ ] Populate QUALITY.md with grades from the scan
- [ ] Sweep for stale references: grep for `canon-init.sh` (renamed to `canon-scaffold.sh`), deleted files, broken paths
- [ ] Fix any stale references found
- [ ] Verify no dead imports or broken script paths in `scripts/`

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Leave old plan names as-is | Rename all 26 to add date prefix | No functional benefit, clutters git history. Convention enforced going forward. |

## Completion criteria

- [ ] No active exec plans from before today remain in `active/`
- [ ] QUALITY.md has at least 5 graded areas
- [ ] `rg 'canon-init\.sh'` returns zero hits outside of git history
- [ ] All script paths in commands/ resolve to existing files
