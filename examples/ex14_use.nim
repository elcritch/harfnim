## Poster 14: USE, one Sinhala syllable in two ligatures.
##
## Shapes SHA plus VIRAMA plus RA plus II with Sinhala Sangam MN.
## The top strip is logical order with codepoint and byte labels; the
## bottom strip is shaped visual order. The abvs feature fuses the
## consonant cluster, then the pair takes its vowel, all inside one
## USE syllable with clusters 0 and 6.

import std/strformat
import std/strutils

import ./support
import harfnim

const
  CanvasW = 1280
  CanvasH = 880
  SizePx = 320
  Text = "\u0dc1\u0dca\u0dbb\u0dd3"
  Targets = [0, 0, 1, 1]
    ## Shaped glyph index per logical codepoint box.

proc main() =
  let path = findFontOrQuit([
    "/System/Library/Fonts/Supplemental/Sinhala Sangam MN.ttc",
    "/System/Library/Fonts/Supplemental/Sinhala MN.ttc"])
  let sf = loadShaper(path, SizePx)
  let k = pixelScale(sf, SizePx)
  let b = shapeText(sf, Text, defaultFeatures())
  doAssert b.len == 2
  doAssert b.info[0].cluster == 0u32
  doAssert b.info[1].cluster == 6u32
  var c = newCanvas(CanvasW, CanvasH)
  c.header("USE: one Sinhala syllable in two ligatures",
    fmt"Sinhala Sangam MN at {SizePx}px shapes four codepoints into {b.len} glyphs: script={scriptName(b)} direction={dirName(b.direction)}")
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
  doAssert offs.len == 4
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
  let baseY = 590.0
  c.label(90, 300, "shaped visual order (cluster fused, vowel joined)",
    16, Ink, "start", "bold")
  var total = 0i32
  for g in 0 ..< b.len:
    total += b.pos[g].xAdvance
  var pen = 640.0 - float64(total) / 2.0
  c.line(90, baseY, 1190, baseY, BaseLine, 2.0)
  var gcenters: seq[float64] = @[]
  for g in 0 ..< b.len:
    let gid = b.info[g].glyphId
    let adv = float64(b.pos[g].xAdvance)
    gcenters.add(pen + adv / 2)
    if adv == 0.0:
      let d = glyphPath(sf, gid, pen, baseY, k)
      if d != "":
        c.path(d, "#fff3e6", Cluster, 3.0)
      c.circle(pen, baseY, 4, Cluster, "#ffffff", 2.0)
      c.label(pen, baseY + 62, "adv 0", 14, Cluster, "middle")
    else:
      c.drawExtentsBox(sf, gid, pen, baseY)
      let d = glyphPath(sf, gid, pen, baseY, k)
      if d != "":
        c.path(d, "#eef1ff", Ink, 3.0)
      c.circle(pen, baseY, 5, Origin, "#ffffff", 2.0)
      c.arrow(pen, baseY + 66, pen + adv, baseY + 66, Advance, 2.5,
        "arrGreen")
    c.label(pen + adv / 2, baseY + 92, fmt"gid {gid}", 13, Ink,
      "middle")
    c.label(pen + adv / 2, baseY + 112,
      fmt"cluster {b.info[g].cluster}", 13, Cluster, "middle")
    pen += adv
  for n in 0 ..< offs.len:
    c.line(centers[n], topY + 70, gcenters[Targets[n]], baseY - 200,
      Cluster, 1.5)
  c.label(90, 762,
    "SHA plus VIRAMA fuse and RA plus II fuse: two ligatures, one syllable.",
    14, Ink)
  c.label(90, 784,
    "No reorder here: the USE win is syllable aware ligation with clusters 0 and 6.",
    14, Ink)
  c.footer("The USE shaper keeps the whole cluster in one syllable so abvs applies across it.")
  let f = outPath("ex14_use")
  c.save(f)
  echo "wrote " & f

when isMainModule:
  main()
