## Poster 4: marks, anchors, offsets, and zero advances.
##
## Two Arial panels. Left: beh plus fatha (U+064E) stays two glyphs,
## the mark positioned by GPOS mark to base with an offset arrow and a
## zero advance. Right: a plus combining acute (U+0301) composes into
## one precomposed glyph through ccmp, merging two clusters into one.

import std/strformat

import ./support
import harfnim

const
  CanvasW = 1280
  CanvasH = 820
  SizePx = 380

proc main() =
  let path = findDemoFont()
  if path == "":
    quit("no demo font found")
  let sf = loadShaper(path, SizePx)
  let k = pixelScale(sf, SizePx)
  var c = newCanvas(CanvasW, CanvasH)
  c.header("Marks: anchors, offsets, and zero advances",
    fmt"Arial at {SizePx}px. Left: GPOS mark to base. Right: ccmp composition.")
  let b = shapeText(sf, "ب" & "\u064E", defaultFeatures())
  doAssert b.len == 2
  let penL = 120.0
  let baseL = 500.0
  c.label(penL, 150, "beh + fatha (U+064E): two glyphs", 20, Ink,
    "start", "bold")
  c.line(penL - 30, baseL, penL + 420, baseL, BaseLine, 2.0)
  var pen = penL
  for i in 0 ..< b.len:
    let gid = b.info[i].glyphId
    let xOff = float64(b.pos[i].xOffset)
    let yOff = float64(b.pos[i].yOffset)
    if i == 0:
      let d = glyphPath(sf, gid, pen, baseL, k, xOff, yOff)
      if d != "":
        c.path(d, "#fff3e6", Cluster, 3.0)
      c.circle(pen + xOff, baseL - yOff, 6, Cluster, "#ffffff", 2.0)
      c.arrow(pen, baseL, pen + xOff, baseL - yOff, Cluster, 2.0,
        "arrCluster")
      c.label(pen + xOff + 16, baseL - yOff + 5,
        fmt"offset {b.pos[i].xOffset},{b.pos[i].yOffset}", 14, Cluster)
      c.label(pen, baseL + 60, "mark: adv 0", 14, Cluster, "middle")
    else:
      c.drawGlyphBox(sf, gid, pen, baseL, k, xOff, yOff)
      c.circle(pen, baseL, 6, Origin, "#ffffff", 2.0)
      c.arrow(pen, baseL + 60, pen + float64(b.pos[i].xAdvance),
        baseL + 60, Advance, 2.5, "arrGreen")
      c.label(pen + 120, baseL + 86,
        fmt"base adv {b.pos[i].xAdvance}", 14, Advance)
    pen += float64(b.pos[i].xAdvance)
  c.label(penL, baseL + 120,
    "The mark rides the base origin plus its offset and", 14, Ink)
  c.label(penL, baseL + 142, "consumes no advance of its own.", 14, Ink)
  let e = shapeText(sf, "a" & "\u0301", defaultFeatures())
  let penR = 740.0
  let baseR = 500.0
  c.label(penR, 150, "a + acute (U+0301): one glyph", 20, Ink, "start",
    "bold")
  c.line(penR - 30, baseR, penR + 420, baseR, BaseLine, 2.0)
  if e.len == 1:
    let gid = e.info[0].glyphId
    c.drawGlyphBox(sf, gid, penR + 40, baseR, k)
    c.circle(penR + 40, baseR, 6, Origin, "#ffffff", 2.0)
    c.label(penR + 40, baseR - 330, fmt"gid {gid} cluster 0", 14, Ink,
      "middle")
    c.label(penR + 40, baseR - 306, "2 chars, 1 glyph", 14, Cluster,
      "middle")
    c.arrow(penR + 40, baseR + 60, penR + 40 + float64(e.pos[0].xAdvance),
      baseR + 60, Advance, 2.5, "arrGreen")
    c.label(penR + 40 + float64(e.pos[0].xAdvance) / 2, baseR + 86,
      fmt"adv {e.pos[0].xAdvance}", 14, Advance, "middle")
    c.label(penR + 40, baseR + 120,
      "ccmp composes the pair and merges clusters 0+1.", 14, Ink)
  else:
    c.label(penR, baseR - 200, "no composition in this font", 14,
      BaseLine)
  c.footer("Mark positioning shifts the glyph without advancing the pen; composition replaces two codepoints with one glyph id.")
  let p = outPath("ex04_marks")
  c.save(p)
  echo "wrote " & p

when isMainModule:
  main()
