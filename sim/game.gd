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
##   {"type": "use_item", "slot": int}  (free action)
##   Shrine actions (player standing on map.shrine; shop keys gate each one):
##   {"type": "buy", "item": "heal"}
##   {"type": "buy", "item": "ability"}             (kit not full)
##   {"type": "buy", "item": "graft", "pick": i}    (i indexes shop.grafts; the other offer is discarded)
##   {"type": "buy", "item": "item"}
##   {"type": "upcycle", "keep": k}                  (press: two held items -> the + form of item k; shop.press)
##   {"type": "upcycle_ability", "keep": i, "scrap": j}  (forge: kit[i] -> +, kit[j] scrapped, never mobility; once per floor, shop.forge)
##
## Shop snapshot shape: {heal?, press?, forge?: true, ability?: id, grafts?: [id, id?], item?: id}
## or {} (Boarded mutator / floor without a shrine).

const Content := preload("res://sim/content.gd")
const MapGen := preload("res://sim/mapgen.gd")

## Single source of truth for replay compatibility: bump whenever a sim change
## alters replay behaviour (shell run saves, regression records and autopsy
## dumps all stamp this value). 3: C1b - ash, root cooldown and blocked
## advance/drag, spore add-stacking, spread fire inheriting the bloom flag.
## 4: C2 - rider rows on grow_spike(+), sun_flare(+), water_jet+, vine_whip+
## and seed_bomb+ (Content data only; every cast of those ids replays anew).
## 5: C3 - the hook dispatcher (_hook) and grafts as data: four rule grafts
## (ember_sap, undertow, compost, oil_tithe) join the shop stock, so the
## shop_graft side draw and every hook-carrying run replay anew.
## 6: C4 - the nine package "+" rows (forgeable and draftable once the base is
## held) and mutators as data (Content.MUTATORS[m]["config"] read through
## _mut; no_lance, wide_draft, upgrades_only join the table).
## 7: Block A - the starting kit comes from Content.LOADOUTS[config.loadout]
## (a run recorded with a non-default loadout replays with that kit from now
## on; "tender" is STARTING_KIT so default runs are untouched) and the
## open_pool mutator row.
## 8: graft prices as data (Content.GRAFTS[g]["price"], shop_cost("graft", id)):
## which graft a purse can afford changed, so any log that bought a graft - or
## skipped one it could not afford - replays differently. snapshot().shop also
## carries "graft_prices" now; that key is derived, so state_hash() hashes the
## raw stored shop instead and the hash never sees it.
## 9: Block D1 - per-ability stat surges and Spore Trail. A cast surges when
## the tender stands on growth and its "surge" dict carries anything that
## applies (a cost delta on a cost >= 2 cast, or any stat delta); a stat surge
## adds the delta to every effect of the cast that carries the key, so
## grow_spike(+), water_jet(+), sun_flare(+) and seed_bomb+ hit, push and reach
## differently on growth (and seed_bomb+ / grow_spike(+) / water_jet(+) now
## consume the tile at cost 1). grow_radius reads its radius key, and
## mycelium_dash+ plants the departure tile (op plant_origin). Every default
## pool holds a surged row, so any log that cast one on growth diverges.
const SIM_VERSION := 9

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
## Effective casts per base ability id (Content.base_id): a cast counts when
## at least one of its effects fired an outcome or a rider ran. Read by
## run_summary(); deliberately absent from snapshot() so the hash never sees it.
var effective_uses: Dictionary = {}
var draft_pool: Array = []
var packages: Array = []  # run-scoped tech packages (config "packages"); read-only metadata
var loadout := "tender"  # starting loadout id (config "loadout"); read-only metadata
var stoked := 0
var greened := 0  # corruption cleansed this floor
var green_need := 0  # dormant-stairs quota (clamped to generated corruption)  # pending extra smog ticks from live smokestacks
var _fixed_floor := {}  # config "fixed_floor": scripted floor-1 layout (tutorials, tests)

## Per-turn cast context counters (docs/PROGRESSION_REVIEW.md §6.3 C1): reset
## in _begin_player_turn, copied by clone(). Deliberately NOT part of
## snapshot() yet so state_hash() stays identical to the pre-grammar sim; a
## later block exposes them alongside a SIM_VERSION bump.
var casts_this_turn := 0
var moved_this_turn := 0
## Hook dispatcher state (C3). hook_uses: source id -> hook rows run this
## turn (per-turn caps); tithe_used_this_turn: the oil_cast_discount mod has
## been spent this turn. Both reset in _begin_player_turn, copied by clone(),
## NOT in snapshot(). The three underscore fields are per-step (reset in step).
var hook_uses := {}
var tithe_used_this_turn := false
var _hook_depth := 0
var _hook_runs := 0
var _hook_capped := false

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
	packages = config.get("packages", []).duplicate()
	# loadout (Content.LOADOUTS, Block A): an unknown id warns and plays as
	# tender; the profile enforces requires, the sim only reads the kit.
	loadout = String(config.get("loadout", "tender"))
	if not Content.LOADOUTS.has(loadout):
		push_warning("Game: unknown loadout id '%s' in config, playing tender" % loadout)
		loadout = "tender"
	for pkg in config.get("packages", []):
		for aid in Content.PACKAGES[pkg]:
			if not draft_pool.has(aid):
				draft_pool.append(aid)
	# open_pool mutator: every package ability joins the draft pool (before
	# pool_ban so a ban still applies to it).
	if bool(_mut("open_pool", false)):
		for pkg in Content.PACKAGES.keys():
			for aid in Content.PACKAGES[pkg]:
				if not draft_pool.has(aid):
					draft_pool.append(aid)
	# an explicit "kit" (sweeps, fixtures) wins over the loadout's kit
	var start_kit: Array = config.get("kit", Content.LOADOUTS[loadout]["kit"])
	player = {
		"pos": Vector2i.ZERO, "hp": Content.PLAYER_HP, "max_hp": Content.PLAYER_HP,
		"charge": 0, "bank": 0, "shield": 0,
		"kit": start_kit.duplicate(),
		"uses": {}, "grafts": [], "gummed": {}, "items": [],
		"thorns_dmg": 0, "thorns_turns": 0, "anchor_turns": 0,
	}
	# mutator config (Content.MUTATORS[m]["config"], read through _mut):
	# banned ids leave the pool (the shop stock follows it) and, with kit_ban,
	# the starting kit; max_hp_delta shifts the starting hp. None touch the rng.
	var banned: Array = _mut("pool_ban", [])
	if not banned.is_empty():
		var kept_pool: Array = []
		for aid in draft_pool:
			if not banned.has(Content.base_id(String(aid))):
				kept_pool.append(aid)
		draft_pool = kept_pool
		if bool(_mut("kit_ban", false)):
			var kept_kit: Array = []
			for aid in player["kit"]:
				if not banned.has(Content.base_id(String(aid))):
					kept_kit.append(aid)
			player["kit"] = kept_kit
	var hp_delta := int(_mut("max_hp_delta", 0))
	if hp_delta != 0:
		player["max_hp"] += hp_delta
		player["hp"] = player["max_hp"]
	# sweep hooks: pre-installed grafts (before floor entry so carapace
	# applies) and a starting bloom balance. Neither touches the main rng.
	for gid in config.get("grafts", []):
		if Content.GRAFTS.has(gid):
			if not player["grafts"].has(gid):
				player["grafts"].append(gid)
		else:
			push_warning("Game: unknown graft id '%s' in config, skipped" % str(gid))
	bloom = int(config.get("bloom", 0))
	_enter_floor(1)
	_begin_player_turn()


func _kit_max() -> int:
	return int(_mut("kit_max", Content.KIT_MAX))


## The one mutator read: scans the held mutators in order over
## Content.MUTATORS[m]["config"]. A scalar key returns the first hit, an array
## key concatenates every hit; `default` when no held mutator carries the key.
## Unknown mutator ids carry no config and are skipped.
func _mut(key: String, default):
	var arr: Array = []
	var any_arr := false
	for m in mutators:
		var cfg: Dictionary = Content.MUTATORS.get(m, {}).get("config", {})
		if not cfg.has(key):
			continue
		var v = cfg[key]
		if v is Array:
			any_arr = true
			arr.append_array(v)
		else:
			return v
	if any_arr:
		return arr
	return default


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
	var oil_mult := int(_mut("oil_mult", 1))
	if oil_mult != 1:
		fdef["oil"] = int(fdef["oil"]) * oil_mult
	var extra_common := int(_mut("extra_common_enemy", 0))
	if extra_common > 0 and not fdef.get("boss", false):
		var common := ""
		var common_n := 0
		for kind in fdef["enemies"]:
			if int(fdef["enemies"][kind]) > common_n:
				common_n = int(fdef["enemies"][kind])
				common = kind
		if common != "":
			fdef["enemies"][common] = common_n + extra_common
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


## Price of one shrine purchase. `id` names the specific offer and matters
## only for grafts: a graft is priced from its own Content.GRAFTS row
## ("price"), so a lever costs more than a stat row. Without an id the graft
## price falls back to the flat SHOP_COSTS entry, which is what callers that
## just want "the graft price" still get. Prices never touch the rng.
func shop_cost(item: String, id: String = "") -> int:
	var cost: int = Content.SHOP_COSTS.get(item, 9999)
	if item == "graft":
		if id != "" and Content.GRAFTS.has(id):
			cost = int(Content.GRAFTS[id].get("price", cost))
		# permanent power gets dearer the more of it you already own, so
		# "farm early, buy everything" is a real commitment, not a default
		cost += player["grafts"].size() * Content.GRAFT_PRICE_STEP
	for i in range(mini(tier, Content.TIERS.size())):
		cost += int(Content.TIERS[i].get("shop_markup", 0))
	return cost


