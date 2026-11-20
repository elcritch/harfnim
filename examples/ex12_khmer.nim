## Poster 12: Khmer, the vowel leaps ahead and Coeng dives below.
##
## Shapes "Khmae" (KHA, COENG, MO, VS AE, RO) with Khmer Sangam MN.
## The top strip is logical order with codepoint and byte labels; the
## bottom strip is shaped visual order. The left vowel moves before
## the base, COENG plus MO fuse into a zero advance below-base form,
## and final RO keeps its byte cluster.

import std/strformat
import std/strutils

import ./support
import harfnim

const
  CanvasW = 1280
  CanvasH = 920
  SizePx = 300
  Text = "\u1781\u17d2\u1798\u17c2\u179a"
  Targets = [1, 2, 2, 0, 3]
    ## Shaped glyph index per logical codepoint box.

proc main() =
  let path = findFontOrQuit([
    "/System/Library/Fonts/Supplemental/Khmer Sangam MN.ttf",
    "/System/Library/Fonts/Supplemental/Khmer MN.ttc"])
  let sf = loadShaper(path, SizePx)
  let k = pixelScale(sf, SizePx)
  let b = shapeText(sf, Text, defaultFeatures())
  doAssert b.len == 4
  doAssert b.info[0].cluster == 0u32
  doAssert b.info[3].cluster == 12u32
  var c = newCanvas(CanvasW, CanvasH)
  c.header("Khmer: the vowel leaps ahead, Coeng dives below",
    fmt"Khmer Sangam MN at {SizePx}px shapes five codepoints into {b.len} glyphs: script={scriptName(b)} direction={dirName(b.direction)}")
  var offs: seq[int] = @[]
  var cps: seq[uint32] = @[]
  var p = 0
  while p < Text.len:
    offs.add(p)
    let b0 = uint8(Text[p])
    if b0 < 0x80u8:
      cps.add(uint32(b0))
      inc p
    elif (b0 and 0xE0u8) == 0xC0u8:
      cps.add((uint32(b0 and 0x1Fu8) shl 6) or
        uint32(uint8(Text[p + 1]) and 0x3Fu8))
      p += 2
    elif (b0 and 0xF0u8) == 0xE0u8:
      cps.add((uint32(b0 and 0x0Fu8) shl 12) or
        (uint32(uint8(Text[p + 1]) and 0x3Fu8) shl 6) or
        uint32(uint8(Text[p + 2]) and 0x3Fu8))
      p += 3
    else:
      cps.add((uint32(b0 and 0x07u8) shl 18) or
        (uint32(uint8(Text[p + 1]) and 0x3Fu8) shl 12) or
        (uint32(uint8(Text[p + 2]) and 0x3Fu8) shl 6) or
        uint32(uint8(Text[p + 3]) and 0x3Fu8))
      p += 4
  doAssert offs.len == 5
  let boxW = 110.0
  let topX = 640.0 - float64(offs.len) * (boxW + 10.0) / 2.0
  let topY = 140.0
  c.label(90, 122, "logical order (codepoints, byte offsets)", 16, Ink,
    "start", "bold")
  var centers: seq[float64] = @[]
  for n, o in offs:
    let x = topX + float64(n) * (boxW + 10.0)
    c.rect(x, topY, boxW, 70, "#ffffff", Faint, 1.5)
    c.label(x + boxW / 2, topY + 30, "U+" & cps[n].toHex(4), 15, Ink,
      "middle")
    c.label(x + boxW / 2, topY + 52, fmt"byte {o}", 12, Faint, "middle")
    centers.add(x + boxW / 2)
  let baseY = 620.0
  c.label(90, 300, "shaped visual order (vowel, base, fused below, Ro)",
    16, Ink, "start", "bold")
  var total = 0i32
  for g in 0 ..< b.len:
    total += b.pos[g].xAdvance
  var pen = 640.0 - float64(total) / 2.0
  c.line(90, baseY, 1190, baseY, BaseLine, 2.0)
  var gcenters: seq[float64] = @[]
  var tags: seq[tuple[x: float64, gid: uint32, cluster: uint32,
    zero: bool]] = @[]
  for g in 0 ..< b.len:
    let gid = b.info[g].glyphId
    let adv = float64(b.pos[g].xAdvance)
    gcenters.add(pen + adv / 2)
    tags.add((pen + adv / 2, gid, b.info[g].cluster, adv == 0.0))
    if adv == 0.0:
      let d = glyphPath(sf, gid, pen, baseY, k)
      if d != "":
        c.path(d, "#fff3e6", Cluster, 3.0)
      c.circle(pen, baseY, 4, Cluster, "#ffffff", 2.0)
      c.label(pen + 55, baseY + 62, "adv 0", 14, Cluster, "middle")
    else:
      c.drawExtentsBox(sf, gid, pen, baseY)
      let d = glyphPath(sf, gid, pen, baseY, k)
      if d != "":
        c.path(d, "#eef1ff", Ink, 3.0)
      c.circle(pen, baseY, 5, Origin, "#ffffff", 2.0)
      c.arrow(pen, baseY + 66, pen + adv, baseY + 66, Advance, 2.5,
        "arrGreen")
    pen += adv
  for t in tags:
    if not t.zero:
      c.label(t.x, baseY + 92, fmt"gid {t.gid}", 13, Ink, "middle")
      c.label(t.x, baseY + 112, fmt"cluster {t.cluster}", 13,
        Cluster, "middle")
  for n in 0 ..< offs.len:
    c.line(centers[n], topY + 70, gcenters[Targets[n]], baseY - 200,
      Cluster, 1.5)
  c.label(90, 800,
    fmt"AE (gid {b.info[0].glyphId}) jumps before KHA while COENG and MO merge into gid {b.info[2].glyphId} below the baseline; RO never moves.",
    14, Ink)
  c.label(90, 822,
    "Clusters 0 and 12 survive the reorder, so hit testing maps back to logical text.",
    14, Ink)
  c.footer("The Khmer shaper reorders the left vowel first, then fuses Coeng pairs with pref and below-base forms.")
  let f = outPath("ex12_khmer")
  c.save(f)
  echo "wrote " & f

when isMainModule:
  main()
