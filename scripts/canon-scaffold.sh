#!/usr/bin/env bash
# Canon Scaffold — scaffolds a Canon prediction-market project.
#
# Usage: bash ~/.claude/scripts/canon-scaffold.sh [--force]
#
# Run from inside the target project directory (must be empty or use --force).
# Fetches agents, skills, and commands from GitHub, generates config and
# template files. Deterministic, idempotent, zero agent guesswork.

set -euo pipefail

REPO="DEGAorg/claude-code-config"
BRANCH="ace-work"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

PROJECT_DIR="$(pwd)"
PROJECT_NAME="$(basename "${PROJECT_DIR}")"
STATE_FILE="${PROJECT_DIR}/.canon/state.json"
TUI_WRITE="${HOME}/.claude/scripts/terminal-ui-write.sh"

# ── Helper: write state to dashboard (no-op if writer not installed) ─────────
state() {
  [[ -f "${TUI_WRITE}" ]] && bash "${TUI_WRITE}" "${STATE_FILE}" "$@" || true
}

# ── Guard: don't run inside claude-code-config itself ─────────────────────────
if [[ -f "CLAUDE.md" ]] && grep -q "claude-code-config" "CLAUDE.md" 2>/dev/null; then
  echo "error: run canon-init from your strategy project, not from claude-code-config" >&2
  exit 1
fi

# ── Guard: check for existing .canon/ ─────────────────────────────────────────
if [[ -d ".canon" && "${FORCE}" != "true" ]]; then
  echo "error: .canon/ already exists. Use --force to overwrite." >&2
  exit 1
fi

echo "canon-init: initializing '${PROJECT_NAME}' in ${PROJECT_DIR}"
echo ""

state phase=init status=running log.info="Canon init starting for '${PROJECT_NAME}'"

# ── Helper: fetch a file from GitHub ──────────────────────────────────────────
fetch() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "${dst}")"
  if ! curl -sfL "${BASE_URL}/${src}" -o "${dst}"; then
    echo "error: failed to fetch ${src}" >&2
    exit 1
  fi
}

# ── 1. Create directory tree ──────────────────────────────────────────────────
echo "→ creating directories..."
mkdir -p .canon/agents .canon/skills .canon/execution .canon/workflows .canon/templates
mkdir -p .claude/commands
mkdir -p src/types

# ── 2. Fetch agents ──────────────────────────────────────────────────────────
echo "→ fetching agents..."
state log.info="Fetching 6 agent personas..."
for agent in strategy-architect risk-analyst market-analyst dev qa deployment-ops; do
  fetch "canon/agents/${agent}.md" ".canon/agents/${agent}.md"
done
state log.info="Agents fetched"

# ── 3. Fetch skills ──────────────────────────────────────────────────────────
echo "→ fetching skills..."
state log.info="Fetching 8 domain skills..."
for skill in prediction-markets polymarket risk-management strategy-patterns \
             backtesting arena-tracking ralph-loop canon-conventions; do
  fetch "canon/skills/${skill}.md" ".canon/skills/${skill}.md"
done
state log.info="Skills fetched"

# ── 4. Fetch commands ────────────────────────────────────────────────────────
echo "→ fetching commands..."
state log.info="Fetching 6 slash commands..."
for cmd in develop ralph-cycle discover register quick-dev canon-start; do
  fetch "canon/commands/${cmd}.md" ".claude/commands/${cmd}.md"
done
state log.info="Commands fetched"

# ── 4b. Fetch strategy templates ──────────────────────────────────────────────
echo "→ fetching strategy templates..."
state log.info="Fetching strategy templates..."
for tmpl in nba-momentum; do
  fetch "canon/templates/${tmpl}.strategy.md" ".canon/templates/${tmpl}.strategy.md"
done
state log.info="Templates fetched"

# ── 5. Generate template files (skip if they exist) ──────────────────────────
echo "→ generating template files..."
state log.info="Generating template files..."

write_if_missing() {
  local path="$1"
  if [[ -f "${path}" && "${FORCE}" != "true" ]]; then
    echo "  skip: ${path} (already exists)"
    return
  fi
  cat > "${path}"
  echo "  wrote: ${path}"
}

