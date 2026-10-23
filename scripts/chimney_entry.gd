extends Node
## Chimney entry: land on a roof near the chimney -> "Press F: enter chimney" -> the elf hops onto the
## rim, hooks the Crook-Line (candy-cane grapple) and abseils down the sooty flue, creeps out of the
## fireplace in a puff of green mist, and you play the elf inside. Back at the hearth, F winches the
## elf up the flue to the sleigh. A lit fireplace blocks the way in: hold F on the roof to fire the
## Fireplace Icer down the flue first.

const GB := preload("res://scripts/greybox.gd")
const FX := preload("res://scripts/fx.gd")
const Elf := preload("res://scripts/elf.gd")
const Gadgets := preload("res://scripts/gadgets.gd")
const ES := preload("res://scripts/elf_size.gd")  ## shared elf height; *_eh values are in elf heights

enum Mode {SLEIGH, CUTSCENE, ELF}

@export var enter_radius := 8.5  ## Sleigh within this distance (m, horizontal) of a chimney on a landed roof.
@export var hop_time := 0.8
@export var hop_arc_eh := 4.0  ## Hop from the sleigh to the chimney rim: arc height, eh (0.88 m).
@export_group("Crook-Line (elf heights)")
@export var crook_line_length_eh := 45.0  ## Line on the reel, eh (9.9 m); every landing-house flue is shorter.
@export var abseil_speed_eh := 9.0  ## Abseil down the flue, eh/s (1.98 m/s).
@export var winch_speed_eh := 14.0  ## Winch back up, eh/s (3.08 m/s).
@export var line_grip_eh := 0.8  ## Where the line meets the elf (its hands), eh (0.18 m).
@export_group("Cutscene framing (elf heights)")
@export var rim_cam_distance_eh := 9.0  ## Hop/winch camera distance from the chimney top, eh (1.98 m).
@export var rim_cam_height_eh := 5.0  ## ... and height above it, eh (1.1 m).
@export var hearth_cam_distance_eh := 4.5  ## Fireplace emergence camera, out from the hearth, eh (0.99 m).
@export var hearth_cam_height_eh := 1.8  ## ... and height, eh (0.4 m).
@export var creep_time := 1.2
@export var exit_confirm_window := 4.0  ## Seconds to press F again to climb out despite evidence warnings.

var main: Node
var sleigh: RigidBody3D
var chase_cam: Camera3D
var houses: Array = []
var elf: CharacterBody3D
var gadgets: Node
var cut_cam: Camera3D
var mode := Mode.SLEIGH
var house: Node3D
var scripted := false  ## scripted checks: don't capture the mouse
var _exit_confirm_until := 0.0
var _hook: Node3D
var _line: MeshInstance3D
var _roof_frost: GPUParticles3D
var _soot_trail: GPUParticles3D
var _cut_t := 0.0  # cutscene progress for checks
var cut_phase := ""
var _roof_icer_t := -10.0
var _gog_beam: SpotLight3D  # green goggle beam in the flue (cutscene)
var _cam_rig: Array = []  # [position, look target] of the cutscene camera


func setup(m: Node, s: RigidBody3D, cam: Camera3D, hs: Array) -> void:
	main = m
	sleigh = s
	chase_cam = cam
	houses = hs
	gadgets = Gadgets.new()
	gadgets.name = "Gadgets"
	gadgets.main = m
	gadgets.mission = self
	add_child(gadgets)
	elf = Elf.new()
	elf.name = "Elf"
	(m as Node3D).add_child(elf)
	elf.visible = false
	elf.puppet = true
	elf.global_position = Vector3(0, -50, 0)
	cut_cam = Camera3D.new()
	cut_cam.fov = 62.0
	cut_cam.near = 0.015  # the flue is only 0.34 m across
	cut_cam.far = 600.0
	(m as Node3D).add_child(cut_cam)


func is_busy() -> bool:
	return mode != Mode.SLEIGH


## The house whose chimney the landed sleigh is next to (or null).
func roof_house() -> Node3D:
	if not bool(sleigh.get("grounded")) or bool(sleigh.get("is_crashed")) or sleigh.global_position.y < 1.5:
		return null
	for h in houses:
		var c: Vector3 = h.call("get_chimney_base_world")
		var d := Vector2(sleigh.global_position.x - c.x, sleigh.global_position.z - c.z).length()
		if d < enter_radius and sleigh.global_position.y > c.y - 3.0:
			return h
	return null


