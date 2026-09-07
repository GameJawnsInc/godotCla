extends "res://bots/deeproot.gd"
## Deeproot Plan persona (docs/PROGRESSION_REVIEW.md 7.5): deeproot's
## clone-based search plus two layers that let it see one setup ahead - the
## combo-depth instrument. Legacy deeproot is untouched, so the delta between
## the two columns isolates planning: draft mode stays "list".
##
## Layer 1 - option value: _score gains terms for what the kit COULD do next
## turn (an enemy standing beside growth while a spike is held, oil under an
## enemy while an igniter is held, an enemy pinned against a wall while a
## shove is held, standing on growth holding an ability that would surge from
## it, roots beside an
## enemy while a shove is held). Every term is computed only for effect ops
## the kit currently holds, read from Content.ABILITIES rows - no ability id
## is named anywhere in this file.
##
## Layer 2 - plan mode: a candidate whose first effect op is a setup op is
## scored not only as "setup, then end_turn" but as the best of "setup, then
## one follow-up ability this same turn, then end_turn" over a round-robin of
## at most PLAN_FOLLOWUPS follow-ups across kit slots. Everything else keeps
## deeproot's 1-ply path.
##
## Shrine routing and shopping: _refresh_field points the gradient at the
## shrine while bloom covers the cheapest useful buy and no enemy is within
## SHRINE_SAFE_RADIUS; on the shrine, buys are legal actions and go through
## the same clone-and-score loop, so a held graft is valued by GRAFT_WEIGHTS
## and a filled kit slot by KIT_SLOT_POINTS, which is what makes a purchase
## read as a gain against the bloom it costs.
##
## Deterministic: clone-based only, no rng draws, no wall clock, stable
## iteration order (kit slots, DIRS, legal_actions order).

## Effect ops that set something up rather than pay off: a candidate whose
## first op is one of these gets the plan-mode follow-up enumeration.
const SETUP_OPS := [
	"grow_radius", "grow_wall", "convert_radius", "apply_status", "aoe_status",
	"create_terrain", "push_line", "push_all", "wash_push", "wash_all", "pull",
	"teleport", "undim",
]
## The shove family: ops that displace an enemy along a line the caster picks.
const PUSH_OPS := ["push_line", "push_all", "wash_push", "wash_all"]
## Ops that displace an enemy at all (PUSH_OPS plus the lash).
const DISPLACE_OPS := ["push_line", "push_all", "wash_push", "wash_all", "pull"]
## Round-robin cap on follow-up ability actions enumerated after a setup.
const PLAN_FOLLOWUPS := 12
## Follow-up clones one decision may spend in total, consumed in candidate
## order (nearest-target-first inside a slot, slots round-robin): a wide
## setup list (a bomb's ~12 tiles plus a dash's growth tiles) would
## otherwise expand every setup to the full PLAN_FOLLOWUPS and push the
## runtime factor past the accepted 2-3x. Setups past the budget keep the
## plain setup-then-end_turn line.
const PLAN_BUDGET := 60
## No shrine detour while an enemy stands this close (manhattan).
const SHRINE_SAFE_RADIUS := 3

## Option-value weights (review 7.5) and caps.
## Scale check against the inherited _score: end_turn banks the unspent
## charge at 2 points per point, so a 2-charge setup that ends the turn gives
## up 4 points of bank; one enemy left standing beside growth is worth
## SPIKE_POINTS = 6, so the setup edges end_turn by 2 (a fresh
## floor-1 hand: bank 3 -> +6 for end_turn, bank 1 + 6 = +8 for the setup).
## A realised hit moves the enemy-hp term by 10 per hp, so 2 damage is 20 -
## above every option term and above every capped total (spike 18, ignite
## 12, pin 10, surge 6, roots 3): the search never trades a real hit for a
## setup, and never lets a 1-ply threat outbid a 2-damage payoff.
const SPIKE_POINTS := 6.0
const SPIKE_CAP := 3
const IGNITE_POINTS := 4.0
const IGNITE_CAP := 3
const PIN_POINTS := 5.0
const PIN_CAP := 2
const SURGE_POINTS := 6.0
const ROOTS_POINTS := 3.0

