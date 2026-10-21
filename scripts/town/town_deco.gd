extends RefCounted
## Christmas yard decorations for the real-map town (a summer Christmas in Brisbane):
## inflatable Santas and kangaroos, light-up wire reindeer, the odd nativity scene, lit hedges,
## jacarandas and gum trees wrapped in string lights, and wreaths on the front doors.
## Delivery houses go all out; background houses get one or two things (or nothing).
## Everything is batched through MeshBatch (one mesh per chunk per material); the bulbs join
## the town's bulb MultiMeshes; each piece gets one or two simple collision boxes/hulls.

const GB := preload("res://scripts/greybox.gd")
const MeshBatch := preload("res://scripts/town/mesh_batch.gd")

const RED := Color(0.86, 0.1, 0.1)
const WHITE := Color(0.97, 0.97, 0.95)
const SKIN := Color(1.0, 0.78, 0.62)
const BLACK := Color(0.06, 0.05, 0.06)
const GOLD := Color(1.0, 0.78, 0.2)
const ROO := Color(0.78, 0.5, 0.28)
const CREAM := Color(0.96, 0.86, 0.68)
const WOOD := Color(0.45, 0.28, 0.16)
const STRAW := Color(0.92, 0.78, 0.36)
const HEDGE := Color(0.14, 0.42, 0.2)
const JAC := [Color(0.62, 0.45, 0.88), Color(0.55, 0.38, 0.82), Color(0.7, 0.52, 0.92)]
const JAC_BARK := Color(0.36, 0.3, 0.26)
const WIRE_GLOW := [Color(1.0, 0.95, 0.82), Color(0.75, 0.9, 1.0), Color(1.0, 0.8, 0.35)]
const MULTI := [Color(1.0, 0.25, 0.2), Color(0.3, 1.0, 0.4), Color(0.35, 0.5, 1.0), Color(1.0, 0.75, 0.2)]
const WARM := [Color(1.0, 0.78, 0.45), Color(1.0, 0.9, 0.7)]
const ICE := [Color(0.75, 0.88, 1.0), Color(1.0, 1.0, 1.0)]

var t: Node3D  ## the town node (helpers, bulb buckets, collision buckets)
var B  ## visuals
var C  ## collision (keys = collision categories)
var rng := RandomNumberGenerator.new()
var counts := {}
var _keys := {}


func _init(town_node: Node3D, seed_: int) -> void:
	t = town_node
	rng.seed = seed_ + 4242
	B = MeshBatch.new()
	B.chunk_size = 192.0
	C = MeshBatch.new()
	C.chunk_size = t.collision_chunk


func _k(c: Color, emission := 0.0, shadow := true) -> String:
	var key := "deco_%s_%s" % [c.to_html(false), emission]
	if not B.has_material(key):
		B.register(key, GB.mat(c, emission))
		if not shadow:
			B.no_shadow[key] = true
	return key


func _count(what: String) -> void:
	counts[what] = int(counts.get(what, 0)) + 1


func build() -> void:
	var t0 := Time.get_ticks_msec()
	for info in t.house_infos:
		var spots := _yard(info)
		var is_delivery: bool = info.get("delivery", false)
		if is_delivery or rng.randf() < 0.42:
			_wreath(info)
		if spots.is_empty():
			continue
		var want: Array = []
		if is_delivery:
			want = ["santa", "roo", "reindeer", "jacaranda", "hedge", "reindeer"]
			if rng.randf() < 0.5:
				want.insert(2, "nativity")
		else:
			var roll := rng.randf()
			if roll < 0.36:
				want.append(_pick())
				if rng.randf() < 0.22:
					want.append(_pick())
		info["deco_n"] = _place(want, spots, is_delivery)
		if is_delivery:
			info["deco_spot"] = spots[0]
	# Street gums wrapped in lights: every one near a delivery house, ~1 in 7 elsewhere.
	var dpos: Array = []
	for info in t.house_infos:
		if info.get("delivery", false):
			dpos.append((info.base as Transform3D).origin)
	for st in t._street_trees:
		var tx: Transform3D = st[0]
		var near := false
		for p in dpos:
			if (p as Vector3).distance_to(tx.origin) < 28.0:
				near = true
				break
		if near or rng.randf() < 0.14:
			_wrap_gum(tx, int(st[2]), near)
	B.commit(t, true)
	t._take_faces(C)
	t.stats["deco"] = counts
	print("[town] decorations: %s in %d ms" % [str(counts), Time.get_ticks_msec() - t0])


