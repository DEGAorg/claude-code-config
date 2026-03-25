# Plan: Orchestrator Visual Demo

**Status:** In progress
**Created:** 2026-03-14

## Requirements

This is a simulation plan to visualize the orchestrator running 10 tasks
across 4 waves with max 4 concurrency. No real development — each task
creates a small file and writes its done-file.

## Approach

Each worker should:
1. Sleep for 30 seconds (simulating work)
2. Create a file at `/tmp/orch-demo/task-<ID>.txt` with content describing the task
3. Mark the checkbox in this plan
4. Write the done-file
5. Stop

## Files to touch

| File | Change |
|------|--------|
| `/tmp/orch-demo/task-*.txt` | Simulated output files |

## Progress log

- [x] Set up demo output directory at /tmp/orch-demo and create task-1.txt with "Wave 1 — no dependencies". (deps: none)
- [x] Create /tmp/orch-demo/task-2.txt with "Wave 1 — no dependencies". (deps: none)
- [x] Create /tmp/orch-demo/task-3.txt with "Wave 1 — no dependencies". (deps: none)
- [x] Create /tmp/orch-demo/task-4.txt with "Wave 1 — no dependencies". (deps: none)
- [x] Create /tmp/orch-demo/task-5.txt with "Wave 2 — depends on 1 and 2". (deps: 1, 2)
- [x] Create /tmp/orch-demo/task-6.txt with "Wave 2 — depends on 3". (deps: 3)
- [x] Create /tmp/orch-demo/task-7.txt with "Wave 2 — depends on 4". (deps: 4)
- [x] Create /tmp/orch-demo/task-8.txt with "Wave 3 — depends on 5 and 6". (deps: 5, 6)
- [x] Create /tmp/orch-demo/task-9.txt with "Wave 3 — depends on 7". (deps: 7)
- [x] Create /tmp/orch-demo/task-10.txt with "Wave 4 — final task, depends on 8 and 9". (deps: 8, 9)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| 30s sleep per task | Instant completion | Need enough time to observe the dashboard and worker windows |
| 4 waves with varied deps | Flat parallelism | Demonstrates dependency scheduling visually |

## Completion criteria

- [ ] All 10 files exist in /tmp/orch-demo/
- [ ] Dashboard showed wave progression: 4 -> 3 -> 2 -> 1
