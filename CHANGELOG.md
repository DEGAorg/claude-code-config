# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Codify canon script runtime contract + extend `apply-core` manifest with canon skills, scripts, and persona block (`20260422-canon-script-contract`) — 2026-04-22

- Add canon umbrella skill + full-phase detection; convert `canon/commands/*` to NL skills with thin aliases (`20260422-canon-umbrella-state`) — 2026-04-22

- Add `canon-new` NL-triggered skill and `bootstrap-check.sh` phase helper (`20260422-canon-new-skill`) — 2026-04-22

- Add missing gh-plan scripts to /apply-core install manifest (`20260324-apply-core-gh-scripts`) — 2026-03-24

- Create GitHub Issue when plan is written, not when orch starts (`20260324-issue-on-plan-create`) — 2026-03-24

- Orchestrator creates PR on SHIP with linked branch (`20260320-orch-ship-pr`) — 2026-03-21

- Orchestrator auto-creates GitHub Issue for local plans (`20260320-orch-auto-issue`) — 2026-03-21

### Changed
- canon umbrella skill + state detection (`20260422-canon-umbrella-state`) — 2026-04-22

- Orch workers → Harness capability contract (background processes) (`20260421-orch-harness-migration`) — 2026-04-21

- Wire Strategy Templates into Canon Start Pipeline (`20260415-wire-templates`) — 2026-04-16

- ARB-01 Binary Arbitrage Scanner (`20260414-arb-01`) — 2026-04-16

- Canon CLI — Agent-Callable Trading Tools (`20260414-canon-cli`) — 2026-04-14

- Polymarket Trading Execution Pipeline (`20260414-polymarket-trading-pipeline`) — 2026-04-14

- Polymarket Trading Client (`20260413-polymarket-trading-client`) — 2026-04-14

- RPA DoraHacks — Multi-Account Session Management (`20260404-rpa-multi-account`) — 2026-04-04

- RPA DoraHacks — Neon DB Migration (`20260404-rpa-neon-migration`) — 2026-04-04

- Migrate timeline from JSON to GitHub Issues + Milestones (`20260403-timeline-migration`) — 2026-04-04

- DoraHacks Listing for Canon Hackathon (`dorahacks-listing`) — 2026-04-02

- Complete GH audit trail with work summaries, feedback, and verify results (`20260325-gh-audit-trail`) — 2026-03-25

- Skip git-tracked plan artifacts when github.sync is true (`20260325-gh-mode-skip-local-artifacts`) — 2026-03-25

- Development Patterns Skill System (`20260321-development-patterns-skill`) — 2026-03-21

- Agent-to-panel integration — Claude controls the GitHub panel (`20260321-agent-panel-integration`) — 2026-03-21

- Redesign GitHub panel — PM dashboard with status and timeline (`20260320-gh-panel-redesign`) — 2026-03-21

- Agent-controlled panels + direct conductor launch (`20260320-agent-panel-control`) — 2026-03-21

- Verify issue body sync works end-to-end (`20260320-verify-body-sync`) — 2026-03-21

- Sync issue body — check off progress log and completion criteria (`20260320-issue-body-sync`) — 2026-03-21

- Conductor TUI — Toad Fork + GitHub Project State (`20260320-project-state-tui`) — 2026-03-21

- GitHub Issues as Plan System (`20260320-github-issues-plans`) — 2026-03-21

- Clear SHIP completion — state, dashboard, and session cleanup (`20260315-fix-orch-ship-completion`) — 2026-03-15

- Autonomous planner loop — long-running agent that plans and executes (`20260315-planner-loop`) — 2026-03-15

- Rename ralph.yaml to dega-core.yaml (`20260315-config-and-state-cleanup`) — 2026-03-15

- Dashboard viewport uses flexGrow for adaptive sizing (`20260315-dashboard-viewport-flexgrow`) — 2026-03-15

- Self-development guide (`20260315-self-development-guide`) — 2026-03-15

### Fixed
- Fix CI pipeline — shellcheck severity and excluded codes (`20260321-fix-ci-pipeline`) — 2026-03-27

- Fix sound interface bug in orch-engine.sh (`20260324-fix-sound-bug`) — 2026-03-24

- Fix shebang inconsistency across scripts and hooks (`20260324-fix-shebang`) — 2026-03-24

- Fix GitHub panel — agent-summoned and repo-aware (`20260320-fix-gh-panel-design`) — 2026-03-21

- Fix orchestrator review quality — reject partial completions (`20260320-orch-review-quality`) — 2026-03-21

- Fix SHIP flow — don't close issue until PR merges (`20260320-fix-ship-close-flow`) — 2026-03-21

- Workshop Prep — Install Fixes, Ralph Cleanup, Merge to Develop (`20260319-workshop-prep`) — 2026-03-20

- Fix orch worktree commits stalling on pre-commit hooks (`20260315-fix-orch-worktree-hooks`) — 2026-03-16

- Fix orch scripts to work when installed globally (`20260315-fix-orch-global-paths`) — 2026-03-15

- Fix apply-core to include all orchestrator and planner files (`20260315-fix-apply-core-orch-files`) — 2026-03-15


### Removed
- Delete diagnostic debris and stale worktrees (`20260324-delete-diagnostic-debris`) — 2026-03-24

## 2026-03-15

### Changed

- AI plan registry (`20260315-ai-plan-registry`)
- Orch clean dashboard exit on SHIP (`20260315-orch-clean-exit`)
- Orch completion criteria gate (`20260315-orch-completion-criteria-gate`)
- Orch done-file validation (`20260315-orch-donefile-validation`)
- Orch fullscreen terminal window (`20260315-orch-fullscreen-terminal`)
- Orch persist engine logs on SHIP (`20260315-orch-persist-logs`)
- Orch progress resilience on failure (`20260315-orch-progress-resilience`)
- Orch worktree plan isolation (`20260315-orch-worktree-plan-isolation`)

