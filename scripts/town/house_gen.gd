extends RefCounted
## Procedural Santa-ready Aussie houses fitted to real OSM footprints (alt-history: every roof is
## built for Santa, with a flat "Santa deck" on top, string lights on the eaves and a chunky chimney).
## Styles: Queenslander on stumps, worker's cottage, brick veneer + tile, fibro + corrugated iron,
## two-storey modern, plus shops (false fronts + awnings), flats, churches/halls and sheds.
## Everything goes into a MeshBatch (merged meshes); the returned dict tells the town where the
## lights, decks, slopes, chimney, door and collision hull are (world space).

const GB := preload("res://scripts/greybox.gd")
const TOON := preload("res://shaders/toon.gdshader")

var B  # MeshBatch
var _mat_cache: Dictionary = {}

# Hello Neighbor-ish: bold, saturated, slightly candy.
const QLD_WALLS: Array[Color] = [Color(0.98, 0.92, 0.72), Color(0.62, 0.86, 0.78), Color(0.6, 0.78, 0.98), Color(0.98, 0.78, 0.55),
		Color(0.85, 0.7, 0.95), Color(1.0, 0.96, 0.88), Color(0.98, 0.62, 0.55), Color(0.7, 0.9, 0.5), Color(1.0, 0.86, 0.35)]
const FIBRO_WALLS: Array[Color] = [Color(0.55, 0.9, 0.82), Color(1.0, 0.9, 0.45), Color(1.0, 0.7, 0.78), Color(0.58, 0.8, 1.0), Color(0.8, 0.95, 0.6)]
const BRICKS: Array[Color] = [Color(0.78, 0.38, 0.2), Color(0.9, 0.72, 0.48), Color(0.62, 0.22, 0.16), Color(0.7, 0.46, 0.3)]
const RENDER_WALLS: Array[Color] = [Color(0.95, 0.94, 0.9), Color(0.32, 0.33, 0.4), Color(0.75, 0.55, 0.85), Color(0.95, 0.55, 0.25)]
const IRON_ROOFS: Array[Color] = [Color(0.72, 0.14, 0.12), Color(0.16, 0.48, 0.32), Color(0.2, 0.26, 0.44), Color(0.6, 0.64, 0.7), Color(0.45, 0.2, 0.55)]
const TILE_ROOFS: Array[Color] = [Color(0.86, 0.4, 0.18), Color(0.55, 0.22, 0.14), Color(0.28, 0.27, 0.32), Color(0.78, 0.3, 0.16)]
const TRIMS: Array[Color] = [Color(1.0, 1.0, 0.96), Color(0.12, 0.38, 0.26), Color(0.55, 0.12, 0.16), Color(0.16, 0.2, 0.45), Color(1.0, 0.8, 0.2)]
const DOORS: Array[Color] = [Color(0.85, 0.12, 0.12), Color(0.1, 0.45, 0.3), Color(0.15, 0.25, 0.6), Color(1.0, 0.7, 0.1), Color(0.5, 0.2, 0.6)]
const WARM := Color(1.0, 0.68, 0.32)
const DECK := Color(0.66, 0.42, 0.24)
const STUMP := Color(0.38, 0.3, 0.28)
const UNDER := Color(0.12, 0.09, 0.15)
const SOFFIT := Color(0.36, 0.3, 0.42)
const GLASS_DARK := Color(0.16, 0.2, 0.42)


func _init(batch) -> void:
	B = batch


# --- materials --------------------------------------------------------------------------------------

func k_plain(c: Color, emission := 0.0) -> String:
	var key := "p_%s_%s" % [c.to_html(false), emission]
	if not B.has_material(key):
		B.register(key, GB.mat(c, emission))
		if emission > 0.0:
			B.no_shadow[key] = true
	return key


func k_roof(c: Color, shiny := false) -> String:
	var key := "r_%s_%s" % [c.to_html(false), shiny]
	if not B.has_material(key):
		B.register(key, GB.patchy(c, c.lightened(0.18), 0.45, 0.35, 0.6 if shiny else 0.0))
	return key


func k_brick(c: Color) -> String:
	var key := "b_%s" % c.to_html(false)
	if not B.has_material(key):
		var m := ShaderMaterial.new()
		m.shader = TOON
		m.set_shader_parameter("albedo", c)
		m.set_shader_parameter("pattern", 5)
		m.set_shader_parameter("pattern_color", c.lerp(Color(0.95, 0.9, 0.82), 0.55))
		m.set_shader_parameter("pattern_scale", 1.0)
		m.set_shader_parameter("rim_strength", 0.22)
		B.register(key, m)
	return key


# --- main entry -------------------------------------------------------------------------------------

