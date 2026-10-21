extends RefCounted
## Scripted checks for the chimney entry / interiors / gadgets / FX (run in a real window to save stills).
##   --intcheck=<dir>     land on each landing house, enter the chimney, walk the elf through every room, exit
##   --wallcheck=<dir>    ram the elf into every wall and closed door in all three houses
##   --gadgetcheck=<dir>  exercise every prototype gadget in the lit-fireplace house (+ evidence warnings)
##   --fxshots=<dir>      fog + particle captures

const ES := preload("res://scripts/elf_size.gd")
const Furn := preload("res://scripts/furniture.gd")

var main: Node3D
var mission: Node
var elf: CharacterBody3D
var gadgets: Node
var dir := ""
var ok := true


func _init_check(m: Node3D, d: String) -> void:
	main = m
	dir = d
	DirAccess.make_dir_recursive_absolute(dir)
	mission = m.get("mission")
	mission.set("scripted", true)
	m.set("stills_mode", true)
	elf = mission.get("elf")
	gadgets = mission.get("gadgets")


func _wait(t: float) -> void:
	await main.get_tree().create_timer(t).timeout


func _frames(n: int) -> void:
	for i in n:
		await main.get_tree().process_frame


func grab(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("[check] (headless) would save still %s" % name)
		await main.get_tree().process_frame
		return
	await RenderingServer.frame_post_draw
	var img := main.get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name + ".png"))
	var small := img.duplicate() as Image
	if small.get_width() > 1280:
		small.resize(1280, int(1280.0 * small.get_height() / small.get_width()), Image.INTERPOLATE_BILINEAR)
	small.save_jpg(dir.path_join(name + ".jpg"), 0.85)
	print("[check] still %s" % name)


func fail(msg: String) -> void:
	ok = false
	print("[check] FAIL %s" % msg)


## Land gently on a house's landing pad and wait until the chimney prompt is available.
func land(h: Node3D) -> bool:
	var off := Vector3(0, 2.0, 0)
	for attempt in 3:
		Input.action_press("brake")
		main.call("_drop_sleigh", "land on %s for chimney entry" % h.name, h, off, Vector3.ZERO)
		await _wait(3.5)
		Input.action_release("brake")
		await _wait(0.6)
		if mission.call("roof_house") == h:
			print("[check] landed on %s (%s), chimney in reach" % [h.name, main.get("sleigh").call("status_text")])
			return true
		off = Vector3(0, 1.2, 0) if attempt == 0 else Vector3(0.6, 1.2, -0.6)
	fail("could not land near %s chimney (status %s)" % [h.name, main.get("sleigh").call("status_text")])
	return false


func cut_look(from: Vector3, to: Vector3) -> void:
	var cam: Camera3D = mission.get("cut_cam")
	cam.current = true
	cam.look_at_from_position(from, to, Vector3.UP)


func wait_phase(p: String, timeout := 12.0) -> void:
	var t0 := Time.get_ticks_msec()
	while str(mission.get("cut_phase")) != p and Time.get_ticks_msec() - t0 < timeout * 1000.0:
		await main.get_tree().process_frame


func wait_mode(m: int, timeout := 15.0) -> void:
	var t0 := Time.get_ticks_msec()
	while int(mission.get("mode")) != m and Time.get_ticks_msec() - t0 < timeout * 1000.0:
		await main.get_tree().process_frame


## Auto-walk the elf to a world point. Returns true if reached.
func walk_to(p: Vector3, timeout := 14.0) -> bool:
	elf.set("auto_target", p)
	var t0 := Time.get_ticks_msec()
	var last := elf.global_position
	var last_t := t0
	var reached := false
	while Time.get_ticks_msec() - t0 < timeout * 1000.0:
		await main.get_tree().physics_frame
		var d := Vector2(elf.global_position.x - p.x, elf.global_position.z - p.z).length()
		if d < 0.2:
			reached = true
			break
		if Time.get_ticks_msec() - last_t > 2500:
			if elf.global_position.distance_to(last) < 0.15:
				break
			last = elf.global_position
			last_t = Time.get_ticks_msec()
	elf.set("auto_target", Vector3.INF)
	elf.velocity = Vector3.ZERO
	return reached


var _grids: Dictionary = {}
const CELL := 0.15


## Walkable grid for one floor level of a house interior (cells blocked by furniture/walls on layer 4).
func _grid(h: Node3D, level_y: float, crouched := false) -> AStarGrid2D:
	var key := "%s|%.1f|%s" % [h.name, level_y, crouched]
	if _grids.has(key):
		return _grids[key]
	var it: Node3D = h.get("interior")
	var x0 := float(it.get("X0"))
	var z0 := float(it.get("Z0"))
	var nx := int(ceil((float(it.get("X1")) - x0) / CELL))
	var nz := int(ceil((float(it.get("Z1")) - z0) / CELL))
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, nx, nz)
	g.cell_size = Vector2(CELL, CELL)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.update()
	var space := main.get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	# the standing elf (plus a little clearance): walks around furniture, not under it
	# (crouched: the crawling elf, which fits under couches and beds)
	var eh_box := ES.crouch_height() if crouched else ES.ELF_HEIGHT
	shape.size = Vector3(ES.radius() * 2.0 + 0.06, eh_box, ES.radius() * 2.0 + 0.06)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 4
	for ix in nx:
		for iz in nz:
			var lp := Vector3(x0 + (ix + 0.5) * CELL, level_y, z0 + (iz + 0.5) * CELL)
			q.transform = Transform3D(h.global_basis, h.to_global(lp + Vector3(0, eh_box * 0.5 + 0.03, 0)))
			var solid := not space.intersect_shape(q, 1).is_empty()
			if not solid:
				var rq := PhysicsRayQueryParameters3D.create(h.to_global(lp + Vector3(0, 0.1, 0)), h.to_global(lp + Vector3(0, -0.4, 0)), 4)
				solid = space.intersect_ray(rq).is_empty()
			g.set_point_solid(Vector2i(ix, iz), solid)
	_grids[key] = g
	return g


func _cell(h: Node3D, g: AStarGrid2D, w: Vector3) -> Vector2i:
	var it: Node3D = h.get("interior")
	var lp := h.to_local(w)
	var c := Vector2i(clampi(int((lp.x - float(it.get("X0"))) / CELL), 0, g.region.size.x - 1), clampi(int((lp.z - float(it.get("Z0"))) / CELL), 0, g.region.size.y - 1))
	if not g.is_point_solid(c):
		return c
	for r in range(1, 8):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var n := c + Vector2i(dx, dz)
				if g.region.has_point(n) and not g.is_point_solid(n):
					return n
	return c


## Walk to a world point, routing around furniture on the same floor (A* over the collision layer).
func walk_path(target: Vector3, house: Node3D = null, crouched := false) -> bool:
	var h := house if house else gadgets.get("house") as Node3D
	if h == null or absf(elf.global_position.y - target.y) > 0.5:
		return await walk_to(target)
	var level := h.to_local(target).y
	var g := _grid(h, level, crouched)
	var it: Node3D = h.get("interior")
	var path := g.get_id_path(_cell(h, g, elf.global_position), _cell(h, g, target), true)
	for i in range(0, path.size()):
		if not crouched and i % 3 != 2 and i != path.size() - 1:
			continue  # (crawling follows every cell: tight gaps between legs and walls)
		var c: Vector2i = path[i]
		var lp := Vector3(float(it.get("X0")) + (c.x + 0.5) * CELL, level, float(it.get("Z0")) + (c.y + 0.5) * CELL)
		await walk_to(h.to_global(lp), 4.0)
	return await walk_to(target, 4.0)


## Point the elf's third-person camera (and so the crosshair ray) at a world point.
func aim_at(p: Vector3) -> void:
	var yaw: Node3D = elf.get("cam_yaw")
	var pitch: Node3D = elf.get("cam_pitch")
	var d := (p - yaw.global_position).normalized()
	yaw.rotation.y = atan2(-d.x, -d.z)
	pitch.rotation.x = clampf(asin(d.y), deg_to_rad(-60), deg_to_rad(35))
	elf.call("face", d)


func roof_type_of(h: Node3D) -> int:
	return int(h.get("roof_type"))


func floor_under(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.3, 0), p + Vector3(0, -4, 0), 4)
	var hit := main.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else p


## Room still from the elf's own third-person camera: the elf stands near a corner, looking over its
## shoulder at the camera, with the room behind it.
func room_shot(h: Node3D, room_name: String, still: String) -> void:
	var it: Node3D = h.get("interior")
	var r: Dictionary = it.call("_r", room_name)
	if r.is_empty():
		return
	var rc: Rect2 = r.rect
	var fl := float(r.floor)
	var g := _grid(h, fl)
	var c := Vector3(rc.get_center().x, fl, rc.get_center().y)
	var best := Vector3.INF
	var best_score := -1
	for corner in [rc.position, Vector2(rc.end.x, rc.position.y), rc.end, Vector2(rc.position.x, rc.end.y)]:
		var cp := Vector3(corner.x, fl, corner.y).lerp(c, 0.28)
		var cell := _cell(h, g, h.to_global(cp))
		var lp := Vector3(float(it.get("X0")) + (cell.x + 0.5) * CELL, fl, float(it.get("Z0")) + (cell.y + 0.5) * CELL)
		if not rc.grow(-0.2).has_point(Vector2(lp.x, lp.z)):
			continue
		var score := 0
		for k in 12:
			var q := lp.lerp(c, (k + 1) / 12.0)
			var qc := Vector2i(int((q.x - float(it.get("X0"))) / CELL), int((q.z - float(it.get("Z0"))) / CELL))
			if g.region.has_point(qc) and not g.is_point_solid(qc):
				score += 1
		# room behind the camera matters too (don't back the camera into a wall)
		var back := lp - (c - lp).normalized() * 1.2
		if rc.has_point(Vector2(back.x, back.z)):
			score += 4
		if score > best_score:
			best_score = score
			best = lp
	if best == Vector3.INF:
		return
	var wp := h.to_global(best)
	elf.global_position = wp + Vector3(0, 0.05, 0)
	elf.velocity = Vector3.ZERO
	var dir := (h.to_global(c) - wp)
	dir.y = 0
	dir = dir.normalized()
	var yaw: Node3D = elf.get("cam_yaw")
	var pitch: Node3D = elf.get("cam_pitch")
	var spring: SpringArm3D = elf.get("spring")
	var old_len := spring.spring_length
	spring.spring_length = 2.3
	yaw.rotation.y = atan2(-dir.x, -dir.z)
	pitch.rotation.x = deg_to_rad(-16)
	yaw.global_position = elf.global_position + Vector3(0, float(elf.get("camera_height")) + 0.25, 0)
	elf.call("face", (-dir).rotated(Vector3.UP, deg_to_rad(40)))
	(elf.get("camera") as Camera3D).current = true
	await _wait(0.7)
	elf.call("face", (-dir).rotated(Vector3.UP, deg_to_rad(40)))
	await grab(still)
	spring.spring_length = old_len


## A cut camera from inside the room the elf is in, framing `target` (avoids clipping into walls).
func room_cam(h: Node3D, target: Vector3, height := 1.7) -> void:
	var it: Node3D = h.get("interior")
	var lp := h.to_local(target)
	var room: Dictionary = {}
	for r in it.get("rooms"):
		if (r.rect as Rect2).has_point(Vector2(lp.x, lp.z)) and absf(float(r.floor) - lp.y) < 1.5:
			room = r
	if room.is_empty():
		return
	var rc: Rect2 = room.rect
	var c := Vector3(rc.get_center().x, float(room.floor), rc.get_center().y)
	var away := (c - lp)
	away.y = 0
	if away.length() < 0.3:
		away = Vector3(1, 0, 0)
	var cp := c + away.normalized() * minf(rc.size.x, rc.size.y) * 0.3
	cp.x = clampf(cp.x, rc.position.x + 0.35, rc.end.x - 0.35)
	cp.z = clampf(cp.z, rc.position.y + 0.35, rc.end.y - 0.35)
	cp.y = float(room.floor) + height
	cut_look(h.to_global(cp), target)


func clean_screen() -> void:
	(main.get("hud") as CanvasLayer).visible = false
	gadgets.get("prompt").text = ""
	gadgets.get("popup").text = ""


func enter_and_capture(h: Node3D, stills: bool) -> void:
	mission.call("enter", h)
	if stills:
		await wait_phase("hook")
		await _wait(0.35)
		clean_screen()
		await grab("int_chimney")
		await wait_phase("abseil")
		await _wait(1.3)
		await grab("int_slide")
		await wait_phase("fireplace")
		await _wait(0.9)
		await grab("int_fireplace")
	await wait_mode(2, 150.0)  # the full chimney entry cutscene runs ~15 s (much longer on a slow renderer)
	if int(mission.get("mode")) != 2:
		fail("never got control of the elf in %s" % h.name)
	await open_doors(h)  # tours / A* assume open doorways (wall_door_check tests them shut)


func exit_house() -> void:
	var it: Node3D = gadgets.get("interior")
	var house: Node3D = gadgets.get("house")
	await walk_path(house.to_global(it.get("hearth_point")))
	if not bool(mission.call("try_exit")):
		await _wait(0.3)
		mission.call("try_exit")
	await wait_mode(0, 15.0)
	if int(mission.get("mode")) != 0:
		fail("exit from %s never finished (elf at %s)" % [house.name, house.to_local(elf.global_position)])
		if int(mission.get("mode")) == 2:
			await mission.call("exit_house")
	else:
		print("[check] exited %s, back on the sleigh" % house.name)


func fps_here(label: String, secs := 3.0) -> String:
	_rec_paused = true
	await _frames(10)
	var frames := 0
	var t0 := Time.get_ticks_usec()
	var worst := 0.0
	var last := t0
	while Time.get_ticks_usec() - t0 < int(secs * 1000000.0):
		await main.get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
	var r := "%s avg %.0f fps (worst %.1f ms)" % [label, frames / ((Time.get_ticks_usec() - t0) / 1000000.0), worst]
	print("[fps] %s" % r)
	if fps_diag:
		await _fps_diag(label)
	_rec_paused = false
	return r


var fps_diag := "--fpsdiag" in OS.get_cmdline_user_args() or FileAccess.file_exists("res://.tools/fpsdiag.flag")


## Where the frame goes: draw calls, CPU times, lights near the camera, and the fps with every
## light shadow off / every light off for a second (A/B), to find what's eating the frame.
func _fps_diag(label: String) -> void:
	var cam := main.get_viewport().get_camera_3d()
	var cp := cam.global_position if cam else Vector3.ZERO
	var lights := main.get_tree().root.find_children("*", "Light3D", true, false)
	var n_vis := 0
	var n_sh := 0
	var n_near := 0
	var n_near_sh := 0
	var sh_names := {}
	for l: Light3D in lights:
		if not l.is_visible_in_tree():
			continue
		n_vis += 1
		var near := l is DirectionalLight3D or l.global_position.distance_to(cp) < 8.0
		if near:
			n_near += 1
		if l.shadow_enabled:
			n_sh += 1
			if near:
				n_near_sh += 1
				var k := str(l.name).rstrip("0123456789@")
				sh_names[k] = int(sh_names.get(k, 0)) + 1
	await _frames(2)
	var rs := RenderingServer
	print("[fpsdiag] %s: draws %d, objects %d, prims %d, cpu process %.1f ms, physics %.1f ms, lights visible %d (shadowed %d), near cam %d (shadowed %d: %s), meshes %d" % [label,
			rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, n_vis, n_sh, n_near, n_near_sh, sh_names,
			main.get_tree().root.find_children("*", "MeshInstance3D", true, false).size()])
	var keep := {}
	for l: Light3D in lights:
		keep[l] = [l.shadow_enabled, l.visible]
	for l: Light3D in lights:
		if not l is DirectionalLight3D:
			l.shadow_enabled = false
	print("[fpsdiag] %s: %s" % [label, await _fps_quick("point/spot shadows off")])
	for l: Light3D in lights:
		l.shadow_enabled = false
	print("[fpsdiag] %s: %s" % [label, await _fps_quick("all shadows off")])
	for l: Light3D in lights:
		if not l is DirectionalLight3D:
			l.visible = false
	print("[fpsdiag] %s: %s" % [label, await _fps_quick("all point/spot lights off")])
	for l: Light3D in lights:
		if is_instance_valid(l):
			l.shadow_enabled = keep[l][0]
			l.visible = keep[l][1]
	var env: Environment = main.get_viewport().world_3d.environment if main.get_viewport().world_3d else null
	if env == null:
		var we := main.get_tree().root.find_children("*", "WorldEnvironment", true, false)
		if not we.is_empty():
			env = (we[0] as WorldEnvironment).environment
	if env:
		var fx := [env.ssao_enabled, env.ssil_enabled, env.sdfgi_enabled, env.glow_enabled, env.volumetric_fog_enabled, env.ssr_enabled]
		print("[fpsdiag] %s: env ssao %s ssil %s sdfgi %s glow %s vfog %s ssr %s" % [label, fx[0], fx[1], fx[2], fx[3], fx[4], fx[5]])
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.sdfgi_enabled = false
		env.volumetric_fog_enabled = false
		env.ssr_enabled = false
		print("[fpsdiag] %s: %s" % [label, await _fps_quick("screen effects off")])
		env.ssao_enabled = fx[0]
		env.ssil_enabled = fx[1]
		env.sdfgi_enabled = fx[2]
		env.volumetric_fog_enabled = fx[4]
		env.ssr_enabled = fx[5]


func _fps_quick(what: String) -> String:
	await _frames(15)
	var frames := 0
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < 1000000:
		await main.get_tree().process_frame
		frames += 1
	return "%s -> %.0f fps" % [what, frames / ((Time.get_ticks_usec() - t0) / 1000000.0)]


## Follow the house tour (it knows the stairs) until reaching the named room.
func tour_to(h: Node3D, room_name: String) -> void:
	for step in (h.get("interior") as Node3D).get("tour"):
		await walk_path(h.to_global(step[1]), h)
		if str(step[0]) == room_name:
			return


