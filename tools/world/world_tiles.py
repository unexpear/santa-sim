#!/usr/bin/env python3
"""Santa Sim world tiler: a Geofabrik .osm.pbf -> streamed world packs in data/world/.

Two stages (see WORLD-STREAMING.md):

  scan   one pass over the whole .pbf (pyosmium). Buildings, roads, trees, landuse, water, waterways and
         the coastline are sorted into 1 x 1 degree blocks and spilled to .tools/osm/work/ (lat/lon).
  build  per block, in parallel: project every feature into its ~1 km tile's own local frame, fit the
         same oriented boxes / front doors as tools/osm/osm_import.py, rasterise the ground (landuse,
         water, ocean from the coastline) and write one compact pack per block to data/world/blocks/.

  python tools/world/world_tiles.py scan  --pbf .tools/osm/australia-latest.osm.pbf
  python tools/world/world_tiles.py build --regions sydney,brisbane,mudgee
  python tools/world/world_tiles.py build --all
  python tools/world/world_tiles.py index

Tile grid: 100 tiles per degree of longitude x 111 per degree of latitude (~0.8-1.1 km x 1.0 km), keyed by
ix = floor(lon * 100), iy = floor(lat * 111). Coordinates inside a tile are metres (decimetre ints) around
the tile centre, local equirectangular, x = east, y = north, so nothing far from an origin ever hits a float.

Map data (c) OpenStreetMap contributors, ODbL 1.0. Every file this writes is OSM-derived and stays ODbL.
"""
import argparse, glob, json, math, os, pickle, struct, sys, time, zlib, datetime
from concurrent.futures import ProcessPoolExecutor, as_completed

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "osm"))
import osm_import as OI  # noqa: E402  (same OBB / kind / width rules as the Paddington import)

WORK = os.path.join(ROOT, ".tools", "osm", "work")
OUT = os.path.join(ROOT, "data", "world")
TLON, TLAT, CELLS = 100, 111, 32
R = 6378137.0
DEG = math.radians(1.0) * R
PACK_VERSION = 1
TILE_VERSION = 1

REGIONS = {  # s, w, n, e
    "sydney": (-34.25, 150.55, -33.45, 151.40),
    "brisbane": (-27.75, 152.75, -27.15, 153.25),  # includes Paddington QLD (the town scene)
    "mudgee": (-32.70, 149.45, -32.50, 149.70),
    "melbourne": (-38.15, 144.55, -37.55, 145.35),
    "perth": (-32.30, 115.70, -31.70, 116.05),
    "adelaide": (-35.15, 138.45, -34.70, 138.75),
    "hobart": (-43.00, 147.15, -42.75, 147.45),
    "darwin": (-12.55, 130.80, -12.33, 131.05),
    "canberra": (-35.50, 148.95, -35.10, 149.25),
    "australia": (-44.0, 112.0, -9.0, 154.5),
}
KINDS = ["house", "shed", "shop", "apartments", "church", "civic", "other"]
ROAD_ENUM = ["motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential", "living_street",
             "service", "road", "motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link", "busway", "track"]
# ground classes (also in scripts/world/world_tile.gd)
G_LAND, G_RES, G_COM, G_IND, G_GRASS, G_PITCH, G_WOOD, G_SAND, G_WATER, G_OCEAN, G_FARM = 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
AREA_TAGS = {
    "residential": G_RES, "commercial": G_COM, "retail": G_COM, "industrial": G_IND, "education": G_RES,
    "grass": G_GRASS, "recreation_ground": G_GRASS, "village_green": G_GRASS, "meadow": G_FARM, "cemetery": G_GRASS,
    "allotments": G_GRASS, "orchard": G_FARM, "farmland": G_FARM, "vineyard": G_FARM, "farmyard": G_FARM,
    "forest": G_WOOD, "reservoir": G_WATER, "basin": G_WATER,
}
LEISURE_TAGS = {"park": G_GRASS, "garden": G_GRASS, "golf_course": G_GRASS, "pitch": G_PITCH, "playground": G_GRASS,
                "nature_reserve": None, "common": G_GRASS, "dog_park": G_GRASS, "swimming_pool": G_WATER}
