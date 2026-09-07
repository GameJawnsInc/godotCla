extends RefCounted
## Static content tables. Adding content means adding data (style guide §6).

const PLAYER_HP := 10
const BASE_REGEN := 3
const BANK_CAP := 6
const SHIELD_CAP := 3
const MOVE_COST := 1
const STRIKE_COST := 1
const STRIKE_DMG := 1
const CLEANSE_COST := 1
const KIT_MAX := 5

const STARTING_KIT := ["solar_lance", "seed_bomb", "mycelium_dash"]

## Abilities are data recipes over effect ops (design doc: composable primitives).
const ABILITIES := {
	"solar_lance": {
		"name": "Solar Lance", "cost": 2, "target": "dir", "range": 3,
		"effects": [{"op": "lance", "dmg": 2, "clear_smog_bonus": 0, "ignite": true}],
		"tags": ["sun", "fire"], "role": "damage",
	},
	"seed_bomb": {
		"name": "Seed Bomb", "cost": 2, "target": "tile", "range": 3,
		"effects": [{"op": "grow_radius", "radius": 1}],
		"tags": ["growth"], "role": "setup",
	},
	"vine_whip": {
		"name": "Vine Whip", "cost": 1, "target": "enemy_line", "range": 3,
		"effects": [{"op": "pull", "dist": 2, "dmg": 2}],
		"tags": ["displace"], "role": "damage",
	},
	"water_jet": {
		"name": "Water Jet", "cost": 1, "target": "dir", "range": 2,
		"effects": [{"op": "wash_push", "push": 2, "collision_dmg": 2}],
		"surge": {"push": 1, "collision_dmg": 1},
		"tags": ["water", "displace"], "role": "damage",
	},
	"mycelium_dash": {
		"name": "Mycelium Dash", "cost": 1, "target": "growth", "range": 4,
		"effects": [{"op": "teleport"}],
		"tags": ["mobility"], "role": "mobility",
	},
	"root_wall": {
		"name": "Root Wall", "cost": 2, "target": "tile", "range": 2,
		"effects": [{"op": "grow_wall", "ttl": 4}],
		"tags": ["growth", "bark"], "role": "setup",
	},
	"pollen_burst": {
		"name": "Pollen Burst", "cost": 2, "target": "self", "range": 2,
		"effects": [{"op": "aoe_status", "status": "stun", "turns": 1, "radius": 2}],
		"tags": ["control"], "role": "control",
	},
	"sun_flare": {
		"name": "Sun Flare", "cost": 2, "target": "self", "range": 2,
		"effects": [{"op": "aoe_damage", "dmg": 1, "radius": 2, "ignite": true, "bonus": {"dmg": 1, "if": [{"target_on": ["fire"]}]}}],
		"surge": {"cost": -1, "radius": 1},
		"tags": ["sun", "fire"], "role": "damage",
	},
	"thorn_shield": {
		"name": "Thorn Shield", "cost": 1, "target": "self", "range": 0,
		"effects": [{"op": "shield", "amount": 2}],
		"tags": ["bark"], "role": "defense",
	},
	"overgrowth": {
		"name": "Overgrowth", "cost": 1, "target": "tile_any", "range": 2,
		"effects": [{"op": "convert_radius", "radius": 1}],
		"tags": ["growth"], "role": "setup",
	},
	"sap_snare": {
		"name": "Sap Snare", "cost": 1, "target": "enemy", "range": 3,
		"effects": [{"op": "apply_status", "status": "root", "turns": 2}],
		"tags": ["control"], "role": "control",
	},
	"grow_spike": {
		"name": "Grow Spike", "cost": 1, "target": "enemy_near_growth", "range": 3,
		"effects": [{"op": "damage", "dmg": 3, "per": {"count": "growth_adjacent_target", "cap": 1, "add": {"dmg": 1}}}],
		"surge": {"dmg": 1},
		"tags": ["growth"], "role": "payoff",
	},
	"spore_cloud": {
		"name": "Spore Cloud", "cost": 2, "target": "self", "range": 2,
		"effects": [{"op": "aoe_status", "status": "spore", "turns": 3, "radius": 2}],
		"tags": ["control"], "role": "control",
	},
	"fungal_ring": {
		"name": "Fungal Ring", "cost": 1, "target": "self", "range": 1,
		"effects": [{"op": "grow_radius", "radius": 1}],
		"tags": ["growth"], "role": "setup",
	},
	"burrow": {
		"name": "Burrow", "cost": 2, "target": "tile", "range": 3,
		"effects": [{"op": "teleport"}],
		"tags": ["mobility"], "role": "mobility",
	},
	"tide": {
		"name": "Tide", "cost": 2, "target": "self", "range": 2,
		"effects": [{"op": "wash_all", "push": 2, "collision_dmg": 1}],
		"tags": ["water", "displace"], "role": "damage",
	},
	"steam_vent": {
		"name": "Steam Vent", "cost": 1, "target": "tile_any", "range": 3,
		"effects": [{"op": "create_terrain", "kind": "smoke", "ttl": 3}],
		"tags": ["smoke"], "role": "setup",
	},
	"geyser": {
		"name": "Geyser", "cost": 2, "target": "self", "range": 1,
		"effects": [{"op": "aoe_damage", "dmg": 1, "radius": 1}, {"op": "push_all", "dist": 2}],
		"tags": ["water", "displace"], "role": "damage",
	},
	"gust": {
		"name": "Gust", "cost": 1, "target": "dir", "range": 3,
		"effects": [{"op": "push_line", "dist": 3, "clear_smoke": true}],
		"tags": ["wind", "displace", "smoke"], "role": "control",
	},
	"updraft": {
		"name": "Updraft", "cost": 1, "target": "dir", "range": 3,
		"effects": [{"op": "dash_dir"}],
		"tags": ["wind", "mobility"], "role": "mobility",
	},
	"clear_air": {
		"name": "Clear Air", "cost": 2, "target": "self", "range": 3,
		"effects": [{"op": "clear_smoke", "radius": 3}, {"op": "push_all", "dist": 1}],
		"tags": ["wind", "smoke", "displace"], "role": "utility",
	},
	"bramble_coat": {
		"name": "Bramble Coat", "cost": 1, "target": "self", "range": 0,
		"effects": [{"op": "thorns", "dmg": 2, "turns": 4}],
		"tags": ["bark"], "role": "defense",
	},
	"anchor_roots": {
		"name": "Anchor Roots", "cost": 1, "target": "self", "range": 0,
		"effects": [{"op": "anchor", "turns": 4}],
		"tags": ["bark"], "role": "defense",
	},
	"moss_filter": {
		"name": "Moss Filter", "cost": 2, "target": "self", "range": 0,
		"effects": [{"op": "undim", "amount": 1}],
		"tags": ["sun"], "role": "utility",
	},
	# Upgraded variants: offered in drafts when the base is owned; replace in place.
	"solar_lance+": {
		"name": "Solar Lance+", "cost": 2, "target": "dir", "range": 4,
		"effects": [{"op": "lance", "dmg": 3, "clear_smog_bonus": 1, "ignite": true}],
		"tags": ["sun", "fire"], "role": "damage",
	},
	"seed_bomb+": {
		"name": "Seed Bomb+", "cost": 1, "target": "tile", "range": 3,
		"effects": [{"op": "grow_radius", "radius": 1, "then": [{"op": "status_target", "status": "root", "turns": 1, "who": "on_planted"}]}],
		"surge": {"radius": 1},
		"tags": ["growth"], "role": "setup",
	},
	"vine_whip+": {
		"name": "Vine Whip+", "cost": 1, "target": "enemy_line", "range": 4,
		"effects": [{"op": "pull", "dist": 3, "dmg": 3, "then": [{"op": "status_target", "status": "stun", "turns": 1, "if": [{"outcome_crossed": "fire"}]}]}],
		"tags": ["displace"], "role": "damage",
	},
	"water_jet+": {
		"name": "Water Jet+", "cost": 1, "target": "dir", "range": 3,
		"effects": [{"op": "wash_push", "push": 3, "collision_dmg": 3, "then": [{"op": "status_target", "status": "root", "turns": 1, "if": [{"outcome": "collided"}, {"outcome": "pushed"}]}]}],
		"surge": {"push": 1, "collision_dmg": 1},
		"tags": ["water", "displace"], "role": "damage",
	},
	# Spore Trail (Block D1): the departure tile becomes growth once the tender
	# has left it (plant_origin - floor, no terrain, no enemy standing there).
	"mycelium_dash+": {
		"name": "Mycelium Dash+", "cost": 1, "target": "growth", "range": 7,
		"effects": [{"op": "teleport"}, {"op": "plant_origin", "kind": "growth"}],
		"tags": ["mobility"], "role": "mobility",
	},
	"root_wall+": {
		"name": "Root Wall+", "cost": 1, "target": "tile", "range": 2,
		"effects": [{"op": "grow_wall", "ttl": 6}],
		"tags": ["growth", "bark"], "role": "setup",
	},
	"pollen_burst+": {
		"name": "Pollen Burst+", "cost": 2, "target": "self", "range": 2,
		"effects": [{"op": "aoe_status", "status": "stun", "turns": 2, "radius": 2}],
		"tags": ["control"], "role": "control",
	},
	"sun_flare+": {
		"name": "Sun Flare+", "cost": 2, "target": "self", "range": 2,
		"effects": [{"op": "aoe_damage", "dmg": 2, "radius": 2, "ignite": true, "bonus": {"dmg": 1, "if": [{"target_on": ["fire"]}]}}],
		"surge": {"cost": -1, "radius": 1},
		"tags": ["sun", "fire"], "role": "damage",
	},
	"thorn_shield+": {
		"name": "Thorn Shield+", "cost": 1, "target": "self", "range": 0,
		"effects": [{"op": "shield", "amount": 3}],
		"tags": ["bark"], "role": "defense",
	},
	"overgrowth+": {
		"name": "Overgrowth+", "cost": 1, "target": "tile_any", "range": 3,
		"effects": [{"op": "convert_radius", "radius": 2}],
		"tags": ["growth"], "role": "setup",
	},
	"sap_snare+": {
		"name": "Sap Snare+", "cost": 1, "target": "enemy", "range": 4,
		"effects": [{"op": "apply_status", "status": "root", "turns": 3}],
		"tags": ["control"], "role": "control",
	},
	"grow_spike+": {
		"name": "Grow Spike+", "cost": 1, "target": "enemy_near_growth", "range": 4,
		"effects": [{"op": "damage", "dmg": 3, "per": {"count": "growth_adjacent_target", "cap": 2, "add": {"dmg": 1}}}],
		"surge": {"dmg": 1},
		"tags": ["growth"], "role": "payoff",
	},
	"bramble_coat+": {
		"name": "Bramble Coat+", "cost": 1, "target": "self", "range": 0,
		"effects": [{"op": "thorns", "dmg": 3, "turns": 5}],
		"tags": ["bark"], "role": "defense",
	},
	"anchor_roots+": {
		"name": "Anchor Roots+", "cost": 1, "target": "self", "range": 0,
		"effects": [{"op": "anchor", "turns": 7}],
		"tags": ["bark"], "role": "defense",
	},
	"moss_filter+": {
		"name": "Moss Filter+", "cost": 1, "target": "self", "range": 0,
		"effects": [{"op": "undim", "amount": 1}],
		"tags": ["sun"], "role": "utility",
	},
	# Package "+" rows (Block C4): offered only once the base is held, so the
	# base draft pool is untouched. Costs never move; one numeric bump each and
	# at most one rider, only where the vocabulary states the base identity.
	"spore_cloud+": {
		"name": "Spore Cloud+", "cost": 2, "target": "self", "range": 3,
		"effects": [{"op": "aoe_status", "status": "spore", "turns": 3, "radius": 3}],
		"tags": ["control"], "role": "control",
	},
	"fungal_ring+": {
		"name": "Fungal Ring+", "cost": 1, "target": "self", "range": 1,
		"effects": [{"op": "grow_radius", "radius": 1, "then": [{"op": "status_target", "status": "root", "turns": 1, "who": "on_planted"}]}],
		"tags": ["growth"], "role": "setup",
	},
	"burrow+": {
		"name": "Burrow+", "cost": 2, "target": "tile", "range": 4,
		"effects": [{"op": "teleport"}],
		"tags": ["mobility"], "role": "mobility",
	},
	"tide+": {
		"name": "Tide+", "cost": 2, "target": "self", "range": 2,
		"effects": [{"op": "wash_all", "push": 3, "collision_dmg": 2, "then": [{"op": "status_target", "status": "root", "turns": 1, "if": [{"outcome": "collided"}, {"outcome": "pushed"}]}]}],
		"tags": ["water", "displace"], "role": "damage",
	},
	"steam_vent+": {
		"name": "Steam Vent+", "cost": 1, "target": "tile_any", "range": 3,
		"effects": [{"op": "create_terrain", "kind": "smoke", "ttl": 5}],
		"tags": ["smoke"], "role": "setup",
	},
	"geyser+": {
		"name": "Geyser+", "cost": 2, "target": "self", "range": 1,
		"effects": [{"op": "aoe_damage", "dmg": 2, "radius": 1, "bonus": {"dmg": 1, "if": [{"target_on": ["fire"]}]}}, {"op": "push_all", "dist": 2}],
		"tags": ["water", "displace"], "role": "damage",
	},
	"gust+": {
		"name": "Gust+", "cost": 1, "target": "dir", "range": 4,
		"effects": [{"op": "push_line", "dist": 4, "clear_smoke": true}],
		"tags": ["wind", "displace", "smoke"], "role": "control",
	},
	"updraft+": {
		"name": "Updraft+", "cost": 1, "target": "dir", "range": 4,
		"effects": [{"op": "dash_dir"}],
		"tags": ["wind", "mobility"], "role": "mobility",
	},
	"clear_air+": {
		"name": "Clear Air+", "cost": 2, "target": "self", "range": 4,
		"effects": [{"op": "clear_smoke", "radius": 4}, {"op": "push_all", "dist": 2}],
		"tags": ["wind", "smoke", "displace"], "role": "utility",
	},
}