func _process(delta: float) -> void:
	match mode:
		Mode.SLEIGH:
			_sleigh_tick(delta)
		Mode.ELF:
			if Input.is_action_just_pressed("interact"):
				try_exit()
			if Input.is_action_just_pressed("ui_cancel"):
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _sleigh_tick(delta: float) -> void:
	var h := roof_house()
	if _roof_frost and Time.get_ticks_msec() / 1000.0 - _roof_icer_t > 0.15:
		_roof_frost.emitting = false
	if h == null:
		if gadgets.prompt.text.begins_with("Press F") or gadgets.prompt.text.begins_with("Fire") or gadgets.prompt.text.begins_with("Hold F"):
			gadgets.prompt.text = ""
		return
	if bool(h.get("fire_lit")):
		gadgets.prompt.text = "Fire's lit down there!  Hold F: Fireplace Icer down the flue"
		if Input.is_action_pressed("interact"):
			roof_icer(h, delta)
		return
	gadgets.prompt.text = "Press F: enter chimney"
	if Input.is_action_just_pressed("interact"):
		enter(h)


## Fire the Icer down the flue from the roof (frost pours down the chimney).
func roof_icer(h: Node3D, delta: float) -> void:
	if _roof_frost == null:
		var c := Color(0.75, 0.95, 1.0)
		_roof_frost = FX.make("flake", 90, 0.9, 0.12, [Color(c, 0.0), Color(1, 1, 1, 1), Color(c, 0.5), Color(c, 0.0)],
				{"dir": Vector3(0, -1, 0), "spread": 12.0, "vmin": 3.0, "vmax": 5.0, "add": true, "spin": 120.0, "box": Vector3(0.15, 0.05, 0.15)})
		(main as Node3D).add_child(_roof_frost)
	_roof_frost.global_position = (h.call("get_chimney_top_world") as Vector3) + Vector3(0, 0.4, 0)
	_roof_frost.emitting = true
	_roof_icer_t = Time.get_ticks_msec() / 1000.0
	gadgets.apply_icer(delta, h)


# =================================================================================================
# Entry
# =================================================================================================

func _w(h: Node3D, local: Vector3) -> Vector3:
	return h.to_global(local)


func _shaft_points(h: Node3D) -> Array:
	var base: Vector3 = h.get("chimney_base")
	var top := base + Vector3(0, float(h.get("chimney_height")), 0)
	var fi: Dictionary = h.get("flue_info")
	if fi.has("liner_bottom"):
		return [_w(h, top), _w(h, fi.liner_bottom)]
	var it: Node3D = h.get("interior")
	var bottom := Vector3(base.x, float(it.get("ceiling_top")) + 0.1, base.z)
	return [_w(h, top), _w(h, bottom)]


