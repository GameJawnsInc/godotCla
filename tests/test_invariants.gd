extends SceneTree
## Procgen invariant sweep: generate every floor over many seeds, validate.
## Run: godot --headless --path . --script tests/test_invariants.gd

const Content := preload("res://sim/content.gd")
const MapGen := preload("res://sim/mapgen.gd")

const SEEDS := 200


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
	quit(1 if bad > 0 else 0)