## Price of every graft on offer, aligned with shop["grafts"]. One place for
## the sim, the snapshot and any consumer that needs the per-offer prices.
func graft_prices() -> Array:
	var out: Array = []
	for gid in shop.get("grafts", []):
		out.append(shop_cost("graft", String(gid)))
	return out


# --- public API ---------------------------------------------------------------

func step(action: Dictionary) -> Array:
	_step_events = []
	_hook_runs = 0
	_hook_capped = false
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
		"upcycle":
			_act_upcycle(action)
		"upcycle_ability":
			_act_upcycle_ability(action)
		"buy":
			_act_buy(action)
		"end_turn":
			_resolve_turn()
		_:
			_emit({"t": "error", "msg": "unknown action"})
	# one place covers every bloomless corruption removal (wash, convert,
	# dredge, enemy-made changes): the gate can never demand more than what
	# is still standing. Ignition is not one of them - a fire counts as the
	# ash it will leave, so lighting a slick never shrinks the gate
	if not over and phase == "play":
		_reclamp_quota()
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
			if Content.is_corruption(_terrain_kind(player["pos"] + d)):
				acts.append({"type": "cleanse", "target": player["pos"] + d})
	for slot in player["kit"].size():
		if player["gummed"].has(slot):
			continue
		var aid: String = player["kit"][slot]
		var flat := ability_cost(aid)
		# oil_cast_discount: each target is priced on its own while the
		# discount is still available this turn (a cheaper oil cast may be
		# legal on 1 charge when the flat price is not)
		var tithe: bool = _graft_mod("oil_cast_discount", 0) > 0 and not tithe_used_this_turn
		for tgt in _ability_targets(aid):
			var c: int = ability_cost(aid, tgt) if tithe else flat
			if player["charge"] >= c:
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
		if shop.has("grafts"):
			# each offer carries its own price, so a cheap stat graft can be
			# affordable on a purse the expensive lever is not
			for i in shop["grafts"].size():
				if bloom >= shop_cost("graft", String(shop["grafts"][i])):
					acts.append({"type": "buy", "item": "graft", "pick": i})
		if shop.has("item") and bloom >= shop_cost("item") and player["items"].size() < Content.ITEM_CAP:
			acts.append({"type": "buy", "item": "item"})
		if shop.get("press", false) and player["items"].size() == 2 and bloom >= shop_cost("press"):
			for k in 2:
				if not String(player["items"][k]).ends_with("+"):
					acts.append({"type": "upcycle", "keep": k})
		if shop.get("forge", false) and bloom >= shop_cost("forge") and player["kit"].size() >= 2:
			for i in player["kit"].size():
				var kid := String(player["kit"][i])
				if not kid.ends_with("+") and Content.ABILITIES.has(kid + "+"):
					for j in player["kit"].size():
						if j != i and not _is_mobility(String(player["kit"][j])):
							acts.append({"type": "upcycle_ability", "keep": i, "scrap": j})
	acts.append({"type": "end_turn"})
	return acts


## The one piece of ability metadata the sim reads: mobility abilities (and
## their + forms, which share the base's role) can never be scrapped by the
## forge.
func _is_mobility(aid: String) -> bool:
	return String(Content.ABILITIES.get(aid, {}).get("role", "")) == "mobility"


## The shop as a consumer sees it: the live stock plus "graft_prices", the
## per-offer prices aligned with "grafts". Prices are derived, never stored,
## so the shop dict the sim carries (and clone() copies) stays pure stock.
func _shop_snapshot() -> Dictionary:
	var out: Dictionary = shop.duplicate(true)
	if shop.has("grafts"):
		out["graft_prices"] = graft_prices()
	return out


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
		"pool": draft_pool.duplicate(), "packages": packages.duplicate(), "loadout": loadout,
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
		"shop": _shop_snapshot(),
		"terrain": terr,
		"events": recent_events.duplicate(true),
	}


## Stable identity of the STORED game state. Rule: derived snapshot keys never
## enter the hash - snapshot()["shop"] carries "graft_prices", which is
## recomputed per snapshot from the stock and the owned grafts, so the hash
## reads the raw stored shop dict instead. A hash that moved because a price
## table moved would report a state change that never happened.
func state_hash() -> String:
	var view := snapshot()
	view["shop"] = shop
	return str(view).sha256_text()


## Deep copy of the whole game, including RNG state. Enables search bots,
## forked what-if analysis, and save/load.
func clone():
	var g = get_script().new(seed_value, {"_blank": true})
	g.rng.state = rng.state
	g.tier = tier
	g.mutators = mutators.duplicate()
	g.effective_uses = effective_uses.duplicate()
	g.stoked = stoked
	g.greened = greened
	g.green_need = green_need
	g._fixed_floor = _fixed_floor.duplicate(true)
	g.draft_pool = draft_pool.duplicate()
	g.packages = packages.duplicate()
	g.loadout = loadout
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
	g.casts_this_turn = casts_this_turn
	g.moved_this_turn = moved_this_turn
	g.hook_uses = hook_uses.duplicate()
	g.tithe_used_this_turn = tithe_used_this_turn
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
	shop = _stock_shop() if bool(_mut("shop", true)) else {}
	var floor_shield := int(_graft_mod("floor_start_shield", 0))
	if floor_shield > 0:
		player["shield"] = mini(maxi(player["shield"], floor_shield), _shield_cap())
	_emit({"t": "floor", "floor": n, "name": fdef["name"]})
	_compute_intents()


## Deterministic side-stream: draws that are incidental to the core action
## economy (shop flavor, supply drops) come from a forked generator so they
## never shift the main rng stream - keeps cross-version seed comparability.
func _side_rng(tag: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, floor_num, tag])
	return r


## Shrine stock for the floor just entered. Every draw is a side-stream
## draw (one generator per slot so list sizes never couple), so the main rng
## after _enter_floor depends on map generation and the floor-entry intents
## alone - never on the kit, grafts, pool or bloom the run arrived with
## (tests/test_economy.gd asserts rng.state equality across configs).
func _stock_shop() -> Dictionary:
	if map["shrine"] == Vector2i(-1, -1):
		return {}
	var stock := {"heal": true, "press": true, "forge": true}
	var aids: Array = []
	for aid in draft_pool:
		# owning the + form excludes the base: never X and X+ in one kit
		if not player["kit"].has(aid) and not player["kit"].has(aid + "+"):
			aids.append(aid)
	if not aids.is_empty():
		var arng := _side_rng("shop_ability")
		stock["ability"] = aids[arng.randi_range(0, aids.size() - 1)]
	var gids: Array = []
	for gid in Content.GRAFTS:
		if not player["grafts"].has(gid):
			gids.append(gid)
	if not gids.is_empty():
		# two distinct offers from one generator: pick one, the other is discarded
		var grng := _side_rng("shop_graft")
		var picks: Array = []
		var gi := grng.randi_range(0, gids.size() - 1)
		picks.append(gids[gi])
		gids.remove_at(gi)
		if not gids.is_empty():
			gi = grng.randi_range(0, gids.size() - 1)
			picks.append(gids[gi])
		stock["grafts"] = picks
	var iids := _base_item_ids()
	var srng := _side_rng("shop_item")
	stock["item"] = iids[srng.randi_range(0, iids.size() - 1)]
	return stock


## Consumable ids the world hands out (shop, supply pods): base forms only.
## The + forms exist only through the shrine press.
func _base_item_ids() -> Array:
	var out: Array = []
	for iid in Content.ITEMS:
		if not String(iid).ends_with("+"):
			out.append(iid)
	return out


## The dormant-stairs quota can never demand more than what is still
## standing: greened plus the corruption left on the floor (fire included -
## it counts as the ash it burns to). Bloomless removals (wash, convert,
## dredge, enemy churn) lower it; neither igniting a slick nor the burnout
## that follows does, since the tile is corruption the whole way through.
func _reclamp_quota() -> void:
	var need: int = mini(green_need, greened + _count_corruption())
	if need < green_need:
		var was: int = green_need
		green_need = need
		# quota_reclamp: the gate shrank because corruption vanished without a cleanse
		_emit({"t": "quota_reclamp", "need": need, "was": was})
		if greened >= green_need:
			# stairs were dormant a moment ago and the shrunken quota is now met
			_emit({"t": "stairs_awaken", "tile": map["stairs"]})


func _begin_player_turn() -> void:
	# regen_on_growth is the conditional half of the regen key: it only pays
	# on the turns the tender begins standing on growth
	var regen: int = maxi(1, Content.BASE_REGEN - dim) + _graft_stat("regen")
	if _terrain_kind(player["pos"]) == "growth":
		regen += _graft_stat("regen_on_growth")
	player["charge"] = player["bank"] + regen
	player["bank"] = 0
	casts_this_turn = 0
	moved_this_turn = 0
	hook_uses = {}
	tithe_used_this_turn = false
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
	# assimilation: when the swarm is thick, adjacent fuse-capable machines
	# telegraph a WELD one full turn ahead. Kill or displace either partner
	# to break it (stagger clears the intent like any other wind-up).
	var fused_ids := {}
	if enemies.size() >= 3:
		for i in enemies.size():
			var a: Dictionary = enemies[i]
			if not Content.ENEMIES[a["kind"]]["traits"].has("fuses") or fused_ids.has(a["id"]):
				continue
			for j in range(i + 1, enemies.size()):
				var b: Dictionary = enemies[j]
				if not Content.ENEMIES[b["kind"]]["traits"].has("fuses") or fused_ids.has(b["id"]):
					continue
				if _manhattan(a["pos"], b["pos"]) == 1:
					a["intent"] = {"type": "fuse", "with": b["id"]}
					fused_ids[a["id"]] = true
					fused_ids[b["id"]] = true
					break
	for e in enemies:
		if fused_ids.has(e["id"]) and String(e["intent"].get("type", "")) == "fuse":
			continue
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


