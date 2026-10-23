# The streamed world: all of Australia (OpenStreetMap → Santa Sim)

`scenes/world/world.tscn` is one seamless map of Australia, like Minecraft or No Man's Sky: no loading
screens and no zones. Chunks build on worker threads and fade in and out around the sleigh as you fly.
Every real building sits at its real spot, rebuilt as one of our own stylised Santa-ready houses (the same
`scripts/town/house_gen.gd` as Paddington, at full quality up close). It's a summer Christmas with no snow.

Paddington is just one area inside it, at the same real coordinates. `scenes/town/town.tscn` (the
hand-tuned Paddington delivery town) is unchanged and still works exactly as before.

Map data © OpenStreetMap contributors, ODbL 1.0. Everything in `data/world/` is OSM-derived and stays ODbL
(see `data/towns/ATTRIBUTION.md`). The game shows the attribution on screen.

## 1. Build the data (offline, once)
You need Python 3.9+, `pip install osmium pillow` (pyosmium ships Windows wheels), and about 2 GB free.

```
# 1. Download the Geofabrik extract (~0.93 GB; gitignored)
curl -L -o .tools\osm\australia-latest.osm.pbf https://download.geofabrik.de/australia-oceania/australia-latest.osm.pbf

# 2. Scan: one pass over the whole country (~12 min, ~6 GB RAM). Writes .tools\osm\work\*.pkl (gitignored).
python tools\world\world_tiles.py scan

# 3a. Build some regions (blocks touching them): Sydney + Brisbane (incl. Paddington) + Mudgee, ~1 min
python tools\world\world_tiles.py build --regions sydney,brisbane,mudgee
# 3b. ...or the full country (all blocks, parallel, ~10-15 min on 16 cores)
python tools\world\world_tiles.py build --all
```
- Region names: `sydney, brisbane, mudgee, melbourne, perth, adelaide, hobart, darwin, canberra, australia`
  (bounding boxes at the top of `world_tiles.py`; add your own).