## The crouched elf crawls fully under a couch and a bed, is flagged hidden, can't stand up there,
## and a nearby sleeper's awareness doesn't rise while it's hidden.
func hide_check(h: Node3D, stills: bool) -> void:
	var it: Node3D = h.get("interior")
	var couch: Node3D = null
	var beds: Array = []
	for c in it.get_children():
		if c is MeshInstance3D and str(c.name).begins_with("Couch"):
			couch = c
		elif c is MeshInstance3D and str(c.name).begins_with("Bed"):
			beds.append(c)
	if couch == null or beds.is_empty():
		fail("%s: no couch or bed found for the hiding check" % h.name)
		return
	print("[hide] %s: couch gap %.3f m (%s), bed gap %.3f m (%s), crawling elf %.3f m (standing %.3f m)" % [h.name,
			float(couch.get_meta("gap")), couch.get_meta("tier", "?"), float(beds[0].get_meta("gap")), beds[0].get_meta("tier", "?"), ES.crouch_height(), ES.ELF_HEIGHT])
	if stills:
		# scale shot: the standing elf beside the couch, low side camera
		var cb := couch.global_basis
		var side_p := couch.global_position - cb.z.normalized() * 0.75 + cb.x.normalized() * 1.45
		await walk_path(side_p, h)
		elf.call("face", -cb.x)
		clean_screen()
		# low camera out in front, inside the room: pick the clearest direction (walls / furniture)
		var look_at_p := elf.global_position.lerp(couch.global_position, 0.35) + Vector3(0, 0.25, 0)
		var best_d := 0.0
		var best_dir := -cb.z.normalized()
		var sp := main.get_world_3d().direct_space_state
		for k in 9:
			var dir := (-cb.z.normalized()).rotated(Vector3.UP, deg_to_rad(-60.0 + 15.0 * k))
			var hq := PhysicsRayQueryParameters3D.create(look_at_p, look_at_p + dir * 2.2 + Vector3(0, 0.15, 0), 4)
			var hh := sp.intersect_ray(hq)
			var dd := 2.2 if hh.is_empty() else look_at_p.distance_to(hh.position)
			if dd > best_d + 0.05:
				best_d = dd
				best_dir = dir
		var cam_d := clampf(best_d - 0.2, 0.8, 1.6)
		cut_look(look_at_p + best_dir * cam_d + Vector3(0, 0.15, 0), look_at_p)
		await _wait(0.6)
		await grab("elf_scale")
		(elf.get("camera") as Camera3D).current = true
	var targets := [["couch", couch, -couch.global_basis.z.normalized(), 0.8]]
	for b: Node3D in beds:
		targets.append(["bed (%s)" % b.name, b, b.global_basis.x.normalized(), (1.8 if str(b.name).contains("Double") else 1.2) * 0.5 + 0.45])
	for tg in targets:
		var piece: Node3D = tg[1]
		var out_dir: Vector3 = tg[2]
		var center := floor_under(piece.global_position + Vector3(0, 0.05, 0))
		var approach := center + out_dir * float(tg[3])
		if absf(elf.global_position.y - center.y) > 0.5:
			await tour_to(h, "Kid's room" if str(piece.name).begins_with("BedKid") else "Bedroom")
		# try both sides (one may be against a wall / blocked)
		var reached := await walk_path(approach, h)
		if not reached:
			approach = center - out_dir * float(tg[3])
			reached = await walk_path(approach, h)
		elf.set("control_enabled", false)
		elf.set("crouching", true)
		await _frames(3)
		var under := await walk_to(center, 8.0)
		await _frames(6)
		var d := Vector2(elf.global_position.x - center.x, elf.global_position.z - center.z).length()
		var hid := bool(elf.get("hidden"))
		var can_stand: bool = elf.call("_can_stand")
		print("[hide] %s %s: approach %s, under=%s (%.2f m from centre), crouched=%s, hidden=%s, can stand=%s" % [h.name, tg[0],
				"ok" if reached else "blocked", under, d, elf.get("crouched"), hid, can_stand])
		# under a couch the elf can't stand up; a bed (0.24 m) has room to stand, but only crouched counts as hidden
		if not (under and hid and (str(piece.get_meta("tier", "")) == "HIGH" or not can_stand)):
			fail("%s: crouched elf not fully hidden under the %s" % [h.name, tg[0]])
		# a sleeper nearby doesn't notice a hidden elf
		if str(tg[0]).begins_with("bed"):
			var r: Node3D = null
			for rr in it.get("residents"):
				if int(rr.state) == 0 and (rr as Node3D).global_position.distance_to(elf.global_position) < 2.0:
					r = rr
			if r:
				var a0 := float(r.get("awareness"))
				await _wait(1.0)
				print("[hide] %s awareness while hidden: %.3f -> %.3f" % [r.get("resident_name"), a0, float(r.get("awareness"))])
				if float(r.get("awareness")) > a0 + 0.001:
					fail("%s noticed a hidden elf" % r.get("resident_name"))
		if stills:
			var still := "elf_undercouch" if tg[0] == "couch" else "elf_underbed"
			if not FileAccess.file_exists(dir.path_join(still + ".png")) or tg[0] == "couch":
				clean_screen()
				var yaw: Node3D = elf.get("cam_yaw")
				yaw.rotation.y = atan2(out_dir.x, out_dir.z)  # camera outside (behind the elf), looking in
				(elf.get("cam_pitch") as Node3D).rotation.x = deg_to_rad(-4)
				elf.call("face", -out_dir)
				(elf.get("camera") as Camera3D).current = true
				await _wait(0.8)
				gadgets.get("hidden_icon").visible = true
				await grab(still)
		await walk_to(approach, 6.0)
		elf.set("crouching", false)
		await _frames(4)
		elf.set("control_enabled", true)


# =================================================================================================

func int_check(m: Node3D, d: String) -> void:
	_init_check(m, d)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _wait(2.5)
	var houses := [m.get_node("HouseFlat"), m.get_node("HouseSteep"), m.get_node("HouseSlick")]
	var first := true
	for h: Node3D in houses:
		print("[check] ---- %s ----" % h.name)
		if not await land(h):
			continue
		if bool(h.get("fire_lit")):
			var t0 := Time.get_ticks_msec()
			while bool(h.get("fire_lit")) and Time.get_ticks_msec() - t0 < 4000:
				mission.call("roof_icer", h, 1.0 / 60.0)
				await main.get_tree().process_frame
			print("[check] roof Icer on %s: fire_lit=%s" % [h.name, h.get("fire_lit")])
		if first:
			var top: Vector3 = h.call("get_chimney_top_world")
			var sl: Vector3 = main.get("sleigh").global_position
			var side := (sl - top)
			side.y = 0
			side = side.normalized()
			cut_look(top + side * 4.0 + side.cross(Vector3.UP) * 3.0 + Vector3(0, 2.6, 0), top + Vector3(0, -0.6, 0))
			await _wait(0.5)
			await grab("int_chimney_prompt")
		await enter_and_capture(h, first)
		await wall_door_check(h)
		var it: Node3D = h.get("interior")
		var tour: Array = it.get("tour")
		for step in tour:
			var reached := await walk_path(h.to_global(step[1]), h)
			if str(step[0]) != "via":
				print("[check] %s: %s %s" % [h.name, step[0], "reached" if reached else "NOT reached (at %s)" % h.to_local(elf.global_position)])
			if not reached and str(step[0]) != "via":
				fail("%s: elf couldn't reach %s" % [h.name, step[0]])
		# room stills from the elf's camera, the elf in each room
		var suffix := "" if first else "_" + str(h.name).to_lower().replace("house", "")
		var rooms := {"Living": "int_living", "Kitchen": "int_kitchen", "Bedroom": "int_bedroom", "Kid's room": "int_kidsroom"}
		if roof_type_of(h) == 2:
			rooms["Hall"] = "int_stairs"
		for rn in rooms:
			await room_shot(h, rn, rooms[rn] + suffix)
		await hide_check(h, first)
		await tier_check(h)
		if not first:
			var shots: Dictionary = it.get("shots")
			cut_look(h.to_global(shots.fireplace[0]), h.to_global(shots.fireplace[1]))
			await _wait(0.5)
			await grab("int_fireplace" + suffix)
		if first:
			# elf's own third-person view in the living room + interior FPS
			(elf.get("camera") as Camera3D).current = true
			elf.global_position = h.to_global(it.get("hearth_point")) + Vector3(0.0, 0.05, 1.2)
			await walk_to(h.to_global(it.get("hearth_point")) + Vector3(0.3, 0, 1.0))
			await fps_here("interior (elf cam, %s)" % h.name)
		elf.global_position = h.to_global(it.get("hearth_point")) + Vector3(0.0, 0.05, 0.8)
		if bool(it.get("fire_was_lit")) and not bool(h.get("fire_lit")):
			gadgets.call("relight")  # Fire Launcher: leave no evidence
			print("[check] relit the fire in %s before leaving: %s" % [h.name, h.get("fire_lit")])
			await _wait(0.5)
		await exit_house()
		first = false
	# window view from outside: flat house living-room window on the street side
	var flat: Node3D = houses[0]
	clean_screen()
	var wl := Vector3(float(flat.get("width")) * 0.5, 1.7, -3.0)
	cut_look(flat.to_global(wl + Vector3(4.2, -0.2, 1.6)), flat.to_global(wl))
	await _wait(0.6)
	await grab("int_window")
	print("[check] intcheck %s" % ("PASS" if ok else "FAIL"))
	m.get_tree().quit()


# =================================================================================================

func gadget_check(m: Node3D, d: String) -> void:
	_init_check(m, d)
	await _wait(2.5)
	var h: Node3D = m.get_node("HouseSteep")
	print("[gadget] lit fireplace at %s: %s" % [h.name, h.get("fire_lit")])
	if not await land(h):
		m.get_tree().quit()
		return
	# Fireplace Icer from the roof
	var top: Vector3 = h.call("get_chimney_top_world")
	cut_look(top + Vector3(2.6, 1.6, 2.4), top + Vector3(0, -0.3, 0))
	(m.get("hud") as CanvasLayer).visible = false
	var shot := false
	var frames := 0
	while bool(h.get("fire_lit")) and frames < 900:  # counted in frames so a slow machine still gets the full hold
		frames += 1
		mission.call("roof_icer", h, 1.0 / 60.0)
		await main.get_tree().process_frame
		if not shot and frames > 66:
			shot = true
			await grab("gadget_icer")
	print("[gadget] roof icer: fire_lit=%s frozen=%s meter=%.2f" % [h.get("fire_lit"), h.get("fire_frozen"), (h.get("interior") as Node).get("freeze_meter")])
	if bool(h.get("fire_lit")):
		fail("icer did not put the fire out")
	await enter_and_capture(h, false)
	var it: Node3D = h.get("interior")
	(elf.get("camera") as Camera3D).current = true
	var hearth := h.to_global(it.get("hearth_point"))
	var res: Array = it.get("residents")
	var dad: Node3D = null
	for r in res:
		if bool(r.get("adult")):
			dad = r
	# --- Glow-Gogs + Snore-o-Meter in the bedroom
	for step in it.get("tour"):
		await walk_path(h.to_global(step[1]))
		if str(step[0]) == "Bedroom":
			break
	gadgets.call("_set_goggles", true)
	aim_at(dad.global_position)
	gadgets.call("select", 1)
	gadgets.call("snore_ping")
	room_cam(h, dad.global_position.lerp(elf.global_position, 0.5) + Vector3(0, 0.3, 0))
	await _wait(0.5)
	await grab("gadget_goggles")
	(elf.get("camera") as Camera3D).current = true
	print("[gadget] goggles on, snore ping done (night factor %.2f)" % gadgets.call("night_factor"))
	# --- Snooze dart at Dad, a stray dart into the wall, magnet it back
	gadgets.call("select", 0)
	var before: int = gadgets.get("darts_left")
	aim_at(dad.global_position + Vector3(0, 0.1, 0))
	await _frames(2)
	gadgets.call("fire_dart")
	await _wait(1.6)
	print("[gadget] dart at %s -> state %d (DARTED=2)" % [dad.get("resident_name"), dad.get("state")])
	if int(dad.get("state")) != 2:
		fail("dart did not knock out %s" % dad.get("resident_name"))
	var wall_p := elf.global_position + (elf.get("camera") as Camera3D).global_basis.z * -1.0
	var room_dir := Vector3(-1, 0, 0) if elf.global_position.x > h.global_position.x else Vector3(1, 0, 0)
	aim_at(elf.global_position + room_dir * 3.0 + Vector3(0, -0.4, 0.8))
	await _frames(2)
	gadgets.call("fire_dart")
	await _wait(0.8)
	var darts_now: Array = gadgets.get("darts_in_house")
	print("[gadget] darts left %d (was %d), %d in the house" % [gadgets.get("darts_left"), before, darts_now.size()])
	gadgets.call("_set_goggles", false)
	# aim at the stray dart: highlight + prompt
	var stray: Node3D = darts_now[darts_now.size() - 1] if darts_now.size() > 0 else null
	if stray:
		aim_at(stray.global_position)
		await _frames(3)
		gadgets.call("_update_magnet_target")
		await _frames(2)
		print("[gadget] magnet target: %s, prompt '%s'" % [gadgets.get("_targeted_dart") != null, gadgets.get("prompt").text])
		var spring: SpringArm3D = elf.get("spring")
		spring.spring_length = 2.2
		await _wait(0.3)
		await grab("gadget_darts")
		spring.spring_length = float(elf.get("camera_distance"))
		if gadgets.get("_targeted_dart") == null:
			fail("Dart Magnet didn't target the aimed dart")
		else:
			gadgets.call("magnet_pull")
			await _wait(0.6)
	await magnet_range_test(h)
	# --- Tuck Trolley: load Dad, wheel him back, tuck in
	gadgets.call("select", 2)
	await walk_path(dad.global_position + (h.to_global(it.get("hearth_point")) - dad.global_position).normalized() * 0.7)
	gadgets.call("load_resident", dad)
	await _wait(0.6)
	var bed_w := it.to_global((dad.get("bed_xform") as Transform3D).origin)
	var mid := elf.global_position.lerp(Vector3(bed_w.x, elf.global_position.y, bed_w.z), 0.4)
	await walk_to(mid, 4.0)
	room_cam(h, elf.global_position + Vector3(0, 0.35, 0), 1.3)
	await _wait(0.4)
	await grab("gadget_trolley")
	(elf.get("camera") as Camera3D).current = true
	gadgets.call("tuck")
	await _wait(1.0)
	print("[gadget] trolley: %s state %d (ASLEEP=0)" % [dad.get("resident_name"), dad.get("state")])
	# pick up any darts on the floor by walking over them
	for dd in (gadgets.get("darts_in_house") as Array).duplicate():
		if is_instance_valid(dd):
			await walk_path(dd.global_position)
			await _frames(5)
			if is_instance_valid(dd) and (gadgets.get("darts_in_house") as Array).has(dd):
				# it's tucked beside or under the furniture: crawl after it (crouched route)
				var stood_at := elf.global_position
				elf.set("control_enabled", false)
				elf.set("crouching", true)
				await _frames(3)
				await walk_path(dd.global_position, null, true)
				await _frames(5)
				await walk_path(stood_at, null, true)
				elf.set("crouching", false)
				await _frames(3)
				elf.set("control_enabled", true)
	print("[gadget] darts after pickup: %d/%d, in house %d" % [gadgets.get("darts_left"), gadgets.get("darts_per_run"), (gadgets.get("darts_in_house") as Array).size()])
	# --- The Ledger on the kid's door
	var door: Node3D = it.get("kid_door")
	var door_out := floor_under(door.global_position + (h.to_global(Vector3(0.4, 0.4, 0.0)) - door.global_position).normalized() * 1.6)
	await walk_path(door_out)
	aim_at(door.global_position)
	gadgets.call("select", 5)
	await _frames(2)
	gadgets.call("scan_ledger")
	print("[gadget] ledger: %s" % gadgets.get("ledger_result"))
	# --- Fit-Ghost at the tree
	var spots: Array = it.get("present_spots")
	var tree_w := it.to_global(it.get("tree_pos"))
	var free_i := 0
	for i in spots.size():
		if not bool(spots[i].taken):
			free_i = i
			break
	var spot_w := it.to_global(spots[free_i].pos)
	await walk_path(spot_w + (hearth - spot_w).normalized() * Vector3(1, 0, 1) * 1.3)
	aim_at(spot_w)
	gadgets.call("select", 3)
	await _frames(4)
	await _wait(0.3)
	await grab("gadget_fitghost")
	print("[gadget] fit-ghost over spot %d fits=%s" % [gadgets.get("_ghost_spot"), gadgets.get("_ghost_fits")])
	gadgets.call("place_present")
	print("[gadget] presents placed %d" % gadgets.get("presents_placed"))
	# --- Puff-Possum on a stocking
	await walk_path(hearth + Vector3(0, 0, 0.9))
	var st: Node3D = (it.get("stockings") as Array)[0]
	aim_at(st.global_position + Vector3(0, -0.25, 0))
	gadgets.call("puff_stocking", st)
	await _wait(0.5)
	gadgets.call("fill_stocking", st)
	print("[gadget] stocking puffed=%s filled=%s" % [st.get_meta("puffed"), st.get_meta("filled")])
	# --- Fire Launcher: relight
	var fpw := h.to_global(it.get("fireplace_spawn")) + Vector3(0, 0.35, 0)
	await walk_path(hearth + Vector3(0.5, 0, 1.4))
	aim_at(fpw)
	gadgets.call("select", 7)
	gadgets.call("relight")
	await _wait(0.25)
	await grab("gadget_relight")
	print("[gadget] relit: fire_lit=%s" % h.get("fire_lit"))
	# --- overuse the Icer indoors: fire out again, pipes frost, crack, burst
	gadgets.call("select", 6)
	aim_at(fpw)
	Input.action_press("gadget_use")
	var pipe: Dictionary = (it.get("pipes") as Array)[0]
	var t0 := Time.get_ticks_msec()
	while int(pipe.state) < 2 and Time.get_ticks_msec() - t0 < 9000:
		aim_at(fpw)
		await main.get_tree().process_frame
	Input.action_release("gadget_use")
	print("[gadget] icer overuse: meter %.2f, pipe state %d (2 = burst), fire_lit=%s" % [it.get("freeze_meter"), pipe.state, h.get("fire_lit")])
	if int(pipe.state) != 2:
		fail("pipes didn't burst on Icer overuse")
	await _wait(2.5)
	var sp: Vector3 = it.to_global(pipe.spray_pos)
	cut_look(sp + Vector3(1.6, 0.4, 2.4), sp + Vector3(0, -0.5, 0.3))
	await _wait(0.4)
	await grab("gadget_burstpipe")
	(elf.get("camera") as Camera3D).current = true
	# leave a dart behind + the fire out: exit should warn first, then let us leave
	aim_at(elf.global_position + Vector3(1.5, -0.3, 1.5))
	gadgets.call("select", 0)
	gadgets.call("fire_dart")
	await _wait(0.6)
	await walk_path(hearth)
	var probs: Array = gadgets.call("exit_problems")
	print("[gadget] exit problems: %s" % ", ".join(probs))
	var first_try: bool = mission.call("try_exit")
	print("[gadget] first F at hearth climbed out: %s (expect false = warning)" % first_try)
	await _wait(0.4)
	await grab("gadget_exitwarning")
	mission.call("try_exit")
	await wait_mode(0, 15.0)
	var log: Array = gadgets.get("evidence_log")
	print("[gadget] evidence log: %s" % str(log))
	print("[gadget] darts for the rest of the run: %d/%d" % [gadgets.get("darts_left"), gadgets.get("darts_per_run")])
	print("[gadget] gadgetcheck %s" % ("PASS" if ok else "FAIL"))
	m.get_tree().quit()


