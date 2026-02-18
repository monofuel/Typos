## Typos τύπος
## AI Text Editor using silky.
##
# TODO very barebones, needs more work

import
  std/[os, times, options],
  opengl, windy, bumpy, vmath,
  silky,
  ./Typos/[common, git_diff],
  ./agents

# TODO this is stupid we never do imports like this in nim
from silky/widgets import frameStates


const
  AreaHeaderHeight = 32.0
  DiffPaneRatio = 0.58f
  PaneGap = 8.0f
  ToolTogglesSpacing = 6.0f

# Chat data
var
  chatMessages: seq[ChatMessage]
  currentInput: string
  inputId: string = "chat_input"

# AI streaming state
var
  isAiResponding: bool = false
  currentAiStream: Option[TyposResponseStream]
  shouldAutoScrollChat: bool = false
  pendingAiStart: bool = false
  pendingAiMessages: seq[ChatMessage]
  readToolsEnabled: bool = false
  yoloModeEnabled: bool = false

# Git diff panel data
var
  currentGitDiff: string
  currentDiffLines: seq[DiffLine]
  currentDiffStatus: string = "Loading git diff..."
  diffNeedsRefresh: bool = true

# Initialize with some sample messages
chatMessages.add(ChatMessage(sender: "AI", content: "Hello! I'm your AI assistant. How can I help you today?", timestamp: 0.0))
chatMessages.add(ChatMessage(sender: "User", content: "I'd like to work on some Nim code.", timestamp: 0.0))
chatMessages.add(ChatMessage(sender: "AI", content: "Great! I can help you with Nim development. What would you like to work on?", timestamp: 0.0))

proc snapToPixels(rect: Rect): Rect =
  rect(rect.x.int.float32, rect.y.int.float32, rect.w.int.float32, rect.h.int.float32)

proc refreshGitDiff() =
  ## Refresh current git diff text, parsed lines, and summary status.
  currentGitDiff = readGitDiff(getCurrentDir())
  currentDiffLines = parseDiffLines(currentGitDiff)
  currentDiffStatus = diffStatusText(currentGitDiff)

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


proc drawPanelShell(title: string, panelRect: Rect): Rect =
  ## Draw a panel shell and return its inner content rectangle.
  let r = panelRect.snapToPixels()
  sk.draw9Patch("panel.body.9patch", 3, r.xy, r.wh)

  let headerRect = rect(r.x, r.y, r.w, AreaHeaderHeight)
  sk.draw9Patch("panel.header.9patch", 3, headerRect.xy, headerRect.wh)
  discard sk.drawText("Default", title, vec2(r.x + 10, r.y + 8), TextPrimaryColor)

  return rect(r.x + 4, r.y + AreaHeaderHeight + 4, r.w - 8, r.h - AreaHeaderHeight - 8)


proc diffLineColor(kind: DiffLineKind): auto =
  ## Map diff line kind to a display color.
  case kind
  of DiffLineHeader:
    UserMessageColor
  of DiffLineHunk:
    WhiteColor
  of DiffLineMeta:
    TextSecondaryColor
  of DiffLineAdded:
    AIMessageColor
  of DiffLineRemoved:
    UserMessageColor
  of DiffLineContext:
    TextPrimaryColor
  of DiffLineEmpty:
    TextPrimaryColor


proc drawGitDiffPanel(panelRect: Rect) =
  ## Draw the Git Diff panel content.
  let contentRect = drawPanelShell("Git Diff", panelRect)
  let font = sk.atlas.fonts["Default"]
  let lineHeight = font.lineHeight + 3

  discard sk.drawText("Default", currentDiffStatus, vec2(contentRect.x + 2, contentRect.y + 2), TextSecondaryColor)
  let diffRect = rect(
    contentRect.x,
    contentRect.y + lineHeight + 4,
    contentRect.w,
    contentRect.h - lineHeight - 4
  )

  frame("git_diff_history", diffRect.xy, diffRect.wh):
    if currentDiffLines.len == 0:
      discard sk.drawText("Default", "No unstaged changes.", sk.at, TextSecondaryColor)
      sk.advance(vec2(0, lineHeight))
    else:
      for line in currentDiffLines:
        discard sk.drawText("Default", line.text, sk.at, diffLineColor(line.kind))
        sk.advance(vec2(0, lineHeight))

