import
  std/[json, unittest],
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
