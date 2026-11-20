## Apple Advanced Typography morph chains (morx) substitution.
##
## Module-for-module port of the harfrust `aat/morx` path (itself a port
## of HarfBuzz `hb-aat-layout-morx-table`): chain iteration, feature
## flag compilation, the state-machine drive loop, and the
## noncontextual, contextual, ligature, rearrangement, and insertion
## drivers. Only 32-bit morx tables are supported; legacy 16-bit mort
## tables are skipped as unparseable, like fonts without morx.
##
## Acceleration structures (glyph-set digests, safe-to-break tables,
## class caches) are deliberately omitted: subtables always run, and
## the safe-to-break conditions are evaluated with direct state-table
## lookups, which is identical in outcome and fast enough for shaping.
## Language matching needs the `ltag` table and is not implemented;
## language-specific chain features never enable their flags.

import std/options

import ../buffer
import ../direction
import ../feature
import ../ot/gsub
import ../tag

const
  DeletedGlyph* = 0xFFFFu32
    ## Glyph id marking a deleted slot.
  ClassEndOfText = 0u16
  ClassOutOfBounds = 1u16
  ClassDeletedGlyph = 2u16

type
  MorxClassTable* = object
    ## Parsed AAT lookup table mapping glyph ids to u16 values.
    fmt*: uint16
    firstGlyph*, glyphCount*: uint16
      ## Format 8/10 range.
    valueSize*: uint16
      ## Format 10 value width in bytes.
    rawValues*: seq[uint8]
      ## Format 10 packed values.
    values*: seq[uint16]
      ## Format 0 dense values and format 8 value array.
    segs*: seq[tuple[first, last: uint16, vals: seq[uint16]]]
      ## Format 2 (one value) and format 4 (value array) segments.
    singles*: seq[tuple[gid, val: uint16]]
      ## Format 6 single mappings.

proc classValueAt(t: MorxClassTable, gid: uint32,
    numGlyphs: uint32): Option[uint16] =
  ## Looks up one glyph, none when the glyph is unmapped.
  case t.fmt
  of 0:
    if gid < uint32(t.values.len) and gid < numGlyphs:
      return some(t.values[gid])
  of 2, 4:
    var lo = 0
    var hi = t.segs.len
    while lo < hi:
      let mid = (lo + hi) shr 1
      if gid < uint32(t.segs[mid].first):
        hi = mid
      elif gid > uint32(t.segs[mid].last):
        lo = mid + 1
      else:
        let k = gid - uint32(t.segs[mid].first)
        if t.segs[mid].vals.len == 1:
          return some(t.segs[mid].vals[0])
        if int(k) < t.segs[mid].vals.len:
          return some(t.segs[mid].vals[int(k)])
        return none(uint16)
  of 6:
    var lo = 0
    var hi = t.singles.len
    while lo < hi:
      let mid = (lo + hi) shr 1
      if gid < uint32(t.singles[mid].gid):
        hi = mid
      elif gid > uint32(t.singles[mid].gid):
        lo = mid + 1
      else:
        return some(t.singles[mid].val)
  of 8:
    if gid >= uint32(t.firstGlyph) and
        gid - uint32(t.firstGlyph) < uint32(t.glyphCount):
      let k = int(gid - uint32(t.firstGlyph))
      if k < t.values.len:
        return some(t.values[k])
  of 10:
    if gid >= uint32(t.firstGlyph) and
        gid - uint32(t.firstGlyph) < uint32(t.glyphCount):
      let k = int(gid - uint32(t.firstGlyph)) * int(t.valueSize)
      if t.valueSize > 0 and k + int(t.valueSize) <= t.rawValues.len:
        var v = 0u16
        for i in 0 ..< int(t.valueSize):
          v = (v shl 8) or uint16(t.rawValues[k + i])
        return some(v)
  else:
    discard
  none(uint16)

type
  MorxReader = object
    # Bounded table reader; every read fails closed.
    bytes: seq[uint8]
    # Table bytes (copied refs share the font bytes).
    base: int
    # Table start offset.
    len: int
    # Table length.
    failed: bool
    # True once a read overran.

proc morxBytes(r: MorxReader, at, n: int): seq[uint8] =
  # Slices n bytes, failing closed on overrun.
  if at < 0 or n < 0 or at + n > r.len or r.base + at + n > r.bytes.len:
    return @[]
  r.bytes[r.base + at ..< r.base + at + n]

proc morxU16(r: var MorxReader, at: int): uint16 =
  # Reads a big endian uint16, failing closed on overrun.
  let b = r.morxBytes(at, 2)
  if b.len != 2:
    r.failed = true
    return 0u16
  (uint16(b[0]) shl 8) or uint16(b[1])

proc morxU32(r: var MorxReader, at: int): uint32 =
  # Reads a big endian uint32, failing closed on overrun.
  let b = r.morxBytes(at, 4)
  if b.len != 4:
    r.failed = true
    return 0u32
  (uint32(b[0]) shl 24) or (uint32(b[1]) shl 16) or
    (uint32(b[2]) shl 8) or uint32(b[3])