## Graft weights, bot-side. Ranking from the docs/BALANCE.md 2026-09-06d
## `sweep_grafts` rows (optimizer tier 0 and tier 6, deeproot tier 0, 30
## seeds, paired against the no-graft row): solar_core +12 / +17 wins per 30
## (p 0.00 both tiers) sits far above everything; compost (+1 / -1 / +5),
## oil_tithe (+0 / +2 / +3) and ember_sap (-2 / +2 / +0) are the rule grafts
## that ship; the stat and mod rows (verdant_pulse +4 / +0, bloom_surge
## +2 / +2, deep_cells +1 / +1, carapace +1 / +0, thick_bark -1 / +1,
## undertow +0 / +1) sit at the bottom. Unknown ids weigh 0.
const GRAFT_WEIGHTS := {
	"solar_core": 12,
	"compost": 5,
	"oil_tithe": 4,
	"ember_sap": 3,
	"verdant_pulse": 2,
	"bloom_surge": 2,
	"deep_cells": 1,
	"carapace": 1,
	"thick_bark": 1,
	"undertow": 1,
}
## Score points per graft weight. Bloom scores 4 per point in _score, so a
## graft is a gain only when weight * GRAFT_POINTS clears its own price
## (the Content.GRAFTS "price" + 2 per graft already owned + tier markup):
## solar_core (120 against a base 8) always, compost (50 against 6) while
## fewer than four are owned, oil_tithe (40 against 5) fewer than three,
## ember_sap (30 against 5) fewer than two, verdant_pulse and bloom_surge
## (20 against 3) only as the very first graft, the weight-1 rows never.
## The weights rank the rows; the prices (which the sim publishes per offer
## as shop.graft_prices) decide what the purse can actually take.
const GRAFT_POINTS := 10.0
## Score points per filled kit slot: a shrine ability (4 bloom = 16 points)
## is a small gain while the kit has room; the tier markup prices it out.
const KIT_SLOT_POINTS := 20.0

const END_TURN := {"type": "end_turn"}
const NO_GOAL := Vector2i(-99, -99)

## The last decision's plan: {action, followup, value}. `followup` is the
## ability action whose forced continuation produced the chosen candidate's
## value ({} when the plain setup-then-end_turn line was the best). Read by
## tests; never by the bot itself.
var last_plan := {}
## Floor on which a shrine detour was abandoned because an enemy closed to
## SHRINE_SAFE_RADIUS mid-walk: one detour attempt per floor, or the goal
## flips between shrine and stairs every time the bot steps toward and away
## from an enemy parked in the corridor (seed 23 tier 0 oscillated on two
## growth tiles for 400 turns that way).
var _shrine_abandoned_floor := -1


func reset(seed_v: int) -> void:
	super.reset(seed_v)
	_shrine_abandoned_floor = -1
	last_plan = {}


func get_bot_name() -> String:
	return "deeproot_plan"


func choose_action(snap: Dictionary, legal: Array) -> Dictionary:
	last_plan = {}
	if snap["phase"] == "draft" or _sim == null:
		return super.choose_action(snap, legal)
	_refresh_field(snap)
	var candidates := _candidates(legal, snap)
	var best: Dictionary = candidates[0]
	var best_s := -1e18
	var best_follow: Dictionary = {}
	var budget := PLAN_BUDGET
	for a in candidates:
		var g = _sim.clone()
		g.step(a)
		var s := -1e18
		var follow: Dictionary = {}
		# plan mode: the setup is on the board, try one follow-up cast before
		# the forced end_turn and keep the best continuation
		if budget > 0 and _is_setup(snap, a) and not g.over and g.phase == "play":
			for f in _followups(g, a):
				if budget <= 0:
					break
				budget -= 1
				var g2 = g.clone()
				g2.step(f)
				if not g2.over and g2.phase == "play":
					g2.step(END_TURN)
				var fs := _score(g2)
				if fs > s:
					s = fs
					follow = f
		if not g.over and g.phase == "play" and String(a["type"]) != "end_turn":
			g.step(END_TURN)
		var plain := _score(g)
		# a tie between the plain line and a follow-up goes to the plain line
		if plain >= s:
			s = plain
			follow = {}
		if s > best_s:
			best_s = s
			best = a
			best_follow = follow
	last_plan = {"action": best, "followup": best_follow, "value": best_s}
	return best


