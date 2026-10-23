extends Node3D
## Real furnished interior built inside a landing house's shell (seamless: same space as the house).
## Rooms come from a per-house layout (see _layout_*), walls are built per room with openings for
## doors, arches and the house windows; floors, ceilings, skirting, architraves, curtains, stairs,
## furniture (Blender pieces via furniture.gd), lights, sleeping residents and the elf mission
## props (stockings, present spots, kid's door plaque, snacks).
## Everything here collides only on physics layer 3 (INTERIOR_LAYER), which only the elf uses, and
## renders on visual layer 2 so the interior lamps never light the outside of the house.

const GB := preload("res://scripts/greybox.gd")
const Furn := preload("res://scripts/furniture.gd")
const ES := preload("res://scripts/elf_size.gd")
const Resident := preload("res://scripts/resident.gd")
const FX := preload("res://scripts/fx.gd")
const Door := preload("res://scripts/door.gd")
const Decor := preload("res://scripts/decor.gd")

const INTERIOR_LAYER := 4
const VIS_LAYER := 2  ## render layer bit for interior meshes + the lights that only light interiors
const INSET := 0.35  ## interior perimeter wall face, measured in from the nominal shell
const WALL_T := 0.08  ## visual wall thickness per room side (a partition = 2 x WALL_T)
const WALL_OUT := 0.25  ## perimeter wall collision extends this far outward (no thin skins to slip through)
const WARM := Color(1.0, 0.72, 0.42)

@export var lamp_energy := 1.1
@export var tree_light_energy := 0.7
@export var nightlight_energy := 0.45
@export var ember_energy := 0.6
@export var dust_mote_amount := 18  ## Dust motes drifting in each room's moonbeams (0 = off).
@export var light_fade_distance := 26.0  ## Interior lights switch off beyond this camera distance (performance).
@export var interior_light_shadows := true  ## The main lamp in the living room and kitchen cast shadows.
@export_range(0.0, 1.0) var doors_closed_chance := 0.4  ## Interior doors that start shut.
@export_range(0.0, 1.0) var doors_ajar_chance := 0.3  ## ...that start ajar (the rest start wide open).
@export var door_ajar_angle := 22.0

# Filled by build()
var house: Node3D
var W := 12.0
var D := 10.0
var H := 4.0
var X0 := 0.0
var X1 := 0.0
var Z0 := 0.0
var Z1 := 0.0
var floor_y := 0.4
var rooms: Array = []  # Dictionaries: name, rect (Rect2 in xz), level, floor, ceil, wall, wall2, pattern, floor_kind
var openings: Array = []  # {p: Vector2, w, kind: "door"/"arch"/"front", level}
var windows: Array = []  # {side: "+x"/"-x"/"+z"/"-z", along, y, w, h} in house-local terms (y = centre)
var stairs: Dictionary = {}
var holes_xz: Array = []  # Rect2s cut out of a level's floor + the ceiling below it (stairwell)
var chimney_xz := Vector2.ZERO
var fireplace_x := 0.0
var fireplace_spawn := Vector3.ZERO  ## inside the firebox (local)
## Furniture height tiers (gap under the body): every piece in TIER_PIECES gets LOW (crawl-only),
## MID (crouch-fit) or HIGH (stand-under), drawn from a shuffled bag so each house has all three.
const TIER_PIECES := ["Couch", "Armchair", "BedDouble", "BedKid", "Wardrobe", "TVUnit", "CoffeeTable", "SideTable"]
var tiered_pieces: Array = []  ## [MeshInstance3D, tier name] for checks
var _tier_rng := RandomNumberGenerator.new()
var _tier_bag: Array = []
var hearth_point := Vector3.ZERO  ## just in front of the fireplace (local)
## Crook-Line anchors (house-interior local): {pos, kind: "grapple" (swing / reel up) or "ledge" (rappel down), normal (out over the drop), name}
var rope_anchors: Array = []
## Marked climbables (local): {box: AABB, normal: out of the climb face, name, mantle: can you climb onto the top}
var climbables: Array = []
var tour: Array = []  # [label, local Vector3]
var shots: Dictionary = {}  # name -> [cam local, look local]
var tree_pos := Vector3.ZERO
var present_spots: Array = []  # {pos: Vector3 local, cap: float (max footprint), taken: bool}
var stockings: Array = []  # MeshInstance3D nodes (meta "filled", "puffed")
var kid_door: Node3D  ## the plaque the Ledger scans
var kid_name := "Mia"
var kid_nice := true
var residents: Array = []
var interactables: Array = []  ## nodes that glow under night vision
var ceiling_top := 3.3
var pipes: Array = []  ## {mat, base_color, spray_pos (local), dir, cracks: [nodes], puddle, spray, state: 0 ok/1 cracked/2 burst}
var freeze_meter := 0.0  ## Fireplace Icer build-up for this house (see gadgets.gd thresholds).
var fire_was_lit := false

var _rng := RandomNumberGenerator.new()
var _wall_mats: Dictionary = {}
var _body: StaticBody3D
var doors: Array = []  ## door.gd nodes (one per "door"/"front" opening)
var wall_segments: Array = []  ## floor-level wall pieces for the wall check: {a, b, inward, floor}
var _doors_made: Dictionary = {}


func build(h: Node3D, roof_type: int, width: float, depth: float, wall_height: float, chimney_local: Vector3) -> void:
	house = h
	W = width
	D = depth
	H = wall_height
	X0 = -W * 0.5 + INSET
	X1 = W * 0.5 - INSET
	Z0 = -D * 0.5 + INSET
	Z1 = D * 0.5 - INSET
	chimney_xz = Vector2(chimney_local.x, chimney_local.z)
	_rng.seed = 99 + roof_type
	_tier_rng.seed = 4242 + roof_type * 17
	_tier_bag.clear()
	_body = StaticBody3D.new()
	_body.name = "InteriorCollision"
	_body.collision_layer = INTERIOR_LAYER
	_body.collision_mask = 0
	add_child(_body)
	match roof_type:
		0:
			_layout_flat()
		1:
			_layout_steep()
		_:
			_layout_slick()
	for r in rooms:
		_build_room(r)
	_build_pipes()
	if dust_mote_amount > 0:
		for r in rooms:
			var rc: Rect2 = r.rect
			var m := FX.dust_motes(Vector3(rc.size.x * 0.4, 0.8, rc.size.y * 0.4), dust_mote_amount)
			m.preprocess = 6.0
			m.visibility_aabb = AABB(Vector3(-5, -2, -5), Vector3(10, 4, 10))
			add_child(m)
			m.position = Vector3(rc.get_center().x, float(r.floor) + 1.3, rc.get_center().y)
	if not stairs.is_empty():
		_build_stairs()
	Decor.interior(self, roof_type)  # visual only, own RNG
	_set_layers(self)


## Windows the house shell should cut and frame (house-local; y is the window centre).
func get_windows() -> Array:
	return windows


# =================================================================================================
# Layouts
# =================================================================================================

func _room(name: String, x0: float, z0: float, x1: float, z1: float, wall: Color, pattern: int, pat: Color, floor_kind: int, level := 0) -> Dictionary:
	var fl := floor_y if level == 0 else 3.1
	var ce := (floor_y + 2.9) if level == 0 else 5.3
	if not stairs.is_empty() and level == 0:
		ce = 2.95
	var r := {"name": name, "rect": Rect2(x0, z0, x1 - x0, z1 - z0), "level": level, "floor": fl, "ceil": ce,
			"wall": wall, "pattern": pattern, "pat": pat, "floor_kind": floor_kind}
	rooms.append(r)
	return r


func _door(x: float, z: float, level := 0, kind := "door", w := 1.0) -> void:
	openings.append({"p": Vector2(x, z), "w": w, "kind": kind, "level": level})


func _win(side: String, along: float, y := 1.7) -> void:
	windows.append({"side": side, "along": along, "y": y, "w": 1.3, "h": 1.1})


func _r(name: String) -> Dictionary:
	for r in rooms:
		if r.name == name:
			return r
	return {}


