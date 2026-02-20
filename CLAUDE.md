# claude-code-config — AI Development Core

The foundational layer for AI-driven development: skills, hooks, commands, agents, and
harness patterns. Everything here is **generic and reusable** — project-specific layers
(like Canon) build on top of this core.

---

## Scope for Ace

**Ace** works on **Phase I** of the Canon MVP Technical Roadmap. All prompts and work must:

- **Focus on Phase I deliverables**: Canon Agent Framework (MCP Server), Ralph Loop, pmxt adapter, agent configurations, harness engineering (all gaps 1–7), execution hardening — everything that is code/infrastructure.
- **Ignore Canon Arena**: No Arena web dashboard, no Arena frontend, no leaderboard UI, no UI work of any kind. Arena is out of scope for Ace.

Source of truth for Phase I scope: `docs/Canon_MVP_Technical_Roadmap.md`

---

## Repo Map

| Path | Purpose |
|---|---|
| `README.md` | Full reference guide — source of truth for all config explanations |
| `claude-md-template.md` | Global CLAUDE.md template (`~/.claude/CLAUDE.md`) — lean map, ~120 lines |
| `rules/` | Language-specific standards loaded by file type (python, node-typescript, rust, bash, github-actions) |
| `settings.json` | Claude Code settings template (hooks, permissions) |
| `mcp-template.json` | MCP server configuration template |
| `scripts/statusline.sh` | Two-line terminal status bar for zsh |
| `commands/` | Global slash commands (`fix-issue`, `review-pr`, `plan`, `cleanup`, `doc-garden`) |
| `skills/` | Core skills (`custom-linter-authoring`) |
| `hooks/` | PreToolUse / PostToolUse hook scripts |
| `docs/Dev_Flow.md` | 9-stage AI-driven development pipeline |
| `docs/AI_Dev_Pipeline.md` | Pipeline diagram (Mermaid) with stage descriptions |
| `docs/exec-plans/` | Execution plans: `active/` (in progress), `completed/` (archived), `tech-debt.md` |
| `docs/QUALITY.md` | Quality grades by codebase area — updated by `/cleanup` |
| `ace/Pipeline_Diagrams.md` | Team pipeline + harness-enhanced diagrams |
| `canon/` | **Canon layer** — prediction market development (see below) |
| `docs/Canon_MVP_Technical_Roadmap.md` | **Source of truth** for Phase I scope and deliverables |

---

## Architecture: Core + Canon

This repo has two layers. **Core** is the root — generic AI development infrastructure
that any project can adopt. **Canon** is a subdirectory with its own context, skills,
hooks, and commands specifically for prediction market development.

```
claude-code-config/             ← Core (this repo root)
├── CLAUDE.md                   ← You are here
├── rules/                      ← Language rules (glob-matched, load only for matching file types)
├── commands/                   ← Generic commands (fix-issue, review-pr, plan, cleanup)
├── hooks/                      ← Generic hooks (rm-rf blocker, push-to-main blocker)
├── docs/                       ← Core docs (pipeline, harness patterns, architecture)
│   └── exec-plans/             ← Execution plans (active + completed)
├── skills/                     ← Core skills (to be created)
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
| 7 | Application legibility to agents | **To do** | App-legibility skill |

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

### Current focus (Ace: Phase I, no Arena)

1. Establish this repo as the AI Development Core with clear boundaries.
2. Scaffold `canon/` subdirectory structure for prediction market development (no Arena — backend/agent framework only).
3. Implement all harness engineering gaps (1–7) in priority order.
4. Build Canon Agent Framework: MCP Server, Ralph Loop, pmxt adapter, agent configs.
5. Build `/apply-core` and `/apply-canon` installation commands.

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
- **Ace scope**: Phase I, no Arena. See `docs/Canon_MVP_Technical_Roadmap.md` for deliverables.
