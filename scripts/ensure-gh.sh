#!/usr/bin/env bash
set -euo pipefail

# Ensure the GitHub CLI (gh) is available, installing via brew if needed.
# Never calls sudo. Fails with platform-specific instructions if brew unavailable.

ensure_gh() {
	if command -v gh &>/dev/null; then
		return 0
	fi

	echo "gh CLI not found. Attempting to install via Homebrew..." >&2

	if ! command -v brew &>/dev/null; then
		echo "error: gh CLI is not installed and Homebrew is not available." >&2
		echo "" >&2
		echo "Install gh manually:" >&2
		case "$(uname -s)" in
		Darwin)
			echo "  Option 1: Install Homebrew first — https://brew.sh" >&2
			echo "  Option 2: Download gh from https://cli.github.com" >&2
			;;
		Linux)
			echo "  Option 1: Install Homebrew for Linux — https://brew.sh" >&2
			echo "  Option 2: See https://github.com/cli/cli/blob/trunk/docs/install_linux.md" >&2
			;;
		*)
			echo "  See https://cli.github.com for installation instructions." >&2
			;;
		esac
		return 1
	fi

	brew install gh >&2 || {
		echo "error: brew install gh failed." >&2
		return 1
	}

	if ! command -v gh &>/dev/null; then
		echo "error: gh was installed but is not in PATH." >&2
		return 1
	fi

	echo "gh installed successfully." >&2
}

# Run when executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	ensure_gh
fi
