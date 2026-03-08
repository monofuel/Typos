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


proc mockMoveFile(source, dest: string) =
  ## Move a mocked file (copy content, delete source).
  if mockFs.files.hasKey(source):
    mockFs.files[dest] = mockFs.files[source]
    mockFs.files.del(source)


proc installMockOps() =
  ## Install mocked tool ops for isolated write-tool testing.
  setToolOps(
    ToolOps(
      fileExists: mockFileExists,
      dirExists: mockDirExists,
      readFile: mockReadFile,
      writeFile: mockWriteFile,
      createDir: mockCreateDir,
      removeFile: mockRemoveFile,
      moveFile: mockMoveFile
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
      "create_directory", "delete_file", "create_issue",
      "move_file", "sed_edit", "insert_lines", "delete_lines", "replace_lines"
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

  test "move_file moves a file":
    mockFs.files["old.txt"] = "data"
    let output = callTool(
      tools,
      "move_file",
      %*{"source": "old.txt", "destination": "new.txt"}
    )
    check output.contains("Moved old.txt to new.txt")
    check not mockFs.files.hasKey("old.txt")
    check mockFs.files["new.txt"] == "data"

  test "move_file source not found":
    let output = callTool(
      tools,
      "move_file",
      %*{"source": "missing.txt", "destination": "new.txt"}
    )
    check output.contains("Source file does not exist")

  test "insert_lines at beginning":
    mockFs.files["f.txt"] = "line1\nline2\n"
    let output = callTool(
      tools,
      "insert_lines",
      %*{"file_path": "f.txt", "after_line": 0, "content": "header"}
    )
    check output.contains("Inserted 1 line(s)")
    check mockFs.files["f.txt"] == "header\nline1\nline2\n"

  test "insert_lines in middle":
    mockFs.files["f.txt"] = "a\nb\nc\n"
    let output = callTool(
      tools,
      "insert_lines",
      %*{"file_path": "f.txt", "after_line": 2, "content": "x\ny"}
    )
    check output.contains("Inserted 2 line(s)")
    check mockFs.files["f.txt"] == "a\nb\nx\ny\nc\n"

  test "insert_lines at end":
    mockFs.files["f.txt"] = "a\nb\n"
    let output = callTool(
      tools,
      "insert_lines",
      %*{"file_path": "f.txt", "after_line": 2, "content": "c"}
    )
    check output.contains("Inserted 1 line(s)")
    check mockFs.files["f.txt"] == "a\nb\nc\n"

  test "insert_lines out of range":
    mockFs.files["f.txt"] = "a\n"
    let output = callTool(
      tools,
      "insert_lines",
      %*{"file_path": "f.txt", "after_line": 5, "content": "x"}
    )
    check output.contains("out of range")

  test "delete_lines single line":
    mockFs.files["f.txt"] = "a\nb\nc\n"
    let output = callTool(
      tools,
      "delete_lines",
      %*{"file_path": "f.txt", "start_line": 2, "end_line": 2}
    )
    check output.contains("Deleted 1 line(s)")
    check mockFs.files["f.txt"] == "a\nc\n"

  test "delete_lines range":
    mockFs.files["f.txt"] = "a\nb\nc\nd\n"
    let output = callTool(
      tools,
      "delete_lines",
      %*{"file_path": "f.txt", "start_line": 2, "end_line": 3}
    )
    check output.contains("Deleted 2 line(s)")
    check mockFs.files["f.txt"] == "a\nd\n"

  test "delete_lines invalid range":
    mockFs.files["f.txt"] = "a\nb\n"
    let output = callTool(
      tools,
      "delete_lines",
      %*{"file_path": "f.txt", "start_line": 3, "end_line": 2}
    )
    check output.contains("Invalid line range")

  test "replace_lines single line":
    mockFs.files["f.txt"] = "a\nb\nc\n"
    let output = callTool(
      tools,
      "replace_lines",
      %*{"file_path": "f.txt", "start_line": 2, "end_line": 2, "content": "B"}
    )
    check output.contains("Replaced lines 2..2")
    check mockFs.files["f.txt"] == "a\nB\nc\n"

  test "replace_lines range with different line count":
    mockFs.files["f.txt"] = "a\nb\nc\nd\n"
    let output = callTool(
      tools,
      "replace_lines",
      %*{"file_path": "f.txt", "start_line": 2, "end_line": 3, "content": "X"}
    )
    check output.contains("Replaced lines 2..3")
    check mockFs.files["f.txt"] == "a\nX\nd\n"

  test "replace_lines invalid range":
    mockFs.files["f.txt"] = "a\nb\n"
    let output = callTool(
      tools,
      "replace_lines",
      %*{"file_path": "f.txt", "start_line": 3, "end_line": 2, "content": "x"}
    )
    check output.contains("Invalid line range")

  test "sed_edit validates required params":
    let output = callTool(
      tools,
      "sed_edit",
      %*{"file_path": "f.txt"}
    )
    check output.contains("Missing required parameter")
