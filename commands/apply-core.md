# Apply Core

@description Install DEGA Core AI development artifacts globally to ~/.degacore/. Detects installed agents (Claude, Gemini, Codex) and generates per-agent config (settings, commands, rules).

Install Core harness artifacts from GitHub into `~/.degacore/` (DEGA_CORE_HOME).
Works from any directory — no need to clone the repo. Shared artifacts live in
`~/.degacore/` under a `config/`, `scripts/`, `state/`, `sounds/` layout.
Agent-specific config (settings, commands, rules) is generated into each
detected agent's config directory (`~/.<agent>/` — e.g. `.claude`, `.gemini`, `.codex`).

## Source

All files are fetched from:

```
https://raw.githubusercontent.com/DEGAorg/claude-code-config/main/
```

Files available:
- `settings.json`
- `agent-template.md`
- `commands/fix-issue.md`
- `commands/review-pr.md`
- `commands/plan.md`
- `commands/cleanup.md`
- `commands/doc-garden.md`
- `commands/core-init.md`
- `commands/canon-init.md`
- `commands/canon-start.md`
- `commands/core-update.md`
- `rules/python.md`
- `rules/node-typescript.md`
- `rules/rust.md`
- `rules/bash.md`
- `rules/github-actions.md`
- `hooks/enforce-loop-mode.sh`
- `hooks/enforce-exec-plan-naming.sh`
- `hooks/enforce-package-manager.sh`
- `hooks/log-gam.sh`
- `hooks/update-exec-plan-reminder.sh`
- `hooks/session-start-logging.sh`
- `hooks/structured-log.sh`
- `hooks/ralph-reviewer-stop.sh`
- `skills/custom-linter-authoring.md`
- `skills/app-legibility.md`
- `skills/sound-notifications.md`
- `scripts/agent-shim.sh`
- `scripts/adapters/claude-settings.sh`
- `scripts/adapters/gemini-settings.sh`
- `scripts/adapters/codex-settings.sh`
- `settings-template.json`
- `scripts/log-server.py`
- `scripts/statusline.sh`
- `scripts/core-version.sh`
- `VERSION`
- `CORE_VERSION.md`
- `dega-core.yaml`
- `scripts/ralph-check.sh`
- `scripts/ralph-loop.sh`
- `scripts/ralph-worker-prompt.md`
- `scripts/ralph-reviewer-prompt.md`
- `scripts/log-client.sh`
- `scripts/plan-advance.sh`
- `scripts/task-complete.sh`
- `scripts/canon-runner.sh`
- `scripts/canon-live-readiness.sh`
- `scripts/ralph-worktree.sh`
- `scripts/terminal-session.sh`
- `scripts/terminal-ui-write.sh`
- `scripts/terminal-ui/package.json`
- `scripts/terminal-ui/tsconfig.json`
- `scripts/terminal-ui/src/types.ts`
- `scripts/terminal-ui/src/write.ts`
- `scripts/terminal-ui/src/verify-shell-compat.ts`
- `scripts/terminal-ui/src/cli.tsx`
- `scripts/terminal-ui/src/app.tsx`
- `scripts/terminal-ui/src/status-bar.tsx`
- `scripts/terminal-ui/src/log-panel.tsx`
- `scripts/terminal-ui/src/metrics-panel.tsx`
- `scripts/canon-scaffold.sh`
- `scripts/canon.sh`
- `scripts/orch-run.sh`
- `scripts/orch-display.sh`
- `scripts/orch-parse-items.sh`
- `scripts/orch-state.sh`
- `scripts/orch-review.sh`
- `scripts/orch-engine.sh`
- `scripts/orch-verify.sh`
- `scripts/ralph-item-reviewer-prompt.md`
- `agents/orch-worker.md`
- `agents/orch-verifier.md`
- `hooks/orch-done-sync.sh`
- `scripts/planner-loop.sh`
- `agents/planner-assess.md`
- `agents/planner-writer.md`
- `sounds/unstoppable.mp3`
- `sounds/super-mario-bros.mp3`
- `sounds/yeahoo.mp3`
- `sounds/warzone-level-up.mp3`
- `sounds/unstoppable.ogg`
- `sounds/super-mario-bros.ogg`
- `sounds/yeahoo.ogg`
- `sounds/warzone-level-up.ogg`
- `sounds/tick.mp3`
- `sounds/tick.ogg`
- `hooks/play-sound.sh`
- `scripts/ensure-gh.sh`
- `scripts/gh-plan-fetch.sh`
- `scripts/gh-plan-sync.sh`
- `scripts/plan-create.sh`
- `scripts/plan-upload.sh`
- `scripts/read-github-config.sh`
- `scripts/create-exec-plan.sh`
- `hooks/orch-lifecycle/01-gh-plan-sync.sh`
- `canon/cli/package.json`
- `canon/cli/tsconfig.json`
- `canon/cli/canon-cli.ts`
- `canon/cli/output.ts`
- `canon/cli/auth.ts`
- `canon/cli/env.ts`
- `canon/cli/wallet-store.ts`
- `canon/cli/commands/index.ts`
- `canon/cli/commands/market.ts`
- `canon/cli/commands/position.ts`
- `canon/cli/commands/balance.ts`
- `canon/cli/commands/order.ts`
- `canon/cli/commands/kill.ts`
- `canon/cli/commands/onboard.ts`
- `canon/cli/commands/wallet.ts`
- `canon/cli/commands/help.ts`
- `canon/skills/canon-cli.md`
- `canon/skills/polymarket.md`
- `canon/templates/` (entire directory — project shell copied wholesale by scaffold)

