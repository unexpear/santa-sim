extends "res://scripts/checks.gd"
## Visual review stills (version-independent: only uses helpers that also exist in older builds,
## so the same file can be dropped into an old checkout to shoot "before"). Run through
## tools/review_tree.gd with REVIEW_DIR set; no user args, so the game starts as the player sees it.


func review(m: Node3D, d: String) -> void:
	_init_check(m, d)
	await _wait(3.0)
	var sl: Node3D = m.get("sleigh")
	await grab("rv_hud_start")
	clean_screen()
	for hn in ["HouseFlat", "HouseSteep", "HouseSlick"]:
		var h := m.get_node_or_null(hn) as Node3D
		if h == null:
			continue
		var c := h.global_position
		cut_look(c + h.global_basis.z * 16.0 + h.global_basis.x * 7.0 + Vector3(0, 7, 0), c + Vector3(0, 2.5, 0))
		await _wait(0.8)
		await grab("rv_ext_" + hn)
	if sl:
		var p := sl.global_position
		cut_look(p + sl.global_basis.x * 3.5 + sl.global_basis.z * 3.0 + Vector3(0, 1.4, 0), p + Vector3(0, 0.6, 0))
		await _wait(0.6)
		await grab("rv_sleigh_team")
		cut_look(p + Vector3(0, 30, 40), p + Vector3(0, 0, -20))
		await _wait(0.8)
		await grab("rv_street_wide")
	var flat: Node3D = m.get_node("HouseFlat")
	if not await land(flat):
		print("[review] land failed")
		m.get_tree().quit()
		return
	await enter_and_capture(flat, false)
	await _wait(1.0)
	await grab("rv_hud_inside")
	clean_screen()
	for k in ["hotbar", "info"]:
		var cc = gadgets.get(k)
		if cc is Control:
			(cc as Control).visible = false
	var it: Node3D = flat.get("interior")
	var shots: Dictionary = it.get("shots")
	for key in shots.keys():
		var s: Array = shots[key]
		cut_look(flat.to_global(s[0]), flat.to_global(s[1]))
		await _wait(0.7)
		await grab("rv_int_" + str(key))
	# the elf, close (front and side)
	var e := elf.global_position
	var fw := -elf.global_basis.z
	fw.y = 0
	fw = fw.normalized() if fw.length() > 0.1 else Vector3.FORWARD
	cut_look(e + fw * 0.38 + Vector3(0, 0.12, 0), e + Vector3(0, 0.1, 0))
	await _wait(0.6)
	await grab("rv_elf_front")
	cut_look(e + fw.cross(Vector3.UP) * 0.38 + Vector3(0, 0.12, 0), e + Vector3(0, 0.1, 0))
	await _wait(0.4)
	await grab("rv_elf_side")
	# doors
	var doors: Array = it.get("doors")
	var n := 0
	for dr in doors:
		if n >= 2:
			break
		var mid: Vector3 = dr.call("world_mid")
		var nn: Vector3 = (dr as Node3D).global_basis.z
		var c0 := flat.global_position
		c0.y = mid.y
		if (c0 - mid).dot(nn) < 0.0:
			nn = -nn
		cut_look(mid + nn * 1.3 + Vector3(0, 0.7, 0), mid + Vector3(0, 0.8, 0))
		await _wait(0.5)
		await grab("rv_door_%d" % n)
		n += 1
	# residents
	var rs: Array = it.get("residents")
	n = 0
	for r in rs:
		if n >= 2:
			break
		var p: Vector3 = (r as Node3D).global_position
		cut_look(p + Vector3(1.0, 1.1, 0.9), p)
		await _wait(0.5)
		await grab("rv_resident_%d" % n)
		n += 1
	# the night cycle (newer builds): the same views at midnight
	var clock = m.get("night_clock")
	if clock:
		clock.call("set_hour", 0.0)
		await _wait(0.5)
		var s2: Array = shots[shots.keys()[0]]
		cut_look(flat.to_global(s2[0]), flat.to_global(s2[1]))
		await _wait(0.5)
		await grab("rv_int_midnight")
		var h2: Node3D = m.get_node("HouseSteep")
		cut_look(h2.global_position + h2.global_basis.z * 16.0 + h2.global_basis.x * 7.0 + Vector3(0, 7, 0), h2.global_position + Vector3(0, 2.5, 0))
		await _wait(0.8)
		await grab("rv_ext_midnight")
	print("[review] done")
	m.get_tree().quit()
