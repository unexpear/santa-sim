extends Node3D
## Hello Neighbor style brick chimney at real house scale (visual only; the house adds the
## collision walls). About 0.64 m square, with a stack that stays straight through the roof and
## then leans and bellies very slightly above the roofline. Bricks are drawn by
## chimney_brick.gdshader on UVs measured in metres, so every brick is the same real size on every
## face (no stretching). Crown: two corbelled brick courses stepping out, then a concrete cap with
## a weathering slope, sooty round the open flue hole. The flue is open and dark all the way down.
## No hatch or lid: the top is just the crown and cap round the open flue hole. Faint warm glow
## from the flue when the fire is lit; frost and icicles when it's iced.

const GB := preload("res://scripts/greybox.gd")
const BRICK_SHADER := preload("res://shaders/chimney_brick.gdshader")
const FLUE_SHADER := preload("res://shaders/flue_brick.gdshader")

const BRICK_L := 0.22  ## brick length (m)
const BRICK_H := 0.068  ## brick height (m)
const JOINT := 0.013  ## mortar joint (m)
const COURSE := BRICK_H + JOINT
const CAP_T := 0.07  ## concrete cap thickness at the outer edge
const CAP_WASH := 0.018  ## cap top falls this much from the hole to the edge
const STEP := 0.035  ## each corbel course steps out this much per side

var height := 1.0  ## local y of the cap top at the flue hole
var outer := 0.64
var flue := 0.34
var crook := Vector3.ZERO  ## sideways offset of the crown (the stack's lean)
var mouth_y := 0.0  ## local y of the cap top at the open flue hole
var stack_top := 0.8  ## local y of the top of the plain stack (corbels start here)
var straight := 0.0  ## the stack is vertical up to here (the roofline), then leans and bellies
var bulge := 0.03
var drift := 0.05
var glow: OmniLight3D
var flue_mat: ShaderMaterial
var _brick_mat: ShaderMaterial
var _cap_mat: ShaderMaterial
var _frost_nodes: Array = []
var _rng := RandomNumberGenerator.new()

const SOOT := Color(0.05, 0.04, 0.04)
const BRASS := Color(0.88, 0.64, 0.26)


