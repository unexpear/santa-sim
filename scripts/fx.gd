extends RefCounted
## Painterly particle effects (GPUParticles3D + soft billboard sprites generated at runtime so they
## match the toon look: soft blobby edges, flat saturated colours, no photographic texture).
## Every builder returns a configured GPUParticles3D; callers add it to the tree and either leave it
## emitting or call burst(p).

static var _tex: Dictionary = {}


## Soft painterly sprite. kind: "blob" (smoke/mist), "dot" (sparks, motes), "star" (glitter),
## "flake" (ice crystal), "drop" (water), "z" (sleep).
static func sprite(kind: String) -> Texture2D:
	if _tex.has(kind):
		return _tex[kind]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = kind.hash()
	noise.frequency = 0.09
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var a := 0.0
			match kind:
				"blob":
					var edge := 0.78 + noise.get_noise_2d(x, y) * 0.35
					a = clampf((edge - r) / 0.25, 0.0, 1.0)
					a = a * a * (3.0 - 2.0 * a) * (0.75 + 0.25 * noise.get_noise_2d(x * 2.0, y * 2.0))
				"dot":
					a = clampf(1.0 - r, 0.0, 1.0)
					a = pow(a, 1.6)
				"star":
					var ang := atan2(v, u)
					var rays := pow(absf(cos(ang * 2.0)), 18.0) * 0.9
					a = clampf((1.0 - r * 2.2) + rays * clampf(1.0 - r, 0.0, 1.0), 0.0, 1.0)
				"flake":
					var ang2 := atan2(v, u)
					var arms := pow(absf(cos(ang2 * 3.0)), 30.0)
					a = clampf(arms * (1.0 - r) * 1.6 + clampf(0.25 - r, 0.0, 1.0) * 3.0, 0.0, 1.0)
				"drop":
					var vv := v + 0.25
					var rr := sqrt(u * u * 2.2 + vv * vv * (1.0 if vv > 0.0 else 0.35))
					a = clampf((0.75 - rr) / 0.2, 0.0, 1.0)
				"z":
					# a chunky letter Z
					var zx := u * 1.25
					var zy := v * 1.25
					var top := absf(zy + 0.6) < 0.18 and absf(zx) < 0.65
					var bot := absf(zy - 0.6) < 0.18 and absf(zx) < 0.65
					var diag := absf(zx + zy * 0.92) < 0.2 and absf(zy) < 0.65
					a = 1.0 if (top or bot or diag) else 0.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[kind] = t
	return t