proc drawChatPanel(panelRect: Rect) =
  ## Draw the AI chat panel content.
  let contentRect = drawPanelShell("AI Chat", panelRect)
  let inputBoxWidth = contentRect.w
  let inputBoxPadding = vec2(8, 8)
  let font = sk.atlas.fonts["Default"]
  let lineHeight = font.lineHeight
  let minInputHeight = lineHeight + inputBoxPadding.y * 2
  let framePadding = sk.theme.padding.float32
  let textSize = sk.getTextSize("Default", currentInput)
  let inputBoxHeight = max(minInputHeight, textSize.y + inputBoxPadding.y * 2)
  let togglesHeight = lineHeight * 2 + ToolTogglesSpacing * 3
  let chatHistoryHeight = contentRect.h - inputBoxHeight - togglesHeight - 10
  let historyRect = rect(contentRect.x, contentRect.y, contentRect.w, chatHistoryHeight)
  let togglesRect = rect(
    contentRect.x,
    historyRect.y + historyRect.h + ToolTogglesSpacing,
    contentRect.w,
    togglesHeight - ToolTogglesSpacing
  )

  var renderedContentHeight = framePadding
  frame("chat_history", historyRect.xy, historyRect.wh):
    for message in chatMessages:
      let senderColor = if message.sender == "User": UserMessageColor else: AIMessageColor
      let senderText = message.sender & ": "
      let senderTextSize = sk.drawText("Default", senderText, sk.at, senderColor)
      sk.at.x += senderTextSize.x

      let maxContentWidth = max(historyRect.w - senderTextSize.x - framePadding - 10, 1.0f)
      let contentTextSize = sk.drawText(
        "Default",
        message.content,
        sk.at,
        TextPrimaryColor,
        maxWidth = maxContentWidth,
        wordWrap = true
      )

      let messageHeight = max(senderTextSize.y, contentTextSize.y) + 5
      renderedContentHeight += messageHeight
      sk.advance(vec2(0, messageHeight))
      sk.at.x = sk.pos.x + framePadding

  if shouldAutoScrollChat and "chat_history" in frameStates:
    let frameState = frameStates["chat_history"]
    let totalContentHeight = renderedContentHeight + framePadding + 16
    let scrollMax = max(totalContentHeight - historyRect.h, 0.0f)
    if scrollMax > 0:
      frameState.scrollPos.y = scrollMax
    shouldAutoScrollChat = false

  sk.pushClipRect(togglesRect)
  sk.at = vec2(togglesRect.x + framePadding, togglesRect.y + ToolTogglesSpacing)
  checkBox("Read-only tools", readToolsEnabled)
  checkBox("YOLO mode (read + write tools)", yoloModeEnabled)
  if yoloModeEnabled:
    readToolsEnabled = true
  if not readToolsEnabled:
    yoloModeEnabled = false
  sk.popClipRect()

  let inputRect = rect(contentRect.x, contentRect.y + contentRect.h - inputBoxHeight, inputBoxWidth, inputBoxHeight)
  let bgColor = if isAiResponding: BorderColor else: WhiteColor
  sk.draw9Patch("frame.9patch", 6, inputRect.xy, inputRect.wh, bgColor)

  if isAiResponding:
    sk.pushClipRect(rect(inputRect.x + 1, inputRect.y + 1, inputRect.w - 2, inputRect.h - 2))
    sk.at = inputRect.xy + inputBoxPadding
    discard sk.drawText("Default", "AI is typing...", sk.at, TextSecondaryColor)
    sk.popClipRect()
  else:
    sk.at = inputRect.xy
    sk.textBox(
      window,
      inputId,
      currentInput,
      inputRect.w,
      inputRect.h,
      wrapWords = true
    )

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
      pendingAiMessages = chatMessages
      diffNeedsRefresh = true

      # Start AI streaming response - add empty message to chatMessages immediately
      isAiResponding = true
      chatMessages.add(ChatMessage(sender: "AI", content: "", timestamp: epochTime()))
      shouldAutoScrollChat = true  # Auto-scroll when AI starts responding
      pendingAiStart = true

      # Clear silky's internal state directly
      if inputId in silky.textboxes.textBoxStates:
        silky.textboxes.textBoxStates[inputId].setText("")
      currentInput = ""
      # Clear any pending input runes to prevent them from being added back
      sk.inputRunes.setLen(0)

  # Process AI streaming response
  if isAiResponding and currentAiStream.isSome:
    let chunk = agents.responses_chat.getNextChunk(currentAiStream.get())
    if chunk.isSome:
      # Update the last message in chatMessages (which is the AI response being streamed)
      chatMessages[^1].content &= chunk.get()
      # Auto-scroll as new content streams in (only if we're already near the bottom)
      # TODO: Check if user has scrolled up manually before auto-scrolling during streaming
      shouldAutoScrollChat = true
    else:
      # Stream is complete
      isAiResponding = false
      currentAiStream = none(TyposResponseStream)
      diffNeedsRefresh = true

  sk.beginUI(window, window.size)

  # Clear screen with background color
  sk.clearScreen(BackgroundColor)

  if diffNeedsRefresh:
    refreshGitDiff()
    diffNeedsRefresh = false

  # Split layout: Git Diff on left, AI chat on right.
  let windowRect = rect(0, 1, window.size.x.float32, window.size.y.float32 - 1)
  let leftPaneWidth = (windowRect.w - PaneGap) * DiffPaneRatio
  let leftRect = rect(windowRect.x, windowRect.y, leftPaneWidth, windowRect.h)
  let rightRect = rect(
    windowRect.x + leftPaneWidth + PaneGap,
    windowRect.y,
    windowRect.w - leftPaneWidth - PaneGap,
    windowRect.h
  )
  drawGitDiffPanel(leftRect)
  drawChatPanel(rightRect)


  sk.endUi()
  window.swapBuffers()

  if pendingAiStart:
    # Start the stream after presenting one frame so the cleared input is visible immediately.
    currentAiStream = if yoloModeEnabled:
      some(agents.responses_chat.sendMessageWithReadWriteTools(pendingAiMessages))
    elif readToolsEnabled:
      some(agents.responses_chat.sendMessageWithReadTools(pendingAiMessages))
    else:
      some(agents.responses_chat.sendMessage(pendingAiMessages))
    pendingAiStart = false

when defined(emscripten):
  window.run()
else:
  while not window.closeRequested:
    pollEvents()
