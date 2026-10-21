extends Node3D
## VISUAL ONLY set dressing that turns the landing test into a little Aussie street at night:
## footpaths, nature strips, driveways and front paths, picket fences, letterboxes, hedges,
## streetlights with warm pools, crooked warm-lit background houses, Hills Hoists, lawn patches,
## gentle back-yard mounds, distant hills, a far-off town skyline and fireflies.
## Houses, fences, letterboxes, hedges, streetlights and Hills Hoists have simple solid collision
## (colliders.gd, layer 1): the sleigh can bump them or rest on a roof, but only the three landing
## houses score. Flat slabs (paths, lawns) and the distant scenery stay visual only.

const GB := preload("res://scripts/greybox.gd")
const TOON := preload("res://shaders/toon.gdshader")
const LightString := preload("res://scripts/light_string.gd")
const C := preload("res://scripts/colliders.gd")

const WARM := Color(1.0, 0.68, 0.32)
const ROAD_LEFT := -1.6  ## Kerb lines (match main.gd's road).
const ROAD_RIGHT := 5.6
const PATH_W := 1.8
const LEFT_PATH_X := -3.45
const RIGHT_PATH_X := 7.45
const LEFT_FENCE_X := -4.55
const RIGHT_FENCE_X := 8.55
const Z_MIN := -190.0
const Z_MAX := 40.0

@export var landing_houses: Array[Node3D] = []
@export_group("Street")
@export var streetlight_spacing := 32.0
@export var streetlight_energy := 2.6
@export var streetlight_range := 11.0
@export var background_house_light := 0.7
@export var background_mute := 0.4  ## Pull background house colours toward a soft dusk grey.
@export var firefly_spots := 16
@export var firefly_glow := 3.0  ## HDR brightness of the fireflies (glow/bloom picks them up).
@export var firefly_size := 0.05
@export_group("Distance")
@export var hill_count := 22
@export var skyline_buildings := 34
@export var mound_count := 14

var _rng := RandomNumberGenerator.new()
var _blocked: Array[Rect2] = []  ## Ground footprints (x, z) that trees and props should avoid.
var _gaps := {"left": [], "right": []}  ## Fence gaps (z ranges) for paths and driveways.
var _picket_xforms: Array[Transform3D] = []
var _rail_xforms: Array[Transform3D] = []
var _hedge_xforms := {"a": [], "b": []}
var _firefly_points: Array[Vector3] = []
var streetlight_heads: Array[Vector3] = []  ## world positions of the lamp heads (moths, haze)
var bg_chimney_tops: Array[Vector3] = []  ## background house chimney tops (smoke wisps)


func _ready() -> void:
	_rng.seed = 2026
	# Reserve the landing houses and the launch pad / runway.
	for h in landing_houses:
		var w := float(h.get("width")) + 9.0
		var d := float(h.get("depth")) + 2.0
		_blocked.append(Rect2(h.global_position.x - w * 0.5, h.global_position.z - d * 0.5, w, d))
	_blocked.append(Rect2(-4.5, -21.0, 9.0, 26.0))
	_footpaths()
	for h in landing_houses:
		_frontage(h.get_door_world(), h.get_door_normal_world(), float(h.get("depth")), true)
	_background_houses()
	_streetlights()
	_fences()
	_hedges()
	_distance()
	_fireflies()


func is_clear(p: Vector3, r: float) -> bool:
	if p.x > ROAD_LEFT - 4.0 and p.x < ROAD_RIGHT + 4.0:
		return false
	for b in _blocked:
		if b.grow(r).has_point(Vector2(p.x, p.z)):
			return false
	return true


# --- street surfaces ---------------------------------------------------------------------------------