## p_height: cap top above the base (rounded to whole brick courses); roofline: local height up
## to which the stack stays vertical (where the flashing is); p_bulge: belly as a fraction of the
## width at mid-height above the roof; p_drift: sideways lean of the crown (m). pot is ignored
## (a real-size flue has no room for a separate pot).
func build(p_height: float, p_outer: float, p_flue: float, seed_v: int, roofline := 0.0, p_bulge := 0.03, p_drift := 0.05, _pot := false) -> void:
	outer = p_outer
	flue = p_flue
	bulge = p_bulge
	drift = p_drift
	straight = roofline
	_rng.seed = seed_v
	stack_top = maxf(straight + 4.0 * COURSE, roundf((p_height - CAP_T - 2.0 * COURSE) / COURSE) * COURSE)
	height = stack_top + 2.0 * COURSE + CAP_T
	crook = _disp(Vector3(0, stack_top, 0))
	crook.y = 0.0
	mouth_y = height
	_brick_mat = ShaderMaterial.new()
	_brick_mat.shader = BRICK_SHADER
	_brick_mat.set_shader_parameter("brick_l", BRICK_L)
	_brick_mat.set_shader_parameter("brick_h", BRICK_H)
	_brick_mat.set_shader_parameter("joint", JOINT)
	_brick_mat.set_shader_parameter("soot_y0", stack_top - 0.45)
	_brick_mat.set_shader_parameter("soot_y1", stack_top + 2.0 * COURSE)
	_cap_mat = ShaderMaterial.new()
	_cap_mat.shader = BRICK_SHADER
	_cap_mat.set_shader_parameter("cap_mode", 1)
	_cap_mat.set_shader_parameter("cap_center", Vector2(crook.x, crook.z))
	_cap_mat.set_shader_parameter("cap_hole", flue * 0.5)
	flue_mat = ShaderMaterial.new()
	flue_mat.shader = FLUE_SHADER
	var bricks := SurfaceTool.new()
	bricks.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cap := SurfaceTool.new()
	cap.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fl := SurfaceTool.new()
	fl.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := outer * 0.5
	var f := flue * 0.5
	# the stack: four faces, displaced (lean + belly above the roofline)
	var nv := maxi(6, int(ceil(stack_top / 0.12)))
	_box_sides(bricks, h, 0.0, stack_top, nv, 4, false)
	# corbelled crown: two brick courses stepping out, with their undersides
	var c1 := h + STEP
	var c2 := h + 2.0 * STEP
	var hc := h + 3.0 * STEP
	_box_sides(bricks, c1, stack_top, stack_top + COURSE, 1, 1, false)
	_annulus(bricks, h, c1, stack_top, false)
	_box_sides(bricks, c2, stack_top + COURSE, stack_top + 2.0 * COURSE, 1, 1, false)
	_annulus(bricks, c1, c2, stack_top + COURSE, false)
	# concrete cap: underside, outer edge, and a top that falls from the hole to the edge
	var cy0 := stack_top + 2.0 * COURSE
	_box_sides(cap, hc, cy0, height - CAP_WASH, 1, 1, false)
	_annulus(cap, c2, hc, cy0, false)
	_annulus_sloped(cap, f, hc, height, height - CAP_WASH)
	# the open flue: sooty brick inside, all the way from the base up to the cap
	_box_sides(fl, f, 0.0, height, nv + 3, 1, true)
	for pair in [[bricks, _brick_mat, "Stack"], [cap, _cap_mat, "Cap"], [fl, flue_mat, "Flue"]]:
		var stv: SurfaceTool = pair[0]
		var mi := MeshInstance3D.new()
		mi.name = pair[2]
		mi.mesh = stv.commit()
		mi.material_override = pair[1]
		add_child(mi)
	var wy := lerpf(straight, stack_top, 0.42)
	var wp := _disp(Vector3(0, wy, h))
	_wreath_on_face(wp + Vector3(0, 0, 0.02))
	_frost(hc)
	glow = OmniLight3D.new()
	glow.light_color = Color(1.0, 0.6, 0.3)
	glow.light_energy = 0.0
	glow.omni_range = 0.9
	glow.omni_attenuation = 1.4
	glow.position = crook + Vector3(0, height - 0.22, 0)
	add_child(glow)
	set_state(false, false)


## Lean + belly: vertical up to the roofline, then the crown drifts sideways (quadratic) and the
## middle bellies out a little; back to true width under the crown.
func _disp(p: Vector3) -> Vector3:
	var t := clampf((p.y - straight) / maxf(0.01, stack_top - straight), 0.0, 1.0)
	var s := 1.0 + bulge * sin(PI * t)
	return Vector3(p.x * s + drift * t * t, p.y, p.z * s + drift * 0.3 * t * t)


## Stack centre (local) at local height y (follows the lean).
func axis_at(y: float) -> Vector3:
	return _disp(Vector3(0, y, 0))


## Half-width of the open flue at local height y (with the belly).
func flue_half_at(y: float) -> float:
	return _disp(Vector3(flue * 0.5, y, 0)).x - _disp(Vector3(0, y, 0)).x


## Two triangles from four corners, wound so the face looks along n (Godot: clockwise = front).
func _quad(st: SurfaceTool, p: Array, uv: Array, n: Vector3) -> void:
	var idx := [[0, 1, 2], [0, 2, 3]]
	for tri in idx:
		var a: Vector3 = p[tri[0]]
		var b: Vector3 = p[tri[1]]
		var c: Vector3 = p[tri[2]]
		var order: Array = tri
		if (b - a).cross(c - a).dot(n) > 0.0:
			order = [tri[0], tri[2], tri[1]]
		for k in order:
			st.set_normal(n)
			st.set_uv(uv[k])
			st.add_vertex(p[k])


