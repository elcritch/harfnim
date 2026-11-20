# Example posters

The `examples/` directory holds sixteen Nim programs that shape real
text and draw the result as fixed size SVG guides. Open the SVGs in a
browser: glyph outlines are stroked and big, and every shaping decision
carries a labeled guide. Regenerate them with `clue task examples`
(see `examples/README.md`).

## 1. Anatomy of shaped text (`ex01_anatomy`, 1280x780)

Shapes "AV" with Arial at 560 px. Shows the full pen walk: baseline,
hhea ascender and descender, one origin dot per glyph, one advance
arrow per glyph, scaled extents boxes, and UTF-8 byte clusters. The
side panel maps each color back to the API: `buf.info` holds glyph ids
and clusters, `buf.pos` holds advances and offsets, and the pen walk is
exactly origin plus advance, in order.

## 2. Kerning (`ex02_kerning`, 1280x760)

Shapes "AV" and "To" twice, once with an empty feature list and once
with kern enabled. The unkerned outlines stay visible in gray behind
the inked kerned output, and a red arrow at the advance level spans
the measured kern delta. Glyph ids and clusters are unchanged; only
advances move, which is the whole point of GPOS pair positioning.

## 3. Ligature (`ex03_ligature`, 1280x780)

System fonts on the test machine carry no fi ligature, so this poster
builds a tiny synthetic TTF in memory: blocky f, i, and fi glyphs, a
cmap for f and i, and a GSUB type 4 ligature lookup. Shaping "fi" with
liga off yields two glyphs with clusters 0 and 1; with liga on it
yields gid 20 with cluster 0 (the minimum) and the ligature bit set.
Substitution happens before positioning, so the fi glyph brings its
own advance and extents.

## 4. Marks (`ex04_marks`, 1280x820)

Two Arial panels. Left: beh plus fatha (U+064E) stays two glyphs; the
mark is positioned by GPOS mark to base, drawn with an arrow for its
`xOffset, yOffset` vector and a zero advance label. Right: a plus
combining acute (U+0301) composes into one precomposed glyph through
ccmp, merging clusters 0 and 1. Positioning shifts the glyph without
advancing the pen; composition replaces two codepoints with one id.

## 5. Bidirectional runs (`ex05_bidi`, 1280x1020)

Runs `visualRuns` over "ab Hebrew cd" with automatic base direction,
then shapes each run on its own with an explicit direction, bypassing
segment guessing. The top strip is logical order with byte offsets;
the rows below are shaped visual order, one band per maximal level
run. Orange connectors follow `VisualText.map` from each source byte
to its visual glyph, so the Hebrew run visibly maps 3, 5, 7 back to
front. The footer states the contract: visual order text, a per byte
source map with sentinel, and maximal level runs.

## 6. Arabic joining (`ex06_arabic`, 1280x820)

Shapes "مرحبا" with Arial. The top strip shows five codepoints in
logical order; the bottom strip shows five shaped glyphs in visual
order with ids, clusters, and advances. Orange connectors follow
clusters and cross, which is exactly the RTL reversal plus joining:
clusters survive joining and presentation forms as 8 6 4 2 0, so hit
testing maps back to logical text.

## 7. Hebrew marks (`ex07_hebrew`, 1280x920)

Shapes "shalom" with Arial. The top strip is logical order with
codepoint and byte labels; the bottom strip is shaped visual order.
With the default feature set the shin dot and vowels compose or hold
as zero advance marks: one qamats keeps cluster 0 with a +168,+2
offset, drawn as an arrow from the base origin to the mark origin.
The buffer reverses for RTL display while every mark keeps its source
cluster.

## 8. Russian (`ex08_russian`, 1280x960)

Top: precomposed YO (U+0401) and decomposed YE plus combining
diaeresis (U+0415 U+0301) shape to the identical glyph, showing
normalization equivalence: the normalizer composes the pair before
GSUB runs. Bottom: the full word "Privet" shaped with kern off (gray)
vs on (ink), with measured totals and the kern delta. The ve pair
tightens, like the Latin pairs in poster 2.

## 9. Thai (`ex09_thai`, 1280x880)

Shapes KO KAI plus precomposed SARA AM (U+0E33) next to KO KAI plus
the explicit NIKHAHIT plus SARA A sequence (U+0E4D U+0E32) with
Ayuthaya. Both inputs produce the identical gid stream, proving the
SARA AM split: a zero advance mark plus the vowel. Clusters merge in
the precomposed row and survive in the explicit row.

## 10. Hangul (`ex10_hangul`, 1280x800)

Shapes conjoining jamo HIEUH A NIEUN (U+1112 U+1161 U+11AB) with
AppleGothic and compares against precomposed HANGUL GEUL. The three
jamo compose to the identical glyph id as the precomposed syllable,
showing Hangul LV and LVT syllable composition before GSUB runs.

## 11. Greek (`ex11_greek`, 1280x960)

Top: precomposed alpha with tonos (U+03AC) and decomposed alpha plus
combining tonos (U+03B1 U+0301) shape to the identical glyph, the same
normalization equivalence as posters 8 and 9. Bottom: the word
"logos" with kern off (gray) vs on (ink); the lamda pair tightens and
word-final sigma takes its final form while clusters stay in logical
order.

## 12. Khmer (`ex12_khmer`, 1280x920)

Shapes "Khmae" (KHA, COENG, MO, VS AE, RO) with Khmer Sangam MN. The
top strip is logical order with codepoint and byte labels; the bottom
strip is shaped visual order. The left vowel leaps before the base,
COENG plus MO fuse into a zero advance below-base form, and final RO
keeps cluster 12. Orange connectors cross where the reorder moved
glyphs, and clusters 0 and 12 survive for hit testing.

## 13. Myanmar (`ex13_myanmar`, 1280x880)

Shapes RA plus ASAT plus VIRAMA plus KA with Myanmar Sangam MN. The
three codepoint reph moves after its base consonant and fuses into a
zero advance form, so both visual glyphs share cluster 0 with the base
first. The converging connectors show three codepoints collapsing
into the reph glyph while KA leads.

## 14. USE (`ex14_use`, 1280x880)

Shapes SHA plus VIRAMA plus RA plus II (no ZWJ) with Sinhala Sangam
MN. Four codepoints shape to two ligatures inside one USE syllable:
SHA plus VIRAMA fuse and RA plus II fuse, with clusters 0 and 6. No
reorder happens here; the poster shows syllable aware ligation
applying across the whole cluster.

## 15. Japanese (`ex15_japanese`, 1280x1000)

Top: HA plus combining voiced mark (U+306F U+3099) and precomposed
BA (U+3070) shape to the identical glyph with Hiragino Sans GB, the
same normalization equivalence as posters 8, 9, and 11. Bottom: the
word "taberu" (kanji TA plus hiragana BE RU) shapes to three full em
glyphs with byte clusters 0, 3, and 6. Kanji sets the verb root,
hiragana sets the inflection, and every glyph takes one em.

## 16. Chinese (`ex16_chinese`, 1280x1040)

Top: "ni hao shi jie" shapes to four full em glyphs with Songti SC,
byte clusters 0, 3, 6, and 9. Bottom: "A" plus two han plus "B"
mixes proportional Latin advances with full em han; the byte
clusters 0, 1, 4, and 7 step one byte for Latin, three for han. No
joining, no ligatures: each han keeps its three byte cluster.
