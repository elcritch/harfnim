## Poster 1: anatomy of shaped text.
##
## Shapes "AV" with Arial at a big size and draws every guide at once:
## baseline, ascender, descender, glyph origins, advance arrows, scaled
## extents boxes, and cluster labels, plus a reading panel.

import std/strformat

import ./support
import harfnim

const
  CanvasW = 1280
  CanvasH = 780
  SizePx = 560
  PenX = 90.0
  BaseY = 580.0

proc main() =
  let path = findDemoFont()
  if path == "":
    quit("no demo font found")
  let sf = loadShaper(path, SizePx)
  let feats = defaultFeatures()
  var b = shapeText(sf, "AV", feats)
  let k = pixelScale(sf, SizePx)
  let (asc, desc) = hheaAscentDescent(sf.font)
  var c = newCanvas(CanvasW, CanvasH)
  c.header("Anatomy of shaped text", "")
  let total = block:
    var t = 0i32
    for i in 0 ..< b.len:
      t += b.pos[i].xAdvance
    t
  let spanL = PenX - 40.0
  let spanR = PenX + float64(total) + 40.0
  c.line(spanL, BaseY - float64(desc) * k, spanR,
    BaseY - float64(desc) * k, MetricLine, 1.5, "7 5")
  c.label(spanR - 4, BaseY - float64(desc) * k - 8, "descender", 13,
    MetricLine, "end")
  c.line(spanL, BaseY - float64(asc) * k, spanR, BaseY - float64(asc) * k,
    MetricLine, 1.5, "7 5")
  c.label(spanR - 4, BaseY - float64(asc) * k - 8, "ascender", 13,
    MetricLine, "end")
  c.line(48, BaseY, 1232, BaseY, BaseLine, 2.0)
  c.label(48, BaseY + 24, "baseline", 13, BaseLine)
  var pen = PenX
  for i in 0 ..< b.len:
    let gid = b.info[i].glyphId
    let adv = float64(b.pos[i].xAdvance)
    let xOff = float64(b.pos[i].xOffset)
    let yOff = float64(b.pos[i].yOffset)
    c.drawExtentsBox(sf, gid, pen, BaseY, xOff, yOff)
    c.drawGlyphBox(sf, gid, pen, BaseY, k, xOff, yOff)
    c.line(pen, 128, pen, 660, Origin, 1.0, "3 4")
    c.circle(pen, BaseY, 6, Origin, "#ffffff", 2.0)
    c.arrow(pen, BaseY + 62, pen + adv, BaseY + 62, Advance, 2.5,
      "arrGreen")
    c.label(pen + adv / 2, BaseY + 88, fmt"adv {b.pos[i].xAdvance}",
      14, Advance, "middle")
    c.label(pen + adv / 2, 112, fmt"cluster {b.info[i].cluster}", 14,
      Cluster, "middle")
    c.label(pen + adv / 2, 134, fmt"gid {gid}", 13, Ink, "middle")
    pen += adv
  c.circle(pen, BaseY, 6, "#ffffff", Origin, 2.0)
  c.label(pen, BaseY + 24, "pen", 13, Origin, "middle")
  var y = 150.0
  c.label(920, y, "Reading the guides", 20, Ink, "start", "bold")
  y += 30
  c.label(920, y, fmt"total advance {total}px over {b.len} glyphs", 15,
    Faint)
  y += 30
  c.label(920, y, fmt"Arial at {SizePx}px", 14, Ink)
  y += 22
  c.label(920, y, fmt"script={scriptName(b)} direction={dirName(b.direction)}",
    14, Ink)
  y += 34
  for (sw, txt) in [("red", "baseline, all origins sit on it"),
      ("teal", "hhea ascender and descender"),
      ("blue", "glyph origin and pen stops"),
      ("green", "advance arrows set the next origin"),
      ("purple", "scaled extents boxes"),
      ("orange", "UTF-8 byte cluster per glyph")]:
    let col = case sw
      of "red": BaseLine
      of "teal": MetricLine
      of "blue": Origin
      of "green": Advance
      of "purple": Box
      else: Cluster
    c.rect(920, y - 12, 26, 12, col, col)
    c.label(954, y, txt, 14, Ink)
    y += 26
  y += 10
  c.label(920, y, "After shape, buf.info holds glyph ids", 14, Ink)
  y += 22
  c.label(920, y, "and clusters, buf.pos holds advances", 14, Ink)
  y += 22
  c.label(920, y, "and offsets. The pen walk above is", 14, Ink)
  y += 22
  c.label(920, y, "exactly origin plus advance, in order.", 14, Ink)
  c.footer("Origins sit on the baseline; each advance arrow spans one glyph advance; purple boxes are scaled extents; orange tags are byte clusters.")
  let p = outPath("ex01_anatomy")
  c.save(p)
  echo "wrote " & p

when isMainModule:
  main()
