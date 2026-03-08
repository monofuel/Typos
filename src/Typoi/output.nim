import
  std/[json, strutils],
  ./cli_args


type
  JsonStreamEventKind* = enum
    JsonStreamEventStatus
    JsonStreamEventMessage
    JsonStreamEventTool

  CliOutputEmitter* = ref object
    outputMode*: OutputMode


proc newCliOutputEmitter*(outputMode: OutputMode): CliOutputEmitter =
  ## Create a stdout emitter for the configured CLI output mode.
  return CliOutputEmitter(outputMode: outputMode)


proc eventTypeName(kind: JsonStreamEventKind): string =
  ## Convert a JSON stream event kind to its serialized type name.
  case kind
  of JsonStreamEventStatus:
    return "status"
  of JsonStreamEventMessage:
    return "message"
  of JsonStreamEventTool:
    return "tool"


proc renderJsonStreamEvent*(
  kind: JsonStreamEventKind,
  text: string,
  name = ""
): string =
  ## Render a single JSON stream event as one JSONL line.
  var event = %*{
    "type": eventTypeName(kind),
    "text": text
  }
  if kind == JsonStreamEventTool:
    event["name"] = %name
  return $event


proc writeLine(line: string) =
  ## Write a line to stdout and flush immediately.
  stdout.write(line & "\n")
  stdout.flushFile()


proc emitStatus*(emitter: CliOutputEmitter, text: string) =
  ## Emit a lifecycle status event when JSON stream mode is active.
  if emitter.outputMode == OutputModeJsonStream:
    writeLine(renderJsonStreamEvent(JsonStreamEventStatus, text))


proc emitMessage*(emitter: CliOutputEmitter, text: string) =
  ## Emit assistant text according to the configured output mode.
  case emitter.outputMode
  of OutputModeText:
    stdout.write(text)
    stdout.flushFile()
  of OutputModeJsonStream:
    writeLine(renderJsonStreamEvent(JsonStreamEventMessage, text))


proc emitTool*(emitter: CliOutputEmitter, name: string, text: string) =
  ## Emit a tool event when JSON stream mode is active.
  if emitter.outputMode == OutputModeJsonStream:
    writeLine(renderJsonStreamEvent(JsonStreamEventTool, text, name))


proc wantsInteractiveText*(emitter: CliOutputEmitter): bool =
  ## Return true when the CLI should render interactive text UI affordances.
  return emitter.outputMode == OutputModeText


proc ensureTrailingNewline*(emitter: CliOutputEmitter, text: string) =
  ## Add a trailing newline for raw text mode when the response lacks one.
  if emitter.outputMode == OutputModeText and text.len > 0 and not text.endsWith("\n"):
    writeLine("")
