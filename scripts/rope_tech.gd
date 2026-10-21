extends Node3D
## Crook-Line tactical rope tech, scaled to a 0.22 m elf (every distance in elf heights, "eh").
## A wrist launcher (dark green / black, candy-cane red band) fires a thin cable with a small claw hook.
##   T / middle mouse / left trigger: fire at the green reticle anchor (or let go).
##     - a LEDGE anchor right at your feet (bookshelf top, mantel, stair rail) = RAPPEL down it:
##       S lowers (the braking hand lets the rope run), W climbs, nothing = brake and hang,
##       Space = kick-off hop, Ctrl = flip upside down to peek; you unclip at the floor.
##     - any other anchor (light fitting, curtain rod, banister, tree branch, a far ledge) = GRAPPLE:
##       hang and swing. WASD pumps the swing, Space reels in, Ctrl pays out, T lets go (quietly).
##       Reel all the way up to a ledge anchor and you mantle onto it.
##   B: zipline. First B fixes anchor A where the reticle points, second B fixes anchor B. The line
##     must run downhill and be clear. Then B near the top end clips the hand trolley on and slides you
##     down. H reels a zipline back in. A zipline left up counts as evidence when you climb out.
##   Space next to a marked climbable (bookshelf, curtain, Christmas tree, brick fireplace front) grabs it:
##     WASD climbs / shimmies, the grip runs down while you hang, W at the top mantles onto it
##     (bookshelf, mantel), Space or Ctrl lets go.
## The chimney abseil (chimney_entry.gd) uses the same Crook-Line (candy-cane hook on the lip).

const ES := preload("res://scripts/elf_size.gd")
const GB := preload("res://scripts/greybox.gd")

@export_group("Crook-Line (elf heights)")
@export var grapple_range_eh := 18.0  ## Reticle turns green on anchors this close, eh (3.96 m).
@export var rappel_reach_eh := 3.0  ## A ledge anchor this close to your feet means rappel, eh (0.66 m).
@export var zip_range_eh := 30.0  ## Each zipline anchor shot, eh (6.6 m).
@export var zip_mount_eh := 3.0  ## Clip on to a zipline's top end from this close, eh (0.66 m).
@export var retrieve_reach_eh := 5.0  ## Reel a zipline in from this close to it, eh (1.1 m).
@export var reel_speed_eh := 6.0  ## Reel in / pay out, eh/s (1.32 m/s).
@export var rappel_speed_eh := 5.0  ## Lowering speed with the brake hand open, eh/s (1.1 m/s).
@export var rappel_climb_eh := 2.0  ## Ascending a rappel line, eh/s (0.44 m/s).
@export var kick_out_eh := 1.0  ## Kick-off hop push away from the wall, eh (0.22 m).
@export var min_rope_eh := 1.0  ## Shortest the cable reels to, eh (0.22 m).
@export var hang_eh := 1.15  ## Hands (cable clip) above the feet when hanging, eh (0.25 m).
@export var swing_pump := 2.2  ## Swing pump, m/s^2 along the swing.
@export var swing_damp := 0.45  ## Air drag on the swing (per second): weighty, settles, no flips.
@export var zip_max_speed_eh := 14.0  ## Hand-trolley top speed, eh/s (3.08 m/s).
@export var zip_friction := 0.9  ## Trolley rolling drag, m/s^2.
@export var zip_min_slope := 0.06  ## The line must drop at least this much per metre...
@export var zip_max_slope := 1.2  ## ...and no more than this (steeper = just rappel).
@export_group("Climbing (elf heights)")
@export var climb_speed_eh := 2.5  ## Up / down, eh/s (0.55 m/s).
@export var shimmy_speed_eh := 2.0  ## Sideways, eh/s (0.44 m/s).
@export var climb_reach_eh := 1.2  ## Grab a climbable face from this close, eh (0.26 m).
@export var stamina_max := 7.0  ## Grip, in seconds of climbing.
@export var stamina_hold_drain := 0.35  ## Grip used per second hanging still (moving uses 1.0).
@export var stamina_regen := 1.5  ## Grip back per second on the ground.
@export_group("Noise / visibility")
@export var climb_noise_eh := 3.0  ## eh (0.66 m)
@export var rope_noise_eh := 2.0  ## Hanging / rappelling, eh (0.44 m)
@export var zip_noise_eh := 5.0  ## The trolley whirr, eh (1.1 m)
@export var rope_visibility := 1.15  ## Hanging out in the open is easier to spot.

