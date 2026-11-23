extends RefCounted
## The shell's ONE names module (fun pass): every string that names an enemy,
## an ability, a graft, a resonance or a damage source goes through here, so
## the log, the callouts, the danger readout and the game-over sheet can never
## spell the same thing two ways. Static only; reads Content and nothing else.
##
## Two source namers on purpose: `src_name` is the SHORT form the log and the
## danger layer print in brackets ("You take 2 (fire)", pinned by
## tests/test_shell.gd 8c), `src_long` the attribution form a recap names a
## hit by ("Solar Lance fire", "Water Jet slam").

const Content := preload("res://sim/content.gd")

## raw source ids that read better as a word than spaced out
const SRC_WORDS := {"spore": "spores", "root": "roots", "stun": "stun"}


## The enemy's display name; "Something" for an empty or unknown kind.
static func ename(kind) -> String:
	var k := String(kind) if kind != null else ""
	if Content.ENEMIES.has(k):
		return String(Content.ENEMIES[k]["name"])
	return "Something"


## "the Drill Bot" mid-sentence; a name that already starts "The " reads
## "the Overseer"; an unknown kind is "it".
static func the_name(kind) -> String:
	var k := String(kind) if kind != null else ""
	if not Content.ENEMIES.has(k):
		return "it"
	var n := ename(k)
	if n.begins_with("The "):
		return "the " + n.substr(4)
	return "the " + n


## A boss at the start of a sentence: "The Overseer", "The Furnace Core".
static func boss_name(kind) -> String:
	var k := String(kind) if kind != null else ""
	if not Content.ENEMIES.has(k):
		return "It"
	var n := ename(k)
	return n if n.begins_with("The ") else "The " + n


## An enemy at the start of a sentence: "Drill Bot", but a boss reads
## "The Furnace Core" (boss_name).
static func subj(kind) -> String:
	var k := String(kind) if kind != null else ""
	if Content.ENEMIES.get(k, {}).get("traits", []).has("boss"):
		return boss_name(k)
	return ename(k)


## "a Drill Bot" / "an Oil Sludge"; a boss is "the Overseer" (there is only
## one); "" is "a machine"; an unknown kind is its id spaced out.
static func a_name(kind) -> String:
	var k := String(kind) if kind != null else ""
	if k == "":
		return "a machine"
	if not Content.ENEMIES.has(k):
		return k.replace("_", " ")
	if Content.ENEMIES[k].get("traits", []).has("boss"):
		return the_name(k)
	var n := ename(k)
	return ("an " if "AEIOU".contains(n.substr(0, 1)) else "a ") + n


## An ability's display name, else its id spaced out.
static func aname(aid) -> String:
	var a := String(aid) if aid != null else ""
	return String(Content.ABILITIES.get(a, {}).get("name", a.replace("_", " ")))


## The name of a hook source: a resonance, a graft or an ability, in the
## order the dispatcher's ids can collide in (they cannot today: the lint
## keeps the three namespaces disjoint).
static func source_name(sid) -> String:
	var s := String(sid) if sid != null else ""
	if Content.RESONANCES.has(s):
		return String(Content.RESONANCES[s]["name"])
	if Content.GRAFTS.has(s):
		return String(Content.GRAFTS[s]["name"])
	return aname(s)


## SHORT source name, for the log's brackets and the danger readout: cut at
## the first ":" ("fire:solar_lance" -> "fire", "collision:water_jet" ->
## "collision"), then a table name, then a word, then the id spaced out.
static func src_name(src) -> String:
	var s := String(src) if src != null else ""
	var ci := s.find(":")
	var base := s.substr(0, ci) if ci >= 0 else s
	if Content.ENEMIES.has(base):
		return ename(base)
	if Content.ABILITIES.has(base):
		return aname(base)
	if Content.GRAFTS.has(base):
		return String(Content.GRAFTS[base]["name"])
	if Content.RESONANCES.has(base):
		return String(Content.RESONANCES[base]["name"])
	if SRC_WORDS.has(base):
		return String(SRC_WORDS[base])
	return base.replace("_", " ")


## LONG source name, for attribution: "collision:water_jet" -> "Water Jet
## slam", "fire:solar_lance" -> "Solar Lance fire", "fire:env" -> "fire",
## anything else as src_name.
static func src_long(src) -> String:
	var s := String(src) if src != null else ""
	var ci := s.find(":")
	if ci < 0:
		return src_name(s)
	var head := s.substr(0, ci)
	var by := s.substr(ci + 1)
	if head == "collision":
		return aname(by) + " slam"
	if Content.TERRAIN.has(head):
		if by == "" or by == "env":
			return head.replace("_", " ")
		return "%s %s" % [src_name(by), head.replace("_", " ")]
	return src_name(s)


## A consumable item's display name, else its id spaced out.
static func item_name(id) -> String:
	var s := String(id) if id != null else ""
	return String(Content.ITEMS.get(s, {}).get("name", s.replace("_", " ")))


## A shrine purchase in words ("bloom_surge" -> "Bloom Surge", "heal" -> "a heal").
static func shop_name(item: String, id: String) -> String:
	match item:
		"heal":
			return "a heal"
		"graft":
			return String(Content.GRAFTS.get(id, {}).get("name", id.replace("_", " ")))
		"ability":
			return aname(id)
		"item":
			return item_name(id)
	return id.replace("_", " ") if id != "" else item


## Display name for a run choice: loadouts and mutators carry one in Content,
## a package is just its id capitalized, and "" is the opted-out row.
static func choice_name(kind: String, id: String) -> String:
	if id == "":
		return "none"
	match kind:
		"loadout":
			return String(Content.LOADOUTS[id]["name"]) if Content.LOADOUTS.has(id) else id
		"mutator":
			return String(Content.MUTATORS[id]["name"]) if Content.MUTATORS.has(id) else id
	return id.capitalize()
