# Develop

@description Scaffold, implement, test, and iterate on a strategy until it passes QA.
@arguments $DESIGN_SPEC: Path to the strategy design specification (from /discover or provided directly)

Load agents: dev, qa.
Load skills: canon-conventions, backtesting, ralph-loop, risk-management.

Run every step below in order. Do not stop or ask for confirmation between steps.

## 1. Scaffold

As dev, scaffold the strategy project from the design specification.

```
canon_init --template <template-name-from-spec> --name <strategy-name>
```

Verify the scaffolded project contains:
- `src/strategy.ts`
- `src/types/TradeSignal.ts`
- `src/types/RiskInterface.ts`
- `.canon/ralph.yaml`
- `AGENTS.md`
- `package.json`

## 2. Implement

Implement strategy logic from the design specification.

Load skills: canon-conventions, risk-management.

Required:
- Implement `TradeSignal` interface in `src/strategy.ts`
- Implement `RiskInterface` in `src/types/RiskInterface.ts` with the hard limits
  from the design specification
- Follow domain layering: Types → Config → Repo → Service → Runtime → UI
- Use agent-oriented error messages (what/why/how format)

Do not skip RiskInterface. "I'll add it later" is not acceptable.

## 3. Test

Run the strategy against historical data:

```
canon_test --timeframe 30d
```

Review results. Note: canon_test completing without runtime errors is the
minimum bar — check backtest metrics against the design spec's success criteria.

## 4. Iterate (Ralph Loop)

If backtest criteria from the design spec are not met, run Ralph Loop:

```
canon_ralph
```

Configure `.canon/ralph.yaml` with:
- `success_criteria` matching the design spec's backtest targets
- `max_iterations: 20`
- `budget.max_spend: "$5.00"`
- `stop_hook: npm test && npm run lint && npx tsc --noEmit`

Load ralph-loop skill for configuration guidance.

Continue iterating until all criteria pass or budget is exhausted. If budget
exhausted without meeting criteria, surface the specific failing criteria for
human review before proceeding.

## 5. QA review

As qa, validate strategy quality.

Load skills: canon-conventions, backtesting, risk-management.

Check:
1. Code conventions: Domain layering respected, error messages follow what/why/how
2. Backtest results across multiple timeframes (7d, 30d, 90d if data available)
3. No overfitting signals (parameter stability, out-of-sample test)
4. RiskInterface correctly enforces hard limits (not just present — verify logic)
5. Edge cases: zero liquidity, API timeout, zero balance

Verdict:
- **Approved:** All criteria met → output QA-approved summary, proceed to register workflow
- **Return to dev:** Specific blocking issues found → list each issue with severity
  (blocking / advisory) and suggested fix → loop back to step 2

## Completion criteria

- Tests pass (`npm test`)
- Lint clean (`npm run lint`)
- Types valid (`npx tsc --noEmit`)
- Backtest criteria from design spec met
- QA approved (≥30 trades, profit_factor ≥1.0, no blocking biases)
- QA-approved strategy ready to hand off to register workflow
