# Bootstrap Install Pattern

How DEGA projects implement single-URL agent-readable installation.

## Architecture

```
INSTALL.md (entry point — one URL to give the agent)
  └── commands/apply-<component>.md (installer procedure)
        └── fetches files from raw GitHub URL
        └── installs to well-known directory
```

The user gives their AI agent a single URL. The agent fetches it, reads
the procedure, and executes every step autonomously. No cloning required.

## How it works

1. **INSTALL.md** — human + agent readable entry point. Contains:
   - One-liner for humans: "tell your agent to fetch this URL"
   - Step-by-step for agents: fetch the installer command, execute it
   - What gets installed (table of components + locations)
   - Post-install usage examples

2. **commands/apply-\<component\>.md** — the actual installer. Contains:
   - Description line (`@description ...`)
   - Source URL (raw GitHub, pinned to branch)
   - File manifest (every file that gets fetched)
   - Prerequisites check (required tools)
   - Install procedure (mkdir, fetch, copy/symlink)
   - Verification steps

## Pattern for new components

To add bootstrap install to a new repo (e.g. Canon TUI):

### 1. Create `INSTALL.md` at repo root

```markdown
# Install Canon TUI

## For AI agents — bootstrap instructions

You are installing Canon TUI, a terminal dashboard for monitoring
AI agent orchestration runs.

**To install, fetch and execute the installer:**

1. Fetch the installer:
   ```
   https://raw.githubusercontent.com/DEGAorg/<repo>/main/commands/apply-canon-tui.md
   ```
2. Read the fetched content — it contains the full installation procedure.
3. Execute every step in that document.

No cloning required. Everything is fetched from GitHub at install time.

---

## For humans — quick start

Tell your AI coding agent:

> Install Canon TUI from https://raw.githubusercontent.com/DEGAorg/<repo>/main/INSTALL.md

---

## What gets installed

| Component | Location | Purpose |
|-----------|----------|---------|
| ... | `~/.canon/` or wherever | ... |

## Usage

...
```

### 2. Create `commands/apply-canon-tui.md`

Follow the same structure as `apply-core.md`:

```markdown
# Apply Canon TUI

@description Install Canon TUI globally to ~/.canon/. ...

## Source

All files are fetched from:
https://raw.githubusercontent.com/DEGAorg/<repo>/<branch>/

Files available:
- file1
- file2
- ...

## Prerequisites

Check these exist before proceeding:
- `node` (>= 22)
- `pnpm`
- any other deps

## Procedure

1. Create install directory: `~/.canon/` (CANON_HOME)
2. Fetch each file from Source URL
3. Install dependencies: `pnpm install`
4. Create shell alias or symlink for `canon` command
5. Verify: `canon --version`

## Verification

Run `canon status` or equivalent to confirm installation.
```

### 3. Wire into DEGA Core (optional)

Once Canon TUI has its own INSTALL.md, the main DEGA Core INSTALL.md
can reference it as an optional component:

```markdown
## Optional: Canon TUI

To also install the Canon terminal dashboard:

> Fetch and execute https://raw.githubusercontent.com/DEGAorg/<repo>/main/INSTALL.md
```

This keeps each repo self-contained while allowing a single entry
point to chain installs.

## Key principles

- **Single URL** — one raw GitHub URL is the entire install instruction
- **No clone required** — everything fetched at install time
- **Agent-readable** — structured as steps an AI agent can follow literally
- **Human-readable** — includes quick start for humans who delegate to agents
- **Idempotent** — safe to re-run, updates in place
- **Self-installing** — the installer registers itself as a command for future updates
