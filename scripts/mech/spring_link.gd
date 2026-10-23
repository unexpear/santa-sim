extends Node3D
## A spring between two attach points on any bodies (a toy spring, a clothes-peg launcher, a door
## closer, a rubber band). F = k (len - rest) + c dlen/dt along the line; compress_only /
## extend_only for a coil you can only squash or a band you can only stretch.

const Mech := preload("res://scripts/mech/mech.gd")

@export var k := 200.0  ## N/m
@export var c := 2.0  ## N*s/m
@export var rest := 0.05
@export var compress_only := false
@export var extend_only := false

var a: Node3D
var la := Vector3.ZERO
var b: Node3D
var lb := Vector3.ZERO
var force := 0.0
var _prev := -1.0


func _ready() -> void:
	process_physics_priority = -10


func setup(na: Node3D, wa: Vector3, nb: Node3D, wb: Vector3) -> void:
	a = na
	la = na.to_local(wa) if na else wa
	b = nb
	lb = nb.to_local(wb) if nb else wb


func _physics_process(dt: float) -> void:
	var pa := Mech.world_point(a, la)
	var pb := Mech.world_point(b, lb)
	var d := pb - pa
	var L := d.length()
	if L < 1e-5:
		return
	var rate := 0.0 if _prev < 0.0 else (L - _prev) / dt
	_prev = L
	var x := L - rest
	if (compress_only and x > 0.0) or (extend_only and x < 0.0):
		force = 0.0
		return
	force = k * x + c * rate  # > 0: pulls the ends together
	var u := d / L
	Mech.apply(a, pa, u * force)
	Mech.apply(b, pb, -u * force)
