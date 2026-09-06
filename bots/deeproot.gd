extends "res://bots/optimizer.gd"
## Deeproot persona: calculating minmaxer. Uses the sim itself as a forward
## model (Game.clone()): every candidate action is applied to a cloned game
## and the resulting state scored - including simulating the full enemy
## response to ending the turn. The measurable skill ceiling.

const Content := preload("res://sim/content.gd")
const MAX_CANDIDATES := 30
## Rollout drafting horizon: turns (via total_turns) each draft fork is
## played forward with the optimizer heuristic before scoring.
const ROLLOUT_TURNS := 60
## Safety cap on actions per rollout (run_loop's 10 actions/turn ratio).
const ROLLOUT_ACTIONS := ROLLOUT_TURNS * 10

## "list": the static preference list (optimizer._draft_choice) - the legacy
## ceiling column. "rollout": fork the sim per distinct pick, roll each fork
## out with the heuristic and take the best scored state (roster persona
## deeproot_rollout sets this through Roster props).
var draft_mode := "list"

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
		if draft_mode == "rollout" and _sim != null:
			return _draft_rollout(snap, legal)
		return _draft_choice(snap, legal)
	if _sim == null:
		return super.choose_action(snap, legal)
	_refresh_field(snap)
	var candidates := _candidates(legal, snap)
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


## Rollout drafting (review 7.4): for every distinct pick (one action per
## offer - for a full kit the drop slot the list policy itself would choose
## for that offer - plus skip) clone the sim, step the pick, play the clone
## forward with the optimizer heuristic (super.choose_action; no rng) until
## the next draft phase, game over or ROLLOUT_TURNS turns, and score the
## resulting state with _score(). Argmax wins; a tie at the top goes to the
## static list preference when it is among the tied forks, else to the
## earliest fork in offer order. Deterministic: clone-based, no rng.
## Values an offer by what the heuristic policy does with it over one floor.
func _draft_rollout(snap: Dictionary, legal: Array) -> Dictionary:
	var fallback := _draft_choice(snap, legal)
	var forks := _draft_forks(snap, legal)
	var best: Dictionary = fallback
	var best_s := -1e18
	var best_is_fallback := false
	for a in forks:
		var g = _sim.clone()
		g.step(a)
		var start_turns: int = g.total_turns
		var steps := 0
		while not g.over and g.phase == "play" and g.total_turns - start_turns < ROLLOUT_TURNS and steps < ROLLOUT_ACTIONS:
			g.step(super.choose_action(g.snapshot(), g.legal_actions()))
			steps += 1
		# the field cache is rebuilt for the fork's floor/goal; invalidated below
		_refresh_field(g.snapshot())
		var s := _score(g)
		var is_fb: bool = a == fallback
		if s > best_s or (s == best_s and is_fb and not best_is_fallback):
			best_s = s
			best = a
			best_is_fallback = is_fb
	# forks left the cache pointing at a rollout's floor/goal; force the next
	# real choose_action to rebuild it for the real game
	_field = {}
	_field_floor = -1
	_field_goal = Vector2i(-99, -99)
	return best


## Distinct draft forks in offer order, skip last: one action per offer.
## When the kit is full the offer has one legal action per drop slot; the
## drop is the one the list policy (optimizer._draft_choice) picks when that
## offer is the only one on the table - obtained by asking it with a reduced
## snapshot/legal pair, so the drop rule lives in one place.
func _draft_forks(snap: Dictionary, legal: Array) -> Array:
	var out: Array = []
	var offers: Array = snap["draft_offers"]
	for i in offers.size():
		var group: Array = []
		for a in legal:
			if int(a.get("pick", -2)) == i:
				group.append(a)
		if group.is_empty():
			continue
		if group.size() == 1:
			out.append(group[0])
			continue
		var sub_snap := snap.duplicate()
		sub_snap["draft_offers"] = [offers[i]]
		var sub_legal: Array = []
		for a in group:
			var b: Dictionary = a.duplicate()
			b["pick"] = 0
			sub_legal.append(b)
		sub_legal.append({"type": "draft", "pick": -1})
		var chosen := _draft_choice(sub_snap, sub_legal)
		var fork: Dictionary = group[0]
		if int(chosen.get("pick", -1)) == 0:
			for a in group:
				if int(a.get("drop", -1)) == int(chosen.get("drop", -1)):
					fork = a
					break
		out.append(fork)
	for a in legal:
		if int(a.get("pick", -2)) == -1:
			out.append(a)
			break
	return out


