---
name: code-review
description: >
  Use when self-reviewing branch changes before committing or opening a PR. Triggers on: "review my
  code", "code review", "self-review", "check my changes", "review before commit". Does NOT trigger
  for: reviewing someone else's PR (use review-pr skill), writing tests (use TDD skill), or
  committing code.
---

# Code Review

Self-review current branch changes against CoralSports project standards. Produces a structured,
actionable report. Every issue must have a file:line reference and a concrete fix — no vague
commentary.

## Severity Taxonomy

| Level | Label | Definition |
|-------|-------|------------|
| 🔴 | **BLOCK** | Correctness bug, security vulnerability, data loss risk, or broken contract. Merge is forbidden. |
| 🟡 | **WARN** | Violates project standards, degrades performance, or will cause future breakage. Must fix before merge. |
| 🔵 | **NIT** | Style, naming, or minor improvement. Fix if trivial; otherwise note and move on. |

Verdict rules: any BLOCK → **BLOCK**. No BLOCKs but WARNs → **REQUEST CHANGES**. Only NITs or
nothing → **APPROVE**.

---

## Step 0: Pre-Flight — Run Automated Tools First

Before any manual review, run these in parallel and fix every failure. Manual review is for judgment
calls, not mechanical issues.

```bash
cd app
npx tsc --noEmit                 # Type errors
npm run lint                     # ESLint violations
npm run test                     # Failing tests
git diff main...HEAD --stat      # Scope of changes
git diff main...HEAD             # Full diff
```

If any tool fails, stop and fix before continuing.

---

## Step 1: Load Context

Read in parallel:

- `app/CLAUDE.md` + `app/AGENTS.md` — project rules and Next.js version guidance
- `TECHNICAL_ARCHITECTURE.md` — data model, service boundaries, auth flow
- Schema: `app/prisma/schema.prisma` — source of truth for data shapes

---

## Step 2: Review Discipline

Spin up parallel review agents by domain:

- **Agent A** — Security + Auth
- **Agent B** — Type safety + correctness
- **Agent C** — Performance + database
- **Agent D** — Tests + observability

For each changed file, trace the full lifecycle:

```
request → auth check → input validation → business logic → DB → response → error path
```

Every step must be accounted for. A missing auth check is a BLOCK even if the code is otherwise
clean.

---

## Step 3: Checklist

### Security & Auth

| Check | Severity if violated |
|-------|---------------------|
| Every server action authenticates the caller at the top — before any logic | 🔴 BLOCK |
| No sensitive fields (password, token, internal IDs) returned to the client | 🔴 BLOCK |
| All user input validated with Zod (or equivalent) before touching Prisma | 🔴 BLOCK |
| No raw SQL string interpolation | 🔴 BLOCK |
| Secrets and env vars accessed only server-side; never `NEXT_PUBLIC_` for secrets | 🔴 BLOCK |
| Authorization checked (user owns resource) not just authentication (user is logged in) | 🔴 BLOCK |

### Type Safety

| Check | Severity if violated |
|-------|---------------------|
| No `any` in changed TypeScript code | 🟡 WARN |
| No `@ts-ignore` or `@ts-expect-error` without a comment explaining why | 🟡 WARN |
| No type assertions (`as X`) that paper over a real type mismatch | 🟡 WARN |
| Zod schemas are the single source of truth for external input shapes | 🟡 WARN |
| `unknown` used instead of `any` for untrusted data | 🔵 NIT |

### Next.js App Router

| Check | Severity if violated |
|-------|---------------------|
| `'use client'` present only on components that actually use browser APIs or hooks | 🟡 WARN |
| No `useState`/`useEffect` in Server Components | 🔴 BLOCK |
| Data fetching is parallel (`Promise.all`) not sequential when fetches are independent | 🟡 WARN |
| `cache()` / `revalidatePath()` / `revalidateTag()` used correctly; no stale data risk | 🟡 WARN |
| New routes have `loading.tsx` for streaming and `error.tsx` for error boundaries | 🔵 NIT |
| Heavy client-side imports use `dynamic(() => import(...), { ssr: false })` | 🟡 WARN |
| `notFound()` and `redirect()` called correctly in server context (not in try/catch) | 🟡 WARN |

### React Correctness

