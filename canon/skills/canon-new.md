# Canon New

@description Start a new prediction-market project with Canon. Triggers on natural-language intent like "new prediction-market project", "start a new strategy", or "I want to try an idea on Polymarket/Kalshi" — detects the current bootstrap phase and hands off to `/apply-core` when Canon is not yet installed, or runs the Canon init flow when it is.

## When to use this skill

Invoke this skill when the user expresses intent to begin a new
prediction-market project or strategy, *before* Canon is necessarily
installed in their working directory. Example phrases:

- "I want to start a new prediction-market project"
- "Let's start a new strategy"
- "I want to try an idea on Polymarket"
- "Try an idea on Kalshi"
- "New project on Polymarket/Kalshi"

Do **not** invoke this skill for questions about existing strategies,
bug reports, or generic Polymarket/Kalshi conversation that isn't about
scaffolding a new project.

---

## 1. Guard: wrong directory

Check if the current directory is the `claude-code-config` repo by looking for
`AGENTS.md` containing "claude-code-config":

```bash
[[ -f "AGENTS.md" ]] && grep -q "claude-code-config" "AGENTS.md" 2>/dev/null
```

If that succeeds, stop and print:

> Run this from your strategy project directory, not from `claude-code-config`.

Do not continue.

---

## 2. Detect the current bootstrap phase

Run the phase-detection helper from the installed Canon scripts directory:

```bash
bash "${DEGA_CORE_HOME:-${HOME}/.degacore}/canon/scripts/bootstrap-check.sh" 2>/dev/null \
  || bash canon/scripts/bootstrap-check.sh 2>/dev/null \
  || echo "not-bootstrapped"
```

The script prints one of three tokens on stdout:

| Token | Meaning |
|-------|---------|
| `not-bootstrapped` | No `dega-core.yaml` at the working directory — Canon is not installed here. |
| `bootstrapped-no-strategy` | `dega-core.yaml` exists but `canon/strategies/` is empty or missing. |
| `has-strategy` | At least one strategy is already scaffolded under `canon/strategies/`. |

Dispatch on the token as described below. Do not skip the dispatch — each
phase has a different hand-off.

---

## 3. Dispatch by phase

### Phase: `not-bootstrapped`

Canon has not been installed in this directory. Hand off to `/apply-core`
so the user can install the agent shim, `canon-scaffold.sh`, and this
skill itself. Print:

> This directory isn't set up for Canon yet. Run `/apply-core` to install
> the Canon runtime (agent shim + scaffold scripts + skills), then ask me
> again to start a new prediction-market project.

Do not continue. Do not attempt to fetch or write files — `/apply-core`
owns installation.

### Phase: `bootstrapped-no-strategy`

Canon is installed but no strategy exists yet. Run the init flow
described in section 4 to scaffold `canon.sh`, install `/canon-start`,
and prepare the workspace.

### Phase: `has-strategy`

At least one strategy is already scaffolded. Ask the user whether they
want to:

1. Create an additional strategy alongside the existing ones, or
2. Open the existing workspace (`./canon.sh`).

If (1), proceed with the init flow in section 4 but skip any step that
would overwrite an existing file (`canon.sh`, `agent-shim.sh`). If (2),
print the launch reminder from section 6 and stop.

---

## 4. Check prerequisites

Check each prerequisite. Collect all failures and report them together at the end.
Do not stop at the first failure — check all of them so the user gets one complete list.

| Check | Command | If missing |
|-------|---------|-----------|
| canon or tmux | `command -v canon \|\| command -v tmux` | "Install canon (preferred): see DEGAorg/conductor-view README, or tmux: `brew install tmux`" |
| agent-shim.sh | `[[ -f "${DEGA_CORE_HOME:-${HOME}/.degacore}/scripts/agent-shim.sh" ]]` | "Run `/apply-core` to install the agent shim" |
| canon-scaffold.sh | `[[ -f "${DEGA_CORE_HOME:-${HOME}/.degacore}/scripts/canon-scaffold.sh" ]]` | "Run `/apply-core` and select Canon Scaffold" |

If any prerequisites are missing, print all missing items and stop:

> **Missing prerequisites:**
> - <item>: <install instruction>
>
> Fix these and re-run.

