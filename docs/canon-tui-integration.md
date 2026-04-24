# Conductor TUI Integration — Work Items for canon-tui

> **Date:** 2026-04-06
> **Repo:** DEGAorg/canon-tui (`/Users/cerratoa/dega/canon-tui`)
> **Context:** The Conductor agent prompt lives in `claude-code-config/agents/conductor.md`.
> This document lists work needed in the canon-tui repo to make the
> Conductor the default entry agent and clean up panel control.

---

## 1. Make Conductor the Default Agent

### Current behavior

The TUI decides which agent to use via this chain (`src/toad/cli.py:145-168`):

1. `--agent` CLI flag (if provided)
2. `toad.json` setting at `~/.config/toad/toad.json` → `agent.default_agent`
3. If neither → launches in "store" mode (agent picker screen)

### What to change

The Conductor is not a separate agent binary — it's a **system prompt
overlay** on top of Claude Code. The TUI should inject the Conductor
persona into the agent's first prompt so that Claude Code behaves as the
Conductor when running inside the TUI.

**Option A (recommended): Expand agent context injection**

The existing mechanism at `src/toad/acp/agent.py:640-673` already injects
`src/toad/data/agent_context.md` as the first content block on the first
prompt. This is the right hook.

Changes needed:

- [ ] **Replace `agent_context.md` content** with the full Conductor agent
  prompt from `claude-code-config/agents/conductor.md`, plus the existing
  TUI socket commands reference. The file should contain:
  1. Conductor identity, persona, and behavioral rules
  2. Socket commands reference (already there, keep it)
  3. State gathering instructions adapted for the TUI context
  4. Delegation rules (what the Conductor does and does not do)

- [ ] **Set `claude.com` as the default agent** so the TUI skips the store
  screen and goes straight to the Conductor. Two options:
  - Set in `toad.json` during install (`install.sh` or first-run setup)
  - Or hardcode fallback in `_read_default_agent()` at `src/toad/cli.py:56`
    to return `"claude.com"` when no setting exists

**Option B (not recommended): Create a separate `conductor.toml` agent**

This would mean a new agent binary or wrapper script. Unnecessary — the
Conductor is Claude Code with a system prompt, not a different runtime.

### Key files

| File | What to do |
|------|-----------|
| `src/toad/data/agent_context.md` | Replace with Conductor prompt + socket reference |
| `src/toad/cli.py:56-68` | Default to `"claude.com"` when no setting exists |
| `src/toad/acp/agent.py:640-673` | No changes needed — injection mechanism works as-is |

---

## 2. Clean Up Panel Control — Remove `/panel` Text Commands

### Current state

Two panel control mechanisms coexist:

| Mechanism | Location | Status |
|-----------|----------|--------|
| `/panel` text interception | `src/toad/widgets/conversation.py:936-964` | Deprecated — remove |
| Socket CLI (`canon-ctl`) | `src/toad/data/agent_context.md` | Active — keep |

The agent context file already tells agents to use `canon-ctl` and NOT
`/panel` text. But the interception code and references still exist.

### Changes needed

- [ ] **Remove `/panel` regex interception** from
  `src/toad/widgets/conversation.py:936-964`
  (`_PANEL_COMMAND_RE` and `_intercept_panel_commands` method)

- [ ] **Remove `/panel` references from `claude.com.toml`** — the `help`
  field at `src/toad/data/agents/claude.com.toml:29-37` still documents
  `/panel github`, `/panel github close`, `/panel list`. Replace with
  `canon-ctl` socket commands.

- [ ] **Update `welcome` message in `claude.com.toml`** — line 45 says
  "Press ctrl+g to toggle the Project Status panel." Verify this is still
  accurate, or update to reference the Conductor.

- [ ] **Remove ACP panel messages if unused** — check if `OpenPanel` and
  `ClosePanel` in `src/toad/acp/messages.py` are still needed after removing
  text interception. The socket `action` command handles panels natively
  via Textual actions (`screen.show_github`, `screen.toggle_project_state`,
  etc.), so ACP panel messages may be dead code.

- [ ] **Update tests** — `tests/test_agent_panel_control.py` likely tests
  the `/panel` interception. Update or remove tests to match the new
  socket-only approach.

### Key files

| File | What to do |
|------|-----------|
| `src/toad/widgets/conversation.py:936-964` | Remove `_intercept_panel_commands` and `_PANEL_COMMAND_RE` |
| `src/toad/data/agents/claude.com.toml` | Remove `/panel` from help text, update with `canon-ctl` |
| `src/toad/acp/messages.py` | Check if `OpenPanel`/`ClosePanel` still needed |
| `tests/test_agent_panel_control.py` | Update or remove panel interception tests |

---

## 3. Socket Commands — Verify Panel Coverage

### Current socket actions (from `agent_context.md`)

```
screen.show_github
screen.show_timeline
screen.show_builder
screen.show_automation
screen.toggle_project_state
screen.refresh_timeline
```

### Verify these cover all panel operations

- [ ] **Confirm `show_github` replaces `/panel github`** — both open and
  close. If `show_github` is a toggle, it covers both. If it only opens,
  a `screen.hide_github` action may be needed.

- [ ] **Confirm `toggle_project_state` replaces `/panel project_state`**
  — same open/close question.

- [ ] **Document close behavior** — the Conductor prompt needs to know
  whether actions are toggles or open-only. Update `agent_context.md`
  accordingly.

---

## 4. Conductor Welcome Experience

When the TUI starts with the Conductor as default agent, the user should
see a clear indication they're talking to the Conductor, not raw Claude.

- [ ] **Update `welcome` in `claude.com.toml`** to reflect the Conductor
  persona. Something like:
  ```
  Conductor ready. Gathering project state...
  ```

- [ ] **On first prompt, the Conductor should gather state** — this is
  handled by the injected `agent_context.md` instructions. The Conductor
  prompt says to gather state on session start (orch status, plans, git,
  PRs, TUI panels). Verify this works with the context injection timing
  (context is injected on first user prompt, not on TUI launch).

---

## File Reference (all paths relative to canon-tui root)

| File | Purpose |
|------|---------|
| `src/toad/cli.py` | CLI entry, default agent selection |
| `src/toad/app.py` | ToadApp, socket server startup |
| `src/toad/acp/agent.py` | Context injection on first prompt |
| `src/toad/data/agent_context.md` | Injected agent instructions (replace with Conductor prompt) |
| `src/toad/data/agents/claude.com.toml` | Claude Code agent config (help, welcome, run_command) |
| `src/toad/widgets/conversation.py` | Panel command interception (remove) |
| `src/toad/acp/messages.py` | ACP panel messages (check if still needed) |
| `src/toad/socket_controller.py` | Socket server (no changes needed) |
| `tools/toad-ctl.sh` | Socket CLI (no changes needed) |
| `src/toad/ctl.py` | Python socket CLI (no changes needed) |
| `tests/test_agent_panel_control.py` | Panel tests (update/remove) |

---

## Dependency: claude-code-config

The Conductor agent prompt at `agents/conductor.md` is the source of truth.
When updating `agent_context.md` in this repo, pull the content from there
and merge it with the socket commands reference already in place.
