# Canon Domain Layering Rule

Enforces the Canon dependency direction: `Types → Config → Repo → Service → Runtime → UI`

Inner layers must never import from outer layers.

---

## Allowed dependency direction

```
Types      ← no imports from Canon layers (pure domain types)
  ↓
Config     ← may import Types
  ↓
Repo       ← may import Types, Config
  ↓
Service    ← may import Types, Config, Repo
  ↓
Runtime    ← may import Types, Config, Repo, Service
  ↓
UI         ← may import anything (presentation layer)
```

---

## ast-grep Rule

```yaml
# canon/rules/domain-layering.yml
id: canon-domain-layering-violation
language: TypeScript
severity: error
message: |
  Domain layering violation: inner layer importing from outer layer.

  WHY: Canon's architecture enforces a strict dependency direction:
    Types → Config → Repo → Service → Runtime → UI
  Outer layers (Runtime, UI) may import from inner layers.
  Inner layers (Types, Config, Repo, Service) must NOT import from outer layers.
  This keeps domain logic independent of infrastructure and presentation.

  HOW TO FIX:
  1. Move the shared logic to a layer both modules can import from.
  2. Use dependency injection — pass the outer-layer value into the inner
     layer at the call site, don't import it.
  3. If the import is genuinely needed, reconsider the layer assignment.

  DOCS: See canon/docs/architecture.md for the full layer definitions.

rule:
  any:
    # Service importing from Runtime
    - pattern: import $$ from "$PATH"
      inside:
        path: "src/service/**"
      has:
        field: source
        regex: "src/runtime/"
    # Repo importing from Service or Runtime
    - pattern: import $$ from "$PATH"
      inside:
        path: "src/repo/**"
      has:
        field: source
        regex: "src/(service|runtime)/"
    # Config importing from Repo, Service, or Runtime
    - pattern: import $$ from "$PATH"
      inside:
        path: "src/config/**"
      has:
        field: source
        regex: "src/(repo|service|runtime)/"
    # Types importing from anything else
    - pattern: import $$ from "$PATH"
      inside:
        path: "src/types/**"
      has:
        field: source
        regex: "src/(config|repo|service|runtime)/"
```

---

## Registration

Add to `ast-grep.yml` at the Canon project root:

```yaml
ruleDirs:
  - canon/rules
```

Run: `ast-grep scan -r canon/rules/domain-layering.yml`

---

## Layer definitions

| Layer | Path pattern | Responsibility |
|-------|-------------|----------------|
| Types | `src/types/` | Domain types, interfaces, enums. No logic. |
| Config | `src/config/` | Configuration loading and validation. |
| Repo | `src/repo/` | Data access: DB queries, API clients, file I/O. |
| Service | `src/service/` | Business logic. Orchestrates Repo calls. |
| Runtime | `src/runtime/` | Agent runtime, event loops, orchestration. |
| UI | `src/ui/` | Presentation only. Depends on Runtime for state. |
