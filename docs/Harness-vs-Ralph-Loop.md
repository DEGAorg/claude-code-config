# Harness Engineering vs Ralph Loop

A decision guide for understanding two complementary — but distinct — AI development
infrastructure concepts used in this repo and in Canon Phase I.

---

## TL;DR

| | Harness Engineering | Ralph Loop |
|---|---|---|
| **What it is** | The environment AI agents operate in | A runtime pattern for running agents repeatedly |
| **When it's active** | Always — it's the static setup | Only during autonomous iteration runs |
| **Analogy** | A test harness / CI infrastructure | A `while` loop with success criteria |
| **Problem solved** | Agent reliability per-session | Continuity and autonomy across sessions |
| **Either/or?** | No — they're complementary | Ralph Loop runs *inside* a harness |
| **Build order** | First | Second (depends on harness) |

---

## What Is a Harness?

A **harness** is the infrastructure surrounding an AI agent — everything between *"the
model knows what to do"* and *"the issue is actually resolved."*

Coined from OpenAI's internal experience building a million-line codebase entirely with
AI agents (Ryan Lopopolo, Feb 2026), harness engineering is the discipline of designing
that surrounding infrastructure so agents are reliable, consistent, and self-correcting.

### What a harness includes

```
┌─────────────────────────────────────────────────────────────┐
│                         HARNESS                             │
│                                                             │
│  Context Engineering                                        │
│  ├── AGENTS.md / CLAUDE.md  (map of the codebase)          │
│  ├── docs/ knowledge base   (design docs, exec plans)       │
│  └── Rules files            (language rules, conventions)   │
│                                                             │
│  Architectural Constraints                                  │
│  ├── Domain layering enforcement  (Types→Config→Service→UI) │
│  ├── Custom linters               (what/why/how errors)     │
│  └── Rigid structure              (boring technology wins)  │
│                                                             │
│  Entropy Reduction                                          │
│  ├── Doc-gardening agents   (stale docs, broken links)      │
│  ├── Code gardening agents  (principle drift detection)     │
│  └── /dega:cleanup command   (weekly GC cadence)             │
│                                                             │
│  Feedback Loops                                             │
│  ├── Convergence review loop (up to 3 rounds)               │
│  ├── Application legibility  (console streaming, snapshots) │
│  └── Execution plans         (versioned, agent-readable)    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
                    [ AI Agent runs here ]
```

### Key insight from practice

> *"Model choice matters less than harness optimization."*
> — can.ac, Feb 2026

Changing only the edit tool (the harness layer that processes model output) improved one
model from **6.7% → 68.3%** success rate. The model didn't change — only the environment
around it did.

The harness is the *static* setup. It exists before any agent run starts. It shapes what
the agent sees, how errors are communicated, and what structure the agent is allowed to
create. A poorly designed harness makes every agent run worse. A well-designed harness
makes agents consistently productive without human correction.

### Seven harness engineering gaps (this repo)

From the gap analysis against OpenAI's methodology:

| # | Gap | What it is |
|---|-----|------------|
| 1 | CLAUDE.md as map + `rules/` | Lean context file + language-specific rule files |
| 2 | Execution plans as artifacts | Versioned specs in `docs/exec-plans/` |
| 3 | Doc-gardening automation | Automated stale-doc detection and repair |
| 4 | Custom linters | ast-grep rules with *what/why/how* error messages |
| 5 | Convergence review loop | Agent-to-agent review up to 3 rounds |
| 6 | Entropy / garbage collection | `/dega:cleanup` command + golden principles |
| 7 | Application legibility | App-per-worktree, console error streaming |

---

## What Is the Ralph Loop?

The **Ralph Loop** is a runtime orchestration pattern: a `while` loop that runs an AI
agent repeatedly until success criteria pass or a budget limit is reached.

Named after Ralph Wiggum from The Simpsons (persistent despite setbacks), originating
from Geoffrey Huntley's work and widely adopted across Claude Code, Codex, and Amp
implementations.

### The core insight

Instead of one long session where context decays, you run the agent in discrete
iterations. Each iteration starts fresh but reads persisted state from the previous run.

