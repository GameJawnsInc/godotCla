extends RefCounted
## ASCII renderer — one view over the sim's snapshot API (style guide §4).
## Any future renderer consumes the same snapshot/event stream.

const MapGen := preload("res://sim/mapgen.gd")

const TERRAIN_CH := {"oil": "~", "goo": ";", "growth": "\"", "fire": "*", "smoke": "%", "roots": "8", "rich_goo": "&"}
const ENEMY_CH := {"drill_bot": "d", "oil_sludge": "S", "sludgeling": "s", "leech_drone": "L", "tar_spitter": "t", "coal_golem": "G", "extractor_engine": "E", "furnace_core": "F"}


static func render(snap: Dictionary) -> String:
	var m: Dictionary = snap["map"]
	var w: int = m["w"]
	var grid: Array = []
	for y in int(m["h"]):
		var row: Array = []
		for x in w:
			row.append("#" if m["tiles"][y * w + x] == MapGen.T_WALL else ".")
		grid.append(row)
	var stairs: Vector2i = m["stairs"]
	if stairs != Vector2i(-1, -1):
		grid[stairs.y][stairs.x] = ">"
	var shrine: Vector2i = m["shrine"]
	if shrine != Vector2i(-1, -1):
		grid[shrine.y][shrine.x] = "+"
	for v in m["vents"]:
		grid[v.y][v.x] = "^"
	for t in snap["terrain"].keys():
		grid[t.y][t.x] = TERRAIN_CH.get(snap["terrain"][t]["kind"], "?")
	for e in snap["enemies"]:
		grid[e["pos"].y][e["pos"].x] = ENEMY_CH.get(e["kind"], "?")
	var pp: Vector2i = snap["player"]["pos"]
	grid[pp.y][pp.x] = "@"

	var lines: Array = []
	for row in grid:
		lines.append("".join(row))
	var pl: Dictionary = snap["player"]
	lines.append("%s  floor %d  turn %d  smog %d (dim %d)  HP %d/%d  shield %d  charge %d  bank %d  bloom %d" % [
		snap["floor_name"], snap["floor"], snap["turn"], snap["smog"], snap["dim"],
		pl["hp"], pl["max_hp"], pl["shield"], pl["charge"], pl["bank"], snap["bloom"]])
	lines.append("  kit: %s" % ", ".join(pl["kit"]))
	if not pl["grafts"].is_empty():
		lines.append("  grafts: %s" % ", ".join(pl["grafts"]))
	for slot in pl["gummed"]:
		lines.append("  GUMMED: slot %d (%s) for %d turns" % [slot, pl["kit"][slot], pl["gummed"][slot]])
	if snap["phase"] == "draft":
		lines.append("  DRAFT: %s" % ", ".join(snap["draft_offers"]))
	for e in snap["enemies"]:
		var status := ""
		for s in e["status"]:
			if int(e["status"][s]) > 0:
				status += " [%s %d]" % [s, e["status"][s]]
		var elite_tag: String = " [ELITE]" if e.get("elite", false) else ""
		lines.append("  %s#%d hp%d (%d,%d) -> %s%s%s" % [e["kind"], e["id"], e["hp"], e["pos"].x, e["pos"].y, _intent_str(e), status, elite_tag])
	for ev in snap["events"]:
		lines.append("  . %s" % str(ev))
	if snap["over"]:
		lines.append("  == WON ==" if snap["won"] else "  == DEAD (%s) ==" % snap["death_cause"])
	return "\n".join(lines)


static func _intent_str(e: Dictionary) -> String:
	var it: Dictionary = e["intent"]
	match String(it.get("type", "idle")):
		"attack":
			return "ATTACK (%d,%d) for %d" % [it["tile"].x, it["tile"].y, it["dmg"]]
		"drain":
			return "DRAIN %d charge" % it["amount"]
		"move":
			return "move"
		"gum":
			return "GUM slot %d" % it["slot"]
		"flood":
			return "FLOOD row %d with oil" % it["row"]
		"slam":
			return "SLAM (%d,%d) for %d" % [it["tile"].x, it["tile"].y, it["dmg"]]
		"ignite_all":
			return "IGNITE all oil"
		"gather":
			return "gathers heat"
		"summon":
			return "summon in %d" % it["in"]
		_:
			return "idle"
