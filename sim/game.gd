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
##   {"type": "draft", "pick": int, "drop": int}  (draft phase only; pick -1 skips, drop when kit is full)

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
var phase := "play"
var draft_offers: Array = []
var shop := {}
var tier := 0
var mutators: Array = []
var draft_pool: Array = []
var stoked := 0
var greened := 0  # corruption cleansed this floor
var green_need := 0  # dormant-stairs quota (clamped to generated corruption)  # pending extra smog ticks from live smokestacks
var _fixed_floor := {}  # config "fixed_floor": scripted floor-1 layout (tutorials, tests)

var _next_id := 1
var _step_events: Array = []
var _pending_floor := 0


func _init(seed_v: int, config: Dictionary = {}) -> void:
	seed_value = seed_v
	rng.seed = seed_v
	if config.get("_blank", false):
		return
	tier = int(config.get("tier", 0))
	mutators = config.get("mutators", []).duplicate()
	_fixed_floor = config.get("fixed_floor", {}).duplicate(true)
	draft_pool = config.get("pool", Content.DRAFT_POOL).duplicate()
	for pkg in config.get("packages", []):
		for aid in Content.PACKAGES[pkg]:
			if not draft_pool.has(aid):
				draft_pool.append(aid)
	player = {
		"pos": Vector2i.ZERO, "hp": Content.PLAYER_HP, "max_hp": Content.PLAYER_HP,
		"charge": 0, "bank": 0, "shield": 0,
		"kit": config.get("kit", Content.STARTING_KIT).duplicate(),
		"uses": {}, "grafts": [], "gummed": {}, "items": [],
		"thorns_dmg": 0, "thorns_turns": 0, "anchor_turns": 0,
	}
	if mutators.has("brittle"):
		player["max_hp"] -= 3
		player["hp"] = player["max_hp"]
	_enter_floor(1)
	_begin_player_turn()


func _kit_max() -> int:
	return 3 if mutators.has("kit_of_3") else Content.KIT_MAX


## Floor definition with this run's difficulty-tier modifiers applied.
func floor_def(n: int) -> Dictionary:
	var fdef: Dictionary = Content.FLOORS[n - 1].duplicate(true)
	for i in range(mini(tier, Content.TIERS.size())):
		var mod: Dictionary = Content.TIERS[i]
		if mod.has("choke_delta") and fdef.get("smog_choke", 0) > 0:
			fdef["smog_choke"] = maxi(10, fdef["smog_choke"] + int(mod["choke_delta"]))
		if mod.has("spawn_every_delta") and fdef.get("smog_spawn_every", 0) > 0:
			fdef["smog_spawn_every"] = maxi(4, fdef["smog_spawn_every"] + int(mod["spawn_every_delta"]))
		if mod.has("dim_delta"):
			var dims: Array = []
			for v in fdef["smog_dim"]:
				dims.append(maxi(4, int(v) + int(mod["dim_delta"])))
			fdef["smog_dim"] = dims
		if mod.has("extra_enemy") and not fdef.get("boss", false):
			var kind := String(mod["extra_enemy"])
			fdef["enemies"][kind] = int(fdef["enemies"].get(kind, 0)) + 1
	if mutators.has("double_oil"):
		fdef["oil"] = int(fdef["oil"]) * 2
	if mutators.has("overtime") and not fdef.get("boss", false):
		var common := ""
		var common_n := 0
		for kind in fdef["enemies"]:
			if int(fdef["enemies"][kind]) > common_n:
				common_n = int(fdef["enemies"][kind])
				common = kind
		if common != "":
			fdef["enemies"][common] = common_n + 1
	var extra_elites := _tier_mod("extra_elites")
	if extra_elites > 0 and not fdef.get("boss", false):
		fdef["elites"] = int(fdef.get("elites", 0)) + extra_elites
	if n == 1 and not _fixed_floor.is_empty():
		fdef.merge(_fixed_floor.get("fdef", {}), true)
	return fdef


func _tier_mod(key: String) -> int:
	var v := 0
	for i in range(mini(tier, Content.TIERS.size())):
		v += int(Content.TIERS[i].get(key, 0))
	return v


func shop_cost(item: String) -> int:
	var cost: int = Content.SHOP_COSTS.get(item, 9999)
	if item == "graft":
		# permanent power gets dearer the more of it you already own, so
		# "farm early, buy everything" is a real commitment, not a default
		cost += player["grafts"].size() * Content.GRAFT_PRICE_STEP
	for i in range(mini(tier, Content.TIERS.size())):
		cost += int(Content.TIERS[i].get("shop_markup", 0))
	return cost


# --- public API ---------------------------------------------------------------

func step(action: Dictionary) -> Array:
	_step_events = []
	if over:
		_emit({"t": "error", "msg": "game is over"})
		return _step_events
	if phase == "draft":
		if String(action.get("type", "")) == "draft":
			_act_draft(action)
		else:
			_emit({"t": "illegal", "action": "draft phase"})
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
		"use_item":
			_act_use_item(action)
		"buy":
			_act_buy(action)
		"end_turn":
			_resolve_turn()
		_:
			_emit({"t": "error", "msg": "unknown action"})
	return _step_events


