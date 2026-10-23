extends Node
## The night: every delivery run starts at sunset and ends at sunrise on a compressed fake clock.
## This node is the SHARED ENVIRONMENT DIRECTOR. It is in group "night_clock" and owns the time
## of night, the sun and moon arcs, the sky gradient, ambient and fog colours and the "lights on"
## level. Other systems (the streamed Australia map in scripts/world/, the suburb, interiors) read
## it instead of touching the WorldEnvironment themselves:
##   var clock := get_tree().get_first_node_in_group("night_clock")
##   clock.lights_on  (0 day .. 1 full night: streetlights, windows, Christmas lights)
##   clock.state()    -> {hour, k, sun_dir, sun_alt_deg, moon_dir, ambient, fog, lights_on, interior_dim}
##   signal changed(state)  (emitted a few times a second, not every frame)
## Lights that should follow dusk can also just join group "night_lights" (energy x lights_on) or
## "interior_lights" (energy x interior_dim); their energy at setup is taken as the full-night value.
##
## Night length (real seconds) = PER_HOUSE_SECONDS x 3 x house_count, computed at run start.

signal changed(state: Dictionary)

## Measured: one full delivery played by the --deliveryrun autoplay bot at a human-ish pace
## (fly from the start pad to HouseFlat ~70 m away, land, chimney cutscene, walk to the tree,
## leave the present, fill the stocking, back to the hearth, climb out, take off).
## See README "Night length". Re-measure with --deliveryrun if the mission changes a lot.
const PER_HOUSE_SECONDS := 150.0
const SLACK := 3.0  ## the night is 3x the bare delivery time (exploring, hiding, mistakes)

@export var house_count := 3  ## delivery houses in this run / town (the streamed map sets this)
@export var sunset_hour := 20.0  ## Sydney, late December: sunset about 8:05 pm
@export var sunrise_hour := 5.75  ## ...sunrise about 5:45 am
@export var lead_in_hours := 0.25  ## the run starts a little before sunset (golden light)
@export var night_seconds_override := 0.0  ## > 0: fixed night length in real seconds (tests)
@export var scrub_rate := 900.0  ## debug: holding F8 (Shift+F8 back) runs the clock this many x faster
@export var running := true

## How dark solar midnight gets relative to the early-night art palette (tunable)
const DEEP_SKY := 0.38
const DEEP_HOR := 0.45
const DEEP_AMBIENT := 0.75
const DEEP_EXPOSURE := 0.9
var deep := 0.0  ## 0 early night .. 1 solar midnight
var night_seconds := 0.0  ## real seconds from start to sunrise
var elapsed := 0.0
var k := 0.0  ## 0 start (just before sunset) .. 1 sunrise
var hour := 19.75
var lights_on := 0.0
var interior_dim := 1.0
var sun_alt_deg := 0.0

var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var fill: DirectionalLight3D
var rim: DirectionalLight3D
var _base := {}
var _night_lights: Array = []  ## [Light3D, base energy]
var _interior_lights: Array = []
var _emit_t := 0.0
var _last_lights := -1.0
var _last_dim := -1.0


func _ready() -> void:
	add_to_group("night_clock")
	if not InputMap.has_action("time_scrub"):
		InputMap.add_action("time_scrub")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F8
		InputMap.action_add_event("time_scrub", ev)


static func night_length_for(houses: int) -> float:
	return PER_HOUSE_SECONDS * SLACK * maxi(houses, 1)


## Start a run: the clock goes back to just before sunset; the length comes from house_count.
func start_run(houses := -1) -> void:
	if houses > 0:
		house_count = houses
	night_seconds = night_seconds_override if night_seconds_override > 0.0 else night_length_for(house_count)
	elapsed = 0.0
	_apply()
	print("[night] run start: %d houses x %.0f s x %.0f = %.0f s (%.1f min) from %s to sunrise %s" % [house_count, PER_HOUSE_SECONDS, SLACK, night_seconds, night_seconds / 60.0, clock_text(_hour_at(0.0)), clock_text(sunrise_hour)])


