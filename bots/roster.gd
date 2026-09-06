extends RefCounted
## Single source of the bot roster (review §7.1). Every runner resolves
## persona names here instead of carrying its own BOTS dict, so an unknown
## name fails loudly (push_error + null) instead of silently running a
## default bot. Entries carry an optional "props" dict applied with
## Object.set() after reset() - a silent no-op while the target bot has no
## such property, so variants can be registered before the bot grows them.

const BOTS := {
	"wanderer": {"script": preload("res://bots/wanderer.gd"), "props": {}},
	"sprout": {"script": preload("res://bots/sprout.gd"), "props": {}},
	"magpie": {"script": preload("res://bots/magpie.gd"), "props": {}},
	"fanatic": {"script": preload("res://bots/fanatic.gd"), "props": {}},
	"optimizer": {"script": preload("res://bots/optimizer.gd"), "props": {}},
	"deeproot": {"script": preload("res://bots/deeproot.gd"), "props": {}},
	"deeproot_rollout": {"script": preload("res://bots/deeproot.gd"), "props": {"draft_mode": "rollout"}},
	"deeproot_plan": {"script": preload("res://bots/deeproot_plan.gd"), "props": {}},
}

## The six legacy personas, in the order BALANCE.md tables list them.
const LEGACY := ["wanderer", "sprout", "magpie", "fanatic", "optimizer", "deeproot"]

## Bot rng seed for a game seed - the convention every runner has always used.
const SEED_MUL := 7919
const SEED_ADD := 17


static func names() -> Array:
	return BOTS.keys()


static func has(name: String) -> bool:
	return BOTS.has(name)


## Script for a roster name; push_error + null on an unknown name.
static func script(name: String) -> GDScript:
	if not BOTS.has(name):
		push_error("unknown bot '%s' (have: %s)" % [name, ", ".join(BOTS.keys())])
		return null
	return BOTS[name]["script"]


static func bot_seed(seed_v: int) -> int:
	return seed_v * SEED_MUL + SEED_ADD


## Instantiate a roster bot for game seed `seed_v`: new(), reset(), props.
## Returns null (after push_error) on an unknown name.
static func make(name: String, seed_v: int) -> RefCounted:
	var s := script(name)
	if s == null:
		return null
	return make_from(s, seed_v, BOTS[name]["props"])


## Instantiate from a raw script (legacy callers that hold a GDScript).
static func make_from(s: GDScript, seed_v: int, props: Dictionary = {}) -> RefCounted:
	var bot = s.new()
	bot.reset(bot_seed(seed_v))
	for k in props:
		bot.set(k, props[k])
	return bot


## First roster name (in BOTS order) bound to `s` with no props - the plain
## persona a raw script stands for. "" when the script is not on the roster.
static func name_of(s: GDScript) -> String:
	if s == null:
		return ""
	for name in BOTS:
		if BOTS[name]["script"] == s and BOTS[name]["props"].is_empty():
			return name
	for name in BOTS:
		if BOTS[name]["script"] == s:
			return name
	return ""