## Dart Magnet range = 20 x the elf height, measured elf to dart: catches at 19.5 eh, refuses at 20.5 eh.
func magnet_range_test(h: Node3D) -> void:
	var it: Node3D = h.get("interior")
	var rng: float = gadgets.call("magnet_range")
	var space := main.get_world_3d().direct_space_state
	var back_to := elf.global_position
	var found := false
	var spot := Vector3.ZERO
	var dir := Vector3.ZERO
	for step in it.get("tour"):
		var p := floor_under(h.to_global(step[1]))
		for k in 36:
			var dv := Vector3(cos(k * TAU / 36.0), 0, sin(k * TAU / 36.0))
			var far := floor_under(p + dv * ES.m(20.5) + Vector3(0, 0.2, 0))
			if absf(far.y - p.y) > 0.05:
				continue
			# clear sight from both the muzzle and the camera pivot, nothing overhead, and no wall
			# right behind (the camera sits there)
			var clear := true
			var ch := float(elf.get("camera_height"))
			var cd := float(elf.get("camera_distance"))
			for seg: Array in [[p + Vector3(0, ES.m(0.6), 0), far + Vector3(0, 0.05, 0) + dv * 0.15],
					[p + Vector3(0, ch, 0), far + Vector3(0, 0.05, 0) + dv * 0.15],
					[p + Vector3(0, 0.05, 0), p + Vector3(0, ch + 0.3, 0)],
					[p + Vector3(0, ch, 0), p + Vector3(0, ch + 0.25, 0) - dv * (cd + 0.2)]]:
				if not space.intersect_ray(PhysicsRayQueryParameters3D.create(seg[0], seg[1], 4)).is_empty():
					clear = false
			if clear:
				found = true
				spot = p
				dir = dv
				break
		if found:
			break
	if not found:
		fail("magnet test: no %.1f m clear line of sight in %s" % [ES.m(20.5), h.name])
		return
	elf.global_position = spot + Vector3(0, 0.02, 0)
	elf.velocity = Vector3.ZERO
	await _frames(4)
	var results := []
	for eh: float in [19.5, 20.5]:
		var d: Node3D = gadgets.call("_make_dart")
		it.add_child(d)
		var dp := elf.global_position + dir * ES.m(eh)
		d.global_position = floor_under(dp + Vector3(0, 0.1, 0)) + Vector3(0, 0.015, 0)
		d.set_meta("landed", true)
		(gadgets.get("darts_in_house") as Array).append(d)
		gadgets.set("darts_left", int(gadgets.get("darts_left")) - 1)
		await _frames(3)
		var yaw: Node3D = elf.get("cam_yaw")
		yaw.global_position = elf.global_position + Vector3(0, float(elf.get("camera_height")), 0)
		aim_at(d.global_position)
		await main.get_tree().physics_frame
		yaw.global_position = elf.global_position + Vector3(0, float(elf.get("camera_height")), 0)
		aim_at(d.global_position)
		gadgets.call("_update_magnet_target")
		var dist := d.global_position.distance_to(elf.global_position)
		var targeted: bool = gadgets.get("_targeted_dart") == d
		var caught := false
		if targeted:
			var before: int = gadgets.get("darts_left")
			gadgets.call("magnet_pull")
			var t0 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t0 < 4000 and int(gadgets.get("darts_left")) == before:
				await main.get_tree().process_frame
			caught = int(gadgets.get("darts_left")) > before
		else:
			gadgets.call("magnet_pull")  # pressing G with nothing targeted does nothing
			await _frames(3)
			caught = not is_instance_valid(d) or not (gadgets.get("darts_in_house") as Array).has(d)
		print("[gadget] magnet at %.1f elf heights (%.2f m, range %.2f m = 20 x %.2f m): targeted=%s caught=%s" % [eh, dist, rng, ES.ELF_HEIGHT, targeted, caught])
		results.append([eh, targeted, caught])
		if is_instance_valid(d) and (gadgets.get("darts_in_house") as Array).has(d):
			gadgets.call("_collect_dart", d, false)  # tidy up: walk over and pick it up
	if not (results[0][1] and results[0][2]) or results[1][1] or results[1][2]:
		fail("Dart Magnet range: expected catch at 19.5 eh and refusal at 20.5 eh")
	elf.global_position = back_to
	await _frames(3)


# =================================================================================================

func fx_shots(m: Node3D, d: String) -> void:
	_init_check(m, d)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var cam: Camera3D = m.get("camera")
	cam.set("locked", true)
	await _wait(3.0)
	cam.look_at_from_position(Vector3(4.6, 1.5, -22.0), Vector3(-1.0, 2.2, -70), Vector3.UP)
	await _wait(1.5)
	await grab("fx_street")
	await fps_here("street view with fog + particles")
	var h: Node3D = m.get_node("HouseSteep")
	var top: Vector3 = h.call("get_chimney_top_world")
	cam.look_at_from_position(top + Vector3(5.5, 2.0, 6.0), top + Vector3(-2.0, 0.5, -3.0), Vector3.UP)
	await _wait(1.5)
	await grab("fx_chimney")
	var flat: Node3D = m.get_node("HouseFlat")
	if await land(flat):
		await enter_and_capture(flat, false)
		var it: Node3D = flat.get("interior")
		var mist := preload("res://scripts/fx.gd").green_mist(28)
		flat.add_child(mist)
		mist.global_position = flat.to_global(it.get("fireplace_spawn")) + Vector3(0, 0.15, 0)
		preload("res://scripts/fx.gd").burst(mist)
		var shots: Dictionary = it.get("shots")
		cut_look(flat.to_global(shots.living[0]), flat.to_global(Vector3(it.get("fireplace_x"), 0.8, -3.0)))
		await _wait(0.9)
		await grab("fx_interior")
		await fps_here("interior with particles")
	m.get_tree().quit()


# =================================================================================================
# Walls + doors: the elf must never end up on the other side of a wall or a closed door.

## Open every door instantly (the room tours and A* grids assume open doorways).
func open_doors(h: Node3D) -> void:
	for dr in (h.get("interior") as Node3D).get("doors"):
		if not bool(dr.get("locked")):
			dr.call("set_open", true)
	await _frames(3)


func _clear_at(p: Vector3, ignore: Array = []) -> bool:
	var sh := BoxShape3D.new()
	sh.size = Vector3(ES.radius() * 2.0 + 0.02, ES.ELF_HEIGHT * 0.9, ES.radius() * 2.0 + 0.02)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.collision_mask = 4
	q.exclude = ignore
	q.transform = Transform3D(Basis(), p + Vector3(0, ES.ELF_HEIGHT * 0.5 + 0.03, 0))
	return main.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## Drive the elf from `start` toward `toward` for `frames` physics frames at speed_mult x walk.
func _ram(start: Vector3, toward: Vector3, frames: int, mult: float) -> void:
	elf.set("crouching", false)
	elf.global_position = start + Vector3(0, 0.02, 0)
	elf.velocity = Vector3.ZERO
	await main.get_tree().physics_frame
	elf.set("speed_mult", mult)
	elf.set("auto_target", toward)
	for i in frames:
		await main.get_tree().physics_frame
	elf.set("auto_target", Vector3.INF)
	elf.set("speed_mult", 1.0)
	elf.velocity = Vector3.ZERO


func wall_door_check(h: Node3D) -> void:
	var it: Node3D = h.get("interior")
	var space := main.get_world_3d().direct_space_state
	var body: Node = it.get_node("InteriorCollision")
	var back_to := elf.global_position
	gadgets.set("active", false)  # no prompts / residents while we ram walls
	var mult := 2.0  # 2x walk speed (no sprint yet; covers one)
	var tested := 0
	var skipped := 0
	var through := []
	var cam_tests := 0
	var cam_bad := []
	for seg: Dictionary in it.get("wall_segments"):
		var a: Vector3 = seg.a
		var b: Vector3 = seg.b
		var n: Vector3 = seg.inward
		var L := a.distance_to(b)
		var ts := [0.5] if L < 1.6 else [0.2, 0.5, 0.8]
		for t: float in ts:
			var pl := a.lerp(b, t)
			var start := h.to_global(pl + n * 0.3)
			var fl := floor_under(start + Vector3(0, 0.1, 0))
			if absf(fl.y - h.to_global(pl).y) > 0.06 or not _clear_at(fl):
				skipped += 1
				continue
			# the wall must be the first thing in front (not furniture against it)
			var q := PhysicsRayQueryParameters3D.create(fl + Vector3(0, 0.1, 0), fl + Vector3(0, 0.1, 0) - h.global_basis * n * 0.45, 4)
			var hit := space.intersect_ray(q)
			if hit.is_empty() or hit.collider != body:
				skipped += 1
				continue
			await _ram(fl, h.to_global(pl - n * 1.2) + Vector3(0, fl.y - h.to_global(pl).y, 0), 40, mult)
			tested += 1
			# camera: look into the room so the boom points back into the wall; it must pull in
			var wn := h.global_basis * n
			var yaw: Node3D = elf.get("cam_yaw")
			yaw.rotation.y = atan2(-wn.x, -wn.z)
			(elf.get("cam_pitch") as Node3D).rotation.x = deg_to_rad(-10)
			for k in 6:
				await main.get_tree().physics_frame
			var cam_depth := (h.to_local((elf.get("camera") as Camera3D).global_position) - pl).dot(n)
			cam_tests += 1
			if cam_depth < 0.012:
				cam_bad.append("%s wall at %s (camera %.3f m from the face)" % [seg.room, pl, cam_depth])
			var depth := (h.to_local(elf.global_position) - pl).dot(n)
			if depth < 0.0 or elf.global_position.y < fl.y - 0.3:
				through.append("%s wall at %s (depth %.3f)" % [seg.room, pl, depth])
	print("[walls] %s: rammed %d wall spots at %.1f m/s (%d skipped: furniture/floor), %d went through" % [h.name, tested, ES.m(float(elf.get("walk_speed_eh"))) * mult, skipped, through.size()])
	for t in through:
		print("[walls]   THROUGH: " + str(t))
	if not through.is_empty():
		fail("%s: elf went through %d wall(s)" % [h.name, through.size()])
	print("[walls] %s: camera stayed in the room at %d/%d wall spots (boom pointed into the wall)" % [h.name, cam_tests - cam_bad.size(), cam_tests])
	for t in cam_bad.slice(0, 6):
		print("[walls]   CAMERA: " + str(t))
	if not cam_bad.is_empty():
		fail("%s: camera clipped into %d wall(s)" % [h.name, cam_bad.size()])
	# doors: closed = solid from both sides; E opens it (swinging away) and the doorway is passable
	var dthrough := []
	var dpass := 0
	var dlocked := 0
	for dr in it.get("doors"):
		dr.call("set_open", false)
		await main.get_tree().physics_frame
		var mid: Vector3 = dr.call("world_mid")
		var n: Vector3 = (dr as Node3D).global_basis.z
		n.y = 0
		n = n.normalized()
		var dbody: Node = dr.get("body")
		for side: float in [1.0, -1.0]:
			var start := floor_under(mid + n * side * 0.35 + Vector3(0, 0.1, 0))
			if absf(start.y - mid.y) > 0.06 or not _clear_at(start):
				continue  # no interior floor there (the street side of the front door)
			await _ram(start, mid - n * side * 1.2, 40, mult)
			if (elf.global_position - mid).dot(n * side) < 0.0:
				dthrough.append("%s closed, side %+d" % [dr.name, int(side)])
		if bool(dr.get("locked")):
			dlocked += 1
			continue
		# open it the way the player does (E within reach), then walk through
		var side2 := 1.0
		var s0 := floor_under(mid + n * 0.4 + Vector3(0, 0.1, 0))
		if not _clear_at(s0, [dbody.get_rid()]):
			side2 = -1.0
			s0 = floor_under(mid - n * 0.4 + Vector3(0, 0.1, 0))
		elf.global_position = s0 + Vector3(0, 0.02, 0)
		elf.velocity = Vector3.ZERO
		await _frames(2)
		if gadgets.call("door_in_reach") != dr:
			fail("%s: %s not in E reach from %.2f m" % [h.name, dr.name, 0.4])
		gadgets.call("use_door", dr)
		await _wait(1.0)
		if float(dr.get("angle")) < float(dr.get("open_angle")) - 1.0:
			# it swung toward us (the far side is obstructed) and is waiting: step back out of its arc
			elf.global_position = floor_under(mid + n * side2 * 1.15 + Vector3(0, 0.1, 0)) + Vector3(0, 0.02, 0)
			elf.velocity = Vector3.ZERO
			await _wait(1.0)
		var dest := floor_under(mid - n * side2 * 0.6 + Vector3(0, 0.1, 0))
		await walk_to(dest, 4.0)
		if (elf.global_position - mid).dot(n * side2) < 0.0 and bool(dr.call("is_open")):
			dpass += 1
		else:
			dthrough.append("%s: couldn't pass once opened (angle %.0f)" % [dr.name, float(dr.get("angle"))])
	print("[doors] %s: %d doors (%d locked street door), closed doors held: %s, opened with E and walked through: %d/%d" % [h.name, (it.get("doors") as Array).size(), dlocked, "yes" if dthrough.is_empty() else "NO", dpass, (it.get("doors") as Array).size() - dlocked])
	for t in dthrough:
		print("[doors]   PROBLEM: " + str(t))
	if not dthrough.is_empty():
		fail("%s: door problems: %d" % [h.name, dthrough.size()])
	await open_doors(h)
	gadgets.set("active", true)
	elf.global_position = back_to
	elf.velocity = Vector3.ZERO
	await _frames(3)


## --wallcheck: land, enter and run only the wall + door check in each house (fast).
func wall_check(m: Node3D, d: String) -> void:
	_init_check(m, d)
	await _wait(2.5)
	for hn in ["HouseFlat", "HouseSteep", "HouseSlick"]:
		var h: Node3D = m.get_node(hn)
		if not await land(h):
			continue
		if bool(h.get("fire_lit")):
			var t0 := Time.get_ticks_msec()
			while bool(h.get("fire_lit")) and Time.get_ticks_msec() - t0 < 4000:
				mission.call("roof_icer", h, 1.0 / 60.0)
				await main.get_tree().process_frame
		await enter_and_capture(h, false)
		await wall_door_check(h)
		await exit_house()
	print("[check] wallcheck %s" % ("PASS" if ok else "FAIL"))
	m.get_tree().quit()


## --collisionshot: the landing street with the collision debug draw on (C / F9), plus FPS.
func collision_shot(m: Node3D, d: String) -> void:
	_init_check(m, d)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var cam: Camera3D = m.get("camera")
	cam.set("locked", true)
	await _wait(3.0)
	await fps_here("street, collision debug off")
	var dbg := preload("res://scripts/collision_debug.gd").new()
	m.add_child(dbg)
	m.set("collision_debug", dbg)
	dbg.call("set_enabled", true)
	var bodies := 0
	for n in m.find_children("*", "StaticBody3D", true, false):
		if (n as StaticBody3D).collision_layer & 1:
			bodies += 1
	print("[collision] %d solid static bodies on the sleigh layer" % bodies)
	cam.look_at_from_position(Vector3(14.0, 11.0, -6.0), Vector3(1.0, 1.0, -40.0), Vector3.UP)
	await _wait(1.0)
	await grab("landing_collision_debug")
	await fps_here("street, collision debug ON")
	cam.look_at_from_position(Vector3(4.6, 1.6, -18.0), Vector3(1.0, 2.0, -60.0), Vector3.UP)
	await _wait(0.6)
	await grab("landing_collision_debug_street")
	print("[check] collisionshot done")
	m.get_tree().quit()


# =================================================================================================
# Chimney stills + entry video (--chimshots=dir)
# =================================================================================================

var _rec_on := false
var _rec_paused := false  ## fps_here pauses frame recording: the per-frame readback + JPEG save is what dragged the old rope swing figure to 24 fps
var _rec_n := 0


