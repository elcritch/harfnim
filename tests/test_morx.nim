## Apple Advanced Typography morph chains (morx) substitution.
##
## Synthetic fonts only; no binary fixtures. Covers table parsing,
## feature flag compilation, the noncontextual and ligature drivers,
## and deleted-glyph removal.

import unittest

import harfnim
import harfnim/aat/morx

proc putU16(s: var seq[uint8], v: uint16) =
  s.add(uint8(v shr 8))
  s.add(uint8(v and 0xFFu16))

proc putI16(s: var seq[uint8], v: int16) =
  s.putU16(cast[uint16](v))

proc putU32(s: var seq[uint8], v: uint32) =
  s.putU16(uint16(v shr 16))
  s.putU16(uint16(v and 0xFFFFu32))

proc pad4(s: var seq[uint8]) =
  while s.len mod 4 != 0:
    s.add(0u8)

proc buildCmap(): seq[uint8] =
  result = @[]
  result.putU16(0u16)
  result.putU16(1u16)
  result.putU16(3u16)
  result.putU16(1u16)
  result.putU32(12u32)
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

proc buildHhea(): seq[uint8] =
  result = @[]
  result.putU32(0x00010000u32)
  result.putI16(800i16)
  result.putI16(-200i16)
  result.putI16(0i16)
  result.putU16(500u16)
  for _ in 0 ..< 4:
    result.putI16(0i16)
  result.putU16(600u16)
  for _ in 0 ..< 8:
    result.putI16(0i16)
  result.putU16(1u16)

proc buildFeat(): seq[uint8] =
  result = @[]
  result.putU32(1u32)
  result.putU16(1u16)
  result.putU16(0u16)
  result.putU32(0u32)
  result.putU16(1u16)
  result.putU16(2u16)
  result.putU32(0u32)
  result.putU16(1u16)
  result.putU16(0u16)

proc buildNonctx(): seq[uint8] =
  # Coverage: horizontal, all directions, noncontextual.
  result = @[]
  result.putU32(22u32)
  result.putU32(0x20000004u32)
  result.putU32(0xFFFFFFFFu32)
  # LookupU16 format 8: glyphs 10..11 map to 20..21.
  result.putU16(8u16)
  result.putU16(10u16)
  result.putU16(2u16)
  result.putU16(20u16)
  result.putU16(21u16)

proc buildLigature(): seq[uint8] =
  # Coverage: horizontal, all directions, ligature.
  result = @[]
  result.putU32(148u32)
  result.putU32(0x20000002u32)
  result.putU32(0x00000002u32)
  # Extended state table: 3 classes, 2 states.
  result.putU32(3u32)
  result.putU32(28u32)
  result.putU32(48u32)
  result.putU32(60u32)
  # Ligature table offsets, state-table-relative.
  result.putU32(78u32)
  result.putU32(86u32)
  result.putU32(110u32)
  # Class table format 6: glyph 10 -> 1, glyph 11 -> 2.
  result.putU16(6u16)
  result.putU16(4u16)
  result.putU16(2u16)
  result.putU16(8u16)
  result.putU16(1u16)
  result.putU16(0u16)
  result.putU16(10u16)
  result.putU16(1u16)
  result.putU16(11u16)
  result.putU16(2u16)
  # State array: row 0 idles, row 1 collects components.
  for v in [0u16, 1u16, 0u16, 0u16, 1u16, 2u16]:
    result.putU16(v)
  # Entry pool: null, set-component, set-component plus perform.
  result.putU16(0u16)
  result.putU16(0u16)
  result.putU16(0u16)
  result.putU16(1u16)
  result.putU16(0x8000u16)
  result.putU16(0u16)
  result.putU16(0u16)
  result.putU16(0xA000u16)
  result.putU16(0u16)
  # Ligature actions: plain offset then store plus last.
  result.putU32(0u32)
  result.putU32(0xC0000000u32)
  # Components indexed by absolute glyph id.
  for i in 0 ..< 12:
    if i == 10:
      result.putU16(5u16)
    elif i == 11:
      result.putU16(7u16)
    else:
      result.putU16(0u16)
  # Ligatures: index 12 is glyph 90.
  for i in 0 ..< 13:
    if i == 12:
      result.putU16(90u16)
    else:
      result.putU16(0u16)

proc buildMorx(): seq[uint8] =
  let nc = buildNonctx()
  let lig = buildLigature()
  result = @[]
  result.putU16(1u16)
  result.putU16(0u16)
  result.putU32(1u32)
  result.putU32(0xFFFFFFFFu32)
  result.putU32(uint32(16 + 12 + nc.len + lig.len))
  result.putU32(1u32)
  result.putU32(2u32)
  result.putU16(1u16)
  result.putU16(2u16)
  result.putU32(0x00000002u32)
  result.putU32(0u32)
  result.add(nc)
  result.add(lig)

