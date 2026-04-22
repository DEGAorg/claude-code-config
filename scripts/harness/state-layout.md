# Orchestrator State Layout

Reference for every on-disk artifact the orchestrator reads or writes under
`.orchestrator/`. Each entry lists **what** the file is, **when** it is
written, **who writes it**, **who reads it**, and the **invariants** that
consumers may rely on.

Path conventions:

- `${ROOT}` — repo root (containing `.orchestrator/`)
- `${SLUG}` — plan slug, e.g. `20260422-orch-events`
- `${N}` — numeric item ID from `plan.md` / `state.json`

---

## Top-level registry

### `.orchestrator/master.json`

- **What.** JSON registry of every plan the orchestrator has started on this
  machine. Top-level shape: `{"version": 1, "plans": [...], "updatedAt": "<iso8601>"}`.
  Each plan entry: `{slug, status, statePath, worktree, startedAt, updatedAt,
  tmuxSession?, progress: {total, done, running, failed}}`.
- **When written.**
  - On plan start, via `orch_master_register` (`scripts/orch-state.sh`).
  - On every engine poll, via `orch_master_update_progress`.
  - On plan end, via `orch_master_deregister` (status → `completed` |
    `failed` | `cancelled`).
- **Writer.** `scripts/orch-state.sh` functions
  (`orch_write_master`, `orch_master_register`, `orch_master_deregister`,
  `orch_master_update_progress`). Writes are atomic: `jq` produces output
  into a tempfile, then `mv` into place.
- **Readers.** `scripts/orch-run.sh` (duplicate-start guard),
  `scripts/orch-gc.sh` (stale-plan sweep), Canon TUI / terminal-ui
  (`scripts/terminal-ui/src/*`) for dashboard rendering.
- **Invariants.**
  - Single writer at any instant — callers serialize via tempfile + `mv`.
  - Slugs are unique: registration removes any prior entry with the same
    slug before appending.
  - `statePath` and `worktree` are repo-relative, not absolute.
  - `progress` counts sum to `≤ total`; `running` ≤ configured
    `maxParallelWorkers`.
  - Never committed to git — `.orchestrator/` is ignored.

---

## Per-plan directory: `.orchestrator/plans/${SLUG}/`

Created when the plan is started; removed only by explicit `orch-gc.sh`
cleanup. All paths below are relative to this directory.

### `plan.md`

- **What.** The canonical execution plan. Progress log checkboxes track
  per-item status; workers flip `[ ]` → `[x]` when finished.
- **When written.**
  - At plan start: copied / materialized from
    `docs/exec-plans/active/${SLUG}/plan.md` (or fetched from the GitHub
    issue body via `scripts/gh-plan-fetch.sh`).
  - During execution: workers edit their own checkbox line in step 3 of
    the worker contract.
- **Writer.** `scripts/orch-run.sh` (initial copy), worker agents
  (per-item checkbox flip).
- **Readers.** `scripts/orch-parse-items.sh` (initial item extraction),
  workers (pre-hydrated context fallback), reviewers, humans.
- **Invariants.**
  - Item IDs in the Progress log match `state.json[].items[].id`
    1-for-1 and 1-indexed.
  - Only the checkbox character changes during execution — body text,
    dep annotations, and ordering are immutable once the plan has started.

### `state.json`

- **What.** Authoritative per-plan state. Shape:
  `{version, plan, issueNumber, maxParallelWorkers, mode, items: [...]}`.
  Each item: `{id, description, deps, status, workerPid, logPath,
  worktree, iteration, maxIterations, lastResult, reviewStatus}`.
- **When written.**
  - Plan start: `orch-run.sh` synthesizes from parsed `plan.md`.
  - Every engine tick: `orch-engine.sh` transitions item status
    (`queued → ready → running → done | failed | review-skipped`).
  - Reviewer transitions: `orch-review.sh` sets `reviewStatus` and
    `lastResult`.
- **Writer.** `scripts/orch-state.sh` (`orch_write_state`) — atomic
  tempfile + `mv`. Only the engine and reviewer call the write path.
- **Readers.** Engine (next-ready selection), reviewer, GC, TUI,
  `orch-state.sh` helpers, `orch-verify.sh`.
- **Invariants.**
  - Exactly one writer at a time (engine and reviewer run serialized
    against this file).
  - `items[*].id` is dense, 1-indexed, matches `plan.md`.
  - `deps` reference valid earlier item IDs.
  - `status` transitions are monotonic per iteration: an item never
    moves from `done` back to `running` within the same `iteration`
    counter; rework bumps `iteration` first.
  - `workerPid` / `logPath` / `worktree` are cleared when the item
    leaves `running`.