## Records every rendered frame (960 px JPEG named with its time in ms) until _rec_on goes false;
## the box stitches them into an MP4 with the real frame timings.
func _record(sub: String) -> void:
	var rd := dir.path_join(sub)
	DirAccess.make_dir_recursive_absolute(rd)
	_rec_on = true
	_rec_n = 0
	var t0 := Time.get_ticks_msec()
	while _rec_on:
		await RenderingServer.frame_post_draw
		if _rec_paused:
			continue
		var img := main.get_viewport().get_texture().get_image()
		img.resize(960, int(960.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
		img.save_jpg(rd.path_join("f%05d_%07d.jpg" % [_rec_n, Time.get_ticks_msec() - t0]), 0.88)
		_rec_n += 1


func chim_exterior(h: Node3D, name: String, dist := 2.1) -> void:
	var g: Dictionary = mission.call("_chim_geo", h)
	var mouth: Vector3 = g.mouth
	var fwd: Vector3 = g.fwd
	var side: Vector3 = g.side
	cut_look(mouth + fwd * dist + side * dist * 0.62 + Vector3(0, dist * 0.32, 0), mouth + Vector3(0, -0.55, 0))
	(mission.get("cut_cam") as Camera3D).fov = 50.0
	var pr: Label = gadgets.get("prompt")
	pr.visible = false
	clean_screen()
	await _wait(0.6)
	await grab(name)
	pr.visible = true


func _hide_signs(h: Node3D) -> void:
	# the big billboard house-type sign shows through the sky in the low flue shots
	for c in h.get_children():
		if c is Label3D and (c as Label3D).font_size == 72:
			(c as Label3D).visible = false


func chim_shots(m: Node3D, d: String) -> void:
	_init_check(m, d)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _wait(2.5)
	var flat: Node3D = m.get_node("HouseFlat")
	if not await land(flat):
		m.get_tree().quit()
		return
	clean_screen()
	await chim_exterior(flat, "chim_exterior")
	await chim_exterior(flat, "chim_exterior_wide", 3.6)
	_record("chimvid")
	mission.call("enter", flat)
	_hide_signs(flat)
	await wait_phase("crown")
	clean_screen()
	await wait_phase("peek")
	await _wait(0.95)
	await grab("chim_peek")
	await wait_phase("hook")
	await _wait(0.3)
	await grab("chim_hook")
	await wait_phase("abseil")
	await _wait(1.1)
	await grab("chim_descent")
	await wait_phase("chamber")
	await _wait(0.5)
	await grab("chim_chamber")
	await wait_phase("damper")
	await _wait(0.2)
	await grab("chim_damper")
	await wait_phase("fireplace")
	await _wait(0.9)
	await grab("chim_emerge")
	await wait_mode(2)
	await _wait(0.4)
	_rec_on = false
	print("[check] recorded %d entry frames" % _rec_n)
	clean_screen()
	# the way out: winch up and climb out of the open flue
	var it: Node3D = flat.get("interior")
	elf.global_position = flat.to_global(it.get("hearth_point")) + Vector3(0, 0.05, 0)
	await _wait(0.3)
	if not bool(mission.call("try_exit")):
		mission.call("try_exit", true)
	await wait_phase("winch")
	await _wait(0.6)
	clean_screen()
	await grab("chim_winch")
	await wait_phase("climb_out")
	await _wait(0.75)
	await grab("chim_climbout")
	await wait_mode(0, 15.0)
	# lit and iced looks on the other two chimneys
	var steep: Node3D = m.get_node("HouseSteep")
	var slick: Node3D = m.get_node("HouseSlick")
	steep.call("set_fire", true)
	await chim_exterior(steep, "chim_exterior_lit")
	slick.call("freeze_fire")
	await chim_exterior(slick, "chim_exterior_iced")
	print("[check] chimshots %s" % ("PASS" if ok else "FAIL"))
	m.get_tree().quit()


## The chimney as the player sees it: from the sleigh chase camera (both modes) after landing,
## a close look (two distances, down into the open flue) and a side view against the roof, on the flat and the steep
## house.
func chim_view(m: Node3D, d: String) -> void:
	_init_check(m, d)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _wait(2.5)
	var cam: Camera3D = main.get("camera")
	for hn in ["HouseFlat", "HouseSteep"]:
		var h: Node3D = m.get_node(hn)
		var tag := "flat" if hn == "HouseFlat" else "steep"
		if not await land(h):
			continue
		clean_screen()
		var pr: Label = gadgets.get("prompt")
		pr.visible = false
		cam.current = true
		cam.call("snap")
		await _wait(0.8)
		await grab("chimview_%s_chase" % tag)
		cam.call("toggle_mode")
		cam.call("snap")
		await _wait(0.8)
		await grab("chimview_%s_top" % tag)
		cam.call("toggle_mode")
		cam.call("snap")
		await chim_exterior(h, "chimview_%s_close" % tag, 1.2)
		await chim_exterior(h, "chimview_%s_crown" % tag, 1.0)
		# side-on, level with the roof, to see how it meets the roof
		var g: Dictionary = mission.call("_chim_geo", h)
		var mouth: Vector3 = g.mouth
		var side: Vector3 = g.side
		var base: Vector3 = h.call("get_chimney_base_world")
		print("chimview %s: cap %.2f m above base, flue %.2f m" % [tag, mouth.y - base.y, float(h.get("flue_size"))])
		var fwd: Vector3 = g.fwd
		cut_look(base.lerp(mouth, 0.35) + fwd * 2.4 + side * 0.4 + Vector3(0, 0.3, 0), base.lerp(mouth, 0.45))
		await _wait(0.6)
		await grab("chimview_%s_side" % tag)
		pr.visible = true
		cam.current = true
	print("[check] chimview %s" % ("PASS" if ok else "FAIL"))
	m.get_tree().quit()


# =================================================================================================
# Elf hat: seated on the head, folds under low furniture (elf_fix_*, elf_under_tv)
# =================================================================================================

func elf_shots(m: Node3D, d: String) -> void:
	_init_check(m, d)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _wait(2.5)
	var flat: Node3D = m.get_node("HouseFlat")
	if not await land(flat):
		m.get_tree().quit()
		return
	await enter_and_capture(flat, false)
	clean_screen()
	(gadgets.get("hotbar") as Control).visible = false
	(gadgets.get("info") as Control).visible = false
	var it: Node3D = flat.get("interior")
	var hearth := flat.to_global(it.get("hearth_point"))
	var cam: Camera3D = mission.get("cut_cam")
	# close-ups of the elf standing on the hearth rug
	elf.set("control_enabled", false)
	# out on open floor a little way into the room (clear of the fireplace and its prompts), with
	# clear lines to a camera in front and to the side
	var space := m.get_world_3d().direct_space_state
	var tour: Array = it.get("tour")
	var into := flat.to_global((tour[1] as Array)[1]) - hearth
	into.y = 0
	into = into.normalized() if into.length() > 0.01 else Vector3(0, 0, 1)
	var spot := hearth + into * 0.7
	var fwd := into
	var found := false
	for k in 16:
		var dk := into.rotated(Vector3.UP, k * TAU / 16.0)
		var p0 := hearth + dk * (0.6 + 0.1 * (k % 3))
		if _underside(p0) != INF or not _capsule_fits(p0, float(elf.call("fit_height", "stand"))):
			continue
		var hp := p0 + Vector3(0, 0.15, 0)
		var sk := dk.cross(Vector3.UP)
		var clear := true
		for to: Vector3 in [hp + dk * 0.55, hp + sk * 0.55, hp - dk * 0.5]:
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(hp, to, 4 | 1)).is_empty():
				clear = false
		if clear:
			spot = p0
			fwd = dk
			found = true
			break
	print("[elfhat] close-up spot %s (clear %s)" % [spot, found])
	elf.global_position = spot + Vector3(0, 0.01, 0)
	elf.velocity = Vector3.ZERO
	elf.call("face", fwd)
	await _frames(10)
	var side := fwd.cross(Vector3.UP)
	var head := elf.global_position + Vector3(0, 0.15, 0)
	cam.fov = 40.0
	cut_look(head + fwd * 0.42 + Vector3(0, 0.03, 0), head - Vector3(0, 0.04, 0))
	await _wait(0.5)
	await grab("elf_fix_front")
	cut_look(head + side * 0.42 + Vector3(0, 0.03, 0), head - Vector3(0, 0.04, 0))
	await _wait(0.5)
	await grab("elf_fix_side")
	# under the TV unit: walk in standing (it ducks by itself, the hat folds), elf camera like play
	var tv: MeshInstance3D = null
	var tier := ""
	for e in it.get("tiered_pieces"):
		if str((e[0] as Node).get_meta("piece")) == "TVUnit":
			tv = e[0]
			tier = e[1]
	if tv == null:
		fail("no TV unit in the flat house")
	else:
		var cen := Furn.mesh_of("TVUnit").get_aabb().get_center()
		var at := tv.global_position + tv.global_basis * Vector3(cen.x, 0, cen.z)
		var under := _underside(at + Vector3(0, 0.005, 0))
		print("[elfhat] TV unit tier %s, gap %.3f m" % [tier, under - at.y])
		elf.set("crouching", false)
		elf.set("crouch_tac", false)
		elf.call("_set_shape", false, false)
		var r := await _walk_under(at)
		print("[elfhat] walk in/out under the TV unit (%s): stances %s, worst mesh poke %+.1f mm, reached %s" % [tier, r[1], float(r[0]) * 1000.0, r[2]])
		print("[elfhat]   worst: %s" % _worst_name)
		if float(r[0]) > 0.001:
			fail("elf mesh pokes %.1f mm up through the TV unit" % (float(r[0]) * 1000.0))
		# again, and stop underneath for the shot from the elf camera
		elf.set("auto_target", at)
		for i in 200:
			await m.get_tree().physics_frame
			if Vector2(elf.global_position.x - at.x, elf.global_position.z - at.z).length() < 0.05:
				break
		elf.set("auto_target", Vector3.INF)
		await _frames(20)
		var poke := _mesh_poke(elf)
		print("[elfhat] under the TV unit: stance %s, hat fold %.2f, hat top %.1f mm under the unit, mesh poke %+.1f mm" % [elf.call("stance"), float(elf.get("_hat_fold")), (under - (elf.call("hat_top") as Vector3).y) * 1000.0, poke * 1000.0])
		if poke > 0.001:
			fail("elf mesh pokes %.1f mm through the TV unit while under it" % (poke * 1000.0))
		elf.call("activate_camera")
		await _frames(30)
		await grab("elf_under_tv")
		# side-on, low, to see the folded hat right under the unit
		var mdl := elf.get("model") as Node3D
		var sd := mdl.global_basis.x.normalized()
		cam.fov = 45.0
		cut_look(elf.global_position + sd * 0.38 + Vector3(0, 0.08, 0), elf.global_position + Vector3(0, 0.08, 0))
		await _wait(0.5)
		await grab("elf_under_tv_side")
	print("[check] elfshots %s" % ("PASS" if ok else "FAIL"))
	m.get_tree().quit()


# =================================================================================================
# Elf bumping into walls and furniture (--bumpcheck=dir): no mesh inside anything
# =================================================================================================

## How deep the elf's mesh is inside walls or furniture (m): every few vertices is tested with a
## point query, and for those inside, a ray from the elf's middle (at that height) finds the surface.
func _mesh_inside(e: Node3D) -> Array:
	var space := main.get_world_3d().direct_space_state
	var worst := 0.0
	var wn := ""
	var model: Node3D = e.get("model")
	var c := e.global_position
	var pq := PhysicsPointQueryParameters3D.new()
	pq.collision_mask = 4
	pq.exclude = [(e as CollisionObject3D).get_rid()]
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if not m.is_visible_in_tree() or m.mesh == null or m.name == "DartPistol" or str(m.name).begins_with("Candy"):
			continue
		var xf := m.global_transform
		var v: PackedVector3Array = m.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for k in range(0, v.size(), 4):
			var w := xf * v[k]
			pq.position = w
			if space.intersect_point(pq, 1).is_empty():
				continue
			var from := Vector3(c.x, w.y, c.z)
			var q := PhysicsRayQueryParameters3D.create(from, w, 4)
			q.exclude = [(e as CollisionObject3D).get_rid()]
			var hit := space.intersect_ray(q)
			var depth := (w - from).length() - ((hit.position as Vector3) - from).length() if not hit.is_empty() else 0.0
			if depth > worst:
				worst = depth
				wn = m.name
	return [worst, wn]


## Drive the elf into walls and furniture in each stance (straight at them from 0.45 m, pushing
## on for about two seconds) and measure how far any part of its mesh goes in.
func bump_check(m: Node3D, d: String) -> void:
	_init_check(m, d)
	await _wait(2.0)
	var flat: Node3D = m.get_node("HouseFlat")
	if not await land(flat):
		m.get_tree().quit()
		return
	await enter_and_capture(flat, false)
	var it: Node3D = flat.get("interior")
	var space := m.get_world_3d().direct_space_state
	elf.set("control_enabled", false)
	elf.set("auto_stance", false)
	var targets := []
	for step in it.get("tour"):
		var p0: Vector3 = flat.to_global(step[1])
		for k in 8:
			var dd := Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0))
			var a := p0 + Vector3(0, 0.05, 0)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, a + dd * 1.4, 4))
			if hit.is_empty() or (hit.position as Vector3).distance_to(a) < 0.5:
				continue
			if absf((hit.normal as Vector3).y) > 0.5:  # a walkable ramp (the hearth's edge), not a wall
				continue
			targets.append([Vector3((hit.position as Vector3).x, p0.y, (hit.position as Vector3).z), dd, str((hit.collider as Node).name)])
		if targets.size() >= 14:
			break
	var worst := {"stand": [0.0, ""], "crouch": [0.0, ""], "crawl": [0.0, ""]}
	for t in targets:
		var hp: Vector3 = t[0]
		var dd: Vector3 = t[1]
		for st in ["stand", "crouch", "crawl"]:
			elf.set("crouching", st == "crawl")
			elf.set("crouch_tac", st == "crouch")
			elf.call("_set_shape", st == "crawl", st == "crouch")
			elf.global_position = hp - dd * 0.45 + Vector3(0, 0.02, 0)
			elf.velocity = Vector3.ZERO
			elf.call("face", dd)
			await _frames(8)
			elf.set("auto_target", hp + dd * 0.3)
			for i in 110:
				await main.get_tree().physics_frame
				if i % 3 == 0:
					var r := _mesh_inside(elf)
					if float(r[0]) > float(worst[st][0]):
						worst[st] = [float(r[0]), "%s into %s" % [r[1], t[2]]]
			elf.set("auto_target", Vector3.INF)
	for st in worst:
		print("[bump] %s: %d runs at walls/furniture, deepest mesh inside %.1f mm (%s)" % [st, targets.size(), float(worst[st][0]) * 1000.0, worst[st][1]])
		if float(worst[st][0]) > 0.006:
			fail("elf %s pokes %.1f mm into %s" % [st, float(worst[st][0]) * 1000.0, worst[st][1]])
	elf.set("crouching", false)
	elf.set("crouch_tac", false)
	elf.set("auto_stance", true)
	print("[check] bumpcheck %s" % ("PASS" if ok else "FAIL"))
	m.get_tree().quit()


# =================================================================================================
# Furniture height tiers
# =================================================================================================

func _capsule_fits(at: Vector3, h: float) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = ES.radius()
	cap.height = h
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = 4
	q.transform = Transform3D(Basis(), at + Vector3(0, h * 0.5 + 0.01, 0))
	return main.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## Every tiered piece: the crawl capsule fits under all three tiers, the tactical crouch fits under
## MID and HIGH but not LOW, standing fits under HIGH only. Then the elf is put under one piece of
## each tier in the matching stance and must be flagged hidden (and unable to get taller there).
func tier_check(h: Node3D) -> void:
	var it: Node3D = h.get("interior")
	var counts := {"LOW": 0, "MID": 0, "HIGH": 0}
	var probe := {}
	for e in it.get("tiered_pieces"):
		var mi: MeshInstance3D = e[0]
		var tn: String = e[1]
		counts[tn] += 1
		var cen := Furn.mesh_of(str(mi.get_meta("piece"))).get_aabb().get_center()
		var at := mi.global_position + mi.global_basis * Vector3(cen.x, 0, cen.z)
		# full stance heights with the hat folded (elf.fit_height), not just the collision capsule
		var crawl := _capsule_fits(at, float(elf.call("fit_height", "crawl")))
		var crouch := _capsule_fits(at, float(elf.call("fit_height", "crouch")))
		var stand := _capsule_fits(at, float(elf.call("fit_height", "stand")))
		var want := [true, tn != "LOW", tn == "HIGH"]
		var got := [crawl, crouch, stand]
		var okp: bool = want == got
		print("[tiers] %s %-11s %-4s gap %.3f m (%.2f eh): crawl %s crouch %s stand %s %s" % [h.name, mi.get_meta("piece"), tn, float(mi.get_meta("gap")),
				float(mi.get_meta("gap")) / ES.ELF_HEIGHT, crawl, crouch, stand, "ok" if okp else "WRONG"])
		if not okp:
			fail("%s: %s (%s tier) fit test crawl/crouch/stand = %s, expected %s" % [h.name, mi.name, tn, got, want])
		if okp and not probe.has(tn) and absf(at.y - elf.global_position.y) < 0.5:
			probe[tn] = at
	for tn in counts:
		if counts[tn] == 0:
			fail("%s has no %s furniture" % [h.name, tn])
	print("[tiers] %s: LOW %d, MID %d, HIGH %d" % [h.name, counts.LOW, counts.MID, counts.HIGH])
	# hidden under each tier, in the stance that fits there
	var back := elf.global_position
	elf.set("control_enabled", false)
	for tn in probe:
		var at: Vector3 = probe[tn]
		elf.set("crouching", tn == "LOW")
		elf.set("crouch_tac", tn == "MID")
		elf.call("_set_shape", tn == "LOW", tn == "MID")
		elf.global_position = at + Vector3(0, 0.01, 0)
		elf.velocity = Vector3.ZERO
		await _frames(8)
		var hid := bool(elf.get("hidden"))
		var st: String = elf.call("stance")
		var taller := bool(elf.call("_can_stand")) if tn != "HIGH" else false
		if tn == "LOW":
			taller = taller or bool(elf.call("can_crouch"))
		var under := _underside(at)
		var poke := _mesh_top(elf) - under
		print("[tiers] %s: elf %s under a %s piece: hidden=%s, could get taller=%s, mesh top %.1f mm vs underside (%+.1f mm)" % [h.name, st, tn, hid, taller, (_mesh_top(elf) - at.y) * 1000.0, poke * 1000.0])
		if not hid or taller:
			fail("%s: %s elf under a %s piece hidden=%s taller=%s" % [h.name, st, tn, hid, taller])
		if poke > 0.001:
			fail("%s: elf mesh pokes %.1f mm up through a %s piece" % [h.name, poke * 1000.0, tn])
	# walking in and out under each tier standing: the elf ducks by itself and the hat folds, and
	# no part of the mesh ever goes up through the furniture
	for tn in probe:
		var at: Vector3 = probe[tn]
		elf.set("crouching", false)
		elf.set("crouch_tac", false)
		elf.call("_set_shape", false, false)
		var r := await _walk_under(at)
		print("[tiers] %s: walking in/out under a %s piece standing: stances %s, worst poke %+.1f mm, reached %s" % [h.name, tn, r[1], float(r[0]) * 1000.0, r[2]])
		if float(r[0]) > 0.001:
			fail("%s: elf mesh pokes %.1f mm up through a %s piece while moving" % [h.name, float(r[0]) * 1000.0, tn])
	elf.set("auto_target", Vector3.INF)
	elf.set("crouching", false)
	elf.set("crouch_tac", false)
	elf.call("_set_shape", false, false)
	elf.global_position = back
	await _frames(4)
	elf.set("control_enabled", true)


