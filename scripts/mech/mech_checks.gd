extends "res://scripts/checks.gd"
## --mechcheck=dir : the generic-physics rigs. Nothing here is scripted to succeed: each rig is
## bodies + ropes + rotors, and the assertion is what the simulation did.
##   pulley: the elf's weight can't lift a 0.8 kg present over a single fixed pulley, can with a
##           2:1 block-and-tackle (and 3:1) - the advantage comes only from the rope routing
##   handles: lever opens by hanging weight; knob doesn't (grip slips) but does with a wrapped
##           rope + counterweight; slider opens with a counterweight over a pulley, not by the elf;
##           the elf alone can't move a heavy front door; a light door it can
##   lever tip, catapult onto a table, spool winch
## Stills (windowed): handle_types, trick_pulley, trick_lever, trick_catapult, trick_door_rope,
## trick_counterweight.

const Mech := preload("res://scripts/mech/mech.gd")
const Parts := preload("res://scripts/mech/parts.gd")
const Door := preload("res://scripts/door.gd")
const GB := preload("res://scripts/greybox.gd")

const ORIGIN := Vector3(0, 400, 0)  ## rigs are built well away from the town
var rig: Node3D
var cam: Camera3D
var results: Array = []


func mech_check(m: Node3D, d: String) -> void:
	_init_check(m, d)
	Door.draw_handles = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _wait(1.0)
	var lift1 := await pulley_rig(1)
	var lift2 := await pulley_rig(2, "trick_pulley")
	var lift3 := await pulley_rig(3)
	_res(lift1 < 0.01, "pulley 1:1 (single fixed): present lifted %.3f m (elf 4.9 N < present 7.8 N: should stay down)" % lift1)
	_res(lift2 > 0.1, "pulley 2:1 block-and-tackle: present lifted %.3f m" % lift2)
	_res(lift3 > 0.1, "pulley 3:1 block-and-tackle: present lifted %.3f m" % lift3)
	await handle_rigs()
	await lever_rig()
	await catapult_rig()
	await winch_rig()
	await handle_types_still()
	for r in results:
		print("[mech] " + str(r))
	print("[check] mechcheck %s" % ("PASS" if ok else "FAIL"))
	m.get_tree().quit()


func _res(pass_: bool, text: String) -> void:
	results.append(("ok   " if pass_ else "FAIL ") + text)
	if not pass_:
		fail(text)


func _new_rig(cam_from: Vector3, cam_at: Vector3) -> Node3D:
	if rig:
		rig.queue_free()
		await _frames(2)
	rig = Node3D.new()
	rig.name = "MechRig"
	main.add_child(rig)
	rig.global_position = ORIGIN
	# a floor, a back wall and a warm work light (the rigs sit in the night sky otherwise)
	var fl := StaticBody3D.new()
	fl.collision_layer = Parts.LAYERS
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(6, 0.1, 3)
	cs.shape = bs
	fl.add_child(cs)
	GB.box(fl, bs.size, Vector3.ZERO, Color(0.55, 0.42, 0.3))
	rig.add_child(fl)
	fl.position = Vector3(0, -0.05, 0)
	GB.box(rig, Vector3(6, 2.4, 0.05), Vector3(0, 1.2, -0.8), Color(0.78, 0.74, 0.66))
	var l := OmniLight3D.new()
	l.omni_range = 6.0
	l.light_energy = 2.2
	l.light_color = Color(1.0, 0.9, 0.75)
	l.shadow_enabled = true
	rig.add_child(l)
	l.position = Vector3(0.6, 1.8, 1.4)
	if cam == null:
		cam = Camera3D.new()
		cam.fov = 50.0
		cam.near = 0.01
		main.add_child(cam)
	cam.global_position = ORIGIN + cam_from
	cam.look_at(ORIGIN + cam_at)
	cam.current = true
	return rig


func _label(text: String, p: Vector3, size := 0.03) -> void:
	var lb := Label3D.new()
	lb.text = text
	lb.pixel_size = size * 0.01
	lb.font_size = 64
	lb.outline_size = 12
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	rig.add_child(lb)
	lb.position = p


