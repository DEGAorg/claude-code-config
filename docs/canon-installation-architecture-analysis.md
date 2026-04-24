# Canon Installation & Architecture Analysis

> **Status:** Analysis Document  
> **Purpose:** Clarify installation flow, Core vs Canon layering, global vs local scope  
> **Derived from:** Canon MVP Technical Roadmap, SAS specs, and architecture discussion

---

## 1. What Is Stated in This Repo

### MCP Server

- The **Canon MCP Server** exposes 8 domain tools: `canon_init`, `canon_register`, `canon_test`, `canon_market`, `canon_position`, `canon_ralph`, `canon_activity`, `canon_help`.
- `canon_init` is explicitly defined as a tool that scaffolds a new strategy from templates (10 templates: odds-monitor, momentum-trader, arbitrage-scanner, etc.).
- The MCP server is the **tool layer** — it provides capabilities the agent can invoke.
- Phase I entry: "Install MCP server + use existing agent" (Claude Code, Cursor, OpenCode).

### canon_init Behavior

- Scaffolds into the **current directory** (project).
- Creates `.canon/` (config.yaml, ralph.yaml, agents/, skills/, workflows/, execution/, hooks/).
- Creates `AGENTS.md`.
- Includes framework pre-configured (personas, skills, workflows).
- Detects agent host and scaffolds appropriate hook scripts into `.canon/hooks/`.

### Canon Core / Agent Framework

- The **Canon "core"** (harness, skills, commands) lives in the project after scaffolding.
- Five-layer architecture: Tools (MCP) → Skills → Agent Personas → Workflows → Orchestration.
- Skills (8): prediction-markets, polymarket, risk-management, strategy-patterns, backtesting, arena-tracking, ralph-loop, canon-conventions.
- Orchestration via `.canon/config.yaml` and `AGENTS.md`.

### Dotagents Interoperability

| Project (`.agents/`) | Global (Claude Code) |
|---------------------|-----------------------|
| `AGENTS.md` | `~/.claude/CLAUDE.md` |
| `commands/` | `~/.claude/commands` |
| `hooks/` | `~/.claude/hooks` |
| `skills/` | `~/.claude/skills` |

Canon adopts `.agents/` as the canonical workspace directory. Interoperability with Claude Code/Codex via dotagents symlinks is optional.

### Quickstart Flow

- "Getting-started guide: install → load agent → scaffold → register in <15 minutes"
- Funnel: "GitHub → MCP install → Arena signup → registered strategy"

---

## 2. Architecture as Described

### Core vs Canon (Intended Model)

| Layer | Scope | Purpose |
|-------|-------|---------|
| **Core** | General AIDD | Harness, skills, commands that improve AI agents for any domain. Lives in a separate "claude code configs" repo. |
| **Canon** | Prediction markets | Domain-specific layer: Polymarket, Kalshi, strategy templates, Arena, risk patterns. Built on top of Core. |

- **Canon does not work alone** — it always requires Core.
- `canon_init` can deliver **Core + Canon** together when scaffolding a Canon strategy project.

### Install vs Init

| Concept | What It Does | Scope |
|---------|--------------|-------|
| **Install** | Add Canon MCP server to the AI host (Cursor, Claude Code). Provides tools. | Must be **global** (user-level) so `canon_init` is available in empty folders. |
| **Init** | Scaffold a new strategy or project. Creates `.canon/`, `AGENTS.md`, etc. | **Local repo** — writes to the current project directory. |

### BMAD Comparison

- BMAD: `npx bmad-method install` → project-local, creates `_bmad/` in the current directory. No MCP.
- Canon: `canon_init` (MCP tool) → scaffolds into project. Requires MCP server to be globally configured so it works when scaffolding new repos.

---

## 3. Implications

### Global MCP Install Required

- To scaffold **new** repos, the agent must have `canon_init` available when the project does not exist yet.
- If the MCP server is configured per-project only (e.g. `.cursor/mcp.json` in the repo), it is not available in an empty folder — chicken-and-egg.
- **Conclusion:** Canon MCP server must be installed to **global** Cursor/Claude config.

### canon_init Output Is Project-Local

- All scaffolded content (`.canon/`, `AGENTS.md`, agents, skills, workflows) is written to the **local repo**.
- No canonical statement that canon_init writes to `~/.claude/`.

### Core Installation Target Undefined

- If Core installs to `~/.claude/` (global): harness and general skills apply to all projects. canon_init adds project-local Canon-specific config.
- If Core installs to `.agents/` (project-local): Core + Canon both live in the project. canon_init would scaffold both into the same project.

### Canon Always Needs Core

- canon_init should scaffold **Core + Canon** together for Canon strategy projects.
- The MCP server templates would need to include Core artifacts (or a dependency on Core) when scaffolding.

---

## 4. Missing Information or Questions

### Explicitly Missing from Docs

1. **Global install instruction** — No statement that the Canon MCP server should be added to global Cursor/Claude MCP config (vs per-project).
2. **Core installation scope** — Where does Core (claude code configs) install: `~/.claude/` (global) or `.agents/` (project)?
3. **Core + Canon integration** — How does canon_init incorporate Core? Does it bundle Core artifacts, or assume Core is pre-installed globally?
4. **Core-only workflow** — When using Core alone (non–prediction-market work), where does Core install/init write: local repo or `~/.claude/`?

### Open Questions

| Question | Context |
|----------|---------|
| Should the quickstart guide explicitly say "Add Canon MCP server to global Cursor/Claude settings"? | Avoids per-project config and chicken-and-egg when scaffolding new repos. |
| Does canon_init depend on Core being pre-installed, or does it scaffold Core + Canon in one step? | Affects install order and user flow. |
| For Core (standalone), is the intended model global install (`~/.claude/`) or per-project (`.agents/`)? | Determines whether Core applies to all projects or only Canon projects. |
| Should the MCP server package document its installation target (global vs project)? | Clarifies for implementers and users. |

---

## 5. Summary

| Aspect | Stated | Missing / Unclear |
|--------|--------|-------------------|
| **MCP server** | Exposes 8 tools including `canon_init`. | Where to configure it (global vs project). |
| **canon_init** | Scaffolds into current directory. | Whether it includes Core or assumes pre-install. |
| **Core** | Referenced as separate layer (claude code configs). | Not defined in canon-docs. Install target undefined. |
| **Core + Canon** | Canon requires Core. canon_init can deliver both. | Integration flow not specified. |
| **Global vs local** | canon_init writes to local repo. Dotagents maps `.agents/` ↔ `~/.claude/`. | Global MCP install not stated. Core install target not stated. |

**Recommendation:** Document the full flow: (1) global MCP server install, (2) global vs project install for Core, (3) canon_init behavior and its relationship to Core, and (4) the distinction between install (host config) and init (project scaffold).
