# Plan: Conductor TUI — Toad Fork + GitHub Project State

**Status:** In progress
**Created:** 2026-03-20

## Requirements

- Fork Toad (AGPL-3.0) as the base for Canon's conductor TUI
- Add a GitHub Project State panel to the SideBar with 4 views: Timeline, Issues, Plans, PRs
- Data comes live from GitHub via `gh` CLI — no stale local files
- Panel opens when the user (or conductor) requests project state
- Reuses `scripts/ensure-gh.sh` from the GitHub Issues plan for cross-platform gh setup
- Works with any GitHub repo (reads from `dega-core.yaml` or git remote)
- Keyboard navigation: Tab (switch views), arrow keys (scroll), r (refresh), q (back to chat)
- Mouse support (inherited from Toad/Textual)
- Conductor (Claude via ACP) already functional from Toad — no chat UI work needed

## Approach

### Architecture

Toad's `MainScreen` is: `SideBar` (left) + `Conversation` (center) + `Footer`.
The SideBar takes `Panel` objects — any Textual widget wrapped in a collapsible section.

```
MainScreen (from Toad)
├── SideBar
│   ├── Panel: "Plan" (existing Toad widget)
│   ├── Panel: "Project" (existing DirectoryTree)
│   └── Panel: "GitHub" ← NEW — GitHubStateWidget
├── Conversation (chat with conductor via ACP) ← exists
└── Footer ← exists
```

### GitHubStateWidget

A Textual `TabbedContent` widget with 4 tabs, each containing a `DataTable`:

```python
class GitHubStateWidget(Widget):
    def compose(self):
        with TabbedContent("Timeline", "Issues", "Plans", "PRs"):
            yield TimelineView()   # DataTable: recent events
            yield IssuesView()     # DataTable: open issues, grouped by label
            yield PlansView()      # DataTable: plan:* issues with progress
            yield PRsView()        # DataTable: open PRs with review status
```

Each view calls `gh` via `subprocess` with `--json` flags and populates the table.

### Data fetching

Direct `gh` CLI calls from the widget (same as Toad's existing subprocess patterns):
```bash
gh issue list --state open --json number,title,labels,createdAt,updatedAt --limit 50
gh pr list --state open --json number,title,reviewDecision,createdAt,updatedAt --limit 50
gh api repos/{owner}/{repo}/events --jq '.[0:30]'
gh issue list --label "plan:active" --json number,title,body --limit 20
```

### Fork setup

1. Fork `batrachianai/toad` to `DEGAorg/canon-conductor` (or chosen name)
2. Clone, install with `uv`, verify it runs
3. Add custom widget files to `src/toad/widgets/`
4. Mount new panel in `screens/main.py`

## Files to touch

| File | Change |
|------|--------|
| `src/toad/widgets/github_state.py` | New — GitHubStateWidget with 4 tabbed views |
| `src/toad/widgets/github_views/timeline.py` | New — timeline DataTable |
| `src/toad/widgets/github_views/issues.py` | New — issues DataTable grouped by label |
| `src/toad/widgets/github_views/plans.py` | New — plan issues with progress parsing |
| `src/toad/widgets/github_views/prs.py` | New — PRs with review status |
| `src/toad/screens/main.py` | Add GitHub panel to SideBar compose() |
| `src/toad/widgets/github_views/fetch.py` | New — gh CLI wrapper (subprocess + JSON parsing) |

## Risks and open questions

- `gh auth` must be valid — widget should show a clear "not authenticated" message, not crash
- GitHub API rate limits (5000/hr authenticated) — 4 calls per refresh is fine even at 30s intervals
- Parsing progress log from plan issue body is fragile — show "progress: unknown" if format doesn't match
- Toad's CSS (`screens/main.tcss`) may need adjustments for the new panel width
- Upstream Toad changes — decide early whether to track upstream or diverge

## Progress log

- [x] Fork `batrachianai/toad` to DEGAorg/conductor-view, clone, install with uv, verify imports (DONE)
- [x] Install `claude-code-acp` adapter (`npm install -g @zed-industries/claude-code-acp`) and verify Toad launches with Claude at `/Users/cerratoa/dega/conductor-view` (deps: 1)
- [x] Create `/Users/cerratoa/dega/conductor-view/src/toad/widgets/github_views/fetch.py` — gh CLI wrapper: auth check, issue/PR/event fetching, returns parsed JSON (deps: 2)
- [x] Create `/Users/cerratoa/dega/conductor-view/src/toad/widgets/github_views/timeline.py` — timeline DataTable from repo events (deps: 3)
- [x] Create `/Users/cerratoa/dega/conductor-view/src/toad/widgets/github_views/issues.py` — issues DataTable grouped by label (deps: 3)
- [x] Create `/Users/cerratoa/dega/conductor-view/src/toad/widgets/github_views/plans.py` — plan issues with progress from body checkboxes (deps: 3)
- [x] Create `/Users/cerratoa/dega/conductor-view/src/toad/widgets/github_views/prs.py` — PRs DataTable with review decision and CI status (deps: 3)
- [ ] Create `/Users/cerratoa/dega/conductor-view/src/toad/widgets/github_state.py` — GitHubStateWidget wrapping 4 views in TabbedContent (deps: 4, 5, 6, 7)
- [ ] Mount GitHub panel in `/Users/cerratoa/dega/conductor-view/src/toad/screens/main.py` SideBar (deps: 8)
- [ ] Test end-to-end — launch conductor from `/Users/cerratoa/dega/conductor-view`, open GitHub panel, verify all 4 views render (deps: 9)
- [ ] Add keybinding to toggle GitHub panel (ctrl+g or similar) and refresh (r key within panel) (deps: 9)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Fork Toad | Pure Textual, Ink (TypeScript) | Toad gives chat UI + ACP + shell + panels for free. Saves ~2 days. See `docs/decisions/20260320-tui-framework-selection.md` |
| AGPL-3.0 accepted | MIT (Textual only) | Conductor TUI is open source. Monetization is in proprietary repos (Arena, cloud exec, marketplace). AGPL doesn't affect them. |
| Direct gh calls from widget | Shell script intermediary, Octokit | gh handles auth and outputs JSON. Matches Toad's existing subprocess patterns. |
| Add to Toad's SideBar.Panel | New screen, separate app | SideBar.Panel is one line to mount. Keeps everything in the conductor's unified view. |

## Completion criteria

- [ ] Toad fork runs and launches the conductor with Claude via ACP
- [ ] GitHub panel appears in the SideBar with 4 tabs
- [ ] Timeline shows recent repo activity
- [ ] Issues view groups by label and shows plan status
- [ ] Plans view parses progress from issue body (e.g., "3/7 done")
- [ ] PRs view shows review decision and CI status
- [ ] Keybinding toggles the GitHub panel
- [ ] Auth failure shows a clear message, not a crash
- [ ] Works on macOS