## Four vertical faces of a square of half-size hs from y0 to y1, as a grid (nv rows, nu columns
## per face), displaced. UV in metres: x runs round the perimeter, y is height. inward: faces
## look into the square (the flue).
func _box_sides(st: SurfaceTool, hs: float, y0: float, y1: float, nv: int, nu: int, inward: bool) -> void:
	var corners := [Vector2(-hs, hs), Vector2(hs, hs), Vector2(hs, -hs), Vector2(-hs, -hs), Vector2(-hs, hs)]
	var u0 := 0.0
	for fi in 4:
		var a: Vector2 = corners[fi]
		var b: Vector2 = corners[fi + 1]
		var side := (b - a).length()
		for i in nu:
			for j in nv:
				var ka := float(i) / nu
				var kb := float(i + 1) / nu
				var ya := lerpf(y0, y1, float(j) / nv)
				var yb := lerpf(y0, y1, float(j + 1) / nv)
				var pa := a.lerp(b, ka)
				var pb := a.lerp(b, kb)
				var q := [_disp(Vector3(pa.x, ya, pa.y)), _disp(Vector3(pb.x, ya, pb.y)), _disp(Vector3(pb.x, yb, pb.y)), _disp(Vector3(pa.x, yb, pa.y))]
				var n := ((q[1] as Vector3) - (q[0] as Vector3)).cross((q[3] as Vector3) - (q[0] as Vector3)).normalized()
				if inward:
					n = -n
				var uvs := [Vector2(u0 + side * ka, ya), Vector2(u0 + side * kb, ya), Vector2(u0 + side * kb, yb), Vector2(u0 + side * ka, yb)]
				_quad(st, q, uvs, n)
		u0 += side


## Flat square ring between half-sizes a (inner) and b (outer) at height y, facing down (an
## overhang's underside) or up.
func _annulus(st: SurfaceTool, a: float, b: float, y: float, up: bool) -> void:
	var n := Vector3.UP if up else Vector3.DOWN
	for k in 4:
		var r := Basis(Vector3.UP, k * PI * 0.5)
		var pts := [r * Vector3(-b, y, b), r * Vector3(b, y, b), r * Vector3(a, y, a), r * Vector3(-a, y, a)]
		var q: Array = []
		var uvs: Array = []
		for p: Vector3 in pts:
			var d := _disp(p)
			q.append(d)
			uvs.append(Vector2(p.x, p.z))
		_quad(st, q, uvs, n)


## The cap's top: a square ring from the hole (half-size a, height ya) falling to the edge (b, yb).
func _annulus_sloped(st: SurfaceTool, a: float, b: float, ya: float, yb: float) -> void:
	for k in 4:
		var r := Basis(Vector3.UP, k * PI * 0.5)
		var pts := [r * Vector3(-b, yb, b), r * Vector3(b, yb, b), r * Vector3(a, ya, a), r * Vector3(-a, ya, a)]
		var q: Array = []
		var uvs: Array = []
		for p: Vector3 in pts:
			q.append(_disp(p))
			uvs.append(Vector2(p.x, p.z))
		var n := ((q[1] as Vector3) - (q[0] as Vector3)).cross((q[3] as Vector3) - (q[0] as Vector3)).normalized()
		if n.y < 0.0:
			n = -n
		_quad(st, q, uvs, n)


func _wreath_on_face(at: Vector3) -> void:
	var wr := GB.torus(self, 0.05, 0.095, at, Color(0.12, 0.42, 0.18), Vector3(90, 0, 0))
	wr.scale = Vector3(1, 1.4, 1)
	for k in 8:
		var a := k * TAU / 8.0
		GB.sphere(self, 0.02, at + Vector3(cos(a) * 0.072, sin(a) * 0.072, 0.012), Color(0.1, 0.36, 0.14), 0.0, Vector3(1.3, 1.3, 0.6))
	var red := Color(0.92, 0.08, 0.1)
	GB.sphere(self, 0.028, at + Vector3(-0.03, -0.078, 0.022), red, 0.1, Vector3(1.3, 0.8, 0.6))
	GB.sphere(self, 0.028, at + Vector3(0.03, -0.078, 0.022), red, 0.1, Vector3(1.3, 0.8, 0.6))
	GB.sphere(self, 0.016, at + Vector3(0, -0.078, 0.028), red.darkened(0.15))