---

## Steps

### 0. Check prerequisites

Check if these tools are available:

| Tool | Required by | Check command |
|------|-------------|---------------|
| `tmux` | Orchestrator | `command -v tmux` |
| `jq` | Orchestrator, hooks | `command -v jq` |
| `node` | Terminal UI dashboard | `command -v node` |
| `pnpm` | Terminal UI dashboard | `command -v pnpm` |

If all are present, continue. If any are missing:

1. List which tools are missing
2. Detect the platform and package manager:
   - **macOS**: `brew install <missing tools>`
   - **Debian/Ubuntu**: `sudo apt-get install -y <missing tools>`
     (`node` -> install via `curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt-get install -y nodejs`;
      `pnpm` -> `npm install -g pnpm`)
   - **Fedora/RHEL**: `sudo dnf install -y <missing tools>`
     (`node` -> `sudo dnf module install -y nodejs:22`;
      `pnpm` -> `npm install -g pnpm`)
   - **Arch**: `sudo pacman -S --noconfirm <missing tools>`
     (`pnpm` -> `npm install -g pnpm`)
3. Ask: "Install missing prerequisites? (y/n)" and show the exact command
4. If yes, run it
5. If no, warn that Orchestrator and Terminal UI will not work without them,
   but allow the rest of the install to continue

---

### 1. Inventory what exists

Read and note which of these already exist under `~/.degacore/`:
- `~/.degacore/settings-template.json`
- `~/.degacore/config/agent-template.md`
- `~/.degacore/config/commands/` (any files)
- `~/.degacore/config/rules/` (any files)
- `~/.degacore/config/skills/` (any files)
- `~/.degacore/config/agents/` (any files)
- `~/.degacore/scripts/agent-shim.sh`
- `~/.degacore/scripts/adapters/` (claude-settings.sh, gemini-settings.sh, codex-settings.sh)
- `~/.degacore/scripts/statusline.sh`
- `~/.degacore/scripts/log-server.py`
- `~/.degacore/scripts/hooks/` (any files)
- `~/.degacore/scripts/hooks/orch-lifecycle/` (any files)
- `~/.degacore/scripts/terminal-session.sh`
- `~/.degacore/scripts/terminal-ui-write.sh`
- `~/.degacore/scripts/terminal-ui/` (any files)
- `~/.degacore/scripts/orch-run.sh`
- `~/.degacore/scripts/orch-engine.sh`
- `~/.degacore/scripts/orch-display.sh`
- `~/.degacore/scripts/orch-parse-items.sh`
- `~/.degacore/scripts/orch-state.sh`
- `~/.degacore/scripts/orch-review.sh`
- `~/.degacore/scripts/orch-verify.sh`
- `~/.degacore/scripts/ralph-item-reviewer-prompt.md`
- `~/.degacore/scripts/planner-loop.sh`
- `~/.degacore/scripts/canon-scaffold.sh`
- `~/.degacore/scripts/canon.sh`
- `~/.degacore/scripts/canon-runner.sh`
- `~/.degacore/scripts/canon-live-readiness.sh`
- `~/.degacore/scripts/ensure-gh.sh`
- `~/.degacore/scripts/gh-plan-fetch.sh`
- `~/.degacore/scripts/gh-plan-sync.sh`
- `~/.degacore/scripts/plan-create.sh`
- `~/.degacore/scripts/plan-upload.sh`
- `~/.degacore/scripts/read-github-config.sh`
- `~/.degacore/scripts/create-exec-plan.sh`
- `~/.degacore/sounds/` (any files)
- `~/.degacore/state/logs/`
- `~/.degacore/state/planner/`
- `~/.degacore/bin/canon-cli`
- `~/.degacore/canon-cli/` (any files)

Also detect installed agents by checking for their CLI binaries:

```bash
command -v claude  # Claude Code
command -v gemini  # Gemini CLI
command -v codex   # Codex CLI
```

If a binary is found, the agent is considered installed. Also check for
existing config directories (`~/.<agent>/` — `.claude`, `.gemini`, `.codex`) —
an agent is detected if either the binary exists or the config directory
exists.

Also check in the current working directory (target project root):
- `dega-core.yaml`

---

### 2. Ask the user what to install

Use AskUserQuestion with a single multi-select question. List each component
with a short description. Pre-label as recommended any component that is
missing from `~/.degacore/`.

Components:
- **Settings Template** — permissions, hooks (rm-rf blocker, push-to-main blocker, doc-reminder), telemetry off.
  Installed to `~/.degacore/settings-template.json` and used to generate agent-specific settings files.
- **Agent Template** — global development standards: philosophy, no speculative features, agent-native by default.
  Installed to `~/.degacore/config/agent-template.md` and used to generate agent-specific global instructions.
- **Commands** — fix-issue, review-pr, plan, cleanup, doc-garden, core-init slash commands.
  Installed to `~/.degacore/config/commands/` and linked into each detected agent's config.
- **Rules** — language-specific standards auto-loaded by file type (python, node-typescript, rust, bash, github-actions).
  Installed to `~/.degacore/config/rules/` and linked into each detected agent's config.
- **Hooks** — enforce-package-manager and log-gam shell scripts.
  Installed to `~/.degacore/scripts/hooks/`.
- **Skills** — custom-linter-authoring, app-legibility, and sound-notifications knowledge files.
  Installed to `~/.degacore/config/skills/`.