NATURAL_TAGS = {"wood": G_WOOD, "scrub": G_WOOD, "heath": G_FARM, "grassland": G_FARM, "water": G_WATER, "wetland": G_WATER,
                "bay": G_OCEAN, "beach": G_SAND, "sand": G_SAND}
DRAW_ORDER = [G_FARM, G_RES, G_COM, G_IND, G_GRASS, G_PITCH, G_WOOD, G_SAND, G_WATER, G_OCEAN]
KEEP_TAGS = ("building", "building:levels", "height", "roof:shape", "roof:material", "addr:housenumber", "addr:street",
             "amenity", "shop")


def log(*a):
    print(*a, flush=True)


def block_of(lon, lat):
    return (math.floor(lat), math.floor(lon))


def bkey(by, bx):
    return "%d_%d" % (by, bx)


def tile_centre(ix, iy):
    return ((iy + 0.5) / TLAT, (ix + 0.5) / TLON)


class TileProj:
    """lat/lon -> metres around the tile centre (local equirectangular)."""
    def __init__(self, ix, iy):
        self.lat0, self.lon0 = tile_centre(ix, iy)
        self.kx = DEG * math.cos(math.radians(self.lat0))

    def __call__(self, lon, lat):
        return ((lon - self.lon0) * self.kx, (lat - self.lat0) * DEG)


# --------------------------------------------------------------------------------------------- scan

class Spill:
    def __init__(self, path):
        self.path = path
        self.buf = {}
        self.n = 0
        os.makedirs(path, exist_ok=True)

    def add(self, key, rec):
        self.buf.setdefault(key, []).append(rec)
        self.n += 1
        if self.n >= 400000:
            self.flush()

    def flush(self):
        for k, recs in self.buf.items():
            with open(os.path.join(self.path, k + ".pkl"), "ab") as f:
                pickle.dump(recs, f, protocol=pickle.HIGHEST_PROTOCOL)
        self.buf.clear()
        self.n = 0


def _blocks_for_bbox(pts):
    lons = [p[0] for p in pts]
    lats = [p[1] for p in pts]
    out = []
    for by in range(math.floor(min(lats)), math.floor(max(lats)) + 1):
        for bx in range(math.floor(min(lons)), math.floor(max(lons)) + 1):
            out.append(bkey(by, bx))
    return out


