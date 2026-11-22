extends SceneTree
## Procgen invariant sweep: generate every floor over many seeds, validate.
## Three passes: the raw Content.FLOORS table (200 seeds) over EVERY encounter
## pack of every row (Block E1: a row's roster is one of its packs, so each
## pack is written into a copy of the row as fdef.enemies), then Game.floor_def(n)
## for every difficulty tier and for the floor-shaping mutators (20 seeds),
## since tiers add enemies/elites and mutators double oil or add spawns that
## the raw table never sees (review §7.6), then "pack layout invariance":
## every pack of a floor generated from the same rng seed must give the same
## tiles, start, stairs, vents, shrine, enemy positions, elite flags, terrain
## and rng.state - the headcount rule that keeps mapgen's main-rng draws
## byte-identical across crews. Boss floors use BOSS_INVARIANTS.
## Run: godot --headless --path . --script tests/test_invariants.gd

const Content := preload("res://sim/content.gd")
const MapGen := preload("res://sim/mapgen.gd")
const Game := preload("res://sim/game.gd")

const SEEDS := 200
const FDEF_SEEDS := 20
## Mutators that change floor_def; the others touch the player or shop only.
## Every mutator whose config touches floor_def (oil_mult / extra_common_enemy
## / encounter_packs - the last is fixed_shift, the classic-crew control),
## read from the table so a new row joins the sweep by itself.
static func _fdef_mutators() -> Array:
	var out: Array = []
	for m in Content.MUTATORS:
		var cfg: Dictionary = Content.MUTATORS[m].get("config", {})
		if cfg.has("oil_mult") or cfg.has("extra_common_enemy") or cfg.has("encounter_packs"):
			out.append(m)
	return out


## The raw rows the generator is fed: one per encounter pack (the pack's
## roster written into a copy of the row as fdef.enemies, the way floor_def
## does), and the boss row once with its empty roster.
static func _raw_rows(fi: int) -> Array:
	var row: Dictionary = Content.FLOORS[fi]
	var out: Array = []
	var packs: Array = row.get("encounters", [])
	for pi in range(maxi(1, packs.size())):
		var fdef: Dictionary = row.duplicate(true)
		fdef.erase("encounters")
		fdef["enemies"] = Content.encounter_roster(row, pi).duplicate()
		out.append(fdef)
	return out


func _init() -> void:
	var gens := 0
	var bad := 0
	var kinds := {}
	var rows := 0
	for fi in range(Content.FLOORS.size()):
		rows += _raw_rows(fi).size()
	for s in range(1, SEEDS + 1):
		for fi in range(Content.FLOORS.size()):
			var raws: Array = _raw_rows(fi)
			for pi in raws.size():
				var rng := RandomNumberGenerator.new()
				rng.seed = s * 1000 + fi
				var fdef: Dictionary = raws[pi]
				var gen := MapGen.generate(rng, fdef)
				gens += 1
				var invs: Array = MapGen.BOSS_INVARIANTS if fdef.get("boss", false) else MapGen.DEFAULT_INVARIANTS
				var fails: Array = MapGen.validate(gen, invs)
				if not fails.is_empty():
					bad += 1
					print("FAIL seed %d floor %d pack %d: %s" % [s, fi + 1, pi, str(fails)])
				for t in gen["terrain"]:
					kinds[String(gen["terrain"][t]["kind"])] = true
	print("invariants: %d generations (%d seeds x %d raw rows: every encounter pack + the boss row), %d violations" % [gens, SEEDS, rows, bad])
	bad += _check_kinds(kinds)
	var fd := _floor_def_sweep()
	print("floor_def invariants: %d configs, %d generations, %d violations" % [fd["configs"], fd["gens"], fd["bad"]])
	bad += int(fd["bad"])
	var li := _pack_layout_invariance()
	print("pack layout invariance: %d generations over %d seeds, %d diffs" % [li["gens"], SEEDS, li["bad"]])
	bad += int(li["bad"])
	quit(1 if bad > 0 else 0)


