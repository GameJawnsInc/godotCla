extends SceneTree
## Economy / shrine / quota checks for sim bump 2 (docs/PROGRESSION_REVIEW.md §6.2):
##  a) main-rng independence: rng.state after Game.new is the same for any
##     kit / grafts / pool / bloom / packages config on the same seed
##  b) shop stock filter: no base of an owned "+" ability, base item ids only,
##     two distinct unowned grafts (one when one remains, none when all owned)
##  c) supply pods hand out base item ids only
##  d) two-graft stock: buying one discards the other
##  e) full-kit ability purchase replaces a slot, never the mobility slot
##  f) press/forge: shop-gated, tier markup, forge once per floor, never
##     scraps mobility; Boarded shrines board every purchase and service
##  g) quota re-clamp after bloomless corruption removal; enemy oil pays 0
##  h) config keys "grafts" and "bloom"
##  i) damage attribution: fire tiles carry "by", enemy-side sources are
##     "fire:<by>" / "collision:<aid>", player-side sources unchanged
## Run: godot --headless --path . --script tests/test_economy.gd

const Content := preload("res://sim/content.gd")
const Game := preload("res://sim/game.gd")
const Roster := preload("res://bots/roster.gd")
const Sweep := preload("res://tests/sweep_lib.gd")

const RNG_SEEDS := 50
const STOCK_SEEDS := 200
const POD_TARGET := 30
const GOUGING_TIER := 5  # Content.TIERS[4] is "Gouging Prices"

var checks := 0
var failures: Array = []


func _init() -> void:
	_check_rng_independence()
	_check_stock_filter()
	_check_pods_and_shops_in_play()
	_check_graft_buy()
	_check_ability_buy_with_drop()
	_check_press_forge_boarded()
	_check_quota_reclamp()
	_check_config_keys()
	_check_attribution()
	if failures.is_empty():
		print("economy: OK (%d checks)" % checks)
		quit(0)
	else:
		for f in failures:
			print("FAIL: %s" % f)
		print("economy: %d failure(s) in %d checks" % [failures.size(), checks])
		quit(1)


func _ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append(msg)


# --- fixture helpers --------------------------------------------------------

## ASCII rows -> a fixed_floor "gen" dict. # wall . floor @ start > stairs
## + shrine ~ oil ; goo, lowercase letters spawn enemies: d drill_bot,
## m cinder_mite.
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
			var p := Vector2i(x, y)
			tiles[y * w + x] = 0 if ch == "#" else 1
			match ch:
				"@":
					gen["start"] = p
				">":
					gen["stairs"] = p
				"+":
					gen["shrine"] = p
				"~":
					gen["terrain"][p] = {"kind": "oil"}
				";":
					gen["terrain"][p] = {"kind": "goo"}
				"d":
					gen["enemies"].append({"kind": "drill_bot", "pos": p})
				"m":
					gen["enemies"].append({"kind": "cinder_mite", "pos": p})
	return gen


static func _fixed(rows: Array, kit: Array, extra: Dictionary = {}) -> Dictionary:
	var cfg := {"fixed_floor": {"gen": _gen(rows), "fdef": extra.get("fdef", {})}, "kit": kit}
	for k in extra:
		if k != "fdef":
			cfg[k] = extra[k]
	return cfg


static func _events_of(events: Array, t: String) -> Array:
	var out: Array = []
	for ev in events:
		if String(ev.get("t", "")) == t:
			out.append(ev)
	return out


static func _has_action(acts: Array, type: String, keys: Dictionary = {}) -> bool:
	for a in acts:
		if String(a.get("type", "")) != type:
			continue
		var match_all := true
		for k in keys:
			if not a.has(k) or a[k] != keys[k]:
				match_all = false
		if match_all:
			return true
	return false


# --- a) rng independence ------------------------------------------------------

