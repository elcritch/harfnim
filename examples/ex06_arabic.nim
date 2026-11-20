## Poster 6: Arabic joining, shaped visual order.
##
## Shapes "مرحبا" with Arial. The top strip shows the five codepoints
## in logical order with byte offsets; the bottom strip shows the five
## shaped glyphs in visual order. Orange connectors follow clusters
## and cross, which is exactly the RTL reversal plus joining.

import std/strformat
import std/strutils

import ./support
import harfnim

const
  CanvasW = 1280
  CanvasH = 820
  SizePx = 330

proc main() =
  let path = findDemoFont()
  if path == "":
    quit("no demo font found")
  let sf = loadShaper(path, SizePx)
  let k = pixelScale(sf, SizePx)
  let feats = defaultFeatures()
  let text = "مرحبا"
  var b = shapeText(sf, text, feats)
  doAssert b.len == 5
  var c = newCanvas(CanvasW, CanvasH)
  c.header("Arabic joining: shaped visual order",
    fmt"Arial at {SizePx}px shapes 'مرحبا' into {b.len} RTL glyphs: script={scriptName(b)} direction={dirName(b.direction)}")
  var offs: seq[int] = @[]
  var cps: seq[uint32] = @[]
  var p = 0
  while p < text.len:
    offs.add(p)
    let b0 = uint8(text[p])
    if b0 < 0x80u8:
      cps.add(uint32(b0))
      inc p
    elif b0 < 0xE0u8:
      cps.add((uint32(b0 and 0x1Fu8) shl 6) or
        uint32(uint8(text[p + 1]) and 0x3Fu8))
      p += 2
    else:
      cps.add(0xFFFDu32)
      p += 3
  let boxW = 110.0
  let topX = 640.0 - float64(offs.len) * (boxW + 10.0) / 2.0
  let topY = 140.0
  c.label(90, 122, "logical order (codepoints, byte offsets)", 16, Ink,
    "start", "bold")
  for n, o in offs:
    let x = topX + float64(n) * (boxW + 10.0)
    c.rect(x, topY, boxW, 70, "#ffffff", Faint, 1.5)
    c.label(x + boxW / 2, topY + 30, "U+" & cps[n].toHex(4), 15, Ink,
      "middle")
    c.label(x + boxW / 2, topY + 52, fmt"byte {o}", 12, Faint, "middle")
  let baseY = 560.0
  c.label(90, 300, "shaped visual order (RTL, joining applied)", 16, Ink,
    "start", "bold")
  var total = 0i32
  for g in 0 ..< b.len:
    total += b.pos[g].xAdvance
  let pen0 = 640.0 - float64(total) / 2.0
  c.line(90, baseY, 1190, baseY, BaseLine, 2.0)
  var pen = pen0
  for g in 0 ..< b.len:
    let gid = b.info[g].glyphId
    c.drawExtentsBox(sf, gid, pen, baseY, float64(b.pos[g].xOffset),
      float64(b.pos[g].yOffset))
    let d = glyphPath(sf, gid, pen, baseY, k,
      float64(b.pos[g].xOffset), float64(b.pos[g].yOffset))
    if d != "":
      c.path(d, "#eef1ff", Ink, 3.0)
    c.circle(pen, baseY, 5, Origin, "#ffffff", 2.0)
    let adv = float64(b.pos[g].xAdvance)
    c.arrow(pen, baseY + 66, pen + adv, baseY + 66, Advance, 2.5,
      "arrGreen")
    c.label(pen + adv / 2, baseY + 92, fmt"gid {gid}", 13, Ink,
      "middle")
    c.label(pen + adv / 2, baseY + 112, fmt"cluster {b.info[g].cluster}",
      13, Cluster, "middle")
    c.label(pen + adv / 2, baseY + 132, fmt"adv {b.pos[g].xAdvance}",
      13, Advance, "middle")
    var li = -1
    for n, o in offs:
      if o == int(b.info[g].cluster):
        li = n
        break
    if li >= 0:
      let lx = topX + float64(li) * (boxW + 10.0) + boxW / 2.0
      c.line(lx, topY + 70, pen + adv / 2, baseY - 190, Cluster, 1.5)
    pen += adv
  c.label(90, 720,
    "Clusters survive joining and presentation forms: 8 6 4 2 0 in visual order.",
    14, Ink)
  c.label(90, 742,
    "Each glyph keeps its source byte cluster, so hit testing maps back to logical text.",
    14, Ink)
  c.footer("Arabic joining is automatic: the shaper picks positional forms and reverses runs for RTL display.")
  let f = outPath("ex06_arabic")
  c.save(f)
  echo "wrote " & f

when isMainModule:
  main()
