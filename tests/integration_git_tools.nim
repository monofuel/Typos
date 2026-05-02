import
  std/[options, os, osproc, streams, strutils, times, unittest],
  openai_leap,
  Typos/[aws_credentials, tools]


const
  BedrockModel = "anthropic.claude-sonnet-4-6"
  BedrockBaseUrl = "https://bedrock-mantle.us-east-1.api.aws/v1"
  BedrockApiEnvVar = "AWS_BEDROCK_TOKEN"


proc makeTempDir(prefix: string): string =
  result = getTempDir() / (prefix & "_" & $epochTime().int64)
  createDir(result)


proc runCmd(workingDir: string, command: string, args: seq[string]): string =
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
  return output


proc initGitRepo(dir: string) =
  discard runCmd(dir, "git", @["init"])
  discard runCmd(dir, "git", @["config", "user.email", "test@example.com"])
  discard runCmd(dir, "git", @["config", "user.name", "Test User"])


proc makeCommit(dir: string, filename: string, content: string, message: string) =
  writeFile(dir / filename, content)
  discard runCmd(dir, "git", @["add", filename])
  discard runCmd(dir, "git", @["commit", "-m", message])


proc requireApiKey(): string =
  ## Return the API key or fall back to AWS CLI short-lived tokens.
  result = getEnv(BedrockApiEnvVar).strip()
  if result.len == 0 and getEnv("AWS_PROFILE").len > 0:
    try:
      result = getBedrockToken()
    except IOError:
      echo "Skipping: AWS_PROFILE set but token generation failed (boto3 missing?)."
      quit(0)
  if result.len == 0:
    echo "Skipping: AWS_BEDROCK_TOKEN not set and no AWS_PROFILE available."
    quit(0)


proc askWithReadTools(api: OpenAiApi, prompt: string): string =
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


proc askWithWriteTools(api: OpenAiApi, prompt: string): string =
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


suite "git tools agent integration":
  let apiKey = requireApiKey()
  let api = newOpenAiApi(
    baseUrl = BedrockBaseUrl,
    apiKey = apiKey
  )

  test "git_log shows commit history":
    let dir = makeTempDir("typos_int_git_log")
    defer: removeDir(dir)
    initGitRepo(dir)
    makeCommit(dir, "a.txt", "a", "alpha commit")
    makeCommit(dir, "b.txt", "b", "beta commit")

    let response = askWithReadTools(api,
      "Use the git_log tool with working_dir '" & dir &
      "' to show recent commits. Tell me the commit messages you see."
    )
    let lower = response.toLowerAscii()
    check "alpha" in lower or "beta" in lower

  test "git_diff_staged shows staged changes":
    let dir = makeTempDir("typos_int_git_diff_staged")
    defer: removeDir(dir)
    initGitRepo(dir)
    makeCommit(dir, "f.txt", "original\n", "init")
    writeFile(dir / "f.txt", "staged-change\n")
    discard runCmd(dir, "git", @["add", "f.txt"])

    let response = askWithReadTools(api,
      "Use the git_diff_staged tool with working_dir '" & dir &
      "' to see staged changes. Tell me what was changed."
    )
    let lower = response.toLowerAscii()
    check "staged" in lower or "change" in lower or "original" in lower

  test "git_show displays commit content":
    let dir = makeTempDir("typos_int_git_show")
    defer: removeDir(dir)
    initGitRepo(dir)
    makeCommit(dir, "f.txt", "show-me-content\n", "show test commit")

    let response = askWithReadTools(api,
      "Use the git_show tool with ref 'HEAD' and working_dir '" & dir &
      "' to show the latest commit. Tell me the commit message."
    )
    check "show test commit" in response.toLowerAscii() or "show" in response.toLowerAscii()

  test "git_branch lists branches":
    let dir = makeTempDir("typos_int_git_branch")
    defer: removeDir(dir)
    initGitRepo(dir)
    makeCommit(dir, "f.txt", "a\n", "init")
    discard runCmd(dir, "git", @["branch", "dev-branch"])

    let response = askWithReadTools(api,
      "Use the git_branch tool with working_dir '" & dir &
      "' to list branches. Tell me all the branch names."
    )
    let lower = response.toLowerAscii()
    check "dev-branch" in lower

  test "git_add and git_commit create a commit":
    let dir = makeTempDir("typos_int_git_add_commit")
    defer: removeDir(dir)
    initGitRepo(dir)
    makeCommit(dir, "init.txt", "init\n", "initial")
    writeFile(dir / "new.txt", "new file content\n")

    discard askWithWriteTools(api,
      "Use the git_add tool to stage the file 'new.txt', then use the git_commit tool " &
      "to commit with message 'added new file'. Use working_dir '" & dir & "' for both calls."
    )

    let log = runCmd(dir, "git", @["log", "--oneline", "-n", "1"])
    check "added new file" in log.toLowerAscii()

  test "git_restore discards changes":
    let dir = makeTempDir("typos_int_git_restore")
    defer: removeDir(dir)
    initGitRepo(dir)
    makeCommit(dir, "f.txt", "original\n", "init")
    writeFile(dir / "f.txt", "dirty\n")

    discard askWithWriteTools(api,
      "Use the git_restore tool to discard working tree changes for 'f.txt'. " &
      "Use working_dir '" & dir & "'. Do not use staged=true."
    )
    check readFile(dir / "f.txt") == "original\n"

  api.close()
