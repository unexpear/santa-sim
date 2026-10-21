#!/usr/bin/env python3
"""Santa Sim offline OSM town importer (standard library only, Python 3.9+).

Pulls one small area from the Overpass API (cached), projects it to local metres around the
town centre and writes a compact game file: data/towns/<town>.json.

  python tools/osm/osm_import.py --town paddington_qld --center -27.4598,152.9985 --size 550
  python tools/osm/osm_import.py --town mudgee --place "Mudgee, NSW" --size 500
  python tools/osm/osm_import.py --town custom --bbox -27.462,152.996,-27.457,153.001

Map data (c) OpenStreetMap contributors, ODbL 1.0. See data/towns/ATTRIBUTION.md.
"""
import argparse, hashlib, json, math, os, sys, time, urllib.parse, urllib.request, datetime

UA = "santa-sim-town-import/0.1 (offline game asset import; contact: local dev)"
ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
]
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
R_EARTH = 6378137.0

# Car roads we draw as asphalt: default carriageway width (m) and whether a footpath is likely.
ROAD_TYPES = {
    "motorway": (14.0, False), "trunk": (12.0, True), "primary": (11.0, True), "secondary": (10.0, True),
    "tertiary": (9.0, True), "unclassified": (7.0, True), "residential": (7.5, True),
    "living_street": (6.0, False), "service": (4.0, False), "road": (7.0, True),
    "motorway_link": (6.0, False), "trunk_link": (6.0, False), "primary_link": (6.0, False),
    "secondary_link": (6.0, False), "tertiary_link": (6.0, False), "busway": (7.0, False),
}
PATH_TYPES = {"footway": 1.8, "path": 1.6, "pedestrian": 4.0, "cycleway": 2.2, "steps": 1.8, "bridleway": 2.0, "track": 3.0}
HOUSE_TAGS = {"house", "detached", "residential", "semidetached_house", "bungalow", "terrace", "cabin", "farm", "static_caravan"}
SHED_TAGS = {"garage", "garages", "shed", "carport", "roof", "hut", "greenhouse", "kiosk", "toilets"}
COMMERCIAL_TAGS = {"retail", "commercial", "office", "industrial", "warehouse", "supermarket", "hotel", "service", "kindergarten"}
CHURCH_TAGS = {"church", "chapel", "cathedral", "temple", "mosque", "synagogue", "religious"}
CIVIC_TAGS = {"school", "university", "college", "public", "civic", "hospital", "government", "train_station", "fire_station", "sports_centre", "pavilion"}
GREEN_LANDUSE = {"grass", "recreation_ground", "village_green", "meadow", "cemetery", "allotments", "orchard", "flowerbed"}
GREEN_LEISURE = {"park", "garden", "playground", "pitch", "golf_course", "nature_reserve", "dog_park", "common"}
WOOD = {"wood", "scrub", "heath", "forest"}
WATER_NATURAL = {"water", "wetland", "bay"}


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# --- area -----------------------------------------------------------------------------------------

def bbox_around(lat, lon, size_m):
    half = size_m / 2.0
    dlat = math.degrees(half / R_EARTH)
    dlon = math.degrees(half / (R_EARTH * math.cos(math.radians(lat))))
    return (lat - dlat, lon - dlon, lat + dlat, lon + dlon)


def geocode(place):
    url = "https://nominatim.openstreetmap.org/search?" + urllib.parse.urlencode({"q": place, "format": "json", "limit": 1})
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    res = json.load(urllib.request.urlopen(req, timeout=60))
    if not res:
        sys.exit("place not found: " + place)
    log("geocoded:", res[0].get("display_name"))
    return float(res[0]["lat"]), float(res[0]["lon"])


# --- fetch (polite + cached) ----------------------------------------------------------------------