## n = 1, 2 or 3 supporting rope runs on the present. Same rope, same pulleys: only the routing differs.
func pulley_rig(n: int, still := "") -> float:
	await _new_rig(Vector3(0.15, 0.7, 1.6), Vector3(0.15, 0.6, 0))
	var beam_y := 1.2
	GB.box(rig, Vector3(0.8, 0.04, 0.06), Vector3(0.1, beam_y + 0.04, 0), Color(0.45, 0.3, 0.2))
	var pr := Parts.present(rig, ORIGIN + Vector3(0, 0.08, 0))
	var elf := Parts.elf_body(rig, ORIGIN + Vector3(0.35, 0.9, 0))
	var r: Node3D = Parts.rope(rig)
	var top := Vector3(0, 0.08, 0)
	var s_redirect := Parts.sheave(rig, ORIGIN + Vector3(0.35, beam_y, 0))
	match n:
		1:
			var s1 := Parts.sheave(rig, ORIGIN + Vector3(0, beam_y, 0))
			r.add_world_point(pr, pr.global_position + top)
			r.add_point(s1, Vector3.ZERO)
		2:
			var hook := ORIGIN + Vector3(-0.04, beam_y, 0)
			GB.sphere(rig, 0.008, hook - ORIGIN, Color(0.3, 0.3, 0.3))
			var block := Parts.sheave(pr, pr.global_position + top + Vector3(0, 0.03, 0))
			var s1 := Parts.sheave(rig, ORIGIN + Vector3(0.04, beam_y, 0))
			r.add_world_point(null, hook)
			r.add_point(block, Vector3.ZERO)
			r.add_point(s1, Vector3.ZERO)
		3:
			var block := Parts.sheave(pr, pr.global_position + top + Vector3(0.04, 0.03, 0))
			var f1 := Parts.sheave(rig, ORIGIN + Vector3(-0.04, beam_y, 0))
			var f2 := Parts.sheave(rig, ORIGIN + Vector3(0.04, beam_y + 0.04, 0))
			r.add_world_point(pr, pr.global_position + top + Vector3(-0.04, 0, 0))
			r.add_point(f1, Vector3.ZERO)
			r.add_point(block, Vector3.ZERO)
			r.add_point(f2, Vector3.ZERO)
	r.add_point(s_redirect, Vector3.ZERO)
	r.add_world_point(elf, elf.global_position + Vector3(0, 0.1, 0), "grip")
	r.call("fit")
	_label("%d:1  (%s)" % [n, "single fixed pulley" if n == 1 else "block and tackle"], Vector3(0.15, 1.4, 0))
	_label("present 0.8 kg", Vector3(-0.15, 0.3, 0.1), 0.02)
	_label("elf 0.5 kg", Vector3(0.5, 0.9, 0.1), 0.02)
	var y0 := pr.global_position.y
	var best := 0.0
	for i in 90:
		await main.get_tree().physics_frame
		best = maxf(best, pr.global_position.y - y0)
		if still != "" and i == 45:
			await grab(still)
	print("[mech] pulley %d:1 tension %.2f N, present rise %.3f m, elf y %.2f" % [n, float(r.get("tension")), best, elf.global_position.y - ORIGIN.y])
	return best


func _door(kind: String, heavy: bool, x: float) -> Node3D:
	var dr := Door.new()
	dr.configure(kind, heavy)
	rig.add_child(dr)
	dr.position = Vector3(x, 0, 0)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 2.05, 0.04)
	var mi_mesh := ArrayMesh.new()
	mi_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bm.get_mesh_arrays())
	var xf := Transform3D(Basis(), Vector3(0.45, 1.025, 0))
	var st := SurfaceTool.new()
	st.append_from(mi_mesh, 0, xf)
	var door_mesh := st.commit()
	door_mesh.surface_set_material(0, GB.mat(Color(0.86, 0.82, 0.74) if kind != "slide" else Color(0.6, 0.75, 0.8)))
	dr.setup(door_mesh, 0.9, 0.0, 1.0)
	dr.prefer_sign = 1.0
	return dr