## Stack rule from Content.STATUSES: "max" keeps the longer duration, "add"
## sums (capped at `cap` when cap > 0). A row with `cooldown` is stagger-style:
## landing it writes "<status>_cd" = duration + cooldown, and while that field
## is above zero with the status itself expired the application is refused
## ({t: "resisted"}). Returns true when the status landed.
func _apply_status(e: Dictionary, status: String, turns: int) -> bool:
	if Content.ENEMIES[e["kind"]]["traits"].has("massive"):
		_emit({"t": "immune", "id": e["id"]})
		return false
	var sdef: Dictionary = Content.STATUSES.get(status, {})
	var have: int = int(e["status"].get(status, 0))
	var cooldown: int = int(sdef.get("cooldown", 0))
	var cd_key := status + "_cd"
	if cooldown > 0 and have <= 0 and int(e["status"].get(cd_key, 0)) > 0:
		_emit({"t": "resisted", "id": e["id"], "status": status})
		return false
	if String(sdef.get("stack", "max")) == "add":
		var total: int = have + turns
		var cap: int = int(sdef.get("cap", 0))
		e["status"][status] = mini(total, cap) if cap > 0 else total
	else:
		e["status"][status] = maxi(have, turns)
	if cooldown > 0:
		e["status"][cd_key] = maxi(int(e["status"].get(cd_key, 0)), int(e["status"][status]) + cooldown)
	_emit({"t": "status", "id": e["id"], "status": status, "turns": turns})
	return true


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
	_hook("staggered", {"enemy": e})


func _execute_intent(e: Dictionary) -> void:
	if int(e["status"].get("stagger_cd", 0)) > 0:
		e["status"]["stagger_cd"] -= 1
	# status cooldowns (Content.STATUSES cooldown) run down once per action
	for sname in Content.STATUSES:
		if int(Content.STATUSES[sname].get("cooldown", 0)) > 0 and int(e["status"].get(sname + "_cd", 0)) > 0:
			e["status"][sname + "_cd"] -= 1
	var it: Dictionary = e["intent"]
	# Content.STATUSES blocks, in table order: the first status that swallows
	# this intent ticks down and ends the enemy's turn
	var itype := String(it.get("type", ""))
	for sname in Content.STATUSES:
		if int(e["status"].get(sname, 0)) <= 0:
			continue
		var blocks: Array = Content.STATUSES[sname].get("blocks", [])
		if blocks.has("*") or blocks.has(itype):
			e["status"][sname] -= 1
			_emit({"t": String(Content.STATUSES[sname].get("blocked_event", sname)), "id": e["id"]})
			return
	match String(it.get("type", "idle")):
		"fuse":
			var partner = null
			for o in enemies:
				if o["id"] == it.get("with", -1):
					partner = o
			if partner != null and _manhattan(e["pos"], partner["pos"]) == 1:
				enemies.erase(partner)
				e["kind"] = "welded_hulk"
				e["hp"] = mini(e["hp"] + partner["hp"], int(Content.ENEMIES["welded_hulk"]["hp"]))
				e["status"] = {}
				_emit({"t": "assimilate", "id": e["id"], "eaten": partner["id"]})
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
					# enemy-made oil: cleansing it counts for the quota but pays no bloom
					terrain[p] = {"kind": "oil", "bloom": 0}
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
				if Content.terrain(String(terrain[t]["kind"]), "flammable", false):
					_ignite(t, e["kind"])
					_hook("ignite", {"tile": t, "by": e["kind"]})
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
						terrain[p] = {"kind": "oil", "bloom": 0}
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
						terrain[old] = {"kind": "oil", "bloom": 0}
				e["pos"] = dest
				_enemy_enter_tile(e)
		"idle":
			pass


func _environment_phase() -> void:
	# hazard tick: every tile whose kind burns whoever stands on it
	# (Content.TERRAIN tick_dmg_*; fire today), captured first in map order
	var hazards: Array = []
	for t in terrain.keys():
		var k := String(terrain[t]["kind"])
		if int(Content.terrain(k, "tick_dmg_player", 0)) > 0 or int(Content.terrain(k, "tick_dmg_enemy", 0)) > 0:
			hazards.append(t)
	for t in hazards:
		var k := _terrain_kind(t)
		var pdmg := int(Content.terrain(k, "tick_dmg_player", 0))
		if pdmg > 0 and player["pos"] == t:
			_damage_player(pdmg, k)
			if over:
				return
		var edmg := int(Content.terrain(k, "tick_dmg_enemy", 0))
		var e = _enemy_at(t)
		if edmg > 0 and e != null:
			_damage_enemy(e, edmg, k + ":" + _fire_by(t))
	_terrain_react()
	# status ticks (Content.STATUSES tick_dmg): the status itself is the source
	for e in enemies.duplicate():
		for sname in Content.STATUSES:
			var tick := int(Content.STATUSES[sname].get("tick_dmg", 0))
			if tick > 0 and int(e["status"].get(sname, 0)) > 0:
				e["status"][sname] -= 1
				_damage_enemy(e, tick, sname)
	var heal := int(Content.terrain(_terrain_kind(player["pos"]), "heal", 0))
	if heal > 0 and player["hp"] < player["max_hp"]:
		var heal_amt: int = heal + _graft_stat("growth_heal")
		player["hp"] = mini(player["hp"] + heal_amt, player["max_hp"])
		_emit({"t": "heal", "amt": heal_amt})


## Terrain reactions (Content.REACTIONS), one pass per environment phase:
## 1) "adjacent" rows are evaluated from every enabled `from` tile in map
##    order, before any ttl decay; the first source tile to reach a target
##    signs it ("by"), and no target is claimed twice;
## 2) every decaying kind (Content.TERRAIN decays) loses one ttl in map order
##    and an expiring tile becomes its "on_expire" result, or vanishes;
## 3) the adjacency results are written ({kind, ttl, by}) and each emits the
##    row's event.
## Spreads are computed from the fires standing before decay and applied
## after it. Every new tile goes through _tile_dict, so the replaced tile's
## "bloom" flag survives: enemy-made oil (bloom 0) burns into bloom-0 fire and
## bloom-0 ash, and its cleanse still pays nothing.
func _terrain_react() -> void:
	var adj_rows: Array = []
	var expire := {}
	for row in Content.REACTIONS:
		if not bool(row.get("enabled", false)):
			continue
		if row.has("adjacent"):
			adj_rows.append(row)
		elif row.has("on_expire"):
			expire[String(row["from"])] = row
	var pending := {}
	if not adj_rows.is_empty():
		for t in terrain.keys():
			var k := String(terrain[t]["kind"])
			for row in adj_rows:
				if String(row["from"]) != k:
					continue
				for d in DIRS:
					var p: Vector2i = t + d
					if _terrain_kind(p) == String(row["adjacent"]) and not pending.has(p):
						pending[p] = {"row": row, "by": _fire_by(t)}
	for t in terrain.keys().duplicate():
		var k := String(terrain[t]["kind"])
		if not bool(Content.terrain(k, "decays", false)):
			continue
		terrain[t]["ttl"] = int(terrain[t].get("ttl", 0)) - 1
		if terrain[t]["ttl"] <= 0:
			var erow: Dictionary = expire.get(k, {})
			var result := String(erow.get("result", ""))
			if result == "":
				terrain.erase(t)
			else:
				# attribution follows hazards: a decaying result keeps "by"
				var by := String(terrain[t].get("by", "")) if bool(Content.terrain(result, "decays", false)) else ""
				terrain[t] = _tile_dict(result, by, terrain[t])
				var eev := String(erow.get("event", ""))
				if eev != "":
					_emit({"t": eev, "tile": t})
	for p in pending:
		var row: Dictionary = pending[p]["row"]
		var result := String(row.get("result", ""))
		if result == "":
			terrain.erase(p)
		else:
			terrain[p] = _tile_dict(result, String(pending[p]["by"]), terrain.get(p, {}))
		var ev := String(row.get("event", ""))
		if ev != "":
			_emit({"t": ev, "tile": p})
			# a reaction whose event is a hook kind fires it (fire spread -> ignite)
			if Content.HOOK_KINDS.has(ev):
				_hook(ev, {"tile": p, "by": String(pending[p]["by"])})


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
	moved_this_turn += 1
	_emit({"t": "move", "who": "player", "to": dest})
	_player_enter_tile()


## Spiked chassis: melee strikes hurt the attacker back. Coal golems carry
## it inherently; every elite is retrofitted - elites are the "bring a tool"
## moments, not bigger punching bags.
func _spiked(e: Dictionary) -> bool:
	return Content.ENEMIES[e["kind"]]["traits"].has("spiked") or e.get("elite", false)


func _act_strike(action: Dictionary) -> void:
	var dir: Vector2i = action.get("dir", Vector2i.ZERO)
	var e = _enemy_at(player["pos"] + dir)
	if e == null or player["charge"] < Content.STRIKE_COST:
		_emit({"t": "illegal", "action": "strike"})
		return
	player["charge"] -= Content.STRIKE_COST
	_emit({"t": "strike", "id": e["id"]})
	var spiked := _spiked(e)
	_damage_enemy(e, Content.STRIKE_DMG, "strike")
	if spiked and not over:
		_damage_player(1, "spikes")


