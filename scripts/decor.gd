extends RefCounted
## Christmas decorations, all visual only (no collision, so nothing changes for the elf's routes or the
## sleigh's landings) and built with their own seeded RNG (so the house and furniture layouts don't move).
##   interior(it):  garland + cards on the mantel, tinsel swags, fairy lights round the windows, a wreath on
##                  the front door, a pavlova on the dining table. The tree (star, baubles, tinsel, lights),
##                  presents, stockings, cookies and milk, beer and a carrot, the fan and air con already exist.
##   yard(h):       gum tree wrapped in lights, inflatable Santa and kangaroo, light-up wire reindeer, lit hedges,
##                  a nativity scene now and then. A different mix per house.

const GB := preload("res://scripts/greybox.gd")
const Furn := preload("res://scripts/furniture.gd")

const BULBS := [Color(1.0, 0.25, 0.2), Color(0.25, 1.0, 0.4), Color(0.35, 0.55, 1.0), Color(1.0, 0.85, 0.25), Color(1.0, 0.45, 0.9)]
const GOLD := Color(1.0, 0.8, 0.3)
const PINE := Color(0.12, 0.42, 0.2)


static func _bulb_mat(c: Color, e := 2.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Many small glowing bulbs in one MultiMesh (cheap).
static func bulbs(parent: Node3D, pts: Array, r: float, colors: Array = BULBS, e := 2.2) -> void:
	if pts.is_empty():
		return
	var by: Dictionary = {}
	for i in pts.size():
		var k := i % colors.size()
		if not by.has(k):
			by[k] = []
		by[k].append(pts[i])
	for k in by:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 6
		sm.rings = 3
		mm.mesh = sm
		mm.instance_count = by[k].size()
		for i in by[k].size():
			mm.set_instance_transform(i, Transform3D(Basis(), by[k][i]))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _bulb_mat(colors[k], e)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)


## A sagging swag between a and b (cylinder segments) with optional bulbs.
static func swag(parent: Node3D, a: Vector3, b: Vector3, sag: float, r: float, color: Color, segs := 8, emission := 0.0) -> Array:
	var pts := []
	for i in segs + 1:
		var t := float(i) / segs
		pts.append(a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0))
	for i in segs:
		_seg(parent, pts[i], pts[i + 1], r, color, emission)
	return pts


static func _seg(parent: Node3D, a: Vector3, b: Vector3, r: float, color: Color, emission := 0.0) -> MeshInstance3D:
	var d := b - a
	var L := d.length()
	if L < 0.001:
		return null
	var mi := GB.cylinder(parent, r, r, L, (a + b) * 0.5, color, Vector3.ZERO, emission, 6)
	var y := d / L
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Pine garland: a fat green rope of lumps with red bows and bulbs.
static func garland(parent: Node3D, a: Vector3, b: Vector3, sag: float, rng: RandomNumberGenerator) -> void:
	var pts := []
	var n := int(a.distance_to(b) / 0.07) + 2
	for i in n:
		var t := float(i) / (n - 1)
		pts.append(a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0))
	var lights := []
	for i in pts.size():
		var p: Vector3 = pts[i]
		var s := GB.sphere(parent, rng.randf_range(0.045, 0.06), p + Vector3(rng.randf_range(-0.01, 0.01), rng.randf_range(-0.01, 0.01), rng.randf_range(-0.01, 0.01)), PINE.lerp(Color(0.2, 0.5, 0.25), rng.randf()), 0.0, Vector3(1.2, 0.9, 1.0))
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i % 2 == 0:
			lights.append(p + Vector3(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.04, 0.0), rng.randf_range(0.02, 0.05)))
	bulbs(parent, lights, 0.012)
	for k in 3:
		var p: Vector3 = pts[int((k + 0.5) * pts.size() / 3.0)]
		_bow(parent, p + Vector3(0, 0, 0.05), 0.05)


