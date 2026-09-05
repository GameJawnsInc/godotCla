extends SceneTree
## Procgen invariant sweep: generate every floor over many seeds, validate.
## Two passes: the raw Content.FLOORS table (200 seeds), then Game.floor_def(n)
## for every difficulty tier and for the floor-shaping mutators (20 seeds),
## since tiers add enemies/elites and mutators double oil or add spawns that
## the raw table never sees (review §7.6). Boss floors use BOSS_INVARIANTS.
## Run: godot --headless --path . --script tests/test_invariants.gd

const Content := preload("res://sim/content.gd")
const MapGen := preload("res://sim/mapgen.gd")
const Game := preload("res://sim/game.gd")

const SEEDS := 200
const FDEF_SEEDS := 20
## Mutators that change floor_def; the others touch the player or shop only.
const FDEF_MUTATORS := ["double_oil", "overtime"]


func _init() -> void:
	var gens := 0
	var bad := 0
	for s in range(1, SEEDS + 1):
		for fi in range(Content.FLOORS.size()):
			var rng := RandomNumberGenerator.new()
			rng.seed = s * 1000 + fi
			var fdef: Dictionary = Content.FLOORS[fi]
			var gen := MapGen.generate(rng, fdef)
			gens += 1
			var invs: Array = MapGen.BOSS_INVARIANTS if fdef.get("boss", false) else MapGen.DEFAULT_INVARIANTS
			var fails: Array = MapGen.validate(gen, invs)
			if not fails.is_empty():
				bad += 1
				print("FAIL seed %d floor %d: %s" % [s, fi + 1, str(fails)])
	print("invariants: %d generations, %d violations" % [gens, bad])
	var fd := _floor_def_sweep()
	print("floor_def invariants: %d configs, %d generations, %d violations" % [fd["configs"], fd["gens"], fd["bad"]])
	bad += int(fd["bad"])
	quit(1 if bad > 0 else 0)


## Validate every floor of Game.floor_def(n) for tiers 0..TIERS.size() and
## for each single FDEF_MUTATORS entry, FDEF_SEEDS seeds each.
func _floor_def_sweep() -> Dictionary:
	var configs: Array = []
	for t in range(Content.TIERS.size() + 1):
		configs.append({"tier": t})
	for mut in FDEF_MUTATORS:
		configs.append({"mutators": [mut]})
	var gens := 0
	var bad := 0
	for ci in configs.size():
		var cfg: Dictionary = configs[ci]
		var game = Game.new(1, cfg)
		for s in range(1, FDEF_SEEDS + 1):
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
