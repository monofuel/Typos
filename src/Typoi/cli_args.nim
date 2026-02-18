import
  std/[parseopt, strutils],
  ../Typos/common


type
  ToolMode* = enum
    ToolModeNone
    ToolModeReadOnly
    ToolModeReadWrite

  InputMode* = enum
    InputModeOneShot
    InputModeRepl

  CliConfig* = object
    provider*: string
    model*: string
    baseUrl*: string
    apiEnvVar*: string
    prompt*: string
    toolMode*: ToolMode
    showHelp*: bool

  InputSelection* = object
    mode*: InputMode
    prompt*: string


const
  DefaultProvider* = OpenAiProviderName
  PromptRequiredError* = "No prompt provided. Use --prompt, pipe stdin, or run in a TTY for REPL."


proc setConfigValue(config: var CliConfig, key: string, value: string) =
  ## Assign a parsed option value to a CLI config.
  case key
  of "provider":
    config.provider = value
  of "model":
    config.model = value
  of "base-url":
    config.baseUrl = value
  of "api-env-var":
    config.apiEnvVar = value
  of "prompt", "p":
    config.prompt = value
  else:
    raise newException(ValueError, "Unknown option: " & key)


proc toolModeName*(toolMode: ToolMode): string =
  ## Convert a tool mode enum to a user-facing name.
  case toolMode
  of ToolModeNone:
    result = "none"
  of ToolModeReadOnly:
    result = "read"
  of ToolModeReadWrite:
    result = "yolo"


proc parseCliArgs*(args: seq[string]): CliConfig =
  ## Parse Typoi CLI arguments into a strongly typed config object.
  result.provider = DefaultProvider
  result.model = OpenAiDefaultModel
  result.baseUrl = ""
  result.apiEnvVar = ""
  result.prompt = ""
  result.toolMode = ToolModeNone
  result.showHelp = false

  var parser = initOptParser(args)
  var pendingValueKey = ""

  while true:
    parser.next()
    case parser.kind
    of cmdEnd:
      break
    of cmdArgument:
      if pendingValueKey.len > 0:
        setConfigValue(result, pendingValueKey, parser.key)
        pendingValueKey = ""
      else:
        raise newException(ValueError, "Unexpected positional argument: " & parser.key)
    of cmdLongOption, cmdShortOption:
      case parser.key
      of "provider":
        if parser.val.len > 0:
          setConfigValue(result, parser.key, parser.val)
        else:
          pendingValueKey = parser.key
      of "model":
        if parser.val.len > 0:
          setConfigValue(result, parser.key, parser.val)
        else:
          pendingValueKey = parser.key
      of "base-url":
        if parser.val.len > 0:
          setConfigValue(result, parser.key, parser.val)
        else:
          pendingValueKey = parser.key
      of "api-env-var":
        if parser.val.len > 0:
          setConfigValue(result, parser.key, parser.val)
        else:
          pendingValueKey = parser.key
      of "prompt", "p":
        if parser.val.len > 0:
          setConfigValue(result, parser.key, parser.val)
        else:
          pendingValueKey = parser.key
      of "read-tools":
        if result.toolMode != ToolModeReadWrite:
          result.toolMode = ToolModeReadOnly
      of "yolo":
        result.toolMode = ToolModeReadWrite
      of "help", "h":
        result.showHelp = true
      else:
        raise newException(ValueError, "Unknown option: " & parser.key)

  if pendingValueKey.len > 0:
    raise newException(ValueError, "Missing value for option: " & pendingValueKey)


proc resolveInputSelection*(promptArg: string, stdinData: string, stdinIsTty: bool): InputSelection =
  ## Resolve one-shot vs REPL mode from prompt argument and stdin state.
  let promptText = promptArg.strip()
  if promptText.len > 0:
    result.mode = InputModeOneShot
    result.prompt = promptText
  elif stdinIsTty:
    result.mode = InputModeRepl
    result.prompt = ""
  else:
    let stdinPrompt = stdinData.strip()
    if stdinPrompt.len == 0:
      raise newException(ValueError, PromptRequiredError)
    result.mode = InputModeOneShot
    result.prompt = stdinPrompt
