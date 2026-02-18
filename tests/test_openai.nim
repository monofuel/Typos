import
  std/[options, os, strutils, unittest],
  openai_leap


const
  OpenAiModel = "gpt-5.1-codex-mini"
  OpenAiBaseUrl = "https://api.openai.com/v1"
  OpenAiApiKeyEnvVar = "OPENAI_API_KEY"
  PromptText = "Reply with exactly: codex-live-ok"


proc createLiveRequest(prompt: string): CreateResponseReq =
  ## Create a live Responses API request payload.
  let req = CreateResponseReq()
  req.model = OpenAiModel
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


suite "openai live responses":
  test "codex 5.1 mini responds":
    let apiKey = getEnv(OpenAiApiKeyEnvVar).strip()
    if apiKey.len == 0:
      raise newException(ValueError, "OPENAI_API_KEY must be set for live OpenAI tests.")

    let api = newOpenAiApi(
      baseUrl = OpenAiBaseUrl,
      apiKey = apiKey
    )
    defer:
      api.close()

    let req = createLiveRequest(PromptText)
    let resp = api.createResponse(req)
    let outputText = responseOutputText(resp)

    check resp.`object` == "response"
    check resp.model == OpenAiModel
    check resp.status == "completed"
    check outputText.len > 0
    check "codex-live-ok" in outputText.toLowerAscii()