enum S {NONE, GRAPPLE, RAPPEL, ZIP, CLIMB, MANTLE}
var state := S.NONE
var elf: CharacterBody3D
var house: Node3D
var interior: Node3D
var gadgets: Node
var anchor := Vector3.ZERO
var anchor_n := Vector3.ZERO
var anchor_kind := ""
var rope_len := 0.0
var vel := Vector3.ZERO
var inverted := false
var zip_lines: Array = []  ## {a: Vector3, b: Vector3 (a is the high end), node: Node3D}
var zip_a := Vector3.INF  ## first zipline anchor waiting for its second
var stamina := 7.0
var aim: Dictionary = {}  ## the reticle target: {pos, kind, normal, name} or empty
var drive: Dictionary = {}  ## scripted inputs (checks): pump: Vector3, reel: float, descend: float, climb: Vector2
var log_events: Array = []
var _kick := 0.0
var _y := 0.0
var _zip: Dictionary = {}
var _zip_t := 0.0
var _zip_v := 0.0
var _climb: Dictionary = {}
var _cu := 0.0
var _cy := 0.0
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _mantle_t := 0.0
var _retract := 0.0
var _retract_from := Vector3.ZERO
var _cable: MeshInstance3D
var _hook: Node3D
var _pending_hook: Node3D
var _trolley: Node3D
var _launcher: Node3D
var _snd: AudioStreamPlayer3D
var _whirr: AudioStreamPlayer3D
var _ui: CanvasLayer
var _grip: Label
var _cable_mat: StandardMaterial3D
static var _thwip_wav: AudioStreamWAV
static var _whirr_wav: AudioStreamWAV


func grapple_range() -> float:
	return ES.m(grapple_range_eh)


func zip_range() -> float:
	return ES.m(zip_range_eh)


func busy() -> bool:
	return state != S.NONE


func state_name() -> String:
	return ["none", "grapple", "rappel", "zip", "climb", "mantle"][state]


# =================================================================================================
# Setup
# =================================================================================================

func _ready() -> void:
	top_level = true
	_cable_mat = StandardMaterial3D.new()
	_cable_mat.albedo_color = Color(0.06, 0.07, 0.06)
	_cable_mat.roughness = 0.5
	_cable = _make_cable()
	_cable.visible = false
	_ui = CanvasLayer.new()
	_ui.layer = 6
	add_child(_ui)
	_grip = Label.new()
	_grip.add_theme_font_size_override("font_size", 18)
	_grip.add_theme_constant_override("outline_size", 6)
	_grip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_grip.anchor_left = 0.5
	_grip.anchor_right = 0.5
	_grip.anchor_top = 0.66
	_grip.anchor_bottom = 0.66
	_grip.offset_left = -90
	_grip.offset_right = 90
	_grip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grip.visible = false
	_ui.add_child(_grip)
	if _thwip_wav == null:
		_thwip_wav = _synth_thwip()
		_whirr_wav = _synth_whirr()


func begin(h: Node3D, e: CharacterBody3D, g: Node) -> void:
	house = h
	interior = h.get("interior")
	elf = e
	gadgets = g
	state = S.NONE
	stamina = stamina_max
	zip_a = Vector3.INF
	elf.set("jump_override", Callable(self, "try_grab"))
	if _launcher == null or not is_instance_valid(_launcher):
		_launcher = _make_launcher()
	if _snd == null or not is_instance_valid(_snd):
		_snd = AudioStreamPlayer3D.new()
		_snd.max_distance = 8.0
		_snd.unit_size = 1.5
		elf.add_child(_snd)
		_whirr = AudioStreamPlayer3D.new()
		_whirr.max_distance = 8.0
		_whirr.unit_size = 1.2
		_whirr.volume_db = -8.0
		elf.add_child(_whirr)


## Climbing out: let go of everything. Ziplines stay up (they're evidence) until the house is left.
func end() -> void:
	_detach()
	for z in zip_lines:
		if is_instance_valid(z.node):
			(z.node as Node3D).queue_free()
	zip_lines.clear()
	_clear_pending()
	_grip.visible = false


func lines_left() -> int:
	return zip_lines.size()


func anchors_world() -> Array:
	var out := []
	if interior == null:
		return out
	for a in interior.get("rope_anchors"):
		out.append({"pos": interior.to_global(a.pos), "kind": a.kind, "name": a.name,
				"normal": (interior.global_basis * (a.normal as Vector3)).normalized() if (a.normal as Vector3) != Vector3.ZERO else Vector3.ZERO})
	return out


# =================================================================================================
# Per frame
# =================================================================================================

func _hand() -> Vector3:
	return elf.global_position + Vector3(0, ES.m(hang_eh), 0)


func _in_vec() -> Vector2:
	if drive.has("climb"):
		return drive.climb
	return Input.get_vector("elf_left", "elf_right", "elf_fwd", "elf_back")


func _pressed(action: String) -> bool:
	return bool(elf.get("control_enabled")) and Input.is_action_just_pressed(action)


func _held(action: String) -> bool:
	return bool(elf.get("control_enabled")) and Input.is_action_pressed(action)


## Called from gadgets._process while the elf mission is active.
func tick(_delta: float) -> void:
	if elf == null:
		return
	_update_aim()
	if _pressed("rope_fire"):
		fire()
	if _pressed("rope_zip"):
		zip_press()
	if _pressed("rope_retrieve"):
		retrieve()
	if state == S.RAPPEL:
		if _pressed("elf_jump"):
			kick()
		if _pressed("elf_crouch"):
			set_inverted(not inverted)
	elif state == S.CLIMB:
		if _pressed("elf_jump") or _pressed("elf_crouch"):
			let_go("Let go")
	elif state == S.ZIP:
		if _pressed("elf_jump"):
			_zip_off(true)


