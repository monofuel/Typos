version     = "0.0.0"
author      = "monofuel"
description = "An AI text editor using silky"
license     = "MIT"

srcDir = "src"

requires "https://github.com/treeform/shady.git#head"
requires "nim >= 2.0.0", "opengl", "windy", "bumpy", "vmath", "chroma"
requires "https://github.com/treeform/silky"

# silky requires the latest shady on git, there hasn't been a release yet.
# and I can't get nimby working properly.