func legal_actions() -> Array:
	var acts: Array = []
	if over:
		return acts
	if phase == "draft":
		for i in draft_offers.size():
			var is_upgrade: bool = String(draft_offers[i]).ends_with("+")
			if is_upgrade or player["kit"].size() < _kit_max():
				acts.append({"type": "draft", "pick": i})
			else:
				for j in player["kit"].size():
					acts.append({"type": "draft", "pick": i, "drop": j})
		acts.append({"type": "draft", "pick": -1})
		return acts
	if player["charge"] >= _move_cost():
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
			if k == "oil" or k == "goo" or k == "rich_goo":
				acts.append({"type": "cleanse", "target": player["pos"] + d})
	for slot in player["kit"].size():
		if player["gummed"].has(slot):
			continue
		var aid: String = player["kit"][slot]
		if player["charge"] >= int(Content.ABILITIES[aid]["cost"]):
			for tgt in _ability_targets(aid):
				acts.append({"type": "ability", "slot": slot, "target": tgt})
	for i in player["items"].size():
		acts.append({"type": "use_item", "slot": i})
	if player["pos"] == map["stairs"] and greened >= green_need:
		acts.append({"type": "descend"})
	if player["pos"] == map["shrine"]:
		if shop.get("heal", false) and bloom >= shop_cost("heal") and player["hp"] < player["max_hp"]:
			acts.append({"type": "buy", "item": "heal"})
		if shop.has("ability") and bloom >= shop_cost("ability") and player["kit"].size() < _kit_max():
			acts.append({"type": "buy", "item": "ability"})
		if shop.has("graft") and bloom >= shop_cost("graft"):
			acts.append({"type": "buy", "item": "graft"})
		if shop.has("item") and bloom >= shop_cost("item") and player["items"].size() < Content.ITEM_CAP:
			acts.append({"type": "buy", "item": "item"})
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
			"status": e["status"].duplicate(),
			"elite": e.get("elite", false),
		})
	var terr := {}
	for t in terrain.keys():
		terr[t] = terrain[t].duplicate()
	return {
		"floor": floor_num, "floor_name": Content.FLOORS[floor_num - 1]["name"], "tier": tier,
		"mutators": mutators.duplicate(),
		"stoked": stoked,
		"turn": turn, "total_turns": total_turns,
		"smog": smog, "dim": dim, "bloom": bloom,
		"greened": greened, "green_need": green_need,
		"over": over, "won": won, "death_cause": death_cause,
		"phase": phase, "draft_offers": draft_offers.duplicate(),
		"player": {
			"pos": player["pos"], "hp": player["hp"], "max_hp": player["max_hp"],
			"charge": player["charge"], "bank": player["bank"], "shield": player["shield"],
			"kit": player["kit"].duplicate(), "uses": player["uses"].duplicate(),
			"grafts": player["grafts"].duplicate(), "gummed": player["gummed"].duplicate(),
			"thorns_dmg": player["thorns_dmg"], "thorns_turns": player["thorns_turns"],
			"anchor_turns": player["anchor_turns"], "items": player["items"].duplicate(),
		},
		"enemies": ens,
		"map": {
			"w": map["w"], "h": map["h"], "tiles": map["tiles"].duplicate(),
			"start": map["start"], "stairs": map["stairs"], "vents": map["vents"].duplicate(),
			"shrine": map["shrine"], "rooms": map.get("rooms", []).duplicate(),
			"bloomed": map.get("bloomed", []).duplicate(),
			"restored": map.get("restored", false),
		},
		"shop": shop.duplicate(),
		"terrain": terr,
		"events": recent_events.duplicate(true),
	}


func state_hash() -> String:
	return str(snapshot()).sha256_text()


## Deep copy of the whole game, including RNG state. Enables search bots,
## forked what-if analysis, and save/load.
func clone():
	var g = get_script().new(seed_value, {"_blank": true})
	g.rng.state = rng.state
	g.tier = tier
	g.mutators = mutators.duplicate()
	g.stoked = stoked
	g.greened = greened
	g.green_need = green_need
	g._fixed_floor = _fixed_floor.duplicate(true)
	g.draft_pool = draft_pool.duplicate()
	g.floor_num = floor_num
	g.turn = turn
	g.total_turns = total_turns
	g.smog = smog
	g.dim = dim
	g.bloom = bloom
	g.over = over
	g.won = won
	g.death_cause = death_cause
	g.player = player.duplicate(true)
	g.enemies = enemies.duplicate(true)
	g.map = map.duplicate(true)
	g.terrain = terrain.duplicate(true)
	g.recent_events = recent_events.duplicate(true)
	g.phase = phase
	g.draft_offers = draft_offers.duplicate()
	g.shop = shop.duplicate(true)
	g._next_id = _next_id
	g._pending_floor = _pending_floor
	return g


# --- floor / turn flow --------------------------------------------------------

func _enter_floor(n: int) -> void:
	floor_num = n
	turn = 0
	smog = 0
	dim = 0
	var fdef := floor_def(n)
	var gen: Dictionary
	if n == 1 and not _fixed_floor.is_empty():
		gen = _fixed_floor["gen"].duplicate(true)
	else:
		gen = MapGen.generate(rng, fdef)
	map = gen
	terrain = gen["terrain"]
	map["bloomed"] = []
	map["restored"] = false
	greened = 0
	# the quota can never exceed what the floor actually generated
	green_need = mini(int(fdef.get("green_need", 0)), _count_corruption())
	player["pos"] = gen["start"]
	enemies.clear()
	for spec in gen["enemies"]:
		var e := _spawn(spec["kind"], spec["pos"])
		if spec.get("elite", false):
			e["elite"] = true
			e["hp"] += Content.ELITE_HP_BONUS
	shop = {} if mutators.has("boarded") else _stock_shop()
	if _has_graft("carapace"):
		player["shield"] = mini(maxi(player["shield"], 2), _shield_cap())
	_emit({"t": "floor", "floor": n, "name": fdef["name"]})
	_compute_intents()


## Deterministic side-stream: draws that are incidental to the core action
## economy (shop flavor, supply drops) come from a forked generator so they
## never shift the main rng stream - keeps cross-version seed comparability.
func _side_rng(tag: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, floor_num, tag])
	return r


func _stock_shop() -> Dictionary:
	var stock := {"heal": true}
	var aids: Array = []
	for aid in draft_pool:
		if not player["kit"].has(aid):
			aids.append(aid)
	if not aids.is_empty():
		stock["ability"] = aids[rng.randi_range(0, aids.size() - 1)]
	var gids: Array = []
	for gid in Content.GRAFTS:
		if not player["grafts"].has(gid):
			gids.append(gid)
	if not gids.is_empty():
		stock["graft"] = gids[rng.randi_range(0, gids.size() - 1)]
	var iids: Array = Content.ITEMS.keys()
	var srng := _side_rng("shop_item")
	stock["item"] = iids[srng.randi_range(0, iids.size() - 1)]
	return stock


func _begin_player_turn() -> void:
	var regen: int = maxi(1, Content.BASE_REGEN - dim) + (1 if _has_graft("solar_core") else 0)
	player["charge"] = player["bank"] + regen
	player["bank"] = 0
	for slot in player["gummed"].keys().duplicate():
		player["gummed"][slot] -= 1
		if player["gummed"][slot] <= 0:
			player["gummed"].erase(slot)
	if player["thorns_turns"] > 0:
		player["thorns_turns"] -= 1
		if player["thorns_turns"] == 0:
			player["thorns_dmg"] = 0
	if player["anchor_turns"] > 0:
		player["anchor_turns"] -= 1


