## Poster 2: kerning, the kern feature at work.
##
## Shapes "AV" and "To" with Arial twice, once with an empty feature
## list and once with kern enabled. The unkerned outlines stay visible
## in gray behind the inked kerned output, and a red arrow at the
## advance level spans the exact kern delta.

import std/strformat
import std/strutils

import ./support
import harfnim

const
  CanvasW = 1280
  CanvasH = 760
  SizePx = 380
  BaseY = 480.0

proc section(c: var Canvas; sf: ShaperFont; text: string; penX: float64;
    k: float64) =
  let off = shapeText(sf, text, offFeatures())
  let on = shapeText(sf, text,
    @[globalFeature(tagFromStr("kern"), 1)])
  c.label(penX, 150, text & " with kern off (gray) vs on (ink)", 20,
    Ink, "start", "bold")
  var penOff = penX
  for i in 0 ..< off.len:
    let d = glyphPath(sf, off.info[i].glyphId, penOff, BaseY, k)
    if d != "":
      c.path(d, "#f4f5fa", "#9aa3b2", 2.5)
    penOff += float64(off.pos[i].xAdvance)
  var penOn = penX
  for i in 0 ..< on.len:
    let gid = on.info[i].glyphId
    c.drawExtentsBox(sf, gid, penOn, BaseY)
    let d = glyphPath(sf, gid, penOn, BaseY, k)
    if d != "":
      c.path(d, "#eef1ff", Ink, 3.0)
    c.circle(penOn, BaseY, 5, Origin, "#ffffff", 2.0)
    penOn += float64(on.pos[i].xAdvance)
  c.line(penX - 20, BaseY, max(penOff, penOn) + 90, BaseY, BaseLine, 2.0)
  var totalOff = 0i32
  var totalOn = 0i32
  var advNote = ""
  for i in 0 ..< off.len:
    totalOff += off.pos[i].xAdvance
    totalOn += on.pos[i].xAdvance
    advNote &= fmt"{off.pos[i].xAdvance}>{on.pos[i].xAdvance} "
  c.arrow(penX + float64(totalOff), BaseY + 95, penX + float64(totalOn),
    BaseY + 95, BaseLine, 2.0, "arrRed")
  c.label((2 * penX + float64(totalOff + totalOn)) / 2, BaseY + 86,
    fmt"kern delta {totalOn - totalOff}", 14, BaseLine, "middle",
    "bold")
  c.label(penX - 20, BaseY + 130, fmt"off total {totalOff}", 14, Faint)
  c.label(penX - 20, BaseY + 152, fmt"on total {totalOn}", 14, Advance)
  c.label(penX - 20, BaseY + 174, fmt"advances {advNote.strip()}", 13,
    Faint)
  c.label(penX, BaseY + 204,
    "Clusters and glyph ids are unchanged; only advances move.", 13,
    Faint)


proc main() =
  let path = findDemoFont()
  if path == "":
    quit("no demo font found")
  let sf = loadShaper(path, SizePx)
  let k = pixelScale(sf, SizePx)
  var c = newCanvas(CanvasW, CanvasH)
  c.header("Kerning: the kern feature at work",
    fmt"Arial at {SizePx}px, kern off vs kern on. Gray is unkerned, ink is kerned.")
  section(c, sf, "AV", 90, k)
  section(c, sf, "To", 700, k)
  c.footer("Pair kerning (GPOS kern) shrinks the first advance; the second glyph shifts left by the kern delta.")
  let p = outPath("ex02_kerning")
  c.save(p)
  echo "wrote " & p

when isMainModule:
  main()
