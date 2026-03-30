# Toad TUI: Canon Sections Spec

Companion spec for conductor-view. Defines what the Toad TUI needs to
support the Canon demo — reading `.canon/state.json` and rendering two
new sections: **Builder** and **Automation**.

## Background

Canon writes all state to a single JSON file: `.canon/state.json`.
This is NOT the orchestrator format (no `master.json`, no per-plan
`state.json`). The canon state file is a flat blackboard:

```json
{
  "phase": "develop",
  "status": "running",
  "startedAt": "2026-03-30T14:00:00Z",
  "updatedAt": "2026-03-30T14:05:12Z",
  "logs": [
    { "ts": "2026-03-30T14:05:12Z", "level": "info", "msg": "Ralph Loop iteration 3" }
  ],
  "error": null,
  "metrics": {
    "iteration": 3,
    "cycles": 0,
    "signals": 0,
    "errors": 0
  }
}
```

### Phase lifecycle

| Phase      | Meaning                                  |
|------------|------------------------------------------|
| `init`     | Canon bootstrapping, waiting for start   |
| `scaffold` | Fetching agents/skills, generating files |
| `strategy` | User selecting or designing strategy     |
| `develop`  | Ralph Loop building the code             |
| `run`      | Automation running                       |

### Status values

`idle`, `running`, `executing`, `paused`, `error`, `complete`

## Requirements

### 1. CanonStateWidget (data layer)

A new widget analogous to `OrchestratorStateWidget` that:

- Watches `.canon/state.json` using the existing directory watcher
- Parses the canon state format into typed dataclass(es)
- Exposes reactive properties: `phase`, `status`, `metrics`, `logs`
- Posts messages when state changes: `CanonStateUpdated`
- Poll fallback (5s) if watcher misses events

Location: `src/toad/widgets/canon_state.py`

### 2. Builder section

A new section in ProjectStatePane that renders during build phases.

**When visible:** `phase ∈ {init, scaffold, strategy, develop}`
(auto-show when canon state detected and phase is a build phase)

**What it shows:**

- **Phase indicator** — current phase name with status badge
  - init: gray, scaffold: blue, strategy: yellow, develop: green
- **Progress** — if `metrics.iteration` exists, show "Iteration N"
- **Logs** — scrollable list of recent log entries (from `logs` array),
  color-coded by level (info=default, warn=yellow, error=red)
- **Error banner** — if `status = error`, show `error` field prominently

**Tab name:** "Builder"

Location: `src/toad/widgets/builder_view.py`

### 3. Automation section

A new section in ProjectStatePane that renders during run phase.

**When visible:** `phase = run`
(auto-show when phase transitions to run)

**What it shows:**

- **Status badge** — executing / paused / error / complete
- **Metrics grid** — render all keys from `metrics` as key-value pairs:
  - `cycles: 15`
  - `signals: 3`
  - `errors: 1`
  - Any other keys the runner adds
- **Logs** — same scrollable log view as Builder, but filtered to
  run-phase entries (or just show the most recent N)
- **Error banner** — same as Builder

**Tab name:** "Automation"

Location: `src/toad/widgets/automation_view.py`

### 4. Section registration in ProjectStatePane

Add two new entries to `SECTIONS` in `project_state_pane.py`:

```python
SECTIONS = {
    "section-github": ...,       # existing
    "section-orchestrator": ..., # existing
    "section-builder": SectionDef(
        label="BUILDER",
        tabs=[TabDef("tab-builder", "Builder", BuilderView)],
    ),
    "section-automations": SectionDef(
        label="AUTOMATION",
        tabs=[TabDef("tab-automation", "Automation", AutomationView)],
    ),
}
```

### 5. Auto-show logic

When `CanonStateWidget` detects a `.canon/state.json`:

- If `phase ∈ {init, scaffold, strategy, develop}`:
  show section-builder, hide section-automations
- If `phase = run`:
  show section-automations, hide section-builder
- If `phase = run` and user manually opened Builder: keep both visible

This can be driven by the same ACP message pattern used for orchestrator
sections, or by direct reactive watch on `CanonStateWidget.phase`.

### 6. CLI flag for project path

Toad needs to know the project directory to find `.canon/state.json`.

Option A: `toad --project /path/to/project`
Option B: Toad auto-detects from CWD (simpler, may already work)

If CWD detection works, no flag needed. `canon.sh` would just
`cd` to the project dir before launching Toad. Confirm which approach
fits better with existing Toad CLI patterns.

## Non-goals

- No changes to the orchestrator section — it stays as-is
- No changes to GitHub section
- Canon state widget does NOT replace OrchestratorStateWidget — they
  coexist. A project can have both `.orchestrator/` and `.canon/`
- No new network calls — everything is local file watching

## Testing

1. Create a mock `.canon/state.json` with phase=develop, some logs
   and metrics. Launch Toad. Builder section should auto-appear.
2. Update the file to phase=run. Automation section should auto-appear,
   Builder should hide.
3. Set status=error with an error message. Error banner should render.
4. Delete `.canon/state.json`. Sections should gracefully hide.

## File inventory

| New file | Purpose |
|----------|---------|
| `src/toad/widgets/canon_state.py` | State watcher + data model |
| `src/toad/widgets/builder_view.py` | Builder section widget |
| `src/toad/widgets/automation_view.py` | Automation section widget |

| Modified file | Change |
|---------------|--------|
| `src/toad/widgets/project_state_pane.py` | Register builder + automation sections |
| `src/toad/screens/main.py` | Mount CanonStateWidget, wire auto-show |
