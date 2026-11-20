## Poster 16: Chinese, four han and Latin around han.
##
## Top: "ni hao shi jie" (U+4F60 U+597D U+4E16 U+754C) shapes to four
## full em glyphs with three byte clusters each. Bottom: "A" plus two
## han plus "B" mixes proportional Latin advances with full em han,
## and the byte clusters step one for Latin, three for han.

import std/strformat

import ./support
import harfnim

const
  CanvasW = 1280
  CanvasH = 1040
  SizeA = 280
  SizeB = 230

proc drawRow(c: var Canvas; sf: ShaperFont; b: Buffer; baseY: float64;
    k: float64) =
  var total = 0i32
  for i in 0 ..< b.len:
    total += b.pos[i].xAdvance
  var pen = 640.0 - float64(total) / 2.0
  c.line(90, baseY, 1190, baseY, BaseLine, 2.0)
  for i in 0 ..< b.len:
    let g = b.info[i].glyphId
    let adv = float64(b.pos[i].xAdvance)
    c.drawExtentsBox(sf, g, pen, baseY)
    let d = glyphPath(sf, g, pen, baseY, k)
    if d != "":
      c.path(d, "#eef1ff", Ink, 3.0)
    c.circle(pen, baseY, 5, Origin, "#ffffff", 2.0)
    c.arrow(pen, baseY + 66, pen + adv, baseY + 66, Advance, 2.5,
      "arrGreen")
    c.label(pen + adv / 2, baseY + 92, fmt"gid {g}", 13, Ink,
      "middle")
    c.label(pen + adv / 2, baseY + 112,
      fmt"cluster {b.info[i].cluster}", 13, Cluster, "middle")
    pen += adv

proc main() =
  let path = findFontOrQuit([
    "/System/Library/Fonts/Supplemental/Songti.ttc",
    "/System/Library/Fonts/Hiragino Sans GB.ttc"])
  var c = newCanvas(CanvasW, CanvasH)
  c.header("Chinese: four han, four full ems",
    "Songti SC shapes hello world, then Latin around han with byte clusters.")
  let sfA = loadShaper(path, SizeA)
  let kA = pixelScale(sfA, SizeA)
  let top = shapeText(sfA, "\u4f60\u597d\u4e16\u754c",
    defaultFeatures())
  doAssert top.len == 4
  doAssert top.info[0].cluster == 0u32
  doAssert top.info[1].cluster == 3u32
  doAssert top.info[2].cluster == 6u32
  doAssert top.info[3].cluster == 9u32
  c.label(90, 150, "hello world in four full ems", 20, Ink, "start",
    "bold")
  drawRow(c, sfA, top, 410.0, kA)
  c.label(90, 585, "Latin around han: proportional next to full em",
    20, Ink, "start", "bold")
  let sfB = loadShaper(path, SizeB)
  let kB = pixelScale(sfB, SizeB)
  let mix = shapeText(sfB, "A\u4e2d\u6587B", defaultFeatures())
  doAssert mix.len == 4
  doAssert mix.info[0].cluster == 0u32
  doAssert mix.info[1].cluster == 1u32
  doAssert mix.info[2].cluster == 4u32
  doAssert mix.info[3].cluster == 7u32
  drawRow(c, sfB, mix, 830.0, kB)
  c.label(90, 985,
    fmt"Clusters 0 1 4 7 step one byte for Latin, three for han, with script={scriptName(mix)}.",
    14, Ink)
  c.footer("No joining, no ligatures: each han takes one em and keeps its three byte cluster.")
  let f = outPath("ex16_chinese")
  c.save(f)
  echo "wrote " & f

when isMainModule:
  main()
