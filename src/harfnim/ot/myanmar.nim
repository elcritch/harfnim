## Myanmar shaper: Ra-As-H reph handling and pre-base matra reordering.
##
## Ports harfrust `ot/shaper/myanmar.rs` (HarfBuzz main). Syllables
## are found first, locl/ccmp apply, then initial reordering assigns
## Myanmar positions, the four basic features apply in order, and the
## four other features apply after clearing syllables.

import std/options

import ../buffer
import ../feature
import ../font
import ../tag
import ./gsub
import ./indic_table
import ./map
import ./maskbits
import ./myanmar_machine
import ./syllabic

export myanmar_machine

const
  MyanmarBasicTags*: array[4, string] = ["rphf", "pref", "blwf", "pstf"]
    ## Basic features applied in order after reordering.
  MyanmarOtherTags*: array[4, string] = ["pres", "abvs", "blws", "psts"]
    ## Other features applied after clearing syllables.

proc myanmarCategory*(g: GlyphInfo): uint8 =
  ## Syllabic category attached during setup (same var slot as Indic).
  g.otShaperCategory()

proc setMyanmarCategory*(g: var GlyphInfo, v: uint8) =
  ## Writes the Myanmar category byte.
  g.setOtShaperCategory(v)

proc myanmarPosition*(g: GlyphInfo): uint8 =
  ## Positional category attached during reordering.
  g.otShaperAuxiliary()

proc setMyanmarPosition*(g: var GlyphInfo, v: uint8) =
  ## Writes the Myanmar position byte.
  g.setOtShaperAuxiliary(v)

proc isMyanmarConsonant(g: GlyphInfo): bool =
  ## True for consonant-like glyphs, ignoring ligated ones.
  if g.ligated():
    return false
  let c = g.myanmarCategory()
  c == OtC or c == OtCs or c == OtRa or c == OtV or c == OtGb or
    c == OtDottedCircle

proc setupMyanmarProperties*(buf: var Buffer) =
  ## Attaches the Indic-derived syllabic category to every glyph.
  ## Runs on codepoints, before glyph mapping.
  for i in 0 ..< min(buf.len, buf.info.len):
    let (cat, _) = getCategories(buf.info[i].glyphId)
    buf.info[i].setMyanmarCategory(cat)

proc setupSyllablesMyanmar*(buf: var Buffer) =
  ## GSUB-pause callback: finds syllables, records over-long cuts,
  ## then marks every syllable unsafe to break across.
  findSyllablesMyanmar(buf)
  var start = 0
  var stop = buf.nextSyllable(0)
  while start < buf.len and buf.successful:
    buf.recordSyllableCut(start, stop)
    buf.unsafeToBreakRange(some(start), some(stop))
    start = stop
    stop = buf.nextSyllable(start)

proc initialReorderingConsonantSyllable(buf: var Buffer, start,
    stop: int): bool =
  if start < 0 or stop > buf.len or stop > buf.info.len or
      start >= stop:
    buf.indexFailed()
    return false
  var base = stop
  var hasReph = false
  var limit = start
  if start + 3 <= stop and
      buf.info[start].myanmarCategory() == OtRa and
      buf.info[start + 1].myanmarCategory() == OtAs and
      buf.info[start + 2].myanmarCategory() == OtH:
    limit += 3
    base = start
    hasReph = true
  if not hasReph:
    base = limit
  for i in limit ..< stop:
    if buf.info[i].isMyanmarConsonant():
      base = i
      break
  var i = start
  let rephCount = if hasReph: 3 else: 0
  while i < start + rephCount:
    buf.info[i].setMyanmarPosition(PosAfterMain)
    inc i
  while i < base:
    buf.info[i].setMyanmarPosition(PosPreC)
    inc i
  if i < stop:
    buf.info[i].setMyanmarPosition(PosBaseC)
    inc i
  var pos = PosAfterMain
  for k in i ..< stop:
    let cat = buf.info[k].myanmarCategory()
    if cat == OtMr:
      buf.info[k].setMyanmarPosition(PosPreC)
      continue
    if cat == OtVPre:
      buf.info[k].setMyanmarPosition(PosPreM)
      continue
    if cat == OtVs:
      let t =
        if k - 1 >= start: buf.info[k - 1].myanmarPosition()
        else: PosAfterMain
      buf.info[k].setMyanmarPosition(t)
      continue
    if pos == PosAfterMain and cat == OtVBlw:
      pos = PosBelowC
      buf.info[k].setMyanmarPosition(pos)
      continue
    if pos == PosBelowC and cat == OtA:
      buf.info[k].setMyanmarPosition(PosBeforeSub)
      continue
    if pos == PosBelowC and cat == OtVBlw:
      buf.info[k].setMyanmarPosition(pos)
      continue
    if pos == PosBelowC and cat != OtA:
      pos = PosAfterSub
      buf.info[k].setMyanmarPosition(pos)
      continue
    buf.info[k].setMyanmarPosition(pos)
  buf.sort(start, stop,
    proc(a, b: GlyphInfo): bool {.closure.} =
      a.myanmarPosition() > b.myanmarPosition())
  var firstLeft = stop
  var lastLeft = stop
  for k in start ..< stop:
    if buf.info[k].myanmarPosition() == PosPreM:
      if firstLeft == stop:
        firstLeft = k
      lastLeft = k
  if firstLeft < lastLeft:
    buf.reverseRange(firstLeft, lastLeft + 1)
    var m = firstLeft
    for j in firstLeft .. lastLeft:
      if buf.info[j].myanmarCategory() == OtVPre:
        buf.reverseRange(m, j + 1)
        m = j + 1
  true

