# Development Patterns — Research Working Doc

Extracted from 4 canon-docs specs. Each pattern is stripped of domain terminology
and generalized for any AI-driven project.

---

## Group: Agent-as-Code (Versioned Agent Artifacts)

| # | Pattern | Source | Section |
|---|---------|--------|---------|
| 1 | **Agent-as-code** — Every agent persona, skill, and workflow is a versioned artifact in the repo. No hidden system prompts, no platform-locked configs. "If it's not in the repo, it doesn't exist." | SAS_Agent_Framework.md | Design Principles §1 |
| 2 | **Host-agnostic artifacts** — Agent personas are markdown, skills are markdown, workflows are YAML+markdown. Only tool integrations (MCP) are host-dependent. Framework works with any AI coding agent that can read files. | SAS_Agent_Framework.md | Design Principles §2 |
| 3 | **Composable skills** — Skills are modular, independently loadable knowledge modules. Agent personas compose skills. Workflows compose agents. Users create custom extensions that plug into the same system. | SAS_Agent_Framework.md | Design Principles §4 |
| 4 | **Progressive disclosure** — Agents discover what they need, when they need it. Entry point is a lean table of contents (~100 lines). Deep docs loaded on demand, not upfront. | SAS_Agent_Framework.md | Design Principles §5 |
| 5 | **SKILL.md manifest format** — Skills use YAML frontmatter declaring name, description, version, capabilities, tools. Lightweight, portable, interoperable across agent hosts. | SAS_Automation_Model.md | SKILL.md Manifest Format |
| 6 | **`.agents/` folder convention** — Canonical source of truth for agent config: AGENTS.md, commands/, hooks/, skills/. Standardizes organization across workspaces and enables interoperability. | SAS_Automation_Model.md | Workspace Configuration |

---

## Group: Context Management

| # | Pattern | Source | Section |
|---|---------|--------|---------|
| 7 | **Progressive context loading** — Start with minimal entry point, load deeper context as needed. User message → lean TOC → orchestration selects agent → agent loads relevant skills → workflow triggers. | SAS_Agent_Framework.md | How Context Flows |
| 8 | **Context routing** — Auto-load relevant skills/standards based on task type. Config maps task categories to agents, skills, and workflows. | SAS_Agent_Framework.md | Layer 5: Orchestration |
| 9 | **Standards injection** — Rules applied to ALL agent interactions regardless of task. Config declares always-loaded skills and universally enforced constraints. | SAS_Agent_Framework.md | Layer 5: Orchestration |
| 10 | **Structured handoff protocol** — When handing off between agents/phases, provide explicit context: what was done, what artifacts produced, what decisions made, what the next agent needs. | SAS_Agent_Framework.md | Handoff Protocol (all personas) |

---

## Group: Autonomous Iteration (Convergence Loops)

