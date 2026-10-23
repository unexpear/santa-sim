extends RefCounted
## THE shared parts library (rigs, checks, and the player build tool in scripts/build/ all use it).
## Detailed household-item meshes from assets/models/rig_parts.glb, built by
## tools/blender/build_rig_parts.py at real size (metres), Godot axes, origin at the physics centre.
## Pieces: Pulley, CottonReel, ReelCrank, Ruler, Crayon, Spoon, MarbleTin, CoalSack, Present, Book,
## Bauble, LeverHandle, KnobHandle, CookiePlate, MilkGlassEmpty.
## REF is each piece's modelled size, so callers scale a piece to their physics body exactly.
## Materials: toon like the furniture; Metal* and Glass* get a highlight, the rest stay matte.

const GB := preload("res://scripts/greybox.gd")
const PATH := "res://assets/models/rig_parts.glb"

const REF := {
	"Pulley": Vector3(0.052, 0.12, 0.03), "CottonReel": Vector3(0.038, 0.038, 0.07), "Ruler": Vector3(0.3, 0.0035, 0.03),
	"Crayon": Vector3(0.1, 0.012, 0.012), "Spoon": Vector3(0.5, 0.02, 0.06), "MarbleTin": Vector3(0.1, 0.12, 0.1),
	"CoalSack": Vector3(0.1, 0.13, 0.09), "Present": Vector3(0.2, 0.16, 0.2), "Book": Vector3(0.15, 0.025, 0.21),
	"Bauble": Vector3(0.06, 0.06, 0.06),
}
static var _cache: Dictionary = {}
static var _loaded := false


static func has(piece: String) -> bool:
	return mesh(piece) != null


static func mesh(piece: String) -> ArrayMesh:
	if not _loaded:
		_loaded = true
		if ResourceLoader.exists(PATH):
			var root := (load(PATH) as PackedScene).instantiate() as Node3D
			for c in root.get_children():
				_cache[str(c.name)] = _merge(c as Node3D)
			root.free()
		else:
			push_warning("part_models: %s not imported; parts fall back to primitives" % PATH)
	return _cache.get(piece, null)


## Add a piece under parent (local pos / rotation in degrees / scale). Null if the piece is missing.
static func add(parent: Node3D, piece: String, pos := Vector3.ZERO, rot_deg := Vector3.ZERO, scale := Vector3.ONE) -> MeshInstance3D:
	var m := mesh(piece)
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = piece
	mi.mesh = m
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scale
	parent.add_child(mi)
	return mi


## Scale that makes a piece fill a physics box of this size.
static func fit(piece: String, size: Vector3) -> Vector3:
	var r: Vector3 = REF.get(piece, Vector3.ONE)
	return Vector3(size.x / r.x, size.y / r.y, size.z / r.z)


static func material_for(src: Material) -> Material:
	var color := Color.WHITE
	var mname := src.resource_name if src != null else ""
	if src is StandardMaterial3D:
		color = (src as StandardMaterial3D).albedo_color
	if mname.begins_with("Glass"):
		return GB.mat(color, 0.12, 0.55, 0.9)
	if mname.begins_with("Metal"):
		return GB.mat(color, 0.0, 0.35, 0.6)
	if mname == "Thread" or mname == "Twine":
		var t := GB.mat(color, 0.0, 0.12).duplicate() as ShaderMaterial
		t.set_shader_parameter("pattern", 9)
		t.set_shader_parameter("pattern_color", color.darkened(0.25))
		return t
	return GB.mat(color, 0.0, 0.18)


static func _merge(src: Node3D) -> ArrayMesh:
	var groups: Dictionary = {}
	for n in src.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var xf := src.global_transform.affine_inverse() * mi.global_transform if src.is_inside_tree() else _rel(mi, src)
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			var key := m.resource_name if m != null else "none"
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = [st, material_for(m)]
			(groups[key][0] as SurfaceTool).append_from(mi.mesh, s, xf)
	var out := ArrayMesh.new()
	for key in groups:
		(groups[key][0] as SurfaceTool).commit(out)
		out.surface_set_material(out.get_surface_count() - 1, groups[key][1])
	return out


static func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != root and c is Node3D:
		t = (c as Node3D).transform * t
		c = c.get_parent()
	return t