static func _bow(parent: Node3D, p: Vector3, s: float) -> void:
	var red := Color(0.85, 0.08, 0.1)
	GB.sphere(parent, s * 0.6, p + Vector3(-s * 0.6, 0, 0), red, 0.0, Vector3(1.0, 0.7, 0.4))
	GB.sphere(parent, s * 0.6, p + Vector3(s * 0.6, 0, 0), red, 0.0, Vector3(1.0, 0.7, 0.4))
	GB.sphere(parent, s * 0.3, p, red)
	GB.box(parent, Vector3(s * 0.25, s * 1.2, s * 0.1), p + Vector3(-s * 0.25, -s * 0.7, 0), red, Vector3(0, 0, 15))
	GB.box(parent, Vector3(s * 0.25, s * 1.2, s * 0.1), p + Vector3(s * 0.25, -s * 0.7, 0), red, Vector3(0, 0, -15))


## Wreath facing +Z of `parent` space at p (ring of pine lumps, berries, bow).
static func wreath(parent: Node3D, p: Vector3, r: float, yaw_deg: float, rng: RandomNumberGenerator) -> Node3D:
	var w := Node3D.new()
	parent.add_child(w)
	w.position = p
	w.rotation_degrees = Vector3(0, yaw_deg, 0)
	var n := 16
	for i in n:
		var a := TAU * i / n
		GB.sphere(w, r * 0.32, Vector3(cos(a) * r, sin(a) * r, 0), PINE.lerp(Color(0.25, 0.55, 0.3), rng.randf()), 0.0, Vector3(1.0, 1.0, 0.6))
	var berries := []
	for i in 9:
		var a := TAU * i / 9 + 0.2
		berries.append(Vector3(cos(a) * r * 1.05, sin(a) * r * 1.05, r * 0.25))
	bulbs(w, berries, r * 0.09, [Color(0.9, 0.05, 0.08)], 0.6)
	_bow(w, Vector3(0, -r * 0.95, r * 0.25), r * 0.45)
	return w


# =================================================================================================
# Interior
# =================================================================================================

