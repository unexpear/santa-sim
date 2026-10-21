extends Node3D
## VISUAL ONLY: the sleigh + Santa models, their squash/stretch, tilt, swinging lanterns, bouncing sack,
## leaning/breathing Santa and runner dust, plus the shared visual flight state machine that the
## reindeer team reads. It only READS the sleigh body (grounded, velocity, inputs) and casts its own
## read-only rays. It never writes to physics, so collision, landing and scoring are untouched.

signal takeoff_started
signal touched_down(impact: float)
signal snapped

enum VisState { PARKED, TAKING_OFF, FLYING, APPROACH, TOUCHDOWN, SETTLING }
const STATE_NAMES: Array[String] = ["parked", "taking off", "flying", "landing approach", "touchdown", "settling"]

const GB := preload("res://scripts/greybox.gd")
const Spring := preload("res://scripts/spring.gd")
const SLEIGH_MODEL := preload("res://assets/models/sleigh.glb")
const SANTA_MODEL := preload("res://assets/models/santa.glb")
const RUNNER_Y := -0.66  ## Bottom of the runners in sleigh space (squash pivot).

@export_group("State machine")
@export var approach_height := 4.5  ## Runners this close above a surface while sinking = landing approach.
@export var approach_min_sink := 0.4  ## m/s downward needed to count as approaching.
@export var takeoff_duration := 1.7  ## Seconds the take-off sequence owns the visuals.
@export var takeoff_air_delay := 0.06  ## Airborne this long from parked = take-off (if no lift input seen).
@export var touchdown_time := 0.5
@export var settle_time := 1.0
@export var quiet_ground_time := 0.25  ## Grounded this long without a touchdown event (resets) = settling.

@export_group("Take-off")
@export var anticipation_time := 0.14  ## Squash before the lurch.
@export var takeoff_squash := 0.2
@export var takeoff_stretch_kick := 3.0
@export var takeoff_tilt_kick := 2.4  ## Nose-up lurch (rad/s) when the reins go taut.
@export var takeoff_santa_kick := 3.0  ## Santa rocks back.

@export_group("Touchdown")
@export var touchdown_squash_per_mps := 1.0
@export var max_squash_kick := 5.0
@export var touchdown_pitch_per_mps := 0.55
@export var touchdown_santa_per_mps := 0.9
@export var spark_impact := 2.0  ## m/s; harder touchdowns throw sparks too.
@export var skid_speed := 1.2  ## Runner dust while sliding faster than this.

@export_group("Springs")
@export var squash_stiffness := 260.0
@export var squash_damping := 10.0
@export var max_squash := 0.32
@export var tilt_stiffness := 110.0
@export var tilt_damping := 8.0
@export var lantern_stiffness := 45.0
@export var lantern_damping := 2.0
@export var lantern_accel_gain := 0.04
@export var sack_stiffness := 170.0
@export var sack_damping := 6.0
@export var santa_stiffness := 80.0
@export var santa_damping := 7.0
@export var santa_lean_gain := 0.022
@export var breath_amount := 0.02
@export var breath_rate := 2.3

var state: int = VisState.PARKED
var state_time := 0.0
var height_above_surface := INF
var last_impact := 0.0

var _sleigh: RigidBody3D
var _squash: Node3D
var _tilt: Node3D
var _santa_pivot: Node3D
var _lanterns: Array[Node3D] = []
var _lantern_springs: Array = []
var _sack: Node3D
var _s_squash := Spring.new()
var _s_tilt := Spring.new()
var _s_sack := Spring.new()
var _s_santa := Spring.new()
var _prev_v := Vector3.ZERO
var _accel := Vector3.ZERO
var _prev_pos := Vector3.ZERO
var _air_time := 0.0
var _ground_time := 0.0
var _last_air_vy := 0.0
var _was_grounded := true
var _stretch_pending := false
var _t := 0.0
const FX := preload("res://scripts/fx.gd")
var _dust: GPUParticles3D
var _sparks: CPUParticles3D
var _skids: Array[CPUParticles3D] = []


func state_name() -> String:
	return STATE_NAMES[state]


