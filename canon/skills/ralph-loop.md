---
name: ralph-loop
description: How to configure and operate Canon's Ralph Loop autonomous iteration
version: 1.0.0
domain: workflow
requires: [canon-conventions]
tools: [canon_ralph]
---

# Ralph Loop Operation

## Context
Load this skill when configuring or running Ralph Loop for strategy iteration.

## Core Knowledge

### What is Ralph Loop?
Ralph Loop is Canon's autonomous execution mode where agents iterate on a task until
success criteria are met — or budget is exhausted. It implements L4 (Autonomous)
agent behavior, distinct from the L3 (Tool-enabled) behavior of standard coding agents.

### How It Works
1. Agent receives task + success criteria
2. Agent executes task (write code, modify strategy, fix bugs)
3. Automated checks run (tests, lint, types)
4. If all criteria pass → SHIP (exit loop)
5. If criteria fail → Agent analyzes failures, plans fix, loops back to step 2
6. Budget/iteration limits prevent infinite loops

### Configuration (.canon/ralph.yaml)

```yaml
ralph_loop:
  success_criteria:
    - tests_pass
    - lint_clean
    - types_valid
    # Custom criteria:
    - custom: "backtest profit_factor > 1.2"

  max_iterations: 20

  budget:
    max_tokens: 200000
    max_spend: "$5.00"

  on_stuck: escalate_to_human

  stop_hook: |
    npm test && npm run lint && npx tsc --noEmit
```

### When to Use Ralph Loop
- Iterating on strategy logic until backtest metrics improve
- Fixing a failing test suite (let agent debug autonomously)
- Refactoring strategy code while maintaining test parity
- Any task with clear, verifiable success criteria

### When NOT to Use Ralph Loop
- Exploratory work with no clear success criteria
- Tasks requiring human judgment (strategy design, market selection)
- One-shot tasks (scaffolding, registration)

## Decision Frameworks

### Setting Good Success Criteria
- **Specific:** "tests_pass" not "code works"
- **Measurable:** "backtest profit_factor > 1.2" not "backtest looks good"
- **Achievable:** Don't set criteria the agent can't verify programmatically
- **Bounded:** Always set max_iterations and budget limits

## Common Mistakes
- **Vague criteria:** "Make it better" → Agent loops forever
- **No budget limit:** Agent burns $50 on a task worth $5
- **Too many criteria:** 10 criteria → Agent can't satisfy all simultaneously
- **Missing stop hook:** Agent exits without checking criteria