## 2026-03-14

### Changed

- Dashboard Live Worker Output (`20260314-orch-dashboard-live-output`)
- Dashboard Terminal Viewport (`20260314-orch-dashboard-terminal-viewport`)
- Fire-and-Forget Orchestrator Launch (`20260314-orch-fire-and-forget`)
- Multi-Plan Orchestration with Master State (`20260314-orch-multi-plan`)
- Parallel Per-Item Review (`20260314-orch-parallel-review`)
- Reviewer Dashboard Visibility (`20260314-orch-reviewer-dashboard-visibility`)

### Fixed

- Dashboard Rendering Fixes (`20260314-orch-dashboard-rendering`)
- Orch/Ralph quick fixes (`20260314-orch-quick-fixes`)

## 2026-03-13

### Changed

- Orchestrator Cleanup (`20260313-orch-cleanup`)
- Orchestrator Full Auto — One Command Does Everything (`20260313-orch-full-auto`)
- Orchestrator Stale Worker Detection (`20260313-orch-stale-worker-detection`)
- Orchestrator Visibility Layer (`20260313-orch-visibility`)

### Fixed

- Fix ralph-loop.sh sed multiline substitution bug (`20260313-ralph-sed-bug`)
- Verify ralph-loop.sh sed fix (`20260313-ralph-sed-verify`)

## 2026-03-10

### Changed

- Orchestrator Tmux Execution Engine (`20260310-orch-tmux-rebuild`)

## 2026-03-09

### Changed

- Orchestrator Smoke Test (`20260309-orch-smoke-test`)
- [DEPRECATED] Hybrid Orchestrator: State Layer + Agent Teams Execution (`20260309-hybrid-orch`)

## 2026-03-08

### Changed

- Orchestrator End-to-End — Polling Loop + Review Integration (`20260308-orch-e2e`)

## 2026-03-07

### Changed

- Orchestrator Agent — Multi-Plan Conductor (`20260307-orchestrator`)
- Orchestrator Hardening — Per-Item Scoping + Single State File (`20260307-orch-hardening`)
- Review-Advance — Per-Item Reviewer Loop (`20260307-review-advance`)

## 2026-03-06

### Changed

- Core Init Command (`20260306-core-init`)
- Docs Update (`20260306-docs-update`)
- Parallel Ralph Loops via Worktrees (`20260306-parallel-worktrees`)
- Post-Demo Cleanup (`20260306-post-demo-cleanup`)

### Fixed

- Fix Ralph Loop Reviewer Not Writing review-result.txt (`20260306-ralph-reviewer-fix`)

## 2026-03-03

### Changed

- /canon-start Command (`20260303-canon-start-command`)
- Demo Prep — March 5 Canon Demo (`20260303-demo-prep`)
- Exec-Plan Naming Enforcement (`20260303-exec-plan-naming-enforcement`)
- Ink Status Dashboard (terminal-ui) (`20260303-ink-status-dashboard`)
- Terminal UI Wiring (End-to-End) (`20260303-terminal-ui-wiring`)
- tmux Session Launcher (`20260303-tmux-session-launcher`)

## 2026-03-02

### Changed

- Demo Prep — Canon Init Flow for March 5 Recording (`20260302-demo-prep`)

## Pre-dating

### Added

- Add ralph loop command hint to /plan hand-off (`plan-ralph-hint`)
- Add shfmt Formatting Check to CI (`shfmt-ci`)

### Changed

- Build /apply-canon Command (`apply-canon-command`)
- Canon Agent Framework Artifacts (`canon-agent-framework`)
- Canon Init — Project-Local Model (`canon-init`)
- Cross-Platform Sound Hooks (WSL2 + Linux) (`sound-hooks-linux`)
- Demo S1 — Sports Arb Strategy Repo Bootstrap (`demo-s1-strategy-repo`)
- Demo S2 — pmxt + Sportsbook API Scaffolding (`demo-s2-pmxt-scaffold`)
- Demo S3 — Sports Arb Strategy Build (The Demo Moment) (`demo-s3-sports-arb`)
- Full Ralph Loop Implementation (`ralph-loop`)
- Harness Gap 7 — App-Legibility Skill (`harness-gap7-app-legibility-skill`)
- Logging Infrastructure — Persistent Server + Ralph Event Logging (`logging-infrastructure`)
- Logging Integration (`logging-integration`)
- Ralph Loop Global Install (`ralph-global-install`)
- Ralph Loop Sound Behavior (`ralph-loop-sounds`)
- Ralph S1 — Per-Item Loop (`ralph-s1-per-item-loop`)
- Ralph S2 — Enforcement (`ralph-s2-enforcement`)
- Ralph S3 — Reliability (`ralph-s3-reliability`)
- Ralph S4 — Structured Logging (`ralph-s4-logging`)
- Ralph S5 — Context Handoff (`ralph-s5-context-handoff`)
- Resume Test (Multi-Step Interrupt/Resume Smoke Test) (`resume-test`)
- Sound Hooks on Task Completion (`sound-hooks`)
- Terminal UI State File Spec (`terminal-ui-state-spec`)
- Test (Exec-Plan Lifecycle Smoke Test) (`test`)

### Fixed

- Add date prefix to exec-plan slugs (`plan-date-prefix`)
- Fix apply-core — install ralph loop scripts per repo (`apply-core-ralph-install`)

### Removed

- Remove ralph-check.sh from global Stop hook (`remove-global-ralph-check`)