func _check_rng_independence() -> void:
	var variants: Array = [
		{"kit": ["solar_lance+", "seed_bomb", "mycelium_dash", "vine_whip", "water_jet"]},
		{"grafts": Content.GRAFTS.keys()},
		{"pool": ["solar_lance", "seed_bomb", "vine_whip"]},
		{"bloom": 9},
		{"packages": Content.PACKAGES.keys()},
	]
	var mismatches := 0
	for s in range(1, RNG_SEEDS + 1):
		var base_state: int = Game.new(s).rng.state
		for v in variants:
			if Game.new(s, v).rng.state != base_state:
				mismatches += 1
				if mismatches <= 3:
					failures.append("rng: seed %d config %s shifted the main rng" % [s, str(v)])
	_ok(mismatches == 0, "rng independence: %d mismatches over %d seeds x %d variants" % [mismatches, RNG_SEEDS, variants.size()])
	print("rng independence: %d seeds x %d configs, %d mismatches" % [RNG_SEEDS, variants.size(), mismatches])


# --- b) stock filter ----------------------------------------------------------

func _check_stock_filter() -> void:
	var kit := ["solar_lance+", "seed_bomb", "mycelium_dash"]
	var five: Array = Content.GRAFTS.keys().slice(0, 5)
	var sixth: String = Content.GRAFTS.keys()[5]
	var bad_ability := 0
	var bad_item := 0
	var bad_grafts := 0
	var bad_keys := 0
	var allowed := {"heal": true, "press": true, "forge": true, "ability": true, "grafts": true, "item": true}
	for s in range(1, STOCK_SEEDS + 1):
		var g = Game.new(s, {"kit": kit})
		var shop: Dictionary = g.shop
		for k in shop:
			if not allowed.has(k):
				bad_keys += 1
		if not shop.has("ability") or shop["ability"] == "solar_lance" or kit.has(shop["ability"]):
			bad_ability += 1
		if not shop.has("item") or String(shop["item"]).ends_with("+"):
			bad_item += 1
		var gr: Array = shop.get("grafts", [])
		if gr.size() != 2 or gr[0] == gr[1] or not Content.GRAFTS.has(gr[0]) or not Content.GRAFTS.has(gr[1]):
			bad_grafts += 1
		var g5 = Game.new(s, {"grafts": five})
		var gr5: Array = g5.shop.get("grafts", [])
		if gr5 != [sixth]:
			bad_grafts += 1
		var g6 = Game.new(s, {"grafts": Content.GRAFTS.keys()})
		if g6.shop.has("grafts") or g6.shop.has("graft"):
			bad_grafts += 1
	_ok(bad_keys == 0, "stock: %d unexpected shop keys" % bad_keys)
	_ok(bad_ability == 0, "stock: %d shops offered an owned/owned-plus base ability" % bad_ability)
	_ok(bad_item == 0, "stock: %d shops offered a + item" % bad_item)
	_ok(bad_grafts == 0, "stock: %d graft offers wrong (2 distinct / 1 remaining / none)" % bad_grafts)
	# a floor without a shrine stocks nothing
	var g7 = Game.new(1)
	g7._enter_floor(Content.FLOORS.size())
	_ok(g7.map["shrine"] == Vector2i(-1, -1) and g7.shop.is_empty(), "boss floor shop is %s" % str(g7.shop))
	print("stock filter: %d seeds, ability/item/graft violations %d/%d/%d" % [STOCK_SEEDS, bad_ability, bad_item, bad_grafts])


# --- c) pods in play ----------------------------------------------------------

