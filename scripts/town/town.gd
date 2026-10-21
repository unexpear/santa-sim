extends Node3D
## Real-map town: loads data/towns/<town>.json (made offline by tools/osm/osm_import.py from
## OpenStreetMap) and builds the streets and OUR stylised Santa-ready houses on the real footprints.
## Real geography, invented buildings (alt-history: every roof is built for Santa).
## Fly the sleigh around; delivery houses have landing decks with proper roof collision.
## Map data (c) OpenStreetMap contributors, ODbL. User args (after "--"):
##   --town=<res path or file>   another town file
##   --townshots=<dir>           top-down / street / flying screenshots, then quit
##   --townfps                   fly a scripted lap and print FPS, then quit
##   --townselftest              scripted landings on delivery decks (works headless), then quit

const GB := preload("res://scripts/greybox.gd")
const LightString := preload("res://scripts/light_string.gd")
const MeshBatch := preload("res://scripts/town/mesh_batch.gd")
const HouseGen := preload("res://scripts/town/house_gen.gd")
const Props := preload("res://scripts/town/town_props.gd")
const Deco := preload("res://scripts/town/town_deco.gd")
const SleighScene := preload("res://scenes/sleigh.tscn")
const PresentScene := preload("res://scenes/present.tscn")
const TeamScript := preload("res://scripts/reindeer_team.gd")
const CamScript := preload("res://scripts/chase_camera.gd")
const HudScript := preload("res://scripts/hud.gd")
const BULB_SHADER := preload("res://shaders/bulb.gdshader")

const STAR := "★"
const NO_STAR := "☆"
const VERGE := 1.6
const FP_W := 1.5
const LANDING_TYPES := ["pad", "ridge", "slick", "pad", "bonus", "ridge", "slick", "pad", "ridge", "bonus", "pad", "slick"]
const LANDING_COLORS := {"pad": Color(0.1, 1.0, 0.25), "ridge": Color(0.1, 1.0, 0.25), "slick": Color(0.15, 0.45, 1.0), "bonus": Color(1.0, 0.65, 0.05)}
const DANGER := Color(1.0, 0.1, 0.06)

@export_file("*.json") var town_file := "res://data/towns/paddington_qld.json"
@export var town_seed := 2026
@export var delivery_count := 10
@export var decorations := true  ## Christmas yard decorations (inflatables, lit trees, reindeer, nativities...).
@export var full_collision := true  ## Solid collision on everything (houses, trees, poles, fences...). Off = old simple hulls.
@export var collision_chunk := 96.0  ## Static collision is merged into one trimesh per (category, chunk).
@export_group("Street")
@export var streetlight_spacing := 44.0
@export var streetlight_energy := 2.6
@export var streetlight_range := 12.0
@export var street_tree_spacing := 24.0
@export var backyard_tree_chance := 0.55
@export var hoist_chance := 0.18
@export_group("Lights")
@export var bg_bulb_spacing := 0.6
@export var bg_bulb_energy := 1.25
@export var landing_light_energy := 2.2
@export_group("Look")
@export var moon_light_energy := 1.0
@export var warm_fill_energy := 0.3
@export var rim_light_energy := 0.5
@export var ambient_energy := 0.5
@export var exposure := 1.15
@export var saturation := 1.18
@export var glow_intensity := 0.55
@export var volumetric_fog := true
@export var fog_density := 0.004
@export var launch_pad_height := 12.0

var town: Dictionary
var sleigh: RigidBody3D
var team: Node3D
var camera: Camera3D
var hud: CanvasLayer
var world_env: Environment
var deliveries: Array = []  ## {addr, type, node, deck_centre, chimney, done, stars}
var house_infos: Array = []  ## per-building build info (for props / checks)
var stats := {}
var last_landing := "none yet"
var current_present: RigidBody3D
var all_presents: Array[RigidBody3D] = []
var presents_delivered := 0
var presents_broken := 0
var pad_top := Vector3.ZERO
var _road_grid: Dictionary = {}  # Vector2i -> [[a2, b2, half_width]]
var _bld_grid: Dictionary = {}  # Vector2i -> [[c2, ax2, ay2, hx, hy]]
var _bulbs: Dictionary = {}  # chunk Vector2i -> {"x": [], "c": [], "d": []}
var _streetlight_points: Array = []
var _marker_nodes: Array = []
var _t := 0.0
# collision: "cat|cx,cz" -> PackedVector3Array faces; built into StaticBody3Ds at the end
var _col_faces: Dictionary = {}
var _col_bodies: Array = []  ## [StaticBody3D, category]
var _col_templates: Dictionary = {}
var _debug_root: Node3D
var _crash_log: Array = []
var _street_trees: Array = []  ## [Transform3D, along-road Vector3] for the collision checks
var _fence_list: Array = []
var _light_list: Array = []
const COL_INFO := {
	"house": ["Rooftop (not on tonight's list)", "a house", Color(1.0, 0.85, 0.2)],
	"filler": ["Rooftop (not on tonight's list)", "a house", Color(0.9, 0.6, 0.2)],
	"tree": ["Gum tree", "a gum tree", Color(0.3, 1.0, 0.3)],
	"light": ["Streetlight", "a streetlight", Color(0.4, 0.8, 1.0)],
	"fence": ["Fence", "a fence", Color(1.0, 1.0, 1.0)],
	"letterbox": ["Letterbox", "a letterbox", Color(1.0, 0.4, 0.4)],
	"hoist": ["Hills Hoist", "a Hills Hoist", Color(0.8, 0.8, 0.9)],
	"kerb": ["Kerb", "the kerb", Color(0.7, 0.5, 1.0)],
	"tower": ["Launch tower", "the launch tower", Color(1.0, 0.5, 0.1)],
	"delivery": ["House", "a house", Color(1.0, 0.3, 0.9)],
	"far": ["Hillside", "a hill", Color(0.6, 0.6, 0.6)],
	"santa": ["Inflatable Santa", "an inflatable Santa", Color(1.0, 0.2, 0.2)],
	"roo": ["Inflatable kangaroo", "an inflatable kangaroo", Color(0.9, 0.6, 0.3)],
	"reindeer": ["Light-up reindeer", "a light-up reindeer", Color(1.0, 1.0, 0.6)],
	"nativity": ["Nativity scene", "the nativity scene", Color(0.8, 0.6, 0.3)],
	"hedge": ["Hedge", "a hedge", Color(0.2, 0.8, 0.3)],
	"jacaranda": ["Jacaranda", "a jacaranda", Color(0.7, 0.5, 1.0)],
}


func _enter_tree() -> void:
	_setup_input()


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--town="):
			town_file = a.get_slice("=", 1)
		elif a == "--nocollide":
			full_collision = false
		elif a == "--nodeco":
			decorations = false
	if not _load():
		return
	_environment()
	_ground()
	_index_roads()
	_index_buildings()
	_roads()
	_buildings()
	_props()
	if decorations:
		Deco.new(self, town_seed).build()
	_outskirts()
	_commit_bulbs()
	_launch_pad()
	_build_collision()
	_spawn_player()
	_ui()
	stats["build_ms"] = Time.get_ticks_msec() - t0
	print("[town] %s: %d buildings (%d houses, %d delivery), %d roads, %d streetlights, %d trees, built in %d ms" % [
			town.get("display_name", "?"), stats.get("buildings", 0), stats.get("houses", 0), deliveries.size(),
			(town.roads as Array).size(), _streetlight_points.size(), stats.get("trees", 0), stats.build_ms])
	print("[town] styles: %s   filler houses outside the square: %d   background bulbs: %d" % [str(stats.get("styles", {})), stats.get("filler_houses", 0), stats.get("bg_bulbs", 0)])
	for d in deliveries:
		print("[town] delivery: %s (%s deck, %s)" % [d.addr, d.type, d.style])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--townshots="):
			_shots(a.get_slice("=", 1))
		elif a == "--townfps":
			_fps_lap()
		elif a == "--townselftest":
			_selftest()
		elif a == "--townphys":
			_phys_bench()
		elif a == "--towncollide":
			_collide_check()
		elif a.begins_with("--decoshot="):
			_deco_shot(a.get_slice("=", 1))
		elif a.begins_with("--colshot="):
			_collision_shot(a.get_slice("=", 1))


# --- data -------------------------------------------------------------------------------------------

func _load() -> bool:
	var txt := FileAccess.get_file_as_string(town_file)
	if txt.is_empty():
		push_error("[town] can't read %s (run tools/osm/osm_import.py first)" % town_file)
		return false
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY or d.get("format", "") != "santa-sim-town":
		push_error("[town] %s is not a santa-sim-town file" % town_file)
		return false
	town = d
	return true


static func v2(p: Array) -> Vector2:
	return Vector2(float(p[0]), -float(p[1]))  # map (east, north) -> Godot (x, z)


static func v3(p: Array, y := 0.0) -> Vector3:
	return Vector3(float(p[0]), y, -float(p[1]))


static func poly2(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(v2(p))
	return out


func _cell(p: Vector2, size := 20.0) -> Vector2i:
	return Vector2i(floori(p.x / size), floori(p.y / size))


func _index_roads() -> void:
	for r in town.roads:
		if r.tunnel:
			continue
		var pts := poly2(r.pts)
		var hw := float(r.width) * 0.5
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var c0 := _cell(Vector2(minf(a.x, b.x) - hw, minf(a.y, b.y) - hw))
			var c1 := _cell(Vector2(maxf(a.x, b.x) + hw, maxf(a.y, b.y) + hw))
			for x in range(c0.x, c1.x + 1):
				for y in range(c0.y, c1.y + 1):
					var k := Vector2i(x, y)
					if not _road_grid.has(k):
						_road_grid[k] = []
					_road_grid[k].append([a, b, hw])


## Distance from p to the nearest road edge (negative = on the carriageway).
func road_clearance(p: Vector2) -> float:
	var best := 99.0
	var c := _cell(p)
	for x in range(c.x - 1, c.x + 2):
		for y in range(c.y - 1, c.y + 2):
			for s in _road_grid.get(Vector2i(x, y), []):
				var q := Geometry2D.get_closest_point_to_segment(p, s[0], s[1])
				best = minf(best, p.distance_to(q) - float(s[2]))
	return best


func _index_buildings() -> void:
	for b in town.buildings:
		var c := v2(b.obb.c)
		var a := float(b.obb.angle)
		var ax := Vector2(cos(a), -sin(a))
		var ay := Vector2(-ax.y, ax.x)
		var e := [c, ax, ay, float(b.obb.size[0]) * 0.5, float(b.obb.size[1]) * 0.5]
		var r := maxf(e[3], e[4])
		var c0 := _cell(c - Vector2(r, r))
		var c1 := _cell(c + Vector2(r, r))
		for x in range(c0.x, c1.x + 1):
			for y in range(c0.y, c1.y + 1):
				var k := Vector2i(x, y)
				if not _bld_grid.has(k):
					_bld_grid[k] = []
				_bld_grid[k].append(e)


## True when p is at least `margin` metres from every building footprint box.
func clear_of_buildings(p: Vector2, margin: float) -> bool:
	var c := _cell(p)
	for x in range(c.x - 1, c.x + 2):
		for y in range(c.y - 1, c.y + 2):
			for e in _bld_grid.get(Vector2i(x, y), []):
				var d: Vector2 = p - e[0]
				if absf(d.dot(e[1])) < float(e[3]) + margin and absf(d.dot(e[2])) < float(e[4]) + margin:
					return false
	return true


func in_extent(p: Vector2, pad := 0.0) -> bool:
	var mn := v2(town.extent.min)
	var mx := v2(town.extent.max)
	return p.x > mn.x - pad and p.x < mx.x + pad and p.y < mn.y + pad and p.y > mx.y - pad


# --- world ------------------------------------------------------------------------------------------

func _environment() -> void:
	var moon_dir := Vector3(0.3, 0.45, -0.85).normalized()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/night_sky.gdshader")
	sky_mat.set_shader_parameter("moon_dir", moon_dir)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.44, 0.78)
	env.ambient_light_energy = ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = exposure
	env.glow_enabled = true
	env.glow_intensity = glow_intensity
	env.glow_strength = 1.0
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 0.95
	env.glow_hdr_scale = 1.5
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.5
	env.volumetric_fog_enabled = volumetric_fog
	env.volumetric_fog_density = fog_density
	env.volumetric_fog_albedo = Color(0.62, 0.5, 0.78)
	env.volumetric_fog_emission = Color(0.05, 0.03, 0.07)
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_length = 220.0
	env.volumetric_fog_ambient_inject = 0.25
	env.volumetric_fog_sky_affect = 0.1
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.36, 0.26, 0.5)
	env.fog_depth_begin = 320.0
	env.fog_depth_end = 3200.0
	env.fog_depth_curve = 1.6
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = saturation
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	world_env = env
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.72, 0.78, 1.0)
	moon.light_energy = moon_light_energy
	moon.shadow_enabled = true
	moon.shadow_blur = 1.6
	moon.directional_shadow_max_distance = 160.0
	moon.shadow_opacity = 0.85
	add_child(moon)
	moon.look_at_from_position(Vector3.ZERO, Vector3(0.55, -0.62, -0.55), Vector3.UP)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(1.0, 0.62, 0.35)
	fill.light_energy = warm_fill_energy
	add_child(fill)
	fill.look_at_from_position(Vector3.ZERO, Vector3(-0.7, -0.3, -0.35), Vector3.UP)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(1.0, 0.55, 0.38)
	rim.light_energy = rim_light_energy
	add_child(rim)
	rim.look_at_from_position(Vector3.ZERO, Vector3(-0.15, -0.22, 1.0), Vector3.UP)


