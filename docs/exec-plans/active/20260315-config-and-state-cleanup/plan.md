# Plan: Rename ralph.yaml to dega-core.yaml

**Status:** In progress
**Created:** 2026-03-15

## Requirements

Rename `ralph.yaml` to `dega-core.yaml` — this config file drives both Ralph
Loop and the orchestrator, so the name should reflect the full core scope.

## Approach

All scripts that read `ralph.yaml` must be updated to read `dega-core.yaml`.
The file format stays identical — only the filename changes. Scripts should
fall back to `ralph.yaml` for one release cycle so existing repos don't break
(print a deprecation warning).

Live code files to change:
- `scripts/ralph-loop.sh` — reads max_iterations, warn_at_iteration
- `scripts/ralph-check.sh` — reads success_criteria
- `scripts/orch-engine.sh` — reads poll_interval_seconds
- `scripts/orch-review.sh` — reads poll_interval_seconds
- `scripts/orch-verify.sh` — reads poll_interval_seconds
- `scripts/canon-scaffold.sh` — writes ralph.yaml for new Canon projects
- `tests/test-parallel-worktrees.sh` — creates ralph.yaml in test setup
- `ralph.yaml` (this repo) — rename the file itself

Live docs to update (current, non-completed references only):
- `CLAUDE.md` — repo map entry
- `README.md` — file structure table
- `docs/Self_Development.md` — ralph.yaml references
- `commands/apply-core.md` — if it copies ralph.yaml
- `commands/core-init.md` — if it references ralph.yaml
- `docs/Dev_Flow.md` — if it references ralph.yaml
- `canon/commands/canon-start.md` — references ralph.yaml
- `canon/skills/ralph-loop.md` — references ralph.yaml
- `canon/commands/develop.md` — references ralph.yaml
- `canon/commands/ralph-cycle.md` — references ralph.yaml

Completed exec-plans are historical records — do NOT update them.

## Files to touch

| File | Change |
|------|--------|
| `ralph.yaml` | Rename to `dega-core.yaml` |
| `scripts/ralph-loop.sh` | Read `dega-core.yaml` with `ralph.yaml` fallback |
| `scripts/ralph-check.sh` | Read `dega-core.yaml` with `ralph.yaml` fallback |
| `scripts/orch-engine.sh` | Read `dega-core.yaml` with `ralph.yaml` fallback |
| `scripts/orch-review.sh` | Read `dega-core.yaml` with `ralph.yaml` fallback |
| `scripts/orch-verify.sh` | Read `dega-core.yaml` with `ralph.yaml` fallback |
| `scripts/canon-scaffold.sh` | Write `dega-core.yaml` instead of `ralph.yaml` |
| `tests/test-parallel-worktrees.sh` | Create `dega-core.yaml` in test setup |
| `CLAUDE.md` | Update repo map: ralph.yaml -> dega-core.yaml |
| `README.md` | Update file structure table |
| `docs/Self_Development.md` | Update ralph.yaml references |
| `commands/apply-core.md` | Update config file reference |
| `commands/core-init.md` | Update config file reference |
| `canon/commands/canon-start.md` | Update ralph.yaml reference |
| `canon/skills/ralph-loop.md` | Update ralph.yaml reference |
| `canon/commands/develop.md` | Update ralph.yaml reference |
| `canon/commands/ralph-cycle.md` | Update ralph.yaml reference |

## Risks and open questions

- **Fallback period:** Scripts should check `dega-core.yaml` first, then fall
  back to `ralph.yaml` with a deprecation warning. This prevents breakage in
  repos that haven't been updated yet.

## Progress log

- [x] Rename `ralph.yaml` to `dega-core.yaml` in this repo (deps: none)
- [x] Add config-reading helper to `orch-state.sh` that checks `dega-core.yaml` then falls back to `ralph.yaml` with warning (deps: none)
- [x] Update `scripts/ralph-loop.sh` to use the config helper (deps: 2)
- [x] Update `scripts/ralph-check.sh` to use the config helper (deps: 2)
- [x] Update `scripts/orch-engine.sh` to use the config helper (deps: 2)
- [x] Update `scripts/orch-review.sh` to use the config helper (deps: 2)
- [x] Update `scripts/orch-verify.sh` to use the config helper (deps: 2)
- [x] Update `scripts/canon-scaffold.sh` to write `dega-core.yaml` (deps: none)
- [x] Update `tests/test-parallel-worktrees.sh` to create `dega-core.yaml` (deps: none)
- [x] Update all live docs: CLAUDE.md, README.md, Self_Development.md, commands/, canon/ (deps: 1)
- [x] Run shellcheck on all modified .sh files (deps: 2-9)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| `dega-core.yaml` name | `core.yaml`, `aidd.yaml`, `harness.yaml` | Matches the dega/aidd branding, clear scope |
| Fallback to ralph.yaml | Hard rename, no fallback | Prevents breakage in existing repos |

## Completion criteria

- [ ] `dega-core.yaml` exists at repo root with same content as old ralph.yaml
- [ ] `ralph.yaml` is deleted from this repo
- [ ] All scripts read `dega-core.yaml` first, fall back to `ralph.yaml` with warning
- [ ] `shellcheck` passes on all modified .sh files
