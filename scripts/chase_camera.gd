extends Camera3D
## Smoothed chase camera. Mode 0 = behind the sleigh, mode 1 = high "landing" view looking down.

@export var target: Node3D
@export var chase_distance := 9.0
@export var chase_height := 3.2
@export var look_ahead := 5.0
@export var landing_back := 4.0
@export var landing_height := 12.0
@export var sharpness := 6.0

var mode := 0
var locked := false  ## Scripted shots (screenshots) set this to stop following.
var _look := Vector3.ZERO


func _ready() -> void:
	top_level = true
	current = true


func toggle_mode() -> void:
	mode = 1 - mode


func snap() -> void:
	_update(1.0)
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if not locked:
		_update(1.0 - exp(-sharpness * delta))


func _update(a: float) -> void:
	if target == null:
		return
	var fwd := -target.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var p := target.global_position
	var want: Vector3
	var look: Vector3
	if mode == 0:
		want = p - fwd * chase_distance + Vector3.UP * chase_height
		look = p + fwd * look_ahead + Vector3.UP * 0.5
	else:
		want = p - fwd * landing_back + Vector3.UP * landing_height
		look = p + fwd * 1.5
	global_position = global_position.lerp(want, a)
	_look = _look.lerp(look, a)
	if global_position.distance_to(_look) > 0.01:
		look_at(_look, Vector3.UP)
