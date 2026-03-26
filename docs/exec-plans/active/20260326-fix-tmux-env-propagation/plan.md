# Fix tmux environment variable propagation

**Source:** `ace/notes/linux-issues.md` issues 2-3
**Analysis:** `ace/notes/linux-issues-analysis.md`

## Problem

When `orch-run.sh` exports `GH_SYNC=true` and spawns the engine via
`tmux new-window`, the engine does not inherit the variable. tmux windows
are spawned by the tmux server process, not as direct children of
`orch-run.sh`, so `export` alone is insufficient.

The engine defaults `GH_SYNC` to `false`, resolves the plan path to
`docs/exec-plans/active/` instead of `.orchestrator/plans/`, fails to find
`plan.md`, and exits. All downstream workers never spawn.

## Approach

Belt-and-suspenders: use `tmux set-environment` to inject vars into the
session (covers all windows), AND prefix inline env vars on the engine
command string (covers direct invocation from a different tmux window).

Apply the same pattern to all orchestrator env vars that cross the
tmux boundary: `GH_SYNC`, `REPO_ROOT`, `SLUG`, `ORCH_STATE_DIR`.

Also audit `orch-review.sh` and `orch-verify.sh` which are spawned
similarly and read `GH_SYNC` from environment.

## Requirements

1. Engine, reviewer, and verifier must receive `GH_SYNC` regardless of how
   tmux was started or whether the server pre-existed.
2. No behavior change when `GH_SYNC=false` (non-GitHub mode).
3. All existing orchestrator tests must still pass.
4. `orch-engine.sh` must work when invoked directly (not via `orch-run.sh`)
   with `GH_SYNC` exported in the caller's shell.

## Progress log

- [ ] Add `tmux set-environment` calls in `orch-run.sh` after session creation for `GH_SYNC`, `REPO_ROOT`, `SLUG`, `ORCH_STATE_DIR`
- [ ] Prefix engine tmux command with inline `GH_SYNC="${GH_SYNC}"` (deps: 1)
- [ ] Prefix reviewer spawn command in `orch-engine.sh` with inline `GH_SYNC` (deps: 1)
- [ ] Prefix verifier spawn command in `orch-engine.sh` with inline `GH_SYNC` (deps: 1)
- [ ] Add diagnostic log line at engine startup: `echo "orch-engine: GH_SYNC=${GH_SYNC}"` (deps: 2)
- [x] Test: run orch with GH_SYNC=true, verify engine sees it in log output (deps: 5)

## Completion criteria

- [ ] `GH_SYNC=true` is visible in engine startup log when `dega-core.yaml` has `github.sync: true`
- [ ] Engine resolves plan path to `.orchestrator/plans/` when `GH_SYNC=true`
- [ ] Reviewer and verifier also see `GH_SYNC=true`
- [ ] shellcheck passes on all modified scripts
