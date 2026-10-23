extends Node3D
## A rope: an ordered list of points (two ends + any number of sheaves in between), each fixed to
## any body by a local offset. Ideal massless rope over frictionless sheaves => one tension T along
## its whole length, and every point gets T times the sum of the unit vectors toward its neighbours.
## That is all a pulley is: a movable sheave between two rope runs gets 2T, a block-and-tackle with
## n supporting runs gets nT. No mechanical-advantage constant anywhere; the routing does it.
## Tension: a stiff spring-damper on stretch (rope can't push), so the rope goes slack too.
## An end can be wound on a spool rotor (cotton reel + crank): winding shortens the rope.

const Mech := preload("res://scripts/mech/mech.gd")
const GB := preload("res://scripts/greybox.gd")

@export var rest_length := 1.0  ## m
@export var stiffness := 500.0  ## N/m (braided string with a little stretch; stable at 60 Hz with 0.5 kg ends)
@export var damping_c := 10.0  ## N*s/m
@export var max_tension := 60.0  ## N: breaks above this (sewing thread ~10 N, the elf's braided cord 60 N)
@export var radius := 0.003  ## visual
@export var color := Color(0.82, 0.78, 0.66)

var points: Array = []  ## [{n: Node3D or null, l: Vector3 (local, or world if n is null), mode: "tie"/"wrap"/"grip"}]
var spool: Node3D  ## optional rotor at points[0]: effective length = rest_length + theta * spool_radius
var spool_radius := 0.0
var tension := 0.0
var broken := false
var _prev_len := -1.0
var _spool0 := 0.0
var _segs: Array = []


func _ready() -> void:
	process_physics_priority = -10  # forces in before the bodies integrate


func add_point(n: Node3D, local: Vector3, mode := "tie") -> void:
	points.append({"n": n, "l": local, "mode": mode})


func add_world_point(n: Node3D, world: Vector3, mode := "tie") -> void:
	add_point(n, n.to_local(world) if n else world, mode)


func world(i: int) -> Vector3:
	var e: Dictionary = points[i]
	return Mech.world_point(e.n, e.l)


func current_length() -> float:
	var s := 0.0
	for i in range(points.size() - 1):
		s += world(i).distance_to(world(i + 1))
	return s


func effective_rest() -> float:
	if spool and is_instance_valid(spool):
		return maxf(rest_length + (float(spool.get("theta")) - _spool0) * spool_radius, 0.01)
	return rest_length


## Wind the start of this rope round a round rotor (knob, cotton reel, crank drum): the rope leaves
## it at the tangent point toward toward_world, and the rotor turns as rope pays out / winds in.
## (This is what "wrap a rope round the knob and pull" is: the knob becomes a capstan.)
func wrap_start(rotor: Node3D, r: float, toward_world: Vector3, side := 1.0) -> void:
	var c := rotor.global_position
	var ax: Vector3 = rotor.call("axis_world")
	var d := toward_world - c
	d -= ax * d.dot(ax)
	var tangent := c + ax.cross(d.normalized()) * r * side
	spool = rotor
	spool_radius = r * side
	points.push_front({"n": null, "l": tangent, "mode": "wrap"})


## Make the rope just taut in its current routing (plus slack metres).
func fit(slack := 0.0) -> void:
	rest_length = current_length() + slack
	_spool0 = float(spool.get("theta")) if spool else 0.0


func _physics_process(dt: float) -> void:
	if points.size() < 2 or broken:
		_draw()
		return
	var L := current_length()
	var rate := 0.0 if _prev_len < 0.0 else (L - _prev_len) / dt
	_prev_len = L
	var stretch := L - effective_rest()
	tension = maxf(0.0, stiffness * stretch + damping_c * rate) if stretch > 0.0 else 0.0
	if tension > max_tension:
		broken = true
		tension = 0.0
	if tension > 0.0:
		for i in points.size():
			var p := world(i)
			var f := Vector3.ZERO
			if i > 0:
				f += (world(i - 1) - p).normalized()
			if i < points.size() - 1:
				f += (world(i + 1) - p).normalized()
			Mech.apply(points[i].n, p, f * tension, str(points[i].mode))
		if spool and is_instance_valid(spool):
			spool.call("apply_torque", tension * spool_radius)  # the load unwinds it (theta + = rope paid out)
	_draw()


func _draw() -> void:
	var n := points.size() - 1
	while _segs.size() < n:
		var mi := GB.cylinder(self, radius, radius, 1.0, Vector3.ZERO, color)
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_segs.append(mi)
	for i in _segs.size():
		var mi: MeshInstance3D = _segs[i]
		mi.visible = i < n and not broken
		if not mi.visible:
			continue
		var a := world(i)
		var b := world(i + 1)
		var d := b - a
		var ln := d.length()
		if ln < 1e-4:
			mi.visible = false
			continue
		var y := d / ln
		var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		mi.global_transform = Transform3D(Basis(x, y * ln, z), (a + b) * 0.5)