## World y of the underside of whatever is right above p (furniture), or INF.
func _underside(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.01, 0), p + Vector3(0, 0.6, 0), 4)
	var hit := main.get_world_3d().direct_space_state.intersect_ray(q)
	return INF if hit.is_empty() else (hit.position as Vector3).y


## Highest vertex of the elf's visible meshes (world y).
func _mesh_top(e: Node3D) -> float:
	var top := -INF
	for mi in (e.get("model") as Node3D).find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.is_visible_in_tree() or m.mesh == null:
			continue
		var xf := m.global_transform
		for si in m.mesh.get_surface_count():
			for v: Vector3 in m.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				top = maxf(top, (xf * v).y)
	return top


var _poke_name := ""
var _worst_name := ""


## How far any elf vertex is above the furniture underside straight above it (m, + = through).
func _mesh_poke(e: Node3D) -> float:
	var worst := -INF
	var space := main.get_world_3d().direct_space_state
	var cache := {}
	for mi in (e.get("model") as Node3D).find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.is_visible_in_tree() or m.mesh == null:
			continue
		var xf := m.global_transform
		for si in m.mesh.get_surface_count():
			var vs: PackedVector3Array = m.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for k in range(0, vs.size(), 2):
				var w := xf * vs[k]
				var key := Vector2i(int(floor(w.x / 0.01)), int(floor(w.z / 0.01)))
				var c: float
				if cache.has(key):
					c = cache[key]
				else:
					var from := Vector3(w.x, e.global_position.y + 0.02, w.z)
					var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 0.5, 0), 4)
					var hit := space.intersect_ray(q)
					c = INF if hit.is_empty() else (hit.position as Vector3).y
					cache[key] = c
				if c != INF and w.y - c > worst:
					worst = w.y - c
					_poke_name = "%s (%.0f mm up, stance %s)" % [m.name, (w.y - e.global_position.y) * 1000.0, e.call("stance")]
	return worst


## Drive the elf (standing, no crouch keys) from beside a piece to under it and back out again.
## Returns [worst mesh poke (m), stances seen, reached].
func _walk_under(at: Vector3) -> Array:
	var space := main.get_world_3d().direct_space_state
	var start := at
	# the nearest open floor about 0.45 m away
	for k in 16:
		var d := Vector3(cos(k * TAU / 16.0), 0, sin(k * TAU / 16.0))
		var p := at + d * 0.45
		if _underside(p) == INF and _capsule_fits(p, float(elf.call("fit_height", "stand"))) \
				and space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.05, 0), p + Vector3(0, 0.05, 0), 4)).is_empty():
			start = p
			break
	elf.global_position = start + Vector3(0, 0.01, 0)
	elf.velocity = Vector3.ZERO
	await _frames(6)
	var worst := -INF
	var seen := []
	var reached := false
	_worst_name = ""
	for leg in [at, start]:
		elf.set("auto_target", leg)
		for i in 150:
			await main.get_tree().physics_frame
			var pk := _mesh_poke(elf)
			if pk > worst:
				worst = pk
				_worst_name = _poke_name
			var st: String = elf.call("stance")
			if seen.is_empty() or seen[-1] != st:
				seen.append(st)
			var dd := Vector2(elf.global_position.x - leg.x, elf.global_position.z - leg.z).length()
			if dd < 0.05:
				if leg == at:
					reached = true
				break
	elf.set("auto_target", Vector3.INF)
	return [worst, " > ".join(seen), reached]


## /furn_tiers.jpg: the three tiers side by side (coffee tables), an elf under each in the stance
## that fits: crawling under LOW, crouching under MID, standing under HIGH.
func furn_tiers_shot(m: Node3D, d: String) -> void:
	_init_check(m, d)
	await _wait(2.0)
	var h: Node3D = m.get_node("HouseFlat")
	var base := h.to_global(Vector3(-2.0, 0, float(h.get("depth")) * 0.5 + 3.2))
	var q := PhysicsRayQueryParameters3D.create(base + Vector3(0, 5, 0), base + Vector3(0, -5, 0), 1)
	var hit := m.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		base = hit.position
	var right := h.global_basis.x.normalized()
	var fwd := h.global_basis.z.normalized()
	var Elf := preload("res://scripts/elf.gd")
	var tiers := [["LOW", ES.GAP_LOW_EH, "crawl"], ["MID", ES.GAP_MID_EH, "crouch"], ["HIGH", ES.GAP_HIGH_EH, "stand"]]
	for i in 3:
		var p := base + right * (i - 1) * 0.85
		var t: Array = tiers[i]
		var mi := Furn.spawn("SideTable", m, p, rad_to_deg(h.global_rotation.y), true, 1.0, ES.m(float(t[1])))
		mi.visibility_range_end = 0.0
		var e := Elf.new()
		m.add_child(e)
		e.puppet = true
		e.global_position = p + fwd * 0.02
		e.call("face", fwd)
		e.call("_set_shape", t[2] == "crawl", t[2] == "crouch")
		var lb := Label3D.new()
		lb.text = "%s  gap %.2f eh = %.3f m\n%s fits" % [t[0], t[1], ES.m(float(t[1])), t[2]]
		lb.font_size = 40
		lb.pixel_size = 0.0013
		lb.outline_size = 10
		lb.modulate = [Color(1, 0.6, 0.5), Color(1, 0.9, 0.5), Color(0.6, 1, 0.6)][i]
		m.add_child(lb)
		lb.global_position = p + Vector3(0, 0.88, 0) + fwd * 0.1
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	clean_screen()
	(main.get("hud") as CanvasLayer).visible = false
	cut_look(base + fwd * 2.35 + Vector3(0, 0.38, 0), base + Vector3(0, 0.4, 0))
	(mission.get("cut_cam") as Camera3D).fov = 50.0
	await _wait(1.5)
	await grab("furn_tiers")
	m.get_tree().quit()


# =================================================================================================
# Crook-Line rope tech + climbing + stances (--ropecheck=<dir>)
# =================================================================================================

var _follow_on := false
var _follow_off := Vector3.ZERO
var _follow_look := Vector3(0, 0.12, 0)


## Cut camera that trails the elf at an offset (pulled in if a wall is in the way).
func _follow_loop() -> void:
	var cam: Camera3D = mission.get("cut_cam")
	cam.current = true
	var space := main.get_world_3d().direct_space_state
	var cur := Vector3.INF
	while _follow_on:
		var tgt := elf.global_position + _follow_look
		var want := tgt + _follow_off
		var q := PhysicsRayQueryParameters3D.create(tgt, want, 4)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			want = tgt.lerp(hit.position, 0.85)
		cur = want if cur == Vector3.INF else cur.lerp(want, 1.0 - exp(-7.0 * main.get_process_delta_time()))
		cam.look_at_from_position(cur, tgt, Vector3.UP)
		await main.get_tree().process_frame


func _follow(off: Vector3, look := Vector3(0, 0.12, 0)) -> void:
	_follow_off = off
	_follow_look = look
	if not _follow_on:
		_follow_on = true
		_follow_loop()