func _slab(size: Vector3, pos: Vector3, color: Color, patch := 0.0) -> void:
	var m := BoxMesh.new()
	m.size = size
	var mat: Material = GB.patchy(color, color.darkened(0.12), patch, 0.4) if patch > 0.0 else GB.mat(color)
	var mi := GB.add_mesh(self, m, pos, Vector3.ZERO, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _footpaths() -> void:
	var concrete := Color(0.62, 0.56, 0.6)
	var strip := Color(0.24, 0.46, 0.16)
	for side: float in [-1.0, 1.0]:
		var px := LEFT_PATH_X if side < 0.0 else RIGHT_PATH_X
		var kerb := ROAD_LEFT if side < 0.0 else ROAD_RIGHT
		# Left side skips the launch pad (it sits across the footpath there).
		var spans: Array = [[Z_MIN, -4.6], [4.6, Z_MAX]] if side < 0.0 else [[Z_MIN, Z_MAX]]
		for sp in spans:
			var z0 := float(sp[0])
			var z1 := float(sp[1])
			_slab(Vector3(PATH_W, 0.08, z1 - z0), Vector3(px, 0.04, (z0 + z1) * 0.5), concrete, 0.6)
			var sw := absf(px - kerb) - PATH_W * 0.5
			_slab(Vector3(sw, 0.03, z1 - z0), Vector3((kerb + px - side * PATH_W * 0.5) * 0.5, 0.015, (z0 + z1) * 0.5), strip, 0.0)
			# Expansion joints
			var z := z0
			while z < z1:
				GB.box(self, Vector3(PATH_W, 0.012, 0.05), Vector3(px, 0.085, z), concrete.darkened(0.25))
				z += 2.0


## Front path from the door to the footpath, a driveway beside it, a letterbox and lawn.
func _frontage(door: Vector3, normal: Vector3, house_depth: float, landing: bool) -> void:
	var left := normal.x > 0.0  # door faces +X => house is on the left of the street
	var fence_x := LEFT_FENCE_X if left else RIGHT_FENCE_X
	var path_edge := LEFT_PATH_X + PATH_W * 0.5 if left else RIGHT_PATH_X - PATH_W * 0.5
	var x0 := door.x
	var plen := absf(path_edge - x0)
	var concrete := Color(0.66, 0.6, 0.62)
	# Path from the door step to the footpath
	_slab(Vector3(plen, 0.06, 1.1), Vector3((x0 + path_edge) * 0.5, 0.03, door.z), concrete, 0.5)
	# Driveway (from the kerb to beside the house)
	var dz := door.z + house_depth * 0.5 - 1.4
	var kerb := ROAD_LEFT if left else ROAD_RIGHT
	var dx1 := door.x - (1.0 if left else -1.0) * 1.2  # runs up to the front wall
	_slab(Vector3(absf(kerb - dx1), 0.05, 3.0), Vector3((kerb + dx1) * 0.5, 0.03, dz), Color(0.5, 0.46, 0.5), 0.7)
	_gaps["left" if left else "right"].append(Vector2(door.z - 0.7, door.z + 0.7))
	_gaps["left" if left else "right"].append(Vector2(dz - 1.7, dz + 1.7))
	# Letterbox at the fence line beside the path
	_letterbox(Vector3(fence_x, 0.0, door.z + 1.15), 1.0 if left else -1.0)
	# Lawn patch in the front yard (a shade lighter than the field)
	var yard_w := absf(x0 - fence_x)
	_slab(Vector3(yard_w, 0.02, house_depth), Vector3((x0 + fence_x) * 0.5, 0.01, door.z), Color(0.27, 0.5, 0.18), 0.0)
	_firefly_points.append(door + normal * 1.5 + Vector3.UP * 1.0)


func _letterbox(pos: Vector3, facing: float) -> void:
	var colors := [Color(0.85, 0.15, 0.12), Color(0.15, 0.4, 0.8), Color(0.95, 0.75, 0.1), Color(0.2, 0.6, 0.3)]
	var c: Color = colors[_rng.randi() % colors.size()]
	var lb := Node3D.new()
	lb.position = pos
	lb.rotation_degrees = Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(-6, 6))
	add_child(lb)
	C.solid(GB.box(lb, Vector3(0.12, 1.0, 0.12), Vector3(0, 0.5, 0), Color(0.45, 0.3, 0.18)), "Letterbox")
	C.solid(GB.box(lb, Vector3(0.5, 0.42, 0.36), Vector3(0, 1.15, 0), c), "Letterbox")
	GB.cylinder(lb, 0.18, 0.18, 0.5, Vector3(0, 1.36, 0), c.lightened(0.1), Vector3(0, 0, 90), 0.0, 10)
	GB.box(lb, Vector3(0.04, 0.05, 0.22), Vector3(facing * 0.26, 1.22, 0), Color(0.1, 0.08, 0.08))  # slot
	GB.box(lb, Vector3(0.03, 0.22, 0.05), Vector3(0, 1.45, 0.2), Color(1.0, 0.3, 0.1))  # flag


