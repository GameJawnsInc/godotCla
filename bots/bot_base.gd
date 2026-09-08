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


## Kit slot id folded onto its BASE id, for base-name matching.
## Content.base_id, NEVER trim_suffix("+"): since Block D6 an upgrade id is
## "<base>+<variant>" ("solar_lance+noon"), which trim_suffix returns
## UNCHANGED - a persona folding its kit that way silently stops matching its
## own base names.
func _kit_id(snap: Dictionary, slot: int) -> String:
	# an inline preload, not a const: every subclass already declares its own
	# Content/CONTENT const and a parent member of that name would clash
	return preload("res://sim/content.gd").base_id(String(snap["player"]["kit"][slot]))
