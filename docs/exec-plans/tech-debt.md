# Technical Debt Tracker

Known debt items that aren't worth fixing immediately but should be tracked.
Add items here during `/fix-issue` or `/cleanup` runs when debt is discovered
but out of scope for the current PR.

---

## Format

```
## [short description]

**Severity:** P1 / P2 / P3
**Area:** [module or subsystem]
**Logged:** YYYY-MM-DD
**Context:** [what task or PR surfaced this]

[Description of the debt and why it was deferred]
```

---

<!-- Add debt items below this line -->

## Orch test suites broken against multi-plan API

**Severity:** P1
**Area:** tests/
**Logged:** 2026-03-15
**Context:** /cleanup scan

`test-orch-e2e.sh` and `test-orch-stale-detection.sh` use the old global
`ORCH_STATE_FILE` path and call `orch_update_item_status` / `orch_write_state`
with the old single-arg API (missing slug). Both tests are fully broken since the
multi-plan migration. Need complete rewrite of test harness setup to use per-plan
directory structure (`orch_plan_state_file(slug)`). 11+ call sites across both files.

---

## orch-state.sh is 822 lines (2x the 400-line limit)

**Severity:** P2
**Area:** scripts/
**Logged:** 2026-03-15
**Context:** /cleanup scan

20+ functions covering atomic writes, item status, done-file sync, review sync,
promotion, stale detection, master registry, worktree management, plan registry,
changelog, and query helpers. Split into logical modules: `orch-worktree.sh`,
`orch-registry.sh`, `orch-query.sh`.

---

## 6 more oversized files (>400 lines)

**Severity:** P2
**Area:** scripts/, tests/
**Logged:** 2026-03-15
**Context:** /cleanup scan

- `tests/test-orch-e2e.sh` (622 lines)
- `scripts/orch-engine.sh` (568 lines)
- `scripts/ralph-loop.sh` (507 lines)
- `scripts/terminal-ui/src/orchestrator-app.tsx` (435 lines — split MasterOrchestratorApp)
- `scripts/canon-scaffold.sh` (429 lines)
- `tests/test-orch-parallel-review.sh` (416 lines)

---

## Duplicate SHIP completion block in ralph-loop.sh

**Severity:** P2
**Area:** scripts/
**Logged:** 2026-03-15
**Context:** /cleanup scan

Lines ~288-303 and ~445-465 contain identical 20-line SHIP blocks (sound, commit,
registry, changelog). Extract into a helper function.

---

## 4 scripts use #!/bin/bash instead of #!/usr/bin/env bash

**Severity:** P2
**Area:** hooks/, scripts/
**Logged:** 2026-03-15
**Context:** /cleanup scan

`hooks/enforce-package-manager.sh`, `hooks/play-sound.sh`, `hooks/log-gam.sh`,
`scripts/statusline.sh`. The `env` shebang is
more portable and matches all other 30+ scripts.

---

## orch-engine.sh calls play-sound.sh with wrong interface

**Severity:** P3
**Area:** scripts/
**Logged:** 2026-03-15
**Context:** /cleanup scan

`orch-engine.sh:396` passes `"success"` as a positional arg, but `play-sound.sh`
reads `CLAUDE_SOUND` env var. The arg is silently ignored. Should set env var like
`ralph-loop.sh` does.

---

## Deprecated ORCH_STATE_FILE export in orch-types.ts

**Severity:** P2
**Area:** scripts/terminal-ui/
**Logged:** 2026-03-15
**Context:** /cleanup scan

Line 200 is marked `@deprecated` with "Kept temporarily for migration." Per project
policy: replace, don't deprecate. Remove after verifying no consumers.

---

## hooks/test-echo.sh is diagnostic debris

**Severity:** P2
**Area:** hooks/
**Logged:** 2026-03-15
**Context:** /cleanup scan

File header says "Run once, inspect /tmp/posttooluse-echo.json, then remove this hook."
Should be deleted.

---

## Triplicated chokidar watcher pattern in terminal-ui

**Severity:** P3
**Area:** scripts/terminal-ui/
**Logged:** 2026-03-15
**Context:** /cleanup scan

The `loadState + chokidar watch + ENOENT handling + lastValidRef` pattern is
copy-pasted 3 times. Extract a `useWatchedState<T>(path)` hook.

---

## 12 TODO stub tests in canon/templates/nba-momentum

**Severity:** P3
**Area:** canon/templates/
**Logged:** 2026-03-15
**Context:** /cleanup scan

All say "TODO: AI fills in assertions." Tests assert nothing.

---

## Orchestrator credit-exhaustion recovery is manual and error-prone