# --- houses ------------------------------------------------------------------------------------------

func _background_houses() -> void:
	var left_slots := [24.0, 6.0, -16.0, -62.0, -86.0, -134.0, -158.0, -180.0]
	var right_slots := [24.0, 4.0, -16.0, -38.0, -56.0, -96.0, -116.0, -138.0, -160.0]
	var palette := [Color(0.95, 0.55, 0.3), Color(0.55, 0.75, 0.45), Color(0.9, 0.8, 0.45), Color(0.6, 0.5, 0.85),
			Color(0.95, 0.45, 0.55), Color(0.45, 0.7, 0.8), Color(0.98, 0.65, 0.2)]
	var i := 0
	for z in left_slots:
		_bg_house(z, -1.0, palette[i % palette.size()], i)
		i += 1
	for z in right_slots:
		_bg_house(z, 1.0, palette[i % palette.size()], i)
		i += 1


func _bg_house(z: float, side: float, wall: Color, idx: int) -> void:
	var w := _rng.randf_range(7.5, 10.0)  # along x (away from the street)
	var d := _rng.randf_range(8.0, 10.0)  # along z (frontage)
	var h := _rng.randf_range(3.0, 3.9)
	var front_x := (LEFT_FENCE_X - _rng.randf_range(2.8, 4.0)) if side < 0.0 else (RIGHT_FENCE_X + _rng.randf_range(2.8, 4.0))
	var cx := front_x + side * w * 0.5
	var root := Node3D.new()
	root.position = Vector3(cx, 0, z)
	root.rotation_degrees = Vector3(0, _rng.randf_range(-3, 3), 0)
	add_child(root)
	_blocked.append(Rect2(cx - w * 0.5 - 2.0, z - d * 0.5 - 2.0, w + 4.0, d + 4.0))
	var trim: Color = [Color(1, 0.95, 0.85), Color(0.35, 0.2, 0.55), Color(0.2, 0.45, 0.5), Color(0.6, 0.2, 0.15)][idx % 4]
	var roof: Color = [Color(0.7, 0.18, 0.12), Color(0.25, 0.3, 0.5), Color(0.35, 0.22, 0.4), Color(0.55, 0.4, 0.3)][idx % 4]
	# Muted next to the landing houses so the lit target roofs stay the clearest things in view.
	roof = roof.lerp(Color(0.3, 0.27, 0.36), background_mute)
	wall = wall.lerp(Color(0.5, 0.45, 0.55), background_mute * 0.8)
	var phase := _rng.randf_range(0.0, TAU)
	var wm := BoxMesh.new()
	wm.size = Vector3(w, h, d)
	wm.subdivide_width = 4
	wm.subdivide_height = 6
	wm.subdivide_depth = 4
	GB.add_mesh(root, wm, Vector3(0, h * 0.5, 0), Vector3.ZERO, GB.warped(wall, h, _rng.randf_range(-0.25, 0.25), 0.04, phase))
	C.box(root, Vector3(w, h, d), Vector3(0, h * 0.5, 0), "Neighbour's house")
	GB.box(root, Vector3(w + 0.3, 0.3, d + 0.3), Vector3(0, 0.15, 0), trim.darkened(0.3))
	# Gable roof (ridge along the frontage), slightly crooked
	var rise := _rng.randf_range(1.6, 2.6)
	var pm := PrismMesh.new()
	pm.size = Vector3(w + 0.9, rise, d + 0.9)
	C.solid(GB.add_mesh(root, pm, Vector3(0, h + rise * 0.5, 0), Vector3(0, 0, _rng.randf_range(-3, 3)), GB.patchy(roof, roof.lightened(0.15), 0.5, 0.6)), "Neighbour's roof")
	# Leaning chimney
	var cz := _rng.randf_range(-d * 0.3, d * 0.3)
	var chim := GB.cylinder(root, 0.55, 0.45, 2.2, Vector3(-side * w * 0.2, h + rise * 0.6, cz), Color(0.7, 0.28, 0.2), Vector3(_rng.randf_range(-6, 6), 45, _rng.randf_range(-8, 8)), 0.0, 4)
	C.solid(chim, "Neighbour's chimney")
	bg_chimney_tops.append(root.position + root.basis * (chim.position + chim.basis.y * 1.15))
	# Street-facing windows + door
	var face_x := -side * (w * 0.5 + 0.06)
	var rot := Vector3(0, -side * 90, 0)
	for wz in [-d * 0.3, d * 0.3]:
		var win := Node3D.new()
		win.position = Vector3(face_x, 1.8, wz)
		win.rotation_degrees = rot + Vector3(0, 0, _rng.randf_range(-6, 6))
		root.add_child(win)
		GB.box(win, Vector3(1.6, 1.4, 0.12), Vector3.ZERO, trim)
		var lit := _rng.randf() < 0.8
		GB.box(win, Vector3(1.25, 1.05, 0.16), Vector3.ZERO, WARM if lit else Color(0.2, 0.15, 0.3), Vector3.ZERO, 1.2 if lit else 0.0)
		GB.box(win, Vector3(0.08, 1.05, 0.2), Vector3.ZERO, trim)
	var door := Node3D.new()
	door.position = Vector3(face_x, 1.05, 0)
	door.rotation_degrees = rot
	root.add_child(door)
	GB.box(door, Vector3(1.1, 2.1, 0.16), Vector3.ZERO, trim)
	GB.box(door, Vector3(0.9, 1.9, 0.2), Vector3(0, -0.05, 0.02), Color(0.4, 0.2, 0.1))
	GB.sphere(door, 0.11, Vector3(0.8, 0.8, 0.25), WARM, 3.0)
	C.solid(GB.box(door, Vector3(1.9, 0.15, 1.0), Vector3(0, 1.3, 0.5), roof, Vector3(-12, 0, 0)), "Porch roof")
	var porch := GB.omni(door, Vector3(0.8, 0.6, 0.9), WARM, background_house_light, 3.5)
	porch.omni_attenuation = 1.6
	# Eave Christmas lights on most houses (mixed colours, dimmer than the landing roofs)
	if _rng.randf() < 0.75:
		var ls := LightString.new()
		root.add_child(ls)
		var ex := -side * (w * 0.5 + 0.35)
		ls.setup(PackedVector3Array([Vector3(ex, h + 0.05, -d * 0.5 - 0.3), Vector3(ex, h + 0.05, d * 0.5 + 0.3)]), WARM, false, 0.75, true, false)
	var door_world := root.to_global(Vector3(face_x - side * 1.2, 0, 0))
	_frontage(door_world, Vector3(-side, 0, 0), d, false)
	# A Hills Hoist out the back of a couple of them
	if idx == 2 or idx == 11:
		_hills_hoist(root.to_global(Vector3(side * (w * 0.5 + 5.0), 0, 0)))


