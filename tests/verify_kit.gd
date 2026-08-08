extends SceneTree
## Focused kit check: measure one kit config at N seeds — the "verify any
## outlier at 30+ seeds before patching" step from docs/BALANCE.md.
## Run: VERIFY_EXTRAS=thorn_shield,overgrowth VERIFY_SEEDS=30 [SWEEP_BOT=deeproot] \
##   godot --headless --path . --script tests/verify_kit.gd
## Empty VERIFY_EXTRAS measures the standard-kit baseline.

const Content := preload("res://sim/content.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const BOTS := {
	"wanderer": preload("res://bots/wanderer.gd"),
	"sprout": preload("res://bots/sprout.gd"),
	"magpie": preload("res://bots/magpie.gd"),
	"fanatic": preload("res://bots/fanatic.gd"),
	"optimizer": preload("res://bots/optimizer.gd"),
	"deeproot": preload("res://bots/deeproot.gd"),
}


func _init() -> void:
	var seeds := 30
	if OS.get_environment("VERIFY_SEEDS") != "":
		seeds = int(OS.get_environment("VERIFY_SEEDS"))
	var cfg := {}
	if OS.get_environment("VERIFY_TIER") != "":
		cfg["tier"] = int(OS.get_environment("VERIFY_TIER"))
	if OS.get_environment("VERIFY_MUTATORS") != "":
		cfg["mutators"] = Array(OS.get_environment("VERIFY_MUTATORS").split(","))
	var extras := OS.get_environment("VERIFY_EXTRAS")
	if extras != "":
		var kit: Array = Content.STARTING_KIT.duplicate()
		kit.append_array(extras.split(","))
		cfg["kit"] = kit
	var bot: GDScript = Sweep.pick_bot()
	var bot_label := ""
	if OS.get_environment("VERIFY_BOT") != "":
		bot = BOTS[OS.get_environment("VERIFY_BOT")]
		bot_label = " (%s)" % OS.get_environment("VERIFY_BOT")
	var m := Sweep.measure(seeds, cfg, bot)
	var label := (extras if extras != "" else "baseline") + bot_label
	if cfg.has("tier"):
		label += " (tier %d)" % cfg["tier"]
	if cfg.has("mutators"):
		label += " [%s]" % ",".join(cfg["mutators"])
	print("%s: %d/%d wins, avg floor %.1f" % [label, m["wins"], m["n"], m["avg_floor"]])
	quit(0)