func _physics_process(delta: float) -> void:
	if elf == null or not is_instance_valid(elf):
		return
	match state:
		S.GRAPPLE:
			_step_grapple(delta)
		S.RAPPEL:
			_step_rappel(delta)
		S.ZIP:
			_step_zip(delta)
		S.CLIMB:
			_step_climb(delta)
		S.MANTLE:
			_step_mantle(delta)
		_:
			if elf.is_on_floor():
				stamina = minf(stamina_max, stamina + stamina_regen * delta)
	_update_visuals(delta)
	_grip.visible = state == S.CLIMB or (stamina < stamina_max - 0.05 and gadgets != null and bool(gadgets.get("active")))
	if _grip.visible:
		var n := int(round(8.0 * stamina / stamina_max))
		_grip.text = "Grip " + "▮".repeat(n) + "▯".repeat(8 - n)
		_grip.modulate = Color(1, 1, 1, 0.9) if stamina > stamina_max * 0.3 else Color(1, 0.45, 0.35, 1)


## Reticle: green on a valid anchor in range with a clear line from the launcher.
func _update_aim() -> void:
	aim = {}
	if state == S.NONE or state == S.GRAPPLE:
		var anchors := anchors_world()
		var pts := []
		for a in anchors:
			pts.append(a.pos)
		var i: int = gadgets.call("aimed", pts, ES.m(0.6), grapple_range())
		if i >= 0 and _clear(_hand(), anchors[i].pos):
			aim = anchors[i]
			aim["rappel"] = _rappel_ok(aim)
	var ch: Label = gadgets.get("crosshair")
	if ch:
		var zip_pending := zip_a != Vector3.INF
		if not aim.is_empty():
			ch.modulate = Color(0.35, 1.0, 0.45, 1.0)
			ch.text = "⊕" if aim.get("rappel", false) else "+"
		elif zip_pending:
			ch.modulate = Color(1.0, 0.85, 0.35, 0.95)
			ch.text = "+"
		else:
			ch.modulate = Color(1, 1, 1, 0.8)
			ch.text = "+"


func _clear(a: Vector3, b: Vector3) -> bool:
	var space := elf.get_world_3d().direct_space_state
	var d := b - a
	if d.length() < 0.05:
		return true
	var q := PhysicsRayQueryParameters3D.create(a, b - d.normalized() * 0.06, 4)
	q.exclude = [elf.get_rid()]
	return space.intersect_ray(q).is_empty()


func _rappel_ok(a: Dictionary) -> bool:
	if a.kind != "ledge":
		return false
	var p: Vector3 = a.pos
	var f := elf.global_position
	var flat := Vector2(p.x - f.x, p.z - f.z).length()
	return flat < ES.m(rappel_reach_eh) and f.y > p.y - ES.m(0.6) and f.y < p.y + ES.m(1.0)


# =================================================================================================
# Fire / grapple / rappel
# =================================================================================================

## T: fire at the reticle anchor, or let go of whatever you're on.
func fire() -> bool:
	match state:
		S.GRAPPLE, S.RAPPEL:
			let_go("Unclipped")
			return true
		S.ZIP:
			_zip_off(true)
			return true
		S.CLIMB, S.MANTLE:
			return false
	if aim.is_empty():
		gadgets.call("flash", "No anchor in range (%.1f m)" % grapple_range(), Color(1, 0.8, 0.5), 1.2)
		return false
	return fire_at(aim)


func fire_at(a: Dictionary) -> bool:
	_thwip()
	if _rappel_ok(a):
		_start_rappel(a)
	else:
		_start_grapple(a)
	return true


func _start_grapple(a: Dictionary) -> void:
	anchor = a.pos
	anchor_kind = a.kind
	anchor_n = a.get("normal", Vector3.ZERO)
	_place_hook(anchor, (anchor - _hand()).normalized())
	rope_len = clampf(_hand().distance_to(anchor), ES.m(min_rope_eh), grapple_range() * 1.1)
	vel = elf.velocity
	state = S.GRAPPLE
	_ext(true, "hang", rope_noise_eh)
	_event("grapple " + str(a.name))


func _start_rappel(a: Dictionary) -> void:
	anchor = a.pos
	anchor_kind = "ledge"
	var n: Vector3 = a.normal
	n.y = 0
	anchor_n = n.normalized() if n.length() > 0.01 else (elf.global_position - anchor).normalized() * -1.0
	_place_hook(anchor, -anchor_n)
	# step back over the edge: a short arc from where you stand to just below the lip
	_mantle_from = elf.global_position
	_mantle_to = anchor + anchor_n * (ES.radius() + 0.015) - Vector3(0, ES.m(1.1), 0)
	_mantle_t = 0.0
	_y = _mantle_to.y
	_kick = 0.0
	inverted = false
	state = S.MANTLE
	set_meta("after_mantle", "rappel")
	_ext(true, "abseil", rope_noise_eh)
	elf.call("face", -anchor_n)
	_event("rappel " + str(a.name))