func _hills_hoist(p: Vector3) -> void:
	var hh := Node3D.new()
	hh.position = p
	hh.rotation_degrees = Vector3(0, _rng.randf_range(0, 90), _rng.randf_range(-3, 3))
	add_child(hh)
	var metal := Color(0.75, 0.75, 0.8)
	C.solid(GB.cylinder(hh, 0.06, 0.07, 2.3, Vector3(0, 1.15, 0), metal), "Hills Hoist")
	for a in 4:
		var arm := Node3D.new()
		arm.position = Vector3(0, 2.25, 0)
		arm.rotation_degrees = Vector3(0, a * 90.0, 0)
		hh.add_child(arm)
		C.solid(GB.box(arm, Vector3(0.05, 0.05, 2.0), Vector3(0, 0.15, 1.0), metal, Vector3(-8, 0, 0)), "Hills Hoist")
	for k in 4:
		var s := 0.5 + k * 0.45
		for a in 4:
			var arm2 := Node3D.new()
			arm2.position = Vector3(0, 2.3 + s * 0.14, 0)
			arm2.rotation_degrees = Vector3(0, a * 90.0 + 45.0, 0)
			hh.add_child(arm2)
			GB.box(arm2, Vector3(s * 1.414, 0.012, 0.012), Vector3(0, 0, s * 0.707), Color(0.9, 0.9, 0.85))
	# Someone left a towel and a pair of boardies on the line
	GB.box(hh, Vector3(0.7, 0.5, 0.02), Vector3(0.6, 2.2, 0.6), Color(0.95, 0.35, 0.4), Vector3(0, 45, 0))
	GB.box(hh, Vector3(0.45, 0.45, 0.02), Vector3(-0.7, 2.2, 0.5), Color(0.2, 0.6, 0.9), Vector3(0, -45, 0))


