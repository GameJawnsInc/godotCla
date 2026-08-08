extends "res://bots/bot_base.gd"
## Optimizer persona: deterministic heuristic play aimed at winning.
## Priorities: descend > strike > lance > dodge telegraphed damage > cleanse
## when safe > path to stairs > pull a blocker into reach > end turn.

const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


func get_bot_name() -> String:
	return "optimizer"


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

	if by.has("buy"):
		for item in ["graft", "heal", "ability"]:
			for a in by["buy"]:
				if a["item"] == item:
					return a

	if by.has("descend"):
		return by["descend"][0]

	var threat := _threat_tiles(snap)

	var boss = null
	for e in snap["enemies"]:
		if e["traits"].has("boss"):
			boss = e
	if boss != null and boss["hp"] <= 6 and not _growth_adj_to(snap, boss["pos"]) and by.has("cleanse"):
		for a in by["cleanse"]:
			var t: Vector2i = a["target"]
			if absi(t.x - boss["pos"].x) + absi(t.y - boss["pos"].y) == 1:
				return a
	if boss != null and boss["hp"] <= 6 and not _growth_adj_to(snap, boss["pos"]) and by.has("ability"):
		var best_bomb = null
		var best_d := 999
		for a in by["ability"]:
			if _kit_id(snap, a["slot"]) == "seed_bomb":
				var d: int = absi(a["target"].x - boss["pos"].x) + absi(a["target"].y - boss["pos"].y)
				if d <= 2 and d < best_d:
					best_d = d
					best_bomb = a
		if best_bomb != null:
			return best_bomb

	# 3 damage for 1 charge beats everything else on the menu
	if by.has("ability"):
		for a in by["ability"]:
			if _kit_id(snap, a["slot"]) == "grow_spike":
				return a

	# Survival gate: standing in telegraphed damage without the HP to trade.
	# A strike only helps here if it kills the attacker before the hit lands;
	# otherwise step out first and fight from a safe tile.
	if threat.has(ppos) and snap["player"]["hp"] + snap["player"]["shield"] <= _incoming_dmg(snap) * 2:
		if by.has("strike"):
			for a in by["strike"]:
				var e = _enemy_at(snap, ppos + a["dir"])
				if e != null and e["hp"] <= 1:
					return a
		var out := _dodge(snap, by, threat)
		if not out.is_empty():
			return out

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
		var near := _enemies_within(snap, 2)
		for a in by["ability"]:
			var aid: String = _kit_id(snap, a["slot"])
			if aid == "sun_flare" and near >= 2:
				return a
			if aid == "pollen_burst" and _enemies_within(snap, 1) >= 2:
				return a
			if aid == "geyser" and _enemies_within(snap, 1) >= 2:
				return a
			if aid == "spore_cloud" and near >= 2:
				return a
		for a in by["ability"]:
			if _kit_id(snap, a["slot"]) == "solar_lance" and _lance_hits(snap, a["target"]):
				return a
		if snap["player"]["shield"] == 0 and near >= 1 and snap["player"]["charge"] >= 2:
			for a in by["ability"]:
				if _kit_id(snap, a["slot"]) == "thorn_shield":
					return a

	if threat.has(ppos):
		var out := _dodge(snap, by, threat)
		if not out.is_empty():
			return out

	# rest up on growth when the coast is clear - but not once the skies are
	# nearly dark; late-floor turns are worth more than hit points then
	if snap["player"]["hp"] <= snap["player"]["max_hp"] - 3 and _nearest_enemy_dist(snap) > 4 and int(snap["dim"]) <= 1:
		var on_growth: bool = snap["terrain"].get(ppos, {}).get("kind", "") == "growth"
		if on_growth:
			return legal[legal.size() - 1]
		if by.has("move"):
			for a in by["move"]:
				if snap["terrain"].get(ppos + a["dir"], {}).get("kind", "") == "growth":
					return a
		if by.has("ability"):
			for a in by["ability"]:
				if _kit_id(snap, a["slot"]) == "seed_bomb" and a["target"] == ppos:
					return a

	# greedy cleansing only while the skies are still clear - the bloom is not
	# worth the turns once the smog clock starts dimming regen
	if by.has("cleanse") and _nearest_enemy_dist(snap) > 3 and int(snap["dim"]) == 0:
		return by["cleanse"][0]

	if by.has("move"):
		var step := _path_step(snap, threat)
		if step != Vector2i.ZERO:
			for a in by["move"]:
				if a["dir"] == step:
					return a

	if by.has("ability"):
		for a in by["ability"]:
			if _kit_id(snap, a["slot"]) == "vine_whip":
				return a

	return legal[legal.size() - 1]


