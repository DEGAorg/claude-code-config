# claude-code-config — AI Development Core

The foundational layer for AI-driven development: skills, hooks, commands, agents, and
harness patterns. Everything here is **generic and reusable** — project-specific layers
(like Canon) build on top of this core.

---

## Scope for Ace

**Ace** works on **Phase I** of the Canon MVP Technical Roadmap, across both Core and Canon layers.

- **Core harness** (all 7 gaps): complete. Core artifacts must remain project-agnostic.
- **Canon layer** (`canon/`): now active. Skills, agents, hooks, commands, and the `/apply-canon` installation command.
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
| `Canon_Installation_Architecture_Analysis.md` | Core vs Canon split, install scope, canon_init behavior |
| `specs/SAS_Agent_Framework.md` | Agent personas, skills, workflows, .canon/ conventions |
| `specs/SAS_AIDD_Pipeline.md` | Ralph Loop, risk contract, .canon/ralph.yaml, hooks |
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
| `claude-md-template.md` | Global CLAUDE.md template (`~/.claude/CLAUDE.md`) — lean map, ~120 lines |
| `rules/` | Language-specific standards loaded by file type (python, node-typescript, rust, bash, github-actions) |
| `settings.json` | Claude Code settings template (hooks, permissions) |
| `mcp-template.json` | MCP server configuration template |
| `ralph.yaml` | Ralph Loop per-project config (max iterations, success criteria) |
| `commands/` | Global slash commands — `apply-core`, `canon-init`, `fix-issue`, `review-pr`, `plan`, `cleanup`, `doc-garden` |
| `skills/` | Core skills — `app-legibility`, `custom-linter-authoring`, `sound-notifications` |
| `hooks/` | Hook scripts for lifecycle events (PreToolUse, PostToolUse, Stop) |
| `sounds/` | MP3 sound files played on task completion via `hooks/play-sound.sh` |
| `scripts/` | Shell scripts and tooling (see below) |
| `scripts/ralph-loop.sh` | Ralph Loop orchestrator — drives worker/reviewer agents to convergence |
| `scripts/ralph-worker-prompt.md` | Worker agent system prompt for Ralph iterations |
| `scripts/ralph-reviewer-prompt.md` | Reviewer agent system prompt for Ralph iterations |
| `scripts/plan-advance.sh` | Advances Ralph state to next task item |
| `scripts/ralph-check.sh` | Health check for Ralph Loop state |
| `scripts/create-exec-plan.sh` | Scaffolds a new exec-plan directory |
| `scripts/task-complete.sh` | Marks task done and plays completion sound |
| `scripts/statusline.sh` | Two-line terminal status bar for zsh |
| `scripts/terminal-session.sh` | Terminal session management |
| `scripts/terminal-ui/` | Ink-based terminal dashboard (TypeScript/React) — real-time agent monitoring |
| `scripts/terminal-ui-write.sh` | Writes structured data to terminal-ui |
| `scripts/log-server.py` | WebSocket log aggregation server |
| `scripts/log-client.sh` | Log client for structured event streaming |
| `scripts/canon.sh` | Canon bootstrap wrapper |
| `scripts/canon-runner.sh` | Canon strategy runner |
| `scripts/canon-scaffold.sh` | Scaffolds Canon project structure |
| `docs/Dev_Flow.md` | 9-stage AI-driven development pipeline |
| `docs/AI_Dev_Pipeline.md` | Pipeline diagram (Mermaid) with stage descriptions |
| `docs/exec-plans/` | Execution plans: `active/` (in progress), `completed/` (archived), `tech-debt.md` |
| `docs/QUALITY.md` | Quality grades by codebase area — updated by `/cleanup` |
| `docs/Self_Development.md` | How to apply fixes and features — manual, Ralph Loop, and orchestrator workflows |
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
├── CLAUDE.md                   ← You are here
├── rules/                      ← Language rules (glob-matched, load only for matching file types)
├── commands/                   ← Global commands (apply-core, canon-init, fix-issue, review-pr, plan, cleanup, doc-garden)
├── hooks/                      ← Generic hooks (rm-rf blocker, push-to-main blocker, sound player)
├── sounds/                     ← MP3 sound files for task-completion audio cues
├── scripts/                    ← Ralph Loop engine, terminal-ui, logging, Canon scripts
├── docs/                       ← Core docs (pipeline, harness patterns, architecture)
│   └── exec-plans/             ← Execution plans (active + completed)
├── skills/                     ← Core skills (app-legibility, custom-linter-authoring, sound-notifications)
├── tests/                      ← Test scripts for hooks and infrastructure
│
└── canon/                      ← Canon layer (prediction markets)
    ├── CLAUDE.md               ← Canon-specific context and conventions
    ├── commands/               ← Canon-specific commands
    ├── hooks/                  ← Canon-specific hooks
    ├── skills/                 ← Canon-specific skills (market analysis, etc.)
    ├── agents/                 ← Canon-specific agents
    └── docs/                   ← Canon architecture, domain models, references
