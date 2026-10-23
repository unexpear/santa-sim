extends Node3D
## A real door, simulated as a mechanism (no scripted "open" for the elf):
##   - the slab is a 1-DOF body on its hinge (or on a sliding track) with real mass, inertia,
##     hinge friction, damping, an optional spring closer and end stops;
##   - its HANDLE is a rotor (scripts/mech/rotor.gd) with a return spring; the LATCH holds the slab
##     shut until the handle has turned past latch_release;
##   - forces arrive from anything: ropes, springs, hanging weights, the elf's push (Mech.apply).
## Which tricks open which door falls out of the handle type (seeded per house/room):
##   lever  - a bar on a spring: hanging weight on its far end turns it (leverage)
##   knob   - round: a hanging hand only slips (friction grip); a rope WRAPPED round it and pulled
##            tangentially turns it, or the gripper
##   plate  - no latch (swing / kitchen door): enough force on the slab, against mass + hinge friction
##   slide  - a heavy slider on rollers with a small flip latch: needs a sustained pull
##   screen - light, with a spring closer that pushes back
## People (residents, scripted checks) still open doors the human way with toggle()/set_open().
## The collision is an AnimatableBody3D on the interior layer so a closed door blocks the elf.

signal creaked(position: Vector3, radius: float)  ## stealth hook: residents can listen for this

const INTERIOR_LAYER := 4
const Mech := preload("res://scripts/mech/mech.gd")
const Rotor := preload("res://scripts/mech/rotor.gd")
const PM := preload("res://scripts/mech/part_models.gd")
const GB := preload("res://scripts/greybox.gd")

@export var width := 0.98  ## slab width (m), fills the opening
@export var height := 2.05
@export var thickness := 0.1  ## collision thickness: at least 2x the elf's 0.05 m capsule radius
@export var open_angle := 95.0  ## degrees when fully open (sign picks the room it swings into)
@export var swing_speed := 160.0  ## degrees per second (people opening it)
@export var creak_radius := 3.5  ## metres: how far a creak carries (house scale, not elf scale)
@export var locked := false  ## deadbolt thrown (front / back doors at night)

## --- mechanism (real scale; see configure()) ---
@export var handle_type := "lever"  ## lever / knob / plate / slide / screen
@export var mass := 12.0  ## kg (hollow-core interior door ~10-14, solid front door ~30-40, glass slider ~40)
@export var hinge_friction := 0.25  ## N*m Coulomb at the hinges (or N on a slider track: rolling resistance)
@export var breakaway := 0.0  ## extra static friction to get it moving (N*m or N): seals, a sticky track
@export var seal_friction := 0.0  ## N*m extra while nearly shut (weatherstrip drag on a front door)
@export var hinge_damping := 0.3  ## N*m*s/rad (or N*s/m)
@export var closer_k := 0.0  ## N*m/rad spring closer (screen door, double-action kitchen hinge)
@export var closer_preload := 0.0
@export var latch_release := 0.5  ## rad the handle must turn before the latch clears the strike
@export var swing_both := false
## Draw placeholder handle geometry (mech test rigs only). In the houses the door keeps its modelled
## look; the handle mechanism runs underneath with no extra primitives on the slab.
static var draw_handles := false  ## double-action (kitchen swing door): no stop at the frame

var angle := 0.0  ## current opening, degrees (0 = closed); for sliders, % of the travel
var target := 0.0
var swing_sign := 1.0  ## +1 or -1: which side it opens toward
var prefer_sign := 1.0  ## the side with the bigger room (an open door there blocks least)
var elf: Node3D  ## set by the interior, used to avoid swinging through the elf
var visual: Node3D
var body: AnimatableBody3D
var handle: Node3D  ## Rotor (null for plate doors)
var flip_latch: Node3D  ## Rotor (sliders)
var latched := false
var q := 0.0  ## generalized coordinate: hinge angle (rad, signed) or slide travel (m)
var qd := 0.0
var driven := false  ## a person is opening/closing it (kinematic) rather than physics
var _gen := 0.0  ## generalized force accumulated this tick (N*m or N)
var _creaked := false
var _slab: Node3D  ## moves with q; handle hangs off it


func is_slider() -> bool:
	return handle_type == "slide"


