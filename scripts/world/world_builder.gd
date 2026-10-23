extends RefCounted
## Builds the streamed world's pieces OFF the main thread (WorkerThreadPool). Nothing here touches the scene
## tree: every job returns a detached Node3D (+ collision faces) that the streamer attaches within a per-frame
## budget. LOD per ~250 m cell (4 x 4 per tile) or per ~1 km tile:
##   near  (cell)  full stylised houses from scripts/town/house_gen.gd, eave lights, gum trees, collision faces
##   mid   (cell)  one vertex-coloured mesh: walls, Santa-deck roofs and lit windows with the near colours
##   roads (tile)  asphalt ribbons
##   far   (tile)  impostors: glowing dots (windows, Christmas lights, streetlights) + skyline boxes for towers
##   ground(tile)  32 x 32 landuse / water class raster on a plane
## Near jobs run one at a time (house_gen shares a static material cache); the rest run in parallel.

const MeshBatch := preload("res://scripts/town/mesh_batch.gd")
const HouseGen := preload("res://scripts/town/house_gen.gd")
const Style := preload("res://scripts/world/world_style.gd")
const Geo := preload("res://scripts/world/geo.gd")

const CPT := 4  ## cells per tile side
const WARM := Color(1.0, 0.68, 0.32)
const STREETLIGHT := Color(1.0, 0.62, 0.26)
const MULTI := [Color(1.0, 0.25, 0.2), Color(0.3, 1.0, 0.4), Color(0.35, 0.5, 1.0), Color(1.0, 0.75, 0.2)]
const ROAD_COLS := [Color(0.2, 0.2, 0.24), Color(0.19, 0.19, 0.22), Color(0.18, 0.18, 0.21)]

var data  # WorldData
var town_seed := 2026
# materials / meshes (made on the main thread by the streamer)
var lod_mat: Material
var dots_mat: Material
var dot_mesh: Mesh
var ground_shader: Shader
var bulb_mesh: Mesh
var bulb_mat: Material
var tree_meshes: Array = []
# fades (camera distance); see world_streamer.gd
var near_end := 410.0
var near_margin := 30.0
var mid_end := 2300.0
var mid_margin := 250.0
var road_end := 2600.0
var far_begin := 1900.0
var far_margin := 350.0
var far_end := 9500.0
var ground_end := 4000.0
var col_chunk := 32.0
var _shared_mats: Dictionary = {}  # near lane only
## Headless runs use the dummy renderer, whose resource tables are NOT thread-safe (Forward+ / Mobile are).
## There, every job serialises the bits that create GPU resources; in the real game this is a no-op.
var _rs := Mutex.new()
var _rs_lock := DisplayServer.get_name() == "headless"


func _lk() -> void:
	if _rs_lock:
		_rs.lock()


func _ulk() -> void:
	if _rs_lock:
		_rs.unlock()


func _init(world_data) -> void:
	data = world_data


static func cell_of(p: Vector2, dims: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((p.x / dims.x + 0.5) * CPT), 0, CPT - 1), clampi(floori((p.y / dims.y + 0.5) * CPT), 0, CPT - 1))


static func cell_centre(c: Vector2i, dims: Vector2) -> Vector2:
	return Vector2(((c.x + 0.5) / CPT - 0.5) * dims.x, ((c.y + 0.5) / CPT - 0.5) * dims.y)


func _ctx(t: Vector2i) -> Array:
	var c := Geo.tile_centre(t)
	return [Style.region_of(c[0], c[1]), data.density(t)]


static func seed_of(b: Dictionary, town_seed_: int) -> int:
	# Same seed string as town.gd, whose ids come from JSON (floats): str(float(id)) keeps Paddington identical.
	return hash(str(float(b.id)) + ":" + str(town_seed_))


static func _vis(gi: GeometryInstance3D, begin: float, begin_margin: float, end: float, end_margin: float) -> void:
	gi.visibility_range_begin = begin
	gi.visibility_range_begin_margin = begin_margin
	gi.visibility_range_end = end
	gi.visibility_range_end_margin = end_margin
	gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


# --------------------------------------------------------------------------------------------- near

