extends RefCounted
## Helpers for building the stylized (toon-shaded, Hello Neighbor-ish) meshes in code. No collision here.

const TOON := preload("res://shaders/toon.gdshader")

static var _mats: Dictionary = {}


## Toon material, cached per colour/options. emission > 0 makes it glow (windows, lanterns).
static func mat(color: Color, emission: float = 0.0, rim: float = 0.28, specular: float = 0.0) -> ShaderMaterial:
	var key := "%s|%s|%s|%s" % [color.to_html(), emission, rim, specular]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("emission_energy", emission)
	m.set_shader_parameter("rim_strength", rim)
	m.set_shader_parameter("specular_strength", specular)
	_mats[key] = m
	return m


## Uncached toon material with the visual-only warp (crooked, bulging walls).
static func warped(color: Color, height: float, bend: float, bulge: float, phase := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("warp_height", height)
	m.set_shader_parameter("bend", bend)
	m.set_shader_parameter("bulge", bulge)
	m.set_shader_parameter("warp_phase", phase)
	return m


## Uncached toon material with painterly colour patches (ground, roofs).
static func patchy(color: Color, patch: Color, strength := 0.6, scale := 0.08, specular := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("patch_color", patch)
	m.set_shader_parameter("patch_strength", strength)
	m.set_shader_parameter("patch_scale", scale)
	m.set_shader_parameter("specular_strength", specular)
	m.set_shader_parameter("rim_strength", 0.12)
	return m


## Swap every imported material in a model (glTF) for the toon material of the same colour.
## Emissive source materials stay glowing. overrides: material name -> Material.
static func toonify(root: Node, overrides: Dictionary = {}) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var mname := src.resource_name if src != null else ""
			if overrides.has(mname):
				mi.set_surface_override_material(i, overrides[mname])
				continue
			var color := Color.WHITE
			var emit := 0.0
			if src is StandardMaterial3D:
				var sm := src as StandardMaterial3D
				color = sm.albedo_color
				if sm.emission_enabled:
					emit = 2.2
			mi.set_surface_override_material(i, mat(color, emit))


static func add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, rot_deg: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rot_deg := Vector3.ZERO, emission := 0.0) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return add_mesh(parent, m, pos, rot_deg, mat(color, emission))


static func cylinder(parent: Node3D, top_r: float, bottom_r: float, height: float, pos: Vector3, color: Color, rot_deg := Vector3.ZERO, emission := 0.0, segments := 16) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = height
	m.radial_segments = segments
	return add_mesh(parent, m, pos, rot_deg, mat(color, emission))


static func sphere(parent: Node3D, radius: float, pos: Vector3, color: Color, emission := 0.0, squash := Vector3.ONE) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 20
	m.rings = 10
	var mi := add_mesh(parent, m, pos, Vector3.ZERO, mat(color, emission))
	mi.scale = squash
	return mi


static func capsule(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = maxf(height, radius * 2.0)
	return add_mesh(parent, m, pos, rot_deg, mat(color))


static func torus(parent: Node3D, inner_r: float, outer_r: float, pos: Vector3, color: Color, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var m := TorusMesh.new()
	m.inner_radius = inner_r
	m.outer_radius = outer_r
	m.rings = 24
	m.ring_segments = 10
	return add_mesh(parent, m, pos, rot_deg, mat(color))


static func omni(parent: Node3D, pos: Vector3, color: Color, energy := 1.5, light_range := 6.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	parent.add_child(l)
	return l
