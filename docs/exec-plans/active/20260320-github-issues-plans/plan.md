# Plan: GitHub Issues as Plan System

**Status:** In progress
**Created:** 2026-03-20

## Requirements

- GitHub Issues are the **single source of truth** for plans — no local plan files committed to git
- `/plan` creates a GitHub Issue with structured plan content (progress log, requirements, approach)
- Orchestrator reads plan content from the GitHub Issue, works locally in `.orchestrator/` (gitignored), posts results back as comments
- `dega-core.yaml` configures the GitHub integration per project (repo, sync behavior)
- Orchestrator lifecycle hooks system — scripts run at milestones (start, review, ship, revise)
- `gh` CLI auto-installed via brew (macOS + Linux); no sudo — fails with instructions if brew unavailable
- Milestone-based comments only: execution started, per-item review results (with iteration counts), final SHIP/REVISE
- `/sync` command reconciles local state with GitHub at session start
- Skill teaches Claude about the system (what scripts exist, data flow, how to use it)
- Fallback: projects without `github.sync` in dega-core.yaml use the existing local plan workflow

## Approach

### Architecture

```
/plan <task>
  │
  ├─ Claude writes plan content (requirements, approach, progress log)
  ├─ scripts/plan-create.sh creates GitHub Issue via gh CLI
  └─ returns issue URL — done, nothing committed to git

Orchestrator:
  │
  ├─ scripts/gh-plan-fetch.sh → fetches issue body → .orchestrator/plans/<slug>/plan.md (temp)
  ├─ orch-parse-items.sh reads temp file (existing parser, no changes)
  ├─ workers run in worktrees, write done-files to .orchestrator/
  ├─ lifecycle hooks fire at milestones:
  │     hooks/orch-lifecycle/01-gh-plan-sync.sh posts comments + updates labels
  └─ temp files cleaned up after SHIP

/sync
  │
  ├─ reads dega-core.yaml for repo config
  ├─ gh issue list → fetches open plan issues
  └─ flags drift (closed issues with running orchestrators, stale labels)
```

### Data flow — no local plans in git

| Data | Location | Lifecycle |
|------|----------|-----------|
| Plan content (requirements, progress log) | GitHub Issue body | Created by `/plan`, read by orchestrator |
| Plan labels (`plan:draft`, `plan:active`, etc.) | GitHub Issue labels | Managed by lifecycle hooks |
| Progress comments (iteration counts, SHIP/REVISE) | GitHub Issue comments | Posted by lifecycle hooks at milestones |
| Worker state, done-files, worktrees | `.orchestrator/plans/<slug>/` (gitignored) | Created at orch start, cleaned up at SHIP |
| Temp plan.md (fetched from issue for parsing) | `.orchestrator/plans/<slug>/plan.md` | Fetched at orch start, disposable |
| Project config | `dega-core.yaml` (committed) | Set once per project |

### dega-core.yaml config

```yaml
github:
  sync: true
  repo: DEGAorg/claude-code-config   # optional — auto-detected from git remote
  labels: true
  comments: true
  close_on_ship: true
```

### Label state machine

```
plan:draft → plan:active → plan:review → plan:completed
                              ↓
                         plan:failed
```

### Milestone comments — detail level

**Execution started:**
> Plan started for issue #42.
> 7 items, 4 max workers.

**Per-item review:**
> Item 2 "Create gh-plan-sync.sh" — SHIP after 1 iteration.
> Item 5 "Hook orchestrator" — SHIP after 2 iterations (reviewer flagged missing error handling on first pass).

**Final SHIP:**
> Plan SHIP. 7/7 items passed. 2 items required rework (9 total review iterations). Elapsed: 12m 34s.

**Final REVISE:**
> Plan REVISE. 5/7 items passed. 2 failed after max iterations. Failed: Item 4 (lint errors), Item 6 (2 assertions failing).

### Artifact roles

| Artifact | Purpose |
|----------|---------|
| **Skill** (`skills/github-plans.md`) | Teaches Claude: what the system is, data flow, what scripts exist, how to call them |
| **Command** (`commands/plan.md`) | User-invoked: Claude generates plan content, calls `plan-create.sh` |
| **Command** (`commands/sync.md`) | User-invoked: reconcile local state with GitHub before starting work |
| **Script** (`scripts/plan-create.sh`) | Deterministic: scaffold issue, apply labels, return issue number |
| **Script** (`scripts/gh-plan-fetch.sh`) | Deterministic: fetch issue body to temp file for orchestrator parsing |
| **Script** (`scripts/gh-plan-sync.sh`) | Deterministic: post comments, update labels at milestones |
| **Script** (`scripts/ensure-gh.sh`) | Deterministic: install gh via brew or fail with instructions |
| **Lifecycle hooks** (`hooks/orch-lifecycle/`) | Orchestrator calls these at milestones with slug + event args |

### ensure-gh.sh install strategy

1. `gh` in PATH → success
2. `brew` available (macOS or Linux) → `brew install gh` (no sudo)
3. Neither → fail with platform-specific manual instructions, never calls sudo

### Auth failure handling

`gh auth status` check returns exit code 2 when auth is missing. Scripts surface:
> gh is not authenticated. Run: gh auth login
> Then re-run this command.

Orchestrator lifecycle hooks check this exit code. Current behavior: log error, skip sync, continue execution. Future conductor: pause and notify user.

## Files to touch

