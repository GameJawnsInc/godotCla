extends RefCounted
## Pure simulation core for TENDER. No scenes, no signals, no rendering.
## Drive with step(action), inspect with snapshot(), enumerate with legal_actions().
##
## Actions:
##   {"type": "move", "dir": Vector2i}
##   {"type": "strike", "dir": Vector2i}
##   {"type": "cleanse", "target": Vector2i}
##   {"type": "ability", "slot": int, "target": Vector2i}  (dir-targeted abilities pass a unit Vector2i)
##   {"type": "descend"}
##   {"type": "end_turn"}

const Content := preload("res://sim/content.gd")
const MapGen := preload("res://sim/mapgen.gd")

const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var rng := RandomNumberGenerator.new()
var seed_value := 0
var floor_num := 1
var turn := 0
var total_turns := 0
var smog := 0
var dim := 0
var bloom := 0
var over := false
var won := false
var death_cause := ""

var player := {}
var enemies: Array = []
var map := {}
var terrain := {}
var recent_events: Array = []

var _next_id := 1
var _step_events: Array = []


func _init(seed_v: int) -> void:
	seed_value = seed_v
	rng.seed = seed_v
	player = {
		"pos": Vector2i.ZERO, "hp": Content.PLAYER_HP, "max_hp": Content.PLAYER_HP,
		"charge": 0, "bank": 0, "kit": Content.STARTING_KIT.duplicate(),
	}
	_enter_floor(1)
	_begin_player_turn()


# --- public API ---------------------------------------------------------------

func step(action: Dictionary) -> Array:
	_step_events = []
	if over:
		_emit({"t": "error", "msg": "game is over"})
		return _step_events
	match String(action.get("type", "")):
		"move":
			_act_move(action)
		"strike":
			_act_strike(action)
		"cleanse":
			_act_cleanse(action)
		"ability":
			_act_ability(action)
		"descend":
			_act_descend()
		"end_turn":
			_resolve_turn()
		_:
			_emit({"t": "error", "msg": "unknown action"})
	return _step_events


func legal_actions() -> Array:
	var acts: Array = []
	if over:
		return acts
	if player["charge"] >= Content.MOVE_COST:
		for d in DIRS:
			if _open(player["pos"] + d):
				acts.append({"type": "move", "dir": d})
	if player["charge"] >= Content.STRIKE_COST:
		for d in DIRS:
			if _enemy_at(player["pos"] + d) != null:
				acts.append({"type": "strike", "dir": d})
	if player["charge"] >= Content.CLEANSE_COST:
		for d in DIRS:
			var k := _terrain_kind(player["pos"] + d)
			if k == "oil" or k == "goo":
				acts.append({"type": "cleanse", "target": player["pos"] + d})
	for slot in player["kit"].size():
		var aid: String = player["kit"][slot]
		if player["charge"] >= int(Content.ABILITIES[aid]["cost"]):
			for tgt in _ability_targets(aid):
				acts.append({"type": "ability", "slot": slot, "target": tgt})
	if player["pos"] == map["stairs"]:
		acts.append({"type": "descend"})
	acts.append({"type": "end_turn"})
	return acts


func snapshot() -> Dictionary:
	var ens: Array = []
	for e in enemies:
		var edef: Dictionary = Content.ENEMIES[e["kind"]]
		ens.append({
			"id": e["id"], "kind": e["kind"], "hp": e["hp"], "pos": e["pos"],
			"intent": e["intent"].duplicate(true),
			"traits": edef["traits"].duplicate(),
			"will_split": edef["traits"].has("splits") and not e["split_used"],
		})
	var terr := {}
	for t in terrain.keys():
		terr[t] = terrain[t].duplicate()
	return {
		"floor": floor_num, "floor_name": Content.FLOORS[floor_num - 1]["name"],
		"turn": turn, "total_turns": total_turns,
		"smog": smog, "dim": dim, "bloom": bloom,
		"over": over, "won": won, "death_cause": death_cause,
		"player": {
			"pos": player["pos"], "hp": player["hp"], "max_hp": player["max_hp"],
			"charge": player["charge"], "bank": player["bank"], "kit": player["kit"].duplicate(),
		},
		"enemies": ens,
		"map": {
			"w": map["w"], "h": map["h"], "tiles": map["tiles"].duplicate(),
			"start": map["start"], "stairs": map["stairs"], "vents": map["vents"].duplicate(),
		},
		"terrain": terr,
		"events": recent_events.duplicate(true),
	}


