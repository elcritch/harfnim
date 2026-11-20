## Metrics variations: MVAR parsing, deltas, and scaled metrics.
##
## All fonts are synthetic; no binary fixtures.

import std/options
import unittest

import harfnim

proc putU16(s: var seq[uint8], v: uint16) =
  s.add(uint8(v shr 8))
  s.add(uint8(v and 0xFFu16))

proc putI16(s: var seq[uint8], v: int16) =
  s.putU16(cast[uint16](v))

proc putU32(s: var seq[uint8], v: uint32) =
  s.putU16(uint16(v shr 16))
  s.putU16(uint16(v and 0xFFFFu32))

proc putFixed(s: var seq[uint8], v: float32) =
  s.putU32(cast[uint32](int32(v * 65536.0f32)))

proc pad4(s: var seq[uint8]) =
  while s.len mod 4 != 0:
    s.add(0u8)

proc tagOf(s: string): uint32 =
  doAssert s.len == 4
  (uint32(uint8(s[0])) shl 24) or (uint32(uint8(s[1])) shl 16) or
    (uint32(uint8(s[2])) shl 8) or uint32(uint8(s[3]))

proc buildFvar(): seq[uint8] =
  result = @[]
  result.putU32(0x00010000u32)
  result.putU16(16u16)
  result.putU16(2u16)
  result.putU16(1u16)
  result.putU16(20u16)
  result.putU16(0u16)
  result.putU16(6u16)
  result.putU32(tagOf("wght"))
  result.putFixed(100.0f32)
  result.putFixed(400.0f32)
  result.putFixed(900.0f32)
  result.putU16(0u16)
  result.putU16(256u16)

proc buildHhea(asc, desc, gap: int16): seq[uint8] =
  result = @[]
  result.putU32(0x00010000u32)
  result.putI16(asc)
  result.putI16(desc)
  result.putI16(gap)
  result.putU16(500u16)
  result.putI16(0i16)
  result.putI16(0i16)
  result.putU16(600u16)
  for _ in 0 ..< 3:
    result.putI16(0i16)
  for _ in 0 ..< 4:
    result.putI16(0i16)
  result.putU16(0u16)
  result.putU16(1u16)

proc buildVhea(asc, desc, gap: int16): seq[uint8] =
  result = @[]
  result.putU32(0x00010000u32)
  result.putI16(asc)
  result.putI16(desc)
  result.putI16(gap)
  result.putU16(500u16)
  result.putI16(0i16)
  result.putI16(0i16)
  result.putU16(600u16)
  for _ in 0 ..< 3:
    result.putI16(0i16)
  for _ in 0 ..< 4:
    result.putI16(0i16)
  result.putU16(0u16)
  result.putU16(1u16)

proc buildCmapFormat4(): seq[uint8] =
  result = @[]
  result.putU16(4u16)
  result.putU16(32u16)
  result.putU16(0u16)
  result.putU16(4u16)
  result.putU16(4u16)
  result.putU16(1u16)
  result.putU16(0u16)
  result.putU16(0x43u16)
  result.putU16(0xFFFFu16)
  result.putU16(0u16)
  result.putU16(0x41u16)
  result.putU16(0xFFFFu16)
  result.putI16(-64i16)
  result.putI16(1i16)
  result.putU16(0u16)
  result.putU16(0u16)

proc buildCmap(): seq[uint8] =
  result = @[]
  result.putU16(0u16)
  result.putU16(1u16)
  result.putU16(3u16)
  result.putU16(1u16)
  result.putU32(12u32)
  result.add(buildCmapFormat4())

proc buildStore(deltas: seq[int16]): seq[uint8] =
  # One axis, one region (0 to 1, peak 1), one data block.
  result = @[]
  result.putU16(1u16)
  result.putU32(10u32)
  result.putU16(1u16)
  result.putU16(20u16)
  result.putU16(1u16)
  result.putU16(1u16)
  result.putI16(0i16)
  result.putI16(0x4000i16)
  result.putI16(0x4000i16)
  result.putU16(uint16(deltas.len))
  result.putU16(1u16)
  result.putU16(1u16)
  result.putU16(0u16)
  for d in deltas:
    result.putI16(d)

proc buildMvar(recs: seq[tuple[tag: string, outer, inner: uint16]],
    store: seq[uint8], major = 1u16): seq[uint8] =
  result = @[]
  result.putU16(major)
  result.putU16(0u16)
  result.putU16(0u16)
  result.putU16(8u16)
  result.putU16(uint16(recs.len))
  result.putU32(uint32(14 + recs.len * 8))
  for r in recs:
    doAssert r.tag.len == 4
    for c in r.tag:
      result.add(uint8(c))
    result.putU16(r.outer)
    result.putU16(r.inner)
  result.add(store)

