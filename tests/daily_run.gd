extends SceneTree
## Daily run: the seed comes from today's date (UTC) and the run's config comes
## from that seed alone - `Profile.daily_config` picks the loadout, the one
## package and the mutator off the profile's frozen DAILY_* lists, so a content
## table that grows later never moves an earlier date's challenge. Deterministic
## sim means everyone playing today's date plays the same run; the optimizer
## replay hash doubles as a verification fingerprint.
## Run: godot --headless --path . --script tests/daily_run.gd

const Content := preload("res://sim/content.gd")
const Game := preload("res://sim/game.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const Roster := preload("res://bots/roster.gd")
const Profile := preload("res://meta/profile.gd")


func _init() -> void:
	var date := Time.get_date_string_from_system(true)
	var seed_v: int = hash(date) & 0x7FFFFFFF
	# career-agnostic: the daily needs nothing unlocked and unlocks nothing
	var daily: Dictionary = Profile.daily_config(seed_v)
	var config: Dictionary = Profile.daily_game_config(seed_v)
	var mut := String(daily["mutator"])
	var pkg := String(daily["package"])
	print("TENDER daily %s — seed %d" % [date, seed_v])
	print("  loadout: %s (%s)" % [
		Content.LOADOUTS[daily["loadout"]]["name"], str(Content.LOADOUTS[daily["loadout"]]["kit"])])
	print("  package: %s" % ("none" if pkg == "" else "%s %s" % [pkg, str(Content.PACKAGES[pkg])]))
	print("  mutator: %s" % ("none" if mut == "" else "%s (%s)" % [mut, Content.MUTATORS[mut]["desc"]]))
	print(Sweep.header("daily_run", ",".join(Roster.names()), config, [seed_v]))
	for bot_name in Roster.names():
		var game = Game.new(seed_v, config)
		Sweep.run_loop(game, Roster.make(bot_name, seed_v))
		var outcome := "WON" if game.won else ("died floor %d (%s)" % [game.floor_num, game.death_cause])
		print("  %-16s %s — turns %d, bloom %d" % [bot_name, outcome, game.total_turns, game.bloom])
		if bot_name == "optimizer":
			print("  verification hash: %s" % game.state_hash().substr(0, 16))
	quit(0)
