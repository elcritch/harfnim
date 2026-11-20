## Khmer shaper: Coeng/Ro pref reordering and split-matra handling.
##
## Ports harfrust `ot/shaper/khmer.rs` (HarfBuzz main, including the
## linear-time joiner-run guard in the syllable machine). Khmer
## reorders before any GSUB: dotted circles for broken syllables,
## Coeng+Ro pref moves with cfar marking, and left-matra moves, then
## locl/ccmp, the five basic features constrained to syllables, and
## the four other features after clearing syllables.

import std/options

import ../buffer
import ../feature
import ../font
import ../tag
import ../unicode
import ./gsub
import ./indic_table
import ./khmer_machine
import ./map
import ./maskbits
import ./syllabic

export khmer_machine

const
  KhmerPref* = 0
    ## Pref stage index.
  KhmerBlwf* = 1
    ## Blwf stage index.
  KhmerAbvf* = 2
    ## Abvf stage index.
  KhmerPstf* = 3
    ## Pstf stage index.
  KhmerCfar* = 4
    ## Cfar stage index.

  KhmerFeatureTags*: array[9, string] = ["pref", "blwf", "abvf", "pstf",
    "cfar", "pres", "abvs", "blws", "psts"]
    ## Feature tag per shaping stage.
  KhmerGlobalFeature*: array[9, bool] = [false, false, false, false,
    false, true, true, true, true]
    ## Whether each stage applies buffer-wide.

type
  KhmerShapePlan* = object
    lookups*: array[9, seq[uint16]]
    ## Feature lookups per shaping stage.
    maskArray*: array[9, uint32]
    ## Masks per shaping stage.
    nextBit*: uint32
    ## Next free mask bit.

proc lookupsForTagScript(gsub: GsubData, scriptTag, langTag: Tag,
    tagStr: string): seq[uint16] =
  # Resolves lookups for one tag under the shaping script.
  gsubLookupsForTag(gsub, scriptTag, langTag, tagFromStr(tagStr).toU32())

proc newKhmerShapePlan*(gsub: GsubData, scriptTag, langTag: Tag): KhmerShapePlan =
  ## Builds per-shape state: feature lookups resolved once plus mask
  ## bits for the five per-position basic features.
  let langOpt = gsubLangSys(gsub, scriptTag, langTag)
  if langOpt.isNone:
    var nextBit0 = 8u32
    for i in 0 ..< 9:
      if KhmerGlobalFeature[i]:
        result.maskArray[i] = 0u32
      else:
        let (m, _) = allocMaskBit(nextBit0, 1u32)
        result.maskArray[i] = m
    result.nextBit = nextBit0
    return
  let lang = langOpt.get
  for i in 0 ..< 9:
    result.lookups[i] = gsubLookupsForLang(gsub, lang,
      tagFromStr(KhmerFeatureTags[i]).toU32())
  var nextBit = 8u32
  for i in 0 ..< 9:
    if KhmerGlobalFeature[i]:
      result.maskArray[i] = 0u32
    else:
      let (m, _) = allocMaskBit(nextBit, 1u32)
      result.maskArray[i] = m
  result.nextBit = nextBit

proc khmerCategory*(g: GlyphInfo): uint8 =
  ## Syllabic category attached during setup (same var slot as Indic).
  g.otShaperCategory()

proc setKhmerCategory*(g: var GlyphInfo, v: uint8) =
  ## Writes the Khmer category byte.
  g.setOtShaperCategory(v)

proc khmerDecompose*(ab: uint32): Option[tuple[a, b: uint32]] =
  ## Split-matra decomposition for codepoints without Unicode data.
  case ab
  of 0x17BEu32, 0x17BFu32, 0x17C0u32, 0x17C4u32, 0x17C5u32:
    some((0x17C1u32, ab))
  else:
    decomposeImpl(ab)

proc khmerCompose*(a, b: uint32): Option[uint32] =
  ## Avoids recomposing split matras.
  if generalCategoryFor(a).isMark():
    return none(uint32)
  composeImpl(a, b)

proc setupKhmerProperties*(buf: var Buffer) =
  ## Attaches the Indic-derived syllabic category to every glyph.
  ## Runs on codepoints, before glyph mapping.
  for i in 0 ..< min(buf.len, buf.info.len):
    let (cat, _) = getCategories(buf.info[i].glyphId)
    buf.info[i].setKhmerCategory(cat)

proc setupSyllablesKhmer*(buf: var Buffer) =
  ## GSUB-pause callback: finds syllables, records over-long cuts,
  ## then marks every syllable unsafe to break across.
  findSyllablesKhmer(buf)
  var start = 0
  var stop = buf.nextSyllable(0)
  while start < buf.len and buf.successful:
    buf.recordSyllableCut(start, stop)
    buf.unsafeToBreakRange(some(start), some(stop))
    start = stop
    stop = buf.nextSyllable(start)

proc rotateRight(buf: var Buffer, first, last, n: int): bool =
  # Rotates infos [first..last] right by n (n <= last-first).
  if n <= 0 or last <= first or first < 0 or last > buf.info.len:
    buf.indexFailed()
    return false
  if n > last - first:
    buf.indexFailed()
    return false
  var tmp = newSeq[GlyphInfo](n)
  for k in 0 ..< n:
    tmp[k] = buf.info[last - n + k]
  for k in countdown(last - n - 1, first):
    buf.info[k + n] = buf.info[k]
  for k in 0 ..< n:
    buf.info[first + k] = tmp[k]
  true

