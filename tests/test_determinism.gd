extends SceneTree
## Determinism checks (style guide §2):
## 1) same seed + same bot, run twice -> identical final state hash
## 2) replaying the recorded action list on a fresh game -> identical hash
## Run: godot --headless --path . --script tests/test_determinism.gd

const Game := preload("res://sim/game.gd")
const BOTS := {
	"wanderer": preload("res://bots/wanderer.gd"),
	"sprout": preload("res://bots/sprout.gd"),
	"optimizer": preload("res://bots/optimizer.gd"),
}

const SEEDS := [3, 11, 42]


func _init() -> void:
	var failures := 0
	var checks := 0
	for bot_name in BOTS:
		for s in SEEDS:
			var a := _run(bot_name, s)
			var b := _run(bot_name, s)
			var c := _replay(s, a["actions"])
			checks += 2
			if a["hash"] != b["hash"]:
				failures += 1
				print("FAIL rerun mismatch: %s seed %d" % [bot_name, s])
			if a["hash"] != c:
				failures += 1
				print("FAIL replay mismatch: %s seed %d" % [bot_name, s])
	# clone determinism: fork mid-run, drive both with identical bots
	for s in SEEDS:
		checks += 1
		if not _clone_check(s):
			failures += 1
			print("FAIL clone divergence: seed %d" % s)
	if failures == 0:
		print("determinism: OK (%d checks)" % checks)
	quit(1 if failures > 0 else 0)


func _clone_check(seed_v: int) -> bool:
	var game = Game.new(seed_v)
	var bot = BOTS["optimizer"].new()
	bot.reset(seed_v * 7919 + 17)
	var actions := 0
	while not game.over and actions < 60:
		game.step(bot.choose_action(game.snapshot(), game.legal_actions()))
		actions += 1
	var fork = game.clone()
	var bot2 = BOTS["optimizer"].new()
	bot2.rng.state = bot.rng.state
	while not game.over and actions < 4000 and game.total_turns < 400:
		game.step(bot.choose_action(game.snapshot(), game.legal_actions()))
		actions += 1
	var actions2 := 60
	while not fork.over and actions2 < 4000 and fork.total_turns < 400:
		fork.step(bot2.choose_action(fork.snapshot(), fork.legal_actions()))
		actions2 += 1
	return game.state_hash() == fork.state_hash()


func _run(bot_name: String, seed_v: int) -> Dictionary:
	var game = Game.new(seed_v)
	var bot = BOTS[bot_name].new()
	bot.reset(seed_v * 7919 + 17)
	var actions: Array = []
	while not game.over and actions.size() < 4000 and game.total_turns < 400:
		var act: Dictionary = bot.choose_action(game.snapshot(), game.legal_actions())
		actions.append(act)
		game.step(act)
	return {"hash": game.state_hash(), "actions": actions}


func _replay(seed_v: int, actions: Array) -> String:
	var game = Game.new(seed_v)
	for act in actions:
		game.step(act)
	return game.state_hash()
