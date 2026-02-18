import
  std/[json, options, os, osproc, re, streams, strformat, strutils],
  openai_leap


const
  MaxToolOutputChars = 100000


var collectedIssues*: seq[JsonNode] = @[]


proc validateToolArgs(args: JsonNode, toolName: string, requiredParams: seq[string]): string =
  ## Validate tool arguments and return an error string when invalid.
  if args.kind != JObject:
    return &"Invalid arguments for {toolName}: expected object."

  for param in requiredParams:
    if not args.hasKey(param):
      return &"Missing required parameter for {toolName}: {param}"

  return ""


proc resolveWorkingDir(args: JsonNode): string =
  ## Resolve a working directory from tool args with safe fallback.
  if args.hasKey("working_dir"):
    let rawDir = args["working_dir"].getStr.strip()
    if rawDir.len > 0 and dirExists(rawDir):
      return rawDir
  return getCurrentDir()


proc truncateToolOutput(output: string, toolName: string): string =
  ## Truncate large tool output to keep responses bounded.
  if output.len > MaxToolOutputChars:
    let truncated = output[0..<MaxToolOutputChars]
    return truncated & &"\n\n[TRUNCATED: Output was {output.len} chars for {toolName}]"
  return output


proc runProcess(command: string, args: seq[string], workingDir: string): tuple[exitCode: int, output: string] =
  ## Run an external process and capture merged stdout/stderr output.
  let process = startProcess(
    command,
    workingDir = workingDir,
    args = args,
    options = {poUsePath, poStdErrToStdOut}
  )

  var output = ""
  for line in process.outputStream.lines:
    output.add(line & "\n")

  result.exitCode = process.waitForExit()
  process.close()
  result.output = output


proc systemPwd(args: JsonNode): string =
  ## Return the current working directory.
  let workingDir = resolveWorkingDir(args)
  let (exitCode, output) = runProcess("pwd", @[], workingDir)
  if exitCode == 0:
    return output.strip()
  return &"Error executing pwd (exit code {exitCode}): {output}"


proc systemLs(args: JsonNode): string =
  ## List directory contents for a given path.
  let validationError = validateToolArgs(args, "system_ls", @["path"])
  if validationError.len > 0:
    return validationError

  let path = args["path"].getStr
  let workingDir = resolveWorkingDir(args)
  let (exitCode, output) = runProcess("ls", @[path], workingDir)
  if exitCode == 0:
    return output.strip()
  return &"Error executing ls {path} (exit code {exitCode}): {output}"


proc nimCheck(args: JsonNode): string =
  ## Run nim check on a list of files.
  let validationError = validateToolArgs(args, "nim_check", @["files"])
  if validationError.len > 0:
    return validationError

  let workingDir = resolveWorkingDir(args)
  var backendFlag = ""
  if args.hasKey("backend"):
    let backend = args["backend"].getStr.strip().toLowerAscii()
    if backend.len > 0 and backend != "c":
      backendFlag = "--backend:" & backend
  elif args.hasKey("cpp") and args["cpp"].getBool:
    backendFlag = "--backend:cpp"

  var results: seq[string] = @[]
  for fileNode in args["files"]:
    let filePath = fileNode.getStr
    var nimArgs = @["check"]
    if backendFlag.len > 0:
      nimArgs.add(backendFlag)
    nimArgs.add(filePath)
    let (exitCode, output) = runProcess("nim", nimArgs, workingDir)
    if exitCode == 0:
      results.add(&"OK: {filePath}")
    else:
      results.add(&"FAIL: {filePath}: {output.strip()}")
  return results.join("\n")


proc nimbleTest(args: JsonNode): string =
  ## Run nimble test in a working directory.
  let workingDir = resolveWorkingDir(args)
  let (exitCode, output) = runProcess("nimble", @["test"], workingDir)
  if exitCode == 0:
    return output.strip()
  return &"Error executing nimble test (exit code {exitCode}): {output}"


proc nimVersion(args: JsonNode): string =
  ## Return nim version information.
  let workingDir = resolveWorkingDir(args)
  let (exitCode, output) = runProcess("nim", @["--version"], workingDir)
  if exitCode == 0:
    return output.strip()
  return &"Error executing nim --version (exit code {exitCode}): {output}"


