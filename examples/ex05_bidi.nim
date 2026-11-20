## Poster 5: bidirectional runs, logical versus visual order.
##
## Runs visualRuns over "ab Hebrew cd" with automatic base direction,
## then shapes each run on its own with an explicit direction. The top
## strip is logical order, the bottom strip is shaped visual order, and
## orange connectors trace the byte map between them.

import std/options
import std/strformat
import std/strutils

import ./support
import harfnim

const
  CanvasW = 1280
  CanvasH = 1020
  SizePx = 200
  Text = "ab אבג cd"

proc runColor(level: int): string =
  case level
  of 0: RunA
  of 1: RunB
  else: RunC

proc runMarker(level: int): string =
  case level
  of 0: "arrBlue"
  of 1: "arrOrange"
  else: "arrGreen"

proc main() =
  let path = findDemoFont()
  if path == "":
    quit("no demo font found")
  let sf = loadShaper(path, SizePx)
  let k = pixelScale(sf, SizePx)
  let feats = defaultFeatures()
  let vt = visualRuns(Text, bdAuto)
  var c = newCanvas(CanvasW, CanvasH)
  c.header("Bidirectional runs: logical versus visual order",
    "visualRuns over 'ab Hebrew cd' (alef, bet, gimel), auto base direction, one run per level.")
  c.label(90, 130, "logical order (reading order, byte offsets)", 16, Ink,
    "start", "bold")
  var chars: seq[tuple[cp: uint32, off, len: int]] = @[]
  var i = 0
  while i < Text.len:
    let b0 = uint8(Text[i])
    var size = 1
    var cp = 0xFFFDu32
    if b0 < 0x80u8:
      cp = uint32(b0)
    elif b0 >= 0xC2u8 and b0 < 0xE0u8 and i + 1 < Text.len:
      cp = (uint32(b0 and 0x1Fu8) shl 6) or uint32(uint8(Text[i+1]) and 0x3Fu8)
      size = 2
    elif b0 < 0xF0u8 and i + 2 < Text.len:
      cp = (uint32(b0 and 0x0Fu8) shl 12) or
        (uint32(uint8(Text[i+1]) and 0x3Fu8) shl 6) or
        uint32(uint8(Text[i+2]) and 0x3Fu8)
      size = 3
    chars.add((cp, i, size))
    i += size
  let boxW = 76.0
  let topX = 640.0 - float64(chars.len) * (boxW + 8.0) / 2.0
  let topY = 150.0
  for n, ch in chars:
    let x = topX + float64(n) * (boxW + 8.0)
    c.rect(x, topY, boxW, 64, "#ffffff", Faint, 1.5)
    var rep = ""
    if ch.cp < 128u32:
      rep = $char(ch.cp)
    else:
      rep = "U+" & ch.cp.toHex(4)
    c.label(x + boxW / 2, topY + 28, rep, 17, Ink, "middle")
    c.label(x + boxW / 2, topY + 50, fmt"byte {ch.off}", 12, Faint,
      "middle")
  var baseY = 430.0
  for r, run in vt.runs:
    let col = runColor(run.level)
    let sub = vt.text[run.first ..< run.last]
    var srcMin = Text.len
    var srcMax = -1
    for j in run.first ..< run.last:
      if j < vt.map.len - 1:
        srcMin = min(srcMin, vt.map[j])
        srcMax = max(srcMax, vt.map[j])
    let logical = Text[srcMin .. srcMax]
    var b = newBuffer()
    b.pushStr(logical)
    b.setDirection(run.dir)
    sf.shape(b, feats)
    var total = 0i32
    for g in 0 ..< b.len:
      total += b.pos[g].xAdvance
    let pen0 = 640.0 - float64(total) / 2.0
    c.label(90, baseY - 130, fmt"run {r}: level {run.level} {dirName(run.dir)}",
      16, col, "start", "bold")
    c.rect(90, baseY - 118, 1180, 190, "#ffffff", col, 1.5)
    c.line(90, baseY, 1270, baseY, BaseLine, 1.5)
    var pen = pen0
    for g in 0 ..< b.len:
      let gid = b.info[g].glyphId
      let d = glyphPath(sf, gid, pen, baseY, k,
        float64(b.pos[g].xOffset), float64(b.pos[g].yOffset))
      if d != "":
        c.path(d, "#eef1ff", Ink, 3.0)
      c.circle(pen, baseY, 4, col, "#ffffff", 2.0)
      c.label(pen + float64(b.pos[g].xAdvance) / 2, baseY + 52,
        fmt"cl {b.info[g].cluster + uint32(srcMin)}", 12, Cluster,
        "middle")
      var li = -1
      for n, ch in chars:
        if int(ch.off) == int(b.info[g].cluster) + srcMin:
          li = n
          break
      if li >= 0:
        let lx = topX + float64(li) * (boxW + 8.0) + boxW / 2.0
        c.line(lx, topY + 64, pen + float64(b.pos[g].xAdvance) / 2,
          baseY - 150, Cluster, 1.2)
      pen += float64(b.pos[g].xAdvance)
    baseY += 190
  c.label(90, baseY - 40,
    "Each run shapes with an explicit direction, bypassing segment guessing.",
    14, Ink)
  c.label(90, baseY - 18,
    "Orange connectors follow VisualText.map from each source byte to its visual glyph.",
    14, Ink)
  c.footer("visualRuns returns visual order text, a per byte source map with sentinel, and maximal level runs.")
  let p = outPath("ex05_bidi")
  c.save(p)
  echo "wrote " & p

when isMainModule:
  main()
