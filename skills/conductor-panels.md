# Conductor Panels

How to control Toad/Conductor sidebar panels from within a conversation.
Use this skill when the user asks to see project state, GitHub info,
or wants to open/close UI panels programmatically.

---

## The `/panel` command

Toad registers a `/panel` slash command that the agent can use in responses.
When the agent outputs `/panel <id>`, Toad intercepts it and emits the
corresponding ACP message — the panel opens or closes without the user
pressing any keybinding.

### Syntax

```
/panel <panel_id>          Open a panel
/panel <panel_id> close    Close a panel
/panel list                List available panels
```

### Available panels

| Panel ID | Description | Keybinding equivalent |
|----------|-------------|-----------------------|
| `github` | GitHub sidebar — repo info, issues, PRs, actions | `ctrl+g` |

More panels may be added in the future. Use `/panel list` to discover
what is available at runtime.

---

## When to use panels

Open the GitHub panel when the user:
- Asks to "show project state" or "show me the repo"
- Wants to see open issues, pull requests, or CI status
- Says "open GitHub" or "show GitHub panel"
- Needs context about the current repository

Close the panel when the user:
- Says "close the panel", "hide GitHub", or "I'm done looking"
- Asks to focus on the conversation

Do not open panels unprompted — only when the user's intent clearly
calls for visual context.

---

## How it works (ACP protocol)

The `/panel` command translates to ACP `sessionUpdate` messages:

| Command | ACP message |
|---------|-------------|
| `/panel github` | `{"sessionUpdate": "open_panel", "panelId": "github"}` |
| `/panel github close` | `{"sessionUpdate": "close_panel", "panelId": "github"}` |

These messages flow: conversation widget -> ACP agent -> main screen,
where `_open_github_panel()` / `_close_github_panel()` handle the
mount/unmount in the sidebar.

---

## Example interaction

**User:** Show me the project state.

**Agent response:**
```
/panel github
Here's your project — the GitHub panel is now open in the sidebar.
You can see open issues, recent PRs, and CI status there.
```

**User:** Thanks, close it.

**Agent response:**
```
/panel github close
Panel closed.
```