func _act_cleanse(action: Dictionary) -> void:
	var target: Vector2i = action.get("target", Vector2i(-1, -1))
	var k := _terrain_kind(target)
	var legal := _manhattan(target, player["pos"]) == 1 and Content.is_corruption(k)
	if not legal or player["charge"] < Content.CLEANSE_COST:
		_emit({"t": "illegal", "action": "cleanse"})
		return
	player["charge"] -= Content.CLEANSE_COST
	# tending leaves life behind: the cleansed tile sprouts growth. Mapgen
	# corruption pays 1 (rich goo more); enemy-made oil carries bloom 0 and
	# pays nothing (surge included) - it still counts toward the quota.
	var yield_: int = int(terrain[target].get("bloom", Content.terrain(k, "bloom", 1)))
	terrain[target] = {"kind": "growth"}
	if yield_ > 0:
		bloom += yield_ + _graft_stat("cleanse_bloom")
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
	_emit({"t": "cleanse", "tile": target, "kind": k, "bloom": bloom})
	_hook("cleanse", {"tile": target, "kind": k})
	_hook("growth_planted", {"tiles": [target]})
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
	draft_offers = _draw_draft_offers(int(_mut("draft_offers", 3)))
	if draft_offers.is_empty():
		_enter_floor(_pending_floor)
		_begin_player_turn()
	else:
		phase = "draft"
		_emit({"t": "draft_offer", "offers": draft_offers.duplicate()})


func _draw_draft_offers(count: int) -> Array:
	var candidates: Array = []
	if not bool(_mut("draft_upgrades_only", false)):
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
		"sun_capsule+":
			player["charge"] += 6
		"balm_fruit":
			player["hp"] = mini(player["hp"] + 4, player["max_hp"])
		"balm_fruit+":
			player["hp"] = player["max_hp"]
		"spore_vial":
			# through _apply_status like any cast: massive (every boss) is immune
			for e in enemies.duplicate():
				if _manhattan(e["pos"], player["pos"]) <= 2:
					_apply_status(e, "stun", 1)
		"spore_vial+":
			for e in enemies.duplicate():
				if _manhattan(e["pos"], player["pos"]) <= 4:
					_apply_status(e, "stun", 2)
		"clearair_pod":
			smog = maxi(smog - 5, 0)
		"clearair_pod+":
			smog = maxi(smog - 12, 0)
		"iron_seed":
			player["shield"] = mini(player["shield"] + 3, _shield_cap())
		"iron_seed+":
			player["max_hp"] += 1
			player["hp"] += 1
			player["shield"] = mini(player["shield"] + 3, _shield_cap())
	_emit({"t": "item_use", "id": iid})


## Shrine press: two held consumables become the + form of the kept one.
## A shrine service like any purchase: priced through shop_cost (tier markup
## applies) and gated on shop.press, so a Boarded shrine boards it too.
func _act_upcycle(action: Dictionary) -> void:
	var keep := int(action.get("keep", -1))
	var on_shrine: bool = player["pos"] == map["shrine"]
	var cost := shop_cost("press")
	if not on_shrine or not shop.get("press", false) or player["items"].size() != 2 or keep < 0 or keep > 1 \
			or bloom < cost or String(player["items"][keep]).ends_with("+"):
		_emit({"t": "illegal", "action": "upcycle"})
		return
	bloom -= cost
	var plus := String(player["items"][keep]) + "+"
	player["items"] = [plus]
	_emit({"t": "upcycle", "id": plus})


## Shrine forge: one kit ability becomes its + form; another is scrapped.
## Once per floor (the use erases shop.forge), never scraps a mobility ability.
func _act_upcycle_ability(action: Dictionary) -> void:
	var keep := int(action.get("keep", -1))
	var scrap := int(action.get("scrap", -1))
	var kmax: int = player["kit"].size()
	var cost := shop_cost("forge")
	var ok: bool = player["pos"] == map["shrine"] and shop.get("forge", false) and bloom >= cost \
		and keep >= 0 and keep < kmax and scrap >= 0 and scrap < kmax and keep != scrap
	if ok:
		var kid := String(player["kit"][keep])
		ok = not kid.ends_with("+") and Content.ABILITIES.has(kid + "+") \
			and not _is_mobility(String(player["kit"][scrap]))
	if not ok:
		_emit({"t": "illegal", "action": "upcycle_ability"})
		return
	bloom -= cost
	shop.erase("forge")
	var kid2 := String(player["kit"][keep])
	_emit({"t": "upcycle_scrap", "id": player["kit"][scrap]})
	player["kit"][keep] = kid2 + "+"
	player["uses"][kid2 + "+"] = int(player["uses"].get(kid2, 0))
	player["kit"].remove_at(scrap)
	# gummed is keyed by slot: drop the scrapped slot, shift the ones above
	var ng := {}
	for k in player["gummed"]:
		var ki := int(k)
		if ki == scrap:
			continue
		ng[ki - 1 if ki > scrap else ki] = player["gummed"][k]
	player["gummed"] = ng
	_emit({"t": "upcycle_ability", "id": kid2 + "+"})


func _room_of(p: Vector2i) -> int:
	var rooms: Array = map.get("rooms", [])
	for i in rooms.size():
		if rooms[i].has_point(p):
			return i
	return -1


## Corruption for counting: the two sites that feed the quota clamp, the
## floor-restore check and the room bloom read Content.counts_as_corruption,
## so a burning oil slick still counts as the corruption it will become.
func _count_corruption() -> int:
	var cnt := 0
	for t in terrain.keys():
		if Content.counts_as_corruption(String(terrain[t]["kind"])):
			cnt += 1
	return cnt


func _room_has_corruption(ri: int) -> bool:
	var r: Rect2i = map["rooms"][ri]
	for t in terrain.keys():
		if r.has_point(t) and Content.counts_as_corruption(String(terrain[t]["kind"])):
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
		var ids := _base_item_ids()
		terrain[t2] = {"kind": "supply", "item": ids[srng.randi_range(0, ids.size() - 1)]}
	_emit({"t": "room_bloom", "room": ri, "bonus": Content.ROOM_BLOOM_BONUS})


func _act_buy(action: Dictionary) -> void:
	var item := String(action.get("item", ""))
	# a graft is priced per offer, so the pick has to be resolved before the
	# price is known; an out-of-range pick keeps the id-less fallback price
	# and is rejected by the graft branch below
	var gid_pick := ""
	if item == "graft":
		var offers0: Array = shop.get("grafts", [])
		var pick0 := int(action.get("pick", -1))
		if pick0 >= 0 and pick0 < offers0.size():
			gid_pick = String(offers0[pick0])
	var cost: int = shop_cost(item, gid_pick)
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
			# a full kit cannot buy: the ability card is simply not for sale
			if not shop.has("ability") or player["kit"].size() >= _kit_max():
				_emit({"t": "illegal", "action": "buy"})
				return
			bloom -= cost
			var aid: String = shop["ability"]
			shop.erase("ability")
			player["kit"].append(aid)
			_emit({"t": "buy", "item": "ability", "id": aid})
		"graft":
			var pick := int(action.get("pick", -1))
			if not shop.has("grafts") or pick < 0 or pick >= shop["grafts"].size():
				_emit({"t": "illegal", "action": "buy"})
				return
			bloom -= cost
			var offers: Array = shop["grafts"]
			var gid: String = offers[pick]
			var other := ""
			for g in offers:
				if g != gid:
					other = g
			# one pick closes the graft counter: the other offer is discarded
			shop.erase("grafts")
			player["grafts"].append(gid)
			# buy/graft with "discarded": the offer left behind ("" when there was one offer)
			_emit({"t": "buy", "item": "graft", "id": gid, "discarded": other})
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


## Sum of `key` over the "stat" dicts of every held graft (Content.GRAFTS).
## Keys: bank_cap, shield_cap, regen, regen_on_growth, growth_heal,
## cleanse_bloom (the closed set tests/test_content.gd lints).
func _graft_stat(key: String) -> int:
	var v := 0
	for gid in player["grafts"]:
		v += int(Content.GRAFTS[gid].get("stat", {}).get(key, 0))
	return v


## The first held graft's "mod" value for `key` (held order), else `default`.
func _graft_mod(key: String, default):
	for gid in player["grafts"]:
		var mod: Dictionary = Content.GRAFTS[gid].get("mod", {})
		if mod.has(key):
			return mod[key]
	return default


func _bank_cap() -> int:
	var cap := int(_mut("bank_cap", -1))
	if cap >= 0:
		return cap
	return Content.BANK_CAP + _graft_stat("bank_cap")


func _shield_cap() -> int:
	return Content.SHIELD_CAP + _graft_stat("shield_cap")


func _act_ability(action: Dictionary) -> void:
	var slot: int = action.get("slot", -1)
	if slot < 0 or slot >= player["kit"].size() or player["gummed"].has(slot):
		_emit({"t": "illegal", "action": "ability"})
		return
	var aid: String = player["kit"][slot]
	var adef: Dictionary = Content.ABILITIES[aid]
	var target = action.get("target")
	var surge_cost := ability_cost(aid)
	var cost := ability_cost(aid, target)
	if player["charge"] < cost or not _ability_targets(aid).has(target):
		_emit({"t": "illegal", "action": "ability", "id": aid})
		return
	# verdant surge (one rule, _surges): standing on growth with a surge dict
	# that applies draws the tile up into the cast - the cost delta is already
	# in surge_cost, the stat deltas ride ctx["surge"] into every effect
	var surge_stats := {}
	if _surges(adef):
		terrain.erase(player["pos"])
		_emit({"t": "verdant", "tile": player["pos"]})
		surge_stats = _surge_stats(_surge_of(adef))
	if cost < surge_cost:
		# oil_cast_discount (oil_tithe): spent on the first oil-aimed cast of the turn
		tithe_used_this_turn = true
		_emit({"t": "tithe", "id": aid})
	player["charge"] -= cost
	player["uses"][aid] = int(player["uses"].get(aid, 0)) + 1
	# cast context: what the riders (if / per / bonus / then) may read
	var ctx := {
		"aid": aid, "adef": adef, "target": target, "origin": player["pos"],
		"casts_before": casts_this_turn, "moved": moved_this_turn,
	}
	casts_this_turn += 1
	_emit({"t": "ability", "id": aid, "target": target})
	if not surge_stats.is_empty():
		var keys := _surge_applied_keys(adef, surge_stats)
		if not keys.is_empty():
			ctx["surge"] = surge_stats
			_emit({"t": "surge", "id": aid, "keys": keys})
	var ev_mark := _step_events.size()
	var fired := false
	for eff in adef["effects"]:
		if _outcome_fired(_apply_effect(eff, adef, target, aid, ctx)):
			fired = true
	if not fired:
		# a rider (per / then) that ran also makes the cast count
		for i in range(ev_mark, _step_events.size()):
			if String(_step_events[i].get("t", "")) == "rider":
				fired = true
				break
	if fired:
		var base := Content.base_id(aid)
		effective_uses[base] = int(effective_uses.get(base, 0)) + 1


