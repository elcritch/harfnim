## Khmer syllable machine: Ragel-table interpreter that tags each
## glyph with its syllable (`serial << 4 | kind`).

import ../buffer
import ./khmer_machine_data

type
  SyllableType* = enum
    ## Khmer syllable shape.
    ConsonantSyllable = 0
    ## Consonant syllable.
    BrokenCluster
    ## Broken cluster.
    NonKhmerCluster
    ## Non Khmer cluster.

  SyllableLookaheadMemo* = object
    ## Remembers `(position, machine state)` pairs an earlier token
    ## already scanned through without matching, so a later token that
    ## reaches the same pair can fall back to `te` right away. The
    ## state is `high(uint32)` while unseen. Allocated lazily on the
    ## first look-ahead past `KhmerMaxSyllableLookahead`.
    seen*: seq[(uint32, uint32)]

proc newSyllableLookaheadMemo*(): SyllableLookaheadMemo =
  ## Builds an empty memo; the backing store is allocated on first use.
  SyllableLookaheadMemo(seen: @[])

proc isDoomedRevisit*(memo: var SyllableLookaheadMemo, p, ts, cs,
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

proc categoryAt(buf: Buffer, memo: var SyllableLookaheadMemo,
    p, ts, te, cs: int): uint8 =
  # Supplies the scanner look-ahead category. Once the look-ahead has
  # run past `KhmerMaxSyllableLookahead`, hands the machine a category
  # no rule continues with, which makes it fall back to `te` exactly
  # as an unbounded scan eventually would.
  if p - max(ts, te) >= KhmerMaxSyllableLookahead and
      memo.isDoomedRevisit(p, ts, cs, buf.len):
    return 0xFFu8
  if p < 0 or p >= buf.info.len:
    return 0xFFu8
  buf.info[p].otShaperCategory()

proc findSyllablesKhmer*(buf: var Buffer) =
  ## Runs the syllable machine over the buffer, tagging syllables and
  ## setting the broken-syllable scratch flag. Mirrors harfrust
  ## `find_syllables_khmer`, including the EOF transition pass.
  var cs = KhmerStart
  var ts = 0
  var te = 0
  var act = 0
  var p = 0
  let pe = buf.len
  let eof = buf.len
  var syllableSerial = 1u8
  var memo = newSyllableLookaheadMemo()
  while p != pe or p == eof:
    var acts = int(KhmerFromStateActions[cs])
    var nacts = int(KhmerActions[acts])
    inc acts
    while nacts > 0:
      if KhmerActions[acts] == 1i8:
        ts = p
      dec nacts
      inc acts
    var trans = 0
    if p == eof:
      if KhmerEofTrans[cs] > 0:
        trans = int(KhmerEofTrans[cs]) - 1
    else:
      var keys = int(KhmerKeyOffsets[cs])
      trans = int(KhmerIndexOffsets[cs])
      var klen = int(KhmerSingleLengths[cs])
      var have = 0
      let cat = categoryAt(buf, memo, p, ts, te, cs)
      if klen > 0:
        var lower = keys
        var upper = keys + klen - 1
        while true:
          if upper < lower:
            keys += klen
            trans += klen
            break
          let mid = lower + ((upper - lower) shr 1)
          if cat < KhmerTransKeys[mid]:
            upper = mid - 1
          elif cat > KhmerTransKeys[mid]:
            lower = mid + 1
          else:
            have = 1
            trans += (mid - keys)
            break
      klen = int(KhmerRangeLengths[cs])
      if have == 0 and klen > 0:
        var lower = keys
        var upper = keys + (klen shl 1) - 2
        while true:
          if upper < lower:
            trans += klen
            break
          let mid = lower + (((upper - lower) shr 1) and (not 1))
          if cat < KhmerTransKeys[mid]:
            upper = mid - 2
          elif cat > KhmerTransKeys[mid + 1]:
            lower = mid + 2
          else:
            trans += ((mid - keys) shr 1)
            break
    cs = int(KhmerCondTargs[trans])
    if KhmerCondActions[trans] != 0:
      var cacts = int(KhmerCondActions[trans])
      var cnacts = int(KhmerActions[cacts])
      inc cacts
      while cnacts > 0:
        case KhmerActions[cacts]
        of 2:
          te = p + 1
        of 3:
          act = 2
        of 4:
          act = 3
        of 5:
          te = p + 1
          foundSyllable(buf, ts, te, syllableSerial, NonKhmerCluster)
        of 6:
          te = p
          p = p - 1
          foundSyllable(buf, ts, te, syllableSerial, ConsonantSyllable)
        of 7:
          te = p
          p = p - 1
          foundSyllable(buf, ts, te, syllableSerial, BrokenCluster)
          buf.scratchFlags = buf.scratchFlags or ScratchFlagHasBrokenSyllable
        of 8:
          te = p
          p = p - 1
          foundSyllable(buf, ts, te, syllableSerial, NonKhmerCluster)
        of 9:
          p = te - 1
          foundSyllable(buf, ts, te, syllableSerial, ConsonantSyllable)
        of 10:
          p = te - 1
          foundSyllable(buf, ts, te, syllableSerial, BrokenCluster)
          buf.scratchFlags = buf.scratchFlags or ScratchFlagHasBrokenSyllable
        of 11:
          case act
          of 2:
            p = te - 1
            foundSyllable(buf, ts, te, syllableSerial, BrokenCluster)
            buf.scratchFlags = buf.scratchFlags or ScratchFlagHasBrokenSyllable
          of 3:
            p = te - 1
            foundSyllable(buf, ts, te, syllableSerial, NonKhmerCluster)
          else:
            discard
        else:
          discard
        dec cnacts
        inc cacts
    if p == eof:
      # Matches Rust `if cs >= 21 break`: the EOF transition already
      # emitted any pending syllable, so the loop ends either way.
      if cs >= KhmerFirstFinal:
        break
      break
    else:
      var tacts = int(KhmerToStateActions[cs])
      var tnacts = int(KhmerActions[tacts])
      inc tacts
      while tnacts > 0:
        if KhmerActions[tacts] == 0i8:
          ts = 0
        dec tnacts
        inc tacts
      inc p
