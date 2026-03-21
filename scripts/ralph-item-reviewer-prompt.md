# Ralph Loop — Per-Item Reviewer Prompt

You are reviewing ONE item from a completed plan. Evaluate whether this
specific item was implemented correctly. You do not review the whole plan.

## Item

**Item:** {ITEM_TEXT}

## Evidence

The worker wrote this handoff summary for this item:

```
{ITEM_HANDOFF}
```

## What to do

### Step 1: Decompose the item into clauses

Split the item description into individual requirements (clauses). Each
distinct action, output, or constraint is a separate clause.

Example: "add clause decomposition step: split item into clauses, verify
each, list results, FAIL if any clause unverified" has four clauses:
1. Add clause decomposition step
2. Split item into clauses
3. Verify each clause
4. FAIL if any clause unverified

List every clause before proceeding. If the item is a single simple
statement, it has one clause.

### Step 2: Verify each clause

For each clause:
1. Read the changed files mentioned in the handoff summary.
2. Find concrete evidence that the clause is satisfied — a specific line,
   function, test, or behavior change.
3. Record the result: VERIFIED (with evidence) or UNVERIFIED (with reason).

Do not skip clauses. Do not infer satisfaction from related work — each
clause needs its own evidence.

### Step 3: Decide PASS or FAIL

- **PASS** — every clause is VERIFIED
- **FAIL** — any clause is UNVERIFIED

A partial completion is a FAIL. If 3 of 4 clauses are verified but 1 is
not, the item FAILs.

## Decision

Write `{REVIEW_DIR}/item-{ITEM_NUM}-review.txt`. The file must follow
this exact format.

If PASS:
```
PASS

CLAUSES:
1. <clause text> — VERIFIED: <evidence>
2. <clause text> — VERIFIED: <evidence>
```

If FAIL:
```
FAIL

CLAUSES:
1. <clause text> — VERIFIED: <evidence>
2. <clause text> — UNVERIFIED: <what is missing>

FINDING: <summary of what is wrong or missing, with file:line>
ACTION: <what must be fixed>
```

## Rules

- Evaluate only this item — ignore other items in the plan
- Read the actual files, not just the summary
- Decompose before deciding — never skip the clause list
- Be strict: partial completion is a FAIL, even if most clauses pass
- Do not implement fixes — only evaluate
- You MUST write the review file before stopping
