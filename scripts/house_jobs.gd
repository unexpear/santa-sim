extends Node
## Per-house delivery objectives (the house is complete only when all are done):
##   - presents under the tree (Fit-Ghost) and stockings filled (Puff-Possum), as before
##   - Santa's snacks: eat the cookies + drink the milk, and take the carrot (+ the beer) for the
##     reindeer. By hand (E: a short eat / drink, the crunch is NOISE) or with the Snack-Vac
##     (hold K: slower, silent). The plate is left with crumbs, the glass empty, and a note.
##   - Santa's sooty boot prints (J: Soot Boots): a continuous trail that STARTS AT THE HEARTH and
##     reaches the cookies, the tree and the stockings in any order. Prints are Santa-sized decals
##     at a Santa stride along the elf's real path. The boots hold soot for so many prints; step
##     back on the hearth to re-soot. A gap (climbing, a rope ride, boots off and wandering) breaks
##     the trail: prints laid away from it don't count until you resume within a stride of the
##     last good print.
## All sizes are Santa's (a 1.8 m man), not the elf's: that's the point of the prints.

const ES := preload("res://scripts/elf_size.gd")
const PM := preload("res://scripts/mech/part_models.gd")
const GB := preload("res://scripts/greybox.gd")

@export_group("Snacks")
@export var eat_time := 2.2  ## by hand: crunch crunch, glug
@export var vac_time := 4.5  ## Snack-Vac: slower but silent
@export var crunch_noise_eh := 16.0  ## by hand: crunch radius, eh (3.5 m) -> resident restlessness
@export var vac_noise_eh := 1.5  ## Snack-Vac: a faint hum, eh
@export_group("Soot Boots (Santa sizes, metres)")
@export var santa_stride := 0.72  ## one boot print every this far along the path
@export var boot_length := 0.32
@export var boot_width := 0.13
@export var boot_spread := 0.11  ## left / right offset from the path line
@export var soot_prints := 26  ## prints per sooting; re-soot on the hearth
@export var target_reach := 1.0  ## a print this close to the cookies / tree / stockings counts
@export var hearth_start_reach := 1.0  ## the first print must be this close to the hearth
@export var break_gap_strides := 1.7  ## a gap longer than this many strides breaks the trail

var gadgets: Node
var elf: CharacterBody3D
var house: Node3D
var interior: Node3D

var cookies_done := false
var milk_done := false
var carrot_done := false
var snack_method := ""  ## "hand" / "vac"
var boots_on := false
var soot_left := 0
var trail: Array = []  ## Vector3 world positions of the valid (hearth-rooted) trail prints
var stray_prints := 0
var reached := {"cookies": false, "tree": false, "stockings": false}
var trail_started := false
var trail_broken := false
var _last_stamp := Vector3.INF  ## where the last print (valid or stray) went down
var _dist_acc := 0.0
var _prev_pos := Vector3.INF
var _left := true
var _eating := 0.0
var _eat_target: Node3D
var _eat_mode := ""
var _prints_root: Node3D
var _boot_tex: Texture2D
var _was_complete := false

signal noise(pos: Vector3, radius: float, what: String)


func begin(h: Node3D, e: CharacterBody3D, g: Node) -> void:
	house = h
	elf = e
	gadgets = g
	interior = h.get("interior")
	var st: Dictionary = interior.get_meta("jobs_state", {})
	cookies_done = st.get("cookies", false)
	milk_done = st.get("milk", false)
	carrot_done = st.get("carrot", false)
	boots_on = false
	soot_left = 0
	_prev_pos = Vector3.INF
	_dist_acc = 0.0
	_was_complete = is_complete()
	if _prints_root == null or not is_instance_valid(_prints_root):
		_prints_root = interior.get_node_or_null("SantaPrints") as Node3D
		if _prints_root == null:
			_prints_root = Node3D.new()
			_prints_root.name = "SantaPrints"
			interior.add_child(_prints_root)


func end() -> void:
	interior.set_meta("jobs_state", {"cookies": cookies_done, "milk": milk_done, "carrot": carrot_done})
	boots_on = false


