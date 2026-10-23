extends Node3D
## Landing test: builds the night world, wires sleigh / reindeer / camera / HUD / presents,
## handles restart and present drops. Optional user args (after "--"):
##   --selftest            scripted landings + present drops, prints results, quits
##   --screenshot=<dir>    saves screenshots of the scene into <dir>, then quits
##   --animcheck=<dir>     scripted take-off + landing in a real window; saves stills into <dir> and
##                         small JPEG frame sequences into <dir>/anim_frames, then quits

const GB := preload("res://scripts/greybox.gd")
const LightString := preload("res://scripts/light_string.gd")
const PresentScene := preload("res://scenes/present.tscn")
const Suburb := preload("res://scripts/suburb.gd")
const Mission := preload("res://scripts/chimney_entry.gd")
const Checks := preload("res://scripts/checks.gd")
const C := preload("res://scripts/colliders.gd")
const CollisionDebug := preload("res://scripts/collision_debug.gd")
var collision_debug: Node
const Atmosphere := preload("res://scripts/atmosphere.gd")

const STAR := "★"
const NO_STAR := "☆"

@onready var sleigh: RigidBody3D = $Sleigh
@onready var camera: Camera3D = $ChaseCamera
@onready var hud: CanvasLayer = $HUD
@onready var team: Node3D = $ReindeerTeam

var presents_broken := 0
var presents_delivered := 0
var current_present: RigidBody3D  ## The one riding on the sleigh (null while one is loose).
var all_presents: Array[RigidBody3D] = []
var last_landing := "none yet"
var _checks: RefCounted  # keeps a running scripted check alive across awaits
var stills_mode := false  ## scripted checks hide the sleigh HUD in stills
var world_env: Environment
var atmosphere: Node3D  ## fog + outdoor particles (scripts/atmosphere.gd)
var mission: Node  ## chimney entry + elf + gadgets (scripts/chimney_entry.gd)
const NightClock := preload("res://scripts/night_clock.gd")
const ClockHud := preload("res://scripts/clock_hud.gd")
var night_clock: Node  ## shared environment director (group "night_clock")
var _sky_mat: ShaderMaterial
var _moon_light: DirectionalLight3D
var _fill_light: DirectionalLight3D
var _rim_light: DirectionalLight3D


func _enter_tree() -> void:
	_setup_input()


func _ready() -> void:
	_build_world()
	team.set("sleigh", sleigh)
	camera.set("target", sleigh)
	sleigh.touchdown.connect(_on_touchdown)
	sleigh.crashed.connect(_on_crashed)
	sleigh.reset_done.connect(_on_sleigh_reset)
	_spawn_present()
	mission = Mission.new()
	mission.name = "ElfMission"
	add_child(mission)
	mission.call("setup", self, sleigh, camera, [$HouseFlat, $HouseSteep, $HouseSlick])
	atmosphere = Atmosphere.new()
	if "--noatmo" in OS.get_cmdline_user_args():
		atmosphere.set("ground_mist", false)
		atmosphere.set("height_fog", false)
		atmosphere.set("bg_chimney_smoke", 0)
		atmosphere.set("ember_amount", 0)
		atmosphere.set("pollen_amount", 0)
		atmosphere.set("moths_per_light", 0)
		atmosphere.set("light_haze", 1.0)
		atmosphere.set("chimney_wisps", false)
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)
	atmosphere.call("setup", world_env, get_node_or_null("Suburb"), sleigh, team, [$HouseFlat, $HouseSteep, $HouseSlick])
	_setup_night()
	camera.call("snap")
	hud.call("flash", "Land on the lit rooftops!  Green = safe   Blue = slick   Red = danger", Color(1, 0.95, 0.8), 5.0)
	for a in OS.get_cmdline_user_args():
		if a == "--selftest":
			_run_selftest()
		elif a.begins_with("--screenshot="):
			_take_screenshots(a.get_slice("=", 1))
		elif a.begins_with("--envshots="):
			_env_shots(a.get_slice("=", 1))
		elif a == "--fpscheck":
			_fps_check()
		elif a.begins_with("--headlight="):
			_headlight_check(a.get_slice("=", 1))
		elif a.begins_with("--animcheck="):
			_anim_check(a.get_slice("=", 1))
		elif a.begins_with("--intcheck="):
			_checks = Checks.new()
			_checks.call("int_check", self, a.get_slice("=", 1))
		elif a.begins_with("--firevis="):
			_checks = Checks.new()
			_checks.call("fire_vis", self, a.get_slice("=", 1))
		elif a.begins_with("--nightshots="):
			_checks = Checks.new()
			_checks.call("night_shots", self, a.get_slice("=", 1))
		elif a.begins_with("--mechcheck="):
			_checks = load("res://scripts/mech/mech_checks.gd").new()
			_checks.call("mech_check", self, a.get_slice("=", 1))
		elif a.begins_with("--chimtop="):
			_checks = Checks.new()
			_checks.call("chim_top", self, a.get_slice("=", 1))
		elif a.begins_with("--flueprobe="):
			_checks = Checks.new()
			_checks.call("flue_probe", self, a.get_slice("=", 1))
		elif a.begins_with("--chimcolshot="):
			_checks = Checks.new()
			_checks.call("chim_collision_shot", self, a.get_slice("=", 1))
		elif a.begins_with("--collisionshot="):
			_checks = Checks.new()
			_checks.call("collision_shot", self, a.get_slice("=", 1))
		elif a.begins_with("--wallcheck="):
			_checks = Checks.new()
			_checks.call("wall_check", self, a.get_slice("=", 1))
		elif a.begins_with("--gadgetcheck="):
			_checks = Checks.new()
			_checks.call("gadget_check", self, a.get_slice("=", 1))
		elif a.begins_with("--furntiers="):
			_checks = Checks.new()
			_checks.call("furn_tiers_shot", self, a.get_slice("=", 1))
		elif a.begins_with("--ropecheck="):
			_checks = Checks.new()
			_checks.call("rope_check", self, a.get_slice("=", 1))
		elif a.begins_with("--decoshots="):
			_checks = Checks.new()
			_checks.call("deco_shots", self, a.get_slice("=", 1))
		elif a.begins_with("--solidcheck="):
			_checks = Checks.new()
			_checks.call("solid_check", self, a.get_slice("=", 1))
		elif a.begins_with("--bumpcheck="):
			_checks = Checks.new()
			_checks.call("bump_check", self, a.get_slice("=", 1))
		elif a.begins_with("--elfshots="):
			_checks = Checks.new()
			_checks.call("elf_shots", self, a.get_slice("=", 1))
		elif a.begins_with("--chimview="):
			_checks = Checks.new()
			_checks.call("chim_view", self, a.get_slice("=", 1))
		elif a.begins_with("--chimshots="):
			_checks = Checks.new()
			_checks.call("chim_shots", self, a.get_slice("=", 1))
		elif a.begins_with("--fxshots="):
			_checks = Checks.new()
			_checks.call("fx_shots", self, a.get_slice("=", 1))


