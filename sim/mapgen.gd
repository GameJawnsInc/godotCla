extends RefCounted
## Floor generator with pluggable invariant checks (style guide §7).

const T_WALL := 0
const T_FLOOR := 1

const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

const DEFAULT_INVARIANTS := [
	"stairs_reachable",
	"entities_on_floor",
	"terrain_on_floor",
	"clear_start_and_stairs",
	"shrine_reachable",
]

## Boss arenas have no stairs or shrine; the exam is reaching and killing the boss.
const BOSS_INVARIANTS := [
	"boss_reachable",
	"entities_on_floor",
	"terrain_on_floor",
]


static func generate(rng: RandomNumberGenerator, fdef: Dictionary) -> Dictionary:
	if fdef.get("boss", false):
		return _generate_boss_arena(rng, fdef)
	var w: int = fdef["w"]
	var h: int = fdef["h"]
	var tiles: Array = []
	tiles.resize(w * h)
	tiles.fill(T_WALL)

	var rooms: Array = []
	var attempts := 0
	while rooms.size() < int(fdef["rooms"]) and attempts < 300:
		attempts += 1
		var rw := rng.randi_range(4, 7)
		var rh := rng.randi_range(3, 5)
		var rx := rng.randi_range(1, w - rw - 2)
		var ry := rng.randi_range(1, h - rh - 2)
		var rect := Rect2i(rx, ry, rw, rh)
		var ok := true
		for r in rooms:
			if rect.grow(1).intersects(r):
				ok = false
				break
		if ok:
			rooms.append(rect)

	for r in rooms:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				tiles[y * w + x] = T_FLOOR
	for i in range(rooms.size() - 1):
		_carve_corridor(tiles, w, rooms[i].get_center(), rooms[i + 1].get_center(), rng)

	var start: Vector2i = rooms[0].get_center()
	var stairs: Vector2i = rooms[rooms.size() - 1].get_center()
	var taken: Array = [start, stairs]

	var vents: Array = []
	for i in range(int(fdef["vents"])):
		var v := _pick_floor(rng, tiles, w, h, taken, start, 0)
		if v != Vector2i(-1, -1):
			vents.append(v)
			taken.append(v)

	var shrine := _pick_floor(rng, tiles, w, h, taken, start, 3)
	if shrine != Vector2i(-1, -1):
		taken.append(shrine)

	var enemies: Array = []
	for kind in fdef["enemies"]:
		for i in range(int(fdef["enemies"][kind])):
			var p := _pick_floor(rng, tiles, w, h, taken, start, 5)
			if p == Vector2i(-1, -1):
				p = _pick_floor(rng, tiles, w, h, taken, start, 2)
			if p != Vector2i(-1, -1):
				enemies.append({"kind": kind, "pos": p})
				taken.append(p)

	var terrain := {}
	for i in range(int(fdef["oil"])):
		var p := _pick_floor(rng, tiles, w, h, taken, start, 2)
		if p != Vector2i(-1, -1):
			terrain[p] = {"kind": "oil"}
			taken.append(p)
	for i in range(int(fdef["goo"])):
		var p := _pick_floor(rng, tiles, w, h, taken, start, 2)
		if p != Vector2i(-1, -1):
			terrain[p] = {"kind": "goo"}
			taken.append(p)

	return {
		"w": w, "h": h, "tiles": tiles,
		"start": start, "stairs": stairs, "vents": vents, "shrine": shrine,
		"enemies": enemies, "terrain": terrain,
	}


static func _generate_boss_arena(rng: RandomNumberGenerator, fdef: Dictionary) -> Dictionary:
	var w: int = fdef["w"]
	var h: int = fdef["h"]
	var tiles: Array = []
	tiles.resize(w * h)
	tiles.fill(T_WALL)
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			tiles[y * w + x] = T_FLOOR

	var start := Vector2i(2, h / 2)
	var boss_pos := Vector2i(w - 3, h / 2)

	# scattered pillars for cover, kept away from the combatants
	var pillars := 0
	var attempts := 0
	while pillars < 5 and attempts < 60:
		attempts += 1
		var p := Vector2i(rng.randi_range(3, w - 4), rng.randi_range(2, h - 3))
		if absi(p.x - start.x) + absi(p.y - start.y) < 3:
			continue
		if absi(p.x - boss_pos.x) + absi(p.y - boss_pos.y) < 3:
			continue
		if tiles[p.y * w + p.x] == T_FLOOR:
			tiles[p.y * w + p.x] = T_WALL
			pillars += 1

	var taken: Array = [start, boss_pos]
	var vents: Array = []
	for i in range(int(fdef["vents"])):
		var v := _pick_floor(rng, tiles, w, h, taken, start, 4)
		if v != Vector2i(-1, -1):
			vents.append(v)
			taken.append(v)
	var terrain := {}
	for i in range(int(fdef["oil"])):
		var p := _pick_floor(rng, tiles, w, h, taken, start, 2)
		if p != Vector2i(-1, -1):
			terrain[p] = {"kind": "oil"}
			taken.append(p)

	return {
		"w": w, "h": h, "tiles": tiles,
		"start": start, "stairs": Vector2i(-1, -1), "vents": vents, "shrine": Vector2i(-1, -1),
		"enemies": [{"kind": "furnace_core", "pos": boss_pos}], "terrain": terrain,
	}