func _pick() -> String:
	var r := rng.randf()
	if r < 0.22:
		return "santa"
	if r < 0.42:
		return "roo"
	if r < 0.62:
		return "reindeer"
	if r < 0.78:
		return "hedge"
	if r < 0.95:
		return "jacaranda"
	return "nativity"


## Free spots in the front yard: [{p, lat, depth}], with the frame stored in the first entry's keys.
func _yard(info: Dictionary) -> Array:
	var b: Dictionary = info.b
	var style := String(info.style)
	if style in ["shop", "shed", "apartments", "hall"] or b.get("road_pt") == null or b.get("road_width") == null:
		return []
	var base: Transform3D = info.base
	var fz := base.basis.z
	var fx := base.basis.x
	var hw := float(b.road_width) * 0.5
	var door: Vector3 = info.get("door", base.origin)
	var rp: Vector3 = t.v3(b.road_pt)
	var to_road := rp - door
	to_road.y = 0
	var s := to_road.dot(fz)
	var front_line := s - (hw + 1.6 + 1.5 + 0.3)  # verge + footpath, as in town.gd
	if s < 3.0 or front_line < 2.4 or front_line > 22.0:
		return []
	var W := float(info.W)
	# same driveway test as the street-furniture pass, so we keep off the drive
	var drive_lat := 999.0
	for side: float in [1.0, -1.0]:
		var probe := base.origin + fx * side * (W * 0.5 + 1.6)
		if t.clear_of_buildings(Vector2(probe.x, probe.z), 0.2) and t.clear_of_buildings(Vector2(probe.x, probe.z) - Vector2(fz.x, fz.z) * 3.0, 0.2):
			drive_lat = (base.origin + fx * side * (W * 0.5 + 1.6) - door).dot(fx)
			break
	var out: Array = []
	var depth := 1.5
	while depth <= front_line - 0.9:
		var lat := -(W * 0.5 + 1.0)
		while lat <= W * 0.5 + 1.0:
			if absf(lat) > 1.3 and absf(lat - drive_lat) > 2.2:
				var p := door + fz * depth + fx * lat
				var p2 := Vector2(p.x, p.z)
				if t.clear_of_buildings(p2, 0.9) and t.road_clearance(p2) > hw * 0.0 + 3.2:
					out.append({"p": Vector3(p.x, 0, p.z), "lat": lat, "depth": depth, "fx": fx, "fz": fz, "front_line": front_line})
			lat += 1.2
		depth += 1.2
	out.shuffle()
	return out


const RADIUS := {"santa": 0.8, "roo": 0.8, "reindeer": 0.8, "nativity": 1.6, "hedge": 1.4, "jacaranda": 2.0}


func _place(want: Array, spots: Array, generous: bool) -> int:
	var used: Array = []  # [pos, radius]
	for w in want:
		var what := String(w)
		var r: float = RADIUS[what]
		for s in spots:
			var p: Vector3 = s.p
			if what == "jacaranda" and not t.clear_of_buildings(Vector2(p.x, p.z), 2.2):
				continue
			if what == "nativity" and float(s.front_line) - float(s.depth) < 1.4:
				continue
			var ok := true
			for u in used:
				if p.distance_to(u[0]) < r + float(u[1]) + 0.2:
					ok = false
					break
			if not ok:
				continue
			used.append([p, r])
			var fx: Vector3 = s.fx
			var fz: Vector3 = s.fz
			var yaw := rng.randf_range(-0.35, 0.35)
			var xf := Transform3D(Basis(fx, Vector3.UP, fz).rotated(Vector3.UP, yaw), p)
			if what == "hedge":
				xf = Transform3D(Basis(fx, Vector3.UP, fz), p)
			B.set_chunk_at(p)
			C.set_chunk_at(p)
			B.xform = xf
			C.xform = xf
			call("_" + what, generous)
			B.xform = Transform3D.IDENTITY
			C.xform = Transform3D.IDENTITY
			_count(what)
			break
	return used.size()


