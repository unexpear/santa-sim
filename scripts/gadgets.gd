extends Node
## Prototype elf gadgets + the in-house HUD (hotbar, crosshair, prompts, freeze meter, night vision).
## Lives under ElfMission. Darts are a run-wide supply (10, never regenerate); picking a dart up
## (walk over it, or aim + Dart Magnet) returns it. Leaving darts, a frozen-out fire, a burst pipe
## or a resident out of bed behind when you climb out = evidence (warned first; the exit never locks).
##
## Hotbar (1-8 / mouse wheel / LB-RB), use = left mouse / right trigger:
##   1 Snooze Darts     2 Snore-o-Meter   3 Tuck Trolley   4 Fit-Ghost
##   5 Puff-Possum      6 The Ledger      7 Fireplace Icer (hold)   8 Fire Launcher
## Always on: N Glow-Gogs, G Dart Magnet (aimed dart), F interact / climb out at the fireplace,
## Crook-Line = the chimney abseil (see chimney_entry.gd).

const GB := preload("res://scripts/greybox.gd")
const FX := preload("res://scripts/fx.gd")
const Furn := preload("res://scripts/furniture.gd")
const Resident := preload("res://scripts/resident.gd")
const GHOST := preload("res://shaders/ghost.gdshader")
const ES := preload("res://scripts/elf_size.gd")  ## the shared elf height: every *_eh tunable below is in elf heights
const NV := preload("res://shaders/nightvision.gdshader")
const RopeTech := preload("res://scripts/rope_tech.gd")
const HouseJobs := preload("res://scripts/house_jobs.gd")

@export_group("Glow-Gogs")
@export var goggles_notice_mult := 1.25  ## Residents notice you this much faster while night vision is on.
@export var crouch_notice_mult := 0.5
@export_group("Snooze Darts (elf heights)")
@export var darts_per_run := 10  ## Whole-run supply. Never regenerates; picked-up darts come back.
@export var dart_range_eh := 40.0  ## Max throw distance, eh (8.8 m).
@export var dart_speed_eh := 60.0  ## Launch speed, eh/s (13.2 m/s).
@export var dart_gravity_eh := 4.0  ## Gravity on the light dart, eh/s^2 (0.88 m/s^2): a slight arc, aim-compensated.
@export var dart_skid_eh := 1.5  ## How far a dart skids after landing on a floor, eh (0.33 m).
@export var dart_length_eh := 0.45  ## Dart length, eh (0.099 m): elf-sized dart.
@export var dart_hit_radius_eh := 0.4  ## Dart pick/aim sphere, eh (0.088 m).
@export var dart_mass_g := 3.0  ## Dart mass (grams). The magnet's tug accelerates lighter darts harder.
@export var pickup_radius_eh := 1.6  ## Walk-over pickup, eh (0.35 m).
@export var aim_cone_deg := 2.3  ## Crosshair targeting cone (half-angle) added to each target's size.
@export var muzzle_height_eh := 0.6  ## Where darts / the Icer leave the elf, eh (0.13 m).
@export_group("Dart Magnet (elf heights)")
@export var magnet_range_eh := 20.0  ## Reach, eh (4.4 m). Aimed dart only, line of sight, one at a time.
@export var magnet_tug_mn := 75.0  ## Pull force (millinewtons): 75 mN on a 3 g dart = 25 m/s^2 (114 eh/s^2).
@export var magnet_max_speed_eh := 45.0  ## Top pull speed, eh/s (9.9 m/s).
@export var magnet_catch_eh := 0.8  ## The elf catches the dart within this, eh (0.18 m).
@export var magnet_lift_eh := 0.8  ## The first tug pops the dart up this high, eh (0.18 m), before it flies in.
@export_group("Snore-o-Meter")
@export var snore_radius_eh := 45.0  ## Ping reach, eh (9.9 m: about a whole house).
@export var snore_cooldown := 6.0
@export var snore_show_time := 4.0
@export var night_length := 600.0  ## Seconds for the night to run from start to dawn.
@export var night_start := 0.15  ## Where in the night (0..1) the run begins.
@export var sleep_depth_curve: Curve  ## Multiplier on each resident's sleep depth over the night (x 0..1).
@export_group("Tuck Trolley (elf heights)")
@export var trolley_speed_mult := 0.7  ## The motorised dolly is slower than a scurrying elf.
@export var load_radius_eh := 7.0  ## Load a darted resident from this close, eh (1.54 m).
@export var tuck_radius_eh := 8.0  ## Tuck back in from this close to the bed, eh (1.76 m).
@export var trolley_deck_eh := 0.4  ## Deck height, eh (0.088 m): a low motorised dolly the elf tows.
@export var trolley_handle_eh := 0.55  ## Tow-bar height at the elf's hands, eh (0.12 m).
@export var trolley_wheel_eh := 0.18  ## Wheel radius, eh (0.04 m).
@export var trolley_gap_eh := 1.2  ## Gap between the elf and the dolly, eh (0.26 m).
@export_group("Fit-Ghost / Puff-Possum / Ledger (elf heights)")
@export var ghost_range_eh := 12.0  ## eh (2.64 m)
@export var present_scale := 1.0  ## Presents are real gifts (0.23-0.46 m = 1-2 eh); the Fit-Ghost previews them 1:1.
@export var bauble_noise := 0.35
@export var stocking_range_eh := 10.0  ## eh (2.2 m; stockings hang ~1 m up on the mantel)
@export var ledger_range_eh := 14.0  ## eh (3.08 m)
@export var door_reach_eh := 5.0  ## E opens / closes a door this close (elf heights)
@export var creak_noise_time := 0.8  ## seconds a door creak counts as noise for the residents
@export var snack_reach_eh := 4.0  ## E at Santa's cookies / the reindeer's beer and carrot from this close, eh (0.88 m)
@export var hearth_radius_eh := 4.5  ## "F: climb out" zone at the hearth, eh (0.99 m)
@export_group("Fireplace Icer")
@export var icer_rate := 0.6  ## Freeze meter per second while the Icer is held.
@export var icer_decay := 0.12
@export var fire_freeze_at := 1.0  ## Meter level that puts a lit fire out.
@export var pipe_frost_start := 1.1  ## Frost starts creeping along the pipes from here (warning).
@export var pipe_crack_at := 1.6  ## Pipes crack here...
@export var crack_burst_delay := 10.0  ## ...and burst this many seconds later unless thawed with the Fire Launcher.
@export var pipe_burst_at := 2.2  ## Or burst straight away if you keep icing to here.
@export var burst_wake_radius := 9.0
@export var puddle_max_radius := 1.7
@export var puddle_grow_time := 18.0
@export var puddle_slip := 0.2  ## Elf acceleration multiplier on the puddle (slippery).
@export var icer_range_eh := 16.0  ## eh (3.52 m)
@export var relight_range_eh := 16.0  ## Fire Launcher relight, eh (3.52 m)
@export var thaw_range_eh := 14.0  ## Fire Launcher pipe thaw, eh (3.08 m)

const SLOTS := ["Snooze Darts", "Snore-o-Meter", "Tuck Trolley", "Fit-Ghost", "Puff-Possum", "The Ledger", "Fireplace Icer", "Fire Launcher"]
const SLOT_COLORS := [Color(0.6, 0.8, 1), Color(0.8, 0.6, 1), Color(1, 0.75, 0.3), Color(0.3, 1, 0.5), Color(1, 0.6, 0.8), Color(1, 0.9, 0.4), Color(0.6, 0.95, 1), Color(1, 0.5, 0.2)]

var main: Node
var rope: Node3D  ## Crook-Line rope tech + climbing (rope_tech.gd)
var mission: Node
var elf: CharacterBody3D
var house: Node3D
var interior: Node3D
var active := false

var slot := 0
var darts_left := 10
var darts_in_house: Array = []
var night_time := 0.0
var goggles := false
var snore_cd := 0.0
var present_stack: Array = ["PresentB", "PresentA", "PresentC", "PresentA", "PresentB", "PresentC"]
var presents_placed := 0
var stockings_filled := 0
var presents_placed_here := 0  ## this house only (house_jobs.gd checklist)
var stockings_filled_here := 0
var jobs: Node  ## per-house objectives: snacks, Santa's boot prints, checklist (house_jobs.gd)
var noise_bus: Callable  ## resident_events.gd: (pos, radius m, what) -> residents' restlessness
var ledger_result := ""
var evidence_log: Array = []  ## one Dictionary per house exited with evidence left behind
var exit_warned_until := 0.0
var icing := false

