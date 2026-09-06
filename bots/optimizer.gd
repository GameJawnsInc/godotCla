extends "res://bots/bot_base.gd"
## Optimizer persona: deterministic heuristic play aimed at winning.
## Priorities: descend > spike > strike > seed-on-head > lance > dodge
## telegraphed damage > cleanse when safe > path to stairs > pull a blocker
## into reach > end turn.

## sim/content.gd under a shouting name: the subclasses (fanatic, deeproot)
## already declare a `Content` const of their own and GDScript forbids
## redeclaring an inherited member.
const CONTENT := preload("res://sim/content.gd")

const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## Ability preference, best first: this ranks the draft offers. Base ids only;
## a "+" form inherits its base's place and ranks just above it (see
## _pref_rank).
const DRAFT_PREF := [
	"sun_flare", "grow_spike", "geyser", "thorn_shield", "water_jet",
	"tide", "sap_snare", "moss_filter", "spore_cloud", "gust", "vine_whip",
	"pollen_burst", "solar_lance", "seed_bomb", "updraft", "overgrowth",
	"anchor_roots", "burrow", "fungal_ring", "clear_air", "steam_vent", "root_wall",
	"mycelium_dash",
]

## Kit slots the draft refuses to drop when the kit is full: mobility is the
## escape button and seed_bomb is the growth engine that makes the Furnace
## core killable.
const NEVER_DROP := ["mycelium_dash", "seed_bomb"]

