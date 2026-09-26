extends RefCounted
## Staged scenes for the animation suite: one small board per thing that can
## animate, built on the real sim through the tutorial's fixed_floor parser.
## tests/test_anim.gd plans a reel for every scene headless and asserts on it;
## tests/capture_anim.gd renders the same scenes frame by frame under a
## virtual display. A scene is {name, game, action}: step `action` on `game`
## and you have the moment the scene is about.
##
## Scenes POKE state the way tests/render_frame.gd's FRAME_ASH does - an
## enemy's intent, a status, the tender's HP - so a staged moment never waits
## on a lucky roll. That is test-tool staging only; nothing here is a rule.

const Game := preload("res://sim/game.gd")
const Content := preload("res://sim/content.gd")
const Tutorial := preload("res://shell/tutorial.gd")

## The ability arena. Tender at (4,4). Up: a drill bot two tiles off with a
## wall behind it (jets collide). Right: an oil slick, then a golem and a
## smokestack in a line (a lance lights the oil and hits; a piercing lance
## hits both). Left: a sludgeling adjacent (shoves, geysers). Down: growth,
## then a tar spitter beside it (dash targets, spikes). Smoke at (5,2) and goo
## at (6,5) for the clearing and converting verbs.
const ARENA := """
###########
#...~.....#
#...d%....#
#.\"\"......#
#..s@~.Gk.#
#...\"\";...#
#...t.....#
#.........#
###########
"""

## An empty room for staging enemy intents; enemies are added per scene.
const OPEN := """
###########
#.........#
#.........#
#.........#
#...@.....#
#.........#
#.........#
#.........#
###########
"""

const FDEF := {"smog_spawn": [999], "smog_spawn_every": 0, "smog_dim": [900, 950], "smog_choke": 999, "green_need": 2}


static func _game(room: String, kit: Array, extra_enemies: Array = [], extra_terrain: Dictionary = {}):
	var ff: Dictionary = Tutorial.room_config(room, FDEF)
	for spec in extra_enemies:
		ff["gen"]["enemies"].append(spec)
	for p in extra_terrain:
		ff["gen"]["terrain"][p] = {"kind": extra_terrain[p]}
	var g = Game.new(7, {"kit": kit.duplicate(), "fixed_floor": ff})
	# staged: a tender who survives the scene and can afford any cast
	g.player["max_hp"] = 30
	g.player["hp"] = 30
	g.player["charge"] = 6
	return g


## Every ability id, one scene each: cast from slot 0 at its most eventful
## legal target (each legal target is tried on a clone and scored).
static func ability_scene(aid: String) -> Dictionary:
	var g = _game(ARENA, [aid])
	var adef: Dictionary = Content.ABILITIES[aid]
	var has_undim := false
	var gated_on_clear := false
	for eff in adef["effects"]:
		if String(eff["op"]) == "undim":
			has_undim = true
		for pred in eff.get("if", []):
			if pred.has("dim"):
				gated_on_clear = true
	if has_undim and not gated_on_clear:
		g.dim = 1  # a filter that lifts nothing draws nothing worth seeing
	var best = null
	var best_score := -1
	for a in g.legal_actions():
		if String(a.get("type", "")) != "ability" or int(a.get("slot", -1)) != 0:
			continue
		var sc := _score(g, a)
		if sc > best_score:
			best_score = sc
			best = a
	return {"name": "ability:" + aid, "game": g, "action": best}


static func _score(g, a: Dictionary) -> int:
	var g2 = g.clone()
	var pre := {}
	for e in g2.enemies:
		pre[e["id"]] = e["pos"]
	var terr0: int = g2.terrain.size()
	var evs: Array = g2.step(a)
	var sc := 0
	for ev in evs:
		match String(ev.get("t", "")):
			"damage":
				sc += 3 if String(ev.get("who", "")) != "player" else -2
			"status", "ignite", "teleport", "dash", "shield", "thorns", "anchor", "undim":
				sc += 2
			"growth", "terrain", "roots", "convert", "wash", "smoke_cleared", "rider":
				sc += 1
			"death":
				sc += 2
	for e in g2.enemies:
		if pre.has(e["id"]) and pre[e["id"]] != e["pos"]:
			sc += 2
	sc += absi(g2.terrain.size() - terr0)
	return sc