var _targeted_dart: Node3D
var _trolley: Node3D
var _carrying: Node3D
var _ghost: MeshInstance3D
var _ghost_spot := -1
var _ghost_fits := false
var _frost: GPUParticles3D
var _snore_labels: Array = []
var _nv_markers: Array = []
var _icer_held := false
var _flying: Array = []  # darts in flight: {node, start, v0, t, T, target, res, normal}
var _pulling: Array = []  # darts being magnet-pulled: {node, vel}
var hidden_icon: Label

# UI
var ui: CanvasLayer
var hotbar: HBoxContainer
var slot_panels: Array = []
var prompt: Label
var info: Label
var popup: Label
var crosshair: Label
var meter_root: Control
var meter_fill: ColorRect
var meter_label: Label
var nv_rect: ColorRect
var _popup_t := 0.0


func _ready() -> void:
	darts_left = darts_per_run
	night_time = night_start * night_length
	if sleep_depth_curve == null:
		sleep_depth_curve = Curve.new()
		sleep_depth_curve.add_point(Vector2(0.0, 1.1))
		sleep_depth_curve.add_point(Vector2(0.5, 0.85))
		sleep_depth_curve.add_point(Vector2(1.0, 0.5))
	_build_ui()
	rope = RopeTech.new()
	rope.name = "RopeTech"
	add_child(rope)
	jobs = HouseJobs.new()
	jobs.name = "HouseJobs"
	add_child(jobs)
	jobs.connect("noise", make_noise)


## Any noise the elf makes (crunching, a snapped pick, a knocked bauble...): residents hear it
## through walls and doors (resident_events.gd) and get restless.
func make_noise(pos: Vector3, radius: float, what: String) -> void:
	if noise_bus.is_valid():
		noise_bus.call(pos, radius, what)
	_creak_t = maxf(_creak_t, 0.5)
	_creak_radius = maxf(_creak_radius if _creak_t > 0.0 else 0.0, radius)


func night_factor() -> float:
	var clock := get_tree().get_first_node_in_group("night_clock") if is_inside_tree() else null
	if clock and float(clock.get("night_seconds")) > 0.0:
		return sleep_depth_curve.sample(clampf(float(clock.get("k")), 0.0, 1.0))
	return sleep_depth_curve.sample(clampf(night_time / night_length, 0.0, 1.0))


# =================================================================================================
# UI
# =================================================================================================

func _label(size: int, parent: Node) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	parent.add_child(l)
	return l


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	nv_rect = ColorRect.new()
	nv_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	nv_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = NV
	nv_rect.material = sm
	nv_rect.visible = false
	ui.add_child(nv_rect)
	crosshair = _label(30, ui)
	crosshair.text = "+"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-9, -22)
	crosshair.modulate = Color(1, 1, 1, 0.8)
	prompt = _label(26, ui)
	prompt.anchor_left = 0.0
	prompt.anchor_right = 1.0
	prompt.anchor_top = 0.66
	prompt.anchor_bottom = 0.66
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.modulate = Color(1.0, 0.95, 0.6)
	popup = _label(40, ui)
	popup.anchor_right = 1.0
	popup.anchor_top = 0.22
	popup.anchor_bottom = 0.22
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info = _label(18, ui)
	info.anchor_left = 1.0
	info.anchor_right = 1.0
	info.offset_left = -430
	info.offset_top = 14
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hotbar = HBoxContainer.new()
	hotbar.anchor_left = 0.5
	hotbar.anchor_right = 0.5
	hotbar.anchor_top = 1.0
	hotbar.anchor_bottom = 1.0
	hotbar.offset_left = -520
	hotbar.offset_top = -118
	hotbar.add_theme_constant_override("separation", 6)
	ui.add_child(hotbar)
	for i in SLOTS.size():
		var pnl := PanelContainer.new()
		pnl.custom_minimum_size = Vector2(124, 60)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.1, 0.08, 0.75)
		sb.border_color = SLOT_COLORS[i]
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(8)
		pnl.add_theme_stylebox_override("panel", sb)
		var l := _label(14, pnl)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hotbar.add_child(pnl)
		slot_panels.append([pnl, sb, l])
	meter_root = Control.new()
	meter_root.anchor_left = 0.5
	meter_root.anchor_right = 0.5
	meter_root.anchor_top = 0.74
	meter_root.anchor_bottom = 0.74
	meter_root.offset_left = -200
	ui.add_child(meter_root)
	var bg := ColorRect.new()
	bg.size = Vector2(400, 18)
	bg.color = Color(0, 0, 0, 0.6)
	meter_root.add_child(bg)
	meter_fill = ColorRect.new()
	meter_fill.size = Vector2(0, 18)
	meter_fill.color = Color(0.6, 0.9, 1.0)
	meter_root.add_child(meter_fill)
	for mark in [fire_freeze_at, pipe_crack_at]:
		var tick := ColorRect.new()
		tick.size = Vector2(3, 26)
		tick.position = Vector2(400.0 * mark / pipe_burst_at - 1.0, -4)
		tick.color = Color(1, 1, 1, 0.9) if mark == fire_freeze_at else Color(1, 0.3, 0.2)
		meter_root.add_child(tick)
	hidden_icon = _label(24, ui)
	hidden_icon.text = "◐ Hidden"
	hidden_icon.anchor_left = 0.5
	hidden_icon.anchor_right = 0.5
	hidden_icon.offset_left = -70
	hidden_icon.offset_top = 16
	hidden_icon.modulate = Color(0.55, 1.0, 0.6)
	hidden_icon.visible = false
	meter_label = _label(16, meter_root)
	meter_label.position = Vector2(0, -24)
	meter_root.visible = false
	set_mode("sleigh")


func set_mode(mode: String) -> void:
	var elf_mode := mode == "elf"
	hotbar.visible = elf_mode
	crosshair.visible = elf_mode
	info.visible = elf_mode
	if not elf_mode:
		nv_rect.visible = false
		hidden_icon.visible = false
	_refresh_hotbar()


func flash(text: String, color := Color.WHITE, seconds := 2.5) -> void:
	popup.text = text
	popup.modulate = color
	_popup_t = seconds


func _refresh_hotbar() -> void:
	for i in slot_panels.size():
		var sb: StyleBoxFlat = slot_panels[i][1]
		var l: Label = slot_panels[i][2]
		var sel := i == slot
		sb.bg_color = Color(0.1, 0.25, 0.15, 0.92) if sel else Color(0.06, 0.1, 0.08, 0.7)
		sb.set_border_width_all(4 if sel else 2)
		var extra := ""
		match i:
			0:
				extra = "\n%d / %d" % [darts_left, darts_per_run]
			1:
				extra = "\nready" if snore_cd <= 0.0 else "\n%.0fs" % snore_cd
			3:
				extra = "\nnext: %s" % (_present_name(present_stack[0]) if not present_stack.is_empty() else "-")
		l.text = "%d %s%s" % [i + 1, SLOTS[i], extra]
		(slot_panels[i][0] as Control).modulate = Color(1, 1, 1, 1.0 if sel else 0.75)


func _present_name(p: String) -> String:
	return {"PresentA": "medium", "PresentB": "BIG", "PresentC": "tall"}.get(p, p)


# =================================================================================================
# Session
# =================================================================================================

func begin(h: Node3D, e: CharacterBody3D) -> void:
	house = h
	interior = h.get("interior")
	elf = e
	active = true
	darts_in_house.clear()
	exit_warned_until = 0.0
	interior.set("fire_was_lit", bool(interior.get("fire_was_lit")) or bool(h.get("fireplace_lit")))
	_build_nv_markers()
	_set_goggles(goggles)
	for dr in interior.get("doors"):
		dr.set("elf", elf)
		if not dr.is_connected("creaked", _on_door_creak):
			dr.connect("creaked", _on_door_creak)
	set_mode("elf")
	_refresh_hotbar()
	rope.call("begin", h, e, self)
	presents_placed_here = 0
	stockings_filled_here = 0
	for sp in interior.get("present_spots"):
		if bool(sp.get("ours", false)):
			presents_placed_here += 1
	for s in interior.get("stockings"):
		if bool(s.get_meta("filled", false)):
			stockings_filled_here += 1
	jobs.call("begin", h, e, self)