## Effect ops that put damage on an enemy tile. _est_dmg reads their "dmg"
## (plus the rider arithmetic around it) and ignores every other op - a bot
## guess, not a sim call, so it stays cheap enough for every candidate.
const DMG_OPS := ["damage", "aoe_damage", "lance", "pull"]


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

	# consumables are free actions - fire them on clear triggers
	if by.has("use_item"):
		var pl0: Dictionary = snap["player"]
		var th0 := _threat_tiles(snap)
		for a in by["use_item"]:
			match String(pl0["items"][a["slot"]]):
				"balm_fruit":
					if pl0["hp"] <= maxi(6, int(pl0["max_hp"]) / 2):
						return a
				"sun_capsule":
					if pl0["charge"] == 0 and _enemies_within(snap, 3) >= 1:
						return a
				"iron_seed":
					if pl0["shield"] == 0 and th0.has(pl0["pos"]):
						return a
				"spore_vial":
					if _enemies_within(snap, 1) >= 2:
						return a
				"clearair_pod":
					if int(snap["dim"]) >= 2:
						return a

	if by.has("buy"):
		var deal := _shop_choice(by["buy"])
		if not deal.is_empty():
			return deal

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

	# 3+ damage for 1 charge beats everything else on the menu. The spike's
	# per-growth rider makes WHICH enemy it hits matter, so the target comes
	# from _est_dmg (kill first, then biggest estimate) instead of kit order.
	if by.has("ability"):
		var spike := _best_spike(snap, by["ability"])
		if not spike.is_empty():
			return spike

	# Desperation: 120+ turns on one floor means some stable loop has eaten
	# the run (spawn streams, corner shield-cycling, dodge orbits). Stop
	# optimizing - walk to the stairs, strike only what plugs the path, and
	# take the hits on the way out.
	var stairs_d: Vector2i = snap["map"]["stairs"]
	if int(snap["turn"]) > 120 and stairs_d != Vector2i(-1, -1):
		if int(snap.get("green_need", 0)) > int(snap.get("greened", 0)):
			if by.has("cleanse"):
				return by["cleanse"][0]
			var cg2 := _nearest_corruption(snap)
			if cg2 != Vector2i(-1, -1):
				stairs_d = cg2
		if by.has("move"):
			var dstep := _bfs_step(snap, false, threat, stairs_d)
			if dstep != Vector2i.ZERO:
				for a in by["move"]:
					if a["dir"] == dstep:
						return a
		if by.has("strike"):
			var ba = null
			var bd := 999999
			for a in by["strike"]:
				var d := _bfs_dist(snap, ppos + a["dir"], stairs_d)
				if d < bd:
					bd = d
					ba = a
			if ba != null:
				return ba

	# Survival gate: standing in telegraphed damage without the HP to trade.
	# A strike only helps here if it kills the attacker before the hit lands;
	# otherwise step out first and fight from a safe tile.
	if threat.has(ppos) and snap["player"]["hp"] + snap["player"]["shield"] <= _incoming_dmg(snap) * 2:
		if by.has("strike"):
			for a in by["strike"]:
				var e = _enemy_at(snap, ppos + a["dir"])
				if e != null and e["hp"] <= CONTENT.STRIKE_DMG:
					return a
		var out := _dodge(snap, by, threat)
		if not out.is_empty():
			return out

	# green gate: the stairs stay dormant until the quota is met. A cleanse
	# is one cheap tap - take it whenever standing safe, and keep taking
	# them into the relief taper (quota + 4 cleanses still pause the clock);
	# only the walk toward corruption waits for a calm moment.
	var quota_left: int = int(snap.get("green_need", 0)) - int(snap.get("greened", 0))
	if quota_left > -4 and by.has("cleanse") and not threat.has(ppos):
		return by["cleanse"][0]
	if quota_left > 0:
		if _enemies_within(snap, 2) == 0:
			var cg := _nearest_corruption(snap)
			if cg != Vector2i(-1, -1) and by.has("move"):
				var gstep := _bfs_step(snap, false, threat, cg)
				if gstep != Vector2i.ZERO:
					for a in by["move"]:
						if a["dir"] == gstep and not threat.has(ppos + a["dir"]):
							return a

	if by.has("strike"):
		# spiked targets (golems, elites) bleed melee attackers: skip the
		# punch unless it kills or we have HP to spare - reach for a tool
		var filtered: Array = []
		for a in by["strike"]:
			var se = _enemy_at(snap, ppos + a["dir"])
			if se != null and (se["traits"].has("spiked") or se.get("elite", false)):
				if se["hp"] > CONTENT.STRIKE_DMG and snap["player"]["hp"] + snap["player"]["shield"] <= 6:
					continue
			filtered.append(a)
		if filtered.is_empty():
			by.erase("strike")
		else:
			by["strike"] = filtered
	if by.has("strike"):
		# lowest HP first, but summoners outrank their spawns - executing the
		# endless hp-1 stream while the engine keeps summoning is how magpie
		# runs used to time out at turn 400
		var best = null
		var best_key := 999999
		for a in by["strike"]:
			var e = _enemy_at(snap, ppos + a["dir"])
			if e == null:
				continue
			var key: int = e["hp"] - (1000 if e["traits"].has("summons") else 0)
			if key < best_key:
				best_key = key
				best = a
		if best != null:
			return best

	# Seed on head: the bomb plants growth on the enemy's own tile, which both
	# makes the spike legal against it and feeds the spike's growth rider - so
	# the spike that follows this same turn lands for its capped maximum.
	# Sits below the strike ladder (never spend 3 charge on what a punch
	# finishes) and above the generic casts.
	if by.has("ability"):
		var head := _seed_on_head(snap, by["ability"])
		if not head.is_empty():
			return head

	if by.has("ability"):
		var near := _enemies_within(snap, 2)
		for a in by["ability"]:
			var aid: String = _kit_id(snap, a["slot"])
			# the flare pays for two targets, or for one it finishes: the
			# estimate counts the burning-ground bonus (and the oil this very
			# cast lights first), which is the light-then-flare finisher
			if aid == "sun_flare" and (near >= 2 or _aoe_finishes(snap, _kit_full_id(snap, a["slot"]))):
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
		# regen relief pays for itself in one turn once the skies have dimmed
		if int(snap["dim"]) >= 1:
			for a in by["ability"]:
				if _kit_id(snap, a["slot"]) == "moss_filter":
					return a
		# anchor against a dragger in range before it starts reeling us in
		if int(snap["player"].get("anchor_turns", 0)) == 0:
			for a in by["ability"]:
				if _kit_id(snap, a["slot"]) == "anchor_roots" and _dragger_near(snap):
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

	# No greedy cleansing: measured at 100 seeds, cleansing off the stairs path
	# costs 11 wins (59 -> 70 without it). The bloom never repays the turns.
	# Cleansing still happens where it pays: boss-gate clearing above, and
	# whatever a shrine purchase passes by.

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
	var offers: Array = snap["draft_offers"]
	var best_pick := -1
	# unlisted offers rank after every listed id (still pickable when nothing
	# listed is on the table); the sentinel is huge so some offer always wins
	# over skipping - a "+" of anything beats its plain form (r * 2 - 1)
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
		if NEVER_DROP.has(String(kit[slot]).trim_suffix("+")):
			continue
		var u: int = uses.get(kit[slot], 0)
		if u < best_u:
			best_u = u
			best_a = a
	return best_a