func _resolve_turn() -> void:
	player["bank"] = mini(player["charge"], _bank_cap())
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
		if edef["traits"].has("boss"):
			_compute_boss_intent(e, edef)
			continue
		if edef["traits"].has("summons"):
			e["intent"] = {"type": "summon", "in": e.get("timer", int(edef["summon_cycle"]))}
			continue
		if edef["traits"].has("oozes"):
			e["intent"] = {"type": "ooze", "in": e.get("timer", int(edef["ooze_cycle"]))}
			continue
		if edef["traits"].has("stokes"):
			e["intent"] = {"type": "stoke", "in": e.get("timer", int(edef["stoke_cycle"]))}
			continue
		if edef["traits"].has("drags"):
			var dd := _manhattan(e["pos"], player["pos"])
			if dd > 1 and dd <= int(edef["drag_range"]):
				e["intent"] = {"type": "drag"}
			else:
				e["intent"] = {"type": "move"}
			continue
		if edef["traits"].has("gums"):
			if _manhattan(e["pos"], player["pos"]) <= int(edef["gum_range"]) and not player["kit"].is_empty():
				e["intent"] = {"type": "gum", "slot": rng.randi_range(0, player["kit"].size() - 1)}
			else:
				e["intent"] = {"type": "move"}
			continue
		if edef["traits"].has("drains"):
			if _manhattan(e["pos"], player["pos"]) <= int(edef["drain_range"]):
				e["intent"] = {"type": "drain", "amount": edef["drain"]}
			else:
				e["intent"] = {"type": "move"}
		elif _manhattan(e["pos"], player["pos"]) == 1:
			var dmg: int = int(edef["dmg"]) + (Content.ELITE_DMG_BONUS if e.get("elite", false) else 0) + _tier_mod("enemy_dmg_delta")
			e["intent"] = {"type": "attack", "tile": player["pos"], "dmg": dmg}
		else:
			e["intent"] = {"type": "move"}


func _apply_status(e: Dictionary, status: String, turns: int) -> void:
	if Content.ENEMIES[e["kind"]]["traits"].has("massive"):
		_emit({"t": "immune", "id": e["id"]})
		return
	e["status"][status] = maxi(int(e["status"].get(status, 0)), turns)
	_emit({"t": "status", "id": e["id"], "status": status, "turns": turns})


func _compute_boss_intent(e: Dictionary, edef: Dictionary) -> void:
	var c: int = e.get("cycle", 0)
	if edef["traits"].has("dredges"):
		var pd: bool = e["hp"] <= 10
		match c % 3:
			0:
				if _manhattan(e["pos"], player["pos"]) <= int(edef["drag_range"]):
					e["intent"] = {"type": "drag", "times": 2 if pd else 1}
				else:
					e["intent"] = {"type": "advance", "steps": 2}
			1:
				if _manhattan(e["pos"], player["pos"]) <= int(edef["slam_range"]):
					e["intent"] = {"type": "slam", "tile": player["pos"], "dmg": int(edef["dmg"]) + _tier_mod("enemy_dmg_delta")}
				else:
					e["intent"] = {"type": "advance", "steps": 2}
			2:
				e["intent"] = {"type": "dredge", "radius": 3 if pd else 2}
		return
	if edef["traits"].has("mobile_boss"):
		var p2: bool = e["hp"] <= 10
		match c % 3:
			0:
				e["intent"] = {"type": "advance", "steps": 3 if p2 else 2}
			1:
				if _manhattan(e["pos"], player["pos"]) <= int(edef["slam_range"]):
					e["intent"] = {"type": "slam", "tile": player["pos"], "dmg": int(edef["dmg"]) + _tier_mod("enemy_dmg_delta")}
				else:
					e["intent"] = {"type": "advance", "steps": 2}
			2:
				if p2 and _manhattan(e["pos"], player["pos"]) <= 2:
					e["intent"] = {"type": "quake", "dmg": 2 + _tier_mod("enemy_dmg_delta")}
				elif _manhattan(e["pos"], player["pos"]) <= int(edef["slam_range"]):
					e["intent"] = {"type": "slam", "tile": player["pos"], "dmg": int(edef["dmg"]) + _tier_mod("enemy_dmg_delta")}
				else:
					e["intent"] = {"type": "advance", "steps": 2}
		return
	var phase2: bool = e["hp"] <= 12
	match c % 3:
		0:
			var row: int = clampi(player["pos"].y + rng.randi_range(-1, 1), 1, int(map["h"]) - 2)
			e["intent"] = {"type": "flood", "row": row}
		1:
			if _manhattan(e["pos"], player["pos"]) <= int(edef["slam_range"]):
				e["intent"] = {"type": "slam", "tile": player["pos"], "dmg": int(edef["dmg"]) + _tier_mod("enemy_dmg_delta")}
			else:
				e["intent"] = {"type": "gather"}
		2:
			if phase2:
				e["intent"] = {"type": "ignite_all"}
			elif _manhattan(e["pos"], player["pos"]) <= int(edef["slam_range"]):
				e["intent"] = {"type": "slam", "tile": player["pos"], "dmg": int(edef["dmg"]) + _tier_mod("enemy_dmg_delta")}
			else:
				e["intent"] = {"type": "gather"}


## Forced movement interrupts the wind-up: the enemy drops its telegraphed
## intent and re-decides next turn. Per-enemy cooldown so cheap displacement
## cannot interrupt-lock a single target forever; bosses hold their footing.
func _stagger(e: Dictionary) -> void:
	if int(e["status"].get("stagger_cd", 0)) > 0:
		return
	if Content.ENEMIES[e["kind"]]["traits"].has("boss"):
		return
	e["status"]["stagger_cd"] = 3
	e["intent"] = {"type": "idle"}
	_emit({"t": "staggered", "id": e["id"]})


