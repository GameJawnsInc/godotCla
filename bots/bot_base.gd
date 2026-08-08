extends RefCounted
## Bot interface (style guide §5): choose_action(visible_state, legal) -> Action.
## Bots get their own seeded RNG so whole runs are reproducible.

var rng := RandomNumberGenerator.new()


func reset(seed_v: int) -> void:
	rng.seed = seed_v


func get_bot_name() -> String:
	return "bot"


func choose_action(_snap: Dictionary, legal: Array) -> Dictionary:
	return legal[legal.size() - 1]


## Kit slot id with any upgrade suffix stripped, for base-name matching.
func _kit_id(snap: Dictionary, slot: int) -> String:
	return String(snap["player"]["kit"][slot]).trim_suffix("+")