## Abilities that can appear in descent drafts. Mobility stays fixed for now.
const DRAFT_POOL := [
	"solar_lance", "seed_bomb", "vine_whip", "water_jet", "root_wall",
	"pollen_burst", "sun_flare", "thorn_shield", "overgrowth", "sap_snare",
	"grow_spike", "bramble_coat", "anchor_roots", "moss_filter",
]

## Descent draft slot roles (Block D4, docs/PROGRESSION_REVIEW.md 6.4 "Affinity-
## slotted draft with focus on skip"). Offer i of a draft is rolled by the
## role DRAFT_SLOTS[i]; an offer past the list (wide_draft asks for 4) is
## "wild". Roles, all over the universe the draft used before (unowned pool
## bases - never a base whose X or X+ is held - plus the + forms of held
## bases; under draft_upgrades_only only the + forms, and every role collapses
## to that list):
##   affinity             unowned pool bases sharing a tag with the run's
##                        affinity set (the union of ABILITIES tags over the
##                        held kit and GRAFTS tags over the held grafts, minus
##                        AFFINITY_IGNORED_TAGS)
##   upgrade_or_affinity  the + forms of held BUILD-DEFINING bases (see
##                        AFFINITY_IGNORED_TAGS) when any exist, else the
##                        affinity list
##   wild                 the whole universe
## A slot whose list is empty after earlier offers are excluded falls back to
## the wild list (reported "wild"; the focus slot below keeps its "focus"
## label through that fallback); Game._draw_draft_offers spends exactly one
## main-rng draw per slot whatever the lists hold. A skip arms `focus`: the
## next draft rolls one extra, last "affinity" slot (reported "focus").
## Entries come from the closed DRAFT_SLOT_ROLES set (tests/test_content.gd
## lints both, and the reported slot names in DRAFT_SLOT_REPORTS).
## A role is CODE, not data: Game._draw_draft_offers is the one site that
## implements them (a match on these strings, wild as the catch-all), so
## adding a role here without an arm there silently rolls it as wild - adding
## a role means changing that function in the same commit.
const DRAFT_SLOT_ROLES := ["affinity", "upgrade_or_affinity", "wild"]
const DRAFT_SLOTS := ["affinity", "upgrade_or_affinity", "wild"]
## What snapshot().draft_slots / the draft_offer event report per offer.
const DRAFT_SLOT_REPORTS := ["affinity", "upgrade", "wild", "focus"]
## Tags that do not define a build. Every loadout carries a mobility ability,
## so a run whose only "mobility" tag came from that slot is not thereby
## "mobility-affine" - and an ability carrying nothing but these tags is no
## part of a build at all. Both draft slots that read the build honour that,
## through the one helper pair Game._tag_defines_build / _build_defining:
## the affinity set ignores these tags, and the upgrade slot skips a + form
## whose base carries only them (mycelium_dash+, burrow+; updraft+ is
## ["wind", "mobility"] and stays). Neither the universe nor the wild slot
## nor the shrine forge is filtered - the + form is still reachable, just not
## dealt by the slot that is supposed to deepen what you are building.
const AFFINITY_IGNORED_TAGS := ["mobility"]