```
┌──────────────────────────────────────────────────┐
│                  RALPH LOOP                      │
│                                                  │
│  while not DONE:                                 │
│    1. Read state  (prd.json, progress.md, git)   │
│    2. Pick next incomplete story                 │
│    3. Spawn fresh agent instance                 │
│    4. Agent implements + runs checks             │
│    5. Check success criteria                     │
│    6. If pass → mark done, commit, continue      │
│    7. If fail → log feedback, iterate            │
│    8. If max_iterations reached → escalate human │
│                                                  │
│  exit when all stories pass OR budget exceeded   │
└──────────────────────────────────────────────────┘
```

### How state persists between iterations

| Mechanism | What it carries |
|-----------|-----------------|
| Git history | Prior implementations, what was tried |
| `progress.md` | Learnings, patterns, gotchas from past runs |
| `prd.json` / `ralph.yaml` | Task list, success criteria, completion status |
| Codebase itself | What was built — the agent reads it fresh each time |

### Canon's three-layer Ralph Loop architecture

In Canon, the Ralph Loop is not a single tool — it's three cooperating layers:

```
┌─────────────────────────────────────────────────────┐
│  LAYER 1: HOST CONTINUATION HOOKS                   │
│  (claude-code/ralph-stop-hook.sh)                   │
│  Intercepts agent exit attempts. If criteria not    │
│  met → block exit, increment iteration, re-prompt.  │
├─────────────────────────────────────────────────────┤
│  LAYER 2: canon_ralph MCP TOOL  (the checking brain)│
│  Agent calls this during work to check criteria.    │
│  Returns: pass/fail, diagnostic feedback, iteration │
│  state, budget remaining.                           │
├─────────────────────────────────────────────────────┤
│  LAYER 3: CONFIGURATION (.canon/ralph.yaml)         │
│  success_criteria, max_iterations, check_command,   │
│  token_budget, spend_cap — all in one file.         │
└─────────────────────────────────────────────────────┘
```

---

## Key Differences

### 1. Static vs Dynamic

The harness is **static infrastructure** — it exists before any agent runs and persists
after. Think of it as the track the train runs on.

The Ralph Loop is **dynamic orchestration** — it runs when you invoke autonomous
iteration. Think of it as the train and its schedule.

### 2. Scope of control

| | Harness | Ralph Loop |
|---|---|---|
| Controls | What agent sees and can create | How many times agent runs + when to stop |
| Operates on | Context, tools, structure, errors | Iteration state, success criteria, budget |
| Time horizon | Always-on | Per-task session |
| Agent visibility | Agent is shaped by it (implicitly) | Agent interacts with it (explicitly, via `canon_ralph`) |

### 3. Problem solved

**Harness solves: per-session reliability**

Without a good harness, the agent has poor context, writes code in the wrong place,
gets confusing error messages it can't act on, and creates structural drift. These are
problems that appear *within* a single agent run.

**Ralph Loop solves: multi-session continuity and autonomy**

Without a Ralph Loop, the agent has to complete work in one session (context window
exhaustion), requires human handoffs between attempts, and can't autonomously retry
failed tasks. These are problems that appear *across* multiple agent runs.

### 4. Dependency direction

```
Ralph Loop  ──depends on──▶  Harness
```

The Ralph Loop runs *inside* a harness. A poorly designed harness (bad context, confusing
errors, no domain layering) makes every Ralph Loop iteration worse — the agent starts
each fresh iteration still confused. A good harness makes each Ralph Loop iteration more
productive because the agent loads clear context, gets actionable errors, and works in a
well-structured codebase.

---

## Common Misconceptions

**"Ralph Loop is part of the harness."**
Partially true in informal use, but they're distinct layers. The harness is the
environment; Ralph Loop is an execution pattern that runs in that environment. You can
have a harness without a Ralph Loop (most development is single-session). You cannot
have a reliable Ralph Loop without a harness.

**"I need to choose between them."**
No. They address different problems. You need both. Implement harness first because it's
foundational; Ralph Loop depends on it.

