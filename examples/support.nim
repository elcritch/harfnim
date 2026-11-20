## Shared helpers for the SVG example posters in this directory.
##
## Font discovery on the host machine, shaping shortcuts with a default
## OpenType feature set, font unit to pixel transforms, glyph outline to
## SVG path conversion, and a tiny SVG canvas builder. Every poster uses
## a fixed canvas size with big stroked outlines so each shaping
## decision stays readable.

import std/math
import std/options
import std/os
import std/strformat
import std/strutils

import harfnim

const
  Ink* = "#22223b"
    ## Glyph strokes and primary text.
  Faint* = "#8d99ae"
    ## Secondary guides and labels.
  BaseLine* = "#d00000"
    ## Baseline color.
  MetricLine* = "#0a9396"
    ## Ascender and descender color.
  Origin* = "#4361ee"
    ## Glyph origin color.
  Advance* = "#2a9d8f"
    ## Advance arrow color.
  Box* = "#8338ec"
    ## Bounding box color.
  Cluster* = "#ff8500"
    ## Cluster label color.
  RunA* = "#4361ee"
    ## Even embedding level run color.
  RunB* = "#e36414"
    ## Odd embedding level run color.
  RunC* = "#2a9d8f"
    ## Level 2 and deeper run color.

type
  Canvas* = object
    ## Fixed size SVG poster under construction.
    w*: int
    ## Canvas width in pixels.
    h*: int
    ## Canvas height in pixels.
    body*: string
    ## Accumulated SVG elements.

proc newCanvas*(w, h: int): Canvas =
  ## Creates an empty poster of the given pixel size.
  Canvas(w: w, h: h, body: "")

proc esc*(s: string): string =
  ## Escapes text for SVG content.
  s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

proc f2*(v: float64): string =
  ## Compact number formatting for path data.
  let r = round(v)
  if abs(v - r) < 0.005: $int(r)
  else: formatFloat(v, ffDecimal, 1)

proc add*(c: var Canvas; s: string) =
  ## Appends a raw SVG element.
  c.body &= s & "\n"

proc line*(c: var Canvas; x1, y1, x2, y2: float64; stroke: string;
    width = 1.0; dash = "") =
  ## Adds a straight guide line.
  var s = fmt"""<line x1="{f2(x1)}" y1="{f2(y1)}" x2="{f2(x2)}" y2="{f2(y2)}" stroke="{stroke}" stroke-width="{f2(width)}""""
  if dash != "":
    s &= fmt""" stroke-dasharray="{dash}""""
  c.add(s & "/>")

proc rect*(c: var Canvas; x, y, w, h: float64; fill, stroke: string;
    sw = 1.0; dash = ""; fillOpacity = 1.0; strokeOpacity = 1.0) =
  ## Adds a rectangle, used for boxes and legend swatches.
  var s = fmt"""<rect x="{f2(x)}" y="{f2(y)}" width="{f2(w)}" height="{f2(h)}" fill="{fill}""""
  if fillOpacity < 1.0:
    s &= fmt""" fill-opacity="{f2(fillOpacity)}""""
  s &= fmt""" stroke="{stroke}" stroke-width="{f2(sw)}""""
  if strokeOpacity < 1.0:
    s &= fmt""" stroke-opacity="{f2(strokeOpacity)}""""
  if dash != "":
    s &= fmt""" stroke-dasharray="{dash}""""
  c.add(s & "/>")

proc circle*(c: var Canvas; cx, cy, r: float64; fill, stroke: string;
    sw = 1.5) =
  ## Adds a circle, used for origins and anchors.
  c.add(fmt"""<circle cx="{f2(cx)}" cy="{f2(cy)}" r="{f2(r)}" fill="{fill}" stroke="{stroke}" stroke-width="{f2(sw)}"/>""")

proc path*(c: var Canvas; d, fill, stroke: string; sw = 3.0;
    opacity = 1.0; join = "round") =
  ## Adds a path, used for stroked glyph outlines.
  var s = fmt"""<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{f2(sw)}" stroke-linejoin="{join}" stroke-linecap="{join}""""
  if opacity < 1.0:
    s &= fmt""" opacity="{f2(opacity)}""""
  c.add(s & "/>")

