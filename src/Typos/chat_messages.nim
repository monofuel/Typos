import
  std/options,
  openai_leap,
  ./common


proc toResponseInputs*(chatMessages: seq[ChatMessage]): seq[ResponseInput] =
  ## Convert chat messages to Responses API input payloads.
  result = @[]
  for message in chatMessages:
    let isUserMessage = message.sender == "User"
    let role = if isUserMessage: "user" else: "assistant"
    let contentType = if isUserMessage: "input_text" else: "output_text"
    result.add(
      ResponseInput(
        `type`: "message",
        role: option(role),
        content: option(@[
          ResponseInputContent(
            `type`: contentType,
            text: option(message.content)
          )
        ])
      )
    )