func reset_trail() -> void:
	trail.clear()
	stray_prints = 0
	trail_started = false
	trail_broken = false
	_last_stamp = Vector3.INF
	reached = {"cookies": false, "tree": false, "stockings": false}
	if _prints_root:
		for c in _prints_root.get_children():
			c.queue_free()


func reset_snacks() -> void:
	cookies_done = false
	milk_done = false
	carrot_done = false
	for c in interior.get_children():
		if c.has_meta("eaten_marker"):
			c.queue_free()
		elif c is MeshInstance3D and str(c.get_meta("piece", "")) in ["CookiesMilk", "BeerCarrot"]:
			(c as Node3D).visible = true


# --- targets -----------------------------------------------------------------------------------------

func _snack(piece: String) -> Node3D:
	for c in interior.get_children():
		if c is MeshInstance3D and str(c.get_meta("piece", "")) == piece:
			return c
	return null


func hearth_w() -> Vector3:
	return interior.to_global(interior.get("hearth_point"))


func targets() -> Dictionary:
	var out := {}
	var ck := _snack("CookiesMilk")
	if ck:
		out["cookies"] = ck.global_position
	out["tree"] = interior.to_global(interior.get("tree_pos"))
	var st: Array = interior.get("stockings")
	if not st.is_empty():
		var c := Vector3.ZERO
		for s: Node3D in st:
			c += s.global_position
		c /= st.size()
		out["stockings"] = c
	return out


# --- snacks ------------------------------------------------------------------------------------------

func busy() -> bool:
	return _eating > 0.0


## E at the snacks (by hand) or hold K (Snack-Vac). Returns true if it started.
func start_eat(sn: Node3D, mode: String) -> bool:
	if sn == null or busy():
		return false
	var piece := str(sn.get_meta("piece", ""))
	if piece == "CookiesMilk" and cookies_done and milk_done:
		return false
	if piece == "BeerCarrot" and carrot_done:
		return false
	_eat_target = sn
	_eat_mode = mode
	_eating = eat_time if mode == "hand" else vac_time
	if mode == "hand":
		elf.set("control_enabled", false)
		elf.set("pose", "peek")
	var r := ES.m(crunch_noise_eh if mode == "hand" else vac_noise_eh)
	noise.emit(sn.global_position, r, "crunch" if mode == "hand" else "snack-vac hum")
	return true


func _finish_eat() -> void:
	var sn := _eat_target
	_eat_target = null
	if mode_hand():
		elf.set("control_enabled", true)
		elf.set("pose", "")
	snack_method = _eat_mode
	if sn == null or not is_instance_valid(sn):
		return
	var piece := str(sn.get_meta("piece", ""))
	var base := sn.position
	sn.visible = false
	if piece == "CookiesMilk":
		cookies_done = true
		milk_done = true
		_leftovers(base, true)
		gadgets.call("flash", "Cookies eaten, milk drunk%s" % ("  (Snack-Vac: silent)" if _eat_mode == "vac" else "  (crunch!)"), Color(1.0, 0.9, 0.6), 2.2)
	else:
		carrot_done = true
		_leftovers(base, false)
		gadgets.call("flash", "Carrot (and the beer) packed for the reindeer", Color(1.0, 0.85, 0.5), 2.2)
	_eat_mode = ""


func mode_hand() -> bool:
	return _eat_mode == "hand"


