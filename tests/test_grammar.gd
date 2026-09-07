extends SceneTree
## Effect grammar checks (docs/PROGRESSION_REVIEW.md §6.3, Block C1a/C1b): the
## rider vocabulary (if / per / bonus / then), returned outcomes, and the data
## tables (Content.TERRAIN / REACTIONS / STATUSES / surge) are exercised with
## hand-built effect dicts passed straight to Game._apply_effect on controlled
## states, plus the C1b rows: ash, the root cooldown and blocked advance/drag,
## spore add-stacking, items through _apply_status, spread fire inheriting
## the bloom flag. The Block C2 content rows (grow_spike(+), sun_flare(+),
## water_jet+, vine_whip+, seed_bomb+) are cast for real through Game.step on
## controlled boards and their numbers, statuses and rider events asserted.
## Block C3: the hook dispatcher (Game._hook) is exercised through the four
## rule grafts installed via config {grafts: [...]} (ember_sap, undertow,
## compost, oil_tithe), the depth / step caps, and the _graft_stat /
## _graft_mod table reads that replaced the six _has_graft sites.
## Block C4: the nine package "+" rows (spore_cloud+, fungal_ring+, burrow+,
## tide+, steam_vent+, geyser+, gust+, updraft+, clear_air+) are cast for real
## through Game.step next to their bases: the bumped number and any rider
## asserted, costs pinned. Also C4: effective casts (Game.effective_uses, a
## use whose outcome fired or whose rider ran) against raw player.uses, the
## run_summary() shape, and mutators as data - Game._mut over
## Content.MUTATORS[m]["config"]: the six legacy rows reproduce their numbers,
## no_lance / wide_draft / upgrades_only hold their invariants on fresh games.
## Block D1: per-ability stat surges and Spore Trail. Every surged row
## (grow_spike(+), water_jet(+), sun_flare(+), seed_bomb+) is cast for real
## through Game.step standing on growth and off it: the stat delta, the
## consumed tile (verdant), the {t: surge} event and the unchanged cost are
## asserted; a cost-1 row with the default surge never consumes growth;
## grow_radius reads its radius key (1 = the old plus, 2 = the 13-tile
## diamond); mycelium_dash+ plants the departure tile through plant_origin
## only when it is bare floor with nobody on it, and that cast is effective.
## Run: godot --headless --path . --script tests/test_grammar.gd

const Content := preload("res://sim/content.gd")
const Game := preload("res://sim/game.gd")

## 11 x 7 room, player at (5, 3). Every interior tile is floor.
const ROOM := [
	"###########",
	"#.........#",
	"#.........#",
	"#....@....#",
	"#.........#",
	"#.........#",
	"###########",
]

var checks := 0
var failures: Array = []


func _init() -> void:
	_check_if_predicates()
	_check_per_counts()
	_check_bonus()
	_check_then()
	_check_outcomes()
	_check_surge_identity()
	_check_terrain_helpers()
	_check_statuses()
	_check_reactions()
	_check_ash()
	_check_root_cooldown()
	_check_spore_stack()
	_check_items_through_table()
	_check_context_counters()
	_check_c2_grow_spike()
	_check_c2_sun_flare()
	_check_c2_water_jet()
	_check_c2_vine_whip()
	_check_c2_seed_bomb()
	_check_c3_graft_tables()
	_check_c3_ember_sap()
	_check_c3_undertow()
	_check_c3_compost()
	_check_c3_oil_tithe()
	_check_c3_hook_caps()
	_check_c4_spore_cloud()
	_check_c4_fungal_ring()
	_check_c4_burrow()
	_check_c4_tide()
	_check_c4_steam_vent()
	_check_c4_geyser()
	_check_c4_gust()
	_check_c4_updraft()
	_check_c4_clear_air()
	_check_c4_effective_uses()
	_check_c4_run_summary()
	_check_c4_mutator_config()
	_check_d1_surge_rule()
	_check_d1_grow_spike()
	_check_d1_water_jet()
	_check_d1_sun_flare()
	_check_d1_seed_bomb()
	_check_d1_grow_radius()
	_check_d1_spore_trail()
	if failures.is_empty():
		print("grammar: OK (%d checks)" % checks)
		quit(0)
	else:
		for f in failures:
			print("FAIL: %s" % f)
		print("grammar: %d failure(s) in %d checks" % [failures.size(), checks])
		quit(1)


func _ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append(msg)


# --- fixtures -----------------------------------------------------------------

static func _gen(rows: Array) -> Dictionary:
	var h := rows.size()
	var w := String(rows[0]).length()
	var tiles: Array = []
	tiles.resize(w * h)
	tiles.fill(0)
	var gen := {
		"w": w, "h": h, "tiles": tiles, "start": Vector2i(1, 1),
		"stairs": Vector2i(-1, -1), "shrine": Vector2i(-1, -1),
		"vents": [], "terrain": {}, "enemies": [], "rooms": [],
	}
	for y in h:
		var row := String(rows[y])
		for x in w:
			var ch := row[x]
			tiles[y * w + x] = 0 if ch == "#" else 1
			if ch == "@":
				gen["start"] = Vector2i(x, y)
	return gen


## A fresh game on ROOM with the given kit; no enemies, no terrain.
static func _game(kit: Array = ["solar_lance", "seed_bomb", "mycelium_dash"]) -> RefCounted:
	return Game.new(1, {"fixed_floor": {"gen": _gen(ROOM), "fdef": {}}, "kit": kit})


## Cast context as _act_ability builds it. `adef` may be an ability id or a
## hand-built ability dict.
static func _ctx(g, adef, target) -> Dictionary:
	var d: Dictionary = Content.ABILITIES[adef] if adef is String else adef
	return {
		"aid": "probe", "adef": d, "target": target, "origin": g.player["pos"],
		"casts_before": g.casts_this_turn, "moved": g.moved_this_turn,
	}


## Run one hand-built effect; returns [outcome, events emitted by the call].
static func _run(g, eff: Dictionary, adef, target) -> Array:
	var d: Dictionary = Content.ABILITIES[adef] if adef is String else adef
	g._step_events = []
	var out: Dictionary = g._apply_effect(eff, d, target, "probe", _ctx(g, d, target))
	return [out, g._step_events.duplicate(true)]


static func _evs(events: Array, t: String) -> Array:
	var outl: Array = []
	for ev in events:
		if String(ev.get("t", "")) == t:
			outl.append(ev)
	return outl


static func _riders(events: Array, kind: String) -> Array:
	var outl: Array = []
	for ev in _evs(events, "rider"):
		if String(ev.get("kind", "")) == kind:
			outl.append(ev)
	return outl


const TILE_ADEF := {"target": "tile", "range": 3, "cost": 1}
const DIR_ADEF := {"target": "dir", "range": 3, "cost": 1}
const SELF_ADEF := {"target": "self", "range": 2, "cost": 1}


# --- if -----------------------------------------------------------------------

func _check_if_predicates() -> void:
	# target_on: the enemy's tile carries oil -> runs; bare floor -> skipped
	var g = _game()
	var e = g._spawn("drill_bot", Vector2i(7, 3))
	var eff := {"op": "damage", "dmg": 1, "if": [{"target_on": ["oil"]}]}
	var r := _run(g, eff, TILE_ADEF, Vector2i(7, 3))
	_ok(r[0]["hit"] == 0 and e["hp"] == 3 and r[1].is_empty(), "if target_on false: %s %s" % [str(r[0]), str(r[1])])
	g.terrain[Vector2i(7, 3)] = {"kind": "oil"}
	r = _run(g, eff, TILE_ADEF, Vector2i(7, 3))
	_ok(r[0]["hit"] == 1 and e["hp"] == 2 and r[0]["affected"] == [e["id"]], "if target_on true: %s" % str(r[0]))
	_ok(_evs(r[1], "rider").is_empty(), "a plain if emits no rider event: %s" % str(r[1]))
	# several kinds in the list, AND across dicts
	g.terrain[Vector2i(7, 3)] = {"kind": "goo"}
	r = _run(g, {"op": "damage", "dmg": 1, "if": [{"target_on": ["oil", "goo"]}, {"dim": 0}]}, TILE_ADEF, Vector2i(7, 3))
	_ok(r[0]["hit"] == 1, "if list membership + AND across dicts: %s" % str(r[0]))
	r = _run(g, {"op": "damage", "dmg": 1, "if": [{"target_on": ["oil", "goo"], "dim": 1}]}, TILE_ADEF, Vector2i(7, 3))
	_ok(r[0]["hit"] == 0, "if AND across keys fails on dim: %s" % str(r[0]))
	# dir target: the tile of the first enemy the op would reach; none -> false
	g.terrain.erase(Vector2i(7, 3))
	g.terrain[Vector2i(7, 3)] = {"kind": "oil"}
	var lance := {"op": "lance", "dmg": 1, "clear_smog_bonus": 0, "ignite": false, "if": [{"target_on": ["oil"]}]}
	r = _run(g, lance, DIR_ADEF, Vector2i(1, 0))
	_ok(r[0]["hit"] == 1, "if target_on resolves a dir target to the first enemy's tile: %s" % str(r[0]))
	r = _run(g, lance, DIR_ADEF, Vector2i(-1, 0))
	_ok(r[0]["hit"] == 0 and r[1].is_empty(), "if target_on on an empty dir line is false: %s" % str(r[0]))
	# target_adjacent
	var g2 = _game()
	var e2 = g2._spawn("drill_bot", Vector2i(7, 3))
	e2["hp"] = 20
	var adj := {"op": "damage", "dmg": 1, "if": [{"target_adjacent": ["growth"]}]}
	r = _run(g2, adj, TILE_ADEF, Vector2i(7, 3))
	_ok(r[0]["hit"] == 0, "if target_adjacent false: %s" % str(r[0]))
	g2.terrain[Vector2i(7, 2)] = {"kind": "growth"}
	r = _run(g2, adj, TILE_ADEF, Vector2i(7, 3))
	_ok(r[0]["hit"] == 1 and e2["hp"] == 19, "if target_adjacent true: %s" % str(r[0]))
	# self_on
	var selfp := {"op": "damage", "dmg": 1, "if": [{"self_on": "growth"}]}
	r = _run(g2, selfp, TILE_ADEF, Vector2i(7, 3))
	_ok(r[0]["hit"] == 0, "if self_on false: %s" % str(r[0]))
	g2.terrain[g2.player["pos"]] = {"kind": "growth"}
	r = _run(g2, selfp, TILE_ADEF, Vector2i(7, 3))
	_ok(r[0]["hit"] == 1, "if self_on true: %s" % str(r[0]))
	# dim (exact)
	g2.dim = 1
	r = _run(g2, {"op": "damage", "dmg": 1, "if": [{"dim": 1}]}, TILE_ADEF, Vector2i(7, 3))
	_ok(r[0]["hit"] == 1, "if dim exact true: %s" % str(r[0]))
	r = _run(g2, {"op": "damage", "dmg": 1, "if": [{"dim": 2}]}, TILE_ADEF, Vector2i(7, 3))
	_ok(r[0]["hit"] == 0, "if dim exact false: %s" % str(r[0]))
	# casts_this_turn_min reads ctx.casts_before
	g2.casts_this_turn = 2
	r = _run(g2, {"op": "damage", "dmg": 1, "if": [{"casts_this_turn_min": 2}]}, TILE_ADEF, Vector2i(7, 3))
	_ok(r[0]["hit"] == 1, "if casts_this_turn_min 2 with 2 casts: %s" % str(r[0]))
	r = _run(g2, {"op": "damage", "dmg": 1, "if": [{"casts_this_turn_min": 3}]}, TILE_ADEF, Vector2i(7, 3))
	_ok(r[0]["hit"] == 0, "if casts_this_turn_min 3 with 2 casts: %s" % str(r[0]))
	# outcome predicates outside a then fail closed; unknown keys fail closed
	r = _run(g2, {"op": "damage", "dmg": 1, "if": [{"outcome": "hit"}]}, TILE_ADEF, Vector2i(7, 3))
	_ok(r[0]["hit"] == 0, "if outcome outside then is false: %s" % str(r[0]))
	r = _run(g2, {"op": "damage", "dmg": 1, "if": [{"no_such_pred": 1}]}, TILE_ADEF, Vector2i(7, 3))
	_ok(r[0]["hit"] == 0, "unknown predicate fails closed: %s" % str(r[0]))


# --- per ----------------------------------------------------------------------

func _check_per_counts() -> void:
	# growth_adjacent_target, cap respected, add applied, rider amt = total added
	var g = _game()
	var e = g._spawn("drill_bot", Vector2i(7, 3))
	e["hp"] = 20
	for t in [Vector2i(7, 2), Vector2i(7, 4), Vector2i(8, 3)]:
		g.terrain[t] = {"kind": "growth"}
	var eff := {"op": "damage", "dmg": 1, "per": {"count": "growth_adjacent_target", "cap": 2, "add": {"dmg": 1}}}
	var r := _run(g, eff, TILE_ADEF, Vector2i(7, 3))
	var dmg_evs := _evs(r[1], "damage")
	_ok(dmg_evs.size() == 1 and int(dmg_evs[0]["amt"]) == 3 and e["hp"] == 17, "per growth_adjacent_target cap 2: %s" % str(dmg_evs))
	var pr := _riders(r[1], "per")
	_ok(pr.size() == 1 and int(pr[0]["amt"]) == 2 and pr[0]["id"] == "probe", "per rider event amt 2: %s" % str(pr))
	_ok(eff["dmg"] == 1, "per never mutates the content dict")
	# no cap: all three count
	r = _run(g, {"op": "damage", "dmg": 1, "per": {"count": "growth_adjacent_target", "cap": 0, "add": {"dmg": 1}}}, TILE_ADEF, Vector2i(7, 3))
	_ok(int(_evs(r[1], "damage")[0]["amt"]) == 4, "per uncapped (cap 0) counts all 3: %s" % str(_evs(r[1], "damage")))
	# count 0: no rider event, base numbers
	r = _run(g, eff, TILE_ADEF, Vector2i(6, 3))
	_ok(_riders(r[1], "per").is_empty() and r[0]["hit"] == 0, "per with count 0 emits nothing: %s" % str(r[1]))
	# fire_within_self (radius from per)
	var g2 = _game()
	var e2 = g2._spawn("drill_bot", Vector2i(6, 3))
	e2["hp"] = 20
	g2.terrain[Vector2i(5, 1)] = {"kind": "fire", "ttl": 2}   # distance 2
	g2.terrain[Vector2i(4, 4)] = {"kind": "fire", "ttl": 2}   # distance 2
	g2.terrain[Vector2i(8, 3)] = {"kind": "fire", "ttl": 2}   # distance 3: outside radius 2
	r = _run(g2, {"op": "damage", "dmg": 1, "per": {"count": "fire_within_self", "radius": 2, "cap": 5, "add": {"dmg": 1}}}, TILE_ADEF, Vector2i(6, 3))
	_ok(int(_evs(r[1], "damage")[0]["amt"]) == 3 and _riders(r[1], "per")[0]["amt"] == 2, "per fire_within_self radius 2 -> +2: %s" % str(r[1]))
	# oil_in_line: oil tiles along the dir up to adef.range
	var g3 = _game()
	var e3 = g3._spawn("drill_bot", Vector2i(8, 3))
	e3["hp"] = 20
	g3.terrain[Vector2i(6, 3)] = {"kind": "oil"}
	g3.terrain[Vector2i(7, 3)] = {"kind": "oil"}
	g3.terrain[Vector2i(9, 3)] = {"kind": "oil"}  # beyond range 3
	var lance := {"op": "lance", "dmg": 1, "clear_smog_bonus": 0, "ignite": false,
		"per": {"count": "oil_in_line", "cap": 5, "add": {"dmg": 1}}}
	r = _run(g3, lance, DIR_ADEF, Vector2i(1, 0))
	_ok(int(_evs(r[1], "damage")[0]["amt"]) == 3 and e3["hp"] == 17, "per oil_in_line 2 oil in range 3 -> +2: %s" % str(r[1]))
	_ok(g3.terrain.has(Vector2i(6, 3)) and g3.terrain[Vector2i(6, 3)]["kind"] == "oil", "ignite false leaves the oil")
	# enemies_adjacent_target
	var g4 = _game()
	var e4 = g4._spawn("drill_bot", Vector2i(7, 3))
	e4["hp"] = 20
	g4._spawn("drill_bot", Vector2i(7, 2))
	g4._spawn("drill_bot", Vector2i(8, 3))
	r = _run(g4, {"op": "damage", "dmg": 1, "per": {"count": "enemies_adjacent_target", "cap": 5, "add": {"dmg": 2}}}, TILE_ADEF, Vector2i(7, 3))
	_ok(int(_evs(r[1], "damage")[0]["amt"]) == 5 and _riders(r[1], "per")[0]["amt"] == 4, "per enemies_adjacent_target 2 x add 2 -> +4: %s" % str(r[1]))
	# unknown count reads as 0
	r = _run(g4, {"op": "damage", "dmg": 1, "per": {"count": "no_such_count", "cap": 5, "add": {"dmg": 2}}}, TILE_ADEF, Vector2i(7, 3))
	_ok(int(_evs(r[1], "damage")[0]["amt"]) == 1 and _riders(r[1], "per").is_empty(), "unknown per count adds nothing")


# --- bonus --------------------------------------------------------------------

func _check_bonus() -> void:
	var bonus := {"dmg": 2, "if": [{"target_on": ["oil"]}]}
	# aoe_damage: per-enemy, only the one on oil gets the bonus
	var g = _game()
	var on_oil = g._spawn("drill_bot", Vector2i(6, 3))
	var off_oil = g._spawn("drill_bot", Vector2i(4, 3))
	on_oil["hp"] = 20
	off_oil["hp"] = 20
	g.terrain[Vector2i(6, 3)] = {"kind": "oil"}
	var r := _run(g, {"op": "aoe_damage", "dmg": 1, "radius": 2, "bonus": bonus}, SELF_ADEF, g.player["pos"])
	_ok(on_oil["hp"] == 17 and off_oil["hp"] == 19, "bonus aoe_damage per enemy: %d %d" % [on_oil["hp"], off_oil["hp"]])
	var br := _riders(r[1], "bonus")
	_ok(br.size() == 1 and int(br[0]["amt"]) == 2, "bonus rider event once, amt 2: %s" % str(br))
	_ok(r[0]["hit"] == 2 and r[0]["affected"].size() == 2, "aoe outcome hit 2: %s" % str(r[0]))
	# lance
	var g2 = _game()
	var e2 = g2._spawn("drill_bot", Vector2i(7, 3))
	e2["hp"] = 20
	g2.terrain[Vector2i(7, 3)] = {"kind": "oil"}
	r = _run(g2, {"op": "lance", "dmg": 1, "clear_smog_bonus": 0, "ignite": false, "bonus": bonus}, DIR_ADEF, Vector2i(1, 0))
	_ok(e2["hp"] == 17 and _riders(r[1], "bonus").size() == 1, "bonus lance on oil: hp %d" % e2["hp"])
	g2.terrain.erase(Vector2i(7, 3))
	r = _run(g2, {"op": "lance", "dmg": 1, "clear_smog_bonus": 0, "ignite": false, "bonus": bonus}, DIR_ADEF, Vector2i(1, 0))
	_ok(e2["hp"] == 16 and _riders(r[1], "bonus").is_empty(), "bonus lance off oil: hp %d" % e2["hp"])
	# damage op
	var g3 = _game()
	var e3 = g3._spawn("drill_bot", Vector2i(7, 3))
	e3["hp"] = 20
	g3.terrain[Vector2i(7, 3)] = {"kind": "oil"}
	r = _run(g3, {"op": "damage", "dmg": 1, "bonus": bonus}, TILE_ADEF, Vector2i(7, 3))
	_ok(e3["hp"] == 17 and _riders(r[1], "bonus").size() == 1, "bonus damage op: hp %d" % e3["hp"])
	# collision: the pushed enemy lands on oil against the wall, then collides
	var g4 = _game()
	var e4 = g4._spawn("drill_bot", Vector2i(8, 3))
	e4["hp"] = 20
	g4.terrain[Vector2i(9, 3)] = {"kind": "oil"}
	r = _run(g4, {"op": "push_line", "dist": 3, "bonus": bonus}, DIR_ADEF, Vector2i(1, 0))
	var dmg_evs := _evs(r[1], "damage")
	_ok(e4["pos"] == Vector2i(9, 3) and dmg_evs.size() == 1 and int(dmg_evs[0]["amt"]) == 3 and dmg_evs[0]["src"] == "collision:probe",
		"bonus collision (push_line): %s %s" % [str(e4["pos"]), str(dmg_evs)])
	_ok(r[0]["pushed"] == 1 and r[0]["collided"] == 1 and r[0]["crossed"] == ["oil"], "push outcome pushed/collided/crossed: %s" % str(r[0]))
	# collision via wash (wash_push) gets the bonus too; the wash strips the oil
	# in its own line, so the bonus reads the tile the enemy lands on
	var g5 = _game()
	var e5 = g5._spawn("drill_bot", Vector2i(6, 3))
	e5["hp"] = 20
	g5.terrain[Vector2i(9, 3)] = {"kind": "oil"}
	r = _run(g5, {"op": "wash_push", "push": 4, "collision_dmg": 1, "bonus": bonus}, DIR_ADEF, Vector2i(1, 0))
	dmg_evs = _evs(r[1], "damage")
	_ok(e5["pos"] == Vector2i(9, 3) and dmg_evs.size() == 1 and int(dmg_evs[0]["amt"]) == 3, "bonus collision (wash_push): %s" % str(dmg_evs))


# --- then ---------------------------------------------------------------------

