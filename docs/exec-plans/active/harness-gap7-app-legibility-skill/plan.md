# Plan: Harness Gap 7 — App-Legibility Skill

**Status:** In progress
**Created:** 2026-02-23

## Requirements

- `skills/app-legibility.md` exists and teaches four patterns for making apps observable to agents
- Gap 7 status in `CLAUDE.md` changes from "To do" to "Done"
- `commands/apply-core.md` lists `skills/app-legibility.md` so `/apply-core` installs it

## Approach

Write a skill file modeled after `skills/custom-linter-authoring.md`. Skills teach
knowledge, not procedures — each pattern includes problem, solution, code examples,
and agent usage. Form: markdown with `##` sections, fenced code blocks, minimal prose.

The four patterns:
1. **Log file redirection** — stdout/stderr → `logs/server.log` (agents use Read/Bash)
2. **Per-worktree isolation** — port + DB derived from worktree name (parallel agents)
3. **Health endpoint** — `GET /health` → JSON so agents can check server state
4. **Crash surfacing** — unhandled exceptions → `logs/crashes.log`

## Files to Touch

| File | Change |
|------|--------|
| `skills/app-legibility.md` | CREATE — skill file |
| `CLAUDE.md` | UPDATE — gap 7 row: **To do** → **Done**, artifact → `skills/app-legibility.md` |
| `commands/apply-core.md` | UPDATE — add `skills/app-legibility.md` to file list and Skills description |

## Risks and Open Questions

None. Skill content is self-contained with no inter-file dependencies.

## Progress Log

- [x] Create exec-plan file
- [x] Create `skills/app-legibility.md`
- [x] Update `CLAUDE.md` gap 7 row
- [x] Update `commands/apply-core.md`

## Decision Log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Skill, not command | Hook, command | Pattern is project-specific; knowledge injection beats standardized script |
| Four patterns (log, isolation, health, crash) | Full DevTools/LogQL integration | Minimal viable Phase I; DevTools is Phase II scope |
| `logs/` directory convention | Env vars, syslog | File-based — agents can Read directly without shell access |

## Completion Criteria

- [x] `skills/app-legibility.md` present with all four patterns
- [x] `CLAUDE.md` gap 7 shows **Done**
- [x] `commands/apply-core.md` includes `skills/app-legibility.md`
- [x] All seven harness gaps are now **Done**
