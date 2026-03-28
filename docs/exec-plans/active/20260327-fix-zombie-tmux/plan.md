# Plan: Fix Orchestrator Zombie tmux Sessions

**Status:** Draft
**Created:** 2026-03-27

## Requirements

- Orchestrator tmux sessions auto-terminate after the engine fully exits (after all SHIP/FAIL steps, review, lifecycle hooks, PR creation, worktree cleanup — the very last command)
- Dashboard loop detects engine death via heartbeat, not just window existence
- A garbage collection script (`orch-gc.sh`) kills stale sessions on demand
- No zombie sessions accumulate between orchestrator runs
- Dashboard stays visible for a configurable grace period after engine exit so the user can read final output

## Approach

Three coordinated fixes as described in `docs/exec-plans/tech-debt.md` § "Orchestrator tmux sessions never auto-kill":

### 1. Engine heartbeat

The engine writes a heartbeat timestamp to `$ORCH_STATE_DIR/plans/$SLUG/heartbeat` at regular intervals (every poll cycle, before/after each major step). This is a single `date +%s > heartbeat` call — zero cost.

The dashboard loop reads this file every 1s (local file check, no tokens, no API). If the heartbeat is stale (>5min old), the engine is dead or hung. The dashboard renders a final frame, waits a grace period (default 60s, configurable via `ORCH_DASHBOARD_TIMEOUT`), then exits.

### 2. Session auto-kill after engine exit

The engine must NOT kill the session after SHIP or FAIL — there's still review, lifecycle hooks, PR creation, worktree cleanup, and validation after those decision points. Instead:

- The engine writes a terminal status (`completed` or `failed`) to `state.json` as its **very last act** before `exit 0`/`exit 1` (this already happens at lines 628-632 and 719-722).
- The dashboard detects the engine window is gone (`tmux has-window` returns false) AND the heartbeat is stale → enters grace period → kills session.
- As a safety net, the engine's tmux command wrapper (line 357 in `orch-run.sh`) appends `; tmux kill-session -t $SESSION` after the existing `sleep 30`, so even if the dashboard is broken, the session dies.

### 3. Stale session GC script

New `scripts/orch-gc.sh` — finds all `orch-*` tmux sessions, checks for engine window, kills those where engine is absent. `--dry-run` lists without killing.

### Dashboard loop interval

The current `while true` loop restarts the node dashboard every 3s. The heartbeat/window check is a local file read + `tmux has-window` — zero network, zero tokens. Reduce to 1s for snappier UI. The node process itself handles its own refresh internally.

### 4. Dashboard heartbeat indicator

