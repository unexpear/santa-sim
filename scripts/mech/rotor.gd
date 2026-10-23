extends Node3D
## A generic 1-DOF rotating part on a hinge axis (local +Z through this node's origin):
## a lever handle, a round knob, a deadbolt thumb-turn, a flip latch, a cotton-reel spool, a crank.
## Real dynamics: inertia, a return spring (preload + stiffness), Coulomb + viscous friction, stops.
## Forces come in through apply_point_force (ropes, hanging weights, springs, the elf's hands).
## Whether a hanging weight turns it is decided by the geometry: torque = (r x F) . axis, and on a
## ROUND part (knob, thumb-turn) a "grip" can only pass friction (mu * squeeze) tangentially.

const Mech := preload("res://scripts/mech/mech.gd")

@export var inertia := 0.0015  ## kg m^2 (handle + latch train)
@export var spring_preload := 0.0  ## N*m the return spring holds at theta = 0
@export var spring_k := 0.0  ## N*m per rad
@export var friction := 0.01  ## N*m Coulomb
@export var damping := 0.004  ## N*m*s/rad
@export var theta_min := 0.0  ## rad (stops)
@export var theta_max := 0.8
@export var round_radius := 0.0  ## > 0: a round part of this radius (grips slip on it)
@export var grip_mu := 0.35  ## skin / boot on polished brass
@export var spring_sign := 1.0  ## the spring pushes back toward theta_min (+1), theta_max (-1), or 0 (0 = centring, both ways)

var theta := 0.0
var omega := 0.0
var visual: Node3D  ## rotated with theta
var _tau := 0.0
var _grip_cap := 0.0


func _ready() -> void:
	process_physics_priority = 10  # after ropes/springs have added their forces


func axis_world() -> Vector3:
	return global_basis.z.normalized()


func apply_point_force(p: Vector3, f: Vector3, mode := "tie") -> void:
	var t := (p - global_position).cross(f).dot(axis_world())
	if mode == "grip" and round_radius > 0.0:
		# a hand on a round knob: only friction turns it; the rest of the force just loads the axle
		var cap := grip_mu * Mech.ELF_GRIP_SQUEEZE * round_radius
		t = clampf(t, -cap, cap)
	_tau += t


func apply_torque(t: float) -> void:
	_tau += t


func point_velocity(p: Vector3) -> Vector3:
	var base := Vector3.ZERO
	var par := get_parent()
	if par and par.has_method("point_velocity"):
		base = par.call("point_velocity", p)
	return base + (axis_world() * omega).cross(p - global_position)


func spring_torque() -> float:
	if spring_k == 0.0 and spring_preload == 0.0:
		return 0.0
	if spring_sign == 0.0:
		return -signf(theta) * (spring_preload + spring_k * absf(theta)) if absf(theta) > 1e-4 else 0.0
	var from := theta - theta_min if spring_sign > 0.0 else theta_max - theta
	return -spring_sign * (spring_preload + spring_k * maxf(from, 0.0))


func _physics_process(dt: float) -> void:
	var t := _tau + spring_torque() - damping * omega
	_tau = 0.0
	if absf(omega) < 1e-3 and absf(t) <= friction:
		omega = 0.0  # static friction holds it
	else:
		var fr := friction * (signf(omega) if absf(omega) >= 1e-3 else signf(t))
		omega += (t - fr) / inertia * dt
	theta += omega * dt
	if theta > theta_max:
		theta = theta_max
		omega = minf(omega, 0.0) * -0.1
	elif theta < theta_min:
		theta = theta_min
		omega = maxf(omega, 0.0) * -0.1
	if visual:
		visual.rotation.z = theta
