import
  std/[json, sets, strutils, tables, unittest],
  openai_leap,
  Typos/tools


type
  MockFsState = object
    files: Table[string, string]
    dirs: HashSet[string]


var mockFs: MockFsState


proc callTool(tools: ResponseToolsTable, name: string, args: JsonNode): string =
  ## Call a registered tool and return its output.
  let (_, toolImpl) = tools[name]
  return toolImpl(args)


proc resetMockFs() =
  ## Reset in-memory filesystem state for deterministic tests.
  mockFs.files.clear()
  mockFs.dirs.clear()
  mockFs.dirs.incl(".")


proc mockFileExists(path: string): bool =
  ## Check whether a mocked file exists.
  return mockFs.files.hasKey(path)


proc mockDirExists(path: string): bool =
  ## Check whether a mocked directory exists.
  return mockFs.dirs.contains(path)


proc mockReadFile(path: string): string =
  ## Read mocked file contents.
  return mockFs.files[path]


proc mockWriteFile(path: string, content: string) =
  ## Write mocked file contents.
  mockFs.files[path] = content


proc mockCreateDir(path: string) =
  ## Create a mocked directory.
  mockFs.dirs.incl(path)


proc mockRemoveFile(path: string) =
  ## Delete a mocked file.
  if mockFs.files.hasKey(path):
    mockFs.files.del(path)


proc installMockOps() =
  ## Install mocked tool ops for isolated write-tool testing.
  setToolOps(
    ToolOps(
      fileExists: mockFileExists,
      dirExists: mockDirExists,
      readFile: mockReadFile,
      writeFile: mockWriteFile,
      createDir: mockCreateDir,
      removeFile: mockRemoveFile
    )
  )


suite "write tools":
  let tools = getTyposReadWriteTools()

  setup:
    resetMockFs()
    installMockOps()
    clearCollectedIssues()

  teardown:
    resetToolOps()

  test "registry contains all write tools":
    let expected = @[
      "write_file", "append_file", "replace_in_file",
      "create_directory", "delete_file", "create_issue"
    ]
    for name in expected:
      check tools.hasKey(name)

  test "write_file creates and overwrites file":
    let output = callTool(
      tools,
      "write_file",
      %*{"file_path": "doc.txt", "content": "hello"}
    )
    check output.contains("Wrote 5 bytes")
    check mockFs.files["doc.txt"] == "hello"

    let output2 = callTool(
      tools,
      "write_file",
      %*{"file_path": "doc.txt", "content": "world"}
    )
    check output2.contains("Wrote 5 bytes")
    check mockFs.files["doc.txt"] == "world"

  test "write_file supports overwrite=false":
    mockFs.files["a.txt"] = "old"
    let output = callTool(
      tools,
      "write_file",
      %*{"file_path": "a.txt", "content": "new", "overwrite": false}
    )
    check output.contains("Refusing to overwrite")
    check mockFs.files["a.txt"] == "old"

  test "append_file appends to existing content":
    mockFs.files["notes.txt"] = "alpha"
    let output = callTool(
      tools,
      "append_file",
      %*{"file_path": "notes.txt", "content": "-beta"}
    )
    check output.contains("Appended 5 bytes")
    check mockFs.files["notes.txt"] == "alpha-beta"

  test "replace_in_file replaces first occurrence":
    mockFs.files["main.nim"] = "x x x"
    let output = callTool(
      tools,
      "replace_in_file",
      %*{"file_path": "main.nim", "old_text": "x", "new_text": "y"}
    )
    check output.contains("Replaced 1 occurrence")
    check mockFs.files["main.nim"] == "y x x"

  test "replace_in_file replaces all occurrences":
    mockFs.files["main.nim"] = "x x x"
    let output = callTool(
      tools,
      "replace_in_file",
      %*{"file_path": "main.nim", "old_text": "x", "new_text": "z", "replace_all": true}
    )
    check output.contains("Replaced 3 occurrence")
    check mockFs.files["main.nim"] == "z z z"

  test "create_directory and delete_file mutate mocked filesystem":
    let dirOutput = callTool(
      tools,
      "create_directory",
      %*{"dir_path": "docs"}
    )
    check dirOutput.contains("Created directory")
    check mockFs.dirs.contains("docs")

    mockFs.files["trash.txt"] = "tmp"
    let fileOutput = callTool(
      tools,
      "delete_file",
      %*{"file_path": "trash.txt"}
    )
    check fileOutput.contains("Deleted file")
    check not mockFs.files.hasKey("trash.txt")

  test "create_issue still collects payloads in yolo mode":
    let output = callTool(
      tools,
      "create_issue",
      %*{"title": "Bug title", "body": "Bug body", "labels": @["bug"]}
    )
    let issues = getCollectedIssues()
    check output.contains("Issue definition collected")
    check issues.len == 1
    check issues[0]["title"].getStr == "Bug title"
