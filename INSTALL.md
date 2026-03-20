# Installation

Get the DEGA Core AI development harness installed and running in under 5 minutes.

## Prerequisites

```bash
brew install tmux jq node@22 pnpm
```

Verify:

```bash
tmux -V && node -v && pnpm -v && jq --version
```

## Quick Install

**Option A — From a Claude session (interactive):**

```bash
git clone https://github.com/DEGAorg/claude-code-config.git
cd claude-code-config
claude
```

Then run `/apply-core` inside the session. It walks you through each
component, detects what you already have, and installs to `~/.claude/`.

**Option B — From GitHub (no clone needed):**

If you already have `/apply-core` installed, run it from any directory.
It fetches everything from the `develop` branch.

## What Gets Installed

| Component | Location | Purpose |
|-----------|----------|---------|
| **CLAUDE.md** | `~/.claude/CLAUDE.md` | Global dev standards + orchestrator instructions |
| **Commands** | `~/.claude/commands/` | `/plan`, `/fix-issue`, `/review-pr`, `/cleanup`, `/doc-garden`, `/core-init` |
| **Rules** | `~/.claude/rules/` | Language standards (Python, TypeScript, Rust, Bash, GitHub Actions) |
| **Hooks** | `~/.claude/hooks/` | Guardrails: block `rm -rf`, enforce package manager, play sounds |
| **Skills** | `~/.claude/skills/` | App legibility, custom linters, sound notifications |
| **Orchestrator** | `~/.claude/scripts/orch-*.sh` | Parallel plan execution engine |
| **Terminal UI** | `~/.claude/scripts/terminal-ui/` | Ink dashboard for monitoring orchestrator runs |
| **Agents** | `~/.claude/agents/` | Worker and verifier agent prompts |
| **Sounds** | `~/.claude/dega/sounds/` | Completion notification sounds |
| **Settings** | `~/.claude/settings.json` | Permissions, hooks, statusline config |

## Per-Project Setup

Each project needs a `dega-core.yaml` at its root. Run `/core-init` from
your project directory to create one:

```bash
cd your-project
claude
# inside the session:
/core-init
```

This creates `dega-core.yaml` with defaults for your project's language,
adds exec-plan directories, and sets up `.gitignore` entries.

## Usage

### Create and run a plan

```bash
# 1. Start Claude in your project
cd your-project
claude

# 2. Create a plan
/plan add input validation to the health endpoint

# 3. Exit Claude, run the plan with the orchestrator
bash ~/.claude/scripts/orch-run.sh 20260319-add-input-validation
```

The orchestrator opens a tmux session with a dashboard, spawns parallel
workers, reviews each item, and iterates until everything passes (SHIP).

### Key commands

| Command | What it does |
|---------|--------------|
| `/plan <task>` | Create an execution plan |
| `/fix-issue <number>` | Fix a GitHub issue end-to-end |
| `/review-pr <number>` | Review a PR with parallel agents |
| `/cleanup` | Scan for code quality issues |
| `/apply-core` | Re-install or update all components |

### Orchestrator options

```bash
# Parallel (default: 4 workers)
bash ~/.claude/scripts/orch-run.sh <slug>

# Sequential (1 worker)
bash ~/.claude/scripts/orch-run.sh <slug> --max-workers 1

# Headless (no dashboard window)
bash ~/.claude/scripts/orch-run.sh <slug> --background

# Autonomous planner (picks work from focus.yaml)
bash ~/.claude/scripts/planner-loop.sh
```

## Verify

After installing, confirm the key pieces are in place:

```bash
# Global CLAUDE.md has orchestrator section
grep "Execution Plans" ~/.claude/CLAUDE.md

# Orchestrator is installed
ls ~/.claude/scripts/orch-run.sh

# Plan command is available
ls ~/.claude/commands/plan.md

# Terminal UI is built
ls ~/.claude/scripts/terminal-ui/dist/cli.js
```

## Updating

Run `/apply-core` again. It fetches the latest from the `develop` branch
and overwrites engine scripts (safe — they have no user customization).
It will ask before overwriting `CLAUDE.md` or `settings.json` since those
may have personal edits.
