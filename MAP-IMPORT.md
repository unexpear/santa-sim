# Real-map import (OpenStreetMap → Santa Sim town)

The game uses real geography with invented buildings. Streets, footprints, addresses, parks and water come
from OpenStreetMap. Every building is replaced by **our** stylised, Santa-ready house: same spot, same
orientation, sized to the footprint, with the front door facing the nearest street.

Map data © OpenStreetMap contributors (ODbL). See `data/towns/ATTRIBUTION.md`.

## 1. Import an area (offline tool)
`tools/osm/osm_import.py` uses only the Python standard library (Python 3.9+, nothing to install).
Run it from `D:\dev\santa-sim`:

```
python tools\osm\osm_import.py --town paddington_qld --display "Paddington, Brisbane QLD" --center=-27.4598,152.9985 --size 550
python tools\osm\osm_import.py --town mudgee --place "Mudgee, NSW" --size 500
python tools\osm\osm_import.py --town my_bbox --bbox=-27.462,152.996,-27.457,153.001
```
- `--center=lat,lon` plus `--size <m>` gives a square around a point. Use the `=` form, because of the minus sign.
- `--place "name"` geocodes once with Nominatim, then works the same as `--center`.
- `--bbox=south,west,north,east` takes degrees.
- Keep areas at or below about 1.5 km across. Around 500 m is a good test size.
- Output goes to `data/towns/<town>.json`. The raw Overpass response is cached in
  `tools/osm/cache/<town>_<hash>.overpass.json`, so re-runs are offline. Use `--refresh` to download again.
- The tool is polite: one request per import, a proper User-Agent, and back-off across three public
  Overpass mirrors. Overpass is often busy, so just re-run it if all three time out.

To check the result by eye (needs Pillow), run `python tools\osm\compare_topdown.py --town <town>` after
taking the screenshots below. It writes `screenshots/town_topdown_compare.jpg` with three panels: the real
map, our render, and the real footprints overlaid on our render.

## 2. Play it
- Open `scenes/town/town.tscn` in the editor and press F6 (Run Current Scene). The landing test is still the main scene.
- From the command line: `.tools\godot\Godot_v4.7.2-stable_win64.exe --path . scenes/town/town.tscn`
- To use another town, add `-- --town=res://data/towns/<town>.json`, or set `town_file` on the Town node.
- The controls are the same as the landing test: W/S, A/D, the arrow keys, Space, Shift, E to drop a present,
  V for the camera and R to restart. **C** shows/hides the collision shapes (colour per kind). The HUD shows the next delivery address, its distance and its compass direction.
- **Delivery houses** (10 by default, `delivery_count`) have a floating gold star and a lit landing deck:
  - **Green** is a Santa deck. It's wide and grippy, and its lights chase toward the deck.
  - **Green ridge** is a narrow deck on a steep 36° roof.
  - **Blue** is a rain-slick deck. It's wet and has almost no grip.
  - **Gold** is a bonus deck.
  - The eaves are always outlined in **red** (danger). The slopes count as roof but have no grip, so you slide off.
  - A scored landing on the deck ticks the house off.
- **Background houses** have warm or mixed string lights and full collision. Landing on one scores
  nothing ("Rooftop (not on tonight's list)").
- **Christmas yards** (`scripts/town/town_deco.gd`, export `decorations`, `--nodeco` to turn off): inflatable
  Santas and kangaroos (in Santa hats, with boxing gloves), glowing wire reindeer (some grazing), the odd
  nativity scene with a gold star, hedges netted in lights, jacarandas with lit trunks and canopy loops, gum trees
  spiralled with lights (every street gum near a delivery house) and wreaths on front doors. Delivery houses get
  5–7 pieces; about a third of background houses get one or two. All batched through `MeshBatch`; the bulbs join
  the town's bulb MultiMeshes. Each piece has one or two simple collision shapes.

### Collision
Everything the sleigh can hit is solid: every building (walls, roofs, verandahs, stumps, stairs, chimneys,
shop awnings), the filler houses, gum trees (trunk + canopy blob), streetlights, fences, hedges, letterboxes,
Hills Hoists, kerbs, the launch tower legs, the yard decorations, the hills and the CBD. The ground/roads
are the existing ground box. Reindeer have no collision; only the sleigh collides.
- Houses use their own (simplified) geometry: windows, trims, fascias and door details are skipped. Delivery
  houses keep their separate scored deck/slope/chimney bodies.
- Props use one simplified template per type, copied per instance.
- It's all merged into one double-sided trimesh per (kind, 96 m chunk): about 530 static bodies and 317k triangles,
  built in about 0.25 s. Physics cost didn't measurably change, so there's no streaming.
- The sleigh's own rules decide crash vs bump (fast wall hit = crash, gentle brush = bump). The town names what
  you hit: "CRASH! Smashed into a gum tree!". The sleigh already uses CCD, and nothing tunnels at 40 m/s.

Checks (they print results and then quit):
- `--headless ... scenes/town/town.tscn -- --townselftest` runs scripted landings: 4 decks, a slam, a roof slope and a background roof.
- `... scenes/town/town.tscn -- --townshots=D:/dev/santa-sim/screenshots` saves `town_topdown.png`, `town_street.png`, `town_fly.png` and `town_overview.png`.
- `... scenes/town/town.tscn -- --townfps` flies a scripted lap and prints the FPS and draw calls.
- `.tools\town_shots.ps1 fps` runs the shots and the FPS lap in one go.
- `--headless ... -- --towncollide` rams the sleigh into a house wall (25, 28 and 40 m/s, plus a 3 m/s brush), a gum
  tree (trunk and canopy), a streetlight and a picket fence (28 m/s and a 2.5 m/s brush). It checks crash vs bump and
  that nothing tunnels through.
