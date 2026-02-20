# Canon MVP Roadmap: Alternative B — Agent Framework First

> **Status:** Proposed Alternative  
> **Relationship to Plan A:** [Canon_MVP_Technical_Roadmap.md](./Canon_MVP_Technical_Roadmap.md) (VS Code fork first)  
> **Phase I Timeline:** February 17 – April 4, 2026 (~7 weeks)  
> **Launch Event:** [Canon NBA Playoffs Hackathon 2026](./Canon_NBA_Playoffs_2026.md) — April 19  
> **Target:** Canon Agent Framework + Canon Arena live for 150+ developers competing with strategies

---

## Why Alternative B

Plan A ships a VS Code fork (Canon IDE) alongside Arena for Phase I. Alternative B **defers the fork to Phase II** and ships a **Canon Agent Framework** — an MCP server, agent personas, skills, workflows, and configurations that work with existing coding agents (Claude Code, OpenCode, Cursor). The VS Code fork becomes a Phase II deliverable, built on real hackathon data.

**The case, stated once:**

1. **The fork is high-risk and not what makes the hackathon work.** The hackathon IS the Arena — strategies competing on a leaderboard. Whether developers build those strategies in a Canon-branded IDE or in Claude Code with Canon's MCP tools, the Arena experience is identical. The fork adds brand value; the hackathon needs execution reliability.

2. **A VS Code fork is unpredictably expensive.** Electron packaging, extension APIs, cross-platform testing, auto-update infra, Kilo Code integration — estimates routinely double. Every week on Electron is a week not on execution reliability, which [Inversion Thinking](./Canon_Inversion_Thinking.md) identifies as the #1 trust-builder.

3. **The SAS designed for this.** Canon's architecture is explicitly agent-agnostic ([SAS_AIDD_Pipeline.md](./specs/SAS_AIDD_Pipeline.md)). An MCP server IS the abstraction layer. Any agent can consume it. Alternative B is the purest expression of the SAS's core principle.

4. **An MCP server is your product, not a plugin.** Canon owns the MCP server, Arena backend, pmxt integration, Ralph Loop logic, strategy pipeline, and user accounts. The coding agent is a replaceable client — the same way Chrome is a replaceable client for a SaaS product.

5. **The hackathon validates demand regardless of surface.** "Do developers want AI-assisted prediction market tooling, and does Arena drive engagement?" — this answer is identical whether participants used a VS Code fork or a terminal.

6. **Post-hackathon fork is built on data, not assumptions.** Which tools did they use most? Where did onboarding break? What workflows need visual UI? Building the fork after this data exists produces a better product faster.

**What this trades away:**

| Tradeoff | Impact | Mitigation |
|----------|--------|------------|
| No "Canon IDE" at hackathon | Weaker brand impression | Arena IS the branded product — leaderboard, strategy cards, portfolio tracking |
| Developer-only Phase I | Smaller TAM for initial event | First hackathon explicitly targets developers; non-dev users are Phase II |
| Weaker investor demo | Harder to pitch without IDE | Don't pitch until fork exists; use hackathon data as validation evidence |
| Terminal experience | Power users form opinions early | Invest fork-freed time into bulletproof MCP tools, onboarding, and Arena polish |

**Decision matrix:**

| Factor | Plan A (Fork First) | Alternative B (Framework First) |
|--------|---------------------|-------------------------------|
| Execution risk | Higher — fork is unpredictable | Lower — MCP server is well-scoped |
| Time to hackathon | Tighter — fork on critical path | More comfortable — fork removed |
| Hackathon experience | Branded IDE + Arena | Terminal tools + Arena |
| Post-hackathon pitch | Stronger immediately | Stronger after fork ships (but with validation data) |
| Engineering focus | Split fork + core features | 100% Arena, Ralph Loop, execution reliability |
| Architecture alignment | Agent-agnostic used for one host | Agent-agnostic used agent-agnostically |
| Dogfooding | Building something team doesn't use | Shipping what team uses daily |

---

## Phase Overview

| Phase | Timeline | Focus | Key Deliverables |
|-------|----------|-------|------------------|
| **Phase I** | Feb 17 – Apr 4 (~7 weeks) | Hackathon Infrastructure | Canon Agent Framework (MCP Server), Arena MVP, Ralph Loop, pmxt, Execution Hardening |
| **Phase II** | Post-Hackathon (Jun–Jul 2026) | Canon IDE + Growth | VS Code Fork, Marketplace, Collaboration, Blueprints, Advanced Features |

**Strategic constraints (unchanged from Plan A):**

1. **Time Constraint** — ~7 weeks for Phase I (AI-assisted development)
2. **Weird Differentiation** — Decisively different from Cursor and Claude Code
3. **Flexibility** — Leverage external tech (AgentAdapters, Skills, MCPs, existing AI agents)
4. **Dogfooding** — Canon builds Canon, compounding our own growth
5. **Network Effects** — Seeded at hackathon, monetized in Phase II

---

## Reference Implementation: Auto-Claude

Canon's core infrastructure leverages **Auto-Claude** — a fully-built, open-source autonomous coding framework — as a reference implementation.

> ⚠️ **Note:** Auto-Claude is a new project. While complete and functional, it has not been battle-tested at scale. Port with appropriate validation.

```
┌─────────────────────────────────────────────────────────────────┐
│                 AUTO-CLAUDE → CANON PORT MAP                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   PHASE I (~7 weeks)                                             │
│   ──────────────────                                             │
│   qa/loop.py (simplified)  →    src/agents/ralph-loop.ts         │
│                                                                  │
│   PHASE II (Post-Hackathon)                                      │
│   ─────────────────────────                                      │
│   core/worktree.py         →    src/core/worktree.ts             │
│   implementation_plan/     →    src/core/dag/                    │
│   memory/                  →    src/core/memory/                 │
│                                                                  │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │         PHASE I: BUILD NEW                              │   │
│   │  • Canon MCP Server (domain tools for agents)           │   │
│   │  • Canon Arena web dashboard                            │   │
│   │  • Prediction market adapter (via pmxt)                  │   │
│   │  • Agent configurations (AGENTS.md, custom commands)    │   │
│   ├─────────────────────────────────────────────────────────┤   │
│   │         PHASE II: BUILD NEW                             │   │
│   │  • Canon IDE (VS Code fork)                             │   │
│   │  • Conductor Agent (Kilo Code)                          │   │
│   │  • Marketplace + x402 payments                          │   │
│   │  • Composable Blueprints                                │   │
│   │  • Multi-agent adapters (AgentAdapter protocol)          │   │
│   │  • (Kalshi adapter — free via pmxt)                     │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

| Auto-Claude Component | Canon Port | Phase |
|-----------------------|------------|-------|
| **QA Validation Loop** (`qa/loop.py`) | Ralph Loop (simplified) | **Phase I** |
| **WorktreeManager** (`core/worktree.py`) | Parallel agent isolation | Phase II |
| **ImplementationPlan** (`implementation_plan/`) | DAG task decomposition | Phase II |
| **Memory Layer** (`memory/`) | Session persistence | Phase II |
| **PhaseExecutor** (`spec/phases/`) | Task orchestration | Phase II |

> 📄 **Auto-Claude Source:** [github.com/AndyMik90/Auto-Claude](https://github.com/AndyMik90/Auto-Claude)

> ✅ **Architecture Validation:** Auto-Claude was ported without modifying the [Canon SAS](./Canon_SAS.md). All ported components map directly to concepts already specified in the architecture — Auto-Claude is purely an implementation detail, not an architectural dependency.

---

## Context: What is Canon?

**Canon is an AI-Driven Development (AIDD) framework for prediction market strategies.** The ready-to-go automations are not the product — they are the starting point. The product is the MCP tools, agent personas, workflows, and Ralph Loop that let users build, customize, and extend those automations using AI agents. Canon users aren't consuming a finished tool; they are developers using Canon's AIDD infrastructure to create their own prediction market automation stack.

Think "TradingView for prediction markets" — but where the *development environment* is the competitive moat, not the automations themselves. Specifically:

- **Code-first strategies** (TypeScript/Python) — users own and modify their logic
- **AI agents** that help build, debug, iterate, and execute — the AIDD loop is the interface
- **Ready-to-go automations** as scaffolding — 10 starter templates, not finished products
- **Marketplace** where creators sell their AIDD-built strategies and earn 85% revenue
- **Multi-day autonomous execution** (agents that don't quit until the job is done)

> **The core insight:** Carson's Code Factory patterns (risk tiers, preflight gates, SHA discipline, remediation loops) are not just how Canon's team builds Canon internally — they are patterns Canon's users will run on their own strategy codebases. Canon's Agent Framework *is* the harness.[^harness-factory]

**Phase I focuses on Polymarket** ($26B+ volume). Future phases expand to Kalshi, crypto, sports betting, and TradFi.

> 📄 **Full Vision:** [Canon_Product_Vision.md](./Canon_Product_Vision.md)  
> 📄 **Architecture:** [Canon_SAS.md](./Canon_SAS.md)

---

## Two-Product Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                CANON PLATFORM (ALTERNATIVE B)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  PHASE I (Hackathon)                                             │
│  ───────────────────                                             │
│                                                                  │
│  ┌───────────────────────┐     ┌──────────────────────────────┐ │
│  │  CANON AGENT FRAMEWORK│     │       CANON ARENA            │ │
│  │  (MCP Server + Tools) │     │    (Web Dashboard)           │ │
│  │                       │     │                              │ │
│  │  • MCP tools for      │     │  • Track strategy performance │ │
│  │    strategy building   │────►│  • AI Automation leaderboard │ │
│  │  • Ralph Loop hooks   │     │  • Monitor positions         │ │
│  │  • Starter templates  │     │  • Portfolio tracking         │ │
│  │  • Agent configs      │     │                              │ │
│  │                       │     │                              │ │
│  │  Works with:          │     │                              │ │
│  │  Claude Code, OpenCode│     │                              │ │
│  │  Cursor, any MCP host │     │                              │ │
│  └───────────┬───────────┘     └──────────────┬───────────────┘ │
│              │                                │                  │
│              └────────────┬───────────────────┘                  │
│                           ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              SHARED BACKEND LAYER                        │    │
│  │  (Polymarket automation, auth, Arena API, strategy DB)  │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  PHASE II (Post-Hackathon)                                       │
│  ─────────────────────────                                       │
│                                                                  │
│  ┌───────────────────────┐     ┌──────────────────────────────┐ │
│  │     CANON IDE         │     │       CANON ARENA v2         │ │
│  │   (VS Code Fork)      │     │    (Web Dashboard)           │ │
│  │                       │     │                              │ │
│  │  • Build strategies   │     │  • Everything from Phase I   │ │
│  │  • Visual tools       │────►│  • Copy/Counter trades       │ │
│  │  • Conductor Agent    │     │  • AI Decision Feed          │ │
│  │  • Non-dev friendly   │     │  • Social features           │ │
│  │  • Marketplace publish│     │  • Marketplace               │ │
│  └───────────────────────┘     └──────────────────────────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

| Aspect | Phase I: Agent Framework | Phase II: Canon IDE |
|--------|--------------------------|---------------------|
| **User** | Developers (technical) | Builders + Deployers (broader audience) |
| **Entry friction** | Install MCP server + use existing agent | Download Canon IDE |
| **Arena** | Full experience (web) | Full experience (web) + IDE integration |
| **Function** | Create supply (strategies) | Create supply + consume supply (marketplace) |

> 📄 **Figma Model Architecture:** [SAS_UI_Collaboration.md § Unified Application Architecture](./specs/SAS_UI_Collaboration.md#unified-application-architecture-figma-model)  
> 📄 **Arena UI Reference:** [AI_Arena_UI.md](../AI_Arena_UI.md)  
> 📄 **Automation Backend:** [Canon_Polymarket_Automation_Guide.md](./Canon_Polymarket_Automation_Guide.md)

---

## Open Core Distribution Strategy

Canon adopts an **open core** model: the developer-facing framework and tools are open source; the platform, execution infrastructure, and marketplace are proprietary. This is the dominant strategy for developer-facing companies building on open ecosystems (Cursor/VS Code, Supabase/Postgres, Vercel/Next.js, GitLab CE/EE).

**The case:**

1. **Canon is built on open source.** BMAD Method, Auto-Claude, pmxt, Open Trees, MCP itself — Canon's foundation is entirely open source. Contributing back is both ethical and strategic; the developer community notices (and punishes) projects that take without giving.

2. **Phase I targets developers.** The hackathon audience is the most open-source-literate demographic. An open-source agent framework gets instant credibility; a closed-source one invites "why should I build on something I can't inspect?" — a question better avoided on Day 1.

3. **Agent-agnosticism requires openness.** Canon works with Claude Code, OpenCode, Cursor, and any MCP host. Open source removes friction for integration — maintainers of other tools can inspect, test, and build adapters without waiting on Canon's team.

4. **The framework is the on-ramp, not the business.** Developers use the open-source tools for free to build strategies, then register on the proprietary Arena to track performance, compete on leaderboards, and monetize. The framework grows the ecosystem; the platform captures value.

5. **Standards propagate through openness.** If Canon's Agent Framework patterns (personas/skills/workflows orchestration) are to become a standard for prediction market AI tooling, open source is the mechanism. Closed standards die or get routed around.

### The Split

```
┌─────────────────────────────────────────────────────────────────┐
│              OPEN CORE — DISTRIBUTION BOUNDARY                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  OPEN SOURCE (Apache 2.0)                                        │
│  ─────────────────────────────────────────────────               │
│  Canon MCP Server        8 domain tools (protocol layer)         │
│  Canon Agent Framework   Personas, skills, workflows, config     │
│  Ralph Loop              Simplified implementation + host hooks  │
│  Starter Templates       10 pre-built strategy scaffolds         │
│  .canon/ conventions     Directory structure and standards       │
│                                                                  │
│  PROPRIETARY — THE CANON AI APP (closed source)                  │
│  ──────────────────────────────────────────────                  │
│                                                                  │
│  Platform & Surfaces                                             │
│  Canon Arena             Leaderboard, tracking, portfolio        │
│  Canon IDE               VS Code fork, Conductor Agent (Ph. II)  │
│  Marketplace             Listings, x402 payments, creator econ.  │
│                                                                  │
│  Execution & Infrastructure                                      │
│  Execution Layer         Trade execution, reconciliation,        │
│                          circuit breakers, monitoring             │
│  Automation Backend      Polymarket/Kalshi execution, positions  │
│  Cloud Execution Service Fly.io Machines — persistent containers, │
│    (SEPARATE FROM ARENA) per-user isolation, always-on (first $)  │
│                                                                  │
│  Social & Collaboration                                          │
│  Collaboration Layer     Teams, DMs, channels, project sharing,  │
│                          roles & permissions, presence            │
│  Social Features         Follow, comments, notifications,        │
│                          referral codes, copy/counter trading     │
│  AI Decision Feed        Stream of agent reasoning, public logs  │
│                                                                  │
│  AI Ecology                                                      │
│  Multi-Agent Orchestration  Invite external agents into your     │
│                             workflow, agent-to-agent handoffs     │
│  AI Agents in Channels   @RiskAgent, @MarketAnalyst in team chat │
│  AI-to-AI Social Learning  Agents learn from other agents' runs  │
│  Conductor Agent         Primary IDE agent (Kilo Code, Ph. II)   │
│                                                                  │
│  Identity & Accounts                                             │
│  User Infrastructure     Accounts, auth, profiles, API keys      │
│                                                                  │
│  WHY THIS BOUNDARY:                                              │
│  Open source grows the ecosystem — more developers building      │
│  strategies = more Arena registrations = more marketplace supply. │
│  Proprietary captures value — the Canon AI App is where users    │
│  deploy, collaborate, compete, host, and pay. The social graph,  │
│  AI ecology, and cloud hosting create compounding lock-in that   │
│  open-source tools alone cannot replicate.                       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Open source (developer tools — the on-ramp):**

