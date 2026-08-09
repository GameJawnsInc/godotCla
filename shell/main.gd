extends Node2D
## The human shell (style guide §1/§4): draws the sim's snapshot and forwards
## input as step() actions. The sim never knows this exists — everything here
## reads snapshot()/legal_actions() and writes step(action).
##
## Run: godot --path .        (uses a time-based seed; SHELL_SEED=<n> to pin)
## Controls: arrows/WASD move (into an enemy = strike) · 1-5 cast (arrows for
## direction, click for tiles) · C+dir cleanse · D descend · H/A/G buy ·
## SPACE end turn · ESC cancel · R restart seed · N next seed

const Game := preload("res://sim/game.gd")
const Content := preload("res://sim/content.gd")
const Art := preload("res://shell/svg_art.gd")
const AsciiView := preload("res://sim/ascii_view.gd")

const TILE := 36
const MAP_X := 10
const MAP_Y := 10
const PANEL_W := 340
const LOG_LINES := 7

const COL_BG := Color("11161a")
const COL_FLOOR := Color("222b26")
const COL_FLOOR_EDGE := Color("2c362f")
const COL_WALL := Color("39424a")
const COL_WALL_TOP := Color("4a545d")
const COL_THREAT := Color(0.88, 0.25, 0.15, 0.30)
const COL_TARGET := Color(0.45, 0.95, 0.45, 0.9)
const COL_TEXT := Color("d8e0d4")
const COL_DIM_TEXT := Color("8a958c")
const COL_GOLD := Color("e8c840")
const COL_RED := Color("e04b3a")

var game
var seed_v := 0
var mode := "normal"  # normal | target_dir | target_tile | cleanse | draft_drop
var mode_slot := -1
var mode_targets: Array = []
var mode_pick := -1
var flash := ""
var font: Font
var hotspots: Array = []  # rebuilt every _draw: {rect, tag} tap targets


func _ready() -> void:
	font = ThemeDB.fallback_font
	var env := OS.get_environment("SHELL_SEED")
	if env != "":
		seed_v = int(env)
	else:
		seed_v = int(Time.get_unix_time_from_system()) % 1000000
	_new_game()


func _new_game() -> void:
	game = Game.new(seed_v)
	mode = "normal"
	flash = ""
	queue_redraw()


func _act(a: Dictionary) -> void:
	if game.over:
		return
	game.step(a)
	mode = "normal"
	mode_targets = []
	flash = ""
	queue_redraw()


func _legal_of(kind: String) -> Array:
	var out: Array = []
	for a in game.legal_actions():
		if String(a.get("type", "")) == kind:
			out.append(a)
	return out


# --- input --------------------------------------------------------------------

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		_key(ev.keycode)
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_click(ev.position)


func _dir_from_key(k: int) -> Vector2i:
	match k:
		KEY_UP, KEY_W: return Vector2i(0, -1)
		KEY_DOWN, KEY_S: return Vector2i(0, 1)
		KEY_LEFT, KEY_A: return Vector2i(-1, 0)
		KEY_RIGHT, KEY_D: return Vector2i(1, 0)
	return Vector2i.ZERO


func _key(k: int) -> void:
	if game.over:
		if k == KEY_R:
			_new_game()
		elif k == KEY_N:
			seed_v += 1
			_new_game()
		return
	if k == KEY_ESCAPE:
		mode = "normal"
		mode_targets = []
		flash = ""
		queue_redraw()
		return
	if game.phase == "draft":
		_draft_key(k)
		return
	match mode:
		"target_dir":
			var d := _dir_from_key(k)
			if d != Vector2i.ZERO:
				_try_ability_target(mode_slot, d)
			return
		"cleanse":
			var d := _dir_from_key(k)
			if d != Vector2i.ZERO:
				_act({"type": "cleanse", "target": game.player["pos"] + d})
			return
	# normal mode
	var d := _dir_from_key(k)
	if d != Vector2i.ZERO:
		_move_or_strike(d)
		return
	match k:
		KEY_SPACE, KEY_ENTER:
			_act({"type": "end_turn"})
		KEY_C:
			if _legal_of("cleanse").is_empty():
				_flash("nothing cleansable adjacent (or no charge)")
			else:
				mode = "cleanse"
				queue_redraw()
		KEY_E:
			if not _legal_of("descend").is_empty():
				_act({"type": "descend"})
			else:
				_flash("not on the stairs")
		KEY_H:
			_buy("heal")
		KEY_B:
			_buy("ability")
		KEY_G:
			_buy("graft")
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			_ability_press(k - KEY_1)
		KEY_R:
			_new_game()
		KEY_N:
			seed_v += 1
			_new_game()


