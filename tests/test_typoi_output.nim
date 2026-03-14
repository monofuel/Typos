import
  std/[json, os, unittest],
  Typoi/output


suite "typoi output":
  test "message event renders as json":
    let line = renderJsonStreamEvent(JsonStreamEventMessage, "hello\nworld")
    let node = parseJson(line)
    check node["type"].getStr == "message"
    check node["text"].getStr == "hello\nworld"

  test "tool event renders name and text":
    let line = renderJsonStreamEvent(JsonStreamEventTool, "Wrote 5 bytes.", "write_file")
    let node = parseJson(line)
    check node["type"].getStr == "tool"
    check node["name"].getStr == "write_file"
    check node["text"].getStr == "Wrote 5 bytes."

  test "last assistant message is written to disk":
    let outputPath = getTempDir() / "typoi_last_message_test.txt"
    defer:
      if fileExists(outputPath):
        removeFile(outputPath)
    writeLastAssistantMessage(outputPath, "final answer")
    check readFile(outputPath) == "final answer"
