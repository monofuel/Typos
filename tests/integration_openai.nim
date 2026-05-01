import
  std/[options, os, strutils, unittest],
  openai_leap,
  Typos/aws_credentials


const
  BedrockModel = "anthropic.claude-sonnet-4-6"
  BedrockBaseUrl = "https://bedrock-mantle.us-east-1.api.aws/v1"
  BedrockApiEnvVar = "AWS_BEDROCK_TOKEN"
  PromptText = "Reply with exactly: bedrock-live-ok"


proc createLiveRequest(prompt: string): CreateResponseReq =
  ## Create a live Responses API request payload.
  let req = CreateResponseReq()
  req.model = BedrockModel
  req.input = option(@[
    ResponseInput(
      `type`: "message",
      role: option("user"),
      content: option(@[
        ResponseInputContent(
          `type`: "input_text",
          text: option(prompt)
        )
      ])
    )
  ])
  return req


proc responseOutputText(resp: OpenAiResponse): string =
  ## Extract assistant text from a Responses API response.
  if resp.output_text.isSome and resp.output_text.get.len > 0:
    return resp.output_text.get

  for output in resp.output:
    if output.`type` == "message" and output.content.isSome:
      for contentPart in output.content.get:
        if contentPart.`type` == "output_text" and contentPart.text.isSome:
          return contentPart.text.get

  return ""


suite "bedrock live responses":
  test "claude sonnet responds":
    var apiKey = getEnv(BedrockApiEnvVar).strip()
    if apiKey.len == 0 and getEnv("AWS_PROFILE").len > 0:
      apiKey = getBedrockToken()
    if apiKey.len == 0:
      echo "Skipping: AWS_BEDROCK_TOKEN not set and no AWS_PROFILE available."
      quit(0)

    let api = newOpenAiApi(
      baseUrl = BedrockBaseUrl,
      apiKey = apiKey
    )
    defer:
      api.close()

    let req = createLiveRequest(PromptText)
    let resp = api.createResponse(req)
    let outputText = responseOutputText(resp)

    check resp.`object` == "response"
    check resp.model.len > 0
    check resp.status == "completed"
    check outputText.len > 0
    check "bedrock-live-ok" in outputText.toLowerAscii()
