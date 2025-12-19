## AI Text Editor using silky.

import
  std/[strformat],
  opengl, windy, bumpy, vmath, chroma,
  silky

# Panel system types
type
  Panel* = ref object
    name*: string
    selected*: bool

  Area* = ref object
    panels*: seq[Panel]
    selectedPanelNum*: int
    rect*: Rect

const
  AreaHeaderHeight = 32.0
  AreaMargin = 6.0

proc snapToPixels(rect: Rect): Rect =
  rect(rect.x.int.float32, rect.y.int.float32, rect.w.int.float32, rect.h.int.float32)

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
  ivec2(800, 600),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

const
  BackgroundColor = parseHtmlColor("#000000").rgbx

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
        sk.draw9Patch("panel.tab.selected.9patch", 3, tabRect.xy, tabRect.wh, rgbx(255, 255, 255, 255))
      elif isHovered:
        sk.draw9Patch("panel.tab.hover.9patch", 3, tabRect.xy, tabRect.wh, rgbx(255, 255, 255, 255))
      else:
        sk.draw9Patch("panel.tab.9patch", 3, tabRect.xy, tabRect.wh)

      discard sk.drawText("Default", panel.name, vec2(x + 8, r.y + 4 + 2), rgbx(255, 255, 255, 255))

      x += tabW + 2
    sk.popClipRect()

    # Draw Content
    let contentRect = rect(r.x, r.y + AreaHeaderHeight, r.w, r.h - AreaHeaderHeight)
    let activePanel = area.panels[area.selectedPanelNum]
    let contentPos = vec2(contentRect.x, contentRect.y)
    let contentSize = vec2(contentRect.w, contentRect.h)
    # Draw panel content directly using silky widgets
    # Start content a bit inset.
    let contentInset = vec2(8, 8)
    sk.at = contentPos + contentInset

    case activePanel.name:
    of "Text Viewer":
      discard sk.drawText("H1", "Text Viewer", sk.at, rgbx(255, 255, 255, 255))
      sk.at.y += 40
      discard sk.drawText("Default", "This is where the text editor content will be displayed.", sk.at, rgbx(255, 255, 255, 255))
      sk.at.y += 20
      discard sk.drawText("Default", "Features to implement:", sk.at, rgbx(255, 255, 255, 255))
      sk.at.y += 20
      discard sk.drawText("Default", "• Syntax highlighting", sk.at, rgbx(255, 255, 255, 255))
      sk.at.y += 20
      discard sk.drawText("Default", "• Line numbers", sk.at, rgbx(255, 255, 255, 255))
      sk.at.y += 20
      discard sk.drawText("Default", "• Multi-cursor editing", sk.at, rgbx(255, 255, 255, 255))
      sk.at.y += 20
      discard sk.drawText("Default", "• Auto-completion", sk.at, rgbx(255, 255, 255, 255))

    of "AI Chat":
      discard sk.drawText("H1", "AI Chat", sk.at, rgbx(255, 255, 255, 255))
      sk.at.y += 40
      discard sk.drawText("Default", "AI assistant chat interface will go here.", sk.at, rgbx(255, 255, 255, 255))
      sk.at.y += 20
      discard sk.drawText("Default", "Planned features:", sk.at, rgbx(255, 255, 255, 255))
      sk.at.y += 20
      discard sk.drawText("Default", "• Natural language queries", sk.at, rgbx(255, 255, 255, 255))
      sk.at.y += 20
      discard sk.drawText("Default", "• Code suggestions", sk.at, rgbx(255, 255, 255, 255))
      sk.at.y += 20
      discard sk.drawText("Default", "• Documentation help", sk.at, rgbx(255, 255, 255, 255))
      sk.at.y += 20
      discard sk.drawText("Default", "• Error explanations", sk.at, rgbx(255, 255, 255, 255))

    of "Console":
      discard sk.drawText("H1", "Console", sk.at, rgbx(255, 255, 255, 255))
      sk.at.y += 40
      discard sk.drawText("Default", "Command output and system messages will appear here.", sk.at, rgbx(255, 255, 255, 255))
      sk.at.y += 20
      discard sk.drawText("Default", "Console output:", sk.at, rgbx(255, 255, 255, 255))
      sk.at.y += 20
      discard sk.drawText("Default", "> Typos initialized successfully", sk.at, rgbx(255, 255, 255, 255))
      sk.at.y += 20
      discard sk.drawText("Default", "> Ready for input...", sk.at, rgbx(255, 255, 255, 255))

    else:
      discard sk.drawText("H1", activePanel.name, sk.at, rgbx(255, 255, 255, 255))
      sk.at.y += 40
      discard sk.drawText("Default", "This is the content of " & activePanel.name, sk.at, rgbx(255, 255, 255, 255))

# Initialize panel layout
var
  textViewerArea = Area()
  aiChatArea = Area()
  consoleArea = Area()

textViewerArea.addPanel("Text Viewer")
aiChatArea.addPanel("AI Chat")
consoleArea.addPanel("Console")

window.runeInputEnabled = true
window.onRune = proc(rune: Rune) =
  sk.inputRunes.add(rune)

window.onFrame = proc() =

  sk.beginUI(window, window.size)

  # Clear screen with background color
  sk.clearScreen(BackgroundColor)

  # Draw tiled test texture as the background.
  for x in 0 ..< 16:
    for y in 0 ..< 10:
      sk.at = vec2(x.float32 * 256, y.float32 * 256)
      image("testTexture", rgbx(30, 30, 30, 255))

  # 3-panel layout:
  # Left: Text Viewer (60% width)
  # Right: AI Chat top, Console bottom (40% width, 50/50 height split)

  let windowRect = rect(0, 1, window.size.x.float32, window.size.y.float32 - 1)
  let leftWidth = windowRect.w * 0.6
  let rightWidth = windowRect.w * 0.4
  let rightHeight = windowRect.h
  let topHeight = rightHeight * 0.5
  let bottomHeight = rightHeight * 0.5

  # Text Viewer panel (left side)
  let textViewerRect = rect(windowRect.x, windowRect.y, leftWidth, windowRect.h)
  drawArea(textViewerArea, textViewerRect)

  # AI Chat panel (top right)
  let aiChatRect = rect(windowRect.x + leftWidth, windowRect.y, rightWidth, topHeight)
  drawArea(aiChatArea, aiChatRect)

  # Console panel (bottom right)
  let consoleRect = rect(windowRect.x + leftWidth, windowRect.y + topHeight, rightWidth, bottomHeight)
  drawArea(consoleArea, consoleRect)

  let ms = sk.avgFrameTime * 1000
  sk.at = sk.pos + vec2(sk.size.x - 250, 20)
  text(&"frame time: {ms:>7.3f}ms")

  sk.endUi()
  window.swapBuffers()

when defined(emscripten):
  window.run()
else:
  while not window.closeRequested:
    pollEvents()