func _check_then() -> void:
	var then_stun := [{"op": "status_target", "status": "stun", "turns": 1}]
	# parent with a zero outcome: then does not run
	var g = _game()
	var e = g._spawn("drill_bot", Vector2i(7, 3))
	var r := _run(g, {"op": "damage", "dmg": 1, "then": then_stun}, TILE_ADEF, Vector2i(6, 3))
	_ok(r[1].is_empty() and int(e["status"].get("stun", 0)) == 0, "then skipped on zero outcome: %s" % str(r[1]))
	# parent hit: then runs once, statuses the affected enemy, emits rider/then amt 1
	r = _run(g, {"op": "damage", "dmg": 1, "then": then_stun}, TILE_ADEF, Vector2i(7, 3))
	var tr := _riders(r[1], "then")
	_ok(int(e["status"].get("stun", 0)) == 1 and tr.size() == 1 and int(tr[0]["amt"]) == 1, "then status_target affected: %s %s" % [str(e["status"]), str(tr)])
	_ok(_evs(r[1], "status").size() == 1, "status event from the then: %s" % str(r[1]))
	# then sees the parent outcome: outcome hit passes, outcome pushed fails
	var g2 = _game()
	var e2 = g2._spawn("drill_bot", Vector2i(7, 3))
	e2["hp"] = 20
	r = _run(g2, {"op": "damage", "dmg": 1, "then": [
		{"op": "status_target", "status": "root", "turns": 2, "if": [{"outcome": "hit"}]},
		{"op": "status_target", "status": "stun", "turns": 1, "if": [{"outcome": "pushed"}]},
	]}, TILE_ADEF, Vector2i(7, 3))
	_ok(int(e2["status"].get("root", 0)) == 2 and int(e2["status"].get("stun", 0)) == 0, "then if outcome hit/pushed: %s" % str(e2["status"]))
	_ok(_riders(r[1], "then").size() == 1, "only the then that ran emits rider/then: %s" % str(_riders(r[1], "then")))
	# outcome_crossed: a pull drags the enemy over fire
	var g3 = _game()
	var e3 = g3._spawn("drill_bot", Vector2i(8, 3))
	e3["hp"] = 20
	g3.terrain[Vector2i(7, 3)] = {"kind": "fire", "ttl": 2, "by": "solar_lance"}
	r = _run(g3, {"op": "pull", "dist": 2, "dmg": 1, "then": [
		{"op": "status_target", "status": "stun", "turns": 1, "if": [{"outcome_crossed": "fire"}]},
	]}, {"target": "enemy_line", "range": 4, "cost": 1}, Vector2i(8, 3))
	_ok(e3["pos"] == Vector2i(6, 3) and r[0]["crossed"] == ["fire"] and r[0]["pushed"] == 1 and r[0]["hit"] == 1,
		"pull outcome crossed fire: %s pos %s" % [str(r[0]), str(e3["pos"])])
	_ok(int(e3["status"].get("stun", 0)) == 1, "then if outcome_crossed fire stuns: %s" % str(e3["status"]))
	var srcs: Array = []
	for ev in _evs(r[1], "damage"):
		srcs.append(ev["src"])
	_ok(srcs == ["fire:solar_lance", "probe"], "pull damage order fire then lash: %s" % str(srcs))
	r = _run(g3, {"op": "damage", "dmg": 1, "then": [
		{"op": "status_target", "status": "root", "turns": 1, "if": [{"outcome_crossed": "fire"}]},
	]}, TILE_ADEF, Vector2i(6, 3))
	_ok(int(e3["status"].get("root", 0)) == 0, "outcome_crossed false when nothing crossed: %s" % str(e3["status"]))
	# who: on_planted - enemies standing on tiles the parent planted
	var g4 = _game()
	var planted_on = g4._spawn("drill_bot", Vector2i(8, 3))
	var bystander = g4._spawn("drill_bot", Vector2i(6, 3))
	g4.terrain[Vector2i(6, 3)] = {"kind": "oil"}   # blocks planting there
	r = _run(g4, {"op": "grow_radius", "radius": 1, "then": [
		{"op": "status_target", "status": "root", "turns": 2, "who": "on_planted"},
	]}, TILE_ADEF, Vector2i(7, 3))
	_ok(r[0]["planted"] == 4 and r[0]["tiles"].size() == 4, "grow_radius plants 4 around an oil tile: %s" % str(r[0]))
	_ok(int(planted_on["status"].get("root", 0)) == 2 and int(bystander["status"].get("root", 0)) == 0,
		"status_target on_planted roots only the enemy on planted growth: %s %s" % [str(planted_on["status"]), str(bystander["status"])])
	# nested then: rejected with an error event; the nested sub-effect never runs
	var g5 = _game()
	var e5 = g5._spawn("drill_bot", Vector2i(7, 3))
	e5["hp"] = 20
	r = _run(g5, {"op": "damage", "dmg": 1, "then": [
		{"op": "damage", "dmg": 5, "then": [{"op": "status_target", "status": "stun", "turns": 1}]},
	]}, TILE_ADEF, Vector2i(7, 3))
	var errs := _evs(r[1], "error")
	_ok(e5["hp"] == 19 and errs.size() == 1 and String(errs[0]["msg"]).begins_with("nested then"),
		"nested then rejected: hp %d %s" % [e5["hp"], str(errs)])
	_ok(_riders(r[1], "then").is_empty() and int(e5["status"].get("stun", 0)) == 0, "nested then runs nothing")
	# then-effects with a zero outcome still fire on a non-empty crossed list
	var g6 = _game()
	var e6 = g6._spawn("drill_bot", Vector2i(6, 3))
	e6["hp"] = 20
	g6.terrain[Vector2i(7, 3)] = {"kind": "growth"}
	r = _run(g6, {"op": "push_line", "dist": 1, "then": then_stun}, DIR_ADEF, Vector2i(1, 0))
	_ok(r[0]["crossed"] == ["growth"] and int(e6["status"].get("stun", 0)) == 1, "then on crossed: %s %s" % [str(r[0]), str(e6["status"])])


# --- outcomes -----------------------------------------------------------------

func _check_outcomes() -> void:
	var zero: Dictionary = _game()._zero_outcome()
	# ops that never touch enemies return the zero outcome
	var g = _game()
	var r := _run(g, {"op": "shield", "amount": 2}, SELF_ADEF, g.player["pos"])
	_ok(r[0] == zero and g.player["shield"] == 2, "shield returns a zero outcome: %s" % str(r[0]))
	r = _run(g, {"op": "teleport"}, TILE_ADEF, Vector2i(3, 3))
	_ok(r[0] == zero and g.player["pos"] == Vector2i(3, 3), "teleport returns a zero outcome")
	# push into a wall: collided 1, pushed 1 (moved), crossed the oil it slid over
	var g2 = _game()
	var e2 = g2._spawn("drill_bot", Vector2i(7, 3))
	e2["hp"] = 20
	g2.terrain[Vector2i(8, 3)] = {"kind": "oil"}
	r = _run(g2, {"op": "push_line", "dist": 3}, DIR_ADEF, Vector2i(1, 0))
	_ok(r[0]["pushed"] == 1 and r[0]["collided"] == 1 and r[0]["crossed"] == ["oil"] and r[0]["affected"] == [e2["id"]],
		"push outcome: %s" % str(r[0]))
	_ok(e2["pos"] == Vector2i(9, 3) and e2["hp"] == 19 and _evs(r[1], "staggered").size() == 1, "push moved 2, hit the wall, staggered")
	# push into another enemy: both take collision damage, collided 2
	var g3 = _game()
	var a = g3._spawn("drill_bot", Vector2i(6, 3))
	var b = g3._spawn("drill_bot", Vector2i(7, 3))
	a["hp"] = 20
	b["hp"] = 20
	r = _run(g3, {"op": "push_all", "dist": 2}, SELF_ADEF, g3.player["pos"])
	_ok(r[0]["collided"] == 2 and r[0]["pushed"] == 0 and r[0]["affected"] == [a["id"], b["id"]] and a["hp"] == 19 and b["hp"] == 19,
		"push into an enemy: %s" % str(r[0]))
	# wash: washed counts oil and fire tiles in the line, pushed threads through
	var g4 = _game()
	var e4 = g4._spawn("drill_bot", Vector2i(7, 3))
	e4["hp"] = 20
	g4.terrain[Vector2i(6, 3)] = {"kind": "oil"}
	g4.terrain[Vector2i(8, 3)] = {"kind": "fire", "ttl": 2}
	g4.terrain[Vector2i(9, 3)] = {"kind": "goo"}
	r = _run(g4, {"op": "wash_push", "push": 1, "collision_dmg": 1}, DIR_ADEF, Vector2i(1, 0))
	_ok(r[0]["washed"] == 2 and r[0]["pushed"] == 1 and r[0]["collided"] == 0 and r[0]["affected"] == [e4["id"]],
		"wash outcome washed 2 pushed 1: %s" % str(r[0]))
	_ok(not g4.terrain.has(Vector2i(6, 3)) and not g4.terrain.has(Vector2i(8, 3)) and g4.terrain.has(Vector2i(9, 3)),
		"wash removes oil and fire, never goo")
	_ok(e4["pos"] == Vector2i(8, 3) and _evs(r[1], "wash").size() == 2, "washed enemy moved 1")
	# wash against a massive enemy: no push, collision damage still lands
	var g5 = _game()
	var boss = g5._spawn("furnace_core", Vector2i(6, 3))
	r = _run(g5, {"op": "wash_push", "push": 2, "collision_dmg": 1}, DIR_ADEF, Vector2i(1, 0))
	_ok(r[0]["pushed"] == 0 and r[0]["collided"] == 1 and boss["pos"] == Vector2i(6, 3) and r[0]["affected"] == [boss["id"]],
		"wash vs massive: %s" % str(r[0]))
	# aoe_status / apply_status list the statused enemies and count them as
	# `statused` (a status that landed is an outcome a then may ride on)
	var g6 = _game()
	var e6 = g6._spawn("drill_bot", Vector2i(6, 3))
	g6._spawn("furnace_core", Vector2i(4, 3))
	r = _run(g6, {"op": "aoe_status", "status": "stun", "turns": 1, "radius": 2}, SELF_ADEF, g6.player["pos"])
	_ok(r[0]["affected"] == [e6["id"]] and int(r[0]["statused"]) == 1 and g6._outcome_fired(r[0]), "aoe_status affected (immune boss excluded), statused 1: %s" % str(r[0]))
	# convert_radius: converted + tiles; create_terrain: planted + tiles
	var g7 = _game()
	g7.terrain[Vector2i(7, 3)] = {"kind": "oil"}
	g7.terrain[Vector2i(8, 3)] = {"kind": "goo"}
	r = _run(g7, {"op": "convert_radius", "radius": 1}, {"target": "tile_any", "range": 3, "cost": 1}, Vector2i(7, 3))
	_ok(r[0]["converted"] == 2 and r[0]["tiles"] == [Vector2i(7, 3), Vector2i(8, 3)], "convert outcome: %s" % str(r[0]))
	r = _run(g7, {"op": "create_terrain", "kind": "smoke", "ttl": 3}, {"target": "tile_any", "range": 3, "cost": 1}, Vector2i(3, 3))
	_ok(r[0]["planted"] == 1 and r[0]["tiles"] == [Vector2i(3, 3)], "create_terrain outcome: %s" % str(r[0]))
	# a core-shielded boss hit is not a hit
	var g8 = _game()
	var core = g8._spawn("furnace_core", Vector2i(7, 3))
	core["hp"] = 4
	g8.terrain[Vector2i(7, 2)] = {"kind": "goo"}
	r = _run(g8, {"op": "damage", "dmg": 1}, TILE_ADEF, Vector2i(7, 3))
	_ok(r[0]["hit"] == 0 and core["hp"] == 4 and _evs(r[1], "core_shielded").size() == 1, "shielded core: hit 0: %s" % str(r[0]))
	# unknown op: error event, zero outcome
	r = _run(g8, {"op": "no_such_op"}, TILE_ADEF, Vector2i(7, 3))
	_ok(r[0] == zero and _evs(r[1], "error").size() == 1, "unknown op errors: %s" % str(r[1]))


# --- surge --------------------------------------------------------------------

func _check_surge_identity() -> void:
	var g = _game()
	var p: Vector2i = g.player["pos"]
	var bad_on := 0
	var bad_off := 0
	var with_key := 0
	for aid in Content.ABILITIES:
		if Content.ABILITIES[aid].has("surge"):
			with_key += 1
		var base := int(Content.ABILITIES[aid]["cost"])
		g.terrain.erase(p)
		if g.ability_cost(aid) != base:
			bad_off += 1
		g.terrain[p] = {"kind": "growth"}
		var want: int = base - 1 if base >= 2 else base
		if g.ability_cost(aid) != want:
			bad_on += 1
	_ok(bad_off == 0, "surge: %d abilities cost != base off growth" % bad_off)
	_ok(bad_on == 0, "surge cost: %d abilities differ from the base-1 formula on growth (no shipped row changes the cost delta)" % bad_on)
	# Block D1: exactly the seven surged rows carry the key; sun_flare(+) keeps the -1
	var keyed: Array = []
	for aid in Content.ABILITIES:
		if Content.ABILITIES[aid].has("surge"):
			keyed.append(aid)
	keyed.sort()
	var want := ["grow_spike", "grow_spike+", "seed_bomb+", "sun_flare", "sun_flare+", "water_jet", "water_jet+"]
	_ok(with_key == 7 and keyed == want, "the seven D1 rows carry a surge key: %s" % str(keyed))
	_ok(Content.ABILITIES["grow_spike"]["surge"] == {"dmg": 1} and Content.ABILITIES["grow_spike+"]["surge"] == {"dmg": 1}
		and Content.ABILITIES["water_jet"]["surge"] == {"push": 1, "collision_dmg": 1} and Content.ABILITIES["water_jet+"]["surge"] == {"push": 1, "collision_dmg": 1}
		and Content.ABILITIES["sun_flare"]["surge"] == {"cost": -1, "radius": 1} and Content.ABILITIES["sun_flare+"]["surge"] == {"cost": -1, "radius": 1}
		and Content.ABILITIES["seed_bomb+"]["surge"] == {"radius": 1}, "D1 surge dicts as specified")
	_ok(Content.SURGE_DEFAULT == {"cost": -1}, "SURGE_DEFAULT is {cost: -1}: %s" % str(Content.SURGE_DEFAULT))
	print("surge identity: %d abilities, all match base-1 on growth / base off growth" % Content.ABILITIES.size())


# --- Content.terrain / is_corruption -------------------------------------------

func _check_terrain_helpers() -> void:
	for k in ["oil", "goo", "rich_goo", "ash"]:
		_ok(Content.is_corruption(k), "is_corruption(%s)" % k)
	for k in ["growth", "fire", "smoke", "roots", "supply", "", "nope"]:
		_ok(not Content.is_corruption(k), "not is_corruption(%s)" % k)
	# counts_as_corruption: corruption, plus "pending corruption" - a fire
	# whose burns_to leaves corruption behind (only the quota clamp, the
	# floor restore and the room bloom read this)
	for k in ["oil", "goo", "rich_goo", "ash", "fire"]:
		_ok(Content.counts_as_corruption(k), "counts_as_corruption(%s)" % k)
	for k in ["growth", "smoke", "roots", "supply", "", "nope"]:
		_ok(not Content.counts_as_corruption(k), "not counts_as_corruption(%s)" % k)
	_ok(not Content.is_corruption("fire") and Content.counts_as_corruption("fire"),
		"fire is pending corruption, not corruption")
	_ok(int(Content.terrain("fire", "ttl", 0)) == 2 and int(Content.terrain("smoke", "ttl", 0)) == 3, "fire/smoke ttl rows")
	_ok(int(Content.terrain("rich_goo", "bloom", 0)) == Content.RICH_GOO_BLOOM, "rich_goo bloom row")
	_ok(Content.terrain("smoke", "blocks_beam", false) == true and Content.terrain("roots", "blocks", false) == true, "smoke blocks_beam, roots blocks")
	_ok(Content.terrain("", "blocks", false) == false and Content.terrain("nope", "x", 7) == 7, "unknown kind/key read as default")
	_ok(Content.terrain("oil", "no_such_key") == null, "unknown key with no default is null")
	var required := ["corruption", "shields_core", "flammable", "washable", "bloom", "ttl", "decays",
		"enter_dmg_player", "enter_dmg_enemy", "tick_dmg_player", "tick_dmg_enemy", "blocks", "blocks_beam", "heal", "burns_to", "convertible"]
	var missing := 0
	for k in ["oil", "goo", "rich_goo", "growth", "fire", "smoke", "roots", "supply", "ash"]:
		_ok(Content.TERRAIN.has(k), "TERRAIN has %s" % k)
		for key in required:
			if not Content.TERRAIN.get(k, {}).has(key):
				missing += 1
	_ok(missing == 0, "TERRAIN rows missing %d required keys" % missing)
	# ash row: corruption that never shields the core, washable, not flammable
	var ash: Dictionary = Content.TERRAIN["ash"]
	_ok(ash["corruption"] == true and ash["shields_core"] == false and ash["flammable"] == false and ash["washable"] == true
		and int(ash["bloom"]) == 1 and ash["decays"] == false and ash["blocks"] == false and ash["convertible"] == true,
		"ash row: %s" % str(ash))
	_ok(Content.terrain("fire", "burns_to", "") == "ash", "fire burns_to ash")
	var conv: Array = []
	for k in Content.TERRAIN:
		if bool(Content.TERRAIN[k]["convertible"]):
			conv.append(k)
	_ok(conv == ["oil", "goo", "ash"], "convertible kinds: %s" % str(conv))
	for k in Content.TERRAIN:
		if bool(Content.TERRAIN[k]["convertible"]):
			_ok(Content.is_corruption(k), "convertible %s is corruption" % k)
	_ok(not bool(Content.TERRAIN["rich_goo"]["convertible"]), "rich_goo is not convertible")
	# the lookups drive the sim: roots block, smoke stops beams, goo bites
	var g = _game()
	g.terrain[Vector2i(6, 3)] = {"kind": "roots", "ttl": 2}
	_ok(not g._open(Vector2i(6, 3)) and g._open(Vector2i(4, 3)), "roots block _open through the table")
	g.terrain[Vector2i(7, 3)] = {"kind": "smoke", "ttl": 3}
	_ok(not g._line_clear(g.player["pos"], Vector2i(9, 3)) and g._line_clear(g.player["pos"], Vector2i(2, 3)), "smoke blocks _line_clear through the table")
	g.terrain[Vector2i(4, 3)] = {"kind": "goo"}
	g.player["pos"] = Vector2i(4, 3)
	g._step_events = []
	g._player_enter_tile()
	var dmg := _evs(g._step_events, "damage")
	_ok(dmg.size() == 1 and dmg[0]["src"] == "goo" and int(dmg[0]["amt"]) == 1, "goo enter damage src goo: %s" % str(dmg))
	g.terrain[Vector2i(3, 3)] = {"kind": "fire", "ttl": 2, "by": "x"}
	g.player["pos"] = Vector2i(3, 3)
	g._step_events = []
	g._player_enter_tile()
	dmg = _evs(g._step_events, "damage")
	_ok(dmg.size() == 1 and dmg[0]["src"] == "fire", "fire enter damage src fire: %s" % str(dmg))
	# boss gate: shields_core kinds only
	_ok(g._corruption_adjacent(Vector2i(5, 3)) and not g._corruption_adjacent(Vector2i(8, 3)), "_corruption_adjacent reads shields_core")


# --- statuses -----------------------------------------------------------------

func _check_statuses() -> void:
	var g = _game()
	var e = g._spawn("drill_bot", Vector2i(6, 3))
	g._apply_status(e, "stun", 1)
	g._apply_status(e, "stun", 3)
	g._apply_status(e, "stun", 2)
	_ok(int(e["status"]["stun"]) == 3, "stun stacks by max: %s" % str(e["status"]))
	# "*" blocks every intent: an attack is swallowed, the status ticks down
	e["intent"] = {"type": "attack", "tile": g.player["pos"], "dmg": 2}
	var hp: int = g.player["hp"]
	g._step_events = []
	g._execute_intent(e)
	_ok(g.player["hp"] == hp and int(e["status"]["stun"]) == 2 and _evs(g._step_events, "stunned").size() == 1,
		"stun blocks attack: hp %d status %s events %s" % [g.player["hp"], str(e["status"]), str(g._step_events)])
	# root blocks only move: the rooted enemy still attacks
	var g2 = _game()
	var e2 = g2._spawn("drill_bot", Vector2i(6, 3))
	g2._apply_status(e2, "root", 2)
	e2["intent"] = {"type": "attack", "tile": g2.player["pos"], "dmg": 2}
	hp = g2.player["hp"]
	g2._step_events = []
	g2._execute_intent(e2)
	_ok(g2.player["hp"] == hp - 2 and int(e2["status"]["root"]) == 2, "root does not block attack: hp %d %s" % [g2.player["hp"], str(e2["status"])])
	e2["intent"] = {"type": "move"}
	e2["pos"] = Vector2i(8, 3)
	g2._step_events = []
	g2._execute_intent(e2)
	_ok(e2["pos"] == Vector2i(8, 3) and int(e2["status"]["root"]) == 1 and _evs(g2._step_events, "rooted").size() == 1,
		"root blocks move: %s %s" % [str(e2["pos"]), str(e2["status"])])
	# spore ticks in the environment phase with the status as source
	var g3 = _game()
	var e3 = g3._spawn("drill_bot", Vector2i(8, 3))
	e3["hp"] = 20
	g3._apply_status(e3, "spore", 2)
	g3._step_events = []
	g3._environment_phase()
	var dmg := _evs(g3._step_events, "damage")
	_ok(dmg.size() == 1 and dmg[0]["src"] == "spore" and int(dmg[0]["amt"]) == 1 and int(e3["status"]["spore"]) == 1,
		"spore tick: %s %s" % [str(dmg), str(e3["status"])])
	# massive enemies are immune; _apply_status reports it
	var g4 = _game()
	var boss = g4._spawn("furnace_core", Vector2i(8, 3))
	g4._step_events = []
	_ok(not g4._apply_status(boss, "stun", 1) and _evs(g4._step_events, "immune").size() == 1 and boss["status"].is_empty(), "massive immune")
	# table shape
	for sname in ["stun", "root", "spore"]:
		var sdef: Dictionary = Content.STATUSES[sname]
		_ok(["max", "add"].has(sdef.get("stack", "")) and sdef.has("blocks") and sdef.has("tick_dmg") and sdef.has("cap"), "STATUSES row %s shape" % sname)
	_ok(Content.STATUSES["stun"]["blocks"] == ["*"] and Content.STATUSES["root"]["blocks"] == ["move", "advance", "drag"] and Content.STATUSES["spore"]["blocks"] == [],
		"STATUSES blocks lists")
	_ok(Content.STATUSES["stun"]["stack"] == "max" and Content.STATUSES["root"]["stack"] == "max" and Content.STATUSES["spore"]["stack"] == "add"
		and int(Content.STATUSES["spore"]["cap"]) == 6 and int(Content.STATUSES["root"]["cooldown"]) == 2,
		"STATUSES stack/cap/cooldown rows")
	_ok(Content.STATUSES["spore"]["tick_dmg"] == 1 and Content.STATUSES["stun"]["tick_dmg"] == 0, "STATUSES tick_dmg")


# --- reactions ----------------------------------------------------------------

func _check_reactions() -> void:
	# fire_spreads: adjacent oil ignites, signed by the fire's igniter
	var g = _game()
	g.terrain[Vector2i(2, 1)] = {"kind": "fire", "ttl": 2, "by": "solar_lance"}
	g.terrain[Vector2i(3, 1)] = {"kind": "oil", "bloom": 0}
	g.terrain[Vector2i(4, 1)] = {"kind": "oil"}
	g._step_events = []
	g._environment_phase()
	_ok(g.terrain.get(Vector2i(3, 1), {}) == {"kind": "fire", "ttl": 2, "by": "solar_lance", "bloom": 0},
		"spread inherits by and the bloom flag: %s" % str(g.terrain.get(Vector2i(3, 1))))
	_ok(g.terrain[Vector2i(4, 1)]["kind"] == "oil", "spread reaches adjacent tiles only")
	_ok(int(g.terrain[Vector2i(2, 1)]["ttl"]) == 1, "source fire decayed to ttl 1")
	var ign := _evs(g._step_events, "ignite")
	_ok(ign.size() == 1 and ign[0]["tile"] == Vector2i(3, 1), "one ignite event: %s" % str(ign))
	# fire_burns_out: an expiring fire leaves ash (no ttl, no by), one ash event
	g._step_events = []
	g._environment_phase()
	_ok(g.terrain.get(Vector2i(2, 1), {}) == {"kind": "ash"} and g.terrain[Vector2i(4, 1)]["kind"] == "fire", "fire burns out to ash, second spread: %s" % str(g.terrain))
	var ashes := _evs(g._step_events, "ash")
	_ok(ashes.size() == 1 and ashes[0]["tile"] == Vector2i(2, 1), "one ash event: %s" % str(ashes))
	# a mapgen-oil fire (no flag) burns to flagless ash; the spread fire's
	# bloom-0 flag rides through to its ash
	g._environment_phase()
	g._environment_phase()
	_ok(g.terrain.get(Vector2i(3, 1), {}) == {"kind": "ash", "bloom": 0} and g.terrain.get(Vector2i(4, 1), {}) == {"kind": "ash"},
		"ash keeps the fire's bloom flag: %s %s" % [str(g.terrain.get(Vector2i(3, 1))), str(g.terrain.get(Vector2i(4, 1)))])
	# first adjacent fire in map order signs the new tile
	var g2 = _game()
	g2.terrain[Vector2i(2, 1)] = {"kind": "fire", "ttl": 2, "by": "first"}
	g2.terrain[Vector2i(4, 1)] = {"kind": "fire", "ttl": 2, "by": "second"}
	g2.terrain[Vector2i(3, 1)] = {"kind": "oil"}
	g2._environment_phase()
	_ok(g2.terrain[Vector2i(3, 1)].get("by", "") == "first", "first fire in map order signs: %s" % str(g2.terrain[Vector2i(3, 1)]))
	# an unsigned fire spreads as env
	var g3 = _game()
	g3.terrain[Vector2i(2, 1)] = {"kind": "fire", "ttl": 2}
	g3.terrain[Vector2i(3, 1)] = {"kind": "oil"}
	g3._environment_phase()
	_ok(g3.terrain[Vector2i(3, 1)].get("by", "") == "env", "unsigned fire spreads as env")
	# disabled rows do nothing: roots next to fire stay roots, smoke next to fire
	# leaves the fire, and roots/smoke still decay
	var g4 = _game()
	g4.terrain[Vector2i(2, 1)] = {"kind": "fire", "ttl": 3, "by": "x"}
	g4.terrain[Vector2i(3, 1)] = {"kind": "roots", "ttl": 2}
	g4.terrain[Vector2i(2, 2)] = {"kind": "smoke", "ttl": 3}
	g4._step_events = []
	g4._environment_phase()
	_ok(g4.terrain[Vector2i(3, 1)] == {"kind": "roots", "ttl": 1} and g4.terrain[Vector2i(2, 2)] == {"kind": "smoke", "ttl": 2},
		"disabled roots_burn/smoke_smother: %s" % str(g4.terrain))
	_ok(g4.terrain[Vector2i(2, 1)]["kind"] == "fire" and int(g4.terrain[Vector2i(2, 1)]["ttl"]) == 2, "fire survives the smoke")
	_ok(g4._step_events.is_empty(), "no events from disabled rows: %s" % str(g4._step_events))
	g4._environment_phase()
	_ok(not g4.terrain.has(Vector2i(3, 1)) and g4.terrain.has(Vector2i(2, 2)), "roots expire at ttl 0, smoke at ttl 1 stays")
	# table shape: enabled rows are exactly fire_spreads and fire_burns_out
	var enabled: Array = []
	for row in Content.REACTIONS:
		if row.get("enabled", false):
			enabled.append(row["id"])
		_ok(Content.TERRAIN.has(row["from"]) and (row.get("result", "") == "" or Content.TERRAIN.has(row["result"])),
			"REACTIONS row %s references known kinds" % row["id"])
	_ok(enabled == ["fire_spreads", "fire_burns_out"], "enabled reactions: %s" % str(enabled))
	# hazard tick still burns whoever stands in fire, with the table's numbers,
	# tiles in map (insertion) order: the player's tile was written first here
	var g5 = _game()
	var e5 = g5._spawn("drill_bot", Vector2i(8, 3))
	e5["hp"] = 20
	g5.terrain[g5.player["pos"]] = {"kind": "fire", "ttl": 2, "by": "sun_flare"}
	g5.terrain[Vector2i(8, 3)] = {"kind": "fire", "ttl": 2, "by": "sun_flare"}
	g5._step_events = []
	g5._environment_phase()
	var srcs: Array = []
	for ev in _evs(g5._step_events, "damage"):
		srcs.append([ev.get("who", ""), ev["src"], ev["amt"]])
	_ok(srcs == [["player", "fire", 1], ["drill_bot", "fire:sun_flare", 1]], "hazard tick sources: %s" % str(srcs))


