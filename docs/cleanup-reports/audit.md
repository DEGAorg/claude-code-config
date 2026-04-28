# Stale path & flow audit — `commands/`, `skills/`, `agents/`

Date: 2026-04-28
Branch: `orch/252-20260428-pre-release-cleanup`
Scope: every top-level file under `commands/`, `skills/`, `agents/`.

## Method

1. `rg -l "exec-plans/active|local plan\.md" commands/ skills/ agents/`
2. Broader sweep with `rg -n "exec-plans|/plan |plans/|plan\.md"` over the
   same trees to catch dead-path refs the narrower regex would miss.
3. Manual read of every file flagged in steps 1-2 (and a skim of the
   remaining files in those dirs) to find stale flow language that does
   not literally mention `exec-plans/active` but still describes the
   pre-GitHub-Issues workflow.

Source of truth for current flow: `CLAUDE.md` ("Plans are GitHub issues
with the `plan:draft` label … the issue body is the canonical plan") and
`agents/orch-worker.md` (runtime plan path = `.orchestrator/plans/<slug>/plan.md`,
fetched from issue body, ephemeral).

## Findings

| File | Line | Snippet | Suggested replacement |
|------|------|---------|------------------------|
| `commands/fix-issue.md` | 17 | `Create a plan directory at `docs/exec-plans/active/YYYYMMDD-issue-$ISSUE_NUMBER/`` | Replace with: open a GitHub issue using `/plan` (or `scripts/plan-create.sh`) with the `plan:draft` label; the orchestrator will fetch the body into `.orchestrator/plans/<slug>/plan.md` at runtime. No local plan dir is created. |
| `commands/fix-issue.md` | 19 | `Write the plan to `docs/exec-plans/active/YYYYMMDD-issue-$ISSUE_NUMBER/plan.md`.` | Remove. The plan body lives in the GitHub issue. Reference it as Issue #N. |
| `commands/fix-issue.md` | 29 | `Non-trivial work always goes in `exec-plans/`.` | Replace with: "Non-trivial work always goes in a GitHub issue with the `plan:draft` label." |
| `commands/fix-issue.md` | 55-56 | `Move the plan directory from `docs/exec-plans/active/...` to `docs/exec-plans/completed/...`` | Remove. Closure is handled by the orchestrator (`close_on_ship: true` in `dega-core.yaml`) — the issue is closed and labeled `plan:completed`. There is no directory move step. |
| `commands/core-init.md` | 3 (`@description`) | `creates dega-core.yaml, exec-plans, .gitignore entries…` | Drop "exec-plans" from the description; the bootstrap should not create a `docs/exec-plans/` tree. |
| `commands/core-init.md` | 90 | `mkdir -p docs/exec-plans/active docs/exec-plans/completed .claude/commands` | Replace with: `mkdir -p .claude/commands`. Also create `.orchestrator/` entry in `.gitignore` (already done on line ~). Plans are issues; nothing to bootstrap on disk. |
| `commands/core-init.md` | 96-97 | `[[ -z "$(ls -A docs/exec-plans/active …)" ]] && touch docs/exec-plans/active/.gitkeep` (and `completed`) | Delete both lines — directories no longer exist. |
| `commands/core-init.md` | 292 | `\| `docs/exec-plans/` \| Execution plans (active + completed) \|` (Repo Map row) | Delete row, or replace with a row pointing to the GitHub issue tracker / `plan:*` labels. |
| `commands/core-init.md` | 298 | `Exec plans: `docs/exec-plans/active/<YYYYMMDD-slug>/plan.md`` | Replace with: "Exec plans: GitHub issues with the `plan:draft` / `plan:active` label. Use `/plan` to create one. Runtime: `.orchestrator/plans/<slug>/plan.md` (ephemeral, gitignored)." |
| `commands/core-init.md` | 302 | `Check `docs/exec-plans/active/` for in-progress plans before starting new work.` | Replace with: `gh issue list --label plan:active` to see in-progress plans. |
| `commands/core-init.md` | 344-345 | `✓ docs/exec-plans/active/  …`  / `✓ docs/exec-plans/completed/  …` | Remove both lines from the completion banner. |
| `commands/cleanup.md` | 79 | `Fix if trivial; otherwise log to `docs/exec-plans/tech-debt.md`.` | Out of scope for the active/local-plan migration but still stale: replace with the project's debt tracker (GitHub issues with `tech-debt` label, per `skills/tech-debt-tracking.md` after that skill is updated — see rows below). Mark for follow-up cleanup. |
| `commands/plan.md` | 94 | `in `rules/exec-plans.md`. Run every check below.` | Verify the rule file is still authoritative; if so, no change. (`rules/exec-plans.md` is referenced from the global CLAUDE.md and is current — keep.) |
| `skills/github-plans.md` | 124 | `(plan files committed to `docs/exec-plans/`). The two modes are mutually exclusive.` | This describes a "fallback" local mode. Confirm intent: if local mode is being removed for the release, delete the entire "Fallback behavior" subsection; if it's retained, leave as-is but mark explicitly as "legacy / fallback only — disable by setting `github.sync: true`". |
| `skills/github-plans.md` | 161 | `back to the local plan workflow: plans live in `docs/exec-plans/active/`` | Same as above — depends on whether local mode survives the cleanup. Recommend deleting (lines ~158-163 entire "Fallback behavior" section) since `dega-core.yaml` ships with `github.sync: true` and there is no test coverage for the local fallback. |
| `skills/plan-registry.md` | 11-12 | `docs/exec-plans/REGISTRY.md` is the single index … `docs/exec-plans/completed/` | Whole skill is built around the local registry. Recommend either: (a) delete `skills/plan-registry.md` outright, or (b) rewrite to query GitHub: `gh issue list --label plan:completed --state closed --json number,title,closedAt`. Without a rewrite, every example in this file is a dead path. |
| `skills/plan-registry.md` | 19, 27, 45 | `[slug](completed/slug/plan.md)` table examples | Replace example link target with `gh issue view <N>` or a GitHub URL. |
| `skills/plan-registry.md` | 52 | `**All plans:** read `docs/exec-plans/REGISTRY.md`` | Replace with `gh issue list --label plan:completed --state closed`. |
| `skills/plan-registry.md` | 56 | `rg "^\| 2026-03-15" docs/exec-plans/REGISTRY.md` | Replace with `gh issue list --label plan:completed --search "closed:2026-03-15"`. |
| `skills/plan-registry.md` | 61 | `rg "\| orch \|$" docs/exec-plans/REGISTRY.md` | Replace or delete — "method" column was a local-registry concept. The orchestrator is the only path now. |
| `skills/plan-registry.md` | 66 | `tail -n +3 docs/exec-plans/REGISTRY.md \| wc -l` | Replace with `gh issue list --label plan:completed --state closed --limit 1000 \| wc -l`. |
| `skills/plan-registry.md` | 69 | `Active plans (not in registry):` check `docs/exec-plans/active/` | Replace with `gh issue list --label plan:active`. |
| `skills/plan-registry.md` | 77-79 | `active/<slug>/plan.md (in progress) ↓ SHIP completed/<slug>/plan.md (archived)` lifecycle diagram | Replace with the issue label lifecycle: `plan:draft → plan:active → plan:review → plan:completed` (closed) / `plan:failed`. |
| `skills/plan-registry.md` | 85 | `… `docs/exec-plans/active/` or check `.orchestrator/plans/*/state.json`` | Replace with `gh issue list --label plan:active`. The `.orchestrator/plans/*/state.json` reference is correct for runtime state but only on the host that ran the orch. |
| `skills/plan-registry.md` | 93-100 | Whole `docs/exec-plans/` tree diagram (`├── REGISTRY.md`, `├── active/`, `├── completed/`, `├── tech-debt.md`, `└── tech-debt/`) | Delete diagram or replace with a description of the GitHub-issue-based layout. None of these directories are produced by the current toolchain. |
| `skills/tech-debt-tracking.md` | 11 | ``docs/exec-plans/tech-debt.md` is the single index of all known debt.` | Out of immediate audit scope (item targets `exec-plans/active`), but flagged here for completeness: rewrite to track debt as GitHub issues with `tech-debt` label, mirroring the plan migration. Confirm with maintainers before changing. |
| `skills/tech-debt-tracking.md` | 17, 31, 50, 60-61, 74, 78-79 | Multiple references to `docs/exec-plans/tech-debt.md` and `docs/exec-plans/tech-debt/` | Same as row above — sweep when the debt-tracking flow is migrated. Not a release blocker for the orch flow itself. |
| `skills/changelog.md` | 40 | `Extracts the plan title from `# Plan: <title>` in `plan.md`` | Verify: the runtime path `.orchestrator/plans/<slug>/plan.md` is fetched from the issue body and still starts with `# Plan: <title>`. If so, the snippet is correct; just clarify it reads the runtime (ephemeral) plan, not a committed one. |
| `commands/sync.md` | 70-125 | References to `.orchestrator/plans/<slug>/` directories | These describe the runtime/ephemeral local state, not the legacy `docs/exec-plans/`. Flow is current — no change. (Listed only because it surfaced in the broad sweep.) |
| `agents/orch-worker.md` | 15, 38, 53, 131 | Mentions of `.orchestrator/plans/<slug>/plan.md` and "runtime plan path" | Current and correct (fixed in commit `32bfa8a8` / item 2 of this plan). No change. |
| `agents/orch-verifier.md` | 5 | `mutates plan.md checkboxes on pass` | Verify the agent uses the runtime path; if so, leave. Optionally clarify "the runtime `.orchestrator/plans/<slug>/plan.md`" to match the worker prompt vocabulary. |

## Files scanned and clean

The following top-level files in scope contained no stale `exec-plans/active`
or local-plan flow language:

- `commands/apply-core.md`
- `commands/canon-init.md`
- `commands/core-update.md`
- `commands/doc-garden.md`
- `commands/review-pr.md`
- `commands/timeline.md`
- `skills/app-legibility.md`
- `skills/custom-linter-authoring.md`
- `skills/development-patterns.md`
- `skills/sound-notifications.md`
- `skills/tui-control.md`
- `agents/conductor.md`

## Severity grouping

- **Must fix before release** (ship-blockers — describe a flow that no longer
  exists and will mislead users):
  `commands/fix-issue.md` (lines 17, 19, 29, 55-56),
  `commands/core-init.md` (lines 3, 90, 96-97, 292, 298, 302, 344-345),
  `skills/plan-registry.md` (entire file — recommend delete or rewrite).
- **Decide and act** (legacy fallback — keep or remove):
  `skills/github-plans.md` "Fallback behavior" section (lines 158-163, 124).
- **Follow-up** (out of this audit's strict scope but discovered while scanning):
  `skills/tech-debt-tracking.md` (multiple lines), `commands/cleanup.md:79`.
- **No action** (already current):
  `commands/sync.md`, `agents/orch-worker.md`, `agents/orch-verifier.md`,
  `commands/plan.md:94`, `skills/changelog.md:40`.
