extends SceneTree
## Re-record every bot log in the regression corpus on its own persona - the
## per-bump step CLAUDE.md asks for ("re-record every bot log the change could
## have moved, not only the ones that stop replaying"), as a tool.
##
## A bot log is tests/regressions/{det,canary}_<persona>_s<seed>.json: the
## persona is the name between the first "_" and the last "_s", the seed the
## int after "_s". Each is replayed from scratch through
## Regress.record_run(persona, seed, <its config>, <its note>) and compared
## with the stored record: actions, outcome and final state hash.
##
## Run: [RERECORD_DRY=1] [REGRESS_DIR=<dir>] godot --headless --path . --script tests/rerecord_bots.gd
##   RERECORD_DRY=1  print the comparison, write nothing
##   REGRESS_DIR     record directory (default tests/regressions)
## Output, one line per record, then a summary:
##   unchanged <name>
##   CHANGED <name> outcome <a> -> <b>, acts <m> -> <n>, hash <old> -> <new>
##   rerecord: N records, C changed, U unchanged (dry|written)
## Without RERECORD_DRY every bot log is rewritten - unchanged ones too, so
## each carries the current sim_version - keeping its config, note and any
## hand-authored expect.events. Exit 1 on an unknown persona or an unreadable
## record (nothing is written for it).

const Regress := preload("res://tests/regress_lib.gd")
const Roster := preload("res://bots/roster.gd")


static func _outcome_text(expect: Dictionary) -> String:
	var status := "died"
	if bool(expect.get("won", false)):
		status = "won"
	elif bool(expect.get("timeout", false)):
		status = "timeout"
	return "%s f%d t%d" % [status, int(expect.get("floor", 0)), int(expect.get("turns", 0))]


static func _short(h: String) -> String:
	return h.substr(0, 8) if h != "" else "none"


func _init() -> void:
	var dry := OS.get_environment("RERECORD_DRY") == "1"
	var dir := OS.get_environment("REGRESS_DIR")
	if dir == "":
		dir = Regress.DIR
	var total := 0
	var changed := 0
	var unchanged := 0
	var errors := 0
	for path in Regress.list_records(dir):
		var name := String(path).get_file().get_basename()
		if not (name.begins_with("det_") or name.begins_with("canary_")):
			continue
		var first := name.find("_")
		var last := name.rfind("_s")
		if first < 0 or last <= first or not name.substr(last + 2).is_valid_int():
			print("FAIL %s: name is not <kind>_<persona>_s<seed>" % name)
			errors += 1
			continue
		var persona := name.substr(first + 1, last - first - 1)
		var seed_v := int(name.substr(last + 2))
		if not Roster.has(persona):
			print("FAIL %s: unknown persona '%s' (have: %s)" % [name, persona, ", ".join(Roster.names())])
			errors += 1
			continue
		var rec := Regress.load_record(String(path))
		if rec.is_empty():
			print("FAIL %s: unreadable record" % name)
			errors += 1
			continue
		total += 1
		var fresh := Regress.record_run(persona, seed_v, rec["game_config"], String(rec.get("note", "")))
		# keep the record's own JSON config and any hand-authored event patterns
		fresh["config"] = rec["config"]
		var old_expect: Dictionary = rec["expect"]
		if old_expect.has("events"):
			fresh["expect"]["events"] = old_expect["events"]
		var old_acts := JSON.stringify(Regress.ints_from_json(rec["actions"]))
		var new_acts := JSON.stringify(Regress.ints_from_json(fresh["actions"]))
		var old_out := _outcome_text(old_expect)
		var new_out := _outcome_text(fresh["expect"])
		var old_hash := String(rec.get("hash", ""))
		var new_hash := String(fresh["hash"])
		if old_acts == new_acts and old_out == new_out and old_hash == new_hash:
			unchanged += 1
			print("unchanged %s" % name)
		else:
			changed += 1
			print("CHANGED %s outcome %s -> %s, acts %d -> %d, hash %s -> %s" % [
				name, old_out, new_out, rec["actions"].size(), fresh["actions"].size(), _short(old_hash), _short(new_hash)])
		if not dry:
			if not Regress.save_record(String(path), fresh):
				print("FAIL %s: could not write" % name)
				errors += 1
	print("rerecord: %d records, %d changed, %d unchanged (%s)" % [total, changed, unchanged, "dry" if dry else "written"])
	quit(1 if errors > 0 else 0)
