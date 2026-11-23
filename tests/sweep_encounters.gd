extends SceneTree
## Block E (bump 17) paired acceptance runner: encounter packs and biome
## reinforcements (the default config) against the fixed_shift control, which
## replays the pre-v17 classic-crew game action for action, on the SAME seeds
## for every loadout. The precedent is tests/sweep_resonance.gd.
##
## Run: [ENC_BOT=optimizer] [ENC_SEEDS=300] [ENC_SEED_FROM=1]
##      [ENC_LOADOUTS=tender,spiker] [ENC_ARMS=both|default|control] [ENC_GATE=0]
##      godot --headless --path . --script tests/sweep_encounters.gd
## Env:
##   ENC_BOT        roster persona (default optimizer; unknown -> exit 1)
##   ENC_SEEDS      seed count per cell (default 300)
##   ENC_SEED_FROM  first seed (default 1) - out-of-sample checks
##   ENC_LOADOUTS   comma list of Content.LOADOUTS ids (default every row).
##                  A cell's config is {loadout: id} (plus the control's
##                  mutator) and commits no package, exactly as the
##                  prototype and the BALANCE.md bump-14 loadout table ran
##   ENC_ARMS       both (default) | default | control; control is
##                  {mutators: ["fixed_shift"]}
##   ENC_GATE=0     report the gate verdict but always exit 0
##
## Machine-readable lines (a measurement driver parses these; the human lines
## sit beside them):
##   ENC_CELL bot=<bot> arm=<default|control> loadout=<id> seeds=<from>..<to>
##     wins=<W>/<N> lo=<Wilson low %, 1dp> hi=<Wilson high %, 1dp>
##     timeouts=<T> stall_floors=<S> avg_floor=<2dp>
##   ENC_POOLED arm=<arm> wins=<W>/<N> lo=.. hi=.. timeouts=.. stall_floors=..
##   ENC_DELTA pooled=<default wins - control wins>          (both arms only)
##   ENC_VARIETY arm=<arm> variety: ...                    (tests/tally.gd)
##   ENC_GATE PASS | ENC_GATE FAIL <reasons> | ENC_GATE NONE
## stall_floors is tests/tally.gd's `stall_floors` (floors on which the turn
## passed 60 or the smog passed the choke + 30 at any point), summed over the
## cell's runs.
##
## Gate (pre-registered in the stage plan; exit 1 on FAIL unless ENC_GATE=0):
##   optimizer  pooled |delta| <= 60 per 1800 runs, scaled to this run's
##              size (needs both arms), AND every default cell's Wilson CI
##              overlaps the 35-65% band
##   magpie     pooled delta <= +33 per 1800 runs, scaled (needs both arms),
##              AND no default cell whose Wilson low clears 10% unless its
##              control cell's does too (judged PAIRED: spiker sits at the trip
##              line on the classic game itself)
##   others     NONE

