---
name: test-driven-development
description: >
  Use when implementing any feature or bugfix, before writing implementation code. Enforces strict
  Red-Green-Refactor TDD cycle with vertical slicing. Triggers on: "implement", "add feature",
  "build", "create", "fix bug", "add test", "tdd". Does NOT trigger for: documentation,
  configuration, or deployment tasks.
---

# Test-Driven Development (TDD) Skill

You MUST follow strict Red-Green-Refactor TDD when implementing features or fixing bugs. Never write
implementation code without a failing test first. No exceptions.

---

## The TDD Cycle

Work in **vertical slices** — one behavior at a time, not horizontal layers.

### 🔴 RED: Write ONE Failing Test

1. Identify the smallest unit of behavior to implement next
2. Write exactly ONE test that specifies that behavior
3. Run the test — confirm it FAILS for the right reason
   - "Cannot find module" → wrong, the file exists but exports wrong thing
   - "Expected X but got undefined" → correct failure
4. Do NOT write another test until this one is green

### 🟢 GREEN: Write Minimal Implementation

1. Write the simplest code that makes the failing test pass
2. Fake it if needed (hardcoded return) — the next test will force generalization
3. Run ALL tests — every single one must pass
4. Do NOT refactor yet, do NOT add features the test doesn't require

### 🔵 REFACTOR: Eliminate Duplication

1. Look for: duplicated logic, unclear names, functions doing more than one thing
2. Refactor — run tests after every change to confirm nothing broke
3. Stop when the code is as simple as it can be and all tests pass
4. Commit this cycle: one commit per RED-GREEN-REFACTOR

Repeat for the next behavior.

---

## Test Pyramid

Maintain this ratio deliberately. Violations indicate design problems.

```
        /\
       /E2E\        ~10% — full user flows only (Playwright)
      /------\
     /Integr. \     ~20% — server actions + DB (Vitest + real DB)
    /----------\
   /    Unit    \   ~70% — pure functions, utils, components (Vitest)
  /--------------\
```

If you find yourself writing many integration tests for something that could be unit tested, the
code has too many responsibilities. Extract and unit test the logic.

---

## CoralSports Test Conventions

### Frameworks by Layer

| Layer | Framework | Command |
|-------|-----------|---------|
| Unit (logic, utils, components) | Vitest | `cd app && npm run test:unit` |
| Integration (server actions, DB) | Vitest | `cd app && npm run test:integration` |
| E2E (full user flows) | Playwright | `cd app && npm run test:e2e` |
| All | Vitest + Playwright | `cd app && npm run test` |

### File Placement

| Test type | Location | Example |
|-----------|----------|---------|
| Unit — library/util | `src/lib/__tests__/<module>.test.ts` | `src/lib/__tests__/format.test.ts` |
| Unit — component | Co-located: `src/components/<Name>.test.tsx` | `TournamentCard.test.tsx` |
| Integration — server action | `src/lib/actions/__tests__/<action>.integration.test.ts` | `tournament.integration.test.ts` |
| E2E | `e2e/<flow>.spec.ts` | `e2e/tournament-registration.spec.ts` |

### Naming Convention

Every test name must read as a specification sentence:

```
should <expected result> when <condition>
```

Examples:
- `should return 404 when tournament does not exist`
- `should reject registration when tournament is at capacity`
- `should not expose email when user is not authenticated`

Vague names like `works correctly` or `test 1` are rejected.

---

## Test Structure

### AAA Pattern — mandatory for every test

```typescript
describe('registerForTournament', () => {
  describe('when tournament has available slots', () => {
    test('should create a registration and decrement slot count', async () => {
      // Arrange — build the world the test needs
      const tournament = await tournamentFactory.create({ maxSlots: 10, currentSlots: 3 });
      const user = await userFactory.create();

      // Act — single operation under test
      const result = await registerForTournament(tournament.id, user.id);

      // Assert — observable outcomes only
      expect(result.success).toBe(true);
      const updated = await db.tournament.findUnique({ where: { id: tournament.id } });
      expect(updated?.currentSlots).toBe(4);
    });
  });
});
```

### Factory Pattern — required for test data

Never construct raw objects inline across tests. Use factories to keep tests readable and
resilient to schema changes.

```typescript
// test/factories/tournament.ts
export const tournamentFactory = {
  build: (overrides: Partial<Tournament> = {}): Tournament => ({
    id: crypto.randomUUID(),
    name: 'Test Tournament',
    maxSlots: 16,
    currentSlots: 0,
    status: 'OPEN',
    ownerId: crypto.randomUUID(),
    createdAt: new Date(),
    ...overrides,
  }),

  create: async (overrides: Partial<Tournament> = {}): Promise<Tournament> =>
    db.tournament.create({ data: tournamentFactory.build(overrides) }),
};
```