func _check_pods_and_shops_in_play() -> void:
	var seen := {}
	var plus_pods := 0
	var plus_shop_items := 0
	var owned_base_offers := 0
	var seed_v := 0
	while seen.size() < POD_TARGET and seed_v < 60:
		seed_v += 1
		var bot_name := "optimizer" if seed_v % 2 == 1 else "magpie"
		var game = Game.new(seed_v)
		var bot = Roster.make(bot_name, seed_v)
		if bot.has_method("set_sim"):
			bot.set_sim(game)
		var actions := 0
		var last_floor := 0
		while not game.over and actions < Sweep.MAX_ACTIONS and game.total_turns < Sweep.MAX_TURNS:
			game.step(bot.choose_action(game.snapshot(), game.legal_actions()))
			actions += 1
			if game.floor_num != last_floor:
				last_floor = game.floor_num
				if game.shop.has("item") and String(game.shop["item"]).ends_with("+"):
					plus_shop_items += 1
				if game.shop.has("ability"):
					var aid := String(game.shop["ability"])
					if game.player["kit"].has(aid) or game.player["kit"].has(aid + "+"):
						owned_base_offers += 1
			for t in game.terrain:
				if game.terrain[t]["kind"] == "supply":
					var key := "%d:%d:%s" % [seed_v, game.floor_num, str(t)]
					if not seen.has(key):
						seen[key] = game.terrain[t]["item"]
						if String(game.terrain[t]["item"]).ends_with("+"):
							plus_pods += 1
	_ok(seen.size() >= POD_TARGET, "pods: only %d supply tiles observed in %d runs" % [seen.size(), seed_v])
	_ok(plus_pods == 0, "pods: %d supply tiles carried a + item" % plus_pods)
	_ok(plus_shop_items == 0, "shops in play: %d + items stocked" % plus_shop_items)
	_ok(owned_base_offers == 0, "shops in play: %d offers of an owned ability (or owned-plus base)" % owned_base_offers)
	print("pods: %d supply tiles over %d bot runs, %d with + items; shops: %d + items, %d owned offers" % [
		seen.size(), seed_v, plus_pods, plus_shop_items, owned_base_offers])


# --- d) two-graft buy ---------------------------------------------------------

func _check_graft_buy() -> void:
	var g = Game.new(1, {"bloom": 20})
	g.player["pos"] = g.map["shrine"]
	var offers: Array = g.shop["grafts"].duplicate()
	_ok(offers.size() == 2, "graft buy: fresh shop offers %s" % str(offers))
	var acts: Array = g.legal_actions()
	_ok(_has_action(acts, "buy", {"item": "graft", "pick": 0}) and _has_action(acts, "buy", {"item": "graft", "pick": 1}),
		"graft buy: legal actions lack pick 0/1")
	_ok(not _has_action(acts, "buy", {"item": "graft", "pick": 2}), "graft buy: pick 2 offered")
	var bloom_before: int = g.bloom
	var evs: Array = g.step({"type": "buy", "item": "graft", "pick": 1})
	var buys := _events_of(evs, "buy")
	_ok(g.player["grafts"] == [offers[1]], "graft buy: grafts %s, expected [%s]" % [str(g.player["grafts"]), offers[1]])
	_ok(not g.shop.has("grafts") and not g.shop.has("graft"), "graft buy: shop still has grafts %s" % str(g.shop))
	_ok(buys.size() == 1 and buys[0].get("id", "") == offers[1] and buys[0].get("discarded", "") == offers[0],
		"graft buy: event %s" % str(buys))
	_ok(g.bloom == bloom_before - Content.SHOP_COSTS["graft"], "graft buy: bloom %d -> %d" % [bloom_before, g.bloom])
	# the old scalar form is gone: a pick-less buy is illegal
	var g2 = Game.new(1, {"bloom": 20})
	g2.player["pos"] = g2.map["shrine"]
	var evs2: Array = g2.step({"type": "buy", "item": "graft"})
	_ok(not _events_of(evs2, "illegal").is_empty() and g2.player["grafts"].is_empty(), "graft buy without pick was accepted")
	# price steps with owned grafts, pre-installed ones included
	var g3 = Game.new(1, {"grafts": ["carapace"]})
	_ok(g3.shop_cost("graft") == Content.SHOP_COSTS["graft"] + Content.GRAFT_PRICE_STEP,
		"graft price with one config graft: %d" % g3.shop_cost("graft"))
	print("graft buy: offers %s, bought %s, discarded %s" % [str(offers), offers[1], offers[0]])


# --- e) ability buy with drop -------------------------------------------------