## What's left: a plate of crumbs, an empty glass with a milk film, a thank-you note (cookies);
## a bitten carrot top and an empty stubby (beer + carrot).
func _leftovers(at: Vector3, cookies: bool) -> void:
	var root := Node3D.new()
	root.set_meta("eaten_marker", true)
	root.position = at
	interior.add_child(root)
	if cookies:
		if PM.add(root, "CookiePlate", Vector3.ZERO, Vector3(0, 20, 0)) == null:
			GB.cylinder(root, 0.11, 0.1, 0.012, Vector3(0, 0.006, 0), Color(0.95, 0.95, 0.92))
			var rng := RandomNumberGenerator.new()
			rng.seed = 77
			for k in 14:
				GB.sphere(root, rng.randf_range(0.004, 0.009), Vector3(rng.randf_range(-0.07, 0.07), 0.015, rng.randf_range(-0.07, 0.07)), Color(0.62, 0.4, 0.2), 0.0, Vector3(1, 0.6, 1))
		var glass := PM.add(root, "MilkGlassEmpty", Vector3(0.15, 0, 0.02))
		if glass == null:
			glass = GB.cylinder(root, 0.034, 0.03, 0.12, Vector3(0.15, 0.06, 0.02), Color(0.85, 0.92, 1.0))
			GB.cylinder(root, 0.031, 0.031, 0.008, Vector3(0.15, 0.006, 0.02), Color(0.98, 0.98, 0.95))  # milk film
		glass.transparency = 0.45
		var note := Label3D.new()
		note.text = "Thanks!\n- S"
		note.font_size = 28
		note.pixel_size = 0.0018
		note.modulate = Color(0.25, 0.12, 0.08)
		note.outline_size = 0
		note.position = Vector3(-0.12, 0.004, 0.05)
		note.rotation_degrees = Vector3(-90, 15, 0)
		root.add_child(note)
		GB.box(root, Vector3(0.09, 0.002, 0.07), Vector3(-0.12, 0.002, 0.05), Color(1.0, 0.98, 0.9))
	else:
		GB.cylinder(root, 0.012, 0.018, 0.04, Vector3(0, 0.02, 0), Color(0.95, 0.5, 0.12), Vector3(90, 0, 0))
		GB.cylinder(root, 0.03, 0.03, 0.12, Vector3(0.1, 0.06, 0), Color(0.45, 0.3, 0.12))
	for n in root.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = 2


# --- soot boots ---------------------------------------------------------------------------------------

func toggle_boots() -> void:
	boots_on = not boots_on
	if boots_on and soot_left <= 0 and _on_hearth(elf.global_position):
		soot_left = soot_prints
	gadgets.call("flash", ("Soot Boots ON  (%d prints of soot)" % soot_left) if boots_on else "Soot Boots off", Color(0.85, 0.85, 0.85), 1.6)
	_prev_pos = Vector3.INF
	_dist_acc = 0.0


func _on_hearth(p: Vector3) -> bool:
	var hp := hearth_w()
	return Vector2(p.x - hp.x, p.z - hp.z).length() < hearth_start_reach and absf(p.y - hp.y) < 0.4


func tick(delta: float) -> void:
	if _eating > 0.0:
		_eating -= delta
		if _eat_target and is_instance_valid(_eat_target):
			elf.call("face", _eat_target.global_position - elf.global_position)
		if _eating <= 0.0:
			_finish_eat()
	if not boots_on or elf == null:
		return
	var p := elf.global_position
	if _on_hearth(p):
		soot_left = soot_prints  # standing in the ash re-soots the boots
	if not elf.is_on_floor() or bool(elf.get("ext_control")):
		_prev_pos = Vector3.INF  # climbing / ropes / jumping: no prints (and a gap)
		return
	if _prev_pos == Vector3.INF:
		_prev_pos = p
		if _last_stamp == Vector3.INF or (not trail_started and _on_hearth(p)):
			_stamp(p, Vector3.ZERO)  # the first print goes down right here
		return
	var step := Vector2(p.x - _prev_pos.x, p.z - _prev_pos.z).length()
	if step > santa_stride * break_gap_strides:
		_prev_pos = p  # teleported / dragged: a gap
		return
	_dist_acc += step
	var dir := (p - _prev_pos)
	dir.y = 0
	_prev_pos = p
	if _dist_acc >= santa_stride:
		_dist_acc = 0.0
		_stamp(p, dir.normalized() if dir.length() > 0.0001 else Vector3.ZERO)


