import
  std/[options, os, osproc, streams, strutils, times, unittest],
  openai_leap,
  Typos/tools


const
  BedrockModel = "anthropic.claude-sonnet-4-6"
  BedrockBaseUrl = "https://bedrock-mantle.us-east-1.api.aws/v1"
  BedrockApiEnvVar = "AWS_BEDROCK_TOKEN"


proc makeTempDir(prefix: string): string =
  result = getTempDir() / (prefix & "_" & $epochTime().int64)
  createDir(result)


proc runCmd(workingDir: string, command: string, args: seq[string]) =
  let process = startProcess(
    command,
    workingDir = workingDir,
    args = args,
    options = {poUsePath, poStdErrToStdOut}
  )
  var output = ""
  for line in process.outputStream.lines:
    output.add(line & "\n")
  let exitCode = process.waitForExit()
  process.close()
  doAssert exitCode == 0, "Command failed: " & command & " " & args.join(" ") & "\n" & output


proc requireApiKey(): string =
  ## Return the API key or exit gracefully when not set.
  result = getEnv(BedrockApiEnvVar).strip()
  if result.len == 0:
    echo "Skipping: AWS_BEDROCK_TOKEN not set."
    quit(0)


proc askWithReadTools(api: OpenAiApi, prompt: string): string =
  ## Send a prompt through the Responses API with read-only tools and return final text.
  let tools = getTyposReadTools()
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


suite "read tools agent integration":
  let apiKey = requireApiKey()
  let api = newOpenAiApi(
    baseUrl = BedrockBaseUrl,
    apiKey = apiKey
  )

  test "read_file tool reads file content":
    let dirPath = makeTempDir("typos_int_read")
    defer: removeDir(dirPath)
    let filePath = dirPath / "config.txt"
    writeFile(filePath, "version=the-magic-value-42\n")

    let response = askWithReadTools(api,
      "You are a coding assistant helping me review a project. " &
      "Please use the read_file tool to read the config file at '" & filePath &
      "' and tell me what version is configured."
    )
    check "the-magic-value-42" in response

  test "system_ls lists directory contents":
    let dirPath = makeTempDir("typos_int_ls")
    defer: removeDir(dirPath)
    writeFile(dirPath / "alpha.txt", "a")
    writeFile(dirPath / "beta.nim", "discard")
    writeFile(dirPath / "gamma.json", "{}")

    let response = askWithReadTools(api,
      "Use the system_ls tool to list the files in '" & dirPath &
      "'. Reply with the filenames you see, one per line."
    )
    let lower = response.toLowerAscii()
    check "alpha.txt" in lower
    check "beta.nim" in lower
    check "gamma.json" in lower

  test "ripgrep finds pattern in files":
    let dirPath = makeTempDir("typos_int_rg")
    defer: removeDir(dirPath)
    writeFile(dirPath / "haystack1.txt", "nothing here\n")
    writeFile(dirPath / "haystack2.txt", "the needle is hidden\n")
    writeFile(dirPath / "haystack3.txt", "also nothing\n")

    let response = askWithReadTools(api,
      "Use the ripgrep tool to search for the word 'needle' in the directory '" & dirPath &
      "'. Tell me which filename contains the match."
    )
    check "haystack2" in response.toLowerAscii()

  test "find_files locates files by pattern":
    let dirPath = makeTempDir("typos_int_find")
    defer: removeDir(dirPath)
    createDir(dirPath / "sub")
    writeFile(dirPath / "top.txt", "a")
    writeFile(dirPath / "code.nim", "discard")
    writeFile(dirPath / "sub" / "nested.nim", "echo 1")
    writeFile(dirPath / "sub" / "data.json", "{}")

    let response = askWithReadTools(api,
      "You are a coding assistant with file tools. " &
      "Use the find_files tool with path '" & dirPath &
      "' and regex '.*\\.nim$' to find all .nim files recursively. " &
      "List every filename you found, including files in subdirectories."
    )
    let lower = response.toLowerAscii()
    check "code.nim" in lower or "nested.nim" in lower

  test "git_status reports modified files":
    let dirPath = makeTempDir("typos_int_git")
    defer: removeDir(dirPath)
    runCmd(dirPath, "git", @["init"])
    runCmd(dirPath, "git", @["config", "user.email", "test@example.com"])
    runCmd(dirPath, "git", @["config", "user.name", "Test User"])
    writeFile(dirPath / "tracked.txt", "original\n")
    runCmd(dirPath, "git", @["add", "tracked.txt"])
    runCmd(dirPath, "git", @["commit", "-m", "init"])
    writeFile(dirPath / "tracked.txt", "modified\n")

    let response = askWithReadTools(api,
      "Use the git_status tool with working_dir '" & dirPath &
      "' to check the repo status. Tell me which file has been modified."
    )
    check "tracked.txt" in response.toLowerAscii()

  api.close()
