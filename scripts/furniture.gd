extends RefCounted
## Furniture library: instances pieces modelled in Blender (assets/models/furniture.glb, built by
## tools/blender/build_models.py). Each piece's parts are merged into one mesh per material (few
## draw calls), toon-shaded, and optionally given colliders on the interior collision layer so the
## elf bumps into it. Collision is legs + raised body: parts named "Leg*"/"Post*" get thin boxes of
## their own and everything else is one box from the body's real bottom up, so there is open space
## under couches, beds, tables, chairs, side tables, the TV unit and the wardrobe (the crouched elf
## crawls under them). Pieces without legs (counters, fridge, bookshelf) stay solid to the floor.
## Piece fronts face -Z.

const GB := preload("res://scripts/greybox.gd")
const SCENE := preload("res://assets/models/furniture.glb")
const INTERIOR_LAYER := 4  ## Physics layer 3: interior walls, floors and furniture (only the elf sees it).
const VIS_RANGE := 40.0  ## Interiors stop drawing beyond this distance (they are only seen up close).

static var _cache: Dictionary = {}  # name -> ArrayMesh with toon materials
static var _colliders: Dictionary = {}  # name -> Array of AABB (body first, then legs), piece-local
static var _bodies: Dictionary = {}  # name -> ArrayMesh without the legs/posts (for height tiers)
static var _leg_mats: Dictionary = {}  # name -> Material of the legs
static var _tiered: Dictionary = {}  # "name|gap" -> [ArrayMesh, Array of AABB]


static func _material_for(src: Material) -> Material:
	var color := Color.WHITE
	var emit := 0.0
	var mname := src.resource_name if src != null else ""
	if src is StandardMaterial3D:
		var sm := src as StandardMaterial3D
		color = sm.albedo_color
		if sm.emission_enabled:
			emit = 2.4
	if mname == "Brick":
		return brick_material(color)
	if mname.begins_with("Wood"):
		var m := GB.mat(color).duplicate() as ShaderMaterial
		m.set_shader_parameter("pattern", 3)
		m.set_shader_parameter("pattern_color", color.darkened(0.18))
		m.set_shader_parameter("pattern_scale", 0.35)
		return m
	if mname == "TreeGreen" or mname == "TreeGreenDark":
		var t := GB.mat(color).duplicate() as ShaderMaterial
		t.set_shader_parameter("pattern", 6)
		t.set_shader_parameter("pattern_color", color.lightened(0.25))
		t.set_shader_parameter("pattern_scale", 0.6)
		return t
	return GB.mat(color, emit, 0.18)


static func brick_material(color := Color(0.72, 0.3, 0.2)) -> ShaderMaterial:
	var m := GB.mat(color).duplicate() as ShaderMaterial
	m.set_shader_parameter("pattern", 5)
	m.set_shader_parameter("pattern_color", Color(0.9, 0.82, 0.72))
	m.set_shader_parameter("pattern_scale", 1.0)
	return m


## Merged mesh for a piece (cached).
static func mesh_of(piece: String) -> ArrayMesh:
	if _cache.has(piece):
		return _cache[piece]
	if _cache.is_empty():
		# Build every piece once, then free the imported scene (nothing stays instanced).
		var root := SCENE.instantiate() as Node3D
		for c in root.get_children():
			_cache[str(c.name)] = _merge(c as Node3D)
			_colliders[str(c.name)] = _collision_boxes(c as Node3D)
			_bodies[str(c.name)] = _merge(c as Node3D, true)
			for n in (c as Node3D).find_children("*", "MeshInstance3D", true, false):
				var nm := str(n.name)
				if nm.begins_with("Leg") or nm.begins_with("Post"):
					_leg_mats[str(c.name)] = _material_for((n as MeshInstance3D).get_active_material(0))
					break
		root.free()
	if not _cache.has(piece):
		push_error("furniture: no piece named %s" % piece)
		_cache[piece] = null
	return _cache[piece]


static func _merge(src: Node3D, skip_legs := false) -> ArrayMesh:
	var groups: Dictionary = {}  # material key -> [SurfaceTool, Material]
	for n in src.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if skip_legs and (str(mi.name).begins_with("Leg") or str(mi.name).begins_with("Post")):
			continue
		var xf := _relative(mi, src)
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			var key := m.resource_name if m != null else "none"
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = [st, _material_for(m)]
			(groups[key][0] as SurfaceTool).append_from(mi.mesh, s, xf)
	var out := ArrayMesh.new()
	for key in groups:
		var st: SurfaceTool = groups[key][0]
		st.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, groups[key][1])
	return out


## Body box (everything that isn't a leg) + one box per leg, in piece space.
static func _collision_boxes(src: Node3D) -> Array:
	var body := AABB()
	var has_body := false
	var legs: Array = []
	for n in src.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var ab := _relative(mi, src) * mi.mesh.get_aabb()
		var nm := str(mi.name)
		if nm.begins_with("Leg") or nm.begins_with("Post"):
			legs.append(ab)
		else:
			body = ab if not has_body else body.merge(ab)
			has_body = true
	var out: Array = [body]
	out.append_array(legs)
	return out


## Lowest point of a piece's body (its clearance above the floor; 0 = solid to the floor).
static func clearance_of(piece: String) -> float:
	mesh_of(piece)
	var boxes: Array = _colliders.get(piece, [])
	return maxf(0.0, (boxes[0] as AABB).position.y) if not boxes.is_empty() else 0.0


