# Dead-code triage — `GH_SYNC=false` branches in `scripts/`

Item 4 of the 20260428 pre-release cleanup plan.

## Method

1. Located every `GH_SYNC=false` (or default-`false`) initializer and every
   `GH_SYNC == false` / `!= true` branch in `scripts/`:

   ```
   rg -n 'GH_SYNC=false|GH_SYNC.*false' scripts/
   ```

2. Located every call site of `gh_config_bool sync`, which is the only
   thing that flips `GH_SYNC` from its default `false` to `true`:

   ```
   rg -n 'gh_config_bool sync' scripts/
   ```

   Hits:
   - `scripts/orch-run.sh:119` — guards `GH_SYNC=true`
   - `scripts/orch-run.sh:195` — guards auto-issue creation
   - `scripts/plan-issue.sh:56`

3. Inspected `gh_config_bool` (defined at `scripts/read-github-config.sh:51`).
   It returns `true` only when `gh_config_value <key>` prints the literal
   string `true`, i.e. when `dega-core.yaml` contains `github.sync: true`.
   In every other case (key absent, `false`, missing config file) it
   returns non-zero, so `GH_SYNC` keeps its `${GH_SYNC:-false}` default.

4. For each `GH_SYNC == false` branch, judged reachability against that
   default-path. The conductor scripts are reusable by downstream
   projects that may have `github.sync: false` or no `github` block at
   all; the `false` branches are the documented local-only path.

## Findings

| file:line | branch description | verdict | rationale |
|---|---|---|---|
| `scripts/orch-run.sh:118` | `GH_SYNC=false` initializer before `gh_config_bool sync` check | REACHABLE | Default value; held when `github.sync` is unset or `false` in `dega-core.yaml`. Flipped to `true` at L120 only when the config opts in. |
| `scripts/orch-run.sh:127` (else of L124 `if GH_SYNC==true`) | `PLAN_DIR=docs/exec-plans/active/${SLUG}` | REACHABLE | Local-mode plan path used by projects without `github.sync: true`. |
| `scripts/orch-run.sh:163-167` (else of L160 `if GH_SYNC==true`) | copy fetched plan into `docs/exec-plans/active/` | REACHABLE | Executed when `--issue N` is passed in a project that has not enabled `github.sync`. The script fetches via `gh-plan-fetch.sh` regardless of sync mode, so this copy step is on the live local path. |
| `scripts/orch-run.sh:178` | `if FROM_ISSUE==false && GH_SYNC==false` — uncommitted-plan guard | REACHABLE | Guard fires for purely-local runs (no `--issue`, no `github.sync: true`). Both clauses must be false; both are achievable when `gh_config_bool sync` returns non-zero and the user did not pass `--issue`. |
| `scripts/orch-verify.sh:36` | `GH_SYNC="${GH_SYNC:-false}"` initializer | REACHABLE | Default when `orch-verify.sh` is invoked outside an `orch-run.sh` parent that exports `GH_SYNC=true`. Manual reruns or projects with sync disabled hit this. |
| `scripts/orch-verify.sh:49-52` (elif/else of L47 `if GH_SYNC==true`) | resolve `PLAN_DIR` from `docs/exec-plans/active/` (worktree, then repo root) | REACHABLE | Local-mode resolution used whenever `GH_SYNC != true`. |
| `scripts/orch-parse-items.sh:26` | `GH_SYNC="${GH_SYNC:-false}"` initializer | REACHABLE | Same default-path argument as above; `orch-parse-items.sh` is also called directly by `orch-run.sh init_state` and by tests. |
| `scripts/orch-parse-items.sh:31` (else of L28 `if GH_SYNC==true`) | `PLAN_DIR=docs/exec-plans/active/${SLUG}` | REACHABLE | Local-mode parse path. |
| `scripts/orch-review.sh:30` | `GH_SYNC="${GH_SYNC:-false}"` initializer | REACHABLE | Default when invoked outside `orch-engine.sh`'s `GH_SYNC=...` env, e.g. manual reruns. |
| `scripts/orch-review.sh:42-45` (elif/else of L40 `if GH_SYNC==true`) | resolve `PLAN_DIR` from `docs/exec-plans/active/` | REACHABLE | Local-mode resolution. |
| `scripts/orch-engine.sh:67` | `GH_SYNC="${GH_SYNC:-false}"` initializer | REACHABLE | Default-path, retained when invoked from a non-sync project or directly for testing. |
| `scripts/orch-engine.sh:87` (else of L84 `if GH_SYNC==true`) | `PLAN_DIR=${WORKTREE_DIR}/docs/exec-plans/active/${SLUG}` | REACHABLE | Local-mode plan path used by the engine when sync is off. |

## Verdict

No `GH_SYNC=false` branch in `scripts/` is dead. The five scripts
(`orch-run.sh`, `orch-engine.sh`, `orch-verify.sh`, `orch-review.sh`,
`orch-parse-items.sh`) intentionally support both modes:

- `GH_SYNC=true` — plans live under `.orchestrator/plans/<slug>/`,
  enabled by `github.sync: true` in `dega-core.yaml`.
- `GH_SYNC=false` (default) — plans live under
  `docs/exec-plans/active/<slug>/`, used by projects that have not
  opted in to GitHub-issue plans.

Although `dega-core.yaml` in *this* repository sets `github.sync: true`
(so workers running here always take the `true` branch), the scripts
are part of the conductor toolkit installed into other repositories via
`/apply-core`. Those downstream repositories may legitimately operate
in local mode, and the bats suite under `tests/orch/` also exercises
the `false` branches. Removing them would break downstream installs
and the test suite.

**Recommendation:** keep all `GH_SYNC=false` branches. No deletions
warranted.