## An ability candidate whose first effect op is a setup op.
func _is_setup(snap: Dictionary, a: Dictionary) -> bool:
	if String(a["type"]) != "ability":
		return false
	var effs: Array = _adef(String(snap["player"]["kit"][a["slot"]])).get("effects", [])
	return not effs.is_empty() and SETUP_OPS.has(String((effs[0] as Dictionary).get("op", "")))


## Follow-up ability actions legal on the clone `g` after the setup `setup`:
## the same round-robin across kit slots as _candidates, nearest-target-first
## inside a slot, capped at PLAN_FOLLOWUPS. Non-ability actions are not
## follow-ups, and a second cast of a teleport setup's own slot is skipped
## (dash then dash again is a wasted clone, never a combo).
func _followups(g, setup: Dictionary) -> Array:
	var legal: Array = g.legal_actions()
	var setup_slot := int(setup.get("slot", -1))
	var skip_slot := -1
	if setup_slot >= 0:
		var effs: Array = _adef(String(g.player["kit"][setup_slot])).get("effects", [])
		if not effs.is_empty() and String((effs[0] as Dictionary).get("op", "")) == "teleport":
			skip_slot = setup_slot
	var view := {"player": {"pos": g.player["pos"], "kit": g.player["kit"]}, "enemies": g.enemies}
	var ppos: Vector2i = g.player["pos"]
	var groups := {}
	var slots: Array = []
	for i in legal.size():
		var a: Dictionary = legal[i]
		if String(a["type"]) != "ability":
			continue
		var slot: int = a["slot"]
		if slot == skip_slot:
			continue
		if not groups.has(slot):
			groups[slot] = []
			slots.append(slot)
		groups[slot].append([_target_enemy_dist(view, ppos, String(g.player["kit"][slot]), a["target"]), i, a])
	slots.sort()
	for slot in slots:
		groups[slot].sort_custom(func(x, y): return x[0] < y[0] if x[0] != y[0] else x[1] < y[1])
	var out: Array = []
	var cursor := {}
	for slot in slots:
		cursor[slot] = 0
	var remaining := true
	while remaining and out.size() < PLAN_FOLLOWUPS:
		remaining = false
		for slot in slots:
			var c: int = cursor[slot]
			if c >= groups[slot].size():
				continue
			out.append(groups[slot][c][2])
			cursor[slot] = c + 1
			remaining = remaining or cursor[slot] < groups[slot].size()
			if out.size() >= PLAN_FOLLOWUPS:
				break
	return out


# --- scoring ------------------------------------------------------------------

func _score(g) -> float:
	var s := super._score(g)
	if g.won or g.over:
		return s
	s += _graft_value(g)
	s += float(g.player["kit"].size()) * KIT_SLOT_POINTS
	if g.phase == "play":
		s += _option_value(g)
	return s


## Held grafts by GRAFT_WEIGHTS - the term that makes a shrine graft worth
## its bloom to the search.
func _graft_value(g) -> float:
	var v := 0.0
	for gid in g.player["grafts"]:
		v += float(GRAFT_WEIGHTS.get(String(gid), 0)) * GRAFT_POINTS
	return v


## Sum of the option-value terms (see _option_terms).
func _option_value(g) -> float:
	var t := _option_terms(g)
	var v := 0.0
	for k in t:
		v += float(t[k])
	return v


