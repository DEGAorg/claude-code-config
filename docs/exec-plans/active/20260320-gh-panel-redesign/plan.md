# Plan: Redesign GitHub panel — PM dashboard with status and timeline

**Status:** In progress
**Created:** 2026-03-20

## Requirements

- Replace the current 3-table layout with a PM-style dashboard
- Top section: status overview cards showing counts — Active plans, PR Review, Completed, Failed, Open Issues, Open PRs
- Middle section: plan flow/timeline — chronological view of plan lifecycle events (created, started, reviewed, shipped) with visual indicators
- Bottom section: detail tables (existing Issues/Plans/PRs tabs) but only shown when user drills down from the overview
- Visual status indicators: colored badges/pills for each plan state (draft=gray, active=green, pr-review=blue, completed=purple, failed=red)
- The overview should be the default view, not the raw tables

## Approach

### Layout redesign

```
┌─────────────────────────────────────────┐
│  GitHub Project State          r=refresh│
├─────────────────────────────────────────┤
│  STATUS OVERVIEW                        │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐  │
│  │ 2    │ │ 1    │ │ 4    │ │ 3    │  │
│  │Active│ │Review│ │ Done │ │ PRs  │  │
│  └──────┘ └──────┘ └──────┘ └──────┘  │
├─────────────────────────────────────────┤
│  TIMELINE                               │
│  ● #7 Fix GH panel     plan:pr-review  │
│  ● #6 Review quality   plan:completed  │
│  ● #5 SHIP flow fix    plan:completed  │
│  ● #3 Verify sync      plan:completed  │
│  ● #2 Auto-issue test  plan:completed  │
├─────────────────────────────────────────┤
│  Tab: [Issues] [Plans] [PRs]   detail  │
│  (expandable detail tables below)       │
└─────────────────────────────────────────┘
```

### Textual widgets

- **Status cards**: Custom `Static` widgets with Rich markup for colored counts
- **Timeline**: `ListView` or `DataTable` with Rich Text cells showing colored labels
- **Detail tabs**: Keep existing `TabbedContent` with DataTables, but collapsed by default

## Files to touch

| File | Change |
|------|--------|
| `/Users/cerratoa/dega/conductor-view/src/toad/widgets/github_state.py` | Rewrite — new layout with status overview, timeline, collapsible detail tabs |
| `/Users/cerratoa/dega/conductor-view/src/toad/widgets/github_views/status_overview.py` | New — status cards widget showing plan counts by state |
| `/Users/cerratoa/dega/conductor-view/src/toad/widgets/github_views/timeline.py` | Rewrite — chronological event list with colored plan labels |
| `/Users/cerratoa/dega/conductor-view/src/toad/widgets/github_views/fetch.py` | Add `fetch_all_plan_issues` to get issues across all plan:* labels for status counts |

## Progress log

- [x] Add `fetch_all_plan_issues` to `fetch.py` — fetch issues across all plan:* labels (draft, active, pr-review, completed, failed) for status counts
- [ ] Create `status_overview.py` — status cards widget: colored count boxes for each plan state, plus open issues and PRs counts (deps: 1)
- [ ] Rewrite `timeline.py` — chronological list of plan lifecycle events with colored label badges (plan:active=green, plan:pr-review=blue, plan:completed=purple, plan:failed=red) (deps: 1)
- [ ] Rewrite `github_state.py` — new layout: status overview on top, timeline in middle, detail tabs collapsed at bottom (deps: 2, 3)
- [ ] Test: open GitHub panel, verify status cards show correct counts, timeline shows recent plan events with colors, detail tabs expand on click (deps: 4)

## Completion criteria

- [ ] Status overview shows count cards for Active, PR Review, Completed, Failed, Open Issues, Open PRs
- [ ] Timeline shows chronological plan events with colored state badges
- [ ] Detail tables are collapsed by default, expandable
- [ ] Status counts match actual GitHub issue label counts
- [ ] Looks like a PM dashboard, not a raw data dump
