# Installer skips agents/ and skills/

## Problem

The manual DEGA Core install (run after `commands/apply-core.md`) copies
`~/.degacore/config/commands/` and `~/.degacore/config/rules/` into `~/.claude/`,
but does **not** copy `~/.degacore/config/agents/` or
`~/.degacore/config/skills/`.

Result: `~/.claude/agents/conductor.md` does not exist after a fresh install.

## Impact

Not a crash. canon-tui's `_load_agent_context()` handles the missing file with
`try/except OSError`, so the TUI still launches. But the Conductor agent loses
its orchestration instructions, which degrades the prediction-markets flow.

This is **separate** from the canon-tui ACP handshake hang it was found
alongside (that hang is a canon-tui code bug in `jsonrpc.py`; this is an
installer coverage gap). Fixing one does not fix the other.

## Suggested fix

Add the missing copy steps to the manual install command in `INSTALL.md` /
`commands/apply-core.md`:

```bash
mkdir -p ~/.claude/agents ~/.claude/skills
cp -n ~/.degacore/config/agents/*.md ~/.claude/agents/
cp -rn ~/.degacore/config/skills/* ~/.claude/skills/
```

## Where to verify

After install, confirm:

```bash
test -f ~/.claude/agents/conductor.md && echo OK
```

## Credit

Identified by carlossampson60 (with Claude.ai / Claude Code) on WSL2, 2026-05-29,
while diagnosing the canon-tui ACP handshake hang.
