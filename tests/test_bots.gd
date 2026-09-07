extends SceneTree
## Bot checks for the deeproot_plan persona (docs/PROGRESSION_REVIEW.md 7.5):
## controlled boards (public vars, as tests/test_grammar.gd builds them),
## bot.set_sim(game), bot.choose_action(game.snapshot(), game.legal_actions()).
##   1) seed on head: plan opens with seed_bomb on / beside the enemy and
##      follows with grow_spike+; legacy deeproot does not open with the bomb
##   2) pin: water_jet+ into a wall (root) valued, the lance as the follow-up
##   3) shrine routing: the field goal is the shrine, the move heads there,
##      on the shrine the highest-weight graft is bought - and the detour is
##      priced per offer (each graft costs what its own Content.GRAFTS row says)
##   3b) shrine detour gates: optimizer and magpie walk to a graft counter only
##      when the purse covers the CHEAPEST offer (snap.shop.graft_prices), not
##      a flat bloom >= 5
##   4) determinism: two fresh instances agree over 40 steps
##   5) runtime factor: deeproot vs deeproot_plan over 5 seeds (test-side
##      Time.get_ticks_msec only; the bots never read a clock)
## Run: godot --headless --path . --script tests/test_bots.gd

const Content := preload("res://sim/content.gd")
const Game := preload("res://sim/game.gd")
const Roster := preload("res://bots/roster.gd")
const Sweep := preload("res://tests/sweep_lib.gd")

const RUNTIME_MAX_FACTOR := 6.0
const RUNTIME_SEEDS := 5

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
	_check_seed_on_head()
	_check_pin()
	_check_shrine_routing()
	_check_shop_detour_gates()
	_check_determinism()
	_check_runtime_factor()
	if failures.is_empty():
		print("bots: OK (%d checks)" % checks)
		quit(0)
	else:
		for f in failures:
			print("FAIL: %s" % f)
		print("bots: %d failure(s) in %d checks" % [failures.size(), checks])
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


## A fresh game on ROOM with the given kit; no enemies, no terrain, charge 3.
static func _game(kit: Array) -> RefCounted:
	return Game.new(1, {"fixed_floor": {"gen": _gen(ROOM), "fdef": {}}, "kit": kit})


static func _bot(name: String, game) -> RefCounted:
	var b = Roster.make(name, 1)
	b.set_sim(game)
	return b


static func _choose(bot, game) -> Dictionary:
	return bot.choose_action(game.snapshot(), game.legal_actions())


static func _kit_id(game, a: Dictionary) -> String:
	if String(a.get("type", "")) != "ability":
		return ""
	return String(game.player["kit"][a["slot"]])


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Player distance to `goal` after stepping `a` on a clone.
static func _shrine_dist_after(game, a: Dictionary, goal: Vector2i) -> int:
	var c = game.clone()
	c.step(a)
	return _manhattan(c.player["pos"], goal)


# --- 1) seed on head ----------------------------------------------------------