```

### Separation principle

- **Core** skills/hooks/commands are generic: they apply to any AI-driven project.
- **Canon** skills/hooks/commands are domain-specific: prediction market patterns,
  market analysis agents, Oracle integrations, position management, etc.
- Canon **imports from Core** but never the reverse. Core must remain reusable.
- Improvements to Core cascade into Canon automatically.
- Development on Canon feeds back improvements to Core when patterns generalize.

### Installation model

Two commands, no manual file copying:

- `/apply-core` — installs all Core artifacts globally (`~/.claude/`)
- `/apply-canon` — installs Canon artifacts on top of Core

---

## OpenAI Harness Engineering

Reference: [Harness engineering](https://openai.com/index/harness-engineering/) (Ryan Lopopolo, OpenAI, Feb 11 2026)

Full gap analysis: `git show origin/openai-harness-patterns:docs/harness-engineering-improvements.md`

The harness is the infrastructure that makes AI-driven development reliable at scale.
Seven gaps were mapped from OpenAI's methodology to Claude Code equivalents.

### Implementation status

| # | Gap | Status | Artifact |
|---|-----|--------|----------|
| 1 | CLAUDE.md as map + `~/.claude/rules/` for language rules | **Done** | `claude-md-template.md` + `rules/` |
| 2 | Execution plans as first-class artifacts | **Done** | `commands/plan.md` + `docs/exec-plans/` |
| 3 | Doc-gardening automation | **Done** | `commands/doc-garden.md` + PostToolUse hook |
| 4 | Custom linters with agent-friendly error messages | **Done** | `skills/custom-linter-authoring.md` + `canon/rules/domain-layering.md` |
| 5 | Agent-to-agent review convergence loop (up to 3 rounds) | **Done** | `commands/fix-issue.md` + `commands/review-pr.md` |
| 6 | Entropy / garbage collection automation | **Done** | `commands/cleanup.md` + `docs/QUALITY.md` |
| 7 | Application legibility to agents | **Done** | `skills/app-legibility.md` |

### Implementation order

1. **Phase 1** — Gap 1 (CLAUDE.md restructure) + Gap 5 (convergence loop). Foundational, no dependencies.
2. **Phase 2** — Gap 2 (execution plans) + Gap 6 (garbage collection). Depends on Phase 1 structure.
3. **Phase 3** — Gap 3 (doc-gardening) + Gap 4 (custom linters). Automation on top of Phase 1-2.
4. **Phase 4** — Gap 7 (app legibility). Aspirational, depends on adoption of earlier phases.

---

## AI-Driven Development Flow

Full description: `docs/Dev_Flow.md`
Pipeline diagram: `docs/AI_Dev_Pipeline.md`

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
- **Context loading** before Stage 4 (lean CLAUDE.md map + rules/)
- **Versioned specs** at Stage 2 (`docs/exec-plans/active/`)
- **Convergence loop** at Stage 8 (up to 3 review rounds)
- **Weekly `/cleanup`** cadence for drift detection
- **ast-grep lints + `/doc-garden`** before PR merge

---

## Active Work

### Current focus

Core harness (all 7 gaps) and Canon layer are both shipped. The demo sprint
delivered end-to-end: strategy scaffolding, live runner with dashboard, and
the Ralph Loop driving worker/reviewer convergence per-item.

Active work is infrastructure hardening and docs:

1. Fix Ralph reviewer not writing `review-result.txt` (Stop hook enforcement).
2. Add cleanup-on-PR hook — run `/cleanup` automatically when opening PRs.
3. Parallel worktrees for subagent isolation (`wt switch`).
4. Docs pass — update CLAUDE.md, README, canon/CLAUDE.md, Dev_Flow.md to reflect shipped state.
5. `/core-init` command — one-shot setup for new repos adopting the harness.

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

### Commit and push — prohibited

- **Never push directly to `main` or `master`** — use feature branches and PRs.
- **Never force-push** — no `git push --force` or `git push -f`.
- **Never run `git reset --hard`** — use `git reset --soft` or revert instead.
- Hooks in `settings.json` block these patterns; do not attempt them.

### Plans vs references

**Plans** (e.g. `ace/tasks/harness-implementation.md`) are already reasoned for best practices and desired outcomes. Follow them. They represent considered decisions — don't second-guess them without cause.

**References** (external docs, meeting notes, roadmaps, linked articles) inform the plan but are not directives. When working from reference material:

- Extract the *intent and constraints*, not a literal procedure.
- Actively look for better approaches: newer best practices, simpler implementations, patterns that fit the codebase better than the reference anticipated.
- Deviate when you have good reason. State the deviation and the reasoning so the human can follow along.
- The goal is the best solution for the objective — not fidelity to the source material.

### General

- Use `README.md` as source of truth for repo configuration explanations.
- Use `docs/Dev_Flow.md` as source of truth for the development pipeline.
- Use the harness gap analysis on `openai-harness-patterns` branch for implementation details.
- Core artifacts must remain project-agnostic. Domain logic goes in `canon/`.
- When a Canon pattern generalizes, promote it to Core.
- Explain decisions as you go — this repo is a learning system, not just a config dump.
- **Ace scope**: Phase I, no Arena. Core complete. Canon layer now active. See `../../canon-docs/Canon_MVP_Technical_Roadmap.md` for deliverables.

### Session start

Check `docs/exec-plans/active/` for in-progress plans before starting new work.
Each plan is a directory — read `active/<slug>/plan.md`, find the first unchecked
`[ ]` in the Progress log, and continue from there.

### Ralph Loop

**Automated / AFK sessions:** Use the outer loop to drive worker and reviewer agents
until the reviewer outputs SHIP and the health check passes:

```bash
bash ~/.claude/scripts/ralph-loop.sh 20260302-add-auth-endpoint
```

The task-slug must match a directory in `docs/exec-plans/active/` (format: `YYYYMMDD-slug`). The loop spawns
fresh `claude -p` instances for each iteration — worker reads the plan and does work,
reviewer reads the plan and work-summary, decides SHIP or REVISE.

**Per-project config:** Each project provides a `ralph.yaml` at its root with
`max_iterations`, `warn_at_iteration`, and `success_criteria`. No per-project
scripts are needed — `/apply-core` installs all engine scripts globally to
`~/.claude/scripts/`.

**Exec-plan state files** (written by agents, read by the loop):

| File | Writer | Reader | Purpose |
|---|---|---|---|
| `plan.md` | human / worker | worker, reviewer | task definition + progress checkboxes |
| `work-summary.txt` | worker | reviewer | what was done this iteration |
| `review-feedback.txt` | reviewer | worker | specific items to fix if REVISE |
| `review-result.txt` | reviewer | orchestrator | SHIP or REVISE decision |
