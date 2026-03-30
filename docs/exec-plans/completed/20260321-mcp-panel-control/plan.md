# Plan: MCP Tool for Agent-Controlled TUI Panels

**Status:** Superseded
**Created:** 2026-03-21
**Completed:** 2026-03-23
**Repo:** DEGAorg/conductor-view (AGPL-3.0, conductor branch)

> **Note:** This plan was superseded by a simpler approach. Instead of an
> MCP server for panel control, we built a Unix socket controller
> (`socket_controller.py`) that accepts JSON commands directly. The ACP
> text interception (`/panel` commands) was kept for backward compatibility.
> Agent context injection handles discovery. Executed manually by Claude
> without the orchestrator — the work targeted conductor-view, which the
> orchestrator cannot manage yet due to multi-repo support not being
> implemented.

## Requirements

- Claude can call `panel_open`, `panel_close`, `panel_list` as proper MCP tool calls
- Panel opens/closes when Claude calls the tool
- Claude discovers tools naturally (listed in tool context, no prompt injection needed)
- Works through existing ACP protocol — no modifications to claude-code-acp
- Remove the `_intercept_panel_commands` regex hack from conversation.py
- Remove prompt injection and welcome text hacks from agent.py

## Approach

The ACP adapter (claude-code-acp) already handles `mcpServers` from `session/new`:
- Servers without `type` become stdio MCP servers (command + args)
- The adapter spawns the subprocess and registers tools with Claude

We create a small Python MCP server script (`src/toad/mcp/panel_server.py`) that:
1. Exposes 3 tools: `panel_open`, `panel_close`, `panel_list`
2. Communicates back to Toad via a Unix domain socket or a temp file
3. Toad watches for commands and emits OpenPanel/ClosePanel messages

Toad passes this server in the `mcpServers` list during `session/new`:
```python
api.session_new(cwd, [{"name": "conductor", "command": "python3", "args": [panel_server_path]}])
```

For the communication channel: the MCP server writes JSON commands to a temp file. Toad polls or watches the file. Simpler alternative: the MCP server writes to stdout (which the adapter captures), but that conflicts with MCP's stdio transport.

**Simplest viable approach:** The MCP server writes panel commands to a known temp file path (passed via env var). Toad's conversation widget watches this file for new commands. When a command appears, Toad emits the appropriate message and truncates the file.

Working directory: `/Users/cerratoa/dega/conductor-view`

## Files to touch

| File | Change |
|------|--------|
| `src/toad/mcp/__init__.py` | Create — empty package init |
| `src/toad/mcp/panel_server.py` | Create — MCP server exposing panel_open, panel_close, panel_list |
| `src/toad/acp/agent.py` | Pass conductor MCP server in session/new mcpServers; set up command file env var |
| `src/toad/acp/protocol.py` | Verify McpServer type supports env field (already does) |
| `src/toad/widgets/conversation.py` | Remove `_intercept_panel_commands` regex; add file watcher for MCP panel commands |
| `src/toad/screens/main.py` | No change — already handles OpenPanel/ClosePanel messages |
| `src/toad/data/agents/claude.com.toml` | Simplify welcome text — remove panel instructions |
| `pyproject.toml` | Add `mcp` dependency if not present |

## Risks and open questions

- **P1: Does the MCP Python SDK work with stdio transport for this use case?** The adapter spawns the server as a subprocess and communicates via stdio. The MCP server must use stdio transport. Need to verify `mcp` Python package supports this.
- **P1: Communication back to Toad.** The MCP server runs as a separate process. It needs to tell Toad "open panel github." A temp file with a file watcher is simple but has latency. A Unix socket is cleaner but more code.

## Progress log

- [ ] Research: verify MCP Python SDK stdio transport works, check if `mcp` package is already a dependency, decide communication mechanism (temp file vs socket)
- [ ] Create `src/toad/mcp/__init__.py` and `src/toad/mcp/panel_server.py` — MCP server with 3 tools using stdio transport (deps: 1)
- [ ] Update `src/toad/acp/agent.py` — pass conductor MCP server in session/new mcpServers, set up communication channel (deps: 2)
- [ ] Update `src/toad/widgets/conversation.py` — add watcher for MCP panel commands, remove regex hack (deps: 3)
- [ ] Update `src/toad/data/agents/claude.com.toml` — simplify welcome text (deps: 4)
- [ ] Test end-to-end: launch Toad, ask Claude to show project state, verify panel opens via tool call (deps: 5)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Stdio MCP server as subprocess | In-process MCP, ACP protocol extension, prompt injection | Adapter already supports stdio MCP servers via mcpServers param; no adapter modifications needed |
| Temp file for IPC back to Toad | Unix socket, shared memory, HTTP | Simplest to implement; latency is acceptable for panel open/close; no extra dependencies |
| Python MCP server | Node MCP server, shell script | Toad is Python; keeps the stack uniform; MCP Python SDK exists |

## Completion criteria

- [ ] Claude calls `panel_open` as a tool call (not text output) when asked for project state
- [ ] Panel opens in Toad sidebar when tool is called
- [ ] `panel_close` and `panel_list` tools work
- [ ] No `_intercept_panel_commands` regex in conversation.py
- [ ] No prompt injection or welcome text hacking in agent.py
- [ ] `pyproject.toml` has MCP dependency if added
- [ ] MCP server script runs standalone without errors