## Rank of an ability id in DRAFT_PREF; lower is better. Unlisted ids rank
## after everything listed. The doubled scale leaves each base one step of
## room so its "+" form ranks strictly better than the plain one.
func _pref_rank(aid: String) -> int:
	var r: int = DRAFT_PREF.find(String(aid).trim_suffix("+"))
	if r == -1:
		r = DRAFT_PREF.size()
	return r * 2 - (1 if String(aid).ends_with("+") else 0)


## Shrine purchase, in the old order (graft, heal, ability, item), from the
## legal list only. Empty dict when nothing on the counter is worth taking.
func _shop_choice(buys: Array) -> Dictionary:
	var graft := _first_graft(buys)
	if not graft.is_empty():
		return graft
	for a in buys:
		if a["item"] == "heal":
			return a
	for a in buys:
		if a["item"] == "ability":
			return a
	for a in buys:
		if a["item"] == "item":
			return a
	return {}


## The shop offers two grafts and one pick closes the counter. Every heuristic
## bot takes offer 0: no graft preference table exists anywhere yet, and the
## progression review holds any graft weighting until tests/sweep_grafts.gd
## has measured them at 30+ seeds. Empty dict when no graft is affordable.
func _first_graft(buys: Array) -> Dictionary:
	var best: Dictionary = {}
	for a in buys:
		if a["item"] != "graft":
			continue
		if best.is_empty() or int(a.get("pick", 0)) < int(best.get("pick", 0)):
			best = a
	return best


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
		# dash out only if it makes progress toward the stairs - dashing
		# between the same two growth tiles while healing off the choke
		# was the magpie immortality loop. Boss floors have no stairs, so
		# any safe dash is progress there.
		var dash_goal: Vector2i = snap["map"]["stairs"]
		var best_dash: Dictionary = {}
		var best_dd := _bfs_dist(snap, ppos, dash_goal)
		for a in by["ability"]:
			if _kit_id(snap, a["slot"]) == "mycelium_dash" and not threat.has(a["target"]):
				if dash_goal == Vector2i(-1, -1):
					return a
				var dd := _bfs_dist(snap, a["target"], dash_goal)
				if dd < best_dd:
					best_dd = dd
					best_dash = a
		if not best_dash.is_empty():
			return best_dash
		# rooting only swallows the intents Content.STATUSES.root blocks
		# (move / advance / drag today), so a snare on an attacker whose
		# wind-up root cannot touch dodges nothing. Read the table, never
		# the literal: a row edit re-aims the snare with no bot change.
		var root_blocks: Array = CONTENT.STATUSES.get("root", {}).get("blocks", [])
		for a in by["ability"]:
			if _kit_id(snap, a["slot"]) == "sap_snare":
				var se = _enemy_at(snap, a["target"])
				if se != null and root_blocks.has(String(se["intent"].get("type", ""))):
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
		# threat = terrain that burns whoever stands in it, plus anything
		# flammable while an ignite_all is telegraphed
		var burns: bool = int(CONTENT.terrain(k, "tick_dmg_player", 0)) > 0
		var will_burn: bool = ignite_coming and bool(CONTENT.terrain(k, "flammable", false))
		if burns or will_burn:
			t[tile] = true
	return t


