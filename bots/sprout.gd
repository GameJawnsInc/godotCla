extends "res://bots/bot_base.gd"
## Sprout persona: cautious noob. Greedy for Bloom even when unsafe, panics at
## low HP, hazard-blind movement, wastes charge, and only uses the obvious
## buttons (strike, lance, plus the tutorial's seed bomb / grow spike and the
## two self-explanatory consumables). Measures teaching-curve fairness.

const Content := preload("res://sim/content.gd")

const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## What a noob thinks is good, best first: this ranks the draft offers.
const DRAFT_PREF := [
	"sun_flare", "solar_lance", "grow_spike", "vine_whip", "water_jet",
	"thorn_shield", "pollen_burst", "sap_snare", "seed_bomb", "root_wall",
	"overgrowth",
]


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

	# the two consumables whose use is obvious: eat when hurting, drink when
	# out of juice with something close. Free actions, no rng draw here.
	if by.has("use_item"):
		var pl0: Dictionary = snap["player"]
		for a in by["use_item"]:
			match String(pl0["items"][a["slot"]]).trim_suffix("+"):
				"balm_fruit":
					if int(pl0["hp"]) <= 4:
						return a
				"sun_capsule":
					if int(pl0["charge"]) == 0 and _nearest_enemy_dist(snap) <= 3:
						return a

	# impulse shopping: heal first, then whatever is shiny
	if by.has("buy") and rng.randf() < 0.5:
		var deal := _shop_impulse(by["buy"])
		if not deal.is_empty():
			return deal

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
		# the tutorial's other two buttons, pressed without any threat reading:
		# a spike whenever it lights up; a bomb under its own feet when hurt
		# and nothing is in the face (first legal tile if home is occupied)
		for a in by["ability"]:
			if _kit_id(snap, a["slot"]) == "grow_spike":
				return a
		if int(snap["player"]["hp"]) <= int(snap["player"]["max_hp"]) - 3 and not _enemy_adjacent(snap):
			var first_bomb: Dictionary = {}
			for a in by["ability"]:
				if _kit_id(snap, a["slot"]) == "seed_bomb":
					if a["target"] == ppos:
						return a
					if first_bomb.is_empty():
						first_bomb = a
			if not first_bomb.is_empty():
				return first_bomb

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
	var offers: Array = snap["draft_offers"]
	var best_pick := -1
	# unlisted offers rank after every listed id; the huge sentinel means an
	# offer is always taken over skipping when nothing listed is on the table
	var best_rank := 1 << 30
	for i in offers.size():
		var r: int = _pref_rank(String(offers[i]))
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


## Rank of an ability id in DRAFT_PREF; lower is better. Unlisted ids rank
## after everything listed; the doubled scale leaves room for a "+" form to
## rank one step better than its plain base.
func _pref_rank(aid: String) -> int:
	var r: int = DRAFT_PREF.find(String(aid).trim_suffix("+"))
	if r == -1:
		r = DRAFT_PREF.size()
	return r * 2 - (1 if String(aid).ends_with("+") else 0)


## Impulse purchase: heal, then an ability, then a graft - from the legal
## list only. Empty dict when nothing on the counter gets taken.
func _shop_impulse(buys: Array) -> Dictionary:
	for a in buys:
		if a["item"] == "heal":
			return a
	for a in buys:
		if a["item"] == "ability":
			return a
	# the shrine offers two grafts and one pick closes the counter: take
	# offer 0. No bot ranks grafts yet - the progression review holds any
	# graft weighting until tests/sweep_grafts.gd has run at 30+ seeds.
	var graft: Dictionary = {}
	for a in buys:
		if a["item"] != "graft":
			continue
		if graft.is_empty() or int(a.get("pick", 0)) < int(graft.get("pick", 0)):
			graft = a
	return graft


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
		if bool(Content.terrain(snap["terrain"].get(p, {}).get("kind", ""), "blocks_beam", false)):
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
	# even a noob reads "the stairs are dormant": head for corruption instead
	if int(snap.get("green_need", 0)) > int(snap.get("greened", 0)):
		var bd := 99999
		for t in snap["terrain"].keys():
			var k := String(snap["terrain"][t]["kind"])
			if Content.is_corruption(k):
				var d: int = absi(t.x - start.x) + absi(t.y - start.y)
				if d < bd:
					bd = d
					goal = t
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
