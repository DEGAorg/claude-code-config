# Plan: Fix apply-core to include all orchestrator and planner files

**Status:** In progress
**Created:** 2026-03-15

## Requirements

The `/apply-core` command installs DEGA Core artifacts globally to `~/.claude/`.
The orchestrator section is missing critical files — `orch-engine.sh` (the core
execution loop), `orch-verify.sh` (final review), agent definitions, the planner
loop, and the done-sync hook. Without these, the orch installs but doesn't work.

Add all missing files to the orchestrator component and add a new planner
component in `commands/apply-core.md`.

## Missing files

### Orchestrator (existing component — incomplete)

| File | Purpose |
|------|---------|
| `scripts/orch-engine.sh` | Core execution loop — spawns workers, polls, handles review |
| `scripts/orch-verify.sh` | Final review gate before SHIP |
| `agents/orch-verifier.md` | Verifier agent prompt for final review |
| `hooks/orch-done-sync.sh` | PostToolUse hook that syncs done-files to orch state |

### Planner (new component)

| File | Purpose |
|------|---------|
| `scripts/planner-loop.sh` | Autonomous planner loop |
| `agents/planner-assess.md` | Assessment agent prompt |
| `agents/planner-writer.md` | Plan-writing agent prompt |

## Approach

Edit `commands/apply-core.md` to:

1. Add the 4 missing orchestrator files to the Source file list and the
   Orchestrator install section.
2. Add a new **Planner** component (opt-in) that installs the 3 planner files.
   Depends on Orchestrator. Listed after Orchestrator in the component menu.
3. Update the post-install summary example to include the planner line.

No other files change — this is purely a docs/command fix.

## Files to touch

| File | Change |
|------|--------|
| `commands/apply-core.md` | Add missing orch files, add planner component |

## Progress log

- [x] Add missing orchestrator files to the Source list in apply-core.md (deps: none)
- [x] Add missing orchestrator files to the Orchestrator install section (deps: 1)
- [x] Add Planner component to the user menu and install section (deps: 1)
- [x] Update post-install summary example to include planner (deps: 3)
- [ ] Verify all referenced files actually exist in the repo (deps: 1, 2, 3)

## Completion criteria

- [ ] All 4 missing orch files listed in Source and Orchestrator sections
- [ ] Planner component with 3 files listed in Source, menu, and install section
- [ ] Post-install example includes planner line
- [ ] Every file path in apply-core.md matches a real file in the repo