func _dragger_near(snap: Dictionary) -> bool:
	var ppos: Vector2i = snap["player"]["pos"]
	for e in snap["enemies"]:
		if not e["traits"].has("drags") and not e["traits"].has("dredges"):
			continue
		if absi(e["pos"].x - ppos.x) + absi(e["pos"].y - ppos.y) <= 5:
			return true
	return false


func _growth_adj_to(snap: Dictionary, pos: Vector2i) -> bool:
	for d in DIRS:
		if snap["terrain"].get(pos + d, {}).get("kind", "") == "growth":
			return true
	return false


## Growth tiles orthogonally adjacent to `pos` - what the sim's
## growth_adjacent_target rider counts (the tile itself never counts).
func _growth_adj_count(snap: Dictionary, pos: Vector2i) -> int:
	var n := 0
	for d in DIRS:
		if String(snap["terrain"].get(pos + d, {}).get("kind", "")) == "growth":
			n += 1
	return n


## Kit slot id as written, upgrade suffix and all: _est_dmg needs the exact
## row, and "grow_spike+" is not "grow_spike" (_kit_id strips the suffix).
func _kit_full_id(snap: Dictionary, slot: int) -> String:
	return String(snap["player"]["kit"][slot])


## What a cast costs right now: Game.ability_cost mirrored over the snapshot -
## standing on growth surges a cost-2+ ability by its own "surge" rule.
func _cast_cost(snap: Dictionary, aid: String) -> int:
	var adef: Dictionary = CONTENT.ABILITIES.get(aid, {})
	if adef.is_empty():
		return 99
	var base := int(adef["cost"])
	if base >= 2 and String(snap["terrain"].get(snap["player"]["pos"], {}).get("kind", "")) == "growth":
		var surge: Dictionary = adef.get("surge", CONTENT.SURGE_DEFAULT)
		return maxi(1, base + int(surge.get("cost", -1)))
	return base


## Damage `aid` would land on an enemy standing at `target`, read from Content
## alone: the base "dmg" of every damage-dealing effect plus its rider
## arithmetic (per, bonus) as the snapshot's terrain scores it. No sim call
## and no clone, so it is affordable on every candidate action.
## `target` is the tile the enemy stands on - for "dir" and "self" abilities
## the caller passes the tile it expects to be hit, never the direction.
func _est_dmg(aid: String, target: Vector2i, snap: Dictionary) -> int:
	var adef: Dictionary = CONTENT.ABILITIES.get(aid, {})
	if adef.is_empty():
		return 0
	var total := 0
	for eff in adef.get("effects", []):
		var op := String(eff["op"])
		if not DMG_OPS.has(op):
			continue
		var dmg := int(eff.get("dmg", 0))
		if op == "lance" and int(snap.get("dim", 0)) == 0:
			dmg += int(eff.get("clear_smog_bonus", 0))
		if eff.has("per"):
			var per: Dictionary = eff["per"]
			var add := int(per.get("add", {}).get("dmg", 0))
			if add != 0:
				var n := _per_count(per, target, snap)
				var cap := int(per.get("cap", 0))
				if cap > 0:
					n = mini(n, cap)
				dmg += add * n
		if eff.has("bonus") and _bonus_holds(eff, target, snap):
			dmg += int(eff["bonus"].get("dmg", 0))
		total += dmg
	return total


