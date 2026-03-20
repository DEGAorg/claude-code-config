# Installation

Get the DEGA Core AI development harness installed and running.

## Prerequisites

The orchestrator needs `tmux` and `jq`. The terminal UI dashboard needs
`node` and `pnpm`. If any are missing, `/apply-core` will offer to install
them via Homebrew during setup.

## Install

```bash
git clone https://github.com/DEGAorg/claude-code-config.git
cd claude-code-config
claude
```

Inside the session, run:

```
/apply-core
```

It walks you through each component, detects what you already have, and
installs everything to `~/.claude/`. After the first install, `/apply-core`
is available from any directory — no need to be in the repo.

## What Gets Installed

| Component | Location | Purpose |
|-----------|----------|---------|
| **CLAUDE.md** | `~/.claude/CLAUDE.md` | Global dev standards + orchestrator instructions |
| **Commands** | `~/.claude/commands/` | `/plan`, `/fix-issue`, `/review-pr`, `/cleanup`, `/doc-garden`, `/core-init` |
| **Rules** | `~/.claude/rules/` | Language standards (Python, TypeScript, Rust, Bash, GitHub Actions) |
| **Hooks** | `~/.claude/hooks/` | Guardrails: block `rm -rf`, enforce package manager, play sounds |
| **Skills** | `~/.claude/skills/` | App legibility, custom linters, sound notifications |
| **Orchestrator** | `~/.claude/scripts/orch-*.sh` | Parallel plan execution engine (needs `tmux`, `jq`) |
| **Terminal UI** | `~/.claude/scripts/terminal-ui/` | Ink dashboard for monitoring runs (needs `node`, `pnpm`) |
| **Agents** | `~/.claude/agents/` | Worker and verifier agent prompts |
| **Sounds** | `~/.claude/dega/sounds/` | Completion notification sounds |
| **Settings** | `~/.claude/settings.json` | Permissions, hooks, statusline config |

## Enable a Project

Run `/core-init` in any repo where you want to use the orchestrator —
whether it's a code project, a research repo, or an ops/documentation repo.

```bash
cd your-project
claude
# inside the session:
/core-init
```

This creates:
- `dega-core.yaml` — orchestrator config (max iterations, success criteria)
- `docs/exec-plans/active/` and `docs/exec-plans/completed/` — plan directories
- `.gitignore` entries for orchestrator state files

## Usage

### Create and run a plan

```bash
# 1. Start Claude in your project
cd your-project
claude

# 2. Create a plan (Claude writes it, then stops)
/plan add input validation to the health endpoint

# 3. Exit Claude, run the plan with the orchestrator
bash ~/.claude/scripts/orch-run.sh 20260319-add-input-validation
```

The orchestrator opens a tmux session with a dashboard, spawns parallel
workers, reviews each item, and iterates until everything passes (SHIP).

### Orchestrator options

```bash
# Parallel (default: 4 workers)
bash ~/.claude/scripts/orch-run.sh <slug>

# Sequential (1 worker at a time)
bash ~/.claude/scripts/orch-run.sh <slug> --max-workers 1

# Headless (no dashboard window)
bash ~/.claude/scripts/orch-run.sh <slug> --background

# Autonomous planner (picks work from focus.yaml, loops)
bash ~/.claude/scripts/planner-loop.sh
```

### Other commands

| Command | What it does |
|---------|--------------|
| `/plan <task>` | Create an execution plan |
| `/fix-issue <number>` | Fix a GitHub issue end-to-end |
| `/review-pr <number>` | Review a PR with parallel agents |
| `/cleanup` | Scan for code quality issues |

## Updating

Run `/apply-core` from any directory. It fetches the latest from the
`develop` branch and overwrites engine scripts (safe — no user
customization). It asks before overwriting `CLAUDE.md` or `settings.json`
since those may have personal edits.
