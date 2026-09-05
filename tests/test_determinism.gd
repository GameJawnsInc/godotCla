extends SceneTree
## Determinism checks (style guide §2):
## 1) same seed + same bot, run twice -> identical final state hash
## 2) replaying the recorded action list on a fresh game -> identical hash
## 3) a mid-run clone driven by an identical bot stays in lockstep
## 4) the main rng after Game.new is independent of kit / grafts / pool /
##    bloom / packages config (shop stock is side-stream only)
## Every roster persona (bots/roster.gd) is checked.
## Run: godot --headless --path . --script tests/test_determinism.gd

const Game := preload("res://sim/game.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const Roster := preload("res://bots/roster.gd")

const SEEDS := [3, 11, 42]
const RNG_SEEDS := 10
const RNG_VARIANTS := [
	{"kit": ["solar_lance+", "seed_bomb", "mycelium_dash", "vine_whip", "water_jet"]},
	{"grafts": ["deep_cells", "verdant_pulse", "thick_bark", "bloom_surge", "solar_core", "carapace"]},
	{"pool": ["solar_lance", "seed_bomb", "vine_whip"]},
	{"bloom": 9},
	{"packages": ["mycology", "hydraulics", "aeolian"]},
]


func _init() -> void:
	var failures := 0
	var checks := 0
	for bot_name in Roster.names():
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
	# rng independence: config that only touches the shop/kit/bank must not
	# move the main stream (tests/test_economy.gd runs the 50-seed version)
	for s in range(1, RNG_SEEDS + 1):
		checks += 1
		var base_state: int = Game.new(s).rng.state
		for v in RNG_VARIANTS:
			if Game.new(s, v).rng.state != base_state:
				failures += 1
				print("FAIL rng state depends on config: seed %d %s" % [s, str(v)])
				break
	if failures == 0:
		print("determinism: OK (%d checks, %d personas)" % [checks, Roster.names().size()])
	quit(1 if failures > 0 else 0)


func _clone_check(seed_v: int) -> bool:
	var game = Game.new(seed_v)
	var bot = Roster.make("optimizer", seed_v)
	var actions := 0
	while not game.over and actions < 60:
		game.step(bot.choose_action(game.snapshot(), game.legal_actions()))
		actions += 1
	var fork = game.clone()
	var bot2 = Roster.script("optimizer").new()
	bot2.rng.state = bot.rng.state
	while not game.over and actions < Sweep.MAX_ACTIONS and game.total_turns < Sweep.MAX_TURNS:
		game.step(bot.choose_action(game.snapshot(), game.legal_actions()))
		actions += 1
	var actions2 := 60
	while not fork.over and actions2 < Sweep.MAX_ACTIONS and fork.total_turns < Sweep.MAX_TURNS:
		fork.step(bot2.choose_action(fork.snapshot(), fork.legal_actions()))
		actions2 += 1
	return game.state_hash() == fork.state_hash()


func _run(bot_name: String, seed_v: int) -> Dictionary:
	var game = Game.new(seed_v)
	var actions: Array = []
	Sweep.run_loop(game, Roster.make(bot_name, seed_v), null, actions)
	return {"hash": game.state_hash(), "actions": actions}


func _replay(seed_v: int, actions: Array) -> String:
	var game = Game.new(seed_v)
	for act in actions:
		game.step(act)
	return game.state_hash()
