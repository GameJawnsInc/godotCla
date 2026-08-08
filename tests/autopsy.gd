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
##   AUTOPSY_JSON (path: also dump the recorded run as JSON)
## Replay mode:
##   AUTOPSY_REPLAY=<path.json> godot --headless --path . --script tests/autopsy.gd

const Game := preload("res://sim/game.gd")
const AsciiView := preload("res://sim/ascii_view.gd")
const BOTS := {
	"wanderer": preload("res://bots/wanderer.gd"),
	"sprout": preload("res://bots/sprout.gd"),
	"magpie": preload("res://bots/magpie.gd"),
	"fanatic": preload("res://bots/fanatic.gd"),
	"optimizer": preload("res://bots/optimizer.gd"),
	"deeproot": preload("res://bots/deeproot.gd"),
}

const MAX_ACTIONS := 4000
const MAX_TURNS := 400


func _init() -> void:
	var last := int(_env("AUTOPSY_LAST", "12"))
	var replay_path := OS.get_environment("AUTOPSY_REPLAY")
	if replay_path != "":
		_replay_file(replay_path, last)
		quit(0)
		return

	var bot_name := _env("AUTOPSY_BOT", "optimizer")
	if not BOTS.has(bot_name):
		push_error("unknown bot '%s' (have: %s)" % [bot_name, ", ".join(BOTS.keys())])
		quit(1)
		return
	var seed_v := int(_env("AUTOPSY_SEED", "1"))
	var cfg := _config_from_env()

	var game = Game.new(seed_v, cfg)
	var bot = BOTS[bot_name].new()
	bot.reset(seed_v * 7919 + 17)
	if bot.has_method("set_sim"):
		bot.set_sim(game)
	var actions: Array = []
	while not game.over and actions.size() < MAX_ACTIONS and game.total_turns < MAX_TURNS:
		var act: Dictionary = bot.choose_action(game.snapshot(), game.legal_actions())
		actions.append(act)
		game.step(act)

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
		_save_record(json_path, seed_v, cfg, actions)
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


func _save_record(path: String, seed_v: int, cfg: Dictionary, actions: Array) -> void:
	var acts: Array = []
	for a in actions:
		acts.append(_act_to_json(a))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"seed": seed_v, "config": cfg, "actions": acts}))
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
