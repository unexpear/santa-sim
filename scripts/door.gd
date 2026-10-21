extends Node3D
## A real interior door: hinged at this node's origin, the slab runs along local +X. The collision
## (an AnimatableBody3D on the interior physics layer) swings with the visual, so a closed door
## blocks the elf and an open doorway is passable. Press E near it (gadgets.gd) to open / close.
## Swings stop rather than shove the elf through a wall: if the elf is in the way, the door waits.

signal creaked(position: Vector3, radius: float)  ## stealth hook: residents can listen for this

const INTERIOR_LAYER := 4

@export var width := 0.98  ## slab width (m), fills the opening
@export var height := 2.05
@export var thickness := 0.1  ## collision thickness: at least 2x the elf's 0.05 m capsule radius
@export var open_angle := 95.0  ## degrees when fully open (sign picks the room it swings into)
@export var swing_speed := 160.0  ## degrees per second
@export var creak_radius := 3.5  ## metres: how far a creak carries (house scale, not elf scale)
@export var locked := false  ## the street door: the elf uses the chimney

var angle := 0.0  ## current opening, degrees (0 = closed)
var target := 0.0
var swing_sign := 1.0  ## +1 or -1: which side it opens toward
var prefer_sign := 1.0  ## the side with the bigger room (an open door there blocks least)
var elf: Node3D  ## set by the interior, used to avoid swinging through the elf
var visual: Node3D
var body: AnimatableBody3D
var _creaked := false


func setup(mesh: Mesh, w: float, start_angle: float, sgn: float) -> void:
	width = w
	swing_sign = sgn
	visual = MeshInstance3D.new()
	(visual as MeshInstance3D).mesh = mesh
	visual.scale = Vector3(w / 0.9, 1.0, 1.0)  # the modelled slab is 0.9 m wide
	add_child(visual)
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
	angle = start_angle
	target = start_angle
	_apply()


func is_open() -> bool:
	return target > 30.0


## Open / close. When opening, the door swings away from whoever opened it (opener in world space).
func toggle(opener := Vector3.INF) -> bool:
	if locked:
		return false
	if target > 1.0:
		target = 0.0
	else:
		if angle < 1.0:
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
	_creaked = false
	return true


## Set the door instantly (scripted checks). Opens to the less obstructed side.
func set_open(open: bool, instant := true) -> void:
	if open and angle < 1.0:
		var bp := _blocked_open(prefer_sign)
		var bo := _blocked_open(-prefer_sign)
		swing_sign = prefer_sign if bp <= bo else -prefer_sign
	target = open_angle if open else 0.0
	if instant:
		angle = target
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


func _apply() -> void:
	var r := deg_to_rad(angle) * swing_sign
	visual.rotation.y = r
	body.rotation.y = r


func _physics_process(delta: float) -> void:
	if is_equal_approx(angle, target):
		return
	var step := signf(target - angle) * minf(absf(target - angle), swing_speed * delta)
	var next := angle + step
	if elf and _blocks_elf(next):
		return  # wait for the elf to move out of the swing
	if not _creaked and absf(step) > 0.0:
		_creaked = true
		creaked.emit(world_mid(), creak_radius)
	angle = next
	_apply()


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
