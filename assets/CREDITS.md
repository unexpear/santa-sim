# Asset credits

## Models in `assets/models/`
| File | What it is | Author | Licence |
|---|---|---|---|
| `sleigh.glb` | Santa's sleigh: curved body with gold scrolls, curled runners, seat, lanterns, toy sack and presents | Made for this project (procedurally modelled by `tools/blender/build_models.py`) | Project-owned, no third-party content |
| `santa.glb` | Seated Santa: face, beard, floppy hat with pom-pom, suit, belt, mittens, reins | Made for this project (same script) | Project-owned, no third-party content |
| `reindeer.glb` | Reindeer with branching antlers, harness and bells. The legs are separate nodes so the game can animate a gallop | Made for this project (same script) | Project-owned, no third-party content |

Rebuild them with Blender 4.2 LTS:
`blender -b -P tools/blender/build_models.py -- assets/models [preview_dir]`

No downloaded models are used right now.

## Free models that were evaluated but not used (October 2026)
- "Santa" by Polygonal Mind on Poly Pizza (https://poly.pizza/m/KtbHdsr07s), CC0. A T-pose figure with stick-thin limbs. It can't sit in the sleigh without rigging work and doesn't match the chunky style.
- "Holiday Kit" by Kenney (https://kenney.nl/assets/holiday-kit), CC0. It has a reindeer and plain sleds, but no Santa or Santa sleigh. The reindeer is a very low-poly, single-piece static mesh with no separate legs to animate.
- "Basic Assets Christmas" by Tribus Games Indie on OpenGameArt (https://opengameart.org/content/basic-assets-christmas), CC0. Voxel style, which clashes with the smooth Hello Neighbor look.

If any of these get added later, list them in the table above with source, author and licence.
