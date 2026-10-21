extends Node3D
## Placeholder resident (no stealth AI yet): lies asleep in bed. Sleep depth (0 = awake .. 1 = deep)
## gets lighter as the night goes on. A nearby elf raises their awareness; at 1.0 they wake and sit
## up. Darted: they slump to the floor beside the bed (asleep) and must be carried back to bed
## (Tuck Trolley). States: ASLEEP, AWAKE, DARTED, CARRIED.

const GB := preload("res://scripts/greybox.gd")
const ES := preload("res://scripts/elf_size.gd")

enum State {ASLEEP, AWAKE, DARTED, CARRIED}

@export var resident_name := "Resident"
@export var adult := true
@export var base_depth := 0.7  ## Sleep depth at the start of the night (1 = very deep).
@export var notice_radius_eh := 10.0  ## A (silent) elf within this many elf heights (2.2 m) raises awareness when sleep is light.
@export var notice_rate := 0.35  ## Awareness per second at full exposure.
@export var calm_rate := 0.15
@export var pajama := Color(0.4, 0.5, 0.9)

var lie_height := 0.55  ## Height of the lying body above the bedroom floor (set from the bed).
var state := State.ASLEEP
var awareness := 0.0
var bed_xform := Transform3D()
var interior: Node3D
var darted_by := 0
var body: Node3D
var _zzz: Label3D
var _glow: MeshInstance3D
var _t := 0.0


func setup(bed: Transform3D, owner_interior: Node3D) -> void:
	bed_xform = bed
	interior = owner_interior
	transform = bed
	body = Node3D.new()
	add_child(body)
	var s := 1.0 if adult else 0.72
	var skin := Color(0.95, 0.75, 0.6) if resident_name != "Dad" else Color(0.85, 0.62, 0.48)
	# lying on the back, head toward the headboard (+Z in bed space is the foot... bed front faces -Z)
	# Bed pieces face -Z, headboard at +Z.
	var torso := GB.capsule(body, 0.2 * s, 1.15 * s, Vector3(0, 0.05, -0.05), pajama, Vector3(90, 0, 0))
	torso.scale = Vector3(1.25, 1.0, 0.75)
	GB.sphere(body, 0.15 * s, Vector3(0, 0.12, 0.72 * s), skin)
	GB.sphere(body, 0.035 * s, Vector3(0, 0.27 * s, 0.86 * s), skin.darkened(0.1))  # nose
	if resident_name == "Dad":
		GB.sphere(body, 0.155 * s, Vector3(0, 0.16, 0.78 * s), Color(0.3, 0.18, 0.1), 0.0, Vector3(1, 0.7, 1))
	else:
		GB.sphere(body, 0.16 * s, Vector3(0, 0.15, 0.8 * s), Color(0.55, 0.28, 0.12) if adult else Color(0.95, 0.75, 0.25), 0.0, Vector3(1.1, 0.8, 1.1))
	for e: float in [-1.0, 1.0]:
		GB.box(body, Vector3(0.05, 0.012, 0.012) * s, Vector3(e * 0.055 * s, 0.25 * s, 0.73 * s + 0.08), Color(0.15, 0.1, 0.1))
	# blanket bump over the legs
	var blanket := GB.capsule(body, 0.22 * s, 1.0 * s, Vector3(0, 0.03, -0.6 * s), pajama.darkened(0.25), Vector3(90, 0, 0))
	blanket.scale = Vector3(1.4, 1.0, 0.55)
	_zzz = Label3D.new()
	_zzz.text = "z z Z"
	_zzz.font_size = 48
	_zzz.pixel_size = 0.006
	_zzz.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_zzz.modulate = Color(0.75, 0.85, 1.0, 0.8)
	_zzz.position = Vector3(0.25, 0.6, 0.8 * s)
	_zzz.no_depth_test = false
	add_child(_zzz)
	# night-vision silhouette (shown through walls while the Glow-Gogs are on)
	_glow = MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.32 * s
	cap.height = 1.9 * s
	_glow.mesh = cap
	_glow.rotation_degrees = Vector3(90, 0, 0)
	_glow.position = Vector3(0, 0.1, 0.1)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(1.0, 0.95, 0.4, 0.35)
	gm.no_depth_test = true
	gm.cull_mode = BaseMaterial3D.CULL_BACK
	_glow.material_override = gm
	_glow.visible = false
	_glow.add_to_group("nv_glow")
	body.add_child(_glow)
	# hit box for Snooze Darts (physics layer 5)
	var hb := StaticBody3D.new()
	hb.collision_layer = 16
	hb.collision_mask = 0
	hb.set_meta("resident", self)
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3 * s
	shape.height = 1.9 * s
	cs.shape = shape
	cs.rotation_degrees = Vector3(90, 0, 0)
	cs.position = Vector3(0, 0.1, 0.1)
	hb.add_child(cs)
	body.add_child(hb)