| Check | Severity if violated |
|-------|---------------------|
| List items have stable, unique `key` props — never array index for dynamic lists | 🟡 WARN |
| No derived state in `useState` — compute inline or with `useMemo` | 🟡 WARN |
| `useEffect` has a reason to exist — not used for data fetching or event handlers | 🟡 WARN |
| `useMemo`/`useCallback` only where profiling shows a real cost — not preemptively | 🔵 NIT |
| Component does one thing; split if it handles unrelated concerns | 🔵 NIT |

### Database & Prisma

| Check | Severity if violated |
|-------|---------------------|
| Queries use `select` to fetch only needed fields — no over-fetching | 🟡 WARN |
| No N+1: related records fetched with `include` or a single join, not in a loop | 🔴 BLOCK |
| Multi-step mutations use `$transaction` | 🟡 WARN |
| Schema changes include the corresponding migration file | 🔴 BLOCK |
| Queries that can return nothing handle the `null` case explicitly | 🟡 WARN |

### Error Handling

| Check | Severity if violated |
|-------|---------------------|
| No empty `catch` blocks | 🔴 BLOCK |
| No caught errors that are silently swallowed — log or rethrow | 🔴 BLOCK |
| Server actions return a typed result (`{ success, error }`) — never throw to the client | 🟡 WARN |
| Error messages include context (what failed, what input caused it) | 🟡 WARN |

### Code Quality

| Check | Severity if violated |
|-------|---------------------|
| No magic numbers — extract named constants | 🟡 WARN |
| Functions ≤ 50 lines, cyclomatic complexity ≤ 8 | 🟡 WARN |
| No dead code, unused imports, or unreachable branches | 🟡 WARN |
| No commented-out code — delete it | 🔵 NIT |

### Testing

| Check | Severity if violated |
|-------|---------------------|
| New behavior has at least one test | 🔴 BLOCK |
| Error paths are tested, not just the happy path | 🟡 WARN |
| Tests assert on observable behavior, not internal state | 🟡 WARN |
| No test modifies shared state without cleanup | 🟡 WARN |

### Accessibility

| Check | Severity if violated |
|-------|---------------------|
| Interactive elements (`button`, `input`) have accessible labels | 🟡 WARN |
| Color is not the sole indicator of state | 🔵 NIT |
| Focus management correct on modals and dialogs | 🟡 WARN |

---

## Step 4: Output Format

```markdown
## Code Review — <branch-name>

**Verdict:** BLOCK | REQUEST CHANGES | APPROVE

---

### 🔴 BLOCK — Must fix before merge

- `src/app/actions/tournament.ts:42` — Server action calls `db.tournament.update()` before
  checking that the caller owns the tournament. Any authenticated user can update any tournament.
  **Fix:** Add `if (tournament.ownerId !== session.user.id) throw new Error('Forbidden')` after
  fetching the tournament, before the update.

### 🟡 WARN — Should fix before merge

- `src/components/TournamentCard.tsx:18` — List rendered with `key={index}`. If items reorder,
  React will remount instead of reconcile.
  **Fix:** Use `key={tournament.id}`.

### 🔵 NIT — Optional

- `src/lib/utils/format.ts:7` — `formatDate` could use `Intl.DateTimeFormat` instead of manual
  string slicing. More locale-aware and less fragile.

---

### Checklist

| Category | Status | Notes |
|----------|--------|-------|
| Security & Auth | ✅ | |
| Type safety | ✅ | |
| Next.js conventions | ⚠️ | See WARN above |
| React correctness | ❌ | key prop issue |
| Database | ✅ | |
| Error handling | ✅ | |
| Tests | ✅ | |
| Accessibility | ✅ | |
```

---

## Rules

1. **No `file:line`, no issue** — vague descriptions are rejected.
2. **Every BLOCK and WARN needs a fix** — show the exact code change, not a direction.
3. **Run tools first** — if `tsc` or tests fail, fix those before writing the report.
4. **Auth before everything** — a missing auth check is always BLOCK, never WARN.
5. **Never approve an empty catch** — silently swallowed errors always surface as production bugs.
6. **N+1 in a loop is always BLOCK** — it degrades under load and causes real outages.
7. **One review per PR** — do not split the report across multiple messages.
