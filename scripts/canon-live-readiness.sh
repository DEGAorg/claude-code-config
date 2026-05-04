#!/usr/bin/env bash
# Canon live-readiness — drive a project from "dry-run validated" to "live trading".
#
# This is the deterministic spine of `/canon-start --live`. The slash
# command stays a thin wrapper; this script is what the agent actually
# invokes so failures are reproducible and unit-testable.
#
# Stages (mirrored in .canon/state.json `phase=live`, `status=...`):
#   1. deposit-pending  — print EOA address + funding instructions
#   2. funds-detected   — first non-zero native USDC balance observed
#   3. onboarding       — running `canon-cli onboard --execute --fund`
#   4. ready            — Safe deployed, V1+V2 approvals set, builder
#                         creds in place, collateral > 0
#   5. running          — live runner started, PID written to state
#
# Idempotency:
#   - On re-run, stage 1 detects an already-onboarded wallet
#     (funderDeployed + approvalsReady + credsReady + collateral > 0)
#     and skips straight to stage 5.
#   - The deposit timeout (default 30 min) writes
#     `phase=live, status=timeout`. Re-running resumes the polling
#     because the EOA address derives deterministically from the PK.
#
# Env overrides:
#   CANON_LIVE_POLL_SECS    — balance poll cadence (default 10s)
#   CANON_LIVE_TIMEOUT_SECS — deposit timeout (default 1800s / 30 min)
#   DEGA_CORE_HOME          — DEGA Core install root (default ~/.degacore)
#
# Exits non-zero on any failure with a state-file message the TUI/agent
# can surface to the operator.

set -euo pipefail

POLL_SECS="${CANON_LIVE_POLL_SECS:-10}"
TIMEOUT_SECS="${CANON_LIVE_TIMEOUT_SECS:-1800}"
STATE=".canon/state.json"
DEGA_CORE_HOME="${DEGA_CORE_HOME:-${HOME}/.degacore}"
TUI_WRITE="${DEGA_CORE_HOME}/scripts/terminal-ui-write.sh"
CANON_CLI="${CANON_CLI:-${DEGA_CORE_HOME}/bin/canon-cli}"

# ── State writer (idempotent if TUI helper missing) ──────────────────────────
tui() {
  if [[ -f "${TUI_WRITE}" ]]; then
    bash "${TUI_WRITE}" "${STATE}" "$@" || true
  fi
}

# ── Bigfloat compare (avoid bash arithmetic on decimals) ─────────────────────
gt0() {
  awk -v a="${1:-0}" 'BEGIN { exit !(a+0 > 0) }'
}

# ── Hard barrier: src/main.ts must exist ─────────────────────────────────────
# The user is required to run /canon-start (dry-run flow) at least once
# to generate src/main.ts and validate the strategy compiles. /canon-start
# --live is for the *transition* — not the initial build.
if [[ ! -f "src/main.ts" ]]; then
  echo "error: src/main.ts not found — run /canon-start (dry-run) first to build the strategy" >&2
  tui phase=live status=error \
    log.error="src/main.ts missing — run /canon-start in dry-run first"
  exit 1
fi

mkdir -p .canon

# ── Read current onboarding status (skip-when-ready short-circuit) ───────────
onboard_status() {
  "${CANON_CLI}" onboard --status --venue polymarket 2>&1 || true
}

status_json=$(onboard_status)
funder_address=$(printf '%s' "${status_json}" | jq -r '.data.funderAddress // empty' 2>/dev/null || echo "")

if [[ -z "${funder_address}" ]]; then
  echo "error: canon-cli onboard --status returned no funder address" >&2
  echo "${status_json}" >&2
  tui phase=live status=error log.error="canon-cli onboard --status failed"
  exit 1
fi

is_ready() {
  local s="$1"
  local fd ar cr fc
  fd=$(printf '%s' "${s}" | jq -r '.data.funderDeployed // false')
  ar=$(printf '%s' "${s}" | jq -r '.data.approvalsReady // false')
  cr=$(printf '%s' "${s}" | jq -r '.data.credsReady // false')
  fc=$(printf '%s' "${s}" | jq -r '.data.fundedCollateral // 0')
  [[ "${fd}" == "true" && "${ar}" == "true" && "${cr}" == "true" ]] &&
    gt0 "${fc}"
}

# ── Stage 1+2+3: deposit → detect → onboard (skipped if already ready) ───────
if is_ready "${status_json}"; then
  collateral=$(printf '%s' "${status_json}" | jq -r '.data.fundedCollateral // 0')
  echo "canon-live-readiness: already onboarded (Safe ${funder_address}, collateral ${collateral} pUSD) — skipping deposit/onboard"
  tui phase=live status=ready \
    "metric.safe=${funder_address}" \
    "metric.collateral=${collateral}" \
    log.info="Already onboarded — going live"
