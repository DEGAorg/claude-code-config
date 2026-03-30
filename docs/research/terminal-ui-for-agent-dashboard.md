# Terminal UI Research: Multi-Panel Agent Dashboard

**Date:** 2026-03-02
**Context:** Demo prep for Mar 3 — Canon strategy automation with visual terminal UI.
**Source:** `docs/demo-prep-mar3.md` (visual requirements, interactive demo flow, gap analysis)

---

## Use Case

An AI agent (Claude Code) runs Canon strategy automation and presents a split-screen
terminal experience to the user:

- **Left panel:** conversation with the agent (chat)
- **Right panel:** automation output (logs, status, data)
- **Status bar:** running/paused state, current phase, elapsed time
- **Interactive control:** user asks "what are you doing?", pauses, resumes
- **Agent-controlled:** the agent itself manages what appears in each panel

Must work on macOS. Should be scriptable from shell or Node.js. Must wrap existing
CLI tools (`claude -p`, Ralph Loop, strategy runners).

---

## What Exists Today

| Component | Status | Notes |
|-----------|--------|-------|
| Ralph Loop (`scripts/ralph-loop.sh`) | Working | Worker→check→reviewer iteration engine |
| Canon agents (6 specialists) | Working | market-analyst, strategy-architect, dev, qa, risk-analyst, deployment-ops |
| Exec-plan state files | Working | `plan.md`, `work-summary.txt`, `review-result.txt`, etc. |
| Statusline (`scripts/statusline.sh`) | Working | Two-line zsh status bar (model, branch, context, cost) |
| Sound notifications (`hooks/play-sound.sh`) | Working | Audio cues on task completion |
| Structured logging (`hooks/structured-log.sh`) | Working | JSON tool-call logging |
| Multi-panel TUI | **Missing** | No split-screen layout |
| Agent-driven workflow entry | **Missing** | No "start automation" command |
| Blackboard state sharing | **Missing** | No process↔agent communication file |
| Interactive control | **Missing** | No pause/resume/report from running automation |

---

## Options Evaluated

### Category 1: Terminal Multiplexers (wrap existing CLIs)

#### 1. tmux

The standard Unix terminal multiplexer. Claude Code has **native integration** —
`teammateMode: "tmux"` spawns agent teammates into separate tmux panes automatically.

| Criteria | Rating |
|----------|--------|
| Programmatic control | Excellent — `tmux split-window`, `send-keys`, `select-pane`, control mode (`-CC`) |
| Multi-panel | Full support — arbitrary splits, named sessions/windows/panes |
| Status bar | Built-in, configurable left/right sections, updated from scripts |
| Interactive control | Any process can send commands to any pane via `tmux send-keys` |
| Wrapping CLIs | Core strength — `claude -p` runs in a pane natively |
| Setup complexity | Single bash script, 20-30 lines |

