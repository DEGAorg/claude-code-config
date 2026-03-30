# GitHub Plans

How execution plans are stored, synced, and tracked via GitHub Issues.
Use this skill when creating plans, running the orchestrator, or
troubleshooting the GitHub-backed plan system.

---

## Overview

GitHub Issues are the **single source of truth** for plans. No plan files
are committed to git. The orchestrator fetches plan content from the issue,
works locally in `.orchestrator/` (gitignored), and posts results back as
comments with label updates.

## Data flow

```
/plan <task>
  ├─ Claude writes plan content (requirements, approach, progress log)
  ├─ scripts/plan-create.sh → gh issue create → returns issue number
  └─ Nothing committed to git

orch-run.sh <slug> --issue <number>
  ├─ scripts/gh-plan-fetch.sh → fetches issue body → .orchestrator/plans/<slug>/plan.md
  ├─ orch-parse-items.sh reads the temp file (existing parser)
  ├─ Workers run in worktrees, write done-files to .orchestrator/
  ├─ Lifecycle hooks fire at milestones:
  │     hooks/orch-lifecycle/01-gh-plan-sync.sh → posts comments, updates labels
  └─ Temp files cleaned up after SHIP

/sync
  ├─ Reads dega-core.yaml for repo config
  ├─ gh issue list → fetches open plan issues
  └─ Flags drift (closed issues with running orchestrators, stale labels)
```

## Scripts

### `scripts/ensure-gh.sh`

Sourced by all other scripts. Provides `ensure_gh()` which installs `gh`
via brew if missing. Never calls sudo. Fails with platform-specific
instructions if brew is unavailable.

### `scripts/plan-create.sh`

Creates a GitHub Issue from plan content. Always applies `plan:draft`.

```bash
# From a file
scripts/plan-create.sh --title "Add auth endpoint" --body-file plan.md

# From a string
scripts/plan-create.sh --title "Add auth endpoint" --body "## Requirements..."

# With extra labels and repo override
scripts/plan-create.sh --title "Fix #42" --body-file plan.md \
  --repo DEGAorg/my-project --label "priority:high"
```

Prints the issue number to stdout. Exit code 2 means `gh` is not
authenticated.

### `scripts/gh-plan-fetch.sh`

Fetches an issue body and writes it to `.orchestrator/plans/<slug>/plan.md`.

```bash
scripts/gh-plan-fetch.sh 42 my-plan-slug
scripts/gh-plan-fetch.sh 42 my-plan-slug --repo DEGAorg/claude-code-config
```

Repo resolution order: `--repo` flag, `dega-core.yaml` `github.repo`,
git remote auto-detect. Prints the plan file path to stdout.

### `scripts/gh-plan-sync.sh`

Posts milestone comments and updates labels on a GitHub Issue. Called by
lifecycle hooks at orchestrator milestones.

```bash
# Plan started
scripts/gh-plan-sync.sh start my-slug --issue 42 --items 7 --max-workers 4

# Per-item review result
scripts/gh-plan-sync.sh review my-slug --issue 42 \
  --item-id 3 --item-desc "Create fetch script" --item-result SHIP --iterations 1

# Plan completed
scripts/gh-plan-sync.sh ship my-slug --issue 42 \
  --items 7 --passed 7 --rework-count 2 --total-reviews 9 --elapsed "12m 34s"

# Plan failed
scripts/gh-plan-sync.sh revise my-slug --issue 42 \
  --items 7 --passed 5 --failed 2 --failed-details "Item 4 (lint), Item 6 (tests)"
```

## Label state machine

```
plan:draft → plan:active → plan:review → plan:completed
                              ↓
                         plan:failed
```

Labels are mutually exclusive. Each transition removes all `plan:*` labels
before applying the target. The `ship` event also closes the issue.

## Project configuration

`dega-core.yaml` at the project root:

```yaml
github:
  sync: true
  repo: DEGAorg/claude-code-config   # optional — auto-detected from git remote
  labels: true
  comments: true
  close_on_ship: true
```

Projects without `github.sync: true` use the existing local plan workflow
(plan files committed to `docs/exec-plans/`). The two modes are mutually
exclusive.

## Authentication

All scripts check `gh auth status` before making API calls. Exit code 2
means authentication is missing. The fix is always:

```bash
gh auth login
```

The orchestrator validates auth before launching workers so failures
surface early, not after work is complete.

## Lifecycle hooks

`hooks/orch-lifecycle/` contains scripts that fire at orchestrator
milestones. Each script receives `(event, slug)` as positional args plus
milestone-specific flags. The orchestrator calls all scripts in the
directory in sort order (01-, 02-, etc.).

`01-gh-plan-sync.sh` is the GitHub sync hook. Additional hooks (Slack
notifications, metrics, etc.) can be added without editing the engine.

## Milestone comment format

| Event | Comment |
|-------|---------|
| start | "Plan started for `<slug>`. 7 items, 4 max workers." |
| review | "Item 3 'Create fetch script' — SHIP after 1 iteration." |
| ship | "Plan SHIP. 7/7 items passed. 2 required rework (9 total reviews). Elapsed: 12m." |
| revise | "Plan REVISE. 5/7 items passed. 2 failed. Failed: Item 4 (lint), Item 6 (tests)." |

## Fallback behavior

When `github.sync` is not configured in `dega-core.yaml`, the system falls
back to the local plan workflow: plans live in `docs/exec-plans/active/`
and are committed to git. Scripts like `plan-create.sh` are not called.
