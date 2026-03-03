# Plan: /canon-start Command

**Status:** In progress
**Created:** 2026-03-03
**Parent:** `docs/research/terminal-ui-action-plan.md` (Plan 4)
**Depends on:** Plan 1 (state spec — complete), Plans 2-3 (Ink dashboard, tmux launcher — in progress)

## Requirements

- Canon-specific guided workflow command: user says `/canon-start`, agent drives the full pipeline
- Agent knows the phases, recommends next steps, asks only when blocked
- Launches tmux session via `terminal-session.sh` (Plan 3) with `.canon/state.json`
- Writes state updates to `.canon/state.json` as phases progress (using `terminal-ui-write.sh`)
- Works both for fresh projects (no `.canon/`) and existing ones (`.canon/` present)
- Bridges the existing Canon commands (`/canon-init`, `/discover`, `/develop`, `/ralph-cycle`)
  into a single guided entry point — does not duplicate their logic
- This is a command (procedure), not a skill (knowledge injection)

## Approach

### What `/canon-start` is NOT

It is not a new orchestration engine. The Ralph Loop, Canon agents, and Canon commands
already exist and work. `/canon-start` is a **guided workflow command** that:

1. Assesses the current project state
2. Determines which phase the user is in
3. Recommends the next action
4. Launches the terminal UI session
5. Writes state updates as the agent progresses

It's the "smart dispatcher" that Carlos described — the user doesn't need to know
whether to run `/canon-init`, `/discover`, or `/develop`. The agent figures it out.

### Pipeline phases

```
init → scaffold → strategy → develop → run
```

| Phase | What happens | Delegates to |
|-------|-------------|--------------|
| **init** | Check if `.canon/` exists. If not, run canon-init. | `/canon-init` |
| **scaffold** | Verify scaffold completeness (agents, skills, types, config). Fill gaps. | `/canon-init` (partial) |
| **strategy** | Check for existing strategy spec. If none, prompt user or run discover. | `/discover` |
| **develop** | Implement strategy from spec. Test and iterate. | `/develop` |
| **run** | Start automation — monitor markets, check for opportunities. | Strategy runner (future) |

### Phase detection logic

The command assesses state by checking what exists:

```
No .canon/ directory          → phase: init
.canon/ but missing files     → phase: scaffold
No strategy spec found        → phase: strategy
Strategy spec but no src/     → phase: develop
src/ exists, tests fail       → phase: develop (iterate)
Everything passes             → phase: run
```

"Strategy spec" means either:
- A file matching `*.strategy.md` or `docs/strategy-*.md` in the project
- A design spec output from `/discover`
- User provides one when prompted

### State file integration

At each phase transition, the command writes to `.canon/state.json` using
`terminal-ui-write.sh`:

```bash
bash terminal-ui-write.sh .canon/state.json phase=init status=running \
  log.info="Checking project structure..."
```

This keeps the Ink dashboard (Plan 2) updated in real time via the tmux right pane.

### tmux session launch

At the start of `/canon-start`, the agent launches the tmux session:

```bash
bash terminal-session.sh --name canon --state .canon/state.json
```

The user runs `claude` in the left pane. The right pane shows the dashboard.
If the tmux session already exists (re-running `/canon-start`), it attaches.

### Guided workflow behavior

At each phase, the agent:

1. **States what it found** — "I see a Canon project with strategy spec but no implementation."
2. **Recommends the next step** — "I recommend running /develop to implement the strategy."
3. **Asks only when blocked** — "No strategy spec found. Would you like me to run /discover
   to scan markets, or do you have a spec to provide?"
4. **Proceeds autonomously** when the path is clear — doesn't ask permission for obvious steps
   like running `/canon-init` on a fresh project.

### Graceful degradation

- If `terminal-session.sh` is not installed: skip tmux, proceed with the workflow in the
  current terminal. Print a note that the visual dashboard is available with `/apply-core`.
- If `terminal-ui-write.sh` is not installed: skip state file writes. The command still
  works — it just won't update the dashboard.
- If the user runs `/canon-start` outside of tmux: launch the tmux session and tell the
  user to switch to it. Or proceed without tmux if they prefer.

## Files to touch

| File | Change |
|------|--------|
| `canon/commands/canon-start.md` | Create — guided workflow command |

## Risks and open questions

- **P1:** Should `/canon-start` actually invoke the other commands (like `/canon-init`)
  inline, or tell the user to run them? → Invoke inline. The whole point is the user
  says one thing and the agent handles everything. "Run `/canon-init` yourself" defeats
  the purpose. The command includes the instructions from each sub-command as needed.
- **P2:** The "run" phase (live automation) doesn't exist yet. → For now, the run phase
  prints "Automation runner not yet implemented. Strategy is ready for manual execution."
  This is honest and doesn't block the demo — the demo shows the pipeline up to develop.
- **P2:** Should `/canon-start` be added to `/apply-canon` install list? → Yes, but
  that's a separate change to `canon/commands/apply-canon.md`. Not in scope here.

## Progress log

- [ ] Write `canon/commands/canon-start.md` with phase detection logic
- [ ] Include tmux session launch instructions at entry
- [ ] Include state file write instructions at each phase transition
- [ ] Include inline delegation to canon-init, discover, develop
- [ ] Include graceful degradation for missing terminal-ui components
- [ ] Verify the command references correct file paths and tool names

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Single command file, not a script | Separate shell script orchestrator | Commands are agent instructions — the agent executes them. A shell script can't make judgment calls (when to ask, what to skip). The agent's LLM reasoning IS the orchestrator. |
| Inline sub-command logic | Call `/canon-init` as separate command invocation | Commands can't invoke other commands. The agent reads one command at a time. `/canon-start` must include the relevant instructions from each sub-command. |
| Phase detection by file presence | Explicit state machine with persisted phase | File presence is observable and idempotent. No stale state to worry about. Running `/canon-start` twice with the same project state gives the same recommendation. |
| Graceful degradation for terminal-ui | Hard dependency on Plans 2-3 | `/canon-start` delivers value (guided workflow) even without the visual dashboard. The dashboard is an enhancement, not a requirement. |
| "run" phase deferred | Build a strategy runner now | Out of scope. The demo shows pipeline up to develop. Live automation is post-demo work. |

## Completion criteria

- [ ] `canon/commands/canon-start.md` exists with all phase logic
- [ ] Command detects fresh project (no `.canon/`) and handles init
- [ ] Command detects existing project and skips to correct phase
- [ ] State file writes are included at each phase transition
- [ ] tmux session launch is included at entry
- [ ] Graceful degradation documented for missing components
