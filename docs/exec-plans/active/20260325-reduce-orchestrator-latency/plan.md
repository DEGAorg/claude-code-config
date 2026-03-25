# Plan: Reduce Orchestrator Latency — Timer Optimization and Context Pre-Hydration

**Status:** Draft
**Created:** 2026-03-25

## Requirements

- Reduce idle polling time across engine, review, and verify phases by introducing per-phase poll intervals
- Reduce engine poll_interval_seconds default from 30s to 15s
- Add separate `review_poll_interval_seconds` (default 10s) and `verify_poll_interval_seconds` (default 10s) config keys
- Reduce post-exit tmux sleep from 5s to 2s in all agent spawn commands
- Worker prompts must include pre-hydrated context: file paths mentioned in the plan item, check command, success criteria, and the plan's requirements section
- Workers should NOT need to read the full plan.md to understand what "done" looks like
- All changes must pass `shellcheck -e SC1091`
- No behavioral regressions — existing orchestrator flows (SHIP, REVISE, verify) must work identically

## Approach

### Phase 1: Timer optimization

Three independent changes to reduce idle wait time:

1. **dega-core.yaml** — Add `review_poll_interval_seconds` and `verify_poll_interval_seconds` keys. Reduce `poll_interval_seconds` from 30 to 15.
2. **orch-review.sh** — Read `review_poll_interval_seconds` instead of `poll_interval_seconds`, defaulting to 10s. Change `sleep 5` to `sleep 2` in the reviewer tmux spawn.
3. **orch-verify.sh** — Read `verify_poll_interval_seconds` instead of `poll_interval_seconds`, defaulting to 10s. Change `sleep 5` to `sleep 2` in the verifier tmux spawn.
4. **orch-engine.sh** — Change `sleep 5` to `sleep 2` in the worker tmux spawn.

The `orch_read_config()` helper in orch-state.sh already supports arbitrary key names, so no changes needed there.

### Phase 2: Worker context pre-hydration

Implement patterns 1 and 4 from `agent-context-patterns.md`:

5. **orch-state.sh** — Add two new helper functions:
   - `orch_extract_file_paths()` — Extracts backtick-quoted file paths and bare `path/file.ext` patterns from text. Returns one path per line.
   - `orch_extract_plan_sections()` — Extracts the `## Requirements` and `## Completion criteria` sections from a plan.md file. Also reads `check_command` from dega-core.yaml.

6. **orch-engine.sh `build_worker_prompt()`** — Call the new helpers to build a `## Task Context (pre-gathered by orchestrator)` section containing:
   - The item's file paths (extracted from description + plan approach)
   - The plan's requirements section (so workers know what "done" looks like)
   - The check command from dega-core.yaml
   - The completion criteria from plan.md
   - Cap the injected section at ~200 lines to avoid bloat

7. **agents/orch-worker.md** — Add a section documenting the pre-hydrated context. Instruct workers to use provided file paths and check command instead of discovering them, and to read the full plan only if the pre-hydrated context is insufficient.

## Files to touch

| File | Change |
|------|--------|
| `dega-core.yaml` | Add `review_poll_interval_seconds: 10`, `verify_poll_interval_seconds: 10`; change `poll_interval_seconds` from 30 to 15 |
| `scripts/orch-review.sh` | Read `review_poll_interval_seconds`; reduce sleep 5 to 2 |
| `scripts/orch-verify.sh` | Read `verify_poll_interval_seconds`; reduce sleep 5 to 2 |
| `scripts/orch-engine.sh` | Reduce sleep 5 to 2; update `build_worker_prompt()` to inject pre-hydrated context |
| `scripts/orch-state.sh` | Add `orch_extract_file_paths()` and `orch_extract_plan_sections()` helpers |
| `agents/orch-worker.md` | Add pre-hydrated context section and instructions |

## Risks and open questions

- File path extraction regex may produce false positives on non-path text — mitigate by only extracting paths that contain `/` and a file extension
- Pre-hydrated context may exceed ~200 lines on plans with very detailed requirements — cap with `head` and add a note that the full plan is available at the plan path

## Progress log

- [x] Add `review_poll_interval_seconds: 10` and `verify_poll_interval_seconds: 10` to `dega-core.yaml`; reduce `poll_interval_seconds` from 30 to 15
- [x] Update `scripts/orch-review.sh`: read `review_poll_interval_seconds` with 10s fallback; change `sleep 5` to `sleep 2` in reviewer tmux spawn (deps: 1)
- [x] Update `scripts/orch-verify.sh`: read `verify_poll_interval_seconds` with 10s fallback; change `sleep 5` to `sleep 2` in verifier tmux spawn (deps: 1)
- [x] Update `scripts/orch-engine.sh`: change `sleep 5` to `sleep 2` in worker tmux spawn command (deps: 1)
- [x] Add `orch_extract_file_paths()` and `orch_extract_plan_sections()` helper functions to `scripts/orch-state.sh` (deps: 1)
- [ ] Update `build_worker_prompt()` in `scripts/orch-engine.sh` to call new helpers and inject pre-hydrated context (file paths, requirements, check command, completion criteria) into the worker prompt (deps: 4, 5)
- [ ] Update `agents/orch-worker.md` to document pre-hydrated context sections and instruct workers to use provided context before discovering on their own (deps: 6)
- [ ] Run `shellcheck -e SC1091` on all modified scripts (`scripts/orch-engine.sh`, `scripts/orch-review.sh`, `scripts/orch-verify.sh`, `scripts/orch-state.sh`) and fix any issues (deps: 2, 3, 6, 7)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Separate poll intervals per phase | Single global poll interval | Review/verify agents finish faster than workers; aggressive polling saves time without CPU cost |
| Extract file paths via regex in bash | Parse plan AST, use jq | Bash regex is simple, adequate for backtick paths and `path/file.ext` patterns; no new dependencies |
| Inject requirements + completion criteria (not full plan) | Inject full plan, inject nothing | Full plan wastes context; requirements + criteria give workers enough to know what "done" looks like |
| Cap pre-hydrated context at ~200 lines | No cap, token-based cap | Line count is simple to enforce in bash; 200 lines ~= 3-4K tokens, well under the 5K guideline |

## Completion criteria

- [ ] `shellcheck -e SC1091 scripts/orch-engine.sh scripts/orch-review.sh scripts/orch-verify.sh scripts/orch-state.sh` passes with no errors
- [ ] `shfmt -d scripts/orch-engine.sh scripts/orch-review.sh scripts/orch-verify.sh scripts/orch-state.sh` shows no formatting diff
- [ ] `dega-core.yaml` contains `review_poll_interval_seconds` and `verify_poll_interval_seconds` keys
- [ ] `orch-review.sh` reads `review_poll_interval_seconds` (grep confirms the string appears in the script)
- [ ] `orch-verify.sh` reads `verify_poll_interval_seconds` (grep confirms the string appears in the script)
- [ ] No `sleep 5` remains in `scripts/orch-engine.sh`, `scripts/orch-review.sh`, or `scripts/orch-verify.sh`
- [ ] `build_worker_prompt()` output includes a `## Task Context` section with file paths, check command, and completion criteria
- [ ] `agents/orch-worker.md` contains instructions for using pre-hydrated context
