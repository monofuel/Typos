import
  std/[json, options, os, osproc, re, streams, strformat, strutils],
  openai_leap

type
  ToolOps* = object
    fileExists*: proc(path: string): bool
    dirExists*: proc(path: string): bool
    readFile*: proc(path: string): string
    writeFile*: proc(path: string, content: string)
    createDir*: proc(path: string)
    removeFile*: proc(path: string)
    moveFile*: proc(source, dest: string)


const
  MaxToolOutputChars = 100000


var collectedIssues*: seq[JsonNode] = @[]

var activeToolEventCallback*: proc(name: string, args: JsonNode, output: string) {.closure.}


proc defaultFileExists(path: string): bool =
  ## Check whether a file exists on disk.
  return fileExists(path)


proc defaultDirExists(path: string): bool =
  ## Check whether a directory exists on disk.
  return dirExists(path)


proc defaultReadFile(path: string): string =
  ## Read file contents from disk.
  return readFile(path)


proc defaultWriteFile(path: string, content: string) =
  ## Write file contents to disk.
  writeFile(path, content)


proc defaultCreateDir(path: string) =
  ## Create directory on disk.
  createDir(path)


proc defaultRemoveFile(path: string) =
  ## Remove a file on disk.
  removeFile(path)


proc defaultMoveFile(source, dest: string) =
  ## Move a file on disk.
  moveFile(source, dest)


let defaultToolOps = ToolOps(
  fileExists: defaultFileExists,
  dirExists: defaultDirExists,
  readFile: defaultReadFile,
  writeFile: defaultWriteFile,
  createDir: defaultCreateDir,
  removeFile: defaultRemoveFile,
  moveFile: defaultMoveFile
)


var activeToolOps = defaultToolOps


proc setToolOps*(ops: ToolOps) =
  ## Set tool operation handlers, used by tests for mocking.
  activeToolOps = ops


proc resetToolOps*() =
  ## Reset tool operation handlers to default filesystem-backed operations.
  activeToolOps = defaultToolOps


proc setToolEventCallback*(
  callback: proc(name: string, args: JsonNode, output: string) {.closure.}
) =
  ## Set a callback that receives tool execution events.
  activeToolEventCallback = callback


proc clearToolEventCallback*() =
  ## Clear the active tool execution callback.
  activeToolEventCallback = nil


proc notifyToolEvent(name: string, args: JsonNode, output: string) =
  ## Notify the active callback after a tool finishes execution.
  if not activeToolEventCallback.isNil:
    activeToolEventCallback(name, args, output)


template registerTyposTool(
  tools: ResponseToolsTable,
  toolName: string,
  toolFunction: ToolFunction,
  impl: untyped
) =
  ## Register a tool and wrap it with optional event notification.
  tools.register(toolName, toolFunction, proc(args: JsonNode): string =
    let output = impl(args)
    notifyToolEvent(toolName, args, output)
    return output
  )


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
    if rawDir.len > 0 and activeToolOps.dirExists(rawDir):
      return rawDir
  return getCurrentDir()


proc truncateToolOutput(output: string, toolName: string): string =
  ## Truncate large tool output to keep responses bounded.
  if output.len > MaxToolOutputChars:
    let truncated = output[0..<MaxToolOutputChars]
    return truncated & &"\n\n[TRUNCATED: Output was {output.len} chars for {toolName}]"
  return output


proc splitContentLines(content: string): seq[string] =
  ## Split content on newlines, stripping trailing empty element from trailing newline.
  result = content.split('\n')
  if result.len > 0 and result[^1] == "":
    result.setLen(result.len - 1)


proc readFileLines(filePath: string): seq[string] =
  ## Read a file and return its lines.
  return splitContentLines(activeToolOps.readFile(filePath))


proc joinLinesWithTrailingNewline(lines: seq[string]): string =
  ## Join lines with newlines, ensuring a trailing newline. Empty seq returns "".
  if lines.len == 0:
    return ""
  return lines.join("\n") & "\n"


proc generateSnippet(lines: seq[string], changeStart, changeEnd: int, contextLines = 3): string =
  ## Generate a numbered snippet showing changed area with context lines.
  let snippetStart = max(0, changeStart - contextLines)
  let snippetEnd = min(lines.len - 1, changeEnd + contextLines)
  var parts: seq[string] = @[]
  for i in snippetStart..snippetEnd:
    parts.add(&"{i + 1:4d}| {lines[i]}")
  return parts.join("\n")


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
  if not activeToolOps.fileExists(filePath):
    return &"Failed to read file {filePath}: file does not exist."
  return truncateToolOutput(activeToolOps.readFile(filePath), "read_file")