- **Logging** — `log-server.py` global Python log server; writes structured JSONL to
  `~/.degacore/state/logs/`. One server per machine, shared by all projects.
  Also installs `session-start-logging.sh` (starts log server on session open) and
  `structured-log.sh` (records every tool call) as global hooks to `~/.degacore/scripts/hooks/`.
  GCP Cloud Logging is zero-config: drop `~/.degacore/gcp-sa.json` and it auto-enables.
  (recommended when `~/.degacore/scripts/log-server.py` is missing)
- **Legacy Scripts (Ralph Loop)** — legacy engine scripts that still work but
  are superseded by the Orchestrator. Installs globally to `~/.degacore/scripts/`
  (`ralph-loop.sh`, `ralph-worktree.sh`, `ralph-check.sh`,
  `ralph-worker-prompt.md`, `ralph-reviewer-prompt.md`, `log-client.sh`,
  `plan-advance.sh`, `task-complete.sh`); only `dega-core.yaml` is per-project
  (written to cwd). Use the Orchestrator instead for new work.
  (opt-in; not recommended — use Orchestrator)
- **Sounds** — notification sounds that play when Claude finishes a task.
  Works on macOS, Linux, and WSL2. Linux needs one of: `mpv`, `ffplay`, or
  `paplay` (PulseAudio/PipeWire). Installs MP3 and OGG files to
  `~/.degacore/sounds/` and the `play-sound.sh` hook to `~/.degacore/scripts/hooks/`.
  Configured via `DEGA_SOUND` env var in settings
  (default: `super-mario-bros`). Available values: `unstoppable`,
  `super-mario-bros`, `yeahoo`, `warzone-level-up`, `none`. Set to `none`
  to disable. Volume controlled via `DEGA_SOUND_VOLUME` (0-100, default 50).
  (recommended when `~/.degacore/sounds/` is missing)
- **Terminal UI** — visual status dashboard for automation sessions. Includes
  tmux session launcher (`terminal-session.sh`), state file writer
  (`terminal-ui-write.sh`), and Ink status dashboard (`terminal-ui/`).
  Requires Node.js. Installs scripts to `~/.degacore/scripts/` and builds
  the Ink app with `pnpm install && pnpm run build`.
  (opt-in; recommended when `~/.degacore/scripts/terminal-ui/` is missing)
- **Orchestrator** — tmux-based orchestrator: persistent state layer + wave-based
  parallel execution. Installs launcher (`orch-run.sh`), engine loop
  (`orch-engine.sh`), display opener (`orch-display.sh`), state library
  (`orch-state.sh`), plan parser (`orch-parse-items.sh`), review script
  (`orch-review.sh`), completion verifier (`orch-verify.sh`), GitHub plan
  scripts (`ensure-gh.sh`, `gh-plan-fetch.sh`, `gh-plan-sync.sh`,
  `plan-create.sh`, `plan-upload.sh`, `read-github-config.sh`,
  `create-exec-plan.sh`) to `~/.degacore/scripts/`, done-file sync hook
  (`orch-done-sync.sh`) and lifecycle hook (`orch-lifecycle/01-gh-plan-sync.sh`)
  to `~/.degacore/scripts/hooks/`, Ink dashboard components to
  `~/.degacore/scripts/terminal-ui/src/`, and agent definitions
  (`orch-worker.md`, `orch-verifier.md`) to `~/.degacore/config/agents/`. Polling
  interval controlled by `poll_interval_seconds` in `dega-core.yaml`
  (default 30). Requires Terminal UI and tmux. Invoke via
  `~/.degacore/scripts/orch-run.sh <slug>`.
  (opt-in; recommended when `~/.degacore/scripts/orch-run.sh` is missing)
- **Planner** — autonomous planner loop that reads `focus.yaml`, assesses the
  project, writes execution plans, and launches the orchestrator. Installs
  `planner-loop.sh` to `~/.degacore/scripts/` and agent prompts
  (`planner-assess.md`, `planner-writer.md`) to `~/.degacore/config/agents/`.
  Requires Orchestrator. Invoke via
  `~/.degacore/scripts/planner-loop.sh`.
  (opt-in; recommended when `~/.degacore/scripts/planner-loop.sh` is missing)
- **Canon Bootstrap** — launcher, scaffold scripts, project templates, and CLI
  for Canon prediction market projects. Installs `canon-scaffold.sh`
  (deterministic project scaffolder called by `/canon-start`), `canon.sh`
  (tmux launcher), `canon/templates/` (complete project shell with shared
  runner, types, clients, and strategy modules like arb-binary), and the Canon CLI
  (`canon-cli`) — an agent-callable TypeScript tool for querying markets,
  managing positions, and executing trades on Polymarket. The CLI is built
  with `pnpm install` and linked to `~/.degacore/bin/canon-cli`. Add
  `~/.degacore/bin` to your `PATH` to use `canon-cli` from any directory.
  (opt-in; recommended when `~/.degacore/scripts/canon-scaffold.sh` is missing)

---

### 3. Fetch selected files

Use WebFetch to download only the files needed for the user's selections from
the GitHub URLs above. Extract the raw file content from each response.

---

### 4. Create directory layout and install to `~/.degacore/`

Create the `~/.degacore/` directory tree if it doesn't exist:

```bash
mkdir -p ~/.degacore/{bin,config/{commands,skills,rules,agents},scripts/{adapters,hooks/orch-lifecycle,terminal-ui/src},state/{logs,planner},sounds,canon-cli/commands}
```

Also install the agent-shim and adapter scripts (always, regardless of
component selection — other scripts depend on them):
- `scripts/agent-shim.sh` -> `~/.degacore/scripts/agent-shim.sh`
- `scripts/adapters/claude-settings.sh` -> `~/.degacore/scripts/adapters/claude-settings.sh`
- `scripts/adapters/gemini-settings.sh` -> `~/.degacore/scripts/adapters/gemini-settings.sh`
- `scripts/adapters/codex-settings.sh` -> `~/.degacore/scripts/adapters/codex-settings.sh`