func _check_ability_buy_with_drop() -> void:
	var kit := ["solar_lance", "seed_bomb", "mycelium_dash", "vine_whip", "water_jet"]
	var g = Game.new(1, {"bloom": 20, "kit": kit})
	g.player["pos"] = g.map["shrine"]
	g.player["gummed"] = {0: 2}
	_ok(g.shop.has("ability"), "ability buy: no ability stocked with kit %s" % str(kit))
	var aid: String = g.shop.get("ability", "")
	var acts: Array = g.legal_actions()
	var drops: Array = []
	var plain := 0
	for a in acts:
		if a.get("type", "") == "buy" and a.get("item", "") == "ability":
			if a.has("drop"):
				drops.append(a["drop"])
			else:
				plain += 1
	drops.sort()
	_ok(plain == 0, "ability buy: %d plain buy actions with a full kit" % plain)
	_ok(drops == [0, 1, 3, 4], "ability buy: drop slots %s, expected [0, 1, 3, 4] (2 is mycelium_dash)" % str(drops))
	# dropping the mobility slot is illegal even when requested directly
	var evs_bad: Array = g.step({"type": "buy", "item": "ability", "drop": 2})
	_ok(not _events_of(evs_bad, "illegal").is_empty() and g.player["kit"][2] == "mycelium_dash", "ability buy: mobility drop accepted")
	var evs: Array = g.step({"type": "buy", "item": "ability", "drop": 0})
	var buys := _events_of(evs, "buy")
	_ok(g.player["kit"][0] == aid and g.player["kit"].size() == 5, "ability buy: kit %s" % str(g.player["kit"]))
	_ok(not g.player["gummed"].has(0), "ability buy: gummed %s still holds slot 0" % str(g.player["gummed"]))
	_ok(buys.size() == 1 and buys[0].get("id", "") == aid and buys[0].get("dropped", "") == "solar_lance",
		"ability buy: event %s" % str(buys))
	_ok(not g.shop.has("ability"), "ability buy: shop still stocks ability")
	# kit not full: plain buy appends
	var g2 = Game.new(1, {"bloom": 20})
	g2.player["pos"] = g2.map["shrine"]
	var aid2: String = g2.shop.get("ability", "")
	_ok(_has_action(g2.legal_actions(), "buy", {"item": "ability"}), "ability buy: plain buy missing with 3-kit")
	g2.step({"type": "buy", "item": "ability"})
	_ok(g2.player["kit"].size() == 4 and g2.player["kit"][3] == aid2, "ability buy: 3-kit append -> %s" % str(g2.player["kit"]))
	print("ability buy: full kit drop slots %s, bought %s over solar_lance" % [str(drops), aid])


# --- f) press / forge / boarded ---------------------------------------------

