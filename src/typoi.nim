## typoi τύποι
## CLI client for Typos

import
  std/[options, parseopt, strformat, strutils, times],
  ./Typos/[common, provider_config],
  ./agents


const
  DefaultProvider = OpenAiProviderName
  ExitCommand = "/exit"
  QuitCommand = "/quit"
  HelpCommand = "/help"
  ClearCommand = "/clear"


proc printBanner(config: ProviderConfig) =
  ## Print the initial CLI banner and command hint.
  echo "Typos CLI"
  echo &"Provider: {providerName(config.provider)}"
  echo &"Model: {config.model}"
  echo &"Base URL: {config.baseUrl}"
  if config.apiEnvVar.len > 0:
    echo &"API Env Var: {config.apiEnvVar}"
  echo "Type a message to chat. Commands: /help, /clear, /exit"
  echo ""


proc printHelp() =
  ## Print available CLI commands.
  echo "Usage: typoi [options]"
  echo "Options:"
  echo "  --provider=NAME      lm_studio | openai | bedrock"
  echo "  --model=MODEL        Override model name"
  echo "  --base-url=URL       Override provider base URL"
  echo "  --api-env-var=NAME   Override API key environment variable"
  echo "  -h, --help           Show help"
  echo ""
  echo "Commands:"
  echo "  /help  Show this help message"
  echo "  /clear Clear conversation history"
  echo "  /exit  Exit Typos CLI"
  echo ""


proc runChat(config: ProviderConfig) =
  ## Run an interactive user-assistant chat loop.
  var chatMessages: seq[ChatMessage]

  agents.responses_chat.initClient(config)
  printBanner(config)

  while true:
    stdout.write("You: ")
    stdout.flushFile()

    var rawInput = ""
    if not stdin.readLine(rawInput):
      echo ""
      break

    let userInput = rawInput.strip()
    if userInput.len == 0:
      continue

    case userInput
    of ExitCommand, QuitCommand:
      break
    of HelpCommand:
      printHelp()
      continue
    of ClearCommand:
      chatMessages.setLen(0)
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

    let stream = agents.responses_chat.sendMessage(chatMessages)

    stdout.write("Assistant: ")
    stdout.flushFile()

    var assistantResponse = ""
    while true:
      let chunk = agents.responses_chat.getNextChunk(stream)
      if chunk.isSome:
        let content = chunk.get()
        assistantResponse &= content
        stdout.write(content)
        stdout.flushFile()
      else:
        break

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
  ## Parse CLI options and start interactive chat.
  var providerArg = DefaultProvider
  var modelArg = ""
  var baseUrlArg = ""
  var apiEnvVarArg = ""

  for kind, key, value in getopt():
    case kind
    of cmdArgument:
      discard
    of cmdLongOption, cmdShortOption:
      case key
      of "provider":
        providerArg = value
      of "model":
        modelArg = value
      of "base-url":
        baseUrlArg = value
      of "api-env-var":
        apiEnvVarArg = value
      of "help", "h":
        printHelp()
        quit(0)
      else:
        echo "Unknown option: " & key
        printHelp()
        quit(1)
    of cmdEnd:
      discard

  let providerConfig = resolveProviderConfig(
    providerArg,
    modelArg,
    baseUrlArg,
    apiEnvVarArg
  )
  runChat(providerConfig)


when isMainModule:
  main()
