# Engine Check for Santa Sim (Oct 20, 2026)

Read-only review of the designer's engines against DESIGN.md. Nothing inside the engine folders was modified or built.
Legend: **Y** = supported in code, **P** = partial / basic, **N** = missing (or only in docs/plans).

## Snapshot

| Engine | Lang | Size / activity | What it really is today |
|---|---|---|---|
| Forge Engine (`%USERPROFILE%\code\forge_engine`) | Rust, zero deps | ~25 files; **1 commit** ("Initial", Apr 5 2026) | Window + ECS + f32 math + Gouraud triangle renderer (software / Vulkan / GL). Demo = spinning tetrahedron (`src/main.rs`). |
| DnD-Game-Engine (`%USERPROFILE%\Desktop\DnD-Game-Engine`) | C++17 / OpenGL (+ empty Godot stub) | ~15k lines in `src/`; 2 commits (Sep 28 2026) | Real small engine: renderer, simple physics, skeletal anim, miniaudio, UI widgets, editor panels, D&D rules. The Godot side is only `project.godot` + a 249-byte `Scripts/GameManager.gd`; `Scenes/` has 0 files. |
| f4 (`D:\dev\f4`) | C++20 | ~1.8 MB src, 57 test files; 59 commits, last Oct 5 2026 | Most serious one: RHI with OpenGL/Vulkan/DX12/WebGPU (+partial Metal), render graph, PBR + glTF, deterministic noise, terrain meshing, hex/voxel/height world streaming. A renderer + procgen terrain engine, not a game engine yet. |
| Godot 4.7.2 | C++ / GDScript / C# | Installed (see below) | Full engine + editor. |

## Requirement table

| Requirement | Forge | DnD-Game-Engine | f4 | Godot 4.7 |
|---|---|---|---|---|
| 3D rendering, stylized art | P: flat/Gouraud triangles only; `Material` is a placeholder (`src/assets/types.rs`) | P: textured OBJ meshes, `src/rendering/renderer.cpp` | Y: PBR, glTF, shadows, instancing, particles (`src/engine/rendering/pbr.cpp`, `src/demos/demo_instancing.cpp`, `demo_particles.cpp`) | Y: custom shaders, toon/cel shading, Forward+ |
| Many emissive lights at night | N: no lights | N/P: hard cap `MAX_SPOTS 8`, `MAX_BOXES 16` occluders (`renderer.cpp:311-312`) | P: emissive in materials (20 refs); no bloom/glow found | Y: emission + Glow, clustered lights (hundreds of OmniLights), GPU particles |
| Globe + geo/OSM data | N | N | N: no globe, ECEF, or geodetic code (0 hits) | P: via addons (below); nothing built in |
| Streaming / LOD | N | N | Y/P: camera-ring chunk streaming, async workers (`src/engine/world/world_streaming.*`; plan says M16 "Partial") | Y: visibility ranges/HLOD, auto mesh LOD, threaded resource loading |
| Planet-scale float precision | N: f32 everywhere | N: f32 transforms | P: int64 hex/chunk coords (`world_data.h`), deterministic float flags (`cmake/FloatPrecision.cmake`); no floating-origin / camera-relative rendering found | Y: `precision=double` build (large world coordinates), or origin shifting |
| Rigid bodies, friction (icy roofs), objects sliding off | N: no physics code | P: linear impulse + friction (`src/physics/physics_system.cpp:273-290`), sphere/AABB only (`collision.cpp`); no angular/rotational dynamics found, no sloped/mesh colliders | N: fixed 60 Hz step loop only (`src/app/f4_app.cpp:539`); "collision demo" is 2D in NDC space | Y: Jolt Physics built in (per-body friction, rotation, convex/trimesh colliders) |
| Stealth AI: sight/hearing, navmesh, wake states | N | P: grid A* only (`src/ai/pathfinding.cpp`); `ai_brain.cpp` is an Ollama LLM bridge, not NPC AI | N: 0 navmesh/pathfind hits | Y: NavigationServer3D (navmesh baking, agents, avoidance); raycasts/Area3D for sight & hearing; state machines in script |
| Carry an NPC, put in bed | N | P: possible by hand (parenting transforms) | N | Y: reparent/attach nodes, ragdoll (PhysicalBone3D), AnimationTree poses |
| UI: route planner, sleigh packing | N | Y/P: retained widget system + drag-drop (`src/ui/ui_widget.cpp` 63 KB, `ui/drag_drop.cpp`) | P: HUD only (`src/graphics/hud`) | Y: Control nodes, drag-and-drop, themes |
| Animation | N | P: skeleton, clips, skinned mesh (`src/animation/*`, ~330 lines) | N: no skinning/skeleton code | Y: AnimationTree, blend trees, IK, glTF import |
| Audio | N | Y/P: miniaudio wrapper (`src/audio/audio_system.cpp`) | N: 0 audio hits | Y: 3D positional audio, buses, effects |
| Editor / tooling | N | P: dock manager, inspector, gizmo, undo, profiler (`src/tools/*`) | N: no editor (plan: "reflection waits for editor era") | Y: full editor |
| Maturity / maintenance | Abandoned prototype (1 commit, Apr) | Early; 2 commits, big monolithic demo scene (`dnd_demo_scene.cpp` 125 KB), 81 MB `engine.log` in repo root | Active, well tested, rigorous, but a renderer/terrain stack | Mature, big community, already used on this PC |