**"Ralph Loop is just a bash while loop."**
The core mechanism is, yes. But the value is in the success criteria evaluation, budget
controls, fresh-context-per-iteration pattern, and the persistence layer (git + progress
files). The loop itself is simple; the contract around it is what matters.

**"The harness is the agent's instructions."**
Instructions (prompts, skills, commands) are part of the harness, but the harness is
larger — it also includes tools, edit mechanisms, error format, architectural constraints,
and entropy reduction. A harness shapes how the agent thinks and what it's allowed to do,
not just what it's asked to do.

---

## Decision Guide: What to Implement First

### If your problem is: the agent makes mistakes every session

→ **Fix the harness first.**

- Is `AGENTS.md` / `CLAUDE.md` clear and lean (≤ 100 lines map, not encyclopedia)?
- Are your linter error messages actionable (*what* is wrong, *why*, *how* to fix)?
- Is domain layering enforced from commit 1?
- Does the agent have access to the right context without noise?

Fixing these will make every agent run — with or without a loop — more reliable.

### If your problem is: the agent can't finish complex tasks in one session

→ **Implement Ralph Loop.**

- Does your task exceed a single context window?
- Do you need autonomous retries without human handoffs?
- Do you need budget/iteration controls?

Ralph Loop solves context decay and enables autonomous multi-iteration development.

### In Canon Phase I: both, in this order

```
Week 1-2:  Harness foundations
           ├── Domain layering (Types→Config→Service→UI)
           ├── AGENTS.md as TOC (not encyclopedia)
           ├── docs/ structure (design-docs/, exec-plans/)
           └── Simplified Ralph Loop (canon_ralph + host hooks + ralph.yaml)
                ↑
                Ralph Loop is Week 1-2 too — it's simple enough to scaffold early,
                but it runs on top of the harness structure being set up in parallel.

Week 3-4:  Harness depth
           ├── Ralph Loop polish (budget controls, Cursor + OpenCode hooks)
           ├── Agent-oriented linter error messages
           └── Runtime bridge (minimal: console streaming)
```

---

## Conclusion: Not Alternatives, Both Required

The framing of "harness vs Ralph Loop" implies a choice between two competing approaches.
That framing is wrong. They solve different problems at different layers and you will need
both in any serious AI-driven development setup.

**Harness engineering** is not optional. Without it, agents are unreliable regardless of
what loop you wrap around them. A poorly designed harness means every iteration — first
or fifteenth — starts from a position of poor context, confusing errors, and structural
drift. You cannot loop your way out of a bad harness.

**Ralph Loop** is not optional either. Without it, agents are limited to what fits in a
single context window, require human handoffs between attempts, and cannot autonomously
recover from partial failures. The harness alone does not give you autonomous iteration.

They are as different as a **test harness** and a **CI pipeline**. A test harness is the
infrastructure that makes a test runnable and repeatable. A CI pipeline is the
orchestration that runs those tests automatically on a schedule. You would never say
"should I use a test harness or a CI pipeline?" — the CI pipeline runs *on top of* the
test harness. Same here.

```
Harness  =  the track
Ralph    =  the train
```

Build the track first. Then run the train.

---

## References

- [OpenAI: Harness Engineering](https://openai.com/index/harness-engineering/) — Ryan Lopopolo, Feb 2026
- [Martin Fowler: Harness Engineering](https://martinfowler.com/articles/exploring-gen-ai/harness-engineering.html) — Birgitta Böckeler's analysis
- [The Harness Problem](https://blog.can.ac/2026/02/12/the-harness-problem/) — how changing the harness alone drove 6.7% → 68.3% success rate
- [snarktank/ralph](https://github.com/snarktank/ralph) — original Ralph Loop implementation
- [ralph-claude-code](https://github.com/frankbria/ralph-claude-code) — Claude Code specific implementation
- [Chief: The Ralph Loop](https://minicodemonkey.github.io/chief/concepts/ralph-loop.html) — pattern documentation
- `../../canon-docs/Canon_MVP_Technical_Roadmap.md` — Canon Phase I scope and Ralph Loop three-layer architecture spec
- `docs/harness-engineering-improvements.md` (on `openai-harness-patterns` branch) — full gap analysis
