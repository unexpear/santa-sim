# Santa Sim: Design Notes (v0.1, Oct 20 2026)

<!-- Restored Oct 20 2026 (evening) after a doc-patch script truncated this file at 5:39 PM.
     Sections marked "reconstructed" were rebuilt from the decisions recorded in the Oct 20 chat with the designer;
     their original wording could not be recovered. Unmarked text is the original wording.
     The truncated stub is kept at .tools/backups/DESIGN.stub-2026-10-20.md. -->

## Pitch
<!-- reconstructed -->
A 3D Santa game on a real globe. You plan a route over a real town built from map data, fly the sleigh, land on rooftops built for Santa, and send in the elves to deliver. The art is chunky and warped, in a Hello Neighbor style.
- Working title only: "Santa Simulator" is already taken on Steam, so the game needs a new title.

## Direction (decided)
<!-- reconstructed -->
- **3D**, with a **real globe and real geo data**.
- **Hello Neighbor-style art:** chunky, warped, saturated, cartoony houses.
- Photoreal map tiles would clash with that look, so they're out. Real streets and building footprints come from OpenStreetMap, and the houses on top are stylized and generated.

## Pillars
<!-- reconstructed -->
- **Real places, cartoon world:** real coastlines and street layouts, with stylized houses on top.
- **The landing is the skill:** physics rooftop landings where coming in too hard means sliding off.
- **Route vs. landing tension:** a short route can force harder landings, and an easy-landing route costs time.
- **Every landing pays off:** a stealth elf mission inside every house.

## Core loop
<!-- reconstructed -->
1. **Plan.** Look over a top-down town map with a night timer and draw a route through the houses on your list.
2. **Launch.** Fling the sleigh off the North Pole ramp, Angry Birds style, with angle and power.
3. **Fly.** Steer between stops while managing reindeer stamina and dodging wind, chimney smoke and power lines.
4. **Land.** Touch down on rooftops built for landing.
5. **Deliver.** Drop the presents, then score on speed, landing cleanliness and route quality.
- The interesting tension: a short route can force harder landings, while an easy-landing route costs you time.

## Roof types (first pass)
<!-- reconstructed -->
- **Flat garage roofs:** the easy pads.
- **Pitched roofs:** need a slow, careful approach.
- **Tiny chimney pads:** hard to hit, worth bonus points.
- **Icy / slick roofs:** low grip, so you have to kill your speed (in Australia these become rain-slick roofs).
- Coming in too hard on any roof means sliding off.

## How real geo data fits the stylized art
<!-- reconstructed -->
- Don't use photoreal map tiles: they clash with the Hello Neighbor look.
- Pull real streets and building footprints from OpenStreetMap.
- Generate warped, cartoony houses from those footprints, and hand-tune the roofs you actually land on.
- The globe itself is used for route planning and the zoom-in from space.
- Plan: an offline OSM import tool exports per-town data, Godot generates the stylized houses, and each town is built at the origin so the standard single-precision build is enough (see `ENGINE-CHECK.md`). OSM data is ODbL, so the game needs attribution.

## Competition (from research)
<!-- reconstructed -->
- Nobody else mixes route planning with physics rooftop landings. That's the hook.
- "Santa Simulator" is already a Steam title, so this game needs another name.

## Open questions
<!-- reconstructed -->
- Title ("Santa Simulator" is taken on Steam).
- Engine (see "Engine" below; resolved later as Godot 4.7).
- Which real town to use first (now: which Australian town).

## Next steps
<!-- reconstructed -->
1. A rough greybox with one sleigh and three roof types, to prove the landing feels good before touching any geo data.
2. Pick the engine.

## Christmas lights as landing language (added Oct 20)
<!-- reconstructed -->
Christmas lights outline the roofs and decorate them, and they double as runway lights for landing:
- **Green** = safe pads.
- **Blue** = slick / icy (rain-slick in Australia).
- **Red** = steep or dangerous edges.
- **Gold** = bonus (chimneys / bonus pads).
- The lights chase toward the best way in.
- Roofs are designed for Santa and for landing, not copied from real buildings (see "Setting: alternate history").

