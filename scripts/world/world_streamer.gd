extends Node3D
## Seamless chunk streaming for the whole-of-Australia world (Minecraft / No Man's Sky style: no loading
## screens, no zones). Around a focus node (the sleigh) it keeps rings of LOD:
##   near  < near_radius   full stylised houses + collision   (per ~250 m cell)
##   mid   < mid_radius    simple coloured buildings           (per cell)
##   roads < road_radius   asphalt                             (per ~1 km tile)
##   ground< ground_radius landuse / water raster              (per tile)
##   far   < far_radius    impostor lights + skyline           (per tile)
##   block < block_radius  250 m overview ground per 1 x 1 deg block, under everything
## All building happens in WorkerThreadPool jobs (world_builder.gd). The main thread only attaches finished
## nodes and creates collision shapes, inside apply_budget_ms per frame. LOD changes are dithered cross-fades
## (visibility ranges with FADE_SELF), and a mid cell only starts hiding once its near cell is attached, so
## nothing pops or leaves holes. Floating origin: rebase() moves the lat/lon origin to the focus and re-places
## every loaded tile from its own lat/lon, so coordinates never grow past a couple of kilometres.

const Geo := preload("res://scripts/world/geo.gd")
const WorldData := preload("res://scripts/world/world_data.gd")
const Builder := preload("res://scripts/world/world_builder.gd")
const Props := preload("res://scripts/town/town_props.gd")
const BULB_SHADER := preload("res://shaders/bulb.gdshader")

const K_FAR := 0
const K_GROUND := 1
const K_ROADS := 2
const K_MID := 3
const K_NEAR := 4
const K_BLOCK := 5
const KIND_NAMES := ["far", "ground", "roads", "mid", "near", "blocks"]
const EMPTY := {}

signal settled  ## emitted when nothing is queued, running or waiting to be applied

@export var near_radius := 380.0
@export var near_unload := 520.0
@export var near_fade := 410.0  ## camera distance where near cross-fades into mid
@export var fade_margin := 30.0
@export var mid_radius := 2500.0
@export var mid_unload := 2900.0
@export var mid_fade := 2300.0
@export var road_radius := 2700.0
@export var road_unload := 3100.0
@export var ground_radius := 4300.0
@export var ground_unload := 4900.0
@export var far_radius := 9000.0
@export var far_unload := 10000.0
@export var block_radius := 95000.0
@export var lookahead_s := 2.5
@export var apply_budget_ms := 2.0
@export var collision_budget_ms := 1.5
@export var max_jobs := 6
@export var update_interval := 0.15

var geo := Geo.new()
var data := WorldData.new()
var builder: Builder
var focus: Node3D
var tiles: Dictionary = {}  # Vector2i -> {"node", "lat", "lon", "items": {name: {"node", "bodies"}}}
var blocks: Dictionary = {}  # Vector2i -> {"node", "mat", "bx", "by"}
var ready_ok := false
var stats := {"jobs_done": 0, "applied": 0, "col_shapes": 0, "rebases": 0, "max_apply_ms": 0.0, "max_update_ms": 0.0,
		"max_col_ms": 0.0, "dropped": 0}

var _queue: Array = []  # job dicts sorted by priority
var _inflight: Dictionary = {}  # Vector4i job id -> true
var _near_busy := false
var _results: Array = []
var _res_mx := Mutex.new()
var _tasks: Array[int] = []
var _col_queue: Array = []  # [tile, item_name, PackedVector3Array | trees Array]
var _t_update := 0.0
var _wanted: Dictionary = {}  # Vector4i(ix, iy, kind, cell) -> true for everything inside the unload radii
var _dirty := true
var frame_ms_log: PackedFloat32Array = PackedFloat32Array()