proc label*(c: var Canvas; x, y: float64; s: string; size = 16;
    fill = Ink; anchor = "start"; weight = "") =
  ## Adds a text label.
  var e = fmt"""<text x="{f2(x)}" y="{f2(y)}" font-size="{size}" fill="{fill}" text-anchor="{anchor}""""
  if weight != "":
    e &= fmt""" font-weight="{weight}""""
  c.add(e & ">" & esc(s) & "</text>")

proc arrow*(c: var Canvas; x1, y1, x2, y2: float64; color: string;
    width = 2.0; marker = "arrInk") =
  ## Adds a directed line with an arrowhead marker.
  c.add(fmt"""<line x1="{f2(x1)}" y1="{f2(y1)}" x2="{f2(x2)}" y2="{f2(y2)}" stroke="{color}" stroke-width="{f2(width)}" marker-end="url(#{marker})"/>""")

proc header*(c: var Canvas; title, sub: string) =
  ## Adds the poster title block.
  c.label(48, 44, title, 30, Ink, "start", "bold")
  c.label(48, 70, sub, 15, Faint)

proc footer*(c: var Canvas; s: string) =
  ## Adds a note pinned near the bottom edge.
  c.label(48, float64(c.h - 22), s, 13, Faint)

const Markers = """<defs>
<marker id="arrInk" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#22223b"/></marker>
<marker id="arrRed" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#d00000"/></marker>
<marker id="arrGreen" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#2a9d8f"/></marker>
<marker id="arrBlue" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#4361ee"/></marker>
<marker id="arrOrange" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#e36414"/></marker>
<marker id="arrCluster" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#ff8500"/></marker>
</defs>
"""

proc save*(c: Canvas; path: string) =
  ## Writes the poster, creating the output directory first.
  let dir = parentDir(path)
  if dir != "":
    createDir(dir)
  let doc = fmt"""<svg xmlns="http://www.w3.org/2000/svg" width="{c.w}" height="{c.h}" viewBox="0 0 {c.w} {c.h}" font-family="Helvetica, Arial, sans-serif">""" &
    "\n" & Markers & fmt"""<rect x="0" y="0" width="{c.w}" height="{c.h}" fill="#ffffff"/>""" &
    "\n" & c.body & "</svg>\n"
  writeFile(path, doc)

proc readBytes*(path: string): seq[uint8] =
  ## Reads a font file into bytes.
  let s = readFile(path)
  result = newSeq[uint8](s.len)
  for i, ch in s:
    result[i] = uint8(ch)

proc findDemoFont*(): string =
  ## First usable host font, preferring Arial for its broad coverage.
  const cands = [
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/Supplemental/Times New Roman.ttf",
    "/System/Library/Fonts/Geneva.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
  ]
  for p in cands:
    if fileExists(p):
      return p
  ""

proc findFontOrQuit*(cands: openArray[string]): string =
  ## First existing host font from candidates, quitting when none match.
  for p in cands:
    if fileExists(p):
      return p
  quit("no demo font found")

proc loadShaper*(path: string; sizePx: int32): ShaperFont =
  ## Parses a font and scales it to the given pixel size.
  let sf = newShaperFont(parseFont(readBytes(path)))
  var m = sf
  m.setScale(sizePx)
  m

proc defaultFeatures*(): seq[Feature] =
  ## Default shaping features, mirroring hr-shape.
  for t in ["abvm", "blwm", "calt", "ccmp", "clig", "curs", "dist",
      "kern", "liga", "locl", "mark", "mkmk", "rlig", "rclt"]:
    result.add(globalFeature(tagFromStr(t), 1))

proc offFeatures*(): seq[Feature] =
  ## Empty feature list, for before and after comparisons.
  @[]

proc shapeText*(sf: ShaperFont; text: string;
    feats: seq[Feature]): Buffer =
  ## Shapes text into a fresh buffer.
  result = newBuffer()
  result.pushStr(text)
  sf.shape(result, feats)

proc dirName*(d: Direction): string =
  ## Short direction name for labels.
  case d
  of dirLeftToRight: "ltr"
  of dirRightToLeft: "rtl"
  of dirTopToBottom: "ttb"
  of dirBottomToTop: "btt"
  of dirInvalid: "invalid"

