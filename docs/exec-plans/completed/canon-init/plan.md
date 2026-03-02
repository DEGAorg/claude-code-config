# Plan: Canon Init — Project-Local Model

**Status:** In progress
**Created:** 2026-03-02

## Requirements

- `/canon-init` is a slash command that runs from inside any strategy project directory
  and scaffolds the full Canon context there — no writes to `~/.claude/`
- After running `/canon-init`, a project has `.canon/agents/` (6 files), `.canon/skills/`
  (8 files), `.canon/config.yaml`, `.canon/ralph.yaml`, `.canon/execution/`, and `AGENTS.md`
  at the project root
- Running `/develop` or `/ralph-cycle` from that project uses the locally-loaded Canon agents
- `/apply-canon` (global install) is removed — the project-local model replaces it

## Approach

Create `commands/canon-init.md` as a slash command that:

1. Guards against running inside `claude-code-config` itself
2. Checks if `.canon/` already exists and asks before overwriting
3. Fetches 6 agent files from GitHub → writes to `.canon/agents/`
4. Fetches 8 skill files from GitHub → writes to `.canon/skills/`
5. Writes `.canon/config.yaml` from an inline template (strategy name derived from `pwd`)
6. Writes `.canon/ralph.yaml` from an inline template (placeholder success criteria)
7. Creates `.canon/execution/.gitkeep`
8. Writes `AGENTS.md` at project root from an inline template
9. Prints post-init instructions: edit `ralph.yaml`, then run `/develop`

Source for all fetched files:
`https://raw.githubusercontent.com/DEGAorg/claude-code-config/main/canon/agents/<name>.md`
`https://raw.githubusercontent.com/DEGAorg/claude-code-config/main/canon/skills/<name>.md`

Delete `commands/apply-canon.md` — it is replaced by this command.

### Why project-local

Core (`/apply-core`) installs generic dev infrastructure globally — it applies to every
project on the machine. Canon is prediction-market-specific context; it belongs in the
project alongside the strategy code. This also matches the `canon_init` MCP tool described
in the MVP roadmap, which scaffolds into the current directory.

### What the demo needs from this

When the demo records Canon building the sports-arb strategy, the flow is:
1. Navigate to the (reset) sports-arb directory
2. Run `/canon-init` on screen — Canon scaffold appears
3. Run `/develop` or `/ralph-cycle` — Canon agents build the strategy
4. Ralph iterates on screen until all checks pass

## Files to touch

| File | Change |
|------|--------|
| `commands/canon-init.md` | Create — project-local Canon init command |
| `commands/apply-canon.md` | Delete — replaced by canon-init |

## Risks and open questions

- **Workflow YAML files**: `config.yaml` references `.canon/workflows/*.yaml` but those
  files don't exist in canon/ yet. For Phase I, the slash commands (`/develop`,
  `/ralph-cycle`) ARE the workflows. `canon-init` will create an empty `workflows/` dir
  with a README noting this. Not blocking.

- **sports-arb .canon/ already populated**: The reset plan (separate) will clear strategy
  files but keep `.canon/`. Running `/canon-init` again on sports-arb is optional — it
  already has the right scaffold from S1. The command just needs to exist for the demo recording.

## Progress log

- [x] Create `docs/exec-plans/active/canon-init/` and write this plan there
- [x] Write `commands/canon-init.md` with all steps defined in Approach
- [x] Delete `commands/apply-canon.md`
- [x] Smoke test: run `/canon-init` in a scratch directory, verify `.canon/` structure
- [x] Verify `AGENTS.md` content at project root matches Canon entry-point spec
- [x] Confirm `~/.claude/` is not modified after running the command

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Project-local only | Global install (apply-canon model) | Canon is strategy context, not global tooling. Matches canon_init MCP spec. |
| Fetch from GitHub | Read from local canon/ directory | Portable — works from any directory, not just when claude-code-config is cloned nearby |
| Inline config.yaml / ralph.yaml templates | Fetch from GitHub | Config files need project-specific values (strategy name); inline is simpler than a template-fetch-and-substitute pattern |
| Delete apply-canon.md | Keep both | Two commands doing overlapping things is confusing. Project-local is the right model going forward. |

## Completion criteria

- [x] `commands/canon-init.md` exists and follows the structure above
- [x] `commands/apply-canon.md` is deleted
- [x] Running `/canon-init` in an empty directory creates `.canon/` with 6 agents, 8 skills,
      `config.yaml`, `ralph.yaml`, `execution/`, and `AGENTS.md` at root
- [x] `~/.claude/` contents are unchanged after running the command
