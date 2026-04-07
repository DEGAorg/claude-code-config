# Research: Single-Entry-Point Installation for DEGA Core

**Date:** 2026-04-07
**Goal:** Allow users to install DEGA Core by giving Claude a single URL — no cloning, no manual steps.

---

## Current State

`/apply-core` is a comprehensive slash command that:
- Detects installed agents (Claude, Gemini, Codex)
- Fetches files from `https://raw.githubusercontent.com/DEGAorg/claude-code-config/develop/`
- Installs shared artifacts to `~/.degacore/`
- Generates per-agent config with adapters
- Self-installs to `~/.degacore/config/commands/apply-core.md`

**Problem:** Requires the repo to be cloned first, then user must open Claude in that directory and run `/apply-core`. Three steps, not one.

---

## Patterns Found

### 1. Plugin Marketplace (`/plugin marketplace add`)
- Official Anthropic mechanism (2026)
- Repos publish `marketplace.json`, users install with `/plugin marketplace add owner/repo`
- Most frictionless — no cloning, no manual file copying
- Used by: feiskyer/claude-code-settings, athola/claude-night-market, vercel-labs/skills

### 2. Self-Installing Slash Command (Trail of Bits)
- `git clone` → `claude` in repo → `/trailofbits:config`
- Smart merge for settings.json, prompt-before-overwrite for CLAUDE.md
- Self-installs the command so future runs work from any directory
- Used by: trailofbits/claude-code-config

### 3. Bootstrap Seed Prompt
- Single ~1400 token prompt in `.claude/CLAUDE.md`
- Bootstraps Claude into a self-improving config system
- No scripts, no hooks — just markdown
- Used by: ChristopherA's gist

### 4. CLI Bootstrap Tools
- `pip install cc-bootstrap` → guided prompts → generates config
- Heavier but more structured
- Used by: vinodismyname/ClaudeCodeBootstrap

### 5. Project-Level Auto-Install
- Configure plugins in `.claude/settings.json` at repo level
- Auto-installs when team member trusts the repo
- Zero user action beyond trusting the project

---

## Tradeoffs

| Pattern | Simplicity | Security | Flexibility |
|---------|-----------|----------|-------------|
| Plugin marketplace | Best (one command) | Reviewed ecosystem | Limited to plugin format |
| Slash command self-install | Good (3 steps) | User reviews on clone | Full control, smart merges |
| Project auto-install | Zero-touch | Trust-on-first-use | Team-scoped only |
| Bootstrap seed | One file copy | Transparent (just markdown) | No scripts/hooks |
| CLI tool | pip install + run | Opaque generation | Heavy, requires API keys |

---

## Recommendation

**Dual approach:**

1. **Plugin marketplace** — Publish `marketplace.json` for skills/commands. Users run:
   ```
   /plugin marketplace add DEGAorg/claude-code-config
   /plugin install --all
   ```

2. **Fetchable bootstrap prompt** — A single markdown file at a stable URL that Claude can fetch and execute. User says to Claude:
   > "Install DEGA Core from https://raw.githubusercontent.com/DEGAorg/claude-code-config/develop/bootstrap.md"
   
   Claude fetches the URL, reads the instructions, and runs the full install flow autonomously.

The bootstrap prompt approach gives us the "single URL" UX while the marketplace gives us discoverability. Both converge on the same `/apply-core` logic for the actual installation.

---

## Key Implementation Details

### Bootstrap file (`bootstrap.md`)
- Contains instructions for Claude to fetch and execute `/apply-core`
- Includes the full apply-core command inline OR fetches it from GitHub
- Must be self-contained — no dependencies on local files

### Marketplace file (`marketplace.json`)
- Lists all publishable skills and commands
- Points to raw GitHub URLs for each component
- Follows Anthropic's marketplace spec

### Entry points (all converge on same install logic):
1. **URL to Claude:** "Install from {url}" → Claude fetches bootstrap.md → runs apply-core
2. **Plugin:** `/plugin marketplace add DEGAorg/claude-code-config`
3. **Manual:** Clone repo → `/apply-core` (existing flow, unchanged)
