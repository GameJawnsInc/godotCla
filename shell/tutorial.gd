extends RefCounted
## The tutorial, entirely as data. To update it, edit this file only:
## - ROOM is the floor, drawn in ASCII (glyphs below)
## - KIT is the loadout the tutorial teaches
## - STEPS is the script: what the guide says, what action advances it
##
## Each step:
##   say      lines of guide text (Array of String)
##   expect   action pattern that advances the step - subset match, so
##            {"type": "move"} matches any move; omit keys to wildcard them
##   do       the exact action the headless test performs for this step
##            (defaults to expect when expect is fully concrete)
##   free     optional: if true, ANY action advances (sandbox moments)
##   allow_nav optional: if true, move/end_turn/strike are allowed without
##            advancing (steps that need the player to walk somewhere first).
##            Steps WITHOUT it are strict: only the expected action works.
##
## tests/test_shell.gd plays every step's `do` through the real sim each
## suite run - if a sim or content change breaks the script, the suite
## fails and the tutorial gets fixed before it ships broken.

## Map glyphs: # wall · . floor · @ player start · d drill bot · ~ oil
## · " growth · > stairs (also gets a wall behind it) · ^ vent
const ROOM := """
##############
#............#
#.@....d.....#
#......~~....#
#..""....~...#
#........>...#
##############
"""

const KIT := ["solar_lance", "seed_bomb", "mycelium_dash"]

## Tutorial floor pacing: no reinforcements, sky never dims, choke far away.
const FDEF := {"smog_spawn": [999], "smog_spawn_every": 0, "smog_dim": [900, 950], "smog_choke": 999, "green_need": 0}

const STEPS := [
	{
		"say": ["This sprout is you.", "Press the D-pad RIGHT to move."],
		"expect": {"type": "move", "dir": Vector2i(1, 0)},
	},
	{
		"say": ["Moving costs 1 charge (the bolt up top).", "Charge refills every turn. Move RIGHT again."],
		"expect": {"type": "move", "dir": Vector2i(1, 0)},
	},
	{
		"say": ["That machine ahead is a Drill Bot.", "End your turn (END button) and watch it."],
		"expect": {"type": "end_turn"},
	},
	{
		"say": ["It moved toward you. When it attacks, the tile", "it will hit glows RED a full turn ahead.", "Nothing here is a surprise. End turn again."],
		"expect": {"type": "end_turn"},
	},
	{
		"say": ["If a RED tile is under you, step off it or", "fight. Walk INTO the drill bot to strike it.", "(Move toward it - striking is just moving into it.)"],
		"expect": {"type": "strike"},
		"allow_nav": true,
		"do": null,
	},
	{
		"say": ["Hit it again. Strikes cost 1 charge and deal 1.", "Your abilities below hit much harder."],
		"expect": {"type": "strike"},
		"allow_nav": true,
		"do": null,
	},
	{
		"say": ["Finish it however you like - strike again, or", "tap ability 1 (Solar Lance) and aim at it."],
		"expect": {},
		"free": true,
		"until_dead": true,
		"do": null,
	},
	{
		"say": ["Scrapped. See the dark OIL puddles? That is the", "combine's corruption. Stand NEXT to one, press", "CLEANSE, then aim at it. It pays 1 bloom, leaves", "growth - and on real floors, greening WAKES the stairs."],
		"expect": {"type": "cleanse"},
		"allow_nav": true,
		"do": null,
	},
	{
		"say": ["Bloom is money - shrines sell heals, abilities,", "and grafts. And see the smog meter filling up top?", "It never stops. Slow runs suffocate.", "Head for the GOLD-RINGED stairs and stand on them."],
		"expect": {"type": "descend"},
		"allow_nav": true,
		"do": null,
		"guide_to_stairs": true,
	},
]

const DONE := [
	"That's the whole loop: read the red tiles, spend",
	"charge well, cleanse what you can afford to,",
	"and always beat the smog downstairs.",
	"",
	"Six more floors and the Furnace waits below.",
	"Good luck, Tender.",
]

const GLYPH_TERRAIN := {"~": "oil", "\"": "growth", ";": "goo", "&": "rich_goo", "*": "fire", "%": "smoke", "8": "roots"}
const GLYPH_ENEMY := {"d": "drill_bot", "S": "oil_sludge", "s": "sludgeling", "L": "leech_drone", "t": "tar_spitter", "G": "coal_golem", "E": "extractor_engine", "r": "rust_hound", "c": "cinder_mite", "P": "pump_jack", "k": "smokestack", "C": "magnet_crane"}


## Parse ROOM into the sim's fixed_floor config.
static func floor_config() -> Dictionary:
	var rows: Array = []
	for line in ROOM.strip_edges().split("\n"):
		rows.append(line)
	var h := rows.size()
	var w := 0
	for r in rows:
		w = maxi(w, String(r).length())
	var tiles := PackedInt32Array()
	tiles.resize(w * h)
	var gen := {
		"w": w, "h": h, "tiles": tiles, "start": Vector2i(1, 1),
		"stairs": Vector2i(-1, -1), "shrine": Vector2i(-1, -1),
		"vents": [], "terrain": {}, "enemies": [],
	}
	for y in h:
		var row := String(rows[y])
		for x in w:
			var ch := row[x] if x < row.length() else "#"
			var p := Vector2i(x, y)
			tiles[y * w + x] = 0 if ch == "#" else 1
			if ch == "@":
				gen["start"] = p
			elif ch == ">":
				gen["stairs"] = p
			elif ch == "+":
				gen["shrine"] = p
			elif ch == "^":
				gen["vents"].append(p)
			elif GLYPH_TERRAIN.has(ch):
				gen["terrain"][p] = {"kind": GLYPH_TERRAIN[ch]}
			elif GLYPH_ENEMY.has(ch):
				gen["enemies"].append({"kind": GLYPH_ENEMY[ch], "pos": p})
	gen["tiles"] = tiles
	return {"gen": gen, "fdef": FDEF}


static func game_config() -> Dictionary:
	return {"kit": KIT.duplicate(), "fixed_floor": floor_config()}


## Does this action advance the given step? Subset match: every key in
## `expect` must equal the action's value; missing keys are wildcards.
static func matches(step: Dictionary, action: Dictionary) -> bool:
	if step.get("free", false):
		return true
	var expect: Dictionary = step.get("expect", {})
	for k in expect:
		if not action.has(k) or action[k] != expect[k]:
			return false
	return true
