# Plan: Core Init Command

**Status:** In progress
**Created:** 2026-03-06

## Requirements

- `/core-init` command that bootstraps any repo for Core tools (Ralph Loop, exec plans, hooks, linting)
- Project-agnostic — works for any codebase, not just Canon/prediction markets
- Generates: `ralph.yaml`, `docs/exec-plans/` structure, `.claude/` hooks directory, minimal CLAUDE.md
- Detects existing config and skips what's already present (idempotent)
- Available after running `/apply-core` (command file installed globally)

## Approach

Model after `/canon-init` but strip all Canon-specific logic. `/core-init` is
the generic layer; `/canon-init` adds Canon on top. The command is a Markdown
instruction file (like all commands) that guides the agent through the bootstrap.

No shell script needed — the agent executes the steps directly. This keeps
the command inspectable and editable by users.

### What gets generated

```
my-project/
├── ralph.yaml                  # Ralph Loop config (success criteria, budget)
├── docs/
│   └── exec-plans/
│       ├── active/
│       │   └── .gitkeep
│       └── completed/
│           └── .gitkeep
├── .claude/
│   ├── commands/               # Local commands (user can add project-specific ones)
│   │   └── .gitkeep
│   └── settings.json           # Hooks config (if not present)
└── CLAUDE.md                   # Minimal project CLAUDE.md (if not present)
```

### ralph.yaml template

```yaml
max_iterations: 20
warn_at_iteration: 15
success_criteria:
  - "tests pass"
  - "linting clean"
  - "types valid"
check_command: |
  # Adjust to your project's toolchain
  npm test && npm run lint && npm run typecheck
```

### Minimal CLAUDE.md template

Points to global rules (loaded by `~/.claude/rules/`), documents project
structure, and links to ralph.yaml. Short — under 50 lines. The user fills
in project-specific context.

## Files to touch

| File | Change |
|------|--------|
| `commands/core-init.md` | New — the `/core-init` command definition |
| `commands/apply-core.md` | Add `commands/core-init.md` to the source file list and install section |
| `docs/core-init-claude-template.md` | New — minimal CLAUDE.md template for bootstrapped repos |

## Risks and open questions

- **Q: Should `/core-init` auto-detect the project's language/toolchain to
  populate `check_command` in ralph.yaml?**
  Decision: Yes, basic detection. Check for `package.json` (Node), `pyproject.toml`
  (Python), `Cargo.toml` (Rust), `go.mod` (Go). Fall back to a comment telling
  the user to fill it in.

- **Q: Should `/core-init` install hooks from settings.json?**
  Decision: No. Hooks are global (`~/.claude/settings.json`) and installed by
  `/apply-core`. `/core-init` only creates per-project artifacts.

- **Q: Relationship to `/canon-init`?**
  `/core-init` is generic. `/canon-init` calls or assumes `/core-init` ran first,
  then adds Canon-specific artifacts (.canon/, canon.sh, agents, skills). They're
  complementary, not competing.

## Progress log

- [x] Write `commands/core-init.md` — command definition with all bootstrap steps
- [x] Write `docs/core-init-claude-template.md` — minimal CLAUDE.md template
- [x] Add language detection logic for ralph.yaml `check_command`
- [x] Add idempotency guards (skip existing files, don't overwrite)
- [x] Add `/core-init` to `commands/apply-core.md` source list and install section
- [x] Test: run in a fresh empty directory, verify all artifacts created
- [x] Test: run in a directory with existing CLAUDE.md, verify it's not overwritten

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Markdown command, not shell script | Shell script like canon-scaffold.sh | Commands are inspectable and editable. The bootstrap is simple enough that agent execution works. Shell script adds a maintenance burden for no gain. |
| Auto-detect language for check_command | Always write generic placeholder | Small effort, big UX win. Developers don't have to figure out what to put in ralph.yaml. |
| Don't install hooks | Install a starter settings.json | Hooks are global and belong to `/apply-core`. Mixing global and per-project config in one command is confusing. |
| Don't overwrite existing files | Always overwrite | Idempotency. Users may have customized their CLAUDE.md or ralph.yaml. |

## Completion criteria

- [x] `/core-init` command exists and is installable via `/apply-core`
- [x] Running in a fresh dir creates ralph.yaml, docs/exec-plans/, .claude/commands/, CLAUDE.md
- [x] Running in a dir with existing CLAUDE.md does not overwrite it
- [x] ralph.yaml check_command is populated for Node, Python, Rust, Go projects
- [x] ralph.yaml check_command falls back to a placeholder comment for unknown projects
