extends SceneTree
## Economy / shrine / quota checks for sim bump 2 (docs/PROGRESSION_REVIEW.md §6.2):
##  a) main-rng independence: rng.state after Game.new is the same for any
##     kit / grafts / pool / bloom / packages config on the same seed
##  b) shop stock filter: no base of an owned "+" ability, base item ids only,
##     two distinct unowned grafts (one when one remains, none when all owned)
##  c) supply pods hand out base item ids only
##  d) two-graft stock: buying one discards the other
##  d2) graft prices as data (bump 8): every offer is priced from its own
##     Content.GRAFTS row - shop_cost("graft", id) = price + GRAFT_PRICE_STEP
##     per owned graft + tier markup; legal_actions prices each pick on its
##     own (a purse between the two prices makes exactly one pick legal), the
##     buy deducts that pick's price, snapshot().shop.graft_prices lines up
##     with .grafts (in a clone too), and the id-less fallback is unchanged
##  e) the shrine ability card is only buyable with a free kit slot
##  f) press/forge: shop-gated, tier markup, forge once per floor, never
##     scraps mobility; Boarded shrines board every purchase and service
##  g) quota re-clamp after bloomless corruption removal; enemy oil pays 0;
##     fire is pending corruption (Content.counts_as_corruption), so neither
##     igniting a slick nor the burnout that follows re-clamps, while washing
##     a fire or an ash tile away does; the room bloom and the floor restore
##     wait for the ash too, and neither fire nor ash shields the boss core
##  h) config keys "grafts" and "bloom"
##  d4) state_hash hashes STORED state only: derived snapshot keys never enter
##     the hash, so state_hash() == the hash of a snapshot with graft_prices
##     stripped, differs from hashing the full snapshot wherever the shrine
##     stocks grafts, and is identical either way on a graftless shrine
##  d3) the regen_on_growth stat key (bump 8): _begin_player_turn adds
##     _graft_stat("regen_on_growth") to regen only while the tender stands on
##     growth. No shipped GRAFTS row uses it - it exists so a conditional
##     alternative to solar_core can be measured - so the behaviour is driven
##     through a subclass that pretends to hold one
##  i) damage attribution: fire tiles carry "by", enemy-side sources are
##     "fire:<by>" / "collision:<aid>", player-side sources unchanged
##  j) loadouts (Block A, bump 7): config "loadout" picks the kit from
##     Content.LOADOUTS, an explicit "kit" wins, an unknown id warns and plays
##     tender, kit_ban applies after the loadout kit, open_pool adds every
##     package id to the pool; rng.state after Game.new is the same for the
##     default config, every loadout and open_pool
##  k) Block D1 (bump 9): rng.state after Game.new for the default config is
##     pinned per seed to the values the bump-8 tree produced (RNG_STATE_BUMP8,
##     seeds 1..50) - the surge / Spore Trail pass touched no main-rng draw;
##     and Game.ability_cost is unchanged in shape for every ABILITIES row on
##     and off growth (base off growth; maxi(1, base - 1) on growth for a cost
##     >= 2 row, base for a cost-1 row - a stat surge never moves the price)
##  l) Block D2 (bump 10): the shrine reroll. Legal only on the shrine with a
##     stocked re-drawable slot, under SHOP_REROLL_CAP and an affordable
##     shop_cost("reroll") (base + SHOP_REROLL_STEP per spin + tier markup);
##     every other case is one illegal event that changes nothing. A reroll
##     redraws each stocked ability / grafts / item slot through its own side
##     generator (reroll<n>_<slot>), excluding the current offer(s) whenever an
##     alternative exists and keeping them otherwise, never re-creates a bought
##     slot, never touches heal / press / forge, costs no charge, leaves
##     rng.state untouched and is reproducible across fresh games; shop.rerolls
##     is stored (clone copies it, state_hash moves with it) while
##     reroll_price / rerolls_left are derived snapshot keys the hash ignores
##  m) Block D3 (bump 11): no new main-rng draw. The Game.new pins (k) still
##     hold; Game._chase_step on rooms where fire and an avoider meet (the
##     search relaxes nodes) and the screened execution of a gum leave
##     rng.state untouched; and a Game subclass that swaps only the two D3
##     entry points back (the reference BFS for _chase_step, _screened false)
##     drives the optimizer over seeds 1..10 to the rng.state recorded at
##     every floor entry (RNG_FLOOR_ENTRY_BUMP13) - so nothing outside those
##     two functions moved a draw
##  n) Block D4 (bump 12): the draft draws moved on purpose (exactly one
##     main-rng draw per slot, see tests/test_grammar.gd (d)), so the
##     floor-entry pins were re-recorded on this tree; the Game.new pins (k)
##     are untouched - the draft happens after floor 1
##  o) Block D6 (bump 13, evolve forks): the shrine forge offers BOTH variants
##     of the kept ability, so legal_actions lists one upcycle_ability per
##     (keep, scrap, variant) triple - every listed triple resolves, none
##     scraps mobility, none names an already-upgraded keep or an out-of-range
##     index, all of them cost the one forge price (a fork is a choice, not a
##     price tier), the once-per-floor rule and the tier markup are unchanged,
##     and listing or forging spends no main-rng draw. The floor-entry pins
##     were re-recorded again: the draw COUNT per draft slot is still one, but
##     the universe now holds both siblings of every held base, so each index
##     resolves differently (see the note on RNG_FLOOR_ENTRY_BUMP13)
## Run: godot --headless --path . --script tests/test_economy.gd

const Content := preload("res://sim/content.gd")
const Game := preload("res://sim/game.gd")
const Roster := preload("res://bots/roster.gd")
const Sweep := preload("res://tests/sweep_lib.gd")

const RNG_SEEDS := 50
const STOCK_SEEDS := 200
const POD_TARGET := 30
const GOUGING_TIER := 5  # Content.TIERS[4] is "Gouging Prices"
## rng.state after Game.new(seed) for seeds 1..50, default config, recorded on
## the bump-8 tree (git HEAD before Block D1). A deliberate mapgen or spawn
## change re-pins these; anything else that moves one is a stray main-rng draw.
const RNG_STATE_BUMP8 := [
	5089575408282122190, -1543445859615755461, 5249088221260300708, -7365291246896200391, -4307724339993763098,
	-5880482361733646265, -2810552436854674636, -1230729324925988375, 2921800532955938594, 2473378904339026979,
	-6414414183668122812, 2991425153590813089, 3396970675805829714, 6179986816058712103, 8222375506542086136,
	-8307466868879457330, -1913913789140790326, -920277023256220633, 4456736551290949148, 6774621626282757442,
	8078245979767963114, 8887448235998919003, -343293399291332840, 7114140600357843809, 1220613033662260858,
	5388088503146639011, 8794150899137250344, 3259365569618313117, 3035381574159428702, 6917545318854331931,
	-2123855832781644880, -5508205788817708395, 744473577580189906, -2489741651320926877, 1249249924779478724,
	-7126007905707854211, 5483058272966479890, 7488929353488925007, 4469199078683118676, -4333298479256176359,
	8916454498695204738, 8748522282163598855, 8919786808711414480, -159301045649121847, 7650199452722886150,
	7411140844524094591, -4638585121757713264, 6393578473144512909, -5397919597486566550, -4398859535905301253,
]

## rng.state after Game.new and then right after every step that entered a
## new floor, optimizer persona, seeds 1..10, replayed by RefGame below (the
## pre-D3 chase and no smoke screen). Re-pinned on the bump-12 tree (Block D4):
## the affinity-slotted draft deliberately moved the draft draws (one main-rng
## draw per slot instead of min(count, candidates) from one list), so every
## run diverges from its first draft on and the bump-10 values could not
## survive; the Game.new column (floor 1) is unchanged from RNG_STATE_BUMP8.
## Re-pinned once more inside bump 12 when the upgrade slot took the
## AFFINITY_IGNORED_TAGS filter: the draw COUNT is what these guard and it is
## untouched (one per slot), but a filtered candidate list resolves each index
## differently, so the persona plays a different run from its first draft.
## RE-PINNED FOR BUMP 13 (Block D6, evolve forks) for the same reason: the
## draw count is still exactly one per slot, but the draft universe now holds
## BOTH variants of every held base and the upgrade slot deals the parity one,
## so each index resolves to a different ability and the persona plays a
## different run from its first draft on.
## THESE VALUES DEPEND ON bots/optimizer.gd, WHICH THIS BUMP ALSO TOUCHES,
## and they have now been RE-STAMPED for the converted bot: the persona's
## _pref_rank reads Content.base_id / Content.is_upgrade instead of
## trim_suffix("+") / ends_with("+"), so a variant offer ranks one step above
## its base again instead of falling off DRAFT_PREF as "unlisted". Five of the
## ten seeds moved when that landed (seeds 3, 5, 6, 7 and 8 - three of them
## reaching a different number of floors), which is the whole point of the
## pins: they are how a bot-side suffix bug shows up as numbers. Re-stamp
## by running an optimizer run per seed on RefGame below and printing
## rng.state at Game.new and after every floor entry.
## From here on, anything that moves one of these is a stray main-rng draw.
const RNG_FLOOR_ENTRY_BUMP13 := [
	[5089575408282122190, -184513544007953650, 8759944363161018601, 2868822161275640310, -8152873371107847509],
	[-1543445859615755461, -8411093148249300473, 1787517375204971321, 8582635207152789512],
	[5249088221260300708, -8668300741929293400, 4694250479173219183, 5574227338355628461, -3061484965246952852, -1172107250573503496],
	[-7365291246896200391, 9118581067688907677, 4174390183580078064, -5937068460318379825, 516707025151674802, -3494329032662390890, 3201227568282568284],
	[-4307724339993763098, -3504797669898524666, 6961354990307791117, 464051487255323640, -4057801299652768257, 7021950593982289331, -3832266116403619108],
	[-5880482361733646265, -808239912685928521, -4338090631578911018, -8046437620736313008, 4196872015560688783, -422735934883274349, -1941129409381335253],
	[-2810552436854674636, 5839575857474482460, 4565013434687613195, -1843283859693427995, -7995792451489974632, -174968855415995460],
	[-1230729324925988375, 1420908871602353461, 6357929784085942264, -926346255672728079, -6150833711807613437, -7107847693446950901, -8495234952923389292],
	[2921800532955938594, 1587407093833056826, 3824933404910214398, 3934717501292175332, 3378600504722340502, -5312019873132383350, 1260004648369663161],
	[2473378904339026979, 8392605424486942015, 2657003823126323915, 5422367580079282869, 8572526701641051724],
]


