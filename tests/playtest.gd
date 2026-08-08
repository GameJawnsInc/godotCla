extends SceneTree
## Playtest harness (style guide §5): N seeds x M bot personas, headless.
## Reports wins, deaths by floor and cause, timeouts, turns, bloom.
## Run: godot --headless --path . --script tests/playtest.gd

const Game := preload("res://sim/game.gd")
const AsciiView := preload("res://sim/ascii_view.gd")
const BOTS := {
	"wanderer": preload("res://bots/wanderer.gd"),
	"optimizer": preload("res://bots/optimizer.gd"),
}

const SEEDS := 30
const MAX_ACTIONS := 4000
const MAX_TURNS := 400


func _init() -> void:
	print("=== TENDER playtest: %d seeds x %d personas ===" % [SEEDS, BOTS.size()])
	for bot_name in BOTS:
		var runs: Array = []
		for s in range(1, SEEDS + 1):
			runs.append(_run(bot_name, s))
		_report(bot_name, runs)
	print("\n--- sample frame: optimizer, seed 1, final state ---")
	print(_final_frame("optimizer", 1))
	quit(0)


func _run(bot_name: String, seed_v: int) -> Dictionary:
	var game = Game.new(seed_v)
	var bot = BOTS[bot_name].new()
	bot.reset(seed_v * 7919 + 17)
	var actions := 0
	while not game.over and actions < MAX_ACTIONS and game.total_turns < MAX_TURNS:
		var act: Dictionary = bot.choose_action(game.snapshot(), game.legal_actions())
		game.step(act)
		actions += 1
	return {
		"won": game.won, "timeout": not game.over, "floor": game.floor_num,
		"turns": game.total_turns, "bloom": game.bloom, "cause": game.death_cause,
	}


func _final_frame(bot_name: String, seed_v: int) -> String:
	var game = Game.new(seed_v)
	var bot = BOTS[bot_name].new()
	bot.reset(seed_v * 7919 + 17)
	var actions := 0
	while not game.over and actions < MAX_ACTIONS and game.total_turns < MAX_TURNS:
		var act: Dictionary = bot.choose_action(game.snapshot(), game.legal_actions())
		game.step(act)
		actions += 1
	return AsciiView.render(game.snapshot())


func _report(bot_name: String, runs: Array) -> void:
	var wins := 0
	var deaths := 0
	var timeouts := 0
	var floors := 0
	var turns := 0
	var bloom := 0
	var by_floor := {}
	var by_cause := {}
	for r in runs:
		floors += r["floor"]
		turns += r["turns"]
		bloom += r["bloom"]
		if r["won"]:
			wins += 1
		elif r["timeout"]:
			timeouts += 1
		else:
			deaths += 1
			by_floor[r["floor"]] = by_floor.get(r["floor"], 0) + 1
			by_cause[r["cause"]] = by_cause.get(r["cause"], 0) + 1
	var n := runs.size()
	print("%-10s wins %d/%d  deaths %d  timeouts %d  avg floor %.1f  avg turns %.1f  avg bloom %.1f" % [
		bot_name, wins, n, deaths, timeouts, float(floors) / n, float(turns) / n, float(bloom) / n])
	print("           deaths by floor %s  causes %s" % [str(by_floor), str(by_cause)])
