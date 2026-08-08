extends SceneTree
## Difficulty tier sweep: every tier must stay bot-winnable.
## Run: godot --headless --path . --script tests/sweep_tiers.gd

const Content := preload("res://sim/content.gd")
const Sweep := preload("res://tests/sweep_lib.gd")

const SEEDS := 20


const HEURISTIC_BAND := 5  # tiers above this bind the ceiling; judge with SWEEP_BOT=deeproot


func _init() -> void:
	var bot := Sweep.pick_bot()
	var unwinnable := 0
	for t in range(Content.TIERS.size() + 1):
		var m := Sweep.measure(SEEDS, {"tier": t}, bot)
		var label: String = "base" if t == 0 else Content.TIERS[t - 1]["name"]
		print("tier %d (%-16s) %2d/%d wins, avg floor %.1f" % [t, label, m["wins"], m["n"], m["avg_floor"]])
		if m["wins"] == 0 and (t <= HEURISTIC_BAND or bot != null):
			unwinnable += 1
	if unwinnable > 0:
		print("WARNING: %d tier(s) had zero wins for this bot" % unwinnable)
	quit(1 if unwinnable > 0 else 0)