- `--townphys` times physics while the sleigh skims the rooftops. `--nocollide` uses the old simple hulls, for comparisons.
- `--colshot=<file.png>` saves a view with the collision shapes on, and `--decoshot=<file.png>` saves a street view of the most
  decorated delivery house.
- `.tools\town_collision.ps1` runs FPS without/with collision, the collision checks and the debug shot.

## 3. Data format (`data/towns/<town>.json`, `"format": "santa-sim-town", "version": 1`)
Coordinates are **local metres** around the square's centre, as `x = east` and `y = north`. In Godot that's
`Vector3(x, 0, -y)`. The projection is local equirectangular, which is accurate to centimetres at this size,
and every town sits at the origin, so the standard single-precision build is fine.

| Key | What |
|---|---|
| `source`, `projection`, `extent` | bbox (S,W,N,E), centre lat/lon, fetch time, square min/max in metres |
| `roads[]` | car roads: `type` (residential, secondary, service...), `name`, `width` (from tags, or a default per type), `lanes`, `oneway`, `bridge`/`tunnel`, `sidewalk` (both/left/right/none/separate) + `sidewalk_inferred`, `pts` centreline |
| `junctions[]` | points where 3+ road ends meet (no centre lines drawn there) |
| `kerbs[]` | road-edge polylines, cut where they would cross another road |
| `footpaths[]` | **inferred** footpaths: 1.5 m wide, 1.6 m nature strip from the kerb, only where OSM has no mapped sidewalk within about 3 m |
| `paths[]` | mapped footways, sidewalks, paths and steps with a width |
| `buildings[]` | `id`, `kind` (house/shed/shop/apartments/church/civic/other), raw `building` tag, `addr`, `street`, `height`, `levels`, `roof_shape`, `area`, `center`, `obb` {c, size, angle}, `front` (unit vector toward the nearest named road, snapped to an OBB face), `front_face`, `road_dist`, `road_pt`, `road_width`, `poly` footprint (CCW) |
| `addresses[]` | address points (`num`, `street`). They're matched to footprints when the building itself has no address. |
| `parcels[]` | lot boundaries, when mapped (almost never in Australia) |
| `barriers[]` | mapped fences, walls and hedges |
| `landuse[]` | park/grass/pitch/wood/residential/commercial/parking/swimming_pool polygons, clipped to the square |
| `water[]`, `waterways[]` | water polygons, plus streams and rivers with a width |
| `trees[]` | individually mapped trees |
| `stats` | counts |

## 4. How the town scene builds it (`scripts/town/`)
- `town.gd` handles the scene root. It covers loading, the environment, ground and landuse, roads, buildings, props,
  the outskirts, the launch tower, the sleigh and reindeer (reused read-only), the HUD, the attribution label and the checks.
- `house_gen.gd` is the procedural house generator. It has a deterministic seed per building (OSM id plus `town_seed`), and the styles are:
  - Queenslander on stumps (verandah, battens, stairs, corrugated-iron hip roof)
  - worker's cottage (gable to the street)
  - brick veneer with a terracotta tile hip roof and a porch
  - fibro cottage with a corrugated-iron gable
  - two-storey modern
  - shops (false front, sign, glowing window, awning over the footpath)
  - flats, halls and sheds

  Every roof is built for Santa: a flat deck on top, string lights on the eaves and a chunky leaning brick chimney.
  Walls lean slightly, and the windows and shutters are crooked.
- `town_props.gd` builds the gum trees (3 variants), streetlights, picket and brick fences, hedges, letterboxes,
  Hills Hoists and low-poly bulbs.
- `mesh_batch.gd` merges everything into one mesh per (192 m chunk, material).

Front yards come from the data. There's a paver path from the door to the footpath and a driveway on the clearer
side. The front fence runs along the property line with gaps for the path and the driveway, and the letterbox
sits by the gate. Gum trees and Hills Hoists go out the back, there are street trees on the nature strips, and
a streetlight stands about every 44 m with a real lamp.

Past the imported square, the roads carry on, around 2,000 low-detail filler houses fill a 260 m ring, and hills
ring the horizon. For Brisbane that includes Mt Coot-tha's TV towers to the west and the lit CBD to the east-south-east.

Performance (RTX 3070 Ti laptop, 1600x900): about 156 FPS flying, about 165 at street level (likely capped by
the monitor), 1,470 draw calls. It builds in about 2 s.

## 5. Known gaps
- **Terrain is flat.** Paddington is very hilly, so houses that really sit on slopes (and real Queenslanders on
  tall back stumps) are all on one level. A DEM import, such as SRTM or Geoscience Australia 5 m, is the next step.
- **Footprints are fitted as one oriented box.** L-shaped and complex footprints get a rectangle (see the overlay),
  and semi-detached pairs become two houses.
- **No parcels in Australian OSM.** Fences, driveways and back yards are inferred from the house, the nearest road
  and clearance checks. Fences can overlap or have gaps where lots are odd shapes, corner lots only get a fence on one street,
  and some driveways go missing where houses sit close together.
- **Facing** uses the nearest *named* road. A few corner houses and battle-axe lots face the "wrong" street.
- **Mapped sidewalks** in OSM are drawn as they are. Inferred ones are only added where none are mapped, and
  footway crossings are drawn over the road like a painted crossing.
- **Untagged `building=yes`** is guessed by size: under 30 m² is a shed, up to 420 m² is a house, and bigger is "other".
  So a few garages or granny flats become small houses.
- **Background houses** have no interiors. Only delivery houses have scored decks,
  and no delivery house has the chimney entry or elf interior yet (that's still in the landing test).
- **No traffic or residents.** The filler houses outside the square are random, not real.