proc parseLookup(r: var MorxReader, at, endAbs: int): tuple[ok: bool,
    t: MorxClassTable] =
  ## Parses one AAT lookup table (formats 0/2/4/6/8/10), bounded by the
  ## subtable end. Formats 2/4/6 carry the standard 10-byte binary
  ## search header; entries start at offset 12.
  result.ok = false
  if at + 2 > endAbs:
    return
  let fmt = r.morxU16(at)
  if r.failed:
    return
  case fmt
  of 0:
    result.t = MorxClassTable(fmt: 0)
    var p = at + 2
    while p + 2 <= endAbs:
      result.t.values.add(r.morxU16(p))
      p += 2
    result.ok = not r.failed
  of 2, 4:
    let unitSize = int(r.morxU16(at + 2))
    let n = int(r.morxU16(at + 4))
    if r.failed or n < 0 or unitSize != 6:
      return
    result.t = MorxClassTable(fmt: fmt)
    for i in 0 ..< n:
      let e = at + 12 + i * 6
      if e + 6 > endAbs:
        return
      let first = r.morxU16(e + 2)
      let last = r.morxU16(e)
      if r.failed or first > last:
        return
      if fmt == 2:
        let v = r.morxU16(e + 4)
        if r.failed:
          return
        result.t.segs.add((first, last, @[v]))
      else:
        let voff = int(r.morxU16(e + 4))
        if r.failed or voff < 0 or at + voff > endAbs:
          return
        var vals: seq[uint16] = @[]
        for k in 0 .. int(last) - int(first):
          vals.add(r.morxU16(at + voff + k * 2))
          if r.failed:
            return
        result.t.segs.add((first, last, vals))
    result.ok = true
  of 6:
    let unitSize = int(r.morxU16(at + 2))
    let n = int(r.morxU16(at + 4))
    if r.failed or n < 0 or unitSize != 4:
      return
    result.t = MorxClassTable(fmt: 6)
    for i in 0 ..< n:
      let e = at + 12 + i * 4
      if e + 4 > endAbs:
        return
      let gid = r.morxU16(e)
      let v = r.morxU16(e + 2)
      if r.failed:
        return
      result.t.singles.add((gid, v))
    result.ok = true
  of 8:
    result.t = MorxClassTable(fmt: 8)
    result.t.firstGlyph = r.morxU16(at + 2)
    result.t.glyphCount = r.morxU16(at + 4)
    if r.failed or result.t.glyphCount == 0:
      return
    if at + 6 + int(result.t.glyphCount) * 2 > endAbs:
      return
    for k in 0 ..< int(result.t.glyphCount):
      result.t.values.add(r.morxU16(at + 6 + k * 2))
      if r.failed:
        return
    result.ok = true
  of 10:
    result.t = MorxClassTable(fmt: 10)
    result.t.firstGlyph = r.morxU16(at + 2)
    result.t.glyphCount = r.morxU16(at + 4)
    result.t.valueSize = r.morxU16(at + 6)
    if r.failed or result.t.glyphCount == 0 or result.t.valueSize == 0 or
        result.t.valueSize > 2:
      return
    let total = int(result.t.glyphCount) * int(result.t.valueSize)
    if at + 8 + total > endAbs:
      return
    result.t.rawValues = r.morxBytes(at + 8, total)
    result.ok = result.t.rawValues.len == total
  else:
    discard

type
  MorxEntry* = tuple[newState, flags, p0, p1: uint16]
    ## One state-table entry with payload words.

  MorxStateTable* = object
    ## Parsed extended state table with row-major entry indexes.
    ok*: bool
    nClasses*: int
    classes*: MorxClassTable
      ## Glyph to class lookup.
    nStates*: int
    rows*: seq[uint16]
      ## State array entry indexes, nStates rows of nClasses.
    entrySize*: int
    pool*: seq[uint8]
      ## Entry pool bytes from the entry table to the subtable end.

proc parseStateTable(r: var MorxReader, at, payloadWords,
    endAbs: int): MorxStateTable =
  ## Parses an extended state table. The state array holds u16 entry
  ## indexes (rows of nClasses); the entry pool follows at entryOff.
  ## All reads stay inside the subtable end.
  result.ok = false
  let nClasses = int(r.morxU32(at))
  let classOff = int(r.morxU32(at + 4))
  let stateOff = int(r.morxU32(at + 8))
  let entryOff = int(r.morxU32(at + 12))
  if r.failed:
    return
  let entrySize = 4 + payloadWords * 2
  if nClasses <= 0 or nClasses > 0xFFFF:
    return
  if stateOff < 16 or entryOff <= stateOff or at + entryOff > endAbs:
    return
  if (entryOff - stateOff) mod (nClasses * 2) != 0:
    return
  let nStates = (entryOff - stateOff) div (nClasses * 2)
  if nStates <= 0:
    return
  let lk = r.parseLookup(at + classOff, endAbs)
  if not lk.ok:
    return
  result.nClasses = nClasses
  result.classes = lk.t
  result.nStates = nStates
  result.entrySize = entrySize
  result.pool = r.morxBytes(at + entryOff, endAbs - (at + entryOff))
  if result.pool.len != endAbs - (at + entryOff):
    return
  var rows = newSeq[uint16](nStates * nClasses)
  for i in 0 ..< rows.len:
    rows[i] = r.morxU16(at + stateOff + i * 2)
    if r.failed:
      return
  result.rows = rows
  result.ok = true

