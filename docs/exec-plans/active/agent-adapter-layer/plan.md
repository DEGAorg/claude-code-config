# Plan: Agent Adapter Layer — Gemini and Codex Support

**Status:** Draft
**Created:** 2026-03-29

## Requirements

- `agent-shim.sh` returns correct CLI flags for all three agents (Claude, Gemini, Codex)
- Orchestrator can spawn workers using Gemini CLI or Codex CLI (set via `DEGA_PROVIDER`)
- Settings adapters generate agent-specific config from a shared template: `settings.json` for Claude/Gemini, `config.toml` + `hooks.json` for Codex
- `/apply-core` detects installed agents and generates config for each
- Hook event names mapped correctly per agent (Claude `PreToolUse` = Gemini `BeforeTool` = Codex `PreToolUse`)
- Graceful degradation when an agent lacks a feature (e.g., Codex has no session env var — skip `env -u`)
- Smoke test: orchestrator runs a trivial plan with `DEGA_PROVIDER=gemini` and `DEGA_PROVIDER=codex`

## Approach

### Plan A: Complete agent-shim.sh with real flag mappings

Fill in the shim functions with researched CLI interfaces. The shim already has the structure — it just needs real values instead of Claude-only defaults.

### Plan B: Settings adapters

Each agent has a different config format:
- **Claude**: `settings.json` (JSON, hooks inline)
- **Gemini**: `settings.json` (JSON, similar structure, different hook event names)
- **Codex**: `config.toml` (TOML) + `hooks.json` (separate file)

Create adapter scripts that read `settings-template.json` and generate agent-specific config.

### Plan C: Hook event name mapping

Our hooks use Claude event names. Gemini uses different names (`BeforeTool` vs `PreToolUse`). Codex uses the same names as Claude. The adapter must translate event names when generating Gemini config.

| Our hook | Claude | Gemini | Codex |
|----------|--------|--------|-------|
| PreToolUse | PreToolUse | BeforeTool | PreToolUse |
| PostToolUse | PostToolUse | AfterTool | PostToolUse |
| Stop | Stop | SessionEnd | Stop |
| UserPromptSubmit | UserPromptSubmit | SessionStart | UserPromptSubmit |

### Capability matrix (researched)

| Feature | Claude | Gemini | Codex |
|---------|--------|--------|-------|
| Prompt flag | `-p "prompt"` | `-p "prompt"` | `exec "prompt"` |
| Headless flags | `--dangerously-skip-permissions` | `--yolo` | `--yolo` |
| JSON output | `--output-format json` | `--output-format json` | `--json` |
| Session env var | `CLAUDECODE` | `GEMINI_CLI` | *(none)* |
| Config dir | `~/.claude/` | `~/.gemini/` | `~/.codex/` |
| Config format | `settings.json` | `settings.json` | `config.toml` |
| Instruction file | `CLAUDE.md` | `GEMINI.md` | `AGENTS.md` |
| Hooks | JSON, inline in settings.json | JSON, inline in settings.json | `hooks.json` separate file |
| Slash commands | `.md` files | `.toml` files | Custom format |
| MCP | `mcpServers` in settings.json | `mcpServers` in settings.json | `[mcp_servers]` in config.toml |

## Files to touch

| File | Change |
|------|--------|
| `scripts/agent-shim.sh` | Fill `dega_agent_command`, `dega_agent_headless_flags`, `dega_agent_session_var`, `dega_agent_prompt_flag` with real Gemini/Codex values; add `dega_agent_json_flag` helper; handle Codex `exec` subcommand pattern |
| `scripts/adapters/claude-settings.sh` (new) | Generate `~/.claude/settings.json` from template |
| `scripts/adapters/gemini-settings.sh` (new) | Generate `~/.gemini/settings.json` from template, translating hook event names |
| `scripts/adapters/codex-settings.sh` (new) | Generate `~/.codex/config.toml` and `~/.codex/hooks.json` from template |
| `settings-template.json` (new) | Agent-neutral hook/permission definitions using canonical event names |
| `commands/apply-core.md` | Update install flow to call adapters for each detected agent |
| `scripts/orch-engine.sh` | Handle Codex `exec` subcommand pattern in worker spawn; handle missing session var gracefully |
| `scripts/orch-review.sh` | Same Codex/session-var fixes |
| `scripts/orch-verify.sh` | Same Codex/session-var fixes |
| `scripts/planner-loop.sh` | Same Codex/session-var fixes; update JSON output flag usage |

## Risks and open questions

