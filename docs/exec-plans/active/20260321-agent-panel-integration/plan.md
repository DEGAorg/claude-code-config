# Plan: Agent-to-panel integration — Claude controls the GitHub panel

**Status:** In progress
**Created:** 2026-03-21

## Requirements

- When the user says "show me the project state" (or similar), Claude opens the GitHub panel
- When the user says "close the panel" or "hide project state", Claude closes it
- Claude must be aware of the panel system — what panels exist, how to open/close them
- Works through Toad's ACP protocol (sessionUpdate messages already wired)
- No manual keybinding needed — the agent controls the UI

## Approach

The ACP plumbing exists (OpenPanel/ClosePanel messages, handlers in agent.py and main.py). The gap is that Claude doesn't know it can send these. Three pieces needed:

### 1. Toad slash command: `/panel`

Register a `/panel` slash command in Toad that the agent can invoke. When the agent types `/panel github` in its response, Toad intercepts it and emits the OpenPanel message. This is the simplest path — Toad already has a slash command system.

```
/panel github        → opens GitHub panel
/panel github close  → closes GitHub panel
/panel list          → lists available panels
```

### 2. Agent instruction via CLAUDE.md or system prompt

The agent needs to know the `/panel` command exists. This can be:
- A CLAUDE.md instruction in the project being worked on
- A skill file that gets loaded into the conductor context
- Toad's agent config that injects panel awareness into the system prompt

### 3. Toad agent config for Claude

Update the Claude agent config (`data/agents/claude.com.toml`) or add a conductor-specific config that includes panel instructions in the agent's system prompt or available commands.

## Files to touch

| File | Change |
|------|--------|
| `/Users/cerratoa/dega/conductor-view/src/toad/slash_command.py` | Register `/panel` slash command |
| `/Users/cerratoa/dega/conductor-view/src/toad/widgets/conversation.py` | Handle `/panel` command — emit OpenPanel/ClosePanel messages |
| `/Users/cerratoa/dega/conductor-view/src/toad/data/agents/claude.com.toml` | Add panel instructions to Claude's agent help or description |
| `skills/conductor-panels.md` | New — skill that teaches Claude about panel commands (loaded in conductor context) |

## Progress log

- [ ] Register `/panel` slash command in Toad — parse args (panel_id, open/close), emit OpenPanel/ClosePanel ACP messages
- [ ] Handle `/panel` in conversation widget — intercept before sending to agent, translate to panel messages (deps: 1)
- [ ] Create `skills/conductor-panels.md` in claude-code-config — teaches Claude about available panels and the `/panel` command (deps: 1)
- [ ] Update Claude agent config in conductor-view — add panel awareness to agent description or help text (deps: 1)
- [ ] Test: launch toad --conductor, type "show me the project state", verify Claude responds with /panel github and panel opens (deps: 1, 2, 3, 4)

## Completion criteria

- [ ] `/panel github` opens the GitHub panel in Toad
- [ ] `/panel github close` closes it
- [ ] Claude knows about the panel system and uses it when asked for project state
- [ ] Panel opens without user pressing ctrl+g
- [ ] Works end-to-end: user asks → Claude responds → panel opens
