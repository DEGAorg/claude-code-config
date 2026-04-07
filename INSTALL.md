# Install DEGA Core

## For AI agents — bootstrap instructions

You are installing DEGA Core, an AI development harness with an orchestrator,
structured logging, safety hooks, and multi-agent support.

**To install, fetch and execute the apply-core command from GitHub:**

1. Fetch the installer command:
   ```
   https://raw.githubusercontent.com/DEGAorg/claude-code-config/main/commands/apply-core.md
   ```

2. Read the fetched content — it contains the full installation procedure.

3. Execute every step in that document. It will:
   - Check prerequisites (`tmux`, `jq`, `node`, `pnpm`)
   - Ask the user which components to install
   - Fetch all selected files from GitHub
   - Install shared artifacts to `~/.degacore/`
   - Detect installed agents (Claude, Gemini, Codex)
   - Generate per-agent config (settings, commands, rules)
   - Self-install `/apply-core` so future updates work from any directory

No cloning required. Everything is fetched from GitHub at install time.

---

## For humans — quick start

Tell your AI coding agent:

> Install DEGA Core from https://raw.githubusercontent.com/DEGAorg/claude-code-config/main/INSTALL.md

Or if you prefer manual steps:

```bash
git clone https://github.com/DEGAorg/claude-code-config.git
cd claude-code-config
claude
# inside the session:
/apply-core
```

---

## What gets installed

Shared artifacts install to `~/.degacore/` (`DEGA_CORE_HOME`):

| Component | Location | Purpose |
|-----------|----------|---------|
| **Settings Template** | `settings-template.json` | Base settings for agent-specific config generation |
| **Agent Template** | `config/agent-template.md` | Global dev standards + orchestrator instructions |
| **Commands** | `config/commands/` | `/plan`, `/fix-issue`, `/review-pr`, `/cleanup`, `/doc-garden`, `/core-init` |
| **Rules** | `config/rules/` | Language standards (Python, TypeScript, Rust, Bash, GitHub Actions) |
| **Skills** | `config/skills/` | App legibility, custom linters, sound notifications |
| **Agents** | `config/agents/` | Worker, verifier, and planner agent prompts |
| **Hooks** | `scripts/hooks/` | Guardrails: block `rm -rf`, enforce package manager, play sounds |
| **Orchestrator** | `scripts/orch-*.sh` | Parallel plan execution engine (needs `tmux`, `jq`) |
| **Terminal UI** | `scripts/terminal-ui/` | Ink dashboard for monitoring runs (needs `node`, `pnpm`) |
| **Sounds** | `sounds/` | Completion notification sounds (MP3 + OGG) |

Per-agent config is generated into each detected agent's directory:

| Agent | Directory | What's generated |
|-------|-----------|-----------------|
| Claude Code | `~/.claude/` | `settings.json`, `CLAUDE.md` shim, `commands/` symlink, `rules/` symlink |
| Gemini CLI | `~/.gemini/` | `GEMINI.md` shim, `commands/` symlink, `rules/` symlink |
| Codex CLI | `~/.codex/` | `CODEX.md` shim, `commands/` symlink, `rules/` symlink |

## Enable a project

Run `/core-init` in any repo to set up the orchestrator:

```bash
cd your-project
claude
# inside the session:
/core-init
```

## Usage

```
/plan add input validation to the health endpoint
# then: "run this plan"
```

The orchestrator spawns parallel workers in tmux, reviews each item, and
iterates until everything passes.

| Command | What it does |
|---------|--------------|
| `/plan <task>` | Create an execution plan |
| `/fix-issue <number>` | Fix a GitHub issue end-to-end |
| `/review-pr <number>` | Review a PR with parallel agents |
| `/cleanup` | Scan for code quality issues |

## Updating

Run `/apply-core` from any directory. It fetches the latest and overwrites
engine scripts (safe — no user customization). It asks before overwriting
agent template or settings template since those may have personal edits.