func build_near(t: Vector2i, cell: Vector2i) -> Dictionary:
	var td: Dictionary = data.tile(t)
	var root := Node3D.new()
	if td.is_empty():
		return {"node": root, "col": [], "trees": [], "count": 0}
	var dims := Geo.tile_dims(t)
	var cc := cell_centre(cell, dims)
	root.name = "Near_%d_%d" % [cell.x, cell.y]
	root.position = Vector3(cc.x, 0.0, -cc.y)
	var ctx := _ctx(t)
	var B = MeshBatch.new()
	B.chunk_size = 1.0e7
	var COL = MeshBatch.new()
	COL.chunk_size = 1.0e7
	B.col_sink = COL
	B.col_key = "house"
	var gen = HouseGen.new(B)
	_lk()
	var bulb_buf := PackedFloat32Array()
	var tree_pts: Array = []  # [Vector3 local, variant]
	var n := 0
	var styles := {}
	for b in td.buildings:
		var c: Array = b.obb.c
		if cell_of(Vector2(c[0], c[1]), dims) != cell:
			continue
		var bb: Dictionary = b.duplicate()
		bb["obb"] = {"c": [float(c[0]) - cc.x, float(c[1]) - cc.y], "size": b.obb.size, "angle": b.obb.angle}
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_of(b, town_seed)
		var style := Style.pick(bb, rng, ctx[0], ctx[1])
		styles[style] = int(styles.get(style, 0)) + 1
		var info: Dictionary = gen.build(bb, style, rng)
		n += 1
		if info.has("eave_world") and style != "shed":
			bulb_buf.append_array(_bulbs(info.eave_world, not info.get("eave_open", false), rng))
		if style != "shed" and b.front != null and rng.randf() < 0.32:
			var fz := Vector3(float(b.front[0]), 0.0, -float(b.front[1]))
			var p: Vector3 = info.base.origin - fz * (float(info.D) * 0.5 + 3.5) + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
			tree_pts.append([p, rng.randi() % maxi(1, tree_meshes.size())])
	var trees: PackedVector2Array = td.trees
	var trng := RandomNumberGenerator.new()
	trng.seed = hash(t) ^ (cell.x * 31 + cell.y)
	for p in trees:
		if cell_of(p, dims) == cell:
			tree_pts.append([Vector3(p.x - cc.x, 0.0, -(p.y - cc.y)), trng.randi() % maxi(1, tree_meshes.size())])
	_share(B)
	var meshes: Array = B.commit(root, true)
	for mi in meshes:
		_vis(mi, 0.0, 0.0, near_end, near_margin)
	if bulb_buf.size() > 0:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = bulb_mesh
		mm.instance_count = bulb_buf.size() / 20
		mm.buffer = bulb_buf
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Bulbs"
		mmi.multimesh = mm
		mmi.material_override = bulb_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vis(mmi, 0.0, 0.0, near_end, near_margin)
		root.add_child(mmi)
	if not tree_pts.is_empty() and not tree_meshes.is_empty():
		var per: Array = []
		for i in tree_meshes.size():
			per.append([])
		for e in tree_pts:
			per[e[1]].append(e[0])
		for v in tree_meshes.size():
			if per[v].is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = tree_meshes[v]
			mm.instance_count = per[v].size()
			var buf := PackedFloat32Array()
			for i in per[v].size():
				var p: Vector3 = per[v][i]
				var a := trng.randf() * TAU
				var s := trng.randf_range(0.8, 1.2)
				var bas := Basis(Vector3.UP, a).scaled(Vector3(s, s, s))
				buf.append_array(_xf12(Transform3D(bas, p)))
			mm.buffer = buf
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Gums_%d" % v
			mmi.multimesh = mm
			_vis(mmi, 0.0, 0.0, near_end, near_margin)
			root.add_child(mmi)
	_ulk()
	# collision: split into ~col_chunk squares so each shape is small to build on the main thread
	var col: Array = []
	var faces: PackedVector3Array = COL.faces_all()
	if faces.size() > 0:
		var parts := {}
		for i in range(0, faces.size(), 3):
			var m := (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0
			var k := Vector2i(floori(m.x / col_chunk), floori(m.z / col_chunk))
			if not parts.has(k):
				parts[k] = []
			var arr: Array = parts[k]
			arr.append(faces[i])
			arr.append(faces[i + 1])
			arr.append(faces[i + 2])
		for k in parts:
			col.append(PackedVector3Array(parts[k]))
	var tpos: Array = []
	for e in tree_pts:
		tpos.append(e[0])
	return {"node": root, "col": col, "trees": tpos, "count": n, "tris": B.tri_count, "styles": styles}


func _share(B) -> void:
	# Re-use one material per key across cells (house_gen makes fresh roof / brick materials per batch).
	var mats: Dictionary = B._mats
	for k in mats:
		if _shared_mats.has(k):
			mats[k] = _shared_mats[k]
		else:
			_shared_mats[k] = mats[k]


## MultiMesh buffer rows for one Transform3D (packed arrays are copy-on-write values: build and append).
static func _xf12(x: Transform3D) -> PackedFloat32Array:
	var b := x.basis
	return PackedFloat32Array([b.x.x, b.y.x, b.z.x, x.origin.x, b.x.y, b.y.y, b.z.y, x.origin.y, b.x.z, b.y.z, b.z.z, x.origin.z])


func _bulbs(loop: PackedVector3Array, closed: bool, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	# same strings as town.gd _add_bg_bulbs (0.6 m spacing, warm or multicolour, a little sag)
	var pts := PackedVector3Array(loop)
	if closed and pts.size() > 0:
		pts.append(pts[0])
	var warm := rng.randf() < 0.7
	var palette: Array = [Color(1.0, 0.78, 0.45), Color(1.0, 0.9, 0.7)] if warm else MULTI
	var n := 0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var L := a.distance_to(b)
		var cnt := maxi(1, int(L / 0.6))
		for k in cnt:
			var tt := (float(k) + 0.5) / float(cnt)
			var p := a.lerp(b, tt) + Vector3.DOWN * (0.06 + 0.08 * sin(tt * PI * maxf(1.0, L / 1.4)) * 0.5)
			var bas := Basis(Vector3.UP, rng.randf_range(0, TAU)) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3))
			var o := buf.size()
			buf.append_array(_xf12(Transform3D(bas, p)))
			buf.resize(o + 20)
			var c: Color = palette[n % palette.size()]
			buf[o + 12] = c.r
			buf[o + 13] = c.g
			buf[o + 14] = c.b
			buf[o + 15] = 1.0
			buf[o + 16] = rng.randf()
			buf[o + 17] = rng.randf()
			buf[o + 18] = 0.0
			buf[o + 19] = 0.0
			n += 1
	return buf


