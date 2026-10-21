extends Node
## Collision debug draw (C on the sleigh, F9 anywhere): see-through tinted volumes of every CollisionShape3D in
## the scene, coloured by physics layer. Orange = sleigh world (1), green = reindeer feet only (2),
## cyan = interior / elf (3), pink = residents, yellow = darts.

var enabled := false
var _mats: Dictionary = {}


func toggle() -> void:
	set_enabled(not enabled)


func set_enabled(on: bool) -> void:
	enabled = on
	if on:
		_add_all(get_tree().root)
	for n in get_tree().get_nodes_in_group("collision_debug_mesh"):
		(n as Node3D).visible = on


func _mat(layer: int) -> StandardMaterial3D:
	if _mats.has(layer):
		return _mats[layer]
	var c := Color(1.0, 0.55, 0.1)
	if layer & 1 == 0:
		if layer & 4:
			c = Color(0.2, 0.95, 1.0)
		elif layer & 16:
			c = Color(1.0, 0.4, 0.8)
		elif layer & 32:
			c = Color(1.0, 0.95, 0.2)
		elif layer & 2:
			c = Color(0.3, 1.0, 0.35)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Godot 4.7 debug meshes include faces: draw them as see-through tinted volumes so the
	# scenery stays readable underneath
	c.a = 0.32
	m.albedo_color = c
	m.vertex_color_use_as_albedo = false
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_mats[layer] = m
	return m


func _add_all(n: Node) -> void:
	if n is CollisionShape3D:
		var cs := n as CollisionShape3D
		if cs.shape != null and not cs.has_node("CollisionDebug"):
			var co := cs.get_parent() as CollisionObject3D
			var layer := co.collision_layer if co else 1
			var mi := MeshInstance3D.new()
			mi.name = "CollisionDebug"
			mi.mesh = cs.shape.get_debug_mesh()
			mi.material_override = _mat(layer)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.layers = 1 | 2
			mi.add_to_group("collision_debug_mesh")
			cs.add_child(mi)
	for c in n.get_children():
		_add_all(c)