func _step_grapple(delta: float) -> void:
	var g := float(elf.get("gravity"))
	var reel := float(drive.get("reel", 0.0))
	if not drive.has("reel"):
		reel = (1.0 if _held("elf_jump") else 0.0) - (1.0 if _held("elf_crouch") else 0.0)
	var min_len := ES.m(min_rope_eh)
	rope_len = clampf(rope_len - reel * ES.m(reel_speed_eh) * delta, min_len, grapple_range() * 1.1)
	_whirr_on(absf(reel) > 0.1 and rope_len > min_len + 0.001)
	var hand := _hand()
	var to_a := anchor - hand
	var taut := to_a.length() >= rope_len - 0.01
	var pump := Vector3.ZERO
	if drive.has("pump"):
		pump = drive.pump
	elif bool(elf.get("control_enabled")):
		var inp := Input.get_vector("elf_left", "elf_right", "elf_fwd", "elf_back")
		var cy: Node3D = elf.get("cam_yaw")
		pump = Basis(Vector3.UP, cy.rotation.y) * Vector3(inp.x, 0, inp.y)
	if elf.is_on_floor() and not taut:
		# standing on the floor with slack line: walk about on the tether
		var want := pump * float(elf.call("walk_speed")) * 0.6
		vel.x = move_toward(vel.x, want.x, 3.0 * delta)
		vel.z = move_toward(vel.z, want.z, 3.0 * delta)
		vel.y = maxf(vel.y - g * delta, -0.5)
		elf.set("pose", "")
	else:
		vel.y -= g * delta
		if taut and pump.length() > 0.01:
			var n := to_a.normalized()
			var tang := (pump - n * pump.dot(n))
			vel += tang * swing_pump * delta
		vel *= 1.0 - swing_damp * delta
		elf.set("pose", "hang")
	elf.velocity = vel
	elf.move_and_slide()
	vel = elf.velocity
	# the cable: an inequality constraint (it pulls, never pushes)
	hand = _hand()
	var d := hand - anchor
	if d.length() > rope_len:
		var fix := anchor + d.normalized() * rope_len - hand
		var col := elf.move_and_collide(fix)
		var n2 := d.normalized()
		var radial := vel.dot(n2)
		if radial > 0.0:
			vel -= n2 * radial
		if col and fix.y > 0.0 and elf.is_on_floor():
			pass
	# face along the swing (yaw only: weighty, no flips)
	var hv := Vector3(vel.x, 0, vel.z)
	if hv.length() > 0.15:
		elf.call("face", hv)
	# reeled right up to a ledge: haul over it
	if anchor_kind == "ledge" and rope_len <= min_len + 0.005 and _hand().distance_to(anchor) < ES.m(min_rope_eh) + 0.04:
		var n3 := anchor_n if anchor_n != Vector3.ZERO else Vector3.FORWARD
		_mantle_from = elf.global_position
		_mantle_to = anchor - n3 * (ES.radius() + 0.05) + Vector3(0, 0.01, 0)
		_mantle_t = 0.0
		state = S.MANTLE
		set_meta("after_mantle", "none")
		elf.set("pose", "mantle")


func kick() -> void:
	if state == S.RAPPEL and _kick <= 0.0:
		_kick = 1.0
		_event("kick")


func set_inverted(on: bool) -> void:
	inverted = on
	var m: Node3D = elf.get("model")
	if m:
		m.rotation.x = PI if on else 0.0
		m.position.y = ES.m(1.0) if on else 0.0
	elf.set("pose", "hang" if on else "abseil")
	_event("inverted" if on else "upright")


func _step_rappel(delta: float) -> void:
	var down := float(drive.get("descend", 0.0))
	if not drive.has("descend"):
		down = (1.0 if _held("elf_back") else 0.0) - (1.0 if _held("elf_fwd") else 0.0)
	var spd := ES.m(rappel_speed_eh) if down > 0.0 else ES.m(rappel_climb_eh)
	var out := 0.0
	if _kick > 0.0:
		_kick = maxf(0.0, _kick - delta / 0.55)
		out = sin(PI * (1.0 - _kick)) * ES.m(kick_out_eh)
		_y -= ES.m(rappel_speed_eh) * 1.4 * delta
	_y -= down * spd * delta
	_whirr_on(down > 0.1)
	# the floor (or anything) below
	var space := elf.get_world_3d().direct_space_state
	var base := anchor + anchor_n * (ES.radius() + 0.015)
	var q := PhysicsRayQueryParameters3D.create(Vector3(base.x, _y + 0.3, base.z), Vector3(base.x, _y - 3.0, base.z), 4)
	q.exclude = [elf.get_rid()]
	var hit := space.intersect_ray(q)
	var floor_y := float((hit.position as Vector3).y) if not hit.is_empty() else _y - 3.0
	var top := anchor.y - ES.m(0.85)
	if _y > top:
		_y = top
		if down < -0.1:
			# climbed back up to the lip: over the top
			_mantle_from = elf.global_position
			_mantle_to = anchor - anchor_n * (ES.radius() + 0.04) + Vector3(0, 0.01, 0)
			_mantle_t = 0.0
			state = S.MANTLE
			set_meta("after_mantle", "none")
			set_inverted(false)
			elf.set("pose", "mantle")
			return
	var bottom := floor_y + (ES.m(1.0) if inverted else 0.0)
	if _y <= bottom + 0.004:
		_y = bottom
		if not inverted:
			_land(Vector3(base.x, floor_y + 0.005, base.z) + anchor_n * 0.02)
			return
	elf.global_position = Vector3(base.x, _y, base.z) + anchor_n * out
	elf.velocity = Vector3.ZERO
	elf.call("face", -anchor_n if not inverted else anchor_n)


