---
name: make-universal-skill
description: Create a new skill that works in both Claude Code (~/.claude/skills/) and Codex (~/.codex/skills/) from a single request. Writes two adapted SKILL.md files plus any shared resource files. Use when the user asks to create, author, or scaffold a new skill and wants it available in both harnesses.
argument-hint: "[skill name and what it does]"
allowed-tools: Bash Read Write Edit Glob Grep
user-invocable: true
---

# Make Universal Skill

Author a new skill that exists in **both** `~/.claude/skills/<name>/` and `~/.codex/skills/<name>/`. A single logical skill, two harness-appropriate SKILL.md files, with shared resource files (reference docs, playbooks, helper scripts) duplicated across both directories so either harness is self-sufficient.

## When to invoke

The user says something like "make a skill that...", "create a /foo skill", "I want a universal skill for X". Also fire when they explicitly say "for both Claude and Codex" or "in both harnesses."

## Input handling

`$ARGUMENTS` is the user's skill request. It usually contains a name and a purpose. If the name is unclear, derive a kebab-case slug from the purpose. If the purpose is too vague to write a useful skill, ask **one** focused clarifying question before proceeding (what should it actually *do* when invoked?). Don't demand a full spec — enough to draft.

## Workflow

1. **Decide the name and shape.** Pick a kebab-case slug (`my-skill`). Decide whether the skill needs auxiliary files:
   - A reference doc (`reference.md`, `playbook.md`, `api-reference.md`) — use when the skill benefits from loading a large body of reusable knowledge only when actually running.
   - A helper script (`scripts/*.py`, `scripts/*.sh`) — use when the skill does deterministic work better done by code than by the model.
   - A credential wrapper script + migration setup script — use whenever the skill needs an API key or bot token. See **Secrets and credentials** below for the full pattern.
   - Just SKILL.md — most cases.

2. **Check for collisions.** Before writing, glob `~/.claude/skills/<name>/` and `~/.codex/skills/<name>/`. If either exists, ask the user whether to overwrite, pick a different name, or edit the existing skill instead.

3. **Write the Claude Code SKILL.md** at `~/.claude/skills/<name>/SKILL.md` with this structure:

   ```markdown
   ---
   name: <slug>
   description: <one sentence: what it does + "Use when..." trigger phrasing so the skill router can match it>
   argument-hint: "[what the user should type after /<slug>]"
   allowed-tools: <space-separated tool names the skill actually uses — Bash Read Write Edit Glob Grep etc.>
   user-invocable: true
   ---

   # <Title Case Name>

   <Body: instructions written to Claude. Reference Claude tools by name (Glob, Grep, Read, Edit, Write, Bash, TaskCreate). Reference aux files with relative links: [playbook.md](playbook.md).>

   ## Task

   $ARGUMENTS
   ```

   The `## Task\n\n$ARGUMENTS` tail is how user-invoked args reach the skill body in Claude Code. Include it whenever `user-invocable: true`.