func sleep_depth(night_factor: float) -> float:
	if state == State.AWAKE:
		return 0.0
	if state == State.DARTED or state == State.CARRIED:
		return 1.0
	return clampf(base_depth * night_factor, 0.0, 1.0)


static func depth_label(d: float) -> String:
	if d <= 0.01:
		return "AWAKE"
	if d < 0.3:
		return "Restless"
	if d < 0.6:
		return "Light"
	return "Deep"


## Called by the gadget manager every frame while the elf is in the house.
## hidden = the elf is crouched fully under furniture (can't be noticed); noise_radius = how far its
## footsteps carry right now (m, 0 when still), which can reach further than the plain notice radius.
func tick(delta: float, elf_pos: Vector3, night_factor: float, notice_mult: float, hidden := false, noise_radius := 0.0) -> void:
	_t += delta
	if state == State.ASLEEP:
		var d := sleep_depth(night_factor)
		var dist := global_position.distance_to(elf_pos)
		var reach := maxf(ES.m(notice_radius_eh), noise_radius)
		var exposure := 0.0 if hidden else clampf(1.0 - dist / reach, 0.0, 1.0) * (1.0 - d)
		if exposure > 0.0:
			awareness += exposure * notice_rate * notice_mult * delta
		else:
			awareness = maxf(0.0, awareness - calm_rate * delta)
		if awareness >= 1.0:
			wake()
		body.position.y = sin(_t * 1.3) * 0.01
		_zzz.visible = true
		_zzz.position.y = 0.6 + fmod(_t * 0.2, 0.3)
	elif state == State.AWAKE:
		_zzz.visible = false
	elif state == State.DARTED:
		_zzz.visible = true


func wake() -> void:
	if state != State.ASLEEP:
		return
	state = State.AWAKE
	awareness = 1.0
	# sit up in bed, looking around
	var tw := create_tween()
	tw.tween_property(body, "rotation_degrees", Vector3(-70, 0, 0), 0.6)
	tw.parallel().tween_property(body, "position", Vector3(0, 0.25, 0.4), 0.6)


## A dart hit: slump out of bed onto the floor beside it, out cold.
func hit_by_dart() -> void:
	if state == State.DARTED or state == State.CARRIED:
		return
	state = State.DARTED
	awareness = 0.0
	var side := bed_xform.basis.x.normalized()
	var floor_pos := bed_xform.origin + side * (1.3 if adult else 0.95)
	floor_pos.y = bed_xform.origin.y - lie_height + 0.12
	var tw := create_tween()
	tw.tween_property(self, "position", floor_pos, 0.7).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(body, "rotation_degrees", Vector3(0, 0, 8), 0.5)
	tw.parallel().tween_property(body, "position", Vector3.ZERO, 0.5)


func load_on(trolley: Node3D) -> void:
	state = State.CARRIED
	reparent(trolley, true)
	var tw := create_tween()
	tw.tween_property(self, "position", Vector3(0, float(trolley.get_meta("deck", 0.1)) + 0.2 * (1.0 if adult else 0.72), 0), 0.4)
	tw.parallel().tween_property(self, "rotation", Vector3.ZERO, 0.4)
	tw.parallel().tween_property(body, "rotation_degrees", Vector3.ZERO, 0.4)


func tuck_in() -> void:
	reparent(interior, true)
	state = State.ASLEEP
	awareness = 0.0
	base_depth = maxf(base_depth, 0.9)  # the dart keeps them deep for the rest of the night
	var tw := create_tween()
	tw.tween_property(self, "transform", bed_xform, 0.8).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(body, "rotation_degrees", Vector3.ZERO, 0.6)
	tw.parallel().tween_property(body, "position", Vector3.ZERO, 0.6)


func set_glow(on: bool) -> void:
	_glow.visible = on
