import std/options
import unittest

import harfnim
import harfnim/ot/gsub
import harfnim/ot/hebrew
import harfnim/ot/shaper

proc putU16(s: var seq[uint8], v: uint16) =
  s.add(uint8(v shr 8))
  s.add(uint8(v and 0xFFu16))

proc putI16(s: var seq[uint8], v: int16) =
  s.putU16(cast[uint16](v))

proc putU32(s: var seq[uint8], v: uint32) =
  s.putU16(uint16(v shr 16))
  s.putU16(uint16(v and 0xFFFFu32))

proc putTag(s: var seq[uint8], t: string) =
  for c in t:
    s.add(uint8(c))

proc pad4(s: var seq[uint8]) =
  while s.len mod 4 != 0:
    s.add(0u8)

proc buildCmap(pairs: seq[tuple[cp, gid: uint16]]): seq[uint8] =
  # Format 4 with one segment per pair (plus sentinel), sorted by cp.
  var sorted = pairs
  for i in 1 ..< sorted.len:
    let cur = sorted[i]
    var j = i
    while j > 0 and sorted[j - 1].cp > cur.cp:
      sorted[j] = sorted[j - 1]
      dec j
    sorted[j] = cur
  result = @[]
  result.putU16(0u16)
  result.putU16(1u16)
  result.putU16(3u16)
  result.putU16(1u16)
  result.putU32(12u32)
  result.putU16(4u16)
  let segCount = sorted.len + 1
  let segX2 = uint16(segCount * 2)
  let length = uint16(16 + segCount * 8)
  result.putU16(length)
  result.putU16(0u16)
  result.putU16(segX2)
  result.putU16(4u16)
  result.putU16(1u16)
  result.putU16(0u16)
  for pr in sorted:
    result.putU16(pr.cp)
  result.putU16(0xFFFFu16)
  result.putU16(0u16)
  for pr in sorted:
    result.putU16(pr.cp)
  result.putU16(0xFFFFu16)
  for pr in sorted:
    result.putU16(uint16((int(pr.gid) - int(pr.cp)) and 0xFFFF))
  result.putI16(1i16)
  for _ in sorted:
    result.putU16(0u16)
  result.putU16(0u16)

proc baseTables(cmap: seq[uint8]): seq[tuple[name: string, data: seq[uint8]]] =
  var head = newSeq[uint8]()
  head.putU32(0x00010000u32)
  head.putU32(0u32)
  head.putU32(0u32)
  head.putU32(0x5F0F3CF5u32)
  head.putU16(0u16)
  head.putU16(1000u16)
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
  hhea.putU16(2u16)
  var maxp = newSeq[uint8]()
  maxp.putU32(0x00005000u32)
  maxp.putU16(12u16)
  var hmtx = newSeq[uint8]()
  hmtx.putU16(500u16)
  hmtx.putI16(0i16)
  hmtx.putU16(600u16)
  hmtx.putI16(10i16)
  var loca = @[0u8, 0u8, 0u8, 0u8]
  @[("head", head), ("hhea", hhea), ("maxp", maxp), ("hmtx", hmtx),
    ("cmap", cmap), ("loca", loca)]

proc buildFontRaw(tables: seq[tuple[name: string, data: seq[uint8]]]): seq[
    uint8] =
  result = @[]
  result.putU32(0x00010000u32)
  result.putU16(uint16(tables.len))
  result.putU16(64u16)
  result.putU16(2u16)
  result.putU16(48u16)
  var off = 12 + tables.len * 16
  for (name, data) in tables:
    for c in name:
      result.add(uint8(c))
    result.putU32(0u32)
    result.putU32(uint32(off))
    var padded = (data.len + 3) and not 3
    result.putU32(uint32(padded))
    off += padded
  for (_, data) in tables:
    result.add(data)
    result.pad4()

proc putU16At(s: var seq[uint8], pos: int, v: uint16) =
  doAssert pos >= 0 and pos + 2 <= s.len
  s[pos] = uint8(v shr 8)
  s[pos + 1] = uint8(v and 0xFFu16)

proc covBytes(glyphs: seq[uint16]): seq[uint8] =
  result = @[]
  result.putU16(1u16)
  result.putU16(uint16(glyphs.len))
  for g in glyphs:
    result.putU16(g)

proc emptySinglePos(): seq[uint8] =
  # SinglePos format 1, valueFormat 0: parses but adjusts nothing.
  result = @[]
  result.putU16(1u16)
  let covPos = result.len
  result.putU16(0u16)
  result.putU16(0u16)
  let covOff = result.len
  for b in covBytes(@[1u16]):
    result.add(b)
  result.putU16At(covPos, uint16(covOff))

