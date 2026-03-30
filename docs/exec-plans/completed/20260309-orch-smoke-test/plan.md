# Orchestrator Smoke Test

Fake plan to exercise the full orchestrator pipeline: parsing, dependency
waves, parallel workers, done-files, final review, and SHIP/REVISE cycle.

All work happens in a temporary directory (`/tmp/orch-smoke-test/`) so the
repo stays clean. Each item creates a small file — easy to verify and clean up.

## Acceptance criteria

- All 8 items complete with done-files written
- Dependency ordering respected (wave 2 waits for wave 1, etc.)
- Final review passes (SHIP)
- Cleanup: `rm -rf /tmp/orch-smoke-test/` after test

## Progress log

- [x] Create project scaffold: mkdir -p /tmp/orch-smoke-test/{src,lib,tests,docs} and write /tmp/orch-smoke-test/README.md with project name "Smoke Test"
- [x] Write math library: create /tmp/orch-smoke-test/lib/math.sh with functions add(), subtract(), multiply() that echo results (deps: 1)
- [x] Write string library: create /tmp/orch-smoke-test/lib/string.sh with functions uppercase(), lowercase(), reverse() that use tr/rev (deps: 1)
- [x] Write config loader: create /tmp/orch-smoke-test/src/config.sh that reads /tmp/orch-smoke-test/.env (KEY=VALUE format) into shell vars (deps: 1)
- [x] Write math tests: create /tmp/orch-smoke-test/tests/test-math.sh that sources lib/math.sh and asserts add 2 3 = 5, multiply 4 5 = 20 (deps: 2)
- [x] Write string tests: create /tmp/orch-smoke-test/tests/test-string.sh that sources lib/string.sh and asserts uppercase hello = HELLO (deps: 3)
- [x] Write integration test: create /tmp/orch-smoke-test/tests/test-integration.sh that sources config, math, and string libs, runs all checks (deps: 4, 5, 6)
- [x] Write summary report: create /tmp/orch-smoke-test/docs/report.md listing all files created and test results (deps: 7)