static func _draw_mat(kind: String, additive: bool, lit := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = sprite(kind)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX if lit else BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.proximity_fade_enabled = not additive
	m.proximity_fade_distance = 0.4
	m.disable_receive_shadows = true
	return m


static func _ramp(cols: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cs := PackedColorArray()
	for i in cols.size():
		offs.append(float(i) / maxf(cols.size() - 1, 1))
		cs.append(cols[i])
	g.offsets = offs
	g.colors = cs
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p in points:
		c.add_point(p)
	var ct := CurveTexture.new()
	ct.curve = c
	return ct


## Generic builder.
static func make(kind: String, amount: int, lifetime: float, size: float, colors: Array, opts := {}) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = bool(opts.get("one_shot", false))
	p.explosiveness = float(opts.get("explosive", 0.0))
	p.randomness = 0.5
	p.fixed_fps = 30
	p.local_coords = bool(opts.get("local", false))
	p.visibility_aabb = AABB(Vector3(-30, -10, -30), Vector3(60, 40, 60))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = opts.get("dir", Vector3.UP)
	pm.spread = float(opts.get("spread", 25.0))
	pm.initial_velocity_min = float(opts.get("vmin", 0.2))
	pm.initial_velocity_max = float(opts.get("vmax", 0.6))
	pm.gravity = opts.get("gravity", Vector3.ZERO)
	pm.damping_min = float(opts.get("damp", 0.0))
	pm.damping_max = float(opts.get("damp", 0.0))
	pm.scale_min = size * 0.6
	pm.scale_max = size * 1.2
	pm.scale_curve = _curve(opts.get("scale_curve", [Vector2(0, 0.4), Vector2(0.3, 1.0), Vector2(1, 1.3)]))
	pm.color_ramp = _ramp(colors)
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -float(opts.get("spin", 20.0))
	pm.angular_velocity_max = float(opts.get("spin", 20.0))
	pm.turbulence_enabled = opts.has("turb")
	if pm.turbulence_enabled:
		pm.turbulence_noise_strength = float(opts.get("turb", 0.5))
		pm.turbulence_noise_scale = 3.0
		pm.turbulence_influence_min = 0.05
		pm.turbulence_influence_max = 0.15
	var box: Vector3 = opts.get("box", Vector3.ZERO)
	if box != Vector3.ZERO:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = box
	elif opts.has("sphere"):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = float(opts.get("sphere", 0.1))
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = _draw_mat(kind, bool(opts.get("add", false)), bool(opts.get("lit", false)))
	p.draw_pass_1 = q
	p.emitting = not p.one_shot
	return p


static func burst(p: GPUParticles3D) -> void:
	p.restart()
	p.emitting = true


# ---- presets --------------------------------------------------------------------------------------

static func smoke(color := Color(0.75, 0.72, 0.8), amount := 18, size := 0.8) -> GPUParticles3D:
	return make("blob", amount, 4.0, size, [Color(color, 0.0), Color(color, 0.45), Color(color.lightened(0.2), 0.25), Color(color, 0.0)],
			{"dir": Vector3.UP, "spread": 12.0, "vmin": 0.4, "vmax": 0.8, "gravity": Vector3(0.25, 0.05, 0.1), "turb": 0.6,
			"scale_curve": [Vector2(0, 0.3), Vector2(0.5, 1.0), Vector2(1, 1.8)], "spin": 15.0, "lit": true})


static func soot_burst() -> GPUParticles3D:
	var c := Color(0.12, 0.1, 0.1)
	return make("blob", 26, 1.4, 0.55, [Color(c, 0.0), Color(c, 0.8), Color(c, 0.5), Color(c, 0.0)],
			{"one_shot": true, "explosive": 0.9, "spread": 60.0, "vmin": 0.6, "vmax": 1.8, "gravity": Vector3(0, -0.6, 0), "damp": 1.5,
			"scale_curve": [Vector2(0, 0.4), Vector2(0.4, 1.0), Vector2(1, 1.6)]})


## The green glowing night-vision mist the elves creep out of (as in the reference art).
static func green_mist(amount := 24) -> GPUParticles3D:
	var g := Color(0.35, 1.0, 0.45)
	return make("blob", amount, 2.6, 0.55, [Color(g, 0.0), Color(g, 0.55), Color(g.darkened(0.3), 0.3), Color(g, 0.0)],
			{"one_shot": true, "explosive": 0.75, "dir": Vector3(0, 0.2, 1), "spread": 70.0, "vmin": 0.3, "vmax": 1.1, "damp": 0.8,
			"gravity": Vector3(0, 0.05, 0), "box": Vector3(0.4, 0.15, 0.25), "add": true, "turb": 0.4,
			"scale_curve": [Vector2(0, 0.5), Vector2(0.5, 1.2), Vector2(1, 1.8)]})


static func sparkle_trail(color := Color(1.0, 0.85, 0.4)) -> GPUParticles3D:
	return make("star", 40, 0.9, 0.12, [Color(color, 0.0), Color(color, 1.0), Color(color.lightened(0.4), 0.6), Color(color, 0.0)],
			{"spread": 180.0, "vmin": 0.05, "vmax": 0.3, "gravity": Vector3(0, -0.4, 0), "add": true, "box": Vector3(0.1, 0.02, 0.6),
			"scale_curve": [Vector2(0, 1.0), Vector2(1, 0.1)], "spin": 90.0})


static func glitter(colors := [Color(1, 0.85, 0.3), Color(0.4, 1, 0.5), Color(1, 0.4, 0.8)]) -> GPUParticles3D:
	return make("star", 40, 1.3, 0.09, [Color(colors[0], 0.0), colors[0], colors[1], colors[2], Color(colors[2], 0.0)],
			{"one_shot": true, "explosive": 0.85, "spread": 70.0, "vmin": 0.6, "vmax": 1.6, "gravity": Vector3(0, -1.5, 0), "add": true,
			"scale_curve": [Vector2(0, 1.0), Vector2(1, 0.2)], "spin": 180.0})


static func zzz_puff() -> GPUParticles3D:
	var c := Color(0.7, 0.8, 1.0)
	return make("z", 8, 1.8, 0.16, [Color(c, 0.0), Color(c, 1.0), Color(c, 0.8), Color(c, 0.0)],
			{"one_shot": true, "explosive": 0.4, "spread": 30.0, "vmin": 0.3, "vmax": 0.6, "gravity": Vector3(0.1, 0.2, 0), "spin": 0.0,
			"scale_curve": [Vector2(0, 0.5), Vector2(1, 1.4)]})


static func dust_motes(box: Vector3, amount := 40) -> GPUParticles3D:
	var c := Color(1.0, 0.95, 0.8)
	return make("dot", amount, 8.0, 0.025, [Color(c, 0.0), Color(c, 0.6), Color(c, 0.6), Color(c, 0.0)],
			{"box": box, "spread": 180.0, "vmin": 0.0, "vmax": 0.03, "turb": 0.3, "add": true, "scale_curve": [Vector2(0, 1), Vector2(1, 1)]})


static func frost_blast() -> GPUParticles3D:
	var c := Color(0.75, 0.95, 1.0)
	return make("flake", 70, 1.0, 0.12, [Color(c, 0.0), Color(1, 1, 1, 1), Color(c, 0.7), Color(c, 0.0)],
			{"dir": Vector3(0, -1, 0), "spread": 14.0, "vmin": 3.5, "vmax": 5.5, "damp": 1.0, "add": true, "spin": 120.0,
			"scale_curve": [Vector2(0, 0.6), Vector2(1, 1.2)]})


static func steam(amount := 24) -> GPUParticles3D:
	var c := Color(0.92, 0.95, 1.0)
	return make("blob", amount, 2.2, 0.5, [Color(c, 0.0), Color(c, 0.55), Color(c, 0.2), Color(c, 0.0)],
			{"dir": Vector3.UP, "spread": 35.0, "vmin": 0.5, "vmax": 1.2, "damp": 0.5, "turb": 0.5,
			"scale_curve": [Vector2(0, 0.3), Vector2(1, 1.8)]})


static func embers(box := Vector3(0.3, 0.05, 0.2), amount := 18) -> GPUParticles3D:
	return make("dot", amount, 1.6, 0.04, [Color(1, 0.8, 0.3, 0.0), Color(1, 0.6, 0.15, 1), Color(1, 0.3, 0.05, 0.8), Color(1, 0.2, 0, 0)],
			{"box": box, "dir": Vector3.UP, "spread": 25.0, "vmin": 0.4, "vmax": 1.0, "turb": 0.8, "add": true,
			"scale_curve": [Vector2(0, 1), Vector2(1, 0.3)]})


static func flames(box := Vector3(0.28, 0.02, 0.12)) -> GPUParticles3D:
	return make("blob", 36, 0.8, 0.32, [Color(1, 0.9, 0.4, 0.0), Color(1, 0.8, 0.3, 0.9), Color(1, 0.45, 0.1, 0.8), Color(0.9, 0.2, 0.05, 0.0)],
			{"box": box, "dir": Vector3.UP, "spread": 8.0, "vmin": 0.5, "vmax": 0.9, "add": true, "turb": 0.4,
			"scale_curve": [Vector2(0, 0.7), Vector2(0.4, 1.0), Vector2(1, 0.15)], "spin": 30.0})


static func flame_burst() -> GPUParticles3D:
	return make("blob", 40, 0.9, 0.45, [Color(1, 0.95, 0.5, 0.0), Color(1, 0.8, 0.3, 1), Color(1, 0.35, 0.05, 0.7), Color(0.4, 0.1, 0.05, 0)],
			{"one_shot": true, "explosive": 0.9, "spread": 50.0, "vmin": 0.8, "vmax": 2.0, "damp": 2.0, "add": true, "box": Vector3(0.3, 0.05, 0.15),
			"scale_curve": [Vector2(0, 0.5), Vector2(0.3, 1.2), Vector2(1, 0.4)]})


static func water_spray() -> GPUParticles3D:
	var c := Color(0.55, 0.8, 1.0)
	return make("drop", 80, 0.9, 0.07, [Color(c, 0.0), Color(c, 0.9), Color(c.lightened(0.3), 0.7), Color(c, 0.0)],
			{"dir": Vector3(0, 0.3, 1), "spread": 25.0, "vmin": 2.0, "vmax": 3.5, "gravity": Vector3(0, -9.8, 0), "spin": 0.0,
			"scale_curve": [Vector2(0, 1), Vector2(1, 0.6)]})


static func motes(box: Vector3, color: Color, amount := 30, size := 0.05) -> GPUParticles3D:
	return make("dot", amount, 6.0, size, [Color(color, 0.0), Color(color, 0.9), Color(color, 0.9), Color(color, 0.0)],
			{"box": box, "spread": 180.0, "vmin": 0.05, "vmax": 0.2, "turb": 1.0, "add": true, "gravity": Vector3(0.05, 0.02, 0),
			"scale_curve": [Vector2(0, 1), Vector2(1, 1)]})


static func ground_mist(box: Vector3, amount := 24) -> GPUParticles3D:
	var c := Color(0.62, 0.55, 0.8)
	return make("blob", amount, 14.0, 6.0, [Color(c, 0.0), Color(c, 0.16), Color(c, 0.16), Color(c, 0.0)],
			{"box": box, "dir": Vector3(1, 0, 0.2), "spread": 20.0, "vmin": 0.15, "vmax": 0.4, "spin": 3.0, "lit": true,
			"scale_curve": [Vector2(0, 0.7), Vector2(1, 1.2)]})


static func dust_kick() -> GPUParticles3D:
	var c := Color(0.62, 0.55, 0.62)
	return make("blob", 22, 1.6, 0.6, [Color(c, 0.0), Color(c, 0.6), Color(c, 0.3), Color(c, 0.0)],
			{"one_shot": true, "explosive": 0.9, "dir": Vector3.UP, "spread": 80.0, "vmin": 0.8, "vmax": 2.0, "damp": 2.5, "box": Vector3(0.8, 0.05, 1.4),
			"gravity": Vector3(0, -0.3, 0), "scale_curve": [Vector2(0, 0.4), Vector2(1, 1.8)], "lit": true})
