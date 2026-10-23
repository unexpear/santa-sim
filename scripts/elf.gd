extends CharacterBody3D
## The stealth elf (assets/models/elf.glb, modelled in build_models.py after
## art/reference/elf_stealth_reference.png). Tiny: the standing height is the shared constant in
## scripts/elf_size.gd (0.22 m, ankle-to-shin on an adult) and every size-dependent tunable below is
## in elf heights (eh). Third-person: WASD / left stick to scurry, mouse / right stick to look,
## C or Ctrl (or left stick click) to crouch-crawl, Space / A to hop. Crouching swaps to a shorter
## collision capsule (0.5 eh = 0.11 m) that fits under couches (0.14 m) and beds (0.24 m); fully
## under furniture while crouched = hidden (residents can't notice you). You can't stand up under
## something. Collides only with the interior layer (layer 3), never with the house shells.

const GB := preload("res://scripts/greybox.gd")
const ES := preload("res://scripts/elf_size.gd")
const MODEL := preload("res://assets/models/elf.glb")

const HEIGHT := ES.ELF_HEIGHT  ## Standing height in metres (gadget ranges are measured in elf heights).

@export_group("Movement (elf heights)")
@export var walk_speed_eh := 6.5  ## Scurry speed, eh/s (1.43 m/s: tiny legs, fast).
@export var sneak_speed_eh := 3.0  ## Crouch-crawl speed, eh/s (0.66 m/s).
@export var crouch_speed_eh := 4.2  ## Tactical crouch-walk speed, eh/s (0.92 m/s).
@export var accel_eh := 45.0  ## eh/s^2 (9.9 m/s^2).
@export var jump_height_eh := 1.0  ## Hop apex, eh (0.22 m: onto a rug edge or a step, not onto furniture).
@export var step_height_eh := 0.35  ## Floor snap / step-up, eh (0.077 m: thresholds, rug edges).
@export var noise_radius_walk_eh := 12.0  ## Footstep noise reach when scurrying, eh (2.64 m).
@export var noise_radius_sneak_eh := 4.0  ## ... when crouch-crawling, eh (0.88 m).
@export var noise_radius_crouch_eh := 7.0  ## ... when crouch-walking, eh (1.54 m).
@export var crouch_visibility := 0.65  ## Residents notice a crouch-walking elf at this rate (standing 1.0; crawling uses the gadgets' crouch_notice_mult).
@export var turn_speed := 12.0
@export var gravity := 9.8
@export_group("Camera (elf heights)")
@export var camera_distance_eh := 3.6  ## Spring arm length standing, eh (0.79 m).
@export var camera_height_eh := 1.5  ## Pivot height standing, eh (0.33 m).
@export var crouch_camera_distance_eh := 2.8  ## ... crouched (0.62 m).
@export var crouch_camera_height_eh := 0.42  ## ... crouched (0.092 m: stays under a 0.14 m couch).
@export var tac_camera_distance_eh := 3.2  ## ... tactical crouch (0.70 m).
@export var tac_camera_height_eh := 0.75  ## ... tactical crouch (0.165 m).
@export var camera_probe_eh := 0.1  ## Camera collision sphere radius, eh (0.022 m).
@export var mouse_sensitivity := 0.0025
@export var stick_sensitivity := 2.6
@export_group("Lean / peek (elf heights)")
@export var lean_eh := 0.6  ## How far the camera slides out round a corner when leaning, eh (0.13 m).
@export var lean_angle_deg := 22.0  ## Body tilt when leaning.
@export_group("Hat")
@export var hat_min_fold := 0.2  ## Fully folded hat cone keeps this fraction of its height.
@export var hat_fold_back_deg := 28.0  ## The cone tips back this far when fully folded.
@export var hat_margin := 0.003  ## Gap kept between the hat and anything above it (m).
@export var hat_fold_speed := 4.0  ## How fast the hat springs back up when there's room (1/s).
## Full visual height per stance with the hat folded as far as it goes (eh). Stance-fit checks and
## a small "hat" collision sphere use these, so the hat never ends up inside furniture.
@export var stand_fit_eh := 0.93  ## 0.205 m (standing, hat folded; HIGH gaps are 1.15)
@export var crouch_fit_eh := 0.8  ## 0.176 m (tactical crouch, hat folded; MID gaps are 0.85 = 0.187 m, fit test adds 1 cm)
@export var crawl_fit_eh := 0.565  ## 0.124 m (crawling, hat folded; LOW gaps are 0.62)
@export_group("Head collision")
## The head and nose lean out past the capsule when crouched or crawling; a sphere follows them so
## they don't poke into walls or furniture. Offsets are forward / up from the feet, in eh.
@export var head_radius_eh := 0.2
@export var head_crouch_fwd_eh := 0.16
@export var head_crouch_up_eh := 0.48
@export var head_crawl_fwd_eh := 0.26
@export var head_crawl_up_eh := 0.27
@export_group("Hat")
@export var auto_stance := true  ## Drop to a crouch or crawl by itself when the folded hat won't fit overhead.
@export_group("Goggles")
@export var goggle_light_energy := 0.35
@export var goggle_light_range_eh := 6.0  ## eh (1.32 m)

var control_enabled := false
var crouching := false  ## wants to crouch (input / scripted)
var crouched := false  ## crawling: collision is the short capsule (stays true under furniture)
var crouch_tac := false  ## wants the tactical crouch (C toggles it; scripted checks set it)
var tac_crouched := false  ## collision is the tactical-crouch capsule (stays true under a mid-height gap)
var hidden := false  ## fully under furniture (any stance that fits there)
var auto_target := Vector3.INF  ## Scripted checks drive the elf here (ignores input while set).
var speed_mult := 1.0  ## gadgets: Tuck Trolley slows you down
var accel_mult := 1.0  ## gadgets: wet floor (burst pipe puddle) is slippery
var puppet := false  ## Cutscenes move the elf directly (no physics).
var ext_control := false  ## The Crook-Line / climbing (rope_tech.gd) is moving the elf; camera still follows.
var ext_anim_speed := 0.0  ## Animation phase speed while ext_control (climbing hand-over-hand).
var ext_noise := 0.0  ## Noise radius (m) while ext_control.
var ext_visibility := 1.0  ## Notice multiplier while ext_control.
var jump_override: Callable  ## rope_tech: jump next to a climbable grabs it instead (returns true when used).
var lean := 0.0  ## -1 left .. 1 right (Z / X): peek round a corner.
var pose := ""  ## Scripted pose blended over the animation: "", "peek", "flip", "abseil", "grate_peek".
var _pose_blend := 0.0
var _pose_last := ""
var camera_distance := 0.0  ## metres (derived)
var camera_height := 0.0  ## metres (derived)