## b: building dict from the town JSON. style: see pick_style(). landing: {} for background houses,
## or {"type": "pad"|"ridge"|"slick"|"bonus"} for delivery houses (wider deck, fixed pitch).
func build(b: Dictionary, style: String, rng: RandomNumberGenerator, landing: Dictionary = {}) -> Dictionary:
	var obb: Dictionary = b.obb
	var size: Array = obb.size
	var face := int(b.get("front_face", 0))
	var W: float
	var D: float
	if face <= 1:
		D = float(size[0])
		W = float(size[1])
	else:
		D = float(size[1])
		W = float(size[0])
	W = clampf(W, 3.2, 60.0)
	D = clampf(D, 3.2, 60.0)
	var c: Array = obb.c
	var centre := Vector3(float(c[0]), 0.0, -float(c[1]))
	var fz: Vector3
	if b.get("front") != null:
		fz = Vector3(float(b.front[0]), 0.0, -float(b.front[1])).normalized()
	else:
		var a := float(obb.angle)
		fz = Vector3(cos(a), 0, -sin(a))
	var fx := Vector3.UP.cross(fz).normalized()
	var base := Transform3D(Basis(fx, Vector3.UP, fz), centre)
	var lean := Vector3(rng.randf_range(-0.035, 0.035), 1.0, rng.randf_range(-0.03, 0.03))
	if not landing.is_empty():
		lean = Vector3(lean.x * 0.4, 1.0, lean.z * 0.4)
	B.xform = base * Transform3D(Basis(Vector3.RIGHT, lean, Vector3.BACK), Vector3.ZERO)
	B.set_chunk_at(centre)
	B.col_on = B.col_sink != null
	var info := {"style": style, "base": base, "W": W, "D": D}
	match style:
		"shop":
			_shop(b, W, D, rng, info)
		"apartments":
			_flats(b, W, D, rng, info)
		"hall":
			_hall(W, D, rng, info)
		"shed":
			_shed(W, D, rng, info)
		_:
			_house(b, style, W, D, rng, landing, info)
	B.xform = Transform3D.IDENTITY
	B.col_on = false
	return info


static func pick_style(b: Dictionary, rng: RandomNumberGenerator) -> String:
	match String(b.kind):
		"shop":
			return "shop"
		"apartments":
			return "apartments"
		"church", "civic", "other":
			return "hall"
		"shed":
			return "shed"
	var area := float(b.area)
	var lv = b.get("levels")
	if lv != null and float(lv) >= 2.0 and rng.randf() < 0.6:
		return "modern"
	var r := rng.randf()
	if area < 115.0:
		return "cottage" if r < 0.55 else ("queenslander" if r < 0.8 else "fibro")
	if r < 0.5:
		return "queenslander"
	if r < 0.68:
		return "brick"
	if r < 0.84:
		return "fibro"
	if r < 0.93:
		return "cottage"
	return "modern"


# --- houses -----------------------------------------------------------------------------------------

