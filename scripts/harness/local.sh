#!/usr/bin/env bash
# Local harness backend — spawn/query/terminate processes on the current
# host via `nohup … & disown`, tracked by PID files.
#
# Do not source this file directly. Source the dispatcher:
#   source "$(dirname "${BASH_SOURCE[0]}")/harness/dispatcher.sh"
#
# Contract: scripts/harness/contract.md
#
# Portability: must run on bash 3.2 (macOS default). No associative
# arrays, no namerefs. Arguments are parsed as `key=value` pairs into
# locally-scoped `arg_<key>` variables by `_harness_local_parse_kv`.

set -euo pipefail

# --- Internal helpers ---

# Parse key=value arguments into variables named `arg_<key>` in the
# caller's scope. bash 3.2 has no associative arrays; we rely on the
# caller declaring each expected `arg_<key>` as `local` beforehand and
# us assigning into it via `eval`. All keys we accept are static and
# validated below — no user input reaches `eval`.
_harness_local_parse_kv() {
  local kv key val
  for kv in "$@"; do
    if [[ "${kv}" != *=* ]]; then
      echo "error: expected key=value, got: ${kv}" >&2
      return 1
    fi
    key="${kv%%=*}"
    val="${kv#*=}"
    case "${key}" in
    role | id | cwd | cmd | logfile | pid_dir | started_at_file | handle | started_at | grace | follow | lines) ;;
    *)
      echo "error: unknown argument key: ${key}" >&2
      return 1
      ;;
    esac
    # shellcheck disable=SC2034
    printf -v "arg_${key}" '%s' "${val}"
  done
}

_harness_local_require() {
  # _harness_local_require key1 key2 …  — checks arg_<key> is non-empty.
  local k val
  for k in "$@"; do
    eval "val=\${arg_${k}:-}"
    if [[ -z "${val}" ]]; then
      echo "error: missing required argument: ${k}" >&2
      return 1
    fi
  done
}

_harness_local_proc_lstart() {
  # Print the process start time (as a string suitable for equality
  # comparison) or empty if the PID is dead. We use `-o lstart=`, which
  # both BSD and GNU `ps` support, and treat the whole string as opaque.
  local pid=$1
  ps -o lstart= -p "${pid}" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# --- Contract implementations ---

harness::spawn_process() {
  local arg_role="" arg_id="" arg_cwd="" arg_cmd=""
  local arg_logfile="" arg_pid_dir="" arg_started_at_file=""
  _harness_local_parse_kv "$@" || return 1
  _harness_local_require role id cwd cmd logfile pid_dir || return 1

  if [[ ! -d "${arg_cwd}" ]]; then
    echo "error: cwd does not exist: ${arg_cwd}" >&2
    return 1
  fi

  mkdir -p "${arg_pid_dir}" "$(dirname "${arg_logfile}")" || {
    echo "error: cannot create pid_dir or log dir" >&2
    return 1
  }

  # Spawn detached. `setsid` would be cleaner but isn't on macOS by
  # default; `nohup … & disown` plus stdin redirect is portable.
  local pid
  nohup bash -c "cd '${arg_cwd}' && ${arg_cmd}" >>"${arg_logfile}" 2>&1 </dev/null &
  pid=$!
  disown "${pid}" 2>/dev/null || true

  printf '%s\n' "${pid}" >"${arg_pid_dir}/${arg_role}-${arg_id}.pid"

  if [[ -n "${arg_started_at_file}" ]]; then
    _harness_local_proc_lstart "${pid}" >"${arg_started_at_file}" || true
  fi

  printf '%s\n' "${pid}"
}

harness::query_status() {
  local arg_handle="" arg_started_at=""
  _harness_local_parse_kv "$@" || return 1
  _harness_local_require handle || return 1

  local pid="${arg_handle}"

  if ! kill -0 "${pid}" 2>/dev/null; then
    echo "dead"
    return 2
  fi

  if [[ -n "${arg_started_at}" ]]; then
    local actual
    actual="$(_harness_local_proc_lstart "${pid}")"
    if [[ "${actual}" != "${arg_started_at}" ]]; then
      # PID was reused — not our process.
      echo "dead"
      return 2
    fi
  fi

  echo "alive"
}

harness::terminate() {
  local arg_handle="" arg_grace=""
  _harness_local_parse_kv "$@" || return 1
  _harness_local_require handle || return 1

  local pid="${arg_handle}"
  local grace="${arg_grace:-5}"

  if ! kill -0 "${pid}" 2>/dev/null; then
    return 0
  fi

  kill -TERM "${pid}" 2>/dev/null || true

  local waited=0
  while ((waited < grace)); do
    if ! kill -0 "${pid}" 2>/dev/null; then
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done

  kill -KILL "${pid}" 2>/dev/null || true
  sleep 1
  if kill -0 "${pid}" 2>/dev/null; then
    echo "error: failed to terminate pid ${pid}" >&2
    return 1
  fi
}

harness::tail_logs() {
  local arg_logfile="" arg_follow="" arg_lines=""
  _harness_local_parse_kv "$@" || return 1
  _harness_local_require logfile || return 1

  local follow="${arg_follow:-false}"
  local lines="${arg_lines:-50}"

  if [[ ! -f "${arg_logfile}" ]]; then
    echo "error: logfile not found: ${arg_logfile}" >&2
    return 1
  fi

  if [[ "${follow}" == "true" ]]; then
    tail -n "${lines}" -F "${arg_logfile}"
  else
    tail -n "${lines}" "${arg_logfile}"
  fi
}

_harness_local_now_ms_utc() {
  # Emit an ISO-8601 UTC timestamp with millisecond precision:
  # YYYY-MM-DDTHH:MM:SS.sssZ. GNU date (Linux, or `gdate` on macOS via
  # coreutils) supports %3N directly. BSD `date` (macOS default) does
  # not — it prints `%3N` literally — so we detect that and fall back
  # to second precision with `.000Z` appended. The schema guarantees
  # the field format, not actual sub-second resolution.
  local ts
  if command -v gdate >/dev/null 2>&1; then
    gdate -u +"%Y-%m-%dT%H:%M:%S.%3NZ"
    return 0
  fi
  ts="$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")"
  # BSD `date` (macOS) consumes the `%` and leaves `3N` as a literal,
  # yielding `…:SS.3NZ`. GNU `date` produces three digits. Detect by
  # checking for exactly three digits between `.` and `Z`.
  if [[ ! "${ts}" =~ \.[0-9]{3}Z$ ]]; then
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    ts="${ts%Z}.000Z"
  fi
  printf '%s\n' "${ts}"
}

