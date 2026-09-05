extends SceneTree
## Playtest harness (style guide §5): N seeds x M bot personas, headless.
## Reports wins, deaths by floor and cause, timeouts, turns, bloom, then the
## per-persona tally block (casts, pick rates, damage shares, combos, economy,
## clock stalls) from tests/tally.gd.
## Run: [PLAYTEST_SEEDS=30] [PLAYTEST_BOTS=a,b,c] godot --headless --path . --script tests/playtest.gd
## CI gate (review §7.6): after every persona, each BALANCE.md band is
## checked against the run's Wilson interval (a band fails only when the
## whole interval lies outside it), plus zero timeouts for optimizer and
## deeproot and zero illegal actions for everyone. Exit 1 on any FAIL.
## PLAYTEST_GATE=0 disables it; fewer than GATE_MIN_SEEDS seeds skips it.

const Game := preload("res://sim/game.gd")
const AsciiView := preload("res://sim/ascii_view.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const Roster := preload("res://bots/roster.gd")
const Tally := preload("res://tests/tally.gd")

const DEFAULT_SEEDS := 30
const GATE_MIN_SEEDS := 20
## Win-rate bands per persona (fractions). Optimizer: BALANCE.md carries both
## the old 30-50% and the current 45-65% band; 35-65 spans both so the gate
## judges the game, not which entry a reader trusts (review §7.6).
const BANDS := {"deeproot": Vector2(0.70, 0.90), "optimizer": Vector2(0.35, 0.65)}
const MAGPIE_MAX_LOWER := 0.05  # canary: fail only when the CI lower bound clears 5%
const WANDERER_MAX_FLOOR := 2.0
const SPROUT_WINS_PER_30 := 1  # "wins rare": at most 1 win per 30 seeds
const NO_TIMEOUT := ["optimizer", "deeproot"]


func _init() -> void:
	var seeds := DEFAULT_SEEDS
	if OS.get_environment("PLAYTEST_SEEDS") != "":
		seeds = int(OS.get_environment("PLAYTEST_SEEDS"))
	var personas: Array = Roster.LEGACY.duplicate()
	if OS.get_environment("PLAYTEST_BOTS") != "":
		personas = Array(OS.get_environment("PLAYTEST_BOTS").split(","))
	for bot_name in personas:
		if not Roster.has(bot_name):
			push_error("unknown bot '%s' (have: %s)" % [bot_name, ", ".join(Roster.names())])
			quit(1)
			return
	var seed_arr := Sweep.seed_list_from(seeds, 1)
	print("=== TENDER playtest: %d seeds x %d personas ===" % [seeds, personas.size()])
	print(Sweep.header("playtest", ",".join(personas), {}, seed_arr))
	var stats := {}
	for bot_name in personas:
		var runs: Array = []
		for s in seed_arr:
			runs.append(Sweep.run_one(s, {}, bot_name))
		stats[bot_name] = _report(bot_name, runs)
	print("\n--- sample frame: optimizer, seed 1, final state ---")
	print(_final_frame("optimizer", 1))
	var gate_fails := _gate(stats, seeds)
	quit(1 if gate_fails > 0 else 0)


func _final_frame(bot_name: String, seed_v: int) -> String:
	var game = Game.new(seed_v)
	Sweep.run_loop(game, Roster.make(bot_name, seed_v))
	return AsciiView.render(game.snapshot())


## Prints the persona block; returns {wins, n, timeouts, illegal, avg_floor}
## for the gate.
func _report(bot_name: String, runs: Array) -> Dictionary:
	var wins := 0
	var deaths := 0
	var timeouts := 0
	var floors := 0
	var turns := 0
	var bloom := 0
	var by_floor := {}
	var by_cause := {}
	var tally := Tally.new()
	var kits: Array = []
	# per-base table: runs holding the base id at the end, runs casting it at
	# least once, wins while holding it (each aggregated per run, then summed)
	var held := {}
	var cast := {}
	var won := {}
	for r in runs:
		floors += r["floor"]
		turns += r["turns"]
		bloom += r["bloom_end"]
		tally.merge(r["tally"])
		kits.append(r["kit"])
		if r["won"]:
			wins += 1
		elif r["timeout"]:
			timeouts += 1
		else:
			deaths += 1
			by_floor[r["floor"]] = by_floor.get(r["floor"], 0) + 1
			by_cause[r["cause"]] = by_cause.get(r["cause"], 0) + 1
		var bases: Array = []
		for aid in r["kit"]:
			var b: String = Tally.base_id(String(aid))
			if not bases.has(b):
				bases.append(b)
		for b in bases:
			held[b] = held.get(b, 0) + 1
			if r["won"]:
				won[b] = won.get(b, 0) + 1
		for b in r["tally"].casts_by_base:
			if int(r["tally"].casts_by_base[b]) > 0:
				cast[b] = cast.get(b, 0) + 1
	var n := runs.size()
	print("%-10s wins %d/%d  deaths %d  timeouts %d  avg floor %.1f  avg turns %.1f  avg bloom %.1f" % [
		bot_name, wins, n, deaths, timeouts, float(floors) / n, float(turns) / n, float(bloom) / n])
	print("           deaths by floor %s  causes %s" % [str(by_floor), str(by_cause)])
	var ci := Sweep.wilson(wins, n)
	print("           win CI %s  stall floors %d  quota-unmet deaths %d  illegal %d" % [
		Sweep.fmt_ci(ci), tally.stall_floors, tally.quota_unmet_deaths, tally.illegal])
	var parts: Array = []
	var ids: Array = held.keys()
	for b in cast:
		if not ids.has(b):
			ids.append(b)
	ids.sort_custom(func(a, b):
		var ha: int = int(held.get(a, 0))
		var hb: int = int(held.get(b, 0))
		if ha != hb:
			return ha > hb
		return String(a) < String(b))
	for b in ids:
		parts.append("%s %d/%d/%d" % [b, held.get(b, 0), cast.get(b, 0), won.get(b, 0)])
	print("           per base held/cast>0/won: %s" % ", ".join(parts))
	var build_runs := {}
	var build_wins := {}
	for r in runs:
		if r.has("build"):
			build_runs[r["build"]] = build_runs.get(r["build"], 0) + 1
			if r["won"]:
				build_wins[r["build"]] = build_wins.get(r["build"], 0) + 1
	if not build_runs.is_empty():
		var bparts: Array = []
		for b in build_runs:
			bparts.append("%s %d/%d" % [b, build_wins.get(b, 0), build_runs[b]])
		print("           build wins: %s" % ", ".join(bparts))
	tally.print_block(n, kits)
	return {"wins": wins, "n": n, "timeouts": timeouts, "illegal": tally.illegal,
		"avg_floor": float(floors) / n}


## CI gate over the personas that ran; returns the number of FAIL lines.
func _gate(stats: Dictionary, seeds: int) -> int:
	print("\n--- gate ---")
	if OS.get_environment("PLAYTEST_GATE") == "0":
		print("gate: disabled (PLAYTEST_GATE=0)")
		return 0
	if seeds < GATE_MIN_SEEDS:
		print("gate: skipped, %d seeds < %d (Wilson bands need a usable interval; run PLAYTEST_SEEDS>=%d)" % [
			seeds, GATE_MIN_SEEDS, GATE_MIN_SEEDS])
		return 0
	var fails := 0
	for bot_name in stats:
		var st: Dictionary = stats[bot_name]
		var w: int = st["wins"]
		var n: int = st["n"]
		var ci := Sweep.wilson(w, n)
		if BANDS.has(bot_name):
			var band: Vector2 = BANDS[bot_name]
			var outside: bool = ci.y < band.x or ci.x > band.y
			fails += _verdict(not outside, "%s band %d-%d%%: %d/%d CI %s" % [
				bot_name, roundi(band.x * 100), roundi(band.y * 100), w, n, Sweep.fmt_ci(ci)])
		if bot_name == "magpie":
			fails += _verdict(ci.x <= MAGPIE_MAX_LOWER, "magpie canary <= %d%%: %d/%d CI %s (fails when the lower bound clears the band)" % [
				roundi(MAGPIE_MAX_LOWER * 100), w, n, Sweep.fmt_ci(ci)])
		if bot_name == "wanderer":
			fails += _verdict(w == 0 and st["avg_floor"] <= WANDERER_MAX_FLOOR, "wanderer 0 wins, avg floor <= %.0f: %d wins, avg floor %.2f" % [
				WANDERER_MAX_FLOOR, w, st["avg_floor"]])
		if bot_name == "sprout":
			var max_wins: int = SPROUT_WINS_PER_30 * int(ceil(n / 30.0))
			fails += _verdict(w <= max_wins, "sprout wins rare (<= %d per %d seeds): %d/%d" % [max_wins, n, w, n])
		if NO_TIMEOUT.has(bot_name):
			fails += _verdict(int(st["timeouts"]) == 0, "%s timeouts == 0: %d" % [bot_name, int(st["timeouts"])])
		fails += _verdict(int(st["illegal"]) == 0, "%s illegal actions == 0: %d" % [bot_name, int(st["illegal"])])
	print("gate: %d FAIL" % fails if fails > 0 else "gate: all PASS")
	return fails


func _verdict(ok: bool, msg: String) -> int:
	print("%s %s" % ["PASS" if ok else "FAIL", msg])
	return 0 if ok else 1
