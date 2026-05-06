---
name: ls
description: List files and directories in the current working directory (or a specified path) as a readable multi-column markdown table. Use when the user wants to see folder contents.
argument-hint: [path]
allowed-tools: Read Glob
user-invocable: true
---

# List Directory Contents

List files and directories formatted as a 3-column markdown table, sorted alphabetically. Directories are marked with a trailing `/`.

## Instructions

1. Use the Glob tool with pattern `*` on the target directory (use the argument as the path if provided, otherwise use the current working directory).
2. Also glob for directories specifically using pattern `*/` on the same path to identify which entries are directories.
3. Sort all entries alphabetically (case-insensitive).
4. Append `/` to directory names.
5. Format the results into a 3-column markdown table with headers `| Name | Name | Name |`.
6. Fill columns left-to-right, row by row. If the last row has fewer than 3 entries, leave remaining cells empty.
7. Show a total count at the bottom: `**N items** (X files, Y directories)`

## Example Output

| Name | Name | Name |
|---|---|---|
| README.md | canon-slides/ | docs/ |
| index.ts | package.json | specs/ |
| tsconfig.json | | |

**7 items** (4 files, 3 directories)

## Task

$ARGUMENTS
