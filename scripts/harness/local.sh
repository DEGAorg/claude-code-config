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
