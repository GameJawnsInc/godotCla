extends SceneTree
## Turn a phone run into a regression pair. The shell appends every action of
## a live run to a save log (shell/main.gd, header + one action per line) and
## keeps finished logs under user://runs/ - this replays one through the pure
## sim and writes the tests/regressions/*.json record it proves.
##
##   IMPORT_RUN=<path to a .save> IMPORT_OUT=<path to .json> [IMPORT_NOTE=...] \
##     godot --headless --path . --script tests/import_run.gd
##
## The save's header version must equal Game.SIM_VERSION: a log recorded
## before a sim change replays into a different game, so importing it would
## mint a record that never happened. Such a save is refused, not guessed at.

const Game := preload("res://sim/game.gd")
const Regress := preload("res://tests/regress_lib.gd")


func _init() -> void:
	var path := OS.get_environment("IMPORT_RUN")
	var out := OS.get_environment("IMPORT_OUT")
	if path == "" or out == "":
		printerr("usage: IMPORT_RUN=<run.save> IMPORT_OUT=<record.json> [IMPORT_NOTE=...] godot --headless --path . --script tests/import_run.gd")
		quit(2)
		return
	var parsed := parse_save(path)
	if not bool(parsed.get("ok", false)):
		printerr(String(parsed.get("err", "unreadable save")))
		quit(1)
		return
	var note := OS.get_environment("IMPORT_NOTE")
	if note == "":
		note = "imported phone run: seed %d, tier %d, %d actions" % [
			int(parsed["seed"]), int(parsed["tier"]), parsed["actions"].size()]
	var rec := build_record(parsed, note)
	if not Regress.save_record(out, rec):
		quit(1)
		return
	var ex: Dictionary = rec["expect"]
	print("imported %s -> %s" % [path, out])
	print("seed %d  config %s  actions %d" % [int(rec["seed"]), JSON.stringify(rec["config"]), rec["actions"].size()])
	print("outcome: won=%s floor=%d turns=%d timeout=%s illegal=%d errors=%d hash=%s" % [
		ex["won"], int(ex["floor"]), int(ex["turns"]), ex["timeout"],
		int(rec["_illegal"]), int(rec["_errors"]), String(rec["hash"])])
	quit(0)


## Read a shell run save: the var_to_str header line, then one var_to_str
## action per line. Returns {ok, seed, tier, config, actions, skipped} or
## {ok: false, err} with a message meant for a human.
static func parse_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "err": "no such run save: %s" % path}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "err": "cannot read %s (error %d)" % [path, FileAccess.get_open_error()]}
	var head = str_to_var(f.get_line())
	if not (head is Dictionary) or not head.has("seed") or not head.has("v"):
		f.close()
		return {"ok": false, "err": "%s: first line is not a shell run header" % path}
	var v := int(head["v"])
	if v != Game.SIM_VERSION:
		f.close()
		return {"ok": false, "err": "%s: recorded on sim_version %d, this build is %d - the log would replay into a different game, so it cannot be imported" % [path, v, Game.SIM_VERSION]}
	var actions: Array = []
	var skipped := 0
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() == "":
			continue
		var act = str_to_var(line)
		if act is Dictionary:
			actions.append(act)
		else:
			skipped += 1
	f.close()
	return {
		"ok": true,
		"seed": int(head["seed"]),
		"tier": int(head.get("tier", 0)),
		"config": Dictionary(head.get("config", {})),
		"actions": actions,
		"skipped": skipped,
	}


## Replay a parsed save on a fresh sim and build the regression record
## (tests/regress_lib.gd schema; "_illegal"/"_errors" are reporting-only and
## never written by save_record, which only stores KEY_ORDER keys).
static func build_record(parsed: Dictionary, note: String) -> Dictionary:
	var cfg: Dictionary = parsed["config"]
	var game = Game.new(int(parsed["seed"]), cfg)
	var illegal := 0
	var errors := 0
	var acts: Array = []
	for a in parsed["actions"]:
		acts.append(Regress.act_to_json(a))
		for ev in game.step(a):
			var t := String(ev.get("t", ""))
			if t == "illegal":
				illegal += 1
			elif t == "error":
				errors += 1
	return {
		"seed": int(parsed["seed"]),
		"config": Regress.config_to_json(cfg),
		"actions": acts,
		"expect": Regress.outcome(game),
		"note": note,
		"sim_version": Game.SIM_VERSION,
		"hash": game.state_hash(),
		"_illegal": illegal,
		"_errors": errors,
	}