Run `chmod +x` on all four scripts.

Install each selected component to its `~/.degacore/` location:

#### Settings Template

- If `~/.degacore/settings-template.json` does **not** exist: write the
  fetched `settings.json` content to `~/.degacore/settings-template.json`.
- If it **does** exist: read both files and merge the repo's keys into the
  existing file — preserve any user keys that don't conflict. Show the merged
  result and ask for confirmation before writing.

#### Agent Template

- If `~/.degacore/config/agent-template.md` does **not** exist: write the
  fetched `agent-template.md` to `~/.degacore/config/agent-template.md`.
- If it **already exists**: tell the user it exists and ask whether to
  overwrite, skip, or show a diff. Never silently overwrite — it likely has
  personal customizations.

#### Commands

Write each selected command file to `~/.degacore/config/commands/<name>.md`.
Safe to overwrite — commands have no user customization.

#### Rules

Write each rule file to `~/.degacore/config/rules/<name>.md`. Safe to
overwrite.

#### Hooks

Write each hook file to `~/.degacore/scripts/hooks/<name>.sh` and
`chmod +x` it. Safe to overwrite.

#### Enforcement — Global hooks

Write and `chmod +x` each file:
- `hooks/enforce-loop-mode.sh` -> `~/.degacore/scripts/hooks/enforce-loop-mode.sh`
- `hooks/enforce-exec-plan-naming.sh` -> `~/.degacore/scripts/hooks/enforce-exec-plan-naming.sh`
- `hooks/enforce-package-manager.sh` -> `~/.degacore/scripts/hooks/enforce-package-manager.sh`

Safe to overwrite. These are PreToolUse guard hooks referenced by
`settings-template.json`. `enforce-loop-mode.sh` blocks destructive
commands and restricts git operations in ralph loop mode.
`enforce-exec-plan-naming.sh` enforces YYYYMMDD-slug naming for
exec-plan directories. `enforce-package-manager.sh` enforces use of
the configured package manager.

#### Skills

Write each skill file to `~/.degacore/config/skills/<name>.md`. Safe to
overwrite.

#### Logging — Global scripts

Write `scripts/log-server.py` to `~/.degacore/scripts/log-server.py`. Safe to
overwrite.

Write `scripts/statusline.sh` to `~/.degacore/scripts/statusline.sh` and
`chmod +x` it. Safe to overwrite.

#### Logging — Global hooks

Write and `chmod +x` each file:
- `hooks/session-start-logging.sh` -> `~/.degacore/scripts/hooks/session-start-logging.sh`
- `hooks/structured-log.sh` -> `~/.degacore/scripts/hooks/structured-log.sh`
- `hooks/ralph-reviewer-stop.sh` -> `~/.degacore/scripts/hooks/ralph-reviewer-stop.sh`

Safe to overwrite. These hooks reference `${DEGA_CORE_HOME}/scripts/log-server.py`
so they work from any project directory. The reviewer stop hook is scoped
via `RALPH_ROLE` env var — it's a no-op outside ralph loop sessions.

#### Legacy Scripts (Ralph Loop) — Global scripts

Write each engine script to `~/.degacore/scripts/`:
- `scripts/ralph-loop.sh` -> `~/.degacore/scripts/ralph-loop.sh`
- `scripts/ralph-worktree.sh` -> `~/.degacore/scripts/ralph-worktree.sh`
- `scripts/ralph-check.sh` -> `~/.degacore/scripts/ralph-check.sh`
- `scripts/ralph-worker-prompt.md` -> `~/.degacore/scripts/ralph-worker-prompt.md`
- `scripts/ralph-reviewer-prompt.md` -> `~/.degacore/scripts/ralph-reviewer-prompt.md`
- `scripts/log-client.sh` -> `~/.degacore/scripts/log-client.sh`
- `scripts/plan-advance.sh` -> `~/.degacore/scripts/plan-advance.sh`
- `scripts/task-complete.sh` -> `~/.degacore/scripts/task-complete.sh`
- `scripts/canon-runner.sh` -> `~/.degacore/scripts/canon-runner.sh`

Run `chmod +x` on all `.sh` files after writing.
Safe to overwrite — these are engine scripts with no user customization.

#### Legacy Scripts (Ralph Loop) — Per-project config

- If `dega-core.yaml` does **not** exist in the cwd: write it directly.
- If it **does** exist: tell the user it exists and ask whether to
  overwrite, skip, or show a diff. Never silently overwrite — the user
  may have customized `max_iterations`, `poll_interval_seconds`, or
  `success_criteria`.

#### Sounds

Write each sound file (MP3 and OGG) to `~/.degacore/sounds/`:
- `sounds/unstoppable.mp3` -> `~/.degacore/sounds/unstoppable.mp3`
- `sounds/super-mario-bros.mp3` -> `~/.degacore/sounds/super-mario-bros.mp3`
- `sounds/yeahoo.mp3` -> `~/.degacore/sounds/yeahoo.mp3`
- `sounds/warzone-level-up.mp3` -> `~/.degacore/sounds/warzone-level-up.mp3`
- `sounds/unstoppable.ogg` -> `~/.degacore/sounds/unstoppable.ogg`
- `sounds/super-mario-bros.ogg` -> `~/.degacore/sounds/super-mario-bros.ogg`
- `sounds/yeahoo.ogg` -> `~/.degacore/sounds/yeahoo.ogg`
- `sounds/warzone-level-up.ogg` -> `~/.degacore/sounds/warzone-level-up.ogg`
- `sounds/tick.mp3` -> `~/.degacore/sounds/tick.mp3`
- `sounds/tick.ogg` -> `~/.degacore/sounds/tick.ogg`

