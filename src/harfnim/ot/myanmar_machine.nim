## Myanmar syllable machine: Ragel-table interpreter that tags each
## glyph with its syllable (`serial << 4 | kind`).
##
## Ports harfrust `ot/shaper/myanmar_machine.rs`, keeping the generated
## tables verbatim (see `myanmar_machine_data.nim`) and translating the
## Ragel driver loop to Nim.

import ../buffer
import ./myanmar_machine_data

type
  SyllableType* = enum
    ## Myanmar syllable shape.
    ConsonantSyllable = 0
    ## Consonant syllable.
    PunctuationCluster
    ## Punctuation cluster.
    BrokenCluster
    ## Broken cluster.
    NonMyanmarCluster
    ## Non Myanmar cluster.

proc foundSyllable(buf: var Buffer, start, stop: int,
    serial: var uint8, kind: SyllableType) =
  # Tags glyphs [start..stop) with the syllable. Out-of-range ends
  # are clamped (mirroring harfrust's `unwrap_or_default`).
  let s = max(start, 0)
  let e = min(min(stop, buf.len), buf.info.len)
  var i = s
  while i < e:
    buf.info[i].setSyllable((serial shl 4) or uint8(ord(kind)))
    inc i
  inc serial
  if serial == 16u8:
    serial = 1u8

proc findSyllablesMyanmar*(buf: var Buffer) =
  ## Runs the syllable machine over the buffer, tagging syllables and
  ## setting the broken-syllable scratch flag. Mirrors harfrust
  ## `find_syllables_myanmar`, including the EOF transition pass.
  var cs = MyanmarStart
  var ts = 0
  var te = 0
  var act = 0
  var p = 0
  let pe = buf.len
  let eof = buf.len
  var syllableSerial = 1u8
  while p != pe or p == eof:
    case MyanmarFromStateActions[cs]
    of 2:
      ts = p
    else:
      discard
    var trans = 0
    if p == eof:
      if MyanmarEofTrans[cs] > 0:
        trans = int(MyanmarEofTrans[cs]) - 1
    else:
      let keys = cs shl 1
      let inds = int(MyanmarIndexOffsets[cs])
      let cat =
        if p >= 0 and p < buf.info.len: buf.info[p].otShaperCategory()
        else: 0u8
      if cat >= 1u8 and cat <= 57u8:
        let ic = int(MyanmarCharClass[int(cat) - 1])
        if ic <= int(MyanmarTransKeys[keys + 1]) and
            ic >= int(MyanmarTransKeys[keys]):
          trans = int(MyanmarIndices[inds +
            (ic - int(MyanmarTransKeys[keys]))])
        else:
          trans = int(MyanmarIndexDefaults[cs])
      else:
        trans = int(MyanmarIndexDefaults[cs])
    cs = int(MyanmarCondTargs[trans])
    if MyanmarCondActions[trans] != 0:
      case MyanmarCondActions[trans]
      of 8:
        te = p + 1
        foundSyllable(buf, ts, te, syllableSerial, ConsonantSyllable)
      of 4:
        te = p + 1
        foundSyllable(buf, ts, te, syllableSerial, NonMyanmarCluster)
      of 10:
        te = p + 1
        foundSyllable(buf, ts, te, syllableSerial, BrokenCluster)
        buf.scratchFlags = buf.scratchFlags or ScratchFlagHasBrokenSyllable
      of 3:
        te = p + 1
        foundSyllable(buf, ts, te, syllableSerial, NonMyanmarCluster)
      of 7:
        te = p
        p = p - 1
        foundSyllable(buf, ts, te, syllableSerial, ConsonantSyllable)
      of 9:
        te = p
        p = p - 1
        foundSyllable(buf, ts, te, syllableSerial, BrokenCluster)
        buf.scratchFlags = buf.scratchFlags or ScratchFlagHasBrokenSyllable
      of 12:
        te = p
        p = p - 1
        foundSyllable(buf, ts, te, syllableSerial, NonMyanmarCluster)
      of 11:
        case act
        of 2:
          p = te - 1
          foundSyllable(buf, ts, te, syllableSerial, NonMyanmarCluster)
        of 3:
          p = te - 1
          foundSyllable(buf, ts, te, syllableSerial, BrokenCluster)
          buf.scratchFlags = buf.scratchFlags or ScratchFlagHasBrokenSyllable
        else:
          discard
      of 6:
        te = p + 1
        act = 2
      of 5:
        te = p + 1
        act = 3
      else:
        discard
    if p == eof:
      # Both the final-state and the non-final EOF paths leave the
      # driver loop; any pending syllable was already emitted by the
      # transition action above.
      break
    else:
      if MyanmarToStateActions[cs] == 1:
        ts = 0
      inc p