func _check_press_forge_boarded() -> void:
	var kit := ["solar_lance", "seed_bomb", "mycelium_dash"]
	var g = Game.new(1, {"bloom": 20, "kit": kit})
	g.player["pos"] = g.map["shrine"]
	g.player["items"] = ["balm_fruit", "sun_capsule"]
	_ok(g.shop.get("press", false) and g.shop.get("forge", false), "shop lacks press/forge: %s" % str(g.shop))
	var acts: Array = g.legal_actions()
	var forges: Array = []
	for a in acts:
		if a.get("type", "") == "upcycle_ability":
			forges.append(a)
	_ok(not forges.is_empty(), "forge: no legal upcycle_ability")
	var scrap_mobility := 0
	for a in forges:
		if a["scrap"] == 2:
			scrap_mobility += 1
	_ok(scrap_mobility == 0, "forge: %d legal actions scrap the mobility slot" % scrap_mobility)
	_ok(_has_action(acts, "upcycle", {"keep": 0}) and _has_action(acts, "upcycle", {"keep": 1}), "press: legal actions missing")
	# direct request to scrap mobility is illegal
	var evs_bad: Array = g.step({"type": "upcycle_ability", "keep": 0, "scrap": 2})
	_ok(not _events_of(evs_bad, "illegal").is_empty() and g.player["kit"].size() == 3, "forge: scrapping mobility accepted")
	# forge once
	var bloom_before: int = g.bloom
	var evs: Array = g.step({"type": "upcycle_ability", "keep": 0, "scrap": 1})
	_ok(not _events_of(evs, "upcycle_ability").is_empty() and g.player["kit"] == ["solar_lance+", "mycelium_dash"],
		"forge: kit %s events %s" % [str(g.player["kit"]), str(evs)])
	_ok(g.bloom == bloom_before - Content.SHOP_COSTS["forge"], "forge: bloom %d -> %d" % [bloom_before, g.bloom])
	_ok(not g.shop.has("forge"), "forge: shop.forge survived a use")
	_ok(not _has_action(g.legal_actions(), "upcycle_ability"), "forge: second forge still legal")
	g.player["kit"] = ["seed_bomb", "mycelium_dash", "vine_whip"]
	var evs2: Array = g.step({"type": "upcycle_ability", "keep": 0, "scrap": 2})
	_ok(not _events_of(evs2, "illegal").is_empty(), "forge: second forge accepted")
	# press still works and is priced through shop_cost
	var bb2: int = g.bloom
	var evs3: Array = g.step({"type": "upcycle", "keep": 0})
	_ok(g.player["items"] == ["balm_fruit+"] and g.bloom == bb2 - Content.SHOP_COSTS["press"],
		"press: items %s bloom %d -> %d events %s" % [str(g.player["items"]), bb2, g.bloom, str(evs3)])
	# gouging prices markup
	var gt = Game.new(1, {"tier": GOUGING_TIER, "bloom": 20, "kit": kit})
	_ok(gt.shop_cost("press") == Content.SHOP_COSTS["press"] + 1 and gt.shop_cost("forge") == Content.SHOP_COSTS["forge"] + 1,
		"gouging: press %d forge %d" % [gt.shop_cost("press"), gt.shop_cost("forge")])
	gt.player["pos"] = gt.map["shrine"]
	gt.player["items"] = ["balm_fruit", "sun_capsule"]
	var bt: int = gt.bloom
	gt.step({"type": "upcycle", "keep": 1})
	_ok(gt.bloom == bt - Content.SHOP_COSTS["press"] - 1, "gouging: press charged %d" % (bt - gt.bloom))
	bt = gt.bloom
	gt.step({"type": "upcycle_ability", "keep": 0, "scrap": 1})
	_ok(gt.bloom == bt - Content.SHOP_COSTS["forge"] - 1, "gouging: forge charged %d" % (bt - gt.bloom))
	# boarded: nothing to buy, press or forge
	var gb = Game.new(1, {"mutators": ["boarded"], "bloom": 20, "kit": kit})
	gb.player["pos"] = gb.map["shrine"]
	gb.player["items"] = ["balm_fruit", "sun_capsule"]
	gb.player["hp"] = 5
	var offered := 0
	for a in gb.legal_actions():
		var t := String(a.get("type", ""))
		if t == "buy" or t == "upcycle" or t == "upcycle_ability":
			offered += 1
	_ok(gb.shop.is_empty() and offered == 0, "boarded: shop %s, %d shrine actions legal" % [str(gb.shop), offered])
	var evb: Array = gb.step({"type": "upcycle", "keep": 0})
	_ok(not _events_of(evb, "illegal").is_empty() and gb.player["items"].size() == 2, "boarded: press accepted")
	var evb2: Array = gb.step({"type": "upcycle_ability", "keep": 0, "scrap": 1})
	_ok(not _events_of(evb2, "illegal").is_empty() and gb.player["kit"].size() == 3, "boarded: forge accepted")
	print("press/forge: forge once (%d bloom), press %d bloom, gouging +1 each, boarded shrine offers %d actions" % [
		Content.SHOP_COSTS["forge"], Content.SHOP_COSTS["press"], offered])


# --- g) quota re-clamp ------------------------------------------------------

