extends "res://bots/optimizer.gd"
## Build Fanatic persona: commits to one archetype per run and forces it at
## any cost - drafts ONLY abilities in the build core (skipping otherwise),
## drops off-build abilities first, buys only on-build abilities, and leads
## with build abilities in combat. Measures whether every archetype is
## actually viable. The archetype table is Content.ARCHETYPES (review §6.1,
## §7.2 item 3): the bot reads it, the sim never does.
##
## Build selection: set_build(id) forces an archetype (it survives a later
## reset()); otherwise reset() picks among the four legacy archetypes by
## seed exactly as the original BUILDS dict did. On its first decision the
## bot checks the archetype's required packages against snapshot.packages
## and falls back to the seed's legacy pick when the run cannot offer the
## core - so an unmet requirement degrades to a measurable legacy run
## instead of a run that skips every draft.

const Content := preload("res://sim/content.gd")

## The original four, in the order the old BUILDS dict listed them - the
## `seed % 4` default must keep picking the same build per seed.
const LEGACY_BUILDS := ["pyro", "gardener", "turtle", "shover"]

## Generic-cast op families for core abilities without a hand-tuned trigger.
const SETUP_OPS := ["grow_radius", "grow_wall", "convert_radius", "create_terrain"]
const SELF_BUFF_OPS := ["shield", "thorns", "anchor", "undim"]
const SETUP_COOLDOWN := 6  # the overgrowth homeostasis-loop breaker
const DEF_COOLDOWN := 3  # the thorn_shield corner-camping breaker

var build := "pyro"
var _build_forced := false  # set_build() was called; reset() keeps the build
var _build_checked := false  # first-decision package check done
var _seed_v := 0
var _last_overgrowth := -99
var _last_def_cast := -99


func get_bot_name() -> String:
	return "fanatic"


func get_build() -> String:
	return build


## Force an archetype id from Content.ARCHETYPES. Survives reset(); unknown
## ids are refused with push_error and the current build is kept.
func set_build(id: String) -> void:
	if not Content.ARCHETYPES.has(id):
		push_error("fanatic: unknown archetype '%s' (have: %s)" % [id, ", ".join(Content.ARCHETYPES.keys())])
		return
	build = id
	_build_forced = true
	_build_checked = false


func reset(seed_v: int) -> void:
	super.reset(seed_v)
	_seed_v = seed_v
	if not _build_forced:
		build = _legacy_build(seed_v)
	_build_checked = false
	_last_overgrowth = -99
	_last_def_cast = -99


static func _legacy_build(seed_v: int) -> String:
	return LEGACY_BUILDS[seed_v % LEGACY_BUILDS.size()]


func _core() -> Array:
	return Content.ARCHETYPES[build]["core"]


func _wants(aid: String) -> bool:
	return _core().has(Content.base_id(aid))


## A forced archetype whose required packages are not in this run cannot
## complete its core; fall back to the seed's legacy pick once, on the first
## decision (the snapshot carries the run's packages, the constructor does not).
func _check_requirements(snap: Dictionary) -> void:
	_build_checked = true
	var required: Array = Content.ARCHETYPES[build].get("requires", {}).get("packages", [])
	if required.is_empty():
		return
	var have: Array = snap.get("packages", [])
	for pkg in required:
		if not have.has(pkg):
			build = _legacy_build(_seed_v)
			return


