# Plan: Agent-Agnostic Harness — Foundation and Script Migration

**Status:** Draft
**Created:** 2026-03-29

## Requirements

- All shared artifacts (scripts, hooks, sounds, commands, skills, rules, agents, templates) install to `~/.degacore/` instead of `~/.claude/`
- `~/.degacore/` uses `config/`, `scripts/`, `state/` subdirectory layout (config = brain, scripts = engine, state = volatile runtime data)
- A sourced `agent-shim.sh` provides detection + helper functions so no script hardcodes `claude` as a command or `~/.claude/` as a path
- Environment variables renamed: `CLAUDE_SOUND` → `DEGA_SOUND`, `CLAUDE_SOUND_VOLUME` → `DEGA_SOUND_VOLUME`, agent type set via `DEGA_PROVIDER`
- `CLAUDECODE` session var handling is dynamic via shim (`dega_agent_session_var`)
- `settings.json` hook paths updated from `~/.claude/hooks/` to `~/.degacore/scripts/hooks/` (or equivalent)
- `/apply-core` installs to `~/.degacore/` and generates agent-specific shim configs in `~/.claude/`, `~/.gemini/`, etc.
- `/core-init` unchanged at project level (already agent-agnostic via AGENTS.md + shims)
- `ralph-loop.sh` is legacy — skip it (not worth porting)
- MCP server portability is out of scope
- Zero behavior change for Claude Code users after migration — everything still works

## Approach

### Phase 1 — Foundation (no breaking changes)

Create `scripts/agent-shim.sh` with detection and helper functions. Source it in all orchestrator scripts. Rename env vars with fallback support during transition. Update all `~/.claude/` path references in scripts and hooks to use `$DEGA_CORE_HOME`.

### Phase 2 — Install refactor

Restructure `~/.degacore/` directory layout (`config/`, `scripts/`, `state/`). Update `/apply-core` to install to `$DEGA_CORE_HOME`. Generate agent-specific config (shims, symlinks) in each detected agent's config dir.

### Phase 3 & 4 — Future (separate plan)

Adapter layer for Gemini/Codex settings generation and capability matrix research. Cleanup of fallback env vars. These require external CLI research and are out of scope for this plan.

### Directory layout

```
~/.degacore/                          # DEGA_CORE_HOME
├── config/                           # "Brain" — knowledge and conventions
│   ├── commands/                     # apply-core, plan, fix-issue, etc.
│   ├── skills/                       # core skills
│   ├── rules/                        # python.md, node-typescript.md, etc.
│   ├── agents/                       # prompt templates
│   └── agent-template.md             # global AGENTS.md template
├── scripts/                          # "Engine" — automation logic
│   ├── agent-shim.sh                 # provider abstraction layer
│   ├── orch-engine.sh                # orchestrator
│   ├── orch-run.sh                   # orchestrator launcher
│   ├── orch-review.sh                # reviewer
│   ├── orch-verify.sh                # verifier
│   ├── planner-loop.sh              # autonomous planner
│   ├── canon.sh                      # canon launcher
│   ├── canon-scaffold.sh             # canon scaffolding
│   ├── canon-runner.sh               # canon runner
│   ├── hooks/                        # enforce-*, play-sound, structured-log, etc.
│   ├── log-server.py                 # structured logging server
│   └── statusline.sh                 # status line
├── state/                            # "Memory" — volatile runtime data
│   ├── logs/                         # session logs, ralph logs
│   └── planner/                      # planner loop state
├── sounds/                           # notification MP3 files
├── dega-core.yaml                    # default project config template
└── settings-template.json            # base settings (hooks, permissions)
```

Agent-specific directories remain where each agent expects them:

```
~/.claude/
├── CLAUDE.md            # thin shim → ~/.degacore/config/agent-template.md
├── settings.json        # generated from settings-template.json
├── commands/ → ~/.degacore/config/commands/
└── rules/ → ~/.degacore/config/rules/
```

## Files to touch

