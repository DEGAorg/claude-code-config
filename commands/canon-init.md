# Canon Init

@description Initialize Canon prediction-market framework in the current project directory.

Scaffolds `.canon/` with agents, skills, config, ralph.yaml, `.claude/commands/` with Canon
slash commands, a TypeScript project template, and AGENTS.md into the **current working
directory**. Does not touch `~/.claude/`. Run this from inside your strategy project, not
from `claude-code-config`.

---

## 1. Pre-checks

**Guard:** If the current directory is `claude-code-config` (i.e., this repo itself),
stop immediately and tell the user:

> Run `/canon-init` from inside your strategy project directory, not from
> `claude-code-config`. Navigate to your project first, then re-run.

**Overwrite check:** If `.canon/` already exists in the current directory, ask the user:

> `.canon/` already exists here. Overwrite? (yes/no)

If no, stop. If yes, continue — existing files will be replaced.

---

## 2. Create directory tree

Create the following directories in the current working directory:

```
.canon/
├── agents/
├── skills/
├── execution/
└── workflows/
.claude/
└── commands/
src/
└── types/
```

---

## 3. Fetch agent files

Fetch each of the following files from GitHub and write them to `.canon/agents/`:

| File | URL |
|------|-----|
| `strategy-architect.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/agents/strategy-architect.md` |
| `risk-analyst.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/agents/risk-analyst.md` |
| `market-analyst.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/agents/market-analyst.md` |
| `dev.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/agents/dev.md` |
| `qa.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/agents/qa.md` |
| `deployment-ops.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/agents/deployment-ops.md` |

---

## 4. Fetch skill files

Fetch each of the following files from GitHub and write them to `.canon/skills/`:

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

---

## 5. Fetch Canon commands

Fetch each of the following files from GitHub and write them to `.claude/commands/`:

| File | URL |
|------|-----|
| `develop.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/commands/develop.md` |
| `ralph-cycle.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/commands/ralph-cycle.md` |
| `discover.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/commands/discover.md` |
| `register.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/commands/register.md` |
| `quick-dev.md` | `https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/canon/commands/quick-dev.md` |

---

## 6. Scaffold TypeScript project template

Create the following files **only if they don't already exist** in the project root.
Skip any file that already exists to avoid overwriting user work.

### `package.json`

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

Replace `<directory-name>` with the actual current directory name.

### `tsconfig.json`

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

### `src/types/TradeSignal.ts`

```typescript
export interface TradeSignal {
  marketId: string;
  direction: "buy" | "sell";
  confidence: number;
  reasoning: string;
  timestamp: Date;
}
```

### `src/types/RiskInterface.ts`

```typescript
export interface RiskInterface {
  maxPositionSize: number;
  maxPortfolioExposure: number;
  stopLossPercent: number;
  validate(signal: unknown): { approved: boolean; reason: string };
}
```

### `.env.example`

```
# API keys — copy to .env and fill in values
POLYMARKET_API_KEY=
ODDS_API_KEY=
```

### `.gitignore`

```
node_modules/
dist/
.env
.canon/execution/
*.tsbuildinfo
```

---

## 7. Write `.canon/config.yaml`

Derive the strategy name from the current directory name (e.g., if the directory is
`sports-arb`, the strategy name is `sports-arb`). Write `.canon/config.yaml`:

```yaml
# Canon Agent Framework Configuration
# This file controls how agents, skills, and workflows compose

version: "1.0"

# Default agent for general tasks
default_agent: dev

# Agent registry — maps names to persona files
agents:
  strategy-architect: .canon/agents/strategy-architect.md
  risk-analyst: .canon/agents/risk-analyst.md
  market-analyst: .canon/agents/market-analyst.md
  dev: .canon/agents/dev.md
  qa: .canon/agents/qa.md
  deployment-ops: .canon/agents/deployment-ops.md

# Skill registry — maps names to skill files
skills:
  prediction-markets: .canon/skills/prediction-markets.md
  polymarket: .canon/skills/polymarket.md
  risk-management: .canon/skills/risk-management.md
  strategy-patterns: .canon/skills/strategy-patterns.md
  backtesting: .canon/skills/backtesting.md
  arena-tracking: .canon/skills/arena-tracking.md
  ralph-loop: .canon/skills/ralph-loop.md
  canon-conventions: .canon/skills/canon-conventions.md

# Workflow registry — maps names to workflow files
# Phase I: use slash commands (/develop, /ralph-cycle) instead of YAML workflows
workflows:
  discover: .canon/workflows/discover.yaml
  develop: .canon/workflows/develop.yaml
  register: .canon/workflows/register.yaml
  ralph-cycle: .canon/workflows/ralph-cycle.yaml
  quick-dev: .canon/workflows/quick-dev.yaml

# Context routing — what skills auto-load based on task type
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

# Standards injection — rules applied to ALL agent interactions
standards:
  always_load: [canon-conventions]
  enforce:
    - "All strategies must implement TradeSignal and RiskInterface"
    - "Position size never exceeds 5% of portfolio"
    - "Domain layering: Types → Config → Repo → Service → Runtime → UI"
    - "Error messages include what/why/how"
    - "If it's not in the repo, it doesn't exist"
```

Replace the strategy name comment with the actual directory name.

---

## 8. Write `.canon/ralph.yaml`

Write `.canon/ralph.yaml` with placeholder success criteria. The user must edit this
to match their specific strategy's check commands before running the Ralph Loop.

Use the current directory name as the `strategy` value.

```yaml
version: 1
strategy: <directory-name>   # derived from pwd

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

---

## 9. Create `.canon/execution/.gitkeep`

Write an empty `.gitkeep` file to `.canon/execution/` so the directory is tracked by git.

---

## 10. Write `AGENTS.md`

Write `AGENTS.md` at the project root (not inside `.canon/`):

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

---

## 11. Post-init summary

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
  4. Run /ralph-cycle to iterate until all checks pass
```
