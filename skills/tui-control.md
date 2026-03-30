# TUI Control via Socket

When Toad (Conductor) is running, it exposes a Unix socket at `/tmp/toad-{pid}.sock`
for programmatic control. Use this to read UI state, toggle views, and update
widgets from shell commands.

## Client

Use `toad-ctl.sh` (in the conductor-view repo) or `socat` directly:

```bash
# Auto-discovers the socket
toad-ctl.sh <command> [args...]

# Or with socat directly
echo '{"cmd":"ping"}' | socat - UNIX-CONNECT:/tmp/toad-*.sock
```

## Commands

### Read state

```bash
# Check TUI is alive
toad-ctl.sh ping

# Get full widget tree (JSON)
toad-ctl.sh snapshot

# Query widgets by CSS selector
toad-ctl.sh query "Button"
toad-ctl.sh query "#project_state_pane"
```

### Trigger actions

```bash
# Toggle the Project State right pane (ctrl+g equivalent)
toad-ctl.sh action "screen.toggle_project_state"

# Toggle dark mode
toad-ctl.sh action toggle_dark

# Open sidebar
toad-ctl.sh action "screen.show_sidebar"

# Any action_* method on App or Screen is callable
toad-ctl.sh action "screen.<action_name>"
```

### Modify widgets

```bash
# Update a widget's text content
toad-ctl.sh update "#project-state-title" "Build Status: Passing"

# Focus a widget
toad-ctl.sh focus "#project_state_pane"

# Simulate a keypress
toad-ctl.sh press enter
```

### Raw JSON

```bash
toad-ctl.sh raw '{"cmd":"action","name":"screen.toggle_project_state"}'
```

## Action namespacing

Textual routes actions by namespace:

| Prefix | Routes to | Example |
|--------|-----------|---------|
| (none) | App | `toggle_dark` |
| `screen.` | Active Screen | `screen.toggle_project_state` |
| `focused.` | Focused Widget | `focused.action_name` |

## When to use

Use socket control when you need to:
- Toggle the Project State pane before/after showing project info
- Update widget content with live data (build status, test results)
- Read the current UI state to decide what to show the user
- Automate TUI interactions from orchestrator scripts

## Key actions

| Action | What it does |
|--------|-------------|
| `screen.toggle_project_state` | Toggle right pane (Project State) |
| `screen.show_sidebar` | Focus the left sidebar |
| `toggle_dark` | Toggle dark/light theme |
| `screen.go_home` | Return to agent picker |
| `screen.sessions` | Open sessions screen |

## Python usage

```python
import json
import socket
from glob import glob

def toad_cmd(cmd: dict) -> dict:
    path = glob("/tmp/toad-*.sock")[0]
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(path)
    s.sendall(json.dumps(cmd).encode() + b"\n")
    response = s.makefile().readline()
    s.close()
    return json.loads(response)

# Toggle project state pane
toad_cmd({"cmd": "action", "name": "screen.toggle_project_state"})

# Read widget tree
state = toad_cmd({"cmd": "snapshot"})
```
