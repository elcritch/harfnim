# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "Pure Nim port of the HarfBuzz text shaping engine"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 2.2.0"

task examples, "Regenerate the SVG shaping guides in examples/out":
  for n in ["01_anatomy", "02_kerning", "03_ligature", "04_marks",
      "05_bidi", "06_arabic", "07_hebrew", "08_russian", "09_thai",
      "10_hangul", "11_greek"]:
    let bin = "/tmp/harfnim-ex-" & n
    exec "clue build examples/ex" & n & ".nim --out:" & bin
    exec bin
