extends Node3D
## Fog + outdoor particles (visual only, no collision): low drifting ground mist (volumetric fog
## volumes + painterly sprite mist), distance height fog, haze around street/string lights, chimney
## smoke from the background houses, summer embers + pollen motes, moths at the streetlights, and
## sparkle trails off the sleigh runners and reindeer hooves while flying.

const FX := preload("res://scripts/fx.gd")

@export_group("Fog")
@export var ground_mist := true
@export var ground_mist_density := 0.06  ## Volumetric density of the low mist volumes.
@export var ground_mist_height := 1.4  ## Mist stays below this (m) so landing roofs read clearly.
@export var ground_mist_sprites := 10  ## Painterly sprite banks drifting along the street + yards.
@export var height_fog := true
@export var height_fog_density := 0.0022  ## Distance fog (depth); keep low so roofs stay readable.
@export var height_fog_falloff := 0.12
@export var light_haze := 2.2  ## Volumetric fog energy multiplier on outdoor lamps (halos).
@export var chimney_wisps := true
@export_group("Outdoor particles")
@export var bg_chimney_smoke := 10  ## Smoke particles per background chimney (0 = off).
@export var ember_amount := 40
@export var pollen_amount := 70
@export var moths_per_light := 6
@export var sleigh_trails := true
@export var trail_min_speed := 2.0

var env: Environment
var suburb: Node
var sleigh: RigidBody3D
var team: Node3D
var houses: Array = []
var _trails: Array = []


func setup(e: Environment, sub: Node, s: RigidBody3D, t: Node3D, hs: Array) -> void:
	env = e
	suburb = sub
	sleigh = s
	team = t
	houses = hs
	_fog()
	_outdoor()
	_trails_setup()


func _fog() -> void:
	if height_fog and env:
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_light_color = Color(0.42, 0.36, 0.6)
		env.fog_light_energy = 0.8
		env.fog_density = height_fog_density
		env.fog_height = 2.0
		env.fog_height_density = height_fog_falloff
		env.fog_sky_affect = 0.25
		env.fog_aerial_perspective = 0.35
	if ground_mist and env and env.volumetric_fog_enabled:
		var fm := FogMaterial.new()
		fm.density = ground_mist_density
		fm.albedo = Color(0.7, 0.62, 0.85)
		fm.height_falloff = 1.6
		fm.edge_fade = 0.6
		# along the street band only (road, verges, front fences), clear of the landing houses
		for z: float in [-10.0, -60.0, -110.0, -160.0]:
			var v := FogVolume.new()
			v.size = Vector3(14, ground_mist_height * 2.0, 50)
			v.material = fm
			add_child(v)
			v.position = Vector3(2, 0.0, z)
	if ground_mist:
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		for i in ground_mist_sprites:
			var m := FX.ground_mist(Vector3(9, 0.25, 9), 14)
			add_child(m)
			m.position = Vector3(rng.randf_range(-22, 26), 0.55, rng.randf_range(-170, 20))
			m.preprocess = 10.0
	# lamp halos
	for l in get_tree().root.find_children("*", "Light3D", true, false):
		if l is DirectionalLight3D:
			continue
		var light := l as Light3D
		if light.light_cull_mask == 2:
			continue  # interior-only lights
		light.light_volumetric_fog_energy = light_haze
	if chimney_wisps:
		for h in houses:
			var w := FX.smoke(Color(0.75, 0.72, 0.85, 1.0), 6, 1.4)
			w.lifetime = 5.0
			w.preprocess = 5.0
			add_child(w)
			w.global_position = (h.call("get_chimney_top_world") as Vector3) + Vector3(0, 0.6, 0)
			var pm := w.process_material as ParticleProcessMaterial
			pm.initial_velocity_min = 0.1
			pm.initial_velocity_max = 0.25
			pm.color_ramp = FX._ramp([Color(0.8, 0.75, 0.9, 0.0), Color(0.8, 0.75, 0.9, 0.12), Color(0.8, 0.75, 0.9, 0.0)])