# --- pieces (local frame: +Z faces the street, y up, origin on the ground) ----------------------------

func _santa(_g: bool) -> void:
	var red := _k(RED, 0.35)
	var white := _k(WHITE, 0.35)
	var black := _k(BLACK)
	for sx: float in [-1.0, 1.0]:
		B.abox(black, Vector3(sx * 0.24, 0.12, 0.08), Vector3(0.3, 0.24, 0.46))
		B.cylinder(red, Vector3(sx * 0.24, 0.22, 0), 0.2, 0.22, 0.42, 8)
		B.sphere(red, Vector3(sx * 0.66, 1.22, 0.05), 0.2, Vector3(1, 1.7, 1), 4, 8)
		B.sphere(black, Vector3(sx * 0.74, 0.86, 0.12), 0.14, Vector3.ONE, 3, 6)
		B.sphere(black, Vector3(sx * 0.11, 1.93, 0.33), 0.045, Vector3.ONE, 2, 5)
	B.sphere(red, Vector3(0, 1.02, 0), 0.62, Vector3(1, 1.1, 0.95), 5, 10)
	B.cylinder(black, Vector3(0, 0.84, 0), 0.625, 0.62, 0.15, 10)
	B.abox(_k(GOLD, 0.6), Vector3(0, 0.915, 0.6), Vector3(0.22, 0.17, 0.06))
	B.sphere(white, Vector3(0, 1.55, 0.3), 0.36, Vector3(1, 1.15, 0.6), 4, 8)
	B.sphere(_k(SKIN, 0.3), Vector3(0, 1.86, 0.05), 0.34, Vector3.ONE, 5, 9)
	B.sphere(_k(Color(1.0, 0.55, 0.5), 0.3), Vector3(0, 1.84, 0.38), 0.07, Vector3.ONE, 2, 5)
	B.cylinder(white, Vector3(0, 2.05, 0), 0.37, 0.37, 0.14, 10)
	B.cylinder(red, Vector3(0, 2.18, 0), 0.33, 0.03, 0.62, 9, Vector3(0, 0, -0.22))
	B.sphere(white, Vector3(0, 2.8, -0.22), 0.11, Vector3.ONE, 3, 6)
	C.abox("santa", Vector3(0, 1.3, 0.02), Vector3(1.4, 2.6, 1.2), 0.0, false)