---

## ZOMBIE Edge Cases — Test All of These

For every function, explicitly test these categories before calling the feature done:

| Letter | Category | Example |
|--------|----------|---------|
| **Z** | Zero / empty | Empty bracket, zero participants, empty string input |
| **O** | One | Single participant, one match, one slot left |
| **M** | Many | 100 participants, max capacity, bulk operations |
| **B** | Boundaries | Exactly at max slots, exactly at deadline |
| **I** | Invalid input | Null, undefined, wrong type, malformed ID |
| **E** | Exceptions | DB down, network timeout, auth failure |

If a ZOMBIE case is missing, the feature is not done.

---

## Mocking Rules

### Mock these — they are external boundaries

- Next.js navigation (`useRouter`, `redirect`, `notFound`) in component tests
- Authentication session (`auth()`) — return a fake session object
- Time (`Date.now`, `new Date()`) — use `vi.setSystemTime()`
- External APIs (email, file upload, payments)
- `Math.random()` when testing non-deterministic behavior

### Never mock these

- **Prisma in integration tests** — use a real test database (local Postgres or SQLite via
  `DATABASE_URL=file:./test.db` in `.env.test`)
- **Pure functions** — test them directly, they have no side effects to isolate
- **Business logic** — if you mock the thing under test, you're testing nothing

### Isolation — required for every test suite

```typescript
beforeEach(async () => {
  // Reset all mocks — no bleed between tests
  vi.clearAllMocks();

  // Clean DB tables in reverse dependency order
  await db.registration.deleteMany();
  await db.tournament.deleteMany();
  await db.user.deleteMany();
});
```

---

## Testing Server Actions

Server actions are imported and called directly — no HTTP layer needed.

```typescript
// src/lib/actions/__tests__/tournament.integration.test.ts
import { registerForTournament } from 'src/lib/actions/tournament';
import { auth } from 'src/lib/auth';

vi.mock('src/lib/auth');

test('should reject unauthenticated caller', async () => {
  vi.mocked(auth).mockResolvedValue(null); // no session

  const result = await registerForTournament('tournament-id');

  expect(result).toEqual({ success: false, error: 'Unauthorized' });
});
```

Always test:
1. Unauthenticated caller (no session)
2. Unauthorized caller (wrong user, not owner)
3. Invalid input (Zod validation)
4. Happy path
5. Edge cases (full tournament, expired deadline, etc.)

---

## Testing React Components

Use `@testing-library/react`. Test what the user sees and does, not internals.

```typescript
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { TournamentCard } from 'src/components/TournamentCard';

test('should show join button when tournament is open and user is not registered', () => {
  render(<TournamentCard tournament={tournamentFactory.build({ status: 'OPEN' })} />);

  expect(screen.getByRole('button', { name: /join/i })).toBeInTheDocument();
});

test('should disable join button when tournament is at capacity', async () => {
  const tournament = tournamentFactory.build({ maxSlots: 10, currentSlots: 10 });
  render(<TournamentCard tournament={tournament} />);

  expect(screen.getByRole('button', { name: /join/i })).toBeDisabled();
});
```

Rules for component tests:
- Use `screen.getByRole` over `getByTestId` — roles are accessible and user-facing
- Use `userEvent` over `fireEvent` — it simulates real browser events
- Test every conditional render branch
- Never assert on className or style — assert on behavior and content

---

## Coverage Philosophy

Coverage is a **floor, not a goal**. 80% coverage that tests the right things beats 100% coverage
of trivial code.

- Coverage tells you what is **definitely not tested**
- It does not tell you if tests are **meaningful**
- Never write a test just to increase coverage
- Never skip testing a behavior because coverage is "already high enough"

To verify tests are meaningful: break the implementation deliberately and confirm the test fails.
If it doesn't fail, the test is not testing what you think it is.

---

## Running Tests

```bash
cd app

# Fast feedback loop during development
npx vitest run src/path/to/file.test.ts

# Full unit + integration suite
npm run test

# With coverage report
npm run test:coverage

# E2E (requires running dev server)
npm run test:e2e

# Watch mode during active development
npm run test:watch
```

---

## Rules

1. **Never** write implementation before a failing test
2. **Never** write more than one failing test at a time
3. **Never** modify a test to make it pass — fix the implementation
4. **Never** mock what you're testing
5. **Always** verify the test fails for the right reason before going GREEN
6. **Always** run the full suite before committing
7. **Always** test auth failure as the first case in every server action test
8. **Always** cover all ZOMBIE edge cases before marking a feature complete
9. Each test must be fully independent — no shared mutable state, no execution order dependency
10. Flaky tests must be fixed or deleted immediately — a flaky test is worse than no test