## Real-scale numbers per handle type (call before setup). heavy = an external door.
func configure(kind: String, heavy := false) -> void:
	handle_type = kind
	match kind:
		"lever":
			mass = 32.0 if heavy else 12.0
		"knob":
			mass = 32.0 if heavy else 12.0
		"plate":
			mass = 9.0
			swing_both = true
			closer_k = 1.2  # double-action hinge springs back to centre
			hinge_friction = 0.15
		"slide":
			mass = 40.0 if heavy else 18.0  # glass patio slider / timber cavity slider
			hinge_friction = 0.012 * mass * Mech.G  # rolling resistance on the track (N)
			breakaway = 0.012 * mass * Mech.G  # sticky track + latch rubbers: static total ~0.024 mg
			hinge_damping = 4.0
		"screen":
			mass = 4.5
			closer_k = 0.9
			closer_preload = 0.6
			hinge_friction = 0.1
	if heavy and kind != "slide":
		hinge_friction = 1.2  # three heavy butt hinges
		seal_friction = 3.2  # weatherstrip drag near shut: ~4.4 N*m to start it moving
		hinge_damping = 0.8


func _inertia() -> float:
	return mass if is_slider() else mass * width * width / 3.0


func setup(mesh: Mesh, w: float, start_angle: float, sgn: float) -> void:
	width = w
	swing_sign = sgn
	_slab = Node3D.new()
	_slab.name = "Slab"
	add_child(_slab)
	visual = MeshInstance3D.new()
	(visual as MeshInstance3D).mesh = mesh
	visual.scale = Vector3(w / 0.9, 1.0, 1.0)  # the modelled slab is 0.9 m wide
	_slab.add_child(visual)
	body = AnimatableBody3D.new()
	body.collision_layer = INTERIOR_LAYER
	body.collision_mask = 0
	body.sync_to_physics = false  # we move it ourselves in _physics_process
	body.set_meta("door", self)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, height, thickness)
	cs.shape = bs
	cs.position = Vector3(w * 0.5, height * 0.5, 0)
	body.add_child(cs)
	add_child(body)
	_build_handle()
	# grabbable edges: the free edge low (the elf can tie on from the floor) and at handle height
	for y: float in [0.12, 0.98]:
		for zs: float in [1.0, -1.0]:
			Mech.add_attach(_slab, Vector3(w - 0.03, y, zs * thickness * 0.5), "edge")
	angle = start_angle
	target = start_angle
	_set_q_from_angle()
	latched = start_angle < 1.0 and _has_latch()
	_apply()


func _has_latch() -> bool:
	return handle_type in ["lever", "knob", "slide", "screen"]


## The handle mechanism for this door's type (real torques: lever ~0.5 N*m to release, knob
## ~0.26 N*m, flip latch a few hundredths).
func _build_handle() -> void:
	var hp := Vector3(width - 0.07, 0.98, 0.0)
	var face := thickness * 0.5 + 0.03
	var brass := Color(0.78, 0.62, 0.3)
	match handle_type:
		"lever", "screen":
			var r := Rotor.new()
			r.name = "Handle"
			r.inertia = 0.004
			r.spring_preload = 0.25 if handle_type == "lever" else 0.12
			r.spring_k = 0.5 if handle_type == "lever" else 0.25
			r.theta_min = 0.0
			r.theta_max = 0.8
			r.friction = 0.02
			r.damping = 0.01
			r.position = hp
			_slab.add_child(r)
			var v := Node3D.new()
			r.add_child(v)
			r.visual = v
			v.visible = draw_handles
			for zs: float in [1.0, -1.0]:
				if PM.add(v, "LeverHandle", Vector3(0, 0, zs * thickness * 0.5), Vector3.ZERO, Vector3(1, 1, zs)) == null:
					GB.cylinder(v, 0.012, 0.012, 0.03, Vector3(0, 0, zs * (face - 0.015)), brass, Vector3(90, 0, 0))
					GB.box(v, Vector3(0.13, 0.018, 0.022), Vector3(-0.055, 0, zs * face), brass)
				Mech.add_attach(r, Vector3(-0.115, 0.0, zs * face), "lever_end")
			handle = r
		"knob":
			var r := Rotor.new()
			r.name = "Handle"
			r.inertia = 0.0008
			r.spring_sign = 0.0
			r.spring_preload = 0.1
			r.spring_k = 0.15
			r.theta_min = -1.3
			r.theta_max = 1.3
			r.friction = 0.015
			r.damping = 0.004
			r.round_radius = 0.028
			r.position = hp
			_slab.add_child(r)
			var v := Node3D.new()
			r.add_child(v)
			r.visual = v
			v.visible = draw_handles
			for zs: float in [1.0, -1.0]:
				if PM.add(v, "KnobHandle", Vector3(0, 0, zs * thickness * 0.5), Vector3.ZERO, Vector3(1, 1, zs)) == null:
					GB.cylinder(v, 0.01, 0.01, 0.05, Vector3(0, 0, zs * (face - 0.02)), brass, Vector3(90, 0, 0))
					GB.sphere(v, 0.028, Vector3(0, 0, zs * (face + 0.012)), brass)
				Mech.add_attach(r, Vector3(0.028, 0.0, zs * (face + 0.012)), "knob_rim")
			latch_release = 1.0
			handle = r
		"slide":
			var r := Rotor.new()
			r.name = "FlipLatch"
			r.inertia = 0.0002
			r.theta_min = 0.0
			r.theta_max = PI * 0.5
			r.friction = 0.01
			r.damping = 0.002
			r.position = Vector3(width - 0.05, 0.95, 0.0)
			_slab.add_child(r)
			var v := Node3D.new()
			r.add_child(v)
			r.visual = v
			v.visible = draw_handles
			GB.box(v, Vector3(0.012, 0.04, 0.012), Vector3(0, 0.02, face), Color(0.75, 0.75, 0.78))
			Mech.add_attach(r, Vector3(0, 0.04, face), "flip_tab")
			flip_latch = r
			# flush pull on the leading edge (a rope ties through it)
			if draw_handles:
				GB.box(_slab, Vector3(0.02, 0.12, 0.03), Vector3(width - 0.02, 0.95, 0), Color(0.3, 0.3, 0.32))
			Mech.add_attach(_slab, Vector3(width - 0.01, 0.95, 0), "pull")


