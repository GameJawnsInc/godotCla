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
		"effects": [{"op": "aoe_damage", "dmg": 1, "radius": 2, "ignite": true}],
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
		"effects": [{"op": "damage", "dmg": 3}],
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
		"effects": [{"op": "grow_radius", "radius": 1}],
		"tags": ["growth"], "role": "setup",
	},
	"vine_whip+": {
		"name": "Vine Whip+", "cost": 1, "target": "enemy_line", "range": 4,
		"effects": [{"op": "pull", "dist": 3, "dmg": 3}],
		"tags": ["displace"], "role": "damage",
	},
	"water_jet+": {
		"name": "Water Jet+", "cost": 1, "target": "dir", "range": 3,
		"effects": [{"op": "wash_push", "push": 3, "collision_dmg": 3}],
		"tags": ["water", "displace"], "role": "damage",
	},
	"mycelium_dash+": {
		"name": "Mycelium Dash+", "cost": 1, "target": "growth", "range": 7,
		"effects": [{"op": "teleport"}],
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
		"effects": [{"op": "aoe_damage", "dmg": 2, "radius": 2, "ignite": true}],
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
		"effects": [{"op": "damage", "dmg": 4}],
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
}

## Abilities that can appear in descent drafts. Mobility stays fixed for now.
const DRAFT_POOL := [
	"solar_lance", "seed_bomb", "vine_whip", "water_jet", "root_wall",
	"pollen_burst", "sun_flare", "thorn_shield", "overgrowth", "sap_snare",
	"grow_spike", "bramble_coat", "anchor_roots", "moss_filter",
]

## --- Sim-ignored ability metadata ------------------------------------------
## The sim never reads "tags", TAGS, ROLES, ARCHETYPES or the helpers below,
## and reads "role" for exactly one rule: the shrine forge may never scrap a
## role == "mobility" ability (Game._is_mobility). Otherwise step() outcomes
## and rng draws are unaffected by any value here. They are shared data (style
## guide §6) for bots (persona build commitments, drop guards), the shell
## (kit labels, build hints) and tests (coverage asserts), so all three agree
## on one vocabulary instead of each hardcoding ids.
## Every "+" form carries the same tags/role as its base; use base_id() to
## fold upgrades back onto the base entry.

## Closed tag vocabulary. Adding a tag means adding it here first.
const TAGS := ["sun", "fire", "water", "wind", "growth", "bark", "control", "displace", "smoke", "mobility"]
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

const GRAFTS := {
	"deep_cells": {"name": "Deep Cells", "desc": "+2 bank cap"},
	"verdant_pulse": {"name": "Verdant Pulse", "desc": "growth heals +1"},
	"thick_bark": {"name": "Thick Bark", "desc": "+2 shield cap"},
	"bloom_surge": {"name": "Bloom Surge", "desc": "cleansing yields +1 bloom"},
	"solar_core": {"name": "Solar Core", "desc": "+1 charge regen"},
	"carapace": {"name": "Carapace", "desc": "start each floor with 2 shield"},
}

## One-line effect text per base ability (upgrades fall back to the base and
## show slightly better numbers in play). UI-facing data; the sim ignores it.
const ABILITY_DESC := {
	"solar_lance": "Beam up to 3 tiles: 2 dmg, ignites oil (+: 3 dmg, 4 under clear skies)",
	"seed_bomb": "Plant a patch of healing growth within 3 tiles",
	"vine_whip": "Yank an enemy 2 tiles toward you, 2 dmg; moving it interrupts its attack",
	"water_jet": "Shove enemies 2 tiles, 2 dmg on impact; moving them interrupts",
	"mycelium_dash": "Teleport to any growth tile within 4",
	"root_wall": "Raise a wall of roots that blocks enemies",
	"pollen_burst": "Stun everything within 2 tiles for a turn",
	"sun_flare": "Flash burn: 1 dmg to all within 2, ignites oil",
	"thorn_shield": "Raise 2 shield - blocks damage before HP",
	"overgrowth": "Convert corruption around a tile into growth",
	"sap_snare": "Root an enemy in place for 2 turns",
	"grow_spike": "3 dmg to an enemy standing near growth",
	"spore_cloud": "Spore all within 2: 1 dmg a turn for 3 turns",
	"fungal_ring": "Sprout growth on every tile around you",
	"burrow": "Tunnel to any open tile within 3",
	"tide": "Wave outward: shove everything 2 tiles away",
	"steam_vent": "Vent smoke onto a tile - blocks lances",
	"geyser": "Erupt: 1 dmg beside you, shove everything 2",
	"gust": "Gust down a line: shove 3 tiles, clears smoke",
	"updraft": "Ride the wind: dash in a straight line",
	"clear_air": "Clear nearby smoke and push enemies back",
	"bramble_coat": "Grow spikes: attackers take 2 dmg, 4 turns",
	"anchor_roots": "Root yourself: immune to drags for 4 turns",
	"moss_filter": "Filter the air: restore a stage of dimmed regen",
}

