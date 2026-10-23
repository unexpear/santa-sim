extends MultiMeshInstance3D
## A real string of C9-style Christmas lights along a polyline (parent-local points):
## a thin dark wire clipped at regular points and sagging slightly (catenary-ish) between clips,
## with small teardrop bulbs standing up from their sockets at a slight random tilt.
## The bulbs are this node's MultiMesh; the wire is a child MultiMesh of short tube segments.
## chase = running pulses that travel from the first point toward the last one ("toward the best
## approach" when the points are ordered along the landing direction). Bulbs twinkle subtly.
## A few faint coloured OmniLights along the string spill colour onto roofs and walls.

const BULB_SHADER := preload("res://shaders/bulb.gdshader")
const GB := preload("res://scripts/greybox.gd")

@export var bulb_spacing := 0.32
@export var clip_spacing := 1.3  ## Distance between the clips holding the wire up.
@export var sag_ratio := 0.05  ## Wire sag at mid-span as a fraction of the span length.
@export var wire_segments_per_span := 6
@export var wire_radius := 0.014
@export var bulb_width := 0.075
@export var bulb_length := 0.17
@export var bulb_tilt_deg := 18.0
@export var pulse_wavelength := 3.0
@export var spill_every := 4.0  ## Metres between colour-spill lights (0 = none).
@export var spill_energy := 0.35
@export var spill_range := 2.8
@export var max_distance_scale := 2.2  ## How much bulbs grow with distance so far strings stay readable.

const PALETTE: Array[Color] = [Color(1.0, 0.08, 0.05), Color(0.05, 1.0, 0.2), Color(0.1, 0.35, 1.0), Color(1.0, 0.65, 0.05), Color(0.9, 0.2, 1.0)]

static var _bulb_mesh: ArrayMesh


static func _make_bulb_mesh(w: float, l: float) -> ArrayMesh:
	# Lathed C9 teardrop: socket (UV.y < 0.2) then a fat glass body tapering to a point at the top.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 9
	var segs := 8
	var prof: Array[Vector2] = []  # (radius, height)
	prof.append(Vector2(0.0, 0.0))
	prof.append(Vector2(0.32, 0.0))
	prof.append(Vector2(0.32, 0.18))
	for i in range(1, rings + 1):
		var t := float(i) / float(rings)
		var r := sin(PI * pow(t, 0.75)) * (1.0 - t * 0.35)
		prof.append(Vector2(r * 0.5, 0.18 + t * 0.82))
	for i in prof.size() - 1:
		var a := prof[i]
		var b := prof[i + 1]
		for s in segs:
			var a0 := TAU * float(s) / float(segs)
			var a1 := TAU * float(s + 1) / float(segs)
			var p := [Vector3(cos(a0) * a.x * w, a.y * l, sin(a0) * a.x * w), Vector3(cos(a1) * a.x * w, a.y * l, sin(a1) * a.x * w),
					Vector3(cos(a1) * b.x * w, b.y * l, sin(a1) * b.x * w), Vector3(cos(a0) * b.x * w, b.y * l, sin(a0) * b.x * w)]
			var uvs := [Vector2(0, a.y), Vector2(0, a.y), Vector2(0, b.y), Vector2(0, b.y)]
			for idx in [0, 2, 1, 0, 3, 2]:
				var v: Vector3 = p[idx]
				var n := Vector3(v.x, 0.25 * w, v.z).normalized()
				st.set_normal(n)
				st.set_uv(uvs[idx])
				st.add_vertex(v)
	return st.commit()


