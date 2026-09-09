extends SceneTree
## Focused kit check: measure one kit config at N seeds — the "verify any
## outlier at 30+ seeds before patching" step from docs/BALANCE.md.
## Run: VERIFY_EXTRAS=thorn_shield,overgrowth VERIFY_SEEDS=30 [SWEEP_BOT=deeproot] \
##   godot --headless --path . --script tests/verify_kit.gd
## Empty VERIFY_EXTRAS measures the standard-kit baseline. VERIFY_BOT names a
## roster persona (overrides SWEEP_BOT; deeproot_rollout works); VERIFY_TIER
## and VERIFY_MUTATORS set the config; SWEEP_SEED_FROM shifts the seed range.

const Content := preload("res://sim/content.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const Roster := preload("res://bots/roster.gd")


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
	var bot_name := Sweep.pick_bot_name()
	var bot_label := ""
	if OS.get_environment("VERIFY_BOT") != "":
		bot_name = OS.get_environment("VERIFY_BOT")
		bot_label = " (%s)" % bot_name
	if not Roster.has(bot_name):
		push_error("unknown bot '%s' (have: %s)" % [bot_name.trim_prefix("UNKNOWN:"), ", ".join(Roster.names())])
		quit(1)
		return
	var seed_arr := Sweep.seed_list_from(seeds, Sweep.seed_from())
	print(Sweep.header("verify_kit", bot_name, cfg, seed_arr))
	var m := Sweep.measure(seed_arr, cfg, bot_name)
	var label := (extras if extras != "" else "baseline") + bot_label
	if cfg.has("tier"):
		label += " (tier %d)" % cfg["tier"]
	if cfg.has("mutators"):
		label += " [%s]" % ",".join(cfg["mutators"])
	print("%s: %d/%d wins, avg floor %.1f" % [label, m["wins"], m["n"], m["avg_floor"]])
	print("           win CI %s  timeouts %d  turns on wins %.1f  dmg taken/run %.1f" % [
		Sweep.fmt_ci(m["ci"]), m["timeouts"], m["mean_turns_on_wins"], m["mean_dmg_taken"]])
	m["tally"].print_block(m["n"], m["kits"])
	quit(0)
