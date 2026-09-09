extends SceneTree
## Death autopsy: run a (seed, bot) game headless, then replay it and print the
## ASCII frames leading up to the end — the agent's way to "watch" a death
## (style guide §4). Records optionally dump as (seed, config, action list)
## JSON, the regression-pair format from style guide §2.
##
## Record mode (default):
##   AUTOPSY_BOT=optimizer AUTOPSY_SEED=42 godot --headless --path . --script tests/autopsy.gd
## Knobs: AUTOPSY_LAST (frames to print, default 12), AUTOPSY_TIER,
##   AUTOPSY_MUTATORS (comma list), AUTOPSY_KIT (comma list),
##   AUTOPSY_JSON (path: also dump the recorded run as JSON with the outcome
##   under "expect" and the sim version, the tests/regressions schema)
## Replay mode:
##   AUTOPSY_REPLAY=<path.json> godot --headless --path . --script tests/autopsy.gd

const Game := preload("res://sim/game.gd")
const AsciiView := preload("res://sim/ascii_view.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const Roster := preload("res://bots/roster.gd")

## Game.SIM_VERSION is the single version source (shell/main.gd
## RUN_SAVE_VERSION reads it too): a record replayed across a sim change
## diverges silently, so the version travels with the action log.
const SIM_VERSION := Game.SIM_VERSION


func _init() -> void:
	var last := int(_env("AUTOPSY_LAST", "12"))
	var replay_path := OS.get_environment("AUTOPSY_REPLAY")
	if replay_path != "":
		_replay_file(replay_path, last)
		quit(0)
		return

	var bot_name := _env("AUTOPSY_BOT", "optimizer")
	if not Roster.has(bot_name):
		push_error("unknown bot '%s' (have: %s)" % [bot_name, ", ".join(Roster.names())])
		quit(1)
		return
	var seed_v := int(_env("AUTOPSY_SEED", "1"))
	var cfg := _config_from_env()
	print(Sweep.header("autopsy", bot_name, cfg, [seed_v]))

	var game = Game.new(seed_v, cfg)
	var actions: Array = []
	Sweep.run_loop(game, Roster.make(bot_name, seed_v), null, actions)

	var outcome := "TIMEOUT"
	if game.won:
		outcome = "WON"
	elif game.over:
		outcome = "DIED (%s)" % game.death_cause
	print("%s seed %d cfg %s: %s  floor %d  turn %d  bloom %d" % [
		bot_name, seed_v, str(cfg), outcome, game.floor_num, game.total_turns, game.bloom])
	print("final kit: %s" % ", ".join(game.player["kit"]))

	var json_path := OS.get_environment("AUTOPSY_JSON")
	if json_path != "":
		var expect := {"won": game.won, "floor": game.floor_num, "turns": game.total_turns}
		_save_record(json_path, seed_v, cfg, actions, expect)
		print("record written to %s" % json_path)

	_dump_frames(seed_v, cfg, actions, last)
	quit(0)


func _replay_file(path: String, last: int) -> void:
	var raw := FileAccess.get_file_as_string(path)
	if raw == "":
		push_error("cannot read %s" % path)
		return
	var rec: Dictionary = JSON.parse_string(raw)
	var cfg := {}
	for k in rec.get("config", {}):
		var v = rec["config"][k]
		cfg[k] = int(v) if v is float else v
	var actions: Array = []
	for a in rec["actions"]:
		actions.append(_act_from_json(a))
	print("replaying %s: seed %d, %d actions" % [path, int(rec["seed"]), actions.size()])
	_dump_frames(int(rec["seed"]), cfg, actions, last)


## Re-run the game from scratch and print the board after each of the last
## `last` actions (plus the frame just before them, for context).
func _dump_frames(seed_v: int, cfg: Dictionary, actions: Array, last: int) -> void:
	var g = Game.new(seed_v, cfg)
	var start := maxi(0, actions.size() - last)
	for i in actions.size():
		if g.over:
			break
		if i == start:
			print("\n=== board before action %d ===" % i)
			print(AsciiView.render(g.snapshot()))
		g.step(actions[i])
		if i >= start:
			print("\n=== action %d: %s ===" % [i, str(actions[i])])
			print(AsciiView.render(g.snapshot()))


func _config_from_env() -> Dictionary:
	var cfg := {}
	if OS.get_environment("AUTOPSY_TIER") != "":
		cfg["tier"] = int(OS.get_environment("AUTOPSY_TIER"))
	if OS.get_environment("AUTOPSY_MUTATORS") != "":
		cfg["mutators"] = Array(OS.get_environment("AUTOPSY_MUTATORS").split(","))
	if OS.get_environment("AUTOPSY_KIT") != "":
		cfg["kit"] = Array(OS.get_environment("AUTOPSY_KIT").split(","))
	return cfg


func _save_record(path: String, seed_v: int, cfg: Dictionary, actions: Array, expect: Dictionary) -> void:
	var acts: Array = []
	for a in actions:
		acts.append(_act_to_json(a))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % path)
		return
	f.store_string(JSON.stringify({
		"seed": seed_v, "config": cfg, "actions": acts,
		"expect": expect, "sim_version": SIM_VERSION,
	}))
	f.close()


func _act_to_json(a: Dictionary) -> Dictionary:
	var out := {}
	for k in a:
		var v = a[k]
		out[k] = [v.x, v.y] if v is Vector2i else v
	return out


func _act_from_json(a: Dictionary) -> Dictionary:
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


func _env(name: String, def: String) -> String:
	var v := OS.get_environment(name)
	return v if v != "" else def
