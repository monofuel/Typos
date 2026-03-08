import
  std/[json, os, osproc, streams, strutils, times, unittest],
  openai_leap,
  Typos/tools


proc callTool(tools: ResponseToolsTable, name: string, args: JsonNode): string =
  let (_, toolImpl) = tools[name]
  return toolImpl(args)


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


proc initGitRepo(dir: string) =
  runCmd(dir, "git", @["init"])
  runCmd(dir, "git", @["config", "user.email", "test@example.com"])
  runCmd(dir, "git", @["config", "user.name", "Test User"])


proc makeCommit(dir: string, filename: string, content: string, message: string) =
  writeFile(dir / filename, content)
  runCmd(dir, "git", @["add", filename])
  runCmd(dir, "git", @["commit", "-m", message])


suite "git read tools":
  let tools = getTyposReadTools()

  test "registry contains new git read tools":
    for name in @["git_log", "git_diff_staged", "git_show", "git_branch"]:
      check tools.hasKey(name)

  test "git_log returns recent commits":
    let dir = makeTempDir("typos_git_log")
    defer: removeDir(dir)
    initGitRepo(dir)
    makeCommit(dir, "a.txt", "a", "first commit")
    makeCommit(dir, "b.txt", "b", "second commit")
    makeCommit(dir, "c.txt", "c", "third commit")

    let output = callTool(tools, "git_log", %*{"count": 2, "working_dir": dir})
    let lines = output.strip().splitLines()
    check lines.len == 2
    check "third commit" in output
    check "second commit" in output

  test "git_log with file_path filters":
    let dir = makeTempDir("typos_git_log_fp")
    defer: removeDir(dir)
    initGitRepo(dir)
    makeCommit(dir, "a.txt", "a", "commit for a")
    makeCommit(dir, "b.txt", "b", "commit for b")

    let output = callTool(tools, "git_log", %*{"file_path": "a.txt", "working_dir": dir})
    check "commit for a" in output
    check "commit for b" notin output

  test "git_diff_staged shows staged changes":
    let dir = makeTempDir("typos_git_diff_staged")
    defer: removeDir(dir)
    initGitRepo(dir)
    makeCommit(dir, "f.txt", "original\n", "init")
    writeFile(dir / "f.txt", "modified\n")
    runCmd(dir, "git", @["add", "f.txt"])

    let output = callTool(tools, "git_diff_staged", %*{"working_dir": dir})
    check "+modified" in output
    check "-original" in output

  test "git_diff_staged empty when nothing staged":
    let dir = makeTempDir("typos_git_diff_staged_empty")
    defer: removeDir(dir)
    initGitRepo(dir)
    makeCommit(dir, "f.txt", "content\n", "init")

    let output = callTool(tools, "git_diff_staged", %*{"working_dir": dir})
    check output.strip().len == 0

  test "git_show displays commit at HEAD":
    let dir = makeTempDir("typos_git_show")
    defer: removeDir(dir)
    initGitRepo(dir)
    makeCommit(dir, "f.txt", "hello\n", "my test commit")

    let output = callTool(tools, "git_show", %*{"ref": "HEAD", "working_dir": dir})
    check "my test commit" in output

  test "git_show with file_path shows file content at ref":
    let dir = makeTempDir("typos_git_show_fp")
    defer: removeDir(dir)
    initGitRepo(dir)
    makeCommit(dir, "f.txt", "version1\n", "v1")
    makeCommit(dir, "f.txt", "version2\n", "v2")

    let output = callTool(tools, "git_show", %*{"ref": "HEAD~1", "file_path": "f.txt", "working_dir": dir})
    check "version1" in output

  test "git_show missing ref returns validation error":
    let output = callTool(tools, "git_show", %*{"working_dir": "."})
    check "Missing required parameter" in output

  test "git_branch lists branches":
    let dir = makeTempDir("typos_git_branch")
    defer: removeDir(dir)
    initGitRepo(dir)
    makeCommit(dir, "f.txt", "a\n", "init")
    runCmd(dir, "git", @["branch", "feature"])

    let output = callTool(tools, "git_branch", %*{"working_dir": dir})
    check "master" in output or "main" in output
    check "feature" in output


suite "git write tools":
  let tools = getTyposReadWriteTools()

  test "registry contains git write tools":
    for name in @["git_add", "git_commit", "git_restore"]:
      check tools.hasKey(name)

  test "git_add stages files":
    let dir = makeTempDir("typos_git_add")
    defer: removeDir(dir)
    initGitRepo(dir)
    makeCommit(dir, "f.txt", "init\n", "init")
    writeFile(dir / "new.txt", "new content\n")

    let output = callTool(tools, "git_add", %*{"paths": ["new.txt"], "working_dir": dir})
    check "Staged" in output
    check "new.txt" in output

    # Verify it's actually staged
    let status = callTool(tools, "git_status", %*{"working_dir": dir})
    check "new file" in status.toLowerAscii()

  test "git_add missing paths returns validation error":
    let output = callTool(tools, "git_add", %*{"working_dir": "."})
    check "Missing required parameter" in output

  test "git_commit creates commit with message":
    let dir = makeTempDir("typos_git_commit")
    defer: removeDir(dir)
    initGitRepo(dir)
    makeCommit(dir, "f.txt", "init\n", "init")
    writeFile(dir / "g.txt", "new\n")
    runCmd(dir, "git", @["add", "g.txt"])

    let output = callTool(tools, "git_commit", %*{"message": "added g file", "working_dir": dir})
    check "added g file" in output or "g.txt" in output

    # Verify commit exists in log
    let log = callTool(tools, "git_log", %*{"count": 1, "working_dir": dir})
    check "added g file" in log

  test "git_commit empty message refused":
    let output = callTool(tools, "git_commit", %*{"message": "", "working_dir": "."})
    check "empty" in output.toLowerAscii()

  test "git_restore with staged=true unstages a file":
    let dir = makeTempDir("typos_git_restore_staged")
    defer: removeDir(dir)
    initGitRepo(dir)
    makeCommit(dir, "f.txt", "init\n", "init")
    writeFile(dir / "f.txt", "changed\n")
    runCmd(dir, "git", @["add", "f.txt"])

    let output = callTool(tools, "git_restore", %*{"paths": ["f.txt"], "staged": true, "working_dir": dir})
    check "Unstaged" in output

    # Verify it's no longer staged
    let diff = callTool(tools, "git_diff_staged", %*{"working_dir": dir})
    check diff.strip().len == 0

  test "git_restore discards working tree changes":
    let dir = makeTempDir("typos_git_restore_discard")
    defer: removeDir(dir)
    initGitRepo(dir)
    makeCommit(dir, "f.txt", "original\n", "init")
    writeFile(dir / "f.txt", "modified\n")

    let output = callTool(tools, "git_restore", %*{"paths": ["f.txt"], "working_dir": dir})
    check "Restored" in output
    check readFile(dir / "f.txt") == "original\n"
