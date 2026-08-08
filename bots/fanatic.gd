extends "res://bots/optimizer.gd"
## Build Fanatic persona: commits to one niche build archetype per run and
## forces it at any cost - drafts ONLY abilities in the build (skipping
## otherwise), drops off-build abilities first, and leads with build
## abilities in combat. Measures whether every archetype is actually viable.

const BUILDS := {
	"pyro": ["solar_lance", "sun_flare"],
	"gardener": ["seed_bomb", "overgrowth", "grow_spike"],
	"turtle": ["thorn_shield", "root_wall", "sap_snare", "grow_spike"],
	"shover": ["water_jet", "vine_whip", "pollen_burst", "solar_lance"],
}

var build := "pyro"


func get_bot_name() -> String:
	return "fanatic"


func get_build() -> String:
	return build


func reset(seed_v: int) -> void:
	super.reset(seed_v)
	var names: Array = BUILDS.keys()
	build = names[seed_v % names.size()]


func _wants(aid: String) -> bool:
	return BUILDS[build].has(aid.trim_suffix("+"))


func choose_action(snap: Dictionary, legal: Array) -> Dictionary:
	if snap["phase"] == "draft":
		return _fanatic_draft(snap, legal)
	var by := {}
	for a in legal:
		var k: String = a["type"]
		if not by.has(k):
			by[k] = []
		by[k].append(a)

	# shop: only build abilities; heals and grafts are always fine
	if by.has("buy"):
		for a in by["buy"]:
			if a["item"] == "heal":
				return a
		for a in by["buy"]:
			if a["item"] == "graft":
				return a
		for a in by["buy"]:
			if a["item"] == "ability" and _wants(String(snap["shop"].get("ability", ""))):
				return a

	# a shielded boss core can't be fought through the build - defer to the
	# parent ladder, which clears the clogged vents first
	var gated_boss := false
	for e in snap["enemies"]:
		if e["traits"].has("boss") and e["hp"] <= 6 and not _growth_adj_to(snap, e["pos"]):
			gated_boss = true
	if not gated_boss:
		# lead with the build, but only on sensible triggers - fanatic about
		# WHAT it casts, not about casting into a wall
		var lead = _build_cast(snap, by)
		if lead != null:
			return lead

	return super.choose_action(snap, legal)


func _build_cast(snap: Dictionary, by: Dictionary) -> Variant:
	if not by.has("ability"):
		return null
	var near2 := _enemies_within(snap, 2)
	var near3 := _enemies_within(snap, 3)
	var ppos: Vector2i = snap["player"]["pos"]
	for a in by["ability"]:
		var aid := _kit_id(snap, a["slot"])
		if not _wants(aid):
			continue
		match aid:
			"solar_lance":
				if _lance_hits(snap, a["target"]):
					return a
			"sun_flare", "pollen_burst":
				if near2 >= 1:
					return a
			"grow_spike", "vine_whip":
				return a
			"seed_bomb":
				if near3 >= 1 and not _growth_adj_to(snap, ppos):
					return a
			"overgrowth":
				if near3 >= 1:
					return a
			"thorn_shield":
				if snap["player"]["shield"] == 0 and near3 >= 1:
					return a
			"root_wall", "sap_snare":
				if near3 >= 1 and near2 == 0:
					return a
			"water_jet":
				if _enemy_at(snap, ppos + a["target"]) != null:
					return a
	return null


func _fanatic_draft(snap: Dictionary, legal: Array) -> Dictionary:
	var offers: Array = snap["draft_offers"]
	var pick := -1
	for i in offers.size():
		if _wants(String(offers[i])):
			pick = i
			break
	if pick == -1:
		return legal[legal.size() - 1]  # nothing on-build: skip, fanatically
	var candidates: Array = []
	for a in legal:
		if int(a.get("pick", -2)) == pick:
			candidates.append(a)
	if candidates.is_empty():
		return legal[legal.size() - 1]
	if candidates.size() == 1:
		return candidates[0]
	# kit full: drop off-build first (never mobility), else least-used
	var kit: Array = snap["player"]["kit"]
	var uses: Dictionary = snap["player"]["uses"]
	var best_a: Dictionary = candidates[0]
	var best_key := 999999
	for a in candidates:
		var slot: int = a["drop"]
		var aid: String = String(kit[slot]).trim_suffix("+")
		if aid == "mycelium_dash":
			continue
		var key: int = uses.get(kit[slot], 0) + (0 if not _wants(aid) else 100000)
		if key < best_key:
			best_key = key
			best_a = a
	return best_a