func _wait_rope(rope: Node3D, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while bool(rope.call("busy")) and Time.get_ticks_msec() - t0 < timeout * 1000.0:
		await main.get_tree().physics_frame


func _nearest(list: Array, p: Vector3) -> Dictionary:
	var best := {}
	var bd := INF
	for a in list:
		var d := (a.pos as Vector3).distance_to(p)
		if d < bd:
			bd = d
			best = a
	return best


func rope_check(m: Node3D, d: String) -> void:
	_init_check(m, d)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _wait(2.5)
	var h: Node3D = m.get_node("HouseFlat")
	if not await land(h):
		m.get_tree().quit()
		return
	await enter_and_capture(h, false)
	clean_screen()
	(gadgets.get("hotbar") as Control).visible = false
	(gadgets.get("info") as Control).visible = false
	var windowed := DisplayServer.get_name() != "headless"
	if windowed:
		_record("ropevid")
	var rope: Node3D = gadgets.get("rope")
	var it: Node3D = h.get("interior")
	var hearth := h.to_global(it.get("hearth_point"))
	var anchors: Array = rope.call("anchors_world")
	var kinds := {}
	for a in anchors:
		kinds[a.name] = int(kinds.get(a.name, 0)) + 1
	print("[rope] %d anchors in %s: %s" % [anchors.size(), h.name, kinds])
	print("[rope] ranges: grapple / reticle %.0f eh = %.2f m, rappel reach %.0f eh = %.2f m, zipline shot %.0f eh = %.2f m, zipline clip-on %.0f eh = %.2f m" % [
			rope.grapple_range_eh, ES.m(rope.grapple_range_eh), rope.rappel_reach_eh, ES.m(rope.rappel_reach_eh),
			rope.zip_range_eh, ES.m(rope.zip_range_eh), rope.zip_mount_eh, ES.m(rope.zip_mount_eh)])
	var R := ES.radius()
	# ---- 1. climb the living-room bookshelf --------------------------------------------------------
	var shelf := {}
	var shelf_d := INF
	for c in it.get("climbables"):
		if str(c.name) == "Bookshelf":
			var dd := h.to_global((c.box as AABB).get_center()).distance_to(hearth)
			if dd < shelf_d:
				shelf_d = dd
				shelf = c
	if shelf.is_empty():
		fail("no bookshelf climbable")
		m.get_tree().quit()
		return
	var f: Dictionary = rope.call("_face", shelf)
	var n_w: Vector3 = (it.global_basis * (f.n as Vector3)).normalized()
	var t_w: Vector3 = (it.global_basis * (f.t as Vector3)).normalized()
	var face_w := it.to_global(Vector3((f.center as Vector3).x, float(f.bottom), (f.center as Vector3).z))
	elf.global_position = face_w + n_w * (R + 0.08) + Vector3(0, 0.01, 0)
	elf.call("face", -n_w)
	elf.velocity = Vector3.ZERO
	await _frames(6)
	_follow(n_w * 0.6 + t_w * 0.35 + Vector3(0, 0.05, 0), Vector3(0, 0.13, 0))
	rope.set("drive", {"climb": Vector2(0, -1)})
	var grabbed := bool(rope.call("try_grab"))
	if not grabbed:
		fail("couldn't grab the bookshelf (at %s)" % elf.global_position)
	var top_y := it.to_global(Vector3(0, float(f.top), 0)).y
	var floor_y := face_w.y
	var g0 := float(rope.get("stamina"))
	var shot := false
	var t0 := Time.get_ticks_msec()
	while bool(rope.call("busy")) and Time.get_ticks_msec() - t0 < 12000:
		if not shot and elf.global_position.y > floor_y + (top_y - floor_y) * 0.5:
			shot = true
			await grab("climb")
		await main.get_tree().physics_frame
	rope.set("drive", {})
	var on_top := absf(elf.global_position.y - top_y) < 0.06
	print("[rope] climb: grabbed=%s, %.2f m bookshelf, mantled on top=%s, grip %.1f -> %.1f s" % [grabbed, top_y - floor_y, on_top, g0, float(rope.get("stamina"))])
	if not on_top:
		fail("climb didn't end on top of the bookshelf (y %.2f, top %.2f)" % [elf.global_position.y, top_y])
	await _wait(0.4)
	# ---- 2. rappel back down its front (kick-off hops, a moment upside down to peek) ----------------
	var ledge := _nearest(anchors.filter(func(a: Dictionary) -> bool: return a.kind == "ledge"), elf.global_position)
	rope.call("_update_aim")
	var r_ok := bool(rope.call("_rappel_ok", ledge))
	rope.call("fire_at", ledge)
	print("[rope] rappel from %s: in reach=%s, state=%s" % [ledge.get("name", "?"), r_ok, rope.call("state_name")])
	_follow(n_w * 0.55 - t_w * 0.32 + Vector3(0, 0.12, 0), Vector3(0, 0.1, 0))
	await _wait(0.6)
	rope.set("drive", {"descend": 1.0})
	await _wait(0.35)
	rope.call("kick")
	await _wait(0.3)
	await grab("rope_rappel")
	rope.set("drive", {"descend": 0.0})
	rope.call("set_inverted", true)
	await _wait(0.7)
	var inv_ok := bool(rope.get("inverted"))
	await grab("rope_rappel_inverted")
	rope.call("set_inverted", false)
	rope.set("drive", {"descend": 1.0})
	await _wait_rope(rope, 10.0)
	rope.set("drive", {})
	var landed := absf(elf.global_position.y - floor_y) < 0.05 and not bool(rope.call("busy"))
	print("[rope] rappel: inverted peek=%s, landed on the floor=%s (y %.3f), events %s" % [inv_ok, landed, elf.global_position.y - floor_y, rope.get("log_events").slice(-6)])
	if not landed or not inv_ok:
		fail("rappel didn't finish on the floor")
	await _wait(0.5)
	# ---- 3. grapple swing from the living-room light fitting --------------------------------------
	var lamps := anchors.filter(func(a: Dictionary) -> bool: return a.name == "Light fitting")
	var lamp := _nearest(lamps, hearth)
	var lp: Vector3 = lamp.pos
	var away := (hearth - lp)
	away.y = 0
	away = away.normalized()
	# swing plane with nothing in it (no couch back to lean on)
	var space := main.get_world_3d().direct_space_state
	for k in 12:
		var dd := away.rotated(Vector3.UP, k * TAU / 12.0)
		var clear := true
		for hy: float in [0.15, 0.5, 0.9, 1.3]:
			for sg: float in [1.0, -1.0]:
				var a0 := Vector3(lp.x, floor_y + hy, lp.z)
				if not space.intersect_ray(PhysicsRayQueryParameters3D.create(a0, a0 + dd * sg * 1.1, 4)).is_empty():
					clear = false
		if clear:
			away = dd
			break
	var start := Vector3(lp.x, floor_y + 0.01, lp.z) + away * 0.9
	elf.global_position = start
	elf.velocity = Vector3.ZERO
	await _frames(4)
	var side := away.cross(Vector3.UP)
	_follow(side * 0.85 + Vector3(0, 0.12, 0), Vector3(0, 0.18, 0))
	rope.call("fire_at", lamp)
	var len0 := float(rope.get("rope_len"))
	rope.set("drive", {"reel": 1.0})
	await _wait(1.0)
	rope.set("drive", {"reel": 0.0, "pump": -away})
	var max_h := 0.0
	var minx := INF
	var maxx := -INF
	var shot2 := false
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3200:
		await main.get_tree().physics_frame
		var rel := elf.global_position - Vector3(lp.x, 0, lp.z)
		var along := rel.dot(away)
		minx = minf(minx, along)
		maxx = maxf(maxx, along)
		max_h = maxf(max_h, elf.global_position.y - floor_y)
		# pump with the swing (in phase with the velocity), like a kid on a swing
		var va := (elf.velocity as Vector3).dot(away)
		var pump := away * signf(va) if absf(va) > 0.05 else -away
		rope.set("drive", {"reel": 0.0, "pump": pump})
		if not shot2 and Time.get_ticks_msec() - t0 > 1600 and absf(along) < 0.25:
			shot2 = true
			await grab("rope_grapple")
	if not shot2:
		await grab("rope_grapple")
	var fps_swing := ""
	if windowed:
		fps_swing = await fps_here("rope swing (cut cam, %s)" % h.name, 2.0)
	var len1 := float(rope.get("rope_len"))
	rope.set("drive", {})
	rope.call("let_go", "check")
	await _wait(1.6)
	var swung := maxx - minx
	var down := elf.is_on_floor() and not bool(rope.call("busy"))
	print("[rope] grapple: rope %.2f -> %.2f m (reeled), lifted %.2f m, swing arc %.2f m, let go and landed=%s (%.2f m up)" % [len0, len1, max_h, swung, down, elf.global_position.y - floor_y])
	if len1 >= len0 - 0.3 or max_h < 0.25 or swung < 0.4 or not down:
		fail("grapple swing (reel %.2f->%.2f, lift %.2f, arc %.2f, landed %s)" % [len0, len1, max_h, swung, down])
	# ---- 4. zipline from the bookshelf top down across the room -----------------------------------
	var top_c := it.to_global(Vector3((f.center as Vector3).x, float(f.top), (f.center as Vector3).z)) - n_w * minf(R + 0.06, float(f.depth) * 0.5)
	elf.global_position = top_c + Vector3(0, 0.01, 0)
	elf.velocity = Vector3.ZERO
	await _frames(6)
	var a_pt := it.to_global(Vector3((f.center as Vector3).x, float(f.top), (f.center as Vector3).z)) - n_w * (float(f.depth) - 0.03) + Vector3(0, 0.3, 0)
	var b_pt := Vector3.INF
	for dist: float in [2.4, 2.0, 2.8, 1.8, 3.2]:
		for ang: float in [0.0, 25.0, -25.0, 45.0, -45.0]:
			var dirz := n_w.rotated(Vector3.UP, deg_to_rad(ang))
			var cand := a_pt + dirz * dist
			cand.y = floor_y + 0.03
			var drop := a_pt.y - cand.y
			if drop / dist > float(rope.zip_max_slope) * 0.95:
				continue
			if bool(rope.call("_clear", a_pt, cand)) and bool(rope.call("_clear", cand, a_pt)):
				b_pt = cand
				break
		if b_pt != Vector3.INF:
			break
	if b_pt == Vector3.INF:
		fail("no clear zipline run from the bookshelf")
	else:
		rope.call("zip_point", a_pt)
		var line: Dictionary = rope.call("zip_point", b_pt)
		if line.is_empty():
			fail("zipline refused")
		else:
			var zd := (b_pt - a_pt)
			var zside := Vector3(zd.x, 0, zd.z).normalized().cross(Vector3.UP)
			_follow(zside * 0.75 + Vector3(0, 0.1, 0), Vector3(0, 0.2, 0))
			await _wait(0.6)
			(gadgets.get("popup") as Label).text = ""
			await grab("rope_zipline_rigged")
			rope.call("ride", line)
			var shot3 := false
			t0 = Time.get_ticks_msec()
			while bool(rope.call("busy")) and Time.get_ticks_msec() - t0 < 10000:
				if not shot3 and float(rope.get("_zip_t")) > a_pt.distance_to(b_pt) * 0.4:
					shot3 = true
					await grab("rope_zipline")
				await main.get_tree().physics_frame
			await _wait(1.0)
			var end_d := Vector2(elf.global_position.x - b_pt.x, elf.global_position.z - b_pt.z).length()
			var probs: Array = gadgets.call("exit_problems")
			var ev_ok := probs.any(func(p: String) -> bool: return p.contains("zipline"))
			print("[rope] zipline: %.2f m line, slope %.2f, rode to %.2f m from anchor B, on the floor=%s, evidence while up: %s" % [
					a_pt.distance_to(b_pt), (a_pt.y - b_pt.y) / Vector2(a_pt.x - b_pt.x, a_pt.z - b_pt.z).length(), end_d,
					absf(elf.global_position.y - floor_y) < 0.06, probs])
			if end_d > 0.8 or not ev_ok:
				fail("zipline ride / evidence (end %.2f m, evidence %s)" % [end_d, ev_ok])
			var got := bool(rope.call("retrieve"))
			print("[rope] zipline reeled in=%s, lines left %d, exit problems now %s" % [got, int(rope.call("lines_left")), gadgets.call("exit_problems")])
			if int(rope.call("lines_left")) != 0:
				fail("zipline not retrieved")
	# ---- 5. stances: noise / visibility / heights ----------------------------------------------------
	_follow_on = false
	var stances := []
	elf.set("auto_target", elf.global_position)
	for st in [["stand", false, false], ["crouch", false, true], ["crawl", true, false]]:
		elf.set("crouching", st[1])
		elf.set("crouch_tac", st[2])
		await _frames(4)
		elf.velocity = Vector3(0.3, 0, 0)
		var nr := float(elf.call("noise_radius"))
		stances.append("%s %.3f m capsule, noise %.2f m, notice x%.2f" % [elf.call("stance"), ((elf.get("_cs") as CollisionShape3D).shape as CapsuleShape3D).height, nr,
				float(gadgets.get("crouch_notice_mult")) if bool(elf.get("crouched")) else float(elf.call("visibility_mult"))])
	elf.set("crouching", false)
	elf.set("crouch_tac", false)
	await _frames(4)
	elf.set("auto_target", Vector3.INF)
	elf.velocity = Vector3.ZERO
	print("[rope] stances: %s" % "; ".join(stances))
	await stance_compare(h)
	# ---- 6. lean / peek ---------------------------------------------------------------------------
	print("[rope] lean: %.2f m camera slide (%.1f eh), %.0f deg body tilt" % [ES.m(float(elf.get("lean_eh"))), float(elf.get("lean_eh")), float(elf.get("lean_angle_deg"))])
	_rec_on = false
	if windowed:
		print("[check] recorded %d rope frames" % _rec_n)
	elf.global_position = hearth + Vector3(0, 0.05, 0)
	(elf.get("camera") as Camera3D).current = true
	await exit_house()
	print("[check] ropecheck %s" % ("PASS" if ok else "FAIL"))
	m.get_tree().quit()


## Three elves side by side in the living room: standing, tactical crouch (pistol up), crawling.
func stance_compare(h: Node3D) -> void:
	var it: Node3D = h.get("interior")
	var hearth := h.to_global(it.get("hearth_point"))
	var out := (hearth - h.to_global(it.get("fireplace_spawn")))
	out.y = 0
	out = out.normalized()
	var side := out.cross(Vector3.UP)
	var base := hearth - out * 0.42  # on the hearth rug, in front of the firebox
	var Elf := preload("res://scripts/elf.gd")
	var made := []
	var labels := [["stand", false, false, "STAND  0.92 eh (0.20 m)\nnoise 12 eh"], ["crouch", false, true, "CROUCH  0.75 eh (0.165 m)\nnoise 7 eh, notice x0.65"], ["crawl", true, false, "CRAWL  0.5 eh (0.11 m)\nnoise 4 eh, notice x0.5"]]
	for i in 3:
		var p := base + side * (i - 1) * 0.3
		var e := Elf.new()
		main.add_child(e)
		e.puppet = true
		e.global_position = p
		e.call("face", out.rotated(Vector3.UP, 0.5))
		e.call("_set_shape", labels[i][1], labels[i][2])
		made.append(e)
		var lb := Label3D.new()
		lb.text = labels[i][3]
		lb.font_size = 32
		lb.pixel_size = 0.0007
		lb.outline_size = 8
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.modulate = [Color(0.7, 1, 0.7), Color(1, 0.9, 0.5), Color(1, 0.65, 0.55)][i]
		main.add_child(lb)
		lb.global_position = p + Vector3(0, 0.33, 0)
		made.append(lb)
	var ghost_pos := elf.global_position
	var cam_fov := (mission.get("cut_cam") as Camera3D).fov
	elf.set("puppet", true)
	elf.global_position = base + out * 3.0 + Vector3(0, -5, 0)  # the real elf steps out of shot
	clean_screen()
	cut_look(base + out * 0.85 + Vector3(0, 0.5, 0), base + Vector3(0, 0.12, 0))
	(mission.get("cut_cam") as Camera3D).fov = 50.0
	await _wait(1.0)
	await grab("stance_compare")
	(mission.get("cut_cam") as Camera3D).fov = cam_fov
	for n in made:
		(n as Node).queue_free()
	elf.global_position = ghost_pos
	elf.set("puppet", false)


# =================================================================================================
# Decorations (--decoshots=<dir>)
# =================================================================================================

func deco_shots(m: Node3D, d: String) -> void:
	_init_check(m, d)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _wait(2.5)
	clean_screen()
	var windowed := DisplayServer.get_name() != "headless"
	# the yards, one per landing house
	for hn in ["HouseFlat", "HouseSteep", "HouseSlick"]:
		var h: Node3D = m.get_node(hn)
		var yd := h.get_node_or_null("YardDecor")
		if yd == null:
			fail("%s has no yard decor" % hn)
			continue
		var n := yd.find_children("*", "VisualInstance3D", true, false).size()
		print("[deco] %s yard: %d visual parts" % [hn, n])
		var hx := float(h.get("width")) * 0.5
		cut_look(h.to_global(Vector3(hx + 9.5, 2.0, 4.5)), h.to_global(Vector3(hx + 2.2, 0.8, 0.0)))
		await _wait(1.2)
		var nm: String = "deco_yard" if hn == "HouseFlat" else "deco_yard_" + str(hn).substr(5).to_lower()
		await grab(nm)
		if hn == "HouseFlat" and windowed:
			await fps_here("yard (cut cam, %s)" % hn, 2.0)
	# inside: land, go in, look round the living room, then the cookies
	var flat: Node3D = m.get_node("HouseFlat")
	if not await land(flat):
		m.get_tree().quit()
		return
	await enter_and_capture(flat, false)
	clean_screen()
	(gadgets.get("hotbar") as Control).visible = false
	(gadgets.get("info") as Control).visible = false
	var it: Node3D = flat.get("interior")
	var deco := it.get_node_or_null("Decor")
	print("[deco] interior decor parts: %d" % (deco.find_children("*", "VisualInstance3D", true, false).size() if deco else 0))
	var shots: Dictionary = it.get("shots")
	cut_look(flat.to_global(shots.living[0]), flat.to_global(shots.living[1]))
	await _wait(1.0)
	await grab("deco_interior")
	# the tree + mantel from the room
	var hearth := flat.to_global(it.get("hearth_point"))
	var tree := flat.to_global(it.get("tree_pos"))
	var mid := (hearth + tree) * 0.5
	var out := (hearth - flat.to_global(it.get("fireplace_spawn")))
	out.y = 0
	out = out.normalized()
	cut_look(mid + out * 2.4 + Vector3(0, 1.1, 0), mid + Vector3(0, 0.9, 0))
	await _wait(0.8)
	await grab("deco_tree_mantel")
	# the pavlova
	var pav: Node3D = null
	for c in it.get_children():
		if c is MeshInstance3D and str(c.get_meta("piece", "")) == "DiningTable":
			pav = c
	if pav:
		cut_look(pav.global_position + Vector3(0.7, 1.2, 0.5), pav.global_position + Vector3(0.1, 0.75, 0))
		await _wait(0.8)
		await grab("deco_pavlova")
	# cookies and milk: walk up, E -> "Santa will want those"
	var cookies: Node3D = null
	for c in it.get_children():
		if c is MeshInstance3D and str(c.get_meta("piece", "")) == "CookiesMilk":
			cookies = c
	if cookies == null:
		fail("no cookies and milk")
	else:
		var cp := cookies.global_position
		var fl := flat.to_global(Vector3(0, float(it.get("floor_y")), 0))
		var spot := Vector3.INF
		for k in 12:
			var dd := Vector3(cos(k * TAU / 12.0), 0, sin(k * TAU / 12.0))
			var cand := Vector3(cp.x, fl.y + 0.01, cp.z) + dd * 0.55
			if _clear_at(cand):
				spot = cand
				break
		if spot == Vector3.INF:
			spot = Vector3(cp.x, fl.y + 0.01, cp.z) + out * 0.6
		elf.global_position = spot
		elf.velocity = Vector3.ZERO
		elf.call("face", cp - spot)
		await _frames(8)
		var sn: Node3D = gadgets.call("snack_in_reach")
		print("[deco] cookies in reach from %.2f m: %s, prompt '%s'" % [Vector2(spot.x - cp.x, spot.z - cp.z).length(), sn != null, (gadgets.get("prompt") as Label).text])
		if sn == null:
			fail("cookies not in reach for E")
		else:
			gadgets.call("look_at_snack", sn)
		var popup_text := (gadgets.get("popup") as Label).text
		print("[deco] E at the cookies: '%s' (no rule effect: exit problems %s)" % [popup_text, gadgets.call("exit_problems")])
		if popup_text != "Santa will want those":
			fail("cookie interact text")
		var side := (spot - cp)
		side.y = 0
		side = side.normalized()
		cut_look(cp + side.rotated(Vector3.UP, 0.9) * 0.75 + Vector3(0, 0.3, 0), cp + Vector3(0, -0.12, 0) + (spot - cp) * 0.3)
		await _wait(0.4)
		await grab("deco_cookies")
	if windowed:
		(elf.get("camera") as Camera3D).current = true
		elf.global_position = hearth + Vector3(0, 0.05, 0) + out * 0.3
		await _wait(0.5)
		await fps_here("interior with decorations (elf cam, %s)" % flat.name, 2.5)
	elf.global_position = hearth + Vector3(0, 0.05, 0)
	await exit_house()
	print("[check] decoshots %s" % ("PASS" if ok else "FAIL"))
	m.get_tree().quit()


# =================================================================================================
# Solid check: nothing that should be solid can be passed through (sleigh and elf, real physics)
# =================================================================================================

## Fly the sleigh at a landing-house wall and at the chimney stack, and walk the elf (physics, not
## teleports) into walls, closed doors, furniture and the fireplace in every stance. Fails if the
## sleigh or the elf's body ends up through anything, if a solid shape is disabled, if the elf's /
## sleigh's layers or masks changed, or if solid bodies went missing.
func solid_check(m: Node3D, d: String) -> void:
	_init_check(m, d)
	await _wait(2.5)
	var sl: RigidBody3D = m.get("sleigh")
	var space := m.get_world_3d().direct_space_state
	# 1) layers, masks, shapes
	if elf.collision_mask != 4:
		fail("elf collision mask is %d, want 4 (interior)" % elf.collision_mask)
	if (sl.collision_mask & 1) == 0:
		fail("sleigh mask %d doesn't include the world layer" % sl.collision_mask)
	var bodies := 0
	var disabled := []
	for n in m.find_children("*", "CollisionObject3D", true, false):
		var co: CollisionObject3D = n
		if co == elf or co == sl or not co.is_inside_tree():
			continue
		if co is StaticBody3D and (co.collision_layer & 5) != 0:
			bodies += 1
		for c in co.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).disabled and (co.collision_layer & 5) != 0 and not co is Area3D:
				disabled.append("%s/%s" % [co.name, c.name])
	print("[solid] %d solid static bodies (world + interior), %d disabled shapes" % [bodies, disabled.size()])
	if bodies < 300:
		fail("only %d solid static bodies (colliders missing?)" % bodies)
	if not disabled.is_empty():
		fail("disabled collision shapes: %s" % str(disabled.slice(0, 8)))
	var ecs: CollisionShape3D = elf.get("_cs")
	if ecs == null or ecs.disabled or ecs.shape == null:
		fail("elf body capsule missing or disabled")
	# 2) the sleigh into walls and chimneys at speed
	for hn in ["HouseFlat", "HouseSteep", "HouseSlick"]:
		var h: Node3D = m.get_node(hn)
		var c := h.global_position
		var targets := []
		for k in 4:
			var dd := Vector3(cos(k * TAU / 4.0 + 0.3), 0, sin(k * TAU / 4.0 + 0.3))
			var a := c + Vector3(0, 1.3, 0) + dd * 14.0
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, c + Vector3(0, 1.3, 0), 1, [sl.get_rid()]))
			if not hit.is_empty() and (hit.collider as Node).get_parent() is Node3D and (hit.position as Vector3).distance_to(c) < 10.0:
				targets.append(["wall", hit.position, -dd])
				break
		var mouth: Vector3 = h.call("get_chimney_mouth_world")
		var cp := mouth + Vector3(0, -0.35, 0)
		var cdir := (Vector3(c.x, cp.y, c.z) - cp)
		cdir = cdir.normalized() if cdir.length() > 0.1 else Vector3.FORWARD
		var ca := cp + cdir * 4.0  # from the roof side, towards the stack
		var chit := space.intersect_ray(PhysicsRayQueryParameters3D.create(ca, cp, 1, [sl.get_rid()]))
		if chit.is_empty():
			fail("%s: no chimney collision on the world layer" % hn)
		else:
			targets.append(["chimney", chit.position, -cdir])
		for t in targets:
			var hp: Vector3 = t[1]
			var dir: Vector3 = t[2]
			var start := hp - dir * 3.0 + Vector3(0, 0.3, 0)
			sl.call("teleport", Transform3D(Basis.looking_at(dir, Vector3.UP), start), dir * 12.0)
			await main.get_tree().physics_frame
			await main.get_tree().physics_frame
			var worst := -INF
			var crashed := false
			for i in 70:
				await main.get_tree().physics_frame
				worst = maxf(worst, (sl.global_position - hp).dot(dir))
				crashed = crashed or bool(sl.get("is_crashed"))
			print("[solid] sleigh into %s %s at 12 m/s: crashed %s, furthest %.2f m past the surface" % [hn, t[0], crashed, worst])
			if worst > 0.6 or not crashed:
				fail("sleigh went through the %s %s (%.2f m past, crashed %s)" % [hn, t[0], worst, crashed])
	sl.call("teleport", Transform3D(Basis(), Vector3(0, 30, 0)), Vector3.ZERO)
	await _wait(0.5)
	# 3) the elf into walls, doors, furniture and the fireplace
	var flat: Node3D = m.get_node("HouseFlat")
	if not await land(flat):
		print("[check] solidcheck FAIL")
		m.get_tree().quit()
		return
	sample_cut_cam(flat)
	await enter_and_capture(flat, false)
	var it: Node3D = flat.get("interior")
	elf.set("control_enabled", false)
	var etargets := []
	for step in it.get("tour"):
		var p0: Vector3 = flat.to_global(step[1])
		for k in 8:
			var dd := Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0))
			var a := p0 + Vector3(0, 0.05, 0)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, a + dd * 1.4, 4))
			if hit.is_empty() or (hit.position as Vector3).distance_to(a) < 0.5:
				continue
			if absf((hit.normal as Vector3).y) > 0.5:  # a walkable ramp (the hearth's edge), not a wall
				continue
			# only faces wider than the elf (not a door's 10 cm edge or a table leg it can slip past)
			var sd := dd.cross(Vector3.UP) * ES.radius() * 1.3
			var wide := true
			for sg: float in [-1.0, 1.0]:
				var hs := space.intersect_ray(PhysicsRayQueryParameters3D.create(a + sd * sg, a + sd * sg + dd * 1.6, 4))
				if hs.is_empty() or hs.collider != hit.collider or absf((hs.position as Vector3).distance_to(a + sd * sg) - (hit.position as Vector3).distance_to(a)) > 0.12:
					wide = false
			if not wide:
				continue
			etargets.append([Vector3((hit.position as Vector3).x, p0.y, (hit.position as Vector3).z), dd, str((hit.collider as Node).name)])
		if etargets.size() >= 24:
			break
	var r := ES.radius()
	var core := CapsuleShape3D.new()  # the elf's core: half its radius, around the knees
	core.radius = r * 0.5
	core.height = 0.06  # 3..9 cm off the floor: fits under the lowest (LOW 0.136 m) gaps
	var cq := PhysicsShapeQueryParameters3D.new()
	cq.shape = core
	cq.collision_mask = 4
	cq.exclude = [elf.get_rid()]
	var inside := 0
	var inside_n := ""
	var through := 0
	var through_n := ""
	for t in etargets:
		var hp: Vector3 = t[0]
		var dd: Vector3 = t[1]
		for st in ["stand", "crouch", "crawl"]:
			elf.set("crouching", st == "crawl")
			elf.set("crouch_tac", st == "crouch")
			elf.global_position = hp - dd * 0.45 + Vector3(0, 0.02, 0)
			elf.velocity = Vector3.ZERO
			elf.call("face", dd)
			await _frames(4)
			# doors may have swung since the targets were picked: only push at what's still there
			var a2 := hp - dd * 0.45 + Vector3(0, 0.05, 0)
			var h2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(a2, a2 + dd * 0.6, 4, [elf.get_rid()]))
			if h2.is_empty() or Vector2((h2.position as Vector3).x - hp.x, (h2.position as Vector3).z - hp.z).length() > 0.03:
				continue
			elf.set("auto_target", hp + dd * 0.5)
			var max_lat := 0.0
			for i in 100:
				await main.get_tree().physics_frame
				# went straight through: past the hit point along the push, still on the push line
				var rel := elf.global_position - hp
				var along := rel.dot(dd)
				var lateral := (Vector3(rel.x, 0, rel.z) - dd * along).length()
				max_lat = maxf(max_lat, lateral)
				if along > 0.02 and max_lat < r * 0.6:  # (auto_target paths around things: only a straight line counts)
					through += 1
					if through_n == "":
						through_n = "%s walked straight through %s (%.0f mm past)" % [st, t[2], along * 1000.0]
				if i % 2 == 0:
					# the core (half the capsule radius) must never be inside a wall, door or piece
					cq.transform = Transform3D(Basis(), elf.global_position + Vector3(0, 0.03 + core.height * 0.5, 0))
					var hits := space.intersect_shape(cq, 4)
					if not hits.is_empty():
						inside += 1
						if inside % 6 == 1:
							var hc: CollisionObject3D = hits[0].collider
							var shp := ""
							for cc in hc.get_children():
								if cc is CollisionShape3D:
									shp += "%s@%s " % [str((cc as CollisionShape3D).shape.get_class()), str((cc as Node3D).global_position)]
							print("[soliddbg] %s %s elf %s core in %s parent %s shapes %s" % [st, t[2], str(elf.global_position), hc.name, hc.get_parent().name, shp])
						if inside_n == "":
							inside_n = "%s pushing at %s: core inside %s" % [st, t[2], (hits[0].collider as Node).name]
			elf.set("auto_target", Vector3.INF)
	elf.set("crouching", false)
	elf.set("crouch_tac", false)
	print("[solid] elf: %d pushes into walls/doors/furniture, %d samples with the body core inside something %s" % [etargets.size() * 3, inside, inside_n])
	print("[solid] elf: %d samples straight through a surface %s" % [through, through_n])
	if inside > 0:
		fail("elf body went into a solid: %s" % inside_n)
	if through > 0:
		fail("elf passed through a solid: %s" % through_n)
	# 4) the elf against every part of the chimney (+ the sleigh into the crown and cap)
	await chimney_solid(m)
	# 5) the cutscene camera never inside bricks, in the other two houses' chimneys too
	_elf_free(flat.to_global(it.get("hearth_point")) + Vector3(0, 0.05, 0))
	await _frames(5)
	await exit_house()
	await sleigh_crown(m)
	for hn in ["HouseSteep", "HouseSlick"]:
		var hh: Node3D = m.get_node(hn)
		if await land(hh):
			sample_cut_cam(hh)
			await enter_and_capture(hh, false)
			await exit_house()
	print("[solid] cutscene camera: %d samples, %d inside something %s" % [_cam_samples, _cam_bad, _cam_bad_n])
	if _cam_bad > 0:
		fail("cutscene camera went into the bricks: %s" % _cam_bad_n)
	if _cam_samples < 100:
		fail("cutscene camera hardly sampled (%d)" % _cam_samples)
	print("[check] solidcheck %s" % ("PASS" if ok else "FAIL"))
	m.get_tree().quit()


