# Task Analysis: GitHub Integration + Project State TUI

**Date:** 2026-03-20
**Author:** Ace

---

## 1. Planner Loop Status

**Usable today.** Run `scripts/planner-loop.sh` against any repo with active plans in
`docs/exec-plans/active/` and it executes them via the orchestrator. The `--create-plans`
flag enables autonomous plan creation but is experimental. Side tooling — not a dependency
for these two plans.

---

## 2. Architecture: GitHub Issues as Single Source of Truth

GitHub Issues **are** the plans. No local plan files committed to git.

```
/plan <task>
  → Claude writes plan content
  → plan-create.sh creates GitHub Issue
  → done. Nothing in git.

Orchestrator:
  → fetches issue body to temp file (.orchestrator/, gitignored)
  → parses progress log, runs workers
  → posts milestone comments back to the issue
  → updates labels (plan:draft → plan:active → plan:completed)
  → temp files cleaned up after SHIP

/project-state
  → queries GitHub directly via gh CLI
  → renders TUI with live data (issues, PRs, plans, timeline)
```

### Key principles

1. **One source of truth** — GitHub Issue body has the plan. No local copies in git.
2. **Scripts for stateful operations** — `plan-create.sh`, `gh-plan-sync.sh` handle all GitHub writes.
3. **Skill for Claude awareness** — `skills/github-plans.md` teaches Claude the system.
4. **Commands for user invocation** — `/plan`, `/sync`, `/project-state`.
5. **Lifecycle hooks on orchestrator** — extensible milestone triggers, not hardcoded sync calls.
6. **`dega-core.yaml` as project config** — `github:` block configures everything.
7. **`gh` via brew, never sudo** — fails with instructions if brew unavailable.
8. **Milestone comments only** — start, per-item review (with iteration count), final SHIP/REVISE.

### Fallback

Projects without `github.sync` in dega-core.yaml use the existing local plan workflow unchanged.

---

## 3. Plans

### Plan 1: `20260320-github-issues-plans` (14 steps)

GitHub Issues as plan system. Core infrastructure:
- `ensure-gh.sh` — cross-platform gh installer
- `plan-create.sh` — creates issues with plan content
- `gh-plan-fetch.sh` — fetches issue to temp for orchestrator
- `gh-plan-sync.sh` — posts comments, updates labels
- Orchestrator lifecycle hooks system
- `/plan` command rewrite, `/sync` command, `skills/github-plans.md`
- `dega-core.yaml` github config block

### Plan 2: `20260320-project-state-tui` (10 steps)

Interactive TUI for project state from GitHub:
- Direct `gh` calls from Ink app (no intermediary files)
- 4 views: Timeline, Issues, Plans, PRs
- Tab navigation, scroll, refresh
- Plan issues show progress parsed from issue body checkboxes
- Extends existing `scripts/terminal-ui/` Ink infrastructure

### Execution order

Plan 1 first — Plan 2 depends on `ensure-gh.sh` and the label conventions from Plan 1.