The dashboard renders a "Last heartbeat: Xs ago" indicator so the user can see engine liveness at a glance. When the heartbeat goes stale (>5min), the indicator turns red/warning. This is read from the same heartbeat file — no new data source.

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-run.sh` | Replace `while true` dashboard loop with heartbeat-aware loop + grace period; append session kill to engine tmux command; add `--gc` flag dispatch; reduce loop interval to 2s |
| `scripts/orch-engine.sh` | Write heartbeat file at poll start, after each major step (worker spawn, review, SHIP steps), and before exit |
| `scripts/orch-gc.sh` (new) | Stale session finder/killer — list `orch-*` sessions, check for engine window + heartbeat staleness, kill if dead |
| `scripts/terminal-ui/src/orchestrator-app.tsx` | Add heartbeat indicator — read heartbeat file, display "Last heartbeat: Xs ago" with stale warning |
| `scripts/terminal-ui/src/orch-types.ts` | Add `lastHeartbeat` field to orchestrator state types |
| `README.md` | Document `orch-gc.sh` usage, heartbeat mechanism, dashboard auto-exit behavior |
| `docs/exec-plans/tech-debt.md` | Mark the zombie session entry as resolved |

## Risks and open questions

- **Heartbeat write frequency**: Every poll cycle (~30s from `poll_interval_seconds`) plus before/after major steps. Enough granularity without overhead. (P3)
- **Grace period vs engine sleep**: Engine tmux command has `sleep 30` after exit. Dashboard grace is 60s. Safety net kill is `sleep 30` after engine sleep. Timeline: engine exits → 30s sleep → safety net fires at 60s. Dashboard sees stale heartbeat within 1s, starts 60s grace → kills at ~61s. Safety net at ~60s. Both converge. (P2 — verify no race)

## Progress log

- [x] Add heartbeat writes to `orch-engine.sh` — write `date +%s` to `heartbeat` file at poll start, after worker spawn, after review, after each SHIP/FAIL step, and before final exit
- [x] Update dashboard loop in `orch-run.sh` — replace `while true; do node ...; sleep 3; done` with a loop that checks heartbeat staleness (>5min) and `tmux has-window` for engine, enters grace period on engine death, then exits; reduce interval to 2s (deps: 1)
- [x] Add safety-net session kill to `orch-run.sh` — append `; sleep 30; tmux kill-session -t $SESSION 2>/dev/null` to the engine tmux command (line 357) so the session dies even if dashboard is broken (deps: 1)
- [x] Create `scripts/orch-gc.sh` — find stale `orch-*` sessions (no engine window OR heartbeat stale >10min), print age and slug, kill them; support `--dry-run` flag (deps: 1)
- [ ] Wire `--gc` flag into `orch-run.sh` arg parser to dispatch to `orch-gc.sh` (deps: 4)
- [ ] Add heartbeat indicator to dashboard — read heartbeat file in `orchestrator-app.tsx`, display "Last heartbeat: Xs ago" with red/warning styling when stale >5min; add `lastHeartbeat` to `orch-types.ts` (deps: 1)
- [ ] Update `README.md` — document `orch-gc.sh` (usage, `--dry-run`, when to use), heartbeat mechanism (what it is, 5min threshold, where the file lives), dashboard auto-exit behavior (grace period, indicator), and the safety-net session kill (deps: 2, 3, 4, 6)
- [ ] Update `docs/exec-plans/tech-debt.md` — mark zombie session entry as resolved with date (deps: 1, 2, 3, 4, 5, 6, 7, 8)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Heartbeat file (engine writes timestamp) | tmux has-window only, sentinel "done" file, IPC signal | Heartbeat detects hangs (engine alive but stuck) not just crashes. `has-window` only catches full death. |
| Dashboard checks every 2s | 3s (current), 500ms, 5s | Local file read + tmux check = zero network/token cost. 2s gives snappy detection without spin-waiting. |
| Session kill is dashboard's job + engine safety net | Engine kills session directly after SHIP/FAIL | Engine can't kill session at SHIP/FAIL — review, hooks, PR, worktree cleanup all happen after. Dashboard watches for engine completion and handles teardown. Safety net catches broken dashboards. |
| 60s dashboard grace period after heartbeat stale | Immediate, 30s, 5min | Enough to read final output. Configurable via `ORCH_DASHBOARD_TIMEOUT`. |
| Separate `orch-gc.sh` script | Built into engine, cron job | Standalone is composable — callable from CLI, Conductor, or cron. |

## Completion criteria

- [ ] After engine exits (SHIP or FAIL), tmux session terminates within ~90s (60s grace + safety net)
- [ ] Engine writes heartbeat at least once per poll cycle
- [ ] Dashboard detects engine death within 4s (2s check interval + 2s buffer)
- [ ] `orch-gc.sh` correctly identifies and kills stale sessions
- [ ] `orch-gc.sh --dry-run` lists but does not kill
- [ ] Dashboard displays "Last heartbeat: Xs ago" that updates live
- [ ] Heartbeat indicator turns red/warning when stale >5min
- [ ] `README.md` documents `orch-gc.sh`, heartbeat, dashboard auto-exit, and safety-net kill
- [ ] `shellcheck` passes on all modified/new `.sh` files
- [ ] No regressions: orchestrator still launches, runs items, reviews, creates PRs correctly