| File | Change |
|------|--------|
| `scripts/agent-shim.sh` (new) | Create sourced helper: `dega_agent_type`, `dega_agent_command`, `dega_agent_config_dir`, `dega_agent_headless_flags`, `dega_agent_session_var`, `dega_agent_prompt_flag` + `DEGA_CORE_HOME` default |
| `scripts/orch-engine.sh` | Source agent-shim.sh; replace `claude` commands with shim helpers; replace `CLAUDECODE` with `$(dega_agent_session_var)`; replace `CLAUDE_SOUND` with `DEGA_SOUND`; replace `~/.claude/` paths with `$DEGA_CORE_HOME/` |
| `scripts/orch-run.sh` | Source agent-shim.sh; replace `~/.claude/` paths with `$DEGA_CORE_HOME/` |
| `scripts/orch-review.sh` | Source agent-shim.sh; replace `claude -p` with shim helpers; replace `CLAUDECODE` with shim; replace `~/.claude/` paths |
| `scripts/orch-verify.sh` | Source agent-shim.sh; replace `claude -p` with shim helpers; replace `CLAUDECODE` with shim; replace `~/.claude/` paths |
| `scripts/planner-loop.sh` | Source agent-shim.sh; replace `claude -p` with shim helpers; replace `CLAUDE_SOUND` with `DEGA_SOUND`; replace `~/.claude/` paths |
| `scripts/canon.sh` | Source agent-shim.sh; replace `claude` command with shim; replace `~/.claude/` paths |
| `scripts/canon-scaffold.sh` | Replace `~/.claude/` paths with `$DEGA_CORE_HOME/` |
| `scripts/canon-runner.sh` | Replace `~/.claude/` paths with `$DEGA_CORE_HOME/` |
| `scripts/log-client.sh` | Replace `~/.claude/logs/` with `$DEGA_CORE_HOME/state/logs/` |
| `scripts/log-server.py` | Replace `~/.claude/` paths with `DEGA_CORE_HOME` env var |
| `hooks/play-sound.sh` | Replace `CLAUDE_SOUND` with `DEGA_SOUND` (fallback to `CLAUDE_SOUND`); replace `~/.claude/dega/sounds` with `$DEGA_CORE_HOME/sounds/` |
| `hooks/session-start-logging.sh` | Replace `~/.claude/` paths with `$DEGA_CORE_HOME/` |
| `hooks/structured-log.sh` | Replace `~/.claude/` paths with `$DEGA_CORE_HOME/` |
| `settings.json` | Update hook paths from `~/.claude/hooks/` to `$HOME/.degacore/scripts/hooks/`; rename `CLAUDE_SOUND*` to `DEGA_SOUND*`; update statusline path |
| `commands/apply-core.md` | Rewrite install flow to target `$DEGA_CORE_HOME` with subdirectory layout; detect agents and generate per-agent config |
| `README.md` | Update directory structure docs and install instructions |
| `INSTALL.md` | Update install paths |

## Risks and open questions

- **Backward compatibility:** Users with existing `~/.claude/` installs need the transition to work. `/apply-core` should handle this — install to `~/.degacore/` and update `~/.claude/` to point there. (P2 — test after implementation)
- **settings.json env var expansion:** Claude Code settings.json doesn't expand `$HOME` or `$DEGA_CORE_HOME` in hook paths — must use literal `~` or absolute paths. Verify hook path format after migration. (P1 — check during item 3)
- **Symlink support in `~/.claude/commands/`:** Claude Code may not follow symlinks for slash commands. If not, `/apply-core` copies instead of symlinking. (P2 — test)
- **`.claude/commands/` relative paths in canon-scaffold.sh:** These are project-local `.claude/commands/` (for Claude Code project commands), NOT global. These should remain `.claude/commands/` since they're Claude-specific project config. (P3 — no change needed)

## Progress log