# --------------------------------------------------------------------------------------------- mid

## What house_gen would build, cheaply: W, D, frame, wall top, colours, pitch (replays the same rng calls).
func _shape_of(b: Dictionary, ctx: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_of(b, town_seed)
	var style := Style.pick(b, rng, ctx[0], ctx[1])
	var size: Array = b.obb.size
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
	var fz: Vector3
	if b.get("front") != null:
		fz = Vector3(float(b.front[0]), 0.0, -float(b.front[1])).normalized()
	else:
		var a := float(b.obb.angle)
		fz = Vector3(cos(a), 0, -sin(a))
	rng.randf()  # lean x (house_gen.build)
	rng.randf()  # lean z
	var lv = b.get("levels")
	var levels := 1 if lv == null else clampi(int(round(float(lv))), 1, 3)
	var out := {"style": style, "W": W, "D": D, "fz": fz, "pitch": 0.0, "flat": true, "floor": 0.3}
	var wall := Color(0.8, 0.8, 0.8)
	var roof := Color(0.3, 0.3, 0.36)
	var top := 3.0
	match style:
		"queenslander", "cottage", "brick", "fibro", "modern":
			rng.randi()  # trim
			var fy := 0.3
			match style:
				"queenslander":
					fy = rng.randf_range(1.7, 2.4)
					wall = HouseGen.QLD_WALLS[rng.randi() % HouseGen.QLD_WALLS.size()]
					roof = HouseGen.IRON_ROOFS[rng.randi() % HouseGen.IRON_ROOFS.size()]
					top = fy + (2.85 * 2.0 if levels >= 2 else 2.85)
					out.pitch = 32.0
				"cottage":
					fy = rng.randf_range(1.1, 1.8)
					wall = HouseGen.QLD_WALLS[rng.randi() % HouseGen.QLD_WALLS.size()]
					roof = HouseGen.IRON_ROOFS[rng.randi() % HouseGen.IRON_ROOFS.size()]
					top = fy + 2.85
					out.pitch = 36.0
				"brick":
					wall = HouseGen.BRICKS[rng.randi() % HouseGen.BRICKS.size()]
					roof = HouseGen.TILE_ROOFS[rng.randi() % HouseGen.TILE_ROOFS.size()]
					top = 0.3 + 2.7 * levels
					out.pitch = 22.0
				"fibro":
					fy = rng.randf_range(0.6, 0.9)
					wall = HouseGen.FIBRO_WALLS[rng.randi() % HouseGen.FIBRO_WALLS.size()]
					roof = HouseGen.IRON_ROOFS[rng.randi() % HouseGen.IRON_ROOFS.size()]
					top = fy + 2.6
					out.pitch = 21.0
				_:
					wall = HouseGen.RENDER_WALLS[rng.randi() % HouseGen.RENDER_WALLS.size()]
					top = 0.2 + 2.9 * maxi(levels, 2)
			out.floor = fy
			out.flat = style == "modern"
		"shop":
			wall = HouseGen.RENDER_WALLS[rng.randi() % HouseGen.RENDER_WALLS.size()].lerp(Color(0.9, 0.8, 0.6), 0.3)
			top = maxf(4.4, 3.6 * (levels if lv != null else 1))
		"apartments":
			wall = HouseGen.BRICKS[rng.randi() % HouseGen.BRICKS.size()]
			top = 2.9 * maxi(3, int(round(float(lv))) if lv != null else 3)
		"hall":
			wall = Color(0.85, 0.8, 0.7)
			top = 6.0
			roof = HouseGen.TILE_ROOFS[rng.randi() % HouseGen.TILE_ROOFS.size()]
			out.flat = false
			out.pitch = 30.0
		_:
			wall = Color(0.58, 0.62, 0.56)
			top = 2.6
	var h = b.get("height")
	if style in ["shop", "apartments", "hall", "shed"] and h != null and float(h) > 3.0:
		top = float(h)
	elif lv != null and float(lv) > 3.0 and style in ["shop", "apartments", "hall"]:
		top = 3.2 * float(lv)
	out.wall = wall
	out.roof = roof
	out.top = top
	out.lit = rng.randf_range(0.35, 0.8)
	return out


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, hint: Vector3, col: Color) -> void:
	_tri(st, a, b, c, hint, col)
	_tri(st, a, c, d, hint, col)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, hint: Vector3, col: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-10:
		return
	if n.dot(hint) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(a)
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(c)


