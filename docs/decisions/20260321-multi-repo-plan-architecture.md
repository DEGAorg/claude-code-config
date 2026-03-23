# Decision: Multi-Repo Plan Architecture

**Date:** 2026-03-21
**Status:** Accepted

## Context

Two repos with incompatible licenses:
- **Core** (DEGAorg/claude-code-config) — Apache 2.0, orchestration engine, plans, skills, commands
- **Toad** (DEGAorg/conductor-view) — AGPL-3.0 fork of batrachianai/toad, TUI surface

We need a unified timeline view across both repos without license contamination.

## Decision

**Single issue tracker, two repos.**

- All plans and tasks live as GitHub Issues in the Core repo, even when the work modifies Toad
- Labels (e.g., `repo:conductor-view`) indicate which repo the code lands in
- The orchestrator runs from Core; worker `cwd` can point to any repo
- Toad's timeline view fetches issues via GitHub API (`gh issue list --repo DEGAorg/claude-code-config`), not from Core's filesystem
- GitHub API is the neutral bus — no direct imports between repos

## Data flow

```
Core repo                  GitHub API              Toad TUI
───────────                ──────────              ────────
plan-create.sh ──writes──> Issue #N         <──reads── timeline view
gh-plan-sync.sh ─updates─> labels, comments <──reads── status cards
orch-engine.sh ──updates─> checkboxes       <──reads── progress bars
```

## Why not alternatives

| Alternative | Problem |
|-------------|---------|
| Merge repos | License conflict (Apache 2.0 vs AGPL-3.0) |
| Separate issue trackers per repo | No unified timeline, duplicated tracking |
| Third "project" repo | Unnecessary indirection, another thing to maintain |
| GitHub Projects (board) | Adds product dependency; `gh` issue API is simpler and sufficient |

## Implications

- Toad only needs to know which GitHub repo to query (configurable setting, not hardcoded)
- Any Toad user pointing at a different repo with the same label conventions gets the same timeline
- Core's plan labels (`plan:draft`, `plan:active`, `plan:review`, `plan:completed`, `plan:failed`) are the shared contract
- The `repo:*` label convention is new — needs to be created on Core's repo