## --- Sim-ignored ability metadata ------------------------------------------
## The sim never reads TAGS, ROLES, ARCHETYPES or the helpers below, and reads
## "role" for exactly one rule: the shrine forge may never scrap a
## role == "mobility" ability (Game._is_mobility). Since Block D4 it reads
## "tags" for exactly one rule too: the draft's affinity slots (DRAFT_SLOTS
## above) offer bases sharing a tag with the held kit and grafts - the tags
## decide WHICH ids a slot can offer, never how many main-rng draws it spends.
## Otherwise step() outcomes and rng draws are unaffected by any value here. They are shared data (style
## guide §6) for bots (persona build commitments, drop guards), the shell
## (kit labels, build hints) and tests (coverage asserts), so all three agree
## on one vocabulary instead of each hardcoding ids.
## Every "+" form carries the same tags/role as its base; use base_id() to
## fold upgrades back onto the base entry.

## Closed tag vocabulary. Adding a tag means adding it here first.
const TAGS := ["sun", "fire", "water", "wind", "growth", "bark", "control", "displace", "smoke", "mobility", "economy"]
## Closed role vocabulary: what an ability does for a turn plan.
const ROLES := ["setup", "payoff", "damage", "defense", "control", "mobility", "utility"]

## Build archetypes: a named core of ability ids plus the packages the core
## needs in the pool. The first four match bots/fanatic.gd's BUILDS exactly so
## BALANCE.md per-build numbers stay comparable; never redefine them, add rows.
const ARCHETYPES := {
	"pyro": {"name": "Pyro", "core": ["solar_lance", "sun_flare"], "requires": {"packages": []}},
	"gardener": {"name": "Gardener", "core": ["seed_bomb", "overgrowth", "grow_spike"], "requires": {"packages": []}},
	"turtle": {"name": "Turtle", "core": ["thorn_shield", "bramble_coat", "seed_bomb", "sap_snare", "root_wall"], "requires": {"packages": []}},
	"shover": {"name": "Shover", "core": ["water_jet", "vine_whip", "pollen_burst", "solar_lance"], "requires": {"packages": []}},
	"pyro_nolance": {"name": "Pyro (lance-free)", "core": ["sun_flare", "moss_filter"], "requires": {"packages": []}},
	"shover_nolance": {"name": "Shover (lance-free)", "core": ["water_jet", "vine_whip", "pollen_burst"], "requires": {"packages": []}},
	"ember": {"name": "Ember", "core": ["sun_flare", "water_jet", "moss_filter"], "requires": {"packages": []}},
	"anchor": {"name": "Anchor", "core": ["anchor_roots", "root_wall", "thorn_shield"], "requires": {"packages": []}},
	"tidecaller": {"name": "Tidecaller", "core": ["tide", "geyser", "steam_vent", "water_jet"], "requires": {"packages": ["hydraulics"]}},
	"skyrunner": {"name": "Skyrunner", "core": ["gust", "updraft", "solar_lance"], "requires": {"packages": ["aeolian"]}},
	"sporewright": {"name": "Sporewright", "core": ["spore_cloud", "fungal_ring", "burrow"], "requires": {"packages": ["mycology"]}},
}


## Strip the upgrade suffix: "solar_lance+" -> "solar_lance". Ids without a
## "+" come back unchanged.
static func base_id(aid: String) -> String:
	var cut: int = aid.find("+")
	if cut < 0:
		return aid
	return aid.substr(0, cut)


## Archetype ids whose whole core can be assembled from `pool` plus the
## starting kit (mycelium_dash and the other STARTING_KIT ids count as always
## available). Preserves ARCHETYPES key order, so the result is deterministic.
static func archetypes_for(pool: Array) -> Array:
	var out: Array = []
	for arch_id in ARCHETYPES.keys():
		var ok := true
		for aid in ARCHETYPES[arch_id]["core"]:
			if not pool.has(aid) and not STARTING_KIT.has(aid):
				ok = false
				break
		if ok:
			out.append(arch_id)
	return out


## Starting loadouts (docs/PROGRESSION_REVIEW.md 6.1, Block A): the run-start
## choice. Data: {id: {name, desc, kit: [3 ids], protect: [ids], requires:
## {packages: [...]}}}. The sim reads exactly one key, "kit" (Game._init takes
## player.kit from LOADOUTS[config.loadout] when no explicit "kit" is given;
## "tender" is STARTING_KIT so a default-config run is byte-identical to
## before). "protect" is bot data - the ids a persona never drops or scraps -
## and "requires" is profile data (meta/profile.gd game_config enforces it;
## the sim only warns on an unknown id). Every row keeps seed_bomb (the
## boss-gate key) and exactly one role == "mobility" ability
## (tests/test_content.gd lints both).
const LOADOUTS := {
	"tender": {"name": "Tender", "desc": "the starter: lance, seed bomb, dash",
		"kit": ["solar_lance", "seed_bomb", "mycelium_dash"],
		"protect": ["mycelium_dash", "seed_bomb"], "requires": {}},
	"tidewarden": {"name": "Tidewarden", "desc": "water jet shoves in place of the lance",
		"kit": ["water_jet", "seed_bomb", "mycelium_dash"],
		"protect": ["mycelium_dash", "seed_bomb"], "requires": {}},
	"flarekeeper": {"name": "Flarekeeper", "desc": "sun flare lights the oil in place of the lance",
		"kit": ["sun_flare", "seed_bomb", "mycelium_dash"],
		"protect": ["mycelium_dash", "seed_bomb"], "requires": {}},
	"spiker": {"name": "Spiker", "desc": "grow spike pays off growth in place of the lance",
		"kit": ["grow_spike", "seed_bomb", "mycelium_dash"],
		"protect": ["mycelium_dash", "seed_bomb"], "requires": {}},
	"lasher": {"name": "Lasher", "desc": "vine whip drags in place of the lance",
		"kit": ["vine_whip", "seed_bomb", "mycelium_dash"],
		"protect": ["mycelium_dash", "seed_bomb"], "requires": {}},
	"skyrunner": {"name": "Skyrunner", "desc": "gust and updraft: wind positioning, no lance, no dash",
		"kit": ["gust", "seed_bomb", "updraft"],
		"protect": ["updraft", "seed_bomb"], "requires": {"packages": ["aeolian"]}},
}


## Loadout ids whose requires.packages are all in `unlocked_packages`.
## Preserves LOADOUTS key order, so the result is deterministic; "tender"
## (no requirements) is always first.
static func loadouts_for(unlocked_packages: Array) -> Array:
	var out: Array = []
	for lid in LOADOUTS.keys():
		var ok := true
		for pkg in LOADOUTS[lid]["requires"].get("packages", []):
			if not unlocked_packages.has(pkg):
				ok = false
				break
		if ok:
			out.append(lid)
	return out

