extends "res://bots/optimizer.gd"
## Deeproot persona: calculating minmaxer. Uses the sim itself as a forward
## model (Game.clone()): every candidate action is applied to a cloned game
## and the resulting state scored - including simulating the full enemy
## response to ending the turn. The measurable skill ceiling.

const MAX_CANDIDATES := 30

var _sim = null
var _field := {}
var _field_floor := -1
var _field_goal := Vector2i(-99, -99)


func get_bot_name() -> String:
	return "deeproot"


## Harness hook: a live Game reference to clone from. Optional - without it
## Deeproot falls back to plain optimizer play.
func set_sim(game) -> void:
	_sim = game


func choose_action(snap: Dictionary, legal: Array) -> Dictionary:
	if snap["phase"] == "draft":
		return _draft_choice(snap, legal)
	if _sim == null:
		return super.choose_action(snap, legal)
	_refresh_field(snap)
	var candidates := _candidates(legal)
	var best: Dictionary = candidates[0]
	var best_s := -1e18
	for a in candidates:
		var g = _sim.clone()
		g.step(a)
		if not g.over and g.phase == "play" and String(a["type"]) != "end_turn":
			g.step({"type": "end_turn"})
		var s := _score(g)
		if s > best_s:
			best_s = s
			best = a
	return best


func _candidates(legal: Array) -> Array:
	# cheap actions always considered; ability targets fill the remaining slots
	var out: Array = []
	var abilities: Array = []
	for a in legal:
		if a["type"] == "ability":
			abilities.append(a)
		else:
			out.append(a)
	for a in abilities:
		if out.size() >= MAX_CANDIDATES:
			break
		out.append(a)
	return out


func _refresh_field(snap: Dictionary) -> void:
	var m: Dictionary = snap["map"]
	var goal: Vector2i = m["stairs"]
	if goal == Vector2i(-1, -1):
		for e in snap["enemies"]:
			if e["traits"].has("boss"):
				goal = e["pos"]
		if goal == Vector2i(-1, -1):
			goal = snap["enemies"][0]["pos"] if not snap["enemies"].is_empty() else snap["player"]["pos"]
	if int(snap["floor"]) == _field_floor and goal == _field_goal:
		return
	_field_floor = int(snap["floor"])
	_field_goal = goal
	_field = {}
	_field[goal] = 0
	var w: int = m["w"]
	var h: int = m["h"]
	var queue: Array = [goal]
	var qi := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		for d in DIRS:
			var nxt: Vector2i = cur + d
			if nxt.x < 0 or nxt.y < 0 or nxt.x >= w or nxt.y >= h:
				continue
			if m["tiles"][nxt.y * w + nxt.x] != 1 or _field.has(nxt):
				continue
			_field[nxt] = int(_field[cur]) + 1
			queue.append(nxt)


func _score(g) -> float:
	if g.won:
		return 1e12
	if g.over:
		return -1e12
	var s := 0.0
	var pl: Dictionary = g.player
	s += pl["hp"] * 40.0 + pl["shield"] * 12.0
	s += (pl["charge"] + pl["bank"]) * 2.0
	s += g.bloom * 4.0
	s += g.floor_num * 800.0
	if g.phase == "draft":
		s += 800.0  # descent taken, floor counter updates after the pick
	s -= g.dim * 30.0
	var ehp := 0
	for e in g.enemies:
		ehp += int(e["hp"])
	s -= ehp * 10.0
	s -= g.enemies.size() * 8.0
	# BFS distance to the goal, with urgency that grows as the smog rises -
	# lingering safely must eventually lose to making progress
	var urgency: float = 6.0 + maxf(0.0, float(g.smog) - 8.0)
	s -= float(_field.get(pl["pos"], 60)) * urgency
	return s
