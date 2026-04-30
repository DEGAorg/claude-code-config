# Plan: live executor split

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Separate `live-executor` and `live-positions` modules | Single combined module | Each has distinct dependencies and test surface |
| FOK limit orders for ARB-01 fills | GTC limit, market | Prevents one-sided exposure |
