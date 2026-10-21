extends RefCounted
## Prop meshes for the real-map town, built once and drawn with MultiMesh:
## gum trees (3 variants), streetlights, picket fence panels, low brick walls, hedges,
## letterboxes, Hills Hoists and low-poly Christmas bulbs for the background houses.

const GB := preload("res://scripts/greybox.gd")
const Suburb := preload("res://scripts/suburb.gd")
const MeshBatch := preload("res://scripts/town/mesh_batch.gd")

const BARK := Color(0.92, 0.86, 0.78)
const GREENS: Array[Color] = [Color(0.3, 0.6, 0.3), Color(0.22, 0.55, 0.42), Color(0.42, 0.66, 0.25)]


static func _b() -> RefCounted:
	return MeshBatch.new()


static func _k(b, c: Color, emission := 0.0) -> String:
	var key := "%s_%s" % [c.to_html(false), emission]
	if not b.has_material(key):
		b.register(key, GB.mat(c, emission))
	return key


## Blobby, crooked gum tree (pale twisting trunk + lumpy canopy), ~7 m tall at scale 1.
static func gum_tree(variant: int) -> ArrayMesh:
	var b = _b()
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + variant
	var bark := _k(b, BARK)
	var h := 6.5 + variant * 0.7
	var lean := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.4, 0.4))
	b.cylinder(bark, Vector3.ZERO, 0.42, 0.24, h * 0.55, 7, lean)
	var mid := Vector3.UP * h * 0.55 + lean
	b.cylinder(bark, mid, 0.24, 0.12, h * 0.4, 6, -lean * 1.2 + Vector3(0.2, 0, 0))
	b.cylinder(bark, mid, 0.16, 0.07, h * 0.38, 5, Vector3(1.3, 0, 0.6))
	var fol := "fol%d" % variant
	b.register(fol, Suburb.foliage(GREENS[variant % 3]))
	var lumps := 7 + variant
	for k in lumps:
		var a := TAU * float(k) / float(lumps) + rng.randf_range(-0.4, 0.4)
		var rad := rng.randf_range(0.7, 2.1)
		var off := Vector3(cos(a) * rad, h + rng.randf_range(-0.7, 1.1), sin(a) * rad) + lean * 0.3
		b.sphere(fol, off, rng.randf_range(1.05, 1.7), Vector3(1.15, 0.8, 1.15), 5, 8)
	b.sphere(fol, Vector3(0, h + 1.3, 0) + lean * 0.3, rng.randf_range(1.2, 1.6), Vector3(1.1, 0.85, 1.1), 5, 8)
	return b.to_array_mesh()


## Streetlight: pole at origin, arm + head out toward +X.
static func streetlight() -> ArrayMesh:
	var b = _b()
	var pole := _k(b, Color(0.3, 0.32, 0.38))
	b.cylinder(pole, Vector3.ZERO, 0.11, 0.07, 5.6, 8)
	b.beam(pole, Vector3(0, 5.5, 0), Vector3(1.6, 5.62, 0), 0.09, 0.09)
	b.abox(_k(b, Color(0.2, 0.21, 0.26)), Vector3(1.45, 5.47, 0), Vector3(0.6, 0.18, 0.32))
	b.abox(_k(b, Color(1.0, 0.75, 0.4), 2.5), Vector3(1.45, 5.36, 0), Vector3(0.5, 0.05, 0.26), 0.0, false)
	return b.to_array_mesh()