# --- ash (C1b) ------------------------------------------------------------------

func _check_ash() -> void:
	# ttl expiry: fire -> {kind: ash} with the inherited bloom flag, ash events
	var g = _game()
	g.terrain[Vector2i(7, 3)] = {"kind": "fire", "ttl": 1, "by": "solar_lance", "bloom": 0}
	g.terrain[Vector2i(8, 3)] = {"kind": "fire", "ttl": 1, "by": "cinder_mite"}
	g._step_events = []
	g._environment_phase()
	_ok(g.terrain.get(Vector2i(7, 3), {}) == {"kind": "ash", "bloom": 0} and g.terrain.get(Vector2i(8, 3), {}) == {"kind": "ash"},
		"fire expiry -> ash: %s %s" % [str(g.terrain.get(Vector2i(7, 3))), str(g.terrain.get(Vector2i(8, 3)))])
	_ok(_evs(g._step_events, "ash").size() == 2, "two ash events: %s" % str(g._step_events))
	_ok(g._count_corruption() == 2, "ash counts as corruption: %d" % g._count_corruption())
	# boss gate: ash never shields the core (an enemy next to only ash is exposed)
	_ok(not g._corruption_adjacent(Vector2i(7, 2)) and not g._corruption_adjacent(Vector2i(6, 3)), "ash does not shield the core")
	var core = g._spawn("furnace_core", Vector2i(7, 2))
	core["hp"] = 4
	var r := _run(g, {"op": "damage", "dmg": 1}, TILE_ADEF, Vector2i(7, 2))
	_ok(r[0]["hit"] == 1 and core["hp"] == 3 and _evs(r[1], "core_shielded").is_empty(), "core next to ash takes the hit: %s" % str(r[0]))
	g.enemies.erase(core)
	# cleansing ash plants growth, pays per the flag, emits cleanse with kind ash
	g.player["pos"] = Vector2i(6, 3)
	g.player["charge"] = 10
	var bloom0: int = g.bloom
	var evs: Array = g.step({"type": "cleanse", "target": Vector2i(7, 3)})
	var cl := _evs(evs, "cleanse")
	_ok(cl.size() == 1 and cl[0]["kind"] == "ash" and cl[0]["tile"] == Vector2i(7, 3), "cleanse event carries kind ash: %s" % str(cl))
	_ok(g.terrain[Vector2i(7, 3)]["kind"] == "growth" and g.bloom == bloom0 and g.greened == 1, "bloom-0 ash cleanse: growth, +0 bloom, greened 1 (bloom %d)" % g.bloom)
	g.player["pos"] = Vector2i(9, 3)
	g.player["charge"] = 10
	evs = g.step({"type": "cleanse", "target": Vector2i(8, 3)})
	_ok(_evs(evs, "cleanse").size() == 1 and g.bloom == bloom0 + 1 and g.greened == 2 and g.terrain[Vector2i(8, 3)]["kind"] == "growth",
		"flagless ash cleanse pays the table's 1: bloom %d" % g.bloom)
	# cleanse of oil / goo names its kind too
	var gk = _game()
	gk.terrain[Vector2i(6, 3)] = {"kind": "goo"}
	gk.player["charge"] = 10
	var ck := _evs(gk.step({"type": "cleanse", "target": Vector2i(6, 3)}), "cleanse")
	_ok(ck.size() == 1 and ck[0]["kind"] == "goo", "cleanse event kind goo: %s" % str(ck))
	# convert_radius converts ash (table: convertible) and still not rich_goo
	var g2 = _game()
	g2.terrain[Vector2i(7, 3)] = {"kind": "ash", "bloom": 0}
	g2.terrain[Vector2i(8, 3)] = {"kind": "rich_goo"}
	g2.terrain[Vector2i(6, 3)] = {"kind": "oil"}
	r = _run(g2, {"op": "convert_radius", "radius": 1}, {"target": "tile_any", "range": 3, "cost": 1}, Vector2i(7, 3))
	_ok(r[0]["converted"] == 2 and g2.terrain[Vector2i(7, 3)]["kind"] == "growth" and g2.terrain[Vector2i(6, 3)]["kind"] == "growth"
		and g2.terrain[Vector2i(8, 3)]["kind"] == "rich_goo", "convert ash + oil, never rich_goo: %s %s" % [str(r[0]), str(g2.terrain)])
	# wash erases ash
	var g3 = _game()
	g3.terrain[Vector2i(6, 3)] = {"kind": "ash"}
	g3.terrain[Vector2i(7, 3)] = {"kind": "goo"}
	r = _run(g3, {"op": "wash_push", "push": 1, "collision_dmg": 1}, DIR_ADEF, Vector2i(1, 0))
	_ok(r[0]["washed"] == 1 and not g3.terrain.has(Vector2i(6, 3)) and g3.terrain.has(Vector2i(7, 3)), "wash erases ash, not goo: %s" % str(g3.terrain))
	# fire never spreads to ash, and ash never ignites
	var g4 = _game()
	g4.terrain[Vector2i(2, 1)] = {"kind": "fire", "ttl": 3, "by": "x"}
	g4.terrain[Vector2i(3, 1)] = {"kind": "ash"}
	g4._step_events = []
	g4._environment_phase()
	_ok(g4.terrain[Vector2i(3, 1)] == {"kind": "ash"} and _evs(g4._step_events, "ignite").is_empty(), "fire does not spread to ash: %s" % str(g4.terrain))
	r = _run(g4, {"op": "aoe_damage", "dmg": 0, "radius": 5, "ignite": true}, SELF_ADEF, g4.player["pos"])
	_ok(r[0]["ignited"] == 0 and g4.terrain[Vector2i(3, 1)]["kind"] == "ash", "ignite skips ash: %s" % str(r[0]))
	# cleanse legality: ash is a cleanse target like any corruption
	var g5 = _game()
	g5.terrain[Vector2i(6, 3)] = {"kind": "ash"}
	var can := false
	for a in g5.legal_actions():
		if String(a.get("type", "")) == "cleanse" and a.get("target", Vector2i(-1, -1)) == Vector2i(6, 3):
			can = true
	_ok(can, "cleanse of ash is a legal action")
	# ignited enemy-made oil keeps bloom 0 through fire and ash; its cleanse pays 0
	var g6 = _game()
	g6.terrain[Vector2i(6, 3)] = {"kind": "oil", "bloom": 0}
	g6.terrain[Vector2i(7, 3)] = {"kind": "oil"}
	g6._ignite(Vector2i(6, 3), "solar_lance")
	g6._ignite(Vector2i(7, 3), "solar_lance")
	_ok(g6.terrain[Vector2i(6, 3)] == {"kind": "fire", "ttl": 2, "by": "solar_lance", "bloom": 0} and g6.terrain[Vector2i(7, 3)] == {"kind": "fire", "ttl": 2, "by": "solar_lance"},
		"_ignite carries the bloom flag only when present: %s %s" % [str(g6.terrain[Vector2i(6, 3)]), str(g6.terrain[Vector2i(7, 3)])])
	g6._environment_phase()
	g6._environment_phase()
	_ok(g6.terrain[Vector2i(6, 3)] == {"kind": "ash", "bloom": 0} and g6.terrain[Vector2i(7, 3)] == {"kind": "ash"}, "burnt enemy oil is bloom-0 ash: %s" % str(g6.terrain))
	g6.player["charge"] = 10
	var b6: int = g6.bloom
	g6.step({"type": "cleanse", "target": Vector2i(6, 3)})
	_ok(g6.bloom == b6 and g6.greened == 1, "bloom-0 ash from enemy oil pays 0: %d" % g6.bloom)
	# igniter enemy walking onto enemy oil: same flag
	var g7 = _game()
	g7.terrain[Vector2i(8, 3)] = {"kind": "oil", "bloom": 0}
	var mite = g7._spawn("cinder_mite", Vector2i(8, 3))
	g7._enemy_enter_tile(mite)
	_ok(g7.terrain[Vector2i(8, 3)] == {"kind": "fire", "ttl": 2, "by": "cinder_mite", "bloom": 0}, "igniter fire carries bloom 0: %s" % str(g7.terrain[Vector2i(8, 3)]))
	# ash sits in the map's terrain like any kind: snapshot and clone keep it
	var g8 = _game()
	g8.terrain[Vector2i(6, 3)] = {"kind": "ash", "bloom": 0}
	_ok(g8.snapshot()["terrain"][Vector2i(6, 3)] == {"kind": "ash", "bloom": 0} and g8.clone().terrain[Vector2i(6, 3)] == {"kind": "ash", "bloom": 0}, "ash survives snapshot/clone")


# --- root cooldown / blocked intents (C1b) ---------------------------------------

func _check_root_cooldown() -> void:
	# drag (magnet_crane) is blocked, root ticks, root_cd was set to turns + cooldown
	var g = _game()
	var crane = g._spawn("magnet_crane", Vector2i(8, 3))
	crane["intent"] = {"type": "drag"}
	g._step_events = []
	_ok(g._apply_status(crane, "root", 2) and int(crane["status"]["root"]) == 2 and int(crane["status"]["root_cd"]) == 4,
		"root 2 lands with root_cd 4: %s" % str(crane["status"]))
	g._step_events = []
	g._execute_intent(crane)
	_ok(g.player["pos"] == Vector2i(5, 3) and int(crane["status"]["root"]) == 1 and int(crane["status"]["root_cd"]) == 3
		and _evs(g._step_events, "rooted").size() == 1 and _evs(g._step_events, "drag").is_empty(),
		"root blocks drag: %s %s" % [str(crane["status"]), str(g._step_events)])
	# re-application while root is active lands (max) and extends the cooldown
	g._step_events = []
	_ok(g._apply_status(crane, "root", 3) and int(crane["status"]["root"]) == 3 and int(crane["status"]["root_cd"]) == 5
		and _evs(g._step_events, "status").size() == 1, "re-root while active: %s" % str(crane["status"]))
	crane["status"]["root"] = 1
	crane["status"]["root_cd"] = 3
	crane["intent"] = {"type": "drag"}
	g._execute_intent(crane)
	_ok(int(crane["status"]["root"]) == 0 and int(crane["status"]["root_cd"]) == 2, "root expired, cd 2: %s" % str(crane["status"]))
	# during the cooldown a fresh root is refused with a resisted event
	g._step_events = []
	_ok(not g._apply_status(crane, "root", 2) and int(crane["status"]["root"]) == 0, "root refused during cooldown: %s" % str(crane["status"]))
	var res := _evs(g._step_events, "resisted")
	_ok(res.size() == 1 and res[0]["id"] == crane["id"] and res[0]["status"] == "root" and _evs(g._step_events, "status").is_empty(),
		"resisted event: %s" % str(g._step_events))
	# the unrooted crane drags again, and the cd runs down once per action
	crane["intent"] = {"type": "drag"}
	g._step_events = []
	g._execute_intent(crane)
	_ok(g.player["pos"] == Vector2i(6, 3) and _evs(g._step_events, "drag").size() == 1 and int(crane["status"]["root_cd"]) == 1, "drag lands once root is gone: %s" % str(g._step_events))
	crane["intent"] = {"type": "idle"}
	g._execute_intent(crane)
	_ok(int(crane["status"]["root_cd"]) == 0, "cd reaches 0: %s" % str(crane["status"]))
	g._step_events = []
	_ok(g._apply_status(crane, "root", 2) and int(crane["status"]["root"]) == 2 and int(crane["status"]["root_cd"]) == 4 and _evs(g._step_events, "status").size() == 1,
		"root lands again after the cooldown: %s" % str(crane["status"]))
	# advance is blocked too (driven directly: the intent executor does not
	# check the kind); the same enemy advances once unrooted
	var g2 = _game()
	var e2 = g2._spawn("drill_bot", Vector2i(8, 3))
	e2["intent"] = {"type": "advance", "steps": 2}
	g2._apply_status(e2, "root", 1)
	g2._step_events = []
	g2._execute_intent(e2)
	_ok(e2["pos"] == Vector2i(8, 3) and int(e2["status"]["root"]) == 0 and _evs(g2._step_events, "rooted").size() == 1, "root blocks advance: %s %s" % [str(e2["pos"]), str(e2["status"])])
	e2["intent"] = {"type": "advance", "steps": 2}
	g2._execute_intent(e2)
	_ok(e2["pos"] == Vector2i(6, 3), "advance moves once the root is gone: %s" % str(e2["pos"]))
	# root still does not swallow attacks, and only ticks when it blocks
	var g3 = _game()
	var e3 = g3._spawn("drill_bot", Vector2i(6, 3))
	g3._apply_status(e3, "root", 2)
	e3["intent"] = {"type": "attack", "tile": g3.player["pos"], "dmg": 1}
	var hp: int = g3.player["hp"]
	g3._execute_intent(e3)
	_ok(g3.player["hp"] == hp - 1 and int(e3["status"]["root"]) == 2 and int(e3["status"]["root_cd"]) == 3, "attack through root; root stays, cd ticks: %s" % str(e3["status"]))
	# a root that never blocked: once its cd is gone it can be re-applied while still active
	# massive enemies stay immune (no cd written)
	var g4 = _game()
	var boss = g4._spawn("the_dredge", Vector2i(8, 3))
	g4._step_events = []
	_ok(not g4._apply_status(boss, "root", 2) and boss["status"].is_empty() and _evs(g4._step_events, "immune").size() == 1, "massive immune to root: %s" % str(boss["status"]))
	# stun and spore carry no cooldown: no _cd field is ever written for them
	var g5 = _game()
	var e5 = g5._spawn("drill_bot", Vector2i(7, 3))
	g5._apply_status(e5, "stun", 1)
	g5._apply_status(e5, "spore", 1)
	_ok(not e5["status"].has("stun_cd") and not e5["status"].has("spore_cd"), "no cd for stun/spore: %s" % str(e5["status"]))
	# through the real cast path: sap_snare on a rooted-out enemy is resisted
	var g6 = _game(["sap_snare", "seed_bomb", "mycelium_dash"])
	var e6 = g6._spawn("drill_bot", Vector2i(7, 3))
	e6["status"]["root_cd"] = 2
	g6.player["charge"] = 10
	var evs: Array = g6.step({"type": "ability", "slot": 0, "target": Vector2i(7, 3)})
	_ok(_evs(evs, "resisted").size() == 1 and not e6["status"].has("root") and _evs(evs, "illegal").is_empty(), "sap_snare resisted through step: %s" % str(evs))
	e6["status"]["root_cd"] = 0
	g6.player["charge"] = 10
	evs = g6.step({"type": "ability", "slot": 0, "target": Vector2i(7, 3)})
	_ok(_evs(evs, "status").size() == 1 and int(e6["status"]["root"]) == 2 and int(e6["status"]["root_cd"]) == 4, "sap_snare lands through step: %s" % str(e6["status"]))


# --- spore add-stacking (C1b) ----------------------------------------------------

func _check_spore_stack() -> void:
	var g = _game()
	var e = g._spawn("drill_bot", Vector2i(6, 3))
	e["hp"] = 20
	g._apply_status(e, "spore", 3)
	_ok(int(e["status"]["spore"]) == 3, "first spore 3: %s" % str(e["status"]))
	g._apply_status(e, "spore", 3)
	_ok(int(e["status"]["spore"]) == 6, "second spore adds to 6: %s" % str(e["status"]))
	g._step_events = []
	_ok(g._apply_status(e, "spore", 3) and int(e["status"]["spore"]) == 6 and _evs(g._step_events, "status").size() == 1,
		"third spore capped at 6 (still a landed status): %s" % str(e["status"]))
	g._apply_status(e, "spore", 1)
	_ok(int(e["status"]["spore"]) == 6, "cap holds for smaller adds")
	# two spore_cloud casts through step
	var g2 = _game(["spore_cloud", "seed_bomb", "mycelium_dash"])
	var e2 = g2._spawn("drill_bot", Vector2i(7, 3))
	var far = g2._spawn("drill_bot", Vector2i(8, 3))
	e2["hp"] = 20
	for i in 3:
		g2.player["charge"] = 10
		g2.step({"type": "ability", "slot": 0, "target": g2.player["pos"]})
	_ok(int(e2["status"]["spore"]) == 6 and not far["status"].has("spore"), "3 x spore_cloud -> 6 within radius 2 only: %s %s" % [str(e2["status"]), str(far["status"])])
	# the tick still burns 1 a turn and drains one stack
	g2._step_events = []
	g2._environment_phase()
	_ok(int(e2["status"]["spore"]) == 5 and _evs(g2._step_events, "damage").size() == 1, "spore tick from 6 to 5: %s" % str(e2["status"]))


# --- items through _apply_status (C1b) ------------------------------------------

func _check_items_through_table() -> void:
	var g = _game()
	var near = g._spawn("drill_bot", Vector2i(7, 3))   # distance 2
	var far = g._spawn("drill_bot", Vector2i(8, 3))    # distance 3
	var boss = g._spawn("furnace_core", Vector2i(5, 1)) # distance 2, massive
	g.player["items"] = ["spore_vial", "spore_vial+"]
	var evs: Array = g.step({"type": "use_item", "slot": 0})
	var st := _evs(evs, "status")
	_ok(st.size() == 1 and st[0]["id"] == near["id"] and st[0]["status"] == "stun" and int(st[0]["turns"]) == 1, "spore_vial status event: %s" % str(st))
	_ok(int(near["status"].get("stun", 0)) == 1 and not far["status"].has("stun") and boss["status"].is_empty(), "spore_vial stuns within 2 only: %s %s" % [str(near["status"]), str(far["status"])])
	var im := _evs(evs, "immune")
	_ok(im.size() == 1 and im[0]["id"] == boss["id"], "boss in range gets the immune event: %s" % str(im))
	_ok(_evs(evs, "item_use").size() == 1 and g.player["items"] == ["spore_vial+"], "item consumed: %s" % str(g.player["items"]))
	# the + form reaches 4 tiles for 2 turns; stun stacks by max
	evs = g.step({"type": "use_item", "slot": 0})
	_ok(int(near["status"]["stun"]) == 2 and int(far["status"].get("stun", 0)) == 2 and boss["status"].is_empty() and _evs(evs, "status").size() == 2 and _evs(evs, "immune").size() == 1,
		"spore_vial+ radius 4 turns 2: %s %s" % [str(near["status"]), str(far["status"])])


# --- cast context counters ----------------------------------------------------

func _check_context_counters() -> void:
	var g = _game(["solar_lance", "seed_bomb", "mycelium_dash", "updraft"])
	_ok(g.casts_this_turn == 0 and g.moved_this_turn == 0, "counters start at 0")
	g.step({"type": "move", "dir": Vector2i(1, 0)})
	_ok(g.moved_this_turn == 1, "move counts: %d" % g.moved_this_turn)
	g.step({"type": "ability", "slot": 1, "target": Vector2i(8, 3)})
	_ok(g.casts_this_turn == 1, "cast counts: %d" % g.casts_this_turn)
	g.player["charge"] = 6
	g.step({"type": "ability", "slot": 3, "target": Vector2i(-1, 0)})
	_ok(g.casts_this_turn == 2 and g.moved_this_turn == 4 and g.player["pos"] == Vector2i(3, 3),
		"dash counts each tile: casts %d moved %d pos %s" % [g.casts_this_turn, g.moved_this_turn, str(g.player["pos"])])
	# seed_bomb planted growth on (7, 3): a dash target 4 tiles from (3, 3)
	g.step({"type": "ability", "slot": 2, "target": Vector2i(7, 3)})
	_ok(g.casts_this_turn == 3 and g.moved_this_turn == 5 and g.player["pos"] == Vector2i(7, 3),
		"teleport counts one tile change: casts %d moved %d pos %s" % [g.casts_this_turn, g.moved_this_turn, str(g.player["pos"])])
	g.step({"type": "ability", "slot": 9, "target": Vector2i(8, 3)})
	_ok(g.casts_this_turn == 3, "an illegal cast does not count")
	# ctx.casts_before is the count before this cast (read by casts_this_turn_min)
	var c = g.clone()
	_ok(c.casts_this_turn == 3 and c.moved_this_turn == 5, "clone copies the counters: %d %d" % [c.casts_this_turn, c.moved_this_turn])
	var snap: Dictionary = g.snapshot()
	_ok(not snap.has("casts_this_turn") and not snap.has("moved_this_turn") and not snap["player"].has("casts_this_turn"),
		"snapshot does not expose the counters")
	_ok(str(snap).find("casts_this_turn") == -1 and str(snap).find("moved_this_turn") == -1, "state hash input carries no counter")
	g.step({"type": "end_turn"})
	_ok(g.casts_this_turn == 0 and g.moved_this_turn == 0, "end_turn resets the counters")
	# the same game and its clone hash alike whatever the counters say
	var g2 = _game()
	var g3 = g2.clone()
	g3.casts_this_turn = 7
	_ok(g2.state_hash() == g3.state_hash(), "counters never move state_hash")


# --- Block C2 content rows, cast for real through step -------------------------

## A fresh game on a custom room (same legend as ROOM) with the given kit.
static func _game_on(rows: Array, kit: Array) -> RefCounted:
	return Game.new(1, {"fixed_floor": {"gen": _gen(rows), "fdef": {}}, "kit": kit})


## Cast kit slot `slot` at `target` with charge to spare; returns the step events.
static func _cast(g, slot: int, target) -> Array:
	g.player["charge"] = 10
	return g.step({"type": "ability", "slot": slot, "target": target})


