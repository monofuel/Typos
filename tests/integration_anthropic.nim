import
  std/[json, options, os, strutils, times, unittest],
  openai_leap,
  Typos/tools


const
  BedrockModel = "claude-sonnet-4-6"
  BedrockBaseUrl = "https://bedrock-mantle.us-east-1.api.aws/v1"
  BedrockApiEnvVar = "AWS_BEDROCK_TOKEN"
  PromptText = "Reply with exactly: claude-live-ok"


proc requireApiKey(): string =
  result = getEnv(BedrockApiEnvVar).strip()
  if result.len == 0:
    raise newException(ValueError, "AWS_BEDROCK_TOKEN must be set for live Bedrock tests.")


proc makeTempDir(prefix: string): string =
  result = getTempDir() / (prefix & "_" & $epochTime().int64)
  createDir(result)


suite "bedrock live messages":
  let apiKey = requireApiKey()
  let api = newOpenAiApi(
    baseUrl = BedrockBaseUrl,
    apiKey = apiKey
  )

  test "claude sonnet responds":
    let req = CreateMessageReq()
    req.model = BedrockModel
    req.max_tokens = 256
    req.messages = @[
      AnthropicMessage(
        role: "user",
        content: % PromptText
      )
    ]
    let resp = api.createMessage(req)
    let text = messageText(resp)

    check resp.model.len > 0
    check text.len > 0
    check "claude-live-ok" in text.toLowerAscii()

  test "claude sonnet streams":
    let req = CreateMessageReq()
    req.model = BedrockModel
    req.max_tokens = 256
    req.messages = @[
      AnthropicMessage(
        role: "user",
        content: % "Reply with exactly: stream-ok"
      )
    ]
    let stream = api.streamMessage(req)
    var fullText = ""
    var chunkCount = 0

    while true:
      let eventOpt = stream.nextMessageEvent()
      if eventOpt.isNone:
        break
      let event = eventOpt.get()
      if event.hasKey("type") and event["type"].getStr == "content_block_delta":
        if event.hasKey("delta") and event["delta"].hasKey("text"):
          fullText.add(event["delta"]["text"].getStr)
          chunkCount.inc

    check fullText.len > 0
    check "stream-ok" in fullText.toLowerAscii()
    check chunkCount > 0

  test "claude sonnet uses read tools":
    let dirPath = makeTempDir("typos_int_anthropic_read")
    defer: removeDir(dirPath)
    let filePath = dirPath / "secret.txt"
    writeFile(filePath, "answer=anthropic-tool-42\n")

    let tools = getTyposReadTools()
    var req = CreateMessageReq()
    req.model = BedrockModel
    req.max_tokens = 1024
    req.messages = @[
      AnthropicMessage(
        role: "user",
        content: % ("Use the read_file tool to read the file at '" & filePath &
          "' and tell me the value of 'answer'.")
      )
    ]
    let resp = api.createMessageWithTools(req, tools)
    let text = messageText(resp)

    check "anthropic-tool-42" in text

  test "toMessageReq converts responses request":
    let responsesReq = CreateResponseReq()
    responsesReq.model = BedrockModel
    responsesReq.input = option(@[
      ResponseInput(
        `type`: "message",
        role: option("user"),
        content: option(@[
          ResponseInputContent(
            `type`: "input_text",
            text: option("hello from converter")
          )
        ])
      )
    ])

    let msgReq = toMessageReq(responsesReq)
    check msgReq.model == BedrockModel
    check msgReq.messages.len == 1
    check msgReq.messages[0].role == "user"

    let resp = api.createMessage(msgReq)
    let text = messageText(resp)
    check text.len > 0

  api.close()
