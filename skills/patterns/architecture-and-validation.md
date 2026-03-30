<!-- Sources: SAS_Agent_Framework.md (Canon Conventions skill, Three Non-Negotiable Constraints), SAS_AIDD_Pipeline.md (Worker Agent Execution Modes, DiagnosticStartup.runPreflight()) -->

# Architecture and Validation

Patterns for structural enforcement and runtime validation.

## Rigid domain layering

Enforce strict import direction between layers (e.g. Types -> Config ->
Repo -> Service -> Runtime -> UI). Each layer may only import from layers
to its left. Enforce mechanically with linters, not culturally with reviews.

## Agent-oriented error messages

All errors include three parts:
1. **What happened** — the failure condition
2. **Why it matters** — impact on the current task
3. **How to fix it** — actionable next step

Agents can act on structured errors; humans can understand them.

## Favor boring technology

Use well-understood, battle-tested tools. Avoid novel or exotic dependencies
unless they provide clear, justified value. Every new dependency is attack
surface and maintenance burden.

## Diagnostic preflight

Before entering any execution mode, validate the runtime environment:
worktree integrity, tool availability, model connectivity, resource access.
Fail before wasting iteration budget.

## Validate before serving

An agent that fails preflight reports diagnostics rather than entering a
doomed iteration loop. Better to fail immediately with clear diagnostics
than silently waste budget on an environment that can't succeed.
