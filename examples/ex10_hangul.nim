## Poster 10: Hangul, jamo compose into syllables.
##
## Shapes conjoining jamo HIEUH A JUNSEONG (U+1112 U+1161 U+11AB) with
## AppleGothic and compares against precomposed HANGUL GEUL. The three
## jamo compose to the identical glyph id as the precomposed syllable,
## showing Hangul LV and LVT composition before GSUB runs.

import std/strformat
import std/strutils

import ./support
import harfnim

const
  CanvasW = 1280
  CanvasH = 800
  SizePx = 280

proc main() =
  let path = findFontOrQuit([
    "/System/Library/Fonts/Supplemental/AppleGothic.ttf",
    "/System/Library/Fonts/Supplemental/AppleMyungjo.ttf"])
  let sf = loadShaper(path, SizePx)
  let k = pixelScale(sf, SizePx)
  let feats = defaultFeatures()
  let jamo = shapeText(sf, "한", feats)
  let pre = shapeText(sf, "한글", feats)
  doAssert jamo.len == 1
  doAssert pre.len == 2
  doAssert jamo.info[0].glyphId == pre.info[0].glyphId
  var c = newCanvas(CanvasW, CanvasH)
  c.header("Hangul: jamo compose into syllables",
    "AppleGothic at 280px: three conjoining jamo become one syllable glyph.")
  let baseY = 600.0
  c.label(90, 150, "conjoining jamo in, one syllable out", 20, Ink,
    "start", "bold")
  let names = ["U+1112 HIEUH", "U+1161 A", "U+11AB NIEUN"]
  var jx = 175.0
  for n in names:
    c.rect(jx, 170, 100, 64, "#ffffff", Faint, 1.5)
    c.label(jx + 50, 196, n.split(' ')[0], 14, Ink, "middle")
    c.label(jx + 50, 216, n.split(' ', 1)[1], 11, Faint, "middle")
    jx += 112
  c.arrow(325, 250, 325, 330, Cluster, 2.5, "arrCluster")
  c.label(345, 295, "compose", 14, Cluster)
  let gid = jamo.info[0].glyphId
  let penL = 325.0 - float64(jamo.pos[0].xAdvance) / 2.0
  let d = glyphPath(sf, gid, penL, baseY, k)
  if d != "":
    c.path(d, "#eef1ff", Ink, 3.0)
  c.circle(penL, baseY, 5, Origin, "#ffffff", 2.0)
  c.arrow(penL, baseY + 62, penL + float64(jamo.pos[0].xAdvance),
    baseY + 62, Advance, 2.5, "arrGreen")
  c.label(325, baseY + 88, fmt"gid {gid} cluster 0", 14, Ink,
    "middle")
  c.label(620, 150, "precomposed 한글 for comparison", 20, Ink, "start",
    "bold")
  c.line(620, baseY, 1230, baseY, BaseLine, 2.0)
  var pen = 645.0
  for i in 0 ..< pre.len:
    let g = pre.info[i].glyphId
    c.drawExtentsBox(sf, g, pen, baseY)
    let dd = glyphPath(sf, g, pen, baseY, k)
    if dd != "":
      c.path(dd, "#eef1ff", Ink, 3.0)
    c.circle(pen, baseY, 5, Origin, "#ffffff", 2.0)
    let adv = float64(pre.pos[i].xAdvance)
    c.arrow(pen, baseY + 62, pen + adv, baseY + 62, Advance, 2.5,
      "arrGreen")
    c.label(pen + adv / 2, baseY + 88, fmt"gid {g}", 14, Ink,
      "middle")
    c.label(pen + adv / 2, baseY + 110,
      fmt"cluster {pre.info[i].cluster}", 14, Cluster, "middle")
    pen += adv
  c.label(620, baseY + 150,
    "First gid matches the composed jamo: U+1112 U+1161 U+11AB and U+D55C converge.",
    14, Ink)
  c.footer("The Hangul shaper composes LV and LVT syllables from jamo before GSUB runs.")
  let p = outPath("ex10_hangul")
  c.save(p)
  echo "wrote " & p

when isMainModule:
  main()
