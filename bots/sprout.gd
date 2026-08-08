extends "res://bots/bot_base.gd"
## Sprout persona: cautious noob. Greedy for Bloom even when unsafe, panics at
## low HP, hazard-blind movement, wastes charge, and only uses the obvious
## buttons (strike, lance). Measures teaching-curve fairness.

const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


func get_bot_name() -> String:
	return "sprout"


func choose_action(snap: Dictionary, legal: Array) -> Dictionary:
	if snap["phase"] == "draft":
		return _draft_choice(snap, legal)
	var ppos: Vector2i = snap["player"]["pos"]
	var by := {}
	for a in legal:
		var k: String = a["type"]
		if not by.has(k):
			by[k] = []
		by[k].append(a)

	# impulse shopping: heal first, then whatever is shiny
	if by.has("buy") and rng.randf() < 0.5:
		for item in ["heal", "ability", "graft"]:
			for a in by["buy"]:
				if a["item"] == item:
					return a

	# usually takes the stairs, sometimes lingers
	if by.has("descend") and rng.randf() < 0.9:
		return by["descend"][0]

	# bloom greed: cleanses with enemies bearing down, as long as none is adjacent
	if by.has("cleanse") and not _enemy_adjacent(snap):
		return by["cleanse"][0]

	# fights what is in the face, but only while feeling healthy
	if by.has("strike") and snap["player"]["hp"] > 4:
		return by["strike"][0]

	# panic: run from the nearest enemy, blind to goo and fire
	if snap["player"]["hp"] <= 4 and _nearest_enemy_dist(snap) <= 3 and by.has("move"):
		var best = null
		var best_d := -1
		for a in by["move"]:
			var d := _nearest_enemy_dist_from(snap, ppos + a["dir"])
			if d > best_d:
				best_d = d
				best = a
		if best != null:
			return best

	# loves the laser
	if by.has("ability"):
		for a in by["ability"]:
			if _kit_id(snap, a["slot"]) == "solar_lance" and _lance_hits(snap, a["target"]):
				return a

	# noob inefficiency: sometimes just stops with charge left over
	if rng.randf() < 0.1:
		return legal[legal.size() - 1]

	# wanders roughly toward the stairs, blind to hazards; sometimes just drifts
	if by.has("move"):
		if rng.randf() < 0.15:
			return by["move"][rng.randi_range(0, by["move"].size() - 1)]
		var step := _bfs_step_blind(snap)
		if step != Vector2i.ZERO:
			for a in by["move"]:
				if a["dir"] == step:
					return a
		return by["move"][rng.randi_range(0, by["move"].size() - 1)]

	return legal[legal.size() - 1]


func _draft_choice(snap: Dictionary, legal: Array) -> Dictionary:
	# noobs pick what looks flashy, and sometimes at random
	if rng.randf() < 0.25:
		return legal[rng.randi_range(0, legal.size() - 1)]
	var pref := [
		"sun_flare", "solar_lance", "grow_spike", "vine_whip", "water_jet",
		"thorn_shield", "pollen_burst", "sap_snare", "seed_bomb", "root_wall",
		"overgrowth",
	]
	var offers: Array = snap["draft_offers"]
	var best_pick := -1
	var best_rank := 999
	for i in offers.size():
		var r: int = pref.find(String(offers[i]).trim_suffix("+"))
		if r == -1:
			r = 500
		r = r * 2 - (1 if String(offers[i]).ends_with("+") else 0)
		if r < best_rank:
			best_rank = r
			best_pick = i
	var candidates: Array = []
	for a in legal:
		if int(a.get("pick", -2)) == best_pick:
			candidates.append(a)
	if candidates.is_empty():
		return legal[legal.size() - 1]
	return candidates[rng.randi_range(0, candidates.size() - 1)]


func _enemy_adjacent(snap: Dictionary) -> bool:
	return _nearest_enemy_dist(snap) == 1


func _nearest_enemy_dist(snap: Dictionary) -> int:
	return _nearest_enemy_dist_from(snap, snap["player"]["pos"])


func _nearest_enemy_dist_from(snap: Dictionary, pos: Vector2i) -> int:
	var best := 999
	for e in snap["enemies"]:
		var d: int = absi(e["pos"].x - pos.x) + absi(e["pos"].y - pos.y)
		if d < best:
			best = d
	return best


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
		for e in snap["enemies"]:
			if e["pos"] == p:
				return true
	return false


func _bfs_step_blind(snap: Dictionary) -> Vector2i:
	# Pathing that ignores terrain hazards and telegraphs entirely.
	var m: Dictionary = snap["map"]
	var w: int = m["w"]
	var h: int = m["h"]
	var start: Vector2i = snap["player"]["pos"]
	var goal: Vector2i = m["stairs"]
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
		if cur == goal:
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
			prev[nxt] = cur
			queue.append(nxt)
	return Vector2i.ZERO