func handle_released() -> bool:
	if flip_latch:
		return float(flip_latch.get("theta")) > 1.0
	if handle:
		return absf(float(handle.get("theta"))) >= latch_release
	return true


func is_open() -> bool:
	return angle > 30.0


## Free a latched door without anyone turning the handle (checks; a door left pushed-to).
func unlatch() -> void:
	latched = false


## People open / close doors (residents, scripted checks): handle turned, slab swung by hand.
## When opening, the door swings away from whoever opened it (opener in world space).
func toggle(opener := Vector3.INF) -> bool:
	if locked:
		return false
	if angle > 1.0:
		target = 0.0
	else:
		if angle < 1.0 and not is_slider():
			var want := swing_sign
			if opener != Vector3.INF:
				var side := signf((opener - world_mid()).dot(global_basis.z))
				if side != 0.0:
					want = side  # a positive swing moves the slab toward -Z, away from the opener
			# ...unless that side is obstructed (furniture, a corridor wall) and the other isn't
			var bw := _blocked_open(want)
			var bo := _blocked_open(-want)
			if bw > bo or (bw == bo and bw > 0 and want != prefer_sign):
				want = -want
			swing_sign = want
		target = open_angle
	latched = false
	driven = true
	_creaked = false
	return true


## Set the door instantly (scripted checks). Opens to the less obstructed side; shut = latched.
func set_open(open: bool, instant := true) -> void:
	if open and angle < 1.0 and not is_slider():
		var bp := _blocked_open(prefer_sign)
		var bo := _blocked_open(-prefer_sign)
		swing_sign = prefer_sign if bp <= bo else -prefer_sign
	target = open_angle if open else 0.0
	latched = false
	driven = true
	if instant:
		angle = target
		_set_q_from_angle()
		qd = 0.0
		driven = false
		latched = not open and _has_latch()
		_apply()


func world_mid() -> Vector3:
	return global_transform * Vector3(width * 0.5, 0, 0)


## How much the fully open slab would overlap (interior walls / furniture) on side sgn.
func _blocked_open(sgn: float) -> int:
	if not is_inside_tree():
		return 0
	var sh := BoxShape3D.new()
	sh.size = Vector3(width - 0.2, height * 0.5, thickness + 0.04)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.collision_mask = INTERIOR_LAYER
	q.exclude = [body.get_rid()]
	var r := deg_to_rad(open_angle) * sgn
	var xf := global_transform * Transform3D(Basis(Vector3.UP, r), Vector3.ZERO)
	var n := 0
	for y: float in [0.15, height * 0.5]:
		q.transform = xf * Transform3D(Basis(), Vector3(0.12 + (width - 0.2) * 0.5, y + height * 0.25 - 0.1, 0))
		n += get_world_3d().direct_space_state.intersect_shape(q, 8).size()
	return n