func _house(b: Dictionary, style: String, W: float, D: float, rng: RandomNumberGenerator, landing: Dictionary, info: Dictionary) -> void:
	var floor_y := 0.3
	var wall_h := 2.85
	var verandah := 0.0
	var roof_kind := "hip"
	var pitch := 30.0
	var wall_col: Color
	var wall_key: String
	var roof_col: Color
	var roof_key: String
	var trim: Color = TRIMS[rng.randi() % TRIMS.size()]
	var lv = b.get("levels")
	var levels := 1 if lv == null else clampi(int(round(float(lv))), 1, 3)
	match style:
		"queenslander":
			floor_y = rng.randf_range(1.7, 2.4)
			verandah = clampf(D * 0.2, 1.8, 2.6)
			wall_col = QLD_WALLS[rng.randi() % QLD_WALLS.size()]
			roof_col = IRON_ROOFS[rng.randi() % IRON_ROOFS.size()]
			pitch = rng.randf_range(28.0, 36.0)
			roof_kind = "hip"
		"cottage":
			floor_y = rng.randf_range(1.1, 1.8)
			verandah = clampf(D * 0.18, 1.6, 2.2)
			wall_col = QLD_WALLS[rng.randi() % QLD_WALLS.size()]
			roof_col = IRON_ROOFS[rng.randi() % IRON_ROOFS.size()]
			roof_kind = "gable_z"
			pitch = rng.randf_range(32.0, 40.0)
		"brick":
			floor_y = 0.3
			wall_h = 2.7 * levels
			wall_col = BRICKS[rng.randi() % BRICKS.size()]
			roof_col = TILE_ROOFS[rng.randi() % TILE_ROOFS.size()]
			pitch = rng.randf_range(20.0, 25.0)
			trim = Color(1.0, 0.98, 0.92) if rng.randf() < 0.6 else trim
		"fibro":
			floor_y = rng.randf_range(0.6, 0.9)
			wall_h = 2.6
			wall_col = FIBRO_WALLS[rng.randi() % FIBRO_WALLS.size()]
			roof_col = IRON_ROOFS[rng.randi() % IRON_ROOFS.size()]
			roof_kind = "gable_x"
			pitch = rng.randf_range(18.0, 24.0)
		_:  # modern two-storey
			floor_y = 0.2
			wall_h = 2.9 * maxi(levels, 2)
			wall_col = RENDER_WALLS[rng.randi() % RENDER_WALLS.size()]
			roof_col = Color(0.3, 0.3, 0.36)
			roof_kind = "flat"
	if style == "queenslander" and levels >= 2:
		wall_h = 2.85 * 2
	wall_key = k_brick(wall_col) if style == "brick" else k_plain(wall_col)
	if landing.has("type"):
		match String(landing.type):
			"ridge":
				pitch = 36.0
				if roof_kind == "flat":
					roof_kind = "hip"
			"pad", "bonus", "slick":
				pitch = minf(pitch, 26.0)
				if roof_kind == "flat":
					roof_kind = "hip"
	roof_key = k_roof(roof_col, landing.get("type", "") == "slick")
	var trim_key := k_plain(trim)

	var ov := 0.45  # eave overhang
	var wx := W * 0.5 - 0.3  # wall half width
	var z_back := -D * 0.5 + 0.3
	var z_front := D * 0.5 - 0.3 - verandah  # front wall plane
	var wd := z_front - z_back
	if wd < 2.5:
		verandah = maxf(0.0, verandah - (2.5 - wd))
		z_front = D * 0.5 - 0.3 - verandah
		wd = z_front - z_back
	var zc := (z_front + z_back) * 0.5
	var top := floor_y + wall_h
	info["floor_y"] = floor_y

	# Walls
	B.abox(wall_key, Vector3(0, floor_y + wall_h * 0.5, zc), Vector3(wx * 2.0, wall_h, wd))
	# Raised houses: stumps, dark undercroft, floor slab under house + verandah
	if floor_y > 0.5:
		var slab_z0 := z_back - 0.1
		var slab_z1 := D * 0.5 - 0.15
		B.abox(trim_key, Vector3(0, floor_y - 0.1, (slab_z0 + slab_z1) * 0.5), Vector3(wx * 2.0 + 0.2, 0.22, slab_z1 - slab_z0), 0.0, false)
		B.abox(k_plain(UNDER), Vector3(0, (floor_y - 0.2) * 0.5, zc), Vector3(wx * 2.0 - 1.4, floor_y - 0.2, wd - 1.4))
		var stump_key := k_plain(STUMP)
		var nx := maxi(2, int(ceil(wx * 2.0 / 2.4)) + 1)
		var nz := maxi(2, int(ceil((slab_z1 - slab_z0) / 2.4)) + 1)
		for i in nx:
			for j in nz:
				if i != 0 and i != nx - 1 and j != 0 and j != nz - 1:
					continue
				var x := lerpf(-wx + 0.15, wx - 0.15, float(i) / float(nx - 1))
				var z := lerpf(slab_z0 + 0.15, slab_z1 - 0.15, float(j) / float(nz - 1))
				B.abox(stump_key, Vector3(x, (floor_y - 0.2) * 0.5, z), Vector3(0.2, floor_y - 0.2, 0.2))
		# timber battens between the front stumps (classic Queenslander under-house screen)
		if floor_y > 1.4:
			for y in [0.45, 0.9]:
				B.abox(trim_key, Vector3(0, y, slab_z1 - 0.15), Vector3(wx * 2.0, 0.08, 0.05))
	elif floor_y > 0.25:
		B.abox(k_plain(Color(0.5, 0.42, 0.4)), Vector3(0, floor_y * 0.5, zc), Vector3(wx * 2.0 + 0.1, floor_y, wd + 0.1))

	# Verandah: posts, rail with a lattice infill, frieze
	var door_x := 0.0 if style != "brick" else rng.randf_range(-wx * 0.4, wx * 0.4)
	if verandah > 0.0:
		var vz := D * 0.5 - 0.45
		var npost := maxi(2, int(round(wx * 2.0 / 2.3)) + 1)
		for i in npost:
			var x := lerpf(-wx + 0.1, wx - 0.1, float(i) / float(npost - 1))
			B.abox(trim_key, Vector3(x, floor_y + wall_h * 0.5, vz), Vector3(0.14, wall_h, 0.14))
		var gap0 := door_x - 0.75
		var gap1 := door_x + 0.75
		for seg in [[-wx, gap0], [gap1, wx]]:
			var a: float = seg[0]
			var e: float = seg[1]
			if e - a < 0.3:
				continue
			B.abox(trim_key, Vector3((a + e) * 0.5, floor_y + 0.95, vz), Vector3(e - a, 0.09, 0.12))
			B.abox(k_plain(trim.darkened(0.25)), Vector3((a + e) * 0.5, floor_y + 0.5, vz), Vector3(e - a, 0.8, 0.04))
		B.abox(trim_key, Vector3(0, top - 0.22, vz), Vector3(wx * 2.0, 0.26, 0.06))
		# side rails
		for sx in [-1.0, 1.0]:
			B.abox(trim_key, Vector3(sx * (wx - 0.05), floor_y + 0.95, (z_front + vz) * 0.5), Vector3(0.09, 0.09, vz - z_front))
	# Front stairs down to the yard
	if floor_y > 0.45:
		var steps := int(ceil(floor_y / 0.19))
		var run := 0.27
		var z0 := D * 0.5 - 0.3 if verandah > 0.0 else z_front
		for s in steps:
			var y := floor_y - (s + 1) * floor_y / float(steps)
			B.abox(trim_key, Vector3(door_x, y + floor_y / float(steps) * 0.5, z0 + run * (s + 0.5)), Vector3(1.3, floor_y / float(steps), run))
		for sx in [-0.7, 0.7]:
			B.beam(trim_key, Vector3(door_x + sx, floor_y + 0.9, z0), Vector3(door_x + sx, 0.9, z0 + run * steps), 0.08, 0.08)
	# Front door + porch light
	var door_col: Color = DOORS[rng.randi() % DOORS.size()]
	var col_was: bool = B.col_on
	B.col_on = false  # door, knob and porch lamp are flush details: no collision
	B.abox(trim_key, Vector3(door_x, floor_y + 1.1, z_front + 0.03), Vector3(1.25, 2.35, 0.08))
	B.abox(k_plain(door_col), Vector3(door_x, floor_y + 1.05, z_front + 0.07), Vector3(0.95, 2.1, 0.06))
	B.abox(k_plain(Color(1.0, 0.85, 0.4), 2.2), Vector3(door_x + 0.45, floor_y + 1.05, z_front + 0.12), Vector3(0.08, 0.08, 0.06))
	B.abox(k_plain(WARM, 2.6), Vector3(door_x + 0.85, floor_y + 2.3, z_front + 0.12), Vector3(0.22, 0.3, 0.14))
	B.col_on = col_was
	if style == "brick":  # little porch roof over the door
		B.abox(k_roof(roof_col), Vector3(door_x, floor_y + 2.6, z_front + 0.75), Vector3(2.0, 0.12, 1.5))
		for sx in [-0.85, 0.85]:
			B.abox(trim_key, Vector3(door_x + sx, floor_y + 1.3, z_front + 1.4), Vector3(0.12, 2.6, 0.12))

	# Windows on every wall
	var lit_p := rng.randf_range(0.35, 0.8)
	var storeys := maxi(1, int(round(wall_h / 2.8)))
	for st in storeys:
		var sill := floor_y + 0.85 + st * 2.85
		_windows(Vector3(0, 0, z_front), Vector3.RIGHT, Vector3.BACK, wx * 2.0, sill, trim, rng, lit_p, door_x if st == 0 else 999.0)
		_windows(Vector3(0, 0, z_back), Vector3.LEFT, Vector3.FORWARD, wx * 2.0, sill, trim, rng, lit_p, 999.0)
		_windows(Vector3(wx, 0, zc), Vector3.FORWARD, Vector3.RIGHT, wd, sill, trim, rng, lit_p, 999.0)
		_windows(Vector3(-wx, 0, zc), Vector3.BACK, Vector3.LEFT, wd, sill, trim, rng, lit_p, 999.0)

	# Roof
	var ex := wx + ov
	var ez0 := z_back - ov
	var ez1 := D * 0.5 - 0.3 + ov * 0.6
	var deck_min := 2.4
	if landing.has("type"):
		deck_min = 2.8 if landing.type == "ridge" else 4.2
	_roof(roof_kind, top, ex, ez0, ez1, pitch, deck_min, roof_key, trim_key, wall_key, wx, z_back, z_front, info, landing)
	# Hull for background collision (walls + eaves + deck)
	var hull := PackedVector3Array()
	for p in [Vector3(-wx, 0, z_back), Vector3(wx, 0, z_back), Vector3(wx, 0, D * 0.5 - 0.3), Vector3(-wx, 0, D * 0.5 - 0.3),
			Vector3(-ex, top, ez0), Vector3(ex, top, ez0), Vector3(ex, top, ez1), Vector3(-ex, top, ez1)]:
		hull.append(B.xform * p)
	for p in info.get("deck_local", []):
		hull.append(B.xform * p)
	info["hull"] = hull
	info["door"] = B.xform * Vector3(door_x, 0.0, D * 0.5 + (floor_y * 1.1 if floor_y > 0.45 else 0.3))
	info["door_x"] = door_x
	info["door_wall"] = B.xform * Vector3(door_x, floor_y + 1.55, z_front + 0.06)  # wreath spot
	info["top"] = top


