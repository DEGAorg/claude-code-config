# Plan: Remove ralph-check.sh from global Stop hook

**Status:** In progress
**Created:** 2026-03-02

## Requirements

- `ralph-check.sh` must NOT run as a global Stop hook in `settings.json`
- The Ralph Loop orchestrator (`ralph-loop.sh`) must continue calling `ralph-check.sh` directly (line 232 — already does this)
- Normal interactive sessions must only run `play-sound.sh` on Stop
- CLAUDE.md must reflect that ralph-check is loop-only, not an interactive Stop hook
- The `permissions.allow` entry for `Bash(bash scripts/ralph-check.sh)` in the installed `~/.claude/settings.json` can be removed (it was there to auto-approve the Stop hook invocation)

## Approach

Straightforward removal. The ralph-check Stop hook was a design mistake — it fires on every session stop, errors when no `ralph.yaml` or state file exists, and the Ralph Loop already calls it directly. Remove it from both the template and installed settings.

## Files to touch

| File | Change |
|------|--------|
| `settings.json` | Remove ralph-check entry from `Stop` hooks array |
| `~/.claude/settings.json` | Remove ralph-check entry from `Stop` hooks array + remove `permissions.allow` entry |
| `CLAUDE.md` | Update "Ralph Loop" section: remove mention of Stop hook running ralph-check in interactive sessions |

## Risks and open questions

- None. The ralph-loop.sh orchestrator already calls ralph-check.sh directly (line 232). Removing the global hook has zero impact on Ralph Loop functionality.

## Progress log

- [x] Remove ralph-check from Stop hooks in `settings.json` (template)
- [x] Remove ralph-check from Stop hooks in `~/.claude/settings.json` (installed)
- [x] Remove `Bash(bash scripts/ralph-check.sh)` from `permissions.allow` in `~/.claude/settings.json`
- [x] Update CLAUDE.md — remove interactive Stop hook reference for ralph-check

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Remove entirely from Stop hooks | Guard with env var check (e.g., `RALPH_LOOP=1`) | Simplest fix. The loop already calls it directly. A guard adds complexity for zero benefit. |

## Completion criteria

- [x] `settings.json` Stop array has only `play-sound.sh`
- [x] `~/.claude/settings.json` Stop array has only `play-sound.sh`
- [x] `~/.claude/settings.json` `permissions.allow` no longer has ralph-check entry
- [x] CLAUDE.md no longer says the Stop hook runs ralph-check
- [x] `ralph-loop.sh` still calls ralph-check.sh on line 232 (unchanged — verify, don't modify)