var model: Node3D
var hips: Node3D
var head: Node3D
var hat: Node3D
var hat_cone: Node3D  ## the cone + pom-pom (folds under low furniture; the brim stays put)
var _hat_meshes: Array = []
var _ear_pts: Array = []
var _visual_h := 0.0  ## how tall the elf is right now with the hat folded flat (m above the feet)
var _clear_here := INF  ## lowest furniture underside right above the elf
var _clear_ahead := INF  ## ... and a step ahead of where it's heading  ## [MeshInstance3D, PackedVector3Array] (the ears stick up next to the hat)
var _hat_fold := 0.0  ## 0 upright .. 1 fully folded, from what's overhead
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var cam_yaw: Node3D
var cam_pitch: Node3D
var spring: SpringArm3D
var camera: Camera3D
var goggle_light: OmniLight3D
var _cs: CollisionShape3D
var _cap_stand: CapsuleShape3D
var _cap_crouch: CapsuleShape3D
var _cap_tac: CapsuleShape3D
var _head_cs: CollisionShape3D  ## sphere round the head and nose, out in front when crouched or crawling
var _head_off := Vector3.ZERO
var _hat_cs: CollisionShape3D  ## small sphere topping out at the stance's fit height (the folded hat)
var auto_low := 0  ## 0 none, 1 auto-crouched, 2 auto-crawling (low surface overhead)
var _tac_blend := 0.0
var _pistol: Node3D
var _phase := 0.0
var _speed_blend := 0.0
var _crouch_blend := 0.0
var _idle_t := 0.0
var _hips_rest := Vector3.ZERO
var _leg_rest_l := Vector3.ZERO
var _leg_rest_r := Vector3.ZERO
## Leg length in model units (hip pivot to the sole, incl. the curly shoe), build_models.py.
const LEG_LEN_MU := 0.16
## The old crawl pose (legs straight back at hip height, over a dropped torso: the boots rode up
## through the elf's back). Only the --bootcheck before/after still sets this.
static var legacy_legs := false
var _jump_queued := false
## Body pushback: the arms, wrist launcher, nose and ears reach past the collision capsule; when
## they would go into a wall, door or furniture side the whole model eases back (horizontally) so
## no mesh ever pokes through. [MeshInstance3D, PackedVector3Array (subsampled local verts)]
var _push_pts: Array = []
var _push_off := Vector3.ZERO
var _model_rest := Vector3.ZERO
@export var pushback_margin_eh := 0.03  ## gap kept between the mesh and a surface, eh (6.6 mm)
@export var pushback_max_eh := 0.45  ## the model never slides further than this from the capsule, eh
## Falls and landings (elf physics): coyote time / jump buffer, a squash on landing that scales
## with the fall, a short stagger after big drops and a thud the residents can hear.
@export var coyote_time := 0.1
@export var jump_buffer := 0.12
@export var land_noise_eh_per_ms := 5.0  ## landing thud radius, eh per m/s of impact (a 0.5 m drop ~ 3.1 m/s -> 15 eh = 3.4 m)
@export var hard_land_speed_eh := 14.0  ## eh/s (3.1 m/s, about a 0.5 m drop): stagger + louder thud
var _air_t := 0.0
var _jump_buf := 0.0
var _fall_v := 0.0
var _squash := 0.0
var _stagger := 0.0
var land_noise := 0.0  ## metres, decays; read by noise_radius()
signal landed(speed: float)


func walk_speed() -> float:
	return ES.m(walk_speed_eh)


func noise_radius() -> float:
	if ext_control:
		return ext_noise
	var hv := Vector2(velocity.x, velocity.z).length()
	if land_noise > 0.0:
		return maxf(land_noise, 0.0 if (hidden or hv < 0.05) else ES.m(noise_radius_sneak_eh if crouched else (noise_radius_crouch_eh if tac_crouched else noise_radius_walk_eh)))
	if hidden or hv < 0.05:
		return 0.0
	return ES.m(noise_radius_sneak_eh if crouched else (noise_radius_crouch_eh if tac_crouched else noise_radius_walk_eh))


## "stand", "crouch" or "crawl".
func stance() -> String:
	if ext_control:
		return "rope"
	return "crawl" if crouched else ("crouch" if tac_crouched else "stand")


## Multiplier on how fast residents notice the elf (crawling is handled by the gadgets).
func visibility_mult() -> float:
	if ext_control:
		return ext_visibility
	return crouch_visibility if tac_crouched and not crouched else 1.0


