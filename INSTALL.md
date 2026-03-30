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
installs shared artifacts to `~/.degacore/`. It then detects installed agents
(Claude, Gemini, Codex) and generates per-agent config (settings, commands,
rules) in each agent's config directory. After the first install, `/apply-core`
is available from any directory — no need to be in the repo.

## What Gets Installed

Shared artifacts install to `~/.degacore/` (`DEGA_CORE_HOME`):

| Component | Location | Purpose |
|-----------|----------|---------|
| **Settings Template** | `~/.degacore/settings-template.json` | Base settings used to generate agent-specific settings |
| **Agent Template** | `~/.degacore/config/agent-template.md` | Global dev standards + orchestrator instructions |
| **Commands** | `~/.degacore/config/commands/` | `/plan`, `/fix-issue`, `/review-pr`, `/cleanup`, `/doc-garden`, `/core-init` |
| **Rules** | `~/.degacore/config/rules/` | Language standards (Python, TypeScript, Rust, Bash, GitHub Actions) |
| **Skills** | `~/.degacore/config/skills/` | App legibility, custom linters, sound notifications |
| **Agents** | `~/.degacore/config/agents/` | Worker, verifier, and planner agent prompts |
| **Hooks** | `~/.degacore/scripts/hooks/` | Guardrails: block `rm -rf`, enforce package manager, play sounds |
| **Orchestrator** | `~/.degacore/scripts/orch-*.sh` | Parallel plan execution engine (needs `tmux`, `jq`) |
| **Terminal UI** | `~/.degacore/scripts/terminal-ui/` | Ink dashboard for monitoring runs (needs `node`, `pnpm`) |
| **Sounds** | `~/.degacore/sounds/` | Completion notification sounds (MP3 + OGG) |

Per-agent config is generated into each detected agent's directory:

| Agent | Directory | What's generated |
|-------|-----------|-----------------|
| Claude Code | `~/.claude/` | `settings.json`, `CLAUDE.md` shim, `commands/` symlink, `rules/` symlink |
| Gemini CLI | `~/.gemini/` | `GEMINI.md` shim, `commands/` symlink, `rules/` symlink |
| Codex CLI | `~/.codex/` | `CODEX.md` shim, `commands/` symlink, `rules/` symlink |

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
bash ~/.degacore/scripts/orch-run.sh <slug>                  # parallel
bash ~/.degacore/scripts/orch-run.sh <slug> --max-workers 1  # sequential
bash ~/.degacore/scripts/orch-run.sh <slug> --background     # headless
bash ~/.degacore/scripts/planner-loop.sh                     # autonomous
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
`develop` branch and overwrites engine scripts in `~/.degacore/` (safe — no
user customization). It asks before overwriting agent template or settings
template since those may have personal edits. Per-agent config (settings,
global instructions) is regenerated for each detected agent.
