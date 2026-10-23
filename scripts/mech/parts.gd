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
const PM := preload("res://scripts/mech/part_models.gd")  ## the shared detailed meshes
const ES := preload("res://scripts/elf_size.gd")
const ELF_MODEL := preload("res://assets/models/elf.glb")

const LAYERS := 1 | 4  ## world + interior: parts sit on floors and furniture and block the elf


static func _pm(friction: float, bounce := 0.05) -> PhysicsMaterial:
	var m := PhysicsMaterial.new()
	m.friction = friction
	m.bounce = bounce
	return m


static func box_body(parent: Node3D, size: Vector3, pos: Vector3, mass: float, color: Color, nm := "Part", friction := 0.6, model := "") -> RigidBody3D:
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
	if model == "" or PM.add(rb, model, Vector3.ZERO, Vector3.ZERO, PM.fit(model, size)) == null:
		GB.box(rb, size, Vector3.ZERO, color)
	parent.add_child(rb)
	rb.global_position = pos
	# grab points on every top edge and corner: a rope can tie to any of them
	for x: float in [-0.5, 0.0, 0.5]:
		for z: float in [-0.5, 0.0, 0.5]:
			Mech.add_attach(rb, Vector3(x * size.x, size.y * 0.5, z * size.z), "edge")
	return rb


## A counterweight. "tin": a biscuit tin of marbles (packed glass ~1.5 g/cm3, an upright
## cylinder 2.4x as tall as its radius). "sack": a hessian sack of coal (~0.8 g/cm3).
static func weight(parent: Node3D, pos: Vector3, mass: float, kind := "tin") -> RigidBody3D:
	if kind == "sack":
		var s := pow(mass / 1.0, 1.0 / 3.0)
		var rb0 := box_body(parent, PM.REF["CoalSack"] * s, pos, mass, Color(0.55, 0.42, 0.26), "CoalSack%.1fkg" % mass, 0.8, "CoalSack")
		return rb0
	var r := pow(mass / 1500.0 / (2.4 * PI), 1.0 / 3.0)
	var rb := _round_body(parent, pos, mass, "MarbleTin%.1fkg" % mass, CylinderShape3D.new(), r, 2.4 * r, 0.45)
	if PM.add(rb, "MarbleTin", Vector3.ZERO, Vector3.ZERO, Vector3.ONE * (r / 0.05)) == null:
		GB.cylinder(rb, r, r, 2.4 * r, Vector3.ZERO, Color(0.7, 0.7, 0.75))
	for a in 6:
		Mech.add_attach(rb, Vector3(cos(a * TAU / 6.0) * r, 1.2 * r, sin(a * TAU / 6.0) * r), "rim")
	return rb


static func _round_body(parent: Node3D, pos: Vector3, mass: float, nm: String, shape: Shape3D, r: float, h: float, friction: float) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.name = nm
	rb.mass = mass
	rb.collision_layer = LAYERS
	rb.collision_mask = LAYERS
	rb.continuous_cd = true
	rb.physics_material_override = _pm(friction)
	var cs := CollisionShape3D.new()
	if shape is CylinderShape3D:
		(shape as CylinderShape3D).radius = r
		(shape as CylinderShape3D).height = h
	elif shape is SphereShape3D:
		(shape as SphereShape3D).radius = r
	cs.shape = shape
	rb.add_child(cs)
	parent.add_child(rb)
	rb.global_position = pos
	return rb


static func present(parent: Node3D, pos: Vector3, mass := 0.8, size := Vector3(0.2, 0.16, 0.2)) -> RigidBody3D:
	var rb := box_body(parent, size, pos, mass, Color(0.75, 0.12, 0.15), "Present", 0.6, "Present")
	if not PM.has("Present"):
		GB.box(rb, Vector3(size.x + 0.004, size.y + 0.004, 0.03), Vector3.ZERO, Color(0.95, 0.85, 0.3))
		GB.box(rb, Vector3(0.03, size.y + 0.004, size.z + 0.004), Vector3.ZERO, Color(0.95, 0.85, 0.3))
	return rb


## A hardback (0.7 g/cm3 paper): 15 x 21 cm, 2.5 cm thick is ~0.55 kg.
static func book(parent: Node3D, pos: Vector3, mass := 0.4, size := Vector3(0.15, 0.025, 0.21), yaw := 0.0) -> RigidBody3D:
	var rb := box_body(parent, size, pos, mass, Color(0.2, 0.35, 0.7), "Book", 0.5, "Book")
	rb.rotation.y = yaw
	return rb