func _ready() -> void:
	add_to_group("door_blocker")  # swinging doors stop against the elf
	set_meta("block_radius", ES.radius())
	collision_layer = 0
	collision_mask = 4
	floor_max_angle = deg_to_rad(48)
	floor_snap_length = ES.m(step_height_eh)
	safe_margin = 0.004
	camera_distance = ES.m(camera_distance_eh)
	camera_height = ES.m(camera_height_eh)
	_cap_stand = CapsuleShape3D.new()
	_cap_stand.radius = ES.radius()
	_cap_stand.height = ES.stand_height()  # the floppy hat tip is soft
	_cap_crouch = CapsuleShape3D.new()
	_cap_crouch.radius = ES.radius()
	_cap_crouch.height = ES.crouch_height()
	_cap_tac = CapsuleShape3D.new()
	_cap_tac.radius = ES.radius()
	_cap_tac.height = ES.tac_crouch_height()
	_cs = CollisionShape3D.new()
	add_child(_cs)
	_hat_cs = CollisionShape3D.new()
	var hs := SphereShape3D.new()
	hs.radius = ES.radius()
	_hat_cs.shape = hs
	add_child(_hat_cs)
	_head_cs = CollisionShape3D.new()
	var hd := SphereShape3D.new()
	hd.radius = ES.m(head_radius_eh)
	_head_cs.shape = hd
	_head_cs.position = Vector3(0, ES.m(0.55), 0)
	add_child(_head_cs)
	_set_shape(false)
	model = MODEL.instantiate() as Node3D
	model.scale = Vector3.ONE * (HEIGHT / ES.MODEL_HEIGHT)
	add_child(model)
	GB.toonify(model)
	for n in model.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = 1 | 2
	hips = model.find_child("Hips", true, false) as Node3D
	head = model.find_child("Head", true, false) as Node3D
	hat = model.find_child("Hat", true, false) as Node3D
	hat_cone = model.find_child("HatCone", true, false) as Node3D
	if hat:
		for n in hat.find_children("*", "MeshInstance3D", true, false):
			_hat_meshes.append(n)
	for n in model.find_children("ElfEar*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh:
			var v: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var few := PackedVector3Array()
			for k in range(0, v.size(), 3):
				few.append(v[k])
			_ear_pts.append([mi, few])
	_model_rest = model.position
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var pm := n as MeshInstance3D
		if pm.mesh == null or pm.mesh.get_surface_count() == 0:
			continue
		var pv: PackedVector3Array = pm.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var few2 := PackedVector3Array()
		var stepv := maxi(1, pv.size() / 60)
		for k in range(0, pv.size(), stepv):
			few2.append(pv[k])
		_push_pts.append([pm, few2])
	arm_l = model.find_child("ArmL", true, false) as Node3D
	arm_r = model.find_child("ArmR", true, false) as Node3D
	leg_l = model.find_child("LegL", true, false) as Node3D
	leg_r = model.find_child("LegR", true, false) as Node3D
	if hips:
		_hips_rest = hips.position
	if leg_l and leg_r:
		_leg_rest_l = leg_l.position
		_leg_rest_r = leg_r.position
	goggle_light = OmniLight3D.new()
	goggle_light.light_color = Color(0.4, 1.0, 0.35)
	goggle_light.light_energy = goggle_light_energy
	goggle_light.omni_range = ES.m(goggle_light_range_eh)
	goggle_light.light_cull_mask = 0xFFFFF
	goggle_light.position = Vector3(0, 0.1, -0.15)  # in front of the goggles (model units)
	(head if head else model).add_child(goggle_light)
	# third-person camera rig: low and close, with a small collision probe so it can follow you
	# under a bed or a couch without clipping into the furniture
	cam_yaw = Node3D.new()
	cam_yaw.top_level = true
	add_child(cam_yaw)
	cam_pitch = Node3D.new()
	cam_pitch.rotation.x = deg_to_rad(-14)
	cam_yaw.add_child(cam_pitch)
	spring = SpringArm3D.new()
	spring.spring_length = camera_distance
	spring.collision_mask = 4
	spring.margin = ES.m(camera_probe_eh) * 0.5
	var sph := SphereShape3D.new()
	sph.radius = ES.m(camera_probe_eh)
	spring.shape = sph
	cam_pitch.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 74.0
	camera.near = 0.01
	camera.far = 600.0
	spring.add_child(camera)


func _set_shape(c: bool, tac := false) -> void:
	crouched = c
	tac_crouched = tac and not c
	var cap := _cap_crouch if c else (_cap_tac if tac_crouched else _cap_stand)
	_cs.shape = cap
	_cs.position = Vector3(0, cap.height * 0.5, 0)
	if _hat_cs:
		_hat_cs.position = Vector3(0, _fit_height(cap) - (_hat_cs.shape as SphereShape3D).radius, 0)


## Full height (m) the elf needs in the stance of this capsule, folded hat included.
func _fit_height(cap: CapsuleShape3D) -> float:
	var eh := stand_fit_eh
	if cap == _cap_crouch:
		eh = crawl_fit_eh
	elif cap == _cap_tac:
		eh = crouch_fit_eh
	return maxf(cap.height, ES.m(eh))


## Standing / crouching / crawling fit height (m), folded hat included.
func fit_height(stance_name: String) -> float:
	return _fit_height(_cap_crouch if stance_name == "crawl" else (_cap_tac if stance_name == "crouch" else _cap_stand))


## Would the standing capsule fit here? (can't stand up under a couch)
func _can_stand() -> bool:
	return _fits(_cap_stand)


## Would the tactical-crouch capsule fit here?
func can_crouch() -> bool:
	return _fits(_cap_tac)


func _fits(cap: CapsuleShape3D) -> bool:
	# the capsule stretched to the stance's full height with the hat folded
	var c2 := CapsuleShape3D.new()
	c2.radius = cap.radius
	c2.height = _fit_height(cap)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = c2
	q.collision_mask = collision_mask
	q.transform = Transform3D(Basis(), global_position + Vector3(0, c2.height * 0.5 + 0.01, 0))
	if not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
		return false
	return _overhead_clear(c2.height + 0.01)


## Nothing lower than h overhead, over the capsule's edge and wherever the head and hat stick out
## past it (rays straight up from just off the floor, so walls beside the elf don't count).
func _overhead_clear(h: float) -> bool:
	if not is_inside_tree():
		return true
	var space := get_world_3d().direct_space_state
	var r := ES.radius()
	var pts: Array = [Vector3.ZERO, Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]
	for i in _hat_meshes.size():
		var mi: MeshInstance3D = _hat_meshes[i]
		var b := mi.global_transform * mi.get_aabb()
		for cx in [b.position.x, b.end.x]:
			for cz in [b.position.z, b.end.z]:
				pts.append(Vector3(cx - global_position.x, 0, cz - global_position.z))
	for o: Vector3 in pts:
		var from := global_position + o + Vector3(0, 0.03, 0)
		var q := PhysicsRayQueryParameters3D.create(from, global_position + o + Vector3(0, h, 0), collision_mask)
		q.exclude = [get_rid()]
		if not space.intersect_ray(q).is_empty():
			return false
	return true


## Fully under furniture: rays straight up from the centre and the capsule's edge all hit
## something low (furniture, not the ceiling).
func _under_cover() -> bool:
	var space := get_world_3d().direct_space_state
	var r := ES.radius()
	var top := (_cs.shape as CapsuleShape3D).height + 0.005
	var reach := 1.2  # anything lower than this is furniture (ceilings are ~2.9 m)
	for off: Vector3 in [Vector3.ZERO, Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]:
		var from := global_position + off + Vector3(0, top, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, reach, 0), collision_mask)
		if space.intersect_ray(q).is_empty():
			return false
	return true


