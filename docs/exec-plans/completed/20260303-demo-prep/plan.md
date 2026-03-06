# Demo Prep — March 5 Canon Demo

**Goal:** Smooth live demo: `/canon-init → exit → ./canon.sh → /canon-start → strategy built with dashboard`

**Principle:** All scaffold work is done by deterministic shell scripts, never inline agent instructions. The agent calls the script; the script does the work.

---

## Naming

| Name | Type | Who runs it | What it does |
|------|------|-------------|--------------|
| `/canon-init` | Claude command | User (inside Claude, no tmux) | Checks prereqs, copies `canon.sh` to project root, prints "exit and run ./canon.sh" |
| `canon.sh` | Local shell script | User (from terminal) | Launches tmux + dashboard + claude, pre-types `/canon-start` |
| `/canon-start` | Claude command | User (inside Claude, inside tmux) | Pipeline orchestrator — detects phase, calls `canon-scaffold.sh`, drives strategy/develop |
| `canon-scaffold.sh` | Global shell script | `/canon-start` (never the user) | Deterministic scaffold — fetch agents, skills, commands, generate templates, verify. Dashboard state writes built in. Installed at `~/.claude/scripts/canon-scaffold.sh` |

**User-visible flow (3 steps):**

```
/canon-init    →  "here's your launcher"
./canon.sh     →  tmux + dashboard + claude appear
/canon-start   →  everything happens (scaffold, strategy, develop)
```

**`canon-scaffold.sh` is an implementation detail** — a global engine
script like `ralph-loop.sh`. Installed by `/apply-core`, called by the
agent inside `/canon-start`, invisible to the user.

---

## Task 1: Rewrite `/canon-init` command — minimal bootstrap

**File:** `commands/canon-init.md`

**Current behavior:** Calls `bash ~/.claude/scripts/canon-init.sh` which
does the full scaffold.

**New behavior:** Lightweight bootstrap only:

1. **Guard:** Refuse to run from `claude-code-config` directory
2. **Check prerequisites:**
   - `tmux` installed → if not: "Install tmux: `brew install tmux`"
   - `node` installed → if not: "Install Node.js 22 LTS"
   - `pnpm` installed → if not: "Install pnpm: `npm i -g pnpm`"
   - `~/.claude/scripts/canon-scaffold.sh` exists → if not:
     "Run `/apply-core` and select Canon Scaffold + Terminal UI"
   - `~/.claude/scripts/terminal-ui-write.sh` exists → if not:
     same suggestion as above
3. **Create `.canon/` directory** (just the dir)
4. **Write `canon.sh`** to project root (from inline template or
   fetched from GitHub)
5. **Run `chmod +x canon.sh`**
6. **Print:**
   ```
   Canon bootstrap complete. All prerequisites met.

   Exit Claude and run:

     ./canon.sh
   ```

No fetching agents. No generating templates. No pnpm install.

---

## Task 2: Write `canon.sh` local launcher script

**Source:** Template written by `/canon-init` to the project root.
Also lives at `scripts/canon.sh` in the repo for reference.

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

`tmux send-keys ... ""` types without pressing Enter. User sees
`/canon-start` pre-typed, presses Enter to confirm.

---

## Task 3: Rename `canon-init.sh` → `canon-scaffold.sh`

**Rename:** `scripts/canon-init.sh` → `scripts/canon-scaffold.sh`

The script content stays the same — it already has dashboard state
writes at every step. Only the filename changes.

Update all references:
- `commands/canon-init.md` — no longer calls it (Task 1 rewrites this)
- `canon/commands/canon-start.md` — update to call `canon-scaffold.sh`
- `commands/apply-core.md` — update manifest entry (Task 5)

---

## Task 4: Update `/canon-start` to expect tmux + call `canon-scaffold.sh`

**File:** `canon/commands/canon-start.md`

Changes:

1. **Replace step 1 (tmux launch)** with a tmux detection check:
   - If inside tmux session "canon": good, continue
   - If inside tmux but different session: continue (dashboard may
     not be visible, but workflow works)
   - If NOT inside tmux at all: print message and stop:
     ```
     Not running inside tmux. Run ./canon.sh first to launch
     the Canon environment with the dashboard.
     ```

