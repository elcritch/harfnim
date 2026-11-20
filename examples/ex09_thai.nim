## Poster 9: Thai, SARA AM splits apart.
##
## Shapes KO KAI plus precomposed SARA AM (U+0E33) next to KO KAI plus
## the explicit NIKHAHIT plus SARA A sequence (U+0E4D U+0E32) with
## Ayuthaya. Both inputs produce the identical gid stream, proving the
## SARA AM split: a zero advance mark plus the vowel.

import std/strformat
import std/strutils

import ./support
import harfnim

const
  CanvasW = 1280
  CanvasH = 880
  SizePx = 380

proc row(c: var Canvas; sf: ShaperFont; text, title: string; penX,
    baseY, k: float64; titleY: float64): seq[uint32] =
  let b = shapeText(sf, text, defaultFeatures())
  doAssert b.len == 3
  c.label(penX, titleY, title, 20, Ink, "start", "bold")
  var pen = 640.0 - 594.0 * k
  for i in 0 ..< b.len:
    let gid = b.info[i].glyphId
    let adv = float64(b.pos[i].xAdvance)
    if adv == 0.0:
      let d = glyphPath(sf, gid, pen, baseY, k)
      if d != "":
        c.path(d, "#fff3e6", Cluster, 3.0)
      c.circle(pen, baseY, 4, Cluster, "#ffffff", 2.0)
      c.label(pen, baseY + 62, "adv 0", 14, Cluster, "middle")
    else:
      let d = glyphPath(sf, gid, pen, baseY, k)
      if d != "":
        c.path(d, "#eef1ff", Ink, 3.0)
      c.circle(pen, baseY, 5, Origin, "#ffffff", 2.0)
      c.arrow(pen, baseY + 62, pen + adv, baseY + 62, Advance, 2.5,
        "arrGreen")
    c.label(pen + adv / 2, baseY + 88, fmt"adv {b.pos[i].xAdvance}", 14,
      Advance, "middle")
    c.label(pen + adv / 2, baseY + 110, fmt"gid {gid} cl {b.info[i].cluster}",
      14, Ink, "middle")
    pen += adv
    result.add(gid)
  c.line(penX, baseY, 1190, baseY, BaseLine, 2.0)

proc main() =
  let path = findFontOrQuit([
    "/System/Library/Fonts/Supplemental/Ayuthaya.ttf"])
  let sf = loadShaper(path, SizePx)
  let k = pixelScale(sf, SizePx)
  var c = newCanvas(CanvasW, CanvasH)
  c.header("Thai: SARA AM splits apart",
    fmt"Ayuthaya at {SizePx}px: one syllable from two encodings.")
  let gA = row(c, sf, "กำ", "precomposed SARA AM (U+0E01 U+0E33)", 90,
    400, k, 150.0)
  let gB = row(c, sf, "ก" & "\u0E4D\u0E32",
    "NIKHIT + SARA A (U+0E01 U+0E4D U+0E32)", 90, 700, k, 560.0)
  doAssert gA == gB
  var s = ""
  for g in gA:
    s &= $g & " "
  c.label(90, 826, fmt"gid streams match: {s.strip()}. The mark takes no advance; clusters merge in A, survive in B.",
    14, Ink)
  c.footer("The Thai shaper splits U+0E33 so NIKHAHIT and SARA A position independently.")
  let p = outPath("ex09_thai")
  c.save(p)
  echo "wrote " & p

when isMainModule:
  main()
