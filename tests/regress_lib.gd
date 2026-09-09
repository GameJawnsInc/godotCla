extends RefCounted
## Regression-corpus library (review §7.6): the JSON codec for
## tests/regressions/*.json, a replayer that collects every event, and the
## in-order subset matcher the runner asserts expected events with.
##
## Record schema (one JSON object per file):
##   seed         int
##   config       Game.new config in JSON form (see config_from_json); a
##                "fixed_floor" may be written as {"room": [ascii rows],
##                "fdef": {...}, "terrain": [{"pos": [x, y], "kind": k}]}
##                and is parsed into the sim's {gen, fdef} shape on load
##   actions      action list; Vector2i values are [x, y] pairs
##   expect       {won, floor, turns?, timeout?, events?: [pattern, ...]}
##                where every pattern is a subset match on the given keys
##   note         free text: what the record proves
##   sim_version  int, mirrors Game.SIM_VERSION (shell/main.gd
##                RUN_SAVE_VERSION reads the same constant)
##   hash         optional final Game.state_hash() (REGRESS_STRICT=1 only)
##
## The action codec is the same logic as tests/autopsy.gd (_act_to_json /
## _act_from_json); autopsy keeps its own copy so it stays standalone.

const Game := preload("res://sim/game.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const Roster := preload("res://bots/roster.gd")
const Tutorial := preload("res://shell/tutorial.gd")

## The one version constant lives in sim/game.gd; shell/main.gd
## RUN_SAVE_VERSION and tests/autopsy.gd SIM_VERSION read the same value.
const SIM_VERSION := Game.SIM_VERSION
const DIR := "res://tests/regressions"

## Top-level record keys in the order they are written.
const KEY_ORDER := ["seed", "config", "actions", "expect", "note", "sim_version", "hash"]


# --- action codec (same as tests/autopsy.gd) ----------------------------------

static func act_to_json(a: Dictionary) -> Dictionary:
	var out := {}
	for k in a:
		var v = a[k]
		out[k] = [v.x, v.y] if v is Vector2i else v
	return out


static func act_from_json(a: Dictionary) -> Dictionary:
	var out := {}
	for k in a:
		var v = a[k]
		if v is Array and v.size() == 2:
			out[k] = Vector2i(int(v[0]), int(v[1]))
		elif v is float:
			out[k] = int(v)
		else:
			out[k] = v
	return out


# --- config codec ---------------------------------------------------------------

## JSON has no int type: fold whole floats back to ints, recursively. Every
## numeric config value the sim reads is an int.
static func ints_from_json(v):
	if v is float:
		return int(v) if v == floor(v) else v
	if v is Array:
		var out: Array = []
		for x in v:
			out.append(ints_from_json(x))
		return out
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = ints_from_json(v[k])
		return out
	return v


## Parsed record config -> the Dictionary Game.new accepts. A "fixed_floor"
## written as {room, fdef, terrain?} becomes {gen, fdef}.
static func config_from_json(cfg_json: Dictionary) -> Dictionary:
	var cfg: Dictionary = ints_from_json(cfg_json)
	if cfg.has("fixed_floor") and cfg["fixed_floor"] is Dictionary and cfg["fixed_floor"].has("room"):
		var ff: Dictionary = cfg["fixed_floor"]
		var gen := room_to_gen(ff["room"])
		for t in ff.get("terrain", []):
			var p: Array = t["pos"]
			gen["terrain"][Vector2i(int(p[0]), int(p[1]))] = {"kind": String(t["kind"])}
		cfg["fixed_floor"] = {"gen": gen, "fdef": ff.get("fdef", {})}
	return cfg


## Bot-run configs (kit/pool/tier/mutators/packages) are already JSON-safe.
## A fixed_floor carrying a parsed "gen" cannot be written back; keep the
## "room" form in the record instead.
static func config_to_json(cfg: Dictionary) -> Dictionary:
	var out := cfg.duplicate(true)
	if out.has("fixed_floor") and out["fixed_floor"] is Dictionary and out["fixed_floor"].has("gen"):
		push_error("config_to_json: fixed_floor.gen is not JSON-serialisable; author it as {room, fdef}")
		out.erase("fixed_floor")
	return out


## ASCII rows -> the sim's fixed_floor "gen" dict. Same legend and parser as
## shell/tutorial.gd floor_config (glyph tables are reused from there):
## # wall · . floor · @ start · > stairs · + shrine · ^ vent · terrain and
## enemy glyphs per Tutorial.GLYPH_TERRAIN / GLYPH_ENEMY.
static func room_to_gen(rows_in: Array) -> Dictionary:
	var rows: Array = []
	for r in rows_in:
		rows.append(String(r))
	var h := rows.size()
	var w := 0
	for r in rows:
		w = maxi(w, String(r).length())
	var tiles: Array = []
	tiles.resize(w * h)
	tiles.fill(0)
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
			elif Tutorial.GLYPH_TERRAIN.has(ch):
				gen["terrain"][p] = {"kind": Tutorial.GLYPH_TERRAIN[ch]}
			elif Tutorial.GLYPH_ENEMY.has(ch):
				gen["enemies"].append({"kind": Tutorial.GLYPH_ENEMY[ch], "pos": p})
	gen["rooms"] = [Rect2i(1, 1, w - 2, h - 2)]
	return gen


# --- files ------------------------------------------------------------------------

## Sorted list of record paths under DIR (deterministic run order).
static func list_records(dir_path: String = DIR) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if not d.current_is_dir() and name.ends_with(".json"):
			out.append(dir_path.path_join(name))
		name = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


## Parse a record file. Returns {} (after push_error) when unreadable.
## The returned dict keeps "config" in JSON form (for writing back) and adds
## "game_config" (decoded) and "game_actions" (decoded).
static func load_record(path: String) -> Dictionary:
	var raw := FileAccess.get_file_as_string(path)
	if raw == "":
		push_error("cannot read %s" % path)
		return {}
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_error("%s: not a JSON object" % path)
		return {}
	var rec: Dictionary = parsed
	rec["seed"] = int(rec.get("seed", 0))
	rec["sim_version"] = int(rec.get("sim_version", 0))
	rec["config"] = rec.get("config", {})
	rec["actions"] = rec.get("actions", [])
	rec["expect"] = ints_from_json(rec.get("expect", {}))
	rec["game_config"] = config_from_json(rec["config"])
	var acts: Array = []
	for a in rec["actions"]:
		acts.append(act_from_json(a))
	rec["game_actions"] = acts
	return rec


## Write a record: one top-level key per line (KEY_ORDER), compact values,
## so a 1000-action bot log stays greppable and a hand-written demo diffs
## cleanly. Decoded helper keys (game_*) are never written.
static func save_record(path: String, rec: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % path)
		return false
	var lines: Array = []
	for k in KEY_ORDER:
		if rec.has(k):
			# whole floats (JSON round-trips, Vector2i components) are written as
			# ints so a REGEN pass does not churn every record on disk
			lines.append("%s: %s" % [JSON.stringify(k), JSON.stringify(ints_from_json(rec[k]))])
	f.store_string("{\n" + ",\n".join(lines) + "\n}\n")
	f.close()
	return true


# --- recording ----------------------------------------------------------------

## Play a roster persona on (seed, cfg) through Sweep.run_loop and return a
## record ready for save_record: expect carries won/floor/turns/timeout and
## the final state hash sits at the top level.
static func record_run(bot_name: String, seed_v: int, cfg: Dictionary, note: String) -> Dictionary:
	var game = Game.new(seed_v, cfg)
	var actions: Array = []
	var r := Sweep.run_loop(game, Roster.make(bot_name, seed_v), null, actions)
	var acts: Array = []
	for a in actions:
		acts.append(act_to_json(a))
	return {
		"seed": seed_v,
		"config": config_to_json(cfg),
		"actions": acts,
		"expect": {"won": r["won"], "floor": r["floor"], "turns": r["turns"], "timeout": r["timeout"]},
		"note": note,
		"sim_version": SIM_VERSION,
		"hash": game.state_hash(),
	}


# --- replay and matching ----------------------------------------------------

## Fresh game + every recorded action; collects all events in order.
## Actions after the game ends are still stepped: the sim answers with an
## "error" event, which the runner then flags.
static func replay(rec: Dictionary) -> Dictionary:
	var game = Game.new(int(rec["seed"]), rec["game_config"])
	var events: Array = []
	var illegal := 0
	var errors := 0
	for act in rec["game_actions"]:
		for ev in game.step(act):
			events.append(ev)
			var t := String(ev.get("t", ""))
			if t == "illegal":
				illegal += 1
			elif t == "error":
				errors += 1
	return {"game": game, "events": events, "illegal": illegal, "errors": errors}


static func outcome(game) -> Dictionary:
	return {"won": game.won, "floor": game.floor_num, "turns": game.total_turns, "timeout": not game.over}


## Subset match: every key of `pat` must be present in `ev` with an equal value.
static func event_matches(ev: Dictionary, pat: Dictionary) -> bool:
	for k in pat:
		if not ev.has(k):
			return false
		var a = ev[k]
		var b = pat[k]
		if a is String or b is String:
			if str(a) != str(b):
				return false
		elif a != b:
			return false
	return true


## Every pattern must match some event, in order (the search resumes after
## the previous match). Returns {ok, matched, missing} where `missing` is
## the first unmatched pattern (or {}) and `matched` the count found.
static func match_events(events: Array, patterns: Array) -> Dictionary:
	var i := 0
	var matched := 0
	for pat in patterns:
		var found := false
		while i < events.size():
			var ev: Dictionary = events[i]
			i += 1
			if event_matches(ev, pat):
				found = true
				break
		if not found:
			return {"ok": false, "matched": matched, "missing": pat}
		matched += 1
	return {"ok": true, "matched": matched, "missing": {}}


## Compact event trace for failure output: "t[:src][:amt]" per event.
static func trace(events: Array, limit: int = 40) -> String:
	var parts: Array = []
	for ev in events:
		var s := String(ev.get("t", "?"))
		if ev.has("src"):
			s += ":" + String(ev["src"])
		if ev.has("amt"):
			s += ":" + str(ev["amt"])
		parts.append(s)
		if parts.size() >= limit:
			parts.append("... (%d events)" % events.size())
			break
	return " ".join(parts)
