# Orchestrator reviewer fixtures

Each fixture is a self-contained scenario with the inputs the reviewer
agent receives + the verdict it should produce.

## Layout

```
fixtures/
  gate-{a,b,c,d}-{pass,fail}/
    plan.md           # plan body excerpt (decision-log + progress log)
    diff.patch        # unified diff representing the PR changes
    repo/             # optional: snapshot of files the diff references,
                      # used by gates that need to read source
    expected.txt      # one line: PASS | FAIL | INCONCLUSIVE | WARN
                      # plus an optional "REASON: ..." second line
```

`run-fixtures.sh` walks every fixture, invokes the corresponding gate
script, and asserts the verdict matches `expected.txt`.

## Gate semantics

| Gate | Subject                                          | Verdict on miss |
|------|--------------------------------------------------|-----------------|
| A    | Integration-trace test for live-infra changes    | FAIL            |
| B    | Decision-log audit (each decision has evidence)  | FAIL or INCONCLUSIVE |
| C    | Named hooks/adapters have production callers     | FAIL            |
| D    | Mock-coverage delta vs. production caller shape  | WARN (advisory) |

Gate D is advisory in v1 — its FAIL is reported as WARN to avoid
blocking PRs while the false-positive rate is still being tuned.
