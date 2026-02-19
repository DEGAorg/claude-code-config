# claude-code-config

Trail of Bits' Claude Code configuration repo — commands, hooks, settings templates, and MCP
configuration. Alberto is onboarding here: explain as you go, don't just implement.

---

## Repo Map

| File / Dir | Purpose |
|---|---|
| `README.md` | Full reference guide (~600 lines) — source of truth for all repo explanations |
| `claude-md-template.md` | Global CLAUDE.md template to install at `~/.claude/CLAUDE.md` |
| `settings.json` | Claude Code settings template (hooks, permissions) |
| `mcp-template.json` | MCP server configuration template |
| `scripts/statusline.sh` | Two-line terminal status bar for zsh/fish |
| `commands/fix-issue.md` | End-to-end issue resolution command (8 steps: plan → implement → test → PR → review → fix → comment) |
| `commands/review-pr.md` | Multi-agent PR review + fix command (5 steps) |
| `hooks/` | Example PreToolUse / PostToolUse hook scripts |
| `diagram.md` | Team pipeline discussion transcript — source of truth for pipeline diagrams |
| `starting.md` | Alberto's task list (3 tasks) |

---

## Active Tasks (Alberto)

### Task 1 — Understand the repo
Read `README.md` end-to-end. It covers commands, skills, hooks, settings, MCP servers, and
the global CLAUDE.md template. Use it as the primary reference for any question about how
this repo works.

### Task 2 — Review the `openai-harness-patterns` branch
Branch adds `docs/harness-engineering-improvements.md` — 7 gaps mapped from OpenAI's
agent-first methodology to Claude Code equivalents.

Access the file without switching branches:
```
git show origin/openai-harness-patterns:docs/harness-engineering-improvements.md
```

Reference article: https://openai.com/index/harness-engineering/
(Ryan Lopopolo, OpenAI, Feb 11 2026)

The 7 gaps in that document:
- **Gap 1** — Restructure CLAUDE.md as a map (~100 lines) + `~/.claude/rules/` for language rules
- **Gap 2** — Execution plans as first-class artifacts (`docs/exec-plans/active/`)
- **Gap 3** — Doc-gardening automation (`/doc-garden` command)
- **Gap 4** — Custom linters with agent-friendly error messages (ast-grep rules)
- **Gap 5** — Agent-to-agent review convergence loop (up to 3 rounds)
- **Gap 6** — Entropy / garbage collection automation (`/cleanup` weekly cadence)
- **Gap 7** — Application legibility to agents (per-worktree boot, structured logs)

we can change branch if needed or bering the file to current branch.

### Task 3 — Produce pipeline diagrams
Write two Mermaid `flowchart LR` diagrams to `docs/pipeline-diagrams.md`:
- **Diagram A** — The team development pipeline from `diagram.md`
- **Diagram B** — Same pipeline with the 5 harness-pattern gaps applied (Gaps 1–6 excluding Gap 7)

Source of truth for Diagram A: `diagram.md` (conversation transcript).
Output file: `docs/pipeline-diagrams.md` (create `docs/` if it doesn't exist).

We need a session to fix the final version of the diagrams.

---

## Key Concepts

### Commands vs Skills vs Hooks
- **Commands** (`/fix-issue`, `/review-pr`) — step-by-step procedures stored in
  `~/.claude/commands/*.md`. Slash-invoked: `/fix-issue 42`.
- **Skills** — knowledge/style injected into Claude's context (e.g., how to write ast-grep
  rules). Live in a marketplace, installed via `/plugin install`.
- **Hooks** — shell scripts that run on Claude Code events (`PreToolUse`, `PostToolUse`).
  Used for guardrails: block `rm -rf`, enforce package manager, log tool calls.

### Global vs Project CLAUDE.md
- **Global** (`~/.claude/CLAUDE.md`) — applies to every project. Use for universal conventions.
- **Project** (`.claude/CLAUDE.md` or `CLAUDE.md` in repo root) — project-specific context.
  Project file is merged with global at session start.

### Team pipeline (from `diagram.md`)
Nine-stage flow with human checkpoints. See Diagram A in `docs/pipeline-diagrams.md` for the
full annotated version. Stages: create task → create spec → review spec → implement locally →
dev reviews AI code-review prompt → record video → submit PR → AI code review activates →
specify human interaction points and owners.

---

## Diagram Specifications

### Diagram A — Team pipeline (flowchart LR)

| # | Stage | Responsible | Human? |
|---|---|---|---|
| 1 | Create Task | Team lead / PM | Yes |
| 2 | Create Spec | Developer | Yes |
| 3 | Review Spec | Reviewer / Lead | Yes |
| 4 | Implement locally | Developer (per dev) | Yes |
| 5 | Dev reviews AI code-review prompt | Developer | Yes |
| 6 | Record walkthrough video | Developer | Yes |
| 7 | Submit PR (code + video) | Developer | Yes |
| 8 | AI code review activates on PR | Claude Code (automated) | No |
| 9 | Specify human interaction points & owners | Lead | Yes |

Human stages: 1, 2, 3, 4, 5, 6, 7, 9. Automated stage: 8.

### Diagram B — With harness patterns (Gaps 1, 2, 3, 4, 5, 6)
Same backbone plus:
- **Gap 1** — "Context Load" node (lean CLAUDE.md map + `~/.claude/rules/`) before stage 4
- **Gap 2** — Stage 2 spec file becomes versioned `docs/exec-plans/active/spec-N.md`
- **Gap 5** — Convergence review loop at stage 8 (up to 3 rounds, back-edge)
- **Gap 6** — `/cleanup` weekly cadence as dashed subgraph
- **Gaps 3+4** — ast-grep custom lints + `/doc-garden` scan before PR merge

---

## Working with Alberto

- Use `README.md` as source of truth for repo explanations — don't paraphrase from memory.
- Read `diagram.md` for diagram content — match the pipeline exactly, don't invent stages.
- Write diagrams to `docs/pipeline-diagrams.md`.
- Prefer Exa MCP for web lookups.
- Explain decisions as you go — Alberto is learning the system, not just executing tasks.
