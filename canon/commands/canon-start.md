# Canon Start

@description Guided entry point for Canon prediction-market development — detects project phase and drives the full pipeline.

Run every step below in order. Do not stop between steps unless explicitly told to.

---

## 1. Launch terminal UI session

Check prerequisites:

1. Run `command -v tmux` to verify tmux is installed.
2. Check if `~/.claude/scripts/terminal-session.sh` exists.

**If tmux is not installed or the script does not exist**, print once:

> Visual dashboard not available. Install tmux and run `/apply-core` for the terminal UI experience.
> Continuing without dashboard — all workflow steps work the same.

Skip to step 2. Do not warn again about the missing dashboard for the rest of this session.

**If both are available**, check whether a tmux session named "canon" already exists:

```bash
tmux has-session -t canon 2>/dev/null && echo "exists" || echo "not found"
```

- **Session exists**: the dashboard is already running. Print:

  > tmux session "canon" is active — dashboard running in the right pane.

  Skip to step 2.

- **Session does not exist**: create it. First ensure the state file exists so the
  dashboard has something to read:

  ```bash
  mkdir -p .canon
  if [[ ! -f .canon/state.json ]]; then
    if [[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]]; then
      bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
        phase=detecting status=running log.info="Canon start — initializing..."
    else
      echo '{"phase":"detecting","status":"running","logs":[],"error":null,"metrics":{}}' > .canon/state.json
    fi
  fi
  ```

  Then create the tmux session with the dashboard in the right pane. Do **not** attach —
  the agent continues working in the current terminal while the dashboard runs in the
  background session:

  ```bash
  STATE="$(pwd)/.canon/state.json"

  # Pick the best dashboard renderer available
  RIGHT_CMD="bash -c 'while true; do clear && cat \"${STATE}\" 2>/dev/null; sleep 1; done'"
  [[ -f "${HOME}/.claude/scripts/terminal-ui/dist/cli.js" ]] && \
    RIGHT_CMD="node ${HOME}/.claude/scripts/terminal-ui/dist/cli.js --state ${STATE}"
  command -v terminal-ui >/dev/null 2>&1 && \
    RIGHT_CMD="terminal-ui --state ${STATE}"

  # Create detached session: left pane for user, right pane for dashboard
  tmux new-session -d -s canon
  tmux split-window -h -t canon -p 40 "${RIGHT_CMD}"
  tmux select-pane -t canon:.0
  tmux set-option -t canon status-left " #S "
  tmux set-option -t canon status-right " %H:%M "
  ```

  Print:

  > tmux session "canon" created with live dashboard. To view it, open a new
  > terminal and run:
  > ```
  > tmux attach -t canon
  > ```

Proceed with the workflow in the current terminal regardless of tmux outcome.

**State write convention:** Every `terminal-ui-write.sh` call in steps 2–7 is guarded.
Before each call, check if the script exists and skip silently if it does not. The note
above is the only user-facing message about the missing dashboard — do not warn again.

---

## 2. Detect phase

Assess the current project state by checking what exists. Evaluate conditions
top-to-bottom — the first match determines the current phase.

| Condition | Phase | Next action |
|-----------|-------|-------------|
| No `.canon/` directory | **init** | Go to step 3 |
| `.canon/` exists but missing required files (see below) | **scaffold** | Go to step 4 |
| No strategy spec found (see below) | **strategy** | Go to step 5 |
| Strategy spec exists but no `src/` directory | **develop** | Go to step 6 |
| `src/` exists but tests fail (`pnpm exec vitest run` exits non-zero) | **develop** | Go to step 6 |
| All checks pass | **run** | Go to step 7 |

**Required scaffold files** (for scaffold-complete check):
- `.canon/config.yaml`
- `.canon/ralph.yaml`
- `.canon/agents/` directory with at least one `.md` file
- `.canon/skills/` directory with at least one `.md` file
- `package.json`
- `tsconfig.json`
- `src/types/TradeSignal.ts`
- `src/types/RiskInterface.ts`

**Strategy spec detection** — a strategy spec is any of:
- A file matching `*.strategy.md` anywhere in the project
- A file matching `docs/strategy-*.md`
- A design spec output from `/discover` (check `.canon/execution/` for spec files)