proc stateEntry*(t: MorxStateTable, state: uint16,
    cls: uint16): tuple[ok: bool, e: MorxEntry] =
  ## Fetches one entry through the state array index, failing on
  ## out-of-range rows, columns, or pool offsets.
  if not t.ok or int(state) >= t.nStates or int(cls) >= t.nClasses:
    return (false, (0u16, 0u16, 0u16, 0u16))
  let idx = int(t.rows[int(state) * t.nClasses + int(cls)])
  let e = idx * t.entrySize
  if e + t.entrySize > t.pool.len:
    return (false, (0u16, 0u16, 0u16, 0u16))
  let b = t.pool
  let ns = (uint16(b[e]) shl 8) or uint16(b[e + 1])
  let fl = (uint16(b[e + 2]) shl 8) or uint16(b[e + 3])
  var p0 = 0u16
  var p1 = 0u16
  if t.entrySize >= 6:
    p0 = (uint16(b[e + 4]) shl 8) or uint16(b[e + 5])
  if t.entrySize >= 8:
    p1 = (uint16(b[e + 6]) shl 8) or uint16(b[e + 7])
  (true, (ns, fl, p0, p1))

proc glyphClass*(t: MorxStateTable, gid: uint32,
    numGlyphs: uint32): uint16 =
  ## Maps a glyph to its class, out of bounds when unmapped.
  if gid == DeletedGlyph:
    let v = t.classes.classValueAt(gid, numGlyphs)
    if v.isSome:
      return v.get
    return ClassDeletedGlyph
  let v = t.classes.classValueAt(gid, numGlyphs)
  if v.isSome:
    return v.get
  ClassOutOfBounds

type
  MorxSubKind* = enum
    skRearrangement
    skContextual
    skLigature
    skNoncontextual
    skInsertion

  MorxSubtable* = object
    ## One parsed morx subtable.
    coverage*: uint32
    subFeatureFlags*: uint32
    kind*: MorxSubKind
    machine*: MorxStateTable
    subsBase*: int
      ## Reader-relative base of the substitution offset array.
    subsEnd*: int
      ## Reader-relative subtable end bounding lookups.
    subs*: seq[Option[MorxClassTable]]
      ## Substitution lookups by mark/current index; none when the
      ## offset leaves the table.
    ligActions*: seq[uint32]
    ligComponents*: seq[uint16]
    ligLigatures*: seq[uint16]
    ncLookup*: MorxClassTable
    ## Noncontextual substitution lookup.
    insGlyphs*: seq[uint16]
    ## Insertion glyph list.

proc subtableType(coverage: uint32): int =
  int(coverage and 0xFFu32)

proc parseSubtable(r: var MorxReader, at,
    subLen: int): tuple[ok: bool, s: MorxSubtable] =
  ## Parses one subtable body; unknown types fail closed (skipped).
  result.ok = false
  if subLen < 12:
    return
  let coverage = r.morxU32(at + 4)
  let sff = r.morxU32(at + 8)
  let typ = subtableType(coverage)
  if r.failed:
    return
  case typ
  of 0:
    let m = r.parseStateTable(at + 12, 0, at + subLen)
    if not m.ok:
      return
    result.s = MorxSubtable(coverage: coverage, subFeatureFlags: sff,
      kind: skRearrangement, machine: m)
  of 1:
    let m = r.parseStateTable(at + 12, 2, at + subLen)
    if not m.ok:
      return
    # Substitution table offset is state-table-relative. The table is
    # a bare array of u32 lookup offsets running to the subtable end
    # (no count); indexes resolve against it, failing closed when the
    # offset leaves the table.
    let stx = at + 12
    let subsOff = int(r.morxU32(stx + 16))
    if r.failed or subsOff < 0 or stx + subsOff > at + subLen:
      return
    let so = stx + subsOff
    result.s = MorxSubtable(coverage: coverage, subFeatureFlags: sff,
      kind: skContextual, machine: m, subsBase: so,
      subsEnd: at + subLen)
    var p = so
    while p + 4 <= at + subLen:
      let lo = int(r.morxU32(p))
      if r.failed:
        return
      if lo < 0 or so + lo + 2 > at + subLen:
        result.s.subs.add(none(MorxClassTable))
      else:
        let lk = r.parseLookup(so + lo, at + subLen)
        if lk.ok:
          result.s.subs.add(some(lk.t))
        else:
          result.s.subs.add(none(MorxClassTable))
      p += 4
    result.ok = true
  of 2:
    let m = r.parseStateTable(at + 12, 1, at + subLen)
    if not m.ok:
      return
    # Ligature table offsets are state-table-relative.
    let stx = at + 12
    let laOff = int(r.morxU32(stx + 16))
    let coOff = int(r.morxU32(stx + 20))
    let liOff = int(r.morxU32(stx + 24))
    if r.failed or laOff < 28 or coOff <= laOff or liOff <= coOff or
        stx + liOff > at + subLen:
      return
    result.s = MorxSubtable(coverage: coverage, subFeatureFlags: sff,
      kind: skLigature, machine: m)
    var p = stx + laOff
    while p + 4 <= stx + coOff:
      result.s.ligActions.add(r.morxU32(p))
      p += 4
    var q = stx + coOff
    while q + 2 <= stx + liOff:
      result.s.ligComponents.add(r.morxU16(q))
      q += 2
    var k = stx + liOff
    while k + 2 <= at + subLen:
      result.s.ligLigatures.add(r.morxU16(k))
      k += 2
    if r.failed:
      return
  of 4:
    let lk = r.parseLookup(at + 12, at + subLen)
    if not lk.ok:
      return
    result.s = MorxSubtable(coverage: coverage, subFeatureFlags: sff,
      kind: skNoncontextual, ncLookup: lk.t)
  of 5:
    let m = r.parseStateTable(at + 12, 2, at + subLen)
    if not m.ok:
      return
    # Insertion action offset is state-table-relative.
    let insOff = int(r.morxU32(at + 12 + 16))
    if r.failed or insOff < 20 or at + 12 + insOff > at + subLen:
      return
    result.s = MorxSubtable(coverage: coverage, subFeatureFlags: sff,
      kind: skInsertion, machine: m)
    var p = at + 12 + insOff
    while p + 2 <= at + subLen:
      result.s.insGlyphs.add(r.morxU16(p))
      p += 2
    if r.failed:
      return
  else:
    return
  result.ok = true

