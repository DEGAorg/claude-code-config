# Custom Linter Authoring

How to write `ast-grep` rules with agent-friendly error messages. Use this skill
when a recurring mistake has been corrected twice in code review — the third time,
encode it as a lint rule instead of repeating the review comment.

---

## The Promote-Rule Pattern

> Correct an agent twice on the same thing → encode it as a lint rule, not an AGENTS.md instruction.

AGENTS.md instructions compete for context space and get forgotten. Lint rules run
every time, catch violations structurally, and inject the fix directly into the
failing agent's context.

Promote to a rule when:
- The same code pattern has been flagged in review ≥2 times
- The fix is mechanical (not judgment-dependent)
- The violation is structural (detectable by AST, not semantic)

---

## Rule File Structure

Place rules in `rules/` (Core) or `canon/rules/` (Canon-specific). Each `.yml`
file is one rule. Register rules in `ast-grep.yml` at the repo root.

```yaml
# rules/no-raw-console-log.yml
id: no-raw-console-log
language: TypeScript
severity: error
message: |
  Use structured logging instead of console.log.

  WHY: console.log output is unstructured and invisible to log aggregators.
  It also violates the Golden Principle: structured logging everywhere.

  HOW TO FIX:
    Replace: console.log("msg", data)
    With:    logger.info({ ...data }, "msg")

  Where logger is imported from the shared logging utility:
    import { logger } from "@/lib/logger"

  DOCS: See docs/logging-patterns.md for the full logging guide.
rule:
  pattern: console.log($$$)
```

---

## Agent-Friendly Error Message Design

Standard linter messages tell you *what* is wrong. Agent-friendly messages tell
you *what*, *why*, *how to fix*, and *where to learn more* — everything needed
to fix the issue without a follow-up search.

### Template

```
[WHAT]: One-line description of what the rule prohibits.

WHY: One sentence explaining the architectural or correctness reason.

HOW TO FIX:
  Replace: [bad pattern]
  With:    [good pattern]

[Optional: note about when the rule doesn't apply / how to suppress]

DOCS: [pointer to the canonical doc on this topic]
```

### What makes a message agent-friendly

| Property | Why it matters |
|----------|---------------|
| Includes the fix | Agent applies it directly without searching |
| Shows before/after | Unambiguous transformation |
| Explains the why | Agent can generalize to similar cases |
| Points to docs | Agent can get deeper context if needed |
| No jargon | No knowledge of internal naming required |

---

## Common ast-grep Patterns

### Prohibit a function call

```yaml
rule:
  pattern: $FUNC($$$)
  inside:
    kind: expression_statement
  has:
    field: function
    regex: "^console\\.log$"
```

### Require a specific import before using a symbol

```yaml
rule:
  all:
    - pattern: $LOGGER.info($$$)
    - not:
        precedes:
          pattern: import { logger } from "@/lib/logger"
```

### Enforce dependency direction (imports must not cross layer boundaries)

```yaml
# Catches service layer importing from runtime layer
rule:
  pattern: import $$ from "$PATH"
  inside:
    path: "src/service/**"
  has:
    field: source
    regex: "src/runtime/"
```

### Detect duplicated utility (hand-rolled fetch wrapper)

```yaml
rule:
  pattern: |
    fetch($URL, {
      method: $METHOD,
      headers: $$$,
      body: $$$
    })
```

---

## ast-grep.yml Registration

```yaml
# ast-grep.yml (repo root)
ruleDirs:
  - rules
  - canon/rules
```

Run all rules: `ast-grep scan`
Run one rule: `ast-grep scan -r rules/no-raw-console-log.yml`

---

## When NOT to Write a Rule

- The violation is judgment-dependent ("is this abstraction premature?")
- The rule would have > 5% false positive rate — noisy rules get suppressed
- The fix is context-dependent and can't be expressed as a pattern

In these cases, keep the guidance in a skill file or AGENTS.md section,
not a lint rule.