func _execute_intent(e: Dictionary) -> void:
	if int(e["status"].get("stagger_cd", 0)) > 0:
		e["status"]["stagger_cd"] -= 1
	if int(e["status"].get("stun", 0)) > 0:
		e["status"]["stun"] -= 1
		_emit({"t": "stunned", "id": e["id"]})
		return
	var it: Dictionary = e["intent"]
	if String(it.get("type", "")) == "move" and int(e["status"].get("root", 0)) > 0:
		e["status"]["root"] -= 1
		_emit({"t": "rooted", "id": e["id"]})
		return
	match String(it.get("type", "idle")):
		"attack":
			if player["pos"] == it["tile"]:
				_damage_player(int(it["dmg"]), e["kind"])
				if player["thorns_turns"] > 0 and _manhattan(e["pos"], player["pos"]) == 1:
					_damage_enemy(e, player["thorns_dmg"], "thorns")
		"flood":
			e["cycle"] = int(e.get("cycle", 0)) + 1
			var row: int = it["row"]
			for x in range(1, int(map["w"]) - 1):
				var p := Vector2i(x, row)
				if _tile(p) == MapGen.T_FLOOR and not terrain.has(p) and _enemy_at(p) == null and p != player["pos"]:
					terrain[p] = {"kind": "oil"}
			_emit({"t": "flood", "row": row})
		"slam":
			e["cycle"] = int(e.get("cycle", 0)) + 1
			var area: Array = [it["tile"]]
			for d in DIRS:
				area.append(it["tile"] + d)
			if area.has(player["pos"]):
				_damage_player(int(it["dmg"]), e["kind"])
				# spiky bark punishes physical contact: a slammer close enough
				# to touch (within 2) eats the reflection like melee and quakes
				if player["thorns_turns"] > 0 and _manhattan(e["pos"], player["pos"]) <= 2:
					_damage_enemy(e, player["thorns_dmg"], "thorns")
		"ignite_all":
			e["cycle"] = int(e.get("cycle", 0)) + 1
			for t in terrain.keys().duplicate():
				if terrain[t]["kind"] == "oil":
					terrain[t] = {"kind": "fire", "ttl": 2}
			_emit({"t": "ignite_all"})
		"gather":
			e["cycle"] = int(e.get("cycle", 0)) + 1
		"advance":
			e["cycle"] = int(e.get("cycle", 0)) + 1
			for i in range(int(it["steps"])):
				if _manhattan(e["pos"], player["pos"]) == 1:
					break
				var dest := _chase_step(e)
				if dest == e["pos"]:
					break
				e["pos"] = dest
				_enemy_enter_tile(e)
				if not enemies.has(e):
					break
		"quake":
			e["cycle"] = int(e.get("cycle", 0)) + 1
			if _manhattan(e["pos"], player["pos"]) == 1:
				_damage_player(int(it["dmg"]), e["kind"])
				if player["thorns_turns"] > 0:
					_damage_enemy(e, player["thorns_dmg"], "thorns")
		"ooze":
			var odef: Dictionary = Content.ENEMIES[e["kind"]]
			var otimer: int = e.get("timer", int(odef["ooze_cycle"])) - 1
			if otimer <= 0:
				for d in DIRS:
					var p: Vector2i = e["pos"] + d
					if _tile(p) == MapGen.T_FLOOR and not terrain.has(p) and _enemy_at(p) == null and p != player["pos"]:
						terrain[p] = {"kind": "oil"}
						_emit({"t": "ooze", "id": e["id"], "tile": p})
						break
				otimer = int(odef["ooze_cycle"])
			e["timer"] = otimer
		"stoke":
			var kdef: Dictionary = Content.ENEMIES[e["kind"]]
			var ktimer: int = e.get("timer", int(kdef["stoke_cycle"])) - 1
			if ktimer <= 0:
				stoked += 1
				_emit({"t": "stoke", "id": e["id"]})
				ktimer = int(kdef["stoke_cycle"])
			e["timer"] = ktimer
		"drag":
			e["cycle"] = int(e.get("cycle", 0)) + 1
			var cdef: Dictionary = Content.ENEMIES[e["kind"]]
			for i in int(it.get("times", 1)):
				if player["anchor_turns"] > 0:
					_emit({"t": "anchored", "id": e["id"]})
					break
				var cd := _manhattan(e["pos"], player["pos"])
				if cd <= 1 or cd > int(cdef["drag_range"]):
					break
				var delta: Vector2i = e["pos"] - player["pos"]
				var step := Vector2i.ZERO
				if delta.x != 0 and absi(delta.x) >= absi(delta.y):
					step = Vector2i(signi(delta.x), 0)
				elif delta.y != 0:
					step = Vector2i(0, signi(delta.y))
				var dest: Vector2i = player["pos"] + step
				if step == Vector2i.ZERO or _tile(dest) != MapGen.T_FLOOR or _enemy_at(dest) != null:
					break
				player["pos"] = dest
				_emit({"t": "drag", "id": e["id"], "to": dest})
				_player_enter_tile()
				if over:
					return
		"dredge":
			e["cycle"] = int(e.get("cycle", 0)) + 1
			var dredged := 0
			for t in terrain.keys().duplicate():
				if terrain[t]["kind"] == "growth" and _manhattan(t, e["pos"]) <= int(it.get("radius", 2)):
					terrain[t] = {"kind": "goo"}
					dredged += 1
			if dredged > 0:
				# heal caps at 3 per bite: in the greened world an uncapped
				# radius-3 dredge was a 6-8 hp swing per action
				var cap: int = int(Content.ENEMIES[e["kind"]]["hp"]) + _tier_mod("boss_hp_delta")
				e["hp"] = mini(e["hp"] + mini(dredged, 3), cap)
				_emit({"t": "dredge", "id": e["id"], "tiles": dredged})
		"summon":
			var edef: Dictionary = Content.ENEMIES[e["kind"]]
			var timer: int = e.get("timer", int(edef["summon_cycle"])) - 1
			if timer <= 0:
				for d in DIRS:
					if _open(e["pos"] + d):
						var s := _spawn("sludgeling", e["pos"] + d)
						s["intent"] = {"type": "idle"}
						_emit({"t": "summon", "id": e["id"], "child": s["id"]})
						break
				timer = int(edef["summon_cycle"])
			e["timer"] = timer
		"gum":
			var gdef: Dictionary = Content.ENEMIES[e["kind"]]
			if _manhattan(e["pos"], player["pos"]) <= int(gdef["gum_range"]):
				var slot: int = it["slot"]
				if slot < player["kit"].size():
					player["gummed"][slot] = maxi(int(player["gummed"].get(slot, 0)), int(gdef["gum_turns"]))
					_emit({"t": "gummed", "slot": slot, "id": player["kit"][slot]})
		"drain":
			if _manhattan(e["pos"], player["pos"]) <= int(Content.ENEMIES[e["kind"]]["drain_range"]):
				var drained: int = mini(player["bank"], int(it["amount"]))
				player["bank"] -= drained
				_emit({"t": "drain", "id": e["id"], "amt": drained})
		"move":
			var steps: int = 2 if Content.ENEMIES[e["kind"]]["traits"].has("fast") else 1
			for i in range(steps):
				if not enemies.has(e) or _manhattan(e["pos"], player["pos"]) == 1:
					break
				var dest := _chase_step(e)
				if dest == e["pos"]:
					break
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
	for t in terrain.keys().duplicate():
		if terrain[t]["kind"] == "roots" or terrain[t]["kind"] == "smoke":
			terrain[t]["ttl"] -= 1
			if terrain[t]["ttl"] <= 0:
				terrain.erase(t)
	for p in spreads:
		terrain[p] = {"kind": "fire", "ttl": 2}
		_emit({"t": "ignite", "tile": p})
	for e in enemies.duplicate():
		if int(e["status"].get("spore", 0)) > 0:
			e["status"]["spore"] -= 1
			_damage_enemy(e, 1, "spore")
	if _terrain_kind(player["pos"]) == "growth" and player["hp"] < player["max_hp"]:
		var heal_amt: int = 1 + (1 if _has_graft("verdant_pulse") else 0)
		player["hp"] = mini(player["hp"] + heal_amt, player["max_hp"])
		_emit({"t": "heal", "amt": heal_amt})