func _ground() -> void:
	var mn := v2(town.extent.min)
	var mx := v2(town.extent.max)
	var size := Vector3(absf(mx.x - mn.x) + 900.0, 1.0, absf(mx.y - mn.y) + 900.0)
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.add_to_group("ground")
	ground.set_meta("surface_name", "Yard")
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	ground.add_child(cs)
	ground.position = Vector3((mn.x + mx.x) * 0.5, -0.5, (mn.y + mx.y) * 0.5)
	add_child(ground)
	var gm := BoxMesh.new()
	gm.size = size
	GB.add_mesh(ground, gm, Vector3.ZERO, Vector3.ZERO, GB.patchy(Color(0.2, 0.42, 0.14), Color(0.42, 0.48, 0.16), 0.45, 0.035))
	# Landuse: parks / grass / pools / car parks
	var B = MeshBatch.new()
	B.chunk_size = 4096.0
	B.register("park", GB.patchy(Color(0.18, 0.5, 0.16), Color(0.35, 0.6, 0.2), 0.6, 0.08))
	B.register("wood", GB.patchy(Color(0.1, 0.3, 0.12), Color(0.2, 0.4, 0.15), 0.6, 0.1))
	B.register("pool", GB.mat(Color(0.2, 0.75, 0.95), 0.5, 0.3, 0.8))
	B.register("asphalt_lu", GB.patchy(Color(0.25, 0.2, 0.32), Color(0.32, 0.26, 0.4), 0.5, 0.3))
	for l in town.landuse:
		var key := ""
		var y := 0.012
		match String(l.type):
			"park", "grass", "pitch":
				key = "park"
			"wood":
				key = "wood"
			"swimming_pool":
				key = "pool"
				y = 0.03
			"parking":
				key = "asphalt_lu"
				y = 0.02
		if key != "":
			B.flat_poly(key, poly2(l.poly), y)
	for w in town.water:
		B.flat_poly("pool", poly2(w.poly), 0.02)
	B.commit(self, false)


func _roads() -> void:
	var B = MeshBatch.new()
	B.chunk_size = 192.0
	B.register("asphalt", GB.patchy(Color(0.25, 0.2, 0.32), Color(0.32, 0.26, 0.4), 0.5, 0.3))
	B.register("lane", GB.patchy(Color(0.4, 0.36, 0.42), Color(0.46, 0.42, 0.5), 0.5, 0.3))
	B.register("line", GB.mat(Color(1.0, 0.8, 0.3), 0.35))
	B.register("kerb", GB.mat(Color(0.6, 0.55, 0.6)))
	B.register("footpath", GB.patchy(Color(0.72, 0.68, 0.66), Color(0.62, 0.58, 0.6), 0.4, 0.5))
	B.register("pavers", GB.patchy(Color(0.75, 0.5, 0.38), Color(0.62, 0.42, 0.34), 0.4, 0.6))
	B.no_shadow["line"] = true
	var junctions: Array[Vector2] = []
	for j in town.junctions:
		junctions.append(v2(j))
	for r in town.roads:
		if r.tunnel:
			continue
		var pts := poly2(r.pts)
		if pts.size() < 2:
			continue
		B.set_chunk_at(Vector3(pts[0].x, 0, pts[0].y))
		var w := float(r.width)
		var minor := String(r.type) == "service"
		var key := "lane" if minor else "asphalt"
		var y := 0.028 if minor else 0.03
		B.ribbon(key, pts, w, y)
		for p in pts:
			B.disc(key, p, w * 0.5, y - 0.001, 12)
		# yellow centre lines (dashed; double solid on the bigger roads), kept clear of junctions
		if not minor and w >= 6.0:
			var double := String(r.type) in ["secondary", "primary", "trunk"]
			_centre_line(B, pts, junctions, w, double)
	var KC = MeshBatch.new()
	KC.chunk_size = collision_chunk
	B.col_sink = KC
	B.col_key = "kerb"
	B.col_on = full_collision
	for k in town.kerbs:
		var pts := poly2(k.pts)
		B.set_chunk_at(Vector3(pts[0].x, 0, pts[0].y))
		B.wall_line("kerb", pts, 0.22, 0.0, 0.15)
	B.col_on = false
	_take_faces(KC)
	for f in town.footpaths:
		var pts := poly2(f.pts)
		B.set_chunk_at(Vector3(pts[0].x, 0, pts[0].y))
		B.ribbon("footpath", pts, float(f.width), 0.07)
	for p in town.paths:
		var pts := poly2(p.pts)
		B.set_chunk_at(Vector3(pts[0].x, 0, pts[0].y))
		B.ribbon("footpath" if String(p.type) != "steps" else "pavers", pts, float(p.width), 0.075)
	B.commit(self, false)


func _centre_line(B, pts: PackedVector2Array, junctions: Array[Vector2], w: float, double: bool) -> void:
	var dash := 3.0
	var gap := 6.0
	var acc := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var L := a.distance_to(b)
		if L < 0.01:
			continue
		var d := (b - a) / L
		var t := 0.0
		while t < L:
			var cyc := fmod(acc + t, dash + gap) if not double else 0.0
			var step := minf(1.0, L - t)
			if double or cyc < dash:
				var p0 := a + d * t
				var p1 := a + d * (t + step)
				var ok := true
				for j in junctions:
					if j.distance_to(p0) < w * 0.5 + 6.0:
						ok = false
						break
				if ok:
					if double:
						var n := Vector2(-d.y, d.x) * 0.16
						B.ribbon("line", PackedVector2Array([p0 + n, p1 + n]), 0.12, 0.04)
						B.ribbon("line", PackedVector2Array([p0 - n, p1 - n]), 0.12, 0.04)
					else:
						B.ribbon("line", PackedVector2Array([p0, p1]), 0.16, 0.04)
			t += step
		acc += L


func _pick_deliveries() -> Dictionary:
	# Farthest-point sampling over decent-sized houses, starting near the centre: spread out drops.
	var cand: Array = []
	for i in (town.buildings as Array).size():
		var b: Dictionary = town.buildings[i]
		if String(b.kind) != "house" or b.get("front") == null:
			continue
		var s: Array = b.obb.size
		if minf(float(s[0]), float(s[1])) < 7.5 or float(b.area) < 90.0 or float(b.area) > 420.0:
			continue
		if b.get("road_dist") == null or float(b.road_dist) > 35.0:
			continue
		cand.append(i)
	var chosen: Array = []
	if cand.is_empty():
		return {}
	var best: int = cand[0]
	for i in cand:
		if v2(town.buildings[i].center).length() < v2(town.buildings[best].center).length():
			best = i
	chosen.append(best)
	while chosen.size() < mini(delivery_count, cand.size()):
		var far := -1
		var far_d := -1.0
		for i in cand:
			if i in chosen:
				continue
			var dmin := 1e9
			for c in chosen:
				dmin = minf(dmin, v2(town.buildings[i].center).distance_to(v2(town.buildings[c].center)))
			if dmin > far_d:
				far_d = dmin
				far = i
		chosen.append(far)
	var out := {}
	for k in chosen.size():
		out[chosen[k]] = LANDING_TYPES[k % LANDING_TYPES.size()]
	return out


func _buildings() -> void:
	var B = MeshBatch.new()
	B.chunk_size = 192.0
	var gen := HouseGen.new(B)
	var picks := _pick_deliveries()
	var styles := {}
	var COL = MeshBatch.new()
	COL.chunk_size = collision_chunk
	if full_collision:
		B.col_sink = COL
		B.col_key = "house"
	var bodies := StaticBody3D.new()
	bodies.name = "BuildingHulls"
	bodies.set_meta("surface_name", "Rooftop (not on tonight's list)")
	bodies.set_meta("what", "a house")
	add_child(bodies)
	var nb := 0
	var nh := 0
	for i in (town.buildings as Array).size():
		var b: Dictionary = town.buildings[i]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(b.id) + ":" + str(town_seed))
		var style := HouseGen.pick_style(b, rng)
		styles[style] = int(styles.get(style, 0)) + 1
		nb += 1
		if String(b.kind) == "house":
			nh += 1
		if picks.has(i):
			if style in ["modern", "brick"] and rng.randf() < 0.7:
				style = "queenslander"
			_delivery_house(b, style, String(picks[i]), rng)
			continue
		var info: Dictionary = gen.build(b, style, rng)
		info["b"] = b
		house_infos.append(info)
		if not full_collision and info.has("hull"):
			var cs := CollisionShape3D.new()
			var sh := ConvexPolygonShape3D.new()
			sh.points = info.hull
			cs.shape = sh
			bodies.add_child(cs)
		if info.has("eave_world") and style != "shed":
			_add_bg_bulbs(info.eave_world, not info.get("eave_open", false), rng)
	B.commit(self, true)
	_take_faces(COL)
	if bodies.get_child_count() > 0:
		_col_bodies.append([bodies, "house"])
	stats["buildings"] = nb
	stats["houses"] = nh
	stats["styles"] = styles
	stats["tris_buildings"] = B.tri_count


