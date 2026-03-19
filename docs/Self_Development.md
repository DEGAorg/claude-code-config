# Self-Development Guide

How to apply fixes and new features to this repo. Covers the full lifecycle
from plan to ship, using manual workflows, the orchestrator, or the planner loop.

---

## Quick Start

Every change follows three steps:

1. **Plan** — create an exec-plan with `/plan`
2. **Implement** — work the plan (manually, orchestrator, or planner loop)
3. **Ship** — review passes, plan archives to `completed/`, commit lands

```bash
# 1. Create a plan
claude "/plan add pre-commit hook for shellcheck"

# 2. Run the plan (pick one)
bash scripts/orch-run.sh 20260315-add-shellcheck-hook      # parallel workers
bash scripts/orch-run.sh 20260315-add-shellcheck-hook --max-workers 1  # sequential

# Or let the planner pick work autonomously from focus.yaml
bash scripts/planner-loop.sh                               # autonomous

# 3. Done — the orchestrator commits and archives on SHIP
```

---

## Planning

Plans are first-class artifacts stored in `docs/exec-plans/active/<slug>/plan.md`.
They persist through completion and inform future work.

### Creating a plan

Use the `/plan` command inside Claude Code:

```
/plan <brief description of the task>
```

This creates a dated directory (e.g. `docs/exec-plans/active/20260315-add-shellcheck-hook/`)
containing `plan.md` with these sections:

| Section | Purpose |
|---------|---------|
| Requirements | What must be true when done |
| Approach | How to implement it |
| Files to touch | Which files change and why |
| Risks and open questions | Blockers to resolve before work starts |
| Progress log | Checkboxes — one per work item |
| Decision log | Choices made and alternatives considered |
| Completion criteria | Verifiable conditions for SHIP |

### Plan lifecycle

```
active/<slug>/plan.md    →  worker checks off items
                         →  reviewer evaluates
                         →  SHIP: move to completed/<slug>/
```

Plans in `active/` are in progress. Plans in `completed/` are done. No plan is
deleted — the history is the audit trail.

---

## Implementation Methods

### Manual

Read the plan, implement each item, check the boxes, commit.

```bash
# Read the plan
cat docs/exec-plans/active/20260315-my-task/plan.md

# Work through items, checking boxes as you go
# Run linters and tests
shellcheck scripts/*.sh
shfmt -d scripts/*.sh

# Commit when done
git add -A && git commit -m "complete 20260315-my-task"
mv docs/exec-plans/active/20260315-my-task docs/exec-plans/completed/
```

Use manual when: you want full control, the task is exploratory, or you need
to make decisions that require human judgment at every step.

### Orchestrator

The orchestrator runs plan items in parallel using tmux panes, each with its
own git worktree. It is designed for plans with independent items that can be
worked simultaneously.

```bash
bash scripts/orch-run.sh <slug> [--max-workers N] [--max-iterations N] [--background]
```

**Options:**

| Flag | Default | Description |
|------|---------|-------------|
| `--max-workers` | 4 | Max concurrent worker panes |
| `--max-iterations` | 3 | Max review/rework cycles |
| `--background` | off | Headless mode — tmux only, no display |

**How it works:**

1. Parses plan items and builds a dependency graph (items with `depends:` wait)
2. Spawns up to N workers in parallel, each in its own worktree
3. Each worker executes one item, writes a done-file, marks `[x]`
4. When all items finish, runs a review pass
5. SHIP: commit and archive. REVISE: re-run failed items with reviewer feedback

For sequential execution (one item at a time), use `--max-workers 1`.

### Planner Loop

The planner loop is a fully autonomous agent that runs for hours unattended. It
reads a `focus.yaml` config, decides what to work on next, creates execution
plans, launches the orchestrator, monitors completion, and repeats — until the
budget is exhausted or all focus areas are addressed.

```bash
bash scripts/planner-loop.sh
```

**How it works:**

1. Reads `focus.yaml` from the repo root (re-reads each iteration so you can
   edit focus mid-run)
2. ASSESS — spawns `claude -p` with `agents/planner-assess.md` to evaluate
   tech-debt, quality grades, active plans, and focus areas. Outputs a JSON
   decision: `create_plan` with a slug, or `done`
3. PLAN — spawns `claude -p` with `agents/planner-writer.md` to write a
   complete `plan.md` for the chosen task
4. COMMIT — git adds and commits the new plan
5. EXECUTE — launches `orch-run.sh --background` to run the plan
6. MONITOR — polls orchestrator `state.json` until completed or failed
7. BUDGET CHECK — increments plan counter, checks failure counter and credit
   exhaustion signals. Loops back to step 1 or exits

**Focus config** (`focus.yaml` at repo root, gitignored):

```yaml
description: |
  Focus on infrastructure hardening. Fix broken test suites first,
  then split oversized files.

areas:
  - area: broken-orch-tests
    priority: high
    source: tech-debt
    context: >
      test-orch-e2e.sh uses old API. Needs rewrite.

budget:
  max_plans: 5
  max_consecutive_failures: 2
  cooldown_seconds: 30
```

**Budget guards:**

| Guard | Trigger | Behavior |
|-------|---------|----------|
| Plan counter | `max_plans` reached | Clean exit |
| Failure counter | `max_consecutive_failures` consecutive orch failures | Clean exit |
| Credit exhaustion | `claude -p` exits with rate-limit/credit/billing error | Clean exit |

**Key differences from Orchestrator:**

- Planner loop decides *what* to work on; orchestrator decides *how* to execute
- Planner creates plans autonomously; orchestrator executes existing plans
- Planner runs across multiple plans over hours; orchestrator runs one plan
- Planner uses the orchestrator as its execution engine

