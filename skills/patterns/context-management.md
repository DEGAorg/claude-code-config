<!-- Sources: SAS_Agent_Framework.md (How Context Flows, Layer 5: Orchestration, Handoff Protocol) -->

# Context Management

Patterns for routing the right information to agents at the right time.

## Progressive context loading

Start with a minimal entry point, load deeper context as needed. The flow:
user message -> lean TOC -> orchestration selects agent -> agent loads
relevant skills -> workflow triggers deeper docs.

## Context routing

Auto-load relevant skills and standards based on task type. Configuration
maps task categories to agents, skills, and workflows. An agent working on
tests loads testing skills; one working on deployment loads infra skills.

## Standards injection

Some rules apply to ALL agent interactions regardless of task. Configuration
declares always-loaded skills and universally enforced constraints. These
load before any task-specific context.

## Structured handoff protocol

When handing off between agents or phases, provide explicit context:
- What was done and what artifacts were produced
- What decisions were made and why
- What the next agent needs to know to continue

No implicit state. Every handoff is a self-contained briefing.