func state_hash() -> String:
	return str(snapshot()).sha256_text()


# --- floor / turn flow --------------------------------------------------------

func _enter_floor(n: int) -> void:
	floor_num = n
	turn = 0
	smog = 0
	dim = 0
	var fdef: Dictionary = Content.FLOORS[n - 1]
	var gen := MapGen.generate(rng, fdef)
	map = gen
	terrain = gen["terrain"]
	player["pos"] = gen["start"]
	enemies.clear()
	for spec in gen["enemies"]:
		_spawn(spec["kind"], spec["pos"])
	_emit({"t": "floor", "floor": n, "name": fdef["name"]})
	_compute_intents()


func _begin_player_turn() -> void:
	var regen: int = maxi(1, Content.BASE_REGEN - dim)
	player["charge"] = player["bank"] + regen
	player["bank"] = 0


func _resolve_turn() -> void:
	player["bank"] = mini(player["charge"], Content.BANK_CAP)
	player["charge"] = 0
	for e in enemies.duplicate():
		if over:
			break
		if not enemies.has(e):
			continue
		_execute_intent(e)
	if over:
		return
	_environment_phase()
	if over:
		return
	turn += 1
	total_turns += 1
	_tick_smog()
	_compute_intents()
	_begin_player_turn()


func _compute_intents() -> void:
	for e in enemies:
		var edef: Dictionary = Content.ENEMIES[e["kind"]]
		if bool(edef["slow"]) and turn % 2 == 1:
			e["intent"] = {"type": "idle"}
			continue
		if edef["traits"].has("drains"):
			if _manhattan(e["pos"], player["pos"]) <= int(edef["drain_range"]):
				e["intent"] = {"type": "drain", "amount": edef["drain"]}
			else:
				e["intent"] = {"type": "move"}
		elif _manhattan(e["pos"], player["pos"]) == 1:
			e["intent"] = {"type": "attack", "tile": player["pos"], "dmg": edef["dmg"]}
		else:
			e["intent"] = {"type": "move"}


func _execute_intent(e: Dictionary) -> void:
	var it: Dictionary = e["intent"]
	match String(it.get("type", "idle")):
		"attack":
			if player["pos"] == it["tile"]:
				_damage_player(int(it["dmg"]), e["kind"])
		"drain":
			if _manhattan(e["pos"], player["pos"]) <= int(Content.ENEMIES[e["kind"]]["drain_range"]):
				var drained: int = mini(player["bank"], int(it["amount"]))
				player["bank"] -= drained
				_emit({"t": "drain", "id": e["id"], "amt": drained})
		"move":
			var dest := _chase_step(e)
			if dest != e["pos"]:
				if Content.ENEMIES[e["kind"]]["traits"].has("oil_trail"):
					var old: Vector2i = e["pos"]
					if not terrain.has(old) and old != map["stairs"]:
						terrain[old] = {"kind": "oil"}
				e["pos"] = dest
				_enemy_enter_tile(e)
		"idle":
			pass