# =================================================================================================
# --solidcheck, part 4: the ELF against every part of the chimney (the designer: "chimney collision was
# off"). Geometric checks against the modelled bricks, so they fail even when a collider is
# missing altogether (--break-chimney puts the old, broken collision back to prove it).
# =================================================================================================

var _cam_bad := 0
var _cam_bad_n := ""
var _cam_samples := 0


## While the chimney cutscene runs, the cutscene camera must never be inside anything solid on
## the elf layer (bricks, flue, fireplace, furniture) - and never inside the stack's bricks.
func sample_cut_cam(h: Node3D) -> void:
	var cam: Camera3D = mission.get("cut_cam")
	var space := main.get_world_3d().direct_space_state
	var t0 := Time.get_ticks_msec()
	while int(mission.get("mode")) != 1 and Time.get_ticks_msec() - t0 < 5000:
		await main.get_tree().process_frame
	var probe := SphereShape3D.new()
	probe.radius = 0.012  # about the near plane
	while int(mission.get("mode")) == 1:
		await main.get_tree().process_frame
		if not cam.current:
			continue
		_cam_samples += 1
		var p := cam.global_position
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = probe
		q.transform = Transform3D(Basis(), p)
		q.collision_mask = 4
		q.exclude = [elf.get_rid()]
		var hits := space.intersect_shape(q, 1)
		var why := ""
		if not hits.is_empty():
			why = "inside %s" % (hits[0].collider as Node).name
		elif _in_stack_bricks(h, p):
			why = "inside the stack's bricks"
		if why != "":
			_cam_bad += 1
			if _cam_bad_n == "":
				_cam_bad_n = "%s phase %s: cutscene camera at %s %s" % [h.name, str(mission.get("cut_phase")), str(p), why]


## Chebyshev distance (house frame) of world point p from the chimney's axis at its height, and
## whether p is in the brick (between the flue and the outer face) of the stack above its base.
func _stack_rel(h: Node3D, p: Vector3) -> Vector2:
	var ax: Vector3 = h.call("flue_axis_world", p.y)
	var l := h.global_basis.inverse() * (p - ax)
	return Vector2(l.x, l.z)


func _in_stack_bricks(h: Node3D, p: Vector3) -> bool:
	var base: Vector3 = h.call("get_chimney_base_world")
	var cm: Node3D = h.get("chimney_model")
	if cm == null or p.y < base.y or p.y > base.y + float(cm.get("height")):
		return false
	var l := _stack_rel(h, p)
	var d := maxf(absf(l.x), absf(l.y))
	var hf := float(h.get("flue_size")) * 0.5
	var ho := float(h.get("chimney_outer")) * 0.5
	return d > hf + 0.004 and d < ho - 0.004


func _elf_free(p: Vector3) -> void:
	elf.set("auto_target", Vector3.INF)
	elf.set("ext_control", false)
	elf.set("puppet", false)
	elf.set("control_enabled", false)
	elf.visible = true
	elf.global_position = p
	elf.velocity = Vector3.ZERO


func _core_hit(space: PhysicsDirectSpaceState3D) -> String:
	var core := CapsuleShape3D.new()
	core.radius = ES.radius() * 0.5
	core.height = 0.06
	var cq := PhysicsShapeQueryParameters3D.new()
	cq.shape = core
	cq.collision_mask = 4
	cq.exclude = [elf.get_rid()]
	cq.transform = Transform3D(Basis(), elf.global_position + Vector3(0, 0.03 + core.height * 0.5, 0))
	var hits := space.intersect_shape(cq, 1)
	return "" if hits.is_empty() else str((hits[0].collider as Node).name)


func chimney_solid(m: Node3D) -> void:
	var space := m.get_world_3d().direct_space_state
	var r := ES.radius()
	var sl: RigidBody3D = m.get("sleigh")
	var bad: Array = []
	var stats := {}
	for hn in ["HouseFlat", "HouseSteep", "HouseSlick"]:
		var h: Node3D = m.get_node(hn)
		var cm: Node3D = h.get("chimney_model")
		var base: Vector3 = h.call("get_chimney_base_world")
		var mouth: Vector3 = h.call("get_chimney_mouth_world")
		var hf := float(h.get("flue_size")) * 0.5
		var ho := float(h.get("chimney_outer")) * 0.5
		var hc := ho + 3.0 * 0.035
		var hb := h.global_basis
		# --- a) the elf walks into the stack from the roof, all four sides, all stances --------
		var roof_pushes := 0
		for k in 4:
			var dl := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)][k] as Vector3
			var dw := hb * dl
			var p0 := base + dw * (ho + 0.4)
			p0.y = mouth.y + 0.5
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p0, p0 + Vector3(0, -4.0, 0), 4, [elf.get_rid()]))
			if hit.is_empty() or (hit.position as Vector3).y < base.y - 1.5:
				if k == 0:
					bad.append("%s: no elf collision on the roof beside the chimney" % hn)
				continue
			var start: Vector3 = hit.position + Vector3(0, 0.02, 0)
			for st in ["stand", "crouch", "crawl"]:
				_elf_free(start)
				elf.set("crouching", st == "crawl")
				elf.set("crouch_tac", st == "crouch")
				elf.call("face", -dw)
				await _frames(3)
				elf.set("auto_target", base - dw * 0.5)
				var deepest := INF
				for i in 90:
					await m.get_tree().physics_frame
					var l := _stack_rel(h, elf.global_position)
					var d := maxf(absf(l.x), absf(l.y))
					if elf.global_position.y > base.y - 0.3 and elf.global_position.y < base.y + float(cm.get("height")):
						deepest = minf(deepest, d)
				elf.set("auto_target", Vector3.INF)
				roof_pushes += 1
				# the capsule's centre must stay a body radius off the bricks (4 mm slack)
				if deepest < ho + r - 0.012:
					bad.append("%s: elf (%s) walked into the stack from the roof: centre %.0f mm from the axis, bricks at %.0f mm" % [hn, st, deepest * 1000.0, ho * 1000.0])
		elf.set("crouching", false)
		elf.set("crouch_tac", false)
		# --- b) standing on the crown / cap, then walking into the open flue --------------------
		var fwd: Vector3 = cm.global_basis.z
		fwd.y = 0
		fwd = fwd.normalized()
		var on_cap := mouth + fwd * ((hf + hc) * 0.5)
		_elf_free(on_cap + Vector3(0, 0.25, 0))
		for i in 60:
			await m.get_tree().physics_frame
		var cap_y := mouth.y - 0.018 * 0.5
		var stood := elf.is_on_floor() and absf(elf.global_position.y - cap_y) < 0.03
		print("[chim] %s: elf on the cap at %.3f (cap top %.3f), on floor %s" % [hn, elf.global_position.y, cap_y, elf.is_on_floor()])
		if not stood:
			bad.append("%s: elf can't stand on the chimney cap (dropped to %.2f m, cap at %.2f m)" % [hn, elf.global_position.y, cap_y])
		# walk off the cap into the hole: the flue must be open (the elf drops in)
		elf.set("auto_target", mouth)
		for i in 50:
			await m.get_tree().physics_frame
		elf.set("auto_target", Vector3.INF)
		for i in 20:
			await m.get_tree().physics_frame
		var dropped := elf.global_position.y < mouth.y - 0.25
		print("[chim] %s: walked into the flue hole -> %.2f m below the mouth" % [hn, mouth.y - elf.global_position.y])
		if not dropped:
			bad.append("%s: the flue hole isn't open (elf stuck at %s, mouth %s)" % [hn, str(elf.global_position), str(mouth)])
		# --- c) rappel the whole flue, ramming the walls, past the damper, into the firebox -----
		var fi: Dictionary = h.get("flue_info")
		var it: Node3D = h.get("interior")
		var fsp: Vector3 = it.get("fireplace_spawn")
		var fpx := fsp.x
		var zc := fsp.z + 0.05
		var ff := fsp.y
		var path: Array = [mouth + Vector3(0, -0.15, 0)]
		var segs := ""
		if not fi.is_empty():
			path.append(h.to_global(fi.liner_bottom))
			path.append(h.to_global(Vector3((fi.chamber_top as Vector3).x, float(fi.liner_y), (fi.chamber_top as Vector3).z)))
			path.append(h.to_global(Vector3(fpx, float(fi.throat_y) + 0.12, zc + 0.03)))
			path.append(h.to_global(Vector3(fpx, ff + 0.4, zc + 0.03)))
			path.append(it.to_global(fsp + Vector3(0, 0.05, 0)))
		h.call("set_damper", 0.0)  # shut: the elf must stop on the plate
		_elf_free(path[0])
		elf.set("ext_control", true)
		var wp := 1
		var t_el := 0.0
		var escaped := ""
		var core_in := ""
		var stuck_t := 0.0
		var last := elf.global_position
		var damper_held := false
		var damper_test_t := -1.0
		var pushes := [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1)]
		var throat_w: float = h.to_global(Vector3(0, float(fi.get("throat_y", 0.0)), 0)).y
		var frames := 0
		while wp < path.size() and t_el < 30.0:
			await m.get_tree().physics_frame
			var dt := m.get_physics_process_delta_time()
			t_el += dt
			frames += 1
			var tgt: Vector3 = path[wp]
			var to := tgt - elf.global_position
			# pinned against a wall by the push it can't reach the centre line: level with it is enough
			if to.length() < 0.04 or (absf(to.y) < 0.03 and Vector2(to.x, to.z).length() < 0.11 and wp < path.size() - 1):
				wp += 1
				continue
			var push: Vector3 = hb * (pushes[int(t_el / 0.3) % 4] as Vector3)
			elf.velocity = to.normalized() * 1.0 + push * 1.6
			elf.move_and_slide()
			var p := elf.global_position
			# the damper: shut, nothing gets past the plate; after a second on it, open it
			if not fi.is_empty() and wp >= 4 and damper_test_t < 0.0 and p.y < throat_w + 0.25:
				damper_test_t = t_el
			if damper_test_t >= 0.0 and not damper_held and t_el - damper_test_t > 1.2:
				damper_held = true
				h.call("set_damper", 1.0)
			if damper_test_t >= 0.0 and not damper_held and p.y < throat_w - 0.01:
				escaped = "dropped through the shut damper (%.0f mm below the throat)" % ((throat_w - p.y) * 1000.0)
			# tunnelling: a straight line from the last position to this one crosses a surface
			# (between the centres of the capsule's bottom sphere: inside the swept body, so a
			# crossing there is a real tunnel, not the feet point grazing a ledge it slid off)
			if escaped == "" and last.distance_to(p) > 0.0005:
				var lift := Vector3(0, r, 0)
				var cr := space.intersect_ray(PhysicsRayQueryParameters3D.create(last + lift, p + lift, 4, [elf.get_rid()]))
				if not cr.is_empty():
					escaped = "went through %s at %s" % [(cr.collider as Node).name, str(cr.position)]
			# geometric: the centre must stay inside the flue / chamber / firebox (minus its radius)
			if escaped == "":
				var why := _outside_flue(h, p, r - 0.012)
				if why != "":
					escaped = why
			if core_in == "" and frames % 2 == 0:
				var ch := _core_hit(space)
				if ch != "":
					core_in = "core inside %s at %s" % [ch, str(p)]
			if p.distance_to(last) < 0.0004:
				stuck_t += dt
			else:
				stuck_t = 0.0
			if stuck_t > 2.5 and not (damper_test_t >= 0.0 and not damper_held):
				break
			last = p
		elf.set("ext_control", false)
		h.call("set_damper", 1.0)
		var fl := it.to_local(elf.global_position)
		var in_box := absf(fl.x - fpx) < 0.45 and fl.z > zc - 0.3 and fl.z < zc + 0.4 and fl.y < ff + 0.35
		print("[chim] %s: rappel %.1f s, waypoint %d/%d, damper held %s, ended %s (firebox %s) %s %s" % [hn, t_el, wp, path.size(), damper_held, str(fl), in_box, escaped, core_in])
		if escaped != "":
			bad.append("%s rappel: %s" % [hn, escaped])
		if core_in != "":
			bad.append("%s rappel: %s" % [hn, core_in])
		if not fi.is_empty() and not damper_held:
			bad.append("%s rappel: never reached the damper (stuck at %s)" % [hn, str(h.to_local(elf.global_position))])
		if not in_box:
			bad.append("%s rappel: didn't come down into the firebox (ended at %s)" % [hn, str(fl)])
		# --- d) the elf walks into the firebox's back and splayed sides, all stances -----------
		var fb_n := 0
		for dl: Vector3 in [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(-0.7, 0, -0.7), Vector3(0.7, 0, -0.7), Vector3(-1, 0, 0.35), Vector3(1, 0, 0.35)]:
			var dw := it.global_basis * dl.normalized()
			for st in ["stand", "crouch", "crawl"]:
				_elf_free(it.to_global(Vector3(fpx, ff + 0.03, zc - 0.02)))
				elf.set("crouching", st == "crawl")
				elf.set("crouch_tac", st == "crouch")
				await _frames(3)
				elf.set("auto_target", elf.global_position + dw * 1.0)
				var worst := ""
				for i in 80:
					await m.get_tree().physics_frame
					if worst == "":
						var lp := it.to_local(elf.global_position)
						worst = _firebox_violation(lp, fpx, zc, ff, r - 0.012)
						if worst == "" and i % 2 == 0:
							var ch := _core_hit(space)
							if ch != "":
								worst = "core inside %s" % ch
				elf.set("auto_target", Vector3.INF)
				fb_n += 1
				if worst != "":
					bad.append("%s firebox (%s, push %s): %s" % [hn, st, str(dl), worst])
		elf.set("crouching", false)
		elf.set("crouch_tac", false)
		# --- e) the camera spring backed into the stack never ends up in the bricks -------------
		var cam_bad := ""
		for k in 4:
			var dl := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)][k] as Vector3
			var dw := hb * dl
			var p0 := base + dw * (ho + 0.2)
			p0.y = mouth.y + 0.5
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p0, p0 + Vector3(0, -4.0, 0), 4, [elf.get_rid()]))
			if hit.is_empty() or (hit.position as Vector3).y < base.y - 1.5:
				continue
			_elf_free(hit.position + Vector3(0, 0.02, 0))
			var cy: Node3D = elf.get("cam_yaw")
			cy.global_position = elf.global_position + Vector3(0, 0.1, 0)
			cy.rotation.y = atan2(-dw.x, -dw.z)  # the arm (its +Z) points back at the stack
			var cam: Camera3D = elf.get("camera")
			for i in 40:
				await m.get_tree().physics_frame
			var cp := cam.global_position
			var pq := PhysicsPointQueryParameters3D.new()
			pq.position = cp
			pq.collision_mask = 4
			pq.exclude = [elf.get_rid()]
			if not space.intersect_point(pq, 1).is_empty() or _in_stack_bricks(h, cp) or (maxf(absf(_stack_rel(h, cp).x), absf(_stack_rel(h, cp).y)) < hf and cp.y < mouth.y and cp.y > base.y):
				cam_bad = "camera at %s is in the chimney (side %d)" % [str(cp), k]
		if cam_bad != "":
			bad.append("%s: %s" % [hn, cam_bad])
		var fx := flue_exposed(h)
		if int(fx[0]) > 0:
			bad.append("%s: %d flue collision points in open room air (invisible wall), e.g. %s" % [hn, fx[0], fx[1]])
		stats[hn] = "%d roof pushes, %d firebox pushes" % [roof_pushes, fb_n]
		print("[chim] %s done: %s" % [hn, stats[hn]])
	for b in bad:
		fail("chimney: %s" % b)
	print("[solid] chimney: %d problems %s" % [bad.size(), str(stats)])