## Characters (group "door_blocker", meta "block_radius") the swinging slab would hit.
func _sweeps_into_someone(q0: float, q1: float) -> bool:
	if absf(q1 - q0) < 1e-6 or not is_inside_tree():
		return false
	var inv := global_transform.affine_inverse()
	for c in get_tree().get_nodes_in_group("door_blocker"):
		var n3 := c as Node3D
		if n3 == null or n3.global_position.distance_squared_to(global_position) > (width + 0.6) * (width + 0.6):
			continue
		var pl := inv * n3.global_position
		if pl.y < -0.1 or pl.y > height:
			continue
		var r := float(n3.get_meta("block_radius", 0.06)) + thickness * 0.5
		var d0 := _slab_dist(pl, q0)
		var d1 := _slab_dist(pl, q1)
		if d1 < r and d1 < d0:
			return true
	return false


func _slab_dist(pl: Vector3, a: float) -> float:
	var d := Vector2(cos(a), -sin(a))
	var p := Vector2(pl.x, pl.z)
	var t := clampf(p.dot(d), 0.0, width)
	return (p - d * t).length()


func _travel() -> float:
	return width * 0.9


func _set_q_from_angle() -> void:
	q = _travel() * angle / open_angle if is_slider() else deg_to_rad(angle) * swing_sign


func _apply() -> void:
	if is_slider():
		_slab.position.x = -q
		body.position.x = -q
	else:
		_slab.rotation.y = q
		body.rotation.y = q


## --- generic mechanics interface (ropes, springs, weights, the elf's push) ---

func apply_point_force(p: Vector3, f: Vector3, _mode := "tie") -> void:
	if is_slider():
		_gen += f.dot(-global_basis.x.normalized())
	else:
		_gen += (p - global_position).cross(f).y


func point_velocity(p: Vector3) -> Vector3:
	if is_slider():
		return -global_basis.x.normalized() * qd
	return Vector3(0, qd, 0).cross(p - global_position)


## The slab point nearest p at height y (world).
func slab_point(p: Vector3) -> Vector3:
	var lp := _slab.to_local(p)
	return _slab.to_global(Vector3(clampf(lp.x, 0.05, width - 0.02), clampf(lp.y, 0.05, height - 0.05), signf(lp.z) * thickness * 0.5))


## The elf leans on the slab with its full traction-limited push (pushing away from itself; on a
## slider it hauls the leading edge toward the cavity). Returns the generalized force it managed.
func elf_push(from_pos: Vector3, force := Mech.ELF_PUSH) -> void:
	var cp := slab_point(from_pos)
	if is_slider():
		apply_point_force(cp, -global_basis.x.normalized() * force)
		return
	var n := _slab.global_basis.z.normalized()
	var side := signf((from_pos - cp).dot(n))
	apply_point_force(cp, -n * side * force)


## E on an unlatched door: lean on it. If it opens TOWARD the elf (the frame stop is on the far
## side), pushing does nothing, so the elf hooks its fingers under the bottom of the leading edge
## (the ~1 cm undercut gap) and pulls instead: same traction-limited force, toward itself.
func _elf_lean_tick(from_pos: Vector3) -> void:
	if is_slider() or swing_both:
		elf_push(from_pos)
		return
	var cp := slab_point(from_pos)
	var n := _slab.global_basis.z.normalized()
	var side := signf((from_pos - cp).dot(n))
	var f := -n * side * Mech.ELF_PUSH
	var tau := (cp - global_position).cross(f).y
	if absf(q) < 0.05 and signf(tau) != signf(swing_sign) and swing_sign != 0.0:
		var edge := _slab.to_global(Vector3(width - 0.03, 0.015, 0.0))
		apply_point_force(edge, -f)
	else:
		apply_point_force(cp, f)


## The elf leaning / hanging on something for a while (E in play): timed loads re-applied each tick.
var _loads: Array = []  ## [{kind: "push"/"hang", from: Vector3, t: float}]


func elf_lean(from_pos: Vector3, seconds := 0.8) -> void:
	_loads.append({"kind": "push", "from": from_pos, "t": seconds})


## Hang the elf's weight on the handle (lever bar end / knob rim) on the elf's side.
func elf_hang(from_pos: Vector3, seconds := 1.2) -> void:
	_loads.append({"kind": "hang", "from": from_pos, "t": seconds})


func handle_grab_point(from_pos: Vector3) -> Vector3:
	var h := handle if handle else flip_latch
	if h == null:
		return slab_point(from_pos)
	var side := signf(h.to_local(from_pos).z)
	var best := h.global_position
	for a in h.get_meta("attach_points", []):
		if signf((a.p as Vector3).z) == side:
			best = h.global_transform * (a.p as Vector3)
	return best