func choose_action(snap: Dictionary, legal: Array) -> Dictionary:
	if not _build_checked:
		_check_requirements(snap)
	if snap["phase"] == "draft":
		return _fanatic_draft(snap, legal)
	# off-build purchase leak (review §7.2 item 3): the parent buys any
	# ability it is offered, so an unwanted shop ability is removed from
	# `legal` before the parent ever sees it. end_turn stays last.
	var shop_aid := String(snap.get("shop", {}).get("ability", ""))
	if shop_aid != "" and not _wants(shop_aid):
		var kept: Array = []
		for a in legal:
			if a["type"] == "buy" and a["item"] == "ability":
				continue
			kept.append(a)
		legal = kept
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
		# graft offer 0: the fanatic has no graft opinion either - the
		# progression review holds any graft weighting until
		# tests/sweep_grafts.gd has run at 30+ seeds
		var graft := _first_graft(by["buy"])
		if not graft.is_empty():
			return graft
		for a in by["buy"]:
			if a["item"] == "ability" and _wants(shop_aid):
				return a

	# fanatic about the build, not suicidal: standing in lethal telegraphed
	# damage routes to the parent's survival gate before any build cast
	var threat := _threat_tiles(snap)
	var ppos: Vector2i = snap["player"]["pos"]
	if threat.has(ppos) and snap["player"]["hp"] + snap["player"]["shield"] <= _incoming_dmg(snap) * 2:
		return super.choose_action(snap, legal)

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
	# Seed on head leads for any build whose core holds both halves of the
	# combo (gardener today): bomb the enemy's own tile so the spike that
	# follows this same turn is both legal and rider-capped. Off-build kits
	# never reach it - _wants gates both ids - and the parent's own
	# seed-on-head branch still covers the generic ladder below.
	if _wants("seed_bomb") and _wants("grow_spike"):
		var head := _seed_on_head(snap, by["ability"])
		if not head.is_empty():
			return head
	# ...and the payoff outbids more setup: once growth is down (usually from
	# the seed above) the spike is the reason it went down, and the lead only
	# pays if the spike lands the same turn instead of a second bomb.
	# _best_spike reads the rider, so it takes the richest target.
	if _wants("grow_spike"):
		var spike_now := _best_spike(snap, by["ability"])
		if not spike_now.is_empty():
			return spike_now
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
			"vine_whip":
				if near2 >= 1:
					return a
			"seed_bomb":
				if near3 >= 1 and not _growth_adj_to(snap, ppos):
					return a
			"overgrowth":
				# cooldown breaks the homeostasis loop: growth healing kept
				# pace with choke damage and runs sat immortal at turn 400
				if near3 >= 1 and int(snap["turn"]) - _last_overgrowth >= SETUP_COOLDOWN:
					_last_overgrowth = int(snap["turn"])
					return a
			"thorn_shield":
				# cooldown between defensive recasts, or the turtle stands in
				# a corner re-shielding forever while growth heals the choke -
				# the last immortal-stall loop. Off-cooldown turns fall through
				# to the parent's pathing, so the turtle actually walks.
				if snap["player"]["shield"] == 0 and near3 >= 1 and int(snap["turn"]) - _last_def_cast >= DEF_COOLDOWN:
					_last_def_cast = int(snap["turn"])
					return a
			"bramble_coat":
				if int(snap["player"].get("thorns_turns", 0)) == 0 and near2 >= 1 and int(snap["turn"]) - _last_def_cast >= DEF_COOLDOWN:
					_last_def_cast = int(snap["turn"])
					return a
			"root_wall", "sap_snare":
				if near3 >= 1 and near2 == 0:
					return a
			"water_jet":
				# shove-and-interrupt is the archetype; the jet also
				# pressure-hits massive targets it cannot move
				for i in range(1, 3):
					if _enemy_at(snap, ppos + a["target"] * i) != null:
						return a
			_:
				if _generic_cast(snap, a, aid, near3):
					return a
	return null


## Trigger for a core ability with no hand-tuned rule above, derived from
## its first effect op and target kind in Content.ABILITIES. Mobility is
## never a build cast (teleport / dash ops move the player, not the fight).
## Returns true when `a` should be cast now; stamps the cooldown it used.
func _generic_cast(snap: Dictionary, a: Dictionary, aid: String, near3: int) -> bool:
	var adef: Dictionary = Content.ABILITIES.get(aid, {})
	if adef.is_empty() or adef.get("effects", []).is_empty():
		return false
	if String(adef.get("role", "")) == "mobility":
		return false
	var eff: Dictionary = adef["effects"][0]
	var op := String(eff["op"])
	var tkind := String(adef["target"])
	var rng_ := int(adef["range"])
	var turn := int(snap["turn"])
	var ppos: Vector2i = snap["player"]["pos"]
	var pl: Dictionary = snap["player"]
	if op == "teleport" or op == "dash_dir":
		return false
	if op.begins_with("aoe_"):
		return _enemies_within(snap, int(eff.get("radius", rng_))) >= 1
	if SETUP_OPS.has(op):
		# setup terrain near a fight, never on top of the same terrain, and
		# on the overgrowth cooldown so it cannot become a stall loop
		if near3 == 0 or turn - _last_overgrowth < SETUP_COOLDOWN:
			return false
		var kind := "growth"
		if op == "grow_wall":
			kind = "roots"
		elif op == "create_terrain":
			kind = String(eff.get("kind", ""))
		if String(snap["terrain"].get(ppos, {}).get("kind", "")) == kind:
			return false
		_last_overgrowth = turn
		return true
	if SELF_BUFF_OPS.has(op):
		if near3 == 0 or turn - _last_def_cast < DEF_COOLDOWN:
			return false
		var useful := false
		match op:
			"shield":
				useful = int(pl["shield"]) == 0
			"thorns":
				useful = int(pl.get("thorns_turns", 0)) == 0
			"anchor":
				useful = int(pl.get("anchor_turns", 0)) == 0
			"undim":
				useful = int(snap.get("dim", 0)) >= 1
		if not useful:
			return false
		_last_def_cast = turn
		return true
	# damage / displacement family: cast where the sim says a target exists
	match tkind:
		"enemy", "enemy_line", "enemy_near_growth":
			return true  # the target is an enemy tile the sim already validated
		"dir":
			var dir: Vector2i = a["target"]
			for i in range(1, rng_ + 1):
				if _enemy_at(snap, ppos + dir * i) != null:
					return true
			return false
		"self":
			# wash_all / push_all reach adjacent tiles first; radius-less
			# self ops need something in melee reach to act on
			return _enemies_within(snap, int(eff.get("radius", 1))) >= 1
	return false


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
		var aid: String = Content.base_id(String(kit[slot]))
		if aid == "mycelium_dash":
			continue
		var key: int = uses.get(kit[slot], 0) + (0 if not _wants(aid) else 100000)
		if key < best_key:
			best_key = key
			best_a = a
	return best_a