## Grafts: passive run-long modifiers (the relic analog). Pure data; the sim
## consults owned grafts at the relevant decision points.
## One-use consumables: harvested when a room blooms, or bought at shrines.
## Using one is a free action - the turn does not advance.
const ITEMS := {
	"sun_capsule": {"name": "Sun Capsule", "desc": "Drink stored light: +3 charge, right now"},
	"balm_fruit": {"name": "Balm Fruit", "desc": "Eat: heal 4 HP"},
	"spore_vial": {"name": "Spore Vial", "desc": "Burst: stun every enemy within 2 tiles"},
	"clearair_pod": {"name": "Clear-Air Pod", "desc": "Pop: smog falls by 5"},
	"iron_seed": {"name": "Iron Seed", "desc": "Crack open: +3 shield"},
	# Upcycled forms: two consumables pressed into one at a shrine.
	"sun_capsule+": {"name": "Solar Battery", "desc": "Drink deep: +6 charge, right now"},
	"balm_fruit+": {"name": "Orchard Feast", "desc": "Eat well: heal to full"},
	"spore_vial+": {"name": "Spore Storm", "desc": "Burst: stun every enemy within 4 for 2 turns"},
	"clearair_pod+": {"name": "Storm Seed", "desc": "Pop: smog falls by 12"},
	"iron_seed+": {"name": "Ironheart", "desc": "Crack: +3 shield and +1 max HP"},
}
const ITEM_CAP := 2  # satchel slots
const ROOM_BLOOM_BONUS := 2  # extra bloom when a room's last corruption falls

## Grafts as data (docs/PROGRESSION_REVIEW.md 6.3 C3). Every row carries
## name, desc, tags (a TAGS subset, read by bots to rank shop offers) and
## exactly one of:
##   stat:  {key: int}   summed over held grafts by Game._graft_stat(key);
##          keys: bank_cap, shield_cap, regen, regen_on_growth, growth_heal,
##          cleanse_bloom (regen_on_growth is added to regen only on the turns
##          the tender begins standing on growth; no shipped row uses it - it
##          exists so a conditional alternative to solar_core can be measured)
##   mod:   {key: value} first held value wins, Game._graft_mod(key, default);
##          keys: floor_start_shield, oil_cast_discount
##   hooks: [{on: kind, effects: [...], cap_per_turn?: n, if?: [...]}] rows
##          the Game._hook dispatcher runs when `kind` (HOOK_KINDS) happens;
##          effects are _apply_effect dicts aimed at the hook tile plus the
##          positional ops damage_at {dmg}, status_at {status, turns} and
##          terrain_at {kind}. cap_per_turn (0 = none) is per source id.
## The lint (tests/test_content.gd) rejects hook rows that grant shield,
## thorns, heal or cleanse credit: those are the stall vector BALANCE.md
## documents, so rule grafts stay on the damage / control / economy side.
##
## "price": int >= 1, the graft's own base price in bloom (Game.shop_cost adds
## GRAFT_PRICE_STEP per graft already owned plus the tier markup; SHOP_COSTS
## ["graft"] stays as the id-less fallback). Priced off the 30-seed pre-install
## sweeps at tiers 0 and 6 recorded in docs/BALANCE.md (2026-09-06d/06f/07):
##   solar_core 8   the one lever: +12 wins at tier 0 (06d; +13 at 07b) and
##                  5/30 -> 22/30 at tier 6, four for four on the
##                  Method rule; all ten grafts held at once are worth no more
##                  than solar_core alone
##   compost 6      ~32 hooks a run and it halves the planner's damage taken -
##                  a growth loop, the second-strongest row
##   ember_sap 5    SHIP rows with a modest but real lift
##   oil_tithe 5
##   undertow 4
##   deep_cells 3   stat rows inside the noise at both tiers: cheap enough that
##   thick_bark 3   they are ever worth taking against a lever
##   verdant_pulse 3
##   bloom_surge 3
##   carapace 3
const GRAFTS := {
	"deep_cells": {"name": "Deep Cells", "desc": "+2 bank cap", "tags": ["sun"], "price": 3, "stat": {"bank_cap": 2}},
	"verdant_pulse": {"name": "Verdant Pulse", "desc": "growth heals +1", "tags": ["growth"], "price": 3, "stat": {"growth_heal": 1}},
	"thick_bark": {"name": "Thick Bark", "desc": "+2 shield cap", "tags": ["bark"], "price": 3, "stat": {"shield_cap": 2}},
	"bloom_surge": {"name": "Bloom Surge", "desc": "cleansing yields +1 bloom", "tags": ["growth", "economy"], "price": 3, "stat": {"cleanse_bloom": 1}},
	"solar_core": {"name": "Solar Core", "desc": "+1 charge regen", "tags": ["sun"], "price": 8, "stat": {"regen": 1}},
	"carapace": {"name": "Carapace", "desc": "start each floor with 2 shield", "tags": ["bark"], "price": 3, "mod": {"floor_start_shield": 2}},
	"ember_sap": {
		"name": "Ember Sap", "desc": "whoever stands on a tile as it catches fire takes 1 (3 times a turn)",
		"tags": ["fire"], "price": 5,
		"hooks": [{"on": "ignite", "effects": [{"op": "damage_at", "dmg": 1}], "cap_per_turn": 3}],
	},
	"undertow": {
		"name": "Undertow", "desc": "staggered enemies are also rooted a turn",
		"tags": ["water", "displace", "control"], "price": 4,
		"hooks": [{"on": "staggered", "effects": [{"op": "status_at", "status": "root", "turns": 1}]}],
	},
	"compost": {
		"name": "Compost", "desc": "a kill leaves growth where the enemy fell",
		"tags": ["growth"], "price": 6,
		"hooks": [{"on": "kill", "effects": [{"op": "terrain_at", "kind": "growth"}]}],
	},
	"oil_tithe": {
		"name": "Oil Tithe", "desc": "the first cast aimed at oil each turn costs 1 less (never below 1)",
		"tags": ["fire", "water", "economy"], "price": 5,
		"mod": {"oil_cast_discount": 1},
	},
}

## Hook kinds the sim dispatches (Game._hook), with the ctx keys each carries:
##   ignite {tile, by}                every ignition: lance, flare, igniter
##                                    enemy, ignite_all, spread, create_terrain
##   staggered {enemy}                forced movement interrupted a wind-up
##   cleanse {tile, kind}             the player tended a corruption tile
##   growth_planted {tiles}           grow_radius / the cleanse plant, one hook
##                                    per cast carrying every tile planted
##   kill {tile, enemy_kind, enemy_id}  an enemy died (any source)
##   shield_break {amt}               a hit took the player shield from > 0 to 0
##   collision {enemy, tile, src, dmg}  an enemy took collision damage
## A REACTIONS row whose event is a hook kind fires that hook (fire spread
## fires "ignite"), so the reaction table and the dispatcher share one name.
const HOOK_KINDS := ["ignite", "staggered", "cleanse", "growth_planted", "kill", "shield_break", "collision"]
## Hooks caused by hook effects nest at most this deep (ember_sap kill ->
## compost growth is depth 2); deeper hooks are skipped with {t: hook_capped}.
const HOOK_DEPTH_MAX := 3
## Total hook rows run in one step(); beyond it hooks are skipped and
## {t: hook_capped} is emitted once for the step.
const HOOK_STEP_CAP := 12