proc buildGposMarkHebr(): seq[uint8] =
  # Minimal GPOS: hebr script with a `mark` feature pointing at one
  # empty SinglePos lookup. Enough for the has_gpos_mark gate.
  let sub = emptySinglePos()
  result = @[]
  result.putU32(0x00010000u32)
  result.putU16(10u16)
  result.putU16(30u16)
  result.putU16(44u16)
  result.putU16(1u16)
  result.putTag("hebr")
  result.putU16(8u16)
  result.putU16(4u16)
  result.putU16(0u16)
  result.putU16(0u16)
  result.putU16(0xFFFFu16)
  result.putU16(1u16)
  result.putU16(0u16)
  result.putU16(1u16)
  result.putTag("mark")
  result.putU16(8u16)
  result.putU16(0u16)
  result.putU16(1u16)
  result.putU16(0u16)
  result.putU16(1u16)
  result.putU16(4u16)
  result.putU16(1u16)
  result.putU16(0u16)
  result.putU16(1u16)
  result.putU16(8u16)
  for b in sub:
    result.add(b)

proc shapeGids(fontBytes: seq[uint8], text: string): seq[uint32] =
  let f = parseFont(fontBytes)
  var sf = newShaperFont(f)
  var b = newBuffer()
  b.pushStr(text)
  sf.shape(b, @[])
  result = @[]
  for i in 0 ..< b.len:
    result.add(b.info[i].glyphId)

proc shapeRunDir(fontBytes: seq[uint8], text: string,
    d: Direction): Buffer =
  # Shapes one bidi run with an explicit direction, the ex05 pattern.
  let f = parseFont(fontBytes)
  var sf = newShaperFont(f)
  result = newBuffer()
  result.pushStr(text)
  result.setDirection(d)
  sf.shape(result, @[])

proc visualGlyphs(fontBytes: seq[uint8],
    text: string): seq[tuple[gid, cluster: uint32]] =
  # Shapes each visualRuns run with its own direction and concatenates
  # the runs in visual order, mapping run-relative clusters back to
  # paragraph bytes.
  let vt = visualRuns(text, bdAuto)
  result = @[]
  for run in vt.runs:
    var srcMin = text.len
    var srcMax = -1
    for j in run.first ..< run.last:
      if j < vt.map.len - 1:
        srcMin = min(srcMin, vt.map[j])
        srcMax = max(srcMax, vt.map[j])
    let b = shapeRunDir(fontBytes, text[srcMin .. srcMax], run.dir)
    for i in 0 ..< b.len:
      result.add((gid: b.info[i].glyphId,
        cluster: b.info[i].cluster + uint32(srcMin)))

test "shaper routing matches harfrust categorize":
  check categorizeShaper(some(Hebrew), true) == skHebrew
  check categorizeShaper(some(Arabic), true) == skArabic
  check categorizeShaper(some(Syriac), true) == skArabic
  check categorizeShaper(some(Syriac), false) == skDefault
  check categorizeShaper(some(Thai), true) == skThai
  check categorizeShaper(some(Lao), true) == skThai
  check categorizeShaper(some(Hangul), true) == skHangul
  check categorizeShaper(some(Devanagari), true) == skDefault
  check categorizeShaper(some(Devanagari), true,
    some(tagFromStr("DFLT"))) == skDefault
  check categorizeShaper(some(Devanagari), true,
    some(tagFromStr("latn"))) == skDefault
  check categorizeShaper(some(Devanagari), true,
    some(tagFromStr("deva"))) == skIndic
  check categorizeShaper(some(Devanagari), true,
    some(tagFromStr("dev3"))) == skUse
  check categorizeShaper(some(Khmer), true) == skKhmer
  check categorizeShaper(some(Myanmar), true,
    some(tagFromStr("mymr"))) == skDefault
  check categorizeShaper(some(Myanmar), true,
    some(tagFromStr("mym2"))) == skMyanmar
  check categorizeShaper(some(Tibetan), true,
    some(tagFromStr("tibt"))) == skUse
  check categorizeShaper(some(Tibetan), true) == skDefault
  check categorizeShaper(some(Latin), true) == skDefault
  check categorizeShaper(none(Script), true) == skDefault

test "gsub script resolution prefers exact over DFLT":
  let gd = GsubData(scripts: @[
    (tag: tagFromStr("DFLT").toU32(), script: ScriptTable()),
    (tag: tagFromStr("hebr").toU32(), script: ScriptTable()),
  ], features: @[], lookups: @[])
  check gsubScriptTagFor(gd, tagFromStr("hebr")) ==
    some(tagFromStr("hebr"))
  check gsubScriptTagFor(gd, tagFromStr("latn")) ==
    some(tagFromStr("DFLT"))
  check gsubScriptTagFor(GsubData(scripts: @[], features: @[],
    lookups: @[]), tagFromStr("hebr")).isNone

