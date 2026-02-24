# Ralph Cycle

@description Autonomous iteration loop — execute, check, iterate until all success criteria pass or budget is exhausted.

Load agent: dev.
Load skills: ralph-loop, canon-conventions.

This workflow is triggered by `canon_ralph` or when Ralph Loop is configured in `.canon/ralph.yaml`.
Run every step below. The loop repeats steps 1-3 until the SHIP or ESCALATE condition is met.

## 1. Execute

Implement or modify code toward the success criteria defined in `.canon/ralph.yaml`.

Load skills: canon-conventions, ralph-loop.

Input:
- Task description
- Success criteria from `.canon/ralph.yaml`
- Feedback from previous iteration (if any)

Apply changes. Follow domain layering and error message conventions.

## 2. Check

Run the automated check suite defined in `ralph.yaml`'s `stop_hook`:

```
npm test && npm run lint && npx tsc --noEmit
```

Also run any custom criteria defined in `ralph.yaml` (e.g., `canon_test` with
backtest thresholds).

Record each criterion: pass ✓ or fail ✗ with the specific failure message.

## 3. Analyze (if checks failed)

If any check failed, analyze the failures before the next iteration:

1. Identify root cause of each failure
2. Plan the fix — be specific (which file, which line, what change)
3. Estimate confidence: Is this fix likely to resolve the failure?

If stuck (same failure across 3+ iterations without progress), escalate immediately
rather than burning more budget.

## 4. Loop or ship

Evaluate the current state:

**SHIP if:**
- All success criteria pass → Write a summary of what was accomplished, exit loop

**LOOP if:**
- Any criterion failed AND iteration count < `max_iterations` AND budget remaining
→ Apply the fix plan from step 3, return to step 1

**ESCALATE if:**
- Iteration count ≥ `max_iterations`, OR
- Budget exhausted (`max_tokens` or `max_spend` reached), OR
- Stuck (same failure ≥3 iterations without progress)
→ Document: which criteria are failing, what was tried, why it's stuck
→ Surface to human for intervention

## Completion criteria

- **SHIP:** All success criteria pass
- **ESCALATE:** Budget/iteration limit reached, or stuck — with full failure report
  for human review