func _layout_flat() -> void:
	# Single storey. Street door on +X into a long hall; living (fireplace) + kitchen to the back,
	# master bedroom + kid's room to the front.
	var hz := 0.7
	_room("Hall", X0, -hz, X1, hz, Color(0.95, 0.85, 0.6), 1, Color(0.85, 0.6, 0.35), 6)
	_room("Living", -0.4, Z0, X1, -hz, Color(0.3, 0.62, 0.55), 2, Color(0.95, 0.85, 0.55), 3)
	_room("Kitchen", X0, Z0, -0.4, -hz, Color(0.98, 0.78, 0.35), 0, Color.WHITE, 4)
	_room("Bedroom", 1.6, hz, X1, Z1, Color(0.62, 0.45, 0.78), 1, Color(0.78, 0.62, 0.9), 6)
	_room("Kid's room", X0, hz, 1.6, Z1, Color(0.45, 0.7, 0.95), 2, Color(1.0, 0.95, 0.6), 6)
	_door(X1, 0.0, 0, "front")
	_door(1.0, -hz)
	_door(-3.5, -hz)
	_door(-0.4, -2.7, 0, "arch", 2.0)
	_door(2.6, hz)
	_door(-1.0, hz)
	_win("+z", 3.6)
	_win("+z", -3.6)
	_win("+x", -3.0)
	_win("+x", 3.0)
	_win("-z", 1.2)
	_win("-z", -3.0)
	_win("-x", -3.2)
	_fireplace(_r("Living"))
	var lv := _r("Living")
	_living(lv, Vector3(0.5, 0, Z0 + 0.75), "+x", -3.0)
	_kitchen(_r("Kitchen"), "-z", "-x")
	_hall(_r("Hall"))
	_bedroom(_r("Bedroom"), "+z", 0.5)
	_kids_room(_r("Kid's room"), "-x", 0.55, Vector3(-1.0, 0, hz))
	var f := floor_y
	tour = [["Fireplace", hearth_point], ["Living room", Vector3(2.4, f, -2.2)], ["via", Vector3(1.0, f, -1.3)],
			["Hall", Vector3(1.0, f, 0.0)], ["via", Vector3(2.6, f, 0.0)], ["via", Vector3(2.6, f, 1.4)], ["Bedroom", Vector3(3.2, f, 1.6)],
			["via", Vector3(2.6, f, 1.4)], ["via", Vector3(2.6, f, 0.0)], ["via", Vector3(-1.0, f, 0.0)], ["via", Vector3(-1.0, f, 1.4)],
			["Kid's room", Vector3(-1.6, f, 2.4)], ["via", Vector3(-1.0, f, 1.4)], ["via", Vector3(-1.0, f, 0.0)], ["via", Vector3(-3.5, f, 0.0)],
			["via", Vector3(-3.5, f, -1.1)], ["Kitchen", Vector3(-1.7, f, -1.25)], ["via", Vector3(-0.4, f, -2.0)], ["via", Vector3(1.5, f, -1.8)],
			["Fireplace", hearth_point]]
	shots = {
		"living": [Vector3(-0.0, 1.9, -1.0), Vector3(3.6, 0.8, -3.6)],
		"kitchen": [Vector3(-0.8, 1.9, -1.0), Vector3(-4.4, 0.8, -3.6)],
		"bedroom": [Vector3(1.9, 1.9, 1.0), Vector3(4.6, 0.6, 3.6)],
		"kids": [Vector3(1.2, 1.9, 1.0), Vector3(-3.5, 0.6, 3.6)],
		"fireplace": [Vector3(fireplace_x - 0.5, 0.75, Z0 + 2.6), Vector3(fireplace_x, 0.75, Z0 + 0.3)],
	}


func _layout_steep() -> void:
	# Single storey, big through-lounge on the east side, door on -X.
	var hz := 0.7
	_room("Hall", X0, -hz, 1.4, hz, Color(0.98, 0.7, 0.55), 2, Color(1.0, 0.9, 0.75), 3)
	_room("Living", 1.4, Z0, X1, Z1, Color(0.95, 0.55, 0.35), 1, Color(1.0, 0.75, 0.45), 3)
	_room("Kitchen", X0, Z0, 1.4, -hz, Color(0.55, 0.8, 0.5), 0, Color.WHITE, 4)
	_room("Bedroom", X0, hz, -1.6, Z1, Color(0.35, 0.5, 0.85), 2, Color(0.6, 0.75, 1.0), 6)
	_room("Kid's room", -1.6, hz, 1.4, Z1, Color(0.98, 0.62, 0.78), 1, Color(1.0, 0.85, 0.9), 6)
	_door(X0, 0.0, 0, "front")
	_door(1.4, 0.0)
	_door(-2.0, -hz)
	_door(1.4, -2.7, 0, "arch", 1.8)
	_door(-2.6, hz)
	_door(0.4, hz)
	_win("+z", -3.3)
	_win("+z", -0.1)
	_win("+z", 3.3)
	_win("+x", 0.0)
	_win("+x", 2.8)
	_win("-x", 3.0)
	_win("-x", -3.0)
	_win("-z", -2.5)
	_fireplace(_r("Living"))
	_living(_r("Living"), Vector3(X1 - 0.9, 0, Z1 - 0.9), "+x", 0.0)
	_kitchen(_r("Kitchen"), "-z", "-x")
	_hall(_r("Hall"))
	_bedroom(_r("Bedroom"), "+z", 0.45)
	_kids_room(_r("Kid's room"), "+z", 0.5, Vector3(0.4, 0, hz))
	var f := floor_y
	tour = [["Fireplace", hearth_point], ["Living room", Vector3(2.6, f, 1.0)], ["via", Vector3(2.2, f, 0.0)], ["via", Vector3(0.8, f, 0.0)],
			["Hall", Vector3(-1.0, f, 0.0)], ["via", Vector3(-2.6, f, 0.0)], ["via", Vector3(-2.6, f, 1.4)], ["Bedroom", Vector3(-3.0, f, 2.0)],
			["via", Vector3(-2.6, f, 1.4)], ["via", Vector3(-2.6, f, 0.0)], ["via", Vector3(0.4, f, 0.0)], ["via", Vector3(0.4, f, 1.4)],
			["Kid's room", Vector3(0.0, f, 2.2)], ["via", Vector3(0.4, f, 1.4)], ["via", Vector3(0.4, f, 0.0)], ["via", Vector3(-2.0, f, 0.0)],
			["via", Vector3(-2.0, f, -1.4)], ["Kitchen", Vector3(-0.6, f, -1.6)], ["via", Vector3(1.4, f, -2.4)], ["via", Vector3(2.6, f, -2.0)],
			["Fireplace", hearth_point]]
	shots = {
		"living": [Vector3(2.2, 1.9, 2.5), Vector3(4.0, 0.7, -3.0)],
		"kitchen": [Vector3(0.8, 1.9, -1.2), Vector3(-3.8, 0.7, -3.6)],
		"bedroom": [Vector3(-1.9, 1.9, 1.1), Vector3(-4.2, 0.6, 3.8)],
		"fireplace": [Vector3(fireplace_x - 0.6, 0.75, Z0 + 2.6), Vector3(fireplace_x, 0.75, Z0 + 0.3)],
	}


func _layout_slick() -> void:
	# Two storeys with a staircase in the entry hall. Door on +X (z = -3.4).
	stairs = {"x_bottom": 4.6, "x_top": 0.1, "z0": Z0, "z1": Z0 + 1.0}
	holes_xz = [Rect2(0.1, Z0, 4.5, 1.0)]
	var sz := -2.2
	_room("Hall", -1.0, Z0, X1, sz, Color(0.62, 0.82, 0.88), 1, Color(0.85, 0.95, 1.0), 3)
	_room("Living", X0, Z0, -1.0, Z1, Color(0.92, 0.42, 0.42), 2, Color(1.0, 0.75, 0.6), 3)
	_room("Kitchen", -1.0, sz, X1, Z1, Color(0.98, 0.9, 0.55), 0, Color.WHITE, 4)
	_room("Landing", -1.0, Z0, X1, sz, Color(0.62, 0.82, 0.88), 1, Color(0.85, 0.95, 1.0), 6, 1)
	_room("Bedroom", X0, Z0, -1.0, Z1, Color(0.5, 0.35, 0.7), 1, Color(0.7, 0.55, 0.85), 6, 1)
	_room("Kid's room", -1.0, sz, X1, Z1, Color(0.4, 0.78, 0.55), 2, Color(1.0, 1.0, 0.7), 6, 1)
	_door(X1, -3.4, 0, "front")
	_door(-1.0, -3.0)
	_door(2.0, sz)
	_door(-1.0, 1.5, 0, "arch", 2.0)
	_door(-1.0, -3.0, 1)
	_door(2.5, sz, 1)
	_win("-x", -3.0)
	_win("-x", 2.0)
	_win("+z", -3.6)
	_win("+z", 2.5)
	_win("-z", -2.0)
	_win("-x", -3.0, 3.9)
	_win("-x", 2.0, 3.9)
	_win("+z", -3.6, 3.9)
	_win("+z", 3.0, 3.9)
	_win("+x", 1.0, 3.9)
	_win("-z", 3.0, 3.9)
	_fireplace(_r("Living"))
	_living(_r("Living"), Vector3(X0 + 0.9, 0, Z1 - 0.9), "-x", 2.0)
	_kitchen(_r("Kitchen"), "+x", "+z")
	_hall(_r("Hall"))
	_hall(_r("Landing"))
	_bedroom(_r("Bedroom"), "+z", 0.45)
	_kids_room(_r("Kid's room"), "+z", 0.55, Vector3(2.5, 0, sz))
	# chimney breast rising through the bedroom upstairs
	_brick_box(Vector3(1.6, 5.3 - 3.1, 0.55), Vector3(fireplace_x, 3.1 + (5.3 - 3.1) * 0.5, Z0 + WALL_T + 0.27))  # in line with the one below: the flue runs up inside it
	var f := floor_y
	var u := 3.1
	tour = [["Fireplace", hearth_point], ["Living room", Vector3(-3.3, f, -1.2)], ["via", Vector3(-1.8, f, -3.0)], ["via", Vector3(-0.2, f, -3.0)],
			["Hall", Vector3(4.9, f, -3.0)], ["via", Vector3(5.1, f, -4.15)], ["Stairs", Vector3(2.4, 1.7, -4.15)], ["via", Vector3(-0.4, u, -4.15)],
			["Landing", Vector3(-0.4, u, -2.9)], ["via", Vector3(2.5, u, -2.9)], ["via", Vector3(2.5, u, -1.4)], ["Kid's room", Vector3(3.0, u, 0.0)],
			["via", Vector3(2.5, u, -1.4)], ["via", Vector3(2.5, u, -2.9)], ["via", Vector3(-0.2, u, -3.0)], ["via", Vector3(-1.8, u, -3.0)],
			["Bedroom", Vector3(-3.2, u, -1.5)], ["via", Vector3(-1.8, u, -3.0)], ["via", Vector3(-0.4, u, -2.9)], ["via", Vector3(-0.4, u, -4.15)],
			["via", Vector3(2.4, 1.7, -4.15)], ["via", Vector3(5.1, f, -4.15)], ["via", Vector3(5.0, f, -3.0)], ["via", Vector3(2.0, f, -3.0)],
			["via", Vector3(2.0, f, -1.4)], ["Kitchen", Vector3(2.0, f, 0.6)], ["via", Vector3(-0.2, f, 1.5)], ["via", Vector3(-2.2, f, 1.5)],
			["via", Vector3(-3.3, f, -1.2)], ["Fireplace", hearth_point]]
	shots = {
		"living": [Vector3(-1.5, 1.9, 2.8), Vector3(-4.5, 0.7, -3.0)],
		"kitchen": [Vector3(-0.5, 1.9, -1.5), Vector3(4.5, 0.6, 3.0)],
		"bedroom": [Vector3(-1.5, 4.6, -3.9), Vector3(-4.0, 3.4, 2.0)],
		"stairs": [Vector3(-0.6, 2.4, -2.5), Vector3(4.6, 0.6, -4.3)],
		"fireplace": [Vector3(fireplace_x + 0.6, 0.75, Z0 + 2.6), Vector3(fireplace_x, 0.75, Z0 + 0.3)],
	}


