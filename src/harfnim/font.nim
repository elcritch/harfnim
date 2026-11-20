import std/options

import ./aat/morx
import ./buffer
import ./draw
import ./normalize
import ./scale
import ./sfnt
import ./tag
import ./variations
import ./ot/gpos
import ./ot/gsub
import ./ot/kern

export scale
export sfnt
export draw
export variations

type
  LayoutTables* = ref object
    ## Lazily parsed layout tables, shared through ShaperFont copies
    ## (same pattern as the outline cache). Table bytes are immutable
    ## per parsed font and parsing ignores the variation location
    ## (applied later from `varCoords`), so no invalidation is needed.
    gsubDone*: bool
    ## True once GSUB parsing was attempted.
    gsub*: Option[GsubData]
    ## Parsed GSUB table, if present.
    gposDone*: bool
    ## True once GPOS parsing was attempted.
    gpos*: Option[GposData]
    ## Parsed GPOS table, if present.
    kernDone*: bool
    ## True once kern parsing was attempted.
    kern*: Option[KernData]
    ## Parsed kern table, if present.
    morxDone*: bool
    ## True once morx parsing was attempted.
    morx*: Option[MorxTable]
    ## Parsed morx table, if present.
    featDone*: bool
    ## True once feat parsing was attempted.
    feat*: Option[seq[FeatEntry]]
    ## Parsed feat feature entries.

  ShaperFont* = ref object
    ## Shaper handle over a parsed font (HarfBuzz `hb_font_t` equivalent).
    ## A ref so copies share state instead of deep-copying megabytes of
    ## font bytes per call. Sharing is observable: `setScale` and
    ## `setVariations` mutate the shared object, so callers needing
    ## isolation must create separate shapers via `newShaperFont`.
    font*: SfntFont
    ## Parsed font.
    unitsPerEm*: uint16
    ## Design units per em.
    scale*: Scale
    ## Active scale.
    outlineCache*: OutlineCache
    ## Shared outline cache.
    layout*: LayoutTables
    ## Shared layout table cache.
    varCoords*: seq[float32]
    ## Normalized variation coordinates.
    # TODO: FontFuncs overrides (custom nominal/metrics callbacks)
    # TODO: cmap cache

proc newShaperFont*(font: SfntFont): ShaperFont =
  ## Creates a shaper handle over a parsed font.
  ShaperFont(
    font: font,
    unitsPerEm: font.unitsPerEm,
    scale: identityScale(int32(font.unitsPerEm)),
    outlineCache: newOutlineCache(),
    layout: LayoutTables(),
    varCoords: newSeq[float32](font.fvarAxes.len),
  )

proc cachedGsub*(f: ShaperFont): Option[GsubData] =
  ## GSUB parsed once per shaper (full-table parse costs milliseconds
  ## on large fonts; `shape` used to pay it on every call).
  if f.layout == nil:
    return parseGsub(f.font)
  if not f.layout.gsubDone:
    f.layout.gsub = parseGsub(f.font)
    f.layout.gsubDone = true
  f.layout.gsub

proc cachedGpos*(f: ShaperFont): Option[GposData] =
  ## Like `cachedGsub` for GPOS.
  if f.layout == nil:
    return parseGpos(f.font)
  if not f.layout.gposDone:
    f.layout.gpos = parseGpos(f.font)
    f.layout.gposDone = true
  f.layout.gpos

proc cachedKern*(f: ShaperFont): Option[KernData] =
  ## Like `cachedGsub` for the legacy `kern` table (parsed only when a
  ## kern feature is requested and GPOS supplied no kern for the script).
  if f.layout == nil:
    return parseKern(f.font)
  if not f.layout.kernDone:
    f.layout.kern = parseKern(f.font)
    f.layout.kernDone = true
  f.layout.kern

const
  TagMorx = 0x6D6F7278u32
  TagFeat = 0x66656174u32

proc cachedMorx*(f: ShaperFont): Option[MorxTable] =
  ## Like `cachedGsub` for the AAT `morx` table.
  if f.layout == nil:
    let t = f.font.tableData(TagMorx)
    if not t.ok:
      return none(MorxTable)
    let m = parseMorxTable(f.font.bytes, t.offset, t.len)
    if m.ok:
      return some(m)
    return none(MorxTable)
  if not f.layout.morxDone:
    let t = f.font.tableData(TagMorx)
    var m = MorxTable(ok: false)
    if t.ok:
      m = parseMorxTable(f.font.bytes, t.offset, t.len)
    if m.ok:
      f.layout.morx = some(m)
    f.layout.morxDone = true
  f.layout.morx

