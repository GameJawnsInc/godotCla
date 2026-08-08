extends RefCounted
## Shared runner for balance sweeps: optimizer-persona runs under a sim config.

const Game := preload("res://sim/game.gd")
const Optimizer := preload("res://bots/optimizer.gd")


static func run_one(seed_v: int, config: Dictionary = {}) -> Dictionary:
	var game = Game.new(seed_v, config)
	var bot = Optimizer.new()
	bot.reset(seed_v * 7919 + 17)
	if bot.has_method("set_sim"):
		bot.set_sim(game)
	var actions := 0
	while not game.over and actions < 4000 and game.total_turns < 400:
		game.step(bot.choose_action(game.snapshot(), game.legal_actions()))
		actions += 1
	return {
		"won": game.won, "floor": game.floor_num, "turns": game.total_turns,
		"kit": game.player["kit"].duplicate(),
	}


static func measure(seeds: int, config: Dictionary = {}) -> Dictionary:
	var wins := 0
	var floors := 0
	var win_kits: Array = []
	for s in range(1, seeds + 1):
		var r := run_one(s, config)
		if r["won"]:
			wins += 1
			win_kits.append(r["kit"])
		floors += r["floor"]
	return {"wins": wins, "n": seeds, "avg_floor": float(floors) / seeds, "win_kits": win_kits}