proc findFiles(args: JsonNode): string =
  ## Find files by optional regex over full file paths.
  let path = if args.hasKey("path"): args["path"].getStr else: "."
  let regexStr = if args.hasKey("regex"): args["regex"].getStr else: ""
  let recursive = if args.hasKey("recursive"): args["recursive"].getBool else: true

  if not dirExists(path):
    return &"Directory does not exist: {path}"

  var files: seq[string] = @[]
  var rx: Regex
  if regexStr.len > 0:
    try:
      rx = re(regexStr)
    except:
      return &"Invalid regex: {regexStr}"

  if recursive:
    for filePath in walkDirRec(path):
      if regexStr.len == 0 or filePath.match(rx):
        files.add(filePath)
  else:
    for kind, filePath in walkDir(path):
      if kind == pcFile and (regexStr.len == 0 or filePath.match(rx)):
        files.add(filePath)

  return files.join("\n")


proc readFileTool(args: JsonNode): string =
  ## Read full file contents.
  let validationError = validateToolArgs(args, "read_file", @["file_path"])
  if validationError.len > 0:
    return validationError

  let filePath = args["file_path"].getStr
  try:
    return truncateToolOutput(readFile(filePath), "read_file")
  except:
    return &"Failed to read file {filePath}: {getCurrentExceptionMsg()}"


proc awkTool(args: JsonNode): string =
  ## Execute awk script against a file.
  let validationError = validateToolArgs(args, "awk", @["file_path", "awk_script"])
  if validationError.len > 0:
    return validationError

  let filePath = args["file_path"].getStr
  let awkScript = args["awk_script"].getStr
  let workingDir = resolveWorkingDir(args)
  let (exitCode, output) = runProcess("awk", @[awkScript, filePath], workingDir)
  if exitCode == 0:
    return truncateToolOutput(output.strip(), "awk")
  return &"Error executing awk (exit code {exitCode}): {output}"


proc ripgrepTool(args: JsonNode): string =
  ## Search inside files with ripgrep.
  let validationError = validateToolArgs(args, "ripgrep", @["pattern"])
  if validationError.len > 0:
    return validationError

  let pattern = args["pattern"].getStr
  let path = if args.hasKey("path") and args["path"].getStr.len > 0: args["path"].getStr else: "."
  let workingDir = resolveWorkingDir(args)
  let ignoreCase = if args.hasKey("ignore_case"): args["ignore_case"].getBool else: false
  let lineNumbers = if args.hasKey("line_numbers"): args["line_numbers"].getBool else: true
  let maxCount = if args.hasKey("max_count"): args["max_count"].getInt else: 100

  var rgArgs: seq[string] = @[]
  if ignoreCase:
    rgArgs.add("--ignore-case")
  if lineNumbers:
    rgArgs.add("--line-number")
  if maxCount > 0:
    rgArgs.add(&"--max-count={maxCount}")
  rgArgs.add(pattern)
  rgArgs.add(path)

  let (exitCode, output) = runProcess("rg", rgArgs, workingDir)
  if exitCode == 0:
    return truncateToolOutput(output.strip(), "ripgrep")
  if exitCode == 1:
    return "No matches found"
  return &"Error executing ripgrep (exit code {exitCode}): {output}"


proc gitStatus(args: JsonNode): string =
  ## Return git status.
  let workingDir = resolveWorkingDir(args)
  let (exitCode, output) = runProcess("git", @["status"], workingDir)
  if exitCode == 0:
    return output.strip()
  return &"Error executing git status (exit code {exitCode}): {output}"


proc gitDiff(args: JsonNode): string =
  ## Return git diff for unstaged changes.
  let workingDir = resolveWorkingDir(args)
  let (exitCode, output) = runProcess("git", @["diff"], workingDir)
  if exitCode == 0:
    return output.strip()
  return &"Error executing git diff (exit code {exitCode}): {output}"


proc createIssueTool(args: JsonNode): string =
  ## Collect an issue definition payload for later handling.
  let validationError = validateToolArgs(args, "create_issue", @["title"])
  if validationError.len > 0:
    return validationError

  let title = args["title"].getStr
  if title.len == 0:
    return "Error: 'title' cannot be empty"

  var issue = %*{"title": title}
  if args.hasKey("body"):
    issue["body"] = args["body"]
  if args.hasKey("labels"):
    issue["labels"] = args["labels"]
  if args.hasKey("assignee"):
    issue["assignee"] = args["assignee"]
  if args.hasKey("assignees"):
    issue["assignees"] = args["assignees"]
  if args.hasKey("milestone"):
    issue["milestone"] = args["milestone"]
  if args.hasKey("due_date"):
    issue["due_date"] = args["due_date"]
  if args.hasKey("ref"):
    issue["ref"] = args["ref"]

  collectedIssues.add(issue)
  return &"Issue definition collected: '{title}'."


