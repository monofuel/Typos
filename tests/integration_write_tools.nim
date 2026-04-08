import
  std/[options, os, strutils, times, unittest],
  openai_leap,
  Typos/tools


const
  BedrockModel = "anthropic.claude-sonnet-4-6"
  BedrockBaseUrl = "https://bedrock-mantle.us-east-1.api.aws/v1"
  BedrockApiEnvVar = "AWS_BEDROCK_TOKEN"


proc makeTempDir(prefix: string): string =
  result = getTempDir() / (prefix & "_" & $epochTime().int64)
  createDir(result)


proc requireApiKey(): string =
  result = getEnv(BedrockApiEnvVar).strip()
  if result.len == 0:
    raise newException(ValueError, "AWS_BEDROCK_TOKEN must be set for integration tests.")


proc askWithWriteTools(api: OpenAiApi, prompt: string): string =
  ## Send a prompt through the Responses API with read+write tools and return final text.
  let tools = getTyposReadWriteTools()
  var req = CreateResponseReq()
  req.model = BedrockModel
  req.input = option(@[
    ResponseInput(
      `type`: "message",
      role: option("user"),
      content: option(@[
        ResponseInputContent(
          `type`: "input_text",
          text: option(prompt)
        )
      ])
    )
  ])
  let resp = api.createResponseWithTools(req, tools)

  if resp.output_text.isSome and resp.output_text.get.len > 0:
    return resp.output_text.get

  for output in resp.output:
    if output.`type` == "message" and output.content.isSome:
      for contentPart in output.content.get:
        if contentPart.`type` == "output_text" and contentPart.text.isSome:
          return contentPart.text.get

  return ""


suite "write tools agent integration":
  let apiKey = requireApiKey()
  let api = newOpenAiApi(
    baseUrl = BedrockBaseUrl,
    apiKey = apiKey
  )

  test "write_file creates a new file":
    let dirPath = makeTempDir("typos_int_write")
    defer: removeDir(dirPath)
    let filePath = dirPath / "hello.txt"

    discard askWithWriteTools(api,
      "Use the write_file tool to create a file at '" & filePath &
      "' with the content 'Hello, integration test!' (exactly that text, no extra newline). " &
      "Confirm when done."
    )
    check fileExists(filePath)
    check readFile(filePath) == "Hello, integration test!"

  test "append_file appends content":
    let dirPath = makeTempDir("typos_int_write")
    defer: removeDir(dirPath)
    let filePath = dirPath / "log.txt"
    writeFile(filePath, "line1\n")

    discard askWithWriteTools(api,
      "Use the append_file tool to append the text 'line2\n' to the file at '" & filePath &
      "'. Confirm when done."
    )
    check readFile(filePath) == "line1\nline2\n"

  test "replace_in_file replaces text":
    let dirPath = makeTempDir("typos_int_write")
    defer: removeDir(dirPath)
    let filePath = dirPath / "config.txt"
    writeFile(filePath, "color=red\nsize=10\n")

    discard askWithWriteTools(api,
      "Use the replace_in_file tool to replace 'red' with 'blue' in the file at '" & filePath &
      "'. Confirm when done."
    )
    check readFile(filePath) == "color=blue\nsize=10\n"

  test "create_directory creates dir":
    let dirPath = makeTempDir("typos_int_write")
    defer: removeDir(dirPath)
    let subDir = dirPath / "newsubdir"

    discard askWithWriteTools(api,
      "Use the create_directory tool to create a directory at '" & subDir &
      "'. Confirm when done."
    )
    check dirExists(subDir)

  test "delete_file removes a file":
    let dirPath = makeTempDir("typos_int_write")
    defer: removeDir(dirPath)
    let filePath = dirPath / "trash.txt"
    writeFile(filePath, "delete me")

    discard askWithWriteTools(api,
      "Use the delete_file tool to delete the file at '" & filePath &
      "'. Confirm when done."
    )
    check not fileExists(filePath)

  test "move_file renames a file":
    let dirPath = makeTempDir("typos_int_write")
    defer: removeDir(dirPath)
    let srcPath = dirPath / "old.txt"
    let dstPath = dirPath / "new.txt"
    writeFile(srcPath, "moveable content")

    discard askWithWriteTools(api,
      "Use the move_file tool to move the file from '" & srcPath &
      "' to '" & dstPath & "'. Confirm when done."
    )
    check not fileExists(srcPath)
    check fileExists(dstPath)
    check readFile(dstPath) == "moveable content"

  test "insert_lines inserts content":
    let dirPath = makeTempDir("typos_int_write")
    defer: removeDir(dirPath)
    let filePath = dirPath / "lines.txt"
    writeFile(filePath, "alpha\ngamma\n")

    discard askWithWriteTools(api,
      "Use the insert_lines tool to insert the text 'beta' after line 1 in the file at '" & filePath &
      "'. Use after_line=1. Confirm when done."
    )
    check readFile(filePath) == "alpha\nbeta\ngamma\n"

  test "delete_lines removes lines":
    let dirPath = makeTempDir("typos_int_write")
    defer: removeDir(dirPath)
    let filePath = dirPath / "lines.txt"
    writeFile(filePath, "keep1\nremoveme\nkeep2\n")

    discard askWithWriteTools(api,
      "Use the delete_lines tool to delete line 2 (start_line=2, end_line=2) from the file at '" & filePath &
      "'. Confirm when done."
    )
    check readFile(filePath) == "keep1\nkeep2\n"

  test "replace_lines replaces content":
    let dirPath = makeTempDir("typos_int_write")
    defer: removeDir(dirPath)
    let filePath = dirPath / "lines.txt"
    writeFile(filePath, "aaa\nbbb\nccc\n")

    discard askWithWriteTools(api,
      "Use the replace_lines tool to replace line 2 (start_line=2, end_line=2) with the text 'BBB' in the file at '" & filePath &
      "'. Confirm when done."
    )
    check readFile(filePath) == "aaa\nBBB\nccc\n"

  api.close()
