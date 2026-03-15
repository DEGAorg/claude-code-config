# Plan: Feature changelog tracking

**Status:** In progress
**Created:** 2026-03-15

## Requirements

- `CHANGELOG.md` exists at repo root following Keep a Changelog format
- The orch SHIP path appends an entry to the changelog on every successful ship
- The ralph-loop SHIP path appends an entry to the changelog on every successful ship
- Entries are auto-generated from the plan title and date
- Backfill: all existing completed plans appear as entries

## Approach

### 1. Create shared helper: `orch_changelog_append`

Add a function to `scripts/orch-state.sh` that appends an entry under `## [Unreleased]` in `CHANGELOG.md`.

```bash
orch_changelog_append() {
    local slug="$1" title="$2" category="$3"
    local changelog="${ORCH_REPO_ROOT}/CHANGELOG.md"
    # Parse title from plan.md first line (# Plan: <title>)
    # Append under the right category (Added/Fixed/Changed)
    # If no [Unreleased] section, create one
}
```

Category detection: scan plan title for keywords — "fix" = Fixed, "add"/"new" = Added, default = Changed.

### 2. Wire into orch-engine.sh SHIP path

After registry append (if present), call `orch_changelog_append`. Read plan title from `completed/<slug>/plan.md` first line.

### 3. Wire into ralph-loop.sh SHIP path

Same — call `orch_changelog_append` after the commit.

### 4. Backfill existing completed plans

Scan `docs/exec-plans/completed/*/plan.md`, extract title from first `# Plan:` line, append entries grouped by date.

## Files to touch

| File | Change |
|------|--------|
| `CHANGELOG.md` | New — feature changelog |
| `scripts/orch-state.sh` | Add `orch_changelog_append` helper |
| `scripts/orch-engine.sh` | Call changelog append in SHIP path |
| `scripts/ralph-loop.sh` | Call changelog append in SHIP path |

## Risks and open questions

- **P2:** Category detection from title is heuristic. Worst case, everything goes under "Changed" — acceptable.

## Progress log

- [x] Add `orch_changelog_append` helper to orch-state.sh
- [x] Create `CHANGELOG.md` with initial structure
- [x] Wire changelog append into orch-engine.sh SHIP path
- [x] Wire changelog append into ralph-loop.sh SHIP path
- [x] Backfill existing completed plans into the changelog

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Keep a Changelog format | Custom format | Well-known convention, easy to parse and read |
| Auto-categorize by title keywords | Always "Changed" | Slightly better organization with minimal complexity |
| Shared helper in orch-state.sh | Separate script | Consistent with registry approach, single source |

## Completion criteria

- [ ] `CHANGELOG.md` exists with backfilled entries
- [ ] Running an orch plan to SHIP appends a changelog entry
- [ ] `shellcheck scripts/orch-state.sh scripts/orch-engine.sh scripts/ralph-loop.sh` clean
