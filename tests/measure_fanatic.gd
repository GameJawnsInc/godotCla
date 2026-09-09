extends SceneTree
## Fanatic per-build measurement: the build-viability table from BALANCE.md
## ("every build > 0" target) at proper sample size, plus timeout seeds.
## Every archetype runs on EVERY seed (review §7.2 item 3), so builds pair
## by seed instead of splitting the seed range four ways as the old runner did.
## Run: [FANATIC_SEEDS=100] godot --headless --path . --script tests/measure_fanatic.gd
## Env:
##   FANATIC_SEEDS     seed count (default 100)
##   FANATIC_SEED_FROM first seed (default 1)
##   FANATIC_BUILDS    comma list of Content.ARCHETYPES ids (default: every
##                     archetype Content.archetypes_for(pool) allows)
##   FANATIC_PACKAGES  comma list of tech packages committed to the run
##   FANATIC_TIER      difficulty tier (default 0)
##   FANATIC_MUTATORS  comma list of mutators
##   FANATIC_VERBOSE=1 print the full Tally block per build

const Game := preload("res://sim/game.gd")
const Content := preload("res://sim/content.gd")
const Roster := preload("res://bots/roster.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const Tally := preload("res://tests/tally.gd")


## Tally that also records the floor on which every core id was first held,
## by inspecting the kit after each step (end_step runs after game.step()).
class CoreTally extends "res://tests/tally.gd":
	var core: Array = []
	var complete_floor := -1  # -1 until every core id is in the kit

	func end_step(game, action: Dictionary) -> void:
		super.end_step(game, action)
		if complete_floor != -1:
			return
		var held := {}
		for kid in game.player["kit"]:
			held[Content.base_id(String(kid))] = true
		for aid in core:
			if not held.has(aid):
				return
		complete_floor = game.floor_num


static func _env_list(name: String) -> Array:
	var v := OS.get_environment(name)
	if v.strip_edges() == "":
		return []
	var out: Array = []
	for part in v.split(","):
		var p: String = part.strip_edges()
		if p != "":
			out.append(p)
	return out


func _init() -> void:
	var n_seeds := 100
	if OS.get_environment("FANATIC_SEEDS") != "":
		n_seeds = int(OS.get_environment("FANATIC_SEEDS"))
	var first := 1
	if OS.get_environment("FANATIC_SEED_FROM") != "":
		first = int(OS.get_environment("FANATIC_SEED_FROM"))
	var seeds := Sweep.seed_list_from(n_seeds, first)
	var verbose := OS.get_environment("FANATIC_VERBOSE") == "1"

	var cfg := {}
	var packages := _env_list("FANATIC_PACKAGES")
	for pkg in packages:
		if not Content.PACKAGES.has(pkg):
			print("FAIL unknown package '%s' (have: %s)" % [pkg, ", ".join(Content.PACKAGES.keys())])
			quit(1)
			return
	if not packages.is_empty():
		cfg["packages"] = packages
	if OS.get_environment("FANATIC_TIER") != "":
		cfg["tier"] = int(OS.get_environment("FANATIC_TIER"))
	var mutators := _env_list("FANATIC_MUTATORS")
	if not mutators.is_empty():
		cfg["mutators"] = mutators

	# the pool the sim will actually offer under this config (packages merged)
	var pool: Array = Game.new(first, cfg).draft_pool.duplicate()
	var builds := _env_list("FANATIC_BUILDS")
	if builds.is_empty():
		builds = Content.archetypes_for(pool)
	for b in builds:
		if not Content.ARCHETYPES.has(b):
			print("FAIL unknown archetype '%s' (have: %s)" % [b, ", ".join(Content.ARCHETYPES.keys())])
			quit(1)
			return

	print(Sweep.header("measure_fanatic", "fanatic", cfg, seeds))
	print("builds: %s  (pool %d ids)" % [", ".join(builds), pool.size()])

	var stats := {}
	for b in builds:
		stats[b] = {
			"runs": 0, "wins": 0, "floors": 0, "timeouts": [], "complete": [],
			"never": 0, "fallbacks": 0, "off_buys": 0, "tally": Tally.new(), "kits": [],
		}
	var timeouts: Array = []
	var total_w := 0
	var total_runs := 0
	for s in seeds:
		for b in builds:
			var game = Game.new(int(s), cfg)
			var bot = Roster.make("fanatic", int(s))
			bot.set_build(b)
			var ct := CoreTally.new()
			ct.core = Content.ARCHETYPES[b]["core"]
			var r := Sweep.run_loop(game, bot, ct)
			var st: Dictionary = stats[b]
			st["runs"] += 1
			st["floors"] += int(r["floor"])
			st["kits"].append(r["kit"])
			st["tally"].merge(ct)
			if String(bot.get_build()) != b:
				st["fallbacks"] += 1
			for aid in ct.ability_buys_by_id:
				if not ct.core.has(Content.base_id(String(aid))):
					st["off_buys"] += int(ct.ability_buys_by_id[aid])
			if ct.complete_floor == -1:
				st["never"] += 1
			else:
				st["complete"].append(ct.complete_floor)
			total_runs += 1
			if r["won"]:
				st["wins"] += 1
				total_w += 1
			elif r["timeout"]:
				var tag := "%s seed %d floor %d" % [b, int(s), int(r["floor"])]
				st["timeouts"].append(tag)
				timeouts.append(tag)

	for b in builds:
		var st: Dictionary = stats[b]
		var n: int = st["runs"]
		var t = st["tally"]
		var k := Tally.kpis(t, n, st["kits"])
		var complete_s := "never"
		if not st["complete"].is_empty():
			var sum := 0
			for f in st["complete"]:
				sum += int(f)
			complete_s = "%.1f" % (float(sum) / st["complete"].size())
		var never_share := 0.0 if n == 0 else float(st["never"]) / n
		var line := "%-14s %2d/%2d wins, avg floor %.1f" % [b, st["wins"], n, 0.0 if n == 0 else float(st["floors"]) / n]
		line += "  CI %s  timeouts %d  core-complete floor %s (never %.0f%%)  signature %.2f  strike %.2f" % [
			Sweep.fmt_ci(Sweep.wilson(st["wins"], n)), st["timeouts"].size(), complete_s, 100.0 * never_share,
			k["signature_share"], k["strike_share"]]
		if st["off_buys"] > 0:
			line += "  OFF-BUILD ABILITY BUYS %d" % st["off_buys"]
		if st["fallbacks"] > 0:
			line += "  (fell back to a legacy build in %d runs: requirements unmet)" % st["fallbacks"]
		print(line)
		if verbose:
			t.print_block(n, st["kits"])
	print("total %d/%d, timeouts: %s" % [total_w, total_runs, str(timeouts)])
	quit(0)
