## Poster 3: ligature, GSUB merges two glyphs into one.
##
## System fonts on this machine carry no fi ligature, so this poster
## builds a tiny synthetic font in memory: blocky f, i, and fi glyphs,
## a cmap for f and i, and a GSUB ligature lookup mapping f + i to the
## fi glyph. Shaping "fi" with liga off and on shows the cluster merge.

import std/strformat

import ./support
import harfnim

const
  CanvasW = 1280
  CanvasH = 780
  SizePx = 440
  Upem = 1000

proc putU16(s: var seq[uint8]; v: uint16) =
  s.add(uint8(v shr 8))
  s.add(uint8(v and 0xFFu16))

proc putI16(s: var seq[uint8]; v: int16) =
  s.putU16(cast[uint16](v))

proc putU32(s: var seq[uint8]; v: uint32) =
  s.putU16(uint16(v shr 16))
  s.putU16(uint16(v and 0xFFFFu32))

proc putTag(s: var seq[uint8]; t: string) =
  for ch in t:
    s.add(uint8(ch))

proc pad4(s: var seq[uint8]) =
  while s.len mod 4 != 0:
    s.add(0u8)

proc buildCmapFI(): seq[uint8] =
  result = @[]
  result.putU16(0u16)
  result.putU16(1u16)
  result.putU16(3u16)
  result.putU16(1u16)
  result.putU32(12u32)
  result.putU16(4u16)
  result.putU16(40u16)
  result.putU16(0u16)
  result.putU16(6u16)
  result.putU16(4u16)
  result.putU16(1u16)
  result.putU16(2u16)
  result.putU16(0x66u16)
  result.putU16(0x69u16)
  result.putU16(0xFFFFu16)
  result.putU16(0u16)
  result.putU16(0x66u16)
  result.putU16(0x69u16)
  result.putU16(0xFFFFu16)
  result.putI16(-101i16)
  result.putI16(-103i16)
  result.putI16(1i16)
  result.putU16(0u16)
  result.putU16(0u16)
  result.putU16(0u16)

proc buildGsubLiga(): seq[uint8] =
  result = @[]
  result.putU32(0x00010000u32)
  result.putU16(10u16)
  result.putU16(30u16)
  result.putU16(44u16)
  result.putU16(1u16)
  result.putTag("latn")
  result.putU16(8u16)
  result.putU16(4u16)
  result.putU16(0u16)
  result.putU16(0u16)
  result.putU16(0xFFFFu16)
  result.putU16(1u16)
  result.putU16(0u16)
  result.putU16(1u16)
  result.putTag("liga")
  result.putU16(8u16)
  result.putU16(0u16)
  result.putU16(1u16)
  result.putU16(0u16)
  result.putU16(1u16)
  result.putU16(4u16)
  result.putU16(4u16)
  result.putU16(0u16)
  result.putU16(1u16)
  result.putU16(8u16)
  result.putU16(1u16)
  result.putU16(8u16)
  result.putU16(1u16)
  result.putU16(14u16)
  result.putU16(1u16)
  result.putU16(1u16)
  result.putU16(1u16)
  result.putU16(1u16)
  result.putU16(4u16)
  result.putU16(20u16)
  result.putU16(2u16)
  result.putU16(2u16)
  doAssert result.len == 80

proc rectPts(x0, y0, x1, y1: int32): seq[tuple[x, y: int32, on: bool]] =
  @[(x0, y0, true), (x1, y0, true), (x1, y1, true), (x0, y1, true)]

proc simpleGlyph(pts: seq[tuple[x, y: int32, on: bool]];
    ends: seq[int]): seq[uint8] =
  result = @[]
  result.putI16(int16(ends.len))
  var x0 = pts[0].x
  var y0 = pts[0].y
  var x1 = x0
  var y1 = y0
  for p in pts:
    x0 = min(x0, p.x)
    y0 = min(y0, p.y)
    x1 = max(x1, p.x)
    y1 = max(y1, p.y)
  result.putI16(int16(x0))
  result.putI16(int16(y0))
  result.putI16(int16(x1))
  result.putI16(int16(y1))
  for e in ends:
    result.putU16(uint16(e))
  result.putU16(0u16)
  for p in pts:
    result.add(if p.on: 1u8 else: 0u8)
  var px = 0i32
  for p in pts:
    result.putI16(int16(p.x - px))
    px = p.x
  var py = 0i32
  for p in pts:
    result.putI16(int16(p.y - py))
    py = p.y
  while result.len mod 2 != 0:
    result.add(0u8)