Write the detected phase to the state file:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=<detected-phase> status=running log.info="Detected phase: <detected-phase>"
```

Tell the user what you found:

> **Phase: <phase>** — <one-sentence description of what was detected>

Then jump to the step for that phase.

---

## 3. Phase: init

The project has no `.canon/` directory. Set up the Canon framework.

**Guard:** If the current directory is `claude-code-config` (this config repo itself),
stop and tell the user:

> Run `/canon-start` from inside your strategy project directory, not from
> `claude-code-config`. Navigate to your project first, then re-run.

Write state update:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=init status=running log.info="Initializing Canon framework..."
```

Execute the canon-init procedure inline. Skip any file that already exists.

### 3a. Create directory tree

```bash
mkdir -p .canon/agents .canon/skills .canon/execution .canon/workflows
mkdir -p .claude/commands
mkdir -p src/types
```

### 3b. Fetch agent files to `.canon/agents/`

| File | URL |
|------|-----|
| `strategy-architect.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/agents/strategy-architect.md` |
| `risk-analyst.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/agents/risk-analyst.md` |
| `market-analyst.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/agents/market-analyst.md` |
| `dev.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/agents/dev.md` |
| `qa.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/agents/qa.md` |
| `deployment-ops.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/agents/deployment-ops.md` |

### 3c. Fetch skill files to `.canon/skills/`

| File | URL |
|------|-----|
| `prediction-markets.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/skills/prediction-markets.md` |
| `polymarket.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/skills/polymarket.md` |
| `risk-management.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/skills/risk-management.md` |
| `strategy-patterns.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/skills/strategy-patterns.md` |
| `backtesting.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/skills/backtesting.md` |
| `arena-tracking.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/skills/arena-tracking.md` |
| `ralph-loop.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/skills/ralph-loop.md` |
| `canon-conventions.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/skills/canon-conventions.md` |

### 3d. Fetch Canon commands to `.claude/commands/`

| File | URL |
|------|-----|
| `develop.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/commands/develop.md` |
| `ralph-cycle.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/commands/ralph-cycle.md` |
| `discover.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/commands/discover.md` |
| `register.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/commands/register.md` |
| `quick-dev.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/commands/quick-dev.md` |

### 3e. Scaffold TypeScript project

Create each file only if it does not already exist.

**`package.json`** — replace `<directory-name>` with the current directory name:

```json
{
  "name": "<directory-name>",
  "version": "0.1.0",
  "type": "module",
  "private": true,
  "scripts": {
    "build": "tsc",
    "check": "tsc --noEmit",
    "lint": "oxlint src/",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "devDependencies": {
    "typescript": "5.9.3",
    "vitest": "4.0.18",
    "oxlint": "1.51.0",
    "tsx": "4.21.0"
  }
}
```

**`tsconfig.json`**:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Node16",
    "moduleResolution": "Node16",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitOverride": true,
    "noPropertyAccessFromIndexSignature": true,
    "verbatimModuleSyntax": true,
    "isolatedModules": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

**`src/types/TradeSignal.ts`**:

```typescript
export interface TradeSignal {
  marketId: string;
  direction: "buy" | "sell";
  confidence: number;
  reasoning: string;
  timestamp: Date;
}
```

**`src/types/RiskInterface.ts`**:

```typescript
export interface RiskInterface {
  maxPositionSize: number;
  maxPortfolioExposure: number;
  stopLossPercent: number;
  validate(signal: unknown): { approved: boolean; reason: string };
}
```

**`.env.example`**:

```
# API keys — copy to .env and fill in values
POLYMARKET_API_KEY=
ODDS_API_KEY=
```

**`.gitignore`**:

```
node_modules/
dist/
.env
.canon/execution/
*.tsbuildinfo
```

### 3f. Write `.canon/config.yaml`

Use the current directory name as the strategy name:

