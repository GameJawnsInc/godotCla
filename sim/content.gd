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
		"effects": [{"op": "lance", "dmg": 2, "clear_smog_bonus": 1, "ignite": true}],
	},
	"seed_bomb": {
		"name": "Seed Bomb", "cost": 2, "target": "tile", "range": 3,
		"effects": [{"op": "grow_radius", "radius": 1}],
	},
	"vine_whip": {
		"name": "Vine Whip", "cost": 1, "target": "enemy_line", "range": 3,
		"effects": [{"op": "pull", "dist": 2, "dmg": 1}],
	},
	"water_jet": {
		"name": "Water Jet", "cost": 1, "target": "dir", "range": 2,
		"effects": [{"op": "wash_push", "push": 2, "collision_dmg": 1}],
	},
	"mycelium_dash": {
		"name": "Mycelium Dash", "cost": 1, "target": "growth", "range": 4,
		"effects": [{"op": "teleport"}],
	},
	"root_wall": {
		"name": "Root Wall", "cost": 2, "target": "tile", "range": 2,
		"effects": [{"op": "grow_wall", "ttl": 4}],
	},
	"pollen_burst": {
		"name": "Pollen Burst", "cost": 2, "target": "self", "range": 2,
		"effects": [{"op": "aoe_status", "status": "stun", "turns": 1, "radius": 2}],
	},
	"sun_flare": {
		"name": "Sun Flare", "cost": 2, "target": "self", "range": 2,
		"effects": [{"op": "aoe_damage", "dmg": 1, "radius": 2, "ignite": true}],
	},
	"thorn_shield": {
		"name": "Thorn Shield", "cost": 1, "target": "self", "range": 0,
		"effects": [{"op": "shield", "amount": 2}],
	},
	"overgrowth": {
		"name": "Overgrowth", "cost": 1, "target": "tile_any", "range": 2,
		"effects": [{"op": "convert_radius", "radius": 1}],
	},
	"sap_snare": {
		"name": "Sap Snare", "cost": 1, "target": "enemy", "range": 3,
		"effects": [{"op": "apply_status", "status": "root", "turns": 2}],
	},
	"grow_spike": {
		"name": "Grow Spike", "cost": 1, "target": "enemy_near_growth", "range": 3,
		"effects": [{"op": "damage", "dmg": 3}],
	},
	"spore_cloud": {
		"name": "Spore Cloud", "cost": 2, "target": "self", "range": 2,
		"effects": [{"op": "aoe_status", "status": "spore", "turns": 3, "radius": 2}],
	},
	"fungal_ring": {
		"name": "Fungal Ring", "cost": 1, "target": "self", "range": 1,
		"effects": [{"op": "grow_radius", "radius": 1}],
	},
	"burrow": {
		"name": "Burrow", "cost": 2, "target": "tile", "range": 3,
		"effects": [{"op": "teleport"}],
	},
	"tide": {
		"name": "Tide", "cost": 2, "target": "self", "range": 2,
		"effects": [{"op": "wash_all", "push": 2, "collision_dmg": 1}],
	},
	"steam_vent": {
		"name": "Steam Vent", "cost": 1, "target": "tile_any", "range": 3,
		"effects": [{"op": "create_terrain", "kind": "smoke", "ttl": 3}],
	},
	"geyser": {
		"name": "Geyser", "cost": 2, "target": "self", "range": 1,
		"effects": [{"op": "aoe_damage", "dmg": 1, "radius": 1}, {"op": "push_all", "dist": 2}],
	},
	"gust": {
		"name": "Gust", "cost": 1, "target": "dir", "range": 3,
		"effects": [{"op": "push_line", "dist": 3, "clear_smoke": true}],
	},
	"updraft": {
		"name": "Updraft", "cost": 1, "target": "dir", "range": 3,
		"effects": [{"op": "dash_dir"}],
	},
	"clear_air": {
		"name": "Clear Air", "cost": 2, "target": "self", "range": 3,
		"effects": [{"op": "clear_smoke", "radius": 3}, {"op": "push_all", "dist": 1}],
	},
	"bramble_coat": {
		"name": "Bramble Coat", "cost": 1, "target": "self", "range": 0,
		"effects": [{"op": "thorns", "dmg": 2, "turns": 4}],
	},
	# Upgraded variants: offered in drafts when the base is owned; replace in place.
	"solar_lance+": {
		"name": "Solar Lance+", "cost": 2, "target": "dir", "range": 4,
		"effects": [{"op": "lance", "dmg": 3, "clear_smog_bonus": 1, "ignite": true}],
	},
	"seed_bomb+": {
		"name": "Seed Bomb+", "cost": 1, "target": "tile", "range": 3,
		"effects": [{"op": "grow_radius", "radius": 1}],
	},
	"vine_whip+": {
		"name": "Vine Whip+", "cost": 1, "target": "enemy_line", "range": 4,
		"effects": [{"op": "pull", "dist": 3, "dmg": 2}],
	},
	"water_jet+": {
		"name": "Water Jet+", "cost": 1, "target": "dir", "range": 3,
		"effects": [{"op": "wash_push", "push": 3, "collision_dmg": 2}],
	},
	"mycelium_dash+": {
		"name": "Mycelium Dash+", "cost": 1, "target": "growth", "range": 7,
		"effects": [{"op": "teleport"}],
	},
	"root_wall+": {
		"name": "Root Wall+", "cost": 1, "target": "tile", "range": 2,
		"effects": [{"op": "grow_wall", "ttl": 6}],
	},
	"pollen_burst+": {
		"name": "Pollen Burst+", "cost": 2, "target": "self", "range": 2,
		"effects": [{"op": "aoe_status", "status": "stun", "turns": 2, "radius": 2}],
	},
	"sun_flare+": {
		"name": "Sun Flare+", "cost": 2, "target": "self", "range": 2,
		"effects": [{"op": "aoe_damage", "dmg": 2, "radius": 2, "ignite": true}],
	},
	"thorn_shield+": {
		"name": "Thorn Shield+", "cost": 1, "target": "self", "range": 0,
		"effects": [{"op": "shield", "amount": 3}],
	},
	"overgrowth+": {
		"name": "Overgrowth+", "cost": 1, "target": "tile_any", "range": 3,
		"effects": [{"op": "convert_radius", "radius": 2}],
	},
	"sap_snare+": {
		"name": "Sap Snare+", "cost": 1, "target": "enemy", "range": 4,
		"effects": [{"op": "apply_status", "status": "root", "turns": 3}],
	},
	"grow_spike+": {
		"name": "Grow Spike+", "cost": 1, "target": "enemy_near_growth", "range": 4,
		"effects": [{"op": "damage", "dmg": 4}],
	},
	"bramble_coat+": {
		"name": "Bramble Coat+", "cost": 1, "target": "self", "range": 0,
		"effects": [{"op": "thorns", "dmg": 3, "turns": 5}],
	},
}

