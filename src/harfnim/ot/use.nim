## Universal Shaping Engine: reph/pref recording and post-base reordering.
##
## Ports harfrust `ot/shaper/use_.rs` (HarfBuzz main, including the
## segment-begin linear-time guard and generic-base topographical
## handling). Syllables are found first with rphf and topographical
## masks tagged upfront; locl/ccmp/nukt/akhn, rphf, pref, and the
## seven basic features apply per syllable; reordering moves repha
## and pre-base marks; topographical and other features finish
## after clearing syllables.

import std/options

import ../buffer
import ../feature
import ../font
import ../tag
import ../unicode
import ./gsub
import ./map
import ./maskbits
import ./syllabic
import ./use_machine
import ./use_table
import ./vowel_constraints

export use_machine
export use_table

const
  UseBasicTags*: array[7, string] = ["rkrf", "abvf", "blwf", "half",
    "pstf", "vatu", "cjct"]
    ## Orthographic-unit features applied per syllable.
  UseTopoTags*: array[4, string] = ["isol", "init", "medi", "fina"]
    ## Topographical features with pre-tagged masks.
  UseOtherTags*: array[5, string] = ["abvs", "blws", "haln", "pres",
    "psts"]
    ## Standard typographic features applied globally.

type
  UseShapePlan* = object
    rphfMask*: uint32
    ## Pre-tagged mask for the reordering-group rphf.
    topoMasks*: array[4, uint32]
    ## Pre-tagged masks for isol/init/medi/fina.
    nextBit*: uint32
    ## Next free mask bit.

proc newUseShapePlan*(): UseShapePlan =
  ## Allocates the rphf plus four topographical mask bits.
  var nextBit = 8u32
  let (rphf, _) = allocMaskBit(nextBit, 1u32)
  result.rphfMask = rphf
  for i in 0 ..< 4:
    let (m, _) = allocMaskBit(nextBit, 1u32)
    result.topoMasks[i] = m
  result.nextBit = nextBit

proc useCategory*(g: GlyphInfo): uint8 =
  ## USE category attached during setup.
  g.otShaperCategory()

proc setUseCategory*(g: var GlyphInfo, v: uint8) =
  ## Writes the USE category byte.
  g.setOtShaperCategory(v)

proc isHalantUse*(g: GlyphInfo): bool =
  ## True for halant-like glyphs, ignoring ligated ones.
  let c = g.useCategory()
  (c == UseH or c == UseHVM or c == UseIS) and not g.ligated()

proc useCompose*(a, b: uint32): Option[uint32] =
  ## Avoids recomposing split matras.
  if generalCategoryFor(a).isMark():
    return none(uint32)
  composeImpl(a, b)

proc preprocessUse*(buf: var Buffer) =
  ## Vowel-constraint splits on codepoints, pre-normalize.
  buf.preprocessVowelConstraints()

proc catFlag(c: uint8): uint32 =
  ## Single category bit, zero past 31.
  if c < 32u8: 1u32 shl c else: 0u32

proc catFlag64(c: uint8): uint64 =
  ## Single category bit in 64-bit space.
  if c < 64u8: 1u64 shl c else: 0u64

proc postBaseFlags(): uint64 =
  # Union of post-base categories that stop a forward repha move.
  catFlag64(UseFAbv) or catFlag64(UseFBlw) or catFlag64(UseFPst) or
    catFlag64(UseFMAbv) or catFlag64(UseFMBlw) or
    catFlag64(UseFMPst) or catFlag64(UseMAbv) or catFlag64(UseMBlw) or
    catFlag64(UseMPst) or catFlag64(UseMPre) or catFlag64(UseVAbv) or
    catFlag64(UseVBlw) or catFlag64(UseVPst) or catFlag64(UseVPre) or
    catFlag64(UseVMAbv) or catFlag64(UseVMBlw) or
    catFlag64(UseVMPst) or catFlag64(UseVMPre)

proc clearSubstitutedFlags(buf: var Buffer) =
  # Clears the substituted bit so recording only sees the immediately
  # preceding feature (mirrors harfrust clear_substitution_flags).
  for i in 0 ..< min(buf.len, buf.info.len):
    buf.info[i].setGlyphProps(buf.info[i].glyphProps() and
      not GlyphPropSubstituted)

proc setupRphfMask(buf: var Buffer, plan: UseShapePlan) =
  ## Tags the first glyph (repha) or first three glyphs of every
  ## syllable with the rphf mask.
  let mask = plan.rphfMask
  if mask == 0u32:
    return
  var start = 0
  var stop = buf.nextSyllable(0)
  while start < buf.len and buf.successful:
    if start >= buf.info.len:
      buf.indexFailed()
      return
    let limit =
      if buf.info[start].useCategory() == UseR: 1
      else: min(3, stop - start)
    for i in start ..< min(start + limit, buf.info.len):
      buf.info[i].mask = buf.info[i].mask or mask
    start = stop
    stop = buf.nextSyllable(start)