proc writeFileTool(args: JsonNode): string =
  ## Write file contents, optionally refusing overwrite.
  let validationError = validateToolArgs(args, "write_file", @["file_path", "content"])
  if validationError.len > 0:
    return validationError

  let filePath = args["file_path"].getStr
  let content = args["content"].getStr
  let overwrite = if args.hasKey("overwrite"): args["overwrite"].getBool else: true
  if not overwrite and activeToolOps.fileExists(filePath):
    return &"Refusing to overwrite existing file: {filePath}"

  activeToolOps.writeFile(filePath, content)
  return &"Wrote {content.len} bytes to {filePath}."


proc appendFileTool(args: JsonNode): string =
  ## Append content to a file, creating it if missing.
  let validationError = validateToolArgs(args, "append_file", @["file_path", "content"])
  if validationError.len > 0:
    return validationError

  let filePath = args["file_path"].getStr
  let content = args["content"].getStr
  let existing = if activeToolOps.fileExists(filePath): activeToolOps.readFile(filePath) else: ""
  activeToolOps.writeFile(filePath, existing & content)
  return &"Appended {content.len} bytes to {filePath}."


proc replaceInFileTool(args: JsonNode): string =
  ## Replace text in file content, once or globally.
  let validationError = validateToolArgs(args, "replace_in_file", @["file_path", "old_text", "new_text"])
  if validationError.len > 0:
    return validationError

  let filePath = args["file_path"].getStr
  if not activeToolOps.fileExists(filePath):
    return &"File does not exist: {filePath}"

  let oldText = args["old_text"].getStr
  let newText = args["new_text"].getStr
  let replaceAll = if args.hasKey("replace_all"): args["replace_all"].getBool else: false
  if oldText.len == 0:
    return "old_text cannot be empty."

  let original = activeToolOps.readFile(filePath)
  let firstMatch = original.find(oldText)
  if firstMatch < 0:
    return &"No matches found for replacement in {filePath}."

  if replaceAll:
    let replaced = original.replace(oldText, newText)
    activeToolOps.writeFile(filePath, replaced)
    let replacedCount = original.count(oldText)
    return &"Replaced {replacedCount} occurrence(s) in {filePath}."

  let prefix = original[0 ..< firstMatch]
  let suffixStart = firstMatch + oldText.len
  let suffix = if suffixStart < original.len: original[suffixStart .. ^1] else: ""
  activeToolOps.writeFile(filePath, prefix & newText & suffix)
  return &"Replaced 1 occurrence(s) in {filePath}."


proc createDirectoryTool(args: JsonNode): string =
  ## Create a directory.
  let validationError = validateToolArgs(args, "create_directory", @["dir_path"])
  if validationError.len > 0:
    return validationError

  let dirPath = args["dir_path"].getStr
  if activeToolOps.dirExists(dirPath):
    return &"Directory already exists: {dirPath}"

  activeToolOps.createDir(dirPath)
  return &"Created directory: {dirPath}"


proc deleteFileTool(args: JsonNode): string =
  ## Delete a file when present.
  let validationError = validateToolArgs(args, "delete_file", @["file_path"])
  if validationError.len > 0:
    return validationError

  let filePath = args["file_path"].getStr
  if not activeToolOps.fileExists(filePath):
    return &"File does not exist: {filePath}"

  activeToolOps.removeFile(filePath)
  return &"Deleted file: {filePath}"


proc moveFileTool(args: JsonNode): string =
  ## Move or rename a file.
  let validationError = validateToolArgs(args, "move_file", @["source", "destination"])
  if validationError.len > 0:
    return validationError

  let source = args["source"].getStr
  let destination = args["destination"].getStr
  if not activeToolOps.fileExists(source):
    return &"Source file does not exist: {source}"

  activeToolOps.moveFile(source, destination)
  return &"Moved {source} to {destination}."