proc buildLigaDemoFont(): seq[uint8] =
  let fPts = rectPts(100, 0, 220, 700) & rectPts(100, 480, 430, 560)
  let iPts = rectPts(100, 0, 220, 470) & rectPts(100, 560, 220, 680)
  let fiPts = rectPts(100, 0, 220, 700) & rectPts(100, 480, 430, 560) &
    rectPts(220, 600, 470, 660) & rectPts(470, 0, 590, 470) &
    rectPts(470, 560, 590, 680)
  let fG = simpleGlyph(fPts, @[3, 7])
  let iG = simpleGlyph(iPts, @[3, 7])
  let fiG = simpleGlyph(fiPts, @[3, 7, 11, 15, 19])
  var glyf: seq[uint8] = @[]
  var offs: seq[int] = @[0, 0]
  glyf.add(fG)
  offs.add(glyf.len)
  glyf.add(iG)
  offs.add(glyf.len)
  for _ in 3 .. 19:
    offs.add(glyf.len)
  glyf.add(fiG)
  offs.add(glyf.len)
  doAssert offs.len == 22
  var loca: seq[uint8] = @[]
  for o in offs:
    loca.putU16(uint16(o div 2))
  var head = newSeq[uint8]()
  head.putU32(0x00010000u32)
  head.putU32(0u32)
  head.putU32(0u32)
  head.putU32(0x5F0F3CF5u32)
  head.putU16(0u16)
  head.putU16(uint16(Upem))
  for _ in 0 ..< 4:
    head.putU32(0u32)
  for _ in 0 ..< 4:
    head.putI16(0i16)
  head.putU16(0u16)
  head.putU16(0u16)
  head.putI16(0i16)
  head.putI16(0i16)
  head.putU16(0u16)
  var hhea = newSeq[uint8]()
  hhea.putU32(0x00010000u32)
  hhea.putI16(800i16)
  hhea.putI16(-200i16)
  hhea.putI16(0i16)
  hhea.putU16(600u16)
  for _ in 0 ..< 11:
    hhea.putI16(0i16)
  hhea.putU16(21u16)
  var maxp = newSeq[uint8]()
  maxp.putU32(0x00005000u32)
  maxp.putU16(21u16)
  var hmtx = newSeq[uint8]()
  for gid in 0 ..< 21:
    let adv =
      case gid
      of 1: 500u16
      of 2: 320u16
      of 20: 800u16
      else: 600u16
    hmtx.putU16(adv)
    hmtx.putI16(0i16)
  let cmap = buildCmapFI()
  let gsub = buildGsubLiga()
  var tables = @[
    ("head", head), ("hhea", hhea), ("maxp", maxp), ("hmtx", hmtx),
    ("cmap", cmap), ("loca", loca), ("glyf", glyf), ("GSUB", gsub),
  ]
  result = @[]
  result.putU32(0x00010000u32)
  result.putU16(uint16(tables.len))
  result.putU16(128u16)
  result.putU16(3u16)
  result.putU16(0u16)
  var off = 12 + tables.len * 16
  for (name, data) in tables:
    for ch in name:
      result.add(uint8(ch))
    result.putU32(0u32)
    result.putU32(uint32(off))
    var padded = (data.len + 3) and not 3
    result.putU32(uint32(padded))
    off += padded
  for (_, data) in tables:
    result.add(data)
    result.pad4()

proc drawRun(c: var Canvas; sf: ShaperFont; b: Buffer; penX, baseY,
    k: float64; title: string) =
  c.label(penX, baseY - 380, title, 20, Ink, "start", "bold")
  c.line(penX - 20, baseY, penX + 460, baseY, BaseLine, 2.0)
  var pen = penX
  for i in 0 ..< b.len:
    let gid = b.info[i].glyphId
    c.drawExtentsBox(sf, gid, pen, baseY)
    c.drawGlyphBox(sf, gid, pen, baseY, k)
    c.circle(pen, baseY, 5, Origin, "#ffffff", 2.0)
    let adv = float64(b.pos[i].xAdvance)
    c.arrow(pen, baseY + 52, pen + adv, baseY + 52, Advance, 2.5,
      "arrGreen")
    c.label(pen + adv / 2, baseY + 78, fmt"adv {b.pos[i].xAdvance}",
      14, Advance, "middle")
    c.label(pen + adv / 2, baseY - 410, fmt"cluster {b.info[i].cluster}",
      14, Cluster, "middle")
    c.label(pen + adv / 2, baseY - 434, fmt"gid {gid}", 13, Ink,
      "middle")
    pen += adv

proc main() =
  var sf = newShaperFont(parseFont(buildLigaDemoFont()))
  sf.setScale(SizePx)
  let k = pixelScale(sf, SizePx)
  let off = shapeText(sf, "fi", offFeatures())
  let on = shapeText(sf, "fi", @[globalFeature(tagFromStr("liga"), 1)])
  doAssert off.len == 2
  doAssert on.len == 1
  doAssert on.info[0].cluster == 0u32
  var c = newCanvas(CanvasW, CanvasH)
  c.header("Ligature: GSUB merges f + i into fi",
    "Synthetic demo font at 440px: blocky f, i, and fi glyphs with a type 4 ligature lookup.")
  drawRun(c, sf, off, 90, 600, k, "liga off: two glyphs")
  c.arrow(560, 420, 660, 420, Cluster, 2.5, "arrCluster")
  c.label(610, 400, "liga", 14, Cluster, "middle", "bold")
  drawRun(c, sf, on, 740, 600, k, "liga on: one glyph")
  c.label(90, 700,
    "Lookup type 4 (ligature set): coverage {f} + components {i} -> gid 20.",
    14, Ink)
  c.label(90, 724,
    "The result carries cluster 0 (minimum of 0 and 1) and the ligature bit.",
    14, Ink)
  c.footer("Substitution happens before positioning: the fi glyph gets its own advance (800 units) and extents.")
  let p = outPath("ex03_ligature")
  c.save(p)
  echo "wrote " & p

when isMainModule:
  main()