## One-line effect text per ability (a + form without its own entry falls back
## to the base). Rider rows (docs/PROGRESSION_REVIEW.md 6.3 C2) name the rider
## in one clause. UI-facing data; the sim ignores it.
const ABILITY_DESC := {
	"solar_lance": "Beam up to 3 tiles: 2 dmg, ignites oil (+: 3 dmg, 4 under clear skies)",
	"seed_bomb": "Plant a patch of healing growth within 3 tiles",
	"seed_bomb+": "Plant a patch of healing growth within 3 tiles; enemies on the fresh growth are rooted a turn; on growth: plants a 13-tile diamond",
	"vine_whip": "Yank an enemy 2 tiles toward you, 2 dmg; moving it interrupts its attack",
	"vine_whip+": "Yank an enemy 3 tiles toward you, 3 dmg; dragged through fire it is stunned a turn",
	"water_jet": "Shove enemies 2 tiles, 2 dmg on impact; moving them interrupts; on growth: pushes 1 further, hits 1 harder",
	"water_jet+": "Shove enemies 3 tiles, 3 dmg on impact; an enemy shoved into something is rooted a turn; on growth: pushes 1 further, hits 1 harder",
	"mycelium_dash": "Teleport to any growth tile within 4",
	"mycelium_dash+": "Teleport to any growth tile within 7; leaves growth where you stood",
	"root_wall": "Raise a wall of roots that blocks enemies",
	"pollen_burst": "Stun everything within 2 tiles for a turn",
	"sun_flare": "Flash burn: 1 dmg to all within 2, ignites oil; +1 dmg to enemies standing in fire; on growth: costs 1 less and reaches 3",
	"sun_flare+": "Flash burn: 2 dmg to all within 2, ignites oil; +1 dmg to enemies standing in fire; on growth: costs 1 less and reaches 3",
	"thorn_shield": "Raise 2 shield - blocks damage before HP",
	"overgrowth": "Convert corruption around a tile into growth",
	"sap_snare": "Root an enemy in place for 2 turns",
	"grow_spike": "3 dmg to an enemy standing near growth, +1 with growth beside it (4 max); on growth: +1 dmg",
	"grow_spike+": "3 dmg to an enemy near growth within 4, +1 per adjacent growth tile (5 max); on growth: +1 dmg",
	"spore_cloud": "Spore all within 2: 1 dmg a turn for 3 turns",
	"fungal_ring": "Sprout growth on every tile around you",
	"burrow": "Tunnel to any open tile within 3",
	"tide": "Wave outward: shove everything 2 tiles away",
	"steam_vent": "Vent smoke onto a tile - blocks lances",
	"geyser": "Erupt: 1 dmg beside you, shove everything 2",
	"gust": "Gust down a line: shove 3 tiles, clears smoke",
	"updraft": "Ride the wind: dash in a straight line",
	"clear_air": "Clear nearby smoke and push enemies back",
	"spore_cloud+": "Spore all within 3: 1 dmg a turn for 3 turns",
	"fungal_ring+": "Sprout growth on every tile around you; enemies on the fresh growth are rooted a turn",
	"burrow+": "Tunnel to any open tile within 4",
	"tide+": "Wave outward: shove everything 3 tiles, 2 dmg on impact; an enemy shoved into something is rooted a turn",
	"steam_vent+": "Vent smoke onto a tile for 5 turns - blocks lances",
	"geyser+": "Erupt: 2 dmg beside you, shove everything 2; +1 dmg to enemies standing in fire",
	"gust+": "Gust down a line of 4: shove 4 tiles, clears smoke",
	"updraft+": "Ride the wind: dash up to 4 in a straight line",
	"clear_air+": "Clear smoke within 4 and shove enemies 2 tiles back",
	"bramble_coat": "Grow spikes: attackers take 2 dmg, 4 turns",
	"anchor_roots": "Root yourself: immune to drags for 4 turns",
	"moss_filter": "Filter the air: restore a stage of dimmed regen",
}

## Shrine price list. "press" (two items -> one + item) and "forge" (one
## ability -> its + form, another scrapped) are shrine services priced here so
## the tier markup (Game.shop_cost) applies to them like every other purchase.
## "graft" here is only the id-less fallback: a real graft offer is priced from
## its own GRAFTS row ("price"), through Game.shop_cost("graft", id).
## "reroll" (Block D2, the one repeatable CHOICE sink) redraws every still-
## stocked re-drawable slot (ability, grafts, item) from the same candidate
## rule the floor stock used, through the side rng; Game.shop_cost("reroll")
## adds SHOP_REROLL_STEP per reroll already taken this floor. The action is
## legal only under the mutator config key shop_reroll (the spinning_shrine
## row) - see MUTATOR_CONFIG_KEYS for why it is off by default.
const SHOP_COSTS := {"heal": 3, "ability": 4, "graft": 4, "item": 2, "press": 1, "forge": 3, "reroll": 2}
const GRAFT_PRICE_STEP := 2  # each owned graft raises the next graft's price
## Rerolls per shrine (per floor). A cap bounds the action space: without one
## a purse could spin the counter indefinitely, and every search bot's
## branching at the shrine would grow with the bloom balance instead of
## staying a small fixed fan-out.
const SHOP_REROLL_CAP := 3
## Price growth per reroll already taken this floor. A repeatable sink must
## get dearer, or the first spin is always the right one and the cap is the
## only thing standing between the purse and "reroll until it fits".
const SHOP_REROLL_STEP := 1
const CLEANSE_SMOG_RELIEF := 1  # a cleanse pauses the smog clock, never rewinds it

## Optional run mutators: free-form spice chosen at run start (unlock-gated).
## Mutators are data (Block C4): the sim reads every row's "config" through
## one helper, Game._mut(key, default), which scans the held mutators in
## order - a scalar key takes the first hit, an array key concatenates every
## hit. Closed key set (tests/test_content.gd lints it):
##   kit_max              ability kit cap (default Content.KIT_MAX)
##   max_hp_delta         added to the starting max hp (hp starts full)
##   bank_cap             charge carried over a descend (default BANK_CAP + grafts)
##   oil_mult             multiplies every floor's oil count
##   extra_common_enemy   +n of each non-boss floor's most common enemy
##   shop                 false boards every shrine (shop == {})
##   pool_ban             ability ids removed from the draft pool (array; the
##                        shop's ability stock follows the pool)
##   kit_ban              true also strips pool_ban ids (+ forms too) from the
##                        starting kit
##   draft_offers         offers per descent draft (default 3; a slot past
##                        DRAFT_SLOTS rolls as "wild", and an armed focus
##                        adds one more on top)
##   draft_upgrades_only  draft candidates are only the + forms of held
##                        abilities - every DRAFT_SLOTS role collapses to that
##                        list (no candidate = the draft is skipped)
##   open_pool            true adds every PACKAGES ability to the draft pool
##                        (the pre-Block-A all-packages variety as a choice;
##                        the profile's one-package-per-run commitment is the
##                        default). Applied before pool_ban.
##   shop_reroll          true lets the shrine counter be rerolled for bloom
##                        (the Block D2 sink). Off by default: with it on the
##                        magpie canary rose 8% -> 15.5% over 200 paired seeds
##                        and every single price/cap lever still failed the
##                        30-seed gate (BALANCE.md 2026-09-07e), so default-on
##                        is an owner decision, not a data tweak.
const MUTATOR_CONFIG_KEYS := [
	"kit_max", "max_hp_delta", "bank_cap", "oil_mult", "extra_common_enemy", "shop",
	"pool_ban", "kit_ban", "draft_offers", "draft_upgrades_only", "open_pool", "shop_reroll",
]
const MUTATORS := {
	"kit_of_3": {"name": "Kit of Three", "desc": "ability kit capped at 3", "config": {"kit_max": 3}},
	"double_oil": {"name": "Slick Combine", "desc": "twice the oil everywhere", "config": {"oil_mult": 2}},
	"brittle": {"name": "Brittle Tender", "desc": "-3 max HP", "config": {"max_hp_delta": -3}},
	"parched": {"name": "Parched Cells", "desc": "charge cannot be banked", "config": {"bank_cap": 0}},
	"overtime": {"name": "Overtime Shift", "desc": "+1 of each floor's most common enemy", "config": {"extra_common_enemy": 1}},
	"boarded": {"name": "Boarded Shrines", "desc": "shrines sell nothing", "config": {"shop": false}},
	"no_lance": {"name": "Lance Embargo", "desc": "no Solar Lance: gone from the kit, the drafts and the shrine",
		"config": {"pool_ban": ["solar_lance"], "kit_ban": true}},
	"wide_draft": {"name": "Wide Draft", "desc": "four offers in every descent draft", "config": {"draft_offers": 4}},
	"upgrades_only": {"name": "Upgrades Only", "desc": "drafts offer only + forms of what you hold",
		"config": {"draft_upgrades_only": true}},
	"open_pool": {"name": "Open Pool", "desc": "draft from every package at once",
		"config": {"open_pool": true}},
	# Block D2: the shrine reroll, held behind a switch (see shop_reroll above)
	"spinning_shrine": {"name": "Spinning Shrine", "desc": "pay bloom to reroll the shrine counter",
		"config": {"shop_reroll": true}},
}