func _check_seed_on_head() -> void:
	var kit := ["solar_lance", "seed_bomb", "mycelium_dash", "grow_spike+"]
	var g = _game(kit)
	# two tiles away on the diagonal: no lance line, no growth anywhere
	var e = g._spawn("drill_bot", Vector2i(6, 4))
	g._compute_intents()
	_ok(int(g.player["charge"]) == 3, "fixture charge 3: %d" % int(g.player["charge"]))
	var plan = _bot("deeproot_plan", g)
	var a: Dictionary = _choose(plan, g)
	var aid := _kit_id(g, a)
	_ok(aid == "seed_bomb", "plan opens with seed_bomb: %s (%s)" % [aid, str(a)])
	if aid == "seed_bomb":
		var d := _manhattan(a["target"], e["pos"])
		_ok(d <= 1, "bomb lands on or beside the enemy: target %s enemy %s (d %d)" % [str(a["target"]), str(e["pos"]), d])
	var fu: Dictionary = plan.last_plan.get("followup", {})
	_ok(_kit_id(g, fu) == "grow_spike+", "the plan's follow-up is grow_spike+: %s" % str(fu))
	# legacy deeproot on the same board does not open with the bomb
	var legacy = _bot("deeproot", g)
	var la: Dictionary = _choose(legacy, g)
	var laid := _kit_id(g, la)
	print("seed on head: legacy deeproot opens with %s; deeproot_plan opens with %s" % [
		str(la) + (" (" + laid + ")" if laid != "" else ""), str(a) + " (" + aid + ")"])
	_ok(laid != "seed_bomb", "legacy does not open with seed_bomb: %s" % str(la))
	_ok(la != a, "the two openings differ: legacy %s plan %s" % [str(la), str(a)])
	# play the bomb for real: the option term sees the enemy beside growth,
	# and the next choice is the spike on that enemy
	g.step(a)
	var terms: Dictionary = plan._option_terms(g)
	_ok(float(terms["spike"]) == plan.SPIKE_POINTS, "spike term after the bomb: %s" % str(terms))
	var b: Dictionary = _choose(plan, g)
	_ok(_kit_id(g, b) == "grow_spike+" and b.get("target", null) == e["pos"],
		"next choice is grow_spike+ on the enemy: %s" % str(b))
	var evs: Array = g.step(b)
	var killed := false
	for ev in evs:
		if String(ev.get("t", "")) == "death" or String(ev.get("t", "")) == "kill":
			killed = true
	_ok(not g.enemies.has(e) or killed, "the spike kills the drill bot: enemies %s events %s" % [str(g.enemies), str(evs)])


# --- 2) pin -------------------------------------------------------------------

func _check_pin() -> void:
	var kit := ["water_jet+", "solar_lance", "mycelium_dash"]
	var g = _game(kit)
	g.player["pos"] = Vector2i(6, 3)
	# hulk with one open tile between it and the east wall (10, 3) on the jet
	# line: the jet shoves it one tile and slams it (pushed + collided = root)
	var e = g._spawn("welded_hulk", Vector2i(8, 3))
	g._compute_intents()
	var plan = _bot("deeproot_plan", g)
	var a: Dictionary = _choose(plan, g)
	var terms: Dictionary = plan._option_terms(g)
	_ok(float(terms["pin"]) == 0.0, "no pin yet: an open tile still separates the hulk from the wall: %s" % str(terms))
	_ok(_kit_id(g, a) == "water_jet+" and a.get("target", null) == Vector2i(1, 0), "plan jets the hulk into the wall: %s" % str(a))
	# plan mode values the lance as a follow-up: on the post-jet clone the
	# lance down the same line is enumerated, and its forced continuation
	# scores above both the plain jet-then-end_turn line and a bare end_turn
	var after_jet = g.clone()
	after_jet.step(a)
	var terms2: Dictionary = plan._option_terms(after_jet)
	_ok(float(terms2["pin"]) == plan.PIN_POINTS, "pin term sees the shoved hulk against the wall: %s" % str(terms2))
	var lance: Dictionary = {}
	for f in plan._followups(after_jet, a):
		if _kit_id(after_jet, f) == "solar_lance" and f["target"] == Vector2i(1, 0):
			lance = f
	_ok(not lance.is_empty(), "the lance down the line is an enumerated follow-up")
	var plain = after_jet.clone()
	plain.step({"type": "end_turn"})
	var plain_s: float = plan._score(plain)
	var bare = g.clone()
	bare.step({"type": "end_turn"})
	var bare_s: float = plan._score(bare)
	var lance_s := -1e18
	if not lance.is_empty():
		var g2 = after_jet.clone()
		g2.step(lance)
		g2.step({"type": "end_turn"})
		lance_s = plan._score(g2)
	_ok(lance_s > plain_s and lance_s > bare_s, "jet-then-lance (%.0f) beats jet-then-end_turn (%.0f) and end_turn (%.0f)" % [lance_s, plain_s, bare_s])
	var fu: Dictionary = plan.last_plan.get("followup", {})
	_ok(not fu.is_empty() and fu.get("target", null) == Vector2i(1, 0), "the chosen follow-up fires down the same line: %s" % str(fu))
	print("pin: chosen follow-up after the jet is %s (%s); the lance continuation scores %.0f, the chosen one %.0f" % [
		str(fu), _kit_id(g, fu), lance_s, float(plan.last_plan.get("value", 0.0))])
	g.step(a)
	_ok(e["pos"] == Vector2i(9, 3) and int(e["hp"]) == 4 and e["status"].has("root"),
		"jet: shoved to (9, 3), 3 collision dmg and the root rider: pos %s hp %d status %s" % [str(e["pos"]), int(e["hp"]), str(e["status"])])
	var b: Dictionary = _choose(plan, g)
	_ok(String(b["type"]) == "ability" and b.get("target", null) == Vector2i(1, 0), "next choice keeps hitting down the line: %s" % str(b))
	g.step(b)
	_ok(int(e["hp"]) < 4, "the follow-up lands: hp %d" % int(e["hp"]))


