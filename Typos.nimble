version     = "0.0.0"
author      = "monofuel"
description = "An AI text editor using silky"
license     = "MIT"

srcDir = "src"

requires "https://github.com/treeform/shady"
requires "https://github.com/treeform/silky"
requires "nim >= 2.0.0", "opengl", "windy", "bumpy", "vmath", "chroma"
# silky requires the latest shady on git, there hasn't been a release yet.
# and I can't get nimby working properly.
# things are broken on CI at the moment