## Layer 1, one entry per term, each computed only when the kit holds the op
## it pays for. Read from the live clone `g` (player, enemies, terrain, map).
##   spike:  a "damage" op targeting enemy_near_growth - SPIKE_POINTS per
##           enemy the sim's own targeting lists (standing on growth or
##           orthogonally beside it, within range), cap SPIKE_CAP
##   ignite: a lance or aoe_damage op with ignite - IGNITE_POINTS per
##           flammable tile inside the op's reach with an enemy on it or
##           beside it, cap IGNITE_CAP
##   pin:    a DISPLACE_OPS op - PIN_POINTS per enemy that the op could move
##           and that stands beside a non-open tile along that line (wall,
##           roots, another enemy), cap PIN_CAP
##   surge:  SURGE_POINTS when the player stands on growth and holds an
##           ability whose surge dict would apply (_surge_applies: a cost
##           delta that lowers a cost-2+ cast, or any stat delta - the sim's
##           own rule, Game._surges)
##   roots:  ROOTS_POINTS when roots stand beside an enemy and a PUSH_OPS
##           op is held
func _option_terms(g) -> Dictionary:
	var t := {"spike": 0.0, "ignite": 0.0, "pin": 0.0, "surge": 0.0, "roots": 0.0}
	var kit: Array = g.player["kit"]
	var on_growth: bool = String(g.terrain.get(g.player["pos"], {}).get("kind", "")) == "growth"
	var holds_push := false
	var pinned := {}
	for slot in kit.size():
		if g.player["gummed"].has(slot):
			continue
		var aid := String(kit[slot])
		var adef := _adef(aid)
		if adef.is_empty():
			continue
		if on_growth and _surge_applies(adef):
			t["surge"] = SURGE_POINTS
		for eff in adef.get("effects", []):
			var op := String(eff.get("op", ""))
			if op == "damage" and String(adef.get("target", "")) == "enemy_near_growth":
				var n: int = mini(g.ability_targets(aid).size(), SPIKE_CAP)
				t["spike"] = maxf(t["spike"], float(n) * SPIKE_POINTS)
			elif (op == "lance" or op == "aoe_damage") and bool(eff.get("ignite", false)):
				var n2: int = mini(_ignite_targets(g, adef, eff, op).size(), IGNITE_CAP)
				t["ignite"] = maxf(t["ignite"], float(n2) * IGNITE_POINTS)
			if DISPLACE_OPS.has(op):
				for id in _pinnable(g, adef, op):
					pinned[id] = true
			if PUSH_OPS.has(op):
				holds_push = true
	t["pin"] = float(mini(pinned.size(), PIN_CAP)) * PIN_POINTS
	if holds_push and _roots_beside_enemy(g):
		t["roots"] = ROOTS_POINTS
	return t


## Content.ABILITIES row for a held id, the base row when a "+" form has none.
func _adef(aid: String) -> Dictionary:
	return Content.ABILITIES.get(aid, Content.ABILITIES.get(Content.base_id(aid), {}))


## Would a cast of `adef` from growth surge at all? The row half of the sim's
## one surge rule (Game._surges, Block D1): a "cost" delta that actually
## lowers a cost-2+ cast, or any stat delta (dmg, push, radius, ...) - which
## surges whatever the cost, so a cost-1 payoff row counts as surge-ready too.
## Read from Content.SURGE_DEFAULT and the row; no ability id is named.
func _surge_applies(adef: Dictionary) -> bool:
	var surge: Dictionary = adef.get("surge", Content.SURGE_DEFAULT)
	var base := int(adef.get("cost", 0))
	if base >= 2 and maxi(1, base + int(surge.get("cost", 0))) < base:
		return true
	for k in surge:
		if String(k) != "cost":
			return true
	return false


## Flammable tiles inside an igniter's reach that carry an enemy or have one
## beside them. Lance reach: the four lines of adef.range from the player,
## stopped by a wall, a beam-blocking tile or the first enemy (which the
## beam still ignites under). aoe_damage reach: eff.radius around the player.
func _ignite_targets(g, adef: Dictionary, eff: Dictionary, op: String) -> Array:
	var out: Array = []
	var ppos: Vector2i = g.player["pos"]
	if op == "lance":
		for d in DIRS:
			var p: Vector2i = ppos
			for i in int(adef.get("range", 0)):
				p += d
				var k := _kind(g, p)
				if _wall(g, p) or bool(Content.terrain(k, "blocks_beam", false)):
					break
				if bool(Content.terrain(k, "flammable", false)) and _enemy_on_or_beside(g, p):
					out.append(p)
				if _enemy_at_tile(g, p) != null:
					break
	else:
		var radius := int(eff.get("radius", 0))
		for tile in g.terrain.keys():
			if absi(tile.x - ppos.x) + absi(tile.y - ppos.y) > radius:
				continue
			if bool(Content.terrain(_kind(g, tile), "flammable", false)) and _enemy_on_or_beside(g, tile):
				out.append(tile)
	return out


