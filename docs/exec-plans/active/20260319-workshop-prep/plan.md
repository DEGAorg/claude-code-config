# Plan: Workshop Prep — Install Fixes, Ralph Cleanup, Merge to Develop

**Status:** In progress
**Created:** 2026-03-19

## Requirements

- All GitHub raw-content URLs in install commands reference `develop` branch, not `ace-work`
- The orchestrator is the only recommended execution method — no Ralph Loop recommendations anywhere
- Ralph Loop references removed or replaced with orchestrator in all skills, commands, docs, and canon files
- `ace-work` is merged into `develop` so the install URLs resolve to the shipped code

## Approach

Two workstreams:

1. **Install refs + Ralph cleanup** — Update every file that references `ace-work` or recommends Ralph Loop:
   - **Commands**: `apply-core.md`, `core-init.md`, `canon-init.md`, `plan.md` — branch refs + remove ralph recommendations
   - **Scripts**: `canon-scaffold.sh` — branch variable
   - **Skills**: `plan-registry.md`, `changelog.md`, `sound-notifications.md` — replace ralph refs with orchestrator
   - **Canon**: `canon/skills/ralph-loop.md` — remove (replaced by orchestrator), `canon/CLAUDE.md` — remove ralph mention
   - **Docs**: `Self_Development.md`, `CLAUDE.md`, `README.md`, `dega-core.yaml` — orchestrator as primary

2. **Merge to develop** — Regular merge `ace-work` into `develop` to preserve history.

## Files to touch

| File | Change |
|------|--------|
| `commands/apply-core.md` | `ace-work` → `develop`, rename "Ralph Loop" section to "Legacy Scripts", remove recommendation |
| `commands/core-init.md` | `ace-work` → `develop` in URL |
| `commands/canon-init.md` | `ace-work` → `develop` in URL |
| `commands/plan.md` | Remove ralph loop from hand-off output, orchestrator only |
| `scripts/canon-scaffold.sh` | `BRANCH="ace-work"` → `BRANCH="develop"` |
| `skills/plan-registry.md` | Replace `ralph` method mention with note that it's legacy |
| `skills/changelog.md` | Replace `Ralph Loop (ralph-loop.sh)` with orchestrator-only |
| `skills/sound-notifications.md` | Replace "Ralph Loop behavior" section with "Orchestrator behavior" |
| `canon/skills/ralph-loop.md` | Delete — orchestrator replaces this |
| `canon/CLAUDE.md` | Remove "Ralph Loop convergence" mention |
| `docs/Self_Development.md` | Orchestrator as primary, move Ralph Loop to "Legacy" appendix |
| `CLAUDE.md` | Rename "Ralph Loop" section, update to reference orchestrator |
| `README.md` | Update scripts description |
| `dega-core.yaml` | Update comment referencing ralph-loop.sh |

## Risks and open questions

- **Q: Delete ralph scripts or keep them?**
  Decision: Keep scripts installed (they still work), but remove all recommendations. Existing completed plans reference them — deleting would break history links. The cleanup is in docs/skills/commands only.

- **Q: Merge strategy?**
  Decision: Regular merge to preserve full commit history.

## Progress log

- [x] Update `commands/apply-core.md` — branch `ace-work` → `develop`, demote Ralph Loop section to "Legacy Scripts"
- [x] Update `commands/core-init.md` — branch URL `ace-work` → `develop` (deps: 1)
- [x] Update `commands/canon-init.md` — branch URL `ace-work` → `develop` (deps: 1)
- [x] Update `commands/plan.md` — remove ralph loop from hand-off, orchestrator only (deps: 1)
- [x] Update `scripts/canon-scaffold.sh` — `BRANCH="ace-work"` → `BRANCH="develop"` (deps: 1)
- [x] Update skills: `plan-registry.md`, `changelog.md`, `sound-notifications.md` — replace ralph refs with orchestrator (deps: 1)
- [x] Delete `canon/skills/ralph-loop.md`, update `canon/CLAUDE.md` to remove ralph references (deps: 1)
- [x] Update `docs/Self_Development.md` — orchestrator primary, ralph loop to legacy appendix (deps: 1)
- [x] Update `CLAUDE.md` — rename Ralph Loop section to Orchestrator, update description (deps: 1)
- [x] Update `README.md` and `dega-core.yaml` — minor ref cleanups (deps: 1)
- [x] Merge `ace-work` into `develop` (deps: 2, 3, 4, 5, 6, 7, 8, 9, 10)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Keep ralph scripts, remove recommendations | Full removal | Scripts work, completed plans reference them, no harm in keeping them installed. Just stop recommending. |
| `develop` as install branch | `main`, tagged releases | `develop` is the team's working stable branch. `main` is for releases. |
| Regular merge | Rebase, squash | Preserves full history. develop is far behind so rebase would be noisy. |
| Delete `canon/skills/ralph-loop.md` | Keep and rename | The skill is entirely about Ralph Loop. Orchestrator has its own patterns via agent prompts. No value in renaming. |

## Completion criteria

- [ ] No file in `commands/` or `scripts/` references `ace-work` branch
- [ ] `commands/plan.md` hand-off section mentions only the orchestrator
- [ ] `docs/Self_Development.md` Quick Start shows orchestrator as the primary method
- [ ] No skill file recommends Ralph Loop as a method to use
- [ ] `canon/skills/ralph-loop.md` does not exist
- [ ] `develop` branch contains all commits from `ace-work`
