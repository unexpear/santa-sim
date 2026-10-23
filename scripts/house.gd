extends Node3D
## A Santa-designed house (alt-history: every roof is built for sleigh landings), drawn in a
## chunky, crooked Hello Neighbor style.
## roof_type 0 = flat landing pad (easy), 1 = steep gable with a narrow ridge pad (slide risk),
## 2 = rain-slick flat roof (low grip, Aussie summer storm).
## Light colours: green = safe pad, blue = slick, red = steep / danger edge, gold = launch pad.
## Green/blue side strings "chase" from the +Z end toward -Z: the intended approach direction.
##
## IMPORTANT: collision boxes (walls, roof slabs, slopes, ridge pad) are plain axis-aligned boxes
## exactly as in the greybox. All the wonkiness (bulging/bent walls, leaning chimneys, crooked
## windows) is visual only, so landing behaviour is unchanged.

const GB := preload("res://scripts/greybox.gd")
const C := preload("res://scripts/colliders.gd")
const LightString := preload("res://scripts/light_string.gd")
const Interior := preload("res://scripts/interior.gd")
const FX := preload("res://scripts/fx.gd")
const Furn := preload("res://scripts/furniture.gd")
const Decor := preload("res://scripts/decor.gd")
const ChimneyModel := preload("res://scripts/chimney_model.gd")
const Carve := preload("res://scripts/carve.gd")
## --break-chimney (checks only): put the chimney back how it was broken (world layer only, no
## flue / fireplace-shaft collision) to prove --solidcheck catches it.
static var break_chimney := OS.get_cmdline_user_args().has("--break-chimney")
const CHIMNEY_LAYERS := 1 | 4  ## the sleigh world AND the elf (interior) layer

const GREEN := Color(0.05, 1.0, 0.15)
const BLUE := Color(0.08, 0.4, 1.0)
const RED := Color(1.0, 0.06, 0.03)
const WARM := Color(1.0, 0.68, 0.28)

@export_enum("Flat pad", "Steep gable", "Rain-slick") var roof_type := 0
@export var width := 12.0
@export var depth := 10.0
@export var wall_height := 4.0
@export var wall_color := Color(0.95, 0.5, 0.18)
@export var trim_color := Color(0.5, 0.25, 0.7)
@export var roof_color := Color(0.3, 0.22, 0.4)

@export_group("Roof tuning")
@export var pad_friction := 1.0
@export var steep_slope_friction := 0.1
@export var slick_friction := 0.01
@export var steep_angle_deg := 30.0
@export var ridge_pad_width := 3.0

@export_group("Style (visual only)")
@export var wall_bend := 0.3  ## Sideways belly of the walls at mid-height (m).
@export var wall_bulge := 0.035  ## Fractional bulge of the walls at mid-height.
@export var chimney_lean := 0.045  ## Sideways lean of the chimney crown above the roofline (m).
@export var chimney_bulge := 0.03  ## Fractional belly of the chimney stack above the roof.
@export var window_crookedness_deg := 7.0
@export var light_energy := 2.4
@export_enum("Front (+Z)", "Right (+X)", "Left (-X)") var door_side := 0  ## Which wall faces the street (door goes there).
@export var door_offset := 0.0  ## Slide the door along its wall (m), e.g. to clear an annex.
@export var window_light_energy := 0.45  ## Small warm light thrown out of each window.
@export var landing_bulb_distance_scale := 3.2  ## Landing strings grow more with distance so they read from the air.
@export var porch_light_energy := 0.6

@export_group("Chimney + interior")
@export var interior_enabled := true  ## Build the furnished interior inside the shell (seamless).
@export var fireplace_lit := false  ## A real fire burns in the fireplace (Fireplace Icer needed to get in).
@export var flue_size := 0.25  ## Inner size of the clay flue liner (m): 250 x 250 suits a 900 x 750 open fire.
@export var chimney_outer := 0.64  ## Outer size of the brick stack (m); walls are (outer - flue) / 2 thick.
@export var chimney_above_roof := 1.0  ## Stack height above the roofline (m) to the cap top (whole brick courses).
@export var chimney_pot := false  ## (unused: a real-size flue has no room for a separate pot)
@export var chimney_smoke_amount := 16
@export var fire_light_energy := 1.6
@export var glass_tint := Color(1.0, 0.85, 0.6, 0.12)

## Height (local) of the main landing surface, filled in by _ready. Used by the self-test.
var landing_top := 0.0
var slope_center_x := 0.0
var _rng := RandomNumberGenerator.new()
var _phase := 0.0
var _door_local := Vector3.ZERO
var _door_normal_local := Vector3.BACK
var interior: Node3D
var chimney_base := Vector3.ZERO  ## local, centre of the chimney footprint on the roof
var chimney_height := 3.0
var fire_lit := false
var fire_frozen := false
var _wall_mi: MeshInstance3D
var _wall_holes: Array = []  # [min, max] in wall-mesh local space
var _fire_nodes: Array = []
var _ice_nodes: Array = []
var _chimney_smoke: GPUParticles3D
var _fire_light: OmniLight3D
var _shaft_glow: MeshInstance3D
var chimney_model: Node3D  ## the brick stack (ChimneyModel): glow, frost
var chimney_below := 0.0  ## height of the roofline above the stack base (m); the stack is straight up to here
var damper_hinge: Node3D  ## damper flap at the bottom of the flue (the elf pushes through it)
var _shaft_mat: ShaderMaterial
var _shaft_light: OmniLight3D
var _t := 0.0


## World position at the centre of the chimney opening (top of the flue).
func get_chimney_top_world() -> Vector3:
	return to_global(chimney_base + Vector3(0, chimney_height + 0.3, 0))


func get_chimney_base_world() -> Vector3:
	return to_global(chimney_base)


## World position on the ground just outside the front door, and the direction the door faces.
func get_door_world() -> Vector3:
	return to_global(_door_local)


func get_door_normal_world() -> Vector3:
	return (global_basis * _door_normal_local).normalized()


func _ready() -> void:
	_rng.seed = 1234 + roof_type
	_phase = _rng.randf_range(0.0, TAU)
	_plan_chimney()
	if interior_enabled:
		interior = Interior.new()
		interior.name = "Interior"
		add_child(interior)
		interior.call("build", self, roof_type, width, depth, wall_height, chimney_base)
		# put the stack straight over the smoke chamber, so the flue runs straight up inside the
		# chimney breast (no offset through open room air)
		var fsp: Vector3 = interior.get("fireplace_spawn")
		_plan_chimney(float(interior.get("fireplace_x")), fsp.z + 0.05 - 0.0625)
	_build_walls()
	match roof_type:
		0:
			_build_flat()
		1:
			_build_steep()
		_:
			_build_slick()
	_build_flue_shaft()
	_elf_chimney_collision()
	if interior:
		_build_fire()
		set_fire(fireplace_lit)
		Decor.yard(self, roof_type, width, depth)  # visual only, own RNG


## Where the chimney goes (same spots as before), decided up front so the interior can put the
## fireplace right under it.
func _plan_chimney(px := NAN, pz := NAN) -> void:
	_plan_chimney_at()
	if is_nan(px):
		return
	chimney_base.x = px
	chimney_base.z = pz
	if roof_type == 1:
		_plan_chimney_at(px - _steep_sc())


func _steep_sc() -> float:
	return ridge_pad_width * 0.5 + (width - ridge_pad_width) * 0.25


func _plan_chimney_at(steep_dx := 0.6) -> void:
	match roof_type:
		0:
			chimney_base = Vector3(width * 0.5 - 1.1, wall_height + 0.3, -depth * 0.5 + 1.1)
			chimney_below = 0.0
			chimney_height = chimney_above_roof
		1:
			var a := deg_to_rad(steep_angle_deg)
			var slope_w := (width - ridge_pad_width) * 0.5
			var rise := slope_w * tan(a)
			var sc := ridge_pad_width * 0.5 + slope_w * 0.5
			var keep := chimney_base
			chimney_base = Vector3(sc + steep_dx, wall_height + rise * 0.3, -depth * 0.32)
			if steep_dx != 0.6:
				chimney_base = Vector3(keep.x, chimney_base.y, keep.z)
			# roof surface at the stack's centre; the stack starts just under its downhill face and
			# stays straight up to its uphill face (where the flashing is)
			var roof_c := wall_height + rise * 0.5 - steep_dx * tan(a) + 0.15 / cos(a)
			var half := chimney_outer * 0.5 * tan(a)
			chimney_base.y = roof_c - half - 0.08
			chimney_below = roof_c + half - chimney_base.y
			chimney_height = roof_c - chimney_base.y + chimney_above_roof
		_:
			chimney_base = Vector3(-width * 0.5 + 1.1, wall_height + 0.3, -depth * 0.5 + 1.1)
			chimney_below = 0.0
			chimney_height = chimney_above_roof