```yaml
version: "1.0"
default_agent: dev

agents:
  strategy-architect: .canon/agents/strategy-architect.md
  risk-analyst: .canon/agents/risk-analyst.md
  market-analyst: .canon/agents/market-analyst.md
  dev: .canon/agents/dev.md
  qa: .canon/agents/qa.md
  deployment-ops: .canon/agents/deployment-ops.md

skills:
  prediction-markets: .canon/skills/prediction-markets.md
  polymarket: .canon/skills/polymarket.md
  risk-management: .canon/skills/risk-management.md
  strategy-patterns: .canon/skills/strategy-patterns.md
  backtesting: .canon/skills/backtesting.md
  arena-tracking: .canon/skills/arena-tracking.md
  ralph-loop: .canon/skills/ralph-loop.md
  canon-conventions: .canon/skills/canon-conventions.md

workflows:
  discover: .canon/workflows/discover.yaml
  develop: .canon/workflows/develop.yaml
  register: .canon/workflows/register.yaml
  ralph-cycle: .canon/workflows/ralph-cycle.yaml
  quick-dev: .canon/workflows/quick-dev.yaml

context_routing:
  strategy_design:
    agent: strategy-architect
    auto_skills: [prediction-markets, strategy-patterns, risk-management]
    workflow: discover
  strategy_implementation:
    agent: dev
    auto_skills: [canon-conventions, backtesting, risk-management]
    workflow: develop
  registration:
    agent: deployment-ops
    auto_skills: [arena-tracking, risk-management]
    workflow: register
  risk_review:
    agent: risk-analyst
    auto_skills: [risk-management, prediction-markets]
  market_analysis:
    agent: market-analyst
    auto_skills: [prediction-markets, polymarket]
    workflow: discover
  iteration:
    agent: dev
    auto_skills: [ralph-loop, canon-conventions]
    workflow: ralph-cycle

standards:
  always_load: [canon-conventions]
  enforce:
    - "All strategies must implement TradeSignal and RiskInterface"
    - "Position size never exceeds 5% of portfolio"
    - "Domain layering: Types → Config → Repo → Service → Runtime → UI"
    - "Error messages include what/why/how"
    - "If it's not in the repo, it doesn't exist"
```

### 3g. Write `.canon/ralph.yaml`

Replace `<directory-name>` with the current directory name:

```yaml
version: 1
strategy: <directory-name>

success_criteria:
  - id: types_compile
    description: TypeScript compiles with no errors
    check: "pnpm exec tsc --noEmit"
    required: true
  - id: lint_clean
    description: Linter reports zero errors
    check: "pnpm exec oxlint src/"
    required: true
  - id: tests_pass
    description: All tests pass
    check: "pnpm exec vitest run"
    required: true

max_iterations: 5
```

### 3h. Write remaining files

**`.canon/execution/.gitkeep`** — empty file.

**`AGENTS.md`** at the project root:

```markdown
# Canon Strategy Development

## Quick Reference
- Framework config: `.canon/config.yaml`
- Ralph Loop config: `.canon/ralph.yaml`
- Agent personas: `.canon/agents/`
- Skills (domain knowledge): `.canon/skills/`
- Workflows: `.canon/workflows/`

## Available Agents

| Agent | Role | Load When |
|-------|------|-----------|
| strategy-architect | Designs strategies from market analysis | Starting a new strategy |
| market-analyst | Interprets market data, finds opportunities | Exploring markets |
| dev | Implements strategies in TypeScript | Writing code |
| qa | Validates quality and standards compliance | Reviewing before registration |
| risk-analyst | Evaluates risk and portfolio impact | Before registration |
| deployment-ops | Registers on Arena, monitors tracked performance | Registering a strategy |

## Available Commands

| Command | Purpose |
|---------|---------|
| `/develop` | Scaffold, implement, test, iterate (full build cycle) |
| `/ralph-cycle` | Execute success criteria checks and iterate until SHIP |
| `/discover` | Market analysis, opportunity identification, strategy design |
| `/register` | Risk review, pre-registration checks, Arena tracking |
| `/quick-dev` | Small changes with lightweight validation |

## Key Workflows
1. **Discover** (`/discover`): Market analysis -> opportunity -> strategy design
2. **Develop** (`/develop`): Verify scaffold -> implement -> test -> iterate (Ralph Loop)
3. **Register** (`/register`): Risk review -> pre-registration checks -> Arena tracking
4. **Ralph Cycle** (`/ralph-cycle`): Execute -> check -> iterate -> SHIP or ESCALATE
5. **Quick Dev** (`/quick-dev`): Small changes with lightweight validation

## Non-Negotiable Rules
1. All strategies implement TradeSignal + RiskInterface
2. Position size never >5% of portfolio
3. Domain layering: Types -> Config -> Repo -> Service -> Runtime -> UI
4. Error messages include what/why/how
5. "If it's not in the repo, it doesn't exist"

## Domain Knowledge (Skills)
For prediction market concepts, strategy patterns, risk management, and
platform-specific knowledge, see `.canon/skills/`:
- `prediction-markets.md` — Fundamentals, mechanics, pricing
- `polymarket.md` — Polymarket-specific knowledge (fees, API, resolution)
- `risk-management.md` — Position sizing, exposure limits, hard limits
- `strategy-patterns.md` — Six strategy archetypes and when to use them
- `backtesting.md` — Testing methodology, interpreting results, avoiding overfitting
- `arena-tracking.md` — Registration pipeline, monitoring live strategies
- `ralph-loop.md` — Configuring and operating autonomous iteration
- `canon-conventions.md` — Coding standards, domain layering, error messages

## Strategy Structure
- `src/strategy.ts` — Strategy logic (or strategy-specific entry point)
- `src/types/TradeSignal.ts` — Output interface (required)
- `src/types/RiskInterface.ts` — Risk validation (required)
- `.canon/ralph.yaml` — Ralph Loop config (edit success_criteria before running)
```

