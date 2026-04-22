# Orchestrator Event Stream Schema

Reference for the append-only event stream the orchestrator emits at
`.orchestrator/plans/${SLUG}/events.jsonl`. Each line is a standalone JSON
object. Consumers (the Canon TUI, dashboards, smoke tests, humans tailing
the file) read this stream to observe plan execution in real time without
parsing raw logs or polling `state.json`.

This document is the contract. The emitter (`harness::emit_event` in
`scripts/harness/local.sh`) and every call site
(`scripts/orch-run.sh`, `scripts/orch-engine.sh`, `scripts/orch-review.sh`)
must match what is documented here. See `state-layout.md` for where
`events.jsonl` sits on disk and how it relates to `state.json`.

---

## File format

- **Path.** `.orchestrator/plans/${SLUG}/events.jsonl`
- **Encoding.** UTF-8, LF line endings.
- **Line format.** One JSON object per line, no trailing comma, no
  surrounding array. Produced by `jq -cn` so all string fields are
  correctly escaped.
- **Write mode.** Append-only (`>>`). Lines are never rewritten, reordered,
  or deleted while the plan is active. GC may remove the entire file on
  plan cleanup; individual lines are never edited.
- **Atomicity.** Each `harness::emit_event` call writes one line with a
  single `>>` append. Lines are under `PIPE_BUF` (4 KiB on macOS/Linux),
  so POSIX guarantees the append is atomic against other appenders.

---

## Common fields

Every event has these two fields. Any extra fields are event-specific and
listed per event below.

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `ts` | string | ✅ | ISO-8601 UTC timestamp with millisecond precision, e.g. `2026-04-22T14:03:12.481Z`. If the platform cannot produce ms precision, the emitter pads with `.000Z` — the field format is always `YYYY-MM-DDTHH:MM:SS.sssZ`. |
| `evt` | string | ✅ | Event type. One of the values enumerated below. |

Additional ambient fields the emitter may include on every event when
available (not required by consumers, but documented for completeness):

| Field | Type | Description |
|-------|------|-------------|
| `slug` | string | Plan slug, e.g. `20260422-orch-events`. Redundant with the file path but useful when events are tailed through a pipeline. |

Consumers MUST ignore unknown fields. The schema is additive — new
optional fields may be added without a version bump.

---

## Event types

The stream contains exactly six event types. Each section below lists
the required and optional fields, typical timing, and what it means.

### `plan_start`

Emitted once at the beginning of a plan run, after `state.json` has been
initialized but before any worker is spawned.

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `ts` | string | ✅ | See common fields. |
| `evt` | string | ✅ | Literal `"plan_start"`. |
| `slug` | string | ✅ | Plan slug. |
| `issue` | number | ⚪ | GitHub issue number if the plan is linked to one. |
| `total_items` | number | ✅ | Number of items in the Progress log. |
| `max_parallel_workers` | number | ✅ | Configured parallelism cap. |
| `mode` | string | ⚪ | `"foreground"` or `"background"`. |

**Writer.** `scripts/orch-run.sh`.

### `item_spawn`

Emitted when the engine spawns a worker for an item — i.e. immediately
after `orch_update_item_status "${SLUG}" "${item_id}" "running"` and the
background harness call for the worker returns. Emitted at most once per
item per iteration; a rework iteration emits a fresh `item_spawn`.

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `ts` | string | ✅ | See common fields. |
| `evt` | string | ✅ | Literal `"item_spawn"`. |
| `slug` | string | ✅ | Plan slug. |
| `item` | number | ✅ | Item ID (1-indexed, matches `plan.md` and `state.json`). |
| `iteration` | number | ✅ | Worker iteration counter (`1` on first run, incremented on rework). |
| `pid` | number | ⚪ | Worker process PID. Present when the harness returns a PID; omitted for dry-run modes. |
| `log_path` | string | ⚪ | Absolute path to the worker's log file. |
| `worktree` | string | ⚪ | Repo-relative worktree path. |

**Writer.** `scripts/orch-engine.sh` (`spawn_worker`).

### `item_status`

Emitted whenever the engine observes an item's `status` field transition
in `state.json`. The engine diffs its in-memory last-known status map
against the state after each `orch_sync_done_files` sync; every changed
item produces exactly one `item_status` event carrying both the previous
and the new status.

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `ts` | string | ✅ | See common fields. |
| `evt` | string | ✅ | Literal `"item_status"`. |
| `slug` | string | ✅ | Plan slug. |
| `item` | number | ✅ | Item ID. |
| `from` | string | ✅ | Previous status. Valid values: `queued`, `ready`, `running`, `verifying`, `done`, `failed`, `review-skipped`. The first-ever transition for an item uses `queued` as `from`. |
| `to` | string | ✅ | New status. Same value set as `from`. |
| `iteration` | number | ✅ | Iteration counter at the moment of transition. |
| `reason` | string | ⚪ | Short reason tag. Examples: `"deps-satisfied"` (for `queued → ready`), `"worker-exit"` (for `running → done`), `"review-max-retries"` (for forced `failed`). |
| `review_status` | string | ⚪ | Reviewer verdict when the transition is review-driven: `SHIP`, `REVISE`, `BLOCKED`. |

**Writer.** `scripts/orch-engine.sh` (main loop, after
`orch_sync_done_files`). The engine is the single source of truth for
status transitions — the reviewer does not emit `item_status` directly;
reviewer-driven transitions are observed by the engine on the next poll.

### `review_start`