# --- input -----------------------------------------------------------------------------------------

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
	# chimney entry + elf (third person) + gadgets
	_bind("interact", [KEY_F], [], [JOY_BUTTON_X])
	_bind("elf_fwd", [KEY_W], [[JOY_AXIS_LEFT_Y, -1.0]])
	_bind("elf_back", [KEY_S], [[JOY_AXIS_LEFT_Y, 1.0]])
	_bind("elf_left", [KEY_A], [[JOY_AXIS_LEFT_X, -1.0]])
	_bind("elf_right", [KEY_D], [[JOY_AXIS_LEFT_X, 1.0]])
	_bind("elf_look_left", [KEY_LEFT], [[JOY_AXIS_RIGHT_X, -1.0]])
	_bind("elf_look_right", [KEY_RIGHT], [[JOY_AXIS_RIGHT_X, 1.0]])
	_bind("elf_look_up", [KEY_UP], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_bind("elf_look_down", [KEY_DOWN], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_bind("elf_crouch", [KEY_CTRL], [], [JOY_BUTTON_LEFT_STICK])  # hold: crawl
	_bind("elf_tac_crouch", [KEY_C], [], [JOY_BUTTON_RIGHT_STICK])  # toggle: tactical crouch
	_bind("collision_debug", [KEY_C, KEY_F9], [])  # C on the sleigh (C crouches as the elf), F9 anywhere
	_bind("elf_jump", [KEY_SPACE], [], [JOY_BUTTON_A])
	_bind("elf_lean_left", [KEY_Z], [], [JOY_BUTTON_DPAD_LEFT])  # hold: lean / peek left
	_bind("elf_lean_right", [KEY_X], [], [JOY_BUTTON_DPAD_RIGHT])  # hold: lean / peek right
	_bind("rope_fire", [KEY_T], [[JOY_AXIS_TRIGGER_LEFT, 1.0]], [], [MOUSE_BUTTON_MIDDLE])  # Crook-Line: grapple / rappel / let go
	_bind("rope_zip", [KEY_B], [], [JOY_BUTTON_DPAD_DOWN])  # zipline: anchor A, anchor B, ride
	_bind("rope_retrieve", [KEY_H], [], [JOY_BUTTON_BACK])  # reel a zipline back in
	_bind("nightvision", [KEY_N], [], [JOY_BUTTON_DPAD_UP])
	_bind("soot_boots", [KEY_J], [])  # Santa's sooty boot prints on / off
	_bind("snack_vac", [KEY_K], [])  # hold: Snack-Vac (silent, from the floor)
	_bind("gadget_use", [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]], [], [MOUSE_BUTTON_LEFT])
	_bind("magnet", [KEY_G], [], [JOY_BUTTON_B], [MOUSE_BUTTON_RIGHT])
	_bind("gadget_next", [KEY_E], [], [JOY_BUTTON_RIGHT_SHOULDER], [MOUSE_BUTTON_WHEEL_DOWN])
	_bind("elf_interact", [KEY_E], [], [JOY_BUTTON_Y])  # doors (E falls through to next gadget when no door is near)
	_bind("gadget_prev", [KEY_Q], [], [JOY_BUTTON_LEFT_SHOULDER], [MOUSE_BUTTON_WHEEL_UP])
	for i in 8:
		_bind("gadget_%d" % (i + 1), [KEY_1 + i], [])


func _bind(action: StringName, keys: Array, axes: Array, buttons: Array = [], mouse: Array = []) -> void:
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
	for mb in mouse:
		var me := InputEventMouseButton.new()
		me.button_index = mb
		InputMap.action_add_event(action, me)


func _process(_delta: float) -> void:
	var busy := mission != null and bool(mission.call("is_busy"))
	if Input.is_action_just_pressed("collision_debug") and (not busy or Input.is_key_pressed(KEY_F9)):
		if collision_debug == null:
			collision_debug = CollisionDebug.new()
			add_child(collision_debug)
		collision_debug.call("toggle")
	hud.visible = not busy and not stills_mode
	if busy:
		return
	if Input.is_action_just_pressed("restart"):
		restart()
	if Input.is_action_just_pressed("camera"):
		camera.call("toggle_mode")
	if Input.is_action_just_pressed("drop_present"):
		drop_present()
	_update_hud()


func _update_hud() -> void:
	var v := sleigh.linear_velocity
	var hs := Vector2(v.x, v.z).length()
	var lines := PackedStringArray()
	lines.append("SPEED      %5.1f m/s   (horizontal %4.1f)" % [v.length(), hs])
	lines.append("VERT SPEED %+5.1f m/s" % v.y)
	lines.append("TILT       %5.0f°" % float(sleigh.get("tilt_deg")))
	lines.append("ALTITUDE   %5.1f m" % sleigh.global_position.y)
	lines.append("STATUS     %s" % sleigh.call("status_text"))
	var vis := sleigh.get_node_or_null("Visual")
	if vis != null:
		lines.append("ANIM       %s" % vis.call("state_name"))
	lines.append("LAST       %s" % last_landing)
	lines.append("PRESENTS   delivered %d   broken %d   %s" % [presents_delivered, presents_broken,
			"(one on board)" if current_present != null else "(one loose)"])
	hud.call("set_stats", "\n".join(lines))


# --- gameplay ---------------------------------------------------------------------------------------

func restart() -> void:
	presents_broken = 0
	presents_delivered = 0
	last_landing = "none yet"
	for p in all_presents:
		if is_instance_valid(p):
			p.queue_free()
	all_presents.clear()
	current_present = null
	sleigh.call("request_reset")
	_spawn_present()
	hud.call("flash", "Restarted", Color.WHITE, 1.5)


func drop_present() -> void:
	if current_present == null:
		return
	var at: Transform3D = sleigh.call("get_set_down_transform") if bool(sleigh.get("grounded")) else sleigh.call("get_carry_transform")
	current_present.call("release", sleigh.linear_velocity, at)
	current_present = null


func _spawn_present() -> void:
	if current_present != null:
		return
	var p := PresentScene.instantiate() as RigidBody3D
	add_child(p)
	p.call("carry", sleigh)
	p.global_transform = sleigh.call("get_carry_transform")
	p.connect("broken", _on_present_broken)
	p.connect("delivered", _on_present_delivered)
	p.connect("lost", _on_present_lost)
	current_present = p
	all_presents.append(p)


func _respawn_present_later(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	_spawn_present()


func _forget(p: RigidBody3D) -> void:
	all_presents.erase(p)
	if p == current_present:
		current_present = null
	p.queue_free()


func _on_present_broken(p: RigidBody3D) -> void:
	presents_broken += 1
	print("[present] smashed (broken total %d)" % presents_broken)
	hud.call("flash", "Present smashed in the yard!", Color(1, 0.4, 0.3), 2.0)
	_forget(p)
	_respawn_present_later(1.0)


func _on_present_lost(p: RigidBody3D) -> void:
	print("[present] lost (never settled on a roof)")
	_forget(p)
	_respawn_present_later(0.5)


func _on_present_delivered(_p: RigidBody3D) -> void:
	presents_delivered += 1
	print("[present] delivered (total %d)" % presents_delivered)
	hud.call("flash", "Present delivered!", Color(0.5, 1, 0.5), 2.0)
	_respawn_present_later(0.6)


func _on_sleigh_reset() -> void:
	# Loose presents in flight when we reset are cleaned up; delivered ones stay on their roofs.
	for p in all_presents.duplicate():
		if is_instance_valid(p) and int(p.get("state")) == 1:
			_forget(p)
	_spawn_present()
	camera.call("snap")


## The night clock: sunset to sunrise over PER_HOUSE_SECONDS x 3 x delivery houses. Scripted
## checks freeze it at 11 pm (the art-directed full night) unless they drive it themselves.
func _setup_night() -> void:
	night_clock = NightClock.new()
	night_clock.name = "NightClock"
	add_child(night_clock)
	night_clock.call("bind", world_env, _sky_mat, _moon_light, _fill_light, _rim_light)
	var roots: Array = [$HouseFlat, $HouseSteep, $HouseSlick]
	if get_node_or_null("Suburb"):
		roots.append(get_node("Suburb"))
	var lights := []
	for r in roots:
		lights.append_array((r as Node).find_children("*", "Light3D", true, false))
	night_clock.call("collect_list", lights)
	night_clock.call("start_run", roots.size() - (1 if get_node_or_null("Suburb") else 0))
	var hud2 := ClockHud.new()
	hud2.name = "ClockHud"
	add_child(hud2)
	if not OS.get_cmdline_user_args().is_empty():
		night_clock.set("running", false)
		night_clock.call("set_hour", 23.0)


func _house_under_sleigh() -> Node3D:
	for h in [$HouseFlat, $HouseSteep, $HouseSlick]:
		var lp: Vector3 = (h as Node3D).to_local(sleigh.global_position)
		if absf(lp.x) < float(h.get("width")) * 0.5 + 1.0 and absf(lp.z) < float(h.get("depth")) * 0.5 + 1.0:
			return h
	return null


func _on_touchdown(r: Dictionary) -> void:
	var detail := "(vert %.1f, horiz %.1f m/s, tilt %.0f°)" % [r.vs, r.hs, r.tilt]
	print("[landing] %s %s stars=%d crash=%s %s" % [r.surface, detail, r.stars, r.crash, r.reason])
	if r.crash:
		last_landing = "CRASH on %s %s" % [r.surface, detail]
		return
	if int(r.stars) == 0:
		return  # launch pad etc.: keep showing the last real landing
	var stars := STAR.repeat(int(r.stars)) + NO_STAR.repeat(3 - int(r.stars))
	last_landing = "%s  %s %s" % [stars, r.surface, detail]
	var words: Array[String] = ["", "Rough landing", "Nice landing!", "PERFECT LANDING!"]
	hud.call("flash", "%s  %s%s" % [stars, "BUMP!  " if r.get("bump", false) else "", words[int(r.stars)]], Color(1, 0.9, 0.3), 3.0)
	# a heavy landing thumps through the roof: the residents of that house stir (resident_events.gd)
	var h := _house_under_sleigh()
	if h and h.has_method("roof_noise"):
		h.call("roof_noise", sleigh.global_position, float(r.vs))


func _on_crashed(reason: String) -> void:
	print("[crash] %s" % reason)
	hud.call("flash", "CRASH!  %s" % reason, Color(1, 0.3, 0.25), 2.5)
	var h := _house_under_sleigh()
	if h and h.has_method("roof_noise"):
		h.call("roof_noise", sleigh.global_position, 9.0)  # a crash on the roof wakes the house


# --- world -----------------------------------------------------------------------------------------

@export_group("Look")
@export var moon_light_energy := 1.05
@export var warm_fill_energy := 0.32
@export var rim_light_energy := 0.55
@export var ambient_energy := 0.5
@export var exposure := 1.15
@export var saturation := 1.18
@export var glow_intensity := 0.55
@export var glow_bloom := 0.03
@export var ssao := true
@export var volumetric_fog := true
@export var fog_density := 0.0055
@export var tree_count := 30
@export var pine_count := 48
@export var runway_length := 16.0


func _build_world() -> void:
	# Painterly dusk-to-night: amber horizon, purple band, deep teal top, toon clouds, big moon.
	var moon_dir := Vector3(0.3, 0.45, -0.85).normalized()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/night_sky.gdshader")
	sky_mat.set_shader_parameter("moon_dir", moon_dir)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_sky_mat = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.44, 0.78)
	env.ambient_light_energy = ambient_energy
	# Filmic-style tonemapping keeps the warm lamps soft instead of clipping; exposure lifts the night.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = exposure
	env.glow_enabled = true
	env.glow_intensity = glow_intensity
	env.glow_strength = 1.0
	env.glow_bloom = glow_bloom
	env.glow_hdr_threshold = 0.95
	env.glow_hdr_scale = 1.5
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# Contact shadows / soft ambient occlusion so houses sit on the ground.
	env.ssao_enabled = ssao
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_light_affect = 0.15
	# Volumetric fog: depth, a lilac horizon haze, and soft glows around the streetlights.
	env.volumetric_fog_enabled = volumetric_fog
	env.volumetric_fog_density = fog_density
	env.volumetric_fog_albedo = Color(0.62, 0.5, 0.78)
	env.volumetric_fog_emission = Color(0.05, 0.03, 0.07)
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_length = 150.0
	env.volumetric_fog_ambient_inject = 0.25
	env.volumetric_fog_sky_affect = 0.12
	env.fog_enabled = false
	env.adjustment_enabled = true
	env.adjustment_saturation = saturation
	env.adjustment_contrast = 1.06
	env.adjustment_brightness = 1.02
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	world_env = env

	# Key: cool moonlight from behind the camera's left so street faces get clear form and the
	# shadows fall away from view (the visible moon in the sky is art-directed separately).
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.72, 0.78, 1.0)
	moon.light_energy = moon_light_energy
	moon.shadow_enabled = true
	moon.shadow_blur = 1.6
	moon.directional_shadow_max_distance = 140.0
	moon.shadow_opacity = 0.85
	# furnished interiors (render layer 2 only) don't cast moon shadows: the shells still do, so
	# moonbeams still fall through the windows, but the shadow cascades skip thousands of props
	moon.shadow_caster_mask = 0xFFFFF & ~2
	add_child(moon)
	_moon_light = moon
	moon.look_at_from_position(Vector3.ZERO, Vector3(0.55, -0.62, -0.55), Vector3.UP)
	# Warm amber fill from the other side (no shadows) keeps shadowed faces warm, never murky.
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(1.0, 0.62, 0.35)
	fill.light_energy = warm_fill_energy
	fill.light_cull_mask = 0xFFFFF & ~2  # interiors (visual layer 2) get their own lamps + moonbeams
	add_child(fill)
	_fill_light = fill
	fill.look_at_from_position(Vector3.ZERO, Vector3(-0.7, -0.3, -0.35), Vector3.UP)
	# Rim/back light from the glowing horizon so silhouettes pop against the sky.
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(1.0, 0.55, 0.38)
	rim.light_energy = rim_light_energy
	rim.light_cull_mask = 0xFFFFF & ~2
	add_child(rim)
	_rim_light = rim
	rim.look_at_from_position(Vector3.ZERO, Vector3(-0.15, -0.22, 1.0), Vector3.UP)

	# Ground (touching it = crash / broken present): painterly summer grass with dry patches.
	var ground := StaticBody3D.new()
	ground.add_to_group("ground")
	ground.set_meta("surface_name", "Yard")
	var gcs := CollisionShape3D.new()
	var gshape := BoxShape3D.new()
	gshape.size = Vector3(600, 1, 600)
	gcs.shape = gshape
	ground.add_child(gcs)
	ground.position = Vector3(0, -0.5, 0)
	add_child(ground)
	var gmesh := BoxMesh.new()
	gmesh.size = gshape.size
	GB.add_mesh(ground, gmesh, Vector3.ZERO, Vector3.ZERO, GB.patchy(Color(0.2, 0.42, 0.14), Color(0.55, 0.5, 0.15), 0.7, 0.05))
	var road := BoxMesh.new()
	road.size = Vector3(7, 0.02, 400)
	GB.add_mesh(self, road, Vector3(2, 0.01, -80), Vector3.ZERO, GB.patchy(Color(0.25, 0.2, 0.32), Color(0.32, 0.26, 0.4), 0.5, 0.3))
	for x in [-1.6, 5.6]:
		GB.box(self, Vector3(0.35, 0.12, 400), Vector3(x, 0.06, -80), Color(0.6, 0.55, 0.6))
	for z in range(-180, 40, 12):
		GB.box(self, Vector3(0.25, 0.03, 3), Vector3(2, 0.015, z), Color(1.0, 0.8, 0.3))

	# The suburb: footpaths, fences, letterboxes, background houses, streetlights, hills... (visual only)
	var sub := Suburb.new()
	sub.name = "Suburb"
	var lh: Array[Node3D] = [$HouseFlat as Node3D, $HouseSteep as Node3D, $HouseSlick as Node3D]
	sub.landing_houses = lh
	add_child(sub)

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# Blobby, crooked gum trees in the back yards and along the nature strips.
	var placed := 0
	var tries := 0
	while placed < tree_count and tries < tree_count * 20:
		tries += 1
		var x := rng.randf_range(12, 55) * (1.0 if tries % 2 == 0 else -1.0)
		var p := Vector3(x, 0, rng.randf_range(-185, 35))
		if sub.call("is_clear", p, 3.0):
			_gum_tree(p, rng)
			placed += 1
	# Ring of chunky Norfolk-pine silhouettes on the horizon.
	for i in pine_count:
		var ang := TAU * float(i) / float(pine_count) + rng.randf_range(-0.05, 0.05)
		var dist := rng.randf_range(150, 230)
		_pine(Vector3(sin(ang) * dist, 0, cos(ang) * dist - 60.0), rng.randf_range(16, 32))

	# Launch pad under the sleigh's start position: chunky wooden deck, candy-cane posts, gold lights.
	var pad := StaticBody3D.new()
	pad.add_to_group("pad")
	pad.set_meta("surface_name", "Launch pad")
	var pcs := CollisionShape3D.new()
	var pshape := BoxShape3D.new()
	pshape.size = Vector3(8, 1.5, 8)
	pcs.shape = pshape
	pad.add_child(pcs)
	pad.position = Vector3(0, 0.75, 0)
	add_child(pad)
	GB.box(pad, pshape.size, Vector3.ZERO, Color(0.6, 0.34, 0.18))
	for i in 8:
		GB.box(pad, Vector3(7.9, 0.06, 0.85), Vector3(0, 0.76, -3.5 + i), Color(0.72, 0.42, 0.2).lightened(0.08 * (i % 2)))
	for c in [Vector3(-4, 0, -4), Vector3(4, 0, -4), Vector3(-4, 0, 4), Vector3(4, 0, 4)]:
		for k in 5:
			GB.cylinder(self, 0.18, 0.18, 0.4, c + Vector3(0, 1.7 + k * 0.4, 0), Color(0.95, 0.1, 0.1) if k % 2 == 0 else Color(0.98, 0.95, 0.9))
		GB.sphere(self, 0.25, c + Vector3(0, 3.7, 0), Color(1.0, 0.7, 0.1), 0.9)
		var post := CylinderShape3D.new()
		post.radius = 0.18
		post.height = 2.0
		var pb := StaticBody3D.new()
		pb.set_meta("surface_name", "Candy-cane post")
		var pcs2 := CollisionShape3D.new()
		pcs2.shape = post
		pcs2.position = c + Vector3(0, 2.5, 0)
		pb.add_child(pcs2)
		var bulb := CollisionShape3D.new()
		var bs := SphereShape3D.new()
		bs.radius = 0.25
		bulb.shape = bs
		bulb.position = c + Vector3(0, 3.7, 0)
		pb.add_child(bulb)
		add_child(pb)
	var gold := Color(1.0, 0.6, 0.05)
	var ls := LightString.new()
	add_child(ls)
	ls.setup(PackedVector3Array([Vector3(-4, 1.55, 4), Vector3(4, 1.55, 4), Vector3(4, 1.55, -4), Vector3(-4, 1.55, -4), Vector3(-4, 1.55, 4)]), gold)
	GB.omni(self, Vector3(0, 3.5, 3), Color(1.0, 0.7, 0.35), 1.2, 10.0)

	# Reindeer runway in front of the pad so the team has somewhere to stand and run on take-off.
	# Solid for the sleigh and presents too (layer 1) and for the reindeer's foot rays (layer 2).
	# Resting on it is "No score here", like the pad.
	var runway := StaticBody3D.new()
	runway.collision_layer = 1 | 2
	runway.set_meta("surface_name", "Reindeer runway")
	runway.collision_mask = 0
	var rcs := CollisionShape3D.new()
	var rshape := BoxShape3D.new()
	rshape.size = Vector3(4.6, 1.5, runway_length)
	rcs.shape = rshape
	runway.add_child(rcs)
	runway.position = Vector3(0, 0.75, -4.0 - runway_length * 0.5)
	add_child(runway)
	GB.box(runway, rshape.size, Vector3.ZERO, Color(0.55, 0.3, 0.16))
	var planks := int(runway_length / 1.0)
	for i in planks:
		GB.box(runway, Vector3(4.5, 0.06, 0.85), Vector3(0, 0.76, runway_length * 0.5 - 0.5 - i), Color(0.68, 0.4, 0.2).lightened(0.08 * (i % 2)))
	var rl := LightString.new()
	add_child(rl)
	var z1 := -4.0 - runway_length
	rl.setup(PackedVector3Array([Vector3(-2.3, 1.55, -4.0), Vector3(-2.3, 1.55, z1), Vector3(2.3, 1.55, z1), Vector3(2.3, 1.55, -4.0)]), Color(0.1, 1.0, 0.25))


