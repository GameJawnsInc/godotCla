extends RefCounted
## Static content tables. Adding content means adding data (style guide §6).

const PLAYER_HP := 10
const BASE_REGEN := 3
const BANK_CAP := 6
const MOVE_COST := 1
const STRIKE_COST := 1
const STRIKE_DMG := 1
const CLEANSE_COST := 1

const STARTING_KIT := ["solar_lance", "seed_bomb", "vine_whip", "water_jet", "mycelium_dash"]

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
}

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
		"smog_spawn": [10, 20], "smog_spawn_every": 12, "smog_dim": [14, 22],
	},
	{
		"name": "Strip Mine II", "w": 24, "h": 15, "rooms": 5,
		"enemies": {"drill_bot": 2, "oil_sludge": 1, "leech_drone": 1},
		"oil": 6, "goo": 3, "vents": 2,
		"smog_spawn": [9, 17], "smog_spawn_every": 10, "smog_dim": [12, 20],
	},
	{
		"name": "Refinery Gate", "w": 26, "h": 16, "rooms": 5,
		"enemies": {"drill_bot": 3, "oil_sludge": 2, "leech_drone": 1},
		"oil": 8, "goo": 4, "vents": 2,
		"smog_spawn": [8, 14, 20], "smog_spawn_every": 8, "smog_dim": [10, 18],
	},
]