def overpass_query(bb, pad_m):
    s, w, n, e = bb
    # Fetch a little beyond the square so roads/footpaths reach the edge cleanly.
    lat0 = (s + n) / 2
    dlat = math.degrees(pad_m / R_EARTH)
    dlon = math.degrees(pad_m / (R_EARTH * math.cos(math.radians(lat0))))
    big = f"{s - dlat:.7f},{w - dlon:.7f},{n + dlat:.7f},{e + dlon:.7f}"
    small = f"{s:.7f},{w:.7f},{n:.7f},{e:.7f}"
    return f"""[out:json][timeout:120];
(
  way["highway"]({big});
  way["building"]({small});
  relation["building"]["type"="multipolygon"]({small});
  way["landuse"]({big});
  way["leisure"]({big});
  way["natural"]({big});
  relation["natural"="water"]({big});
  way["waterway"]({big});
  way["barrier"~"^(fence|wall|hedge)$"]({small});
  node["natural"="tree"]({big});
  node["addr:housenumber"]({small});
  way["boundary"="lot"]({small});
  way["landuse"="residential"]["lot"]({small});
);
out geom qt;"""


def fetch(query, cache_path, refresh=False):
    if os.path.exists(cache_path) and not refresh:
        log("using cached Overpass response:", os.path.relpath(cache_path, ROOT))
        with open(cache_path, "r", encoding="utf-8") as f:
            return json.load(f)
    data = urllib.parse.urlencode({"data": query}).encode()
    last = None
    for attempt in range(6):
        ep = ENDPOINTS[attempt % len(ENDPOINTS)]
        try:
            log(f"Overpass request -> {ep} (attempt {attempt + 1})")
            req = urllib.request.Request(ep, data=data, headers={"User-Agent": UA})
            raw = urllib.request.urlopen(req, timeout=180).read()
            res = json.loads(raw)
            os.makedirs(os.path.dirname(cache_path), exist_ok=True)
            with open(cache_path, "wb") as f:
                f.write(raw)
            return res
        except Exception as ex:  # busy servers: back off politely
            last = ex
            log("  failed:", ex)
            time.sleep(5 + attempt * 5)
    sys.exit(f"Overpass failed: {last}")


# --- geometry -------------------------------------------------------------------------------------

class Proj:
    def __init__(self, lat0, lon0):
        self.lat0, self.lon0 = lat0, lon0
        self.kx = math.radians(1) * R_EARTH * math.cos(math.radians(lat0))
        self.ky = math.radians(1) * R_EARTH

    def __call__(self, lat, lon):
        return ((lon - self.lon0) * self.kx, (lat - self.lat0) * self.ky)


def r2(v):
    return round(v, 2)


def pts_out(pts):
    return [[r2(x), r2(y)] for x, y in pts]


def signed_area(poly):
    a = 0.0
    for i in range(len(poly)):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % len(poly)]
        a += x1 * y2 - x2 * y1
    return a / 2.0


def centroid(poly):
    a = signed_area(poly)
    if abs(a) < 1e-9:
        return (sum(p[0] for p in poly) / len(poly), sum(p[1] for p in poly) / len(poly))
    cx = cy = 0.0
    for i in range(len(poly)):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % len(poly)]
        c = x1 * y2 - x2 * y1
        cx += (x1 + x2) * c
        cy += (y1 + y2) * c
    return (cx / (6 * a), cy / (6 * a))


def hull(points):
    pts = sorted(set(points))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def min_area_rect(poly):
    """Oriented bounding box: (cx, cy, w, d, angle). angle = direction of the w axis (rad, from +x/east, CCW)."""
    h = hull(poly)
    best = None
    for i in range(len(h)):
        x1, y1 = h[i]
        x2, y2 = h[(i + 1) % len(h)]
        ang = math.atan2(y2 - y1, x2 - x1)
        c, s = math.cos(ang), math.sin(ang)
        us = [x * c + y * s for x, y in h]
        vs = [-x * s + y * c for x, y in h]
        u0, u1, v0, v1 = min(us), max(us), min(vs), max(vs)
        area = (u1 - u0) * (v1 - v0)
        if best is None or area < best[0]:
            uc, vc = (u0 + u1) / 2, (v0 + v1) / 2
            best = (area, uc * c - vc * s, uc * s + vc * c, u1 - u0, v1 - v0, ang)
    _, cx, cy, w, d, ang = best
    # keep angle in (-pi/2, pi/2]
    while ang <= -math.pi / 2:
        ang += math.pi
    while ang > math.pi / 2:
        ang -= math.pi
    return cx, cy, w, d, ang


