# Plan: Gantt Timeline Widget — JSON-Driven

**Status:** Completed
**Created:** 2026-03-22
**Completed:** 2026-03-23
**Target repo:** DEGAorg/conductor-view (`conductor` branch)

> **Note:** Executed manually by Claude without the orchestrator. The work
> targeted conductor-view (a separate repo), which the orchestrator cannot
> manage yet due to multi-repo support not being implemented. All items
> were completed in a single interactive session.
**Local path:** `/Users/cerratoa/dega/conductor-view`

## Requirements

- Textual widget at `src/toad/widgets/gantt_timeline.py` that renders a proper Gantt chart
- Reads timeline data from a JSON file (schema matching `data.json` reference)
- Day columns across the top as a date axis
- Task labels on the left, bars positioned proportionally to `startDay` and `days`
- Color-coded bars by category (configurable per-bar `color` field)
- Today marker (vertical indicator on the current date)
- Gate/event markers on the date axis
- Aligned grid — bars sit in correct column positions using block characters
- Standalone-testable via `python -m toad.widgets.gantt_timeline` (follows existing pattern from `plan.py`)
- Reactive: updates when data changes (file reload or programmatic update)

## Approach

Build a single Textual `Static` subclass (`GanttTimeline`) that uses Rich renderables
to compose the chart. The widget computes bar positions as character offsets within a
fixed-width track, then renders using `rich.text.Text` with styled segments.

**Layout (top to bottom):**
1. **Date axis row** — day labels spaced across the track width, with gate/event markers
2. **Bar rows** — one per `ganttBars` entry: `[label (fixed width)] [positioned bar]`
3. **Today marker** — a column highlight or `|` character at the appropriate offset

**Positioning math:**
- `track_width` = widget width minus label column width
- `bar_start` = `int((startDay / totalDays) * track_width)`
- `bar_width` = `max(1, int((days / totalDays) * track_width))`
- Fill with `█` characters, styled with the bar's color

**Color mapping:** Map the JSON `color` field to Rich style names. The reference
data uses: `accent`, `cyan`, `green`, `orange`, `yellow`, `red`. Map these to
terminal-friendly Rich colors.

**Data loading:** Accept either a file path (reads JSON) or a dict (programmatic).
The widget exposes a reactive `timeline_data` property so the parent screen can
update it.

## Files to touch

| File | Change |
|------|--------|
| `src/toad/widgets/gantt_timeline.py` | New — the Gantt widget |
| `tests/test_gantt_timeline.py` | New — widget unit tests |

## Risks and open questions

- **Terminal width:** Narrow terminals compress bars to nothing. Mitigate with `min_bar_width=1` and horizontal scroll if needed.
- **Color theme:** The reference JSON uses `accent` which is theme-dependent. Map to sensible defaults; the parent screen can override via CSS.
- **Integration point:** The split-screen task (not yet done) will mount this widget in the right pane. For now, build standalone with `__main__` block.

## Progress log

- [ ] Create `gantt_timeline.py` with `GanttTimeline` widget class, data models, color mapping, and rendering logic (date axis, bar rows, today marker, gate markers)
- [ ] Add `__main__` standalone runner that loads the reference `data.json` and displays the chart (deps: 1)
- [ ] Write tests in `tests/test_gantt_timeline.py` — bar positioning math, color mapping, empty data, narrow width edge case (deps: 1)
- [ ] Run ruff + ty checks, fix any issues (deps: 2, 3)
- [ ] Visual verification — run standalone, compare against reference HTML layout (deps: 2)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Single `Static` subclass with Rich `Text` rendering | `DataTable` per row, `Canvas` widget | `Text` with styled segments gives pixel-level control over bar positioning without DataTable column overhead. Matches the `plan.py` pattern. |
| Reactive `timeline_data` dict property | File-watcher with `watchdog` | Simpler — the parent screen or orchestrator pushes updates. File watching can be added later if needed. |
| Color string mapping (not CSS classes) | Textual CSS variables | Bars need inline color per-segment. Rich style strings are the natural fit. CSS can still override the container. |
| Standalone `__main__` block | Separate demo app | Follows existing Toad convention (`plan.py` line 152). Zero overhead. |

## Completion criteria

- [ ] `GanttTimeline` widget renders correctly with the reference `data.json`
- [ ] Bar positions are proportional (not left-aligned)
- [ ] Today marker visible at correct position
- [ ] Gate/event markers shown on date axis
- [ ] Colors match the JSON `color` field
- [ ] Tests pass (`pytest tests/test_gantt_timeline.py -q`)
- [ ] Linting clean (`ruff check src/toad/widgets/gantt_timeline.py tests/test_gantt_timeline.py`)

## Notes

**Cross-repo execution:** This plan lives in claude-code-config but targets
conductor-view. Run with `--max-workers 1` to avoid worktree issues:

```bash
bash ~/.claude/scripts/orch-run.sh 20260322-gantt-timeline-widget --max-workers 1
```

The worker agent must `cd /Users/cerratoa/dega/conductor-view` before making
changes. The `dega-core.yaml` check_command should run against that repo.