proc cachedFeat*(f: ShaperFont): Option[seq[FeatEntry]] =
  ## Like `cachedGsub` for the AAT `feat` table.
  if f.layout == nil:
    let t = f.font.tableData(TagFeat)
    if not t.ok:
      return none(seq[FeatEntry])
    return some(parseFeat(f.font.bytes, t.offset, t.len))
  if not f.layout.featDone:
    let t = f.font.tableData(TagFeat)
    if t.ok:
      f.layout.feat = some(parseFeat(f.font.bytes, t.offset, t.len))
    f.layout.featDone = true
  f.layout.feat

proc setScale*(f: var ShaperFont, scale: int32) =
  ## Sets uniform scale from font units.
  f.scale = newScale(scale, scale, int32(f.unitsPerEm))

proc setScaleSeparate*(f: var ShaperFont, xScale, yScale: int32) =
  ## Sets separate horizontal and vertical scales.
  f.scale = newScale(xScale, yScale, int32(f.unitsPerEm))

proc setVariations*(f: var ShaperFont,
    vars: openArray[tuple[tag: uint32, value: float32]]) =
  ## Sets the variation location from user-space axis values. Unknown
  ## tags are ignored; unspecified axes reset to default. Cached
  ## outlines are keyed by glyph only, so the cache is replaced to
  ## avoid serving default-location outlines at the new location
  ## (copies holding the old handle keep their own location's cache).
  f.varCoords = normalizeCoords(f.font.fvarAxes, f.font.avarMaps, vars)
  f.outlineCache = newOutlineCache(f.outlineCache.maxItems)

proc normalizedCoords*(f: ShaperFont): seq[float32] =
  ## Returns the normalized variation coordinates.
  f.varCoords

proc nominalGlyph*(f: ShaperFont, cp: uint32): Option[GlyphId] =
  ## Maps a codepoint to its nominal glyph.
  f.font.mapUnicode(cp)

proc nominalGlyphs*(f: ShaperFont, infos: var seq[GlyphInfo], first,
    last: int): int =
  ## Maps a range of codepoints, returning the mapped count.
  result = 0
  for i in first ..< last:
    if i < 0 or i >= infos.len:
      break
    let gid = f.nominalGlyph(infos[i].glyphId)
    if gid.isNone:
      break
    infos[i].setNormalizerGlyphIndex(gid.get.value)
    inc result

proc variationGlyph*(f: ShaperFont, base, selector: uint32): Option[GlyphId] =
  ## Maps a base plus variation selector pair.
  f.font.mapUnicodeVariant(base, selector)

proc hAdvance*(f: ShaperFont, gid: GlyphId): int32 =
  ## Scaled horizontal advance with variation deltas.
  let base = f.font.hAdvance(gid.value) +
    f.font.hAdvanceDelta(gid.value, f.varCoords)
  f.scale.clampXAdvance(f.scale.scaleX(base))

proc vAdvance*(f: ShaperFont, gid: GlyphId): int32 =
  ## Scaled vertical advance with variation deltas.
  let base = f.font.vAdvance(gid.value) +
    f.font.vAdvanceDelta(gid.value, f.varCoords)
  let v = f.scale.clampYAdvance(f.scale.scaleY(base))
  if v == low(int32): high(int32) else: -v

proc hMetrics*(f: ShaperFont): tuple[ascender, descender, lineGap: int32] =
  ## Scaled horizontal metrics with MVAR deltas at the variation
  ## location.
  let c = f.varCoords
  let asc = f.font.hheaAscender() +
    f.font.mvarDelta(tagFromStr("hasc").toU32(), c)
  let desc = f.font.hheaDescender() +
    f.font.mvarDelta(tagFromStr("hdsc").toU32(), c)
  let gap = f.font.hheaLineGap() +
    f.font.mvarDelta(tagFromStr("hlgp").toU32(), c)
  (f.scale.scaleY(asc), f.scale.scaleY(desc), f.scale.scaleY(gap))

