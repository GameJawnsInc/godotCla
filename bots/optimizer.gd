extends "res://bots/bot_base.gd"
## Optimizer persona: deterministic heuristic play aimed at winning.
## Priorities: descend > strike > lance > dodge telegraphed damage > cleanse
## when safe > path to stairs > pull a blocker into reach > end turn.

const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


func get_bot_name() -> String:
	return "optimizer"


func choose_action(snap: Dictionary, legal: Array) -> Dictionary:
	var ppos: Vector2i = snap["player"]["pos"]
	var by := {}
	for a in legal:
		var k: String = a["type"]
		if not by.has(k):
			by[k] = []
		by[k].append(a)

	if by.has("descend"):
		return by["descend"][0]

	var threat := _threat_tiles(snap)

	if by.has("strike"):
		var best = null
		var best_hp := 999
		for a in by["strike"]:
			var e = _enemy_at(snap, ppos + a["dir"])
			if e != null and e["hp"] < best_hp:
				best_hp = e["hp"]
				best = a
		if best != null:
			return best

	if by.has("ability"):
		for a in by["ability"]:
			if snap["player"]["kit"][a["slot"]] == "solar_lance" and _lance_hits(snap, a["target"]):
				return a

	if threat.has(ppos) and by.has("move"):
		for a in by["move"]:
			var dest: Vector2i = ppos + a["dir"]
			if not threat.has(dest) and not _hazard(snap, dest):
				return a

	if by.has("cleanse") and _nearest_enemy_dist(snap) > 3:
		return by["cleanse"][0]

	if by.has("move"):
		var step := _path_step(snap, threat)
		if step != Vector2i.ZERO:
			for a in by["move"]:
				if a["dir"] == step:
					return a

	if by.has("ability"):
		for a in by["ability"]:
			if snap["player"]["kit"][a["slot"]] == "vine_whip":
				return a

	return legal[legal.size() - 1]


func _threat_tiles(snap: Dictionary) -> Dictionary:
	var t := {}
	for e in snap["enemies"]:
		if String(e["intent"].get("type", "")) == "attack":
			t[e["intent"]["tile"]] = true
	for tile in snap["terrain"].keys():
		if snap["terrain"][tile]["kind"] == "fire":
			t[tile] = true
	return t


func _enemy_at(snap: Dictionary, pos: Vector2i):
	for e in snap["enemies"]:
		if e["pos"] == pos:
			return e
	return null


func _nearest_enemy_dist(snap: Dictionary) -> int:
	var ppos: Vector2i = snap["player"]["pos"]
	var best := 999
	for e in snap["enemies"]:
		var d: int = absi(e["pos"].x - ppos.x) + absi(e["pos"].y - ppos.y)
		if d < best:
			best = d
	return best


func _hazard(snap: Dictionary, pos: Vector2i) -> bool:
	var k: String = snap["terrain"].get(pos, {}).get("kind", "")
	return k == "fire" or k == "goo"


func _lance_hits(snap: Dictionary, dir: Vector2i) -> bool:
	var m: Dictionary = snap["map"]
	var p: Vector2i = snap["player"]["pos"]
	for i in 3:
		p += dir
		if p.x < 0 or p.y < 0 or p.x >= int(m["w"]) or p.y >= int(m["h"]):
			return false
		if m["tiles"][p.y * int(m["w"]) + p.x] != 1:
			return false
		if snap["terrain"].get(p, {}).get("kind", "") == "smoke":
			return false
		if _enemy_at(snap, p) != null:
			return true
	return false


func _path_step(snap: Dictionary, threat: Dictionary) -> Vector2i:
	var stairs: Vector2i = snap["map"]["stairs"]
	var step := _bfs_step(snap, true, threat, stairs)
	if step != Vector2i.ZERO:
		return step
	step = _bfs_step(snap, false, threat, stairs)
	if step != Vector2i.ZERO:
		return step
	# Route to the stairs is blocked by enemies: advance on the nearest one.
	var target := _nearest_enemy_pos(snap)
	if target != Vector2i(-1, -1):
		return _bfs_step(snap, false, threat, target)
	return Vector2i.ZERO


func _nearest_enemy_pos(snap: Dictionary) -> Vector2i:
	var ppos: Vector2i = snap["player"]["pos"]
	var best := Vector2i(-1, -1)
	var best_d := 9999
	for e in snap["enemies"]:
		var d: int = absi(e["pos"].x - ppos.x) + absi(e["pos"].y - ppos.y)
		if d < best_d:
			best_d = d
			best = e["pos"]
	return best


func _bfs_step(snap: Dictionary, strict: bool, threat: Dictionary, goal: Vector2i) -> Vector2i:
	var m: Dictionary = snap["map"]
	var w: int = m["w"]
	var h: int = m["h"]
	var start: Vector2i = snap["player"]["pos"]
	var occupied := {}
	for e in snap["enemies"]:
		occupied[e["pos"]] = true
	var prev := {}
	prev[start] = start
	var queue: Array = [start]
	var qi := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		var arrived: bool = cur == goal
		if occupied.has(goal):
			arrived = absi(cur.x - goal.x) + absi(cur.y - goal.y) == 1
		if arrived:
			var node := cur
			while prev[node] != start:
				node = prev[node]
			return node - start
		for d in DIRS:
			var nxt: Vector2i = cur + d
			if nxt.x < 0 or nxt.y < 0 or nxt.x >= w or nxt.y >= h:
				continue
			if m["tiles"][nxt.y * w + nxt.x] != 1:
				continue
			if prev.has(nxt) or occupied.has(nxt):
				continue
			if strict:
				if threat.has(nxt):
					continue
				var k: String = snap["terrain"].get(nxt, {}).get("kind", "")
				if k == "fire" or k == "goo":
					continue
			prev[nxt] = cur
			queue.append(nxt)
	return Vector2i.ZERO