proc sedEditTool(args: JsonNode): string =
  ## Execute sed script against a file (in-place edit).
  let validationError = validateToolArgs(args, "sed_edit", @["file_path", "sed_script"])
  if validationError.len > 0:
    return validationError

  let filePath = args["file_path"].getStr
  let sedScript = args["sed_script"].getStr
  let workingDir = resolveWorkingDir(args)
  let (exitCode, output) = runProcess("sed", @["-i", sedScript, filePath], workingDir)
  if exitCode == 0:
    return &"sed edit applied to {filePath}."
  return &"Error executing sed (exit code {exitCode}): {output}"


proc insertLinesTool(args: JsonNode): string =
  ## Insert lines after a given line number (0 = beginning of file).
  let validationError = validateToolArgs(args, "insert_lines", @["file_path", "after_line", "content"])
  if validationError.len > 0:
    return validationError

  let filePath = args["file_path"].getStr
  let afterLine = args["after_line"].getInt
  let content = args["content"].getStr

  if not activeToolOps.fileExists(filePath):
    return &"File does not exist: {filePath}"

  var lines = readFileLines(filePath)
  if afterLine < 0 or afterLine > lines.len:
    return &"after_line {afterLine} is out of range (0..{lines.len})."

  let newLines = splitContentLines(content)
  let insertPos = afterLine
  for i, line in newLines:
    lines.insert(line, insertPos + i)

  activeToolOps.writeFile(filePath, joinLinesWithTrailingNewline(lines))
  let snippet = generateSnippet(lines, insertPos, insertPos + newLines.len - 1)
  return &"Inserted {newLines.len} line(s) after line {afterLine} in {filePath}.\n{snippet}"


proc deleteLinesTool(args: JsonNode): string =
  ## Delete a range of lines (1-based, inclusive).
  let validationError = validateToolArgs(args, "delete_lines", @["file_path", "start_line", "end_line"])
  if validationError.len > 0:
    return validationError

  let filePath = args["file_path"].getStr
  let startLine = args["start_line"].getInt
  let endLine = args["end_line"].getInt

  if not activeToolOps.fileExists(filePath):
    return &"File does not exist: {filePath}"

  if startLine < 1 or endLine < startLine:
    return &"Invalid line range: {startLine}..{endLine}."

  var lines = readFileLines(filePath)
  if endLine > lines.len:
    return &"end_line {endLine} exceeds file length ({lines.len} lines)."

  let deletedCount = endLine - startLine + 1
  let before = lines[0 ..< startLine - 1]
  let after = if endLine < lines.len: lines[endLine .. ^1] else: @[]
  lines = before & after

  activeToolOps.writeFile(filePath, joinLinesWithTrailingNewline(lines))
  if lines.len == 0:
    return &"Deleted {deletedCount} line(s) from {filePath}. File is now empty."
  let snippetStart = max(0, startLine - 2)
  let snippetEnd = min(lines.len - 1, snippetStart + 5)
  let snippet = generateSnippet(lines, snippetStart, snippetEnd)
  return &"Deleted {deletedCount} line(s) from {filePath}.\n{snippet}"


proc replaceLinesTool(args: JsonNode): string =
  ## Replace a range of lines (1-based, inclusive) with new content.
  let validationError = validateToolArgs(args, "replace_lines", @["file_path", "start_line", "end_line", "content"])
  if validationError.len > 0:
    return validationError

  let filePath = args["file_path"].getStr
  let startLine = args["start_line"].getInt
  let endLine = args["end_line"].getInt
  let content = args["content"].getStr

  if not activeToolOps.fileExists(filePath):
    return &"File does not exist: {filePath}"

  if startLine < 1 or endLine < startLine:
    return &"Invalid line range: {startLine}..{endLine}."

  var lines = readFileLines(filePath)
  if endLine > lines.len:
    return &"end_line {endLine} exceeds file length ({lines.len} lines)."

  let newLines = splitContentLines(content)
  let before = lines[0 ..< startLine - 1]
  let after = if endLine < lines.len: lines[endLine .. ^1] else: @[]
  lines = before & newLines & after

  activeToolOps.writeFile(filePath, joinLinesWithTrailingNewline(lines))
  let snippet = generateSnippet(lines, startLine - 1, startLine - 1 + newLines.len - 1)
  return &"Replaced lines {startLine}..{endLine} in {filePath}.\n{snippet}"


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