proc reorderSyllableMyanmar(buf: var Buffer, start, stop: int): bool =
  if start < 0 or start >= buf.info.len or stop > buf.info.len:
    buf.indexFailed()
    return false
  case buf.info[start].syllable() and 0x0Fu8
  of 0u8, 2u8:
    buf.initialReorderingConsonantSyllable(start, stop)
  else:
    true

proc reorderMyanmar*(buf: var Buffer, sf: ShaperFont): bool =
  ## GSUB-pause callback: dotted-circle insertion for broken
  ## syllables, then per-syllable initial reordering.
  if buf.insertDottedCircles(sf, uint8(ord(BrokenCluster)),
      OtDottedCircle, none(uint8), none(uint8)):
    discard
  if not buf.successful:
    return false
  var start = 0
  var stop = buf.nextSyllable(0)
  while start < buf.len and buf.successful:
    if not buf.reorderSyllableMyanmar(start, stop):
      return false
    start = stop
    stop = buf.nextSyllable(start)
  buf.successful

proc lookupsForTag(gsub: GsubData, scriptTag, langTag: Tag,
    tagStr: string): seq[uint16] =
  # Resolves lookups for one tag under the shaping script.
  gsubLookupsForTag(gsub, scriptTag, langTag, tagFromStr(tagStr).toU32())

proc applyMyanmarFeature(buf: var Buffer, gsub: GsubData,
    scriptTag, langTag: Tag, tagStr: string, perSyllable: bool,
    nextBit: var uint32) =
  ## Applies one automatic feature with a fresh buffer-wide mask.
  let lookups = lookupsForTag(gsub, scriptTag, langTag, tagStr)
  if lookups.len == 0:
    return
  let (m, v) = allocMaskBit(nextBit, 1u32)
  if m == 0u32:
    return
  buf.setMasks(v, m, GlobalStart, GlobalEnd)
  buf.applySubstLookups(gsub, lookups, m, perSyllable)

proc applyMyanmarGsub*(buf: var Buffer, sf: ShaperFont, gsub: GsubData,
    scriptTag, langTag: Tag, userFeatures: openArray[Feature]) =
  ## Full Myanmar GSUB: syllable setup, locl/ccmp, reordering, the
  ## four basic features in order, then the four other features after
  ## clearing syllables.
  buf.setupSyllablesMyanmar()
  if not buf.successful:
    return
  var nextBit = 8u32
  buf.applyMyanmarFeature(gsub, scriptTag, langTag, "locl", true,
    nextBit)
  buf.applyMyanmarFeature(gsub, scriptTag, langTag, "ccmp", true,
    nextBit)
  if not buf.reorderMyanmar(sf):
    return
  for t in MyanmarBasicTags:
    buf.applyMyanmarFeature(gsub, scriptTag, langTag, t, true, nextBit)
  buf.clearSyllables()
  for t in MyanmarOtherTags:
    buf.applyMyanmarFeature(gsub, scriptTag, langTag, t, false,
      nextBit)
  const myanmarAutoTags = ["locl", "ccmp", "rphf", "pref", "blwf",
    "pstf", "pres", "abvs", "blws", "psts"]
  var uBit = nextBit
  for f in userFeatures:
    if f.value == 0u32:
      continue
    var covered = false
    for t in myanmarAutoTags:
      if f.tag.toU32() == tagFromStr(t).toU32():
        covered = true
        break
    if covered:
      continue
    let (m, v) = allocMaskBit(uBit, f.value)
    if m == 0u32:
      continue
    let lks = gsubLookupsForTag(gsub, scriptTag, langTag, f.tag.toU32())
    if lks.len == 0:
      continue
    buf.setMasks(v, m, f.start, f.stop)
    buf.applySubstLookups(gsub, lks, m)
  buf.clearSyllables()
