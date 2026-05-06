# Orchestrator Agent Notifications

The orchestrator surfaces terminal plan events back to the agent without
requiring the user to ask. When a plan ships, fails verification, or
exhausts its review iterations, a notification file is written to disk.
The next time Claude Code finishes a turn, a `Stop` hook reads any unseen
notifications and injects them into the agent's context as a
`system-reminder`, so the agent can announce "plan X completed: PR Y" on
its own.

## Trigger events

The lifecycle hook `hooks/orch-lifecycle/02-agent-notify.sh` fires on
three events emitted by `orch-engine.sh`:

| Event    | When a notification is written                                   | Resulting `status`  |
|----------|------------------------------------------------------------------|---------------------|
| `ship`   | Plan was merged — PR url/number persisted in `state.finalReview` | `completed`         |
| `verify` | Only when `verification.status == "failed"`                      | `failed`            |
| `revise` | Only when the engine bailed (`state.status == "failed"`)         | `in_progress`       |

Mid-loop `revise` events and successful `verify` runs are silent — the
hook exits 0 without writing a file.

## File location

Notifications live at:

```
.orchestrator/notifications/<slug>.json
```

The entire `.orchestrator/` directory is gitignored, so notifications
never leak into commits. One file per plan slug; subsequent events
overwrite the file atomically (tmp + `mv`).

## Schema

```json
{
  "slug": "20260428-stop-hook-agent-bump",
  "status": "completed",
  "summary": "Plan <slug> shipped (6/6 items, 12m) — PR <url>",
  "createdAt": "2026-04-28T18:42:11Z",
  "seen": false,
  "issueNumber": 258,
  "prUrl": "https://github.com/DEGAorg/claude-code-config/pull/260",
  "prNumber": 260
}
```

`prUrl` and `prNumber` are present only on `ship`. `issueNumber` is
present whenever `state.json` carries it. The schema is shared with
Canon TUI per `docs/specs/canon-tui-plan-completion.md`.

## Stop hook behavior

`hooks/stop/01-orch-notify.sh` is registered in `settings.json` under
`hooks.Stop`. On each Stop event it:

1. Exits 0 silently if `${CLAUDE_PROJECT_DIR}/.orchestrator/notifications/`
   does not exist (so it is a no-op outside this repo).
2. Scans `*.json` for entries where `seen: false`.
3. Builds a single human-readable message — up to 6 detailed entries,
   any remainder summarized as a count plus the directory path.
4. Marks each reported entry `seen: true` via atomic rewrite, so the
   same notification is never injected twice.
5. Emits `{"decision": "block", "reason": "<message>"}` on stdout. Claude
   Code surfaces the `reason` as a system-reminder for the next turn.

## How to disable

Remove the `01-orch-notify.sh` entry from the `hooks.Stop` array in
`settings.json` (or `.claude/settings.local.json`). The lifecycle hook
will keep writing files for Canon TUI to consume, but the agent will
no longer be auto-notified at Stop time. To also stop writing files,
remove `02-agent-notify.sh` from the orch lifecycle hooks directory.
