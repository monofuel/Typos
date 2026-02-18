import
  std/[osproc, streams, strformat, strutils]


type
  DiffLineKind* = enum
    DiffLineHeader
    DiffLineHunk
    DiffLineMeta
    DiffLineAdded
    DiffLineRemoved
    DiffLineContext
    DiffLineEmpty

  DiffLine* = object
    kind*: DiffLineKind
    text*: string


proc readGitDiff*(workingDir: string): string =
  ## Read the current git diff for a working directory.
  let process = startProcess(
    "git",
    workingDir = workingDir,
    args = @["diff"],
    options = {poUsePath, poStdErrToStdOut}
  )

  var output = ""
  for line in process.outputStream.lines:
    output.add(line & "\n")

  let exitCode = process.waitForExit()
  process.close()

  if exitCode == 0:
    return output.strip()
  return &"Error executing git diff (exit code {exitCode}): {output.strip()}"


proc classifyDiffLine(line: string): DiffLineKind =
  ## Classify a single git diff line for presentation styling.
  if line.len == 0:
    return DiffLineEmpty
  if line.startsWith("diff --git"):
    return DiffLineHeader
  if line.startsWith("@@"):
    return DiffLineHunk
  if line.startsWith("index ") or line.startsWith("--- ") or line.startsWith("+++ "):
    return DiffLineMeta
  if line.startsWith("+") and not line.startsWith("+++"):
    return DiffLineAdded
  if line.startsWith("-") and not line.startsWith("---"):
    return DiffLineRemoved
  return DiffLineContext


proc parseDiffLines*(diffText: string): seq[DiffLine] =
  ## Parse diff text into typed lines for rendering and testing.
  for line in diffText.splitLines():
    result.add(DiffLine(kind: classifyDiffLine(line), text: line))


proc diffStatusText*(diffText: string): string =
  ## Generate a concise status summary for the current diff.
  if diffText.strip().len == 0:
    return "No unstaged changes."

  let lines = parseDiffLines(diffText)
  var
    files = 0
    added = 0
    removed = 0

  for line in lines:
    case line.kind
    of DiffLineHeader:
      files.inc
    of DiffLineAdded:
      added.inc
    of DiffLineRemoved:
      removed.inc
    else:
      discard

  return &"Files: {files}  +{added}  -{removed}"