proc setupTopographicalMasks(buf: var Buffer, plan: UseShapePlan) =
  ## Tags isol/init/medi/fina masks per joining form. Generic bases
  ## (R/CS followed by GB) never join; hieroglyph and symbol clusters
  ## break joining; ZWNJ retains inside the preceding syllable.
  var allMasks = 0u32
  for i in 0 ..< 4:
    allMasks = allMasks or plan.topoMasks[i]
  if allMasks == 0u32:
    return
  let otherMasks = not allMasks
  var lastStart = 0
  var lastForm = -1
  var start = 0
  var stop = buf.nextSyllable(0)
  while start < buf.len and buf.successful:
    if start >= buf.info.len:
      buf.indexFailed()
      return
    var syllable = buf.info[start].syllable() and 0x0Fu8
    var base = start
    if base < buf.info.len and (buf.info[base].useCategory() == UseR or
        buf.info[base].useCategory() == UseCS):
      inc base
    if base < stop and base < buf.info.len and
        buf.info[base].useCategory() == UseGB:
      syllable = uint8(ord(NonCluster))
    if syllable == uint8(ord(HieroglyphCluster)) or
        syllable == uint8(ord(NonCluster)) or
        syllable == uint8(ord(SymbolCluster)):
      if lastForm != -1:
        buf.unsafeToConcatRange(some(lastStart), some(stop))
      lastForm = -1
    else:
      let join = lastForm == 3 or lastForm == 0
      buf.unsafeToConcatRange(some(lastStart), some(stop))
      if join:
        buf.unsafeToBreakRange(some(lastStart), some(stop))
        let form = if lastForm == 3: 2 else: 1
        for i in lastStart ..< min(start, buf.info.len):
          buf.info[i].mask = (buf.info[i].mask and otherMasks) or
            plan.topoMasks[form]
      let form = if join: 3 else: 0
      lastForm = form
      for i in start ..< min(stop, buf.info.len):
        buf.info[i].mask = (buf.info[i].mask and otherMasks) or
          plan.topoMasks[form]
    var hasZwnj = false
    for i in start ..< min(stop, buf.info.len):
      if buf.info[i].useCategory() == UseZWNJ:
        hasZwnj = true
        break
    if hasZwnj:
      lastForm = -1
    lastStart = start
    start = stop
    stop = buf.nextSyllable(start)

proc setupSyllablesUse*(buf: var Buffer, plan: UseShapePlan) =
  ## GSUB-pause callback: finds syllables, records over-long cuts,
  ## marks breaks unsafe, then tags rphf and topographical masks.
  findSyllablesUse(buf)
  var start = 0
  var stop = buf.nextSyllable(0)
  while start < buf.len and buf.successful:
    buf.recordSyllableCut(start, stop)
    buf.unsafeToBreakRange(some(start), some(stop))
    start = stop
    stop = buf.nextSyllable(start)
  buf.setupRphfMask(plan)
  buf.setupTopographicalMasks(plan)

proc recordRphfUse(buf: var Buffer, plan: UseShapePlan) =
  ## Marks a substituted rphf glyph as repha for reordering.
  let mask = plan.rphfMask
  if mask == 0u32:
    return
  var start = 0
  var stop = buf.nextSyllable(0)
  while start < buf.len and buf.successful:
    for i in start ..< min(stop, buf.info.len):
      if (buf.info[i].mask and mask) == 0u32:
        break
      if buf.info[i].substituted():
        buf.info[i].setUseCategory(UseR)
        break
    start = stop
    stop = buf.nextSyllable(start)

proc recordPrefUse(buf: var Buffer) =
  ## Marks a substituted pref glyph as pre-base vowel behaviour.
  var start = 0
  var stop = buf.nextSyllable(0)
  while start < buf.len and buf.successful:
    for i in start ..< min(stop, buf.info.len):
      if buf.info[i].substituted():
        buf.info[i].setUseCategory(UseVPre)
        break
    start = stop
    stop = buf.nextSyllable(start)

proc rotateLeft(buf: var Buffer, first, last: int): bool =
  # Rotates infos [first..last] left by one.
  if last <= first or first < 0 or last >= buf.info.len:
    buf.indexFailed()
    return false
  let tmp = buf.info[first]
  for k in first ..< last:
    buf.info[k] = buf.info[k + 1]
  buf.info[last] = tmp
  true

proc rotateRight(buf: var Buffer, first, last: int): bool =
  # Rotates infos [first..last] right by one.
  if last <= first or first < 0 or last >= buf.info.len:
    buf.indexFailed()
    return false
  let tmp = buf.info[last]
  for k in countdown(last, first + 1):
    buf.info[k] = buf.info[k - 1]
  buf.info[first] = tmp
  true

