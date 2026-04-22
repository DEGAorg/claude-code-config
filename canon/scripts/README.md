# Canon scripts — runtime contract

Scripts in this directory are the deterministic bits of the canon agent:
small shell helpers the agent shells out to for things that must not be
hallucinated (filesystem probes, phase detection, bootstrap checks).

This document is the contract every script here must follow. Tests and
reviewers enforce it; new scripts that deviate should be rewritten, not
grandfathered in.

## Runtime

- **Language:** POSIX-ish `bash`. Each script is a single `.sh` file.
- **Header:** every script starts with `#!/usr/bin/env bash` followed
  immediately by `set -euo pipefail`.
- **Linters:** scripts pass `shellcheck <script>` and
  `shfmt -d <script>` with no warnings. CI runs both.
- **Scope:** one small task per script. If a script grows a second
  responsibility, split it. Composition happens in the agent, not in
  shell.
- **Location-independent:** scripts may be executed from the repo
  (`canon/scripts/foo.sh`) or from an installed copy
  (`~/.degacore/canon/scripts/foo.sh`). Use
  `source "$(dirname "${BASH_SOURCE[0]}")/canon-error.sh"` to source
  sibling helpers so both paths resolve.

## Exit-code taxonomy

Scripts signal outcome with a small, agent-legible set of exit codes:

| Code | Meaning | Agent behavior |
|------|---------|----------------|
| `0`  | Success | Continue. |
| `1`  | Generic failure — unclassified error. | Surface to user; do not auto-retry. |
| `2`  | Precondition failure — something the agent can repair, then retry. | Repair the precondition (install a tool, create a dir, fetch a file) and re-run the script. |
| `3`  | User input needed — the script cannot proceed without a human decision or credential. | Stop and ask the user; do not retry until input arrives. |

Any other non-zero code is treated as generic failure (same as `1`).
Do not invent new codes — extend the taxonomy in this doc first if a
new class of outcome is genuinely needed.

## Stderr convention

On any non-zero exit, the script's **first stderr line** must be a
structured single-line prefix:

```
canon-error: <code>: <short>
```

- `<code>` is the numeric exit code (`1`, `2`, or `3`).
- `<short>` is a stable, human-readable slug describing the failure
  class (e.g. `missing-tool`, `not-a-repo`, `needs-login`). Keep it
  short and greppable — no punctuation beyond `-`.
- Free-text detail (paths, suggested fixes, command output) may follow
  on subsequent stderr lines. The agent parses the first line for
  routing and shows the rest to the user as context.

Success paths must not emit a `canon-error:` line.

## Shared helper

`canon-error.sh` is the one place this format is produced. Other
scripts `source` it and call its emitter on failure paths rather than
hand-rolling the prefix, so the format stays consistent.

```bash
source "$(dirname "${BASH_SOURCE[0]}")/canon-error.sh"

if ! command -v jq >/dev/null 2>&1; then
  canon_error 2 missing-tool "jq is required; install via 'brew install jq'"
fi
```

`canon_error <code> <short> [detail...]` writes the prefixed line (plus
any detail) to stderr and exits with `<code>`.

## Checklist for new scripts

Before merging a new script in `canon/scripts/`:

- [ ] `#!/usr/bin/env bash` and `set -euo pipefail` at the top.
- [ ] `shellcheck` and `shfmt -d` clean.
- [ ] Does one small task; no mixed concerns.
- [ ] All failure paths emit `canon-error: <code>: <short>` via
      `canon_error` from `canon-error.sh`.
- [ ] Exit codes match the taxonomy above.
- [ ] Sources siblings via `BASH_SOURCE` so it works installed or
      in-repo.
- [ ] Has a sibling test in `canon/scripts/__tests__/` covering at
      least one success and one failure path.