proc gitLog(args: JsonNode): string =
  ## Return recent git log entries.
  let workingDir = resolveWorkingDir(args)
  let count = if args.hasKey("count"): args["count"].getInt else: 10
  var gitArgs = @["log", "--oneline", "-n", $count]
  if args.hasKey("file_path"):
    let filePath = args["file_path"].getStr
    if filePath.len > 0:
      gitArgs.add("--")
      gitArgs.add(filePath)
  let (exitCode, output) = runProcess("git", gitArgs, workingDir)
  if exitCode == 0:
    return output.strip()
  return &"Error executing git log (exit code {exitCode}): {output}"


proc gitDiffStaged(args: JsonNode): string =
  ## Return git diff for staged changes.
  let workingDir = resolveWorkingDir(args)
  let (exitCode, output) = runProcess("git", @["diff", "--cached"], workingDir)
  if exitCode == 0:
    return output.strip()
  return &"Error executing git diff --cached (exit code {exitCode}): {output}"


proc gitShow(args: JsonNode): string =
  ## Show a git object (commit, file at ref, etc).
  let validationError = validateToolArgs(args, "git_show", @["ref"])
  if validationError.len > 0:
    return validationError

  let workingDir = resolveWorkingDir(args)
  let refStr = args["ref"].getStr
  var target = refStr
  if args.hasKey("file_path"):
    let filePath = args["file_path"].getStr
    if filePath.len > 0:
      target = refStr & ":" & filePath
  let (exitCode, output) = runProcess("git", @["show", target], workingDir)
  if exitCode == 0:
    return truncateToolOutput(output.strip(), "git_show")
  return &"Error executing git show (exit code {exitCode}): {output}"


proc gitBranch(args: JsonNode): string =
  ## List git branches.
  let workingDir = resolveWorkingDir(args)
  let (exitCode, output) = runProcess("git", @["branch"], workingDir)
  if exitCode == 0:
    return output.strip()
  return &"Error executing git branch (exit code {exitCode}): {output}"


proc gitAdd(args: JsonNode): string =
  ## Stage files for commit.
  let validationError = validateToolArgs(args, "git_add", @["paths"])
  if validationError.len > 0:
    return validationError

  let workingDir = resolveWorkingDir(args)
  var paths: seq[string] = @[]
  for pathNode in args["paths"]:
    paths.add(pathNode.getStr)
  let (exitCode, output) = runProcess("git", @["add"] & paths, workingDir)
  if exitCode == 0:
    return "Staged: " & paths.join(", ")
  return &"Error executing git add (exit code {exitCode}): {output}"


proc gitCommit(args: JsonNode): string =
  ## Create a git commit.
  let validationError = validateToolArgs(args, "git_commit", @["message"])
  if validationError.len > 0:
    return validationError

  let message = args["message"].getStr
  if message.strip().len == 0:
    return "Error: commit message cannot be empty."

  let workingDir = resolveWorkingDir(args)
  let (exitCode, output) = runProcess("git", @["commit", "-m", message], workingDir)
  if exitCode == 0:
    return output.strip()
  return &"Error executing git commit (exit code {exitCode}): {output}"


