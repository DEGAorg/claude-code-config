# Plan: Docs Update

**Status:** In progress
**Created:** 2026-03-06

## Requirements

- All documentation reflects what actually shipped through the demo sprint
- CLAUDE.md repo map covers all current top-level dirs and key files
- README.md has a navigable file structure section
- canon/CLAUDE.md no longer says "being scaffolded" — artifacts exist
- docs/Dev_Flow.md accounts for terminal-ui, runner, and dashboard lifecycle
- canon/AGENTS.md verified accurate (audit found it already up to date)

## Approach

Top-down pass through each doc layer. Update the repo map in CLAUDE.md
first (it's the most-read file), then cascade into README, canon/CLAUDE.md,
and Dev_Flow.md. Don't rewrite — patch what's stale.

## Files to touch

| File | Change |
|------|--------|
| `CLAUDE.md` | Expand Repo Map: add `scripts/` (full listing), `scripts/terminal-ui/`, `canon/templates/`, `ace/`. Add `apply-core.md` and `canon-init.md` to commands row. Update "Active Work" section to post-demo state. |
| `README.md` | Add "File Structure" section after Contents — top-level dirs with 1-line descriptions. |
| `canon/CLAUDE.md` | Remove "being scaffolded" language. Reflect that agents, skills, commands, templates all exist. Update apply-canon references. |
| `docs/Dev_Flow.md` | Add subsection explaining terminal-ui dashboard and runner lifecycle in the context of Stages 4-5 (local implementation). |

## Risks and open questions

- README.md currently has no repo map at all. Adding one means deciding on
  level of detail. Decision: top-level dirs only, link to CLAUDE.md for full map.

## Progress log

- [x] Update CLAUDE.md Repo Map — expand `scripts/`, `commands/`, add missing dirs
- [x] Update CLAUDE.md "Active Work" section — post-demo state, current focus
- [x] Add file structure section to README.md
- [x] Update canon/CLAUDE.md — remove "being scaffolded", reflect shipped artifacts
- [x] Update docs/Dev_Flow.md — add terminal-ui/runner subsection to Stage 4-5
- [x] Verify canon/AGENTS.md still matches reality (audit says yes, quick confirm)
- [x] Read through all changes for consistency

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Top-level dirs only in README | Full nested tree | README should orient, not duplicate CLAUDE.md. Link to CLAUDE.md for details. |
| Patch docs, don't rewrite | Full rewrite of Dev_Flow | Demo additions are additive — existing pipeline stages are still correct, just incomplete. |

## Completion criteria

- [x] CLAUDE.md Repo Map lists all top-level dirs and key files
- [x] README.md has a file structure section
- [x] canon/CLAUDE.md contains no "being scaffolded" or stale TODO language
- [x] docs/Dev_Flow.md references terminal-ui and runner
- [x] No doc references files or paths that don't exist
