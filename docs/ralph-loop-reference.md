# Ralph Loop — Technical Reference

**Saved:** 2026-02-23
**Why this exists:** Critical implementation detail — the exact CLI invocation required
for the outer loop to spawn agents that can actually do work (read/write files, run
commands, commit). Without this, the loop produces text but no actions.

---

## Core invocation

```bash
env -u CLAUDECODE claude -p --dangerously-skip-permissions "$(cat PROMPT.md)"
```

- `env -u CLAUDECODE` — unsets the `CLAUDECODE` env var so the spawned instance
  is not treated as a nested session. Claude Code blocks nested spawning unless
  this is unset. Required when running ralph-loop.sh from within a Claude Code session
  or any environment where `CLAUDECODE` is set.
- `-p` — non-interactive / print mode (stdin/prompt argument)
- `--dangerously-skip-permissions` — disables all approval prompts; agent executes
  Bash, file edits, and destructive operations autonomously without pausing

Without `--dangerously-skip-permissions`, the agent cannot read files, write files,
or run commands autonomously. The loop would stall waiting for human approval.

## Other agent variants (same pattern)

| Agent | Command |
|-------|---------|
| Claude Code | `claude -p --dangerously-skip-permissions "$(cat PROMPT.md)"` |
| Codex | `codex exec --yolo -` |
| Droid | `droid exec --skip-permissions-unsafe -f {prompt}` |
| OpenCode | `opencode run "$(cat {prompt})"` |

## The minimal loop

```bash
while :; do cat PROMPT.md | agent; done
```

Fresh instance per iteration. No context carry-over. Memory via files + git only.

## State files (memory between iterations)

| File | Written by | Read by | Purpose |
|------|-----------|---------|---------|
| `plan.md` | human / worker | worker, reviewer | task definition + progress checkboxes |
| `work-summary.txt` | worker | reviewer | what was done this iteration |
| `review-feedback.txt` | reviewer | worker | specific items to fix if REVISE |
| `review-result.txt` | reviewer | orchestrator | SHIP or REVISE decision |
| git history | worker (commits) | worker (next iter) | implemented work persists |

## Safety

`--dangerously-skip-permissions` is intentionally unsafe. Mitigations:

- Run in a Docker container or isolated VM — never on a machine with private data
- Provide API keys only — no credentials, no sensitive files in scope
- Set `max_iterations` (default: 10) to cap runaway loops
- Review commits before merging

## Two operational modes

**PLANNING** — reads specs, generates/updates `plan.md`, no code execution
**BUILDING** — implements tasks, runs tests/linters, commits, updates plan

Ralph thrives on machine-verifiable tasks (tests, linters, type checkers as
backpressure). Struggles with subjective work (design decisions, UX).

## Sources

- [Geoffrey Huntley — everything is a ralph loop](https://ghuntley.com/loop/)
- [snarktank/ralph](https://github.com/snarktank/ralph)
- [vercel-labs/ralph-loop-agent](https://github.com/vercel-labs/ralph-loop-agent)
- [iannuttall/ralph — minimal file-based agent loop](https://github.com/iannuttall/ralph)
- [goose Ralph Loop tutorial](https://block.github.io/goose/docs/tutorials/ralph-loop/)
- [--dangerously-skip-permissions explained](https://docs.bswen.com/blog/2026-02-21-dangerously-skip-permissions-explained/)
