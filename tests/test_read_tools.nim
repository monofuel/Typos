import
  std/[json, os, osproc, streams, strutils, times, unittest],
  openai_leap,
  Typos/tools


proc callTool(tools: ResponseToolsTable, name: string, args: JsonNode): string =
  ## Call a registered read tool and return its output.
  let (_, toolImpl) = tools[name]
  return toolImpl(args)


proc makeTempDir(prefix: string): string =
  ## Create a unique temporary directory for test fixtures.
  result = getTempDir() / (prefix & "_" & $epochTime().int64)
  createDir(result)


proc runCmd(workingDir: string, command: string, args: seq[string]) =
  ## Run a command and fail the current test if it exits non-zero.
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
  check exitCode == 0


suite "read tools":
  let tools = getTyposReadTools()

  test "registry contains all read tools":
    let expected = @[
      "system_pwd", "system_ls", "nim_check", "nimble_test", "nim_version",
      "find_files", "read_file", "awk", "ripgrep", "git_status", "git_diff"
    ]
    for name in expected:
      check tools.hasKey(name)

  test "system_pwd":
    let dirPath = makeTempDir("typos_pwd")
    defer: removeDir(dirPath)
    let output = callTool(tools, "system_pwd", %*{"working_dir": dirPath})
    check output.strip() == dirPath

  test "system_ls":
    let dirPath = makeTempDir("typos_ls")
    defer: removeDir(dirPath)
    writeFile(dirPath / "a.txt", "hello")
    let output = callTool(tools, "system_ls", %*{"path": ".", "working_dir": dirPath})
    check "a.txt" in output

  test "nim_check":
    let dirPath = makeTempDir("typos_nim_check")
    defer: removeDir(dirPath)
    let filePath = dirPath / "ok.nim"
    writeFile(filePath, "discard\n")
    let output = callTool(tools, "nim_check", %*{"files": @["ok.nim"], "working_dir": dirPath})
    check "OK: ok.nim" in output

  test "nimble_test":
    let dirPath = makeTempDir("typos_nimble_test")
    defer: removeDir(dirPath)
    createDir(dirPath / "tests")
    writeFile(
      dirPath / "sample.nimble",
      "version = \"0.1.0\"\n" &
      "author = \"test\"\n" &
      "description = \"test\"\n" &
      "license = \"MIT\"\n" &
      "task test, \"run tests\":\n" &
      "  exec \"nim c -r tests/test_sample.nim\"\n"
    )
    writeFile(
      dirPath / "tests/test_sample.nim",
      "import std/unittest\nsuite \"sample\":\n  test \"ok\":\n    check true\n"
    )
    let output = callTool(tools, "nimble_test", %*{"working_dir": dirPath})
    check output.toLowerAscii().contains("ok")

  test "nim_version":
    let output = callTool(tools, "nim_version", %*{})
    check "Nim Compiler Version" in output

  test "find_files":
    let dirPath = makeTempDir("typos_find_files")
    defer: removeDir(dirPath)
    writeFile(dirPath / "alpha.txt", "a")
    writeFile(dirPath / "beta.nim", "discard\n")
    let output = callTool(tools, "find_files", %*{"path": dirPath, "regex": ".*\\.nim$"})
    check "beta.nim" in output

  test "read_file":
    let dirPath = makeTempDir("typos_read_file")
    defer: removeDir(dirPath)
    let filePath = dirPath / "data.txt"
    writeFile(filePath, "hello world\n")
    let output = callTool(tools, "read_file", %*{"file_path": filePath})
    check output == "hello world\n"

  test "awk":
    let dirPath = makeTempDir("typos_awk")
    defer: removeDir(dirPath)
    let filePath = dirPath / "nums.txt"
    writeFile(filePath, "1\n2\n3\n")
    let output = callTool(
      tools,
      "awk",
      %*{"file_path": filePath, "awk_script": "{sum += $1} END {print sum}", "working_dir": dirPath}
    )
    check output.strip() == "6"

  test "ripgrep":
    let dirPath = makeTempDir("typos_ripgrep")
    defer: removeDir(dirPath)
    writeFile(dirPath / "main.txt", "hello tool world\n")
    let output = callTool(tools, "ripgrep", %*{"pattern": "tool", "path": dirPath, "working_dir": dirPath})
    check "main.txt" in output
    check "tool" in output

  test "git_status":
    let dirPath = makeTempDir("typos_git_status")
    defer: removeDir(dirPath)
    runCmd(dirPath, "git", @["init"])
    runCmd(dirPath, "git", @["config", "user.email", "test@example.com"])
    runCmd(dirPath, "git", @["config", "user.name", "Test User"])
    writeFile(dirPath / "tracked.txt", "a\n")
    runCmd(dirPath, "git", @["add", "tracked.txt"])
    runCmd(dirPath, "git", @["commit", "-m", "init"])
    writeFile(dirPath / "tracked.txt", "b\n")
    let output = callTool(tools, "git_status", %*{"working_dir": dirPath})
    check output.toLowerAscii().contains("modified")

  test "git_diff":
    let dirPath = makeTempDir("typos_git_diff")
    defer: removeDir(dirPath)
    runCmd(dirPath, "git", @["init"])
    runCmd(dirPath, "git", @["config", "user.email", "test@example.com"])
    runCmd(dirPath, "git", @["config", "user.name", "Test User"])
    writeFile(dirPath / "tracked.txt", "a\n")
    runCmd(dirPath, "git", @["add", "tracked.txt"])
    runCmd(dirPath, "git", @["commit", "-m", "init"])
    writeFile(dirPath / "tracked.txt", "b\n")
    let output = callTool(tools, "git_diff", %*{"working_dir": dirPath})
    check output.contains("-a")
    check output.contains("+b")

suite "read+write tools":
  let tools = getTyposReadWriteTools()

  test "registry includes write tools":
    check tools.hasKey("create_issue")

  test "create_issue":
    clearCollectedIssues()
    let output = callTool(
      tools,
      "create_issue",
      %*{"title": "Bug title", "body": "Bug body", "labels": @["bug"]}
    )
    let issues = getCollectedIssues()
    check output.contains("Issue definition collected")
    check issues.len == 1
    check issues[0]["title"].getStr == "Bug title"
    check issues[0]["body"].getStr == "Bug body"