## Is world point p (the elf's centre) outside the open flue by more than slack? Uses the modelled
## geometry (stack above the base, liner, offset, corbelled chamber; below the throat it's left to
## the firebox check).
func _outside_flue(h: Node3D, p: Vector3, inset: float) -> String:
	var fi: Dictionary = h.get("flue_info")
	var hf := float(h.get("flue_size")) * 0.5
	var base: Vector3 = h.call("get_chimney_base_world")
	if p.y >= base.y:
		var l := _stack_rel(h, p)
		var d := maxf(absf(l.x), absf(l.y))
		if d > hf - inset + 0.004:
			return "left the flue in the stack (%.0f mm off the axis, flue half %.0f mm)" % [d * 1000.0, hf * 1000.0]
		return ""
	if fi.is_empty():
		return ""
	var lp := h.to_local(p)
	var lc: Vector3 = fi.liner_bottom
	var ct: Vector3 = fi.chamber_top
	var kink_y: float = fi.kink_y
	var liner_y: float = fi.liner_y
	var throat_y: float = fi.throat_y
	var rect: Rect2
	var where := ""
	if lp.y >= kink_y:
		rect = Rect2(lc.x - hf, lc.z - hf, hf * 2.0, hf * 2.0)
		where = "liner"
	elif lp.y >= liner_y:
		var k := (lp.y - liner_y) / maxf(kink_y - liner_y, 0.001)
		var c := Vector3(ct.x, 0, ct.z).lerp(Vector3(lc.x, 0, lc.z), k)
		rect = Rect2(c.x - hf - 0.012, c.z - hf - 0.012, hf * 2.0 + 0.024, hf * 2.0 + 0.024)  # slices
		where = "offset"
	elif lp.y >= throat_y:
		var courses := 8
		var ch := float(fi.ch_h) / courses
		var kk := float(clampi(int((lp.y - throat_y) / ch), 0, courses - 1)) / float(courses - 1)
		var fpx: float = (fi.throat as Vector3).x
		var r0 := Rect2(fpx - float(fi.tw) * 0.5, float(fi.bz0), float(fi.tw), float(fi.bz1) - float(fi.bz0))
		var r1 := Rect2(ct.x - hf, ct.z - hf, hf * 2.0, hf * 2.0)
		rect = Rect2(r0.position.lerp(r1.position, kk), r0.size.lerp(r1.size, kk))
		where = "smoke chamber"
	else:
		return ""
	var g := rect.grow(-inset + 0.004)
	if lp.x < g.position.x or lp.x > g.end.x or lp.z < g.position.y or lp.z > g.end.y:
		return "left the %s at %s (open %s)" % [where, str(lp), str(rect)]
	return ""


## The elf's centre (interior-local lp) against the modelled firebox: the firebrick back (face at
## zc - 0.25 up to 0.33 m) and the two splayed sides (19.3 deg, inner faces 5 cm in from x = +-0.41).
func _firebox_violation(lp: Vector3, fpx: float, zc: float, ff: float, need: float) -> String:
	var x := lp.x - fpx
	var z := lp.z - zc
	var y := lp.y - ff
	if y < 0.4 and absf(x) < 0.3 and z < -0.25 + need:
		return "into the firebox back (%.0f mm past the clearance)" % ((-0.25 + need - z) * 1000.0)
	for g: float in [-1.0, 1.0]:
		var ps := deg_to_rad(19.3) * g
		var n := Vector3(cos(ps), 0, -sin(ps)) * g  # outward
		var along := Vector3(sin(ps), 0, cos(ps))
		var rel := Vector3(x - g * 0.41, 0, z)
		if absf(rel.dot(along)) > 0.28 or y > 0.94:
			continue
		var into := rel.dot(n) + 0.05  # > 0: past the inner face, outward
		if into > -need and rel.dot(n) < 0.06:
			return "into the %s firebox side (%.0f mm past the clearance)" % ["left" if g < 0 else "right", (into + need) * 1000.0]
	return ""

## The sleigh into each chimney's crown and cap at 12 m/s (run with the sleigh flying, not parked).
func sleigh_crown(m: Node3D) -> void:
	var space := m.get_world_3d().direct_space_state
	var sl: RigidBody3D = m.get("sleigh")
	var bad: Array = []
	for hn in ["HouseFlat", "HouseSteep", "HouseSlick"]:
		var h: Node3D = m.get_node(hn)
		var cm: Node3D = h.get("chimney_model")
		var mouth: Vector3 = h.call("get_chimney_mouth_world")
		# --- f) the sleigh into the crown and the cap at speed ---------------------------------
		var cdir := Vector3(h.global_position.x - mouth.x, 0, h.global_position.z - mouth.z)
		cdir = cdir.normalized() if cdir.length() > 0.1 else Vector3.FORWARD
		var stack_top_w: float = cm.to_global(Vector3(0, float(cm.get("stack_top")), 0)).y
		for tg in [["crown", stack_top_w + 0.1], ["cap", mouth.y - 0.035]]:
			var cp := Vector3(mouth.x, float(tg[1]), mouth.z)
			var ca := cp + cdir * 4.0
			var chit := space.intersect_ray(PhysicsRayQueryParameters3D.create(ca, cp, 1, [sl.get_rid()]))
			if chit.is_empty():
				bad.append("%s: no sleigh collision on the chimney %s" % [hn, tg[0]])
				continue
			var hp: Vector3 = chit.position
			var dir := -cdir
			sl.call("teleport", Transform3D(Basis.looking_at(dir, Vector3.UP), hp - dir * 3.0), dir * 12.0)
			await m.get_tree().physics_frame
			await m.get_tree().physics_frame
			var worst := -INF
			var crashed := false
			var embedded := 0
			var hc := float(h.get("chimney_outer")) * 0.5 + 3.0 * 0.035
			for i in 70:
				await m.get_tree().physics_frame
				worst = maxf(worst, (sl.global_position - hp).dot(dir))
				crashed = crashed or bool(sl.get("is_crashed"))
				# through = the sleigh's centre inside the crown, below the cap top (bouncing up
				# over the cap after the crash is fine)
				var l := _stack_rel(h, sl.global_position)
				if maxf(absf(l.x), absf(l.y)) < hc - 0.05 and sl.global_position.y < mouth.y - 0.02:
					embedded += 1
			print("[solid] sleigh into %s chimney %s at 12 m/s: crashed %s, furthest %.2f m along, %d frames inside the crown" % [hn, tg[0], crashed, worst, embedded])
			if embedded > 0 or not crashed:
				bad.append("sleigh went through the %s chimney %s (%d frames inside, crashed %s)" % [hn, tg[0], embedded, crashed])
		sl.call("teleport", Transform3D(Basis(), Vector3(0, 30, 0)), Vector3.ZERO)
		await _wait(0.3)
	for b in bad:
		fail("chimney: %s" % b)


## --chimcolshot=<dir>: chimney collision debug stills (F9 view): the stack, crown and cap from the
## roof, and the fireplace / firebox colliders from the living room.
func chim_collision_shot(m: Node3D, d: String) -> void:
	_init_check(m, d)
	await _wait(2.5)
	var dbg := preload("res://scripts/collision_debug.gd").new()
	m.add_child(dbg)
	m.set("collision_debug", dbg)
	dbg.call("set_enabled", true)
	clean_screen()
	for hn in ["HouseFlat", "HouseSteep"]:
		var h: Node3D = m.get_node(hn)
		var mouth: Vector3 = h.call("get_chimney_mouth_world")
		var c := h.global_position
		var out := Vector3(mouth.x - c.x, 0, mouth.z - c.z).normalized()
		var side := out.cross(Vector3.UP)
		cut_look(mouth - out * 1.3 + side * 1.1 + Vector3(0, 0.75, 0), mouth + Vector3(0, -0.5, 0))
		await _wait(0.6)
		await grab("chim_collision_debug" if hn == "HouseFlat" else "chim_collision_debug_steep")
	var flat: Node3D = m.get_node("HouseFlat")
	var it: Node3D = flat.get("interior")
	var fp: Vector3 = it.to_global(it.get("fireplace_spawn"))
	var hearth: Vector3 = it.to_global(it.get("hearth_point"))
	var o := hearth - fp
	o.y = 0
	o = o.normalized()
	var sd := o.cross(Vector3.UP)
	cut_look(fp + o * 1.5 + sd * 0.6 + Vector3(0, 0.8, 0), fp + Vector3(0, 0.5, 0))
	await _wait(0.6)
	await grab("chim_collision_debug_fireplace")
	print("[check] chimcolshot done")
	m.get_tree().quit()


## --flueprobe: print where each flue runs (house-local) against the rooms' ceilings.
func flue_probe(m: Node3D, _d: String) -> void:
	main = m
	await m.get_tree().physics_frame
	await m.get_tree().physics_frame
	for hn in ["HouseFlat", "HouseSteep", "HouseSlick"]:
		var h: Node3D = m.get_node(hn)
		var it: Node3D = h.get("interior")
		var fi: Dictionary = h.get("flue_info")
		var ceils := []
		for r in it.get("rooms"):
			var rc: Rect2 = r.rect
			ceils.append("%s f%.2f c%.2f x%.1f..%.1f z%.1f..%.1f" % [r.name, float(r.floor), float(r.ceil), rc.position.x, rc.end.x, rc.position.y, rc.end.y])
		print("[probe] %s base %s wall_h %.2f ceiling_top %.2f fi %s" % [hn, str(h.get("chimney_base")), float(h.get("wall_height")), float(it.get("ceiling_top")), str(fi)])
		print("[probe]   rooms: %s" % "; ".join(ceils))
		print("[probe]   flue collision in open room air: %s" % str(flue_exposed(h)))
	m.get_tree().quit()



## Flue collision that sits in open room air (an invisible wall): points of the FlueCollision boxes
## that are inside a room (between its floor and ceiling) but not inside the interior's own solids
## (the chimney breast, walls, ceilings). Returns [count, first example].
func flue_exposed(h: Node3D) -> Array:
	var space := h.get_world_3d().direct_space_state
	var it: Node3D = h.get("interior")
	var ib: CollisionObject3D = it.get("_body")
	var fc := h.get_node_or_null("FlueCollision")
	if fc == null:
		return [0, ""]
	var n := 0
	var ex := ""
	for c in fc.get_children():
		if not c is CollisionShape3D or not (c as CollisionShape3D).shape is BoxShape3D or (c as Node).has_meta("visible_solid"):
			continue
		var cs := c as CollisionShape3D
		var sz := ((cs.shape as BoxShape3D).size)
		for ix in 3:
			for iy in 3:
				for iz in 3:
					var lp := Vector3((ix - 1) * 0.45 * sz.x, (iy - 1) * 0.45 * sz.y, (iz - 1) * 0.45 * sz.z)
					var wp := cs.global_transform * lp
					var hp := it.to_local(wp)
					var in_room := false
					for r in it.get("rooms"):
						var rc: Rect2 = r.rect
						if rc.has_point(Vector2(hp.x, hp.z)) and hp.y > float(r.floor) and hp.y < float(r.ceil):
							in_room = true
					if not in_room:
						continue
					var pq := PhysicsPointQueryParameters3D.new()
					pq.position = wp
					pq.collision_mask = 4
					var covered := false
					for hit in space.intersect_point(pq, 8):
						if hit.collider == ib:
							covered = true
					if not covered:
						n += 1
						if ex == "":
							ex = "house-local %s" % str(h.to_local(wp))
	return [n, ex]


## --firevis=<dir>: the flue and fire looks (chim_inside_after = the chim_descent framing,
## fire_topdown / fire_topdown_flue / fire_room / fire_iced / fire_iced_topdown), with fps.
func fire_vis(m: Node3D, d: String) -> void:
	_init_check(m, d)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _wait(2.5)
	var flat: Node3D = m.get_node("HouseFlat")
	if not await land(flat):
		m.get_tree().quit()
		return
	clean_screen()
	mission.call("enter", flat)
	_hide_signs(flat)
	await wait_phase("abseil")
	await _wait(1.1)
	clean_screen()
	await grab("chim_inside_after")
	_vis_diag(flat)
	var big := []
	for mi in flat.find_children("*", "MeshInstance3D", true, false):
		var v := mi as MeshInstance3D
		if v.mesh is BoxMesh and (v.mesh as BoxMesh).size.x > 10.0 and v.is_visible_in_tree():
			big.append(v)
	for k in big.size():
		(big[k] as Node3D).visible = false
		await grab("dbg_hide%d" % k)
		var mat = (big[k] as MeshInstance3D).material_override
		print("[vis] hid %d %s %s hole_count=%s min=%s max=%s" % [k, big[k].get_path(), (big[k] as MeshInstance3D).mesh.size, mat.get_shader_parameter("hole_count") if mat is ShaderMaterial else "-", mat.get_shader_parameter("hole_min") if mat is ShaderMaterial else "", mat.get_shader_parameter("hole_max") if mat is ShaderMaterial else ""])
		(big[k] as Node3D).visible = true
	fps_diag = false
	print("[firevis] descent: %s" % await fps_here("descent", 0.6))
	await wait_phase("chamber")
	await _wait(0.5)
	await grab("chim_chamber_after")
	await wait_phase("damper")
	await _wait(0.2)
	await grab("chim_damper_after")
	await wait_mode(2)
	await _wait(0.4)
	clean_screen()
	for c in m.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	elf.visible = false
	var it: Node3D = flat.get("interior")
	var fi: Dictionary = flat.get("flue_info")
	var fp: Vector3 = it.to_global(it.get("fireplace_spawn"))
	var hearth: Vector3 = it.to_global(it.get("hearth_point"))
	var o := hearth - fp
	o.y = 0
	o = o.normalized()
	var sd := o.cross(Vector3.UP)
	var throat: Vector3 = flat.to_global(fi.throat)
	var cam: Camera3D = mission.get("cut_cam")
	for state in ["lit", "iced"]:
		if state == "lit":
			flat.call("set_fire", true)
		else:
			flat.call("freeze_fire")
		await _wait(2.0)
		var tag := "fire" if state == "lit" else "fire_iced"
		cam.fov = 50.0
		cut_look(fp + o * 1.25 + sd * 0.35 + Vector3(0, 0.45, 0), fp + Vector3(0, 0.15, 0))
		await _wait(0.5)
		await grab("fire_room" if state == "lit" else "fire_iced")
		print("[firevis] %s room: %s" % [state, await fps_here(state + " room", 1.5)])
		# straight down from the throat (what the elf sees as he drops into the firebox)
		flat.call("set_flue_view", true)
		cam.fov = 60.0
		cam.look_at_from_position(throat + Vector3(0, -0.02, -0.02), fp + Vector3(0, 0, 0.01), o)
		await _wait(0.5)
		await grab("fire_topdown" if state == "lit" else "fire_iced_topdown")
		print("[firevis] %s topdown: %s" % [state, await fps_here(state + " topdown", 1.5)])
		# from up in the smoke chamber, down past the damper
		cam.fov = 46.0
		cam.look_at_from_position(throat + Vector3(0, 0.55, -0.05), fp + Vector3(0, 0, 0.05), o)
		await _wait(0.4)
		await grab("fire_topdown_flue" if state == "lit" else "fire_iced_topdown_flue")
		flat.call("set_flue_view", false)
	flat.call("set_fire", false)
	print("[check] firevis done")
	m.get_tree().quit()


func _vis_diag(h: Node3D) -> void:
	var cam := main.get_viewport().get_camera_3d()
	print("[vis] cam %s fwd %s fov %.0f elf %s" % [h.to_local(cam.global_position), -cam.global_basis.z, cam.fov, h.to_local(elf.global_position)])
	print("[vis] flue_info %s" % [h.get("flue_info")])
	var vs := main.get_viewport().get_visible_rect().size
	var rd := cam.project_ray_normal(Vector2(vs.x * 0.4, vs.y * 0.7))
	for d: float in [0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4]:
		var q := cam.global_position + rd * d
		for mi in main.find_children("*", "MeshInstance3D", true, false):
			var v := mi as MeshInstance3D
			if v.is_visible_in_tree() and (v.global_transform * v.get_aabb()).grow(0.01).has_point(q):
				print("[vis]  at %.2f: %s (%s) %s" % [d, v.get_path(), v.get_aabb().size, v.mesh.get_class() if v.mesh else "-"])