## One simplified building into st. origin = footprint centre (local), s = _shape_of().
func _mid_building(st: SurfaceTool, origin: Vector3, s: Dictionary, rng: RandomNumberGenerator, windows := true) -> void:
	var fz: Vector3 = s.fz
	var fx := Vector3.UP.cross(fz).normalized()
	var hw := float(s.W) * 0.5 - 0.3
	var hd := float(s.D) * 0.5 - 0.3
	var top := float(s.top)
	var wall: Color = s.wall
	var roof: Color = s.roof
	var P := func(x: float, y: float, z: float) -> Vector3: return origin + fx * x + Vector3.UP * y + fz * z
	var dark := wall.darkened(0.12)
	_quad(st, P.call(-hw, 0, hd), P.call(hw, 0, hd), P.call(hw, top, hd), P.call(-hw, top, hd), fz, wall)
	_quad(st, P.call(-hw, 0, -hd), P.call(hw, 0, -hd), P.call(hw, top, -hd), P.call(-hw, top, -hd), -fz, dark)
	_quad(st, P.call(hw, 0, -hd), P.call(hw, 0, hd), P.call(hw, top, hd), P.call(hw, top, -hd), fx, wall.darkened(0.05))
	_quad(st, P.call(-hw, 0, -hd), P.call(-hw, 0, hd), P.call(-hw, top, hd), P.call(-hw, top, -hd), -fx, dark)
	if bool(s.flat):
		_quad(st, P.call(-hw, top, -hd), P.call(hw, top, -hd), P.call(hw, top, hd), P.call(-hw, top, hd), Vector3.UP, roof)
	else:
		var ex := hw + 0.45
		var ez := hd + 0.45
		var r := maxf(0.0, minf(ex, ez) - 1.2)  # Santa deck on top, like the near houses
		var rise := r * tan(deg_to_rad(float(s.pitch)))
		var y1 := top + rise
		var e := [P.call(-ex, top, -ez), P.call(ex, top, -ez), P.call(ex, top, ez), P.call(-ex, top, ez)]
		var t := [P.call(-ex + r, y1, -ez + r), P.call(ex - r, y1, -ez + r), P.call(ex - r, y1, ez - r), P.call(-ex + r, y1, ez - r)]
		var hints := [-fz + Vector3.UP, fx + Vector3.UP, fz + Vector3.UP, -fx + Vector3.UP]
		for i in 4:
			var j := (i + 1) % 4
			_quad(st, e[i], e[j], t[j], t[i], hints[i], roof.darkened(0.08 * float(i % 2)))
		_quad(st, t[0], t[1], t[2], t[3], Vector3.UP, HouseGen.DECK)
		_quad(st, e[0], e[1], e[2], e[3], Vector3.DOWN, HouseGen.SOFFIT)
	if not windows:
		return
	# lit windows (vertex alpha = glow)
	var fy := float(s.floor)
	var storeys := maxi(1, int((top - fy) / 2.9))
	var tall := storeys > 3
	for side in [1.0, -1.0]:
		var zz: float = hd * side + 0.04 * side
		var nrm: Vector3 = fz * side
		for stn in mini(storeys, 40):
			var y0 := fy + 0.9 + stn * 2.9
			if y0 + 1.2 > top:
				break
			if tall:
				if rng.randf() < float(s.lit):
					var lit_c := Color(WARM.r, WARM.g, WARM.b, 1.0) if rng.randf() < 0.8 else Color(0.7, 0.85, 1.0, 1.0)
					_quad(st, P.call(-hw + 0.6, y0, zz), P.call(hw - 0.6, y0, zz), P.call(hw - 0.6, y0 + 1.1, zz), P.call(-hw + 0.6, y0 + 1.1, zz), nrm, lit_c)
				continue
			var nw := maxi(1, int((hw * 2.0 - 1.0) / 2.6))
			for k in nw:
				var cx := -hw + (float(k) + 0.5) * (hw * 2.0) / float(nw)
				var lit := rng.randf() < float(s.lit)
				var wc := Color(WARM.r, WARM.g, WARM.b, 1.0) if lit else Color(HouseGen.GLASS_DARK.r, HouseGen.GLASS_DARK.g, HouseGen.GLASS_DARK.b, 0.0)
				_quad(st, P.call(cx - 0.45, y0, zz), P.call(cx + 0.45, y0, zz), P.call(cx + 0.45, y0 + 1.1, zz), P.call(cx - 0.45, y0 + 1.1, zz), nrm, wc)