func setup(lat: float, lon: float) -> bool:
	geo.set_origin(lat, lon)
	if not data.load_index():
		push_error("[world] no data/world/index.json: run tools/world/world_tiles.py (see WORLD-STREAMING.md)")
		return false
	builder = Builder.new(data)
	builder.near_end = near_fade
	builder.near_margin = fade_margin
	builder.mid_end = mid_fade
	builder.road_end = road_radius - 150.0
	builder.far_begin = mid_fade - 400.0
	builder.far_end = far_radius - 600.0
	builder.ground_end = ground_radius - 400.0
	var lod := ShaderMaterial.new()
	lod.shader = preload("res://shaders/world_lod.gdshader")
	builder.lod_mat = lod
	var dm := ShaderMaterial.new()
	dm.shader = preload("res://shaders/world_dots.gdshader")
	builder.dots_mat = dm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	builder.dot_mesh = q
	builder.ground_shader = preload("res://shaders/world_ground.gdshader")
	builder.bulb_mesh = Props.lowpoly_bulb()
	var bm := ShaderMaterial.new()
	bm.shader = BULB_SHADER
	bm.set_shader_parameter("energy", 1.25)
	bm.set_shader_parameter("max_distance_scale", 2.0)
	builder.bulb_mat = bm
	for v in 3:
		builder.tree_meshes.append(Props.gum_tree(v))
	ready_ok = true
	return true


func _exit_tree() -> void:
	for id in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()
	for r in _results:  # finished but never attached
		if r.has("node") and is_instance_valid(r.node):
			(r.node as Node).free()
	_results.clear()


## Busy = anything queued, running or not yet attached.
func busy() -> bool:
	_res_mx.lock()
	var r := _results.size()
	_res_mx.unlock()
	return _dirty or not _queue.is_empty() or not _inflight.is_empty() or r > 0 or not _col_queue.is_empty()


func counts() -> Dictionary:
	var c := {"tiles": tiles.size(), "near": 0, "mid": 0, "roads": 0, "ground": 0, "far": 0, "blocks": blocks.size(), "bodies": 0}
	for t in tiles:
		var items: Dictionary = tiles[t].items
		for nm in items:
			c[KIND_NAMES[nm.x]] += 1
			c.bodies += (items[nm].bodies as Array).size()
	return c


# --------------------------------------------------------------------------------------------- frame

func _process(delta: float) -> void:
	if not ready_ok or focus == null:
		return
	var f0 := Time.get_ticks_usec()
	_t_update -= delta
	var updated := false
	if _t_update <= 0.0:
		_t_update = update_interval
		var u0 := Time.get_ticks_usec()
		_update_wanted()
		updated = true
		stats.max_update_ms = maxf(stats.max_update_ms, (Time.get_ticks_usec() - u0) / 1000.0)
	_dispatch()
	# a frame that re-planned the rings skips attaching, so the two costs never stack in one frame
	if not updated:
		var a0 := Time.get_ticks_usec()
		_apply_results()
		stats.max_apply_ms = maxf(stats.max_apply_ms, (Time.get_ticks_usec() - a0) / 1000.0)
		var c0 := Time.get_ticks_usec()
		_apply_collision()
		stats.max_col_ms = maxf(stats.max_col_ms, (Time.get_ticks_usec() - c0) / 1000.0)
	frame_ms_log.append((Time.get_ticks_usec() - f0) / 1000.0)
	if frame_ms_log.size() > 20000:
		frame_ms_log = frame_ms_log.slice(10000)
	if not busy():
		settled.emit()


func _focus_point() -> Vector3:
	var p := focus.global_position
	if focus.has_meta("velocity"):
		var v2: Vector3 = focus.get_meta("velocity") * lookahead_s
		v2.y = 0.0
		p += v2.limit_length(700.0)
	elif focus is RigidBody3D:
		var v := (focus as RigidBody3D).linear_velocity * lookahead_s
		v.y = 0.0
		p += v.limit_length(700.0)
	p.y = 0.0
	return p


static func _rect_dist(p: Vector3, c: Vector3, half: Vector2) -> float:
	var dx := maxf(absf(p.x - c.x) - half.x, 0.0)
	var dz := maxf(absf(p.z - c.z) - half.y, 0.0)
	return sqrt(dx * dx + dz * dz)