func activate_camera() -> void:
	cam_yaw.global_position = global_position + Vector3(0, camera_height, 0)
	cam_yaw.rotation.y = model.global_rotation.y
	camera.current = true


func face(dir: Vector3) -> void:
	dir.y = 0
	if dir.length() > 0.01:
		model.rotation.y = atan2(-dir.x, -dir.z)


## Forward direction of the camera on the ground plane.
func aim_dir() -> Vector3:
	return -camera.global_basis.z


func _unhandled_input(event: InputEvent) -> void:
	if not control_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		cam_yaw.rotation.y -= m.relative.x * mouse_sensitivity
		cam_pitch.rotation.x = clampf(cam_pitch.rotation.x - m.relative.y * mouse_sensitivity, deg_to_rad(-60), deg_to_rad(35))
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if puppet:
		_animate(delta, 0.0)
		return
	if ext_control:
		hidden = false
		lean = move_toward(lean, 0.0, delta * 6.0)
		_phase += delta * ext_anim_speed
		_animate(delta, 0.0)
		_follow_cam(delta)
		return
	var move := Vector3.ZERO
	var lean_want := 0.0
	if auto_target != Vector3.INF:
		var to := auto_target - global_position
		to.y = 0
		if to.length() > 0.03:
			move = to.normalized()
	elif control_enabled:
		var look := Vector2(Input.get_axis("elf_look_left", "elf_look_right"), Input.get_axis("elf_look_up", "elf_look_down"))
		cam_yaw.rotation.y -= look.x * stick_sensitivity * delta
		cam_pitch.rotation.x = clampf(cam_pitch.rotation.x - look.y * stick_sensitivity * delta, deg_to_rad(-60), deg_to_rad(35))
		var inp := Input.get_vector("elf_left", "elf_right", "elf_fwd", "elf_back")
		var basis := Basis(Vector3.UP, cam_yaw.rotation.y)
		move = basis * Vector3(inp.x, 0, inp.y)
		if move.length() > 1.0:
			move = move.normalized()
		crouching = Input.is_action_pressed("elf_crouch")
		if Input.is_action_just_pressed("elf_tac_crouch"):
			crouch_tac = not crouch_tac
		if Input.is_action_just_pressed("elf_jump"):
			_jump_queued = true
		lean_want = Input.get_axis("elf_lean_left", "elf_lean_right")
	# crouch = a real collision change; standing back up needs headroom
	# stance = a real collision change; getting taller needs headroom (stay low under furniture)
	# Something low just ahead or overhead that even the folded hat won't clear: duck by itself.
	auto_low = _auto_low(move) if auto_stance else 0
	var want_crawl := crouching or auto_low == 2
	var want_tac := crouch_tac or auto_low == 1
	if want_crawl:
		if not crouched:
			_set_shape(true)
	elif want_tac:
		if crouched and can_crouch():
			_set_shape(false, true)
		elif not crouched and not tac_crouched:
			_set_shape(false, true)
	else:
		if (crouched or tac_crouched) and _can_stand():
			_set_shape(false)
		elif crouched and can_crouch():
			_set_shape(false, true)
	hidden = _under_cover()
	var spd := ES.m(sneak_speed_eh if crouched else (crouch_speed_eh if tac_crouched else walk_speed_eh)) * speed_mult
	var want := move * spd
	# heading under something lower than the elf is right now (still ducking): wait for the body to
	# get low enough before going under, so nothing pokes through the edge
	if auto_stance and _clear_ahead < _clear_here - 0.001 and _visual_h > _clear_ahead - 0.004:
		want = Vector3.ZERO
		velocity.x = 0.0
		velocity.z = 0.0
	if _stagger > 0.0:
		_stagger -= delta
		want *= 0.35  # winded after a big drop
	var on_floor := is_on_floor()
	# in the air you keep most of your momentum (only a little air control)
	var acc := ES.m(accel_eh) * accel_mult * delta * (1.0 if on_floor else 0.3)
	velocity.x = move_toward(velocity.x, want.x, acc)
	velocity.z = move_toward(velocity.z, want.z, acc)
	if _jump_queued:
		_jump_buf = jump_buffer
	_jump_queued = false
	_jump_buf = maxf(0.0, _jump_buf - delta)
	if on_floor:
		_air_t = 0.0
	else:
		_air_t += delta
	var can_jump := on_floor or _air_t < coyote_time
	if not on_floor:
		velocity.y -= gravity * delta
		_fall_v = maxf(_fall_v, -velocity.y)
	else:
		velocity.y = maxf(velocity.y, -0.5)
	if _jump_buf > 0.0 and can_jump:
		if on_floor and jump_override.is_valid() and bool(jump_override.call()):
			_jump_buf = 0.0
		elif not crouched and velocity.y <= 0.01:
			velocity.y = sqrt(2.0 * gravity * ES.m(jump_height_eh))
			_jump_buf = 0.0
			_air_t = coyote_time
	var was_air := not on_floor
	move_and_slide()
	land_noise = maxf(0.0, land_noise - delta * ES.m(20.0))
	if was_air and is_on_floor():
		_on_landed(_fall_v)
		_fall_v = 0.0
	# lean / peek: only while (nearly) still on the floor
	if Vector2(velocity.x, velocity.z).length() > walk_speed() * 0.6 or not is_on_floor():
		lean_want = 0.0
	lean = move_toward(lean, lean_want, delta * 5.0)
	var hv := Vector3(velocity.x, 0, velocity.z)
	if hv.length() > 0.04:
		var target_yaw := atan2(-hv.x, -hv.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))
	_animate(delta, hv.length())
	_follow_cam(delta)