func _move_or_strike(d: Vector2i) -> void:
	for a in _legal_of("strike"):
		if a["dir"] == d:
			_act(a)
			return
	for a in _legal_of("move"):
		if a["dir"] == d:
			_act(a)
			return
	_flash("blocked (or no charge)")


func _buy(item: String) -> void:
	for a in _legal_of("buy"):
		if a["item"] == item:
			_act(a)
			return
	_flash("can't buy %s here" % item)


func _ability_press(slot: int) -> void:
	if slot >= game.player["kit"].size():
		return
	var acts: Array = []
	for a in _legal_of("ability"):
		if int(a["slot"]) == slot:
			acts.append(a)
	if acts.is_empty():
		_flash("%s: no legal target / not enough charge / gummed" % game.player["kit"][slot])
		return
	var aid: String = game.player["kit"][slot]
	var ttype: String = Content.ABILITIES[aid]["target"]
	if ttype == "dir" or ttype == "enemy_line":
		mode = "target_dir"
		mode_slot = slot
		_flash("%s: press a direction" % aid)
	elif acts.size() == 1:
		_act(acts[0])
	else:
		mode = "target_tile"
		mode_slot = slot
		mode_targets = []
		for a in acts:
			mode_targets.append(a["target"])
		_flash("%s: click a highlighted tile" % aid)
	queue_redraw()


func _try_ability_target(slot: int, target) -> void:
	for a in _legal_of("ability"):
		if int(a["slot"]) == slot and a["target"] == target:
			_act(a)
			return
	_flash("not a legal target")
	mode = "normal"
	queue_redraw()


func _click(pos: Vector2) -> void:
	for hsp in hotspots:
		if hsp["rect"].has_point(pos):
			_tap(hsp["tag"])
			return
	if game.over:
		seed_v += 1
		_new_game()
		return
	if game.phase == "draft":
		return
	var t := Vector2i(int((pos.x - MAP_X) / TILE), int((pos.y - MAP_Y) / TILE))
	var pp: Vector2i = game.player["pos"]
	match mode:
		"target_tile":
			if mode_targets.has(t):
				_try_ability_target(mode_slot, t)
		"cleanse":
			_act({"type": "cleanse", "target": t})
		"target_dir":
			var d := t - pp
			if absi(d.x) + absi(d.y) == 1:
				_try_ability_target(mode_slot, d)
		"normal":
			if t == pp:
				_act({"type": "end_turn"})
			elif absi(t.x - pp.x) + absi(t.y - pp.y) == 1:
				_move_or_strike(t - pp)


func _tap(tag: String) -> void:
	if tag.begins_with("ability:"):
		_ability_press(int(tag.get_slice(":", 1)))
	elif tag.begins_with("buy:"):
		_buy(tag.get_slice(":", 1))
	elif tag.begins_with("draft:"):
		_draft_pick(int(tag.get_slice(":", 1)))
	elif tag.begins_with("drop:"):
		_act({"type": "draft", "pick": mode_pick, "drop": int(tag.get_slice(":", 1))})
	elif tag == "end_turn":
		_act({"type": "end_turn"})
	elif tag == "cleanse":
		_key(KEY_C)
	elif tag == "descend":
		_key(KEY_E)
	elif tag == "skip_draft":
		_act({"type": "draft", "pick": -1})


func _draft_key(k: int) -> void:
	var snap: Dictionary = game.snapshot()
	if mode == "draft_drop":
		if k >= KEY_1 and k <= KEY_5:
			_act({"type": "draft", "pick": mode_pick, "drop": k - KEY_1})
		return
	if k == KEY_0:
		_act({"type": "draft", "pick": -1})
		return
	if k >= KEY_1 and k <= KEY_1 + snap["draft_offers"].size() - 1:
		_draft_pick(k - KEY_1)