| File | Change |
|------|--------|
| `scripts/ensure-gh.sh` | New — cross-platform gh installer (brew, no sudo) |
| `scripts/plan-create.sh` | New — creates GitHub Issue from plan content, applies labels |
| `scripts/gh-plan-fetch.sh` | New — fetches issue body to .orchestrator temp file |
| `scripts/gh-plan-sync.sh` | New — posts milestone comments, updates labels |
| `scripts/orch-engine.sh` | Add lifecycle hook calls at start, review, ship, revise |
| `scripts/orch-run.sh` | Call gh-plan-fetch.sh to get plan from issue before parsing |
| `hooks/orch-lifecycle/01-gh-plan-sync.sh` | New — lifecycle hook wrapper that calls gh-plan-sync.sh |
| `skills/github-plans.md` | New — teaches Claude about the GitHub plan system |
| `commands/plan.md` | Rewrite — Claude generates content, calls plan-create.sh |
| `commands/sync.md` | New — session-start reconciliation command |
| `dega-core.yaml` | Add `github:` config block |
| `.github/ISSUE_TEMPLATE/plan-task.yml` | New — structured issue template |
| `tests/test-ensure-gh.sh` | New — test installer detection |
| `tests/test-gh-plan-sync.sh` | New — test comment formatting and label updates |

## Risks and open questions

- `gh auth login` is interactive — scripts detect and fail clearly, but orchestrator runs are unattended. Auth must be validated before launching the orch.
- Issue body size limit (65536 chars) — large plans could hit this. Mitigate by keeping plans concise; if hit, split into issue body + first comment.
- Someone edits the issue body manually and breaks the progress log format — `orch-parse-items.sh` should fail with a clear parse error, not silently skip items.
- Rate limits on `gh api` — debounce by posting comments only at milestones, not on every poll.

## Progress log

- [x] Create `scripts/ensure-gh.sh` — detect gh, install via brew, fail with instructions if no brew
- [x] Create `scripts/plan-create.sh` — create GitHub Issue from plan content, apply `plan:draft` label, return issue number (deps: 1)
- [x] Create `scripts/gh-plan-fetch.sh` — fetch issue body by number, write to `.orchestrator/plans/<slug>/plan.md` (deps: 1)
- [x] Create `scripts/gh-plan-sync.sh` — post formatted milestone comments, update labels; accepts event type (start, review, ship, revise) and slug as args (deps: 1)
- [x] Add orchestrator lifecycle hooks system — `hooks/orch-lifecycle/` directory, engine calls scripts at milestones with (event, slug) args (deps: 4)
- [x] Wire `orch-run.sh` to fetch plan from issue — call `gh-plan-fetch.sh` before `orch-parse-items.sh`; validate auth before launch (deps: 3, 5)
- [x] Create lifecycle hook `hooks/orch-lifecycle/01-gh-plan-sync.sh` — wrapper that calls `gh-plan-sync.sh` with milestone data including per-item iteration counts (deps: 4, 5)
- [x] Rewrite `commands/plan.md` — Claude generates plan content, calls `plan-create.sh`; supports `--from-issue #N` for existing issues (deps: 2)
- [x] Create `commands/sync.md` — fetch open plan issues, flag drift, reconcile state (deps: 3, 4)
- [x] Create `skills/github-plans.md` — teaches Claude about the system: data flow, scripts, how to use them (deps: 2, 3, 4)
- [x] Add `github:` config block to `dega-core.yaml` and teach all scripts to read it (deps: 2, 3, 4)
- [x] Create `.github/ISSUE_TEMPLATE/plan-task.yml` — structured issue template (deps: 1)
- [x] Create `tests/test-ensure-gh.sh` and `tests/test-gh-plan-sync.sh` (deps: 1, 4)
- [x] End-to-end test — `/plan` creates issue, orch runs from it, comments posted at milestones, labels updated, SHIP closes issue (deps: 6, 7, 8, 9, 11)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| GitHub Issue is the single source of truth | Local plan.md in git, bidirectional sync | One source of truth eliminates drift. Local files are temp/gitignored only. |
| `dega-core.yaml` as project config | Per-plan flags, env vars | Configure once per project. Flags are overrides for exceptions. |
| Brew for cross-platform install, no sudo | apt/dnf with sudo, snap, conda | Brew works on both macOS and Linux without sudo. Clean failure with instructions if unavailable. |
| Lifecycle hooks directory | Hardcoded sync calls in engine | Extensible — add Slack, metrics, or other integrations without editing engine code. |
| Comments at milestones only | Every poll, every state change | Avoids comment spam. Milestones: start, per-item review, final result. |
| Scripts for stateful ops, skill for awareness | Claude instructions only | Scripts are deterministic and testable. Skill teaches Claude when and how to call them. |
| Auth check before orch launch | Retry mid-run, silent skip | Fail fast. Better to block launch than to complete work and fail to report it. |

## Completion criteria

- [ ] `ensure-gh.sh` installs gh via brew on macOS and Linux; fails with instructions when brew unavailable
- [ ] `/plan <task>` creates a GitHub Issue with plan content and `plan:draft` label
- [ ] Orchestrator fetches plan from GitHub Issue, parses items, runs workers
- [ ] Lifecycle hooks fire at milestones (start, review, ship, revise)
- [ ] SHIP comment includes per-item iteration counts and elapsed time
- [ ] SHIP updates label to `plan:completed` and closes the issue
- [ ] `/sync` fetches open plan issues and flags drift
- [ ] `skills/github-plans.md` exists and documents the system for Claude
- [ ] All tests pass
- [ ] shellcheck and shfmt clean on all new scripts
