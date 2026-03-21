<!-- Sources: SAS_AIDD_Pipeline.md (Overview: Agent Adapter Interface), SAS_Automation_Model.md (Interoperability, AGENTS.md, Why Both AGENTS.md AND Vector Memory), Canon_MVP_Technical_Roadmap.md (Feature 3: Simplified Ralph Loop) -->

# Interoperability and Memory

Patterns for cross-tool compatibility and persistent agent knowledge.

## Agent adapter interface

Abstract over different AI coding agents. Core orchestration patterns are
universal; only the hook mechanisms differ between hosts. Write the loop
logic once, swap the agent adapter per tool.

## Symlink interoperability

A canonical agent config folder maps to multiple tools via symlinks. The
same artifacts (personas, skills, commands) serve Claude Code, Codex,
Cursor, and other hosts without duplication.

## Three-layer loop architecture

Separate concerns across three layers:
1. **Host hooks** — sit above the agent, control looping and exit
2. **MCP tool** — checks success criteria, reports status
3. **Configuration** — declares loop parameters and gates

The MCP tool cannot control the agent; host hooks can intercept exit.
This separation allows each layer to evolve independently.

## Persistent agent learnings

A human-readable file (e.g. AGENTS.md) accumulates discovered patterns,
gotchas, and conventions. Read at session start; successful iterations
append new learnings. Knowledge compounds across sessions.

## Dual memory layers

Two complementary memory systems:
- **Explicit**: human-readable markdown, curated, read at session start
- **Implicit**: vector/graph store for pattern retrieval across histories

Explicit memory is reliable and inspectable. Implicit memory scales to
large histories. Neither replaces the other.