## Game._rider_per over the snapshot, for the counts a bot can read off a
## tile. Unknown counts read as 0, exactly like the sim's closed set.
func _per_count(per: Dictionary, target: Vector2i, snap: Dictionary) -> int:
	var n := 0
	match String(per.get("count", "")):
		"growth_adjacent_target":
			n = _growth_adj_count(snap, target)
		"enemies_adjacent_target":
			for d in DIRS:
				if _enemy_at(snap, target + d) != null:
					n += 1
	return n


## Game._rider_if over the snapshot for an effect's "bonus" rider aimed at
## `target`. One deliberate deviation: a cast that ignites lights the
## flammable ground under the target before it rolls damage (aoe_damage and
## lance run their ignite pass first), so oil under the target already counts
## as fire here. Unknown predicates fail closed, like the sim.
func _bonus_holds(eff: Dictionary, target: Vector2i, snap: Dictionary) -> bool:
	var kind := String(snap["terrain"].get(target, {}).get("kind", ""))
	for pred in eff["bonus"].get("if", []):
		for key in pred:
			match String(key):
				"target_on":
					var kinds: Array = pred[key]
					if kinds.has(kind):
						continue
					if kinds.has("fire") and bool(eff.get("ignite", false)) \
							and bool(CONTENT.terrain(kind, "flammable", false)):
						continue
					return false
				"target_adjacent":
					var near_kinds: Array = pred[key]
					var found := false
					for d in DIRS:
						if near_kinds.has(String(snap["terrain"].get(target + d, {}).get("kind", ""))):
							found = true
					if not found:
						return false
				"self_on":
					if String(snap["terrain"].get(snap["player"]["pos"], {}).get("kind", "")) != String(pred[key]):
						return false
				"dim":
					if int(snap.get("dim", 0)) != int(pred[key]):
						return false
				_:
					return false
	return true


