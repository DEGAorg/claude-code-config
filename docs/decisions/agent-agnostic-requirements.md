# Agent-Agnostic Architecture Requirements

Make the entire stack runnable with Claude Code, Gemini CLI, and OpenAI Codex
without forking or maintaining per-agent branches. The core principle: one
codebase, agent-specific only at the boundary.

---

## 1. Directory layout — XDG-based `~/.degacore/`

Today everything installs to `~/.claude/`. Move shared artifacts to an
agent-neutral location following XDG conventions.

```
~/.degacore/                          # DEGA_CORE_HOME (XDG_DATA_HOME/degacore)
├── scripts/                          # orch-engine, orch-run, orch-state, etc.
├── hooks/                            # enforce-package-manager, play-sound, structured-log
├── sounds/                           # MP3 files
├── commands/                         # apply-core, plan, fix-issue, cleanup, etc.
├── skills/                           # core skills + patterns/
├── rules/                            # python.md, node-typescript.md, rust.md, bash.md
├── agents/                           # prompt templates (orch-worker, orch-verifier, etc.)
├── agent-template.md                 # global AGENTS.md template (agent-neutral)
├── dega-core.yaml                    # default per-project config template
└── settings-template.json            # base settings (hooks, permissions — agent-neutral)
```

Agent-specific directories remain where each agent expects them:

```
~/.claude/                            # Claude Code
├── CLAUDE.md                         # thin shim → ~/.degacore/agent-template.md
├── settings.json                     # generated from settings-template.json + claude adapter
├── commands/ → ~/.degacore/commands/ # symlinks or copies
└── rules/ → ~/.degacore/rules/

~/.gemini/                            # Gemini CLI
├── GEMINI.md                         # thin shim → ~/.degacore/agent-template.md
└── (agent-specific config)

~/.codex/                             # OpenAI Codex
├── instructions.md                   # thin shim → ~/.degacore/agent-template.md
└── (agent-specific config)
```

### Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `DEGA_CORE_HOME` | `~/.degacore` | Root of shared artifacts |
| `AGENT_TYPE` | auto-detected | `claude`, `gemini`, `codex` |
| `AGENT_CONFIG_DIR` | derived from `AGENT_TYPE` | `~/.claude`, `~/.gemini`, `~/.codex` |
| `AGENT_COMMAND` | derived from `AGENT_TYPE` | `claude`, `gemini`, `codex` |

---

## 2. Agent abstraction layer — `scripts/agent-shim.sh`

A single sourced helper that all scripts use instead of hardcoded values.

### Required functions

```bash
# Detect agent from environment or explicit AGENT_TYPE
dega_agent_type()         # → claude | gemini | codex

# Return the CLI command to invoke the agent
dega_agent_command()      # → claude | gemini | codex

# Return the agent's config directory
dega_agent_config_dir()   # → ~/.claude | ~/.gemini | ~/.codex

# Return flags for non-interactive headless invocation
dega_agent_headless_flags()  # → "--dangerously-skip-permissions" (claude), etc.

# Return the session env var to unset for clean subagent spawn
dega_agent_session_var()  # → CLAUDECODE | GEMINI_SESSION | ...

# Return prompt flag (-p for claude, equivalent for others)
dega_agent_prompt_flag()  # → -p | --prompt | ...
```

### Detection heuristic

1. Explicit `AGENT_TYPE` env var (highest priority)
2. Parent process name (`claude`, `gemini`, `codex`)
3. Known session env vars (`CLAUDECODE`, `GEMINI_SESSION`, etc.)
4. Fallback: `claude` (current default)

---

## 3. Hardcoded references to refactor

### 3a. Script files — agent command invocations

Every `claude -p` or `claude --dangerously-skip-permissions` call must go
through `dega_agent_command` + `dega_agent_headless_flags`.

| File | Current hardcoding |
|------|--------------------|
| `scripts/orch-engine.sh` | `claude -p --dangerously-skip-permissions` (worker spawn) |
| `scripts/orch-review.sh` | `env -u CLAUDECODE claude -p` (reviewer spawn) |
| `scripts/orch-verify.sh` | `env -u CLAUDECODE claude -p` (verifier spawn) |
| `scripts/planner-loop.sh` | `claude -p --output-format json` (assessor + writer) |
| `scripts/ralph-loop.sh` | `env -u CLAUDECODE claude -p` (legacy worker/reviewer) |
| `scripts/canon.sh` | `claude --dangerously-skip-permissions` (canon launcher) |

### 3b. Environment variables

| Current | Replacement | Files affected |
|---------|-------------|----------------|
| `CLAUDE_SOUND` | `DEGA_SOUND` | settings.json, hooks/play-sound.sh, orch-engine.sh, ralph-loop.sh, planner-loop.sh |
| `CLAUDE_SOUND_VOLUME` | `DEGA_SOUND_VOLUME` | same as above |
| `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY` | keep (agent-specific, set conditionally) | settings.json |
| `env -u CLAUDECODE` | `env -u $(dega_agent_session_var)` | orch-review.sh, orch-verify.sh, ralph-loop.sh |

### 3c. Path references — `~/.claude/` in scripts and hooks

