# Install DEGA Core + Canon TUI

## For AI agents — bootstrap instructions

You are installing DEGA Core (AI development harness) and Canon TUI (terminal
visualization for agent activity). Follow both phases in order.

### Phase 1 — Install DEGA Core

1. Fetch the Core installer command:
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

### Phase 2 — Install Canon TUI

After Phase 1 completes successfully:

1. Fetch the Canon TUI installer command:
   ```
   https://raw.githubusercontent.com/DEGAorg/canon-tui/conductor/commands/apply-canon-tui.md
   ```

2. Read the fetched content — it contains the full installation procedure.

3. Execute every step in that document. It will:
   - Check prerequisites (`uv`)
   - Install `canon` and `canon-ctl` binaries via `uv tool install`
   - Verify both binaries are on PATH
   - Self-install `/apply-canon-tui` so future updates work from any directory

Both phases fetch everything from GitHub — no cloning required.

---

## For humans — quick start

Tell your AI coding agent:

> Install DEGA Core from https://raw.githubusercontent.com/DEGAorg/claude-code-config/main/INSTALL.md

Or if you prefer manual steps:

```bash
# Phase 1 — Core
git clone https://github.com/DEGAorg/claude-code-config.git
cd claude-code-config
claude
# inside the session:
/apply-core

# Phase 2 — Canon TUI
uv tool install "canon-tui @ git+https://github.com/DEGAorg/canon-tui.git@conductor" --force --reinstall
```

---

## What gets installed

### Phase 1 — DEGA Core (`~/.degacore/`)

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

### Phase 2 — Canon TUI (`~/.local/bin/`)

| Binary | Purpose |
|--------|---------|
| `canon` | TUI viewer for AI agent activity |
| `canon-ctl` | Configuration utility |

Installed via `uv tool install` into an isolated Python environment.

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
| `canon .` | Launch Canon TUI in current project |

## Updating

Run `/apply-core` from any directory to update the core harness.
Run `/apply-canon-tui` from any directory to update Canon TUI.