static func interior(it: Node3D, roof_type: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150 + roof_type * 7
	var root := Node3D.new()
	root.name = "Decor"
	it.add_child(root)
	var rooms: Array = it.get("rooms")
	var fx: float = it.get("fireplace_x")
	var Z0: float = it.get("Z0")
	var WALL_T: float = it.WALL_T
	var living: Dictionary = {}
	var kitchen: Dictionary = {}
	for r in rooms:
		if str(r.name) == "Living":
			living = r
		elif str(r.name) == "Kitchen":
			kitchen = r
	if not living.is_empty():
		var f := float(living.floor)
		var zc := Z0 + WALL_T + 0.4
		# mantel garland, swagged, with bows and lights
		garland(root, Vector3(fx - 1.0, f + 1.36, zc + 0.4), Vector3(fx + 1.0, f + 1.36, zc + 0.4), 0.12, rng)
		# Christmas cards standing on the mantel
		for k in 6:
			var x := fx - 0.85 + k * 0.32 + rng.randf_range(-0.04, 0.04)
			if absf(x - (fx + 0.55)) < 0.12:
				continue  # leave the rappel anchor clear
			_card(root, Vector3(x, f + 1.33, zc + 0.24), rng)
		# tinsel swags under the cornice along the long walls
		var rc: Rect2 = living.rect
		var ce := float(living.ceil)
		var tins := [Color(0.85, 0.85, 0.95), GOLD, Color(0.9, 0.2, 0.25)]
		for side: float in [0.0, 1.0]:
			var z := rc.position.y + WALL_T + 0.04 if side == 0.0 else rc.end.y - WALL_T - 0.04
			var x := rc.position.x + 0.3
			var i := 0
			while x + 0.9 < rc.end.x - 0.2:
				swag(root, Vector3(x, ce - 0.12, z), Vector3(x + 0.9, ce - 0.12, z), 0.18, 0.012, tins[(i + int(side)) % 3], 6, 0.6)
				x += 0.9
				i += 1
		# a string of cards across the side wall
		var sx := rc.end.x - WALL_T - 0.03
		var cpts := swag(root, Vector3(sx, f + 1.8, rc.position.y + 0.8), Vector3(sx, f + 1.8, rc.end.y - 0.8), 0.15, 0.003, Color(0.9, 0.85, 0.7), 10)
		for k in range(1, cpts.size() - 1):
			var cp: Vector3 = cpts[k]
			var card := GB.box(root, Vector3(0.004, 0.13, 0.09), cp - Vector3(0.004, 0.07, 0), [Color(0.85, 0.15, 0.15), Color(0.15, 0.5, 0.25), Color(0.95, 0.92, 0.85), Color(0.2, 0.35, 0.75)][k % 4])
			card.rotation_degrees = Vector3(rng.randf_range(-8, 8), 0, 0)
	# fairy lights round every window
	for w in it.call("get_windows"):
		_window_lights(root, it, w, rng)
	# wreath on the front door (both faces, it swings with the slab)
	for dr in it.get("doors"):
		if str(dr.name) == "FrontDoor":
			var wd: float = dr.get("width")
			for sgn: float in [1.0, -1.0]:
				wreath(dr, Vector3(wd * 0.5, 1.5, sgn * 0.07), 0.16, 0.0 if sgn > 0 else 180.0, rng)
	# pavlova on the dining table (with a cake server)
	if not kitchen.is_empty():
		var tbl := _find_piece(it, "DiningTable")
		if tbl:
			var top := Furn.mesh_of("DiningTable").get_aabb().end.y
			pavlova(root, tbl.position + Vector3(0.12, top + 0.005, 0.0), rng)
	# lights strung along the hall ceiling
	for r in rooms:
		if str(r.name) == "Hall":
			var rc2: Rect2 = r.rect
			var y := float(r.ceil) - 0.08
			var pts := swag(root, Vector3(rc2.position.x + 0.3, y, rc2.get_center().y), Vector3(rc2.end.x - 0.3, y, rc2.get_center().y), 0.15, 0.003, Color(0.1, 0.1, 0.1), 14)
			var bp := []
			for i in range(1, pts.size() - 1):
				bp.append((pts[i] as Vector3) - Vector3(0, 0.02, 0))
			bulbs(root, bp, 0.014)


static func _find_piece(it: Node3D, piece: String) -> Node3D:
	for c in it.get_children():
		if c is MeshInstance3D and str(c.get_meta("piece", "")) == piece:
			return c
	return null


## A folded card standing in a V.
static func _card(parent: Node3D, p: Vector3, rng: RandomNumberGenerator) -> void:
	var cols := [Color(0.85, 0.12, 0.15), Color(0.12, 0.45, 0.25), Color(0.95, 0.93, 0.86), Color(0.2, 0.3, 0.7), GOLD]
	var c: Color = cols[rng.randi() % cols.size()]
	var h := rng.randf_range(0.11, 0.16)
	var yaw := rng.randf_range(-25, 25)
	for s: float in [-1.0, 1.0]:
		var b := GB.box(parent, Vector3(0.09, h, 0.003), p + Vector3(0, h * 0.5, s * 0.012), c)
		b.rotation_degrees = Vector3(s * 10.0, yaw, 0)
	GB.sphere(parent, 0.018, p + Vector3(0, h * 0.6, 0.02), [Color(1, 0.85, 0.3), Color(0.9, 0.1, 0.1), Color(0.2, 0.6, 0.3)][rng.randi() % 3], 0.3, Vector3(1, 1, 0.2))


static func _window_lights(parent: Node3D, it: Node3D, w: Dictionary, rng: RandomNumberGenerator) -> void:
	var X0: float = it.get("X0")
	var X1: float = it.get("X1")
	var Z0: float = it.get("Z0")
	var Z1: float = it.get("Z1")
	var off: float = it.WALL_T + 0.05
	var side := str(w.side)
	var along := float(w.along)
	var cy := float(w.y)
	var ww := float(w.w) + 0.3
	var wh := float(w.h) + 0.2
	var pts := []
	var n := 16
	for i in n + 1:
		var t := float(i) / n
		# down one side, a sagging run across the top, down the other side
		var u := 0.0
		var v := 0.0
		if t < 0.25:
			u = -ww * 0.5
			v = lerpf(-wh * 0.35, wh * 0.5, t / 0.25)
		elif t < 0.75:
			var k := (t - 0.25) / 0.5
			u = lerpf(-ww * 0.5, ww * 0.5, k)
			v = wh * 0.5 - sin(PI * k * 3.0) * 0.03
		else:
			u = ww * 0.5
			v = lerpf(wh * 0.5, -wh * 0.35, (t - 0.75) / 0.25)
		var p := Vector3.ZERO
		match side:
			"+x":
				p = Vector3(X1 - off, cy + v, along + u)
			"-x":
				p = Vector3(X0 + off, cy + v, along + u)
			"+z":
				p = Vector3(along + u, cy + v, Z1 - off)
			_:
				p = Vector3(along + u, cy + v, Z0 + off)
		pts.append(p)
	var cols := BULBS.duplicate()
	if rng.randf() < 0.4:
		cols = [Color(1.0, 0.85, 0.55)]  # some windows get warm white
	bulbs(parent, pts, 0.016, cols, 2.6)


## Pavlova: meringue base, cream, strawberries, kiwi and passionfruit.
static func pavlova(parent: Node3D, p: Vector3, rng: RandomNumberGenerator) -> void:
	GB.cylinder(parent, 0.17, 0.17, 0.015, p + Vector3(0, 0.008, 0), Color(0.97, 0.97, 0.99), Vector3.ZERO, 0.0, 24)  # plate
	GB.cylinder(parent, 0.12, 0.13, 0.07, p + Vector3(0, 0.05, 0), Color(0.98, 0.94, 0.86), Vector3.ZERO, 0.0, 20)  # meringue
	GB.sphere(parent, 0.115, p + Vector3(0, 0.09, 0), Color(1.0, 0.99, 0.95), 0.0, Vector3(1.0, 0.32, 1.0))  # cream
	for i in 7:
		var a := TAU * i / 7.0 + rng.randf_range(-0.2, 0.2)
		var rr := rng.randf_range(0.03, 0.08)
		GB.sphere(parent, 0.016, p + Vector3(cos(a) * rr, 0.118, sin(a) * rr), Color(0.9, 0.1, 0.15), 0.0, Vector3(1, 1.2, 1))
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		var k := GB.cylinder(parent, 0.02, 0.02, 0.006, p + Vector3(cos(a) * 0.06, 0.12, sin(a) * 0.06), Color(0.45, 0.75, 0.2), Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-20, 20)), 0.0, 10)
		k.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	GB.sphere(parent, 0.02, p + Vector3(0, 0.125, 0), Color(0.95, 0.75, 0.15), 0.0, Vector3(1, 0.4, 1))  # passionfruit
	GB.box(parent, Vector3(0.03, 0.004, 0.16), p + Vector3(0.2, 0.017, 0.02), Color(0.8, 0.8, 0.82), Vector3(0, 20, 0))  # cake server