func _gum_tree(pos: Vector3, rng: RandomNumberGenerator) -> void:
	# Pale, twisting trunk with a blobby multi-lump canopy (toon, lighter underside, leafy patches).
	var t := Node3D.new()
	t.position = pos
	t.rotation_degrees = Vector3(0, rng.randf_range(0, 360), 0)
	add_child(t)
	var bark := Color(0.92, 0.86, 0.78)
	var h := rng.randf_range(5.0, 8.0)
	var lean := rng.randf_range(-12, 12)
	C.solid(GB.cylinder(t, 0.24, 0.45, h * 0.55, Vector3(0, h * 0.27, 0), bark, Vector3(0, 0, lean)), "Gum tree")
	var canopy := []
	GB.cylinder(t, 0.14, 0.26, h * 0.55, Vector3(-lean * 0.02, h * 0.72, 0), bark, Vector3(0, 0, -lean * 1.4))
	GB.cylinder(t, 0.08, 0.14, h * 0.4, Vector3(-lean * 0.02 + 0.5, h * 0.8, 0.3), bark, Vector3(25, 0, -lean - 30))
	var greens := [Color(0.3, 0.6, 0.3), Color(0.22, 0.55, 0.42), Color(0.42, 0.66, 0.25)]
	var mat: Material = Suburb.foliage(greens[rng.randi() % 3])
	var lumps := rng.randi_range(6, 9)
	for k in lumps:
		var a := TAU * float(k) / float(lumps) + rng.randf_range(-0.4, 0.4)
		var rad := rng.randf_range(0.6, 2.0)
		var off := Vector3(cos(a) * rad, h + rng.randf_range(-0.6, 1.2), sin(a) * rad)
		var r := rng.randf_range(1.0, 1.7)
		var mi := GB.sphere(t, r, off, greens[k % 3], 0.0, Vector3(1.15, 0.8, 1.15))
		mi.material_override = mat
		canopy.append([off, r * 0.9])
	var top := GB.sphere(t, rng.randf_range(1.2, 1.6), Vector3(0, h + 1.3, 0), greens[0], 0.0, Vector3(1.1, 0.85, 1.1))
	top.material_override = mat
	canopy.append([top.position, top.mesh.get("radius") * 0.9])
	C.spheres(t, canopy, "Gum tree")