## The sim with the two Block D3 entry points swapped back (the old BFS chase
## and no smoke screen) and nothing else, so an optimizer run on it must
## reproduce the pins above exactly. Used only by (m).
class RefGame extends Game:
	func _chase_step(e: Dictionary) -> Vector2i:
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

	func _screened(_e: Dictionary, _itype: String) -> bool:
		return false


var checks := 0
var failures: Array = []


func _init() -> void:
	_check_rng_independence()
	_check_stock_filter()
	_check_pods_and_shops_in_play()
	_check_graft_buy()
	_check_graft_prices()
	_check_state_hash_view()
	_check_regen_on_growth()
	_check_ability_buy_kit_slot()
	_check_press_forge_boarded()
	_check_quota_reclamp()
	_check_config_keys()
	_check_attribution()
	_check_loadouts()
	_check_d1_rng_pins()
	_check_d1_ability_cost()
	_check_reroll_legality()
	_check_reroll_price_and_cap()
	_check_reroll_redraw()
	_check_reroll_state()
	_check_d3_rng_untouched()
	_check_d6_forge_actions()
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
		{"kit": ["solar_lance+noon", "seed_bomb", "mycelium_dash", "vine_whip", "water_jet"]},
		{"grafts": Content.GRAFTS.keys()},
		{"grafts": ["solar_core"]},  # prices are pure table reads: never an rng draw
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
	var kit := ["solar_lance+noon", "seed_bomb", "mycelium_dash"]
	# every graft but the last pre-installed: the one remaining is the only offer
	var all_but_last: Array = Content.GRAFTS.keys().slice(0, Content.GRAFTS.size() - 1)
	var last: String = Content.GRAFTS.keys()[Content.GRAFTS.size() - 1]
	var bad_ability := 0
	var bad_item := 0
	var bad_grafts := 0
	var bad_keys := 0
	var allowed := {"heal": true, "press": true, "forge": true, "ability": true, "grafts": true, "item": true, "rerolls": true}
	for s in range(1, STOCK_SEEDS + 1):
		var g = Game.new(s, {"kit": kit})
		var shop: Dictionary = g.shop
		for k in shop:
			if not allowed.has(k):
				bad_keys += 1
		# the reroll counter is stored stock, fresh at 0 (Block D2)
		if int(shop.get("rerolls", -1)) != 0:
			bad_keys += 1
		if not shop.has("ability") or shop["ability"] == "solar_lance" or kit.has(shop["ability"]):
			bad_ability += 1
		# ITEMS keep the plain "+" convention: the press is not the Block D6
		# ability forge, so ends_with("+") is right on an item id
		if not shop.has("item") or String(shop["item"]).ends_with("+"):
			bad_item += 1
		var gr: Array = shop.get("grafts", [])
		if gr.size() != 2 or gr[0] == gr[1] or not Content.GRAFTS.has(gr[0]) or not Content.GRAFTS.has(gr[1]):
			bad_grafts += 1
		var g5 = Game.new(s, {"grafts": all_but_last})
		var gr5: Array = g5.shop.get("grafts", [])
		if gr5 != [last]:
			bad_grafts += 1
		# held grafts never reappear in the stock (four held: both offers unheld)
		var held: Array = Content.GRAFTS.keys().slice(0, 4)
		var g4 = Game.new(s, {"grafts": held})
		var gr4: Array = g4.shop.get("grafts", [])
		if gr4.size() != 2 or held.has(gr4[0]) or held.has(gr4[1]) or gr4[0] == gr4[1]:
			bad_grafts += 1
		var g6 = Game.new(s, {"grafts": Content.GRAFTS.keys()})
		if g6.shop.has("grafts") or g6.shop.has("graft"):
			bad_grafts += 1
	_ok(bad_keys == 0, "stock: %d unexpected shop keys" % bad_keys)
	_ok(bad_ability == 0, "stock: %d shops offered an owned/owned-plus base ability" % bad_ability)
	_ok(bad_item == 0, "stock: %d shops offered a + item" % bad_item)
	_ok(bad_grafts == 0, "stock: %d graft offers wrong (2 distinct / 1 remaining / none / held excluded)" % bad_grafts)
	_ok(Content.GRAFTS.size() == 10, "stock draws from %d grafts (C3: ten)" % Content.GRAFTS.size())
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
				# items keep the plain "+" convention (not forked by Block D6)
				if game.shop.has("item") and String(game.shop["item"]).ends_with("+"):
					plus_shop_items += 1
				if game.shop.has("ability"):
					var aid := String(game.shop["ability"])
					# an ability base is excluded when ANY of its variants is
					# held, so fold the kit onto base ids
					for kid in game.player["kit"]:
						if Content.base_id(String(kid)) == aid:
							owned_base_offers += 1
							break
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
	_ok(g.bloom == bloom_before - int(Content.GRAFTS[offers[1]]["price"]),
		"graft buy: bloom %d -> %d, %s costs %d" % [bloom_before, g.bloom, offers[1], int(Content.GRAFTS[offers[1]]["price"])])
	# the old scalar form is gone: a pick-less buy is illegal
	var g2 = Game.new(1, {"bloom": 20})
	g2.player["pos"] = g2.map["shrine"]
	var evs2: Array = g2.step({"type": "buy", "item": "graft"})
	_ok(not _events_of(evs2, "illegal").is_empty() and g2.player["grafts"].is_empty(), "graft buy without pick was accepted")
	# price steps with owned grafts, pre-installed ones included
	# the id-less fallback is untouched by pricing-as-data: still 4 + 2 per held
	var g3 = Game.new(1, {"grafts": ["carapace"]})
	_ok(g3.shop_cost("graft") == Content.SHOP_COSTS["graft"] + Content.GRAFT_PRICE_STEP,
		"graft price with one config graft: %d" % g3.shop_cost("graft"))
	_ok(Content.GRAFT_PRICE_STEP == 2 and Content.SHOP_COSTS["graft"] == 4, "graft price step unchanged (4 + 2 per held)")
	var g4 = Game.new(1, {"grafts": ["carapace", "ember_sap", "compost"]})
	_ok(g4.shop_cost("graft") == Content.SHOP_COSTS["graft"] + 3 * Content.GRAFT_PRICE_STEP,
		"graft price with three config grafts (rule grafts count): %d" % g4.shop_cost("graft"))
	print("graft buy: offers %s, bought %s, discarded %s" % [str(offers), offers[1], offers[0]])


# --- d2) graft prices as data -------------------------------------------------

func _check_graft_prices() -> void:
	# 1) the price formula, per id, with and without owned grafts and markup
	var g0 = Game.new(1)
	var bad_formula := 0
	for gid in Content.GRAFTS:
		if g0.shop_cost("graft", gid) != int(Content.GRAFTS[gid]["price"]):
			bad_formula += 1
	_ok(bad_formula == 0, "graft price: %d ids priced off their own row on a fresh run" % bad_formula)
	var held := ["carapace", "ember_sap"]
	var gh = Game.new(1, {"grafts": held})
	var gt = Game.new(1, {"tier": GOUGING_TIER, "grafts": held})
	var bad_step := 0
	for gid in Content.GRAFTS:
		var base: int = int(Content.GRAFTS[gid]["price"])
		if gh.shop_cost("graft", gid) != base + held.size() * Content.GRAFT_PRICE_STEP:
			bad_step += 1
		if gt.shop_cost("graft", gid) != base + held.size() * Content.GRAFT_PRICE_STEP + 1:
			bad_step += 1
	_ok(bad_step == 0, "graft price: %d ids mispriced with %d held / gouging markup" % [bad_step, held.size()])
	# an unknown or empty id falls back to the flat SHOP_COSTS entry
	_ok(g0.shop_cost("graft", "no_such_graft") == Content.SHOP_COSTS["graft"]
			and g0.shop_cost("graft") == Content.SHOP_COSTS["graft"],
		"graft price: unknown id did not fall back to %d" % Content.SHOP_COSTS["graft"])
	# 2) a purse between the two offers makes exactly one pick legal
	var seed_used := -1
	var cheap := -1
	var dear := -1
	var picks: Array = []
	for s in range(1, 200):
		var gs = Game.new(s)
		var offs: Array = gs.shop.get("grafts", [])
		if offs.size() != 2:
			continue
		var p0: int = gs.shop_cost("graft", String(offs[0]))
		var p1: int = gs.shop_cost("graft", String(offs[1]))
		if p0 == p1:
			continue
		seed_used = s
		cheap = mini(p0, p1)
		dear = maxi(p0, p1)
		picks = [p0, p1]
		break
	_ok(seed_used > 0, "graft price: no seed under 200 offered two differently priced grafts")
	if seed_used > 0:
		var gm = Game.new(seed_used, {"bloom": dear - 1})
		gm.player["pos"] = gm.map["shrine"]
		var legal := 0
		var legal_pick := -1
		for a in gm.legal_actions():
			if String(a.get("type", "")) == "buy" and String(a.get("item", "")) == "graft":
				legal += 1
				legal_pick = int(a.get("pick", -1))
		_ok(legal == 1 and legal_pick == (0 if picks[0] == cheap else 1),
			"graft price: bloom %d between %d and %d -> %d legal picks (pick %d)" % [dear - 1, cheap, dear, legal, legal_pick])
		# the dear pick is not just missing from legal_actions, it is refused
		var evs: Array = gm.step({"type": "buy", "item": "graft", "pick": 1 if picks[0] == cheap else 0})
		_ok(not _events_of(evs, "illegal").is_empty() and gm.player["grafts"].is_empty(),
			"graft price: an unaffordable pick was sold anyway (%s)" % str(evs))
		# with the dear price in the purse both picks are legal again
		var gr = Game.new(seed_used, {"bloom": dear})
		gr.player["pos"] = gr.map["shrine"]
		var legal2 := 0
		for a in gr.legal_actions():
			if String(a.get("type", "")) == "buy" and String(a.get("item", "")) == "graft":
				legal2 += 1
		_ok(legal2 == 2, "graft price: bloom %d -> %d legal picks, expected 2" % [dear, legal2])
		# 3) the buy deducts that pick's own price, not the flat one
		var bad_charge := 0
		for pick in 2:
			var gb = Game.new(seed_used, {"bloom": 30})
			gb.player["pos"] = gb.map["shrine"]
			var gid: String = String(gb.shop["grafts"][pick])
			var want: int = gb.shop_cost("graft", gid)
			var before: int = gb.bloom
			gb.step({"type": "buy", "item": "graft", "pick": pick})
			if gb.bloom != before - want or gb.player["grafts"] != [gid]:
				bad_charge += 1
				failures.append("graft price: pick %d (%s) charged %d, expected %d" % [pick, gid, before - gb.bloom, want])
		_ok(bad_charge == 0, "graft price: %d picks charged the wrong price" % bad_charge)
	# 4) snapshot().shop.graft_prices lines up with .grafts, in a clone too
	var bad_snap := 0
	var no_key := 0
	for s in range(1, 60):
		var gs2 = Game.new(s)
		var snap: Dictionary = gs2.snapshot()
		var offs2: Array = snap["shop"].get("grafts", [])
		if offs2.is_empty():
			if snap["shop"].has("graft_prices"):
				no_key += 1
			continue
		var prices: Array = snap["shop"].get("graft_prices", [])
		if prices.size() != offs2.size():
			bad_snap += 1
			continue
		for i in offs2.size():
			if int(prices[i]) != gs2.shop_cost("graft", String(offs2[i])):
				bad_snap += 1
		var csnap: Dictionary = gs2.clone().snapshot()
		if csnap["shop"].get("graft_prices", []) != prices or csnap["shop"].get("grafts", []) != offs2:
			bad_snap += 1
	_ok(bad_snap == 0 and no_key == 0,
		"graft price: %d snapshots misaligned, %d graftless shops carried graft_prices" % [bad_snap, no_key])
	# a graftless shrine (every graft held) exposes neither key
	var gall = Game.new(1, {"grafts": Content.GRAFTS.keys()})
	var sall: Dictionary = gall.snapshot()
	_ok(not sall["shop"].has("grafts") and not sall["shop"].has("graft_prices"),
		"graft price: all-grafts shop %s" % str(sall["shop"]))
	print("graft prices: seed %d offers %s at %s bloom; fallback %d, step %d" % [
		seed_used, str(Game.new(maxi(seed_used, 1)).shop.get("grafts", [])), str(picks), Content.SHOP_COSTS["graft"], Content.GRAFT_PRICE_STEP])


