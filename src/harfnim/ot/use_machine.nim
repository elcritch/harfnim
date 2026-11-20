## USE syllable machine: Ragel-table interpreter that tags each
## glyph with its syllable (`serial << 4 | kind`).
##
## Ports harfrust `ot/shaper/use_machine.rs`. The transition lookup
## follows the flat `char_class` / `indices` / `index_defaults` backend
## of that file; the driver loop, look-ahead memo and cond-action
## dispatch mirror `khmer_machine.nim`.

import ../buffer
import ./use_machine_data

type
  SyllableType* = enum
    ## USE syllable shape. Note `IndependentCluster` comes first,
    ## matching harfrust; only the actions below emit the rest.
    IndependentCluster = 0
    ## Independent cluster.
    ViramaTerminatedCluster
    ## Virama terminated cluster.
    SakotTerminatedCluster
    ## Sakot terminated cluster.
    StandardCluster
    ## Standard cluster.
    NumberJoinerTerminatedCluster
    ## Number joiner terminated cluster.
    NumeralCluster
    ## Numeral cluster.
    SymbolCluster
    ## Symbol cluster.
    HieroglyphCluster
    ## Hieroglyph cluster.
    BrokenCluster
    ## Broken cluster.
    NonCluster
    ## Non cluster.

  UseSyllableLookaheadMemo* = object
    ## Remembers `(position, machine state)` pairs an earlier token
    ## already scanned through without matching, so a later token that
    ## reaches the same pair can fall back to `te` right away. The
    ## state is `high(uint32)` while unseen. Allocated lazily on the
    ## first look-ahead past `UseMaxSyllableLookahead`.
    seen*: seq[(uint32, uint32)]

proc newUseSyllableLookaheadMemo*(): UseSyllableLookaheadMemo =
  ## Builds an empty memo; the backing store is allocated on first use.
  UseSyllableLookaheadMemo(seen: @[])

proc isDoomedRevisit*(memo: var UseSyllableLookaheadMemo, p, ts, cs,
    len: int): bool =
  ## Returns true when `(p, cs)` was already visited by an earlier
  ## token (one with a smaller start `ts`) and can therefore be cut
  ## short. Otherwise records this visit and returns false.
  if memo.seen.len == 0:
    memo.seen = newSeq[(uint32, uint32)](len)
    for i in 0 ..< len:
      memo.seen[i] = (high(uint32), 0u32)
  if p < 0 or p >= memo.seen.len:
    return false
  let entry = memo.seen[p]
  if entry[0] == uint32(cs) and entry[1] < uint32(ts):
    return true
  memo.seen[p] = (uint32(cs), uint32(ts))
  return false

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

proc categoryAt(buf: Buffer, memo: var UseSyllableLookaheadMemo,
    p, ts, te, cs: int): uint8 =
  # Supplies the scanner look-ahead category. Once the look-ahead has
  # run past `UseMaxSyllableLookahead`, hands the machine a category
  # no rule continues with, which makes it fall back to `te` exactly
  # as an unbounded scan eventually would.
  if p - max(ts, te) >= UseMaxSyllableLookahead and
      memo.isDoomedRevisit(p, ts, cs, buf.len):
    return 0xFFu8
  if p < 0 or p >= buf.info.len:
    return 0xFFu8
  buf.info[p].otShaperCategory()

