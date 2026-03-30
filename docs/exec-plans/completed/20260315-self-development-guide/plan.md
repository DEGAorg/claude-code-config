# Plan: Self-development guide

**Status:** In progress
**Created:** 2026-03-15

## Requirements

- A document at `docs/Self_Development.md` explaining how to apply fixes and new features to this repo
- Covers both manual workflows and the automated orchestrator/ralph loop
- Explains the full lifecycle: plan, implement, review, ship
- Documents when to use orch (parallel multi-item plans) vs ralph (single-item sequential)
- Includes concrete examples of common tasks

## Approach

### 1. Write `docs/Self_Development.md`

Structure:
1. **Overview** — this repo is AI-driven infrastructure that develops itself
2. **Quick start** — how to make a change (the 3-step version)
3. **Planning** — creating an exec-plan with `/plan`, the plan format, where plans live
4. **Implementation methods**:
   - **Manual**: read plan, implement, commit
   - **Ralph Loop**: `bash scripts/ralph-loop.sh <slug>` — single-focus sequential worker/reviewer
   - **Orchestrator**: `bash scripts/orch-run.sh <slug>` — parallel multi-item with dashboard
5. **When to use what** — decision table (orch vs ralph vs manual)
6. **Common tasks** — adding a new hook, fixing a bug, adding a skill, modifying orch itself
7. **Troubleshooting** — common failures, how to resume, how to inspect state

### 2. Cross-reference from README.md and CLAUDE.md

Add a one-line pointer from the repo map sections to the new guide. Don't duplicate content.

## Files to touch

| File | Change |
|------|--------|
| `docs/Self_Development.md` | New — self-development guide |
| `CLAUDE.md` | Add link in repo map |
| `README.md` | Add link in relevant section |

## Risks and open questions

None — this is a documentation-only plan.

## Progress log

- [x] Write `docs/Self_Development.md` with all sections
- [x] Add cross-reference link in CLAUDE.md repo map
- [x] Add cross-reference link in README.md

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Standalone doc in docs/ | Section in README | README is already large. Separate doc keeps it focused. |
| Cover orch + ralph + manual | Only orch | All three methods are actively used. Users need to know when to pick which. |

## Completion criteria

- [x] `docs/Self_Development.md` exists with all sections
- [x] CLAUDE.md and README.md link to the new guide
