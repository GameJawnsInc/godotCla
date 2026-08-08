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
}

## Abilities that can appear in descent drafts. Mobility stays fixed for now.
const DRAFT_POOL := [
	"solar_lance", "seed_bomb", "vine_whip", "water_jet", "root_wall",
	"pollen_burst", "sun_flare", "thorn_shield", "overgrowth", "sap_snare",
	"grow_spike",
]

const ENEMIES := {
	"drill_bot": {"name": "Drill Bot", "hp": 3, "dmg": 2, "slow": false, "traits": []},
	"oil_sludge": {"name": "Oil Sludge", "hp": 4, "dmg": 1, "slow": true, "traits": ["splits", "oil_trail"]},
	"sludgeling": {"name": "Sludgeling", "hp": 1, "dmg": 1, "slow": false, "traits": []},
	"leech_drone": {"name": "Leech Drone", "hp": 2, "dmg": 0, "slow": false, "traits": ["drains"], "drain": 2, "drain_range": 2},
}

const FLOORS := [
	{
		"name": "Strip Mine I", "w": 22, "h": 14, "rooms": 4,
		"enemies": {"drill_bot": 2},
		"oil": 4, "goo": 2, "vents": 1,
		"smog_spawn": [10, 20], "smog_spawn_every": 12, "smog_dim": [14, 22], "smog_choke": 38,
	},
	{
		"name": "Strip Mine II", "w": 24, "h": 15, "rooms": 5,
		"enemies": {"drill_bot": 2, "oil_sludge": 1, "leech_drone": 1},
		"oil": 6, "goo": 3, "vents": 2,
		"smog_spawn": [9, 17], "smog_spawn_every": 10, "smog_dim": [12, 20], "smog_choke": 36,
	},
	{
		"name": "Refinery Gate", "w": 26, "h": 16, "rooms": 5,
		"enemies": {"drill_bot": 2, "oil_sludge": 2, "leech_drone": 1},
		"oil": 8, "goo": 4, "vents": 2,
		"smog_spawn": [8, 16], "smog_spawn_every": 10, "smog_dim": [12, 20], "smog_choke": 34,
	},
]