func build_mid(t: Vector2i, cell: Vector2i) -> Dictionary:
	var td: Dictionary = data.tile(t)
	var root := Node3D.new()
	if td.is_empty():
		return {"node": root}
	var dims := Geo.tile_dims(t)
	var cc := cell_centre(cell, dims)
	root.name = "Mid_%d_%d" % [cell.x, cell.y]
	root.position = Vector3(cc.x, 0.0, -cc.y)
	var ctx := _ctx(t)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	var n := 0
	for b in td.buildings:
		var c: Array = b.obb.c
		if cell_of(Vector2(c[0], c[1]), dims) != cell:
			continue
		var s := _shape_of(b, ctx)
		rng.seed = seed_of(b, town_seed) ^ 0x5a17
		_mid_building(st, Vector3(float(c[0]) - cc.x, 0.0, -(float(c[1]) - cc.y)), s, rng)
		n += 1
	if n > 0:
		var mi := MeshInstance3D.new()
		mi.name = "MidMesh"
		_lk()
		mi.mesh = st.commit()
		_ulk()
		mi.material_override = lod_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vis(mi, 0.0, 0.0, mid_end, mid_margin)
		root.add_child(mi)
	return {"node": root, "count": n}


# --------------------------------------------------------------------------------------------- roads

func build_roads(t: Vector2i) -> Dictionary:
	var td: Dictionary = data.tile(t)
	var root := Node3D.new()
	root.name = "Roads"
	if td.is_empty() or (td.roads as Array).is_empty():
		return {"node": root}
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in td.roads:
		var typ := int(r[0])
		var w := float(r[1])
		var pts: PackedVector2Array = r[3]
		var rank := 0 if typ <= 4 or (typ >= 10 and typ <= 14) else (1 if typ in [5, 6, 7, 9, 15] else 2)
		var y := 0.05 + (2 - rank) * 0.006
		var col: Color = ROAD_COLS[rank]
		if typ == 16:  # track: dirt
			col = Color(0.42, 0.33, 0.22)
		_ribbon(st, pts, w, y, col)
	var mi := MeshInstance3D.new()
	_lk()
	mi.mesh = st.commit()
	_ulk()
	mi.material_override = lod_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis(mi, 0.0, 0.0, road_end, mid_margin)
	root.add_child(mi)
	return {"node": root}


