extends RefCounted
## Regional house styles for the streamed world (same style names as scripts/town/house_gen.gd).
## - QLD suburbs keep the exact Paddington rules (HouseGen.pick_style), so Paddington looks the same in both
##   scenes: Queenslanders on stumps, cottages, fibro, some brick.
## - The tropical north (NT Top End, Kimberley): elevated tropical homes and fibro under corrugated iron.
## - The south (NSW, VIC, SA, WA, TAS, ACT): brick veneer under terracotta tile, terraces/cottages, fibro.
## - Remote areas (very few buildings around): low-set fibro / weatherboard under corrugated iron.
## Only the existing house_gen styles are used: the house models themselves are never changed here.
## OSM roof:material (tile / metal) and roof:shape=flat win over the regional dice.

const HouseGen := preload("res://scripts/town/house_gen.gd")
const REMOTE_DENSITY := 6.0  ## average buildings per ~1 km tile (3 x 3 around) below which it is "remote"


static func region_of(lat: float, lon: float) -> String:
	if lon >= 138.0 and lat > -28.95:
		return "qld"
	if lat > -20.0:
		return "tropic"
	return "south"


static func pick(b: Dictionary, rng: RandomNumberGenerator, region: String, density: float) -> String:
	var kind := String(b.kind)
	if kind != "house":
		return HouseGen.pick_style(b, rng)
	if region == "qld" and density >= REMOTE_DENSITY:
		return HouseGen.pick_style(b, rng)
	var roof := int(b.get("roof", 0))
	var area := float(b.area)
	var lv = b.get("levels")
	var r := rng.randf()
	if density < REMOTE_DENSITY:
		return "fibro" if area < 160.0 or r < 0.7 else "queenslander"
	if (roof & 12) == 4:
		return "modern"
	if (roof & 3) == 1:
		return "brick"
	if lv != null and float(lv) >= 2.0 and r < 0.55:
		return "modern"
	if region == "tropic":
		if (roof & 3) == 2:
			return "queenslander" if r < 0.6 else "fibro"
		return "queenslander" if r < 0.45 else ("fibro" if r < 0.8 else "brick")
	# south
	if (roof & 3) == 2:
		return "cottage" if r < 0.45 else "fibro"
	if area < 110.0:
		return "cottage" if r < 0.45 else ("brick" if r < 0.8 else "fibro")
	if r < 0.58:
		return "brick"
	if r < 0.74:
		return "fibro"
	if r < 0.88:
		return "cottage"
	return "modern"
