# Tools

This document describes the built-in agent tools, how they are grouped, and how they work at a high level.

## Overview

The tool system is implemented as a typed tool registry that returns a `ResponseToolsTable`.
Two tool sets are exposed:

- `getReadTools()`: inspection and analysis tools only.
- `getAllTools()`: read tools plus file-modification tools.

At runtime, each tool implementation is wrapped with timing traces before registration.

## Execution Model

Most command-oriented tools execute OS processes using `startProcess(...)` with:

- `poUsePath` so binaries are resolved from `PATH`.
- `poStdErrToStdOut` so stderr is captured in a single stream.

Outputs are read line-by-line, then normalized before returning.

## Shared Safety and Output Handling

The registry includes shared helpers used by many tools:

- Argument validation for required JSON fields.
- Working-directory resolution with fallback to current directory.
- ANSI escape stripping from tool output.
- Control-character analysis for diagnostics.
- Output truncation with a max-character guardrail.

File-editing helpers also normalize line handling:

- Ensure trailing newline for non-empty writes.
- Split/join helpers that avoid accidental extra blank lines.
- Change snippets with contextual line numbers for edit tools.

## Tool Modes

### Read Mode

Read mode includes:

- `system_pwd`
- `system_ls`
- `nim_check`
- `nimble_test`
- `nim_version`
- `find_files`
- `read_file`
- `awk`
- `ripgrep`
- `git_status`
- `git_diff`
- `create_issue`

### All-Tools Mode

All-tools mode includes every read tool plus:

- `write_file`
- `move_file`
- `sed_edit`
- `create_dir`
- `insert_lines`
- `delete_lines`
- `replace_lines`
- `append_file`

## Read Tool Details

### `system_pwd`

Returns the working directory by running `pwd` in a resolved working directory.

### `system_ls`

Runs `ls <path>` and returns directory contents.

### `nim_check`

Runs `nim check` for each file in the provided `files` array.
Supports backend overrides (`backend` or `cpp`).
Aggregates per-file success/failure lines.

### `nimble_test`

Runs `nimble test` in the selected working directory.

### `nim_version`

Runs `nim --version` and returns version output.

### `find_files`

Finds files by regex against full file paths.
Supports recursive and non-recursive traversal.
Compiles and validates the regex before search.

### `read_file`

Reads full file content and applies output truncation safeguards.

### `awk`

Runs `awk <script> <file_path>` and returns processed output.

### `ripgrep`

Runs `rg` for content search.
Supports case-insensitive search, line numbers, and max-count behavior.
Returns "No matches found" on exit code `1`.

### `git_status`

Runs `git status` and returns repository status text.

### `git_diff`

Runs `git diff` and returns unstaged changes.

### `create_issue`

Collects issue definitions as structured JSON for later emission.
This tool records issue payloads; it does not create remote issues directly.

## Write Tool Details

### `write_file`

Overwrites file content.
Creates parent directories when missing.
Normalizes trailing newline behavior.

### `move_file`

Moves a file from `src_path` to `dest_path`.
Creates destination parent directories when needed.

### `sed_edit`

Runs `sed` edits with optional in-place mode.
Useful for straightforward single-line or pattern-based edits.

### `create_dir`

Creates a directory path recursively.

### `insert_lines`

Inserts multiline content after a 1-based line index (`0` inserts at top).
Writes updated file and returns a contextual snippet.

### `delete_lines`

Deletes an inclusive 1-based line range.
Writes updated file and returns a contextual snippet.

### `replace_lines`

Replaces an inclusive 1-based line range with new multiline content.
Writes updated file and returns a contextual snippet.

### `append_file`

Appends multiline content to end-of-file.
Creates parent directories if needed and returns a contextual snippet.

## Notes for Prompting and Agent Behavior

- Use read mode for analysis-only tasks.
- Use all-tools mode for tasks that require filesystem changes.
- Prefer specialized tools over generic shell execution.
- For content search, use `ripgrep`; for path search, use `find_files`.
- For deterministic edits with reviewable context, prefer line-edit tools (`insert_lines`, `replace_lines`, `delete_lines`) when applicable.