## Ids of the enemies a displacing op could move that stand beside a
## non-open tile along the line the op would move them on: away from the
## player for the shove family, toward the player for a pull (the player's
## own tile does not count as a pin for a pull - that is melee range).
func _pinnable(g, adef: Dictionary, op: String) -> Array:
	var out: Array = []
	var ppos: Vector2i = g.player["pos"]
	var rng_ := int(adef.get("range", 0))
	match op:
		"push_line", "wash_push", "wash_all":
			for d in DIRS:
				var p: Vector2i = ppos
				for i in rng_:
					p += d
					if _wall(g, p):
						break
					var e = _enemy_at_tile(g, p)
					if e != null:
						if not _massive(e) and _blocked(g, p + d):
							out.append(e["id"])
						break
		"push_all":
			for d in DIRS:
				var e = _enemy_at_tile(g, ppos + d)
				if e != null and not _massive(e) and _blocked(g, ppos + d + d):
					out.append(e["id"])
		"pull":
			for e in g.enemies:
				var delta: Vector2i = e["pos"] - ppos
				if delta.x != 0 and delta.y != 0:
					continue
				var dist: int = absi(delta.x) + absi(delta.y)
				if dist <= 1 or dist > rng_ or _massive(e):
					continue
				var dir := Vector2i(-signi(delta.x), -signi(delta.y))
				var nxt: Vector2i = e["pos"] + dir
				if nxt != ppos and _blocked(g, nxt):
					out.append(e["id"])
	return out


func _roots_beside_enemy(g) -> bool:
	for e in g.enemies:
		for d in DIRS:
			if bool(Content.terrain(_kind(g, e["pos"] + d), "blocks", false)):
				return true
	return false


# --- board reads on a live game -----------------------------------------------

func _kind(g, p: Vector2i) -> String:
	return String(g.terrain.get(p, {}).get("kind", ""))


func _wall(g, p: Vector2i) -> bool:
	var m: Dictionary = g.map
	if p.x < 0 or p.y < 0 or p.x >= int(m["w"]) or p.y >= int(m["h"]):
		return true
	return int(m["tiles"][p.y * int(m["w"]) + p.x]) != 1


## Non-open for a shove: a wall, the player, an enemy, or blocking terrain.
func _blocked(g, p: Vector2i) -> bool:
	if _wall(g, p) or p == g.player["pos"] or _enemy_at_tile(g, p) != null:
		return true
	return bool(Content.terrain(_kind(g, p), "blocks", false))


func _enemy_at_tile(g, p: Vector2i) -> Variant:
	for e in g.enemies:
		if e["pos"] == p:
			return e
	return null


func _enemy_on_or_beside(g, p: Vector2i) -> bool:
	if _enemy_at_tile(g, p) != null:
		return true
	for d in DIRS:
		if _enemy_at_tile(g, p + d) != null:
			return true
	return false


func _massive(e: Dictionary) -> bool:
	return Content.ENEMIES[e["kind"]]["traits"].has("massive")


# --- shrine routing -----------------------------------------------------------

## The shrine is the goal while the player is off it, no enemy is within
## SHRINE_SAFE_RADIUS and bloom covers the cheapest useful buy; otherwise
## deeproot's stairs / corruption / boss goal as before.
func _refresh_field(snap: Dictionary) -> void:
	var goal := _shrine_goal(snap)
	if goal == NO_GOAL:
		super._refresh_field(snap)
		return
	if int(snap["floor"]) == _field_floor and goal == _field_goal:
		return
	_field_floor = int(snap["floor"])
	_field_goal = goal
	_field = {}
	_field[goal] = 0
	var m: Dictionary = snap["map"]
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