## What would count as evidence if you left now.
func exit_problems() -> Array:
	var out := []
	var n := darts_in_house.size()
	if n > 0:
		out.append("%d dart%s left in house!" % [n, "" if n == 1 else "s"])
	if bool(interior.get("fire_was_lit")) and not bool(house.get("fire_lit")):
		out.append("Fire left out!")
	for p in interior.get("pipes"):
		if int(p.state) == 2:
			out.append("Burst pipe!")
			break
		elif int(p.state) == 1:
			out.append("Cracked pipe (it'll burst)!")
			break
	for r in interior.get("residents"):
		if int(r.state) == Resident.State.DARTED or int(r.state) == Resident.State.CARRIED:
			out.append("%s isn't back in bed!" % r.resident_name)
	var zl := int(rope.call("lines_left")) if rope else 0
	if zl > 0:
		out.append("%d zipline%s left up!" % [zl, "" if zl == 1 else "s"])
	return out


## Called when the elf climbs out. Records evidence (for the newspaper / penalty).
func end() -> Dictionary:
	var problems := exit_problems()
	var ev := {"house": str(house.name), "darts_left_behind": darts_in_house.size(), "problems": problems,
			"fire_out": bool(interior.get("fire_was_lit")) and not bool(house.get("fire_lit")),
			"pipes_burst": problems.has("Burst pipe!") or problems.has("Cracked pipe (it'll burst)!"),
			"presents": presents_placed, "stockings": stockings_filled, "ledger": ledger_result,
			"complete": bool(jobs.call("is_complete")), "jobs": jobs.call("checklist_text")}
	jobs.call("end")
	print("[jobs] %s: %s" % [ev.house, "COMPLETE" if ev.complete else "unfinished"])
	if not problems.is_empty():
		evidence_log.append(ev)
		var lines := []
		if ev.darts_left_behind > 0:
			lines.append("EVIL BURGLAR ELVES DRUG LOCAL FAMILY")
		if ev.fire_out:
			lines.append("FIREPLACE MYSTERIOUSLY FROZEN")
		if ev.pipes_burst:
			lines.append("PLUMBERS WORKING CHRISTMAS DAY AFTER MYSTERY BIG FREEZE")
		if int(rope.call("lines_left")) > 0:
			lines.append("TINY ZIPLINE FOUND STRUNG ACROSS LOUNGE ROOM")
		print("[evidence] %s: %s | headlines: %s" % [ev.house, ", ".join(problems), "; ".join(lines)])
	else:
		print("[evidence] %s: clean exit" % ev.house)
	for d in darts_in_house:
		if is_instance_valid(d):
			d.set_meta("left_behind", true)
	for m in _nv_markers:
		if is_instance_valid(m):
			m.queue_free()
	_nv_markers.clear()
	_clear_snore()
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if _trolley:
		_trolley.queue_free()
		_trolley = null
	if _frost:
		_frost.queue_free()
		_frost = null
	_set_goggles(false, false)
	rope.call("end")
	active = false
	set_mode("sleigh")
	return ev


# =================================================================================================
# Per-frame
# =================================================================================================

func _process(delta: float) -> void:
	night_time += delta
	snore_cd = maxf(0.0, snore_cd - delta)
	if _popup_t > 0.0:
		_popup_t -= delta
		popup.modulate.a = clampf(_popup_t, 0.0, 1.0)
	_update_pipes_all(delta)
	if elf != null and interior != null:
		_update_flying(delta)
		_update_pulling(delta)
	if not active or elf == null:
		_update_meter()
		return
	if Input.is_action_just_pressed("nightvision"):
		_set_goggles(not goggles)
	for i in SLOTS.size():
		if Input.is_action_just_pressed("gadget_%d" % (i + 1)):
			select(i)
	var door_used := false
	if Input.is_action_just_pressed("elf_interact") and bool(elf.get("control_enabled")):
		var dr := door_in_reach()
		if dr:
			use_door(dr)
			door_used = true
		else:
			var sn := snack_in_reach()
			if sn:
				eat_by_hand(sn)
				door_used = true
	if Input.is_action_just_pressed("gadget_next") and not door_used:
		select((slot + 1) % SLOTS.size())
	if Input.is_action_just_pressed("gadget_prev"):
		select((slot + SLOTS.size() - 1) % SLOTS.size())
	var ctl := bool(elf.get("control_enabled"))
	var use_pressed := ctl and Input.is_action_just_pressed("gadget_use")
	var use_held := ctl and Input.is_action_pressed("gadget_use")
	if Input.is_action_just_pressed("soot_boots") and ctl:
		jobs.call("toggle_boots")
	if Input.is_action_pressed("snack_vac") and ctl and not bool(jobs.call("busy")):
		var sv := snack_in_reach(true)
		if sv:
			jobs.call("start_eat", sv, "vac")
	jobs.call("tick", delta)
	rope.call("tick", delta)
	_tick(delta, use_pressed, use_held or _icer_held)
	_update_meter()


func select(i: int) -> void:
	slot = i
	_refresh_hotbar()
	if _trolley:
		_trolley.visible = slot == 2 or _carrying != null


## The gadget logic (also driven directly by the scripted check).
func _tick(delta: float, use_pressed: bool, use_held: bool) -> void:
	var nf := night_factor()
	var mult := (goggles_notice_mult if goggles else 1.0) * (crouch_notice_mult if bool(elf.get("crouched")) else float(elf.call("visibility_mult")))
	var hid := bool(elf.get("hidden"))
	hidden_icon.visible = hid
	var noise := float(elf.call("noise_radius"))
	if _creak_t > 0.0:
		_creak_t -= delta
		noise = maxf(noise, _creak_radius)  # a creaking door carries further than footsteps
	var awake := []
	for r in interior.get("residents"):
		r.tick(delta, elf.global_position + Vector3(0, ES.m(0.5), 0), nf, mult, hid, noise)
		if int(r.state) == Resident.State.AWAKE:
			awake.append(r.resident_name)
	var p_text := ""
	# dart pickup by walking over + Dart Magnet targeting (aimed dart, line of sight, range in elf heights)
	for d in darts_in_house.duplicate():
		if is_instance_valid(d) and bool(d.get_meta("landed", false)) and d.global_position.distance_to(elf.global_position + Vector3(0, ES.m(0.3), 0)) < ES.m(pickup_radius_eh):
			_collect_dart(d, false)
	_update_magnet_target()
	if _targeted_dart:
		var dm := _targeted_dart.global_position.distance_to(elf.global_position)
		p_text = "G: Dart Magnet  (%.1f m = %.1f elf heights)" % [dm, dm / ES.ELF_HEIGHT]
		if Input.is_action_just_pressed("magnet"):
			magnet_pull()
	# slippery puddles
	var slip := 1.0
	for p in interior.get("pipes"):
		var pud: MeshInstance3D = p.puddle
		if pud.visible and Vector2(elf.global_position.x - pud.global_position.x, elf.global_position.z - pud.global_position.z).length() < pud.scale.x:
			slip = puddle_slip
	elf.set("accel_mult", slip)
	elf.set("speed_mult", trolley_speed_mult if _carrying else 1.0)
	if _carrying:
		_place_trolley()
	# gadget in hand
	if _ghost:
		_ghost.visible = false
	icing = false
	if _frost:
		_frost.emitting = false
	match slot:
		0:
			if use_pressed:
				fire_dart()
		1:
			if use_pressed:
				snore_ping()
		2:
			p_text = _trolley_tick(use_pressed, p_text)
		3:
			p_text = _ghost_tick(use_pressed, p_text)
		4:
			p_text = _puff_tick(use_pressed, p_text)
		5:
			p_text = _ledger_tick(use_pressed, p_text)
		6:
			p_text = _icer_tick(delta, use_held, p_text)
		7:
			p_text = _relight_tick(use_pressed, p_text)
	var snear := snack_in_reach()
	if snear and p_text == "":
		p_text = "E: " + ("cookies and milk" if str(snear.get_meta("piece", "")) == "CookiesMilk" else "beer and a carrot")
	var dnear := door_in_reach()
	if dnear and p_text == "":
		p_text = "Door: deadbolted" if bool(dnear.get("locked")) else ("E: lean on it (%s, %.0f kg)" % [str(dnear.get("handle_type")), float(dnear.get("mass"))] if not bool(dnear.get("latched")) else "E: hang on the %s handle (latched)" % str(dnear.get("handle_type")))
	if Vector2(elf.global_position.x, elf.global_position.z).distance_to(Vector2(_hearth().x, _hearth().z)) < hearth_radius():
		var probs := exit_problems()
		if probs.is_empty():
			p_text = "F: climb back up the chimney (Crook-Line)"
		else:
			p_text = "F: climb out  -  WARNING: " + "  ".join(probs)
	if snear and not p_text.begins_with("E:"):
		p_text = "E: " + ("cookies and milk" if str(snear.get_meta("piece", "")) == "CookiesMilk" else "beer and a carrot") + "    " + p_text
	prompt.text = p_text
	if not awake.is_empty():
		info.text = "%s AWAKE!  Dart them or get out of sight.\n" % ", ".join(awake)
	else:
		info.text = ""
	info.text += "Darts %d/%d   (%d in this house)\nN: Glow-Gogs %s   J: Soot Boots   K: Snack-Vac\n\n%s" % [darts_left, darts_per_run, darts_in_house.size(),
			"ON" if goggles else "off", jobs.call("checklist_text")]
	if snore_cd > 0.0 or slot == 1:
		_refresh_hotbar()


