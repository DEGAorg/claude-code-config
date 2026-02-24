# Apply Canon

@description Install Canon prediction-market layer artifacts globally to ~/.claude/.

Install Canon harness artifacts from GitHub into `~/.claude/`. Works from any
directory — no need to clone the repo. Requires Core to be installed first.

## Source

All files are fetched from:

```
https://raw.githubusercontent.com/DEGAorg/claude-code-config/main/canon/
```

Files available:

**Rules**
- `canon/rules/domain-layering.md`

**Skills**
- `canon/skills/prediction-markets.md`
- `canon/skills/polymarket.md`
- `canon/skills/risk-management.md`
- `canon/skills/strategy-patterns.md`
- `canon/skills/backtesting.md`
- `canon/skills/arena-tracking.md`
- `canon/skills/ralph-loop.md`
- `canon/skills/canon-conventions.md`

**Agents**
- `canon/agents/strategy-architect.md`
- `canon/agents/risk-analyst.md`
- `canon/agents/market-analyst.md`
- `canon/agents/dev.md`
- `canon/agents/qa.md`
- `canon/agents/deployment-ops.md`

**Commands**
- `canon/commands/discover.md`
- `canon/commands/develop.md`
- `canon/commands/register.md`
- `canon/commands/ralph-cycle.md`
- `canon/commands/quick-dev.md`

---

## Steps

### 1. Pre-check: Core must be installed

Check whether `~/.claude/commands/fix-issue.md` exists.

If it does **not** exist, stop immediately and tell the user:

> Core is not installed. Run `/apply-core` first, then re-run `/apply-canon`.

Do not proceed until Core is confirmed present.

---

### 2. Inventory what exists

Read and note which of these already exist:
- `~/.claude/rules/domain-layering.md`
- `~/.claude/skills/prediction-markets.md`
- `~/.claude/skills/polymarket.md`
- `~/.claude/skills/risk-management.md`
- `~/.claude/skills/strategy-patterns.md`
- `~/.claude/skills/backtesting.md`
- `~/.claude/skills/arena-tracking.md`
- `~/.claude/skills/ralph-loop.md`
- `~/.claude/skills/canon-conventions.md`
- `~/.claude/agents/strategy-architect.md`
- `~/.claude/agents/risk-analyst.md`
- `~/.claude/agents/market-analyst.md`
- `~/.claude/agents/dev.md`
- `~/.claude/agents/qa.md`
- `~/.claude/agents/deployment-ops.md`
- `~/.claude/commands/discover.md`
- `~/.claude/commands/develop.md`
- `~/.claude/commands/register.md`
- `~/.claude/commands/ralph-cycle.md`
- `~/.claude/commands/quick-dev.md`

---

### 3. Ask the user what to install

Use AskUserQuestion with a single multi-select question. List each component
with a short description. Pre-label as recommended any component that is
missing from `~/.claude/`.

Components:
- **Rules** — domain-layering: enforces Canon's `Types → Config → Repo → Service → Runtime → UI`
  dependency direction via ast-grep rules with agent-friendly error messages
- **Skills** — 8 domain knowledge files: prediction markets, Polymarket platform,
  risk management, strategy patterns, backtesting, Arena tracking, Ralph Loop, Canon conventions
- **Agents** — 6 agent personas: strategy-architect, risk-analyst, market-analyst,
  dev, qa, deployment-ops (install to `~/.claude/agents/`)
- **Commands** — 5 workflow commands: discover, develop, register, ralph-cycle, quick-dev

---

### 4. Fetch selected files

Use WebFetch to download only the files needed for the user's selections from
the GitHub URLs above. Extract the raw file content from each response.

---

### 5. Install each selected component

#### Rules

Create `~/.claude/rules/` if it doesn't exist.

Write each rule file to `~/.claude/rules/<name>.md`. Safe to overwrite — Canon
rules have no user customization.

#### Skills

Create `~/.claude/skills/` if it doesn't exist.

Write each skill file to `~/.claude/skills/<name>.md`. Safe to overwrite.

#### Agents

Create `~/.claude/agents/` if it doesn't exist.

Write each agent file to `~/.claude/agents/<name>.md`. Safe to overwrite.

#### Commands

Write each command file to `~/.claude/commands/<name>.md`. Safe to overwrite.

---

### 6. Self-install

After completing the user's selections, also install this command itself to
`~/.claude/commands/apply-canon.md` by fetching:

```
https://raw.githubusercontent.com/DEGAorg/claude-code-config/main/commands/apply-canon.md
```

This makes `/apply-canon` available from any directory in future without
needing the repo cloned.

---

### 7. Post-install

Summarize what was installed or updated.

Remind the user of next steps:

> Canon artifacts are now installed. To scaffold a new Canon prediction-market
> project, run `canon_init` in your project directory. This creates the `.canon/`
> directory tree with strategy templates, the Ralph Loop config, and domain
> scaffolding. See the Canon MVP Technical Roadmap for full details.
