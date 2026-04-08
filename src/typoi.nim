## typoi τύποι
## CLI client for Typos

import
  std/[json, options, os, strformat, strutils, terminal, times],
  openai_leap,
  ./Typoi/[cli_args, output],
  ./Typos/[common, dotfile_config, mcp_tools, provider_config, tools],
  ./agents


const
  ExitCommand = "/exit"
  QuitCommand = "/quit"
  HelpCommand = "/help"
  ClearCommand = "/clear"


proc printBanner(config: ProviderConfig, toolMode: ToolMode) =
  ## Print the initial REPL banner and command hint.
  echo "Typos CLI"
  echo &"Provider: {providerName(config.provider)}"
  echo &"Model: {config.model}"
  echo &"Base URL: {config.baseUrl}"
  if config.apiEnvVar.len > 0:
    echo &"API Env Var: {config.apiEnvVar}"
  echo &"Tool Mode: {toolModeName(toolMode)}"
  echo "Type a message to chat. Commands: /help, /clear, /exit"
  echo ""


proc printHelp() =
  ## Print available CLI flags and REPL commands.
  echo "Usage: typoi [options] [--prompt \"text\" | < prompt.txt]"
  echo "Options:"
  echo "  --provider=NAME      openai | anthropic | lm_studio | bedrock"
  echo "  --model=MODEL        Override model name"
  echo "  --api-env-var=NAME   Override API key environment variable"
  echo "  --base-url=URL       Override provider base URL"
  echo "  --profile=NAME       Select config profile from ~/.typos/config.json"
  echo "  --mcp-server-url=URL Connect to MCP server for additional tools"
  echo "  -p, --prompt=TEXT    One-shot prompt text"
  echo "  --json-stream        Emit JSONL events to stdout"
  echo "  --output-last-message=PATH"
  echo "                       Write the final assistant message to a file"
  echo "  --read-tools         Enable read-only tool mode"
  echo "  --yolo               Select read+write mode (write tools not implemented yet)"
  echo "  -h, --help           Show help"
  echo ""
  echo "Commands:"
  echo "  /help  Show this help message"
  echo "  /clear Clear conversation history"
  echo "  /exit  Exit Typos CLI"
  echo ""


proc streamAssistantResponse(
  chatMessages: seq[ChatMessage],
  toolMode: ToolMode,
  emitter: CliOutputEmitter,
  extraTools: ResponseToolsTable = newResponseToolsTable()
): string =
  ## Stream or buffer assistant response with optional read-tools support.
  if emitter.outputMode == OutputModeJsonStream:
    setToolEventCallback(proc(name: string, args: JsonNode, output: string) =
      emitter.emitTool(name, output)
    )
    defer:
      clearToolEventCallback()

  let hasExtraTools = extraTools.len > 0

  let stream = if hasExtraTools and toolMode != ToolModeNone:
    # Merge native tools with extra (MCP) tools
    var tools = case toolMode
    of ToolModeReadOnly:
      getTyposReadTools()
    of ToolModeReadWrite:
      getTyposReadWriteTools()
    of ToolModeNone:
      newResponseToolsTable()
    for name, entry in extraTools.pairs:
      let (toolFunc, impl) = entry
      tools.register(name, toolFunc, impl)
    agents.responses_chat.sendMessageWithTools(chatMessages, tools)
  else:
    case toolMode
    of ToolModeReadOnly:
      agents.responses_chat.sendMessageWithReadTools(chatMessages)
    of ToolModeReadWrite:
      agents.responses_chat.sendMessageWithReadWriteTools(chatMessages)
    of ToolModeNone:
      agents.responses_chat.sendMessage(chatMessages)

  while true:
    let chunk = agents.responses_chat.getNextChunk(stream)
    if chunk.isSome:
      let content = chunk.get()
      result &= content
      emitter.emitMessage(content)
    else:
      break


proc runOneShot(
  config: ProviderConfig,
  prompt: string,
  toolMode: ToolMode,
  emitter: CliOutputEmitter,
  outputLastMessagePath: string,
  extraTools: ResponseToolsTable = newResponseToolsTable()
) =
  ## Run a single prompt-response exchange and exit.
  agents.responses_chat.initClient(config)
  emitter.emitStatus("ready")

  var chatMessages: seq[ChatMessage]
  chatMessages.add(
    ChatMessage(
      sender: "User",
      content: prompt,
      timestamp: epochTime()
    )
  )

  let assistantResponse = streamAssistantResponse(chatMessages, toolMode, emitter, extraTools)
  writeLastAssistantMessage(outputLastMessagePath, assistantResponse)
  emitter.ensureTrailingNewline(assistantResponse)
  emitter.emitStatus("done")


