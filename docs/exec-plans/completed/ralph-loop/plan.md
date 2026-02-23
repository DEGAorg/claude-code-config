# Plan: Full Ralph Loop Implementation

**Status:** In progress
**Created:** 2026-02-23

## Context

The Ralph Loop is an autonomous agent orchestration pattern: an outer loop spawns
fresh agent instances repeatedly until external checks confirm the work is done.
The agent cannot declare itself finished — the harness decides.

We have the state mechanism (exec-plans) and the exit gate (ralph-check.sh) but
are missing three things: (1) the orchestration script that runs the loop, (2) the
reviewer agent that decides SHIP or REVISE, and (3) proper repo-health checks in
ralph-check.sh (currently it checks harness artifact existence, not code quality).

We are also converting exec-plans from single files to directories, since the Ralph
Loop requires multiple files per task (plan, work-summary, review-feedback, result).

## Requirements

- `docs/exec-plans/active/` contains only directories (no loose .md files)
- `scripts/ralph-loop.sh` drives worker → reviewer → health-check cycle
- Worker prompt template instructs agent to resume from plan checkboxes and write
  work-summary.txt at end of each iteration
- Reviewer prompt template instructs agent to evaluate plan completion criteria and
  write review-result.txt (SHIP or REVISE) + review-feedback.txt
- `scripts/ralph-check.sh` checks real repo health: shellcheck, shfmt, actionlint,
  no TODOs in core files, active plans are directories
- `settings.json` has a Stop hook that runs ralph-check.sh
- `commands/plan.md` creates `active/$SLUG/plan.md` not `active/$SLUG-plan.md`
- `hooks/update-exec-plan-reminder.sh` globs `active/*/plan.md`

## Approach

Exec-plan directories are the state layer. The orchestration script spawns `claude -p`
for each phase (worker, reviewer) with fresh context each time. Memory persists via
files and git. The reviewer reads completion criteria from plan.md to decide SHIP/REVISE
— no task-specific config needed.

## Files to touch

| File | Change |
|------|--------|
| `commands/plan.md` | Create dir + plan.md, update archiving instruction |
| `hooks/update-exec-plan-reminder.sh` | Glob `active/*/plan.md` not `active/*.md` |
| `commands/apply-core.md` | Add ralph-loop scripts to file list |
| `ralph.yaml` | Replace harness criteria with worker/reviewer config |
| `scripts/ralph-check.sh` | Replace harness checks with real repo health |
| `scripts/ralph-loop.sh` | Create — outer orchestration loop |
| `scripts/ralph-worker-prompt.md` | Create — worker agent instructions |
| `scripts/ralph-reviewer-prompt.md` | Create — reviewer agent instructions |
| `settings.json` | Add Stop hook |
| `CLAUDE.md` | Update Working Conventions — ralph-loop.sh usage |

## Risks and open questions

- None blocking — all decisions resolved in planning.

## Progress log

- [x] Copy this plan to `docs/exec-plans/active/ralph-loop/plan.md`
- [x] Update `commands/plan.md` to create dir-based plans
- [x] Update `hooks/update-exec-plan-reminder.sh` to glob `active/*/plan.md`
- [x] Update `ralph.yaml` — repo health config + worker/reviewer keys
- [x] Rewrite `scripts/ralph-check.sh` with real repo health checks
- [x] Create `scripts/ralph-worker-prompt.md`
- [x] Create `scripts/ralph-reviewer-prompt.md`
- [x] Create `scripts/ralph-loop.sh`
- [x] Add Stop hook to `settings.json`
- [x] Update `CLAUDE.md` Working Conventions
- [x] Migrate existing flat plans to directories
- [x] Update `commands/apply-core.md` with new script files

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Dir per task | Keep flat files, put ralph state in `.ralph/` subdir | Co-location: task is self-contained, archiving is one mv |
| `claude -p` for fresh context | Reuse same session, Stop hook only | True ralph loop requires no context carry-over between iterations |
| Prompt templates as .md files | Hardcode in shell script | Editable without touching executable code; agents can read them directly |
| Strip harness checks from ralph-check.sh | Keep them, add new ones | They are permanently true; checking them adds noise and no signal |
| Stop hook as complement, not replacement | Stop hook only (no outer loop) | Interactive sessions need the gate; AFK automation needs the loop |

## Completion criteria

- [x] `docs/exec-plans/active/` contains only directories (no loose .md files)
- [x] `scripts/ralph-loop.sh` created with worker → reviewer → health-check cycle
- [x] Reviewer prompt outputs SHIP or REVISE with structured feedback
- [x] `ralph-check.sh` checks real repo health (shellcheck, shfmt, actionlint) — 5/5 passing
- [x] Stop hook added to `settings.json`
- [x] CLAUDE.md reflects updated usage instructions