type
  MorxChain* = object
    ## One parsed morph chain.
    defaultFlags*: uint32
    features*: seq[tuple[kind, setting: uint16, enable, disable: uint32]]
    subtables*: seq[MorxSubtable]

  MorxTable* = object
    ## Parsed morx table.
    ok*: bool
    chains*: seq[MorxChain]

proc parseMorxTable*(bytes: seq[uint8], off, len: int): MorxTable =
  ## Parses a morx table; unparseable tables yield ok == false.
  result.ok = false
  var r = MorxReader(bytes: bytes, base: off, len: len)
  let version = r.morxU16(0)
  let nChains = int(r.morxU32(4))
  if r.failed or version == 0 or nChains < 0:
    return
  var p = 8
  for _ in 0 ..< nChains:
    if p + 16 > len:
      return
    let defaultFlags = r.morxU32(p)
    let chainLen = int(r.morxU32(p + 4))
    let nFeat = int(r.morxU32(p + 8))
    let nSub = int(r.morxU32(p + 12))
    if r.failed or chainLen < 16 or p + chainLen > len or nFeat < 0 or
        nSub < 0:
      return
    var chain = MorxChain(defaultFlags: defaultFlags)
    var q = p + 16
    for _ in 0 ..< nFeat:
      if q + 12 > p + chainLen:
        return
      chain.features.add((r.morxU16(q), r.morxU16(q + 2), r.morxU32(q + 4),
        r.morxU32(q + 8)))
      q += 12
      if r.failed:
        return
    for _ in 0 ..< nSub:
      if q + 12 > p + chainLen:
        return
      let slen = int(r.morxU32(q))
      if r.failed or slen < 12 or q + slen > p + chainLen:
        return
      let sub = r.parseSubtable(q, slen)
      if r.failed:
        return
      if sub.ok:
        chain.subtables.add(sub.s)
      q += slen
    if r.failed:
      return
    result.chains.add(chain)
    p += chainLen
  result.ok = true

type
  FeatEntry* = tuple[kind: uint16, nSettings: int, exclusive: bool]

proc parseFeat*(bytes: seq[uint8], off, len: int): seq[FeatEntry] =
  ## Parses a feat table into feature type entries.
  result = @[]
  if off < 0 or len < 12 or off + len > bytes.len:
    return
  var r = MorxReader(bytes: bytes, base: off, len: len)
  discard r.morxU32(0)
  let nFeat = int(r.morxU16(4))
  if r.failed or nFeat < 0:
    return
  for i in 0 ..< nFeat:
    let e = 12 + i * 12
    let kind = r.morxU16(e)
    let nSet = int(r.morxU16(e + 2))
    let flags = r.morxU16(e + 8)
    if r.failed or nSet < 0:
      return
    result.add((kind, nSet, (flags and 1u16) != 0u16))

const
  AatLigatures* = 1u16
    ## AAT ligature feature type.
  LigCommonOn* = 2u16
  LigCommonOff* = 3u16
  LigRareOn* = 4u16
  LigRareOff* = 5u16
  LigRequiredOn* = 0u16
  LigRequiredOff* = 1u16
  LigContextOn* = 18u16
  LigContextOff* = 19u16
  LigHistoricalOn* = 20u16
  LigHistoricalOff* = 21u16

type
  AatRange* = tuple[flags: uint32, first, last: uint32]
    ## Chain flags valid for a cluster range (last inclusive).

  AatMap* = object
    ## Compiled per-chain flags for one shaping run.
    chainFlags*: seq[seq[AatRange]]

  AatFeature* = tuple[kind, setting: uint16, exclusive: bool]

