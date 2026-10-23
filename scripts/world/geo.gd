extends RefCounted
## Lat/lon <-> local metres around a movable origin (the floating origin of the streamed world).
## GDScript floats are 64-bit, so lat/lon and the origin stay exact; only the small local results go into
## (32-bit) Vector3s. Mean-latitude equirectangular: centimetre-accurate for everything within ~20 km of the
## origin, which is all that is ever loaded. Godot axes: x = east, z = -north (same as the town scene).

const R := 6378137.0
const DEG := 111319.49079327357  ## metres per degree of latitude (deg_to_rad(1) * R)
const TLON := 100  ## tiles per degree of longitude (tools/world/world_tiles.py)
const TLAT := 111  ## tiles per degree of latitude

var lat0 := 0.0
var lon0 := 0.0


func _init(lat := 0.0, lon := 0.0) -> void:
	lat0 = lat
	lon0 = lon


func set_origin(lat: float, lon: float) -> void:
	lat0 = lat
	lon0 = lon


## Metres east / north of the origin.
func east_north(lat: float, lon: float) -> Vector2:
	var k := DEG * cos(deg_to_rad((lat + lat0) * 0.5))
	return Vector2((lon - lon0) * k, (lat - lat0) * DEG)


func to_world(lat: float, lon: float, y := 0.0) -> Vector3:
	var k := DEG * cos(deg_to_rad((lat + lat0) * 0.5))
	return Vector3((lon - lon0) * k, y, -(lat - lat0) * DEG)


## World position -> [lat, lon].
func to_latlon(p: Vector3) -> PackedFloat64Array:
	var lat := lat0 + (-p.z) / DEG
	var k := DEG * cos(deg_to_rad((lat + lat0) * 0.5))
	return PackedFloat64Array([lat, lon0 + p.x / k])


static func tile_of(lat: float, lon: float) -> Vector2i:
	return Vector2i(floori(lon * TLON), floori(lat * TLAT))


static func tile_centre(t: Vector2i) -> PackedFloat64Array:
	return PackedFloat64Array([(t.y + 0.5) / TLAT, (t.x + 0.5) / TLON])


## Tile width (east) x height (north) in metres.
static func tile_dims(t: Vector2i) -> Vector2:
	var lat := (t.y + 0.5) / TLAT
	return Vector2(DEG * cos(deg_to_rad(lat)) / TLON, DEG / TLAT)


## Block (bx, by) = (floor(lon), floor(lat)) that holds a tile.
static func block_of(t: Vector2i) -> Vector2i:
	return Vector2i(floori(t.x / float(TLON)), floori(t.y / float(TLAT)))


static func block_key(b: Vector2i) -> String:
	return "%d_%d" % [b.y, b.x]