## Abilities that can appear in descent drafts. Mobility stays fixed for now.
const DRAFT_POOL := [
	"solar_lance", "seed_bomb", "vine_whip", "water_jet", "root_wall",
	"pollen_burst", "sun_flare", "thorn_shield", "overgrowth", "sap_snare",
	"grow_spike", "bramble_coat",
]

## Grafts: passive run-long modifiers (the relic analog). Pure data; the sim
## consults owned grafts at the relevant decision points.
const GRAFTS := {
	"deep_cells": {"name": "Deep Cells", "desc": "+2 bank cap"},
	"verdant_pulse": {"name": "Verdant Pulse", "desc": "growth heals +1"},
	"thick_bark": {"name": "Thick Bark", "desc": "+2 shield cap"},
	"bloom_surge": {"name": "Bloom Surge", "desc": "cleansing yields +1 bloom"},
	"solar_core": {"name": "Solar Core", "desc": "+1 charge regen"},
	"carapace": {"name": "Carapace", "desc": "start each floor with 2 shield"},
}

const SHOP_COSTS := {"heal": 3, "ability": 4, "graft": 5}

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

const ENEMIES := {
	"drill_bot": {"name": "Drill Bot", "hp": 3, "dmg": 2, "slow": false, "traits": []},
	"oil_sludge": {"name": "Oil Sludge", "hp": 4, "dmg": 1, "slow": true, "traits": ["splits", "oil_trail"]},
	"sludgeling": {"name": "Sludgeling", "hp": 1, "dmg": 1, "slow": false, "traits": []},
	"leech_drone": {"name": "Leech Drone", "hp": 2, "dmg": 0, "slow": false, "traits": ["drains"], "drain": 2, "drain_range": 2},
	"tar_spitter": {"name": "Tar Spitter", "hp": 2, "dmg": 0, "slow": false, "traits": ["gums"], "gum_range": 3, "gum_turns": 2},
	"coal_golem": {"name": "Coal Golem", "hp": 4, "dmg": 2, "slow": true, "traits": ["smoke_burst"]},
	"extractor_engine": {"name": "Extractor Engine", "hp": 5, "dmg": 0, "slow": false, "traits": ["summons"], "summon_cycle": 3},
	"rust_hound": {"name": "Rust Hound", "hp": 2, "dmg": 1, "slow": false, "traits": ["fast"]},
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
		"oil": 4, "goo": 2, "vents": 1,
		"smog_spawn": [10, 20], "smog_spawn_every": 12, "smog_dim": [14, 22], "smog_choke": 38,
	},
	{
		"name": "Strip Mine II", "biome": "strip_mine", "w": 24, "h": 15, "rooms": 5,
		"enemies": {"drill_bot": 1, "oil_sludge": 1, "leech_drone": 1, "tar_spitter": 1},
		"oil": 6, "goo": 3, "vents": 2, "vaults": ["old_garden"],
		"smog_spawn": [9, 17], "smog_spawn_every": 10, "smog_dim": [12, 20], "smog_choke": 36,
	},
	{
		"name": "Refinery Gate", "biome": "refinery", "w": 26, "h": 16, "rooms": 5,
		"enemies": {"drill_bot": 1, "oil_sludge": 1, "leech_drone": 1, "tar_spitter": 1, "coal_golem": 1},
		"oil": 8, "goo": 4, "vents": 2, "elites": 1, "vaults": ["tar_hoard", "old_garden"], "pipes": 1,
		"smog_spawn": [10, 18], "smog_spawn_every": 11, "smog_dim": [14, 22], "smog_choke": 36,
	},
	{
		"name": "Cracking Yard", "biome": "refinery", "w": 26, "h": 16, "rooms": 6,
		"enemies": {"drill_bot": 1, "oil_sludge": 1, "tar_spitter": 1, "extractor_engine": 1, "rust_hound": 1, "magnet_crane": 1},
		"oil": 9, "goo": 4, "vents": 2, "vaults": ["oil_spill", "tar_hoard"], "pipes": 1,
		"smog_spawn": [12, 22], "smog_spawn_every": 12, "smog_dim": [14, 22], "smog_choke": 34,
	},
	{
		"name": "Pipeworks", "biome": "refinery", "w": 28, "h": 16, "rooms": 6,
		"enemies": {"drill_bot": 1, "oil_sludge": 1, "coal_golem": 1, "extractor_engine": 1, "pump_jack": 1, "rust_hound": 1, "smokestack": 1},
		"oil": 10, "goo": 5, "vents": 3, "elites": 1, "vaults": ["oil_spill", "tar_hoard", "fuel_depot"], "pipes": 2,
		"smog_spawn": [12, 20], "smog_spawn_every": 12, "smog_dim": [13, 21], "smog_choke": 32,
	},
	{
		"name": "Furnace Approach", "biome": "furnace", "w": 28, "h": 17, "rooms": 6,
		"enemies": {"drill_bot": 1, "coal_golem": 2, "tar_spitter": 1, "extractor_engine": 1, "cinder_mite": 2, "smokestack": 1},
		"oil": 12, "goo": 5, "vents": 3, "elites": 1, "vaults": ["fuel_depot", "tar_hoard", "sacred_grove"], "pipes": 2,
		"smog_spawn": [10, 18], "smog_spawn_every": 11, "smog_dim": [12, 20], "smog_choke": 30,
	},
	{
		"name": "The Furnace", "biome": "furnace", "boss": true, "w": 20, "h": 12,
		"bosses": ["furnace_core", "overseer", "the_dredge"],
		"enemies": {}, "oil": 6, "goo": 0, "vents": 2, "rooms": 0,
		"smog_spawn": [12, 24], "smog_spawn_every": 12, "smog_dim": [16, 26], "smog_choke": 44,
	},
]
