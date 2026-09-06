extends SceneTree
## Daily run: seed and mutator derived from today's date (UTC), full pool.
## Deterministic sim means everyone playing today's date plays the same run;
## the optimizer replay hash doubles as a verification fingerprint.
## Run: godot --headless --path . --script tests/daily_run.gd

const Content := preload("res://sim/content.gd")
const Game := preload("res://sim/game.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const Roster := preload("res://bots/roster.gd")

## The daily draws from the six launch mutators, in their original table order.
const DAILY_MUTATORS := ["kit_of_3", "double_oil", "brittle", "parched", "overtime", "boarded"]


func _init() -> void:
	var date := Time.get_date_string_from_system(true)
	var seed_v: int = hash(date) & 0x7FFFFFFF
	# a frozen list, not Content.MUTATORS.keys(): a table that grows would move
	# every date's daily onto a different mutator (and onto ones no career has)
	var muts: Array = DAILY_MUTATORS
	var mut: String = muts[seed_v % muts.size()]
	var config := {"mutators": [mut], "packages": Content.PACKAGES.keys()}
	print("TENDER daily %s — seed %d, mutator: %s (%s)" % [
		date, seed_v, mut, Content.MUTATORS[mut]["desc"]])
	print(Sweep.header("daily_run", ",".join(Roster.names()), config, [seed_v]))
	for bot_name in Roster.names():
		var game = Game.new(seed_v, config)
		Sweep.run_loop(game, Roster.make(bot_name, seed_v))
		var outcome := "WON" if game.won else ("died floor %d (%s)" % [game.floor_num, game.death_cause])
		print("  %-16s %s — turns %d, bloom %d" % [bot_name, outcome, game.total_turns, game.bloom])
		if bot_name == "optimizer":
			print("  verification hash: %s" % game.state_hash().substr(0, 16))
	quit(0)
