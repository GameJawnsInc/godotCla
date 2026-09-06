extends SceneTree
## Composes a full shell frame as a single SVG file, headless — the same
## sprites and layout the Godot shell draws, for screenshots without a
## display. FRAME_BOT/FRAME_SEED pick the run, FRAME_ACTIONS how far in,
## FRAME_OUT where to write. FRAME_ASH=<n> stamps n ash tiles next to the
## player so the C1b burnt-oil terrain can be seen without waiting for a fire
## to expire.
## Run: FRAME_SEED=42 FRAME_ACTIONS=150 FRAME_OUT=/tmp/frame.svg \
##   godot --headless --path . --script tests/render_frame.gd

const Game := preload("res://sim/game.gd")
const Content := preload("res://sim/content.gd")
const Art := preload("res://shell/svg_art.gd")
const Shell := preload("res://shell/main.gd")
const AsciiView := preload("res://sim/ascii_view.gd")
const BOTS := {
	"wanderer": preload("res://bots/wanderer.gd"),
	"sprout": preload("res://bots/sprout.gd"),
	"magpie": preload("res://bots/magpie.gd"),
	"fanatic": preload("res://bots/fanatic.gd"),
	"optimizer": preload("res://bots/optimizer.gd"),
	"deeproot": preload("res://bots/deeproot.gd"),
}

const T := 36
const PAD := 10


func _sp(id: String, x: float, y: float, s: float = float(T)) -> String:
	if not Art.ART.has(id):
		return ""
	# strip the sprite's outer <svg> wrapper and re-place it as a transformed
	# group - nested <svg x y> loses its position in Godot's rasterizer
	var doc := String(Art.ART[id])
	var body := doc.substr(doc.find(">") + 1)
	body = body.substr(0, body.rfind("</svg>"))
	return '<g transform="translate(%.0f,%.0f) scale(%.3f)">%s</g>' % [x, y, s / 32.0, body]


func _text(x: float, y: float, s: String, fill: String = "#d8e0d4", size: int = 14, bold: bool = false) -> String:
	var wgt := ' font-weight="bold"' if bold else ""
	return '<text x="%.0f" y="%.0f" font-family="monospace" font-size="%d" fill="%s"%s>%s</text>' % [
		x, y, size, fill, wgt, s.xml_escape()]


