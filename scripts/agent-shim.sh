#!/usr/bin/env bash
# Agent-agnostic shim — sourced by orchestrator scripts to abstract
# provider-specific commands, flags, env vars, and config paths.
#
# Detection heuristic (first match wins):
#   1. DEGA_PROVIDER env var (explicit override)
#   2. Parent process name (claude, gemini, codex)
#   3. Session env vars (CLAUDECODE, GEMINI_SESSION, etc.)
#   4. Fallback: claude
#
# Usage: source "${SCRIPT_DIR}/agent-shim.sh"

# Guard against double-sourcing
if [[ -n "${_DEGA_AGENT_SHIM_LOADED:-}" ]]; then
  return 0
fi
_DEGA_AGENT_SHIM_LOADED=1

# --- Core home ---

DEGA_CORE_HOME="${DEGA_CORE_HOME:-${HOME}/.degacore}"
export DEGA_CORE_HOME

# --- Provider detection ---

_dega_detect_provider() {
  # 1. Explicit env var
  if [[ -n "${DEGA_PROVIDER:-}" ]]; then
    echo "${DEGA_PROVIDER}"
    return
  fi

  # 2. Parent process name
  local ppid_name
  ppid_name="$(ps -o comm= -p "${PPID}" 2>/dev/null || true)"
  case "${ppid_name##*/}" in
    claude*) echo "claude"; return ;;
    gemini*) echo "gemini"; return ;;
    codex*)  echo "codex";  return ;;
  esac

  # 3. Session env vars
  if [[ -n "${CLAUDECODE:-}" ]]; then
    echo "claude"
    return
  fi
  if [[ -n "${GEMINI_SESSION:-}" ]]; then
    echo "gemini"
    return
  fi
  if [[ -n "${CODEX_SESSION:-}" ]]; then
    echo "codex"
    return
  fi

  # 4. Fallback
  echo "claude"
}

# Cache the detected provider for the lifetime of this shell
_DEGA_PROVIDER_CACHE=""

# --- Public API ---

# Returns the detected agent provider name (claude, gemini, codex).
dega_agent_type() {
  if [[ -z "${_DEGA_PROVIDER_CACHE}" ]]; then
    _DEGA_PROVIDER_CACHE="$(_dega_detect_provider)"
  fi
  echo "${_DEGA_PROVIDER_CACHE}"
}

# Returns the CLI command to invoke the agent.
dega_agent_command() {
  local provider
  provider="$(dega_agent_type)"
  case "${provider}" in
    claude) echo "claude" ;;
    gemini) echo "gemini" ;;
    codex)  echo "codex" ;;
    *)      echo "${provider}" ;;
  esac
}

# Returns the agent-specific config directory path.
dega_agent_config_dir() {
  local provider
  provider="$(dega_agent_type)"
  case "${provider}" in
    claude) echo "${HOME}/.claude" ;;
    gemini) echo "${HOME}/.gemini" ;;
    codex)  echo "${HOME}/.codex" ;;
    *)      echo "${HOME}/.${provider}" ;;
  esac
}

# Returns flags for headless (non-interactive) invocation.
dega_agent_headless_flags() {
  local provider
  provider="$(dega_agent_type)"
  case "${provider}" in
    claude) echo "-p --dangerously-skip-permissions" ;;
    gemini) echo "--headless" ;;
    codex)  echo "--headless" ;;
    *)      echo "--headless" ;;
  esac
}

# Returns the session env var name that the agent sets when running.
dega_agent_session_var() {
  local provider
  provider="$(dega_agent_type)"
  case "${provider}" in
    claude) echo "CLAUDECODE" ;;
    gemini) echo "GEMINI_SESSION" ;;
    codex)  echo "CODEX_SESSION" ;;
    *)      echo "${provider^^}_SESSION" ;;
  esac
}

# Returns the flag used to pass a prompt string to the agent CLI.
dega_agent_prompt_flag() {
  local provider
  provider="$(dega_agent_type)"
  case "${provider}" in
    claude) echo "-p" ;;
    gemini) echo "--prompt" ;;
    codex)  echo "--prompt" ;;
    *)      echo "--prompt" ;;
  esac
}
