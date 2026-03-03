# Plan: Ink Status Dashboard (terminal-ui)

**Status:** In progress
**Created:** 2026-03-03
**Parent:** `docs/research/terminal-ui-action-plan.md` (Plan 2)
**Depends on:** `terminal-ui-state-spec` (Plan 1 — complete: `types.ts`, `write.ts` exist)

## Requirements

- Ink (React/TS) app that watches a state file and renders a read-only status dashboard
- Runs as a CLI: `terminal-ui --state .canon/state.json`
- Renders: phase indicator, status badge (color-coded), log stream, metrics key-value pairs
- Auto-refreshes on file changes (chokidar file watcher)
- Graceful fallback: shows "waiting for state file..." if missing, recovers when file appears
- Handles malformed JSON without crashing (log warning, keep last valid state)
- Small: ~150-200 lines of TSX total across all components
- Builds on existing `scripts/terminal-ui/` package (Plan 1 scaffold)
- Installable globally via `/apply-core` to `~/.claude/scripts/terminal-ui/`

## Approach

### Package updates

Add Ink + React dependencies to the existing `scripts/terminal-ui/package.json`:

| Dependency | Version | Purpose |
|-----------|---------|---------|
| `ink` | 6.8.0 | React renderer for terminal |
| `react` | 18.3.1 | React 18 (Ink 6 requires 18, not 19) |
| `@types/react` | 18.3.23 | TypeScript types for React |
| `chokidar` | 4.0.3 | File watcher |

Update `tsconfig.json`: add `"jsx": "react-jsx"` for automatic JSX transform.
Rename `.ts` files that contain JSX to `.tsx`.

### CLI entry point

`src/cli.tsx` — parses `--state <path>` from `process.argv`, renders `<App>`.
Add `"bin": { "terminal-ui": "./dist/cli.js" }` to `package.json`.
Shebang `#!/usr/bin/env node` at top.

### Component structure

```
src/
├── types.ts          ← existing (Plan 1)
├── write.ts          ← existing (Plan 1)
├── cli.tsx           ← entry point, arg parsing, render()
├── app.tsx           ← main app: file watcher + state management
├── status-bar.tsx    ← phase + status badge (color-coded)
├── log-panel.tsx     ← scrolling log entries
└── metrics-panel.tsx ← key-value pairs from state.metrics
```

### App component (`app.tsx`)

- Uses `chokidar.watch(statePath)` to watch the file
- On change: reads file, parses JSON, updates React state
- On parse error: keeps last valid state, shows warning in log panel
- On file missing: shows "Waiting for state file..." placeholder
- Cleanup: closes watcher on unmount

### Layout

```
┌─────────────────────────────────────┐
│  Phase: scaffold  │  ● RUNNING      │  ← StatusBar
├─────────────────────────────────────┤
│  14:22:15  info  Scaffolding repo   │  ← LogPanel
│  14:22:16  info  Creating src/      │
│  14:22:17  warn  No .env found      │
│  ...                                │
├─────────────────────────────────────┤
│  iteration: 3    elapsed: 2m14s     │  ← MetricsPanel
│  strategy: arb   market: Polymarket │
└─────────────────────────────────────┘
```

- `StatusBar`: single row, phase left-aligned, status badge right-aligned
- `LogPanel`: flexGrow=1 (takes remaining space), shows most recent N entries that fit
- `MetricsPanel`: bottom section, two-column key-value grid

### Status badge colors

| Status | Color |
|--------|-------|
| running | green |
| paused | yellow |
| idle | gray/dim |
| error | red |

## Files to touch

