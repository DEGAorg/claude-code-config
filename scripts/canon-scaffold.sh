#!/usr/bin/env bash
# Canon Scaffold — scaffolds a Canon prediction-market project.
#
# Usage: bash "$DEGA_CORE_HOME/scripts/canon-scaffold.sh" [--force]
#
# Run from inside the target project directory (must be empty or use --force).
# Copies canon/templates/ wholesale as the project root, then fetches agents,
# skills, and commands from GitHub. Deterministic, idempotent, zero agent
# guesswork.

set -euo pipefail

REPO="DEGAorg/claude-code-config"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

PROJECT_DIR="$(pwd)"
PROJECT_NAME="$(basename "${PROJECT_DIR}")"
STATE_FILE="${PROJECT_DIR}/.canon/state.json"
DEGA_CORE_HOME="${DEGA_CORE_HOME:-${HOME}/.degacore}"
TUI_WRITE="${DEGA_CORE_HOME}/scripts/terminal-ui-write.sh"
TEMPLATE_DIR="${DEGA_CORE_HOME}/canon/templates"

# ── Helper: write state to dashboard (no-op if writer not installed) ─────────
state() {
  if [[ -f "${TUI_WRITE}" ]]; then
    bash "${TUI_WRITE}" "${STATE_FILE}" "$@" || true
  fi
}

# ── Guard: don't run inside claude-code-config itself ────────────────────────
if [[ -f "AGENTS.md" ]] && grep -q "claude-code-config" "AGENTS.md" 2>/dev/null; then
  echo "error: run canon-init from your strategy project, not from claude-code-config" >&2
  exit 1
fi

# ── Guard: check for existing .canon/ ────────────────────────────────────────
if [[ -d ".canon" && "${FORCE}" != "true" ]]; then
  echo "error: .canon/ already exists. Use --force to overwrite." >&2
  exit 1
fi

# ── Guard: templates directory must exist ────────────────────────────────────
if [[ ! -d "${TEMPLATE_DIR}" ]]; then
  echo "error: templates not found at ${TEMPLATE_DIR}" >&2
  echo "  ensure DEGA_CORE_HOME is set correctly (current: ${DEGA_CORE_HOME})" >&2
  exit 1
fi

echo "canon-init: initializing '${PROJECT_NAME}' in ${PROJECT_DIR}"
echo ""

state phase=init status=running log.info="Canon init starting for '${PROJECT_NAME}'"

# ── Helper: fetch a file from GitHub ─────────────────────────────────────────
fetch() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "${dst}")"
  if ! curl -sfL "${BASE_URL}/${src}" -o "${dst}"; then
    echo "error: failed to fetch ${src}" >&2
    exit 1
  fi
}

# ── Helper: portable in-place sed (avoids macOS/Linux -i difference) ─────────
sed_inplace() {
  local expr="$1" file="$2"
  local tmp="${file}.tmp.$$"
  sed "${expr}" "${file}" >"${tmp}" && mv "${tmp}" "${file}"
}

# ── 0. Ensure git repo exists (orchestrator needs it for worktree isolation)
if [[ ! -d ".git" ]]; then
  echo "→ initializing git repo..."
  git init -q
  state log.info="Git repo initialized"
fi

# ── 1. Copy templates as project root ────────────────────────────────────────
echo "→ copying project templates..."
cp -a "${TEMPLATE_DIR}/." "${PROJECT_DIR}/"

# Stamp the actual project name into package.json and dega-core.yaml
sed_inplace "s/\"name\": \"canon-templates\"/\"name\": \"${PROJECT_NAME}\"/" package.json
sed_inplace "s/strategy: canon-templates/strategy: ${PROJECT_NAME}/" dega-core.yaml

state log.info="Project templates copied"

# ── 2. Create runtime directories ────────────────────────────────────────────
mkdir -p .canon/execution .canon/workflows
touch .canon/execution/.gitkeep