func _delivery_house(b: Dictionary, style: String, ltype: String, rng: RandomNumberGenerator) -> void:
	var B = MeshBatch.new()
	B.chunk_size = 100000.0
	var DC = MeshBatch.new()
	DC.chunk_size = 100000.0
	B.col_sink = DC
	B.col_key = "delivery"
	var gen := HouseGen.new(B)
	var info: Dictionary = gen.build(b, style, rng, {"type": ltype})
	info["b"] = b
	info["delivery"] = true
	house_infos.append(info)
	var addr := String(b.addr) if String(b.addr) != "" else ("House on " + String(b.street) if String(b.street) != "" else "Mystery house")
	var root := Node3D.new()
	root.name = "Delivery_%d" % deliveries.size()
	add_child(root)
	B.commit(root, true)
	var col: Color = LANDING_COLORS[ltype]
	var base: Transform3D = info.base
	# Walls: convex hull of the wall box from the ground up to the eaves (hitting it fast = crash).
	# Walls, verandah, stumps, stairs...: the house's own simplified geometry (everything but the
	# scored roof parts, which get their own bodies below). Hitting it fast = crash.
	var walls := StaticBody3D.new()
	walls.set_meta("surface_name", addr + " (wall)")
	walls.set_meta("what", "the house at " + addr)
	root.add_child(walls)
	var wf: PackedVector3Array = DC.faces_all()
	var wcs := CollisionShape3D.new()
	if full_collision and not wf.is_empty():
		var wsh := ConcavePolygonShape3D.new()
		wsh.backface_collision = true
		wsh.set_faces(wf)
		wcs.shape = wsh
	else:
		var hull := PackedVector3Array()
		var hp: PackedVector3Array = info.hull
		for k in mini(8, hp.size()):
			var p := hp[k]
			hull.append(Vector3(p.x, minf(p.y, float(info.top) - 0.05), p.z))
		var wsh2 := ConvexPolygonShape3D.new()
		wsh2.points = hull
		wcs.shape = wsh2
	walls.add_child(wcs)
	_col_bodies.append([walls, "delivery"])
	# Deck: the safe landing pad (box, good grip; rain-slick ones are wet and slippery).
	var deck: PackedVector3Array = info.deck_world
	var dc := (deck[0] + deck[1] + deck[2] + deck[3]) * 0.25
	var dx := deck[0].distance_to(deck[1])
	var dz := deck[1].distance_to(deck[2])
	var pad := StaticBody3D.new()
	pad.add_to_group("roof")
	var surf: String = {"pad": "Santa deck", "ridge": "Ridge deck", "slick": "Rain-slick deck", "bonus": "Bonus deck"}[ltype]
	pad.set_meta("surface_name", "%s · %s" % [addr, surf])
	pad.set_meta("delivery", deliveries.size())
	var pm := PhysicsMaterial.new()
	pm.friction = 0.02 if ltype == "slick" else 1.0
	pad.physics_material_override = pm
	var pcs := CollisionShape3D.new()
	var psh := BoxShape3D.new()
	psh.size = Vector3(dx, 0.3, dz)
	pcs.shape = psh
	pad.add_child(pcs)
	root.add_child(pad)
	_col_bodies.append([pad, "delivery"])
	pad.global_transform = Transform3D(base.basis, dc + Vector3(0, -0.11, 0))
	# Slopes: low grip, scored as roof but you slide off (like the steep roof in the landing test).
	var spm := PhysicsMaterial.new()
	spm.friction = 0.1
	for s in info.get("slopes", []):
		var sb := StaticBody3D.new()
		sb.add_to_group("roof")
		sb.set_meta("surface_name", "%s · Roof slope" % addr)
		sb.set_meta("delivery", deliveries.size())
		sb.physics_material_override = spm
		var scs := CollisionShape3D.new()
		var ssh := ConvexPolygonShape3D.new()
		var sp := PackedVector3Array()
		for p in s:
			sp.append(p + Vector3(0, 0.02, 0))
			sp.append(p + Vector3(0, -0.3, 0))
		ssh.points = sp
		scs.shape = ssh
		sb.add_child(scs)
		root.add_child(sb)
		_col_bodies.append([sb, "delivery"])
	# Chimney collision (solid; flying into it fast is a crash)
	var ch := StaticBody3D.new()
	ch.set_meta("surface_name", addr + " chimney")
	var ccs := CollisionShape3D.new()
	var csh := BoxShape3D.new()
	var ctop: Vector3 = info.chimney_top
	var cbase: Vector3 = info.base * info.chimney_local
	csh.size = Vector3(float(info.chimney_w), ctop.y - cbase.y, float(info.chimney_w))
	ccs.shape = csh
	ch.add_child(ccs)
	root.add_child(ch)
	ch.set_meta("what", "a chimney")
	_col_bodies.append([ch, "delivery"])
	ch.global_transform = Transform3D(base.basis, Vector3(ctop.x, (ctop.y + cbase.y) * 0.5, ctop.z))
	# Lights: deck outline in the landing colour (green chases toward the deck), eaves in danger red.
	var dl := PackedVector3Array()
	for p in deck:
		dl.append(p + Vector3(0, 0.14, 0))
	dl.append(dl[0])
	var ls := LightString.new()
	ls.spill_every = 5.0
	root.add_child(ls)
	ls.setup(dl, col, ltype == "pad", landing_light_energy)
	var el := PackedVector3Array(info.eave_world)
	el.append(el[0])
	var es := LightString.new()
	es.spill_every = 0.0
	es.bulb_spacing = 0.4
	root.add_child(es)
	es.setup(el, DANGER if ltype != "bonus" else col, false, landing_light_energy * 0.8, false, false)
	# Floating star marker above the chimney (turns green once delivered).
	var star := Node3D.new()
	star.position = Vector3(dc.x, float(info.deck_y) + 5.5, dc.z)
	root.add_child(star)
	for r in [0.0, 45.0]:
		GB.box(star, Vector3(0.9, 0.9, 0.18), Vector3.ZERO, Color(1.0, 0.8, 0.2), Vector3(0, 0, r), 3.0)
	var beam := GB.cylinder(star, 0.06, 0.06, 4.6, Vector3(0, -2.6, 0), Color(1.0, 0.75, 0.3), Vector3.ZERO, 1.6, 6)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker_nodes.append(star)
	deliveries.append({"addr": addr, "type": ltype, "style": style, "node": root, "deck_centre": dc, "deck_size": Vector2(dx, dz),
			"basis": base.basis, "chimney": ctop, "done": false, "stars": 0, "star": star, "info": info})


# --- background Christmas lights (batched) ------------------------------------------------------------

func _add_bg_bulbs(loop: PackedVector3Array, closed: bool, rng: RandomNumberGenerator) -> void:
	var pts := PackedVector3Array(loop)
	if closed:
		pts.append(pts[0])
	var warm := rng.randf() < 0.7
	var palette: Array = [Color(1.0, 0.78, 0.45), Color(1.0, 0.9, 0.7)] if warm else [Color(1.0, 0.25, 0.2), Color(0.3, 1.0, 0.4), Color(0.35, 0.5, 1.0), Color(1.0, 0.75, 0.2)]
	var key := Vector2i(floori(pts[0].x / 192.0), floori(pts[0].z / 192.0))
	if not _bulbs.has(key):
		_bulbs[key] = {"x": [], "c": [], "d": [], "w": []}
	var bucket: Dictionary = _bulbs[key]
	var n := 0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var L := a.distance_to(b)
		var cnt := maxi(1, int(L / bg_bulb_spacing))
		bucket.w.append([a, b])
		for k in cnt:
			var t := (float(k) + 0.5) / float(cnt)
			var p := a.lerp(b, t) + Vector3.DOWN * (0.06 + 0.08 * sin(t * PI * maxf(1.0, L / 1.4)) * 0.5)
			var bas := Basis(Vector3.UP, rng.randf_range(0, TAU)) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3))
			bucket.x.append(Transform3D(bas, p))
			bucket.c.append(palette[n % palette.size()])
			bucket.d.append(Color(rng.randf(), rng.randf(), 0, 0))
			n += 1