## Camera follows smoothly; low and closer when crouched (fits under a couch); slides out when leaning.
func _follow_cam(delta: float) -> void:
	var ch := ES.m(crouch_camera_height_eh if crouched else (tac_camera_height_eh if tac_crouched else camera_height_eh))
	var cd := ES.m(crouch_camera_distance_eh if crouched else (tac_camera_distance_eh if tac_crouched else camera_distance_eh))
	spring.spring_length = lerpf(spring.spring_length, cd, 1.0 - exp(-6.0 * delta))
	var cam_target := global_position + Vector3(0, ch, 0)
	if absf(lean) > 0.01:
		var right := Basis(Vector3.UP, cam_yaw.rotation.y) * Vector3.RIGHT
		var want := cam_target + right * lean * ES.m(lean_eh)
		# don't push the camera through the wall you're peeking round
		var q := PhysicsRayQueryParameters3D.create(cam_target, want + right * signf(lean) * ES.m(0.2), collision_mask)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		cam_target = want if hit.is_empty() else cam_target.lerp(want, clampf(cam_target.distance_to(hit.position) / ES.m(lean_eh + 0.2), 0.0, 1.0) * 0.8)
	cam_yaw.global_position = cam_yaw.global_position.lerp(cam_target, 1.0 - exp(-12.0 * delta))


## Lowest overhead surface (furniture underside) above the elf and a step ahead, and the stance it
## needs: 0 any, 1 crouch, 2 crawl. Only counts low things (furniture), not ceilings.
func _auto_low(move: Vector3) -> int:
	if not is_on_floor():
		return auto_low
	var space := get_world_3d().direct_space_state
	var pts := [global_position]
	if move.length() > 0.1:
		pts.append(global_position + move.normalized() * ES.radius() * 1.6)
		pts.append(global_position + move.normalized() * (ES.radius() * 1.6 + 0.12))
	var clear := INF
	_clear_here = INF
	_clear_ahead = INF
	for p: Vector3 in pts:
		var from := p + Vector3(0, 0.02, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 0.4, 0), collision_mask)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var cy := (hit.position as Vector3).y - global_position.y
			clear = minf(clear, cy)
			if p == global_position:
				_clear_here = cy
			else:
				_clear_ahead = minf(_clear_ahead, cy)
	if clear >= fit_height("stand"):
		return 0
	if clear >= fit_height("crouch"):
		return 1
	return 2


## Procedural scurry + idle; crouched = a low crawl with the floppy hat squashed flat.
## speed in m/s. Offsets are in model units (the model is scaled to the elf height).
func _animate(delta: float, speed: float) -> void:
	if hips == null:
		return
	var speed_eh := speed / HEIGHT
	_speed_blend = lerpf(_speed_blend, clampf(speed / walk_speed(), 0.0, 1.0), 1.0 - exp(-8.0 * delta))
	_crouch_blend = lerpf(_crouch_blend, 1.0 if crouched else 0.0, 1.0 - exp(-10.0 * delta))
	_phase += delta * (4.0 + speed_eh * 2.6)
	_idle_t += delta
	var s := sin(_phase)
	var w := _speed_blend
	var c := _crouch_blend
	var sneak := 0.35 * (1.0 - c)
	# hips: drop low and pitch the body forward into a crawl when crouched
	hips.position = _hips_rest + Vector3(0, -0.075 * c - absf(s) * 0.015 * w * (1.0 - c) + sin(_idle_t * 2.2) * 0.003, 0.03 * c)
	hips.rotation = Vector3(deg_to_rad(18.0 * sneak + 6.0 * w * (1.0 - c)) - deg_to_rad(78.0) * c, sin(_phase * 0.5) * 0.08 * w, sin(_phase) * 0.05 * w)
	# legs: high tiptoe steps standing; knees back (kneeling) and a small shuffle when crawling
	# crawl: the leg pivots drop and slide back with the hips (they are siblings of Hips in the
	# rig), and the legs angle back-and-down just enough that the soles reach the floor: knees
	# under the belly, boots trailing low behind on the floor, never up over the back.
	var kneel := -_floor_leg_angle(_hips_rest.y - 0.075) if not legacy_legs else -1.5
	leg_l.rotation = Vector3(lerpf(s * 0.7 * w, kneel + s * 0.2 * w, c), 0, 0)
	leg_r.rotation = Vector3(lerpf(-s * 0.7 * w, kneel - s * 0.2 * w, c), 0, 0)
	# arms: held up sneakily standing; reaching forward to the floor when crawling
	var raise := 0.9 * (1.0 - w * 0.4)
	arm_l.rotation = Vector3(lerpf(-raise - s * 0.4 * w, 0.2 - s * 0.35 * w, c), 0, -0.35 - 0.15 * sin(_idle_t * 1.7))
	arm_r.rotation = Vector3(lerpf(-raise + s * 0.4 * w, -0.3 + s * 0.35 * w, c), 0, 0.35 + 0.15 * sin(_idle_t * 1.5))
	# head: peeks left and right when idle; looks forward (tipped back) when crawling
	var peek := sin(_idle_t * 0.9) * 0.6 * (1.0 - w)
	head.rotation = Vector3(-deg_to_rad(18.0 * sneak) + deg_to_rad(48.0) * c + sin(_idle_t * 2.0) * 0.04, peek, sin(_idle_t * 1.3) * 0.08)
	# the floppy hat: the brim stays seated on the head, the cone squashes and folds back when
	# crawling and under anything low overhead (see _fit_hat)
	_set_hat_fold(maxf(0.8 * c, _hat_fold))
	# tactical crouch-walk: knees bent, low and leaning in, both hands on the dart pistol
	_tac_blend = lerpf(_tac_blend, 1.0 if tac_crouched else 0.0, 1.0 - exp(-10.0 * delta))
	var tb := _tac_blend
	if tb > 0.01:
		hips.position = hips.position.lerp(_hips_rest + Vector3(0, -0.05 - absf(s) * 0.006 * w, 0.0), tb)
		hips.rotation = hips.rotation.lerp(Vector3(deg_to_rad(-24.0), sin(_phase * 0.5) * 0.04 * w, 0), tb)
		leg_l.rotation = leg_l.rotation.lerp(Vector3(-0.35 + s * 0.45 * w, 0, 0.05), tb)
		leg_r.rotation = leg_r.rotation.lerp(Vector3(-0.35 - s * 0.45 * w, 0, -0.05), tb)
		arm_l.rotation = arm_l.rotation.lerp(Vector3(-1.25, 0, 0.45), tb)
		arm_r.rotation = arm_r.rotation.lerp(Vector3(-1.4, 0, -0.2), tb)
		head.rotation = head.rotation.lerp(Vector3(deg_to_rad(20.0), sin(_idle_t * 0.9) * 0.25 * (1.0 - w), 0), tb)
	if _pistol == null and arm_r:
		_pistol = _make_pistol()
	if _pistol:
		_pistol.visible = tb > 0.3
	_apply_pose(delta)
	_legs_follow_hips(c)
	if absf(lean) > 0.01:
		hips.rotation.z -= lean * deg_to_rad(lean_angle_deg)
		head.rotation.z -= lean * deg_to_rad(lean_angle_deg * 0.5)
	_fit_hat(delta, 0.8 * c)
	_update_hat_shape()
	_update_head_shape(delta)
	_body_pushback(delta)
	# landing squash (feet stay planted: scale about the model origin at the feet)
	_squash = move_toward(_squash, 0.0, delta * 3.5)
	var sq := _squash * 0.22
	model.scale = Vector3.ONE * (HEIGHT / ES.MODEL_HEIGHT) * Vector3(1.0 + sq * 0.6, 1.0 - sq, 1.0 + sq * 0.6)


