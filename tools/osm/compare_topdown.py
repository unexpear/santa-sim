#!/usr/bin/env python3
"""Side-by-side check that our houses sit on the real footprints.

Needs Pillow (pip install pillow). Fetches a few OpenStreetMap tiles once (cached in
tools/osm/cache/tiles, polite User-Agent) and builds:  real map | our top-down render | overlay.

  1) render:  Godot_v4.7.2-stable_win64_console.exe --path . scenes/town/town.tscn -- --townshots=D:/dev/santa-sim/screenshots
  2) compare: python tools/osm/compare_topdown.py --town paddington_qld

The top-down render is orthographic, north up, and its height covers exactly the imported square.
"""
import argparse, json, math, os, urllib.request
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
UA = "santa-sim-town-import/0.1 (one-off comparison render)"


def tiles(bb, z, cache):
    s, w, n, e = bb

    def xy(lat, lon):
        x = (lon + 180) / 360 * 2 ** z
        y = (1 - math.log(math.tan(math.radians(lat)) + 1 / math.cos(math.radians(lat))) / math.pi) / 2 * 2 ** z
        return x, y
    x0, y0 = xy(n, w)
    x1, y1 = xy(s, e)
    os.makedirs(cache, exist_ok=True)
    img = Image.new("RGB", ((int(x1) - int(x0) + 1) * 256, (int(y1) - int(y0) + 1) * 256))
    for tx in range(int(x0), int(x1) + 1):
        for ty in range(int(y0), int(y1) + 1):
            fn = os.path.join(cache, f"{z}_{tx}_{ty}.png")
            if not os.path.exists(fn):
                req = urllib.request.Request(f"https://tile.openstreetmap.org/{z}/{tx}/{ty}.png", headers={"User-Agent": UA})
                with open(fn, "wb") as f:
                    f.write(urllib.request.urlopen(req, timeout=60).read())
            img.paste(Image.open(fn).convert("RGB"), ((tx - int(x0)) * 256, (ty - int(y0)) * 256))
    ox, oy = (x0 - int(x0)) * 256, (y0 - int(y0)) * 256
    return img.crop((int(ox), int(oy), int(ox + (x1 - x0) * 256), int(oy + (y1 - y0) * 256)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--town", required=True)
    ap.add_argument("--render", default=os.path.join(ROOT, "screenshots", "town_topdown.png"))
    ap.add_argument("--out", default=os.path.join(ROOT, "screenshots", "town_topdown_compare.jpg"))
    ap.add_argument("--zoom", type=int, default=18)
    a = ap.parse_args()
    d = json.load(open(os.path.join(ROOT, "data", "towns", a.town + ".json"), encoding="utf-8"))
    ren = Image.open(a.render).convert("RGB")
    H = ren.height
    ren = ren.crop(((ren.width - H) // 2, 0, (ren.width + H) // 2, H))
    ref = tiles(d["source"]["bbox_swne"], a.zoom, os.path.join(ROOT, "tools", "osm", "cache", "tiles")).resize((H, H))
    ext = d["extent"]
    sc = H / (ext["max"][0] - ext["min"][0])
    ov = ren.copy()
    dr = ImageDraw.Draw(ov)
    for b in d["buildings"]:
        pts = [((p[0] - ext["min"][0]) * sc, (ext["max"][1] - p[1]) * sc) for p in b["poly"]]
        dr.line(pts + [pts[0]], fill=(255, 255, 0), width=2)
    S = 700
    out = Image.new("RGB", (S * 3 + 40, S + 70), (20, 18, 30))
    d2 = ImageDraw.Draw(out)
    for i, (p, t) in enumerate(zip((ref, ren, ov), ("Real map (OpenStreetMap)", "Santa Sim town (our houses)", "Overlay: real footprints in yellow"))):
        out.paste(p.resize((S, S)), (10 + i * (S + 10), 40))
        d2.text((10 + i * (S + 10), 12), t, fill=(255, 240, 200))
    d2.text((10, S + 48), f"{d.get('display_name', a.town)}, north up.  Map data (c) OpenStreetMap contributors (ODbL).", fill=(220, 220, 220))
    out.save(a.out, quality=88)
    print("wrote", a.out)


if __name__ == "__main__":
    main()