## The nearest door the elf can reach (same floor, within door_reach_eh of the slab's middle).
func door_in_reach() -> Node3D:
	if interior == null or elf == null:
		return null
	var best: Node3D = null
	var bd := ES.m(door_reach_eh)
	for dr in interior.get("doors"):
		var m: Vector3 = dr.call("world_mid")
		if absf(m.y - elf.global_position.y) > 0.5:
			continue
		var dd := Vector2(m.x - elf.global_position.x, m.z - elf.global_position.z).length()
		if dd < bd:
			bd = dd
			best = dr
	return best


## Santa's snacks (cookies and milk, beer and a carrot) within reach: E just comments, no rule effect.
func snack_in_reach(device := false) -> Node3D:
	if interior == null or elf == null:
		return null
	var best: Node3D = null
	var bd := ES.m(snack_reach_eh) * (2.2 if device else 1.0)  # the Snack-Vac's hose reaches up from the floor
	for c in interior.get_children():
		if c is MeshInstance3D and str(c.get_meta("piece", "")) in ["CookiesMilk", "BeerCarrot"]:
			var d := (c as Node3D).global_position.distance_to(elf.global_position)
			if d < bd:
				bd = d
				best = c
	return best


## By hand the elf has to be UP at the snacks (on the coffee table / hearth), not under them: a
## 0.22 m elf can't reach a plate 0.45 m up. From the floor use the Snack-Vac (hold K).
func eat_by_hand(sn: Node3D) -> bool:
	if sn.global_position.y - elf.global_position.y > ES.m(0.6):
		flash("Too high to reach: climb up there, or hold K for the Snack-Vac", Color(1.0, 0.85, 0.6), 2.0)
		return false
	if not bool(jobs.call("start_eat", sn, "hand")):
		look_at_snack(sn)
		return false
	return true


func look_at_snack(sn: Node3D) -> void:
	if str(sn.get_meta("piece", "")) == "CookiesMilk":
		flash("Santa will want those", Color(1.0, 0.9, 0.65), 2.2)
	else:
		flash("The reindeer will want that", Color(1.0, 0.9, 0.65), 2.2)


## E at a door: the elf does what a 0.5 kg elf can do - hang its weight on the handle if it has
## climbed up to it, or lean on the slab. The door mechanism (door.gd) decides what happens.
func use_door(dr: Node3D) -> void:
	if bool(dr.get("locked")):
		flash("Deadbolted. Climb to the thumb-turn inside, or pick it", Color(1.0, 0.8, 0.5), 1.8)
		return
	var hp: Vector3 = dr.call("handle_grab_point", elf.global_position)
	var at_handle := absf(hp.y - elf.global_position.y - ES.m(0.8)) < ES.m(0.9) and Vector2(hp.x - elf.global_position.x, hp.z - elf.global_position.z).length() < ES.m(3.0)
	if bool(dr.get("latched")):
		if at_handle:
			dr.call("elf_hang", elf.global_position)
			var kind := str(dr.get("handle_type"))
			if kind == "knob":
				flash("Your hands slip on the round knob. Wrap a rope round it and pull", Color(1.0, 0.85, 0.6), 2.2)
			else:
				flash("Hanging on the handle...", Color(0.9, 1.0, 0.8), 1.2)
		else:
			flash("Latched. The handle's way up there: climb to it, or rope it (%s)" % str(dr.get("handle_type")), Color(1.0, 0.85, 0.6), 2.2)
		return
	dr.call("elf_lean", elf.global_position)


var _creak_t := 0.0
var _creak_radius := 0.0


## Stealth hook: a door creak is a noise event (radius in metres) the residents hear briefly.
func _on_door_creak(_pos: Vector3, radius: float) -> void:
	_creak_t = creak_noise_time
	_creak_radius = radius


func hearth_radius() -> float:
	return ES.m(hearth_radius_eh)


func magnet_range() -> float:
	return ES.m(magnet_range_eh)


func _hearth() -> Vector3:
	return house.to_global(interior.get("hearth_point"))


# ---- aiming ---------------------------------------------------------------------------------------

func _cam() -> Camera3D:
	return elf.get("camera")


func ray(mask: int, max_dist := 30.0) -> Dictionary:
	var cam := _cam()
	var from := cam.global_position
	var to := from - cam.global_basis.z * max_dist
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	return elf.get_world_3d().direct_space_state.intersect_ray(q)


## Index of the target (world positions) closest to the aim line, within line distance + range.
func aimed(points: Array, line_tol: float, max_range: float) -> int:
	var cam := _cam()
	var o := cam.global_position
	var d := -cam.global_basis.z
	var best := -1
	var best_score := INF
	for i in points.size():
		var p: Vector3 = points[i]
		if p.distance_to(elf.global_position) > max_range:
			continue
		var t := (p - o).dot(d)
		if t < 0.0:
			continue
		var perp := (o + d * t).distance_to(p)
		var tol := line_tol + t * tan(deg_to_rad(aim_cone_deg))
		if perp < tol and perp < best_score:
			best_score = perp
			best = i
	return best


# ---- Snooze Darts + Dart Magnet --------------------------------------------------------------------

func _make_dart() -> Node3D:
	# modelled 0.12 m long, then scaled to the elf (dart_length_eh)
	var d := Node3D.new()
	d.name = "Dart"
	var vis := Node3D.new()
	vis.name = "Vis"
	vis.scale = Vector3.ONE * (ES.m(dart_length_eh) / 0.12)
	d.add_child(vis)
	var shaft := GB.cylinder(vis, 0.008, 0.008, 0.12, Vector3(0, 0, 0.0), Color(0.75, 0.78, 0.8), Vector3(90, 0, 0))
	GB.cylinder(vis, 0.0, 0.01, 0.03, Vector3(0, 0, -0.075), Color(0.6, 0.6, 0.65), Vector3(-90, 0, 0))
	var tail := GB.sphere(vis, 0.025, Vector3(0, 0, 0.07), Color(1.0, 0.4, 0.8), 0.6, Vector3(1, 1, 1.6))
	tail.name = "Tail"
	var r := ES.m(dart_hit_radius_eh)
	var glow := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r * 0.7
	sm.height = r * 1.4
	glow.mesh = sm
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(1.0, 0.4, 0.9, 0.55)
	gm.no_depth_test = true
	glow.material_override = gm
	glow.visible = false
	glow.add_to_group("nv_glow")
	d.add_child(glow)
	var hl := MeshInstance3D.new()
	hl.name = "Highlight"
	var hm := SphereMesh.new()
	hm.radius = r
	hm.height = r * 2.0
	hl.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.albedo_color = Color(0.4, 1.0, 0.5, 0.45)
	hmat.no_depth_test = true
	hl.material_override = hmat
	hl.visible = false
	d.add_child(hl)
	var body := StaticBody3D.new()
	body.collision_layer = 32
	body.collision_mask = 0
	body.set_meta("dart", d)
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = r
	cs.shape = s
	body.add_child(cs)
	d.add_child(body)
	for n in d.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = 3
	shaft.name = "Shaft"
	return d


func _muzzle() -> Vector3:
	return elf.global_position + Vector3(0, ES.m(muzzle_height_eh), 0)


