# Harden core-init GitHub detection

**Source:** `ace/notes/linux-issues.md` issue 1
**Analysis:** `ace/notes/linux-issues-analysis.md`

## Problem

Running `/core-init` on a fresh Linux repo produced a `dega-core.yaml`
with the `github:` block completely missing. The command template includes
the block, but the LLM-executed procedure skipped it silently. No error
was shown.

Since `dega-core.yaml` drives `GH_SYNC` detection, a missing `github:`
block cascades into orchestrator plan-path failures (issues 2-4).

## Approach

1. Make the `github:` block mandatory in the template — always write it,
   even if detection fails (with `sync: false` and a TODO comment).
2. Add a validation step after writing: re-read the file and verify the
   `github:` key exists. If missing, error loudly.
3. Add explicit instructions in the command that the github block must
   NEVER be omitted, with a validation gate.

## Requirements

1. Every `dega-core.yaml` produced by `/core-init` must contain a `github:`
   block, regardless of whether `gh` is installed or GitHub remote exists.
2. If `gh` is not installed or not authenticated, `sync: false` with a
   comment explaining why.
3. Validation step catches the missing block and re-adds it if needed.

## Progress log

- [ ] Update `commands/core-init.md` step 4: add fallback when `gh` not installed — write `sync: false` with comment
- [ ] Update `commands/core-init.md` step 5: add bold instruction that github block must NEVER be omitted (deps: 1)
- [ ] Add validation gate after write: re-read `dega-core.yaml`, check `github:` key exists, error if missing (deps: 2)
- [ ] Add test case: run core-init logic against a repo with no `gh` CLI — verify github block is present with `sync: false` (deps: 3)

## Completion criteria

- [ ] core-init command always produces a `github:` block in `dega-core.yaml`
- [ ] Missing `gh` CLI results in `sync: false` with explanatory comment
- [ ] Validation gate catches missing block and reports error
- [ ] shellcheck passes on any new scripts
