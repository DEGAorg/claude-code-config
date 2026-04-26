---
name: make-universal-skill
description: Create a new skill that works in both Codex (~/.codex/skills/) and Claude Code (~/.claude/skills/) from a single request. Writes two adapted SKILL.md files plus any shared resource files. Use when the user asks to create, author, or scaffold a new skill and wants it available in both harnesses.
---

# Make Universal Skill

Author a new skill that exists in **both** `~/.codex/skills/<name>/` and `~/.claude/skills/<name>/`. One logical skill, two harness-appropriate SKILL.md files, with any shared resource files (reference docs, playbooks, helper scripts) duplicated across both directories so either harness is self-sufficient.

## When to invoke

The user says "make a skill that...", "create a /foo skill", "I want a universal skill for X", or explicitly mentions "both harnesses" / "Claude and Codex."

## Input handling

The user message contains the skill request — a name and a purpose. If the name is unclear, derive a kebab-case slug from the purpose. If the purpose is too vague to write a useful skill, ask one focused clarifying question before proceeding. Don't demand a full spec.

## Workflow

1. Decide the name and shape. Pick a kebab-case slug. Decide whether the skill needs auxiliary files:
   - Reference doc (`reference.md`, `playbook.md`, `api-reference.md`) — for reusable knowledge loaded on demand.
   - Helper script (`scripts/*.py`, `scripts/*.sh`) — for deterministic work better done by code.
   - Credential wrapper + migration setup script — whenever the skill needs an API key or bot token. See **Secrets and credentials** below.
   - Just SKILL.md — most cases.

2. Check for collisions. Before writing, look at `~/.codex/skills/<name>/` and `~/.claude/skills/<name>/`. If either exists, ask whether to overwrite, rename, or edit the existing skill.

3. Write the Codex SKILL.md at `~/.codex/skills/<name>/SKILL.md`:

   ```markdown
   ---
   name: <slug>
   description: <one sentence: what it does + "Use when..." trigger phrasing>
   ---

   # <Title Case Name>

   <Body: direct imperatives. Generic tool references ("read", "search", "write"). Reference aux files as [playbook.md](playbook.md). No $ARGUMENTS placeholder. No trailing ## Task section. Terser than the Claude version.>
   ```

4. Write the Claude Code SKILL.md at `~/.claude/skills/<name>/SKILL.md`:

   ```markdown
   ---
   name: <slug>
   description: <same description, optionally with richer trigger phrasing>
   argument-hint: "[what the user types after /<slug>]"
   allowed-tools: <space-separated tool names — Bash Read Write Edit Glob Grep etc.>
   user-invocable: true
   ---

   # <Title Case Name>

   <Body: same ideas, but reference Claude tools by name (Glob, Grep, Read, Edit, Write, Bash, TaskCreate). Reference aux files as [playbook.md](playbook.md).>

   ## Task

   $ARGUMENTS
   ```

   The `## Task\n\n$ARGUMENTS` tail is how user-invoked args reach the skill body in Claude Code. Include it whenever `user-invocable: true`.

5. Write shared resource files to both directories with identical content. If you created a `playbook.md` or `api-reference.md`, write it to both locations. If you created helper scripts, write them under `scripts/` in both. Never symlink across `.codex`/`.claude` — copy.

6. Verify. After writing, list both directories and show the user what was created.

## Writing good skill bodies

- Lead with when to invoke and what input looks like.
- Numbered imperatives, not narration.
- Hardcode non-obvious constraints: rate limits, destructive-action confirmations, env vars to check first.
- Reference aux files instead of inlining long content.
- End with output format if the skill produces structured output.

## Secrets and credentials

Any skill that needs an API key, bot token, or other credential uses this
pattern. Do not ask the user to export credentials in shell startup files. Do
not store credentials in broad agent config that every subprocess can inherit.

1. Storage — scoped credential files at `chmod 600`, one per service:
   - Codex: `$CODEX_HOME/<service>.env` or `$HOME/.codex/<service>.env`
   - Claude Code: `$CLAUDE_HOME/<service>.env` or `$HOME/.claude/<service>.env`

   Plain `NAME=value` lines, one per required variable.

2. Setup script — if setup is non-trivial, write a companion script that:
   - Reads required values from the current environment or a hidden prompt.
   - Writes both scoped env files at 0600.
   - Strips any `export <VAR>=` lines from `~/.zshenv`, `.zprofile`, `.zshrc`, `.bash_profile`, `.bashrc`, `.profile`.
   - Runs `launchctl unsetenv <VAR>` and removes any matching LaunchAgent plist.

   zsh gotcha: inside functions, `local path="..."` silently clobbers `$PATH` because zsh aliases `$path` to the `$PATH` array. Use `target`, `env_path`, or similar.

3. Runtime loading — access credentials only through a
   `scripts/<service>-api.sh` wrapper that sources the scoped file per call.
   Never inline credential values in commands, examples, logs, or error
   messages. Generic loader:

   ```bash
   script_dir="$(cd "$(dirname "$0")" && pwd -P)"
   codex_home="${CODEX_HOME:-$HOME/.codex}"
   claude_home="${CLAUDE_HOME:-$HOME/.claude}"
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

   A Codex-installed skill prefers the Codex-scoped file and falls back to Claude's copy (vice versa for Claude), so either harness is self-sufficient.

4. SKILL.md must include a `## Credentials` section listing both generic file
   paths, the `chmod 600` requirement, and an instruction to use the wrapper
   rather than inline commands. Forbid echoing or logging credential values.

5. MCP-server skills are the exception. If the skill only configures an MCP
   server, follow that server's official scoped configuration guidance. Do not
   use broad config storage for skills that call REST APIs directly.

## Adaptation rules (Codex → Claude)

| Codex | Claude Code addition/change |
|---|---|
| generic "read", "search", "write" | can reference tools by name: Read, Grep, Glob, Edit, Write |
| no frontmatter extras | add `argument-hint`, `allowed-tools`, `user-invocable: true` |
| no $ARGUMENTS | add `## Task\n\n$ARGUMENTS` trailing section |
| bash commands | keep verbatim |
| aux file links `[playbook.md](playbook.md)` | keep verbatim |

## Common pitfalls

- Don't symlink across harnesses. Copy. A user may have only one harness installed.
- Don't forget `user-invocable: true` on the Claude side if the user expects `/<name>` to work.
- Keep the description trigger-rich — both harnesses route by description.
- Draft the body once, then mechanically apply adaptation rules for the second version.

## Output

Report the two SKILL.md paths written, any aux files written to both locations, and how each harness reaches the skill (`/<name>` in Claude Code; description match in Codex).
