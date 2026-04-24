# claude-code-config — AI Development Core

The foundational layer for AI-driven development: skills, hooks, commands, agents, and
harness patterns. Everything here is **generic and reusable** — project-specific layers
(like Canon) build on top of this core.

---

## Scope for Ace

**Ace** works on **Phase I** of the Canon MVP Technical Roadmap, across both Core and Canon layers.

- **Core harness** (all 7 gaps): complete. Core artifacts must remain project-agnostic.
- **Canon layer** (`canon/`): now active. Skills, agents, commands, and templates.
- **Ignore Canon Arena**: No Arena web dashboard, no Arena frontend, no leaderboard UI, no UI work of any kind. Arena is out of scope for Ace.

Source of truth for Phase I scope: `../../canon-docs/Canon_MVP_Technical_Roadmap.md`
Full spec index: see **Canon Specs** section below.

---

## Canon Specs (Read-Only Reference)

Canon specifications live in a sibling docs repo. Do not duplicate them in Core.

| Repo | Purpose | Absolute path |
|------|---------|---------------|
| **Core** (this repo) | Harness, skills, commands, MCP server | `/Users/cerratoa/dega/aidd/claude-code-config` |
| **Canon Docs** | Specs, roadmap, SAS — source of truth | `/Users/cerratoa/dega/canon-docs` |

**Relative path from Core:** `../../canon-docs`

**Read these specs before implementing Canon features:**

| File | Use when |
|------|----------|
| `Canon_MVP_Technical_Roadmap.md` | Scaffold structure, canon_init, 10 templates, .canon/ tree |
| `canon-installation-architecture-analysis.md` | Core vs Canon split, install scope, canon_init behavior |
| `specs/SAS_Agent_Framework.md` | Agent personas, skills, workflows, .canon/ conventions |
| `specs/SAS_AIDD_Pipeline.md` | Ralph Loop, risk contract, .canon/dega-core.yaml, hooks |
| `specs/SAS_Automation_Model.md` | Strategy scaffolds, automation patterns |
| `Canon_Key_Components.md` | High-level components, canon init --profile |
| `specs/SAS_Deployment.md` | Cloud execution, $HOME/.canon/, image registry |

Canon scaffold (.canon/ directory): see `Canon_MVP_Technical_Roadmap.md` lines 578-620 and 891-917.

**Rule:** All Canon implementation tasks must be grounded in a spec from canon-docs. If a task has no backing spec, write one there first.

---

## Repo Map

| Path | Purpose |
|---|---|
| `README.md` | Full reference guide — source of truth for all config explanations |
| `DECISIONS.md` | Settled architecture decisions for Core + Canon |
| `AGENTS.md` | Project-level agent configuration — single source of truth (this file) |
| `CLAUDE.md` | Shim — points agents to `AGENTS.md` (Claude Code auto-discovery) |
| `GEMINI.md` | Shim — points agents to `AGENTS.md` (Gemini auto-discovery) |
| `.cursorrules` | Shim — points agents to `AGENTS.md` (Cursor auto-discovery) |
| `agent-template.md` | Global CLAUDE.md template (`~/.claude/CLAUDE.md`) — lean map, ~120 lines |
| `rules/` | Language-specific standards loaded by file type (python, node-typescript, rust, bash, github-actions) |
| `settings.json` | Claude Code settings template (hooks, permissions) |
| `mcp-template.json` | MCP server configuration template |
| `dega-core.yaml` | Dega Core per-project config (max iterations, success criteria, poll interval) |
| `commands/` | Global slash commands — `apply-core`, `canon-init`, `core-init`, `fix-issue`, `review-pr`, `plan`, `cleanup`, `doc-garden` |
| `skills/` | Core skills — `app-legibility`, `changelog`, `custom-linter-authoring`, `development-patterns`, `plan-registry`, `sound-notifications`, `tech-debt-tracking` |

