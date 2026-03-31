# Demo Recording Agenda — Mar 30, 2026

## Setup

- Fresh empty project directory with `.env` containing `THE_ODDS_API_KEY`
- Toad installed, Claude installed, `/apply-core` done

## Flow

### 1. Canon Init

Open Claude in the empty project dir, type `/canon-init`. It checks
prereqs, writes `canon.sh`. Exit Claude.

### 2. Launch Toad

Run `./canon.sh`. Toad opens. Pick Claude as agent.

### 3. Open State View

Ctrl+G — opens the State panel on the right side. Shows idle.

### 4. Start Canon

Type `/canon-start`. Agent takes over:

- **Scaffold** (~30s) — fetches agents, skills, templates, generates
  project structure. State view shows progress logs live.
- **Strategy** — agent asks which strategy. Pick the NBA Momentum template.
- **Build** — agent implements the strategy code inline, item by item.
  State view shows each item completing.

### 5. Run

Agent detects all checks pass, finds the API key in `.env`, launches
the runner. State view shows cycles, signals, errors updating in real
time.

### 6. Ask a Question

While running, type "what's happening?" to show the agent has context
of the live automation process.

### 7. Stop

Type `/canon-stop` to kill the runner and reset state.

## Recording Tips

- Keep Ctrl+G open the whole time so State view is visible
- The scaffold phase is the most visual (lots of log updates)
- If the runner hits API errors, that's fine for 1-2 cycles — shows
  real behavior. `/canon-stop` if it spirals
- The point of the demo is the pipeline, not the strategy results