## Hook up the world's lighting (main.gd does this; the streamed map can call it with its own).
func bind(p_env: Environment, p_sky: ShaderMaterial, p_moon: DirectionalLight3D, p_fill: DirectionalLight3D, p_rim: DirectionalLight3D) -> void:
	env = p_env
	sky_mat = p_sky
	moon = p_moon
	fill = p_fill
	rim = p_rim
	_base = {
		"top": _sky_param("top_color"), "mid": _sky_param("mid_color"), "hor": _sky_param("horizon_color"),
		"cloud": _sky_param("cloud_color"), "cloud_lit": _sky_param("cloud_lit_color"),
		"amb": env.ambient_light_color, "amb_e": env.ambient_light_energy, "fog": env.volumetric_fog_albedo,
		"moon_e": moon.light_energy if moon else 0.0, "fill_e": fill.light_energy if fill else 0.0, "rim_e": rim.light_energy if rim else 0.0,
		"exp": env.tonemap_exposure,
	}
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "Sun"
		sun.light_color = Color(1.0, 0.62, 0.32)
		sun.shadow_enabled = false  # low sun only at the ends of the night; the moon keeps the shadows
		sun.light_cull_mask = 0xFFFFF & ~2
		add_child(sun)


## Lights that switch with dusk (streetlights, windows, Christmas lights) and interior lamps
## (dimmed late at night). Their current energy is taken as the full-night value.
func collect_list(lights: Array) -> void:
	_night_lights.clear()
	_interior_lights.clear()
	for n in lights:
		var l := n as Light3D
		if l == null or l is DirectionalLight3D or l.is_in_group("no_night_switch") or l.has_meta("twinkle"):
			continue
		if ((l.light_cull_mask & 2) != 0 and (l.light_cull_mask & 1) == 0) or l.is_in_group("interior_lights"):
			_interior_lights.append([l, l.light_energy])
		else:
			_night_lights.append([l, l.light_energy])
	_last_lights = -1.0
	_last_dim = -1.0


func _sky_param(n: String) -> Vector3:
	if sky_mat == null:
		return Vector3.ZERO
	var v = sky_mat.get_shader_parameter(n)
	if v == null:
		v = RenderingServer.shader_get_parameter_default(sky_mat.shader.get_rid(), n)
	if v is Color:
		return Vector3(v.r, v.g, v.b)
	return v if v is Vector3 else Vector3.ZERO


func _hour_at(kk: float) -> float:
	var span := fposmod(sunrise_hour - (sunset_hour - lead_in_hours), 24.0)
	return fposmod(sunset_hour - lead_in_hours + kk * span, 24.0)


## Hours since sunset (negative before it).
func _since_sunset(h: float) -> float:
	var d := fposmod(h - sunset_hour + 12.0, 24.0) - 12.0
	return d


static func clock_text(h: float) -> String:
	var hh := int(floor(h)) % 24
	var mm := int(floor((h - floor(h)) * 60.0))
	var ap := "am" if hh < 12 else "pm"
	var h12 := hh % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, mm, ap]


