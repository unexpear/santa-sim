extends Node3D
## Visual-only reindeer team (4 pairs + a red-nosed lead) on harness lines in front of the sleigh.
## There are NO physics bodies here: the team can hang past roof edges or over open air and can never
## touch a roof, cause a crash, or affect landing scoring. It follows the sleigh and animates from the
## visual state machine in sleigh_visuals.gd (parked / taking off / flying / approach / touchdown /
## settling). Read-only raycasts find a surface under each reindeer so it can stand on it; where there
## is none (past a roof edge) it hovers and paddles instead.

const GB := preload("res://scripts/greybox.gd")
const Spring := preload("res://scripts/spring.gd")
const FX := preload("res://scripts/fx.gd")
const SV := preload("res://scripts/sleigh_visuals.gd")
const REINDEER_MODEL := preload("res://assets/models/reindeer.glb")
const BEAM_SHADER := preload("res://shaders/beam.gdshader")
const HARNESS := Color(0.2, 0.1, 0.05)
const FEET := 0.69  ## Hoof bottom below the reindeer's origin.
const LEG_NAMES: Array[String] = ["LegFL", "LegFR", "LegBL", "LegBR"]

@export var sleigh: Node3D
@export_group("Formation")
@export var pairs := 4
@export var pair_spacing := 2.5
@export var pair_half_gap := 0.8  ## Sideways offset of each reindeer from the centre line.
@export var gap_to_sleigh := 2.6  ## Metres from the sleigh's centre forward to the rear pair.
@export var follow_sharpness := 9.0
@export var turn_sharpness := 6.0
@export_flags_3d_physics var ground_mask := 3  ## What reindeer can stand on (1 = world, 2 = visual-only runway).

@export_group("Take-off")
@export var crouch_time := 0.18
@export var crouch_amount := 0.16
@export var run_time := 0.32  ## Ground gallop before the lead pair leaps.
@export var leap_stagger := 0.13  ## Delay between pairs leaping, lead first.
@export var leap_time := 0.42
@export var leap_height := 0.8
@export var leap_stretch_kick := 2.6
@export var head_toss_kick := 4.0
@export var swoop_pitch_kick := 2.6
@export var bell_kick := 6.0
@export var takeoff_reach := 4.0  ## Extra ray reach during the run so they keep running as the sleigh rises.

@export_group("Landing")
@export var flare_pitch := 0.3  ## Each reindeer's body pitch-up while braced on approach.
@export var team_flare_pitch := 0.07  ## Whole-team pitch-up on approach (small: the lead is ~11 m out).
@export var land_stagger := 0.08  ## Delay between pairs touching down, rear pair first.
@export var land_squash_kick := 2.2
@export var land_squash_per_mps := 0.5
@export var stumble_pitch_kick := -3.2
@export var skid_distance := 0.5
@export var stand_reach := 1.3  ## A surface this far below the hooves counts as "standing".

@export_group("Gaits")
@export var run_rate := 13.0
@export var fly_rate := 8.5
@export var paddle_rate := 3.0
@export var blend_speed := 7.0
@export var plant_speed := 6.0

@export_group("Idle")
@export var idle_event_min := 1.0
@export var idle_event_max := 3.2

@export_group("Lead nose")
@export var nose_scale := 1.8
@export var nose_glow := 7.0
@export var nose_pulse := 0.35