func _commit_bulbs() -> void:
	var bulb := Props.lowpoly_bulb()
	var mat := ShaderMaterial.new()
	mat.shader = BULB_SHADER
	mat.set_shader_parameter("energy", bg_bulb_energy)
	mat.set_shader_parameter("max_distance_scale", 2.0)
	var total := 0
	var wire := MeshBatch.new()
	wire.chunk_size = 192.0
	wire.register("wire", GB.mat(Color(0.04, 0.07, 0.05), 0.0, 0.1))
	wire.no_shadow["wire"] = true
	for key in _bulbs:
		var bk: Dictionary = _bulbs[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = bulb
		mm.instance_count = bk.x.size()
		for i in bk.x.size():
			mm.set_instance_transform(i, bk.x[i])
			mm.set_instance_color(i, bk.c[i])
			mm.set_instance_custom_data(i, bk.d[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.name = "Bulbs_%d_%d" % [key.x, key.y]
		add_child(mmi)
		total += bk.x.size()
		for seg in bk.w:
			wire.set_chunk_at(seg[0])
			wire.beam("wire", seg[0] + Vector3(0, -0.03, 0), seg[1] + Vector3(0, -0.03, 0), 0.03, 0.03)
	wire.commit(self, false)
	stats["bg_bulbs"] = total


# --- street furniture ---------------------------------------------------------------------------------

func _props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = town_seed
	var tree_x: Array = [[], [], []]
	var light_x: Array = []
	var fence_x := {}
	var letter_x: Array = [[], [], []]
	var hoist_x: Array = []
	var B = MeshBatch.new()  # driveways + front paths
	B.chunk_size = 192.0
	B.register("drive", GB.patchy(Color(0.66, 0.63, 0.6), Color(0.56, 0.54, 0.55), 0.4, 0.4))
	B.register("pavers", GB.patchy(Color(0.78, 0.48, 0.34), Color(0.66, 0.4, 0.3), 0.4, 0.8))

	# Front yards: path from the front door to the footpath, driveway beside the house, front fence
	# with gaps, a letterbox by the gate; gum tree and Hills Hoist out the back.
	for info in house_infos:
		var b: Dictionary = info.b
		var style := String(info.style)
		if style in ["shop", "shed"] or b.get("road_pt") == null or b.get("road_width") == null:
			continue
		var base: Transform3D = info.base
		var fz := base.basis.z
		var fx := base.basis.x
		var hw := float(b.road_width) * 0.5
		var door: Vector3 = info.get("door", base.origin)
		var rp := v3(b.road_pt)
		var to_road := rp - door
		to_road.y = 0
		var s := to_road.dot(fz)
		var front_line := s - (hw + VERGE + FP_W + 0.3)  # distance from the door to the front boundary
		if s < 3.0 or front_line < 0.6 or front_line > 22.0 or float(b.road_dist) > 45.0:
			continue
		B.set_chunk_at(door)
		var gate := door + fz * front_line
		B.ribbon("pavers", PackedVector2Array([Vector2(door.x, door.z), Vector2(gate.x, gate.z) + Vector2(fz.x, fz.z) * (FP_W * 0.5 + 0.3)]), 1.1, 0.05)
		# driveway on the clearer side
		var W := float(info.W)
		var drive_side := 0.0
		for side: float in [1.0, -1.0]:
			var probe := base.origin + fx * side * (W * 0.5 + 1.6)
			if clear_of_buildings(Vector2(probe.x, probe.z), 0.2) and clear_of_buildings(Vector2(probe.x, probe.z) - Vector2(fz.x, fz.z) * 3.0, 0.2):
				drive_side = side
				break
		var drive_x := 0.0
		if drive_side != 0.0:
			drive_x = W * 0.5 + 1.6
			var d0 := base.origin + fx * drive_side * drive_x - fz * minf(float(info.D) * 0.3, 4.0)
			var d1 := d0 + fz * (to_road.dot(fz) + (door - d0).dot(fz) - hw + 0.1)
			B.ribbon("drive", PackedVector2Array([Vector2(d0.x, d0.z), Vector2(d1.x, d1.z)]), 2.8, 0.045)
		# fence along the front boundary with gaps for the path and the driveway
		var fstyle := rng.randi() % 6
		var fkey := "picket_white" if fstyle <= 2 else ("picket_color" if fstyle == 3 else ("brick" if fstyle == 4 else "hedge"))
		if not fence_x.has(fkey):
			fence_x[fkey] = []
		var half := W * 0.5 + 1.2
		var gaps := [[-0.7, 0.7]]
		if drive_side != 0.0:
			var dxl: float = (base.origin + fx * drive_side * drive_x - gate).dot(fx)
			gaps.append([dxl - 1.6, dxl + 1.6])
			half = maxf(half, absf(dxl) + 2.0)
		var u := -half
		while u < half - 0.3:
			var e := minf(u + 2.0, half)
			var blocked := false
			for g in gaps:
				if e > float(g[0]) and u < float(g[1]):
					blocked = true
					e = maxf(float(g[1]), u + 0.2)
					break
			if not blocked and e - u > 0.3:
				var mid := gate + fx * ((u + e) * 0.5)
				if clear_of_buildings(Vector2(mid.x, mid.z), 0.3) and road_clearance(Vector2(mid.x, mid.z)) > 1.0:
					fence_x[fkey].append(Transform3D(Basis(fx * ((e - u) / 2.0), Vector3.UP, fz), mid))
			u = e
		# letterbox beside the gate (street side of the fence)
		var lb := gate + fx * (1.1 if drive_side <= 0.0 else -1.1) + fz * 0.35
		letter_x[rng.randi() % 3].append(Transform3D(Basis(Vector3.UP, atan2(fz.x, fz.z)), lb))
		# back yard: gum tree, Hills Hoist
		var back := base.origin - fz * (float(info.D) * 0.5 + rng.randf_range(3.0, 7.0)) + fx * rng.randf_range(-W * 0.3, W * 0.3)
		if rng.randf() < backyard_tree_chance and clear_of_buildings(Vector2(back.x, back.z), 2.0) and road_clearance(Vector2(back.x, back.z)) > 3.0:
			tree_x[rng.randi() % 3].append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * rng.randf_range(0.75, 1.2)), back))
		var hp := base.origin - fz * (float(info.D) * 0.5 + 2.6) + fx * rng.randf_range(-W * 0.25, W * 0.25)
		if rng.randf() < hoist_chance and clear_of_buildings(Vector2(hp.x, hp.z), 2.2) and road_clearance(Vector2(hp.x, hp.z)) > 3.0:
			hoist_x.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)), hp))
	B.commit(self, false)

	# Street trees on the nature strips + streetlights, walking along every car road.
	var light_flip := 1.0
	for r in town.roads:
		if r.tunnel or String(r.type) == "service":
			continue
		var pts := poly2(r.pts)
		var hw := float(r.width) * 0.5
		var acc := rng.randf_range(0.0, street_tree_spacing)
		var lacc := rng.randf_range(0.0, streetlight_spacing)
		for i in pts.size() - 1:
			var a := pts[i]
			var bb := pts[i + 1]
			var L := a.distance_to(bb)
			if L < 0.01:
				continue
			var d := (bb - a) / L
			var n := Vector2(-d.y, d.x)
			var t := 0.0
			while t < L:
				var step := minf(L - t, street_tree_spacing - acc)
				t += step
				acc += step
				if acc >= street_tree_spacing - 0.01:
					acc = rng.randf_range(-4.0, 4.0)
					for side: float in [1.0, -1.0]:
						var p := a + d * t + n * side * (hw + 0.8)
						if in_extent(p, 10.0) and road_clearance(p) > 0.5 and clear_of_buildings(p, 2.5) and rng.randf() < 0.75:
							var tv := rng.randi() % 3
							var tt := Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * rng.randf_range(0.6, 0.95)), Vector3(p.x, 0, p.y))
							tree_x[tv].append(tt)
							_street_trees.append([tt, Vector3(d.x, 0, d.y), tv])
			t = 0.0
			while t < L:
				var step := minf(L - t, streetlight_spacing - lacc)
				t += step
				lacc += step
				if lacc >= streetlight_spacing - 0.01:
					lacc = 0.0
					light_flip = -light_flip
					var p := a + d * t + n * light_flip * (hw + 0.45)
					if in_extent(p, 5.0) and road_clearance(p) > 0.2 and clear_of_buildings(p, 0.5):
						var toward := -n * light_flip
						var bas := Basis(Vector3(toward.x, 0, toward.y), Vector3.UP, Vector3(toward.x, 0, toward.y).cross(Vector3.UP))
						light_x.append(Transform3D(bas, Vector3(p.x, 0, p.y)))
	# OSM-mapped trees
	for tp in town.trees:
		var p := v2(tp)
		if clear_of_buildings(p, 1.5):
			tree_x[rng.randi() % 3].append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * rng.randf_range(0.8, 1.2)), Vector3(p.x, 0, p.y)))
	# Parks get a few more gums
	for l in town.landuse:
		if not String(l.type) in ["park", "grass", "wood"]:
			continue
		var poly := poly2(l.poly)
		var rect := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			rect = rect.expand(p)
		var want := clampi(int(rect.get_area() / 250.0), 1, 30)
		for k in want * 3:
			if want <= 0:
				break
			var p := rect.position + Vector2(rng.randf() * rect.size.x, rng.randf() * rect.size.y)
			if Geometry2D.is_point_in_polygon(p, poly) and clear_of_buildings(p, 2.0) and road_clearance(p) > 2.0:
				tree_x[rng.randi() % 3].append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * rng.randf_range(0.8, 1.3)), Vector3(p.x, 0, p.y)))
				want -= 1

	if full_collision:
		for v in 3:
			_col_instances("tree", _tpl("tree%d" % v), tree_x[v])
		_col_instances("light", _tpl("light"), light_x)
		_light_list = light_x.duplicate()
		for k in fence_x:
			_col_instances("fence", _tpl("fence_" + k), fence_x[k])
			for f in fence_x[k]:
				_fence_list.append([f, k])
		for v in 3:
			_col_instances("letterbox", _tpl("letterbox"), letter_x[v])
		_col_instances("hoist", _tpl("hoist"), hoist_x)
	var nt := 0
	for v in 3:
		_multimesh(Props.gum_tree(v), tree_x[v], "GumTrees%d" % v, true)
		nt += (tree_x[v] as Array).size()
	stats["trees"] = nt
	_multimesh(Props.streetlight(), light_x, "Streetlights", true)
	var fence_meshes := {"picket_white": Props.fence_panel(0, Color(0.97, 0.96, 0.92)), "picket_color": Props.fence_panel(0, Color(0.3, 0.6, 0.45)),
			"brick": Props.fence_panel(1, Color(0.72, 0.36, 0.22)), "hedge": Props.fence_panel(2, Color(0.2, 0.5, 0.25))}
	for k in fence_x:
		_multimesh(fence_meshes[k], fence_x[k], "Fences_" + k, false)
	var lcol := [Color(0.85, 0.15, 0.12), Color(0.2, 0.45, 0.85), Color(0.95, 0.8, 0.2)]
	for v in 3:
		_multimesh(Props.letterbox(lcol[v]), letter_x[v], "Letterboxes%d" % v, false)
	_multimesh(Props.hills_hoist(), hoist_x, "HillsHoists", false)
	stats["letterboxes"] = (letter_x[0] as Array).size() + (letter_x[1] as Array).size() + (letter_x[2] as Array).size()
	stats["fence_panels"] = 0
	for k in fence_x:
		stats.fence_panels += (fence_x[k] as Array).size()
	# Real lamps under the streetlight heads (no shadows; clustered lighting handles dozens)
	for x in light_x:
		var t: Transform3D = x
		var head := t * Vector3(1.45, 5.25, 0)
		var spot := SpotLight3D.new()
		spot.position = head
		spot.rotation_degrees = Vector3(-90, 0, 0)
		spot.light_color = Color(1.0, 0.72, 0.42)
		spot.light_energy = streetlight_energy
		spot.spot_range = streetlight_range
		spot.spot_angle = 58.0
		spot.spot_angle_attenuation = 1.6
		spot.spot_attenuation = 0.8
		spot.shadow_enabled = false
		spot.light_volumetric_fog_energy = 2.0
		add_child(spot)
		_streetlight_points.append(head)