- **Codex `exec` subcommand**: Codex uses `codex exec "prompt"` not `codex -p "prompt"`. The shim needs to handle this differently — `dega_agent_prompt_flag` returns `-p` for Claude/Gemini but for Codex the prompt is a positional arg to `exec`. (P1 — handle in shim design)
- **Codex no session env var**: Codex doesn't set a session var like `CLAUDECODE`. The `env -u $(dega_agent_session_var)` pattern would fail. Shim must return empty and callers must handle it. (P1 — fix in shim + callers)
- **Gemini hook JSON format**: Gemini hooks communicate via stdin/stdout JSON. Need to verify our hook scripts are compatible or if we need wrappers. (P2 — test during implementation)
- **Slash command format differences**: Claude uses `.md`, Gemini uses `.toml`, Codex has its own format. Commands can't be shared directly — adapters must convert or skip. (P3 — defer command conversion to future plan)
- **Gemini TOML commands don't work in headless mode**: Known Gemini limitation. Slash commands won't work for orchestrator workers. (P3 — not blocking, workers use prompts not commands)

## Progress log

- [x] Update `scripts/agent-shim.sh` — fill all helper functions with real Gemini/Codex values: `dega_agent_command` returns `gemini`/`codex`; `dega_agent_headless_flags` returns `--yolo` for both; `dega_agent_session_var` returns `GEMINI_CLI` for Gemini, empty for Codex; `dega_agent_prompt_flag` returns `-p` for Claude/Gemini, `exec` for Codex; add `dega_agent_json_flag` returning `--output-format json` for Claude/Gemini, `--json` for Codex; add `dega_agent_build_headless_cmd` that assembles the full command string handling Codex's `exec` subcommand pattern
- [x] Update orchestrator scripts to handle Codex pattern and missing session var — in `orch-engine.sh`, `orch-review.sh`, `orch-verify.sh`: use `dega_agent_build_headless_cmd` instead of manual command assembly; skip `env -u` when session var is empty (deps: 1)
- [x] Update `scripts/planner-loop.sh` — use `dega_agent_build_headless_cmd` for assessor and writer spawns; use `dega_agent_json_flag` for JSON output (deps: 1)
- [x] Create `settings-template.json` — agent-neutral hook/permission definitions using canonical event names (`PreToolUse`, `PostToolUse`, `Stop`); document the mapping to each agent's names in comments (deps: 1)
- [x] Create `scripts/adapters/claude-settings.sh` — read `settings-template.json`, output `settings.json` with Claude event names and `~/.degacore/` hook paths (deps: 4)
- [x] Create `scripts/adapters/gemini-settings.sh` — read `settings-template.json`, translate event names (`PreToolUse`→`BeforeTool`, `PostToolUse`→`AfterTool`, `Stop`→`SessionEnd`), output `settings.json` for `~/.gemini/` (deps: 4)
- [ ] Create `scripts/adapters/codex-settings.sh` — read `settings-template.json`, generate `config.toml` (MCP servers, model config) and `hooks.json` (hooks in Codex format) for `~/.codex/` (deps: 4)
- [ ] Update `commands/apply-core.md` — add step to detect installed agents (`command -v claude gemini codex`), run corresponding adapter for each, generate instruction file shims (`CLAUDE.md`, `GEMINI.md` pointing to `AGENTS.md`; Codex uses `AGENTS.md` natively) (deps: 5, 6, 7)
- [ ] Run `shellcheck` on all modified/new `.sh` files; verify shim returns correct values for all three agents (deps: 2, 3, 5, 6, 7)
- [ ] Smoke test — run orchestrator with `DEGA_PROVIDER=gemini` on a trivial 1-item plan; verify worker spawns with correct `gemini -p --yolo` command (deps: 2, 8)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Add `dega_agent_build_headless_cmd` helper | Let each script handle Codex `exec` pattern | Codex's `exec` subcommand breaks the `command + flags + prompt` pattern. Centralizing in one helper avoids duplicating logic across 5+ scripts. |
| Skip slash command conversion | Convert `.md` commands to `.toml` (Gemini) and Codex format | Format differences are significant and commands aren't needed for orchestrator workers (they use prompts). Defer to future plan. |
| `settings-template.json` uses Claude event names as canonical | Use agent-neutral names | Claude and Codex share event names. Only Gemini differs. Easier to map from Claude names than invent new ones. |
| Empty string for Codex session var | Invent a custom `DEGA_SESSION` var | Codex doesn't set one. Adding a fake var would mislead. Callers should handle empty gracefully. |

## Completion criteria

- [ ] `dega_agent_command` returns correct binary for all three agents
- [ ] `dega_agent_headless_flags` returns `--dangerously-skip-permissions` for Claude, `--yolo` for Gemini/Codex
- [ ] `dega_agent_session_var` returns `CLAUDECODE` for Claude, `GEMINI_CLI` for Gemini, empty for Codex
- [ ] `dega_agent_build_headless_cmd` produces correct command string for all three agents
- [ ] Orchestrator scripts handle empty session var without error
- [ ] Three adapter scripts exist and generate valid config for their respective agents
- [ ] `/apply-core` detects installed agents and runs adapters
- [ ] `shellcheck` passes on all modified/new `.sh` files
- [ ] Smoke test passes with `DEGA_PROVIDER=gemini` (worker spawns with correct flags)
