## Shaper dispatch: script-to-shaper routing and shared predicates.
##
## Ports the `categorize` routing from harfrust `ot/shaper/mod.rs`
## plus the preferred script-tag resolution (`all_tags_from_script`):
## Indic scripts and Myanmar resolve to their current-spec xxx2 tags
## (with xxx3 tried first, routing Indic xxx3 fonts to USE) before
## falling back to the old tag and DFLT.

import std/options

import ../direction
import ../script
import ../tag
import ./map

type
  ShaperKind* = enum
    skDefault
    skArabic
    skHebrew
    skHangul
    skThai
    skIndic
    skKhmer
    skMyanmar
    skUse

proc gsubScriptTagFor*(gsub: GsubData, scriptTag: Tag): Option[Tag] =
  ## The GSUB script record tag that `scriptTag` resolves to: the exact
  ## script when present, else the DFLT record, else none.
  for s in gsub.scripts:
    if s.tag == scriptTag.toU32():
      return some(fromU32(s.tag))
  let dflt = defaultScriptTag().toU32()
  for s in gsub.scripts:
    if s.tag == dflt:
      return some(fromU32(s.tag))
  none(Tag)

proc newTagFor*(script: Script): Option[Tag] =
  ## Current-spec OT script tag (xxx2) for the nine Indic scripts
  ## plus Myanmar, mirroring harfrust `new_tag_from_script`. Others
  ## have no new tag.
  if script == Bengali:
    some(tagFromStr("bng2"))
  elif script == Devanagari:
    some(tagFromStr("dev2"))
  elif script == Gujarati:
    some(tagFromStr("gjr2"))
  elif script == Gurmukhi:
    some(tagFromStr("gur2"))
  elif script == Kannada:
    some(tagFromStr("knd2"))
  elif script == Malayalam:
    some(tagFromStr("mlm2"))
  elif script == Oriya:
    some(tagFromStr("ory2"))
  elif script == Tamil:
    some(tagFromStr("tml2"))
  elif script == Telugu:
    some(tagFromStr("tel2"))
  elif script == Myanmar:
    some(tagFromStr("mym2"))
  else:
    none(Tag)

proc preferredScriptTags*(script: Script, oldTag: Tag): seq[Tag] =
  ## OpenType script tags from most to least preferred, mirroring
  ## harfrust `all_tags_from_script`: the xxx3 variant (except
  ## Myanmar, which has no xxx3), then xxx2, then the old tag.
  result = @[]
  let nt = newTagFor(script)
  if nt.isSome:
    if nt.get != tagFromStr("mym2"):
      var b3 = nt.get.toU32()
      b3 = (b3 and 0xFFFFFF00u32) or 0x33u32
      result.add(fromU32(b3))
    result.add(nt.get)
  result.add(oldTag)

proc chooseGsubScript*(gsub: GsubData, script: Option[Script],
    oldTag: Tag): Tag =
  ## Resolves the shaping script tag against the font: the first
  ## preferred tag present in GSUB, else DFLT when present, else the
  ## old tag (preserving the previous no-table behaviour).
  if script.isSome:
    for t in preferredScriptTags(script.get, oldTag):
      for s in gsub.scripts:
        if s.tag == t.toU32():
          return t
  let dflt = defaultScriptTag()
  for s in gsub.scripts:
    if s.tag == dflt.toU32():
      return dflt
  oldTag

proc isDfltOrLatn(t: Tag): bool =
  # True for DFLT or latn script records.
  t == defaultScriptTag() or t == tagFromStr("latn")

proc isIndy3(t: Tag): bool =
  # True for xxx3 Indic script records routed to USE.
  (t.toU32() and 0xFFu32) == 0x33u32

