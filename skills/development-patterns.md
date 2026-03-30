# Development Patterns for AI-Driven Projects

Patterns extracted from real AI development methodology specs and generalized
for any AI-driven project. Use this skill when designing agent workflows,
orchestration systems, or harness infrastructure.

---

## Pattern Index

Each topic links to an extension file with full pattern descriptions.

| Extension | Patterns | When to use |
|-----------|----------|-------------|
| [agent-artifacts](patterns/agent-artifacts.md) | Agent-as-code, host-agnostic artifacts, composable skills, progressive disclosure, skill manifests, workspace conventions | Designing agent config, skill systems, persona frameworks |
| [context-management](patterns/context-management.md) | Progressive context loading, context routing, standards injection, structured handoff | Building context pipelines, agent orchestration layers |
| [convergence-loops](patterns/convergence-loops.md) | Convergence loop, two-gate verification, budget-bounded iteration, spiral detection, escape hatches, completion criteria, iteration over perfection | Implementing autonomous agent loops |
| [quality-gates](patterns/quality-gates.md) | Risk contract, risk-tiered paths, preflight ordering, SHA discipline, parallel review, cross-model review | Designing review pipelines, merge policies |
| [task-orchestration](patterns/task-orchestration.md) | DAG decomposition, interview phase, tests-first decomposition, worktree isolation | Planning and parallelizing agent work |
| [architecture-and-validation](patterns/architecture-and-validation.md) | Domain layering, agent-oriented errors, boring technology, diagnostic preflight, validate-before-serve | Enforcing structural rules, runtime validation |
| [distribution-and-packaging](patterns/distribution-and-packaging.md) | Open core boundary, dogfooding, spec-grounded implementation, plugin-first, deferred decisions, manifest-driven packaging, single abstraction | Packaging and distributing agent frameworks |
| [interoperability-and-memory](patterns/interoperability-and-memory.md) | Agent adapter interface, symlink interop, three-layer loop, persistent learnings, dual memory | Cross-tool compatibility, agent knowledge persistence |

## Sourcing Methodology

All patterns were extracted from four methodology specs:

- `SAS_Agent_Framework.md` — agent-as-code, progressive disclosure, composable skills
- `SAS_AIDD_Pipeline.md` — convergence loops, risk contracts, cross-model review
- `SAS_Automation_Model.md` — workspace conventions, interoperability, deferred decisions
- `Canon_MVP_Technical_Roadmap.md` — open core boundary, dogfooding, spec-grounded implementation

Each extension file has an HTML comment header citing its specific sources.
Domain-specific terminology was stripped; only generic development patterns remain.

## How to Use

1. **Scan the index** above to find the topic relevant to your task.
2. **Read the extension** for full pattern descriptions and guidance.
3. **Apply patterns** that fit — not all patterns apply to every project.

## Growth Rule

To add a new pattern:

1. Identify the source spec and the generic principle.
2. Strip domain-specific terminology — the pattern must apply to any AI project.
3. Add it to the appropriate extension file (or create a new one if no topic fits).
4. Keep each extension under 80 lines. Split if it grows beyond that.
5. Update the index table above.