## Compact end-of-run record for the meta layer and the runners: what was
## held, what was cast (raw and effective, folded onto base ids) and how the
## run ended. Pure read; the sim never consumes it. player.uses keeps both
## keys when an ability is upgraded (the + key is seeded with the base's
## count at upgrade time), so per base the larger count is the true total.
func run_summary() -> Dictionary:
	var uses_by_base := {}
	for aid in player["uses"]:
		var b := Content.base_id(String(aid))
		uses_by_base[b] = maxi(int(uses_by_base.get(b, 0)), int(player["uses"][aid]))
	return {
		"won": won, "floor": floor_num, "turns": total_turns,
		"kit": player["kit"].duplicate(), "grafts": player["grafts"].duplicate(),
		"uses_by_base": uses_by_base, "effective_uses_by_base": effective_uses.duplicate(),
		"bloom": bloom, "death_cause": death_cause, "seed": seed_value, "tier": tier,
		"mutators": mutators.duplicate(), "packages": packages.duplicate(), "loadout": loadout,
	}


## Live cost of an ability right now: standing on growth applies the cost
## delta of the ability's surge rule (Content.SURGE_DEFAULT unless the row
## carries its own "surge") to a cost-2+ cast: maxi(1, base + surge.cost).
## Whether the cast surges at all (and so consumes the tile) is _surges; the
## stat half of a surge never moves the price. With a `target`, a held
## oil_cast_discount graft mod (oil_tithe) that is unspent this turn takes its
## discount off an oil-aimed cast, floored at 1: the resolved target tile is
## oil, or for "dir" abilities the line holds oil within range. Without a
## target the discount is never applied.
func ability_cost(aid: String, target = null) -> int:
	var adef: Dictionary = Content.ABILITIES[aid]
	var base: int = int(adef["cost"])
	var cost := base
	if base >= 2 and _terrain_kind(player["pos"]) == "growth":
		cost = maxi(1, base + _surge_cost_delta(adef))
	if target != null and cost > 1 and not tithe_used_this_turn:
		var discount := int(_graft_mod("oil_cast_discount", 0))
		if discount > 0 and _targets_oil(adef, target):
			cost = maxi(1, cost - discount)
	return cost


## The surge dict of an ability row: its "surge" key, else Content.SURGE_DEFAULT.
func _surge_of(adef: Dictionary) -> Dictionary:
	return adef.get("surge", Content.SURGE_DEFAULT)


## The cost half of a surge dict, the one number ability_cost and _surges both
## read: an explicit dict without a "cost" key is a stat-only surge and moves
## no price (sun_flare spells its discount out as {cost: -1, radius: 1}); the
## default {cost: -1} applies only to a row with no dict at all.
func _surge_cost_delta(adef: Dictionary) -> int:
	return int(_surge_of(adef).get("cost", 0))


## The stat half of a surge dict: every key but "cost", each an int delta that
## _apply_effect adds to the matching key of every effect of the cast.
func _surge_stats(surge: Dictionary) -> Dictionary:
	var stats := {}
	for k in surge:
		if String(k) != "cost":
			stats[String(k)] = int(surge[k])
	return stats


## The one surge rule (Block D1): a cast of `adef` SURGES when the tender
## stands on growth and the surge dict carries anything that applies to it -
## a cost delta that lowers a cost >= 2 (maxi(1, base + cost) < base), or any
## stat key. A surged cast consumes the growth tile (event verdant). A cost-1
## ability with only the default {cost: -1} therefore never surges and never
## consumes growth; one with a stat surge does, and gets the stat.
func _surges(adef: Dictionary) -> bool:
	if _terrain_kind(player["pos"]) != "growth":
		return false
	var base := int(adef["cost"])
	if base >= 2 and maxi(1, base + _surge_cost_delta(adef)) < base:
		return true
	return not _surge_stats(_surge_of(adef)).is_empty()


## The surge stat keys that touch at least one effect of the row (top level or
## inside a then): what the {t: "surge"} event reports. The content lint
## requires every stat key to touch something, so for a shipped row this is
## every stat key in row order.
func _surge_applied_keys(adef: Dictionary, stats: Dictionary) -> Array:
	var keys: Array = []
	for k in stats:
		var found := false
		for eff in adef["effects"]:
			if eff.has(k):
				found = true
			for sub in eff.get("then", []):
				if sub.has(k):
					found = true
		if found:
			keys.append(k)
	return keys


## Whether a cast of `adef` at `target` is aimed at oil: "dir" abilities when
## the line holds oil within range (walls stop the walk, Game._rider_per
## oil_in_line), every other target shape when the target tile itself is oil.
func _targets_oil(adef: Dictionary, target) -> bool:
	if not (target is Vector2i):
		return false
	if String(adef.get("target", "")) == "dir":
		var ctx := {"adef": adef, "target": target, "origin": player["pos"]}
		return _rider_per({"count": "oil_in_line"}, ctx) > 0
	return _terrain_kind(target) == "oil"


## Public read-only view of the legal target list for an ability the player
## could cast from the current position. Pure query: no state or rng change.
func ability_targets(aid: String) -> Array:
	return _ability_targets(aid)


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