proc categorizeShaper*(script: Option[Script], isHorizontal: bool,
    gsubScript: Option[Tag] = none(Tag)): ShaperKind =
  ## Mirrors harfrust `categorize`. Indic-family scripts fall back to
  ## the default shaper when the font only targets DFLT/latn (or,
  ## for Indic, route to USE for `xxx3` script tags), matching the
  ## "designer designed for DFLT" rule.
  if script.isNone:
    return skDefault
  let s = script.get
  if s == Arabic or s == Syriac:
    # Arabic fallback shaping applies to horizontal layout only;
    # vertical text uses the generic shaper.
    if isHorizontal:
      return skArabic
    return skDefault
  if s == Thai or s == Lao:
    return skThai
  if s == Hangul:
    return skHangul
  if s == Hebrew:
    return skHebrew
  if s == Bengali or s == Devanagari or s == Gujarati or s == Gurmukhi or
      s == Kannada or s == Malayalam or s == Oriya or s == Tamil or
      s == Telugu:
    if gsubScript.isNone or isDfltOrLatn(gsubScript.get):
      return skDefault
    if isIndy3(gsubScript.get):
      return skUse
    return skIndic
  if s == Khmer:
    return skKhmer
  if s == Myanmar:
    if gsubScript.isNone or isDfltOrLatn(gsubScript.get) or
        gsubScript.get == tagFromStr("mymr"):
      return skDefault
    return skMyanmar
  if s == MyanmarZawgyi:
    # The Zawgyi shaper is default-like (legacy encoding, no OT
    # features); keep it on the default path.
    return skDefault
  # USE catch-all, mirroring harfrust: Tibetan, Mongolian, Sinhala,
  # Buhid, Hanunoo, Tagalog, Tagbanwa, Limbu, TaiLe, Buginese,
  # Kharoshthi, SylotiNagri, Tifinagh, Balinese, Nko, PhagsPa, Cham,
  # KayahLi, Lepcha, Rejang, Saurashtra, Sundanese,
  # EgyptianHieroglyphs, Javanese, Kaithi, MeeteiMayek, TaiTham,
  # TaiViet, Batak, Brahmi, Mandaic, Chakma, Miao, Sharada, Takri,
  # Duployan, Grantha, Khojki, Khudawadi, Mahajani, Manichaean, Modi,
  # PahawhHmong, PsalterPahlavi, Siddham, Tirhuta, Ahom, Multani,
  # Adlam, Bhaiksuki, Marchen, Newa, MasaramGondi, Soyombo,
  # ZanabazarSquare, Dogra, GunjalaGondi, HanifiRohingya, Makasar,
  # Medefaidrin, OldSogdian, Sogdian, Elymaic, Nandinagari,
  # NyiakengPuachueHmong, Wancho, Chorasmian, DivesAkuru,
  # KhitanSmallScript, Yezidi, CyproMinoan, OldUyghur, Tangsa, Toto,
  # Vithkuqi, Kawi, NagMundari, Garay, GurungKhema, KiratRai, OlOnal,
  # Sunuwar, Todhri, TuluTigalari, BeriaErfe, Sidetic, TaiYo,
  # TolongSiki, Jurchen, ProtoCuneiform, Seal.
  if s == Tibetan or s == Mongolian or s == Sinhala or s == Buhid or
      s == Hanunoo or s == Tagalog or s == Tagbanwa or s == Limbu or
      s == TaiLe or s == Buginese or s == Kharoshthi or
      s == SylotiNagri or s == Tifinagh or s == Balinese or s == Nko or
      s == PhagsPa or s == Cham or s == KayahLi or s == Lepcha or
      s == Rejang or s == Saurashtra or s == Sundanese or
      s == EgyptianHieroglyphs or s == Javanese or s == Kaithi or
      s == MeeteiMayek or s == TaiTham or s == TaiViet or s == Batak or
      s == Brahmi or s == Mandaic or s == Chakma or s == Miao or
      s == Sharada or s == Takri or s == Duployan or s == Grantha or
      s == Khojki or s == Khudawadi or s == Mahajani or s == Manichaean or
      s == Modi or s == PahawhHmong or s == PsalterPahlavi or
      s == Siddham or s == Tirhuta or s == Ahom or s == Multani or
      s == Adlam or s == Bhaiksuki or s == Marchen or s == Newa or
      s == MasaramGondi or s == Soyombo or s == ZanabazarSquare or
      s == Dogra or s == GunjalaGondi or s == HanifiRohingya or
      s == Makasar or s == Medefaidrin or s == OldSogdian or
      s == Sogdian or s == Elymaic or s == Nandinagari or
      s == NyiakengPuachueHmong or s == Wancho or s == Chorasmian or
      s == DivesAkuru or s == KhitanSmallScript or s == Yezidi or
      s == CyproMinoan or s == OldUyghur or s == Tangsa or s == Toto or
      s == Vithkuqi or s == Kawi or s == NagMundari or s == Garay or
      s == GurungKhema or s == KiratRai or s == OlOnal or s == Sunuwar or
      s == Todhri or s == TuluTigalari or s == BeriaErfe or s == Sidetic or
      s == TaiYo or s == TolongSiki or s == Jurchen or
      s == ProtoCuneiform or s == Seal:
    if gsubScript.isNone or isDfltOrLatn(gsubScript.get):
      return skDefault
    return skUse
  skDefault

proc gposHasMark*(gpos: GposData, scriptTag, langTag: Tag): bool =
  ## Whether the `mark` feature resolves to lookups for the script.
  ## Mirrors harfrust `plan.has_gpos_mark` (used to gate Hebrew
  ## presentation-form composition).
  gposLookupsForTag(gpos, scriptTag, langTag,
    tagFromStr("mark").toU32()).len > 0