func _check_quota_reclamp() -> void:
	var rows := [
		"#########",
		"#@~~.>..#",
		"#########",
	]
	# wash: water_jet range 2 erases both oil tiles bloomlessly
	var g = Game.new(1, _fixed(rows, ["water_jet", "mycelium_dash"], {"fdef": {"green_need": 2}}))
	_ok(g.green_need == 2 and g.greened == 0, "wash setup: need %d greened %d" % [g.green_need, g.greened])
	_ok(not _has_action(g.legal_actions(), "descend"), "wash setup: descend legal before anything")
	var evs: Array = g.step({"type": "ability", "slot": 0, "target": Vector2i(1, 0)})
	_ok(_events_of(evs, "wash").size() == 2, "wash: %d wash events" % _events_of(evs, "wash").size())
	var rc := _events_of(evs, "quota_reclamp")
	_ok(rc.size() == 1 and int(rc[0].get("need", -1)) == 0 and int(rc[0].get("was", -1)) == 2, "wash: quota_reclamp %s" % str(rc))
	_ok(_events_of(evs, "stairs_awaken").size() == 1, "wash: stairs_awaken missing (%s)" % str(evs))
	_ok(g.green_need == 0, "wash: green_need %d" % g.green_need)
	g.player["pos"] = g.map["stairs"]
	_ok(_has_action(g.legal_actions(), "descend"), "wash: descend not legal on stairs")
	# ignite: the lance turns both oil tiles into fire, which is not corruption
	var gi = Game.new(1, _fixed(rows, ["solar_lance", "mycelium_dash"], {"fdef": {"green_need": 2}}))
	var evi: Array = gi.step({"type": "ability", "slot": 0, "target": Vector2i(1, 0)})
	_ok(_events_of(evi, "ignite").size() == 2, "ignite: %d ignite events" % _events_of(evi, "ignite").size())
	var rci := _events_of(evi, "quota_reclamp")
	_ok(rci.size() == 1 and int(rci[0].get("need", -1)) == 0 and gi.green_need == 0, "ignite: reclamp %s need %d" % [str(rci), gi.green_need])
	_ok(_events_of(evi, "stairs_awaken").size() == 1, "ignite: stairs_awaken missing")
	_ok(gi.terrain[Vector2i(2, 1)].get("by", "") == "solar_lance", "ignite: fire by %s" % str(gi.terrain.get(Vector2i(2, 1))))
	# partial: one of three oil tiles washed -> need drops from 3 to 2, stairs stay dormant
	var rows3 := [
		"#########",
		"#@~..~~>#",
		"#########",
	]
	var gp = Game.new(1, _fixed(rows3, ["water_jet", "mycelium_dash"], {"fdef": {"green_need": 3}}))
	var evp: Array = gp.step({"type": "ability", "slot": 0, "target": Vector2i(1, 0)})
	var rcp := _events_of(evp, "quota_reclamp")
	_ok(rcp.size() == 1 and int(rcp[0]["need"]) == 2 and int(rcp[0]["was"]) == 3 and gp.green_need == 2,
		"partial wash: reclamp %s need %d" % [str(rcp), gp.green_need])
	_ok(_events_of(evp, "stairs_awaken").is_empty(), "partial wash: stairs awoke with 2 oil left")
	# no reclamp event when nothing changed
	var evn: Array = gp.step({"type": "end_turn"})
	_ok(_events_of(evn, "quota_reclamp").is_empty(), "idle turn emitted quota_reclamp")
	# enemy-made oil pays no bloom but counts for the quota
	var ge = Game.new(1, _fixed(rows, ["water_jet", "mycelium_dash"], {"fdef": {"green_need": 2}, "grafts": ["bloom_surge"], "bloom": 5}))
	ge.terrain[Vector2i(2, 1)] = {"kind": "oil", "bloom": 0}
	var eve: Array = ge.step({"type": "cleanse", "target": Vector2i(2, 1)})
	_ok(_events_of(eve, "cleanse").size() == 1 and ge.bloom == 5 and ge.greened == 1,
		"enemy oil cleanse: bloom %d (want 5) greened %d (want 1) events %s" % [ge.bloom, ge.greened, str(eve)])
	_ok(ge.terrain[Vector2i(2, 1)]["kind"] == "growth", "enemy oil cleanse: tile %s" % str(ge.terrain.get(Vector2i(2, 1))))
	# mapgen oil (no bloom key) still pays 1 + surge
	var evm: Array = ge.step({"type": "move", "dir": Vector2i(1, 0)})
	_ok(_events_of(evm, "illegal").is_empty(), "enemy oil: move onto growth illegal")
	# 5 + 1 (tile) + 1 (surge) + 5 (floor_restored: last corruption gone) = 12
	var evc: Array = ge.step({"type": "cleanse", "target": Vector2i(3, 1)})
	_ok(_events_of(evc, "cleanse").size() == 1 and _events_of(evc, "floor_restored").size() == 1 and ge.bloom == 12 and ge.greened == 2,
		"mapgen oil cleanse: bloom %d (want 12) greened %d (want 2) events %s" % [ge.bloom, ge.greened, str(evc)])
	_ok(_events_of(evc, "stairs_awaken").size() == 1 and ge.green_need == 2, "mapgen oil cleanse: stairs_awaken / need %d" % ge.green_need)
	# enemy-made oil sources carry bloom 0: sludge trail
	var rows_s := [
		"#########",
		"#@......#",
		"#########",
	]
	var gs = Game.new(1, _fixed(rows_s, ["water_jet", "mycelium_dash"]))
	gs._spawn("oil_sludge", Vector2i(6, 1))
	gs.turn = 0  # sludge is slow: acts on even turns
	gs._compute_intents()
	gs.step({"type": "end_turn"})
	var trail_ok: bool = gs.terrain.has(Vector2i(6, 1)) and gs.terrain[Vector2i(6, 1)].get("kind", "") == "oil" \
		and int(gs.terrain[Vector2i(6, 1)].get("bloom", 1)) == 0
	_ok(trail_ok, "sludge trail: terrain at (6,1) %s" % str(gs.terrain.get(Vector2i(6, 1))))
	print("quota reclamp: wash 2->0, ignite 2->0, partial 3->2; enemy oil pays 0 bloom, counts greened")


