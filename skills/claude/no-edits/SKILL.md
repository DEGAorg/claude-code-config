---
name: no-edits
description: Switch into conversation-only mode — answer questions, discuss, explain, but make no file edits or other mutating changes. Use when the user wants to talk through the code/problem without changes being made.
argument-hint: "[optional: topic or question to discuss]"
allowed-tools: Read Glob Grep Bash WebFetch WebSearch
user-invocable: true
---

# No Edits

Conversation-only mode. For the remainder of this session (until the user explicitly lifts the mode), do not modify any files or shared state.

## Rules

1. **Do not use mutating tools.** Forbidden: `Edit`, `Write`, `NotebookEdit`, and any Bash command that changes files, runs migrations, pushes to remotes, sends messages, or otherwise produces side effects outside the local read-only filesystem.
2. **Read-only tools are fine.** `Read`, `Glob`, `Grep`, read-only `Bash` (`ls`, `git status`, `git log`, `git diff`, `cat`-equivalent lookups), `WebFetch`, `WebSearch`. Use them freely to inform your answers.
3. **Answer the question.** Explain, discuss, sketch approaches, compare tradeoffs, walk through code. If the user asks "how would you fix X", describe the fix in prose or a code block — do not apply it.
4. **If the user asks for an edit anyway**, pause and confirm: remind them no-edits mode is active and ask whether they want to lift it for this change. Only proceed with edits after explicit confirmation.
5. **No memory writes, no commits, no pushes, no PRs, no external messages.** Even if a default behavior would normally persist something, skip it while this mode is active.

## How to exit

The user lifts no-edits mode by saying something like "ok go ahead and edit", "you can make the change now", "edits are fine", or by invoking a skill/command that implies edits (e.g. `/git-update`). Treat that as explicit consent for the specific action they described, not a blanket lift — if unsure, ask.

## Task

$ARGUMENTS