def seg_closest(p, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    L = dx * dx + dy * dy
    t = 0.0 if L < 1e-12 else max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / L))
    q = (ax + dx * t, ay + dy * t)
    return q, math.hypot(p[0] - q[0], p[1] - q[1])


def point_in_poly(p, poly):
    x, y = p
    inside = False
    for i in range(len(poly)):
        x1, y1 = poly[i]
        x2, y2 = poly[i - 1]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / ((y2 - y1) or 1e-12) + x1:
            inside = not inside
    return inside


def clip_polyline(pts, lo, hi):
    """Clip a polyline to an axis-aligned rect (Liang-Barsky per segment). Returns a list of polylines."""
    out, cur = [], []
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        t0, t1 = 0.0, 1.0
        dx, dy = x1 - x0, y1 - y0
        ok = True
        for p, q in ((-dx, x0 - lo[0]), (dx, hi[0] - x0), (-dy, y0 - lo[1]), (dy, hi[1] - y0)):
            if abs(p) < 1e-12:
                if q < 0:
                    ok = False
                    break
            else:
                r = q / p
                if p < 0:
                    t0 = max(t0, r)
                else:
                    t1 = min(t1, r)
        if not ok or t0 > t1:
            if len(cur) >= 2:
                out.append(cur)
            cur = []
            continue
        a = (x0 + dx * t0, y0 + dy * t0)
        b = (x0 + dx * t1, y0 + dy * t1)
        if not cur:
            cur = [a]
        elif math.hypot(cur[-1][0] - a[0], cur[-1][1] - a[1]) > 1e-6:
            if len(cur) >= 2:
                out.append(cur)
            cur = [a]
        cur.append(b)
        if t1 < 1.0:
            out.append(cur)
            cur = []
    if len(cur) >= 2:
        out.append(cur)
    return out


def clip_poly_to_rect(poly, lo, hi):
    """Sutherland-Hodgman polygon clip to an axis-aligned rect."""
    def clip(pl, inside, inter):
        res = []
        for i in range(len(pl)):
            cur, prev = pl[i], pl[i - 1]
            if inside(cur):
                if not inside(prev):
                    res.append(inter(prev, cur))
                res.append(cur)
            elif inside(prev):
                res.append(inter(prev, cur))
        return res

    def ix(x):
        return lambda a, b: (x, a[1] + (b[1] - a[1]) * (x - a[0]) / ((b[0] - a[0]) or 1e-12))

    def iy(y):
        return lambda a, b: (a[0] + (b[0] - a[0]) * (y - a[1]) / ((b[1] - a[1]) or 1e-12), y)
    pl = poly
    for inside, inter in ((lambda p: p[0] >= lo[0], ix(lo[0])), (lambda p: p[0] <= hi[0], ix(hi[0])),
                          (lambda p: p[1] >= lo[1], iy(lo[1])), (lambda p: p[1] <= hi[1], iy(hi[1]))):
        if not pl:
            break
        pl = clip(pl, inside, inter)
    return pl


def offset_polyline(pts, d):
    """Offset to the left (d > 0) or right (d < 0) using mitred normals."""
    n = len(pts)
    out = []
    for i in range(n):
        if i == 0:
            tx, ty = pts[1][0] - pts[0][0], pts[1][1] - pts[0][1]
        elif i == n - 1:
            tx, ty = pts[-1][0] - pts[-2][0], pts[-1][1] - pts[-2][1]
        else:
            ax, ay = pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]
            bx, by = pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]
            la, lb = math.hypot(ax, ay) or 1, math.hypot(bx, by) or 1
            tx, ty = ax / la + bx / lb, ay / la + by / lb
        L = math.hypot(tx, ty) or 1
        tx, ty = tx / L, ty / L
        nx, ny = -ty, tx
        scale = 1.0
        if 0 < i < n - 1:
            ax, ay = pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]
            la = math.hypot(ax, ay) or 1
            cosh = (-ay / la) * nx + (ax / la) * ny
            scale = 1.0 / max(cosh, 0.5)
        out.append((pts[i][0] + nx * d * scale, pts[i][1] + ny * d * scale))
    return out