## A 6 cm glass bauble (20 g). Its cap and loop stop it rolling far (rolling damping).
static func bauble(parent: Node3D, pos: Vector3, mass := 0.02, r := 0.03) -> RigidBody3D:
	var rb := _round_body(parent, pos, mass, "Bauble", SphereShape3D.new(), r, 0.0, 0.8)
	rb.angular_damp = 6.0
	if PM.add(rb, "Bauble", Vector3.ZERO, Vector3.ZERO, Vector3.ONE * (r / 0.03)) == null:
		GB.sphere(rb, r, Vector3.ZERO, Color(0.9, 0.2, 0.25))
	Mech.add_attach(rb, Vector3(0, r * 1.3, 0), "loop")
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
	var H := ES.ELF_HEIGHT
	cap.radius = H * 0.2
	cap.height = H
	cs.shape = cap
	rb.add_child(cs)
	var model := ELF_MODEL.instantiate() as Node3D
	model.scale = Vector3.ONE * (H / ES.MODEL_HEIGHT)
	model.position = Vector3(0, -H * 0.5, 0)
	rb.add_child(model)
	GB.toonify(model)
	parent.add_child(rb)
	rb.global_position = pos
	Mech.add_attach(rb, Vector3(0, H * 0.42, 0), "hands")
	return rb


static func plank(parent: Node3D, pos: Vector3, length: float, mass: float, width := 0.04, thick := 0.012, yaw := 0.0) -> RigidBody3D:
	var rb := box_body(parent, Vector3(length, thick, width), pos, mass, Color(0.82, 0.68, 0.45), "Ruler", 0.55, "Ruler")
	rb.rotation.y = yaw
	return rb


## A long wooden cooking spoon (50 cm, beech 0.7 g/cm3 ~ 80 g) as a seesaw / catapult arm, bowl
## at +x. Collision: the handle bar, a dished floor under the bowl and a lip each end of it.
static func spoon(parent: Node3D, pos: Vector3, mass := 0.08) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.name = "Spoon"
	rb.mass = mass
	rb.collision_layer = LAYERS
	rb.collision_mask = LAYERS
	rb.continuous_cd = true
	rb.physics_material_override = _pm(0.55)
	for b in [[Vector3(0.41, 0.012, 0.03), Vector3(-0.045, 0, 0)], [Vector3(0.09, 0.006, 0.06), Vector3(0.205, -0.006, 0)],
			[Vector3(0.008, 0.02, 0.06), Vector3(0.158, 0.004, 0)], [Vector3(0.008, 0.02, 0.06), Vector3(0.252, 0.004, 0)],
			[Vector3(0.09, 0.02, 0.006), Vector3(0.205, 0.004, 0.03)], [Vector3(0.09, 0.02, 0.006), Vector3(0.205, 0.004, -0.03)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b[0]
		cs.shape = bs
		cs.position = b[1]
		rb.add_child(cs)
	if PM.add(rb, "Spoon") == null:
		GB.box(rb, Vector3(0.5, 0.012, 0.06), Vector3.ZERO, Color(0.78, 0.58, 0.36))
	parent.add_child(rb)
	rb.global_position = pos
	for x: float in [-0.24, -0.12, 0.0, 0.12]:
		Mech.add_attach(rb, Vector3(x, 0.006, 0), "edge")
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
	# r <= 1 cm: a jumbo crayon lying across; fatter: a cotton reel on its side
	var vis: MeshInstance3D = null
	if r <= 0.01:
		vis = PM.add(body, "Crayon", Vector3.ZERO, Vector3(0, 90, 0), Vector3(length / 0.1, r / 0.006, r / 0.006))
	else:
		vis = PM.add(body, "CottonReel", Vector3.ZERO, Vector3.ZERO, Vector3(r / 0.019, r / 0.019, length / 0.07))
	if vis == null:
		GB.cylinder(body, r, r, length, Vector3.ZERO, Color(0.2, 0.45, 0.85), Vector3(90, 0, 0))
	parent.add_child(body)
	body.global_position = pos
	return body


## A pulley wheel. On a static anchor (a hook in the ceiling, a chair rung) pass parent_body = null;
## on a movable block pass the body it rides on. Returns the sheave node (rope points tie to it).
static func sheave(parent: Node3D, pos: Vector3, r := 0.02, hook_down := false) -> Node3D:
	var s := Node3D.new()
	s.name = "Sheave"
	parent.add_child(s)
	s.global_position = pos
	if PM.add(s, "Pulley", Vector3.ZERO, Vector3(0, 0, 180) if hook_down else Vector3.ZERO, Vector3.ONE * (r / 0.02)) == null:
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
	var k := r / 0.012
	if PM.add(v, "CottonReel", Vector3.ZERO, Vector3.ZERO, Vector3.ONE * k) == null:
		GB.cylinder(v, r, r, 0.03, Vector3.ZERO, Color(0.9, 0.85, 0.75), Vector3(90, 0, 0))
		GB.box(v, Vector3(crank, 0.006, 0.006), Vector3(crank * 0.5, 0, 0.02), Color(0.5, 0.3, 0.2))
	else:
		PM.add(v, "ReelCrank", Vector3.ZERO, Vector3.ZERO, Vector3(crank / 0.05, 1.0, 1.0) * k)
	Mech.add_attach(v, Vector3(crank, 0, 0.034 * k), "crank")
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