### 3i. Post-init summary

Print a summary of what was created:

```
Canon initialized in <current-directory>/

  .canon/
    agents/    — 6 agent personas
    skills/    — 8 domain knowledge modules
    execution/ — decision logs written here at runtime
    workflows/ — Phase I: use slash commands instead (/develop, /ralph-cycle)
    config.yaml
    ralph.yaml  <- edit success_criteria to match your strategy's check commands

  .claude/commands/
    develop.md, ralph-cycle.md, discover.md, register.md, quick-dev.md

  src/types/
    TradeSignal.ts, RiskInterface.ts

  package.json, tsconfig.json, .env.example, .gitignore
  AGENTS.md

Next steps:
  1. Run: pnpm install
  2. Edit .canon/ralph.yaml — set the check commands for your strategy
  3. Run /develop to start building with Canon agents
```

After printing the summary, write state update:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=init status=running log.info="Canon framework initialized"
```

Proceed to step 4 (scaffold verification).

---

## 4. Phase: scaffold

The `.canon/` directory exists but may be incomplete. Verify and fill gaps.

Write state update:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=scaffold status=running log.info="Verifying scaffold completeness..."
```

Check each required scaffold file from the list in step 2. For each missing file,
create it using the templates from step 3 (sections 3b–3h).

Report what was found:

> Scaffold check: <N> of <total> files present. <Missing: list, or "All present.">

If any files were created, report them. Then proceed to step 5.

Write state update:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=scaffold status=running log.info="Scaffold complete"
```

---

## 5. Phase: strategy

The scaffold is complete but no strategy spec was found.

Write state update:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=strategy status=running log.info="Looking for strategy specification..."
```

Ask the user:

> No strategy specification found. Choose one:
>
> 1. **Run /discover** — I'll scan prediction markets, identify opportunities,
>    and generate a strategy design spec automatically.
> 2. **Provide a spec** — Point me to an existing strategy document or describe
>    your strategy and I'll write the spec.

Wait for the user's response.

**If the user chooses /discover:**

Execute the `/discover` procedure inline:

1. As market-analyst, research available prediction markets using web search
   and the Polymarket API documentation.
2. Scan for opportunities (price movements, volume spikes, thin liquidity, resolution events).
3. Select the top opportunity by edge size, liquidity, resolution clarity, and capital efficiency.
4. As strategy-architect, design a strategy for the selected opportunity:
   - Select strategy archetype (from strategy-patterns skill)
   - Design entry/exit signal logic
   - Define risk parameters (position size ≤5%, stop-loss, circuit breakers)
   - Define backtest success criteria (win rate >55%, profit factor >1.2,
     max drawdown <15%, min 30 trades)

Write the strategy spec to `docs/strategy-<name>.md`.