func _tick_smog() -> void:
	# smokestack stokes are extra FULL ticks, so dim/choke/spawn thresholds
	# are crossed one value at a time and never skipped
	var ticks := 1 + stoked
	stoked = 0
	for i in ticks:
		smog += 1
		var fdef := floor_def(floor_num)
		if fdef["smog_dim"].has(smog) and dim < 2:
			dim += 1
			_emit({"t": "smog_dim", "dim": dim})
		var choke: int = fdef.get("smog_choke", 0)
		if choke > 0 and smog >= choke and (smog - choke) % 3 == 0:
			# escalates as the smog deepens so no amount of healing sustains
			# camping forever - the clock must always win eventually, or streams
			# of summons plus growth regen produce unwinnable-but-unlosable runs
			_emit({"t": "choke"})
			_damage_player(1 + (smog - choke) / 60, "smog")
			if over:
				return
		var spawn: bool = fdef["smog_spawn"].has(smog)
		if not spawn:
			var last: int = fdef["smog_spawn"].back()
			var every: int = fdef.get("smog_spawn_every", 0)
			spawn = every > 0 and smog > last and (smog - last) % every == 0
		if spawn:
			for v in map["vents"]:
				if _open(v):
					if _terrain_kind(v) == "growth":
						# nature chokes the machine: the seal absorbs this spawn
						terrain.erase(v)
						_emit({"t": "seal_burst", "tile": v})
						continue
					var e := _spawn("drill_bot", v)
					e["intent"] = {"type": "idle"}
					_emit({"t": "reinforcement", "tile": v})


# --- player actions -----------------------------------------------------------

func _act_move(action: Dictionary) -> void:
	var dir: Vector2i = action.get("dir", Vector2i.ZERO)
	var dest: Vector2i = player["pos"] + dir
	var cost := _move_cost()
	if not DIRS.has(dir) or player["charge"] < cost or not _open(dest):
		_emit({"t": "illegal", "action": "move"})
		return
	player["charge"] -= cost
	player["pos"] = dest
	_emit({"t": "move", "who": "player", "to": dest})
	_player_enter_tile()


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
	var legal := _manhattan(target, player["pos"]) == 1 and (k == "oil" or k == "goo" or k == "rich_goo")
	if not legal or player["charge"] < Content.CLEANSE_COST:
		_emit({"t": "illegal", "action": "cleanse"})
		return
	player["charge"] -= Content.CLEANSE_COST
	# tending leaves life behind: the cleansed tile sprouts growth
	terrain[target] = {"kind": "growth"}
	var yield_: int = Content.RICH_GOO_BLOOM if k == "rich_goo" else 1
	bloom += yield_ + (1 if _has_graft("bloom_surge") else 0)
	# tending the world buys time, but the sky can only mend so fast per
	# floor: quota cleanses thin the smog by 2 (funds the gate's detour),
	# the next few thin it by 1, and beyond that cleansing still pays
	# bloom/growth/blooms but no longer pauses the clock - this is what
	# keeps marathon cleanse-farming from stalling the game (measured:
	# uncapped relief-1 put the ceiling bot at 92%)
	var relief := 0
	if greened < green_need:
		relief = Content.CLEANSE_SMOG_RELIEF + 1
	elif greened < green_need + 4:
		relief = Content.CLEANSE_SMOG_RELIEF
	smog = maxi(smog - relief, 0)
	greened += 1
	_emit({"t": "cleanse", "tile": target, "bloom": bloom})
	if green_need > 0 and greened == green_need:
		_emit({"t": "stairs_awaken", "tile": map["stairs"]})
	_check_room_bloom(target)
	# the whole floor scrubbed clean: it is RESTORED - skies clear for good
	if not map.get("restored", false) and _count_corruption() == 0:
		map["restored"] = true
		dim = 0
		smog = maxi(smog - 8, 0)
		bloom += 5
		_emit({"t": "floor_restored", "bonus": 5})


func _act_descend() -> void:
	if player["pos"] != map["stairs"]:
		_emit({"t": "illegal", "action": "descend"})
		return
	if greened < green_need:
		_emit({"t": "stairs_dormant", "have": greened, "need": green_need})
		return
	if floor_num >= Content.FLOORS.size():
		won = true
		over = true
		_emit({"t": "win"})
		return
	player["bank"] = mini(player["charge"], _bank_cap())
	player["max_hp"] += Content.DESCEND_MAX_HP_BONUS
	player["hp"] = mini(player["hp"] + Content.DESCEND_HEAL, player["max_hp"])
	_emit({"t": "descend", "to_floor": floor_num + 1})
	_pending_floor = floor_num + 1
	draft_offers = _draw_draft_offers(3)
	if draft_offers.is_empty():
		_enter_floor(_pending_floor)
		_begin_player_turn()
	else:
		phase = "draft"
		_emit({"t": "draft_offer", "offers": draft_offers.duplicate()})


func _draw_draft_offers(count: int) -> Array:
	var candidates: Array = []
	for aid in draft_pool:
		if not player["kit"].has(aid) and not player["kit"].has(aid + "+"):
			candidates.append(aid)
	for aid in player["kit"]:
		var up: String = aid + "+"
		if Content.ABILITIES.has(up):
			candidates.append(up)
	var offers: Array = []
	while offers.size() < count and not candidates.is_empty():
		var i := rng.randi_range(0, candidates.size() - 1)
		offers.append(candidates[i])
		candidates.remove_at(i)
	return offers


func _act_draft(action: Dictionary) -> void:
	var pick: int = action.get("pick", -1)
	if pick >= draft_offers.size():
		_emit({"t": "illegal", "action": "draft"})
		return
	if pick >= 0:
		var aid: String = draft_offers[pick]
		if aid.ends_with("+"):
			var slot: int = player["kit"].find(aid.trim_suffix("+"))
			if slot == -1:
				_emit({"t": "illegal", "action": "draft"})
				return
			player["kit"][slot] = aid
			player["uses"][aid] = int(player["uses"].get(aid.trim_suffix("+"), 0))
			_emit({"t": "draft_upgrade", "id": aid})
		elif player["kit"].size() >= _kit_max():
			var drop: int = action.get("drop", -1)
			if drop < 0 or drop >= player["kit"].size():
				_emit({"t": "illegal", "action": "draft drop"})
				return
			_emit({"t": "draft_drop", "id": player["kit"][drop]})
			player["kit"][drop] = aid
		else:
			player["kit"].append(aid)
		_emit({"t": "draft_pick", "id": aid})
	else:
		_emit({"t": "draft_skip"})
	draft_offers = []
	phase = "play"
	_enter_floor(_pending_floor)
	_begin_player_turn()


