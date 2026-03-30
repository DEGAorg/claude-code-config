# Session Handoff — 2026-03-21

## What was built (2026-03-20, 12 plans shipped)

### GitHub Issues as Plan System (engine layer, this repo)

Scripts:
- `scripts/ensure-gh.sh` — cross-platform gh installer (brew, no sudo)
- `scripts/plan-create.sh` — creates GitHub Issue from plan content
- `scripts/gh-plan-fetch.sh` — fetches issue body to .orchestrator temp file
- `scripts/gh-plan-sync.sh` — posts milestone comments, updates labels, edits issue body checkboxes
- `scripts/read-github-config.sh` — reads `github:` block from dega-core.yaml

Orchestrator changes:
- `hooks/orch-lifecycle/` — lifecycle hooks system, scripts run at milestones (start, review, ship, revise, fail)
- `hooks/orch-lifecycle/01-gh-plan-sync.sh` — calls gh-plan-sync at each milestone
- `orch-run.sh` — auto-creates GitHub Issue for local plans when `github.sync: true`
- `orch-engine.sh` — fires lifecycle hooks at start, review, ship, revise, fail

Commands and skills:
- `commands/plan.md` — rewritten, Claude generates content then calls plan-create.sh
- `commands/sync.md` — session-start reconciliation, fetches open plan issues, flags drift
- `skills/github-plans.md` — teaches Claude about the GitHub plan system
- `skills/conductor-panels.md` — teaches Claude about panel commands

Config:
- `dega-core.yaml` has `github:` block (sync, repo, labels, comments, close_on_ship)

Fixes applied:
- Issue body checkbox sync (awk-based, handles special chars)
- SHIP flow: issue stays open with `plan:pr-review`, PR has `Closes #N`, GitHub auto-closes on merge
- Orch review quality: clause-by-clause verification in reviewer prompt
- CI pipeline: shellcheck `-e SC1091 -S warning`, shfmt without `-i 2` (repo uses tabs)
- Auto-issue: call ensure-gh.sh as subprocess not source

Labels created on DEGAorg/claude-code-config:
- `plan:draft`, `plan:active`, `plan:review`, `plan:pr-review`, `plan:completed`, `plan:failed`

### Conductor TUI (DEGAorg/conductor-view repo)

Repo: [DEGAorg/conductor-view](https://github.com/DEGAorg/conductor-view)
Local path: `/Users/cerratoa/dega/conductor-view`
Base: Fork of [batrachianai/toad](https://github.com/batrachianai/toad) (AGPL-3.0)
Python: 3.14 required, venv at `.venv/`

What was added:
- `src/toad/widgets/github_state.py` — GitHubStateWidget (TabbedContent with 4 views)
- `src/toad/widgets/github_views/` — fetch.py, timeline.py, issues.py, plans.py, prs.py, status_overview.py
- `src/toad/screens/main.py` — GitHub panel dynamically mounted via ctrl+g or agent command
- `src/toad/acp/messages.py` — OpenPanel, ClosePanel ACP message types
- `src/toad/acp/agent.py` — handles open_panel/close_panel sessionUpdate events
- `src/toad/widgets/conversation.py` — /panel slash command handling
- `src/toad/cli.py` — `--conductor` flag (skips home, launches Claude), `--project-dir` flag
- `src/toad/data/agents/claude.com.toml` — panel awareness in agent description

How to run:
```bash
cd ~/dega/conductor-view
source .venv/bin/activate
toad --conductor --project-dir ~/dega/aidd/claude-code-config
```
- `ctrl+g` toggles GitHub panel
- `/panel github` opens it, `/panel github close` closes it
- Ask Claude "show me the project state" and it should use /panel

Dependency: `npm install -g @zed-industries/claude-code-acp` (ACP adapter for Claude Code)

## Open GitHub Issues

| Issue | State | Label | Description |
|-------|-------|-------|-------------|
| #11 | OPEN | plan:pr-review | Agent-to-panel integration (/panel command) |
| #10 | OPEN | plan:review | CI pipeline fix (verification failed, fix applied manually, CI green) |
| #9 | OPEN | plan:pr-review | GitHub panel PM redesign (status cards + timeline) |
| #8 | OPEN | plan:pr-review | Agent-controlled panels + --conductor flag |
| #7 | OPEN | plan:pr-review | GitHub panel — agent-summoned, repo-aware |
| #6 | OPEN | plan:pr-review | Orch review quality (clause-by-clause) |
| #5 | CLOSED | plan:completed | Fix SHIP flow — defer close to PR merge |
| #3 | CLOSED | plan:completed | Verify body sync e2e |
| #2 | CLOSED | plan:completed | Auto-issue test |
| #1 | CLOSED | plan:completed | E2E test |

## Pre-existing active plans (not touched)

- `20260306-cleanup-on-pr`
- `20260313-orch-linux-testing`
- `20260314-orch-demo`
- `20260315-fix-broken-tests`

## Known gaps / debt

1. **Conductor-view needs its own dega-core.yaml + orchestrator** — plans modifying Toad should run from that repo, not claude-code-config
2. **ACP adapter auto-install** — `ensure-acp.sh` missing, users must manually run `npm install -g @zed-industries/claude-code-acp`
3. **GitHub panel sizing** — cramped in sidebar, needs layout work
4. **Global script sync** — `/apply-core` doesn't install the new gh-plan scripts yet
5. **Verification false-negatives** — verifier sometimes can't confirm criteria in worktree context, causing unnecessary REVISE cycles
6. **Issue #10 needs manual promotion** — work done, CI green, but orch verification failed

## Architecture decisions

- Decision doc: `docs/decisions/20260320-tui-framework-selection.md` — Fork Toad (AGPL-3.0)
- GitHub Issues are single source of truth for plans (no local plan.md in git)
- `dega-core.yaml` `github:` block controls all sync behavior
- Conductor (agent) controls UI panels via ACP messages
- Two repos: claude-code-config (engine) + conductor-view (TUI), shared contract is state.json schema + label conventions
- CI: shellcheck with `-e SC1091 -S warning`, shfmt with tabs (no `-i 2`)

## Branch state

- **claude-code-config**: `ace-work` branch, pushed to origin, CI green
- **conductor-view**: `main` branch, pushed to origin