# =================================================================================================
# Yard (the landing suburb houses)
# =================================================================================================

static func yard(h: Node3D, roof_type: int, width: float, depth: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 909 + roof_type * 131
	var root := Node3D.new()
	root.name = "YardDecor"
	h.add_child(root)
	var hx := width * 0.5
	var hz := depth * 0.5
	# the front lawn is on +X (the street door side)
	var fx := hx + 1.25
	var spots := [Vector3(fx, 0, -hz * 0.55), Vector3(fx + 0.35, 0, hz * 0.1), Vector3(fx, 0, hz * 0.6), Vector3(fx + 0.6, 0, -hz * 0.15)]
	var kinds := ["santa", "roo", "reindeer", "nativity"]
	# vary per house
	match roof_type:
		0:
			kinds = ["santa", "reindeer", "roo", "reindeer"]
		1:
			kinds = ["roo", "nativity", "santa", "reindeer"]
		_:
			kinds = ["reindeer", "santa", "reindeer", "roo"]
	for i in kinds.size():
		var p: Vector3 = spots[i]
		var yaw := rng.randf_range(-30, 30) + 90.0  # face the street (+X)
		match kinds[i]:
			"santa":
				inflatable_santa(root, p, yaw, rng)
			"roo":
				inflatable_roo(root, p, yaw, rng)
			"reindeer":
				wire_reindeer(root, p, yaw + rng.randf_range(-40, 40), rng.randf_range(1.15, 1.4))
			"nativity":
				nativity(root, p, yaw)
	# lit hedge along the front of the lawn
	lit_hedge(root, Vector3(hx + 2.45, 0, hz * 0.35 if roof_type == 0 else 0.0), depth * (0.45 if roof_type == 0 else 0.6), rng)
	# gum tree wrapped in lights in the corner of the yard
	lit_gum(root, Vector3(hx + 1.6, 0, -hz - 1.0 if roof_type != 2 else hz + 1.0), rng)
	# a glow on the lawn so it all reads at night
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.45)
	l.light_energy = 0.9
	l.omni_range = 6.0
	l.position = Vector3(fx + 0.8, 1.6, 0)
	l.light_cull_mask = 1
	root.add_child(l)