func _pine(pos: Vector3, h: float) -> void:
	var silhouette := Color(0.16, 0.1, 0.26)
	C.box(self, Vector3(h * 0.35, h, h * 0.35), pos + Vector3(0, h * 0.5, 0), "Norfolk pine")
	GB.cylinder(self, 0.3, 0.5, h * 0.4, pos + Vector3(0, h * 0.2, 0), silhouette, Vector3.ZERO, 0.0, 6)
	for k in 3:
		var y := h * (0.3 + 0.22 * k)
		var r := h * (0.28 - 0.07 * k)
		GB.cylinder(self, 0.0, r, h * 0.38, pos + Vector3(0, y, 0), silhouette, Vector3.ZERO, 0.0, 7)


# --- self-test & screenshots -----------------------------------------------------------------------

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _drop_sleigh(label: String, house: Node3D, offset: Vector3, velocity: Vector3) -> void:
	var top := float(house.get("landing_top"))
	var pos := house.global_position + Vector3(offset.x, top + offset.y, offset.z)
	print("[selftest] %s" % label)
	sleigh.call("teleport", Transform3D(Basis(), pos), velocity)


func _run_selftest() -> void:
	print("[selftest] start")
	await _wait(1.0)
	var flat := $HouseFlat as Node3D
	var steep := $HouseSteep as Node3D
	var slick := $HouseSlick as Node3D
	# Hold Brake (hover) on the way down: should be a soft 3-star landing.
	Input.action_press("brake")
	_drop_sleigh("hover-braked descent onto flat pad (expect 3 stars)", flat, Vector3(0, 4.0, 0), Vector3(0, 0, -3.0))
	await _wait(5.0)
	Input.action_release("brake")
	print("[selftest] status after flat: %s" % sleigh.call("status_text"))
	# Present: set it down on the flat roof while landed there -> should be delivered.
	drop_present()
	await _wait(3.0)
	_drop_sleigh("free-fall drop on flat pad (expect 1-2 stars)", flat, Vector3(2, 1.4, 0), Vector3.ZERO)
	await _wait(2.5)
	_drop_sleigh("hard slam on flat pad (expect crash)", flat, Vector3(0, 2.5, 0), Vector3(0, -9, 0))
	await _wait(3.0)
	_drop_sleigh("gentle drop on steep ridge pad (expect stars)", steep, Vector3(0, 1.2, 0), Vector3.ZERO)
	await _wait(3.0)
	print("[selftest] status after ridge: %s" % sleigh.call("status_text"))
	_drop_sleigh("drop on steep slope (expect slide off -> reset)", steep, Vector3(3.6, 1.0, 0), Vector3.ZERO)
	await _wait(6.0)
	_drop_sleigh("fast skid onto rain-slick roof (expect landing then slide off)", slick, Vector3(0, 1.0, 3.5), Vector3(0, 0, -7.0))
	await _wait(6.0)
	# Present dropped from altitude over the yard -> should smash.
	await _wait(1.5)
	if current_present != null:
		print("[selftest] dropping present over the yard (expect smash)")
		current_present.call("release", Vector3.ZERO, Transform3D(Basis(), Vector3(20, 8, 0)))
		current_present = null
	await _wait(4.0)
	print("[selftest] done: delivered=%d broken=%d" % [presents_delivered, presents_broken])
	get_tree().quit()


