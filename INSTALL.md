# Installation

Get the DEGA Core AI development harness installed and running.

## Prerequisites

The orchestrator needs `tmux` and `jq`. The terminal UI dashboard needs
`node` and `pnpm`. If any are missing, `/apply-core` detects your platform
and offers to install them (Homebrew on macOS, apt/dnf/pacman on Linux).

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
- `AGENTS.md` — project-level agent configuration (single source of truth)
- `CLAUDE.md`, `GEMINI.md`, `.cursorrules` — shims pointing to `AGENTS.md`
- `dega-core.yaml` — orchestrator config (max iterations, success criteria)
- `docs/exec-plans/active/` and `docs/exec-plans/completed/` — plan directories
- `.gitignore` entries for orchestrator state files

## Usage

### Create and run a plan

```
# 1. Inside Claude, create a plan
/plan add input validation to the health endpoint

# 2. Claude writes the plan and stops. Ask it to run:
run this plan

# Claude knows to use the orchestrator (from the global CLAUDE.md).
# It launches orch-run.sh, opens a tmux dashboard, and runs the plan.
```

The orchestrator spawns parallel workers, reviews each item, and iterates
until everything passes (SHIP).

You can also run the orchestrator directly from the terminal:

```bash
bash ~/.claude/scripts/orch-run.sh <slug>                  # parallel
bash ~/.claude/scripts/orch-run.sh <slug> --max-workers 1  # sequential
bash ~/.claude/scripts/orch-run.sh <slug> --background     # headless
bash ~/.claude/scripts/planner-loop.sh                     # autonomous
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