proc morxFont(): seq[uint8] =
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
  maxp.putU16(256u16)
  var hmtx = newSeq[uint8]()
  hmtx.putU16(500u16)
  hmtx.putI16(0i16)
  var loca = @[0u8, 0u8, 0u8, 0u8]
  let tables = @[
    ("head", head), ("hhea", buildHhea()), ("maxp", maxp),
    ("hmtx", hmtx), ("cmap", buildCmap()), ("loca", loca),
    ("morx", buildMorx()), ("feat", buildFeat()),
  ]
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

proc morxTable(): MorxTable =
  let f = parseFont(morxFont())
  let t = f.tableData(0x6D6F7278u32)
  doAssert t.ok
  parseMorxTable(f.bytes, t.offset, t.len)

proc shapeGids(gids: openArray[uint32], map: AatMap,
    morx: MorxTable): Buffer =
  ## Shapes raw glyph ids the way the shaper would: per-subtable
  ## substitution in logical order, then deleted-glyph removal.
  result = newBuffer()
  result.pushStr("fi")
  doAssert result.len == gids.len
  for i, g in gids:
    result.info[i].glyphId = g
  result.setDirection(dirLeftToRight)
  applyMorx(morx, map, result, 256u32)
  removeDeletedGlyphs(result)

proc allFlagsMap(morx: MorxTable): AatMap =
  AatMap(chainFlags: @[@[(flags: 0xFFFFFFFFu32, first: 0u32,
    last: high(uint32))]])

test "morx parses chains and subtables":
  let m = morxTable()
  check m.ok
  check m.chains.len == 1
  check m.chains[0].features.len == 1
  check m.chains[0].features[0].kind == 1u16
  check m.chains[0].features[0].setting == 2u16
  check m.chains[0].subtables.len == 2
  check m.chains[0].subtables[0].kind == skNoncontextual
  check m.chains[0].subtables[1].kind == skLigature
  check m.chains[0].subtables[1].machine.nClasses == 3
  check m.chains[0].subtables[1].machine.nStates == 2

test "morx noncontextual substitutes glyphs":
  let m = morxTable()
  let b = shapeGids([10u32, 11u32], allFlagsMap(m), m)
  check b.len == 2
  check b.info[0].glyphId == 20u32
  check b.info[1].glyphId == 21u32
  check b.info[0].cluster == 0u32
  check b.info[1].cluster == 1u32

test "morx ligature forms fi":
  let m = morxTable()
  let subs = m.chains[0].subtables[1]
  let onlyLig = MorxTable(ok: true, chains: @[MorxChain(
    defaultFlags: 0xFFFFFFFFu32, features: @[], subtables: @[subs])])
  let b = shapeGids([10u32, 11u32], allFlagsMap(onlyLig), onlyLig)
  check b.len == 1
  check b.info[0].glyphId == 90u32
  check b.info[0].cluster == 0u32

test "morx feature flags gate subtables":
  let f = parseFont(morxFont())
  let t = f.tableData(0x66656174u32)
  doAssert t.ok
  let feat = parseFeat(f.bytes, t.offset, t.len)
  check feat.len == 1
  check feat[0].kind == 1u16
  let chains = @[MorxChain(defaultFlags: 0u32, features: @[(
    kind: 1u16, setting: 2u16, enable: 2u32, disable: 0xFFFFFFFFu32)],
    subtables: @[])]
  let onMap = compileAatMap(chains, feat,
    @[globalFeature(tagFromStr("liga"), 1)])
  check onMap.chainFlags.len == 1
  check onMap.chainFlags[0][0].flags == 2u32
  let offMap = compileAatMap(chains, feat,
    @[globalFeature(tagFromStr("liga"), 0)])
  check offMap.chainFlags.len == 1
  check offMap.chainFlags[0][0].flags == 0u32
  let otherMap = compileAatMap(chains, feat,
    @[globalFeature(tagFromStr("kern"), 1)])
  check otherMap.chainFlags[0][0].flags == 0u32

test "morx removes deleted glyphs":
  var b = newBuffer()
  b.pushStr("abc")
  b.info[1].glyphId = DeletedGlyph
  b.scratchFlags = b.scratchFlags or ScratchFlagShaper0
  removeDeletedGlyphs(b)
  check b.len == 2
  check b.info[0].glyphId == uint32('a')
  check b.info[1].glyphId == uint32('c')

