extends RigidBody3D
## Santa's sleigh: arcade-physical flight plus Lunar Lander-style touchdown scoring.
## Only this body's runners/tub count for landing. The reindeer team is visual-only (reindeer_team.gd).
## Local axes: forward = -Z, up = +Y.

signal touchdown(result: Dictionary)
signal crashed(reason: String)
signal reset_done

const SleighVisuals := preload("res://scripts/sleigh_visuals.gd")

@export_group("Flight")
@export var sleigh_mass := 300.0
@export var flight_gravity_scale := 0.6  ## Christmas magic: gravity is softened while flying.
@export var thrust_accel := 7.0  ## Forward pull from the reindeer (m/s^2).
@export var reverse_accel := 3.5
@export var lift_accel := 11.0  ## Upward accel at full lift. Hover needs ~5.9 (9.8 * gravity scale).
@export var yaw_torque := 3.5
@export var pitch_torque := 2.0
@export var upright_strength := 6.0  ## Self-levelling while airborne. pitch/upright ~ sin(max pitch).
@export var air_brake := 1.6  ## Horizontal damping while Brake is held (airborne only).
@export var hover_sink_speed := 1.2  ## Brake/hover holds this gentle descent rate.
@export var hover_vertical_gain := 3.0
@export var max_speed := 28.0
@export var linear_drag := 0.15
@export var angular_drag := 3.0

@export_group("Landing")
@export var crash_vertical_speed := 6.0
@export var crash_horizontal_speed := 9.0
@export var crash_tilt_deg := 30.0
## Star thresholds as (vertical m/s, horizontal m/s, tilt deg). All three must be under the limit.
@export var three_star := Vector3(1.5, 1.5, 6.0)
@export var two_star := Vector3(3.0, 3.5, 14.0)
@export var wall_crash_speed := 5.0
@export var flip_tilt_deg := 65.0
@export var min_air_time := 0.35  ## Airborne this long before a new touchdown is scored.
@export var reset_delay := 1.6

# Read by HUD / main
var controls_enabled := true  ## Off while the elf is inside a house (sleigh parked).
var grounded := false
var tilt_deg := 0.0
var surface_name := ""
var is_crashed := false
var last_result: Dictionary = {}

var _air_time := 0.0
var _last_air_velocity := Vector3.ZERO
var _last_surface_roof := false
var _reset_timer := 0.0
var _start_xform := Transform3D()
var _pending := false
var _pending_xform := Transform3D()
var _pending_vel := Vector3.ZERO
var _pending_is_reset := false
var _carry_local := Transform3D(Basis(), Vector3(-0.4, 0.06, 1.0))  # on the rear compartment floor
var _set_down_local := Transform3D(Basis(), Vector3(0.0, -0.44, 2.4))


func _ready() -> void:
	mass = sleigh_mass
	gravity_scale = flight_gravity_scale
	linear_damp = linear_drag
	angular_damp = angular_drag
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 16
	continuous_cd = true
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.3, 0.1)
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	pm.bounce = 0.0
	physics_material_override = pm
	# Collision: two runners + the tub. Nothing else (reindeer have no collision at all).
	_add_shape(Vector3(0.16, 0.12, 3.0), Vector3(-0.7, -0.6, 0.1))
	_add_shape(Vector3(0.16, 0.12, 3.0), Vector3(0.7, -0.6, 0.1))
	_add_shape(Vector3(1.5, 0.7, 2.6), Vector3(0, 0.0, 0.1))
	_build_visual()
	_start_xform = global_transform


