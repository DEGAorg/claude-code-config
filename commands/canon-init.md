# Canon Init

@description Bootstrap Canon environment — checks prerequisites, writes the launcher script.

Run every step below in order. Stop and report if any prerequisite fails.

---

## 1. Guard: wrong directory

Check if the current directory is the `claude-code-config` repo by looking for
`CLAUDE.md` containing "claude-code-config":

```bash
[[ -f "CLAUDE.md" ]] && grep -q "claude-code-config" "CLAUDE.md" 2>/dev/null
```

If that succeeds, stop and print:

> Run `/canon-init` from your strategy project directory, not from `claude-code-config`.

Do not continue.

---

## 2. Check prerequisites

Check each prerequisite. Collect all failures and report them together at the end.
Do not stop at the first failure — check all of them so the user gets one complete list.

| Check | Command | If missing |
|-------|---------|-----------|
| tmux | `command -v tmux` | "Install tmux: `brew install tmux`" |
| node | `command -v node` | "Install Node.js 22 LTS" |
| pnpm | `command -v pnpm` | "Install pnpm: `npm i -g pnpm`" |
| canon-scaffold.sh | `[[ -f "${HOME}/.claude/scripts/canon-scaffold.sh" ]]` | "Run `/apply-core` and select Canon Scaffold + Terminal UI" |
| terminal-ui-write.sh | `[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]]` | same as above |

If any prerequisites are missing, print all missing items and stop:

> **Missing prerequisites:**
> - <item>: <install instruction>
>
> Fix these and re-run `/canon-init`.

Do not continue if any check fails.

---

## 3. Create directories and install `/canon-start` command

```bash
mkdir -p .canon .claude/commands
```

Fetch the `/canon-start` command so it's available when Claude starts inside tmux:

```bash
curl -sfL "https://raw.githubusercontent.com/DEGAorg/claude-code-config/ace-work/canon/commands/canon-start.md" \
  -o .claude/commands/canon-start.md
```

If the fetch fails, stop and tell the user:

> Failed to fetch `/canon-start` command. Check your internet connection and try again.

---

## 4. Write `canon.sh` launcher to project root

Write this exact script to `canon.sh` in the current directory. Use a bash heredoc
or the Write tool. The script must be written exactly as shown — do not modify it.

```bash
#!/usr/bin/env bash
set -euo pipefail

STATE="$(pwd)/.canon/state.json"
TUI_WRITE="${HOME}/.claude/scripts/terminal-ui-write.sh"

# ── Init state file ──────────────────────────────────────────────────
mkdir -p .canon
if [[ -f "${TUI_WRITE}" ]]; then
  bash "${TUI_WRITE}" "${STATE}" \
    phase=init status=idle log.info="Waiting for /canon-start..."
else
  printf '{"phase":"init","status":"idle","startedAt":"%s","updatedAt":"%s","logs":[],"error":null,"metrics":{}}\n' \
    "$(date -u +%FT%TZ)" "$(date -u +%FT%TZ)" > "${STATE}"
fi

# ── Dashboard renderer (best available) ──────────────────────────────
RIGHT_CMD="bash -c 'while true; do clear; cat \"${STATE}\" 2>/dev/null; sleep 1; done'"
[[ -f "${HOME}/.claude/scripts/terminal-ui/dist/cli.js" ]] && \
  RIGHT_CMD="node ${HOME}/.claude/scripts/terminal-ui/dist/cli.js --state ${STATE}"
command -v terminal-ui >/dev/null 2>&1 && \
  RIGHT_CMD="terminal-ui --state ${STATE}"

# ── Create tmux: left=claude, right=dashboard ────────────────────────
tmux new-session -d -s canon "claude"
tmux split-window -h -t canon -p 40 "${RIGHT_CMD}"
tmux select-pane -t canon:.0

# ── Pre-type /canon-start (user hits Enter to confirm) ──────────────
tmux send-keys -t canon:.0 "/canon-start" ""

# ── Status bar ───────────────────────────────────────────────────────
tmux set-option -t canon status-left " Canon "
tmux set-option -t canon status-right " %H:%M "

exec tmux attach-session -t canon
```

Then make it executable:

```bash
chmod +x canon.sh
```

---

## 5. Print completion message

Print exactly:

> Canon bootstrap complete. All prerequisites met.
>
> Exit Claude and run:
>
>     ./canon.sh

Do not run anything else. Do not fetch agents, generate templates, or install
dependencies. The launcher script handles everything from here.