func _environment_phase() -> void:
	var fires: Array = []
	for t in terrain.keys():
		if terrain[t]["kind"] == "fire":
			fires.append(t)
	for t in fires:
		if player["pos"] == t:
			_damage_player(1, "fire")
			if over:
				return
		var e = _enemy_at(t)
		if e != null:
			_damage_enemy(e, 1, "fire")
	var spreads: Array = []
	for t in fires:
		for d in DIRS:
			var p: Vector2i = t + d
			if _terrain_kind(p) == "oil" and not spreads.has(p):
				spreads.append(p)
	for t in fires:
		if terrain.has(t):
			terrain[t]["ttl"] -= 1
			if terrain[t]["ttl"] <= 0:
				terrain.erase(t)
	for p in spreads:
		terrain[p] = {"kind": "fire", "ttl": 2}
		_emit({"t": "ignite", "tile": p})
	if _terrain_kind(player["pos"]) == "growth" and player["hp"] < player["max_hp"]:
		player["hp"] += 1
		_emit({"t": "heal", "amt": 1})


func _tick_smog() -> void:
	smog += 1
	var fdef: Dictionary = Content.FLOORS[floor_num - 1]
	if fdef["smog_dim"].has(smog) and dim < 2:
		dim += 1
		_emit({"t": "smog_dim", "dim": dim})
	var spawn: bool = fdef["smog_spawn"].has(smog)
	if not spawn:
		var last: int = fdef["smog_spawn"].back()
		var every: int = fdef.get("smog_spawn_every", 0)
		spawn = every > 0 and smog > last and (smog - last) % every == 0
	if spawn:
		for v in map["vents"]:
			if _open(v):
				var e := _spawn("drill_bot", v)
				e["intent"] = {"type": "idle"}
				_emit({"t": "reinforcement", "tile": v})
				break


# --- player actions -----------------------------------------------------------

func _act_move(action: Dictionary) -> void:
	var dir: Vector2i = action.get("dir", Vector2i.ZERO)
	var dest: Vector2i = player["pos"] + dir
	if not DIRS.has(dir) or player["charge"] < Content.MOVE_COST or not _open(dest):
		_emit({"t": "illegal", "action": "move"})
		return
	player["charge"] -= Content.MOVE_COST
	player["pos"] = dest
	_emit({"t": "move", "who": "player", "to": dest})
	var k := _terrain_kind(dest)
	if k == "fire":
		_damage_player(1, "fire")
	elif k == "goo":
		_damage_player(1, "goo")


func _act_strike(action: Dictionary) -> void:
	var dir: Vector2i = action.get("dir", Vector2i.ZERO)
	var e = _enemy_at(player["pos"] + dir)
	if e == null or player["charge"] < Content.STRIKE_COST:
		_emit({"t": "illegal", "action": "strike"})
		return
	player["charge"] -= Content.STRIKE_COST
	_emit({"t": "strike", "id": e["id"]})
	_damage_enemy(e, Content.STRIKE_DMG, "strike")


func _act_cleanse(action: Dictionary) -> void:
	var target: Vector2i = action.get("target", Vector2i(-1, -1))
	var k := _terrain_kind(target)
	var legal := _manhattan(target, player["pos"]) == 1 and (k == "oil" or k == "goo")
	if not legal or player["charge"] < Content.CLEANSE_COST:
		_emit({"t": "illegal", "action": "cleanse"})
		return
	player["charge"] -= Content.CLEANSE_COST
	terrain.erase(target)
	bloom += 1
	_emit({"t": "cleanse", "tile": target, "bloom": bloom})


func _act_descend() -> void:
	if player["pos"] != map["stairs"]:
		_emit({"t": "illegal", "action": "descend"})
		return
	if floor_num >= Content.FLOORS.size():
		won = true
		over = true
		_emit({"t": "win"})
		return
	player["bank"] = mini(player["charge"], Content.BANK_CAP)
	_emit({"t": "descend", "to_floor": floor_num + 1})
	_enter_floor(floor_num + 1)
	_begin_player_turn()


