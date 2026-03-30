# Demo Prep — Mar 3, 2026

Reference notes from the Mar 2 planning meeting (Alberto + Carlos).

---

## What the Demo Proves

The AI development pipeline works end-to-end. An agent receives a plan, creates a
TypeScript repo, scaffolds the app, writes strategy logic, and runs it — all driven
by Claude Code + harness. The strategy correctness is secondary; the pipeline is the point.

## Demo Scenario

1. Agent receives a sports prediction strategy plan
2. Builds a TS repo from scratch (canon init + scaffold)
3. Writes the strategy logic
4. Runs the automation — pings for opportunities (Polymarket update times vs faster provider)
5. Even if it finds nothing, it should be visibly running and checking

## Visual Requirements

Raw terminal output is too low-level for the audience (includes non-technical people).

| Element | Description |
|---------|-------------|
| **Status indicator** | Always visible: running, paused, current phase |
| **Log panel** | Meaningful activity — data arriving, analysis, results (not raw debug) |
| **Two-panel layout** | One panel for chatting with the agent, one showing automation output |
| **Interactive control** | Ask "what are you doing?", pause, resume, get plain-language answers |

### Minimum viable visual

Two side-by-side terminals — chat + automation output — is acceptable as long as the
experience feels coherent.

### References

- dvtm / tmux-based multi-agent TUI (integrates with Claude Code) — evaluate as base or reference
- TUI libraries — research terminal UI frameworks (Carlos sent two examples previously)

## Interactive Demo Flow (Carlos's ideal)

1. User says "start automation" or "activate sports automation"
2. Agent opens panels, starts running
3. User asks "what is happening with the automation right now?" — gets a clear answer
4. User says "pause the automation" — visual indicator changes to paused
5. User says "reactivate" — it resumes
6. Demonstrates the agent has context awareness of the running process

## State Management

Automation state (current phase, balance, open positions) must be stored where both
the running process and the conversational agent can read it. Carlos references the
Blackboard Pattern as an architectural approach.

## Timeline

| When | What |
|------|------|
| Mar 2 evening | Final dry run — full flow end-to-end |
| Mar 3 | Record demo video, send to Carlos for feedback |
| Before Wed/Thu | Carlos reviews, gives feedback |

## Action Items

- [ ] Final dry run tonight (full flow)
- [ ] Record demo video Mar 3
- [ ] Add visual terminal UI (status indicator, meaningful logs)
- [ ] Evaluate dvtm/tmux wrapper as base or reference
- [ ] Implement two-panel setup (chat + automation output)
- [ ] Add interactive control (report state, pause, resume)
- [ ] Decide state storage approach

## Gap: Agent-Driven Workflow (Missing Today)

**Source:** Carlos, meet-mar-2 transcript (~lines 236-265, 247, 252)

### The problem

Today, using Claude Code is like being an orchestra conductor — the user must hold the
entire workflow in their head and direct every step. The agent only helps someone who
already knows what to do. That's a linear advantage (speeds up the expert). Carlos wants
an **exponential** advantage: the agent itself knows the workflow and guides the user
through it.

### What "start" should look like

The user says `init` or `start automation` and the agent:

1. **Knows what to do** — the full workflow, phases, and next steps are built in
2. **Tells the user what it recommends** — "I've done X, Y, Z. Here's what I recommend next."
3. **Asks only when blocked** — "Your GitHub isn't authenticated. Here are the steps.
   Let me know when you're done."
4. **Handles repo setup, scaffolding, config** — whether starting fresh or working with
   an existing repo, the agent figures it out
5. **Runs autonomously in background** — monitors, checks for opportunities, reports back

### Current gap in Core + Canon agents

- No "start" entry point that kicks off a full workflow
- Agents don't proactively suggest next steps — they wait for commands
- No built-in awareness of "what phase am I in" across the pipeline
- User must know which commands to run and in what order
- Skills and commands exist in isolation — no orchestration layer connects them

### Why it matters (Carlos's framing)

> If we launch as-is, maybe 4,000 people on Earth can understand and use it.
> With agent-driven workflow, that's 20,000 — and growing as we add UI layers.

The goal is to blur the line between using apps and developing apps. The agent should
be the guide, not just the tool.

### Implication for demo

Even if the full orchestration isn't ready, the demo should **show the intent**: the user
says "start automation" and the agent takes over — opens panels, starts running, reports
status, responds to questions. The user doesn't need to know the internals.

---

## Post-Demo (Deferred)

- Centralized operation logging
- Config/auth system (Encore-style workspace authorization)
