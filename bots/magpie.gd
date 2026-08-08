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
		for item in ["heal", "graft", "ability"]:
			for a in by["buy"]:
				if a["item"] == item:
					return a

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

	# otherwise: the optimizer's full ladder (fight, dodge, heal, shop, stairs)
	return super.choose_action(snap, legal)


func _nearest_corruption(snap: Dictionary) -> Vector2i:
	var ppos: Vector2i = snap["player"]["pos"]
	var best := Vector2i(-1, -1)
	var best_d := 9999
	for t in snap["terrain"].keys():
		var k: String = snap["terrain"][t]["kind"]
		if k != "oil" and k != "goo" and k != "rich_goo":
			continue
		var d: int = absi(t.x - ppos.x) + absi(t.y - ppos.y)
		if k == "rich_goo":
			d -= 4  # rich veins pull harder
		if d < best_d:
			best_d = d
			best = t
	return best
