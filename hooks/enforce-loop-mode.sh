#!/usr/bin/env bash
# PreToolUse/Bash hook. Two-level command enforcement.
# Level 1: hard stop — destructive commands, always blocked.
# Level 2: soft block — mode-restricted commands, blocked with recovery guidance.
# Mode read from RALPH_MODE env (set by ralph-loop.sh). Default: "full" (nothing blocked).

set -euo pipefail

CMD=$(jq -r '.tool_input.command // empty')
[[ -z "${CMD}" ]] && exit 0

# ── Level 1: always blocked regardless of mode ──────────────────────────────

if printf '%s\n' "${CMD}" | grep -qE 'rm[[:space:]]+-[^[:space:]]*r[^[:space:]]*f'; then
	echo "BLOCKED: rm -rf is not allowed. Use trash instead." >&2
	exit 2
fi

if printf '%s\n' "${CMD}" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard'; then
	echo "BLOCKED: git reset --hard is not allowed." >&2
	exit 2
fi

if printf '%s\n' "${CMD}" | grep -qE 'git[[:space:]]+push.*(--force|[[:space:]]-f([[:space:]]|$))'; then
	echo "BLOCKED: git push --force is not allowed." >&2
	exit 2
fi

# ── Evidence gate: task-complete.sh requires at least one file changed ────────

if printf '%s\n' "${CMD}" | grep -q 'task-complete\.sh'; then
	CHANGES=$(git diff HEAD --name-only 2>/dev/null | wc -l | tr -d ' ')
	if [[ "${CHANGES}" -eq 0 ]]; then
		echo "BLOCKED: no file changes detected — complete actual work before calling task-complete.sh" >&2
		exit 2
	fi
fi

# ── Level 2: blocked when RALPH_MODE=local-only ───────────────────────────────

RALPH_MODE="${RALPH_MODE:-full}"
[[ "${RALPH_MODE}" != "local-only" ]] && exit 0

if printf '%s\n' "${CMD}" | grep -qE 'git[[:space:]]+commit'; then
	echo "BLOCKED [local-only]: git commit is not allowed inside a ralph loop." >&2
	echo "The orchestrator commits after SHIP. Focus on the current task." >&2
	exit 2
fi

if printf '%s\n' "${CMD}" | grep -qE 'git[[:space:]]+push'; then
	echo "BLOCKED [local-only]: git push is not allowed inside a ralph loop." >&2
	echo "Changes stay local until the reviewer outputs SHIP; a human will push and open the PR." >&2
	exit 2
fi

exit 0