func _draft_pick(pick: int) -> void:
	var needs_drop := false
	for a in game.legal_actions():
		if String(a.get("type", "")) == "draft" and int(a.get("pick", -2)) == pick:
			needs_drop = a.has("drop")
			break
	if needs_drop:
		mode = "draft_drop"
		mode_pick = pick
		queue_redraw()
	else:
		_act({"type": "draft", "pick": pick})


func _flash(msg: String) -> void:
	flash = msg
	queue_redraw()


# --- drawing ------------------------------------------------------------------

func _threat_tiles(snap: Dictionary) -> Dictionary:
	var t := {}
	for e in snap["enemies"]:
		var it: Dictionary = e["intent"]
		match String(it.get("type", "")):
			"attack":
				t[it["tile"]] = true
			"slam":
				t[it["tile"]] = true
				for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
					t[it["tile"] + d] = true
			"quake":
				for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
					t[e["pos"] + d] = true
	return t


func _tile_rect(p: Vector2i) -> Rect2:
	return Rect2(MAP_X + p.x * TILE, MAP_Y + p.y * TILE, TILE, TILE)


func _sprite(id: String, p: Vector2i) -> void:
	var tx := Art.tex(id, TILE)
	if tx != null:
		draw_texture(tx, Vector2(MAP_X + p.x * TILE, MAP_Y + p.y * TILE))


func _hot(r: Rect2, tag: String) -> void:
	hotspots.append({"rect": r, "tag": tag})


func _button(px: float, py: float, wd: float, label: String, tag: String) -> float:
	var r := Rect2(px, py, wd, 36)
	draw_rect(r, Color(0.16, 0.22, 0.18))
	draw_rect(r, COL_DIM_TEXT, false, 1.0)
	_txt(Vector2(px + 12, py + 24), label, COL_TEXT, 14)
	_hot(r, tag)
	return py + 44