const Content := preload("res://sim/content.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const Roster := preload("res://bots/roster.gd")
const Tally := preload("res://tests/tally.gd")

const CONTROL_MUTATOR := "fixed_shift"
const GATE_SCALE_RUNS := 1800.0
const OPT_DELTA_PER_1800 := 60.0
const OPT_BAND := Vector2(0.35, 0.65)
const MAGPIE_DELTA_PER_1800 := 33.0
const MAGPIE_MAX_LOWER := 0.10


static func _env_list(name: String) -> Array:
	var out: Array = []
	for part in OS.get_environment(name).split(","):
		var p: String = part.strip_edges()
		if p != "":
			out.append(p)
	return out


static func _arm_config(arm: String, loadout: String) -> Dictionary:
	var cfg := {}
	if arm == "control":
		cfg["mutators"] = [CONTROL_MUTATOR]
	cfg["loadout"] = loadout
	return cfg


static func _pct(x: float) -> String:
	return "%.1f" % (100.0 * x)


func _init() -> void:
	var bot := OS.get_environment("ENC_BOT").strip_edges()
	if bot == "":
		bot = "optimizer"
	if not Roster.has(bot):
		push_error("unknown ENC_BOT '%s' (have: %s)" % [bot, ", ".join(Roster.names())])
		quit(1)
		return
	var n_seeds := 300
	if OS.get_environment("ENC_SEEDS") != "":
		n_seeds = int(OS.get_environment("ENC_SEEDS"))
	var first := 1
	if OS.get_environment("ENC_SEED_FROM") != "":
		first = int(OS.get_environment("ENC_SEED_FROM"))
	var seeds := Sweep.seed_list_from(n_seeds, first)
	var loadouts := _env_list("ENC_LOADOUTS")
	if loadouts.is_empty():
		loadouts = Content.LOADOUTS.keys()
	for lid in loadouts:
		if not Content.LOADOUTS.has(lid):
			push_error("unknown ENC_LOADOUTS entry '%s' (have: %s)" % [lid, ", ".join(Content.LOADOUTS.keys())])
			quit(1)
			return
	var arms_env := OS.get_environment("ENC_ARMS").strip_edges()
	if arms_env == "":
		arms_env = "both"
	var arms: Array = []
	match arms_env:
		"both":
			arms = ["control", "default"]
		"default":
			arms = ["default"]
		"control":
			arms = ["control"]
		_:
			push_error("bad ENC_ARMS '%s' (want both | default | control)" % arms_env)
			quit(1)
			return
	var gate_on := OS.get_environment("ENC_GATE") != "0"
	var range_s := "%d..%d" % [first, first + n_seeds - 1]

	print("=== sweep_encounters | bot %s | seeds %s (%d) | loadouts %s | arms %s (control = {mutators: [\"%s\"]}) | instrument v2 ===" % [
		bot, range_s, n_seeds, ",".join(loadouts), arms_env, CONTROL_MUTATOR])

	# cells[arm][loadout] = measure() result; pooled per arm
	var cells := {}
	var pooled := {}
	for arm in arms:
		cells[arm] = {}
		pooled[arm] = {"wins": 0, "n": 0, "timeouts": 0, "stall": 0, "tally": Tally.new()}
	for lid in loadouts:
		for arm in arms:
			var cfg := _arm_config(arm, lid)
			var m := Sweep.measure(seeds, cfg, bot)
			cells[arm][lid] = m
			var t = m["tally"]
			var ci: Vector2 = m["ci"]
			print("ENC_CELL bot=%s arm=%s loadout=%s seeds=%s wins=%d/%d lo=%s hi=%s timeouts=%d stall_floors=%d avg_floor=%.2f" % [
				bot, arm, lid, range_s, int(m["wins"]), int(m["n"]), _pct(ci.x), _pct(ci.y),
				int(m["timeouts"]), int(t.stall_floors), float(m["avg_floor"])])
			var p: Dictionary = pooled[arm]
			p["wins"] += int(m["wins"])
			p["n"] += int(m["n"])
			p["timeouts"] += int(m["timeouts"])
			p["stall"] += int(t.stall_floors)
			p["tally"].merge(t)
		# the human per-loadout line
		var parts: Array = []
		for arm in arms:
			var m: Dictionary = cells[arm][lid]
			parts.append("%s %d/%d %s" % [arm, int(m["wins"]), int(m["n"]), Sweep.fmt_ci(m["ci"])])
		var line := "%-12s %s" % [lid, "  ".join(parts)]
		if arms.size() == 2:
			var c: Dictionary = cells["control"][lid]
			var d: Dictionary = cells["default"][lid]
			var pr := Sweep.paired(d["wins_by_seed"], c["wins_by_seed"])
			line += "  delta %+d  (default-only %d, control-only %d, sign p=%.2f)" % [
				int(d["wins"]) - int(c["wins"]), int(pr["only_a"]), int(pr["only_b"]), float(pr["sign_p"])]
		print(line)

	for arm in arms:
		var p: Dictionary = pooled[arm]
		var ci := Sweep.wilson(int(p["wins"]), int(p["n"]))
		print("ENC_POOLED arm=%s wins=%d/%d lo=%s hi=%s timeouts=%d stall_floors=%d" % [
			arm, int(p["wins"]), int(p["n"]), _pct(ci.x), _pct(ci.y), int(p["timeouts"]), int(p["stall"])])
	var delta := 0
	if arms.size() == 2:
		delta = int(pooled["default"]["wins"]) - int(pooled["control"]["wins"])
		print("ENC_DELTA pooled=%d" % delta)
	for arm in arms:
		var p: Dictionary = pooled[arm]
		print("ENC_VARIETY arm=%s %s" % [arm, p["tally"].variety_line(int(p["n"]))])

	# --- gate ---
	var reasons: Array = []
	var evaluated := false
	var both := arms.size() == 2
	var n_runs := float(seeds.size() * loadouts.size())
	if bot == "optimizer":
		if both:
			evaluated = true
			var lim := OPT_DELTA_PER_1800 * n_runs / GATE_SCALE_RUNS
			if absf(float(delta)) > lim:
				reasons.append("optimizer pooled |delta| %d > %.1f (60 per 1800, scaled to %d runs)" % [absi(delta), lim, int(n_runs)])
		if arms.has("default"):
			evaluated = true
			for lid in loadouts:
				var ci: Vector2 = cells["default"][lid]["ci"]
				if ci.y < OPT_BAND.x or ci.x > OPT_BAND.y:
					reasons.append("optimizer %s default CI [%s, %s] misses 35-65" % [lid, _pct(ci.x), _pct(ci.y)])
	elif bot == "magpie" and both:
		evaluated = true
		var lim := MAGPIE_DELTA_PER_1800 * n_runs / GATE_SCALE_RUNS
		if float(delta) > lim:
			reasons.append("magpie pooled delta %+d > +%.1f (33 per 1800, scaled to %d runs)" % [delta, lim, int(n_runs)])
		for lid in loadouts:
			var dci: Vector2 = cells["default"][lid]["ci"]
			var cci: Vector2 = cells["control"][lid]["ci"]
			if dci.x > MAGPIE_MAX_LOWER and not cci.x > MAGPIE_MAX_LOWER:
				reasons.append("magpie %s default low %s%% clears 10%% while control low %s%% does not" % [lid, _pct(dci.x), _pct(cci.x)])
	if not evaluated:
		print("ENC_GATE NONE")
	elif reasons.is_empty():
		print("ENC_GATE PASS")
	else:
		print("ENC_GATE FAIL %s" % "; ".join(reasons))
	if not gate_on:
		print("gate disabled (ENC_GATE=0): exit 0 whatever the verdict")
		quit(0)
		return
	quit(1 if evaluated and not reasons.is_empty() else 0)
