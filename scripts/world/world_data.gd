extends RefCounted
## Reads the streamed-world packs written by tools/world/world_tiles.py (data/world/blocks/<lat>_<lon>.pack).
## Thread-safe: worker threads call tile() while the main thread streams. Each read opens its own FileAccess;
## the block headers and a small LRU of decoded tiles are shared behind a mutex.
## Map data (c) OpenStreetMap contributors, ODbL 1.0.

const Geo := preload("res://scripts/world/geo.gd")
const KINDS := ["house", "shed", "shop", "apartments", "church", "civic", "other"]
const TILE_CACHE := 160

var root := "res://data/world"
var index: Dictionary = {}
var _blocks: Dictionary = {}  # key -> Dictionary ({} = missing)
var _tiles: Dictionary = {}  # Vector2i -> decoded tile
var _lru: Array[Vector2i] = []
var _mx := Mutex.new()
var bytes_read := 0


func load_index() -> bool:
	var p := root + "/index.json"
	if not FileAccess.file_exists(p):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	if typeof(d) != TYPE_DICTIONARY or d.get("format", "") != "santa-sim-world":
		return false
	index = d
	return true


func has_block(key: String) -> bool:
	return (index.get("blocks", {}) as Dictionary).has(key)


## Header + tile table of a block, or {} when it is not built. Loads on first use (call from a worker).
func block(key: String) -> Dictionary:
	_mx.lock()
	if _blocks.has(key):
		var b: Dictionary = _blocks[key]
		_mx.unlock()
		return b
	_mx.unlock()
	var nb := _read_block(key)
	_mx.lock()
	_blocks[key] = nb
	_mx.unlock()
	return nb


## Only what is already loaded (never touches the disk: safe on the main thread).
func block_if_loaded(key: String):
	_mx.lock()
	var b = _blocks.get(key)
	_mx.unlock()
	return b


static func _s16(v: int) -> int:
	return v - 65536 if v >= 32768 else v


static func _s32(v: int) -> int:
	return v - 4294967296 if v >= 2147483648 else v


func _read_block(key: String) -> Dictionary:
	var path := "%s/blocks/%s.pack" % [root, key]
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_buffer(4).get_string_from_ascii() != "SSWP":
		return {}
	var _ver := f.get_16()
	var bx := _s16(f.get_16())
	var by := _s16(f.get_16())
	var _tlon := f.get_16()
	var _tlat := f.get_16()
	var cells := f.get_16()
	var n := f.get_32()
	var ow := f.get_16()
	var oh := f.get_16()
	var ovl := f.get_32()
	var ov := f.get_buffer(ovl).decompress(ow * oh, FileAccess.COMPRESSION_DEFLATE)
	var tiles := {}
	var nb_total := 0
	for i in n:
		var ix := _s32(f.get_32())
		var iy := _s32(f.get_32())
		var off := f.get_32()
		var cl := f.get_32()
		var ul := f.get_32()
		var nb := f.get_16()
		var fl := f.get_16()
		tiles[Vector2i(ix, iy)] = PackedInt64Array([off, cl, ul, nb, fl])
		nb_total += nb
	return {"key": key, "bx": bx, "by": by, "path": path, "tiles": tiles, "ov": ov, "ow": ow, "oh": oh, "cells": cells, "buildings": nb_total}


## Table entry [off, clen, ulen, buildings, flags] for a tile, or an empty array (block must be loaded).
func tile_entry(t: Vector2i) -> PackedInt64Array:
	var b = block_if_loaded(Geo.block_key(Geo.block_of(t)))
	if b == null or (b as Dictionary).is_empty():
		return PackedInt64Array()
	return (b.tiles as Dictionary).get(t, PackedInt64Array())


## Average buildings per tile over the 3 x 3 tiles around t (remote / rural / suburban style rules).
func density(t: Vector2i) -> float:
	var s := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var e := tile_entry(t + Vector2i(dx, dy))
			if e.size() > 0:
				s += int(e[3])
	return s / 9.0


## Decoded tile: {"buildings": [dict like the town JSON], "roads": [[type, width, flags, PackedVector2Array]],
## "trees": PackedVector2Array, "ground": PackedByteArray (32 x 32 classes, row 0 = north)}. {} if absent.
func tile(t: Vector2i) -> Dictionary:
	_mx.lock()
	if _tiles.has(t):
		var d: Dictionary = _tiles[t]
		_lru.erase(t)
		_lru.append(t)
		_mx.unlock()
		return d
	_mx.unlock()
	var b := block(Geo.block_key(Geo.block_of(t)))
	if b.is_empty() or not (b.tiles as Dictionary).has(t):
		return {}
	var e: PackedInt64Array = b.tiles[t]
	var f := FileAccess.open(String(b.path), FileAccess.READ)
	if f == null:
		return {}
	f.seek(int(e[0]))
	var raw := f.get_buffer(int(e[1])).decompress(int(e[2]), FileAccess.COMPRESSION_DEFLATE)
	var d := _decode(raw)
	_mx.lock()
	bytes_read += int(e[1])
	_tiles[t] = d
	_lru.append(t)
	while _lru.size() > TILE_CACHE:
		_tiles.erase(_lru.pop_front())
	_mx.unlock()
	return d


static func _decode(raw: PackedByteArray) -> Dictionary:
	var sp := StreamPeerBuffer.new()
	sp.data_array = raw
	var _ver := sp.get_u16()
	var nb := sp.get_u16()
	var nr := sp.get_u16()
	var nt := sp.get_u16()
	var hg := sp.get_u8()
	var ground := PackedByteArray()
	if hg:
		ground = sp.get_data(1024)[1]
	var buildings: Array = []
	for i in nb:
		var id := sp.get_64()
		var kind := sp.get_u8()
		var roof := sp.get_u8()
		var lv2 := sp.get_u8()
		var h := sp.get_u8()
		var cx := sp.get_16() * 0.1
		var cy := sp.get_16() * 0.1
		var w := sp.get_u16() * 0.1
		var dd := sp.get_u16() * 0.1
		var area := sp.get_u16()
		var ang := sp.get_16() / 10000.0
		var face := sp.get_u8()
		var hf := sp.get_u8()
		var fang := sp.get_16() / 10000.0
		var al := sp.get_u8()
		var addr := sp.get_utf8_string(al) if al > 0 else ""
		buildings.append({"id": id, "kind": KINDS[mini(kind, KINDS.size() - 1)], "roof": roof,
				"levels": (lv2 / 2.0) if lv2 > 0 else null, "height": float(h) if h > 0 else null, "area": float(area),
				"obb": {"c": [cx, cy], "size": [w, dd], "angle": ang}, "front": [cos(fang), sin(fang)] if hf else null,
				"front_face": face, "addr": addr})
	var roads: Array = []
	for i in nr:
		var typ := sp.get_u8()
		var wd := sp.get_u8() / 4.0
		var fl := sp.get_u8()
		var n := sp.get_u16()
		var pts := PackedVector2Array()
		pts.resize(n)
		for k in n:
			pts[k] = Vector2(sp.get_16() * 0.1, sp.get_16() * 0.1)
		roads.append([typ, wd, fl, pts])
	var trees := PackedVector2Array()
	trees.resize(nt)
	for i in nt:
		trees[i] = Vector2(sp.get_16() * 0.1, sp.get_16() * 0.1)
	return {"buildings": buildings, "roads": roads, "trees": trees, "ground": ground}
