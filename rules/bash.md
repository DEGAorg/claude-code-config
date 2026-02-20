---
glob: "*.sh"
---

# Bash Standards

All scripts must start with `set -euo pipefail`.

Lint and format before committing: `shellcheck script.sh && shfmt -d script.sh`

- `shellcheck` catches correctness issues (unquoted variables, missing error handling, portability)
- `shfmt` enforces consistent formatting (`-i 2` for 2-space indent, `-w` to write in place)

Prefer explicit error messages over silent failures. Use `|| { echo "error: ..."; exit 1; }` for commands that must succeed.
