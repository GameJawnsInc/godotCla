extends RefCounted
## Danger readability (fun pass, phase 1): pure functions from the sim's
## three read-only forecasts - Game.smog_forecast, Game.telegraph and
## Game.end_turn_forecast - to the data the shell draws: the SKIES countdown
## chips, the INCOMING line, intent badges, tile numbers, drag tethers, vent
## countdowns, the HP danger level, the lethal guard's words and the
## transition cues. No drawing, no Node, no state of its own:
## tests/test_shell.gd asserts on what these return, and tests/render_frame.gd
## draws the badges and tile numbers from the same functions.
## Never mutates the game: every look-ahead runs on a clone().

const Content := preload("res://sim/content.gd")
const Names := preload("res://shell/names.gd")
const MapGen := preload("res://sim/mapgen.gd")

const SKY_HORIZON := 60   # end turns the smog walk looks ahead
const SKY_AMBER := 5      # choke this close (and not yet choking): amber bar, warn tick
const VENT_MARK := 5      # vents draw their countdown on the map this close
const DIM_CHIP := 9       # the dim chip shows this close
const LOW_HP_FLOOR := 3   # low HP: hp <= max(LOW_HP_FLOOR, max_hp / 4)
const GUARD_MS := 1500    # confirm window for an implicit end turn into a lethal hit
## The escape-aware hints: when lethal, compute() clones once per candidate
## action to find which ones survive, so the guard flash can say "step off" or
## "use the glowing item" and the saving satchel item pulses. They reveal no
## rng, but they do solve a one-step puzzle for the player; false is the
## owner's one-line switch back to the plain "tap again" flash and no pulse.
const HINT_ESCAPES := true

const COL_TEXT := Color("d8e0d4")
const COL_DIM := Color("97a29a")
const COL_AMBER := Color("e8a33a")
const COL_RED := Color("e04b3a")
const COL_SEALED := Color("8fdc6a")

## Intent type -> badge. num names the snapshot intent key whose value is the
## badge number ("dmg" reads the telegraph entry's dmg); "" draws no number.
## cat picks the ring colour (CAT_COL). An intent type in NO_BADGE draws
## nothing. tests/test_shell.gd holds this table to tests/test_content.gd
## INTENT_TYPES, so a new intent type cannot ship without a badge decision.
const BADGE := {
	"attack": {"icon": "in_attack", "num": "dmg", "cat": "hit"},
	"slam": {"icon": "in_slam", "num": "dmg", "cat": "hit"},
	"quake": {"icon": "in_quake", "num": "dmg", "cat": "hit"},
	"drain": {"icon": "in_drain", "num": "amount", "cat": "control"},
	"gum": {"icon": "in_gum", "num": "", "cat": "control"},
	"drag": {"icon": "in_drag", "num": "times", "cat": "control"},
	"advance": {"icon": "in_advance", "num": "steps", "cat": "control"},
	"summon": {"icon": "in_summon", "num": "in", "cat": "timer"},
	"ooze": {"icon": "in_ooze", "num": "in", "cat": "timer"},
	"stoke": {"icon": "in_stoke", "num": "in", "cat": "timer"},
	"fuse": {"icon": "in_fuse", "num": "", "cat": "world"},
	"dredge": {"icon": "in_dredge", "num": "radius", "cat": "world"},
	"flood": {"icon": "in_flood", "num": "", "cat": "world"},
	"gather": {"icon": "in_gather", "num": "", "cat": "world"},
	"ignite_all": {"icon": "in_ignite", "num": "", "cat": "world"},
}
const NO_BADGE := ["move", "idle"]
## telegraph "blocked" reason -> the icon that replaces the intent glyph
const BLOCK_ICON := {"stun": "in_stunned", "root": "in_rooted", "screened": "in_screened", "anchor": "in_anchored"}
const CAT_COL := {
	"hit": Color("e04b3a"), "control": Color("b48ae0"), "timer": Color("e8a33a"),
	"world": Color("ef933a"), "blocked": Color("97a29a"),
}


