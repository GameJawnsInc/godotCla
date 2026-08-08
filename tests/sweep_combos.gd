extends SceneTree
## Pairwise combo sweep: seed the standard kit plus each ability pair, measure
## optimizer win rates, and flag outliers against the baseline.
## Run: godot --headless --path . --script tests/sweep_combos.gd

const Content := preload("res://sim/content.gd")
const Sweep := preload("res://tests/sweep_lib.gd")

const SEEDS := 10
const FLAG_MARGIN := 30  # percentage points from baseline


func _init() -> void:
	var bot := Sweep.pick_bot()
	var base := Sweep.measure(SEEDS, {}, bot)
	var base_pct: float = 100.0 * base["wins"] / base["n"]
	print("baseline (standard kit): %d/%d (%.0f%%), avg floor %.1f" % [base["wins"], base["n"], base_pct, base["avg_floor"]])

	var extras: Array = []
	for aid in Content.DRAFT_POOL:
		if not Content.STARTING_KIT.has(aid):
			extras.append(aid)

	var rows: Array = []
	for i in extras.size():
		for j in range(i + 1, extras.size()):
			var kit: Array = Content.STARTING_KIT.duplicate()
			kit.append(extras[i])
			kit.append(extras[j])
			var m := Sweep.measure(SEEDS, {"kit": kit}, bot)
			rows.append({"pair": "%s + %s" % [extras[i], extras[j]], "wins": m["wins"], "avg_floor": m["avg_floor"]})

	rows.sort_custom(func(a, b): return a["wins"] > b["wins"])
	print("\npair sweeps (%d pairs x %d seeds, standard kit + pair):" % [rows.size(), SEEDS])
	for r in rows:
		var pct: float = 100.0 * r["wins"] / SEEDS
		var flag := ""
		if pct >= base_pct + FLAG_MARGIN:
			flag = "  << OVERPERFORMS"
		elif pct <= base_pct - FLAG_MARGIN:
			flag = "  << UNDERPERFORMS"
		print("  %-28s %d/%d  avg floor %.1f%s" % [r["pair"], r["wins"], SEEDS, r["avg_floor"], flag])
	quit(0)
