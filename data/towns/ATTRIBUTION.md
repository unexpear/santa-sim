# Map data attribution

The town files in this folder (`*.json`) are derived from **OpenStreetMap** data.

**© OpenStreetMap contributors.** The data is available under the
[Open Database License (ODbL) 1.0](https://opendatacommons.org/licenses/odbl/1-0/).
See https://www.openstreetmap.org/copyright.

- The derived town files are a "Derivative Database" under the ODbL. If we publish them
  (for example, shipped inside the game), they stay under the ODbL and must be offered on the same terms.
- The game itself (art, code and our invented houses) is a "Produced Work". It only needs the visible
  credit below, which the town scene shows on screen at all times:
  `Map data © OpenStreetMap contributors (ODbL)`.
- The credit also needs to go in the game's credits screen and the store page once those exist.
- Raw Overpass responses are cached in `tools/osm/cache/` and fall under the same licence.

| Town file | Area | Source | Fetched |
|---|---|---|---|
| `paddington_qld.json` | Paddington, Brisbane QLD (550 m square around -27.4598, 152.9985) | Overpass API (overpass-api.de) | 2026-10-20 |

The houses drawn in the game are **not** OSM data. They are our own procedural, Santa-ready houses,
placed on the real footprints (same position, orientation and size).