| `skills/patterns/` | Development pattern extensions grouped by topic — loaded by `development-patterns` skill |
| `hooks/` | Hook scripts for lifecycle events (enforce-package-manager, play-sound, orch-done-sync, structured-log, etc.) |
| `sounds/` | MP3 sound files played on task completion via `hooks/play-sound.sh` |
| `scripts/` | Shell scripts and tooling (see below) |
| `scripts/ralph-loop.sh` | Legacy — single-item worker/reviewer loop (use orchestrator instead) |
| `scripts/ralph-worker-prompt.md` | Legacy — worker prompt for Ralph iterations |
| `scripts/ralph-reviewer-prompt.md` | Legacy — reviewer prompt for Ralph iterations |
| `scripts/plan-advance.sh` | Legacy — advances Ralph state to next task item |
| `scripts/ralph-check.sh` | Legacy — health check for Ralph Loop state |
| `scripts/create-exec-plan.sh` | Scaffolds a new exec-plan directory |
| `scripts/task-complete.sh` | Marks task done and plays completion sound |
| `scripts/statusline.sh` | Two-line terminal status bar for zsh |
| `scripts/terminal-session.sh` | Terminal session management |
| `scripts/terminal-ui/` | Ink-based terminal dashboard (TypeScript/React) — real-time agent monitoring |
| `scripts/terminal-ui-write.sh` | Writes structured data to terminal-ui |
| `scripts/log-server.py` | WebSocket log aggregation server |
| `scripts/log-client.sh` | Log client for structured event streaming |
| `scripts/orch-run.sh` | Orchestrator launcher — validates, initializes state, creates tmux session, starts engine |
| `scripts/orch-engine.sh` | Orchestrator engine — poll loop, worker spawning, review, SHIP/REVISE handling |
| `scripts/orch-state.sh` | Orchestrator state helpers — read/write state.json, worktree management, master state |
| `scripts/orch-parse-items.sh` | Parses plan.md progress log into JSON items with dependencies |
| `scripts/orch-review.sh` | Per-item reviewer — spawns reviewer agents, collects SHIP/REVISE decisions |
| `scripts/orch-verify.sh` | Completion criteria verifier — checks unchecked criteria after review |
| `scripts/orch-display.sh` | Opens tmux dashboard in a terminal window (macOS .command / Linux terminal) |
| `scripts/ralph-worktree.sh` | Legacy — worktree management for Ralph Loop |
| `scripts/review-advance.sh` | Legacy — per-item reviewer loop for Ralph iterations |
| `scripts/canon.sh` | Canon bootstrap wrapper |
| `scripts/canon-runner.sh` | Canon strategy runner |
| `scripts/plan-upload.sh` | Commits and pushes reviewed plans to GitHub. Supports `--push`, `--issues`, `--all` flags. |
| `scripts/canon-scaffold.sh` | Scaffolds Canon project structure |
| `docs/dev-flow.md` | 9-stage AI-driven development pipeline |
| `docs/ai-dev-pipeline.md` | Pipeline diagram (Mermaid) with stage descriptions |
| `docs/exec-plans/` | Execution plans: `active/` (in progress), `completed/` (archived), `tech-debt.md` |
| `docs/quality.md` | Quality grades by codebase area — updated by `/cleanup` |
| `docs/self-development.md` | How to apply fixes and features — manual and orchestrator workflows |
| `agents/` | Agent prompt templates (conductor, orch-worker, orch-verifier) |
| `tests/` | Test scripts for hooks and infrastructure |
| `ace/` | Ace agent notes — meeting notes, progress logs, tasks |
| `canon/` | **Canon layer** — prediction market development (see below) |

---

## Architecture: Core + Canon

This repo has two layers. **Core** is the root — generic AI development infrastructure
that any project can adopt. **Canon** is a subdirectory with its own context, skills,
hooks, and commands specifically for prediction market development.

```
claude-code-config/             ← Core (this repo root)
├── AGENTS.md                  ← Project configuration — single source of truth
├── CLAUDE.md                  ← Shim (points to AGENTS.md)
├── GEMINI.md                  ← Shim (points to AGENTS.md)
├── .cursorrules               ← Shim (points to AGENTS.md)
├── rules/                      ← Language rules (glob-matched, load only for matching file types)
├── commands/                   ← Global commands (apply-core, canon-init, core-init, fix-issue, review-pr, plan, cleanup, doc-garden)
├── hooks/                      ← Lifecycle hooks (enforce-package-manager, play-sound, orch-done-sync, structured-log, etc.)
├── sounds/                     ← MP3 sound files for task-completion audio cues
├── scripts/                    ← Orchestrator engine, terminal-ui, logging, Canon scripts
├── agents/                     ← Agent prompt templates (conductor, orch-worker, orch-verifier)
├── docs/                       ← Core docs (pipeline, harness patterns, architecture)
│   └── exec-plans/             ← Execution plans (active + completed)
├── skills/                     ← Core skills (app-legibility, development-patterns, sound-notifications)
│   └── patterns/               ← Development pattern extensions (topic-grouped)
├── tests/                      ← Test scripts for hooks and infrastructure
│
└── canon/                      ← Canon layer (prediction markets)
    ├── AGENTS.md               ← Canon-specific context and conventions
    ├── CLAUDE.md               ← Shim (points to canon/AGENTS.md)
    ├── commands/               ← Canon-specific commands
    ├── hooks/                  ← Canon-specific hooks (empty — future use)
    ├── skills/                 ← Canon-specific skills (market analysis, etc.)
    ├── agents/                 ← Canon-specific agents
    └── docs/                   ← Canon-specific docs (empty — future use)
```

