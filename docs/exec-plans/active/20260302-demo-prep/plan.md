# Plan: Demo Prep — Canon Init Flow for March 5 Recording

**Status:** In progress
**Created:** 2026-03-02

## Requirements

- A user can go to a clean empty directory, run `/canon-init`, and get:
  - Canon context: `.canon/` (agents, skills, config, ralph.yaml)
  - Canon commands: `.claude/commands/` (develop, ralph-cycle, etc.)
  - TypeScript project template: `package.json`, `tsconfig.json`, vitest,
    oxlint, `src/types/` stubs (TradeSignal, RiskInterface)
- After init, the user runs `/develop` or gives a natural language prompt and
  Canon agents build the actual strategy (scanner, signals, risk, tests, runner)
- GitHub raw URLs in canon-init point at `premar-demo` branch (no merge to
  main required — merge happens later when ready)
- `/canon-init` is available globally (`~/.claude/commands/`)
- Canon slash commands (`/develop`, `/ralph-cycle`) are available in the target
  project after init (installed to `.claude/commands/`)
- `/develop` and `/ralph-cycle` work without Canon MCP tools (no MCP server
  exists yet)

## Approach

Five steps, in dependency order.

### Step 1: Update GitHub fetch URLs to `premar-demo` branch

All fetch URLs in `canon-init.md` currently point at `main` where Canon
artifacts don't exist yet. Change the base URL from:

```
https://raw.githubusercontent.com/DEGAorg/claude-code-config/main/
```

to:

```
https://raw.githubusercontent.com/DEGAorg/claude-code-config/premar-demo/
```

This applies to all agent fetches (6 URLs) and all skill fetches (8 URLs),
plus the new command fetches added in Step 2. No merge to main needed —
`premar-demo` is pushed to origin and has all Canon artifacts.

### Step 2: Update `canon-init.md` — install Canon commands + TS template

Add a new step (between current step 4 and step 5) that creates
`.claude/commands/` in the target project and fetches the 5 Canon command files:

| File | GitHub source path |
|------|-------------------|
| `develop.md` | `canon/commands/develop.md` |
| `ralph-cycle.md` | `canon/commands/ralph-cycle.md` |
| `discover.md` | `canon/commands/discover.md` |
| `register.md` | `canon/commands/register.md` |
| `quick-dev.md` | `canon/commands/quick-dev.md` |

Same fetch-from-GitHub pattern as agents/skills. Target: `.claude/commands/`
in the project directory.

Update the post-init summary (step 9) to mention the installed commands.

Also add a new step that scaffolds the TypeScript project template:

- `package.json` with dev deps (typescript, vitest, oxlint, tsx)
- `tsconfig.json` with strict settings
- `src/types/TradeSignal.ts` — empty interface stub
- `src/types/RiskInterface.ts` — empty interface stub
- `.env.example` — documents required credentials
- `.gitignore` — node_modules, .env, .canon/execution/

This is the template that `/develop` step 1 currently tries to create via
the `canon_init` MCP tool. Baking it into `/canon-init` means the project
is ready for strategy implementation immediately after init.

### Step 3: Fix Canon commands — remove MCP tool dependencies

The Canon commands reference `canon_*` MCP tools that don't exist yet.
Replace with local equivalents:

**`develop.md`:**
- Step 1 (Scaffold): Remove `canon_init --template`. Replace with: "Verify the
  project scaffold exists (package.json, tsconfig, src/types/). If missing, the
  user should run `/canon-init` first." The template is now part of canon-init.
- Step 3 (Test): Replace `canon_test --timeframe 30d` with the check commands
  from `.canon/ralph.yaml` (i.e., `pnpm exec vitest run`)
- Step 4 (Iterate): Replace `canon_ralph` with: "Run the success criteria
  checks from `.canon/ralph.yaml` and iterate until all pass"