proc otToAat(tag: Tag): tuple[ok: bool, kind: uint16, on, off: uint16] =
  ## Maps user OpenType features to AAT ligature kinds. Extended with
  ## more kinds as morx consumers need them.
  let t = tag.toStr()
  if t == "liga":
    return (true, AatLigatures, LigCommonOn, LigCommonOff)
  if t == "rlig":
    return (true, AatLigatures, LigRequiredOn, LigRequiredOff)
  if t == "clig":
    return (true, AatLigatures, LigContextOn, LigContextOff)
  if t == "dlig":
    return (true, AatLigatures, LigRareOn, LigRareOff)
  if t == "hlig":
    return (true, AatLigatures, LigHistoricalOn, LigHistoricalOff)
  (false, 0u16, 0u16, 0u16)

proc compileChainFlags(chain: MorxChain,
    current: openArray[AatFeature]): seq[AatRange] =
  ## Compiles one chain's flags from the active feature set.
  var flags = chain.defaultFlags
  for f in chain.features:
    var lo = 0
    var hi = current.len
    var found = false
    while lo < hi:
      let mid = (lo + hi) shr 1
      if current[mid].kind < f.kind or
          (current[mid].kind == f.kind and
            current[mid].setting < f.setting):
        lo = mid + 1
      elif current[mid].kind == f.kind and
          current[mid].setting == f.setting:
        found = true
        break
      else:
        hi = mid
    if found:
      flags = flags and f.disable
      flags = flags or f.enable
  result = @[(flags, 0u32, high(uint32))]

proc compileAatMap*(chains: seq[MorxChain], feat: seq[FeatEntry],
    features: openArray[Feature]): AatMap =
  ## Compiles chain flags for the requested user features. Feature
  ## ranges are global here; the single range keeps the drive loop's
  ## range check cheap.
  var current: seq[AatFeature] = @[]
  for ft in features:
    let m = otToAat(ft.tag)
    if not m.ok:
      continue
    var exposed = false
    var exclusive = true
    for fe in feat:
      if fe.kind == m.kind and fe.nSettings > 0:
        exposed = true
        exclusive = fe.exclusive
    if not exposed:
      continue
    let setting = if ft.value != 0u32: m.on else: m.off
    current.add((m.kind, setting, exclusive))
  # Sort by (kind, setting) for the binary search.
  for i in 1 ..< current.len:
    let cur = current[i]
    var j = i
    while j > 0 and (current[j - 1].kind > cur.kind or
        (current[j - 1].kind == cur.kind and
          current[j - 1].setting > cur.setting)):
      current[j] = current[j - 1]
      dec j
    current[j] = cur
  result.chainFlags = newSeq[seq[AatRange]](chains.len)
  for i, chain in chains:
    result.chainFlags[i] = compileChainFlags(chain, current)

const
  MaxMorxMatches = 64
    ## Ligature component stack depth.
  RearrMarkFirst = 0x8000u16
  RearrDontAdvance = 0x4000u16
  RearrMarkLast = 0x2000u16
  RearrVerb = 0x000Fu16
  CtxSetMark = 0x8000u16
  CtxDontAdvance = 0x4000u16
  LigSetComponent = 0x8000u16
  LigDontAdvance = 0x4000u16
  LigPerformAction = 0x2000u16
  LigActionLast = 0x80000000u32
  LigActionStore = 0x40000000u32
  LigActionOffset = 0x3FFFFFFFu32
  InsSetMark = 0x8000u16
  InsDontAdvance = 0x4000u16
  InsCurBefore = 0x0800u16
  InsMarkedBefore = 0x0400u16
  InsCurCount = 0x03E0u16
  InsMarkedCount = 0x001Fu16

const RearrMap: array[16, uint8] = [0x00u8, 0x10u8, 0x01u8, 0x11u8,
  0x20u8, 0x30u8, 0x02u8, 0x03u8, 0x12u8, 0x13u8, 0x21u8, 0x31u8,
  0x22u8, 0x32u8, 0x23u8, 0x33u8]
  ## Rearrangement verbs: nibbles move glyphs to the other side.

type
  MorxDrive = object
    # Per-kind transition state threaded through the drive loop.
    start*, stop*: int
    markSet*: bool
    mark*: int
    matchLen*: int
    matchPos*: array[MaxMorxMatches, int]

proc morxActionable(kind: MorxSubKind, e: MorxEntry,
    sub: MorxSubtable): bool =
  ## True when the entry performs an action.
  case kind
  of skRearrangement:
    (e.flags and RearrVerb) != 0u16
  of skContextual:
    e.p0 != 0xFFFFu16 or e.p1 != 0xFFFFu16
  of skLigature:
    (e.flags and LigPerformAction) != 0u16
  of skNoncontextual:
    false
  of skInsertion:
    (e.flags and (InsCurCount or InsMarkedCount)) != 0u16 and
      (e.p0 != 0xFFFFu16 or e.p1 != 0xFFFFu16)

