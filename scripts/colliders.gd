extends RefCounted
## Simple solid collision for set dressing (layer 1, the sleigh / present world). Each helper
## gives a mesh (or a spot) a StaticBody3D with one primitive shape and a surface_name for the HUD.
## Touching these is never "ground" and never scores: a sleigh resting on one gets "No score here".

const WORLD_LAYER := 1


static func _body(parent: Node3D, surface: String) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = WORLD_LAYER
	b.collision_mask = 0
	b.set_meta("surface_name", surface)
	parent.add_child(b)
	return b


static func _shape(b: StaticBody3D, s: Shape3D, xf := Transform3D()) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.transform = xf
	b.add_child(cs)


## Give a GB-made MeshInstance3D a matching primitive collider (box / cylinder / sphere / prism).
static func solid(mi: MeshInstance3D, surface: String) -> MeshInstance3D:
	if mi == null or mi.mesh == null:
		return mi
	var b := _body(mi, surface)
	var m := mi.mesh
	if m is BoxMesh:
		var s := BoxShape3D.new()
		s.size = (m as BoxMesh).size
		_shape(b, s)
	elif m is CylinderMesh:
		var cm := m as CylinderMesh
		var s := CylinderShape3D.new()
		s.radius = maxf(maxf(cm.top_radius, cm.bottom_radius) * 0.85, 0.03)  # tapered: an average
		s.height = cm.height
		_shape(b, s)
	elif m is SphereMesh:
		var s := SphereShape3D.new()
		s.radius = (m as SphereMesh).radius
		_shape(b, s)
	else:
		_shape(b, m.create_convex_shape(true, true))
	return mi


static func box(parent: Node3D, size: Vector3, pos: Vector3, surface: String, rot_deg := Vector3.ZERO) -> void:
	var s := BoxShape3D.new()
	s.size = size
	var b := _body(parent, surface)
	_shape(b, s, Transform3D(Basis.from_euler(rot_deg * PI / 180.0), pos))


## Many spheres in one body (hedges): Array of [centre: Vector3, radius: float].
static func spheres(parent: Node3D, items: Array, surface: String) -> void:
	if items.is_empty():
		return
	var b := _body(parent, surface)
	for it in items:
		var s := SphereShape3D.new()
		s.radius = float(it[1])
		_shape(b, s, Transform3D(Basis(), it[0]))
