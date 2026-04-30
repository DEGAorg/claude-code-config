# Plan: add risk outcome callback

## Files to touch

| File | Change |
|------|--------|
| `runner.ts` | Add `OnOutcome` type and call site |
| `entry.ts` | Wire OnOutcome to risk.recordOutcome |