### `heartbeat`

- **What.** Plain text file containing the engine's most recent poll
  epoch (seconds).
- **When written.** Every engine poll iteration (`write_heartbeat` is
  called at the top of each loop and at most transition points in
  `scripts/orch-engine.sh`).
- **Writer.** `scripts/orch-engine.sh`.
- **Readers.** `scripts/orch-gc.sh` (declares the engine stale if the
  heartbeat is older than 10 minutes).
- **Invariants.**
  - Contents match `^[0-9]+$`. A non-matching file is treated as
    malformed and the plan is swept by GC.
  - Monotonically non-decreasing while the engine is healthy.

### `pids/`

Per-process metadata used for liveness checks and stale-process cleanup.

- **Files.**
  - `engine-${SLUG}.pid` — engine daemon PID.
  - `engine-${SLUG}.started_at` — engine start epoch.
  - `worker-${N}.pid` / `worker-${N}.started` — active worker PID and
    start epoch for item `N`.
  - `reviewer-${N}.pid` / `reviewer-${N}.started` — active reviewer PID
    and start epoch for item `N`.
  - `verifier-${ROLE}-${ID}.pid` — per the `scripts/harness/contract.md`
    convention (`<role>-<id>.pid` under `pid_dir`).
- **When written.** On spawn (`scripts/harness/local.sh` `run_background`
  writes `${pid_dir}/${role}-${id}.pid`). `.started` / `.started_at`
  sidecars are written by the spawning script.
- **Writer.** `scripts/harness/local.sh` (PID file), engine / run /
  review / verify scripts (sidecar timestamps, removal on exit).
- **Readers.** Engine and reviewer (liveness checks via `kill -0`),
  `harness::list_active`, `orch-gc.sh`, `orch-run.sh` duplicate-start
  guard.
- **Invariants.**
  - PID files contain a single integer PID, no trailing whitespace
    beyond the newline written by `printf '%s\n'`.
  - Removed when the owning process exits cleanly. A stale PID file
    whose PID is not alive is safe for GC to delete.
  - File names follow `<role>-<id>.pid` so `list_active` can enumerate
    by glob.

### `logs/`

- **Files.**
  - `engine.log` — stdout/stderr of the engine daemon, appended across
    the plan's lifetime.
  - `worker-${N}.log` — combined stdout/stderr of the worker agent for
    item `N`.
  - `reviewer-${N}.log` — combined stdout/stderr of the reviewer agent
    for item `N` (one file per review attempt; overwritten on rework).
- **When written.** Continuously while the owning process runs. The
  engine log is `tee`-appended by `orch-run.sh` / `orch-engine.sh`;
  worker and reviewer logs are the redirected output of the spawned
  harness command.
- **Writer.** Engine process (`engine.log`), worker processes
  (`worker-*.log`), reviewer processes (`reviewer-*.log`).
- **Readers.** Humans, `orch-engine.sh` error reporting, reviewer
  prompts (worker log is the primary evidence of worker behavior), TUI.
- **Invariants.**
  - Raw logs are append-only from the perspective of any single owning
    process — not rotated by the orchestrator. The new `events.jsonl`
    (see below) is additive and does not replace these logs.
  - Paths referenced by `state.json[].items[].logPath` are absolute.

### `done/`

- **Files.** `item-${N}.txt` per completed item.
- **What.** Worker-authored summary of the item's work: clause
  checklist, file:line references, and a 3-5 sentence summary.
- **When written.** At the end of the worker's execution, before the
  worker exits (step 5 of the worker contract). On rework iterations
  the worker overwrites the existing file.
- **Writer.** Worker agent (via `Write` tool inside the harness).
- **Readers.** Reviewer (primary evidence), engine (presence → mark
  item `done` pending review), downstream workers (completed
  dependency summaries injected into their prompts).
- **Invariants.**
  - One file per item ID. Presence of `item-${N}.txt` means the worker
    self-reported completion; it does not imply the reviewer has passed
    the item.
  - Overwritten, not appended, on rework — the latest file reflects the
    latest iteration.

### `reviews/`

- **Files.** `item-${N}-review.txt` per reviewed item.
- **What.** Reviewer-authored verdict for item `N`. First line is the
  verdict keyword (`SHIP` | `REVISE` | `BLOCKED`) followed by feedback.