static func _ribbon(st: SurfaceTool, pts: PackedVector2Array, width: float, y: float, col: Color) -> void:
	var n := pts.size()
	if n < 2:
		return
	var hw := width * 0.5
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in n:
		var t: Vector2
		if i == 0:
			t = pts[1] - pts[0]
		elif i == n - 1:
			t = pts[n - 1] - pts[n - 2]
		else:
			t = (pts[i] - pts[i - 1]).normalized() + (pts[i + 1] - pts[i]).normalized()
		t = t.normalized()
		var nrm := Vector2(-t.y, t.x)
		var s := 1.0
		if i > 0 and i < n - 1:
			var seg := (pts[i] - pts[i - 1]).normalized()
			s = 1.0 / maxf(absf(Vector2(-seg.y, seg.x).dot(nrm)), 0.5)
		left.append(pts[i] + nrm * hw * s)
		right.append(pts[i] - nrm * hw * s)
	for i in n - 1:
		_quad(st, Vector3(left[i].x, y, -left[i].y), Vector3(left[i + 1].x, y, -left[i + 1].y),
				Vector3(right[i + 1].x, y, -right[i + 1].y), Vector3(right[i].x, y, -right[i].y), Vector3.UP, col)


# --------------------------------------------------------------------------------------------- far

func build_far(t: Vector2i) -> Dictionary:
	var td: Dictionary = data.tile(t)
	var root := Node3D.new()
	root.name = "Far"
	if td.is_empty():
		return {"node": root}
	var ctx := _ctx(t)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(t) ^ 0x2f
	var buf := PackedFloat32Array()
	var bl: Array = td.buildings
	var stride := maxi(1, int(ceil(bl.size() / 1400.0)))
	var sky := SurfaceTool.new()
	sky.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_sky := 0
	for i in range(0, bl.size()):
		var b: Dictionary = bl[i]
		var c: Array = b.obb.c
		var p := Vector3(float(c[0]), 0.0, -float(c[1]))
		var tall := (b.get("height") != null and float(b.height) >= 20.0) or (b.get("levels") != null and float(b.levels) >= 6.0)
		if tall:
			var s := _shape_of(b, ctx)
			if float(s.top) >= 18.0:
				_mid_building(sky, p, s, rng, true)
				n_sky += 1
		if i % stride != 0 or String(b.kind) == "shed":
			continue
		var hh := 4.0 if b.get("levels") == null else float(b.levels) * 3.0 + 1.0
		var col: Color = WARM if rng.randf() < 0.62 else MULTI[rng.randi() % MULTI.size()]
		buf.append_array(_dot(p + Vector3(rng.randf_range(-2, 2), hh, rng.randf_range(-2, 2)), col, rng.randf()))
	for r in td.roads:
		var typ := int(r[0])
		if typ == 8 or typ == 16:  # service roads + tracks: unlit
			continue
		var pts: PackedVector2Array = r[3]
		var carry := rng.randf() * 45.0
		for k in pts.size() - 1:
			var a := pts[k]
			var bpt := pts[k + 1]
			var L := a.distance_to(bpt)
			var d := carry
			while d < L:
				var q := a.lerp(bpt, d / L)
				buf.append_array(_dot(Vector3(q.x, 7.0, -q.y), STREETLIGHT, 0.4 + rng.randf() * 0.3))
				d += 45.0
			carry = d - L
	_lk()
	if buf.size() > 0:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = dot_mesh
		mm.instance_count = buf.size() / 20
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Lights"
		mmi.multimesh = mm
		mmi.material_override = dots_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vis(mmi, far_begin, far_margin, far_end, 800.0)
		root.add_child(mmi)
	if n_sky > 0:
		var mi := MeshInstance3D.new()
		mi.name = "Skyline"
		mi.mesh = sky.commit()
		mi.material_override = lod_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vis(mi, mid_end, mid_margin, far_end * 1.6, 1200.0)
		root.add_child(mi)
	_ulk()
	return {"node": root, "dots": buf.size() / 20, "skyline": n_sky}