Load agents: market-analyst, strategy-architect.
Load skills: prediction-markets, polymarket, strategy-patterns, risk-management.

**If the user provides a spec:**

Read the provided document. Validate it contains:
- Target market(s)
- Strategy archetype or approach
- Entry/exit logic
- Risk parameters

If anything is missing, ask the user to clarify before proceeding.

Write state update:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=strategy status=running log.info="Strategy spec ready"
```

Proceed to step 6.

---

## 6. Phase: develop

A strategy spec exists. Implement, test, and iterate.

Write state update:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=develop status=running log.info="Starting development..."
```

Execute the `/develop` procedure inline:

Load agent: dev.
Load skills: canon-conventions, backtesting, ralph-loop, risk-management.

### 6a. Implement

Implement strategy logic from the design specification:

- Implement `TradeSignal` interface in `src/strategy.ts`
- Implement `RiskInterface` in `src/types/RiskInterface.ts` with hard limits from the spec.
  Do not skip RiskInterface — "I'll add it later" is not acceptable.
- Follow domain layering: Types -> Config -> Repo -> Service -> Runtime -> UI
- Use agent-oriented error messages (what/why/how format)

### 6b. Test and iterate

Run every check command from `.canon/ralph.yaml` `success_criteria`:

```
pnpm exec tsc --noEmit
pnpm exec oxlint src/
pnpm exec vitest run
```

All must pass. If any fail, iterate:

1. Read failing output to identify what broke
2. Fix the issue in code
3. Re-run all checks
4. Repeat until all pass or `max_iterations` from `.canon/ralph.yaml` is reached

Write state update on each iteration:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=develop status=running metric.iteration=<N> log.info="Iteration <N>: <pass/fail summary>"
```

If max iterations reached without passing, surface failing criteria for human review.

### 6c. QA review

As qa, validate strategy quality:

Load skills: canon-conventions, backtesting, risk-management.

1. Code conventions: domain layering respected, error messages follow what/why/how
2. Backtest results across multiple timeframes (7d, 30d, 90d if data available)
3. No overfitting signals
4. RiskInterface correctly enforces hard limits
5. Edge cases: zero liquidity, API timeout, zero balance

Verdict:
- **Approved**: All criteria met -> proceed to step 7
- **Return to dev**: Specific blocking issues -> list issues -> loop back to step 6a

Write state update:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=develop status=running log.info="QA: <Approved|Returned with N issues>"
```

---

## 7. Phase: run

All checks pass and QA is approved. The strategy is ready for execution.

Write state update:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=run status=idle log.info="Strategy ready for execution"
```

Print:

> **Strategy development complete.**
>
> All checks pass. QA approved. Your strategy is ready.
>
> Next steps:
> - Run `/register` to submit to Canon Arena for tracked performance
> - Automation runner is not yet implemented — run your strategy manually
>   or monitor markets and execute signals by hand
>
> To re-run any phase, use the individual commands:
> - `/discover` — market analysis and strategy design
> - `/develop` — implement, test, iterate
> - `/ralph-cycle` — iterate until all success criteria pass
> - `/register` — risk review and Arena registration

---

## Graceful degradation

This command works with or without the terminal UI components:

| Component | If missing | Behavior |
|-----------|-----------|----------|
| `~/.claude/scripts/terminal-session.sh` | Skip tmux launch | Workflow runs in current terminal |
| `~/.claude/scripts/terminal-ui-write.sh` | Skip state file writes | No dashboard updates, workflow still runs |
| tmux not installed | Skip tmux launch | Same as missing terminal-session.sh |

Every `terminal-ui-write.sh` call in this command is already guarded with
`[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] &&`. If the script
does not exist, the call is skipped silently — no error, no repeated warnings.

The tmux launch in step 1 checks for both `tmux` and `terminal-session.sh`.
If either is missing, it prints one note and skips. No further warnings.

---

## Completion criteria

- Phase detection correctly identifies the project's current state
- Each phase delegates to the right sub-command logic (canon-init, discover, develop)
- State file is updated at each phase transition (when terminal-ui-write.sh is available)
- tmux session is launched at entry (when terminal-session.sh is available)
- Graceful degradation: command works without terminal UI components
- User is guided through the full pipeline with minimal questions
