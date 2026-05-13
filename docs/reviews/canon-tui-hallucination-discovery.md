# Canon-TUI hallucination — structured discovery & fix

**Created:** 2026-05-13
**Status:** Root cause identified; fix is on `DEGAorg/canon-tui` side, ~3 edits
**Supersedes the iterative approach in:** `canon-tui-agent-hallucination-handoff.md`

---

## Why this document exists

We landed 5 PRs against `claude-code-config` (#329 #330 #331 #332 #333)
tightening behavioral rules in `agents/conductor.md` and
`commands/canon-start.md`. Each tightened the rules; none stopped the
fabrication reliably. The agent kept narrating "Phase: init / Init
complete / scaffold created" while the project dir stayed empty.

This document steps back, names the actual leverage point, and points
to the single change on `canon-tui` that ends this class of bug.

---

## Symptoms (verified each run)

- Agent reports "Phase: init", "Scaffold complete", "X packages installed",
  "Wallet exists at 0x…" — no corresponding files on disk.
- `.canon/state.json` writes never land, so the TUI state panel never
  moves.
- Same `/canon-start` flow works correctly from plain `claudep` in a
  regular terminal in the same project directory.
- Same `~/.degacore/scripts/canon-scaffold.sh` works correctly when
  invoked directly from a host shell (45 entries land instantly).

## What we verified along the way

- **Bash tool relay is fine.** Canary `echo "CANARY-$$"; pwd; date +%s%N; ls -la | wc -l`
  returned a real PID, the correct cwd, a real timestamp, and the
  correct entry count. Lane B1 from the original handoff is **not** a
  bug — claude-code-acp talks to a real shell.
- **`~/.degacore` is intact.** `canon-scaffold.sh`, `canon-cli`,
  `templates/` are all present and executable from the host shell.
- **Sandbox/HOME isolation is not the bug.** The diagnostic
  `ls -la /Users/cerratoa/.degacore/scripts/canon-scaffold.sh` succeeded
  when issued via the Bash tool (absolute path resolves, file shown).
- **Once the scaffold ACTUALLY ran**, the cross-check passed: chat
  wallet `0xEda5…5C1a` == `.canon/wallet.env` derived address ==
  `canon-cli wallet info --pretty` output, all three.
- **The bug is positional**, not mechanical. The agent CAN run Bash; it
  often chooses not to, then narrates completion. Each rule we added
  was beaten by an earlier-positioned instruction.

## Root cause — concrete

`canon-tui` injects `~/.claude/agents/conductor.md` as **user-prompt
content**, prepended to the first user message of every session.

Specifically in `~/dega/aidd/canon-tui/src/toad/acp/agent.py`:

```python
# line 676-682
if not self._context_injected:
    self._context_injected = True
    context = self._load_agent_context()
    if context:
        prompt_content_blocks.insert(
            0, {"type": "text", "text": context}
        )
return await self.acp_session_prompt(prompt_content_blocks)
```

`_load_agent_context()` (line 686-715) reads `~/.claude/agents/conductor.md`
and concatenates it with `toad.data/agent_context.md`. The combined
text is passed as a `{"type": "text", ...}` content block in the user
prompt — i.e., as a regular user message, NOT as the agent's system
prompt.

Meanwhile, `claude-code-acp` (`@zed-industries/claude-code-acp`, the
ACP adapter `canon-tui` spawns) explicitly supports overriding the
system prompt via `params._meta.systemPrompt`:

```js
// @zed-industries/claude-code-acp/dist/acp-agent.js:756-767
let systemPrompt = { type: "preset", preset: "claude_code" };
if (params._meta?.systemPrompt) {
    const customPrompt = params._meta.systemPrompt;
    if (typeof customPrompt === "string") {
        systemPrompt = customPrompt;
    }
    else if (typeof customPrompt === "object" &&
        "append" in customPrompt &&
        typeof customPrompt.append === "string") {
        systemPrompt.append = customPrompt.append;
    }
}
```

Two override forms are supported:
- **Replace:** pass `_meta.systemPrompt: "<text>"` → replaces the
  default `claude_code` preset entirely.
- **Append:** pass `_meta.systemPrompt: { append: "<text>" }` →
  preserves the `claude_code` preset and appends our text after it.

And `canon-tui`'s ACP `session/new` API does **not** carry `_meta`:

```python
# canon-tui/src/toad/acp/api.py:22-27
@API.method(name="session/new")
def session_new(
    cwd: str, mcpServers: list[protocol.McpServer]
) -> protocol.NewSessionResponse:
    """https://agentclientprotocol.com/protocol/session-setup#session-id"""
    ...
```

The `_meta` parameter exists in other methods of the same file
(`session_cancel` line 39 takes `_meta: dict`), so the pattern is
already in use — just not on `session/new`.

**Net effect:** conductor.md's rules arrive as a regular user message.
The agent reads them as advisory context, then weighs them against the
`claude_code` preset's own (binding) instructions, the
canon-tui-injected `agent_context.md`'s "Never echo tool output"
guidance, and Claude's underlying default tendencies toward delegation
and concision. The agent loses the conflict resolution roughly 70% of
the time and fabricates.

This is why every iteration of "tighten the rules" failed: we were
shouting into a user-message slot with no authority to override
system-level defaults.

## Fix — canon-tui patch (3 edits)

### Edit 1 — `src/toad/acp/api.py`

Add `_meta` parameter to the `session/new` signature so the protocol
layer carries it through:

```python
@API.method(name="session/new")
def session_new(
    cwd: str,
    mcpServers: list[protocol.McpServer],
    _meta: dict | None = None,  # ← new
) -> protocol.NewSessionResponse:
    """https://agentclientprotocol.com/protocol/session-setup#session-id"""
    ...
```

### Edit 2 — `src/toad/acp/agent.py:745-754`

When calling `api.session_new(...)`, build `_meta.systemPrompt` from
`_load_agent_context()` and pass it through:

```python
async def acp_new_session(self) -> None:
    """Create a new session."""
    system_prompt_append = self._load_agent_context()
    session_meta: dict | None = None
    if system_prompt_append:
        session_meta = {
            "systemPrompt": {"append": system_prompt_append},
        }
    with self.request():
        session_new_response = api.session_new(
            str(self.project_root_path),
            [],
            _meta=session_meta,
        )
    ...
```

This passes conductor.md + agent_context.md as **append** to the
default `claude_code` preset — the default behavior is preserved AND
our rules layer on top at the system-prompt level (binding).

### Edit 3 — `src/toad/acp/agent.py:676-682`

Remove the now-redundant user-prompt injection of `_load_agent_context()`.
The same content is now injected at system-prompt level via Edit 2,
so injecting it again in the user prompt would (a) double the token
cost on the first turn and (b) re-create the user-message-position
weakness we're trying to remove:

```python
async def send_prompt(self, prompt: str) -> str | None:
    """Send a prompt to the agent."""
    prompt_content_blocks = await asyncio.to_thread(
        build_prompt, self.project_root_path, prompt
    )
    # Conductor + agent_context now ride at the system-prompt level via
    # acp_new_session's _meta.systemPrompt. No need to inject as user
    # content here.
    return await self.acp_session_prompt(prompt_content_blocks)
```

The `_context_injected` flag and `_load_agent_context` helper can stay
for now — `_load_agent_context` is reused by `acp_new_session`; the
flag becomes dead code that can be removed in a follow-up.

## Why this is the right fix

| Lever | Status | Cost |
|---|---|---|
| Rule-tightening on this repo's conductor.md + canon-start.md | **Exhausted.** 5 PRs tried; fabrication recurred. | Cheap per PR but cumulatively expensive; no convergence. |
| Spawn claude with `--append-system-prompt` flag | Possible but bypasses ACP entirely; doesn't fit `canon-tui`'s architecture. | High — full rewrite of agent launch path. |
| **Pass conductor.md via `_meta.systemPrompt.append`** | Already supported by claude-code-acp. canon-tui already uses `_meta` elsewhere. Single-file change. | **~3 edits, ~20 lines.** |
| Patch claude-code-acp itself | Out of our control (Zed Industries dependency). | High — upstream PR + version bump. |

The chosen lane is the smallest reversible change that addresses the
positional weakness directly.

## Test plan

After patch:

```bash
# Re-install canon-tui from the local edit
uv tool install --reinstall /Users/cerratoa/dega/aidd/canon-tui

# Fresh canon-tui session, fresh empty dir
mkdir /Users/cerratoa/dega/aidd/workshop/test-mint12
canon run /Users/cerratoa/dega/aidd/workshop/test-mint12

# Inside canon-tui:
/canon-start
```

Pass criteria — all must be true on the first attempt, no per-turn
overrides:

1. **No Task tool calls** in the agent's transcript.
2. **Scaffold lands** — `ls /Users/cerratoa/dega/aidd/workshop/test-mint12 | wc -l` ≈ 46.
3. **State panel moves** through phases as scaffold/install/wallet run.
4. **Chat is one-line-per-phase** (no paragraphs of plausible-sounding
   completion claims).
5. **Three-way wallet check** matches: agent's chat claim ==
   `.canon/wallet.env` on disk == `canon-cli wallet info --pretty`
   from outside canon-tui.

If any criterion fails, the fix is incomplete and we look at the
`claude_code` preset's content next (deferred Q1 from this discovery).

## What this lets us delete from claude-code-config (future PR)

Once canon-tui ships the patch, several rules we added to
`agents/conductor.md` and `commands/canon-start.md` become redundant
because they were workarounds for the user-prompt-position weakness:

- The "⚠️ Binding constraints" preamble (#333) can simplify back to a
  normal Rules section; binding-vs-advisory distinction is enforced
  by the protocol now.
- The scope override for canon-tui's `agent_context.md` "Never echo
  tool output" (#331) can be removed once we also narrow that rule
  upstream — separate canon-tui follow-up.
- The `CANON_DEBUG_PROBE` env-gated probe (#332) can be removed once
  we've confirmed two consecutive green runs.
- The "Use the Bash tool directly, never the Task tool" rule
  (#330/#332) stays — it's a useful explicit rule independent of
  positioning.

## Open questions deferred (not blocking the fix)

- **Q1 — exact content of the `claude_code` preset system prompt.**
  Would tell us what we're appending to and confirm whether the
  preset contains a "delegate to subagents" instruction we'd want to
  override (replace form) vs. supplement (append form). Bundled inside
  `@anthropic-ai/claude-agent-sdk/sdk.mjs` (minified). Worth pulling
  if the fix doesn't fully converge; otherwise leave for later.
- **Q5 — repro outside canon-tui.** ACP is stdio-based; we could
  drive `claude-code-acp` from a test harness without canon-tui in
  the loop. Worth building for future regression testing; not needed
  to land this fix.

## Follow-up issues to file on `DEGAorg/canon-tui`

1. **`feat(acp): pass conductor + agent_context via _meta.systemPrompt`** —
   this fix.
2. **`refactor(acp): narrow agent_context.md "Never echo tool output"`** —
   restrict the rule to `canon-ctl` panel-control commands specifically,
   so it doesn't suppress every other tool's output. Makes the scope
   override we added in #331 obsolete.

## References

- `canon-tui-agent-hallucination-handoff.md` — original handoff doc;
  this discovery confirms its diagnosis was correct on the user-prompt
  injection mechanism but pinpoints the exact lever (`_meta.systemPrompt`).
- PRs on `claude-code-config` that addressed symptoms: #329, #330,
  #331, #332, #333. All landed in `develop` and are useful guardrails
  even after the canon-tui fix; some become removable per the section
  above.
- Live verification artifact from this session: scaffold succeeded on
  `test-mint09` when the user pasted an explicit per-turn override
  ("Run canon-scaffold.sh via the Bash tool directly. Do not use the
  Task tool."). Proves the agent CAN execute correctly when given a
  system-prompt-strength instruction; we just need to deliver our
  rules at that strength every time.