else
  # Get the EOA address for deposit instructions
  eoa_json=$("${CANON_CLI}" wallet address 2>&1 || true)
  eoa_address=$(printf '%s' "${eoa_json}" | jq -r '.data.address // empty' 2>/dev/null || echo "")
  if [[ -z "${eoa_address}" ]]; then
    echo "error: canon-cli wallet address returned no address" >&2
    echo "${eoa_json}" >&2
    tui phase=live status=error log.error="canon-cli wallet address failed"
    exit 1
  fi

  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  echo "  Canon live mode — wallet onboarding required"
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""
  echo "  Send native USDC on Polygon to your EOA:"
  echo "    ${eoa_address}"
  echo ""
  echo "  Do NOT send to the Safe (${funder_address}) — Canon will pull"
  echo "  funds from the EOA into the Safe via a gasless permit."
  echo ""
  echo "  Polling every ${POLL_SECS}s, timeout ${TIMEOUT_SECS}s."
  echo ""

  tui phase=live status=deposit-pending \
    "metric.eoa=${eoa_address}" \
    "metric.safe=${funder_address}" \
    "metric.poll_secs=${POLL_SECS}" \
    "metric.timeout_secs=${TIMEOUT_SECS}" \
    log.info="Awaiting native USDC deposit at ${eoa_address}"

  # Poll for funds
  start_epoch=$(date +%s)
  detected_amount=0
  while :; do
    elapsed=$(($(date +%s) - start_epoch))
    if ((elapsed > TIMEOUT_SECS)); then
      tui phase=live status=timeout \
        "metric.eoa=${eoa_address}" \
        "metric.safe=${funder_address}" \
        "metric.elapsed_secs=${elapsed}" \
        "error=no deposit detected at ${eoa_address} after ${elapsed}s" \
        log.error="Deposit timeout — re-run /canon-start --live to resume"
      echo "error: timeout — no deposit at ${eoa_address} after ${elapsed}s" >&2
      exit 1
    fi

    bal_json=$("${CANON_CLI}" balance 2>/dev/null || echo '{"data":[]}')
    detected_amount=$(printf '%s' "${bal_json}" |
      jq -r '.data[]? | select(.currency == "USDC") | .amount // 0' 2>/dev/null |
      head -n1)
    detected_amount="${detected_amount:-0}"

    if gt0 "${detected_amount}"; then
      echo "canon-live-readiness: detected ${detected_amount} USDC at ${eoa_address}"
      tui phase=live status=funds-detected \
        "metric.detected_amount=${detected_amount}" \
        "metric.elapsed_secs=${elapsed}" \
        log.info="Detected ${detected_amount} USDC — onboarding"
      break
    fi

    tui "metric.detected_amount=${detected_amount}" \
      "metric.elapsed_secs=${elapsed}"

    sleep "${POLL_SECS}"
  done

  # Stage 3: run onboard --execute --fund (no --amount → pulls full balance)
  tui phase=live status=onboarding \
    log.info="Running canon-cli onboard --execute --fund (pulling ${detected_amount} USDC)"
  if ! "${CANON_CLI}" onboard --execute --fund --venue polymarket; then
    tui phase=live status=error \
      log.error="canon-cli onboard --execute --fund failed"
    echo "error: onboarding failed — see canon-cli output above" >&2
    exit 1
  fi

  # Verify the chain converged
  status_json=$(onboard_status)
  if ! is_ready "${status_json}"; then
    tui phase=live status=error \
      log.error="Onboard ran but verification reports incomplete state"
    echo "error: post-onboard verification failed" >&2
    echo "${status_json}" >&2
    exit 1
  fi
  collateral=$(printf '%s' "${status_json}" | jq -r '.data.fundedCollateral // 0')
  tui phase=live status=ready \
    "metric.collateral=${collateral}" \
    log.info="Wallet ready — ${collateral} pUSD on Safe ${funder_address}"
  echo "canon-live-readiness: wallet ready (${collateral} pUSD on Safe ${funder_address})"
fi

# ── Stop any existing dry-run runner ─────────────────────────────────────────
# canon-runner.sh refuses to start if .canon/execution/runner.pid exists
# and points at a live process. The standard /canon-start flow leaves a
# dry-run runner backgrounded for validation; --live needs to stop it
# before launching the live counterpart. SIGTERM, then 5s grace, then
# the live launch fires regardless — runner.sh's own cleanup trap will
# deal with stragglers.
if [[ -f .canon/execution/runner.pid ]]; then
  old_pid=$(cat .canon/execution/runner.pid 2>/dev/null || echo "")
  if [[ -n "${old_pid}" ]] && kill -0 "${old_pid}" 2>/dev/null; then
    echo "canon-live-readiness: stopping existing dry-run runner (PID ${old_pid})..."
    tui log.info="Stopping dry-run runner (PID ${old_pid}) before live launch"
    kill -TERM "${old_pid}" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      kill -0 "${old_pid}" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "${old_pid}" 2>/dev/null; then
      kill -KILL "${old_pid}" 2>/dev/null || true
      sleep 1
    fi
  fi
  rm -f .canon/execution/runner.pid
fi

# ── Stage 5: launch live runner ──────────────────────────────────────────────
echo "canon-live-readiness: launching live runner..."
tui phase=live status=running log.info="Starting live runner"

bash "${DEGA_CORE_HOME}/scripts/canon-runner.sh" --live &
RUNNER_PID=$!
disown
sleep 2

if kill -0 "${RUNNER_PID}" 2>/dev/null; then
  echo "canon-live-readiness: OK — live runner started (PID ${RUNNER_PID})"
  tui "metric.runner_pid=${RUNNER_PID}" \
    log.info="Live runner running (PID ${RUNNER_PID})"
else
  tui phase=live status=error log.error="Live runner failed to start"
  echo "error: live runner failed to start" >&2
  if [[ -f .canon/execution/runner.log ]]; then
    tail -n 20 .canon/execution/runner.log >&2 || true
  fi
  exit 1
fi