func _stamp(p: Vector3, dir: Vector3) -> void:
	if soot_left <= 0:
		if boots_on:
			gadgets.call("flash", "Out of soot: step back on the hearth", Color(0.9, 0.8, 0.7), 1.2)
		return
	if dir == Vector3.ZERO:  # first print: pointing out of the fireplace
		dir = p - interior.to_global(interior.get("fireplace_spawn"))
		dir.y = 0
		dir = dir.normalized() if dir.length() > 0.01 else interior.global_basis.z
	soot_left -= 1
	# a valid print: the trail is empty and we're on the hearth, or we're within the gap rule of the
	# last valid print
	var valid := false
	if trail.is_empty():
		valid = _on_hearth(p)
	else:
		valid = Vector2(p.x - trail[-1].x, p.z - trail[-1].z).length() <= santa_stride * break_gap_strides
	if valid:
		trail.append(p)
		trail_started = true
		var tg := targets()
		for key in tg:
			var t: Vector3 = tg[key]
			if Vector2(p.x - t.x, p.z - t.z).length() < target_reach:
				if not reached[key]:
					reached[key] = true
					gadgets.call("flash", "Boot prints reach the %s" % key, Color(0.85, 0.85, 0.85), 1.2)
	else:
		stray_prints += 1
		if trail_started:
			trail_broken = true
	_last_stamp = p
	_place_print(p, dir, valid)


func _place_print(p: Vector3, dir: Vector3, valid: bool) -> void:
	if _boot_tex == null:
		_boot_tex = _make_boot_texture()
	var side := dir.cross(Vector3.UP).normalized()
	var off := side * boot_spread * (1.0 if _left else -1.0)
	_left = not _left
	var d := Decal.new()
	d.texture_albedo = _boot_tex
	d.size = Vector3(boot_width, 0.12, boot_length)
	d.modulate = Color(0.08, 0.07, 0.07, 0.85 if valid else 0.55)
	d.cull_mask = 2
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	_prints_root.add_child(d)
	d.global_position = p + off + Vector3(0, 0.02, 0)
	d.global_basis = Basis.looking_at(-dir if dir.length() > 0.01 else Vector3.FORWARD, Vector3.UP)
	d.set_meta("valid", valid)


## A chunky boot sole (heel + tread) drawn into a small texture once.
func _make_boot_texture() -> Texture2D:
	var w := 64
	var h := 160
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			var u := (x + 0.5) / w * 2.0 - 1.0
			var v := (y + 0.5) / h
			var a := 0.0
			# sole (front 0..0.62) and heel (0.7..1) with a waist between
			if v < 0.62:
				var ww := 0.92 - pow((0.3 - v) / 0.32, 2.0) * 0.5
				if absf(u) < ww:
					a = 1.0
			elif v > 0.7:
				if absf(u) < 0.72 and v < 0.98:
					a = 1.0
			# tread bars
			if a > 0.0 and fmod(v * 22.0, 1.0) < 0.28:
				a = 0.35
			if a > 0.0:
				var n := fmod(sin(x * 12.9898 + y * 78.233) * 43758.5453, 1.0)
				a *= 0.75 + 0.25 * absf(n)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


# --- checklist ----------------------------------------------------------------------------------------

func footprints_ok() -> bool:
	return trail_started and reached.cookies and reached.tree and reached.stockings


func snacks_ok() -> bool:
	return cookies_done and milk_done and carrot_done


func is_complete() -> bool:
	if gadgets == null:
		return false
	return int(gadgets.get("presents_placed_here")) > 0 and int(gadgets.get("stockings_filled_here")) >= 1 and snacks_ok() and footprints_ok()


func checklist_text() -> String:
	var ck := func(b: bool) -> String: return "[x]" if b else "[ ]"
	var t := "HOUSE JOBS\n"
	t += "%s Presents under the tree\n" % ck.call(int(gadgets.get("presents_placed_here")) > 0)
	t += "%s Stocking filled\n" % ck.call(int(gadgets.get("stockings_filled_here")) >= 1)
	t += "%s Cookies  %s Milk  %s Carrot\n" % [ck.call(cookies_done), ck.call(milk_done), ck.call(carrot_done)]
	t += "%s Santa's prints (J): hearth %s cookies %s tree %s stockings %s%s" % [ck.call(footprints_ok()), "+" if trail_started else "-",
			"+" if reached.cookies else "-", "+" if reached.tree else "-", "+" if reached.stockings else "-",
			("   soot %d" % soot_left) if boots_on else ""]
	if trail_broken and not footprints_ok():
		t += "\n   trail broken: resume next to your last print"
	if is_complete():
		t += "\nHOUSE COMPLETE - back up the chimney"
	return t
