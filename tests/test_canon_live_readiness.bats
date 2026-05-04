#!/usr/bin/env bats
#
# Tests for scripts/canon-live-readiness.sh — the deterministic spine
# behind `/canon-start --live`.
#
# The script depends on `canon-cli` for status/balance/onboard; we
# stub those by writing a fake `canon-cli` that reads scripted
# responses from $TEST_TMP/canon-cli-script. Each test sets up the
# script's responses, invokes the readiness flow, and asserts on
# .canon/state.json transitions.

setup() {
  TEST_TMP=$(mktemp -d)
  export TEST_TMP

  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/canon-live-readiness.sh"

  # Project root: tests run from a tmp project dir
  cd "${TEST_TMP}"
  mkdir -p src .canon
  touch src/main.ts

  # Fast polling so timeout tests don't take 30 minutes
  export CANON_LIVE_POLL_SECS=1
  export CANON_LIVE_TIMEOUT_SECS=2

  # Fake canon-cli — picks responses from a scripted file based on subcommand
  STUB_BIN="${TEST_TMP}/bin"
  mkdir -p "${STUB_BIN}"
  cat >"${STUB_BIN}/canon-cli" <<'STUB'
#!/usr/bin/env bash
# $1 = first arg ("onboard" / "wallet" / "balance"), $2 = subcommand or option
SCRIPT_FILE="${TEST_TMP}/canon-cli-script"

case "$1" in
  onboard)
    if [[ "$2" == "--status" ]]; then
      [[ -f "${SCRIPT_FILE}.onboard-status" ]] && cat "${SCRIPT_FILE}.onboard-status" || \
        echo '{"ok":true,"data":{"funderDeployed":false,"approvalsReady":false,"credsReady":false,"fundedCollateral":0,"funderAddress":"0xSafe1111111111111111111111111111111111"}}'
    elif [[ "$2" == "--execute" ]]; then
      if [[ -f "${SCRIPT_FILE}.onboard-execute" ]]; then
        cat "${SCRIPT_FILE}.onboard-execute"
        exit "$(cat "${SCRIPT_FILE}.onboard-execute-rc" 2>/dev/null || echo 0)"
      fi
      echo '{"ok":true,"data":{}}'
    fi
    ;;
  wallet)
    if [[ "$2" == "address" ]]; then
      [[ -f "${SCRIPT_FILE}.wallet-address" ]] && cat "${SCRIPT_FILE}.wallet-address" || \
        echo '{"ok":true,"data":{"address":"0xEOA1111111111111111111111111111111111111"}}'
    fi
    ;;
  balance)
    [[ -f "${SCRIPT_FILE}.balance" ]] && cat "${SCRIPT_FILE}.balance" || echo '{"ok":true,"data":[]}'
    ;;
esac
STUB
  chmod +x "${STUB_BIN}/canon-cli"
  export CANON_CLI="${STUB_BIN}/canon-cli"

  # Fake DEGA_CORE_HOME — point canon-runner.sh at a no-op so we don't
  # actually launch tsx, but use the real terminal-ui-write.sh so state
  # transitions land on disk and the assertions can observe them.
  FAKE_DEGA_CORE_HOME="${TEST_TMP}/degacore"
  mkdir -p "${FAKE_DEGA_CORE_HOME}/scripts"
  cat >"${FAKE_DEGA_CORE_HOME}/scripts/canon-runner.sh" <<'RUNNER'
#!/usr/bin/env bash
# Test runner stub — sleeps long enough that kill -0 succeeds on the
# parent script's verification check, then exits cleanly.
sleep 30
RUNNER
  chmod +x "${FAKE_DEGA_CORE_HOME}/scripts/canon-runner.sh"
  ln -s "${REPO_ROOT}/scripts/terminal-ui-write.sh" \
    "${FAKE_DEGA_CORE_HOME}/scripts/terminal-ui-write.sh"
  export DEGA_CORE_HOME="${FAKE_DEGA_CORE_HOME}"
}

teardown() {
  trash "${TEST_TMP}" 2>/dev/null || rm -rf "${TEST_TMP}"
}

# ---------------------------------------------------------------------------
# Hard-barrier guard
# ---------------------------------------------------------------------------

@test "exits non-zero when src/main.ts is missing" {
  rm -f src/main.ts
  run bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" =~ "src/main.ts not found" ]]
  [ "$(jq -r '.status' .canon/state.json 2>/dev/null)" = "error" ]
}

# ---------------------------------------------------------------------------
# Skip-when-already-onboarded
# ---------------------------------------------------------------------------

@test "skips deposit/onboard when already onboarded and launches live runner" {
  cat >"${TEST_TMP}/canon-cli-script.onboard-status" <<'EOF'
{"ok":true,"data":{"funderDeployed":true,"approvalsReady":true,"credsReady":true,"fundedCollateral":42.5,"funderAddress":"0xSafe1111111111111111111111111111111111"}}
EOF

  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" =~ "already onboarded" ]]
  [[ "${output}" =~ "live runner started" ]]
  [ "$(jq -r '.phase' .canon/state.json)" = "live" ]
  [ "$(jq -r '.status' .canon/state.json)" = "running" ]
}