func _roo(_g: bool) -> void:
	var fur := _k(ROO, 0.3)
	var cream := _k(CREAM, 0.3)
	var red := _k(RED, 0.35)
	var white := _k(WHITE, 0.35)
	var black := _k(BLACK)
	B.beam(fur, Vector3(0, 0.3, -0.25), Vector3(0, 0.08, -1.05), 0.22, 0.18)
	B.sphere(fur, Vector3(0, 0.55, -0.05), 0.5, Vector3(1, 0.9, 1.1), 4, 9)
	B.sphere(fur, Vector3(0, 1.15, 0.05), 0.42, Vector3(0.9, 1.3, 0.85), 5, 9)
	B.sphere(cream, Vector3(0, 1.05, 0.26), 0.28, Vector3(1, 1.35, 0.6), 4, 8)
	for sx: float in [-1.0, 1.0]:
		B.abox(fur, Vector3(sx * 0.18, 0.08, 0.28), Vector3(0.18, 0.14, 0.62))
		B.beam(fur, Vector3(sx * 0.24, 1.4, 0.22), Vector3(sx * 0.22, 1.05, 0.46), 0.12, 0.12)
		B.sphere(red, Vector3(sx * 0.22, 1.02, 0.5), 0.14, Vector3.ONE, 3, 6)
		B.beam(fur, Vector3(sx * 0.09, 1.92, 0.04), Vector3(sx * 0.17, 2.22, -0.02), 0.11, 0.05)
		B.sphere(black, Vector3(sx * 0.09, 1.84, 0.3), 0.035, Vector3.ONE, 2, 5)
	B.sphere(fur, Vector3(0, 1.78, 0.12), 0.24, Vector3(0.9, 1, 1.2), 4, 8)
	B.sphere(fur, Vector3(0, 1.72, 0.37), 0.13, Vector3.ONE, 3, 6)
	B.sphere(black, Vector3(0, 1.75, 0.49), 0.04, Vector3.ONE, 2, 5)
	B.cylinder(white, Vector3(-0.02, 1.96, 0.1), 0.2, 0.2, 0.07, 9)
	B.cylinder(red, Vector3(-0.02, 2.03, 0.1), 0.18, 0.02, 0.4, 8, Vector3(0.18, 0, -0.05))
	B.sphere(white, Vector3(0.16, 2.43, 0.05), 0.07, Vector3.ONE, 2, 5)
	C.abox("roo", Vector3(0, 1.1, -0.15), Vector3(1.0, 2.3, 1.6), 0.0, false)


func _reindeer(_g: bool) -> void:
	var glow := _k(WIRE_GLOW[rng.randi() % WIRE_GLOW.size()], 3.0, false)
	var grazing := rng.randf() < 0.4
	var w := 0.05
	var hx := 0.17
	var y0 := 0.78
	var y1 := 1.18
	var z0 := -0.48
	var z1 := 0.45
	var c := [Vector3(-hx, y0, z0), Vector3(hx, y0, z0), Vector3(hx, y0, z1), Vector3(-hx, y0, z1),
			Vector3(-hx, y1, z0), Vector3(hx, y1, z0), Vector3(hx, y1, z1), Vector3(-hx, y1, z1)]
	for i in 4:
		B.beam(glow, c[i], c[(i + 1) % 4], w, w)
		B.beam(glow, c[i + 4], c[(i + 1) % 4 + 4], w, w)
		B.beam(glow, c[i], c[i + 4], w, w)
		B.beam(glow, c[i], Vector3(c[i].x * 1.1, 0.0, c[i].z * 1.05), w, w)  # legs
	B.beam(glow, Vector3(0, y1, z0), Vector3(0, y1 + 0.15, z0 - 0.15), w, w)  # tail
	var neck_top := Vector3(0, 0.5, 0.95) if grazing else Vector3(0, 1.62, 0.66)
	var nose := neck_top + (Vector3(0, -0.12, 0.28) if not grazing else Vector3(0, -0.25, 0.12))
	B.beam(glow, Vector3(0, y1, z1), neck_top, w * 1.3, w * 1.3)
	B.beam(glow, Vector3(0, y0 + 0.1, z1), neck_top + Vector3(0, -0.12, 0), w, w)
	B.beam(glow, neck_top, nose, w * 1.6, w * 1.6)
	B.sphere(_k(Color(1.0, 0.15, 0.1), 3.5, false), nose + Vector3(0, 0, 0.05), 0.06, Vector3.ONE, 2, 5)
	for sx: float in [-1.0, 1.0]:
		var a0 := neck_top + Vector3(sx * 0.08, 0.06, -0.02)
		var a1 := a0 + Vector3(sx * 0.18, 0.32, -0.12)
		B.beam(glow, a0, a1, w, w)
		B.beam(glow, a1, a1 + Vector3(sx * 0.14, 0.12, 0.1), w, w)
		B.beam(glow, a0.lerp(a1, 0.5), a0.lerp(a1, 0.5) + Vector3(0, 0.18, 0.1), w, w)
	C.abox("reindeer", Vector3(0, 0.85, 0.15), Vector3(0.5, 1.7 if not grazing else 1.3, 1.5), 0.0, false)