proc gitRestore(args: JsonNode): string =
  ## Restore files (discard changes or unstage).
  let validationError = validateToolArgs(args, "git_restore", @["paths"])
  if validationError.len > 0:
    return validationError

  let workingDir = resolveWorkingDir(args)
  let staged = if args.hasKey("staged"): args["staged"].getBool else: false
  var paths: seq[string] = @[]
  for pathNode in args["paths"]:
    paths.add(pathNode.getStr)
  var gitArgs = @["restore"]
  if staged:
    gitArgs.add("--staged")
  gitArgs.add(paths)
  let (exitCode, output) = runProcess("git", gitArgs, workingDir)
  if exitCode == 0:
    let action = if staged: "Unstaged" else: "Restored"
    return action & ": " & paths.join(", ")
  return &"Error executing git restore (exit code {exitCode}): {output}"


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

  result.registerTyposTool("system_pwd", ToolFunction(
    name: "system_pwd",
    description: option("Get the current working directory"),
    parameters: option(%*{"type": "object", "properties": {"working_dir": {"type": "string"}}, "required": []})
  ), systemPwd)

  result.registerTyposTool("system_ls", ToolFunction(
    name: "system_ls",
    description: option("List directory contents"),
    parameters: option(%*{"type": "object", "properties": {"path": {"type": "string"}, "working_dir": {"type": "string"}}, "required": ["path"]})
  ), systemLs)

  result.registerTyposTool("nim_check", ToolFunction(
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

  result.registerTyposTool("nimble_test", ToolFunction(
    name: "nimble_test",
    description: option("Run nimble test"),
    parameters: option(%*{"type": "object", "properties": {"working_dir": {"type": "string"}}, "required": []})
  ), nimbleTest)

  result.registerTyposTool("nim_version", ToolFunction(
    name: "nim_version",
    description: option("Get Nim version"),
    parameters: option(%*{"type": "object", "properties": {"working_dir": {"type": "string"}}, "required": []})
  ), nimVersion)

  result.registerTyposTool("find_files", ToolFunction(
    name: "find_files",
    description: option("Find files by regex over full file paths"),
    parameters: option(%*{"type": "object", "properties": {"path": {"type": "string"}, "regex": {"type": "string"}, "recursive": {"type": "boolean"}}, "required": []})
  ), findFiles)

  result.registerTyposTool("read_file", ToolFunction(
    name: "read_file",
    description: option("Read file contents"),
    parameters: option(%*{"type": "object", "properties": {"file_path": {"type": "string"}}, "required": ["file_path"]})
  ), readFileTool)

  result.registerTyposTool("awk", ToolFunction(
    name: "awk",
    description: option("Run awk script against file"),
    parameters: option(%*{"type": "object", "properties": {"file_path": {"type": "string"}, "awk_script": {"type": "string"}, "working_dir": {"type": "string"}}, "required": ["file_path", "awk_script"]})
  ), awkTool)

  result.registerTyposTool("ripgrep", ToolFunction(
    name: "ripgrep",
    description: option("Search file contents with ripgrep"),
    parameters: option(%*{"type": "object", "properties": {"pattern": {"type": "string"}, "path": {"type": "string"}, "working_dir": {"type": "string"}, "ignore_case": {"type": "boolean"}, "line_numbers": {"type": "boolean"}, "max_count": {"type": "integer"}}, "required": ["pattern"]})
  ), ripgrepTool)

  result.registerTyposTool("git_status", ToolFunction(
    name: "git_status",
    description: option("Get git status"),
    parameters: option(%*{"type": "object", "properties": {"working_dir": {"type": "string"}}, "required": []})
  ), gitStatus)

  result.registerTyposTool("git_diff", ToolFunction(
    name: "git_diff",
    description: option("Get unstaged git diff"),
    parameters: option(%*{"type": "object", "properties": {"working_dir": {"type": "string"}}, "required": []})
  ), gitDiff)

  result.registerTyposTool("git_log", ToolFunction(
    name: "git_log",
    description: option("Show recent git log entries"),
    parameters: option(%*{
      "type": "object",
      "properties": {
        "count": {"type": "integer"},
        "file_path": {"type": "string"},
        "working_dir": {"type": "string"}
      },
      "required": []
    })
  ), gitLog)

  result.registerTyposTool("git_diff_staged", ToolFunction(
    name: "git_diff_staged",
    description: option("Get staged git diff"),
    parameters: option(%*{"type": "object", "properties": {"working_dir": {"type": "string"}}, "required": []})
  ), gitDiffStaged)

  result.registerTyposTool("git_show", ToolFunction(
    name: "git_show",
    description: option("Show a git object (commit or file at ref)"),
    parameters: option(%*{
      "type": "object",
      "properties": {
        "ref": {"type": "string"},
        "file_path": {"type": "string"},
        "working_dir": {"type": "string"}
      },
      "required": ["ref"]
    })
  ), gitShow)

  result.registerTyposTool("git_branch", ToolFunction(
    name: "git_branch",
    description: option("List git branches"),
    parameters: option(%*{"type": "object", "properties": {"working_dir": {"type": "string"}}, "required": []})
  ), gitBranch)


proc getTyposReadWriteTools*(): ResponseToolsTable =
  ## Build and return the read+write tool registry for Typoi/Typos.
  result = getTyposReadTools()

  result.registerTyposTool("write_file", ToolFunction(
    name: "write_file",
    description: option("Write full file contents"),
    parameters: option(%*{"type": "object", "properties": {"file_path": {"type": "string"}, "content": {"type": "string"}, "overwrite": {"type": "boolean"}}, "required": ["file_path", "content"]})
  ), writeFileTool)

  result.registerTyposTool("append_file", ToolFunction(
    name: "append_file",
    description: option("Append content to file"),
    parameters: option(%*{"type": "object", "properties": {"file_path": {"type": "string"}, "content": {"type": "string"}}, "required": ["file_path", "content"]})
  ), appendFileTool)

  result.registerTyposTool("replace_in_file", ToolFunction(
    name: "replace_in_file",
    description: option("Replace content inside file text"),
    parameters: option(%*{"type": "object", "properties": {"file_path": {"type": "string"}, "old_text": {"type": "string"}, "new_text": {"type": "string"}, "replace_all": {"type": "boolean"}}, "required": ["file_path", "old_text", "new_text"]})
  ), replaceInFileTool)

  result.registerTyposTool("create_directory", ToolFunction(
    name: "create_directory",
    description: option("Create directory"),
    parameters: option(%*{"type": "object", "properties": {"dir_path": {"type": "string"}}, "required": ["dir_path"]})
  ), createDirectoryTool)

  result.registerTyposTool("delete_file", ToolFunction(
    name: "delete_file",
    description: option("Delete file"),
    parameters: option(%*{"type": "object", "properties": {"file_path": {"type": "string"}}, "required": ["file_path"]})
  ), deleteFileTool)

  result.registerTyposTool("move_file", ToolFunction(
    name: "move_file",
    description: option("Move or rename a file"),
    parameters: option(%*{"type": "object", "properties": {"source": {"type": "string"}, "destination": {"type": "string"}}, "required": ["source", "destination"]})
  ), moveFileTool)

  result.registerTyposTool("sed_edit", ToolFunction(
    name: "sed_edit",
    description: option("Run sed in-place edit on a file"),
    parameters: option(%*{"type": "object", "properties": {"file_path": {"type": "string"}, "sed_script": {"type": "string"}, "working_dir": {"type": "string"}}, "required": ["file_path", "sed_script"]})
  ), sedEditTool)

  result.registerTyposTool("insert_lines", ToolFunction(
    name: "insert_lines",
    description: option("Insert lines after a given line number (0 for beginning)"),
    parameters: option(%*{"type": "object", "properties": {"file_path": {"type": "string"}, "after_line": {"type": "integer"}, "content": {"type": "string"}}, "required": ["file_path", "after_line", "content"]})
  ), insertLinesTool)

  result.registerTyposTool("delete_lines", ToolFunction(
    name: "delete_lines",
    description: option("Delete a range of lines (1-based, inclusive)"),
    parameters: option(%*{"type": "object", "properties": {"file_path": {"type": "string"}, "start_line": {"type": "integer"}, "end_line": {"type": "integer"}}, "required": ["file_path", "start_line", "end_line"]})
  ), deleteLinesTool)

  result.registerTyposTool("replace_lines", ToolFunction(
    name: "replace_lines",
    description: option("Replace a range of lines (1-based, inclusive) with new content"),
    parameters: option(%*{"type": "object", "properties": {"file_path": {"type": "string"}, "start_line": {"type": "integer"}, "end_line": {"type": "integer"}, "content": {"type": "string"}}, "required": ["file_path", "start_line", "end_line", "content"]})
  ), replaceLinesTool)

  result.registerTyposTool("create_issue", ToolFunction(
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

  result.registerTyposTool("git_add", ToolFunction(
    name: "git_add",
    description: option("Stage files for commit"),
    parameters: option(%*{
      "type": "object",
      "properties": {
        "paths": {"type": "array", "items": {"type": "string"}},
        "working_dir": {"type": "string"}
      },
      "required": ["paths"]
    })
  ), gitAdd)

  result.registerTyposTool("git_commit", ToolFunction(
    name: "git_commit",
    description: option("Create a git commit"),
    parameters: option(%*{
      "type": "object",
      "properties": {
        "message": {"type": "string"},
        "working_dir": {"type": "string"}
      },
      "required": ["message"]
    })
  ), gitCommit)

  result.registerTyposTool("git_restore", ToolFunction(
    name: "git_restore",
    description: option("Restore files (discard changes or unstage)"),
    parameters: option(%*{
      "type": "object",
      "properties": {
        "paths": {"type": "array", "items": {"type": "string"}},
        "staged": {"type": "boolean"},
        "working_dir": {"type": "string"}
      },
      "required": ["paths"]
    })
  ), gitRestore)
