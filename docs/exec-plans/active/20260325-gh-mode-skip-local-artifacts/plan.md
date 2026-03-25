# Plan: Skip git-tracked plan artifacts when github.sync is true

**Status:** In progress
**Created:** 2026-03-25

## Requirements

When `dega-core.yaml` has `github.sync: true`, the orchestrator must
never read from or write to `docs/exec-plans/`. GitHub Issues are the
single source of truth in GH mode. PRs should contain only code changes.

When `github.sync` is false or absent (local mode), the current behavior
is preserved: plan artifacts live in `docs/exec-plans/active/` and move
to `completed/` on SHIP.

## Context

The problem has two halves:

**Launch time (orch-run.sh):** Even in GH mode, `PLAN_DIR` resolves to
`docs/exec-plans/active/<slug>`. When fetching from `--issue`, the
fetched plan is copied INTO `docs/exec-plans/active/`. The worktree
copy also writes there. In GH mode, plans should resolve from
`.orchestrator/plans/<slug>/plan.md` instead.

**SHIP time (orch-engine.sh):** Steps 1/4/5/6 write plan state back
to `docs/exec-plans/` and commit it. Post-SHIP validation checks those
directories exist. These cause merge conflicts when multiple plans run
concurrently.

The GH sync layer (`gh-plan-sync.sh`) already handles state transitions:
labels, comments, progress checkbox updates, and Status field changes on
the issue body.

## Approach

Add a `GH_SYNC` boolean flag (read via `gh_config_bool sync`) and use
it to switch plan paths and gate local-only steps.

### Launch path changes in `orch-run.sh`

In GH mode:
- `PLAN_DIR` resolves to `.orchestrator/plans/<slug>` instead of
  `docs/exec-plans/active/<slug>`
- When fetching from `--issue`, plan stays in `.orchestrator/` (no copy
  to `docs/exec-plans/active/`)
- When plan already exists locally in `docs/exec-plans/active/`, copy it
  to `.orchestrator/plans/<slug>/plan.md` and use that as `PLAN_DIR`
- Worktree plan copy: write to `.orchestrator/` path inside worktree, not
  `docs/exec-plans/active/`
- Skip the uncommitted-plan guard (irrelevant in GH mode)

In local mode: no changes.

### Engine/parser path changes

- `orch-engine.sh`: resolve `PLAN_DIR` from `.orchestrator/` in GH mode
- `orch-parse-items.sh`: resolve plan path from `.orchestrator/` in GH mode
- `orch-verify.sh`: resolve plan path from `.orchestrator/` in GH mode

### SHIP flow changes in `orch-engine.sh`

| Step | Action | GH mode | Local mode |
|------|--------|---------|------------|
| 1 | Sync plan.md worktree -> active/ | Skip | Keep |
| 2 | Commit worktree code changes | Keep | Keep |
| 3 | Deregister master state | Keep | Keep |
| 4 | Move active/ -> completed/ | Skip | Keep |
| 5 | Commit plan move | Skip | Keep |
| 6 | Append plan registry | Skip | Keep |
| 7 | Append changelog | Keep | Keep |
| 8 | Push branch + create PR | Keep | Keep |
| 9 | Clean up worktree | Keep | Keep |
| Post | Validate active/completed dirs | Skip | Keep |

### Review/verify file writes

- `orch-verify.sh`: writes `verify-result.txt` into plan dir. In GH mode,
  plan dir is already `.orchestrator/`, so no change needed beyond path
  resolution.
- `orch-review.sh`: writes `review-feedback.txt` into plan dir. Same.

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-run.sh` | In GH mode: resolve PLAN_DIR from `.orchestrator/`, skip copy to `docs/exec-plans/`, skip uncommitted guard |
| `scripts/orch-engine.sh` | Read `GH_SYNC` at startup; resolve PLAN_DIR from `.orchestrator/`; gate SHIP steps 1, 4, 5, 6, and post-validation |
| `scripts/orch-parse-items.sh` | Resolve plan path from `.orchestrator/` in GH mode |
| `scripts/orch-verify.sh` | Resolve plan path from `.orchestrator/` in GH mode |
| `scripts/orch-review.sh` | Resolve plan path from `.orchestrator/` in GH mode (review-feedback.txt stays in `.orchestrator/`) |

## Risks and open questions

1. **Worker agent prompt** -- `agents/orch-worker.md` tells workers to
   look at `docs/exec-plans/active/<slug>/plan.md`. In GH mode the plan
   is at a different path. The prompt template uses `{PLAN_PATH}` which
   is resolved by the engine, so this should work if the engine passes
   the correct path. Verify.

2. **Backward compatibility** -- local mode must work exactly as before.
   All changes are gated behind the `GH_SYNC` flag.

3. **Existing plans in docs/exec-plans/active/** -- in GH mode, these
   are ignored by the engine. They can be cleaned up separately.

## Decisions (settled)

- Changelog: keep in both modes (useful for releases regardless of backend)
- Plan registry: skip in GH mode (issue list IS the registry)

## Progress log

- [x] Add `GH_SYNC` flag to `orch-run.sh`; resolve PLAN_DIR from `.orchestrator/` in GH mode; skip copy to `docs/exec-plans/` and uncommitted guard
- [x] Add `GH_SYNC` flag to `orch-engine.sh`; resolve PLAN_DIR from `.orchestrator/`; gate SHIP steps 1, 4, 5, 6, and post-validation (deps: 1)
- [x] Update `orch-parse-items.sh` to resolve plan path from `.orchestrator/` in GH mode (deps: 1)
- [ ] Update `orch-verify.sh` to resolve plan path from `.orchestrator/` in GH mode (deps: 2)
- [ ] Update `orch-review.sh` to resolve plan path from `.orchestrator/` in GH mode (deps: 2)
- [ ] Test: run a plan with `github.sync: true` and verify PR diff has zero `docs/exec-plans/` files; run with `sync: false` and verify local flow works (deps: 3, 4, 5)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Gate with boolean flag | Separate code paths / strategy pattern | Simple if/else is clearer for a handful of conditional lines |
| Keep changelog in both modes | Skip in GH mode | Useful for releases regardless of plan backend |
| Skip registry in GH mode | Keep in both | GH Issues list IS the registry |
| Resolve plan from .orchestrator/ in GH mode | Keep docs/exec-plans/ as read path | Cleaner separation; .orchestrator/ is already gitignored |

## Completion criteria

- [ ] `rg 'GH_SYNC' scripts/orch-run.sh scripts/orch-engine.sh` shows the flag defined and used in both
- [ ] With `github.sync: true`, `docs/exec-plans/active/` is never written to during a plan run
- [ ] With `github.sync: true`, a completed plan's PR diff contains zero files under `docs/exec-plans/`
- [ ] With `github.sync: false`, `docs/exec-plans/completed/<slug>/plan.md` exists after SHIP
- [ ] `shellcheck -e SC1091 -S warning scripts/orch-run.sh scripts/orch-engine.sh scripts/orch-parse-items.sh scripts/orch-verify.sh scripts/orch-review.sh` passes