## `aid` is the casting ability: every damage, ignition and collision the
## effect causes is attributed to it (events, autopsy, death tables).
##
## Effect grammar (docs/PROGRESSION_REVIEW.md §6.3 C1). Any effect dict may
## carry three optional rider keys, evaluated by _rider_if / _rider_per only:
##   "if":    Array of predicate dicts, every key of every dict must hold;
##            a failed `if` skips the effect (zero outcome, no event)
##   "per":   {count, radius?, cap, add: {key: n}} - before the op runs, each
##            add key grows by add[k] * min(count, cap) on a copy of the effect
##   "bonus": {dmg, if: [...]} - per affected enemy inside aoe_damage, lance,
##            damage and collision damage; its predicates read the enemy's tile
##   "then":  Array of effects run once, in order, after the parent when the
##            parent outcome has any counter > 0 or a non-empty crossed list;
##            they share the parent's target and see its outcome through
##            `outcome` / `outcome_crossed` predicates (ctx["parent"]). A then
##            inside a then is rejected: error event, zero outcome. The
##            {t: rider, kind: then} event fires once per then-effect whose
##            own outcome fired, never for one that found nothing to do.
## On `pull` the bonus rides the lash hit (pull has no collision damage) and
## its predicates read the enemy's landing tile.
## Surge stats (Block D1): when ctx carries "surge" ({key: delta}, the stat
## half of the row's surge dict, set by _act_ability only on a surged cast),
## every delta is added to the matching key of this effect on a copy, before
## `per` grows it and before the op runs; then-effects get the same treatment
## through the ctx they inherit. An effect without the key is untouched.
## `ctx` is the cast context built by _act_ability: {aid, adef, target, origin,
## casts_before, moved} plus "surge" on a stat-surged cast and "parent" (the
## parent outcome) inside a then.
## Returns the outcome: int counters hit / ignited / pushed / collided /
## converted / planted / washed / statused, `affected` (ids of enemies the op damaged,
## displaced or statused), `crossed` (terrain kinds any displaced enemy
## stepped onto) and `tiles` (tiles the op planted or converted, read by
## status_target who = "on_planted").
func _apply_effect(eff: Dictionary, adef: Dictionary, target, aid: String, ctx: Dictionary = {}) -> Dictionary:
	var out := _zero_outcome()
	var parent = ctx.get("parent", null)
	if parent != null and eff.has("then"):
		_emit({"t": "error", "msg": "nested then in %s" % aid})
		return out
	if eff.has("if") and not _rider_if(eff["if"], ctx, parent, null):
		return out
	var surge_stats: Dictionary = ctx.get("surge", {})
	if not surge_stats.is_empty():
		var surged := eff.duplicate()
		var touched := false
		for k in surge_stats:
			if eff.has(k):
				surged[k] = int(eff[k]) + int(surge_stats[k])
				touched = true
		if touched:
			eff = surged
	if eff.has("per"):
		var per: Dictionary = eff["per"]
		var n := _rider_per(per, ctx)
		var cap := int(per.get("cap", 0))
		if cap > 0:
			n = mini(n, cap)
		if n > 0:
			var added := 0
			var grown := eff.duplicate()
			for k in per.get("add", {}):
				var delta: int = int(per["add"][k]) * n
				grown[k] = int(eff.get(k, 0)) + delta
				added += delta
			if added != 0:
				eff = grown
				# rider/per: the scaled add (amt = total added)
				_emit({"t": "rider", "id": aid, "kind": "per", "amt": added})
	match String(eff["op"]):
		"lance":
			var dmg: int = eff["dmg"] + (int(eff["clear_smog_bonus"]) if dim == 0 else 0)
			var p: Vector2i = player["pos"]
			for i in range(int(adef["range"])):
				p += target
				var k := _terrain_kind(p)
				if _tile(p) == MapGen.T_WALL or bool(Content.terrain(k, "blocks_beam", false)):
					break
				if bool(Content.terrain(k, "flammable", false)) and bool(eff["ignite"]):
					_ignite(p, aid)
					_emit({"t": "ignite", "tile": p})
					out["ignited"] += 1
					_hook("ignite", {"tile": p, "by": aid})
				var e = _enemy_at(p)
				if e != null:
					if _damage_enemy(e, dmg + _bonus_dmg(eff, ctx, e), aid):
						out["hit"] += 1
					_affect(out, e)
					break
		"grow_radius":
			# every floor tile within manhattan eff.radius of the target: 1 is
			# the plus, 2 the 13-tile diamond a surged seed_bomb+ reaches. The
			# plus keeps its pre-D1 order (target, then DIRS) because terrain
			# insertion order is observable - terrain.keys() feeds the growth
			# target list and the state hash - so a radius-1 cast stays
			# byte-identical; the outer rings follow dy then dx ascending.
			# The plus is always drawn, so radius is honoured from 1 up -
			# tests/test_content.gd rejects a grow_radius row below 1
			var gr := int(eff["radius"])
			var tiles_: Array = [target]
			for d in DIRS:
				tiles_.append(target + d)
			for dy in range(-gr, gr + 1):
				for dx in range(-gr, gr + 1):
					var md := absi(dx) + absi(dy)
					if md < 2 or md > gr:
						continue
					tiles_.append(target + Vector2i(dx, dy))
			for t in tiles_:
				if _tile(t) == MapGen.T_FLOOR and not terrain.has(t):
					terrain[t] = {"kind": "growth"}
					out["planted"] += 1
					out["tiles"].append(t)
			_emit({"t": "growth", "tile": target})
			if not out["tiles"].is_empty():
				_hook("growth_planted", {"tiles": out["tiles"].duplicate()})
		"pull":
			var e = _enemy_at(target)
			if e == null:
				return out
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
					_cross(out["crossed"], nxt)
					_enemy_enter_tile(e)
					if not enemies.has(e):
						out["pushed"] += 1
						_affect(out, e)
						return out
				if pulled > 0:
					out["pushed"] += 1
					_stagger(e)
			if _damage_enemy(e, int(eff["dmg"]) + _bonus_dmg(eff, ctx, e), aid):
				out["hit"] += 1
			_affect(out, e)
		"wash_push":
			_merge_wash(out, _wash_dir(target, int(adef["range"]), int(eff["push"]), int(eff["collision_dmg"]), aid, eff, ctx))
		"wash_all":
			for d in DIRS:
				_merge_wash(out, _wash_dir(d, int(adef["range"]), int(eff["push"]), int(eff["collision_dmg"]), aid, eff, ctx))
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
					_merge_push(out, _push_enemy(e, target, int(eff["dist"]), 1, aid, eff, ctx))
					break
		"push_all":
			for d in DIRS:
				var e = _enemy_at(player["pos"] + d)
				if e != null:
					_merge_push(out, _push_enemy(e, d, int(eff["dist"]), 1, aid, eff, ctx))
		"dash_dir":
			for i in range(int(adef["range"])):
				var nxt: Vector2i = player["pos"] + target
				if not _open(nxt):
					break
				player["pos"] = nxt
				moved_this_turn += 1
				_player_enter_tile()
				if over:
					return out
			_emit({"t": "dash", "to": player["pos"]})
		"create_terrain":
			if _tile(target) == MapGen.T_FLOOR and not terrain.has(target):
				terrain[target] = {"kind": String(eff["kind"]), "ttl": int(eff["ttl"])}
				if String(eff["kind"]) == "fire":
					terrain[target]["by"] = aid
				out["planted"] += 1
				out["tiles"].append(target)
				_emit({"t": "terrain", "kind": eff["kind"], "tile": target})
				if String(eff["kind"]) == "fire":
					_hook("ignite", {"tile": target, "by": aid})
		"clear_smoke":
			for t in terrain.keys().duplicate():
				if terrain[t]["kind"] == "smoke" and _manhattan(t, player["pos"]) <= int(eff["radius"]):
					terrain.erase(t)
					_emit({"t": "smoke_cleared", "tile": t})
		"teleport":
			if target != player["pos"]:
				moved_this_turn += 1
			player["pos"] = target
			_emit({"t": "teleport", "to": target})
		"plant_origin":
			# Spore Trail (Block D1): write eff.kind on the tile the cast left
			# from (ctx.origin) once the tender is gone - floor, no terrain, no
			# enemy standing there. Counts as planted so on_planted riders,
			# the growth_planted hook and effective_uses all see it.
			var o = ctx.get("origin", null)
			var kind := String(eff["kind"])
			if o is Vector2i and o != player["pos"] and _tile(o) == MapGen.T_FLOOR \
					and not terrain.has(o) and _enemy_at(o) == null:
				terrain[o] = _tile_dict(kind, aid if kind == "fire" else "", {})
				out["planted"] += 1
				out["tiles"].append(o)
				_emit({"t": "terrain", "kind": kind, "tile": o})
				if kind == "growth":
					_hook("growth_planted", {"tiles": [o]})
				elif kind == "fire":
					_hook("ignite", {"tile": o, "by": aid})
		"grow_wall":
			var walled: Array = [target]
			for d in DIRS:
				walled.append(target + d)
			for t in walled:
				if _tile(t) == MapGen.T_FLOOR and not terrain.has(t) and _open(t) and t != map["stairs"]:
					terrain[t] = {"kind": "roots", "ttl": int(eff["ttl"])}
					out["planted"] += 1
					out["tiles"].append(t)
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
					if _apply_status(e, String(eff["status"]), int(eff["turns"])):
						out["statused"] += 1
						_affect(out, e)
		"aoe_damage":
			for t in terrain.keys().duplicate():
				if bool(eff.get("ignite", false)) and bool(Content.terrain(String(terrain[t]["kind"]), "flammable", false)) \
						and _manhattan(t, player["pos"]) <= int(eff["radius"]):
					_ignite(t, aid)
					_emit({"t": "ignite", "tile": t})
					out["ignited"] += 1
					_hook("ignite", {"tile": t, "by": aid})
			for e in enemies.duplicate():
				if _manhattan(e["pos"], player["pos"]) <= int(eff["radius"]):
					if _damage_enemy(e, int(eff["dmg"]) + _bonus_dmg(eff, ctx, e), aid):
						out["hit"] += 1
					_affect(out, e)
		"convert_radius":
			for dy in range(-int(eff["radius"]), int(eff["radius"]) + 1):
				for dx in range(-int(eff["radius"]), int(eff["radius"]) + 1):
					if absi(dx) + absi(dy) > int(eff["radius"]):
						continue
					var t: Vector2i = target + Vector2i(dx, dy)
					var k := _terrain_kind(t)
					if bool(Content.terrain(k, "convertible", false)):
						terrain[t] = {"kind": "growth"}
						out["converted"] += 1
						out["tiles"].append(t)
						_emit({"t": "convert", "tile": t})
		"apply_status":
			var e = _enemy_at(target)
			if e != null:
				if _apply_status(e, String(eff["status"]), int(eff["turns"])):
					out["statused"] += 1
					_affect(out, e)
		"damage":
			var e = _enemy_at(target)
			if e != null:
				if _damage_enemy(e, int(eff["dmg"]) + _bonus_dmg(eff, ctx, e), aid):
					out["hit"] += 1
				_affect(out, e)
		"status_target":
			# then-only op: status the parent's affected enemies ("affected",
			# default) or whoever stands on a tile the parent planted ("on_planted")
			var par: Dictionary = parent if parent != null else _zero_outcome()
			var ids: Array = []
			if String(eff.get("who", "affected")) == "on_planted":
				for t in par["tiles"]:
					var e = _enemy_at(t)
					if e != null:
						ids.append(e["id"])
			else:
				ids = par["affected"].duplicate()
			for id in ids:
				var e = _enemy_by_id(int(id))
				if e != null and _apply_status(e, String(eff["status"]), int(eff["turns"])):
					out["statused"] += 1
					_affect(out, e)
		_:
			_emit({"t": "error", "msg": "unknown effect op %s" % String(eff["op"])})
	if eff.has("then") and _outcome_fired(out):
		for sub in eff["then"]:
			var c2 := ctx.duplicate()
			c2["parent"] = out
			var sub_out := _apply_effect(sub, adef, target, aid, c2)
			# rider/then counts only a then-effect that changed something: its
			# `if` held AND its own outcome fired (a then whose op found no
			# enemy or no tile is not a combo, so the Tally never sees it)
			if _outcome_fired(sub_out):
				_emit({"t": "rider", "id": aid, "kind": "then", "amt": 1})
	return out


func _zero_outcome() -> Dictionary:
	return {
		"hit": 0, "ignited": 0, "pushed": 0, "collided": 0, "converted": 0, "planted": 0, "washed": 0,
		"statused": 0, "affected": [], "crossed": [], "tiles": [],
	}


## True when any counter is above zero or a displaced enemy crossed terrain -
## the condition for a "then" list to run.
func _outcome_fired(out: Dictionary) -> bool:
	for k in ["hit", "ignited", "pushed", "collided", "converted", "planted", "washed", "statused"]:
		if int(out[k]) > 0:
			return true
	return not out["crossed"].is_empty()


func _affect(out: Dictionary, e: Dictionary) -> void:
	if not out["affected"].has(e["id"]):
		out["affected"].append(e["id"])


func _cross(crossed: Array, p: Vector2i) -> void:
	var k := _terrain_kind(p)
	if k != "" and not crossed.has(k):
		crossed.append(k)


func _merge_push(out: Dictionary, res: Dictionary) -> void:
	if int(res["moved"]) > 0:
		out["pushed"] += 1
	out["collided"] += int(res["collided"])
	for k in res["crossed"]:
		if not out["crossed"].has(k):
			out["crossed"].append(k)
	for id in res["affected"]:
		if not out["affected"].has(id):
			out["affected"].append(id)


