extends SceneTree
## Focused kit check: measure one kit config at N seeds — the "verify any
## outlier at 30+ seeds before patching" step from docs/BALANCE.md.
## Run: VERIFY_EXTRAS=thorn_shield,overgrowth VERIFY_SEEDS=30 [SWEEP_BOT=deeproot] \
##   godot --headless --path . --script tests/verify_kit.gd
## Empty VERIFY_EXTRAS measures the standard-kit baseline.

const Content := preload("res://sim/content.gd")
const Sweep := preload("res://tests/sweep_lib.gd")


func _init() -> void:
	var seeds := 30
	if OS.get_environment("VERIFY_SEEDS") != "":
		seeds = int(OS.get_environment("VERIFY_SEEDS"))
	var cfg := {}
	var extras := OS.get_environment("VERIFY_EXTRAS")
	if extras != "":
		var kit: Array = Content.STARTING_KIT.duplicate()
		kit.append_array(extras.split(","))
		cfg["kit"] = kit
	var m := Sweep.measure(seeds, cfg, Sweep.pick_bot())
	var label := extras if extras != "" else "baseline"
	print("%s: %d/%d wins, avg floor %.1f" % [label, m["wins"], m["n"], m["avg_floor"]])
	quit(0)