func _take_screenshots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await _wait(2.5)
	var cam := camera
	cam.set("locked", true)
	var shots := [
		["landing_test.png", Vector3(7, 9, 16), Vector3(-2, 4, -45)],
		["models_closeup.png", Vector3(2.5, 3.7, 2.8), Vector3(0, 2.7, -0.7)],
		["santa_face.png", Vector3(-1.9, 3.6, -2.4), Vector3(0, 3.25, 0.1)],
		["models_side.png", Vector3(9.5, 3.6, -6.8), Vector3(0, 2.7, -6.8)],
		["house_closeup.png", Vector3(-1, 10, -52), Vector3(9, 5, -75)],
	]
	for s in shots:
		cam.look_at_from_position(s[1], s[2], Vector3.UP)
		cam.reset_physics_interpolation()
		await _wait(0.4)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := dir.path_join(s[0])
		img.save_png(path)
		print("[screenshot] saved %s" % path)
	get_tree().quit()


# --- animation check (real window) ------------------------------------------------------------------

var _anim_frame := 0


func _side_cam(look_ahead: float, dist: float, height: float) -> void:
	var p := sleigh.global_position
	camera.look_at_from_position(p + Vector3(dist, height, -look_ahead), p + Vector3(0, 0.6, -look_ahead), Vector3.UP)