## 2 m fence panel along X, centred, standing on y = 0. style: 0 picket, 1 low brick wall, 2 hedge.
static func fence_panel(style: int, color: Color) -> ArrayMesh:
	var b = _b()
	match style:
		0:
			var k := _k(b, color)
			b.abox(k, Vector3(-0.95, 0.55, 0), Vector3(0.12, 1.1, 0.12))
			b.abox(k, Vector3(0, 0.3, 0), Vector3(2.0, 0.07, 0.05))
			b.abox(k, Vector3(0, 0.75, 0), Vector3(2.0, 0.07, 0.05))
			for i in 8:
				var x := -0.85 + i * 0.245
				b.abox(k, Vector3(x, 0.48, 0.04), Vector3(0.09, 0.96, 0.03))
				b.beam(k, Vector3(x - 0.045, 0.96, 0.04), Vector3(x, 1.03, 0.04), 0.03, 0.03)
		1:
			var bk := "brick"
			var m := ShaderMaterial.new()
			m.shader = preload("res://shaders/toon.gdshader")
			m.set_shader_parameter("albedo", color)
			m.set_shader_parameter("pattern", 5)
			m.set_shader_parameter("pattern_color", color.lerp(Color(0.95, 0.9, 0.8), 0.5))
			b.register(bk, m)
			b.abox(bk, Vector3(0, 0.4, 0), Vector3(2.0, 0.8, 0.25))
			b.abox(_k(b, color.lightened(0.3)), Vector3(0, 0.83, 0), Vector3(2.04, 0.07, 0.32))
			b.abox(bk, Vector3(-0.95, 0.5, 0), Vector3(0.36, 1.0, 0.36))
		_:
			var fol := "hedge"
			b.register(fol, Suburb.foliage(color))
			for i in 3:
				b.sphere(fol, Vector3(-0.66 + i * 0.66, 0.55, 0), 0.62, Vector3(1.0, 0.95, 0.75), 4, 7)
	return b.to_array_mesh()


static func letterbox(color: Color) -> ArrayMesh:
	var b = _b()
	b.abox(_k(b, Color(0.45, 0.32, 0.22)), Vector3(0, 0.5, 0), Vector3(0.12, 1.0, 0.12))
	var k := _k(b, color)
	b.abox(k, Vector3(0, 1.12, 0), Vector3(0.36, 0.3, 0.5))
	b.cylinder(k, Vector3(0, 1.22, -0.25), 0.18, 0.18, 0.5, 8)  # rounded top hint
	b.abox(_k(b, Color(1.0, 0.85, 0.2)), Vector3(0, 1.12, 0.255), Vector3(0.22, 0.04, 0.01))
	return b.to_array_mesh()


static func hills_hoist() -> ArrayMesh:
	var b = _b()
	var k := _k(b, Color(0.75, 0.78, 0.8))
	b.cylinder(k, Vector3.ZERO, 0.05, 0.05, 2.1, 6)
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		b.beam(k, Vector3(0, 2.05, 0), Vector3(cos(a) * 2.0, 1.8, sin(a) * 2.0), 0.04, 0.04)
	var line := _k(b, Color(0.9, 0.9, 0.88))
	for r in [0.9, 1.5, 1.95]:
		for i in 4:
			var a0 := TAU * i / 4.0 + 0.4
			var a1 := TAU * (i + 1) / 4.0 + 0.4
			var y: float = 2.05 - 0.25 * r / 2.0
			b.beam(line, Vector3(cos(a0) * r, y, sin(a0) * r), Vector3(cos(a1) * r, y, sin(a1) * r), 0.015, 0.015)
	# a towel and a Santa hat on the line
	b.abox(_k(b, Color(0.95, 0.3, 0.3)), Vector3(cos(0.4) * 1.5 * 0.7, 1.6, sin(0.4) * 1.5 * 0.9), Vector3(0.7, 0.7, 0.03), 30.0)
	return b.to_array_mesh()


## Low-poly C9 bulb (same UV convention as light_string.gd: UV.y < 0.2 is the socket) for the
## thousands of background bulbs.
static func lowpoly_bulb(w := 0.09, l := 0.2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prof: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(0.32, 0.0), Vector2(0.32, 0.18), Vector2(0.48, 0.42), Vector2(0.42, 0.7), Vector2(0.0, 1.0)]
	var segs := 6
	for i in prof.size() - 1:
		var a := prof[i]
		var c := prof[i + 1]
		for s in segs:
			var a0 := TAU * float(s) / float(segs)
			var a1 := TAU * float(s + 1) / float(segs)
			var p := [Vector3(cos(a0) * a.x * w, a.y * l, sin(a0) * a.x * w), Vector3(cos(a1) * a.x * w, a.y * l, sin(a1) * a.x * w),
					Vector3(cos(a1) * c.x * w, c.y * l, sin(a1) * c.x * w), Vector3(cos(a0) * c.x * w, c.y * l, sin(a0) * c.x * w)]
			var uvs := [a.y, a.y, c.y, c.y]
			for idx in [0, 2, 1, 0, 3, 2]:
				var v: Vector3 = p[idx]
				st.set_normal(Vector3(v.x, 0.25 * w, v.z).normalized())
				st.set_uv(Vector2(0, uvs[idx]))
				st.add_vertex(v)
	return st.commit()