func enter(h: Node3D) -> void:
	if mode != Mode.SLEIGH:
		return
	house = h
	mode = Mode.CUTSCENE
	gadgets.prompt.text = ""
	sleigh.set("controls_enabled", false)
	sleigh.freeze = true
	print("[mission] entering %s" % h.name)
	var g := _chim_geo(h)
	var mouth: Vector3 = g.mouth
	var fwd: Vector3 = g.fwd
	var side: Vector3 = g.side
	var rim: Vector3 = g.rim
	var bottom: Vector3 = (_shaft_points(h)[1] as Vector3)
	var fs := float(h.get("flue_size"))
	# 1) hop from the sleigh onto the crown, at the edge of the open flue
	cut_phase = "hop"
	elf.visible = true
	elf.puppet = true
	elf.control_enabled = false
	elf.pose = ""
	var start := sleigh.global_position + sleigh.global_basis.x * 0.9 + Vector3(0, 0.2, 0)
	cut_cam.current = true
	cut_cam.fov = 55.0
	var cd := ES.m(rim_cam_distance_eh)
	_cam_rig = [mouth + fwd * cd + side * cd * 0.7 + Vector3(0, ES.m(rim_cam_height_eh), 0), mouth + Vector3(0, -0.15, 0)]
	_cam_apply()
	elf.face(rim - start)
	await _arc(start, rim, hop_time, ES.m(hop_arc_eh))
	elf.face(-fwd)
	await _wait(0.25)
	# 2) a look down the open flue from the crown (a breath of soot drifts up)
	cut_phase = "crown"
	_cam_rig = [mouth + fwd * 0.85 + side * 0.55 + Vector3(0, 0.42, 0), mouth + Vector3(0, -0.05, 0)]
	_cam_apply()
	_soot_puff(mouth + Vector3(0, 0.05, 0), 6)
	await _wait(0.45)
	# 3) peek in: kneel at the lip, goggles glowing green, lighting the sooty bricks
	cut_phase = "peek"
	elf.pose = "peek"
	_goggles(true)
	var lip := mouth + fwd * (fs * 0.5 + 0.015)  # kneeling on the liner's lip
	await _move(rim, lip, 0.35)
	# low from the side at cap level: the elf leaning over the dark flue, goggles lighting the bricks
	# hanging just over the open mouth, looking back at the elf's face peering in
	_cam_rig = [_in_flue(h, mouth - fwd * (fs * 0.5) + side * 0.03 + Vector3(0, -0.2, 0)), lip - fwd * 0.1 + Vector3(0, 0.07, 0)]
	var fill := OmniLight3D.new()  # warm bounce from the flue lighting the elf's face
	fill.light_color = Color(1.0, 0.62, 0.35)
	fill.light_energy = 0.7
	fill.omni_range = 0.7
	(main as Node3D).add_child(fill)
	fill.global_position = mouth - fwd * 0.05 + Vector3(0, -0.3, 0)
	_autofree(fill, 1.6)
	_cam_apply()
	await _wait(1.4)
	# 4) hook the Crook-Line candy cane on the lip, swing over the hole
	cut_phase = "hook"
	elf.pose = "flip"
	_make_hook(mouth + fwd * (fs * 0.5 + 0.017) + Vector3(0, 0.01, 0), -fwd)
	_cam_rig = [mouth + fwd * 0.8 - side * 0.55 + Vector3(0, 0.45, 0), mouth + Vector3(0, 0.0, 0)]
	_cam_apply()
	await _wait(0.45)
	elf.pose = "abseil"
	elf.face(fwd)
	var hang := mouth + fwd * (fs * 0.5 - minf(ES.m(0.9), fs * 0.5)) + Vector3(0, -ES.m(0.9), 0)
	await _arc(lip, hang, 0.5, ES.m(0.8), true)
	# 5) abseil down the tight clay liner: camera above, looking down past the elf to the glow
	cut_phase = "abseil"
	cut_cam.fov = 46.0
	h.call("set_flue_view", true)
	_soot_trail = FX.make("blob", 26, 1.6, 0.05, [Color(0.1, 0.08, 0.08, 0.0), Color(0.12, 0.1, 0.09, 0.8), Color(0.1, 0.08, 0.08, 0.0)],
			{"spread": 25.0, "dir": Vector3(0, -1, 0), "vmin": 0.1, "vmax": 0.35, "gravity": Vector3(0, -0.6, 0), "box": Vector3(fs * 0.4, 0.05, fs * 0.4), "lit": true})
	(main as Node3D).add_child(_soot_trail)
	var stop := Vector3(hang.x, bottom.y + 0.12, hang.z)
	var drop := hang.distance_to(stop)
	if drop + 1.0 > ES.m(crook_line_length_eh):
		push_warning("Crook-Line too short for %s (%.1f m flue, %.1f m line)" % [h.name, drop, ES.m(crook_line_length_eh)])
	var dt := maxf(2.4, drop / ES.m(abseil_speed_eh))
	await _abseil(h, hang, stop, dt, fwd, side, fs)
	# 6) out of the liner into the smoke chamber: the corbelled brick opens out below, the damper
	# and the fire's glow at the bottom
	cut_phase = "chamber"
	var fi: Dictionary = h.get("flue_info")
	var throat_l: Vector3 = fi.throat if fi.has("throat") else h.to_local(stop) + Vector3(0, -0.6, 0)
	var throat := _w(h, throat_l)
	var above := _w(h, throat_l + Vector3(0, 0.16, -0.05))
	var lb := bottom
	var ctop: Vector3 = _w(h, fi.chamber_top) if fi.has("chamber_top") else lb
	# down the offset (if any) to the top of the chamber, then into the widening chamber
	var path := [stop, ctop + Vector3(0, 0.1, 0), above]
	var cam_poly: Array = [stop + Vector3(0, 0.5, 0), stop, path[1], above]
	var total_len := stop.distance_to(path[1]) + (path[1] as Vector3).distance_to(above)
	var el := 0.0
	var tch := 0.9 + stop.distance_to(ctop) / maxf(ES.m(abseil_speed_eh), 0.1)
	while el < tch:
		var k := el / tch
		var e := k * k * (3.0 - 2.0 * k)
		var seg := stop.distance_to(path[1]) / maxf(stop.distance_to(path[1]) + (path[1] as Vector3).distance_to(above), 0.01)
		var p := (stop as Vector3).lerp(path[1], e / seg) if e < seg else (path[1] as Vector3).lerp(above, (e - seg) / (1.0 - seg))
		elf.global_position = p
		_update_line()
		# camera trails 0.5 m behind the elf ALONG the flue (so it follows the liner's offset instead
		# of going straight up into the bricks), then hangs in the top of the chamber looking down
		var trail := _along(cam_poly, (e * total_len))  # cam_poly is the elf's path with 0.5 m of liner above it
		var cam_p := trail.lerp(ctop + Vector3(0, 0.05, 0) + side * fs * 0.15, clampf((e - seg) / maxf(1.0 - seg, 0.01) * 1.5, 0.0, 1.0))
		cut_cam.look_at_from_position(cam_p, p + Vector3(0, -0.3, 0) + side * 0.001, Vector3.UP)
		await get_tree().process_frame
		el += get_process_delta_time()
	# 7) squeeze past the damper plate beside the smoke shelf
	cut_phase = "damper"
	await _tween_damper(h, 1.0, 1.0, 0.2)
	await _move(above, _w(h, throat_l + Vector3(0, -0.12, -0.05)), 0.35, true)
	# 8) drop into the firebox; peek out past the grate in the green mist
	cut_phase = "fireplace"
	h.call("set_flue_view", false)
	_clear_hook()
	if _soot_trail:
		_soot_trail.queue_free()
		_soot_trail = null
	h.call("set_damper", 1.0)
	var it: Node3D = h.get("interior")
	var fp := _w(h, it.get("fireplace_spawn"))
	var hearth := _w(h, it.get("hearth_point"))
	var out := (hearth - fp)
	out.y = 0
	out = out.normalized()
	# beside the log grate, just inside the opening, on the side the camera sees
	_cam_rig = _hearth_cam(h, fp, out)
	_cam_apply()
	var fside := out.cross(Vector3.UP)
	var cam_side := signf(fside.dot((_cam_rig[0] as Vector3) - fp))
	if cam_side == 0.0:
		cam_side = 1.0
	var peek := fp + out * 0.1 - fside * 0.34 * cam_side
	_cam_rig[1] = (_cam_rig[1] as Vector3) - fside * cam_side * 0.14
	_cam_apply()
	elf.global_position = peek + Vector3(0, ES.m(1.5), 0)
	elf.face(out + fside * cam_side * 0.6)
	elf.pose = "grate_peek"
	cut_cam.fov = 50.0
	_cam_rig[1] = (_cam_rig[1] as Vector3).lerp(peek + Vector3(0, 0.3, 0), 0.45)
	_cam_apply()
	var mist := FX.green_mist(40)
	h.add_child(mist)
	mist.global_position = fp - out * 0.05 + Vector3(0, 0.05, 0)
	mist.scale = Vector3.ONE * 1.1
	FX.burst(mist)
	_autofree(mist, 4.5)
	_soot_puff(fp + Vector3(0, 0.5, 0), 10, h)
	await _move(elf.global_position, peek, 0.22)
	await _wait(1.5)
	elf.pose = ""
	_goggles(false)
	elf.face(out)
	await _move(peek, hearth, creep_time)
	# 9) hand over control
	cut_phase = "elf"
	cut_cam.fov = 62.0
	elf.global_position = hearth + Vector3(0, 0.05, 0)
	elf.velocity = Vector3.ZERO
	elf.puppet = false
	elf.control_enabled = true
	elf.call("activate_camera")
	elf.cam_yaw.rotation.y = atan2(-out.x, -out.z)
	elf.cam_yaw.global_position = elf.global_position + Vector3(0, float(elf.get("camera_height")), 0)
	gadgets.begin(h, elf)
	if not scripted:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mode = Mode.ELF
	gadgets.flash("You're in. WASD sneak  Ctrl crouch  1-8 gadgets  N Glow-Gogs  F at the hearth to leave", Color(0.6, 1.0, 0.6), 5.0)
	print("[mission] elf inside %s" % h.name)