func _handle_attach(dr: Node3D, kind: String) -> Vector3:
	var h: Node3D = dr.get("handle") if dr.get("handle") else dr.get("flip_latch")
	for a in h.get_meta("attach_points", []):
		if str(a.kind) == kind and float((a.p as Vector3).z) > 0.0:
			return h.global_transform * (a.p as Vector3)
	return h.global_position


func handle_rigs() -> void:
	# --- lever: hang the elf's weight on the bar end -------------------------------------------
	await _new_rig(Vector3(0.6, 1.0, 1.5), Vector3(0.6, 0.9, 0))
	var dr := _door("lever", false, 0.0)
	var h: Node3D = dr.get("handle")
	var p := _handle_attach(dr, "lever_end")
	var elf := Parts.elf_body(rig, p + Vector3(0, -0.2, 0.0))
	var r: Node3D = Parts.rope(rig)
	r.add_world_point(h.get("visual"), p, "grip")
	r.add_world_point(elf, elf.global_position + Vector3(0, 0.1, 0), "grip")
	r.call("fit")
	await _wait(1.2)
	var released := not bool(dr.get("latched"))
	var th := rad_to_deg(float(h.get("theta")))
	for i in 120:  # hanging there, it kicks off the frame (its traction-limited push)
		dr.call("elf_push", elf.global_position + Vector3(0, 0, 0.3))
		await main.get_tree().physics_frame
	_res(released and float(dr.get("angle")) > 10.0, "lever handle + hanging elf weight: handle %.0f deg, latch %s, door opened to %.0f deg" % [th, "released" if released else "HELD", float(dr.get("angle"))])
	await grab("trick_door_rope")
	# --- knob: hanging slips; a wrapped rope + 1 kg counterweight turns it ---------------------
	await _new_rig(Vector3(0.6, 1.0, 1.5), Vector3(0.6, 0.9, 0))
	dr = _door("knob", false, 0.0)
	h = dr.get("handle")
	p = _handle_attach(dr, "knob_rim")
	elf = Parts.elf_body(rig, p + Vector3(0, -0.2, 0.0))
	r = Parts.rope(rig)
	r.add_world_point(h.get("visual"), p, "grip")
	r.add_world_point(elf, elf.global_position + Vector3(0, 0.1, 0), "grip")
	r.call("fit")
	await _wait(1.2)
	var knob_hang := not bool(dr.get("latched"))
	var th_hang := rad_to_deg(float(h.get("theta")))
	r.queue_free()
	elf.queue_free()
	await _frames(2)
	var cw := Parts.weight(rig, h.global_position + Vector3(0.03, -0.35, 0.08), 1.0)
	var r2: Node3D = Parts.rope(rig)
	r2.add_world_point(cw, cw.global_position + Vector3(0, 0.03, 0))
	r2.call("wrap_start", h, 0.028, cw.global_position, -1.0)
	r2.call("fit")
	await _wait(1.5)
	var knob_rope := not bool(dr.get("latched"))
	_res(not knob_hang, "knob + hanging elf: grip slips (knob %.0f deg), latch %s" % [th_hang, "released" if knob_hang else "held"])
	_res(knob_rope, "knob + wrapped rope + 1 kg counterweight: knob %.0f deg, latch %s" % [rad_to_deg(float(h.get("theta"))), "released" if knob_rope else "HELD"])
	# --- slider: flip the latch, the elf can't haul 40 kg; a 1.5 kg counterweight over a pulley can
	await _new_rig(Vector3(0.2, 1.1, 1.8), Vector3(0.2, 0.8, 0))
	dr = _door("slide", true, 0.0)
	var fl: Node3D = dr.get("flip_latch")
	var tab := _handle_attach(dr, "flip_tab")
	for i in 30:
		fl.call("apply_point_force", tab, Vector3(-Mech.ELF_PUSH, 0, 0))  # flick the tab toward the hinge
		await main.get_tree().physics_frame
	for i in 120:
		dr.call("elf_push", dr.call("world_mid") + Vector3(0.4, 0.3, 0.3))
		await main.get_tree().physics_frame
	var by_elf := float(dr.get("q"))
	var pull := dr.to_global(Vector3(0.89, 0.95, 0.0))
	var sv := Parts.sheave(rig, ORIGIN + Vector3(-0.7, 0.95, 0.0))
	cw = Parts.weight(rig, ORIGIN + Vector3(-0.74, 0.6, 0.0), 1.5)
	r = Parts.rope(rig)
	r.add_world_point(dr.get("_slab"), pull)
	r.add_point(sv, Vector3.ZERO)
	r.add_world_point(cw, cw.global_position + Vector3(0, 0.04, 0))
	r.call("fit")
	await _wait(2.0)
	var by_cw := float(dr.get("q"))
	_res(by_elf < 0.01 and by_cw > 0.25, "slider 40 kg: elf alone moved it %.3f m; 1.5 kg counterweight over a pulley %.2f m" % [by_elf, by_cw])
	await grab("trick_counterweight")
	# --- heavy front door vs a light interior door, elf pushing alone -------------------------
	await _new_rig(Vector3(1.0, 1.0, 2.0), Vector3(1.0, 0.8, 0))
	var heavy := _door("lever", true, 0.0)
	var light := _door("lever", false, 1.4)
	heavy.call("unlatch")
	light.call("unlatch")
	for i in 180:
		heavy.call("elf_push", heavy.to_global(Vector3(0.75, 0.15, 0.3)))
		light.call("elf_push", light.to_global(Vector3(0.75, 0.15, 0.3)))
		await main.get_tree().physics_frame
	_res(float(heavy.get("angle")) < 2.0, "heavy front door (32 kg, seals): elf pushing alone for 3 s opened it %.1f deg" % float(heavy.get("angle")))
	_res(float(light.get("angle")) > 10.0, "light interior door (12 kg, unlatched): elf push opened it %.0f deg" % float(light.get("angle")))