func _apply_loads(delta: float) -> void:
	for i in range(_loads.size() - 1, -1, -1):
		var ld: Dictionary = _loads[i]
		ld.t = float(ld.t) - delta
		if float(ld.t) <= 0.0:
			_loads.remove_at(i)
			continue
		if ld.kind == "push":
			_elf_lean_tick(ld.from)
		else:
			var h := handle if handle else flip_latch
			if h:
				var gp := handle_grab_point(ld.from)
				# a hang on a flip latch is a push on its tab; on a lever / knob it is the elf's weight
				var f := Vector3(0, -Mech.ELF_WEIGHT, 0) if handle else -global_basis.x * Mech.ELF_PUSH
				h.call("apply_point_force", gp, f, "grip")


func _physics_process(delta: float) -> void:
	_apply_loads(delta)
	if driven:
		_gen = 0.0
		if is_equal_approx(angle, target):
			driven = false
			qd = 0.0
			if target < 1.0 and _has_latch():
				latched = true
			return
		var step := signf(target - angle) * minf(absf(target - angle), swing_speed * delta)
		var next := angle + step
		if elf and not is_slider() and _blocks_elf(next):
			return  # wait for the elf to move out of the swing
		if not _creaked and absf(step) > 0.0:
			_creaked = true
			creaked.emit(world_mid(), creak_radius)
		angle = next
		_set_q_from_angle()
		_apply()
		return
	var f := _gen
	_gen = 0.0
	if latched:
		if handle_released():
			latched = false
		else:
			q = 0.0
			qd = 0.0
			return
	if closer_k > 0.0 or closer_preload > 0.0:
		f -= closer_k * q + (closer_preload * signf(q) if absf(q) > 0.01 else 0.0)
	f -= hinge_damping * qd
	var fr := hinge_friction + (seal_friction if not is_slider() and absf(q) < 0.15 else 0.0)
	if absf(qd) < 1e-3 and absf(f) <= fr + breakaway:
		qd = 0.0
		return
	var dirn := signf(qd) if absf(qd) >= 1e-3 else signf(f)
	qd += (f - fr * dirn) / _inertia() * delta
	if absf(qd) < 1e-3 and absf(f) <= fr:
		qd = 0.0
	var nq := q + qd * delta
	var lo := 0.0
	var hi := 0.0
	if is_slider():
		hi = _travel()
	elif swing_both:
		lo = -deg_to_rad(open_angle)
		hi = deg_to_rad(open_angle)
	else:
		lo = minf(0.0, deg_to_rad(open_angle) * swing_sign)
		hi = maxf(0.0, deg_to_rad(open_angle) * swing_sign)
	if nq < lo or nq > hi:
		nq = clampf(nq, lo, hi)
		qd *= -0.15  # door stop / frame: a dull bump
	if not is_slider() and _sweeps_into_someone(q, nq):
		nq = q  # the slab stops against the elf / a resident (a kinematic slab would run through them)
		qd = 0.0
	# the bevelled latch snaps into the strike when it swings shut
	if _has_latch() and absf(nq) < 0.004 and absf(q) >= 0.004 and not handle_released():
		nq = 0.0
		qd = 0.0
		latched = true
	var na := absf(nq) / _travel() * open_angle if is_slider() else rad_to_deg(absf(nq))
	if elf and not is_slider() and nq != 0.0 and _blocks_elf_q(nq):
		qd = 0.0
		return
	if not _creaked and absf(qd) > 0.08:
		_creaked = true
		creaked.emit(world_mid(), creak_radius * clampf(absf(qd) / 0.6, 0.3, 1.0))
	if absf(qd) < 1e-3:
		_creaked = false
	q = nq
	angle = na
	target = angle
	if not is_slider() and absf(q) > 1e-4:
		swing_sign = signf(q)
	_apply()


func _blocks_elf_q(nq: float) -> bool:
	var keep := swing_sign
	swing_sign = signf(nq)
	var b := _blocks_elf(rad_to_deg(absf(nq)))
	swing_sign = keep
	return b


func _blocks_elf(next_angle: float) -> bool:
	var lp := to_local(elf.global_position)
	var flat := Vector2(lp.x, lp.z)
	var r := 0.07  # elf radius + a little
	if flat.length() > width + r or lp.y > height or lp.y < -0.3:
		return false
	# the slab at angle a lies along (cos a, -sin a * sign) in local xz (rotation about +Y)
	for a: float in [next_angle, (angle + next_angle) * 0.5]:
		var ra := deg_to_rad(a) * swing_sign
		var dir := Vector2(cos(ra), -sin(ra))
		var along := clampf(flat.dot(dir), 0.0, width)
		if (flat - dir * along).length() < r + thickness * 0.5:
			return true
	return false