## Everything the shell draws about danger, from one live game. The three
## sim queries plus the derived verdicts; "escapes" only when lethal (it
## clones once per candidate action). Over, or in the draft: {"ok": false}.
static func compute(game) -> Dictionary:
	if game == null or game.over or game.phase != "play":
		var hp := "ok"
		if game != null and not game.over:
			hp = hp_state(int(game.player["hp"]), int(game.player["max_hp"]), false)
		return {"ok": false, "lethal": false, "hp": hp, "sky": {}, "tele": {"enemies": [], "tiles": {}},
			"fc": {"dmg": 0, "absorbed": 0, "by_src": {}, "dies": false}, "escapes": {}}
	var sky: Dictionary = game.smog_forecast(SKY_HORIZON)
	var fc: Dictionary = game.end_turn_forecast()
	var d := {
		"ok": true, "floor": game.floor_num, "sky": sky,
		"sky_calm": game.smog_forecast(SKY_HORIZON, false) if bool(sky["stoker"]) else sky,
		"tele": game.telegraph(), "fc": fc, "lethal": bool(fc["dies"]),
		"hp": hp_state(int(game.player["hp"]), int(game.player["max_hp"]), bool(fc["dies"])),
		"escapes": escapes(game) if bool(fc["dies"]) and HINT_ESCAPES else {},
	}
	return d


static func low_hp(hp: int, max_hp: int) -> bool:
	return hp <= maxi(LOW_HP_FLOOR, max_hp / 4)


## "lethal" (the forecast kills), "low" (low_hp), else "ok". One rule for the
## red HP chip, the danger vignette and the redraw pulse.
static func hp_state(hp: int, max_hp: int, lethal: bool) -> String:
	if lethal:
		return "lethal"
	return "low" if low_hp(hp, max_hp) else "ok"


static func sky_alert(sky: Dictionary) -> String:
	if bool(sky.get("choking", false)):
		return "red"
	var c := int(sky.get("choke_in", -1))
	return "amber" if c >= 1 and c <= SKY_AMBER else ""


## The SKIES countdown chips, in draw order: [{key, icon, text, col}].
static func sky_chips(sky: Dictionary) -> Array:
	var out: Array = []
	var c := int(sky.get("choke_in", -1))
	if c > 0:
		var cc := COL_TEXT
		if bool(sky.get("choking", false)) or c == 1:
			cc = COL_RED
		elif c <= SKY_AMBER:
			cc = COL_AMBER
		out.append({"key": "choke", "icon": "ic_choke", "text": str(c), "col": cc})
	var v := int(sky.get("spawn_in", -1))
	if v > 0:
		var vc := COL_AMBER if v == 1 else COL_TEXT
		if int(sky.get("spawn_open", 0)) == 0:
			vc = COL_SEALED if int(sky.get("spawn_sealed", 0)) > 0 else COL_DIM
		out.append({"key": "vent", "icon": "vent", "text": str(v), "col": vc})
	var dm := int(sky.get("dim_in", -1))
	if dm > 0 and dm <= DIM_CHIP:
		out.append({"key": "dim", "icon": "ic_dim", "text": str(dm), "col": COL_AMBER if dm <= 2 else COL_DIM})
	return out


## Does this floor have stairs, and are they awake? A real stairs tile (the
## boss arena's is (-1, -1)) and the quota met - green_need can be reclamped
## to 0 on an ordinary floor, where the stairs ARE awake, so the quota alone
## cannot tell the boss floor apart.
static func stairs_awake(snap: Dictionary) -> bool:
	var st = snap.get("map", {}).get("stairs", Vector2i(-1, -1))
	if not (st is Vector2i) or st == Vector2i(-1, -1):
		return false
	return int(snap.get("greened", 0)) >= int(snap.get("green_need", 0))


## The danger-owned context line, or {} when danger has nothing to say:
## {text, col, pulse}. Priority inside: incoming damage, then the choke
## countdown, then the vents. `awake` is stairs_awake(snap).
static func context_line(d: Dictionary, awake: bool) -> Dictionary:
	if not bool(d.get("ok", false)):
		return {}
	var fc: Dictionary = d["fc"]
	var dmg := int(fc.get("dmg", 0))
	if dmg > 0:
		if bool(fc.get("dies", false)):
			return {"text": "! INCOMING %d - LETHAL%s" % [dmg, _src_suffix(fc)], "col": COL_RED, "pulse": true}
		if int(fc.get("absorbed", 0)) >= dmg:
			return {"text": "! INCOMING %d - shield holds" % dmg, "col": COL_AMBER, "pulse": false}
		return {"text": "! INCOMING %d%s" % [dmg, _src_suffix(fc)], "col": COL_AMBER, "pulse": false}
	var sky: Dictionary = d["sky"]
	var c := int(sky.get("choke_in", -1))
	if not bool(sky.get("choking", false)) and c >= 1 and c <= SKY_AMBER:
		# the boss floor has no stairs: stairs_awake says so, never green_need
		var how := "descend to escape it" if awake else "cleansing thins it"
		if c == 1:
			return {"text": "Smog chokes NEXT TURN - %s" % how, "col": COL_RED, "pulse": true}
		return {"text": "Smog chokes in %d - %s" % [c, how], "col": COL_AMBER, "pulse": false}
	if int(sky.get("spawn_in", -1)) == 1 and int(sky.get("spawn_open", 0)) > 0:
		return {"text": "The vents release next turn", "col": COL_AMBER, "pulse": false}
	return {}