| # | Pattern | Source | Section |
|---|---------|--------|---------|
| 11 | **Convergence loop** — Agent iterates internally until verifiable success criteria are met, rather than "fire and forget" with human shepherding of failures. Work → check → fix → check → ship. | SAS_AIDD_Pipeline.md | Ralph Loop Mode |
| 12 | **Two-gate verification** — Gate 1: automated checks (tests, lint, types). Gate 2: cross-model LLM review (different model reviews coder's work). Both must pass before shipping. | SAS_AIDD_Pipeline.md | Ralph Loop Execution |
| 13 | **Budget-bounded iteration** — Always set max iterations and cost limits. Prevent infinite loops. Escalate to human when budget exhausted or stuck detected. | SAS_AIDD_Pipeline.md | RalphLoopConfig |
| 14 | **Spiral detection** — Circuit breakers for debugging loops: regression detection (test count drops), context churn (same files edited repeatedly), lint regression (errors increasing). Pause/escalate/rollback. | SAS_AIDD_Pipeline.md | spiralDetection |
| 15 | **Escape hatch with documentation** — When stuck after N iterations, document blockers (what's failing, what was attempted, alternative approaches) rather than looping forever. | SAS_AIDD_Pipeline.md | Escape Hatch Instructions |
| 16 | **Clear completion criteria** — Success must be verifiable and measurable. "tests_pass" not "code works". "profit_factor > 1.2" not "looks good". Vague criteria cause infinite loops. | SAS_AIDD_Pipeline.md | Ralph Loop Prompt Best Practices |
| 17 | **Iteration over perfection** — Don't aim for perfect on first try. Failures are data — test failures and lint errors are informative signals guiding the next iteration. | SAS_AIDD_Pipeline.md | Philosophy |

---

## Group: Quality Gates and Risk Contracts

| # | Pattern | Source | Section |
|---|---------|--------|---------|
| 18 | **Risk contract** — Machine-readable policy (JSON/YAML) governing which checks are required before merge, based on which files changed. High-risk paths get more gates. | SAS_AIDD_Pipeline.md | Risk Contract & Merge Policy |
| 19 | **Risk-tiered file paths** — Classify files by risk tier. Money-touching code, schemas, and core logic are high tier. Everything else is low tier. High tier gets full review; low tier gets fast checks. | SAS_AIDD_Pipeline.md | Risk Contract |
| 20 | **Preflight gate ordering** — Run cheap/fast checks first (policy, lint). Only trigger expensive checks (security scan, cross-model review) after preflight passes. Fail fast, save cost. | SAS_AIDD_Pipeline.md | Preflight gate ordering |
| 21 | **Current-head SHA discipline** — Review state is only valid when it matches the current commit SHA. Stale reviews from earlier iterations are rejected. Every push invalidates prior review state. | SAS_AIDD_Pipeline.md | Current-Head SHA Discipline |
| 22 | **Parallel review agents** — Multiple specialized review agents run in parallel: linting, security, testing, types, architecture. Aggregate results, present to human. | SAS_AIDD_Pipeline.md | Local PR System |
| 23 | **Cross-model review** — Different model reviews the coder's work. "Self-testing is self-consistency, not falsification." Cross-model catches different blind spots. | SAS_AIDD_Pipeline.md | Cross-Model Review Gate |

---

## Group: Task Decomposition and Orchestration

| # | Pattern | Source | Section |
|---|---------|--------|---------|
| 24 | **DAG task decomposition** — Decompose features into dependency graphs. Independent tasks run in parallel. Dependent tasks wait. Architect agent identifies which tasks can start immediately. | SAS_AIDD_Pipeline.md | Architect Agent |
| 25 | **Interview phase (spec refinement)** — Before planning, conduct structured dialogue to refine ambiguous input into precise, testable requirements. Surfaces 2-3 issues the user didn't consider. | SAS_AIDD_Pipeline.md | Interview Phase |
| 26 | **Tests-first decomposition** — Write failing tests BEFORE implementation. Coder's job is to make the tests pass. Tests become the specification. | SAS_AIDD_Pipeline.md | DAG-Aware Workflow |
| 27 | **Worktree isolation** — Each parallel agent works in its own git worktree. No shared working directories. Prevents conflicts between concurrent agents. | SAS_AIDD_Pipeline.md | Local PR System |

---

## Group: Layered Architecture Enforcement

| # | Pattern | Source | Section |
|---|---------|--------|---------|
| 28 | **Rigid domain layering** — Enforce strict import direction: Types → Config → Repo → Service → Runtime → UI. Each layer may only import from layers to its left. Enforce mechanically, not culturally. | SAS_Agent_Framework.md | Canon Conventions skill |
| 29 | **Agent-oriented error messages** — All errors include three parts: what happened, why it matters, how to fix it. Agents can act on structured errors; humans can understand them. | SAS_Agent_Framework.md | Canon Conventions skill |
| 30 | **Favor boring technology** — Use well-understood, battle-tested tools. Avoid novel/exotic dependencies unless they provide clear, justified value. | SAS_Agent_Framework.md | Three Non-Negotiable Constraints |

---

## Group: Open Core and Distribution

| # | Pattern | Source | Section |
|---|---------|--------|---------|
| 31 | **Open core boundary** — Open-source the framework that grows the ecosystem (tools, skills, templates). Monetize the platform that captures value (dashboard, execution, marketplace). | Canon_MVP_Technical_Roadmap.md | Open Core Distribution Strategy |
| 32 | **Dogfooding** — Build with your own tools. Internal usage drives quality. Patterns discovered while building become first-party features. | Canon_MVP_Technical_Roadmap.md | Why Alternative B |
| 33 | **Spec-grounded implementation** — Every implementation task must be grounded in a specification. If no spec exists, write one first. Specs prevent scope creep and miscommunication. | Canon_MVP_Technical_Roadmap.md | Harness Engineering Patterns |
| 34 | **Plugin-first development** — Build feature as plugin → test with users → promote to core if successful. Proves demand before committing to core integration. | SAS_Automation_Model.md | Dogfooding section |

---

## Group: Deferred Decisions and Unified Abstractions

| # | Pattern | Source | Section |
|---|---------|--------|---------|
| 35 | **Deferred decisions** — Don't force users to choose architecture upfront. Start building; defer packaging/targeting decisions until build time. Same code, different targets. | SAS_Automation_Model.md | Design Principles |
| 36 | **Manifest-driven packaging** — Single manifest file declares capabilities, dependencies, and build targets. Build-time packaging, not project-creation-time templates. | SAS_Automation_Model.md | canon.manifest.yaml |
| 37 | **Single abstraction** — Everything is one thing (a "Canon Automation"). Strategies, plugins, agents, services all follow the same development pattern. Reduces cognitive load. | SAS_Automation_Model.md | Design Principles |

---

## Group: Agent Adapter and Interoperability

| # | Pattern | Source | Section |
|---|---------|--------|---------|
| 38 | **Agent adapter interface** — Abstract over different AI coding agents. Core orchestration patterns are universal; only the hook mechanisms differ between hosts. | SAS_AIDD_Pipeline.md | Overview (Agent Adapter Interface) |
| 39 | **Symlink interoperability** — Agent config folder convention maps to multiple tools via symlinks. Same artifacts serve Claude Code, Codex, Cursor, etc. | SAS_Automation_Model.md | Interoperability |
| 40 | **Three-layer loop architecture** — Separate host hooks (looping), MCP tool (checking), and configuration. MCP tool can't control the agent; host hooks sit above the agent and can intercept exit. | Canon_MVP_Technical_Roadmap.md | Feature 3: Simplified Ralph Loop |

---

## Group: Persistent Agent Knowledge

| # | Pattern | Source | Section |
|---|---------|--------|---------|
| 41 | **AGENTS.md as persistent learnings** — Human-readable file accumulating discovered patterns, gotchas, conventions. Read at session start; successful iterations append new learnings. Compounding knowledge base. | SAS_Automation_Model.md | AGENTS.md |
| 42 | **Dual memory layers** — Human-readable markdown for explicit, curated knowledge (read at session start). Vector/graph store for implicit pattern retrieval across large histories. Complementary, not redundant. | SAS_Automation_Model.md | Why Both AGENTS.md AND Vector Memory |

---

## Group: Preflight and Validation

| # | Pattern | Source | Section |
|---|---------|--------|---------|
| 43 | **Diagnostic preflight** — Before entering any execution mode, validate runtime environment: worktree integrity, tool availability, model connectivity, resource access. Fail before wasting iteration budget. | SAS_AIDD_Pipeline.md | Worker Agent Execution Modes (preflight) |
| 44 | **Validate before serving** — Worker agent that fails preflight reports diagnostics rather than entering a doomed iteration loop. Better to fail immediately with clear diagnostics than silently waste budget. | SAS_AIDD_Pipeline.md | DiagnosticStartup.runPreflight() |

---

## Proposed Topic Groups (for extension files)

1. **agent-artifacts** — Patterns 1-6: agent-as-code, host-agnostic, composable skills, progressive disclosure, manifests, folder conventions
2. **context-management** — Patterns 7-10: progressive loading, context routing, standards injection, structured handoffs
3. **convergence-loops** — Patterns 11-17: autonomous iteration, two-gate verification, budgets, spiral detection, escape hatches, completion criteria
4. **quality-gates** — Patterns 18-23: risk contracts, tiered paths, preflight ordering, SHA discipline, parallel review, cross-model review
5. **task-orchestration** — Patterns 24-27: DAG decomposition, interview/spec refinement, tests-first, worktree isolation
6. **architecture-enforcement** — Patterns 28-30: domain layering, agent-oriented errors, boring technology
7. **distribution-strategy** — Patterns 31-34: open core, dogfooding, spec-grounded, plugin-first
8. **deferred-decisions** — Patterns 35-37: deferred decisions, manifest-driven, single abstraction
9. **interoperability** — Patterns 38-40: agent adapters, symlink conventions, three-layer loops
10. **agent-knowledge** — Patterns 41-42: persistent learnings, dual memory
11. **preflight-validation** — Patterns 43-44: diagnostic preflight, validate before serving

### Consolidation notes

Some groups are small (2-3 patterns) and could merge:
- **architecture-enforcement** (3) + **preflight-validation** (2) → "architecture-and-validation" (5)
- **deferred-decisions** (3) + **distribution-strategy** (4) → "distribution-and-packaging" (7)
- **interoperability** (3) + **agent-knowledge** (2) → "interoperability-and-memory" (5)

Suggested final grouping (7 extensions):
1. **agent-artifacts** (6 patterns)
2. **context-management** (4 patterns)
3. **convergence-loops** (7 patterns)
4. **quality-gates** (6 patterns)
5. **task-orchestration** (4 patterns)
6. **architecture-and-validation** (5 patterns: 28-30 + 43-44)
7. **distribution-and-packaging** (7 patterns: 31-37)
8. **interoperability-and-memory** (5 patterns: 38-42)

Total: 44 patterns across 8 extensions.
