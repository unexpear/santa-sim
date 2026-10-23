extends Node3D
## Santa Sim: the streamed world (all of Australia from OpenStreetMap, built as our own stylised houses).
## One seamless, chunk-streamed map: no loading screens, no zones. See WORLD-STREAMING.md.
## Paddington (Brisbane) is just one area inside it, at the same real coordinates as scenes/town/town.tscn,
## which still works exactly as before.
## Map data (c) OpenStreetMap contributors, ODbL 1.0.

const Geo := preload("res://scripts/world/geo.gd")
const Streamer := preload("res://scripts/world/world_streamer.gd")
const Style := preload("res://scripts/world/world_style.gd")
const Builder := preload("res://scripts/world/world_builder.gd")
const HouseGen := preload("res://scripts/town/house_gen.gd")
const SleighScene := preload("res://scenes/sleigh.tscn")
const TeamScript := preload("res://scripts/reindeer_team.gd")
const CamScript := preload("res://scripts/chase_camera.gd")
const HudScript := preload("res://scripts/hud.gd")
const GB := preload("res://scripts/greybox.gd")

## Paddington QLD: the centre of data/towns/paddington_qld.json.
@export var start_lat := -27.4598
@export var start_lon := 152.9985
@export var rebase_distance := 1500.0
@export var tower_height := 24.0
@export var town_seed := 2026

const WARPS := [
	["Paddington, Brisbane QLD", -27.4598, 152.9985],
	["Sydney CBD, NSW", -33.8688, 151.2093],
	["Mudgee, NSW", -32.5940, 149.5870],
	["Bondi, Sydney NSW", -33.8915, 151.2767],
	["Brisbane CBD, QLD", -27.4698, 153.0251],
]

var streamer: Streamer
var sleigh: RigidBody3D
var team: Node3D
var camera: Camera3D
var hud: CanvasLayer
var tower: StaticBody3D
var ocean: MeshInstance3D
var probe: Node3D  ## headless checks: stands in for the sleigh
var spawn_lat := 0.0
var spawn_lon := 0.0
var place_name := ""
var _fps_t := 0.0
var _fps_frames := 0
var _fps := 0.0
var _check_mode := ""


func _enter_tree() -> void:
	_setup_input()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--worldcheck" or a == "--worldfps" or a.begins_with("--worldshots"):
			_check_mode = a
		elif a.begins_with("--start="):
			var i := int(a.get_slice("=", 1))
			start_lat = WARPS[i][1]
			start_lon = WARPS[i][2]
	streamer = Streamer.new()
	streamer.name = "Streamer"
	add_child(streamer)
	if not streamer.setup(start_lat, start_lon):
		if _check_mode != "":
			print("[worldcheck] FAIL no world data")
			get_tree().quit(2)
		return
	streamer.builder.town_seed = town_seed
	spawn_lat = start_lat
	spawn_lon = start_lon
	place_name = WARPS[0][0] if is_equal_approx(start_lat, WARPS[0][1]) else ""
	_environment()
	_ground()
	if _check_mode == "--worldcheck":
		probe = Node3D.new()
		probe.name = "Probe"
		add_child(probe)
		streamer.focus = probe
		_worldcheck.call_deferred()
		return
	_tower()
	_spawn_player()
	_ui()
	streamer.focus = sleigh
	var idx: Dictionary = streamer.data.index
	print("[world] %d blocks, %d tiles, %d buildings (%s). Start %s" % [idx.totals.blocks, idx.totals.tiles, idx.totals.buildings,
			", ".join(idx.get("regions", [])), place_name])
	if _check_mode == "--worldfps":
		_fps_run.call_deferred()
	elif _check_mode.begins_with("--worldshots"):
		_shots.call_deferred(_check_mode.get_slice("=", 1))


# --------------------------------------------------------------------------------------------- scene