**Pros:**
- Claude Code native tmux support (agent teams, split panes)
- Battle-tested for decades, ubiquitous
- Trivial to script from bash, Python, or Node.js
- Session persistence survives disconnects and crashes
- Large ecosystem: [claude-tmux](https://github.com/nielsgroen/claude-tmux),
  [tmux-mcp](https://github.com/nickgnd/tmux-mcp)
- Zero dependency on any particular language runtime

**Cons:**
- Status bar is basic text — no rich widgets, no progress bars
- Layout changes require tmux commands (not declarative)
- Styling is limited compared to purpose-built TUI frameworks

**Verdict:** Best path for the demo. Gets a working two-panel layout in an afternoon.

---

#### 2. Zellij

Modern terminal multiplexer written in Rust. WebAssembly plugin system. Floating panes,
KDL layout files.

| Criteria | Rating |
|----------|--------|
| Programmatic control | Mixed — `zellij action` CLI, less comprehensive than tmux |
| Multi-panel | Excellent — floating panes, stacked panes, named KDL layouts |
| Status bar | Plugin-based — writing a WASM plugin is heavier than tmux status |
| Interactive control | Less mature than tmux API |
| Wrapping CLIs | Works like tmux |
| Setup complexity | `brew install zellij`, KDL layouts more readable than tmux scripts |

**Pros:**
- Modern UX, floating panes, better defaults than tmux
- KDL layout files are readable
- WASM plugin system for rich extensions
- Active development, growing community

**Cons:**
- Claude Code does NOT have native Zellij integration
- CLI scripting API less mature than tmux
- Status bar customization requires WASM plugin
- Smaller ecosystem for AI-tool integrations

**Verdict:** Not recommended for the demo. Interesting for later if Zellij's
scripting API matures and Claude Code adds native support.

---

#### 3. dvtm

Tiling window manager for the console, inspired by dwm. ~4000 lines of C.

| Criteria | Rating |
|----------|--------|
| Programmatic control | Limited — named pipes (FIFOs) only |
| Multi-panel | 4 layouts: vertical stack, bottom stack, grid, fullscreen |
| Status bar | Reads from named pipe |
| Interactive control | Primitive compared to tmux |
| Wrapping CLIs | Less ergonomic, no `send-keys` equivalent |
| Setup complexity | Requires compilation from source, no macOS package |

**Verdict:** Not recommended. tmux does everything dvtm does with better scripting
and ecosystem. No active development.

---

#### 4. WezTerm

GPU-accelerated terminal emulator with built-in multiplexing and full Lua scripting.
Replaces your terminal app entirely.

| Criteria | Rating |
|----------|--------|
| Programmatic control | Excellent — full Lua API with hot-reloading |
| Multi-panel | Full multiplexing: tabs, splits, workspaces |
| Status bar | Fully customizable via Lua, dynamic content |
| Interactive control | `wezterm cli` for external control, user variables for pane↔config signals |
| Wrapping CLIs | Full support, `wezterm cli send-text` |
| Setup complexity | `brew install --cask wezterm`, single Lua config file |

**Pros:**
- Most powerful scripting API of any terminal (Lua, hot-reloadable)
- Bidirectional pane↔config communication via user variables
- GPU-accelerated rendering
- [Claude Code Bridge](https://www.verdent.ai/guides/claude-code-bridge-terminal-ai-agents)
  validates this approach

**Cons:**
- Replaces your terminal emulator — bigger commitment
- Lua scripting learning curve
- No session persistence across restarts (unlike tmux detach/attach)

**Verdict:** Strong option for a polished production version. Too heavy for a demo
that needs to work tomorrow.

---

### Category 2: TUI Frameworks (build a custom app)

#### 5. blessed / blessed-contrib (Node.js)

Terminal interface library for Node.js. `blessed-contrib` adds dashboard widgets
(line charts, maps, donuts, logs, tables).

| Criteria | Rating |
|----------|--------|
| Programmatic control | Full — build entire UI in JavaScript |
| Multi-panel | Excellent — grid layout, percentage-based sizing |
| Status bar | Build from `blessed.box` elements |
| Interactive control | Expose IPC (Unix sockets, HTTP) for external control |
| Wrapping CLIs | Possible via `blessed.terminal` widget |
| Setup complexity | `npm install blessed blessed-contrib`, ~50-100 lines |

**Verdict:** Not recommended. Unmaintained for 4+ years. Known bugs unfixed.
Use Ink instead for anything new in Node.js.

---

#### 6. Ink (React for terminal, Node.js)

React components that render to the terminal. Uses Yoga (flexbox) for layout.

| Criteria | Rating |
|----------|--------|
| Programmatic control | Excellent — React state/props drive UI |
| Multi-panel | Flexbox via `<Box>` — `flexDirection: "row"` for side-by-side |
| Status bar | Build from `<Box>` + `<Text>`, `@inkjs/ui` for spinners/progress |
| Interactive control | React state driven from any async source |
| Wrapping CLIs | Pipe `child_process.spawn` output — no raw PTY widget |
| Setup complexity | `npx create-ink-app`, ~40 lines TSX for two-panel |

**Pros:**
- Actively maintained, large ecosystem
- Full TypeScript support
- React mental model, flexbox layout
- Used by Gatsby, Parcel, Yarn 2

**Cons:**
- No terminal emulator widget — wrapping interactive CLIs is harder than tmux
- Adds React as a dependency
- Not designed for long-running log streaming (no built-in scrollback)

**Verdict:** Good for a polished status/control panel. Pairs well with tmux
(Ink for dashboard, tmux for agent panes). Post-demo candidate.

---

#### 7. Bubble Tea (Go)

TUI framework based on the Elm architecture. Part of the Charm ecosystem
(Lip Gloss, Bubbles, Gum).

| Criteria | Rating |
|----------|--------|
| Programmatic control | Full — Elm architecture (Model-Update-View) |
| Multi-panel | Lip Gloss composition: `JoinHorizontal()` / `JoinVertical()` |
| Status bar | Build from styled strings |
| Interactive control | `tea.Cmd` for async, custom IPC for external control |
| Wrapping CLIs | Read stdout/stderr into viewport, no raw PTY |
| Setup complexity | Go toolchain required, ~100-150 lines |

**Pros:**
- Beautiful Charm ecosystem
- [OpenCode](https://github.com/opencode-ai/opencode) (AI coding TUI) built with it
- Single binary, no runtime dependencies

**Cons:**
- Requires Go toolchain — doesn't fit shell/TS workflow
- More boilerplate
- No direct PTY wrapping

**Verdict:** Best if building a distributable binary. OpenCode proves the pattern.
Too heavy for a demo, interesting for a long-term product.

---

#### 8. Charmbracelet/Gum (shell)

TUI components for shell scripts: input, confirm, choose, spin, filter, table, log.

| Criteria | Rating |
|----------|--------|
| Programmatic control | Each invocation is standalone |
| Multi-panel | None — individual prompts, not persistent layouts |
| Status bar | `gum spin` for spinners, `gum log` for styled output |
| Interactive control | Each command is its own process |
| Wrapping CLIs | No |
| Setup complexity | `brew install gum`, zero code |

**Verdict:** Not a dashboard framework. Use it for setup menus and interactive
prompts that launch a tmux session.

---

#### 9. Textual (Python)

Modern TUI framework built on Rich. Async-powered, CSS-styled, rich widget library.

| Criteria | Rating |
|----------|--------|
| Programmatic control | Excellent — reactive attributes, message passing |
| Multi-panel | CSS-like grid and dock layouts, responsive |
| Status bar | Built-in `Header` and `Footer` widgets |
| Interactive control | Actions from keystrokes or programmatic calls |
| Wrapping CLIs | `RichLog` for streaming text, no raw PTY |
| Setup complexity | `uv add textual`, ~60-80 lines Python |

**Pros:**
- Most polished widget library of any TUI framework
- CSS-based styling
- Async-native — perfect for streaming agent output
- `textual-dev` hot-reload server
- Active development by Textualize

**Cons:**
- Python runtime required
- No terminal emulator widget for wrapping interactive CLIs
- Heavier than tmux for a simple split-screen

**Verdict:** Excellent for a productionized monitoring dashboard where you control
the data format. Post-demo candidate.

---

#### 10. Rich / Rich Live (Python)

Rich text, tables, progress bars, syntax highlighting, live-updating displays.
The foundation Textual is built on.

| Criteria | Rating |
|----------|--------|
| Programmatic control | Full — `Live` context manager for real-time updates |
| Multi-panel | `rich.layout.Layout` splits into named regions |
| Status bar | Build from `Layout` + `Panel` widgets |
| Interactive control | Limited — primarily an output library |
| Wrapping CLIs | Capture subprocess output into `Panel`, no PTY |
| Setup complexity | `uv add rich`, ~30-40 lines Python |

**Pros:**
- Fastest setup for a good-looking dashboard (fewest lines of code)
- Beautiful defaults — panels, tables, syntax highlighting, progress bars
- `Layout` + `Live` is the right abstraction for a status dashboard

**Cons:**
- Output-only — no built-in input handling
- Cannot wrap interactive CLIs
- For pause/resume, need threading + raw terminal input

**Verdict:** Best for a read-only status panel inside a tmux pane. Pairs with
tmux for the full experience. Good demo-day option.

---

## Existing Projects Worth Studying

| Project | What It Does | What to Take |
|---------|-------------|--------------|
| [NTM](https://github.com/Dicklesworthstone/ntm) | tmux orchestrator with TUI command palette | Multi-agent spawning, context monitoring patterns |
| [TmuxCC](https://github.com/nyanko3141592/tmuxcc) | tmux dashboard for AI agents | Agent discovery in panes, status monitoring, approval flow |
| [claude-tmux](https://github.com/nielsgroen/claude-tmux) | tmux popup with session mgmt | Git worktree integration, PR support |
| [Claude Code Bridge](https://www.verdent.ai/guides/claude-code-bridge-terminal-ai-agents) | WezTerm split grid for multi-agent | Multi-agent side-by-side layout patterns |
| [OpenCode](https://github.com/opencode-ai/opencode) | AI coding TUI (Bubble Tea) | Full TUI design for AI coding workflows |
| [Conduit](https://getconduit.sh/) | Multi-agent TUI | Tabbed sessions, token tracking, git integration |

---

## Recommendation

### For the demo (Mar 3): tmux + bash script

| Demo Requirement | tmux Solution |
|---|---|
| Two-panel layout | `tmux split-window -h` |
| Status indicator | `tmux set status-right "Phase: Running"` |
| Log panel | Right pane runs automation |
| Interactive control | User types in left pane (chat) |
| Pause/resume | State file (`.canon/state.json`) read by automation |

**Implementation:** a shell script (`canon/scripts/demo-session.sh`, ~30 lines)
that creates a named tmux session with two panes and a status bar.

**Optional upgrade:** add a Rich Live script in a third pane (top-right) for a
polished status display (phase indicator, progress bar, metrics). Reads state from
`.canon/state.json`. Adds 2 hours, delivers much better visual impact.

### For production: tmux + TUI framework

tmux as the multiplexer (CLI wrapping, session persistence, agent pane management)
combined with a purpose-built TUI app for the monitoring/control panel:

- **Textual** (Python) if the dashboard is a monitoring tool
- **Ink** (React/TS) if it needs to integrate with the Canon TypeScript codebase

This is the pattern NTM, TmuxCC, and Ralph TUI all converge on — tmux as
infrastructure, a TUI framework for the chrome.

### For long-term: agent-driven workflow (the real gap)

The visual layer is presentation. The higher-value investment is the **workflow
orchestration** — a `/canon-start` command where the user says "start automation"
and the agent takes over: opens panels, starts running, reports status, responds
to questions. The user doesn't need to know the internals.

This requires:
1. A "start" entry point that kicks off the full pipeline
2. Phase-aware agent that knows where it is in the workflow
3. Proactive next-step suggestions (not waiting for commands)
4. Blackboard state file for process↔agent communication
5. Background autonomy with interrupt capability

---

## Build Now vs Defer

### Build now (demo)

- [ ] tmux session launcher script (`canon/scripts/demo-session.sh`)
- [ ] State file spec (`.canon/state.json`) — the blackboard
- [ ] Skill teaching agent how to report state, pause, resume

### Defer (post-demo, high value)

- [ ] `/canon-start` orchestration command (agent-driven workflow)
- [ ] Phase-aware agent context (knows full pipeline, suggests next steps)
- [ ] Proactive workflow guidance ("I recommend X next. Proceed?")

### Defer (post-demo, polish)

- [ ] Rich TUI dashboard (Textual or Ink)
- [ ] WezTerm Lua integration (if switching terminal emulators)
- [ ] Centralized operation logging dashboard
- [ ] Config/auth system (Encore-style workspace authorization)
