---
name: canon-start
description: >-
  Start or resume a Canon prediction-market project through scaffold, strategy selection, build,
  and dry-run validation. Use for canon-start; live mode requires an explicit --live request.
---

# Canon Start in Codex

Read `references/workflow.md` beside this skill and follow its phases in the
current project. The installer bundles the shared `commands/canon-start.md`
there. If missing, stop and report an incomplete Core skill installation.

Apply these Codex host adaptations to that procedure:

- Treat `$canon-start`, `/canon-start`, and an explicit natural-language request
  to start Canon as this workflow. Preserve the user's arguments. Only enter
  the live phase when the user explicitly requests `--live`; never infer it
  from funding, credentials, or a previous live run.
- Use Codex's shell and file tools for Bash/Read/Write operations. Use a Bash
  shell for the procedure's Bash blocks. Use a question tool when available;
  otherwise ask in chat and wait for the strategy choice. `AskUserQuestion`
  is a Claude tool name, not a prerequisite.
- Read requested personas from `.canon/agents/<name>.md` and domain guidance
  from `.canon/skills/<name>.md`. These are files, not required named Codex
  tools or separately installed skills. Follow `/discover`'s inline procedure
  in phase 5. Implement phase 6's plan directly as that phase specifies.
- Before any mutations, reject the Core source repository (an `AGENTS.md`
  containing `claude-code-config`), including worktrees with different names.
- If phase detection reports `scaffold` but `.canon/agents` and `.canon/skills`
  are absent, use phase 3's initialization path. A bootstrap-only `.canon`
  directory is not a completed scaffold. That path also installs dependencies
  and ensures the local wallet before strategy selection.
- Do not overwrite an existing project with `--force` without checking the
  affected files and obtaining approval for any loss of user changes.
- For a bundled strategy, use `strategies/<name>/plan.md` when present. Do not
  assume the legacy `.canon/templates/<name>/plan.md` exists. If the bundled
  entry point passes the project checks, proceed to dry-run; otherwise plan
  the remaining work from its actual strategy spec.
- Invoke dry-run through `canon-runner.sh` without `--live`, using a persistent
  shell session if needed. Confirm the PID and logs before reporting success.
  Report an exited runner as exited, even if the launch command succeeded.

Use `$canon-start --live` in Codex-facing follow-up instructions. A missing
TUI panel does not prevent the workflow from running in Codex.
