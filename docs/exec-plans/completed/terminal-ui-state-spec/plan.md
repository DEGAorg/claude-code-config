# Plan: Terminal UI State File Spec

**Status:** In progress
**Created:** 2026-03-03
**Parent:** `docs/research/terminal-ui-action-plan.md` (Plan 1)

## Requirements

- Define a JSON schema for the terminal-ui blackboard state file
- TypeScript interface is the source of truth (`scripts/terminal-ui/src/types.ts`)
- Generic base shape that Canon and Ralph Loop extend without modifying Core
- Timestamps use ISO 8601 (consistent with `.ralph-state.json`, structured logs, log-server events)
- Log entries align with existing structured logging format (ts + level + msg)
- Extensible `metrics` object for domain-specific data
- Schema must be readable by the Ink dashboard, writable by any automation (shell, TS, Python)
- File path is caller-defined (e.g., `.canon/state.json`, `.ralph-state-ui.json`)

## Approach

Scaffold `scripts/terminal-ui/` as a minimal TS package. Define the state interface
first — this unblocks Plan 2 (Ink app) and Plan 4 (`/canon-start`) in parallel.

The state file is a single JSON file on disk. No socket, no server — the Ink app
watches it with `chokidar` (or `fs.watch`). Writers do atomic writes (write to
temp file, rename) to avoid partial reads.

### Schema design

**Base fields** (required, Core-owned):

| Field | Type | Description |
|-------|------|-------------|
| `phase` | string | Current pipeline phase (e.g., "init", "scaffold", "run") |
| `status` | enum | `running` \| `paused` \| `idle` \| `error` |
| `startedAt` | string (ISO 8601) | When the session started |
| `updatedAt` | string (ISO 8601) | Last state write timestamp |
| `logs` | array | Recent log entries (ring buffer, max 50) |
| `error` | string \| null | Error message if status is "error" |

**Log entry shape** (aligns with existing `log-server.py` events):

| Field | Type | Description |
|-------|------|-------------|
| `ts` | string (ISO 8601) | Entry timestamp |
| `level` | enum | `info` \| `warn` \| `error` \| `debug` |
| `msg` | string | Human-readable message |

**Extension point** — `metrics` object:

Any automation can add domain-specific key-value pairs. The Ink dashboard renders
all keys it finds. No schema enforcement on `metrics` — it's `Record<string, unknown>`.

Canon adds: `strategyName`, `market`, `iteration`, `balance`, `positions`
Ralph Loop adds: `iteration`, `maxIterations`, `decision`, `stagnationCount`

### Writer helpers

A shell function (`scripts/terminal-ui-write.sh`) and a TS utility
(`scripts/terminal-ui/src/write.ts`) for atomic state writes. Both:
- Read existing state (or create default)
- Merge updates (partial writes — only send changed fields)
- Atomic rename (`mv tmp state.json`)
- Append to `logs[]` ring buffer (cap at 50 entries)

## Files to touch

| File | Change |
|------|--------|
| `scripts/terminal-ui/package.json` | Create — minimal TS package (name, dependencies) |
| `scripts/terminal-ui/tsconfig.json` | Create — strict TS config per project standards |
| `scripts/terminal-ui/src/types.ts` | Create — state interface (source of truth) |
| `scripts/terminal-ui/src/write.ts` | Create — atomic state writer utility |
| `scripts/terminal-ui-write.sh` | Create — shell helper for state writes |

## Risks and open questions

- **P2:** Should `logs[]` cap be configurable or hardcoded at 50? → Hardcode at 50.
  The Ink dashboard viewport is small; 50 entries is plenty. Configurable adds
  complexity for zero benefit right now.
- **P2:** Should the shell writer depend on `jq`? → Yes. It's already a dependency
  for `statusline.sh` and `ralph-loop.sh`. No new requirement.

## Progress log

- [x] Create `scripts/terminal-ui/` package scaffold (package.json, tsconfig.json)
- [x] Define TypeScript state interface in `src/types.ts`
- [x] Write atomic state writer in `src/write.ts` with log ring buffer
- [x] Write shell helper `scripts/terminal-ui-write.sh` for bash callers
- [x] Verify shell writer produces valid JSON that TS interface accepts

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Single JSON file on disk | Unix socket, shared memory, SQLite | Simplest. File watch is reliable. Any language can read/write JSON. Aligns with `.ralph-state.json` pattern. |
| Atomic rename for writes | Direct write, flock | Atomic rename is safe across platforms, no partial reads, no lock contention. Standard pattern. |
| `metrics` as `Record<string, unknown>` | Typed union of Canon/Ralph/etc shapes | Keeps Core generic. Domain layers define their own keys. Dashboard renders whatever it finds. |
| ISO 8601 timestamps | Unix epoch, locale strings | Consistent with `.ralph-state.json`, `log-server.py`, `structured-log.sh`. Human-readable. |
| Ring buffer logs (max 50) | Unbounded array, external log file | Prevents file growth. Dashboard only shows recent entries. Full logs live in `~/.claude/logs/`. |
| jq for shell writer | Pure bash JSON, Python one-liner | Already a project dependency. Handles merges and array manipulation correctly. |

## Completion criteria

- [x] `scripts/terminal-ui/src/types.ts` exists with exported interfaces
- [x] `scripts/terminal-ui/src/write.ts` compiles and exports `writeState()` function
- [x] `scripts/terminal-ui-write.sh` passes shellcheck
- [x] Shell writer output is valid JSON matching the TS interface
- [x] `tsc --noEmit` passes on the terminal-ui package
