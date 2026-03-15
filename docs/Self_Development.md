# Self-Development Guide

How to apply fixes and new features to this repo. Covers the full lifecycle
from plan to ship, using manual workflows, the Ralph Loop, or the orchestrator.

---

## Quick Start

Every change follows three steps:

1. **Plan** — create an exec-plan with `/plan`
2. **Implement** — work the plan (manually, Ralph Loop, or orchestrator)
3. **Ship** — review passes, plan archives to `completed/`, commit lands

```bash
# 1. Create a plan
claude "/plan add pre-commit hook for shellcheck"

# 2. Run the plan (pick one)
bash scripts/ralph-loop.sh 20260315-add-shellcheck-hook   # sequential
bash scripts/orch-run.sh 20260315-add-shellcheck-hook      # parallel

# 3. Done — the loop commits and archives on SHIP
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

### Ralph Loop

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

**Key differences from Ralph Loop:**

- Workers run in parallel (Ralph is sequential)
- Each worker gets its own worktree (Ralph works in the main tree)
- Items can declare dependencies on other items
- Uses tmux for process management and display

---

## When to Use What

| Scenario | Method | Why |
|----------|--------|-----|
| Single focused task, 1-3 items | Ralph Loop | Sequential is simpler, no worktree overhead |
| Multi-item plan, items are independent | Orchestrator | Parallel execution, faster wall-clock time |
| Exploratory work, unclear scope | Manual | You need human judgment at each step |
| Quick fix, one file | Manual | Overhead of a loop isn't worth it |
| AFK batch run | Ralph or Orch | Both run unattended until SHIP or budget exhausted |
| Items have complex dependencies | Orchestrator | Supports `depends:` declarations |
| Modifying the orchestrator itself | Ralph or Manual | Orch can't safely modify its own scripts mid-run |

---

## Common Tasks

### Adding a new hook

1. Create the script in `hooks/` (e.g. `hooks/my-hook.sh`)
2. Add the hook entry to `settings.json` under the appropriate event
3. Add a test in `tests/` that exercises the hook
4. Run `shellcheck hooks/my-hook.sh && shfmt -d hooks/my-hook.sh`

### Fixing a bug

1. `/plan fix: <description of the bug>`
2. Run `bash scripts/ralph-loop.sh <slug>` — Ralph handles implement + review
3. The loop commits on SHIP

### Adding a skill

1. Write the skill markdown in `skills/<name>.md`
2. Reference it from `CLAUDE.md` repo map if it's a core skill
3. For Canon-specific skills, put it in `canon/skills/` instead

### Adding a command

1. Write the command markdown in `commands/<name>.md`
2. Follow the existing command format (description, arguments, steps)
3. Update `CLAUDE.md` repo map

### Modifying the orchestrator or Ralph Loop

1. `/plan <description>`
2. Use Ralph Loop or manual — not the orchestrator (it can't modify itself safely)
3. Test with a small plan before running on real work

---

## Troubleshooting

### Ralph Loop stagnates (exit code 2)

The loop detected no file changes across 2 consecutive iterations. The worker
is running but not producing output.

**Fix:** Read `review-feedback.txt` and the last `iterations/NNN/` archive to
understand what the worker is stuck on. Manually unblock the issue, then re-run:

```bash
bash scripts/ralph-loop.sh <slug>
```

### Ralph Loop exhausts iterations (exit code 1)

The iteration budget ran out before the reviewer approved.

**Fix:** Check `review-feedback.txt` for the last REVISE reason. Either fix the
issue manually, increase `max_iterations` in `dega-core.yaml`, or re-run.

### Orchestrator worker fails

Check the done-file at `.orchestrator/done/<slug>/item-N.txt` — it contains
the worker's summary or blocker description. Failed items are re-run with
reviewer feedback on the next iteration.

### Plan items not checking off

Workers mark `[x]` in `plan.md` as they complete items. If checkboxes aren't
being checked, the worker may be failing before it reaches the checkpoint step.
Read the worker output in the tmux pane or the iteration archive.

### Health check failures

The Ralph Loop runs `ralph-check.sh` before SHIP. Health checks are defined in
`dega-core.yaml` under `success_criteria`. Common failures:

| Check | Fix |
|-------|-----|
| `shellcheck` | Fix lint errors in `scripts/` and `hooks/` |
| `shfmt` | Run `shfmt -w scripts/*.sh hooks/*.sh` |
| `actionlint` | Fix workflow issues in `.github/workflows/` |
| `no-todos` | Remove TODO/FIXME from `commands/`, `skills/`, `hooks/` |

### Resuming after interruption

Both Ralph and the orchestrator are resume-safe. The plan file tracks progress
via checkboxes. Re-running the same command picks up where it left off — already
checked items are skipped.