func _multimesh(mesh: Mesh, xforms: Array, nm: String, shadows: bool) -> void:
	if xforms.is_empty():
		return
	# split into spatial chunks so frustum culling still helps
	var buckets := {}
	for x in xforms:
		var t: Transform3D = x
		var k := Vector2i(floori(t.origin.x / 192.0), floori(t.origin.z / 192.0))
		if not buckets.has(k):
			buckets[k] = []
		buckets[k].append(t)
	for k in buckets:
		var arr: Array = buckets[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "%s_%d_%d" % [nm, k.x, k.y]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


# --- beyond the imported square --------------------------------------------------------------------

## The imported square is only ~550 m across, so the world doesn't stop at its edge: roads that run
## off the map carry on as plain streets, low-detail filler houses (MultiMesh, warm windows and an
## eave glow) fill a ~250 m ring around it, and soft hills ring the horizon. Brisbane extras: the
## lit CBD to the east-south-east and Mt Coot-tha's TV towers (red beacons) to the west.
func _outskirts() -> void:
	var mn := v2(town.extent.min)
	var mx := v2(town.extent.max)
	var x0 := minf(mn.x, mx.x)
	var x1 := maxf(mn.x, mx.x)
	var z0 := minf(mn.y, mx.y)
	var z1 := maxf(mn.y, mx.y)
	var ring := 260.0
	var rng := RandomNumberGenerator.new()
	rng.seed = town_seed + 77
	var B = MeshBatch.new()
	B.chunk_size = 256.0
	B.register("asphalt", GB.patchy(Color(0.25, 0.2, 0.32), Color(0.32, 0.26, 0.4), 0.5, 0.3))
	# 1) extend roads that leave the square
	var ext_segs: Array = []
	for r in town.roads:
		if r.tunnel or String(r.type) == "service":
			continue
		var pts := poly2(r.pts)
		for end in [0, 1]:
			var p: Vector2 = pts[0] if end == 0 else pts[pts.size() - 1]
			var q: Vector2 = pts[1] if end == 0 else pts[pts.size() - 2]
			if p.x > x0 + 3.0 and p.x < x1 - 3.0 and p.y > z0 + 3.0 and p.y < z1 - 3.0:
				continue
			var dir := (p - q).normalized()
			var e := p + dir * ring
			B.set_chunk_at(Vector3(e.x, 0, e.y))
			B.ribbon("asphalt", PackedVector2Array([p, e]), float(r.width), 0.03)
			ext_segs.append([p, e, float(r.width) * 0.5 + 6.0])
	B.commit(self, false)
	# 2) filler houses on a jittered grid in the ring, kept off the extended roads
	var variants: Array = []
	for i in 6:
		variants.append([])
	var step := 17.0
	var gx := x0 - ring
	while gx < x1 + ring:
		var gz := z0 - ring
		while gz < z1 + ring:
			var p := Vector2(gx + rng.randf_range(-4, 4), gz + rng.randf_range(-4, 4))
			gz += step
			if p.x > x0 - 6.0 and p.x < x1 + 6.0 and p.y > z0 - 6.0 and p.y < z1 + 6.0:
				continue
			if rng.randf() < 0.18:
				continue
			var ok := true
			var yaw := 0.0
			var best := 1e9
			for s in ext_segs:
				var cp := Geometry2D.get_closest_point_to_segment(p, s[0], s[1])
				var dd := p.distance_to(cp)
				if dd < float(s[2]):
					ok = false
					break
				if dd < best:
					best = dd
					var dv: Vector2 = (s[1] - s[0])
					yaw = atan2(dv.x, dv.y)
			if not ok:
				continue
			var sc := Vector3(rng.randf_range(0.85, 1.25), rng.randf_range(0.9, 1.2), rng.randf_range(0.85, 1.2))
			var bas := Basis(Vector3.UP, yaw + (PI * 0.5 if rng.randf() < 0.3 else 0.0)).scaled(sc)
			variants[rng.randi() % 6].append(Transform3D(bas, Vector3(p.x, 0, p.y)))
		gx += step
	var walls := [Color(0.98, 0.92, 0.72), Color(0.62, 0.86, 0.78), Color(0.78, 0.38, 0.2), Color(0.6, 0.78, 0.98), Color(0.85, 0.7, 0.95), Color(1.0, 0.86, 0.35)]
	var roofs := [Color(0.72, 0.14, 0.12), Color(0.16, 0.48, 0.32), Color(0.86, 0.4, 0.18), Color(0.2, 0.26, 0.44), Color(0.6, 0.64, 0.7), Color(0.55, 0.22, 0.14)]
	var nf := 0
	for v in 6:
		_multimesh(_filler_mesh(walls[v], roofs[(v * 5 + 1) % 6], v), variants[v], "Filler%d" % v, true)
		if full_collision:
			_col_instances("filler", _tpl("filler%d" % v), variants[v])
		nf += (variants[v] as Array).size()
	stats["filler_houses"] = nf
	# 3) horizon hills + Brisbane landmarks (simple silhouettes, deep in the fog)
	var hill_col := Color(0.16, 0.12, 0.24)
	for i in 26:
		var a := TAU * float(i) / 26.0 + rng.randf_range(-0.08, 0.08)
		var dist := rng.randf_range(1300.0, 1900.0)
		var hr := rng.randf_range(260.0, 520.0)
		GB.sphere(self, hr, Vector3(sin(a) * dist, -hr * 0.72, cos(a) * dist), hill_col.lerp(Color(0.2, 0.2, 0.3), rng.randf()), 0.0, Vector3(1.6, 1.0, 1.2))
		if full_collision:
			_ellipsoid_body(Vector3(sin(a) * dist, -hr * 0.72, cos(a) * dist), hr * Vector3(1.6, 1.0, 1.2))
	# Mt Coot-tha (west) with three TV towers and blinking-red beacons
	var coot := Vector3(-2400, 0, -150)
	GB.sphere(self, 900.0, coot + Vector3(0, -560, 0), Color(0.13, 0.1, 0.2), 0.0, Vector3(1.4, 1.0, 1.0))
	if full_collision:
		_ellipsoid_body(coot + Vector3(0, -560, 0), 900.0 * Vector3(1.4, 1.0, 1.0))
	for k in 3:
		var tp := coot + Vector3(-80 + k * 85, 330, -40 + k * 30)
		GB.cylinder(self, 1.5, 4.0, 120.0 + k * 20.0, tp + Vector3(0, 60 + k * 10, 0), Color(0.5, 0.48, 0.55), Vector3.ZERO, 0.0, 6)
		GB.sphere(self, 4.0, tp + Vector3(0, 124 + k * 20, 0), Color(1.0, 0.1, 0.05), 6.0)
	# CBD skyline (east-south-east)
	var cbd := Vector3(2300, 0, 900)
	for k in 26:
		var bp := cbd + Vector3(rng.randf_range(-260, 260), 0, rng.randf_range(-220, 220))
		var bh := rng.randf_range(40.0, 190.0)
		var bw := rng.randf_range(25.0, 50.0)
		var brot := rng.randf_range(0, 90)
		GB.box(self, Vector3(bw, bh, bw), bp + Vector3(0, bh * 0.5, 0), Color(0.18, 0.16, 0.3), Vector3(0, brot, 0))
		if full_collision:
			_box_body(Transform3D(Basis(Vector3.UP, deg_to_rad(brot)), bp + Vector3(0, bh * 0.5, 0)), Vector3(bw, bh, bw), "far")
		for wv in int(bh / 22.0):
			GB.box(self, Vector3(bw + 0.6, 2.0, bw + 0.6), bp + Vector3(0, 10.0 + wv * 22.0, 0), Color(1.0, 0.75, 0.4), Vector3.ZERO, 1.2)


func _filler_mesh(wall: Color, roof: Color, v: int) -> ArrayMesh:
	var b = MeshBatch.new()
	b.register("w", GB.mat(wall))
	b.register("r", GB.patchy(roof, roof.lightened(0.18), 0.45, 0.35))
	b.register("g", GB.mat(Color(1.0, 0.68, 0.32), 1.6))
	b.register("l", GB.mat(Color(1.0, 0.8, 0.5), 2.4))
	b.no_shadow["g"] = true
	b.no_shadow["l"] = true
	var W := 10.0
	var D := 12.0
	var fy := 1.8 if v % 2 == 0 else 0.4
	var wh := 2.8
	b.abox("w", Vector3(0, (fy + wh) * 0.5, 0), Vector3(W, fy + wh, D))
	var y := fy + wh
	var ex := W * 0.5 + 0.5
	var ez := D * 0.5 + 0.5
	var r := 3.4
	var ty := y + r * 0.6
	var e := [Vector3(-ex, y, -ez), Vector3(ex, y, -ez), Vector3(ex, y, ez), Vector3(-ex, y, ez)]
	var t := [Vector3(-ex + r, ty, -ez + r), Vector3(ex - r, ty, -ez + r), Vector3(ex - r, ty, ez - r), Vector3(-ex + r, ty, ez - r)]
	var hints := [Vector3(0, 1, -1), Vector3(1, 1, 0), Vector3(0, 1, 1), Vector3(-1, 1, 0)]
	for i in 4:
		b.quad("r", e[i], e[(i + 1) % 4], t[(i + 1) % 4], t[i], hints[i])
	b.quad("r", t[0], t[1], t[2], t[3], Vector3.UP)
	b.quad("w", e[0], e[1], e[2], e[3], Vector3.DOWN)
	for i in 4:
		b.beam("l", e[i] + Vector3(0, -0.1, 0), e[(i + 1) % 4] + Vector3(0, -0.1, 0), 0.12, 0.12)
	for k in 3:
		b.abox("g", Vector3(-3.0 + k * 3.0, fy + 1.5, D * 0.5 + 0.03), Vector3(1.1, 1.3, 0.06))
		b.abox("g", Vector3(-3.0 + k * 3.0, fy + 1.5, -D * 0.5 - 0.03), Vector3(1.1, 1.3, 0.06))
	return b.to_array_mesh()


# --- launch pad + player ------------------------------------------------------------------------------

func _launch_pad() -> void:
	# The workshop's launch tower: the most open spot near the middle (raised, so the reindeer
	# runway never clips a roof). Reindeer runway extends north (-Z) on the visual-only layer 2.
	var best := Vector2.ZERO
	var best_s := -1e9
	for gx in range(-30, 31):
		for gy in range(-30, 31):
			var p := Vector2(gx * 4.0, gy * 4.0)
			var clear := 0.0
			for m in [6.0, 4.0, 2.5, 1.0]:
				if clear_of_buildings(p, m) and clear_of_buildings(p + Vector2(0, -12), m * 0.5):
					clear = m
					break
			var rc := road_clearance(p)
			var s := clear * 2.0 + minf(rc, 6.0) - p.length() * 0.03
			if rc < 5.0:  # keep the tower legs off the street
				s -= 20.0
			if s > best_s:
				best_s = s
				best = p
	var h := launch_pad_height
	pad_top = Vector3(best.x, h, best.y)
	var pad := StaticBody3D.new()
	pad.name = "LaunchPad"
	pad.add_to_group("pad")
	pad.set_meta("surface_name", "Launch pad")
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(8, 1.0, 8)
	cs.shape = sh
	pad.add_child(cs)
	pad.position = pad_top - Vector3(0, 0.5, 0)
	add_child(pad)
	GB.box(pad, sh.size, Vector3.ZERO, Color(0.6, 0.34, 0.18))
	for i in 8:
		GB.box(pad, Vector3(7.9, 0.06, 0.85), Vector3(0, 0.51, -3.5 + i), Color(0.72, 0.42, 0.2).lightened(0.08 * (i % 2)))
	var leg := Color(0.95, 0.1, 0.1)
	for c in [Vector3(-3.6, 0, -3.6), Vector3(3.6, 0, -3.6), Vector3(-3.6, 0, 3.6), Vector3(3.6, 0, 3.6)]:
		if full_collision:
			_box_body(Transform3D(Basis(), pad_top + c + Vector3(0, -h * 0.5 - 0.5, 0)), Vector3(0.5, h - 1.0, 0.5), "tower")
		var n := int(h / 1.2)
		for k in n:
			GB.cylinder(self, 0.22, 0.26, 1.2, pad_top + c + Vector3(0, -h + 0.6 + k * 1.2, 0), leg if k % 2 == 0 else Color(0.98, 0.95, 0.9))
	var ls := LightString.new()
	add_child(ls)
	var y := h + 0.05
	ls.setup(PackedVector3Array([pad_top + Vector3(-4, 0.05, 4), pad_top + Vector3(4, 0.05, 4), pad_top + Vector3(4, 0.05, -4), pad_top + Vector3(-4, 0.05, -4), pad_top + Vector3(-4, 0.05, 4)]), Color(1.0, 0.6, 0.05))
	GB.omni(self, pad_top + Vector3(0, 2.5, 3), Color(1.0, 0.7, 0.35), 1.2, 10.0)
	var runway := StaticBody3D.new()
	runway.collision_layer = 2
	runway.collision_mask = 0
	var rcs := CollisionShape3D.new()
	var rsh := BoxShape3D.new()
	rsh.size = Vector3(4.6, 1.0, 16.0)
	rcs.shape = rsh
	runway.add_child(rcs)
	runway.position = pad_top + Vector3(0, -0.5, -12.0)
	add_child(runway)
	GB.box(runway, rsh.size, Vector3.ZERO, Color(0.55, 0.3, 0.16))
	var rl := LightString.new()
	add_child(rl)
	rl.setup(PackedVector3Array([pad_top + Vector3(-2.3, 0.05, -4), pad_top + Vector3(-2.3, 0.05, -20), pad_top + Vector3(2.3, 0.05, -20), pad_top + Vector3(2.3, 0.05, -4)]), Color(0.1, 1.0, 0.25))
	stats["pad"] = pad_top
	stats["pad_y"] = y


func _spawn_player() -> void:
	sleigh = SleighScene.instantiate() as RigidBody3D
	sleigh.position = pad_top + Vector3(0, 0.75, 0)
	add_child(sleigh)
	team = Node3D.new()
	team.name = "ReindeerTeam"
	team.set_script(TeamScript)
	team.set("sleigh", sleigh)
	add_child(team)
	camera = Camera3D.new()
	camera.name = "ChaseCamera"
	camera.far = 4000.0
	camera.set_script(CamScript)
	camera.set("target", sleigh)
	add_child(camera)
	hud = CanvasLayer.new()
	hud.set_script(HudScript)
	add_child(hud)
	sleigh.connect("touchdown", _on_touchdown)
	sleigh.connect("crashed", _on_crashed)
	sleigh.connect("reset_done", _on_reset)
	camera.call("snap")
	_spawn_present()


func _ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var l := Label.new()
	l.text = "Map data %s (ODbL)  ·  %s" % [String(town.get("attribution", "© OpenStreetMap contributors")), String(town.get("display_name", ""))]
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.modulate = Color(1, 1, 1, 0.85)
	l.anchor_left = 1.0
	l.anchor_right = 1.0
	l.anchor_top = 1.0
	l.anchor_bottom = 1.0
	l.offset_left = -560.0
	l.offset_right = -14.0
	l.offset_top = -62.0
	l.offset_bottom = -40.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.name = "OSMAttribution"
	layer.add_child(l)
	hud.call("flash", "%s: land on the decks with the floating stars!" % String(town.get("display_name", "Town")), Color(1, 0.95, 0.8), 6.0)


# --- input + gameplay -------------------------------------------------------------------------------

func _setup_input() -> void:
	_bind("thrust_fwd", [KEY_W], [[JOY_AXIS_LEFT_Y, -1.0]])
	_bind("thrust_back", [KEY_S], [[JOY_AXIS_LEFT_Y, 1.0]])
	_bind("yaw_left", [KEY_A], [[JOY_AXIS_LEFT_X, -1.0]])
	_bind("yaw_right", [KEY_D], [[JOY_AXIS_LEFT_X, 1.0]])
	_bind("pitch_down", [KEY_UP], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_bind("pitch_up", [KEY_DOWN], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_bind("lift", [KEY_SPACE], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_bind("brake", [KEY_SHIFT], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_bind("drop_present", [KEY_E], [], [JOY_BUTTON_A])
	_bind("restart", [KEY_R], [], [JOY_BUTTON_START])
	_bind("camera", [KEY_V], [], [JOY_BUTTON_Y])
	_bind("town_collision_debug", [KEY_C], [], [JOY_BUTTON_BACK])


func _bind(action: StringName, keys: Array, axes: Array, buttons: Array = []) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for ax in axes:
		var j := InputEventJoypadMotion.new()
		j.axis = ax[0]
		j.axis_value = ax[1]
		InputMap.action_add_event(action, j)
	for btn in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = btn
		InputMap.action_add_event(action, jb)


func _process(delta: float) -> void:
	if sleigh == null:
		return
	_t += delta
	for i in _marker_nodes.size():
		var s: Node3D = _marker_nodes[i]
		s.rotation.y = _t * 1.2 + i
		s.position.y += sin(_t * 2.0 + i) * 0.004
	if Input.is_action_just_pressed("restart"):
		sleigh.call("request_reset")
	if Input.is_action_just_pressed("camera"):
		camera.call("toggle_mode")
	if Input.is_action_just_pressed("drop_present"):
		_drop_present()
	if Input.is_action_just_pressed("town_collision_debug"):
		toggle_collision_debug()
	var v := sleigh.linear_velocity
	var lines := PackedStringArray()
	lines.append("SPEED      %5.1f m/s   VERT %+5.1f" % [v.length(), v.y])
	lines.append("ALTITUDE   %5.1f m   TILT %3.0f°" % [sleigh.global_position.y, float(sleigh.get("tilt_deg"))])
	lines.append("STATUS     %s" % sleigh.call("status_text"))
	lines.append("LAST       %s" % last_landing)
	var done := 0
	var nearest = null
	var nd := 1e9
	for d in deliveries:
		if d.done:
			done += 1
			continue
		var dd := sleigh.global_position.distance_to(d.deck_centre)
		if dd < nd:
			nd = dd
			nearest = d
	lines.append("DELIVERED  %d / %d houses   presents %d (broken %d)" % [done, deliveries.size(), presents_delivered, presents_broken])
	if nearest != null:
		var to: Vector3 = nearest.deck_centre - sleigh.global_position
		var heading := rad_to_deg(atan2(to.x, -to.z))
		var dirs := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
		lines.append("NEXT       %s  (%s deck)  %d m %s" % [nearest.addr, nearest.type, int(nd), dirs[int(round(fposmod(heading, 360.0) / 45.0)) % 8]])
	hud.call("set_stats", "\n".join(lines))


func _on_touchdown(r: Dictionary) -> void:
	var detail := "(vert %.1f, horiz %.1f m/s, tilt %.0f°)" % [r.vs, r.hs, r.tilt]
	print("[landing] %s %s stars=%d crash=%s %s" % [r.surface, detail, r.stars, r.crash, r.reason])
	if r.crash:
		last_landing = "CRASH on %s" % r.surface
		return
	if int(r.stars) == 0:
		return
	var stars := STAR.repeat(int(r.stars)) + NO_STAR.repeat(3 - int(r.stars))
	last_landing = "%s  %s" % [stars, r.surface]
	for d in deliveries:
		if String(r.surface).begins_with(String(d.addr) + " · ") and String(r.surface).ends_with("deck"):
			if not d.done:
				d.done = true
				d.stars = int(r.stars)
				(d.star as Node3D).visible = false
				hud.call("flash", "%s  Landed at %s!" % [stars, d.addr], Color(0.5, 1, 0.5), 3.0)
				return
	hud.call("flash", "%s  %s" % [stars, r.surface], Color(1, 0.9, 0.3), 2.5)


func _on_crashed(reason: String) -> void:
	# The sleigh's own crash rules decide THAT it crashed; we just name WHAT it hit.
	var what := ""
	for body in sleigh.get_colliding_bodies():
		if body.has_meta("what"):
			what = String(body.get_meta("what"))
			break
	_crash_log.append([reason, what, Time.get_ticks_msec()])
	var msg := reason
	if what != "" and reason.begins_with("Smashed"):
		msg = "Smashed into %s!" % what
	print("[crash] %s" % msg)
	hud.call("flash", "CRASH!  %s" % msg, Color(1, 0.3, 0.25), 2.5)


func _on_reset() -> void:
	for p in all_presents.duplicate():
		if is_instance_valid(p) and int(p.get("state")) == 1:
			_forget(p)
	_spawn_present()
	camera.call("snap")


func _spawn_present() -> void:
	if current_present != null:
		return
	var p := PresentScene.instantiate() as RigidBody3D
	add_child(p)
	p.call("carry", sleigh)
	p.global_transform = sleigh.call("get_carry_transform")
	p.connect("broken", _on_present_broken)
	p.connect("delivered", _on_present_delivered)
	p.connect("lost", _on_present_lost)
	current_present = p
	all_presents.append(p)


func _on_present_broken(pr: RigidBody3D) -> void:
	presents_broken += 1
	hud.call("flash", "Present smashed in the yard!", Color(1, 0.4, 0.3), 2.0)
	_forget(pr)
	_later_present(1.0)


func _on_present_delivered(_pr: RigidBody3D) -> void:
	presents_delivered += 1
	hud.call("flash", "Present delivered!", Color(0.5, 1, 0.5), 2.0)
	_later_present(0.6)


func _on_present_lost(pr: RigidBody3D) -> void:
	_forget(pr)
	_later_present(0.5)


func _later_present(s: float) -> void:
	await get_tree().create_timer(s).timeout
	_spawn_present()


func _forget(p: RigidBody3D) -> void:
	all_presents.erase(p)
	if p == current_present:
		current_present = null
	p.queue_free()


func _drop_present() -> void:
	if current_present == null:
		return
	var at: Transform3D = sleigh.call("get_set_down_transform") if bool(sleigh.get("grounded")) else sleigh.call("get_carry_transform")
	current_present.call("release", sleigh.linear_velocity, at)
	current_present = null


# --- scripted checks ----------------------------------------------------------------------------------

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _selftest() -> void:
	await _wait(1.0)
	var results := []
	for i in mini(deliveries.size(), 4):
		var d: Dictionary = deliveries[i]
		var b: Basis = d.basis
		var ds: Vector2 = d.deck_size
		var axis: Vector3 = b.x if ds.x > ds.y else b.z
		var xf := Transform3D(Basis(Vector3.UP, atan2(-axis.x, -axis.z)), d.deck_centre + Vector3(0, 0.82, 0))
		print("[townselftest] gentle drop onto %s (%s deck)" % [d.addr, d.type])
		sleigh.call("teleport", xf, Vector3(0, -0.5, 0))
		await _wait(3.0)
		results.append([d.addr, d.type, last_landing, d.done])
	# A fast slam onto a deck must crash
	var d0: Dictionary = deliveries[0]
	print("[townselftest] slam onto %s" % d0.addr)
	sleigh.call("teleport", Transform3D(Basis(), d0.deck_centre + Vector3(0, 4.0, 0)), Vector3(0, -9.0, 0))
	await _wait(2.5)
	# A roof slope: scored as a touchdown, but there's no grip, so the sleigh slides off
	for d in deliveries:
		var sl: Array = d.info.get("slopes", [])
		if String(d.type) == "ridge" and not sl.is_empty():
			var q: PackedVector3Array = sl[0]
			var sc := (q[0] + q[1] + q[2] + q[3]) * 0.25
			print("[townselftest] drop onto the roof slope of %s" % d.addr)
			sleigh.call("teleport", Transform3D(Basis(), sc + Vector3(0, 1.3, 0)), Vector3(0, -0.5, 0))
			await _wait(4.0)
			break
	# Background roof: no score
	var bg: Dictionary = {}
	for info in house_infos:
		if not info.get("delivery", false) and String(info.style) == "queenslander" and info.has("deck_world"):
			bg = info
			break
	if not bg.is_empty():
		var dw: PackedVector3Array = bg.deck_world
		var c := (dw[0] + dw[2]) * 0.5
		print("[townselftest] drop onto a background roof at %s" % String(bg.b.addr))
		sleigh.call("teleport", Transform3D(Basis(), c + Vector3(0, 1.4, 0)), Vector3(0, -1.0, 0))
		await _wait(2.5)
	sleigh.call("request_reset")
	await _wait(2.0)
	var ok := 0
	for r in results:
		print("[townselftest] %s (%s): %s  delivered=%s" % r)
		if r[3]:
			ok += 1
	print("[townselftest] sleigh back on the launch pad: %s, status %s" % [sleigh.global_position.distance_to(pad_top) < 3.0, sleigh.call("status_text")])
	print("[townselftest] RESULT %d/%d delivery decks scored" % [ok, results.size()])
	get_tree().quit()


func _fps_lap() -> void:
	await _wait(2.0)
	camera.set("locked", true)
	var mn := v2(town.extent.min)
	var mx := v2(town.extent.max)
	var samples: Array[float] = []
	var frames := 0
	var t0 := Time.get_ticks_usec()
	var total := 12.0
	var t := 0.0
	while t < total:
		var a := t / total * TAU
		var p := Vector3(cos(a) * 160.0, 28.0, sin(a) * 160.0)
		camera.look_at_from_position(p, Vector3(cos(a + 0.6) * 60.0, 2.0, sin(a + 0.6) * 60.0), Vector3.UP)
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		frames += 1
		samples.append(Engine.get_frames_per_second())
	var el := (Time.get_ticks_usec() - t0) / 1e6
	samples.sort()
	print("[townfps] flying lap: avg %.1f fps (%d frames in %.1f s), median %.0f, 5%% low %.0f" % [frames / el, frames, el, samples[samples.size() / 2], samples[int(samples.size() * 0.05)]])
	# street level
	var d: Dictionary = deliveries[0] if not deliveries.is_empty() else {}
	frames = 0
	t0 = Time.get_ticks_usec()
	while (Time.get_ticks_usec() - t0) < 4000000:
		if not d.is_empty():
			var b: Dictionary = d.info.b
			var rp := v3(b.road_pt, 1.7)
			camera.look_at_from_position(rp + (rp - Vector3(d.deck_centre.x, 1.7, d.deck_centre.z)).normalized() * 3.0, d.deck_centre, Vector3.UP)
		await get_tree().process_frame
		frames += 1
	print("[townfps] street level: avg %.1f fps" % (frames / ((Time.get_ticks_usec() - t0) / 1e6)))
	print("[townfps] draw calls %d, primitives %d, objects %d" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
	get_tree().quit()


func _shot(dir: String, fname: String) -> void:
	await _wait(0.5)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(fname)
	img.save_png(path)
	print("[townshots] saved %s" % path)


func _shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await _wait(2.5)
	camera.set("locked", true)
	hud.visible = false
	# 1) top-down orthographic, north up, framed on the imported square
	var mn := v2(town.extent.min)
	var mx := v2(town.extent.max)
	var c := Vector3((mn.x + mx.x) * 0.5, 0, (mn.y + mx.y) * 0.5)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = absf(mx.y - mn.y)
	camera.near = 1.0
	camera.far = 1200.0
	camera.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), c + Vector3(0, 500, 0))
	world_env.volumetric_fog_enabled = false
	world_env.fog_enabled = false
	await _wait(0.6)
	await _shot(dir, "town_topdown.png")
	world_env.volumetric_fog_enabled = volumetric_fog
	world_env.fog_enabled = true
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 70.0
	camera.near = 0.05
	camera.far = 4000.0
	# 2) street level, looking up the street at a delivery house
	var d: Dictionary = deliveries[0]
	var b: Dictionary = d.info.b
	var rp := v3(b.road_pt, 1.6)
	var to_house := Vector3(d.deck_centre.x, 1.6, d.deck_centre.z) - rp
	var side := to_house.normalized().cross(Vector3.UP)
	var eye := rp - side * 9.0 - to_house.normalized() * 1.5
	camera.look_at_from_position(eye, Vector3(d.deck_centre.x, float(d.info.deck_y) * 0.55, d.deck_centre.z) + side * 4.0, Vector3.UP)
	await _wait(0.8)
	await _shot(dir, "town_street.png")
	# 3) flying: sleigh cruising in over the rooftops toward the most central delivery deck, chase cam
	camera.set("locked", false)
	var d2: Dictionary = deliveries[0]
	for dd in deliveries:
		if Vector2(dd.deck_centre.x, dd.deck_centre.z).length() < Vector2(d2.deck_centre.x, d2.deck_centre.z).length():
			d2 = dd
	var target: Vector3 = d2.deck_centre
	var out_dir := Vector3(target.x - c.x, 0, target.z - c.z)
	out_dir = out_dir.normalized() if out_dir.length() > 1.0 else Vector3(0, 0, 1)
	var start := target + out_dir * 42.0 + Vector3(8, 16, 0)
	var fwd := (target - start)
	fwd.y = 0
	fwd = fwd.normalized()
	sleigh.call("teleport", Transform3D(Basis.looking_at(fwd, Vector3.UP), start), fwd * 9.0)
	await _wait(0.25)
	camera.call("snap")
	await _wait(1.6)
	await _shot(dir, "town_fly.png")
	camera.set("locked", true)
	var hi := target + out_dir * 75.0 + Vector3(0, 48, 0)
	camera.look_at_from_position(hi, target, Vector3.UP)
	await _wait(0.8)
	await _shot(dir, "town_overview.png")
	get_tree().quit()


# --- collision ----------------------------------------------------------------------------------------
## Everything solid is merged into one double-sided trimesh (ConcavePolygonShape3D) per
## (category, 96 m chunk): ~100 static bodies for the whole town instead of thousands of nodes.
## Shapes come from the same procedural geometry as the visuals (houses), or from a simplified
## template per prop (trunk + canopy blob, pole + arm, fence panel...) transformed per instance.
## Only the sleigh collides with them; the reindeer have no bodies (their foot rays may rest on them).

func _take_faces(batch) -> void:
	for e in batch.faces_by_chunk():
		_add_faces(String(e.key), e.chunk, e.faces)


func _add_faces(cat: String, chunk: Vector2i, faces: PackedVector3Array) -> void:
	var k := "%s|%d,%d" % [cat, chunk.x, chunk.y]
	var arr: PackedVector3Array = _col_faces.get(k, PackedVector3Array())
	arr.append_array(faces)
	_col_faces[k] = arr  # packed arrays are values: write back


func _col_instances(cat: String, tpl: PackedVector3Array, xforms: Array) -> void:
	for x in xforms:
		var t: Transform3D = x
		var c := Vector2i(floori(t.origin.x / collision_chunk), floori(t.origin.z / collision_chunk))
		var k := "%s|%d,%d" % [cat, c.x, c.y]
		var arr: PackedVector3Array = _col_faces.get(k, PackedVector3Array())
		arr.append_array(t * tpl)
		_col_faces[k] = arr


## Simplified collision templates (local space, same frames as the prop meshes).
func _tpl(name_: String) -> PackedVector3Array:
	if _col_templates.has(name_):
		return _col_templates[name_]
	var b = MeshBatch.new()
	b.chunk_size = 1e6
	b.register("c", null)
	if name_.begins_with("tree"):
		var v := int(name_.substr(4))
		var rng := RandomNumberGenerator.new()
		rng.seed = 900 + v  # same lean as town_props.gum_tree()
		var h := 6.5 + v * 0.7
		var lean := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.4, 0.4))
		b.cylinder("c", Vector3.ZERO, 0.42, 0.26, h * 0.55, 6, lean)
		var mid := Vector3.UP * h * 0.55 + lean
		b.cylinder("c", mid, 0.26, 0.14, h * 0.4, 6, -lean * 1.2 + Vector3(0.2, 0, 0))
		b.sphere("c", Vector3(0, h + 0.35, 0) + lean * 0.3, 2.6, Vector3(1.1, 0.75, 1.1), 3, 7)
	elif name_ == "light":
		b.cylinder("c", Vector3.ZERO, 0.12, 0.09, 5.6, 6)
		b.beam("c", Vector3(0, 5.5, 0), Vector3(1.6, 5.62, 0), 0.12, 0.12)
		b.abox("c", Vector3(1.45, 5.42, 0), Vector3(0.62, 0.28, 0.34), 0.0, false)
	elif name_ == "fence_picket_white" or name_ == "fence_picket_color":
		b.abox("c", Vector3(0, 0.55, 0), Vector3(2.0, 1.1, 0.14), 0.0, false)
	elif name_ == "fence_brick":
		b.abox("c", Vector3(0, 0.45, 0), Vector3(2.0, 0.9, 0.34), 0.0, false)
	elif name_ == "fence_hedge":
		b.abox("c", Vector3(0, 0.6, 0), Vector3(2.0, 1.15, 0.95), 0.0, false)
	elif name_ == "letterbox":
		b.abox("c", Vector3(0, 0.5, 0), Vector3(0.14, 1.0, 0.14), 0.0, false)
		b.abox("c", Vector3(0, 1.15, -0.05), Vector3(0.4, 0.42, 0.62), 0.0, false)
	elif name_ == "hoist":
		b.cylinder("c", Vector3.ZERO, 0.06, 0.06, 2.1, 6)
		for i in 4:
			var a := TAU * i / 4.0 + 0.4
			b.beam("c", Vector3(0, 2.05, 0), Vector3(cos(a) * 2.0, 1.8, sin(a) * 2.0), 0.08, 0.08)
	elif name_.begins_with("filler"):
		var v := int(name_.substr(6))
		var fy := 1.8 if v % 2 == 0 else 0.4
		var y := fy + 2.8
		b.abox("c", Vector3(0, y * 0.5, 0), Vector3(10.0, y, 12.0), 0.0, false)
		var ex := 5.5
		var ez := 6.5
		var r := 3.4
		var ty := y + r * 0.6
		var e := [Vector3(-ex, y, -ez), Vector3(ex, y, -ez), Vector3(ex, y, ez), Vector3(-ex, y, ez)]
		var t := [Vector3(-ex + r, ty, -ez + r), Vector3(ex - r, ty, -ez + r), Vector3(ex - r, ty, ez - r), Vector3(-ex + r, ty, ez - r)]
		var hints := [Vector3(0, 1, -1), Vector3(1, 1, 0), Vector3(0, 1, 1), Vector3(-1, 1, 0)]
		for i in 4:
			b.quad("c", e[i], e[(i + 1) % 4], t[(i + 1) % 4], t[i], hints[i])
		b.quad("c", t[0], t[1], t[2], t[3], Vector3.UP)
		b.quad("c", e[0], e[1], e[2], e[3], Vector3.DOWN)
	var f: PackedVector3Array = b.faces_all()
	_col_templates[name_] = f
	return f


func _ellipsoid_body(c: Vector3, radii: Vector3) -> void:
	var pts := PackedVector3Array()
	for i in range(0, 7):
		var th := PI * float(i) / 6.0
		for j in 12:
			var ph := TAU * float(j) / 12.0
			pts.append(c + Vector3(sin(th) * cos(ph) * radii.x, cos(th) * radii.y, sin(th) * sin(ph) * radii.z))
	var sh := ConvexPolygonShape3D.new()
	sh.points = pts
	_shape_body(sh, Transform3D.IDENTITY, "far")


func _box_body(xf: Transform3D, size: Vector3, cat: String) -> void:
	var sh := BoxShape3D.new()
	sh.size = size
	_shape_body(sh, xf, cat)


func _shape_body(sh: Shape3D, xf: Transform3D, cat: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Col_%s_%d" % [cat, _col_bodies.size()]
	var info: Array = COL_INFO.get(cat, COL_INFO.house)
	body.set_meta("surface_name", info[0])
	body.set_meta("what", info[1])
	var cs := CollisionShape3D.new()
	cs.shape = sh
	body.add_child(cs)
	add_child(body)
	body.global_transform = xf
	_col_bodies.append([body, cat])
	return body


func _build_collision() -> void:
	var t0 := Time.get_ticks_msec()
	var tris := 0
	var root := Node3D.new()
	root.name = "Collision"
	add_child(root)
	for k in _col_faces:
		var faces: PackedVector3Array = _col_faces[k]
		if faces.size() < 3:
			continue
		var cat := (k as String).get_slice("|", 0)
		var body := StaticBody3D.new()
		body.name = "Col_" + (k as String).replace("|", "_").replace(",", "_")
		var info: Array = COL_INFO.get(cat, COL_INFO.house)
		body.set_meta("surface_name", info[0])
		body.set_meta("what", info[1])
		var cs := CollisionShape3D.new()
		var sh := ConcavePolygonShape3D.new()
		sh.backface_collision = true  # double-sided: nothing can be entered from behind a face
		sh.set_faces(faces)
		cs.shape = sh
		body.add_child(cs)
		root.add_child(body)
		_col_bodies.append([body, cat])
		tris += faces.size() / 3
	_col_faces.clear()
	stats["col_bodies"] = _col_bodies.size()
	stats["col_tris"] = tris
	print("[town] collision: %d static bodies, %d triangles, built in %d ms%s" % [_col_bodies.size(), tris, Time.get_ticks_msec() - t0,
			"" if full_collision else " (--nocollide: simple hulls only)"])


func toggle_collision_debug() -> void:
	if _debug_root == null:
		_debug_root = Node3D.new()
		_debug_root.name = "CollisionDebug"
		add_child(_debug_root)
		var mats := {}
		for e in _col_bodies:
			var body: StaticBody3D = e[0]
			if not is_instance_valid(body):
				continue
			var cat: String = e[1]
			if not mats.has(cat):
				var m := StandardMaterial3D.new()
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				var cc: Color = (COL_INFO.get(cat, COL_INFO.house) as Array)[2]
				cc.a = 0.42
				m.albedo_color = cc
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.render_priority = 1
				mats[cat] = m
			for cs in body.get_children():
				if cs is CollisionShape3D and (cs as CollisionShape3D).shape != null:
					var mi := MeshInstance3D.new()
					mi.mesh = (cs as CollisionShape3D).shape.get_debug_mesh()
					mi.material_override = mats[cat]
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					_debug_root.add_child(mi)
					mi.global_transform = (cs as CollisionShape3D).global_transform
		_debug_root.visible = false
	_debug_root.visible = not _debug_root.visible
	hud.call("flash", "Collision shapes: %s" % ("ON" if _debug_root.visible else "OFF"), Color(0.8, 0.9, 1.0), 1.5)


# --- collision checks (--towncollide) -------------------------------------------------------------------

## Fly the sleigh straight at something. Returns [crashed, what, max progress past the target point].
func _ram(label: String, target: Vector3, dir: Vector3, speed: float, start_dist: float, window := 1.0) -> Array:
	dir.y = 0.0
	dir = dir.normalized()
	var start := target - dir * start_dist
	_crash_log.clear()
	sleigh.call("teleport", Transform3D(Basis.looking_at(dir, Vector3.UP), start), dir * speed)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var t0 := Time.get_ticks_msec()
	var max_prog := -1e9
	var min_speed_along := 1e9
	var first_touch := ""
	var steps := int(window * 60.0)
	for i in steps:
		await get_tree().physics_frame
		var prog := (sleigh.global_position - target).dot(dir)
		max_prog = maxf(max_prog, prog)
		min_speed_along = minf(min_speed_along, sleigh.linear_velocity.dot(dir))
		if OS.is_debug_build() and first_touch == "":
			for bd in sleigh.get_colliding_bodies():
				first_touch = "%s/%s @%.2f y%.2f" % [bd.name, bd.get_meta("what", "?"), prog, sleigh.global_position.y]
	var crashed := not _crash_log.is_empty()
	var what: String = _crash_log[0][1] if crashed else ""
	var reason: String = _crash_log[0][0] if crashed else ""
	if crashed and what != "" and reason.begins_with("Smashed"):
		reason = "Smashed into %s!" % what
		what = ""
	print("[towncollide] %-34s %4.0f m/s -> %s%s | furthest point: %+.2f m from the target | lowest forward speed %+.1f m/s" % [
			label, speed, ("CRASH: " + reason) if crashed else "no crash", (" (hit %s)" % what) if what != "" else "", max_prog, min_speed_along])
	print("[towncollide]     first touch: ", first_touch)
	sleigh.call("request_reset")
	await _wait(0.4)
	return [crashed, what, max_prog, min_speed_along]


func _collide_check() -> void:
	await _wait(1.0)
	var results: Array = []
	# 1) house walls: a plain single-storey brick house (no verandah), straight into the front wall
	var wall_pt := Vector3.ZERO
	var fz := Vector3.BACK
	var found := false
	for info in house_infos:
		if found:
			break
		if String(info.style) in ["brick", "fibro", "modern"] and not info.get("delivery", false) and float(info.W) > 8.0:
			var base: Transform3D = info.base
			# side walls (no verandah, no front-yard clutter): try both
			for sx: float in [1.0, -1.0]:
				var p := base * Vector3(sx * (float(info.W) * 0.5 - 0.3), float(info.floor_y) + 2.0, 0.0)
				var into := -(base.basis.x * sx)
				if _clear_path(p, into, 9.0, "a house"):
					wall_pt = p
					fz = -into
					found = true
					break
	print("[towncollide] wall target found: %s at %s" % [found, wall_pt])
	var r := await _ram("house wall (fast)", wall_pt, -fz, 25.0, 7.0)
	results.append(["house wall, fast -> crash", r[0] and r[2] < 0.0])
	r = await _ram("house wall (max speed)", wall_pt, -fz, 28.0, 7.5)
	results.append(["house wall, 28 m/s -> crash, no tunnelling", r[0] and r[2] < 0.0])
	r = await _ram("house wall (40 m/s, overspeed)", wall_pt, -fz, 40.0, 7.5)
	results.append(["house wall, 40 m/s -> crash, no tunnelling", r[0] and r[2] < 0.0])
	r = await _ram("house wall (soft brush)", wall_pt, -fz, 3.0, 2.2, 0.35)
	results.append(["house wall, 3 m/s -> bump, no crash", (not r[0]) and r[2] < 0.0])
	# 2) a street gum tree trunk, along the nature strip
	var tr: Array = _street_trees[0]
	for x in _street_trees:
		if _clear_path((x[0] as Transform3D).origin + Vector3(0, 1.6, 0), x[1], 9.0, "a gum tree"):
			tr = x
			break
	var tt: Transform3D = tr[0]
	r = await _ram("gum tree trunk", tt.origin + Vector3(0, 1.6, 0), tr[1], 25.0, 7.0)
	results.append(["gum tree, fast -> crash", r[0] and r[2] < 0.5])
	r = await _ram("gum tree canopy", tt.origin + Vector3(0, (6.5 + int(tr[2]) * 0.7) * tt.basis.get_scale().y + 0.3, 0), tr[1], 25.0, 9.0)
	results.append(["gum tree canopy, fast -> crash", r[0] and r[2] < 2.0])
	# 3) a streetlight pole, along the road
	var lp: Transform3D = _light_list[0]
	for x in _light_list:
		var lx: Transform3D = x
		if _clear_path(lx.origin + Vector3(0, 3.0, 0), lx.basis.z, 9.0, "a streetlight"):
			lp = lx
			break
	r = await _ram("streetlight pole", lp.origin + Vector3(0, 3.0, 0), lp.basis.z, 25.0, 7.0)
	results.append(["streetlight, fast -> crash", r[0] and r[2] < 0.5])
	r = await _ram("streetlight pole (max speed)", lp.origin + Vector3(0, 3.0, 0), lp.basis.z, 28.0, 9.0)
	results.append(["streetlight, 28 m/s -> crash, no tunnelling", r[0] and r[2] < 0.5])
	# 4) a front fence, from the street side at max speed (thin: tunnelling check)
	var fe: Array = _fence_list[0]
	for f in _fence_list:
		var fx: Transform3D = f[0]
		if String(f[1]).begins_with("picket") and _clear_path(fx.origin + Vector3(0, 1.0, 0), -fx.basis.z, 9.0, "a fence"):
			fe = f
			break
	var ft: Transform3D = fe[0]
	r = await _ram("picket fence (max speed)", ft.origin + Vector3(0, 1.0, 0), -ft.basis.z, 28.0, 7.0)
	results.append(["fence, 28 m/s -> crash, no tunnelling", r[0] and r[2] < 0.3])
	r = await _ram("picket fence (soft brush)", ft.origin + Vector3(0, 1.0, 0), -ft.basis.z, 2.5, 1.9, 0.3)
	results.append(["fence, 2.5 m/s -> bump, no crash", (not r[0]) and r[2] < 0.3])
	var ok := 0
	for x in results:
		print("[towncollide] %-48s %s" % [x[0], "PASS" if x[1] else "FAIL"])
		if x[1]:
			ok += 1
	print("[towncollide] RESULT %d/%d" % [ok, results.size()])
	get_tree().quit()


## True if a fat-ish corridor (5 rays: centre, +-0.9 m sideways, +-0.5 m up/down) from `dist` metres
## back first hits something labelled `what` near the target.
func _clear_path(target: Vector3, dir: Vector3, dist: float, what: String) -> bool:
	dir.y = 0.0
	dir = dir.normalized()
	var side := dir.cross(Vector3.UP)
	var space := get_world_3d().direct_space_state
	for o in [Vector3.ZERO, side * 0.9, -side * 0.9, Vector3(0, 0.5, 0), Vector3(0, -0.4, 0)]:
		var q := PhysicsRayQueryParameters3D.create(target - dir * dist + o, target + dir * 0.6 + o, 1)
		q.exclude = [sleigh.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty() and o != Vector3.ZERO:
			continue
		if hit.is_empty() or String((hit.collider as Object).get_meta("what", "")) != what:
			return false
		if (hit.position - (target + o)).dot(dir) < -1.0:  # hit something of that kind, but too early (a neighbour)
			return false
	return true


func _street_light_xforms() -> Array:
	var out: Array = []
	for c in get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("Streetlights"):
			var mm := (c as MultiMeshInstance3D).multimesh
			for i in mm.instance_count:
				out.append(mm.get_instance_transform(i))
	return out


func _collision_shot(path: String) -> void:
	await _wait(2.0)
	toggle_collision_debug()
	camera.set("locked", true)
	hud.visible = true
	var d2: Dictionary = deliveries[0]
	for dd in deliveries:
		if Vector2(dd.deck_centre.x, dd.deck_centre.z).length() < Vector2(d2.deck_centre.x, d2.deck_centre.z).length():
			d2 = dd
	var target: Vector3 = d2.deck_centre
	camera.look_at_from_position(target + Vector3(-26, 17, 30), target + Vector3(4, -2, -4), Vector3.UP)
	await _wait(1.0)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[townshots] saved %s" % path)
	get_tree().quit()


## Physics cost: the sleigh skims low over the whole town (lots of nearby collision) for 20 s of game time.
func _phys_bench() -> void:
	await _wait(1.0)
	var ms := 0.0
	var worst := 0.0
	var n := 0
	var t0 := Time.get_ticks_usec()
	for lap in 16:
		var a := TAU * lap / 16.0
		var dir := Vector3(cos(a), 0, sin(a))
		sleigh.call("teleport", Transform3D(Basis.looking_at(dir, Vector3.UP), -dir * 240.0 + Vector3(dir.z, 0, -dir.x) * 30.0 + Vector3(0, 9.0, 0)), dir * 24.0)
		for i in 300:
			await get_tree().physics_frame
			var v := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			ms += v
			worst = maxf(worst, v)
			n += 1
	var wall := (Time.get_ticks_usec() - t0) / 1e3
	print("[townphys] %d physics steps in %.0f ms of real time = %.3f ms per step (whole engine, headless), crashes %d" % [n, wall, wall / n, _crash_log.size()])
	get_tree().quit()


## Street-level view of the most decorated delivery house's front yard.
func _deco_shot(path: String) -> void:
	await _wait(2.0)
	camera.set("locked", true)
	var best: Dictionary = {}
	for info in house_infos:
		if info.get("delivery", false) and int(info.get("deco_n", 0)) > int(best.get("deco_n", -1)):
			best = info
	print("[townshots] most decorated delivery house: %s (%d yard pieces)" % [best.b.addr, int(best.deco_n)])
	var base: Transform3D = best.base
	var fz := base.basis.z
	var fx := base.basis.x
	var door: Vector3 = best.door
	var fl: float = (best.get("deco_spot", {}) as Dictionary).get("front_line", 6.0)
	var target := door + fz * (fl * 0.5) + Vector3(0, 1.6, 0)
	camera.look_at_from_position(target + fz * (fl * 0.5 + 9.0) + fx * 7.0 + Vector3(0, 3.2, 0), target + Vector3(0, 0.6, 0), Vector3.UP)
	await _wait(1.0)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[townshots] saved %s" % path)
	get_tree().quit()