# --- 3) shrine routing --------------------------------------------------------

func _check_shrine_routing() -> void:
	var g = _game(["solar_lance", "seed_bomb", "mycelium_dash"])
	var shrine := Vector2i(7, 3)
	g.map["shrine"] = shrine
	g.map["stairs"] = Vector2i(1, 1)
	g.shop = {"heal": true, "press": true, "forge": true, "grafts": ["thick_bark", "solar_core"], "ability": "vine_whip", "item": "balm_fruit"}
	g.bloom = 12
	var plan = _bot("deeproot_plan", g)
	var a: Dictionary = _choose(plan, g)
	_ok(plan._field_goal == shrine, "field goal is the shrine: %s" % str(plan._field_goal))
	_ok(String(a["type"]) != "end_turn" and _shrine_dist_after(g, a, shrine) <= _manhattan(g.player["pos"], shrine),
		"first action heads for the shrine: %s" % str(a))
	# legacy on the same board heads for the stairs
	var legacy = _bot("deeproot", g)
	_choose(legacy, g)
	_ok(legacy._field_goal == Vector2i(1, 1), "legacy field goal is the stairs: %s" % str(legacy._field_goal))
	# get there: no choice moves away from the shrine, and the bot arrives
	# within four actions (two moves; or a bomb on the shrine and a dash onto
	# the fresh growth, which is the plan the search finds at 3 charge)
	var steps := 0
	var path: Array = []
	while g.player["pos"] != shrine and steps < 4:
		var before := _manhattan(g.player["pos"], shrine)
		path.append(a)
		g.step(a)
		_ok(_manhattan(g.player["pos"], shrine) <= before, "step %d never moves away: %s" % [steps, str(a)])
		steps += 1
		if g.player["pos"] != shrine:
			a = _choose(plan, g)
	print("shrine routing: reached the shrine in %d actions: %s" % [steps, str(path)])
	_ok(g.player["pos"] == shrine, "arrived on the shrine in %d steps" % steps)
	var buy: Dictionary = _choose(plan, g)
	_ok(String(buy["type"]) == "buy" and String(buy["item"]) == "graft" and int(buy["pick"]) == 1,
		"on the shrine the highest-weight graft (solar_core, offer 1) is bought first: %s" % str(buy))
	g.step(buy)
	_ok(g.player["grafts"] == ["solar_core"] and g.bloom == 4,
		"graft installed at its own price, bloom 12 -> 4: %s %d" % [str(g.player["grafts"]), g.bloom])
	# with the graft counter closed and bloom for one more buy, the field
	# goal falls back to the stairs once the shrine has nothing useful left
	_choose(plan, g)
	_ok(plan._field_goal == Vector2i(1, 1), "on the shrine the goal is the stairs again: %s" % str(plan._field_goal))
	# an enemy within 3 cancels the detour on a fresh board
	var g2 = _game(["solar_lance", "seed_bomb", "mycelium_dash"])
	g2.map["shrine"] = shrine
	g2.map["stairs"] = Vector2i(1, 1)
	g2.shop = g.shop.duplicate(true)
	g2.shop["grafts"] = ["thick_bark", "solar_core"]
	g2.bloom = 12
	g2._spawn("drill_bot", Vector2i(5, 1))
	g2._compute_intents()
	var plan2 = _bot("deeproot_plan", g2)
	_choose(plan2, g2)
	_ok(plan2._field_goal != shrine, "an enemy within 3 cancels the shrine goal: %s" % str(plan2._field_goal))
	# no bloom: no detour
	var g3 = _game(["solar_lance", "seed_bomb", "mycelium_dash"])
	g3.map["shrine"] = shrine
	g3.map["stairs"] = Vector2i(1, 1)
	g3.shop = g.shop.duplicate(true)
	g3.shop["grafts"] = ["thick_bark", "solar_core"]
	g3.bloom = 2
	var plan3 = _bot("deeproot_plan", g3)
	_choose(plan3, g3)
	_ok(plan3._field_goal == Vector2i(1, 1), "bloom below the cheapest useful buy: stairs goal: %s" % str(plan3._field_goal))
	# worth test: a weight clears the offer's OWN price, not a flat graft price
	_ok(plan._graft_worth("solar_core", 8) and not plan._graft_worth("thick_bark", 3),
		"the lever clears its 8, the weight-1 stat row never clears its 3")
	_ok(not plan._graft_worth("nonesuch", 1), "an unknown id weighs 0 at any price")
	for gid in Content.GRAFTS:
		_ok(plan.GRAFT_WEIGHTS.has(gid), "GRAFT_WEIGHTS covers %s" % gid)

	# per-offer prices: a Solar Core at 8 is no reason to walk with 6 bloom,
	# a 3-bloom Verdant Pulse on the same counter is. Graft-only shops, so the
	# ability and heal branches cannot price the detour instead.
	var g4 = _game(["solar_lance", "seed_bomb", "mycelium_dash"])
	g4.map["shrine"] = shrine
	g4.map["stairs"] = Vector2i(1, 1)
	g4.bloom = 6
	g4.shop = {"grafts": ["solar_core"]}
	var plan4 = _bot("deeproot_plan", g4)
	var snap4: Dictionary = g4.snapshot()
	_ok(snap4["shop"]["graft_prices"] == [8], "the snapshot prices the lone offer: %s" % str(snap4["shop"].get("graft_prices", [])))
	_ok(plan4._cheapest_useful_buy(snap4) == 8,
		"the cheapest useful buy is the lever's own 8: %d" % plan4._cheapest_useful_buy(snap4))
	_choose(plan4, g4)
	_ok(plan4._field_goal == Vector2i(1, 1),
		"a lever the purse cannot cover is no detour: %s" % str(plan4._field_goal))
	var g5 = _game(["solar_lance", "seed_bomb", "mycelium_dash"])
	g5.map["shrine"] = shrine
	g5.map["stairs"] = Vector2i(1, 1)
	g5.bloom = 6
	g5.shop = {"grafts": ["verdant_pulse", "solar_core"]}
	var plan5 = _bot("deeproot_plan", g5)
	var snap5: Dictionary = g5.snapshot()
	_ok(snap5["shop"]["graft_prices"] == [3, 8],
		"the two offers are priced apart: %s" % str(snap5["shop"].get("graft_prices", [])))
	_ok(plan5._cheapest_useful_buy(snap5) == 3,
		"the cheap stat graft prices the detour: %d" % plan5._cheapest_useful_buy(snap5))
	_choose(plan5, g5)
	_ok(plan5._field_goal == shrine,
		"a 3-bloom graft the purse covers is worth the walk: %s" % str(plan5._field_goal))
	print("graft prices: offers %s at %s bloom; cheapest useful buy %d (purse 6)" % [
		str(g5.shop["grafts"]), str(snap5["shop"]["graft_prices"]), plan5._cheapest_useful_buy(snap5)])


