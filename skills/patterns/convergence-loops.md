<!-- Sources: SAS_AIDD_Pipeline.md (Ralph Loop Mode, Ralph Loop Execution, RalphLoopConfig, spiralDetection, Escape Hatch Instructions, Prompt Best Practices, Philosophy) -->

# Convergence Loops

Patterns for autonomous agent iteration toward verifiable outcomes.

## Convergence loop

The agent iterates internally until verifiable success criteria are met:
work -> check -> fix -> check -> ship. No "fire and forget" with human
shepherding of failures.

## Two-gate verification

Gate 1: automated checks (tests, lint, types). Gate 2: cross-model LLM
review (a different model reviews the coder's work). Both must pass.

## Budget-bounded iteration

Always set max iterations and cost limits. Prevent infinite loops. Escalate
to a human when the budget is exhausted or the agent is stuck.

## Spiral detection

Circuit breakers for debugging loops:
- **Regression**: test count drops between iterations
- **Context churn**: same files edited repeatedly without progress
- **Lint regression**: error count increasing instead of decreasing

When detected: pause, escalate, or rollback.

## Escape hatch with documentation

When stuck after N iterations, document blockers — what's failing, what was
attempted, alternative approaches — rather than looping forever. The
documentation becomes the handoff to a human or a different agent.

## Clear completion criteria

Success must be verifiable and measurable. "tests_pass && lint_clean" not
"code works." Vague criteria cause infinite loops because the agent cannot
determine when to stop.

## Iteration over perfection

Don't aim for perfect on the first try. Failures are data — test failures
and lint errors are informative signals guiding the next iteration.
