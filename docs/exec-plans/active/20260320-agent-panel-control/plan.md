# Plan: Agent-controlled panels + direct conductor launch

**Status:** In progress
**Created:** 2026-03-20

## Requirements

### Direct conductor launch
- Add a shortcut on Toad's home/store screen that launches Claude conductor directly — no dropdown, no install prompts, one click
- Alternatively, a CLI flag like `toad conductor` or `toad --conductor` that skips the home screen entirely and opens Claude session with the project context
- Claude Code + ACP adapter must be detected automatically; if missing, show a single "Install" button that does it all

### Agent-controlled panels
- The Claude agent (conductor) can open/close panels programmatically
- New ACP message types: `OpenPanel`, `ClosePanel` that the agent sends to control what's displayed
- When user says "show me the project state", the agent sends `OpenPanel("github")` and the panel appears
- The agent can pass context (e.g., which repo to show)
- Panels can be dismissed by the agent or by the user (ctrl+g still works)

## Approach

### Direct launch
Toad's home screen (`screens/store.py`) shows agent cards. Add a "Canon Conductor" card pinned to the top that auto-selects Claude with the project-dir context. Or add a `--conductor` CLI flag to `cli.py` that skips the store screen and goes directly to MainScreen with Claude.

### Agent panel control
Toad uses Textual messages to communicate between ACP agent and UI. The pattern exists for `Plan` updates (`sessionUpdate: "plan"`). Extend this:

1. Add new `sessionUpdate` types in the ACP protocol layer:
   - `{"sessionUpdate": "open_panel", "panelId": "github", "context": {...}}`
   - `{"sessionUpdate": "close_panel", "panelId": "github"}`
2. Add message handlers in `Conversation` widget that translate these into Textual messages
3. `MainScreen` handles the messages and mounts/unmounts panels dynamically

For Claude to send these, it needs a tool (MCP or slash command) that emits the right ACP message. In the short term, the agent can use a `/panel` slash command.

## Files to touch

| File | Change |
|------|--------|
| `/Users/cerratoa/dega/conductor-view/src/toad/cli.py` | Add `--conductor` flag that skips store, launches Claude directly |
| `/Users/cerratoa/dega/conductor-view/src/toad/screens/store.py` | Add pinned "Conductor" card at top |
| `/Users/cerratoa/dega/conductor-view/src/toad/acp/messages.py` | Add OpenPanel, ClosePanel message types |
| `/Users/cerratoa/dega/conductor-view/src/toad/acp/agent.py` | Handle `open_panel`/`close_panel` sessionUpdate events |
| `/Users/cerratoa/dega/conductor-view/src/toad/screens/main.py` | Handle OpenPanel/ClosePanel messages, dynamically mount panels |

## Progress log

- [x] Add `--conductor` CLI flag to skip store and launch Claude directly with project-dir context
- [ ] Add pinned "Conductor" shortcut card on the store/home screen that does the same as --conductor (deps: 1)
- [x] Add `OpenPanel` and `ClosePanel` message types in `acp/messages.py` (deps: 1)
- [ ] Handle `open_panel`/`close_panel` sessionUpdate events in `acp/agent.py` — translate to Textual messages (deps: 3)
- [ ] Handle OpenPanel/ClosePanel in `screens/main.py` — dynamically mount/unmount sidebar panels with context (deps: 4)
- [ ] Test: launch with `toad --conductor --project-dir ~/dega/aidd/claude-code-config`, ask agent "show project state", verify GitHub panel opens (deps: 1, 5)

## Completion criteria

- [ ] `toad --conductor` skips home screen and opens Claude session directly
- [ ] Home screen has a pinned Conductor shortcut
- [ ] Agent can send open_panel/close_panel via ACP sessionUpdate
- [ ] "show project state" in chat opens the GitHub panel
- [ ] ctrl+g still works as manual toggle
