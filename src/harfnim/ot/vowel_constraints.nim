## Vowel-letter constraints: dotted-circle insertion inside
## vowel sequences that look like another vowel.
##
## Ports harfrust `ot/shaper/vowel_constraints.rs` (generated from
## the USE script development spec). Default ignorables are
## transparent between listed codepoints; matched runs are marked
## unsafe to break in the output buffer.

import std/options

import ../buffer
import ../script
import ../unicode

type
  VowelPair* = tuple[first: uint32, seconds: seq[uint32]]

const
  DevanagariVowels*: seq[VowelPair] = @[
    (0x0905u32, @[0x093Au32, 0x093Bu32, 0x093Eu32, 0x0945u32, 0x0946u32,
      0x0949u32, 0x094Au32, 0x094Bu32, 0x094Cu32, 0x094Fu32, 0x0956u32,
      0x0957u32]),
    (0x0906u32, @[0x093Au32, 0x0945u32, 0x0946u32, 0x0947u32, 0x0948u32]),
    (0x0909u32, @[0x0941u32]),
    (0x090Fu32, @[0x0945u32, 0x0946u32, 0x0947u32]),
  ]
  BengaliVowels*: seq[VowelPair] = @[
    (0x0985u32, @[0x09BEu32]),
    (0x098Bu32, @[0x09C3u32]),
    (0x098Cu32, @[0x09E2u32]),
  ]
  GurmukhiVowels*: seq[VowelPair] = @[
    (0x0A05u32, @[0x0A3Eu32, 0x0A48u32, 0x0A4Cu32]),
    (0x0A72u32, @[0x0A3Fu32, 0x0A40u32, 0x0A47u32]),
    (0x0A73u32, @[0x0A41u32, 0x0A42u32, 0x0A4Bu32]),
  ]
  GujaratiVowels*: seq[VowelPair] = @[
    (0x0A85u32, @[0x0ABEu32, 0x0AC5u32, 0x0AC7u32, 0x0AC8u32, 0x0AC9u32,
      0x0ACBu32, 0x0ACCu32]),
    (0x0AC5u32, @[0x0ABEu32]),
  ]
  OriyaVowels*: seq[VowelPair] = @[
    (0x0B05u32, @[0x0B3Eu32]),
    (0x0B0Fu32, @[0x0B57u32]),
    (0x0B13u32, @[0x0B57u32]),
  ]
  TeluguVowels*: seq[VowelPair] = @[
    (0x0C12u32, @[0x0C4Cu32, 0x0C55u32]),
    (0x0C3Fu32, @[0x0C55u32]),
    (0x0C46u32, @[0x0C55u32]),
    (0x0C4Au32, @[0x0C55u32]),
  ]
  KannadaVowels*: seq[VowelPair] = @[
    (0x0C89u32, @[0x0CBEu32]),
    (0x0C8Bu32, @[0x0CBEu32]),
    (0x0C92u32, @[0x0CCCu32]),
  ]
  MalayalamVowels*: seq[VowelPair] = @[
    (0x0D07u32, @[0x0D57u32]),
    (0x0D09u32, @[0x0D57u32]),
    (0x0D0Eu32, @[0x0D46u32]),
    (0x0D12u32, @[0x0D3Eu32, 0x0D57u32]),
  ]
  SinhalaVowels*: seq[VowelPair] = @[
    (0x0D85u32, @[0x0DCFu32, 0x0DD0u32, 0x0DD1u32]),
    (0x0D8Bu32, @[0x0DDFu32]),
    (0x0D8Fu32, @[0x0DDFu32]),
    (0x0D94u32, @[0x0DDFu32]),
    (0x0D8Du32, @[0x0DD8u32]),
    (0x0D91u32, @[0x0DCAu32, 0x0DD9u32, 0x0DDAu32, 0x0DDCu32, 0x0DDDu32,
      0x0DDEu32]),
  ]
  BrahmiVowels*: seq[VowelPair] = @[
    (0x11005u32, @[0x11038u32]),
    (0x1100Bu32, @[0x1103Eu32]),
    (0x1100Fu32, @[0x11042u32]),
  ]
  KhojkiVowels*: seq[VowelPair] = @[
    (0x11200u32, @[0x1122Cu32, 0x11231u32, 0x11233u32]),
    (0x11206u32, @[0x1122Cu32]),
    (0x1122Cu32, @[0x11230u32, 0x11231u32]),
    (0x11240u32, @[0x1122Eu32]),
  ]
  KhudawadiVowels*: seq[VowelPair] = @[
    (0x112B0u32, @[0x112E0u32, 0x112E5u32, 0x112E6u32, 0x112E7u32,
      0x112E8u32]),
  ]
  TirhutaVowels*: seq[VowelPair] = @[
    (0x11481u32, @[0x114B0u32]),
    (0x1148Bu32, @[0x114BAu32]),
    (0x1148Du32, @[0x114BAu32]),
    (0x114AAu32, @[0x114B5u32, 0x114B6u32]),
  ]
  ModiVowels*: seq[VowelPair] = @[
    (0x11600u32, @[0x11639u32, 0x1163Au32]),
    (0x11601u32, @[0x11639u32, 0x1163Au32]),
  ]
  TakriVowels*: seq[VowelPair] = @[
    (0x11680u32, @[0x116ADu32, 0x116B4u32, 0x116B5u32]),
    (0x11686u32, @[0x116B2u32]),
  ]