## Throw a dart along the crosshair. It flies a light ballistic arc (aim-compensated so it lands on
## the crosshair point), then sticks in a wall, skids along a floor, or knocks out a resident.
func fire_dart() -> void:
	if darts_left <= 0:
		flash("Out of darts! Pick some back up.", Color(1, 0.5, 0.4))
		return
	var rng := ES.m(dart_range_eh)
	var hit := ray(4, rng)
	# sleepers lie inside their bed's collision box, so test residents separately (a little leeway)
	var rhit := ray(16, rng)
	if not rhit.is_empty():
		var o := _cam().global_position
		if hit.is_empty() or o.distance_to(rhit.position) <= o.distance_to(hit.position) + 0.7:
			hit = rhit
	var cam := _cam()
	var target: Vector3 = hit.position if not hit.is_empty() else cam.global_position - cam.global_basis.z * rng
	darts_left -= 1
	var d := _make_dart()
	interior.add_child(d)
	var start := _muzzle()
	d.global_position = start
	darts_in_house.append(d)
	var res: Variant = null
	if not hit.is_empty() and hit.collider and (hit.collider as Node).has_meta("resident"):
		res = (hit.collider as Node).get_meta("resident")
	var g := ES.m(dart_gravity_eh)
	var T := maxf(0.03, start.distance_to(target) / ES.m(dart_speed_eh))
	var v0 := (target - start) / T + Vector3(0, 0.5 * g * T, 0)
	d.set_meta("landed", false)
	_flying.append({"node": d, "start": start, "v0": v0, "t": 0.0, "T": T, "target": target, "res": res,
			"normal": hit.get("normal", Vector3.UP), "g": g})
	_orient(d, v0)
	_refresh_hotbar()


func _orient(d: Node3D, v: Vector3) -> void:
	if v.length() > 0.001:
		d.look_at(d.global_position + v, Vector3.UP if absf(v.normalized().y) < 0.98 else Vector3.FORWARD)


func _update_flying(delta: float) -> void:
	for f in _flying.duplicate():
		var d: Node3D = f.node
		if not is_instance_valid(d):
			_flying.erase(f)
			continue
		f.t = minf(float(f.t) + delta, float(f.T))
		var t := float(f.t)
		var v0: Vector3 = f.v0
		d.global_position = (f.start as Vector3) + v0 * t + Vector3(0, -0.5 * float(f.g) * t * t, 0)
		_orient(d, v0 + Vector3(0, -float(f.g) * t, 0))
		if t >= float(f.T):
			_flying.erase(f)
			d.global_position = f.target
			_dart_landed(d, f.res, f.normal, v0)


