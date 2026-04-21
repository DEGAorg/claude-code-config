# Strategy Template Index

Source: `C2_Plantillas18Estrategias_AgentesAI.docx` and
`D2_Plantillas18_InyeccConfiguracion.docx`

Tracks which strategies from the 18-template library have been ported
into `canon/templates/` as runnable strategy directories.

## Status legend

- **Ported** — strategy.md + runner + config in `canon/templates/<dir>/`
- **Next** — selected for next implementation
- **Planned** — will be ported, not yet started
- **Deferred** — requires infrastructure not yet built (Phase 2/3)

---

## Group 1 — Pure Arbitrage

| ID | Name | Risk | Complexity | Scanner-ready? | Status | Notes |
|----|------|------|------------|----------------|--------|-------|
| ARB-01 | Binary Arb Buy (YES+NO < $1) | Very Low | Low | Yes | Ported | `strategies/arb-binary/` — scanner + risk checks |
| ARB-02 | Binary Arb Sell / Mint | Very Low | Medium | Yes | Planned | Requires CTF mint tx (4-6s latency) |
| ARB-03 | NegRisk Multi-condition Buy | Low | Medium | Yes | Ported | `strategies/arb-negrisk-buy/` — multi-leg scanner + risk checks |
| ARB-04 | NegRisk Multi-condition Sell | Medium | High | No | Deferred | Mint set + parallel sell, ~5% of markets |
| ARB-05 | Cross-Market Combinatorial | Medium | Very High | No | Deferred | LLM + IP Solver, $500k+ capital, Phase 3 |

## Group 2 — Minting & Market Making

| ID | Name | Risk | Complexity | Scanner-ready? | Status | Notes |
|----|------|------|------------|----------------|--------|-------|
| MINT-01 | Simple Mint $1,000 | Low | Low | No (exec) | Planned | Single cycle, +$13.57/cycle |
| MINT-02 | Split Mint $500+$500 | Very Low | Low | No (exec) | Planned | Two sub-cycles, adjustable between |
| MINT-03 | MM at Midpoint (Passive) | Medium | Medium | No (exec) | Planned | LP rewards only, loses on execution |
| MINT-04 | MM Premium +0.75c | Low | Medium | No (exec) | Ported | `strategies/mm-premium/` — scanner + risk checks |
| MINT-05 | MM Sweet Spot (Dynamic) | Low | Medium | No (exec) | Planned | Auto-adjusts offset 0.25-0.50c |
| MINT-06 | Compounding Multi-Cycle | Low | Low | No (exec) | Planned | Meta-strategy, reinvests MINT-01/04 |

## Group 3 — Active Trading

| ID | Name | Risk | Complexity | Scanner-ready? | Status | Notes |
|----|------|------|------------|----------------|--------|-------|
| TRADE-02 | Momentum Trading | Medium | Medium | Yes | Ported | Buy rising (10-30%), sell at ~50% |

## Group 4 — AI & Advanced Automation

| ID | Name | Risk | Complexity | Scanner-ready? | Status | Notes |
|----|------|------|------------|----------------|--------|-------|
| IA-01 | News Front-Running | Medium | High | Yes (scanner) | Deferred | Needs Reuters/AP APIs, <500ms, Phase 3 |
| IA-02 | Whale Copy-Trading | Medium | High | Yes (scanner) | Deferred | On-chain indexer, <2s replica, Phase 2 |
| IA-03 | Fair Value Model | Medium | High | Yes (scanner) | Deferred | Statistical model, 5pp divergence, Phase 2 |
| IA-04 | Arb Bot Types 1-3 | Low | Medium | Yes | Planned | Production bot of ARB-01/02/03 combined |
| IA-05 | LLM Dependency Detection | High | Very High | No | Deferred | $500k+, LLM+Solver, 15-35s latency |
| IA-06 | Bregman+Frank-Wolfe Optimizer | Low | High | N/A (layer) | Deferred | Transversal sizing layer, not standalone |

## Existing in repo

| Template | Source strategy | Status |
|----------|---------------|--------|
| `nba-momentum/` | Custom (cross-venue arb scanner) | Ported, dry-run only |
| `arb-binary/` | Binary Arb Buy (from C2 spec) | Ported, scanner + risk checks |

## Easiest to implement next (scanner-capable, low complexity)

1. **TRADE-02** — Momentum scanner. Watches price velocity + volume. Similar structure to nba-momentum (poll loop + signal detection).
2. **ARB-03** — NegRisk multi-condition scanner. Sums all YES prices in a NegRisk market, flags when sum < threshold.

## Implementation path

**Scanner (dry-run):** strategy.md + config + runner that imports
shared `canon/templates/runner.ts`. Logs signals to JSONL. No wallet
needed, no execution.

**Live execution:** Same strategy, flip `dryRun: false` in runner
config. Requires wallet auth + integration test passing for that
strategy's order type.