## Damage events signed by `src` (an ability id) in `events`.
static func _dmg(events: Array, src: String) -> Array:
	var outl: Array = []
	for ev in _evs(events, "damage"):
		if String(ev.get("src", "")) == src:
			outl.append(ev)
	return outl


## grow_spike+ {dmg 3, per growth_adjacent_target cap 2}: 3 / 4 / 5 with 0 / 1 / 2+
## adjacent growth tiles; growth under the target does not count. Base row caps
## at 1 (3 / 4 / 4) and keeps range 3 so the + form (range 4) stays an upgrade.
func _check_c2_grow_spike() -> void:
	var t := Vector2i(8, 3)
	# 0 adjacent: growth under the enemy only makes it targetable, adds nothing
	var g = _game(["grow_spike+", "seed_bomb", "mycelium_dash"])
	var e = g._spawn("drill_bot", t)
	e["hp"] = 10
	g.terrain[t] = {"kind": "growth"}
	var evs: Array = _cast(g, 0, t)
	_ok(_evs(evs, "illegal").is_empty() and e["hp"] == 7 and _riders(evs, "per").is_empty(),
		"grow_spike+ 0 adjacent (growth under only): hp %d %s" % [e["hp"], str(evs)])
	_ok(_dmg(evs, "grow_spike+").size() == 1 and int(_dmg(evs, "grow_spike+")[0]["amt"]) == 3, "grow_spike+ base hit is 3: %s" % str(evs))
	# 1 adjacent -> 4, rider per amt 1
	g.terrain[Vector2i(8, 2)] = {"kind": "growth"}
	evs = _cast(g, 0, t)
	var per := _riders(evs, "per")
	_ok(e["hp"] == 3 and per.size() == 1 and int(per[0]["amt"]) == 1 and String(per[0]["id"]) == "grow_spike+",
		"grow_spike+ 1 adjacent -> 4 (rider per 1): hp %d %s" % [e["hp"], str(evs)])
	# 2 adjacent -> 5, rider per amt 2
	e["hp"] = 10
	g.terrain[Vector2i(8, 4)] = {"kind": "growth"}
	evs = _cast(g, 0, t)
	per = _riders(evs, "per")
	_ok(e["hp"] == 5 and per.size() == 1 and int(per[0]["amt"]) == 2, "grow_spike+ 2 adjacent -> 5 (rider per 2): hp %d %s" % [e["hp"], str(evs)])
	# 3 adjacent (plus growth under): still 5, the cap holds
	e["hp"] = 10
	g.terrain[Vector2i(9, 3)] = {"kind": "growth"}
	evs = _cast(g, 0, t)
	per = _riders(evs, "per")
	_ok(e["hp"] == 5 and per.size() == 1 and int(per[0]["amt"]) == 2, "grow_spike+ 3 adjacent capped at 5: hp %d %s" % [e["hp"], str(evs)])
	# the whole cast is one ability + one damage event, and the growth stays
	_ok(_evs(evs, "ability").size() == 1 and _dmg(evs, "grow_spike+").size() == 1 and int(_dmg(evs, "grow_spike+")[0]["amt"]) == 5
		and g.terrain.has(t) and g.terrain.has(Vector2i(8, 2)), "grow_spike+ single 5-damage hit, growth kept: %s" % str(evs))
	# range: the + form reaches 4 tiles, the base only 3
	var far := Vector2i(9, 3)
	var g4 = _game(["grow_spike+", "grow_spike", "mycelium_dash"])
	var e4 = g4._spawn("drill_bot", far)
	e4["hp"] = 10
	g4.terrain[far] = {"kind": "growth"}
	evs = _cast(g4, 1, far)
	_ok(_evs(evs, "illegal").size() == 1 and e4["hp"] == 10, "grow_spike (range 3) cannot reach distance 4: %s" % str(evs))
	evs = _cast(g4, 0, far)
	_ok(_evs(evs, "illegal").is_empty() and e4["hp"] == 7, "grow_spike+ (range 4) reaches distance 4: hp %d" % e4["hp"])
	# base row: 3 / 4 / 4
	var gb = _game(["grow_spike", "seed_bomb", "mycelium_dash"])
	var eb = gb._spawn("drill_bot", t)
	eb["hp"] = 10
	gb.terrain[t] = {"kind": "growth"}
	evs = _cast(gb, 0, t)
	_ok(_evs(evs, "illegal").is_empty() and eb["hp"] == 7 and _riders(evs, "per").is_empty(), "grow_spike 0 adjacent -> 3: hp %d %s" % [eb["hp"], str(evs)])
	gb.terrain[Vector2i(8, 2)] = {"kind": "growth"}
	evs = _cast(gb, 0, t)
	per = _riders(evs, "per")
	_ok(eb["hp"] == 3 and per.size() == 1 and int(per[0]["amt"]) == 1 and String(per[0]["id"]) == "grow_spike",
		"grow_spike 1 adjacent -> 4 (rider per 1): hp %d %s" % [eb["hp"], str(evs)])
	eb["hp"] = 10
	gb.terrain[Vector2i(8, 4)] = {"kind": "growth"}
	gb.terrain[Vector2i(7, 3)] = {"kind": "growth"}
	evs = _cast(gb, 0, t)
	per = _riders(evs, "per")
	_ok(eb["hp"] == 6 and per.size() == 1 and int(per[0]["amt"]) == 1, "grow_spike 3 adjacent capped at 4: hp %d %s" % [eb["hp"], str(evs)])
	# cost unchanged: 1 charge each
	_ok(int(Content.ABILITIES["grow_spike"]["cost"]) == 1 and int(Content.ABILITIES["grow_spike+"]["cost"]) == 1, "grow_spike costs stay 1")


## sun_flare(+) {aoe_damage, ignite, bonus dmg 1 if target_on fire}: an enemy on
## oil is ignited by the same cast and then takes the bonus; bare enemies do not.
func _check_c2_sun_flare() -> void:
	for pair in [["sun_flare+", 2], ["sun_flare", 1]]:
		var aid: String = pair[0]
		var base: int = pair[1]
		var g = _game([aid, "seed_bomb", "mycelium_dash"])
		var bare = g._spawn("drill_bot", Vector2i(5, 1))    # distance 2, bare floor
		var oiled = g._spawn("drill_bot", Vector2i(7, 3))   # distance 2, on oil
		var burning = g._spawn("drill_bot", Vector2i(5, 5)) # distance 2, already on fire
		var far = g._spawn("drill_bot", Vector2i(8, 3))     # distance 3, out of radius
		for e in [bare, oiled, burning, far]:
			e["hp"] = 10
		g.terrain[Vector2i(7, 3)] = {"kind": "oil"}
		g.terrain[Vector2i(5, 5)] = {"kind": "fire", "ttl": 2}
		var evs: Array = _cast(g, 0, g.player["pos"])
		_ok(_evs(evs, "illegal").is_empty(), "%s cast is legal: %s" % [aid, str(evs)])
		_ok(bare["hp"] == 10 - base, "%s bare enemy takes %d: hp %d" % [aid, base, bare["hp"]])
		_ok(g._terrain_kind(Vector2i(7, 3)) == "fire" and _evs(evs, "ignite").size() == 1,
			"%s ignites the oil first: %s %s" % [aid, g._terrain_kind(Vector2i(7, 3)), str(evs)])
		_ok(oiled["hp"] == 10 - base - 1, "%s enemy on oil (ignited this cast) takes %d: hp %d" % [aid, base + 1, oiled["hp"]])
		_ok(burning["hp"] == 10 - base - 1, "%s enemy already in fire takes %d: hp %d" % [aid, base + 1, burning["hp"]])
		_ok(far["hp"] == 10, "%s radius 2 leaves distance 3 alone" % aid)
		var bonus := _riders(evs, "bonus")
		_ok(bonus.size() == 2 and int(bonus[0]["amt"]) == 1 and int(bonus[1]["amt"]) == 1
			and String(bonus[0]["id"]) == aid and String(bonus[1]["id"]) == aid,
			"%s emits one bonus rider per enemy in fire: %s" % [aid, str(_evs(evs, "rider"))])
		_ok(_riders(evs, "per").is_empty() and _riders(evs, "then").is_empty(), "%s emits no per/then rider" % aid)
		var hits := _dmg(evs, aid)
		_ok(hits.size() == 3, "%s three damage events signed by it: %s" % [aid, str(hits)])
		_ok(int(Content.ABILITIES[aid]["cost"]) == 2, "%s cost stays 2" % aid)


## water_jet+ {wash_push 3 / 3, then root 1 if collided AND pushed}: the pin
## lands only when the enemy moved at least a tile and then hit something;
## the root cooldown refuses the second pin.
func _check_c2_water_jet() -> void:
	var kit := ["water_jet+", "seed_bomb", "mycelium_dash"]
	# pin: enemy at (8,3) shoved to (9,3), wall at (10,3) -> pushed 1, collided 1
	var g = _game(kit)
	var e = g._spawn("drill_bot", Vector2i(8, 3))
	e["hp"] = 10
	var evs: Array = _cast(g, 0, Vector2i(1, 0))
	_ok(_evs(evs, "illegal").is_empty() and e["pos"] == Vector2i(9, 3) and e["hp"] == 7,
		"water_jet+ pin: moved to (9,3), 3 collision dmg: %s hp %d" % [str(e["pos"]), e["hp"]])
	_ok(int(e["status"].get("root", 0)) == 1 and int(e["status"].get("root_cd", 0)) == 3,
		"water_jet+ pin roots 1 (cd 3): %s" % str(e["status"]))
	var then := _riders(evs, "then")
	_ok(then.size() == 1 and int(then[0]["amt"]) == 1 and String(then[0]["id"]) == "water_jet+",
		"water_jet+ pin emits rider then 1: %s" % str(_evs(evs, "rider")))
	var st := _evs(evs, "status")
	_ok(st.size() == 1 and String(st[0]["status"]) == "root" and int(st[0]["id"]) == int(e["id"]), "water_jet+ pin status event: %s" % str(st))
	_ok(_dmg(evs, "collision:water_jet+").size() == 1 and int(_dmg(evs, "collision:water_jet+")[0]["amt"]) == 3, "collision signed by water_jet+: %s" % str(evs))
	# the root cooldown refuses the second pin: root expired, cd still running
	e["status"]["root"] = 0
	e["pos"] = Vector2i(8, 3)
	evs = _cast(g, 0, Vector2i(1, 0))
	_ok(e["pos"] == Vector2i(9, 3) and e["hp"] == 4 and int(e["status"].get("root", 0)) == 0,
		"second pin: shoved and hit again, not rooted: %s %s" % [str(e["pos"]), str(e["status"])])
	_ok(_evs(evs, "resisted").size() == 1 and _riders(evs, "then").is_empty() and _evs(evs, "status").is_empty(),
		"second pin resisted, no rider then: %s" % str(evs))
	# wall-pinned: enemy already against the wall -> collided, not pushed -> no root
	var g2 = _game(kit)
	g2.player["pos"] = Vector2i(6, 3)
	var e2 = g2._spawn("drill_bot", Vector2i(9, 3))
	e2["hp"] = 10
	evs = _cast(g2, 0, Vector2i(1, 0))
	_ok(_evs(evs, "illegal").is_empty() and e2["pos"] == Vector2i(9, 3) and e2["hp"] == 7,
		"wall-pinned enemy takes 3, does not move: %s hp %d" % [str(e2["pos"]), e2["hp"]])
	_ok(not e2["status"].has("root") and _riders(evs, "then").is_empty() and _evs(evs, "status").is_empty(),
		"wall-pinned (collided, not pushed) -> no root: %s %s" % [str(e2["status"]), str(evs)])
	# blocked by another enemy: both take collision damage, neither is rooted
	var g3 = _game(kit)
	var e3 = g3._spawn("drill_bot", Vector2i(8, 3))
	var wall = g3._spawn("drill_bot", Vector2i(9, 3))
	e3["hp"] = 10
	wall["hp"] = 10
	evs = _cast(g3, 0, Vector2i(1, 0))
	_ok(e3["hp"] == 7 and wall["hp"] == 7 and e3["pos"] == Vector2i(8, 3) and not e3["status"].has("root") and not wall["status"].has("root")
		and _riders(evs, "then").is_empty(), "enemy-pinned: both hit, none rooted: %d %d %s" % [e3["hp"], wall["hp"], str(evs)])
	# open lane: enemy at (6,3) travels the full 3 tiles -> pushed, not collided -> no root, no damage
	var g4 = _game(kit)
	var e4 = g4._spawn("drill_bot", Vector2i(6, 3))
	e4["hp"] = 10
	evs = _cast(g4, 0, Vector2i(1, 0))
	_ok(_evs(evs, "illegal").is_empty() and e4["pos"] == Vector2i(9, 3) and e4["hp"] == 10,
		"open lane: shoved 3, no collision: %s hp %d" % [str(e4["pos"]), e4["hp"]])
	_ok(not e4["status"].has("root") and _riders(evs, "then").is_empty() and _evs(evs, "status").is_empty() and _evs(evs, "staggered").size() == 1,
		"open lane (pushed, not collided) -> no root, still staggered: %s %s" % [str(e4["status"]), str(evs)])
	_ok(int(Content.ABILITIES["water_jet+"]["cost"]) == 1, "water_jet+ cost stays 1")


## vine_whip+ {pull 3 / 3, then stun 1 if outcome_crossed fire}: the stun lands
## only when the drag crossed a burning tile (the enemy's own start tile is
## not crossed).
func _check_c2_vine_whip() -> void:
	var kit := ["vine_whip+", "seed_bomb", "mycelium_dash"]
	# drag through embers: enemy at (9,3), fire at (7,3), pulled to (6,3)
	var g = _game(kit)
	var e = g._spawn("drill_bot", Vector2i(9, 3))
	e["hp"] = 10
	g.terrain[Vector2i(7, 3)] = {"kind": "fire", "ttl": 2}
	var evs: Array = _cast(g, 0, Vector2i(9, 3))
	_ok(_evs(evs, "illegal").is_empty() and e["pos"] == Vector2i(6, 3), "vine_whip+ pulls 3 to (6,3): %s %s" % [str(e["pos"]), str(evs)])
	_ok(e["hp"] == 6 and _dmg(evs, "vine_whip+").size() == 1 and int(_dmg(evs, "vine_whip+")[0]["amt"]) == 3 and _dmg(evs, "fire:env").size() == 1,
		"drag through embers: 3 lash + 1 fire: hp %d %s" % [e["hp"], str(evs)])
	_ok(int(e["status"].get("stun", 0)) == 1, "crossed fire -> stun 1: %s" % str(e["status"]))
	var then := _riders(evs, "then")
	_ok(then.size() == 1 and int(then[0]["amt"]) == 1 and String(then[0]["id"]) == "vine_whip+", "vine_whip+ rider then 1: %s" % str(_evs(evs, "rider")))
	var st := _evs(evs, "status")
	_ok(st.size() == 1 and String(st[0]["status"]) == "stun", "stun status event: %s" % str(st))
	_ok(g._terrain_kind(Vector2i(7, 3)) == "fire", "the fire tile survives the drag")
	# oil on the path: crossed, but not fire -> no stun
	var g2 = _game(kit)
	var e2 = g2._spawn("drill_bot", Vector2i(9, 3))
	e2["hp"] = 10
	g2.terrain[Vector2i(7, 3)] = {"kind": "oil"}
	evs = _cast(g2, 0, Vector2i(9, 3))
	_ok(e2["pos"] == Vector2i(6, 3) and e2["hp"] == 7 and not e2["status"].has("stun") and _riders(evs, "then").is_empty() and _evs(evs, "status").is_empty(),
		"crossed oil only -> no stun: %s %s %s" % [str(e2["pos"]), str(e2["status"]), str(evs)])
	# fire under the enemy's start tile is not "crossed": no stun
	var g3 = _game(kit)
	var e3 = g3._spawn("drill_bot", Vector2i(9, 3))
	e3["hp"] = 10
	g3.terrain[Vector2i(9, 3)] = {"kind": "fire", "ttl": 2}
	evs = _cast(g3, 0, Vector2i(9, 3))
	_ok(e3["pos"] == Vector2i(6, 3) and e3["hp"] == 7 and not e3["status"].has("stun") and _riders(evs, "then").is_empty(),
		"fire under the start tile is not crossed -> no stun: %s %s" % [str(e3["status"]), str(evs)])
	# fire beside the path (not on it) -> no stun; bare path -> no rider at all
	var g4 = _game(kit)
	var e4 = g4._spawn("drill_bot", Vector2i(9, 3))
	e4["hp"] = 10
	g4.terrain[Vector2i(7, 2)] = {"kind": "fire", "ttl": 2}
	evs = _cast(g4, 0, Vector2i(9, 3))
	_ok(e4["hp"] == 7 and not e4["status"].has("stun") and _evs(evs, "rider").is_empty(), "fire beside the path -> no rider: %s" % str(evs))
	_ok(int(Content.ABILITIES["vine_whip+"]["cost"]) == 1, "vine_whip+ cost stays 1")


## seed_bomb+ {grow_radius 1, then root 1 who on_planted}: enemies standing on
## tiles this cast planted are rooted a turn; pre-existing growth under an
## enemy is not a planted tile. Seed-on-head: the same turn's grow_spike+ on
## the seeded enemy hits for 5.
func _check_c2_seed_bomb() -> void:
	var g = _game(["seed_bomb+", "grow_spike+", "mycelium_dash"])
	var head = g._spawn("drill_bot", Vector2i(7, 3))      # the target tile itself
	var old = g._spawn("drill_bot", Vector2i(8, 3))       # on pre-existing growth
	var beside = g._spawn("drill_bot", Vector2i(7, 4))    # on a tile the plus plants
	var off = g._spawn("drill_bot", Vector2i(9, 4))       # outside the plus
	for e in [head, old, beside, off]:
		e["hp"] = 10
	g.terrain[Vector2i(8, 3)] = {"kind": "growth"}
	var evs: Array = _cast(g, 0, Vector2i(7, 3))
	_ok(_evs(evs, "illegal").is_empty() and _evs(evs, "growth").size() == 1, "seed_bomb+ on an enemy's tile is legal: %s" % str(evs))
	_ok(g._terrain_kind(Vector2i(7, 3)) == "growth" and g._terrain_kind(Vector2i(7, 2)) == "growth"
		and g._terrain_kind(Vector2i(7, 4)) == "growth" and g._terrain_kind(Vector2i(6, 3)) == "growth" and g._terrain_kind(Vector2i(8, 3)) == "growth",
		"the plus is planted around (7,3)")
	_ok(int(head["status"].get("root", 0)) == 1 and int(beside["status"].get("root", 0)) == 1,
		"enemies on planted tiles are rooted 1: %s %s" % [str(head["status"]), str(beside["status"])])
	_ok(not old["status"].has("root") and not off["status"].has("root"),
		"pre-existing growth / outside the plus -> no root: %s %s" % [str(old["status"]), str(off["status"])])
	var then := _riders(evs, "then")
	_ok(then.size() == 1 and int(then[0]["amt"]) == 1 and String(then[0]["id"]) == "seed_bomb+", "seed_bomb+ rider then fires once per cast: %s" % str(_evs(evs, "rider")))
	var st := _evs(evs, "status")
	_ok(st.size() == 2 and String(st[0]["status"]) == "root" and String(st[1]["status"]) == "root", "two root status events: %s" % str(st))
	_ok(g.player["charge"] == 9, "seed_bomb+ still costs 1: charge %d" % g.player["charge"])
	# seed-on-head, same turn: grow_spike+ on (7,3) sees 4 adjacent growth -> cap 2 -> 5
	g.player["charge"] = 1
	evs = g.step({"type": "ability", "slot": 1, "target": Vector2i(7, 3)})
	var per := _riders(evs, "per")
	_ok(_evs(evs, "illegal").is_empty() and head["hp"] == 5 and per.size() == 1 and int(per[0]["amt"]) == 2 and g.casts_this_turn == 2,
		"seed-on-head: grow_spike+ for 5 the same turn: hp %d %s" % [head["hp"], str(evs)])
	# a seed that plants nothing under anyone: no root, no rider
	var g2 = _game(["seed_bomb+", "grow_spike+", "mycelium_dash"])
	var e2 = g2._spawn("drill_bot", Vector2i(8, 3))
	evs = _cast(g2, 0, Vector2i(5, 1))
	_ok(_evs(evs, "illegal").is_empty() and not e2["status"].has("root") and _evs(evs, "rider").is_empty() and _evs(evs, "status").is_empty(),
		"seed_bomb+ away from enemies: no root, no rider: %s" % str(evs))
	# a seed on a fully grown tile set plants nothing: no then at all
	var g3 = _game(["seed_bomb+", "grow_spike+", "mycelium_dash"])
	var e3 = g3._spawn("drill_bot", Vector2i(7, 3))
	for t in [Vector2i(7, 2), Vector2i(7, 4), Vector2i(6, 3), Vector2i(8, 3)]:
		g3.terrain[t] = {"kind": "growth"}
	# (7,3) is bare so the tile is a legal target; only it gets planted -> head rooted, count 1
	evs = _cast(g3, 0, Vector2i(7, 3))
	_ok(int(e3["status"].get("root", 0)) == 1 and _evs(evs, "status").size() == 1, "only the head tile was fresh: one root: %s" % str(evs))
	# the base row plants and does nothing else
	var g4 = _game(["seed_bomb", "grow_spike+", "mycelium_dash"])
	var e4 = g4._spawn("drill_bot", Vector2i(7, 3))
	evs = _cast(g4, 0, Vector2i(7, 3))
	_ok(_evs(evs, "illegal").is_empty() and not e4["status"].has("root") and _evs(evs, "rider").is_empty(), "base seed_bomb carries no rider: %s" % str(evs))


# --- Block C3: hook dispatcher through the rule grafts ---------------------------

## A fresh game on ROOM with the given kit and pre-installed grafts.
static func _game_g(kit: Array, grafts: Array) -> RefCounted:
	return Game.new(1, {"fixed_floor": {"gen": _gen(ROOM), "fdef": {}}, "kit": kit, "grafts": grafts})


static func _hooks(events: Array, id: String) -> Array:
	var outl: Array = []
	for ev in _evs(events, "hook"):
		if String(ev.get("id", "")) == id:
			outl.append(ev)
	return outl