Emitted when the reviewer is spawned for a specific item. The reviewer
writes its output to `reviews/item-${N}-review.txt`; this event fires
before that file is created.

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `ts` | string | ✅ | See common fields. |
| `evt` | string | ✅ | Literal `"review_start"`. |
| `slug` | string | ✅ | Plan slug. |
| `item` | number | ✅ | Item ID under review. |
| `iteration` | number | ✅ | Review iteration counter (matches the worker's iteration that produced the done-file). |
| `pid` | number | ⚪ | Reviewer process PID. |
| `log_path` | string | ⚪ | Absolute path to the reviewer's log file. |

**Writer.** `scripts/orch-review.sh`.

### `review_end`

Emitted when the reviewer exits and its verdict file has been read. The
verdict is the first non-empty line of `reviews/item-${N}-review.txt`.

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `ts` | string | ✅ | See common fields. |
| `evt` | string | ✅ | Literal `"review_end"`. |
| `slug` | string | ✅ | Plan slug. |
| `item` | number | ✅ | Item ID that was reviewed. |
| `iteration` | number | ✅ | Review iteration counter. |
| `verdict` | string | ✅ | One of `SHIP`, `REVISE`, `BLOCKED`. |
| `duration_ms` | number | ⚪ | Wall-clock duration of the review in milliseconds, if the emitter can compute it. |

**Writer.** `scripts/orch-review.sh`.

### `plan_end`

Emitted exactly once at plan termination. Fires on normal completion
(all items SHIP), on hard failure (an item exhausts `maxIterations` or
the engine aborts), and on cancellation. In background mode the event
is emitted both when `orch-run.sh` returns control to the caller AND
when the engine itself completes — consumers MUST tolerate two
`plan_end` events in the stream and use the last one as authoritative.

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `ts` | string | ✅ | See common fields. |
| `evt` | string | ✅ | Literal `"plan_end"`. |
| `slug` | string | ✅ | Plan slug. |
| `status` | string | ✅ | Terminal status: `completed`, `failed`, `cancelled`. |
| `total_items` | number | ✅ | Total items in the plan. |
| `done_items` | number | ✅ | Count of items that finished in `done` with a SHIP verdict. |
| `failed_items` | number | ✅ | Count of items in `failed`. |
| `duration_ms` | number | ⚪ | Wall-clock duration since `plan_start`. |

**Writer.** `scripts/orch-run.sh`.

---

## Ordering invariants

Consumers may rely on the following causal ordering within a single
`events.jsonl` file. Timestamps are monotonically non-decreasing but not
strictly monotonic — two events may share a `ts` value when emitted in
the same millisecond. Ordering below is by **stream position (line
number)**, not by `ts`.

1. **`plan_start` is the first event.** No other event precedes it in
   the file. If the file exists but is empty, the plan has not started
   emitting yet.
2. **`plan_end` is the last event.** Once it appears, no further events
   are appended in the same plan lifecycle. (See the `plan_end`
   duplication note above: in background mode two `plan_end` lines may
   appear; the second is authoritative and is still the final line.)
3. **`item_spawn` precedes every event referencing that item.**
   Specifically: no `item_status`, `review_start`, or `review_end` with
   `"item": N` appears before the `item_spawn` with `"item": N` for the
   same `iteration`.
4. **`review_start` precedes its matching `review_end`.** Pairs are
   matched by `(item, iteration)`. A `review_end` without a preceding
   `review_start` is a protocol violation.
5. **`item_status` transitions are consistent.** For item `N`, the
   sequence of `(from, to)` pairs forms a valid chain: the `to` of
   event `k` equals the `from` of event `k+1` (same item). The first
   event's `from` is `queued`.
6. **Iteration monotonicity.** For any given item, `iteration` values
   across `item_spawn` / `item_status` / `review_start` / `review_end`
   are non-decreasing. Rework bumps the counter.
7. **Additive, not authoritative.** `state.json` remains the source of
   truth for status. A missing or malformed `events.jsonl` line does
   not imply the state machine is broken — only that an observer lost
   an update.

---

## Example sequence

Minimal example for a one-item plan that passes review on the first
attempt. Line breaks added for readability; real events are one per
line.

```jsonl
{"ts":"2026-04-22T14:03:12.481Z","evt":"plan_start","slug":"20260422-orch-events","total_items":1,"max_parallel_workers":4,"mode":"foreground"}
{"ts":"2026-04-22T14:03:12.502Z","evt":"item_status","slug":"20260422-orch-events","item":1,"from":"queued","to":"ready","iteration":1,"reason":"deps-satisfied"}
{"ts":"2026-04-22T14:03:12.611Z","evt":"item_spawn","slug":"20260422-orch-events","item":1,"iteration":1,"pid":48213,"log_path":"/…/logs/worker-1.log"}
{"ts":"2026-04-22T14:03:12.612Z","evt":"item_status","slug":"20260422-orch-events","item":1,"from":"ready","to":"running","iteration":1}
{"ts":"2026-04-22T14:04:48.193Z","evt":"item_status","slug":"20260422-orch-events","item":1,"from":"running","to":"done","iteration":1,"reason":"worker-exit"}
{"ts":"2026-04-22T14:04:48.240Z","evt":"review_start","slug":"20260422-orch-events","item":1,"iteration":1,"pid":48577}
{"ts":"2026-04-22T14:05:02.911Z","evt":"review_end","slug":"20260422-orch-events","item":1,"iteration":1,"verdict":"SHIP","duration_ms":14671}
{"ts":"2026-04-22T14:05:03.044Z","evt":"plan_end","slug":"20260422-orch-events","status":"completed","total_items":1,"done_items":1,"failed_items":0,"duration_ms":110563}
```

---

## Versioning

The schema is currently unversioned — it is v1 by convention. Additive
changes (new optional fields, new event types) do not require a version
bump. A breaking change (renaming a field, removing an event, tightening
a required field) will bump a `schema_version` field on `plan_start` and
be documented here. Consumers are expected to be permissive about
unknown fields and unknown `evt` values (log and skip, do not crash).