func _grab(still_path := "", frames_dir := "") -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if still_path != "":
		img.save_png(still_path)
		print("[animcheck] still %s  anim=%s" % [still_path.get_file(), sleigh.get_node("Visual").call("state_name")])
	if frames_dir != "":
		var small := img.duplicate() as Image
		small.resize(640, 360, Image.INTERPOLATE_BILINEAR)
		small.save_jpg(frames_dir.path_join("f_%04d.jpg" % _anim_frame), 0.8)
		_anim_frame += 1


## Records frames for `seconds`, following the sleigh from the side. `stills` maps a time (s) to a file.
func _record(seconds: float, frames_dir: String, stills: Dictionary, look_ahead: float, dist: float, height: float, on_tick: Callable = Callable()) -> void:
	var t0 := Time.get_ticks_msec()
	var pending := stills.keys()
	pending.sort()
	var next_frame := 0.0
	while true:
		var t := (Time.get_ticks_msec() - t0) / 1000.0
		if t > seconds:
			break
		if on_tick.is_valid():
			on_tick.call(t)
		_side_cam(look_ahead, dist, height)
		var still := ""
		if not pending.is_empty() and t >= float(pending[0]):
			still = str(stills[pending.pop_front()])
		if still != "" or t >= next_frame:
			await _grab(still, frames_dir if t >= next_frame else "")
			if t >= next_frame:
				next_frame += 1.0 / 12.0
		else:
			await get_tree().process_frame