## Chimney geometry for the cutscene, following the stack's lean: flue mouth centre, the
## front direction (fwd), a side vector and where the elf lands on the cap.
func _chim_geo(h: Node3D) -> Dictionary:
	var mouth: Vector3 = h.call("get_chimney_mouth_world")
	var m: Node3D = h.get("chimney_model")
	var fwd := Vector3.BACK
	if m:
		fwd = m.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	var fs := float(h.get("flue_size"))
	var liner := 0.05 if m == null else float(m.get("mouth_y")) - float(m.get("height"))
	var rim := mouth + fwd * (fs * 0.5 + 0.035 + ES.radius() + 0.07) + Vector3(0, -liner - 0.008, 0)
	return {"mouth": mouth, "fwd": fwd, "side": side, "rim": rim}


## A camera for the firebox emergence: low on the hearth, off to one side, framing the firebox,
## the stockings on the mantel and (when possible) the tree. Picks a spot with a clear view.
func _hearth_cam(h: Node3D, fp: Vector3, out: Vector3) -> Array:
	var side := out.cross(Vector3.UP)
	var it: Node3D = h.get("interior")
	var pref := 1.0
	var tree = it.get("tree_pos")
	if tree is Vector3 and tree != Vector3.ZERO:
		pref = signf(side.dot(_w(h, tree) - fp))
		if pref == 0.0:
			pref = 1.0
	var target := fp + Vector3(0, 0.5, 0) + out * 0.05
	var space := (main as Node3D).get_world_3d().direct_space_state
	var best: Array = []
	var probe := SphereShape3D.new()
	probe.radius = 0.2
	var best_score := 1 << 20
	for cand in [[1.7, 0.35, 0.8], [1.55, 0.25, 0.7], [1.6, 0.5, 0.95], [1.3, 0.4, 0.45], [1.15, 0.3, 0.42], [1.0, 0.25, 0.38], [1.25, 0.2, 0.5], [0.95, 0.15, 0.36], [1.4, 0.85, 0.42], [1.3, 0.5, 0.45], [1.1, 0.4, 0.8], [1.3, 0.3, 0.85], [0.9, 0.3, 0.7], [0.8, 0.3, 0.3], [0.7, 0.25, 0.28]]:
		for sg: float in [pref, -pref]:
			var p: Vector3 = fp + out * float(cand[0]) + side * float(cand[1]) * sg + Vector3(0, float(cand[2]), 0)
			var score := 0
			# low sight lines too, so a coffee table between the camera and the hearth counts.
			# A high camera looks down over furniture, so its rays go straight from the lens.
			for hy in [0.1, 0.25, minf(float(cand[2]), 0.6), 0.6]:
				var a2 := Vector3(fp.x, fp.y + hy, fp.z) + out * 0.45
				var b2 := Vector3(p.x, fp.y + hy, p.z) if float(cand[2]) < 0.65 else p
				if not space.intersect_ray(PhysicsRayQueryParameters3D.create(a2, b2, 4)).is_empty():
					score += 3
			# and nothing in the shot: rays from the camera across the fireplace front
			var up := Vector3.UP
			for o in [side * 0.5, -side * 0.5, up * 0.35 + side * 0.4, up * 0.35 - side * 0.4, -up * 0.3 + side * 0.3, -up * 0.3 - side * 0.3]:
				var tp: Vector3 = fp + out * 0.48 + Vector3(0, 0.45, 0) + o
				if not space.intersect_ray(PhysicsRayQueryParameters3D.create(p, tp, 4)).is_empty():
					score += 1
			# straight in front of a brick jamb the jamb fills half the frame
			if absf(float(cand[1])) > 0.45 and absf(float(cand[1])) < 1.05 and float(cand[0]) < 1.6:
				score += 2
			var sq := PhysicsShapeQueryParameters3D.new()
			sq.shape = probe
			sq.transform = Transform3D(Basis(), p)
			sq.collision_mask = 4
			if not space.intersect_shape(sq, 1).is_empty():
				score += 10
			if score == 0:
				print("chimcam: clear ", cand, " side ", sg)
				return [p, target]
			if score < best_score:
				best_score = score
				best = [p, target]
	if best.is_empty():
		best = [fp + out * 0.6 + Vector3(0, 0.3, 0), target]
	print("chimcam: best score ", best_score)
	return best