func _ready() -> void:
	_sleigh = get_parent() as RigidBody3D
	# Pivots: Visual > Squash (at runner bottom) > Tilt (rear-ish contact) > Inner > models.
	_squash = Node3D.new()
	_squash.name = "Squash"
	_squash.position = Vector3(0, RUNNER_Y, 0)
	add_child(_squash)
	_tilt = Node3D.new()
	_tilt.name = "Tilt"
	_tilt.position = Vector3(0, 0, 0.6)
	_squash.add_child(_tilt)
	var inner := Node3D.new()
	inner.position = Vector3(0, -RUNNER_Y, -0.6)
	_tilt.add_child(inner)
	var sl := SLEIGH_MODEL.instantiate() as Node3D
	inner.add_child(sl)
	GB.toonify(sl)
	_santa_pivot = Node3D.new()
	_santa_pivot.name = "SantaPivot"
	_santa_pivot.position = Vector3(0, 0.1, 0.05)  # his hips on the seat
	inner.add_child(_santa_pivot)
	var sa := SANTA_MODEL.instantiate() as Node3D
	sa.position = -_santa_pivot.position
	_santa_pivot.add_child(sa)
	GB.toonify(sa)
	for n: String in ["LanternL", "LanternR"]:
		var l := sl.find_child(n, true, false) as Node3D
		if l == null:
			push_warning("sleigh.glb is missing " + n)
			continue
		_lanterns.append(l)
		_lantern_springs.append(Spring.new())
		GB.omni(l, Vector3(0.02, 0.36, -0.06), Color(1.0, 0.8, 0.45), 0.8, 5.0)
	_sack = sl.find_child("Sack", true, false) as Node3D
	# Runner dust + gold sparkles (world-space particles so they stay behind as the sleigh moves).
	_dust = FX.dust_kick()  # soft painterly sprite smoke (was plain sphere puffs)
	add_child(_dust)
	_dust.position = Vector3(0, RUNNER_Y + 0.05, 0.1)
	_sparks = _particles(Color(1.0, 0.85, 0.35), 30, true, true)
	_sparks.position = Vector3(0, RUNNER_Y + 0.05, 0.4)
	_sparks.emission_box_extents = Vector3(0.75, 0.02, 1.2)
	for x in [-0.7, 0.7]:
		var sk := _particles(Color(0.92, 0.84, 0.7), 14, false, false)
		sk.position = Vector3(x, RUNNER_Y + 0.05, 1.3)
		sk.emission_box_extents = Vector3(0.06, 0.02, 0.2)
		_skids.append(sk)
	_prev_pos = _sleigh.global_position


func _particles(color: Color, amount: int, one_shot: bool, sparkle: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.one_shot = one_shot
	p.emitting = false
	p.explosiveness = 0.92 if one_shot else 0.0
	p.lifetime = 0.55 if sparkle else 0.8
	p.local_coords = false
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	if sparkle:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var mesh := SphereMesh.new()
	mesh.radius = 0.035 if sparkle else 0.13
	mesh.height = mesh.radius * 2.0
	mesh.radial_segments = 6 if sparkle else 10
	mesh.rings = 3 if sparkle else 5
	mesh.material = m
	p.mesh = mesh
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.direction = Vector3(0, 1, 0)
	p.spread = 75.0
	p.initial_velocity_min = 1.0 if sparkle else 0.6
	p.initial_velocity_max = 3.5 if sparkle else 1.8
	p.gravity = Vector3(0, -6.0, 0) if sparkle else Vector3(0, 0.4, 0)
	p.damping_min = 0.5
	p.damping_max = 1.5
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5 if not sparkle else 1.0))
	curve.add_point(Vector2(1, 1.6 if not sparkle else 0.2))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	var c0 := color
	c0.a = 0.85
	var c1 := color
	c1.a = 0.0
	g.set_color(0, c0)
	g.set_color(1, c1)
	p.color_ramp = g
	add_child(p)
	return p


func _burst_gpu(p: GPUParticles3D, amount: int) -> void:
	p.amount = clampi(amount, 6, 40)
	FX.burst(p)


func _burst(p: CPUParticles3D, amount: int) -> void:
	p.amount = maxi(amount, 4)
	p.restart()
	p.emitting = true


# --- state machine ----------------------------------------------------------------------------------

func _set_state(s: int) -> void:
	state = s
	state_time = 0.0


func _physics_process(delta: float) -> void:
	if _sleigh == null:
		return
	_t += delta
	state_time += delta
	var pos := _sleigh.global_position
	var v := _sleigh.linear_velocity
	if pos.distance_to(_prev_pos) > 4.0:
		_snap(v)
	_prev_pos = pos
	_accel = _accel.lerp((v - _prev_v) / maxf(delta, 0.001), 0.3)
	_prev_v = v
	var grounded := bool(_sleigh.get("grounded"))
	height_above_surface = _probe_height()
	var lift := Input.get_action_strength("lift")

	if grounded and not _was_grounded and _air_time > 0.2 and state != VisState.PARKED and state != VisState.SETTLING:
		_touchdown(maxf(0.0, -_last_air_vy))
	if grounded:
		_air_time = 0.0
		_ground_time += delta
	else:
		_air_time += delta
		_ground_time = 0.0
		_last_air_vy = v.y

	match state:
		VisState.PARKED, VisState.SETTLING:
			if (not grounded and _air_time > takeoff_air_delay) or (grounded and lift > 0.1):
				_begin_takeoff()
			elif state == VisState.SETTLING and state_time > settle_time and v.length() < 0.8:
				_set_state(VisState.PARKED)
		VisState.TAKING_OFF:
			if state_time > takeoff_duration:
				_set_state(VisState.SETTLING if grounded else VisState.FLYING)
		VisState.FLYING:
			if grounded and _ground_time > quiet_ground_time:
				_set_state(VisState.SETTLING)
			elif not grounded and v.y < -approach_min_sink and height_above_surface < approach_height:
				_set_state(VisState.APPROACH)
		VisState.APPROACH:
			if grounded and _ground_time > quiet_ground_time:
				_set_state(VisState.SETTLING)
			elif v.y > 0.4 or height_above_surface > approach_height * 1.6:
				_set_state(VisState.FLYING)
		VisState.TOUCHDOWN:
			if not grounded and _air_time > 0.15 and lift > 0.1:
				_begin_takeoff()
			elif state_time > touchdown_time:
				_set_state(VisState.SETTLING if grounded else VisState.FLYING)
	_was_grounded = grounded
	_animate(delta, v, grounded)


