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

## 5 scripts use #!/bin/bash instead of #!/usr/bin/env bash

**Severity:** P2
**Area:** hooks/, scripts/
**Logged:** 2026-03-15
**Context:** /cleanup scan

`hooks/enforce-package-manager.sh`, `hooks/play-sound.sh`, `hooks/log-gam.sh`,
`scripts/statusline.sh`, `scripts/dev-test/test-sound.sh`. The `env` shebang is
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