def scan(args):
    import osmium
    t0 = time.time()
    if os.path.isdir(WORK):
        for f in glob.glob(os.path.join(WORK, "*.pkl")):
            os.remove(f)
    sp = Spill(WORK)
    filt = osmium.filter.KeyFilter("building", "highway", "landuse", "leisure", "natural", "waterway", "amenity")
    fp = (osmium.FileProcessor(args.pbf).with_locations(args.storage)
          .with_areas(osmium.filter.KeyFilter("building", "landuse", "leisure", "natural", "amenity"))
          .with_filter(filt))
    cnt = {"buildings": 0, "roads": 0, "trees": 0, "areas": 0, "waterways": 0, "coast": 0, "bad": 0}
    last = time.time()
    for o in fp:
        try:
            if o.is_node():
                if o.tags.get("natural") == "tree":
                    lon, lat = o.location.lon, o.location.lat
                    sp.add(bkey(*block_of(lon, lat)), ("t", round(lon, 7), round(lat, 7)))
                    cnt["trees"] += 1
            elif o.is_way():
                t = o.tags
                hw = t.get("highway")
                nat = t.get("natural")
                ww = t.get("waterway")
                if hw in OI.ROAD_TYPES or hw == "track":
                    pts = [(round(n.lon, 7), round(n.lat, 7)) for n in o.nodes]
                    if len(pts) < 2:
                        continue
                    rec = ("r", o.id, hw, t.get("width"), t.get("lanes"), t.get("service", ""),
                           t.get("bridge", "no") != "no", t.get("tunnel", "no") != "no", bool(t.get("name")), pts)
                    for k in _blocks_for_bbox(pts):
                        sp.add(k, rec)
                    cnt["roads"] += 1
                elif nat == "coastline":
                    pts = [(round(n.lon, 7), round(n.lat, 7)) for n in o.nodes]
                    if len(pts) >= 2:
                        for k in _blocks_for_bbox(pts):
                            sp.add(k, ("c", pts))
                        cnt["coast"] += 1
                elif ww in ("river", "stream", "canal", "drain") and t.get("tunnel", "no") == "no":
                    pts = [(round(n.lon, 7), round(n.lat, 7)) for n in o.nodes]
                    if len(pts) >= 2:
                        width = OI.parse_len(t.get("width")) or {"river": 25.0, "canal": 10.0, "stream": 3.0, "drain": 2.0}[ww]
                        for k in _blocks_for_bbox(pts):
                            sp.add(k, ("w", ww, width, pts))
                        cnt["waterways"] += 1
            elif o.is_area():
                t = o.tags
                oid = o.orig_id() if o.from_way() else -o.orig_id()
                rings = [[(round(n.lon, 7), round(n.lat, 7)) for n in r] for r in o.outer_rings()]
                if "building" in t:
                    tags = {k: t.get(k) for k in KEEP_TAGS if k in t}
                    for ring in rings:
                        if len(ring) < 4:
                            continue
                        lon = sum(p[0] for p in ring) / len(ring)
                        lat = sum(p[1] for p in ring) / len(ring)
                        sp.add(bkey(*block_of(lon, lat)), ("b", oid, tags, ring))
                        cnt["buildings"] += 1
                    continue
                cls = None
                lu, le, nat = t.get("landuse"), t.get("leisure"), t.get("natural")
                if nat in NATURAL_TAGS:
                    cls = NATURAL_TAGS[nat]
                elif le in LEISURE_TAGS:
                    cls = LEISURE_TAGS[le]
                elif lu in AREA_TAGS:
                    cls = AREA_TAGS[lu]
                if cls is None:
                    continue
                for ring in rings:
                    if len(ring) < 4:
                        continue
                    for k in _blocks_for_bbox(ring):
                        sp.add(k, ("a", cls, ring))
                    cnt["areas"] += 1
        except osmium.InvalidLocationError:
            cnt["bad"] += 1
        if time.time() - last > 30:
            last = time.time()
            log("[scan] %5.0f s  %s" % (last - t0, cnt))
    sp.flush()
    meta = {"pbf": os.path.basename(args.pbf), "pbf_bytes": os.path.getsize(args.pbf), "scanned_utc": _utc(),
            "seconds": round(time.time() - t0), "counts": cnt}
    try:
        h = osmium.io.Reader(args.pbf, osmium.osm.osm_entity_bits.NOTHING).header()
        meta["osm_base"] = h.get("osmosis_replication_timestamp", "")
    except Exception:
        pass
    with open(os.path.join(WORK, "scan.json"), "w") as f:
        json.dump(meta, f, indent=1)
    log("[scan] done in %.0f s: %s" % (time.time() - t0, cnt))


def _utc():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# --------------------------------------------------------------------------------------------- build

def _load_block(key):
    recs = []
    p = os.path.join(WORK, key + ".pkl")
    with open(p, "rb") as f:
        while True:
            try:
                recs.extend(pickle.load(f))
            except EOFError:
                break
    return recs


def _tiles_on_segment(a, b):
    """Tile keys a lon/lat segment passes through (sampled every ~1/4 tile, plus both ends)."""
    dx, dy = (b[0] - a[0]) * TLON, (b[1] - a[1]) * TLAT
    n = max(1, int(math.ceil(max(abs(dx), abs(dy)) * 4)))
    out = set()
    for i in range(n + 1):
        t = i / n
        out.add((math.floor((a[0] + (b[0] - a[0]) * t) * TLON), math.floor((a[1] + (b[1] - a[1]) * t) * TLAT)))
    return out


def _dm(v):
    return max(-32767, min(32767, int(round(v * 10.0))))


class Grid:
    def __init__(self, cell=60.0):
        self.c = cell
        self.g = {}

    def add(self, a, b, item):
        x0, x1 = sorted((a[0], b[0]))
        y0, y1 = sorted((a[1], b[1]))
        for gx in range(int(math.floor(x0 / self.c)), int(math.floor(x1 / self.c)) + 1):
            for gy in range(int(math.floor(y0 / self.c)), int(math.floor(y1 / self.c)) + 1):
                self.g.setdefault((gx, gy), []).append((a, b, item))

    def near(self, p, r):
        seen = set()
        for gx in range(int(math.floor((p[0] - r) / self.c)), int(math.floor((p[0] + r) / self.c)) + 1):
            for gy in range(int(math.floor((p[1] - r) / self.c)), int(math.floor((p[1] + r) / self.c)) + 1):
                for e in self.g.get((gx, gy), ()):
                    k = id(e)
                    if k not in seen:
                        seen.add(k)
                        yield e


