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
##   3d) shrine reroll gates (Block D2): the optimizer spins only a counter
##      that fits its kit nothing and only with a graft's worth of bloom left
##      over; the magpie spins whenever the counter sells it nothing; the
##      tally counts the spin, its price and the buy that follows
##   3c) Block D1 surge terms: optimizer._est_dmg adds a row's surge dmg while
##      the tender stands on growth (and the sim lands exactly that number),
##      and the planner's surge-ready term follows the sim's rule - any held
##      row whose surge dict applies, cost-1 stat surges included
##   3e) Block D3 denial columns: a screened intent counts by intent type and
##      reaches kpis()/merge(), and the enemy fire damage the same line prints
##      is the source split that was already there
##   3f) Block D4 draft slots: a real draft's offers and the pick count by
##      the slot role the sim reports, a skip's focus draft counts, and both
##      halves survive merge() into kpis()
##   3g) Block D6 variant ids ("<base>+<variant>"): the suffix hazard - every
##      consumer that used to test ends_with("+") or trim_suffix("+") on an
##      ability id. The two personas' draft preference, the kit-slot fold every
##      trigger matches on, deeproot's row fallback, the tally's per-variant
##      split, and the profile's won_with fold plus its pre-D6 id migration
##   3h) Block D5 resonances, consumer side: the optimizer's draft DROP guard
##      (a drop that would put a lit element out is taken last), the planner's
##      flat per-active-resonance term, and the tally's split hook columns plus
##      its four exposure columns through merge() and kpis()
##   4) determinism: two fresh instances agree over 40 steps
##   5) runtime factor: deeproot vs deeproot_plan over 5 seeds (test-side
##      Time.get_ticks_msec only; the bots never read a clock)
## Run: godot --headless --path . --script tests/test_bots.gd

