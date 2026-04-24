# Provider-Agnostic AI Harness: Recommendations for Gemini & Claude

This document outlines the architectural strategy for transitioning the DEGA Core AI development harness from a Claude-only toolset to a provider-agnostic system supporting both Claude and Gemini (and future agents).

## 1. Single Root Architecture (`~/.degacore/`)

While strict XDG compliance suggests splitting files across multiple system directories, a **Single Root** approach is preferred for simplicity and discoverability.

- **Root Location**: `~/.degacore/` (replacing the hardcoded `~/.claude/`).
- **Benefits**: Centralizes all "intelligence" and "automation" in one place, avoiding "identity conflicts" when switching between different AI providers.

### Internal Directory Layout
Within `~/.degacore/`, concerns should be separated:

| Sub-directory | Content | Purpose |
| :--- | :--- | :--- |
| `config/` | `rules/`, `skills/`, `commands/`, `AGENTS.md` | The "Brain": Knowledge and conventions. |
| `scripts/` | `orch-*.sh`, `planner-*.sh`, `ai-exec.sh` | The "Engine": Automation logic and shims. |
| `state/` | `logs/`, `worktrees/`, `state.json` | The "Memory": Volatile data and execution state. |

---

## 2. The Provider Abstraction Layer (`ai-exec.sh`)

To avoid hardcoding provider-specific commands (like `claude -p`) into the shell scripts, a centralized **Provider Shim** is required.

- **Concept**: All automation scripts (Orchestrator, Planner) should call `ai-exec.sh` instead of a specific CLI binary.
- **Responsibility**: This script translates generic intent (e.g., `--headless`, `--json`, `--prompt`) into the correct CLI flags for the active provider.

### Detection Logic
The shim identifies the active provider using a tiered approach:
1.  **Explicit Override**: An environment variable like `DEGA_PROVIDER` (set by the TUI/Toad fork).
2.  **Environment Markers**: Presence of `CLAUDECODE` or `GEMINI_CLI` environment variables.
3.  **Process Inspection**: Checking the parent process name (`ps -p $PPID`).

---

## 3. The "Stateless Shim" Strategy (Project Roots)

Since AI agents (Claude, Gemini, Cursor) natively look for configuration files in the project root, we use "Pointer Files" rather than duplicating content.

- **`CLAUDE.md`**: Contains a reference link: `--- Context from: ~/.degacore/config/AGENTS.md ---`
- **`GEMINI.md`**: Contains the same reference link.
- **Outcome**: The agent finds the file natively, but the developer manages the rules in a single central location.

---

## 4. Implementation Priorities

### Update `/apply-core`
The installation command must be updated to:
- Default to `~/.degacore/` for all operations.
- Detect the installing CLI and set the initial `provider` in `dega-core.yaml`.
- Install the `ai-exec.sh` shim into the user's path or the global scripts directory.

### Decouple Engine Scripts
Systematically update the following scripts to use the abstraction layer:
- `orch-engine.sh` / `orch-review.sh` (Worker spawning)
- `ralph-loop.sh` (Legacy worker/reviewer iterations)

### Global Path Migration
Update all hooks (`structured-log.sh`, `play-sound.sh`) to resolve paths relative to a `DEGA_HOME` variable, defaulting to `~/.degacore/`.