func _merge_wash(out: Dictionary, res: Dictionary) -> void:
	out["washed"] += int(res["washed"])
	out["pushed"] += int(res["pushed"])
	out["collided"] += int(res["collided"])
	for k in res["crossed"]:
		if not out["crossed"].has(k):
			out["crossed"].append(k)
	for id in res["affected"]:
		if not out["affected"].has(id):
			out["affected"].append(id)


## The tile a rider predicate means by "target": the enemy's own tile when
## evaluating a per-enemy bonus; for "dir" abilities the tile of the first
## enemy the op would reach (walls stop the walk; null when none); otherwise
## the cast target itself.
func _rider_target_tile(ctx: Dictionary, enemy):
	if enemy != null:
		return enemy["pos"]
	var adef: Dictionary = ctx.get("adef", {})
	var target = ctx.get("target", null)
	if target == null:
		return null
	if String(adef.get("target", "")) == "dir":
		var p: Vector2i = ctx.get("origin", player["pos"])
		for i in range(int(adef.get("range", 0))):
			p += target
			if _tile(p) == MapGen.T_WALL:
				return null
			if _enemy_at(p) != null:
				return p
		return null
	return target


## Rider predicates (closed v1 set), AND across dicts and across keys:
##   target_on: [kinds]        terrain kind at the target tile is one of kinds
##   target_adjacent: [kinds]  a tile orthogonally adjacent to the target holds one
##   self_on: kind             terrain kind under the player
##   dim: n                    exact dim stage
##   casts_this_turn_min: n    ctx.casts_before >= n
##   outcome: counter          (then only) parent outcome counter > 0
##   outcome_crossed: kind     (then only) parent crossed has kind
## `outcome` is the parent outcome inside a then, null otherwise (so outcome
## predicates fail outside a then). Unknown keys fail closed.
func _rider_if(preds: Array, ctx: Dictionary, outcome, enemy) -> bool:
	for pred in preds:
		for key in pred:
			var v = pred[key]
			match String(key):
				"target_on":
					var t = _rider_target_tile(ctx, enemy)
					if t == null or not (v as Array).has(_terrain_kind(t)):
						return false
				"target_adjacent":
					var t = _rider_target_tile(ctx, enemy)
					if t == null:
						return false
					var found := false
					for d in DIRS:
						if (v as Array).has(_terrain_kind(t + d)):
							found = true
					if not found:
						return false
				"self_on":
					if _terrain_kind(player["pos"]) != String(v):
						return false
				"dim":
					if dim != int(v):
						return false
				"casts_this_turn_min":
					if int(ctx.get("casts_before", 0)) < int(v):
						return false
				"outcome":
					if outcome == null or int(outcome.get(String(v), 0)) <= 0:
						return false
				"outcome_crossed":
					if outcome == null or not outcome["crossed"].has(String(v)):
						return false
				_:
					return false
	return true


## Rider counts (closed v1 set):
##   growth_adjacent_target    growth tiles orthogonally adjacent to the target tile
##   fire_within_self          fire tiles within per.radius of the player
##   oil_in_line               oil tiles along the dir target up to adef.range (walls stop)
##   enemies_adjacent_target   enemies orthogonally adjacent to the target tile
## Unknown counts read as 0.
func _rider_per(per: Dictionary, ctx: Dictionary) -> int:
	var n := 0
	match String(per.get("count", "")):
		"growth_adjacent_target":
			var t = _rider_target_tile(ctx, null)
			if t != null:
				for d in DIRS:
					if _terrain_kind(t + d) == "growth":
						n += 1
		"fire_within_self":
			var radius := int(per.get("radius", 1))
			for t in terrain.keys():
				if terrain[t]["kind"] == "fire" and _manhattan(t, player["pos"]) <= radius:
					n += 1
		"oil_in_line":
			var adef: Dictionary = ctx.get("adef", {})
			var target = ctx.get("target", null)
			if target is Vector2i:
				var p: Vector2i = ctx.get("origin", player["pos"])
				for i in range(int(adef.get("range", 0))):
					p += target
					if _tile(p) == MapGen.T_WALL:
						break
					if _terrain_kind(p) == "oil":
						n += 1
		"enemies_adjacent_target":
			var t = _rider_target_tile(ctx, null)
			if t != null:
				for d in DIRS:
					if _enemy_at(t + d) != null:
						n += 1
	return n


## Per-enemy bonus damage of an effect ("bonus": {dmg, if}); the predicates
## read `e`'s tile as the target. Emits the rider event when it adds anything.
func _bonus_dmg(eff: Dictionary, ctx: Dictionary, e: Dictionary) -> int:
	if not eff.has("bonus"):
		return 0
	var b: Dictionary = eff["bonus"]
	if b.has("if") and not _rider_if(b["if"], ctx, null, e):
		return 0
	var amt := int(b.get("dmg", 0))
	if amt != 0:
		_emit({"t": "rider", "id": String(ctx.get("aid", "")), "kind": "bonus", "amt": amt})
	return amt


## Light tile p as fire signed by `by` (an ability id or an enemy kind). The
## burnt tile's "bloom" flag rides along (enemy-made oil -> bloom-0 fire).
func _ignite(p: Vector2i, by: String) -> void:
	terrain[p] = _tile_dict("fire", by, terrain.get(p, {}))


## The dict for a `kind` tile written over `old` (the tile it replaces, {} for
## none): ttl from Content.TERRAIN when the kind decays, "by" when given, and
## the old tile's "bloom" flag when it carries one - the flag outlives every
## oil -> fire -> ash transition so the eventual cleanse pays what the oil
## would have.
func _tile_dict(kind: String, by: String, old: Dictionary) -> Dictionary:
	var made := {"kind": kind}
	if bool(Content.terrain(kind, "decays", false)):
		made["ttl"] = int(Content.terrain(kind, "ttl", 0))
	if by != "":
		made["by"] = by
	if old.has("bloom"):
		made["bloom"] = old["bloom"]
	return made


func _enemy_by_id(id: int):
	for e in enemies:
		if e["id"] == id:
			return e
	return null


# --- hook dispatcher (C3) -----------------------------------------------------

## Synthetic ability row hook effects run under: hook effects are aimed at the
## hook tile, so every op reads it as a "tile" target of range 1.
const HOOK_ADEF := {"name": "hook", "cost": 0, "target": "tile", "range": 1, "effects": []}
## Positional ops only the dispatcher knows: they read the tile / enemy from
## the hook ctx instead of a cast target.
const HOOK_OPS := ["damage_at", "status_at", "terrain_at"]

## Dispatch a hook of `kind` (Content.HOOK_KINDS) with its ctx (see the table
## comment there). Sources are scanned in fixed order: kit slots 0..n (an
## ABILITIES row may carry "hooks"), then player.grafts in held order; each
## source row {on, effects, cap_per_turn?, if?} whose `on` matches runs once
## per dispatch, unless its per-turn cap (hook_uses, per source id) is spent
## or its `if` predicates (Game._rider_if against the hook tile) fail.
## Effects reuse _apply_effect with the hook tile as target, plus the three
## HOOK_OPS. Hooks caused by hook effects nest up to Content.HOOK_DEPTH_MAX and
## at most Content.HOOK_STEP_CAP rows run per step; beyond either the hook is
## skipped and {t: hook_capped} is emitted once per step. Every row that runs
## emits {t: hook, id: source id, on: kind, tile}. Nothing runs once the game
## is over.
func _hook(kind: String, ctx: Dictionary) -> void:
	if over:
		return
	var sources: Array = []
	for aid in player["kit"]:
		for row in Content.ABILITIES[aid].get("hooks", []):
			sources.append([String(aid), row])
	for gid in player["grafts"]:
		for row in Content.GRAFTS[gid].get("hooks", []):
			sources.append([String(gid), row])
	var tile = _hook_tile(kind, ctx)
	for src in sources:
		var sid: String = src[0]
		var row: Dictionary = src[1]
		if String(row.get("on", "")) != kind:
			continue
		var cap := int(row.get("cap_per_turn", 0))
		if cap > 0 and int(hook_uses.get(sid, 0)) >= cap:
			continue
		if _hook_depth >= Content.HOOK_DEPTH_MAX or _hook_runs >= Content.HOOK_STEP_CAP:
			if not _hook_capped:
				_hook_capped = true
				_emit({"t": "hook_capped"})
			continue
		var hctx := {
			"aid": sid, "adef": HOOK_ADEF, "target": tile, "origin": player["pos"],
			"casts_before": casts_this_turn, "moved": moved_this_turn, "hook": kind,
		}
		if row.has("if") and not _rider_if(row["if"], hctx, null, null):
			continue
		hook_uses[sid] = int(hook_uses.get(sid, 0)) + 1
		_hook_runs += 1
		_emit({"t": "hook", "id": sid, "on": kind, "tile": tile})
		_hook_depth += 1
		for eff in row.get("effects", []):
			if over:
				break
			if HOOK_OPS.has(String(eff.get("op", ""))):
				_hook_effect(eff, sid, tile, ctx)
			else:
				_apply_effect(eff, HOOK_ADEF, tile, sid, hctx)
		_hook_depth -= 1


## The tile a hook is "about": ctx.tile when given, the enemy's tile for
## staggered, the player's for shield_break, the first planted tile for
## growth_planted; null when nothing applies.
func _hook_tile(kind: String, ctx: Dictionary):
	if ctx.has("tile"):
		return ctx["tile"]
	if ctx.has("enemy"):
		return ctx["enemy"]["pos"]
	if ctx.has("tiles") and not (ctx["tiles"] as Array).is_empty():
		return ctx["tiles"][0]
	if kind == "shield_break":
		return player["pos"]
	return null


