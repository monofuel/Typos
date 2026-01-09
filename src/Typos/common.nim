## Common types and constants for Typos

import chroma, bumpy

# local lm studio
# http://10.11.2.14:1234
# can use with openai_leap library
# can use `unsloth/qwen3-coder-30b-a3b-instruct` with tool usage.

# can also use xai with grok-code-fast-1
# racha has configuration for xai API keys and stuff.


# Chat message types
type
  ChatMessage* = ref object
    sender*: string  # "User" or "AI"
    content*: string
    timestamp*: float64

# Panel system types
type
  Panel* = ref object
    name*: string
    selected*: bool

  Area* = ref object
    panels*: seq[Panel]
    selectedPanelNum*: int
    rect*: Rect

# Theme constants for dark mode
const
  # Background colors
  BackgroundColor* = parseHtmlColor("#0d1117").rgbx  # Main background
  PanelBackgroundColor* = parseHtmlColor("#161b22").rgbx  # Panel backgrounds

  # Text colors
  TextPrimaryColor* = parseHtmlColor("#e6edf3").rgbx  # Primary text
  TextSecondaryColor* = parseHtmlColor("#8b949e").rgbx  # Secondary text
  UserMessageColor* = parseHtmlColor("#58a6ff").rgbx  # User messages
  AIMessageColor* = parseHtmlColor("#3fb950").rgbx  # AI messages

  # UI element colors
  BorderColor* = parseHtmlColor("#30363d").rgbx  # Borders and highlights
  WhiteColor* = rgbx(255, 255, 255, 255)  # Pure white for accents
