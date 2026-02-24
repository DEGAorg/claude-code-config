# Plan: Fix apply-core — install ralph loop scripts per repo

**Status:** In progress
**Created:** 2026-02-24

## Requirements

- `/apply-core` installs `ralph.yaml`, `scripts/ralph-loop.sh`, `scripts/ralph-check.sh`,
  `scripts/ralph-worker-prompt.md`, and `scripts/ralph-reviewer-prompt.md` into the
  **current working directory** (the target project repo root), not globally.
- Installation is offered as an opt-in component in the Step 2 multi-select question.
- The inventory step (Step 1) checks whether ralph files already exist in the cwd.
- Install instructions handle the case where `scripts/` dir doesn't exist yet (create it).
- Shell scripts are `chmod +x` after writing.
- Existing `ralph.yaml` in the cwd is **not silently overwritten** — prompt to overwrite,
  skip, or show a diff (same treatment as `CLAUDE.md`).
- The `ralph.yaml` in the source list references `scripts/ralph-*.sh` relative paths —
  this remains correct since both land in the project root.
- The `@description` header line in `apply-core.md` is updated to mention per-repo
  ralph install alongside the global `~/.claude/` install.

## Approach

Single file edit: `commands/apply-core.md`.

Four targeted changes:

1. **Inventory (Step 1)** — add ralph file checks to the existing list.
2. **Ask what to install (Step 2)** — add a **Ralph Loop** component to the multi-select list.
3. **Install instructions (Step 4)** — add a new `#### Ralph Loop` section specifying
   destination as `<cwd>/ralph.yaml` and `<cwd>/scripts/ralph-*.{sh,md}`.
4. **Description header** — update `@description` to reflect per-repo ralph install.

No new files. No changes to the scripts themselves. No changes to `ralph.yaml`.

## Files to touch

| File | Change |
|------|--------|
| `commands/apply-core.md` | Add ralph loop component to inventory, selection, and install steps |

## Risks and open questions

- **None blocking.** The install destination (cwd) is unambiguous: ralph-loop.sh already
  hardcodes `docs/exec-plans/active/` and `scripts/` as relative paths from repo root.
  Installing to `$HOME` or `~/.local/bin` would break those relative references.

## Progress log

- [x] Edit `commands/apply-core.md`: inventory step — add ralph file checks
- [x] Edit `commands/apply-core.md`: Step 2 multi-select — add Ralph Loop component
- [x] Edit `commands/apply-core.md`: Step 4 — add `#### Ralph Loop` install section
- [x] Edit `commands/apply-core.md`: `@description` header — mention per-repo ralph
- [x] Run `shellcheck` and `shfmt` on scripts (no-op — no script changes, but verify health check passes)
- [x] Verify no TODOs introduced

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Install to cwd (per-repo) | `~/.local/bin`, `~/.claude/scripts/` | ralph-loop.sh uses relative paths (`docs/exec-plans/active/`, `scripts/`); must run from project root |
| Overwrite protection for `ralph.yaml` | Always overwrite | Matches CLAUDE.md treatment; user may have customized `max_iterations` or `success_criteria` |
| Single file edit only | Add new install step/command | Minimal scope; gap is in the existing command, not a missing command |

## Completion criteria

- [ ] `commands/apply-core.md` lists Ralph Loop in inventory, selection question, and install section
- [ ] Install section specifies cwd destinations (`ralph.yaml`, `scripts/ralph-*.{sh,md}`)
- [ ] `ralph.yaml` overwrite protection documented (prompt user, don't silently overwrite)
- [ ] `chmod +x` specified for `.sh` files
- [ ] No TODOs or FIXMEs introduced
- [ ] `shellcheck scripts/*.sh hooks/*.sh` passes
- [ ] `shfmt -i 2 -d scripts/ hooks/` passes
