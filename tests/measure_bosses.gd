extends SceneTree
## Per-boss arrival/conversion measurement: which floor-7 boss each seed
## draws, and whether the run converts the arrival into a win.
## Run: [BOSS_BOT=<persona>] [BOSS_SEEDS=<n>] godot --headless --path . --script tests/measure_bosses.gd

const Game := preload("res://sim/game.gd")
const Content := preload("res://sim/content.gd")
const BOTS := {
	"wanderer": preload("res://bots/wanderer.gd"),
	"sprout": preload("res://bots/sprout.gd"),
	"magpie": preload("res://bots/magpie.gd"),
	"fanatic": preload("res://bots/fanatic.gd"),
	"optimizer": preload("res://bots/optimizer.gd"),
	"deeproot": preload("res://bots/deeproot.gd"),
}


func _init() -> void:
	var bot_name := OS.get_environment("BOSS_BOT")
	if bot_name == "":
		bot_name = "optimizer"
	var seeds := 45
	if OS.get_environment("BOSS_SEEDS") != "":
		seeds = int(OS.get_environment("BOSS_SEEDS"))
	var arrivals := {}
	var wins := {}
	for s in range(1, seeds + 1):
		var game = Game.new(s)
		var bot = BOTS[bot_name].new()
		bot.reset(s * 7919 + 17)
		if bot.has_method("set_sim"):
			bot.set_sim(game)
		var actions := 0
		var boss_kind := ""
		while not game.over and actions < 4000 and game.total_turns < 400:
			game.step(bot.choose_action(game.snapshot(), game.legal_actions()))
			actions += 1
			if boss_kind == "" and game.floor_num == 7:
				for e in game.enemies:
					if Content.ENEMIES[e["kind"]]["traits"].has("boss"):
						boss_kind = e["kind"]
		if boss_kind != "":
			arrivals[boss_kind] = arrivals.get(boss_kind, 0) + 1
			if game.won:
				wins[boss_kind] = wins.get(boss_kind, 0) + 1
	print("%s, %d seeds:" % [bot_name, seeds])
	for kind in arrivals:
		print("  %-14s %2d arrivals, %2d converted" % [kind, arrivals[kind], wins.get(kind, 0)])
	quit(0)