### Separation principle

- **Core** skills/hooks/commands are generic: they apply to any AI-driven project.
- **Canon** skills/hooks/commands are domain-specific: prediction market patterns,
  market analysis agents, Oracle integrations, position management, etc.
- Canon **imports from Core** but never the reverse. Core must remain reusable.
- Improvements to Core cascade into Canon automatically.
- Development on Canon feeds back improvements to Core when patterns generalize.

### Installation model

- `/apply-core` — installs all Core artifacts globally (`~/.claude/`)

---

## OpenAI Harness Engineering

Reference: [Harness engineering](https://openai.com/index/harness-engineering/) (Ryan Lopopolo, OpenAI, Feb 11 2026)

Full gap analysis: `git show origin/openai-harness-patterns:docs/harness-engineering-improvements.md`

The harness is the infrastructure that makes AI-driven development reliable at scale.
Seven gaps were mapped from OpenAI's methodology to Claude Code equivalents.

### Implementation status

| # | Gap | Status | Artifact |
|---|-----|--------|----------|
| 1 | AGENTS.md as map + `~/.claude/rules/` for language rules | **Done** | `agent-template.md` + `rules/` |
| 2 | Execution plans as first-class artifacts | **Done** | `commands/plan.md` + `docs/exec-plans/` |
| 3 | Doc-gardening automation | **Done** | `commands/doc-garden.md` + PostToolUse hook |
| 4 | Custom linters with agent-friendly error messages | **Done** | `skills/custom-linter-authoring.md` + `canon/rules/domain-layering.md` |
| 5 | Agent-to-agent review convergence loop (up to 3 rounds) | **Done** | `commands/fix-issue.md` + `commands/review-pr.md` |
| 6 | Entropy / garbage collection automation | **Done** | `commands/cleanup.md` + `docs/quality.md` |
| 7 | Application legibility to agents | **Done** | `skills/app-legibility.md` |

### Implementation order

1. **Phase 1** — Gap 1 (AGENTS.md restructure) + Gap 5 (convergence loop). Foundational, no dependencies.
2. **Phase 2** — Gap 2 (execution plans) + Gap 6 (garbage collection). Depends on Phase 1 structure.
3. **Phase 3** — Gap 3 (doc-gardening) + Gap 4 (custom linters). Automation on top of Phase 1-2.
4. **Phase 4** — Gap 7 (app legibility). Aspirational, depends on adoption of earlier phases.

---

## AI-Driven Development Flow

Full description: `docs/dev-flow.md`
Pipeline diagram: `docs/ai-dev-pipeline.md`

Nine-stage pipeline with five quality layers:

```
TDD → Local AI Review → Video QA → Automated CI Review → Human Sign-off
```

| # | Stage | Actor | Type |
|---|-------|-------|------|
| 1 | Create Task | Lead / PM | Human |
| 2 | Create Spec | Developer + AI | Agent-controlled |
| 3 | Review Spec | Lead / Reviewer | Human |
| 4 | Implement (TDD) | Developer + Claude Code | Agent-controlled |
| 5 | Local AI Review | Developer + Claude Code | Agent-controlled |
| 6 | Record Video | Developer | Human |
| 7 | Submit PR | Developer + Claude Code | Agent-controlled |
| 8 | AI Code Review | CI / Claude Code | Automated |
| 9 | Sign-off | Lead / Reviewer | Human |

With harness patterns applied (Phase 1-3), the pipeline gains:
- **Context loading** before Stage 4 (lean AGENTS.md map + rules/)
- **Versioned specs** at Stage 2 (`docs/exec-plans/active/`)
- **Convergence loop** at Stage 8 (up to 3 review rounds)
- **Weekly `/cleanup`** cadence for drift detection
- **ast-grep lints + `/doc-garden`** before PR merge

---

## Active Work

### Current focus

Core harness (all 7 gaps), Canon layer, and the orchestrator are all shipped.
The orchestrator drives parallel worker agents via tmux with an Ink dashboard,
per-item review, completion criteria gates, and automatic SHIP/merge/archive.

Active work:

1. Add cleanup-on-PR hook — run `/cleanup` automatically when opening PRs.
2. Orchestrator Linux/WSL testing and platform fixes.
3. Dashboard viewport improvements (log-file fallback for post-completion browsing).

### Key concepts

| Concept | Description |
|---|---|
| **Commands** | Step-by-step procedures (`/fix-issue`, `/review-pr`). Slash-invoked. |
| **Skills** | Knowledge/style injected into context. Shape how Claude thinks. |
| **Hooks** | Shell scripts on lifecycle events. Guardrails, not walls. |
| **Agents** | Specialized subagents with focused personas and tool sets. |
| **Harness** | Infrastructure making AI-driven development reliable at scale. |

### Commands vs Skills vs Hooks vs Agents

- **Commands** run procedures: plan → implement → test → PR.
- **Skills** teach approaches: how to write ast-grep rules, how to analyze markets.
- **Hooks** enforce guardrails: block rm -rf, enforce package manager, log mutations.
- **Agents** are specialists: security auditor persona, market analysis persona.

---

## Working Conventions

### Operating mode (read first every session)

**Read `docs/agent-operating-mode.md`.** It defines the defaults for any agent working here: decide-and-move on reversible actions, self-verify before shipping (tsc + tests + lint + live smoke), cite with links, keep PRs focused, log follow-ups to `docs/exec-plans/tech-debt.md`. These rules hold across all sessions — do not re-derive them and do not ask the user to re-confirm them. If a rule is wrong for a situation, say so and propose an update to that doc.

### Canon TUI wiring

The Canon TUI (`DEGAorg/conductor-view`, separate repo) is not auto-wired to this repo's knowledge. See `canon/docs/tui-wiring.md` for what the TUI must do to access `canon-cli` commands and installed skills, and what it must NOT duplicate.

### Commit and push — prohibited

- **Never push directly to the project's trunk** (`main` / `master`, or whatever `github.pr_target` resolves to in this repo) — always open a PR.
- **Never force-push** — no `git push --force` or `git push -f`.
- **Never run `git reset --hard`** — use `git reset --soft` or revert instead.
- Hooks in `settings.json` block these patterns; do not attempt them.

### PR target

**Never hardcode `main`.** Resolve the PR target dynamically: `github.pr_target` from `dega-core.yaml` → `develop` if the remote has it → `main`. See `docs/agent-operating-mode.md` § "PR target resolution" for the exact shell recipe.

In this repo, `github.pr_target` is currently `ace-work`: open PRs against `ace-work`; the user promotes to `main` on their own schedule. Do not override this.

### Plans vs references

**Plans** (e.g. `ace/tasks/harness-implementation.md`) are already reasoned for best practices and desired outcomes. Follow them. They represent considered decisions — don't second-guess them without cause.

**References** (external docs, meeting notes, roadmaps, linked articles) inform the plan but are not directives. When working from reference material:

- Extract the *intent and constraints*, not a literal procedure.
- Actively look for better approaches: newer best practices, simpler implementations, patterns that fit the codebase better than the reference anticipated.
- Deviate when you have good reason. State the deviation and the reasoning so the human can follow along.
- The goal is the best solution for the objective — not fidelity to the source material.

### General

- Use `README.md` as source of truth for repo configuration explanations.
- Use `docs/dev-flow.md` as source of truth for the development pipeline.
- Use the harness gap analysis on `openai-harness-patterns` branch for implementation details.
- Core artifacts must remain project-agnostic. Domain logic goes in `canon/`.
- When a Canon pattern generalizes, promote it to Core.
- Explain decisions as you go — this repo is a learning system, not just a config dump.
- **Ace scope**: Phase I, no Arena. Core complete. Canon layer now active. See `../../canon-docs/Canon_MVP_Technical_Roadmap.md` for deliverables.

### Session start

1. Read `docs/agent-operating-mode.md` — the defaults for how to work here.
2. Check `docs/exec-plans/active/` for in-progress plans. Each plan is a directory — read `active/<slug>/plan.md`, find the first unchecked `[ ]` in the Progress log, and continue from there.
3. If the session is picking up a specific task (a GitHub issue, a PR review, a user request), proceed directly; do not re-plan from scratch.

### Orchestrator

**Automated / AFK sessions:** Use the orchestrator to drive parallel worker agents
with per-item review, completion criteria gates, and automatic SHIP/merge/archive:

```bash
bash ~/.claude/scripts/orch-run.sh docs/exec-plans/active/20260302-add-auth-endpoint
```

The plan path must point to a directory in `docs/exec-plans/active/` (format: `YYYYMMDD-slug`).
The orchestrator creates a tmux session, spawns worker agents in isolated worktrees,
reviews each item, and iterates until all items pass review and completion criteria are met.

**Per-project config:** Each project provides a `dega-core.yaml` at its root with
`max_iterations`, `warn_at_iteration`, and `success_criteria`. No per-project
scripts are needed — `/apply-core` installs all engine scripts globally to
`~/.claude/scripts/`.

**Exec-plan state files** (written by agents, read by the orchestrator):

| File | Writer | Reader | Purpose |
|---|---|---|---|
| `plan.md` | human / worker | worker, reviewer | task definition + progress checkboxes |
| `work-summary.txt` | worker | reviewer | what was done this iteration |
| `review-feedback.txt` | reviewer | worker | specific items to fix if REVISE |
| `review-result.txt` | reviewer | orchestrator | SHIP or REVISE decision |
