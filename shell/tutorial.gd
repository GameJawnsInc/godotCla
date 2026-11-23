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

## Every `say` is at most two short lines (tests/test_shell.gd
## _check_tutorial_text holds each one to the banner's size on the narrowest
## phone, unshrunk): one idea per step, said warmly, in the player's own verbs.
const STEPS := [
	{
		"say": ["This little sprout is you!", "Tap RIGHT on the D-pad to move."],
		"expect": {"type": "move", "dir": Vector2i(1, 0)},
	},
	{
		"say": ["Moving costs 1 charge (the bolt).", "It refills each turn. RIGHT again."],
		"expect": {"type": "move", "dir": Vector2i(1, 0)},
	},
	{
		"say": ["A Drill Bot! Tap END to pass", "the turn and see what it does."],
		"expect": {"type": "end_turn"},
	},
	{
		"say": ["It came closer. RED marks where", "it will strike next. END again."],
		"expect": {"type": "end_turn"},
	},
	{
		"say": ["Step off the red - or be brave:", "walk INTO the bot to strike it."],
		"expect": {"type": "strike"},
		"allow_nav": true,
		"do": null,
	},
	{
		"say": ["Nice! A strike deals 1.", "Strike again."],
		"expect": {"type": "strike"},
		"allow_nav": true,
		"do": null,
	},
	{
		"say": ["Finish it off: strike again,", "or tap SOLAR LANCE and aim."],
		"expect": {},
		"free": true,
		"until_dead": "drill_bot",
		"do": null,
	},
	{
		"say": ["Scrapped! The golem is SPIKED, so", "punches hurt. LANCE it from afar."],
		"expect": {"type": "ability", "slot": 0},
		"allow_nav": true,
		"until_dead": "coal_golem",
		"do": null,
	},
	{
		"say": ["Oil! Stand beside it, tap CLEANSE", "and aim. It pays bloom, leaves growth."],
		"expect": {"type": "cleanse"},
		"allow_nav": true,
		"do": null,
	},
	{
		"say": ["Growth heals you. Stand ON it, then", "cast SEED BOMB: growth powers it up."],
		"expect": {"type": "ability", "slot": 1},
		"allow_nav": true,
		"do": null,
	},
	{
		"say": ["Cleanse the last of it. A tended room", "BLOOMS - and the stairs wake up!"],
		"expect": {"type": "cleanse"},
		"allow_nav": true,
		"do": null,
	},
	{
		"say": ["A supply pod! Walk over it, then", "tap your satchel slot. It's free!"],
		"expect": {"type": "use_item"},
		"allow_nav": true,
		"do": null,
	},
	{
		"say": ["Spend bloom at shrines later. Now", "stand on the stairs and DESCEND."],
		"expect": {"type": "descend"},
		"allow_nav": true,
		"do": null,
		"guide_to_stairs": true,
	},
]

const DONE := [
	"You're a natural!",
	"Green each floor, wake its stairs,",
	"and cool the Furnace far below.",
]

const GLYPH_TERRAIN := {"~": "oil", "\"": "growth", ";": "goo", "&": "rich_goo", "*": "fire", "%": "smoke", "8": "roots"}
const GLYPH_ENEMY := {"d": "drill_bot", "S": "oil_sludge", "s": "sludgeling", "L": "leech_drone", "t": "tar_spitter", "G": "coal_golem", "E": "extractor_engine", "r": "rust_hound", "c": "cinder_mite", "P": "pump_jack", "k": "smokestack", "C": "magnet_crane"}


## Parse ROOM into the sim's fixed_floor config.
static func floor_config() -> Dictionary:
	return room_config(ROOM, FDEF)


## Parse any ASCII room (the glyphs above) into a fixed_floor config. The
## animation suite stages its scenes with it (tests/anim_scenes.gd).
static func room_config(room: String, fdef: Dictionary) -> Dictionary:
	var rows: Array = []
	for line in room.strip_edges().split("\n"):
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
	return {"gen": gen, "fdef": fdef}


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