## A ruler on a crayon: the elf drops onto the long end and tips a book up on the short end.
func lever_rig() -> void:
	await _new_rig(Vector3(0.0, 0.35, 0.9), Vector3(0.0, 0.08, 0))
	Parts.fulcrum(rig, ORIGIN + Vector3(0, 0.015, 0))
	var pl := Parts.plank(rig, ORIGIN + Vector3(0, 0.036, 0), 0.4, 0.06)
	var book := Parts.box_body(rig, Vector3(0.1, 0.03, 0.08), ORIGIN + Vector3(-0.15, 0.06, 0), 0.4, Color(0.2, 0.35, 0.7), "Book")
	await _wait(0.8)
	var y0 := book.global_position.y
	var elf := Parts.elf_body(rig, ORIGIN + Vector3(0.17, 0.25, 0))
	var best := 0.0
	for i in 90:
		await main.get_tree().physics_frame
		best = maxf(best, book.global_position.y - y0)
		if i == 30:
			await grab("trick_lever")
	_res(best > 0.02, "lever: ruler on a crayon, elf (0.5 kg at 17 cm) vs book (0.4 kg at 15 cm): book rose %.3f m" % best)
	elf.queue_free()
	pl.queue_free()


## Seesaw catapult: a 1.5 kg tin dropped on the short arm flings a 20 g bauble onto a side table.
func catapult_rig() -> void:
	await _new_rig(Vector3(0.6, 0.6, 1.6), Vector3(0.6, 0.2, 0))
	Parts.fulcrum(rig, ORIGIN + Vector3(0, 0.02, 0), 0.02)
	var pl := Parts.plank(rig, ORIGIN + Vector3(0.07, 0.047, 0), 0.5, 0.08, 0.06)
	var shot := Parts.box_body(rig, Vector3(0.03, 0.03, 0.03), ORIGIN + Vector3(0.29, 0.08, 0), 0.02, Color(0.9, 0.2, 0.25), "Bauble", 0.8)
	# side table: 0.3 m high top, 0.5 m deep, starting 0.7 m out
	var tb := StaticBody3D.new()
	tb.collision_layer = Parts.LAYERS
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.36, 0.2, 0.5)
	cs.shape = bs
	tb.add_child(cs)
	GB.box(tb, bs.size, Vector3.ZERO, Color(0.5, 0.33, 0.2))
	rig.add_child(tb)
	tb.position = Vector3(0.62, 0.1, 0)
	await _wait(0.6)
	var tin := Parts.weight(rig, ORIGIN + Vector3(-0.16, 0.55, 0), 1.5, Color(0.7, 0.7, 0.75))
	var landed := false
	var peak := 0.0
	for i in 150:
		await main.get_tree().physics_frame
		peak = maxf(peak, shot.global_position.y - ORIGIN.y)
		if i == 14:
			await grab("trick_catapult")
		var lp := shot.global_position - ORIGIN
		if absf(lp.x - 0.62) < 0.18 and lp.y > 0.19 and lp.y < 0.26 and shot.linear_velocity.length() < 0.05:
			landed = true
	var lp2 := shot.global_position - ORIGIN
	landed = landed or (absf(lp2.x - 0.62) < 0.18 and absf(lp2.z) < 0.25 and lp2.y > 0.19)
	_res(landed, "catapult: 1.5 kg tin from 0.5 m onto a ruler seesaw: 20 g bauble peaked %.2f m, ended at x %.2f y %.2f (side table top x 0.44-0.80, y 0.20)" % [peak, lp2.x, lp2.y])
	tin.queue_free()
	pl.queue_free()