static func _sway(n: Node3D, deg: float, period: float) -> void:
	var tw := n.create_tween().set_loops()
	tw.tween_property(n, "rotation_degrees:z", deg, period * 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(n, "rotation_degrees:z", -deg, period * 0.5).set_trans(Tween.TRANS_SINE)


static func _ready_sway(n: Node3D, deg: float, period: float) -> void:
	if n.is_inside_tree():
		_sway(n, deg, period)
	else:
		n.tree_entered.connect(func() -> void: _sway(n, deg, period), CONNECT_ONE_SHOT)


## A blow-up Santa (1.7 m) with a fan box and guy ropes; it sways.
static func inflatable_santa(parent: Node3D, p: Vector3, yaw: float, _rng: RandomNumberGenerator) -> void:
	var base := Node3D.new()
	parent.add_child(base)
	base.position = p
	base.rotation_degrees = Vector3(0, yaw, 0)
	var s := Node3D.new()
	base.add_child(s)
	var red := Color(0.9, 0.12, 0.12)
	var white := Color(0.97, 0.97, 0.95)
	GB.sphere(s, 0.42, Vector3(0, 0.55, 0), red, 0.0, Vector3(1.0, 1.25, 0.9))  # body
	GB.cylinder(s, 0.36, 0.42, 0.08, Vector3(0, 0.12, 0), white)
	GB.cylinder(s, 0.43, 0.43, 0.07, Vector3(0, 0.6, 0), Color(0.08, 0.08, 0.08))  # belt
	GB.box(s, Vector3(0.12, 0.09, 0.05), Vector3(0, 0.6, 0.41), GOLD)
	GB.sphere(s, 0.24, Vector3(0, 1.22, 0), Color(1.0, 0.8, 0.68))  # head
	GB.sphere(s, 0.22, Vector3(0, 1.1, 0.08), white, 0.0, Vector3(1.0, 1.1, 0.8))  # beard
	GB.sphere(s, 0.04, Vector3(0, 1.24, 0.23), Color(1, 0.6, 0.55))  # nose
	for x: float in [-0.08, 0.08]:
		GB.sphere(s, 0.025, Vector3(x, 1.31, 0.2), Color(0.05, 0.05, 0.05))
	GB.cylinder(s, 0.0, 0.22, 0.4, Vector3(0, 1.55, -0.03), red, Vector3(-18, 0, 0))  # hat
	GB.cylinder(s, 0.24, 0.24, 0.07, Vector3(0, 1.38, 0), white)
	GB.sphere(s, 0.07, Vector3(0, 1.75, -0.12), white)
	for x: float in [-1.0, 1.0]:
		var arm := GB.sphere(s, 0.12, Vector3(x * 0.42, 0.8, 0.05), red, 0.0, Vector3(0.9, 1.6, 0.9))
		arm.rotation_degrees = Vector3(0, 0, x * -35)
		GB.sphere(s, 0.08, Vector3(x * 0.55, 0.55, 0.1), white)
	GB.box(base, Vector3(0.25, 0.15, 0.2), Vector3(0, 0.075, -0.45), Color(0.2, 0.2, 0.22))  # blower
	for a: float in [45.0, 135.0, 225.0, 315.0]:
		var g := Vector3(cos(deg_to_rad(a)) * 0.9, 0.0, sin(deg_to_rad(a)) * 0.9)
		_seg(base, Vector3(0, 1.0, 0), g, 0.004, Color(0.9, 0.9, 0.85))
	_ready_sway(s, 3.0, 3.2)


## A blow-up kangaroo in a Santa hat (1.5 m).
static func inflatable_roo(parent: Node3D, p: Vector3, yaw: float, _rng: RandomNumberGenerator) -> void:
	var base := Node3D.new()
	parent.add_child(base)
	base.position = p
	base.rotation_degrees = Vector3(0, yaw, 0)
	var s := Node3D.new()
	base.add_child(s)
	var fur := Color(0.78, 0.5, 0.28)
	var light := Color(0.95, 0.82, 0.62)
	GB.sphere(s, 0.32, Vector3(0, 0.55, 0), fur, 0.0, Vector3(1.0, 1.5, 0.9))
	GB.sphere(s, 0.2, Vector3(0, 0.5, 0.15), light, 0.0, Vector3(1.0, 1.4, 0.6))  # belly
	GB.sphere(s, 0.17, Vector3(0, 1.12, 0.06), fur, 0.0, Vector3(0.9, 1.0, 1.3))  # head
	GB.sphere(s, 0.08, Vector3(0, 1.08, 0.24), fur, 0.0, Vector3(1, 0.8, 1.2))  # snout
	GB.sphere(s, 0.03, Vector3(0, 1.1, 0.33), Color(0.1, 0.07, 0.06))
	for x: float in [-1.0, 1.0]:
		var ear := GB.sphere(s, 0.08, Vector3(x * 0.1, 1.33, -0.02), fur, 0.0, Vector3(0.6, 1.8, 0.4))
		ear.rotation_degrees = Vector3(0, 0, x * -20)
		GB.sphere(s, 0.022, Vector3(x * 0.07, 1.18, 0.19), Color(0.05, 0.05, 0.05))
		GB.sphere(s, 0.09, Vector3(x * 0.2, 0.12, 0.12), fur, 0.0, Vector3(0.8, 0.6, 2.0))  # feet
		GB.sphere(s, 0.07, Vector3(x * 0.25, 0.75, 0.2), Color(0.85, 0.1, 0.12))  # boxing gloves
	GB.cylinder(s, 0.05, 0.13, 0.7, Vector3(0, 0.3, -0.4), fur, Vector3(-60, 0, 0))  # tail
	GB.cylinder(s, 0.0, 0.14, 0.3, Vector3(0.03, 1.36, 0.02), Color(0.9, 0.12, 0.12), Vector3(-10, 0, -15))  # Santa hat
	GB.cylinder(s, 0.15, 0.15, 0.05, Vector3(0, 1.24, 0.03), Color(0.97, 0.97, 0.95))
	GB.sphere(s, 0.05, Vector3(0.08, 1.52, -0.02), Color(0.97, 0.97, 0.95))
	GB.box(base, Vector3(0.22, 0.14, 0.18), Vector3(0, 0.07, -0.55), Color(0.2, 0.2, 0.22))
	_ready_sway(s, 4.0, 2.7)


## Light-up wire reindeer: glowing white wire outline.
static func wire_reindeer(parent: Node3D, p: Vector3, yaw: float, sc: float) -> void:
	var r := Node3D.new()
	parent.add_child(r)
	r.position = p
	r.rotation_degrees = Vector3(0, yaw, 0)
	r.scale = Vector3.ONE * sc
	var c := Color(1.0, 0.95, 0.8)
	var e := 2.5
	var lines := [
		[Vector3(-0.35, 0.6, 0), Vector3(0.35, 0.65, 0)], [Vector3(-0.35, 0.45, 0), Vector3(0.35, 0.5, 0)],
		[Vector3(-0.35, 0.6, 0), Vector3(-0.35, 0.45, 0)], [Vector3(0.35, 0.65, 0), Vector3(0.35, 0.5, 0)],
		[Vector3(-0.3, 0.45, 0.06), Vector3(-0.32, 0.0, 0.06)], [Vector3(-0.3, 0.45, -0.06), Vector3(-0.28, 0.0, -0.06)],
		[Vector3(0.3, 0.5, 0.06), Vector3(0.33, 0.0, 0.06)], [Vector3(0.3, 0.5, -0.06), Vector3(0.28, 0.0, -0.06)],
		[Vector3(0.35, 0.62, 0), Vector3(0.48, 0.92, 0)], [Vector3(0.48, 0.92, 0), Vector3(0.66, 0.86, 0)],
		[Vector3(0.66, 0.86, 0), Vector3(0.5, 0.82, 0)], [Vector3(0.47, 0.95, 0), Vector3(0.42, 1.15, 0.05)],
		[Vector3(0.42, 1.15, 0.05), Vector3(0.32, 1.22, 0.08)], [Vector3(0.43, 1.08, 0.05), Vector3(0.55, 1.18, 0.08)],
		[Vector3(0.47, 0.95, 0), Vector3(0.44, 1.15, -0.05)], [Vector3(0.44, 1.15, -0.05), Vector3(0.36, 1.24, -0.08)],
		[Vector3(-0.35, 0.58, 0), Vector3(-0.45, 0.66, 0)]]
	for ln in lines:
		_seg(r, ln[0], ln[1], 0.018, c, e)
		bulbs(r, [ln[0], (ln[0] as Vector3).lerp(ln[1], 0.5)], 0.028, [Color(1.0, 0.95, 0.75)], 3.0)
	GB.sphere(r, 0.03, Vector3(0.67, 0.86, 0), Color(1.0, 0.2, 0.15), 3.0)  # Rudolph nose


## A small nativity: stable, figures, glowing manger, star.
static func nativity(parent: Node3D, p: Vector3, yaw: float) -> void:
	var n := Node3D.new()
	parent.add_child(n)
	n.position = p
	n.rotation_degrees = Vector3(0, yaw, 0)
	var wood := Color(0.45, 0.3, 0.18)
	for x: float in [-0.5, 0.5]:
		GB.box(n, Vector3(0.06, 0.9, 0.06), Vector3(x, 0.45, -0.3), wood)
		GB.box(n, Vector3(0.06, 0.75, 0.06), Vector3(x, 0.375, 0.25), wood)
	GB.box(n, Vector3(1.15, 0.05, 0.7), Vector3(0, 0.88, -0.02), Color(0.6, 0.45, 0.25), Vector3(-10, 0, 0))
	GB.box(n, Vector3(1.0, 0.7, 0.04), Vector3(0, 0.35, -0.33), wood.darkened(0.2))
	GB.box(n, Vector3(0.22, 0.1, 0.13), Vector3(0, 0.08, 0.0), Color(0.6, 0.45, 0.2))  # manger
	GB.sphere(n, 0.06, Vector3(0, 0.15, 0), Color(1.0, 0.95, 0.75), 2.5, Vector3(1.4, 0.7, 1.0))  # baby, glowing
	var figs := [[Vector3(-0.28, 0, 0.05), Color(0.25, 0.4, 0.8), 0.5], [Vector3(0.28, 0, 0.0), Color(0.55, 0.35, 0.2), 0.58],
			[Vector3(-0.42, 0, 0.3), Color(0.8, 0.75, 0.6), 0.3], [Vector3(0.45, 0, 0.32), Color(0.7, 0.2, 0.5), 0.52]]
	for f in figs:
		var hgt: float = f[2]
		GB.cylinder(n, hgt * 0.12, hgt * 0.3, hgt * 0.8, (f[0] as Vector3) + Vector3(0, hgt * 0.4, 0), f[1])
		GB.sphere(n, hgt * 0.13, (f[0] as Vector3) + Vector3(0, hgt * 0.9, 0), Color(0.95, 0.78, 0.6))
	GB.sphere(n, 0.08, Vector3(0, 1.1, 0.0), Color(1.0, 0.9, 0.4), 4.0, Vector3(1, 1, 0.3))  # star
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.55)
	l.light_energy = 0.8
	l.omni_range = 1.8
	l.position = Vector3(0, 0.6, 0.3)
	n.add_child(l)