## The positional hook ops. damage_at {dmg}: whoever stands on the hook tile
## (an enemy via _damage_enemy, or the player via _damage_player), src = the
## source id. status_at {status, turns}: ctx.enemy when the hook carries one
## (staggered, collision), else the enemy on the tile. terrain_at {kind}: write
## the kind on the hook tile when it is floor with no terrain and no enemy.
func _hook_effect(eff: Dictionary, sid: String, tile, ctx: Dictionary) -> void:
	if tile == null:
		return
	match String(eff["op"]):
		"damage_at":
			var e = _enemy_at(tile)
			if e != null:
				_damage_enemy(e, int(eff["dmg"]), sid)
			elif player["pos"] == tile:
				_damage_player(int(eff["dmg"]), sid)
		"status_at":
			var e = ctx.get("enemy", null)
			if e == null:
				e = _enemy_at(tile)
			if e != null and enemies.has(e):
				_apply_status(e, String(eff["status"]), int(eff["turns"]))
		"terrain_at":
			if _tile(tile) == MapGen.T_FLOOR and not terrain.has(tile) and _enemy_at(tile) == null:
				terrain[tile] = _tile_dict(String(eff["kind"]), "", {})
				_emit({"t": "terrain", "kind": eff["kind"], "tile": tile})


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


## Returns true when damage was applied (false: already gone, or the boss
## core is shielded).
func _damage_enemy(e: Dictionary, amt: int, src: String) -> bool:
	if not enemies.has(e):
		return false
	var edef: Dictionary = Content.ENEMIES[e["kind"]]
	if edef["traits"].has("boss") and e["hp"] <= int(edef.get("gate_hp", 6)) 			and not _growth_adjacent(e["pos"]) and _corruption_adjacent(e["pos"]):
		_emit({"t": "core_shielded", "id": e["id"]})
		return false
	e["hp"] -= amt
	_emit({"t": "damage", "who": e["kind"], "id": e["id"], "amt": amt, "src": src})
	if e["hp"] <= 0:
		enemies.erase(e)
		_emit({"t": "death", "who": e["kind"], "id": e["id"]})
		_hook("kill", {"tile": e["pos"], "enemy_kind": e["kind"], "enemy_id": e["id"]})
		if e.get("elite", false):
			bloom += Content.ELITE_BOUNTY
			_emit({"t": "bounty", "bloom": bloom})
		if edef["traits"].has("boss"):
			won = true
			over = true
			_emit({"t": "win"})
			return true
		if Content.ENEMIES[e["kind"]]["traits"].has("smoke_burst"):
			var tiles_: Array = [e["pos"]]
			for d in DIRS:
				tiles_.append(e["pos"] + d)
			for t in tiles_:
				if _tile(t) == MapGen.T_FLOOR and not terrain.has(t):
					terrain[t] = {"kind": "smoke", "ttl": int(Content.terrain("smoke", "ttl", 3))}
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
			return true
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
	return true


func _damage_player(amt: int, src: String) -> void:
	if player["shield"] > 0:
		var absorbed: int = mini(player["shield"], amt)
		player["shield"] -= absorbed
		amt -= absorbed
		_emit({"t": "shield_absorb", "amt": absorbed})
		if player["shield"] == 0:
			_hook("shield_break", {"amt": absorbed})
		if amt <= 0:
			return
	player["hp"] -= amt
	_emit({"t": "damage", "who": "player", "amt": amt, "src": src})
	if player["hp"] <= 0:
		over = true
		death_cause = src
		_emit({"t": "player_death", "cause": src})


## `src` is the casting ability id; collision damage is signed "collision:<src>".
## `eff` / `ctx` carry the effect's "bonus" rider into the collision hits.
## Returns {moved: tiles travelled, collided: enemies that took collision
## damage, crossed: terrain kinds stepped onto, affected: enemy ids displaced
## or damaged}.
func _push_enemy(e: Dictionary, dir: Vector2i, dist: int, collision_dmg: int, src: String, eff: Dictionary = {}, ctx: Dictionary = {}) -> Dictionary:
	var res := {"moved": 0, "collided": 0, "crossed": [], "affected": []}
	if Content.ENEMIES[e["kind"]]["traits"].has("massive"):
		return res
	for i in range(dist):
		var nxt: Vector2i = e["pos"] + dir
		if not _open(nxt):
			if collision_dmg > 0:
				var dmg1: int = collision_dmg + _bonus_dmg(eff, ctx, e)
				if _damage_enemy(e, dmg1, "collision:" + src):
					res["collided"] += 1
					if not res["affected"].has(e["id"]):
						res["affected"].append(e["id"])
					_hook("collision", {"enemy": e, "tile": e["pos"], "src": src, "dmg": dmg1})
				var hit = _enemy_at(nxt)
				if hit != null:
					var dmg2: int = collision_dmg + _bonus_dmg(eff, ctx, hit)
					if _damage_enemy(hit, dmg2, "collision:" + src):
						res["collided"] += 1
						res["affected"].append(hit["id"])
						_hook("collision", {"enemy": hit, "tile": hit["pos"], "src": src, "dmg": dmg2})
			if int(res["moved"]) > 0 and enemies.has(e):
				_stagger(e)
			return res
		e["pos"] = nxt
		res["moved"] += 1
		if not res["affected"].has(e["id"]):
			res["affected"].append(e["id"])
		_cross(res["crossed"], nxt)
		_enemy_enter_tile(e)
		if not enemies.has(e):
			return res
	if int(res["moved"]) > 0:
		_stagger(e)
	return res


## Returns {washed: tiles cleared, pushed: enemies displaced, collided,
## crossed, affected} (the last three as in _push_enemy).
func _wash_dir(dir: Vector2i, rng_: int, push: int, collision_dmg: int, src: String, eff: Dictionary = {}, ctx: Dictionary = {}) -> Dictionary:
	var res := {"washed": 0, "pushed": 0, "collided": 0, "crossed": [], "affected": []}
	var line: Array = []
	var p: Vector2i = player["pos"]
	for i in range(rng_):
		p += dir
		if _tile(p) == MapGen.T_WALL:
			break
		line.append(p)
	var pushed = null
	for t in line:
		if bool(Content.terrain(_terrain_kind(t), "washable", false)):
			terrain.erase(t)
			res["washed"] += 1
			_emit({"t": "wash", "tile": t})
		if pushed == null:
			var e = _enemy_at(t)
			if e != null:
				if Content.ENEMIES[e["kind"]]["traits"].has("massive"):
					# too heavy to shove; the jet's pressure still hits
					if collision_dmg > 0:
						var dmg3: int = collision_dmg + _bonus_dmg(eff, ctx, e)
						if _damage_enemy(e, dmg3, "collision:" + src):
							res["collided"] += 1
							res["affected"].append(e["id"])
							_hook("collision", {"enemy": e, "tile": e["pos"], "src": src, "dmg": dmg3})
					return res
				pushed = e
	if pushed != null:
		var pr := _push_enemy(pushed, dir, push, collision_dmg, src, eff, ctx)
		if int(pr["moved"]) > 0:
			res["pushed"] += 1
		res["collided"] += int(pr["collided"])
		res["crossed"] = pr["crossed"]
		res["affected"] = pr["affected"]
	return res


func _player_enter_tile() -> void:
	var k := _terrain_kind(player["pos"])
	var dmg := int(Content.terrain(k, "enter_dmg_player", 0))
	if dmg > 0:
		_damage_player(dmg, String(Content.terrain(k, "enter_src", k)))
	elif k == "supply":
		if player["items"].size() < Content.ITEM_CAP:
			var iid := String(terrain[player["pos"]].get("item", "balm_fruit"))
			player["items"].append(iid)
			terrain.erase(player["pos"])
			_emit({"t": "item_pickup", "id": iid})
		else:
			_emit({"t": "satchel_full"})


## Boss-gate shield: a core-shielding kind (Content.TERRAIN shields_core)
## stands orthogonally adjacent.
func _corruption_adjacent(p: Vector2i) -> bool:
	for d in DIRS:
		if bool(Content.terrain(_terrain_kind(p + d), "shields_core", false)):
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
	var k := _terrain_kind(e["pos"])
	if Content.ENEMIES[e["kind"]]["traits"].has("igniter") and bool(Content.terrain(k, "flammable", false)):
		_ignite(e["pos"], e["kind"])
		_emit({"t": "ignite", "tile": e["pos"]})
		_hook("ignite", {"tile": e["pos"], "by": e["kind"]})
		k = _terrain_kind(e["pos"])
	var dmg := int(Content.terrain(k, "enter_dmg_enemy", 0))
	if dmg > 0:
		_damage_enemy(e, dmg, k + ":" + _fire_by(e["pos"]))


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


## Who lit the fire at p: the casting ability id, the igniting enemy kind,
## or "env" for a tile that carries no attribution.
func _fire_by(p: Vector2i) -> String:
	if terrain.has(p):
		return String(terrain[p].get("by", "env"))
	return "env"


func _enemy_at(p: Vector2i):
	for e in enemies:
		if e["pos"] == p:
			return e
	return null


func _open(p: Vector2i) -> bool:
	if _tile(p) != MapGen.T_FLOOR or _enemy_at(p) != null or p == player["pos"]:
		return false
	var k := _terrain_kind(p)
	return k == "" or not bool(Content.terrain(k, "blocks", false))


func _line_clear(a: Vector2i, b: Vector2i) -> bool:
	var delta: Vector2i = b - a
	var dir := Vector2i(signi(delta.x), signi(delta.y))
	var p := a + dir
	while p != b:
		if _tile(p) == MapGen.T_WALL or _enemy_at(p) != null or bool(Content.terrain(_terrain_kind(p), "blocks_beam", false)):
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