## A cotton-reel winch: the elf cranks (its push on a 5 cm crank) and winds a 0.6 kg present up.
func winch_rig() -> void:
	await _new_rig(Vector3(0.1, 0.6, 1.2), Vector3(0.1, 0.5, 0))
	var sp := Parts.spool(rig, ORIGIN + Vector3(0.0, 0.9, 0))
	var pr := Parts.present(rig, ORIGIN + Vector3(0.012, 0.08, 0), 0.6, Vector3(0.12, 0.1, 0.12))
	var r: Node3D = Parts.rope(rig)
	r.add_world_point(pr, pr.global_position + Vector3(0, 0.05, 0))
	r.call("wrap_start", sp, 0.012, pr.global_position, 1.0)
	r.call("fit")
	var y0 := pr.global_position.y
	for i in 180:
		sp.call("apply_torque", -Mech.ELF_PUSH * 0.05)  # elf leaning on the crank: 0.22 N*m vs 0.6*9.81*0.012 = 0.07 N*m
		await main.get_tree().physics_frame
	_res(pr.global_position.y - y0 > 0.05, "winch: elf cranking a cotton reel lifted a 0.6 kg present %.3f m" % (pr.global_position.y - y0))


func handle_types_still() -> void:
	await _new_rig(Vector3(2.3, 1.2, 3.6), Vector3(2.3, 0.95, 0))
	var kinds := ["lever", "knob", "plate", "slide", "screen"]
	var names := ["LEVER\nhang weight on the bar", "ROUND KNOB\nwrap a rope, pull tangentially", "PUSH PLATE\nno latch: mass + friction", "SLIDER 40 kg\nflip latch + sustained pull", "SCREEN\nspring closer pushes back"]
	for i in kinds.size():
		var dr := _door(kinds[i], kinds[i] == "slide", i * 1.15)
		var lb_p := Vector3(i * 1.15 + 0.45, 2.3, 0.1)
		_label(str(names[i]), lb_p, 0.022)
		print("[mech] door %s: mass %.0f kg, hinge friction %.2f, closer %.2f N*m/rad, latch release %.2f rad" % [kinds[i], float(dr.get("mass")), float(dr.get("hinge_friction")), float(dr.get("closer_k")), float(dr.get("latch_release"))])
	await _wait(0.5)
	await grab("handle_types")