## A clipped hedge covered in fairy lights.
static func lit_hedge(parent: Node3D, center: Vector3, length: float, rng: RandomNumberGenerator) -> void:
	var hg := Node3D.new()
	parent.add_child(hg)
	hg.position = center
	var n := int(length / 0.55)
	var pts := []
	for i in n:
		var z := -length * 0.5 + (i + 0.5) * length / n
		GB.sphere(hg, 0.42, Vector3(0, 0.45, z), Color(0.16, 0.42, 0.2).lerp(Color(0.22, 0.5, 0.25), rng.randf()), 0.0, Vector3(0.9, 1.15, 1.0))
		for k in 9:
			var dirb := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 1.0), rng.randf_range(-1, 1)).normalized()
			pts.append(Vector3(0, 0.45, z) + dirb * Vector3(0.9, 1.15, 1.0) * 0.44)
	bulbs(hg, pts, 0.035, BULBS if rng.randf() < 0.6 else [Color(1.0, 0.85, 0.5), Color(0.6, 0.85, 1.0)], 2.4)


## A small gum tree with a light string spiralling up the trunk and bulbs in the canopy.
static func lit_gum(parent: Node3D, p: Vector3, rng: RandomNumberGenerator) -> void:
	var t := Node3D.new()
	parent.add_child(t)
	t.position = p
	var bark := Color(0.92, 0.86, 0.78)
	var h := 3.2
	GB.cylinder(t, 0.1, 0.18, h, Vector3(0, h * 0.5, 0), bark, Vector3(0, 0, 4))
	GB.cylinder(t, 0.05, 0.09, 1.2, Vector3(0.35, h * 0.85, 0.1), bark, Vector3(20, 0, -35))
	var greens := [Color(0.3, 0.6, 0.3), Color(0.22, 0.55, 0.42), Color(0.42, 0.66, 0.25)]
	var pts := []
	for k in 6:
		var a := TAU * k / 6.0 + rng.randf_range(-0.3, 0.3)
		var off := Vector3(cos(a) * 0.7, h + rng.randf_range(-0.2, 0.5), sin(a) * 0.7)
		var r := rng.randf_range(0.55, 0.8)
		GB.sphere(t, r, off, greens[k % 3], 0.0, Vector3(1.15, 0.8, 1.15))
		for j in 6:
			var b := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.6), rng.randf_range(-1, 1)).normalized()
			pts.append(off + b * r * Vector3(1.15, 0.8, 1.15) * 1.02)
	for i in 40:
		var tt := float(i) / 39.0
		var a := tt * TAU * 6.0
		var rr := lerpf(0.2, 0.12, tt)
		pts.append(Vector3(cos(a) * rr + tt * 0.08, 0.3 + tt * (h - 0.5), sin(a) * rr))
	bulbs(t, pts, 0.045, BULBS, 3.0)