## Touchdown after a fall: squash proportional to impact, a thud (noise) the residents hear,
## and a short stagger after a big drop. Tiny step-downs are silent.
func _on_landed(v: float) -> void:
	if v < ES.m(4.0):  # step-downs and rug edges: silent
		return
	var hard := ES.m(hard_land_speed_eh)
	_squash = clampf(v / hard, 0.15, 1.0)
	land_noise = ES.m(v * land_noise_eh_per_ms * (0.5 if (crouched or tac_crouched) else 1.0))
	if v > hard:
		_stagger = 0.35
	landed.emit(v)


## Ease the whole model back from any wall, door or furniture side its reaching parts would
## enter: the farthest sampled vertices in 8 directions x 4 height bands each cast a ray out from
## the elf's middle; any overlap (plus a small margin) becomes a horizontal shove back.
func _body_pushback(delta: float) -> void:
	if model == null or not is_inside_tree():
		return
	if puppet or ext_control or _push_pts.is_empty():
		_push_off = _push_off.lerp(Vector3.ZERO, 1.0 - exp(-10.0 * delta))
		model.position = _model_rest + _push_off
		return
	var c := global_position
	var best := {}
	for e in _push_pts:
		var mi: MeshInstance3D = e[0]
		if not mi.is_visible_in_tree():
			continue
		var xf := mi.global_transform
		for v: Vector3 in e[1]:
			var w: Vector3 = xf * v - _push_off
			var hv := Vector3(w.x - c.x, 0, w.z - c.z)
			var d := hv.length()
			if d < ES.radius() * 0.8:
				continue
			var key := (int((atan2(hv.z, hv.x) + PI) / TAU * 8.0) % 8) * 4 + clampi(int((w.y - c.y) / ES.m(0.3)), 0, 3)
			if not best.has(key) or float(best[key][0]) < d:
				best[key] = [d, w]
	var space := get_world_3d().direct_space_state
	var push := Vector3.ZERO
	var margin := ES.m(pushback_margin_eh)
	for key in best:
		var d: float = best[key][0]
		var w: Vector3 = best[key][1]
		var dir := Vector3(w.x - c.x, 0, w.z - c.z) / d
		var from := Vector3(c.x, w.y, c.z)
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * (d + margin), collision_mask)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var over := d + margin - from.distance_to(hit.position)
		if over <= 0.0:
			continue
		var n: Vector3 = hit.normal
		n.y = 0
		n = n.normalized() if n.length() > 0.1 else -dir
		# shove along the surface normal; add only what isn't already covered
		var have := push.dot(n)
		var need := over / maxf(absf(n.dot(dir)), 0.35)
		if need > have:
			push += n * (need - have)
	push = push.limit_length(ES.m(pushback_max_eh))
	if push.length() >= _push_off.length():
		_push_off = push  # never lag into a wall
	else:
		_push_off = _push_off.lerp(push, 1.0 - exp(-8.0 * delta))
	model.position = _model_rest + _push_off


func _update_head_shape(delta: float) -> void:
	if _head_cs == null or model == null:
		return
	_head_cs.disabled = puppet or ext_control
	var want := Vector3(0, ES.m(0.55), 0)
	if crouched:
		want = Vector3(0, ES.m(head_crawl_up_eh), -ES.m(head_crawl_fwd_eh))
	elif tac_crouched:
		want = Vector3(0, ES.m(head_crouch_up_eh), -ES.m(head_crouch_fwd_eh))
	_head_off = _head_off.lerp(want, 1.0 - exp(-12.0 * delta))
	_head_cs.position = Basis(Vector3.UP, model.global_rotation.y) * _head_off