test "hebrew composes yod + hiriq without GPOS mark":
  let cmap = buildCmap(@[(0x05D9u16, 1u16), (0x05B4u16, 2u16),
    (0xFB1Du16, 3u16)])
  let fontBytes = buildFontRaw(baseTables(cmap))
  # RTL output is visual order; single glyph either way.
  check shapeGids(fontBytes, "\u05D9\u05B4") == @[3u32]

test "hebrew composes bet + dagesh without GPOS mark":
  let cmap = buildCmap(@[(0x05D1u16, 1u16), (0x05BCu16, 2u16),
    (0xFB31u16, 3u16)])
  let fontBytes = buildFontRaw(baseTables(cmap))
  check shapeGids(fontBytes, "\u05D1\u05BC") == @[3u32]

test "hebrew keeps yod + hiriq split with GPOS mark":
  let cmap = buildCmap(@[(0x05D9u16, 1u16), (0x05B4u16, 2u16),
    (0xFB1Du16, 3u16)])
  var tables = baseTables(cmap)
  tables.add(("GPOS", buildGposMarkHebr()))
  let fontBytes = buildFontRaw(tables)
  # Visual order: hiriq glyph first, then yod.
  check shapeGids(fontBytes, "\u05D9\u05B4") == @[2u32, 1u32]

test "hebrew reorders patah + sheva + meteg":
  # BET base avoids ALEF+PATAH presentation composition.
  let cmap = buildCmap(@[(0x05D1u16, 1u16), (0x05B7u16, 2u16),
    (0x05B0u16, 3u16), (0x05BDu16, 4u16)])
  let fontBytes = buildFontRaw(baseTables(cmap))
  # Logical [BET PATAH SHEVA METEG] reorders the last two marks;
  # RTL output is visual (reversed) order.
  check shapeGids(fontBytes, "\u05D1\u05B7\u05B0\u05BD") ==
    @[3u32, 4u32, 2u32, 1u32]

test "hebrew leaves other mark orders alone":
  let cmap = buildCmap(@[(0x05D1u16, 1u16), (0x05B4u16, 2u16),
    (0x05B0u16, 3u16), (0x05BDu16, 4u16)])
  let fontBytes = buildFontRaw(baseTables(cmap))
  # Sheva + hiriq + meteg: c0 is not patah/qamats, so no triple
  # match and the order survives (visual reversed).
  check shapeGids(fontBytes, "\u05D1\u05B0\u05B4\u05BD") ==
    @[4u32, 2u32, 3u32, 1u32]
  # Two-mark run: nothing to swap (CCC sort orders sheva first).
  check shapeGids(fontBytes, "\u05D1\u05B4\u05B0") == @[2u32, 3u32, 1u32]

test "latin composition is unaffected by the hebrew path":
  let cmap = buildCmap(@[(0x0065u16, 1u16), (0x0301u16, 2u16),
    (0x00E9u16, 3u16)])
  let fontBytes = buildFontRaw(baseTables(cmap))
  check shapeGids(fontBytes, "\u0065\u0301") == @[3u32]

test "hebrew latin mixed runs shape with per-run direction":
  # a(10) c(11); BET(20) PATAH(21) SHEVA(22) METEG(23).
  let cmap = buildCmap(@[(0x0061u16, 10u16), (0x0063u16, 11u16),
    (0x05D1u16, 20u16), (0x05B7u16, 21u16), (0x05B0u16, 22u16),
    (0x05BDu16, 23u16)])
  let fontBytes = buildFontRaw(baseTables(cmap))
  # Bytes: a@0 BET@1 PATAH@3 SHEVA@5 METEG@7 c@9.
  let text = "a\u05D1\u05B7\u05B0\u05BDc"
  let vt = visualRuns(text, bdAuto)
  check vt.runs.len == 3
  check vt.runs[0].level == 0
  check vt.runs[1].level == 1
  check vt.runs[2].level == 0
  check vt.runs[0].dir == dirLeftToRight
  check vt.runs[1].dir == dirRightToLeft
  check vt.runs[2].dir == dirLeftToRight
  # The RTL run reorders to SHEVA METEG PATAH BET (visual order)
  # while the Latin runs stay in logical order. Grapheme clustering
  # merges the base plus marks into the run start byte, so every
  # Hebrew glyph maps back to paragraph byte 1.
  check visualGlyphs(fontBytes, text) == @[(gid: 10u32, cluster: 0u32),
    (gid: 22u32, cluster: 1u32), (gid: 23u32, cluster: 1u32),
    (gid: 21u32, cluster: 1u32), (gid: 20u32, cluster: 1u32),
    (gid: 11u32, cluster: 9u32)]
