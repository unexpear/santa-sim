extends RefCounted
## Collision helpers for the chimney: cut a genuinely open hole through box colliders (the flue
## through the roof, ceilings, floors and the chimney breast), and build hollow square tubes
## (the brick walls round the open flue / smoke chamber) as plain boxes.

## Transform of node n relative to ancestor ref (works before the nodes are in the tree).
static func rel(ref: Node, n: Node3D) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur != null and cur != ref:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Cut hole (an AABB in ref-local space) out of every box CollisionShape3D under body: each box it
## touches is replaced by up to six boxes round the hole. Returns the number of boxes cut.
static func carve(ref: Node3D, body: Node, hole: AABB) -> int:
	var cut := 0
	for c in body.get_children():
		if not c is CollisionShape3D:
			continue
		var cs := c as CollisionShape3D
		if not cs.shape is BoxShape3D or cs.is_queued_for_deletion():
			continue
		var size := (cs.shape as BoxShape3D).size
		var inv := rel(ref, cs).affine_inverse()
		var hl := AABB(inv * hole.position, Vector3.ZERO)
		for k in 8:
			hl = hl.expand(inv * hole.get_endpoint(k))
		var bx := AABB(-size * 0.5, size)
		if not bx.intersects(hl):
			continue
		var i := bx.intersection(hl)
		if i.size.x < 0.001 or i.size.y < 0.001 or i.size.z < 0.001:
			continue
		var parts: Array = []
		var b0 := bx.position
		var b1 := bx.end
		var i0 := i.position
		var i1 := i.end
		parts.append(AABB(b0, Vector3(i0.x - b0.x, size.y, size.z)))
		parts.append(AABB(Vector3(i1.x, b0.y, b0.z), Vector3(b1.x - i1.x, size.y, size.z)))
		parts.append(AABB(Vector3(i0.x, b0.y, b0.z), Vector3(i.size.x, i0.y - b0.y, size.z)))
		parts.append(AABB(Vector3(i0.x, i1.y, b0.z), Vector3(i.size.x, b1.y - i1.y, size.z)))
		parts.append(AABB(Vector3(i0.x, i0.y, b0.z), Vector3(i.size.x, i.size.y, i0.z - b0.z)))
		parts.append(AABB(Vector3(i0.x, i0.y, i1.z), Vector3(i.size.x, i.size.y, b1.z - i1.z)))
		for p: AABB in parts:
			if p.size.x < 0.002 or p.size.y < 0.002 or p.size.z < 0.002:
				continue
			var ncs := CollisionShape3D.new()
			var s := BoxShape3D.new()
			s.size = p.size
			ncs.shape = s
			ncs.transform = cs.transform * Transform3D(Basis(), p.get_center())
			body.add_child(ncs)
		body.remove_child(cs)
		cs.queue_free()
		cut += 1
	return cut


## Four boxes making a square tube wall of thickness t round the open rect r (x, z) from y0 to y1,
## added to body at offset (body-local).
## t_zpos (optional): a different thickness for the +z (room-side) wall, so it can stop at the
## face of the chimney breast instead of poking out into the room.
static func tube(body: Node, r: Rect2, y0: float, y1: float, t: float, t_zpos := -1.0) -> void:
	var h := y1 - y0
	var yc := (y0 + y1) * 0.5
	var tf := t if t_zpos < 0.0 else t_zpos
	var x0 := r.position.x - t
	var x1 := r.end.x + t
	# back/front (z) walls full outer width, side (x) walls between them
	box(body, Vector3(x1 - x0, h, t), Vector3((x0 + x1) * 0.5, yc, r.position.y - t * 0.5))
	if tf > 0.002:
		box(body, Vector3(x1 - x0, h, tf), Vector3((x0 + x1) * 0.5, yc, r.end.y + tf * 0.5))
	box(body, Vector3(t, h, r.size.y), Vector3(r.position.x - t * 0.5, yc, r.get_center().y))
	box(body, Vector3(t, h, r.size.y), Vector3(r.end.x + t * 0.5, yc, r.get_center().y))


static func box(body: Node, size: Vector3, pos: Vector3, rot := Basis()) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	cs.transform = Transform3D(rot, pos)
	body.add_child(cs)
	return cs