@export_group("Headlight")  ## Rudolph's nose as a single forward headlight (visual only).
@export var headlight_color := Color(1.0, 0.42, 0.32)
@export var headlight_energy := 20.0
@export var headlight_range := 34.0
@export_range(5.0, 60.0) var headlight_cone_deg := 20.0
@export_range(0.0, 1.0) var headlight_softness := 0.35  ## Cone edge falloff (higher = softer edge).
@export_range(-10.0, 60.0) var headlight_pitch_down_deg := 32.0
@export_range(0.0, 2.0) var beam_visibility := 0.9  ## 0 hides the visible cone in the air.
@export var beam_length := 24.0
@export var headlight_shadows := true
@export_range(0.0, 2.0) var headlight_falloff := 0.25  ## Distance falloff exponent (lower = reaches further at full strength).
@export var headlight_pulse := 0.12  ## How much the beam follows the nose pulse.
@export_range(0.0, 1.0) var lead_head_steadiness := 0.92  ## 1 = lead's head held dead level (no bob/toss); 0 = animates like the others.
@export var beam_smoothing := 4.0  ## How quickly the stabilised headlight re-aims to the flight heading (1/s; lower = smoother).
@export_range(0.0, 1.0) var beam_follow_climb := 0.5  ## Fraction of the sleigh's climb/dive the beam follows.
@export var nose_glow_energy := 0.0  ## Optional tiny muzzle glow (0 = off; no red pool around the team).


class Deer:
	var anchor: Node3D
	var pose: Node3D
	var squash: Node3D
	var legs: Array[Node3D] = []
	var head: Node3D
	var ear_l: Node3D
	var ear_r: Node3D
	var tail: Node3D
	var bells: Array[Node3D] = []
	var puff: GPUParticles3D
	var lead := false
	var order_front := 0
	var order_rear := 0
	var phase := 0.0
	var plant := 0.0
	var has_ground := false
	var ground_offset := 0.0
	var w := {"stand": 1.0, "run": 0.0, "fly": 0.0, "paddle": 0.0, "brace": 0.0}
	var squash_s = Spring.new()
	var pitch_s = Spring.new()
	var head_s = Spring.new()
	var bell_s = Spring.new()
	var skid_s = Spring.new()
	var leap_at := -1.0
	var leapt := true
	var land_at := -1.0
	var landed := true
	var impact := 0.0
	var hop := 1.0
	var idle_next := 0.0
	var idle_kind := ""
	var idle_t := 9.0
	var idle_leg := 0
	var snap := true


var state: int = SV.VisState.PARKED
var _deer: Array[Deer] = []
var _harness: Array = [[], []]
var _vis: Node
var _t := 0.0
var _takeoff_t0 := -10.0
var _rng := RandomNumberGenerator.new()
var _nose_mat: ShaderMaterial
var _nose_light: OmniLight3D
var _headlight: SpotLight3D
var _headlight_mount: Node3D
var _nose: Node3D
var _beam_pitch := 0.0
var _beam_mat: ShaderMaterial


func _ready() -> void:
	top_level = true
	_rng.seed = 2412
	for i in pairs:
		for side in [-1.0, 1.0]:
			var d := _add_reindeer(Vector3(side * pair_half_gap, 0, -1.0 - i * pair_spacing), false)
			d.order_front = pairs - i
			d.order_rear = i
	var lead := _add_reindeer(Vector3(0, 0, -1.0 - pairs * pair_spacing), true)
	lead.order_front = 0
	lead.order_rear = pairs
	for side_i in 2:
		for k in pairs + 1:
			var seg := GB.box(self, Vector3(0.04, 0.04, 1.0), Vector3.ZERO, HARNESS)
			seg.top_level = true
			seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_harness[side_i].append(seg)