Replace all `~/.claude/` references in executable scripts with
`$DEGA_CORE_HOME` (for shared artifacts) or `$(dega_agent_config_dir)`
(for agent-specific files).

| Pattern | Count | Replacement |
|---------|-------|-------------|
| `~/.claude/hooks/` | ~10 call sites in settings.json | `$DEGA_CORE_HOME/hooks/` |
| `~/.claude/scripts/` | ~15 call sites across scripts, docs | `$DEGA_CORE_HOME/scripts/` |
| `~/.claude/sounds/` or `~/.claude/dega/sounds/` | ~3 in play-sound.sh | `$DEGA_CORE_HOME/sounds/` |
| `~/.claude/statusline.sh` | settings.json | `$DEGA_CORE_HOME/scripts/statusline.sh` |
| `~/.claude/commands/` | apply-core.md, README | `$DEGA_CORE_HOME/commands/` (shared) + agent symlink |
| `~/.claude/rules/` | agent-template.md, README | `$DEGA_CORE_HOME/rules/` (shared) + agent symlink |

### 3d. settings.json — Claude-specific schema and structure

The `settings.json` template is Claude Code-specific (JSON schema, hook
format, permission model). Each agent has its own config format.

Approach:
- Keep `settings-template.json` as the canonical hook/permission definition
- Generate agent-specific config via adapter scripts:
  - `scripts/adapters/claude-settings.sh` → `~/.claude/settings.json`
  - `scripts/adapters/gemini-settings.sh` → `~/.gemini/settings.yaml` (or equivalent)
  - `scripts/adapters/codex-settings.sh` → `~/.codex/config.json` (or equivalent)

---

## 4. Install flow — updated `/apply-core` and `/core-init`

### `/apply-core` changes

1. Install shared artifacts to `$DEGA_CORE_HOME` instead of `~/.claude/`
2. Detect which agents are installed (check for `claude`, `gemini`, `codex` binaries)
3. For each detected agent, generate agent-specific config:
   - Shim file (CLAUDE.md, GEMINI.md, instructions.md) pointing to `$DEGA_CORE_HOME/agent-template.md`
   - Settings file via adapter
   - Symlinks for commands/ and rules/ if the agent supports them
4. Print summary of what was installed and for which agents

### `/core-init` changes

1. Generate AGENTS.md in project root (unchanged)
2. Generate shim files for all detected agents (CLAUDE.md, GEMINI.md, .cursorrules, etc.)
3. Copy `dega-core.yaml` from `$DEGA_CORE_HOME/dega-core.yaml`

---

## 5. Project-level config — already done

The provider-agnostic project config (plan 20260327) is complete:
- `AGENTS.md` is the single source of truth
- `CLAUDE.md`, `GEMINI.md`, `.cursorrules` are 3-line shims
- No further changes needed at project level

---

## 6. Agent capability matrix

Not all agents support the same features. The shim layer must handle
graceful degradation.

| Feature | Claude Code | Gemini CLI | Codex |
|---------|-------------|------------|-------|
| `-p` prompt flag | yes | TBD | TBD |
| `--dangerously-skip-permissions` | yes | TBD | TBD |
| `--output-format json` | yes | TBD | TBD |
| MCP servers | yes | TBD | TBD |
| Hooks (PreToolUse, PostToolUse) | yes | TBD | TBD |
| Custom commands (slash commands) | yes | TBD | TBD |
| Rules (glob-matched files) | yes | TBD | TBD |
| Worktree isolation | yes (manual) | TBD | TBD |
| tmux session spawning | yes | TBD | TBD |

**Action:** Research Gemini CLI and Codex CLI interfaces to fill TBD cells
before implementing adapters.

---

## 7. Migration path

### Phase 1 — Foundation (no breaking changes)

1. Create `scripts/agent-shim.sh` with detection + helper functions
2. Create `$DEGA_CORE_HOME` directory structure
3. Update scripts to source `agent-shim.sh` and use helpers
4. Rename `CLAUDE_SOUND` → `DEGA_SOUND` (keep `CLAUDE_SOUND` as fallback temporarily)
5. All scripts continue to work with Claude — zero behavior change

### Phase 2 — Install refactor

6. Update `/apply-core` to install to `$DEGA_CORE_HOME`
7. Generate agent-specific shims in `~/.claude/`, `~/.gemini/`, etc.
8. Symlink or copy commands/rules to agent config dirs
9. Update `/core-init` for multi-agent project setup

### Phase 3 — Adapter layer

10. Build settings adapters for each agent
11. Fill capability matrix with real Gemini/Codex CLI research
12. Implement graceful degradation for unsupported features
13. Test orchestrator with at least one non-Claude agent

### Phase 4 — Cleanup

14. Remove `CLAUDE_SOUND` fallback, `~/.claude/` hardcoded paths in docs
15. Update README, INSTALL.md, agent-template.md for multi-agent
16. Archive ralph-loop.sh (already legacy, not worth porting)

---

## 8. Out of scope

- Rewriting the orchestrator engine in a non-shell language
- Supporting agents that have no CLI / headless mode
- Per-agent prompt tuning (AGENTS.md is agent-neutral by design)
- MCP server portability (agent-specific by nature, handled separately)