# --- d4) state_hash hashes stored state only ----------------------------------

## snapshot().shop carries "graft_prices", "reroll_price" and "rerolls_left",
## derived per snapshot from the stock, the owned grafts, the tier and the
## stored reroll counter. state_hash() swaps in the raw stored shop dict, so a
## price table that moves never moves the hash.
const DERIVED_SHOP_KEYS := ["graft_prices", "reroll_price", "rerolls_left"]


func _check_state_hash_view() -> void:
	var with_prices := 0
	var without := 0
	var bad_strip := 0
	var bad_full := 0
	var bad_same := 0
	for s in range(1, 60):
		var g = Game.new(s)
		var snap: Dictionary = g.snapshot()
		var full := str(snap).sha256_text()
		var stripped: Dictionary = snap.duplicate(true)
		stripped["shop"] = snap["shop"].duplicate(true)
		for k in DERIVED_SHOP_KEYS:
			stripped["shop"].erase(k)
		if g.state_hash() != str(stripped).sha256_text():
			bad_strip += 1
		if snap["shop"].has("graft_prices"):
			with_prices += 1
		else:
			without += 1
		# every stocked shrine carries reroll_price, so the full snapshot
		# never hashes like the stored view
		if snap["shop"].has("reroll_price") and g.state_hash() == full:
			bad_full += 1
		if not snap["shop"].has("reroll_price") or not snap["shop"].has("rerolls_left"):
			bad_same += 1
	_ok(bad_strip == 0, "state_hash: %d seeds disagreed with the derived-key-stripped snapshot" % bad_strip)
	_ok(with_prices > 0 and bad_full == 0,
		"state_hash: %d of %d stocked shrines hashed the same as the full snapshot" % [bad_full, with_prices])
	_ok(bad_same == 0, "state_hash: %d stocked shrines lacked reroll_price / rerolls_left" % bad_same)
	# an explicitly graftless shrine (every graft already held): no graft_prices,
	# but the reroll keys are still derived and still stripped
	var gall = Game.new(1, {"grafts": Content.GRAFTS.keys()})
	var sall: Dictionary = gall.snapshot()
	var sall_stripped: Dictionary = sall.duplicate(true)
	sall_stripped["shop"] = gall.shop
	_ok(not sall["shop"].has("graft_prices") and sall["shop"].has("reroll_price")
			and gall.state_hash() == str(sall_stripped).sha256_text() and gall.state_hash() != str(sall).sha256_text(),
		"state_hash: graftless shrine %s" % str(sall["shop"]))
	# a boarded shop is {} with no derived key at all: full and stored views agree
	var gbd = Game.new(1, {"mutators": ["boarded"]})
	var sbd: Dictionary = gbd.snapshot()
	_ok(sbd["shop"].is_empty() and gbd.state_hash() == str(sbd).sha256_text(),
		"state_hash: boarded shop %s" % str(sbd["shop"]))
	# and the hash still tracks stored state: buying a graft moves it
	var gb = Game.new(1, {"bloom": 30})
	var before := gb.state_hash()
	gb.player["pos"] = gb.map["shrine"]
	gb.step({"type": "buy", "item": "graft", "pick": 0})
	_ok(gb.state_hash() != before and not gb.player["grafts"].is_empty(),
		"state_hash: a graft purchase left the hash unchanged")
	print("state_hash: %d priced / %d graftless shrines over 59 seeds; derived keys stay out" % [with_prices, without])


# --- d3) the regen_on_growth stat key -----------------------------------------

## Game with one imaginary graft granting `stat` - the table is a const, so a
## key no shipped row uses is exercised by overriding the one table read.
class _StatProbe extends Game:
	var probe_stat: Dictionary = {}

	func _graft_stat(key: String) -> int:
		return super(key) + int(probe_stat.get(key, 0))


func _check_regen_on_growth() -> void:
	# no shipped row uses the key: a real run never pays it
	var live := 0
	for gid in Content.GRAFTS:
		live += int(Content.GRAFTS[gid].get("stat", {}).get("regen_on_growth", 0))
	_ok(live == 0, "regen_on_growth: %d shipped points - the key is meant to be unused" % live)
	var plain = Game.new(1)
	plain.terrain[plain.player["pos"]] = {"kind": "growth"}
	plain._begin_player_turn()
	var base_charge: int = plain.player["charge"]
	plain.terrain.erase(plain.player["pos"])
	plain._begin_player_turn()
	_ok(plain.player["charge"] == base_charge, "regen_on_growth: growth moved regen with no graft holding the key")
	# unconditional regen (the shipped solar_core shape) pays everywhere
	var sun = Game.new(1, {"grafts": ["solar_core"]})
	sun._begin_player_turn()
	_ok(sun.player["charge"] == base_charge + 1, "regen_on_growth: solar_core regen %d, expected %d" % [sun.player["charge"], base_charge + 1])
	# the conditional key pays on growth and nowhere else
	var p = _StatProbe.new(1)
	p.probe_stat = {"regen_on_growth": 1}
	p.terrain.erase(p.player["pos"])
	p._begin_player_turn()
	var off: int = p.player["charge"]
	p.terrain[p.player["pos"]] = {"kind": "growth"}
	p._begin_player_turn()
	var on: int = p.player["charge"]
	_ok(off == base_charge and on == base_charge + 1,
		"regen_on_growth: charge off growth %d (want %d), on growth %d (want %d)" % [off, base_charge, on, base_charge + 1])
	# oil is not growth: only the growth tile pays
	p.terrain[p.player["pos"]] = {"kind": "oil"}
	p._begin_player_turn()
	_ok(p.player["charge"] == base_charge, "regen_on_growth: oil paid the growth bonus (%d)" % p.player["charge"])
	print("regen_on_growth: %d shipped points; base charge %d, +1 only on growth" % [live, base_charge])


# --- e) ability buy needs a free kit slot -------------------------------------

