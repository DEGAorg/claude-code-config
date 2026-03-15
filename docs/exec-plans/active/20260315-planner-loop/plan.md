# Plan: Autonomous planner loop — long-running agent that plans and executes

**Status:** In progress
**Created:** 2026-03-15

## Requirements

Build a planner loop that runs for hours unattended. It reads a focus config,
decides what to work on next, creates execution plans, launches the
orchestrator, monitors completion, and repeats — until the budget is
exhausted or all focus areas are addressed.

The loop replaces the manual cycle of: check status → read tech debt →
decide next plan → write plan.md → run orch → wait → repeat.

## Architecture

```
planner-loop.sh (outer bash loop, runs for hours)
│
├── 1. ASSESS — spawn short claude -p to read focus.yaml, tech-debt.md,
│               active plans, QUALITY.md → outputs a JSON decision
├── 2. PLAN   — spawn short claude -p to write plan.md for the chosen task
├── 3. COMMIT — git add + commit the new plan
├── 4. EXECUTE — launch orch-run.sh (parallel workers, review, SHIP)
├── 5. MONITOR — poll orch state.json until plan completes or fails
├── 6. BUDGET CHECK — increment plan counter, check credit limit signal
└── 7. LOOP   — go to step 1
```

Each Claude invocation is a fresh `claude -p` with a focused prompt.
No single instance runs for hours — the bash script is the long-lived
process, Claude instances are short-lived tools it invokes.

## Focus config (focus.yaml)

YAML is the right format because:
- **Structured priorities** — areas have explicit priority ordering that a
  plain text description can't express unambiguously
- **Machine-parseable constraints** — `max_plans`, `skip_areas` are read by
  the bash loop directly via `yq`, not just by Claude
- **Composable** — can merge a project-level focus.yaml with the global one
- **Consistent** — matches `dega-core.yaml` format already used by the harness
- **Diffable** — changes to focus are trackable in git

### Schema

```yaml
# focus.yaml — what the planner loop should work on
version: 1

# Natural language guidance for the planner agent. This is the primary
# input — the planner reads this to understand intent, priorities, and
# constraints that don't fit neatly into structured fields.
description: |
  Focus on infrastructure hardening. Fix broken test suites first (P1),
  then split oversized files (P2). Skip canon template work for now.

# Structured priority list — planner uses this alongside the description.
# Each area maps to a module or subsystem. Priority controls ordering.
# Context gives the planner enough info to create a plan without reading
# every file in the area.
areas:
  - area: broken-orch-tests
    priority: high
    source: tech-debt  # where this came from (tech-debt, quality, manual)
    context: >
      test-orch-e2e.sh and test-orch-stale-detection.sh use old API.
      Need rewrite for multi-plan directory structure.
  - area: orch-state-splitting
    priority: medium
    source: tech-debt
    context: >
      orch-state.sh is 822 lines. Split into orch-worktree.sh,
      orch-registry.sh, orch-query.sh.

# Hard constraints read by the bash loop (not by Claude)
budget:
  max_plans: 5              # stop after completing this many plans
  max_consecutive_failures: 2  # stop if N plans fail in a row
  cooldown_seconds: 30      # pause between plans (rate limiting)
```

The `description` field is the most important — it's free-form guidance
that the planner agent reads as its primary directive. The `areas` list
gives structure but the description can override or supplement it.

### Where focus.yaml lives

- **Per-repo:** `focus.yaml` at repo root (gitignored — personal focus)
- **Planner reads:** `focus.yaml` in the repo where it's launched
- **Fallback:** if no `focus.yaml` exists, planner reads `tech-debt.md`
  and `QUALITY.md` and picks the highest-severity item

## Budget and credit limits

The planner loop needs to stop gracefully. Three mechanisms:

1. **Plan counter** — `budget.max_plans` in focus.yaml. The bash loop
   increments a counter after each completed plan. When it hits the max,
   the loop exits cleanly.

2. **Failure counter** — `budget.max_consecutive_failures`. If the orch
   fails (worker errors, review rejects after max iterations), increment
   a failure counter. Reset on success. Stop if it hits the max.

3. **Credit exhaustion detection** — when `claude -p` exits with a
   non-zero status during the ASSESS or PLAN phase, check stderr for
   credit/rate-limit signals. If detected, the loop prints a message
   and exits. This handles the "session limit reached" case naturally —
   the next `claude -p` call fails and the loop stops.

## Approach

### planner-loop.sh

The main script. Bash loop that orchestrates the assess → plan → execute
cycle. Reads `focus.yaml` for constraints. Spawns `claude -p` for
decisions. Launches `orch-run.sh` for execution.

Key behaviors:
- Reads `focus.yaml` at loop start (re-reads each iteration so you can
  edit focus mid-run)
