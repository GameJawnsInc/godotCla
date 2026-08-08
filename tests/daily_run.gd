extends SceneTree
## Daily run: seed and mutator derived from today's date (UTC), full pool.
## Deterministic sim means everyone playing today's date plays the same run;
## the optimizer replay hash doubles as a verification fingerprint.
## Run: godot --headless --path . --script tests/daily_run.gd

const Content := preload("res://sim/content.gd")
const Game := preload("res://sim/game.gd")
const BOTS := {
	"wanderer": preload("res://bots/wanderer.gd"),
	"sprout": preload("res://bots/sprout.gd"),
	"optimizer": preload("res://bots/optimizer.gd"),
}


func _init() -> void:
	var date := Time.get_date_string_from_system(true)
	var seed_v: int = hash(date) & 0x7FFFFFFF
	var muts: Array = Content.MUTATORS.keys()
	var mut: String = muts[seed_v % muts.size()]
	var config := {"mutators": [mut], "packages": Content.PACKAGES.keys()}
	print("TENDER daily %s — seed %d, mutator: %s (%s)" % [
		date, seed_v, mut, Content.MUTATORS[mut]["desc"]])
	for bot_name in BOTS:
		var game = Game.new(seed_v, config)
		var bot = BOTS[bot_name].new()
		bot.reset(seed_v * 7919 + 17)
		var actions := 0
		while not game.over and actions < 4000 and game.total_turns < 400:
			game.step(bot.choose_action(game.snapshot(), game.legal_actions()))
			actions += 1
		var outcome := "WON" if game.won else ("died floor %d (%s)" % [game.floor_num, game.death_cause])
		print("  %-10s %s — turns %d, bloom %d" % [bot_name, outcome, game.total_turns, game.bloom])
		if bot_name == "optimizer":
			print("  verification hash: %s" % game.state_hash().substr(0, 16))
	quit(0)