## Two-phase loop: sleigh then elves (added Oct 20)
<!-- reconstructed -->
Every house has two phases:
1. **Sleigh:** Santa lands on the roof.
2. **Elves:** a short Hello Neighbor-style indoor stealth mission. The elves place presents, fill stockings, check the list, eat the cookies and more, while sneaking past sleepers, pets, and kids peeking from the stairs.
- The halves are tied together: a cleaner landing gets the elves a better way in (chimney, window or back door) and more time.
- Getting spotted originally cost stars instead of ending the run. That rule was replaced by Stingy Jack's curse (see below).

## Updated next steps
<!-- reconstructed -->
1. Pick the engine (stealth indoors plus a 3D globe outside rules out anything too light).
2. Greybox the landing with one sleigh and light-outlined roofs (flat, steep, icy).
3. Then prototype the indoor elf phase.

## Elf tools: sleep darts and tucking back into bed (added Oct 20)
<!-- reconstructed -->
- Elves carry **sleep darts** for residents who stir.
- A darted resident has to be **carried back to bed** and tucked in (like body hiding in stealth games).
- **HARD RULE: DON'T FORGET THE DARTS.** Leaving a dart behind gets you exposed as "evil burglars who drug people". It's a heavy penalty or fails the house outright, and it makes the newspaper.
- **Residents get more active as the night progresses**, so later houses are harder.
- Current dart supply and magnet rules are under "Prototype gadgets" (10 per run, no regeneration, the magnet grabs only the dart you're looking at within 20 elf-heights, and the exit never locks).

## Sleigh packing (added Oct 20)
<!-- reconstructed -->
- At the start of the night you pack the sleigh based on your route.
- The sleigh is a **stack: you can only take the top present** at a time, so pack it in reverse route order.
- Pack it wrong enough and you have to unpack the sleigh on someone's roof to dig down.
- Presents that fall off **break and are lost**, which costs time and grade. Digging down on an icy (or rain-slick) roof is where presents slide off.

## Globe build plan (added Oct 20)
<!-- reconstructed -->
- Build the globe **continent by continent**, not all at once.
- The globe is the planning screen and the zoom-in from space, and each town is its own level.
- First continent: Australia (see below).

## Engine (in progress)
<!-- reconstructed -->
- Requirement: the engine has to fully support the game (globe and geo data, many night lights, flight and landing physics, presents sliding off roofs, indoor stealth AI, carrying residents).
- The designer's engines and project bots were all checked (Forge Engine, f4, DnD Game Engine, Bio-mec-an, mmath, Canvas Fogworks). None can run this game today, and all six bots recommend Godot. Details in `ENGINE-CHECK.md`.
- **The designer picked Godot 4.7** (Oct 20). Godot 4.7.2 portable is at `D:\dev\ofa\.tools\godot\` (don't modify the ofa folder; the project uses its own copy in `.tools\godot\`).

## Continent 1: Australia (decided Oct 20)
<!-- reconstructed -->
- Australia is the first continent. It's one of the first places to hit midnight on Christmas Eve, so the campaign starts where Santa's night starts.
- **Summer Christmas:** no snow. Rain-slick roofs instead of icy ones (blue lights = slick), and noisy tin roofs that can wake people up.
- Houses: Queenslanders on stilts, big outback homesteads. Reindeer tire faster in the heat.
- Indoors: ceiling fans cover the elves' noise, people sleep out on verandahs, plus backyard dogs and possums in the roof.
- Level ideas: a coastal tutorial town, Sydney suburbs, city apartments, an outback station.
- Open: which real town is level one.

## Setting: alternate history (decided Oct 20)
<!-- reconstructed -->
- In this world Santa is real, and every home has been built around his visit for generations.
- So houses don't have to be culturally or structurally accurate to the real buildings.
- Real coastlines and street layouts (OSM) stay. Everything above the footprint is ours: roofs designed and decorated for Santa, with landing pads, light-lined approach strips, sleigh hitching posts and chimney hatches.
- Australian twists, like shade sails over the pads.
- Lore ideas: a Santa building code with roof ratings, older houses with outdated pads that are harder to land on, rich families with over-the-top runways.
- The dart rule still fits: people are happy to have Santa visit, but they'd be scandalized to find out his elves drugged them.

## Getting seen: Stingy Jack's curse (decided Oct 20)
<!-- reconstructed -->
- If you're seen, you get **robbed of 10x the gifts** you were meant to leave at that house.
- You're also hit by a Halloween curse from **Stingy Jack**, for "copying his style with all the candy": **-5% speed**.
- **Stacking:** each sighting adds another -5%, **capped at -30%**.
- **Duration:** the curse lasts **3 houses from your most recent sighting**. A new sighting resets it to 3 houses; houses never stack.
- **Robbed empty:** if the sleigh holds fewer than 10x, they take everything left and **the run ends early**.
- This replaces the old "getting spotted costs stars" rule. Getting seen early hurts most, because the lost gifts wreck later deliveries, which ties stealth back to packing.
- Look idea: a cursed sleigh gets a jack-o'-lantern glow and an orange trail.

## End-of-run newspaper (decided Oct 20)
<!-- reconstructed -->
- **Every run ends with a newspaper front page** (decided), not only runs that end early.
- It tells the night in story form, built from what actually happened: which towns or houses you skipped, how many times the elves were seen, broken presents, and the curse.
- The designer's examples: "SANTA SKIPPED ..." and "DOES THIS MEAN WE'RE ALL ON THE NAUGHTY LIST?"
- A forgotten dart gets its own headline, e.g. "EVIL BURGLAR ELVES DRUG LOCAL FAMILY".
- A good night gets a good front page, e.g. "SANTA NAILS ROOFTOP LANDING ON MAIN ST", with a photo of your best landing. It doubles as a shareable highlight reel.
- The first chapter uses Australian papers.

## Newspaper style + headline bank (Oct 20)
<!-- reconstructed -->
<!-- The POINT OF VIEW bullet below is the original text, recovered verbatim. -->
- Like a real newspaper: masthead, a Christmas Day date, a big headline, a photo of your best or worst landing, story columns and resident quotes.
- Headlines are written for the designer (he asked for them). The game picks a headline based on what happened and fills in the real town and street names.
- Headline bank:
  - **Great night:** "NOT A CREATURE WAS STIRRING: Elves Go Unseen All Night"
  - **Messy night:** "PRESENT PILEUP: 12 Gifts Smashed on Ocean St Rooftops"
  - **Ended early:** "SLEIGH ROBBED BARE: Christmas Ends in Byron Bay"
  - **Dart left behind:** "'I WOKE UP WITH A DART IN MY NECK': Family Demands Answers From North Pole"
  - **Australia:** "STRUTH! Santa's Sleigh Spotted Over the Outback"
- POINT OF VIEW (decided Oct 20): the paper is written by local citizens' press, from the townspeople's view, never Santa's or the workshop's. Reporters only know what residents saw and found: empty stockings, smashed presents in the gutter, a dart in the couch, a sleigh scraping the roof at 2am, an elf glimpsed on the stairs. Santa never gets to explain himself. Quotes come from residents, kids, local police, the mayor, and the Santa Building Code inspector.

## Sleigh and reindeer (decided Oct 20)
- A real sleigh pulled by a team of reindeer.
- Reindeer are NOT part of landing requirements: only the sleigh's runners/body are judged. Reindeer can hang off the roof edge or over open air with no penalty.

### Headline bank: burst pipes (approved by the designer, Oct 20)
- "PLUMBERS WORKING CHRISTMAS DAY AFTER MYSTERY BIG FREEZE"

## Chimney entry and interiors (prototype, Oct 20)
- Landing houses have chunky Hello Neighbor brick chimneys with a real hollow flue, a sooty shaft, and a candy-striped Santa hatch. The fast-impact crash rule is unchanged.
- Flow: land on the roof near the chimney, press F, and the elf abseils down the flue on the Crook-Line (soot in the flue), then creeps out of the fireplace in green glowing mist. Third-person elf play (sneak and crouch). Exit is at the fireplace: winch back up to the sleigh.
- Interiors are seamless inside the real shells, so lit rooms are visible through the windows. There are three distinct layouts (one two-storey with stairs), all furnished with Blender-modelled furniture that has collision. Aussie summer Christmas dressing. Warm, saturated toon lighting from lamps, tree lights, nightlights and moonlight.
- Lit fireplaces block entry until frozen out with the Fireplace Icer.

## Prototype gadgets (first playable pass, Oct 20)
- Hotbar: Snooze Darts, Snore-o-Meter, Tuck Trolley, Fit-Ghost, Puff-Possum, The Ledger, Fireplace Icer, Fire Launcher. Always on: Glow-Gogs (N, residents notice you 1.25x faster), Dart Magnet (G), Crook-Line (chimney abseil).
- **Dart rules (the designer's rule change):** 10 darts for the whole run that never regenerate. Picking a dart back up returns it to your supply. The Dart Magnet grabs only the specific dart you're looking at (crosshair, line of sight) within 20 elf heights, one at a time, with a highlight and a grab prompt. It is not an area pull. The exit never locks, but leaving a dart behind means you're exposed: a clear warning at the fireplace ("2 darts left in house!") before you climb out, and a newspaper/penalty flag.
- **Fireplace Icer / Fire Launcher:** some fireplaces are lit, and coming down a lit chimney is blocked. Freeze the fire from the roof (down the flue) or at the fireplace, with frost, steam and ice crystals. Relight it with the Fire Launcher before leaving. A fire left out is evidence: a warning at exit and the "FIREPLACE MYSTERIOUSLY FROZEN" flag.
- **Burst pipes:** holding or overusing the Icer fills a visible freeze meter. Past the threshold, frost creeps along nearby pipes (by the fireplace and in the kitchen), then they crack, then burst: spray, bang, hiss. A burst lightens or wakes nearby residents and leaves a spreading slippery puddle. It counts as evidence (a warning at exit plus the burst-pipe headline). The Fire Launcher can thaw a cracked pipe before it bursts.
- Residents are placeholder sleepers. There's no stealth AI yet, only proximity awareness scaled by sleep depth, a night curve, goggles and crouch.

## Notes: chimney redo and furniture height tiers (2026-10-20)
- **Chimney** (scripts/chimney_model.gd): a chunky, slightly leaning and bulging brick stack, every brick its own instance in one MultiMesh (5 reds, mortar recess, chipped and missing bricks, soot near the top), a corbelled stepped crown with a chamfered cap, a terracotta liner/pot, and a green, brass-trimmed Santa hatch hinged at the back with a wreath and bow. Frost cap and icicles when iced, faint warm glow when lit. Entry: hop onto the crown, flip the hatch, peek in with the goggles, hook the candy-cane Crook-Line on the lip, abseil the sooty flue (cobwebs, soot gradient, warm or icy glow from below), push through the damper, peek out of the firebox. Exit reverses it and closes the hatch. Collision walls and the old random draws are unchanged, so the self-test is unaffected.
- **Stances:** stand 0.92 eh capsule, tactical crouch 0.75 eh (C toggle, crouch-walk with the dart pistol, noise 7 eh, visibility x0.65), crawl 0.5 eh (Ctrl hold, unchanged). Hidden works in any stance when fully under cover.
- **Furniture tiers:** under-able pieces get a LOW (0.62 eh, crawl-only), MID (0.85 eh, crouch-fit) or HIGH (1.15 eh, stand-under) gap from a shuffled bag seeded per house, so every house has all three. The gaps sit between the stance heights with margin (crawl 0.5 < LOW 0.62 < crouch 0.75 < MID 0.85 < stand 0.92 < HIGH 1.15). Legs are rebuilt to match (bun feet, turned legs, tall brass-capped legs) and things resting on the piece move with it. The dining table is left as-is (it's naturally stand-under).

## Notes: Crook-Line rope tech, climbing, lean (2026-10-20)
- One wrist launcher (scripts/rope_tech.gd) does everything: a ledge anchor at your feet means rappel, anything else means grapple. Same cable, hook and sounds as the chimney abseil, so the elf has one tool, not three.
- Anchors and climbables are data in interior.gd (rope_anchors, climbables), added without touching the layout RNG, so every house builds exactly as before. Each room gained a pendant light fitting (visual only) to swing from.
- Grapple is a pendulum with an inequality constraint (the cable pulls, never pushes), yaw-only facing and air drag, so it feels weighty and never flips. Rappel is scripted along the wall face with kick-off hops and an upside-down peek. Zipline uses gravity along the slope with rolling drag and a top speed; feet skim obstacles and you unclip at the far end.
- Ranges (elf heights / metres): grapple + reticle 18 / 3.96, rappel reach 3 / 0.66, zipline shot 30 / 6.6, clip-on 3 / 0.66, reel-in 5 / 1.1.
- A zipline left up is evidence at the exit (newspaper headline). Grapple and rappel lines whip back into the launcher when you let go.
- Climbing has a grip meter (7 s of climbing, slower drain when still, refills on the floor). Mantle only where the top is walkable (bookshelf, mantel); curtains and the tree stop at the top.
- Lean / peek (Z / X) slides the camera 0.6 eh sideways and tilts the body; it's ray-checked so it never pokes through the corner you're peeking round.
- The elf only plays indoors for now, so the outdoor climbables in the brief (drainpipes, trellis, tree trunks, roof edges) wait for an outdoor elf mode.

## Notes: decorations (2026-10-20)
- scripts/decor.gd builds everything visual-only with its own seeded RNG: no collision (elf routes and sleigh landings unchanged, self-test identical) and no shift in the house or furniture layouts.
- Indoors: mantel garland with bows and lights, cards on the mantel and on a string, tinsel swags under the cornice, fairy lights round every window (some warm white), lights along the hall, a wreath on both faces of the front door, a pavlova on the dining table. Already there: the tree (star, baubles, tinsel, lights), presents, stockings, cookies and milk, beer and a carrot, fan and air con.
- E at the cookies says "Santa will want those" (the beer and carrot: "The reindeer will want that"). No rule effect.
- Yards (front lawn, the street-door side): inflatable Santa and kangaroo (they sway), light-up wire reindeer with a red nose, a lit hedge, a small gum tree wrapped in lights, a nativity at the steep house. A different mix per house.


## Chimney: real-size rebuild (2026-10-20, late)
The designer found the chimney "bad or weird". It was a 1.2 m tower 1.55 m above the roof with a 1.56 m cap slab, 0.3 m bricks with grey gaps where bricks were missing, a terracotta liner, soot ring and a part-cover hatch stacked as orange/black/green layers on the cap (read as a striped box), a separate pot, and no flashing where it went into the roof. Now: 0.64 m square, 0.34 m open flue, about 1 m above the roofline (whole brick courses), straight through the roof with lead flashing (apron plus upstand, stepped on the gable), then a slight lean and belly above it. Bricks are drawn by a shader on metre UVs so every brick is 0.22 x 0.068 m on every face. Two corbelled courses and a sloped concrete cap, sooty round the hole. A small flat green hatch on an iron frame, hinged at the back. Collision follows the stack in three lifts plus the crown, open down the flue. The flue cutscene cameras are clamped inside the flue. Tunables: house.gd chimney_outer, flue_size, chimney_above_roof, chimney_lean, chimney_bulge.


## Elf hat fit (2026-10-20)
The elf's floppy hat sits on top of the head (brim just above the goggle strap, ears out under it) and its cone and pom hang on their own pivot. Under low surfaces the cone folds back and squashes just enough to stay under them, never through, and springs back when there's room. Stance fit uses the elf's full visual height with the hat folded (stand 0.93 eh, tactical crouch 0.80 eh, crawl 0.565 eh, plus 1 cm), so crawl fits LOW, crouch fits MID and stand fits HIGH. Walking towards something too low, the elf drops to crouch or crawl by itself, waits until its body is low enough, then goes under; it stands back up once there's room. The interior check fails if any elf mesh vertex ends up above a furniture underside, standing still or moving in and out.

## Chimney inside, real anatomy, no hatch (2026-10-21)
- No hatch, lid or door on the chimney. The top is the brick crown and concrete cap round an open, sooty flue; the wreath stays. Entry: the elf hops on the crown, peeks in with the goggles glowing, hooks the Crook-Line on the lip and abseils. Exit: winch up and climb out over the crown.
- The inside follows a real open-fireplace chimney (see CHIMNEY-RESEARCH.md): 250 x 250 mm clay flue liner (the size a 900 x 750 mm open fire needs), a 30-degree offset where the stack sits beside the fireplace, a corbelled smoke chamber widening to the fireplace width, a smoke shelf behind the throat, a cast-iron damper plate in the narrow throat above the lintel, and a firebox with a sloped firebrick back and splayed sides. The elf is 22 cm tall, so even the 250 mm liner is roomy for it. Descent beats: tight liner, chamber widening, squeeze past the damper, drop into the fire glow.
- The fire is real 3D: barked logs with charred, glowing ends on fire dogs and a grate, a crackling ember bed, layered flame tongues that lean outward so they read from directly above, sparks, smoke up the throat, heat shimmer, flickering light. Iced: frosted logs, cold blue embers, ice crystals, cold mist.