## Candidate set for the 1-ply search. Non-ability actions are always in;
## ability targets fill the rest round-robin across kit slots so a wide
## targeter (overgrowth: ~20 tiles) cannot crowd a narrow one (grow_spike)
## out of MAX_CANDIDATES entirely. Within a slot, targets closest to an
## enemy come first; ties keep legal_actions order (stable by construction:
## the sort key is (distance, original index)).
func _candidates(legal: Array, snap: Dictionary) -> Array:
	var out: Array = []
	var groups := {}  # slot -> Array of [dist, idx, action]
	var slots: Array = []
	var ppos: Vector2i = snap["player"]["pos"]
	for i in legal.size():
		var a: Dictionary = legal[i]
		if a["type"] != "ability":
			out.append(a)
			continue
		var slot: int = a["slot"]
		if not groups.has(slot):
			groups[slot] = []
			slots.append(slot)
		groups[slot].append([_target_enemy_dist(snap, ppos, String(snap["player"]["kit"][slot]), a["target"]), i, a])
	slots.sort()
	for slot in slots:
		groups[slot].sort_custom(func(x, y): return x[0] < y[0] if x[0] != y[0] else x[1] < y[1])
	var cursor := {}
	for slot in slots:
		cursor[slot] = 0
	var remaining := true
	while remaining and out.size() < MAX_CANDIDATES:
		remaining = false
		for slot in slots:
			var c: int = cursor[slot]
			if c >= groups[slot].size():
				continue
			out.append(groups[slot][c][2])
			cursor[slot] = c + 1
			remaining = remaining or cursor[slot] < groups[slot].size()
			if out.size() >= MAX_CANDIDATES:
				break
	return out


## Manhattan distance from where an ability action lands to the nearest
## enemy. "dir" targets land at player + dir; "self" targets count as 0;
## every other kind carries a tile position. No enemies: 0 (legal order).
func _target_enemy_dist(snap: Dictionary, ppos: Vector2i, aid: String, target) -> int:
	var adef: Dictionary = Content.ABILITIES.get(aid, Content.ABILITIES.get(aid.trim_suffix("+"), {}))
	var kind := String(adef.get("target", "tile"))
	if kind == "self":
		return 0
	var tile: Vector2i = ppos + target if kind == "dir" else target
	var best := 999999
	for e in snap["enemies"]:
		var d: int = absi(e["pos"].x - tile.x) + absi(e["pos"].y - tile.y)
		if d < best:
			best = d
	return best if best != 999999 else 0


func _refresh_field(snap: Dictionary) -> void:
	var m: Dictionary = snap["map"]
	var goal: Vector2i = m["stairs"]
	# dormant stairs: while the green quota is unmet, the gradient points at
	# the nearest corruption instead
	if int(snap.get("green_need", 0)) > int(snap.get("greened", 0)):
		var pp0: Vector2i = snap["player"]["pos"]
		var bd0 := 99999
		for t in snap["terrain"].keys():
			var k0 := String(snap["terrain"][t]["kind"])
			if not Content.is_corruption(k0):
				continue
			var d0: int = absi(t.x - pp0.x) + absi(t.y - pp0.y)
			if d0 < bd0:
				bd0 = d0
				goal = t
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
	# a stocked satchel is stored tempo/safety; slightly below the raw value
	# of its effects so the search still spends items when they matter
	s += pl["items"].size() * 30.0
	# unmet green quota is distance-to-descent in disguise
	s -= maxf(0.0, float(g.green_need - g.greened)) * 80.0
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
