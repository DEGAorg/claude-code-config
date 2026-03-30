# Plan: Demo S1 — Sports Arb Strategy Repo Bootstrap

**Status:** In progress
**Created:** 2026-02-27

## Requirements

- A new git repo exists at `/Users/cerratoa/dega/sports-arb`
- The repo has a complete Node 22 ESM + TypeScript project scaffold (pnpm, tsconfig strict,
  vitest, oxlint)
- Canon framework is installed: `.canon/` directory with all 6 agent personas, all 8 skills,
  and `AGENTS.md` copied from this repo's `canon/` layer
- `.canon/ralph.yaml` is written with sports arb-specific success criteria
- `.env.example` documents all required credentials (Polymarket private key + proxy address,
  sportsbook API key) — no real keys committed
- `.gitignore` covers `.env`, `node_modules/`, `.canon/execution/`
- `src/types/` directory exists as placeholder for TradeSignal and RiskInterface
- `pnpm install` runs without errors (dev dependencies only — no pmxt yet)
- `tsc --noEmit` passes on the empty scaffold
- `oxlint` passes on the empty scaffold

## Approach

Create the strategy repo by hand — no MCP server, no `canon_init`. This mirrors the demo
story: "I told Claude Code to build me a sports arbitrage scanner. It used the Canon agent
framework."

**Step 1:** Initialize repo, package manager, TypeScript toolchain.

**Step 2:** Copy Canon artifacts from `canon/` in this repo into `.canon/` in the new repo.
The demo says "Canon agents" are loaded — the mechanism is Claude Code reading the AGENTS.md
that maps to `.canon/agents/` and `.canon/skills/`.

**Step 3:** Write `.canon/ralph.yaml` with success criteria specific to the sports arb
strategy (TypeScript compiles, tests pass, dry-run emits decision logs).

**Step 4:** Scaffold `src/types/` with empty placeholder files so `tsc` has a valid source
tree to check.

## Files to touch

All files are **created** in `/Users/cerratoa/dega/sports-arb/`.

| File | Change |
|------|--------|
| `package.json` | Create — Node 22 ESM, pnpm, TypeScript 5, vitest, oxlint, type-fest |
| `tsconfig.json` | Create — strict, noUncheckedIndexedAccess, exactOptionalPropertyTypes, etc. |
| `.oxlintrc.json` | Create — typescript + import + unicorn plugins enabled |
| `vitest.config.ts` | Create — minimal vitest config |
| `AGENTS.md` | Create — copy of `canon/AGENTS.md` |
| `.canon/config.yaml` | Create — Canon config pointing to local agents + skills |
| `.canon/ralph.yaml` | Create — sports arb success criteria (see below) |
| `.canon/agents/*.md` | Create — copy all 6 from `canon/agents/` |
| `.canon/skills/*.md` | Create — copy all 8 from `canon/skills/` |
| `.env.example` | Create — credential placeholders |
| `.gitignore` | Create — .env, node_modules, dist, .canon/execution |
| `src/types/.gitkeep` | Create — placeholder so directory is tracked |

### `.canon/ralph.yaml` success criteria

```yaml
version: 1
strategy: sports-arb

success_criteria:
  - id: types_compile
    description: TypeScript compiles with no errors
    check: "pnpm exec tsc --noEmit"
    required: true

  - id: lint_clean
    description: oxlint reports zero errors
    check: "pnpm exec oxlint src/"
    required: true

  - id: tests_pass
    description: vitest passes
    check: "pnpm exec vitest run"
    required: true

  - id: dry_run_emits
    description: Dry-run runner writes at least one decision log to .canon/execution/
    check: "test -d .canon/execution && ls .canon/execution/*.jsonl 2>/dev/null | head -1 | xargs test -f"
    required: true

max_iterations: 5
```

## Risks and open questions

- **pmxt package name:** Canon docs reference `pmxtjs` for Node but this library may not be
  published on npm yet. S2 plan will verify. S1 does not install pmxt — that's S2's job.
- **Sportsbook API:** The Odds API (`https://the-odds-api.com`) is real and has a free tier.
  API key goes in `.env`. S2 writes the wrapper.

## Progress log

- [x] `git init /Users/cerratoa/dega/sports-arb` and initial commit
- [x] Create `package.json` (Node 22 ESM, pnpm, TypeScript 5, vitest, oxlint)
- [x] Create `tsconfig.json` (strict settings per node-typescript.md standards)
- [x] Create `.oxlintrc.json`
- [x] Create `vitest.config.ts`
- [x] Copy `AGENTS.md` from `canon/AGENTS.md`
- [x] Create `.canon/config.yaml`
- [x] Write `.canon/ralph.yaml` with sports arb success criteria
- [x] Copy all 6 agent markdown files into `.canon/agents/`
- [x] Copy all 8 skill markdown files into `.canon/skills/`
- [x] Create `.env.example` with all credential placeholders documented
- [x] Create `.gitignore`
- [x] Create `src/types/.gitkeep`
- [x] Run `pnpm install` — confirm no errors
- [x] Run `pnpm exec tsc --noEmit` — confirm passes on empty scaffold
- [x] Run `pnpm exec oxlint src/` — confirm passes

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| `.canon/` directory structure | `.agents/` (demo doc wording) | AGENTS.md and canon spec both use `.canon/`; `.agents/` in demo doc is informal shorthand |
| Copy canon artifacts manually | Run `/apply-canon` command | Demo story is "manually built" — no MCP server; also validates the Canon artifacts are self-contained |
| Node 22 + TypeScript (not Python) | Python + pmxt | Demo doc specifies "TypeScript standalone script"; TradeSignal/RiskInterface are typed TS interfaces |
| pnpm | npm, bun | node-typescript.md standards: pnpm audit, minimumReleaseAge, ignore-scripts |

## Completion criteria

- [x] `pnpm install` exits 0
- [x] `pnpm exec tsc --noEmit` exits 0
- [x] `pnpm exec oxlint src/` exits 0
- [x] `.canon/agents/` contains 6 agent files
- [x] `.canon/skills/` contains 8 skill files
- [x] `.canon/ralph.yaml` exists with all 4 success criteria
- [x] `.env.example` exists with no real credentials