## Keep a camera point inside the flue (well clear of the bricks, near plane included) when it is
## below the flue mouth; points above the mouth are left alone.
func _in_flue(h: Node3D, p: Vector3, margin := 0.075) -> Vector3:
	var mouth: Vector3 = h.call("get_chimney_mouth_world")
	if p.y > mouth.y - 0.01:
		return p
	var ax: Vector3 = h.call("flue_axis_world", p.y)
	var half := float(h.get("flue_size")) * 0.5 - margin
	var lp := h.global_basis.inverse() * (p - ax)
	lp.x = clampf(lp.x, -half, half)
	lp.z = clampf(lp.z, -half, half)
	return ax + h.global_basis * lp


## Point at arc length d along a polyline.
func _along(poly: Array, d: float) -> Vector3:
	for i in poly.size() - 1:
		var a: Vector3 = poly[i]
		var b: Vector3 = poly[i + 1]
		var l := a.distance_to(b)
		if d <= l or i == poly.size() - 2:
			return a.lerp(b, clampf(d / maxf(l, 0.0001), 0.0, 1.0))
		d -= l
	return poly[-1]


func _cam_apply() -> void:
	if _cam_rig.size() == 2:
		cut_cam.look_at_from_position(_cam_rig[0], _cam_rig[1], Vector3.UP)