## Decide what should be loaded (integer keys only: this runs every update_interval on the main thread).
func _update_wanted() -> void:
	_dirty = false
	var p := _focus_point()
	var ll := geo.to_latlon(p)
	var lat: float = ll[0]
	var lon: float = ll[1]
	var want: Array = []
	var keep := {}
	for by in range(floori(lat) - 1, floori(lat) + 2):
		for bx in range(floori(lon) - 1, floori(lon) + 2):
			var bk := Vector2i(bx, by)
			var key := Geo.block_key(bk)
			if not data.has_block(key):
				continue
			var bc := geo.to_world(by + 0.5, bx + 0.5)
			var d := _rect_dist(p, bc, Vector2(Geo.DEG * cos(deg_to_rad(by + 0.5)) * 0.5, Geo.DEG * 0.5))
			if d < block_radius:
				var id := Vector4i(bx, by, K_BLOCK, 0)
				keep[id] = true
				if not blocks.has(bk):
					want.append([-1.0, id, key, geo.lat0, geo.lon0])
				elif blocks[bk].get("refresh", false):
					blocks[bk].refresh = false
					want.append([-1.0, Vector4i(bx, by, K_BLOCK, 1), key, geo.lat0, geo.lon0, blocks[bk].node.material_override])
	# tile centres from a local linearisation around the focus (exact enough for ring tests)
	var kx := Geo.DEG * cos(deg_to_rad(lat))
	var dlat := far_unload / Geo.DEG
	var dlon := far_unload / kx
	var iy0 := floori((lat - dlat) * Geo.TLAT)
	var iy1 := floori((lat + dlat) * Geo.TLAT)
	var ix0 := floori((lon - dlon) * Geo.TLON)
	var ix1 := floori((lon + dlon) * Geo.TLON)
	var tw := kx / Geo.TLON
	var th := Geo.DEG / Geo.TLAT
	var half := Vector2(tw, th) * 0.5
	var chalf := half / Builder.CPT
	var bcache := {}
	for iy in range(iy0, iy1 + 1):
		var tz := p.z + ((lat - (iy + 0.5) / Geo.TLAT) * Geo.DEG)
		for ix in range(ix0, ix1 + 1):
			var bk := Vector2i(floori(ix / float(Geo.TLON)), floori(iy / float(Geo.TLAT)))
			var tbl = bcache.get(bk)
			if tbl == null:
				var b = data.block_if_loaded(Geo.block_key(bk))
				tbl = {} if b == null or (b as Dictionary).is_empty() else b.tiles
				bcache[bk] = tbl
			var t := Vector2i(ix, iy)
			var e = (tbl as Dictionary).get(t)
			if e == null:
				continue
			var tx := p.x + (((ix + 0.5) / Geo.TLON - lon) * kx)
			var cw := Vector3(tx, 0.0, tz)
			var d := _rect_dist(p, cw, half)
			if d > far_unload:
				continue
			var nb := int(e[3])
			var loaded: Dictionary = tiles[t].items if tiles.has(t) else EMPTY
			if nb > 0:
				keep[Vector4i(ix, iy, K_FAR, -1)] = true
				if d < far_radius and not loaded.has(Vector2i(K_FAR, -1)):
					want.append([d * 1.4 + 300.0, Vector4i(ix, iy, K_FAR, -1)])
			if (int(e[4]) & 1) != 0 and d < ground_unload:
				keep[Vector4i(ix, iy, K_GROUND, -1)] = true
				if d < ground_radius and not loaded.has(Vector2i(K_GROUND, -1)):
					want.append([d * 0.9, Vector4i(ix, iy, K_GROUND, -1)])
			if d < road_unload:
				keep[Vector4i(ix, iy, K_ROADS, -1)] = true
				if d < road_radius and not loaded.has(Vector2i(K_ROADS, -1)):
					want.append([d * 1.05, Vector4i(ix, iy, K_ROADS, -1)])
			if nb == 0 or d > mid_unload:
				continue
			for cy in Builder.CPT:
				for cx in Builder.CPT:
					var cwc := cw + Vector3(((cx + 0.5) / Builder.CPT - 0.5) * tw, 0.0, -((cy + 0.5) / Builder.CPT - 0.5) * th)
					var dc := _rect_dist(p, cwc, chalf)
					if dc >= mid_unload:
						continue
					var cell := cx * Builder.CPT + cy
					keep[Vector4i(ix, iy, K_MID, cell)] = true
					if dc < mid_radius and not loaded.has(Vector2i(K_MID, cell)):
						want.append([dc, Vector4i(ix, iy, K_MID, cell)])
					if dc < near_unload:
						keep[Vector4i(ix, iy, K_NEAR, cell)] = true
						if dc < near_radius and not loaded.has(Vector2i(K_NEAR, cell)):
							want.append([dc * 0.5 - 50.0, Vector4i(ix, iy, K_NEAR, cell)])
	_wanted = keep
	for t in tiles.keys():
		var rec: Dictionary = tiles[t]
		for nm in (rec.items as Dictionary).keys():
			if not keep.has(Vector4i(t.x, t.y, nm.x, nm.y)):
				_unload_item(t, nm)
		if (rec.items as Dictionary).is_empty():
			(rec.node as Node).queue_free()
			tiles.erase(t)
	for bk in blocks.keys():
		if not keep.has(Vector4i(bk.x, bk.y, K_BLOCK, 0)) and not _inflight.has(Vector4i(bk.x, bk.y, K_BLOCK, 1)):
			(blocks[bk].node as Node).queue_free()
			blocks.erase(bk)
	var q: Array = []
	for j in want:
		if not _inflight.has(j[1]):
			q.append(j)
	q.sort_custom(func(a, b): return a[0] < b[0])
	_queue = q