func _act_ability(action: Dictionary) -> void:
	var slot: int = action.get("slot", -1)
	if slot < 0 or slot >= player["kit"].size():
		_emit({"t": "illegal", "action": "ability"})
		return
	var aid: String = player["kit"][slot]
	var adef: Dictionary = Content.ABILITIES[aid]
	var target = action.get("target")
	if player["charge"] < int(adef["cost"]) or not _ability_targets(aid).has(target):
		_emit({"t": "illegal", "action": "ability", "id": aid})
		return
	player["charge"] -= int(adef["cost"])
	_emit({"t": "ability", "id": aid, "target": target})
	for eff in adef["effects"]:
		_apply_effect(eff, adef, target)


func _ability_targets(aid: String) -> Array:
	var adef: Dictionary = Content.ABILITIES[aid]
	var rng_: int = adef["range"]
	var out: Array = []
	match String(adef["target"]):
		"dir":
			out = DIRS.duplicate()
		"tile":
			for dy in range(-rng_, rng_ + 1):
				for dx in range(-rng_, rng_ + 1):
					if absi(dx) + absi(dy) > rng_ or (dx == 0 and dy == 0):
						continue
					var p: Vector2i = player["pos"] + Vector2i(dx, dy)
					if _tile(p) == MapGen.T_FLOOR and not terrain.has(p):
						out.append(p)
			if not terrain.has(player["pos"]):
				out.append(player["pos"])
		"enemy_line":
			for e in enemies:
				var delta: Vector2i = e["pos"] - player["pos"]
				if delta.x != 0 and delta.y != 0:
					continue
				var d := _manhattan(player["pos"], e["pos"])
				if d == 0 or d > rng_:
					continue
				if _line_clear(player["pos"], e["pos"]):
					out.append(e["pos"])
		"growth":
			for t in terrain.keys():
				if terrain[t]["kind"] == "growth" and _manhattan(t, player["pos"]) <= rng_ and _open(t):
					out.append(t)
	return out


func _apply_effect(eff: Dictionary, adef: Dictionary, target) -> void:
	match String(eff["op"]):
		"lance":
			var dmg: int = eff["dmg"] + (int(eff["clear_smog_bonus"]) if dim == 0 else 0)
			var p: Vector2i = player["pos"]
			for i in range(int(adef["range"])):
				p += target
				if _tile(p) == MapGen.T_WALL or _terrain_kind(p) == "smoke":
					break
				if _terrain_kind(p) == "oil" and bool(eff["ignite"]):
					terrain[p] = {"kind": "fire", "ttl": 2}
					_emit({"t": "ignite", "tile": p})
				var e = _enemy_at(p)
				if e != null:
					_damage_enemy(e, dmg, "solar_lance")
					break
		"grow_radius":
			var tiles_: Array = [target]
			for d in DIRS:
				tiles_.append(target + d)
			for t in tiles_:
				if _tile(t) == MapGen.T_FLOOR and not terrain.has(t):
					terrain[t] = {"kind": "growth"}
			_emit({"t": "growth", "tile": target})
		"pull":
			var e = _enemy_at(target)
			if e == null:
				return
			var delta: Vector2i = player["pos"] - e["pos"]
			var dir := Vector2i(signi(delta.x), signi(delta.y))
			for i in range(int(eff["dist"])):
				var nxt: Vector2i = e["pos"] + dir
				if _manhattan(e["pos"], player["pos"]) <= 1 or not _open(nxt):
					break
				e["pos"] = nxt
				_enemy_enter_tile(e)
				if not enemies.has(e):
					return
			_damage_enemy(e, int(eff["dmg"]), "vine_whip")
		"wash_push":
			var line: Array = []
			var p: Vector2i = player["pos"]
			for i in range(int(adef["range"])):
				p += target
				if _tile(p) == MapGen.T_WALL:
					break
				line.append(p)
			var pushed = null
			for t in line:
				var k := _terrain_kind(t)
				if k == "oil" or k == "fire":
					terrain.erase(t)
					_emit({"t": "wash", "tile": t})
				if pushed == null:
					var e = _enemy_at(t)
					if e != null:
						pushed = e
			if pushed != null:
				for i in range(int(eff["push"])):
					var nxt: Vector2i = pushed["pos"] + target
					if not _open(nxt):
						_damage_enemy(pushed, int(eff["collision_dmg"]), "collision")
						break
					pushed["pos"] = nxt
					_enemy_enter_tile(pushed)
					if not enemies.has(pushed):
						break
		"teleport":
			player["pos"] = target
			_emit({"t": "teleport", "to": target})