# =================================================================================================
# Room furnishing
# =================================================================================================

## Put a piece with its back against a wall of `room`. side = which wall ("-z" back, "+z", "-x",
## "+x"); t = 0..1 along that wall. The piece turns to face into the room.
func against(room: Dictionary, side: String, t: float, piece: String, solid := true, gap := 0.04, up := 0.0) -> MeshInstance3D:
	var rc: Rect2 = room.rect
	var sz := Furn.size_of(piece)
	var y := float(room.floor) + up
	var pos := Vector3.ZERO
	var yaw := 0.0
	match side:
		"-z":
			yaw = 180.0
			pos = Vector3(rc.position.x + rc.size.x * t, y, rc.position.y + WALL_T + gap + sz.z * 0.5)
		"+z":
			yaw = 0.0
			pos = Vector3(rc.position.x + rc.size.x * t, y, rc.end.y - WALL_T - gap - sz.z * 0.5)
		"-x":
			yaw = -90.0
			pos = Vector3(rc.position.x + WALL_T + gap + sz.z * 0.5, y, rc.position.y + rc.size.y * t)
		_:
			yaw = 90.0
			pos = Vector3(rc.end.x - WALL_T - gap - sz.z * 0.5, y, rc.position.y + rc.size.y * t)
	var center_off := Furn.mesh_of(piece).get_aabb().get_center()
	var g := _gap_for(piece)
	var mi := _note_tier(Furn.spawn(piece, self, pos, yaw + _rng.randf_range(-2.5, 2.5), solid, 1.0, g), g)
	# re-centre the footprint (pieces are modelled around their origin but bounds can be offset)
	var off := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(center_off.x, 0, center_off.z)
	mi.position -= off
	return mi


func put(piece: String, pos: Vector3, yaw := 0.0, solid := true) -> MeshInstance3D:
	var g := _gap_for(piece)
	return _note_tier(Furn.spawn(piece, self, pos, yaw + _rng.randf_range(-3.0, 3.0), solid, 1.0, g), g)


func _anchor(pos: Vector3, kind: String, name: String, normal := Vector3.ZERO) -> void:
	rope_anchors.append({"pos": pos, "kind": kind, "normal": normal, "name": name})


func _climbable(box: AABB, normal: Vector3, name: String, mantle: bool) -> void:
	climbables.append({"box": box, "normal": normal.normalized(), "name": name, "mantle": mantle})


## A bookshelf: climbable up its front, rappel back down from its top front edge.
func _mark_shelf(mi: MeshInstance3D) -> void:
	var bb: AABB = mi.transform * Furn.mesh_of("Bookshelf").get_aabb()
	var fwd := Basis(Vector3.UP, mi.rotation.y) * Vector3(0, 0, -1)
	_climbable(bb, fwd, "Bookshelf", true)
	var top := Vector3(mi.position.x, bb.end.y, mi.position.z)
	_anchor(top + fwd * (Furn.size_of("Bookshelf").z * 0.5 - 0.02), "ledge", "Bookshelf", fwd)


## Gap for a tiered piece (m), or -1 for pieces that keep their modelled legs.
func _gap_for(piece: String) -> float:
	if not piece in TIER_PIECES:
		return -1.0
	if _tier_bag.is_empty():
		_tier_bag = [ES.GAP_LOW_EH, ES.GAP_MID_EH, ES.GAP_HIGH_EH]
		for i in range(2, 0, -1):
			var j := _tier_rng.randi_range(0, i)
			var tmp = _tier_bag[i]
			_tier_bag[i] = _tier_bag[j]
			_tier_bag[j] = tmp
	return ES.m(float(_tier_bag.pop_back()))


func _note_tier(mi: MeshInstance3D, gap: float) -> MeshInstance3D:
	if gap >= 0.0:
		var tn := "LOW" if gap < ES.m(0.7) else ("MID" if gap < ES.m(1.0) else "HIGH")
		mi.set_meta("tier", tn)
		tiered_pieces.append([mi, tn])
	return mi


