---
name: ls
description: List files and directories in the current working directory or a specified path as a readable 3-column markdown table. Use when the user wants to see folder contents.
---

# List Directory Contents

List the visible entries of a directory as a 3-column markdown table, sorted alphabetically. Directories are marked with a trailing `/`.

Use the bundled helper:

```bash
python3 "${CODEX_HOME:-$HOME/.codex}/skills/ls/scripts/ls_table.py" [path]
```

## Rules

1. If no path is provided, use the current working directory.
2. If the target does not exist, report that instead of fabricating output.
3. If the target is a file rather than a directory, say so instead of trying to list it.
4. The output must be a markdown table with headers `| Name | Name | Name |`.
5. Sort entries case-insensitively.
6. Append `/` to directory names.
7. Show a final count line in the form `**N items** (X files, Y directories)`.
8. Match shell-style `*` behavior by excluding hidden entries unless the user explicitly asks for them.
