extends RigidBody3D
## One present. CARRIED (rides on the sleigh) -> LOOSE (real rigid body) -> DELIVERED (settled on a
## roof) or BROKEN (hit the ground / fell out of the world) or LOST (stuck somewhere that isn't a roof).

signal broken(present: RigidBody3D)
signal delivered(present: RigidBody3D)
signal lost(present: RigidBody3D)

enum State { CARRIED, LOOSE, DELIVERED, BROKEN }

const GB := preload("res://scripts/greybox.gd")

@export var present_mass := 4.0
@export var present_friction := 0.8
@export var settle_speed := 0.2  ## Below this speed on a roof the present counts as settled...
@export var settle_time := 1.2  ## ...for this many seconds -> delivered.
@export var lost_time := 12.0

var state := State.CARRIED
var sleigh: Node3D
var _settle := 0.0
var _loose_time := 0.0


func _ready() -> void:
	mass = present_mass
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	var pm := PhysicsMaterial.new()
	pm.friction = present_friction
	physics_material_override = pm
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 0.4, 0.5)
	cs.shape = shape
	add_child(cs)
	GB.box(self, Vector3(0.5, 0.4, 0.5), Vector3.ZERO, Color(0.1, 0.55, 0.25))
	GB.box(self, Vector3(0.52, 0.42, 0.1), Vector3.ZERO, Color(0.9, 0.1, 0.1))
	GB.box(self, Vector3(0.1, 0.42, 0.52), Vector3.ZERO, Color(0.9, 0.1, 0.1))
	GB.sphere(self, 0.09, Vector3(0, 0.23, 0), Color(0.95, 0.2, 0.2))
	body_entered.connect(_on_body_entered)


func carry(by: Node3D) -> void:
	sleigh = by
	state = State.CARRIED
	freeze = true
	if by is PhysicsBody3D:
		add_collision_exception_with(by)


func release(velocity: Vector3, at: Transform3D) -> void:
	state = State.LOOSE
	_settle = 0.0
	_loose_time = 0.0
	global_transform = at
	freeze = false
	linear_velocity = velocity
	angular_velocity = Vector3.ZERO
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	match state:
		State.CARRIED:
			if sleigh != null and sleigh.has_method("get_carry_transform"):
				global_transform = sleigh.call("get_carry_transform")
		State.LOOSE:
			_loose_time += delta
			if global_position.y < -5.0:
				_break()
				return
			var on_roof := false
			for b in get_colliding_bodies():
				if b.is_in_group("roof"):
					on_roof = true
			if on_roof and linear_velocity.length() < settle_speed:
				_settle += delta
				if _settle >= settle_time:
					state = State.DELIVERED
					freeze = true
					delivered.emit(self)
			else:
				_settle = 0.0
			if _loose_time > lost_time and state == State.LOOSE:
				state = State.BROKEN
				lost.emit(self)


func _on_body_entered(body: Node) -> void:
	if state == State.LOOSE and body.is_in_group("ground"):
		_break()


func _break() -> void:
	if state == State.BROKEN:
		return
	state = State.BROKEN
	_spawn_debris()
	broken.emit(self)


func _spawn_debris() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var colors := [Color(0.1, 0.55, 0.25), Color(0.9, 0.1, 0.1)]
	for i in 6:
		var d := RigidBody3D.new()
		d.mass = 0.3
		var cs := CollisionShape3D.new()
		var s := BoxShape3D.new()
		s.size = Vector3(0.16, 0.12, 0.16)
		cs.shape = s
		d.add_child(cs)
		GB.box(d, s.size, Vector3.ZERO, colors[i % 2])
		parent.add_child(d)
		d.global_position = global_position + Vector3(randf_range(-0.2, 0.2), 0.2, randf_range(-0.2, 0.2))
		d.linear_velocity = Vector3(randf_range(-2.5, 2.5), randf_range(1.5, 3.5), randf_range(-2.5, 2.5))
		d.angular_velocity = Vector3(randf(), randf(), randf()) * 8.0
		get_tree().create_timer(5.0).timeout.connect(d.queue_free)