func _draw() -> void:
	hotspots.clear()
	var snap: Dictionary = game.snapshot()
	var m: Dictionary = snap["map"]
	var w: int = m["w"]
	var h: int = m["h"]
	draw_rect(Rect2(0, 0, MAP_X * 2 + w * TILE + PANEL_W, MAP_Y * 2 + h * TILE + 150), COL_BG)

	for y in h:
		for x in w:
			var p := Vector2i(x, y)
			var r := _tile_rect(p)
			if m["tiles"][y * w + x] == 1:
				draw_rect(r, COL_FLOOR)
				draw_rect(Rect2(r.position, Vector2(TILE, 1)), COL_FLOOR_EDGE)
			else:
				draw_rect(r, COL_WALL)
				draw_rect(Rect2(r.position, Vector2(TILE, 4)), COL_WALL_TOP)

	for t in snap["terrain"].keys():
		_sprite(snap["terrain"][t]["kind"], t)
	for v in m["vents"]:
		_sprite("vent", v)
	if m["stairs"] != Vector2i(-1, -1):
		_sprite("stairs", m["stairs"])
	if m["shrine"] != Vector2i(-1, -1):
		_sprite("shrine", m["shrine"])

	var threat := _threat_tiles(snap)
	for t in threat:
		draw_rect(_tile_rect(t), COL_THREAT)

	for e in snap["enemies"]:
		_sprite(e["kind"], e["pos"])
		var r := _tile_rect(e["pos"])
		if e.get("elite", false):
			draw_rect(r.grow(-1), COL_GOLD, false, 2.0)
		var edef: Dictionary = Content.ENEMIES[e["kind"]]
		var maxhp: int = int(edef["hp"]) + (Content.ELITE_HP_BONUS if e.get("elite", false) else 0)
		if e["hp"] < maxhp or edef["traits"].has("boss"):
			var frac: float = clampf(float(e["hp"]) / maxf(1.0, float(maxhp)), 0.0, 1.0)
			draw_rect(Rect2(r.position + Vector2(3, -4), Vector2(TILE - 6, 3)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(r.position + Vector2(3, -4), Vector2((TILE - 6) * frac, 3)), COL_RED)

	_sprite("player", snap["player"]["pos"])
	var pr := _tile_rect(snap["player"]["pos"])
	if int(snap["player"].get("anchor_turns", 0)) > 0:
		draw_rect(pr.grow(-1), Color("7a5a34"), false, 2.0)
	if int(snap["player"].get("thorns_turns", 0)) > 0:
		draw_rect(pr.grow(-3), Color("57b34a"), false, 1.5)

	if mode == "target_tile":
		for t in mode_targets:
			draw_rect(_tile_rect(t).grow(-2), COL_TARGET, false, 2.0)
	elif mode == "target_dir" or mode == "cleanse":
		for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			draw_rect(_tile_rect(snap["player"]["pos"] + d).grow(-2), COL_TARGET, false, 1.5)

	_draw_panel(snap, MAP_X * 2 + w * TILE)
	_draw_log(snap, MAP_Y * 2 + h * TILE)
	if snap["phase"] == "draft":
		_draw_draft(snap, w, h)
	if snap["over"]:
		_draw_over(snap, w, h)


func _txt(pos: Vector2, s: String, color: Color = COL_TEXT, size: int = 14) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw_panel(snap: Dictionary, px: int) -> void:
	var pl: Dictionary = snap["player"]
	var y := 26
	_txt(Vector2(px, y), "TENDER  seed %d" % seed_v, COL_GOLD, 16); y += 22
	_txt(Vector2(px, y), "%s  (floor %d)   turn %d" % [snap["floor_name"], snap["floor"], snap["turn"]]); y += 20
	var dim_s := "" if snap["dim"] == 0 else "  DIM %d" % snap["dim"]
	_txt(Vector2(px, y), "smog %d%s" % [snap["smog"], dim_s], COL_DIM_TEXT if snap["dim"] == 0 else COL_RED); y += 24
	_txt(Vector2(px, y), "HP %d/%d   shield %d" % [pl["hp"], pl["max_hp"], pl["shield"]],
		COL_TEXT if pl["hp"] > 3 else COL_RED, 16); y += 20
	_txt(Vector2(px, y), "charge %d   bank %d   bloom %d" % [pl["charge"], pl["bank"], snap["bloom"]]); y += 24
	for i in pl["kit"].size():
		var aid: String = pl["kit"][i]
		var adef: Dictionary = Content.ABILITIES[aid]
		var gum := ""
		if pl["gummed"].has(i):
			gum = "  GUMMED %d" % pl["gummed"][i]
		var col := COL_TEXT if int(pl["charge"]) >= int(adef["cost"]) and not pl["gummed"].has(i) else COL_DIM_TEXT
		_hot(Rect2(px - 4, y - 14, PANEL_W - 20, 18), "ability:%d" % i)
		_txt(Vector2(px, y), "%d  %s (%d)%s" % [i + 1, adef["name"], adef["cost"], gum], col); y += 18
	if not pl["grafts"].is_empty():
		var names: Array = []
		for g in pl["grafts"]:
			names.append(Content.GRAFTS[g]["name"])
		_txt(Vector2(px, y), "grafts: %s" % ", ".join(names), COL_DIM_TEXT); y += 18
	y += 6
	if pl["pos"] == snap["map"]["shrine"] and not snap["shop"].is_empty():
		_txt(Vector2(px, y), "SHRINE:", COL_GOLD); y += 18
		if snap["shop"].get("heal", false):
			_hot(Rect2(px - 4, y - 13, PANEL_W - 20, 16), "buy:heal")
			_txt(Vector2(px, y), "  H  heal 4 (%d bloom)" % game.shop_cost("heal")); y += 16
		if snap["shop"].has("ability"):
			_hot(Rect2(px - 4, y - 13, PANEL_W - 20, 16), "buy:ability")
			_txt(Vector2(px, y), "  B  learn %s (%d bloom)" % [snap["shop"]["ability"], game.shop_cost("ability")]); y += 16
		if snap["shop"].has("graft"):
			_hot(Rect2(px - 4, y - 13, PANEL_W - 20, 16), "buy:graft")
			_txt(Vector2(px, y), "  G  graft %s (%d bloom)" % [Content.GRAFTS[snap["shop"]["graft"]]["name"], game.shop_cost("graft")]); y += 16
		y += 6
	for e in snap["enemies"]:
		var elite := " [ELITE]" if e.get("elite", false) else ""
		_txt(Vector2(px, y), "%s hp%d%s" % [Content.ENEMIES[e["kind"]]["name"], e["hp"], elite],
			COL_RED if _threat_tiles(snap).has(snap["player"]["pos"]) and e["intent"].get("tile", Vector2i(-9, -9)) == snap["player"]["pos"] else COL_TEXT, 13); y += 15
		_txt(Vector2(px + 10, y), AsciiView._intent_str(e), COL_DIM_TEXT, 12); y += 16
	if flash != "":
		y += 6
		_txt(Vector2(px, y), flash, COL_GOLD, 13); y += 16
	y += 8
	var hint := "arrows move/strike · 1-%d cast · C cleanse · E descend · SPACE end turn" % pl["kit"].size()
	if mode == "cleanse":
		hint = "CLEANSE: press a direction (ESC cancels)"
	elif mode == "target_dir":
		hint = "AIM: press a direction (ESC cancels)"
	elif mode == "target_tile":
		hint = "AIM: click a highlighted tile (ESC cancels)"
	_txt(Vector2(px, y), hint, COL_DIM_TEXT, 12)
	y += 14
	y = _button(px, y, 130, "END TURN", "end_turn")
	if not _legal_of("cleanse").is_empty():
		y = _button(px, y, 130, "CLEANSE", "cleanse")
	if not _legal_of("descend").is_empty():
		y = _button(px, y, 130, "DESCEND", "descend")


func _draw_log(snap: Dictionary, ly: int) -> void:
	var evs: Array = snap["events"]
	var start: int = maxi(0, evs.size() - LOG_LINES)
	var y := ly + 18
	for i in range(start, evs.size()):
		_txt(Vector2(MAP_X, y), str(evs[i]), COL_DIM_TEXT, 12)
		y += 15


func _draw_draft(snap: Dictionary, w: int, h: int) -> void:
	var r := Rect2(MAP_X + w * TILE / 2.0 - 220, MAP_Y + h * TILE / 2.0 - 140, 440, 280)
	draw_rect(r, Color(0.05, 0.08, 0.06, 0.95))
	draw_rect(r, COL_GOLD, false, 2.0)
	var y := r.position.y + 28
	_txt(Vector2(r.position.x + 16, y), "DESCENT DRAFT — pick with 1-%d, 0 to skip" % snap["draft_offers"].size(), COL_GOLD, 16); y += 26
	for i in snap["draft_offers"].size():
		var aid: String = snap["draft_offers"][i]
		var adef: Dictionary = Content.ABILITIES[aid]
		if mode != "draft_drop":
			_hot(Rect2(r.position.x + 10, y - 15, r.size.x - 20, 19), "draft:%d" % i)
		_txt(Vector2(r.position.x + 16, y), "%d  %s  (cost %d, %s)" % [i + 1, adef["name"], adef["cost"], adef["target"]]); y += 20
	if mode != "draft_drop":
		_hot(Rect2(r.position.x + 10, y - 13, r.size.x - 20, 17), "skip_draft")
		_txt(Vector2(r.position.x + 16, y), "0  skip", COL_DIM_TEXT); y += 18
	if mode == "draft_drop":
		y += 6
		_txt(Vector2(r.position.x + 16, y), "kit full — press/tap what to drop:", COL_RED); y += 20
		for i in snap["player"]["kit"].size():
			_hot(Rect2(r.position.x + 20, y - 15, r.size.x - 40, 18), "drop:%d" % i)
			_txt(Vector2(r.position.x + 26, y), "%d  %s" % [i + 1, snap["player"]["kit"][i]]); y += 18


func _draw_over(snap: Dictionary, w: int, h: int) -> void:
	var r := Rect2(MAP_X + w * TILE / 2.0 - 190, MAP_Y + h * TILE / 2.0 - 70, 380, 140)
	draw_rect(r, Color(0.05, 0.08, 0.06, 0.95))
	draw_rect(r, COL_GOLD if snap["won"] else COL_RED, false, 2.0)
	var msg := "THE FURNACE IS COLD — YOU WIN" if snap["won"] else "DEAD — %s" % snap["death_cause"]
	_txt(Vector2(r.position.x + 20, r.position.y + 40), msg, COL_GOLD if snap["won"] else COL_RED, 18)
	_txt(Vector2(r.position.x + 20, r.position.y + 70), "floor %d · turn %d · bloom %d · seed %d" % [snap["floor"], snap["turn"], snap["bloom"], seed_v])
	_txt(Vector2(r.position.x + 20, r.position.y + 100), "R restart this seed · N next seed", COL_DIM_TEXT)