# --- h) config keys -----------------------------------------------------------

func _check_config_keys() -> void:
	var g = Game.new(1, {"grafts": ["carapace"]})
	_ok(g.player["grafts"] == ["carapace"] and g.player["shield"] == 2, "config grafts: %s shield %d" % [str(g.player["grafts"]), g.player["shield"]])
	var g2 = Game.new(1, {"grafts": ["no_such_graft", "deep_cells"]})
	_ok(g2.player["grafts"] == ["deep_cells"], "config grafts with unknown id: %s" % str(g2.player["grafts"]))
	var g3 = Game.new(1, {"bloom": 7})
	_ok(g3.bloom == 7 and g3.snapshot()["bloom"] == 7, "config bloom: %d" % g3.bloom)
	_ok(Game.new(1).bloom == 0, "default bloom not 0")
	var c = g.clone()
	_ok(c.player["grafts"] == ["carapace"] and c.snapshot()["player"]["grafts"] == ["carapace"], "clone drops config grafts")
	print("config keys: grafts pre-install (carapace shield 2, unknown skipped), bloom 7")


# --- i) attribution -----------------------------------------------------------

func _check_attribution() -> void:
	# lance ignites oil under an enemy: the tile is signed, the burn is fire:solar_lance
	var rows := [
		"#########",
		"#@~d....#",
		"#########",
	]
	var g = Game.new(1, _fixed(rows, ["solar_lance", "mycelium_dash"]))
	g.terrain[Vector2i(3, 1)] = {"kind": "oil"}
	var evs: Array = g.step({"type": "ability", "slot": 0, "target": Vector2i(1, 0)})
	var lance_hits: Array = []
	for ev in _events_of(evs, "damage"):
		if ev.get("who", "") == "drill_bot":
			lance_hits.append(ev.get("src", ""))
	_ok(lance_hits == ["solar_lance"], "lance hit srcs %s" % str(lance_hits))
	_ok(g.terrain[Vector2i(2, 1)].get("by", "") == "solar_lance" and g.terrain[Vector2i(3, 1)].get("by", "") == "solar_lance",
		"lance fire tiles %s %s" % [str(g.terrain.get(Vector2i(2, 1))), str(g.terrain.get(Vector2i(3, 1)))])
	var snap_t: Dictionary = g.snapshot()["terrain"]
	_ok(snap_t[Vector2i(2, 1)].get("by", "") == "solar_lance", "snapshot terrain lost by")
	_ok(g.clone().terrain[Vector2i(2, 1)].get("by", "") == "solar_lance", "clone terrain lost by")
	var evs2: Array = g.step({"type": "end_turn"})
	var fire_srcs: Array = []
	for ev in _events_of(evs2, "damage"):
		if ev.get("who", "") == "drill_bot":
			fire_srcs.append(ev.get("src", ""))
	_ok(fire_srcs.has("fire:solar_lance"), "enemy fire srcs after end_turn %s" % str(fire_srcs))
	# water_jet shove into a wall: collision:water_jet
	var rows_w := [
		"#########",
		"#.d@....#",
		"#########",
	]
	var gw = Game.new(1, _fixed(rows_w, ["water_jet", "mycelium_dash"]))
	var evw: Array = gw.step({"type": "ability", "slot": 0, "target": Vector2i(-1, 0)})
	var coll: Array = []
	for ev in _events_of(evw, "damage"):
		coll.append(ev.get("src", ""))
	_ok(coll == ["collision:water_jet"], "water_jet srcs %s" % str(coll))
	# player-side fire source stays "fire"
	var gp = Game.new(1, _fixed(["#########", "#@......#", "#########"], ["water_jet", "mycelium_dash"]))
	gp.terrain[Vector2i(1, 1)] = {"kind": "fire", "ttl": 2, "by": "solar_lance"}
	var evp: Array = gp.step({"type": "end_turn"})
	var psrc: Array = []
	for ev in _events_of(evp, "damage"):
		if ev.get("who", "") == "player":
			psrc.append(ev.get("src", ""))
	_ok(psrc == ["fire"], "player fire srcs %s" % str(psrc))
	# igniter enemy walking into oil signs the tile with its kind
	var gm = Game.new(1, _fixed(["#########", "#@.~m...#", "#########"], ["water_jet", "mycelium_dash"]))
	var evm: Array = gm.step({"type": "end_turn"})
	var mite_srcs: Array = []
	for ev in _events_of(evm, "damage"):
		if ev.get("who", "") == "cinder_mite":
			mite_srcs.append(ev.get("src", ""))
	_ok(mite_srcs == ["fire:cinder_mite"], "cinder mite srcs %s" % str(mite_srcs))
	_ok(gm.terrain.has(Vector2i(3, 1)) and gm.terrain[Vector2i(3, 1)].get("by", "") == "cinder_mite",
		"mite fire tile %s" % str(gm.terrain.get(Vector2i(3, 1))))
	# spread keeps the igniter's signature; an unsigned fire reads as env
	var gsp = Game.new(1, _fixed(["#########", "#@..~~..#", "#########"], ["water_jet", "mycelium_dash"]))
	gsp.terrain[Vector2i(3, 1)] = {"kind": "fire", "ttl": 2}
	gsp.step({"type": "end_turn"})
	_ok(gsp.terrain.has(Vector2i(4, 1)) and gsp.terrain[Vector2i(4, 1)].get("kind", "") == "fire"
		and gsp.terrain[Vector2i(4, 1)].get("by", "") == "env", "spread tile %s" % str(gsp.terrain.get(Vector2i(4, 1))))
	# geyser damage is attributed to geyser, not sun_flare
	var gg = Game.new(1, _fixed(["#########", "#.d@....#", "#########"], ["geyser", "mycelium_dash"]))
	var evg: Array = gg.step({"type": "ability", "slot": 0, "target": gg.player["pos"]})
	var gsrc: Array = []
	for ev in _events_of(evg, "damage"):
		gsrc.append(ev.get("src", ""))
	_ok(gsrc.has("geyser") and not gsrc.has("sun_flare"), "geyser srcs %s" % str(gsrc))
	print("attribution: lance/fire:solar_lance/collision:water_jet/fire:cinder_mite/env spread/geyser OK; player fire src 'fire'")