Safe to overwrite — these are static assets with no user customization.
OGG files are needed for `paplay` on Linux (cannot decode MP3).

Write `hooks/play-sound.sh` to `~/.degacore/scripts/hooks/play-sound.sh` and
`chmod +x` it. Safe to overwrite.

#### Terminal UI

Write each file to its corresponding path under `~/.degacore/scripts/`:
- `scripts/terminal-session.sh` -> `~/.degacore/scripts/terminal-session.sh`
- `scripts/terminal-ui-write.sh` -> `~/.degacore/scripts/terminal-ui-write.sh`
- `scripts/terminal-ui/package.json` -> `~/.degacore/scripts/terminal-ui/package.json`
- `scripts/terminal-ui/tsconfig.json` -> `~/.degacore/scripts/terminal-ui/tsconfig.json`
- `scripts/terminal-ui/src/types.ts` -> `~/.degacore/scripts/terminal-ui/src/types.ts`
- `scripts/terminal-ui/src/write.ts` -> `~/.degacore/scripts/terminal-ui/src/write.ts`
- `scripts/terminal-ui/src/verify-shell-compat.ts` -> `~/.degacore/scripts/terminal-ui/src/verify-shell-compat.ts`
- `scripts/terminal-ui/src/cli.tsx` -> `~/.degacore/scripts/terminal-ui/src/cli.tsx`
- `scripts/terminal-ui/src/app.tsx` -> `~/.degacore/scripts/terminal-ui/src/app.tsx`
- `scripts/terminal-ui/src/status-bar.tsx` -> `~/.degacore/scripts/terminal-ui/src/status-bar.tsx`
- `scripts/terminal-ui/src/log-panel.tsx` -> `~/.degacore/scripts/terminal-ui/src/log-panel.tsx`
- `scripts/terminal-ui/src/metrics-panel.tsx` -> `~/.degacore/scripts/terminal-ui/src/metrics-panel.tsx`

Run `chmod +x ~/.degacore/scripts/terminal-session.sh ~/.degacore/scripts/terminal-ui-write.sh` after writing.

Then build the Ink dashboard:
```bash
cd ~/.degacore/scripts/terminal-ui && pnpm install && pnpm run build
```

If `pnpm` is not available, fall back to `npm install && npm run build`.

Safe to overwrite — these are engine scripts and app source with no user customization.

#### Orchestrator

Write each shell script to `~/.degacore/scripts/`:
- `scripts/orch-run.sh` -> `~/.degacore/scripts/orch-run.sh`
- `scripts/orch-engine.sh` -> `~/.degacore/scripts/orch-engine.sh`
- `scripts/orch-display.sh` -> `~/.degacore/scripts/orch-display.sh`
- `scripts/orch-parse-items.sh` -> `~/.degacore/scripts/orch-parse-items.sh`
- `scripts/orch-state.sh` -> `~/.degacore/scripts/orch-state.sh`
- `scripts/orch-review.sh` -> `~/.degacore/scripts/orch-review.sh`
- `scripts/orch-verify.sh` -> `~/.degacore/scripts/orch-verify.sh`
- `scripts/ralph-item-reviewer-prompt.md` -> `~/.degacore/scripts/ralph-item-reviewer-prompt.md`

Run `chmod +x ~/.degacore/scripts/orch-*.sh` after writing.

Write GitHub plan scripts to `~/.degacore/scripts/`:
- `scripts/ensure-gh.sh` -> `~/.degacore/scripts/ensure-gh.sh`
- `scripts/gh-plan-fetch.sh` -> `~/.degacore/scripts/gh-plan-fetch.sh`
- `scripts/gh-plan-sync.sh` -> `~/.degacore/scripts/gh-plan-sync.sh`
- `scripts/plan-create.sh` -> `~/.degacore/scripts/plan-create.sh`
- `scripts/plan-upload.sh` -> `~/.degacore/scripts/plan-upload.sh`
- `scripts/read-github-config.sh` -> `~/.degacore/scripts/read-github-config.sh`
- `scripts/create-exec-plan.sh` -> `~/.degacore/scripts/create-exec-plan.sh`

Run `chmod +x` on all `.sh` files above after writing.

Write the done-sync hook and lifecycle hook:
- `hooks/orch-done-sync.sh` -> `~/.degacore/scripts/hooks/orch-done-sync.sh`
- `hooks/orch-lifecycle/01-gh-plan-sync.sh` -> `~/.degacore/scripts/hooks/orch-lifecycle/01-gh-plan-sync.sh`

Run `chmod +x` on both after writing.

Write each Ink component to `~/.degacore/scripts/terminal-ui/src/`:
- `scripts/terminal-ui/src/orch-types.ts` -> `~/.degacore/scripts/terminal-ui/src/orch-types.ts`
- `scripts/terminal-ui/src/orchestrator-app.tsx` -> `~/.degacore/scripts/terminal-ui/src/orchestrator-app.tsx`
- `scripts/terminal-ui/src/session-table.tsx` -> `~/.degacore/scripts/terminal-ui/src/session-table.tsx`
- `scripts/terminal-ui/src/session-detail.tsx` -> `~/.degacore/scripts/terminal-ui/src/session-detail.tsx`

