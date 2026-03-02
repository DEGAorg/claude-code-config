# Doc Garden

@description Scan docs/ and CLAUDE.md for stale references, broken cross-links, and outdated instructions. Opens a PR with fixes.

Perform a documentation health scan against the live codebase. Docs that
don't reflect code mislead both developers and agents. This command finds
and fixes the gap.

Execute every step below sequentially.

## 1. Build the file inventory

Collect two inventories:

- **Live files**: every source file currently in the repo (`rg --files`)
- **Doc references**: every file path, function name, command, and config key
  mentioned in `docs/`, `CLAUDE.md`, `README.md`, and `canon/CLAUDE.md`

## 2. Find stale references

Cross-check doc references against live files:

### 2a. Dead file references

References in docs to files that no longer exist:
- `path/to/file.ts` mentioned in a doc but not present in repo
- Module names, package paths, import paths that are outdated

Flag each as: `[DOC_FILE:LINE] references [MISSING_FILE] — file does not exist`

### 2b. Dead function/symbol references

Function names, class names, or config keys mentioned in docs that
no longer exist. Use `ast-grep` to verify each referenced symbol
exists in the codebase.

Flag each as: `[DOC_FILE:LINE] references [SYMBOL] — symbol not found in codebase`

### 2c. Broken cross-links

Links between doc files that point to non-existent sections or files:
- `[text](../other-doc.md#section)` where the file or anchor doesn't exist
- References like "see `docs/Foo.md`" where `docs/Foo.md` doesn't exist

### 2d. Outdated commands and instructions

- Slash commands referenced in docs that don't exist in `commands/`
- Tool names that have been replaced (e.g. mentioning `eslint` when
  the project uses `oxlint`)
- Config file formats or keys that have changed

### 2e. Phantom features

Docs describing features flagged with "coming soon", work-in-progress markers, or
describing behavior that doesn't exist in code. Use the Golden Principle:
no phantom features. Flag for human judgment — do not auto-delete.

## 3. Prioritize findings

- **P1** — broken reference that will actively mislead an agent or developer.
  Fix immediately.
- **P2** — outdated reference or instruction. Fix in this PR.
- **P3** — minor wording issue, phantom feature note, aspirational language.
  Flag in a doc comment; don't fix automatically.

## 4. Fix P1 and P2 findings

For each P1-P2 finding:

- Update the doc to reflect current reality
- If the doc section is fully obsolete, delete the section (not the whole file)
- If the fix requires human judgment (e.g. "is this feature actually removed?"),
  leave an inline comment `<!-- DOC-GARDEN: [question] -->` and continue

## 5. Verify

Read every modified doc once after edits to confirm no new breakage was
introduced by the fixes.

## 6. Create PR

- Branch: `docs/doc-garden-YYYY-MM-DD`
- Commit: `docs: doc-garden scan — [summary of main fixes]`
- PR title: `docs: doc-garden YYYY-MM-DD`
- PR body:
  - Total references scanned
  - Findings by severity (P1/P2/P3)
  - Files modified
  - Any items left for human judgment (inline `DOC-GARDEN` comments)