proc morxCanAdvance(kind: MorxSubKind, e: MorxEntry): bool =
  ## True when the transition advances past the current glyph.
  case kind
  of skRearrangement:
    (e.flags and RearrDontAdvance) == 0u16
  of skContextual:
    (e.flags and CtxDontAdvance) == 0u16
  of skLigature:
    (e.flags and LigDontAdvance) == 0u16
  of skNoncontextual:
    true
  of skInsertion:
    (e.flags and InsDontAdvance) == 0u16

proc eotSafe(m: MorxStateTable, kind: MorxSubKind,
    sub: MorxSubtable, state: uint16): bool =
  ## Condition 3: no end-of-text action can fire out of the state.
  let e = m.stateEntry(state, ClassEndOfText)
  if not e.ok:
    return true
  not morxActionable(kind, e.e, sub)

proc wouldbeMatches(m: MorxStateTable, kind: MorxSubKind,
    sub: MorxSubtable, class: uint16, nextState: uint16,
    advance: bool): bool =
  ## Condition 2c: starting over on the class is a quiet move to the
  ## same state with the same advance.
  var c = class
  if int(c) >= m.nClasses:
    c = ClassOutOfBounds
  let e = m.stateEntry(0u16, c)
  if not e.ok or morxActionable(kind, e.e, sub):
    return false
  e.e.newState == nextState and morxCanAdvance(kind, e.e) == advance

proc curGid(b: Buffer, i: int): tuple[ok: bool, gid: uint32] =
  ## Glyph id at the index, failing past the buffer end.
  if i < 0 or i >= b.len or i >= b.info.len:
    return (false, 0u32)
  (true, b.info[i].glyphId)