| Component | Distribution | Rationale |
|-----------|-------------|-----------|
| **Canon MCP Server** | Open source (Apache 2.0) | Protocol adapter — value is in what it connects to, not the adapter itself |
| **Agent Framework** (personas, skills, workflows) | Open source (Apache 2.0) | Markdown artifacts — community contributions make them better for everyone |
| **Ralph Loop** (simplified) | Open source (Apache 2.0) | Iteration pattern — adoption drives standardization |
| **Starter templates** | Open source (Apache 2.0) | Onboarding content — more templates = lower friction = more Arena users |
| **Host hooks** (Claude Code, Cursor, OpenCode) | Open source (Apache 2.0) | Integration layer — must be inspectable by host maintainers |

**Proprietary (the Canon AI App — where value compounds):**

| Component | Category | Rationale |
|-----------|----------|-----------|
| **Canon Arena** | Platform | Core product — leaderboard, performance tracking, portfolio monitoring |
| **Canon IDE** (Phase II) | Platform | VS Code fork, Conductor Agent, visual tools — the branded surface |
| **Marketplace** | Platform | Revenue engine — listings, payments, creator economics |
| **Execution infrastructure** | Infrastructure | Money-touching code — trade execution, reconciliation, circuit breakers |
| **Automation backend** | Infrastructure | Polymarket/Kalshi execution layer — operational IP |
| **Cloud Execution Service** | Infrastructure | Production-grade strategy hosting on Fly.io Machines — per-user persistent containers with auto-restart, persistent volumes, exchange reconciliation for crash recovery. **Separate from Arena** (Arena tracks; this runs). First paid feature ($29/mo post-hackathon). Phase I deliverable. |
| **Collaboration Layer** | Social | Teams, DMs, channels, project sharing, roles & permissions, presence — the "Bloomberg Chat" lock-in |
| **Social features** | Social | Follow, comments, notifications, referral codes, copy/counter trading |
| **AI Decision Feed** | Social | Stream of agent reasoning — transparency layer that drives engagement |
| **Multi-agent orchestration** | AI Ecology | Invite external agents into your workflow, agent-to-agent handoffs, tri-provider coordination |
| **AI agents in channels** | AI Ecology | `@RiskAgent what's our exposure?` — agents as first-class collaboration participants |
| **AI-to-AI Social Learning** | AI Ecology | Agents learn from other agents' successful runs — the recursive improvement engine |
| **Conductor Agent** (Phase II) | AI Ecology | Primary IDE agent (Kilo Code) — the user-facing orchestrator |
| **User accounts + auth** | Identity | Platform identity — switching cost, profile, API keys |

### License Strategy

All open-source components — Canon MCP Server, Agent Framework, Ralph Loop, starter templates, and host hooks — are **Apache 2.0 licensed**. This provides maximum adoption with an explicit patent grant, making Canon suitable for enterprise and corporate environments without legal review friction.

### Precedent Validation

| Company | Open Source | Proprietary | Outcome |
|---------|-----------|-------------|---------|
| **Cursor** | Built on VS Code (MIT) | AI features, cloud sync | Dominant AI coding tool |
| **Supabase** | Client libraries, tooling | Hosted platform, dashboard | $116M ARR (2025) |
| **Vercel** | Next.js framework | Hosting platform, analytics | Framework became the standard |
| **GitLab** | Core CE edition | Enterprise features, SaaS | $34B acquisition by Google (2025) |
| **HashiCorp** | Terraform (BSL) | Terraform Cloud, HCP | $35B acquisition by IBM (2024) |

The pattern is consistent: open source the framework that grows the ecosystem, monetize the platform that captures value from it.

---

## Phase I Scope (~7 Weeks)

### What's in Phase I

