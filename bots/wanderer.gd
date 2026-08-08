extends "res://bots/bot_base.gd"
## Wanderer persona: uniformly random legal actions. Crash and softlock finder.


func get_bot_name() -> String:
	return "wanderer"


func choose_action(_snap: Dictionary, legal: Array) -> Dictionary:
	return legal[rng.randi_range(0, legal.size() - 1)]