func _environment() -> void:
	var moon_dir := Vector3(0.3, 0.45, -0.85).normalized()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/night_sky.gdshader")
	sky_mat.set_shader_parameter("moon_dir", moon_dir)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.44, 0.78)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.15
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 0.95
	env.glow_hdr_scale = 1.5
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.5
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.003
	env.volumetric_fog_albedo = Color(0.62, 0.5, 0.78)
	env.volumetric_fog_emission = Color(0.05, 0.03, 0.07)
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_length = 220.0
	env.volumetric_fog_ambient_inject = 0.25
	env.volumetric_fog_sky_affect = 0.1
	# Long haze instead of the town's 3.2 km wall: far LOD fades into it, so nothing visibly pops in.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.3, 0.23, 0.45)
	env.fog_depth_begin = 700.0
	env.fog_depth_end = 11000.0
	env.fog_depth_curve = 1.35
	env.fog_sky_affect = 0.35
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.72, 0.78, 1.0)
	moon.light_energy = 1.0
	moon.shadow_enabled = true
	moon.shadow_blur = 1.6
	moon.directional_shadow_max_distance = 160.0
	moon.shadow_opacity = 0.85
	add_child(moon)
	moon.look_at_from_position(Vector3.ZERO, Vector3(0.55, -0.62, -0.55), Vector3.UP)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(1.0, 0.62, 0.35)
	fill.light_energy = 0.3
	add_child(fill)
	fill.look_at_from_position(Vector3.ZERO, Vector3(-0.7, -0.3, -0.35), Vector3.UP)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(1.0, 0.55, 0.38)
	rim.light_energy = 0.5
	add_child(rim)
	rim.look_at_from_position(Vector3.ZERO, Vector3(-0.15, -0.22, 1.0), Vector3.UP)


func _ground() -> void:
	# Infinite flat ground (terrain heights come later) + an ocean sheet under the blocks for open sea.
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.set_meta("surface_name", "Ground")
	body.set_meta("what", "the ground")
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	body.add_child(cs)
	add_child(body)
	ocean = MeshInstance3D.new()
	ocean.name = "Ocean"
	var pm := PlaneMesh.new()
	pm.size = Vector2(400000, 400000)
	ocean.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.03, 0.08, 0.19)
	m.roughness = 0.15
	m.metallic_specular = 0.8
	ocean.material_override = m
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ocean.position.y = -0.8
	add_child(ocean)


func _tower() -> void:
	tower = StaticBody3D.new()
	tower.name = "LaunchTower"
	tower.set_meta("surface_name", "Launch tower")
	tower.set_meta("what", "the launch tower")
	var top := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(7.0, 0.6, 9.0)
	top.shape = bs
	top.position = Vector3(0, tower_height - 0.3, 0)
	tower.add_child(top)
	var leg := CollisionShape3D.new()
	var ls := BoxShape3D.new()
	ls.size = Vector3(1.2, tower_height, 1.2)
	leg.shape = ls
	leg.position = Vector3(0, tower_height * 0.5, 0)
	tower.add_child(leg)
	GB.box(tower, Vector3(7.0, 0.6, 9.0), Vector3(0, tower_height - 0.3, 0), Color(0.55, 0.2, 0.15))
	GB.box(tower, Vector3(1.2, tower_height, 1.2), Vector3(0, tower_height * 0.5, 0), Color(0.3, 0.3, 0.34))
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.7, 0.35)
	lamp.light_energy = 2.0
	lamp.omni_range = 14.0
	lamp.position = Vector3(0, tower_height + 3.0, 0)
	tower.add_child(lamp)
	add_child(tower)


func _spawn_player() -> void:
	sleigh = SleighScene.instantiate() as RigidBody3D
	sleigh.position = Vector3(0, tower_height + 0.75, 0)
	add_child(sleigh)
	team = Node3D.new()
	team.name = "ReindeerTeam"
	team.set_script(TeamScript)
	team.set("sleigh", sleigh)
	add_child(team)
	camera = Camera3D.new()
	camera.name = "ChaseCamera"
	camera.far = 24000.0
	camera.set_script(CamScript)
	camera.set("target", sleigh)
	add_child(camera)
	hud = CanvasLayer.new()
	hud.set_script(HudScript)
	add_child(hud)
	camera.call("snap")