---

## When to Use What

| Scenario | Method | Why |
|----------|--------|-----|
| Single focused task, 1-3 items | Orchestrator (`--max-workers 1`) | Sequential execution, simple setup |
| Multi-item plan, items are independent | Orchestrator | Parallel execution, faster wall-clock time |
| Exploratory work, unclear scope | Manual | You need human judgment at each step |
| Quick fix, one file | Manual | Overhead of a loop isn't worth it |
| AFK batch run, single plan | Orchestrator | Runs unattended until SHIP or budget exhausted |
| AFK batch run, multiple plans | Planner Loop | Autonomously picks work, creates plans, executes them |
| Items have complex dependencies | Orchestrator | Supports `depends:` declarations |
| Long unattended session (hours) | Planner Loop | Budget guards handle credit exhaustion and failures |
| Modifying the orchestrator itself | Manual | Orch can't safely modify its own scripts mid-run |

---

## Common Tasks

### Adding a new hook

1. Create the script in `hooks/` (e.g. `hooks/my-hook.sh`)
2. Add the hook entry to `settings.json` under the appropriate event
3. Add a test in `tests/` that exercises the hook
4. Run `shellcheck hooks/my-hook.sh && shfmt -d hooks/my-hook.sh`

### Fixing a bug

1. `/plan fix: <description of the bug>`
2. Run `bash scripts/orch-run.sh <slug>` — orchestrator handles implement + review
3. The orchestrator commits on SHIP

### Adding a skill

1. Write the skill markdown in `skills/<name>.md`
2. Reference it from `CLAUDE.md` repo map if it's a core skill
3. For Canon-specific skills, put it in `canon/skills/` instead

### Adding a command

1. Write the command markdown in `commands/<name>.md`
2. Follow the existing command format (description, arguments, steps)
3. Update `CLAUDE.md` repo map

### Modifying the orchestrator

1. `/plan <description>`
2. Use manual workflow — not the orchestrator (it can't modify itself safely)
3. Test with a small plan before running on real work

---

## Troubleshooting

### Orchestrator worker fails

Check the done-file at `.orchestrator/done/<slug>/item-N.txt` — it contains
the worker's summary or blocker description. Failed items are re-run with
reviewer feedback on the next iteration.

### Plan items not checking off

Workers mark `[x]` in `plan.md` as they complete items. If checkboxes aren't
being checked, the worker may be failing before it reaches the checkpoint step.
Read the worker output in the tmux pane or the iteration archive.

### Health check failures

Health checks are defined in `dega-core.yaml` under `success_criteria`.
Common failures:

| Check | Fix |
|-------|-----|
| `shellcheck` | Fix lint errors in `scripts/` and `hooks/` |
| `shfmt` | Run `shfmt -w scripts/*.sh hooks/*.sh` |
| `actionlint` | Fix workflow issues in `.github/workflows/` |
| `no-todos` | Remove TODO/FIXME from `commands/`, `skills/`, `hooks/` |

### Resuming after interruption

The orchestrator is resume-safe. The plan file tracks progress via checkboxes.
Re-running the same command picks up where it left off — already checked items
are skipped.

---

## Appendix: Legacy — Ralph Loop

> **Note:** The Ralph Loop is superseded by the orchestrator. It still works
> but is no longer recommended. Use the orchestrator for all new work.

The Ralph Loop spawns worker and reviewer agents in sequence. The worker
implements plan items one at a time; the reviewer evaluates each item against
the plan criteria. The loop repeats until the reviewer outputs SHIP or the
iteration budget is exhausted.

```bash
bash scripts/ralph-loop.sh <slug>
```

**How it works:**

1. Worker reads `plan.md`, finds the next unchecked `[ ]` item, implements it,
   marks `[x]`, writes a context handoff for the next item
2. Repeats until all items are checked
3. Structural checks run (all checkboxes checked? health check passes?)
4. Per-item reviewer evaluates each completed item
5. If all pass: SHIP — archive plan, commit, play sound
6. If any fail: REVISE — write feedback, worker re-runs failed items
7. If no file changes in 2 consecutive iterations: STAGNATED — stop for human

**Configuration** in `dega-core.yaml` at the repo root:

```yaml
max_iterations: 3          # budget cap
budget:
  warn_at_iteration: 2     # alert when approaching limit
```

**State files** written during execution:

| File | Purpose |
|------|---------|
| `plan.md` | Source of truth — checkboxes track progress |
| `.ralph-state.json` | Machine-readable loop state |
| `context-handoff.txt` | Passes context between items within one iteration |
| `review-feedback.txt` | Reviewer notes for REVISE iterations |
| `review-result.txt` | SHIP, REVISE, or BLOCKED |
| `reviews/item-N-review.txt` | Per-item reviewer verdict |
| `iterations/NNN/` | Archived state from previous iterations |

**Exit codes:**

| Code | Meaning |
|------|---------|
| 0 | SHIP — all items passed review |
| 1 | Exhausted — max iterations reached without SHIP |
| 2 | Stagnated or blocked — human action required |

**Troubleshooting:**

- **Stagnates (exit code 2):** No file changes across 2 consecutive iterations.
  Read `review-feedback.txt` and the last `iterations/NNN/` archive to understand
  the blocker. Manually unblock, then re-run.
- **Exhausts iterations (exit code 1):** Budget ran out before reviewer approved.
  Check `review-feedback.txt` for the last REVISE reason. Fix manually, increase
  `max_iterations` in `dega-core.yaml`, or re-run.
