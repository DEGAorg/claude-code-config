# Agent-Agnostic Architecture

DEGA Core runs identically under Claude Code, Gemini CLI, and OpenAI Codex.
One codebase, agent-specific only at the boundary.

## How it works

```
                  ┌─────────────────────────┐
                  │   settings-template.json │  Canonical hooks, permissions,
                  │   (agent-neutral)        │  env vars, MCP servers
                  └────────┬────────────────┘
                           │
              ┌────────────┼────────────────┐
              ▼            ▼                ▼
   claude-settings.sh  gemini-settings.sh  codex-settings.sh
              │            │                │
              ▼            ▼                ▼
   ~/.claude/          ~/.gemini/        ~/.codex/
   settings.json       settings.json     config.toml + hooks.json
```

All orchestrator scripts source `agent-shim.sh` for runtime detection:

```
   orch-engine.sh ──┐
   orch-review.sh ──┤── source agent-shim.sh ──► dega_agent_build_headless_cmd()
   orch-verify.sh ──┤                             dega_agent_command()
   planner-loop.sh ─┘                             dega_agent_headless_flags()
```

No script contains a hardcoded `claude`, `gemini`, or `codex` invocation.

## Agent shim (`scripts/agent-shim.sh`)

The shim is sourced (not executed) by every script that spawns agents.
It provides a public API and caches the detected provider per shell session.

### Detection heuristic (first match wins)

1. `DEGA_PROVIDER` env var (explicit override)
2. Parent process name via `ps -o comm=` (`claude*`, `gemini*`, `codex*`)
3. Session env vars (`CLAUDECODE`, `GEMINI_CLI`)
4. Fallback: `claude`

### Public API

| Function | Claude | Gemini | Codex |
|----------|--------|--------|-------|
| `dega_agent_type()` | `claude` | `gemini` | `codex` |
| `dega_agent_command()` | `claude` | `gemini` | `codex` |
| `dega_agent_config_dir()` | `~/.claude` | `~/.gemini` | `~/.codex` |
| `dega_agent_headless_flags()` | `--dangerously-skip-permissions` | `--yolo` | `--yolo` |
| `dega_agent_session_var()` | `CLAUDECODE` | `GEMINI_CLI` | *(empty)* |
| `dega_agent_prompt_flag()` | `-p` | `-p` | `exec` |
| `dega_agent_json_flag()` | `--output-format json` | `--output-format json` | `--json` |
| `dega_agent_build_headless_cmd(prompt)` | `claude --dangerously-skip-permissions -p "prompt"` | `gemini --yolo -p "prompt"` | `codex --yolo exec "prompt"` |

Codex uses `exec` as a subcommand (not a flag), so the prompt is a
positional argument. The shim handles this transparently.

## Settings adapters (`scripts/adapters/`)

Each adapter reads `settings-template.json` and generates provider-specific config.

| Adapter | Output | Key transformations |
|---------|--------|---------------------|
| `claude-settings.sh` | `~/.claude/settings.json` | Strips metadata, adds Claude-specific fields. Event names unchanged. |
| `gemini-settings.sh` | `~/.gemini/settings.json` | Translates event names: `PreToolUse` → `BeforeTool`, `PostToolUse` → `AfterTool`, `Stop` → `SessionEnd`, `UserPromptSubmit` → `SessionStart`. |
| `codex-settings.sh` | `~/.codex/config.toml` + `~/.codex/hooks.json` | Converts MCP servers from JSON to TOML. Enables `codex_hooks` feature flag. Event names unchanged. |

The `settings-template.json` includes an `_event_name_mapping` metadata block
that documents the canonical → agent-specific translations. Adapters read this
to stay in sync.

## Install flow (`/apply-core`)

1. Shared artifacts install to `~/.degacore/` (config, scripts, hooks, sounds)
2. Detect installed agents (check for `claude`, `gemini`, `codex` binaries)
3. For each detected agent:
   - Run the adapter to generate settings
   - Copy commands from `~/.degacore/config/commands/` into agent's `commands/` dir
   - Copy rules from `~/.degacore/config/rules/` into agent's `rules/` dir
   - Write instruction shim (`CLAUDE.md`, `GEMINI.md`) pointing to `AGENTS.md`
4. Existing user commands/rules with the same filename are skipped (user takes precedence)

## Directory layout

```
~/.degacore/                          # Shared (DEGA_CORE_HOME)
├── settings-template.json            # Canonical settings
├── config/
│   ├── agent-template.md             # Global dev standards
│   ├── commands/                     # apply-core, plan, fix-issue, etc.
│   ├── rules/                        # python, node-typescript, rust, bash
│   ├── skills/                       # app-legibility, custom-linter-authoring
│   └── agents/                       # orch-worker, orch-verifier, planner-*
├── scripts/
│   ├── agent-shim.sh                 # Provider abstraction layer
│   ├── adapters/                     # claude-settings.sh, gemini-settings.sh, codex-settings.sh
│   ├── hooks/                        # enforce-package-manager, play-sound, structured-log, etc.
│   ├── orch-*.sh                     # Orchestrator engine
│   ├── planner-loop.sh              # Autonomous planner
│   ├── statusline.sh                # Terminal status bar
│   └── terminal-ui/                  # Ink dashboard
├── sounds/                           # Completion sounds (MP3 + OGG)
└── state/                            # Logs, planner state

~/.claude/                            # Agent-specific (generated)
├── settings.json                     # Generated by claude-settings.sh
├── CLAUDE.md                         # Shim → AGENTS.md
├── commands/                         # Copies from ~/.degacore/config/commands/
└── rules/                            # Copies from ~/.degacore/config/rules/

~/.gemini/                            # Same structure, Gemini adapter
~/.codex/                             # config.toml + hooks.json, Codex adapter
```

## Switching providers

Automatic — the shim detects the parent process. To override:

```bash
export DEGA_PROVIDER=gemini
```

Or simply run your scripts under the target agent's CLI. The orchestrator,
planner, and all hooks adapt automatically.