- Re-running `build` only rewrites the blocks it touches and merges them into `data/world/index.json`.
- To update the map, download a fresh `.pbf` and run `scan` again.
- `data/world/blocks/` is gitignored (it's large and regenerable). Only the tools and docs are in git.

## 2. Play it
- Open `scenes/world/world.tscn` and press F6, or run
  `.tools\godot\Godot_v4.7.2-stable_win64.exe --path . res://scenes/world/world.tscn`.
- You start on a launch tower over Paddington. The flight controls are the same as the town scene. Keys **1-5** warp to
  Paddington, Sydney CBD, Mudgee, Bondi and Brisbane CBD. A warp is just a teleport: the world streams in
  around you the same way it does when you fly there. `-- --start=<n>` picks the start spot.
- The HUD shows lat/lon, the region style (QLD / SOUTH / TROPIC), what's loaded and the FPS.

## 3. Data format
**Tile grid:** 100 tiles per degree of longitude × 111 per degree of latitude (about 0.8-1.1 km × 1.0 km), with
`ix = floor(lon*100)` and `iy = floor(lat*111)`. Tiles are grouped into 1° × 1° **blocks**, one file per block:
`data/world/blocks/<lat>_<lon>.pack` (for example `-28_152` holds Paddington). Inside a tile, coordinates are
decimetre ints around the tile's own centre (local equirectangular), so nothing is ever far from an origin.

`.pack` (little-endian): `"SSWP"`, version, bx, by, tiles/deg, ground cells, tile count, a zlib **overview** raster
(4 cells per tile, about 250 m, ground classes), then a tile table of `ix, iy, offset, zlen, len, buildings, flags`,
then one zlib blob per tile:
- the **ground** raster: 32 × 32 classes (about 31 m). The classes are land, residential, commercial, industrial,
  grass/park, pitch, wood, sand, water, ocean and farmland. Ocean is flood-filled from the OSM coastline (land is
  on the left of the way). Rivers 12 m or wider are drawn in.
- **buildings:** OSM id, kind (house/shed/shop/apartments/church/civic/other), roof hint (`roof:material`
  tile/metal, `roof:shape`), levels, height, oriented box (centre, size, angle), footprint area, front face and
  front direction toward the nearest named road, and the address. These use the same rules as `tools/osm/osm_import.py`.
- **roads:** type, width (from tags, or a default per type), bridge/named flags and the clipped centreline.
- **trees:** individually mapped `natural=tree` nodes.

`data/world/index.json` lists the blocks, regions, totals, source snapshot and attribution.

## 4. Streaming, LOD and the floating origin (`scripts/world/`)
| Ring (from the sleigh, plus 2.5 s of velocity look-ahead) | Unit | What |
|---|---|---|
| near, under 380 m | ~250 m cell | full `house_gen.gd` houses, eave lights, gum trees, **collision** (house trimesh in 64 m pieces, tree trunk and crown) |
| mid, under 2.5 km | cell | one vertex-coloured mesh per cell: walls, Santa-deck roofs, lit windows, using the **same colours** as the near houses (it replays house_gen's dice) |
| roads, under 2.7 km | tile | asphalt ribbons |
| ground, under 4.3 km | tile | 32 × 32 landuse/water raster |
| far, under 9 km | tile | impostors: glowing dots for windows, Christmas lights and streetlights, plus skyline boxes for towers (seen out to about 14 km) |
| block, under 95 km | 1° block | the 250 m overview ground under everything, plus an ocean sheet |

- **No hitches:** every mesh, texture and MultiMesh is built in `WorkerThreadPool` jobs (`world_builder.gd`). Near
  jobs run one at a time because house_gen shares a material cache; the rest run up to 6 in parallel. The main
  thread only attaches finished nodes (`apply_budget_ms` = 2 ms per frame) and creates collision shapes
  (`collision_budget_ms` = 1.5 ms per frame). Items unload past a slightly larger radius (hysteresis), so nothing flickers.
- **Smooth LOD:** dithered cross-fades using `visibility_range` with `FADE_SELF` (near→mid at 410 m, mid→far at about
  2.3 km). A mid cell only starts fading out once its near cell is attached, so there are never holes. Depth fog
  (0.7-11 km) hides the outer edge.
- **Floating origin:** `geo.gd` keeps the origin as double-precision lat/lon. When the sleigh is more than 1.5 km from it,
  `world.gd` moves the origin under the sleigh. Every loaded tile re-places itself from its own lat/lon, and the
  sleigh, reindeer and camera shift by the same offset. Positions never exceed about 1.5 km, so single-precision
  physics and rendering stay exact anywhere in Australia.
- **Regional styles** (`world_style.gd`, using only the existing house_gen styles):
  - QLD suburbs use exactly the Paddington rules: Queenslanders, cottages, fibro and some brick.
  - The tropical north is mostly elevated Queenslander and fibro under iron.
  - The south is mostly brick veneer under terracotta tile, plus cottages and fibro.
  - Remote areas with very few buildings around get low-set fibro and the odd Queenslander under iron.
  - OSM `roof:material` and `roof:shape=flat` override the dice.

## 5. Checks
- `--headless --path . res://scenes/world/world.tscn -- --worldcheck` prints PASS/FAIL lines and exits non-zero on a failure. It covers:
  - data loads
  - every Paddington building from the town scene is found in the world tiles, at the same spot (cm) and size, with the same house style
  - streaming settles at Paddington, and a ray down on house centres hits collision
  - a 13 km flight at 100 m/s, measuring main-thread streaming time per frame (p99 and worst) and counting rebases
  - floating-origin precision
  - warps to Sydney CBD and Mudgee, with collision checked there
- `-- --worldfps` (needs a window) flies three scripted legs (suburb low, city mid, city high) and prints FPS, 5%
  lows, worst frame, hitches over 16.7 ms and draw calls.
- `-- --worldshots=<dir>` saves `world_flyover`, `world_brisbane_cbd`, `world_sydney`, `world_bondi`,
  `world_region2` (Mudgee), `world_lod` and `world_street` jpgs.

## 6. Not yet
- Terrain heights: the ground is flat. Ocean comes from the coastline, but there are no hills yet.
- No delivery decks, chimneys or yard decorations in the streamed world yet. Those stay in the Paddington town scene for now.
- Blocks with no buildings, roads or coastline at all (deep desert) aren't written, so they show the ocean sheet.