| File | Change |
|------|--------|
| `scripts/terminal-ui/package.json` | Add ink, react, @types/react, chokidar deps; add bin entry |
| `scripts/terminal-ui/tsconfig.json` | Add `"jsx": "react-jsx"` |
| `scripts/terminal-ui/src/cli.tsx` | Create — CLI entry point with arg parsing |
| `scripts/terminal-ui/src/app.tsx` | Create — main app with file watcher and state |
| `scripts/terminal-ui/src/status-bar.tsx` | Create — phase + status badge component |
| `scripts/terminal-ui/src/log-panel.tsx` | Create — scrolling log entries component |
| `scripts/terminal-ui/src/metrics-panel.tsx` | Create — key-value metrics display |

## Risks and open questions

- **P1:** ~~Ink 6 requires React 18. React 19 causes runtime errors.~~ **WRONG.**
  Ink 6.8.0 ships `react-reconciler@0.33.0` which requires React 19
  (`ReactSharedInternals.S` is a React 19 internal). React 18 causes
  `TypeError: Cannot read properties of undefined (reading 'S')`.
  Fixed post-completion: pinned `react@19.1.0`, `@types/react@19.1.8`.
- **P2:** Should `LogPanel` auto-scroll or show most recent entries? → Show most recent
  entries (bottom of ring buffer). No scroll interaction needed — this is read-only.
  The state file already caps at 50 entries via the writer.
- **P2:** Terminal height detection — how many log lines to show? → Use Ink's
  `useStdout()` hook to get terminal rows. Subtract StatusBar (1 row) and
  MetricsPanel (~3 rows) height. Show remaining rows of logs.

## Progress log

- [x] Add Ink, React, chokidar dependencies to package.json and install
- [x] Update tsconfig.json with jsx setting
- [x] Create `src/cli.tsx` — entry point with `--state` arg parsing
- [x] Create `src/app.tsx` — file watcher, state management, layout composition
- [x] Create `src/status-bar.tsx` — phase and status badge
- [x] Create `src/log-panel.tsx` — recent log entries display
- [x] Create `src/metrics-panel.tsx` — key-value metrics grid
- [x] `tsc --noEmit` passes
- [x] Manual test: create a state.json, run `terminal-ui --state state.json`, verify render
- [x] Manual test: update state.json while running, verify live refresh

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| chokidar for file watching | `fs.watch`, `fs.watchFile` | `fs.watch` has platform quirks (double events on macOS). chokidar handles debouncing and cross-platform edge cases. Standard choice. |
| ~~React 18.3.1 pinned~~ React 19.1.0 pinned | React 18 | Ink 6.8.0 uses react-reconciler@0.33.0 which requires React 19 internals. React 18 crashes at startup. Corrected post-completion. |
| No `@inkjs/ui` | Include for spinners/badges | Last published 2 years ago. The components we need (colored text, boxes) are built into `ink` core. No extra dependency needed. |
| Single file watcher in App | Watcher in CLI, pass state as prop | Keeps the watcher lifecycle tied to React (useEffect cleanup). CLI stays thin. |
| Show most recent logs (no scroll) | Scrollable viewport | Read-only dashboard. Scroll adds interaction complexity. 50-entry ring buffer + terminal height is sufficient. |

## Completion criteria

- [x] `tsc --noEmit` passes on the full package
- [x] `terminal-ui --state <path>` renders status bar, logs, and metrics
- [x] Dashboard updates live when state file changes on disk
- [x] Missing state file shows placeholder, recovers when file appears
- [x] Malformed JSON does not crash the app

## Post-completion fixes

**2026-03-03 — smoke test failures**

Two bugs found during first manual smoke test after all plans completed:

1. **React version mismatch.** Ink 6.8.0 ships `react-reconciler@0.33.0` which
   accesses `ReactSharedInternals.S` — a React 19 internal. React 18.3.1 caused
   `TypeError: Cannot read properties of undefined (reading 'S')` at startup.
   Fix: pinned `react@19.1.0` and `@types/react@19.1.8`.

2. **MetricsPanel null crash.** `Object.entries(metrics)` threw when `metrics`
   was undefined (state file with missing or null metrics field).
   Fix: `Object.entries(metrics ?? {})`.