static func _carve_corridor(tiles: Array, w: int, a: Vector2i, b: Vector2i, rng: RandomNumberGenerator) -> void:
	var p := a
	if rng.randi_range(0, 1) == 0:
		while p.x != b.x:
			p.x += signi(b.x - p.x)
			tiles[p.y * w + p.x] = T_FLOOR
		while p.y != b.y:
			p.y += signi(b.y - p.y)
			tiles[p.y * w + p.x] = T_FLOOR
	else:
		while p.y != b.y:
			p.y += signi(b.y - p.y)
			tiles[p.y * w + p.x] = T_FLOOR
		while p.x != b.x:
			p.x += signi(b.x - p.x)
			tiles[p.y * w + p.x] = T_FLOOR


static func _pick_floor(rng: RandomNumberGenerator, tiles: Array, w: int, h: int, taken: Array, origin: Vector2i, min_dist: int) -> Vector2i:
	var candidates: Array = []
	for y in h:
		for x in w:
			var p := Vector2i(x, y)
			if tiles[y * w + x] != T_FLOOR:
				continue
			if taken.has(p):
				continue
			if absi(p.x - origin.x) + absi(p.y - origin.y) < min_dist:
				continue
			candidates.append(p)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func validate(gen: Dictionary, invariants: Array = DEFAULT_INVARIANTS) -> Array:
	var fails: Array = []
	for inv in invariants:
		match inv:
			"stairs_reachable":
				if not _reachable(gen, gen["start"], gen["stairs"]):
					fails.append("stairs not reachable from start")
			"entities_on_floor":
				for e in gen["enemies"]:
					if _tile_at(gen, e["pos"]) != T_FLOOR:
						fails.append("enemy in wall at %s" % str(e["pos"]))
					if e["pos"] == gen["start"]:
						fails.append("enemy on start")
				for v in gen["vents"]:
					if _tile_at(gen, v) != T_FLOOR:
						fails.append("vent in wall at %s" % str(v))
			"terrain_on_floor":
				for t in gen["terrain"].keys():
					if _tile_at(gen, t) != T_FLOOR:
						fails.append("terrain in wall at %s" % str(t))
			"clear_start_and_stairs":
				if gen["terrain"].has(gen["start"]) or gen["terrain"].has(gen["stairs"]):
					fails.append("hazard on start or stairs")
				for e in gen["enemies"]:
					if e["pos"] == gen["stairs"]:
						fails.append("enemy on stairs")
			"shrine_reachable":
				if gen["shrine"] == Vector2i(-1, -1):
					fails.append("no shrine placed")
				elif not _reachable(gen, gen["start"], gen["shrine"]):
					fails.append("shrine not reachable from start")
			"boss_reachable":
				var found := false
				for e in gen["enemies"]:
					if e["kind"] == "furnace_core":
						found = true
						var adjacent_ok := false
						for d in DIRS:
							var p: Vector2i = e["pos"] + d
							if _tile_at(gen, p) == T_FLOOR and _reachable(gen, gen["start"], p):
								adjacent_ok = true
						if not adjacent_ok:
							fails.append("boss not reachable from start")
				if not found:
					fails.append("no boss on boss floor")
	return fails


static func _tile_at(gen: Dictionary, p: Vector2i) -> int:
	if p.x < 0 or p.y < 0 or p.x >= int(gen["w"]) or p.y >= int(gen["h"]):
		return T_WALL
	return gen["tiles"][p.y * int(gen["w"]) + p.x]


static func _reachable(gen: Dictionary, from: Vector2i, to: Vector2i) -> bool:
	var seen := {}
	seen[from] = true
	var queue: Array = [from]
	var qi := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		if cur == to:
			return true
		for d in DIRS:
			var nxt: Vector2i = cur + d
			if seen.has(nxt):
				continue
			if _tile_at(gen, nxt) != T_FLOOR:
				continue
			seen[nxt] = true
			queue.append(nxt)
	return false
