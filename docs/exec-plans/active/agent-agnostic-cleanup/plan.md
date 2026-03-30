# Plan: Agent-Agnostic Cleanup — Remove Legacy Fallbacks

**Status:** Draft
**Created:** 2026-03-29

## Requirements

- Remove `CLAUDE_SOUND` / `CLAUDE_SOUND_VOLUME` fallback env vars (only `DEGA_SOUND` / `DEGA_SOUND_VOLUME`)
- Remove any remaining `~/.claude/` hardcoded paths in documentation
- Archive `ralph-loop.sh` (legacy, not ported to agent-agnostic)
- Update `agent-template.md` and `AGENTS.md` for multi-agent install instructions
- Clean up `docs/agent-agnostic-requirements.md` and `docs/agnostic-gem-recommendations.md` (move to completed/decisions or delete)

## Approach

Straightforward cleanup pass. Remove transitional fallbacks added in Phase 1, update docs to reflect the final multi-agent state.

## Files to touch

| File | Change |
|------|--------|
| `hooks/play-sound.sh` | Remove `CLAUDE_SOUND` fallback — use `DEGA_SOUND` only |
| `scripts/ralph-loop.sh` | Archive or delete (legacy, not agent-agnostic) |
| `agent-template.md` | Update for multi-agent context |
| `README.md` | Final pass — remove any `~/.claude/` references in prose |
| `INSTALL.md` | Final pass — multi-agent install instructions |
| `docs/agent-agnostic-requirements.md` | Move to `docs/decisions/` or delete |
| `docs/agnostic-gem-recommendations.md` | Move to `docs/decisions/` or delete |

## Risks and open questions

- **Ralph loop users**: Anyone still using `ralph-loop.sh` directly? Likely no — superseded by orchestrator. (P3)

## Progress log

- [x] Remove `CLAUDE_SOUND` / `CLAUDE_SOUND_VOLUME` fallbacks from `hooks/play-sound.sh` and any other files still referencing them
- [ ] Archive `scripts/ralph-loop.sh` — move to `scripts/legacy/` or delete entirely (deps: 1)
- [ ] Update `agent-template.md`, `README.md`, `INSTALL.md` for final multi-agent documentation (deps: 1)
- [ ] Clean up research docs — move `docs/agent-agnostic-requirements.md` and `docs/agnostic-gem-recommendations.md` to `docs/decisions/` (deps: 1)
- [ ] Final grep audit — `grep -r "CLAUDE_SOUND\|~/.claude/" scripts/ hooks/ commands/ settings.json` returns zero hits (deps: 1, 2, 3)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Delete ralph-loop.sh rather than port | Port to agent-agnostic | Superseded by orchestrator. No users. Not worth the maintenance. |
| Move research docs to decisions/ | Delete entirely | They document the rationale for the migration — useful as historical reference |

## Completion criteria

- [ ] `grep -r "CLAUDE_SOUND" scripts/ hooks/` returns zero hits
- [ ] `grep -r "~/.claude/" scripts/ hooks/ commands/` returns zero hits (excluding intentional project-local `.claude/commands/`)
- [ ] `ralph-loop.sh` archived or deleted
- [ ] Research docs moved to `docs/decisions/`
- [ ] `shellcheck` passes on all modified `.sh` files