func _nativity(_g: bool) -> void:
	var wood := _k(WOOD)
	var straw := _k(STRAW, 0.25)
	var skin := _k(SKIN, 0.2)
	B.abox(straw, Vector3(0, 0.05, 0), Vector3(2.6, 0.1, 1.6), 0.0, false)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			B.abox(wood, Vector3(sx * 1.2, 0.95, sz * 0.7), Vector3(0.12, 1.9, 0.12))
		B.box(_k(Color(0.55, 0.4, 0.25)), Transform3D(Basis(Vector3.BACK, -sx * 0.42), Vector3(sx * 0.66, 2.12, 0)), Vector3(1.6, 0.08, 1.8), false)
	B.abox(wood, Vector3(0, 0.95, -0.76), Vector3(2.5, 1.8, 0.08))
	var star := _k(GOLD, 4.0, false)
	B.abox(star, Vector3(0, 2.78, 0.05), Vector3(0.45, 0.12, 0.06))
	B.abox(star, Vector3(0, 2.78, 0.05), Vector3(0.12, 0.45, 0.06))
	B.box(star, Transform3D(Basis(Vector3.BACK, PI / 4), Vector3(0, 2.78, 0.05)), Vector3(0.3, 0.3, 0.05))
	B.abox(wood, Vector3(0, 0.3, 0.15), Vector3(0.6, 0.3, 0.36))
	B.abox(straw, Vector3(0, 0.47, 0.15), Vector3(0.56, 0.06, 0.3))
	B.sphere(_k(CREAM, 0.6), Vector3(0, 0.53, 0.15), 0.1, Vector3(1.6, 0.8, 1), 3, 6)
	B.cylinder(_k(Color(0.25, 0.42, 0.85), 0.2), Vector3(-0.55, 0.1, 0.05), 0.26, 0.12, 0.95, 8)
	B.sphere(skin, Vector3(-0.55, 1.15, 0.05), 0.13, Vector3.ONE, 3, 6)
	B.sphere(_k(Color(0.25, 0.42, 0.85), 0.2), Vector3(-0.55, 1.18, 0.0), 0.16, Vector3(1, 1, 0.9), 3, 6)
	B.cylinder(_k(Color(0.55, 0.36, 0.2), 0.2), Vector3(0.55, 0.1, 0.0), 0.27, 0.13, 1.08, 8)
	B.sphere(skin, Vector3(0.55, 1.3, 0.0), 0.14, Vector3.ONE, 3, 6)
	B.beam(wood, Vector3(0.82, 0.1, 0.15), Vector3(0.85, 1.6, 0.2), 0.05, 0.05)
	B.sphere(_k(WHITE, 0.2), Vector3(0.95, 0.32, 0.6), 0.24, Vector3(1.3, 0.9, 1), 3, 7)
	B.sphere(_k(BLACK), Vector3(1.22, 0.42, 0.66), 0.1, Vector3.ONE, 2, 5)
	_bulbs(PackedVector3Array([Vector3(-1.3, 1.95, 0.8), Vector3(0, 2.5, 0.85), Vector3(1.3, 1.95, 0.8)]), WARM, 0.32)
	C.abox("nativity", Vector3(0, 1.3, 0), Vector3(2.7, 2.6, 1.7), 0.0, false)