## _graft_stat sums stat keys over held grafts, _graft_mod returns the first
## held mod value; the six legacy grafts read through them with their old numbers.
func _check_c3_graft_tables() -> void:
	var g = _game_g(["solar_lance", "seed_bomb", "mycelium_dash"], ["deep_cells", "thick_bark", "solar_core", "carapace"])
	_ok(g._graft_stat("bank_cap") == 2 and g._bank_cap() == Content.BANK_CAP + 2, "deep_cells: bank cap %d" % g._bank_cap())
	_ok(g._graft_stat("shield_cap") == 2 and g._shield_cap() == Content.SHIELD_CAP + 2, "thick_bark: shield cap %d" % g._shield_cap())
	_ok(g._graft_stat("regen") == 1 and g.player["charge"] == Content.BASE_REGEN + 1, "solar_core: regen +1, charge %d" % g.player["charge"])
	_ok(g._graft_stat("growth_heal") == 0 and g._graft_stat("cleanse_bloom") == 0 and g._graft_stat("no_such_stat") == 0, "unheld stats read 0")
	_ok(int(g._graft_mod("floor_start_shield", 0)) == 2 and g.player["shield"] == 2, "carapace: floor_start_shield 2, shield %d" % g.player["shield"])
	_ok(int(g._graft_mod("oil_cast_discount", 0)) == 0 and String(g._graft_mod("oil_cast_discount", "none")) == "none", "unheld mod returns the default")
	var g0 = _game_g(["solar_lance", "seed_bomb", "mycelium_dash"], [])
	_ok(g0._bank_cap() == Content.BANK_CAP and g0._shield_cap() == Content.SHIELD_CAP and g0.player["charge"] == Content.BASE_REGEN and g0.player["shield"] == 0,
		"no grafts: base numbers")
	# verdant_pulse and bloom_surge through the table
	var gv = _game_g(["solar_lance", "seed_bomb", "mycelium_dash"], ["verdant_pulse", "bloom_surge"])
	gv.terrain[gv.player["pos"]] = {"kind": "growth"}
	gv.player["hp"] = 5
	gv.step({"type": "end_turn"})
	_ok(gv.player["hp"] == 7, "verdant_pulse: growth heals 2, hp %d" % gv.player["hp"])
	gv.terrain[Vector2i(6, 3)] = {"kind": "oil"}
	gv.terrain[Vector2i(9, 1)] = {"kind": "oil"}  # keeps the floor from restoring
	gv.player["charge"] = 3
	var b0: int = gv.bloom
	gv.step({"type": "cleanse", "target": Vector2i(6, 3)})
	_ok(gv.bloom == b0 + 2, "bloom_surge: cleanse pays 2, bloom %d -> %d" % [b0, gv.bloom])
	# every graft row has the shape the dispatcher reads
	for gid in Content.GRAFTS:
		var row: Dictionary = Content.GRAFTS[gid]
		_ok(row.has("stat") or row.has("mod") or row.has("hooks"), "graft %s carries stat/mod/hooks" % gid)
	_ok(Content.GRAFTS.size() == 10, "ten grafts")
	# hook state is per-turn, cloned, not in the snapshot
	var gc = _game_g(["solar_lance", "seed_bomb", "mycelium_dash"], ["ember_sap", "oil_tithe"])
	gc.hook_uses = {"ember_sap": 2}
	gc.tithe_used_this_turn = true
	var c = gc.clone()
	_ok(c.hook_uses == {"ember_sap": 2} and c.tithe_used_this_turn == true, "clone copies hook_uses / tithe_used_this_turn")
	_ok(not gc.snapshot().has("hook_uses") and not gc.snapshot().has("tithe_used_this_turn"), "snapshot leaves hook state out")
	gc.step({"type": "end_turn"})
	_ok(gc.hook_uses.is_empty() and gc.tithe_used_this_turn == false, "new turn resets hook_uses / tithe: %s %s" % [str(gc.hook_uses), str(gc.tithe_used_this_turn)])


## ember_sap {on ignite, damage_at 1, cap 3}: whoever stands on the tile that
## just lit takes 1 signed ember_sap - the enemy under a lance-lit slick, the
## caster when a flare lights the oil underfoot; three times a turn, then it
## rests until the next turn.
func _check_c3_ember_sap() -> void:
	# lance lights oil under an enemy: ember 1 + lance 2
	var g = _game_g(["solar_lance", "sun_flare", "mycelium_dash"], ["ember_sap"])
	var e = g._spawn("drill_bot", Vector2i(7, 3))
	e["hp"] = 10
	g.terrain[Vector2i(7, 3)] = {"kind": "oil"}
	var evs: Array = _cast(g, 0, Vector2i(1, 0))
	_ok(_evs(evs, "illegal").is_empty() and e["hp"] == 7, "ember_sap + lance on oiled enemy: hp %d %s" % [e["hp"], str(evs)])
	var emb := _dmg(evs, "ember_sap")
	_ok(emb.size() == 1 and int(emb[0]["amt"]) == 1 and int(emb[0]["id"]) == int(e["id"]), "ember_sap damage event signed ember_sap: %s" % str(emb))
	var hk := _hooks(evs, "ember_sap")
	_ok(hk.size() == 1 and String(hk[0]["on"]) == "ignite" and hk[0]["tile"] == Vector2i(7, 3), "hook event {ember_sap, ignite, (7,3)}: %s" % str(hk))
	# order: ignite, hook, ember damage, then the lance damage
	var order: Array = []
	for ev in evs:
		if ["ignite", "hook", "damage"].has(String(ev["t"])):
			order.append(String(ev["t"]) + ":" + String(ev.get("src", "")))
	_ok(order == ["ignite:", "hook:", "damage:ember_sap", "damage:solar_lance"], "hook fires right after the ignite emit: %s" % str(order))
	_ok(int(g.hook_uses.get("ember_sap", 0)) == 1, "hook_uses counts the run: %s" % str(g.hook_uses))
	# the caster lights the oil underfoot with a flare: the sap burns the caster
	var g2 = _game_g(["sun_flare", "seed_bomb", "mycelium_dash"], ["ember_sap"])
	g2.terrain[g2.player["pos"]] = {"kind": "oil"}
	evs = _cast(g2, 0, g2.player["pos"])
	_ok(_evs(evs, "illegal").is_empty() and g2.player["hp"] == Content.PLAYER_HP - 1, "flare on oil underfoot: player hp %d %s" % [g2.player["hp"], str(evs)])
	var pd := _dmg(evs, "ember_sap")
	_ok(pd.size() == 1 and String(pd[0]["who"]) == "player" and int(pd[0]["amt"]) == 1, "player damage signed ember_sap: %s" % str(pd))
	_ok(_hooks(evs, "ember_sap").size() == 1, "one hook for the one ignite")
	# no ember_sap held: no hook, no extra damage
	var g3 = _game_g(["solar_lance", "sun_flare", "mycelium_dash"], [])
	var e3 = g3._spawn("drill_bot", Vector2i(7, 3))
	e3["hp"] = 10
	g3.terrain[Vector2i(7, 3)] = {"kind": "oil"}
	evs = _cast(g3, 0, Vector2i(1, 0))
	_ok(e3["hp"] == 8 and _evs(evs, "hook").is_empty() and _dmg(evs, "ember_sap").is_empty(), "without the graft: plain lance %d" % e3["hp"])
	# cap 3 per turn: a flare lighting three oiled enemies runs the hook thrice;
	# a fourth ignite the same turn is silent; the next turn it runs again
	var g4 = _game_g(["sun_flare", "seed_bomb", "mycelium_dash"], ["ember_sap"])
	var tiles: Array = [Vector2i(4, 3), Vector2i(6, 3), Vector2i(5, 2)]
	var ens: Array = []
	for t in tiles:
		var en = g4._spawn("drill_bot", t)
		en["hp"] = 10
		g4.terrain[t] = {"kind": "oil"}
		ens.append(en)
	evs = _cast(g4, 0, g4.player["pos"])
	_ok(_hooks(evs, "ember_sap").size() == 3 and _dmg(evs, "ember_sap").size() == 3, "three ignites -> three hooks: %s" % str(_evs(evs, "hook")))
	_ok(ens[0]["hp"] == 7 and ens[1]["hp"] == 7 and ens[2]["hp"] == 7, "each oiled enemy: 1 sap + 1 flare + 1 fire bonus: %d %d %d" % [ens[0]["hp"], ens[1]["hp"], ens[2]["hp"]])
	_ok(int(g4.hook_uses.get("ember_sap", 0)) == 3, "hook_uses ember_sap 3: %s" % str(g4.hook_uses))
	g4.terrain[Vector2i(5, 4)] = {"kind": "oil"}
	var e4 = g4._spawn("drill_bot", Vector2i(5, 4))
	e4["hp"] = 10
	evs = _cast(g4, 0, g4.player["pos"])
	_ok(_evs(evs, "ignite").size() == 1 and _hooks(evs, "ember_sap").is_empty() and _dmg(evs, "ember_sap").is_empty() and _evs(evs, "hook_capped").is_empty(),
		"fourth ignite this turn: cap holds silently (no hook_capped): %s" % str(evs))
	_ok(e4["hp"] == 8, "capped: flare + fire bonus only, hp %d" % e4["hp"])
	g4.step({"type": "end_turn"})
	_ok(g4.hook_uses.is_empty(), "hook_uses reset at the new turn")
	g4.terrain[Vector2i(7, 3)] = {"kind": "oil"}
	var e5 = g4._spawn("drill_bot", Vector2i(7, 3))
	e5["hp"] = 10
	evs = _cast(g4, 0, g4.player["pos"])
	var hk5 := _hooks(evs, "ember_sap")
	_ok(hk5.size() == 1 and hk5[0]["tile"] == Vector2i(7, 3) and e5["hp"] == 7, "next turn the sap runs again: hp %d %s" % [e5["hp"], str(hk5)])
	# igniter enemy stepping onto oil fires the hook too (by = enemy kind)
	var g6 = _game_g(["solar_lance", "seed_bomb", "mycelium_dash"], ["ember_sap"])
	var mite = g6._spawn("cinder_mite", Vector2i(8, 3))
	mite["hp"] = 10
	g6.terrain[Vector2i(7, 3)] = {"kind": "oil"}
	mite["intent"] = {"type": "move"}
	evs = g6.step({"type": "end_turn"})
	var hk6 := _hooks(evs, "ember_sap")
	_ok(hk6.size() >= 1 and _dmg(evs, "ember_sap").size() >= 1, "igniter enemy lighting oil fires the hook: %s" % str(evs))


## undertow {on staggered, status_at root 1}: a shoved enemy that stops is
## staggered and therefore rooted; the root cooldown refuses the next one.
func _check_c3_undertow() -> void:
	var g = _game_g(["water_jet", "seed_bomb", "mycelium_dash"], ["undertow"])
	var e = g._spawn("drill_bot", Vector2i(7, 3))
	e["hp"] = 10
	var evs: Array = _cast(g, 0, Vector2i(1, 0))
	_ok(_evs(evs, "illegal").is_empty() and e["pos"] == Vector2i(9, 3) and _evs(evs, "staggered").size() == 1, "jet to the wall staggers: %s %s" % [str(e["pos"]), str(evs)])
	_ok(int(e["status"].get("root", 0)) == 1 and int(e["status"].get("root_cd", 0)) == 3, "undertow roots the staggered enemy (cd 3): %s" % str(e["status"]))
	var hk := _hooks(evs, "undertow")
	_ok(hk.size() == 1 and String(hk[0]["on"]) == "staggered" and hk[0]["tile"] == Vector2i(9, 3), "hook event {undertow, staggered, (9,3)}: %s" % str(hk))
	var st := _evs(evs, "status")
	_ok(st.size() == 1 and String(st[0]["status"]) == "root" and int(st[0]["id"]) == int(e["id"]), "one root status event: %s" % str(st))
	# root expired, cooldown still running, stagger available again: resisted
	e["status"]["root"] = 0
	e["status"]["stagger_cd"] = 0
	e["pos"] = Vector2i(7, 3)
	evs = _cast(g, 0, Vector2i(1, 0))
	_ok(_evs(evs, "staggered").size() == 1 and _hooks(evs, "undertow").size() == 1, "second stagger runs the hook again: %s" % str(evs))
	_ok(_evs(evs, "resisted").size() == 1 and int(e["status"].get("root", 0)) == 0 and _evs(evs, "status").is_empty(), "the root cooldown refuses the second root: %s %s" % [str(e["status"]), str(evs)])
	# a pull that moves the enemy staggers it too
	var g2 = _game_g(["vine_whip", "seed_bomb", "mycelium_dash"], ["undertow"])
	var e2 = g2._spawn("drill_bot", Vector2i(8, 3))
	e2["hp"] = 10
	evs = _cast(g2, 0, Vector2i(8, 3))
	_ok(e2["pos"] == Vector2i(6, 3) and int(e2["status"].get("root", 0)) == 1 and _hooks(evs, "undertow").size() == 1, "vine_whip pull -> staggered -> rooted: %s %s" % [str(e2["pos"]), str(e2["status"])])
	# without the graft the stagger roots nothing
	var g3 = _game_g(["water_jet", "seed_bomb", "mycelium_dash"], [])
	var e3 = g3._spawn("drill_bot", Vector2i(7, 3))
	e3["hp"] = 10
	evs = _cast(g3, 0, Vector2i(1, 0))
	_ok(_evs(evs, "staggered").size() == 1 and not e3["status"].has("root") and _evs(evs, "hook").is_empty(), "no undertow: staggered, not rooted")


## compost {on kill, terrain_at growth}: a kill leaves growth on the tile the
## enemy fell on when it is bare; a tile holding terrain (fire, oil) keeps it.
func _check_c3_compost() -> void:
	var g = _game_g(["solar_lance", "seed_bomb", "mycelium_dash"], ["compost"])
	var e = g._spawn("drill_bot", Vector2i(7, 3))
	e["hp"] = 1
	var evs: Array = _cast(g, 0, Vector2i(1, 0))
	_ok(_evs(evs, "death").size() == 1 and g._terrain_kind(Vector2i(7, 3)) == "growth", "kill on bare floor leaves growth: %s %s" % [g._terrain_kind(Vector2i(7, 3)), str(evs)])
	var hk := _hooks(evs, "compost")
	_ok(hk.size() == 1 and String(hk[0]["on"]) == "kill" and hk[0]["tile"] == Vector2i(7, 3), "hook event {compost, kill, (7,3)}: %s" % str(hk))
	var terr := _evs(evs, "terrain")
	_ok(terr.size() == 1 and String(terr[0]["kind"]) == "growth" and terr[0]["tile"] == Vector2i(7, 3), "terrain event for the compost growth: %s" % str(terr))
	# killed while standing on oil the lance just lit: the fire stays
	var g2 = _game_g(["solar_lance", "seed_bomb", "mycelium_dash"], ["compost"])
	var e2 = g2._spawn("drill_bot", Vector2i(7, 3))
	e2["hp"] = 1
	g2.terrain[Vector2i(7, 3)] = {"kind": "oil"}
	evs = _cast(g2, 0, Vector2i(1, 0))
	_ok(_evs(evs, "death").size() == 1 and g2._terrain_kind(Vector2i(7, 3)) == "fire" and _hooks(evs, "compost").size() == 1 and _evs(evs, "terrain").is_empty(),
		"kill on fire: hook runs, nothing planted: %s %s" % [g2._terrain_kind(Vector2i(7, 3)), str(evs)])
	# killed on oil that did not light (strike): the oil stays
	var g3 = _game_g(["solar_lance", "seed_bomb", "mycelium_dash"], ["compost"])
	var e3 = g3._spawn("drill_bot", Vector2i(6, 3))
	e3["hp"] = 1
	g3.terrain[Vector2i(6, 3)] = {"kind": "oil"}
	g3.player["charge"] = 5
	evs = g3.step({"type": "strike", "dir": Vector2i(1, 0)})
	_ok(_evs(evs, "death").size() == 1 and g3._terrain_kind(Vector2i(6, 3)) == "oil", "kill on oil keeps the oil: %s" % g3._terrain_kind(Vector2i(6, 3)))
	# a kill by an enemy-side source (fire tick) composts too: any kill counts
	var g4 = _game_g(["solar_lance", "seed_bomb", "mycelium_dash"], ["compost"])
	var e4 = g4._spawn("drill_bot", Vector2i(8, 1))
	e4["hp"] = 1
	g4.terrain[Vector2i(8, 1)] = {"kind": "fire", "ttl": 3}
	evs = g4.step({"type": "end_turn"})
	_ok(_evs(evs, "death").size() == 1 and _hooks(evs, "compost").size() == 1 and g4._terrain_kind(Vector2i(8, 1)) == "fire", "fire-tick kill: hook runs, fire tile kept: %s" % str(evs))
	# nesting: ember_sap's damage kills -> the kill hook runs inside the ignite
	# hook (depth 2); the lance then continues to the enemy behind
	var g5 = _game_g(["solar_lance", "seed_bomb", "mycelium_dash"], ["ember_sap", "compost"])
	var e5 = g5._spawn("drill_bot", Vector2i(7, 3))
	var e6 = g5._spawn("drill_bot", Vector2i(8, 3))
	e5["hp"] = 1
	e6["hp"] = 10
	g5.terrain[Vector2i(7, 3)] = {"kind": "oil"}
	evs = _cast(g5, 0, Vector2i(1, 0))
	_ok(_dmg(evs, "ember_sap").size() == 1 and _evs(evs, "death").size() == 1 and not g5.enemies.has(e5), "ember_sap kills the oiled enemy: %s" % str(evs))
	_ok(_hooks(evs, "ember_sap").size() == 1 and _hooks(evs, "compost").size() == 1 and _evs(evs, "hook_capped").is_empty(), "nested kill hook ran (depth 2): %s" % str(_evs(evs, "hook")))
	_ok(g5._terrain_kind(Vector2i(7, 3)) == "fire", "compost finds fire, plants nothing")
	_ok(e6["hp"] == 8 and _dmg(evs, "solar_lance").size() == 1, "the lance passes the emptied tile and hits the next enemy: hp %d" % e6["hp"])


## oil_tithe {mod oil_cast_discount 1}: the first oil-aimed cast of a turn
## costs 1 less, floored at 1; legal_actions prices each target on its own.
func _check_c3_oil_tithe() -> void:
	var kit := ["solar_lance", "water_jet", "seed_bomb"]
	var g = _game_g(kit, ["oil_tithe"])
	g.terrain[Vector2i(7, 3)] = {"kind": "oil"}
	_ok(g.ability_cost("solar_lance") == 2, "no target: full price %d" % g.ability_cost("solar_lance"))
	_ok(g.ability_cost("solar_lance", Vector2i(1, 0)) == 1, "lance at the oil line: %d" % g.ability_cost("solar_lance", Vector2i(1, 0)))
	_ok(g.ability_cost("solar_lance", Vector2i(-1, 0)) == 2, "lance away from oil: %d" % g.ability_cost("solar_lance", Vector2i(-1, 0)))
	_ok(g.ability_cost("water_jet", Vector2i(1, 0)) == 1, "cost-1 jet at oil stays 1 (floor): %d" % g.ability_cost("water_jet", Vector2i(1, 0)))
	# legal_actions: with exactly 1 charge only the discounted lance is offered
	g.player["charge"] = 1
	var acts: Array = g.legal_actions()
	var lances: Array = []
	for a in acts:
		if String(a["type"]) == "ability" and int(a["slot"]) == 0:
			lances.append(a["target"])
	_ok(lances == [Vector2i(1, 0)], "1 charge: only the oil-line lance is legal: %s" % str(lances))
	# the same board without the graft offers no lance on 1 charge
	var g0 = _game_g(kit, [])
	g0.terrain[Vector2i(7, 3)] = {"kind": "oil"}
	g0.player["charge"] = 1
	var l0 := 0
	for a in g0.legal_actions():
		if String(a["type"]) == "ability" and int(a["slot"]) == 0:
			l0 += 1
	_ok(l0 == 0 and g0.ability_cost("solar_lance", Vector2i(1, 0)) == 2, "no graft: no discounted lance (%d legal, cost %d)" % [l0, g0.ability_cost("solar_lance", Vector2i(1, 0))])
	# cast: charge 2 -> 1, tithe event, discount spent
	g.player["charge"] = 2
	var evs: Array = g.step({"type": "ability", "slot": 0, "target": Vector2i(1, 0)})
	_ok(_evs(evs, "illegal").is_empty() and g.player["charge"] == 1 and g.tithe_used_this_turn, "discounted lance: charge %d tithe_used %s" % [g.player["charge"], str(g.tithe_used_this_turn)])
	var tithe := _evs(evs, "tithe")
	_ok(tithe.size() == 1 and String(tithe[0]["id"]) == "solar_lance", "tithe event: %s" % str(tithe))
	_ok(_evs(evs, "ignite").size() == 1 and g._terrain_kind(Vector2i(7, 3)) == "fire", "the lance still lit the oil")
	# second oil cast this turn: full price
	g.terrain[Vector2i(5, 1)] = {"kind": "oil"}
	_ok(g.ability_cost("solar_lance", Vector2i(0, -1)) == 2, "second oil cast this turn: %d" % g.ability_cost("solar_lance", Vector2i(0, -1)))
	evs = g.step({"type": "ability", "slot": 0, "target": Vector2i(0, -1)})
	_ok(_evs(evs, "illegal").size() == 1 and g.player["charge"] == 1, "1 charge cannot pay the full second cast: %s" % str(evs))
	g.player["charge"] = 5
	evs = g.step({"type": "ability", "slot": 0, "target": Vector2i(0, -1)})
	_ok(_evs(evs, "illegal").is_empty() and g.player["charge"] == 3 and _evs(evs, "tithe").is_empty(), "second oil cast pays 2, no tithe event: charge %d" % g.player["charge"])
	# 1 charge with the discount spent: the lance is not legal even at oil
	g.player["charge"] = 1
	g.terrain[Vector2i(5, 5)] = {"kind": "oil"}
	var l1 := 0
	for a in g.legal_actions():
		if String(a["type"]) == "ability" and int(a["slot"]) == 0:
			l1 += 1
	_ok(l1 == 0, "discount spent: no lance on 1 charge (%d)" % l1)
	# new turn: the discount is back
	g.step({"type": "end_turn"})
	_ok(not g.tithe_used_this_turn and g.ability_cost("solar_lance", Vector2i(0, 1)) == 1, "next turn: oil lance costs %d again" % g.ability_cost("solar_lance", Vector2i(0, 1)))
	# a cost-1 ability aimed at oil never consumes the tithe (nothing to discount)
	g.player["charge"] = 5
	evs = g.step({"type": "ability", "slot": 1, "target": Vector2i(0, 1)})
	_ok(_evs(evs, "illegal").is_empty() and g.player["charge"] == 4 and _evs(evs, "tithe").is_empty() and not g.tithe_used_this_turn,
		"jet at oil: cost 1, tithe untouched: charge %d %s" % [g.player["charge"], str(evs)])
	_ok(g.ability_cost("solar_lance", Vector2i(0, 1)) == 1 or g._terrain_kind(Vector2i(5, 5)) != "oil", "tithe still available after the jet")
	# a "dir" line whose oil sits beyond range is not oil-aimed
	var g2 = _game_g(kit, ["oil_tithe"])
	g2.terrain[Vector2i(9, 3)] = {"kind": "oil"}  # distance 4 > lance range 3
	_ok(g2.ability_cost("solar_lance", Vector2i(1, 0)) == 2, "oil beyond range: %d" % g2.ability_cost("solar_lance", Vector2i(1, 0)))
	# a wall between: the walk stops
	g2.terrain.erase(Vector2i(9, 3))
	g2.map["tiles"][3 * 11 + 7] = 0
	g2.terrain[Vector2i(8, 3)] = {"kind": "oil"}
	_ok(g2.ability_cost("solar_lance", Vector2i(1, 0)) == 2, "oil behind a wall: %d" % g2.ability_cost("solar_lance", Vector2i(1, 0)))
	# surge plus tithe: growth underfoot already makes it 1, the tithe adds nothing
	var g3 = _game_g(kit, ["oil_tithe"])
	g3.terrain[g3.player["pos"]] = {"kind": "growth"}
	g3.terrain[Vector2i(7, 3)] = {"kind": "oil"}
	_ok(g3.ability_cost("solar_lance", Vector2i(1, 0)) == 1, "surge + tithe floors at 1: %d" % g3.ability_cost("solar_lance", Vector2i(1, 0)))
	g3.player["charge"] = 2
	evs = g3.step({"type": "ability", "slot": 0, "target": Vector2i(1, 0)})
	_ok(_evs(evs, "verdant").size() == 1 and _evs(evs, "tithe").is_empty() and not g3.tithe_used_this_turn and g3.player["charge"] == 1,
		"surged cast: verdant, no tithe spent: %s" % str(evs))
	# a non-dir target on oil: the target tile itself decides (enemy on oil)
	var g4 = _game_g(["pollen_burst", "grow_spike", "mycelium_dash"], ["oil_tithe"])
	g4.terrain[g4.player["pos"]] = {"kind": "oil"}
	_ok(g4.ability_cost("pollen_burst", g4.player["pos"]) == 1, "self-target while standing on oil: %d" % g4.ability_cost("pollen_burst", g4.player["pos"]))
	g4.terrain.erase(g4.player["pos"])
	_ok(g4.ability_cost("pollen_burst", g4.player["pos"]) == 2, "self-target off oil: %d" % g4.ability_cost("pollen_burst", g4.player["pos"]))