## One scene per enemy intent type (tests/test_content.gd INTENT_TYPES minus
## idle), plus the two ways an intent fails to run.
const INTENT_SCENES := {
	"move": [["drill_bot", Vector2i(8, 2)], ["rust_hound", Vector2i(1, 7)]],
	"attack": [["drill_bot", Vector2i(5, 4)]],
	"advance": [["overseer", Vector2i(8, 4), {"type": "advance", "steps": 2}]],
	"slam": [["overseer", Vector2i(6, 4), {"type": "slam", "tile": Vector2i(4, 4), "dmg": 3}]],
	"quake": [["overseer", Vector2i(5, 4), {"type": "quake", "dmg": 2}]],
	"flood": [["furnace_core", Vector2i(8, 2), {"type": "flood", "row": 5}]],
	"ignite_all": [["furnace_core", Vector2i(8, 2), {"type": "ignite_all"}]],
	"gather": [["furnace_core", Vector2i(8, 2), {"type": "gather"}]],
	"ooze": [["pump_jack", Vector2i(6, 6), {"type": "ooze", "in": 1}, {"timer": 1}]],
	"stoke": [["smokestack", Vector2i(7, 2), {"type": "stoke", "in": 1}, {"timer": 1}]],
	"drag": [["magnet_crane", Vector2i(7, 4)]],
	"dredge": [["the_dredge", Vector2i(6, 5), {"type": "dredge", "radius": 2}]],
	"summon": [["extractor_engine", Vector2i(7, 2), {"type": "summon", "in": 1}, {"timer": 1}]],
	"gum": [["tar_spitter", Vector2i(6, 4)]],
	"drain": [["leech_drone", Vector2i(6, 4)]],
	"fuse": [["drill_bot", Vector2i(6, 2)], ["drill_bot", Vector2i(7, 2)], ["sludgeling", Vector2i(1, 7)]],
	"blocked": [["drill_bot", Vector2i(5, 4), null, {"status": {"stun": 1}}],
		["drill_bot", Vector2i(7, 6), null, {"status": {"root": 2}}]],
	"screened": [["tar_spitter", Vector2i(4, 1), {"type": "gum", "slot": 0}]],
}
const INTENT_TERRAIN := {
	"ignite_all": {Vector2i(2, 2): "oil", Vector2i(3, 6): "oil", Vector2i(6, 3): "oil", Vector2i(7, 6): "oil", Vector2i(2, 5): "oil"},
	"dredge": {Vector2i(5, 5): "growth", Vector2i(6, 6): "growth", Vector2i(7, 5): "growth", Vector2i(5, 6): "growth"},
	"screened": {Vector2i(4, 3): "smoke"},
}


static func intent_scene(verb: String) -> Dictionary:
	var specs: Array = INTENT_SCENES[verb]
	var enemies: Array = []
	for s in specs:
		enemies.append({"kind": s[0], "pos": s[1]})
	var g = _game(OPEN, ["solar_lance", "seed_bomb", "mycelium_dash"], enemies, INTENT_TERRAIN.get(verb, {}))
	g.player["bank"] = 2
	for j in specs.size():
		var s: Array = specs[j]
		var e = g.enemies[j]
		if s.size() > 2 and s[2] != null:
			e["intent"] = (s[2] as Dictionary).duplicate(true)
		if s.size() > 3:
			for k in s[3]:
				e[k] = s[3][k] if not (s[3][k] is Dictionary) else (s[3][k] as Dictionary).duplicate(true)
	return {"name": "intent:" + verb, "game": g, "action": {"type": "end_turn"}}


## The tender's own verbs outside abilities.
static func basic_scene(which: String) -> Dictionary:
	match which:
		"move":
			var g = _game(OPEN, ["solar_lance"])
			return {"name": "move", "game": g, "action": {"type": "move", "dir": Vector2i(1, 0)}}
		"strike":
			var g = _game(OPEN, ["solar_lance"], [{"kind": "drill_bot", "pos": Vector2i(5, 4)}])
			return {"name": "strike", "game": g, "action": {"type": "strike", "dir": Vector2i(1, 0)}}
		"strike_spiked":
			var g = _game(OPEN, ["solar_lance"], [{"kind": "coal_golem", "pos": Vector2i(5, 4)}])
			return {"name": "strike_spiked", "game": g, "action": {"type": "strike", "dir": Vector2i(1, 0)}}
		"kill":
			var g = _game(OPEN, ["solar_lance"], [{"kind": "sludgeling", "pos": Vector2i(5, 4)}])
			return {"name": "kill", "game": g, "action": {"type": "strike", "dir": Vector2i(1, 0)}}
		"cleanse":
			var g = _game(OPEN, ["solar_lance"], [], {Vector2i(5, 4): "oil"})
			return {"name": "cleanse", "game": g, "action": {"type": "cleanse", "target": Vector2i(5, 4)}}
		"item":
			var g = _game(OPEN, ["solar_lance"], [{"kind": "drill_bot", "pos": Vector2i(5, 5)}])
			g.player["items"] = ["spore_vial"]
			return {"name": "item", "game": g, "action": {"type": "use_item", "slot": 0}}
		"heal_item":
			var g = _game(OPEN, ["solar_lance"])
			g.player["hp"] = 20
			g.player["items"] = ["balm_fruit"]
			return {"name": "heal_item", "game": g, "action": {"type": "use_item", "slot": 0}}
		"surge":
			var g = _game(ARENA, ["sun_flare"])
			g.player["pos"] = Vector2i(4, 5)
			return {"name": "surge", "game": g, "action": {"type": "ability", "slot": 0, "target": Vector2i(4, 5)}}
		"death":
			var g = _game(OPEN, ["solar_lance"], [{"kind": "drill_bot", "pos": Vector2i(5, 4)}])
			g.player["hp"] = 1
			return {"name": "death", "game": g, "action": {"type": "end_turn"}}
	return {}


const BASIC := ["move", "strike", "strike_spiked", "kill", "cleanse", "item", "heal_item", "surge", "death"]


static func all_scenes() -> Array:
	var out: Array = []
	for w in BASIC:
		out.append(basic_scene(w))
	for aid in Content.ABILITIES:
		out.append(ability_scene(aid))
	for v in INTENT_SCENES:
		out.append(intent_scene(v))
	return out
