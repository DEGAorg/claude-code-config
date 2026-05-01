# Plan: ARB-01 live execution

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| FOK limit orders for ARB-01 fills | GTC limit, market | ARB requires both legs to fill near-simultaneously |
| Idempotent USDC allowance with threshold check | Approve-on-every-submit | Avoids redundant gas |
