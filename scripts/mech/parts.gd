extends RefCounted
## Physical parts the player places and connects (and the checks build rigs from). Every one is a
## real Jolt body or a mech rotor; nothing knows what trick it is part of.
##   weight / present / book: any RigidBody3D box   plank: a ruler, a slat (lever, seesaw, ramp)
##   fulcrum: a crayon / pencil / cotton reel lying down   wedge: a door-stop ramp
##   sheave: a pulley wheel, fixed (screwed to something) or on a movable block
##   spool: a cotton reel on an axle with a crank (a winch)   spring: spring_link.gd
## Mass and friction are real: pine 0.5 g/cm3, books ~0.7, a wrapped present 0.3-1.5 kg.

const Mech := preload("res://scripts/mech/mech.gd")
const Rotor := preload("res://scripts/mech/rotor.gd")
const RopeLine := preload("res://scripts/mech/rope_line.gd")
const SpringLink := preload("res://scripts/mech/spring_link.gd")
const GB := preload("res://scripts/greybox.gd")

const LAYERS := 1 | 4  ## world + interior: parts sit on floors and furniture and block the elf


static func _pm(friction: float, bounce := 0.05) -> PhysicsMaterial:
	var m := PhysicsMaterial.new()
	m.friction = friction
	m.bounce = bounce
	return m


static func box_body(parent: Node3D, size: Vector3, pos: Vector3, mass: float, color: Color, nm := "Part", friction := 0.6) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.name = nm
	rb.mass = mass
	rb.collision_layer = LAYERS
	rb.collision_mask = LAYERS
	rb.continuous_cd = true  # small fast bodies (catapult shots, dropped weights) don't tunnel
	rb.physics_material_override = _pm(friction)
	rb.can_sleep = true
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	rb.add_child(cs)
	GB.box(rb, size, Vector3.ZERO, color)
	parent.add_child(rb)
	rb.global_position = pos
	# grab points on every top edge and corner: a rope can tie to any of them
	for x: float in [-0.5, 0.0, 0.5]:
		for z: float in [-0.5, 0.0, 0.5]:
			Mech.add_attach(rb, Vector3(x * size.x, size.y * 0.5, z * size.z), "edge")
	return rb


static func weight(parent: Node3D, pos: Vector3, mass: float, color := Color(0.55, 0.5, 0.45)) -> RigidBody3D:
	var side := pow(mass / 2500.0, 1.0 / 3.0)  # a dense-ish lump (2.5 g/cm3: a jar of coins, a stone)
	return box_body(parent, Vector3.ONE * side, pos, mass, color, "Weight%.1fkg" % mass)


static func present(parent: Node3D, pos: Vector3, mass := 0.8, size := Vector3(0.2, 0.16, 0.2)) -> RigidBody3D:
	var rb := box_body(parent, size, pos, mass, Color(0.75, 0.12, 0.15), "Present")
	GB.box(rb, Vector3(size.x + 0.004, size.y + 0.004, 0.03), Vector3.ZERO, Color(0.95, 0.85, 0.3))
	GB.box(rb, Vector3(0.03, size.y + 0.004, size.z + 0.004), Vector3.ZERO, Color(0.95, 0.85, 0.3))
	return rb


## The elf as a body (0.5 kg, capsule): rigs hang it on ropes and handles. In play the real elf
## hangs its weight the same way through Mech.apply.
static func elf_body(parent: Node3D, pos: Vector3) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.name = "ElfBody"
	rb.mass = Mech.ELF_MASS
	rb.collision_layer = LAYERS
	rb.collision_mask = LAYERS
	rb.continuous_cd = true
	rb.physics_material_override = _pm(Mech.ELF_FOOT_MU)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.05
	cap.height = 0.2
	cs.shape = cap
	rb.add_child(cs)
	GB.cylinder(rb, 0.045, 0.05, 0.12, Vector3(0, -0.02, 0), Color(0.15, 0.5, 0.2))
	GB.sphere(rb, 0.035, Vector3(0, 0.07, 0), Color(0.95, 0.78, 0.65))
	GB.cylinder(rb, 0.0, 0.03, 0.07, Vector3(0, 0.12, 0), Color(0.8, 0.1, 0.12))
	parent.add_child(rb)
	rb.global_position = pos
	Mech.add_attach(rb, Vector3(0, 0.1, 0), "hands")
	return rb