static func _src_suffix(fc: Dictionary) -> String:
	var by: Dictionary = fc.get("by_src", {})
	if by.is_empty():
		return ""
	var keys: Array = by.keys()
	keys.sort_custom(func(a, b):
		if int(by[a]) != int(by[b]):
			return int(by[a]) > int(by[b])
		return String(a) < String(b))
	var names: Array = []
	for i in mini(2, keys.size()):
		names.append(Names.src_name(String(keys[i])))  # the log's SHORT form
	var s := "  ·  " + ", ".join(names)
	if keys.size() > 2:
		s += " +%d" % (keys.size() - 2)
	return s


## One legal action, then the end turn, survives - by kind, for the guard's
## words and the satchel pulse. Only called when the forecast is lethal.
## `strike` is a deliberate addition to the spec's {move, item, descend}
## shape. An action that WINS the run (c.over and c.won: a strike or an item
## that kills the boss) is an escape of its kind - the best one there is; an
## action that ends the run any other way is not. `win` names the kind of the
## first winning action ("strike" | "item", "" for none), so the guard can
## point at the winning blow before it suggests stepping off; `win_item` is
## that winning item's slot (-1 for none), `win_kind` the kind standing on the
## winning strike's tile ("" for none) and `strike_dirs` counts EVERY legal
## strike direction, surviving or not - counted before any forecast filter,
## because a minion whose strike still dies is exactly the wrong blow a bare
## "strike to win" would let the player pick. So the words claim a win without
## naming its target only where one strike exists at all, and otherwise name
## the target (`glow_items`, `guard_flash`).
static func escapes(game) -> Dictionary:
	var out := {"move": false, "strike": false, "item": [], "descend": false, "win": "",
		"win_item": -1, "win_kind": "", "strike_dirs": 0}
	for a in game.legal_actions():
		var t := String(a.get("type", ""))
		if not (t in ["move", "strike", "use_item", "descend"]):
			continue
		if t == "strike":
			out["strike_dirs"] = int(out["strike_dirs"]) + 1
		var c = game.clone()
		c.step(a)
		if c.over and not c.won:
			continue
		if not c.over and c.phase != "play":
			if t == "descend":
				out["descend"] = true
			continue
		if not c.over and bool(c.end_turn_forecast()["dies"]):
			continue
		if c.over and String(out["win"]) == "" and t in ["strike", "use_item"]:
			out["win"] = "strike" if t == "strike" else "item"
			if t == "use_item":
				out["win_item"] = int(a["slot"])
			else:
				var at: Vector2i = game.player["pos"] + a["dir"]
				for e in game.enemies:
					if e["pos"] == at:
						out["win_kind"] = String(e["kind"])
						break
		if t == "use_item":
			out["item"].append(int(a["slot"]))
		elif t == "descend":
			out["descend"] = true
		elif t == "strike":
			out["strike"] = true
		else:
			out["move"] = true
	return out


## The satchel slots that glow: every surviving item, except that when an
## item WINS only that one glows - "the glowing item wins" must not light a
## slot that merely survives.
static func glow_items(es: Dictionary) -> Array:
	if String(es.get("win", "")) == "item" and int(es.get("win_item", -1)) >= 0:
		return [int(es["win_item"])]
	return es.get("item", [])


