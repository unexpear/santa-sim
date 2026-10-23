# Santa Sim: Landing Test (Godot 4.7 greybox)

First playable prototype. It only answers one question: **does sleigh flight and rooftop landing feel good?**
There's no globe, map data or menus yet. The chimney entry, furnished interiors, a playable elf and the prototype gadgets are in (see below). See `DESIGN.md` for the full game.

## Run it
- Editor: open `project.godot` with Godot 4.7.x (a portable copy lives in `.tools/godot/`, which git ignores), then press F5.
- Command line:
  `.tools\godot\Godot_v4.7.2-stable_win64.exe --path .`
- Self-test (headless, scripted landings, prints results and quits):
  `.tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --fixed-fps 60 -- --selftest`
- Screenshots (opens a window briefly, saves PNGs, quits):
  `.tools\godot\Godot_v4.7.2-stable_win64_console.exe --path . -- --screenshot=D:/dev/santa-sim/screenshots`

Physics engine: Jolt (`physics/3d/physics_engine = "Jolt Physics"`), with physics interpolation on.

## Controls
| Action | Keyboard | Gamepad |
|---|---|---|
| Reindeer pull forward / reverse | W / S | Left stick up / down |
| Turn (yaw) | A / D | Left stick left / right |
| Pitch nose down / up | Up / Down arrow | Right stick up / down |
| Lift | Space | Right trigger |
| Brake + hover (gentle sink, kills horizontal speed, airborne only) | Left Shift | Left trigger |
| Drop present (on the ground: set it down behind the sleigh) | E | A |
| Toggle chase / top-down landing camera | V | Y |
| Restart (resets counters too) | R | Start |
| Collision debug draw (shapes tinted by layer) | C on the sleigh, F9 anywhere (C is the tactical crouch as the elf) | - |
| Enter the chimney (landed on a roof near it) / climb out at the hearth | F | X |
| Fireplace Icer down a lit chimney (on the roof, hold) | hold F | hold X |
| **Elf:** sneak (move) | W A S D | Left stick |
| **Elf:** jump (one elf height) | Space | A |
| **Elf:** look | Mouse (click to capture, Esc to release) / arrow keys | Right stick |
| **Elf:** crawl (hold; 0.5 eh, fits under every furniture tier; fully under furniture = Hidden) | Ctrl (hold) | Left stick click |
| **Elf:** tactical crouch (toggle; 0.75 eh, crouch-walk with the dart pistol, fits under MID and HIGH furniture) | C | Right stick click |
| **Elf:** use the selected gadget (hold for the Icer) | Left mouse | Right trigger |
| **Elf:** open / close the door in reach | E | Y |
| **Elf:** select gadget 1-8 / next / previous | 1-8 / E (when no door is in reach) or wheel down / Q or wheel up | RB / LB |
| **Elf:** Glow-Gogs night vision | N | D-pad up |
| **Elf:** Dart Magnet (the dart under the crosshair) | G or right mouse | B |
| **Elf:** lean / peek round a corner (hold, while still) | Z / X | D-pad left / right |
| **Elf:** Crook-Line: fire at the green-reticle anchor (rappel if it's a ledge at your feet, else grapple) / let go | T or middle mouse | Left trigger |
| **Elf:** on a grapple: pump the swing / reel in / pay out | W A S D / hold Space / hold Ctrl | Left stick / A / L3 |
| **Elf:** rappelling: lower / climb / brake / kick-off hop / flip upside down to peek | S / W / let go / Space / Ctrl | Left stick / A / L3 |
| **Elf:** zipline: anchor A, anchor B, then ride from the top end (Space drops off) | B | D-pad down |
| **Elf:** reel a zipline back in (a line left up is evidence) | H | Back / View |
| **Elf:** climb a marked climbable (bookshelf, curtain, tree, fireplace front): grab / climb + shimmy / let go | Space next to it / W A S D (W at the top mantles) / Space or Ctrl | A / Left stick / A or L3 |

## What's in the scene
- A night sky, summer grass, a road, gum trees, and a gold-lit launch pad where the sleigh starts.
- **Flat pad house** (easy). Green lights.
- **Steep gable house.** Only the 3 m ridge pad (green lights) is safe. The 30° slopes (red eaves and gables) have almost no grip, so the sleigh slides off.
- **Rain-slick house.** A flat, wet roof with very low friction (blue lights). Kill your speed before touchdown or you skid off the far edge.
- The green and blue side strings chase from the +Z end toward -Z, which is the approach direction from the launch pad.
- Each house has a chimney. Flying into a chimney or wall fast is a crash.

## Art style (Hello Neighbor-inspired, at night)
- `shaders/toon.gdshader` handles all meshes. It gives banded diffuse with soft band edges, a warm toon rim light, an optional toon glint (wet roof and puddles), painterly colour patches (ground, roofs and road), and a visual-only wall warp (bend and bulge).
- `shaders/night_sky.gdshader` draws an amber horizon fading through purple to deep teal, with toon-edged drifting clouds, twinkling stars and a big moon. The moon matches the direction of the moonlight.
- `shaders/bulb.gdshader` draws unshaded, saturated bulbs that don't clip to white. The bulbs grow with camera distance so the light strings read from far away.
- Each house has bold walls, a contrasting trim colour and a roof colour, all set as exports in `main.tscn`. Walls are crooked and bulging, chimneys lean and belly slightly, windows are crooked and warm-lit with skewed shutters, and some houses have a bolt-on annex.
- **Collision is unchanged.** Walls, roof slabs, slopes and the ridge pad are still the same plain boxes. All the warping is visual only. The landing-house chimneys are real size (0.64 m square, about 1 m above the roofline) and their collision follows the brick stack and crown, open down the flue. The annexes also have collision.
- Look knobs in `main.gd` (`Look` group): `moon_light_energy`, `warm_fill_energy`, `ambient_energy`, `saturation`, `glow_intensity`, `tree_count`, `pine_count`. Per house (`Style` group): `wall_bend`, `wall_bulge`, `chimney_lean`, `chimney_bulge`, `window_crookedness_deg`, `light_energy`. The shaders also expose uniforms (bands, rim, sky colours, cloud coverage and so on).

## Character models
- `assets/models/sleigh.glb`, `santa.glb` and `reindeer.glb` are original models, generated by `tools/blender/build_models.py` (Blender 4.2 LTS, headless). They use metaballs for the bodies, bevelled curves for runners, scrolls, antlers and reins, and subdivision surfaces elsewhere.
- At runtime, `GB.toonify()` swaps every imported material for the toon shader in the same colour.
- The lead reindeer's `Nose` material is overridden with a glowing red version.
- Reindeer legs (`LegFL`, `LegFR`, `LegBL`, `LegBR`) pivot at the hip and are animated as a gallop in `reindeer_team.gd`.
- Credits and licences are in `assets/CREDITS.md`.

## Rules
- **Touchdown** is scored on the first contact after at least 0.35 s airborne. It uses vertical speed, horizontal speed, and tilt just before contact:
  - 3 stars: under 1.5 m/s vertical, under 1.5 m/s horizontal, and under 6° tilt
  - 2 stars: under 3.0 m/s, 3.5 m/s, and 14°
  - 1 star: anything else that doesn't crash
  - Crash: over 6 m/s vertical, over 9 m/s horizontal, or over 30° tilt. A fast wall hit or a flip also crashes.
- Touching the ground counts as "Landed in the yard" or "Slid off the roof!". Any crash resets you to the launch pad after 1.6 s.
- **Only the sleigh counts.** The reindeer team (4 pairs plus a red-nosed lead) is visual-only, with no physics bodies. The reindeer can hang past roof edges or over open air, and they never affect scoring.
- **Present:** one rides on the sleigh. Drop it from the air or set it down while landed. If it settles on a roof for 1.2 s, it's delivered. If it hits the ground, it smashes (broken counter goes up). Either way, a new present appears in the sleigh.

## Tuning knobs
Every knob is an `@export` variable, so you can tweak it in the Inspector after selecting the node in `main.tscn` or its scene:
- `scripts/sleigh.gd`
  - **Flight:** `thrust_accel`, `reverse_accel`, `lift_accel`, `flight_gravity_scale`, `yaw_torque`, `pitch_torque`, `upright_strength`, `air_brake`, `hover_sink_speed`, `hover_vertical_gain`, `max_speed`, `linear_drag`, `angular_drag`
  - **Landing:** `crash_vertical_speed`, `crash_horizontal_speed`, `crash_tilt_deg`, `three_star`, `two_star` (vertical, horizontal, tilt), `wall_crash_speed`, `flip_tilt_deg`, `min_air_time`, `reset_delay`
- `scripts/house.gd`: `roof_type`, size and colour, `pad_friction`, `steep_slope_friction`, `slick_friction`, `steep_angle_deg`, `ridge_pad_width`
- `scripts/reindeer_team.gd`: `pairs`, `pair_spacing`, `gap_to_sleigh`, `follow_sharpness`, `turn_sharpness`
- `scripts/present.gd`: `present_mass`, `present_friction`, `settle_speed`, `settle_time`
- `scripts/chase_camera.gd`: distances, heights, `sharpness`
- `scripts/light_string.gd`: bulb `spacing`, `bulb_radius`, `pulse_wavelength`

## Layout
```
project.godot
assets/   models/*.glb, CREDITS.md
tools/    blender/build_models.py
scenes/   main.tscn, sleigh.tscn, house.tscn, present.tscn
shaders/  toon.gdshader, night_sky.gdshader, bulb.gdshader
scripts/  main.gd (world, input, rules glue, selftest), sleigh.gd, reindeer_team.gd, house.gd,
          light_string.gd (MultiMesh bulbs + chase shader), present.gd, chase_camera.gd, hud.gd, greybox.gd
```

## Take-off / landing animation (visual only)
- `scripts/sleigh_visuals.gd` (the sleigh's `Visual` node) runs the visual state machine:
  parked > taking off > flying > landing approach > touchdown > settling. It only reads the sleigh
  (grounded, velocity, lift input, a read-only ray for height) and never writes physics.
  It drives the sleigh squash/stretch + tilt, swinging lanterns, bouncing sack, Santa lean/breathing,
  runner dust, skid dust and touchdown sparks.
- `scripts/reindeer_team.gd` follows that state: crouch, ground gallop, pair-by-pair leap (lead first),
  flying gallop, brace on approach, staggered skid/stumble touchdown (rear pair first), idle fidgets.
  Read-only foot rays let each reindeer stand on whatever is under it; past a roof edge it hovers
  and paddles. The lead's nose is a bigger pulsing bulb with a single forward red headlight
  (SpotLight3D on the head + faint additive cone, `shaders/beam.gdshader`); tunables under "Headlight".
- A reindeer runway extends the launch pad. It's solid for the sleigh and presents too (layers 1 and 2); resting on it is "No score here", like the pad.
- **Collision on everything** (`scripts/colliders.gd`, simple primitives on layer 1): the 17 background houses (walls, gable roof as a convex prism, chimney, porch roof), gum trees (trunk cylinder plus canopy spheres), horizon pines, streetlights (pole, arm, head), picket fences (one box per run), letterboxes, hedges (one sphere per blob), Hills Hoists (pole and arms), the pad's candy-cane posts, and the landing houses' porch roofs and front steps. Background roofs are landable but never score ("No score here"); only the three landing houses score. Flat slabs (paths, lawns, road) and the distant hills and skyline stay visual only. Reindeer still have no collision. About 340 static bodies; FPS is unchanged (see the scripted checks). Indoors, every furniture piece and prop is solid for the elf (TV, lamps, nightlights, cookies, beer and carrot, stockings, under-bed clutter), except flat rugs. The under-furniture gaps are kept.
- Collision debug: C (on the sleigh) or F9 toggles see-through tinted volumes of every collision shape: orange = sleigh world, green = reindeer-feet only, cyan = interior/elf, pink = residents, yellow = darts.
- All timings, squash amounts and stagger delays are exported in those two scripts.
- `--animcheck=<dir>` runs a scripted take-off + landing in a real window and saves stills plus a
  12 fps JPEG frame sequence into `<dir>/anim_frames`.

## Chimney entry and interiors
- Every landing house has a real-size brick chimney (`scripts/chimney_model.gd`, `shaders/chimney_brick.gdshader`): 0.64 m square (`chimney_outer`) with an open 250 x 250 mm clay flue liner (`flue_size` 0.25, the size a 900 x 750 mm open fire needs; see `CHIMNEY-RESEARCH.md`), about 1 m above the roofline (`chimney_above_roof`, rounded to whole brick courses). It stays straight through the roof, where lead flashing (an apron on the roof plus an upstand against the bricks, stepped along the slope on the gable) seals it, then leans and bellies slightly above the roof in the Hello Neighbor way (`chimney_lean` 0.045 m, `chimney_bulge` 3%). The bricks are drawn on UVs measured in metres, so every brick is the same real size (0.22 x 0.068 m, 13 mm joints) on every face with no stretching: running bond, sunken mortar, bevelled edges, three reds, a few chipped and burnt bricks, soot creeping down from the crown. The crown is two corbelled brick courses stepping out, then a concrete cap that falls slightly to its edges and is sooty round the hole. There is no hatch, lid or door: the top is just the crown and cap round the open, sooty flue (the wreath stays on the stack). Frost and icicles when the fire is iced, a faint warm glow when it's lit. Inside, the flue follows a real open-fireplace chimney from top to bottom (`house.gd` `_build_flue_shaft`, `shaders/flue_brick.gdshader`): a tight square clay liner in 0.6 m sections, a 30-degree offset where the stack sits off to the side of the fireplace, then the smoke chamber, eight corbelled brick courses widening from the liner down to the full width of the fireplace, with real-size bricks, dark recessed mortar, chipped and missing bricks, glossy creosote streaks and soot that is black at the top and warmer, firelit lower down. Behind the throat is the smoke shelf (a ledge crusted with soot and grit), and the throat itself is a narrow slot above the lintel closed by a cast-iron damper plate hinged at the front (open while the fire is lit). Cobwebs and drifting soot dust near the top. The fireplace below has a firebrick back that slopes forward, splayed sides, a lintel and breast, a projecting mantel and a hearth 300 mm deep. The fire (`house.gd` `_build_fire`, `shaders/fire_flame.gdshader`, `fire_embers.gdshader`, `heat_haze.gdshader`) is three barked logs with charred, glowing ends on iron fire dogs and a grate, a crackling ember bed, layered flame tongues that lean outward so they read from straight above as well as from the room, sparks, smoke drawn up the throat, a heat shimmer, and flickering warm light on the flue and the room. Iced, the logs frost over, the embers go cold and blue, ice crystals grow on the grate and cold mist rolls out. Collision matches the model: four brick walls in three lifts that follow the lean, plus the wider crown, open down the middle. Hitting a chimney fast still crashes. The cutscene cameras inside the flue are clamped to stay clear of the bricks.
- **Entry flow:** land on a roof within about 8.5 m of the chimney, and "Press F: enter chimney" appears. The elf hops onto the crown, kneels on the lip and peeks in with the goggles glowing (a soft green spot), hooks the Crook-Line (candy-cane hook) on the lip, abseils down the tight liner with kick-off hops (soot dust falling, rope taut above), drops into the smoke chamber as it widens, squeezes past the damper plate through the throat, drops into the firebox and peeks out past the grate in green mist, stockings above. You then play the elf in third person. Walk back to the hearth and press F to winch back up; the elf climbs out over the crown and hops back to the sleigh. The sleigh is parked (frozen, controls off) while the elf is inside.
- **Lit fireplaces** (the steep and rain-slick houses start lit) block the way in. Hold F on the roof to fire the Fireplace Icer down the flue first.
- **Interiors** are built inside the real house shells (no loading, no separate scene), so the lit rooms show through the windows from the street. Each house has its own layout: living room with fireplace, hall, kitchen, master bedroom and a kid's room. The rain-slick house has two storeys and a staircase. Interior walls, doors, rugs, wallpaper, skirting, curtains, an Aussie summer Christmas (tree, presents, stockings, beer and a carrot, cookies and milk, fans and air con), lamps, tree lights, nightlights and moonlight.
- Furniture is modelled in Blender (`tools/blender/build_models.py`, `assets/models/furniture.glb`) and gets box collision where the elf would bump into it. The elf (`assets/models/elf.glb`) follows the designer's reference (`art/reference/elf_stealth_reference.png`): tiny, 0.22 m standing (about ankle-to-shin on an adult), big ears, pointy nose, tactical outfit, floppy hat with a pom-pom, glowing green goggles, candy cane. Sneak-walk, idle and the crouch-crawl (hat squashed flat) are procedural (`scripts/elf.gd`).
- **The elf's hat** sits on top of the head: the brim rests just above the goggle strap, so the goggles and face are fully visible below it, and the ears come out under the brim. The floppy cone and pom-pom hang on their own pivot (`HatCone`), so the brim stays put while the cone bends. Under anything low the cone folds back and squashes just enough to stay under it (never through it) and springs back when there's room (`hat_min_fold` 0.2 = the most it squashes, `hat_fold_back_deg`, `hat_margin`, `hat_fold_speed`). A small collision sphere tracks the top of the hat and ears, so it can't be pushed through furniture, and the stance fit heights include the folded hat. The checks (`--intcheck`, `--elfshots`) fail if any elf mesh vertex ends up above a furniture underside, standing still or walking in and out.
- **Under the furniture (three height tiers):** couches, armchairs, beds, side tables, the coffee table, TV unit and wardrobe stand on legs, and each piece gets one of three gaps under its body, drawn from a shuffled bag (seeded per house, so it's repeatable and every house has all three): **LOW** 0.62 eh (0.136 m, crawl-only: squat bun feet), **MID** 0.85 eh (0.187 m, crouch-fit: turned legs), **HIGH** 1.15 eh (0.253 m, stand-under: tall tapered legs with brass caps). The legs are rebuilt to match the gap and the body (and whatever sits on it: the TV, lamps, nightlight, cookies, sleepers in bed) moves with it. The elf's three stances fit like this: crawl fits all three, tactical crouch fits MID and HIGH, standing fits HIGH only; you can't get taller until there's room. The fit is judged on the elf's full visual height with the hat folded as far as it goes (`elf.gd` `stand_fit_eh` 0.93, `crouch_fit_eh` 0.80, `crawl_fit_eh` 0.565, plus 1 cm clearance), not just the collision capsule. Walking towards something too low for the current stance, the elf drops to crouch or crawl by itself (`auto_stance`), waits for the body to get low before going under, and stands back up once there's room. The dining table and chairs keep their tall legs. Collision is thin leg boxes plus one raised body box whose underside is the gap. Kitchen counters, the fridge and bookshelves stay solid to the floor. Under the beds there's clutter (a shoebox, a lost sock, a toy car and ball) with no collision, so it never blocks the crawl.
- **Walls and doors:** every interior wall has box collision matching its visual slab. Partitions are solid across both rooms' slabs (0.16 m), and perimeter walls extend 0.25 m out into the house shell, so there are no thin skins. Every doorway has a real hinged door (`scripts/door.gd`): the collision swings with the slab, a closed door blocks, and an open doorway is passable. Press E within 5 elf heights (1.1 m) to open or close it. A door swings away from you unless that side is obstructed, it's hinged near the room corner so it folds back against the side wall, and it waits instead of shoving the elf through a wall. Some doors start shut, some ajar and some wide open (`interior.gd` `doors_closed_chance`, `doors_ajar_chance`, `door_ajar_angle`). The street door is locked: elves use the chimney. Each swing emits `creaked(position, radius)` (stealth hook; `creak_radius` 3.5 m); for now the gadgets treat it as noise for `creak_noise_time` seconds. The elf camera is a SpringArm3D with a sphere probe on the interior layer, so it pulls in at walls and doors.
- **Hiding:** fully under furniture in any stance that fits there (five upward probes from the top of the current capsule, at its centre and edge, all hit cover) = Hidden, under all three tiers. A small "◐ Hidden" icon shows at the top of the screen. Residents can't notice you and you make no noise.
- Interiors use their own physics layer (3) and render layer (2): interior lights only light interiors, and the outdoor fill/rim lights skip them.
- Tunables: `house.gd` "Chimney + interior" group (`interior_enabled`, `fireplace_lit`, `flue_size`, `chimney_outer`, `chimney_above_roof`, `chimney_smoke_amount`, `fire_light_energy`, `glass_tint`), `interior.gd` (`lamp_energy`, `tree_light_energy`, `nightlight_energy`, `ember_energy`, `dust_mote_amount`, `interior_light_shadows`), `elf.gd` (speeds, jump, step, noise, camera, sensitivity, `goggle_light_energy`, and the "Hat" group: hat fold, stance fit heights, `auto_stance`), `chimney_entry.gd` (`enter_radius`, Crook-Line length and speeds, cutscene framing, `creep_time`, `exit_confirm_window`). Everything sized by the elf is in elf heights: see the next section.

## Elf scale (everything in elf heights)
One shared constant, `scripts/elf_size.gd` `ELF_HEIGHT` = **0.22 m** (1 elf height, "eh"), drives everything sized by the elf. Each tunable below is exported in elf heights (`*_eh`) and converted with `ES.m(eh)`, so changing `ELF_HEIGHT` rescales the whole stealth game. House and furniture sizes stay real-world metres. Metres below are at `ELF_HEIGHT` = 0.22.

| Tunable (script) | Elf heights | Metres |
|---|---|---|
| Standing height (`elf_size.gd` `ELF_HEIGHT`) | 1 | 0.22 |
| Standing collision height (`STAND_CAPSULE_EH`; the hat tip is soft) | 0.92 | 0.202 |
| Tactical crouch collision height (`TAC_CROUCH_EH`) | 0.75 | 0.165 |
| Crawl collision height (`CROUCH_EH`) | 0.5 | 0.11 |
| Furniture gap LOW, crawl-only (`GAP_LOW_EH`) | 0.62 | 0.136 |
| Furniture gap MID, crouch-fit (`GAP_MID_EH`) | 0.85 | 0.187 |
| Furniture gap HIGH, stand-under (`GAP_HIGH_EH`) | 1.15 | 0.253 |
| Capsule radius (`RADIUS_EH`) | 0.23 | 0.05 |
| Walk speed (`elf.gd` `walk_speed_eh`) | 6.5 /s | 1.43 m/s |
| Tactical crouch-walk speed (`crouch_speed_eh`) | 4.2 /s | 0.92 m/s |
| Crawl speed (`sneak_speed_eh`) | 3.0 /s | 0.66 m/s |
| Acceleration (`accel_eh`) | 45 /s² | 9.9 m/s² |
| Jump height (`jump_height_eh`) | 1.0 | 0.22 |
| Step height / floor snap (`step_height_eh`) | 0.35 | 0.077 |
| Noise radius walking (`noise_radius_walk_eh`) | 12 | 2.64 |
| Noise radius crouch-walking (`noise_radius_crouch_eh`) | 7 | 1.54 |
| Noise radius crawling (`noise_radius_sneak_eh`; 0 when still or hidden) | 4 | 0.88 |
| Camera distance standing (`camera_distance_eh`) | 3.6 | 0.79 |
| Camera height standing (`camera_height_eh`) | 1.5 | 0.33 |
| Camera distance crouched (`crouch_camera_distance_eh`) | 2.8 | 0.62 |
| Camera height crouched (`crouch_camera_height_eh`) | 0.42 | 0.092 |
| Camera distance tactical crouch (`tac_camera_distance_eh`) | 3.2 | 0.70 |
| Camera height tactical crouch (`tac_camera_height_eh`) | 0.75 | 0.165 |
| Camera collision probe (`camera_probe_eh`) | 0.1 | 0.022 |
| Glow-Gogs light range (`goggle_light_range_eh`) | 6 | 1.32 |
| Resident notice distance (`resident.gd` `notice_radius_eh`) | 10 | 2.2 |
| Dart range (`gadgets.gd` `dart_range_eh`) | 40 | 8.8 |
| Dart throw speed (`dart_speed_eh`) | 60 /s | 13.2 m/s |
| Dart gravity feel (`dart_gravity_eh`) | 4 /s² | 0.88 m/s² |
| Dart skid after landing (`dart_skid_eh`) | 1.5 | 0.33 |
| Dart length (`dart_length_eh`) | 0.45 | 0.099 |
| Dart hit / magnet target radius (`dart_hit_radius_eh`) | 0.4 | 0.088 |
| Dart mass (`dart_mass_g`) | - | 3 g |
| Dart pickup radius (`pickup_radius_eh`) | 1.6 | 0.35 |
| Muzzle height (`muzzle_height_eh`) | 0.6 | 0.13 |
| Crosshair targeting cone (`aim_cone_deg`, angular so scale-free) | - | 2.3° |
| **Dart Magnet range** (`magnet_range_eh`, line of sight, aimed dart only) | **20** | **4.40** |
| Magnet tug (`magnet_tug_mn`): a = F/m = 75 mN / 3 g | - | 25 m/s² |
| Magnet top pull speed (`magnet_max_speed_eh`) | 45 /s | 9.9 m/s |
| Magnet catch / snap distance (`magnet_catch_eh`) | 0.8 | 0.18 |
| Magnet first-tug lift hop (`magnet_lift_eh`) | 0.8 | 0.18 |
| Snore-o-Meter ping radius (`snore_radius_eh`) | 45 | 9.9 |
| Tuck Trolley load radius (`load_radius_eh`) | 7 | 1.54 |
| Tuck Trolley tuck-in radius (`tuck_radius_eh`) | 8 | 1.76 |
| Trolley deck height (`trolley_deck_eh`) | 0.4 | 0.088 |
| Trolley handle / tow-bar height (`trolley_handle_eh`) | 0.55 | 0.12 |
| Trolley wheel radius (`trolley_wheel_eh`) | 0.18 | 0.04 |
| Trolley gap behind the elf (`trolley_gap_eh`) | 1.2 | 0.26 |
| Trolley speed while loaded (`trolley_speed_mult`) | x0.7 | 1.0 m/s |
| Fit-Ghost range (`ghost_range_eh`) | 12 | 2.64 |
| Fit-Ghost and present scale (`present_scale`; presents are real gifts, 1-2 eh) | x1 | 0.23-0.46 |
| Stocking range (`stocking_range_eh`) | 10 | 2.2 |
| The Ledger door range (`ledger_range_eh`) | 14 | 3.08 |
| Hearth (exit / Crook-Line) radius (`hearth_radius_eh`) | 4.5 | 0.99 |
| Door reach for E (`door_reach_eh`) | 5 | 1.1 |
| Fireplace Icer range indoors (`icer_range_eh`) | 16 | 3.52 |
| Fire Launcher relight range (`relight_range_eh`) | 16 | 3.52 |
| Fire Launcher pipe thaw range (`thaw_range_eh`) | 14 | 3.08 |
| Rim hop arc (`chimney_entry.gd` `hop_arc_eh`) | 4 | 0.88 |
| Crook-Line length (`crook_line_length_eh`) | 45 | 9.9 |
| Abseil speed (`abseil_speed_eh`) | 9 /s | 1.98 m/s |
| Winch speed (`winch_speed_eh`) | 14 /s | 3.08 m/s |
| Line grip offset (`line_grip_eh`) | 0.8 | 0.18 |
| Chimney cutscene rim camera distance / height (`rim_cam_distance_eh`, `rim_cam_height_eh`) | 9 / 5 | 1.98 / 1.1 |
| Fireplace cutscene camera distance / height (`hearth_cam_distance_eh`, `hearth_cam_height_eh`) | 4.5 / 1.8 | 0.99 / 0.4 |

Not elf-scaled on purpose: house, furniture and present sizes, the roof `enter_radius` (8.5 m, sleigh scale) and the burst-pipe `burst_wake_radius` (9 m, house scale).

## Crook-Line rope tech and climbing (`scripts/rope_tech.gd`)
Spec-ops rope work scaled to a 0.22 m elf. A wrist launcher on the left forearm (dark green and black, candy-cane red band) fires a thin black cable with a small three-prong claw hook ("thwip-clack", then a reel whirr; both synthesised at runtime). Nothing flips: the elf only yaws, and the swing is damped and weighty.

- **Reticle:** the crosshair turns green on a valid anchor within range with a clear line from the launcher (⊕ = a ledge you can rappel from). Anchors: light fittings (a pendant in every room), curtain rods, the banister and the upstairs stair rail, the Christmas tree, bookshelf tops and the mantel. Amber = a zipline anchor A waiting for its B.
- **Grapple swing:** fire at a light fitting, rod, banister or branch. Space reels in, Ctrl pays out, WASD pumps the swing, T lets go and you drop quietly. Reel right up to a ledge anchor and you haul yourself over it.
- **Rappel:** fire at a ledge anchor at your feet (bookshelf top, mantel, stair rail). The elf steps back over the edge, feet on the wall. S lowers (the braking hand lets rope run), W climbs, release = brake and hang, Space kicks off the wall, Ctrl flips upside down to peek. It unclips at the floor; climb back to the top and it mantles over. The chimney abseil uses the same Crook-Line.
- **Zipline:** B fixes anchor A, B again fixes anchor B. The line must run downhill (slope 0.06-1.2), be longer than 4 eh and be clear. B near the top end clips the hand trolley on and slides you down (gravity, rolling drag, top speed); your feet skim anything in the way and you unclip at the far end (Space drops off early). H reels a line back in. A zipline left up is evidence at the exit ("1 zipline left up!", headline "TINY ZIPLINE FOUND STRUNG ACROSS LOUNGE ROOM").
- **Climbing:** marked climbables are bookshelves, curtains, the Christmas tree and the brick fireplace front. Space next to one (facing it) grabs on; WASD climbs and shimmies. Grip runs down while you hang (7 s of climbing, slower when still) and refills on the ground; at zero you fall. W at the top mantles onto bookshelves and the mantel. Space or Ctrl lets go. The elf only plays inside the houses for now, so the outdoor climbables in the spec (drainpipes, trellis, tree trunks, roof edges) aren't reachable yet.
- **Stances:** stand (0.92 eh capsule), tactical crouch (C toggle, 0.75 eh, crouch-walk with the dart pistol up) and crawl (hold Ctrl, 0.5 eh, unchanged). Hidden still works in any stance that fits under furniture. **Lean / peek:** hold Z / X while still to slide the camera 0.6 eh round a corner (it won't go through the wall) with a 22° body tilt.

| Stance / state | Height | Speed | Noise radius | Notice rate |
|---|---|---|---|---|
| Stand | 0.92 eh (0.20 m) | 6.5 eh/s (1.43 m/s) | 12 eh (2.64 m) | x1.0 |
| Tactical crouch | 0.75 eh (0.165 m) | 4.2 eh/s (0.92 m/s) | 7 eh (1.54 m) | x0.65 |
| Crawl | 0.5 eh (0.11 m) | 3.0 eh/s (0.66 m/s) | 4 eh (0.88 m) | x0.5 |
| Climbing | - | 2.5 eh/s up, 2.0 sideways | 3 eh (0.66 m) | x1.15 |
| Grapple / rappel | - | reel 6 eh/s, lower 5 eh/s | 2 eh (0.44 m) | x1.15 |
| Zipline | - | up to 14 eh/s (3.08 m/s) | 5 eh (1.1 m) | x1.15 |

| Rope tunable (`rope_tech.gd`) | Elf heights | Metres |
|---|---|---|
| Grapple / reticle range (`grapple_range_eh`) | 18 | 3.96 |
| Rappel: ledge anchor within (`rappel_reach_eh`) | 3 | 0.66 |
| Zipline anchor shot (`zip_range_eh`) | 30 | 6.6 |
| Zipline clip-on reach (`zip_mount_eh`) | 3 | 0.66 |
| Zipline reel-in reach (`retrieve_reach_eh`) | 5 | 1.1 |
| Reel in / pay out (`reel_speed_eh`) | 6 /s | 1.32 m/s |
| Rappel lower / climb (`rappel_speed_eh`, `rappel_climb_eh`) | 5 / 2 /s | 1.1 / 0.44 m/s |
| Kick-off hop (`kick_out_eh`) | 1.0 | 0.22 |
| Shortest cable (`min_rope_eh`) | 1.0 | 0.22 |
| Climb / shimmy (`climb_speed_eh`, `shimmy_speed_eh`) | 2.5 / 2.0 /s | 0.55 / 0.44 m/s |
| Grab reach (`climb_reach_eh`) | 1.2 | 0.26 |
| Lean camera slide (`elf.gd` `lean_eh`) | 0.6 | 0.13 |

Also exported: `swing_pump`, `swing_damp`, `zip_friction`, `zip_min_slope`, `zip_max_slope`, `stamina_max`, `stamina_hold_drain`, `stamina_regen`, the noise radii and `rope_visibility`.

## Prototype gadgets (first playable pass)
The hotbar sits at the bottom of the screen while you're the elf. Residents are placeholder sleepers in their beds, and there's no stealth AI yet: awareness just rises when you're close and their sleep is light.

| # | Gadget | What it does |
|---|---|---|
| N | Glow-Gogs | Night vision: green tint and grain, and sleepers, darts and interactables glow. Residents notice you 1.25x faster (`goggles_notice_mult`). |
| - | Crook-Line | The candy-cane grapple for the abseil down the chimney and the winch back up, plus the wrist launcher for grapple swings, rappels and ziplines indoors (see the Crook-Line section). |
| 1 | Snooze Darts | A small, fast dart on a slight arc (aim-compensated, so it lands on the crosshair). It drops off a resident, skids along the floor, or sticks in a wall. 10 for the whole run, never regenerating. Walk over a dart to pick it up (crawl under furniture for one that skidded there). |
| G | Dart Magnet | Pulls back only the dart under the crosshair (line of sight, within 20 elf heights = 4.4 m). It's highlighted, with a "G: Dart Magnet (x m = y elf heights)" prompt. The dart hops up, then accelerates at F/m (75 mN on a 3 g dart) to a top speed and is caught 0.18 m from the elf. One at a time. |
| 2 | Snore-o-Meter | Ping (cooldown) shows each resident's sleep depth. Sleep gets lighter through the night (`sleep_depth_curve`). |
| 3 | Tuck Trolley | A tiny elf can't push a full-size adult, so it's a motorised dolly: a 1.9 m low deck on six small wheels with a red motor box and a blinking light, towed behind the elf on a bar. Load a darted resident and tow them back to bed (slower while loaded). |
| 4 | Fit-Ghost | Hologram of the next present under the tree. Green fits, red would knock a bauble off. |
| 5 | Puff-Possum | Puffs a stocking open, then click again to fill it. |
| 6 | The Ledger | Scan a kid's bedroom door: Naughty or Nice. |
| 7 | Fireplace Icer | Hold to freeze a lit fire out (from the roof or at the fireplace). Overuse fills the freeze meter: pipes frost, crack, then burst. |
| 8 | Fire Launcher | Relight a frozen-out fire before you leave, or thaw a cracked pipe before it bursts. |

- **Evidence at exit:** darts left in the house, a fire left out, a burst (or cracked) pipe, a resident not back in bed, or a zipline left up. Pressing F at the hearth first shows a warning (for example "2 darts left in house!"). Pressing F again climbs out anyway. The exit never locks. Evidence is logged for the newspaper (`[evidence]` lines with headlines).
- Tunables are in `scripts/gadgets.gd` (dart supply/range/speed, magnet range, snore cooldown and night curve, trolley speed, Icer rate/decay, `fire_freeze_at`, `pipe_frost_start`, `pipe_crack_at`, `crack_burst_delay`, `pipe_burst_at`, burst wake radius, puddle size and slipperiness).

## Fog and particles
- `scripts/atmosphere.gd`: low volumetric ground mist (fog volumes kept under about 1.4 m, cleared inside the landing houses) plus drifting painterly mist sprites, distance height fog, haze halos on outdoor lamps (`light_haze`), thin wisps over the landing chimneys, chimney smoke from the background houses, summer embers and pollen motes, moths at the streetlights, and glitter trails off the sleigh runners and reindeer hooves in flight. All of it is exported (`ground_mist_density`, `ground_mist_height`, `height_fog_density`, `ember_amount`, `pollen_amount`, `moths_per_light`, `bg_chimney_smoke`, `sleigh_trails` ...).
- `scripts/fx.gd`: GPUParticles3D presets with procedurally painted soft billboard sprites (smoke, soot, green mist, glitter, zzz, dust motes, frost, steam, embers, flames, water spray). Landing dust from the runners and hooves now uses soft sprite smoke instead of spheres. Fireflies are brighter (`suburb.gd` `firefly_glow`).
- Indoors: dust motes in every room, green mist from the fireplace when the elf comes out, glitter when a present is placed or a stocking is filled, a "zzz" puff on a dart hit, and the Glow-Gogs grain (`shaders/nightvision.gdshader`).

## Scripted checks
- `-- --intcheck=<dir>`: lands on each landing house, uses the roof Icer where the fire is lit, enters the chimney, walks the elf through every room (A* around furniture), exits, and saves stills (`int_*`). It also prints interior FPS. Per house it checks every furniture tier's stance fit, parks the elf under a LOW, MID and HIGH piece, and walks it in and out under each tier from standing; it fails if any elf mesh vertex ends up above the underside.
  It also runs the hide check: in every house the crawling elf goes fully under the couch and both beds, must be flagged Hidden (and unable to stand unless the piece is HIGH), and residents' awareness must not rise. Then the tier check: for every tiered piece the crawl capsule must fit under it, the crouch capsule only under MID and HIGH, the standing capsule only under HIGH; each house must have all three tiers; and the elf is put under one piece of each tier in the stance that fits (crawl/LOW, crouch/MID, stand/HIGH) and must be Hidden and unable to get taller. Stills: `elf_scale`, `elf_undercouch`, `elf_underbed`. `--furntiers=<dir>` saves `furn_tiers` (the three tiers side by side with an elf under each).
- `-- --wallcheck=<dir>` (fast: add `--headless --fixed-fps 60`): in all three houses the elf runs at 2x walk speed straight into every wall segment (furniture-free spots) and both sides of every closed door. It must never end up on the other side, and the camera boom pointed into each wall must stay in the room. Each door must also open with E and be walked through. The intcheck runs the same check.
- `-- --chimshots=<dir>`: lands on the flat house and captures the chimney (`chim_exterior`, `chim_exterior_wide`, `chim_exterior_lit`, `chim_exterior_iced`) and every entry beat (`chim_peek`, `chim_hook`, `chim_descent`, `chim_chamber`, `chim_damper`, `chim_emerge`, `chim_winch`, `chim_climbout`), and records the entry frames into `chimvid/` for the video.
- `-- --elfshots=<dir>`: lands on the flat house, enters, and saves the elf front and side at the hearth (`elf_fix_front`, `elf_fix_side`). It then finds the TV unit, walks the elf in under it and back out (auto stance, folding hat), stops underneath and saves the elf camera view (`elf_under_tv`) and a side view (`elf_under_tv_side`). It prints the stance, hat fold and how far the highest elf vertex is below the unit, and fails on any poke-through over 1 mm.
- `-- --chimview=<dir>`: lands on the flat and the steep house and saves the chimney as the player sees it: from the sleigh chase camera in both modes (`chimview_*_chase`, `chimview_*_top`), close up and from above the crown (`chimview_*_close`, `chimview_*_crown`) and side-on against the roof (`chimview_*_side`).
- `-- --ropecheck=<dir>` (runs headless too): in the flat house the elf climbs the living-room bookshelf and mantles on top, rappels back down (kick-off hop, upside-down peek, unclips at the floor), grapples the light fitting, reels up and pumps a swing, lets go and lands, rigs a zipline from the bookshelf top across the room, rides it to the far anchor, checks it counts as evidence, reels it in, then prints the stance heights / noise / notice rates and the ranges. Stills: `climb`, `rope_rappel`, `rope_rappel_inverted`, `rope_grapple`, `rope_zipline_rigged`, `rope_zipline`, `stance_compare`; frames in `ropevid/`.
- `-- --gadgetcheck=<dir>`: exercises every gadget in the lit-fireplace house, including burst pipes and the evidence warning (`gadget_*` stills). The magnet range test puts darts at 19.5 and 20.5 elf heights in clear line of sight: the first must be caught, the second refused.
- `-- --collisionshot=<dir>`: the street with the collision debug draw on (`landing_collision_debug`), plus FPS with it off and on.
- `-- --fxshots=<dir>`: fog and particle stills (`fx_*`) plus FPS.

## License
- **Code and original assets: CC0 1.0 Universal (public domain).** See `LICENSE`. This covers the scripts, scenes, shaders,
  tools and the project-made models in `assets/models/` (see `assets/CREDITS.md`). Use them for anything, no credit needed.
- **OpenStreetMap-derived data is NOT CC0.** The town files in `data/towns/*` and the raw Overpass responses in
  `tools/osm/cache/` stay under the [Open Database License (ODbL) 1.0](https://opendatacommons.org/licenses/odbl/1-0/),
  Map data © OpenStreetMap contributors. Details and the required attribution are in `data/towns/ATTRIBUTION.md`.
  The streamed Australia world in `data/world/` (see `WORLD-STREAMING.md`) is under the same ODbL terms.
- Third-party style reference images (Hello Neighbor key art, the Prep & Landing elf still) are kept locally in
  `art/reference/` but are not in the repo, because they aren't ours to release.