**Severity:** P1
**Area:** scripts/orch-*
**Logged:** 2026-03-26
**Context:** pmxt POC run (issue #30) — orch ran out of API credits mid-run, items 7-8 hit review-max-retries. Recovery required manual tmux kill, worktree inspection, git merge, conflict resolution, and PR creation. No automated or documented recovery path exists.

Problems:
1. **No graceful credit/budget exhaustion handling** — orch keeps retrying until max iterations, wasting cycles on review when the worker can't respond
2. **No `orch recover` command** — after a failed run, resuming requires manual worktree merge, state inspection, and cleanup. Should have a single command: `orch-run.sh --recover <slug>` that merges completed work, marks failed items as resumable, and offers to re-run only remaining items
3. **Worktree branch merge into working branch is undocumented** — the merge from `orch/<slug>` into the working branch can conflict with concurrent pushes (as happened here with rebase conflicts)
4. **No partial-success PR flow** — when 6/8 items SHIP but 2 fail, there's no way to ship the completed work and re-queue the rest

---

## Deprecate Ralph Loop in favor of Orchestrator

**Severity:** P2
**Area:** scripts/, commands/, CLAUDE.md
**Logged:** 2026-03-26
**Context:** Core readiness assessment for team sharing

Ralph Loop (`scripts/ralph-loop.sh`, `scripts/ralph-worker-prompt.md`,
`scripts/ralph-reviewer-prompt.md`, `scripts/plan-advance.sh`,
`scripts/ralph-check.sh`, `scripts/ralph-worktree.sh`,
`scripts/review-advance.sh`) is legacy. The orchestrator (`orch-run.sh`)
replaced it entirely. Agents still see Ralph references in CLAUDE.md,
`dega-core.yaml` templates (`worker_prompt`, `reviewer_prompt`), and
inline comments, which causes confusion about which system to use.

Action:
1. Remove Ralph scripts or move to `scripts/legacy/`
2. Strip `worker_prompt` / `reviewer_prompt` from `dega-core.yaml` template in `core-init.md`
3. Remove Ralph references from CLAUDE.md and docs
4. Update `core-init.md` completion message (step 5 says "Run it: bash ~/.claude/scripts/orch-run.sh")

---

## No troubleshooting guide for team onboarding

**Severity:** P2
**Area:** docs/
**Logged:** 2026-03-26
**Context:** Core readiness assessment for team sharing

No `TROUBLESHOOTING.md` or FAQ section for common setup failures:
hooks path errors when running outside an initialized project, prerequisite
install failures (tmux, jq, node), terminal-ui build failures, tmux attach
problems, settings.json merge conflicts. Teammates hitting these issues
have no recovery path except reading source code.

---

## No "first plan" quickstart guide

**Severity:** P3
**Area:** docs/
**Logged:** 2026-03-26
**Context:** Core readiness assessment for team sharing

35+ completed exec-plans exist as reference, but no short walkthrough for
writing a first plan. A teammate new to the system has to reverse-engineer
the format from completed plans or read the full `/plan` command spec.
A 30-line "Your First Plan" guide with a minimal example would cut
onboarding time significantly.

---

## ~~Orchestrator tmux sessions never auto-kill — zombie session accumulation~~

**Severity:** P1
**Area:** scripts/orch-run.sh, scripts/orch-engine.sh
**Logged:** 2026-03-26
**Resolved:** 2026-03-27
**Context:** Found 56 zombie tmux sessions draining GitHub GraphQL API quota (5000/hr exhausted). First Linux run investigation.

**Resolution:** Fixed via plan `20260327-fix-zombie-tmux`. Three coordinated fixes:

1. **Engine heartbeat** — `orch-engine.sh` writes `date +%s` to
   `$ORCH_STATE_DIR/plans/$SLUG/heartbeat` at poll start, after worker
   spawn, after review, after each SHIP/FAIL step, and before exit.

2. **Dashboard exit condition** — `orch-run.sh` dashboard loop checks
   heartbeat staleness (>5min) and `tmux has-window` for the engine window.
   On engine death, enters a configurable grace period (default 60s via
   `ORCH_DASHBOARD_TIMEOUT`), then kills the session. Safety-net
   `tmux kill-session` appended to engine tmux command fires after 30s
   sleep even if dashboard is broken.

3. **Stale session GC** — `scripts/orch-gc.sh` finds `orch-*` sessions
   with no engine window or stale heartbeat (>10min), prints age and slug,
   kills them. Supports `--dry-run`. Accessible via `orch-run.sh --gc`.

---

## orch_read_config() grep matches partial key names

**Severity:** P1
**Area:** scripts/orch-state.sh
**Logged:** 2026-03-26
**Context:** Both orchestrator engines crashed on startup — `sleep` received `15\n10\n10` instead of `15`. First Linux run investigation.

`orch_read_config()` at `orch-state.sh:60` uses `grep "${key}:"` without
anchoring. When reading `poll_interval_seconds`, it also matches
`review_poll_interval_seconds` and `verify_poll_interval_seconds`, producing
a multiline value that crashes `sleep` and any other consumer expecting a
single value.

**Hotfix applied** (2026-03-26): changed to `grep -m1 "^${key}:"`. This
fixes the immediate crash but the function is still fragile — it doesn't
handle nested YAML, quoted values, or comments. A proper fix would use
`yq` or a dedicated YAML parser, but the hotfix is sufficient for the
current flat config format.

---

## Stale MEMORY.md — active plans, decisions, and preferences from March 20

**Severity:** P3
**Area:** memory/
**Logged:** 2026-03-28
**Context:** Memory audit

`MEMORY.md` (32 lines, last updated 2026-03-20) tracks active plans in flight
(github-issues, project-state-tui), architectural decisions (Toad fork, GitHub
Issues as source of truth), naming conventions (Conductor vs Agent View), repo
layout, and user preferences (autonomous, AIDD estimates). Likely stale — verify
and update or prune.

---

## Orchestrator workers cannot run browser-dependent tools (Remotion render, Playwright, etc.)

**Severity:** P2
**Area:** scripts/orch-engine.sh, worker prompt
**Logged:** 2026-03-30
**Context:** Plan #73 (demo-video) — orchestrator completed 6/7 items but worker-7 stalled on `remotion render`

The orchestrator spawns workers as headless Claude agents via
`claude --dangerously-skip-permissions -p "..."`. These run in tmux panes
with no display server. Remotion's `render` command needs a Chromium
instance to rasterize React components into frames. The worker launched
but never started rendering — no process spawned, no error surfaced, the
worker just hung at 0% CPU until the session was killed.

This affects any plan item that requires a browser runtime: Remotion
render, Playwright tests, Puppeteer screenshots, Storybook builds.

**Workaround applied:** Killed the orch session, ran `remotion render`
interactively from the worktree (took ~15s per composition). All 8 MP4
clips exported successfully.

**Possible fixes:**
1. Detect browser-dependent items in the plan and flag them as
   `manual: true` — orchestrator skips them and leaves a TODO
2. Run workers with `DISPLAY=:99` using Xvfb (Linux) or headless
   Chromium flags
3. Add a `check_command` pre-flight that verifies the tool can run
   in the current environment before starting the worker

---

## Stale ralph-loop-issues.md — orchestrator post-mortem from March 7

**Severity:** P3
**Area:** memory/
**Logged:** 2026-03-28
**Context:** Memory audit

`ralph-loop-issues.md` (52 lines, 2026-03-07) documents 4 root causes from a
failed orchestrator run: reviewer can't see untracked files, phantom checkboxes
in plan-advance.sh, token exhaustion, per-item JSON files. Most of these were
addressed by subsequent orchestrator rewrites. Verify fixes landed and delete.

---

## Missing reviewer prompt template breaks orch review phase

**Severity:** P1
**Area:** scripts/orch-review.sh
**Logged:** 2026-04-13
**Context:** Plan #162 (scope guardrails) — all 3 items completed successfully but review phase failed with `error: reviewer prompt template not found: /Users/cerratoa/.degacore/scripts/ralph-item-reviewer-prompt.md`

`orch-review.sh` expects a reviewer prompt template at
`~/.degacore/scripts/ralph-item-reviewer-prompt.md` but the file does not exist.
This means **no plan can complete the review phase**, so every orch run ends with
all items done but no SHIP decision. The orchestrator silently exits after the
error — no retry, no fallback.

This may be a missing file from `/apply-core` (the template exists in the repo
but isn't installed) or a path mismatch after the `~/.claude/` → `~/.degacore/`
migration.

**Impact:** Every orchestrator run is blocked from completing review and SHIP.
Workers do the work, but no PR is created and no issue is closed.

---

## Orch SHIP cleanup proceeds after failed push — deletes branch with all work

**Severity:** P1
**Area:** scripts/orch-engine.sh
**Logged:** 2026-04-14
**Context:** Plan #166 (Polymarket Trading Client) — push failed (rate limit), engine deleted local branch and worktree anyway, reported 0 errors

`orch-engine.sh` step 8/9 (push + PR creation) treats push failure as non-fatal:
it logs "WARN — git push failed, skipping PR creation" then continues to step 9
which deletes the worktree and the local branch. The branch contained all 15 items
of committed work. The engine then reported "SHIP COMPLETE / Errors: 0".

In this case the push actually succeeded (branch was on remote) but the engine
misdetected it as a failure. Either way, the cleanup logic should not destroy the
only copy of the work when the push/PR step fails.

**Fix:** Step 9 (worktree cleanup + branch delete) must be gated on step 8 success.
If push or PR creation fails, preserve the worktree and branch, increment the error
count, and print recovery instructions (`git push origin <branch>` + `gh pr create`).

---

<!-- Resolved 2026-04-18: shipped `swapToUsdce()` + `canon-cli onboard`. -->
<!-- See canon/templates/client-polymarket.ts and canon/cli/commands/onboard.ts. -->

## Polymarket onboarding — ETH-from-bridge path

**Severity:** P3
**Area:** canon/cli/commands/onboard.ts
**Logged:** 2026-04-18
**Context:** Autoswap shipped for native USDC / USDT / POL. Users bridging ETH from L1 land with POS-bridged WETH on Polygon, not covered by the current onboard plan.

**Fix:** add WETH as a `SwapSource`. Same Uniswap v3 quoter-driven pattern; pool exists at 0.05%.