proc reorderConsonantSyllable(buf: var Buffer, plan: KhmerShapePlan,
    start, stop: int): bool =
  if start < 0 or stop > buf.len or stop > buf.info.len or start >= stop:
    buf.indexFailed()
    return false
  let mask = plan.maskArray[KhmerBlwf] or plan.maskArray[KhmerAbvf] or
    plan.maskArray[KhmerPstf]
  for i in start + 1 ..< stop:
    buf.info[i].mask = buf.info[i].mask or mask
  var numCoengs = 0
  var i = start + 1
  while i < stop:
    let cat = buf.info[i].khmerCategory()
    if cat == OtH and numCoengs < 2 and i + 1 < stop:
      inc numCoengs
      if buf.info[i + 1].khmerCategory() == OtRa:
        buf.info[i].mask = buf.info[i].mask or plan.maskArray[KhmerPref]
        buf.info[i + 1].mask = buf.info[i + 1].mask or
          plan.maskArray[KhmerPref]
        buf.mergeClusters(start, i + 2)
        if not buf.rotateRight(start, i + 2, 2):
          return false
        if plan.maskArray[KhmerCfar] != 0u32:
          for j in i + 2 ..< stop:
            buf.info[j].mask = buf.info[j].mask or
              plan.maskArray[KhmerCfar]
        numCoengs = 2
    elif cat == OtVPre:
      buf.mergeClusters(start, i + 1)
      if not buf.rotateRight(start, i + 1, 1):
        return false
    inc i
  true

proc reorderSyllableKhmer(buf: var Buffer, plan: KhmerShapePlan,
    start, stop: int): bool =
  if start < 0 or start >= buf.info.len or stop > buf.info.len:
    buf.indexFailed()
    return false
  case buf.info[start].syllable() and 0x0Fu8
  of 0u8, 1u8:
    buf.reorderConsonantSyllable(plan, start, stop)
  else:
    true

proc reorderKhmer*(buf: var Buffer, sf: ShaperFont,
    plan: KhmerShapePlan): bool =
  ## GSUB-pause callback: dotted-circle insertion for broken
  ## syllables, then per-syllable Coeng/Ro and left-matra reordering.
  if buf.insertDottedCircles(sf, uint8(ord(BrokenCluster)),
      OtDottedCircle, some(OtRepha), none(uint8)):
    discard
  if not buf.successful:
    return false
  var start = 0
  var stop = buf.nextSyllable(0)
  while start < buf.len and buf.successful:
    if not buf.reorderSyllableKhmer(plan, start, stop):
      return false
    start = stop
    stop = buf.nextSyllable(start)
  buf.successful

proc applyKhmerFeature(buf: var Buffer, gsub: GsubData,
    lookups: seq[uint16], mask: uint32, isGlobal: bool,
    plan: var KhmerShapePlan) =
  ## Applies one shaping feature constrained to syllables. Global
  ## features get a fresh buffer-wide mask; per-position features use
  ## the masks tagged during reordering.
  if lookups.len == 0:
    return
  if isGlobal:
    let (m, v) = allocMaskBit(plan.nextBit, 1u32)
    if m == 0u32:
      return
    buf.setMasks(v, m, GlobalStart, GlobalEnd)
    buf.applySubstLookups(gsub, lookups, m, true)
  else:
    if mask == 0u32:
      return
    buf.applySubstLookups(gsub, lookups, mask, true)

proc applyKhmerGsub*(buf: var Buffer, sf: ShaperFont, gsub: GsubData,
    scriptTag, langTag: Tag, userFeatures: openArray[Feature],
    plan: var KhmerShapePlan) =
  ## Full Khmer GSUB: syllable setup and reordering first (masks for
  ## the basic features), then locl/ccmp/clig, the five basic stages,
  ## then the four other stages after clearing syllables.
  buf.setupSyllablesKhmer()
  if not buf.successful:
    return
  if not buf.reorderKhmer(sf, plan):
    return
  buf.applyKhmerFeature(gsub,
    lookupsForTagScript(gsub, scriptTag, langTag, "locl"), 0u32, true,
    plan)
  buf.applyKhmerFeature(gsub,
    lookupsForTagScript(gsub, scriptTag, langTag, "ccmp"), 0u32, true,
    plan)
  buf.applyKhmerFeature(gsub,
    lookupsForTagScript(gsub, scriptTag, langTag, "clig"), 0u32, true,
    plan)
  for i in 0 ..< 5:
    buf.applyKhmerFeature(gsub, plan.lookups[i], plan.maskArray[i],
      KhmerGlobalFeature[i], plan)
  buf.clearSyllables()
  for i in 5 ..< 9:
    buf.applyKhmerFeature(gsub, plan.lookups[i], plan.maskArray[i],
      KhmerGlobalFeature[i], plan)
  const khmerAutoTags = ["locl", "ccmp", "clig", "pref", "blwf", "abvf",
    "pstf", "cfar", "pres", "abvs", "blws", "psts", "liga"]
  var uBit = plan.nextBit
  for f in userFeatures:
    if f.value == 0u32:
      continue
    var covered = false
    for t in khmerAutoTags:
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
