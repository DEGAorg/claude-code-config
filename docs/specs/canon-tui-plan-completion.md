# Canon TUI — Plan Completion Rendering

**Status:** Draft
**Owner:** Alberto
**Repo:** [DEGAorg/canon-tui](https://github.com/DEGAorg/canon-tui)
**Local clone:** `/Users/cerratoa/dega/aidd/canon-tui`

---

## Problem

When the orchestrator finishes a plan, Canon TUI keeps the plan panel in its
last in-progress state. The user sees no terminal status (completed / failed),
no PR link, no rework summary — just a stale snapshot of the last running
item. The TUI updates correctly during the `start` and per-item `review`
phases, but misses the final `ship` / `verify` transitions.

This breaks the user's primary feedback loop: they open Canon TUI to watch a
plan, the agent says "I opened the panel for you," and the panel never
confirms completion. The user has to leave the TUI and check GitHub manually
to know the plan finished.

## Goal

The plan panel must reflect terminal state within seconds of orch reaching
`status: completed` (or `status: failed`), and surface the artifacts the user
needs to act on next:

1. **Terminal status badge** — Completed (SHIP), Failed, or Aborted.
2. **PR link** — clickable URL to the PR opened by the ship phase.
3. **Run summary** — items passed, items reworked, total review iterations,
   wall-clock elapsed.
4. **Verification result** — pass / fail and unchecked-criteria count if
   verification ran.

## Sources of truth

The TUI already reads from `.orchestrator/plans/<slug>/`. The relevant files:

| File | Use |
|------|-----|
| `state.json` | Authoritative status. `status` field transitions to `completed` / `failed` on terminal. `verification` block carries pass/fail. `finalReview` carries SHIP/REVISE result. |
| `posted.json` | Records which lifecycle events have been posted to GitHub. Presence of `ship:plan:<N>` key means the ship phase fired. |
| `heartbeat` | Engine writes a unix timestamp every poll. Stops updating when engine exits. |
| `logs/engine.log` | Free-form engine output. Useful for displaying the last few lines on the panel. |

The TUI does **not** need to call GitHub. The PR URL must be discoverable
locally. Today the ship event in `hooks/orch-lifecycle/01-gh-plan-sync.sh`
posts the PR URL as a comment but does not persist the URL into state. This
spec requires that change (see "Engine-side requirement" below).

## Required behaviour

### Terminal-state detection

The TUI watches `state.json` (existing behaviour). On every change, evaluate:

```python
# pseudocode
if state["status"] in ("completed", "failed"):
    render_terminal(state)
    stop_polling_workers()  # workers are gone; freeze worker list
```

Terminal states observed in real runs:

- `status: completed` + `finalReview.result: SHIP` + `verification.status: passed` → Completed
- `status: completed` + `finalReview.result: SHIP` + `verification.status: failed` → Completed (verify advisory)
- `status: failed` → Failed (engine bailed out, e.g. budget exhausted)
- `status: aborted` → Aborted (user stopped via `orch stop`)

### Display additions

The plan panel currently shows: title, items, per-item status, current
worker. Add to it on terminal state:

```
┌─ Plan: 20260428-pre-release-cleanup ────────────────────────────┐
│ Status: ✅ Completed (SHIP)                                      │
│ PR: #257  https://github.com/DEGAorg/.../pull/257               │
│ Verification: passed (0 unchecked)                              │
│ Items: 7/7 shipped, 0 reworked                                  │
│ Reviews: 7 total iterations                                     │
│ Elapsed: 16m 18s                                                │
│ Issue: #252                                                     │
│                                                                 │
│ [Open PR]  [View Issue]  [Open Reports]                         │
└─────────────────────────────────────────────────────────────────┘
```

Failure variant:

```
│ Status: ❌ Failed                                                │
│ Reason: budget exhausted after 3 review iterations              │
│ Items: 4/7 shipped, 3 stuck in REVISE                           │
│ Last error: see engine.log line 4231                            │
│ [View Logs]  [View Issue]                                       │
```

### Reactivity — root cause hypothesis

Three plausible reasons the panel doesn't refresh on completion today.
Investigate in this order:

1. **File-watcher misses the final write.** The TUI may use a watcher that
   coalesces rapid writes; the engine writes state.json then exits, and the
   final write may be debounced into nothing if the watcher's poll loop
   shuts down with the engine. **Fix:** poll-on-interval at least once after
   detecting heartbeat staleness, regardless of file-watch events.

2. **Heartbeat-driven render loop.** If the TUI re-renders only when
   `heartbeat` updates, and heartbeat stops updating at terminal, the panel
   freezes in last-known state. **Fix:** decouple "should we re-read state"
   from heartbeat. Re-read state on every change OR on a timer that keeps
   running until terminal is observed.

3. **Status field not in render path.** The TUI may render items but not
   the top-level `state.status`. **Fix:** thread `state.status` into the
   plan panel header component.

### Engine-side requirement (cross-repo)

Canon TUI cannot render a PR URL it doesn't have. The orchestrator engine in
`claude-code-config` must persist the PR URL into `state.json` on the ship
event:

```json
{
  "status": "completed",
  "finalReview": { "result": "SHIP", "prUrl": "https://github.com/.../pull/257", "prNumber": 257 },
  ...
}
```

The ship hook (`hooks/orch-lifecycle/01-gh-plan-sync.sh`) already invokes
`scripts/gh-plan-sync.sh ship`, which creates the PR. That script must
return the PR URL to the engine, which writes it into state.json. This work
lives in `claude-code-config` and should land **before** the canon-tui PR
ships, so the TUI can rely on the field.

### Notification mechanism (separate file, complementary)

The Canon TUI does not own the agent-bump mechanism. That is implemented as
a Stop-hook in `claude-code-config` (`hooks/stop/01-orch-notify.sh` —
proposed). The TUI may, optionally, also consume
`.orchestrator/notifications/<slug>.json` to render a one-time toast — but
the primary surface for "plan finished" is the panel header described above.
**Out of scope for this spec.**

## Non-goals

- Re-architecting how the TUI watches `.orchestrator/`.
- Rendering review-comment text inline (already shown in the worker pane).
- Cross-plan dashboard view (existing scope).
- Showing PR diff content inside the TUI.

## Acceptance criteria

- [ ] Plan panel header renders Completed / Failed / Aborted within 5 seconds
      of `state.status` reaching a terminal value.
- [ ] PR URL renders when `state.finalReview.prUrl` is present.
- [ ] Verification block shows pass/fail and unchecked count when
      `state.verification` is present.
- [ ] Run summary line (items shipped / reworked / elapsed) shown on
      terminal.
- [ ] Existing per-item rendering during the run is unchanged.
- [ ] Manual test: run a real plan via `orch-run.sh <slug> --issue N` while
      the TUI is open; observe the panel transition from running → terminal
      with PR URL visible.

## Implementation pointers

Files most likely to change in canon-tui:

- `src/toad/widgets/plan_status_rail.py` — panel header where status badge
  goes
- `src/toad/widgets/orchestrator_state.py` — state.json reader; surfaces the
  status / finalReview fields to widgets
- `src/toad/widgets/plan_execution_section.py` — likely the render gate that
  needs to refresh on terminal
- `src/toad/widgets/plan_execution_tab.py` — top-level orchestration of the
  panel

Don't edit canon-tui from a worktree of `claude-code-config`. Do the canon-tui
work in `/Users/cerratoa/dega/aidd/canon-tui` against its own default branch.

## Sequencing with `claude-code-config`

1. Land `state.finalReview.prUrl` persistence in `claude-code-config`
   (small change in `scripts/gh-plan-sync.sh` ship handler + engine writer).
2. Land Canon TUI panel changes against the new state schema.
3. Smoke-test by running a plan end-to-end with the TUI open.