func _init() -> void:
	var bot_name := OS.get_environment("FRAME_BOT")
	if bot_name == "":
		bot_name = "optimizer"
	var seed_v := 42
	if OS.get_environment("FRAME_SEED") != "":
		seed_v = int(OS.get_environment("FRAME_SEED"))
	var steps := 120
	if OS.get_environment("FRAME_ACTIONS") != "":
		steps = int(OS.get_environment("FRAME_ACTIONS"))
	var out := OS.get_environment("FRAME_OUT")
	if out == "":
		out = "/tmp/frame.svg"

	var game = Game.new(seed_v)
	var bot = BOTS[bot_name].new()
	bot.reset(seed_v * 7919 + 17)
	if bot.has_method("set_sim"):
		bot.set_sim(game)
	for i in steps:
		if game.over:
			break
		game.step(bot.choose_action(game.snapshot(), game.legal_actions()))

	# FRAME_ASH=<n> stamps n ash tiles onto free floor near the player, so a
	# frame containing ash (C1b: what a burnt-out fire leaves) can be rendered
	# without waiting for one to burn out. Rendering-side only: the sim is
	# never asked to place terrain, this pokes the dict the renderer reads.
	var ash_want := 0
	if OS.get_environment("FRAME_ASH") != "":
		ash_want = maxi(1, int(OS.get_environment("FRAME_ASH")))
	var ash_placed := _stamp_ash(game, ash_want)
	var ash_tiles := 0
	for t in game.terrain:
		if String(game.terrain[t]["kind"]) == "ash":
			ash_tiles += 1

	var snap: Dictionary = game.snapshot()
	var m: Dictionary = snap["map"]
	var w: int = m["w"]
	var h: int = m["h"]
	var panel_x := PAD * 2 + w * T
	var total_w := panel_x + 330
	var total_h := maxi(PAD * 2 + h * T + 130, 560)

	var pal: Dictionary = Shell.BIOME_PAL.get(
		String(game.floor_def(game.floor_num).get("biome", "strip_mine")), Shell.BIOME_PAL["strip_mine"])
	var b := '<rect width="%d" height="%d" fill="#11161a"/>' % [total_w, total_h]
	for y in h:
		for x in w:
			var px := PAD + x * T
			var py := PAD + y * T
			if m["tiles"][y * w + x] == 1:
				var fc: Color = pal["f1"] if (x + y) % 2 == 0 else pal["f2"]
				b += '<rect x="%d" y="%d" width="%d" height="%d" fill="#%s"/>' % [px, py, T, T, fc.to_html(false)]
			else:
				b += '<rect x="%d" y="%d" width="%d" height="%d" fill="#%s"/><rect x="%d" y="%d" width="%d" height="4" fill="#%s"/>' % [px, py, T, T, Color(pal["w"]).to_html(false), px, py, T, Color(pal["wt"]).to_html(false)]
	for t in snap["terrain"].keys():
		b += _sp(snap["terrain"][t]["kind"], PAD + t.x * T, PAD + t.y * T)
	for v in m["vents"]:
		b += _sp("vent", PAD + v.x * T, PAD + v.y * T)
	if m["stairs"] != Vector2i(-1, -1):
		b += _sp("stairs", PAD + m["stairs"].x * T, PAD + m["stairs"].y * T)
	if m["shrine"] != Vector2i(-1, -1):
		b += _sp("shrine", PAD + m["shrine"].x * T, PAD + m["shrine"].y * T)

	var threat := {}
	for e in snap["enemies"]:
		var it: Dictionary = e["intent"]
		match String(it.get("type", "")):
			"attack":
				threat[it["tile"]] = true
			"slam":
				threat[it["tile"]] = true
				for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
					threat[it["tile"] + d] = true
			"quake":
				for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
					threat[e["pos"] + d] = true
	for t in threat:
		b += '<rect x="%d" y="%d" width="%d" height="%d" fill="#e04b3a" fill-opacity="0.3"/>' % [PAD + t.x * T, PAD + t.y * T, T, T]

	for e in snap["enemies"]:
		var ex: int = PAD + e["pos"].x * T
		var ey: int = PAD + e["pos"].y * T
		b += _sp(e["kind"], ex, ey)
		if e.get("elite", false):
			b += '<rect x="%d" y="%d" width="%d" height="%d" fill="none" stroke="#e8c840" stroke-width="2"/>' % [ex + 1, ey + 1, T - 2, T - 2]
		var edef: Dictionary = Content.ENEMIES[e["kind"]]
		var maxhp: int = int(edef["hp"]) + (Content.ELITE_HP_BONUS if e.get("elite", false) else 0)
		if e["hp"] < maxhp or edef["traits"].has("boss"):
			var frac: float = clampf(float(e["hp"]) / maxf(1.0, float(maxhp)), 0.0, 1.0)
			b += '<rect x="%d" y="%d" width="%d" height="3" fill="#000" fill-opacity="0.6"/><rect x="%d" y="%d" width="%.0f" height="3" fill="#e04b3a"/>' % [
				ex + 3, ey - 4, T - 6, ex + 3, ey - 4, (T - 6) * frac]

	var pl: Dictionary = snap["player"]
	b += _sp("player", PAD + pl["pos"].x * T, PAD + pl["pos"].y * T)

	var ty := 28.0
	b += _text(panel_x, ty, "TENDER  seed %d (%s)" % [seed_v, bot_name], "#e8c840", 16, true); ty += 24
	b += _text(panel_x, ty, "%s (floor %d)  turn %d" % [snap["floor_name"], snap["floor"], snap["turn"]]); ty += 20
	b += _text(panel_x, ty, "smog %d  dim %d" % [snap["smog"], snap["dim"]], "#e04b3a" if snap["dim"] > 0 else "#8a958c"); ty += 24
	b += _text(panel_x, ty, "HP %d/%d  shield %d" % [pl["hp"], pl["max_hp"], pl["shield"]], "#d8e0d4", 16, true); ty += 20
	b += _text(panel_x, ty, "charge %d  bank %d  bloom %d" % [pl["charge"], pl["bank"], snap["bloom"]]); ty += 24
	for i in pl["kit"].size():
		var adef: Dictionary = Content.ABILITIES[pl["kit"][i]]
		b += _text(panel_x, ty, "%d  %s (%d)" % [i + 1, adef["name"], adef["cost"]]); ty += 18
	ty += 8
	for e in snap["enemies"]:
		b += _text(panel_x, ty, "%s hp%d%s" % [Content.ENEMIES[e["kind"]]["name"], e["hp"], "  [ELITE]" if e.get("elite", false) else ""], "#d8e0d4", 13); ty += 16
		b += _text(panel_x + 10, ty, AsciiView._intent_str(e), "#8a958c", 12); ty += 17

	var ly := PAD + h * T + 18
	var evs: Array = snap["events"]
	for i in range(maxi(0, evs.size() - 6), evs.size()):
		b += _text(PAD, ly, str(evs[i]), "#8a958c", 12); ly += 15

	var doc := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">%s</svg>' % [
		total_w, total_h, total_w, total_h, b]
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(doc)
	f.close()
	print("frame written to %s (floor %d, turn %d, %d enemies, %d ash tiles%s)" % [
		out, snap["floor"], snap["turn"], snap["enemies"].size(), ash_tiles,
		", %d stamped" % ash_placed if ash_placed > 0 else ""])
	quit(0)


## Put up to `want` ash tiles on empty walkable floor near the player, nearest
## first. Returns how many were placed (0 when want is 0). Test scaffolding.
func _stamp_ash(game, want: int) -> int:
	if want <= 0:
		return 0
	var m: Dictionary = game.map
	var w: int = m["w"]
	var pp: Vector2i = game.player["pos"]
	var taken := {pp: true}
	for e in game.enemies:
		taken[e["pos"]] = true
	for v in m["vents"]:
		taken[v] = true
	taken[m["stairs"]] = true
	taken[m["shrine"]] = true
	var free: Array = []
	for y in int(m["h"]):
		for x in w:
			var p := Vector2i(x, y)
			if m["tiles"][y * w + x] != 1 or taken.has(p) or game.terrain.has(p):
				continue
			free.append(p)
	free.sort_custom(func(a, b):
		var da := absi(a.x - pp.x) + absi(a.y - pp.y)
		var db := absi(b.x - pp.x) + absi(b.y - pp.y)
		if da != db:
			return da < db
		return a.y * w + a.x < b.y * w + b.x)
	var n: int = mini(want, free.size())
	for i in n:
		game.terrain[free[i]] = {"kind": "ash"}
	return n
