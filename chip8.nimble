# Package

version       = "0.1.0"
author        = "HugoGranstrom"
description   = "A Chip-8 emulator written in Nim"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["chip8"]


# Dependencies

requires "nim >= 1.6.14"
requires "windy"
requires "opengl"
requires "sound"
requires "cligen"
