extends SceneTree
## Composes a shrine or draft SHEET as a single SVG file, headless - the sheets
## are where the reading happens (six or more offers at once) and, unlike the
## map, tests/render_frame.gd never drew them. It renders shell/main.gd's own
## _card_layout dict, so what this shows is the layout the phone draws and not
## a second implementation of it.
## Run: SHEET=shop SHEET_OUT=/tmp/shop.svg godot --headless --path . \
##   --script tests/render_sheet.gd
## SHEET=shop|draft|drop  SHEET_W/SHEET_H (default 1080x2400, a phone)
## SHEET_SEED / SHEET_ACTIONS pick the run state; SHEET_BLOOM funds the purse.

const Game := preload("res://sim/game.gd")
const Content := preload("res://sim/content.gd")
const Art := preload("res://shell/svg_art.gd")
const Shell := preload("res://shell/main.gd")
const Roster := preload("res://bots/roster.gd")

var out_svg: Array = []


func _env(k: String, d: int) -> int:
	return int(OS.get_environment(k)) if OS.get_environment(k) != "" else d


func _sp(id: String, x: float, y: float, s: float) -> String:
	if not Art.ART.has(id):
		return ""
	var doc := String(Art.ART[id])
	var body := doc.substr(doc.find(">") + 1)
	body = body.substr(0, body.rfind("</svg>"))
	return '<g transform="translate(%.1f,%.1f) scale(%.4f)">%s</g>' % [x, y, s / 32.0, body]


func _text(x: float, y: float, s: String, fill: String, size: int, bold := false) -> String:
	return '<text x="%.1f" y="%.1f" font-family="DejaVu Sans, sans-serif" font-size="%d" fill="%s"%s>%s</text>' % [
		x, y, size, fill, ' font-weight="bold"' if bold else "", s.xml_escape()]


func _hex(c: Color) -> String:
	return "#" + c.to_html(false)


func _draw_card(L: Dictionary, r: Rect2, afford: bool) -> void:
	out_svg.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" fill="#1d2a1f" stroke="#4b6349" stroke-width="2"/>' % [
		r.position.x, r.position.y, r.size.x, r.size.y, clampf(r.size.y * 0.22, 8, 22)])
	var ic: Dictionary = L["icon"]
	if int(ic["size"]) > 0:
		out_svg.append(_sp(String(ic["id"]), ic["pos"].x, ic["pos"].y, float(ic["size"])))
	var nm: Dictionary = L["name"]
	out_svg.append(_text(nm["pos"].x, nm["pos"].y, String(nm["text"]), "#d8e0d4", int(nm["size"]), true))
	var pp: Dictionary = L["pips"]
	for c in int(pp["n"]):
		out_svg.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="#e8c840"/>' % [
			float(pp["pos"].x) + c * float(pp["step"]), float(pp["pos"].y), float(pp["radius"])])
	if L.has("up"):
		out_svg.append(_text(L["up"]["pos"].x, L["up"]["pos"].y, "+", "#e8c840", int(L["up"]["size"]), true))
	if L.has("badge"):
		out_svg.append(_text(L["badge"]["pos"].x, L["badge"]["pos"].y, String(L["badge"]["text"]),
			"#e8c840", int(L["badge"]["size"]), true))
	if L.has("price"):
		var pr: Dictionary = L["price"]
		out_svg.append(_sp("ic_bloom", pr["icon_pos"].x, pr["icon_pos"].y, float(pr["icon_size"])))
		out_svg.append(_text(pr["pos"].x, pr["pos"].y, String(pr["text"]),
			"#e8c840" if afford else "#e04b3a", int(pr["size"]), true))
	var de: Dictionary = L["desc"]
	var ly: float = float(de["pos"].y)
	for line in de["lines"]:
		out_svg.append(_text(float(de["pos"].x), ly, String(line), "#97a29a", int(de["size"])))
		ly += float(de["line_h"])