harness::emit_event() {
  # Append one JSON event line to an append-only events.jsonl file.
  #
  # Usage:
  #   harness::emit_event <events_file> <evt> [key=value | key:=json_value ...]
  #
  # `key=value` encodes the value as a JSON string (safely escaped by jq).
  # `key:=value` passes the value through as raw JSON — use this for
  # numbers, booleans, or null (e.g. `item:=3`, `duration_ms:=14671`).
  # `ts` is set automatically to ms-precision UTC; `evt` is the second
  # positional argument. Callers supply any additional event-specific
  # fields per scripts/harness/events-schema.md.
  local events_file="${1:-}"
  local evt="${2:-}"
  if [[ -z "${events_file}" || -z "${evt}" ]]; then
    echo "error: harness::emit_event <events_file> <evt> [key=value | key:=json ...]" >&2
    return 1
  fi
  shift 2

  local ts
  ts="$(_harness_local_now_ms_utc)"

  local -a jq_args=(-cn --arg ts "${ts}" --arg evt "${evt}")
  # shellcheck disable=SC2016 # single quotes intentional — these are jq variables, not shell expansions
  local obj='{ts: $ts, evt: $evt}'

  local kv key val is_raw
  for kv in "$@"; do
    if [[ "${kv}" == *:=* ]]; then
      key="${kv%%:=*}"
      val="${kv#*:=}"
      is_raw=1
    elif [[ "${kv}" == *=* ]]; then
      key="${kv%%=*}"
      val="${kv#*=}"
      is_raw=0
    else
      echo "error: harness::emit_event: expected key=value, got: ${kv}" >&2
      return 1
    fi
    if [[ ! "${key}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
      echo "error: harness::emit_event: invalid field name: ${key}" >&2
      return 1
    fi
    if ((is_raw)); then
      jq_args+=(--argjson "${key}" "${val}")
    else
      jq_args+=(--arg "${key}" "${val}")
    fi
    obj="${obj%\}}, ${key}: \$${key}}"
  done

  mkdir -p "$(dirname "${events_file}")" || {
    echo "error: cannot create events_file directory: $(dirname "${events_file}")" >&2
    return 1
  }

  jq "${jq_args[@]}" "${obj}" >>"${events_file}"
}

harness::list_active() {
  local arg_pid_dir=""
  _harness_local_parse_kv "$@" || return 1
  _harness_local_require pid_dir || return 1

  if [[ ! -d "${arg_pid_dir}" ]]; then
    # Nothing tracked yet — not an error.
    return 0
  fi

  local pid_file base role id pid
  for pid_file in "${arg_pid_dir}"/*.pid; do
    [[ -e "${pid_file}" ]] || continue
    base="$(basename "${pid_file}" .pid)"
    role="${base%-*}"
    id="${base##*-}"
    pid="$(head -n1 "${pid_file}" 2>/dev/null | tr -d '[:space:]')"
    if [[ -z "${pid}" ]] || ! kill -0 "${pid}" 2>/dev/null; then
      rm -f "${pid_file}"
      continue
    fi
    printf '%s %s %s\n' "${role}" "${id}" "${pid}"
  done
}