proc vMetrics*(f: ShaperFont): tuple[ascender, descender, lineGap: int32] =
  ## Scaled vertical metrics with MVAR deltas; zeros without vhea.
  if not f.font.hasVMetrics:
    return (0i32, 0i32, 0i32)
  let c = f.varCoords
  let asc = f.font.vheaAscender() +
    f.font.mvarDelta(tagFromStr("vasc").toU32(), c)
  let desc = f.font.vheaDescender() +
    f.font.mvarDelta(tagFromStr("vdsc").toU32(), c)
  let gap = f.font.vheaLineGap() +
    f.font.mvarDelta(tagFromStr("vlgp").toU32(), c)
  (f.scale.scaleY(asc), f.scale.scaleY(desc), f.scale.scaleY(gap))

proc drawGlyph*(f: ShaperFont, gid: GlyphId,
    cb: proc(op: DrawOp) {.closure.}): bool =
  ## Cached outline emission. Hits replay the stored outline; misses
  ## decode once and store the result (including failures). The cache
  ## lives behind a ref so it works through value copies of the font.
  let (hit, v) = cacheLookup(f.outlineCache, gid.value)
  if hit:
    if v.isNone:
      return false
    replayOutline(v.get, cb)
    return true
  var b = OutlineBuilder()
  let ok = b.collectInto(proc(
      c: proc(op: DrawOp) {.closure.}): bool =
    f.font.drawGlyph(gid.value, c, f.varCoords))
  let o = b.finish()
  cacheStore(f.outlineCache, gid.value,
    if ok: some(o) else: none(GlyphOutline))
  if not ok:
    return false
  replayOutline(o, cb)
  true

proc glyphOutline*(f: ShaperFont, gid: GlyphId): Option[GlyphOutline] =
  ## Cached value outline.
  let (hit, v) = cacheLookup(f.outlineCache, gid.value)
  if hit:
    return v
  var b = OutlineBuilder()
  let ok = b.collectInto(proc(
      c: proc(op: DrawOp) {.closure.}): bool =
    f.font.drawGlyph(gid.value, c, f.varCoords))
  let o = if ok: some(b.finish()) else: none(GlyphOutline)
  cacheStore(f.outlineCache, gid.value, o)
  o

proc glyphBoundsComputedCached*(f: ShaperFont,
    gid: GlyphId): Option[tuple[xMin, yMin, xMax, yMax: int32]] =
  ## Outline bounds from the cache, decoding on miss.
  let o = f.glyphOutline(gid)
  if o.isNone:
    return none(tuple[xMin, yMin, xMax, yMax: int32])
  outlineBounds(o.get)

proc isVaried*(f: ShaperFont): bool =
  ## True when a non-default variation location is active.
  for v in f.varCoords:
    if v != 0.0f32:
      return true
  false

proc glyphExtents*(f: ShaperFont, gid: GlyphId): Option[GlyphExtents] =
  ## Scaled extents, preferring the header box over decoded bounds.
  if not f.isVaried() or not f.font.hasGvar():
    let b = f.font.glyphBoundsUnscaled(gid.value)
    if b.isSome:
      let (xMin, yMin, xMax, yMax) = b.get
      return some(f.scale.scaleExtents(GlyphExtents(xBearing: xMin,
        yBearing: yMax, width: xMax - xMin, height: yMin - yMax)))
  # Header box unavailable (composite glyph or CFF outlines) or the
  # location is varied: fall back to the decoded outline bounds.
  # TODO: metric variations (HVAR/MVAR) for advances.
  let cb = f.glyphBoundsComputedCached(gid)
  if cb.isNone:
    return none(GlyphExtents)
  let (xMin, yMin, xMax, yMax) = cb.get
  some(f.scale.scaleExtents(GlyphExtents(xBearing: xMin, yBearing: yMax,
    width: xMax - xMin, height: yMin - yMax)))

proc hasGlyph*(f: ShaperFont, cp: uint32): bool =
  ## True when the font maps the codepoint.
  f.nominalGlyph(cp).isSome

proc normalizeContextFor*(f: ShaperFont): NormalizeContext =
  ## Builds a normalize context bound to this font.
  let ff = f
  newNormalizeContext(
    nominalGlyph = proc(cp: uint32): Option[GlyphId] = ff.nominalGlyph(cp),
    nominalGlyphs = proc(infos: var seq[GlyphInfo], first,
        last: int): int =
      ff.nominalGlyphs(infos, first, last),
    variationGlyph = proc(base, selector: uint32): Option[GlyphId] =
      ff.variationGlyph(base, selector),
  )
