extends SceneTree
## Regression corpus replay (review §7.6, style guide §2): every
## tests/regressions/*.json is a (seed, config, actions) pair with an
## expected outcome and, for the hand-authored combo demos, the event
## patterns that must appear in order. Each record is replayed on a fresh
## Game and fails on any illegal/error event, an outcome mismatch, a missing
## event pattern, or (REGRESS_STRICT=1) a final state_hash mismatch.
##
## Run:  godot --headless --path . --script tests/test_regressions.gd
##   REGRESS_STRICT=1  also compare the stored final state hash
##   REGEN=1           rewrite expect (won/floor/turns/timeout), hash and
##                     sim_version from the replay, printing outcome diffs;
##                     event patterns are hand-authored and are never rewritten
##   REGRESS_DIR       record directory (default tests/regressions)
## Exit 1 on any failure; prints "regressions: N ok, M failed".

const Regress := preload("res://tests/regress_lib.gd")


func _init() -> void:
	var strict := OS.get_environment("REGRESS_STRICT") == "1"
	var regen := OS.get_environment("REGEN") == "1"
	var dir := OS.get_environment("REGRESS_DIR")
	if dir == "":
		dir = Regress.DIR
	var paths := Regress.list_records(dir)
	print("=== regressions | dir %s | %d records | strict %s | regen %s ===" % [dir, paths.size(), str(strict), str(regen)])
	if paths.is_empty():
		print("FAIL: no records found in %s" % dir)
		print("regressions: 0 ok, 1 failed")
		quit(1)
		return
	var ok := 0
	var failed := 0
	for path in paths:
		var problems := _check(String(path), strict, regen)
		var name := String(path).get_file()
		if problems.is_empty():
			ok += 1
		else:
			failed += 1
			for p in problems:
				print("FAIL %s: %s" % [name, p])
	print("regressions: %d ok, %d failed" % [ok, failed])
	quit(1 if failed > 0 else 0)


## Replay one record; returns the list of problems (empty = pass).
func _check(path: String, strict: bool, regen: bool) -> Array:
	var problems: Array = []
	var name := path.get_file()
	var rec := Regress.load_record(path)
	if rec.is_empty():
		return ["unreadable record"]
	if int(rec["sim_version"]) != Regress.SIM_VERSION and not regen:
		problems.append("stale record: sim_version %d != %d (rerun with REGEN=1 after checking the outcome)" % [
			int(rec["sim_version"]), Regress.SIM_VERSION])
	var r := Regress.replay(rec)
	var game = r["game"]
	var events: Array = r["events"]
	if int(r["illegal"]) > 0 or int(r["errors"]) > 0:
		problems.append("%d illegal + %d error events during replay" % [int(r["illegal"]), int(r["errors"])])
	var out := Regress.outcome(game)
	var expect: Dictionary = rec["expect"]
	var diffs: Array = []
	for k in ["won", "floor", "turns", "timeout"]:
		if expect.has(k) and expect[k] != out[k]:
			diffs.append("%s %s -> %s" % [k, str(expect[k]), str(out[k])])
	var hash_now: String = game.state_hash()
	var hash_changed: bool = rec.has("hash") and String(rec["hash"]) != hash_now
	if not regen:
		for d in diffs:
			problems.append("outcome mismatch: " + d)
		if strict and hash_changed:
			problems.append("state hash mismatch (strict)")
	var patterns: Array = expect.get("events", [])
	if not patterns.is_empty():
		var m := Regress.match_events(events, patterns)
		if not bool(m["ok"]):
			problems.append("event pattern %d/%d not found in order: %s" % [
				int(m["matched"]) + 1, patterns.size(), str(m["missing"])])
			problems.append("trace: " + Regress.trace(events))
	var line := "%-36s %s floor %d turns %3d %s events %d" % [
		name, "WON " if out["won"] else ("TIME" if out["timeout"] else "died"),
		int(out["floor"]), int(out["turns"]),
		"hash CHANGED" if hash_changed else ("hash ok" if rec.has("hash") else "no hash"), events.size()]
	if not String(rec.get("note", "")).is_empty():
		line += "  (%s)" % String(rec["note"])
	print(("ok   " if problems.is_empty() else "FAIL ") + line)
	if regen:
		for d in diffs:
			print("     regen %s: %s" % [name, d])
		if hash_changed:
			print("     regen %s: hash rewritten" % name)
		if int(rec["sim_version"]) != Regress.SIM_VERSION:
			print("     regen %s: sim_version %d -> %d" % [name, int(rec["sim_version"]), Regress.SIM_VERSION])
		var new_expect: Dictionary = expect.duplicate(true)
		for k in ["won", "floor", "turns", "timeout"]:
			if expect.has(k) or k == "won" or k == "floor":
				new_expect[k] = out[k]
		var new_rec := {
			"seed": rec["seed"], "config": rec["config"], "actions": rec["actions"],
			"expect": new_expect, "note": rec.get("note", ""),
			"sim_version": Regress.SIM_VERSION, "hash": hash_now,
		}
		if not Regress.save_record(path, new_rec):
			problems.append("could not rewrite record")
	return problems
