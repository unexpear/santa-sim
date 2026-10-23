extends RefCounted
## Generic mechanics helpers shared by ropes, springs, handles, doors and placed parts.
## Nothing here knows about a particular trick: a force at a point goes to whatever body is there.
##   - RigidBody3D: Jolt does the rest (apply_force at the point)
##   - a "mech" node (door, handle, latch, spool: anything with apply_point_force/point_velocity),
##     which integrates its own 1-DOF joint (hinge or slide) with springs, friction and limits
##   - anything else (StaticBody3D, plain Node3D, null): an immovable anchor
## Real units throughout: kg, N, N*m, metres. The elf weighs ELF_MASS.

const ES := preload("res://scripts/elf_size.gd")

const G := 9.81
const ELF_MASS := 0.5  ## kg (a 22 cm elf; about a small bag of sugar)
const ELF_WEIGHT := ELF_MASS * G  ## 4.9 N: what the elf can hang on anything
const ELF_FOOT_MU := 0.9  ## rubber-soled boots on a floor
const ELF_PUSH := ELF_FOOT_MU * ELF_WEIGHT  ## 4.4 N: the most the elf can push/pull standing (traction-limited)
const ELF_GRIP_SQUEEZE := 2.0  ## N: how hard elf hands squeeze a round knob (friction grip on a round thing)


## Apply a world-space force at a world point. mode: "tie" (knotted / hooked: full force),
## "wrap" (rope wound round a round thing: full tangential force), "grip" (a hand or a hanging
## body holding on: on a round surface only friction can transmit tangential force, so it slips).
static func apply(target: Object, point: Vector3, force: Vector3, mode := "tie") -> void:
	target = holder(target)
	if target == null:
		return
	if target.has_method("apply_point_force"):
		target.call("apply_point_force", point, force, mode)
	elif target is RigidBody3D:
		var rb := target as RigidBody3D
		rb.apply_force(force, point - rb.global_position)


static func point_velocity(target: Object, point: Vector3) -> Vector3:
	target = holder(target)
	if target == null:
		return Vector3.ZERO
	if target.has_method("point_velocity"):
		return target.call("point_velocity", point)
	if target is RigidBody3D:
		var rb := target as RigidBody3D
		return rb.linear_velocity + rb.angular_velocity.cross(point - rb.global_position)
	return Vector3.ZERO


## The body that takes a force applied to n: n itself, or the nearest ancestor that is a rigid body
## or a mech (a knot on a handle's visual goes to the handle; a hook on a door slab to the door).
static func holder(n: Object) -> Object:
	var c := n as Node
	var hops := 0
	while c and is_instance_valid(c) and hops < 4:
		if c is RigidBody3D or c.has_method("apply_point_force"):
			return c
		if c is StaticBody3D:
			return null
		c = c.get_parent()
		hops += 1
	return null


static func world_point(target: Node3D, local: Vector3) -> Vector3:
	return target.global_transform * local if target and is_instance_valid(target) else local


## Mark a node as having grabbable attach points (local positions). Parts and doors do this so the
## rig tool can highlight them; any other surface can still be tied to at its raycast hit point.
static func add_attach(n: Node3D, local: Vector3, kind := "edge") -> void:
	var a: Array = n.get_meta("attach_points", [])
	a.append({"p": local, "kind": kind})
	n.set_meta("attach_points", a)
	n.add_to_group("mech_attach")