func _land(p: Vector3) -> void:
	elf.global_position = p
	_event("landed")
	_detach()


func let_go(why := "") -> void:
	if state == S.NONE:
		return
	var v := vel if state == S.GRAPPLE else Vector3.ZERO
	_event("let go " + why)
	_detach()
	elf.velocity = v


func _detach() -> void:
	if state == S.NONE and _hook == null:
		return
	if inverted:
		set_inverted(false)
	if state == S.ZIP and _trolley:
		_trolley.visible = false
	state = S.NONE
	_whirr_on(false)
	if elf and is_instance_valid(elf):
		_ext(false, "")
	# the hook flicks loose and the cable whips back into the launcher
	if _hook and is_instance_valid(_hook):
		_retract = 1.0
		_retract_from = _hook.global_position
		_whirr_on(true)


func _ext(on: bool, pose: String, noise_eh := 0.0) -> void:
	elf.set("ext_control", on)
	elf.set("pose", pose)
	elf.set("ext_noise", ES.m(noise_eh) if on else 0.0)
	elf.set("ext_visibility", rope_visibility if on else 1.0)
	elf.set("ext_anim_speed", 0.0)
	if not on:
		elf.velocity = Vector3.ZERO


func _step_mantle(delta: float) -> void:
	_mantle_t = minf(1.0, _mantle_t + delta / 0.5)
	var k := _mantle_t
	var e := k * k * (3.0 - 2.0 * k)
	var p := _mantle_from.lerp(_mantle_to, e)
	p.y += sin(PI * k) * ES.m(0.5)
	elf.global_position = p
	elf.velocity = Vector3.ZERO
	if k >= 1.0:
		var nxt := str(get_meta("after_mantle", "none"))
		if nxt == "rappel":
			state = S.RAPPEL
			elf.set("pose", "abseil")
		else:
			_event("mantled")
			_detach()


# =================================================================================================
# Zipline
# =================================================================================================

## B: anchor A, anchor B, or clip on near a line's top end.
func zip_press() -> void:
	if state == S.ZIP:
		_zip_off(true)
		return
	if state != S.NONE:
		return
	var near := _zip_near_top()
	if not near.is_empty() and zip_a == Vector3.INF:
		ride(near)
		return
	var hit: Dictionary = gadgets.call("ray", 4, zip_range() + 1.0)
	if hit.is_empty() or (hit.position as Vector3).distance_to(elf.global_position) > zip_range():
		gadgets.call("flash", "Nothing to anchor to in range (%.1f m)" % zip_range(), Color(1, 0.8, 0.5), 1.2)
		return
	zip_point((hit.position as Vector3) + (hit.normal as Vector3) * 0.015)


## Fix one zipline anchor (scripted checks call this directly). Returns the new line when it's the second.
func zip_point(p: Vector3) -> Dictionary:
	_thwip()
	if zip_a == Vector3.INF:
		zip_a = p
		_clear_pending()
		_pending_hook = _make_hook()
		add_child(_pending_hook)
		_pending_hook.global_position = p
		gadgets.call("flash", "Zipline anchor A set - now anchor B", Color(0.7, 1, 0.7), 1.6)
		return {}
	var a := zip_a
	var b := p
	if b.y > a.y:
		var t := a
		a = b
		b = t
	var drop := a.y - b.y
	var run := Vector2(a.x - b.x, a.z - b.z).length()
	var why := ""
	if a.distance_to(b) < ES.m(4.0):
		why = "too short"
	elif run < 0.05 or drop / run < zip_min_slope:
		why = "needs to run downhill"
	elif drop / run > zip_max_slope:
		why = "too steep: rappel instead"
	elif not _clear(a, b) or not _clear(b, a):
		why = "something's in the way"
	if why != "":
		gadgets.call("flash", "Zipline " + why, Color(1, 0.7, 0.5), 1.6)
		_clear_pending()
		zip_a = Vector3.INF
		return {}
	_clear_pending()
	zip_a = Vector3.INF
	var node := Node3D.new()
	node.name = "Zipline%d" % zip_lines.size()
	add_child(node)
	var cab := _make_cable()
	cab.reparent(node)
	_set_cable(cab, a, b)
	for e: Vector3 in [a, b]:
		var hk := _make_hook()
		node.add_child(hk)
		hk.global_position = e
	var line := {"a": a, "b": b, "node": node}
	zip_lines.append(line)
	gadgets.call("flash", "Zipline up - B at the top end to ride, H to reel in", Color(0.7, 1, 0.7), 2.0)
	_event("zipline %.2f m" % a.distance_to(b))
	return line


