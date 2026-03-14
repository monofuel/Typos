import
  std/[json, options, strutils, tables],
  openai_leap,
  mcport


proc connectMcpClient*(url: string): HttpMcpClient =
  ## Create, connect, and initialize an MCPort HTTP MCP client.
  result = newHttpMcpClient("typoi", "1.0.0", url, logEnabled = false)
  result.connectAndInitialize()


proc mcpToolToToolFunction(tool: McpTool): ToolFunction =
  ## Convert an MCPort McpTool to an openai_leap ToolFunction.
  result = ToolFunction()
  result.name = tool.name
  result.description = option(tool.description)
  if tool.inputSchema != nil and tool.inputSchema.kind != JNull:
    result.parameters = option(tool.inputSchema)
  else:
    result.parameters = option(%*{"type": "object", "properties": {}, "required": []})


proc registerMcpTools*(tools: var ResponseToolsTable, client: HttpMcpClient) =
  ## Fetch tools from MCP server and register them into the ResponseToolsTable.
  ## Each MCP tool is wrapped as a proxy that calls client.callTool().
  for name, mcpTool in client.client.availableTools.pairs:
    let toolFunc = mcpToolToToolFunction(mcpTool)
    let toolName = name
    let mcpClient = client
    tools.register(toolName, toolFunc, proc(args: JsonNode): string =
      let callResult = mcpClient.callTool(toolName, args)
      # Extract text content from MCP tool result
      if callResult.hasKey("content") and callResult["content"].kind == JArray:
        var parts: seq[string] = @[]
        for item in callResult["content"]:
          if item.hasKey("text") and item["text"].kind == JString:
            parts.add(item["text"].getStr)
        return parts.join("\n")
      elif callResult.kind == JString:
        return callResult.getStr
      else:
        return $callResult
    )