func _omni(pos: Vector3, color: Color, energy: float, rng: float, shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.3
	l.light_cull_mask = VIS_LAYER
	l.shadow_enabled = shadow
	l.light_specular = 0.2
	l.light_volumetric_fog_energy = 0.0
	# interiors are only seen up close: fade lights (and their shadows) out with distance
	l.distance_fade_enabled = true
	l.distance_fade_begin = light_fade_distance
	l.distance_fade_length = 6.0
	l.distance_fade_shadow = 12.0
	add_child(l)
	return l


func _fireplace(room: Dictionary) -> void:
	var rc: Rect2 = room.rect
	fireplace_x = clampf(chimney_xz.x, rc.position.x + 1.2, rc.end.x - 1.2)
	var f := float(room.floor)
	var zc := Z0 + WALL_T + 0.4
	Furn.spawn("Fireplace", self, Vector3(fireplace_x, f, zc), 180.0, false)
	# collision matching the Fireplace model (tools/blender/build_models.py): the two brick jambs,
	# the firebox's splayed firebrick sides, its back (vertical, then sloping forward to the throat),
	# the lintel + front breast over the opening, the mantel shelf and the raised hearth (with
	# shallow ramps so the elf walks on and off it). The opening and the throat stay open.
	if OS.get_cmdline_user_args().has("--break-chimney"):  # checks only: the old, wrong collision
		for s: float in [-1.0, 1.0]:
			_coll(Vector3(0.55, 1.2, 0.75), Vector3(fireplace_x + s * 0.72, f + 0.6, zc))
		_coll(Vector3(2.0, 1.4, 0.15), Vector3(fireplace_x, f + 0.7, Z0 + WALL_T + 0.05))
	else:
		_fireplace_collision(f, zc)
	# chimney breast (brick) from the mantel to the ceiling
	var ce := float(room.ceil)
	_brick_box(Vector3(1.6, ce - (f + 1.3), 0.55), Vector3(fireplace_x, (f + 1.3 + ce) * 0.5, Z0 + WALL_T + 0.27))
	_climbable(AABB(Vector3(fireplace_x - 1.0, f, zc - 0.4), Vector3(2.0, 1.32, 0.78)), Vector3(0, 0, 1), "Fireplace", true)
	_anchor(Vector3(fireplace_x + 0.55, f + 1.32, zc + 0.36), "ledge", "Mantel", Vector3(0, 0, 1))
	fireplace_spawn = Vector3(fireplace_x, f, zc - 0.05)
	hearth_point = Vector3(fireplace_x, f, zc + 1.0)
	_omni(Vector3(fireplace_x, f + 0.3, zc + 0.2), Color(1.0, 0.45, 0.15), ember_energy, 2.6)
	# stockings hung from the mantel (Puff-Possum targets)
	for k in 3:
		var s := Furn.spawn("Stocking", self, Vector3(fireplace_x - 0.6 + k * 0.6, f + 1.2, zc + 0.5), 0.0, true)
		s.set_meta("puffed", false)
		s.set_meta("filled", false)
		stockings.append(s)
		interactables.append(s)
	# Aussie touch on the hearth: a beer and a carrot for the reindeer
	put("BeerCarrot", Vector3(fireplace_x + 0.75, f + 0.06, zc + 0.6), 20.0, true)


func _brick_box(size: Vector3, pos: Vector3) -> void:
	var m := Furn.brick_material()
	var bm := BoxMesh.new()
	bm.size = size
	GB.add_mesh(self, bm, pos, Vector3.ZERO, m)
	_coll(size, pos)


## Collision for the Fireplace model (see _fireplace).
func _fireplace_collision(f: float, zc: float) -> void:
	for s: float in [-1.0, 1.0]:
		_coll(Vector3(0.55, 1.2, 0.75), Vector3(fireplace_x + s * 0.72, f + 0.6, zc))
		# splayed side: 19.3 deg, front end out; 0.1 visual, collider 0.2 (extra goes outward)
		var ps := deg_to_rad(19.3) * s
		var outw := Vector3(cos(ps), 0, -sin(ps)) * s
		_coll(Vector3(0.2, 0.94, 0.56), Vector3(fireplace_x + s * 0.41, f + 0.47, zc) + outw * 0.05, Vector3(0, ps, 0))
	_coll(Vector3(2.0, 1.4, 0.175), Vector3(fireplace_x, f + 0.7, zc - 0.3375))  # back: face at the firebrick
	# sloping upper back (22 deg forward), 0.1 visual, collider 0.2 deep (extra goes backward)
	var sb := Basis(Vector3.RIGHT, deg_to_rad(22.0))
	_coll(Vector3(0.9, 0.62, 0.2), Vector3(fireplace_x, f + 0.62, zc - 0.2) - sb.z * 0.05, Vector3(deg_to_rad(22.0), 0, 0))
	_coll(Vector3(1.0, 0.46, 0.235), Vector3(fireplace_x, f + 0.98, zc + 0.2775))  # lintel + front breast
	_coll(Vector3(2.2, 0.1, 0.32), Vector3(fireplace_x, f + 1.25, zc + 0.42))  # mantel shelf
	# the fireplace head: solid brick between the jambs, over the firebox and round the throat, up
	# to the mantel (the house cuts the throat / smoke chamber out of it). Hidden behind the lintel
	# and mantel except a brick strip behind the mantel shelf and the ends over the jambs.
	_coll(Vector3(1.99, 0.25, 0.585), Vector3(fireplace_x, f + 1.075, zc - 0.1325))
	_coll(Vector3(1.99, 0.1, 0.685), Vector3(fireplace_x, f + 1.25, zc - 0.0825))
	var bm := Furn.brick_material()
	for piece: Array in [[Vector3(1.99, 0.09, 0.115), Vector3(fireplace_x, f + 1.255, zc + 0.2025)],
			[Vector3(0.195, 0.1, 0.685), Vector3(fireplace_x - 0.8975, f + 1.25, zc - 0.0825)],
			[Vector3(0.195, 0.1, 0.685), Vector3(fireplace_x + 0.8975, f + 1.25, zc - 0.0825)]]:
		var hb := BoxMesh.new()
		hb.size = piece[0]
		GB.add_mesh(self, hb, piece[1], Vector3.ZERO, bm)
	# raised stone hearth: modelled 6 cm, solid to 2.5 cm (the elf has no step-up, and the walk grid
	# treats anything over 3 cm as furniture), with shallow ramps on all four edges
	_coll(Vector3(2.1, 0.025, 0.6), Vector3(fireplace_x, f + 0.0125, zc + 0.55))
	_ramp(Vector3(fireplace_x, f + 0.025, zc + 0.85), Vector3(fireplace_x, f, zc + 0.92), 2.1)  # front
	for s: float in [-1.0, 1.0]:
		_ramp(Vector3(fireplace_x + s * 1.05, f + 0.025, zc + 0.55), Vector3(fireplace_x + s * 1.12, f, zc + 0.55), 0.6)
	_ramp(Vector3(fireplace_x, f + 0.025, zc + 0.25), Vector3(fireplace_x, f, zc + 0.18), 0.89)  # into the firebox


## A walkable ramp collider: its top face runs from edge a (top) to edge b (bottom), w wide.
func _ramp(a: Vector3, b: Vector3, w: float) -> void:
	var d := b - a
	var run := Vector3(d.x, 0, d.z)
	var across := run.normalized().cross(Vector3.UP)
	var fwd := d.normalized()
	var up := across.cross(fwd).normalized()
	if up.y < 0.0:
		up = -up
	var t := 0.03
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, t, d.length())
	cs.shape = bs
	cs.transform = Transform3D(Basis(across, up, across.cross(up)).orthonormalized(), (a + b) * 0.5 - up * t * 0.5)
	_body.add_child(cs)


