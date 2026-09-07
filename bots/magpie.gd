extends "res://bots/optimizer.gd"
## Magpie persona: greedy explorer. Plays the optimizer's competent game, but
## buys everything, cleanses with enemies looming, and routes to every
## corrupted tile before the stairs while the light holds. Measures what
## greed costs against the smog clock.


func get_bot_name() -> String:
	return "magpie"


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

	# buy everything affordable, always
	if by.has("buy"):
		var deal := _magpie_buy(by["buy"], snap)
		if not deal.is_empty():
			return deal

	var threat := _threat_tiles(snap)

	# greedy cleanse: enemies may loom, but nothing adjacent and no incoming hit
	if by.has("cleanse") and _nearest_enemy_dist(snap) > 1 and not threat.has(ppos):
		return by["cleanse"][0]

	# harvest route: nearest corrupted tile while the light holds and it's quiet
	if by.has("move") and snap["dim"] < 2 and _enemies_within(snap, 3) == 0:
		var goal := _nearest_corruption(snap)
		if goal != Vector2i(-1, -1):
			var step := _bfs_step(snap, true, threat, goal)
			if step == Vector2i.ZERO:
				step = _bfs_step(snap, false, threat, goal)
			if step != Vector2i.ZERO:
				for a in by["move"]:
					if a["dir"] == step:
						return a

	# greedy shopping: the optimizer only shops on the way to the stairs, but
	# a magpie with bloom in its pouch always detours for shiny things
	if by.has("move") and snap["dim"] < 2:
		var shrine: Vector2i = snap["map"]["shrine"]
		if shrine != Vector2i(-1, -1) and ppos != shrine:
			# grafts are priced per offer (shop.graft_prices, 3 to 8 bloom):
			# the cheapest one on the counter is what makes the detour pay
			var worth: bool = _graft_worth_detour(snap)
			if snap["shop"].has("ability") and snap["bloom"] >= 4:
				worth = true
			if snap["shop"].get("heal", false) and snap["bloom"] >= 3 and snap["player"]["hp"] < snap["player"]["max_hp"]:
				worth = true
			if worth:
				var sstep := _bfs_step(snap, true, threat, shrine)
				if sstep == Vector2i.ZERO:
					sstep = _bfs_step(snap, false, threat, shrine)
				if sstep != Vector2i.ZERO:
					for a in by["move"]:
						if a["dir"] == sstep:
							return a

	# otherwise: the optimizer's full ladder (fight, dodge, heal, stairs)
	return super.choose_action(snap, legal)


## Greedy shrine: heal, then a graft, then an ability - everything affordable
## on the counter, in that order. Empty dict when nothing is affordable.
func _magpie_buy(buys: Array, snap: Dictionary) -> Dictionary:
	for a in buys:
		if a["item"] == "heal":
			return a
	# the graft pick is the parent's tag-fit ranking (optimizer._first_graft):
	# best overlap between the offer's Content.GRAFTS tags and the tags of the
	# abilities in hand, ties to the lowest offer index
	var graft := _first_graft(buys, snap)
	if not graft.is_empty():
		return graft
	for a in buys:
		if a["item"] == "ability":
			return a
	return {}


func _nearest_corruption(snap: Dictionary) -> Vector2i:
	var ppos: Vector2i = snap["player"]["pos"]
	var best := Vector2i(-1, -1)
	var best_d := 9999
	for t in snap["terrain"].keys():
		var k: String = snap["terrain"][t]["kind"]
		if not CONTENT.is_corruption(k):
			continue
		var d: int = absi(t.x - ppos.x) + absi(t.y - ppos.y)
		if k == "rich_goo":
			d -= 4  # rich veins pull harder
		if d < best_d:
			best_d = d
			best = t
	return best