proc findSyllablesUse*(buf: var Buffer) =
  ## Runs the syllable machine over the buffer, tagging syllables and
  ## setting the broken-syllable scratch flag. Mirrors harfrust
  ## `find_syllables`, including the EOF transition pass.
  var cs = UseStart
  var ts = 0
  var te = 0
  var act = 0
  var p = 0
  let pe = buf.len
  let eof = buf.len
  var syllableSerial = 1u8
  var memo = newUseSyllableLookaheadMemo()
  while p != pe or p == eof:
    if UseFromStateActions[cs] == 3i8:
      ts = p
    var trans = 0
    if p == eof:
      if UseEofTrans[cs] > 0:
        trans = int(UseEofTrans[cs]) - 1
    else:
      let keys = cs shl 1
      let inds = int(UseIndexOffsets[cs])
      trans = int(UseIndexDefaults[cs])
      let cat = categoryAt(buf, memo, p, ts, te, cs)
      if cat <= 56u8:
        let ic = int(UseCharClass[int(cat)])
        if ic >= int(UseTransKeys[keys]) and
            ic <= int(UseTransKeys[keys + 1]):
          trans = int(UseIndices[inds + (ic - int(UseTransKeys[keys]))])
    cs = int(UseCondTargs[trans])
    let cact = UseCondActions[trans]
    if cact != 0i8:
      case cact
      of 7:
        te = p + 1
      of 16:
        te = p + 1
        foundSyllable(buf, ts, te, syllableSerial, ViramaTerminatedCluster)
      of 14:
        te = p + 1
        foundSyllable(buf, ts, te, syllableSerial, SakotTerminatedCluster)
      of 12:
        te = p + 1
        foundSyllable(buf, ts, te, syllableSerial, StandardCluster)
      of 20:
        te = p + 1
        foundSyllable(buf, ts, te, syllableSerial,
          NumberJoinerTerminatedCluster)
      of 18:
        te = p + 1
        foundSyllable(buf, ts, te, syllableSerial, NumeralCluster)
      of 10:
        te = p + 1
        foundSyllable(buf, ts, te, syllableSerial, SymbolCluster)
      of 25:
        te = p + 1
        foundSyllable(buf, ts, te, syllableSerial, HieroglyphCluster)
      of 5:
        te = p + 1
        foundSyllable(buf, ts, te, syllableSerial, BrokenCluster)
        buf.scratchFlags = buf.scratchFlags or ScratchFlagHasBrokenSyllable
      of 4:
        te = p + 1
        foundSyllable(buf, ts, te, syllableSerial, NonCluster)
      of 15:
        te = p
        p = p - 1
        foundSyllable(buf, ts, te, syllableSerial, ViramaTerminatedCluster)
      of 13:
        te = p
        p = p - 1
        foundSyllable(buf, ts, te, syllableSerial, SakotTerminatedCluster)
      of 11:
        te = p
        p = p - 1
        foundSyllable(buf, ts, te, syllableSerial, StandardCluster)
      of 19:
        te = p
        p = p - 1
        foundSyllable(buf, ts, te, syllableSerial,
          NumberJoinerTerminatedCluster)
      of 17:
        te = p
        p = p - 1
        foundSyllable(buf, ts, te, syllableSerial, NumeralCluster)
      of 9:
        te = p
        p = p - 1
        foundSyllable(buf, ts, te, syllableSerial, SymbolCluster)
      of 24:
        te = p
        p = p - 1
        foundSyllable(buf, ts, te, syllableSerial, HieroglyphCluster)
      of 21:
        te = p
        p = p - 1
        foundSyllable(buf, ts, te, syllableSerial, BrokenCluster)
        buf.scratchFlags = buf.scratchFlags or ScratchFlagHasBrokenSyllable
      of 23:
        te = p
        p = p - 1
        foundSyllable(buf, ts, te, syllableSerial, NonCluster)
      of 1:
        p = te - 1
        foundSyllable(buf, ts, te, syllableSerial, SymbolCluster)
      of 22:
        case act
        of 8:
          p = te - 1
          foundSyllable(buf, ts, te, syllableSerial, NonCluster)
        of 9:
          p = te - 1
          foundSyllable(buf, ts, te, syllableSerial, BrokenCluster)
          buf.scratchFlags = buf.scratchFlags or ScratchFlagHasBrokenSyllable
        else:
          discard
      of 6:
        te = p + 1
        act = 8
      of 8:
        te = p + 1
        act = 9
      else:
        discard
    if p == eof:
      # Matches Rust `if cs >= 1 break`: the EOF transition already
      # emitted any pending syllable, so the loop ends either way.
      if cs >= UseFirstFinal:
        break
      break
    else:
      if UseToStateActions[cs] == 2i8:
        ts = 0
      inc p