func _act_use_item(action: Dictionary) -> void:
	var slot := int(action.get("slot", -1))
	if slot < 0 or slot >= player["items"].size():
		_emit({"t": "illegal", "action": "use_item"})
		return
	var iid := String(player["items"][slot])
	player["items"].remove_at(slot)
	match iid:
		"sun_capsule":
			player["charge"] += 3
		"balm_fruit":
			player["hp"] = mini(player["hp"] + 4, player["max_hp"])
		"spore_vial":
			for e in enemies:
				if _manhattan(e["pos"], player["pos"]) <= 2 and not Content.ENEMIES[e["kind"]]["traits"].has("boss"):
					e["status"]["stun"] = maxi(int(e["status"].get("stun", 0)), 1)
		"clearair_pod":
			smog = maxi(smog - 5, 0)
		"iron_seed":
			player["shield"] = mini(player["shield"] + 3, _shield_cap())
	_emit({"t": "item_use", "id": iid})


func _room_of(p: Vector2i) -> int:
	var rooms: Array = map.get("rooms", [])
	for i in rooms.size():
		if rooms[i].has_point(p):
			return i
	return -1


func _count_corruption() -> int:
	var cnt := 0
	for t in terrain.keys():
		var k := String(terrain[t]["kind"])
		if k == "oil" or k == "goo" or k == "rich_goo":
			cnt += 1
	return cnt


func _room_has_corruption(ri: int) -> bool:
	var r: Rect2i = map["rooms"][ri]
	for t in terrain.keys():
		if r.has_point(t):
			var k := String(terrain[t]["kind"])
			if k == "oil" or k == "goo" or k == "rich_goo":
				return true
	return false


## A fully tended room blooms once: bonus bloom and a supply drop.
func _check_room_bloom(p: Vector2i) -> void:
	var ri := _room_of(p)
	if ri < 0 or map.get("bloomed", []).has(ri) or _room_has_corruption(ri):
		return
	map["bloomed"].append(ri)
	bloom += Content.ROOM_BLOOM_BONUS
	var r: Rect2i = map["rooms"][ri]
	var spots: Array = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var t := Vector2i(x, y)
			if _open(t) and not terrain.has(t) and t != player["pos"] and t != map["stairs"] and t != map["shrine"]:
				spots.append(t)
	if not spots.is_empty():
		# the pod springs up as close to the tender as the room allows
		# (row-major scan order breaks ties deterministically)
		var t2: Vector2i = spots[0]
		for t3 in spots:
			if _manhattan(t3, player["pos"]) < _manhattan(t2, player["pos"]):
				t2 = t3
		var srng := _side_rng("supply%d" % ri)
		var ids: Array = Content.ITEMS.keys()
		terrain[t2] = {"kind": "supply", "item": ids[srng.randi_range(0, ids.size() - 1)]}
	_emit({"t": "room_bloom", "room": ri, "bonus": Content.ROOM_BLOOM_BONUS})


func _act_buy(action: Dictionary) -> void:
	var item := String(action.get("item", ""))
	var cost: int = shop_cost(item)
	var on_shrine: bool = player["pos"] == map["shrine"]
	if not on_shrine or bloom < cost:
		_emit({"t": "illegal", "action": "buy"})
		return
	match item:
		"heal":
			if not shop.get("heal", false) or player["hp"] >= player["max_hp"]:
				_emit({"t": "illegal", "action": "buy"})
				return
			shop.erase("heal")
			bloom -= cost
			player["hp"] = mini(player["hp"] + Content.SHOP_HEAL_AMOUNT, player["max_hp"])
			_emit({"t": "buy", "item": "heal", "hp": player["hp"]})
		"ability":
			if not shop.has("ability") or player["kit"].size() >= _kit_max():
				_emit({"t": "illegal", "action": "buy"})
				return
			bloom -= cost
			var aid: String = shop["ability"]
			shop.erase("ability")
			player["kit"].append(aid)
			_emit({"t": "buy", "item": "ability", "id": aid})
		"graft":
			if not shop.has("graft"):
				_emit({"t": "illegal", "action": "buy"})
				return
			bloom -= cost
			var gid: String = shop["graft"]
			shop.erase("graft")
			player["grafts"].append(gid)
			_emit({"t": "buy", "item": "graft", "id": gid})
		"item":
			if not shop.has("item") or player["items"].size() >= Content.ITEM_CAP:
				_emit({"t": "illegal", "action": "buy"})
				return
			bloom -= cost
			var iid2: String = shop["item"]
			shop.erase("item")
			player["items"].append(iid2)
			_emit({"t": "buy", "item": "item", "id": iid2})
		_:
			_emit({"t": "illegal", "action": "buy"})


func _has_graft(gid: String) -> bool:
	return player["grafts"].has(gid)


func _bank_cap() -> int:
	if mutators.has("parched"):
		return 0
	return Content.BANK_CAP + (2 if _has_graft("deep_cells") else 0)


func _shield_cap() -> int:
	return Content.SHIELD_CAP + (2 if _has_graft("thick_bark") else 0)