write_if_missing "package.json" <<EOF
{
  "name": "${PROJECT_NAME}",
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
EOF

write_if_missing "tsconfig.json" <<EOF
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
EOF

write_if_missing "src/types/TradeSignal.ts" <<'EOF'
export interface TradeSignal {
  marketId: string;
  direction: "buy" | "sell";
  confidence: number;
  reasoning: string;
  timestamp: Date;
}
EOF

write_if_missing "src/types/RiskInterface.ts" <<'EOF'
export interface RiskInterface {
  maxPositionSize: number;
  maxPortfolioExposure: number;
  stopLossPercent: number;
  validate(signal: unknown): { approved: boolean; reason: string };
}
EOF

write_if_missing ".env.example" <<'EOF'
# API keys — copy to .env and fill in values
POLYMARKET_API_KEY=
ODDS_API_KEY=
EOF

write_if_missing ".gitignore" <<'EOF'
node_modules/
dist/
.env
.canon/execution/
*.tsbuildinfo
EOF

# ── 6. Write .canon/config.yaml ──────────────────────────────────────────────
echo "→ writing .canon/config.yaml..."
cat > ".canon/config.yaml" <<EOF
# Canon Agent Framework Configuration
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
    - "Domain layering: Types > Config > Repo > Service > Runtime > UI"
    - "Error messages include what/why/how"
    - "If it is not in the repo, it does not exist"
EOF

# ── 7. Write .canon/ralph.yaml ───────────────────────────────────────────────
echo "→ writing .canon/ralph.yaml..."
cat > ".canon/ralph.yaml" <<EOF
version: 1
strategy: ${PROJECT_NAME}

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
EOF

# ── 8. Create .canon/execution/.gitkeep ───────────────────────────────────────
touch ".canon/execution/.gitkeep"

# ── 9. Write AGENTS.md ───────────────────────────────────────────────────────
echo "→ writing AGENTS.md..."
cat > "AGENTS.md" <<'EOF'
# Canon Strategy Development

## Quick Reference
- Framework config: `.canon/config.yaml`
- Ralph Loop config: `.canon/ralph.yaml`
- Agent personas: `.canon/agents/`
- Skills (domain knowledge): `.canon/skills/`

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
| `/canon-start` | Guided workflow — detects project state, drives full pipeline |
| `/develop` | Scaffold, implement, test, iterate (full build cycle) |
| `/ralph-cycle` | Execute success criteria checks and iterate until SHIP |
| `/discover` | Market analysis, opportunity identification, strategy design |
| `/register` | Risk review, pre-registration checks, Arena tracking |
| `/quick-dev` | Small changes with lightweight validation |

## Non-Negotiable Rules
1. All strategies implement TradeSignal + RiskInterface
2. Position size never >5% of portfolio
3. Domain layering: Types -> Config -> Repo -> Service -> Runtime -> UI
4. Error messages include what/why/how
5. "If it's not in the repo, it doesn't exist"
EOF

# ── 10. Verify ────────────────────────────────────────────────────────────────
echo ""
echo "→ verifying..."
state log.info="Verifying all files..."
ERRORS=0
for f in \
  .canon/agents/dev.md \
  .canon/agents/strategy-architect.md \
  .canon/skills/prediction-markets.md \
  .canon/skills/canon-conventions.md \
  .canon/config.yaml \
  .canon/ralph.yaml \
  .claude/commands/canon-start.md \
  .claude/commands/develop.md \
  src/types/TradeSignal.ts \
  src/types/RiskInterface.ts \
  package.json \
  tsconfig.json \
  AGENTS.md; do
  if [[ ! -f "${f}" ]]; then
    echo "  MISSING: ${f}" >&2
    ERRORS=$((ERRORS + 1))
  fi
done

if [[ ${ERRORS} -gt 0 ]]; then
  echo ""
  echo "error: ${ERRORS} file(s) missing — init incomplete" >&2
  state status=error error="${ERRORS} file(s) missing" log.error="Init incomplete: ${ERRORS} file(s) missing"
  exit 1
fi

state log.info="Verification passed — all files present"

# ── 11. Summary ───────────────────────────────────────────────────────────────
echo ""
echo "Canon initialized in ${PROJECT_DIR}/"
echo ""
echo "  .canon/"
echo "    agents/    — 6 agent personas"
echo "    skills/    — 8 domain knowledge modules"
echo "    execution/ — decision logs written here at runtime"
echo "    config.yaml"
echo "    ralph.yaml  <- edit success_criteria to match your strategy"
echo ""
echo "  .claude/commands/"
echo "    canon-start, develop, ralph-cycle, discover, register, quick-dev"
echo ""
echo "  src/types/"
echo "    TradeSignal.ts, RiskInterface.ts"
echo ""
echo "  package.json, tsconfig.json, .env.example, .gitignore, AGENTS.md"
echo ""
echo "Next steps:"
echo "  1. pnpm install"
echo "  2. Start claude and run /canon-start"

state phase=init status=running log.info="Canon framework initialized — ready for next phase"