func _zip_near_top() -> Dictionary:
	var best := {}
	var bd := ES.m(zip_mount_eh)
	for z in zip_lines:
		var d := (z.a as Vector3).distance_to(_hand())
		if d < bd:
			bd = d
			best = z
	return best


func ride(line: Dictionary) -> void:
	_zip = line
	var a: Vector3 = line.a
	var b: Vector3 = line.b
	var L := a.distance_to(b)
	_zip_t = clampf((_hand() - a).dot((b - a) / L), 0.04, L * 0.5)
	_zip_v = 0.0
	state = S.ZIP
	if _trolley == null:
		_trolley = _make_trolley()
	_trolley.visible = true
	_ext(true, "zip", zip_noise_eh)
	elf.call("face", Vector3(b.x - a.x, 0, b.z - a.z))
	_event("ride")


func _step_zip(delta: float) -> void:
	var a: Vector3 = _zip.a
	var b: Vector3 = _zip.b
	var L := a.distance_to(b)
	var dir := (b - a) / L
	var g := float(elf.get("gravity"))
	_zip_v = minf(ES.m(zip_max_speed_eh), maxf(0.0, _zip_v + (g * -dir.y - zip_friction) * delta))
	_zip_t += _zip_v * delta
	_whirr_on(true)
	var p := a + dir * _zip_t
	var feet := p - Vector3(0, ES.m(hang_eh), 0)
	# feet would touch something below: stop there
	var space := elf.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p, feet - Vector3(0, 0.01, 0), 4)
	q.exclude = [elf.get_rid()]
	var hit := space.intersect_ray(q)
	_trolley.global_position = p
	_trolley.look_at(p + dir, Vector3.UP)
	if not hit.is_empty():
		var hy := (hit.position as Vector3).y + 0.005
		if _zip_t > L * 0.6:
			# feet down at the far end: unclip and stand
			elf.global_position = Vector3(p.x, hy, p.z)
			_zip_off(false)
			return
		feet.y = hy  # knees up, skimming over whatever's below
	elf.global_position = feet
	elf.velocity = dir * _zip_v
	if _zip_t >= L - ES.m(0.6):
		_zip_off(false)


func _zip_off(drop: bool) -> void:
	var v := elf.velocity * (0.35 if not drop else 0.6)
	_event("zip off")
	if _trolley:
		_trolley.visible = false
	state = S.NONE
	_whirr_on(false)
	_ext(false, "")
	elf.velocity = v


## H: reel in the nearest zipline (a line left up is evidence).
func retrieve() -> bool:
	if zip_a != Vector3.INF:
		_clear_pending()
		zip_a = Vector3.INF
		gadgets.call("flash", "Anchor A reeled in", Color(0.8, 1, 0.8), 1.2)
		return true
	var best := -1
	var bd := ES.m(retrieve_reach_eh)
	var h := _hand()
	for i in zip_lines.size():
		var a: Vector3 = zip_lines[i].a
		var b: Vector3 = zip_lines[i].b
		var t := clampf((h - a).dot((b - a).normalized()), 0.0, a.distance_to(b))
		var d := (a + (b - a).normalized() * t).distance_to(h)
		if d < bd:
			bd = d
			best = i
	if best < 0:
		gadgets.call("flash", "No zipline close enough to reel in", Color(1, 0.8, 0.5), 1.2)
		return false
	if state == S.ZIP and _zip == zip_lines[best]:
		_zip_off(true)
	(zip_lines[best].node as Node3D).queue_free()
	zip_lines.remove_at(best)
	_whirr_burst()
	gadgets.call("flash", "Zipline reeled in", Color(0.8, 1, 0.8), 1.2)
	_event("retrieved")
	return true


func _clear_pending() -> void:
	if _pending_hook and is_instance_valid(_pending_hook):
		_pending_hook.queue_free()
	_pending_hook = null


# =================================================================================================
# Climbing
# =================================================================================================

## Space next to a climbable: grab on (the elf's jump calls this first). Returns true when it grabbed.
func try_grab() -> bool:
	if state != S.NONE or interior == null or stamina < 0.5:
		return false
	var c := climbable_near()
	if c.is_empty():
		return false
	_climb = c
	var lp: Vector3 = interior.to_local(elf.global_position)
	var f := _face(c)
	_cu = clampf((lp - f.center).dot(f.t), -f.half_w + ES.radius(), f.half_w - ES.radius())
	_cy = clampf(lp.y + ES.m(0.15), f.bottom, f.top - ES.m(0.9))
	state = S.CLIMB
	_ext(true, "climb", climb_noise_eh)
	_place_on_face()
	_event("climb " + str(c.name))
	return true