func _act_ability(action: Dictionary) -> void:
	var slot: int = action.get("slot", -1)
	if slot < 0 or slot >= player["kit"].size() or player["gummed"].has(slot):
		_emit({"t": "illegal", "action": "ability"})
		return
	var aid: String = player["kit"][slot]
	var adef: Dictionary = Content.ABILITIES[aid]
	var target = action.get("target")
	if player["charge"] < int(adef["cost"]) or not _ability_targets(aid).has(target):
		_emit({"t": "illegal", "action": "ability", "id": aid})
		return
	player["charge"] -= int(adef["cost"])
	player["uses"][aid] = int(player["uses"].get(aid, 0)) + 1
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
		"self":
			out.append(player["pos"])
		"tile_any":
			for dy in range(-rng_, rng_ + 1):
				for dx in range(-rng_, rng_ + 1):
					if absi(dx) + absi(dy) > rng_:
						continue
					var p: Vector2i = player["pos"] + Vector2i(dx, dy)
					if _tile(p) == MapGen.T_FLOOR:
						out.append(p)
		"enemy":
			for e in enemies:
				if _manhattan(e["pos"], player["pos"]) <= rng_:
					out.append(e["pos"])
		"enemy_near_growth":
			for e in enemies:
				if _manhattan(e["pos"], player["pos"]) > rng_:
					continue
				var near := _terrain_kind(e["pos"]) == "growth"
				for d in DIRS:
					if _terrain_kind(e["pos"] + d) == "growth":
						near = true
				if near:
					out.append(e["pos"])
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
			# massive enemies cannot be dragged, but the lash still lands -
			# no ability should be a dead button against bosses
			if not Content.ENEMIES[e["kind"]]["traits"].has("massive"):
				var delta: Vector2i = player["pos"] - e["pos"]
				var dir := Vector2i(signi(delta.x), signi(delta.y))
				var pulled := 0
				for i in range(int(eff["dist"])):
					var nxt: Vector2i = e["pos"] + dir
					if _manhattan(e["pos"], player["pos"]) <= 1 or not _open(nxt):
						break
					e["pos"] = nxt
					pulled += 1
					_enemy_enter_tile(e)
					if not enemies.has(e):
						return
				if pulled > 0:
					_stagger(e)
			_damage_enemy(e, int(eff["dmg"]), "vine_whip")
		"wash_push":
			_wash_dir(target, int(adef["range"]), int(eff["push"]), int(eff["collision_dmg"]))
		"wash_all":
			for d in DIRS:
				_wash_dir(d, int(adef["range"]), int(eff["push"]), int(eff["collision_dmg"]))
		"push_line":
			var p: Vector2i = player["pos"]
			for i in range(int(adef["range"])):
				p += target
				if _tile(p) == MapGen.T_WALL:
					break
				if bool(eff.get("clear_smoke", false)) and _terrain_kind(p) == "smoke":
					terrain.erase(p)
					_emit({"t": "smoke_cleared", "tile": p})
				var e = _enemy_at(p)
				if e != null:
					_push_enemy(e, target, int(eff["dist"]), 1)
					break
		"push_all":
			for d in DIRS:
				var e = _enemy_at(player["pos"] + d)
				if e != null:
					_push_enemy(e, d, int(eff["dist"]), 1)
		"dash_dir":
			for i in range(int(adef["range"])):
				var nxt: Vector2i = player["pos"] + target
				if not _open(nxt):
					break
				player["pos"] = nxt
				_player_enter_tile()
				if over:
					return
			_emit({"t": "dash", "to": player["pos"]})
		"create_terrain":
			if _tile(target) == MapGen.T_FLOOR and not terrain.has(target):
				terrain[target] = {"kind": String(eff["kind"]), "ttl": int(eff["ttl"])}
				_emit({"t": "terrain", "kind": eff["kind"], "tile": target})
		"clear_smoke":
			for t in terrain.keys().duplicate():
				if terrain[t]["kind"] == "smoke" and _manhattan(t, player["pos"]) <= int(eff["radius"]):
					terrain.erase(t)
					_emit({"t": "smoke_cleared", "tile": t})
		"teleport":
			player["pos"] = target
			_emit({"t": "teleport", "to": target})
		"grow_wall":
			var walled: Array = [target]
			for d in DIRS:
				walled.append(target + d)
			for t in walled:
				if _tile(t) == MapGen.T_FLOOR and not terrain.has(t) and _open(t) and t != map["stairs"]:
					terrain[t] = {"kind": "roots", "ttl": int(eff["ttl"])}
			_emit({"t": "roots", "tile": target})
		"shield":
			player["shield"] = mini(player["shield"] + int(eff["amount"]), _shield_cap())
			_emit({"t": "shield", "total": player["shield"]})
		"thorns":
			player["thorns_dmg"] = int(eff["dmg"])
			player["thorns_turns"] = maxi(player["thorns_turns"], int(eff["turns"]))
			_emit({"t": "thorns", "dmg": eff["dmg"], "turns": player["thorns_turns"]})
		"anchor":
			player["anchor_turns"] = maxi(player["anchor_turns"], int(eff["turns"]))
			_emit({"t": "anchor", "turns": player["anchor_turns"]})
		"undim":
			# relieves the dim penalty only - raw smog is untouched, so choke
			# still scales and the clock still wins; no scrub-camping loops
			if dim > 0:
				dim = maxi(0, dim - int(eff["amount"]))
				_emit({"t": "undim", "dim": dim})
		"aoe_status":
			for e in enemies.duplicate():
				if _manhattan(e["pos"], player["pos"]) <= int(eff["radius"]):
					_apply_status(e, String(eff["status"]), int(eff["turns"]))
		"aoe_damage":
			for t in terrain.keys().duplicate():
				if bool(eff.get("ignite", false)) and terrain[t]["kind"] == "oil" and _manhattan(t, player["pos"]) <= int(eff["radius"]):
					terrain[t] = {"kind": "fire", "ttl": 2}
					_emit({"t": "ignite", "tile": t})
			for e in enemies.duplicate():
				if _manhattan(e["pos"], player["pos"]) <= int(eff["radius"]):
					_damage_enemy(e, int(eff["dmg"]), "sun_flare")
		"convert_radius":
			for dy in range(-int(eff["radius"]), int(eff["radius"]) + 1):
				for dx in range(-int(eff["radius"]), int(eff["radius"]) + 1):
					if absi(dx) + absi(dy) > int(eff["radius"]):
						continue
					var t: Vector2i = target + Vector2i(dx, dy)
					var k := _terrain_kind(t)
					if k == "oil" or k == "goo":
						terrain[t] = {"kind": "growth"}
						_emit({"t": "convert", "tile": t})
		"apply_status":
			var e = _enemy_at(target)
			if e != null:
				_apply_status(e, String(eff["status"]), int(eff["turns"]))
		"damage":
			var e = _enemy_at(target)
			if e != null:
				_damage_enemy(e, int(eff["dmg"]), "grow_spike")


# --- entities and damage ------------------------------------------------------

func _spawn(kind: String, pos: Vector2i) -> Dictionary:
	var edef: Dictionary = Content.ENEMIES[kind]
	var hp: int = int(edef["hp"]) + _tier_mod("enemy_hp_delta")
	if edef["traits"].has("boss"):
		hp += _tier_mod("boss_hp_delta")
	var e := {"id": _next_id, "kind": kind, "hp": hp, "pos": pos, "intent": {"type": "idle"}, "split_used": false, "status": {}}
	_next_id += 1
	enemies.append(e)
	return e