# --- street furniture --------------------------------------------------------------------------------

func _streetlights() -> void:
	for side: float in [-1.0, 1.0]:
		var x := ROAD_LEFT - 0.45 if side < 0.0 else ROAD_RIGHT + 0.45
		var z := Z_MAX - 6.0 - (streetlight_spacing * 0.5 if side > 0.0 else 0.0)
		while z > Z_MIN:
			if not (side < 0.0 and absf(z) < 7.0):
				_streetlight(Vector3(x, 0, z), -side)
			z -= streetlight_spacing


func _streetlight(p: Vector3, toward_road: float) -> void:
	var pole := Color(0.3, 0.32, 0.38)
	var sl := Node3D.new()
	sl.position = p
	sl.rotation_degrees = Vector3(0, 0, _rng.randf_range(-2.5, 2.5))
	add_child(sl)
	C.solid(GB.cylinder(sl, 0.07, 0.11, 5.6, Vector3(0, 2.8, 0), pole), "Streetlight")
	C.solid(GB.box(sl, Vector3(1.6, 0.09, 0.09), Vector3(toward_road * 0.75, 5.55, 0), pole, Vector3(0, 0, toward_road * 6)), "Streetlight")
	C.solid(GB.box(sl, Vector3(0.6, 0.18, 0.32), Vector3(toward_road * 1.45, 5.45, 0), pole.darkened(0.3)), "Streetlight")
	GB.box(sl, Vector3(0.5, 0.05, 0.26), Vector3(toward_road * 1.45, 5.35, 0), Color(1.0, 0.75, 0.4), Vector3.ZERO, 2.5)
	var spot := SpotLight3D.new()
	spot.position = Vector3(toward_road * 1.45, 5.25, 0)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	spot.light_color = Color(1.0, 0.72, 0.42)
	spot.light_energy = streetlight_energy
	spot.spot_range = streetlight_range
	spot.spot_angle = 55.0
	spot.spot_angle_attenuation = 1.6
	spot.spot_attenuation = 0.8
	spot.shadow_enabled = false
	sl.add_child(spot)
	streetlight_heads.append(p + Vector3(toward_road * 1.45, 5.2, 0))
	_firefly_points.append(p + Vector3(toward_road * 1.2, 2.0, 0))