func _dispatch() -> void:
	var i := 0
	while i < _queue.size() and _inflight.size() < max_jobs + 1:
		var j: Array = _queue[i]
		var id: Vector4i = j[1]
		var is_near := id.z == K_NEAR
		if is_near and _near_busy:
			i += 1
			continue
		if not is_near and _inflight.size() - (1 if _near_busy else 0) >= max_jobs:
			i += 1
			continue
		_queue.remove_at(i)
		_inflight[id] = true
		if is_near:
			_near_busy = true
		_tasks.append(WorkerThreadPool.add_task(_run_job.bind(j), is_near, "world job"))
	var keep_tasks: Array[int] = []
	for tid in _tasks:
		if not WorkerThreadPool.is_task_completed(tid):
			keep_tasks.append(tid)
		else:
			WorkerThreadPool.wait_for_task_completion(tid)
	_tasks = keep_tasks


func _run_job(j: Array) -> void:
	var id: Vector4i = j[1]
	var t := Vector2i(id.x, id.y)
	var cell := Vector2i(id.w / Builder.CPT, id.w % Builder.CPT) if id.w >= 0 else Vector2i.ZERO
	var r: Dictionary
	match id.z:
		K_NEAR:
			r = builder.build_near(t, cell)
		K_MID:
			r = builder.build_mid(t, cell)
		K_ROADS:
			r = builder.build_roads(t)
		K_GROUND:
			r = builder.build_ground(t)
		K_FAR:
			r = builder.build_far(t)
		K_BLOCK:
			r = builder.build_block(String(j[2]), float(j[3]), float(j[4]), j[5] if j.size() > 5 else null)
	r["id"] = id
	_res_mx.lock()
	_results.append(r)
	_res_mx.unlock()


func _apply_results() -> void:
	var t0 := Time.get_ticks_usec()
	var budget := int(apply_budget_ms * 1000.0)
	while true:
		_res_mx.lock()
		var r = _results.pop_front() if not _results.is_empty() else null
		_res_mx.unlock()
		if r == null:
			break
		var id: Vector4i = r.id
		_inflight.erase(id)
		if id.z == K_NEAR:
			_near_busy = false
		stats.jobs_done += 1
		var k0 := Time.get_ticks_usec()
		_apply(r, id)
		var kn: String = "apply_ms_" + String(KIND_NAMES[id.z])
		stats[kn] = maxf(float(stats.get(kn, 0.0)), (Time.get_ticks_usec() - k0) / 1000.0)
		if Time.get_ticks_usec() - t0 > budget:
			break