Write the agent definitions to `~/.degacore/config/agents/`:
- `agents/orch-worker.md` -> `~/.degacore/config/agents/orch-worker.md`
- `agents/orch-verifier.md` -> `~/.degacore/config/agents/orch-verifier.md`
- `agents/conductor.md` -> `~/.degacore/config/agents/conductor.md`

Safe to overwrite — these are engine scripts, hooks, components, and agent
definitions with no user customization.

If Terminal UI was also selected, the `pnpm install && pnpm run build` step
in that section will pick up the new orchestrator components automatically.
If Terminal UI was not selected but the Ink app was previously installed,
rebuild it:
```bash
cd ~/.degacore/scripts/terminal-ui && pnpm install && pnpm run build
```

#### Planner

Write the planner loop script:
- `scripts/planner-loop.sh` -> `~/.degacore/scripts/planner-loop.sh`

Run `chmod +x ~/.degacore/scripts/planner-loop.sh` after writing.

Write the agent prompts:
- `agents/planner-assess.md` -> `~/.degacore/config/agents/planner-assess.md`
- `agents/planner-writer.md` -> `~/.degacore/config/agents/planner-writer.md`

Safe to overwrite — these are engine scripts and agent definitions with no
user customization.

#### Canon Bootstrap

Write each file to `~/.degacore/scripts/`:
- `scripts/canon-scaffold.sh` -> `~/.degacore/scripts/canon-scaffold.sh`
- `scripts/canon.sh` -> `~/.degacore/scripts/canon.sh`
- `scripts/canon-runner.sh` -> `~/.degacore/scripts/canon-runner.sh`
- `scripts/canon-live-readiness.sh` -> `~/.degacore/scripts/canon-live-readiness.sh`

Run `chmod +x ~/.degacore/scripts/canon-scaffold.sh ~/.degacore/scripts/canon.sh ~/.degacore/scripts/canon-runner.sh ~/.degacore/scripts/canon-live-readiness.sh` after writing.

Clone the `canon/templates/` directory to `~/.degacore/canon/templates/`. This is
the project shell that `canon-scaffold.sh` copies wholesale into new projects.
Instead of fetching files individually, use `gh` to download the directory:

```bash
rm -rf ~/.degacore/canon/templates
mkdir -p ~/.degacore/canon
cd /tmp && rm -rf _canon_tpl && mkdir _canon_tpl && cd _canon_tpl
gh api repos/DEGAorg/claude-code-config/tarball/main \
  --header 'Accept: application/vnd.github+json' > repo.tar.gz
tar xzf repo.tar.gz --strip-components=1
cp -R canon/templates ~/.degacore/canon/templates
cd / && rm -rf /tmp/_canon_tpl
```

Verify the templates are present:
```bash
test -f ~/.degacore/canon/templates/runner.ts && \
test -f ~/.degacore/canon/templates/package.json && \
test -d ~/.degacore/canon/templates/strategies/arb-binary && \
echo "templates OK" || echo "templates MISSING"
```

Safe to overwrite — these are template files with no user customization.

#### Canon CLI

Write each source file to `~/.degacore/canon-cli/`:
- `canon/cli/package.json` -> `~/.degacore/canon-cli/package.json`
- `canon/cli/tsconfig.json` -> `~/.degacore/canon-cli/tsconfig.json`
- `canon/cli/canon-cli.ts` -> `~/.degacore/canon-cli/canon-cli.ts`
- `canon/cli/output.ts` -> `~/.degacore/canon-cli/output.ts`
- `canon/cli/auth.ts` -> `~/.degacore/canon-cli/auth.ts`
- `canon/cli/env.ts` -> `~/.degacore/canon-cli/env.ts`
- `canon/cli/wallet-store.ts` -> `~/.degacore/canon-cli/wallet-store.ts`
- `canon/cli/commands/index.ts` -> `~/.degacore/canon-cli/commands/index.ts`
- `canon/cli/commands/market.ts` -> `~/.degacore/canon-cli/commands/market.ts`
- `canon/cli/commands/position.ts` -> `~/.degacore/canon-cli/commands/position.ts`
- `canon/cli/commands/balance.ts` -> `~/.degacore/canon-cli/commands/balance.ts`
- `canon/cli/commands/order.ts` -> `~/.degacore/canon-cli/commands/order.ts`
- `canon/cli/commands/kill.ts` -> `~/.degacore/canon-cli/commands/kill.ts`
- `canon/cli/commands/onboard.ts` -> `~/.degacore/canon-cli/commands/onboard.ts`
- `canon/cli/commands/wallet.ts` -> `~/.degacore/canon-cli/commands/wallet.ts`
- `canon/cli/commands/help.ts` -> `~/.degacore/canon-cli/commands/help.ts`

Write the agent discovery skills:
- `canon/skills/canon-cli.md` -> `~/.degacore/config/skills/canon-cli.md`
- `canon/skills/polymarket.md` -> `~/.degacore/config/skills/polymarket.md`

Safe to overwrite — these are CLI source files and skills with no user
customization.

Then install dependencies. After `pnpm install`, two post-install steps
are required because `canon-cli/package.json` declares
`"canon-templates": "file:../templates"` — that path is relative to the
**source repo** layout (`canon/cli` and `canon/templates` are siblings
there), not the install layout where `canon-cli` lives at
`~/.degacore/canon-cli/` and templates live at
`~/.degacore/canon/templates/`. After install, `pnpm` resolves
`file:../templates` to `~/.degacore/templates/` (a stale or absent dir),
not the current templates we just laid down. Retarget the symlink so
`import "canon-templates/<file>.js"` from `canon-cli` resolves to the
real templates directory.