Do not continue if any check fails.

---

## 5. Create directories and install `/canon-start` command

```bash
mkdir -p .canon .claude/commands
```

Fetch the `/canon-start` command so it's available when the agent starts:

```bash
curl -sfL "https://raw.githubusercontent.com/DEGAorg/claude-code-config/develop/canon/commands/canon-start.md" \
  -o .claude/commands/canon-start.md
```

If the fetch fails, stop and tell the user:

> Failed to fetch `/canon-start` command. Check your internet connection and try again.

---

## 6. Write `canon.sh` launcher to project root

First, copy the agent shim so `canon.sh` can source it from the same directory:

```bash
cp "${DEGA_CORE_HOME:-${HOME}/.degacore}/scripts/agent-shim.sh" agent-shim.sh
```

Then write this exact script to `canon.sh` in the current directory. Use a bash
heredoc or the Write tool. The script must be written exactly as shown — do not
modify it.

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=agent-shim.sh
source "${SCRIPT_DIR}/agent-shim.sh"

PROJECT_DIR="$(pwd)"
STATE="${PROJECT_DIR}/.canon/state.json"
TUI_WRITE="${DEGA_CORE_HOME}/scripts/terminal-ui-write.sh"

# ── Init state file ──────────────────────────────────────────────────
mkdir -p .canon
if [[ -f "${TUI_WRITE}" ]]; then
  bash "${TUI_WRITE}" "${STATE}" \
    phase=init status=idle log.info="Waiting for /canon-start..."
else
  printf '{"phase":"init","status":"idle","startedAt":"%s","updatedAt":"%s","logs":[],"error":null,"metrics":{}}\n' \
    "$(date -u +%FT%TZ)" "$(date -u +%FT%TZ)" >"${STATE}"
fi

# ── Launch mode: Canon TUI (preferred) or tmux (fallback) ────────────
if command -v canon >/dev/null 2>&1; then
  echo "Launching Canon TUI. Type /canon-start to begin."
  exec canon run "${PROJECT_DIR}"
fi

# ── Fallback: tmux with agent + dashboard ────────────────────────────
if ! command -v tmux >/dev/null 2>&1; then
  echo "error: neither canon nor tmux found. Install one of:"
  echo "  canon — see DEGAorg/conductor-view README"
  echo "  tmux  — brew install tmux"
  exit 1
fi

_canon_dashboard_cmd() {
  if command -v terminal-ui >/dev/null 2>&1; then
    echo "terminal-ui --state ${STATE}"
    return
  fi
  if [[ -f "${DEGA_CORE_HOME}/scripts/terminal-ui/dist/cli.js" ]]; then
    echo "node ${DEGA_CORE_HOME}/scripts/terminal-ui/dist/cli.js --state ${STATE}"
    return
  fi
  echo "bash -c 'while true; do clear; cat \"${STATE}\" 2>/dev/null; sleep 1; done'"
}
RIGHT_CMD="$(_canon_dashboard_cmd)"

HEADLESS_FLAGS="$(dega_agent_headless_flags)"
AGENT_CMD="$(dega_agent_command) ${HEADLESS_FLAGS}; "
AGENT_CMD+="[[ -f '${TUI_WRITE}' ]] && bash '${TUI_WRITE}' '${STATE}' status=idle log.info='Agent session ended'; "
AGENT_CMD+="echo 'Agent exited. Run ./canon.sh to restart, or Ctrl-D to close.'; "
AGENT_CMD+="exec bash"
tmux new-session -d -s canon "${AGENT_CMD}"
tmux split-window -h -t canon -p 40 "${RIGHT_CMD}"
tmux select-pane -t canon:.0

tmux send-keys -t canon:.0 "/canon-start" ""

tmux set-option -t canon status-left " Canon "
tmux set-option -t canon status-right " %H:%M "

exec tmux attach-session -t canon
```

Then make it executable:

```bash
chmod +x canon.sh
```

---

## 7. Print completion message

Print exactly:

> Canon is ready. All prerequisites met.
>
> Exit this agent and run:
>
>     ./canon.sh
>
> Then type `/canon-start` to begin your new prediction-market strategy.

Do not run anything else. Do not fetch agents, generate templates, or install
dependencies. The launcher script handles everything from here.