## The hat collision sphere tops out at the elf's real height right now with the hat folded as far
## as it goes, so while the body is still ducking (animation lag) it can't slide under something
## its head would go through.
func _update_hat_shape() -> void:
	if _hat_cs == null or _cs == null or hat == null or _hat_meshes.is_empty() or puppet or ext_control:
		return
	var keep: Vector3 = hat_cone.scale if hat_cone else Vector3.ONE
	var keep_r: Vector3 = hat_cone.rotation if hat_cone else Vector3.ZERO
	_set_hat_fold(1.0)
	var tp := hat_top()
	var need := tp.y - global_position.y
	for e in _ear_pts:
		var xf: Transform3D = (e[0] as MeshInstance3D).global_transform
		for v: Vector3 in e[1]:
			need = maxf(need, (xf * v).y - global_position.y)
	if hat_cone:
		hat_cone.scale = keep
		hat_cone.rotation = keep_r
	var r := (_hat_cs.shape as SphereShape3D).radius
	_visual_h = need
	var h := maxf(_fit_height(_cs.shape as CapsuleShape3D), need)
	# over the hat itself (it sits forward or back of the elf's middle as the body leans)
	var off := Vector3(tp.x - global_position.x, 0, tp.z - global_position.z).limit_length(ES.radius() * 0.5)
	_hat_cs.position = Vector3(off.x, minf(h, ES.m(stand_fit_eh) + 0.01) - r, off.z)


func _set_hat_fold(f: float) -> void:
	var cone := hat_cone if hat_cone else hat
	if cone == null:
		return
	f = clampf(f, 0.0, 1.0)
	cone.scale = Vector3(1.0 + 0.18 * f, 1.0 - (1.0 - hat_min_fold) * f, 1.0 + 0.12 * f)
	cone.rotation = Vector3(deg_to_rad(hat_fold_back_deg) * f, 0, 0)


## Highest point of the hat (world), from the hat meshes' bounds.
func hat_top() -> Vector3:
	var best := Vector3(0, -INF, 0)
	for mi: MeshInstance3D in _hat_meshes:
		var bb := mi.global_transform * mi.get_aabb()
		if bb.end.y > best.y:
			best = Vector3(bb.get_center().x, bb.end.y, bb.get_center().z)
	return best


## Lowest thing overhead (world y) above the hat, or INF.
func _ceiling_over_hat() -> float:
	if hat == null or not is_inside_tree():
		return INF
	var space := get_world_3d().direct_space_state
	var top := hat_top()
	var base := hat.global_position
	var c := INF
	var bb := AABB()
	for i in _hat_meshes.size():
		var mi: MeshInstance3D = _hat_meshes[i]
		var b2 := mi.global_transform * mi.get_aabb()
		bb = b2 if i == 0 else bb.merge(b2)
	var pts := [Vector3(base.x, 0, base.z), Vector3(top.x, 0, top.z)]
	for cx in [bb.position.x, bb.end.x]:
		for cz in [bb.position.z, bb.end.z]:
			pts.append(Vector3(cx, 0, cz))
	for xz: Vector3 in pts:
		# from just off the floor, so a ray never starts inside the thing overhead
		var from := Vector3(xz.x, global_position.y + 0.03, xz.z)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 0.5, 0), collision_mask)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			c = minf(c, (hit.position as Vector3).y)
	return c


## The hat reacts to what's overhead: it folds just enough to stay under a low surface (never
## through it) and springs back up when there's room again. floor_fold: the stance's own fold.
func _fit_hat(delta: float, floor_fold: float) -> void:
	if hat == null or _hat_meshes.is_empty():
		return
	var ceil_y := _ceiling_over_hat() - hat_margin
	var cur := maxf(floor_fold, _hat_fold)
	if ceil_y == INF:
		_hat_fold = move_toward(_hat_fold, 0.0, delta * hat_fold_speed)
		_set_hat_fold(maxf(floor_fold, _hat_fold))
		return
	# relax towards upright, but only as far as it still fits
	var relaxed := move_toward(_hat_fold, 0.0, delta * hat_fold_speed)
	_set_hat_fold(maxf(floor_fold, relaxed))
	if hat_top().y <= ceil_y:
		_hat_fold = relaxed
		return
	# fold more until it fits (or is fully folded)
	var f := cur
	_set_hat_fold(f)
	var n := 0
	while hat_top().y > ceil_y and f < 1.0 and n < 20:
		f = minf(1.0, f + 0.05)
		_set_hat_fold(f)
		n += 1
	_hat_fold = f


## The dart pistol held in the crouch (model units, on the right hand).
func _make_pistol() -> Node3D:
	var p := Node3D.new()
	p.name = "DartPistol"
	arm_r.add_child(p)
	p.position = Vector3(0.0, -0.02, -0.11)
	var green := Color(0.12, 0.28, 0.16)
	GB.box(p, Vector3(0.03, 0.035, 0.09), Vector3(0, 0, -0.03), green)
	GB.box(p, Vector3(0.026, 0.06, 0.03), Vector3(0, -0.04, 0.0), Color(0.08, 0.08, 0.09), Vector3(15, 0, 0))
	GB.cylinder(p, 0.01, 0.01, 0.06, Vector3(0, 0.005, -0.1), Color(0.08, 0.08, 0.09), Vector3(90, 0, 0))
	GB.box(p, Vector3(0.032, 0.008, 0.02), Vector3(0, 0.02, -0.05), Color(0.9, 0.1, 0.12))
	for n in p.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = 1 | 2
	p.visible = false
	return p


## Angle (rad, back from vertical) at which a leg hung from a pivot at height h (model units)
## just reaches the floor.
func _floor_leg_angle(h: float) -> float:
	return acos(clampf(h / LEG_LEN_MU, 0.0, 1.0))


## In the low poses (crawl, kneeling peeks) the leg pivots move with the hips, so the legs stay
## attached under the body instead of floating at standing hip height.
func _legs_follow_hips(c: float) -> void:
	if legacy_legs or leg_l == null:
		return
	var ground := c
	if _pose_last in ["peek", "grate_peek", "mantle", "flip"]:
		ground = maxf(ground, _pose_blend)
	ground *= 1.0 - _tac_blend
	var off := (hips.position - _hips_rest) * ground
	leg_l.position = _leg_rest_l + off
	leg_r.position = _leg_rest_r + off