## Depth and step caps: the dispatcher reads Content.HOOK_DEPTH_MAX and
## Content.HOOK_STEP_CAP, skips the hook beyond either and emits hook_capped
## once per step; step() clears the per-step counters.
func _check_c3_hook_caps() -> void:
	_ok(Content.HOOK_DEPTH_MAX == 3 and Content.HOOK_STEP_CAP == 12, "cap constants: depth %d step %d" % [Content.HOOK_DEPTH_MAX, Content.HOOK_STEP_CAP])
	var g = _game_g(["solar_lance", "seed_bomb", "mycelium_dash"], ["compost"])
	# direct dispatch on a bare tile plants growth (the kill ctx after an erase)
	g._step_events = []
	g._hook("kill", {"tile": Vector2i(8, 1), "enemy_kind": "drill_bot", "enemy_id": 99})
	_ok(g._terrain_kind(Vector2i(8, 1)) == "growth" and _hooks(g._step_events, "compost").size() == 1 and g._hook_runs == 1, "direct kill hook plants: runs %d" % g._hook_runs)
	# step cap: at the cap the hook is skipped, hook_capped once
	g._step_events = []
	g._hook_runs = Content.HOOK_STEP_CAP
	g._hook("kill", {"tile": Vector2i(8, 2), "enemy_kind": "drill_bot", "enemy_id": 99})
	g._hook("kill", {"tile": Vector2i(8, 3), "enemy_kind": "drill_bot", "enemy_id": 99})
	_ok(not g.terrain.has(Vector2i(8, 2)) and not g.terrain.has(Vector2i(8, 3)) and _evs(g._step_events, "hook").is_empty(),
		"step cap: both hooks skipped")
	_ok(_evs(g._step_events, "hook_capped").size() == 1, "hook_capped emitted once: %s" % str(g._step_events))
	# one below the cap still runs, and the run lands exactly on the cap
	g._step_events = []
	g._hook_runs = Content.HOOK_STEP_CAP - 1
	g._hook_capped = false
	g._hook("kill", {"tile": Vector2i(8, 2), "enemy_kind": "drill_bot", "enemy_id": 99})
	_ok(g._terrain_kind(Vector2i(8, 2)) == "growth" and g._hook_runs == Content.HOOK_STEP_CAP and _evs(g._step_events, "hook_capped").is_empty(), "cap - 1 runs")
	# a new step clears the counters: the next kill hook runs
	var e = g._spawn("drill_bot", Vector2i(7, 3))
	e["hp"] = 1
	var evs: Array = _cast(g, 0, Vector2i(1, 0))
	_ok(_hooks(evs, "compost").size() == 1 and g._terrain_kind(Vector2i(7, 3)) == "growth" and _evs(evs, "hook_capped").is_empty(), "step() resets the step cap: %s" % str(evs))
	# depth cap: a dispatch at HOOK_DEPTH_MAX is skipped, hook_capped once
	g._step_events = []
	g._hook_depth = Content.HOOK_DEPTH_MAX
	g._hook("kill", {"tile": Vector2i(8, 4), "enemy_kind": "drill_bot", "enemy_id": 99})
	g._hook("kill", {"tile": Vector2i(8, 5), "enemy_kind": "drill_bot", "enemy_id": 99})
	_ok(not g.terrain.has(Vector2i(8, 4)) and _evs(g._step_events, "hook").is_empty() and _evs(g._step_events, "hook_capped").size() == 1, "depth cap: skipped, capped once: %s" % str(g._step_events))
	g._hook_depth = Content.HOOK_DEPTH_MAX - 1
	g._step_events = []
	g._hook("kill", {"tile": Vector2i(8, 4), "enemy_kind": "drill_bot", "enemy_id": 99})
	_ok(g._terrain_kind(Vector2i(8, 4)) == "growth" and g._hook_depth == Content.HOOK_DEPTH_MAX - 1, "depth max - 1 runs and restores the depth")
	g._hook_depth = 0
	# an unknown hook kind runs nothing; a game that is over runs nothing
	g._step_events = []
	g._hook("sneeze", {"tile": Vector2i(8, 5)})
	_ok(_evs(g._step_events, "hook").is_empty() and not g.terrain.has(Vector2i(8, 5)), "unknown kind: no source matches")
	g.over = true
	g._hook("kill", {"tile": Vector2i(8, 5), "enemy_kind": "drill_bot", "enemy_id": 99})
	_ok(not g.terrain.has(Vector2i(8, 5)), "game over: hooks do not run")
	g.over = false
	# sources scan kit slots first, then grafts in held order (hook events in that order)
	var g2 = _game_g(["solar_lance", "seed_bomb", "mycelium_dash"], ["compost", "ember_sap"])
	var e2 = g2._spawn("drill_bot", Vector2i(7, 3))
	e2["hp"] = 1
	g2.terrain[Vector2i(7, 3)] = {"kind": "oil"}
	evs = _cast(g2, 0, Vector2i(1, 0))
	var ids: Array = []
	for ev in _evs(evs, "hook"):
		ids.append(String(ev["id"]))
	_ok(ids == ["ember_sap", "compost"], "ignite hook (ember_sap) then its nested kill hook (compost): %s" % str(ids))


# --- Block C4: package "+" rows, cast for real through step -----------------------

## 15 x 7 room, player at (2, 3): a long open lane east for the dist / range bumps.
const LANE := [
	"###############",
	"#.............#",
	"#.............#",
	"#.@...........#",
	"#.............#",
	"#.............#",
	"###############",
]


## spore_cloud+ {aoe_status spore 3, radius 3}: wider, not longer - two casts
## still fill the add-stack cap of 6 exactly. Distance 3 is spored by the +
## form only; distance 4 by neither; every spored enemy carries 3 turns.
func _check_c4_spore_cloud() -> void:
	for pair in [["spore_cloud+", 3], ["spore_cloud", 2]]:
		var aid: String = pair[0]
		var radius: int = pair[1]
		var g = _game([aid, "seed_bomb", "mycelium_dash"])
		var near = g._spawn("drill_bot", Vector2i(7, 3))   # distance 2
		var edge = g._spawn("drill_bot", Vector2i(8, 3))   # distance 3
		var far = g._spawn("drill_bot", Vector2i(9, 3))    # distance 4
		var diag = g._spawn("drill_bot", Vector2i(7, 1))   # distance 4 (2 + 2)
		var evs: Array = _cast(g, 0, g.player["pos"])
		_ok(_evs(evs, "illegal").is_empty(), "%s cast is legal: %s" % [aid, str(evs)])
		_ok(int(near["status"].get("spore", 0)) == 3, "%s spores distance 2 for 3: %s" % [aid, str(near["status"])])
		_ok(int(edge["status"].get("spore", 0)) == (3 if radius == 3 else 0),
			"%s (radius %d) at distance 3: %s" % [aid, radius, str(edge["status"])])
		_ok(not far["status"].has("spore") and not diag["status"].has("spore"), "%s leaves distance 4 alone" % aid)
		_ok(_evs(evs, "status").size() == (2 if radius == 3 else 1) and _evs(evs, "rider").is_empty(),
			"%s status events, no rider: %s" % [aid, str(evs)])
		_ok(int(Content.ABILITIES[aid]["cost"]) == 2, "%s cost stays 2" % aid)
	# a second + cast stacks to exactly the cap (3 + 3 = 6)
	var g2 = _game(["spore_cloud+", "seed_bomb", "mycelium_dash"])
	var e2 = g2._spawn("drill_bot", Vector2i(8, 3))
	e2["hp"] = 10
	_cast(g2, 0, g2.player["pos"])
	_cast(g2, 0, g2.player["pos"])
	_ok(int(e2["status"].get("spore", 0)) == 6, "two spore_cloud+ casts stack to the cap of 6: %s" % str(e2["status"]))


## fungal_ring+ {grow_radius 1, then root 1 who on_planted}: radius 1 is the
## plus around the target (grow_radius reads the key since D1, and the row
## keeps 1), so the bump is the seed_bomb+ rider - enemies standing where the
## ring sprouted are rooted a turn.
func _check_c4_fungal_ring() -> void:
	var g = _game(["fungal_ring+", "seed_bomb", "mycelium_dash"])
	var east = g._spawn("drill_bot", Vector2i(6, 3))    # bare tile the ring plants
	var west = g._spawn("drill_bot", Vector2i(4, 3))    # pre-existing growth
	var off = g._spawn("drill_bot", Vector2i(7, 3))     # outside the plus
	g.terrain[Vector2i(4, 3)] = {"kind": "growth"}
	var evs: Array = _cast(g, 0, g.player["pos"])
	_ok(_evs(evs, "illegal").is_empty() and _evs(evs, "growth").size() == 1, "fungal_ring+ cast is legal: %s" % str(evs))
	for t in [Vector2i(5, 3), Vector2i(6, 3), Vector2i(4, 3), Vector2i(5, 2), Vector2i(5, 4)]:
		_ok(g._terrain_kind(t) == "growth", "fungal_ring+ growth at %s" % str(t))
	_ok(g._terrain_kind(Vector2i(7, 3)) == "", "fungal_ring+ plants a plus, not a radius-2 diamond")
	_ok(int(east["status"].get("root", 0)) == 1, "enemy on a fresh ring tile is rooted 1: %s" % str(east["status"]))
	_ok(not west["status"].has("root") and not off["status"].has("root"),
		"pre-existing growth / outside the ring -> no root: %s %s" % [str(west["status"]), str(off["status"])])
	var then := _riders(evs, "then")
	_ok(then.size() == 1 and int(then[0]["amt"]) == 1 and String(then[0]["id"]) == "fungal_ring+", "fungal_ring+ rider then once: %s" % str(_evs(evs, "rider")))
	_ok(_evs(evs, "status").size() == 1 and String(_evs(evs, "status")[0]["status"]) == "root", "one root status event: %s" % str(_evs(evs, "status")))
	_ok(g.player["charge"] == 9, "fungal_ring+ costs 1: charge %d" % g.player["charge"])
	# nobody on the ring: growth, no root, no rider
	var g2 = _game(["fungal_ring+", "seed_bomb", "mycelium_dash"])
	var e2 = g2._spawn("drill_bot", Vector2i(8, 3))
	evs = _cast(g2, 0, g2.player["pos"])
	_ok(_evs(evs, "illegal").is_empty() and not e2["status"].has("root") and _evs(evs, "rider").is_empty() and _evs(evs, "status").is_empty(),
		"fungal_ring+ with nobody adjacent: no root, no rider: %s" % str(evs))
	# the base row plants the same plus and carries no rider
	var g3 = _game(["fungal_ring", "seed_bomb", "mycelium_dash"])
	var e3 = g3._spawn("drill_bot", Vector2i(6, 3))
	evs = _cast(g3, 0, g3.player["pos"])
	_ok(_evs(evs, "illegal").is_empty() and g3._terrain_kind(Vector2i(6, 3)) == "growth" and not e3["status"].has("root") and _evs(evs, "rider").is_empty(),
		"base fungal_ring plants under the enemy, no root: %s" % str(evs))
	_ok(int(Content.ABILITIES["fungal_ring"]["cost"]) == 1 and int(Content.ABILITIES["fungal_ring+"]["cost"]) == 1, "fungal_ring costs stay 1")


## burrow+ {teleport, range 4}: the tile list (Game._ability_targets "tile")
## reads adef.range, so distance 4 is legal for the + form and illegal for the base.
func _check_c4_burrow() -> void:
	var far := Vector2i(9, 3)
	var g = _game(["burrow", "burrow+", "mycelium_dash"])
	var evs: Array = _cast(g, 0, far)
	_ok(_evs(evs, "illegal").size() == 1 and g.player["pos"] == Vector2i(5, 3), "burrow (range 3) cannot reach distance 4: %s" % str(evs))
	evs = _cast(g, 1, far)
	_ok(_evs(evs, "illegal").is_empty() and g.player["pos"] == far and _evs(evs, "teleport").size() == 1 and g.moved_this_turn == 1,
		"burrow+ (range 4) tunnels to distance 4: %s %s" % [str(g.player["pos"]), str(evs)])
	# distance 5 is out for both
	g.player["pos"] = Vector2i(4, 3)
	evs = _cast(g, 1, far)
	_ok(_evs(evs, "illegal").size() == 1 and g.player["pos"] == Vector2i(4, 3), "burrow+ stops at 4: %s" % str(evs))
	# a growth-free destination is fine (burrow is not mycelium_dash); a walled one is not
	evs = _cast(g, 1, Vector2i(0, 3))
	_ok(_evs(evs, "illegal").size() == 1, "burrow+ cannot enter a wall")
	_ok(int(Content.ABILITIES["burrow"]["cost"]) == 2 and int(Content.ABILITIES["burrow+"]["cost"]) == 2, "burrow costs stay 2")


## tide+ {wash_all push 3 / collision 2, then root 1 if collided AND pushed}:
## the water_jet+ pin around the caster. The then reads the merged four-way
## outcome, so an enemy that moved and hit is rooted; a free lane (pushed only)
## or a wall-pinned enemy (collided only) is not.
func _check_c4_tide() -> void:
	# pin: enemy at (7,3) (distance 2) shoved to (9,3), wall at (10,3) -> pushed + collided
	var g = _game(["tide+", "seed_bomb", "mycelium_dash"])
	var e = g._spawn("drill_bot", Vector2i(7, 3))
	e["hp"] = 10
	var evs: Array = _cast(g, 0, g.player["pos"])
	_ok(_evs(evs, "illegal").is_empty() and e["pos"] == Vector2i(9, 3) and e["hp"] == 8,
		"tide+ pin: shoved to (9,3), 2 collision dmg: %s hp %d" % [str(e["pos"]), e["hp"]])
	_ok(int(e["status"].get("root", 0)) == 1, "tide+ pin roots 1: %s" % str(e["status"]))
	var then := _riders(evs, "then")
	_ok(then.size() == 1 and int(then[0]["amt"]) == 1 and String(then[0]["id"]) == "tide+", "tide+ rider then once: %s" % str(_evs(evs, "rider")))
	_ok(_dmg(evs, "collision:tide+").size() == 1 and int(_dmg(evs, "collision:tide+")[0]["amt"]) == 2, "collision signed by tide+: %s" % str(evs))
	# free lane: enemy at (6,3) travels 3 to (9,3), no collision -> no root
	var g2 = _game(["tide+", "seed_bomb", "mycelium_dash"])
	var e2 = g2._spawn("drill_bot", Vector2i(6, 3))
	e2["hp"] = 10
	evs = _cast(g2, 0, g2.player["pos"])
	_ok(e2["pos"] == Vector2i(9, 3) and e2["hp"] == 10 and not e2["status"].has("root") and _riders(evs, "then").is_empty(),
		"tide+ free lane: shoved 3, no dmg, no root: %s %s" % [str(e2["pos"]), str(evs)])
	# wall-pinned: player at (7,3), enemy at (9,3) -> collided only -> no root
	var g3 = _game(["tide+", "seed_bomb", "mycelium_dash"])
	g3.player["pos"] = Vector2i(7, 3)
	var e3 = g3._spawn("drill_bot", Vector2i(9, 3))
	e3["hp"] = 10
	evs = _cast(g3, 0, g3.player["pos"])
	_ok(e3["pos"] == Vector2i(9, 3) and e3["hp"] == 8 and not e3["status"].has("root") and _riders(evs, "then").is_empty(),
		"tide+ wall-pinned: 2 dmg, not moved, no root: %s %s" % [str(e3["status"]), str(evs)])
	# four-way: every direction is washed in one cast; the merged outcome roots every affected enemy
	var g4 = _game(["tide+", "seed_bomb", "mycelium_dash"])
	var n = g4._spawn("drill_bot", Vector2i(5, 2))   # north, adjacent: (5,1) then wall -> pushed 1, collided
	var s_ = g4._spawn("drill_bot", Vector2i(5, 4))  # south, adjacent: (5,5) then wall -> pushed 1, collided
	var w = g4._spawn("drill_bot", Vector2i(3, 3))   # west, distance 2: (2,3),(1,3) then wall -> pushed 2, collided
	for x in [n, s_, w]:
		x["hp"] = 10
	evs = _cast(g4, 0, g4.player["pos"])
	_ok(n["pos"] == Vector2i(5, 1) and s_["pos"] == Vector2i(5, 5) and w["pos"] == Vector2i(1, 3), "tide+ washes all four directions: %s %s %s" % [str(n["pos"]), str(s_["pos"]), str(w["pos"])])
	_ok(n["hp"] == 8 and s_["hp"] == 8 and w["hp"] == 8 and int(n["status"].get("root", 0)) == 1 and int(s_["status"].get("root", 0)) == 1 and int(w["status"].get("root", 0)) == 1,
		"tide+ pins all three: %d %d %d %s" % [n["hp"], s_["hp"], w["hp"], str(_evs(evs, "status"))])
	_ok(_riders(evs, "then").size() == 1, "one rider then for the whole wave: %s" % str(_evs(evs, "rider")))
	# base row: push 2, collision 1, no rider
	var gb = _game(["tide", "seed_bomb", "mycelium_dash"])
	var eb = gb._spawn("drill_bot", Vector2i(7, 3))
	eb["hp"] = 10
	evs = _cast(gb, 0, gb.player["pos"])
	_ok(_evs(evs, "illegal").is_empty() and eb["pos"] == Vector2i(9, 3) and eb["hp"] == 10 and not eb["status"].has("root") and _evs(evs, "rider").is_empty(),
		"base tide shoves 2 to (9,3), no collision, no root: %s hp %d %s" % [str(eb["pos"]), eb["hp"], str(evs)])
	# base collision: player at (6,3), enemy at (8,3) (distance 2) -> (9,3) then wall -> 1 dmg
	var gb2 = _game(["tide", "seed_bomb", "mycelium_dash"])
	gb2.player["pos"] = Vector2i(6, 3)
	var eb2 = gb2._spawn("drill_bot", Vector2i(8, 3))
	eb2["hp"] = 10
	evs = _cast(gb2, 0, gb2.player["pos"])
	_ok(eb2["pos"] == Vector2i(9, 3) and eb2["hp"] == 9 and not eb2["status"].has("root"), "base tide collision is 1, no root: hp %d %s" % [eb2["hp"], str(eb2["status"])])
	# the wash reaches range 2 only: an enemy at distance 3 is untouched by either row
	var gb3 = _game(["tide+", "seed_bomb", "mycelium_dash"])
	var eb3 = gb3._spawn("drill_bot", Vector2i(8, 3))
	evs = _cast(gb3, 0, gb3.player["pos"])
	_ok(eb3["pos"] == Vector2i(8, 3) and _evs(evs, "rider").is_empty(), "tide+ range stays 2: distance 3 untouched: %s" % str(evs))
	_ok(int(Content.ABILITIES["tide"]["cost"]) == 2 and int(Content.ABILITIES["tide+"]["cost"]) == 2, "tide costs stay 2")


## steam_vent+ {create_terrain smoke, ttl 5}: the smoke lingers two turns longer.
func _check_c4_steam_vent() -> void:
	for pair in [["steam_vent+", 5], ["steam_vent", 3]]:
		var aid: String = pair[0]
		var ttl: int = pair[1]
		var g = _game([aid, "seed_bomb", "mycelium_dash"])
		var t := Vector2i(8, 3)
		var evs: Array = _cast(g, 0, t)
		_ok(_evs(evs, "illegal").is_empty() and g._terrain_kind(t) == "smoke" and int(g.terrain[t]["ttl"]) == ttl,
			"%s vents smoke with ttl %d: %s %s" % [aid, ttl, str(g.terrain.get(t)), str(evs)])
		_ok(_evs(evs, "terrain").size() == 1 and String(_evs(evs, "terrain")[0]["kind"]) == "smoke" and _evs(evs, "rider").is_empty(),
			"%s one terrain event, no rider: %s" % [aid, str(evs)])
		# smoke blocks the lance the same either way
		var far = g._spawn("drill_bot", Vector2i(9, 3))
		far["hp"] = 10
		g.player["kit"][1] = "solar_lance"
		evs = _cast(g, 1, Vector2i(1, 0))
		_ok(far["hp"] == 10, "%s smoke blocks the lance behind it: hp %d" % [aid, far["hp"]])
		# distance 4 is out of range; an occupied tile is refused
		var g2 = _game([aid, "seed_bomb", "mycelium_dash"])
		evs = _cast(g2, 0, Vector2i(9, 3))
		_ok(_evs(evs, "illegal").size() == 1, "%s range stays 3" % aid)
		_ok(int(Content.ABILITIES[aid]["cost"]) == 1, "%s cost stays 1" % aid)


## geyser+ {aoe_damage 2 radius 1, bonus 1 if target_on fire; push_all 2}: the
## sun_flare+ scald - an adjacent enemy standing in fire takes 3 before the shove.
func _check_c4_geyser() -> void:
	for pair in [["geyser+", 2, 1], ["geyser", 1, 0]]:
		var aid: String = pair[0]
		var base: int = pair[1]
		var bonus: int = pair[2]
		var g = _game([aid, "seed_bomb", "mycelium_dash"])
		var bare = g._spawn("drill_bot", Vector2i(6, 3))     # east, bare
		var burning = g._spawn("drill_bot", Vector2i(4, 3))  # west, in fire
		var far = g._spawn("drill_bot", Vector2i(5, 1))      # distance 2: out of radius, not adjacent
		for e in [bare, burning, far]:
			e["hp"] = 10
		g.terrain[Vector2i(4, 3)] = {"kind": "fire", "ttl": 3}
		var evs: Array = _cast(g, 0, g.player["pos"])
		_ok(_evs(evs, "illegal").is_empty(), "%s cast is legal: %s" % [aid, str(evs)])
		_ok(bare["hp"] == 10 - base and bare["pos"] == Vector2i(8, 3), "%s bare enemy takes %d and is shoved 2: hp %d %s" % [aid, base, bare["hp"], str(bare["pos"])])
		_ok(burning["hp"] == 10 - base - bonus and burning["pos"] == Vector2i(2, 3),
			"%s enemy in fire takes %d and is shoved 2: hp %d %s" % [aid, base + bonus, burning["hp"], str(burning["pos"])])
		_ok(far["hp"] == 10 and far["pos"] == Vector2i(5, 1), "%s leaves distance 2 alone" % aid)
		var riders := _riders(evs, "bonus")
		_ok(riders.size() == bonus and (bonus == 0 or (int(riders[0]["amt"]) == 1 and String(riders[0]["id"]) == aid)),
			"%s bonus rider %d: %s" % [aid, bonus, str(_evs(evs, "rider"))])
		_ok(_dmg(evs, aid).size() == 2 and _evs(evs, "staggered").size() == 2, "%s two hits, two staggers: %s" % [aid, str(evs)])
		_ok(g._terrain_kind(Vector2i(4, 3)) == "fire", "%s does not ignite or wash: fire stays" % aid)
		_ok(int(Content.ABILITIES[aid]["cost"]) == 2, "%s cost stays 2" % aid)
	# oil under an adjacent enemy is not fire: no bonus (geyser carries no ignite)
	var g2 = _game(["geyser+", "seed_bomb", "mycelium_dash"])
	var oiled = g2._spawn("drill_bot", Vector2i(6, 3))
	oiled["hp"] = 10
	g2.terrain[Vector2i(6, 3)] = {"kind": "oil"}
	var evs2: Array = _cast(g2, 0, g2.player["pos"])
	_ok(oiled["hp"] == 8 and g2._terrain_kind(Vector2i(6, 3)) == "oil" and _riders(evs2, "bonus").is_empty(),
		"geyser+ on oil: 2 dmg, oil unlit, no bonus: hp %d %s" % [oiled["hp"], str(evs2)])