func _outdoor() -> void:
	if suburb == null:
		return
	if bg_chimney_smoke > 0:
		for top: Vector3 in suburb.get("bg_chimney_tops"):
			var s := FX.smoke(Color(0.62, 0.58, 0.7), bg_chimney_smoke, 1.0)
			s.preprocess = 4.0
			add_child(s)
			s.global_position = top + Vector3(0, 0.2, 0)
	if ember_amount > 0 and pollen_amount > 0:
		var e := FX.motes(Vector3(16, 3, 60), Color(1.0, 0.55, 0.2), ember_amount, 0.045)
		add_child(e)
		e.position = Vector3(2, 4.0, -60)
		e.preprocess = 6.0
		var e2 := e.duplicate() as GPUParticles3D
		add_child(e2)
		e2.position = Vector3(2, 4.0, -140)
		var p := FX.motes(Vector3(18, 2.0, 60), Color(1.0, 0.95, 0.6), pollen_amount, 0.03)
		add_child(p)
		p.position = Vector3(2, 2.0, -50)
		p.preprocess = 6.0
		var p2 := p.duplicate() as GPUParticles3D
		add_child(p2)
		p2.position = Vector3(2, 2.0, -130)
	if moths_per_light > 0:
		for head: Vector3 in suburb.get("streetlight_heads"):
			var m := FX.make("dot", moths_per_light, 3.0, 0.06, [Color(0.9, 0.85, 0.7, 0.0), Color(1.0, 0.95, 0.8, 1.0), Color(1.0, 0.95, 0.8, 1.0), Color(0.9, 0.85, 0.7, 0.0)],
					{"sphere": 0.55, "spread": 180.0, "vmin": 0.6, "vmax": 1.4, "turb": 2.5, "damp": 0.5, "scale_curve": [Vector2(0, 1), Vector2(1, 1)]})
			m.preprocess = 3.0
			add_child(m)
			m.global_position = head + Vector3(0, -0.35, 0)


func _trails_setup() -> void:
	if not sleigh_trails or sleigh == null:
		return
	for x: float in [-0.7, 0.7]:
		var t := FX.sparkle_trail(Color(1.0, 0.85, 0.4))
		sleigh.add_child(t)
		t.position = Vector3(x, -0.6, 1.2)
		t.emitting = false
		_trails.append(t)
	if team:
		var deer: Array = team.get("_deer")
		for d in deer:
			var sq: Node3D = d.squash
			for zz: float in [-0.35, 0.35]:
				var t := FX.sparkle_trail(Color(0.75, 0.9, 1.0))
				t.amount = 10
				sq.add_child(t)
				t.position = Vector3(0, -0.6, zz)
				t.emitting = false
				_trails.append(t)


func _process(_delta: float) -> void:
	_update_indoor_fog()
	if _trails.is_empty():
		return
	var flying := not bool(sleigh.get("grounded")) and sleigh.linear_velocity.length() > trail_min_speed and sleigh.global_position.y > 1.0 and not sleigh.freeze
	for t in _trails:
		(t as GPUParticles3D).emitting = flying


var _fog_was_on := false
var _indoor := false


## Volumetric fog inside a closed room has no light to scatter (interior lights skip the fog),
## so it turns into dark blobs at depth edges. Switch it off while the camera is indoors.
func _update_indoor_fog() -> void:
	if env == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var inside := false
	for h in houses:
		var hn := h as Node3D
		if hn == null or hn.get("interior") == null:
			continue
		var p := hn.to_local(cam.global_position)
		if absf(p.x) < float(hn.get("width")) * 0.5 and absf(p.z) < float(hn.get("depth")) * 0.5 and p.y > -0.5 and p.y < 5.6:
			inside = true
			break
	if inside == _indoor:
		return
	_indoor = inside
	if inside:
		_fog_was_on = env.volumetric_fog_enabled
		env.volumetric_fog_enabled = false
	else:
		env.volumetric_fog_enabled = _fog_was_on
