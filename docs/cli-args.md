# CLI Arguments

This document defines the current Typoi CLI behavior.

## Usage

```bash
typoi [options] [--prompt "text" | < prompt.txt]
```

## Input Modes

Typoi supports one-shot and interactive REPL in a single binary.

- If `--prompt` / `-p` is provided: one-shot mode.
- Else if stdin is piped: one-shot mode using stdin content.
- Else (stdin is a TTY): REPL mode.

If stdin is piped but empty and no `--prompt` is provided, Typoi exits with an error.

## Defaults

- `--provider`: `openai`
- `--model`: `gpt-5.1-codex-mini`
- `--api-env-var`: provider default
- `--base-url`: provider default
- tool mode: none

Provider defaults:

- `openai`
  - base URL: `https://api.openai.com/v1`
  - env var: `OPENAI_API_KEY`
- `lm_studio`
  - base URL: `http://10.11.2.14:1234/v1`
  - env var: none required
- `bedrock`
  - base URL: `https://bedrock-mantle.us-east-1.api.aws/v1`
  - env var: `AWS_BEDROCK_TOKEN`

## Supported Flags

- `--provider=PROVIDER`
- `--model=MODEL`
- `--api-env-var=VAR`
- `--base-url=URL`
- `-p, --prompt=TEXT`
- `--read-tools`
- `--yolo`
- `-h, --help`

## Tool Mode (Current Scope)

Tool mode is parsed and tracked, but no real tool execution is implemented yet.

- no flag: tool mode `none`
- `--read-tools`: tool mode `read`
- `--yolo`: tool mode `yolo` (read + write)
- if both are passed, `--yolo` takes precedence

## REPL Commands

- `/help`
- `/clear`
- `/exit` (or `/quit`)

## Out of Scope for Now

- MCP server mode
- meta-analysis mode
- mock mode
- pull-model mode
