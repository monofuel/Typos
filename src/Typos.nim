## AI Text Editor using silky.

import
  std/[times, options],
  opengl, windy, bumpy, vmath,
  silky,
  openai_leap,
  ./Typos/common,
  ./agents

from silky/widgets import frameStates


const
  AreaHeaderHeight = 32.0

# Chat data
var
  chatMessages: seq[ChatMessage]
  currentInput: string
  inputId: int = 0

# AI streaming state
var
  isAiResponding: bool = false
  currentAiStream: Option[OpenAIStream]
  shouldAutoScrollChat: bool = false

# Initialize with some sample messages
chatMessages.add(ChatMessage(sender: "AI", content: "Hello! I'm your AI assistant. How can I help you today?", timestamp: 0.0))
chatMessages.add(ChatMessage(sender: "User", content: "I'd like to work on some Nim code.", timestamp: 0.0))
chatMessages.add(ChatMessage(sender: "AI", content: "Great! I can help you with Nim development. What would you like to work on?", timestamp: 0.0))

proc snapToPixels(rect: Rect): Rect =
  rect(rect.x.int.float32, rect.y.int.float32, rect.w.int.float32, rect.h.int.float32)

# TODO we should probably use openai_leap message format internally?
# we will always be using the openai api format for all providers.

proc convertChatMessagesToOpenAi(chatMsgs: seq[ChatMessage]): seq[Message] =
  ## Convert our ChatMessage format to openai_leap Message format
  result = @[]
  for msg in chatMsgs:
    let role = if msg.sender == "User": "user" else: "assistant"
    let openaiMsg = Message(
      role: role,
      content: option(@[
        MessageContentPart(
          `type`: "text",
          text: option(msg.content)
        )
      ])
    )
    result.add(openaiMsg)

proc addPanel*(area: Area, name: string) =
  let panel = Panel(name: name)
  area.panels.add(panel)
  if area.panels.len == 1:
    panel.selected = true
    area.selectedPanelNum = 0