| Feature | Complexity | Source |
|---------|------------|--------|
| **Canon MCP Server** (8 domain tools) | Medium | New |
| **Canon Agent Framework** (personas, skills, workflows, orchestration) | Low-Medium | New (influenced by [BMAD](https://github.com/bmad-code-org/BMAD-METHOD), [Agent OS](https://buildermethods.com/agent-os)) |
| **Canon Arena MVP** (leaderboard + performance tracking) | Medium-High | New |
| **Simplified Ralph Loop** (stop hook + success criteria) | Low | Port from Auto-Claude |
| **Prediction market adapter (pmxt)** | Low | [pmxt](https://github.com/pmxt-dev/pmxt) |
| **Starter templates** (10 pre-built strategies) | Low | New |
| **Execution Reliability & Hardening** | Medium | New |
| **Cloud Execution Service** (Fly.io Machines) — production-grade, first paid feature | Medium-High | New + [SAS_Deployment.md](./specs/SAS_Deployment.md) |
| **Developer onboarding** (docs, guides, quickstart) | Low-Medium | New |
| **Harness Eng. Patterns**[^harness-eng] | Low | [Canon_SAS.md](./Canon_SAS.md#core-operating-principles) |
| **Runtime Bridge (minimal)**[^harness-eng] | Medium | [Canon_SAS.md](./Canon_SAS.md#runtime-bridge--application-legibility-for-agents-phase-1) |
| Basic Memory Layer | Low | Port from Auto-Claude |

### What's deferred to Phase II

| Feature | Complexity | Source |
|---------|------------|--------|
| **Canon IDE (VS Code fork)** | High | New — informed by hackathon data |
| **Conductor Agent (Kilo Code)** | Medium | New — requires IDE |
| Marketplace MVP (listings + x402) | Medium | New |
| Composable Blueprints (visual wiring) | Medium | New |
| Kalshi API adapter | Trivial | pmxt provides unified API |
| Local PR System (Worktrees) | Low | Port from Auto-Claude |
| DAG Task Decomposition | Low | Port from Auto-Claude |
| Advanced Ralph Loop (spiral detection, DAG) | Medium | New |
| Copy/Counter trading | Medium | New |
| AI Decision Feed | Medium | New |
| Referral code system | Low | New |
| Cloud Execution: advanced (scheduled runs, event triggers, multiplayer, Inngest evaluation) | Medium | New |
| Collaboration Layer | Medium | New |
| Entropy Management[^harness-eng] | Medium | [Canon_SAS.md](./Canon_SAS.md#doc-gardening-agent-automated-knowledge-base-maintenance) |

---

## Phase I Features

### Feature 1: Canon Arena MVP

Canon Arena is a **performance tracking dashboard** — it monitors registered Polymarket accounts and displays charts, leaderboards, and portfolio data. Arena does not host execution infrastructure; strategies run on users' own machines (or Canon's cloud execution service in the future). Arena reads Polymarket account state and presents it.

| Component | Description | Priority |
|-----------|-------------|----------|
| **AI Automation Leaderboard** | Rank by portfolio value, win rate, ROI | P0 |
| **Strategy registration** | Register strategy on Arena for tracking (via `canon_register` MCP tool or CLI) | P0 |
| **Portfolio tracking** | Real-time P&L, position monitoring (reads from Polymarket) | P0 |
| **Basic strategy cards** | View registered strategy info and performance | P0 |

**Deferred to Phase II:** AI Decision Feed, Copy/Counter trading, advanced social features.

> 📄 **UI Reference:** [AI_Arena_UI.md](../AI_Arena_UI.md)
> 📄 **Automation Guide:** [Canon_Polymarket_Automation_Guide.md](./Canon_Polymarket_Automation_Guide.md)

---

### Feature 2: Canon Agent Framework (MCP Server + Agent Personas + Skills + Workflows)

The Agent Framework replaces the VS Code fork as the Phase I builder experience. It's a structured prompt engineering and agent orchestration system — inspired by [BMAD Method](https://github.com/bmad-code-org/BMAD-METHOD) and [Agent OS](https://buildermethods.com/agent-os) — that defines how AI agents understand, operate within, and build for Canon's prediction market platform.

> 📄 **Full Agent Framework Specification:** [SAS_Agent_Framework.md](./specs/SAS_Agent_Framework.md)

MCP tools give agents *capabilities* (register, test, query data). The Agent Framework adds the intelligence layer: **agent personas** that understand prediction markets, **skills** that encode domain expertise, and **workflows** that guide agents through Canon's development lifecycle.

**Five-layer architecture:**

| Layer | What It Defines | Artifact Type |
|-------|----------------|---------------|
| **Tools (MCP)** | What agents can do — capabilities | TypeScript (Canon MCP Server) |
| **Skills** | What agents know — composable domain knowledge | Markdown (`.canon/skills/`) |
| **Agent Personas** | Who the agent is — role, expertise, constraints | Markdown (`.canon/agents/`) |
| **Workflows** | How work flows — structured multi-step sequences | YAML + Markdown (`.canon/workflows/`) |
| **Orchestration** | How it all composes — context routing, standards | YAML (`.canon/config.yaml`) |

**Phase I scope:**

| Component | Description | Priority |
|-----------|-------------|----------|
| **Canon MCP Server** | MCP tool server exposing Canon's domain tools (8 tools) | P0 |
| **`canon_init`** | Scaffold new strategy from template (10 templates, includes `.canon/` framework) | P0 |
| **`canon_register`** | Register strategy on Arena for performance tracking | P0 |
| **`canon_test`** | Run strategy against historical market data | P0 |
| **`canon_market`** | Query real-time market data via pmxt | P0 |
| **`canon_position`** | Check current positions, P&L, portfolio state | P0 |
| **`canon_ralph`** | Ralph Loop verification — run success criteria checks, track iteration state, enforce budget (the *checking brain*; looping lives in host hooks) | P0 |
| **`canon_activity`** | Query structured execution data (trades, decisions, signals, summaries) — reads local store or cloud API; the agent interprets and explains to the user | P0 |
| **`canon_help`** | Contextual guidance — what to do next (inspired by BMAD `/bmad-help`) | P0 |
| **Agent Personas (6)** | Strategy Architect, Market Analyst, Dev, QA, Risk Analyst, Deployment Ops | P0 |
| **Skills (8)** | Prediction markets, Polymarket, Risk management, Strategy patterns, Backtesting, Arena tracking, Ralph Loop, Canon conventions | P0 |
| **Workflows (5)** | Discover, Develop, Register, Ralph Cycle, Quick Dev | P0 |
| **Orchestration config** | `.canon/config.yaml` — context routing, standards injection, agent selection | P0 |
| **AGENTS.md** | ~100-line TOC entry point for the full framework | P0 |
| **Developer quickstart** | Getting-started guide: install → load agent → scaffold → register in <15 minutes | P0 |

**MCP Server implementation:**

```typescript
// Canon MCP Server — domain tools for coding agents
const server = new McpServer({
  name: "canon",
  version: "1.0.0",
});

// Strategy scaffolding — includes .canon/ framework in every project
server.tool("canon_init", {
  template: z.enum([
    "odds-monitor", "bracket-builder", "simple-strategy",
    "momentum-trader", "arbitrage-scanner", "news-sentiment",
    "portfolio-rebalancer", "contrarian-fade",
    "volatility-harvester", "multi-market-basket"
  ]),
  name: z.string().optional(),
}, async ({ template, name }) => {
  // Scaffold strategy + .canon/ directory (agents, skills, workflows, config)
});

// Arena registration (register strategy for performance tracking)
server.tool("canon_register", {
  strategy_path: z.string(),
  arena_name: z.string().optional(),
  polymarket_wallet: z.string(),
}, async ({ strategy_path, arena_name, polymarket_wallet }) => {
  // Register strategy metadata + Polymarket wallet with Arena for tracking
});

// Market data (via pmxt)
server.tool("canon_market", {
  query: z.string().optional(),
  market_id: z.string().optional(),
  platform: z.enum(["polymarket", "kalshi"]).default("polymarket"),
}, async ({ query, market_id, platform }) => {
  // Fetch market data via pmxt unified API
});

// Position management
server.tool("canon_position", {
  action: z.enum(["list", "pnl", "portfolio"]),
}, async ({ action }) => {
  // Check positions, P&L, portfolio state via pmxt
});

// Ralph Loop verification (checking brain — looping legs live in host hooks)
server.tool("canon_ralph", {
  action: z.enum(["check", "status", "init"]),
  criteria_overrides: z.array(z.string()).optional(),
}, async ({ action, criteria_overrides }) => {
  // "init"   → Read .canon/ralph.yaml, return config + set iteration 0
  // "check"  → Run success criteria (tests, lint, types, custom),
  //            return pass/fail per criterion + diagnostic feedback
  //            + iteration count + budget remaining
  // "status" → Return current iteration state without running checks
});

// Strategy testing
server.tool("canon_test", {
  strategy_path: z.string(),
  market_id: z.string().optional(),
  timeframe: z.string().default("7d"),
}, async ({ strategy_path, market_id, timeframe }) => {
  // Run strategy against historical data via pmxt fetchOHLCV
});

// Automation activity — structured execution data for agent interpretation
server.tool("canon_activity", {
  action: z.enum(["trades", "decisions", "signals", "summary"]),
  since: z.string().optional(),       // ISO timestamp or relative ("1h", "24h")
  market_id: z.string().optional(),
  limit: z.number().default(20),
}, async ({ action, since, market_id, limit }) => {
  // Reads from local execution store (.canon/execution/) when running locally,
  // or queries Canon Cloud Execution API when connected to cloud.
  // "trades"    → Recent trades with entry reasoning, signal values, risk assessment
  // "decisions" → All decision points (including decisions NOT to trade) with reasoning
  // "signals"   → Raw signal history (odds velocity, sentiment scores, thresholds)
  // "summary"   → Natural-language-ready digest: what happened, top trades, P&L impact
});

// Contextual guidance (inspired by BMAD /bmad-help)
server.tool("canon_help", {
  question: z.string().optional(),
}, async ({ question }) => {
  // Reads .canon/ config, project state, recommends next agent/skill/workflow
});
```

**Automation Observability — the agent as the comprehension layer:**

Strategies are headless terminal processes — they run identically on a developer's laptop and on Canon's cloud infrastructure. For AI-assisted developers (not necessarily experts), understanding *why* trades happen is critical. Rather than building a dedicated trade reasoning UI for Phase I, Canon makes the **agent itself** the comprehension layer by giving it structured execution data to query and interpret.

All starter templates emit structured execution data (trades, decisions, signals, reasoning) to a local store (`.canon/execution/`). The `canon_activity` MCP tool provides a unified query interface that agents use to build dynamic queries against this data — then interpret and narrate results in natural language for the end user.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│           AUTOMATION OBSERVABILITY — LOCAL ↔ CLOUD TRANSPARENCY              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  STRATEGY EXECUTION (headless process)                                       │
│  ─────────────────────────────────────                                       │
│  Every template emits structured execution data:                             │
│  • Trade events: what was bought/sold, price, size, reasoning                │
│  • Decision points: signals evaluated, thresholds checked, action taken      │
│  • Signal history: raw values over time (odds velocity, sentiment, etc.)     │
│                                                                              │
│  LOCAL EXECUTION                        CLOUD EXECUTION                      │
│  ─────────────────                      ─────────────────                    │
│  Strategy writes to                     Strategy writes to                   │
│  .canon/execution/                      Canon Cloud Execution API            │
│       │                                       │                              │
│       ▼                                       ▼                              │
│  ┌──────────────────────────────────────────────────────┐                   │
│  │  canon_activity MCP tool (unified query interface)    │                   │
│  │                                                       │                   │
│  │  Detects execution context:                           │                   │
│  │  • Local? → reads .canon/execution/ (JSON files)      │                   │
│  │  • Cloud? → queries Cloud Execution API               │                   │
│  │                                                       │                   │
│  │  Same tool, same queries, same response format.       │                   │
│  └──────────────────────┬───────────────────────────────┘                   │
│                         │                                                    │
│                         ▼                                                    │
│  ┌──────────────────────────────────────────────────────┐                   │
│  │  AGENT (Claude Code, Cursor, OpenCode)                │                   │
│  │                                                       │                   │
│  │  Builds dynamic queries via canon_activity:           │                   │
│  │  "Show me trades from the last 4 hours"               │                   │
│  │  "Why did it buy YES on Lakers Game 3?"               │                   │
│  │  "What signals triggered the last 5 decisions?"       │                   │
│  │  "Summarize today's activity and P&L impact"          │                   │
│  │                                                       │                   │
│  │  → Interprets structured data → explains to user      │                   │
│  │    in natural language with full context               │                   │
│  └──────────────────────────────────────────────────────┘                   │
│                                                                              │
│  WHY THIS WORKS:                                                             │
│  The agent IS the comprehension layer. No dedicated trade reasoning UI       │
│  needed in Phase I — the same agent that helped build the strategy can       │
│  explain what it's doing, because it has structured data to query.           │
│  The AI Decision Feed (Phase II Arena feature) later surfaces this same      │
│  data in a web UI for passive monitoring without an agent conversation.      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Agent Framework directory structure:**

```
my-strategy/
├── .canon/
│   ├── config.yaml              # Orchestration: context routing, standards
│   ├── ralph.yaml               # Ralph Loop config (success criteria, budget)
│   ├── execution/               # Structured execution data (queried by canon_activity)
│   │   ├── trades.jsonl         # Trade events with reasoning
│   │   ├── decisions.jsonl      # Decision points (including no-trade decisions)
│   │   └── signals.jsonl        # Raw signal values over time
│   ├── agents/                  # 6 agent personas
│   │   ├── strategy-architect.md
│   │   ├── market-analyst.md
│   │   ├── dev.md
│   │   ├── qa.md
│   │   ├── risk-analyst.md
│   │   └── deployment-ops.md
│   ├── skills/                  # 8 composable knowledge modules
│   │   ├── prediction-markets.md
│   │   ├── polymarket.md
│   │   ├── risk-management.md
│   │   ├── strategy-patterns.md
│   │   ├── backtesting.md
│   │   ├── arena-tracking.md
│   │   ├── ralph-loop.md
│   │   └── canon-conventions.md
│   ├── workflows/               # 5 structured sequences
│   │   ├── discover.yaml        # Market analysis → strategy design
│   │   ├── develop.yaml         # Scaffold → implement → test → iterate
│   │   ├── register.yaml        # Risk review → register on Arena → monitor
│   │   ├── ralph-cycle.yaml     # Autonomous iteration loop
│   │   └── quick-dev.yaml       # Lightweight build for small changes
│   └── hooks/                   # Host-specific Ralph Loop continuation hooks
│       ├── claude-code/         # Claude Code hook scripts (.claude/hooks/)
│       │   └── ralph-stop-hook.sh
│       ├── cursor/              # Cursor rule files for Ralph continuation
│       │   └── ralph-continuation.mdc
│       └── opencode/            # OpenCode hook scripts
│           └── ralph-stop-hook.sh
├── AGENTS.md                    # ~100-line TOC (framework entry point)
├── src/
│   ├── strategy.ts
│   └── types/
├── package.json
└── README.md
```

**AGENTS.md (entry point):**

```markdown
# Canon Strategy Development

## Quick Reference
- Framework config: `.canon/config.yaml`
- Agent personas: `.canon/agents/` (6 specialized agents)
- Skills (domain knowledge): `.canon/skills/` (8 composable modules)
- Workflows: `.canon/workflows/` (5 structured sequences)
- Ralph Loop config: `.canon/ralph.yaml`
- Ralph Loop hooks: `.canon/hooks/` (host-specific continuation scripts)

## Available Agents
| Agent | Role | Load When |
|-------|------|-----------|
| strategy-architect | Designs strategies from market analysis | Starting a new strategy |
| market-analyst | Interprets market data, finds opportunities | Exploring markets |
| dev | Implements strategies in TypeScript | Writing code |
| qa | Validates quality and standards compliance | Reviewing before registration |
| risk-analyst | Evaluates risk and portfolio impact | Before registration |
| deployment-ops | Registers on Arena, monitors performance | Registering a strategy |

## Available Tools (MCP)
- `canon_init` — Scaffold strategy from template (includes .canon/ framework)
- `canon_register` — Register strategy on Arena for performance tracking
- `canon_test` — Run against historical data
- `canon_market` — Query market data (Polymarket, Kalshi)
- `canon_position` — Check positions, P&L, portfolio
- `canon_ralph` — Ralph Loop verification (check criteria, track state, enforce budget)
- `canon_activity` — Query execution data (trades, decisions, signals) — works local and cloud
- `canon_help` — Get contextual guidance (what to do next)

## Key Workflows
1. **Discover:** Market analysis → opportunity → strategy design
2. **Develop:** Scaffold → implement → test → iterate (Ralph Loop)
3. **Register:** Risk review → pre-registration checks → Arena registration

## Non-Negotiable Rules
1. All strategies implement TradeSignal + RiskInterface
2. Position size never >5% of portfolio
3. Domain layering: Types → Config → Repo → Service → Runtime → UI
4. Error messages include what/why/how
5. "If it's not in the repo, it doesn't exist"

## Domain Knowledge
See `.canon/skills/` for prediction market concepts, strategy patterns,
risk management, and platform-specific knowledge.
```

**What this replaces from Plan A → and what it adds:**

| Plan A | Alternative B | Shared logic? |
|--------|--------------|---------------|
| VS Code fork setup | Canon MCP Server (tools layer) | Yes — MCP tools wrap same domain logic |
| Conductor Agent (Kilo Code) | Agent Personas + Orchestration config | Yes — same agent roles |
| IDE-embedded domain knowledge | Skills (`.canon/skills/`) | Yes — skills become IDE tooltips in Phase II |
| IDE-guided workflows | Workflows (`.canon/workflows/`) | Yes — workflows become IDE wizard flows in Phase II |
| IDE ↔ Arena sync | `canon_register` MCP tool | Yes — same registration pipeline |
| *(not in Plan A)* | Domain skills (8 modules) — structured for agent consumption | New |
| *(not in Plan A)* | Agent personas (6 roles) — specialized agent behavior | New |
| *(not in Plan A)* | Structured workflows (5 sequences) — handoff protocols | New |
| *(not in Plan A)* | `canon_help` tool — contextual guidance | New |
| *(not in Plan A)* | `canon_activity` tool — execution observability via MCP (local ↔ cloud) | New |
| *(not in Plan A)* | Standards injection — rules auto-loaded into every interaction | New |

---

### Feature 3: Simplified Ralph Loop

**Reference Implementation:** Auto-Claude's `qa/loop.py` — simplified for Phase I.

**Phase I Architecture — Three-Layer Split:**

The SAS defines the Ralph Loop as an **orchestration pattern that sits above the agent** — it spawns fresh agent instances, checks results, and decides whether to iterate ([SAS_Cross_Model_Architecture.md](./specs/SAS_Cross_Model_Architecture.md)). An MCP tool cannot orchestrate the agent that called it — it returns results and the agent decides what to do. This means the Ralph Loop is **not a single MCP tool** but a system of three cooperating layers:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    RALPH LOOP — THREE-LAYER ARCHITECTURE                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  LAYER 1: HOST HOOKS (the looping legs)                              │   │
│  │  .canon/hooks/{agent-host}/                                          │   │
│  │                                                                      │   │
│  │  • Intercepts agent exit → checks if criteria are met                │   │
│  │  • If not met → redirects agent back into iteration                  │   │
│  │  • Host-specific: Claude Code hooks, Cursor rules, OpenCode hooks    │   │
│  │  • Scaffolded by canon_init per detected agent host                  │   │
│  │  • This is where "keep going until done" lives                       │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  LAYER 2: CANON_RALPH MCP TOOL (the checking brain)                  │   │
│  │                                                                      │   │
│  │  • Runs success criteria (tests, lint, types, custom checks)         │   │
│  │  • Returns structured pass/fail per criterion                        │   │
│  │  • Tracks iteration count and budget spent                           │   │
│  │  • Provides diagnostic feedback for next iteration                   │   │
│  │  • Enforces budget limits (rejects if exceeded)                      │   │
│  │  • Does NOT control the loop — returns results to the agent          │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  LAYER 3: CONFIGURATION (.canon/ralph.yaml)                          │   │
│  │                                                                      │   │
│  │  • Success criteria definitions                                      │   │
│  │  • Budget limits (tokens, spend)                                     │   │
│  │  • Max iterations                                                    │   │
│  │  • Escalation policy (human vs abort)                                │   │
│  │  • Read by both MCP tool and host hooks                              │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  FLOW:                                                                       │
│  Agent works → calls canon_ralph("check") → gets pass/fail + feedback →     │
│  Agent attempts exit → Host hook intercepts → reads ralph.yaml →            │
│  Criteria not met? → Redirects agent back with feedback → Agent iterates    │
│  Criteria met? → Agent exits (SHIP)                                         │
│                                                                              │
│  WHY THIS SPLIT:                                                             │
│  An MCP tool is invoked BY the agent — it can't control the agent.          │
│  Host hooks sit ABOVE the agent — they can intercept exit and redirect.     │
│  The user experiences one cohesive system; the split is internal.            │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

> ⚠️ **SAS Alignment Note:** The full SAS Ralph Loop operates at the **process level** — spawning fresh agent instances in isolated worktrees with cross-model review gates (Codex codes → Claude reviews). Phase I simplifies to single-agent, single-session iteration. Fresh context per iteration and cross-model review are Phase II features that require the worktree infrastructure and tri-provider orchestration layer. See [§ Phase II: Advanced Ralph Loop](#advanced-ralph-loop).

**Phase I scope — all three layers ship as part of the Agent Framework:**

| Component | Layer | Description | Priority |
|-----------|-------|-------------|----------|
| **Host continuation hooks** | Host Hooks | Intercept agent exit, check criteria via `canon_ralph`, redirect if not met — scaffolded per agent host by `canon_init` | P0 |
| **`canon_ralph` MCP tool** | MCP (checking) | Run success criteria, return structured pass/fail + diagnostic feedback + iteration state | P0 |
| **Success criteria config** | Configuration | `.canon/ralph.yaml` — tests pass, lint clean, types valid, custom checks | P0 |
| **Budget controls** | MCP + Config | Token limits, spend caps — `canon_ralph` enforces, `ralph.yaml` defines | P0 |
| **Escalate to human** | Host Hooks | When stuck or budget exceeded, hook stops redirecting and surfaces escalation | P0 |
| **Host hook scaffolding** | Framework | `canon_init` detects agent host and scaffolds appropriate hook scripts into `.canon/hooks/` | P0 |

**Interfaces:**

```typescript
// Configuration (read from .canon/ralph.yaml)
interface RalphLoopConfig {
  success_criteria: SuccessCriterion[];
  max_iterations: number;
  budget: {
    max_tokens: number;
    max_spend: string;
  };
  on_stuck: "escalate_to_human" | "abort";
}

type SuccessCriterion = 
  | "tests_pass"
  | "lint_clean"
  | "types_valid"
  | { custom: string };

// MCP tool response (what canon_ralph returns to the agent)
interface RalphCheckResult {
  action: "check" | "status" | "init";
  iteration: number;
  criteria_results: {
    criterion: string;
    passed: boolean;
    diagnostic: string;    // What failed, why, how to fix
  }[];
  all_passed: boolean;
  budget_remaining: {
    tokens: number;
    spend: string;
  };
  should_continue: boolean;  // false if budget exhausted or max iterations hit
  feedback_summary: string;  // Formatted guidance for the next iteration
}
```

**Configuration:**

```yaml
# .canon/ralph.yaml (Phase I - simplified)
ralph_loop:
  success_criteria:
    - tests_pass
    - lint_clean
    
  max_iterations: 20
  
  budget:
    max_tokens: 200000
    max_spend: "$5.00"
    
  on_stuck: escalate_to_human
  
  # Shell command run by canon_ralph to evaluate criteria
  check_command: |
    npm test && npm run lint
```

**Host hook example (Claude Code):**

```bash
#!/bin/bash
# .canon/hooks/claude-code/ralph-stop-hook.sh
# Installed as a Claude Code PostToolUse hook
# Intercepts agent exit attempts and checks ralph.yaml criteria

RALPH_CONFIG=".canon/ralph.yaml"
RALPH_STATE=".canon/.ralph-state.json"

# Read current iteration from state file
ITERATION=$(jq -r '.iteration // 0' "$RALPH_STATE" 2>/dev/null || echo 0)
MAX_ITERATIONS=$(yq -r '.ralph_loop.max_iterations // 20' "$RALPH_CONFIG")

if [ "$ITERATION" -ge "$MAX_ITERATIONS" ]; then
  echo "Ralph Loop: max iterations ($MAX_ITERATIONS) reached — escalating to human"
  exit 0  # Allow agent to exit
fi

# Run check command from ralph.yaml
CHECK_CMD=$(yq -r '.ralph_loop.check_command' "$RALPH_CONFIG")
if eval "$CHECK_CMD" > /dev/null 2>&1; then
  echo "Ralph Loop: all criteria pass — SHIP"
  exit 0  # Allow agent to exit
else
  echo "Ralph Loop: criteria not met (iteration $ITERATION/$MAX_ITERATIONS) — continuing"
  # Increment iteration
  jq ".iteration = $(($ITERATION + 1))" "$RALPH_STATE" > "$RALPH_STATE.tmp" && mv "$RALPH_STATE.tmp" "$RALPH_STATE"
  exit 1  # Block agent exit — redirect back into iteration
fi
```

> 📄 **Full Ralph Loop Spec:** [SAS_AIDD_Pipeline.md](./specs/SAS_AIDD_Pipeline.md)  
> 📄 **Cross-Model Architecture:** [SAS_Cross_Model_Architecture.md](./specs/SAS_Cross_Model_Architecture.md) — Ralph Loop reference implementation, why the loop sits above the agent  
> 📄 **Error Mitigation Patterns:** [Canon_SAS.md § Error Mitigation](./Canon_SAS.md#error-mitigation--debugging-patterns)

---

### Feature 4: Prediction Market Adapter (via pmxt)

> **DRY NOTE:** Canon uses [pmxt](https://github.com/pmxt-dev/pmxt) ("CCXT for prediction markets") as its unified exchange layer. See Plan A for full specification.

| Component | Description | Priority |
|-----------|-------------|----------|
| **Market data** | Real-time odds, market lists, categories (via pmxt `fetchMarkets`, `fetchEvents`) | P0 |
| **Position tracking** | Current positions, P&L (via pmxt `fetchPositions`, `fetchBalance`) | P0 |
| **Basic execution** | Buy/sell orders (via pmxt `createOrder`, `cancelOrder`) | P0 |
| **Historical data** | Past market results (via pmxt `fetchOHLCV`, `fetchTrades`) | P1 |
| **WebSocket streaming** | Real-time order book and trade updates (via pmxt `watchOrderBook`, `watchTrades`) | P1 |

---

### Feature 5: Starter Templates (10 Pre-Built Strategies)

| Template | Description | Use Case |
|----------|-------------|----------|
| **odds-monitor** | Real-time Polymarket odds tracking | Price movements |
| **bracket-builder** | NBA Playoffs bracket optimizer | Sports predictions |
| **simple-strategy** | Basic buy/sell logic scaffold | Learning |
| **momentum-trader** | Buy/sell based on odds velocity | Trend following |
| **arbitrage-scanner** | Cross-market price discrepancy detection | Arbitrage |
| **news-sentiment** | AI-powered news analysis → position signals | Event-driven |
| **portfolio-rebalancer** | Automated position sizing and rebalancing | Risk management |
| **contrarian-fade** | Counter-trade high-conviction public positions | Mean reversion |
| **volatility-harvester** | Profit from odds swings regardless of direction | Volatility |
| **multi-market-basket** | Correlated position across related markets | Diversification |

**Scaffolding example:**

```
User in Claude Code: "Initialize a new momentum trading strategy"

Claude Code invokes canon_init with template: "momentum-trader"

→ Scaffolds complete project:
  my-momentum-strategy/
  ├── src/
  │   ├── strategy.ts        # Strategy logic (pre-filled)
  │   ├── types/
  │   │   ├── TradeSignal.ts  # Standard output interface
  │   │   └── RiskInterface.ts
  │   └── index.ts
  ├── .canon/
  │   ├── ralph.yaml          # Ralph Loop config (criteria, budget)
  │   ├── execution/          # Structured execution data (trades, decisions, signals)
  │   │   └── .gitkeep        # canon_activity reads from here locally; cloud writes to API
  │   └── hooks/              # Host-specific Ralph continuation hooks
  │       └── claude-code/    # (auto-detected host; others scaffolded on request)
  │           └── ralph-stop-hook.sh
  ├── AGENTS.md               # Agent instructions
  ├── package.json
  └── README.md
```

---

### Feature 6: Execution Reliability & Hardening

Per [Inversion Thinking](./Canon_Inversion_Thinking.md), execution reliability is the #1 trust-builder. Load testing and circuit breakers are elevated to P0 — engineering time freed from the deferred fork is invested here.

| Component | Description | Priority |
|-----------|-------------|----------|
| **Trade execution test suite** | End-to-end tests for every order path (buy/sell/cancel) | P0 |
| **Retry & error recovery** | Graceful handling of failed transactions, network timeouts | P0 |
| **Position reconciliation** | Verify Arena's tracked data matches Polymarket state | P0 |
| **Execution monitoring** | Real-time alerts for failed or stuck trades | P0 |
| **Load testing harness** | Simulate 200+ concurrent strategies executing trades | P0 |
| **Failsafe circuit breakers** | Auto-halt execution if error rate exceeds threshold | P0 |

---

### Feature 7: Cloud Execution Service (Production-Grade — First Paid Feature)

Canon's first monetization hook **and** the infrastructure that must scale to 500+ concurrent strategies between the NBA Playoffs hackathon (April 19) and the FIFA World Cup (June 11). During the hackathon, participants run strategies locally. The moment the hackathon ends, profitable strategies convert to always-on cloud execution — and 10 days later, World Cup prediction markets explode in volume. The infrastructure must be **built, tested, and proven** before the hackathon ends.

This is separate from Arena. Arena is a tracking dashboard that monitors Polymarket accounts. The Cloud Execution Service is infrastructure that *runs* strategies against Polymarket on the user's behalf. Arena displays the results.

**Why this must be production-grade from Day 1:**

1. **The conversion window is 10 days.** Hackathon ends ~June 1. World Cup starts June 11. Developers whose strategies made money during NBA Playoffs want them running on World Cup markets immediately. There is no time to stand up infrastructure after the fact.
2. **Strategies manage real money.** A crash that loses position state means lost funds. Persistent containers with auto-restart and exchange reconciliation are trust requirements, not luxuries.
3. **Isolation is non-negotiable.** One user's buggy strategy cannot crash another user's profitable one. Per-user Machines are the minimum viable isolation model.
4. **Real infrastructure cost justifies the price.** Running a strategy 24/7 in a persistent container with crash recovery costs compute, storage, and monitoring. The price is justified, not artificial.
5. **Highest-intent conversion moment.** A hackathon participant whose strategy *made money* is the most motivated buyer imaginable: "Keep it running for $29/mo."

**Architecture** (aligned with [SAS_Deployment.md](./specs/SAS_Deployment.md)):

```
┌─────────────────────────────────────────────────────────────────────────────┐
│          CLOUD EXECUTION SERVICE — FLY.IO MACHINES ARCHITECTURE              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  COMPUTE: FLY.IO MACHINES (persistent Docker containers)                     │
│  ───────────────────────────────────────────────────────                     │
│  • Per-user isolated Machines (one strategy crash ≠ another's problem)      │
│  • Persistent — containers stay running 24/7, not ephemeral/serverless     │
│  • Auto-restart on crash (Fly.io built-in, no external supervisor)          │
│  • Persistent volumes for decision history, signal cache, execution logs    │
│  • Pre-built Docker images (pmxt + deps baked in, fast deploy)              │
│  • Multi-region capable (us-east, eu-west, ap-southeast)                    │
│  • Low ops burden (no Kubernetes cluster management)                        │
│                                                                              │
│  SESSION COORDINATION (Phase I): ARENA BACKEND HANDLES DIRECTLY             │
│  ──────────────────────────────────────────────────────────────              │
│  • Strategies push events to Arena backend API via HTTP                     │
│  • Arena fans out to browser clients via WebSocket                          │
│  • At 500-user Phase I scale, no separate coordination layer needed        │
│  • Phase II scaling upgrade: Cloudflare Durable Objects if/when             │
│    Arena WebSocket fanout hits limits at 5,000+ users                       │
│                                                                              │
│  STATE PERSISTENCE: FLY.IO PERSISTENT VOLUMES                                │
│  ────────────────────────────────────────────                                │
│  • Decision history (what the strategy decided and why)                     │
│  • Signal cache (recent market signals for continuity)                      │
│  • Execution logs (full audit trail)                                        │
│  • Survives container restarts — no snapshot/restore needed                 │
│                                                                              │
│  CRASH RECOVERY: AUTO-RESTART + EXCHANGE RECONCILIATION                      │
│  ──────────────────────────────────────────────────────                      │
│  ON RESTART → Fly.io auto-restarts the Machine                              │
│            → Strategy calls pmxt: fetchPositions(), fetchOpenOrders(),       │
│              fetchBalance() to reconcile against Polymarket (source of       │
│              truth for positions)                                            │
│            → Reads decision history + signal cache from persistent volume   │
│            → Re-establishes WebSocket subscriptions to market data          │
│            → Resumes strategy execution                                     │
│                                                                              │
│  LIFECYCLE:                                                                  │
│  ──────────                                                                  │
│  PROVISION → Deploy pre-built Docker image to new Fly.io Machine            │
│            → Attach persistent volume for user's state                      │
│            → Start strategy execution                                       │
│                                                                              │
│  ACTIVE   → Strategy executing in persistent container                      │
│           → Events pushed to Arena backend API (HTTP)                       │
│           → State written to persistent volume continuously                 │
│                                                                              │
│  PAUSE    → Stop Machine (persistent volume retained)                       │
│  RESUME   → Start Machine → exchange reconciliation → resume               │
│                                                                              │
│  TERMINATE → Stop Machine → export logs → release volume (if requested)     │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Phase I scope (production-grade — ready for post-hackathon scale):**

| Component | Description | Priority |
|-----------|-------------|----------|
| **Fly.io Machine provisioning** | Per-user persistent containers with strategy execution; pre-built Docker images with Node.js + pmxt pre-installed | P0 |
| **Persistent volumes** | Per-user volumes for decision history, signal cache, execution logs; survives restarts | P0 |
| **Crash recovery (exchange reconciliation)** | Auto-restart → pmxt `fetchPositions()`, `fetchOpenOrders()`, `fetchBalance()` → re-establish WebSocket subscriptions → resume | P0 |
| **Arena event integration** | Strategies push events (live P&L, trade events, health) to Arena backend API via HTTP; Arena fans out via WebSocket | P0 |
| **Session lifecycle** | Full provision → active → pause → resume → terminate flow with command queuing | P0 |
| **Strategy hosting** | Run registered strategies on Canon's infrastructure (server-side execution against Polymarket) | P0 |
| **Free trial period** | Strategies run free during hackathon; free period expires post-hackathon | P1 |
| **Expiration + pause** | `strategy.expires_at` field; cron pauses expired strategies with notification | P1 |
| **Stripe checkout** | Payment link: $29/mo "early access" to keep strategy running | P1 |
| **Usage dashboard** | Strategy status (running/paused/expired), uptime, next billing date | P1 |
| **Load testing at 500+ Machines** | Verify isolation, performance, and cost at target concurrency | P0 |

**Phase II scope (advanced features) — see [§ Phase II: Cloud Execution Service](#cloud-execution-service-advanced):**

| Component | Description |
|-----------|-------------|
| **Scheduled runs** | Cron-based strategy execution (run every hour, daily, on market events) |
| **Event-driven triggers** | Execute strategy when specific market conditions are met (odds threshold, volume spike) |
| **Inngest integration** | Evaluate durable step functions for multi-step trade execution and event-driven fan-out |
| **Multi-strategy orchestration** | Run portfolio of strategies with shared risk limits |
| **Execution dashboard (advanced)** | Detailed view: logs, execution history, cost tracking, error rates per Machine |
| **Multiplayer sessions** | Multiple team members monitoring/adjusting the same running strategy |
| **Cloudflare Durable Objects** | Session coordination scaling upgrade if/when Arena WebSocket fanout hits limits at 5,000+ users |

**Pricing:**

| Tier | Price | Included | When |
|------|-------|----------|------|
| **Hackathon** | Free | Strategy runs during hackathon period | Apr 19 – Jun 1 |
| **Early Access** | $29/mo | 1 always-on strategy, persistent container, crash recovery, basic monitoring | Post-hackathon |
| **Pro** (Phase II) | $49/mo | 3 strategies, scheduled runs, priority execution | Phase II |
| **Elite** (Phase II) | $249/mo | Unlimited strategies, priority data, advanced analytics | Phase II |

> 📄 **Revenue Model:** [PV_Revenue_Model.md](./specs/PV_Revenue_Model.md)  
> 📄 **Cloud Architecture:** [SAS_Deployment.md](./specs/SAS_Deployment.md) — Fly.io Machines architecture, persistent volumes, ML infrastructure  
> 📄 **Reference Patterns:** [SAS_Orchestration_References.md § Ramp Inspect](./specs/SAS_Orchestration_References.md#ramp-inspect-cloud-execution-infrastructure--conceptual-influence) — conceptual influence for image pre-building patterns  
> **Relationship to Arena:** Arena tracks and displays performance. Cloud Execution Service runs the strategy. Users can run locally (free) and still appear on Arena — cloud execution is a convenience/reliability upgrade, not a tracking requirement.

---

## Phase I Supporting Infrastructure

### Harness Engineering Patterns[^harness-eng][^harness-factory]

| Pattern | Phase I Application | Priority |
|---------|---------------------|----------|
| **Core Operating Principles** | "If it's not in the repo, it doesn't exist" / Favor boring technology / Rigid architecture early | P0 |
| **AGENTS.md as Table of Contents** | `AGENTS.md` stays ~100 lines — a map, not a manual | P0 |
| **Structured `docs/` Knowledge Base** | `docs/` layout with `design-docs/`, `exec-plans/`, `product-specs/`, `references/` | P1 |
| **Agent-Oriented Error Messages** | All custom lints include *what/why/how* | P0 |
| **Rigid Domain Layering** | Enforce `Types → Config → Repo → Service → Runtime → UI` | P0 |
| **Runtime Bridge / Application Legibility** | App-per-worktree, console streaming, DOM snapshots | P1 |

### Resource Governance

```yaml
# .canon/resource-governance.yaml (Phase I - simplified)
budget:
  max_api_spend_per_task: "$5.00"
  max_llm_tokens_per_task: 200000

circuit_breakers:
  consecutive_test_failures: 5
  idle_timeout_minutes: 30
```

### Basic Auth + User Accounts

| Component | Description | Priority |
|-----------|-------------|----------|
| **User registration** | Email/password or OAuth | P0 |
| **Strategy ownership** | Link strategies to users | P0 |
| **Basic profile** | Username, avatar for leaderboard | P0 |

---

## Phase I Build Schedule (~7 Weeks)

### Week 1-2: Foundation (Feb 17 – Mar 2)

| Task | Owner | Deliverable |
|------|-------|-------------|
| **Canon MCP Server scaffold** | Core | MCP server with `canon_init`, `canon_market`, `canon_help` tools working |
| **Agent Framework foundation** | Core | `.canon/` directory structure, `config.yaml` schema, 4 core skills (prediction-markets, risk-management, canon-conventions, polymarket), 3 core agent personas (dev, strategy-architect, risk-analyst) |
| **Simplified Ralph Loop** | Core | `canon_ralph` MCP tool (check/status/init) + host continuation hooks for Claude Code; `.canon/ralph.yaml` config |
| Claude Code integration | Core | MCP server connected, AGENTS.md configured, framework artifacts loadable |
| **Arena UI scaffold** | Frontend | Fork template, apply Canon branding |
| Basic auth system | Backend | User registration, accounts |
| **Domain layering + `docs/` structure** | Core | Enforce `Types→Config→Repo→Service→Runtime→UI`; set up `AGENTS.md` TOC + `docs/` knowledge base[^harness-eng] |

**Milestone:** MCP server running with basic tools. Agent Framework foundation in place — dev agent persona + core skills loading correctly. Claude Code can scaffold a strategy (with `.canon/` included) and query market data. Arena shell is live with placeholder UI. Domain layering enforced from first commit.

### Week 3-4: Arena Core + Cloud Execution Foundation (Mar 3 – Mar 16)

| Task | Owner | Deliverable |
|------|-------|-------------|
| **pmxt integration** | Core | Market data + execution via pmxt unified API, exposed through MCP tools |
| **Arena backend** | Backend | Polymarket account tracking + performance monitoring integration |
| **Strategy registration** (`canon_register`) | Backend | Register strategies from Agent Framework → Arena for tracking |
| **Leaderboard system** | Backend | Ranking by P&L, win rate, ROI |
| Ralph Loop polish | Core | Budget controls, escalation, `canon_ralph` MCP tool (check/status/init), host hook scripts for OpenCode + Cursor |
| **Agent Framework: remaining skills + personas** | Core | Remaining 4 skills (strategy-patterns, backtesting, arena-tracking, ralph-loop), remaining 3 personas (market-analyst, qa, deployment-ops), 3 core workflows (discover, develop, register) |
| **`canon_help` implementation** | Core | Contextual guidance tool reads `.canon/config.yaml` and recommends agents/skills/workflows |
| **Agent-oriented linters** | Core | Custom lints with *what/why/how* error messages[^harness-eng] |
| **Execution: trade test suite** | Backend | End-to-end tests for every order path (buy/sell/cancel) |
| **Fly.io Machine provisioning** | Infra | Per-user persistent containers running; pre-built Docker image pipeline for `node:20-slim` + pmxt; basic provision → active → terminate lifecycle; persistent volumes attached |
| **Arena event integration scaffold** | Infra | Strategies push events to Arena backend API via HTTP; Arena fans out to browser clients via WebSocket |

**Milestone:** Can register strategy on Arena via `canon_register` and see it on leaderboard. Full Agent Framework in place — all 6 personas, 8 skills, and core workflows operational. `canon_help` provides contextual guidance. Ralph Loop works for basic tasks. Trade execution tested end-to-end. Fly.io Machines provisioning and executing a test strategy in isolation. Arena receiving strategy events via HTTP and streaming to clients.

### Week 5-6: Integration + Cloud Execution Hardening (Mar 17 – Mar 30)

| Task | Owner | Deliverable |
|------|-------|-------------|
| **Arena portfolio tracking** | Frontend | Real-time P&L, positions |
| **MCP ↔ Arena sync** | Core | Seamless strategy registration via MCP tools + tracking workflow |
| **Agent Framework: remaining workflows** | Core | ralph-cycle and quick-dev workflows; integration testing: framework + MCP + Arena tracking end-to-end |
| **Execution: retry & recovery** | Backend | Graceful handling of failed transactions, network timeouts |
| **Execution: position reconciliation** | Backend | Verify Arena's tracked data matches Polymarket state |
| **Execution: monitoring & alerts** | Backend | Real-time alerts for failed or stuck trades |
| **Execution: load testing** | Backend | Simulate 200+ concurrent strategies |
| **Execution: circuit breakers** | Backend | Auto-halt on error threshold |
| **Runtime Bridge (minimal)** | Core | App-per-worktree + console error streaming[^harness-eng] |
| Starter templates | Content | 10 pre-built strategy templates |
| **Crash recovery (exchange reconciliation)** | Infra | Auto-restart → pmxt `fetchPositions()`, `fetchOpenOrders()`, `fetchBalance()` → re-establish WebSocket subscriptions → resume; tested with simulated crashes |
| **Persistent volume state management** | Infra | Decision history, signal cache, execution logs written to Fly.io persistent volumes; survives restarts; validated under crash scenarios |
| **Full session lifecycle** | Infra | Provision → active → pause → resume → terminate with command queuing; Arena event integration (strategies push live P&L, trade events, health to Arena backend API) |
| **Cloud execution end-to-end** | Infra | Full flow: `canon_register` → Fly.io Machine provisioned → strategy executing → Arena displaying live data via event push → pause/resume working |

**Milestone:** Full Agent Framework + Arena integration working end-to-end. Trade execution hardened with retry, reconciliation, monitoring, load testing, and circuit breakers. Cloud Execution Service functional: strategies running in persistent Fly.io Machines with exchange reconciliation crash recovery and real-time event streaming to Arena. Ready for beta testing.

### Week 7: Developer Experience (Mar 31 – Apr 4)

| Task | Owner | Deliverable |
|------|-------|-------------|
| **Developer quickstart guide** | Docs | Install → scaffold → register in <15 minutes |
| **Video walkthrough** | Marketing | Screen recording: Claude Code + Canon MCP → Arena registration + tracking |
| **OpenCode integration** | Core | Verify MCP server + Agent Framework works with OpenCode |
| **Cursor integration** | Core | Verify MCP server + Agent Framework works with Cursor |
| **Agent Framework polish** | Core | Iterate on skills and personas based on internal dogfooding; refine `canon_help` responses |
| **End-to-end smoke test** | QA | Full flow: scaffold → build → test → register → Arena tracking |
| **Hackathon onboarding flow** | Docs | Step-by-step guide for hackathon Day 1 |
| Bug fixes | All | Stability pass |

**Milestone:** Developer experience polished. Quickstart guide lets participants go from zero to registered strategy in <15 minutes. MCP server verified across Claude Code, OpenCode, and Cursor.

### Buffer Period (Apr 5 – Apr 18)

| Task | Owner | Deliverable |
|------|-------|-------------|
| Internal beta testing | All | Canon team uses Agent Framework with real strategies |
| Early access invites | Marketing | 20-30 beta users stress test |
| **Execution stress testing** | QA | Verify zero lost orders under 200+ concurrent strategy load |
| **Load testing** | QA | Verify 150+ concurrent users on Arena leaderboard |
| **MCP server stability** | Core | Verify MCP server handles concurrent connections reliably |
| **Cloud execution load testing** | Infra | Verify 500+ concurrent isolated Fly.io Machines; test crash recovery under load; validate exchange reconciliation with open positions; measure restart-to-resume latency |
| **Stripe checkout + expiration** | Backend | Payment link ($29/mo early access); `strategy.expires_at` + cron pause + notification |
| **Cloud execution chaos testing** | Infra | Simulated Machine crashes with position recovery via exchange reconciliation; network partition handling; verify zero lost state under failure scenarios |
| Video tutorials | Marketing | Onboarding content |
| Final bug fixes | All | Critical issues resolved |

**Milestone:** Arena and Agent Framework battle-tested and ready for 150+ participants. Execution layer proven under load with zero lost trades. Cloud Execution Service proven at 500+ concurrent Fly.io Machines with exchange reconciliation crash recovery and real-time event streaming. Payment flow ready to activate post-hackathon.

---

## Phase II Features: Post-Hackathon (June–July 2026)

### Canon IDE (VS Code Fork)

The fork is built with real data from the hackathon — which tools were used most, where onboarding broke, what workflows need visual UI. The MCP Server built in Phase I becomes the IDE's backend — it wraps MCP tools in visual UI without replacing the business logic.

| Component | Description |
|-----------|-------------|
| **VS Code fork setup** | Bootable Canon IDE with Canon branding |
| **Conductor Agent (Kilo Code)** | Primary user interface agent for IDE operations |
| **MCP Server → IDE integration** | Canon MCP tools become native IDE commands |
| **Arena registration UI** | One-click register from IDE to Arena for tracking (wraps `canon_register`) |
| **Ralph Loop UI** | Visual status, iteration history, budget tracking |
| **Strategy builder UI** | Visual scaffolding, template browser |
| **Non-dev onboarding** | Guided workflows for non-developer users |

### Marketplace with x402 Payments

| Component | Description |
|-----------|-------------|
| **Listing system** | Project metadata, description, pricing, category |
| **x402 integration** | One-time purchase + subscription support |
| **Creator dashboard** | Earnings, downloads, analytics |
| **Fork/remix** | One-click copy with attribution |
| **Discovery** | Categories, search, featured projects |

> 📄 **Revenue Model:** [PV_Revenue_Model.md](./specs/PV_Revenue_Model.md)

### Composable Blueprints

| Component | Description |
|-----------|-------------|
| **Blueprint manifest** | YAML format for workflow definition |
| **Visual wiring UI** | Connect agents visually (requires IDE) |
| **Agent pipelines** | Data → Strategy → Execution flows |
| **Publish to marketplace** | Convert blueprint to listing |

### Advanced Ralph Loop

Phase I ships the simplified Ralph Loop (single-agent, single-session, automated checks only). Phase II completes the SAS-specified architecture:

| Component | Description | Why Phase II |
|-----------|-------------|--------------|
| **Fresh context per iteration** | Each iteration spawns a new agent instance with clean context (SAS core principle) | Requires worktree infrastructure |
| **Cross-model review gate** | Claude reviews Codex's code with blocking SHIP/NEEDS_WORK verdict — different model families catch different blind spots ("self-testing is self-consistency, not falsification"[^flow-next]) | Requires tri-provider orchestration layer |
| **Multi-agent adapters** | Open Code (via ACP), custom agents via AgentAdapter | Requires AgentAdapter protocol |
| **DAG decomposition** | Architect Agent for task breakdown | Requires Architect Agent + Local PR system |
| **Spiral detection** | Circuit breakers to prevent debugging loops | Requires iteration history analysis across fresh-context sessions |
| **Continuation tokens** | Session persistence across fresh-context iterations | Requires memory layer integration |
| **Local PR System** | Worktree-based parallel development | Requires git worktree management (Open Trees) |

> 📄 **Cross-Model Architecture:** [SAS_Cross_Model_Architecture.md](./specs/SAS_Cross_Model_Architecture.md) — tri-provider model, blocking review gate, flow-next reference

### Cloud Execution Service (Advanced)

Phase I ships production-grade cloud execution on Fly.io Machines (persistent containers, exchange reconciliation crash recovery, persistent volumes, event streaming to Arena, Stripe billing). Phase II adds advanced orchestration features:

| Component | Description |
|-----------|-------------|
| **Scheduled runs** | Cron-based strategy execution — run hourly, daily, or on market events |
| **Event-driven triggers** | Execute strategy when specific market conditions are met (odds threshold, volume spike); evaluate Inngest for durable step functions |
| **Multi-strategy orchestration** | Run portfolio of strategies with shared risk limits |
| **Execution dashboard (advanced)** | Detailed view: logs, execution history, cost tracking, error rates per Machine |
| **Multiplayer sessions** | Multiple team members monitoring/adjusting the same running strategy with per-user attribution |
| **Cloudflare Durable Objects** | Session coordination scaling upgrade if/when Arena WebSocket fanout hits limits at 5,000+ users |
| **Kubernetes migration evaluation** | Assess migration triggers (>100 concurrent Machines, multi-region, GPU scheduling) per [SAS_Deployment.md](./specs/SAS_Deployment.md) |

> 📄 **Inngest Evaluation:** [SAS_Orchestration_References.md](./specs/SAS_Orchestration_References.md) — durable workflow engine candidate for event-driven fan-out and multi-step trade execution  
> **Relationship to Arena:** Arena displays performance data from cloud-executed strategies. The execution service is the infrastructure; Arena is the dashboard.

### Arena v2 Features

| Component | Description |
|-----------|-------------|
| **Copy/Counter trading** | Mirror or fade strategies |
| **AI Decision Feed** | Stream of automation reasoning |
| **Social features** | Follow, comments, notifications |
| **Referral codes** | Viral growth mechanics |

### Collaboration Layer

| Component | Description |
|-----------|-------------|
| **Teams** | Create teams, shared access, invite by username/email |
| **Direct Messages** | 1:1 private chat |
| **Team Channels** | Team-wide discussion |
| **Project Channels** | Chat tied to specific projects |
| **Presence indicators** | Online/away/busy status |
| **Roles & permissions** | Owner/admin/member hierarchy |
| **Project sharing** | Visibility controls, share links, forking |
| **AI agents in channels** | `@RiskAgent what's our exposure?` |

> 📄 **Full Collaboration Spec:** [SAS_UI_Collaboration.md § Collaboration Layer](./specs/SAS_UI_Collaboration.md#collaboration-layer)

### Codebase Entropy Management[^harness-eng]

| Component | Description |
|-----------|-------------|
| **Doc-Gardening Agent** | Daily scan for stale docs, broken links, orphaned plans |
| **Code Gardening Agent** | Daily scan for golden principle deviations |
| **Golden Principles config** | `.canon/golden-principles.yaml` |
| **Quality score tracking** | `docs/QUALITY_SCORE.md` |

### Deferred Beyond Phase II

| Feature | Reason |
|---------|--------|
| **AI-to-AI Social Learning** | High complexity, requires established user base |
| **System Flow Visualizer** | UX polish, not core functionality |
| **Graph Memory (Cognee)** | Post-PMF optimization |
| **Full Multi-Agent Ecology** | Progressive rollout after single-agent proven |

---

## Phase II Build Schedule (June–July 2026)

### June 2026: Canon IDE + Marketplace

| Task | Owner | Deliverable |
|------|-------|-------------|
| **VS Code fork setup** | Core | Bootable Canon IDE |
| **Conductor Agent (Kilo Code)** | Core | IDE operations agent |
| **MCP → IDE integration** | Core | MCP tools as native IDE commands |
| **Arena registration UI** | Frontend | One-click register from IDE |
| Marketplace backend | Backend | Listings, search, creator accounts |
| x402 integration | Backend | Payments working |
| Fork/remix flow | Frontend | One-click fork to workspace |
| Creator dashboard | Frontend | Earnings, downloads, analytics |
| Referral code system | Backend | Viral growth mechanics |

**Milestone:** Canon IDE live. Marketplace live. Hackathon projects can be monetized.

### July 2026: Advanced Features

| Task | Owner | Deliverable |
|------|-------|-------------|
| Composable Blueprints | Core | YAML manifest + basic wiring UI |
| Advanced Ralph Loop | Core | DAG decomposition, spiral detection |
| Open Code via AgentAdapter (ACP) | Core | Multi-agent support |
| Copy/Counter trading | Backend | Mirror or fade strategies |
| AI Decision Feed | Backend | Stream automation reasoning |
| Local PR System | Core | Worktree-based parallel development |
| **Collaboration Layer: MVP** | Backend | Teams, invite, DMs, team channels, presence |
| **Collaboration Layer: Advanced** | Backend | Roles, permissions, project sharing, AI agents in channels |
| **Doc-Gardening Agent**[^harness-eng] | Core | Daily recurring agent: stale docs, broken links |
| **Code Gardening Agent**[^harness-eng] | Core | Daily recurring agent: golden principle deviations |

**Milestone:** Full Canon v1.0 with IDE + marketplace + advanced AI features + collaboration + automated entropy management.

### URL Structure

```
arena.canon.xyz     → Canon Arena (track, monitor, leaderboard)
app.canon.xyz       → Canon IDE (Phase II — build, test, publish)
canon.xyz           → Marketing/landing
```

---

## Success Metrics

### Phase I Launch (April 18)

| Metric | Target |
|--------|--------|
| **Core features working** | 8/8 (Arena, Agent Framework, MCP Server, Ralph Loop, pmxt, Execution Hardening, Templates, Cloud Execution Service) |
| **MCP Server functional** | All 8 tools working (`init`, `register`, `test`, `market`, `position`, `ralph`, `activity`, `help`) |
| **Agent Framework complete** | 19/19 (6 personas + 8 skills + 5 workflows) |
| **Multi-agent verified** | Claude Code + at least one other host (OpenCode or Cursor) |
| **Ralph Loop working** | Three-layer system operational: `canon_ralph` MCP tool (check/status/init) + host continuation hooks + `.canon/ralph.yaml` config |
| **Execution reliability** | Zero lost trades under 200+ concurrent strategy load |
| **Starter templates** | 10 scaffoldable via `canon_init`  |
| **Arena live** | Leaderboard, performance tracking, portfolio monitoring |
| **Cloud Execution Service proven** | 500+ concurrent isolated Fly.io Machines; crash recovery with zero lost state via exchange reconciliation; persistent volumes validated under failure |
| **Cloud → Arena streaming** | Live P&L, trade events, and health checks flowing from strategy Machines to Arena dashboard via event push |
| **Quickstart guide** | Zero to registered strategy in <15 minutes |
| **Open-source repos live** | MCP Server + Agent Framework + templates published under Apache 2.0 |

### Hackathon Launch (April 19)

| Metric | Target |
|--------|--------|
| **Registrations** | 200+ |
| **Strategies registered (Day 1)** | 50+ |
| **Arena leaderboard entries** | 100+ |
| **Real-time tracking** | P&L updates during games |
| **Agent distribution** | Track which agents participants use — informs IDE priorities |
| **GitHub stars** | 100+ on MCP Server repo |

### Hackathon End (~June 1)

| Metric | Target |
|--------|--------|
| **Active participants** | 150+ throughout tournament |
| **Projects submitted** | 50+ |
| **Top strategies ROI** | Track leaderboard data |
| **User feedback** | 50+ surveys/interviews |
| **IDE feature requests** | Collect: what workflows need visual UI? What was painful in terminal? |
| **OSS contributions** | Track external PRs, community-contributed skills/templates |
| **GitHub stars** | 500+ on MCP Server repo |

### Cloud Execution Conversion (Post-Hackathon)

| Metric | Target |
|--------|--------|
| **Cloud execution signups** | 20+ (from hackathon participants whose strategies were profitable) |
| **Conversion rate** | 15%+ of active participants convert to $29/mo |
| **MRR from cloud execution** | $500+ within 30 days of hackathon end |
| **Strategy uptime** | 99.9%+ for cloud-hosted strategies (Fly.io Machine + auto-restart + exchange reconciliation) |
| **Crash recovery** | Zero lost positions on Machine failure; auto-restart + reconciliation <30s |
| **World Cup readiness** | Infrastructure proven at 500+ concurrent strategies before June 11 |

### Post-Hackathon Pipeline (~June 1–30)

Per [Inversion Thinking](./Canon_Inversion_Thinking.md), hackathon projects dying after events is a critical failure mode.

| Metric | Target |
|--------|--------|
| **Winners onboarded to publishing** | 100% of top 10 |
| **"Marketplace Launch" program** | 15+ participants |
| **Content spotlights** | 10+ posts featuring top projects |
| **Alumni retained (Day 30)** | 50%+ |
| **Strategies refined for marketplace** | 10+ |

**Pipeline steps:**
1. **Day 1-3 post-hackathon:** Personal outreach to top 20 projects
2. **Day 3-7:** 1:1 onboarding calls with top 10
3. **Day 7-30:** "Marketplace Launch" cohort
4. **Day 30:** First cohort of marketplace listings goes live with Phase II launch

> ⚠️ **Phase gate:** Marketplace (Phase II) does not launch until Canon has **500+ active developers**.

### Phase II Launch (July 2026)

| Metric | Target |
|--------|--------|
| **Canon IDE live** | Bootable, functional, deployed |
| **Marketplace listings** | 15+ |
| **Paying subscribers** | 50+ |
| **Arena signups (non-hackathon)** | 200+ |
| **Strategies registered** | 100+ |
| **IDE adoption** | Track % of Agent Framework users migrating to IDE |
| **OSS → Arena conversion** | Track funnel: GitHub → MCP install → Arena signup → registered strategy |
| **GitHub stars** | 1,000+ across repos |
| **Community-contributed skills** | 10+ external skills/templates merged |

---

## Risk Register

### Phase I Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **Arena backend delays** | Medium | Critical | Start Week 1, parallelize |
| **Ralph Loop complexity** | Medium | High | Simplified scope for Phase I |
| **Prediction market API changes** | Low | Medium | Abstracted via pmxt |
| **Scope creep** | High | High | Strict Phase I/II separation; defer aggressively |
| **Trade execution failure** | Medium | Critical | Load testing + circuit breakers P0 |
| **~7 weeks too tight** | Low | High | 2-week buffer; fork removal frees ~2-3 weeks |
| **High API Costs (Claude Code)** | Medium | Medium | Budget controls P0; monitor during beta |
| **Leaderboard at scale** | Medium | High | Load test with simulated 200+ strategies |
| **MCP server reliability** | Low | High | Standard server engineering; MCP is a mature protocol |
| **Developer onboarding friction** | Medium | High | Week 7 dedicated to DX; quickstart <15 min |
| **Agent host compatibility** | Low | Medium | Verify across Claude Code, OpenCode, Cursor in Week 7 |
| **OSS community management overhead** | Medium | Medium | Limit scope to issues/PRs on framework repo; Arena is closed source and not community-managed |
| **License selection delay** | Low | High | License is Apache 2.0 for all open-source components; finalize before public repo creation |
| **Competitor forks open-source tools** | Low | Medium | Value is in the Arena platform + execution layer, not in tools alone; competitors forking is acceptable — they cannot replicate the platform moat |
| **Fly.io Machine restart latency** | Low | Medium | Fly.io auto-restart is fast (seconds); exchange reconciliation adds overhead — test full restart-to-resume latency under load |
| **Fly.io vendor lock-in** | Low | Low | Standard Docker containers — portable to any container platform; Kubernetes migration path at >100 concurrent Machines per [SAS_Deployment.md](./specs/SAS_Deployment.md) |
| **Fly.io costs at scale** | Medium | Medium | Persistent Machines have predictable costs (not pay-per-use); monitor cost curve during beta; Kubernetes migration trigger defined in [SAS_Deployment.md](./specs/SAS_Deployment.md) |
| **Persistent volume data loss** | Low | Critical | Polymarket is source of truth for positions — exchange reconciliation via pmxt on every restart; decision history and logs are supplementary, not critical path; chaos testing during buffer period |
| **Cloud infra adds scope to 7-week sprint** | Medium | High | Fly.io Machines are low-ops (Docker deploy, no cluster management); start Week 3 (not Week 1) after foundation is solid; buffer period absorbs overflow |

### Phase II Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **VS Code fork unpredictable** | Medium | High | Hackathon data to scope properly; no time pressure |
| **x402 integration delays** | Medium | High | Stripe fallback ready |
| **Marketplace adoption slow** | Medium | Medium | Hackathon creates initial supply |
| **Advanced features complexity** | Medium | Medium | Progressive rollout |
| **Agent Framework → IDE migration** | Low | Medium | MCP Server business logic is reused |
| **Investor pitch timing** | Medium | Medium | Pitch with hackathon validation data before IDE ships |
| **OSS adoption without Arena conversion** | Medium | Medium | Track funnel: GitHub stars → MCP installs → Arena signups → registered strategies; optimize conversion at each step |
| **Open-source IP perception by investors** | Low | Medium | Open core is proven (HashiCorp $35B, GitLab $34B, Elastic $8.4B); Canon's proprietary moat is Arena + execution + marketplace, not the framework |

---

## Key Integration Points

| Component | How Canon Leverages It | Distribution |
|-----------|----------------------|-------------|
| **Canon Agent Framework** | Structured prompt engineering — agent personas, skills, workflows, orchestration. Inspired by [BMAD Method](https://github.com/bmad-code-org/BMAD-METHOD) and [Agent OS](https://buildermethods.com/agent-os) | **Open source** (Apache 2.0) |
| **Canon MCP Server** | Domain logic exposed as MCP tools — scaffolding, registration, market data, Ralph Loop, positions, help | **Open source** (Apache 2.0) |
| **AgentAdapter interface** | Agent-agnostic orchestration — each agent integrates via its native hook mechanism | **Open source** (Apache 2.0) |
| **Agent personas + Skills** | Markdown-based agent roles and composable knowledge — host-agnostic | **Open source** (Apache 2.0) |
| **Canon Arena** | Leaderboard, performance tracking, portfolio monitoring (tracks Polymarket accounts — no execution infrastructure) | **Proprietary** |
| **Canon IDE** | VS Code fork, Conductor Agent, visual tools (Phase II) | **Proprietary** |
| **Execution Layer** | Trade execution, reconciliation, circuit breakers, monitoring | **Proprietary** |
| **Cloud Execution Service** | Production-grade strategy hosting on Fly.io Machines — per-user persistent containers, auto-restart with exchange reconciliation crash recovery, persistent volumes, event streaming to Arena. Separate from Arena (Arena tracks; this runs). First paid feature ($29/mo). Architecture from [SAS_Deployment.md](./specs/SAS_Deployment.md) | **Proprietary** |
| **Collaboration Layer** | Teams, DMs, channels, project sharing, roles, presence, AI agents in channels | **Proprietary** |
| **Social + AI Decision Feed** | Follow, comments, copy/counter trading, agent reasoning stream | **Proprietary** |
| **AI Ecology** | Multi-agent orchestration, AI-to-AI social learning, Conductor Agent | **Proprietary** |
| **Marketplace** | Listings, x402 payments, creator economics, fork/remix | **Proprietary** |
| **User Infrastructure** | Accounts, auth, profiles, API keys | **Proprietary** |
| **MCP (Model Context Protocol)** | Primary tool integration protocol — consumed by any MCP-compatible host | Open protocol (Anthropic) |
| **Claude Code / OpenCode / Cursor** | Interchangeable agent clients that invoke Canon's MCP tools | Third-party |
| **Fly.io Machines** | Persistent container compute for Cloud Execution Service — per-user isolation, auto-restart, persistent volumes, Docker-based, multi-region capable, low ops burden (Phase 1 compute; Kubernetes Phase 2 per [SAS_Deployment.md](./specs/SAS_Deployment.md)) | Third-party (managed) |
| **LanceDB** | Embedded vector store (semantic search, memory) | Third-party (OSS) |
| **Git worktrees** | Parallel agent isolation | Third-party (OSS) |

> 📄 **Agent Coordination:** [SAS_Agent_Coordination.md](./specs/SAS_Agent_Coordination.md)

---

## References

### Product Vision
- [Canon_Product_Vision.md](./Canon_Product_Vision.md) — Master product vision
- [PV_Product_Overview.md](./specs/PV_Product_Overview.md) — Product capabilities
- [PV_AI_Features.md](./specs/PV_AI_Features.md) — AI ecology, Ralph Loop, Social Learning
- [PV_GTM_Strategy.md](./specs/PV_GTM_Strategy.md) — Go-to-market strategy

### Agent Framework
- [SAS_Agent_Framework.md](./specs/SAS_Agent_Framework.md) — Canon Agent Framework specification
- [BMAD Method](https://github.com/bmad-code-org/BMAD-METHOD) — Reference: agent-as-code patterns, structured workflows
- [Agent OS](https://buildermethods.com/agent-os) — Reference: standards injection, context routing

### Architecture
- [Canon_SAS.md](./Canon_SAS.md) — Software Architecture Specification (master)
- [Canon_SAS.md § Core Operating Principles](./Canon_SAS.md#core-operating-principles) — Three non-negotiable engineering constraints[^harness-eng]
- [Canon_SAS.md § Harness Engineering Patterns](./Canon_SAS.md#agentsmd-as-table-of-contents-not-encyclopedia) — AGENTS.md as TOC, structured `docs/`, Doc-Gardening Agent, Golden Principles, Agent-Oriented Error Messages, Application Legibility[^harness-eng]
- [Canon_SAS.md § Worktree Management](./Canon_SAS.md#worktree-management-open-trees) — Open Trees reference patterns
- [Canon_SAS.md § Error Mitigation](./Canon_SAS.md#error-mitigation--debugging-patterns) — Debugging patterns, spiral prevention
- [SAS_UI_Collaboration.md](./specs/SAS_UI_Collaboration.md) — Figma Model, VS Code modifications, Collaboration Layer
- [SAS_AIDD_Pipeline.md](./specs/SAS_AIDD_Pipeline.md) — Ralph Loop, Local PRs, DAG orchestration
- [SAS_AI_Ecology.md](./specs/SAS_AI_Ecology.md) — Agent types, Data Agent validation
- [SAS_Workflow_Composition.md](./specs/SAS_Workflow_Composition.md) — BOCA pattern, Tick-Based Control
- [SAS_Agent_Coordination.md](./specs/SAS_Agent_Coordination.md) — Resource governance, worktree isolation
- [SAS_Memory_Context.md](./specs/SAS_Memory_Context.md) — LanceDB, persistent memory
- [SAS_Automation_Model.md](./specs/SAS_Automation_Model.md) — Blueprint manifest, build targets

### Roadmap Alternatives
- [Canon_MVP_Technical_Roadmap.md](./Canon_MVP_Technical_Roadmap.md) — **Plan A** (VS Code fork first)
- **This document** — **Alternative B** (Agent Framework first)

### Components
- [Canon_Key_Components.md](./Canon_Key_Components.md) — Core IDE components

### Canon Arena & UI/UX
- [SAS_UI_Collaboration.md](./specs/SAS_UI_Collaboration.md) — Dashboard Mode / Studio Mode architecture
- [AI_Arena_UI.md](../AI_Arena_UI.md) — Arena-style dashboard product analysis
- [Canon_Polymarket_Automation_Guide.md](./Canon_Polymarket_Automation_Guide.md) — Hybrid automation architecture

### Launch
- [Canon_NBA_Playoffs_2026.md](./Canon_NBA_Playoffs_2026.md) — Hackathon GTM event

### Strategic Analysis
- [Canon_Inversion_Thinking.md](./Canon_Inversion_Thinking.md) — Inversion analysis (execution reliability as #1 trust-builder)

### Open Core & Licensing
- [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0) — All Canon open-source components; includes explicit patent grant, enterprise-friendly
- [Open Core Model](https://en.wikipedia.org/wiki/Open-core_model) — Distribution pattern: open-source core + proprietary extensions/platform

### External Resources
- [pmxt](https://github.com/pmxt-dev/pmxt) — Unified prediction market API
- [OpenAI: Harness Engineering](https://openai.com/index/harness-engineering/)[^harness-eng] — Lessons from building a million-line agent-generated codebase
- [Claude Cookbook](https://platform.claude.com/cookbook) — Anthropic's practical guides for agent implementation
- [Auto-Claude](https://github.com/AndyMik90/Auto-Claude) — Reference implementation for Ralph Loop, worktrees, DAG, memory
- [Open Trees](https://github.com/0xSero/open-trees) — OpenCode plugin for worktree management
- [Fly.io Machines](https://fly.io/docs/machines/) — Persistent container compute for Cloud Execution Service (Phase 1 compute layer)
- [Ramp Inspect](https://builders.ramp.com/post/why-we-built-our-background-agent)[^ramp-inspect] — Conceptual influence for image pre-building patterns; Canon diverges from Ramp's ephemeral Modal approach in favor of persistent Fly.io Machines
- [Inngest](https://github.com/inngest/inngest) — ⚠️ *Evaluate for Phase II* — durable workflow orchestration for event-driven fan-out
- [Canon_SAS.md § Agent Orchestration & UI/UX Reference Implementations](./Canon_SAS.md#agent-orchestration--uiux-reference-implementations)

---

## Appendix: Feature Prioritization Matrix

| Feature | Hackathon Essential | Weird | ~7wk Feasible | Dogfood | **Phase** |
|---------|---------------------|-------|---------------|---------|-----------|
| **Canon Arena MVP** | ✅✅✅ | ✅✅ | ✅✅✅ | ✅✅ | **Phase I** |
| **Canon Agent Framework** | ✅✅✅ | ✅✅✅ | ✅✅✅ | ✅✅✅ | **Phase I** |
| **Canon MCP Server** | ✅✅✅ | ✅✅ | ✅✅✅ | ✅✅✅ | **Phase I** |
| **Simplified Ralph Loop** | ✅✅ | ✅✅✅ | ✅✅✅ | ✅✅✅ | **Phase I** |
| **Prediction Market Adapter (pmxt)** | ✅✅✅ | ✅ | ✅✅✅ | ✅✅ | **Phase I** |
| **Starter Templates (10)** | ✅✅✅ | ✅ | ✅✅✅ | ✅ | **Phase I** |
| **Execution Reliability** | ✅✅✅ | ✅✅ | ✅✅✅ | ✅✅✅ | **Phase I** |
| **Cloud Execution (Fly.io Machines)** | ✅✅✅ | ✅✅ | ✅✅ | ✅✅ | **Phase I** (P0) |
| **Harness Eng. Patterns**[^harness-eng] | ✅✅ | ✅✅✅ | ✅✅✅ | ✅✅✅ | **Phase I** |
| **Runtime Bridge (minimal)**[^harness-eng] | ✅ | ✅✅✅ | ✅✅ | ✅✅✅ | **Phase I** |
| **Developer Onboarding** | ✅✅✅ | ✅ | ✅✅✅ | ✅✅ | **Phase I** |
| **Canon IDE (VS Code Fork)** | ❌ | ✅✅ | ❌ (deferred) | ✅ | **Phase II** |
| **Marketplace + x402** | ✅ | ✅✅ | ✅✅ | ✅✅ | **Phase II** |
| **Cloud Execution (advanced)** | ✅✅ | ✅✅ | ✅✅ | ✅✅ | **Phase II** |
| **Composable Blueprints** | ✅ | ✅✅ | ✅✅ | ✅✅✅ | **Phase II** |
| **Collaboration Layer** | ✅✅ | ✅✅ | ✅✅ | ✅✅✅ | **Phase II** |
| **Advanced Ralph Loop** | ✅ | ✅✅✅ | ✅ | ✅✅✅ | **Phase II** |
| **Copy/Counter Trading** | ✅ | ✅✅ | ✅✅ | ✅ | **Phase II** |
| **Referral Codes** | ✅ | ✅ | ✅✅ | ✅ | **Phase II** |
| **Entropy Management**[^harness-eng] | ✅ | ✅✅ | ✅✅ | ✅✅✅ | **Phase II** |
| AI-to-AI Social | ❌ | ✅✅✅ | ❌ | ✅ | Deferred |
| System Flow Visualizer | ❌ | ✅✅ | ✅ | ✅ | Deferred |
| Graph Memory (Cognee) | ❌ | ✅ | ❌ | ✅ | Deferred |

**Legend:** ✅ = low, ✅✅ = medium, ✅✅✅ = high, ❌ = not feasible / not essential

---

*"Ship Arena + Agent Framework + Ralph Loop + production-grade cloud execution (Fly.io Machines) by April. Validate with 150+ developers. Scale to 500+ strategies for World Cup. Build the IDE on data, not assumptions. First revenue from cloud execution post-hackathon."*

---

## Footnotes

[^harness-factory]: Ryan Carson, "Code Factory: How to setup your repo so your agent can auto write and review 100% of your code," X (Twitter), February 14, 2026. <https://x.com/ryancarson/status/2023452909883609111>. Practitioner's implementation guide for Harness Engineering in a production repo — covers machine-readable risk contracts (risk tiers by path, required checks by tier), preflight gate ordering (fail-fast before expensive CI fanout), current-head SHA discipline (review state valid only for headSha, stale evidence causes merge failure), single rerun-comment writer with SHA dedupe (avoids race conditions in multi-workflow setups), and optional in-branch remediation loop (review agent finds issue → coding agent patches → push → rerun). Canon adopts three patterns from this guide: risk contract (`.canon/risk-contract.json`), preflight gate ordering in the Local PR system, and SHA discipline for review state. See [SAS_AIDD_Pipeline.md § Risk Contract & Merge Policy](./specs/SAS_AIDD_Pipeline.md#risk-contract--merge-policy).

[^harness-eng]: Ryan Lopopolo, "Harness Engineering: Leveraging Codex in an Agent-First World," OpenAI Engineering Blog, February 11, 2026. <https://openai.com/index/harness-engineering/>. Canon adopts 9 patterns: Core Operating Principles (repo-as-truth, boring technology, rigid architecture), AGENTS.md as ~100-line TOC, structured `docs/` with execution plan lifecycle, Agent-Oriented Error Messages, Application Legibility / Runtime Bridge (elevated to Phase I), Doc-Gardening Agent, Code Gardening / Golden Principles. Full specifications in [Canon_SAS.md § Core Operating Principles](./Canon_SAS.md#core-operating-principles).

[^flow-next]: Gordon Mickel, "Ralph Mode: Why AI Agents Should Forget," Mickel Tech, January 12, 2026. <https://mickel.tech/log/ralph-mode-why-ai-agents-should-forget>. Introduces cross-model review gates (different model reviews code with blocking SHIP/NEEDS_WORK verdicts), interview-driven spec refinement before planning, and fresh-context-per-iteration philosophy. Key insight: "Self-testing is self-consistency. Not falsification." — same model writing and reviewing converges to local coherence, not global correctness. Canon adapts: tri-provider model (Claude plans/reviews, Codex codes, Gemini researches), blocking in-loop LLM review, and interview phase. Source: [flow-next GitHub](https://github.com/gmickel/gmickel-claude-marketplace).

[^ramp-inspect]: Ramp Engineering, "Why We Built Our Background Agent," Ramp Builders Blog, 2026. <https://builders.ramp.com/post/why-we-built-our-background-agent>. Engineering spec for Ramp's Inspect background coding agent — Modal-based sandboxes with 30-min image pre-building, filesystem snapshots for state persistence, warm pool management, Cloudflare Durable Objects for per-session real-time streaming, multiplayer collaboration with per-user attribution, and child session spawning. Reports ~30% of Ramp's merged PRs written by Inspect. **Conceptual influence only** — Canon uses persistent Fly.io Machines (not ephemeral Modal sandboxes) with exchange reconciliation for crash recovery (not snapshot/restore). Image pre-building pattern still applicable (pre-bake Docker images with pmxt + deps). See [SAS_Orchestration_References.md § Ramp Inspect](./specs/SAS_Orchestration_References.md#ramp-inspect-cloud-execution-infrastructure--conceptual-influence) and [SAS_Deployment.md](./specs/SAS_Deployment.md).
