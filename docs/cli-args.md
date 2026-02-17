# CLI Arguments

This document captures the current command-line argument behavior used by the existing implementation, so it can be reproduced in Typos.

## Usage

```bash
<binary> [options] [--prompt "text" | < prompt.txt]
```

Prompt sources:

- `--prompt` / `-p` if provided.
- otherwise stdin is read.
- empty prompt is an error.

## Defaults

- `--model`: `grok-code-fast-1`
- `--provider`: `xai`
- `--api-env-var`: `OPENAI_API_KEY`
- `--base-url`: empty string (provider default behavior)
- `--temperature`: `1.0`

## Supported Flags

### Core Model / Provider

- `--model=MODEL`
- `--provider=PROVIDER`
- `--api-env-var=VAR`
- `--base-url=URL`
- `--temperature=FLOAT`

Temperature validation:

- must parse as float
- must be in `[0.0, 2.0]`
- invalid values exit with error

### Prompt Input

- `-p, --prompt=TEXT`
- `--system-prompt-file=FILE`

`--system-prompt-file` appends additional instructions to the generated system prompt.

### Tool Mode

- `--read-tools`
- `--yolo`

Behavior:

- if neither flag is set: no tools
- if `--read-tools` is set: read-only tools
- if `--yolo` is set: all tools (read + write)
- if both are set: all tools (YOLO takes precedence)

### Runtime / Diagnostics

- `--pull-model`
- `--trace`
- `--trace-file=FILE`
- `--log-ttft`

Behavior notes:

- `--pull-model` only applies to local provider flows.
- tracing writes Chrome-compatible timing traces.
- `--log-ttft` enables streaming-based time-to-first-token logging for no-tool requests.

### Meta Analysis

- `--meta-analysis`
- `--meta-analysis-file=FILE`

Runs a post-response quality check and writes markdown when enabled.

### Mock Mode

- `--mock=FILE`

Mock-mode constraints:

- requires both `--provider=mock` and `--model=mock`
- requires `--mock=...`
- cannot be combined with `--meta-analysis`
- cannot be combined with `--pull-model`

### MCP Server Mode

- `--mcp-server`

Behavior:

- starts HTTP MCP server on `127.0.0.1:4243` at `/mcp`
- uses the configured provider/model
- write tools are enabled only when `--yolo` is set
- `--read-tools` is not used by MCP startup path; MCP write enablement is keyed from `--yolo`

### Help

- `-h`, `--help`

## Supported Provider Values

- `openai`
- `xai`
- `anthropic`
- `gemini`
- `openrouter`
- `andrewlytics`
- `local`
- `mock`

## Exit / Error Semantics

Common immediate-fail cases:

- unknown option
- missing prompt (no `--prompt` and empty stdin)
- invalid temperature
- mock-mode mismatch/invalid combinations
- unknown provider

## Suggested Compatibility Notes for Typos

To preserve behavior parity:

- keep argument names and defaults unchanged initially
- keep mode precedence (`--yolo` over `--read-tools`)
- keep strict mock-mode validation
- keep MCP server host/port/path and write-enable behavior