proc buildFont(extra: seq[tuple[name: string, data: seq[uint8]]],
    asc, desc, gap: int16, withVhea: bool): seq[uint8] =
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
  var maxp = newSeq[uint8]()
  maxp.putU32(0x00005000u32)
  maxp.putU16(3u16)
  var hmtx = newSeq[uint8]()
  hmtx.putU16(500u16)
  hmtx.putI16(0i16)
  var loca = @[0u8, 0u8, 0u8, 0u8]
  var tables = @[
    ("head", head), ("hhea", buildHhea(asc, desc, gap)),
    ("maxp", maxp), ("hmtx", hmtx), ("cmap", buildCmap()),
    ("loca", loca),
  ]
  if withVhea:
    tables.add(("vhea", buildVhea(900i16, -100i16, 50i16)))
  tables.add(("fvar", buildFvar()))
  for t in extra:
    tables.add(t)
  result = @[]
  result.putU32(0x00010000u32)
  result.putU16(uint16(tables.len))
  result.putU16(32u16)
  result.putU16(1u16)
  result.putU16(16u16)
  var off = 12 + tables.len * 16
  for (tname, data) in tables:
    for c in tname:
      result.add(uint8(c))
    result.putU32(0u32)
    result.putU32(uint32(off))
    var padded = (data.len + 3) and not 3
    result.putU32(uint32(padded))
    off += padded
  for (_, data) in tables:
    result.add(data)
    result.pad4()

proc mvarFont(withVhea = true): seq[uint8] =
  let recs = @[("hasc", 0u16, 0u16), ("hdsc", 0u16, 1u16),
    ("vasc", 0u16, 2u16)]
  let store = buildStore(@[100i16, -50i16, 80i16])
  buildFont(@[("MVAR", buildMvar(recs, store))], 800i16, -200i16,
    100i16, withVhea)

proc wght(v: float32): tuple[tag: uint32, value: float32] =
  (tagFromStr("wght").toU32(), v)

test "mvar parses records and store":
  let f = parseFont(mvarFont())
  check f.mvarRecords.len == 3
  check f.mvarRecords[0] ==
    (tag: tagOf("hasc"), outer: 0u16, inner: 0u16)
  check f.mvarRecords[1] ==
    (tag: tagOf("hdsc"), outer: 0u16, inner: 1u16)
  check f.mvarRecords[2] ==
    (tag: tagOf("vasc"), outer: 0u16, inner: 2u16)
  check f.mvarStore.ok
  check f.mvarDelta(tagOf("hasc"), @[1.0f32]) == 100i32
  check f.mvarDelta(tagOf("hdsc"), @[1.0f32]) == -50i32
  check f.mvarDelta(tagOf("xxxx"), @[1.0f32]) == 0i32
  check f.mvarDelta(tagOf("hasc"), @[]) == 0i32

test "mvar metrics match hhea at default location":
  var sf = newShaperFont(parseFont(mvarFont()))
  sf.setScale(1000)
  check sf.hMetrics() == (ascender: 800i32, descender: -200i32, lineGap: 100i32)
  check sf.vMetrics() == (ascender: 900i32, descender: -100i32, lineGap: 50i32)

test "mvar deltas apply at wght extremes":
  var sf = newShaperFont(parseFont(mvarFont()))
  sf.setScale(1000)
  sf.setVariations([wght(900.0f32)])
  check sf.hMetrics() == (ascender: 900i32, descender: -250i32, lineGap: 100i32)
  check sf.vMetrics() == (ascender: 980i32, descender: -100i32, lineGap: 50i32)

test "mvar deltas interpolate at midpoint":
  var sf = newShaperFont(parseFont(mvarFont()))
  sf.setScale(1000)
  sf.setVariations([wght(650.0f32)])
  check sf.hMetrics() == (ascender: 850i32, descender: -225i32, lineGap: 100i32)
  check sf.vMetrics() == (ascender: 940i32, descender: -100i32, lineGap: 50i32)

test "mvar metrics scale with size":
  var sf = newShaperFont(parseFont(mvarFont()))
  sf.setScale(2000)
  check sf.hMetrics() == (ascender: 1600i32, descender: -400i32, lineGap: 200i32)

test "mvar malformed version stays static":
  let recs = @[("hasc", 0u16, 0u16)]
  let store = buildStore(@[100i16])
  let bytes = buildFont(@[("MVAR", buildMvar(recs, store, 2u16))],
    800i16, -200i16, 100i16, false)
  let f = parseFont(bytes)
  check f.mvarRecords.len == 0
  var sf = newShaperFont(f)
  sf.setScale(1000)
  sf.setVariations([wght(900.0f32)])
  check sf.hMetrics() == (ascender: 800i32, descender: -200i32, lineGap: 100i32)

test "mvar truncated store stays static":
  let recs = @[("hasc", 0u16, 0u16)]
  let store = buildStore(@[100i16])
  var bad = buildMvar(recs, store)
  bad.setLen(bad.len - 4)
  let bytes = buildFont(@[("MVAR", bad)], 800i16, -200i16, 100i16,
    false)
  let f = parseFont(bytes)
  check f.mvarRecords.len == 1
  check not f.mvarStore.ok
  var sf = newShaperFont(f)
  sf.setScale(1000)
  sf.setVariations([wght(900.0f32)])
  check sf.hMetrics() == (ascender: 800i32, descender: -200i32, lineGap: 100i32)

test "vmetrics without vhea are zero":
  var sf = newShaperFont(parseFont(mvarFont(false)))
  sf.setScale(1000)
  sf.setVariations([wght(900.0f32)])
  check sf.vMetrics() == (ascender: 0i32, descender: 0i32, lineGap: 0i32)
  check sf.hMetrics() == (ascender: 900i32, descender: -250i32, lineGap: 100i32)