func _check_ability_buy_kit_slot() -> void:
	var kit := ["solar_lance", "seed_bomb", "mycelium_dash", "vine_whip", "water_jet"]
	var g = Game.new(1, {"bloom": 20, "kit": kit})
	g.player["pos"] = g.map["shrine"]
	_ok(g.shop.has("ability"), "ability buy: no ability stocked with kit %s" % str(kit))
	var aid: String = g.shop.get("ability", "")
	# a full kit simply cannot buy: no ability buy action of any shape
	var buy_acts := 0
	for a in g.legal_actions():
		if a.get("type", "") == "buy" and a.get("item", "") == "ability":
			buy_acts += 1
	_ok(buy_acts == 0, "ability buy: %d ability buy actions with a full kit" % buy_acts)
	# a hand-built drop purchase is illegal and changes nothing
	var kit_before: Array = g.player["kit"].duplicate()
	var bloom_before: int = g.bloom
	var evs_bad: Array = g.step({"type": "buy", "item": "ability", "drop": 0})
	_ok(not _events_of(evs_bad, "illegal").is_empty(), "ability buy: full-kit drop buy emitted no illegal")
	_ok(_events_of(evs_bad, "buy").is_empty(), "ability buy: full-kit drop buy emitted a buy event")
	_ok(g.player["kit"] == kit_before, "ability buy: kit changed to %s" % str(g.player["kit"]))
	_ok(g.bloom == bloom_before, "ability buy: bloom %d -> %d" % [bloom_before, g.bloom])
	_ok(g.shop.has("ability"), "ability buy: illegal buy still cleared the shop stock")
	# kit not full: plain buy appends
	var g2 = Game.new(1, {"bloom": 20})
	g2.player["pos"] = g2.map["shrine"]
	var aid2: String = g2.shop.get("ability", "")
	_ok(g2.player["kit"].size() == 3, "ability buy: starting kit %s is not size 3" % str(g2.player["kit"]))
	_ok(_has_action(g2.legal_actions(), "buy", {"item": "ability"}), "ability buy: plain buy missing with 3-kit")
	var evs2: Array = g2.step({"type": "buy", "item": "ability"})
	var buys := _events_of(evs2, "buy")
	_ok(g2.player["kit"].size() == 4 and g2.player["kit"][3] == aid2, "ability buy: 3-kit append -> %s" % str(g2.player["kit"]))
	_ok(buys.size() == 1 and buys[0].get("id", "") == aid2 and not buys[0].has("dropped"),
		"ability buy: event %s" % str(buys))
	_ok(not g2.shop.has("ability"), "ability buy: shop still stocks ability after the buy")
	print("ability buy: full kit offers %d ability buys, 3-kit bought %s (shop stocked %s)" % [buy_acts, aid2, aid])


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
	_ok(not _events_of(evs, "upcycle_ability").is_empty() and g.player["kit"] == ["solar_lance+noon", "mycelium_dash"],
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
	# ignite: the lance turns both oil tiles into fire. Fire is pending
	# corruption (Content.counts_as_corruption: its burns_to is ash), so the
	# count is unchanged, the gate does not shrink and the stairs stay
	# dormant - lighting a slick is a detour, never a discount
	var gi = Game.new(1, _fixed(rows, ["solar_lance", "mycelium_dash"], {"fdef": {"green_need": 2}}))
	_ok(gi.green_need == 2 and gi._count_corruption() == 2, "ignite setup: need %d count %d" % [gi.green_need, gi._count_corruption()])
	var evi: Array = gi.step({"type": "ability", "slot": 0, "target": Vector2i(1, 0)})
	_ok(_events_of(evi, "ignite").size() == 2, "ignite: %d ignite events" % _events_of(evi, "ignite").size())
	_ok(_events_of(evi, "quota_reclamp").is_empty(), "ignite: quota_reclamp fired %s" % str(_events_of(evi, "quota_reclamp")))
	_ok(_events_of(evi, "stairs_awaken").is_empty(), "ignite: stairs awoke over a burning gate (%s)" % str(evi))
	_ok(gi.green_need == 2 and gi._count_corruption() == 2, "ignite: need %d count %d (fire counts)" % [gi.green_need, gi._count_corruption()])
	_ok(gi.terrain[Vector2i(2, 1)].get("by", "") == "solar_lance", "ignite: fire by %s" % str(gi.terrain.get(Vector2i(2, 1))))
	# counting is the only rule that changed: a fire is still not cleansable
	_ok(not _has_action(gi.legal_actions(), "cleanse"), "ignite: fire offered as a cleanse target")
	var stairs_pos: Vector2i = gi.map["stairs"]
	var here: Vector2i = gi.player["pos"]
	gi.player["pos"] = stairs_pos
	_ok(not _has_action(gi.legal_actions(), "descend"), "ignite: descend legal with the gate unmet")
	gi.player["pos"] = here
	# burnout: the fires (ttl 2) become ash over two end_turns. The tile was
	# corruption for the counter the whole way through, so no quota_reclamp
	# fires at either end of the burn
	var evb1: Array = gi.step({"type": "end_turn"})
	var evb2: Array = gi.step({"type": "end_turn"})
	_ok(_events_of(evb1, "quota_reclamp").is_empty() and _events_of(evb2, "quota_reclamp").is_empty(), "burnout: reclamp fired %s %s" % [str(evb1), str(evb2)])
	_ok(_events_of(evb1, "ash").is_empty() and _events_of(evb2, "ash").size() == 2, "burnout: ash events %s / %s" % [str(_events_of(evb1, "ash")), str(_events_of(evb2, "ash"))])
	_ok(gi.terrain.get(Vector2i(2, 1), {}) == {"kind": "ash"} and gi.terrain.get(Vector2i(3, 1), {}) == {"kind": "ash"},
		"burnout: tiles %s %s" % [str(gi.terrain.get(Vector2i(2, 1))), str(gi.terrain.get(Vector2i(3, 1)))])
	_ok(gi._count_corruption() == 2 and gi.green_need == 2, "burnout: count %d need %d (the gate never moved)" % [gi._count_corruption(), gi.green_need])
	# cleansing the mapgen-oil ash pays the table's 1 and counts greened; the event names the kind
	var evca: Array = gi.step({"type": "cleanse", "target": Vector2i(2, 1)})
	var cla := _events_of(evca, "cleanse")
	_ok(cla.size() == 1 and cla[0].get("kind", "") == "ash" and gi.greened == 1 and gi.terrain[Vector2i(2, 1)]["kind"] == "growth",
		"ash cleanse: %s greened %d" % [str(cla), gi.greened])
	# washing a live fire is a real removal (nothing is left to burn to ash):
	# the re-clamp fires, exactly as it does for oil or ash
	var gf = Game.new(1, _fixed(rows, ["water_jet", "mycelium_dash"], {"fdef": {"green_need": 2}}))
	gf.terrain[Vector2i(2, 1)] = {"kind": "fire", "ttl": 2, "by": "solar_lance"}
	gf.terrain[Vector2i(3, 1)] = {"kind": "fire", "ttl": 2, "by": "solar_lance"}
	_ok(gf.green_need == 2 and gf._count_corruption() == 2, "fire wash setup: need %d count %d" % [gf.green_need, gf._count_corruption()])
	var evf: Array = gf.step({"type": "ability", "slot": 0, "target": Vector2i(1, 0)})
	var rcf := _events_of(evf, "quota_reclamp")
	_ok(_events_of(evf, "wash").size() == 2 and rcf.size() == 1 and int(rcf[0].get("need", -1)) == 0 and int(rcf[0].get("was", -1)) == 2 and gf.green_need == 0,
		"fire wash: %d washes, reclamp %s need %d" % [_events_of(evf, "wash").size(), str(rcf), gf.green_need])
	_ok(not gf.terrain.has(Vector2i(2, 1)) and not gf.terrain.has(Vector2i(3, 1)), "fire wash: tiles gone %s" % str(gf.terrain))
	# washing ash is a bloomless removal like washing oil: the re-clamp still fires
	var ga = Game.new(1, _fixed(rows, ["water_jet", "mycelium_dash"], {"fdef": {"green_need": 2}}))
	ga.terrain[Vector2i(2, 1)] = {"kind": "ash", "bloom": 0}
	ga.terrain[Vector2i(3, 1)] = {"kind": "ash"}
	_ok(ga.green_need == 2 and ga._count_corruption() == 2, "ash wash setup: need %d count %d" % [ga.green_need, ga._count_corruption()])
	var eva: Array = ga.step({"type": "ability", "slot": 0, "target": Vector2i(1, 0)})
	var rca := _events_of(eva, "quota_reclamp")
	_ok(_events_of(eva, "wash").size() == 2 and rca.size() == 1 and int(rca[0].get("need", -1)) == 0 and int(rca[0].get("was", -1)) == 2 and ga.green_need == 0,
		"ash wash: %d washes, reclamp %s need %d" % [_events_of(eva, "wash").size(), str(rca), ga.green_need])
	_ok(not ga.terrain.has(Vector2i(2, 1)) and not ga.terrain.has(Vector2i(3, 1)), "ash wash: tiles gone %s" % str(ga.terrain))
	# enemy-made oil (bloom 0) ignited by the lance burns to bloom-0 ash: its cleanse pays 0 but counts
	var gz = Game.new(1, _fixed(rows, ["solar_lance", "mycelium_dash"], {"fdef": {"green_need": 2}, "bloom": 5}))
	gz.terrain[Vector2i(2, 1)] = {"kind": "oil", "bloom": 0}
	gz.step({"type": "ability", "slot": 0, "target": Vector2i(1, 0)})
	_ok(gz.terrain.get(Vector2i(2, 1), {}) == {"kind": "fire", "ttl": 2, "by": "solar_lance", "bloom": 0}, "enemy oil fire: %s" % str(gz.terrain.get(Vector2i(2, 1))))
	gz.step({"type": "end_turn"})
	gz.step({"type": "end_turn"})
	_ok(gz.terrain.get(Vector2i(2, 1), {}) == {"kind": "ash", "bloom": 0}, "enemy oil ash: %s" % str(gz.terrain.get(Vector2i(2, 1))))
	var evz: Array = gz.step({"type": "cleanse", "target": Vector2i(2, 1)})
	_ok(_events_of(evz, "cleanse").size() == 1 and gz.bloom == 5 and gz.greened == 1, "bloom-0 ash cleanse: bloom %d (want 5) greened %d" % [gz.bloom, gz.greened])
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
	_ok(_events_of(eve, "cleanse").size() == 1 and ge.bloom == 5 and ge.greened == 1 and _events_of(eve, "cleanse")[0].get("kind", "") == "oil",
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
	_check_pending_corruption()
	print("quota reclamp: wash 2->0, ignite no reclamp (fire counts), burnout to ash no reclamp, fire/ash wash 2->0, partial 3->2; enemy oil / bloom-0 ash pay 0 bloom, count greened")


## Pending corruption, the other two consumers: a room whose last corruption
## is burning does not bloom, and a floor whose last corruption is burning is
## not restored - both wait for the ash. The boss gate is untouched by either
## (shields_core still reads is_corruption, and neither fire nor ash shields).
func _check_pending_corruption() -> void:
	var rows := [
		"#######",
		"#.~.>.#",
		"#;@...#",
		"#######",
	]
	var g = Game.new(1, _fixed(rows, ["solar_lance", "mycelium_dash"], {"fdef": {"green_need": 0}}))
	g.map["rooms"] = [Rect2i(1, 1, 5, 2)]
	var seen: Array = []
	_ok(g._count_corruption() == 2 and g._room_has_corruption(0), "pending setup: count %d room %s" % [g._count_corruption(), str(g._room_has_corruption(0))])
	_ok(g._corruption_adjacent(Vector2i(3, 1)), "pending setup: oil shields the core")
	# 1. light the oil overhead
	seen.append_array(g.step({"type": "ability", "slot": 0, "target": Vector2i(0, -1)}))
	_ok(g.terrain.get(Vector2i(2, 1), {}).get("kind", "") == "fire", "pending: oil not lit (%s)" % str(g.terrain.get(Vector2i(2, 1))))
	_ok(g._room_has_corruption(0), "pending: burning room reads clean")
	_ok(not g._corruption_adjacent(Vector2i(3, 1)), "pending: fire shields the core")
	seen.append_array(g.step({"type": "end_turn"}))
	# 2. cleanse the room's other corruption: the fire still counts, so the
	#    room does not bloom and the floor is not restored
	seen.append_array(g.step({"type": "cleanse", "target": Vector2i(1, 2)}))
	_ok(_events_of(seen, "room_bloom").is_empty(), "pending: room bloomed with the fire still burning (%s)" % str(seen))
	_ok(_events_of(seen, "floor_restored").is_empty(), "pending: floor restored with the fire still burning")
	_ok(g._count_corruption() == 1 and g._room_has_corruption(0), "pending: count %d room %s" % [g._count_corruption(), str(g._room_has_corruption(0))])
	# 3. the fire burns out; ash is corruption outright, so nothing changes
	while g.terrain.get(Vector2i(2, 1), {}).get("kind", "") == "fire":
		seen.append_array(g.step({"type": "end_turn"}))
	_ok(g.terrain.get(Vector2i(2, 1), {}).get("kind", "") == "ash", "pending: fire left %s" % str(g.terrain.get(Vector2i(2, 1))))
	_ok(_events_of(seen, "ash").size() == 1, "pending: %d ash events" % _events_of(seen, "ash").size())
	_ok(_events_of(seen, "room_bloom").is_empty() and _events_of(seen, "floor_restored").is_empty(), "pending: burnout itself bloomed/restored the room")
	_ok(not g._corruption_adjacent(Vector2i(3, 1)), "pending: ash shields the core")
	# 4. cleanse the ash: the room blooms once and the floor is restored
	seen.append_array(g.step({"type": "cleanse", "target": Vector2i(2, 1)}))
	_ok(_events_of(seen, "cleanse").size() == 2, "pending: %d cleanse events" % _events_of(seen, "cleanse").size())
	_ok(_events_of(seen, "room_bloom").size() == 1, "pending: %d room_bloom events after the ash cleanse" % _events_of(seen, "room_bloom").size())
	_ok(_events_of(seen, "floor_restored").size() == 1, "pending: %d floor_restored events after the ash cleanse" % _events_of(seen, "floor_restored").size())
	_ok(g._count_corruption() == 0 and not g._room_has_corruption(0), "pending: count %d room %s" % [g._count_corruption(), str(g._room_has_corruption(0))])
	# the room blooms exactly once: a later cleanse in the same room adds none
	g.terrain[Vector2i(3, 2)] = {"kind": "goo"}
	var evx: Array = g.step({"type": "cleanse", "target": Vector2i(3, 2)})
	_ok(_events_of(evx, "room_bloom").is_empty(), "pending: room bloomed twice (%s)" % str(evx))
	_ok(_events_of(seen, "illegal").is_empty() and _events_of(seen, "error").is_empty(),
		"pending: %d illegal / %d error events during the run" % [_events_of(seen, "illegal").size(), _events_of(seen, "error").size()])
	print("pending corruption: fire counts for the quota, the room bloom and the floor restore; it never shields the core and is never cleansable")


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


# --- j) loadouts ---------------------------------------------------------------

func _check_loadouts() -> void:
	# default config == tender == STARTING_KIT, byte-identical
	var g0 = Game.new(1)
	_ok(g0.loadout == "tender" and g0.player["kit"] == Content.STARTING_KIT
		and g0.player["kit"] == Content.LOADOUTS["tender"]["kit"], "default loadout: %s %s" % [g0.loadout, str(g0.player["kit"])])
	_ok(Game.new(1, {"loadout": "tender"}).state_hash() == g0.state_hash(), "explicit tender differs from default")
	# every loadout row applies its kit, and only its kit
	for lid in Content.LOADOUTS:
		var g = Game.new(1, {"loadout": lid})
		_ok(g.loadout == lid and g.player["kit"] == Content.LOADOUTS[lid]["kit"],
			"loadout %s: got %s kit %s" % [lid, g.loadout, str(g.player["kit"])])
		_ok(g.snapshot()["loadout"] == lid and g.clone().player["kit"] == Content.LOADOUTS[lid]["kit"], "loadout %s: snapshot/clone" % lid)
		_ok(g.draft_pool == Content.DRAFT_POOL and g.player["hp"] == Content.PLAYER_HP, "loadout %s touched pool or hp" % lid)
	# explicit kit wins over the loadout (sweeps pass {kit, pool})
	var gk = Game.new(1, {"loadout": "spiker", "kit": ["vine_whip", "mycelium_dash"]})
	_ok(gk.player["kit"] == ["vine_whip", "mycelium_dash"] and gk.loadout == "spiker", "explicit kit: %s %s" % [str(gk.player["kit"]), gk.loadout])
	# unknown loadout id warns and plays tender
	var gu = Game.new(1, {"loadout": "no_such_loadout"})
	_ok(gu.loadout == "tender" and gu.player["kit"] == Content.STARTING_KIT, "unknown loadout: %s %s" % [gu.loadout, str(gu.player["kit"])])
	_ok(gu.state_hash() == g0.state_hash(), "unknown loadout differs from default")
	# an unmet requires is still applied by the sim (the profile enforces it)
	var gs = Game.new(1, {"loadout": "skyrunner"})
	_ok(gs.player["kit"] == ["gust", "seed_bomb", "updraft"] and gs.draft_pool == Content.DRAFT_POOL,
		"skyrunner without aeolian: %s pool %d" % [str(gs.player["kit"]), gs.draft_pool.size()])
	# kit_ban applies after the loadout kit is chosen
	var gb = Game.new(1, {"loadout": "tender", "mutators": ["no_lance"]})
	_ok(gb.player["kit"] == ["seed_bomb", "mycelium_dash"] and not gb.draft_pool.has("solar_lance"),
		"no_lance after tender: %s" % str(gb.player["kit"]))
	var gb2 = Game.new(1, {"loadout": "tidewarden", "mutators": ["no_lance"]})
	_ok(gb2.player["kit"] == ["water_jet", "seed_bomb", "mycelium_dash"], "no_lance after tidewarden: %s" % str(gb2.player["kit"]))
	# open_pool: every package id joins the pool, the base pool is unchanged
	var go = Game.new(1, {"mutators": ["open_pool"]})
	var expect_pool: Array = Content.DRAFT_POOL.duplicate()
	for pkg in Content.PACKAGES.keys():
		expect_pool.append_array(Content.PACKAGES[pkg])
	_ok(go.draft_pool == expect_pool, "open_pool pool %s" % str(go.draft_pool))
	_ok(go.player["kit"] == Content.STARTING_KIT and go.loadout == "tender", "open_pool touched the kit")
	# open_pool with a committed package: no duplicate ids
	var gop = Game.new(1, {"mutators": ["open_pool"], "packages": ["aeolian"]})
	_ok(gop.draft_pool.size() == expect_pool.size() and gop.packages == ["aeolian"], "open_pool + aeolian pool %d" % gop.draft_pool.size())
	# open_pool then no_lance: the ban still applies to the widened pool
	var gol = Game.new(1, {"mutators": ["open_pool", "no_lance"]})
	_ok(gol.draft_pool.size() == expect_pool.size() - 1 and not gol.draft_pool.has("solar_lance") and gol.draft_pool.has("gust"),
		"open_pool + no_lance pool %s" % str(gol.draft_pool))
	# the shrine ability stock follows the widened pool: nothing outside it
	var outside := 0
	for s in range(1, 41):
		var gsh = Game.new(s, {"mutators": ["open_pool"]})
		var aid: String = String(gsh.shop.get("ability", ""))
		if aid != "" and not expect_pool.has(aid):
			outside += 1
	_ok(outside == 0, "open_pool shop stock outside the pool: %d" % outside)
	# rng.state after Game.new: identical for every loadout and open_pool
	var mismatches := 0
	for s in range(1, RNG_SEEDS + 1):
		var base_state: int = Game.new(s).rng.state
		for lid in Content.LOADOUTS:
			if Game.new(s, {"loadout": lid}).rng.state != base_state:
				mismatches += 1
		if Game.new(s, {"mutators": ["open_pool"]}).rng.state != base_state:
			mismatches += 1
		if Game.new(s, {"loadout": "skyrunner", "packages": ["aeolian"]}).rng.state != base_state:
			mismatches += 1
	_ok(mismatches == 0, "loadout rng independence: %d mismatches" % mismatches)
	print("loadouts: %d rows apply their kit; explicit kit wins; unknown -> tender; kit_ban after loadout; open_pool %d ids; rng mismatches %d" % [
		Content.LOADOUTS.size(), expect_pool.size(), mismatches])


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


# --- k) Block D1: rng pins and the unchanged cost rule ---------------------------

func _check_d1_rng_pins() -> void:
	var moved := 0
	for i in range(RNG_STATE_BUMP8.size()):
		var s := i + 1
		var st: int = Game.new(s).rng.state
		if st != int(RNG_STATE_BUMP8[i]):
			moved += 1
			if moved <= 3:
				failures.append("rng pin: seed %d state %d, bump-8 tree had %d" % [s, st, int(RNG_STATE_BUMP8[i])])
	_ok(RNG_STATE_BUMP8.size() == RNG_SEEDS, "rng pins cover %d seeds" % RNG_SEEDS)
	_ok(moved == 0, "rng.state after Game.new matches the bump-8 tree: %d of %d seeds moved" % [moved, RNG_STATE_BUMP8.size()])
	print("rng pins: %d seeds, %d moved" % [RNG_STATE_BUMP8.size(), moved])


## ability_cost per row, on and off growth, against the pre-D1 formula: the
## surge's stat half never prices anything, so grow_spike / water_jet /
## seed_bomb+ stay 1 on growth and sun_flare(+) keeps its 2 -> 1 discount.
func _check_d1_ability_cost() -> void:
	var g = Game.new(1)
	var p: Vector2i = g.player["pos"]
	var bad: Array = []
	for aid in Content.ABILITIES:
		var base := int(Content.ABILITIES[aid]["cost"])
		g.terrain.erase(p)
		if g.ability_cost(aid) != base:
			bad.append("%s off=%d" % [aid, g.ability_cost(aid)])
		g.terrain[p] = {"kind": "growth"}
		var want: int = maxi(1, base - 1) if base >= 2 else base
		if g.ability_cost(aid) != want:
			bad.append("%s on=%d want %d" % [aid, g.ability_cost(aid), want])
	g.terrain.erase(p)
	_ok(bad.is_empty(), "ability_cost unchanged for every row on/off growth: %s" % str(bad))
	# the surged cost-1 rows and sun_flare(+) named: 1 / 1 and 2 / 1
	g.terrain[p] = {"kind": "growth"}
	_ok(g.ability_cost("grow_spike") == 1 and g.ability_cost("water_jet") == 1 and g.ability_cost("seed_bomb+tangle") == 1
		and g.ability_cost("sun_flare") == 1 and g.ability_cost("sun_flare+corona") == 1 and g.ability_cost("seed_bomb") == 1,
		"on growth: stat-surged cost-1 rows stay 1, cost-2 rows drop to 1")
	g.terrain.erase(p)
	_ok(g.ability_cost("grow_spike") == 1 and g.ability_cost("water_jet") == 1 and g.ability_cost("sun_flare") == 2 and g.ability_cost("seed_bomb") == 2,
		"off growth: base costs")
	# the one cost-delta read (Game._surge_cost_delta): no dict -> the default
	# -1; an explicit dict spells its own delta; a stat-only dict moves no price
	# and still surges on growth through its stat half
	var no_dict := {"cost": 2, "effects": [{"op": "damage", "dmg": 1}]}
	var spelled := {"cost": 2, "effects": [{"op": "damage", "dmg": 1}], "surge": {"cost": -1, "dmg": 1}}
	var stat_only := {"cost": 2, "effects": [{"op": "damage", "dmg": 1}], "surge": {"dmg": 1}}
	_ok(g._surge_cost_delta(no_dict) == -1 and g._surge_cost_delta(spelled) == -1 and g._surge_cost_delta(stat_only) == 0,
		"surge cost delta: default -1 without a dict, spelled -1, 0 for a stat-only dict")
	g.terrain[p] = {"kind": "growth"}
	_ok(g._surges(no_dict) and g._surges(spelled) and g._surges(stat_only),
		"on growth all three surge (the stat-only row through its stat half)")
	_ok(not g._surges({"cost": 1, "effects": [{"op": "damage", "dmg": 1}]}),
		"a cost-1 row with no dict never surges")
	g.terrain.erase(p)
	print("D1 ability_cost: %d rows checked on and off growth" % Content.ABILITIES.size())


# --- l) Block D2: the shrine reroll ------------------------------------------------

## A shrine game with a fat purse, standing on the shrine.
static func _shrine_game(seed_v: int, extra: Dictionary = {}) -> Game:
	# the reroll is a mutator switch: the fixture turns it on; a case that
	# passes its own "mutators" overrides this
	var cfg := {"bloom": 40, "mutators": ["spinning_shrine"]}
	for k in extra:
		cfg[k] = extra[k]
	var g = Game.new(seed_v, cfg)
	g.player["pos"] = g.map["shrine"]
	return g


## One illegal reroll attempt: exactly one illegal event, nothing moves.
func _assert_illegal_reroll(g, label: String) -> void:
	var shop_before: Dictionary = g.shop.duplicate(true)
	var bloom_before: int = g.bloom
	var charge_before: int = g.player["charge"]
	var rng_before: int = g.rng.state
	# the illegal event itself lands in recent_events, so compare the
	# snapshot with the event log stripped
	var snap_before: Dictionary = g.snapshot()
	snap_before.erase("events")
	_ok(not _has_action(g.legal_actions(), "reroll"), "reroll %s: still legal" % label)
	var evs: Array = g.step({"type": "reroll"})
	var ill: Array = _events_of(evs, "illegal")
	_ok(ill.size() == 1 and String(ill[0].get("action", "")) == "reroll" and _events_of(evs, "reroll").is_empty(),
		"reroll %s: events %s" % [label, str(evs)])
	var snap_after: Dictionary = g.snapshot()
	snap_after.erase("events")
	_ok(g.shop == shop_before and g.bloom == bloom_before and g.player["charge"] == charge_before
			and g.rng.state == rng_before and str(snap_after) == str(snap_before),
		"reroll %s: an illegal reroll changed state" % label)


func _check_reroll_legality() -> void:
	# the switch off (default config): a stocked counter and a full purse on
	# the shrine still list no reroll, and the derived rerolls_left reads 0
	var g0 = _shrine_game(1, {"mutators": []})
	_assert_illegal_reroll(g0, "mutator off")
	_ok(int(g0.snapshot()["shop"].get("rerolls_left", -1)) == 0 and g0.snapshot()["shop"].has("reroll_price"),
		"reroll mutator off: snapshot shop %s" % str(g0.snapshot()["shop"]))
	# off the shrine
	var g = Game.new(1, {"bloom": 40, "mutators": ["spinning_shrine"]})
	if g.player["pos"] == g.map["shrine"]:
		g.player["pos"] = g.map["start"] + Vector2i(0, 0)
	_ok(g.player["pos"] != g.map["shrine"], "reroll fixture: start is the shrine")
	_assert_illegal_reroll(g, "off shrine")
	# on the shrine, fresh stock: legal
	g.player["pos"] = g.map["shrine"]
	_ok(_has_action(g.legal_actions(), "reroll"), "reroll: not legal on a fresh stocked shrine")
	# no re-drawable slot left (heal / press / forge only)
	var g2 = _shrine_game(1)
	g2.shop.erase("ability")
	g2.shop.erase("grafts")
	g2.shop.erase("item")
	_ok(g2.shop.get("heal", false) and g2.shop.get("press", false) and g2.shop.get("forge", false), "reroll fixture: services gone")
	_assert_illegal_reroll(g2, "no re-drawable slot")
	# cap reached
	var g3 = _shrine_game(1)
	g3.shop["rerolls"] = Content.SHOP_REROLL_CAP
	_assert_illegal_reroll(g3, "cap reached")
	# short purse: one under the price
	var g4 = _shrine_game(1)
	g4.bloom = g4.shop_cost("reroll") - 1
	_assert_illegal_reroll(g4, "short purse")
	g4.bloom = g4.shop_cost("reroll")
	_ok(_has_action(g4.legal_actions(), "reroll"), "reroll: exact price not legal")
	# boarded (shop: false) - the shop is {} and the snapshot carries no reroll keys
	var g5 = _shrine_game(1, {"mutators": ["spinning_shrine", "boarded"]})
	_assert_illegal_reroll(g5, "boarded")
	var s5: Dictionary = g5.snapshot()["shop"]
	_ok(s5.is_empty(), "reroll boarded: snapshot shop %s" % str(s5))
	# draft phase: the step is refused by the phase gate, not by the reroll
	var g6 = _shrine_game(1)
	g6.phase = "draft"
	g6.draft_offers = ["vine_whip"]
	var evs6: Array = g6.step({"type": "reroll"})
	_ok(not _events_of(evs6, "illegal").is_empty() and int(g6.shop["rerolls"]) == 0
			and not _has_action(g6.legal_actions(), "reroll"),
		"reroll in draft phase: %s" % str(evs6))
	# a legal reroll costs bloom, no charge, and keeps the shop open
	var g7 = _shrine_game(1)
	var b7: int = g7.bloom
	var c7: int = g7.player["charge"]
	var evs7: Array = g7.step({"type": "reroll"})
	var rev: Array = _events_of(evs7, "reroll")
	_ok(rev.size() == 1 and int(rev[0]["n"]) == 1 and int(rev[0]["cost"]) == Content.SHOP_COSTS["reroll"]
			and _events_of(evs7, "illegal").is_empty(),
		"reroll: events %s" % str(evs7))
	_ok(g7.bloom == b7 - Content.SHOP_COSTS["reroll"] and g7.player["charge"] == c7 and int(g7.shop["rerolls"]) == 1
			and g7.phase == "play" and not g7.over,
		"reroll: bloom %d -> %d charge %d -> %d rerolls %s" % [b7, g7.bloom, c7, g7.player["charge"], str(g7.shop.get("rerolls"))])
	print("reroll legality: mutator off / off shrine / no slot / cap / purse / boarded / draft phase illegal; on shrine under spinning_shrine legal at %d bloom" % Content.SHOP_COSTS["reroll"])


func _check_reroll_price_and_cap() -> void:
	var base: int = Content.SHOP_COSTS["reroll"]
	var step: int = Content.SHOP_REROLL_STEP
	var cap: int = Content.SHOP_REROLL_CAP
	_ok(base == 2 and step == 1 and cap == 3, "reroll data: base %d step %d cap %d (spec 2 / 1 / 3)" % [base, step, cap])
	# escalation 2 / 3 / 4 at tier 0, then the cap
	var g = _shrine_game(1)
	var prices: Array = []
	var lefts: Array = []
	var spent := 0
	for i in cap:
		var snap: Dictionary = g.snapshot()["shop"]
		prices.append(int(snap.get("reroll_price", -1)))
		lefts.append(int(snap.get("rerolls_left", -1)))
		_ok(g.shop_cost("reroll") == base + step * i and int(snap["reroll_price"]) == g.shop_cost("reroll"),
			"reroll price at %d spins: %d (snapshot %s)" % [i, g.shop_cost("reroll"), str(snap.get("reroll_price"))])
		var b: int = g.bloom
		var evs: Array = g.step({"type": "reroll"})
		var rev: Array = _events_of(evs, "reroll")
		_ok(rev.size() == 1 and int(rev[0]["cost"]) == base + step * i and int(rev[0]["n"]) == i + 1,
			"reroll %d: event %s" % [i + 1, str(evs)])
		spent += b - g.bloom
	_ok(prices == [2, 3, 4] and lefts == [3, 2, 1], "reroll: prices %s lefts %s" % [str(prices), str(lefts)])
	_ok(spent == 9 and int(g.shop["rerolls"]) == cap and int(g.snapshot()["shop"]["rerolls_left"]) == 0,
		"reroll: spent %d over %d spins, counter %s" % [spent, cap, str(g.shop.get("rerolls"))])
	_assert_illegal_reroll(g, "past the cap")
	# a fresh floor resets the counter
	g._enter_floor(2)
	_ok(int(g.shop.get("rerolls", -1)) == 0 and g.shop_cost("reroll") == base, "reroll: floor 2 counter %s price %d" % [str(g.shop.get("rerolls")), g.shop_cost("reroll")])
	# tier markup on every spin
	var gt = _shrine_game(1, {"tier": GOUGING_TIER})
	var tp: Array = []
	for i in cap:
		tp.append(gt.shop_cost("reroll"))
		gt.step({"type": "reroll"})
	_ok(tp == [3, 4, 5], "reroll gouging prices: %s" % str(tp))
	print("reroll price: %s at tier 0, %s at tier %d, cap %d then illegal, floor entry resets" % [str(prices), str(tp), GOUGING_TIER, cap])


func _check_reroll_redraw() -> void:
	# 1) every slot redrawn excludes its current offer while alternatives exist
	var same_ability := 0
	var same_graft := 0
	var same_item := 0
	var missing := 0
	var bad_cands := 0
	var dup_graft := 0
	for s in range(1, 41):
		var g = _shrine_game(s)
		var before: Dictionary = g.shop.duplicate(true)
		var evs: Array = g.step({"type": "reroll"})
		var rev: Dictionary = _events_of(evs, "reroll")[0]
		if not (rev.has("ability") and rev.has("grafts") and rev.has("item")):
			missing += 1
		if g.shop["ability"] == before["ability"]:
			same_ability += 1
		if g.shop["item"] == before["item"]:
			same_item += 1
		var gr: Array = g.shop["grafts"]
		if gr.size() != 2 or gr[0] == gr[1]:
			dup_graft += 1
		for gid in gr:
			if before["grafts"].has(gid):
				same_graft += 1
		# the redraw obeys the stock rule: pool ids not held, unowned grafts, base items
		if not g.draft_pool.has(g.shop["ability"]) or g.player["kit"].has(g.shop["ability"]):
			bad_cands += 1
		# items are not forked: the plain "+" convention holds here
		if String(g.shop["item"]).ends_with("+") or not Content.ITEMS.has(g.shop["item"]):
			bad_cands += 1
		if rev["ability"] != g.shop["ability"] or rev["grafts"] != g.shop["grafts"] or rev["item"] != g.shop["item"]:
			bad_cands += 1
	_ok(missing == 0, "reroll redraw: %d events lacked a redrawn slot key" % missing)
	_ok(same_ability == 0 and same_graft == 0 and same_item == 0,
		"reroll redraw: current offer kept with alternatives (ability %d, graft %d, item %d)" % [same_ability, same_graft, same_item])
	_ok(dup_graft == 0 and bad_cands == 0, "reroll redraw: %d bad graft pairs, %d candidate-rule violations" % [dup_graft, bad_cands])
	# 2) no alternative: a pool of exactly one ability keeps the offer and the
	#    slot is not redrawn; a graft list with one candidate likewise
	var all_but_last: Array = Content.GRAFTS.keys().slice(0, Content.GRAFTS.size() - 1)
	var last: String = Content.GRAFTS.keys()[Content.GRAFTS.size() - 1]
	var g1 = _shrine_game(3, {"pool": ["vine_whip"], "grafts": all_but_last})
	_ok(g1.shop.get("ability", "") == "vine_whip" and g1.shop.get("grafts", []) == [last],
		"reroll fixture: shop %s" % str(g1.shop))
	var item_before: String = g1.shop["item"]
	var evs1: Array = g1.step({"type": "reroll"})
	var rev1: Dictionary = _events_of(evs1, "reroll")[0]
	_ok(g1.shop["ability"] == "vine_whip" and g1.shop["grafts"] == [last]
			and not rev1.has("ability") and not rev1.has("grafts") and rev1.has("item") and g1.shop["item"] != item_before
			and int(rev1["n"]) == 1 and int(g1.shop["rerolls"]) == 1,
		"reroll with no alternative: shop %s event %s" % [str(g1.shop), str(rev1)])
	# 3) bought slots stay bought: buy a graft, reroll -> no grafts key, ability redrawn
	var g2 = _shrine_game(2)
	g2.step({"type": "buy", "item": "graft", "pick": 0})
	_ok(not g2.shop.has("grafts") and g2.player["grafts"].size() == 1, "reroll fixture: graft buy %s" % str(g2.shop))
	var a_before: String = g2.shop["ability"]
	var evs2: Array = g2.step({"type": "reroll"})
	var rev2: Dictionary = _events_of(evs2, "reroll")[0]
	_ok(not g2.shop.has("grafts") and not rev2.has("grafts") and rev2.has("ability") and g2.shop["ability"] != a_before
			and not g2.snapshot()["shop"].has("graft_prices"),
		"reroll after a graft buy: shop %s event %s" % [str(g2.shop), str(rev2)])
	# the redrawn graft counter never offers the graft just bought either
	var g2b = _shrine_game(2)
	var bought: String = g2b.shop["grafts"][0]
	g2b.step({"type": "buy", "item": "graft", "pick": 0})
	g2b.step({"type": "reroll"})
	_ok(g2b.player["grafts"] == [bought] and not g2b.shop.has("grafts"), "reroll: bought graft %s reappeared" % bought)
	# ability and item bought: only the graft counter spins
	var g3 = _shrine_game(2, {"kit": ["solar_lance", "seed_bomb", "mycelium_dash"]})
	g3.step({"type": "buy", "item": "ability"})
	g3.step({"type": "buy", "item": "item"})
	_ok(not g3.shop.has("ability") and not g3.shop.has("item") and g3.shop.has("grafts"), "reroll fixture: shop %s" % str(g3.shop))
	var evs3: Array = g3.step({"type": "reroll"})
	var rev3: Dictionary = _events_of(evs3, "reroll")[0]
	_ok(not g3.shop.has("ability") and not g3.shop.has("item") and rev3.has("grafts") and not rev3.has("ability") and not rev3.has("item"),
		"reroll with ability/item bought: shop %s event %s" % [str(g3.shop), str(rev3)])
	# 4) heal / press / forge untouched, a used forge stays used
	var g4 = _shrine_game(2, {"kit": ["solar_lance", "seed_bomb", "mycelium_dash"]})
	g4.step({"type": "upcycle_ability", "keep": 0, "scrap": 1})
	_ok(not g4.shop.has("forge"), "reroll fixture: forge %s" % str(g4.shop))
	g4.step({"type": "reroll"})
	_ok(g4.shop.get("heal", false) == true and g4.shop.get("press", false) == true and not g4.shop.has("forge"),
		"reroll: services moved: %s" % str(g4.shop))
	var g4b = _shrine_game(2)
	g4b.step({"type": "reroll"})
	_ok(g4b.shop.get("heal", false) == true and g4b.shop.get("press", false) == true and g4b.shop.get("forge", false) == true,
		"reroll: fresh services moved: %s" % str(g4b.shop))
	# 5) rng.state untouched; the same seed and floor redraw identically on two fresh games
	var mismatch := 0
	var rng_moved := 0
	for s in range(1, 31):
		var ga = _shrine_game(s)
		var gb = _shrine_game(s)
		var st: int = ga.rng.state
		var ea: Array = ga.step({"type": "reroll"})
		var eb: Array = gb.step({"type": "reroll"})
		if ga.rng.state != st:
			rng_moved += 1
		if ga.shop != gb.shop or _events_of(ea, "reroll") != _events_of(eb, "reroll"):
			mismatch += 1
		ga.step({"type": "reroll"})
		gb.step({"type": "reroll"})
		if ga.rng.state != st:
			rng_moved += 1
		if ga.shop != gb.shop:
			mismatch += 1
	_ok(rng_moved == 0, "reroll: main rng moved on %d rerolls" % rng_moved)
	_ok(mismatch == 0, "reroll: %d seeds redrew differently on two fresh games" % mismatch)
	# 6) reroll 1 and reroll 2 use different generators: the tags seed different streams
	var same_stream := 0
	for s in range(1, 51):
		var g = Game.new(s)
		if g._side_rng("reroll0_ability").randi() == g._side_rng("reroll1_ability").randi() \
				or g._side_rng("reroll0_graft").randi() == g._side_rng("reroll1_graft").randi() \
				or g._side_rng("reroll0_item").randi() == g._side_rng("reroll1_item").randi() \
				or g._side_rng("reroll0_ability").randi() == g._side_rng("shop_ability").randi():
			same_stream += 1
	_ok(same_stream == 0, "reroll: %d of 50 seeds had reroll0 / reroll1 / shop_ability generators agree on their first draw" % same_stream)
	# and the second spin's draw is reproducible from its own generator: a
	# fresh game with rerolls forced to 1 draws what the second spin drew
	var gx = _shrine_game(4)
	gx.step({"type": "reroll"})
	var first: Dictionary = gx.shop.duplicate(true)
	gx.step({"type": "reroll"})
	var gy = _shrine_game(4)
	gy.shop = first.duplicate(true)
	gy.step({"type": "reroll"})
	_ok(gy.shop == gx.shop, "reroll: second spin not reproducible from rerolls=1 (%s vs %s)" % [str(gy.shop), str(gx.shop)])
	print("reroll redraw: 40 seeds exclude the offer, one-candidate slots keep it, bought slots stay closed, services untouched, rng fixed, %d/50 tag collisions" % same_stream)


func _check_reroll_state() -> void:
	# clone() copies the counter; state_hash moves with it and not with the derived keys
	var g = _shrine_game(5)
	var h0 := g.state_hash()
	g.step({"type": "reroll"})
	var h1 := g.state_hash()
	_ok(h1 != h0, "reroll: state_hash did not move on a reroll")
	var c = g.clone()
	_ok(int(c.shop["rerolls"]) == 1 and c.shop == g.shop and c.state_hash() == h1 and c.shop_cost("reroll") == g.shop_cost("reroll"),
		"reroll: clone shop %s vs %s" % [str(c.shop), str(g.shop)])
	c.step({"type": "reroll"})
	_ok(int(c.shop["rerolls"]) == 2 and int(g.shop["rerolls"]) == 1, "reroll: clone shares the counter with its source")
	# the counter alone moves the hash (same stock, rerolls 0 -> 1)
	var g2 = _shrine_game(5)
	var h2 := g2.state_hash()
	g2.shop["rerolls"] = 1
	_ok(g2.state_hash() != h2, "reroll: state_hash ignored shop.rerolls")
	g2.shop["rerolls"] = 0
	_ok(g2.state_hash() == h2, "reroll: state_hash did not return with the counter")
	# derived keys: present in the snapshot, absent from the stored shop, out of the hash
	var snap: Dictionary = g2.snapshot()["shop"]
	_ok(snap.has("reroll_price") and snap.has("rerolls_left") and not g2.shop.has("reroll_price") and not g2.shop.has("rerolls_left"),
		"reroll: derived keys stored or missing: snapshot %s stored %s" % [str(snap), str(g2.shop)])
	_ok(int(snap["reroll_price"]) == g2.shop_cost("reroll") and int(snap["rerolls_left"]) == Content.SHOP_REROLL_CAP - int(g2.shop["rerolls"]),
		"reroll: derived values %s / %s" % [str(snap["reroll_price"]), str(snap["rerolls_left"])])
	var view: Dictionary = g2.snapshot()
	view["shop"] = g2.shop
	_ok(g2.state_hash() == str(view).sha256_text() and g2.state_hash() != str(g2.snapshot()).sha256_text(),
		"reroll: state_hash saw a derived key")
	# a tier change moves reroll_price but not the hash of the stored shop view
	var gt = _shrine_game(5, {"tier": GOUGING_TIER})
	_ok(int(gt.snapshot()["shop"]["reroll_price"]) == Content.SHOP_COSTS["reroll"] + 1, "reroll: gouging snapshot price %s" % str(gt.snapshot()["shop"].get("reroll_price")))
	print("reroll state: clone copies rerolls, hash follows the counter, derived keys reroll_price / rerolls_left stay out")


# --- m) Block D3: no new main-rng draw ------------------------------------------

## Two-corridor room (tests/test_grammar.gd DETOUR_4): @ (2, 1), fire at (5, 1)
## on the short row, an avoider spawned at (9, 1) so the search has to relax
## nodes to find the detour.
const D3_ROOM := [
	"###########",
	"#.@..F...E#",
	"##.######.#",
	"#.........#",
	"###########",
]


func _check_d3_rng_untouched() -> void:
	# 1) the search on a board where fire and an avoider meet, and where they do not
	var gen := _gen(D3_ROOM)
	gen["terrain"][Vector2i(5, 1)] = {"kind": "fire", "ttl": 99, "by": "env"}
	var g = Game.new(1, {"fixed_floor": {"gen": gen, "fdef": {}}, "kit": Content.STARTING_KIT})
	var e = g._spawn("drill_bot", Vector2i(9, 1))
	var hulk = g._spawn("welded_hulk", Vector2i(1, 3))  # the dead-end tile: off the detour
	var st: int = g.rng.state
	var step_a: Vector2i = g._chase_step(e)
	var step_h: Vector2i = g._chase_step(hulk)
	_ok(g.rng.state == st, "_chase_step (avoider through a detour, hulk on a plain board) leaves rng.state alone")
	_ok(step_a == Vector2i(9, 2) and step_h == Vector2i(2, 3), "the two chases went where expected: %s %s" % [str(step_a), str(step_h)])
	# 2) a screened gum executed directly: no rng draw (the gum slot draw belongs to _compute_intents, not to the screen)
	var g2 = Game.new(1, {"fixed_floor": {"gen": _gen(D3_ROOM), "fdef": {}}, "kit": Content.STARTING_KIT})
	g2.terrain[Vector2i(3, 1)] = {"kind": "smoke", "ttl": 9}
	var spitter = g2._spawn("tar_spitter", Vector2i(5, 1))
	spitter["intent"] = {"type": "gum", "slot": 0}
	st = g2.rng.state
	g2._step_events = []
	g2._execute_intent(spitter)
	_ok(g2.rng.state == st and _events_of(g2._step_events, "screened").size() == 1 and _events_of(g2._step_events, "gummed").is_empty(),
		"a screened gum executes without an rng draw: %s" % str(g2._step_events))
	# 3) the D3-swapped sim (RefGame) under the optimizer reproduces the recorded floor-entry states
	var seeds_checked := 0
	var floors_checked := 0
	var moved := 0
	for i in range(RNG_FLOOR_ENTRY_BUMP13.size()):
		var s := i + 1
		var rg = RefGame.new(s)
		var bot = Roster.make("optimizer", s)
		if bot.has_method("set_sim"):
			bot.set_sim(rg)
		var states: Array = [rg.rng.state]
		var last_floor: int = rg.floor_num
		var actions := 0
		while not rg.over and actions < Sweep.MAX_ACTIONS and rg.total_turns < Sweep.MAX_TURNS:
			var act: Dictionary = bot.choose_action(rg.snapshot(), rg.legal_actions())
			rg.step(act)
			actions += 1
			if rg.floor_num != last_floor:
				last_floor = rg.floor_num
				states.append(rg.rng.state)
		seeds_checked += 1
		var want: Array = RNG_FLOOR_ENTRY_BUMP13[i]
		if states.size() != want.size():
			moved += 1
			failures.append("floor-entry pins: seed %d reached %d floors, the pinned run reached %d" % [s, states.size(), want.size()])
			continue
		for f in range(states.size()):
			floors_checked += 1
			if int(states[f]) != int(want[f]):
				moved += 1
				if moved <= 3:
					failures.append("floor-entry pins: seed %d floor %d state %d, pinned %d" % [s, f + 1, int(states[f]), int(want[f])])
	_ok(moved == 0, "RefGame optimizer run: rng.state at every floor entry matches the bump-13 pins (%d seeds, %d floor entries, %d moved)" % [seeds_checked, floors_checked, moved])
	_ok(RefGame.new(1).rng.state == int(RNG_STATE_BUMP8[0]) and Game.new(1).rng.state == int(RNG_STATE_BUMP8[0]), "RefGame and Game share the Game.new pins")
	print("d3 rng: floor-entry pins %d seeds / %d entries, %d moved" % [seeds_checked, floors_checked, moved])


# --- Block D6: the forge branch of legal_actions -------------------------------
## The shrine forge now offers BOTH variants of the kept ability, so the
## action carries a `variant` index and legal_actions lists one action per
## (keep, scrap, variant) triple. Everything else about the branch is
## unchanged: shop-gated, priced through shop_cost("forge") with the tier
## markup, once per floor, never scraps a mobility ability, needs a kit of 2+,
## and every listed action must be affordable.
func _check_d6_forge_actions() -> void:
	var kit := ["solar_lance", "seed_bomb", "mycelium_dash"]
	var g = Game.new(1, {"bloom": 20, "kit": kit})
	g.player["pos"] = g.map["shrine"]
	var acts: Array = g.legal_actions()
	var triples := {}
	var bad_scrap := 0
	var bad_keep := 0
	var bad_index := 0
	for a in acts:
		if String(a.get("type", "")) != "upcycle_ability":
			continue
		var keep := int(a["keep"])
		var scrap := int(a["scrap"])
		var v := int(a.get("variant", -1))
		triples["%d/%d/%d" % [keep, scrap, v]] = true
		if String(kit[scrap]) == "mycelium_dash":
			bad_scrap += 1
		if Content.is_upgrade(String(kit[keep])) or Content.variants_of(String(kit[keep])).is_empty():
			bad_keep += 1
		if v < 0 or v >= Content.variants_of(String(kit[keep])).size():
			bad_index += 1
	_ok(triples.size() == 8 and bad_scrap == 0 and bad_keep == 0 and bad_index == 0,
		"D6 forge branch: %d triples, %d mobility scraps, %d bad keeps, %d bad indices" % [
			triples.size(), bad_scrap, bad_keep, bad_index])
	# every listed triple is actually legal (nothing illegal is offered)
	var accepted := 0
	for key in triples:
		var parts: PackedStringArray = String(key).split("/")
		var gg = Game.new(1, {"bloom": 20, "kit": kit})
		gg.player["pos"] = gg.map["shrine"]
		var evs: Array = gg.step({"type": "upcycle_ability", "keep": int(parts[0]), "scrap": int(parts[1]), "variant": int(parts[2])})
		if _events_of(evs, "illegal").is_empty() and not _events_of(evs, "upcycle_ability").is_empty():
			accepted += 1
	_ok(accepted == 8, "D6 forge branch: %d / 8 listed triples resolve" % accepted)
	# price: still one forge price, whichever variant (a fork is a choice, not
	# a price tier), and the tier markup still applies
	var before: int = g.bloom
	g.step({"type": "upcycle_ability", "keep": 0, "scrap": 1, "variant": 1})
	_ok(g.bloom == before - Content.SHOP_COSTS["forge"], "D6 forge branch: variant 1 costs the plain forge price (%d)" % (before - g.bloom))
	_ok(not _has_action(g.legal_actions(), "upcycle_ability"), "D6 forge branch: still once per floor")
	var gt = Game.new(1, {"bloom": 20, "kit": kit, "tier": 5})
	gt.player["pos"] = gt.map["shrine"]
	var bt: int = gt.bloom
	gt.step({"type": "upcycle_ability", "keep": 0, "scrap": 1, "variant": 1})
	_ok(gt.bloom == bt - Content.SHOP_COSTS["forge"] - 1, "D6 forge branch: the tier markup still applies (%d)" % (bt - gt.bloom))
	# a purse that covers nothing lists nothing
	var gp = Game.new(1, {"bloom": 0, "kit": kit})
	gp.player["pos"] = gp.map["shrine"]
	_ok(not _has_action(gp.legal_actions(), "upcycle_ability"), "D6 forge branch: an empty purse lists no forge action")
	# a kit whose only upgradable entry is already a variant lists nothing
	var gu = Game.new(1, {"bloom": 20, "kit": ["solar_lance+noon", "seed_bomb+tangle"]})
	gu.player["pos"] = gu.map["shrine"]
	_ok(not _has_action(gu.legal_actions(), "upcycle_ability"), "D6 forge branch: an all-variant kit lists no forge action")
	# the forge listing never touches the rng
	var gr = Game.new(1, {"bloom": 20, "kit": kit})
	gr.player["pos"] = gr.map["shrine"]
	var st: int = gr.rng.state
	gr.legal_actions()
	gr.step({"type": "upcycle_ability", "keep": 1, "scrap": 0, "variant": 1})
	_ok(gr.rng.state == st and gr.player["kit"] == ["seed_bomb+reclaim", "mycelium_dash"],
		"D6 forge branch: listing and forging spend no main-rng draw: %s" % str(gr.player["kit"]))
	print("d6 forge: %d (keep, scrap, variant) triples on a 3-ability kit, all legal, one price" % triples.size())
