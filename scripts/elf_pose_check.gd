extends "res://scripts/checks.gd"
## --bootcheck=dir : the elf's boots and lower legs never pass through its torso, in every stance
## and pose: stand, walk cycle, sneak lean, tactical crouch (+ walking), crawl / lying prone
## (+ crawling), and the scripted poses peek, flip, abseil (also used upside down on the rope),
## hang, zip, climb (whole cycle), mantle, grate_peek. Runs headless (pure transform maths on the
## rig pivots + the modelled tube / ellipsoid sizes from build_models.py).
## Windowed it also saves elf_boots_fix (side view: crawl, crouch, stand; before / after).

const Elf := preload("res://scripts/elf.gd")
const MODEL := preload("res://assets/models/elf.glb")
const ORIGIN := Vector3(0, 400, 0)

# torso metaball ellipsoids, Hips-local model units (centre, semi-axes)
const TORSO := [[Vector3(0, 0.09, 0), Vector3(0.07, 0.1, 0.055)], [Vector3(0, 0.01, 0), Vector3(0.065, 0.05, 0.052)]]


## Shoe + lower-leg sample spheres in leg-pivot-local model units: [centre, radius].
static func _leg_samples(s: float) -> Array:
	var out := []
	var shoe := [[Vector3(0.04, 0.02, -(-0.02)), 0.022], [Vector3(0.04, 0.018, -0.03), 0.0167], [Vector3(0.04, 0.03, -0.07), 0.0103], [Vector3(0.04, 0.06, -0.075), 0.0044]]
	for e in shoe:
		var p: Vector3 = e[0]
		out.append([Vector3(s * 0.005, p.y - 0.17, p.z), float(e[1])])
	for i in 4:  # mid-shin down to the ankle (the thigh legitimately joins the body at the hip)
		var t := 0.35 + i * 0.2
		var a := Vector3(0, 0.1 - 0.17, -0.005)
		var b := Vector3(0, 0.03 - 0.17, 0.0)
		out.append([Vector3(s * 0.005, 0, 0) + a.lerp(b, t), 0.019])
	return out


func boot_check(m: Node3D, d: String) -> void:
	_init_check(m, d)
	await _wait(0.5)
	var e := elf
	if e == null:
		fail("no elf")
		m.get_tree().quit()
		return
	e.set("ext_control", true)
	var poses := _pose_list(e)
	var worst := 0.0
	var worst_name := ""
	var bad := 0
	for p in poses:
		var depth := _measure(e, p)
		var mm := depth * (ES.ELF_HEIGHT / ES.MODEL_HEIGHT) * 1000.0
		if mm > worst:
			worst = mm
			worst_name = str(p.name)
		if mm > 1.0:
			bad += 1
			fail("boots/shins inside the torso in %s: %.1f mm" % [p.name, mm])
	print("[boots] %d poses, worst boot-vs-torso overlap %.2f mm (%s)" % [poses.size(), worst, worst_name if worst_name != "" else "-"])
	# legacy pose for the record (what the designer saw)
	Elf.legacy_legs = true
	var old := _measure(e, {"name": "crawl (old)", "crouched": true, "speed": 0.0})
	Elf.legacy_legs = false
	print("[boots] old crawl pose overlap %.1f mm (the bug), new %.1f mm" % [old * (ES.ELF_HEIGHT / ES.MODEL_HEIGHT) * 1000.0, _measure(e, {"name": "crawl", "crouched": true, "speed": 0.0}) * (ES.ELF_HEIGHT / ES.MODEL_HEIGHT) * 1000.0])
	if DisplayServer.get_name() != "headless":
		await _still(e)
	print("[check] bootcheck %s" % ("PASS" if ok else "FAIL"))
	m.get_tree().quit()


func _pose_list(e: Node) -> Array:
	var ws: float = e.call("walk_speed")
	var out := [{"name": "stand", "speed": 0.0}]
	for k in 8:
		out.append({"name": "walk %d/8" % k, "speed": ws, "phase": k * TAU / 8.0})
		out.append({"name": "crawl-move %d/8" % k, "speed": ws * 0.5, "phase": k * TAU / 8.0, "crouched": true})
		out.append({"name": "crouch-walk %d/8" % k, "speed": ws * 0.6, "phase": k * TAU / 8.0, "tac": true})
		out.append({"name": "climb %d/8" % k, "speed": 0.0, "phase": k * TAU / 8.0, "pose": "climb"})
	out += [{"name": "crawl / prone", "speed": 0.0, "crouched": true}, {"name": "crouch", "speed": 0.0, "tac": true},
		{"name": "lean L", "speed": 0.0, "lean": -1.0}, {"name": "lean R", "speed": 0.0, "lean": 1.0},
		{"name": "crawl lean", "speed": 0.0, "crouched": true, "lean": 1.0}]
	for p in ["peek", "flip", "abseil", "hang", "zip", "mantle", "grate_peek"]:
		out.append({"name": p, "speed": 0.0, "pose": p})
	out.append({"name": "abseil kicking", "speed": 0.0, "pose": "abseil", "idle": 0.52})
	return out