func _fences() -> void:
	for side_name: String in ["left", "right"]:
		var x := LEFT_FENCE_X if side_name == "left" else RIGHT_FENCE_X
		var z := Z_MIN
		var run_start := z
		while z < Z_MAX:
			var gap: bool = (side_name == "left" and z > -6.0 and z < 6.0)
			for g in _gaps[side_name]:
				if z >= (g as Vector2).x and z <= (g as Vector2).y:
					gap = true
					break
			if gap:
				if z - run_start > 0.5:
					_rails(x, run_start, z)
				run_start = z + 0.25
			else:
				var lean := deg_to_rad(_rng.randf_range(-4.0, 4.0))
				_picket_xforms.append(Transform3D(Basis(Vector3.BACK, lean), Vector3(x, 0.45, z)))
			z += 0.24
		if Z_MAX - run_start > 0.5:
			_rails(x, run_start, Z_MAX)
	var picket := BoxMesh.new()
	picket.size = Vector3(0.05, 0.9, 0.1)
	_multimesh(picket, _picket_xforms, GB.mat(Color(0.95, 0.92, 0.85)))
	var rail := BoxMesh.new()
	rail.size = Vector3(0.05, 0.07, 1.0)
	_multimesh(rail, _rail_xforms, GB.mat(Color(0.88, 0.85, 0.78)))


func _rails(x: float, z0: float, z1: float) -> void:
	C.box(self, Vector3(0.12, 0.9, z1 - z0), Vector3(x - 0.03, 0.45, (z0 + z1) * 0.5), "Fence")
	for y in [0.3, 0.7]:
		_rail_xforms.append(Transform3D(Basis().scaled(Vector3(1, 1, z1 - z0)), Vector3(x - 0.06, y, (z0 + z1) * 0.5)))


func _hedges() -> void:
	# Blobby hedges and shrubs just inside the front fences.
	for side: float in [-1.0, 1.0]:
		var x := (LEFT_FENCE_X - 0.7) if side < 0.0 else (RIGHT_FENCE_X + 0.7)
		var z := Z_MIN
		while z < Z_MAX:
			var run := _rng.randf_range(2.0, 6.0)
			if _rng.randf() < 0.45 and is_clear(Vector3(x + side * 1.2, 0, z), 0.0):
				var k := 0.0
				while k < run:
					var r := _rng.randf_range(0.45, 0.75)
					var key := "a" if _rng.randf() < 0.6 else "b"
					_hedge_xforms[key].append(Transform3D(Basis().scaled(Vector3(r, r * 0.85, r)), Vector3(x + _rng.randf_range(-0.2, 0.2), r * 0.6, z + k)))
					k += r * 1.1
			z += run + _rng.randf_range(1.0, 5.0)
	var hedge_shapes := []
	for key in _hedge_xforms:
		for xf: Transform3D in _hedge_xforms[key]:
			hedge_shapes.append([xf.origin, xf.basis.get_scale().x * 0.92])
	C.spheres(self, hedge_shapes, "Hedge")
	var blob := SphereMesh.new()
	blob.radius = 1.0
	blob.height = 2.0
	blob.radial_segments = 12
	blob.rings = 6
	_multimesh(blob, _hedge_xforms["a"], foliage(Color(0.22, 0.52, 0.2)))
	_multimesh(blob, _hedge_xforms["b"], foliage(Color(0.3, 0.6, 0.28)))


func _multimesh(mesh: Mesh, xforms: Array, mat: Material) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