# --- entities and damage ------------------------------------------------------

func _spawn(kind: String, pos: Vector2i) -> Dictionary:
	var edef: Dictionary = Content.ENEMIES[kind]
	var e := {"id": _next_id, "kind": kind, "hp": edef["hp"], "pos": pos, "intent": {"type": "idle"}, "split_used": false}
	_next_id += 1
	enemies.append(e)
	return e


func _damage_enemy(e: Dictionary, amt: int, src: String) -> void:
	if not enemies.has(e):
		return
	e["hp"] -= amt
	_emit({"t": "damage", "who": e["kind"], "id": e["id"], "amt": amt, "src": src})
	if e["hp"] <= 0:
		enemies.erase(e)
		_emit({"t": "death", "who": e["kind"], "id": e["id"]})
	elif Content.ENEMIES[e["kind"]]["traits"].has("splits") and not e["split_used"]:
		e["split_used"] = true
		for d in DIRS:
			var p: Vector2i = e["pos"] + d
			if _open(p):
				var s := _spawn("sludgeling", p)
				_emit({"t": "split", "id": e["id"], "child": s["id"]})
				break


func _damage_player(amt: int, src: String) -> void:
	player["hp"] -= amt
	_emit({"t": "damage", "who": "player", "amt": amt, "src": src})
	if player["hp"] <= 0:
		over = true
		death_cause = src
		_emit({"t": "player_death", "cause": src})


func _enemy_enter_tile(e: Dictionary) -> void:
	if _terrain_kind(e["pos"]) == "fire":
		_damage_enemy(e, 1, "fire")


func _chase_step(e: Dictionary) -> Vector2i:
	# BFS toward a tile adjacent to the player; occupied tiles are impassable.
	var start: Vector2i = e["pos"]
	var goal: Vector2i = player["pos"]
	var prev := {}
	prev[start] = start
	var queue: Array = [start]
	var qi := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		if _manhattan(cur, goal) == 1:
			var node := cur
			while prev[node] != start:
				node = prev[node]
			return node
		for d in DIRS:
			var nxt: Vector2i = cur + d
			if prev.has(nxt) or not _open(nxt):
				continue
			prev[nxt] = cur
			queue.append(nxt)
	return start


# --- helpers ------------------------------------------------------------------

func _tile(p: Vector2i) -> int:
	if p.x < 0 or p.y < 0 or p.x >= int(map["w"]) or p.y >= int(map["h"]):
		return MapGen.T_WALL
	return map["tiles"][p.y * int(map["w"]) + p.x]


func _terrain_kind(p: Vector2i) -> String:
	if terrain.has(p):
		return terrain[p]["kind"]
	return ""


func _enemy_at(p: Vector2i):
	for e in enemies:
		if e["pos"] == p:
			return e
	return null


func _open(p: Vector2i) -> bool:
	return _tile(p) == MapGen.T_FLOOR and _enemy_at(p) == null and p != player["pos"]


func _line_clear(a: Vector2i, b: Vector2i) -> bool:
	var delta: Vector2i = b - a
	var dir := Vector2i(signi(delta.x), signi(delta.y))
	var p := a + dir
	while p != b:
		if _tile(p) == MapGen.T_WALL or _enemy_at(p) != null or _terrain_kind(p) == "smoke":
			return false
		p += dir
	return true


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _emit(ev: Dictionary) -> void:
	_step_events.append(ev)
	recent_events.append(ev)
	while recent_events.size() > 8:
		recent_events.pop_front()
