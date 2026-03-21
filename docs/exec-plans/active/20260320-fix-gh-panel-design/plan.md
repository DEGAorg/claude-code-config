# Plan: Fix GitHub panel — agent-summoned and repo-aware

**Status:** In progress
**Created:** 2026-03-20

## Requirements

- GitHub panel must NOT be mounted in the sidebar by default — it should only appear when the agent (or user via keybinding) summons it
- The panel must show the repo configured in `dega-core.yaml` (the project being worked on), NOT the conductor-view repo
- `ctrl+g` should still toggle it, but starting state is hidden
- When the agent sends a command to show project state, the panel opens with the correct repo
- The repo should be configurable: read from dega-core.yaml in the project directory the agent is working in, or fall back to `--repo` flag when launching toad

## Approach

### Fix 1: Remove default sidebar mount, make it on-demand

Currently `screens/main.py` mounts `GitHubStateWidget` as a `SideBar.Panel` in `compose()`. Change this:
- Remove the GitHub panel from `compose()`
- `ctrl+g` (or agent command) dynamically mounts the panel into the sidebar
- If already mounted, toggle visibility
- If not mounted, create and mount it with the target repo

### Fix 2: Read repo from the project directory, not cwd

The `detect_repo()` function in `fetch.py` uses `gh repo view` which reads the cwd's git remote. Instead:
1. Accept a `--project-dir` or `--repo` argument when launching toad
2. Read `dega-core.yaml` from the project directory for `github.repo`
3. Fall back to git remote of the project directory (not conductor-view's directory)
4. Pass the resolved `RepoInfo` to the widget when mounting

### Fix 3: Agent-controlled panel opening

Toad's ACP message system lets the agent send `sessionUpdate` events. Add a new message type that the agent can send to open the GitHub panel with a specific repo. This connects to the "agent controls the UI" API we discussed in the architecture.

## Files to touch

| File | Change |
|------|--------|
| `/Users/cerratoa/dega/conductor-view/src/toad/screens/main.py` | Remove GitHub panel from compose(), add dynamic mount in action_toggle_github() |
| `/Users/cerratoa/dega/conductor-view/src/toad/widgets/github_views/fetch.py` | Add `detect_repo_from_path(path)` that reads dega-core.yaml or git remote from a given directory |
| `/Users/cerratoa/dega/conductor-view/src/toad/widgets/github_state.py` | Accept project_path parameter, pass to fetch functions |
| `/Users/cerratoa/dega/conductor-view/src/toad/cli.py` | Add `--project-dir` CLI argument, pass to MainScreen |

## Progress log

- [x] Update `fetch.py` — add `detect_repo_from_path(path)` that reads dega-core.yaml github.repo or git remote from a specified project directory
- [x] Update `github_state.py` — accept `project_path` parameter, use `detect_repo_from_path` instead of `detect_repo` (deps: 1)
- [ ] Update `screens/main.py` — remove GitHub panel from compose(), make `action_toggle_github` dynamically mount it on first toggle with project_path (deps: 2)
- [ ] Update `cli.py` — add `--project-dir` argument, pass through to MainScreen so the panel knows which project to show (deps: 3)
- [ ] Test: launch toad with `--project-dir ~/dega/aidd/claude-code-config`, press ctrl+g, verify it shows claude-code-config issues not conductor-view issues (deps: 4)

## Completion criteria

- [ ] GitHub panel is NOT visible on initial load
- [ ] ctrl+g opens the panel dynamically
- [ ] Panel shows issues from the specified project repo, not conductor-view
- [ ] `toad --project-dir /path/to/project` controls which repo the panel shows
- [ ] Without --project-dir, falls back to dega-core.yaml or git remote of cwd
