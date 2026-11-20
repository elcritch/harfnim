## Poster 11: Greek, accent and final sigma.
##
## Top: precomposed alpha with tonos (U+03AC) and decomposed alpha
## plus combining tonos (U+03B1 U+0301) shape to the identical glyph,
## showing normalization equivalence. Bottom: the word "logos"
## shaped with kern off (gray) vs on (ink); the lamda pair tightens
## and word-final sigma takes its final form.

import std/strformat

import ./support
import harfnim

const
  CanvasW = 1280
  CanvasH = 960
  SizeA = 340
  SizeB = 260

proc main() =
  let path = findDemoFont()
  if path == "":
    quit("no demo font found")
  var c = newCanvas(CanvasW, CanvasH)
  c.header("Greek: accent and final sigma",
    "Arial shows normalization equivalence, then kerns the word logos.")
  let sfA = loadShaper(path, SizeA)
  let kA = pixelScale(sfA, SizeA)
  let pre = shapeText(sfA, "ά", offFeatures())
  let decomp = shapeText(sfA, "α" & "\u0301", offFeatures())
  doAssert pre.len == 1 and decomp.len == 1
  doAssert pre.info[0].glyphId == decomp.info[0].glyphId
  let baseA = 400.0
  c.label(90, 150, "one accent, two encodings", 20, Ink, "start",
    "bold")
  let gid = pre.info[0].glyphId
  var pen = 450.0
  let panels = [("U+03AC precomposed", pre),
    ("U+03B1 + U+0301 decomposed", decomp)]
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
  let word = "λόγος"
  let off = shapeText(sfB, word, offFeatures())
  let on = shapeText(sfB, word,
    @[globalFeature(tagFromStr("kern"), 1)])
  let baseB = 750.0
  c.label(90, 540, "the full word, kern off (gray) vs on (ink)", 20,
    Ink, "start", "bold")
  var totalOff = 0i32
  var totalOn = 0i32
  for i in 0 ..< off.len:
    totalOff += off.pos[i].xAdvance
    totalOn += on.pos[i].xAdvance
  let penB = 640.0 - float64(totalOff) / 2.0
  var pOff = penB
  for i in 0 ..< off.len:
    let d = glyphPath(sfB, off.info[i].glyphId, pOff, baseB, kB)
    if d != "":
      c.path(d, "#f4f5fa", "#9aa3b2", 2.5)
    pOff += float64(off.pos[i].xAdvance)
  var pOn = penB
  for i in 0 ..< on.len:
    let gidB = on.info[i].glyphId
    let d = glyphPath(sfB, gidB, pOn, baseB, kB)
    if d != "":
      c.path(d, "#eef1ff", Ink, 3.0)
    c.circle(pOn, baseB, 5, Origin, "#ffffff", 2.0)
    pOn += float64(on.pos[i].xAdvance)
  c.line(penB - 20, baseB, penB + float64(totalOff) + 20, baseB,
    BaseLine, 2.0)
  c.label(penB - 20, baseB + 36, fmt"off total {totalOff}", 14, Faint)
  c.label(penB - 20, baseB + 58, fmt"on total {totalOn}", 14, Advance)
  c.label(penB - 20, baseB + 80, fmt"kern delta {totalOn - totalOff}",
    14, BaseLine, "start", "bold")
  c.label(penB + float64(totalOn) + 30, baseB - 40,
    "final sigma keeps cluster 8", 14, Cluster)
  c.footer("The lamda pair tightens and word-final sigma takes its final form; clusters stay in logical order.")
  let p = outPath("ex11_greek")
  c.save(p)
  echo "wrote " & p

when isMainModule:
  main()