### Helper projects (parts only, not engines)
- **Bio-mec-an** (`%USERPROFILE%\Bio-mec-an`, Rust): biomechanics/RL sandbox built on **rapier3d 0.32** (`Cargo.toml`). Shows the designer can use Rapier, but Godot already has Jolt, so there's nothing to pull in. Its procedural locomotion (CPG + IK) is interesting for reindeer gait later, but it would need porting.
- **mmathEn** (`D:\mmathEn`, C++20): a **music/acoustics** math engine (tuning, DSP, waveguides, FEM for vibrating strings, hearing models), not rigid-body physics or game math. 440 tests passing (`verify_summary.txt`). Its only realistic use here is offline audio: synthesizing sleigh bells or creaky-floor sounds into WAVs.

## Godot on this PC
- **Godot 4.7.2 stable** works: `D:\dev\ofa\.tools\godot\Godot_v4.7.2-stable_win64.exe` (`--version` gives `4.7.2.stable.official.ed1daf0bf`). It is a portable copy inside the `ofa` project's tools folder, not a system install.
- `%USERPROFILE%\Downloads\Godot_v4.4-stable_win64.exe` is **1 byte** (broken). The 67 MB zip next to it is the real 4.4 download.
- `%APPDATA%\Godot` has editor settings for 4.3, 4.4, 4.6, and 4.7, so the designer already uses Godot regularly.
- Suggestion: copy 4.7.2 to its own folder (e.g. `D:\tools\godot\`) so the Santa project doesn't depend on `ofa`.

## Recommendation: Godot 4.7
None of the designer's engines can run this game without months of engine work first. Forge is a triangle demo. DnD-Game-Engine has the widest feature spread of the three, but every system is thin (8 lights, sphere/box physics with no rotation, grid A*). f4 has the best renderer and the streaming core, but no physics, audio, animation, navigation, or editor. Godot covers every requirement except geo, and geo is solvable with addons.

### Globe / geo approach in Godot
- **Globe view (planning + zoom-in):** a stylized globe made by us (a sphere with a painted continent texture, unlocked one continent at a time). The design calls for stylized art, so no photoreal globe is needed. For an optional real-terrain look: **3D Tiles for Godot** (Battle Road / Cesium, WGS84 globe, GDExtension, true-origin mode on double builds) or **Godotiles** (Rust GDExtension, quadtree LOD, imagery + elevation, built-in origin shifting, Godot 4.4+).
- **Town data:** do the OSM import **offline** in a small Python tool (osmnx / Overpass API pulls streets plus building footprints and heights), export per-town JSON or glTF, then generate Hello Neighbor-style houses in Godot from the footprints (extrude, tilt/warp, oversized chimneys, light strings along roof edges). `godot-openstreetmap` (RodZill4) exists but its own README calls it unstable, so use it for reference only. Note: OSM data is ODbL, so the game needs attribution.
- **Precision:** the globe is a menu/transition and each town is its own level. Put each town at the origin (local tangent plane) and the standard single-precision build is enough, which is the Godot docs' own advice for level-based worlds. Only switch to a `precision=double` custom build (that means compiling Godot and rebuilding any GDExtensions) if we later want one seamless flight from orbit to rooftop. Either way, keep lat/lon in doubles in game data.

### Possible role for the designer's own code
- f4's world-streaming ideas could inform a later continent streaming system, but don't port it now.
- mmathEn could generate audio assets offline.

## Next step
Greybox in Godot 4.7: one sleigh (RigidBody3D + thrust), three roof types (flat, pitched, icy with low friction), light-outlined edges, and a present that can slide off. This proves the landing feel before any geo work.

## Engine bot replies (Oct 20, read-only checks by each project's own bot)
All six recommend Godot.
- Forge Engine bot: about 4.6k lines; no lighting, models, physics, AI, animation, UI, audio, or editor. "Many person-years" from a game like this.
- DnD Game Engine bot: native C++/OpenGL; the Godot part is a leftover stub. Nothing worth porting to Godot.
- f4 bot: strong renderer and asset import, but a single directional light (PointLight is a stub), a flat chunk world with no globe or floating origin, and no physics, skinning, AI, audio, game UI, or editor. "Months to years" of engine work.
- Bio-mec-an bot: a creature-sim studio with an offline renderer only. Could later bake elf or reindeer gaits offline.
- mmath bot: an audio/acoustics lib, no game math. Could later make physically modeled sleigh bells and wind sounds.
- Canvas Fogworks bot (WebGL1 tool): 4-light cap, no fog or post effects, box/sphere physics, no AI. Best used as a content tool exporting glTF/PNG textures and simple house models to Godot.