## Pose the live rig synchronously (no frame passes, so the elf's own tick can't interfere) and
## return the deepest boot / shin penetration into the torso, model units.
func _set_pose(e: Node, p: Dictionary) -> void:
	e.set("crouched", bool(p.get("crouched", false)))
	e.set("tac_crouched", bool(p.get("tac", false)))
	e.set("lean", float(p.get("lean", 0.0)))
	e.set("pose", str(p.get("pose", "")))
	for i in 120:
		e.set("_phase", float(p.get("phase", 0.0)))
		e.set("_idle_t", float(p.get("idle", 0.0)))
		e.call("_animate", 1.0 / 60.0, float(p.speed))


func _measure(e: Node, p: Dictionary) -> float:
	_set_pose(e, p)
	var hips: Node3D = e.get("hips")
	var inv := hips.global_transform.affine_inverse()
	var worst := 0.0
	for side in [["leg_l", -1.0], ["leg_r", 1.0]]:
		var leg: Node3D = e.get(side[0])
		for smp in _leg_samples(float(side[1])):
			var hp: Vector3 = inv * (leg.global_transform * (smp[0] as Vector3))
			for el in TORSO:
				var semi: Vector3 = (el[1] as Vector3) + Vector3.ONE * float(smp[1])
				var q: Vector3 = (hp - (el[0] as Vector3)) / semi
				var dn := q.length()
				if dn < 1.0:
					worst = maxf(worst, (1.0 - dn) * minf(semi.x, minf(semi.y, semi.z)))
	return worst


## Side view: crawl, crouch, stand, the old legs (top row) and the fixed ones (bottom row).
func _still(e: Node) -> void:
	var rig := Node3D.new()
	main.add_child(rig)
	rig.global_position = ORIGIN
	var fl := GBX.box(rig, Vector3(3, 0.02, 3), Vector3(0, -0.01, 0), Color(0.55, 0.42, 0.3))
	fl.name = "Floor"
	var l := DirectionalLight3D.new()
	rig.add_child(l)
	l.rotation_degrees = Vector3(-40, -60, 0)
	var src: Node3D = e.get("model")
	var cols := [{"name": "crawl / prone", "speed": 0.0, "crouched": true}, {"name": "crouch", "speed": 0.0, "tac": true}, {"name": "stand", "speed": 0.0}]
	for row in 2:
		Elf.legacy_legs = row == 0
		for ci in cols.size():
			_set_pose(e, cols[ci])
			var cp := MODEL.instantiate() as Node3D
			rig.add_child(cp)
			GBX.toonify(cp)
			_copy_pose(src, cp)
			cp.scale = src.scale
			cp.position = Vector3(0, (1 - row) * 0.3, -0.36 + ci * 0.36)
			if row == 0:
				GBX.box(rig, Vector3(0.3, 0.01, 0.3), Vector3(0, 0.295, -0.36 + ci * 0.36), Color(0.4, 0.32, 0.25))
			var lb := Label3D.new()
			lb.text = ("BEFORE " if row == 0 else "AFTER ") + str(cols[ci].name)
			lb.pixel_size = 0.0004
			lb.font_size = 48
			lb.outline_size = 10
			lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			rig.add_child(lb)
			lb.position = Vector3(0, (1 - row) * 0.3 + 0.25, -0.36 + ci * 0.36)
	Elf.legacy_legs = false
	_set_pose(e, {"name": "stand", "speed": 0.0})
	var cam := Camera3D.new()
	cam.fov = 40
	cam.near = 0.01
	main.add_child(cam)
	cam.global_position = ORIGIN + Vector3(1.55, 0.3, 0.0)
	cam.look_at(ORIGIN + Vector3(0, 0.2, 0))
	cam.current = true
	clean_screen()
	await _wait(0.4)
	await grab("elf_boots_fix")


const GBX := preload("res://scripts/greybox.gd")


func _copy_pose(src: Node3D, dst: Node3D) -> void:
	for n in src.find_children("*", "Node3D", true, false):
		var path := src.get_path_to(n)
		var t := dst.get_node_or_null(path) as Node3D
		if t:
			t.transform = (n as Node3D).transform
