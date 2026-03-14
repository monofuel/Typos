import
  std/[json, options, tables, unittest],
  openai_leap,
  mcport,
  Typos/mcp_tools


suite "mcp tools":
  test "convert McpTool to ToolFunction":
    let mcpTool = McpTool(
      name: "submit_pr",
      description: "Submit a pull request for review",
      inputSchema: %*{
        "type": "object",
        "properties": {
          "title": {"type": "string"},
          "body": {"type": "string"}
        },
        "required": ["title"]
      }
    )

    # Create a mock MCP client with the tool in availableTools
    let client = newHttpMcpClient("test", "1.0.0", "http://localhost:9999", logEnabled = false)
    client.client.availableTools["submit_pr"] = mcpTool

    var tools = newResponseToolsTable()
    registerMcpTools(tools, client)

    check tools.hasKey("submit_pr")
    let (toolFunc, _) = tools["submit_pr"]
    check toolFunc.name == "submit_pr"
    check toolFunc.description.get == "Submit a pull request for review"
    check toolFunc.parameters.isSome
    check toolFunc.parameters.get["properties"].hasKey("title")

  test "MCP tools merge without colliding with native tools":
    var tools = newResponseToolsTable()

    # Register a native tool
    tools.register("read_file", ToolFunction(
      name: "read_file",
      description: option("Read file contents"),
      parameters: option(%*{"type": "object", "properties": {}, "required": []})
    ), proc(args: JsonNode): string = "native")

    # Register MCP tool with different name
    let mcpTool = McpTool(
      name: "submit_review",
      description: "Submit a code review",
      inputSchema: %*{"type": "object", "properties": {}, "required": []}
    )
    let client = newHttpMcpClient("test", "1.0.0", "http://localhost:9999", logEnabled = false)
    client.client.availableTools["submit_review"] = mcpTool

    registerMcpTools(tools, client)

    check tools.hasKey("read_file")
    check tools.hasKey("submit_review")
    check tools.len == 2

  test "McpTool with nil inputSchema gets default parameters":
    let mcpTool = McpTool(
      name: "ping",
      description: "Ping the server",
      inputSchema: newJNull()
    )
    let client = newHttpMcpClient("test", "1.0.0", "http://localhost:9999", logEnabled = false)
    client.client.availableTools["ping"] = mcpTool

    var tools = newResponseToolsTable()
    registerMcpTools(tools, client)

    check tools.hasKey("ping")
    let (toolFunc, _) = tools["ping"]
    check toolFunc.parameters.isSome
    check toolFunc.parameters.get["type"].getStr == "object"