static func guard_flash(d: Dictionary) -> String:
	var dmg := int(d.get("fc", {}).get("dmg", 0))
	var es: Dictionary = d.get("escapes", {})
	# a blow that WINS the run is the best way out there is: named first. The
	# flash names no direction, so a bare "strike to win" is said only when
	# the winning strike is the ONLY legal strike (`strike_dirs`, every legal
	# direction, a losing one included); with the boss and a minion both
	# adjacent it names the target instead ("strike the Overseer to win"), and
	# with no target to name it falls back to the order below. The winning
	# item is the only slot that glows.
	match String(es.get("win", "")):
		"strike":
			if int(es.get("strike_dirs", 1)) <= 1:
				return "LETHAL (%d) - strike to win, or tap again to end turn" % dmg
			var wk := String(es.get("win_kind", ""))
			if wk != "":
				return "LETHAL (%d) - strike %s to win, or tap again" % [dmg, Names.the_name(wk)]
		"item":
			return "LETHAL (%d) - the glowing item wins, or tap again" % dmg
	if bool(es.get("move", false)):
		return "LETHAL (%d) - step off, or tap again to end turn" % dmg
	if bool(es.get("strike", false)):
		return "LETHAL (%d) - strike first, or tap again to end turn" % dmg
	if not es.get("item", []).is_empty():
		return "LETHAL (%d) - use the glowing item, or tap again" % dmg
	if bool(es.get("descend", false)):
		return "LETHAL (%d) - descend, or tap again to end turn" % dmg
	return "LETHAL (%d) - tap again to end the turn" % dmg


## What the guard compares between the two presses: anything a player action
## can change. Same signature inside GUARD_MS = the confirmation.
static func guard_sig(game) -> Array:
	return [game.floor_num, game.total_turns, game.player["pos"], game.player["charge"],
		game.player["hp"], game.player["shield"], game.player["items"].size(), game.bloom]


static func badges(snap: Dictionary, tele: Dictionary) -> Array:
	var out: Array = []
	var by_id := {}
	for e in snap.get("enemies", []):
		by_id[e["id"]] = e
	for ent in tele.get("enemies", []):
		if not by_id.has(ent["id"]):
			continue
		var it: Dictionary = by_id[ent["id"]]["intent"]
		var blocked := String(ent["blocked"])
		if blocked != "":
			out.append({"id": ent["id"], "pos": ent["pos"], "icon": BLOCK_ICON.get(blocked, "in_stunned"),
				"text": "", "cat": "blocked", "col": CAT_COL["blocked"], "live": false})
			continue
		var row: Dictionary = BADGE.get(String(ent["type"]), {})
		if row.is_empty():
			continue
		var text := ""
		match String(row["num"]):
			"":
				text = ""
			"dmg":
				text = str(int(ent["dmg"]))
			"times":
				text = str(int(it.get("times", 1))) if int(it.get("times", 1)) > 1 else ""
			_:
				text = str(int(it.get(String(row["num"]), 0)))
		out.append({"id": ent["id"], "pos": ent["pos"], "icon": row["icon"], "text": text,
			"cat": row["cat"], "col": CAT_COL[row["cat"]], "live": bool(ent["live"])})
	return out


## Summed telegraphed damage per tile, minus the tender's own tile (the
## INCOMING line speaks for that one).
static func tile_numbers(tele: Dictionary, pp: Vector2i) -> Dictionary:
	var out: Dictionary = tele.get("tiles", {}).duplicate()
	out.erase(pp)
	return out


static func tethers(tele: Dictionary, pp: Vector2i) -> Array:
	var out: Array = []
	for ent in tele.get("enemies", []):
		if String(ent["type"]) != "drag":
			continue
		var path: Array = ent["path"]
		# the sim fills `path` before it applies a block, so a blocked drag
		# (anchored, rooted, stunned) lands nowhere: no ring
		var blocked := String(ent.get("blocked", "")) != ""
		out.append({"from": ent["pos"], "to": pp,
			"land": path.back() if not path.is_empty() and not blocked else null,
			"live": bool(ent["live"])})
	return out


## Tiles a non-damage intent will change: {pos, kind} with kind flood |
## ignite | dredge (the weld partner already has its line).
static func marks(tele: Dictionary) -> Array:
	var out: Array = []
	for ent in tele.get("enemies", []):
		if String(ent["blocked"]) != "":
			continue
		var k := ""
		match String(ent["type"]):
			"flood": k = "flood"
			"ignite_all": k = "ignite"
			"dredge": k = "dredge"
		if k == "":
			continue
		for p in ent["marks"]:
			out.append({"pos": p, "kind": k})
	return out