## Toon foliage with a lighter, warmer underside (bounce light) so canopies don't read as flat discs.
static func foliage(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("emission_energy", 0.06)
	m.set_shader_parameter("rim_strength", 0.38)
	m.set_shader_parameter("rim_color", Color(0.85, 0.95, 0.6))
	m.set_shader_parameter("underside_light", 0.55)
	m.set_shader_parameter("underside_color", color.lerp(Color(0.85, 0.9, 0.45), 0.55))
	m.set_shader_parameter("patch_strength", 0.35)
	m.set_shader_parameter("patch_color", color.lightened(0.25))
	m.set_shader_parameter("patch_scale", 0.6)
	return m


# --- distance ----------------------------------------------------------------------------------------

func _distance() -> void:
	# Rolling hills ring: big squashed blobs that the fog turns into layered silhouettes.
	for i in hill_count:
		var ang := TAU * float(i) / float(hill_count) + _rng.randf_range(-0.1, 0.1)
		var dist := _rng.randf_range(300.0, 430.0)
		var p := Vector3(sin(ang) * dist, -6.0, cos(ang) * dist - 60.0)
		var s := Vector3(_rng.randf_range(70, 130), _rng.randf_range(22, 48), _rng.randf_range(50, 80))
		var c := Color(0.2, 0.17, 0.33).lerp(Color(0.3, 0.2, 0.38), _rng.randf())
		var mi := GB.sphere(self, 1.0, p, c, 0.0, s)
		mi.rotation_degrees = Vector3(0, rad_to_deg(ang), 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Far-off town skyline down the end of the street, with a scatter of lit windows.
	for i in skyline_buildings:
		var x := _rng.randf_range(-260.0, 260.0)
		var z := -560.0 - _rng.randf_range(0.0, 60.0)
		var h := _rng.randf_range(8.0, 34.0) * (1.6 if absf(x) < 60.0 else 1.0)
		var bw := _rng.randf_range(10.0, 26.0)
		var b := GB.box(self, Vector3(bw, h, 12.0), Vector3(x, h * 0.5 - 2.0, z), Color(0.16, 0.12, 0.26))
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for k in _rng.randi_range(1, 4):
			GB.box(self, Vector3(1.4, 1.0, 0.2), Vector3(x + _rng.randf_range(-bw * 0.4, bw * 0.4), _rng.randf_range(2.0, h - 2.0), z + 6.1), WARM, Vector3.ZERO, 2.0)
	# Gentle mounds in the back paddocks (low, visual only).
	for i in mound_count:
		var p := Vector3(_rng.randf_range(48.0, 120.0) * (1.0 if i % 2 == 0 else -1.0), -0.2, _rng.randf_range(-200.0, 50.0))
		var r := _rng.randf_range(10.0, 22.0)
		var mi := GB.sphere(self, 1.0, p, Color(0.22, 0.42, 0.16), 0.0, Vector3(r, _rng.randf_range(0.8, 1.8), r * 0.8))
		mi.material_override = GB.patchy(Color(0.22, 0.42, 0.16), Color(0.5, 0.48, 0.18), 0.6, 0.06)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _fireflies() -> void:
	_rng.seed = 99
	var spots := _firefly_points.duplicate()
	for i in mini(firefly_spots, spots.size()):
		var p: Vector3 = spots[(i * 7) % spots.size()]
		var f := CPUParticles3D.new()
		f.amount = 16
		f.lifetime = 4.0
		f.preprocess = 4.0
		f.position = p
		f.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		f.emission_sphere_radius = 2.2
		f.direction = Vector3(0, 1, 0)
		f.spread = 180.0
		f.gravity = Vector3.ZERO
		f.initial_velocity_min = 0.1
		f.initial_velocity_max = 0.35
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.vertex_color_use_as_albedo = true
		var sm := SphereMesh.new()
		sm.radius = firefly_size
		sm.height = firefly_size * 2.0
		sm.radial_segments = 6
		sm.rings = 3
		sm.material = m
		f.mesh = sm
		var g := Gradient.new()
		g.set_color(0, Color(0.8, 1.0, 0.3, 0.0))
		g.set_color(1, Color(0.8, 1.0, 0.3, 0.0))
		g.add_point(0.3, Color(0.8 * firefly_glow, firefly_glow, 0.25 * firefly_glow, 1.0))
		g.add_point(0.5, Color(0.8, 1.0, 0.3, 0.1))
		g.add_point(0.7, Color(0.8 * firefly_glow, firefly_glow, 0.25 * firefly_glow, 1.0))
		f.color_ramp = g
		add_child(f)