proc curGlyph(buf: Buffer, i: int): uint32 =
  ## Reads the codepoint i positions ahead, skipping default
  ## ignorables; 0 matches nothing at end of input.
  var pos = buf.idx
  for _ in 0 ..< i:
    if pos >= buf.len:
      return 0u32
    inc pos
    while pos < buf.len and pos < buf.info.len and
        isDefaultIgnorable(buf.info[pos].glyphId):
      inc pos
  if pos < buf.len and pos < buf.info.len:
    buf.info[pos].glyphId
  else:
    0u32

proc nextConstrainedGlyph(buf: var Buffer) =
  # Advances one glyph, skipping default ignorables.
  if not buf.successful:
    return
  buf.nextGlyph()
  while buf.successful:
    let cur = buf.cur(0)
    if cur == nil:
      break
    if not isDefaultIgnorable(cur[].glyphId):
      break
    buf.nextGlyph()

proc outputDottedCircle(buf: var Buffer) =
  # Emits a dotted circle placeholder with fresh Unicode props.
  buf.outputGlyph(0x25CCu32)
  if not buf.successful:
    return
  let slot = buf.outAt(buf.outLen - 1)
  if slot == nil:
    buf.indexFailed()
    return
  var scratch = buf.scratchFlags
  slot[].initUnicodeProps(scratch)
  buf.scratchFlags = scratch
  slot[].clearContinuation()

proc outputWithDottedCircle(buf: var Buffer) =
  # Emits the current glyph followed by a dotted circle.
  outputDottedCircle(buf)
  nextConstrainedGlyph(buf)

proc preprocessVowelConstraints*(buf: var Buffer) =
  ## Inserts dotted circles into ambiguous vowel sequences for the
  ## Indic and USE scripts, on codepoints pre-normalize. Other
  ## scripts pass through unchanged (clear + sync is identity).
  if buf.flags.contains(DoNotInsertDottedCircle):
    return
  buf.clearOutput()
  if buf.script.isSome:
    let s = buf.script.get
    var table: seq[VowelPair] = @[]
    var isTamilAu = false
    var isDevaRa = false
    if s == Devanagari:
      table = DevanagariVowels
      isDevaRa = true
    elif s == Bengali:
      table = BengaliVowels
    elif s == Gurmukhi:
      table = GurmukhiVowels
    elif s == Gujarati:
      table = GujaratiVowels
    elif s == Oriya:
      table = OriyaVowels
    elif s == Tamil:
      isTamilAu = true
    elif s == Telugu:
      table = TeluguVowels
    elif s == Kannada:
      table = KannadaVowels
    elif s == Malayalam:
      table = MalayalamVowels
    elif s == Sinhala:
      table = SinhalaVowels
    elif s == Brahmi:
      table = BrahmiVowels
    elif s == Khojki:
      table = KhojkiVowels
    elif s == Khudawadi:
      table = KhudawadiVowels
    elif s == Tirhuta:
      table = TirhutaVowels
    elif s == Modi:
      table = ModiVowels
    elif s == Takri:
      table = TakriVowels
    buf.idx = 0
    while buf.idx + 1 < buf.len and buf.successful:
      let start = buf.outLen
      var matched = false
      let c0 = curGlyph(buf, 0)
      if isDevaRa and c0 == 0x0930u32 and curGlyph(buf, 1) == 0x094Du32 and
          buf.idx + 2 < buf.len and curGlyph(buf, 2) == 0x0907u32:
        nextConstrainedGlyph(buf)
        nextConstrainedGlyph(buf)
        outputDottedCircle(buf)
      elif isTamilAu and c0 == 0x0B85u32 and curGlyph(buf, 1) == 0x0BC2u32:
        nextConstrainedGlyph(buf)
        outputDottedCircle(buf)
      else:
        for (first, seconds) in table:
          if c0 != first:
            continue
          let c1 = curGlyph(buf, 1)
          for sc in seconds:
            if c1 == sc:
              matched = true
              break
          if matched:
            break
      nextConstrainedGlyph(buf)
      if matched:
        outputWithDottedCircle(buf)
        buf.unsafeToBreakFromOutbuffer(some(start), some(buf.outLen))
  discard buf.sync()