func _probe_height() -> float:
	var from := _sleigh.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 40.0)
	q.exclude = [_sleigh.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return INF
	return from.y + RUNNER_Y - (hit.position as Vector3).y


func _snap(v: Vector3) -> void:
	# Teleport / reset: drop any in-flight animation and let the state machine pick up from scratch.
	_set_state(VisState.FLYING)
	_air_time = 0.0
	_ground_time = 0.0
	_was_grounded = false
	_prev_v = v
	_accel = Vector3.ZERO
	for sp in [_s_squash, _s_tilt, _s_sack, _s_santa]:
		sp.reset()
	for lsp in _lantern_springs:
		lsp.reset()
	snapped.emit()


func _begin_takeoff() -> void:
	_set_state(VisState.TAKING_OFF)
	_stretch_pending = true
	_burst_gpu(_dust, 16)
	_s_sack.kick(-1.2)
	takeoff_started.emit()


func _touchdown(impact: float) -> void:
	last_impact = impact
	_set_state(VisState.TOUCHDOWN)
	_s_squash.kick(-minf(impact * touchdown_squash_per_mps + 0.6, max_squash_kick))
	_s_tilt.kick(-impact * touchdown_pitch_per_mps)
	_s_sack.kick(-minf(1.0 + impact * 1.2, 6.0))
	_s_santa.kick(-impact * touchdown_santa_per_mps - 0.4)
	for lsp in _lantern_springs:
		lsp.kick(-1.0 - impact * 0.8)
	_burst_gpu(_dust, int(10 + impact * 7.0))
	if impact > spark_impact:
		_burst(_sparks, int(12 + impact * 5.0))
	touched_down.emit(impact)


# --- animation --------------------------------------------------------------------------------------

func _animate(dt: float, v: Vector3, grounded: bool) -> void:
	# Body squash & stretch (volume-ish preserving), pivoting at the runners.
	var sq_target := 0.0
	if state == VisState.TAKING_OFF and state_time < anticipation_time:
		sq_target = -takeoff_squash
	elif _stretch_pending:
		_stretch_pending = false
		_s_squash.kick(takeoff_stretch_kick)
		_s_tilt.kick(takeoff_tilt_kick)
		_s_santa.kick(takeoff_santa_kick)
		_s_sack.kick(2.5)
		for lsp in _lantern_springs:
			lsp.kick(2.5)
	var s := clampf(_s_squash.step(sq_target, squash_stiffness, squash_damping, dt), -max_squash, max_squash)
	_squash.scale = Vector3(1.0 - s * 0.5, 1.0 + s, 1.0 - s * 0.5)
	_tilt.rotation.x = clampf(_s_tilt.step(0.0, tilt_stiffness, tilt_damping, dt), -0.35, 0.45)

	var fwd := -_sleigh.global_transform.basis.z
	var a_fwd := _accel.dot(fwd)
	var a_up := _accel.y
	for i in _lanterns.size():
		var ls = _lantern_springs[i]
		var ang: float = ls.step(clampf(a_fwd * lantern_accel_gain, -0.5, 0.5), lantern_stiffness, lantern_damping, dt)
		_lanterns[i].rotation.x = clampf(ang, -0.7, 0.7)
		_lanterns[i].rotation.z = sin(_t * 2.1 + i * 1.7) * 0.03

	if _sack != null:
		var sk := clampf(_s_sack.step(clampf(-a_up * 0.004, -0.08, 0.08), sack_stiffness, sack_damping, dt), -0.3, 0.3)
		_sack.scale = Vector3(1.0 - sk * 0.4, 1.0 + sk, 1.0 - sk * 0.4)

	var lean := _s_santa.step(clampf(a_fwd * santa_lean_gain, -0.25, 0.25), santa_stiffness, santa_damping, dt)
	_santa_pivot.rotation.x = clampf(lean, -0.4, 0.4)
	var breath := sin(_t * breath_rate) * breath_amount * (1.0 if grounded else 0.5)
	_santa_pivot.scale = Vector3(1.0 - breath * 0.3, 1.0 + breath, 1.0 - breath * 0.3)

	var sliding := grounded and Vector2(v.x, v.z).length() > skid_speed
	for emitter in _skids:
		emitter.emitting = sliding