Also, `canon-cli.ts`'s shebang is `#!/usr/bin/env tsx`, which requires
`tsx` on global `PATH`. After `pnpm install`, `tsx` is only at
`~/.degacore/canon-cli/node_modules/.bin/tsx`. So instead of symlinking
the `.ts` directly, write a shell wrapper at `~/.degacore/bin/canon-cli`
that explicitly invokes the local `tsx`.

```bash
cd ~/.degacore/canon-cli && pnpm install

# Retarget the canon-templates link to the actual templates dir installed
# by Canon Bootstrap above. Idempotent — overwrites any prior link.
trash ~/.degacore/canon-cli/node_modules/canon-templates 2>/dev/null || true
ln -sf ~/.degacore/canon/templates ~/.degacore/canon-cli/node_modules/canon-templates

# Also pnpm install the templates package so its own deps (e.g.
# @polymarket/builder-signing-sdk) get hoisted into
# ~/.degacore/canon/templates/node_modules/ where canon-cli's runtime
# imports of canon-templates/polymarket-onboard.js can resolve them.
cd ~/.degacore/canon/templates && pnpm install

# Write a shell wrapper that uses the local tsx (canon-cli node_modules).
cat > ~/.degacore/bin/canon-cli <<'WRAPPER'
#!/bin/sh
# Canon CLI launcher — runs canon-cli.ts via local tsx (installed by canon-cli package).
exec "$HOME/.degacore/canon-cli/node_modules/.bin/tsx" "$HOME/.degacore/canon-cli/canon-cli.ts" "$@"
WRAPPER
chmod +x ~/.degacore/bin/canon-cli
```

If `pnpm` is not available, fall back to `npm install` (the wrapper and
symlink steps are unchanged).

Verify the install works:
```bash
~/.degacore/bin/canon-cli --help
```

If the user does not have `~/.degacore/bin` on their `PATH`, advise them
to add it:
```bash
export PATH="$HOME/.degacore/bin:$PATH"
```

Add this line to `~/.zshrc` or `~/.bashrc` for persistence.

---

### 5. Detect agents and generate per-agent config

After installing shared artifacts to `~/.degacore/`, detect which AI coding
agents are installed and generate agent-specific config for each one.

#### Detection

Detect installed agents using both binary presence and config directory existence:

```bash
command -v claude && HAVE_CLAUDE=1
command -v gemini && HAVE_GEMINI=1
command -v codex  && HAVE_CODEX=1

# Also detect by config directory (agent may be installed but not on PATH)
[[ -d ~/.claude ]] && HAVE_CLAUDE=1
[[ -d ~/.gemini ]] && HAVE_GEMINI=1
[[ -d ~/.codex ]]  && HAVE_CODEX=1
```

If no agents are detected, default to Claude Code (create its config directory).

Report which agents were detected before proceeding.

#### Per-agent settings generation

For each detected agent, run its adapter script to generate settings from
the shared template. The adapters read `~/.degacore/settings-template.json`
and write agent-specific config to the agent's config directory.

| Agent | Adapter script | Output |
|-------|---------------|--------|
| Claude | `~/.degacore/scripts/adapters/claude-settings.sh` | `$HOME/.claude/settings.json` |
| Gemini | `~/.degacore/scripts/adapters/gemini-settings.sh` | `~/.gemini/settings.json` |
| Codex | `~/.degacore/scripts/adapters/codex-settings.sh` | `~/.codex/config.toml` + `~/.codex/hooks.json` |

Run the adapter only if the **Settings Template** component was selected.
Each adapter handles its own merge/overwrite logic:

- If the agent's settings file does **not** exist: write it directly.
- If it **does** exist: read both files and merge the template's keys
  into the existing file — preserve any user keys that don't conflict.
  Show the merged result and ask for confirmation before writing.

```bash
# Run adapter for each detected agent
[[ "${HAVE_CLAUDE:-}" == 1 ]] && bash ~/.degacore/scripts/adapters/claude-settings.sh
[[ "${HAVE_GEMINI:-}" == 1 ]] && bash ~/.degacore/scripts/adapters/gemini-settings.sh
[[ "${HAVE_CODEX:-}" == 1 ]]  && bash ~/.degacore/scripts/adapters/codex-settings.sh
```

#### Global instructions file (AGENTS.md shims)

Each agent looks for a specific instruction file. Claude and Gemini need
thin shims that redirect to `AGENTS.md` (the project-level single source
of truth). Codex reads `AGENTS.md` natively (configured via
`model_instructions_file = "AGENTS.md"` in its `config.toml`).

| Agent | Instruction file | Content |
|-------|-----------------|---------|
| Claude | `$HOME/.claude/CLAUDE.md` | Shim pointing to `AGENTS.md` |
| Gemini | `~/.gemini/GEMINI.md` | Shim pointing to `AGENTS.md` |
| Codex | *(none needed)* | Reads `AGENTS.md` natively via config.toml |

If the **Agent Template** component was selected, for Claude and Gemini:

- If the agent's instruction file does **not** exist: write a thin shim:
  ```markdown
  # Agent Configuration

  Read and follow all instructions in AGENTS.md
  ```
- If it **already exists**: tell the user it exists and ask whether to
  overwrite, skip, or show a diff. Never silently overwrite.

Codex does not need an instruction shim — the codex-settings adapter
sets `model_instructions_file = "AGENTS.md"` in `config.toml`, which
tells Codex to read `AGENTS.md` directly.

#### Commands (copy per file)

If the **Commands** component was selected, copy each command file into
each agent's config directory. This preserves any existing user commands.

For each detected agent:
```bash
mkdir -p ~/.<agent>/commands
cp ~/.degacore/config/commands/*.md ~/.<agent>/commands/
```