func _process(delta: float) -> void:
	if night_seconds <= 0.0:
		return
	var rate := 1.0 if running else 0.0
	if Input.is_action_pressed("time_scrub"):
		rate = scrub_rate * (-1.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	elapsed = clampf(elapsed + delta * rate, 0.0, night_seconds * 1.04)
	_apply()


## Jump to a point of the night (0 = start .. 1 = sunrise); tests and the debug scrubber.
func set_k(kk: float) -> void:
	elapsed = clampf(kk, 0.0, 1.04) * night_seconds
	_apply()


func set_hour(h: float) -> void:
	var span := fposmod(sunrise_hour - (sunset_hour - lead_in_hours), 24.0)
	set_k(fposmod(h - (sunset_hour - lead_in_hours), 24.0) / span)


func state() -> Dictionary:
	return {"hour": hour, "k": k, "sun_alt_deg": sun_alt_deg, "sun_dir": _sun_dir(), "moon_dir": _moon_dir(),
			"ambient": env.ambient_light_color if env else Color.BLACK, "fog": env.volumetric_fog_albedo if env else Color.BLACK,
			"lights_on": lights_on, "interior_dim": interior_dim, "text": clock_text(hour)}


var _night_h := 9.75


func _sun_dir() -> Vector3:
	# sets in the west-north-west, rises in the east-south-east (southern summer); below the horizon
	# all night. Direction the light TRAVELS is -this.
	var t := _since_sunset(hour)
	var a := deg_to_rad(sun_alt_deg)
	var az := lerpf(deg_to_rad(-60.0), deg_to_rad(-300.0), clampf((t + 0.5) / (_night_h + 1.0), 0.0, 1.0))
	return Vector3(cos(a) * sin(az), sin(a), cos(a) * cos(az)).normalized()


func _moon_dir() -> Vector3:
	# a near-full Christmas moon: rises in the east at dusk, high over the north at midnight, sets west at dawn
	var t := clampf(_since_sunset(hour) / _night_h, -0.1, 1.1)
	var alt := deg_to_rad(10.0 + 48.0 * sin(clampf(t, 0.0, 1.0) * PI))
	var az := lerpf(deg_to_rad(110.0), deg_to_rad(-110.0), t)
	return Vector3(cos(alt) * sin(az) * -1.0, sin(alt), -cos(alt) * cos(az)).normalized()


func _apply() -> void:
	k = clampf(elapsed / maxf(night_seconds, 0.001), 0.0, 1.04)
	hour = _hour_at(minf(k, 1.0)) if k <= 1.0 else fposmod(sunrise_hour + (k - 1.0) * 6.0, 24.0)
	_night_h = fposmod(sunrise_hour - sunset_hour, 24.0)
	var t := _since_sunset(hour)
	# sun altitude: about -12 deg per hour after sunset, ~-40 deg at midnight, rising again
	if t <= 0.0:
		sun_alt_deg = -t * 12.0
	elif t >= _night_h:
		sun_alt_deg = (t - _night_h) * 12.0
	else:
		sun_alt_deg = -40.0 * sin(PI * t / _night_h)  # ~ -12.9 deg/h at each end, -40 at solar midnight
	var dawn := t > _night_h * 0.5  # pre-dawn / sunrise palette vs sunset / dusk
	# 0 = sun up .. 1 = full night (astronomical-ish), from the sun's altitude
	var night := clampf(-sun_alt_deg / 14.0, 0.0, 1.0)
	night = night * night * (3.0 - 2.0 * night)
	lights_on = clampf((-sun_alt_deg - 1.0) / 4.0, 0.0, 1.0)  # on through civil dusk (sun -1..-5 deg)
	interior_dim = lerpf(1.0, 0.8, clampf((-sun_alt_deg - 8.0) / 12.0, 0.0, 1.0))  # house lamps dim once everyone's in bed
	# "deep" night: the art-directed palette is the early-night look; around solar midnight it
	# goes properly dark (deeper sky, more stars, unlit clouds, lower ambient and exposure)
	deep = clampf((-sun_alt_deg - 12.0) / 20.0, 0.0, 1.0)
	deep = deep * deep * (3.0 - 2.0 * deep)
	if env == null:
		return
	# sky: sunset (warm, light) -> dusk -> the art-directed night -> pre-dawn (pink) -> sunrise
	if sky_mat:
		var day_top := Vector3(0.22, 0.36, 0.62) if not dawn else Vector3(0.3, 0.42, 0.66)
		var day_mid := Vector3(0.85, 0.48, 0.42) if not dawn else Vector3(0.95, 0.62, 0.6)
		var day_hor := Vector3(1.0, 0.55, 0.18) if not dawn else Vector3(1.0, 0.7, 0.42)
		var dusk_hor := Vector3(0.95, 0.42, 0.22) if not dawn else Vector3(0.92, 0.5, 0.48)
		var nb: Vector3 = _base.top
		var nm: Vector3 = _base.mid
		var nh: Vector3 = _base.hor
		var e1 := clampf(night * 2.0, 0.0, 1.0)  # day -> dusk
		var e2 := clampf(night * 2.0 - 1.0, 0.0, 1.0)  # dusk -> night
		var hor := day_hor.lerp(dusk_hor, e1).lerp(nh, e2) * lerpf(1.0, DEEP_HOR, deep)
		sky_mat.set_shader_parameter("top_color", day_top.lerp(nb.lerp(day_top, 0.25), e1).lerp(nb, e2) * lerpf(1.0, DEEP_SKY, deep))
		sky_mat.set_shader_parameter("mid_color", day_mid.lerp(nm, night) * lerpf(1.0, DEEP_SKY, deep))
		sky_mat.set_shader_parameter("horizon_color", hor)
		sky_mat.set_shader_parameter("cloud_color", (_base.cloud as Vector3) * lerpf(1.0, DEEP_SKY, deep))
		sky_mat.set_shader_parameter("cloud_lit_color", (_base.cloud_lit as Vector3).lerp(_base.cloud as Vector3, deep) * lerpf(1.0, DEEP_SKY + 0.15, deep))
		sky_mat.set_shader_parameter("star_amount", (0.35 + 0.45 * deep) * clampf((night - 0.45) / 0.55, 0.0, 1.0))
		sky_mat.set_shader_parameter("moon_dir", _moon_dir())
		sky_mat.set_shader_parameter("sun_dir", _sun_dir())
		sky_mat.set_shader_parameter("sun_amount", clampf((sun_alt_deg + 4.0) / 4.0, 0.0, 1.0))
		sky_mat.set_shader_parameter("sun_color", Vector3(1.0, 0.55, 0.22) if not dawn else Vector3(1.0, 0.68, 0.38))
	# The models' lighting stays the art-directed look (ambient, fog, exposure, fill/rim: the values
	# main.gd set up). Sunset/sunrise only colour the SKY; around solar midnight things go a bit darker.
	# (An earlier version brightened ambient + fog toward a "day" palette: it washed every model out.)
	env.ambient_light_color = _base.amb
	env.ambient_light_energy = float(_base.amb_e) * lerpf(1.0, DEEP_AMBIENT, deep)
	env.volumetric_fog_albedo = (_base.fog as Color).darkened(0.35 * deep)
	env.tonemap_exposure = float(_base.exp) * lerpf(1.0, DEEP_EXPOSURE, deep)
	if sun:
		var sd := _sun_dir()
		sun.visible = sun_alt_deg > -3.0
		sun.light_energy = clampf((sun_alt_deg + 3.0) / 8.0, 0.0, 1.0) * 0.3  # a low warm glint, not a fill
		if sun.visible:
			sun.look_at_from_position(Vector3.ZERO, -sd, Vector3.UP if absf(sd.y) < 0.99 else Vector3.FORWARD)
	if moon:
		moon.light_energy = float(_base.moon_e) * lerpf(0.6, 1.0, night)
	if fill:
		fill.light_energy = float(_base.fill_e) * lerpf(1.0, 0.7, deep)
	if rim:
		rim.light_energy = float(_base.rim_e)
	# dusk switches: streetlights, windows, Christmas lights; interior lamps dim later in the night
	if absf(lights_on - _last_lights) > 0.01:
		_last_lights = lights_on
		for e in _night_lights:
			if is_instance_valid(e[0]):
				(e[0] as Light3D).light_energy = float(e[1]) * lights_on
				(e[0] as Light3D).visible = lights_on > 0.01
		for g in get_tree().get_nodes_in_group("night_lit"):
			if g.has_method("set_night_level"):
				g.call("set_night_level", lights_on)
	if absf(interior_dim - _last_dim) > 0.01:
		_last_dim = interior_dim
		for e in _interior_lights:
			if is_instance_valid(e[0]):
				(e[0] as Light3D).light_energy = float(e[1]) * interior_dim
	_emit_t -= get_process_delta_time()
	if _emit_t <= 0.0:
		_emit_t = 0.25
		changed.emit(state())