## Cutscene / rope poses, blended in over the procedural animation.
func _apply_pose(delta: float) -> void:
	if pose != "":
		_pose_last = pose
	_pose_blend = lerpf(_pose_blend, 1.0 if pose != "" else 0.0, 1.0 - exp(-9.0 * delta))
	if _pose_blend < 0.01:
		return
	var k := _pose_blend
	var hp := Vector3.ZERO
	var hr := Vector3.ZERO
	var ll := Vector3.ZERO
	var lr := Vector3.ZERO
	var al := Vector3.ZERO
	var ar := Vector3.ZERO
	var hd := Vector3.ZERO
	var wob := sin(_idle_t * 3.0)
	match _pose_last:
		"peek":  # kneeling at the lip, leaning right over the hole, head down
			hp = Vector3(0, -0.06, -0.05)
			hr = Vector3(deg_to_rad(-50), 0, 0)
			ll = Vector3(-1.45 if legacy_legs else -_floor_leg_angle(_hips_rest.y - 0.06), 0, 0.1)
			lr = Vector3(-1.45 if legacy_legs else -_floor_leg_angle(_hips_rest.y - 0.06), 0, -0.1)
			al = Vector3(-1.2, 0, -0.25)
			ar = Vector3(-1.2, 0, 0.25)
			hd = Vector3(deg_to_rad(-38) + wob * 0.03, sin(_idle_t * 1.4) * 0.2, 0)
		"flip":  # crouched, right arm flung up
			hp = Vector3(0, -0.05, 0)
			hr = Vector3(deg_to_rad(-25), 0, 0)
			ll = Vector3(-1.1, 0, 0)
			lr = Vector3(-0.6, 0, 0)
			al = Vector3(-0.4, 0, -0.4)
			ar = Vector3(-2.6, 0, 0.2)
			hd = Vector3(deg_to_rad(10), 0, 0)
		"abseil":  # sitting back in the harness, feet on the wall, braking hand low, guide hand up
			hp = Vector3(0, 0, 0.02)
			hr = Vector3(deg_to_rad(28), 0, 0)
			ll = Vector3((-1.25 if legacy_legs else 1.25) + wob * 0.12, 0, 0.12)  # feet forward, on the wall
			lr = Vector3((-1.25 if legacy_legs else 1.25) - wob * 0.12, 0, -0.12)
			al = Vector3(-2.7, 0, -0.15)
			ar = Vector3(-0.5, 0, 0.5)
			hd = Vector3(deg_to_rad(-20), 0, 0)
		"hang":  # on the Crook-Line: both hands up on the cable, legs together, a little swing
			hp = Vector3(0, 0.02, 0)
			hr = Vector3(deg_to_rad(6) + wob * 0.04, 0, 0)
			ll = Vector3(-0.35, 0, 0.05)
			lr = Vector3(-0.2, 0, -0.05)
			al = Vector3(-2.95, 0, -0.12)
			ar = Vector3(-2.95, 0, 0.12)
			hd = Vector3(deg_to_rad(-12), 0, 0)
		"zip":  # hanging from the hand trolley, knees tucked up
			hp = Vector3(0, 0.02, 0)
			hr = Vector3(deg_to_rad(-8), 0, 0)
			ll = Vector3(-1.1 if legacy_legs else 1.1, 0, 0.08)  # knees tucked up in front
			lr = Vector3(-1.0 if legacy_legs else 1.0, 0, -0.08)
			al = Vector3(-3.0, 0, -0.08)
			ar = Vector3(-3.0, 0, 0.08)
			hd = Vector3(deg_to_rad(5), 0, 0)
		"climb":  # hand over hand, toes in
			var c2 := sin(_phase)
			hp = Vector3(0, 0, 0.0)
			hr = Vector3(deg_to_rad(-8), 0, 0)
			ll = Vector3((-0.9 if legacy_legs else 0.45) + c2 * 0.4, 0, 0.1)  # toes in toward the wall
			lr = Vector3((-0.9 if legacy_legs else 0.45) - c2 * 0.4, 0, -0.1)
			al = Vector3(-2.6 - c2 * 0.35, 0, -0.2)
			ar = Vector3(-2.6 + c2 * 0.35, 0, 0.2)
			hd = Vector3(deg_to_rad(-25), 0, 0)
		"mantle":  # hauling up over a ledge
			hp = Vector3(0, -0.03, -0.03)
			hr = Vector3(deg_to_rad(-45), 0, 0)
			ll = Vector3(-1.4, 0, 0.1)
			lr = Vector3(-0.4, 0, -0.1)
			al = Vector3(-1.6, 0, -0.3)
			ar = Vector3(-1.6, 0, 0.3)
			hd = Vector3(deg_to_rad(-10), 0, 0)
		"grate_peek":  # low in the firebox, peeking out past the grate
			hp = Vector3(0, -0.085, 0.02)
			hr = Vector3(deg_to_rad(-35), 0, 0)
			ll = Vector3(-1.6 if legacy_legs else -_floor_leg_angle(_hips_rest.y - 0.085), 0, 0.1)
			lr = Vector3(-1.6 if legacy_legs else -_floor_leg_angle(_hips_rest.y - 0.085), 0, -0.1)
			al = Vector3(-1.4, 0, -0.2)
			ar = Vector3(-0.9, 0, 0.3)
			hd = Vector3(deg_to_rad(15), sin(_idle_t * 1.1) * 0.45, 0)
	hips.position = hips.position.lerp(_hips_rest + hp, k)
	hips.rotation = hips.rotation.lerp(hr, k)
	leg_l.rotation = leg_l.rotation.lerp(ll, k)
	leg_r.rotation = leg_r.rotation.lerp(lr, k)
	arm_l.rotation = arm_l.rotation.lerp(al, k)
	arm_r.rotation = arm_r.rotation.lerp(ar, k)
	head.rotation = head.rotation.lerp(hd, k)
