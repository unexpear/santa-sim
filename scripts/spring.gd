extends RefCounted
## Tiny damped spring used by the visual-only animation code (squash, tilt, swings, bounces).
## step() eases x toward target; kick() adds velocity for an instant jolt.

var x := 0.0
var v := 0.0


func step(target: float, stiffness: float, damping: float, dt: float) -> float:
	v += ((target - x) * stiffness - v * damping) * dt
	x += v * dt
	return x


func kick(impulse: float) -> void:
	v += impulse


func reset(value := 0.0) -> void:
	x = value
	v = 0.0
