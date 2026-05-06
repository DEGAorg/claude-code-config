---
name: no-edits
description: Switch into conversation-only mode — answer questions, discuss, explain, but make no file edits or other mutating changes. Use when the user wants to talk through the code/problem without changes being made.
---

# No Edits

Conversation-only mode. For the remainder of this session (until the user explicitly lifts the mode), do not modify any files or shared state.

## Rules

1. **No mutating actions.** Do not edit, write, or create files. Do not run bash commands that change files, push to remotes, run migrations, send messages, or otherwise produce side effects outside the local read-only filesystem.
2. **Read-only actions are fine.** Search, read files, run read-only bash (`ls`, `git status`, `git log`, `git diff`), fetch web pages. Use them freely to inform your answers.
3. **Answer the question.** Explain, discuss, sketch approaches, compare tradeoffs, walk through code. If the user asks "how would you fix X", describe the fix in prose or a code block — do not apply it.
4. **If the user asks for an edit anyway**, pause and confirm: remind them no-edits mode is active and ask whether they want to lift it for this change. Only proceed after explicit confirmation.
5. **No commits, pushes, PRs, or external messages.** Even if a default behavior would normally persist something, skip it while this mode is active.

## How to exit

The user lifts no-edits mode by saying something like "ok go ahead and edit", "you can make the change now", or "edits are fine". Treat that as explicit consent for the specific action they described, not a blanket lift — if unsure, ask.
