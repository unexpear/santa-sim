extends RefCounted
## Merges lots of small toon-shaded pieces into a few big meshes: one MeshInstance3D per
## (spatial chunk, material key). Hundreds of houses end up as a few hundred draw calls.
## Godot front faces wind clockwise; every add_* takes an outward hint and fixes the winding.

var chunk_size := 128.0
var chunk := Vector2i.ZERO
var xform := Transform3D.IDENTITY  ## Applied to everything added (house-local -> world).

var _tools: Dictionary = {}  # "cx,cz|key" -> SurfaceTool
var _mats: Dictionary = {}  # key -> Material
var tri_count := 0
var col_sink = null  ## Another MeshBatch that receives world-space triangles while col_on is true (collision).
var col_on := false
var col_key := "col"
var no_shadow: Dictionary = {}  ## material keys that never cast shadows (glass, trims, lights)


func set_chunk_at(p: Vector3) -> void:
	chunk = Vector2i(floori(p.x / chunk_size), floori(p.z / chunk_size))


func register(key: String, m: Material) -> void:
	_mats[key] = m


func has_material(key: String) -> bool:
	return _mats.has(key)


func _st(key: String) -> SurfaceTool:
	var k := "%d,%d|%s" % [chunk.x, chunk.y, key]
	var st: SurfaceTool = _tools.get(k)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[k] = st
	return st


## World-space triangle (xform NOT applied).
func tri_w(key: String, a: Vector3, b: Vector3, c: Vector3, hint: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-10:
		return
	if n.dot(hint) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	var st := _st(key)
	st.set_normal(n)
	st.set_uv(Vector2(a.x + a.z, a.y))
	st.add_vertex(a)
	st.set_normal(n)
	st.set_uv(Vector2(b.x + b.z, b.y))
	st.add_vertex(b)
	st.set_normal(n)
	st.set_uv(Vector2(c.x + c.z, c.y))
	st.add_vertex(c)
	tri_count += 1


func tri(key: String, a: Vector3, b: Vector3, c: Vector3, hint: Vector3) -> void:
	var wa := xform * a
	var wb := xform * b
	var wc := xform * c
	tri_w(key, wa, wb, wc, xform.basis * hint)
	if col_on and col_sink != null:
		col_sink.chunk = chunk
		col_sink.tri_w(col_key, wa, wb, wc, xform.basis * hint)


func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, hint: Vector3) -> void:
	tri(key, a, b, c, hint)
	tri(key, a, c, d, hint)


## Box in the current frame. t = local transform of the box centre.
func box(key: String, t: Transform3D, size: Vector3, skip_bottom := true) -> void:
	var h := size * 0.5
	var c: Array[Vector3] = []
	for i in 8:
		c.append(t * Vector3(h.x if (i & 1) != 0 else -h.x, h.y if (i & 2) != 0 else -h.y, h.z if (i & 4) != 0 else -h.z))
	var faces := [[0, 1, 3, 2, Vector3(0, 0, -1)], [4, 5, 7, 6, Vector3(0, 0, 1)], [0, 2, 6, 4, Vector3(-1, 0, 0)],
			[1, 3, 7, 5, Vector3(1, 0, 0)], [2, 3, 7, 6, Vector3(0, 1, 0)], [0, 1, 5, 4, Vector3(0, -1, 0)]]
	for f in faces:
		if skip_bottom and f[4] == Vector3(0, -1, 0):
			continue
		quad(key, c[f[0]], c[f[1]], c[f[2]], c[f[3]], t.basis * f[4])


## Axis-aligned box helper (local frame): centre + size, optional yaw (deg) and roll.
func abox(key: String, centre: Vector3, size: Vector3, yaw_deg := 0.0, skip_bottom := true) -> void:
	box(key, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), centre), size, skip_bottom)


## Box spanning from a to b (local frame) with a square-ish cross section.
func beam(key: String, a: Vector3, b: Vector3, w: float, h: float) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var z := d / l
	var up := Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	box(key, Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, h, l), false)


func cylinder(key: String, base: Vector3, r_bot: float, r_top: float, h: float, segs := 8, lean := Vector3.ZERO) -> void:
	var top := base + Vector3.UP * h + lean
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		quad(key, base + d0 * r_bot, base + d1 * r_bot, top + d1 * r_top, top + d0 * r_top, (d0 + d1))
		if r_top > 0.001:
			tri(key, top, top + d0 * r_top, top + d1 * r_top, Vector3.UP)


## Flat polygon (x,z in the current frame) at height y, facing up (or down).
func flat_poly(key: String, pts: PackedVector2Array, y: float, up := true) -> void:
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		return
	var hint := Vector3.UP if up else Vector3.DOWN
	for i in range(0, idx.size(), 3):
		var a := pts[idx[i]]
		var b := pts[idx[i + 1]]
		var c := pts[idx[i + 2]]
		tri(key, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), hint)