## gust+ {push_line dist 4, range 4, clear_smoke}: reaches and shoves one tile
## further than the base and still clears smoke along the line.
func _check_c4_gust() -> void:
	var kit := ["gust+", "gust", "mycelium_dash"]
	# push distance: enemy at (3,3) in an open lane -> (7,3) for +, (6,3) for base
	for pair in [[0, Vector2i(7, 3)], [1, Vector2i(6, 3)]]:
		var g = _game_on(LANE, kit)
		var e = g._spawn("drill_bot", Vector2i(3, 3))
		e["hp"] = 10
		var evs: Array = _cast(g, int(pair[0]), Vector2i(1, 0))
		_ok(_evs(evs, "illegal").is_empty() and e["pos"] == pair[1] and e["hp"] == 10 and _evs(evs, "staggered").size() == 1,
			"%s shoves the adjacent enemy to %s: %s %s" % [kit[pair[0]], str(pair[1]), str(e["pos"]), str(evs)])
	# reach: smoke at distance 4 (6,3) is cleared by the + form only; distance 3 by both
	for pair in [[0, true], [1, false]]:
		var g = _game_on(LANE, kit)
		g.terrain[Vector2i(5, 3)] = {"kind": "smoke", "ttl": 3}
		g.terrain[Vector2i(6, 3)] = {"kind": "smoke", "ttl": 3}
		var evs: Array = _cast(g, int(pair[0]), Vector2i(1, 0))
		_ok(_evs(evs, "illegal").is_empty() and g._terrain_kind(Vector2i(5, 3)) == "", "%s clears smoke at distance 3" % kit[pair[0]])
		_ok((g._terrain_kind(Vector2i(6, 3)) == "") == bool(pair[1]) and _evs(evs, "smoke_cleared").size() == (2 if pair[1] else 1),
			"%s smoke at distance 4 cleared = %s: %s" % [kit[pair[0]], str(pair[1]), str(evs)])
	# an enemy at distance 4 is in reach for the + form only (shoved the full 4 to (10,3))
	for pair in [[0, Vector2i(10, 3)], [1, Vector2i(6, 3)]]:
		var g = _game_on(LANE, kit)
		var e = g._spawn("drill_bot", Vector2i(6, 3))
		e["hp"] = 10
		var evs: Array = _cast(g, int(pair[0]), Vector2i(1, 0))
		_ok(_evs(evs, "illegal").is_empty() and e["pos"] == pair[1], "%s vs an enemy at distance 4: %s" % [kit[pair[0]], str(e["pos"])])
	_ok(int(Content.ABILITIES["gust"]["cost"]) == 1 and int(Content.ABILITIES["gust+"]["cost"]) == 1, "gust costs stay 1")
	_ok(_evs(_cast(_game_on(LANE, kit), 0, Vector2i(1, 0)), "rider").is_empty(), "gust+ carries no rider")


## updraft+ {dash_dir, range 4}: the dash runs one tile further; walls and
## enemies still stop it early.
func _check_c4_updraft() -> void:
	var kit := ["updraft+", "updraft", "mycelium_dash"]
	for pair in [[0, Vector2i(6, 3)], [1, Vector2i(5, 3)]]:
		var g = _game_on(LANE, kit)
		var evs: Array = _cast(g, int(pair[0]), Vector2i(1, 0))
		_ok(_evs(evs, "illegal").is_empty() and g.player["pos"] == pair[1] and _evs(evs, "dash").size() == 1 and g.moved_this_turn == 4 - pair[0],
			"%s dashes to %s: %s %s" % [kit[pair[0]], str(pair[1]), str(g.player["pos"]), str(evs)])
	# an enemy in the lane stops the + dash short
	var g2 = _game_on(LANE, kit)
	g2._spawn("drill_bot", Vector2i(5, 3))
	var evs2: Array = _cast(g2, 0, Vector2i(1, 0))
	_ok(_evs(evs2, "illegal").is_empty() and g2.player["pos"] == Vector2i(4, 3), "updraft+ stops before an enemy: %s" % str(g2.player["pos"]))
	# a wall one tile away: the dash is a single step
	var g3 = _game_on(LANE, kit)
	var evs3: Array = _cast(g3, 0, Vector2i(-1, 0))
	_ok(_evs(evs3, "illegal").is_empty() and g3.player["pos"] == Vector2i(1, 3), "updraft+ west stops at the wall: %s" % str(g3.player["pos"]))
	_ok(int(Content.ABILITIES["updraft"]["cost"]) == 1 and int(Content.ABILITIES["updraft+"]["cost"]) == 1, "updraft costs stay 1")


## clear_air+ {clear_smoke radius 4, push_all dist 2}: smoke at distance 4 goes
## and adjacent enemies are shoved 2 instead of 1.
func _check_c4_clear_air() -> void:
	for pair in [["clear_air+", 4, 2], ["clear_air", 3, 1]]:
		var aid: String = pair[0]
		var radius: int = pair[1]
		var dist: int = pair[2]
		var g = _game([aid, "seed_bomb", "mycelium_dash"])
		g.terrain[Vector2i(8, 3)] = {"kind": "smoke", "ttl": 3}   # distance 3
		g.terrain[Vector2i(9, 3)] = {"kind": "smoke", "ttl": 3}   # distance 4
		g.terrain[Vector2i(7, 1)] = {"kind": "smoke", "ttl": 3}   # distance 4 (2 + 2)
		g.terrain[Vector2i(5, 4)] = {"kind": "oil"}                # not smoke: untouched
		var e = g._spawn("drill_bot", Vector2i(4, 3))
		e["hp"] = 10
		var evs: Array = _cast(g, 0, g.player["pos"])
		_ok(_evs(evs, "illegal").is_empty() and g._terrain_kind(Vector2i(8, 3)) == "", "%s clears smoke at distance 3: %s" % [aid, str(evs)])
		_ok((g._terrain_kind(Vector2i(9, 3)) == "") == (radius == 4) and (g._terrain_kind(Vector2i(7, 1)) == "") == (radius == 4),
			"%s (radius %d) at distance 4: %s %s" % [aid, radius, g._terrain_kind(Vector2i(9, 3)), g._terrain_kind(Vector2i(7, 1))])
		_ok(_evs(evs, "smoke_cleared").size() == (3 if radius == 4 else 1) and g._terrain_kind(Vector2i(5, 4)) == "oil",
			"%s smoke_cleared events, oil kept: %s" % [aid, str(evs)])
		_ok(e["pos"] == Vector2i(4 - dist, 3) and e["hp"] == 10 and _evs(evs, "staggered").size() == 1,
			"%s shoves the adjacent enemy %d: %s" % [aid, dist, str(e["pos"])])
		_ok(_evs(evs, "rider").is_empty() and _evs(evs, "ability").size() == 1, "%s no rider, one ability event" % aid)
		_ok(int(Content.ABILITIES[aid]["cost"]) == 2, "%s cost stays 2" % aid)


# --- Block C4: effective casts, run summary, mutators as data ------------------

## Game.effective_uses counts a cast only when an effect outcome fired or a
## rider ran; player.uses counts every legal cast. Keyed by base id, copied by
## clone(), never in snapshot().
func _check_c4_effective_uses() -> void:
	# a lance into an empty lane: a use, not an effective one
	var g = _game(["solar_lance", "grow_spike", "mycelium_dash"])
	var evs: Array = _cast(g, 0, Vector2i(1, 0))
	_ok(_evs(evs, "illegal").is_empty() and int(g.player["uses"].get("solar_lance", 0)) == 1,
		"empty-lane lance is a use: %s" % str(g.player["uses"]))
	_ok(not g.effective_uses.has("solar_lance"), "empty-lane lance is not effective: %s" % str(g.effective_uses))
	# a grow_spike that hits: a use and an effective use
	var t := Vector2i(8, 3)
	var e = g._spawn("drill_bot", t)
	e["hp"] = 10
	g.terrain[t] = {"kind": "growth"}
	evs = _cast(g, 1, t)
	_ok(_evs(evs, "illegal").is_empty() and e["hp"] == 7, "grow_spike hit: hp %d" % e["hp"])
	_ok(int(g.player["uses"].get("grow_spike", 0)) == 1 and int(g.effective_uses.get("grow_spike", 0)) == 1,
		"grow_spike hit is a use and effective: %s %s" % [str(g.player["uses"]), str(g.effective_uses)])
	# a grow_spike whose only legal target is gone by cast time cannot be cast
	# (illegal, no use); the empty-lane lance above is the raw-not-effective case
	# a + form folds onto the base id; the lance now hits the enemy
	g.player["kit"][0] = "solar_lance+"
	e["pos"] = Vector2i(7, 3)
	evs = _cast(g, 0, Vector2i(1, 0))
	_ok(_evs(evs, "illegal").is_empty() and _dmg(evs, "solar_lance+").size() == 1, "solar_lance+ hits: %s" % str(evs))
	_ok(int(g.effective_uses.get("solar_lance", 0)) == 1 and not g.effective_uses.has("solar_lance+"),
		"solar_lance+ effective cast folds onto solar_lance: %s" % str(g.effective_uses))
	_ok(int(g.player["uses"].get("solar_lance+", 0)) == 1 and int(g.player["uses"].get("solar_lance", 0)) == 1,
		"raw uses keep both keys: %s" % str(g.player["uses"]))
	# clone copies, and a cast on the clone never leaks back
	var c = g.clone()
	_ok(c.effective_uses == g.effective_uses, "clone copies effective_uses: %s" % str(c.effective_uses))
	var ce = c._spawn("drill_bot", t)
	ce["hp"] = 10
	_cast(c, 1, t)
	_ok(int(c.effective_uses.get("grow_spike", 0)) == 2 and int(g.effective_uses.get("grow_spike", 0)) == 1,
		"clone effective_uses is a copy: clone %s game %s" % [str(c.effective_uses), str(g.effective_uses)])
	# not in the snapshot: the hash never churns on it
	var snap: Dictionary = g.snapshot()
	_ok(not snap.has("effective_uses") and not snap["player"].has("effective_uses"), "snapshot carries no effective_uses")
	var h1: String = g.state_hash()
	g.effective_uses["grow_spike"] = 99
	_ok(g.state_hash() == h1, "state_hash ignores effective_uses")
	# a fresh game starts empty; a rider-carrying cast counts once
	_ok(_game().effective_uses.is_empty(), "fresh game has no effective uses")


## run_summary(): the compact end-of-run record. Exact key set; uses_by_base
## folds + keys onto the base with the larger count (the + key was seeded
## with the base's count at upgrade time, so a sum would double count).
func _check_c4_run_summary() -> void:
	var g = Game.new(7, {"mutators": ["brittle"], "packages": ["mycology"], "tier": 2, "grafts": ["carapace"]})
	g.player["uses"] = {"solar_lance": 2, "solar_lance+": 5, "seed_bomb": 3}
	g.effective_uses = {"solar_lance": 4, "seed_bomb": 1}
	g.player["kit"] = ["solar_lance+", "seed_bomb", "mycelium_dash"]
	g.bloom = 11
	g.total_turns = 40
	g.death_cause = "drill_bot"
	var sm: Dictionary = g.run_summary()
	var want := ["won", "floor", "turns", "kit", "grafts", "uses_by_base", "effective_uses_by_base",
		"bloom", "death_cause", "seed", "tier", "mutators", "packages", "loadout"]
	var keys: Array = sm.keys()
	keys.sort()
	want.sort()
	_ok(keys == want, "run_summary keys: %s" % str(keys))
	_ok(sm["won"] == false and int(sm["floor"]) == 1 and int(sm["turns"]) == 40 and int(sm["bloom"]) == 11
		and String(sm["death_cause"]) == "drill_bot" and int(sm["seed"]) == 7 and int(sm["tier"]) == 2,
		"run_summary scalars: %s" % str(sm))
	_ok(sm["kit"] == ["solar_lance+", "seed_bomb", "mycelium_dash"] and sm["grafts"] == ["carapace"]
		and sm["mutators"] == ["brittle"] and sm["packages"] == ["mycology"] and String(sm["loadout"]) == "tender",
		"run_summary lists: %s" % str(sm))
	_ok(sm["uses_by_base"] == {"solar_lance": 5, "seed_bomb": 3}, "uses_by_base folds + onto base: %s" % str(sm["uses_by_base"]))
	_ok(sm["effective_uses_by_base"] == {"solar_lance": 4, "seed_bomb": 1}, "effective_uses_by_base: %s" % str(sm["effective_uses_by_base"]))
	sm["kit"].append("x")
	sm["effective_uses_by_base"]["x"] = 1
	_ok(g.player["kit"].size() == 3 and not g.effective_uses.has("x"), "run_summary hands out copies")
	# a won game reports won and the last floor
	var w = Game.new(3)
	w.won = true
	w.over = true
	w.floor_num = Content.FLOORS.size()
	_ok(w.run_summary()["won"] == true and int(w.run_summary()["floor"]) == Content.FLOORS.size(), "won summary")


## Mutators as data: Game._mut scans Content.MUTATORS[m]["config"] in held
## order (scalar: first hit; array: concatenation; default otherwise). The six
## legacy rows reproduce their numbers; the three C4 rows hold their invariants.
func _check_c4_mutator_config() -> void:
	# _mut semantics
	var g = Game.new(1, {"mutators": ["kit_of_3", "brittle"]})
	_ok(int(g._mut("kit_max", 9)) == 3 and int(g._mut("max_hp_delta", 0)) == -3, "_mut reads both held rows")
	_ok(int(g._mut("bank_cap", -1)) == -1 and g._mut("pool_ban", []) == [], "_mut default when no held row carries the key")
	g.mutators = ["no_lance", "no_lance"]
	_ok(g._mut("pool_ban", []) == ["solar_lance", "solar_lance"], "_mut concatenates array keys: %s" % str(g._mut("pool_ban", [])))
	g.mutators = ["brittle", "not_a_mutator"]
	_ok(int(g._mut("max_hp_delta", 0)) == -3 and int(g._mut("kit_max", 5)) == 5, "_mut skips unknown ids")
	_ok(Game.new(1)._mut("kit_max", Content.KIT_MAX) == Content.KIT_MAX, "_mut with no mutators is the default")
	for k in Content.MUTATOR_CONFIG_KEYS:
		var seen := false
		for m in Content.MUTATORS:
			if Content.MUTATORS[m]["config"].has(k):
				seen = true
		_ok(seen, "config key %s is carried by some mutator row" % k)
	# the six legacy rows
	_ok(Game.new(1, {"mutators": ["kit_of_3"]})._kit_max() == 3 and Game.new(1)._kit_max() == Content.KIT_MAX, "kit_of_3 -> kit_max 3")
	var b = Game.new(1, {"mutators": ["brittle"]})
	_ok(b.player["max_hp"] == Content.PLAYER_HP - 3 and b.player["hp"] == Content.PLAYER_HP - 3, "brittle -> -3 max hp")
	_ok(Game.new(1, {"mutators": ["parched"]})._bank_cap() == 0 and Game.new(1)._bank_cap() == Content.BANK_CAP, "parched -> bank cap 0")
	_ok(Game.new(1, {"mutators": ["parched"], "grafts": ["deep_cells"]})._bank_cap() == 0, "parched beats a bank_cap graft")
	var d = Game.new(1, {"mutators": ["double_oil"]})
	_ok(int(d.floor_def(1)["oil"]) == int(Content.FLOORS[0]["oil"]) * 2 and int(Game.new(1).floor_def(1)["oil"]) == int(Content.FLOORS[0]["oil"]),
		"double_oil -> oil x2")
	var o = Game.new(1, {"mutators": ["overtime"]})
	var base_enemies: Dictionary = Content.FLOORS[0]["enemies"]
	var common := ""
	var common_n := 0
	for kind in base_enemies:
		if int(base_enemies[kind]) > common_n:
			common_n = int(base_enemies[kind])
			common = kind
	_ok(int(o.floor_def(1)["enemies"][common]) == common_n + 1, "overtime -> +1 %s" % common)
	_ok(o.floor_def(Content.FLOORS.size())["enemies"] == Content.FLOORS[Content.FLOORS.size() - 1]["enemies"], "overtime leaves the boss floor alone")
	_ok(Game.new(1, {"mutators": ["boarded"]}).shop.is_empty() and not Game.new(1).shop.is_empty(), "boarded -> shop {}")
	# no_lance: kit of 2 without solar_lance, pool without it, shop stock follows
	var nl = Game.new(1, {"mutators": ["no_lance"]})
	_ok(nl.player["kit"] == ["seed_bomb", "mycelium_dash"], "no_lance kit: %s" % str(nl.player["kit"]))
	_ok(not nl.draft_pool.has("solar_lance") and nl.draft_pool.size() == Content.DRAFT_POOL.size() - 1, "no_lance pool: %s" % str(nl.draft_pool))
	_ok(nl.snapshot()["pool"] == nl.draft_pool, "no_lance pool in the snapshot")
	var nl2 = Game.new(1, {"mutators": ["no_lance"], "kit": ["solar_lance+", "seed_bomb"], "pool": ["solar_lance", "vine_whip"]})
	_ok(nl2.player["kit"] == ["seed_bomb"] and nl2.draft_pool == ["vine_whip"], "no_lance strips the + form and a custom pool: %s %s" % [str(nl2.player["kit"]), str(nl2.draft_pool)])
	var lance_stocked := 0
	for s in range(1, 21):
		var gs = Game.new(s, {"mutators": ["no_lance"]})
		if String(gs.shop.get("ability", "")) == "solar_lance":
			lance_stocked += 1
		gs.player["pos"] = gs.map["stairs"]
		gs.greened = gs.green_need
		gs.step({"type": "descend"})
		if gs.draft_offers.has("solar_lance"):
			lance_stocked += 1
	_ok(lance_stocked == 0, "no_lance: no solar_lance in 20 seeds of shop stock or first draft")
	_ok(Game.new(5, {"mutators": ["no_lance"]}).rng.state == Game.new(5).rng.state, "no_lance never touches the main rng at Game.new")
	# wide_draft: the first draft offers 4 (3 in the base game)
	for pair in [[["wide_draft"], 4], [[], 3]]:
		var wd = Game.new(2, {"mutators": pair[0]})
		wd.player["pos"] = wd.map["stairs"]
		wd.greened = wd.green_need
		wd.step({"type": "descend"})
		_ok(wd.phase == "draft" and wd.draft_offers.size() == int(pair[1]), "mutators %s: first draft offers %s" % [str(pair[0]), str(wd.draft_offers)])
	_ok(Game.new(5, {"mutators": ["wide_draft"]}).rng.state == Game.new(5).rng.state, "wide_draft never touches the main rng at Game.new")
	# upgrades_only: only + forms of held abilities; none available -> skipped
	var uo = Game.new(2, {"mutators": ["upgrades_only"]})
	uo.player["pos"] = uo.map["stairs"]
	uo.greened = uo.green_need
	uo.step({"type": "descend"})
	var all_plus: bool = uo.phase == "draft" and not uo.draft_offers.is_empty()
	for aid in uo.draft_offers:
		if not String(aid).ends_with("+") or not uo.player["kit"].has(String(aid).trim_suffix("+")):
			all_plus = false
	_ok(all_plus, "upgrades_only: first draft offers only + forms of the kit: %s" % str(uo.draft_offers))
	var uo2 = Game.new(2, {"mutators": ["upgrades_only"], "kit": ["solar_lance+", "seed_bomb+", "mycelium_dash+"]})
	uo2.player["pos"] = uo2.map["stairs"]
	uo2.greened = uo2.green_need
	var evs: Array = uo2.step({"type": "descend"})
	_ok(uo2.phase == "play" and uo2.floor_num == 2 and _evs(evs, "draft_offer").is_empty(),
		"upgrades_only with an all-+ kit skips the draft: phase %s floor %d" % [uo2.phase, uo2.floor_num])
	_ok(Game.new(5, {"mutators": ["upgrades_only"]}).rng.state == Game.new(5).rng.state, "upgrades_only never touches the main rng at Game.new")
	# every MUTATORS row builds and steps without an error event
	for m in Content.MUTATORS:
		var gm = Game.new(3, {"mutators": [m]})
		var bad := false
		for i in 5:
			for ev in gm.step({"type": "end_turn"}):
				if String(ev.get("t", "")) == "error":
					bad = true
		_ok(not bad and gm.snapshot()["mutators"] == [m], "mutator %s runs five end_turns clean" % m)


# --- Block D1: per-ability stat surges and Spore Trail --------------------------

## Fresh game on ROOM with the kit, the tender standing on growth when `on`.
static func _game_on_growth(kit: Array, on: bool) -> RefCounted:
	var g = _game(kit)
	if on:
		g.terrain[g.player["pos"]] = {"kind": "growth"}
	return g


## Game._surges is the one rule: growth underfoot AND a surge dict that applies
## (a cost delta on cost >= 2, or any stat key). The cost formula is unchanged
## for every row on and off growth; a default-surge cost-1 row never surges and
## never consumes the tile; a default-surge cost-2 row surges (verdant) with no
## surge event; a stat surge emits {t: surge, id, keys} once with only the stat keys.
func _check_d1_surge_rule() -> void:
	var g = _game_on_growth(["solar_lance", "seed_bomb", "sap_snare"], true)
	var p: Vector2i = g.player["pos"]
	# off growth nothing surges
	g.terrain.erase(p)
	var none := 0
	for aid in Content.ABILITIES:
		if g._surges(Content.ABILITIES[aid]):
			none += 1
	_ok(none == 0, "off growth no row surges (%d did)" % none)
	# on growth: cost >= 2 rows and the seven stat rows surge, default cost-1 rows do not
	g.terrain[p] = {"kind": "growth"}
	var bad: Array = []
	for aid in Content.ABILITIES:
		var adef: Dictionary = Content.ABILITIES[aid]
		var want: bool = int(adef["cost"]) >= 2 or adef.has("surge")
		if g._surges(adef) != want:
			bad.append(aid)
	_ok(bad.is_empty(), "on growth surges == (cost >= 2 or a D1 stat row): wrong for %s" % str(bad))
	# hand-built rows pin the rule's edges: {cost: 0} on a cost-2 row lowers nothing
	# -> no surge; a stat key on a cost-1 row -> surge; the default on cost 1 -> no
	_ok(not g._surges({"cost": 2, "surge": {"cost": 0}, "effects": []}), "a cost delta that lowers nothing does not surge")
	_ok(g._surges({"cost": 1, "surge": {"dmg": 1}, "effects": []}), "a stat key on a cost-1 row surges")
	_ok(not g._surges({"cost": 1, "effects": []}), "the default surge on a cost-1 row never surges")
	_ok(g._surges({"cost": 3, "effects": []}), "the default surge on a cost-3 row surges")
	_ok(g._surge_stats({"cost": -1, "radius": 1, "dmg": 2}) == {"radius": 1, "dmg": 2}, "_surge_stats drops cost")
	# cost-1 default row (sap_snare) cast on growth: no verdant, growth stays, cost 1
	var e = g._spawn("drill_bot", Vector2i(8, 3))
	var evs: Array = _cast(g, 2, Vector2i(8, 3))
	_ok(_evs(evs, "illegal").is_empty() and _evs(evs, "verdant").is_empty() and _evs(evs, "surge").is_empty()
		and g._terrain_kind(p) == "growth" and g.player["charge"] == 9 and int(e["status"].get("root", 0)) == 2,
		"sap_snare (cost 1, default surge) on growth: no verdant, growth kept, cost 1: %s" % str(evs))
	# cost-2 default row (solar_lance) on growth: verdant, cost 1, no surge event
	evs = _cast(g, 0, Vector2i(1, 0))
	_ok(_evs(evs, "illegal").is_empty() and _evs(evs, "verdant").size() == 1 and _evs(evs, "surge").is_empty()
		and g._terrain_kind(p) == "" and g.player["charge"] == 9,
		"solar_lance on growth: verdant, cost 1, no surge event: %s" % str(evs))
	# ability_cost is the same function on and off growth for every row
	var cost_bad: Array = []
	for aid in Content.ABILITIES:
		var base := int(Content.ABILITIES[aid]["cost"])
		g.terrain.erase(p)
		if g.ability_cost(aid) != base:
			cost_bad.append(aid)
		g.terrain[p] = {"kind": "growth"}
		if g.ability_cost(aid) != (maxi(1, base - 1) if base >= 2 else base):
			cost_bad.append(aid)
	_ok(cost_bad.is_empty(), "ability_cost unchanged on/off growth: %s" % str(cost_bad))
	print("D1 surge rule: %d abilities checked" % Content.ABILITIES.size())