const Content := preload("res://sim/content.gd")
const Game := preload("res://sim/game.gd")
const Roster := preload("res://bots/roster.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const Tally := preload("res://tests/tally.gd")
const Profile := preload("res://meta/profile.gd")

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
	_check_reroll_gates()
	_check_d1_surge_terms()
	_check_d3_denial_tally()
	_check_d4_draft_tally()
	_check_d6_variants()
	_check_d5_resonances()
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


## One action through the sim with a tally listening, exactly as
## Sweep.run_loop feeds it.
static func _step_into(tally, game, a: Dictionary) -> void:
	tally.begin_step(game)
	for ev in game.step(a):
		tally.add(ev, a, game)
	tally.end_step(game, a)


## Every legal buy on the board, in the sim's own order.
static func _buys(game) -> Array:
	var out: Array = []
	for a in game.legal_actions():
		if String(a.get("type", "")) == "buy":
			out.append(a)
	return out


static func _has_action(game, t: String) -> bool:
	for a in game.legal_actions():
		if String(a.get("type", "")) == t:
			return true
	return false


## The cheapest price any Content.GRAFTS row carries, read test-side so the
## bot helper is checked against the table and not against itself.
static func _table_cheapest_graft() -> int:
	var best := 1 << 30
	for gid in Content.GRAFTS:
		best = mini(best, int(Content.GRAFTS[gid].get("price", 1)))
	return best


## A board with the tender already standing on the shrine, a graft-only
## counter (so no heal / ability / item branch can answer first) and `spins`
## rerolls already taken this floor.
static func _shrine_game(kit: Array, grafts: Array, purse: int, spins: int) -> RefCounted:
	var g = _game(kit)
	g.mutators = ["spinning_shrine"]  # the reroll is a mutator switch (read live by _mut)
	g.map["shrine"] = g.player["pos"]
	g.map["stairs"] = Vector2i(1, 1)
	g.shop = {"grafts": grafts.duplicate(), "rerolls": spins}
	g.bloom = purse
	return g


## Player distance to `goal` after stepping `a` on a clone.
static func _shrine_dist_after(game, a: Dictionary, goal: Vector2i) -> int:
	var c = game.clone()
	c.step(a)
	return _manhattan(c.player["pos"], goal)


# --- 1) seed on head ----------------------------------------------------------

func _check_seed_on_head() -> void:
	var kit := ["solar_lance", "seed_bomb", "mycelium_dash", "grow_spike+impale"]
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
	_ok(_kit_id(g, fu) == "grow_spike+impale", "the plan's follow-up is grow_spike+impale: %s" % str(fu))
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
	_ok(_kit_id(g, b) == "grow_spike+impale" and b.get("target", null) == e["pos"],
		"next choice is grow_spike+ on the enemy: %s" % str(b))
	var evs: Array = g.step(b)
	var killed := false
	for ev in evs:
		if String(ev.get("t", "")) == "death" or String(ev.get("t", "")) == "kill":
			killed = true
	_ok(not g.enemies.has(e) or killed, "the spike kills the drill bot: enemies %s events %s" % [str(g.enemies), str(evs)])


# --- 2) pin -------------------------------------------------------------------

func _check_pin() -> void:
	var kit := ["water_jet+pin", "solar_lance", "mycelium_dash"]
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
	_ok(_kit_id(g, a) == "water_jet+pin" and a.get("target", null) == Vector2i(1, 0), "plan jets the hulk into the wall: %s" % str(a))
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
	# post-D2 stock shape: the reroll counter rides in the stock dict
	g.shop = {"heal": true, "press": true, "forge": true, "grafts": ["thick_bark", "solar_core"], "ability": "vine_whip", "item": "balm_fruit", "rerolls": 0}
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
	g4.shop = {"grafts": ["solar_core"], "rerolls": 0}
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
	g5.shop = {"grafts": ["verdant_pulse", "solar_core"], "rerolls": 0}
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
			g.shop = {"grafts": ["compost", "solar_core"], "rerolls": 0}
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
		gn.shop = {"press": true, "rerolls": 0}
		gn.bloom = 20
		var botn = Roster.make(pname, 1)
		_ok(not botn._graft_worth_detour(gn.snapshot()),
			"%s: no grafts on the counter, no graft detour at 20 bloom" % pname)
		print("detour gate %-9s bloom 5 -> %s, bloom 6 -> %s" % [pname, str(seen[5]), str(seen[6])])


# --- 3d) Block D2 shrine reroll gates -----------------------------------------

## The bot half of the shrine reroll. Kit sun/fire/growth/mobility, so
## Thick Bark and Carapace (bark) score 0 on the tag fit and Solar Core (sun)
## scores 1 - the optimizer spins a counter it wants nothing from and only
## while the purse still covers the cheapest graft the table can offer after
## paying; the magpie spins whenever the counter sells it nothing at all.
## Prices and spins left are read from snapshot().shop, never from the sim.
func _check_reroll_gates() -> void:
	var kit := ["solar_lance", "seed_bomb", "mycelium_dash"]
	var opt = Roster.make("optimizer", 1)
	var mag = Roster.make("magpie", 1)
	var cheap := _table_cheapest_graft()
	_ok(opt._cheapest_graft_price() == cheap,
		"the bot reads the table's cheapest graft price: %d vs %d" % [opt._cheapest_graft_price(), cheap])
	var tags: Dictionary = opt._kit_tag_counts({"player": {"kit": kit}})
	_ok(opt._graft_fit("thick_bark", tags) == 0 and opt._graft_fit("carapace", tags) == 0,
		"bark grafts fit a sun/fire/growth kit not at all: %s" % str(tags))
	_ok(opt._graft_fit("solar_core", tags) > 0, "Solar Core fits the sun half of the kit")

	# a) misfit counter, purse exactly reroll price + cheapest graft: spin
	var ga = _shrine_game(kit, ["thick_bark", "carapace"], 2 + cheap, 0)
	var snap_a: Dictionary = ga.snapshot()
	_ok(int(snap_a["shop"]["reroll_price"]) == 2 and int(snap_a["shop"]["rerolls_left"]) == Content.SHOP_REROLL_CAP,
		"a fresh counter prices the spin at 2 with %d spins left: %s" % [Content.SHOP_REROLL_CAP, str(snap_a["shop"])])
	_ok(not _buys(ga).is_empty(), "both misfit offers are affordable at %d bloom" % ga.bloom)
	var a_a: Dictionary = opt.choose_action(snap_a, ga.legal_actions())
	_ok(String(a_a.get("type", "")) == "reroll",
		"optimizer spins a counter that fits nothing rather than buying it: %s" % str(a_a))
	# and the escalation bites: 3 bloom left cannot cover a 3-bloom spin plus a graft
	ga.step(a_a)
	var snap_a2: Dictionary = ga.snapshot()
	_ok(ga.bloom == cheap and int(ga.shop["rerolls"]) == 1,
		"the spin cost 2 and stored the count: bloom %d rerolls %s" % [ga.bloom, str(ga.shop.get("rerolls"))])
	_ok(int(snap_a2["shop"]["reroll_price"]) == 3 and int(snap_a2["shop"]["rerolls_left"]) == Content.SHOP_REROLL_CAP - 1,
		"the second spin is dearer with one fewer left: %s" % str(snap_a2["shop"]))
	_ok(String(opt.choose_action(snap_a2, ga.legal_actions()).get("type", "")) != "reroll",
		"the purse that is left never buys a second spin")

	# b) a fitting affordable offer is bought, never spun away
	var gb = _shrine_game(kit, ["thick_bark", "solar_core"], 12, 0)
	var snap_b: Dictionary = gb.snapshot()
	_ok(not opt._wants_reroll(snap_b, _buys(gb)), "a fitting affordable graft cancels the spin")
	var a_b: Dictionary = opt.choose_action(snap_b, gb.legal_actions())
	_ok(String(a_b.get("type", "")) == "buy" and String(a_b.get("item", "")) == "graft" and int(a_b.get("pick", -1)) == 1,
		"optimizer buys the fitting offer instead: %s" % str(a_b))

	# c) spins spent: the sim stops offering it and the bot stops asking
	var gc = _shrine_game(kit, ["thick_bark", "carapace"], 12, Content.SHOP_REROLL_CAP)
	var snap_c: Dictionary = gc.snapshot()
	_ok(int(snap_c["shop"]["rerolls_left"]) == 0, "the cap shows as 0 spins left: %s" % str(snap_c["shop"]))
	_ok(not _has_action(gc, "reroll"), "the sim refuses the spin at the cap")
	_ok(not opt._wants_reroll(snap_c, _buys(gc)), "the bot does not ask for a spin it cannot have")
	_ok(String(opt.choose_action(snap_c, gc.legal_actions()).get("type", "")) == "buy",
		"with the counter spun out it takes the misfit rather than stalling")

	# d) the reserve: a spin it can pay for but which would leave no graft purse
	var gd = _shrine_game(kit, ["thick_bark", "carapace"], 2 + cheap - 1, 0)
	_ok(_has_action(gd, "reroll"), "the sim offers the spin at %d bloom" % gd.bloom)
	_ok(not opt._wants_reroll(gd.snapshot(), _buys(gd)),
		"the optimizer never spends its last graft purse on a spin")
	_ok(String(opt.choose_action(gd.snapshot(), gd.legal_actions()).get("type", "")) == "buy",
		"it buys what it can instead")

	# e) unaffordable counter: magpie greed spins, the optimizer holds
	var ge = _shrine_game(kit, ["solar_core"], 3, 0)
	var snap_e: Dictionary = ge.snapshot()
	_ok(snap_e["shop"]["graft_prices"] == [8] and _buys(ge).is_empty(),
		"nothing on the counter is affordable at 3 bloom: %s" % str(snap_e["shop"]))
	_ok(String(mag.choose_action(snap_e, ge.legal_actions()).get("type", "")) == "reroll",
		"magpie spins its last bloom on a counter it cannot buy from")
	_ok(String(opt.choose_action(snap_e, ge.legal_actions()).get("type", "")) != "reroll",
		"the optimizer keeps a graft's worth back on the same board")

	# f) magpie buys before it spins
	var gf = _shrine_game(kit, ["thick_bark", "carapace"], 2 + cheap, 0)
	var a_f: Dictionary = mag.choose_action(gf.snapshot(), gf.legal_actions())
	_ok(String(a_f.get("type", "")) == "buy" and String(a_f.get("item", "")) == "graft",
		"magpie takes the affordable misfit before it spins: %s" % str(a_f))

	# g) the tally half: the spin, its price, and the buy off a spun counter
	var gg = _shrine_game(kit, ["thick_bark", "carapace"], 12, 0)
	var tal = Tally.new()
	_step_into(tal, gg, {"type": "reroll"})
	_ok(tal.rerolls == 1 and tal.bloom_spent_on_rerolls == 2 and tal.buys_after_reroll == 0,
		"tally counts the spin and its price: %d / %d" % [tal.rerolls, tal.bloom_spent_on_rerolls])
	var buys_g := _buys(gg)
	_ok(not buys_g.is_empty(), "the spun counter still sells something")
	_step_into(tal, gg, buys_g[0])
	_ok(tal.buys_after_reroll == 1 and int(tal.buys_by_kind.get("graft", 0)) == 1,
		"a buy off a spun counter is counted: %d" % tal.buys_after_reroll)
	tal.finish(gg)
	_ok(tal.bloom_unspent == gg.bloom, "unspent bloom at the end: %d vs %d" % [tal.bloom_unspent, gg.bloom])
	var tal2 = Tally.new()
	tal2.merge(tal)
	_ok(tal2.rerolls == 1 and tal2.bloom_spent_on_rerolls == 2 and tal2.buys_after_reroll == 1
			and tal2.bloom_unspent == gg.bloom, "merge carries every reroll column")
	var kg: Dictionary = Tally.kpis(tal2, 1, [])
	_ok(int(kg.get("rerolls", -1)) == 1 and int(kg.get("bloom_spent_on_rerolls", -1)) == 2
			and int(kg.get("buys_after_reroll", -1)) == 1 and int(kg.get("bloom_unspent", -1)) == gg.bloom,
		"kpis exposes the reroll columns: %s" % str([kg.get("rerolls"), kg.get("bloom_spent_on_rerolls"),
			kg.get("buys_after_reroll"), kg.get("bloom_unspent")]))
	print("reroll gates: optimizer spins at %d bloom on a misfit counter (price 2, reserve %d), holds at %d; magpie spins at 3 with nothing affordable" % [
		2 + cheap, cheap, 2 + cheap - 1])


# --- 3c) Block D1 surge terms -------------------------------------------------

## The bot half of the D1 surge rule, both sides read from the Content row and
## never from an id:
##   optimizer._est_dmg adds the row's surge "dmg" while the tender stands on
##   growth (grow_spike 3 -> 4, the growth-adjacent rider still paying on top),
##   and adds nothing to a row whose surge carries no dmg;
##   deeproot_plan's surge-ready term fires for a held cost-1 ability with a
##   stat surge (grow_spike), which the old cost-2+ rule could not see, and
##   still fires for the cost-2 rows it always saw.
func _check_d1_surge_terms() -> void:
	var g = _game(["grow_spike", "solar_lance", "mycelium_dash"])
	var e = g._spawn("welded_hulk", Vector2i(8, 3))
	g._compute_intents()
	var opt = Roster.make("optimizer", 1)
	var ppos: Vector2i = g.player["pos"]
	var off: Dictionary = g.snapshot()
	_ok(opt._est_dmg("grow_spike", e["pos"], off) == 3,
		"off growth the spike estimates its base 3: %d" % opt._est_dmg("grow_spike", e["pos"], off))
	_ok(opt._est_dmg("solar_lance", e["pos"], off) == 2,
		"off growth the lance estimates 2: %d" % opt._est_dmg("solar_lance", e["pos"], off))
	# stand on growth: the spike's own surge {dmg: 1} lands on the base dmg
	g.terrain[ppos] = {"kind": "growth"}
	var on: Dictionary = g.snapshot()
	_ok(opt._est_dmg("grow_spike", e["pos"], on) == 4,
		"on growth the spike estimates 4: %d" % opt._est_dmg("grow_spike", e["pos"], on))
	_ok(opt._est_dmg("solar_lance", e["pos"], on) == 2,
		"a row without a dmg surge is unchanged on growth: %d" % opt._est_dmg("solar_lance", e["pos"], on))
	_ok(opt._surge_stat(Content.ABILITIES["grow_spike"], "dmg", on) == 1
			and opt._surge_stat(Content.ABILITIES["grow_spike"], "dmg", off) == 0,
		"the surge delta is read only while standing on growth")
	_ok(opt._surge_stat(Content.ABILITIES["water_jet"], "dmg", on) == 0
			and opt._surge_stat(Content.ABILITIES["water_jet"], "push", on) == 1,
		"a push surge is no damage surge: %s" % str(Content.ABILITIES["water_jet"]["surge"]))
	# growth beside the enemy too: surge and the growth_adjacent rider stack
	g.terrain[Vector2i(8, 2)] = {"kind": "growth"}
	var on2: Dictionary = g.snapshot()
	var est: int = opt._est_dmg("grow_spike", e["pos"], on2)
	_ok(est == 5, "surge + one growth-adjacent rider: 3 + 1 + 1 = %d" % est)
	var gp = _game(["grow_spike+impale", "solar_lance", "mycelium_dash"])
	gp._spawn("welded_hulk", Vector2i(8, 3))
	gp.terrain[gp.player["pos"]] = {"kind": "growth"}
	gp.terrain[Vector2i(8, 2)] = {"kind": "growth"}
	gp.terrain[Vector2i(8, 4)] = {"kind": "growth"}
	var estp: int = opt._est_dmg("grow_spike+impale", Vector2i(8, 3), gp.snapshot())
	_ok(estp == 6, "grow_spike+ on growth with two growth beside the target: 3 + 1 + 2 = %d" % estp)
	# the estimate is the sim's number: cast it for real
	var hp0: int = int(e["hp"])
	var evs: Array = g.step({"type": "ability", "slot": 0, "target": e["pos"]})
	var kinds: Array = []
	for ev in evs:
		kinds.append(String(ev.get("t", "")))
	_ok(hp0 - int(e["hp"]) == est, "the sim lands the estimate: hp %d -> %d (est %d)" % [hp0, int(e["hp"]), est])
	_ok(kinds.has("verdant") and kinds.has("surge"), "the surged cast consumes growth and reports it: %s" % str(kinds))
	print("est_dmg: grow_spike off growth %d, on growth %d, on growth beside growth %d (sim dealt %d); grow_spike+ %d" % [
		3, 4, est, hp0 - int(e["hp"]), estp])

	# the harness counts both halves: the stat surge per casting id, and the
	# tile a Spore Trail dash left behind
	var gt = _game(["mycelium_dash+trail", "grow_spike", "solar_lance"])
	var from: Vector2i = gt.player["pos"]
	gt.terrain[Vector2i(8, 3)] = {"kind": "growth"}
	var tally = Tally.new()
	_step_into(tally, gt, {"type": "ability", "slot": 0, "target": Vector2i(8, 3)})
	_ok(gt.player["pos"] == Vector2i(8, 3) and String(gt.terrain.get(from, {}).get("kind", "")) == "growth",
		"the dash plants the tile it left: %s -> %s, terrain %s" % [str(from), str(gt.player["pos"]), str(gt.terrain.get(from, {}))])
	_ok(int(tally.origin_plants_by_aid.get("mycelium_dash+trail", 0)) == 1,
		"tally counts the origin plant: %s" % str(tally.origin_plants_by_aid))
	gt.terrain[gt.player["pos"]] = {"kind": "growth"}
	gt.player["charge"] = 3
	gt._spawn("welded_hulk", Vector2i(8, 5))
	gt.terrain[Vector2i(8, 6)] = {"kind": "growth"}
	_step_into(tally, gt, {"type": "ability", "slot": 1, "target": Vector2i(8, 5)})
	_ok(int(tally.surges_by_aid.get("grow_spike", 0)) == 1 and tally.verdant == 1,
		"tally counts the stat surge and its verdant: %s verdant %d" % [str(tally.surges_by_aid), tally.verdant])
	var k: Dictionary = Tally.kpis(tally, 1, [])
	_ok(int(k["surges"]) == 1 and int(k["origin_plants"]) == 1,
		"kpis carry both counters: surges %d origin plants %d" % [int(k["surges"]), int(k["origin_plants"])])

	# planner: surge-ready for a cost-1 stat-surge row
	var gs = _game(["grow_spike", "sap_snare", "mycelium_dash"])
	gs.terrain[gs.player["pos"]] = {"kind": "growth"}
	var plan = _bot("deeproot_plan", gs)
	var terms: Dictionary = plan._option_terms(gs)
	_ok(float(terms["surge"]) == plan.SURGE_POINTS,
		"a cost-1 stat-surge row held on growth is surge-ready: %s" % str(terms))
	var gc = _game(["sap_snare", "bramble_coat", "mycelium_dash"])
	gc.terrain[gc.player["pos"]] = {"kind": "growth"}
	var planc = _bot("deeproot_plan", gc)
	_ok(float(planc._option_terms(gc)["surge"]) == 0.0,
		"cost-1 rows with only the default surge stay worth nothing: %s" % str(planc._option_terms(gc)))
	var g2 = _game(["spore_cloud", "sap_snare", "mycelium_dash"])
	g2.terrain[g2.player["pos"]] = {"kind": "growth"}
	var plan2 = _bot("deeproot_plan", g2)
	_ok(float(plan2._option_terms(g2)["surge"]) == plan2.SURGE_POINTS,
		"the cost-2 discount rows the old rule saw still count: %s" % str(plan2._option_terms(g2)))
	var g3 = _game(["grow_spike", "sap_snare", "mycelium_dash"])
	var plan3 = _bot("deeproot_plan", g3)
	_ok(float(plan3._option_terms(g3)["surge"]) == 0.0, "off growth nothing is surge-ready")
	_ok(plan._surge_applies(Content.ABILITIES["grow_spike"])
			and plan._surge_applies(Content.ABILITIES["water_jet"])
			and plan._surge_applies(Content.ABILITIES["sun_flare"])
			and plan._surge_applies(Content.ABILITIES["seed_bomb"]),
		"stat surges and cost-2 discounts both apply")
	_ok(not plan._surge_applies(Content.ABILITIES["sap_snare"])
			and not plan._surge_applies(Content.ABILITIES["mycelium_dash+trail"])
			and not plan._surge_applies({}),
		"a cost-1 row with the default surge (and an unknown row) applies nothing")
	var ready: Array = []
	for aid in Content.ABILITIES:
		if plan._surge_applies(Content.ABILITIES[aid]):
			ready.append(aid)
	print("surge-ready rows (%d of %d): %s" % [ready.size(), Content.ABILITIES.size(), str(ready)])


## Block D3 harness wiring (spec item 5): the two terrain-denial columns the
## runners print. A screened intent ({"t": "screened", id, intent}) counts by
## intent type, survives a merge and reaches kpis(); the fire half of the same
## line is the "fire:<igniter>" source split that was already there, not a new
## counter, so a kind with no avoid list walking into fire lands in both.
func _check_d3_denial_tally() -> void:
	var g = _game(["solar_lance", "seed_bomb", "mycelium_dash"])
	g.terrain[Vector2i(6, 3)] = {"kind": "smoke", "ttl": 9}
	g._spawn("tar_spitter", Vector2i(8, 3))
	g._compute_intents()
	var shown := String(g.snapshot()["enemies"][0]["intent"].get("type", ""))
	_ok(shown == "gum", "the spitter still telegraphs its gum before the screen: %s" % shown)
	var tally = Tally.new()
	_step_into(tally, g, {"type": "end_turn"})
	_ok(int(tally.screened_by_intent.get("gum", 0)) == 1 and tally.screened_by_intent.size() == 1,
		"tally counts the screened intent by type: %s" % str(tally.screened_by_intent))
	var k: Dictionary = Tally.kpis(tally, 1, [])
	_ok(int(k["screened"]) == 1 and int(k["screened_by_intent"].get("gum", 0)) == 1,
		"kpis carry the screened columns: %s" % str([k["screened"], k["screened_by_intent"]]))
	# a kind with no avoid list walks into fire and burns for it
	var g2 = _game(["solar_lance", "seed_bomb", "mycelium_dash"])
	g2._spawn("welded_hulk", Vector2i(7, 3))
	g2.terrain[Vector2i(6, 3)] = {"kind": "fire", "ttl": 9}
	g2._compute_intents()
	var t2 = Tally.new()
	_step_into(t2, g2, {"type": "end_turn"})
	var k2: Dictionary = Tally.kpis(t2, 1, [])
	_ok(int(k2["enemy_fire_dmg"]) > 0 and int(k2["enemy_fire_dmg"]) == int(t2.fire_dmg_by_by.get("env", 0))
			and int(k2["screened"]) == 0,
		"the hulk burns and the fire column reads the source split: %d / %s" % [
			int(k2["enemy_fire_dmg"]), str(t2.fire_dmg_by_by)])
	var m = Tally.new()
	m.merge(tally)
	m.merge(t2)
	var km: Dictionary = Tally.kpis(m, 2, [])
	_ok(int(km["screened"]) == 1 and int(km["enemy_fire_dmg"]) == int(k2["enemy_fire_dmg"]),
		"merge carries both denial columns: %s" % str([m.screened_by_intent, km["enemy_fire_dmg"]]))
	print("d3 denial columns: screened %s, enemy fire dmg %d (%s)" % [
		str(m.screened_by_intent), int(km["enemy_fire_dmg"]), str(m.fire_dmg_by_by)])


## Block D4 harness wiring (spec item 6): the draft-slot columns the runners
## print. Rolled on a real floor, not a hand-built board - the roles come off
## the sim's own draft_offer event ("slots"), so the tally never re-derives
## which slot an id belongs to. Checked: every offer counts under the role the
## event reports, the pick lands under the role of the offer it took, a skip's
## focus draft counts as one focused draft with one extra "focus" offer, and
## both halves reach kpis() and survive a merge.
func _check_d4_draft_tally() -> void:
	var t1 = Tally.new()
	var g = _to_first_draft(t1, 4, {})
	_ok(g.phase == "draft" and not g.draft_offers.is_empty(),
		"seed 4 reaches a draft: %s %s" % [g.phase, str(g.draft_offers)])
	var slots: Array = g.draft_slots.duplicate()
	_ok(slots.size() == g.draft_offers.size(), "one slot per offer: %s / %s" % [str(slots), str(g.draft_offers)])
	var want := {}
	for role in slots:
		want[String(role)] = int(want.get(String(role), 0)) + 1
	_ok(t1.offers_by_slot == want and t1.drafts == 1 and t1.focus_drafts == 0,
		"tally counts every offer under the role the event reports: %s (event %s)" % [
			str(t1.offers_by_slot), str(want)])
	var unknown_role := false
	for role in t1.offers_by_slot:
		if not Content.DRAFT_SLOT_REPORTS.has(role):
			unknown_role = true
	_ok(not unknown_role, "every counted role is a Content.DRAFT_SLOT_REPORTS entry: %s" % str(t1.offers_by_slot))
	# the pick is attributed to the slot that offered it
	var took: String = String(g.draft_offers[0])
	var took_role: String = String(slots[0])
	_step_into(t1, g, {"type": "draft", "pick": 0})
	_ok(int(t1.picks_by_slot.get(took_role, 0)) == 1 and Tally._sum(t1.picks_by_slot) == 1
			and int(t1.picks_by_id.get(took, 0)) == 1,
		"the pick counts under its own slot: %s took %s from %s" % [str(t1.picks_by_slot), took, took_role])
	var k1: Dictionary = Tally.kpis(t1, 1, [])
	_ok(k1["offers_by_slot"] == t1.offers_by_slot and k1["picks_by_slot"] == t1.picks_by_slot
			and int(k1["focus_drafts"]) == 0
			and is_equal_approx(float(k1["pick_rate_by_slot"][took_role]),
				1.0 / float(t1.offers_by_slot[took_role])),
		"kpis carry the slot columns and their pick rate: %s" % str(k1["pick_rate_by_slot"]))
	# the focus half: a skip arms one extra affinity offer on the next draft
	var t2 = Tally.new()
	var g2 = _to_first_draft(t2, 4, {})
	var n_offers: int = g2.draft_offers.size()
	_step_into(t2, g2, {"type": "draft", "pick": -1})
	_ok(t2.skips == 1 and t2.focus_drafts == 0, "the skip itself is not a focused draft: %d" % t2.focus_drafts)
	_descend_into(t2, g2)
	_ok(g2.draft_offers.size() == n_offers + 1 and String(g2.draft_slots[-1]) == "focus",
		"the next draft carries the focus offer: %s %s" % [str(g2.draft_offers), str(g2.draft_slots)])
	_ok(t2.focus_drafts == 1 and int(t2.offers_by_slot.get("focus", 0)) == 1
			and Tally._sum(t2.offers_by_slot) == n_offers * 2 + 1,
		"tally counts the focused draft and its extra offer: %s focus %d" % [
			str(t2.offers_by_slot), t2.focus_drafts])
	var m = Tally.new()
	m.merge(t1)
	m.merge(t2)
	var km: Dictionary = Tally.kpis(m, 2, [])
	_ok(int(km["focus_drafts"]) == 1
			and Tally._sum(km["offers_by_slot"]) == Tally._sum(t1.offers_by_slot) + Tally._sum(t2.offers_by_slot)
			and Tally._sum(km["picks_by_slot"]) == 1,
		"merge carries both slot columns: %s / %s" % [str(km["offers_by_slot"]), str(km["picks_by_slot"])])
	print("d4 draft slots: offers %s picks %s focus %d of %d drafts (order %s)" % [
		str(m.offers_by_slot), str(m.picks_by_slot), m.focus_drafts, m.drafts,
		str(Tally.slot_order(m.offers_by_slot))])


## A real run stepped straight to its first descent draft, every event fed to
## `tally` exactly as Sweep.run_loop feeds it. The quota and the position are
## set test-side (tests/test_meta.gd _first_draft_offers does the same) - the
## point is the draft, not the floor that precedes it.
func _to_first_draft(tally, seed_v: int, cfg: Dictionary) -> RefCounted:
	var g = Game.new(seed_v, cfg)
	_descend_into(tally, g)
	return g


func _descend_into(tally, game) -> void:
	game.player["pos"] = game.map["stairs"]
	game.greened = game.green_need
	_step_into(tally, game, {"type": "descend"})


# --- 4) determinism -----------------------------------------------------------

## Block D6: a variant id is "<base>+<variant>" and does NOT end in "+", so
## every consumer that folded ids with trim_suffix("+") or tested them with
## ends_with("+") changed meaning silently. These are the consumer-side pins.
func _check_d6_variants() -> void:
	var forked := ""
	for base in Content.DRAFT_POOL:
		if Content.variants_of(String(base)).size() == 2:
			forked = String(base)
			break
	_ok(forked != "", "the pool holds a forked base to test with: '%s'" % forked)
	var sibs: Array = Content.variants_of(forked)
	var a_id := String(sibs[0])
	var b_id := String(sibs[1])
	_ok(not a_id.ends_with("+") and Content.is_upgrade(a_id) and Content.base_id(a_id) == forked,
		"a variant id is an upgrade that does not end in '+': %s" % a_id)

	# (i) draft preference: both siblings rank one step above their base and
	# strictly above an unlisted id. trim_suffix would have left them unlisted.
	var opt = Roster.make("optimizer", 1)
	var spr = Roster.make("sprout", 1)
	for bot in [opt, spr]:
		var base_r: int = bot._pref_rank(forked)
		var unlisted: int = bot._pref_rank("no_such_ability")
		_ok(bot._pref_rank(a_id) == base_r - 1 and bot._pref_rank(b_id) == base_r - 1,
			"%s ranks both siblings one step above the base: %d/%d vs %d" % [
				bot.get_bot_name(), bot._pref_rank(a_id), bot._pref_rank(b_id), base_r])
		_ok(bot._pref_rank(a_id) < unlisted,
			"%s ranks a variant above an unlisted id: %d < %d" % [
				bot.get_bot_name(), bot._pref_rank(a_id), unlisted])

	# (ii) the kit-slot fold: a variant in a slot still reads as its base, so
	# every hand-tuned trigger keyed on a base name keeps firing. Both personas
	# resolve to bot_base._kit_id (the two subclass overrides are gone, the
	# base folds with Content.base_id), so this pins the base implementation.
	var gk = _game(["solar_lance+pierce", "seed_bomb+reclaim", "mycelium_dash"])
	var snap: Dictionary = gk.snapshot()
	_ok(opt._kit_id(snap, 0) == "solar_lance" and opt._kit_id(snap, 1) == "seed_bomb"
			and spr._kit_id(snap, 0) == "solar_lance",
		"a variant in a kit slot folds onto its base: %s / %s" % [
			opt._kit_id(snap, 0), opt._kit_id(snap, 1)])
	_ok(opt._kit_full_id(snap, 0) == "solar_lance+pierce",
		"...while the full id survives for the row reads: %s" % opt._kit_full_id(snap, 0))

	# (iii) deeproot's row fallback reads the VARIANT's own row, not the base's,
	# and falls back to the BASE row for an id ABILITIES does not carry.
	# A variant that left its base's "self" shape discriminates the two rows:
	# a "self" row scores 0 whatever the target, a tile-shaped one measures
	# from the target tile, so the same call must return different numbers.
	var dr = Roster.make("deeproot", 1)
	var moved := ""
	for vid in Content.ABILITIES:
		var v := String(vid)
		if not Content.is_upgrade(v) or Content.base_id(v) == v:
			continue
		var vt := String(Content.ABILITIES[v].get("target", ""))
		var bt := String(Content.ABILITIES[Content.base_id(v)].get("target", ""))
		if bt == "self" and vt != "self" and vt != "dir":
			moved = v
			break
	_ok(moved != "", "some variant left its base's 'self' shape: '%s'" % moved)
	var gd = _game(["solar_lance", "seed_bomb", "mycelium_dash"])
	gd._spawn("drill_bot", Vector2i(8, 3))
	var sd: Dictionary = gd.snapshot()
	var ppos: Vector2i = sd["player"]["pos"]
	var tgt := Vector2i(2, 3)  # six tiles from the enemy, so the shapes differ
	if moved != "":
		var dv: int = dr._target_enemy_dist(sd, ppos, moved, tgt)
		var db: int = dr._target_enemy_dist(sd, ppos, Content.base_id(moved), tgt)
		_ok(dv == 6 and db == 0,
			"deeproot reads the variant's own row: %s (%s) -> %d, base (self) -> %d" % [
				moved, String(Content.ABILITIES[moved]["target"]), dv, db])
	# an id ABILITIES does not carry falls back to its base row, never to {}
	# (the {} default would read target "tile" and measure from the tile)
	var ghost: int = dr._target_enemy_dist(sd, ppos, "solar_lance+ghost", Vector2i(1, 0))
	var real: int = dr._target_enemy_dist(sd, ppos, "solar_lance", Vector2i(1, 0))
	var as_tile: int = absi(1 - 8) + absi(0 - 3)
	_ok(ghost == real and ghost != as_tile,
		"an unknown variant id falls back to its base row: %d (base %d, raw tile %d)" % [
			ghost, real, as_tile])

	# (iv) the tally splits the siblings, and only the tally does: casts_by_base
	# still folds them, casts_by_id / effective_casts_by_id keep them apart.
	var gt = _game([a_id, b_id, "mycelium_dash"])
	gt._spawn("welded_hulk", Vector2i(8, 3))
	gt.player["charge"] = 9
	var tally = Tally.new()
	var cast_a := false
	var cast_b := false
	for slot in 2:
		for act in gt.legal_actions():
			if String(act.get("type", "")) == "ability" and int(act["slot"]) == slot:
				_step_into(tally, gt, act)
				if slot == 0:
					cast_a = true
				else:
					cast_b = true
				break
	_ok(cast_a and cast_b, "both siblings were cast on the fixture board")
	_ok(int(tally.casts_by_base.get(forked, 0)) == 2,
		"casts_by_base folds the fork onto one key: %s" % str(tally.casts_by_base))
	_ok(int(tally.casts_by_id.get(a_id, 0)) == 1 and int(tally.casts_by_id.get(b_id, 0)) == 1,
		"casts_by_id keeps the siblings apart: %s" % str(tally.casts_by_id))
	_ok(int(tally.plus_casts) == 2, "plus_casts counts a variant as an upgrade: %d" % tally.plus_casts)
	var eff: Dictionary = tally.effective_casts_by_id
	_ok(_sum_dict(eff) == int(gt.effective_uses.get(forked, 0)),
		"effective_casts_by_id totals the sim's own effective_uses: %s vs %s" % [
			str(eff), str(gt.effective_uses)])
	var kv: Dictionary = Tally.kpis(tally, 1, [])
	_ok(kv["casts_by_id"].has(a_id) and kv["effective_casts_by_id"] is Dictionary,
		"kpis carry the per-variant columns")
	var mv = Tally.new()
	mv.merge(tally)
	mv.merge(tally)
	_ok(int(mv.casts_by_id.get(a_id, 0)) == 2, "merge sums the per-variant columns: %s" % str(mv.casts_by_id))

	# (v) the profile: base_id already folds a variant onto its base for
	# won_with, and a career saved before the rename migrates instead of
	# silently losing the id it earned.
	_ok(Profile._holds([a_id, "mycelium_dash"], forked),
		"won_with '%s' is satisfied by holding %s" % [forked, a_id])
	_ok(not Profile._holds([b_id, "mycelium_dash"], a_id),
		"...and a won_with naming one sibling is not satisfied by the other")
	var legacy_ids: Array = Profile._known_ability_ids([forked + "+", "mycelium_dash", "no_such_ability"])
	_ok(legacy_ids == [a_id, "mycelium_dash"],
		"a pre-D6 '%s+' in stored history migrates to the inherited variant: %s" % [forked, str(legacy_ids)])
	print("d6 variants: %s forks into %s; pref ranks %d/%d (base %d), casts_by_id %s" % [
		forked, str(sibs), opt._pref_rank(a_id), opt._pref_rank(b_id), opt._pref_rank(forked),
		str(tally.casts_by_id)])


## (3h) Block D5, the consumer half. The sim owns the threshold rule and the
## active set; what is tested here is what the three consumers do with it.
## Seated on cinder_grip (fire 3), the ONE row that ships - the design phase's
## displace row was cut on its own falsifier and the growth row on the greed
## canary. Fire has only two BASES, so every kit at the threshold here holds a
## sibling of one of them, which is what a forge or a locked kit produces.
func _check_d5_resonances() -> void:
	# (i) the optimizer's draft drop guard. A five-slot kit at fire 3 has
	# Cinder Grip lit; the offer is off-element, so the pick must drop
	# something - and three of the four unprotected slots are what light the
	# element. With every use count at 0 the OLD rule took the first
	# unprotected slot, which is the lance.
	var kit := ["solar_lance", "solar_lance+noon", "sun_flare", "moss_filter", "mycelium_dash"]
	var g = _game(kit)
	_ok(g.snapshot()["resonances"] == ["cinder_grip"],
		"the fire-3 kit lights exactly Cinder Grip: %s" % str(g.snapshot()["resonances"]))
	g.phase = "draft"
	g.draft_offers = ["overgrowth"]
	g.draft_slots = ["wild"]
	var opt = Roster.make("optimizer", 1)
	var dsnap: Dictionary = g.snapshot()
	_ok(opt._tag_counts(dsnap).get("fire", 0) == 3,
		"the persona counts the kit's three fire cards: %s" % str(opt._tag_counts(dsnap)))
	_ok(opt._drop_breaks_resonance(dsnap, 0, 0) and opt._drop_breaks_resonance(dsnap, 1, 0)
			and opt._drop_breaks_resonance(dsnap, 2, 0),
		"dropping any of the three fire cards for an off-element offer breaks the row")
	_ok(not opt._drop_breaks_resonance(dsnap, 3, 0),
		"dropping the off-element moss filter does not")
	var pick: Dictionary = opt.choose_action(dsnap, g.legal_actions())
	_ok(int(pick.get("pick", -9)) == 0 and int(pick.get("drop", -9)) == 3,
		"the optimizer drops the moss filter, not a fire card, to keep Cinder Grip: %s" % str(pick))

	# ...and with the kit's grafts counted too: ember_sap is fire, so the same
	# board with the graft held survives dropping ONE of the three cards.
	var gg = Game.new(1, {"fixed_floor": {"gen": _gen(ROOM), "fdef": {}}, "kit": kit,
			"grafts": ["ember_sap"]})
	gg.phase = "draft"
	gg.draft_offers = ["overgrowth"]
	gg.draft_slots = ["wild"]
	var gsnap: Dictionary = gg.snapshot()
	_ok(opt._tag_counts(gsnap).get("fire", 0) == 4,
		"the held graft's tag is counted with the kit's: %s" % str(opt._tag_counts(gsnap)))
	_ok(not opt._drop_breaks_resonance(gsnap, 0, 0),
		"with the graft held, dropping one fire card no longer breaks the row")
	var pick2: Dictionary = opt.choose_action(gsnap, gg.legal_actions())
	_ok(int(pick2.get("drop", -9)) == 0,
		"...so the persona goes back to its plain least-used drop: %s" % str(pick2))

	# (ii) the fallback: when EVERY legal drop breaks the row the guard must not
	# leave the pick unmade. A kit whose three unprotected slots are the three
	# fire cards that light cinder_grip has no non-breaking drop. (A locked-kit
	# config may hold both siblings of one base; the tag counts twice, which is
	# what makes an exactly-at-need kit constructible here.)
	var g3 = _game(["solar_lance", "sun_flare", "solar_lance+noon", "seed_bomb", "mycelium_dash"])
	g3.phase = "draft"
	g3.draft_offers = ["overgrowth"]
	g3.draft_slots = ["wild"]
	var s3: Dictionary = g3.snapshot()
	_ok(s3["resonances"] == ["cinder_grip"], "the fire-3 kit lights cinder_grip: %s" % str(s3["resonances"]))
	_ok(opt._drop_breaks_resonance(s3, 0, 0) and opt._drop_breaks_resonance(s3, 1, 0)
			and opt._drop_breaks_resonance(s3, 2, 0),
		"every unprotected drop breaks the row")
	var pick3: Dictionary = opt.choose_action(s3, g3.legal_actions())
	_ok(int(pick3.get("pick", -9)) == 0 and int(pick3.get("drop", -9)) >= 0,
		"a pick is still made when every drop breaks a row: %s" % str(pick3))

	# (iii) the planner's term is flat per ACTIVE resonance and reads the sim,
	# so a board that lights nothing scores exactly RESONANCE_POINTS lower per
	# row than the same board that lights one.
	var plan = Roster.make("deeproot_plan", 1)
	var lit = _game(["solar_lance", "solar_lance+noon", "sun_flare"])
	var dark = _game(["solar_lance", "seed_bomb", "mycelium_dash"])
	_ok(plan._resonance_value(lit) == plan.RESONANCE_POINTS
			and plan._resonance_value(dark) == 0.0,
		"deeproot_plan values one lit resonance at %.0f and none at 0 (%.0f / %.0f)" % [
			plan.RESONANCE_POINTS, plan._resonance_value(lit), plan._resonance_value(dark)])

	# (iv) the tally: a resonance hook must NOT land in the graft column, and
	# the four exposure columns must survive merge() into kpis().
	var t = Tally.new()
	var rid := String(Content.RESONANCES.keys()[0])
	t.add({"t": "hook", "id": rid, "on": "ignite"}, {}, lit)
	t.add({"t": "hook", "id": "ember_sap", "on": "ignite"}, {}, lit)
	_ok(t.hooks_by_resonance.get(rid, 0) == 1 and not t.hooks_by_graft.has(rid)
			and t.hooks_by_graft.get("ember_sap", 0) == 1,
		"the hook column splits by source: graft %s / resonance %s" % [
			str(t.hooks_by_graft), str(t.hooks_by_resonance)])
	_ok(int(t.hooks_by_kind.get("ignite", 0)) == 2,
		"...while hooks_by_kind still counts both")
	# exposure: one step on the lit board, then a run finished
	t.begin_step(lit)
	t.end_step(lit, {"type": "end_turn"})
	t.finish(lit)
	_ok(int(t.resonance_runs.get(rid, 0)) == 1
			and int(t.resonance_first_floor.get(rid, 0)) == lit.floor_num
			and int(t.resonance_turns.get(rid, 0)) == 1,
		"the tally records the run, its first floor and its turns: %s / %s / %s" % [
			str(t.resonance_runs), str(t.resonance_first_floor), str(t.resonance_turns)])
	# a drop that breaks the row counts as a break, not as a second run
	var t2 = Tally.new()
	t2.begin_step(lit)
	t2.end_step(lit, {"type": "end_turn"})
	t2.begin_step(dark)
	t2.end_step(dark, {"type": "end_turn"})
	t2.finish(dark)
	_ok(int(t2.resonance_breaks.get(rid, 0)) == 1
			and int(t2.resonance_runs.get(rid, 0)) == 1,
		"a row that goes out counts one break and still one run: %s / %s" % [
			str(t2.resonance_breaks), str(t2.resonance_runs)])
	t.merge(t2)
	var k := Tally.kpis(t, 2, [])
	_ok(int((k["resonance_runs"] as Dictionary).get(rid, 0)) == 2
			and int((k["hooks_by_resonance"] as Dictionary).get(rid, 0)) == 1
			and int((k["resonance_breaks"] as Dictionary).get(rid, 0)) == 1,
		"merge and kpis carry the resonance columns: %s" % str(k["resonance_runs"]))
	# the report line names every row: the reached one with its numbers, and -
	# on a tally that never met it - the same row at 0, which is how a row
	# nobody reaches stays visible in a sweep
	_ok(t.resonance_line(2).begins_with("resonance: ")
			and t.resonance_line(2).contains("%s 2/2" % rid)
			and Tally.new().resonance_line(2).contains("%s 0/2" % rid),
		"the report line names every row, reached or not: %s | %s" % [
			t.resonance_line(2), Tally.new().resonance_line(2)])
	print("d5 resonances: lit %s; optimizer keeps it (drop %d) and drops %d without it; planner %.0f/row; %s" % [
		str(lit.snapshot()["resonances"]), int(pick["drop"]), int(pick2["drop"]),
		plan.RESONANCE_POINTS, t.resonance_line(2)])


static func _sum_dict(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n


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
