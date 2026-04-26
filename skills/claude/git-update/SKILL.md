---
name: git-update
description: Stage, commit, and push the current git work safely. Use when the user asks to "git update", commit current changes, ship the current branch, or stage, commit, and push a set of completed edits to the remote repository.
argument-hint: "[optional: files or scope to commit]"
allowed-tools: Bash Read Grep
user-invocable: true
---

# Git Update

Determine the active repository first. If the current working directory is
inside a nested repository, operate on that repository; otherwise operate on the
parent repository. Confirm with `git rev-parse --show-toplevel`.

Inspect the current state before changing anything:

```bash
git status
git diff --staged
git diff
git log --oneline -5
```

Stop if there is nothing relevant to commit. If the tree is clean, or only
unrelated/generated noise is present, report that and do not create an empty
commit.

Stage only the files relevant to the recent work. Prefer explicit paths over
`git add -A` or `git add .` so credentials, env files, binaries, and unrelated
churn do not get swept in accidentally.

Write a concise commit message that explains the reason for the change, not a
file-by-file summary. Match the repository's recent commit style when it is
clear.

Commit non-interactively. Prefer `git commit -F -` with piped message content
or `git commit -m` for a short single-line message. Do not open an editor.

Before pushing, inspect the branch and repository policy. Never force push. Do
not push directly from `main`, `master`, or a branch that matches the repo's
configured PR target. Stop and tell the user to create a feature branch and PR
instead.

Push only a non-trunk feature branch to the current branch's tracking remote. If
no upstream is configured, detect the branch name and push with
`git push -u origin <branch>`.

If push fails because the environment blocks network access or needs approval,
request escalation rather than stopping at the local commit.

Report the result with the commit hash and whether the push succeeded.

## Task

$ARGUMENTS