func _add_reindeer(pos: Vector3, lead: bool) -> Deer:
	# anchor (formation slot) > pose (planting, hops, skids, pitch) > squash (at the hooves) > model
	var d := Deer.new()
	d.lead = lead
	d.phase = _rng.randf_range(0.0, TAU)
	d.anchor = Node3D.new()
	d.anchor.position = pos
	add_child(d.anchor)
	d.pose = Node3D.new()
	d.anchor.add_child(d.pose)
	d.squash = Node3D.new()
	d.squash.position = Vector3(0, -FEET, 0)
	d.pose.add_child(d.squash)
	var r := REINDEER_MODEL.instantiate() as Node3D
	r.position = Vector3(0, FEET, 0)
	d.squash.add_child(r)
	var overrides := {}
	if lead:
		_nose_mat = GB.mat(Color(1.0, 0.06, 0.04), nose_glow).duplicate() as ShaderMaterial
		overrides["Nose"] = _nose_mat
	GB.toonify(r, overrides)
	for leg_name in LEG_NAMES:
		var leg := r.find_child(leg_name, true, false) as Node3D
		if leg == null:
			push_warning("reindeer.glb is missing " + leg_name)
			leg = Node3D.new()
		d.legs.append(leg)
	d.head = _find(r, "Head")
	d.ear_l = _find(r, "EarL")
	d.ear_r = _find(r, "EarR")
	d.tail = _find(r, "Tail")
	for n in r.find_children("*Bell*", "Node3D", true, false):
		d.bells.append(n as Node3D)
	if lead:
		var nose := r.find_child("DeerNose", true, false) as Node3D
		if nose == null:
			push_warning("reindeer.glb is missing DeerNose")
		else:
			nose.scale *= nose_scale
			if nose_glow_energy > 0.0:
				_nose_light = GB.omni(nose, Vector3(0, 0, -0.05), Color(1.0, 0.12, 0.08), nose_glow_energy, 0.9)
				_nose_light.shadow_enabled = false
			_nose = nose
			if nose is GeometryInstance3D:
				(nose as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_add_headlight()
	d.puff = FX.dust_kick()  # painterly sprite dust
	d.puff.amount = 10
	var ppm := d.puff.process_material as ParticleProcessMaterial
	ppm.emission_box_extents = Vector3(0.25, 0.02, 0.4)
	ppm.scale_min *= 0.55
	ppm.scale_max *= 0.55
	d.puff.lifetime = 1.0
	d.puff.position = Vector3(0, 0.05, 0)
	d.squash.add_child(d.puff)
	d.idle_next = _rng.randf_range(0.5, 2.5)
	_deer.append(d)
	return d


func _add_headlight() -> void:
	# Stabilised mount: rides at the lead's nose but aims along the smoothed flight heading
	# (set in _update_headlight), so gallop bob and head motion never make the beam jitter.
	var mount := Node3D.new()
	mount.name = "Headlight"
	mount.top_level = true
	add_child(mount)
	_headlight_mount = mount
	var aim := Node3D.new()  # pitch-down offset lives here
	aim.rotation_degrees = Vector3(-headlight_pitch_down_deg, 0, 0)
	mount.add_child(aim)
	mount = aim
	_headlight = SpotLight3D.new()
	_headlight.light_color = headlight_color
	_headlight.light_energy = headlight_energy
	_headlight.spot_range = headlight_range
	_headlight.spot_angle = headlight_cone_deg
	_headlight.spot_angle_attenuation = lerpf(0.4, 3.0, headlight_softness)
	_headlight.spot_attenuation = headlight_falloff
	_headlight.shadow_enabled = headlight_shadows
	_headlight.shadow_bias = 0.05
	mount.add_child(_headlight)
	if beam_visibility <= 0.0:
		return
	var cone := CylinderMesh.new()
	cone.top_radius = tan(deg_to_rad(headlight_cone_deg)) * beam_length * 0.8
	cone.bottom_radius = 0.06
	cone.height = beam_length
	cone.radial_segments = 24
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = BEAM_SHADER
	_beam_mat.set_shader_parameter("color", headlight_color)
	_beam_mat.set_shader_parameter("intensity", beam_visibility)
	_beam_mat.set_shader_parameter("far_radius", cone.top_radius)
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	beam.mesh = cone
	beam.material_override = _beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.rotation_degrees = Vector3(-90, 0, 0)  # cone axis +Y -> -Z (forward)
	beam.position = Vector3(0, 0, -beam_length * 0.5)
	mount.add_child(beam)


func _find(root: Node, n: String) -> Node3D:
	var node := root.find_child(n, true, false) as Node3D
	if node == null:
		push_warning("reindeer.glb is missing " + n)
		node = Node3D.new()
	return node


# --- events from the sleigh's visual state machine --------------------------------------------------

func _connect_visuals() -> void:
	_vis = sleigh.get_node_or_null("Visual")
	if _vis == null:
		return
	_vis.connect("takeoff_started", _on_takeoff)
	_vis.connect("touched_down", _on_touchdown)
	_vis.connect("snapped", _on_snapped)


func _on_takeoff() -> void:
	_takeoff_t0 = _t
	for d in _deer:
		d.leap_at = _t + crouch_time + run_time + d.order_front * leap_stagger
		d.leapt = false
		d.landed = false
		d.land_at = -1.0


func _on_touchdown(impact: float) -> void:
	for d in _deer:
		d.land_at = _t + d.order_rear * land_stagger
		d.landed = false
		d.leapt = true
		d.impact = impact


func _on_snapped() -> void:
	for d in _deer:
		d.leapt = true
		d.landed = true
		d.land_at = -1.0
		d.snap = true
		for sp in [d.squash_s, d.pitch_s, d.head_s, d.bell_s, d.skid_s]:
			sp.reset()


# --- per-frame --------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if sleigh == null:
		return
	if _vis == null:
		_connect_visuals()
	_t += delta
	state = int(_vis.get("state")) if _vis != null else SV.VisState.FLYING
	_follow(delta)
	var space := get_world_3d().direct_space_state
	for d in _deer:
		_update_deer(d, delta, space)
	_update_harness()
	_update_headlight(delta)
	if _nose_mat != null:
		var calm := state == SV.VisState.PARKED or state == SV.VisState.SETTLING
		var pulse := 1.0 + sin(_t * (3.0 if calm else 6.0)) * nose_pulse
		_nose_mat.set_shader_parameter("emission_energy", nose_glow * pulse)
		if _nose_light != null:
			_nose_light.light_energy = nose_glow_energy * pulse
		if _headlight != null:
			var hp := 1.0 + (pulse - 1.0) * headlight_pulse / maxf(nose_pulse, 0.001)
			_headlight.light_energy = headlight_energy * hp
			if _beam_mat != null:
				_beam_mat.set_shader_parameter("intensity", beam_visibility * hp)


func _follow(delta: float) -> void:
	var sx := sleigh.global_transform
	var fwd := -sx.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = -global_transform.basis.z
		fwd.y = 0.0
	fwd = fwd.normalized()
	var target_basis := Basis.looking_at(fwd, Vector3.UP)
	var target_pos := sx.origin + target_basis * Vector3(0, 0.35, -gap_to_sleigh)
	var vel := Vector3.ZERO
	if sleigh is RigidBody3D:
		vel = (sleigh as RigidBody3D).linear_velocity
	var pitch := clampf(vel.y * 0.04, -0.35, 0.35)
	if state == SV.VisState.APPROACH:
		pitch = team_flare_pitch  # flare: the whole team tips up a little to brake
	target_basis = target_basis * Basis(Vector3.RIGHT, pitch)
	if global_position.distance_to(target_pos) > 15.0:
		global_transform = Transform3D(target_basis, target_pos)
		reset_physics_interpolation()
		for d in _deer:
			d.snap = true
	else:
		var a := 1.0 - exp(-follow_sharpness * delta)
		var r := 1.0 - exp(-turn_sharpness * delta)
		var new_basis := global_transform.basis.orthonormalized().slerp(target_basis, r).orthonormalized()
		global_transform = Transform3D(new_basis, global_position.lerp(target_pos, a))


func _update_deer(d: Deer, dt: float, space: PhysicsDirectSpaceState3D) -> void:
	var taking_off := state == SV.VisState.TAKING_OFF and _t < d.leap_at
	var ground_state := state == SV.VisState.PARKED or state == SV.VisState.SETTLING or state == SV.VisState.TOUCHDOWN

	# Read-only ray: is there something to stand on under this reindeer?
	var ap := d.anchor.global_position
	var reach := stand_reach + (takeoff_reach if taking_off else 0.0)
	var q := PhysicsRayQueryParameters3D.create(ap + Vector3.UP * 0.8, ap + Vector3.DOWN * (FEET + reach))
	q.collision_mask = ground_mask
	if sleigh is CollisionObject3D:
		q.exclude = [(sleigh as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	d.has_ground = not hit.is_empty()
	if d.has_ground:
		d.ground_offset = minf((hit.position as Vector3).y + FEET - ap.y, 0.6)

	# Timeline events
	if not d.leapt and _t >= d.leap_at:
		d.leapt = true
		d.hop = 0.0 if d.plant > 0.5 else 1.0
		d.squash_s.kick(leap_stretch_kick)
		d.head_s.kick(head_toss_kick * ((1.0 - lead_head_steadiness) if d.lead else 1.0))
		d.pitch_s.kick(swoop_pitch_kick)
		d.bell_s.kick(bell_kick)
		if d.plant > 0.5:
			_puff(d, 8)
	if not d.landed and d.land_at >= 0.0 and _t >= d.land_at:
		d.landed = true
		if d.has_ground:
			var k := clampf(d.impact / 3.0, 0.3, 1.3)
			d.squash_s.kick(-(land_squash_kick + d.impact * land_squash_per_mps))
			d.pitch_s.kick(stumble_pitch_kick * k)
			d.skid_s.reset(-skid_distance * k)
			d.bell_s.kick(bell_kick)
			_puff(d, int(8 + d.impact * 3.0))
		else:
			d.bell_s.kick(bell_kick * 0.5)

	# Pick the target gait
	var tw := {"stand": 0.0, "run": 0.0, "fly": 0.0, "paddle": 0.0, "brace": 0.0}
	var on_ground := false
	var sq_target := 0.0
	if taking_off:
		on_ground = d.has_ground
		if _t < _takeoff_t0 + crouch_time:
			tw.stand = 1.0
			sq_target = -crouch_amount
		elif d.has_ground:
			tw.run = 1.0
		else:
			tw.paddle = 1.0
	elif ground_state and d.landed:
		if d.has_ground:
			on_ground = true
			if state == SV.VisState.TOUCHDOWN or (d.land_at >= 0.0 and _t - d.land_at < 0.45):
				tw.brace = 0.65
				tw.stand = 0.35
			else:
				tw.stand = 1.0
		else:
			tw.paddle = 1.0
	elif state == SV.VisState.APPROACH or (ground_state and not d.landed):
		tw.brace = 1.0
	else:
		tw.fly = 1.0
	var bl := 1.0 - exp(-blend_speed * dt)
	for key in d.w:
		d.w[key] = lerpf(d.w[key], tw[key], 1.0 if d.snap else bl)
	var plant_target := 1.0 if on_ground else 0.0
	d.plant = plant_target if d.snap else move_toward(d.plant, plant_target, plant_speed * dt)
	d.snap = false

	# Idle fidgets (shuffle / ear flick / tail wag / head bob) when standing or hovering.
	d.idle_t += dt
	if float(d.w.stand) + float(d.w.paddle) > 0.6 and _t > d.idle_next:
		var kinds: Array[String] = ["shuffle", "ear", "tail", "head", "ear", "tail"]
		d.idle_kind = kinds[_rng.randi() % kinds.size()]
		d.idle_leg = _rng.randi() % 4
		d.idle_t = 0.0
		d.idle_next = _t + _rng.randf_range(idle_event_min, idle_event_max)
	var idle_w := float(d.w.stand) + float(d.w.paddle) * 0.6
	var shuffle := 0.0
	var ear_flick := 0.0
	var tail_wag := 0.0
	var head_bob := 0.0
	match d.idle_kind:
		"shuffle":
			shuffle = sin(PI * clampf(d.idle_t / 0.45, 0.0, 1.0)) * 0.55
		"ear":
			ear_flick = sin(d.idle_t * 32.0) * 0.45 * maxf(0.0, 1.0 - d.idle_t / 0.4)
		"tail":
			tail_wag = sin(d.idle_t * 22.0) * 0.6 * maxf(0.0, 1.0 - d.idle_t / 0.9)
		"head":
			head_bob = -sin(PI * clampf(d.idle_t / 0.9, 0.0, 1.0)) * 0.35

	var t := _t
	var w: Dictionary = d.w
	# Body: plant onto the surface, hop arc, gait bob, skid slide, pitch, squash.
	var hop_y := 0.0
	if d.hop < 1.0:
		d.hop = minf(d.hop + dt / leap_time, 1.0)
		hop_y = sin(PI * d.hop) * leap_height
	var bob := 0.0
	bob += float(w.fly) * sin(t * fly_rate + d.phase) * 0.08
	bob += float(w.run) * absf(sin(t * run_rate * 0.5 + d.phase)) * 0.1
	bob += float(w.paddle) * sin(t * paddle_rate * 0.5 + d.phase) * 0.07
	bob += float(w.stand) * sin(t * 2.0 + d.phase) * 0.008
	if d.idle_kind == "shuffle":
		bob += shuffle * 0.04 * float(w.stand)
	var skid: float = d.skid_s.step(0.0, 40.0, 9.0, dt)
	d.pose.position = Vector3(0, d.ground_offset * d.plant + bob + hop_y, skid)
	var pitch: float = d.pitch_s.step(0.0, 90.0, 8.0, dt)
	pitch += float(w.brace) * flare_pitch * 0.6 + float(w.fly) * 0.06 - float(w.run) * 0.1
	pitch += float(w.fly) * sin(t * fly_rate + d.phase - 0.6) * 0.05
	d.pose.rotation.x = pitch
	var s := clampf(d.squash_s.step(sq_target, 240.0, 10.0, dt), -0.3, 0.3)
	d.squash.scale = Vector3(1.0 - s * 0.5, 1.0 + s, 1.0 - s * 0.5)

	# Legs (rotation about the hip; + swings the hoof forward)
	for i in 4:
		var front := i < 2
		var lp := d.phase + (0.0 if front else PI) + (0.0 if i % 2 == 0 else 0.6)
		var a := 0.0
		a += float(w.run) * sin(t * run_rate + lp) * 0.75
		a += float(w.fly) * ((0.55 if front else -0.6) + 0.5 * sin(t * fly_rate + lp))
		a += float(w.paddle) * sin(t * paddle_rate + lp + i) * 0.4
		a += float(w.brace) * (0.95 if front else 0.3)
		if i == d.idle_leg:
			a += float(w.stand) * shuffle
		d.legs[i].rotation.x = a

	# Head: toss on leap, bob in the gallop, up and back when bracing, the odd graze-bob when idle.
	var head_target := float(w.brace) * 0.4
	head_target += float(w.fly) * sin(t * fly_rate + d.phase + 0.8) * 0.13
	head_target += float(w.run) * sin(t * run_rate + d.phase + 0.5) * 0.12
	head_target += idle_w * head_bob
	if d.lead:
		# Steady lead: damp all head motion and counter the body's pitch so the head stays level.
		head_target *= 1.0 - lead_head_steadiness
		head_target -= d.pose.rotation.x * lead_head_steadiness
	d.head.rotation.x = clampf(d.head_s.step(head_target, 120.0, 10.0, dt), -0.6, 0.8)
	var ears_back := float(w.brace) * 0.85 + float(w.fly) * 0.45 + float(w.run) * 0.3
	ears_back += float(w.fly) * sin(t * fly_rate * 1.5 + d.phase) * 0.12
	d.ear_l.rotation = Vector3(ears_back, 0.0, ear_flick * idle_w)
	d.ear_r.rotation = Vector3(ears_back, 0.0, -ear_flick * idle_w * 0.6)
	var wag := float(w.fly) * sin(t * 16.0 + d.phase) * 0.35 + float(w.run) * sin(t * 13.0) * 0.3
	wag += idle_w * tail_wag + float(w.brace) * 0.0
	d.tail.rotation = Vector3(float(w.fly) * -0.4 + float(w.brace) * 0.5, wag, 0.0)

	# Bells jingle: a decaying wobble from events plus a constant shake while galloping.
	var jingle: float = d.bell_s.step(0.0, 25.0, 2.5, dt)
	var shake := (float(w.run) + float(w.fly)) * sin(t * 24.0 + d.phase) * 0.3
	for b in d.bells:
		b.rotation.z = clampf(jingle * 0.12 + shake, -0.8, 0.8)
		b.rotation.x = clampf(shake * 0.6, -0.5, 0.5)


func _update_headlight(dt: float) -> void:
	if _headlight_mount == null or _nose == null:
		return
	# Flat heading of the team (already smoothed), plus a damped share of the sleigh's climb angle.
	var fwd := -global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return
	fwd = fwd.normalized()
	var vel := Vector3.ZERO
	if sleigh is RigidBody3D:
		vel = (sleigh as RigidBody3D).linear_velocity
	var climb := 0.0
	if Vector2(vel.x, vel.z).length() > 1.0:
		climb = clampf(atan2(vel.y, Vector2(vel.x, vel.z).length()), -0.5, 0.5) * beam_follow_climb
	var k := 1.0 - exp(-beam_smoothing * dt)
	_beam_pitch = lerpf(_beam_pitch, climb, k)
	var target := Basis.looking_at(fwd, Vector3.UP) * Basis(Vector3.RIGHT, _beam_pitch)
	var cur := _headlight_mount.global_basis.orthonormalized()
	var b := cur.slerp(target, k).orthonormalized() if cur.determinant() > 0.5 else target
	# Ride exactly with the nose horizontally; smooth only the vertical gallop bob.
	var pos := _nose.global_position + fwd * 0.3
	var y := lerpf(_headlight_mount.global_position.y, pos.y, 1.0 - exp(-beam_smoothing * 2.0 * dt))
	if absf(y - pos.y) > 1.5:
		y = pos.y  # teleports / resets: snap
	_headlight_mount.global_transform = Transform3D(b, Vector3(pos.x, y, pos.z))


func _puff(d: Deer, amount: int) -> void:
	d.puff.amount = clampi(amount, 4, 24)
	d.puff.restart()
	d.puff.emitting = true


func _attach(d: Deer, local_x: float) -> Vector3:
	return d.squash.global_transform * Vector3(local_x, FEET, -0.05)


func _update_harness() -> void:
	# Harness lines run sleigh nose -> each reindeer on that side -> lead, following the animated bodies.
	var sx := sleigh.global_transform
	var lead := _deer[_deer.size() - 1]
	for side_i in 2:
		var side := -1.0 if side_i == 0 else 1.0
		var pts: Array[Vector3] = [sx * Vector3(side * 0.35, 0.76, -1.3)]
		for p in pairs:
			pts.append(_attach(_deer[p * 2 + side_i], -side * 0.28))
		pts.append(_attach(lead, side * 0.26))
		for k in pts.size() - 1:
			_stretch(_harness[side_i][k], pts[k], pts[k + 1])


func _stretch(seg: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var dv := b - a
	var length := dv.length()
	if length < 0.05:
		seg.visible = false
		return
	seg.visible = true
	var dir := dv / length
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	seg.global_transform = Transform3D(Basis.looking_at(dir, up) * Basis.from_scale(Vector3(1, 1, length)), (a + b) * 0.5)