def _ground(key, recs, by, bx):
    """Rasterise landuse/water/ocean for the block: returns a PIL 'L' image (3200 x 3552), north up."""
    from PIL import Image, ImageDraw
    W, H = TLON * CELLS, TLAT * CELLS
    sx, sy = TLON * CELLS, TLAT * CELLS

    def px(p):
        return ((p[0] - bx) * sx, (by + 1 - p[1]) * sy)
    coast = [r[1] for r in recs if r[0] == "c"]
    img = None
    if coast:
        m = Image.new("L", (W, H), 0)
        d = ImageDraw.Draw(m)
        for pts in coast:
            d.line([px(p) for p in pts], fill=1, width=1)
        seeds = []
        for pts in coast:
            for i in range(len(pts) - 1):
                a, b = px(pts[i]), px(pts[i + 1])
                vx, vy = b[0] - a[0], b[1] - a[1]
                L = math.hypot(vx, vy)
                if L < 0.5:
                    continue
                mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
                nx, ny = -vy / L, vx / L  # right of travel in pixel space = water
                seeds.append((mx + nx * 2.2, my + ny * 2.2, 2))
                seeds.append((mx - nx * 2.2, my - ny * 2.2, 3))
        pxl = m.load()
        for x, y, v in seeds:
            xi, yi = int(x), int(y)
            if 0 <= xi < W and 0 <= yi < H and pxl[xi, yi] == 0:
                ImageDraw.floodfill(m, (xi, yi), v)
        # leftover unknown = land; coastline pixels = water (thin line)
        img = m.point(lambda v: [G_LAND, G_OCEAN, G_OCEAN, G_LAND][v] if v < 4 else G_LAND)
        ocean = m.point(lambda v: 255 if v in (1, 2) else 0)
    else:
        img = Image.new("L", (W, H), G_LAND)
        ocean = None
    d = ImageDraw.Draw(img)
    areas = [r for r in recs if r[0] == "a"]
    for cls in DRAW_ORDER:
        for r in areas:
            if r[1] == cls:
                d.polygon([px(p) for p in r[2]], fill=cls)
    for r in recs:
        if r[0] == "w" and r[1] in ("river", "canal") and r[2] >= 12:
            wpx = max(1, int(round(r[2] / (DEG / sy))))
            d.line([px(p) for p in r[3]], fill=G_WATER, width=wpx)
    if ocean is not None:  # landuse polygons that spill over the sea (marine parks...) stay sea
        img.paste(G_OCEAN, mask=ocean)
    return img


