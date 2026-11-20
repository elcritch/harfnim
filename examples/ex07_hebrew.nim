## Poster 7: Hebrew, vowels ride the consonants.
##
## Shapes "shalom" (shin, qamats, lamed, vav, holam, final mem, plus
## the shin dot) with Arial. The top strip is logical order; the bottom
## strip is shaped visual order with mark offset arrows. The Hebrew
## shaper reorders marks, the RTL buffer reverses, and GPOS offsets
## place each vowel and dot.

import std/strformat
import std/strutils

import ./support
import harfnim

const
  CanvasW = 1280
  CanvasH = 920
  SizePx = 300
  Text = "שָׁלוֹם"

proc main() =
  let path = findDemoFont()
  if path == "":
    quit("no demo font found")
  let sf = loadShaper(path, SizePx)
  let k = pixelScale(sf, SizePx)
  let feats = defaultFeatures()
  let b = shapeText(sf, Text, feats)
  doAssert b.direction == dirRightToLeft
  var c = newCanvas(CanvasW, CanvasH)
  c.header("Hebrew: vowels ride the consonants",
    fmt"Arial at {SizePx}px shapes shalom into {b.len} RTL glyphs: script={scriptName(b)} direction={dirName(b.direction)}")
  var offs: seq[int] = @[]
  var cps: seq[uint32] = @[]
  var p = 0
  while p < Text.len:
    offs.add(p)
    let b0 = uint8(Text[p])
    if b0 < 0x80u8:
      cps.add(uint32(b0))
      inc p
    else:
      cps.add((uint32(b0 and 0x1Fu8) shl 6) or
        uint32(uint8(Text[p + 1]) and 0x3Fu8))
      p += 2
  let boxW = 110.0
  let topX = 640.0 - float64(offs.len) * (boxW + 10.0) / 2.0
  let topY = 140.0
  c.label(90, 122, "logical order (codepoints, byte offsets)", 16, Ink,
    "start", "bold")
  for n, o in offs:
    let x = topX + float64(n) * (boxW + 10.0)
    c.rect(x, topY, boxW, 70, "#ffffff", Faint, 1.5)
    c.label(x + boxW / 2, topY + 30, "U+" & cps[n].toHex(4), 15, Ink,
      "middle")
    c.label(x + boxW / 2, topY + 52, fmt"byte {o}", 12, Faint, "middle")
  let baseY = 620.0
  c.label(90, 300, "shaped visual order (RTL, marks positioned)", 16,
    Ink, "start", "bold")
  var total = 0i32
  for g in 0 ..< b.len:
    total += b.pos[g].xAdvance
  let pen0 = 640.0 - float64(total) / 2.0
  c.line(90, baseY, 1190, baseY, BaseLine, 2.0)
  var pen = pen0
  for g in 0 ..< b.len:
    let gid = b.info[g].glyphId
    let adv = float64(b.pos[g].xAdvance)
    let xOff = float64(b.pos[g].xOffset)
    let yOff = float64(b.pos[g].yOffset)
    let isMark = adv == 0.0
    if isMark:
      let d = glyphPath(sf, gid, pen, baseY, k, xOff, yOff)
      if d != "":
        c.path(d, "#fff3e6", Cluster, 3.0)
      if xOff != 0.0 or yOff != 0.0:
        c.arrow(pen, baseY, pen + xOff, baseY - yOff, Cluster, 2.0,
          "arrCluster")
        c.label(pen + xOff + 10, baseY - yOff - 10,
          fmt"offset {b.pos[g].xOffset},{b.pos[g].yOffset}", 13,
          Cluster)
      c.circle(pen, baseY, 4, Cluster, "#ffffff", 2.0)
    else:
      c.drawExtentsBox(sf, gid, pen, baseY, xOff, yOff)
      let d = glyphPath(sf, gid, pen, baseY, k, xOff, yOff)
      if d != "":
        c.path(d, "#eef1ff", Ink, 3.0)
      c.circle(pen, baseY, 5, Origin, "#ffffff", 2.0)
      c.arrow(pen, baseY + 66, pen + adv, baseY + 66, Advance, 2.5,
        "arrGreen")
    c.label(pen + adv / 2, baseY + 92, fmt"gid {gid}", 13, Ink,
      "middle")
    c.label(pen + adv / 2, baseY + 112, fmt"cluster {b.info[g].cluster}",
      13, Cluster, "middle")
    var li = -1
    for n, o in offs:
      if o == int(b.info[g].cluster):
        li = n
        break
    if li >= 0:
      let lx = topX + float64(li) * (boxW + 10.0) + boxW / 2.0
      c.line(lx, topY + 70, pen + adv / 2, baseY - 200, Cluster, 1.5)
    pen += adv
  c.label(90, 800,
    "Marks keep their source clusters while the buffer reverses for RTL display.",
    14, Ink)
  c.label(90, 822,
    "The Hebrew shaper orders shin dots and vowels; GPOS offsets drop each one onto its base.",
    14, Ink)
  c.footer("Consonants advance the pen; combining marks ride along with offsets and zero advances.")
  let f = outPath("ex07_hebrew")
  c.save(f)
  echo "wrote " & f

when isMainModule:
  main()
