# Core Update

@description Update DEGA Core to the latest `main` by re-running the canonical installer (`INSTALL.md`). Install is idempotent, so re-running it brings the project and `~/.degacore/` to the latest version.

## Natural-language triggers

Invoke this skill when the user says any of:

- "update dega core"
- "update core"
- "upgrade dega core"
- "upgrade core"
- "bring dega core up to date"
- `/core-update`

These phrases all map to this same procedure. Do not ask the user to
clarify between them.

---

## How update works

DEGA Core's installer (`INSTALL.md` -> `commands/apply-core.md`) is
idempotent: every step checks for existing state and either skips,
merges, or overwrites safely. That means **re-running the installer
against an already-installed machine is the supported update path**.

There is no separate update procedure. This skill is a thin wrapper
that re-executes the install flow pointed at the current `main` of
`DEGAorg/claude-code-config`.

---

## Steps

### 0. Short-circuit if already up to date

Before fetching or running anything, compare the locally-recorded
install SHA against the remote `main` HEAD of
`DEGAorg/claude-code-config`. If they match, report "already up to
date" and exit — no work, no noise.

**Local SHA file:** `~/.degacore/state/core-sha`

This file is written by this skill after every successful update (see
step 3 below). It contains a single line — the 40-char commit SHA that
was installed. The installer (`apply-core.md`) does not currently
write it, so on a first-ever `/core-update` run against a machine that
has Core already installed, the file will not exist. Treat that as
"unknown local SHA" and proceed with the update unconditionally — the
post-update step will create the file so subsequent runs can
short-circuit.

**Resolve remote SHA:**

```bash
gh api repos/DEGAorg/claude-code-config/commits/main --jq .sha
```

If `gh` is not available or the call fails (offline, rate-limited,
auth missing), do not short-circuit — proceed with the update and let
the installer's own error handling surface any real problem. A
missing remote SHA is not a reason to block an update the user
explicitly asked for.

**Resolve local SHA:**

```bash
cat ~/.degacore/state/core-sha 2>/dev/null || true
```

**Compare:**

- If both SHAs are non-empty and equal → print
  `DEGA Core is already up to date (SHA: <sha>).` and stop. Do not
  proceed to step 1.
- Otherwise → continue to step 1.

### 1. Fetch the canonical installer

Fetch the latest `INSTALL.md` from `main`:

```
https://raw.githubusercontent.com/DEGAorg/claude-code-config/main/INSTALL.md
```

Read the fetched content. It is the single source of truth for how
Core is installed and updated.

### 2. Execute every step in `INSTALL.md`

Follow each phase and step in the fetched `INSTALL.md` exactly as
written. Do not skip phases. Specifically this means:

- **Phase 1 — Core**: fetch `commands/apply-core.md` from `main` and
  execute every step in that document. The installer will:
  - Check prerequisites (`tmux`, `jq`, `node`, `pnpm`).
  - Inventory what already exists under `~/.degacore/`.
  - Ask the user which components to install/update (pre-labeled as
    recommended where state is missing).
  - Fetch the selected files from `main`.
  - Write them to `~/.degacore/` using each component's documented
    merge/overwrite policy (some overwrite silently, some prompt,
    some merge).
  - Detect installed agents (Claude, Gemini, Codex) and regenerate
    per-agent config.
  - Self-install `/apply-core` and `/core-update` so future updates
    work from any directory.
- **Phase 2 — Canon TUI**: fetch
  `commands/apply-canon-tui.md` from the `canon-tui` repo `main` and
  execute every step. This re-runs `uv tool install --force
  --reinstall` which is inherently an update operation.

Because the installer is idempotent, re-running it is the update.
Files owned by the installer are refreshed; user-customized files
(settings, agent templates, `dega-core.yaml`) are either merged or
prompted on — never silently overwritten.

### 3. Record the new install SHA

After the installer completes successfully, resolve the remote `main`
HEAD SHA again and write it to `~/.degacore/state/core-sha`:

```bash
mkdir -p ~/.degacore/state
gh api repos/DEGAorg/claude-code-config/commits/main --jq .sha \
  > ~/.degacore/state/core-sha
```

This is what enables the step 0 short-circuit on the next run. If
`gh` is unavailable, skip writing the file — the next run will simply
re-update unconditionally, which is safe because install is
idempotent.

Resolve the SHA *after* the installer runs (not before), so the
recorded SHA reflects what was actually pulled. If `main` advances
mid-update, the recorded SHA matches the newer tip, which is fine —
the worst case is one extra no-op run next time, not a stale record.

### 4. Report what changed

After the installer finishes, summarize what was updated. Use the
post-install checklist that `apply-core.md` already emits. If the
user asks for a file-level diff, note that the detailed
installer-owned-files diff is produced by the full `/core-update`
flow in later iterations of this skill (tracked separately).

---

## Guardrails

- **Do not duplicate installer logic here.** If a step is missing,
  fix it in `INSTALL.md` / `commands/apply-core.md`, not in this
  skill.
- **Do not write your own fetch list.** The installer enumerates the
  files it owns. This skill is a dispatcher, not an installer.
- **Do not skip Phase 2.** "Update core" colloquially means "update
  the whole DEGA stack on this machine." Canon TUI is part of that
  stack.
- **Run from any directory.** This skill does not require the user
  to `cd` into a cloned repo. Everything is fetched from GitHub.

---

## Relationship to `/apply-core`

`/apply-core` installs Core. `/core-update` updates Core. They point
at the same underlying procedure (`INSTALL.md`), so the distinction
is semantic: users who type "update" get routed here; users who type
"install" get routed to `/apply-core`. Both end up re-running the
installer.
