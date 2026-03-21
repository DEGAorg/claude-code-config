<!-- Sources: SAS_AIDD_Pipeline.md (Architect Agent, Interview Phase, DAG-Aware Workflow, Local PR System) -->

# Task Orchestration

Patterns for decomposing work and coordinating parallel agents.

## DAG task decomposition

Decompose features into dependency graphs. Independent tasks run in
parallel. Dependent tasks wait. An architect agent identifies which tasks
can start immediately and which must be sequenced.

## Interview phase (spec refinement)

Before planning, conduct a structured dialogue to refine ambiguous input
into precise, testable requirements. This surfaces 2-3 issues the user
didn't consider and prevents wasted iteration budget.

## Tests-first decomposition

Write failing tests BEFORE implementation. The coder's job is to make the
tests pass. Tests become the specification — they are unambiguous, verifiable,
and machine-checkable.

## Worktree isolation

Each parallel agent works in its own git worktree. No shared working
directories. This prevents merge conflicts between concurrent agents and
allows independent iteration on each task.
