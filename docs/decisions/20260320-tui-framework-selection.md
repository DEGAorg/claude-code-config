# Decision: TUI Framework Selection — Toad Fork vs Pure Textual

**Date:** 2026-03-20
**Status:** Decided — Fork Toad
**Context:** Conductor TUI + GitHub Project State views

---

## Background

Canon's Alternative B defers the VS Code fork to Phase II. Phase I needs a terminal-based
conductor — a TUI where the user chats with an AI agent (conductor), and the conductor
controls side panels showing project state, orchestrator dashboards, file views, etc.

Meeting notes (Mar 19) define the requirements:
1. Script/app launches the conductor
2. Main panel is always Claude (chat)
3. Conductor controls what shows in the side panel
4. Screen splits further per orchestrator
5. Mouse support

Toad (by Will McGugan, built on Textual) matches these requirements almost exactly.

---

## Options Evaluated

### Option A: Fork Toad (AGPL-3.0)

**What Toad gives us (already built):**
- Chat/conversation UI with markdown rendering, streaming responses (1,951 lines)
- ACP protocol support — Claude, Codex, Gemini, 12+ agents day 1
- Shell integration with full-color output
- SideBar with Panel system (add any widget as a panel in one line)
- Prompt editor with @-file fuzzy search
- Mouse support, keyboard navigation, scrolling
- Multi-session management (ctrl+s shows all agents)
- File/directory browsing (ProjectDirectoryTree)
- ~15K lines of polished Python code total

**What we add:**
- `GitHubStateWidget` — 4-tab panel (Timeline, Issues, Plans, PRs)
- Orchestrator dashboard panel
- Resource governance panel
- Plan management panel
- `dega-core.yaml` integration

**Toad source architecture (from inspection):**
- `app.py` (862 lines) — main Textual App subclass
- `screens/main.py` (290 lines) — MainScreen = SideBar + Conversation + Footer
- `widgets/conversation.py` (1,951 lines) — chat UI, ACP agent communication
- `widgets/side_bar.py` (89 lines) — collapsible panel container, takes any widget
- `widgets/` (8,549 lines total) — 20 widget files, all standard Textual
- `acp/` — Agent Client Protocol implementation
- `shell.py` (304 lines) — shell integration

Adding a panel is:
```python
SideBar.Panel("GitHub", GitHubStateWidget())
```

### Option B: Build from scratch on Textual (MIT)

**What Textual gives us (framework):**
- `DataTable`, `TabbedContent`, `DirectoryTree`, `MarkdownViewer` — rich widgets
- Mouse, scroll, keyboard — built-in
- CSS-like styling, hot reload
- MIT license — zero restrictions

**What we build:**
- Everything. Chat UI, ACP protocol, shell integration, prompt editor, session management,
  side panel system, all custom views, keybindings, themes.

---

## High-Level Effort Estimates (AIDD with Orchestrator)

All estimates assume AI-driven development with the orchestrator running parallel workers.

### Option A: Fork Toad

| Task | Estimate |
|------|----------|
| Fork, install, verify it runs | 1 hour |
| Understand panel architecture + add GitHub state panel (Plan 2) | 2-3 hours |
| Add orchestrator dashboard panel | 3-4 hours |
| Add plan management + resource governance panels | 3-4 hours |
| Customize branding, keybindings, conductor-specific behavior | 2-3 hours |
| **Total to usable conductor prototype** | **~1.5-2 days** |

### Option B: Pure Textual

| Task | Estimate |
|------|----------|
| Scaffold app, main screen layout (sidebar + chat + footer) | 2-3 hours |
| Chat/conversation widget with markdown rendering + streaming | 4-6 hours |
| ACP protocol implementation (JSON-RPC 2.0, agent lifecycle) | 4-6 hours |
| Shell integration | 3-4 hours |
| Prompt editor with file search | 3-4 hours |
| Session management (multi-agent) | 2-3 hours |
| GitHub state panel (Plan 2) | 2-3 hours |
| Orchestrator dashboard panel | 3-4 hours |
| Plan management + resource governance panels | 3-4 hours |
| **Total to usable conductor prototype** | **~3-4 days** |

### Key difference

The fork saves ~2 days. The chat UI + ACP + shell + prompt editor are ~15K lines that
already work. With AIDD these can be rebuilt in days, not weeks — but they're still days
of work that the fork eliminates.

---

## License Analysis

### AGPL-3.0 (Toad fork)

- All modifications to the forked code must be AGPL-3.0
- If the conductor is offered as a network service, source must be published
- AGPL is "viral" — tightly coupled code inherits the license

### Impact on Canon

| Component | License | Affected by AGPL? |
|-----------|---------|-------------------|
| Conductor TUI (the fork) | AGPL-3.0 | Yes — this is the fork |
| MCP Server | Apache 2.0 (separate repo) | No |
| Agent personas, skills, workflows | Apache 2.0 (separate repo) | No |
| Canon Arena | Proprietary (separate repo) | No |
| Orchestrator scripts (bash) | This repo's license | No — shell scripts, not linked |

The AGPL scope is limited to the TUI application itself. MCP tools, skills, agents,
and the Arena are in separate repos with their own licenses. The conductor TUI is
planned to be open source regardless.

**Risk:** If Canon later wants the conductor TUI to be proprietary or under a
more permissive license, the AGPL fork prevents that. Relicensing would require
replacing all Toad-derived code.

**Mitigation:** Canon's open source components are Apache 2.0. The conductor could
be AGPL as a standalone TUI while everything it consumes (MCP, skills, agents)
stays Apache 2.0. Monetization (cloud execution, marketplace) is in proprietary
components unaffected by AGPL.

### MIT (Pure Textual)

No restrictions. Full licensing flexibility forever.

---

## Comparison Matrix

| Factor | Fork Toad | Pure Textual |
|--------|-----------|-------------|
| **Time to Plan 2 (GitHub state)** | 2-3 hours | 2-3 hours |
| **Time to conductor prototype** | 1.5-2 days | 3-4 days |
| **Chat UI** | Done | Build |
| **ACP (agent-agnostic)** | Done (12 agents) | Build |
| **Shell integration** | Done | Build |
| **Mouse + scroll** | Done | Done (Textual) |
| **Custom panels** | Easy (SideBar.Panel) | Easy (your layout) |
| **License** | AGPL-3.0 | MIT |
| **Upstream dependency** | Must track or diverge | None |
| **Codebase familiarity** | ~15K lines to understand | Your code from day 1 |
| **Future flexibility** | Constrained by AGPL | Unconstrained |

---

## Decision

**Fork Toad.** The 2-day savings on chat UI + ACP + shell integration justifies the
AGPL license given that the conductor TUI is open source anyway. Canon's monetization
(cloud execution, marketplace, Arena) lives in proprietary repos unaffected by AGPL.

The fork gives us a working conductor prototype (chat + side panels + ACP) on day 1.
Custom panels (GitHub state, orchestrator dashboard, plans) are the only new work.

---

## Open Questions

1. Is AGPL acceptable for the conductor TUI given Canon's monetization model?
2. Will McGugan is actively developing Toad — is upstream tracking viable or would
   we diverge immediately?
3. Should we explore contributing panel extensibility to Toad upstream instead of forking?