func _ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var l := Label.new()
	l.text = "Map data %s (ODbL)" % String(streamer.data.index.get("attribution", "\u00a9 OpenStreetMap contributors"))
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.modulate = Color(1, 1, 1, 0.85)
	l.anchor_left = 1.0
	l.anchor_right = 1.0
	l.anchor_top = 1.0
	l.anchor_bottom = 1.0
	l.offset_left = -560.0
	l.offset_right = -14.0
	l.offset_top = -62.0
	l.offset_bottom = -40.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.name = "OSMAttribution"
	layer.add_child(l)
	hud.call("flash", "Australia, Christmas Eve. Fly anywhere: 1-5 jump between cities.", Color(1, 0.95, 0.8), 6.0)


# --------------------------------------------------------------------------------------------- input

func _setup_input() -> void:
	_bind("thrust_fwd", [KEY_W], [[JOY_AXIS_LEFT_Y, -1.0]])
	_bind("thrust_back", [KEY_S], [[JOY_AXIS_LEFT_Y, 1.0]])
	_bind("yaw_left", [KEY_A], [[JOY_AXIS_LEFT_X, -1.0]])
	_bind("yaw_right", [KEY_D], [[JOY_AXIS_LEFT_X, 1.0]])
	_bind("pitch_down", [KEY_UP], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_bind("pitch_up", [KEY_DOWN], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_bind("lift", [KEY_SPACE], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_bind("brake", [KEY_SHIFT], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_bind("drop_present", [KEY_E], [], [JOY_BUTTON_A])
	_bind("restart", [KEY_R], [], [JOY_BUTTON_START])
	_bind("camera", [KEY_V], [], [JOY_BUTTON_Y])
	for i in WARPS.size():
		_bind("world_warp_%d" % i, [KEY_1 + i], [])


func _bind(action: StringName, keys: Array, axes: Array, buttons: Array = []) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for ax in axes:
		var j := InputEventJoypadMotion.new()
		j.axis = ax[0]
		j.axis_value = ax[1]
		InputMap.action_add_event(action, j)
	for btn in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = btn
		InputMap.action_add_event(action, jb)


# --------------------------------------------------------------------------------------------- frame

func _physics_process(_delta: float) -> void:
	var f: Node3D = sleigh if sleigh != null else probe
	if f == null or streamer == null or not streamer.ready_ok:
		return
	var p := f.global_position
	if absf(p.x) > rebase_distance or absf(p.z) > rebase_distance:
		_rebase(Vector3(p.x, 0.0, p.z))
	if ocean != null:
		ocean.position = Vector3(snappedf(p.x, 1000.0), -0.8, snappedf(p.z, 1000.0))


## Floating origin: move the world origin under the player. Everything dynamic shifts by the same offset.
func _rebase(d: Vector3) -> void:
	var off := streamer.rebase(d)
	if tower != null:
		tower.position = streamer.geo.to_world(spawn_lat, spawn_lon)
		tower.reset_physics_interpolation()
	if sleigh != null:
		sleigh.global_position -= off
		var sx: Transform3D = sleigh.get("_start_xform")
		sx.origin = tower.position + Vector3(0, tower_height + 0.75, 0)
		sleigh.set("_start_xform", sx)
		sleigh.reset_physics_interpolation()
		team.global_position -= off
		team.reset_physics_interpolation()
		camera.global_position -= off
		camera.set("_look", (camera.get("_look") as Vector3) - off)
		camera.reset_physics_interpolation()
	if probe != null:
		probe.global_position -= off


func warp(i: int) -> void:
	var w: Array = WARPS[i]
	spawn_lat = w[1]
	spawn_lon = w[2]
	place_name = w[0]
	streamer.reset_origin(spawn_lat, spawn_lon)
	if tower != null:
		tower.position = Vector3.ZERO
		tower.reset_physics_interpolation()
	if sleigh != null:
		var sx := Transform3D(Basis(), Vector3(0, tower_height + 0.75, 0))
		sleigh.set("_start_xform", sx)
		sleigh.call("request_reset")
		camera.call("snap")
		hud.call("flash", w[0], Color(1, 0.95, 0.8), 3.0)
	if probe != null:
		probe.global_position = Vector3.ZERO


func _process(delta: float) -> void:
	_fps_t += delta
	_fps_frames += 1
	if _fps_t >= 0.5:
		_fps = _fps_frames / _fps_t
		_fps_t = 0.0
		_fps_frames = 0
	if sleigh == null:
		return
	for i in WARPS.size():
		if Input.is_action_just_pressed("world_warp_%d" % i):
			warp(i)
	if Input.is_action_just_pressed("restart"):
		sleigh.call("request_reset")
	if Input.is_action_just_pressed("camera"):
		camera.call("toggle_mode")
	var v := sleigh.linear_velocity
	var ll := streamer.geo.to_latlon(sleigh.global_position)
	var c := streamer.counts()
	var lines := PackedStringArray()
	lines.append("SPEED      %5.1f m/s   VERT %+5.1f" % [v.length(), v.y])
	lines.append("ALTITUDE   %5.1f m" % sleigh.global_position.y)
	lines.append("STATUS     %s" % sleigh.call("status_text"))
	lines.append("WHERE      %.5f, %.5f  (%s)" % [ll[0], ll[1], Style.region_of(ll[0], ll[1]).to_upper()])
	lines.append("WORLD      %d tiles  near %d  mid %d  far %d   %.0f fps" % [c.tiles, c.near, c.mid, c.far, _fps])
	hud.call("set_stats", "\n".join(lines))


# --------------------------------------------------------------------------------------------- checks

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _settle(max_s: float) -> float:
	var t0 := Time.get_ticks_msec()
	await get_tree().process_frame
	await get_tree().process_frame
	while streamer.busy() and Time.get_ticks_msec() - t0 < max_s * 1000.0:
		await get_tree().process_frame
	return (Time.get_ticks_msec() - t0) / 1000.0


func _ray_down(p: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 200.0, p + Vector3.DOWN * 5.0)
	return get_world_3d().direct_space_state.intersect_ray(q)


## Headless: data integrity, Paddington = town scene, streaming hitches, floating origin, collision.
func _worldcheck() -> void:
	var ok := true
	var idx: Dictionary = streamer.data.index
	print("[worldcheck] data: %d blocks, %d tiles, %d buildings, %.1f MB, regions %s" % [idx.totals.blocks, idx.totals.tiles,
			idx.totals.buildings, float(idx.totals.bytes) / 1.0e6, ", ".join(idx.get("regions", []))])
	# 1. Paddington: every town-scene building at the same spot, same size, same style
	var town = JSON.parse_string(FileAccess.get_file_as_string("res://data/towns/paddington_qld.json"))
	var cen: Array = town.projection.center_latlon
	var tlat: float = cen[0]
	var tlon: float = cen[1]
	streamer.reset_origin(tlat, tlon)
	var kx := Geo.DEG * cos(deg_to_rad(tlat))
	var matched := 0
	var total := 0
	var max_err := 0.0
	var sum_err := 0.0
	var same_style := 0
	var max_size := 0.0
	var reshaped := 0
	for b in town.buildings:
		total += 1
		var c: Array = b.obb.c
		var lat := tlat + float(c[1]) / Geo.DEG
		var lon := tlon + float(c[0]) / kx
		var found = null
		var tfound := Vector2i.ZERO
		var t0 := Geo.tile_of(lat, lon)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var t := t0 + Vector2i(dx, dy)
				streamer.data.block(Geo.block_key(Geo.block_of(t)))
				var td: Dictionary = streamer.data.tile(t)
				for wb in td.get("buildings", []):
					if int(wb.id) == int(b.id):
						found = wb
						tfound = t
		if found == null:
			continue
		matched += 1
		var tc := Geo.tile_centre(tfound)
		var wp := streamer.geo.to_world(tc[0], tc[1]) + Vector3(float(found.obb.c[0]), 0, -float(found.obb.c[1]))
		var err := Vector2(wp.x - float(c[0]), -wp.z - float(c[1])).length()
		max_err = maxf(max_err, err)
		sum_err += err
		var sd := absf(float(found.obb.size[0]) - float(b.obb.size[0])) + absf(float(found.obb.size[1]) - float(b.obb.size[1]))
		if sd > 1.0:
			reshaped += 1  # footprint edited in OSM since the town import (different snapshot)
		else:
			max_size = maxf(max_size, sd)
		var r1 := RandomNumberGenerator.new()
		r1.seed = hash(str(b.id) + ":" + str(town_seed))
		var s_town := HouseGen.pick_style(b, r1)
		var r2 := RandomNumberGenerator.new()
		r2.seed = Builder.seed_of(found, town_seed)
		var s_world := Style.pick(found, r2, Style.region_of(tc[0], tc[1]), streamer.data.density(tfound))
		if s_town == s_world:
			same_style += 1
	var rate := float(matched) / maxf(1.0, total)
	var p1 := rate >= 0.95 and max_err < 1.0 and reshaped <= int(total * 0.03)
	ok = ok and p1
	print("[worldcheck] %s paddington: %d/%d town buildings found in the world tiles (%.0f%%), position error mean %.2f m max %.2f m, size diff max %.2f m (%d footprints edited in OSM since the town import), same style %d/%d" % [
			"PASS" if p1 else "FAIL", matched, total, rate * 100.0, sum_err / maxf(1, matched), max_err, max_size, reshaped, same_style, matched])
	# 2. stream in at Paddington, collision on real houses
	probe.global_position = Vector3.ZERO
	var st := await _settle(60.0)
	var c := streamer.counts()
	print("[worldcheck] settle at Paddington: %.1f s, %s" % [st, str(c)])
	await _wait(0.3)
	var hits := 0
	var tried := 0
	for b in town.buildings:
		if String(b.kind) != "house" or tried >= 40:
			continue
		var bc: Array = b.obb.c
		if Vector2(bc[0], bc[1]).length() > 300.0:
			continue
		tried += 1
		var h := _ray_down(Vector3(bc[0], 0, -float(bc[1])))
		if not h.is_empty() and h.position.y > 2.0:
			hits += 1
	var p2 := tried > 0 and hits >= int(tried * 0.85)
	ok = ok and p2
	print("[worldcheck] %s collision: %d/%d Paddington house centres hit a roof/wall collider above 2 m" % ["PASS" if p2 else "FAIL", hits, tried])
	# 3. fly 13 km at 100 m/s (360 km/h) (east over the CBD and out to Moreton Bay) and watch for hitches + rebases
	streamer.frame_ms_log = PackedFloat32Array()
	streamer.stats.max_apply_ms = 0.0
	streamer.stats.max_update_ms = 0.0
	streamer.stats.max_col_ms = 0.0
	var speed := 100.0
	var dir := Vector3(1, 0, -0.35).normalized()
	probe.set_meta("velocity", dir * speed)
	var flown := 0.0
	var frames := 0
	var worst := 0.0
	var max_abs := 0.0
	var reb0: int = streamer.stats.rebases
	var dist_goal := 13000.0
	var t_start := Time.get_ticks_usec()
	var last := Time.get_ticks_usec()
	while flown < dist_goal:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := minf((now - last) / 1.0e6, 0.05)
		last = now
		var step := dir * speed * dt
		probe.global_position += step
		flown += step.length()
		frames += 1
		max_abs = maxf(max_abs, maxf(absf(probe.global_position.x), absf(probe.global_position.z)))
	var secs := (Time.get_ticks_usec() - t_start) / 1.0e6
	probe.remove_meta("velocity")
	var flog: PackedFloat32Array = streamer.frame_ms_log
	var srt := flog.duplicate()
	srt.sort()
	var p99 := srt[int(srt.size() * 0.99)] if srt.size() > 0 else 0.0
	worst = srt[srt.size() - 1] if srt.size() > 0 else 0.0
	var over := 0
	for v in flog:
		if v > 6.0:
			over += 1
	var reb: int = streamer.stats.rebases - reb0
	var p3 := worst < 12.0 and p99 < 4.0
	ok = ok and p3
	print("[worldcheck] %s streaming: flew %.1f km in %.1f s (%d frames), main-thread streaming work per frame p99 %.2f ms worst %.2f ms, frames over 6 ms: %d, max apply %.2f ms, max update %.2f ms, max collision %.2f ms, jobs %d" % [
			"PASS" if p3 else "FAIL", flown / 1000.0, secs, frames, p99, worst, over, streamer.stats.max_apply_ms, streamer.stats.max_update_ms,
			streamer.stats.max_col_ms, streamer.stats.jobs_done])
	var per := PackedStringArray()
	for k in streamer.stats:
		if String(k).begins_with("apply_ms_"):
			per.append("%s %.2f" % [String(k).substr(9), float(streamer.stats[k])])
	print("[worldcheck]   worst attach per kind (ms): %s; worst single collider: house %.2f ms (%d faces), trees %.2f ms" % [", ".join(per),
			float(streamer.stats.get("col_house_ms", 0.0)), int(streamer.stats.get("col_house_faces", 0)), float(streamer.stats.get("col_trees_ms", 0.0))])
	var p4 := reb >= 6 and max_abs < rebase_distance + 50.0
	ok = ok and p4
	var ll := streamer.geo.to_latlon(probe.global_position)
	print("[worldcheck] %s floating origin: %d rebases, player never further than %.0f m from the origin; now at %.5f, %.5f" % [
			"PASS" if p4 else "FAIL", reb, max_abs, ll[0], ll[1]])
	# after all those rebases a Paddington house must still sit on its lat/lon to the centimetre
	var b0: Dictionary = town.buildings[0]
	var lat_b := tlat + float(b0.obb.c[1]) / Geo.DEG
	var lon_b := tlon + float(b0.obb.c[0]) / kx
	var back := streamer.geo.to_world(lat_b, lon_b)
	var ll2 := streamer.geo.to_latlon(back)
	var drift := Vector2((ll2[1] - lon_b) * kx, (ll2[0] - lat_b) * Geo.DEG).length()
	var p5 := drift < 0.01
	ok = ok and p5
	print("[worldcheck] %s precision: lat/lon -> world -> lat/lon round trip %.4f m, %.0f m away" % ["PASS" if p5 else "FAIL", drift, back.length()])
	# 4. warp to Sydney, check houses + collision there (second region)
	for wi in [1, 2]:
		warp(wi)
		var st2 := await _settle(60.0)
		await _wait(0.3)
		var c2 := streamer.counts()
		var h2 := 0
		var n2 := 0
		var t := Geo.tile_of(WARPS[wi][1], WARPS[wi][2])
		var td: Dictionary = streamer.data.tile(t)
		var tc := Geo.tile_centre(t)
		var base := streamer.geo.to_world(tc[0], tc[1])
		for wb in td.get("buildings", []):
			var p := base + Vector3(float(wb.obb.c[0]), 0, -float(wb.obb.c[1]))
			if p.length() > 320.0 or String(wb.kind) == "shed" or n2 >= 40:
				continue
			n2 += 1
			var hh := _ray_down(p)
			if not hh.is_empty() and hh.position.y > 2.0:
				h2 += 1
		var p6: bool = int(c2.near) > 0 and n2 > 0 and h2 >= int(n2 * 0.8)
		ok = ok and p6
		print("[worldcheck] %s %s: settled in %.1f s, %s, collision %d/%d buildings" % ["PASS" if p6 else "FAIL", WARPS[wi][0], st2, str(c2), h2, n2])
	print("[worldcheck] %s" % ("ALL PASS" if ok else "SOME FAILED"))
	get_tree().quit(0 if ok else 1)


## Windowed: scripted flight (sleigh frozen and moved along a path), FPS + hitches.
func _fps_run() -> void:
	sleigh.freeze = true
	var st := await _settle(60.0)
	print("[worldfps] initial settle %.1f s %s" % [st, str(streamer.counts())])
	await _wait(1.0)
	var results := []
	for leg in [["Paddington -> Brisbane CBD at 60 m, 45 m/s", 0, 60.0, 45.0, Vector3(1, 0, -0.1), 20.0],
			["Sydney CBD -> Bondi at 120 m, 60 m/s", 1, 120.0, 60.0, Vector3(1, 0, 0.1), 20.0],
			["High over Sydney at 600 m, 120 m/s", 1, 600.0, 120.0, Vector3(-0.5, 0, 1), 15.0]]:
		warp(int(leg[1]))
		sleigh.global_position = Vector3(0, leg[2], 0)
		camera.call("snap")
		await _settle(60.0)
		await _wait(1.0)
		var dir: Vector3 = (leg[4] as Vector3).normalized()
		sleigh.look_at(sleigh.global_position + dir, Vector3.UP)
		var times := PackedFloat32Array()
		var t0 := Time.get_ticks_usec()
		var last := t0
		while (Time.get_ticks_usec() - t0) / 1.0e6 < float(leg[5]):
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			var dt := (now - last) / 1.0e6
			last = now
			times.append(dt * 1000.0)
			sleigh.global_position += dir * float(leg[3]) * dt
			sleigh.set_meta("velocity", dir * float(leg[3]))
		var s := times.duplicate()
		s.sort()
		var sum := 0.0
		for v in s:
			sum += v
		var avg := 1000.0 / (sum / s.size())
		var low5 := 1000.0 / s[int(s.size() * 0.95)]
		var hitches := 0
		for v in times:
			if v > 16.7:
				hitches += 1
		var line := "[worldfps] %s: avg %.0f fps, median %.0f, 5%% low %.0f, worst frame %.1f ms, frames > 16.7 ms: %d of %d, draw calls %d, primitives %d" % [
				leg[0], avg, 1000.0 / s[s.size() / 2], low5, s[s.size() - 1], hitches, s.size(),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)]
		print(line)
		print("[worldfps]   %s" % str(streamer.counts()))
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if path.ends_with(".jpg"):
		img.save_jpg(path, 0.9)
	else:
		img.save_png(path)
	print("[worldshots] saved %s" % path)


func _shots(dir: String) -> void:
	sleigh.freeze = true
	camera.set("locked", true)
	var plan := [
		["world_flyover.jpg", 0, Vector3(-60, 70, 90), Vector3(80, 0, -60)],
		["world_brisbane_cbd.jpg", 4, Vector3(-900, 260, 1100), Vector3(0, 40, 0)],
		["world_sydney.jpg", 1, Vector3(-1500, 380, 1700), Vector3(300, 60, -200)],
		["world_bondi.jpg", 3, Vector3(-250, 110, 300), Vector3(150, 0, -150)],
		["world_region2.jpg", 2, Vector3(-260, 140, 320), Vector3(60, 0, -60)],
		["world_lod.jpg", 1, Vector3(0, 1800, 4200), Vector3(0, 0, -2500)],
		["world_street.jpg", 0, Vector3(20, 9, 40), Vector3(-30, 4, -40)],
	]
	for p in plan:
		warp(int(p[1]))
		sleigh.global_position = (p[2] as Vector3) + Vector3(0, -3, 8)
		camera.global_position = p[2]
		camera.look_at(p[3], Vector3.UP)
		streamer.focus = camera
		await _settle(90.0)
		await _wait(1.5)
		await _shot(dir.path_join(String(p[0])))
	streamer.focus = sleigh
	get_tree().quit()