- [x] Create `scripts/agent-shim.sh` — implement `dega_agent_type`, `dega_agent_command`, `dega_agent_config_dir`, `dega_agent_headless_flags`, `dega_agent_session_var`, `dega_agent_prompt_flag`; set `DEGA_CORE_HOME` default to `~/.degacore`; detection heuristic: `DEGA_PROVIDER` env → parent process → session env vars → fallback `claude`
- [ ] Update `scripts/orch-engine.sh` — source `agent-shim.sh`; replace all `claude` command invocations with `$(dega_agent_command)` + `$(dega_agent_headless_flags)`; replace `env -u CLAUDECODE` with `env -u $(dega_agent_session_var)`; replace `CLAUDE_SOUND` with `DEGA_SOUND`; replace all `~/.claude/` paths with `$DEGA_CORE_HOME/scripts/` or `$DEGA_CORE_HOME/state/` as appropriate (deps: 1)
- [ ] Update `scripts/orch-run.sh` — source `agent-shim.sh`; replace `~/.claude/scripts/` paths with `$DEGA_CORE_HOME/scripts/` (deps: 1)
- [ ] Update `scripts/orch-review.sh` — source `agent-shim.sh`; replace `claude -p --dangerously-skip-permissions` with shim helpers; replace `env -u CLAUDECODE` with shim; replace `~/.claude/` paths (deps: 1)
- [ ] Update `scripts/orch-verify.sh` — source `agent-shim.sh`; replace `claude -p --dangerously-skip-permissions` with shim helpers; replace `env -u CLAUDECODE` with shim; replace `~/.claude/` paths (deps: 1)
- [ ] Update `scripts/planner-loop.sh` — source `agent-shim.sh`; replace `claude -p` invocations with shim helpers; replace `CLAUDE_SOUND` with `DEGA_SOUND`; replace `~/.claude/planner` with `$DEGA_CORE_HOME/state/planner/` (deps: 1)
- [ ] Update `scripts/canon.sh`, `scripts/canon-scaffold.sh`, `scripts/canon-runner.sh` — source `agent-shim.sh` in canon.sh; replace global `~/.claude/scripts/` paths with `$DEGA_CORE_HOME/scripts/`; keep project-local `.claude/commands/` unchanged (those are Claude-specific project config) (deps: 1)
- [ ] Update hooks — `hooks/play-sound.sh`: rename `CLAUDE_SOUND` → `DEGA_SOUND` with fallback `${DEGA_SOUND:-${CLAUDE_SOUND:-super-mario-bros}}`; update sounds dir to `$DEGA_CORE_HOME/sounds/`; `hooks/session-start-logging.sh` and `hooks/structured-log.sh`: replace `~/.claude/` paths with `$DEGA_CORE_HOME/state/` (deps: 1)
- [ ] Update `scripts/log-client.sh` and `scripts/log-server.py` — replace `~/.claude/logs/` with `$DEGA_CORE_HOME/state/logs/`; update Python paths to read `DEGA_CORE_HOME` env var (deps: 1)
- [ ] Update `settings.json` — replace all `~/.claude/hooks/` paths with `~/.degacore/scripts/hooks/`; rename `CLAUDE_SOUND` → `DEGA_SOUND` and `CLAUDE_SOUND_VOLUME` → `DEGA_SOUND_VOLUME`; update statusline path to `~/.degacore/scripts/statusline.sh` (deps: 2, 3, 4, 5, 6, 7, 8, 9)
- [ ] Update `commands/apply-core.md` — rewrite install flow: target `$DEGA_CORE_HOME` (`~/.degacore/`); create subdirectory layout (`config/`, `scripts/`, `state/`, `sounds/`); install scripts to `scripts/`, hooks to `scripts/hooks/`, commands to `config/commands/`, etc.; detect installed agents and generate per-agent config (shims, settings, symlinks/copies for commands and rules) (deps: 10)
- [ ] Update `README.md` and `INSTALL.md` — update directory structure documentation, install instructions, and path references to reflect `~/.degacore/` layout (deps: 11)
- [ ] Run `shellcheck` on all modified `.sh` files; verify no stale `~/.claude/` references remain in scripts or hooks (grep audit) (deps: 2, 3, 4, 5, 6, 7, 8, 9)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| `~/.degacore/` with `config/scripts/state/` subdirs | Flat layout from requirements doc; XDG split across `~/.local/share` etc. | Gemini's Brain/Engine/Memory separation adds clarity without XDG complexity; single root is simpler to manage |
| Sourced `agent-shim.sh` library (not standalone `ai-exec.sh` wrapper) | Standalone executable wrapper; inline detection in each script | Scripts need multiple helper functions (command, flags, session var, config dir), not just "run agent". Sourced library is more flexible. |
| `DEGA_PROVIDER` env var (not `AGENT_TYPE`) | `AGENT_TYPE` from requirements doc | Consistent `DEGA_*` namespace; avoids collision with generic env var names |
| Fallback env vars during transition (`DEGA_SOUND` falls back to `CLAUDE_SOUND`) | Hard cut (break existing installs); no fallback | Users with existing `~/.claude/` setups need time to run updated `/apply-core`. Fallbacks removed in Phase 4 (future plan). |
| Skip `ralph-loop.sh` migration | Port ralph-loop.sh to agent-agnostic | Legacy code, superseded by orchestrator. Not worth the churn. |
| Keep project-local `.claude/commands/` in canon-scaffold.sh | Change to `.agents/commands/` | These are Claude Code project commands — Claude requires them in `.claude/commands/`. Agent-specific by design. |
| Phase 3 (adapters) and Phase 4 (cleanup) deferred to separate plan | Include everything in one plan | Phase 3 requires Gemini/Codex CLI research that may block. Ship foundation first, iterate. |

## Completion criteria

- [ ] `scripts/agent-shim.sh` exists and passes `shellcheck`
- [ ] No hardcoded `claude` command invocations remain in orchestrator scripts (orch-engine, orch-run, orch-review, orch-verify, planner-loop, canon.sh)
- [ ] No `~/.claude/` path references remain in scripts or hooks (except project-local `.claude/commands/` in canon-scaffold.sh which is intentional)
- [ ] `DEGA_SOUND` and `DEGA_SOUND_VOLUME` are the primary env vars (with `CLAUDE_SOUND*` fallbacks)
- [ ] `settings.json` hook paths point to `~/.degacore/scripts/hooks/`
- [ ] `/apply-core` installs to `~/.degacore/` with `config/`, `scripts/`, `state/`, `sounds/` layout
- [ ] `shellcheck` passes on all modified `.sh` files
- [ ] `grep -r "~/.claude/" scripts/ hooks/` returns zero hits (excluding intentional project-local refs)
