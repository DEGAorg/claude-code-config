# Plan: Resume Test (Multi-Step Interrupt/Resume Smoke Test)

**Status:** In progress
**Created:** 2026-02-22

## Requirements

- Create `tests/scratch/` with three files: `file-a.md`, `file-b.md`, `file-c.md`
- Each file has distinct content so completion is verifiable
- Three sleep steps act as interrupt windows — one between each file creation
- `tests/scratch/` is gitignored (throwaway artifacts)
- Verify all three files exist at the end

## Approach

Seven steps: setup → sleep → create A → sleep → create B → sleep → create C → verify.
Sleep steps are deliberate interrupt windows. On resume, the agent reads this file,
finds the first unchecked box, and continues from there.

## Files to touch

| File | Change |
|------|--------|
| `.gitignore` | Add `tests/scratch/` |
| `tests/scratch/file-a.md` | Create with content |
| `tests/scratch/file-b.md` | Create with content |
| `tests/scratch/file-c.md` | Create with content |

## Progress log

- [x] Add `tests/scratch/` to `.gitignore` and create the directory
- [x] `sleep 20` — interrupt window A (interrupt here to test resume)
- [x] Create `tests/scratch/file-a.md`
- [x] `sleep 20` — interrupt window B (interrupt here to test resume)
- [x] Create `tests/scratch/file-b.md`
- [x] `sleep 20` — interrupt window C (interrupt here to test resume)
- [x] Create `tests/scratch/file-c.md`
- [x] Verify: `ls tests/scratch/` shows all three files

## Completion criteria

- [x] `tests/scratch/file-a.md`, `file-b.md`, `file-c.md` all exist
- [x] `tests/scratch/` is in `.gitignore`
- [x] `bash scripts/ralph-check.sh` exits 0 (5/5 passing)
