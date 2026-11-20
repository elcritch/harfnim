# Shaping

## Plans and entry points

`src/harfnim/shape.nim` owns orchestration:

* `ShapePlan`: `scriptTag`, `langTag`, `features`.
* `newShapePlan(scriptTag, langTag, features)`: copies features into
  a preallocated seq.
* `shapePlan(font, buf, features)`: guesses segment properties, then
  builds a plan.
* `shapeWithPlan(font, buf, plan)`: runs the full pipeline.
* `shape(font, buf, features = [])`: plans and shapes in one call.

`scriptTagForBuffer` lowercases the ISO 15924 script tag; full HarfBuzz
script mapping is still TODO. `langTagForBuffer` always returns the
default language system.

## Feature model

`src/harfnim/feature.nim` defines `Feature(tag, value, start, stop)`.
`globalFeature` covers the whole buffer. Value 0 disables a feature.

`src/harfnim/ot/maskbits.nim` allocates mask bits above the glyph flag
bits (`allocMaskBit`). Valued features occupy as many bits as needed.
All appliers share this helper.

## Shaper dispatch

`src/harfnim/ot/shaper.nim` maps script plus direction plus the resolved
GSUB script to a `ShaperKind`:

* Arabic and Syriac (horizontal only): Arabic shaper.
* Thai and Lao: Thai shaper.
* Hangul: Hangul shaper.
* Hebrew: Hebrew shaper.
* Indic family: Indic shaper unless the font only targets DFLT or latn
  (then default), with `xxx3` scripts routed to USE. Script tags prefer
  the current-spec `xxx2` form (`xxx3` first) when the font carries it.
* Khmer: Khmer shaper (Coeng/Ro pref, left-matra moves, split-matras).
* Myanmar: Myanmar shaper for `mym2` fonts (`mymr`/DFLT stay default).
* The long USE list: USE shaper unless the font only targets DFLT
  or latn (then default).
* Everything else: default shaper.

`gposHasMark` gates Hebrew composition on GPOS mark support.

## Default GSUB and GPOS

* `applyGsubFeatures` resolves the LangSys once, then applies each
  requested feature with a fresh mask.
* `applyDefaultGpos` applies mark, mkmk, curs, dist, abvm, and blwm by
  default, then user features with fresh bits.
* Legacy `kern` runs after GPOS when requested and GPOS supplied no kern
  for the script.
* AAT morx replaces GSUB when present and the text is horizontal (or
  the font has no GSUB): complex shapers stand down to the default
  shaper, morx applies with feat derived flags, deleted glyphs are
  compacted, and the morx path skips mark advance zeroing and fallback
  mark positioning.
* Fallback mark positioning runs only when neither GPOS nor legacy kern
  positioned, and Thai, Indic, Khmer, Myanmar, and USE opt out.
* Marks without GPOS attachment still get zero advances; RTL buffers
  reverse at the end.

## Script specific paths

* Arabic: ordered joining features with joining aware masks, Unicode and
  win1256 fallback presentation forms, mark reordering.
* Hangul: jamo masks plus ljmo, vjmo, tjmo, and calt handling.
* Indic, Khmer, Myanmar, USE: full staged appliers
  (see [Complex shapers](shapers.md)).
* Hebrew, Thai: preprocessing and reorder hooks before or during GSUB.

## Reading results

After `shape`, `buf.info[i].glyphId` holds glyph ids, `buf.pos[i]`
holds advances and offsets, and `buf.info[i].cluster` holds source
clusters. hr-shape prints these in hb-shape compatible form.