func _hedge(g: bool) -> void:
	var L := rng.randf_range(3.0, 4.6)
	var h := 0.95
	B.abox(_k(HEDGE), Vector3(0, h * 0.5, 0), Vector3(L, h, 0.75))
	B.sphere(_k(HEDGE.lightened(0.08)), Vector3(-L * 0.25, h, 0), 0.4, Vector3(2.2, 0.5, 0.95), 3, 7)
	B.sphere(_k(HEDGE.lightened(0.08)), Vector3(L * 0.25, h, 0), 0.4, Vector3(2.2, 0.5, 0.95), 3, 7)
	var pal: Array = MULTI if (g or rng.randf() < 0.5) else (ICE if rng.randf() < 0.5 else WARM)
	# net of lights: zig-zag across the street face and a run along the top
	var pts := PackedVector3Array()
	var n := int(L / 0.5)
	for i in n + 1:
		var x := -L * 0.5 + L * float(i) / float(n)
		pts.append(Vector3(x, 0.25 if i % 2 == 0 else h - 0.05, 0.4))
	_bulbs(pts, pal, 0.28)
	_bulbs(PackedVector3Array([Vector3(-L * 0.5, h + 0.08, 0.3), Vector3(L * 0.5, h + 0.08, 0.3), Vector3(L * 0.5, h + 0.08, -0.3), Vector3(-L * 0.5, h + 0.08, -0.3), Vector3(-L * 0.5, h + 0.08, 0.3)]), pal, 0.3)
	C.abox("hedge", Vector3(0, h * 0.55, 0), Vector3(L, h * 1.1, 0.8), 0.0, false)


func _jacaranda(g: bool) -> void:
	var bark := _k(JAC_BARK)
	var h := rng.randf_range(3.2, 3.8)
	var lean := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
	B.cylinder(bark, Vector3.ZERO, 0.28, 0.18, h, 7, lean)
	var top := Vector3(0, h, 0) + lean
	var blobs: Array = []
	for i in 5:
		var a := TAU * float(i) / 5.0 + rng.randf_range(-0.3, 0.3)
		var r := rng.randf_range(1.2, 1.8)
		var c := top + Vector3(cos(a) * r, rng.randf_range(0.6, 1.2), sin(a) * r)
		B.beam(bark, top + Vector3(0, -0.4, 0), c + Vector3(0, -0.3, 0), 0.13, 0.13)
		blobs.append(c)
		B.sphere(_k(JAC[i % 3]), c, rng.randf_range(1.1, 1.4), Vector3(1.15, 0.6, 1.15), 4, 8)
	B.sphere(_k(JAC[1]), top + Vector3(0, 1.4, 0), 1.5, Vector3(1.1, 0.6, 1.1), 4, 8)
	B.disc(_k(Color(0.66, 0.5, 0.9)), Vector2.ZERO, 3.0, 0.025, 12)  # fallen flowers
	# lights: spiral up the trunk, then hanging loops around the canopy rim
	var pal: Array = WARM if (not g and rng.randf() < 0.5) else (ICE if rng.randf() < 0.3 else MULTI)
	var sp := PackedVector3Array()
	for i in 25:
		var f := float(i) / 24.0
		var a := f * TAU * 3.5
		var r := lerpf(0.34, 0.24, f)
		sp.append(Vector3(cos(a) * r, f * h * 0.95, sin(a) * r) + lean * f)
	_bulbs(sp, pal, 0.3)
	var rim := PackedVector3Array()
	for i in 29:
		var a := TAU * float(i) / 28.0
		var rr := 2.5 if i % 2 == 0 else 2.2
		rim.append(top + Vector3(cos(a) * rr, 0.35 if i % 2 == 0 else -0.05, sin(a) * rr))
	_bulbs(rim, pal, 0.4)
	if g:
		var rim2 := PackedVector3Array()
		for i in 21:
			var a := TAU * float(i) / 20.0 + 0.2
			rim2.append(top + Vector3(cos(a) * 1.6, 1.25, sin(a) * 1.6))
		_bulbs(rim2, pal, 0.4)
	C.cylinder("jacaranda", Vector3.ZERO, 0.3, 0.2, h, 6, lean)
	C.sphere("jacaranda", top + Vector3(0, 1.0, 0), 2.3, Vector3(1.25, 0.6, 1.25), 3, 7)