func _tile_rec(t: Vector2i) -> Dictionary:
	if tiles.has(t):
		return tiles[t]
	var tc := Geo.tile_centre(t)
	var n := Node3D.new()
	n.name = "Tile_%d_%d" % [t.x, t.y]
	add_child(n)
	n.position = geo.to_world(tc[0], tc[1])
	n.reset_physics_interpolation()
	var rec := {"node": n, "lat": tc[0], "lon": tc[1], "items": {}}
	tiles[t] = rec
	return rec


func _apply(r: Dictionary, id: Vector4i) -> void:
	if id.z == K_BLOCK:
		var bk := Vector2i(id.x, id.y)
		if r.has("empty"):
			return
		if id.w == 1:  # re-projected mesh for a block we already show
			if blocks.has(bk):
				_set_block_mesh(blocks[bk], r)
			return
		if not _wanted.has(id):
			return
		var mi := MeshInstance3D.new()
		mi.name = "Block_%d_%d" % [id.y, id.x]
		mi.material_override = r.mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		blocks[bk] = {"node": mi, "bx": bk.x, "by": bk.y}
		_set_block_mesh(blocks[bk], r)
		_dirty = true  # its tiles can be wanted now: re-plan next frame
		_t_update = 0.0
		return
	var node: Node3D = r.node
	if not _wanted.has(id):
		node.free()
		stats.dropped += 1
		return
	var t := Vector2i(id.x, id.y)
	var rec := _tile_rec(t)
	var nm := Vector2i(id.z, id.w)
	if (rec.items as Dictionary).has(nm):
		node.free()
		return
	(rec.node as Node3D).add_child(node)
	rec.items[nm] = {"node": node, "bodies": []}
	stats.applied += 1
	if id.z == K_NEAR:
		for faces in r.col:
			_col_queue.append([t, nm, faces])
		var tr: Array = r.trees
		var k := 0
		while k < tr.size():  # small tree bodies so no single attach blows the frame budget
			_col_queue.append([t, nm, tr.slice(k, k + 12)])
			k += 12
		var mid_nm := Vector2i(K_MID, id.w)
		if rec.items.has(mid_nm):
			_set_mid_begin(rec.items[mid_nm].node, near_fade, fade_margin)
	elif id.z == K_MID:
		if rec.items.has(Vector2i(K_NEAR, id.w)):
			_set_mid_begin(node, near_fade, fade_margin)


func _set_mid_begin(n: Node, begin: float, margin: float) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).visibility_range_begin = begin
			(c as GeometryInstance3D).visibility_range_begin_margin = margin


func _unload_item(t: Vector2i, nm: Vector2i) -> void:
	var rec: Dictionary = tiles[t]
	var it: Dictionary = rec.items[nm]
	if nm.x == K_NEAR:
		var mid_nm := Vector2i(K_MID, nm.y)
		if rec.items.has(mid_nm):
			_set_mid_begin(rec.items[mid_nm].node, 0.0, 0.0)  # mid takes over everywhere before near goes
	(it.node as Node).queue_free()
	rec.items.erase(nm)