## Post-win difficulty tiers. Tier N applies the first N modifiers, stacking.
const TIERS := [
	{"name": "Thicker Smog", "choke_delta": -4},
	{"name": "Busy Vents", "spawn_every_delta": -2},
	{"name": "Rich Veins", "extra_enemy": "drill_bot"},
	{"name": "Dim Skies", "dim_delta": -2},
	{"name": "Gouging Prices", "shop_markup": 1},
	# Ceiling tiers: stat modifiers that bind even near-optimal play.
	{"name": "Hardened Plating", "enemy_hp_delta": 1},
	{"name": "Sharpened Drills", "enemy_dmg_delta": 1},
	{"name": "Overcharged Core", "boss_hp_delta": 6, "extra_elites": 1},
]
const SHOP_HEAL_AMOUNT := 4
const DESCEND_MAX_HP_BONUS := 1
const DESCEND_HEAL := 4

## Meta-unlock tech packages: milestones add these to the draft pool.
const PACKAGES := {
	"mycology": ["spore_cloud", "fungal_ring", "burrow"],
	"hydraulics": ["tide", "steam_vent", "geyser"],
	"aeolian": ["gust", "updraft", "clear_air"],
}

## Career milestones. `kind` names the profile bucket the id unlocks:
## package | mutator | loadout | graft (meta/profile.gd dispatches on it and
## push_errors on anything else). requires keys, all evaluated by
## meta/profile.gd against the recorded run history:
##   best_floor            deepest floor ever reached
##   wins                  total wins
##   tier_wins             wins at tier >= 1
##   casts {id: n}         effective casts of a base ability, summed over runs
##   won_with [ids]        one win whose kit held every id ("+" forms satisfy
##                         a base id; a "+" id must be held exactly)
##   wins_without [ids]    one win whose kit held none of them
##   grafts_owned_at_win n one win holding at least n grafts
const MILESTONES := [
	{"id": "mycology", "kind": "package", "requires": {"best_floor": 5}, "desc": "Reach the Pipeworks"},
	{"id": "hydraulics", "kind": "package", "requires": {"wins": 1}, "desc": "Shut down the Furnace"},
	{"id": "aeolian", "kind": "package", "requires": {"tier_wins": 1}, "desc": "Win at tier 1 or higher"},
	{"id": "kit_of_3", "kind": "mutator", "requires": {"wins": 1}, "desc": "Shut down the Furnace"},
	{"id": "double_oil", "kind": "mutator", "requires": {"wins": 1}, "desc": "Shut down the Furnace"},
	{"id": "brittle", "kind": "mutator", "requires": {"tier_wins": 1}, "desc": "Win at tier 1 or higher"},
	{"id": "parched", "kind": "mutator", "requires": {"tier_wins": 1}, "desc": "Win at tier 1 or higher"},
	{"id": "overtime", "kind": "mutator", "requires": {"wins": 2}, "desc": "Shut down the Furnace twice"},
	{"id": "boarded", "kind": "mutator", "requires": {"wins": 2}, "desc": "Shut down the Furnace twice"},
	{"id": "no_lance", "kind": "mutator", "requires": {"wins_without": ["solar_lance"]}, "desc": "Win with no Solar Lance in your kit"},
	{"id": "wide_draft", "kind": "mutator", "requires": {"casts": {"grow_spike": 60}}, "desc": "Land 60 Grow Spikes"},
	{"id": "upgrades_only", "kind": "mutator", "requires": {"won_with": ["seed_bomb+"]}, "desc": "Win holding Seed Bomb+"},
	# Block A: the run-start choices. `open_pool` hands back the old
	# everything-at-once draft pool (a run now commits to one package), and the
	# loadout rows open the starting kits in LOADOUTS - each earned by playing
	# the thing it hands you.
	{"id": "open_pool", "kind": "mutator", "requires": {"wins": 1}, "desc": "Draft from every package at once"},
	{"id": "spinning_shrine", "kind": "mutator", "requires": {"wins": 1}, "desc": "Pay bloom to reroll the shrine counter"},
	{"id": "tidewarden", "kind": "loadout", "requires": {"best_floor": 3}, "desc": "Reach the Refinery Gate"},
	{"id": "flarekeeper", "kind": "loadout", "requires": {"best_floor": 4}, "desc": "Reach the Cracking Yard"},
	{"id": "spiker", "kind": "loadout", "requires": {"casts": {"grow_spike": 30}}, "desc": "Land 30 Grow Spikes"},
	{"id": "lasher", "kind": "loadout", "requires": {"won_with": ["vine_whip"]}, "desc": "Win holding Vine Whip"},
	{"id": "skyrunner", "kind": "loadout", "requires": {"wins": 1}, "desc": "Shut down the Furnace"},
]

## Terrain vaults: hand-authored set-pieces stamped into a room. Terrain-only
## (never walls), so they can't sever connectivity. Legend: ~ oil, ; goo,
## & rich goo (cleanse for +3 bloom), " growth, . leave as-is.
const VAULTS := {
	"tar_hoard": [";;;", ";&;", ";;;"],
	"oil_spill": ["~~~~", "~&&~", "~~~~"],
	"old_garden": ["\"\"\"", "\"&\"", "\"\"\""],
	"fuel_depot": ["~~~~~", "~&~&~", "~~~~~"],
	"sacred_grove": ["\"\"\"\"", "\"&&\"", "\"\"\"\""],
}

const RICH_GOO_BLOOM := 3
const ELITE_HP_BONUS := 2
const ELITE_DMG_BONUS := 0
const ELITE_BOUNTY := 4

## --- Effect grammar data tables (docs/PROGRESSION_REVIEW.md §6.3, C1) -------
## Every literal the sim used to hardcode about terrain, statuses and terrain
## reactions lives here. C1a introduces the tables with zero behaviour change;
## later blocks flip rows (ash, root blocking advance/drag, spore add-stack).

## Per-ability surge rule (key "surge" on an ABILITIES row; this is the default
## when the row has none). A cast made while standing on growth SURGES when the
## dict carries anything that applies to it (Game._surges): a "cost" delta on
## a base cost >= 2 (the cast costs maxi(1, base + cost)) or any stat key.
## Stat keys - dmg, push, collision_dmg, radius, dist, turns, ttl (the closed
## set tests/test_content.gd lints) - are int deltas added to the matching key
## of every effect of the cast that carries it, before riders run. A surged
## cast consumes the growth tile (event verdant) and a stat surge emits
## {t: "surge", id, keys}. So a cost-1 row with only this default never surges
## and never consumes growth; grow_spike(+) {dmg: 1}, water_jet(+) {push: 1,
## collision_dmg: 1} and seed_bomb+ {radius: 1} do, and sun_flare(+) keeps its
## discount and reaches 3 ({cost: -1, radius: 1}). Block D1.
const SURGE_DEFAULT := {"cost": -1}

