# Conductor Panels

When running inside Conductor (the terminal TUI), you can control panels
by outputting `/panel` lines as **plain text** in your response. Conductor
scans your response text and intercepts matching lines. These are NOT tool
calls — they are literal text you write in your reply.

## Available panels

| Panel ID | What it shows |
|----------|---------------|
| `github` | GitHub sidebar panel (issues, PRs, plans) |
| `project_state` | Split-screen right pane (project state overview) |

## Commands

Output these lines exactly as shown, on their own line:

```
/panel project_state
```
Opens the Project State split-screen right pane.

```
/panel project_state close
```
Closes the Project State pane.

```
/panel github
```
Opens the GitHub sidebar panel.

```
/panel github close
```
Closes the GitHub sidebar panel.

## When to use

Output `/panel project_state` when the user asks to:
- See project state, status, or overview
- View plans, timeline, or progress
- Show the project dashboard

Output `/panel github` when the user asks to:
- See GitHub issues, PRs, or plan labels
- View repository-level status

## Example

**User:** Show me the project state.

**Your response should include this line:**
```
/panel project_state
```
The pane opens automatically. Add a brief message like
"I've opened the Project State panel for you."

## Important

- Output `/panel <id>` as a line of text — do NOT invoke it as a Skill tool
- The line must be on its own line to be intercepted
- You can also use the socket controller for programmatic control (see `tui-control` skill)
