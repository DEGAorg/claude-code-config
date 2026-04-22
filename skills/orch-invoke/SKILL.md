---
name: orch-invoke
description: Launch an existing execution plan (GitHub issue) through the orchestrator from natural-language intent. Invoked when the user asks to run, execute, kick off, or start a plan or issue.
---

# orch-invoke

Resolve a user's natural-language intent to a concrete execution plan
(GitHub Issue + slug), validate it, and launch it through
`scripts/orch-run.sh` in background mode. Return structured handoff data
the agent can use to narrate progress or attach a TUI.

This skill is triggered by **conversational intent**, not by a slash
command. The agent decides when to invoke based on the cues below.
It works identically across Claude Code, Codex, and Gemini — the skill
is a plain shell contract with markdown documentation.

---

## When to invoke

Invoke this skill when the user expresses intent to **start, run, or
execute** an existing plan. Positive triggers include (non-exhaustive):

1. "run plan X" / "run the X plan"
2. "execute plan X" / "execute the X plan"
3. "kick off issue N" / "kick off plan N"
4. "start the orchestrator for X" / "start orch on X"
5. "launch plan X" / "launch the X work"
6. "go ahead and run X" / "let's run X now"
7. "orchestrate X" / "orch X"
8. "spin up workers for X" / "start workers on X"
9. "begin executing X" / "begin work on X"
10. "ship plan X" / "start shipping X"
11. "get started on issue N" / "pick up issue N"
12. "run issue N in the background" / "background-run N"

The user may refer to a plan by:
- **Issue number** ("#214", "issue 214", "214") — highest confidence.
- **Slug** ("20260422-orch-invoke-skill") — high confidence.
- **Topic keywords** ("the orch invoke skill", "the events plan") —
  resolver does fuzzy keyword matching and may return `ambiguous`.

---

## When NOT to invoke

Do **not** call this skill for:

1. **Plan authoring** — "create a plan for X", "draft a plan", "/plan X".
   Use the `/plan` skill or write the plan yourself.
2. **Plan discovery** — "what plans are open?", "list active plans",
   "show me the plan board". Use `gh issue list` directly.
3. **Plan inspection** — "what does plan X do?", "explain plan X",
   "summarize the approach". Read the issue body directly.
4. **Plan review** — "review plan X", "is this plan reasonable?".
   Use the `review-pr` or equivalent review skill.
5. **Plan editing** — "add a step to plan X", "update plan X".
   Edit the issue body directly.
6. **Orchestrator status** — "how is plan X going?", "is the orch
   running?", "what's the status?". Read `.orchestrator/state.json`
   and `.orchestrator/events.jsonl` directly — the plan is already
   running.
7. **Stopping work** — "kill the orch", "stop plan X". This skill
   only starts; use `tmux kill-session` or the orch stop command.
8. **Foreground runs** — if the user explicitly asks for a synchronous
   / foreground run, call `scripts/orch-run.sh` directly without this
   skill; the skill always launches in background.

---

## Behavior contract

The skill performs three phases. Each phase can fail safely and the
skill will return a structured error the agent must rephrase for the
user rather than retry blindly.

### Phase 1 — Resolve intent

`skills/orch-invoke/resolve.sh "<user_intent>"` reads the user's
natural-language intent and returns JSON:

```json
{
  "status": "exact" | "match" | "ambiguous" | "empty",
  "issue": 214,
  "slug": "20260422-orch-events",
  "candidates": [
    { "issue": 214, "slug": "20260422-orch-events", "title": "..." }
  ]
}
```

- `exact` — user gave an issue number or exact slug. `issue` and `slug`
  are populated. Proceed to Phase 2.
- `match` — keyword match above the single-best-match threshold.
  Proceed to Phase 2 but surface the resolved plan to the user
  ("Launching plan #214 — orch events…") so they can abort.
- `ambiguous` — two or more candidates tie. `candidates` is populated.
  **Stop and ask the user to disambiguate.** Do not guess.
- `empty` — no candidates. Tell the user no matching plan was found
  and suggest `/plan` to create one.

### Phase 2 — Validate

Before launching, `launch.sh` verifies:

- The plan file at `docs/exec-plans/active/<slug>/plan.md` or
  `.orchestrator/plans/<slug>/plan.md` exists.
- Every Progress log item past the first has a `(deps: N)` annotation
  (per `~/.claude/rules/exec-plans.md`). Missing annotations ⇒ refuse
  with `error: "missing_deps"`.
- `.orchestrator/master.json` does not already list an active run for
  this slug. Already-running ⇒ refuse with `error: "already_running"`
  and return the existing `{pid, events_path, state_path}`.
- The plan's GitHub issue is not labelled `plan:completed`. Completed ⇒
  refuse with `error: "already_completed"`.

If any check fails, the skill returns `{ "ok": false, "error": "...",
"detail": "..." }` and does **not** launch anything.

### Phase 3 — Launch

On success, the skill runs:

```
bash scripts/orch-run.sh <slug> --issue <N> --background
```

It then tails `.orchestrator/events.jsonl` for the `plan_start` event
(contract from Plan A, PR #214) with a short timeout to confirm the
run came up. If `plan_start` does not appear within the timeout, the
skill returns `error: "launch_timeout"` with the spawned `pid` so the
agent can tell the user to investigate.

---

## Structured output shape

On success:

```json
{
  "ok": true,
  "slug": "20260422-orch-invoke-skill",
  "issue": 213,
  "pid": 48213,
  "events_path": ".orchestrator/events.jsonl",
  "state_path": ".orchestrator/state.json"
}
```

On failure:

```json
{
  "ok": false,
  "error": "missing_deps" | "already_running" | "already_completed"
         | "ambiguous" | "empty" | "plan_not_found" | "launch_timeout"
         | "gh_auth" | "unknown",
  "detail": "<human-readable explanation>",
  "candidates": [ ... ]   // only for "ambiguous"
}
```

The agent should translate `error` codes into natural language for the
user — never surface the raw JSON.

---

## Agent usage pattern

Pseudocode the agent should follow, independent of host (Claude Code,
Codex, Gemini):

```
1. Detect NL trigger (see "When to invoke").
2. Run:  bash skills/orch-invoke/resolve.sh "<user intent>"
3. If status == "ambiguous": present candidates, ask user which one; stop.
4. If status == "empty":     tell user no plan matches; suggest /plan; stop.
5. Else:                     run bash skills/orch-invoke/launch.sh <issue>
6. On ok=true:               confirm launch to user, include slug + pid.
7. On ok=false:               rephrase error for user; do not retry silently.
```

The agent must never chain additional orchestrator commands off this
skill's output without user confirmation. The skill's job ends at a
successful background launch.

---

## Cross-agent notes

- No Claude-Code-specific tool invocations appear in this skill.
  Helpers are plain POSIX shell scripts.
- The agent host is expected to execute shell via its native bash tool
  (Claude Code: Bash; Codex: shell; Gemini: run_shell_command).
- Output is JSON on stdout; diagnostics on stderr. Both resolver and
  launcher exit non-zero on hard failure so hosts that gate on exit
  codes behave correctly.

---

## Safety and idempotency

- **Background-only launches.** The skill never blocks the agent; all
  work runs under a detached tmux session managed by `orch-run.sh`.
- **Idempotent.** Running the skill twice for the same slug returns
  `already_running` on the second call with the existing pid — no
  duplicate orchestrator is spawned.
- **Refusal over guessing.** Ambiguous intent stops and asks; missing
  deps refuse; unknown plans refuse. The skill does not create plans,
  edit plans, or fabricate slugs.