- Skips plans that already exist in `docs/exec-plans/active/`
- Logs each cycle to `~/.claude/planner/<timestamp>.log`
- Plays a sound on completion (all plans done) or failure (budget hit)

### agents/planner-assess.md

Agent prompt for the ASSESS phase. Given the focus config, tech debt,
quality grades, and active plans, it outputs a JSON decision:

```json
{
  "action": "create_plan",
  "slug": "fix-orch-test-suites",
  "title": "Fix broken orchestrator test suites for multi-plan API",
  "rationale": "P1 debt item, blocking test coverage for orch changes",
  "focus_area": "broken-orch-tests"
}
```

Or if nothing to do:
```json
{
  "action": "done",
  "rationale": "All focus areas addressed"
}
```

### agents/planner-writer.md

Agent prompt for the PLAN phase. Given the slug, title, rationale, and
relevant context files, it writes a complete `plan.md` following the
exec-plan format (requirements, approach, files to touch, progress log,
completion criteria).

### Integration with existing infra

- Uses `orch-run.sh` as-is for execution (no changes needed)
- Uses `create-exec-plan.sh` to scaffold the plan directory
- Reads `dega-core.yaml` for `poll_interval_seconds`
- Reads tech-debt.md, QUALITY.md, REGISTRY.md via existing skill patterns
- Planner state (logs, cycle history) goes to `~/.claude/planner/`

## Files to create

| File | Purpose |
|------|---------|
| `scripts/planner-loop.sh` | Main loop script |
| `agents/planner-assess.md` | Assessment agent prompt |
| `agents/planner-writer.md` | Plan-writing agent prompt |
| `focus.yaml` | Example focus config for this repo |
| `.gitignore` | Add `focus.yaml` entry |

## Files to update

| File | Change |
|------|--------|
| `CLAUDE.md` | Add planner-loop to repo map and scripts section |
| `README.md` | Add planner-loop to usage docs |
| `docs/Self_Development.md` | Add planner loop as a workflow option |
| `dega-core.yaml` | Add `planner` section (optional poll interval override) |

## Progress log

- [x] Create `agents/planner-assess.md` — assessment agent prompt with JSON output schema (deps: none)
- [x] Create `agents/planner-writer.md` — plan-writing agent prompt (deps: none)
- [x] Create `scripts/planner-loop.sh` — main loop: read focus, assess, plan, execute, monitor, budget check (deps: 1, 2)
- [x] Create `focus.yaml` example for this repo with current tech debt priorities (deps: none)
- [x] Add `focus.yaml` to `.gitignore` (deps: none)
- [x] Update `CLAUDE.md` repo map and Self_Development.md with planner loop workflow (deps: 3)
- [x] Run shellcheck on `scripts/planner-loop.sh` (deps: 3)
- [x] End-to-end test: run planner-loop.sh with max_plans=1, verify it assesses, plans, and launches orch (deps: 3, 4)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Bash outer loop + short claude -p calls | Single long-running claude session | No context window exhaustion, each call is fresh and focused |
| focus.yaml (YAML) | Plain text description, JSON, TOML | Matches dega-core.yaml convention, structured + human-readable, yq-parseable by bash |
| focus.yaml gitignored | Tracked in repo | Focus is personal/session-specific, not project architecture |
| Credit detection via exit code | API usage tracking, token counting | Simple — when claude -p fails, the loop stops. No need to track internals |
| Planner state in ~/.claude/planner/ | In repo, in .orchestrator/ | Ephemeral state, not project-specific |
| Re-read focus.yaml each iteration | Read once at start | Allows editing focus mid-run without restarting |

## Risks and open questions

- **Plan quality:** The planner-writer agent creates plans without human
  review. Mitigation: orch has its own review step, and plans are committed
  to git so they can be inspected. The `max_consecutive_failures` guard
  stops runaway bad plans.

- **Credit detection accuracy:** `claude -p` may exit non-zero for reasons
  other than credit exhaustion (network errors, transient failures).
  Mitigation: check stderr for specific patterns (`rate_limit`, `credit`,
  `billing`). On ambiguous failures, count toward the failure budget rather
  than hard-stopping.

- **Focus drift:** The planner might repeatedly create plans for the same
  area if it doesn't track what was already attempted. Mitigation: the
  ASSESS prompt includes the list of active and recently-completed plans
  from REGISTRY.md. The planner sees what's been done.

## Completion criteria

- [ ] `planner-loop.sh` runs end-to-end: reads focus.yaml, spawns assess agent, creates plan, launches orch, monitors completion
- [ ] Budget guard stops the loop after `max_plans` completed plans
- [ ] Failure guard stops after `max_consecutive_failures` consecutive failures
- [ ] Credit exhaustion detected and exits cleanly
- [ ] `focus.yaml` schema documented and example provided
- [ ] `shellcheck` passes on planner-loop.sh