def build_block(key, regions):
    t0 = time.time()
    by, bx = (int(v) for v in key.split("_"))
    recs = _load_block(key)
    s, w, n, e = by, bx, by + 1, bx + 1
    if regions:
        boxes = [REGIONS[r] for r in regions]
    else:
        boxes = [(s, w, n, e)]

    def wanted_tile(ix, iy):
        lat, lon = tile_centre(ix, iy)
        if not (by <= lat < by + 1 and bx <= lon < bx + 1):
            return False
        return any(b[0] - 0.006 <= lat <= b[2] + 0.006 and b[1] - 0.006 <= lon <= b[3] + 0.006 for b in boxes)

    has_land_features = any(r[0] in ("b", "r") for r in recs)
    has_coast = any(r[0] == "c" for r in recs)
    if not has_land_features and not has_coast:
        return key, None
    ground = _ground(key, recs, by, bx)
    # block metric frame (only for nearest-road search and directions)
    bp = TileProj(int((bx + 0.5) * TLON), int((by + 0.5) * TLAT))
    tiles = {}

    def T(ix, iy):
        t = tiles.get((ix, iy))
        if t is None:
            t = tiles[(ix, iy)] = {"b": [], "r": [], "t": [], "proj": TileProj(ix, iy)}
        return t

    # roads -> per-tile clipped polylines + block road index
    grid = Grid(60.0)
    roads = []
    for r in recs:
        if r[0] != "r":
            continue
        _, rid, hw, wtag, lanes, service, bridge, tunnel, named, pts = r
        if tunnel:
            continue
        base_w = OI.ROAD_TYPES.get(hw, (3.5, False))[0]
        try:
            ln = int(str(lanes).split(";")[0]) if lanes else None
        except ValueError:
            ln = None
        width = OI.parse_len(wtag) or (max(base_w, ln * 3.3) if ln and hw != "service" else base_w)
        if hw == "service" and service in ("driveway", "parking_aisle", "drive-through"):
            width = 3.2
        width = max(2.5, min(width, 40.0))
        ri = len(roads)
        roads.append((hw, width, named, service))
        bpts = [bp(*p) for p in pts]
        for i in range(len(bpts) - 1):
            grid.add(bpts[i], bpts[i + 1], ri)
        segs = {}
        for i in range(len(pts) - 1):
            for tk in _tiles_on_segment(pts[i], pts[i + 1]):
                segs.setdefault(tk, set()).add(i)
        for tk, idxs in segs.items():
            if not wanted_tile(*tk):
                continue
            tp = T(*tk).get("proj")
            idxs = sorted(idxs)
            runs, cur = [], [idxs[0]]
            for i in idxs[1:]:
                if i == cur[-1] + 1:
                    cur.append(i)
                else:
                    runs.append(cur)
                    cur = [i]
            runs.append(cur)
            for run in runs:
                local = [tp(*pts[i]) for i in range(run[0], run[-1] + 2)]
                for part in OI.clip_polyline(local, (-620.0, -600.0), (620.0, 600.0)):
                    T(*tk)["r"].append((ROAD_ENUM.index(hw) if hw in ROAD_ENUM else 9, width, (1 if bridge else 0) | (2 if named else 0), part))
    # trees
    for r in recs:
        if r[0] == "t":
            tk = (math.floor(r[1] * TLON), math.floor(r[2] * TLAT))
            if wanted_tile(*tk):
                T(*tk)["t"].append(T(*tk)["proj"](r[1], r[2]))
    # buildings
    for r in recs:
        if r[0] != "b":
            continue
        _, oid, tags, ring = r
        lon = sum(p[0] for p in ring[:-1]) / max(1, len(ring) - 1)
        lat = sum(p[1] for p in ring[:-1]) / max(1, len(ring) - 1)
        tk = (math.floor(lon * TLON), math.floor(lat * TLAT))
        if not wanted_tile(*tk):
            continue
        tp = T(*tk)["proj"]
        poly = [tp(*p) for p in (ring[:-1] if ring[0] == ring[-1] else ring)]
        if len(poly) < 3:
            continue
        if OI.signed_area(poly) < 0:
            poly = poly[::-1]
        area = OI.signed_area(poly)
        if area < 6:
            continue
        cx, cy, bw, bd, ang = OI.min_area_rect(poly)
        kind = OI.building_kind(tags, area)
        bc = bp(lon, lat)
        best = None
        for a, b, ri in grid.near(bc, 80.0):
            hw, rw, named, service = roads[ri]
            if hw == "service" and service in ("driveway", "parking_aisle"):
                continue
            q, dd = OI.seg_closest(bc, a, b)
            if dd > 80:
                continue
            score = dd - (8.0 if named else 0.0)
            if best is None or score < best[0]:
                best = (score, q, dd)
        face, fang, has_front = 0, 0.0, False
        if best:
            vx, vy = best[1][0] - bc[0], best[1][1] - bc[1]
            L = math.hypot(vx, vy) or 1.0
            vx, vy = vx / L, vy / L
            axes = [(math.cos(ang), math.sin(ang)), (-math.sin(ang), math.cos(ang))]
            cand = [(axes[0][0], axes[0][1], 0), (-axes[0][0], -axes[0][1], 1), (axes[1][0], axes[1][1], 2), (-axes[1][0], -axes[1][1], 3)]
            fx, fy, face = max(cand, key=lambda c: c[0] * vx + c[1] * vy)
            fang = math.atan2(fy, fx)
            has_front = True
        try:
            levels = float(tags.get("building:levels") or 0)
        except ValueError:
            levels = 0.0
        height = OI.parse_len(tags.get("height")) or 0.0
        rm = (tags.get("roof:material") or "").lower()
        roof = 1 if rm in ("roof_tiles", "tile", "tiles", "clay", "concrete") else (2 if rm in ("metal", "metal_sheet", "tin", "corrugated", "zinc", "steel") else 0)
        rs = (tags.get("roof:shape") or "").lower()
        roof |= {"flat": 4, "gabled": 8, "hipped": 12}.get(rs, 0)
        addr = ""
        if tags.get("addr:housenumber"):
            addr = (tags.get("addr:housenumber", "") + " " + tags.get("addr:street", "")).strip()[:60]
        T(*tk)["b"].append((oid, KINDS.index(kind), roof, min(255, int(round(levels * 2))), min(255, int(round(height))),
                            cx, cy, bw, bd, ang, face, has_front, fang, addr, area))
    # ground tiles: every wanted tile that is not uniform plain land/ocean or that has features
    W = TLON * CELLS
    gbytes = ground.tobytes()
    for iy in range(by * TLAT, (by + 1) * TLAT):
        for ix in range(bx * TLON, (bx + 1) * TLON):
            if not wanted_tile(ix, iy):
                continue
            col0 = (ix - bx * TLON) * CELLS
            row0 = ((by + 1) * TLAT - 1 - iy) * CELLS
            cells = bytearray()
            for rr in range(CELLS):
                o = (row0 + rr) * W + col0
                cells += gbytes[o:o + CELLS]
            uniform = cells.count(cells[0]) == len(cells)
            t = tiles.get((ix, iy))
            if t is None and uniform and cells[0] in (G_LAND, G_OCEAN):
                continue
            T(ix, iy)["g"] = bytes(cells)
    # overview raster: 4 cells per tile (~250 m), nearest
    from PIL import Image
    ov = ground.resize((TLON * 4, TLAT * 4), Image.NEAREST)
    data = _write_pack(key, by, bx, tiles, ov)
    nb = sum(len(t["b"]) for t in tiles.values())
    return key, {"tiles": len(tiles), "buildings": nb, "bytes": data, "seconds": round(time.time() - t0, 1)}