## The marked climbable face you're standing at (and roughly facing), or {}.
func climbable_near() -> Dictionary:
	var lp: Vector3 = interior.to_local(elf.global_position)
	var look: Vector3 = interior.global_basis.inverse() * (elf.call("aim_dir") as Vector3)
	look.y = 0
	for c in interior.get("climbables"):
		var f := _face(c)
		var d: float = (lp - (f.center as Vector3)).dot(f.n as Vector3)
		if d < -0.02 or d > ES.radius() + ES.m(climb_reach_eh):
			continue
		if absf((lp - f.center).dot(f.t)) > f.half_w:
			continue
		if lp.y < f.bottom - 0.05 or lp.y > f.top - ES.m(0.9):
			continue
		if look.length() > 0.01 and look.normalized().dot(-f.n) < 0.2 and not drive.has("climb"):
			continue
		return c
	return {}


## Face frame of a climbable (interior-local): centre of the face, out-normal n, tangent t, extents.
func _face(c: Dictionary) -> Dictionary:
	var box: AABB = c.box
	var n: Vector3 = c.normal
	n.y = 0
	n = n.normalized()
	var half := box.size * 0.5
	var ext_n := absf(n.x) * half.x + absf(n.z) * half.z
	var t := n.cross(Vector3.UP).normalized()
	var half_w := absf(t.x) * half.x + absf(t.z) * half.z
	var center := box.get_center() + n * ext_n
	return {"center": Vector3(center.x, 0, center.z), "n": n, "t": t, "half_w": half_w, "bottom": box.position.y, "top": box.end.y, "depth": ext_n * 2.0}


func _place_on_face() -> void:
	var f := _face(_climb)
	var lp: Vector3 = f.center + f.t * _cu + f.n * (ES.radius() + 0.012)
	lp.y = _cy
	elf.global_position = interior.to_global(lp)
	elf.velocity = Vector3.ZERO
	elf.call("face", -(interior.global_basis * (f.n as Vector3)))


func _step_climb(delta: float) -> void:
	var f := _face(_climb)
	var inp := _in_vec()
	var moving := inp.length() > 0.1
	_cy += -inp.y * ES.m(climb_speed_eh) * delta
	_cu += -inp.x * ES.m(shimmy_speed_eh) * delta  # facing the face: screen right is the face's -t
	_cu = clampf(_cu, -f.half_w + ES.radius(), f.half_w - ES.radius())
	var top_y: float = f.top - ES.m(0.9)
	_cy = clampf(_cy, f.bottom, top_y)
	stamina -= (1.0 if moving else stamina_hold_drain) * delta
	elf.set("ext_anim_speed", 7.0 if moving else 0.0)
	_place_on_face()
	if _cy <= f.bottom + 0.002 and inp.y > 0.1:
		let_go("down")
		return
	if _cy >= top_y - 0.002 and inp.y < -0.1:
		if bool(_climb.mantle):
			# ledge grab and mantle onto the top
			var top_lp: Vector3 = f.center + f.t * _cu - f.n * minf(ES.radius() + 0.06, float(f.depth) * 0.5)
			top_lp.y = float(f.top) + 0.01
			_mantle_from = elf.global_position
			_mantle_to = interior.to_global(top_lp)
			_mantle_t = 0.0
			state = S.MANTLE
			set_meta("after_mantle", "none")
			elf.set("pose", "mantle")
			return
	if stamina <= 0.0:
		stamina = 0.0
		gadgets.call("flash", "Lost your grip!", Color(1, 0.6, 0.5), 1.4)
		let_go("grip")


# =================================================================================================
# Visuals and sound
# =================================================================================================

func _update_visuals(delta: float) -> void:
	var on: bool = state == S.GRAPPLE or state == S.RAPPEL or (state == S.MANTLE and get_meta("after_mantle", "") == "rappel")
	if on and _hook and is_instance_valid(_hook):
		_cable.visible = true
		_set_cable(_cable, _launcher_pos(), _hook.global_position)
	elif _retract > 0.0:
		_retract = maxf(0.0, _retract - delta / 0.3)
		var lp := _launcher_pos()
		var tip := lp.lerp(_retract_from, _retract)
		_cable.visible = _retract > 0.02
		_set_cable(_cable, lp, tip)
		if _hook and is_instance_valid(_hook):
			_hook.global_position = tip
		if _retract <= 0.0:
			if _hook and is_instance_valid(_hook):
				_hook.queue_free()
			_hook = null
			_whirr_on(false)
	else:
		_cable.visible = false


func _launcher_pos() -> Vector3:
	if _launcher and is_instance_valid(_launcher) and not inverted:
		return _launcher.global_position
	return _hand()


func _make_cable() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0028
	cm.bottom_radius = 0.0028
	cm.height = 1.0
	cm.radial_segments = 6
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _cable_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 1 | 2
	add_child(mi)
	return mi


