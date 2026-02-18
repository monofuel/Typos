import
  std/[json, options, os],
  openai_leap,
  ../Typos/[chat_messages, common, provider_config, tools]


type
  TyposResponseStream* = ref object
    stream*: OpenAIResponseStream
    hasEmittedDelta*: bool
    bufferedResponse*: string
    emittedBuffered*: bool


var
  apiClient: OpenAiApi
  activeConfig: ProviderConfig


proc extractResponseText(resp: OpenAiResponse): string =
  ## Extract final assistant text from a structured OpenAI response object.
  if resp.output_text.isSome and resp.output_text.get.len > 0:
    return resp.output_text.get

  for output in resp.output:
    if output.`type` == "message" and output.content.isSome:
      for contentPart in output.content.get:
        if contentPart.`type` == "output_text" and contentPart.text.isSome:
          return contentPart.text.get

  return ""


proc extractResponseText(responseNode: JsonNode): string =
  ## Extract final assistant text from a Responses API completion payload.
  if responseNode.hasKey("output_text"):
    let outputText = responseNode["output_text"]
    if outputText.kind == JString:
      result = outputText.str
      return

  if responseNode.hasKey("output"):
    let output = responseNode["output"]
    if output.kind == JArray:
      for item in output:
        if item.hasKey("type") and item["type"].kind == JString and item["type"].str == "message":
          if item.hasKey("content") and item["content"].kind == JArray:
            for contentPart in item["content"]:
              if contentPart.hasKey("type") and contentPart["type"].kind == JString and contentPart["type"].str == "output_text":
                if contentPart.hasKey("text") and contentPart["text"].kind == JString:
                  result = contentPart["text"].str
                  return


proc initClient*(config: ProviderConfig) =
  ## Initialize the OpenAI-compatible client for the configured provider.
  let apiKey = if config.apiEnvVar.len > 0: getEnv(config.apiEnvVar) else: ""
  let resolvedApiKey = if apiKey.len > 0: apiKey else: "not-needed-for-lm-studio"

  if config.provider != ProviderLmStudio and apiKey.len == 0:
    raise newException(
      ValueError,
      "Missing required API key env var: " & config.apiEnvVar
    )

  if not apiClient.isNil:
    apiClient.close()

  apiClient = newOpenAiApi(
    baseUrl = config.baseUrl,
    apiKey = resolvedApiKey
  )
  activeConfig = config


proc ensureClientInitialized() =
  ## Ensure a client has been initialized before sending requests.
  if apiClient.isNil:
    initClient(defaultProviderConfig(ProviderOpenAi))


proc sendMessage*(chatMessages: seq[ChatMessage]): TyposResponseStream =
  ## Start a streaming Responses API request for the current chat history.
  ensureClientInitialized()
  let req = CreateResponseReq()
  req.model = activeConfig.model
  req.input = option(toResponseInputs(chatMessages))

  result = TyposResponseStream(
    stream: apiClient.streamResponse(req),
    hasEmittedDelta: false,
    bufferedResponse: "",
    emittedBuffered: false
  )


proc sendMessageWithReadTools*(chatMessages: seq[ChatMessage]): TyposResponseStream =
  ## Run a Responses request with read-only tools and return buffered text output.
  ensureClientInitialized()

  var req = CreateResponseReq()
  req.model = activeConfig.model
  req.input = option(toResponseInputs(chatMessages))
  let tools = getTyposReadTools()
  let resp = apiClient.createResponseWithTools(req, tools)

  let bufferedResponse = extractResponseText(resp)

  result = TyposResponseStream(
    stream: nil,
    hasEmittedDelta: false,
    bufferedResponse: bufferedResponse,
    emittedBuffered: false
  )


proc getNextChunk*(stream: TyposResponseStream): Option[string] =
  ## Get the next text chunk from the Responses API stream.
  if stream.stream.isNil:
    if not stream.emittedBuffered and stream.bufferedResponse.len > 0:
      stream.emittedBuffered = true
      return option(stream.bufferedResponse)
    return none(string)

  while true:
    let chunkOpt = stream.stream.nextResponseChunk()
    if chunkOpt.isNone:
      return none(string)

    let chunk = chunkOpt.get()
    if not chunk.hasKey("type") or chunk["type"].kind != JString:
      continue

    let eventType = chunk["type"].str
    if eventType == "response.output_text.delta":
      if chunk.hasKey("delta") and chunk["delta"].kind == JString:
        let delta = chunk["delta"].str
        if delta.len > 0:
          stream.hasEmittedDelta = true
          return option(delta)
    elif eventType == "response.completed":
      if chunk.hasKey("response") and chunk["response"].kind == JObject and not stream.hasEmittedDelta:
        let finalText = extractResponseText(chunk["response"])
        if finalText.len > 0:
          return option(finalText)
      return none(string)