## What _tick_smog does at vent `v` when a wave fires, by its own two tests in
## its own order, read off the snapshot: "covered" when Game._open(v) is false
## - not a floor tile, a machine or the tender standing on it, or a terrain
## kind whose Content.TERRAIN row "blocks" (Roots) - and the vent releases
## NOTHING; "sealed" when growth covers it (the seal absorbs the release and
## is spent); "open" when it releases. The state as it stands: the enemy
## phase and the terrain decay both run before the smog tick, so a covered
## vent can be open again by the wave (the words say "while covered").
## Mirrors Game._open and the vent arm of Game._tick_smog - change together.
static func vent_state(snap: Dictionary, v: Vector2i) -> String:
	var m: Dictionary = snap.get("map", {})
	var w := int(m.get("w", 0))
	if v.x < 0 or v.y < 0 or v.x >= w or v.y >= int(m.get("h", 0)) \
			or int(m["tiles"][v.y * w + v.x]) != MapGen.T_FLOOR:
		return "covered"
	if snap.get("player", {}).get("pos", Vector2i(-1, -1)) == v:
		return "covered"
	for e in snap.get("enemies", []):
		if e["pos"] == v:
			return "covered"
	var k := ""
	if snap.get("terrain", {}).has(v):
		k = String(snap["terrain"][v]["kind"])
	if k != "" and bool(Content.terrain(k, "blocks", false)):
		return "covered"
	return "sealed" if k == "growth" else "open"


static func vent_marks(snap: Dictionary, sky: Dictionary) -> Array:
	var out: Array = []
	var n := int(sky.get("spawn_in", -1))
	if n < 1 or n > VENT_MARK:
		return out
	for v in snap.get("map", {}).get("vents", []):
		var sealed: bool = snap["terrain"].has(v) and String(snap["terrain"][v]["kind"]) == "growth"
		out.append({"pos": v, "text": str(n), "urgent": n == 1 and not sealed, "sealed": sealed})
	return out


## Kit slots a live, unblocked gum will tar if the turn ends now.
static func gum_slots(snap: Dictionary, tele: Dictionary) -> Array:
	var out: Array = []
	var by_id := {}
	for e in snap.get("enemies", []):
		by_id[e["id"]] = e
	for ent in tele.get("enemies", []):
		if String(ent["type"]) == "gum" and bool(ent["live"]) and String(ent["blocked"]) == "" and by_id.has(ent["id"]):
			var slot := int(by_id[ent["id"]]["intent"].get("slot", -1))
			if slot >= 0 and not out.has(slot):
				out.append(slot)
	return out


## "No choke countdown announced yet on this floor" for cues' `announced`.
const NO_CUE := 99


## Danger transitions worth a sound or a banner, from the state before a
## step to the state after it: {sounds: [ids], banner: [line, line] or [],
## announced: int}. The choke cues have HYSTERESIS: `announced` is the lowest
## choke countdown already announced on this floor (NO_CUE = none; the shell
## keeps it and resets it on a new game, the tutorial and a run load, and a
## floor change resets it here), and the window tick (entering 1..SKY_AMBER)
## and the banner (reaching 1) fire only when a NEW minimum is reached - so a
## cleanse that pushes the choke back and the end turn that brings it down
## again do not replay the same warning turn after turn. A countdown already
## standing before the step counts as announced (a resumed run, a reset).
static func cues(prev: Dictionary, cur: Dictionary, announced: int = NO_CUE) -> Dictionary:
	var out := {"sounds": [], "banner": [], "announced": announced}
	if not bool(cur.get("ok", false)):
		return out
	var same_floor: bool = bool(prev.get("ok", false)) and int(prev.get("floor", -1)) == int(cur.get("floor", -2))
	var p: Dictionary = prev if same_floor else {}
	var ann := announced if same_floor else NO_CUE
	if bool(cur.get("lethal", false)) and not bool(p.get("lethal", false)):
		out["sounds"].append("warn")
	var cs: Dictionary = cur.get("sky", {})
	var ps: Dictionary = p.get("sky", {})
	var c_now := -1 if bool(cs.get("choking", false)) else int(cs.get("choke_in", -1))
	var c_prev := -1 if bool(ps.get("choking", false)) else int(ps.get("choke_in", -1))
	if c_prev >= 1 and c_prev <= SKY_AMBER:
		ann = mini(ann, c_prev)
	if c_now >= 1 and c_now <= SKY_AMBER and c_now < ann:
		if c_now == 1:
			out["banner"] = ["THE SMOG THICKENS", "it chokes from next turn"]
			if not out["sounds"].has("warn"):
				out["sounds"].append("warn")
		elif ann > SKY_AMBER and not out["sounds"].has("warn"):
			out["sounds"].append("warn")
		ann = c_now
	out["announced"] = ann
	return out
