extends SceneTree
## Per-boss arrival/conversion measurement: which floor-7 boss each seed
## draws, and whether the run converts the arrival into a win - overall and
## per kit signature (review §7.7), so "does The Dredge filter gardener kits"
## is a number rather than a guess.
## Run: [BOSS_BOT=<persona>] [BOSS_SEEDS=<n>] [BOSS_KIT=a,b,c] \
##   godot --headless --path . --script tests/measure_bosses.gd
## BOSS_KIT forces a LOCKED kit ({kit: K, pool: K}; see Sweep.CAVEAT_LOCKED).
## Kit signature = sorted base ids outside STARTING_KIT joined by "+", or
## "starter" when the final kit is the starting kit alone.

const Game := preload("res://sim/game.gd")
const Content := preload("res://sim/content.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const Roster := preload("res://bots/roster.gd")
const Tally := preload("res://tests/tally.gd")


func _init() -> void:
	var bot_name := OS.get_environment("BOSS_BOT")
	if bot_name == "":
		bot_name = Sweep.pick_bot_name()
	if not Roster.has(bot_name):
		push_error("unknown bot '%s' (have: %s)" % [bot_name, ", ".join(Roster.names())])
		quit(1)
		return
	var seeds := 45
	if OS.get_environment("BOSS_SEEDS") != "":
		seeds = int(OS.get_environment("BOSS_SEEDS"))
	var cfg := Sweep.tier_config({})
	if OS.get_environment("BOSS_KIT") != "":
		var kit: Array = Array(OS.get_environment("BOSS_KIT").split(","))
		cfg = Sweep.locked_config(kit, cfg)
		print("note: " + Sweep.CAVEAT_LOCKED)
	var seed_arr := Sweep.seed_list_from(seeds, 1)
	print(Sweep.header("measure_bosses", bot_name, cfg, seed_arr))
	var arrivals := {}
	var wins := {}
	var by_sig := {}  # boss -> {sig -> [arrivals, wins]}
	for s in seed_arr:
		var game = Game.new(s, cfg)
		var r := Sweep.run_loop(game, Roster.make(bot_name, s))
		var boss_kind := _boss_kind(game, r["tally"])
		if boss_kind != "":
			arrivals[boss_kind] = arrivals.get(boss_kind, 0) + 1
			if game.won:
				wins[boss_kind] = wins.get(boss_kind, 0) + 1
			var sig := kit_signature(game.player["kit"])
			if not by_sig.has(boss_kind):
				by_sig[boss_kind] = {}
			var row: Array = by_sig[boss_kind].get(sig, [0, 0])
			row[0] += 1
			if game.won:
				row[1] += 1
			by_sig[boss_kind][sig] = row
	print("%s, %d seeds:" % [bot_name, seeds])
	for kind in arrivals:
		print("  %-14s %2d arrivals, %2d converted" % [kind, arrivals[kind], wins.get(kind, 0)])
	print("conversions per boss x kit signature (won/arrived):")
	var kinds: Array = arrivals.keys()
	kinds.sort()
	for kind in kinds:
		var sigs: Array = by_sig[kind].keys()
		sigs.sort_custom(func(a, b):
			var na: int = by_sig[kind][a][0]
			var nb: int = by_sig[kind][b][0]
			if na != nb:
				return na > nb
			return String(a) < String(b))
		for sig in sigs:
			var row: Array = by_sig[kind][sig]
			print("  %-14s %2d/%2d  %s" % [kind, row[1], row[0], sig])
	quit(0)


## The floor-7 boss this run met: still alive in the enemy list, or dead in
## the tally's kill ledger (bosses only ever spawn on the boss floor).
static func _boss_kind(game, tally) -> String:
	if game.floor_num != Content.FLOORS.size():
		return ""
	for e in game.enemies:
		if Content.ENEMIES[e["kind"]]["traits"].has("boss"):
			return e["kind"]
	for kind in tally.kills_by_kind:
		if Content.ENEMIES.has(kind) and Content.ENEMIES[kind]["traits"].has("boss"):
			return kind
	return ""


## Sorted base ids outside STARTING_KIT joined by "+", or "starter".
static func kit_signature(kit: Array) -> String:
	var ids: Array = []
	for aid in kit:
		var b: String = Tally.base_id(String(aid))
		if not Content.STARTING_KIT.has(b) and not ids.has(b):
			ids.append(b)
	ids.sort()
	return "starter" if ids.is_empty() else "+".join(ids)