func _set_cable(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.001:
		mi.visible = false
		return
	var y := d / L
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	mi.global_transform = Transform3D(Basis(x, y * L, z), (a + b) * 0.5)


## Small three-prong claw hook with a candy-cane band (~3 cm).
func _make_hook() -> Node3D:
	var h := Node3D.new()
	var dark := Color(0.09, 0.1, 0.09)
	GB.cylinder(h, 0.004, 0.004, 0.03, Vector3(0, 0, 0), dark)
	GB.cylinder(h, 0.0055, 0.0055, 0.008, Vector3(0, 0.006, 0), Color(0.9, 0.12, 0.14))
	for i in 3:
		var a := i * TAU / 3.0
		var prong := GB.box(h, Vector3(0.004, 0.018, 0.004), Vector3(cos(a) * 0.008, -0.018, sin(a) * 0.008), dark)
		prong.rotation = Vector3(sin(a) * 0.9, 0, -cos(a) * 0.9)
	for n in h.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = 1 | 2
	return h


func _place_hook(p: Vector3, _dir: Vector3) -> void:
	if _hook and is_instance_valid(_hook):
		_hook.queue_free()
	_retract = 0.0
	_hook = _make_hook()
	add_child(_hook)
	_hook.global_position = p


## Wrist launcher on the left forearm: dark green body, black barrel, candy-cane red band, claw at the muzzle.
func _make_launcher() -> Node3D:
	var arm: Node3D = elf.get("arm_l")
	var root := Node3D.new()
	root.name = "CrookLauncher"
	(arm if arm else elf).add_child(root)
	root.position = Vector3(0.012, -0.03, -0.075)
	var green := Color(0.1, 0.24, 0.14)
	var black := Color(0.05, 0.05, 0.06)
	GB.box(root, Vector3(0.034, 0.03, 0.075), Vector3(0, 0, 0), green)
	GB.cylinder(root, 0.009, 0.009, 0.05, Vector3(0, 0.014, -0.035), black, Vector3(90, 0, 0))
	GB.cylinder(root, 0.0105, 0.0105, 0.01, Vector3(0, 0.014, -0.02), Color(0.92, 0.1, 0.12), Vector3(90, 0, 0))
	GB.cylinder(root, 0.0105, 0.0105, 0.006, Vector3(0, 0.014, -0.032), Color(0.97, 0.95, 0.92), Vector3(90, 0, 0))
	GB.cylinder(root, 0.014, 0.014, 0.02, Vector3(-0.02, 0, 0.005), black, Vector3(0, 0, 90))  # reel drum
	GB.box(root, Vector3(0.036, 0.008, 0.02), Vector3(0, -0.014, 0.02), black)  # wrist strap
	for i in 3:
		var a := i * TAU / 3.0
		GB.box(root, Vector3(0.004, 0.004, 0.012), Vector3(cos(a) * 0.007, 0.014 + sin(a) * 0.007, -0.064), black)
	for n in root.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = 1 | 2
	return root


func _make_trolley() -> Node3D:
	var t := Node3D.new()
	add_child(t)
	var black := Color(0.06, 0.06, 0.07)
	GB.box(t, Vector3(0.012, 0.03, 0.05), Vector3(0, -0.012, 0), Color(0.1, 0.24, 0.14))
	for z: float in [-0.015, 0.015]:
		GB.cylinder(t, 0.008, 0.008, 0.01, Vector3(0, 0.004, z), black, Vector3(0, 0, 90))
	GB.box(t, Vector3(0.05, 0.006, 0.008), Vector3(0, -0.03, 0), Color(0.9, 0.12, 0.14))  # hand bar
	for n in t.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = 1 | 2
	t.visible = false
	return t


func _thwip() -> void:
	if _snd:
		_snd.stream = _thwip_wav
		_snd.play()


func _whirr_on(on: bool) -> void:
	if _whirr == null:
		return
	if on and not _whirr.playing:
		_whirr.stream = _whirr_wav
		_whirr.play()
	elif not on and _whirr.playing and _retract <= 0.0:
		_whirr.stop()


func _whirr_burst() -> void:
	if _whirr:
		_whirr.stream = _whirr_wav
		_whirr.play()
		get_tree().create_timer(0.45).timeout.connect(func() -> void:
			if is_instance_valid(_whirr) and state != S.ZIP:
				_whirr.stop())


static func _pcm(samples: PackedFloat32Array, rate: int, loop := false) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


## "thwip" (a falling whistle + air) then "clack" (the claw biting).
static func _synth_thwip() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.24)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		var v := 0.0
		if t < 0.12:
			var f := lerpf(2600.0, 520.0, t / 0.12)
			ph += TAU * f / rate
			var env := sin(PI * t / 0.12)
			v += (sin(ph) * 0.55 + rng.randf_range(-1, 1) * 0.3) * env * 0.6
		if t > 0.15 and t < 0.19:
			var tc := t - 0.15
			var env2 := exp(-tc * 160.0)
			v += (signf(sin(TAU * 1900.0 * tc)) * 0.5 + rng.randf_range(-1, 1) * 0.6) * env2 * 0.8
		s[i] = v
	return _pcm(s, rate)


## Reel whirr: a buzzy little motor (loops).
static func _synth_whirr() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.4)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / rate
		var saw := fmod(t * 150.0, 1.0) * 2.0 - 1.0
		var saw2 := fmod(t * 300.0, 1.0) * 2.0 - 1.0
		var am := 0.7 + 0.3 * sin(TAU * 25.0 * t)
		s[i] = (saw * 0.35 + saw2 * 0.15) * am * 0.5
	return _pcm(s, rate, true)


func _event(e: String) -> void:
	log_events.append(e)
	if log_events.size() > 40:
		log_events.pop_front()