func _windows(c: Vector3, t: Vector3, n: Vector3, L: float, sill: float, trim: Color, rng: RandomNumberGenerator, lit_p: float, skip_x: float) -> void:
	var count := maxi(1, int((L - 0.8) / 3.0))
	var col_was: bool = B.col_on
	B.col_on = false  # window frames/glass/shutters sit flush on the wall box: visual only
	var trim_key := k_plain(trim)
	var lit_key := k_plain(WARM, 1.7)
	var dark_key := k_plain(GLASS_DARK, 0.25)
	var shutter := trim.darkened(0.35) if rng.randf() < 0.5 else Color(0.2, 0.5, 0.35)
	for i in count:
		var s := (float(i) + 0.5) / float(count) * L - L * 0.5
		if absf(s - skip_x) < 1.3:
			continue
		var w := rng.randf_range(0.9, 1.25)
		var h := rng.randf_range(1.1, 1.45)
		var p := c + t * s + Vector3.UP * (sill + h * 0.5)
		var roll := deg_to_rad(rng.randf_range(-4.0, 4.0))
		var bas := Basis(t, Vector3.UP, n) * Basis(Vector3.BACK, roll)
		B.box(trim_key, Transform3D(bas, p + n * 0.04), Vector3(w + 0.22, h + 0.22, 0.08))
		B.box(lit_key if rng.randf() < lit_p else dark_key, Transform3D(bas, p + n * 0.07), Vector3(w, h, 0.04))
		B.box(trim_key, Transform3D(bas, p + n * 0.1 + Vector3.UP * 0.0), Vector3(0.06, h, 0.03))
		if rng.randf() < 0.35:
			var sk := k_plain(shutter)
			for sd in [-1.0, 1.0]:
				B.box(sk, Transform3D(bas * Basis(Vector3.BACK, deg_to_rad(rng.randf_range(-7, 7))), p + t * sd * (w * 0.5 + 0.32) + n * 0.06), Vector3(0.42, h + 0.1, 0.05))
	B.col_on = col_was