proc clearCollectedIssues*() =
  ## Clear all collected issue definitions.
  collectedIssues.setLen(0)


proc getCollectedIssues*(): seq[JsonNode] =
  ## Return collected issue definitions.
  return collectedIssues


proc getTyposReadTools*(): ResponseToolsTable =
  ## Build and return the read-only tool registry for Typoi/Typos.
  result = newResponseToolsTable()

  result.register("system_pwd", ToolFunction(
    name: "system_pwd",
    description: option("Get the current working directory"),
    parameters: option(%*{"type": "object", "properties": {"working_dir": {"type": "string"}}, "required": []})
  ), systemPwd)

  result.register("system_ls", ToolFunction(
    name: "system_ls",
    description: option("List directory contents"),
    parameters: option(%*{"type": "object", "properties": {"path": {"type": "string"}, "working_dir": {"type": "string"}}, "required": ["path"]})
  ), systemLs)

  result.register("nim_check", ToolFunction(
    name: "nim_check",
    description: option("Run nim check on Nim source files"),
    parameters: option(%*{
      "type": "object",
      "properties": {
        "files": {"type": "array", "items": {"type": "string"}},
        "working_dir": {"type": "string"},
        "backend": {"type": "string"},
        "cpp": {"type": "boolean"}
      },
      "required": ["files"]
    })
  ), nimCheck)

  result.register("nimble_test", ToolFunction(
    name: "nimble_test",
    description: option("Run nimble test"),
    parameters: option(%*{"type": "object", "properties": {"working_dir": {"type": "string"}}, "required": []})
  ), nimbleTest)

  result.register("nim_version", ToolFunction(
    name: "nim_version",
    description: option("Get Nim version"),
    parameters: option(%*{"type": "object", "properties": {"working_dir": {"type": "string"}}, "required": []})
  ), nimVersion)

  result.register("find_files", ToolFunction(
    name: "find_files",
    description: option("Find files by regex over full file paths"),
    parameters: option(%*{"type": "object", "properties": {"path": {"type": "string"}, "regex": {"type": "string"}, "recursive": {"type": "boolean"}}, "required": []})
  ), findFiles)

  result.register("read_file", ToolFunction(
    name: "read_file",
    description: option("Read file contents"),
    parameters: option(%*{"type": "object", "properties": {"file_path": {"type": "string"}}, "required": ["file_path"]})
  ), readFileTool)

  result.register("awk", ToolFunction(
    name: "awk",
    description: option("Run awk script against file"),
    parameters: option(%*{"type": "object", "properties": {"file_path": {"type": "string"}, "awk_script": {"type": "string"}, "working_dir": {"type": "string"}}, "required": ["file_path", "awk_script"]})
  ), awkTool)

  result.register("ripgrep", ToolFunction(
    name: "ripgrep",
    description: option("Search file contents with ripgrep"),
    parameters: option(%*{"type": "object", "properties": {"pattern": {"type": "string"}, "path": {"type": "string"}, "working_dir": {"type": "string"}, "ignore_case": {"type": "boolean"}, "line_numbers": {"type": "boolean"}, "max_count": {"type": "integer"}}, "required": ["pattern"]})
  ), ripgrepTool)

  result.register("git_status", ToolFunction(
    name: "git_status",
    description: option("Get git status"),
    parameters: option(%*{"type": "object", "properties": {"working_dir": {"type": "string"}}, "required": []})
  ), gitStatus)

  result.register("git_diff", ToolFunction(
    name: "git_diff",
    description: option("Get unstaged git diff"),
    parameters: option(%*{"type": "object", "properties": {"working_dir": {"type": "string"}}, "required": []})
  ), gitDiff)

  result.register("create_issue", ToolFunction(
    name: "create_issue",
    description: option("Collect issue definition payload"),
    parameters: option(%*{
      "type": "object",
      "properties": {
        "title": {"type": "string"},
        "body": {"type": "string"},
        "labels": {"type": "array", "items": {"type": "string"}},
        "assignee": {"type": "string"},
        "assignees": {"type": "array", "items": {"type": "string"}},
        "milestone": {"type": "integer"},
        "due_date": {"type": "string"},
        "ref": {"type": "string"}
      },
      "required": ["title"]
    })
  ), createIssueTool)