- **When written.** At the end of each review attempt
  (`scripts/orch-review.sh`). A new attempt removes the prior file
  before the reviewer runs to guarantee freshness.
- **Writer.** Reviewer agent, via the review prompt's output contract.
  `orch-review.sh` deletes the file before spawning the reviewer and
  reads it back after the reviewer exits.
- **Readers.** `orch-review.sh` (verdict parsing → `lastResult` /
  `reviewStatus`), `orch-engine.sh` (rework decision), humans.
- **Invariants.**
  - Presence after a reviewer run is required — its absence is treated
    as a reviewer failure.
  - First non-empty line is the verdict keyword.
  - Overwritten per attempt, not versioned.

### `review-feedback.txt` *(plan root, not `reviews/`)*

- **What.** Aggregated human-readable feedback written at review time
  for downstream consumption by the ralph / rework flow.
- **Writer.** `scripts/orch-review.sh` (see `FEEDBACK_FILE=` at
  `orch-review.sh:436`).
- **Readers.** Worker rework prompts, humans.
- **Invariants.** Overwritten each review cycle; not authoritative for
  status — `state.json` is.

### `events.jsonl` *(added by this plan — see `events-schema.md`)*

- **What.** Append-only newline-delimited JSON event stream for the
  plan. One event per line; lines are never rewritten or deleted.
- **When written.**
  - `plan_start` / `plan_end` — `scripts/orch-run.sh`.
  - `item_spawn` / `item_status` — `scripts/orch-engine.sh` on every
    status transition.
  - `review_start` / `review_end` — `scripts/orch-review.sh`.
- **Writer.** `harness::emit_event` in `scripts/harness/local.sh`,
  called by the scripts above. Writes go through an atomic append
  (`>>`) with `flock`-style semantics where available.
- **Readers.** TUI / dashboards, smoke tests (`tests/harness/test_events.bats`),
  external observability pipelines, humans tailing the file.
- **Invariants.**
  - Append-only. Consumers may rely on byte offsets being stable.
  - Each line is a standalone valid JSON object with at minimum
    `ts` (ISO-8601 UTC with millisecond precision) and `evt` (string).
  - Event ordering is causal per plan: `plan_start` is first,
    `plan_end` is last, and `item_status` for an item never precedes
    that item's `item_spawn`.
  - Additive: the stream never replaces `state.json` or the raw logs.
  - Missing or malformed lines do not corrupt the state machine —
    `state.json` remains authoritative.

---

## Worker / reviewer scratch files (plan root)

These files live directly under `.orchestrator/plans/${SLUG}/` and are
used to ferry information between the orchestrator and spawned agents.
They are overwritten freely and have no long-term invariants beyond
"exists during the relevant phase":

- `prompt-${N}-*.md` — per-item prompt snapshots (also kept at
  `.orchestrator/prompt-*.md` for older runs).
- `context-handoff.txt`, `work-summary.txt` — ralph-style handoffs used
  by `scripts/ralph-worktree.sh`.

These are debug aids, not state. Nothing in the engine reads them to
make decisions.

---

## Worktrees: `.orchestrator/worktrees/${SLUG}/`

- **What.** Per-plan git worktree (branch `orch/<issue>-${SLUG}`) where
  workers and reviewers run. Contains a full checkout of the project.
- **Writer.** `scripts/orch-run.sh` (`git worktree add`), workers
  (normal file edits during execution).
- **Readers.** All orchestrator scripts invoked with `cwd` inside the
  worktree; `git` itself.
- **Invariants.**
  - One worktree per slug.
  - Removed only by `orch-gc.sh` or explicit operator action — never by
    the engine while items are still `running`.
  - Referenced by `master.json[].plans[].worktree` and
    `state.json[].items[].worktree` as a repo-relative path.

---

## Cross-cutting rules

- **Atomic writes.** All JSON files (`master.json`, `state.json`) are
  updated via tempfile + `mv` within the same filesystem. Readers may
  see either the old or the new complete document — never a partial
  document.
- **Single-writer discipline.** Each file listed above has exactly one
  writer at any instant. The engine serializes its own writes; the
  reviewer serializes its own writes; both avoid overlapping the same
  fields in `state.json`.
- **Never committed.** `.orchestrator/` is `.gitignore`d. Nothing here
  is expected to survive a clean checkout — the plan itself lives in
  `docs/exec-plans/` and the GitHub issue.
- **Additive observability.** `events.jsonl` is additive. Existing
  consumers that only read `state.json` and the raw logs continue to
  work unchanged.