proc runRepl(
  config: ProviderConfig,
  toolMode: ToolMode,
  emitter: CliOutputEmitter,
  outputLastMessagePath: string,
  extraTools: ResponseToolsTable = newResponseToolsTable()
) =
  ## Run interactive chat REPL mode.
  var chatMessages: seq[ChatMessage]
  agents.responses_chat.initClient(config)
  emitter.emitStatus("ready")
  if emitter.wantsInteractiveText():
    printBanner(config, toolMode)

  while true:
    if emitter.wantsInteractiveText():
      stdout.write("You: ")
      stdout.flushFile()

    var rawInput = ""
    if not stdin.readLine(rawInput):
      if emitter.wantsInteractiveText():
        echo ""
      emitter.emitStatus("done")
      break

    let userInput = rawInput.strip()
    if userInput.len == 0:
      continue

    case userInput
    of ExitCommand, QuitCommand:
      break
    of HelpCommand:
      if emitter.wantsInteractiveText():
        printHelp()
      continue
    of ClearCommand:
      chatMessages.setLen(0)
      if emitter.wantsInteractiveText():
        echo "Conversation cleared."
        echo ""
      continue
    else:
      discard

    chatMessages.add(
      ChatMessage(
        sender: "User",
        content: userInput,
        timestamp: epochTime()
      )
    )

    if emitter.wantsInteractiveText():
      stdout.write("Assistant: ")
      stdout.flushFile()
    let assistantResponse = streamAssistantResponse(chatMessages, toolMode, emitter, extraTools)
    writeLastAssistantMessage(outputLastMessagePath, assistantResponse)
    if emitter.wantsInteractiveText():
      echo ""
      echo ""

    chatMessages.add(
      ChatMessage(
        sender: "AI",
        content: assistantResponse,
        timestamp: epochTime()
      )
    )


proc main() =
  ## Parse CLI args and dispatch one-shot or REPL mode.
  let cliConfig = parseCliArgs(commandLineParams())
  if cliConfig.showHelp:
    printHelp()
    quit(0)
  let emitter = newCliOutputEmitter(cliConfig.outputMode)
  emitter.emitStatus("init")

  # Load dotfile and project configs, resolve profile defaults
  let dotfileConfig = loadDotfileConfig()
  let projectConfig = loadProjectConfig()
  let mergedConfig = mergeConfigs(dotfileConfig, projectConfig)
  let profile = resolveProfile(mergedConfig, cliConfig.profile)

  # CLI flags override profile values; profile overrides hardcoded defaults
  let providerName = if cliConfig.provider != DefaultProvider and cliConfig.provider.len > 0:
    cliConfig.provider
  elif profile.provider.len > 0:
    profile.provider
  else:
    cliConfig.provider
  let modelOverride = if cliConfig.model.len > 0: cliConfig.model elif profile.model.len > 0: profile.model else: ""
  let baseUrlOverride = if cliConfig.baseUrl.len > 0: cliConfig.baseUrl elif profile.baseUrl.len > 0: profile.baseUrl else: ""
  let apiEnvVarOverride = if cliConfig.apiEnvVar.len > 0: cliConfig.apiEnvVar elif profile.apiKeyEnv.len > 0: profile.apiKeyEnv else: ""

  let providerConfig = resolveProviderConfig(
    providerName,
    modelOverride,
    baseUrlOverride,
    apiEnvVarOverride
  )

  # Connect MCP client if URL provided
  var extraTools = newResponseToolsTable()
  if cliConfig.mcpServerUrl.len > 0:
    let mcpClient = connectMcpClient(cliConfig.mcpServerUrl)
    registerMcpTools(extraTools, mcpClient)

  let stdinIsTty = stdin.isatty
  let stdinData = if stdinIsTty: "" else: readAll(stdin)
  let inputSelection = resolveInputSelection(cliConfig.prompt, stdinData, stdinIsTty)

  case inputSelection.mode
  of InputModeOneShot:
    runOneShot(
      providerConfig,
      inputSelection.prompt,
      cliConfig.toolMode,
      emitter,
      cliConfig.outputLastMessagePath,
      extraTools
    )
  of InputModeRepl:
    runRepl(
      providerConfig,
      cliConfig.toolMode,
      emitter,
      cliConfig.outputLastMessagePath,
      extraTools
    )


when isMainModule:
  main()
