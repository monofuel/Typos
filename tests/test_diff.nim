import
  std/[os, osproc, streams, strutils, times, unittest],
  Typos/git_diff


proc makeTempDir(prefix: string): string =
  ## Create a temporary directory for test fixtures.
  result = getTempDir() / (prefix & "_" & $epochTime().int64)
  createDir(result)


proc runCmd(workingDir: string, command: string, args: seq[string]) =
  ## Run a command and assert it exits successfully.
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


suite "git diff helpers":
  test "parseDiffLines classifies each major line type":
    let diffText = """
diff --git a/a.txt b/a.txt
index 1111111..2222222 100644
--- a/a.txt
+++ b/a.txt
@@ -1 +1 @@
-old
+new
 unchanged
"""
    let lines = parseDiffLines(diffText)
    check lines.len > 7
    check lines[0].kind == DiffLineHeader
    check lines[1].kind == DiffLineMeta
    check lines[2].kind == DiffLineMeta
    check lines[3].kind == DiffLineMeta
    check lines[4].kind == DiffLineHunk
    check lines[5].kind == DiffLineRemoved
    check lines[6].kind == DiffLineAdded
    check lines[7].kind == DiffLineContext

  test "diffStatusText returns empty status when no diff":
    check diffStatusText("") == "No unstaged changes."
    check diffStatusText("  \n") == "No unstaged changes."

  test "diffStatusText summarizes files and line counts":
    let diffText = """
diff --git a/a.txt b/a.txt
@@ -1 +1,2 @@
-line1
+line2
+line3
"""
    let status = diffStatusText(diffText)
    check "Files: 1" in status
    check "+2" in status
    check "-1" in status

  test "readGitDiff reads unstaged diff from a real git repo":
    let repoDir = makeTempDir("typos_diff_repo")
    defer: removeDir(repoDir)

    runCmd(repoDir, "git", @["init"])
    runCmd(repoDir, "git", @["config", "user.email", "test@example.com"])
    runCmd(repoDir, "git", @["config", "user.name", "Test User"])

    let filePath = repoDir / "tracked.txt"
    writeFile(filePath, "before\n")
    runCmd(repoDir, "git", @["add", "tracked.txt"])
    runCmd(repoDir, "git", @["commit", "-m", "init"])

    writeFile(filePath, "after\n")

    let diffText = readGitDiff(repoDir)
    check "diff --git" in diffText
    check "-before" in diffText
    check "+after" in diffText
