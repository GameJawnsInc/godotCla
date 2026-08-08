extends SceneTree
## Package validation sweep: measure the optimizer with each tech package added
## to the draft pool, before that package ships to players.
## Run: godot --headless --path . --script tests/sweep_packages.gd

const Content := preload("res://sim/content.gd")
const Sweep := preload("res://tests/sweep_lib.gd")

const SEEDS := 20


func _init() -> void:
	var bot := Sweep.pick_bot()
	var base := Sweep.measure(SEEDS, {}, bot)
	print("baseline pool: %d/%d wins, avg floor %.1f" % [base["wins"], base["n"], base["avg_floor"]])
	var configs := {}
	for pkg in Content.PACKAGES:
		configs[pkg] = {"packages": [pkg]}
	configs["all three"] = {"packages": Content.PACKAGES.keys()}
	for label in configs:
		var m := Sweep.measure(SEEDS, configs[label], bot)
		var drafted := {}
		for kit in m["win_kits"]:
			for aid in kit:
				if not Content.DRAFT_POOL.has(aid) and not Content.STARTING_KIT.has(aid):
					drafted[aid] = drafted.get(aid, 0) + 1
		print("+ %-10s %d/%d wins, avg floor %.1f, package abilities in winning kits: %s" % [
			label, m["wins"], m["n"], m["avg_floor"], str(drafted)])
	quit(0)