## Terrain kinds. Required keys (tests/test_content.gd lints them):
##   corruption      counts for the cleanse quota / room bloom / floor restore
##   shields_core    adjacency shields a low-hp boss core (Game._corruption_adjacent)
##   flammable       lance / flare / igniter / ignite_all turn it into fire
##   washable        a water wash removes it
##   bloom           cleanse yield when the tile carries no "bloom" key of its own
##   ttl             lifetime written when the sim creates the tile (0 = the
##                   creator decides: roots take theirs from the ability)
##   decays          loses one ttl per environment phase and expires at 0
##   enter_dmg_player / enter_dmg_enemy   damage on stepping onto the tile
##   enter_src       player-side damage source string for enter damage
##   tick_dmg_player / tick_dmg_enemy     damage for standing on it each
##                   environment phase (enemy source is "<kind>:<by>")
##   blocks          impassable (Game._open)
##   blocks_beam     stops lances and enemy_line targeting (Game._line_clear)
##   heal            hp the player regains per environment phase standing on it
##   burns_to        what an expiring fire leaves behind ("" = nothing; fire
##                   burns to ash: the REACTIONS fire_burns_out row mirrors it)
##   convertible     a convert_radius (overgrowth) turns it into growth; every
##                   corruption kind except rich_goo, whose bonus must be cleansed
##   screens         a smoke screen (Block D3): while the tender stands on such a
##                   tile or one lies on any of the four DIRS neighbours, every
##                   SCREENED_INTENTS intent from a non-adjacent, non-massive
##                   enemy fizzles ({t: "screened"}); smoke only
## Ash (C1b): what oil leaves once its fire burns out. Corruption for the
## quota, room bloom and floor restore, cleansable and washable, but it never
## shields the boss core and never burns again. Mapgen never places it; the
## tile inherits the burnt oil's "bloom" flag, so enemy-made oil (bloom 0)
## ends as bloom-0 ash.
const TERRAIN := {
	"oil": {
		"corruption": true, "shields_core": true, "flammable": true, "washable": true,
		"bloom": 1, "ttl": 0, "decays": false,
		"enter_dmg_player": 0, "enter_dmg_enemy": 0, "enter_src": "",
		"tick_dmg_player": 0, "tick_dmg_enemy": 0,
		"blocks": false, "blocks_beam": false, "heal": 0, "burns_to": "", "convertible": true, "screens": false,
	},
	"goo": {
		"corruption": true, "shields_core": true, "flammable": false, "washable": false,
		"bloom": 1, "ttl": 0, "decays": false,
		"enter_dmg_player": 1, "enter_dmg_enemy": 0, "enter_src": "goo",
		"tick_dmg_player": 0, "tick_dmg_enemy": 0,
		"blocks": false, "blocks_beam": false, "heal": 0, "burns_to": "", "convertible": true, "screens": false,
	},
	"rich_goo": {
		"corruption": true, "shields_core": true, "flammable": false, "washable": false,
		"bloom": RICH_GOO_BLOOM, "ttl": 0, "decays": false,
		"enter_dmg_player": 1, "enter_dmg_enemy": 0, "enter_src": "goo",
		"tick_dmg_player": 0, "tick_dmg_enemy": 0,
		"blocks": false, "blocks_beam": false, "heal": 0, "burns_to": "", "convertible": false, "screens": false,
	},
	"growth": {
		"corruption": false, "shields_core": false, "flammable": false, "washable": false,
		"bloom": 0, "ttl": 0, "decays": false,
		"enter_dmg_player": 0, "enter_dmg_enemy": 0, "enter_src": "",
		"tick_dmg_player": 0, "tick_dmg_enemy": 0,
		"blocks": false, "blocks_beam": false, "heal": 1, "burns_to": "", "convertible": false, "screens": false,
	},
	"fire": {
		"corruption": false, "shields_core": false, "flammable": false, "washable": true,
		"bloom": 0, "ttl": 2, "decays": true,
		"enter_dmg_player": 1, "enter_dmg_enemy": 1, "enter_src": "fire",
		"tick_dmg_player": 1, "tick_dmg_enemy": 1,
		"blocks": false, "blocks_beam": false, "heal": 0, "burns_to": "ash", "convertible": false, "screens": false,
	},
	"smoke": {
		"corruption": false, "shields_core": false, "flammable": false, "washable": false,
		"bloom": 0, "ttl": 3, "decays": true,
		"enter_dmg_player": 0, "enter_dmg_enemy": 0, "enter_src": "",
		"tick_dmg_player": 0, "tick_dmg_enemy": 0,
		"blocks": false, "blocks_beam": true, "heal": 0, "burns_to": "", "convertible": false, "screens": true,
	},
	"roots": {
		"corruption": false, "shields_core": false, "flammable": false, "washable": false,
		"bloom": 0, "ttl": 0, "decays": true,
		"enter_dmg_player": 0, "enter_dmg_enemy": 0, "enter_src": "",
		"tick_dmg_player": 0, "tick_dmg_enemy": 0,
		"blocks": true, "blocks_beam": false, "heal": 0, "burns_to": "", "convertible": false, "screens": false,
	},
	"supply": {
		"corruption": false, "shields_core": false, "flammable": false, "washable": false,
		"bloom": 0, "ttl": 0, "decays": false,
		"enter_dmg_player": 0, "enter_dmg_enemy": 0, "enter_src": "",
		"tick_dmg_player": 0, "tick_dmg_enemy": 0,
		"blocks": false, "blocks_beam": false, "heal": 0, "burns_to": "", "convertible": false, "screens": false,
	},
	"ash": {
		"corruption": true, "shields_core": false, "flammable": false, "washable": true,
		"bloom": 1, "ttl": 0, "decays": false,
		"enter_dmg_player": 0, "enter_dmg_enemy": 0, "enter_src": "",
		"tick_dmg_player": 0, "tick_dmg_enemy": 0,
		"blocks": false, "blocks_beam": false, "heal": 0, "burns_to": "", "convertible": true, "screens": false,
	},
}

## Terrain reactions, consumed by Game._terrain_react() once per environment
## phase. Row shape: {id, from, adjacent | on_expire | on_wash, result, event,
## enabled}. "adjacent": every enabled `from` tile turns each neighbouring
## `adjacent` tile into `result` (the first source in map order signs the new
## tile's "by"; the replaced tile's "bloom" flag is inherited; "" removes the
## tile). "on_expire": a decaying `from` tile whose ttl hits 0 becomes
## `result` ("" = removed; the result inherits the "bloom" flag, and "by"
## only when it decays itself) and emits `event` when one is named. "on_wash"
## is reserved (a wash over `from`); no consumer reads it yet. Disabled rows
## are design intent kept as data.
const REACTIONS := [
	{"id": "fire_spreads", "from": "fire", "adjacent": "oil", "result": "fire", "event": "ignite", "enabled": true},
	{"id": "fire_burns_out", "from": "fire", "on_expire": true, "result": "ash", "event": "ash", "enabled": true},
	{"id": "damp", "from": "goo", "on_wash": true, "result": "", "event": "damp", "enabled": false},
	{"id": "roots_burn", "from": "fire", "adjacent": "roots", "result": "fire", "event": "ignite", "enabled": false},
	{"id": "smoke_smother", "from": "smoke", "adjacent": "fire", "result": "", "event": "smothered", "enabled": false},
]

## Enemy statuses. stack: "max" keeps the longer duration, "add" sums (capped
## at `cap` when cap > 0). blocks: intent types the status swallows ("*" =
## every intent); a blocked intent decrements the status and emits
## blocked_event. tick_dmg: damage per environment phase while it lasts
## (source = the status name), decrementing the status each tick. cooldown
## (optional, stagger-style): landing the status writes "<name>_cd" =
## max(existing cd, resulting duration + cooldown) on the enemy, so a
## re-application while it is active can extend but never shorten the
## cooldown; the field drops by one each time the enemy acts, and while it is
## above zero with the status itself expired a fresh application is refused
## with {t: "resisted"}. The stagger cooldown
## (status "stagger_cd") is an internal field, not a row here.
const STATUSES := {
	"stun": {"stack": "max", "blocks": ["*"], "tick_dmg": 0, "cap": 0, "blocked_event": "stunned"},
	"root": {"stack": "max", "blocks": ["move", "advance", "drag"], "tick_dmg": 0, "cap": 0, "blocked_event": "rooted", "cooldown": 2},
	"spore": {"stack": "add", "blocks": [], "tick_dmg": 1, "cap": 6},
}


## Enemy intents a smoke screen swallows (Block D3, Game._screened): drain,
## gum and drag are the ranged, aimed intents that need to see the tender; a
## melee attack, a slam or a summon does not look. Closed list - every entry
## must be an intent type Game._execute_intent handles (tests/test_content.gd
## INTENT_TYPES). The rule lives at execution only, so the intent is still
## computed and telegraphed: a shown gum is something the tender can step into
## smoke to dodge.
const SCREENED_INTENTS := ["drain", "gum", "drag"]

## One TERRAIN attribute; `default` when the kind or key is unknown ("" is the
## no-terrain kind and always reads as default).
static func terrain(kind: String, key: String, default = null):
	var row = TERRAIN.get(kind)
	if row == null:
		return default
	return row.get(key, default)


static func is_corruption(kind: String) -> bool:
	return bool(terrain(kind, "corruption", false))


## Corruption for COUNTING purposes (the quota clamp, floor restore and room
## bloom): the kind itself, or "pending corruption" - a fire whose burns_to
## leaves corruption behind. Lighting a slick therefore never shrinks the
## green gate, and the room it burns in waits for the ash before it blooms.
## Every other rule (cleanse legality, shields_core, convertible, washable,
## bot pathing) keeps is_corruption: a fire is not a thing you can tend.
static func counts_as_corruption(kind: String) -> bool:
	return is_corruption(kind) or is_corruption(String(terrain(kind, "burns_to", "")))


