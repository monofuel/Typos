import
  std/options,
  openai_leap,
  ./common


proc toResponseInputs*(chatMessages: seq[ChatMessage]): seq[ResponseInput] =
  ## Convert chat messages to Responses API input payloads.
  result = @[]
  for message in chatMessages:
    let role = if message.sender == "User": "user" else: "assistant"
    result.add(
      ResponseInput(
        `type`: "message",
        role: option(role),
        content: option(@[
          ResponseInputContent(
            `type`: "input_text",
            text: option(message.content)
          )
        ])
      )
    )