## Icicles hanging from the cap's edge (shown when the fire is iced).
func _frost(hc: float) -> void:
	var ice := StandardMaterial3D.new()
	ice.albedo_color = Color(0.85, 0.95, 1.0, 0.85)
	ice.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ice.emission_enabled = true
	ice.emission = Color(0.5, 0.75, 1.0)
	ice.emission_energy_multiplier = 0.4
	ice.roughness = 0.2
	var n := Node3D.new()
	n.name = "Frost"
	add_child(n)
	var y := stack_top + 2.0 * COURSE
	for i in 12:
		var face := i % 4
		var along := _rng.randf_range(-0.8, 0.8) * hc
		var p := Vector3(along, y, hc - 0.012)
		var cm := CylinderMesh.new()
		cm.top_radius = _rng.randf_range(0.008, 0.014)
		cm.bottom_radius = 0.0
		cm.height = _rng.randf_range(0.04, 0.11)
		cm.radial_segments = 6
		var m := GB.add_mesh(n, cm, p.rotated(Vector3.UP, face * PI * 0.5) + crook - Vector3(0, cm.height * 0.5, 0), Vector3.ZERO, ice)
		m.rotation.y = face * PI * 0.5
	_frost_nodes.append(n)


func set_state(lit: bool, frozen: bool) -> void:
	for n in _frost_nodes:
		(n as Node3D).visible = frozen
	for m in [_brick_mat, _cap_mat]:
		if m:
			(m as ShaderMaterial).set_shader_parameter("frost", 0.6 if frozen else 0.0)
	if glow:
		glow.visible = lit or frozen
		glow.light_color = Color(0.55, 0.8, 1.0) if frozen else Color(1.0, 0.58, 0.28)
		glow.light_energy = 0.4 if frozen else 0.8


func _bm(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static var _web_tex: ImageTexture


## A dangling cobweb: a translucent quad with a drawn web (radial threads + sagging rings).
static func cobweb(parent: Node3D, pos: Vector3, size: float, yaw_deg: float, layers := 1) -> MeshInstance3D:
	if _web_tex == null:
		var n := 128
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var c := Vector2(6, 6)  # anchored in the top corner
		var rays := 7
		for r in rays:
			var a := lerpf(0.05, PI * 0.5 - 0.05, float(r) / (rays - 1))
			for k in 170:
				var p := c + Vector2(cos(a), sin(a)) * k * 0.72
				if p.x < n and p.y < n:
					img.set_pixelv(Vector2i(p), Color(0.92, 0.92, 0.95, 0.75))
		for ring in range(1, 9):
			var rad := ring * 13.0
			for k in 200:
				var a := lerpf(0.05, PI * 0.5 - 0.05, k / 199.0)
				var sag := sin(fmod(a, PI * 0.5 / (rays - 1)) / (PI * 0.5 / (rays - 1)) * PI) * ring * 0.9
				var p := c + Vector2(cos(a), sin(a)) * (rad - sag)
				if p.x >= 0 and p.y >= 0 and p.x < n and p.y < n:
					img.set_pixelv(Vector2i(p), Color(0.9, 0.9, 0.93, 0.55))
		# a few loose strands hanging down
		for s in 3:
			var x := 30 + s * 27
			for y in range(int(x * 0.4), n):
				img.set_pixel(x + int(sin(y * 0.1 + s) * 2.0), y, Color(0.9, 0.9, 0.93, 0.35))
		_web_tex = ImageTexture.create_from_image(img)
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _web_tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.albedo_color = Color(0.85, 0.85, 0.9)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = Vector3(0, yaw_deg, 0)
	mi.layers = layers
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