## The shrine tile when a detour is worth it, else NO_GOAL.
func _shrine_goal(snap: Dictionary) -> Vector2i:
	var shrine: Vector2i = snap["map"]["shrine"]
	if shrine == Vector2i(-1, -1) or snap["player"]["pos"] == shrine:
		return NO_GOAL
	var floor_n := int(snap["floor"])
	if floor_n == _shrine_abandoned_floor:
		return NO_GOAL
	# past the floor's choke the clock bites every turn: no shopping detours
	if _sim != null and int(snap["smog"]) >= int(_sim.floor_def(floor_n).get("smog_choke", 0)) \
			and int(_sim.floor_def(floor_n).get("smog_choke", 0)) > 0:
		return NO_GOAL
	if _enemies_within(snap, SHRINE_SAFE_RADIUS) > 0:
		if _field_floor == floor_n and _field_goal == shrine:
			_shrine_abandoned_floor = floor_n
		return NO_GOAL
	var cheapest := _cheapest_useful_buy(snap)
	if cheapest < 0 or int(snap["bloom"]) < cheapest:
		return NO_GOAL
	return shrine


## Cost of the cheapest useful buy at the snapshot's shop: a graft the search
## would take (its weight clears its own price), an ability while the kit has
## room, a heal while hp is below max. -1 when nothing useful is stocked.
## Costs come from the live game's shop_cost (a graft is priced from its own
## Content.GRAFTS row, plus the per-graft-owned step and the tier markup);
## without a live game, the base price list.
func _cheapest_useful_buy(snap: Dictionary) -> int:
	var shop: Dictionary = snap.get("shop", {})
	var pl: Dictionary = snap["player"]
	var best := -1
	if shop.has("grafts"):
		# the two offers are priced apart, so the detour question is "is any
		# offer worth its own price", not "is the best offer worth the flat
		# graft price": a Solar Core at 8 the purse cannot cover is no reason
		# to walk, a 3-bloom stat graft that clears its price is
		var offers: Array = shop["grafts"]
		var prices: Array = shop.get("graft_prices", [])
		for i in offers.size():
			var gid := String(offers[i])
			var cost: int = int(prices[i]) if i < prices.size() else _shop_cost("graft", gid)
			if _graft_worth(gid, cost) and (best < 0 or cost < best):
				best = cost
	# the ability and heal branches apply the same worth test the search
	# does (bloom scores 4 per point), or the routing walks to a shrine the
	# search then refuses to spend at and flips back to the stairs
	if shop.has("ability") and pl["kit"].size() < _kit_max(snap):
		var cost2 := _shop_cost("ability")
		if KIT_SLOT_POINTS > float(cost2) * 4.0 and (best < 0 or cost2 < best):
			best = cost2
	if bool(shop.get("heal", false)) and int(pl["hp"]) < int(pl["max_hp"]):
		var cost3 := _shop_cost("heal")
		var missing: int = mini(int(pl["max_hp"]) - int(pl["hp"]), Content.SHOP_HEAL_AMOUNT)
		if 40.0 * float(missing) > float(cost3) * 4.0 and (best < 0 or cost3 < best):
			best = cost3
	return best


## Price of one shrine offer. `id` names the specific offer and matters only
## for grafts, which the sim prices from their own Content.GRAFTS row; without
## a live game the bare row price (no owned-graft step, no tier markup) is the
## best the snapshot alone can say.
func _shop_cost(item: String, id: String = "") -> int:
	if _sim != null:
		return int(_sim.shop_cost(item, id))
	if item == "graft" and Content.GRAFTS.has(id):
		return int(Content.GRAFTS[id].get("price", Content.SHOP_COSTS.get(item, 9999)))
	return int(Content.SHOP_COSTS.get(item, 9999))


## Kit cap under the snapshot's mutators (Content.MUTATORS config, first hit).
func _kit_max(snap: Dictionary) -> int:
	for m in snap.get("mutators", []):
		var cfg: Dictionary = Content.MUTATORS.get(String(m), {}).get("config", {})
		if cfg.has("kit_max"):
			return int(cfg["kit_max"])
	return Content.KIT_MAX


## Would the search buy this graft at `cost` bloom: its term clears the
## bloom term it gives up (bloom scores 4 per point in the inherited _score).
func _graft_worth(gid: String, cost: int) -> bool:
	return float(GRAFT_WEIGHTS.get(gid, 0)) * GRAFT_POINTS > float(cost) * 4.0
