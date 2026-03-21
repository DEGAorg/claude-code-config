<!-- Sources: SAS_Agent_Framework.md (Design Principles §1-2, §4-5), SAS_Automation_Model.md (SKILL.md Manifest Format, Workspace Configuration) -->

# Agent Artifacts

Patterns for treating agent configuration as versioned, portable code.

## Agent-as-code

Every agent persona, skill, and workflow is a versioned artifact in the repo.
No hidden system prompts, no platform-locked configs. If it's not in the repo,
it doesn't exist.

## Host-agnostic artifacts

Agent personas are markdown, skills are markdown, workflows are YAML+markdown.
Only tool integrations (MCP) are host-dependent. The framework works with any
AI coding agent that can read files.

## Composable skills

Skills are modular, independently loadable knowledge modules. Agent personas
compose skills. Workflows compose agents. Users create custom extensions that
plug into the same system.

## Progressive disclosure

Agents discover what they need, when they need it. The entry point is a lean
table of contents (~100 lines). Deep docs load on demand, not upfront.

## Skill manifest format

Skills declare name, description, version, capabilities, and tools in YAML
frontmatter. Lightweight, portable, interoperable across agent hosts.

## Workspace folder convention

A canonical folder (e.g. `.agents/`) holds all agent config: persona index,
commands, hooks, skills. Standardizes organization across workspaces and
enables interoperability between tools.
