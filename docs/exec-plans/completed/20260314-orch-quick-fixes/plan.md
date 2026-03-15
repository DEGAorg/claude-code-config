# Plan: Orch/Ralph quick fixes

**Status:** In progress
**Created:** 2026-03-14

## Requirements

- `orch-run.sh` checks for required tools (`jq`, `tmux`, `node`) at startup with clear error messages
- `orch-run.sh` accepts `--max-iterations N` flag, passed through to `orch-engine.sh` and into state.json
- `orch-engine.sh` accepts `--max-iterations N` flag, uses it in state init instead of hardcoded `${MAX_ITERATIONS:-3}`
- `ralph-loop.sh` uses `mktemp` instead of hardcoded `/tmp/ralph_*.tmp` paths (4 occurrences)
- Ghost directory `docs/exec-plans/active/20260313-orch-stale-worker-detection/` removed

## Approach

Four independent fixes, all surgical:

1. **Dependency check** — add a function `check_deps()` near the top of `orch-run.sh` that verifies `jq`, `tmux`, `node` are on PATH. Print which tool is missing and exit 1.

2. **MAX_ITERATIONS flag** — add `--max-iterations` to the arg parser in both `orch-run.sh` and `orch-engine.sh`. `orch-run.sh` passes it through to the engine command line. `orch-engine.sh` doesn't use it directly yet, but `orch-run.sh` uses it in `init_state()` (line 105, currently `${MAX_ITERATIONS:-3}`). Wire the parsed value into the variable.

3. **mktemp in ralph-loop.sh** — replace 4 occurrences of `/tmp/ralph_*.tmp` with `mktemp` calls. Each is a jq-filter-to-file-then-mv pattern. Use `mktemp "${TASK_DIR}/.ralph-XXXXXX"` to keep temp files colocated with state.

4. **Ghost directory** — delete the empty `active/20260313-orch-stale-worker-detection/` directory.

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-run.sh` | Add `check_deps()`, add `--max-iterations` arg parsing, pass to engine |
| `scripts/orch-engine.sh` | Add `--max-iterations` arg parsing, pass to state (future use) |
| `scripts/ralph-loop.sh` | Replace 4x `/tmp/ralph_*.tmp` with `mktemp` |
| `docs/exec-plans/active/20260313-orch-stale-worker-detection/` | Delete empty directory |

## Risks and open questions

- None — all changes are straightforward and low-risk.

## Progress log

- [x] Add dependency check (`jq`, `tmux`, `node`) to `orch-run.sh`
- [x] Add `--max-iterations N` flag to `orch-run.sh` and `orch-engine.sh`, wire into state init
- [x] Replace 4x `/tmp/ralph_*.tmp` with `mktemp` in `ralph-loop.sh`
- [x] Remove ghost directory `docs/exec-plans/active/20260313-orch-stale-worker-detection/`

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| `mktemp` in TASK_DIR | `mktemp` in system tmpdir | Colocated temp files are easier to debug and clean up if interrupted |
| Check deps in orch-run.sh only | Check in orch-engine.sh too | orch-run.sh is the entry point; if it passes, engine will too |

## Completion criteria

- [ ] `orch-run.sh` exits with clear error when `jq`/`tmux`/`node` missing
- [ ] `orch-run.sh --max-iterations 5` sets maxIterations to 5 in state.json
- [ ] No `/tmp/ralph_` references remain in `ralph-loop.sh`
- [ ] `shellcheck scripts/orch-run.sh scripts/orch-engine.sh scripts/ralph-loop.sh` clean