func _damage_enemy(e: Dictionary, amt: int, src: String) -> void:
	if not enemies.has(e):
		return
	var edef: Dictionary = Content.ENEMIES[e["kind"]]
	if edef["traits"].has("boss") and e["hp"] <= int(edef.get("gate_hp", 6)) 			and not _growth_adjacent(e["pos"]) and _corruption_adjacent(e["pos"]):
		_emit({"t": "core_shielded", "id": e["id"]})
		return
	e["hp"] -= amt
	_emit({"t": "damage", "who": e["kind"], "id": e["id"], "amt": amt, "src": src})
	if e["hp"] <= 0:
		enemies.erase(e)
		_emit({"t": "death", "who": e["kind"], "id": e["id"]})
		if e.get("elite", false):
			bloom += Content.ELITE_BOUNTY
			_emit({"t": "bounty", "bloom": bloom})
		if edef["traits"].has("boss"):
			won = true
			over = true
			_emit({"t": "win"})
			return
		if Content.ENEMIES[e["kind"]]["traits"].has("smoke_burst"):
			var tiles_: Array = [e["pos"]]
			for d in DIRS:
				tiles_.append(e["pos"] + d)
			for t in tiles_:
				if _tile(t) == MapGen.T_FLOOR and not terrain.has(t):
					terrain[t] = {"kind": "smoke", "ttl": 3}
			_emit({"t": "smoke_burst", "tile": e["pos"]})
	elif edef["traits"].has("boss"):
		if edef["traits"].has("mobile_boss"):
			if e["hp"] <= 10 and not e.get("phase2_done", false):
				e["phase2_done"] = true
				_emit({"t": "boss_phase", "phase": 2})
			if e["hp"] <= int(edef.get("gate_hp", 6)) and not e.get("phase3_done", false):
				e["phase3_done"] = true
				_clog_vents(e["pos"])
				_emit({"t": "boss_phase", "phase": 3})
			return
		if e["hp"] <= 12 and not e.get("phase2_done", false):
			e["phase2_done"] = true
			_emit({"t": "boss_phase", "phase": 2})
			for v in map["vents"]:
				if _open(v):
					var g := _spawn("coal_golem", v)
					g["intent"] = {"type": "idle"}
					_emit({"t": "reinforcement", "tile": v})
					break
		if e["hp"] <= 6 and not e.get("phase3_done", false):
			e["phase3_done"] = true
			_clog_vents(e["pos"])
			_emit({"t": "boss_phase", "phase": 3})
	elif Content.ENEMIES[e["kind"]]["traits"].has("splits") and not e["split_used"]:
		e["split_used"] = true
		for d in DIRS:
			var p: Vector2i = e["pos"] + d
			if _open(p):
				var s := _spawn("sludgeling", p)
				_emit({"t": "split", "id": e["id"], "child": s["id"]})
				break


func _damage_player(amt: int, src: String) -> void:
	if player["shield"] > 0:
		var absorbed: int = mini(player["shield"], amt)
		player["shield"] -= absorbed
		amt -= absorbed
		_emit({"t": "shield_absorb", "amt": absorbed})
		if amt <= 0:
			return
	player["hp"] -= amt
	_emit({"t": "damage", "who": "player", "amt": amt, "src": src})
	if player["hp"] <= 0:
		over = true
		death_cause = src
		_emit({"t": "player_death", "cause": src})


func _push_enemy(e: Dictionary, dir: Vector2i, dist: int, collision_dmg: int) -> void:
	if Content.ENEMIES[e["kind"]]["traits"].has("massive"):
		return
	var moved := 0
	for i in range(dist):
		var nxt: Vector2i = e["pos"] + dir
		if not _open(nxt):
			if collision_dmg > 0:
				_damage_enemy(e, collision_dmg, "collision")
				var hit = _enemy_at(nxt)
				if hit != null:
					_damage_enemy(hit, collision_dmg, "collision")
			if moved > 0 and enemies.has(e):
				_stagger(e)
			return
		e["pos"] = nxt
		moved += 1
		_enemy_enter_tile(e)
		if not enemies.has(e):
			return
	if moved > 0:
		_stagger(e)


func _wash_dir(dir: Vector2i, rng_: int, push: int, collision_dmg: int) -> void:
	var line: Array = []
	var p: Vector2i = player["pos"]
	for i in range(rng_):
		p += dir
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
				if Content.ENEMIES[e["kind"]]["traits"].has("massive"):
					# too heavy to shove; the jet's pressure still hits
					if collision_dmg > 0:
						_damage_enemy(e, collision_dmg, "collision")
					return
				pushed = e
	if pushed != null:
		_push_enemy(pushed, dir, push, collision_dmg)


func _player_enter_tile() -> void:
	var k := _terrain_kind(player["pos"])
	if k == "fire":
		_damage_player(1, "fire")
	elif k == "goo" or k == "rich_goo":
		_damage_player(1, "goo")
	elif k == "supply":
		if player["items"].size() < Content.ITEM_CAP:
			var iid := String(terrain[player["pos"]].get("item", "balm_fruit"))
			player["items"].append(iid)
			terrain.erase(player["pos"])
			_emit({"t": "item_pickup", "id": iid})
		else:
			_emit({"t": "satchel_full"})


func _corruption_adjacent(p: Vector2i) -> bool:
	for d in DIRS:
		var k := _terrain_kind(p + d)
		if k == "oil" or k == "goo" or k == "rich_goo":
			return true
	return false


func _clog_vents(p: Vector2i) -> void:
	for d in DIRS:
		var t: Vector2i = p + d
		if _tile(t) == MapGen.T_FLOOR and not terrain.has(t) and _enemy_at(t) == null and t != player["pos"]:
			terrain[t] = {"kind": "goo"}
	_emit({"t": "vents_clogged", "tile": p})


func _growth_adjacent(p: Vector2i) -> bool:
	for d in DIRS:
		if _terrain_kind(p + d) == "growth":
			return true
	return false


func _enemy_enter_tile(e: Dictionary) -> void:
	if Content.ENEMIES[e["kind"]]["traits"].has("igniter") and _terrain_kind(e["pos"]) == "oil":
		terrain[e["pos"]] = {"kind": "fire", "ttl": 2}
		_emit({"t": "ignite", "tile": e["pos"]})
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


func _move_cost() -> int:
	# oil is sticky: stepping off it costs an extra charge
	return Content.MOVE_COST + (1 if _terrain_kind(player["pos"]) == "oil" else 0)


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
	return _tile(p) == MapGen.T_FLOOR and _enemy_at(p) == null and p != player["pos"] and _terrain_kind(p) != "roots"


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