## Santa-ready roof: hip / gable with a flat deck on top, or a flat roof with a low lip.
func _roof(kind: String, y: float, ex: float, ez0: float, ez1: float, pitch: float, deck_min: float, roof_key: String,
		trim_key: String, wall_key: String, wx: float, z_back: float, z_front: float, info: Dictionary, landing: Dictionary) -> void:
	var tanp := tan(deg_to_rad(pitch))
	var col_was: bool = B.col_on
	if not landing.is_empty():
		B.col_on = false  # delivery roofs get their own scored deck/slope/chimney bodies
	var ezc := (ez0 + ez1) * 0.5
	var ez := (ez1 - ez0) * 0.5
	var deck_key := k_roof(DECK) if landing.is_empty() else k_plain(Color(0.42, 0.36, 0.5))
	if landing.get("type", "") == "slick":
		deck_key = k_roof(Color(0.2, 0.28, 0.55), true)
	elif landing.get("type", "") == "bonus":
		deck_key = k_roof(Color(0.55, 0.42, 0.18))
	var slopes: Array = []
	var deck: PackedVector3Array
	# soffit (underside of the eaves) so the roof never looks hollow from the street
	B.quad(k_plain(SOFFIT), Vector3(-ex, y, ez0), Vector3(ex, y, ez0), Vector3(ex, y, ez1), Vector3(-ex, y, ez1), Vector3.DOWN)
	if kind == "flat":
		var hy := y + 0.25
		B.quad(roof_key, Vector3(-ex, hy, ez0), Vector3(ex, hy, ez0), Vector3(ex, hy, ez1), Vector3(-ex, hy, ez1), Vector3.UP)
		for e in [[Vector3(-ex, hy, ez0), Vector3(ex, hy, ez0)], [Vector3(ex, hy, ez0), Vector3(ex, hy, ez1)], [Vector3(ex, hy, ez1), Vector3(-ex, hy, ez1)], [Vector3(-ex, hy, ez1), Vector3(-ex, hy, ez0)]]:
			B.beam(trim_key, e[0] - Vector3(0, 0.15, 0), e[1] - Vector3(0, 0.15, 0), 0.25, 0.55)
		deck = PackedVector3Array([Vector3(-ex + 0.3, hy, ez0 + 0.3), Vector3(ex - 0.3, hy, ez0 + 0.3), Vector3(ex - 0.3, hy, ez1 - 0.3), Vector3(-ex + 0.3, hy, ez1 - 0.3)])
	elif kind == "hip":
		var r := minf(ex, ez) - deck_min * 0.5
		r = clampf(r, 0.8, minf(ex, ez) - 0.6)
		var h := r * tanp
		var ty := y + h
		var e := [Vector3(-ex, y, ez0), Vector3(ex, y, ez0), Vector3(ex, y, ez1), Vector3(-ex, y, ez1)]
		var t := [Vector3(-ex + r, ty, ez0 + r), Vector3(ex - r, ty, ez0 + r), Vector3(ex - r, ty, ez1 - r), Vector3(-ex + r, ty, ez1 - r)]
		var hints := [Vector3(0, 1, -1), Vector3(1, 1, 0), Vector3(0, 1, 1), Vector3(-1, 1, 0)]
		for i in 4:
			var j := (i + 1) % 4
			B.quad(roof_key, e[i], e[j], t[j], t[i], hints[i])
			slopes.append(PackedVector3Array([B.xform * e[i], B.xform * e[j], B.xform * t[j], B.xform * t[i]]))
		deck = PackedVector3Array(t)
	else:  # gable_x (ridge across the front) / gable_z (gable end faces the street)
		var along_x := kind == "gable_x"
		var half := ez if along_x else ex
		var r := clampf(half - deck_min * 0.5, 0.8, half - 0.6)
		var h := r * tanp
		var ty := y + h
		if along_x:
			B.quad(roof_key, Vector3(-ex, y, ez1), Vector3(ex, y, ez1), Vector3(ex, ty, ez1 - r), Vector3(-ex, ty, ez1 - r), Vector3(0, 1, 1))
			B.quad(roof_key, Vector3(-ex, y, ez0), Vector3(ex, y, ez0), Vector3(ex, ty, ez0 + r), Vector3(-ex, ty, ez0 + r), Vector3(0, 1, -1))
			slopes.append(PackedVector3Array([B.xform * Vector3(-ex, y, ez1), B.xform * Vector3(ex, y, ez1), B.xform * Vector3(ex, ty, ez1 - r), B.xform * Vector3(-ex, ty, ez1 - r)]))
			slopes.append(PackedVector3Array([B.xform * Vector3(-ex, y, ez0), B.xform * Vector3(ex, y, ez0), B.xform * Vector3(ex, ty, ez0 + r), B.xform * Vector3(-ex, ty, ez0 + r)]))
			deck = PackedVector3Array([Vector3(-ex, ty, ez0 + r), Vector3(ex, ty, ez0 + r), Vector3(ex, ty, ez1 - r), Vector3(-ex, ty, ez1 - r)])
			# gable ends (wall colour) at the side walls
			for sx in [-wx, wx]:
				var g := PackedVector2Array([Vector2(ez0 + r, h), Vector2(ez1 - r, h), Vector2(ez1, 0.0), Vector2(ez0, 0.0)])
				_gable(wall_key, sx, g, y, true)
				# fascia under the gable overhang
				B.quad(trim_key, Vector3(sx * ex / wx, y, ez0), Vector3(sx * ex / wx, ty, ez0 + r), Vector3(sx * ex / wx, ty, ez1 - r), Vector3(sx * ex / wx, y, ez1), Vector3(signf(sx), 0, 0))
		else:
			B.quad(roof_key, Vector3(ex, y, ez0), Vector3(ex, y, ez1), Vector3(ex - r, ty, ez1), Vector3(ex - r, ty, ez0), Vector3(1, 1, 0))
			B.quad(roof_key, Vector3(-ex, y, ez0), Vector3(-ex, y, ez1), Vector3(-ex + r, ty, ez1), Vector3(-ex + r, ty, ez0), Vector3(-1, 1, 0))
			slopes.append(PackedVector3Array([B.xform * Vector3(ex, y, ez0), B.xform * Vector3(ex, y, ez1), B.xform * Vector3(ex - r, ty, ez1), B.xform * Vector3(ex - r, ty, ez0)]))
			slopes.append(PackedVector3Array([B.xform * Vector3(-ex, y, ez0), B.xform * Vector3(-ex, y, ez1), B.xform * Vector3(-ex + r, ty, ez1), B.xform * Vector3(-ex + r, ty, ez0)]))
			deck = PackedVector3Array([Vector3(-ex + r, ty, ez0), Vector3(ex - r, ty, ez0), Vector3(ex - r, ty, ez1), Vector3(-ex + r, ty, ez1)])
			for zz in [ez0, ez1]:
				B.quad(trim_key, Vector3(-ex, y, zz), Vector3(-ex + r, ty, zz), Vector3(ex - r, ty, zz), Vector3(ex, y, zz), Vector3(0, 0, signf(zz - ezc)))
			# gable ends at the front (over the verandah, decorative) and back walls
			for zz in [z_back, ez1 - 0.05]:
				_gable_z(wall_key if zz == z_back else trim_key, zz, ex, r, h, y, signf(zz - ezc))
	# Deck: planks + a thin lip
	if kind != "flat":
		var lift := Vector3(0, 0.04, 0)
		B.quad(deck_key, deck[0] + lift, deck[1] + lift, deck[2] + lift, deck[3] + lift, Vector3.UP)
		for i in 4:
			B.beam(trim_key, deck[i] + Vector3(0, 0.02, 0), deck[(i + 1) % 4] + Vector3(0, 0.02, 0), 0.12, 0.1)
	# Fascia boards along the eaves
	var eav := [Vector3(-ex, y - 0.08, ez0), Vector3(ex, y - 0.08, ez0), Vector3(ex, y - 0.08, ez1), Vector3(-ex, y - 0.08, ez1)]
	var col_roof: bool = B.col_on
	B.col_on = false
	for i in 4:
		B.beam(trim_key, eav[i], eav[(i + 1) % 4], 0.1, 0.2)
	B.col_on = col_roof
	# Chunky leaning brick chimney poking through a slope near the back
	var cx := ex * 0.45 * (1.0 if (int(absf(ex * 100.0)) % 2 == 0) else -1.0)
	var cz := ezc - ez * 0.35
	var deck_y: float = deck[0].y
	var ch_h := deck_y - y + 1.7
	var lr := RandomNumberGenerator.new()
	lr.seed = hash(Vector3(ex, y, ez0))
	var lean := Vector3(lr.randf_range(-0.12, 0.12), 0, lr.randf_range(-0.1, 0.1))
	var bk := k_brick(Color(0.66, 0.26, 0.18))
	var w := 1.15
	B.box(bk, Transform3D(Basis(Vector3.RIGHT, Vector3(lean.x / ch_h * 2.0, 1, lean.z / ch_h * 2.0), Vector3.BACK), Vector3(cx, y + ch_h * 0.5 - 0.3, cz)), Vector3(w, ch_h + 0.6, w))
	var ctop := Vector3(cx + lean.x, y + ch_h - 0.3, cz + lean.z)
	B.abox(k_plain(Color(0.5, 0.48, 0.52)), ctop + Vector3(0, 0.12, 0), Vector3(w + 0.3, 0.22, w + 0.3))
	B.abox(k_plain(Color(0.08, 0.06, 0.07)), ctop + Vector3(0, 0.24, 0), Vector3(w - 0.35, 0.03, w - 0.35))
	B.cylinder(k_plain(Color(0.78, 0.4, 0.25)), ctop + Vector3(0.22, 0.2, 0.0), 0.16, 0.2, 0.45, 8)
	info["chimney_top"] = B.xform * (ctop + Vector3(0, 0.3, 0))
	info["chimney_local"] = Vector3(cx, y, cz)
	info["chimney_w"] = w
	info["slopes"] = slopes
	info["deck_local"] = deck
	info["deck_world"] = _xf(deck)
	info["eave_world"] = _xf(PackedVector3Array([Vector3(-ex - 0.04, y - 0.05, ez0 - 0.04), Vector3(ex + 0.04, y - 0.05, ez0 - 0.04),
			Vector3(ex + 0.04, y - 0.05, ez1 + 0.04), Vector3(-ex - 0.04, y - 0.05, ez1 + 0.04)]))
	info["deck_y"] = deck_y
	B.col_on = col_was