func _coll(size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = pos
	cs.rotation = rot
	_body.add_child(cs)


func _living(room: Dictionary, tree: Vector3, tv_side: String, _win_along: float) -> void:
	var rc: Rect2 = room.rect
	var f := float(room.floor)
	var c := rc.get_center()
	# couch facing the fireplace, coffee table between, armchair angled in
	var couch_z := Z0 + 3.0
	put("RugRect", Vector3(fireplace_x, f, couch_z - 1.0), 0.0, false)
	put("Couch", Vector3(fireplace_x, f, couch_z), 180.0 + 180.0)
	var ct := put("CoffeeTable", Vector3(fireplace_x - 0.1, f, couch_z - 1.15), 0.0)
	put("CookiesMilk", Vector3(fireplace_x - 0.35, f + 0.44 + float(ct.get_meta("tier_dy", 0.0)), couch_z - 1.15), 0.0, true)
	var arm_x := fireplace_x - 1.9 if fireplace_x - 1.9 > rc.position.x + 0.7 else fireplace_x + 1.9
	put("Armchair", Vector3(arm_x, f, couch_z - 1.3), 90.0 if arm_x < fireplace_x else -90.0)
	put("FloorLamp", Vector3(fireplace_x + 1.5 if arm_x < fireplace_x else fireplace_x - 1.5, f, couch_z + 0.2), 0.0)
	var lamp_x := fireplace_x + 1.5 if arm_x < fireplace_x else fireplace_x - 1.5
	_omni(Vector3(lamp_x, f + 1.25, couch_z + 0.2), WARM, lamp_energy, 5.0, interior_light_shadows)
	# TV on a side wall
	var tvu := against(room, tv_side, 0.72, "TVUnit")
	var tv_pos := tvu.position + Vector3(0, Furn.mesh_of("TVUnit").get_aabb().end.y + 0.01 + float(tvu.get_meta("tier_dy", 0.0)), 0)
	Furn.spawn("TV", self, tv_pos, tvu.rotation_degrees.y, true)
	_omni(tv_pos + Basis(Vector3.UP, tvu.rotation.y) * Vector3(0, 0.45, -0.6), Color(0.45, 0.6, 1.0), 0.35, 2.5)
	_mark_shelf(against(room, "-x" if tv_side == "+x" else "+x", 0.75, "Bookshelf"))
	put("Plant", Vector3(rc.position.x + 0.45, f, rc.end.y - 0.45) if tree.x > c.x else Vector3(rc.end.x - 0.45, f, rc.end.y - 0.45))
	against(room, "+z" if tv_side != "+z" else "-x", 0.5, "Fan", true, 0.2)
	var ac := against(room, "-x" if tv_side == "+x" else "+x", 0.3, "AirCon", false, 0.0, 2.35)
	ac.position.y = f + 2.35
	var pic := against(room, "-z", 0.12 if fireplace_x > c.x else 0.88, "PictureA", false, 0.0, 1.7)
	pic.position.y = f + 1.7
	# the tree, with presents already under it and free spots for the Fit-Ghost
	tree_pos = Vector3(tree.x, f, tree.z)
	put("ChristmasTree", tree_pos, _rng.randf_range(0, 360))
	var to_c := (Vector3(c.x, f, c.y) - tree_pos).normalized()
	_climbable(AABB(tree_pos + Vector3(-0.32, 0, -0.32), Vector3(0.64, 1.75, 0.64)), to_c, "ChristmasTree", false)
	_anchor(tree_pos + Vector3(0, 1.45, 0) + to_c * 0.25, "grapple", "Tree branch")
	for k in 3:
		var l := _omni(tree_pos + Vector3(cos(k * 2.1) * 0.5, 0.7 + k * 0.45, sin(k * 2.1) * 0.5),
				[Color(1, 0.3, 0.2), Color(0.3, 1, 0.4), Color(0.4, 0.5, 1)][k], tree_light_energy, 2.6)
		l.set_meta("twinkle", k)
	var to_room := (Vector3(c.x, f, c.y) - tree_pos).normalized()
	var side := to_room.cross(Vector3.UP)
	var spots := [[to_room * 0.95, 0.5], [to_room * 0.8 + side * 0.65, 0.36], [to_room * 0.8 - side * 0.65, 0.36],
			[to_room * 0.55 + side * 1.0, 0.28], [to_room * 0.55 - side * 1.0, 0.5]]
	for i in spots.size():
		var sp := {"pos": tree_pos + (spots[i][0] as Vector3), "cap": float(spots[i][1]), "taken": false}
		present_spots.append(sp)
	# two of the family's own presents already there
	for i in [1, 4]:
		put(["PresentA", "PresentB"][i % 2], present_spots[i].pos, _rng.randf_range(0, 90), true)
		present_spots[i].taken = true


func _kitchen(room: Dictionary, bench_side: String, fridge_side: String) -> void:
	var f := float(room.floor)
	var rc: Rect2 = room.rect
	var n := int(floor((rc.size.x if bench_side in ["-z", "+z"] else rc.size.y) - 1.6))
	n = clampi(n, 3, 5)
	var pieces := ["KitchenCounter", "Stove", "KitchenSink", "KitchenCounter", "KitchenCounter"]
	for i in n:
		var t := (0.65 + i * 1.02) / (rc.size.x if bench_side in ["-z", "+z"] else rc.size.y)
		against(room, bench_side, t, pieces[i], true, 0.02)
	against(room, fridge_side, 0.2 if bench_side == "-z" else 0.8, "Fridge")
	var c := rc.get_center()
	var tc := Vector3(c.x, f, c.y + 0.3) if bench_side in ["-z", "+z"] else Vector3(c.x + 0.3, f, c.y)
	put("RugRect", tc, 90.0, false)
	put("DiningTable", tc, 0.0)
	for s: float in [-1.0, 1.0]:
		put("DiningChair", tc + Vector3(s * 0.38, 0, 0.75), 180.0)
		put("DiningChair", tc + Vector3(s * 0.38, 0, -0.75), 0.0)
	put("Plant", Vector3(rc.end.x - 0.4, f, rc.end.y - 0.4) if bench_side != "+x" else Vector3(rc.position.x + 0.4, f, rc.end.y - 0.4))
	var pic := against(room, "+x" if fridge_side == "-x" else "-x", 0.5, "PictureB", false, 0.0)
	pic.position.y = f + 1.65
	_omni(tc + Vector3(0, 2.2, 0), WARM, lamp_energy * 0.7, 4.5, interior_light_shadows)
	GB.cylinder(self, 0.25, 0.08, 0.25, tc + Vector3(0, 2.45, 0), Color(1.0, 0.85, 0.5), Vector3.ZERO, 1.2)
	GB.cylinder(self, 0.01, 0.01, float(room.ceil) - (f + 2.55), tc + Vector3(0, (float(room.ceil) + f + 2.55) * 0.5 - f, 0), Color(0.1, 0.1, 0.1))


func _hall(room: Dictionary) -> void:
	var f := float(room.floor)
	var rc: Rect2 = room.rect
	var c := rc.get_center()
	var long_x := rc.size.x > rc.size.y
	var runner := put("RugOval", Vector3(c.x, f, c.y), 90.0 if not long_x else 0.0, false)
	runner.scale = Vector3(minf(rc.size.x, 4.0) / 2.2, 1, 0.9) if long_x else Vector3(0.9, 1, minf(rc.size.y, 4.0) / 2.2)
	var nl := against(room, "-z" if long_x else "-x", 0.15, "Nightlight", false, 0.0, 0.35)
	nl.position.y = f + 0.35
	_omni(nl.position + Vector3(0, 0.1, 0) + (Vector3(0, 0, 0.3) if long_x else Vector3(0.3, 0, 0)), Color(0.6, 0.8, 1.0), nightlight_energy, 3.0)
	var pic := against(room, "+z" if long_x else "+x", 0.35, "PictureB", false, 0.0)
	pic.position.y = f + 1.6
	var pic2 := against(room, "+z" if long_x else "+x", 0.7, "PictureA", false, 0.0)
	pic2.position.y = f + 1.65


func _bedroom(room: Dictionary, bed_side: String, t: float) -> void:
	var f := float(room.floor)
	var rc: Rect2 = room.rect
	var bed := against(room, bed_side, t, "BedDouble", true, 0.05)
	var right := Basis(Vector3.UP, bed.rotation.y) * Vector3.RIGHT
	var back := Basis(Vector3.UP, bed.rotation.y) * Vector3(0, 0, 1)
	var head := bed.position + back * 0.75
	for s: float in [-1.0, 1.0]:
		var g := _gap_for("SideTable")
		var st := _note_tier(Furn.spawn("SideTable", self, head + right * s * 1.15, bed.rotation_degrees.y, true, 1.0, g), g)
		Furn.spawn("Lamp", self, st.position + Vector3(0, _side_table_top() + float(st.get_meta("tier_dy", 0.0)), 0), 0.0, true)
	_omni(head + right * 1.15 + Vector3(0, 1.0, 0), WARM, lamp_energy * 0.35, 3.2)
	against(room, "-x" if bed_side != "-x" else "+x", 0.25, "Wardrobe")
	put("RugRect", bed.position - back * 0.9 + Vector3(0, 0, 0), bed.rotation_degrees.y + 90.0, false)
	var ac := against(room, "-x" if bed_side != "-x" else "+x", 0.75, "AirCon", false, 0.0)
	ac.position.y = f + 2.3
	var pic := against(room, bed_side, t, "PictureA", false, 0.0)
	pic.position.y = f + 1.75
	# Mum and Dad, asleep
	for s: float in [-1.0, 1.0]:
		var r := Resident.new()
		r.resident_name = "Dad" if s < 0 else "Mum"
		r.adult = true
		r.base_depth = 0.75 if s < 0 else 0.6
		r.pajama = Color(0.3, 0.45, 0.85) if s < 0 else Color(0.9, 0.45, 0.6)
		add_child(r)
		r.lie_height = _mattress_top("BedDouble") + 0.07 + float(bed.get_meta("tier_dy", 0.0))
		r.setup(Transform3D(bed.basis, bed.position + right * s * 0.4 + Vector3(0, r.lie_height, 0)), self)
		residents.append(r)
	_under_bed_clutter(bed, 1.6)


func _side_table_top() -> float:
	return Furn.mesh_of("SideTable").get_aabb().end.y


func _mattress_top(piece: String) -> float:
	return 0.48 + Furn.clearance_of(piece) - 0.07  # mattress top = frame bottom + 0.41 (see build_models.py)


## The classic under-bed clutter: a shoebox, a lost sock and a toy car + ball. No collision, so they
## never block the crawl; placed toward the sides so the middle stays a clear hiding spot.
func _under_bed_clutter(bed: Node3D, w: float) -> void:
	var b := Basis(Vector3.UP, bed.rotation.y)
	var items := [["Shoebox", Vector3(-w * 0.32, 0, -0.55), 15.0], ["LostSock", Vector3(w * 0.3, 0, 0.35), -40.0],
			["ToyCar", Vector3(-w * 0.25, 0, 0.6), 70.0]]
	for it in items:
		var mi := Furn.spawn(str(it[0]), self, bed.position + b * (it[1] as Vector3), bed.rotation_degrees.y + float(it[2]), true)
		mi.set_meta("clutter", true)


func _kids_room(room: Dictionary, bed_side: String, t: float, door_at: Vector3) -> void:
	var f := float(room.floor)
	var rc: Rect2 = room.rect
	var bed := against(room, bed_side, t, "BedKid", true, 0.05)
	var right := Basis(Vector3.UP, bed.rotation.y) * Vector3.RIGHT
	var back := Basis(Vector3.UP, bed.rotation.y) * Vector3(0, 0, 1)
	var g := _gap_for("SideTable")
	var st := _note_tier(Furn.spawn("SideTable", self, bed.position + back * 0.8 + right * 0.85, bed.rotation_degrees.y, true, 1.0, g), g)
	var nl := Furn.spawn("Nightlight", self, st.position + Vector3(0, _side_table_top() + 0.07 + float(st.get_meta("tier_dy", 0.0)), 0), bed.rotation_degrees.y, true)
	_omni(nl.position + Vector3(0, 0.2, 0), Color(0.55, 0.75, 1.0), nightlight_energy * 1.3, 3.2)
	_mark_shelf(against(room, "+x" if bed_side == "-x" else "-x", 0.3, "Bookshelf"))
	put("RugOval", Vector3(rc.get_center().x, f, rc.get_center().y), 0.0, false)
	put("PresentC", Vector3(rc.get_center().x + 0.6, f, rc.get_center().y + 0.4), 30.0)  # a toy box
	var pic := against(room, "-z" if bed_side != "-z" else "+z", 0.6, "PictureB", false, 0.0)
	pic.position.y = f + 1.5
	var kid := Resident.new()
	kid.resident_name = kid_name
	kid.adult = false
	kid.base_depth = 0.5
	kid.pajama = Color(1.0, 0.75, 0.2)
	add_child(kid)
	kid.lie_height = _mattress_top("BedKid") + 0.02 + float(bed.get_meta("tier_dy", 0.0))
	kid.setup(Transform3D(bed.basis, bed.position + Vector3(0, kid.lie_height, 0)), self)
	residents.append(kid)
	_under_bed_clutter(bed, 1.0)
	# Name plaque on the hall side of the kid's door (the Ledger scans it)
	kid_nice = _rng.randf() < 0.7
	var hall_dir := Vector3.ZERO
	var c := rc.get_center()
	if absf(door_at.z - rc.position.y) < 0.05:
		hall_dir = Vector3(0, 0, -1)
	elif absf(door_at.z - rc.end.y) < 0.05:
		hall_dir = Vector3(0, 0, 1)
	elif absf(door_at.x - rc.position.x) < 0.05:
		hall_dir = Vector3(-1, 0, 0)
	else:
		hall_dir = Vector3(1, 0, 0)
	kid_door = Node3D.new()
	kid_door.name = "KidDoorPlaque"
	add_child(kid_door)
	var along := hall_dir.cross(Vector3.UP)
	kid_door.position = Vector3(door_at.x, f + 1.5, door_at.z) + hall_dir * (WALL_T + 0.03) + along * 0.8
	kid_door.look_at(kid_door.position + hall_dir, Vector3.UP)
	kid_door.rotate_object_local(Vector3.UP, PI)
	GB.box(kid_door, Vector3(0.5, 0.26, 0.04), Vector3.ZERO, Color(1.0, 0.85, 0.3))
	var lbl := Label3D.new()
	lbl.text = "%s'S ROOM\nKEEP OUT!" % kid_name.to_upper()
	lbl.font_size = 40
	lbl.pixel_size = 0.0035
	lbl.modulate = Color(0.5, 0.15, 0.6)
	lbl.position = Vector3(0, 0, -0.03)
	lbl.rotation_degrees = Vector3(0, 180, 0)
	lbl.outline_size = 0
	kid_door.add_child(lbl)
	interactables.append(kid_door)


# =================================================================================================
# Rooms: floors, ceilings, walls with openings
# =================================================================================================

func _wall_mat(room: Dictionary) -> ShaderMaterial:
	var key := str(room.name) + str(room.level)
	if _wall_mats.has(key):
		return _wall_mats[key]
	var m := GB.mat(room.wall).duplicate() as ShaderMaterial
	m.set_shader_parameter("pattern", room.pattern)
	m.set_shader_parameter("pattern_color", room.pat)
	m.set_shader_parameter("pattern_scale", 1.0)
	m.set_shader_parameter("rim_strength", 0.06)
	_wall_mats[key] = m
	return m


func _floor_mat(kind: int) -> ShaderMaterial:
	var key := "floor%d" % kind
	if _wall_mats.has(key):
		return _wall_mats[key]
	var base := Color(0.7, 0.45, 0.25)
	var pat := Color(0.5, 0.3, 0.15)
	if kind == 4:
		base = Color(0.95, 0.93, 0.88)
		pat = Color(0.25, 0.55, 0.6)
	elif kind == 6:
		base = Color(0.55, 0.42, 0.62)
		pat = Color(0.68, 0.55, 0.75)
	var m := GB.mat(base).duplicate() as ShaderMaterial
	m.set_shader_parameter("pattern", kind)
	m.set_shader_parameter("pattern_color", pat)
	m.set_shader_parameter("pattern_scale", 1.0)
	m.set_shader_parameter("rim_strength", 0.0)
	_wall_mats[key] = m
	return m


func _room_rect_at(p: Vector2, level: int) -> Rect2:
	for r in rooms:
		if int(r.level) == level and (r.rect as Rect2).grow(0.01).has_point(p):
			return r.rect
	return Rect2()


func _room_area_at(p: Vector2, level: int) -> float:
	for r in rooms:
		if int(r.level) == level and (r.rect as Rect2).grow(0.01).has_point(p):
			return (r.rect as Rect2).get_area()
	return 0.0


## Rect minus holes (axis-aligned), as a list of rects.
func _subtract(r: Rect2, holes: Array) -> Array:
	var out := [r]
	for h in holes:
		var nxt := []
		for a in out:
			var ar: Rect2 = a
			var hr: Rect2 = h
			if not ar.intersects(hr):
				nxt.append(ar)
				continue
			var i := ar.intersection(hr)
			if i.position.y > ar.position.y:
				nxt.append(Rect2(ar.position.x, ar.position.y, ar.size.x, i.position.y - ar.position.y))
			if i.end.y < ar.end.y:
				nxt.append(Rect2(ar.position.x, i.end.y, ar.size.x, ar.end.y - i.end.y))
			if i.position.x > ar.position.x:
				nxt.append(Rect2(ar.position.x, i.position.y, i.position.x - ar.position.x, i.size.y))
			if i.end.x < ar.end.x:
				nxt.append(Rect2(i.end.x, i.position.y, ar.end.x - i.end.x, i.size.y))
		out = nxt
	return out


func _build_room(room: Dictionary) -> void:
	var rc: Rect2 = room.rect
	var fl := float(room.floor)
	var ce := float(room.ceil)
	var lvl := int(room.level)
	# floor (with collision); the upper level floor has the stairwell cut out
	var floor_holes := holes_xz if lvl == 1 else []
	for fr in _subtract(rc, floor_holes):
		var r2: Rect2 = fr
		var size := Vector3(r2.size.x, 0.15, r2.size.y)
		var pos := Vector3(r2.get_center().x, fl - 0.075, r2.get_center().y)
		var bm := BoxMesh.new()
		bm.size = size
		GB.add_mesh(self, bm, pos, Vector3.ZERO, _floor_mat(int(room.floor_kind)))
		_coll(size, pos)
	# ceiling (visual): the ground floor ceiling has the stairwell cut out too
	var ceil_holes := holes_xz if (lvl == 0 and not stairs.is_empty()) else []
	for cr in _subtract(rc, ceil_holes):
		var r3: Rect2 = cr
		var cm := BoxMesh.new()
		cm.size = Vector3(r3.size.x, 0.1, r3.size.y)
		GB.add_mesh(self, cm, Vector3(r3.get_center().x, ce + 0.05, r3.get_center().y), Vector3.ZERO, GB.mat(Color(0.96, 0.92, 0.84), 0.0, 0.0))
	ceiling_top = maxf(ceiling_top, ce + 0.1)
	_pendant(room, rc, ce)
	# cornice
	var trim := Color(0.98, 0.95, 0.88)
	# walls: four edges
	var a := rc.position
	var b := rc.end
	_edge(room, Vector2(a.x, a.y), Vector2(b.x, a.y), Vector2(0, 1), lvl, fl, ce, trim)  # -z edge
	_edge(room, Vector2(a.x, b.y), Vector2(b.x, b.y), Vector2(0, -1), lvl, fl, ce, trim)  # +z edge
	_edge(room, Vector2(a.x, a.y), Vector2(a.x, b.y), Vector2(1, 0), lvl, fl, ce, trim)  # -x edge
	_edge(room, Vector2(b.x, a.y), Vector2(b.x, b.y), Vector2(-1, 0), lvl, fl, ce, trim)  # +x edge


## A pendant light fitting in the middle of the room (no collision): a Crook-Line swing anchor.
func _pendant(room: Dictionary, rc: Rect2, ce: float) -> void:
	var c := rc.get_center()
	if not stairs.is_empty() and int(room.level) == 0:
		for hr: Rect2 in holes_xz:
			if hr.grow(0.4).has_point(c):
				return
	var drop := 0.5
	GB.cylinder(self, 0.006, 0.006, drop, Vector3(c.x, ce - drop * 0.5, c.y), Color(0.15, 0.15, 0.15))
	GB.cylinder(self, 0.05, 0.05, 0.03, Vector3(c.x, ce - 0.015, c.y), Color(0.95, 0.93, 0.88))
	GB.cylinder(self, 0.06, 0.2, 0.16, Vector3(c.x, ce - drop - 0.06, c.y), (room.wall as Color).lerp(Color(0.98, 0.95, 0.85), 0.6))
	var bulb := GB.sphere(self, 0.045, Vector3(c.x, ce - drop - 0.13, c.y), Color(1.0, 0.92, 0.7), 1.5)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_anchor(Vector3(c.x, ce - drop + 0.03, c.y), "grapple", "Light fitting")


func _edge(room: Dictionary, a: Vector2, b: Vector2, inward: Vector2, lvl: int, fl: float, ce: float, trim: Color) -> void:
	var L := a.distance_to(b)
	var d := (b - a) / L
	var ops: Array = []
	for o in openings:
		if int(o.level) != lvl:
			continue
		var p: Vector2 = o.p
		var rel := p - a
		var along := rel.dot(d)
		var off := absf(rel.dot(Vector2(-d.y, d.x)))
		if off < 0.06 and along > 0.3 and along < L - 0.3:
			var top := fl + (2.4 if o.kind == "arch" else 2.1)
			ops.append({"c": along, "w": float(o.w), "bottom": fl, "top": top, "kind": o.kind, "id": openings.find(o)})
	# house windows on perimeter edges
	for w in windows:
		var wy := float(w.y)
		if (wy > 3.0) != (lvl == 1):
			continue
		var wp := Vector2.ZERO
		match str(w.side):
			"+z":
				wp = Vector2(float(w.along), Z1)
			"-z":
				wp = Vector2(float(w.along), Z0)
			"+x":
				wp = Vector2(X1, float(w.along))
			_:
				wp = Vector2(X0, float(w.along))
		var rel := wp - a
		var along := rel.dot(d)
		var off := absf(rel.dot(Vector2(-d.y, d.x)))
		if off < 0.06 and along > 0.5 and along < L - 0.5:
			ops.append({"c": along, "w": float(w.w), "bottom": wy - float(w.h) * 0.5, "top": wy + float(w.h) * 0.5, "kind": "window"})
	ops.sort_custom(func(x, y): return x.c < y.c)
	var mat := _wall_mat(room)
	var cursor := 0.0
	var pieces: Array = []  # [s0, s1, y0, y1, skirting]
	for o in ops:
		var s0 := float(o.c) - float(o.w) * 0.5
		var s1 := float(o.c) + float(o.w) * 0.5
		if s0 > cursor + 0.01:
			pieces.append([cursor, s0, fl, ce, true])
		pieces.append([s0, s1, float(o.top), ce, false])
		if float(o.bottom) > fl + 0.01:
			pieces.append([s0, s1, fl, float(o.bottom), true])
		cursor = s1
		_opening_trim(a, d, inward, o, fl, trim, room)
	if cursor < L - 0.01:
		pieces.append([cursor, L, fl, ce, true])
	for pc in pieces:
		var s0: float = pc[0]
		var s1: float = pc[1]
		var y0: float = pc[2]
		var y1: float = pc[3]
		if s1 - s0 < 0.005 or y1 - y0 < 0.005:
			continue
		var mid := a + d * ((s0 + s1) * 0.5) + inward * (WALL_T * 0.5)
		var len := s1 - s0
		var size := Vector3(len, y1 - y0, WALL_T) if absf(d.x) > 0.5 else Vector3(WALL_T, y1 - y0, len)
		var pos := Vector3(mid.x, (y0 + y1) * 0.5, mid.y)
		var bm := BoxMesh.new()
		bm.size = size
		GB.add_mesh(self, bm, pos, Vector3.ZERO, mat)
		# collision: the visual slab plus an outward extension, so no wall is a thin skin. A
		# partition extends to the neighbour room's face (2 x WALL_T solid); a perimeter wall
		# extends WALL_OUT into the house shell.
		var on_edge := absf(a.x - X0) < 0.01 and absf(b.x - X0) < 0.01 or absf(a.x - X1) < 0.01 and absf(b.x - X1) < 0.01 \
				or absf(a.y - Z0) < 0.01 and absf(b.y - Z0) < 0.01 or absf(a.y - Z1) < 0.01 and absf(b.y - Z1) < 0.01
		var ext := WALL_OUT if on_edge else WALL_T
		var cmid := a + d * ((s0 + s1) * 0.5) + inward * ((WALL_T - ext) * 0.5)
		var csize := Vector3(len, y1 - y0, WALL_T + ext) if absf(d.x) > 0.5 else Vector3(WALL_T + ext, y1 - y0, len)
		_coll(csize, Vector3(cmid.x, (y0 + y1) * 0.5, cmid.y))
		if y0 <= fl + 0.01 and y1 - y0 > 0.5:
			var fa := a + d * s0 + inward * WALL_T
			var fb := a + d * s1 + inward * WALL_T
			wall_segments.append({"a": Vector3(fa.x, fl, fa.y), "b": Vector3(fb.x, fl, fb.y), "inward": Vector3(inward.x, 0, inward.y),
					"floor": fl, "room": room.name, "perimeter": on_edge})
		if pc[4]:
			var sk_mid := a + d * ((s0 + s1) * 0.5) + inward * (WALL_T + 0.015)
			var sk := Vector3(len, 0.14, 0.03) if absf(d.x) > 0.5 else Vector3(0.03, 0.14, len)
			GB.box(self, sk, Vector3(sk_mid.x, y0 + 0.07, sk_mid.y), trim.darkened(0.1))
		if y1 >= ce - 0.01:
			var cn_mid := a + d * ((s0 + s1) * 0.5) + inward * (WALL_T + 0.04)
			var cn := Vector3(len, 0.1, 0.08) if absf(d.x) > 0.5 else Vector3(0.08, 0.1, len)
			GB.box(self, cn, Vector3(cn_mid.x, ce - 0.05, cn_mid.y), trim)


func _opening_trim(a: Vector2, d: Vector2, inward: Vector2, o: Dictionary, fl: float, trim: Color, room: Dictionary) -> void:
	var c := float(o.c)
	var w := float(o.w)
	var top := float(o.top)
	var bottom := float(o.bottom)
	var face := inward * (WALL_T + 0.02)
	var horiz := absf(d.x) > 0.5
	var t := trim
	for s: float in [-1.0, 1.0]:
		var p := a + d * (c + s * (w * 0.5 + 0.05)) + face
		var sz := Vector3(0.1, top - bottom, 0.04) if horiz else Vector3(0.04, top - bottom, 0.1)
		GB.box(self, sz, Vector3(p.x, (top + bottom) * 0.5, p.y), t)
	var tp := a + d * c + face
	var tsz := Vector3(w + 0.3, 0.1, 0.04) if horiz else Vector3(0.04, 0.1, w + 0.3)
	GB.box(self, tsz, Vector3(tp.x, top + 0.05, tp.y), t)
	if o.kind == "window":
		# sill ledge, curtain rod and two chunky curtains
		var sl := a + d * c + inward * (WALL_T + 0.08)
		var ssz := Vector3(w + 0.25, 0.05, 0.16) if horiz else Vector3(0.16, 0.05, w + 0.25)
		GB.box(self, ssz, Vector3(sl.x, bottom - 0.02, sl.y), t)
		var curtain: Color = (room.wall as Color).lerp(Color(0.95, 0.3, 0.3), 0.55)
		for s: float in [-1.0, 1.0]:
			var cp := a + d * (c + s * (w * 0.5 + 0.12)) + inward * (WALL_T + 0.1)
			var csz := Vector3(0.32, top - bottom + 0.55, 0.07) if horiz else Vector3(0.07, top - bottom + 0.55, 0.32)
			var cm := BoxMesh.new()
			cm.size = csz
			cm.subdivide_height = 6
			var mi := GB.add_mesh(self, cm, Vector3(cp.x, (top + bottom) * 0.5 - 0.15, cp.y), Vector3.ZERO,
					GB.warped(curtain, csz.y, 0.03, 0.12, s * 2.0 + c))
			mi.rotation_degrees = Vector3(0, 0, _rng.randf_range(-2, 2))
			var cc := Vector3(cp.x, (top + bottom) * 0.5 - 0.15, cp.y)
			_climbable(AABB(cc - csz * 0.5 - Vector3(0, 0, 0), csz), Vector3(inward.x, 0, inward.y), "Curtain", false)
		var rp := a + d * c + inward * (WALL_T + 0.1)
		_anchor(Vector3(rp.x, top + 0.15, rp.y), "grapple", "Curtain rod")
		GB.cylinder(self, 0.02, 0.02, w + 0.8, Vector3(rp.x, top + 0.15, rp.y), Color(0.85, 0.65, 0.3), Vector3(0, 0, 90) if horiz else Vector3(90, 0, 0))
	if (o.kind == "door" or o.kind == "front") and not _doors_made.has(int(o.get("id", -1))):
		# one real hinged door per opening (both rooms see the opening; the first one builds it).
		# A partition door sits on the shared wall line; the street door sits in the perimeter wall.
		_doors_made[int(o.get("id", -1))] = true
		var front: bool = o.kind == "front"
		var mid2 := a + d * c
		# swing into the bigger room (the open slab blocks least there)...
		var pos_side := Vector2(d.y, -d.x)
		var area_pos := _room_area_at(mid2 + pos_side * 0.3, int(room.level))
		var area_neg := _room_area_at(mid2 - pos_side * 0.3, int(room.level))
		var into := pos_side if area_pos >= area_neg else -pos_side
		# ...hinged at the end of the opening nearer that room's corner, so it folds back against
		# the side wall instead of sticking out across the room
		var dd := d
		var rr := _room_rect_at(mid2 + into * 0.3, int(room.level))
		if rr.size != Vector2.ZERO:
			var lo := INF
			var hi := -INF
			for corner: Vector2 in [rr.position, rr.end, Vector2(rr.position.x, rr.end.y), Vector2(rr.end.x, rr.position.y)]:
				lo = minf(lo, (corner - a).dot(d))
				hi = maxf(hi, (corner - a).dot(d))
			if (hi - (c + w * 0.5)) < ((c - w * 0.5) - lo):
				dd = -d  # hinge on the far end, slab runs back along -d
		var hinge := mid2 - dd * (w * 0.5 - 0.01) + (inward * (WALL_T * 0.5) if front else Vector2.ZERO)
		var dr := Door.new()
		dr.name = "FrontDoor" if front else "Door%d" % doors.size()
		dr.position = Vector3(hinge.x, fl, hinge.y)
		dr.rotation.y = atan2(-dd.y, dd.x)
		add_child(dr)
		# a positive swing moves the slab toward (dd.y, -dd.x)
		var sgn := 1.0 if into.dot(Vector2(dd.y, -dd.x)) > 0.0 else -1.0
		var roll := _rng.randf()
		var start := 0.0
		if not front:
			start = 0.0 if roll < doors_closed_chance else (door_ajar_angle if roll < doors_closed_chance + doors_ajar_chance else dr.open_angle)
		dr.locked = front
		# the handle mechanism decides which tricks open it (seeded per house and room)
		var hr := RandomNumberGenerator.new()
		hr.seed = 7700 + _tier_rng.seed * 3 + doors.size() * 17
		var kind := "lever"
		var rn := str(room.get("name", "")).to_lower()
		if front:
			kind = "lever" if hr.randf() < 0.6 else "knob"
		elif "bath" in rn or "toilet" in rn:
			kind = "knob" if hr.randf() < 0.7 else "lever"
		elif "kitchen" in rn and hr.randf() < 0.6:
			kind = "plate"
		else:
			var x := hr.randf()
			kind = "lever" if x < 0.5 else ("knob" if x < 0.8 else "slide")
		dr.configure(kind, front)
		if kind == "slide":
			start = 0.0 if start < 1.0 else start
		dr.setup(Furn.mesh_of("InteriorDoor"), w - 0.02, start, sgn)
		dr.prefer_sign = sgn
		dr.set_meta("door", true)
		doors.append(dr)


# =================================================================================================
# Stairs (two-storey house)
# =================================================================================================

func _build_stairs() -> void:
	var xb := float(stairs.x_bottom)
	var xt := float(stairs.x_top)
	var z0 := float(stairs.z0) + WALL_T
	var z1 := float(stairs.z1)
	var y0 := floor_y
	var y1 := 3.1
	var steps := 15
	var run := (xb - xt) / steps
	var rise := (y1 - y0) / steps
	var wood := Furn.mesh_of("Couch")  # warm-up the cache (no-op)
	var tread_mat := _floor_mat(3)
	for i in steps:
		var x := xb - (i + 0.5) * run
		var h := (i + 1) * rise
		var bm := BoxMesh.new()
		bm.size = Vector3(run + 0.02, h, z1 - z0)
		GB.add_mesh(self, bm, Vector3(x, y0 + h * 0.5, (z0 + z1) * 0.5), Vector3.ZERO, tread_mat)
		GB.box(self, Vector3(run + 0.04, 0.03, z1 - z0 + 0.04), Vector3(x, y0 + h + 0.015, (z0 + z1) * 0.5), Color(0.96, 0.9, 0.78))
	# a smooth ramp collider so the elf walks straight up
	var L := Vector2(xb - xt, y1 - y0).length()
	var ang := atan2(y1 - y0, xb - xt)
	var mid := Vector3((xb + xt) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
	var n := Vector3(sin(ang), cos(ang), 0)
	# extend only past the bottom (into the floor); the top edge sits flush with the landing so the
	# elf can walk back down without catching a lip
	var down := Vector3(cos(ang), -sin(ang), 0)
	_coll(Vector3(L + 0.3, 0.1, z1 - z0), mid - n * 0.05 + down * 0.15, Vector3(0, 0, -ang))
	# banister on the open side
	var rail_z := z1 + 0.03
	for i in 6:
		var x := xb - (i + 0.5) * (xb - xt) / 6.0
		var hh := y0 + (xb - x) / (xb - xt) * (y1 - y0)
		GB.cylinder(self, 0.025, 0.025, 0.9, Vector3(x, hh + 0.45, rail_z), Color(0.98, 0.95, 0.88))
	var rail := GB.cylinder(self, 0.04, 0.04, L, mid + Vector3(0, 0.9, rail_z - mid.z), Color(0.55, 0.3, 0.15), Vector3(0, 0, 90))
	rail.rotation = Vector3(0, 0, PI * 0.5 - ang)
	_coll(Vector3(L, 1.0, 0.06), mid + Vector3(0, 0.5, rail_z - mid.z), Vector3(0, 0, -ang))
	# railing around the stairwell upstairs
	GB.box(self, Vector3(xb - xt, 0.06, 0.06), Vector3((xb + xt) * 0.5, y1 + 0.9, z1 + 0.03), Color(0.55, 0.3, 0.15))
	for i in 7:
		GB.cylinder(self, 0.02, 0.02, 0.9, Vector3(xt + 0.3 + i * (xb - xt - 0.4) / 6.0, y1 + 0.45, z1 + 0.03), Color(0.98, 0.95, 0.88))
	_coll(Vector3(xb - xt, 1.0, 0.08), Vector3((xb + xt) * 0.5, y1 + 0.5, z1 + 0.03))
	# rappel down the stairwell from the upstairs railing, or swing from the banister
	_anchor(Vector3((xb + xt) * 0.5 + 0.6, y1 + 0.93, z1 + 0.03), "ledge", "Stair rail", Vector3(0, 0, -1))
	_anchor(mid + Vector3(0, 0.93, rail_z - mid.z), "grapple", "Banister")


## Copper water pipes beside the fireplace and in the kitchen corner (the Icer can freeze them).
func _build_pipes() -> void:
	var lv := _r("Living")
	var f := float(lv.floor)
	var rc: Rect2 = lv.rect
	var px := fireplace_x + 1.35 if fireplace_x + 1.6 < rc.end.x else fireplace_x - 1.35
	var z := Z0 + WALL_T + 0.07
	_pipe_run([Vector3(px, f, z), Vector3(px, f + 1.9, z), Vector3(px + (0.9 if px > fireplace_x else -0.9), f + 1.9, z), Vector3(px + (0.9 if px > fireplace_x else -0.9), float(lv.ceil), z)],
			Vector3(px, f + 1.0, z + 0.05), Vector3(0, 0.2, 1), 1.0)
	var kt := _r("Kitchen")
	var kr: Rect2 = kt.rect
	var kf := float(kt.floor)
	var corner := Vector3(kr.end.x - WALL_T - 0.07, kf, kr.end.y - WALL_T - 0.07)
	_pipe_run([corner, corner + Vector3(0, 1.4, 0), corner + Vector3(-1.0, 1.4, 0), corner + Vector3(-1.0, float(kt.ceil) - kf, 0)],
			corner + Vector3(-0.5, 1.4, -0.05), Vector3(0, 0.1, -1).normalized(), 0.8)


## exposure: how much of the Icer's freeze reaches this run (the fireplace pipes get it all).
func _pipe_run(pts: Array, spray: Vector3, dir: Vector3, exposure := 1.0) -> void:
	var copper := Color(0.85, 0.45, 0.22)
	var m := GB.mat(copper, 0.0, 0.3, 0.6).duplicate() as ShaderMaterial
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.035
		cm.bottom_radius = 0.035
		cm.height = a.distance_to(b)
		cm.radial_segments = 10
		mi.mesh = cm
		mi.material_override = m
		add_child(mi)
		mi.position = (a + b) * 0.5
		var d := (b - a).normalized()
		if absf(d.y) < 0.99:
			mi.quaternion = Quaternion(Vector3.UP, d)
		var el := GB.sphere(self, 0.05, b, copper)
		el.material_override = m
		for k in [0.25, 0.75]:
			GB.box(self, Vector3(0.1, 0.03, 0.1), a.lerp(b, k), Color(0.4, 0.4, 0.42))
	var valve := GB.torus(self, 0.05, 0.09, spray + Vector3(0, 0.25, 0.03), Color(0.85, 0.1, 0.1), Vector3(90, 0, 0))
	var cracks := []
	for k in 3:
		var c := GB.box(self, Vector3(0.012, 0.12, 0.012), spray + Vector3((k - 1) * 0.02, (k - 1) * 0.04, 0.035), Color(0.05, 0.05, 0.08), Vector3(0, 0, (k - 1) * 30.0))
		c.visible = false
		cracks.append(c)
	var puddle := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 1.0
	pm.bottom_radius = 1.0
	pm.height = 0.01
	pm.radial_segments = 32
	puddle.mesh = pm
	puddle.material_override = GB.mat(Color(0.3, 0.55, 0.9), 0.15, 0.5, 3.0)
	var floor_at := Vector3(spray.x, 0.0, spray.z) + Vector3(dir.x, 0, dir.z).normalized() * 0.4
	floor_at.y = float(pts[0].y) + 0.012
	puddle.position = floor_at
	puddle.scale = Vector3(0.01, 1, 0.01)
	puddle.visible = false
	add_child(puddle)
	pipes.append({"mat": m, "base": copper, "spray_pos": spray, "dir": dir, "cracks": cracks, "puddle": puddle, "spray": null, "state": 0, "valve": valve, "exposure": exposure})


func _set_layers(n: Node) -> void:
	for c in n.get_children():
		if c is VisualInstance3D and not (c is Light3D):
			(c as VisualInstance3D).layers = VIS_LAYER
			if c is GeometryInstance3D and (c as GeometryInstance3D).visibility_range_end == 0.0:
				(c as GeometryInstance3D).visibility_range_end = Furn.VIS_RANGE
		_set_layers(c)


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for c in get_children():
		if c is OmniLight3D and c.has_meta("twinkle"):
			var k := int(c.get_meta("twinkle"))
			(c as OmniLight3D).light_energy = tree_light_energy * (0.75 + 0.25 * sin(t * (2.0 + k) + k * 1.7))
