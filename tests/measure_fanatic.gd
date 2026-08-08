extends SceneTree
## Fanatic per-build measurement: the build-viability table from BALANCE.md
## ("every build > 0" target) at proper sample size, plus timeout seeds.
## Run: [FANATIC_SEEDS=100] godot --headless --path . --script tests/measure_fanatic.gd

const Game := preload("res://sim/game.gd")
const Fanatic := preload("res://bots/fanatic.gd")


func _init() -> void:
	var seeds := 100
	if OS.get_environment("FANATIC_SEEDS") != "":
		seeds = int(OS.get_environment("FANATIC_SEEDS"))
	var runs := {}
	var wins := {}
	var floors := {}
	var timeouts: Array = []
	for s in range(1, seeds + 1):
		var game = Game.new(s)
		var bot = Fanatic.new()
		bot.reset(s * 7919 + 17)
		var n := 0
		while not game.over and n < 4000 and game.total_turns < 400:
			game.step(bot.choose_action(game.snapshot(), game.legal_actions()))
			n += 1
		var b: String = bot.get_build()
		runs[b] = int(runs.get(b, 0)) + 1
		floors[b] = int(floors.get(b, 0)) + game.floor_num
		if game.won:
			wins[b] = int(wins.get(b, 0)) + 1
		elif not game.over:
			timeouts.append("%s seed %d floor %d" % [b, s, game.floor_num])
	var total_w := 0
	for b in runs:
		total_w += int(wins.get(b, 0))
		print("%-10s %2d/%2d wins, avg floor %.1f" % [b, wins.get(b, 0), runs[b], float(floors[b]) / runs[b]])
	print("total %d/%d, timeouts: %s" % [total_w, seeds, str(timeouts)])
	quit(0)
