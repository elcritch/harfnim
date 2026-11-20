## Poster 15: Japanese, one voicing mark and a mixed word.
##
## Top: HA plus combining voiced mark (U+306F U+3099) and precomposed
## BA (U+3070) shape to the identical glyph, showing normalization
## equivalence. Bottom: the word "taberu" (kanji TA plus hiragana
## BE RU) shapes to three full em glyphs with three byte clusters.

import std/strformat

import ./support
import harfnim

const
  CanvasW = 1280
  CanvasH = 1000
  SizeA = 340
  SizeB = 230

proc main() =
  let path = findFontOrQuit([
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/System/Library/Fonts/PingFang.ttc"])
  var c = newCanvas(CanvasW, CanvasH)
  c.header("Japanese: one voicing mark, two encodings",
    "Hiragino Sans GB shapes two encodings to one glyph, then a kanji plus hiragana word.")
  let sfA = loadShaper(path, SizeA)
  let kA = pixelScale(sfA, SizeA)
  let pre = shapeText(sfA, "\u3070", offFeatures())
  let decomp = shapeText(sfA, "\u306F" & "\u3099", offFeatures())
  doAssert pre.len == 1 and decomp.len == 1
  doAssert pre.info[0].glyphId == decomp.info[0].glyphId
  let baseA = 400.0
  c.label(90, 150, "one voicing mark, two encodings", 20, Ink, "start",
    "bold")
  let gid = pre.info[0].glyphId
  var pen = 450.0
  let panels = [("U+3070 precomposed", pre),
    ("U+306F + U+3099 decomposed", decomp)]
  for pi in 0 ..< panels.len:
    let (label, b) = panels[pi]
    let d = glyphPath(sfA, gid, pen, baseA, kA)
    if d != "":
      c.path(d, "#eef1ff", Ink, 3.0)
    c.circle(pen, baseA, 5, Origin, "#ffffff", 2.0)
    let adv = float64(b.pos[0].xAdvance)
    c.label(pen + adv / 2, baseA + 46, label, 14, Ink, "middle")
    c.label(pen + adv / 2, baseA + 68,
      fmt"gid {gid} cluster {b.info[0].cluster}", 14, Cluster,
      "middle")
    pen += adv
    if pi == 0:
      c.arrow(pen + 14, baseA - 120, pen + 110, baseA - 120, Cluster,
        2.5, "arrCluster")
      c.label(pen + 62, baseA - 132, "same", 14, Cluster, "middle")
      pen += 124
  c.label(90, 500,
    "Both inputs shape to the same glyph: the normalizer composes the pair before GSUB runs.",
    14, Ink)
  let sfB = loadShaper(path, SizeB)
  let kB = pixelScale(sfB, SizeB)
  let word = "\u98df\u3079\u308b"
  let wb = shapeText(sfB, word, defaultFeatures())
  doAssert wb.len == 3
  doAssert wb.info[0].cluster == 0u32
  doAssert wb.info[1].cluster == 3u32
  doAssert wb.info[2].cluster == 6u32
  let baseB = 800.0
  c.label(90, 560, "kanji sets the root, hiragana sets the inflection",
    20, Ink, "start", "bold")
  var total = 0i32
  for i in 0 ..< wb.len:
    total += wb.pos[i].xAdvance
  let penB = 640.0 - float64(total) / 2.0
  c.line(90, baseB, 1190, baseB, BaseLine, 2.0)
  var p = penB
  for i in 0 ..< wb.len:
    let g = wb.info[i].glyphId
    let adv = float64(wb.pos[i].xAdvance)
    c.drawExtentsBox(sfB, g, p, baseB)
    let d = glyphPath(sfB, g, p, baseB, kB)
    if d != "":
      c.path(d, "#eef1ff", Ink, 3.0)
    c.circle(p, baseB, 5, Origin, "#ffffff", 2.0)
    c.arrow(p, baseB + 66, p + adv, baseB + 66, Advance, 2.5,
      "arrGreen")
    c.label(p + adv / 2, baseB + 92, fmt"gid {g}", 13, Ink, "middle")
    c.label(p + adv / 2, baseB + 112,
      fmt"cluster {wb.info[i].cluster}", 13, Cluster, "middle")
    p += adv
  c.label(90, 940,
    fmt"Three glyphs take three full ems with script={scriptName(wb)}; every han and kana costs three UTF-8 bytes.",
    14, Ink)
  c.footer("The dakuten composes away, then TA BE RU walk the baseline with one origin per em.")
  let f = outPath("ex15_japanese")
  c.save(f)
  echo "wrote " & f

when isMainModule:
  main()