If a file with the same name already exists, skip it and warn:
"`<name>` already exists — skipping (user version takes precedence)."

#### Rules (copy per file)

Same strategy as commands:

```bash
mkdir -p ~/.<agent>/rules
cp ~/.degacore/config/rules/*.md ~/.<agent>/rules/
```

Same skip-and-warn handling: user files with the same name take precedence.

---

### 5b. Record the install version

Copy the repo's `VERSION` and `CORE_VERSION.md` files to `~/.degacore/` so
the install records which release it is on and the AI has the
natural-language reference on hand when asked "what core version am I on?".

Fetch and write each file:

```
https://raw.githubusercontent.com/DEGAorg/claude-code-config/main/VERSION
https://raw.githubusercontent.com/DEGAorg/claude-code-config/main/CORE_VERSION.md
```

Write to `~/.degacore/VERSION` and `~/.degacore/CORE_VERSION.md`. Safe to
overwrite — both files are installer-owned.

Also install `scripts/core-version.sh` to `~/.degacore/scripts/core-version.sh`
and `chmod +x` it. The helper prints
`installed=<x>  latest=<y>  status=<up-to-date|behind|ahead|unknown>`
by reading `~/.degacore/VERSION` and `gh api …/contents/VERSION`.

After writing, run the helper as a sanity check:

```bash
bash ~/.degacore/scripts/core-version.sh
```

It should print `status=up-to-date` (or `unknown` if `gh` is not on PATH —
that's fine, the install still succeeded).

---

### 6. Self-install

After completing the user's selections, also install this command itself to
`~/.degacore/config/commands/apply-core.md` by fetching:

```
https://raw.githubusercontent.com/DEGAorg/claude-code-config/main/commands/apply-core.md
```

Then copy it into each detected agent's commands directory:
```bash
cp ~/.degacore/config/commands/apply-core.md ~/.<agent>/commands/apply-core.md
```

This makes `/apply-core` available from any directory in future without
needing the repo cloned.

---

### 7. GCP setup (optional)

This step only applies if the user selected **Logging**.

Check whether `~/.degacore/gcp-sa.json` exists:

- **If it exists**: note that GCP Cloud Logging is configured. The log server
  will auto-enable GCP output when it starts.
- **If it does not exist**: tell the user:

  > GCP Cloud Logging is optional. To enable it, place a GCP service account
  > key at `~/.degacore/gcp-sa.json`. The log server detects this file at
  > startup and enables GCP output automatically — no other configuration
  > needed. Local JSONL logging to `~/.degacore/state/logs/` works without it.
  >
  > To create a service account key:
  > 1. Go to the GCP Console -> IAM & Admin -> Service Accounts.
  > 2. Create a service account with the **Logs Writer** role
  >    (`roles/logging.logWriter`).
  > 3. Create a JSON key for that service account and download it.
  > 4. Move the downloaded file to `~/.degacore/gcp-sa.json`.
  >
  > Do not commit this file — it contains credentials.

Do not copy, read, or transmit the key contents. Only check for its presence.

---

### 8. Post-install

Summarize what was installed or updated. Use a checklist format, one line per
component. Note any manual steps (e.g. agent template diff review).

For the **Logging** component, include one of these lines based on the
`~/.degacore/gcp-sa.json` check from Step 7:

- If `gcp-sa.json` **found**: `Logging — GCP active (gcp-sa.json detected)`
- If `gcp-sa.json` **absent**: `Logging — local-only (add ~/.degacore/gcp-sa.json to enable GCP)`

List which agents were configured:

```
Agents configured:
  Claude Code — $HOME/.claude/ (settings.json, commands, rules, CLAUDE.md → AGENTS.md)
  Gemini CLI  — ~/.gemini/ (settings.json, commands, rules, GEMINI.md → AGENTS.md)
  Codex CLI   — ~/.codex/ (config.toml + hooks.json, AGENTS.md native)
```

Example summary:

```
Installed to ~/.degacore/:
  Settings Template -> settings-template.json
  Agent Template -> config/agent-template.md
  Commands -> config/commands/ (fix-issue, review-pr, plan, cleanup, doc-garden, core-init)
  Rules -> config/rules/ (python, node-typescript, rust, bash, github-actions)
  Hooks -> scripts/hooks/ (enforce-loop-mode, enforce-exec-plan-naming, enforce-package-manager, log-gam)
  Skills -> config/skills/ (custom-linter-authoring, app-legibility, sound-notifications, canon-cli, polymarket)
  Logging -> scripts/log-server.py + scripts/hooks/ (local-only; add gcp-sa.json to enable GCP)
  Sounds -> sounds/ (MP3 + OGG) + scripts/hooks/play-sound.sh
  Terminal UI -> scripts/terminal-ui/ (built with pnpm)
  Orchestrator -> scripts/orch-*.sh + config/agents/ + scripts/hooks/
  Planner -> scripts/planner-loop.sh + config/agents/
  Canon Bootstrap -> scripts/canon-scaffold.sh + scripts/canon.sh
  Canon CLI -> canon-cli/ (built) + bin/canon-cli (linked)

Agents configured:
  Claude Code — $HOME/.claude/ (settings.json, commands, rules, CLAUDE.md → AGENTS.md)

Canon Bootstrap installs the CLI globally. Run /apply-canon from a Canon strategy
project to add the prediction-market layer (templates, strategies) on top of Core.
Ensure ~/.degacore/bin is on your PATH to use canon-cli from any directory.
```

Adapt to what the user actually selected — omit components that were skipped.