2. **Step 3 (init phase)** calls the renamed script:
   ```bash
   bash "${HOME}/.claude/scripts/canon-scaffold.sh"
   ```
   Script handles everything deterministically. Dashboard updates
   happen inside the script via `terminal-ui-write.sh` calls.

3. **After scaffold**, agent continues to step 4+ as before —
   detect phase, strategy, develop, run. Agent does judgment work;
   scripts do file work.

---

## Task 5: Add `canon-scaffold.sh` + `canon.sh` to `/apply-core` manifest

**File:** `commands/apply-core.md`

Add to the source file list:
- `scripts/canon-scaffold.sh`
- `scripts/canon.sh` (reference copy, also written by `/canon-init`)

Add install section (under Terminal UI or as a new "Canon Bootstrap" group):
- `scripts/canon-scaffold.sh` → `~/.claude/scripts/canon-scaffold.sh`
- `scripts/canon.sh` → `~/.claude/scripts/canon.sh`
- `chmod +x` both

Also update any existing references to `canon-init.sh` in the manifest.

---

## Task 6: Run `/apply-core` to install all global scripts

**Manual step:**

Run `/apply-core` and select ALL components including Terminal UI.
Verify after install:
- `~/.claude/scripts/canon-scaffold.sh` exists and is executable
- `~/.claude/scripts/canon.sh` exists and is executable
- `~/.claude/scripts/terminal-session.sh` exists
- `~/.claude/scripts/terminal-ui-write.sh` exists
- `~/.claude/scripts/terminal-ui/dist/cli.js` exists

---

## Task 7: Push `ace-work` branch to GitHub

**Manual step:**

`canon-scaffold.sh` fetches agents/skills/commands from GitHub.
Before the demo:
1. Commit all changes (including renames)
2. Push `ace-work` to origin
3. Verify: `curl -sfL https://raw.githubusercontent.com/DEGAorg/claude-code-config/ace-work/canon/agents/dev.md | head -3`

---

## Task 8: Pre-write demo fallback strategy spec

**New file:** `docs/demo-strategy-spec.md` (not committed, local only)

Write a strategy spec for a well-known Polymarket market so that if
`/discover` is slow or produces unexpected results, the user can paste
the pre-written spec instead.

---

## Task 9: End-to-end dry run

Full test of the demo flow:

1. Create a fresh empty directory
2. Start `claude` in it
3. Run `/canon-init`:
   - Prereqs all pass
   - `canon.sh` written to project root
   - Clear instructions printed
4. Exit Claude
5. Run `./canon.sh`:
   - tmux session "canon" created
   - Right pane: Ink dashboard shows "Waiting for /canon-start..."
   - Left pane: Claude auto-starts
   - `/canon-start` pre-typed in Claude prompt
6. Press Enter:
   - `/canon-start` runs
   - Detects init phase (no scaffold yet)
   - Calls `canon-scaffold.sh`
   - Dashboard updates live: dirs → agents → skills → commands → templates → verify
7. Scaffold complete, `/canon-start` continues:
   - Detects strategy phase
   - Asks: "Run /discover or provide a spec?"
8. Provide pre-written spec OR run `/discover`
9. Development phase with dashboard updates

---

## Progress Log

- [x] Task 1: Rewrite `/canon-init` to minimal bootstrap
- [x] Task 2: Write `canon.sh` local launcher (also at `scripts/canon.sh`)
- [x] Task 3: Rename `canon-init.sh` → `canon-scaffold.sh`, update refs
- [x] Task 4: Update `/canon-start` — expect tmux, call `canon-scaffold.sh`
- [x] Task 5: Add `canon-scaffold.sh` + `canon.sh` to `/apply-core` manifest
- [x] Task 6: Run `/apply-core` to install all global scripts
- [x] Task 7: Push `ace-work` to GitHub, verify fetches
- [x] Task 8: Pre-write demo fallback strategy spec
- [x] Task 9: End-to-end dry run