let builder = newAtlasBuilder(1024, 4)
builder.addDir("data/", "data/")
builder.addFont("data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont("data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("dist/atlas.png", "dist/atlas.json")

let window = newWindow(
  "Typos - AI Text Editor",
  ivec2(1200, 1200),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()


let sk = newSilky("dist/atlas.png", "dist/atlas.json")

proc drawArea(area: Area, r: Rect) =
  area.rect = r.snapToPixels()

  if area.panels.len > 0:
    # Ensure valid selection
    if area.selectedPanelNum > area.panels.len - 1:
      area.selectedPanelNum = area.panels.len - 1

    # Draw Header
    let headerRect = rect(r.x, r.y, r.w, AreaHeaderHeight)
    sk.draw9Patch("panel.header.9patch", 3, headerRect.xy, headerRect.wh)

    # Draw Tabs
    var x = r.x + 4
    sk.pushClipRect(rect(r.x, r.y, r.w - 2, AreaHeaderHeight))
    for i, panel in area.panels:
      let textSize = sk.getTextSize("Default", panel.name)
      let tabW = textSize.x + 16
      let tabRect = rect(x, r.y + 4, tabW, AreaHeaderHeight - 4)

      let isSelected = i == area.selectedPanelNum
      let isHovered = window.mousePos.vec2.overlaps(tabRect)

      # Handle Tab Clicks
      if isHovered and window.buttonPressed[MouseLeft]:
        area.selectedPanelNum = i
        for j, p in area.panels:
          p.selected = (j == i)

      if isSelected:
        sk.draw9Patch("panel.tab.selected.9patch", 3, tabRect.xy, tabRect.wh, WhiteColor)
      elif isHovered:
        sk.draw9Patch("panel.tab.hover.9patch", 3, tabRect.xy, tabRect.wh, WhiteColor)
      else:
        sk.draw9Patch("panel.tab.9patch", 3, tabRect.xy, tabRect.wh)

      discard sk.drawText("Default", panel.name, vec2(x + 8, r.y + 4 + 2), TextPrimaryColor)

      x += tabW + 2
    sk.popClipRect()

    # Draw Content
    let contentRect = rect(r.x, r.y + AreaHeaderHeight, r.w, r.h - AreaHeaderHeight)
    let activePanel = area.panels[area.selectedPanelNum]
    let contentPos = vec2(contentRect.x, contentRect.y)
    # Draw panel content directly using silky widgets
    # Start content a bit inset.
    let contentInset = vec2(8, 8)
    sk.at = contentPos + contentInset

    case activePanel.name:
    of "Text Viewer":
      discard sk.drawText("H1", "Text Viewer", sk.at, TextPrimaryColor)
      sk.at.y += 40
      discard sk.drawText("Default", "This is where the text editor content will be displayed.", sk.at, TextPrimaryColor)
      sk.at.y += 20
      discard sk.drawText("Default", "Features to implement:", sk.at, TextPrimaryColor)
      sk.at.y += 20
      discard sk.drawText("Default", "• Syntax highlighting", sk.at, TextPrimaryColor)
      sk.at.y += 20
      discard sk.drawText("Default", "• Line numbers", sk.at, TextPrimaryColor)
      sk.at.y += 20
      discard sk.drawText("Default", "• Multi-cursor editing", sk.at, TextPrimaryColor)
      sk.at.y += 20
      discard sk.drawText("Default", "• Auto-completion", sk.at, TextPrimaryColor)

    of "AI Chat":
      # Calculate input box height dynamically
      let inputBoxWidth = contentRect.w
      let inputBoxPadding = vec2(8, 8)
      let font = sk.atlas.fonts["Default"]
      let lineHeight = font.lineHeight
      let minInputHeight = lineHeight + inputBoxPadding.y * 2

      # Calculate height needed for wrapped text
      let textSize = sk.getTextSize("Default", currentInput)
      let inputBoxHeight = max(minInputHeight, textSize.y + inputBoxPadding.y * 2)

      # Chat history area (scrollable) - adjusted for dynamic input height
      let chatHistoryHeight = contentRect.h - inputBoxHeight - 10
      let historyRect = rect(contentRect.x, contentRect.y, contentRect.w, chatHistoryHeight)

      # TODO: silky frame widget should support autoScrollToBottom flag in FrameState
      # to avoid manual content size calculation and scroll position setting
      frame("chat_history", historyRect.xy, historyRect.wh):
        for message in chatMessages:
          # Draw sender label
          let senderColor = if message.sender == "User": UserMessageColor else: AIMessageColor
          let senderText = message.sender & ": "
          let senderTextSize = sk.drawText("Default", senderText, sk.at, senderColor)
          sk.at.x += senderTextSize.x

          # Draw message content - account for max width to allow wrapping
          let maxContentWidth = sk.size.x - sk.at.x - theme.padding.float32 - 10  # Account for scrollbar
          let contentTextSize = sk.drawText("Default", message.content, sk.at, TextPrimaryColor, maxWidth = maxContentWidth)

          # Advance to next line - use the maximum height of sender label and content
          let messageHeight = max(senderTextSize.y, contentTextSize.y) + 5  # Add small spacing
          sk.advance(vec2(0, messageHeight))  # This updates stretchAt
          sk.at.x = sk.pos.x + theme.padding.float32  # Reset x for next line

      # Auto-scroll to bottom after frame is done processing
      # TODO: silky frame widget should support autoScrollToBottom flag to avoid manual calculation
      # We need to calculate content size manually since sk.stretchAt is reset after frame is popped
      if shouldAutoScrollChat and "chat_history" in frameStates:
        let frameState = frameStates["chat_history"]
        # Calculate total content height by summing all message heights
        # This should match the actual drawing logic above
        var totalContentHeight = theme.padding.float32  # Start with top padding
        let framePadding = theme.padding.float32
        let messageSpacing = 5.0f  # Match the spacing used in drawing
        let maxContentWidth = historyRect.w - framePadding * 2 - 10  # Account for scrollbar width
        
        for message in chatMessages:
          let senderText = message.sender & ": "
          let senderTextSize = sk.getTextSize("Default", senderText)
          let contentTextSize = sk.getTextSize("Default", message.content)
          # Calculate wrapped height for content (accounting for maxWidth)
          # Use the font's lineHeight to calculate wrapped lines
          let font = sk.atlas.fonts["Default"]
          let lineHeight = font.lineHeight
          let wrappedHeight = if contentTextSize.x > maxContentWidth:
            # Approximate wrapped height: ceil(width / maxWidth) * lineHeight
            let lines = (contentTextSize.x / maxContentWidth).ceil.int
            lineHeight * lines.float32
          else:
            contentTextSize.y
          # Message height is max of sender label height and wrapped content height, plus spacing
          let messageHeight = max(senderTextSize.y, wrappedHeight) + messageSpacing
          totalContentHeight += messageHeight
        
        totalContentHeight += framePadding + 16  # Bottom padding + extra spacing (matches frame template)
        
        # Calculate scroll position to show bottom
        let scrollMax = max(totalContentHeight - historyRect.h, 0.0f)
        if scrollMax > 0:
          frameState.scrollPos.y = scrollMax
        
        shouldAutoScrollChat = false


      # Position input box at bottom, expanding upward
      let inputRect = rect(contentRect.x, contentRect.y + contentRect.h - inputBoxHeight, inputBoxWidth, inputBoxHeight)

      # Draw input box background directly - different color when AI is responding
      let bgColor = if isAiResponding: BorderColor else: WhiteColor
      sk.draw9Patch("frame.9patch", 6, inputRect.xy, inputRect.wh, bgColor)

      # Set up clip rect for input area
      sk.pushClipRect(rect(inputRect.x + 1, inputRect.y + 1, inputRect.w - 2, inputRect.h - 2))

      # Position text inside the input box
      sk.at = inputRect.xy + inputBoxPadding

      # Draw input text manually (simplified version without frame wrapper)
      if inputId notin silky.widgets.textInputStates:
        silky.widgets.textInputStates[inputId] = InputTextState(focused: false)
        silky.widgets.textInputStates[inputId].setText(currentInput)

      let textInputState = silky.widgets.textInputStates[inputId]

      # Handle focus
      if window.buttonPressed[MouseLeft]:
        if window.mousePos.vec2.overlaps(inputRect):
          textInputState.focused = true
        else:
          textInputState.focused = false

      # Process input if focused
      if textInputState.focused:
        # Process runes
        for r in sk.inputRunes:
          textInputState.typeCharacter(r)
        textInputState.handleInput(window)
        # Sync back
        currentInput = textInputState.getText()

      # Draw text - dimmed when AI is responding
      let textColor = if isAiResponding: TextSecondaryColor else: TextPrimaryColor
      let displayText = if isAiResponding: "AI is typing..." else: currentInput
      discard sk.drawText("Default", displayText, sk.at, textColor)

      # Draw cursor if focused
      if textInputState.focused and (epochTime() * 2).int mod 2 == 0:
        let textBeforeCursor = $textInputState.runes[0 ..< min(textInputState.cursor, textInputState.runes.len)]
        let textSize = sk.getTextSize("Default", textBeforeCursor)
        let cursorX = sk.at.x + textSize.x
        let cursorY = sk.at.y
        sk.drawRect(vec2(cursorX, cursorY), vec2(2, lineHeight), TextPrimaryColor)

      sk.popClipRect()


    else:
      discard sk.drawText("H1", activePanel.name, sk.at, TextPrimaryColor)
      sk.at.y += 40
      discard sk.drawText("Default", "This is the content of " & activePanel.name, sk.at, TextPrimaryColor)

# Initialize panel layout
var
  aiChatArea = Area()

aiChatArea.addPanel("AI Chat")

window.runeInputEnabled = true
window.onRune = proc(rune: Rune) =
  # Don't add newline characters to input - handle Enter key separately for submission
  if rune != Rune('\n') and rune != Rune('\r'):
    sk.inputRunes.add(rune)

window.onFrame = proc() =

  # Handle input submission
  if window.buttonPressed[KeyEnter] and not isAiResponding:
    if currentInput.len > 0:
      chatMessages.add(ChatMessage(sender: "User", content: currentInput, timestamp: epochTime()))
      shouldAutoScrollChat = true  # Auto-scroll when user sends message

      # Start AI streaming response - add empty message to chatMessages immediately
      isAiResponding = true
      chatMessages.add(ChatMessage(sender: "AI", content: "", timestamp: epochTime()))
      shouldAutoScrollChat = true  # Auto-scroll when AI starts responding

      # Convert chat messages to openai_leap format and start streaming
      let openaiMessages = convertChatMessagesToOpenAi(chatMessages)
      currentAiStream = some(agents.qwen3_coder.sendMessage(openaiMessages))

      # Clear silky's internal state directly
      if inputId in silky.widgets.textInputStates:
        silky.widgets.textInputStates[inputId].setText("")
      currentInput = ""
      # Clear any pending input runes to prevent them from being added back
      sk.inputRunes.setLen(0)

  # Process AI streaming response
  if isAiResponding and currentAiStream.isSome:
    let chunk = agents.qwen3_coder.getNextChunk(currentAiStream.get())
    if chunk.isSome:
      # Update the last message in chatMessages (which is the AI response being streamed)
      chatMessages[^1].content &= chunk.get()
      # Auto-scroll as new content streams in (only if we're already near the bottom)
      # TODO: Check if user has scrolled up manually before auto-scrolling during streaming
      shouldAutoScrollChat = true
    else:
      # Stream is complete
      isAiResponding = false
      currentAiStream = none(OpenAIStream)

  sk.beginUI(window, window.size)

  # Clear screen with background color
  sk.clearScreen(BackgroundColor)

  # Full-window AI Chat layout
  let windowRect = rect(0, 1, window.size.x.float32, window.size.y.float32 - 1)

  # AI Chat panel (full window)
  drawArea(aiChatArea, windowRect)


  sk.endUi()
  window.swapBuffers()

when defined(emscripten):
  window.run()
else:
  while not window.closeRequested:
    pollEvents()