proc scriptName*(b: Buffer): string =
  ## Guessed script tag, or a dash when unset.
  if b.script.isSome: b.script.get.tag().toStr() else: "-"

proc pixelScale*(sf: ShaperFont; sizePx: int32): float64 =
  ## Font units per pixel factor at the given size.
  float64(sizePx) / float64(sf.unitsPerEm)

proc glyphPath*(sf: ShaperFont; gid: uint32; penX, baseY, k: float64;
    xOffPx = 0.0; yOffPx = 0.0): string =
  ## SVG path data for an outline placed at the pen with a y flip.
  ## Offsets and advances arrive scaled (pixels); outline points are
  ## font units scaled here by k. Returns "" when the glyph has no
  ## outline.
  var d = ""
  let ok = sf.drawGlyph(newGlyphId(gid), proc(op: DrawOp) =
    let px = func(x: int32): float64 = penX + xOffPx + float64(x) * k
    let py = func(y: int32): float64 = baseY - yOffPx - float64(y) * k
    case op.kind
    of moveTo:
      d &= "M" & f2(px(op.to.x)) & " " & f2(py(op.to.y)) & " "
    of lineTo:
      d &= "L" & f2(px(op.to.x)) & " " & f2(py(op.to.y)) & " "
    of quadraticTo:
      d &= "Q" & f2(px(op.qCtrl.x)) & " " & f2(py(op.qCtrl.y)) & " " &
        f2(px(op.qTo.x)) & " " & f2(py(op.qTo.y)) & " "
    of cubicTo:
      d &= "C" & f2(px(op.c1.x)) & " " & f2(py(op.c1.y)) & " " &
        f2(px(op.c2.x)) & " " & f2(py(op.c2.y)) & " " &
        f2(px(op.cTo.x)) & " " & f2(py(op.cTo.y)) & " "
    of closePath:
      d &= "Z "
  )
  if not ok:
    return ""
  d

proc hheaAscentDescent*(f: SfntFont): tuple[asc, desc: int] =
  ## Ascender and descender in font units, with safe fallbacks.
  const HheaTag = 0x68686561u32
  let t = f.tableData(HheaTag)
  if not t.ok or t.len < 10 or t.offset + 10 > f.bytes.len:
    return (800, -200)
  proc i16be(b: seq[uint8]; at: int): int =
    let v = (int(b[at]) shl 8) or int(b[at + 1])
    if v >= 0x8000: v - 0x10000 else: v
  (i16be(f.bytes, t.offset + 4), i16be(f.bytes, t.offset + 6))

proc drawGlyphBox*(c: var Canvas; sf: ShaperFont; gid: uint32; penX,
    baseY, k: float64; xOffPx = 0.0; yOffPx = 0.0;
    fill = "#eef1ff") =
  ## Strokes a glyph outline, or a dashed placeholder when empty.
  let d = glyphPath(sf, gid, penX, baseY, k, xOffPx, yOffPx)
  if d == "":
    let e = sf.glyphExtents(newGlyphId(gid))
    if e.isSome:
      let b = e.get
      c.rect(penX + float64(b.xBearing), baseY - float64(b.yBearing),
        float64(b.width), float64(-b.height), "none", Faint, 1.5, "5 4")
    else:
      c.rect(penX, baseY - 500.0 * k, 500.0 * k, 700.0 * k, "none",
        Faint, 1.5, "5 4")
  else:
    c.path(d, fill, Ink, 3.0)

proc drawExtentsBox*(c: var Canvas; sf: ShaperFont; gid: uint32; penX,
    baseY: float64; xOffPx = 0.0; yOffPx = 0.0) =
  ## Dashed bounding box from scaled glyph extents.
  let e = sf.glyphExtents(newGlyphId(gid))
  if e.isNone:
    return
  let b = e.get
  c.rect(penX + xOffPx + float64(b.xBearing),
    baseY - yOffPx - float64(b.yBearing), float64(b.width),
    float64(-b.height), "none", Box, 1.5, "6 4")

proc outPath*(name: string): string =
  ## Output SVG path next to these sources.
  "examples/out/" & name & ".svg"
