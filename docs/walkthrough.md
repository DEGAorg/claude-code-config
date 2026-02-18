# Trail of Bits Claude Code Config — Walkthrough Guide

> **Purpose:** Quick-reference for learning this repo. Open in a Markdown previewer (VS Code,
> GitHub, etc.) and use the section headers to jump around.
> **Source of truth:** `README.md` (~600 lines) — this guide is a curated entry point, not a
> replacement.

---

## 1. What Is This Repo?

A **configuration and workflow starter pack** for [Claude Code](https://claude.ai/code) at Trail of
Bits. Instead of using Claude Code out of the box, you copy templates from this repo into
`~/.claude/` to get:

- Guardrails that block dangerous commands (`rm -rf`, force-push to main)
- Reusable autonomous workflows for fixing issues and reviewing PRs
- Shared coding standards applied to every session
- MCP tool integrations for docs lookup and web search

### Repo Map

| File / Dir | What it is |
|---|---|
| `README.md` | Full 600-line reference. **Read this.** |
| `claude-md-template.md` | Global CLAUDE.md — install at `~/.claude/CLAUDE.md` |
| `settings.json` | Claude Code settings (hooks, permissions, statusline) |
| `mcp-template.json` | MCP server config (Context7, Exa) |
| `scripts/statusline.sh` | Two-line terminal status bar |
| `commands/fix-issue.md` | `/fix-issue 123` command definition |
| `commands/review-pr.md` | `/review-pr 456` command definition |
| `hooks/` | Example hook scripts |
| `diagram.md` | Team pipeline discussion transcript |
| `starting.md` | Alberto's 3 onboarding tasks |

---

## 2. One-Time Setup

Copy these files into your home `~/.claude/` directory to activate everything:

```bash
# 1. Global CLAUDE.md — sets standards for every project
cp claude-md-template.md ~/.claude/CLAUDE.md

# 2. Settings — hooks, permissions, statusline
cp settings.json ~/.claude/settings.json

# 3. MCP servers — docs lookup + web search
cp mcp-template.json ~/.mcp.json
# Then edit ~/.mcp.json and replace "your-exa-api-key-here" with a real Exa key

# 4. Statusline script
cp scripts/statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh

# 5. Commands (slash commands available in every session)
mkdir -p ~/.claude/commands
cp commands/fix-issue.md ~/.claude/commands/
cp commands/review-pr.md ~/.claude/commands/
```

**Shell alias** — add to `~/.zshrc`:

```bash
alias claude-yolo="claude --dangerously-skip-permissions"
```

**Plugin marketplaces** (run once after installing Claude Code):

```bash
claude plugin marketplace add trailofbits/skills
claude plugin marketplace add trailofbits/skills-internal
claude plugin marketplace add trailofbits/skills-curated
```

> **Shortcut:** Running `/trailofbits:config` inside a Claude Code session walks you through
> all of the above interactively.

---

## 3. Core Mental Model: Commands vs Skills vs Hooks

These three concepts are the foundation of how Claude Code is extended and controlled.

| | Commands | Skills | Hooks |
|---|---|---|---|
| **What it is** | Step-by-step procedure in a markdown file | Expert knowledge injected into Claude's context | Shell script that fires at a lifecycle event |
| **Lives in** | `~/.claude/commands/*.md` | Plugin marketplace | `settings.json` or `~/.claude/hooks/` |
| **How to invoke** | `/fix-issue 123` (slash command) | `/plugin install <name>` then call it | Fires automatically (no user action) |
| **What it does** | Runs a multi-step autonomous workflow | Shapes how Claude *thinks* about a task | Intercepts tool calls — can block, log, or redirect |
| **Best for** | Repeatable procedures (fix issue, review PR) | Reusable expertise (Python style, audit method) | Guardrails and audit logging |

---

## 4. Commands

**Commands are markdown files.** Each file in `~/.claude/commands/` becomes a slash command.
They're parameterized (`$ISSUE_NUMBER`, `$PR_NUMBER`) and define numbered steps Claude follows
autonomously.

### `/fix-issue 123` — End-to-End Issue Resolution

| Step | What Claude does |
|---|---|
| 1. Read | Reads the GitHub issue thoroughly: requirements, linked PRs, discussion |
| 2. Plan | Writes `plan-issue-123.md`: files to change, approach, design decisions |
| 3. Implement | Makes all code changes following project CLAUDE.md standards |
| 4. Build / Test / Lint | Runs build → full test suite → linting → type checking; iterates until green |
| 5. Branch / Commit / Push | Creates branch `fix/issue-123`, deletes plan file, conventional commit, pushes |
| 6. Create PR | Opens PR with title <70 chars and "Closes #123" in description |
| 7. Self-review | Runs `/compound-engineering:workflows:review`, ranks findings P1–P4 |
| 8. Fix findings | Fixes or dismisses each P1–P3 finding with reasoning; separate commit |
| 9. Comment | Posts implementation summary + PR link on the original issue |

### `/review-pr 456` — Multi-Agent PR Review

| Step | What Claude does |
|---|---|
| 1. Read | `gh pr view`, checks out branch, reads diff and commit history |
| 2. Review | Parallel agents review; findings ranked P1 (blocks merge) / P2 / P3 / P4 |
| 3. Fix | Addresses all P1–P3; dismisses with reasoning or fixes |
| 4. Verify | Build → tests → lint/format/type-check |
| 5. Commit / Push | Separate commit: `fix: resolve code review findings for PR #456` |
| 6. Post summary | Comments on PR: findings by severity, fixed vs dismissed |

### Writing Your Own Command

Create any file in `~/.claude/commands/`. Example:

```markdown
@description Run security audit on a Solidity contract file.
@arguments $FILE: Path to the Solidity file

## 1. Static analysis
Run slither on $FILE and list all findings.

## 2. Manual review
Apply the audit-context-building skill line by line.
```

Then invoke with `/your-command-name path/to/Contract.sol`.

---

## 5. Hooks

**Hooks are shell scripts wired to Claude Code lifecycle events.** They intercept actions before
or after they happen and can block them.

### Lifecycle Events

| Event | Fires when | Can block? |
|---|---|---|
| `PreToolUse` | Before any tool call executes | **Yes** — exit 2 to block |
| `PostToolUse` | After a tool call succeeds | No (already ran) |
| `UserPromptSubmit` | When you submit a message | Yes |
| `Stop` | When Claude finishes a response | Yes (forces it to continue) |
| `SessionStart` | Session begins or resumes | No |
| `SubagentStart` / `SubagentStop` | Subagent spawns / finishes | Stop: yes |
| `TaskCompleted` | Task marked complete | Yes |

### Exit Codes

| Code | Meaning |
|---|---|
| `0` | Allow — proceed normally |
| `1` | Warn — non-blocking, stderr shown in verbose mode |
| `2` | **Block** — stderr message is fed back to Claude as an error |

Exit code 2 is the important one: Claude reads the error message and must change its approach.

### Examples in This Repo

**1. Block `rm -rf` (inline in `settings.json`)**

```json
{
  "matcher": "Bash",
  "hooks": [{
    "type": "command",
    "command": "CMD=$(jq -r '.tool_input.command'); if echo \"$CMD\" | grep -qE 'rm[[:space:]]+-[^[:space:]]*r[^[:space:]]*f'; then echo 'BLOCKED: Use trash instead of rm -rf' >&2; exit 2; fi"
  }]
}
```

Claude reads "BLOCKED: Use trash instead of rm -rf" and uses `trash` instead.

**2. Block direct push to main (inline in `settings.json`)**

```json
{
  "type": "command",
  "command": "CMD=$(jq -r '.tool_input.command'); if echo \"$CMD\" | grep -qE 'git[[:space:]]+push.*(main|master)'; then echo 'BLOCKED: Use feature branches, not direct push to main' >&2; exit 2; fi"
}
```

**3. Enforce package manager (`hooks/enforce-package-manager.sh`)**

Blocks `npm` commands in projects that have a `pnpm-lock.yaml`. PreToolUse on Bash.

```bash
[[ ! -f "${CLAUDE_PROJECT_DIR}/pnpm-lock.yaml" ]] && exit 0  # skip if not a pnpm project
if echo "$CMD" | grep -qE '^npm\s'; then
  echo "BLOCKED: This project uses pnpm, not npm. Use pnpm instead." >&2
  exit 2
fi
```

**4. Audit log for Google Apps Manager (`hooks/log-gam.sh`)**

PostToolUse hook that logs all GAM write verbs (create, delete, update, etc.) to a JSONL file,
skipping read operations. Useful for admin audit trails.

---

## 6. CLAUDE.md — Global and Project

### Two Layers

| | Global | Project |
|---|---|---|
| **Location** | `~/.claude/CLAUDE.md` | `CLAUDE.md` in repo root |
| **Scope** | Every Claude Code session everywhere | Only when working in that repo |
| **What to put here** | Universal conventions (code style, tools, philosophy) | Architecture, build/test commands, nav patterns, domain APIs |
| **Source** | `claude-md-template.md` in this repo | Write your own per project |

Both files are **merged at session start**. Project file adds to and can override global.

### Key Sections in the Global Template

**Philosophy (10 principles)** — the most important ones:
- No speculative features — only build what's asked
- No premature abstraction — three similar lines is better than a premature helper
- Replace, don't deprecate — remove old code, no backwards-compat shims
- Agent-native by default — design so agents can do anything users can (file-based state, avoid
  UI-only flows)
- Bias toward action — decide and move on easily reversed things; ask for interfaces and data
  models

**Hard code quality limits:**
- ≤ 100 lines per function
- Cyclomatic complexity ≤ 8
- ≤ 5 positional parameters
- 100-character line length
- Zero warnings — fix every warning from linters, type checkers, compilers, tests

**Per-language toolchains:**

| Language | Deps | Lint/Format | Types | Test |
|---|---|---|---|---|
| Python 3.13 | uv | ruff check + ruff format | ty (strict) | pytest |
| Node 22 ESM | pnpm | oxlint + oxfmt | tsc --noEmit | vitest |
| Rust (latest) | cargo | clippy -D warnings | — | cargo test |
| Bash | — | shellcheck + shfmt -d | — | — |

**Use `ast-grep` for code structure searches, `ripgrep` for literal string searches.**
**Never use `rm -rf` — use `trash` instead.**

### What to Put in a Project CLAUDE.md

```markdown
## Architecture
[Directory tree, key modules and their responsibilities]

## Build & Test
- `make dev` — start dev server
- `make test` — run full test suite
- `make lint` — check style

## Codebase Navigation
[ast-grep example patterns, key entry points]

## Domain-specific APIs and Gotchas
[Framework quirks, testing conventions, known pitfalls]
```

---

## 7. Skills

**Skills teach Claude *how to think*, not *what to do*.** They inject expert knowledge and
decision frameworks into the conversation context.

Install marketplaces first (see Setup above), then:

```bash
/plugin install ask-questions-if-underspecified
```

### Recommended Skills

| Skill | What it does | When to use |
|---|---|---|
| `ask-questions-if-underspecified` | Claude asks clarifying questions before starting work | Always — prevents wasted effort on misunderstood tasks |
| `modern-python` | Configures projects with uv, ruff, ty, pytest, prek | Starting or auditing a Python project |
| `audit-context-building` | Line-by-line analysis using First Principles + 5 Whys | Security audits, deep code review |
| `differential-review` | Security-focused review of code changes | PR reviews, auditing diffs |
| `superpowers:brainstorm` | Socratic questioning to refine ideas before implementation | Architecture decisions, feature design |
| `superpowers:systematic-debugging` | Structured debugging methodology | Hard-to-reproduce bugs |
| `compound-engineering:workflows:review` | Multi-agent parallel code review | Used internally by `/review-pr` |

---

## 8. MCP Servers

**MCP (Model Context Protocol)** lets Claude call external tools during a session. Think of it as
giving Claude access to APIs beyond its built-in capabilities.

### Config File: `~/.mcp.json`

```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"]
    },
    "exa": {
      "command": "npx",
      "args": ["-y", "exa-mcp-server"],
      "env": {
        "EXA_API_KEY": "your-exa-api-key-here"
      }
    }
  }
}
```

### The Two Servers in This Repo

| Server | What it does | API key? |
|---|---|---|
| **Context7** | Looks up current documentation for libraries (no hallucinated APIs) | No |
| **Exa** | Semantic web search returning clean LLM-optimized text | Yes — get from exa.ai |

### Important Setting

In `settings.json`:

```json
"enableAllProjectMcpServers": false
```

This means MCP servers in a project `.mcp.json` are **not enabled automatically** — you must
explicitly approve each one. Prevents a malicious repo from auto-loading a harmful MCP server.

---

## 9. `settings.json` Explained

The settings file lives at `~/.claude/settings.json`. Key sections:

### Environment Variables

```json
"env": {
  "DISABLE_TELEMETRY": "1",
  "DISABLE_ERROR_REPORTING": "1",
  "CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY": "1",
  "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
}
```

Telemetry off, agent teams (parallel subagents) on.

### Permissions Deny List

Blocks dangerous operations **without asking** — Claude simply cannot do these:

```json
"permissions": {
  "deny": [
    "Bash(rm -rf *)",          // Destructive delete
    "Bash(sudo *)",             // Privilege escalation
    "Bash(git push --force*)",  // Force push
    "Bash(git reset --hard*)",  // Discard local changes
    "Read(~/.ssh/**)",          // SSH private keys
    "Read(~/.aws/**)",          // AWS credentials
    "Read(~/.kube/**)",         // Kubernetes configs
    // ... and more credential paths
  ]
}
```

These are a **safety net** — Claude can still ask you to run something manually if needed, but
it can't do these autonomously.

### Hooks Wiring

```json
"hooks": {
  "PreToolUse": [{
    "matcher": "Bash",   // only fires for Bash tool calls
    "hooks": [{ "type": "command", "command": "..." }]
  }]
}
```

The `matcher` filters which tool triggers the hook. Use `"Bash"` for shell command hooks.

### Statusline

```json
"statusLine": {
  "type": "command",
  "command": "~/.claude/statusline.sh"
}
```

Runs the statusline script and displays a two-line status bar showing:
`model | folder | branch` / `[context bar] XX% | $0.00 | 2m30s | cache 80%`

---

## 10. Day-to-Day Cheatsheet

### Session Commands

| Command | What it does |
|---|---|
| `/clear` | Wipe conversation, reload CLAUDE.md fresh — **prefer this between tasks** |
| `/compact` | Compress conversation to save context (lossy — information is lost) |
| `Esc Esc` or `/rewind` | Roll back to any previous checkpoint in the session |
| `/fast` | Toggle 2.5× faster output at 6× cost — only for tight interactive loops |
| `/insights` | Analyze recent sessions, surface patterns to improve your workflow |
| `/output-style explanatory` | Add `★ Insight` blocks explaining code — useful when learning a new codebase |

### Context Management

- **Scope work to one session.** A focused session with a clear goal outperforms a sprawling one.
- **Prefer `/clear` over `/compact`.** `/clear` loses no information — it just reloads context.
  `/compact` compresses and is lossy.
- **Cut losses after two corrections.** If Claude is going the wrong direction, use `Esc Esc`
  to rewind rather than trying to correct mid-stream.
- **Stable context belongs in CLAUDE.md**, not in the conversation. Don't re-explain project
  conventions every session — write them once in CLAUDE.md.

### Web Browsing

| Need | Tool |
|---|---|
| Search the web for info | Exa MCP (`exa-mcp-server`) |
| Multi-step workflow on a public site | `agent-browser` skill (headless Chromium) |
| Access authenticated pages (Gmail, Jira, Google Docs) | Claude in Chrome extension |

---

## 11. Your Next Steps

From `starting.md`:

**Task 2 — Review the harness patterns branch**

Read the OpenAI harness methodology doc *without* switching branches:

```bash
git show origin/openai-harness-patterns:docs/harness-engineering-improvements.md
```

This file maps 7 gaps from [OpenAI's agent-first engineering methodology](https://openai.com/index/harness-engineering/)
to Claude Code equivalents.

**Task 3 — Write pipeline diagrams**

Two Mermaid `flowchart LR` diagrams to `docs/pipeline-diagrams.md`:

- **Diagram A** — The 9-stage team development pipeline from `diagram.md`
- **Diagram B** — Same pipeline with the 5 harness-pattern gaps applied (Gaps 1–6 excluding Gap 7)

Source of truth for the pipeline stages: `diagram.md` in this repo.

---

> **Tip:** After reading this guide, run `/trailofbits:config` in a Claude Code session to do
> the interactive setup, then work through Tasks 2 and 3 using this repo as context.