**`ralph-cycle.md`:**
- Intro: Remove "triggered by `canon_ralph`" — triggered by running `/ralph-cycle`
- Step 2 (Check): Replace `canon_test` reference with: "Run every check command
  in `.canon/ralph.yaml` `success_criteria`"

**`discover.md`:**
- Step 1: Replace `canon_market` with: "Research available prediction markets
  using web search and Polymarket API documentation"
- Step 3: Remove `canon_init --template` reference

**`register.md`** and **`quick-dev.md`**: Not needed for demo. Leave as-is
(register references `canon_register`/`canon_position` which require MCP).

### Step 4: Install `canon-init` globally

Copy `commands/canon-init.md` to `~/.claude/commands/canon-init.md` so it's
available from any directory. This is a manual step (or update `/apply-core`
to include it — but that's more scope than needed for demo prep).

### Step 5: End-to-end verification

In a fresh temp directory:
1. Run `/canon-init` — confirm all files scaffolded
2. Verify `.canon/agents/` (6 files), `.canon/skills/` (8 files),
   `.canon/config.yaml`, `.canon/ralph.yaml`, `AGENTS.md`
3. Verify `.claude/commands/` has the 5 Canon commands
4. Confirm `/develop` and `/ralph-cycle` are available as slash commands
5. Give Claude a natural language prompt to build the NBA strategy and
   verify it uses the Canon agents/skills context

## Files to touch

| File | Change |
|------|--------|
| `commands/canon-init.md` | Add Canon commands install + TypeScript project template |
| `canon/commands/develop.md` | Replace `canon_init`, `canon_test`, `canon_ralph` with local equivalents |
| `canon/commands/ralph-cycle.md` | Replace `canon_ralph`, `canon_test` with local equivalents |
| `canon/commands/discover.md` | Replace `canon_market`, `canon_init` with local equivalents |
| `~/.claude/commands/canon-init.md` | Manual copy for global availability |

## Risks and open questions

- **Branch coupling**: Fetch URLs point at `premar-demo`. If that branch gets
  rebased or deleted before demo, URLs break. Low risk — branch is stable and
  pushed to origin. Merge to `main` after demo removes this coupling.
- **Template scope**: The TypeScript template baked into canon-init is generic
  (types stubs, standard tooling). Strategy-specific deps (e.g., Polymarket
  client, Odds API client) are NOT in the template — Canon installs those
  during `/develop` step 2 (Implement). This keeps the template reusable.

## Progress log

- [x] Update `commands/canon-init.md` — switch URLs to `premar-demo`, add Canon commands + TS template
- [x] Fix `canon/commands/develop.md` — remove MCP dependencies
- [x] Fix `canon/commands/ralph-cycle.md` — remove MCP dependencies
- [x] Fix `canon/commands/discover.md` — remove MCP dependencies
- [x] Copy `canon-init.md` to `~/.claude/commands/`
- [x] End-to-end test in clean directory

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Fetch from premar-demo branch | Merge to main first | Avoids large merge before demo; URLs work now, merge later |
| Install commands via canon-init | Require separate /apply-canon step | Project-local model — canon-init is the single entry point |
| Replace MCP refs with local tooling | Build MCP server, skip commands and use natural language | MCP server is out of scope for demo; local tooling works today |
| Manual global install of canon-init | Update /apply-core to include it | Faster; apply-core update is nice-to-have, not blocking |
| TS template baked into canon-init | Canon creates scaffold live during /develop | canon-init is the single setup command; /develop focuses on strategy logic |

## Completion criteria

- [x] All GitHub raw URLs in canon-init resolve (premar-demo branch)
- [x] `/canon-init` from clean dir produces .canon/, .claude/commands/, and TS template
- [x] `/develop` runs without referencing nonexistent MCP tools
- [x] `/ralph-cycle` runs without referencing nonexistent MCP tools
- [x] End-to-end: clean dir → `/canon-init` → Canon context fully loaded