def _tile_blob(t):
    out = bytearray()
    g = t.get("g")
    out += struct.pack("<HHHHB", TILE_VERSION, len(t["b"]), len(t["r"]), len(t["t"]), 1 if g else 0)
    if g:
        out += g
    for (oid, kind, roof, lv2, h, cx, cy, bw, bd, ang, face, hf, fang, addr, area) in t["b"]:
        ab = addr.encode("utf-8")[:60]
        out += struct.pack("<qBBBBhhHHHhBBhB", oid, kind, roof, lv2, h, _dm(cx), _dm(cy), min(65535, int(round(bw * 10))),
                           min(65535, int(round(bd * 10))), min(65535, int(round(area))), int(round(ang * 10000)), face, 1 if hf else 0,
                           int(round(fang * 10000)), len(ab))
        out += ab
    for (typ, width, flags, pts) in t["r"]:
        out += struct.pack("<BBBH", typ, min(255, int(round(width * 4))), flags, len(pts))
        for x, y in pts:
            out += struct.pack("<hh", _dm(x), _dm(y))
    for x, y in t["t"]:
        out += struct.pack("<hh", _dm(x), _dm(y))
    return bytes(out)


def _write_pack(key, by, bx, tiles, ov):
    os.makedirs(os.path.join(OUT, "blocks"), exist_ok=True)
    blobs = []
    for (ix, iy), t in sorted(tiles.items()):
        raw = _tile_blob(t)
        blobs.append((ix, iy, zlib.compress(raw, 6), len(raw), len(t["b"]), 1 if t.get("g") else 0))
    ovc = zlib.compress(ov.tobytes(), 9)
    head = struct.pack("<4sHhhHHHIHHI", b"SSWP", PACK_VERSION, bx, by, TLON, TLAT, CELLS, len(blobs), ov.width, ov.height, len(ovc))
    table_len = len(blobs) * struct.calcsize("<iiIIIHH")
    off = len(head) + len(ovc) + table_len
    table = bytearray()
    for ix, iy, c, ulen, nb, fl in blobs:
        table += struct.pack("<iiIIIHH", ix, iy, off, len(c), ulen, min(nb, 65535), fl)
        off += len(c)
    path = os.path.join(OUT, "blocks", key + ".pack")
    with open(path + ".tmp", "wb") as f:
        f.write(head)
        f.write(ovc)
        f.write(table)
        for b in blobs:
            f.write(b[2])
    os.replace(path + ".tmp", path)
    return os.path.getsize(path)