func _dart_landed(d: Variant, res: Variant, normal: Variant, vel: Variant = Vector3.ZERO) -> void:
	if not is_instance_valid(d):
		return
	var dart := d as Node3D
	get_tree().create_timer(1.2).timeout.connect(_mark_landed.bind(weakref(dart)))
	if res != null:
		var z := FX.zzz_puff()
		interior.add_child(z)
		z.global_position = dart.global_position + Vector3(0, 0.15, 0)
		FX.burst(z)
		_autofree(z, 3.0)
		res.call("hit_by_dart")
		flash("%s is out cold. Now tuck them back in (and get that dart back)." % res.get("resident_name"), Color(0.7, 0.85, 1.0))
		# the dart pops out and drops off the bed on the side it came from (onto open floor, not
		# under the bed where only a crawl could reach it)
		var floor_y := interior.to_global((res.get("bed_xform") as Transform3D).origin).y - float(res.get("lie_height"))
		var back := -Vector3((vel as Vector3).x, 0, (vel as Vector3).z)
		back = back.normalized() if back.length() > 0.01 else Vector3.FORWARD
		var fall := dart.global_position + Vector3(randf_range(-0.1, 0.1), 0, randf_range(-0.1, 0.1))
		var space := elf.get_world_3d().direct_space_state
		var found := false
		for i in 50:  # nearest open floor, searching outward (the throw's back direction first)
			for k in 12:
				var dir := back.rotated(Vector3.UP, floorf((k + 1) / 2.0) * (TAU / 12.0) * (1 if k % 2 == 0 else -1))
				var p := dart.global_position + dir * (0.05 * i)
				var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, floor_y + 1.2, p.z), Vector3(p.x, floor_y - 0.1, p.z), 4)
				q.hit_from_inside = true  # the bed's collision box reaches up to the headboard
				var h := space.intersect_ray(q)
				if not h.is_empty() and absf((h.position as Vector3).y - floor_y) < 0.03:
					fall = p + dir * 0.12
					found = true
					break
			if found:
				break
		fall.y = floor_y + 0.02
		var tw := create_tween()
		tw.tween_interval(0.5)
		tw.tween_property(dart, "global_position", fall, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(dart, "rotation_degrees", Vector3(0, randf_range(0, 360), 85), 0.5)
		return
	var n := normal as Vector3
	var v := vel as Vector3
	if n.y > 0.7:
		# floor: skid along it (stopping short of anything in the way), lying flat
		var dir := Vector3(v.x, 0, v.z)
		if dir.length() > 0.01:
			dir = dir.normalized()
			var skid := ES.m(dart_skid_eh)
			var from := dart.global_position + Vector3(0, 0.03, 0)
			var q := PhysicsRayQueryParameters3D.create(from, from + dir * skid, 4)
			var h := elf.get_world_3d().direct_space_state.intersect_ray(q)
			if not h.is_empty():
				skid = maxf(0.0, from.distance_to(h.position) - 0.03)
			dart.look_at(dart.global_position + dir, Vector3.UP)
			var end := dart.global_position + dir * skid + Vector3(0, 0.012, 0)
			var tw := create_tween()
			tw.tween_property(dart, "global_position", end, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			return
	dart.global_position += n * 0.01  # stuck in a wall / furniture


func _mark_landed(ref: WeakRef) -> void:
	var dart := ref.get_ref() as Node3D
	if dart:
		dart.set_meta("landed", true)


func _update_magnet_target() -> void:
	var prev := _targeted_dart
	_targeted_dart = null
	if not darts_in_house.is_empty():
		var hit := ray(4 | 32, magnet_range() + float(elf.get("camera_distance")) + 1.0)
		if not hit.is_empty() and (hit.collider as Node).has_meta("dart"):
			var d: Node3D = (hit.collider as Node).get_meta("dart")
			var busy := false
			for p in _pulling:
				busy = busy or p.node == d
			if not busy and d.global_position.distance_to(elf.global_position) <= magnet_range():
				_targeted_dart = d
	if prev != _targeted_dart and prev != null and is_instance_valid(prev):
		prev.get_node("Highlight").visible = false
	if _targeted_dart:
		var hl := _targeted_dart.get_node("Highlight") as MeshInstance3D
		hl.visible = true
		hl.scale = Vector3.ONE * (1.0 + 0.25 * sin(Time.get_ticks_msec() / 120.0))


## Dart Magnet: tug the one dart you're aiming at back to the elf (physics: force / mass, top speed,
## catch distance). One dart at a time.
func magnet_pull() -> void:
	if _targeted_dart == null or not _pulling.is_empty():
		return
	var d := _targeted_dart
	_targeted_dart = null
	(d.get_node("Highlight") as Node3D).visible = false
	darts_in_house.erase(d)
	for f in _flying.duplicate():
		if f.node == d:
			_flying.erase(f)
	# the first tug pops it up off the floor / out of the wall
	var lift := ES.m(magnet_lift_eh)
	_pulling.append({"node": d, "vel": Vector3(0, sqrt(2.0 * 9.8 * lift), 0)})


func magnet_accel() -> float:
	return (magnet_tug_mn / 1000.0) / (dart_mass_g / 1000.0)  # a = F / m  (m/s^2)


func _update_pulling(delta: float) -> void:
	for p in _pulling.duplicate():
		var d: Node3D = p.node
		if not is_instance_valid(d):
			_pulling.erase(p)
			continue
		var to := _muzzle() - d.global_position
		var dist := to.length()
		if dist <= ES.m(magnet_catch_eh):
			_pulling.erase(p)
			_collect_dart(d, true)
			continue
		var vel: Vector3 = p.vel
		vel += to / dist * magnet_accel() * delta
		vel *= 1.0 - minf(0.9, 2.0 * delta)  # air drag keeps it from orbiting
		var vmax := ES.m(magnet_max_speed_eh)
		if vel.length() > vmax:
			vel = vel.normalized() * vmax
		var step := vel * delta
		if step.length() > dist:
			step = to
		d.global_position += step
		p.vel = vel
		_orient(d, -vel)  # tail first, like it's being reeled in


func _collect_dart(d: Node3D, magnet: bool) -> void:
	darts_in_house.erase(d)
	if is_instance_valid(d):
		d.queue_free()
	darts_left = mini(darts_left + 1, darts_per_run)
	flash("Dart recovered%s (%d/%d)" % [" by magnet" if magnet else "", darts_left, darts_per_run], Color(0.6, 1.0, 0.7), 1.5)
	_refresh_hotbar()


# ---- Snore-o-Meter --------------------------------------------------------------------------------

func snore_ping() -> void:
	if snore_cd > 0.0:
		flash("Snore-o-Meter recharging (%.0fs)" % snore_cd, Color(0.8, 0.7, 1.0), 1.2)
		return
	snore_cd = snore_cooldown
	_clear_snore()
	var nf := night_factor()
	var lines := []
	for r in interior.get("residents"):
		if (r as Node3D).global_position.distance_to(elf.global_position) > ES.m(snore_radius_eh):
			continue
		var dpt: float = r.sleep_depth(nf)
		var lab: String = Resident.depth_label(dpt)
		var col := Color(0.4, 1.0, 0.5) if lab == "Deep" else (Color(1, 0.9, 0.3) if lab == "Light" else (Color(1, 0.55, 0.2) if lab == "Restless" else Color(1, 0.2, 0.2)))
		var l := Label3D.new()
		l.text = "%s\n%s  %d%%" % [r.resident_name, lab, int(dpt * 100.0)]
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.font_size = 44
		l.pixel_size = 0.005
		l.outline_size = 10
		l.modulate = col
		interior.add_child(l)
		l.global_position = (r as Node3D).global_position + Vector3(0, 0.9, 0)
		_snore_labels.append(l)
		lines.append("%s: %s" % [r.resident_name, lab])
	flash("Snore-o-Meter:  " + "   ".join(lines), Color(0.85, 0.75, 1.0), snore_show_time)
	get_tree().create_timer(snore_show_time).timeout.connect(_clear_snore)
	_refresh_hotbar()


func _clear_snore() -> void:
	for l in _snore_labels:
		if is_instance_valid(l):
			l.queue_free()
	_snore_labels.clear()


# ---- Tuck Trolley ---------------------------------------------------------------------------------

func _ensure_trolley() -> void:
	if _trolley:
		return
	# The Tuck Trolley: a low motorised dolly, resident-length (they have to lie on it) but only
	# 0.4 eh high, towed behind the tiny elf on a tow bar at hand height. The motor does the work.
	_trolley = Node3D.new()
	_trolley.name = "TuckTrolley"
	var deck := ES.m(trolley_deck_eh)
	var wr := ES.m(trolley_wheel_eh)
	var L := 1.9
	var W := 0.55
	var parent := elf.get_parent() as Node3D
	parent.add_child(_trolley)
	_trolley.set_meta("deck", deck)
	GB.box(_trolley, Vector3(W, 0.025, L), Vector3(0, deck, 0), Color(0.25, 0.6, 0.35))
	GB.box(_trolley, Vector3(W - 0.05, 0.02, L - 0.06), Vector3(0, deck + 0.02, 0), Color(0.95, 0.9, 0.8))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 0.0, 1.0]:
			GB.cylinder(_trolley, wr, wr, 0.025, Vector3(sx * (W * 0.5 - 0.03), wr, sz * (L * 0.5 - 0.12)), Color(0.1, 0.1, 0.1), Vector3(0, 0, 90))
	# motor box with a blinking light at the front, and the tow bar up to the elf's hands
	GB.box(_trolley, Vector3(0.18, 0.07, 0.12), Vector3(0, deck + 0.05, -L * 0.5 + 0.08), Color(0.85, 0.15, 0.15))
	var led := GB.sphere(_trolley, 0.015, Vector3(0.06, deck + 0.095, -L * 0.5 + 0.05), Color(0.3, 1.0, 0.4), 3.0)
	led.name = "Led"
	var gap := ES.m(trolley_gap_eh)
	var hand := ES.m(trolley_handle_eh)
	var bar_len := Vector2(gap + 0.04, hand - deck).length()
	var bar := GB.cylinder(_trolley, 0.006, 0.006, bar_len, Vector3(0, (deck + hand) * 0.5, -L * 0.5 - (gap + 0.04) * 0.5), Color(0.95, 0.15, 0.15),
			Vector3(rad_to_deg(atan2(gap + 0.04, hand - deck)), 0, 0))
	bar.name = "Handle"
	GB.torus(_trolley, 0.004, 0.012, Vector3(0, hand, -L * 0.5 - gap - 0.04), Color(1, 1, 1), Vector3(0, 0, 90))
	for n in _trolley.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = 3


## Keep the dolly trailing behind the elf (towed), blinking.
func _place_trolley() -> void:
	if _trolley == null or not is_instance_valid(_trolley):
		return
	var model: Node3D = elf.get("model")
	var back := model.global_basis.z.normalized()  # model faces -Z, so +Z is behind
	back.y = 0
	back = back.normalized()
	var L := 1.9
	var want := elf.global_position + back * (ES.m(trolley_gap_eh) + 0.04 + L * 0.5)
	_trolley.global_position = _trolley.global_position.lerp(want, 0.25) if _trolley.global_position.distance_to(want) < 1.0 else want
	_trolley.global_position.y = elf.global_position.y
	var fwd := elf.global_position - _trolley.global_position
	fwd.y = 0
	if fwd.length() > 0.01:
		_trolley.look_at(_trolley.global_position + fwd, Vector3.UP)
	var led := _trolley.get_node_or_null("Led") as Node3D
	if led:
		led.visible = int(Time.get_ticks_msec() / 300) % 2 == 0


func _trolley_tick(use_pressed: bool, p_text: String) -> String:
	_ensure_trolley()
	_trolley.visible = true
	_place_trolley()
	if _carrying:
		var bed: Vector3 = (_carrying.get("bed_xform") as Transform3D).origin
		var bed_w := (_carrying.get("interior") as Node3D).to_global(bed)
		if elf.global_position.distance_to(Vector3(bed_w.x, elf.global_position.y, bed_w.z)) < ES.m(tuck_radius_eh):
			if use_pressed:
				tuck()
				return p_text
			return "Click: tuck %s back into bed" % _carrying.get("resident_name")
		return "Wheel %s back to their bed" % _carrying.get("resident_name")
	var r := _nearest_darted()
	if r:
		if use_pressed:
			load_resident(r)
			return p_text
		return "Click: load %s onto the Tuck Trolley" % r.get("resident_name")
	return p_text


func _nearest_darted() -> Node3D:
	for r in interior.get("residents"):
		if int(r.state) == Resident.State.DARTED and (r as Node3D).global_position.distance_to(elf.global_position) < ES.m(load_radius_eh):
			return r
	return null


func load_resident(r: Node3D) -> void:
	_ensure_trolley()
	_trolley.visible = true
	_carrying = r
	r.call("load_on", _trolley)
	flash("Loaded %s onto the Tuck Trolley" % r.get("resident_name"), Color(1, 0.8, 0.4), 1.6)


func tuck() -> void:
	if _carrying == null:
		return
	_carrying.call("tuck_in")
	flash("%s tucked back in. Like nothing ever happened." % _carrying.get("resident_name"), Color(1, 0.85, 0.5))
	_carrying = null


# ---- Fit-Ghost --------------------------------------------------------------------------------------

func _ghost_tick(use_pressed: bool, p_text: String) -> String:
	if present_stack.is_empty():
		return "Sleigh stack is empty"
	var spots: Array = interior.get("present_spots")
	var tree_w := interior.to_global(interior.get("tree_pos"))
	if tree_w.distance_to(elf.global_position) > ES.m(ghost_range_eh) + 1.0:
		return p_text if p_text != "" else "Fit-Ghost: go to the tree"
	var pts := []
	for sp in spots:
		pts.append(interior.to_global(sp.pos))
	var i := aimed(pts, 0.45, ES.m(ghost_range_eh) + 1.0)
	if i < 0:
		var best := INF
		for k in pts.size():
			var dd := (pts[k] as Vector3).distance_to(elf.global_position)
			if dd < best:
				best = dd
				i = k
	_ghost_spot = i
	var piece: String = present_stack[0]
	if _ghost == null:
		_ghost = MeshInstance3D.new()
		var gm := ShaderMaterial.new()
		gm.shader = GHOST
		_ghost.material_override = gm
		_ghost.layers = 3
		_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		interior.add_child(_ghost)
	_ghost.mesh = Furn.mesh_of(piece)
	_ghost.visible = true
	_ghost.global_position = pts[i]
	_ghost.rotation.y = Time.get_ticks_msec() / 2000.0
	_ghost.scale = Vector3.ONE * present_scale
	var sz := Furn.size_of(piece) * present_scale
	var foot := maxf(sz.x, sz.z)
	_ghost_fits = not bool(spots[i].taken) and foot <= float(spots[i].cap) + 0.02
	(_ghost.material_override as ShaderMaterial).set_shader_parameter("color", Color(0.2, 1.0, 0.4) if _ghost_fits else Color(1.0, 0.2, 0.15))
	if use_pressed:
		place_present()
		return p_text
	return "Fit-Ghost (%s present): %s   Click to place" % [_present_name(piece), "FITS" if _ghost_fits else "won't fit, it'd knock things over!"]


func place_present() -> void:
	if _ghost_spot < 0 or present_stack.is_empty():
		return
	var spots: Array = interior.get("present_spots")
	var sp: Dictionary = spots[_ghost_spot]
	var w := interior.to_global(sp.pos)
	if not _ghost_fits:
		# knock a bauble off: noise
		var b := GB.sphere(interior, 0.055, interior.to_local(w + Vector3(0, 1.0, 0)), Color(0.9, 0.1, 0.12))
		b.layers = 2
		var tw := create_tween()
		tw.tween_property(b, "position", interior.to_local(w + Vector3(0.3, 0.05, 0.2)), 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		for r in interior.get("residents"):
			if int(r.state) == Resident.State.ASLEEP:
				r.awareness += bauble_noise
		make_noise(w, ES.m(20.0), "bauble smash")
		flash("CRASH! A bauble hit the floor. Wrong spot.", Color(1, 0.4, 0.3))
		return
	var piece: String = present_stack.pop_front()
	var mi := Furn.spawn(piece, interior, sp.pos, randf_range(0, 90), true, present_scale)
	mi.layers = 2
	sp.taken = true
	presents_placed += 1
	presents_placed_here += 1
	sp["ours"] = true
	var g := FX.glitter()
	interior.add_child(g)
	g.global_position = w + Vector3(0, 0.25, 0)
	FX.burst(g)
	_autofree(g, 3.0)
	flash("Present placed under the tree!", Color(0.5, 1.0, 0.6))
	_refresh_hotbar()


# ---- Puff-Possum ------------------------------------------------------------------------------------

func _puff_tick(use_pressed: bool, p_text: String) -> String:
	var st: Array = interior.get("stockings")
	var pts := []
	for s in st:
		pts.append((s as Node3D).global_position + Vector3(0, -0.25, 0))
	var i := aimed(pts, 0.3, ES.m(stocking_range_eh))
	if i < 0:
		return p_text if p_text != "" else "Puff-Possum: aim at a stocking"
	var s: Node3D = st[i]
	if not bool(s.get_meta("puffed")):
		if use_pressed:
			puff_stocking(s)
			return p_text
		return "Click: puff the stocking open"
	if not bool(s.get_meta("filled")):
		if use_pressed:
			fill_stocking(s)
			return p_text
		return "Click: fill the stocking"
	return "Stocking's full"


func puff_stocking(s: Node3D) -> void:
	s.set_meta("puffed", true)
	var tw := create_tween()
	tw.tween_property(s, "scale", Vector3(1.45, 1.1, 1.45), 0.15).set_trans(Tween.TRANS_BACK)
	tw.tween_property(s, "scale", Vector3(1.25, 1.05, 1.25), 0.3)
	var p := FX.make("blob", 14, 0.8, 0.18, [Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.0)],
			{"one_shot": true, "explosive": 0.9, "spread": 70.0, "vmin": 0.5, "vmax": 1.2, "damp": 2.0})
	interior.add_child(p)
	p.global_position = s.global_position
	FX.burst(p)
	_autofree(p, 2.0)


func fill_stocking(s: Node3D) -> void:
	s.set_meta("filled", true)
	stockings_filled += 1
	stockings_filled_here += 1
	var cane := GB.cylinder(s, 0.012, 0.012, 0.22, Vector3(0.02, 0.06, 0), Color(0.95, 0.1, 0.1), Vector3(0, 0, 12))
	cane.layers = 2
	var toy := GB.box(s, Vector3(0.09, 0.09, 0.09), Vector3(-0.04, 0.02, 0.02), Color(0.3, 0.6, 1.0), Vector3(10, 20, 0))
	toy.layers = 2
	var g := FX.glitter()
	interior.add_child(g)
	g.global_position = s.global_position + Vector3(0, 0.05, 0)
	FX.burst(g)
	_autofree(g, 3.0)
	flash("Stocking filled!", Color(1, 0.6, 0.8), 1.6)


# ---- The Ledger -------------------------------------------------------------------------------------

func _ledger_tick(use_pressed: bool, p_text: String) -> String:
	var door: Node3D = interior.get("kid_door")
	if door == null:
		return p_text
	if aimed([door.global_position], 0.35, ES.m(ledger_range_eh)) < 0:
		return p_text if p_text != "" else "The Ledger: scan a kid's bedroom door"
	if use_pressed:
		scan_ledger()
		return p_text
	return "Click: scan %s's door with The Ledger" % interior.get("kid_name")


func scan_ledger() -> void:
	var nice := bool(interior.get("kid_nice"))
	var kid := str(interior.get("kid_name"))
	ledger_result = "%s: %s" % [kid, "NICE" if nice else "NAUGHTY"]
	flash("THE LEDGER  -  %s is %s" % [kid.to_upper(), "NICE  ✓  (bike tagged)" if nice else "NAUGHTY  ✗  (lump of coal)"],
			Color(0.4, 1.0, 0.5) if nice else Color(1.0, 0.35, 0.3), 3.5)
	var door: Node3D = interior.get("kid_door")
	var l := Label3D.new()
	l.text = "NICE" if nice else "NAUGHTY"
	l.modulate = Color(0.4, 1.0, 0.5) if nice else Color(1, 0.3, 0.25)
	l.font_size = 64
	l.pixel_size = 0.004
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(0, 0.35, 0)
	l.outline_size = 10
	door.add_child(l)


# ---- Fireplace Icer + Fire Launcher + burst pipes ----------------------------------------------------

func _fireplace_w() -> Vector3:
	return house.to_global(interior.get("fireplace_spawn")) + Vector3(0, 0.35, 0)


func _ensure_frost(parent: Node3D) -> void:
	if _frost and is_instance_valid(_frost):
		if _frost.get_parent() != parent:
			_frost.reparent(parent, false)
		return
	var c := Color(0.75, 0.95, 1.0)
	_frost = FX.make("flake", 80, 0.8, 0.1, [Color(c, 0.0), Color(1, 1, 1, 1), Color(c, 0.6), Color(c, 0.0)],
			{"dir": Vector3(0, 0, -1), "spread": 10.0, "vmin": 3.0, "vmax": 5.0, "damp": 1.0, "add": true, "spin": 140.0,
			"scale_curve": [Vector2(0, 0.5), Vector2(1, 1.4)]})
	parent.add_child(_frost)


func _icer_tick(delta: float, held: bool, p_text: String) -> String:
	var fw := _fireplace_w()
	var in_range := fw.distance_to(elf.global_position) < ES.m(icer_range_eh) and aimed([fw], 0.6, ES.m(icer_range_eh)) >= 0
	if not in_range:
		return p_text if p_text != "" else "Fireplace Icer: aim at the fireplace and hold"
	if held:
		_ensure_frost(interior)
		_frost.global_position = _muzzle()
		_frost.look_at(fw, Vector3.UP)
		_frost.emitting = true
		apply_icer(delta)
	return "Hold: Fireplace Icer   (freeze %.0f%%)" % (100.0 * float(interior.get("freeze_meter")) / fire_freeze_at)


## Add freeze. Puts a lit fire out at fire_freeze_at; overuse frosts, cracks and bursts the pipes.
func apply_icer(delta: float, h: Node3D = null) -> void:
	if h == null:
		h = house
	var it: Node3D = h.get("interior")
	icing = true
	var m := float(it.get("freeze_meter")) + icer_rate * delta
	it.set("freeze_meter", m)
	if bool(h.get("fire_lit")) and m >= fire_freeze_at:
		it.set("fire_was_lit", true)
		h.call("freeze_fire")
		var st := FX.steam(30)
		st.one_shot = true
		st.explosiveness = 0.6
		h.add_child(st)
		st.global_position = h.to_global(it.get("fireplace_spawn")) + Vector3(0, 0.3, 0)
		FX.burst(st)
		_autofree(st, 4.0)
		var top := FX.steam(20)
		top.one_shot = true
		h.add_child(top)
		top.global_position = h.call("get_chimney_top_world")
		FX.burst(top)
		_autofree(top, 4.0)
		flash("Hssss... fire's out. Ice crystals in the grate.", Color(0.7, 0.95, 1.0))
	_icer_house = h


var _icer_house: Node3D


func _update_pipes_all(delta: float) -> void:
	for h in (mission.get("houses") if mission else []):
		var it: Node3D = h.get("interior")
		if it == null:
			continue
		var m := float(it.get("freeze_meter"))
		if not (icing and _icer_house == h):
			m = maxf(0.0, m - icer_decay * delta)
			it.set("freeze_meter", m)
		_update_pipes(h, it, m, delta)
	icing = false


func _update_pipes(h: Node3D, it: Node3D, m: float, delta: float) -> void:
	for p in it.get("pipes"):
		var mat: ShaderMaterial = p.mat
		var st := int(p.state)
		var pm := m * float(p.get("exposure", 1.0))
		var f := 1.0 if st >= 1 else clampf((pm - pipe_frost_start) / (pipe_crack_at - pipe_frost_start), 0.0, 1.0)
		mat.set_shader_parameter("albedo", (p.base as Color).lerp(Color(0.85, 0.95, 1.0), f))
		mat.set_shader_parameter("emission_energy", 0.35 * f)
		if st == 0 and pm >= pipe_crack_at:
			_crack(h, it, p)
		elif st == 1:
			p.timer = float(p.get("timer", 0.0)) + delta
			if pm >= pipe_burst_at or float(p.timer) >= crack_burst_delay:
				_burst(h, it, p)
		elif st == 2:
			var pud: MeshInstance3D = p.puddle
			var r := minf(puddle_max_radius, pud.scale.x + puddle_max_radius / puddle_grow_time * delta)
			pud.scale = Vector3(r, 1, r)


func _crack(h: Node3D, it: Node3D, p: Dictionary) -> void:
	p.state = 1
	p.timer = 0.0
	for c in p.cracks:
		(c as Node3D).visible = true
	var hiss := FX.steam(10)
	hiss.amount = 8
	it.add_child(hiss)
	hiss.position = p.spray_pos
	p.hiss = hiss
	if active and house == h:
		flash("CRACK! A frozen pipe split. Thaw it with the Fire Launcher before it bursts!", Color(1, 0.6, 0.3), 3.5)


func _burst(h: Node3D, it: Node3D, p: Dictionary) -> void:
	p.state = 2
	var spray := FX.water_spray()
	it.add_child(spray)
	spray.position = p.spray_pos
	spray.look_at_from_position(spray.global_position, spray.global_position + (p.dir as Vector3), Vector3.UP)
	spray.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
	p.spray = spray
	var pud: MeshInstance3D = p.puddle
	pud.visible = true
	pud.scale = Vector3(0.15, 1, 0.15)
	var bang := Label3D.new()
	bang.text = "BANG!  hsssssss"
	bang.font_size = 72
	bang.pixel_size = 0.005
	bang.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bang.modulate = Color(1, 0.9, 0.3)
	bang.outline_size = 12
	bang.no_depth_test = true
	it.add_child(bang)
	bang.position = (p.spray_pos as Vector3) + Vector3(0, 0.5, 0)
	var tw := create_tween()
	tw.tween_property(bang, "position", bang.position + Vector3(0, 0.5, 0), 2.0)
	tw.parallel().tween_property(bang, "modulate:a", 0.0, 2.0)
	tw.tween_callback(bang.queue_free)
	var wp := it.to_global(p.spray_pos)
	for r in it.get("residents"):
		if (r as Node3D).global_position.distance_to(wp) < burst_wake_radius:
			r.base_depth *= 0.5
			r.awareness += 0.8
			if r.awareness >= 1.0:
				r.call("wake")
	print("[gadget] pipe burst in %s" % h.name)
	if active and house == h:
		flash("BANG! A pipe burst! Water everywhere (slippery) and the house is stirring.", Color(1, 0.4, 0.3), 3.5)


func _relight_tick(use_pressed: bool, p_text: String) -> String:
	# thaw a cracked pipe first (aimed), else relight the fire
	var pipes: Array = interior.get("pipes")
	var pts := []
	for p in pipes:
		pts.append(interior.to_global(p.spray_pos))
	var pi := aimed(pts, 0.5, ES.m(thaw_range_eh))
	if pi >= 0 and int(pipes[pi].state) == 1:
		if use_pressed:
			thaw_pipe(pipes[pi])
			return p_text
		return "Click: Fire Launcher - thaw the cracked pipe"
	var fw := _fireplace_w()
	if aimed([fw], 0.6, ES.m(relight_range_eh)) < 0:
		return p_text if p_text != "" else "Fire Launcher: aim at the fireplace"
	if bool(house.get("fire_lit")):
		return "The fire's burning"
	if not bool(interior.get("fire_was_lit")):
		return "This fireplace wasn't lit, leave it cold"
	if use_pressed:
		relight()
		return p_text
	return "Click: Fire Launcher - relight the fire so nobody notices"


func relight() -> void:
	house.call("set_fire", true)
	interior.set("freeze_meter", 0.0)
	var b := FX.flame_burst()
	house.add_child(b)
	b.global_position = _fireplace_w() - Vector3(0, 0.25, 0)
	FX.burst(b)
	_autofree(b, 2.0)
	var e := FX.embers(Vector3(0.3, 0.1, 0.2), 30)
	e.one_shot = true
	e.explosiveness = 0.8
	house.add_child(e)
	e.global_position = b.global_position
	FX.burst(e)
	_autofree(e, 2.5)
	flash("WHOOMPH! Fire relit, nobody will ever know.", Color(1, 0.6, 0.25))


func thaw_pipe(p: Dictionary) -> void:
	p.state = 0
	p.timer = 0.0
	for c in p.cracks:
		(c as Node3D).visible = false
	if p.get("hiss") and is_instance_valid(p.hiss):
		(p.hiss as Node).queue_free()
	interior.set("freeze_meter", minf(float(interior.get("freeze_meter")), pipe_frost_start * 0.5))
	var b := FX.flame_burst()
	b.amount = 16
	interior.add_child(b)
	b.position = p.spray_pos
	FX.burst(b)
	_autofree(b, 2.0)
	flash("Pipe thawed. Phew.", Color(1, 0.75, 0.4))


func _update_meter() -> void:
	var h := house if active else _icer_house
	if h == null or h.get("interior") == null:
		meter_root.visible = false
		return
	var m := float((h.get("interior") as Node).get("freeze_meter"))
	meter_root.visible = m > 0.01
	meter_fill.size.x = 400.0 * clampf(m / pipe_burst_at, 0.0, 1.0)
	meter_fill.color = Color(0.6, 0.9, 1.0) if m < pipe_frost_start else (Color(1, 0.8, 0.3) if m < pipe_crack_at else Color(1, 0.3, 0.2))
	var txt := "FREEZE"
	if m >= fire_freeze_at:
		txt += "  -  fire out"
	if m >= pipe_frost_start:
		txt += "  -  PIPES FROSTING, STOP!"
	meter_label.text = txt


# ---- Glow-Gogs --------------------------------------------------------------------------------------

func _set_goggles(on: bool, announce := true) -> void:
	goggles = on
	nv_rect.visible = on and active
	get_tree().call_group("nv_glow", "set_visible", on)
	for r in (interior.get("residents") if interior else []):
		r.call("set_glow", on)
	if elf:
		var gl: OmniLight3D = elf.get("goggle_light")
		if gl:
			gl.light_energy = float(elf.get("goggle_light_energy")) * (2.5 if on else 1.0)
	if announce and active:
		flash("Glow-Gogs %s%s" % ["ON" if on else "off", "  (residents notice you %d%% faster)" % int((goggles_notice_mult - 1.0) * 100.0) if on else ""], Color(0.5, 1.0, 0.5), 1.8)


func _build_nv_markers() -> void:
	var pts := []
	for s in interior.get("stockings"):
		pts.append((s as Node3D).global_position + Vector3(0, -0.2, 0))
	if interior.get("kid_door"):
		pts.append((interior.get("kid_door") as Node3D).global_position)
	pts.append(_fireplace_w())
	for sp in interior.get("present_spots"):
		if not bool(sp.taken):
			pts.append(interior.to_global(sp.pos) + Vector3(0, 0.05, 0))
	for p in interior.get("pipes"):
		pts.append(interior.to_global(p.spray_pos))
	for p in pts:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.1
		sm.height = 0.2
		m.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.7, 1.0, 0.6, 0.5)
		mat.no_depth_test = true
		m.material_override = mat
		m.layers = 3
		interior.add_child(m)
		m.global_position = p
		m.visible = goggles
		m.add_to_group("nv_glow")
		_nv_markers.append(m)


func _autofree(n: Node, t: float) -> void:
	get_tree().create_timer(t).timeout.connect(n.queue_free)