func setup(points: PackedVector3Array, color: Color, chase := false, energy := 1.8, mixed := false, spill := true) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(points) + str(color))
	# 1) Clip points along the polyline.
	var clips := PackedVector3Array()
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var n := maxi(1, int(round(a.distance_to(b) / clip_spacing)))
		for k in n:
			clips.append(a.lerp(b, float(k) / float(n)))
	clips.append(points[points.size() - 1])
	# 2) Wire polyline with sag between clips.
	var wire := PackedVector3Array()
	for i in range(clips.size() - 1):
		var a := clips[i]
		var b := clips[i + 1]
		var sag := a.distance_to(b) * sag_ratio
		for k in wire_segments_per_span:
			var t := float(k) / float(wire_segments_per_span)
			wire.append(a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t))
	wire.append(clips[clips.size() - 1])
	# 3) Bulbs at even spacing along the wire.
	var xforms: Array[Transform3D] = []
	var cols: Array[Color] = []
	var data: Array[Color] = []
	var acc := 0.0
	var next := bulb_spacing * 0.5
	var count := 0
	for i in range(wire.size() - 1):
		var a := wire[i]
		var b := wire[i + 1]
		var seg := a.distance_to(b)
		if seg < 0.0001:
			continue
		var tangent := (b - a) / seg
		while next <= acc + seg:
			var p := a.lerp(b, (next - acc) / seg)
			var side := tangent.cross(Vector3.UP)
			if side.length() < 0.01:
				side = Vector3.RIGHT
			side = side.normalized()
			var tilt := deg_to_rad(bulb_tilt_deg)
			var basis := Basis(side, rng.randf_range(-tilt, tilt)) * Basis(tangent, rng.randf_range(-tilt, tilt) * 0.6)
			basis = basis * Basis(Vector3.UP, rng.randf_range(0.0, TAU))
			xforms.append(Transform3D(basis, p))
			var c := color
			if mixed:
				c = PALETTE[count % PALETTE.size()]
			elif count % 4 == 2:
				c = color.lerp(Color(1.0, 0.95, 0.8), 0.25)  # same hue, a touch paler: reads as real mixed glass
			cols.append(c)
			data.append(Color(next / pulse_wavelength, rng.randf(), 0.0, 0.0))
			count += 1
			next += bulb_spacing
		acc += seg

	if _bulb_mesh == null:
		_bulb_mesh = _make_bulb_mesh(bulb_width, bulb_length)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _bulb_mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, cols[i])
		mm.set_instance_custom_data(i, data[i])
	multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = BULB_SHADER
	m.set_shader_parameter("chase", 1.0 if chase else 0.0)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("max_distance_scale", max_distance_scale)
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_energy = energy
	add_to_group("night_lit")  # night_clock.gd: bulbs come on at dusk

	# Wire: short tubes between successive wire points.
	var tube := CylinderMesh.new()
	tube.top_radius = wire_radius
	tube.bottom_radius = wire_radius
	tube.height = 1.0
	tube.radial_segments = 4
	tube.rings = 1
	var wm := MultiMesh.new()
	wm.transform_format = MultiMesh.TRANSFORM_3D
	wm.mesh = tube
	wm.instance_count = wire.size() - 1
	for i in range(wire.size() - 1):
		var a := wire[i]
		var b := wire[i + 1]
		var d := b - a
		var l := maxf(d.length(), 0.001)
		var y := d / l
		var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		wm.set_instance_transform(i, Transform3D(Basis(x, y * l, z), (a + b) * 0.5))
	var wmi := MultiMeshInstance3D.new()
	wmi.multimesh = wm
	wmi.material_override = GB.mat(Color(0.04, 0.07, 0.05), 0.0, 0.1)
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wmi)

	# Faint colour spill on the roof/walls around the string.
	if spill and spill_every > 0.0:
		var total := 0.0
		for i in range(points.size() - 1):
			total += points[i].distance_to(points[i + 1])
		var n := maxi(1, int(total / spill_every))
		for k in n:
			var target := (float(k) + 0.5) / float(n) * total
			var run := 0.0
			for i in range(points.size() - 1):
				var seg := points[i].distance_to(points[i + 1])
				if run + seg >= target:
					var l := OmniLight3D.new()
					l.position = points[i].lerp(points[i + 1], (target - run) / maxf(seg, 0.001)) + Vector3.UP * 0.25
					l.light_color = color
					l.light_energy = spill_energy
					l.omni_range = spill_range
					l.omni_attenuation = 1.4
					l.shadow_enabled = false
					add_child(l)
					break
				run += seg


var _energy := 1.8


## night_clock.gd: 0 = switched off (daylight) .. 1 = full night glow.
func set_night_level(f: float) -> void:
	var m := material_override as ShaderMaterial
	if m:
		m.set_shader_parameter("energy", _energy * clampf(f, 0.0, 1.0) + 0.02)
