#!/usr/bin/env bats
#
# Tests for scripts/canon-scaffold.sh.
#
# Regression for the partial-scaffold bug observed during the MINT-04
# live smoke: cp -a was interrupted mid-copy, leaving the project dir
# half-populated (no AGENTS.md / package.json / runner.ts / .cursorrules)
# while the script appeared to "succeed" on the surface. These tests
# assert the script either copies every expected entry or aborts loudly.

setup() {
  TEST_TMP=$(mktemp -d)
  export TEST_TMP

  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/canon-scaffold.sh"
  SOURCE_TEMPLATES="${REPO_ROOT}/canon/templates"

  # Point DEGA_CORE_HOME at the repo so TEMPLATE_DIR resolves locally
  # (no GitHub fetch). The fetch helpers fall back to network for
  # agents/skills/commands; we mirror those under TEST_TMP/dega-core.
  DEGA_HOME="${TEST_TMP}/dega-core"
  mkdir -p "${DEGA_HOME}/canon"
  ln -s "${REPO_ROOT}/canon/templates" "${DEGA_HOME}/canon/templates"
  ln -s "${REPO_ROOT}/canon/agents" "${DEGA_HOME}/canon/agents"
  ln -s "${REPO_ROOT}/canon/skills" "${DEGA_HOME}/canon/skills"
  ln -s "${REPO_ROOT}/canon/commands" "${DEGA_HOME}/canon/commands"
  export DEGA_CORE_HOME="${DEGA_HOME}"

  # git config for the scaffold's `git commit` step (CI envs lack it)
  export GIT_AUTHOR_NAME="canon-scaffold-test"
  export GIT_AUTHOR_EMAIL="test@example.com"
  export GIT_COMMITTER_NAME="canon-scaffold-test"
  export GIT_COMMITTER_EMAIL="test@example.com"
}

teardown() {
  cd /
  rm -rf "${TEST_TMP}"
}

# ─── happy path ──────────────────────────────────────────────────────────────

@test "scaffold lands every expected file in an empty dir" {
  PROJECT="${TEST_TMP}/proj-happy"
  mkdir -p "${PROJECT}"
  cd "${PROJECT}"

  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]

  # Every path the in-script verify block checks must be present.
  for f in \
    AGENTS.md \
    CLAUDE.md \
    GEMINI.md \
    .cursorrules \
    package.json \
    tsconfig.json \
    vitest.config.ts \
    runner.ts \
    client-polymarket.ts \
    client-sportsbook.ts \
    dega-core.yaml \
    types/TradeSignal.ts \
    types/RiskInterface.ts \
    nba-momentum/strategy.md \
    nba-momentum/plan.md \
    strategies/arb-binary/signal.ts \
    strategies/arb-binary/main.ts \
    strategies/arb-binary/entry.ts \
    .canon/agents/dev.md \
    .canon/agents/strategy-architect.md \
    .canon/skills/prediction-markets.md \
    .canon/skills/canon-conventions.md \
    .canon/config.yaml \
    .claude/commands/canon-start.md \
    .claude/commands/develop.md; do
    [ -f "${PROJECT}/${f}" ] || {
      echo "missing: ${f}" >&2
      false
    }
  done

  # node_modules is intentionally skipped — pnpm install recreates it.
  [ ! -e "${PROJECT}/node_modules" ]
}

@test "scaffold copies the same number of top-level entries as templates (minus skips)" {
  PROJECT="${TEST_TMP}/proj-count"
  mkdir -p "${PROJECT}"
  cd "${PROJECT}"

  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]

  # Source minus node_modules and package-lock.json (the documented skips)
  expected=$(find "${SOURCE_TEMPLATES}" -mindepth 1 -maxdepth 1 \
    ! -name node_modules ! -name package-lock.json | wc -l | tr -d ' ')
  # Project minus things the scaffold creates itself (.git, .claude)
  actual=$(find "${PROJECT}" -mindepth 1 -maxdepth 1 \
    ! -name .git ! -name .claude | wc -l | tr -d ' ')
  [ "${expected}" -eq "${actual}" ]
}

# ─── failure / partial-state paths ───────────────────────────────────────────

@test "scaffold aborts loudly when template dir is missing" {
  PROJECT="${TEST_TMP}/proj-no-templates"
  mkdir -p "${PROJECT}"
  cd "${PROJECT}"

  rm "${DEGA_HOME}/canon/templates"
  mkdir "${DEGA_HOME}/canon/templates-stash"
  # canon-scaffold treats missing templates as a hard guard error
  DEGA_CORE_HOME="${TEST_TMP}/does-not-exist" run bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  echo "${output}" | grep -q "templates not found"
}

@test "scaffold's partial-copy guard fires when copy is incomplete" {
  # Simulate a silent partial copy by intercepting cp with a stub that
  # only copies the first two top-level entries. The script's post-copy
  # entry-count check must catch the shortfall and exit non-zero with a
  # clear error.
  PROJECT="${TEST_TMP}/proj-partial"
  mkdir -p "${PROJECT}"
  cd "${PROJECT}"

  STUB_BIN="${TEST_TMP}/stub-bin"
  mkdir -p "${STUB_BIN}"
  cat >"${STUB_BIN}/cp" <<STUB
#!/usr/bin/env bash
# Pass through sed-related calls; sabotage template-copy calls after
# the third entry by silently succeeding without copying.
COUNT_FILE="${TEST_TMP}/cp-count"
n=\$(cat "\${COUNT_FILE}" 2>/dev/null || echo 0)
n=\$((n + 1))
echo "\${n}" >"\${COUNT_FILE}"
if [[ \${n} -gt 3 ]]; then
  exit 0
fi
exec /bin/cp "\$@"
STUB
  chmod +x "${STUB_BIN}/cp"

  PATH="${STUB_BIN}:${PATH}" run bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  echo "${output}" | grep -q "template copy incomplete"
}

@test "scaffold's EXIT trap reports partial state when interrupted before completion" {
  # Force an early abort by making one of the fetch sources unreachable.
  # The script should exit non-zero AND the trap should write the
  # "aborted before completion" message.
  PROJECT="${TEST_TMP}/proj-trap"
  mkdir -p "${PROJECT}"
  cd "${PROJECT}"

  # Break the agents symlink so the local-first fetch falls through to
  # curl, then point BASE_URL at an unroutable host so curl fails fast.
  rm "${DEGA_HOME}/canon/agents"

  # The script hardcodes BASE_URL, so we exercise the fetch failure via
  # the `exit 1` in fetch(). That hits the trap before completion.
  run bash -c "
    set +e
    cd '${PROJECT}'
    # Make curl always fail by pointing at an invalid resolver
    curl() { return 1; }
    export -f curl
    bash '${SCRIPT}' 2>&1
  "
  [ "${status}" -ne 0 ]
  echo "${output}" | grep -q "aborted before completion"
}