static func plank(parent: Node3D, pos: Vector3, length: float, mass: float, width := 0.04, thick := 0.012, yaw := 0.0) -> RigidBody3D:
	var rb := box_body(parent, Vector3(length, thick, width), pos, mass, Color(0.82, 0.68, 0.45), "Plank", 0.55)
	rb.rotation.y = yaw
	return rb


## A round fulcrum lying across (a crayon, a pencil): static if pinned to the floor, else rolls.
static func fulcrum(parent: Node3D, pos: Vector3, r := 0.015, length := 0.12, pinned := true) -> Node3D:
	var body: CollisionObject3D = StaticBody3D.new() if pinned else RigidBody3D.new()
	body.name = "Fulcrum"
	body.collision_layer = LAYERS
	body.collision_mask = LAYERS
	if body is RigidBody3D:
		(body as RigidBody3D).mass = 0.01
		(body as RigidBody3D).continuous_cd = true
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = r
	cy.height = length
	cs.shape = cy
	cs.rotation_degrees = Vector3(90, 0, 0)
	body.add_child(cs)
	GB.cylinder(body, r, r, length, Vector3.ZERO, Color(0.2, 0.45, 0.85), Vector3(90, 0, 0))
	parent.add_child(body)
	body.global_position = pos
	return body


## A pulley wheel. On a static anchor (a hook in the ceiling, a chair rung) pass parent_body = null;
## on a movable block pass the body it rides on. Returns the sheave node (rope points tie to it).
static func sheave(parent: Node3D, pos: Vector3, r := 0.02) -> Node3D:
	var s := Node3D.new()
	s.name = "Sheave"
	parent.add_child(s)
	s.global_position = pos
	GB.cylinder(s, r, r, 0.012, Vector3.ZERO, Color(0.7, 0.72, 0.75), Vector3(90, 0, 0))
	GB.cylinder(s, r * 0.35, r * 0.35, 0.02, Vector3.ZERO, Color(0.3, 0.3, 0.32), Vector3(90, 0, 0))
	Mech.add_attach(s, Vector3.ZERO, "sheave")
	return s


## A cotton reel on an axle with a crank: a winch. Turning the crank (elf torque) winds the rope in.
static func spool(parent: Node3D, pos: Vector3, r := 0.012, crank := 0.05) -> Node3D:
	var ro := Rotor.new()
	ro.name = "Spool"
	ro.inertia = 0.0004
	ro.theta_min = -1000.0
	ro.theta_max = 1000.0
	ro.friction = 0.004
	ro.damping = 0.001
	ro.round_radius = r
	parent.add_child(ro)
	ro.global_position = pos
	var v := Node3D.new()
	ro.add_child(v)
	ro.visual = v
	GB.cylinder(v, r, r, 0.03, Vector3.ZERO, Color(0.9, 0.85, 0.75), Vector3(90, 0, 0))
	GB.box(v, Vector3(crank, 0.006, 0.006), Vector3(crank * 0.5, 0, 0.02), Color(0.5, 0.3, 0.2))
	Mech.add_attach(v, Vector3(crank, 0, 0.02), "crank")
	return ro


static func rope(parent: Node3D) -> Node3D:
	var r := RopeLine.new()
	r.name = "Rope"
	parent.add_child(r)
	return r


static func spring(parent: Node3D, a: Node3D, wa: Vector3, b: Node3D, wb: Vector3, k: float, rest: float) -> Node3D:
	var s := SpringLink.new()
	s.k = k
	s.rest = rest
	parent.add_child(s)
	s.setup(a, wa, b, wb)
	return s