func _apply_collision() -> void:
	if _col_queue.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var budget := int(collision_budget_ms * 1000.0)
	while not _col_queue.is_empty():
		var e: Array = _col_queue.pop_front()
		var t: Vector2i = e[0]
		var nm: Vector2i = e[1]
		if not tiles.has(t) or not tiles[t].items.has(nm):
			continue
		var it: Dictionary = tiles[t].items[nm]
		var parent: Node3D = it.node
		var i0 := Time.get_ticks_usec()
		var body := StaticBody3D.new()
		if e[2] is PackedVector3Array:
			body.name = "HouseCol"
			body.set_meta("surface_name", "Rooftop (not on tonight's list)")
			body.set_meta("what", "a house")
			var cs := CollisionShape3D.new()
			var sh := ConcavePolygonShape3D.new()
			sh.backface_collision = true
			sh.set_faces(e[2])
			cs.shape = sh
			body.add_child(cs)
		else:
			body.name = "TreeCol"
			body.set_meta("surface_name", "Gum tree")
			body.set_meta("what", "a gum tree")
			var trunk := CylinderShape3D.new()
			trunk.radius = 0.35
			trunk.height = 6.0
			var crown := SphereShape3D.new()
			crown.radius = 2.6
			for pt in e[2]:
				var c1 := CollisionShape3D.new()
				c1.shape = trunk
				c1.position = pt + Vector3(0, 3.0, 0)
				body.add_child(c1)
				var c2 := CollisionShape3D.new()
				c2.shape = crown
				c2.position = pt + Vector3(0, 7.2, 0)
				body.add_child(c2)
		parent.add_child(body)
		(it.bodies as Array).append(body)
		stats.col_shapes += 1
		var ck := "col_house_ms" if e[2] is PackedVector3Array else "col_trees_ms"
		stats[ck] = maxf(float(stats.get(ck, 0.0)), (Time.get_ticks_usec() - i0) / 1000.0)
		if ck == "col_house_ms":
			stats.col_house_faces = maxi(int(stats.get("col_house_faces", 0)), (e[2] as PackedVector3Array).size() / 3)
		if Time.get_ticks_usec() - t0 > budget:
			break


# --------------------------------------------------------------------------------------------- origin

func _set_block_mesh(b: Dictionary, r: Dictionary) -> void:
	var mi: MeshInstance3D = b.node
	mi.mesh = r.mesh
	var at: PackedFloat64Array = r.built_at
	b["built_at"] = at
	# the mesh is relative to the block centre as seen from the origin it was built for
	var g := Geo.new(at[0], at[1])
	var c_then := g.to_world(int(b.by) + 0.5, int(b.bx) + 0.5)
	b["offset_then"] = c_then
	mi.position = geo.to_world(int(b.by) + 0.5, int(b.bx) + 0.5)
	mi.reset_physics_interpolation()


## Re-place a block plane after a rebase. Its vertices only need re-projecting (off-thread) once the origin
## has moved ~10 km (the mean-latitude projection then drifts ~20 m at the block's far edge, deep in the haze).
func _block_follow(b: Dictionary) -> void:
	var mi: MeshInstance3D = b.node
	mi.position = geo.to_world(int(b.by) + 0.5, int(b.bx) + 0.5)
	mi.reset_physics_interpolation()
	var at: PackedFloat64Array = b.get("built_at", PackedFloat64Array([geo.lat0, geo.lon0]))
	if geo.east_north(at[0], at[1]).length() > 10000.0:
		b["refresh"] = true
		b["built_at"] = PackedFloat64Array([geo.lat0, geo.lon0])


## Move the origin to world point d (horizontal). Returns the exact offset the caller must subtract from
## dynamic things (sleigh, camera...). Tiles re-place themselves from lat/lon.
func rebase(d: Vector3) -> Vector3:
	d.y = 0.0
	var ll := geo.to_latlon(d)
	var old := geo.to_world(ll[0], ll[1])
	geo.set_origin(ll[0], ll[1])
	for t in tiles:
		var rec: Dictionary = tiles[t]
		(rec.node as Node3D).position = geo.to_world(rec.lat, rec.lon)
		(rec.node as Node3D).reset_physics_interpolation()
	for bk in blocks:
		_block_follow(blocks[bk])
	stats.rebases += 1
	return old


## Jump the origin somewhere else entirely (warps): everything reloads around the new spot.
func reset_origin(lat: float, lon: float) -> void:
	geo.set_origin(lat, lon)
	for t in tiles:
		var rec: Dictionary = tiles[t]
		(rec.node as Node3D).position = geo.to_world(rec.lat, rec.lon)
		(rec.node as Node3D).reset_physics_interpolation()
	for bk in blocks:
		_block_follow(blocks[bk])
		blocks[bk]["refresh"] = true
	_t_update = 0.0
	_dirty = true