proc reorderSyllableUse*(buf: var Buffer, start, stop: int): bool =
  if start < 0 or start >= buf.info.len or stop > buf.info.len or
      start >= stop:
    buf.indexFailed()
    return false
  let syllable = buf.info[start].syllable() and 0x0Fu8
  const reorderMask = (1u32 shl uint32(ord(ViramaTerminatedCluster))) or
    (1u32 shl uint32(ord(SakotTerminatedCluster))) or
    (1u32 shl uint32(ord(StandardCluster))) or
    (1u32 shl uint32(ord(SymbolCluster))) or
    (1u32 shl uint32(ord(BrokenCluster)))
  if ((1u32 shl syllable) and reorderMask) == 0u32:
    return true
  let flags = postBaseFlags()
  if buf.info[start].useCategory() == UseR and stop - start > 1:
    var i = start + 1
    while i < stop:
      let cat = buf.info[i].useCategory()
      let isPostBase = ((catFlag64(cat) and flags) != 0u64) or
        buf.info[i].isHalantUse()
      if isPostBase or i == stop - 1:
        var m = i
        if isPostBase:
          dec m
        buf.mergeClusters(start, m + 1)
        if not buf.rotateLeft(start, m):
          return false
        break
      inc i
  var j = start
  for i in start ..< stop:
    let cat = buf.info[i].useCategory()
    if buf.info[i].isHalantUse():
      j = i + 1
    elif ((catFlag(cat) and (catFlag(UseVPre) or
        catFlag(UseVMPre))) != 0u32) and buf.info[i].ligComp() == 0u8 and
        j < i:
      buf.mergeClusters(j, i + 1)
      if not buf.rotateRight(j, i):
        return false
  true

proc reorderUse*(buf: var Buffer, sf: ShaperFont): bool =
  ## GSUB-pause callback: dotted-circle insertion for broken
  ## syllables, then per-syllable repha and pre-base reordering.
  if buf.insertDottedCircles(sf, uint8(ord(BrokenCluster)), UseB,
      some(UseR), none(uint8)):
    discard
  if not buf.successful:
    return false
  var start = 0
  var stop = buf.nextSyllable(0)
  while start < buf.len and buf.successful:
    if not buf.reorderSyllableUse(start, stop):
      return false
    start = stop
    stop = buf.nextSyllable(start)
  buf.successful

proc applyUseFeature(buf: var Buffer, gsub: GsubData, scriptTag,
    langTag: Tag, tagStr: string, mask: uint32, fresh: bool,
    perSyllable: bool, nextBit: var uint32) =
  ## Applies one automatic feature: fresh allocates a buffer-wide
  ## mask, otherwise the pre-tagged mask is used.
  let lookups = gsubLookupsForTag(gsub, scriptTag, langTag,
    tagFromStr(tagStr).toU32())
  if lookups.len == 0:
    return
  if fresh:
    let (m, v) = allocMaskBit(nextBit, 1u32)
    if m == 0u32:
      return
    buf.setMasks(v, m, GlobalStart, GlobalEnd)
    buf.applySubstLookups(gsub, lookups, m, perSyllable)
  else:
    if mask == 0u32:
      return
    buf.applySubstLookups(gsub, lookups, mask, perSyllable)

proc applyUseGsub*(buf: var Buffer, sf: ShaperFont, gsub: GsubData,
    scriptTag, langTag: Tag, userFeatures: openArray[Feature],
    plan: var UseShapePlan) =
  ## Full USE GSUB: syllable setup with rphf/topographical masks,
  ## pre-processing group, reordering group with recording, basic
  ## group, reordering, topographical and other groups, user
  ## features.
  buf.setupSyllablesUse(plan)
  if not buf.successful:
    return
  buf.applyUseFeature(gsub, scriptTag, langTag, "locl", 0u32, true,
    true, plan.nextBit)
  buf.applyUseFeature(gsub, scriptTag, langTag, "ccmp", 0u32, true,
    true, plan.nextBit)
  buf.applyUseFeature(gsub, scriptTag, langTag, "nukt", 0u32, true,
    true, plan.nextBit)
  buf.applyUseFeature(gsub, scriptTag, langTag, "akhn", 0u32, true,
    true, plan.nextBit)
  buf.clearSubstitutedFlags()
  buf.applyUseFeature(gsub, scriptTag, langTag, "rphf", plan.rphfMask,
    false, true, plan.nextBit)
  buf.recordRphfUse(plan)
  buf.clearSubstitutedFlags()
  buf.applyUseFeature(gsub, scriptTag, langTag, "pref", 0u32, true,
    true, plan.nextBit)
  buf.recordPrefUse()
  for t in UseBasicTags:
    buf.applyUseFeature(gsub, scriptTag, langTag, t, 0u32, true, true,
      plan.nextBit)
  if not buf.reorderUse(sf):
    return
  buf.clearSyllables()
  for i in 0 ..< 4:
    buf.applyUseFeature(gsub, scriptTag, langTag, UseTopoTags[i],
      plan.topoMasks[i], false, false, plan.nextBit)
  for t in UseOtherTags:
    buf.applyUseFeature(gsub, scriptTag, langTag, t, 0u32, true,
      false, plan.nextBit)
  const useAutoTags = ["locl", "ccmp", "nukt", "akhn", "rphf", "pref",
    "rkrf", "abvf", "blwf", "half", "pstf", "vatu", "cjct", "isol",
    "init", "medi", "fina", "abvs", "blws", "haln", "pres", "psts"]
  var uBit = plan.nextBit
  for f in userFeatures:
    if f.value == 0u32:
      continue
    var covered = false
    for t in useAutoTags:
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
