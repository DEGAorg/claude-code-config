# Core Version

DEGA Core ships with a single source-of-truth version file. This document
explains where that version lives, how to read it, and how to tell whether
the locally installed copy is up to date with the remote.

## Where the version lives

| Location | Role |
|----------|------|
| `VERSION` (repo root) | Source of truth on `DEGAorg/claude-code-config`. One line, semver (e.g. `0.6.0`). |
| `~/.degacore/VERSION` | The version of Core that the running install is on. Written by `INSTALL.md` Phase 1 (`cp VERSION ~/.degacore/`). |

The `VERSION` file at the repo root is the canonical source. The copy in
`~/.degacore/` is a sentinel — it records which release the user installed.

The `0.6.0` floor reflects the surface shipped through 2026-04-30
(orch detached-by-default, reviewer Gate A, ARB-01, MINT-01, WALLET rename).

## How to read it

Local install:

```bash
cat ~/.degacore/VERSION
```

Remote (latest on `main`):

```bash
gh api -H 'Accept: application/vnd.github.raw' \
  repos/DEGAorg/claude-code-config/contents/VERSION
```

Both together (with a status verdict):

```bash
bash scripts/core-version.sh
# installed=0.6.0  latest=0.6.0  status=up-to-date
```

The helper reads `~/.degacore/VERSION` for installed and `gh api …` for
latest, then compares the two as semver. Override the install path with
`DEGACORE_VERSION_FILE`; override the remote with `DEGACORE_REMOTE_REPO`.
Missing files, missing `gh`, or network failures degrade to `status=unknown`
rather than aborting.

## When the AI is asked about the version

Questions like *"what core version am I on?"*, *"is there an update?"*,
*"am I behind?"* map to:

1. Run `bash scripts/core-version.sh`.
2. Read the `installed`, `latest`, and `status` tokens it prints.
3. Report the verdict in plain language.

If `status=behind`, suggest re-running `INSTALL.md` (the supported update
path; idempotent). If `status=ahead`, the user is on a development branch
that has not yet shipped to `main`. If `status=unknown`, fall back to
`cat ~/.degacore/VERSION` and explain why the remote read failed (no `gh`,
no network, etc.).

## How to update

Re-run `INSTALL.md` from `DEGAorg/claude-code-config@main`. The installer
is idempotent and brings every component to the latest `main` HEAD,
including the `VERSION` and `CORE_VERSION.md` copies in `~/.degacore/`.
Inside an AI session, `/core-update` (or natural language `update dega
core`) is the same path with a SHA short-circuit.
