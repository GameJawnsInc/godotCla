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
	# --- Evolve forks (Block D6, docs/PROGRESSION_REVIEW.md 6.4) --------------
	# Each of the fifteen base abilities has TWO named variants keyed
	# "<base>+<word>" (never a grade: no "+2", no "Greater"). Variant A of each
	# pair is the pre-D6 "<base>+" row verbatim - same cost, target, range,
	# effects, riders, surge, tags and role - renamed, so the measured balance
	# point is preserved and every number D6 moves is attributable to B alone.
	# Variant B forks: a different shape, target class, status, count or
	# terrain, never a bigger number on the same line.
	# TABLE ORDER IS LOAD-BEARING: Content.variants_of scans these keys, and
	# the draft's parity pick indexes that list, so A must be listed FIRST for
	# every base (parity = the floor being entered, so A is dealt on even
	# floors and B on odd; drafts happen on floors 2..7, so both siblings are
	# draftable inside one run and neither is ever unobtainable - and the
	# shrine forge lists one action per variant, so a run can always buy the
	# sibling this floor's parity cannot deal).
	# EXEMPTION from the C4 package convention ("numeric bumps only"): five B
	# rows are SIDEGRADES of their own base rather than supersets -
	# root_wall+cage (loses the `tile` shape for a body), sap_snare+blight (a
	# different status, not a longer one), grow_spike+throng (a different `per`
	# count), bramble_coat+bristle (5 dmg over 2 turns against the base's
	# 2 over 4) and overgrowth+palisade (roots instead of growth). The fork
	# axis for those five IS shape/status/count, and there is no way to fork
	# those without giving something up. The other ten Bs are strictly better
	# than their base.
	# DEFAULT SURGE, worth stating because it qualifies four fork prices: the
	# D1 rule (Game._surges with Content.SURGE_DEFAULT {cost: -1}) surges ANY
	# cast of cost >= 2 made while standing on growth, whatever the row. Four B
	# rows crossed to cost 2 and are therefore cost-1 casts FROM GROWTH, at the
	# price of the tile underfoot: seed_bomb+reclaim, root_wall+cage,
	# pollen_burst+drift and moss_filter+prism. (solar_lance+pierce is cost 2
	# too and surges the same way, but so does its cost-2 A sibling, so the
	# discount is not part of that fork; solar_lance+noon and
	# pollen_burst+torpor always surged.) So
	# "costs twice as much as its sibling" in the notes below is the price OFF
	# growth; reclaim in particular is a growth-WRITING card that eats the
	# growth it is cast from.
	"solar_lance+noon": {
		"name": "Noon Lance", "cost": 2, "target": "dir", "range": 4,
		"effects": [{"op": "lance", "dmg": 3, "clear_smog_bonus": 1, "ignite": true}],
		"tags": ["sun", "fire"], "role": "damage",
	},
	# pierce: the beam does not break on the first body, so oil BEHIND an
	# enemy becomes lightable at all (the base lance cannot reach it at any
	# price). Walls and blocks_beam smoke still stop the walk.
	"solar_lance+pierce": {
		"name": "Piercing Lance", "cost": 2, "target": "dir", "range": 4,
		"effects": [{"op": "lance", "dmg": 2, "clear_smog_bonus": 0, "ignite": true, "pierce": true}],
		"tags": ["sun", "fire"], "role": "damage",
	},
	"seed_bomb+tangle": {
		"name": "Tangle Bomb", "cost": 1, "target": "tile", "range": 3,
		"effects": [{"op": "grow_radius", "radius": 1, "then": [{"op": "status_target", "status": "root", "turns": 1, "who": "on_planted"}]}],
		"surge": {"radius": 1},
		"tags": ["growth"], "role": "setup",
	},
	# tile_any is load-bearing: the "tile" shape excludes tiles that already
	# hold terrain, so the plain bomb cannot even be AIMED at a slick.
	"seed_bomb+reclaim": {
		"name": "Reclaimer Bomb", "cost": 2, "target": "tile_any", "range": 3,
		"effects": [{"op": "grow_radius", "radius": 1}, {"op": "convert_radius", "radius": 1}],
		"tags": ["growth"], "role": "setup",
	},
	"vine_whip+lash": {
		"name": "Vine Lash", "cost": 1, "target": "enemy_line", "range": 4,
		"effects": [{"op": "pull", "dist": 3, "dmg": 3, "then": [{"op": "status_target", "status": "stun", "turns": 1, "if": [{"outcome_crossed": "fire"}]}]}],
		"tags": ["displace"], "role": "damage",
	},
	# the base whip's numbers over a whole line: the pool's cheapest mass
	# interrupt, and the gatherer its area payoffs have no setup for
	"vine_whip+rake": {
		"name": "Vine Rake", "cost": 1, "target": "dir_enemy", "range": 3,
		"effects": [{"op": "pull_line", "dist": 2, "dmg": 2}],
		"tags": ["displace"], "role": "damage",
	},
	"water_jet+pin": {
		"name": "Pinning Jet", "cost": 1, "target": "dir", "range": 3,
		"effects": [{"op": "wash_push", "push": 3, "collision_dmg": 3, "then": [{"op": "status_target", "status": "root", "turns": 1, "if": [{"outcome": "collided"}, {"outcome": "pushed"}]}]}],
		"surge": {"push": 1, "collision_dmg": 1},
		"tags": ["water", "displace"], "role": "damage",
	},
	# the hose half: _wash_dir erases every washable tile on the whole line
	# regardless of enemies, so range 5 really does wash five tiles
	"water_jet+sluice": {
		"name": "Sluice Jet", "cost": 1, "target": "dir", "range": 5,
		"effects": [{"op": "wash_push", "push": 2, "collision_dmg": 2}],
		"surge": {"push": 1, "collision_dmg": 1},
		"tags": ["water", "displace"], "role": "damage",
	},
	# Spore Trail (Block D1): the departure tile becomes growth once the tender
	# has left it (plant_origin - floor, no terrain, no enemy standing there).
	"mycelium_dash+trail": {
		"name": "Spore Trail", "cost": 1, "target": "growth", "range": 7,
		"effects": [{"op": "teleport"}, {"op": "plant_origin", "kind": "growth"}],
		"tags": ["mobility"], "role": "mobility",
	},
	# effects run in order and aoe_damage reads player["pos"], which teleport
	# has already moved: the burst lands where you ARRIVE, no `center` needed
	"mycelium_dash+scatter": {
		"name": "Scattering Dash", "cost": 1, "target": "growth", "range": 4,
		"effects": [{"op": "teleport"}, {"op": "aoe_damage", "dmg": 1, "radius": 1}],
		"tags": ["mobility"], "role": "mobility",
	},
	"root_wall+bulwark": {
		"name": "Bulwark Roots", "cost": 1, "target": "tile", "range": 2,
		"effects": [{"op": "grow_wall", "ttl": 6}],
		"tags": ["growth", "bark"], "role": "setup",
	},
	# aimed at a BODY: grow_wall needs _open(t), which is false where an enemy
	# stands and where the tender stands, so a cage fills exactly the target's
	# free neighbours - the one card in the base pool that stops a massive
	# enemy, since passability does not care what statuses bounce off it
	"root_wall+cage": {
		"name": "Root Cage", "cost": 2, "target": "enemy", "range": 3,
		"effects": [{"op": "grow_wall", "ttl": 4}],
		"tags": ["growth", "bark"], "role": "setup",
	},
	"pollen_burst+torpor": {
		"name": "Torpor Burst", "cost": 2, "target": "self", "range": 2,
		"effects": [{"op": "aoe_status", "status": "stun", "turns": 2, "radius": 2}],
		"tags": ["control"], "role": "control",
	},
	# center: "target" measures the radius from the cast tile, so the cloud
	# stuns the clump where it FORMS instead of only where you are standing
	"pollen_burst+drift": {
		"name": "Pollen Drift", "cost": 2, "target": "tile_any", "range": 3,
		"effects": [{"op": "aoe_status", "status": "stun", "turns": 1, "radius": 2, "center": "target"}],
		"tags": ["control"], "role": "control",
	},
	"sun_flare+corona": {
		"name": "Corona Flare", "cost": 2, "target": "self", "range": 2,
		"effects": [{"op": "aoe_damage", "dmg": 2, "radius": 2, "ignite": true, "bonus": {"dmg": 1, "if": [{"target_on": ["fire"]}]}}],
		"surge": {"cost": -1, "radius": 1},
		"tags": ["sun", "fire"], "role": "damage",
	},
	# ignite_ttl: the flash is the base's 1, the FIRE is twice as long. Since
	# D3 that is a positional statement - seven enemy rows avoid fire and pay
	# ENEMY_AVOID_COST per burning tile - and the burn stands in the tender's
	# way just as long. A fire that spreads from an overridden tile takes the
	# table ttl, so a long burn does not propagate its length.
	"sun_flare+smoulder": {
		"name": "Smouldering Flare", "cost": 2, "target": "self", "range": 2,
		"effects": [{"op": "aoe_damage", "dmg": 1, "radius": 2, "ignite": true, "ignite_ttl": 4,
			"bonus": {"dmg": 1, "if": [{"target_on": ["fire"]}]}}],
		"surge": {"cost": -1, "radius": 1},
		"tags": ["sun", "fire"], "role": "damage",
	},
	"thorn_shield+plate": {
		"name": "Plate Bark", "cost": 1, "target": "self", "range": 0,
		"effects": [{"op": "shield", "amount": 3}],
		"tags": ["bark"], "role": "defense",
	},
	# SHIELD_CAP is 3, so the absorption axis is finished and B forks sideways:
	# the smoke is a D3 screen (Game._screened reads the tender's tile and its
	# four neighbours), so drain/gum/drag from a non-adjacent, non-massive
	# enemy fizzles for two turns. Two self-limits ship with it: create_terrain
	# needs a bare floor tile (no cloud while standing on your own growth), and
	# smoke blocks_beam, so camping in it gives up lance and enemy_line lines.
	"thorn_shield+chaff": {
		"name": "Chaff Bark", "cost": 1, "target": "self", "range": 0,
		"effects": [{"op": "shield", "amount": 2}, {"op": "create_terrain", "kind": "smoke", "ttl": 2}],
		"tags": ["bark"], "role": "defense",
	},
	"overgrowth+sprawl": {
		"name": "Sprawling Growth", "cost": 1, "target": "tile_any", "range": 3,
		"effects": [{"op": "convert_radius", "radius": 2}],
		"tags": ["growth"], "role": "setup",
	},
	# kind + ttl: the same input, a different product - the only card that
	# manufactures cover out of the enemy's own terrain, and the only thing
	# that makes anything of goo. Quota relief is identical either way.
	"overgrowth+palisade": {
		"name": "Palisade", "cost": 1, "target": "tile_any", "range": 2,
		"effects": [{"op": "convert_radius", "radius": 1, "kind": "roots", "ttl": 3}],
		"tags": ["growth"], "role": "setup",
	},
	"sap_snare+tether": {
		"name": "Tether Snare", "cost": 1, "target": "enemy", "range": 4,
		"effects": [{"op": "apply_status", "status": "root", "turns": 3}],
		"tags": ["control"], "role": "control",
	},
	# which status the sap carries: spore blocks nothing but ticks, has no
	# cooldown and is the one STATUSES row that stacks by addition - so a
	# second dose really does stack, which root's cooldown forbids
	"sap_snare+blight": {
		"name": "Blight Snare", "cost": 1, "target": "enemy", "range": 3,
		"effects": [{"op": "apply_status", "status": "spore", "turns": 3}],
		"tags": ["control"], "role": "control",
	},
	"grow_spike+impale": {
		"name": "Impaling Spike", "cost": 1, "target": "enemy_near_growth", "range": 4,
		"effects": [{"op": "damage", "dmg": 3, "per": {"count": "growth_adjacent_target", "cap": 2, "add": {"dmg": 1}}}],
		"surge": {"dmg": 1},
		"tags": ["growth"], "role": "payoff",
	},
	# activates enemies_adjacent_target, the one PER_COUNTS entry no shipped
	# row used: the payoff card for the displace half of the pool
	"grow_spike+throng": {
		"name": "Throng Spike", "cost": 1, "target": "enemy_near_growth", "range": 3,
		"effects": [{"op": "damage", "dmg": 3, "per": {"count": "enemies_adjacent_target", "cap": 2, "add": {"dmg": 1}}}],
		"surge": {"dmg": 1},
		"tags": ["growth"], "role": "payoff",
	},
	"bramble_coat+briar": {
		"name": "Briar Coat", "cost": 1, "target": "self", "range": 0,
		"effects": [{"op": "thorns", "dmg": 3, "turns": 5}],
		"tags": ["bark"], "role": "defense",
	},
	# a parry, not a posture: 5 crosses the HP line of the only two 4-HP melee
	# kinds (coal_golem, oil_sludge) and the window has to be AIMED at a
	# telegraph. Deliberately not a growth-scaling coat: thorns is the
	# documented stall vector, so the bark fork that cannot be kept up wins.
	"bramble_coat+bristle": {
		"name": "Bristle Coat", "cost": 1, "target": "self", "range": 0,
		"effects": [{"op": "thorns", "dmg": 5, "turns": 2}],
		"tags": ["bark"], "role": "defense",
	},
	"anchor_roots+bedrock": {
		"name": "Bedrock Anchor", "cost": 1, "target": "self", "range": 0,
		"effects": [{"op": "anchor", "turns": 7}],
		"tags": ["bark"], "role": "defense",
	},
	# the base's four turns plus something that happens NOW. Grants no shield,
	# heal, thorns or cleanse credit, so it stays off the stall surface.
	"anchor_roots+heave": {
		"name": "Heaving Roots", "cost": 1, "target": "self", "range": 1,
		"effects": [{"op": "anchor", "turns": 4}, {"op": "push_all", "dist": 1}],
		"tags": ["bark"], "role": "defense",
	},
	"moss_filter+sieve": {
		"name": "Fine Sieve", "cost": 1, "target": "self", "range": 0,
		"effects": [{"op": "undim", "amount": 1}],
		"tags": ["sun"], "role": "utility",
	},
	# a castability fork, not a value one: regen is maxi(1, BASE_REGEN - dim),
	# so at dim 2 the cost-1 sieve is castable on income and this is not - OFF
	# growth. See the default-surge note below: standing on growth this costs 1
	# too, at the price of the tile.
	# Effects run in order, so undim resolves first and the flare's if reads
	# the stage the cast just produced - the reward exists only on the floors
	# where the smog is already being beaten. First shipped user of `dim`.
	"moss_filter+prism": {
		"name": "Prism Moss", "cost": 2, "target": "self", "range": 2,
		"effects": [{"op": "undim", "amount": 1},
			{"op": "aoe_damage", "dmg": 1, "radius": 2, "if": [{"dim": 0}]}],
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
## Block D6 (evolve forks): the "+ forms of held bases" the upgrade slot and
## the universe draw from are now VARIANTS - each of the fifteen base-pool
## abilities has two, keyed "<base>+<word>". The upgrade slot lists ONE per
## held build-defining base, picked by Content.variant_for(base, floor) - a
## parity read of the floor being entered, never a draw, so this file's
## one-main-rng-draw-per-slot contract is untouched. The wild slot's universe
## holds BOTH siblings of every held base, and the shrine forge lists one
## action per variant, so no fork is unobtainable: the sibling a floor's
## parity cannot deal is reachable on the next floor and at every shrine.
## Every target shape Game._ability_targets can generate, and therefore every
## value an ABILITIES row's "target" may take (tests/test_content.gd lints it).
## "dir" and "dir_enemy" both hand the effect a unit vector - Game._is_dir_shape
## is the one reader of that fact - and differ only in legality: "dir" offers
## all four directions always, "dir_enemy" only a direction whose line holds an
## enemy within range, which is what a cast doing nothing to an empty line
## needs (Block D6, vine_whip+rake).
const TARGET_SHAPES := [
	"dir", "dir_enemy", "tile", "tile_any", "enemy", "enemy_line",
	"enemy_near_growth", "growth", "self",
]

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


## Strip the upgrade suffix: "solar_lance+noon" -> "solar_lance". Ids without
## a "+" come back unchanged. Unchanged by Block D6: it already cuts at the
## first "+", so a "<base>+<variant>" key folds onto its base like the old
## "<base>+" did.
static func base_id(aid: String) -> String:
	var cut: int = aid.find("+")
	if cut < 0:
		return aid
	return aid.substr(0, cut)


## Is `aid` an upgrade (a "+" form of some base) rather than a base itself?
## THE ONE TEST TO USE. Block D6 renamed every base "+" row to
## "<base>+<variant>", so "solar_lance+pierce".ends_with("+") is FALSE:
## an ends_with("+") on an ABILITY id silently changed meaning and must be
## this call (or an explicit base_id comparison) everywhere. The ITEMS press
## keeps the plain "+" convention - items are not forked - so its sites keep
## ends_with("+") on purpose.
static func is_upgrade(aid: String) -> bool:
	return base_id(aid) != aid


## Every upgrade variant of `base`, in ABILITIES table order (the order is
## load-bearing: variant_for indexes this list, so a base's variant A must be
## listed before its B). Derived by scanning, never a hand-maintained list, so
## a new row is a new variant with no second place to update. Two entries for
## each of the fifteen base-pool abilities (Block D6), one for each package
## ability (those keep their single plain "+" form), zero for an id that has
## no upgrade at all.
static func variants_of(base: String) -> Array:
	var out: Array = []
	for aid in ABILITIES.keys():
		var key := String(aid)
		if key != base and base_id(key) == base:
			out.append(key)
	return out


## The variant of `base` this draft may deal, chosen by PARITY - no rng draw,
## so the draft's one-main-rng-draw-per-slot contract is untouched and WHICH
## sibling a slot could offer is a function of the floor, not of a roll.
## `parity` is the floor being entered (Game._pending_floor), and drafts
## happen on floors 2..7, so a run sees variant A on even floors and B on odd
## and both siblings are draftable inside one run. The sibling a given floor
## cannot deal is always buyable at the shrine forge, which lists one action
## per variant - no fork is ever unobtainable. "" when `base` has no variant.
static func variant_for(base: String, parity: int) -> String:
	var vs: Array = variants_of(base)
	if vs.is_empty():
		return ""
	return String(vs[posmod(parity, vs.size())])


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
##   stat:  {key: int}   summed over held grafts AND the active resonances
##          (Content.RESONANCES) by Game._passive_stat(key);
##          keys: bank_cap, shield_cap, regen, regen_on_growth, growth_heal,
##          cleanse_bloom (regen_on_growth is added to regen only on the turns
##          the tender begins standing on growth; no shipped row uses it - it
##          exists so a conditional alternative to solar_core can be measured)
##   mod:   {key: value} first value wins over the held grafts then the
##          active resonances, Game._passive_mod(key, default);
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

## Resonances as data (Block D5, docs/PROGRESSION_REVIEW.md 6.4 "one resonance
## per element"). A run's kit and grafts carry TAGS; when the count of one tag
## reaches that row's `need` the element RESONATES and its row takes effect for
## the rest of the run - and stops the moment the count drops again (a draft
## drop, a forge scrap; grafts are only ever appended, so a graft-borne count
## can only rise). Nothing is stored: Game._tag_counts and Game._resonances
## derive the set on every read, so a resonance never enters state_hash() and
## cannot by itself desync a replay.
##
## A row is {name, desc, tag, need} plus EXACTLY ONE of:
##   stat:  {key: int}   summed with the held grafts by Game._passive_stat
##   mod:   {key: value} scanned after the grafts by Game._passive_mod, so a
##                       graft mod shadows a resonance mod (first hit wins)
##   hooks: [rows]       run by Game._hook, which scans kit rows, then grafts,
##                       then the active resonances in the key order below
## - the same three-way choice a GRAFTS row makes, read by the same machinery
## with the ROW ID as the source id, so cap_per_turn, hook_uses and
## tests/tally.gd need no change. D5 adds a SOURCE, not a system: no new op,
## stat key, mod key, hook kind, predicate or terrain key.
##
## KEY ORDER IS LOAD-BEARING: it is the hook scan order after the grafts and
## the order of snapshot()["resonances"]. Rows are listed in TAGS order.
## Ids are NAMES, never tags ("cinder_grip", not "fire"): the id shows up in
## {t: "hook", id}, in hook_uses and in the shell, where it has to read as a
## source. "One resonance per element" is therefore a lint rule and not a
## dictionary key - tests/test_content.gd rejects two rows on one tag, a row
## whose tag is in AFFINITY_IGNORED_TAGS (this is where "mobility never
## counts" lives, in data instead of an id literal in sim/game.gd), a `need`
## below 2, an id colliding with a GRAFTS or ABILITIES id (they share the
## hook_uses namespace) and a tag the content tables cannot reach `need` of.
## Hook rows go through the same lint as graft hooks, shield / thorns
## rejection included: a free permanent that grants survivability is the stall
## vector BALANCE.md documents.
##
## Resonance tags do NOT feed the D4 affinity set: Game._affinity_tags reads
## the kit and the grafts only, so the draft never chases a threshold that a
## resonance itself created.
##
## ONE row ships, on fire. The other ten tags ship nothing, on measured reach,
## on trigger rate, on vocabulary and - for the two that were authored and then
## cut - on their own measurements (BALANCE.md 2026-09-08, bump 14):
## mobility is lint-excluded; sun is 90% of tender optimizer runs at need 2 and
## double-pays off the two fire cards; water is an ability-side subset of
## displace; wind and smoke are package-locked (wind 2 is met from turn one on
## the skyrunner kit, the exact failure the roadmap bullet deferred this item
## on); bark's own seat (shield_break) fires 0.83 times a run and every payoff
## its vocabulary offers is survivability; control has NO event (nothing fires
## when a status lands); economy is carried by zero abilities; displace and
## growth each shipped a row that was cut, below.
##
## So no shipped row carries `stat` or `mod` today - both shapes are live data
## the lint and tests/test_grammar.gd keep exercised through fixture rows, not
## dead vocabulary.
##
## displace shipped a row in the D5 design phase and it was CUT on its own
## pre-registered falsifier before the bump landed. Follow Through was
## {tag: displace, need: 2, hooks: [{on: collision, effects:
## [{op: damage_at, dmg: 1}], cap_per_turn: 2}]} and the design phase declared:
## "if it totals fewer than 30 hooks over 30 optimizer runs on the locked kit
## [vine_whip, water_jet, seed_bomb, mycelium_dash] it should be cut rather
## than shipped as a fourth dead row". Measured on exactly that kit: 22 hooks
## in seeds 1..30 and 21 in 31..60 (0.73 and 0.70 per run against a predicted
## 2-6), of which only 5 landed any damage - the other 17 fired on a body the
## collision had already killed, because _damage_enemy erases the enemy before
## _hook runs, so damage_at finds no target. Free-drafting, the band persona
## reaches displace 2 in 3 of 30 runs and fires the row 0.00 times a run.
## The row is NOT dead at the ceiling (deeproot 8.8-9.1 hooks and ~6 damage a
## run on the same kit, 5.9% of its enemy damage), so it is a ceiling-only
## row - but a FREE permanent that pays only the search bot is not the
## build-identity payoff the block set out to ship, and the 45-65 band is read
## off the persona that never collects it. `need` is not the lever (the row is
## active on 30/30 of those runs and simply does not fire) and neither is
## cap_per_turn (it never binds at 0.73 hooks a run). Re-seating displace
## needs a trigger the collision hook cannot give: `collision` is the only
## displacement-shaped HOOK_KIND, and every closed stat/mod key is
## survivability, charge or bloom. So displace waits for vocabulary, exactly
## as control does. Re-adding the row is one dict entry if the owner wants the
## ceiling-only reading shipped anyway; the numbers are in BALANCE.md.
##
## growth shipped a row too, and it was CUT on the canary - by the owner, after
## the block was implemented. Deep Loam was {tag: growth, need: 3, stat:
## {regen_on_growth: 1}}: +1 charge on every turn BEGUN standing on growth, and
## the regen_on_growth key's first and only shipped consumer. It was not cut
## for failing to do anything - it was cut for what it pays FOR. Paired on the
## greed canary (magpie, spiker loadout, 300 seeds a setting) against the
## tests/playtest.gd gate MAGPIE_MAX_LOWER 0.10, which trips when the Wilson
## LOWER bound clears 10%:
##   row absent   38/300  12.7%  [ 9.4, 16.9]  pass   +0.0
##   need 3       56/300  18.7%  [14.7, 23.5]  FAIL   +6.0
##   need 4       48/300  16.0%  [12.3, 20.6]  FAIL   +3.3
##   need 5       39/300  13.0%  [ 9.7, 17.3]  pass   +0.3
## `need` was the design phase's pre-registered lever and it is the wrong one:
## there is no threshold at which the row both clears the canary and does
## anything, because its canary cost is PROPORTIONAL to its effect. The row
## pays per turn BEGUN on growth, and the greed persona spends about twice the
## share of its turns standing there that the skilled one does (magpie 23.6% of
## turns on tender / 26.7% on spiker, against optimizer 13.4% / 15.8%).
## Lingering on a floor to farm it IS standing on your own growth, so the row
## subsidises exactly the behaviour the canary exists to detect; raising `need`
## changes how OFTEN the row is on, never WHO it pays, which is why need 5 buys
## a pass by being switched off in most runs (+0.3 over the row's absence).
## Growth is therefore not a threshold problem but a payoff-SHAPE one, and it
## waits for a key that pays on an ACT - a cast, a plant, a cleanse - rather
## than on a turn spent in place; every closed stat/mod key today is
## survivability, charge or bloom, so that key does not exist yet. Re-adding
## the row is one dict entry; the numbers are in BALANCE.md.
const RESONANCES := {
	"cinder_grip": {
		"name": "Cinder Grip", "desc": "a machine standing on a tile as it catches fire is rooted a turn (3 times a turn)",
		"tag": "fire", "need": 3,
		"hooks": [{"on": "ignite", "effects": [{"op": "status_at", "status": "root", "turns": 1}], "cap_per_turn": 3}],
	},
}

## One-line effect text per ability (a + form without its own entry falls back
## to the base). Rider rows (docs/PROGRESSION_REVIEW.md 6.3 C2) name the rider
## in one clause. UI-facing data; the sim ignores it.
const ABILITY_DESC := {
	"solar_lance": "Beam up to 3 tiles: 2 dmg, ignites oil",
	"solar_lance+noon": "Beam 4 tiles: 3 dmg, 4 under clear skies, ignites oil",
	"solar_lance+pierce": "Beam 4 tiles that nothing but a wall or smoke stops: 2 dmg to every enemy on the line, and every oil tile behind them lights",
	"seed_bomb": "Plant a patch of healing growth within 3 tiles",
	"seed_bomb+tangle": "Plant a patch of healing growth within 3 tiles; enemies on the fresh growth are rooted a turn; on growth: plants a 13-tile diamond",
	"seed_bomb+reclaim": "Plant a patch of healing growth within 3 - and the oil, goo or ash lying in the patch turns to growth with it",
	"vine_whip": "Yank an enemy 2 tiles toward you, 2 dmg; moving it interrupts its attack",
	"vine_whip+lash": "Yank an enemy 3 tiles toward you, 3 dmg; dragged through fire it is stunned a turn",
	"vine_whip+rake": "Rake a line 3 tiles long: every enemy on it is hauled 2 tiles toward you for 2, and being hauled interrupts each of them",
	"water_jet": "Shove enemies 2 tiles, 2 dmg on impact; moving them interrupts; on growth: pushes 1 further, hits 1 harder",
	"water_jet+pin": "Shove enemies 3 tiles, 3 dmg on impact; an enemy shoved into something is rooted a turn; on growth: pushes 1 further, hits 1 harder",
	"water_jet+sluice": "A long jet: washes oil, fire and ash off 5 tiles, shoves 2, 2 dmg on impact; on growth: pushes 1 further, hits 1 harder",
	"mycelium_dash": "Teleport to any growth tile within 4",
	"mycelium_dash+trail": "Teleport to any growth tile within 7; leaves growth where you stood",
	"mycelium_dash+scatter": "Teleport to any growth tile within 4 and land in a burst of spores: 1 dmg to everything beside you",
	"root_wall": "Raise a wall of roots that blocks enemies",
	"root_wall+bulwark": "Raise a wall of roots that blocks enemies for 6 turns",
	"root_wall+cage": "Cage an enemy within 3: roots fill every open tile beside it for 4 turns",
	"pollen_burst": "Stun everything within 2 tiles for a turn",
	"pollen_burst+torpor": "Stun everything within 2 tiles for 2 turns",
	"pollen_burst+drift": "Throw the cloud: stun everything within 2 of a tile up to 3 away for a turn",
	"sun_flare": "Flash burn: 1 dmg to all within 2, ignites oil; +1 dmg to enemies standing in fire; on growth: costs 1 less and reaches 3",
	"sun_flare+corona": "Flash burn: 2 dmg to all within 2, ignites oil; +1 dmg to enemies standing in fire; on growth: costs 1 less and reaches 3",
	"sun_flare+smoulder": "Flash burn: 1 dmg to all within 2 and the oil it lights burns 4 turns; +1 dmg to enemies standing in fire; on growth: costs 1 less and reaches 3",
	"thorn_shield": "Raise 2 shield - blocks damage before HP",
	"thorn_shield+plate": "Raise 3 shield - blocks damage before HP",
	"thorn_shield+chaff": "Raise 2 shield and shed a cloud of chaff: for 2 turns ranged machinery loses your position",
	"overgrowth": "Convert corruption around a tile into growth",
	"overgrowth+sprawl": "Convert corruption within 2 of a tile up to 3 away into growth",
	"overgrowth+palisade": "The muck snarls up: corruption around the target becomes a hedge of roots for 3 turns",
	"sap_snare": "Root an enemy in place for 2 turns",
	"sap_snare+tether": "Root an enemy in place for 3 turns",
	"sap_snare+blight": "Blight an enemy within 3: 1 dmg a turn for 3 turns, and a second dose stacks",
	"grow_spike": "3 dmg to an enemy standing near growth, +1 with growth beside it (4 max); on growth: +1 dmg",
	"grow_spike+impale": "3 dmg to an enemy near growth within 4, +1 per adjacent growth tile (5 max); on growth: +1 dmg",
	"grow_spike+throng": "3 dmg to an enemy near growth, +1 per enemy standing beside it (5 max); on growth: +1 dmg",
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
	"bramble_coat+briar": "Grow spikes: attackers take 3 dmg, 5 turns",
	"bramble_coat+bristle": "Grow long spines: attackers take 5 dmg, 2 turns",
	"anchor_roots": "Root yourself: immune to drags for 4 turns",
	"anchor_roots+bedrock": "Root yourself: immune to drags for 7 turns",
	"anchor_roots+heave": "Set your roots for 4 turns and heave everything adjacent back a tile",
	"moss_filter": "Filter the air: restore a stage of dimmed regen",
	"moss_filter+sieve": "Filter the air: restore a stage of dimmed regen",
	"moss_filter+prism": "Filter the air; if that leaves the sky clear, 1 dmg to everything within 2",
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
##   won_with [ids]        one win whose kit held every id (an upgrade variant
##                         satisfies its base id; a variant id must be held
##                         exactly)
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
	# Block D6 renamed seed_bomb+ to seed_bomb+tangle (the variant that
	# reproduces the pre-D6 row). The requirement is now for that SPECIFIC
	# sibling - dealt by the draft on even floors, always buyable at the forge.
	# A profile recorded before the rename stores the dead id "seed_bomb+";
	# Profile._migrate_ability_id maps such a "<base>+" to that base's FIRST
	# variant (derived through Content.variants_of, no rename table), so old
	# history keeps satisfying this milestone.
	{"id": "upgrades_only", "kind": "mutator", "requires": {"won_with": ["seed_bomb+tangle"]}, "desc": "Win holding a Tangle Bomb"},
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
##   convertible     a convert_radius turns it into the effect's `kind` - growth
##                   by default, roots for an overgrowth+palisade; the kind may
##                   never name a corruption row (see OP_KEYS). Every corruption
##                   kind except rich_goo, whose bonus must be cleansed
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
