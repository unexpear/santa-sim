extends RefCounted
## Visual-mesh carving: subtract boxes from render meshes (exact polygon clipping, attributes
## interpolated). The chimney uses it to cut a CAMERA CHANNEL down the descent path, so no visual
## surface (a roof slab, the house shell's cap, a fascia, a bulb row) can ever sit in front of the
## cutscene camera's near plane inside the flue. Collision is untouched (carve.gd handles colliders).

const CHANNEL_MARGIN := 0.05  ## m beyond the camera near plane


## Transform of n relative to ancestor ref (works before the nodes are in the tree).
static func rel(ref: Node, n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p and p != ref:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


## Carve every MeshInstance3D under root (except the excluded subtrees) with the boxes (root-local).
## MultiMesh instances inside a box are scaled to nothing. Returns the number of meshes changed.
static func carve_channel(root: Node3D, boxes: Array, exclude: Array) -> int:
	var changed := 0
	var all_bb := AABB()
	for i in boxes.size():
		all_bb = boxes[i] if i == 0 else all_bb.merge(boxes[i])
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var skip := false
		for e in exclude:
			if e and (e == n or (e as Node).is_ancestor_of(n)):
				skip = true
				break
		if skip:
			continue
		var xf := rel(root, n as Node3D)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null or mi.skin != null:
				continue
			if not (xf * mi.mesh.get_aabb()).intersects(all_bb):
				continue
			var hit: Array = []
			for b in boxes:
				if (xf * mi.mesh.get_aabb()).intersects(b):
					hit.append(b)
			var nm := _carve_mesh(mi.mesh, xf, hit)
			if nm:
				mi.mesh = nm
				changed += 1
		elif n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null:
				continue
			var dup: MultiMesh = null
			for i in mm.instance_count:
				var ixf: Transform3D = xf * mm.get_instance_transform(i)
				var ib := ixf * mm.mesh.get_aabb()
				for b in boxes:
					if ib.intersects(b):
						if dup == null:
							dup = mm.duplicate()
						dup.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), mm.get_instance_transform(i).origin))
						break
			if dup:
				(n as MultiMeshInstance3D).multimesh = dup
				changed += 1
	return changed


## Planes (mesh space) of a root-space AABB seen through xf: inside = n.p <= d for all six.
static func _planes(b: AABB, xf: Transform3D) -> Array:
	var out := []
	var bt := xf.basis.transposed()
	for ax in 3:
		var nrm := Vector3.ZERO
		nrm[ax] = 1.0
		for s: float in [1.0, -1.0]:
			var n_root := nrm * s
			var d_root: float = (b.end[ax] if s > 0.0 else -b.position[ax])
			out.append([bt * n_root, d_root - n_root.dot(xf.origin)])
	return out


static func _carve_mesh(mesh: Mesh, xf: Transform3D, boxes: Array) -> ArrayMesh:
	if boxes.is_empty():
		return null
	var plane_sets := []
	for b in boxes:
		plane_sets.append(_planes(b, xf))
	var out := ArrayMesh.new()
	var any := false
	for s in mesh.get_surface_count():
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return null
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nr = arr[Mesh.ARRAY_NORMAL]
		var uv = arr[Mesh.ARRAY_TEX_UV]
		var uv2 = arr[Mesh.ARRAY_TEX_UV2]
		var col = arr[Mesh.ARRAY_COLOR]
		var idx = arr[Mesh.ARRAY_INDEX]
		var tri_count: int = (idx.size() if idx != null else v.size()) / 3
		var polys := []
		var surf_changed := false
		for t in tri_count:
			var poly := []
			for k in 3:
				var i: int = idx[t * 3 + k] if idx != null else t * 3 + k
				poly.append([v[i], nr[i] if nr != null else Vector3.UP, uv[i] if uv != null else Vector2.ZERO, uv2[i] if uv2 != null else Vector2.ZERO, col[i] if col != null else Color.WHITE])
			var pieces := [poly]
			for ps in plane_sets:
				var next := []
				for pc in pieces:
					var res := _subtract(pc, ps)
					if res.size() != 1 or res[0] != pc:
						surf_changed = true
					next.append_array(res)
				pieces = next
			polys.append_array(pieces)
		if surf_changed:
			any = true
		var nv := PackedVector3Array()
		var nn := PackedVector3Array()
		var nu := PackedVector2Array()
		var nu2 := PackedVector2Array()
		var nc := PackedColorArray()
		for pc in polys:
			for k in range(1, pc.size() - 1):
				for vv in [pc[0], pc[k], pc[k + 1]]:
					nv.append(vv[0])
					nn.append(vv[1])
					nu.append(vv[2])
					nu2.append(vv[3])
					nc.append(vv[4])
		if nv.is_empty():
			continue
		var na := []
		na.resize(Mesh.ARRAY_MAX)
		na[Mesh.ARRAY_VERTEX] = nv
		if nr != null:
			na[Mesh.ARRAY_NORMAL] = nn
		if uv != null:
			na[Mesh.ARRAY_TEX_UV] = nu
		if uv2 != null:
			na[Mesh.ARRAY_TEX_UV2] = nu2
		if col != null:
			na[Mesh.ARRAY_COLOR] = nc
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, na)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(s))
	return out if any else null


## Convex polygon minus the convex region (all planes inside): the pieces outside it.
static func _subtract(poly: Array, planes: Array) -> Array:
	var keep := []
	var cur := poly
	for pl in planes:
		var n: Vector3 = pl[0]
		var d: float = pl[1]
		var inside := []
		var outside := []
		for i in cur.size():
			var a: Array = cur[i]
			var b: Array = cur[(i + 1) % cur.size()]
			var da: float = n.dot(a[0]) - d
			var db: float = n.dot(b[0]) - d
			if da <= 0.0:
				inside.append(a)
			else:
				outside.append(a)
			if (da < 0.0 and db > 0.0) or (da > 0.0 and db < 0.0):
				var t := da / (da - db)
				var m := [(a[0] as Vector3).lerp(b[0], t), (a[1] as Vector3).lerp(b[1], t).normalized(), (a[2] as Vector2).lerp(b[2], t), (a[3] as Vector2).lerp(b[3], t), (a[4] as Color).lerp(b[4], t)]
				inside.append(m)
				outside.append(m)
		if outside.size() >= 3:
			keep.append(outside)
		if inside.size() < 3:
			return [poly]  # nothing of it reaches the region: keep it whole
		cur = inside
	return keep
