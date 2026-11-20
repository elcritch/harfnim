## Shared syllabic-shaper helpers: dotted-circle insertion for broken
## syllables, syllable-cut recording for over-long syllables, and
## syllable-var cleanup.
##
## Ported from harfrust `ot/shaper/syllabic.rs`. Used by the
## Indic-family shapers after final reordering.

import std/options

import ../buffer
import ../font

const MaxSyllableLength* = 64
  ## Maximum glyphs per syllable piece; longer runs are cut.

proc insertDottedCircles*(buf: var Buffer, sf: ShaperFont,
    brokenType, dottedCategory: uint8, rephaCategory: Option[uint8],
    dottedPosition: Option[uint8]): bool =
  ## Inserts a dotted circle into every broken syllable
  ## (`syllable & 0x0F == brokenType`). The circle takes the current
  ## glyph's mask, cluster, and syllable, plus `dottedCategory` (and
  ## `dottedPosition` when given). When the broken syllable starts
  ## with a repha, the circle goes after it. Returns false when
  ## skipped or when the font lacks U+25CC.
  if buf.flags.contains(DoNotInsertDottedCircle):
    return false
  if (buf.scratchFlags and ScratchFlagHasBrokenSyllable) == 0u32:
    return false
  let dotted = sf.nominalGlyph(0x25CCu32)
  if dotted.isNone:
    return false
  var circle = GlyphInfo(glyphId: 0x25CCu32, cluster: 0u32)
  circle.setOtShaperCategory(dottedCategory)
  if dottedPosition.isSome:
    circle.setOtShaperAuxiliary(dottedPosition.get)
  circle.glyphId = dotted.get.value
  buf.clearOutput()
  buf.idx = 0
  var lastSyllable = 0u8
  while buf.idx < buf.len and buf.successful:
    if buf.idx >= buf.info.len:
      buf.indexFailed()
      return false
    let syllable = buf.info[buf.idx].syllable()
    if lastSyllable == syllable or (syllable and 0x0Fu8) != brokenType:
      buf.nextGlyph()
      continue
    lastSyllable = syllable
    var ginfo = circle
    if buf.idx < buf.info.len:
      ginfo.cluster = buf.info[buf.idx].cluster
      ginfo.mask = buf.info[buf.idx].mask
      ginfo.setSyllable(buf.info[buf.idx].syllable())
    # Insert the circle after a possible repha.
    if rephaCategory.isSome:
      let rc = rephaCategory.get
      while buf.idx < buf.len and buf.idx < buf.info.len and
          lastSyllable == buf.info[buf.idx].syllable() and
          buf.info[buf.idx].otShaperCategory() == rc:
        buf.nextGlyph()
    buf.outputInfo(ginfo)
  discard buf.sync()
  buf.successful

proc clearSyllables*(buf: var Buffer) =
  ## Resets the syllable byte on every glyph. Runs after shaping no
  ## longer needs syllables (harfrust also deallocates the var; the
  ## harfnim var storage is static, so resetting suffices).
  for i in 0 ..< buf.info.len:
    buf.info[i].setSyllable(0u8)

proc recordSyllableCut*(buf: var Buffer, start, stop: int) =
  ## Records a cut for an over-long syllable so pre- and post-GSUB
  ## walks see the same pieces. Only runs when the piece reaches
  ## `MaxSyllableLength`; shorter pieces and cuts at a syllable
  ## boundary are no-ops. Mirrors harfrust `record_syllable_cut`.
  if stop - start < MaxSyllableLength:
    return
  if start < 0 or start >= buf.len or stop < 0 or stop > buf.len:
    return
  if start >= buf.info.len or stop > buf.info.len:
    buf.indexFailed()
    return
  let syllable = buf.info[start].syllable()
  if stop == buf.len or buf.info[stop].syllable() != syllable:
    return
  var syllableEnd = stop
  while syllableEnd < buf.len and syllableEnd < buf.info.len and
      buf.info[syllableEnd].syllable() == syllable:
    inc syllableEnd
  let prevSerial =
    if start == 0 or start - 1 >= buf.info.len: 0u8
    else: buf.info[start - 1].syllable() shr 4
  let lastSerial = syllable shr 4
  buf.mergeClusters(start, syllableEnd)
  if not buf.successful:
    return
  var serials: array[2, uint8] = [0u8, 0u8]
  var serial = 1u8
  for k in 0 ..< 2:
    while serial == prevSerial or serial == lastSerial:
      inc serial
    serials[k] = serial
    inc serial
  var s = start
  var e = stop
  var j = 0
  while syllableEnd - s > MaxSyllableLength:
    e = s + MaxSyllableLength
    let value = (serials[j] shl 4) or (syllable and 0x0Fu8)
    for i in s ..< min(e, buf.info.len):
      buf.info[i].setSyllable(value)
    s = e
    j = j xor 1