func _wrap_gum(tx: Transform3D, v: int, near: bool) -> void:
	var s := tx.basis.get_scale().y
	var h := (6.5 + v * 0.7) * s
	var o := tx.origin
	var pal: Array = MULTI if near or rng.randf() < 0.5 else (WARM if rng.randf() < 0.6 else ICE)
	var sp := PackedVector3Array()
	var turns := 3.0
	var n := 40
	for i in n + 1:
		var f := float(i) / float(n)
		var a := f * TAU * turns + rng.randf() * 0.1
		var y := lerpf(h - 1.0 * s, h + 1.2 * s, f)
		var r := 2.25 * s * sin(lerpf(0.55, 2.7, f))
		sp.append(o + Vector3(cos(a) * r, y, sin(a) * r))
	_bulbs_world(sp, pal, 0.45)
	var tr := PackedVector3Array()
	for i in 16:
		var f := float(i) / 15.0
		var a := f * TAU * 3.0
		tr.append(o + Vector3(cos(a) * 0.4 * s, 0.3 + f * h * 0.5, sin(a) * 0.4 * s))
	_bulbs_world(tr, pal, 0.35)
	_count("lit gum tree")


func _wreath(info: Dictionary) -> void:
	if not info.has("door_wall"):
		return
	var p: Vector3 = info.door_wall
	var base: Transform3D = info.base
	var fz := base.basis.z
	var fx := base.basis.x
	B.set_chunk_at(p)
	B.xform = Transform3D(Basis(fx, Vector3.UP, fz), p)
	var green := _k(Color(0.1, 0.4, 0.18))
	for i in 10:
		var a := TAU * float(i) / 10.0
		B.sphere(green, Vector3(cos(a) * 0.27, sin(a) * 0.27, 0.05), 0.1, Vector3(1, 1, 0.7), 2, 5)
	B.sphere(_k(RED, 0.4), Vector3(0, -0.27, 0.13), 0.07, Vector3(1.8, 1, 0.8), 2, 6)
	B.beam(_k(RED, 0.4), Vector3(0, -0.27, 0.13), Vector3(-0.08, -0.48, 0.12), 0.06, 0.02)
	B.beam(_k(RED, 0.4), Vector3(0, -0.27, 0.13), Vector3(0.08, -0.48, 0.12), 0.06, 0.02)
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.6
		B.sphere(_k(RED, 0.4), Vector3(cos(a) * 0.27, sin(a) * 0.27, 0.12), 0.04, Vector3.ONE, 2, 4)
	B.xform = Transform3D.IDENTITY
	var ring := PackedVector3Array()
	for i in 13:
		var a := TAU * float(i) / 12.0
		ring.append(p + fx * cos(a) * 0.36 + Vector3.UP * sin(a) * 0.36 + fz * 0.1)
	_bulbs_world(ring, WARM, 0.2)
	_count("wreath")


# --- bulbs: straight into the town's bulb MultiMesh buckets ----------------------------------------------

func _bulbs(local_pts: PackedVector3Array, pal: Array, spacing: float) -> void:
	_bulbs_world(B.xform * local_pts, pal, spacing)


func _bulbs_world(pts: PackedVector3Array, pal: Array, spacing: float) -> void:
	if pts.size() < 2:
		return
	var key := Vector2i(floori(pts[0].x / 192.0), floori(pts[0].z / 192.0))
	if not t._bulbs.has(key):
		t._bulbs[key] = {"x": [], "c": [], "d": [], "w": []}
	var bucket: Dictionary = t._bulbs[key]
	var n := 0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var L := a.distance_to(b)
		var cnt := maxi(1, int(L / spacing))
		bucket.w.append([a, b])
		for k in cnt:
			var f := (float(k) + 0.5) / float(cnt)
			var bas := Basis(Vector3.UP, rng.randf_range(0, TAU)) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3))
			bucket.x.append(Transform3D(bas, a.lerp(b, f) + Vector3.DOWN * 0.04))
			bucket.c.append(pal[n % pal.size()])
			bucket.d.append(Color(rng.randf(), rng.randf(), 0, 0))
			n += 1
	counts["bulbs"] = int(counts.get("bulbs", 0)) + n
