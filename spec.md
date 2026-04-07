# Spec

Typos (τύπος) is an AI-powered text editor and coding agent built in Nim.
It ships two executables: **Typos** (GUI) and **Typoi** (CLI).

## Architecture

### Dual-Binary Design

- **Typos** — graphical editor built on [Silky](https://github.com/treeform/silky)
  (OpenGL + Windy). Two-pane layout: git diff panel (left) and AI chat panel
  (right). Renders streaming AI responses, tool toggle checkboxes, and a text
  input box.
- **Typoi** — command-line client for agentic coding. Supports one-shot
  (`--prompt` / stdin pipe) and interactive REPL modes. Emits text or JSONL
  event streams.

Both binaries share the core agent, tool registry, provider abstraction, and
configuration modules.

### Provider Abstraction

A single OpenAI-compatible client handles all providers via two API shapes:

| Provider    | API Shape     | Default Model              | Base URL                                     |
|-------------|---------------|----------------------------|----------------------------------------------|
| LM Studio   | Responses API | Qwen3-Coder-30B            | `http://10.11.2.14:1234/v1`                  |
| OpenAI       | Responses API | `gpt-5.1-codex-mini`       | `https://api.openai.com/v1`                  |
| Bedrock      | Responses API | `openai.gpt-oss-20b`       | `https://bedrock-mantle.us-east-1.api.aws/v1`|
| Anthropic    | Messages API  | `claude-sonnet-4-6`        | Anthropic default                            |

`TyposResponseStream` wraps both Responses API and Messages API streaming,
exposing a uniform `getNextChunk()` interface.

### Configuration Cascade

Provider and model settings resolve through a layered cascade:

1. **Dotfile** — `~/.typos/config.json` (global defaults and named profiles)
2. **Project** — `.typos.json` (per-repo overrides)
3. **CLI flags** — `--provider`, `--model`, `--base-url`, `--api-env-var`

Later layers override earlier ones. Named profiles can be selected at runtime.
`ProfileConfig` carries provider, model, apiKeyEnv, baseUrl, and
reasoningEffort.

## Tool System

The tool registry (`src/Typos/tools/registry.nim`) maps tool names to typed
implementations via `ResponseToolsTable`. Tools are registered with timing
traces and operate through a `ToolOps` abstraction that can be swapped for an
in-memory mock during testing.

### Read Tools

Directory and environment: `system_pwd`, `system_ls`, `find_files`

Nim build: `nim_check`, `nimble_test`, `nim_version`

File and text: `read_file`, `awk`, `ripgrep`

Git (read-only): `git_status`, `git_diff`, `git_diff_staged`, `git_log`,
`git_show`, `git_branch`

Issue collection: `create_issue` (records structured JSON, no remote creation)

### Write Tools

File operations: `write_file`, `append_file`, `move_file`, `delete_file`,
`create_directory`

Line-based editing: `insert_lines`, `delete_lines`, `replace_lines`,
`replace_in_file`

Sed scripting: `sed_edit`

Git (write): `git_add`, `git_commit`, `git_restore`

### Shared Safety

- Output truncation at 100,000 characters.
- ANSI escape stripping.
- Working-directory resolution with fallback.
- Trailing-newline normalization for writes.
- Contextual line-number snippets returned from edit tools.

### Tool Levels

Three escalation levels control which tools the agent may use:

- `sendMessage()` — no tools.
- `sendMessageWithReadTools()` — read-only tools.
- `sendMessageWithReadWriteTools()` — read + write tools.
- `sendMessageWithTools()` — custom tool set (e.g. MCP-extended).

## MCP Integration

`src/Typos/mcp_tools.nim` connects to MCP servers via `MCPort`:

- `connectMcpClient()` — creates and initializes an `HttpMcpClient`.
- `mcpToolToToolFunction()` — converts MCP tool definitions to the internal
  `ToolFunction` format.
- `registerMcpTools()` — wraps MCP tools with proxy implementations and adds
  them to the registry.

This allows dynamic tool extension without modifying the core registry.

## CLI (Typoi)

### Input Modes

| Condition                    | Mode     |
|------------------------------|----------|
| `--prompt` / `-p` provided   | One-shot |
| stdin is piped (non-empty)   | One-shot |
| stdin is a TTY               | REPL     |

### Output Modes

- **Text** (default) — human-readable streaming output.
- **JSON Stream** — JSONL events (`status`, `message`, `tool`) for
  programmatic consumption.

### REPL Commands

`/help`, `/clear`, `/exit` (or `/quit`).

### Supported Flags

`--provider`, `--model`, `--api-env-var`, `--base-url`, `-p`/`--prompt`,
`--read-tools`, `--yolo`, `-h`/`--help`.

## GUI (Typos)

Built on Silky with OpenGL rendering via Windy.

### Layout

- **Left pane (58%)** — git diff panel with syntax-highlighted diff lines
  (`DiffLineKind`: Header, Hunk, Meta, Added, Removed, Context, Empty).
- **Right pane (42%)** — AI chat panel with message history, word wrapping,
  streaming response rendering, and a text input box.

### Theme

GitHub dark-mode palette: background `#0d1117`, text `#e6edf3`, user messages
`#58a6ff`, AI messages `#3fb950`.

### Controls

- Tool toggle checkboxes for read-only and YOLO modes.
- Enter-key submission.
- Auto-scroll on new messages.

## Agent Modes

(Defined in AGENTS.md — design-level, not yet fully implemented in the GUI.)

- **Plan Mode** — read-only analysis; AI creates a plan, user approves before
  execution.
- **Ask Mode** — pure Q&A with read-only tools, no state changes.
- **Code Mode** — read-write tool access with optional auto-plan toggle.

No generic bash/shell tool is exposed; all operations go through specialized
built-in tools.

## System Prompt

Generated programmatically at runtime with injected context:

1. Reasoning level directive.
2. Role statement (autonomous AI assistant with tool access).
3. Current working directory.
4. Directory listing snapshot.
5. Autonomous operation policy (no questions, no approvals, end-to-end).
6. Tool usage instructions.
7. Response format rules (brief, concrete, no follow-ups).
8. Optional additional-instructions overlay from a prompt file.

## Module Map

```
src/
├── Typos.nim                  # GUI entry point
├── typoi.nim                  # CLI entry point
├── agents.nim                 # Re-exports responses_chat
├── Typos/
│   ├── common.nim             # Shared types (ChatMessage, ProviderKind, etc.)
│   ├── chat_messages.nim      # Chat message conversion
│   ├── provider_config.nim    # Provider configuration logic
│   ├── git_diff.nim           # Diff parsing and display
│   ├── dotfile_config.nim     # ~/.typos/config.json + .typos.json
│   ├── mcp_tools.nim          # MCP server integration
│   └── tools/
│       └── registry.nim       # Tool registry (read + write tools)
├── Typoi/
│   ├── cli_args.nim           # CLI argument parsing
│   └── output.nim             # Output formatting (text / JSONL)
└── agents/
    ├── responses_chat.nim     # Response streaming + tool calling
    └── qwen3_coder.nim        # LM Studio / Qwen3 integration
```

## Test Coverage

### Unit Tests

| File                     | Area                          |
|--------------------------|-------------------------------|
| `test_cli_args.nim`      | CLI argument parsing          |
| `test_diff.nim`          | Git diff line classification  |
| `test_dotfile_config.nim`| Config parsing and merging    |
| `test_git_tools.nim`     | Git tool operations           |
| `test_mcp_tools.nim`     | MCP tool conversion           |
| `test_read_tools.nim`    | Read tools (mocked FS)        |
| `test_write_tools.nim`   | Write tools (mocked FS)       |
| `test_typoi_output.nim`  | JSONL output formatting       |

### Integration Tests

| File                          | Area                              |
|-------------------------------|-----------------------------------|
| `integration_anthropic.nim`   | Live Anthropic API streaming      |
| `integration_openai.nim`      | Live OpenAI API streaming         |
| `integration_read_tools.nim`  | Read tools against real FS        |
| `integration_write_tools.nim` | Write tools against real FS       |
| `integration_git_tools.nim`   | Git tools against real repos      |

Tests use a `ToolOps` mock interface to swap the real filesystem for an
in-memory `Table[string, string]`, keeping unit tests deterministic and
network-free.

## Build and CI

### Makefile Targets

- `make build` / `make build-typoi` — release build of the CLI.
- `make build-typos` — release build of the GUI.
- `make test` — run all `test_*.nim` unit tests.
- `make integration-test` — run `integration_*.nim` tests.
- `make e2e-test` — run `e2e_*.nim` tests (placeholder).

### CI Pipeline (`.github/workflows/build.yml`)

- **test** — runs on push/PR, executes all unit tests.
- **linux-binary** — builds typoi release binary (x86_64).
- **release** — publishes GitHub release on version tags (`v*`).
- **release-master** — rolling `master-latest` tag/release.

System dependencies: `libpcre3-dev`, `libcurl4-openssl-dev`.
Uses `nimby` for lock-file-based dependency management.

## Dependencies

- **Nim >= 2.0.0**
- **Silky** (+ Shady, Fluffy) — UI rendering
- **Windy** — window management
- **OpenGL**, **Bumpy**, **Vmath**, **Chroma** — graphics primitives
- **MCPort >= 1.0.0** — MCP server client
