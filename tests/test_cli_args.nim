import
  std/unittest,
  Typoi/cli_args


suite "typoi cli args":
  test "defaults use openai codex and no tools":
    let config = parseCliArgs(@[])
    check config.provider == "openai"
    check config.model == ""
    check config.toolMode == ToolModeNone
    check config.prompt == ""

  test "read tools can be selected":
    let config = parseCliArgs(@["--read-tools"])
    check config.toolMode == ToolModeReadOnly

  test "json stream can be selected":
    let config = parseCliArgs(@["--json-stream"])
    check config.outputMode == OutputModeJsonStream

  test "yolo takes precedence over read tools":
    let config = parseCliArgs(@["--read-tools", "--yolo"])
    check config.toolMode == ToolModeReadWrite

  test "prompt option maps to one shot prompt":
    let config = parseCliArgs(@["--prompt", "hello world"])
    check config.prompt == "hello world"

  test "output last message path can be selected":
    let config = parseCliArgs(@["--output-last-message", "last.txt"])
    check config.outputLastMessagePath == "last.txt"

  test "help option sets showHelp":
    let config = parseCliArgs(@["--help"])
    check config.showHelp

  test "unknown option fails":
    expect(ValueError):
      discard parseCliArgs(@["--unknown"])

  test "prompt arg prefers one shot in tty":
    let selection = resolveInputSelection("hello", "", true)
    check selection.mode == InputModeOneShot
    check selection.prompt == "hello"

  test "tty without prompt selects repl":
    let selection = resolveInputSelection("", "", true)
    check selection.mode == InputModeRepl
    check selection.prompt == ""

  test "piped stdin without prompt selects one shot":
    let selection = resolveInputSelection("", "  from stdin  ", false)
    check selection.mode == InputModeOneShot
    check selection.prompt == "from stdin"

  test "empty piped stdin fails":
    expect(ValueError):
      discard resolveInputSelection("", "   ", false)

  test "anthropic provider can be selected":
    let config = parseCliArgs(@["--provider=anthropic"])
    check config.provider == "anthropic"
