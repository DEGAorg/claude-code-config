# Single Entry Point Installation

**Created:** 2026-04-07
**Status:** draft
**Branch:** feat/single-entry-install

## Problem

Installing DEGA Core currently requires cloning the repo, opening Claude in it, and running `/apply-core`. Users should be able to install by simply telling Claude a URL or running a single command.

## Research

See [docs/research/single-entry-install.md](../../research/single-entry-install.md) for full analysis.

## Requirements

1. A user can install DEGA Core by giving Claude a single URL — no cloning, no manual steps
2. The plugin marketplace format (`.claude-plugin/`) is the primary distribution mechanism
3. Skills, commands, agents, and hooks are packaged as plugins
4. Rules and settings (which plugins can't install directly) are handled by a bootstrap skill within the plugin
5. Existing `/apply-core` flow continues to work as a fallback
6. All three entry points converge on the same install logic

## Approach

**Two-layer architecture:**

1. **Plugin layer** — `.claude-plugin/marketplace.json` + plugin structure for skills, agents, hooks
2. **Bootstrap skill** — A skill inside the plugin that handles everything plugins can't (rules, settings.json, agent-template.md, scripts, sounds, orchestrator, terminal UI)

**User flow:**
```
User: "Install DEGA Core from DEGAorg/claude-code-config"
Claude: runs /plugin marketplace add DEGAorg/claude-code-config
Claude: runs /plugin install dega-core@dega
Claude: runs /dega-core:bootstrap (installs rules, settings, scripts)
Done.
```

**Alternative flow (URL-based):**
```
User: pastes https://raw.githubusercontent.com/DEGAorg/claude-code-config/develop/bootstrap.md
Claude: fetches URL, reads instructions, runs the above flow
```

## Scope

### In scope
- `.claude-plugin/marketplace.json` with marketplace definition
- `plugins/dega-core/` with plugin.json, skills, agents, hooks
- Bootstrap skill that installs rules, settings, scripts, sounds
- `bootstrap.md` at repo root — fetchable install prompt
- Updated README with new install instructions

### Out of scope
- Removing `/apply-core` (kept as legacy/manual fallback)
- Multi-agent adapters in plugin format (Gemini/Codex adapters stay in `/apply-core`)
- npm publishing (GitHub-only for now)

## Progress log

- [ ] Create `.claude-plugin/marketplace.json` with DEGA marketplace definition
- [ ] Create `plugins/dega-core/.claude-plugin/plugin.json` with plugin metadata (deps: 1)
- [ ] Move/copy skills into `plugins/dega-core/skills/` in plugin format (deps: 2)
- [ ] Move/copy agents into `plugins/dega-core/agents/` in plugin format (deps: 2)
- [ ] Package hooks into `plugins/dega-core/hooks/` (deps: 2)
- [ ] Create bootstrap skill `plugins/dega-core/skills/bootstrap/SKILL.md` — installs rules, settings, scripts, sounds, orchestrator, terminal UI (deps: 3, 4, 5)
- [ ] Create `bootstrap.md` at repo root — fetchable install prompt with instructions for Claude (deps: 6)
- [ ] Update README.md with new install instructions (deps: 7)
- [ ] Test: verify `/plugin marketplace add` + `/plugin install` + bootstrap flow works end-to-end (deps: 8)

## Completion criteria

- [ ] `marketplace.json` is valid and discoverable
- [ ] `/plugin marketplace add DEGAorg/claude-code-config` succeeds
- [ ] `/plugin install dega-core@dega` installs skills, agents, hooks
- [ ] `/dega-core:bootstrap` installs rules, settings, scripts, sounds to `~/.degacore/`
- [ ] Fetching `bootstrap.md` URL and pasting to Claude triggers full install
- [ ] Existing `/apply-core` still works unchanged
