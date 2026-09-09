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
##   until_dead optional: true = advance once no enemies remain; a String
##            kind = advance once no enemy of that kind remains
##   allow_nav optional: if true, move/end_turn/strike are allowed without
##            advancing (steps that need the player to walk somewhere first).
##            Steps WITHOUT it are strict: only the expected action works.
##
## tests/test_shell.gd plays every step's `do` through the real sim each
## suite run - if a sim or content change breaks the script, the suite
## fails and the tutorial gets fixed before it ships broken.

## Map glyphs: # wall · . floor · @ player start · d drill bot · ~ oil
## · " growth · > stairs (also gets a wall behind it) · ^ vent
##
## The second slick sits OFF row 4 on purpose. The golem starts on row 4 and
## the guide teaches lancing down its row - a slick in that beam is lit by the
## step before the one that asks you to cleanse it, and a burning tile is not
## corruption, so CLEANSE refuses until it burns down to ash.
const ROOM := """
##############
#............#
#.@....d.....#
#......~.....#
#.."".......G#
#........>.~.#
##############
"""

const KIT := ["solar_lance", "seed_bomb", "mycelium_dash"]

## Tutorial floor pacing: no reinforcements, sky never dims, choke far away.
const FDEF := {"smog_spawn": [999], "smog_spawn_every": 0, "smog_dim": [900, 950], "smog_choke": 999, "green_need": 2}

const STEPS := [
	{
		"say": ["This sprout is you.", "Press the D-pad RIGHT to move."],
		"expect": {"type": "move", "dir": Vector2i(1, 0)},
	},
	{
		"say": ["Moving costs 1 charge (the bolt up top).", "Charge refills each turn. Move RIGHT again."],
		"expect": {"type": "move", "dir": Vector2i(1, 0)},
	},
	{
		"say": ["That machine ahead is a Drill Bot.", "End your turn (END button) and watch it."],
		"expect": {"type": "end_turn"},
	},
	{
		"say": ["It moved toward you. The tile it will hit", "glows RED a full turn ahead.", "End turn again."],
		"expect": {"type": "end_turn"},
	},
	{
		"say": ["Step off a RED tile, or fight.", "Walk INTO the drill bot to strike it."],
		"expect": {"type": "strike"},
		"allow_nav": true,
		"do": null,
	},
	{
		"say": ["Hit it again. A strike costs 1, deals 1.", "Your abilities below hit harder."],
		"expect": {"type": "strike"},
		"allow_nav": true,
		"do": null,
	},
	{
		"say": ["Finish it: strike again, or tap ability 1", "(Solar Lance) and aim at it."],
		"expect": {},
		"free": true,
		"until_dead": "drill_bot",
		"do": null,
	},
	{
		"say": ["Scrapped. Now the Coal Golem - it is SPIKED,", "so punching it costs you 1 HP.", "Line up its row, tap SOLAR LANCE, aim."],
		"expect": {"type": "ability", "slot": 0},
		"allow_nav": true,
		"until_dead": "coal_golem",
		"do": null,
	},
	{
		"say": ["Those dark puddles are OIL - the combine's.", "The stairs stay DORMANT until you green the", "floor ('green 0/2' up top). Stand NEXT to one,", "press CLEANSE, aim. It pays bloom, leaves GROWTH."],
		"expect": {"type": "cleanse"},
		"allow_nav": true,
		"do": null,
	},
	{
		"say": ["Growth heals you, and fuels your casts.", "Stand ON growth, then cast SEED BOMB", "(ability 2): it surges, and spends the tile."],
		"expect": {"type": "ability", "slot": 1},
		"allow_nav": true,
		"do": null,
	},
	{
		"say": ["Now cleanse the last of it. A fully tended", "room BLOOMS: bonus bloom and a supply pod -", "and THE STAIRS AWAKEN."],
		"expect": {"type": "cleanse"},
		"allow_nav": true,
		"do": null,
	},
	{
		"say": ["Walk over the pod to pocket the item, then", "TAP the satchel slot by the D-pad to use it.", "Items cost no turn."],
		"expect": {"type": "use_item"},
		"allow_nav": true,
		"do": null,
	},
	{
		"say": ["Bloom is money: shrines sell heals, abilities,", "grafts and items, and the smog keeps rising.", "Every floor: green it, wake the stairs, descend.", "Stand on them."],
		"expect": {"type": "descend"},
		"allow_nav": true,
		"do": null,
		"guide_to_stairs": true,
	},
]

const DONE := [
	"That's the loop: read the red tiles, green each",
	"floor to wake its stairs, cast from your garden,",
	"and stay ahead of the smog.",
	"",
	"Seven floors down, the Furnace waits.",
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
	gen["rooms"] = [Rect2i(1, 1, w - 2, h - 2)]
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
