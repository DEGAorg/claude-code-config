# Plan Creation Instructions

These instructions guide the plan writer agent for every plan created
in the claude-code-config repository.

## Architecture constraints

- All shell scripts must pass `shellcheck -e SC1091 -S warning` and `shfmt -d`
- Core artifacts (scripts/, hooks/, commands/, skills/) must remain project-agnostic
- Domain-specific logic goes in `canon/`, never in core
- GitHub Issues are the plan backend when `dega-core.yaml` has `github.sync: true`
- The orchestrator runs in tmux with one pane per worker, each in its own worktree
- `dega-core.yaml` at repo root is the per-project config file

## Multi-repo plans

Plans that modify repos other than claude-code-config must:
- Include a `repo:` field in the plan header (e.g., `repo: canon-tui`)
- Be tracked as GitHub Issues in the core repo (DEGAorg/claude-code-config)
- Use `repo:canon-tui` label for routing
- Account for separate worktree setup in the target repo
- Reference the decision doc: `docs/decisions/20260321-multi-repo-plan-architecture.md`

## Plan style

- Progress log items should be small enough for one agent session
- Prefer sequential plans unless items are truly independent
- Every plan must have verifiable completion criteria (commands, not prose)
- Include "Files to touch" table so reviewers can assess blast radius
- 3-8 items per plan. More than 8 means split into multiple plans.
- Always add `(deps: N)` annotations to every progress log item

## Naming and paths

- Scripts go in `scripts/` (flat, no subdirectories except terminal-ui/)
- Hooks go in `hooks/` (lifecycle hooks in `hooks/orch-lifecycle/`)
- Agent prompts go in `agents/`
- Skills go in `skills/` (core) or `canon/skills/` (domain)
- Decision docs go in `docs/decisions/YYYYMMDD-slug.md`

## What to avoid

- No UI work (Arena dashboard, web frontend)
- No Canon MCP Server implementation (separate repo)
- No changes to CI/CD pipelines without explicit approval in the plan
- No new npm/Python dependencies without justification in the decision log
- No force-push, no git reset --hard, no amending pushed commits

## Testing

- Shell scripts: write bats tests in `tests/` or inline validation scripts
- For e2e tests: use temporary repos/branches, clean up after
- Completion criteria must be runnable commands with expected output

## Reference files

- MVP scope: `docs/mvp-scope.md`
- Tech debt: `docs/exec-plans/tech-debt.md`
- Quality grades: `docs/QUALITY.md`
- Session handoff: `ace/tasks/20260321-session-handoff.md`
- Carlos meeting (Mar 23): `ace/meets/meet-mar-23.md`
- Multi-repo decision: `docs/decisions/20260321-multi-repo-plan-architecture.md`
- TUI decision: `docs/decisions/20260320-tui-framework-selection.md`