func _init() -> void:
	var which := OS.get_environment("SHEET")
	if which == "":
		which = "shop"
	var vw := float(_env("SHEET_W", 1080))
	var vh := float(_env("SHEET_H", 2400))
	var out := OS.get_environment("SHEET_OUT")
	if out == "":
		out = "/tmp/sheet_%s.svg" % which
	var sh = Shell.new()
	sh._ready()
	var g = Game.new(_env("SHEET_SEED", 7), {"bloom": _env("SHEET_BLOOM", 9)})
	sh.game = g
	sh.screen = "game"
	var title := ""
	var cards: Array = []
	var snap: Dictionary = {}
	if which == "shop":
		g.player["pos"] = g.map["shrine"]
		g.player["items"] = ["balm_fruit", "sun_capsule"]
		snap = g.snapshot()
		title = "SHRINE SHOP"
		cards = sh._shop_cards(snap)
	else:
		# walk a real run to its first descent draft, so the offers and their
		# slot roles are the ones the sim actually deals
		# an optimizer, because a random walker never descends and so never
		# reaches a draft at all
		var bot = Roster.make("optimizer", _env("SHEET_SEED", 7) * Roster.SEED_MUL + Roster.SEED_ADD)
		var guard := 0
		while g.phase != "draft" and not g.over and guard < 6000:
			guard += 1
			g.step(bot.choose_action(g.snapshot(), g.legal_actions()))
		if g.phase != "draft":
			print("no draft reached from seed %d - try another SHEET_SEED" % _env("SHEET_SEED", 7))
			quit()
			return
		snap = g.snapshot()
		title = "DESCENT DRAFT"
		if which == "drop":
			sh.mode = "draft_drop"
			sh.mode_pick = 0
			cards = sh._drop_cards(snap)
		else:
			cards = sh._draft_cards(snap)
	out_svg.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % [
		int(vw), int(vh), int(vw), int(vh)])
	out_svg.append('<rect width="%d" height="%d" fill="#0a120c"/>' % [int(vw), int(vh)])
	out_svg.append('<rect x="%.0f" y="%.0f" width="%.0f" height="%.0f" fill="#121c14" stroke="#5a7a5a" stroke-width="2"/>' % [
		vw * 0.025, vh * 0.035, vw * 0.95, vh * 0.93])
	out_svg.append(_text(vw / 2.0, vh * 0.095, title, "#e8c840", int(vh * 0.034), true)
		.replace("<text ", '<text text-anchor="middle" '))
	var y := vh * 0.16
	var bh := vh * 0.105
	var bloom := int(snap["bloom"])
	if which == "shop":
		out_svg.append(_text(vw * 0.06, y, "bloom  %d" % bloom, "#e8c840", int(vh * 0.026)))
		y += vh * 0.05
		var bot := vh * 0.86
		var gap := vh * 0.02
		bh = minf(vh * 0.105, maxf(vh * 0.06, (bot - y - gap * (cards.size() - 1)) / cards.size()))
		for c in cards:
			var r := Rect2(vw * 0.05, y, vw * 0.9, bh)
			var price := int(c[4])
			_draw_card(sh._card_layout(r, String(c[0]), String(c[1]), String(c[2]), "", int(c[5]), price),
				r, bloom >= price)
			y += bh + gap
	else:
		out_svg.append(_text(vw * 0.06, y, "Take one down with you:", "#d8e0d4", int(vh * 0.024)))
		y += vh * 0.038
		var rl := sh._resonance_line(snap)
		if rl != "":
			out_svg.append(_text(vw * 0.06, y, "ELEMENTS  %s" % rl, "#97a29a", int(vh * 0.019)))
		y += vh * 0.028
		for c in cards:
			var r2 := Rect2(vw * 0.05, y, vw * 0.9, bh)
			_draw_card(sh._card_layout(r2, String(c[0]), String(c[1]), String(c[2]),
				String(c[4]), int(c[5]), -1, bool(c[6])), r2, true)
			y += bh + vh * 0.02
	out_svg.append("</svg>")
	var doc := "\n".join(PackedStringArray(out_svg))
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(doc)
	f.close()
	print("wrote %s (%d cards, %dx%d)" % [out, cards.size(), int(vw), int(vh)])
	# SVG only, deliberately: Godot's own rasterizer (ThorVG) drops <text>
	# entirely, so a PNG from here would be a picture of the layout with every
	# word missing - exactly the thing this tool exists to show
	# the number the owner actually complained about
	var worst := 999
	for c in cards:
		var r3 := Rect2(vw * 0.05, 0, vw * 0.9, bh)
		var L := sh._card_layout(r3, String(c[0]), String(c[1]), String(c[2]))
		worst = mini(worst, int(L["desc"]["size"]))
	print("card height %d px, smallest description %d px" % [int(bh), worst])
	quit()