# ── 3. Fetch agents ─────────────────────────────────────────────────────────
echo "→ fetching agents..."
state log.info="Fetching 6 agent personas..."
for agent in strategy-architect risk-analyst market-analyst dev qa deployment-ops; do
  fetch "canon/agents/${agent}.md" ".canon/agents/${agent}.md"
done
state log.info="Agents fetched"

# ── 4. Fetch skills ─────────────────────────────────────────────────────────
echo "→ fetching skills..."
state log.info="Fetching 8 domain skills..."
for skill in prediction-markets polymarket risk-management strategy-patterns \
  backtesting arena-tracking orchestrator canon-conventions; do
  fetch "canon/skills/${skill}.md" ".canon/skills/${skill}.md"
done
state log.info="Skills fetched"

# ── 5. Fetch commands ───────────────────────────────────────────────────────
echo "→ fetching commands..."
state log.info="Fetching 6 slash commands..."
for cmd in develop ralph-cycle discover register quick-dev canon-start; do
  fetch "canon/commands/${cmd}.md" ".claude/commands/${cmd}.md"
done
state log.info="Commands fetched"

# ── 6. Verify ───────────────────────────────────────────────────────────────
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
  dega-core.yaml \
  nba-momentum/strategy.md \
  nba-momentum/plan.md \
  .claude/commands/canon-start.md \
  .claude/commands/develop.md \
  types/TradeSignal.ts \
  types/RiskInterface.ts \
  client-polymarket.ts \
  client-sportsbook.ts \
  runner.ts \
  strategies/arb-binary/signal.ts \
  strategies/arb-binary/main.ts \
  strategies/arb-binary/entry.ts \
  package.json \
  tsconfig.json \
  vitest.config.ts \
  AGENTS.md \
  CLAUDE.md \
  GEMINI.md \
  .cursorrules; do
  if [[ ! -f "${f}" ]]; then
    echo "  MISSING: ${f}" >&2
    ERRORS=$((ERRORS + 1))
  fi
done

if [[ ${ERRORS} -gt 0 ]]; then
  echo ""
  echo "error: ${ERRORS} file(s) missing — init incomplete" >&2
  state status=error error="${ERRORS} file(s) missing" \
    log.error="Init incomplete: ${ERRORS} file(s) missing"
  exit 1
fi

state log.info="Verification passed — all files present"

# ── 7. Summary ──────────────────────────────────────────────────────────────
echo ""
echo "Canon initialized in ${PROJECT_DIR}/"
echo ""
echo "  Project (from canon/templates/):"
echo "    runner.ts          — configurable strategy poll loop"
echo "    types/             — TradeSignal, RiskInterface"
echo "    client-*.ts        — Polymarket, sportsbook API clients"
echo "    strategies/        — arb-binary + STRATEGY-INDEX.md"
echo "    __tests__/         — full test suite"
echo "    package.json, tsconfig.json, vitest.config.ts"
echo ""
echo "  .canon/"
echo "    agents/    — 6 agent personas"
echo "    skills/    — 8 domain knowledge modules"
echo "    execution/ — decision logs written here at runtime"
echo "    config.yaml"
echo ""
echo "  dega-core.yaml  <- edit success_criteria to match your strategy"
echo ""
echo "  .claude/commands/"
echo "    canon-start, develop, ralph-cycle, discover, register, quick-dev"
echo ""
echo "  AGENTS.md          <- project configuration (source of truth)"
echo "  CLAUDE.md          <- shim → AGENTS.md"
echo "  GEMINI.md          <- shim → AGENTS.md"
echo "  .cursorrules       <- shim → AGENTS.md"
echo ""

# ── 8. Initial git commit (orchestrator needs at least one commit) ──────────
echo "→ creating initial commit..."
git add -A
git commit -q -m "scaffold: Canon framework initialized"
state log.info="Initial commit created"

echo ""
echo "Next steps:"
echo "  1. pnpm install"
echo "  2. Start claude and run /canon-start"

state phase=init status=running \
  log.info="Canon framework initialized — ready for next phase"