# --- 3b) optimizer / magpie shrine detour gates -------------------------------

## Both personas used to gate the graft detour on a flat bloom >= 5, which with
## per-offer prices (3..8) walks them to counters they cannot buy from. The gate
## now reads snap.shop.graft_prices: offers priced [6, 8] are out of reach at 5
## bloom and in reach at 6. The ability (4) and heal (3) branches are unchanged,
## so these boards stock grafts only.
func _check_shop_detour_gates() -> void:
	var shrine := Vector2i(7, 3)
	var stairs := Vector2i(1, 1)
	for pname in ["optimizer", "magpie"]:
		var seen: Dictionary = {}
		for purse in [5, 6]:
			var g = _game(["solar_lance", "seed_bomb", "mycelium_dash"])
			g.map["shrine"] = shrine
			g.map["stairs"] = stairs
			g.shop = {"grafts": ["compost", "solar_core"]}
			g.bloom = purse
			var snap: Dictionary = g.snapshot()
			_ok(snap["shop"]["graft_prices"] == [6, 8],
				"%s: offers priced [6, 8]: %s" % [pname, str(snap["shop"].get("graft_prices", []))])
			var bot = Roster.make(pname, 1)
			var worth: bool = bot._graft_worth_detour(snap)
			_ok(worth == (purse == 6),
				"%s: purse %d vs cheapest offer 6 -> worth %s" % [pname, purse, str(worth)])
			# and the routing follows the gate: toward the shrine (+x) only at 6
			var step := Vector2i.ZERO
			if pname == "optimizer":
				step = bot._path_step(snap, bot._threat_tiles(snap))
			else:
				var a: Dictionary = bot.choose_action(snap, g.legal_actions())
				if String(a.get("type", "")) == "move":
					step = a["dir"]
			seen[purse] = step
			_ok((step == Vector2i(1, 0)) == (purse == 6),
				"%s: purse %d steps %s (shrine is +x, stairs are -x/-y)" % [pname, purse, str(step)])
		# a graftless counter is never worth a detour on price alone
		var gn = _game(["solar_lance", "seed_bomb", "mycelium_dash"])
		gn.map["shrine"] = shrine
		gn.map["stairs"] = stairs
		gn.shop = {"press": true}
		gn.bloom = 20
		var botn = Roster.make(pname, 1)
		_ok(not botn._graft_worth_detour(gn.snapshot()),
			"%s: no grafts on the counter, no graft detour at 20 bloom" % pname)
		print("detour gate %-9s bloom 5 -> %s, bloom 6 -> %s" % [pname, str(seen[5]), str(seen[6])])