4. **Write the Codex SKILL.md** at `~/.codex/skills/<name>/SKILL.md` — same ideas, adapted:

   ```markdown
   ---
   name: <slug>
   description: <same one-sentence description, or a slightly terser variant>
   ---

   # <Title Case Name>

   <Body: same instructions, but:
   - Drop references to Claude-specific tool names; use generic verbs ("search for", "read the file", "run this bash command").
   - Drop the `$ARGUMENTS` placeholder — Codex passes args through conversation, not substitution.
   - Drop the `## Task` tail section.
   - Keep the tone terser and more imperative; Codex skills tend to be shorter.
   - Reference aux files with relative links the same way: [playbook.md](playbook.md).>
   ```

5. **Write shared resource files to BOTH directories** (identical content). If you created a `playbook.md` or `api-reference.md`, write it to both `~/.claude/skills/<name>/` and `~/.codex/skills/<name>/`. If you created helper scripts, write them under `scripts/` in both. Each harness must be self-sufficient — never symlink across `.claude`/`.codex`.

6. **Verify.** After writing, list both directories and show the user what was created. If the skill has a reference doc, confirm the link resolves in each location.

## Writing good skill bodies

- **Lead with when to invoke and what input looks like.** The router matches on the description; the body matches on the situation.
- **Instructions, not narration.** Numbered steps, imperatives. Not "I will then..."
- **Hardcode non-obvious constraints.** Rate limits, destructive-action confirmations, env vars to check first, format requirements.
- **Reference aux files instead of inlining long content.** A 400-line API reference belongs in `api-reference.md`, loaded on demand.
- **End with output format** if the skill produces structured output (tables, summaries, commit messages).

## Secrets and credentials

Any skill that needs an API key, bot token, or other credential follows this
pattern. Do not ask the user to export credentials in their shell startup files,
and do not store credentials in broad agent config that every subprocess can
inherit.

1. **Storage layout** — scoped credential files at `chmod 600`, one per service:
   - Claude Code: `$CLAUDE_HOME/<service>.env` or `$HOME/.claude/<service>.env`
   - Codex: `$CODEX_HOME/<service>.env` or `$HOME/.codex/<service>.env`

   Both contain plain `NAME=value` lines, one line per required variable. Example:
   ```
   # Written by setup_<service>_api_key.sh. chmod 600.
   # Sourced on demand by the /<service> skill; NOT auto-loaded into the shell.
   SERVICE_CREDENTIAL=...
   ```

2. **Setup script** — if setup is non-trivial, write a companion script that:
   - Reads required values from the current environment or a hidden prompt.
   - Writes both scoped credential files at 0600.
   - Strips any prior `export <VAR>=` lines from `~/.zshenv`, `.zprofile`, `.zshrc`, `.bash_profile`, `.bashrc`, `.profile`.
   - Runs `launchctl unsetenv <VAR>` and removes any matching LaunchAgent plist.

   **zsh gotcha:** inside functions, `local path="..."` silently clobbers `$PATH` because zsh aliases `$path` to the `$PATH` array. Use `target`, `env_path`, or similar.

3. **Runtime loading** — the skill accesses credentials only through a
   `scripts/<service>-api.sh` wrapper that sources the scoped file for the
   duration of each call. Never inline credential values in commands, examples,
   logs, or error messages. Generic loader block:

   ```bash
   script_dir="$(cd "$(dirname "$0")" && pwd -P)"
   claude_home="${CLAUDE_HOME:-$HOME/.claude}"
   codex_home="${CODEX_HOME:-$HOME/.codex}"
   case "$script_dir" in
     */codex/*) candidates=("$codex_home/<service>.env" "$claude_home/<service>.env") ;;
     *)         candidates=("$claude_home/<service>.env" "$codex_home/<service>.env") ;;
   esac
   env_file=""
   for f in "${candidates[@]}"; do
     [[ -r "$f" ]] && { env_file="$f"; break; }
   done
   [[ -z "$env_file" ]] && { echo "Credential file not found for <service>." >&2; exit 1; }
   set -a; source "$env_file"; set +a
   ```

   The harness-match ordering means a skill invoked from Codex prefers the Codex-scoped file and falls back to Claude's copy (and vice versa), so either harness is self-sufficient even if the user only migrated once.

4. **SKILL.md must document the credential layout:** a `## Credentials` section
   naming the two generic file paths, noting the `chmod 600` requirement, and
   instructing the skill to use the wrapper rather than inline commands. Forbid
   echoing or logging credential values.

5. **MCP-server skills are the exception.** If the skill only configures an MCP
   server, follow that server's official scoped configuration guidance. Do not
   use broad config storage for skills that call REST APIs directly.

## Adaptation rules (Claude → Codex)

| Claude Code | Codex equivalent |
|---|---|
| `Glob`, `Grep`, `Read`, `Edit`, `Write` tools | "search for", "read", "edit", "write" (generic) |
| `TaskCreate` for progress tracking | drop — Codex doesn't have equivalent; just execute |
| `$ARGUMENTS` placeholder | drop — user message carries the arg |
| `## Task\n\n$ARGUMENTS` trailing section | drop |
| `allowed-tools:` frontmatter | drop |
| `user-invocable: true` frontmatter | drop |
| `argument-hint:` frontmatter | drop |
| Links like `[playbook.md](playbook.md)` | keep — both harnesses resolve them |
| Bash commands | keep verbatim — both harnesses run bash |

## Common pitfalls

- **Don't symlink across harnesses.** Copy. A user may have only one harness installed, or the two paths may diverge.
- **Don't forget `user-invocable: true` on Claude side** if the user will type `/<name>`. Without it, the skill exists but isn't reachable by slash command.
- **Keep the description trigger-rich.** Both harnesses route by description. "Use when..." or "Use whenever..." phrasing helps.
- **Don't write the same skill twice from scratch.** Draft the body once (mentally or in a scratch), then mechanically apply the adaptation rules for the Codex version.

## Output

After creating the files, report:

- The two SKILL.md paths written
- Any aux files written (to both locations)
- The slash command the user can now type in Claude Code (`/<name>`)
- How Codex will invoke it (by description match, no slash prefix needed in Codex)

## Task

$ARGUMENTS
