# Pre-release cleanup — SUMMARY

Date: 2026-04-28
Plan: `20260428-pre-release-cleanup` (issue #252)
Branch: `orch/252-20260428-pre-release-cleanup`

Aggregates the six cleanup reports under `docs/cleanup-reports/` and records the
go/no-go verdict for the `develop → main` merge.

## Reports

### Item 1 — Baseline

- Report: [baseline.log](baseline.log)
- Summary: `bats tests/orch/*.bats` passed 48/48 and `shellcheck scripts/*.sh hooks/**/*.sh` ran clean from a clean checkout — no pre-existing regressions vs `develop` HEAD. **PASS**

### Item 2 — Verify subshell PATH fix

- Report: covered by `bats tests/orch/test_verify_path.bats` (no separate file; behavior verified via the bats suite captured in `baseline.log`)
- Summary: `scripts/orch-verify.sh` now prepends `/opt/homebrew/bin:/usr/local/bin:/usr/local/sbin:` to the inherited PATH inside its `bash -c` subshell so `rg`, `yq`, `fd` resolve under `verify.mode=enforce`; the new bats fixture confirms a tool placed only at a Homebrew-shaped path resolves. **PASS**

### Item 3 — Stale-path / flow audit

- Report: [audit.md](audit.md)
- Summary: 28 stale-reference rows across 11 files in `commands/`, `skills/`, `agents/`. Hard-stale clusters in `commands/fix-issue.md`, `commands/core-init.md`, `skills/plan-registry.md` (recommend rewrite/delete). Findings feed a follow-up doc-sweep plan; nothing here gates the merge. **PASS**

### Item 4 — Dead-code triage (`GH_SYNC=false` branches)

- Report: [deadcode.md](deadcode.md)
- Summary: 12 `GH_SYNC` branches across `scripts/orch-{run,engine,verify,review,parse-items}.sh` — all REACHABLE. Both modes (`github.sync: true` and the local `docs/exec-plans/active/` flow) are intentionally supported for downstream installs. No deletions warranted. **PASS**

### Item 5 — Fresh-install smoke (`INSTALL.md`)

- Report: [install-smoke.log](install-smoke.log)
- Summary: Clean `mktemp -d` reproduced `INSTALL.md` end-to-end — `git clone`, `claude --version` (2.1.121), and `canon --version` (canon-tui from `@main`) all reported cleanly; `grep -q '"@main"'` confirmed the canon-tui ref. **PASS**

### Item 6 — Orchestrator E2E smoke

- Report: [orch-smoke.log](orch-smoke.log)
- Summary: Throwaway issue #255 (`cleanup-smoke-2026-04-28`) drove a real `scripts/orch-run.sh` end-to-end → PR #256 opened, issue comments = 5 (well under the 50 runaway threshold), no `dashboard` tmux window in default detached mode. PR #256 and issue #255 both `CLOSED`; remote branch deleted. **PASS**

## Verdict

All six items passed. No release-blocking findings. The audit and dead-code
reports feed follow-up plans (doc sweep, dead-code review) but do not gate
this merge.

READY FOR MERGE: yes
