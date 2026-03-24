# Canon MVP Scope — What's Left

Condensed from `../../canon-docs/Canon_MVP_Technical_Roadmap.md` (Alternative B).
This file is the planner's reference for what needs building.

**Hackathon date:** April 18, 2026
**Today:** March 23, 2026 (26 days left)
**Timeline start:** March 19 (Day 4 of build)

## Done (Core Infrastructure)

All shipped and stable in claude-code-config:

- Orchestrator (parallel workers, tmux, per-item review, SHIP/REVISE)
- Planner loop (--plan-only, --create-plans, assessment, execution)
- Ralph Loop (iteration control, success criteria, budget)
- Agent Framework structure (6 personas, 8 skills in canon/)
- 8 commands (/plan, /fix-issue, /review-pr, /cleanup, /doc-garden, /apply-core, /core-init, /canon-init)
- 10 hooks (enforce-package-manager, play-sound, structured-log, orch-lifecycle, etc.)
- Domain layering rule (canon/rules/)
- GitHub Issues as plan backend (labels, lifecycle hooks, sync)
- TOAD TUI fork (agent selector, GitHub panel, project state panel)
- Timeline widget (Gantt bars in TUI)
- TUI control skill (socket-based panel management)
- Plan upload workflow (plan-upload.sh)
- 90+ plans shipped

## Done But Needs Work

| Item | State | What's left |
|------|-------|-------------|
| GH Issues lifecycle | Built, 12 issues shipped | Full e2e test of create→orch→PR→merge→auto-close chain |
| TOAD TUI | Fork working | Rename to Canon, fix timeline legend (3 colors: done/active/pending), file viewer panel |
| TUI control | 1 action (project_state) | Panel stacking/replacing, more actions |
| /apply-core | Installs core artifacts | Doesn't install gh-plan scripts yet |
| Canon agent personas | 6 in canon/agents/ | Need validation against MCP tools |
| Canon skills | 8 in canon/skills/ | Need validation against MCP tools |

## Not Started — Must Ship (P1)

| Item | Est. days | Deps | Notes |
|------|-----------|------|-------|
| **pmxt POC** | 0.5 | none | Gate: test Polymarket API via pmxt. Fallback: direct CLOB API |
| **MCP Server** | 6 | pmxt POC | 8 tools: canon_init, canon_register, canon_market, canon_position, canon_test, canon_ralph, canon_activity, canon_help. New repo. |
| **Arena MVP** | 7 | MCP Server | Next.js + Vercel. Leaderboard, strategy registration, portfolio tracking. Reads Polymarket on-chain data. |
| **Strategy templates (3 min)** | 4 | MCP tools stable | Sampson defines logic, orch builds code. Min 3 for hackathon. |
| **Single-command install** | 1 | XDG migration | `canon install` or equivalent. Agent-managed with troubleshooting. |
| **Developer quickstart** | 1 | MCP + templates | Getting-started guide: install → load → scaffold → register in <15 min |

## Not Started — Should Ship (P2)

| Item | Est. days | Deps | Notes |
|------|-----------|------|-------|
| Remaining MCP tools polish | 2 | MCP Server | canon_activity, canon_test, canon_help refinement |
| 4 more strategy templates | 3 | Template code infra | Total of 7 templates |
| Portfolio view in Arena | 2 | Arena MVP | Per-user position display |
| RPA outreach tool | 2 | none | Playwright: scrape DoraHacks, semi-auto DMs |
| Workflows (5) | 2 | MCP tools | .canon/workflows/ — discover, develop, register, ralph, quick-dev |
| .canon/ralph.yaml | 1 | canon_ralph tool | Canon-specific Ralph Loop config |

## Not Started — Nice to Have (P3)

| Item | Est. days | Deps | Notes |
|------|-----------|------|-------|
| canon_help refinement | 1 | MCP Server | Contextual guidance |
| 10th template | 1 | Template infra | Stretch goal |
| Video walkthroughs | 2 | Everything | Requires stable product |
| Cloud Execution Service | 5+ | Arena | Fly.io Machines. Deferred — not for hackathon launch |

## This Repo's Scope (Core/Engine)

The planner targets items that live in this repo. Canon-product items (MCP Server,
Arena, templates) live in their own repos and are planned separately.

**Core items for the planner:**

1. GH Issues full lifecycle e2e test
2. Multi-repo orchestrator (worker cwd routing, cross-repo worktrees)
3. XDG migration (scripts from ~/.claude/ to ~/.dega-core/)
4. Single-command install script
5. /apply-core update (install gh-plan scripts)
6. Stale plan triage (5 active plans need archive/rewrite)
7. Broken test suites (orch e2e, stale detection — rewrite)
8. orch-state.sh split (822 lines → 3 files)
9. TUI improvements (rename, legend, file viewer, panel stacking)
10. Conductor agent design (routes work to specialized agents)
11. Canon agent/skill validation against MCP tool signatures
12. Developer onboarding docs