## Controlled descent: feet on the front wall, short kick-off hops, braking; camera hangs above.
func _abseil(h: Node3D, a: Vector3, b: Vector3, t: float, fwd: Vector3, side: Vector3, fs: float) -> void:
	var el := 0.0
	while true:
		var k := clampf(el / t, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		var hop := absf(sin(k * PI * 4.0)) * minf(ES.m(0.9), fs * 0.2) * (1.0 - k * 0.5)
		var p := a.lerp(b, e) - fwd * hop
		elf.global_position = p
		_update_line()
		if _soot_trail:
			_soot_trail.global_position = p + Vector3(0, ES.m(2.5), 0)
		var cam := _in_flue(h, p + Vector3(0, 0.58, 0) - fwd * (fs * 0.3) + side * (fs * 0.22))
		cut_cam.look_at_from_position(cam, p + Vector3(0, -0.3, 0) + fwd * 0.03, Vector3.UP)
		if k >= 1.0:
			break
		await get_tree().process_frame
		el += get_process_delta_time()


func _tween_damper(h: Node3D, a: float, b: float, t: float) -> void:
	var el := 0.0
	while el < t:
		h.call("set_damper", lerpf(a, b, el / t))
		await get_tree().process_frame
		el += get_process_delta_time()
	h.call("set_damper", b)


func _goggles(on: bool) -> void:
	if on and _gog_beam == null:
		# a soft night-vision glow round the elf (no hard-edged spotlight pool on the bricks): a
		# wide, dim, pale-green wash that fades out with distance
		_gog_beam = SpotLight3D.new()
		_gog_beam.light_color = Color(0.72, 1.0, 0.78)
		_gog_beam.light_energy = 0.35
		_gog_beam.spot_range = ES.m(4.0)
		_gog_beam.spot_angle = 70.0
		_gog_beam.spot_angle_attenuation = 0.35
		_gog_beam.spot_attenuation = 2.4
		_gog_beam.shadow_enabled = false
		var head: Node3D = elf.get("head")
		(head if head else elf).add_child(_gog_beam)
		_gog_beam.position = Vector3(0, 0.1, -0.12)
	if _gog_beam:
		_gog_beam.visible = on
	var gl: OmniLight3D = elf.get("goggle_light")
	if gl:
		gl.light_color = Color(0.72, 1.0, 0.78) if on else Color(0.4, 1.0, 0.35)
		gl.light_energy = 0.12 if on else float(elf.get("goggle_light_energy"))
		gl.omni_range = ES.m(1.6) if on else ES.m(float(elf.get("goggle_light_range_eh")))


func _soot_puff(at: Vector3, amount: int, parent: Node = null) -> void:
	var c := Color(0.2, 0.18, 0.17)
	var soot := FX.make("blob", amount, 1.1, 0.09, [Color(c, 0.0), Color(c, 0.65), Color(c, 0.35), Color(c, 0.0)],
			{"one_shot": true, "explosive": 0.9, "spread": 50.0, "dir": Vector3(0, 1, 0), "vmin": 0.15, "vmax": 0.5,
			"gravity": Vector3(0, -0.3, 0), "damp": 1.2, "box": Vector3(0.15, 0.02, 0.15), "lit": true,
			"scale_curve": [Vector2(0, 0.5), Vector2(0.4, 1.0), Vector2(1, 1.5)]})
	(parent if parent else main).add_child(soot)
	soot.global_position = at
	FX.burst(soot)
	_autofree(soot, 2.5)


## F at the hearth. Warns first if you'd leave evidence; F again (within a few seconds) climbs out anyway.
func try_exit(force := false) -> bool:
	if mode != Mode.ELF:
		return false
	var hearth := _w(house, (house.get("interior") as Node).get("hearth_point"))
	if Vector2(elf.global_position.x - hearth.x, elf.global_position.z - hearth.z).length() > float(gadgets.call("hearth_radius")):
		return false
	var probs: Array = gadgets.exit_problems()
	var now := Time.get_ticks_msec() / 1000.0
	if not probs.is_empty() and not force and now > _exit_confirm_until:
		_exit_confirm_until = now + exit_confirm_window
		gadgets.flash("%s\nPress F again to climb out anyway (it'll make the papers)" % "\n".join(probs), Color(1, 0.45, 0.3), exit_confirm_window)
		print("[mission] exit warning: %s" % ", ".join(probs))
		return false
	exit_house()
	return true


func exit_house() -> void:
	mode = Mode.CUTSCENE
	_exit_confirm_until = 0.0
	var h := house
	var ev: Dictionary = gadgets.end()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elf.control_enabled = false
	elf.puppet = true
	elf.auto_target = Vector3.INF
	var it: Node3D = h.get("interior")
	var fp := _w(h, it.get("fireplace_spawn"))
	var hearth := _w(h, it.get("hearth_point"))
	var out := (hearth - fp)
	out.y = 0
	out = out.normalized()
	cut_phase = "exit_fireplace"
	cut_cam.current = true
	_cam_rig = _hearth_cam(h, fp, out)
	_cam_apply()
	elf.face(-out)
	await _move(elf.global_position, fp, 0.7)
	var mist := FX.green_mist(20)
	h.add_child(mist)
	mist.global_position = fp + Vector3(0, 0.15, 0)
	FX.burst(mist)
	_autofree(mist, 4.0)
	await _wait(0.3)
	var g := _chim_geo(h)
	var mouth: Vector3 = g.mouth
	var fwd: Vector3 = g.fwd
	var side: Vector3 = g.side
	var bottom: Vector3 = (_shaft_points(h)[1] as Vector3)
	var fs := float(h.get("flue_size"))
	# winch up the open flue
	cut_phase = "winch"
	h.call("set_flue_view", true)
	elf.pose = "abseil"
	elf.face(fwd)
	_make_hook(mouth + fwd * (fs * 0.5 + 0.017) + Vector3(0, 0.01, 0), -fwd)
	_cam_rig = [mouth + fwd * 1.3 - side * 0.9 + Vector3(0, 0.75, 0), mouth + Vector3(0, -0.1, 0)]
	_cam_apply()
	var hang := mouth + fwd * (fs * 0.5 - minf(ES.m(0.9), fs * 0.5)) + Vector3(0, -ES.m(0.9), 0)
	var from := Vector3(hang.x, bottom.y, hang.z)
	var wt := from.distance_to(hang) / ES.m(winch_speed_eh)
	await _move(from, hang, wt if not bool(h.get("fire_lit")) else wt * 0.7, true)
	# climb out onto the crown and unhook
	cut_phase = "climb_out"
	h.call("set_flue_view", false)
	var rim: Vector3 = g.rim
	await _arc(hang, rim, 0.4, ES.m(1.2), true)
	_clear_hook()
	_soot_puff(mouth + Vector3(0, 0.08, 0), 8)
	elf.pose = ""
	await _wait(0.2)
	var seat := sleigh.global_position + sleigh.global_basis.x * 0.9 + Vector3(0, 0.2, 0)
	elf.face(seat - rim)
	await _arc(rim, seat, hop_time, ES.m(hop_arc_eh))
	elf.visible = false
	elf.global_position = Vector3(0, -50, 0)
	cut_cam.fov = 62.0
	sleigh.freeze = false
	sleigh.set("controls_enabled", true)
	chase_cam.current = true
	if chase_cam.has_method("snap"):
		chase_cam.call("snap")
	cut_phase = ""
	mode = Mode.SLEIGH
	if (ev.problems as Array).is_empty():
		gadgets.flash("Clean getaway from %s!" % h.name, Color(0.6, 1.0, 0.6), 3.0)
	else:
		gadgets.flash("EVIDENCE LEFT: %s" % ", ".join(ev.problems), Color(1, 0.45, 0.3), 4.0)
	print("[mission] back on the sleigh from %s" % h.name)


# =================================================================================================
# Cutscene helpers
# =================================================================================================

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _move(a: Vector3, b: Vector3, t: float, line := false) -> void:
	var el := 0.0
	while true:
		var k := clampf(el / t, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		elf.global_position = a.lerp(b, e)
		if line and _hook:
			_update_line()
		if k >= 1.0:
			break
		await get_tree().process_frame
		el += get_process_delta_time()


func _arc(a: Vector3, b: Vector3, t: float, h: float, line := false) -> void:
	var el := 0.0
	while true:
		var k := clampf(el / t, 0.0, 1.0)
		elf.global_position = a.lerp(b, k) + Vector3(0, sin(k * PI) * h, 0)
		if line and _hook:
			_update_line()
		if k >= 1.0:
			break
		await get_tree().process_frame
		el += get_process_delta_time()


## Crook-Line: the candy-cane hook hooked over a lip at `at`, its long leg hanging toward `into`.
func _make_hook(at: Vector3, into := Vector3.FORWARD) -> void:
	_clear_hook()
	_hook = Node3D.new()
	(main as Node3D).add_child(_hook)
	_hook.global_position = at
	into.y = 0
	if into.length() > 0.01:
		_hook.look_at(at + into.normalized(), Vector3.UP)
	_hook.scale = Vector3.ONE * (ES.ELF_HEIGHT / 0.55)  # modelled for a 0.55 m elf; scaled to the current one
	var red := Color(0.95, 0.1, 0.12)
	var white := Color(1, 0.97, 0.95)
	# crook over the lip, long striped leg hanging inside (-z), short tip outside (+z)
	GB.torus(_hook, 0.06, 0.11, Vector3(0.0, 0.07, 0.0), red, Vector3(0, 0, 90))
	for k in 5:
		GB.cylinder(_hook, 0.025, 0.025, 0.06, Vector3(0, 0.04 - k * 0.06, -0.085), red if k % 2 == 0 else white)
	GB.cylinder(_hook, 0.025, 0.02, 0.06, Vector3(0, 0.04, 0.085), white)
	_line = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = ES.m(0.015)  # 3.3 mm tactical cord
	cm.bottom_radius = ES.m(0.015)
	cm.height = 1.0
	cm.radial_segments = 6
	_line.mesh = cm
	_line.material_override = GB.mat(Color(0.2, 0.22, 0.16), 0.0, 0.1)  # olive-drab kernmantle (no glow)
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(main as Node3D).add_child(_line)
	for n in _hook.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = 3
	_line.layers = 3
	_update_line()


func _update_line() -> void:
	if _line == null:
		return
	var a := _hook.to_global(Vector3(0, -0.24, -0.085))
	var b := elf.global_position + Vector3(0, ES.m(line_grip_eh), 0)
	var len := maxf(0.01, a.distance_to(b))
	_line.global_position = (a + b) * 0.5
	var d := (b - a) / len
	_line.global_basis = Basis(Quaternion(Vector3.UP, d)) if absf(d.y) < 0.999 else Basis()
	_line.scale = Vector3(1, len, 1)


func _clear_hook() -> void:
	if _hook:
		_hook.queue_free()
		_hook = null
	if _line:
		_line.queue_free()
		_line = null


func _autofree(n: Node, t: float) -> void:
	get_tree().create_timer(t).timeout.connect(n.queue_free)
