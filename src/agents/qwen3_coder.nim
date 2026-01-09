# local lm studio
# http://10.11.2.14:1234
# can use with openai_leap library
# can use `unsloth/qwen3-coder-30b-a3b-instruct` with tool usage.

# keep constants in src/Typos/common.nim

import openai_leap, options
import ../Typos/common

var apiClient: OpenAiApi

proc initClient*() =
  ## Initialize the OpenAI API client for LM Studio
  if apiClient.isNil:
    apiClient = newOpenAiApi(
      baseUrl = LmStudioBaseUrl,
      apiKey = "not-needed-for-lm-studio"
    )

proc sendMessage*(messages: seq[Message]): OpenAIStream =
  ## Send a message to the AI and return a streaming response
  if apiClient.isNil:
    initClient()

  let req = CreateChatCompletionReq()
  req.model = Qwen3CoderModel
  req.messages = messages
  req.stream = option(true)

  result = apiClient.streamChatCompletion(req)

proc getNextChunk*(stream: OpenAIStream): Option[string] =
  ## Get the next chunk from the streaming response
  ## Returns the delta content if available, or none if stream is complete
  let chunk = stream.next()
  if chunk.isSome:
    let chatChunk = chunk.get()
    if chatChunk.choices.len > 0 and chatChunk.choices[0].delta.isSome:
      let delta = chatChunk.choices[0].delta.get()
      if delta.content != "":
        return option(delta.content)
  return none(string)


when isMainModule:
  ## Basic test of the qwen3_coder streaming chat functionality

  echo "Testing qwen3_coder agent..."

  # Initialize the client
  initClient()
  echo "✓ Client initialized"

  # Create a simple test message
  let testMessage = Message(
    role: "user",
    content: option(@[
      MessageContentPart(
        `type`: "text",
        text: option("Hello! Please respond with a short greeting.")
      )
    ])
  )

  let messages = @[testMessage]

  # Start streaming response
  echo "Starting streaming chat completion..."
  let stream = sendMessage(messages)

  # Process streaming chunks
  echo "AI Response: "
  var responseText = ""
  var chunkCount = 0

  while true:
    let chunk = getNextChunk(stream)
    if chunk.isSome:
      let content = chunk.get()
      responseText &= content
      stdout.write(content)  # Print character by character
      stdout.flushFile()
      chunkCount += 1
    else:
      # Stream is complete
      break

  echo ""
  echo "✓ Stream complete. Received " & $chunkCount & " chunks."
  echo "✓ Total response length: " & $responseText.len & " characters."
  echo "✓ Test completed successfully!"