## Flat strip along a polyline (x,z) at height y. Mitred joints.
func ribbon(key: String, pts: PackedVector2Array, width: float, y: float) -> void:
	var n := pts.size()
	if n < 2:
		return
	var hw := width * 0.5
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in n:
		var t: Vector2
		if i == 0:
			t = (pts[1] - pts[0])
		elif i == n - 1:
			t = (pts[n - 1] - pts[n - 2])
		else:
			t = (pts[i] - pts[i - 1]).normalized() + (pts[i + 1] - pts[i]).normalized()
		t = t.normalized()
		var nrm := Vector2(-t.y, t.x)
		var s := 1.0
		if i > 0 and i < n - 1:
			var seg := (pts[i] - pts[i - 1]).normalized()
			s = 1.0 / maxf(absf(Vector2(-seg.y, seg.x).dot(nrm)), 0.5)
		left.append(pts[i] + nrm * hw * s)
		right.append(pts[i] - nrm * hw * s)
	for i in n - 1:
		quad(key, Vector3(left[i].x, y, left[i].y), Vector3(left[i + 1].x, y, left[i + 1].y),
				Vector3(right[i + 1].x, y, right[i + 1].y), Vector3(right[i].x, y, right[i].y), Vector3.UP)


## Raised strip (kerb, low wall) along a polyline.
func wall_line(key: String, pts: PackedVector2Array, width: float, y0: float, h: float) -> void:
	for i in pts.size() - 1:
		var a := Vector3(pts[i].x, y0 + h * 0.5, pts[i].y)
		var b := Vector3(pts[i + 1].x, y0 + h * 0.5, pts[i + 1].y)
		beam(key, a, b, width, h)


## Squashed low-poly sphere (canopy lumps, letterbox tops).
func sphere(key: String, c: Vector3, r: float, squash := Vector3.ONE, rings := 5, segs := 8) -> void:
	for i in rings:
		var t0 := PI * float(i) / float(rings)
		var t1 := PI * float(i + 1) / float(rings)
		for j in segs:
			var p0 := TAU * float(j) / float(segs)
			var p1 := TAU * float(j + 1) / float(segs)
			var a := Vector3(sin(t0) * cos(p0), cos(t0), sin(t0) * sin(p0))
			var b := Vector3(sin(t0) * cos(p1), cos(t0), sin(t0) * sin(p1))
			var cc := Vector3(sin(t1) * cos(p1), cos(t1), sin(t1) * sin(p1))
			var d := Vector3(sin(t1) * cos(p0), cos(t1), sin(t1) * sin(p0))
			var hint := (a + b + cc + d)
			if i > 0:
				tri(key, c + a * r * squash, c + b * r * squash, c + cc * r * squash, hint)
			if i < rings - 1:
				tri(key, c + a * r * squash, c + cc * r * squash, c + d * r * squash, hint)


func disc(key: String, c: Vector2, r: float, y: float, segs := 14) -> void:
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		tri(key, Vector3(c.x, y, c.y), Vector3(c.x + cos(a0) * r, y, c.y + sin(a0) * r), Vector3(c.x + cos(a1) * r, y, c.y + sin(a1) * r), Vector3.UP)


## One MeshInstance3D per (chunk, material). Returns the instances.
func commit(parent: Node3D, cast_shadow := true, vis_end := 0.0, layers := 1) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for k in _tools:
		var st: SurfaceTool = _tools[k]
		var key: String = (k as String).get_slice("|", 1)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _mats.get(key)
		mi.name = "Batch_" + (k as String).replace("|", "_").replace(",", "_")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (cast_shadow and not no_shadow.has(key)) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = layers
		if vis_end > 0.0:
			mi.visibility_range_end = vis_end
			mi.visibility_range_end_margin = 20.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(mi)
		out.append(mi)
	_tools.clear()
	return out


## Everything added so far as ONE multi-surface ArrayMesh (for MultiMesh props). Ignores chunks.
func to_array_mesh() -> ArrayMesh:
	var am := ArrayMesh.new()
	for k in _tools:
		var st: SurfaceTool = _tools[k]
		var key: String = (k as String).get_slice("|", 1)
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, _mats.get(key))
	_tools.clear()
	return am


## Collision faces: [{"chunk": Vector2i, "key": String, "faces": PackedVector3Array}], then clears.
func faces_by_chunk() -> Array:
	var out: Array = []
	for k in _tools:
		var st: SurfaceTool = _tools[k]
		var arrs := st.commit_to_arrays()
		var ks := k as String
		var cc := ks.get_slice("|", 0)
		out.append({"chunk": Vector2i(int(cc.get_slice(",", 0)), int(cc.get_slice(",", 1))), "key": ks.get_slice("|", 1),
				"faces": arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array})
	_tools.clear()
	return out


## All triangles added so far as one face list (collision templates), then clears.
func faces_all() -> PackedVector3Array:
	var out := PackedVector3Array()
	for e in faces_by_chunk():
		out.append_array(e.faces)
	return out