## Best legal grow_spike cast: a target the estimate kills outright first,
## then the biggest estimate (the rider pays per growth tile beside the
## target). Empty dict when no spike is legal.
func _best_spike(snap: Dictionary, abilities: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_key := -999999
	for a in abilities:
		if _kit_id(snap, a["slot"]) != "grow_spike":
			continue
		var e = _enemy_at(snap, a["target"])
		var est := _est_dmg(_kit_full_id(snap, a["slot"]), a["target"], snap)
		var key := est + (1000 if e != null and est >= int(e["hp"]) else 0)
		if best.is_empty() or key > best_key:
			best_key = key
			best = a
	return best


## Would this self-centred aoe finish something? True when the estimate kills
## an enemy inside the first damaging effect's radius.
func _aoe_finishes(snap: Dictionary, aid: String) -> bool:
	var adef: Dictionary = CONTENT.ABILITIES.get(aid, {})
	var radius := -1
	for eff in adef.get("effects", []):
		if DMG_OPS.has(String(eff["op"])):
			radius = int(eff.get("radius", 0))
			break
	if radius <= 0:
		return false
	var ppos: Vector2i = snap["player"]["pos"]
	for e in snap["enemies"]:
		if absi(e["pos"].x - ppos.x) + absi(e["pos"].y - ppos.y) > radius:
			continue
		if _est_dmg(aid, e["pos"], snap) >= int(e["hp"]):
			return true
	return false


## Seed on head: bomb the tile an enemy is standing on (enemy-occupied tiles
## are legal "tile" targets). The bomb plants growth under and around it,
## which both makes grow_spike legal against that enemy and feeds the spike's
## growth-adjacent rider up to its cap, so the spike that follows on the next
## decision - still this turn - lands for its maximum.
## Trigger: the kit holds a spike and a bomb; the enemy's own tile is a legal
## bomb target with fewer adjacent growth tiles than the spike's rider cap
## (otherwise the seed adds nothing); the enemy outlives a plain punch; and
## this turn's charge covers both casts. Ties break on fewest growth already
## there, then the meatiest target. Empty dict when nothing qualifies.
func _seed_on_head(snap: Dictionary, abilities: Array) -> Dictionary:
	var kit: Array = snap["player"]["kit"]
	var spike := ""
	for i in kit.size():
		if snap["player"]["gummed"].has(i):
			continue
		if CONTENT.base_id(String(kit[i])) == "grow_spike":
			spike = String(kit[i])
			break
	if spike == "":
		return {}
	# a spike row with no per rider still gains legality from the seed, so it
	# counts as cap 1: seed only when nothing grows beside the target yet
	var effs: Array = CONTENT.ABILITIES.get(spike, {}).get("effects", [])
	var cap := 1
	if not effs.is_empty():
		cap = maxi(1, int((effs[0] as Dictionary).get("per", {}).get("cap", 0)))
	var charge := int(snap["player"]["charge"])
	var spike_cost := _cast_cost(snap, spike)
	var best: Dictionary = {}
	var best_adj := 99
	var best_hp := -1
	for a in abilities:
		var aid := String(kit[a["slot"]])
		if CONTENT.base_id(aid) != "seed_bomb":
			continue
		if charge < _cast_cost(snap, aid) + spike_cost:
			continue
		var e = _enemy_at(snap, a["target"])
		if e == null or int(e["hp"]) <= CONTENT.STRIKE_DMG:
			continue
		var adj := _growth_adj_count(snap, a["target"])
		if adj >= cap:
			continue
		if best.is_empty() or adj < best_adj or (adj == best_adj and int(e["hp"]) > best_hp):
			best_adj = adj
			best_hp = int(e["hp"])
			best = a
	return best


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
	# hazard = terrain that damages the player for stepping onto it
	return int(CONTENT.terrain(k, "enter_dmg_player", 0)) > 0


func _lance_hits(snap: Dictionary, dir: Vector2i) -> bool:
	var m: Dictionary = snap["map"]
	var p: Vector2i = snap["player"]["pos"]
	for i in 3:
		p += dir
		if p.x < 0 or p.y < 0 or p.x >= int(m["w"]) or p.y >= int(m["h"]):
			return false
		if m["tiles"][p.y * int(m["w"]) + p.x] != 1:
			return false
		if bool(CONTENT.terrain(snap["terrain"].get(p, {}).get("kind", ""), "blocks_beam", false)):
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
		var worth: bool = snap["shop"].has("grafts") and snap["bloom"] >= 5
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
	# Route to the stairs is blocked by enemies: advance on a summoner first -
	# its spawn stream is usually what is clogging the corridor, and killing
	# spawns adjacent to us forever is a timeout, not progress.
	var target := _nearest_summoner_pos(snap)
	if target == Vector2i(-1, -1):
		target = _nearest_enemy_pos(snap)
	if target != Vector2i(-1, -1):
		return _bfs_step(snap, false, threat, target)
	return Vector2i.ZERO


func _nearest_summoner_pos(snap: Dictionary) -> Vector2i:
	var ppos: Vector2i = snap["player"]["pos"]
	var best := Vector2i(-1, -1)
	var best_d := 9999
	for e in snap["enemies"]:
		if not e["traits"].has("summons"):
			continue
		var d: int = absi(e["pos"].x - ppos.x) + absi(e["pos"].y - ppos.y)
		if d < best_d:
			best_d = d
			best = e["pos"]
	return best


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
				# bad footing: anything that hurts on entry, plus corruption
				# (oil) - a strict route steps on neither
				if int(CONTENT.terrain(k, "enter_dmg_player", 0)) > 0 or CONTENT.is_corruption(k):
					continue
			prev[nxt] = cur
			queue.append(nxt)
	return Vector2i.ZERO


func _nearest_corruption(snap: Dictionary) -> Vector2i:
	var pp: Vector2i = snap["player"]["pos"]
	var best := Vector2i(-1, -1)
	var bd := 99999
	for t in snap["terrain"].keys():
		var k := String(snap["terrain"][t]["kind"])
		if not CONTENT.is_corruption(k):
			continue
		var d: int = absi(t.x - pp.x) + absi(t.y - pp.y)
		if d < bd:
			bd = d
			best = t
	return best