func _anim_check(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var frames := dir.path_join("anim_frames")
	DirAccess.make_dir_recursive_absolute(frames)
	for f in DirAccess.get_files_at(frames):
		DirAccess.remove_absolute(frames.path_join(f))
	camera.set("locked", true)
	camera.fov = 55.0
	await _wait(1.5)
	# Parked idle on the pad / runway
	await _record(2.5, frames, {2.0: dir.path_join("anim_parked.png")}, 6.5, 14.0, 4.6)
	# Take-off: lift + a nudge of thrust, then hover-brake to hold height.
	print("[animcheck] take-off")
	var tick := func(t: float) -> void:
		if t < 0.75:
			Input.action_press("lift")
		else:
			Input.action_release("lift")
		if t < 0.9:
			Input.action_press("thrust_fwd")
		else:
			Input.action_release("thrust_fwd")
		if t > 1.5:
			Input.action_press("brake")
	await _record(3.6, frames, {0.12: dir.path_join("anim_takeoff_1.png"), 0.55: dir.path_join("anim_takeoff_2.png"), 1.25: dir.path_join("anim_takeoff_3.png")}, 6.5, 14.0, 4.2, tick)
	Input.action_release("brake")
	# Landing on the flat roof: brake-hover down, then drop the last metre for a visible jolt.
	print("[animcheck] landing")
	var flat := $HouseFlat as Node3D
	var top := float(flat.get("landing_top"))
	sleigh.call("teleport", Transform3D(Basis(), flat.global_position + Vector3(0, top + 4.6, 5.0)), Vector3(0, 0, -3.5))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var vis := sleigh.get_node("Visual")
	var marks := {"approach": -1.0, "touch": -1.0}
	var stills := {}
	var land_tick := func(t: float) -> void:
		var h := sleigh.global_position.y - 0.66 - (flat.global_position.y + top)
		if h > 1.1 and not bool(sleigh.get("grounded")):
			Input.action_press("brake")
		else:
			Input.action_release("brake")
		var st := int(vis.get("state"))
		if st == 3 and marks.approach < 0.0:
			marks.approach = t
			stills[t + 0.5] = dir.path_join("anim_landing_1.png")
		if st == 4 and marks.touch < 0.0:
			marks.touch = t
			stills[t + 0.04] = dir.path_join("anim_landing_2.png")
			stills[t + 0.9] = dir.path_join("anim_landing_3.png")
	await _record_dynamic(6.0, frames, stills, land_tick)
	Input.action_release("brake")
	print("[animcheck] done frames=%d last=%s" % [_anim_frame, sleigh.get("last_result")])
	get_tree().quit()


## Like _record, but stills can be added by on_tick while recording (landing moments aren't known up front).
func _record_dynamic(seconds: float, frames_dir: String, stills: Dictionary, on_tick: Callable) -> void:
	var t0 := Time.get_ticks_msec()
	var next_frame := 0.0
	var done := {}
	while true:
		var t := (Time.get_ticks_msec() - t0) / 1000.0
		if t > seconds:
			break
		on_tick.call(t)
		_side_cam(4.5, -12.5, 3.4)
		var still := ""
		for k in stills.keys():
			if not done.has(k) and t >= float(k):
				done[k] = true
				still = str(stills[k])
				break
		if still != "" or t >= next_frame:
			await _grab(still, frames_dir if t >= next_frame else "")
			if t >= next_frame:
				next_frame += 1.0 / 12.0
		else:
			await get_tree().process_frame


## Stills of the lead reindeer's headlight: parked on the runway, then flying level toward a house.
func _headlight_check(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	camera.set("locked", true)
	camera.fov = 60.0
	await _wait(2.0)
	camera.look_at_from_position(Vector3(9, 6.5, 5), Vector3(0, 1.0, -17), Vector3.UP)
	camera.reset_physics_interpolation()
	await _wait(0.5)
	await _grab(dir.path_join("headlight_parked.png"))
	var hl := team.find_child("Headlight", true, false) as Node3D
	if hl != null:
		var spot := hl.find_children("*", "SpotLight3D", true, false)[0] as SpotLight3D
		print("[headlight] at=%s aim=%s energy=%.1f range=%.1f" % [spot.global_position, -spot.global_basis.z, spot.light_energy, spot.spot_range])
	var lead_pos := sleigh.global_position + Vector3(0, 0, -13.6)
	camera.look_at_from_position(lead_pos + Vector3(5.0, 2.0, -2.0), lead_pos + Vector3(0, -0.5, -5.5), Vector3.UP)
	camera.reset_physics_interpolation()
	await _wait(0.3)
	await _grab(dir.path_join("headlight_closeup.png"))
	var flat := $HouseFlat as Node3D
	var top := float(flat.get("landing_top"))
	var start := flat.global_position + Vector3(0, top + 5.5, 34.0)
	sleigh.call("teleport", Transform3D(Basis(), start), Vector3(0, 0, -7.0))
	Input.action_press("lift", 0.535)
	var t0 := Time.get_ticks_msec()
	var shots := [0.6, 1.0, 1.4, 1.8]
	var i := 0
	while i < shots.size():
		var t := (Time.get_ticks_msec() - t0) / 1000.0
		var p := sleigh.global_position
		camera.look_at_from_position(p + Vector3(6.0, 7.5, 8.0), p + Vector3(0, -3.0, -20.0), Vector3.UP)
		if t >= float(shots[i]):
			await _grab(dir.path_join("headlight_fly_%d.png" % i))
			var sp := team.find_children("*", "SpotLight3D", true, false)[0] as SpotLight3D
			var aim := -sp.global_basis.z
			var q := PhysicsRayQueryParameters3D.create(sp.global_position, sp.global_position + aim * 40.0)
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			print("[headlight] fly at=%s aim=%s hit=%s" % [sp.global_position, aim, hit.get("position", "none")])
			i += 1
		else:
			await get_tree().process_frame
	Input.action_release("lift")
	get_tree().quit()


## Environment stills: wide, street level, house close-up, and flying toward the flat-pad house.
func _env_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	camera.set("locked", true)
	camera.fov = 60.0
	await _wait(2.5)
	var shots := [
		["env_wide.png", Vector3(14, 16, 24), Vector3(-3, 2, -60)],
		["env_street.png", Vector3(4.6, 1.7, -19.0), Vector3(1.0, 2.8, -70)],
		["env_house.png", Vector3(3.5, 3.4, -31.0), Vector3(-7.0, 2.6, -41.5)],
	]
	for sh in shots:
		camera.look_at_from_position(sh[1], sh[2], Vector3.UP)
		camera.reset_physics_interpolation()
		await _wait(0.5)
		await _grab(dir.path_join(sh[0]))
	var flat := $HouseFlat as Node3D
	var top := float(flat.get("landing_top"))
	sleigh.call("teleport", Transform3D(Basis(), flat.global_position + Vector3(0, top + 5.5, 34.0)), Vector3(0, 0, -7.0))
	Input.action_press("lift", 0.535)
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) < 1300:
		var p := sleigh.global_position
		camera.look_at_from_position(p + Vector3(7.0, 6.5, 9.0), p + Vector3(-1.0, -2.5, -20.0), Vector3.UP)
		await get_tree().process_frame
	await _grab(dir.path_join("env_fly.png"))
	Input.action_release("lift")
	get_tree().quit()


## Average FPS in a real window (vsync off) from the default chase view and a wide street view.
func _fps_check() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _wait(3.0)
	var results := []
	for view in ["chase", "wide"]:
		if view == "wide":
			camera.set("locked", true)
			camera.look_at_from_position(Vector3(14, 16, 24), Vector3(-3, 2, -60), Vector3.UP)
		await _wait(1.0)
		var frames := 0
		var t0 := Time.get_ticks_usec()
		var worst := 0.0
		var last := t0
		while Time.get_ticks_usec() - t0 < 5000000:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			worst = maxf(worst, (now - last) / 1000.0)
			last = now
			frames += 1
		var secs := (Time.get_ticks_usec() - t0) / 1000000.0
		results.append("%s avg %.0f fps (worst frame %.1f ms)" % [view, frames / secs, worst])
	print("[fps] %s | %s | %s" % [", ".join(results), RenderingServer.get_video_adapter_name(), DisplayServer.window_get_size()])
	get_tree().quit()