func _static_box(size: Vector3, xform: Transform3D, color: Color, friction: float, group := "", surface_name := "", material: Material = null, visual := true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.transform = xform
	var pm := PhysicsMaterial.new()
	pm.friction = friction
	body.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	if visual:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = material if material != null else GB.mat(color)
		body.add_child(mi)
	if group != "":
		body.add_to_group(group)
	body.set_meta("surface_name", surface_name if surface_name != "" else "House")
	# how springy the roof is for a sleigh bump (sleigh.gd): corrugated iron rings and bounces,
	# terracotta tiles and the membrane pad soak it up
	var bounce := 0.5
	if surface_name.contains("slick"):
		bounce = 1.0  # wet corrugated iron
	elif surface_name.contains("Steep") or surface_name.contains("Ridge"):
		bounce = 0.3  # tiles
	body.set_meta("roof_bounce", bounce)
	add_child(body)
	return body


func _lights(points: Array, color: Color, chase := false) -> void:
	var ls := LightString.new()
	ls.max_distance_scale = landing_bulb_distance_scale
	add_child(ls)
	var e := light_energy * (1.5 if color == BLUE else 1.0)
	ls.setup(PackedVector3Array(points), color, chase, e)


## Outline a rectangle at height y. The two long sides chase toward -Z (approach direction).
func _outline_rect(w: float, d: float, y: float, color: Color) -> void:
	var hw := w * 0.5
	var hd := d * 0.5
	_lights([Vector3(-hw, y, hd), Vector3(-hw, y, -hd)], color, true)
	_lights([Vector3(hw, y, hd), Vector3(hw, y, -hd)], color, true)
	_lights([Vector3(-hw, y, hd), Vector3(hw, y, hd)], color)
	_lights([Vector3(-hw, y, -hd), Vector3(hw, y, -hd)], color)


## Same maths as the toon shader's warp, so windows/doors sit on the bent wall surface.
func _on_wall(p: Vector3) -> Vector3:
	var t := clampf(p.y / wall_height, 0.0, 1.0)
	var s := sin(t * PI)
	return Vector3(p.x * (1.0 + wall_bulge * s) + wall_bend * s, p.y,
			p.z * (1.0 + wall_bulge * s) + wall_bend * 0.5 * sin(t * TAU + _phase))


func _build_walls() -> void:
	# Collision: the same plain box as before (wall hits = crash). Visual: a subdivided, bent box.
	_static_box(Vector3(width, wall_height, depth), Transform3D(Basis(), Vector3(0, wall_height * 0.5, 0)), wall_color, 0.6, "house", "Wall", null, false)
	var wm := BoxMesh.new()
	wm.size = Vector3(width, wall_height, depth)
	wm.subdivide_width = 6
	wm.subdivide_height = 8
	wm.subdivide_depth = 6
	GB.add_mesh(self, wm, Vector3(0, wall_height * 0.5, 0), Vector3.ZERO, GB.warped(wall_color, wall_height, wall_bend, wall_bulge, _phase))
	# Chunky skirting along the base
	GB.box(self, Vector3(width + 0.3, 0.35, depth + 0.3), Vector3(0, 0.17, 0), trim_color.darkened(0.3))

	_wall_mi = get_child(get_child_count() - 2) as MeshInstance3D  # the bent wall mesh (added before the skirting)
	if interior:
		for w in interior.call("get_windows"):
			_window_from(w)
	else:
		var rows := 2 if wall_height > 4.8 else 1
		for row in rows:
			var y := 1.7 + row * 2.2
			for x in [-width * 0.3, width * 0.3]:
				_window_from({"side": "+z", "along": x, "y": y, "w": 1.3, "h": 1.1})
	# the flue drops through the top of the shell
	# (first in the list: the shader takes 16 holes, and a house with many windows used to drop it)
	_wall_holes.push_front([Vector3(chimney_base.x - flue_size * 0.5, -20.0, chimney_base.z - flue_size * 0.5),
			Vector3(chimney_base.x + flue_size * 0.5, 20.0, chimney_base.z + flue_size * 0.5)])
	_apply_wall_holes()
	# Front door (on the street-facing wall) with a crooked little porch roof and a warm porch lamp.
	var dl := Vector3(door_offset, 1.1, depth * 0.5)
	var yaw := 0.0
	_door_normal_local = Vector3.BACK
	if door_side == 1:
		dl = Vector3(width * 0.5, 1.1, door_offset)
		yaw = 90.0
		_door_normal_local = Vector3.RIGHT
	elif door_side == 2:
		dl = Vector3(-width * 0.5, 1.1, door_offset)
		yaw = -90.0
		_door_normal_local = Vector3.LEFT
	var dn := Node3D.new()
	dn.name = "FrontDoor"
	dn.position = _on_wall(dl)
	dn.rotation_degrees = Vector3(0, yaw, 0)
	add_child(dn)
	_door_local = Vector3(dn.position.x, 0.0, dn.position.z) + _door_normal_local * 1.2
	GB.box(dn, Vector3(1.25, 2.3, 0.18), Vector3(0, 0, 0.06), trim_color, Vector3(0, 0, _rng.randf_range(-3, 3)))
	GB.box(dn, Vector3(1.0, 2.0, 0.2), Vector3(0, -0.05, 0.1), Color(0.45, 0.22, 0.1), Vector3(0, 0, _rng.randf_range(-3, 3)))
	GB.sphere(dn, 0.07, Vector3(0.3, -0.1, 0.22), Color(1.0, 0.8, 0.3), 1.0)
	C.solid(GB.box(dn, Vector3(2.2, 0.18, 1.2), Vector3(0, 1.45, 0.55), roof_color, Vector3(-12, 0, _rng.randf_range(-6, 6))), "Porch roof")
	C.solid(GB.box(dn, Vector3(2.0, 0.2, 1.0), Vector3(0, -1.0, 0.6), Color(0.5, 0.45, 0.42)), "Front step")
	GB.sphere(dn, 0.13, Vector3(0.9, 0.9, 0.3), WARM, 3.0)
	# Small, soft porch pool (the old 6 m porch omni right against the wall made a big orange blotch).
	var porch := GB.omni(dn, Vector3(0.9, 0.7, 0.8), WARM, porch_light_energy, 3.2)
	porch.omni_attenuation = 1.6


## A window opening: the shell is cut (shader hole), a crooked frame sits on the bent wall, a
## clear warm-tinted pane, and reveal boards line the gap back to the interior wall so you can see
## the lit room inside from the street.
func _window_from(w: Dictionary) -> void:
	var side := str(w.side)
	var along := float(w.along)
	var y := float(w.y)
	var ow := float(w.w)
	var oh := float(w.h)
	var raw := Vector3.ZERO
	var normal := Vector3.ZERO
	var yaw := 0.0
	match side:
		"+z":
			raw = Vector3(along, y, depth * 0.5)
			normal = Vector3(0, 0, 1)
		"-z":
			raw = Vector3(along, y, -depth * 0.5)
			normal = Vector3(0, 0, -1)
			yaw = 180.0
		"+x":
			raw = Vector3(width * 0.5, y, along)
			normal = Vector3(1, 0, 0)
			yaw = 90.0
		_:
			raw = Vector3(-width * 0.5, y, along)
			normal = Vector3(-1, 0, 0)
			yaw = -90.0
	var tangent := Vector3(absf(normal.z), 0, absf(normal.x))
	var half := tangent * ow * 0.5 + Vector3(0, oh * 0.5, 0)
	var thick := normal.abs() * 1.2
	var off := Vector3(0, wall_height * 0.5, 0)
	_add_wall_hole(raw - off - half - thick, raw - off + half + thick)
	var pos := _on_wall(raw)
	# depth from the bent shell surface back to the interior wall face
	var inner := (raw - normal * 0.35).dot(normal.abs())
	var reveal := maxf(0.15, absf(pos.dot(normal.abs()) - inner) + 0.06)
	var wn := Node3D.new()
	wn.position = pos
	wn.rotation_degrees = Vector3(0, yaw, 0)
	add_child(wn)
	var trim := trim_color
	for s2: float in [-1.0, 1.0]:
		GB.box(wn, Vector3(0.06, oh, reveal), Vector3(s2 * (ow * 0.5 + 0.02), 0, -reveal * 0.5), trim.darkened(0.15))
		GB.box(wn, Vector3(ow + 0.1, 0.06, reveal), Vector3(0, s2 * (oh * 0.5 + 0.02), -reveal * 0.5), trim.darkened(0.15))
	var glass := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(ow, oh)
	glass.mesh = q
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = glass_tint
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.material_override = gm
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass.position = Vector3(0, 0, -0.05)
	wn.add_child(glass)
	var fr := Node3D.new()
	fr.rotation_degrees = Vector3(0, 0, _rng.randf_range(-window_crookedness_deg, window_crookedness_deg) * 0.4)
	wn.add_child(fr)
	var bw := 0.22
	GB.box(fr, Vector3(ow + bw * 2.0 - 0.1, bw, 0.14), Vector3(0, oh * 0.5 + bw * 0.5 - 0.05, 0.02), trim)
	GB.box(fr, Vector3(ow + bw * 2.0 - 0.1, bw, 0.14), Vector3(0, -oh * 0.5 - bw * 0.5 + 0.05, 0.02), trim)
	GB.box(fr, Vector3(bw, oh + 0.1, 0.14), Vector3(ow * 0.5 + bw * 0.5 - 0.05, 0, 0.02), trim)
	GB.box(fr, Vector3(bw, oh + 0.1, 0.14), Vector3(-ow * 0.5 - bw * 0.5 + 0.05, 0, 0.02), trim)
	GB.box(fr, Vector3(0.06, oh, 0.08), Vector3(0, 0, 0.0), trim)
	GB.box(fr, Vector3(ow, 0.06, 0.08), Vector3(0, 0.1, 0.0), trim)
	GB.box(fr, Vector3(ow + 0.6, 0.16, 0.3), Vector3(0, -oh * 0.5 - 0.25, 0.1), trim.darkened(0.2))
	var sd := -1.0 if _rng.randf() < 0.5 else 1.0
	GB.box(fr, Vector3(0.5, oh + 0.3, 0.08), Vector3(sd * (ow * 0.5 + 0.5), -0.05, 0.04), trim.lightened(0.15), Vector3(0, 0, sd * _rng.randf_range(2, 9)))
	if window_light_energy > 0.0:
		var l := GB.omni(wn, Vector3(0, -0.2, 0.9), WARM, window_light_energy, 3.0)
		l.distance_fade_enabled = true
		l.distance_fade_begin = 55.0
		l.distance_fade_length = 10.0
		l.omni_attenuation = 1.5


func _add_wall_hole(mn: Vector3, mx: Vector3) -> void:
	_wall_holes.append([mn, mx])


func _apply_wall_holes() -> void:
	if _wall_mi == null:
		return
	var m := _wall_mi.material_override as ShaderMaterial
	var mins := PackedVector3Array()
	var maxs := PackedVector3Array()
	for h in _wall_holes.slice(0, 16):
		mins.append(h[0])
		maxs.append(h[1])
	m.set_shader_parameter("hole_count", mins.size())
	m.set_shader_parameter("hole_min", mins)
	m.set_shader_parameter("hole_max", maxs)


## Cut the flue out of a roof mesh (any transform under this house) with a shader hole.
func _cut_flue(mi: MeshInstance3D) -> void:
	if mi == null:
		return
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n != self:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var inv := xf.affine_inverse()
	var hs := flue_size * 0.5
	var mn := Vector3(INF, INF, INF)
	var mx := -mn
	for cx in [-hs, hs]:
		for cy in [-6.0, 6.0]:
			for cz in [-hs, hs]:
				var p := inv * (chimney_base + Vector3(cx, cy, cz))
				mn = mn.min(p)
				mx = mx.max(p)
	var m := (mi.material_override as ShaderMaterial).duplicate() as ShaderMaterial
	m.set_shader_parameter("hole_count", 1)
	m.set_shader_parameter("hole_min", PackedVector3Array([mn]))
	m.set_shader_parameter("hole_max", PackedVector3Array([mx]))
	mi.material_override = m


func _mesh_of(body: Node) -> MeshInstance3D:
	for c in body.get_children():
		if c is MeshInstance3D:
			return c
	return null


## Real-size brick chimney with an open flue. The look is ChimneyModel (bricks on metre UVs,
## corbelled crown, concrete cap, open sooty flue, no hatch). Collision matches it:
## four brick walls round the open flue in three lifts that follow the lean, plus the wider crown
## (layer 1, so flying into it fast is still a crash; the elf goes down the open middle).
## Lead flashing where it meets the roof.
func _chimney(base: Vector3, height: float, lean_dir: float) -> void:
	# The old chimney drew 9 numbers from _rng; draw the same ones so everything built after it
	# (annexes, fire, ...) is unchanged.
	_rng.randf_range(-1, 1)
	for k in 4:
		_rng.randf_range(-0.3, 0.3)
		_rng.randf_range(0.1, 0.18)
	var c := ChimneyModel.new()
	c.name = "Chimney"
	c.position = base
	add_child(c)
	c.build(height, chimney_outer, flue_size, 7700 + roof_type * 31, chimney_below + 0.1, chimney_bulge, -lean_dir * chimney_lean)
	chimney_model = c
	height = c.height
	var hf := flue_size * 0.5
	var stack_top: float = c.stack_top
	# The stack: four brick walls round the open flue, in lifts about 15 cm tall that follow the
	# mesh's lean and belly (ChimneyModel._disp), so the colliders sit on the bricks.
	var lifts := maxi(4, int(ceil(stack_top / 0.15)))
	var spans: Array = []  # [y0, y1, outer half or -1 (= follow the belly)]
	for i in lifts:
		spans.append([stack_top * i / lifts, stack_top * (i + 1) / lifts, -1.0])
	# the crown, exactly as modelled: two corbelled courses stepping out, then the concrete cap
	var co := ChimneyModel.COURSE
	var stp := ChimneyModel.STEP
	var ho0 := chimney_outer * 0.5
	spans.append([stack_top, stack_top + co, ho0 + stp])
	spans.append([stack_top + co, stack_top + 2.0 * co, ho0 + 2.0 * stp])
	spans.append([stack_top + 2.0 * co, height, ho0 + 3.0 * stp])
	for sp in spans:
		var y0: float = sp[0]
		var y1: float = sp[1]
		var mid := (y0 + y1) * 0.5
		var ax: Vector3 = c.axis_at(mid)
		var hi: float = c.flue_half_at(mid) if float(sp[2]) < 0.0 else hf
		var ho: float = c.flue_half_at(mid) * ho0 / hf if float(sp[2]) < 0.0 else float(sp[2])
		var t := ho - hi
		var at := base + Vector3(ax.x, mid, ax.z)
		var hh := y1 - y0
		for s2: float in [-1.0, 1.0]:
			for b in [_static_box(Vector3(ho * 2.0, hh, t), Transform3D(Basis(), at + Vector3(0, 0, s2 * (ho - t * 0.5))), Color(), 0.6, "house", "Chimney", null, false),
					_static_box(Vector3(t, hh, hi * 2.0), Transform3D(Basis(), at + Vector3(s2 * (ho - t * 0.5), 0, 0)), Color(), 0.6, "house", "Chimney", null, false)]:
				(b as StaticBody3D).collision_layer = 1 if break_chimney else CHIMNEY_LAYERS
				(b as StaticBody3D).add_to_group("chimney_collision")
	_flashing(base)
	# a thin wisp of haze hanging around the chimney top
	var wisp := FX.make("blob", 5, 6.0, 0.5, [Color(0.7, 0.62, 0.85, 0.0), Color(0.7, 0.62, 0.85, 0.08), Color(0.7, 0.62, 0.85, 0.0)],
			{"box": Vector3(0.25, 0.1, 0.25), "spread": 180.0, "vmin": 0.02, "vmax": 0.06, "lit": true})
	wisp.position = c.crook + Vector3(0, height + 0.35, 0)
	c.add_child(wisp)
	chimney_height = height


## Lead flashing where the stack meets the roof: an apron lying on the roof round the stack and a
## short upstand dressed up against the bricks on every side (stepped along the slope on a pitch).
func _flashing(base: Vector3) -> void:
	var lead := GB.mat(Color(0.47, 0.49, 0.53), 0.25, 0.55, 0.3)
	var h := chimney_outer * 0.5
	var lip := 0.075  # apron width out from the bricks
	var up := 0.1  # upstand height
	var th := 0.012
	if roof_type == 1:
		var a := deg_to_rad(steep_angle_deg)
		var b := Basis(Vector3.BACK, -a)
		var roof_c := base.y + chimney_below - h * tan(a)
		var pc := Vector3(base.x, roof_c, base.z)
		var hl := h / cos(a)  # half the stack's footprint measured along the slope
		var n := b.y
		# apron, in the roof's frame (x down the slope, y the roof normal, z across)
		for s2: float in [-1.0, 1.0]:
			var fm := GB.add_mesh(self, _bm(Vector3(2.0 * (hl + lip), th, lip)), pc + n * th * 0.5 + b * Vector3(0, 0, s2 * (h + lip * 0.5)), Vector3.ZERO, lead)
			fm.basis = b
			fm = GB.add_mesh(self, _bm(Vector3(lip, th, 2.0 * h)), pc + n * th * 0.5 + b * Vector3(s2 * (hl + lip * 0.5), 0, 0), Vector3.ZERO, lead)
			fm.basis = b
			# step flashing up the two sides that run down the slope
			fm = GB.add_mesh(self, _bm(Vector3(2.0 * hl + 0.016, up, 0.008)), pc + n * up * 0.5 + Vector3(0, 0, s2 * (h + 0.004)), Vector3.ZERO, lead)
			fm.basis = b
			# front (downhill) and back (uphill) upstands, level
			var x := s2 * (h + 0.004)
			var ry := roof_c - s2 * h * tan(a)
			GB.box(self, Vector3(0.008, up, 2.0 * h + 0.016), Vector3(base.x + x, ry + up * 0.5, base.z), Color(0.47, 0.49, 0.53)).material_override = lead
	else:
		var y := base.y
		for s2: float in [-1.0, 1.0]:
			GB.add_mesh(self, _bm(Vector3(2.0 * (h + lip), th, lip)), Vector3(base.x, y + th * 0.5, base.z + s2 * (h + lip * 0.5)), Vector3.ZERO, lead)
			GB.add_mesh(self, _bm(Vector3(lip, th, 2.0 * h)), Vector3(base.x + s2 * (h + lip * 0.5), y + th * 0.5, base.z), Vector3.ZERO, lead)
			GB.add_mesh(self, _bm(Vector3(2.0 * h + 0.016, up, 0.008)), Vector3(base.x, y + up * 0.5, base.z + s2 * (h + 0.004)), Vector3.ZERO, lead)
			GB.add_mesh(self, _bm(Vector3(0.008, up, 2.0 * h)), Vector3(base.x + s2 * (h + 0.004), y + up * 0.5, base.z), Vector3.ZERO, lead)


## World point on the flue's centre line at world height wy (follows the stack's lean above the
## roof; straight down the shaft below it).
func flue_axis_world(wy: float) -> Vector3:
	if chimney_model == null:
		var b := to_global(chimney_base)
		return Vector3(b.x, wy, b.z)
	var m: Node3D = chimney_model
	var ly := m.to_local(Vector3(m.global_position.x, wy, m.global_position.z)).y
	var p: Vector3 = m.to_global(m.call("axis_at", ly))
	return Vector3(p.x, wy, p.z)


## World point on the chimney (local to the stack, so it follows the lean and crook).
func chimney_point(local: Vector3) -> Vector3:
	return chimney_model.to_global(local) if chimney_model else to_global(chimney_base + local)


## Centre of the flue mouth (top of the liner), world.
func get_chimney_mouth_world() -> Vector3:
	if chimney_model == null:
		return to_global(chimney_base + Vector3(0, chimney_height, 0))
	var m: Node3D = chimney_model
	return m.to_global(Vector3(m.get("crook").x, float(m.get("mouth_y")), m.get("crook").z))


## 0 shut .. 1 fully open (the plate swings up and back from its front hinge).
func set_damper(k: float) -> void:
	if damper_hinge:
		damper_hinge.rotation.x = deg_to_rad(80.0) * clampf(k, 0.0, 1.0)


func brick_dark() -> ShaderMaterial:
	return Furn.brick_material(Color(0.55, 0.2, 0.15))


func _bm(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## Real fireplace anatomy below the stack (CHIMNEY-RESEARCH.md), visual only, inside the breast:
## a 250 mm clay flue liner straight down from the stack to the smoke chamber; the chamber, a
## corbelled brick funnel 0.6 m tall widening to the 0.9 m throat over the firebox (it also takes
## up any sideways offset between the stack and the fireplace); the smoke shelf behind the throat
## with its crust of soot; and the cast-iron throat damper, its plate hinged at the front and
## swinging up and back. The fire's flickering glow climbs the walls from the throat.
var flue_info := {}  ## local points: liner_bottom, throat, firebox (centres) + sizes
var flue_blockers: Array = []  ## interior meshes crossing the liner (hidden while the camera is in it)

func _build_flue_shaft() -> void:
	var top := chimney_base.y + 0.05
	var fs := flue_size
	var fp: Vector3 = interior.get("fireplace_spawn") if interior else Vector3(chimney_base.x, 0.0, chimney_base.z)
	var zc := fp.z + 0.05  # fireplace front reference (the model's origin)
	var f := fp.y
	var throat_y := f + 0.95
	var ch_h := 0.6
	var liner_y := throat_y + ch_h
	if top - liner_y < 0.3:
		return
	var tw := 0.9  # throat / chamber bottom width
	var bz0 := zc - 0.28  # chamber back (over the smoke shelf)
	var bz1 := zc + 0.155  # chamber front (behind the lintel)
	var bc := Vector3(fp.x, throat_y, (bz0 + bz1) * 0.5)
	# the chamber sits square over the firebox; if the stack is off to one side, the liner makes a
	# 30-degree offset (as masons do) from the top of the chamber to under the stack
	var ct := Vector3(bc.x, liner_y, bc.z)
	var off := Vector2(chimney_base.x - ct.x, chimney_base.z - ct.z)
	var kink_y := minf(liner_y + off.length() / tan(deg_to_rad(30.0)), top - 0.3)
	var lc := Vector3(chimney_base.x, kink_y, chimney_base.z)
	flue_info = {"liner_bottom": lc, "chamber_top": ct, "throat": Vector3(fp.x, throat_y, zc + 0.04), "firebox": fp + Vector3(0, 0.05, 0),
			"liner_top": Vector3(chimney_base.x, top, chimney_base.z), "fs": fs,
			"liner_y": liner_y, "kink_y": kink_y, "throat_y": throat_y, "tw": tw, "bz0": bz0, "bz1": bz1, "zc": zc, "ch_h": ch_h}
	var mouth_y := get_chimney_mouth_world().y
	var full := mouth_y - to_global(Vector3(0, throat_y, 0)).y
	_shaft_mat = ShaderMaterial.new()
	_shaft_mat.shader = ChimneyModel.FLUE_SHADER
	_shaft_mat.set_shader_parameter("mode", 0)  # brick-lined flue: real bricks read better than a plain clay tube
	var brick_mat := ShaderMaterial.new()
	brick_mat.shader = ChimneyModel.FLUE_SHADER
	_chamber_mat = brick_mat
	var cmf: ShaderMaterial = chimney_model.get("flue_mat") as ShaderMaterial
	cmf.set_shader_parameter("mode", 0)
	for m: ShaderMaterial in [_shaft_mat, cmf, brick_mat]:
		m.set_shader_parameter("soot_top_y", mouth_y)
		m.set_shader_parameter("soot_depth", maxf(1.0, full * 0.55))
		m.set_shader_parameter("soot_max", 0.62)  # sooty, but the brick and mortar still read
		m.set_shader_parameter("glow_bottom_y", to_global(Vector3(0, throat_y - 0.25, 0)).y)
		m.set_shader_parameter("glow_reach", 2.6)
	# the liner: an inward-facing square tube
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube_in(st, Rect2(lc.x - fs * 0.5, lc.z - fs * 0.5, fs, fs), kink_y, Rect2(lc.x - fs * 0.5, lc.z - fs * 0.5, fs, fs), top)
	if kink_y > liner_y + 0.001:
		_tube_in(st, Rect2(ct.x - fs * 0.5, ct.z - fs * 0.5, fs, fs), liner_y, Rect2(lc.x - fs * 0.5, lc.z - fs * 0.5, fs, fs), kink_y)
	st.generate_normals()
	var liner := MeshInstance3D.new()
	liner.name = "FlueLiner"
	liner.mesh = st.commit()
	liner.material_override = _shaft_mat
	liner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(liner)
	# the smoke chamber: corbelled courses stepping in from the throat to the liner
	var courses := 8
	var ch := ch_h / courses
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r0 := Rect2(fp.x - tw * 0.5, bz0, tw, bz1 - bz0)
	var r1 := Rect2(ct.x - fs * 0.5, ct.z - fs * 0.5, fs, fs)
	var prev := r0
	for k in courses:
		var t := float(k) / float(courses - 1)
		var r := Rect2(r0.position.lerp(r1.position, t), r0.size.lerp(r1.size, t))
		var y0 := throat_y + k * ch
		_tube_in(st2, r, y0, r, y0 + ch)
		if k > 0:
			_ledge_down(st2, prev, r, y0)
		prev = r
	st2.generate_normals()
	var chamber := MeshInstance3D.new()
	chamber.name = "SmokeChamber"
	chamber.mesh = st2.commit()
	chamber.material_override = brick_mat
	chamber.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(chamber)
	# smoke shelf: a ledge behind the throat with a crust of soot and grit
	var shelf_mat := GB.mat(Color(0.07, 0.06, 0.055), 0.0, 0.0, 0.0)
	GB.add_mesh(self, _bm(Vector3(tw, 0.03, zc - 0.07 - bz0)), Vector3(fp.x, throat_y - 0.015, (bz0 + zc - 0.07) * 0.5), Vector3.ZERO, shelf_mat)
	var grit := RandomNumberGenerator.new()
	grit.seed = 4411 + roof_type
	for k in 26:
		var gp := Vector3(fp.x + grit.randf_range(-0.4, 0.4), throat_y + 0.004, grit.randf_range(bz0 + 0.02, zc - 0.09))
		GB.sphere(self, grit.randf_range(0.006, 0.018), gp, Color(0.05, 0.045, 0.04).lightened(grit.randf() * 0.12), 0.0, Vector3(1.4, 0.4, 1.1))
	# throat damper: a cast-iron frame across the throat, the plate hinged on its front edge
	var iron := GB.mat(Color(0.16, 0.15, 0.15), 0.0, 0.1, 0.15)
	var dz0 := zc - 0.07
	var dz1 := zc + 0.15
	for sx: float in [-1.0, 1.0]:
		GB.add_mesh(self, _bm(Vector3(0.025, 0.035, dz1 - dz0)), Vector3(fp.x + sx * (tw * 0.5 - 0.0125), throat_y - 0.02, (dz0 + dz1) * 0.5), Vector3.ZERO, iron)
	GB.add_mesh(self, _bm(Vector3(tw, 0.035, 0.02)), Vector3(fp.x, throat_y - 0.02, dz1 - 0.01), Vector3.ZERO, iron)
	GB.add_mesh(self, _bm(Vector3(tw, 0.035, 0.02)), Vector3(fp.x, throat_y - 0.02, dz0 + 0.01), Vector3.ZERO, iron)
	damper_hinge = Node3D.new()
	damper_hinge.name = "Damper"
	damper_hinge.position = Vector3(fp.x, throat_y, dz1 - 0.02)
	add_child(damper_hinge)
	if not break_chimney:  # the plate is solid for the elf (it swings with the hinge)
		var db := StaticBody3D.new()
		db.name = "DamperCollision"
		db.collision_layer = Interior.INTERIOR_LAYER
		db.collision_mask = 0
		db.set_meta("surface_name", "Damper")
		damper_hinge.add_child(db)
		var dpl := dz1 - dz0 - 0.04
		Carve.box(db, Vector3(tw - 0.06, 0.02, dpl), Vector3(0, 0.006, -dpl * 0.5))
	var pl := dz1 - dz0 - 0.04
	GB.add_mesh(damper_hinge, _bm(Vector3(tw - 0.06, 0.012, pl)), Vector3(0, 0.006, -pl * 0.5), Vector3.ZERO, iron)
	for rx in [-0.3, 0.0, 0.3]:
		GB.add_mesh(damper_hinge, _bm(Vector3(0.02, 0.01, pl - 0.02)), Vector3(rx, 0.016, -pl * 0.5), Vector3.ZERO, iron)
	var rod := CylinderMesh.new()
	rod.top_radius = 0.008
	rod.bottom_radius = 0.008
	rod.height = tw - 0.04
	GB.add_mesh(damper_hinge, rod, Vector3.ZERO, Vector3(0, 0, 90), iron)
	set_damper(1.0)  # open while the fire's lit
	# a couple of cobwebs up in the cold top of the liner, and soot dust hanging in the air
	var hfs := fs * 0.5 - 0.004
	for w in [[0.82, Vector2(1, 1), 0.12], [0.6, Vector2(-1, -1), 0.1]]:
		var wy: float = lerpf(liner_y, top + chimney_height * 0.7, float(w[0]))
		var d: Vector2 = w[1]
		var ax: Vector3 = chimney_model.call("axis_at", wy - chimney_base.y) if chimney_model and wy > chimney_base.y else Vector3.ZERO
		var pos := Vector3(chimney_base.x + ax.x + d.x * (hfs - float(w[2]) * 0.3), wy, chimney_base.z + ax.z + d.y * (hfs - float(w[2]) * 0.3))
		var web := ChimneyModel.cobweb(self, pos, float(w[2]), rad_to_deg(atan2(d.x, d.y)) + 90.0)
		web.rotation_degrees.x = -12.0
	var dust := FX.motes(Vector3(fs * 0.8, (top - liner_y) * 0.5, fs * 0.8), Color(0.35, 0.3, 0.27), 24, 0.012)
	dust.position = Vector3(lc.x, (kink_y + top) * 0.5, lc.z)
	add_child(dust)
	_shaft_light = OmniLight3D.new()
	_shaft_light.add_to_group("no_night_switch")
	_shaft_light.position = Vector3(fp.x, throat_y + 0.15, bc.z)
	_shaft_light.omni_range = 1.4
	_shaft_light.omni_attenuation = 1.8
	_shaft_light.shadow_enabled = false
	add_child(_shaft_light)
	# interior meshes the liner passes through (floor and ceiling slabs): hidden while the cutscene
	# camera is inside the flue so it sees down the liner
	if interior:
		var col := AABB(Vector3(lc.x - fs * 0.5, kink_y + 0.05, lc.z - fs * 0.5), Vector3(fs, top - kink_y, fs))
		for n in interior.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var bb := global_transform.affine_inverse() * (mi.global_transform * mi.get_aabb()) if is_inside_tree() else interior.transform * (mi.transform * mi.get_aabb())
			if bb.intersects(col):
				flue_blockers.append(mi)
	_apply_flue_glow()


var _chamber_mat: ShaderMaterial


## Inward-facing walls between two rectangles (x,z) at heights y0 and y1.
func _tube_in(st: SurfaceTool, a: Rect2, y0: float, b: Rect2, y1: float) -> void:
	var ca := [Vector3(a.position.x, y0, a.position.y), Vector3(a.end.x, y0, a.position.y), Vector3(a.end.x, y0, a.end.y), Vector3(a.position.x, y0, a.end.y)]
	var cb := [Vector3(b.position.x, y1, b.position.y), Vector3(b.end.x, y1, b.position.y), Vector3(b.end.x, y1, b.end.y), Vector3(b.position.x, y1, b.end.y)]
	for i in 4:
		var j := (i + 1) % 4
		# winding so the faces point into the tube
		st.add_vertex(ca[i])
		st.add_vertex(cb[i])
		st.add_vertex(ca[j])
		st.add_vertex(ca[j])
		st.add_vertex(cb[i])
		st.add_vertex(cb[j])


## The underside of a corbel step (between a wider course below and a narrower one above), facing down.
func _ledge_down(st: SurfaceTool, lo: Rect2, hi: Rect2, y: float) -> void:
	var o := [Vector3(lo.position.x, y, lo.position.y), Vector3(lo.end.x, y, lo.position.y), Vector3(lo.end.x, y, lo.end.y), Vector3(lo.position.x, y, lo.end.y)]
	var n := [Vector3(hi.position.x, y, hi.position.y), Vector3(hi.end.x, y, hi.position.y), Vector3(hi.end.x, y, hi.end.y), Vector3(hi.position.x, y, hi.end.y)]
	for i in 4:
		var j := (i + 1) % 4
		st.add_vertex(o[i])
		st.add_vertex(o[j])
		st.add_vertex(n[i])
		st.add_vertex(n[i])
		st.add_vertex(o[j])
		st.add_vertex(n[j])


## Hide / show the floor and ceiling slabs the liner passes through (cutscene camera in the flue).
func set_flue_view(on: bool) -> void:
	_flue_view = on
	for mi in flue_blockers:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).visible = not on
	if not on:
		_set_shell_cut(false)


## While the cutscene camera is down inside the liner, the house shell around the stack (the
## walls box's top cap, roof slabs, fascia, the roofline light strings) is hidden: the liner hides
## it anyway, and its faces at roof height otherwise cut across the flue as a flat coloured slab
## right in front of the camera (the "orange / purple bar" at the top of the descent).
var _flue_view := false
var _shell_cut := false
var _shell_nodes: Array = []


func _set_shell_cut(on: bool) -> void:
	if on == _shell_cut:
		return
	_shell_cut = on
	if on and _shell_nodes.is_empty():
		var fs := flue_size * 0.5 + 0.9
		var top := get_chimney_mouth_world().y
		var col := AABB(to_global(Vector3(chimney_base.x - fs, 0, chimney_base.z - fs)), Vector3(fs * 2.0, 0, fs * 2.0))
		col.position.y = to_global(Vector3(0, wall_height - 0.7, 0)).y
		col.size.y = top - col.position.y
		var keep := [interior, chimney_model, damper_hinge]
		for c in get_children():
			if c in keep or str(c.name) in ["FlueLiner", "SmokeChamber"]:
				continue
			var vis: Array = c.find_children("*", "GeometryInstance3D", true, false)
			if c is GeometryInstance3D:
				vis.append(c)
			for g: GeometryInstance3D in vis:
				if not g.visible:
					continue
				var bb := g.global_transform * g.get_aabb()
				if bb.intersects(col) and bb.end.y > col.position.y:
					_shell_nodes.append(g)
	for g in _shell_nodes:
		if is_instance_valid(g):
			(g as GeometryInstance3D).visible = not on


## Colours of the flue (bottom glow, chimney-top glow, frost) for the fire state.
func _apply_flue_glow() -> void:
	var col := Color(1.0, 0.5, 0.18)
	var e := 0.5
	if fire_lit:
		e = 1.6
	elif fire_frozen:
		col = Color(0.45, 0.75, 1.0)
		e = 1.0
	for m in [_shaft_mat, _chamber_mat, (chimney_model.get("flue_mat") if chimney_model else null)]:
		if m:
			(m as ShaderMaterial).set_shader_parameter("glow_color", col)
			(m as ShaderMaterial).set_shader_parameter("glow_energy", e)
	if _shaft_light:
		_shaft_light.light_color = col
		_shaft_light.light_energy = e * 0.9
	if _shaft_glow:
		_shaft_glow.material_override = GB.mat(col, e * 1.4)
	if chimney_model:
		chimney_model.call("set_state", fire_lit, fire_frozen)


## A real fire in the firebox, made to look right from the room AND from straight above (the elf
## comes down the flue): three split logs on an iron grate with fire dogs, charred ends glowing,
## an ember bed with a glowing crackle, layered flame tongues (bent cones eaten by scrolling noise,
## so they read as licks from any angle), rising sparks, smoke drawn up the throat, a heat shimmer
## and a flickering warm light. Iced by the Fireplace Icer: frosted logs, blue ice crystals and a
## cold mist instead.
const FLAME_SHADER := preload("res://shaders/fire_flame.gdshader")
const EMBER_SHADER := preload("res://shaders/fire_embers.gdshader")
const HAZE_SHADER := preload("res://shaders/heat_haze.gdshader")
var _ember_mats: Array = []
var _log_mat: StandardMaterial3D
var _flames: Array = []
var _cold_nodes: Array = []

func _build_fire() -> void:
	var fp: Vector3 = interior.get("fireplace_spawn")
	var fire := Node3D.new()
	fire.name = "Fire"
	fire.position = fp + Vector3(0, 0.0, -0.03)
	add_child(fire)
	var iron := Color(0.1, 0.09, 0.09)
	# grate: two cast-iron fire dogs (with brass knobs at the front) and bars between them
	for s2: float in [-1.0, 1.0]:
		GB.box(fire, Vector3(0.025, 0.02, 0.36), Vector3(s2 * 0.2, 0.06, 0.0), iron)
		GB.box(fire, Vector3(0.025, 0.12, 0.025), Vector3(s2 * 0.2, 0.06, 0.17), iron)
		GB.box(fire, Vector3(0.02, 0.06, 0.02), Vector3(s2 * 0.2, 0.03, -0.16), iron)
		GB.sphere(fire, 0.022, Vector3(s2 * 0.2, 0.135, 0.17), Color(0.85, 0.62, 0.25), 0.1)
	for k in 5:
		GB.box(fire, Vector3(0.42, 0.012, 0.012), Vector3(0, 0.07, -0.13 + k * 0.065), iron)
	# ember bed on the inner hearth, under the grate
	var bed_m := ShaderMaterial.new()
	bed_m.shader = EMBER_SHADER
	bed_m.set_shader_parameter("scale", 22.0)
	_ember_mats.append(bed_m)
	var bed := MeshInstance3D.new()
	var bm := PlaneMesh.new()
	bm.size = Vector2(0.5, 0.38)
	bm.subdivide_width = 6
	bm.subdivide_depth = 6
	bed.mesh = bm
	bed.material_override = bed_m
	bed.position = Vector3(0, 0.022, 0.0)
	fire.add_child(bed)
	for k in 14:  # lumps of glowing coal in the bed
		var lump := GB.sphere(fire, _rng.randf_range(0.015, 0.03), Vector3(_rng.randf_range(-0.2, 0.2), 0.03, _rng.randf_range(-0.14, 0.14)), Color.BLACK, 0.0, Vector3(1.3, 0.6, 1.1))
		lump.material_override = bed_m
	# split logs (about 100 mm across, 400 mm long): bark, charred and glowing at the ends
	_log_mat = StandardMaterial3D.new()
	_log_mat.albedo_color = Color(0.3, 0.18, 0.1)
	_log_mat.roughness = 0.95
	var char_m := ShaderMaterial.new()
	char_m.shader = EMBER_SHADER
	char_m.set_shader_parameter("scale", 40.0)
	_ember_mats.append(char_m)
	var logs := [[Vector3(-0.02, 0.12, -0.06), Vector3(0, 8, 90), 0.05], [Vector3(0.01, 0.12, 0.07), Vector3(0, -12, 90), 0.045],
			[Vector3(0.0, 0.2, 0.0), Vector3(0, 70, 90), 0.042]]
	for L in logs:
		var lg := Node3D.new()
		lg.position = L[0]
		lg.rotation_degrees = L[1]
		fire.add_child(lg)
		var r: float = L[2]
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r * 1.06
		cm.height = 0.4
		cm.radial_segments = 9
		var body := MeshInstance3D.new()
		body.mesh = cm
		body.material_override = _log_mat
		lg.add_child(body)
		# the underside and middle burnt black and cracked (char), glowing
		var under := MeshInstance3D.new()
		var um := CylinderMesh.new()
		um.top_radius = r * 1.02
		um.bottom_radius = r * 1.08
		um.height = 0.26
		um.radial_segments = 9
		under.mesh = um
		under.material_override = char_m
		under.position = Vector3(0.012, 0, 0)
		under.scale = Vector3(1, 1, 0.92)
		lg.add_child(under)
		for e: float in [-1.0, 1.0]:  # end grain: dark rings with a hot core
			var cap := MeshInstance3D.new()
			var capm := CylinderMesh.new()
			capm.top_radius = r * 0.98
			capm.bottom_radius = r * 0.98
			capm.height = 0.006
			capm.radial_segments = 9
			cap.mesh = capm
			cap.material_override = char_m
			cap.position = Vector3(0, e * 0.2, 0)
			lg.add_child(cap)
	# flame tongues: layered bent cones along the logs, tallest in the middle
	var tongues := [[Vector3(0.0, 0.14, 0.0), 0.3, 0.08], [Vector3(-0.1, 0.13, -0.03), 0.22, 0.06], [Vector3(0.1, 0.13, 0.03), 0.24, 0.06],
			[Vector3(-0.05, 0.15, 0.06), 0.18, 0.05], [Vector3(0.06, 0.15, -0.06), 0.2, 0.05], [Vector3(-0.16, 0.12, 0.04), 0.14, 0.04],
			[Vector3(0.16, 0.12, -0.02), 0.15, 0.04], [Vector3(0.0, 0.16, 0.0), 0.38, 0.045]]
	var tk := 0
	for T in tongues:
		var h: float = T[1]
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = float(T[2]) * 0.75
		cone.height = h
		cone.radial_segments = 10
		cone.rings = 6
		var fm := ShaderMaterial.new()
		fm.shader = FLAME_SHADER
		fm.set_shader_parameter("seed", float(tk) * 1.37)
		fm.set_shader_parameter("cone_h", h)
		fm.set_shader_parameter("sway", 0.02 + h * 0.08)
		fm.set_shader_parameter("intensity", 1.15 if tk < 7 else 0.8)
		var fl := MeshInstance3D.new()
		fl.mesh = cone
		fl.material_override = fm
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# lean each tongue away from the middle of the fire (a fan of licks seen from above)
		var base_p: Vector3 = T[0]
		var lean_dir := Vector3(base_p.x, 0, base_p.z)
		if lean_dir.length() < 0.01:
			lean_dir = Vector3(0, 0, 1) if tk % 2 == 0 else Vector3(0, 0, -1)
		var lean_axis := Vector3.UP.cross(lean_dir.normalized())
		var lean := deg_to_rad(10.0 + 6.0 * float(tk % 3))
		fl.basis = Basis(lean_axis, lean)
		fl.position = base_p + fl.basis * Vector3(0, h * 0.5, 0)
		fire.add_child(fl)
		_flames.append(fl)
		_fire_nodes.append(fl)
		tk += 1
	# small flame sprites licking off the logs, sparks rising, smoke drawn up the throat
	var fl2 := FX.flames(Vector3(0.18, 0.02, 0.1))
	fl2.amount = 6
	fl2.position = Vector3(0, 0.16, 0)
	fl2.scale = Vector3.ONE * 0.32
	fire.add_child(fl2)
	_fire_nodes.append(fl2)
	var sparks := FX.make("dot", 22, 2.2, 0.012, [Color(1, 0.8, 0.3, 0.0), Color(1, 0.75, 0.3, 1.0), Color(1, 0.4, 0.1, 0.8), Color(0.8, 0.2, 0.05, 0.0)],
			{"box": Vector3(0.18, 0.02, 0.1), "dir": Vector3.UP, "spread": 18.0, "vmin": 0.4, "vmax": 1.1, "add": true, "turb": 0.6,
			"gravity": Vector3(0, 0.15, 0), "scale_curve": [Vector2(0, 1), Vector2(1, 0.3)]})
	sparks.position = Vector3(0, 0.2, 0)
	sparks.visibility_aabb = AABB(Vector3(-1, -0.5, -1), Vector3(2, 3, 2))
	fire.add_child(sparks)
	_fire_nodes.append(sparks)
	var smoke := FX.make("blob", 10, 1.6, 0.14, [Color(0.12, 0.11, 0.1, 0.0), Color(0.12, 0.11, 0.1, 0.3), Color(0.1, 0.1, 0.1, 0.15), Color(0.1, 0.1, 0.1, 0.0)],
			{"box": Vector3(0.12, 0.02, 0.06), "dir": Vector3.UP, "spread": 10.0, "vmin": 0.25, "vmax": 0.45, "lit": true, "turb": 0.3,
			"scale_curve": [Vector2(0, 0.5), Vector2(1, 1.6)]})
	smoke.position = Vector3(0, 0.45, 0.02)
	smoke.visibility_aabb = AABB(Vector3(-1, -0.5, -1), Vector3(2, 3, 2))
	fire.add_child(smoke)
	_fire_nodes.append(smoke)
	# heat shimmer: a horizontal sheet over the flames (wobbles the view from above) and a vertical one
	var hz_m := ShaderMaterial.new()
	hz_m.shader = HAZE_SHADER
	for rot in [Vector3(90, 0, 0)]:
		var hz := MeshInstance3D.new()
		var hp := PlaneMesh.new()
		hp.size = Vector2(0.5, 0.4)
		hz.mesh = hp
		hz.material_override = hz_m
		hz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hz.rotation_degrees = rot
		hz.position = Vector3(0, 0.5, 0) if rot == Vector3.ZERO else Vector3(0, 0.42, 0.1)
		fire.add_child(hz)
		_fire_nodes.append(hz)
	_fire_light = OmniLight3D.new()
	_fire_light.add_to_group("no_night_switch")
	_fire_light.light_color = Color(1.0, 0.55, 0.2)
	_fire_light.light_energy = fire_light_energy
	_fire_light.omni_range = 4.5
	_fire_light.light_cull_mask = 2
	_fire_light.position = Vector3(0, 0.35, 0.35)
	fire.add_child(_fire_light)
	# iced: blue ice crystals (six-sided, pointed) growing off the logs and grate, and a cold mist
	var ice_m := StandardMaterial3D.new()
	ice_m.albedo_color = Color(0.7, 0.88, 1.0, 0.85)
	ice_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ice_m.emission_enabled = true
	ice_m.emission = Color(0.35, 0.65, 1.0)
	ice_m.emission_energy_multiplier = 0.7
	ice_m.roughness = 0.1
	ice_m.metallic_specular = 0.9
	for k in 16:
		var cr := CylinderMesh.new()
		var cl := _rng.randf_range(0.06, 0.2)
		cr.top_radius = 0.0
		cr.bottom_radius = _rng.randf_range(0.012, 0.028)
		cr.height = cl
		cr.radial_segments = 6
		cr.rings = 1
		var ice := MeshInstance3D.new()
		ice.mesh = cr
		ice.material_override = ice_m
		var a := _rng.randf() * TAU
		var base := Vector3(_rng.randf_range(-0.18, 0.18), _rng.randf_range(0.03, 0.2), _rng.randf_range(-0.12, 0.12))
		ice.position = base + Vector3(0, cl * 0.4, 0)
		ice.rotation = Vector3(_rng.randf_range(-0.6, 0.6), a, _rng.randf_range(-0.6, 0.6))
		ice.visible = false
		fire.add_child(ice)
		_ice_nodes.append(ice)
	var mist := FX.make("blob", 16, 3.5, 0.22, [Color(0.75, 0.88, 1.0, 0.0), Color(0.75, 0.88, 1.0, 0.3), Color(0.7, 0.85, 1.0, 0.18), Color(0.7, 0.85, 1.0, 0.0)],
			{"box": Vector3(0.25, 0.03, 0.18), "dir": Vector3(0, 0.3, 1), "spread": 40.0, "vmin": 0.03, "vmax": 0.1, "lit": true,
			"gravity": Vector3(0, -0.02, 0), "scale_curve": [Vector2(0, 0.6), Vector2(1, 1.5)]})
	mist.position = Vector3(0, 0.06, 0.05)
	mist.emitting = false
	fire.add_child(mist)
	_cold_nodes.append(mist)
	_chimney_smoke = FX.smoke(Color(0.55, 0.5, 0.6), chimney_smoke_amount, 0.9)
	_chimney_smoke.position = chimney_base + Vector3(0, chimney_height + 0.4, 0)
	add_child(_chimney_smoke)
	for n in fire.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = 2


func set_fire(on: bool) -> void:
	fire_lit = on
	for n in _fire_nodes:
		if n is GPUParticles3D:
			(n as GPUParticles3D).emitting = on
		else:
			(n as Node3D).visible = on
	if _fire_light:
		_fire_light.visible = on
	if _chimney_smoke:
		_chimney_smoke.emitting = on
	if on:
		fire_frozen = false
	_apply_fire_look()
	_apply_flue_glow()


## Embers and logs for the state: burning (glowing cracks), out (cold char) or iced (frosted logs,
## ice crystals, cold mist).
func _apply_fire_look() -> void:
	for m in _ember_mats:
		(m as ShaderMaterial).set_shader_parameter("heat", 1.0 if fire_lit else 0.0)
		(m as ShaderMaterial).set_shader_parameter("frost", 1.0 if fire_frozen else 0.0)
	if _log_mat:
		_log_mat.albedo_color = Color(0.72, 0.84, 0.95) if fire_frozen else Color(0.3, 0.18, 0.1)
		_log_mat.roughness = 0.35 if fire_frozen else 0.95
	for i in _ice_nodes:
		(i as Node3D).visible = fire_frozen
	for c in _cold_nodes:
		(c as GPUParticles3D).emitting = fire_frozen


func freeze_fire() -> void:
	fire_frozen = true
	set_fire(false)
	fire_frozen = true
	_apply_fire_look()
	_apply_flue_glow()


func _process(delta: float) -> void:
	_t += delta
	if _flue_view:
		var cam := get_viewport().get_camera_3d()
		if cam:
			var lp := to_local(cam.global_position)
			var inside := lp.y < to_local(get_chimney_mouth_world()).y - 0.06 and Vector2(lp.x - chimney_base.x, lp.z - chimney_base.z).length() < flue_size
			_set_shell_cut(inside)
	if _fire_light and fire_lit:
		var fk := 0.8 + 0.12 * sin(_t * 13.0) * sin(_t * 7.3 + 1.0) + 0.08 * sin(_t * 23.0 + 2.0)
		_fire_light.light_energy = fire_light_energy * fk
		if _shaft_light:
			_shaft_light.light_energy = 1.45 * fk
		for m in [_shaft_mat, _chamber_mat, (chimney_model.get("flue_mat") if chimney_model else null)]:
			if m:
				(m as ShaderMaterial).set_shader_parameter("flicker", fk / 0.8)


func _add_sign(text: String, y: float, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = Vector3(0, y, 0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 72
	l.outline_size = 18
	l.pixel_size = 0.012
	l.modulate = color
	l.shaded = false
	add_child(l)


func _fascia(w: float, d: float, top_y: float) -> void:
	# Chunky trim around the roof edge, kept just below the landing surface.
	var t := 0.45
	var c := trim_color
	GB.box(self, Vector3(w + 0.5, t, 0.3), Vector3(0, top_y - t * 0.5 - 0.02, d * 0.5 + 0.1), c)
	GB.box(self, Vector3(w + 0.5, t, 0.3), Vector3(0, top_y - t * 0.5 - 0.02, -d * 0.5 - 0.1), c)
	GB.box(self, Vector3(0.3, t, d + 0.5), Vector3(w * 0.5 + 0.1, top_y - t * 0.5 - 0.02, 0), c)
	GB.box(self, Vector3(0.3, t, d + 0.5), Vector3(-w * 0.5 - 0.1, top_y - t * 0.5 - 0.02, 0), c)


func _annex(side: float, h: float) -> void:
	# Mismatched bolt-on extension (Hello Neighbor houses are always growing extra bits).
	var w := 4.0
	var d := depth * 0.55
	var x := side * (width * 0.5 + w * 0.5 - 0.1)
	_static_box(Vector3(w, h, d), Transform3D(Basis(), Vector3(x, h * 0.5, d * 0.2)), Color(), 0.6, "house", "Wall", null, false)
	var m := BoxMesh.new()
	m.size = Vector3(w, h, d)
	m.subdivide_height = 4
	GB.add_mesh(self, m, Vector3(x, h * 0.5, d * 0.2), Vector3.ZERO, GB.warped(trim_color.lightened(0.25), h, 0.15, 0.03, _phase + 1.0))
	GB.box(self, Vector3(w + 0.6, 0.25, d + 0.6), Vector3(x, h + 0.25, d * 0.2), roof_color, Vector3(0, 0, -side * 9))
	GB.box(self, Vector3(0.12, 1.0, 0.9), Vector3(x + side * (w * 0.5 + 0.02), h * 0.55, d * 0.2), WARM, Vector3(0, 0, 4), 1.3)


func _build_flat() -> void:
	landing_top = wall_height + 0.3
	var slab := _static_box(Vector3(width + 0.4, 0.3, depth + 0.4), Transform3D(Basis(), Vector3(0, wall_height + 0.15, 0)), roof_color, pad_friction, "roof", "Flat pad",
			GB.patchy(roof_color, roof_color.lightened(0.18), 0.5, 0.35))
	_cut_flue(_mesh_of(slab))
	_fascia(width + 0.4, depth + 0.4, landing_top)
	# Pad markings (visual only, flush with the surface)
	GB.cylinder(self, 2.7, 2.7, 0.02, Vector3(0, landing_top + 0.01, 0), Color(1.0, 0.78, 0.1), Vector3.ZERO, 0.25, 32)
	GB.cylinder(self, 2.35, 2.35, 0.02, Vector3(0, landing_top + 0.02, 0), roof_color.darkened(0.25), Vector3.ZERO, 0.0, 32)
	GB.box(self, Vector3(0.55, 0.02, 3.0), Vector3(0, landing_top + 0.03, 0), Color(1.0, 0.78, 0.1), Vector3.ZERO, 0.25)
	_outline_rect(width + 0.3, depth + 0.3, landing_top + 0.07, GREEN)
	_chimney(chimney_base, chimney_height, 1.0)
	_annex(-1.0, wall_height * 0.6)
	for p in [Vector3(-1, 0, -1), Vector3(1, 0, 1)]:
		GB.omni(self, Vector3(p.x * width * 0.5, landing_top + 0.6, p.z * depth * 0.5), GREEN, 1.4, 7.0)
	_add_sign("FLAT PAD\neasy", landing_top + 5.0, Color(0.4, 1.0, 0.45))


func _build_steep() -> void:
	var a := deg_to_rad(steep_angle_deg)
	var slope_w := (width - ridge_pad_width) * 0.5
	var rise := slope_w * tan(a)
	var board_len := slope_w / cos(a)
	var hd := (depth + 0.4) * 0.5
	slope_center_x = ridge_pad_width * 0.5 + slope_w * 0.5
	var shingle := GB.patchy(roof_color, roof_color.lightened(0.2), 0.55, 0.6)
	for side: float in [-1.0, 1.0]:
		var b := Basis(Vector3.BACK, -side * a)
		var pos := Vector3(side * slope_center_x, wall_height + rise * 0.5, 0)
		var board := _static_box(Vector3(board_len + 0.1, 0.3, depth + 0.4), Transform3D(b, pos), roof_color, steep_slope_friction, "roof", "Steep slope", shingle)
		if side > 0.0:
			_cut_flue(_mesh_of(board))
		# Chunky eave beam under the low edge (visual)
		GB.box(self, Vector3(0.35, 0.4, depth + 0.7), Vector3(side * (width * 0.5 + 0.05), wall_height - 0.15, 0), trim_color)
	_static_box(Vector3(ridge_pad_width, 0.3, depth + 0.4), Transform3D(Basis(), Vector3(0, wall_height + rise, 0)), Color(0.3, 0.26, 0.36), pad_friction, "roof", "Ridge pad")
	landing_top = wall_height + rise + 0.15
	# Attic gable fill (visual) with a round attic window on the front.
	var prism := PrismMesh.new()
	prism.size = Vector3(width, rise, depth)
	var gable := GB.add_mesh(self, prism, Vector3(0, wall_height + rise * 0.5, 0), Vector3.ZERO, GB.mat(wall_color))
	_cut_flue(gable)
	GB.cylinder(self, 0.55, 0.55, 0.15, Vector3(0, wall_height + rise * 0.4, depth * 0.5 + 0.05), trim_color, Vector3(90, 0, 0))
	GB.cylinder(self, 0.4, 0.4, 0.2, Vector3(0, wall_height + rise * 0.4, depth * 0.5 + 0.07), WARM, Vector3(90, 0, 0), 1.3)
	_chimney(chimney_base, chimney_height, -1.0)
	# Lights: green chase along the ridge pad, red along eaves and gable edges.
	var hp := ridge_pad_width * 0.5
	var y := landing_top + 0.07
	_lights([Vector3(-hp, y, hd), Vector3(-hp, y, -hd)], GREEN, true)
	_lights([Vector3(hp, y, hd), Vector3(hp, y, -hd)], GREEN, true)
	_lights([Vector3(-hp, y, hd), Vector3(hp, y, hd)], GREEN)
	_lights([Vector3(-hp, y, -hd), Vector3(hp, y, -hd)], GREEN)
	var ex := width * 0.5 + 0.05
	var ey := wall_height + 0.08
	for side: float in [-1.0, 1.0]:
		_lights([Vector3(side * ex, ey, hd), Vector3(side * ex, ey, -hd)], RED)
		for z in [hd, -hd]:
			_lights([Vector3(side * ex, ey, z), Vector3(side * hp, y - 0.05, z)], RED)
	GB.omni(self, Vector3(0, landing_top + 0.6, hd), GREEN, 1.4, 6.0)
	GB.omni(self, Vector3(0, landing_top + 0.6, -hd), GREEN, 1.4, 6.0)
	GB.omni(self, Vector3(-ex, ey, 0), RED, 1.2, 6.0)
	GB.omni(self, Vector3(ex, ey, 0), RED, 1.2, 6.0)
	_add_sign("STEEP GABLE\nland on the ridge pad", landing_top + 4.5, Color(1.0, 0.55, 0.45))


func _build_slick() -> void:
	landing_top = wall_height + 0.3
	var wet := GB.patchy(roof_color, roof_color.lightened(0.35), 0.45, 0.25, 1.4)
	var slab := _static_box(Vector3(width + 0.4, 0.3, depth + 0.4), Transform3D(Basis(), Vector3(0, wall_height + 0.15, 0)), roof_color, slick_friction, "roof", "Rain-slick roof", wet)
	_cut_flue(_mesh_of(slab))
	_fascia(width + 0.4, depth + 0.4, landing_top)
	# Puddles (visual): glossy toon discs that catch the moon and the blue lights.
	for i in 6:
		var r := _rng.randf_range(0.6, 1.5)
		var p := GB.cylinder(self, r, r, 0.02, Vector3(_rng.randf_range(-4, 4), landing_top + 0.01, _rng.randf_range(-3.5, 3.5)), Color(0.2, 0.45, 0.85), Vector3.ZERO, 0.15, 24)
		p.material_override = GB.mat(Color(0.2, 0.45, 0.85), 0.15, 0.4, 3.0)
	_outline_rect(width + 0.3, depth + 0.3, landing_top + 0.07, BLUE)
	_chimney(chimney_base, chimney_height, -1.0)
	_annex(1.0, wall_height * 0.55)
	for p in [Vector3(-1, 0, 1), Vector3(1, 0, -1)]:
		GB.omni(self, Vector3(p.x * width * 0.5, landing_top + 0.6, p.z * depth * 0.5), BLUE, 1.8, 7.0)
	_add_sign("RAIN-SLICK\nlow grip, stop early", landing_top + 5.0, Color(0.45, 0.7, 1.0))


## Elf-side chimney collision (layer 4, which the elf, its camera spring and the rope gear use):
## - the roof again, for the elf, with the flue column cut out (the sleigh's roof is untouched);
## - the flue through the house: the 250 mm liner (straight, then the 30-degree offset) and the
##   corbelled smoke chamber as brick walls round the open flue, the smoke shelf, and the flue
##   column cut out of every interior collider it crosses (ceilings, floors, the breast), so the
##   flue is genuinely open from the cap down to the throat over the firebox.
## The stack above the roof is already on layer 4 (see _chimney).
func _elf_chimney_collision() -> void:
	if break_chimney:
		return
	var fs := flue_size
	var hf := fs * 0.5
	var body := StaticBody3D.new()
	body.name = "FlueCollision"
	body.collision_layer = Interior.INTERIOR_LAYER
	body.collision_mask = 0
	body.set_meta("surface_name", "Chimney")
	body.add_to_group("chimney_collision")
	add_child(body)
	# roof for the elf
	var roof_c := chimney_base.y
	if roof_type == 1:
		roof_c = chimney_base.y + chimney_below - chimney_outer * 0.5 * tan(deg_to_rad(steep_angle_deg))
	var roof_hole := AABB(Vector3(chimney_base.x - hf, roof_c - 0.4, chimney_base.z - hf), Vector3(fs, 0.8, fs))
	for r in get_children():
		if not (r is StaticBody3D and (r as Node).is_in_group("roof")):
			continue
		var rb := r as StaticBody3D
		var eb := StaticBody3D.new()
		eb.name = "%sElf" % rb.name
		eb.transform = rb.transform
		eb.collision_layer = Interior.INTERIOR_LAYER
		eb.collision_mask = 0
		eb.physics_material_override = rb.physics_material_override
		eb.set_meta("surface_name", rb.get_meta("surface_name", "Roof"))
		eb.add_to_group("elf_roof")
		for c in rb.get_children():
			if c is CollisionShape3D:
				var nc := CollisionShape3D.new()
				nc.shape = (c as CollisionShape3D).shape.duplicate()
				nc.transform = (c as CollisionShape3D).transform
				eb.add_child(nc)
		add_child(eb)
		Carve.carve(self, eb, roof_hole)
	if flue_info.is_empty():
		return
	var it_body: Node = interior.get("_body") if interior else null
	var t := 0.07  # brick round the liner
	var top: float = (flue_info.liner_top as Vector3).y + 0.06
	var lc: Vector3 = flue_info.liner_bottom
	var ct: Vector3 = flue_info.chamber_top
	var kink_y: float = flue_info.kink_y
	var liner_y: float = flue_info.liner_y
	# straight liner from the kink up into the stack
	var r_top := Rect2(lc.x - hf, lc.z - hf, fs, fs)
	Carve.tube(body, r_top, kink_y, top, t)
	if it_body:
		Carve.carve(self, it_body, AABB(Vector3(r_top.position.x, kink_y, r_top.position.y), Vector3(fs, top - kink_y + 0.5, fs)))
	# the offset, in thin slices
	if kink_y > liner_y + 0.001:
		var n := maxi(2, int(ceil((kink_y - liner_y) / 0.04)))
		for k in n:
			var y0 := lerpf(liner_y, kink_y, float(k) / n)
			var y1 := lerpf(liner_y, kink_y, float(k + 1) / n)
			var cc := Vector3(ct.x, 0, ct.z).lerp(Vector3(lc.x, 0, lc.z), (float(k) + 0.5) / n)
			var r := Rect2(cc.x - hf, cc.z - hf, fs, fs)
			Carve.tube(body, r, y0, y1 + 0.01, t)
			if it_body:
				Carve.carve(self, it_body, AABB(Vector3(r.position.x, y0, r.position.y), Vector3(fs, y1 - y0, fs)))
	# the smoke chamber: corbelled courses from the throat slot up to the liner
	var tw: float = flue_info.tw
	var bz0: float = flue_info.bz0
	var bz1: float = flue_info.bz1
	var zc: float = flue_info.zc
	var throat_y: float = flue_info.throat_y
	var fpx: float = (flue_info.throat as Vector3).x
	var fi_f: float = (flue_info.firebox as Vector3).y - 0.05  # the living room floor
	var courses := 8
	var ch := float(flue_info.ch_h) / courses
	var r0 := Rect2(fpx - tw * 0.5, bz0, tw, bz1 - bz0)
	var r1 := Rect2(ct.x - hf, ct.z - hf, fs, fs)
	for k in courses:
		var kk := float(k) / float(courses - 1)
		var r := Rect2(r0.position.lerp(r1.position, kk), r0.size.lerp(r1.size, kk))
		var y0 := throat_y + k * ch
		# room side: behind the lintel / front breast (to 1.3 m over the hearth) the wall can be
		# full thickness; higher up it stops at the chimney breast's face (zc + 0.145)
		var tfr := 0.09 if y0 + ch < float(fi_f) + 1.3 else clampf(zc + 0.145 - r.end.y, 0.0, 0.09)
		Carve.tube(body, r, y0, y0 + ch + 0.005, 0.09, tfr)
		if it_body:
			Carve.carve(self, it_body, AABB(Vector3(r.position.x, y0, r.position.y), Vector3(r.size.x, ch, r.size.y)))
		# the corbel's ledge (the course above steps in): a lid over the part this course sticks out
		if k < courses - 1:
			var kn := float(k + 1) / float(courses - 1)
			var rn := Rect2(r0.position.lerp(r1.position, kn), r0.size.lerp(r1.size, kn))
			var y := y0 + ch
			for strip: Rect2 in [Rect2(r.position.x, r.position.y, r.size.x, rn.position.y - r.position.y),
					Rect2(r.position.x, rn.end.y, r.size.x, r.end.y - rn.end.y),
					Rect2(r.position.x, rn.position.y, rn.position.x - r.position.x, rn.size.y),
					Rect2(rn.end.x, rn.position.y, r.end.x - rn.end.x, rn.size.y)]:
				if strip.size.x > 0.003 and strip.size.y > 0.003:
					Carve.box(body, Vector3(strip.size.x, 0.02, strip.size.y), Vector3(strip.get_center().x, y + 0.01, strip.get_center().y))
	# smoke shelf behind the throat slot
	var shelf := Carve.box(body, Vector3(tw, 0.04, zc - 0.07 - bz0), Vector3(fpx, throat_y - 0.02, (bz0 + zc - 0.07) * 0.5))
	shelf.set_meta("visible_solid", true)  # it has its own mesh (the sooty shelf), not an invisible wall
