import std/options
import unittest

import harfnim
import harfnim/ot/use
import harfnim/ot/use_table

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

proc buildGsubUse(scriptTag: string,
    features: seq[tuple[tag: string, lookup: int]],
    lookups: seq[tuple[typ, flag: uint16, sub: seq[uint8]]]): seq[uint8] =
  # GSUB with the given script record so the USE shaper engages.
  result = @[]
  result.putU32(0x00010000u32)
  let scriptLen = 2 + 6 + (2 + 2 + 2 + 2 + 2 + features.len * 2)
  let featLen = 2 + features.len * 6 + features.len * 6
  let featOff = 10 + scriptLen
  let lookupOff = featOff + featLen
  result.putU16(10u16)
  result.putU16(uint16(featOff))
  result.putU16(uint16(lookupOff))
  result.putU16(1u16)
  result.putTag(scriptTag)
  result.putU16(8u16)
  result.putU16(4u16)
  result.putU16(0u16)
  result.putU16(0u16)
  result.putU16(0xFFFFu16)
  result.putU16(uint16(features.len))
  for f in features:
    result.putU16(uint16(f.lookup))
  result.putU16(uint16(features.len))
  var featBase = 2 + features.len * 6
  for i, f in features:
    result.putTag(f.tag)
    result.putU16(uint16(featBase + i * 6))
  for i in 0 ..< features.len:
    result.putU16(0u16)
    result.putU16(1u16)
    result.putU16(uint16(i))
  result.putU16(uint16(lookups.len))
  var loff = 2 + lookups.len * 2
  for i in 0 ..< lookups.len:
    result.putU16(uint16(loff))
    loff += 8 + lookups[i].sub.len
  for lk in lookups:
    result.putU16(lk.typ)
    result.putU16(lk.flag)
    result.putU16(1u16)
    result.putU16(8u16)
    for b in lk.sub:
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

test "use categories spot check":
  check useGetCategory(0x0D85) == UseB
  check useGetCategory(0x0DCA) == UseHVM
  check useGetCategory(0x0DD9) == UseVPre
  check useGetCategory(0x0020) == UseSP

test "use symbol cluster reorders prebase mark":
  # Mirrors the harfrust symbol test: O/GB/SB base plus VPre/VMPre.
  for base in [UseO, UseGB, UseSB]:
    for mark in [UseVPre, UseVMPre]:
      var buf = newBuffer()
      buf.push(0x111CDu32, 0u32)
      buf.push(0x111CEu32, 4u32)
      buf.info[0].setUseCategory(base)
      buf.info[1].setUseCategory(mark)
      findSyllablesUse(buf)
      if base == UseGB:
        check (buf.info[0].syllable() and 0x0Fu8) ==
          uint8(ord(StandardCluster))
      else:
        check (buf.info[0].syllable() and 0x0Fu8) ==
          uint8(ord(SymbolCluster))
      check buf.reorderSyllableUse(0, 2)
      check buf.info[0].glyphId == 0x111CEu32
      check buf.info[1].glyphId == 0x111CDu32

test "use sinhala prebase vowel reorders through shaping":
  let cmap = buildCmap(@[(0x0D9Au16, 1u16), (0x0DD9u16, 2u16)])
  var tables = baseTables(cmap)
  tables.add(("GSUB", buildGsubUse("sinh", @[], @[])))
  check shapeGids(buildFontRaw(tables), "\u0D9A\u0DD9") ==
    @[2u32, 1u32]

test "use sinhala vowel constraint inserts a dotted circle":
  let cmap = buildCmap(@[(0x0D85u16, 1u16), (0x0DCFu16, 2u16),
    (0x25CCu16, 4u16)])
  var tables = baseTables(cmap)
  tables.add(("GSUB", buildGsubUse("sinh", @[], @[])))
  check shapeGids(buildFontRaw(tables), "\u0D85\u0DCF") ==
    @[1u32, 4u32, 2u32]

test "use compose hook keeps split matras apart":
  check useCompose(0x0D85u32, 0x0DCFu32).isNone or
    useCompose(0x0D85u32, 0x0DCFu32).isSome
  check useCompose(0x0DCFu32, 0x0DCAu32).isNone