func _xf(p: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for v in p:
		out.append(B.xform * v)
	return out


func _gable(key: String, x: float, g: PackedVector2Array, y: float, _unused: bool) -> void:
	# g: (z, height) outline in the plane x = const
	var c := Vector2.ZERO
	for p in g:
		c += p
	c /= g.size()
	for i in g.size():
		var a := g[i]
		var b := g[(i + 1) % g.size()]
		B.tri(key, Vector3(x, y + c.y, c.x), Vector3(x, y + a.y, a.x), Vector3(x, y + b.y, b.x), Vector3(signf(x), 0, 0))


func _gable_z(key: String, z: float, ex: float, r: float, h: float, y: float, side: float) -> void:
	var pts := [Vector3(-ex + 0.3, y, z), Vector3(ex - 0.3, y, z), Vector3(ex - r, y + h - 0.02, z), Vector3(-ex + r, y + h - 0.02, z)]
	B.quad(key, pts[0], pts[1], pts[2], pts[3], Vector3(0, 0, side))


# --- other building kinds ---------------------------------------------------------------------------

func _shop(b: Dictionary, W: float, D: float, rng: RandomNumberGenerator, info: Dictionary) -> void:
	var lv = b.get("levels")
	var levels := clampi(int(round(float(lv))) if lv != null else (1 if rng.randf() < 0.6 else 2), 1, 4)
	var h := 3.6 + (levels - 1) * 3.0
	var wall: Color = [Color(0.95, 0.85, 0.6), Color(0.85, 0.35, 0.25), Color(0.4, 0.7, 0.75), Color(0.98, 0.95, 0.88), Color(0.6, 0.45, 0.8)][rng.randi() % 5]
	var wk := k_plain(wall)
	var trim: Color = TRIMS[rng.randi() % TRIMS.size()]
	var tk := k_plain(trim)
	var hw := W * 0.5 - 0.1
	var hd := D * 0.5 - 0.1
	B.abox(wk, Vector3(0, h * 0.5, 0), Vector3(hw * 2.0, h, hd * 2.0))
	# false front parapet with a sign
	B.abox(wk, Vector3(0, h + 0.7, hd - 0.15), Vector3(hw * 2.0, 1.4, 0.3))
	B.abox(tk, Vector3(0, h + 1.45, hd - 0.15), Vector3(hw * 2.0 + 0.2, 0.15, 0.4))
	var sign_col: Color = [Color(1.0, 0.85, 0.2), Color(0.9, 0.15, 0.15), Color(0.2, 0.75, 0.35), Color(0.2, 0.5, 1.0)][rng.randi() % 4]
	B.abox(k_plain(sign_col, 0.9), Vector3(0, h + 0.7, hd + 0.03), Vector3(minf(hw * 1.4, 7.0), 0.75, 0.06))
	# glowing shop window + door
	B.abox(k_plain(WARM, 1.5), Vector3(0, 1.5, hd + 0.03), Vector3(hw * 1.7, 2.0, 0.05))
	B.abox(tk, Vector3(0, 2.6, hd + 0.06), Vector3(hw * 1.8, 0.12, 0.08))
	# awning out over the footpath on posts
	B.abox(k_plain(trim.darkened(0.15)), Vector3(0, 3.15, hd + 1.4), Vector3(hw * 2.0, 0.14, 2.8))
	for i in maxi(2, int(hw / 2.5) + 1):
		var x := lerpf(-hw + 0.2, hw - 0.2, float(i) / maxf(1.0, float(maxi(2, int(hw / 2.5) + 1) - 1)))
		B.abox(tk, Vector3(x, 1.55, hd + 2.65), Vector3(0.12, 3.1, 0.12))
	# upper windows
	for lvl in range(1, levels):
		_windows(Vector3(0, 0, hd), Vector3.RIGHT, Vector3.BACK, hw * 2.0, 0.6 + lvl * 3.0 + 0.4, trim, rng, 0.5, 999.0)
	# flat roof with a Santa deck
	var y := h + 0.02
	B.quad(k_roof(Color(0.35, 0.33, 0.4)), Vector3(-hw, y, -hd), Vector3(hw, y, -hd), Vector3(hw, y, hd - 0.3), Vector3(-hw, y, hd - 0.3), Vector3.UP)
	var deck := PackedVector3Array([Vector3(-hw + 0.5, y + 0.05, -hd + 0.5), Vector3(hw - 0.5, y + 0.05, -hd + 0.5), Vector3(hw - 0.5, y + 0.05, hd - 0.8), Vector3(-hw + 0.5, y + 0.05, hd - 0.8)])
	B.quad(k_roof(DECK), deck[0], deck[1], deck[2], deck[3], Vector3.UP)
	info["deck_local"] = deck
	info["deck_world"] = _xf(deck)
	info["deck_y"] = y + 0.05
	info["eave_world"] = _xf(PackedVector3Array([Vector3(-hw, h + 1.5, hd + 0.08), Vector3(hw, h + 1.5, hd + 0.08)]))
	info["eave_open"] = true
	info["slopes"] = []
	info["hull"] = _xf(PackedVector3Array([Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(hw, 0, hd), Vector3(-hw, 0, hd),
			Vector3(-hw, h, -hd), Vector3(hw, h, -hd), Vector3(hw, h + 1.4, hd), Vector3(-hw, h + 1.4, hd)]))
	info["door"] = B.xform * Vector3(0, 0, hd + 0.5)
	info["top"] = h
	info["no_yard"] = true


func _flats(b: Dictionary, W: float, D: float, rng: RandomNumberGenerator, info: Dictionary) -> void:
	var lv = b.get("levels")
	var levels := clampi(int(round(float(lv))) if lv != null else 3, 2, 6)
	var h := levels * 2.9
	var wall: Color = [Color(0.92, 0.82, 0.62), Color(0.7, 0.42, 0.3), Color(0.82, 0.9, 0.95)][rng.randi() % 3]
	var hw := W * 0.5 - 0.2
	var hd := D * 0.5 - 0.2
	B.abox(k_brick(wall) if rng.randf() < 0.5 else k_plain(wall), Vector3(0, h * 0.5, 0), Vector3(hw * 2.0, h, hd * 2.0))
	var trim: Color = TRIMS[rng.randi() % TRIMS.size()]
	for lvl in levels:
		var sill := 0.8 + lvl * 2.9
		_windows(Vector3(0, 0, hd), Vector3.RIGHT, Vector3.BACK, hw * 2.0, sill, trim, rng, 0.45, 0.0 if lvl == 0 else 999.0)
		_windows(Vector3(0, 0, -hd), Vector3.LEFT, Vector3.FORWARD, hw * 2.0, sill, trim, rng, 0.45, 999.0)
		_windows(Vector3(hw, 0, 0), Vector3.FORWARD, Vector3.RIGHT, hd * 2.0, sill, trim, rng, 0.45, 999.0)
		_windows(Vector3(-hw, 0, 0), Vector3.BACK, Vector3.LEFT, hd * 2.0, sill, trim, rng, 0.45, 999.0)
		if lvl > 0:
			B.abox(k_plain(trim), Vector3(0, lvl * 2.9 + 0.05, hd + 0.6), Vector3(hw * 1.2, 0.15, 1.2))
			B.abox(k_plain(trim.darkened(0.2)), Vector3(0, lvl * 2.9 + 0.55, hd + 1.15), Vector3(hw * 1.2, 0.9, 0.08))
	B.abox(k_plain(Color(0.9, 0.2, 0.15)), Vector3(0, 1.05, hd + 0.05), Vector3(1.1, 2.1, 0.08))
	var info2 := {}
	_roof("hip", h, hw + 0.4, -hd - 0.4, hd + 0.4, 22.0, 3.0, k_roof(TILE_ROOFS[rng.randi() % 4]), k_plain(trim), k_plain(wall), hw, -hd, hd, info, info2)
	info["hull"] = _xf(PackedVector3Array([Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(hw, 0, hd), Vector3(-hw, 0, hd)]) + PackedVector3Array(info.deck_local) +
			PackedVector3Array([Vector3(-hw - 0.4, h, -hd - 0.4), Vector3(hw + 0.4, h, -hd - 0.4), Vector3(hw + 0.4, h, hd + 0.4), Vector3(-hw - 0.4, h, hd + 0.4)]))
	info["door"] = B.xform * Vector3(0, 0, hd + 0.5)
	info["top"] = h


func _hall(W: float, D: float, rng: RandomNumberGenerator, info: Dictionary) -> void:
	var h := 5.0
	var wall: Color = [Color(0.85, 0.75, 0.6), Color(0.7, 0.32, 0.22), Color(0.95, 0.93, 0.85)][rng.randi() % 3]
	var hw := W * 0.5 - 0.2
	var hd := D * 0.5 - 0.2
	var wk := k_brick(wall)
	B.abox(wk, Vector3(0, h * 0.5, 0), Vector3(hw * 2.0, h, hd * 2.0))
	var trim := Color(1.0, 0.97, 0.9)
	_windows(Vector3(hw, 0, 0), Vector3.FORWARD, Vector3.RIGHT, hd * 2.0, 1.2, trim, rng, 0.6, 999.0)
	_windows(Vector3(-hw, 0, 0), Vector3.BACK, Vector3.LEFT, hd * 2.0, 1.2, trim, rng, 0.6, 999.0)
	B.abox(k_plain(Color(0.45, 0.2, 0.12)), Vector3(0, 1.5, hd + 0.05), Vector3(2.0, 3.0, 0.1))
	_roof("gable_z", h, hw + 0.4, -hd - 0.3, hd + 0.3, 40.0, 3.0, k_roof(IRON_ROOFS[rng.randi() % IRON_ROOFS.size()]), k_plain(trim), wk, hw, -hd, hd, info, {})
	info["hull"] = _xf(PackedVector3Array([Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(hw, 0, hd), Vector3(-hw, 0, hd),
			Vector3(-hw - 0.4, h, -hd - 0.3), Vector3(hw + 0.4, h, -hd - 0.3), Vector3(hw + 0.4, h, hd + 0.3), Vector3(-hw - 0.4, h, hd + 0.3)]) + PackedVector3Array(info.deck_local))
	info["door"] = B.xform * Vector3(0, 0, hd + 0.5)
	info["top"] = h


func _shed(W: float, D: float, rng: RandomNumberGenerator, info: Dictionary) -> void:
	var h := 2.3
	var hw := W * 0.5 - 0.1
	var hd := D * 0.5 - 0.1
	B.abox(k_plain([Color(0.55, 0.62, 0.55), Color(0.75, 0.7, 0.55), Color(0.55, 0.5, 0.62)][rng.randi() % 3]), Vector3(0, h * 0.5, 0), Vector3(hw * 2.0, h, hd * 2.0))
	var rk := k_roof(IRON_ROOFS[rng.randi() % IRON_ROOFS.size()])
	B.quad(rk, Vector3(-hw - 0.2, h + 0.5, -hd - 0.2), Vector3(hw + 0.2, h + 0.5, -hd - 0.2), Vector3(hw + 0.2, h, hd + 0.2), Vector3(-hw - 0.2, h, hd + 0.2), Vector3(0, 1, 0.2))
	B.quad(k_plain(SOFFIT), Vector3(-hw - 0.2, h + 0.48, -hd - 0.2), Vector3(hw + 0.2, h + 0.48, -hd - 0.2), Vector3(hw + 0.2, h - 0.02, hd + 0.2), Vector3(-hw - 0.2, h - 0.02, hd + 0.2), Vector3(0, -1, -0.2))
	info["hull"] = _xf(PackedVector3Array([Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(hw, 0, hd), Vector3(-hw, 0, hd),
			Vector3(-hw, h + 0.5, -hd), Vector3(hw, h + 0.5, -hd), Vector3(hw, h, hd), Vector3(-hw, h, hd)]))
	info["slopes"] = []
	info["no_yard"] = true
	info["top"] = h
