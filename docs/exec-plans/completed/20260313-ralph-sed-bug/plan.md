# Plan: Fix ralph-loop.sh sed multiline substitution bug

**Status:** In progress
**Created:** 2026-03-13

## Requirements

- Per-item review in `ralph-loop.sh` works when handoff text contains newlines
- Worker prompt substitution in `ralph-loop.sh` works when `{TASK_DIR}` or `{STATE_FILE}` contain special characters
- No `sed` used for template substitution anywhere in `ralph-loop.sh`

## Approach

Replace `sed` template substitution with bash parameter expansion in
`ralph-loop.sh`. This is the same pattern `orch-review.sh` already uses
(lines 95-99) and handles multiline content correctly.

Two substitution sites in `ralph-loop.sh`:

1. **Worker prompt** (line 228-231): `sed -e "s|{TASK_DIR}|..." -e "s|{STATE_FILE}|..."`
   → Replace with: read file via `cat`, then `${VAR//pattern/replacement}`

2. **Reviewer prompt** (line 368-373): `sed -e "s|{ITEM_TEXT}|..." ...` then
   `sed "s|{ITEM_HANDOFF}|${HANDOFF}|g"` (this is the one that crashes)
   → Replace with: read file via `cat`, then bash expansion for all 4 placeholders

## Files to touch

| File | Change |
|------|--------|
| `scripts/ralph-loop.sh` | Replace sed template substitution with bash parameter expansion (2 sites) |

## Risks and open questions

- **Bash expansion with special chars**: `${VAR//pattern/replacement}` handles
  newlines but can break on `&`, `\`, and `/` in the replacement string. Handoff
  text could contain any of these. Risk is low — `orch-review.sh` has been using
  this pattern without issues. If it does break, option 3 from bugs.md (heredoc
  temp file) is the fallback.

## Progress log

- [x] Replace sed with bash expansion for worker prompt substitution (lines 228-231)
- [x] Replace sed with bash expansion for reviewer prompt substitution (lines 368-373)
- [x] Test: run ralph-loop.sh on a plan where context-handoff.txt has multiline content

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Bash parameter expansion | awk/perl, heredoc temp file | Simplest fix, already proven in orch-review.sh. No new dependencies. |

## Completion criteria

- [x] No `sed` template substitution remains in `ralph-loop.sh` (only structural sed like completion-criteria extraction is ok)
- [x] shellcheck and shfmt clean
- [x] Per-item review runs successfully with multiline handoff text