## Block E1's layout rule: every pack of a floor has pack 0's headcount and
## mapgen's placement never reads a kind, so generating a floor from the same
## rng seed with any of its packs must give the identical map - only the kind
## on each enemy tile may differ. Compares everything else, plus rng.state
## after generate (the next main-rng draw would otherwise shift).
func _pack_layout_invariance() -> Dictionary:
	var gens := 0
	var bad := 0
	for s in range(1, SEEDS + 1):
		for fi in range(Content.FLOORS.size()):
			var raws: Array = _raw_rows(fi)
			if raws.size() <= 1:
				continue
			var ref := ""
			var ref_state := 0
			for pi in raws.size():
				var rng := RandomNumberGenerator.new()
				rng.seed = s * 7919 + fi
				var gen := MapGen.generate(rng, raws[pi])
				gens += 1
				var spots: Array = []
				for e in gen["enemies"]:
					spots.append([e["pos"], bool(e.get("elite", false))])
				var sig := str([gen["tiles"], gen["start"], gen["stairs"], gen["vents"], gen["shrine"],
					spots, gen["terrain"], gen.get("rooms", [])])
				if pi == 0:
					ref = sig
					ref_state = rng.state
				elif sig != ref or rng.state != ref_state:
					bad += 1
					if bad <= 5:
						print("FAIL pack layout: seed %d floor %d pack %d generates a different map than pack 0 (rng %s)" % [
							s, fi + 1, pi, "moved" if rng.state != ref_state else "same"])
	return {"gens": gens, "bad": bad}


## Every kind mapgen puts on a floor must be a Content.TERRAIN row (so every
## renderer and rule can look it up). Runtime-only kinds - ash, fire, smoke,
## roots - are legal terrain but must never be generated: mapgen makes the
## corruption the player starts against, not the results of reactions.
const GEN_ONLY_KINDS := ["ash", "fire", "smoke", "roots"]


func _check_kinds(kinds: Dictionary) -> int:
	var bad := 0
	for k in kinds:
		if not Content.TERRAIN.has(k):
			bad += 1
			print("FAIL mapgen emits kind %s, absent from Content.TERRAIN" % k)
		if GEN_ONLY_KINDS.has(k):
			bad += 1
			print("FAIL mapgen emits runtime-only kind %s" % k)
	print("terrain kinds: %s (%d violations)" % [str(kinds.keys()), bad])
	return bad


## Validate every floor of Game.floor_def(n) for tiers 0..TIERS.size() and
## for each mutator whose config touches floor_def, FDEF_SEEDS seeds each.
func _floor_def_sweep() -> Dictionary:
	var configs: Array = []
	for t in range(Content.TIERS.size() + 1):
		configs.append({"tier": t})
	for mut in _fdef_mutators():
		configs.append({"mutators": [mut]})
	var gens := 0
	var bad := 0
	for ci in configs.size():
		var cfg: Dictionary = configs[ci]
		for s in range(1, FDEF_SEEDS + 1):
			# Block E1: floor_def draws the seed's own pack, so each seed is its
			# own game (a blank one: floor_def reads seed, tier and mutators)
			var game = Game.new(s, {"_blank": true})
			game.tier = int(cfg.get("tier", 0))
			game.mutators = cfg.get("mutators", []).duplicate()
			for n in range(1, Content.FLOORS.size() + 1):
				var fdef: Dictionary = game.floor_def(n)
				var rng := RandomNumberGenerator.new()
				rng.seed = (ci + 1) * 100000 + s * 1000 + n
				var gen := MapGen.generate(rng, fdef)
				gens += 1
				var invs: Array = MapGen.BOSS_INVARIANTS if fdef.get("boss", false) else MapGen.DEFAULT_INVARIANTS
				var fails: Array = MapGen.validate(gen, invs)
				if not fails.is_empty():
					bad += 1
					print("FAIL floor_def cfg %s seed %d floor %d: %s" % [str(cfg), s, n, str(fails)])
	return {"configs": configs.size(), "gens": gens, "bad": bad}