# --- 4) determinism -----------------------------------------------------------

func _check_determinism() -> void:
	var seed_v := 3
	var ga = Game.new(seed_v)
	var gb = Game.new(seed_v)
	var ba = Roster.make("deeproot_plan", seed_v)
	var bb = Roster.make("deeproot_plan", seed_v)
	ba.set_sim(ga)
	bb.set_sim(gb)
	var same := true
	var n := 0
	for i in 40:
		if ga.over or gb.over:
			break
		var a: Dictionary = _choose(ba, ga)
		var b: Dictionary = _choose(bb, gb)
		if a != b:
			same = false
			failures.append("determinism: step %d differs: %s vs %s" % [i, str(a), str(b)])
			break
		ga.step(a)
		gb.step(b)
		n += 1
	_ok(same and ga.state_hash() == gb.state_hash(), "two fresh deeproot_plan instances agree over %d steps" % n)
	print("determinism: %d identical steps on seed %d" % [n, seed_v])


# --- 5) runtime factor --------------------------------------------------------

func _check_runtime_factor() -> void:
	var ms := {"deeproot": 0, "deeproot_plan": 0}
	var summary := {}
	for name in ms:
		var t0 := Time.get_ticks_msec()
		var wins := 0
		var actions := 0
		for s in range(1, RUNTIME_SEEDS + 1):
			var r := Sweep.run_one(s, {}, name)
			wins += 1 if r["won"] else 0
			actions += int(r["actions"])
		ms[name] = Time.get_ticks_msec() - t0
		summary[name] = "wins %d/%d actions %d" % [wins, RUNTIME_SEEDS, actions]
	var factor := float(ms["deeproot_plan"]) / maxf(1.0, float(ms["deeproot"]))
	print("runtime: deeproot %d ms (%s), deeproot_plan %d ms (%s), factor %.2fx over %d seeds" % [
		ms["deeproot"], summary["deeproot"], ms["deeproot_plan"], summary["deeproot_plan"], factor, RUNTIME_SEEDS])
	_ok(factor < RUNTIME_MAX_FACTOR, "runtime factor %.2f < %.1f" % [factor, RUNTIME_MAX_FACTOR])
