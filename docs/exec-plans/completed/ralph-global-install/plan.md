# Plan: Ralph Loop Global Install

**Status:** In progress
**Created:** 2026-03-02
**Issue:** N/A

## Requirements

- After running `/apply-core` once (globally into `~/.claude/`), Ralph Loop is immediately
  usable from any project directory.
- No per-project script copying required. The only per-project artifact is `ralph.yaml`.
- `~/.claude/scripts/ralph-loop.sh <slug>` works when invoked from any project root.
- `ralph-check.sh` (now global) reads `success_criteria` from the project's `ralph.yaml`
  and runs each check, making it project-agnostic.
- The Stop hook in `settings.json` references `~/.claude/scripts/ralph-check.sh`
  (absolute path), so it works in any project without per-project scripts.
- `apply-core.md` reflects the new model: scripts go to `~/.claude/scripts/`, only
  `ralph.yaml` is a per-project install.

## Approach

**Engine scripts → global** (`~/.claude/scripts/`):
- `ralph-loop.sh`, `log-client.sh`, `plan-advance.sh`, `task-complete.sh`
- `ralph-worker-prompt.md`, `ralph-reviewer-prompt.md`
- `ralph-check.sh` (rewritten to be project-agnostic)

**Project config → per-project** (unchanged):
- `ralph.yaml` — defines `max_iterations`, `warn_at_iteration`, `success_criteria`

**Key changes to `ralph-loop.sh`:**
- All internal helper refs use `${SCRIPT_DIR}/` (resolves to `~/.claude/scripts/` when global)
- `ralph.yaml` and exec-plans use `$PWD`-relative paths (already the case)
- Prompt files: look in `$PWD/scripts/` first, fall back to `${SCRIPT_DIR}/` — allows
  projects to customize prompts without losing the default
- `ralph-check.sh`: invoke via `${SCRIPT_DIR}/ralph-check.sh` (no per-project override needed)

**Key changes to `ralph-check.sh`:**
- Remove hardcoded shellcheck/shfmt/actionlint/no-todos/exec-plan-dirs checks
- Add YAML parsing: read `success_criteria[].check` from `ralph.yaml`, run each as a check
- Keep loop-state checks (task-claimed, handoff-entry) — these are generic
- If `ralph.yaml` not found or has no `success_criteria`: skip project checks (loop state only)

**`settings.json` Stop hook:**
- Change `bash scripts/ralph-check.sh` → `bash ~/.claude/scripts/ralph-check.sh`

**`apply-core.md` changes:**
- Ralph Loop component: install all scripts to `~/.claude/scripts/` (not `./scripts/`)
- Only `ralph.yaml` goes to `$PWD` (per-project config init)
- Update invocation instructions: `~/.claude/scripts/ralph-loop.sh <slug>`

## Files to touch

| File | Change |
|------|--------|
| `scripts/ralph-loop.sh` | Replace per-project helper refs with `${SCRIPT_DIR}/`; add prompt fallback |
| `scripts/ralph-check.sh` | Rewrite: generic loop-state checks + iterate `ralph.yaml` success_criteria |
| `settings.json` | Stop hook: `bash ~/.claude/scripts/ralph-check.sh` |
| `commands/apply-core.md` | Ralph Loop: scripts → `~/.claude/scripts/`; per-project = ralph.yaml only |
| `CLAUDE.md` | Update Ralph Loop invocation path to `~/.claude/scripts/ralph-loop.sh` |

## Risks and open questions

- **YAML parsing without a parser**: `ralph-check.sh` needs to extract `check:` values
  from `ralph.yaml`'s `success_criteria` list using awk/grep. The yaml structure is
  simple enough (single-line `check:` values) that awk works reliably. Constraint:
  `check:` values in ralph.yaml must be single-line commands.
- **Fetch branch**: `apply-core.md` fetches from `ace-work` branch. The updated scripts
  need to be on that branch for remote installs to work. This is a deployment concern —
  the plan covers code changes only; branch merging is a separate step.
- **Existing per-project installs**: Projects with `scripts/ralph-*.sh` already copied
  will have stale local files. Cleanup is manual and non-blocking.

## Progress log

- [x] Rewrite `scripts/ralph-check.sh`: remove hardcoded checks, add ralph.yaml
  success_criteria parsing, keep loop state checks
- [x] Update `scripts/ralph-loop.sh`: resolve all internal helpers via `${SCRIPT_DIR}/`,
  add prompt fallback logic
- [x] Update `settings.json` Stop hook to `bash ~/.claude/scripts/ralph-check.sh`
- [x] Update `commands/apply-core.md`: scripts to `~/.claude/scripts/`, ralph.yaml only
  per-project
- [x] Update `CLAUDE.md` Ralph Loop section with new invocation path
- [x] Run `shellcheck` and `shfmt` on modified scripts, fix any issues

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Generic ralph-check.sh reads ralph.yaml | Separate per-project check script | Keeps the global install model clean; zero per-project scripts needed |
| Prompt fallback: project-local → global | Project-local only / global only | Allows projects to customize prompts without losing the default |
| Keep ralph.yaml per-project | Also make it global | ralph.yaml has project-specific success_criteria — it's config, not engine |

## Completion criteria

- [x] `shellcheck scripts/ralph-check.sh scripts/ralph-loop.sh` passes
- [x] `shfmt -d scripts/ralph-check.sh scripts/ralph-loop.sh` passes
- [x] `actionlint` passes
- [x] `rg 'TODO|FIXME' commands/ scripts/` returns nothing
- [x] `ralph-loop.sh` uses `${SCRIPT_DIR}/` for all internal helper paths (plan-advance,
  ralph-check, log-client, prompts fallback)
- [x] `ralph-check.sh` has no hardcoded project-specific check commands
- [x] `ralph-check.sh` reads and runs `success_criteria[].check` from `ralph.yaml`
- [x] `settings.json` Stop hook references `~/.claude/scripts/ralph-check.sh`
- [x] `apply-core.md` installs all ralph scripts to `~/.claude/scripts/`
- [x] `apply-core.md` lists only `ralph.yaml` as the per-project install
