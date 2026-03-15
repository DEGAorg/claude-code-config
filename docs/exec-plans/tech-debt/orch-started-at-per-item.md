# Orch: startedAt not tracked per item

**Discovered:** 2026-03-14
**Severity:** Low

## Problem

Stale worker detection (`orch_detect_stale_workers` in `orch-state.sh`) checks
whether a tmux pane exists for running items. It uses a 30s poll interval as buffer.

A worker that starts and crashes within one poll interval won't be detected as
stale until the next poll cycle. With a 30s interval this is unlikely but possible.

The stale detection plan (`20260313-orch-stale-worker-detection`) explicitly
deferred per-item `startedAt` tracking.

## Proposed fix

Add `startedAt` timestamp to each item when status transitions to `running`.
Stale detection can then use wall-clock time instead of relying on poll interval
cadence. A worker running for >5 minutes with no done-file and a dead pane is
definitively stale regardless of when the last poll happened.

## Files involved

| File | Role |
|------|------|
| `scripts/orch-state.sh` | Add `startedAt` field, update stale detection |
| `scripts/orch-engine.sh` | Set `startedAt` when spawning workers |
