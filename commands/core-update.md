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

### 3. Report what changed

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