func _draft_choice(snap: Dictionary, legal: Array) -> Dictionary:
	var pref := [
		"sun_flare", "grow_spike", "geyser", "thorn_shield", "water_jet",
		"tide", "sap_snare", "spore_cloud", "gust", "vine_whip",
		"pollen_burst", "solar_lance", "seed_bomb", "updraft", "overgrowth",
		"burrow", "fungal_ring", "clear_air", "steam_vent", "root_wall",
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
	if candidates.size() == 1:
		return candidates[0]
	# kit is full: drop the least-used ability. Never drop mobility, and never
	# drop the growth engine - the Furnace core is only vulnerable near growth.
	var uses: Dictionary = snap["player"]["uses"]
	var kit: Array = snap["player"]["kit"]
	var best_a: Dictionary = candidates[0]
	var best_u := 999999
	for a in candidates:
		var slot: int = a["drop"]
		if String(kit[slot]).trim_suffix("+") == "mycelium_dash" or String(kit[slot]).trim_suffix("+") == "seed_bomb":
			continue
		var u: int = uses.get(kit[slot], 0)
		if u < best_u:
			best_u = u
			best_a = a
	return best_a


## Step out of telegraphed damage; when cornered, shove an adjacent attacker
## away, dash out, or root the attacker in place. Empty dict if nothing works.
func _dodge(snap: Dictionary, by: Dictionary, threat: Dictionary) -> Dictionary:
	var ppos: Vector2i = snap["player"]["pos"]
	if by.has("move"):
		# among safe tiles, retreat toward the stairs - a dodge that makes no
		# progress oscillates forever while the smog clock runs out
		var stairs: Vector2i = snap["map"]["stairs"]
		var best: Dictionary = {}
		var best_d := 999999
		for a in by["move"]:
			var dest: Vector2i = ppos + a["dir"]
			if not threat.has(dest) and not _hazard(snap, dest):
				var d := _bfs_dist(snap, dest, stairs)
				if d < best_d:
					best_d = d
					best = a
		if not best.is_empty():
			return best
	if by.has("ability"):
		for a in by["ability"]:
			if _kit_id(snap, a["slot"]) == "water_jet" and _enemy_at(snap, ppos + a["target"]) != null:
				return a
		for a in by["ability"]:
			if _kit_id(snap, a["slot"]) == "mycelium_dash" and not threat.has(a["target"]):
				return a
		for a in by["ability"]:
			if _kit_id(snap, a["slot"]) == "sap_snare":
				return a
		for a in by["ability"]:
			if _kit_id(snap, a["slot"]) == "gust" and _enemy_at(snap, ppos + a["target"]) != null:
				return a
	return {}


## Walkable BFS distance between two tiles (enemies block, goal exempt);
## 999999 when unreachable or the goal is off-map.
func _bfs_dist(snap: Dictionary, from: Vector2i, to: Vector2i) -> int:
	if to == Vector2i(-1, -1):
		return 999999
	if from == to:
		return 0
	var m: Dictionary = snap["map"]
	var w: int = m["w"]
	var h: int = m["h"]
	var occupied := {}
	for e in snap["enemies"]:
		occupied[e["pos"]] = true
	var dist := {}
	dist[from] = 0
	var queue: Array = [from]
	var qi := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		for d in DIRS:
			var nxt: Vector2i = cur + d
			if nxt == to:
				return int(dist[cur]) + 1
			if nxt.x < 0 or nxt.y < 0 or nxt.x >= w or nxt.y >= h:
				continue
			if m["tiles"][nxt.y * w + nxt.x] != 1:
				continue
			if dist.has(nxt) or occupied.has(nxt):
				continue
			dist[nxt] = int(dist[cur]) + 1
			queue.append(nxt)
	return 999999


## Total telegraphed damage that will land on the player's current tile.
func _incoming_dmg(snap: Dictionary) -> int:
	var ppos: Vector2i = snap["player"]["pos"]
	var total := 0
	for e in snap["enemies"]:
		var it: Dictionary = e["intent"]
		match String(it.get("type", "")):
			"attack":
				if it["tile"] == ppos:
					total += int(it["dmg"])
			"slam":
				var t: Vector2i = it["tile"]
				if t == ppos or absi(t.x - ppos.x) + absi(t.y - ppos.y) == 1:
					total += int(it["dmg"])
			"quake":
				if absi(e["pos"].x - ppos.x) + absi(e["pos"].y - ppos.y) == 1:
					total += int(it.get("dmg", 2))
	return total


func _enemies_within(snap: Dictionary, radius: int) -> int:
	var ppos: Vector2i = snap["player"]["pos"]
	var n := 0
	for e in snap["enemies"]:
		if absi(e["pos"].x - ppos.x) + absi(e["pos"].y - ppos.y) <= radius:
			n += 1
	return n


func _threat_tiles(snap: Dictionary) -> Dictionary:
	var t := {}
	var ignite_coming := false
	for e in snap["enemies"]:
		var it: String = String(e["intent"].get("type", ""))
		if it == "attack":
			t[e["intent"]["tile"]] = true
		elif it == "slam":
			t[e["intent"]["tile"]] = true
			for d in DIRS:
				t[e["intent"]["tile"] + d] = true
		elif it == "quake":
			for d in DIRS:
				t[e["pos"] + d] = true
		elif it == "ignite_all":
			ignite_coming = true
	for tile in snap["terrain"].keys():
		var k: String = snap["terrain"][tile]["kind"]
		if k == "fire" or (ignite_coming and k == "oil"):
			t[tile] = true
	return t


func _growth_adj_to(snap: Dictionary, pos: Vector2i) -> bool:
	for d in DIRS:
		if snap["terrain"].get(pos + d, {}).get("kind", "") == "growth":
			return true
	return false


func _enemy_at(snap: Dictionary, pos: Vector2i) -> Variant:
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
	return k == "fire" or k == "goo" or k == "rich_goo"


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
	# shop only when the shrine is nearly on the way to the stairs - measured:
	# unconditional detours cost this bot ~9 wins/30 to the smog clock, more
	# than any purchase returns (the Boarded Shrines mutator proved it by
	# accidentally beating the un-mutated baseline)
	var shrine: Vector2i = snap["map"]["shrine"]
	if shrine != Vector2i(-1, -1) and snap["player"]["pos"] != shrine and int(snap["dim"]) == 0:
		var worth: bool = snap["shop"].has("graft") and snap["bloom"] >= 5
		if snap["shop"].get("heal", false) and snap["bloom"] >= 3 and snap["player"]["hp"] <= snap["player"]["max_hp"] - 4:
			worth = true
		if worth:
			var ppos2: Vector2i = snap["player"]["pos"]
			var extra := _bfs_dist(snap, ppos2, shrine) + _bfs_dist(snap, shrine, stairs) - _bfs_dist(snap, ppos2, stairs)
			if extra <= 4:
				var to_shrine := _bfs_step(snap, true, threat, shrine)
				if to_shrine != Vector2i.ZERO:
					return to_shrine
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
				if k == "fire" or k == "goo" or k == "rich_goo" or k == "oil":
					continue
			prev[nxt] = cur
			queue.append(nxt)
	return Vector2i.ZERO