## Extra step-cost an enemy pays to enter a tile whose terrain kind is in its
## row's "avoid" list (Block D3, Game._chase_step). Walking around costs the
## detour's extra tiles, walking through costs this much per avoided tile, and
## the enemy takes whichever is cheaper (at equal cost the path with fewer
## avoided tiles): a detour up to this many tiles longer is taken, a longer
## one is not. So a ring of fire is never an immortal fence - when burning
## through is the cheapest way, the enemy burns through. This constant is the
## one tuning lever the measure phase may name.
const ENEMY_AVOID_COST := 4

## Enemy rows. Optional key "avoid": [TERRAIN kinds] (default [] = terrain-
## blind, exactly the pre-D3 chase) - the kinds the enemy paths around at
## ENEMY_AVOID_COST per tile. Every mobile machine avoids fire; the rows that
## deviate say why. Stationary kinds (extractor_engine, pump_jack, smokestack)
## never move, so an avoid list would be dead data; bosses see through smoke
## (massive) and fear nothing.
const ENEMIES := {
	"drill_bot": {"name": "Drill Bot", "hp": 3, "dmg": 2, "slow": false, "traits": ["fuses"], "avoid": ["fire"]},
	"oil_sludge": {"name": "Oil Sludge", "hp": 4, "dmg": 1, "slow": true, "traits": ["splits", "oil_trail"], "avoid": ["fire"]},
	"sludgeling": {"name": "Sludgeling", "hp": 1, "dmg": 1, "slow": false, "traits": [], "avoid": ["fire"]},
	"leech_drone": {"name": "Leech Drone", "hp": 2, "dmg": 0, "slow": false, "traits": ["drains"], "drain": 2, "drain_range": 2, "avoid": ["fire"]},
	"tar_spitter": {"name": "Tar Spitter", "hp": 2, "dmg": 0, "slow": false, "traits": ["gums"], "gum_range": 3, "gum_turns": 2, "avoid": ["fire"]},
	# Two drill bots welded into one by the combine's assimilation. No avoid
	# list: nothing stops the hulk, it walks straight through fire.
	"welded_hulk": {"name": "Welded Hulk", "hp": 7, "dmg": 2, "slow": true, "traits": ["spiked"]},
	# Spiked: melee strikes hurt the attacker - reach for a tool instead.
	# No avoid list: it is made of coal and does not mind fire.
	"coal_golem": {"name": "Coal Golem", "hp": 4, "dmg": 2, "slow": true, "traits": ["smoke_burst", "spiked"]},
	"extractor_engine": {"name": "Extractor Engine", "hp": 5, "dmg": 0, "slow": false, "traits": ["summons"], "summon_cycle": 3},
	"rust_hound": {"name": "Rust Hound", "hp": 2, "dmg": 1, "slow": false, "traits": ["spiked", "fast"], "avoid": ["fire"]},
	# No avoid list: the igniter WANTS fire - it lights the oil it walks over.
	"cinder_mite": {"name": "Cinder Mite", "hp": 1, "dmg": 1, "slow": false, "traits": ["igniter"]},
	"pump_jack": {"name": "Pump Jack", "hp": 4, "dmg": 0, "slow": false, "traits": ["oozes"], "ooze_cycle": 2},
	# Stationary clock attacker: every stoke_cycle turns the smog clock ticks
	# an extra time while it lives. Kill it (tempo cost) or race it.
	"smokestack": {"name": "Smokestack", "hp": 4, "dmg": 0, "slow": false, "traits": ["stokes"], "stoke_cycle": 2},
	# Position disruptor: drags the player one tile toward itself each turn
	# while in range - punishes pure kiting, feeds melee packs.
	"magnet_crane": {"name": "Magnet Crane", "hp": 3, "dmg": 0, "slow": false, "traits": ["drags"], "drag_range": 3, "avoid": ["fire"]},
	"furnace_core": {"name": "Furnace Core", "hp": 18, "dmg": 3, "slow": false, "traits": ["boss", "massive"], "slam_range": 3, "gate_hp": 6},
	"overseer": {"name": "The Overseer", "hp": 16, "dmg": 3, "slow": false, "traits": ["boss", "massive", "mobile_boss"], "slam_range": 3, "gate_hp": 5},
	# Anti-growth boss: drags the player in, slams, and dredges nearby growth
	# back into goo (healing per tile). Counterplay: fight it away from your
	# garden, or accept feeding it.
	"the_dredge": {"name": "The Dredge", "hp": 16, "dmg": 2, "slow": false, "traits": ["boss", "massive", "mobile_boss", "dredges"], "slam_range": 2, "drag_range": 4, "gate_hp": 5},
}

const FLOORS := [
	{
		"name": "Strip Mine I", "biome": "strip_mine", "w": 22, "h": 14, "rooms": 4,
		"enemies": {"drill_bot": 2},
		"oil": 4, "goo": 2, "vents": 1, "green_need": 2,
		"smog_spawn": [10, 20], "smog_spawn_every": 12, "smog_dim": [14, 22], "smog_choke": 38,
	},
	{
		"name": "Strip Mine II", "biome": "strip_mine", "w": 24, "h": 15, "rooms": 5,
		"enemies": {"drill_bot": 1, "oil_sludge": 1, "leech_drone": 1, "tar_spitter": 1},
		"oil": 6, "goo": 3, "vents": 2, "green_need": 3, "vaults": ["old_garden"],
		"smog_spawn": [9, 17], "smog_spawn_every": 10, "smog_dim": [12, 20], "smog_choke": 36,
	},
	{
		"name": "Refinery Gate", "biome": "refinery", "w": 26, "h": 16, "rooms": 5,
		"enemies": {"drill_bot": 1, "oil_sludge": 1, "leech_drone": 1, "tar_spitter": 1, "coal_golem": 1},
		"oil": 8, "goo": 4, "vents": 2, "green_need": 3, "elites": 1, "vaults": ["tar_hoard", "old_garden"], "pipes": 1,
		"smog_spawn": [10, 18], "smog_spawn_every": 11, "smog_dim": [14, 22], "smog_choke": 36,
	},
	{
		"name": "Cracking Yard", "biome": "refinery", "w": 26, "h": 16, "rooms": 6,
		"enemies": {"drill_bot": 1, "oil_sludge": 1, "tar_spitter": 1, "extractor_engine": 1, "rust_hound": 1, "magnet_crane": 1},
		"oil": 9, "goo": 4, "vents": 2, "green_need": 3, "vaults": ["oil_spill", "tar_hoard"], "pipes": 1,
		"smog_spawn": [12, 22], "smog_spawn_every": 12, "smog_dim": [14, 22], "smog_choke": 34,
	},
	{
		"name": "Pipeworks", "biome": "refinery", "w": 28, "h": 16, "rooms": 6,
		"enemies": {"drill_bot": 1, "oil_sludge": 1, "coal_golem": 1, "extractor_engine": 1, "pump_jack": 1, "rust_hound": 1, "smokestack": 1},
		"oil": 10, "goo": 5, "vents": 3, "green_need": 3, "elites": 1, "vaults": ["oil_spill", "tar_hoard", "fuel_depot"], "pipes": 2,
		"smog_spawn": [12, 20], "smog_spawn_every": 12, "smog_dim": [13, 21], "smog_choke": 32,
	},
	{
		"name": "Furnace Approach", "biome": "furnace", "w": 28, "h": 17, "rooms": 6,
		"enemies": {"drill_bot": 1, "coal_golem": 2, "tar_spitter": 1, "extractor_engine": 1, "cinder_mite": 2, "smokestack": 1},
		"oil": 12, "goo": 5, "vents": 3, "green_need": 4, "elites": 1, "vaults": ["fuel_depot", "tar_hoard", "sacred_grove"], "pipes": 2,
		"smog_spawn": [10, 18], "smog_spawn_every": 11, "smog_dim": [12, 20], "smog_choke": 30,
	},
	{
		"name": "The Furnace", "biome": "furnace", "boss": true, "w": 20, "h": 12,
		"bosses": ["furnace_core", "overseer", "the_dredge"],
		"enemies": {}, "oil": 6, "goo": 0, "vents": 2, "rooms": 0,
		"smog_spawn": [12, 24], "smog_spawn_every": 12, "smog_dim": [16, 26], "smog_choke": 44,
	},
]