## Shrine price list. "press" (two items -> one + item) and "forge" (one
## ability -> its + form, another scrapped) are shrine services priced here so
## the tier markup (Game.shop_cost) applies to them like every other purchase.
const SHOP_COSTS := {"heal": 3, "ability": 4, "graft": 4, "item": 2, "press": 1, "forge": 3}
const GRAFT_PRICE_STEP := 2  # each owned graft raises the next graft's price
const CLEANSE_SMOG_RELIEF := 1  # a cleanse pauses the smog clock, never rewinds it

## Optional run mutators: free-form spice chosen at run start (unlock-gated).
const MUTATORS := {
	"kit_of_3": {"name": "Kit of Three", "desc": "ability kit capped at 3"},
	"double_oil": {"name": "Slick Combine", "desc": "twice the oil everywhere"},
	"brittle": {"name": "Brittle Tender", "desc": "-3 max HP"},
	"parched": {"name": "Parched Cells", "desc": "charge cannot be banked"},
	"overtime": {"name": "Overtime Shift", "desc": "+1 of each floor's most common enemy"},
	"boarded": {"name": "Boarded Shrines", "desc": "shrines sell nothing"},
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

## Career milestones. requires keys: best_floor, wins, tier_wins (wins at tier >= 1).
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
## when the row has none): a cast of base cost >= 2 made while standing on
## growth costs maxi(1, base + cost) and consumes the growth tile.
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
		"blocks": false, "blocks_beam": false, "heal": 0, "burns_to": "", "convertible": true,
	},
	"goo": {
		"corruption": true, "shields_core": true, "flammable": false, "washable": false,
		"bloom": 1, "ttl": 0, "decays": false,
		"enter_dmg_player": 1, "enter_dmg_enemy": 0, "enter_src": "goo",
		"tick_dmg_player": 0, "tick_dmg_enemy": 0,
		"blocks": false, "blocks_beam": false, "heal": 0, "burns_to": "", "convertible": true,
	},
	"rich_goo": {
		"corruption": true, "shields_core": true, "flammable": false, "washable": false,
		"bloom": RICH_GOO_BLOOM, "ttl": 0, "decays": false,
		"enter_dmg_player": 1, "enter_dmg_enemy": 0, "enter_src": "goo",
		"tick_dmg_player": 0, "tick_dmg_enemy": 0,
		"blocks": false, "blocks_beam": false, "heal": 0, "burns_to": "", "convertible": false,
	},
	"growth": {
		"corruption": false, "shields_core": false, "flammable": false, "washable": false,
		"bloom": 0, "ttl": 0, "decays": false,
		"enter_dmg_player": 0, "enter_dmg_enemy": 0, "enter_src": "",
		"tick_dmg_player": 0, "tick_dmg_enemy": 0,
		"blocks": false, "blocks_beam": false, "heal": 1, "burns_to": "", "convertible": false,
	},
	"fire": {
		"corruption": false, "shields_core": false, "flammable": false, "washable": true,
		"bloom": 0, "ttl": 2, "decays": true,
		"enter_dmg_player": 1, "enter_dmg_enemy": 1, "enter_src": "fire",
		"tick_dmg_player": 1, "tick_dmg_enemy": 1,
		"blocks": false, "blocks_beam": false, "heal": 0, "burns_to": "ash", "convertible": false,
	},
	"smoke": {
		"corruption": false, "shields_core": false, "flammable": false, "washable": false,
		"bloom": 0, "ttl": 3, "decays": true,
		"enter_dmg_player": 0, "enter_dmg_enemy": 0, "enter_src": "",
		"tick_dmg_player": 0, "tick_dmg_enemy": 0,
		"blocks": false, "blocks_beam": true, "heal": 0, "burns_to": "", "convertible": false,
	},
	"roots": {
		"corruption": false, "shields_core": false, "flammable": false, "washable": false,
		"bloom": 0, "ttl": 0, "decays": true,
		"enter_dmg_player": 0, "enter_dmg_enemy": 0, "enter_src": "",
		"tick_dmg_player": 0, "tick_dmg_enemy": 0,
		"blocks": true, "blocks_beam": false, "heal": 0, "burns_to": "", "convertible": false,
	},
	"supply": {
		"corruption": false, "shields_core": false, "flammable": false, "washable": false,
		"bloom": 0, "ttl": 0, "decays": false,
		"enter_dmg_player": 0, "enter_dmg_enemy": 0, "enter_src": "",
		"tick_dmg_player": 0, "tick_dmg_enemy": 0,
		"blocks": false, "blocks_beam": false, "heal": 0, "burns_to": "", "convertible": false,
	},
	"ash": {
		"corruption": true, "shields_core": false, "flammable": false, "washable": true,
		"bloom": 1, "ttl": 0, "decays": false,
		"enter_dmg_player": 0, "enter_dmg_enemy": 0, "enter_src": "",
		"tick_dmg_player": 0, "tick_dmg_enemy": 0,
		"blocks": false, "blocks_beam": false, "heal": 0, "burns_to": "", "convertible": true,
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


const ENEMIES := {
	"drill_bot": {"name": "Drill Bot", "hp": 3, "dmg": 2, "slow": false, "traits": ["fuses"]},
	"oil_sludge": {"name": "Oil Sludge", "hp": 4, "dmg": 1, "slow": true, "traits": ["splits", "oil_trail"]},
	"sludgeling": {"name": "Sludgeling", "hp": 1, "dmg": 1, "slow": false, "traits": []},
	"leech_drone": {"name": "Leech Drone", "hp": 2, "dmg": 0, "slow": false, "traits": ["drains"], "drain": 2, "drain_range": 2},
	"tar_spitter": {"name": "Tar Spitter", "hp": 2, "dmg": 0, "slow": false, "traits": ["gums"], "gum_range": 3, "gum_turns": 2},
	# Two drill bots welded into one by the combine's assimilation.
	"welded_hulk": {"name": "Welded Hulk", "hp": 7, "dmg": 2, "slow": true, "traits": ["spiked"]},
	# Spiked: melee strikes hurt the attacker - reach for a tool instead.
	"coal_golem": {"name": "Coal Golem", "hp": 4, "dmg": 2, "slow": true, "traits": ["smoke_burst", "spiked"]},
	"extractor_engine": {"name": "Extractor Engine", "hp": 5, "dmg": 0, "slow": false, "traits": ["summons"], "summon_cycle": 3},
	"rust_hound": {"name": "Rust Hound", "hp": 2, "dmg": 1, "slow": false, "traits": ["spiked", "fast"]},
	"cinder_mite": {"name": "Cinder Mite", "hp": 1, "dmg": 1, "slow": false, "traits": ["igniter"]},
	"pump_jack": {"name": "Pump Jack", "hp": 4, "dmg": 0, "slow": false, "traits": ["oozes"], "ooze_cycle": 2},
	# Stationary clock attacker: every stoke_cycle turns the smog clock ticks
	# an extra time while it lives. Kill it (tempo cost) or race it.
	"smokestack": {"name": "Smokestack", "hp": 4, "dmg": 0, "slow": false, "traits": ["stokes"], "stoke_cycle": 2},
	# Position disruptor: drags the player one tile toward itself each turn
	# while in range - punishes pure kiting, feeds melee packs.
	"magnet_crane": {"name": "Magnet Crane", "hp": 3, "dmg": 0, "slow": false, "traits": ["drags"], "drag_range": 3},
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
