# Plan: Add missing gh-plan scripts to /apply-core install manifest

**Status:** In progress
**Created:** 2026-03-24

## Requirements

- `/apply-core` command installs all GitHub plan scripts globally
- 7 scripts added to the Orchestrator component's file list and install steps
- The `/apply-core` command file (`commands/apply-core.md`) is the only file modified
- After this change, running `/apply-core` and selecting Orchestrator installs the full gh-plan toolchain

## Approach

Add the 7 missing scripts to the `/apply-core` command in two places:
1. The **Source** file list at the top (so they're fetched from GitHub)
2. The **Orchestrator** install section (so they're written to `~/.claude/scripts/`)

Scripts to add:
- `scripts/ensure-gh.sh`
- `scripts/gh-plan-fetch.sh`
- `scripts/gh-plan-sync.sh`
- `scripts/plan-create.sh`
- `scripts/plan-upload.sh`
- `scripts/read-github-config.sh`
- `scripts/create-exec-plan.sh`

Also add the `hooks/orch-lifecycle/` directory and its hook:
- `hooks/orch-lifecycle/01-gh-plan-sync.sh`

## Files to touch

| File | Change |
|------|--------|
| `commands/apply-core.md` | Add 7 scripts to Source list and Orchestrator install section |

## Risks and open questions

- The command file is long (~400 lines). Changes are additive — adding lines to two existing lists.

## Questions for reviewer

No blocking questions.

## Progress log

- [ ] Add the 7 gh-plan scripts and orch-lifecycle hook to the Source file list in `commands/apply-core.md`
- [ ] Add install instructions for these scripts in the Orchestrator section (deps: 1)
- [ ] Verify the updated file references match actual repo paths (deps: 2)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Add to Orchestrator component | Create new "GitHub Plans" component | These scripts are part of the orchestrator's GH integration, not a standalone feature |

## Completion criteria

- [ ] `rg 'ensure-gh\|gh-plan-fetch\|gh-plan-sync\|plan-create\|plan-upload\|read-github-config\|create-exec-plan' commands/apply-core.md | wc -l` returns at least 14 (each script appears in Source list + install section)
- [ ] `rg 'orch-lifecycle' commands/apply-core.md | wc -l` returns at least 2