static func _relative(n: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != ancestor:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## A piece re-legged to a different gap under its body (furniture height tiers). The body (and
## anything resting on it) moves up or down by gap - clearance; the legs/posts are rebuilt to
## reach the floor: squat bun feet for a low gap, turned legs for a mid gap, tall tapered legs
## with brass caps for a high gap. Returns [mesh, collision boxes] (cached per piece and gap).
static func tiered(piece: String, gap: float) -> Array:
	var key := "%s|%.3f" % [piece, gap]
	if _tiered.has(key):
		return _tiered[key]
	mesh_of(piece)
	var boxes: Array = _colliders.get(piece, [])
	var clr := clearance_of(piece)
	if boxes.size() < 2 or clr <= 0.0:
		_tiered[key] = [mesh_of(piece), boxes]
		return _tiered[key]
	var dy := gap - clr
	var st := SurfaceTool.new()
	var out := (_bodies[piece] as ArrayMesh).duplicate() as ArrayMesh
	# shift the body surfaces by dy
	var shifted := ArrayMesh.new()
	for si in out.get_surface_count():
		var arr := out.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for vi in verts.size():
			verts[vi].y += dy
		arr[Mesh.ARRAY_VERTEX] = verts
		shifted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		shifted.surface_set_material(si, out.surface_get_material(si))
	var low := gap < 0.16
	var high := gap > 0.22
	var new_boxes: Array = [AABB((boxes[0] as AABB).position + Vector3(0, dy, 0), (boxes[0] as AABB).size)]
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var brass := SurfaceTool.new()
	brass.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, boxes.size()):
		var ab: AABB = boxes[i]
		var top := maxf(0.02, ab.end.y + dy)
		var c := ab.get_center()
		var w := minf(ab.size.x, ab.size.z)
		var leg_h := top
		var lm: Mesh
		var lxf := Transform3D(Basis(), Vector3(c.x, top * 0.5, c.z))
		if low and ab.end.y + dy < 0.25:
			# squat bun foot (wider than the original leg) under the low body
			var sm := SphereMesh.new()
			sm.radius = maxf(w * 0.75, 0.025)
			sm.height = sm.radius * 2.0
			sm.radial_segments = 10
			sm.rings = 6
			lm = sm
			lxf = Transform3D(Basis().scaled(Vector3(1, top / (sm.radius * 2.0), 1)), Vector3(c.x, top * 0.5, c.z))
		elif ab.size.x > w * 2.5 or ab.size.z > w * 2.5 or ab.size.y > 0.6:
			# a board or a tall post: a box of the original footprint
			var bm := BoxMesh.new()
			bm.size = Vector3(ab.size.x, leg_h, ab.size.z)
			lm = bm
		else:
			var cm := CylinderMesh.new()
			cm.top_radius = w * 0.5
			cm.bottom_radius = w * (0.3 if high else 0.42)
			cm.height = leg_h
			cm.radial_segments = 10
			cm.rings = 1
			lm = cm
			if high:
				var cap := CylinderMesh.new()
				cap.top_radius = w * 0.32
				cap.bottom_radius = w * 0.34
				cap.height = 0.02
				cap.radial_segments = 10
				brass.append_from(cap, 0, Transform3D(Basis(), Vector3(c.x, 0.01, c.z)))
		st.append_from(lm, 0, lxf)
		new_boxes.append(AABB(Vector3(ab.position.x, 0.0, ab.position.z), Vector3(ab.size.x, top, ab.size.z)))
	st.generate_normals()
	st.commit(shifted)
	shifted.surface_set_material(shifted.get_surface_count() - 1, _leg_mats.get(piece, GB.mat(Color(0.35, 0.22, 0.12))))
	if high:
		brass.commit(shifted)
		shifted.surface_set_material(shifted.get_surface_count() - 1, GB.mat(Color(1.0, 0.76, 0.3), 0.15, 0.3, 0.6))
	_tiered[key] = [shifted, new_boxes]
	return _tiered[key]


## Place a piece. yaw_deg turns its front (-Z) around Y. solid = box collider from its bounds.
## gap >= 0 re-legs it to that gap under the body (see tiered()); meta "tier_dy" = body shift (m).
static func spawn(piece: String, parent: Node3D, pos: Vector3, yaw_deg := 0.0, solid := true, scale := 1.0, gap := -1.0) -> MeshInstance3D:
	var mesh := mesh_of(piece)
	var tier_boxes: Array = []
	var dy := 0.0
	if gap >= 0.0 and clearance_of(piece) > 0.0:
		var t := tiered(piece, gap)
		mesh = t[0]
		tier_boxes = t[1]
		dy = gap - clearance_of(piece)
	var mi := MeshInstance3D.new()
	mi.name = piece
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = Vector3(0, yaw_deg, 0)
	mi.scale = Vector3.ONE * scale
	mi.visibility_range_end = VIS_RANGE
	mi.visibility_range_end_margin = 4.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	mi.set_meta("tier_dy", dy)
	mi.set_meta("piece", piece)
	mi.set_meta("gap", gap if gap >= 0.0 else clearance_of(piece))
	parent.add_child(mi)
	if solid and mesh != null:
		var body := StaticBody3D.new()
		body.collision_layer = INTERIOR_LAYER
		body.collision_mask = 0
		var boxes: Array = tier_boxes if not tier_boxes.is_empty() else _colliders.get(piece, [mesh.get_aabb()])
		for i in boxes.size():
			var ab: AABB = boxes[i]
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			# body: trimmed a little at the sides (bevels) but its bottom stays exact (the clearance)
			bs.size = Vector3(ab.size.x * 0.95, ab.size.y, ab.size.z * 0.95) if i == 0 else ab.size
			cs.shape = bs
			cs.position = ab.get_center()
			body.add_child(cs)
		mi.add_child(body)
	return mi


## Size of a piece's bounds (unrotated, unscaled).
static func size_of(piece: String) -> Vector3:
	var m := mesh_of(piece)
	return m.get_aabb().size if m != null else Vector3.ONE