def build(args):
    t0 = time.time()
    regions = [] if args.all else [r.strip() for r in args.regions.split(",") if r.strip()]
    for r in regions:
        if r not in REGIONS:
            sys.exit("unknown region %s (have: %s)" % (r, ", ".join(REGIONS)))
    keys = []
    for f in glob.glob(os.path.join(WORK, "*.pkl")):
        k = os.path.basename(f)[:-4]
        by, bx = (int(v) for v in k.split("_"))
        if regions:
            if not any(b[0] < by + 1 and b[2] > by and b[1] < bx + 1 and b[3] > bx for b in (REGIONS[r] for r in regions)):
                continue
        keys.append(k)
    log("[build] %d blocks (%s), %d workers" % (len(keys), ",".join(regions) or "all", args.jobs))
    done = {}
    with ProcessPoolExecutor(max_workers=args.jobs) as ex:
        futs = {ex.submit(build_block, k, regions): k for k in keys}
        for fu in as_completed(futs):
            k, info = fu.result()
            if info:
                done[k] = info
                log("[build] %s: %d tiles, %d buildings, %.1f MB, %.0f s" % (k, info["tiles"], info["buildings"], info["bytes"] / 1e6, info["seconds"]))
    _merge_index(done, regions or ["australia"])
    log("[build] done in %.0f s" % (time.time() - t0))


def _merge_index(done, regions):
    p = os.path.join(OUT, "index.json")
    idx = {}
    if os.path.exists(p):
        with open(p) as f:
            idx = json.load(f)
    scanm = {}
    sp = os.path.join(WORK, "scan.json")
    if os.path.exists(sp):
        with open(sp) as f:
            scanm = json.load(f)
    idx.update({"format": "santa-sim-world", "version": PACK_VERSION, "tiles_per_degree": [TLON, TLAT], "ground_cells": CELLS,
                "attribution": "\u00a9 OpenStreetMap contributors", "license": "ODbL 1.0 (OSM-derived)",
                "source": scanm.get("pbf", ""), "osm_base": scanm.get("osm_base", ""), "built_utc": _utc()})
    blocks = idx.get("blocks", {})
    blocks.update(done)
    for k in list(blocks):
        if not os.path.exists(os.path.join(OUT, "blocks", k + ".pack")):
            del blocks[k]
    idx["blocks"] = dict(sorted(blocks.items()))
    idx["regions"] = sorted(set(idx.get("regions", [])) | set(regions))
    idx["region_boxes"] = {r: REGIONS[r] for r in idx["regions"]}
    idx["totals"] = {"blocks": len(blocks), "tiles": sum(b["tiles"] for b in blocks.values()),
                     "buildings": sum(b["buildings"] for b in blocks.values()), "bytes": sum(b["bytes"] for b in blocks.values())}
    os.makedirs(OUT, exist_ok=True)
    with open(p, "w") as f:
        json.dump(idx, f, indent=1)
    log("[index] %s" % idx["totals"])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("scan")
    a.add_argument("--pbf", default=os.path.join(ROOT, ".tools", "osm", "australia-latest.osm.pbf"))
    a.add_argument("--storage", default="flex_mem")
    b = sub.add_parser("build")
    b.add_argument("--regions", default="sydney,brisbane,mudgee")
    b.add_argument("--all", action="store_true")
    b.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 4) - 4))
    sub.add_parser("index")
    args = ap.parse_args()
    if args.cmd == "scan":
        scan(args)
    elif args.cmd == "build":
        build(args)
    else:
        _merge_index({}, [])


if __name__ == "__main__":
    main()