proc driveTransition(kind: MorxSubKind, sub: MorxSubtable,
    e: MorxEntry, d: var MorxDrive, b: var Buffer): bool =
  ## Runs one entry transition; false aborts the subtable.
  case kind
  of skRearrangement:
    let flags = e.flags
    if (flags and RearrMarkFirst) != 0u16:
      d.start = b.idx
    if (flags and RearrMarkLast) != 0u16:
      d.stop = min(b.idx + 1, b.len)
    if (flags and RearrVerb) != 0u16 and d.start < d.stop:
      let mv = RearrMap[int(flags and RearrVerb)]
      let l = min(int(mv shr 4), 2)
      let r = min(int(mv and 0x0Fu8), 2)
      let revL = (mv shr 4) == 3u8
      let revR = (mv and 0x0Fu8) == 3u8
      if d.stop - d.start >= l + r and
          d.stop - d.start <= MaxContextLength:
        b.mergeClusters(d.start, min(b.idx + 1, b.len))
        b.mergeClusters(d.start, d.stop)
        # Swap the first l glyphs with the last r: rotate the run
        # left by l, then rotate the rest right by r.
        let n = d.stop - d.start
        var run = newSeq[GlyphInfo](n)
        for i in 0 ..< n:
          run[i] = b.info[d.start + i]
        var rotated = newSeq[GlyphInfo](n)
        for i in 0 ..< n:
          rotated[i] = run[(i + l) mod n]
        var final = rotated
        if n - l > 0 and r > 0:
          for i in 0 ..< n - l:
            final[i] = rotated[(i + (n - l) - r) mod (n - l)]
        if revL:
          swap(final[n - 2], final[n - 1])
        if revR:
          swap(final[0], final[1])
        for i in 0 ..< n:
          b.info[d.start + i] = final[i]
    true
  of skContextual:
    if b.idx == b.len and not d.markSet:
      return true
    if b.len == 0:
      return true
    var replacement = none(uint32)
    if e.p0 != 0xFFFFu16:
      let g = curGid(b, d.mark)
      if g.ok and int(e.p0) >= 0 and int(e.p0) < sub.subs.len:
        let lk = sub.subs[int(e.p0)]
        if lk.isSome:
          let v = lk.get.classValueAt(g.gid, uint32(b.info.len))
          if v.isSome:
            replacement = some(uint32(v.get))
    if replacement.isSome:
      b.unsafeToBreakRange(some(d.mark),
        some(min(b.idx + 1, b.len)))
      if d.mark < 0 or d.mark >= b.info.len:
        return false
      b.info[d.mark].glyphId = replacement.get
    replacement = none(uint32)
    let at = min(b.idx, b.len - 1)
    if e.p1 != 0xFFFFu16:
      let g = curGid(b, at)
      if g.ok and int(e.p1) >= 0 and int(e.p1) < sub.subs.len:
        let lk = sub.subs[int(e.p1)]
        if lk.isSome:
          let v = lk.get.classValueAt(g.gid, uint32(b.info.len))
          if v.isSome:
            replacement = some(uint32(v.get))
    if replacement.isSome:
      if at < 0 or at >= b.info.len:
        return false
      b.info[at].glyphId = replacement.get
    if (e.flags and CtxSetMark) != 0u16:
      d.markSet = true
      d.mark = b.idx
    true
  of skLigature:
    if (e.flags and LigSetComponent) != 0u16:
      if d.matchLen != 0 and
          d.matchPos[(d.matchLen - 1) mod MaxMorxMatches] == b.outLen:
        dec d.matchLen
      d.matchPos[d.matchLen mod MaxMorxMatches] = b.outLen
      inc d.matchLen
    if (e.flags and LigPerformAction) == 0u16:
      return true
    let finish = b.outLen
    if d.matchLen == 0:
      return true
    if b.idx >= b.len:
      return true
    var actionIdx = int(e.p0)
    var cursor = d.matchLen
    var ligIdx = 0u32
    while true:
      if cursor == 0:
        d.matchLen = 0
        break
      dec cursor
      if not b.moveTo(d.matchPos[cursor mod MaxMorxMatches]):
        return true
      if actionIdx < 0 or actionIdx >= sub.ligActions.len:
        break
      var action = sub.ligActions[actionIdx]
      var uoff = action and LigActionOffset
      if (uoff and 0x20000000u32) != 0u32:
        uoff = uoff or 0xC0000000u32
      let off = cast[int32](uoff)
      let g = curGid(b, b.idx)
      if not g.ok:
        break
      let ci = int64(g.gid) + int64(off)
      if ci < 0 or ci >= int64(sub.ligComponents.len):
        break
      let comp = uint32(sub.ligComponents[ci])
      if ligIdx > high(uint32) - comp:
        break
      ligIdx += comp
      if (action and (LigActionStore or LigActionLast)) != 0u32:
        if int(ligIdx) >= sub.ligLigatures.len:
          break
        let lig = uint32(sub.ligLigatures[int(ligIdx)])
        b.replaceGlyph(lig)
        if not b.successful:
          return false
        let ligEnd =
          d.matchPos[(d.matchLen - 1) mod MaxMorxMatches] + 1
        while d.matchLen - 1 > cursor:
          dec d.matchLen
          if not b.moveTo(d.matchPos[d.matchLen mod MaxMorxMatches]):
            return true
          b.replaceGlyph(DeletedGlyph)
          if not b.successful:
            return false
          b.scratchFlags = b.scratchFlags or ScratchFlagShaper0
        if not b.moveTo(ligEnd):
          return true
        b.mergeOutClusters(d.matchPos[cursor mod MaxMorxMatches],
          b.outLen)
      inc actionIdx
      if (action and LigActionLast) != 0u32:
        break
    if not b.moveTo(finish):
      return true
    true
  of skNoncontextual:
    true
  of skInsertion:
    let flags = e.flags
    let markLoc = b.outLen
    if e.p1 != 0xFFFFu16:
      var count = int(flags and InsMarkedCount)
      b.maxOps -= count
      if b.maxOps <= 0:
        return true
      let start = int(e.p1)
      let before = (flags and InsMarkedBefore) != 0u16
      let finish = b.outLen
      if not b.moveTo(d.mark):
        return true
      if b.idx < b.len and not before:
        b.copyGlyph()
      for i in 0 ..< count:
        if start + i >= sub.insGlyphs.len:
          b.indexFailed()
          return false
        b.outputGlyph(uint32(sub.insGlyphs[start + i]))
        if not b.successful:
          return false
      if b.idx < b.len and not before:
        b.skipGlyph()
      if not b.moveTo(finish + count):
        return true
      b.unsafeToBreakFromOutbuffer(some(d.mark),
        some(min(b.idx + 1, b.len)))
    if (flags and InsSetMark) != 0u16:
      d.mark = markLoc
    if e.p0 != 0xFFFFu16:
      var count = int((flags and InsCurCount) shr 5)
      b.maxOps -= count
      if b.maxOps < 0:
        return true
      let start = int(e.p0)
      let before = (flags and InsCurBefore) != 0u16
      let finish = b.outLen
      if b.idx < b.len and not before:
        b.copyGlyph()
      for i in 0 ..< count:
        if start + i >= sub.insGlyphs.len:
          b.indexFailed()
          return false
        b.outputGlyph(uint32(sub.insGlyphs[start + i]))
        if not b.successful:
          return false
      if b.idx < b.len and not before:
        b.skipGlyph()
      if not b.moveTo(if (flags and InsDontAdvance) != 0u16: finish
        else: finish + count):
        return true
    true