class SegIndex:
    """Spatial hash of road centreline segments (for 'is this point on a road?' and nearest road)."""

    def __init__(self, cell=20.0):
        self.cell = cell
        self.grid = {}

    def add(self, a, b, info):
        c = self.cell
        x0, x1 = sorted((a[0], b[0]))
        y0, y1 = sorted((a[1], b[1]))
        for gx in range(int(math.floor(x0 / c)), int(math.floor(x1 / c)) + 1):
            for gy in range(int(math.floor(y0 / c)), int(math.floor(y1 / c)) + 1):
                self.grid.setdefault((gx, gy), []).append((a, b, info))

    def near(self, p, r):
        c = self.cell
        seen = set()
        for gx in range(int(math.floor((p[0] - r) / c)), int(math.floor((p[0] + r) / c)) + 1):
            for gy in range(int(math.floor((p[1] - r) / c)), int(math.floor((p[1] + r) / c)) + 1):
                for s in self.grid.get((gx, gy), ()):
                    k = id(s)
                    if k not in seen:
                        seen.add(k)
                        yield s


def split_where(pts, keep, step=1.0):
    """Resample a polyline every `step` m and keep only the runs where keep(point) is True."""
    runs, cur = [], []
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        n = max(1, int(math.ceil(L / step)))
        for k in range(n + (1 if i == len(pts) - 2 else 0)):
            t = k / n
            p = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            if keep(p):
                cur.append(p)
            else:
                if len(cur) >= 2:
                    runs.append(cur)
                cur = []
    if len(cur) >= 2:
        runs.append(cur)
    # simplify collinear resample points
    out = []
    for r in runs:
        s = [r[0]]
        for j in range(1, len(r) - 1):
            ax, ay = r[j][0] - s[-1][0], r[j][1] - s[-1][1]
            bx, by = r[j + 1][0] - r[j][0], r[j + 1][1] - r[j][1]
            if abs(ax * by - ay * bx) > 0.02 * (math.hypot(ax, ay) * math.hypot(bx, by) + 1e-9):
                s.append(r[j])
        s.append(r[-1])
        if sum(math.hypot(s[i + 1][0] - s[i][0], s[i + 1][1] - s[i][1]) for i in range(len(s) - 1)) > 1.5:
            out.append(s)
    return out


def parse_len(v):
    if v is None:
        return None
    try:
        v = v.strip().lower().replace(",", ".")
        if v.endswith("'"):
            return float(v[:-1]) * 0.3048
        for suf in (" m", "m"):
            if v.endswith(suf):
                v = v[: -len(suf)]
        return float(v)
    except Exception:
        return None


def assemble_rings(ways):
    """Join member way geometries into closed rings."""
    segs = [list(w) for w in ways if len(w) >= 2]
    rings = []
    while segs:
        ring = segs.pop(0)
        changed = True
        while ring[0] != ring[-1] and changed:
            changed = False
            for i, s in enumerate(segs):
                if s[0] == ring[-1]:
                    ring += s[1:]
                elif s[-1] == ring[-1]:
                    ring += s[::-1][1:]
                elif s[-1] == ring[0]:
                    ring = s[:-1] + ring
                elif s[0] == ring[0]:
                    ring = s[::-1][:-1] + ring
                else:
                    continue
                segs.pop(i)
                changed = True
                break
        if ring[0] == ring[-1] and len(ring) >= 4:
            rings.append(ring)
    return rings


# --- conversion -----------------------------------------------------------------------------------

def building_kind(tags, area):
    b = tags.get("building", "yes")
    if b in HOUSE_TAGS:
        return "house" if area >= 35 else "shed"
    if b in SHED_TAGS:
        return "shed"
    if b == "apartments" or b == "dormitory":
        return "apartments"
    if b in CHURCH_TAGS or tags.get("amenity") == "place_of_worship":
        return "church"
    if b in CIVIC_TAGS or tags.get("amenity") in ("school", "kindergarten", "library", "community_centre"):
        return "civic"
    if b in COMMERCIAL_TAGS or "shop" in tags or tags.get("amenity") in ("pub", "cafe", "restaurant", "bar", "fast_food", "pharmacy"):
        return "shop"
    # building=yes: guess from size (alt-history: almost everything small is a house)
    if area < 30:
        return "shed"
    if area <= 420:
        return "house"
    return "other"


