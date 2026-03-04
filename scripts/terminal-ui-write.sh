#!/usr/bin/env bash
# Atomic terminal-ui state writer for bash callers.
#
# Mirrors scripts/terminal-ui/src/write.ts — reads existing state,
# merges partial updates, caps the log ring buffer at 50, and
# atomically renames into place.
#
# Usage:
#   bash scripts/terminal-ui-write.sh <state-file> [field=value ...]
#
# Fields:
#   phase=<string>       Pipeline phase (e.g., "init", "scaffold", "run")
#   status=<enum>        running | paused | idle | error
#   error=<string>       Error message (use error= to clear)
#   startedAt=<iso8601>  Session start time
#   metric.<key>=<val>   Add/update a metrics key (shallow merge)
#   metrics=reset        Clear all metrics before applying new metric.* keys
#   log.<level>=<msg>    Append a log entry (level: info|warn|error|debug)
#
# Examples:
#   # Set phase and status
#   bash scripts/terminal-ui-write.sh .canon/state.json phase=scaffold status=running
#
#   # Append a log entry and set a metric
#   bash scripts/terminal-ui-write.sh .canon/state.json log.info="Starting build" metric.iteration=3
#
#   # Clear error
#   bash scripts/terminal-ui-write.sh .canon/state.json status=running error=

set -euo pipefail

LOG_BUFFER_MAX=50

STATE_FILE="${1:-}"

if [[ -z "${STATE_FILE}" ]]; then
	echo "error: usage: terminal-ui-write.sh <state-file> [field=value ...]" >&2
	exit 1
fi

shift

# Read existing state or create default
NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

if [[ -f "${STATE_FILE}" ]]; then
	STATE=$(cat "${STATE_FILE}")
else
	STATE=$(jq -n \
		--arg now "${NOW}" \
		'{
      phase: "init",
      status: "idle",
      startedAt: $now,
      updatedAt: $now,
      logs: [],
      error: null,
      metrics: {}
    }')
fi

# Collect updates into jq filter parts
JQ_FILTERS=".updatedAt = \"${NOW}\""
NEW_LOGS="[]"
METRIC_UPDATES=""
METRICS_RESET=false

for arg in "$@"; do
	key="${arg%%=*}"
	val="${arg#*=}"

	case "${key}" in
	phase | status | startedAt)
		JQ_FILTERS="${JQ_FILTERS} | .${key} = \"${val}\""
		;;
	error)
		if [[ -z "${val}" ]]; then
			JQ_FILTERS="${JQ_FILTERS} | .error = null"
		else
			JQ_FILTERS="${JQ_FILTERS} | .error = \"${val}\""
		fi
		;;
	metrics)
		if [[ "${val}" == "reset" ]]; then
			METRICS_RESET=true
		else
			echo "error: metrics only supports 'reset' (got '${val}')" >&2
			exit 1
		fi
		;;
	metric.*)
		metric_key="${key#metric.}"
		# Attempt to parse as JSON value; fall back to string
		if echo "${val}" | jq -e '.' >/dev/null 2>&1; then
			METRIC_UPDATES="${METRIC_UPDATES} | .metrics.\"${metric_key}\" = (\"${val}\" | fromjson)"
		else
			METRIC_UPDATES="${METRIC_UPDATES} | .metrics.\"${metric_key}\" = \"${val}\""
		fi
		;;
	log.*)
		level="${key#log.}"
		case "${level}" in
		info | warn | error | debug) ;;
		*)
			echo "error: invalid log level '${level}' (use info|warn|error|debug)" >&2
			exit 1
			;;
		esac
		NEW_LOGS=$(echo "${NEW_LOGS}" | jq \
			--arg ts "${NOW}" \
			--arg lvl "${level}" \
			--arg msg "${val}" \
			'. + [{ts: $ts, level: $lvl, msg: $msg}]')
		;;
	*)
		echo "error: unknown field '${key}'" >&2
		exit 1
		;;
	esac
done

# Append new logs and enforce ring buffer cap
if [[ "${NEW_LOGS}" != "[]" ]]; then
	JQ_FILTERS="${JQ_FILTERS} | .logs = (.logs + ${NEW_LOGS} | .[-${LOG_BUFFER_MAX}:])"
fi

# Reset metrics if requested, then apply individual updates
if [[ "${METRICS_RESET}" == "true" ]]; then
	JQ_FILTERS="${JQ_FILTERS} | .metrics = {}"
fi
if [[ -n "${METRIC_UPDATES}" ]]; then
	JQ_FILTERS="${JQ_FILTERS}${METRIC_UPDATES}"
fi

# Atomic write: temp file in same directory → rename
STATE_DIR=$(dirname "${STATE_FILE}")
mkdir -p "${STATE_DIR}"
TMP_FILE="${STATE_DIR}/.tmp-$$-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"

echo "${STATE}" | jq "${JQ_FILTERS}" >"${TMP_FILE}"
mv "${TMP_FILE}" "${STATE_FILE}"