proc driveMachine(m: MorxStateTable, kind: MorxSubKind,
    sub: MorxSubtable, b: var Buffer, numGlyphs: uint32,
    subFlags: uint32, ranges: openArray[AatRange]): bool =
  ## Runs the state machine over the buffer; false aborts the subtable.
  let inPlace = kind == skRearrangement or kind == skContextual
  if not inPlace:
    b.clearOutput()
  var d = MorxDrive()
  var state = 0u16
  var lastRange = -1
  if ranges.len > 1:
    lastRange = 0
  let startSafeEot = eotSafe(m, kind, sub, 0u16)
  b.idx = 0
  while true:
    if lastRange >= 0 and lastRange < ranges.len:
      var r = lastRange
      if b.idx < b.len and b.idx < b.info.len:
        let cl = b.info[b.idx].cluster
        while r > 0 and cl < ranges[r].first:
          dec r
        while r + 1 < ranges.len and cl > ranges[r].last:
          inc r
      lastRange = r
      if (ranges[r].flags and subFlags) == 0u32:
        if b.idx >= b.len or not b.successful:
          break
        state = 0u16
        b.nextGlyph()
        continue
    let class =
      if b.idx < b.len:
        let g = curGid(b, b.idx)
        if not g.ok or g.gid > 0xFFFFu32:
          return false
        m.glyphClass(g.gid, numGlyphs)
      else:
        ClassEndOfText
    let ent = m.stateEntry(state, class)
    if not ent.ok:
      break
    let e = ent.e
    let nextState = e.newState
    let actionable = morxActionable(kind, e, sub)
    let advance = morxCanAdvance(kind, e)
    if lastRange < 0 and state == 0u16 and nextState == 0u16 and
        startSafeEot and not actionable and advance:
      let oldClass = class
      while true:
        if not driveTransition(kind, sub, e, d, b):
          return false
        if b.idx >= b.len or not b.successful:
          break
        b.nextGlyph()
        let nc =
          if b.idx < b.len:
            let g = curGid(b, b.idx)
            if not g.ok or g.gid > 0xFFFFu32:
              return false
            m.glyphClass(g.gid, numGlyphs)
          else:
            ClassEndOfText
        if nc != oldClass:
          break
      if b.idx >= b.len or not b.successful:
        break
      continue
    let safe = (not actionable) and
      (state == 0u16 or
        (not advance and nextState == 0u16) or
        wouldbeMatches(m, kind, sub, class, nextState, advance)) and
      eotSafe(m, kind, sub, state)
    if not safe and b.backtrackLen() > 0 and b.idx < b.len:
      b.unsafeToBreakFromOutbuffer(some(b.backtrackLen() - 1),
        some(b.idx + 1))
    if not driveTransition(kind, sub, e, d, b):
      return false
    state = nextState
    if b.idx >= b.len or not b.successful:
      break
    if advance:
      b.nextGlyph()
    else:
      if b.maxOps <= 0:
        b.nextGlyph()
      dec b.maxOps
  if not inPlace:
    discard b.sync()
  true

proc applyNoncontextual(sub: MorxSubtable, b: var Buffer,
    numGlyphs: uint32, subFlags: uint32,
    ranges: openArray[AatRange]): bool =
  ## Applies a single-substitution pass over the buffer.
  var lastRange = -1
  if ranges.len > 1:
    lastRange = 0
  for i in 0 ..< b.len:
    if lastRange >= 0 and lastRange < ranges.len:
      var r = lastRange
      if i < b.info.len:
        let cl = b.info[i].cluster
        while r > 0 and cl < ranges[r].first:
          dec r
        while r + 1 < ranges.len and cl > ranges[r].last:
          inc r
      lastRange = r
      if (ranges[r].flags and subFlags) == 0u32:
        continue
    if i >= b.info.len:
      break
    let v = sub.ncLookup.classValueAt(b.info[i].glyphId, numGlyphs)
    if v.isSome:
      b.info[i].glyphId = uint32(v.get)
  true

proc applyMorxSubtable*(sub: MorxSubtable, b: var Buffer,
    numGlyphs: uint32, subFlags: uint32,
    ranges: openArray[AatRange]): bool =
  ## Applies one subtable; false aborts it (the buffer is marked failed).
  case sub.kind
  of skRearrangement, skContextual, skLigature, skInsertion:
    if not sub.machine.ok:
      return true
    driveMachine(sub.machine, sub.kind, sub, b, numGlyphs, subFlags,
      ranges)
  of skNoncontextual:
    applyNoncontextual(sub, b, numGlyphs, subFlags, ranges)

proc applyMorx*(morx: MorxTable, map: AatMap, b: var Buffer,
    numGlyphs: uint32) =
  ## Applies all chains in order, reversing around subtables whose
  ## coverage demands it.
  var reversed = false
  for ci, chain in morx.chains:
    if ci >= map.chainFlags.len:
      continue
    let chainFlags = map.chainFlags[ci]
    for sub in chain.subtables:
      if chainFlags.len == 1 and
          (sub.subFeatureFlags and chainFlags[0].flags) == 0u32:
        continue
      let cov = sub.coverage
      let allDirs = (cov and 0x20000000u32) != 0u32
      let vertical = (cov and 0x80000000u32) != 0u32
      if not allDirs and b.direction.isVertical() != vertical:
        continue
      let isLogical = (cov and 0x10000000u32) != 0u32
      let isBackwards = (cov and 0x40000000u32) != 0u32
      let rev =
        if isLogical: isBackwards
        else: isBackwards != b.direction.isBackward()
      if rev != reversed:
        b.reverse()
        reversed = not reversed
      if not applyMorxSubtable(sub, b, numGlyphs, sub.subFeatureFlags,
          chainFlags):
        b.indexFailed()
        return
  if reversed:
    b.reverse()

proc removeDeletedGlyphs*(b: var Buffer) =
  ## Compacts 0xFFFF slots left by morx deletions.
  if (b.scratchFlags and ScratchFlagShaper0) == 0u32:
    return
  b.deleteGlyphsInplace(proc(g: GlyphInfo): bool {.closure.} =
    g.glyphId == DeletedGlyph)