static func _dot(p: Vector3, c: Color, sz: float) -> PackedFloat32Array:
	return PackedFloat32Array([1.0, 0.0, 0.0, p.x, 0.0, 1.0, 0.0, p.y, 0.0, 0.0, 1.0, p.z, c.r, c.g, c.b, 1.0, sz, 0.0, 0.0, 0.0])


# --------------------------------------------------------------------------------------------- ground

func build_ground(t: Vector2i) -> Dictionary:
	var td: Dictionary = data.tile(t)
	var root := Node3D.new()
	root.name = "Ground"
	if td.is_empty() or (td.ground as PackedByteArray).size() != 1024:
		return {"node": root}
	var img := Image.create_from_data(32, 32, false, Image.FORMAT_R8, td.ground)
	_lk()
	var tex := ImageTexture.create_from_image(img)
	var mat := ShaderMaterial.new()
	mat.shader = ground_shader
	mat.set_shader_parameter("classes", tex)
	var dims := Geo.tile_dims(t)
	var pm := PlaneMesh.new()
	pm.size = dims
	_ulk()
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis(mi, 0.0, 0.0, ground_end, 400.0)
	root.add_child(mi)
	return {"node": root}


## Block overview ground (4 cells per tile, ~250 m): texture + a 24 x 24 grid mesh projected through the
## origin snapshot (lat0, lon0) the streamer had when it asked, relative to the block centre. All off-thread.
func build_block(key: String, lat0: float, lon0: float, mat_in: Material = null) -> Dictionary:
	var b: Dictionary = data.block(key)
	if b.is_empty():
		return {"empty": true}
	var g := Geo.new(lat0, lon0)
	var bx := int(b.bx)
	var by := int(b.by)
	var N := 24
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := g.to_world(by + 0.5, bx + 0.5)
	for j in N:
		for i in N:
			var corners := []
			for k in 4:
				var u := float(i + (1 if k == 1 or k == 2 else 0)) / N
				var v := float(j + (1 if k >= 2 else 0)) / N
				corners.append([g.to_world(by + 1.0 - v, bx + u, -0.3) - c, Vector2(u, v)])
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.UP)
				st.set_uv(corners[k][1])
				st.add_vertex(corners[k][0])
	if mat_in != null:
		_lk()
		var m2 := st.commit()
		_ulk()
		return {"mesh": m2, "mat": mat_in, "built_at": PackedFloat64Array([lat0, lon0])}
	var img := Image.create_from_data(int(b.ow), int(b.oh), false, Image.FORMAT_R8, b.ov)
	_lk()
	var tex := ImageTexture.create_from_image(img)
	var mat := ShaderMaterial.new()
	mat.shader = ground_shader
	mat.set_shader_parameter("classes", tex)
	var mesh := st.commit()
	_ulk()
	return {"mesh": mesh, "mat": mat, "built_at": PackedFloat64Array([lat0, lon0]), "tiles": (b.tiles as Dictionary).size()}