# ---------------------------------------------------------------------------
# Deposit detection → onboard → ready → running
# ---------------------------------------------------------------------------

@test "polls until funds arrive, runs onboard, reaches running" {
  # First status: nothing onboarded
  cat >"${TEST_TMP}/canon-cli-script.onboard-status" <<'EOF'
{"ok":true,"data":{"funderDeployed":false,"approvalsReady":false,"credsReady":false,"fundedCollateral":0,"funderAddress":"0xSafe1111111111111111111111111111111111"}}
EOF
  cat >"${TEST_TMP}/canon-cli-script.balance" <<'EOF'
{"ok":true,"data":[{"currency":"USDC","address":"0xEOA","amount":1.5}]}
EOF

  # The onboard --execute call flips status to "fully onboarded" by
  # rewriting the status response after it's invoked. The stub doesn't
  # have callback hooks, so we pre-script the next status read.
  cat >"${FAKE_DEGA_CORE_HOME}/scripts/canon-runner.sh" <<RUNNER
#!/usr/bin/env bash
# After onboard runs, the second status check needs to report ready
cat >"${TEST_TMP}/canon-cli-script.onboard-status" <<EOFR
{"ok":true,"data":{"funderDeployed":true,"approvalsReady":true,"credsReady":true,"fundedCollateral":1.5,"funderAddress":"0xSafe1111111111111111111111111111111111"}}
EOFR
sleep 30
RUNNER
  chmod +x "${FAKE_DEGA_CORE_HOME}/scripts/canon-runner.sh"

  # Wire the post-onboard status into the stub by intercepting onboard --execute
  # to overwrite the status file before returning success.
  cat >"${STUB_BIN}/canon-cli" <<STUB
#!/usr/bin/env bash
case "\$1" in
  onboard)
    if [[ "\$2" == "--status" ]]; then
      cat "${TEST_TMP}/canon-cli-script.onboard-status"
    elif [[ "\$2" == "--execute" ]]; then
      cat >"${TEST_TMP}/canon-cli-script.onboard-status" <<EOFR
{"ok":true,"data":{"funderDeployed":true,"approvalsReady":true,"credsReady":true,"fundedCollateral":1.5,"funderAddress":"0xSafe1111111111111111111111111111111111"}}
EOFR
      echo '{"ok":true,"data":{}}'
    fi
    ;;
  wallet)
    [[ "\$2" == "address" ]] && echo '{"ok":true,"data":{"address":"0xEOA1111111111111111111111111111111111111"}}'
    ;;
  balance)
    cat "${TEST_TMP}/canon-cli-script.balance"
    ;;
esac
STUB

  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" =~ "detected 1.5 USDC" ]]
  [[ "${output}" =~ "wallet ready" ]]
  [[ "${output}" =~ "live runner started" ]]
  [ "$(jq -r '.phase' .canon/state.json)" = "live" ]
  [ "$(jq -r '.status' .canon/state.json)" = "running" ]
}

# ---------------------------------------------------------------------------
# Timeout
# ---------------------------------------------------------------------------

@test "times out when no deposit arrives within the window" {
  # Empty balance for the duration of the test
  cat >"${TEST_TMP}/canon-cli-script.balance" <<'EOF'
{"ok":true,"data":[]}
EOF

  run bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" =~ "timeout" ]]
  [ "$(jq -r '.phase' .canon/state.json)" = "live" ]
  [ "$(jq -r '.status' .canon/state.json)" = "timeout" ]
  jq -e '.error | test("no deposit detected")' .canon/state.json >/dev/null
}

# ---------------------------------------------------------------------------
# canon-cli onboard --status itself failing
# ---------------------------------------------------------------------------

@test "stops a stale dry-run runner before launching live" {
  cat >"${TEST_TMP}/canon-cli-script.onboard-status" <<'EOF'
{"ok":true,"data":{"funderDeployed":true,"approvalsReady":true,"credsReady":true,"fundedCollateral":42.5,"funderAddress":"0xSafe1111111111111111111111111111111111"}}
EOF

  # Drop a dead PID into runner.pid so the file exists but kill -0 fails
  mkdir -p .canon/execution
  echo "999999999" > .canon/execution/runner.pid

  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  # runner.pid should have been cleaned up before launching the live runner
  [ ! -f .canon/execution/runner.pid ]
  [ "$(jq -r '.status' .canon/state.json)" = "running" ]
}

@test "exits non-zero when canon-cli onboard --status returns no funder address" {
  # Empty data
  cat >"${TEST_TMP}/canon-cli-script.onboard-status" <<'EOF'
{"ok":false,"error":"auth failed"}
EOF

  run bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" =~ "no funder address" ]]
  [ "$(jq -r '.status' .canon/state.json)" = "error" ]
}