def convert(osm, bb, name, display, size_label):
    s, w, n, e = bb
    lat0, lon0 = (s + n) / 2, (w + e) / 2
    P = Proj(lat0, lon0)
    lo = P(s, w)
    hi = P(n, e)
    margin = 25.0
    lo_m = (lo[0] - margin, lo[1] - margin)
    hi_m = (hi[0] + margin, hi[1] + margin)

    def geom(el):
        return [P(g["lat"], g["lon"]) for g in el.get("geometry", []) if g]

    roads, paths, buildings, landuse, water, waterways, trees, addrs, parcels, barriers = [], [], [], [], [], [], [], [], [], []
    for el in osm["elements"]:
        t = el.get("tags", {})
        typ = el["type"]
        if typ == "node":
            p = P(el["lat"], el["lon"])
            if t.get("natural") == "tree":
                if lo_m[0] <= p[0] <= hi_m[0] and lo_m[1] <= p[1] <= hi_m[1]:
                    trees.append([r2(p[0]), r2(p[1])])
            if "addr:housenumber" in t:
                addrs.append({"pt": [r2(p[0]), r2(p[1])], "num": t["addr:housenumber"], "street": t.get("addr:street", "")})
            continue
        if typ == "relation":
            if "building" in t:
                outers = [[P(g["lat"], g["lon"]) for g in m.get("geometry", [])] for m in el.get("members", []) if m.get("role") == "outer" and m.get("type") == "way"]
                for ring in assemble_rings(outers):
                    buildings.append((el["id"], "r", t, ring))
            elif t.get("natural") == "water":
                outers = [[P(g["lat"], g["lon"]) for g in m.get("geometry", [])] for m in el.get("members", []) if m.get("role") == "outer"]
                for ring in assemble_rings(outers):
                    water.append({"type": t.get("water", "water"), "name": t.get("name", ""), "poly": ring})
            continue
        g = geom(el)
        if len(g) < 2:
            continue
        closed = len(g) >= 4 and g[0] == g[-1]
        hw = t.get("highway")
        if hw:
            if t.get("area") == "yes" or hw in ("platform", "construction", "proposed"):
                continue
            if hw in ROAD_TYPES:
                base_w, fp_likely = ROAD_TYPES[hw]
                lanes = None
                try:
                    lanes = int(t.get("lanes", "").split(";")[0])
                except ValueError:
                    pass
                width = parse_len(t.get("width")) or (max(base_w, lanes * 3.3) if lanes and hw not in ("service",) else base_w)
                if hw == "service" and t.get("service") in ("driveway", "parking_aisle", "drive-through"):
                    width = 3.2
                sw = t.get("sidewalk", t.get("sidewalk:both"))
                if sw is None:
                    l, r = t.get("sidewalk:left"), t.get("sidewalk:right")
                    if l or r:
                        sw = "both" if (l not in (None, "no") and r not in (None, "no")) else ("left" if l not in (None, "no") else "right")
                inferred = False
                if sw is None:
                    sw = "both" if fp_likely else "none"
                    inferred = True
                elif sw in ("separate", "yes"):
                    sw = "both" if sw == "yes" else "separate"
                elif sw not in ("both", "left", "right"):
                    sw = "none"
                for part in clip_polyline(g, lo_m, hi_m):
                    roads.append({"id": el["id"], "type": hw, "service": t.get("service", ""), "name": t.get("name", ""),
                                  "ref": t.get("ref", ""), "width": r2(width), "lanes": lanes, "oneway": t.get("oneway") in ("yes", "1", "true"),
                                  "bridge": t.get("bridge", "no") not in ("no",), "tunnel": t.get("tunnel", "no") not in ("no",),
                                  "layer": int(t.get("layer", "0")) if t.get("layer", "0").lstrip("-").isdigit() else 0,
                                  "surface": t.get("surface", ""), "sidewalk": sw, "sidewalk_inferred": inferred, "pts": part})
            elif hw in PATH_TYPES:
                width = parse_len(t.get("width")) or PATH_TYPES[hw]
                kind = "footpath" if (t.get("footway") == "sidewalk" or t.get("path") == "sidewalk") else hw
                for part in clip_polyline(g, lo_m, hi_m):
                    paths.append({"id": el["id"], "type": kind, "width": r2(width), "name": t.get("name", ""), "pts": part})
            continue
        if "building" in t and closed:
            buildings.append((el["id"], "w", t, g))
            continue
        if t.get("barrier") in ("fence", "wall", "hedge"):
            for part in clip_polyline(g, lo_m, hi_m):
                barriers.append({"type": t["barrier"], "pts": pts_out(part)})
            continue
        if t.get("boundary") == "lot" or "lot" in t:
            if closed:
                parcels.append({"id": el["id"], "poly": pts_out(g[:-1])})
            continue
        lu, le, nat = t.get("landuse"), t.get("leisure"), t.get("natural")
        if nat in WATER_NATURAL or lu in ("reservoir", "basin"):
            if closed:
                water.append({"type": nat or lu, "name": t.get("name", ""), "poly": g})
            continue
        if "waterway" in t and not closed:
            ww = t["waterway"]
            width = parse_len(t.get("width")) or {"river": 25.0, "canal": 10.0, "stream": 3.0, "drain": 2.0, "ditch": 1.5}.get(ww, 2.0)
            for part in clip_polyline(g, lo_m, hi_m):
                waterways.append({"type": ww, "width": r2(width), "name": t.get("name", ""), "tunnel": t.get("tunnel", "no") != "no", "pts": pts_out(part)})
            continue
        if closed:
            cls = None
            if le in GREEN_LEISURE:
                cls = "park" if le not in ("pitch",) else "pitch"
            elif lu in GREEN_LANDUSE:
                cls = "grass"
            elif nat in WOOD or lu == "forest":
                cls = "wood"
            elif lu in ("residential", "commercial", "retail", "industrial", "education", "religious"):
                cls = lu
            elif le in ("swimming_pool",) or t.get("amenity") == "parking":
                cls = le or "parking"
            if cls:
                landuse.append({"type": cls, "name": t.get("name", ""), "poly": g})

    # --- roads: index + intersections
    car = [r for r in roads if not r["tunnel"]]
    idx = SegIndex()
    for ri, r in enumerate(car):
        for i in range(len(r["pts"]) - 1):
            idx.add(r["pts"][i], r["pts"][i + 1], ri)
    node_count = {}
    for r in car:
        for k, p in enumerate(r["pts"]):
            key = (round(p[0], 1), round(p[1], 1))
            node_count[key] = node_count.get(key, 0) + (2 if 0 < k < len(r["pts"]) - 1 else 1)
    junctions = [[r2(k[0]), r2(k[1])] for k, c in node_count.items() if c >= 3]

    def on_carriageway(p, pad=0.0, skip=None):
        for a, b, ri in idx.near(p, 12.0):
            if ri == skip:
                continue
            r = car[ri]
            if r["type"] == "service" and r["width"] < 4:
                continue
            _, d = seg_closest(p, a, b)
            if d < r["width"] / 2 + pad:
                return True
        return False

    # Kerbs + inferred footpaths: offset lines along each car road, cut where they cross other roads.
    kerbs, footpaths = [], []
    has_mapped_sidewalks = any(p["type"] == "footpath" for p in paths)
    VERGE, FP_W = 1.6, 1.5
    # Mapped sidewalks (footway=sidewalk) win: don't infer a second footpath right next to one.
    walk_idx = SegIndex(10.0)
    for pth in paths:
        if pth["type"] in ("footpath", "footway", "path", "pedestrian"):
            for i in range(len(pth["pts"]) - 1):
                walk_idx.add(pth["pts"][i], pth["pts"][i + 1], 0)

    def near_mapped_walk(p, r=3.2):
        return any(seg_closest(p, a, b)[1] < r for a, b, _ in walk_idx.near(p, r))
    for ri, r in enumerate(car):
        if r["type"] in ("service",) and r["width"] < 5:
            continue
        hwid = r["width"] / 2
        for side in (1, -1):
            edge = offset_polyline(r["pts"], side * hwid)
            for run in split_where(edge, lambda p: not on_carriageway(p, -0.05) and lo[0] - 5 <= p[0] <= hi[0] + 5 and lo[1] - 5 <= p[1] <= hi[1] + 5):
                kerbs.append({"road": ri, "pts": pts_out(run)})
            want = r["sidewalk"] == "both" or (r["sidewalk"] == "left" and side == 1) or (r["sidewalk"] == "right" and side == -1)
            if want and not (r["sidewalk"] == "separate"):
                off = hwid + VERGE + FP_W / 2
                line = offset_polyline(r["pts"], side * off)
                for run in split_where(line, lambda p: not on_carriageway(p, FP_W / 2 + 0.3) and not near_mapped_walk(p) and lo[0] - 5 <= p[0] <= hi[0] + 5 and lo[1] - 5 <= p[1] <= hi[1] + 5):
                    footpaths.append({"road": ri, "side": "left" if side == 1 else "right", "width": FP_W, "inferred": r["sidewalk_inferred"], "pts": pts_out(run)})

    # --- buildings
    out_b = []
    addr_used = set()
    for oid, ot, t, ring in buildings:
        poly = ring[:-1] if ring[0] == ring[-1] else ring
        if len(poly) < 3:
            continue
        if signed_area(poly) < 0:
            poly = poly[::-1]
        area = signed_area(poly)
        c = centroid(poly)
        if not (lo[0] <= c[0] <= hi[0] and lo[1] <= c[1] <= hi[1]) or area < 6:
            continue
        cx, cy, bw, bd, ang = min_area_rect(poly)
        kind = building_kind(t, area)
        # nearest car road -> front direction, snapped to an OBB face
        best = None
        for a, b, ri in idx.near((cx, cy), 80.0):
            rr = car[ri]
            if rr["type"] == "service" and rr["service"] in ("driveway", "parking_aisle"):
                continue
            q, d = seg_closest((cx, cy), a, b)
            score = d - (8.0 if rr["name"] else 0.0)
            if best is None or score < best[0]:
                best = (score, q, d, rr["name"], ri)
        front = None
        face = 0
        road_name, road_dist, road_pt, road_w = "", None, None, None
        if best:
            _, q, d, road_name, _ri = best
            road_w = car[_ri]["width"]
            vx, vy = q[0] - cx, q[1] - cy
            L = math.hypot(vx, vy) or 1
            vx, vy = vx / L, vy / L
            axes = [(math.cos(ang), math.sin(ang)), (-math.sin(ang), math.cos(ang))]
            cand = [(axes[0][0], axes[0][1], 0), (-axes[0][0], -axes[0][1], 1), (axes[1][0], axes[1][1], 2), (-axes[1][0], -axes[1][1], 3)]
            fx, fy, face = max(cand, key=lambda a: a[0] * vx + a[1] * vy)
            front = [round(fx, 4), round(fy, 4)]
            road_dist = r2(d)
            road_pt = [r2(q[0]), r2(q[1])]
        # address: addr on the building itself, else an address node inside / nearest within 25 m
        num, street = t.get("addr:housenumber", ""), t.get("addr:street", "")
        if not num:
            bestA = None
            for ai, a in enumerate(addrs):
                if ai in addr_used:
                    continue
                inside = point_in_poly(a["pt"], poly)
                d = 0.0 if inside else math.hypot(a["pt"][0] - cx, a["pt"][1] - cy)
                if d < 25 and (bestA is None or d < bestA[0]):
                    bestA = (d, ai)
            if bestA and kind in ("house", "apartments", "shop", "church", "civic", "other"):
                addr_used.add(bestA[1])
                num, street = addrs[bestA[1]]["num"], addrs[bestA[1]]["street"]
        levels = t.get("building:levels")
        try:
            levels = float(levels) if levels else None
        except ValueError:
            levels = None
        out_b.append({
            "id": oid if ot == "w" else -oid, "kind": kind, "building": t.get("building", "yes"),
            "name": t.get("name", ""), "addr": (num + " " + street).strip() if num else "", "street": street or road_name,
            "height": parse_len(t.get("height")), "levels": levels, "roof_shape": t.get("roof:shape", ""),
            "roof_colour": t.get("roof:colour", ""), "wall_colour": t.get("building:colour", ""),
            "area": r2(area), "center": [r2(c[0]), r2(c[1])],
            "obb": {"c": [r2(cx), r2(cy)], "size": [r2(bw), r2(bd)], "angle": round(ang, 5)},
            "front": front, "front_face": face, "road_dist": road_dist, "road_pt": road_pt, "road_width": road_w,
            "poly": pts_out(poly),
        })

    for r in roads:
        r["pts"] = pts_out(r["pts"])
    for p in paths:
        p["pts"] = pts_out(p["pts"])
    for l in landuse:
        cp = clip_poly_to_rect(l["poly"][:-1] if l["poly"][0] == l["poly"][-1] else l["poly"], lo_m, hi_m)
        l["poly"] = pts_out(cp)
    landuse = [l for l in landuse if len(l["poly"]) >= 3]
    for wv in water:
        cp = clip_poly_to_rect(wv["poly"][:-1] if wv["poly"][0] == wv["poly"][-1] else wv["poly"], lo_m, hi_m)
        wv["poly"] = pts_out(cp)
    water = [wv for wv in water if len(wv["poly"]) >= 3]

    kinds = {}
    for b in out_b:
        kinds[b["kind"]] = kinds.get(b["kind"], 0) + 1
    out = {
        "format": "santa-sim-town", "version": 1,
        "name": name, "display_name": display,
        "attribution": "\u00a9 OpenStreetMap contributors",
        "license": "ODbL 1.0 (https://opendatacommons.org/licenses/odbl/). See data/towns/ATTRIBUTION.md",
        "source": {"bbox_swne": [round(v, 7) for v in bb], "size": size_label, "fetched_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                   "osm_base": osm.get("osm3s", {}).get("timestamp_osm_base", "")},
        "projection": {"type": "local_equirectangular", "center_latlon": [round(lat0, 7), round(lon0, 7)],
                        "units": "metres", "axes": "x = east, y = north. Godot: Vector3(x, 0, -y)"},
        "extent": {"min": [r2(lo[0]), r2(lo[1])], "max": [r2(hi[0]), r2(hi[1])]},
        "stats": {"buildings": len(out_b), "kinds": kinds, "roads": len(roads), "paths": len(paths), "footpaths_inferred": len(footpaths),
                  "trees": len(trees), "addresses": len(addrs), "parcels": len(parcels), "has_mapped_sidewalks": has_mapped_sidewalks},
        "roads": roads, "junctions": junctions, "kerbs": kerbs, "footpaths": footpaths, "paths": paths,
        "buildings": out_b, "addresses": addrs, "parcels": parcels, "barriers": barriers,
        "landuse": landuse, "water": water, "waterways": waterways, "trees": trees,
    }
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--town", required=True, help="file name: data/towns/<town>.json")
    ap.add_argument("--display", default="", help="pretty name shown in game")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--bbox", help="south,west,north,east in degrees")
    g.add_argument("--center", help="lat,lon (use with --size)")
    g.add_argument("--place", help="place name, geocoded once with Nominatim (use with --size)")
    ap.add_argument("--size", type=float, default=500.0, help="square side in metres for --center/--place (default 500, keep <= 1500)")
    ap.add_argument("--refresh", action="store_true", help="ignore the cached Overpass response")
    ap.add_argument("--out", default=os.path.join(ROOT, "data", "towns"))
    ap.add_argument("--cache", default=os.path.join(ROOT, "tools", "osm", "cache"))
    a = ap.parse_args()
    if a.bbox:
        bb = tuple(float(v) for v in a.bbox.split(","))
        size_label = "bbox"
    else:
        lat, lon = geocode(a.place) if a.place else tuple(float(v) for v in a.center.split(","))
        bb = bbox_around(lat, lon, a.size)
        size_label = f"{a.size:.0f} m square"
    q = overpass_query(bb, 60.0)
    key = hashlib.sha1(q.encode()).hexdigest()[:10]
    cache_path = os.path.join(a.cache, f"{a.town}_{key}.overpass.json")
    osm = fetch(q, cache_path, a.refresh)
    town = convert(osm, bb, a.town, a.display or a.town, size_label)
    os.makedirs(a.out, exist_ok=True)
    path = os.path.join(a.out, a.town + ".json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(town, f, separators=(",", ":"), ensure_ascii=False)
    log(f"wrote {path} ({os.path.getsize(path) / 1024:.0f} KB)")
    log(json.dumps(town["stats"]))


if __name__ == "__main__":
    main()
