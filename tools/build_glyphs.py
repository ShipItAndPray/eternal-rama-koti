# Shapes each canonical form with HarfBuzz, extracts outlines with fontTools,
# normalizes into a 1000x400 box (y-down), writes glyphs/<id>.txt, forms.json, preview.html.
import json, os
import uharfbuzz as hb
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.recordingPen import DecomposingRecordingPen

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FONTS = os.path.join(HERE, "fonts")
OUT = os.path.join(ROOT, "glyphs")

FORMS = [
    (0, "Telugu",    "శ్రీరామ",  "NotoSerifTelugu",     ["sri", "ra", "ma"]),
    (1, "Hindi",     "श्रीराम",  "NotoSerifDevanagari", ["sri", "ra", "ma"]),
    (2, "Tamil",     "ஸ்ரீராம",  "NotoSerifTamil",      ["sri", "ra", "ma"]),
    (3, "Kannada",   "ಶ್ರೀರಾಮ",  "NotoSerifKannada",    ["sri", "ra", "ma"]),
    (4, "Malayalam", "ശ്രീരാമ",  "NotoSerifMalayalam",  ["sri", "ra", "ma"]),
    (5, "Bengali",   "শ্রীরাম",  "NotoSerifBengali",    ["sri", "ra", "ma"]),
    (6, "Gujarati",  "શ્રીરામ",  "NotoSerifGujarati",   ["sri", "ra", "ma"]),
    (7, "Odia",      "ଶ୍ରୀରାମ",  "NotoSerifOriya",      ["sri", "ra", "ma"]),
    (8, "Punjabi",   "ਸ਼੍ਰੀਰਾਮ",  "NotoSerifGurmukhi",   ["sri", "ra", "ma"]),
    (9, "English",   "Sri Rama", "NotoSerif",           ["sri", " ra", "ma"]),
]
BOX_W, BOX_H, PAD = 1000, 400, 40

def font_path(family):
    for f in sorted(os.listdir(FONTS)):
        if f.endswith(".ttf") and (f.startswith(family + "[") or f.startswith(family + "-Regular")):
            return os.path.join(FONTS, f)
    raise SystemExit(f"font for {family} not found in {FONTS}")

def shape(path, text):
    blob = hb.Blob.from_file_path(path)
    face = hb.Face(blob)
    font = hb.Font(face)
    upem = face.upem
    font.scale = (upem, upem)
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(font, buf)
    return upem, [(i.codepoint, p.x_advance, p.x_offset, p.y_offset) for i, p in zip(buf.glyph_infos, buf.glyph_positions)]

def outline(ttf_path, text):
    tt = TTFont(ttf_path)
    gs = tt.getGlyphSet()
    order = tt.getGlyphOrder()
    upem, run = shape(ttf_path, text)
    rec = DecomposingRecordingPen(gs)
    x = 0
    for gid, adv, dx, dy in run:
        g = gs[order[gid]]
        g.draw(TransformPen(rec, (1, 0, 0, 1, x + dx, dy)))
        x += adv
    return rec, upem

def normalize(rec):
    b = BoundsPen(None)
    rec.replay(b)
    xmin, ymin, xmax, ymax = b.bounds
    w, h = xmax - xmin, ymax - ymin
    s = min((BOX_W - 2 * PAD) / w, (BOX_H - 2 * PAD) / h)
    tx = (BOX_W - w * s) / 2 - xmin * s
    ty = (BOX_H + h * s) / 2 + ymin * s
    pen = SVGPathPen(None, ntos=lambda v: str(int(round(v))))
    rec.replay(TransformPen(pen, (s, 0, 0, -s, tx, ty)))
    return pen.getCommands()

def main():
    os.makedirs(OUT, exist_ok=True)
    forms_json, previews = [], []
    for id_, lang, form, family, rom in FORMS:
        fp = font_path(family)
        rec, _ = outline(fp, form)
        d = normalize(rec)
        with open(os.path.join(OUT, f"{id_}.txt"), "w", encoding="utf-8") as f:
            f.write(d)
        forms_json.append({"id": id_, "language": lang, "form": form, "romanized": rom})
        previews.append(f'<figure><svg viewBox="0 0 {BOX_W} {BOX_H}" width="300"><rect width="{BOX_W}" height="{BOX_H}" fill="#FBF3E4"/><path d="{d}" fill="#9B1C1C"/></svg><figcaption>{id_} {lang} · {form} · {os.path.basename(fp)} · {len(d)} bytes</figcaption></figure>')
        print(f"{id_} {lang:10s} {len(d):6d} bytes  {os.path.basename(fp)}")
    with open(os.path.join(OUT, "forms.json"), "w", encoding="utf-8") as f:
        json.dump(forms_json, f, ensure_ascii=False, indent=2)
    with open(os.path.join(OUT, "preview.html"), "w", encoding="utf-8") as f:
        f.write('<!doctype html><meta charset="utf-8"><title>glyph preview</title><style>body{font-family:serif;background:#fff;margin:0}figure{display:inline-block;margin:8px;text-align:center}figcaption{font-size:12px}</style><div style="display:flex;flex-wrap:nowrap;overflow-x:auto">' + "".join(previews) + "</div>")

if __name__ == "__main__":
    main()