func _add_shape(size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = pos
	add_child(cs)


func _build_visual() -> void:
	# Modelled sleigh + seated Santa with visual-only take-off/landing animation (sleigh_visuals.gd).
	# It only reads this body's state; the collision shapes above are unchanged.
	var v := SleighVisuals.new()
	v.name = "Visual"
	add_child(v)


# --- public API -----------------------------------------------------------------------------------

func get_carry_transform() -> Transform3D:
	return global_transform * _carry_local


func get_set_down_transform() -> Transform3D:
	return global_transform * _set_down_local


func request_reset() -> void:
	teleport(_start_xform, Vector3.ZERO)
	_pending_is_reset = true


func teleport(xform: Transform3D, velocity := Vector3.ZERO) -> void:
	_pending = true
	_pending_is_reset = false
	_pending_xform = xform
	_pending_vel = velocity


func status_text() -> String:
	if is_crashed:
		return "CRASHED"
	if grounded:
		return "On " + surface_name
	return "Flying"


# --- physics --------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if is_crashed:
		_reset_timer -= delta
		if _reset_timer <= 0.0:
			request_reset()
	elif global_position.y < -20.0:
		_fail("Lost in the dark!")


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _pending:
		_pending = false
		state.transform = _pending_xform
		state.linear_velocity = _pending_vel
		state.angular_velocity = Vector3.ZERO
		is_crashed = false
		grounded = false
		_air_time = min_air_time  # a teleport counts as airborne, so the next contact is scored
		_last_air_velocity = _pending_vel
		_last_surface_roof = false
		call_deferred("reset_physics_interpolation")
		if _pending_is_reset:
			_air_time = 0.0  # settling back onto the launch pad isn't a scored touchdown
			call_deferred("emit_signal", "reset_done")
		return

	var b := state.transform.basis
	var v := state.linear_velocity
	tilt_deg = rad_to_deg(b.y.angle_to(Vector3.UP))

	# --- contacts: what are the runners/tub touching? ---
	var support: Node = null
	var touched_ground := false
	var wall_hit := false
	for i in state.get_contact_count():
		var col := state.get_contact_collider_object(i) as Node
		if col == null:
			continue
		if col.is_in_group("ground"):
			touched_ground = true
		if absf(state.get_contact_local_normal(i).y) > 0.55:
			support = col
		else:
			wall_hit = true

	if not is_crashed:
		if touched_ground:
			_fail("Slid off the roof!" if _last_surface_roof else "Landed in the yard!")
		elif support != null and _air_time >= min_air_time:
			_evaluate_touchdown(support)
		elif wall_hit and support == null and _air_time > 0.0 and _last_air_velocity.length() > wall_crash_speed:
			_fail("Smashed into the house!")
		elif support != null and tilt_deg > flip_tilt_deg:
			_fail("Flipped the sleigh!")

	grounded = support != null
	if grounded:
		_air_time = 0.0
		surface_name = str(support.get_meta("surface_name", "ground"))
	else:
		_air_time += state.step
		_last_air_velocity = v

	if is_crashed:
		return
	_apply_controls(state, b, v)


func _apply_controls(state: PhysicsDirectBodyState3D, b: Basis, v: Vector3) -> void:
	if not controls_enabled:
		return
	var thrust := Input.get_axis("thrust_back", "thrust_fwd")
	var lift := Input.get_action_strength("lift")
	var brake := Input.get_action_strength("brake")
	var yaw := Input.get_axis("yaw_right", "yaw_left")
	var pitch := Input.get_axis("pitch_up", "pitch_down")  # + = nose down

	var accel := Vector3.ZERO
	accel += -b.z * thrust * (thrust_accel if thrust > 0.0 else reverse_accel)
	accel += Vector3.UP * lift * lift_accel
	if brake > 0.0 and not grounded:
		# Hover: cancel gravity, settle into a gentle sink, bleed off horizontal speed.
		var target_vy := -hover_sink_speed + lift * 3.0
		accel.y += -state.total_gravity.y * brake + (target_vy - v.y) * hover_vertical_gain * brake
		accel += -Vector3(v.x, 0.0, v.z) * air_brake * brake
	var speed := v.length()
	if speed > max_speed:
		accel += -v / speed * (speed - max_speed) * 4.0
	state.apply_central_force(accel * mass)

	var torque := Vector3.UP * yaw * yaw_torque
	torque += b.x * -pitch * pitch_torque
	if not grounded:
		torque += b.y.cross(Vector3.UP) * upright_strength
	state.apply_torque(torque * mass)


# --- landing --------------------------------------------------------------------------------------

func _evaluate_touchdown(surface: Node) -> void:
	var vs := maxf(0.0, -_last_air_velocity.y)
	var hs := Vector2(_last_air_velocity.x, _last_air_velocity.z).length()
	var r := {
		"surface": str(surface.get_meta("surface_name", "somewhere")),
		"vs": vs, "hs": hs, "tilt": tilt_deg, "stars": 0, "crash": false, "reason": "",
	}
	if not surface.is_in_group("roof"):
		_last_surface_roof = false
		r.reason = "No score here"
		_emit_touchdown(r)
		return
	_last_surface_roof = true
	if vs > crash_vertical_speed:
		r.reason = "Came down too hard!"
	elif hs > crash_horizontal_speed:
		r.reason = "Too fast across the roof!"
	elif tilt_deg > crash_tilt_deg:
		r.reason = "Landed crooked!"
	if r.reason != "":
		r.crash = true
		_emit_touchdown(r)
		_fail(r.reason)
		return
	if vs < three_star.x and hs < three_star.y and tilt_deg < three_star.z:
		r.stars = 3
	elif vs < two_star.x and hs < two_star.y and tilt_deg < two_star.z:
		r.stars = 2
	else:
		r.stars = 1
	_emit_touchdown(r)


func _emit_touchdown(r: Dictionary) -> void:
	last_result = r
	call_deferred("emit_signal", "touchdown", r)


func _fail(reason: String) -> void:
	if is_crashed:
		return
	is_crashed = true
	_reset_timer = reset_delay
	call_deferred("emit_signal", "crashed", reason)
