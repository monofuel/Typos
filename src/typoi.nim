## typoi τύποι
## CLI client for Typos

import
  std/[json, options, os, strformat, strutils, terminal, times],
  ./Typoi/[cli_args, output],
  ./Typos/[common, provider_config, tools],
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
  echo "  -p, --prompt=TEXT    One-shot prompt text"
  echo "  --json-stream        Emit JSONL events to stdout"
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
  emitter: CliOutputEmitter
): string =
  ## Stream or buffer assistant response with optional read-tools support.
  if emitter.outputMode == OutputModeJsonStream:
    setToolEventCallback(proc(name: string, args: JsonNode, output: string) =
      emitter.emitTool(name, output)
    )
    defer:
      clearToolEventCallback()

  let stream = case toolMode
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
  emitter: CliOutputEmitter
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

  let assistantResponse = streamAssistantResponse(chatMessages, toolMode, emitter)
  emitter.ensureTrailingNewline(assistantResponse)
  emitter.emitStatus("done")


proc runRepl(config: ProviderConfig, toolMode: ToolMode, emitter: CliOutputEmitter) =
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
    let assistantResponse = streamAssistantResponse(chatMessages, toolMode, emitter)
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

  let providerConfig = resolveProviderConfig(
    cliConfig.provider,
    cliConfig.model,
    cliConfig.baseUrl,
    cliConfig.apiEnvVar
  )

  let stdinIsTty = stdin.isatty
  let stdinData = if stdinIsTty: "" else: readAll(stdin)
  let inputSelection = resolveInputSelection(cliConfig.prompt, stdinData, stdinIsTty)

  case inputSelection.mode
  of InputModeOneShot:
    runOneShot(providerConfig, inputSelection.prompt, cliConfig.toolMode, emitter)
  of InputModeRepl:
    runRepl(providerConfig, cliConfig.toolMode, emitter)


when isMainModule:
  main()