## grow_spike {dmg 3, per cap 1, surge dmg 1}: 3 off growth, 4 on growth (tile
## consumed, surge event keys [dmg]); with adjacent growth 4 off / 5 on. The +
## form (cap 2) reaches 6 on growth with two adjacent growth tiles. Cost stays 1.
func _check_d1_grow_spike() -> void:
	var t := Vector2i(8, 3)
	var p := Vector2i(5, 3)
	# off growth: 3, no verdant, no surge
	var g = _game_on_growth(["grow_spike", "seed_bomb", "mycelium_dash"], false)
	var e = g._spawn("drill_bot", t)
	e["hp"] = 10
	g.terrain[t] = {"kind": "growth"}
	var evs: Array = _cast(g, 0, t)
	_ok(_evs(evs, "illegal").is_empty() and e["hp"] == 7 and _evs(evs, "verdant").is_empty() and _evs(evs, "surge").is_empty(),
		"grow_spike off growth: 3, no verdant/surge: hp %d %s" % [e["hp"], str(evs)])
	# on growth: 4, tile consumed, one surge event, cost 1
	g.terrain[p] = {"kind": "growth"}
	evs = _cast(g, 0, t)
	var sg := _evs(evs, "surge")
	_ok(_evs(evs, "illegal").is_empty() and e["hp"] == 3, "grow_spike on growth: 4: hp %d %s" % [e["hp"], str(evs)])
	_ok(_evs(evs, "verdant").size() == 1 and g._terrain_kind(p) == "" and g._terrain_kind(t) == "growth",
		"grow_spike on growth consumes the tile underfoot only: %s" % str(evs))
	_ok(sg.size() == 1 and String(sg[0]["id"]) == "grow_spike" and sg[0]["keys"] == ["dmg"], "one surge event, keys [dmg]: %s" % str(sg))
	_ok(g.player["charge"] == 9, "grow_spike still costs 1 on growth: charge %d" % g.player["charge"])
	_ok(_dmg(evs, "grow_spike").size() == 1 and int(_dmg(evs, "grow_spike")[0]["amt"]) == 4, "a single 4-damage event")
	_ok(int(g.effective_uses.get("grow_spike", 0)) == 2, "both casts effective: %s" % str(g.effective_uses))
	# adjacent growth: per rides on top of the surge (3 + 1 surge + 1 per = 5), cap 1 holds with two
	e["hp"] = 10
	g.terrain[p] = {"kind": "growth"}
	g.terrain[Vector2i(8, 2)] = {"kind": "growth"}
	g.terrain[Vector2i(8, 4)] = {"kind": "growth"}
	evs = _cast(g, 0, t)
	var per := _riders(evs, "per")
	_ok(e["hp"] == 5 and per.size() == 1 and int(per[0]["amt"]) == 1 and _evs(evs, "surge").size() == 1,
		"grow_spike on growth with 2 adjacent: 5 (cap 1): hp %d %s" % [e["hp"], str(evs)])
	# + form: 3 + 1 surge + 2 per = 6
	var g2 = _game_on_growth(["grow_spike+", "seed_bomb", "mycelium_dash"], true)
	var e2 = g2._spawn("drill_bot", t)
	e2["hp"] = 10
	g2.terrain[t] = {"kind": "growth"}
	g2.terrain[Vector2i(8, 2)] = {"kind": "growth"}
	g2.terrain[Vector2i(8, 4)] = {"kind": "growth"}
	evs = _cast(g2, 0, t)
	per = _riders(evs, "per")
	_ok(_evs(evs, "illegal").is_empty() and e2["hp"] == 4 and per.size() == 1 and int(per[0]["amt"]) == 2,
		"grow_spike+ on growth with 2 adjacent: 6: hp %d %s" % [e2["hp"], str(evs)])
	_ok(_evs(evs, "surge").size() == 1 and String(_evs(evs, "surge")[0]["id"]) == "grow_spike+" and _evs(evs, "verdant").size() == 1
		and g2._terrain_kind(p) == "" and g2.player["charge"] == 9, "grow_spike+ surge event, verdant, cost 1: %s" % str(evs))
	# off growth the + form is the C2 5
	e2["hp"] = 10
	evs = _cast(g2, 0, t)
	_ok(e2["hp"] == 5 and _evs(evs, "surge").is_empty() and _evs(evs, "verdant").is_empty(), "grow_spike+ off growth: 5, no surge: hp %d" % e2["hp"])


## water_jet {wash_push 2 / 2, surge push 1 / collision_dmg 1}: an enemy two
## tiles out is shoved 2 to the wall's neighbour off growth (no hit); on growth
## the shove is 3 and collides for 3. water_jet+ (3 / 3) becomes 4 / 4 and its
## then-root still lands. Cost stays 1, the tile is consumed.
func _check_d1_water_jet() -> void:
	var p := Vector2i(5, 3)
	var g = _game_on_growth(["water_jet", "seed_bomb", "mycelium_dash"], false)
	var e = g._spawn("drill_bot", Vector2i(7, 3))
	e["hp"] = 10
	var evs: Array = _cast(g, 0, Vector2i(1, 0))
	_ok(_evs(evs, "illegal").is_empty() and e["pos"] == Vector2i(9, 3) and e["hp"] == 10 and _evs(evs, "surge").is_empty(),
		"water_jet off growth: shoved 2 to (9,3), no collision: %s hp %d" % [str(e["pos"]), e["hp"]])
	e["pos"] = Vector2i(7, 3)
	e["status"] = {}
	g.terrain[p] = {"kind": "growth"}
	evs = _cast(g, 0, Vector2i(1, 0))
	var sg := _evs(evs, "surge")
	_ok(_evs(evs, "illegal").is_empty() and e["pos"] == Vector2i(9, 3) and e["hp"] == 7,
		"water_jet on growth: shoved 3 into the wall, 3 collision dmg: %s hp %d %s" % [str(e["pos"]), e["hp"], str(evs)])
	_ok(sg.size() == 1 and String(sg[0]["id"]) == "water_jet" and sg[0]["keys"] == ["push", "collision_dmg"],
		"water_jet surge event keys [push, collision_dmg]: %s" % str(sg))
	_ok(_evs(evs, "verdant").size() == 1 and g._terrain_kind(p) == "" and g.player["charge"] == 9,
		"water_jet on growth: verdant, tile consumed, cost 1: %s" % str(evs))
	_ok(_dmg(evs, "collision:water_jet").size() == 1 and int(_dmg(evs, "collision:water_jet")[0]["amt"]) == 3, "collision signed by water_jet for 3: %s" % str(evs))
	# + form: 4 / 4 from (6,3): (7,3) (8,3) (9,3) then the wall -> collided 4, then-root
	var g2 = _game_on_growth(["water_jet+", "seed_bomb", "mycelium_dash"], true)
	var e2 = g2._spawn("drill_bot", Vector2i(6, 3))
	e2["hp"] = 10
	evs = _cast(g2, 0, Vector2i(1, 0))
	_ok(_evs(evs, "illegal").is_empty() and e2["pos"] == Vector2i(9, 3) and e2["hp"] == 6 and int(e2["status"].get("root", 0)) == 1,
		"water_jet+ on growth: shoved 3 (push 4) into the wall for 4, rooted: %s hp %d %s" % [str(e2["pos"]), e2["hp"], str(e2["status"])])
	_ok(_evs(evs, "surge").size() == 1 and _riders(evs, "then").size() == 1 and _evs(evs, "verdant").size() == 1 and g2.player["charge"] == 9,
		"water_jet+ surge + then rider + verdant, cost 1: %s" % str(evs))
	# off growth the + form from (6,3) stops at (9,3) without a hit (push 3)
	var g3 = _game_on_growth(["water_jet+", "seed_bomb", "mycelium_dash"], false)
	var e3 = g3._spawn("drill_bot", Vector2i(6, 3))
	e3["hp"] = 10
	evs = _cast(g3, 0, Vector2i(1, 0))
	_ok(e3["pos"] == Vector2i(9, 3) and e3["hp"] == 10 and not e3["status"].has("root") and _evs(evs, "surge").is_empty(),
		"water_jet+ off growth: push 3, no collision, no root: %s hp %d" % [str(e3["pos"]), e3["hp"]])


## sun_flare {aoe_damage 1 radius 2, surge cost -1 radius 1}: on growth it costs
## 1 and reaches distance 3 (distance 4 never); off growth cost 2, distance 3
## untouched. The surge event names only the stat key (radius), the cost half
## is the verdant discount. Same for the + form (dmg 2).
func _check_d1_sun_flare() -> void:
	for pair in [["sun_flare", 1], ["sun_flare+", 2]]:
		var aid: String = pair[0]
		var base: int = pair[1]
		var g = _game_on_growth([aid, "seed_bomb", "mycelium_dash"], false)
		var near = g._spawn("drill_bot", Vector2i(7, 3))   # distance 2
		var edge = g._spawn("drill_bot", Vector2i(8, 3))   # distance 3
		var far = g._spawn("drill_bot", Vector2i(9, 3))    # distance 4
		for e in [near, edge, far]:
			e["hp"] = 10
		var evs: Array = _cast(g, 0, g.player["pos"])
		_ok(_evs(evs, "illegal").is_empty() and near["hp"] == 10 - base and edge["hp"] == 10 and far["hp"] == 10,
			"%s off growth: radius 2, cost 2: hp %d %d %d" % [aid, near["hp"], edge["hp"], far["hp"]])
		_ok(g.player["charge"] == 8 and _evs(evs, "surge").is_empty() and _evs(evs, "verdant").is_empty(), "%s off growth costs 2, no surge" % aid)
		for e in [near, edge, far]:
			e["hp"] = 10
		g.terrain[g.player["pos"]] = {"kind": "growth"}
		evs = _cast(g, 0, g.player["pos"])
		var sg := _evs(evs, "surge")
		_ok(_evs(evs, "illegal").is_empty() and near["hp"] == 10 - base and edge["hp"] == 10 - base and far["hp"] == 10,
			"%s on growth: radius 3 reaches distance 3, not 4: hp %d %d %d" % [aid, near["hp"], edge["hp"], far["hp"]])
		_ok(g.player["charge"] == 9 and _evs(evs, "verdant").size() == 1 and g._terrain_kind(g.player["pos"]) == "",
			"%s on growth costs 1 and consumes the tile: charge %d" % [aid, g.player["charge"]])
		_ok(sg.size() == 1 and String(sg[0]["id"]) == aid and sg[0]["keys"] == ["radius"], "%s surge event keys [radius]: %s" % [aid, str(sg)])
		_ok(g.ability_cost(aid) == 2, "%s ability_cost is 2 again off growth" % aid)


## seed_bomb+ {grow_radius 1, then root on_planted, surge radius 1}: on growth
## the cast plants the 13-tile diamond (the consumed tile underfoot included
## when it lies inside), roots an enemy at distance 2 from the target, costs 1
## and consumes the tile; off growth it is the C2 plus. Base seed_bomb keeps the
## default: plus shape on growth too, with the verdant discount and no surge event.
func _check_d1_seed_bomb() -> void:
	var p := Vector2i(5, 3)
	var target := Vector2i(7, 3)
	var g = _game_on_growth(["seed_bomb+", "grow_spike+", "mycelium_dash"], true)
	var ring = g._spawn("drill_bot", Vector2i(9, 3))     # distance 2: diamond only
	var beside = g._spawn("drill_bot", Vector2i(7, 4))   # distance 1: plus
	var evs: Array = _cast(g, 0, target)
	_ok(_evs(evs, "illegal").is_empty() and _evs(evs, "growth").size() == 1, "seed_bomb+ on growth cast legal: %s" % str(evs))
	var planted := 0
	for t in g.terrain:
		if g.terrain[t]["kind"] == "growth":
			planted += 1
	_ok(planted == 13, "seed_bomb+ on growth plants 13 tiles (diamond, consumed tile re-planted): %d" % planted)
	for t in [Vector2i(7, 1), Vector2i(7, 5), Vector2i(5, 3), Vector2i(9, 3), Vector2i(6, 2), Vector2i(8, 4)]:
		_ok(g._terrain_kind(t) == "growth", "diamond tile %s planted" % str(t))
	_ok(g._terrain_kind(Vector2i(6, 1)) == "" and g._terrain_kind(Vector2i(4, 3)) == "", "manhattan 3 is outside the diamond")
	_ok(int(ring["status"].get("root", 0)) == 1 and int(beside["status"].get("root", 0)) == 1,
		"enemies on fresh diamond tiles are rooted: %s %s" % [str(ring["status"]), str(beside["status"])])
	var sg := _evs(evs, "surge")
	_ok(sg.size() == 1 and String(sg[0]["id"]) == "seed_bomb+" and sg[0]["keys"] == ["radius"], "seed_bomb+ surge event keys [radius]: %s" % str(sg))
	_ok(_evs(evs, "verdant").size() == 1 and g.player["charge"] == 9, "seed_bomb+ on growth: verdant, cost 1: charge %d" % g.player["charge"])
	_ok(_riders(evs, "then").size() == 1 and _evs(evs, "status").size() == 2, "then rider once, two roots: %s" % str(_evs(evs, "status")))
	# off growth: the plus, distance 2 untouched, no verdant / surge
	var g2 = _game_on_growth(["seed_bomb+", "grow_spike+", "mycelium_dash"], false)
	var ring2 = g2._spawn("drill_bot", Vector2i(9, 3))
	evs = _cast(g2, 0, target)
	_ok(_evs(evs, "illegal").is_empty() and g2.terrain.size() == 5 and g2._terrain_kind(Vector2i(9, 3)) == "" and not ring2["status"].has("root")
		and _evs(evs, "surge").is_empty() and _evs(evs, "verdant").is_empty() and g2.player["charge"] == 9,
		"seed_bomb+ off growth: plus of 5, no surge: %d tiles %s" % [g2.terrain.size(), str(evs)])
	# base seed_bomb on growth: plus (5 new tiles), verdant discount to 1, no surge event
	var g3 = _game_on_growth(["seed_bomb", "grow_spike+", "mycelium_dash"], true)
	evs = _cast(g3, 0, target)
	_ok(_evs(evs, "illegal").is_empty() and g3.terrain.size() == 5 and g3._terrain_kind(p) == "" and g3._terrain_kind(Vector2i(9, 3)) == "",
		"base seed_bomb on growth: plus only, tile underfoot consumed: %d tiles" % g3.terrain.size())
	_ok(_evs(evs, "verdant").size() == 1 and _evs(evs, "surge").is_empty() and g3.player["charge"] == 9,
		"base seed_bomb on growth: verdant, cost 1, no surge event: %s" % str(evs))
	# base seed_bomb off growth: plus, cost 2
	var g4 = _game_on_growth(["seed_bomb", "grow_spike+", "mycelium_dash"], false)
	evs = _cast(g4, 0, target)
	_ok(g4.terrain.size() == 5 and g4.player["charge"] == 8 and _evs(evs, "verdant").is_empty(), "base seed_bomb off growth: plus, cost 2")


## grow_radius reads eff.radius: 1 is exactly the old plus (target + DIRS, in
## that insertion order - terrain.keys() and the state hash see it), 2 adds
## the 8-tile ring dy then dx ascending; walls and held tiles are skipped;
## planted counts the fresh tiles only.
func _check_d1_grow_radius() -> void:
	var g = _game()
	var target := Vector2i(7, 3)
	var r1 := _run(g, {"op": "grow_radius", "radius": 1}, "seed_bomb", target)
	var want1: Array = [target]
	for d in g.DIRS:
		want1.append(target + d)
	want1.sort()
	var got1: Array = r1[0]["tiles"].duplicate()
	got1.sort()
	_ok(int(r1[0]["planted"]) == 5 and got1 == want1, "grow_radius 1 = the plus: %s" % str(r1[0]["tiles"]))
	_ok(r1[0]["tiles"] == [Vector2i(7, 3), Vector2i(7, 2), Vector2i(8, 3), Vector2i(7, 4), Vector2i(6, 3)],
		"grow_radius 1 plants target then DIRS (the pre-D1 insertion order, hash-visible): %s" % str(r1[0]["tiles"]))
	_ok(_evs(r1[1], "growth").size() == 1, "one growth event per cast")
	# radius 2 on a fresh board: 13 tiles, first (7,1) last (7,5)
	var g2 = _game()
	var r2 := _run(g2, {"op": "grow_radius", "radius": 2}, "seed_bomb", target)
	var tiles2: Array = r2[0]["tiles"]
	_ok(int(r2[0]["planted"]) == 13 and tiles2.size() == 13 and tiles2.slice(0, 5) == r1[0]["tiles"]
		and tiles2.slice(5) == [Vector2i(7, 1), Vector2i(6, 2), Vector2i(8, 2), Vector2i(5, 3), Vector2i(9, 3), Vector2i(6, 4), Vector2i(8, 4), Vector2i(7, 5)],
		"grow_radius 2 = the plus first, then the 8-tile ring dy then dx: %s" % str(tiles2))
	var outside := 0
	for t in tiles2:
		if g2._manhattan(t, target) > 2:
			outside += 1
	_ok(outside == 0, "every diamond tile is within manhattan 2")
	# radius 2 near the wall: the wall tiles and a held tile are skipped
	var g3 = _game()
	g3.terrain[Vector2i(8, 3)] = {"kind": "oil"}
	var r3 := _run(g3, {"op": "grow_radius", "radius": 2}, "seed_bomb", Vector2i(9, 3))
	_ok(int(r3[0]["planted"]) == 8 and not r3[0]["tiles"].has(Vector2i(8, 3)) and g3._terrain_kind(Vector2i(8, 3)) == "oil",
		"grow_radius 2 at (9,3): 9 in-room tiles minus the held one = 8: %s" % str(r3[0]["tiles"]))
	# the shipped rows all carry radius 1 except none: seed_bomb, seed_bomb+, fungal_ring(+)
	for aid in ["seed_bomb", "seed_bomb+", "fungal_ring", "fungal_ring+"]:
		_ok(int(Content.ABILITIES[aid]["effects"][0]["radius"]) == 1, "%s grow_radius radius stays 1" % aid)


## mycelium_dash+ {teleport, plant_origin growth}: the departure tile becomes
## growth when it is bare floor once the tender has left; a tile holding
## terrain, a wall, or a tile with an enemy on it (only reachable through
## _apply_effect directly) is left alone. The planting makes the cast
## effective and counts as planted; the base dash plants nothing.
func _check_d1_spore_trail() -> void:
	var p := Vector2i(5, 3)
	var g = _game(["mycelium_dash+", "seed_bomb", "mycelium_dash"])
	g.terrain[Vector2i(8, 3)] = {"kind": "growth"}
	var evs: Array = _cast(g, 0, Vector2i(8, 3))
	_ok(_evs(evs, "illegal").is_empty() and g.player["pos"] == Vector2i(8, 3) and _evs(evs, "teleport").size() == 1, "mycelium_dash+ teleports: %s" % str(evs))
	_ok(g._terrain_kind(p) == "growth" and g.terrain[p] == {"kind": "growth"}, "the departure tile is growth: %s" % str(g.terrain.get(p)))
	var ter := _evs(evs, "terrain")
	_ok(ter.size() == 1 and String(ter[0]["kind"]) == "growth" and ter[0]["tile"] == p, "terrain event for the planted origin: %s" % str(ter))
	_ok(int(g.effective_uses.get("mycelium_dash", 0)) == 1 and int(g.player["uses"].get("mycelium_dash+", 0)) == 1,
		"a dash that plants is an effective cast: %s" % str(g.effective_uses))
	_ok(g.player["charge"] == 9 and _evs(evs, "verdant").is_empty() and _evs(evs, "surge").is_empty(), "cost 1, no surge (default surge on cost 1)")
	# dashing from growth: the origin holds terrain -> nothing planted, the growth stays (no consumption either)
	g.terrain[Vector2i(2, 3)] = {"kind": "growth"}
	evs = _cast(g, 0, Vector2i(2, 3))
	_ok(_evs(evs, "illegal").is_empty() and g.player["pos"] == Vector2i(2, 3) and g._terrain_kind(Vector2i(8, 3)) == "growth"
		and _evs(evs, "terrain").is_empty() and _evs(evs, "verdant").is_empty(), "from a growth tile: origin kept as growth, nothing planted: %s" % str(evs))
	_ok(int(g.effective_uses.get("mycelium_dash", 0)) == 1, "that dash was not effective: %s" % str(g.effective_uses))
	# origin on oil: the oil stays
	g.terrain[g.player["pos"]] = {"kind": "oil"}
	evs = _cast(g, 0, Vector2i(5, 3))
	_ok(_evs(evs, "illegal").is_empty() and g.player["pos"] == Vector2i(5, 3) and g._terrain_kind(Vector2i(2, 3)) == "oil" and _evs(evs, "terrain").is_empty(),
		"origin holding oil is not overwritten: %s" % g._terrain_kind(Vector2i(2, 3)))
	# direct op: an enemy on the origin tile, or a wall, or the player's own tile -> nothing
	var g2 = _game(["mycelium_dash+", "seed_bomb", "mycelium_dash"])
	var e = g2._spawn("drill_bot", Vector2i(7, 3))
	var eff := {"op": "plant_origin", "kind": "growth"}
	var d: Dictionary = Content.ABILITIES["mycelium_dash+"]
	for origin in [Vector2i(7, 3), Vector2i(0, 3), g2.player["pos"]]:
		var ctx := _ctx(g2, d, Vector2i(8, 3))
		ctx["origin"] = origin
		g2._step_events = []
		var out: Dictionary = g2._apply_effect(eff, d, Vector2i(8, 3), "mycelium_dash+", ctx)
		_ok(int(out["planted"]) == 0 and out["tiles"].is_empty() and not g2.terrain.has(origin) and g2._step_events.is_empty(),
			"plant_origin skips origin %s (enemy / wall / tender still there)" % str(origin))
	_ok(g2._enemy_at(Vector2i(7, 3)) == e, "the enemy is untouched")
	# a bare origin through the op: planted 1, tiles [origin], growth_planted hook tile = origin (compost-free: no hook rows)
	var ctx2 := _ctx(g2, d, Vector2i(8, 3))
	ctx2["origin"] = Vector2i(3, 3)
	g2._step_events = []
	var out2: Dictionary = g2._apply_effect(eff, d, Vector2i(8, 3), "mycelium_dash+", ctx2)
	_ok(int(out2["planted"]) == 1 and out2["tiles"] == [Vector2i(3, 3)] and g2._terrain_kind(Vector2i(3, 3)) == "growth",
		"plant_origin on a bare origin: planted 1, tiles [origin]: %s" % str(out2))
	# on_planted riders see the origin: a then status_target roots an enemy standing there
	# (only constructible through the op, since the tender's own tile never holds an enemy)
	var g3 = _game(["mycelium_dash+", "seed_bomb", "mycelium_dash"])
	var e3 = g3._spawn("drill_bot", Vector2i(3, 3))
	var eff3 := {"op": "plant_origin", "kind": "growth", "then": [{"op": "status_target", "status": "root", "turns": 1, "who": "on_planted"}]}
	var ctx3 := _ctx(g3, d, Vector2i(8, 3))
	ctx3["origin"] = Vector2i(3, 3)
	var out3: Dictionary = g3._apply_effect(eff3, d, Vector2i(8, 3), "probe", ctx3)
	_ok(int(out3["planted"]) == 0 and not e3["status"].has("root"), "an occupied origin is never planted, so on_planted finds nothing")
	# the base dash never plants and is never effective
	var g4 = _game(["mycelium_dash", "seed_bomb", "mycelium_dash+"])
	g4.terrain[Vector2i(8, 3)] = {"kind": "growth"}
	evs = _cast(g4, 0, Vector2i(8, 3))
	_ok(_evs(evs, "illegal").is_empty() and g4.player["pos"] == Vector2i(8, 3) and not g4.terrain.has(p) and g4.effective_uses.is_empty(),
		"base mycelium_dash: no planting, not effective: %s" % str(evs))
	# the row as shipped
	_ok(Content.ABILITIES["mycelium_dash+"]["effects"] == [{"op": "teleport"}, {"op": "plant_origin", "kind": "growth"}]
		and int(Content.ABILITIES["mycelium_dash+"]["cost"]) == 1 and int(Content.ABILITIES["mycelium_dash+"]["range"]) == 7,
		"mycelium_dash+ row: teleport + plant_origin growth, cost 1, range 7")
