extends Node2D
## The human shell (style guide §1/§4): draws the sim's snapshot and forwards
## input as step() actions. The sim never knows this exists — everything here
## reads snapshot()/legal_actions() and writes step(action).
##
## Portrait, touch-first layout: map on top, log + status below, D-pad and
## action buttons at the bottom. Long-press any tile for a tooltip.
## Keyboard still works everywhere (see docs/SHELL.md).

const Game := preload("res://sim/game.gd")
const Content := preload("res://sim/content.gd")
const Art := preload("res://shell/svg_art.gd")

const TILE := 40
const MAP_X := 10
const MAP_Y := 10
const LOG_H := 96
const PANEL_BUDGET := 470
const DPAD_H := 300
const LOG_LINES := 4
const HOLD_MS := 420

const COL_BG := Color("11161a")
const COL_FLOOR := Color("222b26")
const COL_FLOOR_EDGE := Color("2c362f")
const COL_WALL := Color("39424a")
const COL_WALL_TOP := Color("4a545d")
const COL_THREAT := Color(0.88, 0.25, 0.15, 0.30)
const COL_TARGET := Color(0.45, 0.95, 0.45, 0.9)
const COL_TEXT := Color("d8e0d4")
const COL_DIM_TEXT := Color("97a29a")
const COL_GOLD := Color("e8c840")
const COL_RED := Color("e04b3a")
const COL_BTN := Color(0.16, 0.22, 0.18)

## sprite id, display name, one-line blurb — HELP overlay and hold-tooltips
const LEGEND := [
	["player", "You, the Tender", "descend, cleanse, survive"],
	["stairs", "Stairs", "the way down - your objective each floor"],
	["shrine", "Shrine", "stand here and spend bloom on heals, abilities, grafts"],
	["vent", "Vent", "vents reinforcements as the smog rises"],
	["oil", "Oil", "corruption - cleanse it (adjacent) for bloom"],
	["goo", "Goo", "corruption - cleansing yields bloom"],
	["rich_goo", "Rich goo", "corruption - cleanses for extra bloom"],
	["growth", "Growth", "heals 1 HP per turn while you stand on it"],
	["fire", "Fire", "burns whoever stands in it"],
	["smoke", "Smoke", "blocks solar lances"],
	["roots", "Roots", "blocks enemies for a while"],
	["drill_bot", "Drill Bot", "melee - telegraphs its strike a turn ahead"],
	["oil_sludge", "Oil Sludge", "slow, leaves oil, splits when killed"],
	["sludgeling", "Sludgeling", "weak spawn"],
	["leech_drone", "Leech Drone", "drains your banked charge from range"],
	["tar_spitter", "Tar Spitter", "gums up one of your abilities"],
	["coal_golem", "Coal Golem", "tough; bursts into smoke"],
	["extractor_engine", "Extractor", "summons sludgelings - kill it first"],
	["rust_hound", "Rust Hound", "fast - moves twice"],
	["cinder_mite", "Cinder Mite", "ignites oil"],
	["pump_jack", "Pump Jack", "pumps out fresh oil"],
	["smokestack", "Smokestack", "makes the smog clock tick faster"],
	["magnet_crane", "Magnet Crane", "drags you toward it every turn"],
	["furnace_core", "Furnace Core", "floor 7 boss"],
	["overseer", "The Overseer", "floor 7 boss"],
	["the_dredge", "The Dredge", "floor 7 boss - eats your growth"],
]

const DIRS4 := {
	"up": Vector2i(0, -1), "down": Vector2i(0, 1),
	"left": Vector2i(-1, 0), "right": Vector2i(1, 0),
}

var game
var seed_v := 0
var mode := "normal"  # normal | target_dir | target_tile | cleanse | draft_drop | intro | help
var mode_slot := -1
var mode_targets: Array = []
var mode_pick := -1
var flash := ""
var font: Font
var hotspots: Array = []  # rebuilt every _draw: {rect, tag} tap targets
var seen_intro := false

var _press_local := Vector2.ZERO
var _press_ms := 0
var _held := false
var tooltip: Array = []           # lines currently shown
var tooltip_tile := Vector2i(-1, -1)


func _ready() -> void:
	font = ThemeDB.fallback_font
	var env := OS.get_environment("SHELL_SEED")
	if env != "":
		seed_v = int(env)
	else:
		seed_v = int(Time.get_unix_time_from_system()) % 1000000
	set_process(true)
	_new_game()


func _new_game() -> void:
	game = Game.new(seed_v)
	mode = "normal"
	if not seen_intro:
		seen_intro = true
		mode = "intro"
	flash = ""
	tooltip = []
	_fit()
	queue_redraw()


func _content_size() -> Vector2:
	var m: Dictionary = game.map
	var cw := maxf(float(MAP_X * 2 + int(m["w"]) * TILE), 760.0)
	var ch := float(MAP_Y + int(m["h"]) * TILE + LOG_H + PANEL_BUDGET + DPAD_H + 20)
	return Vector2(cw, ch)


## Scale + center the whole canvas so the content fills the window — the map
## fills a portrait phone's width and the text scales up with it.
func _fit() -> void:
	if not is_inside_tree() or game == null:
		return
	var cs := _content_size()
	var vp := get_viewport_rect().size
	var sc := minf(vp.x / cs.x, vp.y / cs.y)
	scale = Vector2(sc, sc)
	position = Vector2((vp.x - cs.x * sc) / 2.0, 0)


func _act(a: Dictionary) -> void:
	if game.over:
		return
	game.step(a)
	mode = "normal"
	mode_targets = []
	flash = ""
	tooltip = []
	_fit()
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
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_press_local = to_local(ev.position)
			_press_ms = Time.get_ticks_msec()
			_held = true
		else:
			var had_tip := not tooltip.is_empty()
			_held = false
			if had_tip:
				tooltip = []
				queue_redraw()
			elif Time.get_ticks_msec() - _press_ms < HOLD_MS:
				_click(to_local(ev.position))
	elif ev is InputEventMouseMotion and _held:
		if to_local(ev.position).distance_to(_press_local) > 26.0:
			_held = false


func _process(_dt: float) -> void:
	if _held and tooltip.is_empty() and Time.get_ticks_msec() - _press_ms >= HOLD_MS:
		_show_tooltip(_press_local)


func _legend_of(id: String) -> Array:
	for row in LEGEND:
		if row[0] == id:
			return row
	return []


## Long-press: describe whatever is on the tile under the finger.
func _show_tooltip(pos: Vector2) -> void:
	if mode == "intro" or mode == "help" or game.over:
		return
	var snap: Dictionary = game.snapshot()
	var t := Vector2i(int((pos.x - MAP_X) / TILE), int((pos.y - MAP_Y) / TILE))
	if t.x < 0 or t.y < 0 or t.x >= int(snap["map"]["w"]) or t.y >= int(snap["map"]["h"]):
		return
	var lines: Array = []
	for e in snap["enemies"]:
		if e["pos"] == t:
			var row := _legend_of(e["kind"])
			lines.append("%s - hp %d%s" % [_ename(e["kind"]), e["hp"], "  ELITE" if e.get("elite", false) else ""])
			lines.append(_intent_words(e))
			if not row.is_empty():
				lines.append(row[2])
	if lines.is_empty() and snap["player"]["pos"] == t:
		lines = ["You - HP %d/%d" % [snap["player"]["hp"], snap["player"]["max_hp"]], "tap yourself to end the turn"]
	if lines.is_empty():
		var id := ""
		if snap["terrain"].has(t):
			id = snap["terrain"][t]["kind"]
		elif t == snap["map"]["stairs"]:
			id = "stairs"
		elif t == snap["map"]["shrine"]:
			id = "shrine"
		elif snap["map"]["vents"].has(t):
			id = "vent"
		var row := _legend_of(id)
		if not row.is_empty():
			lines = [row[1], row[2]]
	if lines.is_empty():
		return
	tooltip = lines
	tooltip_tile = t
	queue_redraw()


func _dir_from_key(k: int) -> Vector2i:
	match k:
		KEY_UP, KEY_W: return Vector2i(0, -1)
		KEY_DOWN, KEY_S: return Vector2i(0, 1)
		KEY_LEFT, KEY_A: return Vector2i(-1, 0)
		KEY_RIGHT, KEY_D: return Vector2i(1, 0)
	return Vector2i.ZERO


func _key(k: int) -> void:
	if mode == "intro" or mode == "help":
		mode = "normal"
		queue_redraw()
		return
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
	if k == KEY_L:
		mode = "help"
		queue_redraw()
		return
	if game.phase == "draft":
		_draft_key(k)
		return
	var d := _dir_from_key(k)
	if d != Vector2i.ZERO:
		_dir_input(d)
		return
	match k:
		KEY_SPACE, KEY_ENTER:
			_act({"type": "end_turn"})
		KEY_C:
			_tap("cleanse")
		KEY_E:
			_tap("descend")
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


## One directional input, from key, D-pad button, or adjacent-tile tap:
## aims in targeting modes, cleanses in cleanse mode, else moves/strikes.
func _dir_input(d: Vector2i) -> void:
	match mode:
		"target_dir":
			_try_ability_target(mode_slot, d)
		"cleanse":
			_act({"type": "cleanse", "target": game.player["pos"] + d})
		_:
			_move_or_strike(d)


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
		_flash("%s: pick a direction (D-pad or tap beside you)" % aid)
	elif acts.size() == 1:
		_act(acts[0])
	else:
		mode = "target_tile"
		mode_slot = slot
		mode_targets = []
		for a in acts:
			mode_targets.append(a["target"])
		_flash("%s: tap a highlighted tile" % aid)
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
	if mode == "intro" or mode == "help":
		mode = "normal"
		queue_redraw()
		return
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
	elif tag.begins_with("dir:"):
		_dir_input(DIRS4[tag.get_slice(":", 1)])
	elif tag == "end_turn":
		_act({"type": "end_turn"})
	elif tag == "cleanse":
		if _legal_of("cleanse").is_empty():
			_flash("nothing cleansable adjacent (or no charge)")
		else:
			mode = "cleanse"
			queue_redraw()
	elif tag == "descend":
		if not _legal_of("descend").is_empty():
			_act({"type": "descend"})
		else:
			_flash("not on the stairs")
	elif tag == "help":
		mode = "help"
		queue_redraw()
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


# --- event log in words -------------------------------------------------------

func _ename(kind: String) -> String:
	return Content.ENEMIES[kind]["name"] if Content.ENEMIES.has(kind) else kind


func _ev_text(ev: Dictionary) -> String:
	match String(ev.get("t", "")):
		"damage":
			if ev.get("who", "") == "player":
				return "You take %d damage (%s)" % [ev["amt"], ev.get("src", "?")]
			return "%s takes %d" % [_ename(ev["who"]), ev["amt"]]
		"death":
			return "%s destroyed" % _ename(ev["who"])
		"player_death":
			return "You die (%s)" % ev.get("cause", "?")
		"heal":
			return "Growth heals you +%d" % ev["amt"]
		"cleanse":
			return "Cleansed - bloom earned"
		"choke":
			return "The smog chokes you"
		"smog_dim":
			return "Skies dim - charge regen drops"
		"reinforcement":
			return "A vent releases a drill bot"
		"gummed":
			return "Tar gums up %s" % str(ev.get("id", "an ability"))
		"drain":
			return "Leech drone drains %d banked charge" % ev["amt"]
		"drag":
			return "You are dragged"
		"stoke":
			return "Smokestack thickens the smog"
		"boss_phase":
			return "BOSS PHASE %d" % ev["phase"]
		"vents_clogged":
			return "The boss clogs the vents with goo"
		"core_shielded":
			return "Core shielded - cleanse the corruption beside it"
		"dredge":
			return "The Dredge devours %d growth and heals" % ev["tiles"]
		"summon":
			return "The extractor summons a sludgeling"
		"split":
			return "The sludge splits"
		"ignite_all":
			return "ALL OIL IGNITES"
		"flood":
			return "Oil floods the arena"
		"smoke_burst":
			return "The golem bursts into smoke"
		"buy":
			return "Bought %s" % str(ev.get("id", ev.get("item", "")))
		"draft_upgrade":
			return "Upgraded to %s" % str(ev["id"])
		"shield":
			return "Shield up (%d)" % ev["total"]
		"thorns":
			return "Thorns up (%d dmg)" % ev["dmg"]
		"anchor":
			return "Anchored - drags can't move you"
		"undim":
			return "Air clears a little - regen recovers"
		"immune":
			return "The boss shrugs off the status"
		"stunned":
			return "Enemy stunned"
		"rooted":
			return "Enemy rooted in place"
		"floor":
			return "— %s —" % str(ev.get("name", "next floor"))
		"illegal":
			return "Can't do that"
	return ""


func _intent_words(e: Dictionary) -> String:
	var it: Dictionary = e["intent"]
	match String(it.get("type", "idle")):
		"attack":
			return "will hit the red tile for %d" % it["dmg"]
		"slam":
			return "will SLAM the red cross for %d" % it["dmg"]
		"quake":
			return "will QUAKE all around it for %d" % it["dmg"]
		"move":
			return "moving toward you"
		"drain":
			return "will drain %d banked charge" % it["amount"]
		"gum":
			return "will gum an ability"
		"summon":
			return "summons in %d" % it["in"]
		"ooze":
			return "oozes oil in %d" % it["in"]
		"stoke":
			return "stokes the smog in %d" % it["in"]
		"drag":
			return "will DRAG you %d closer" % it.get("times", 1)
		"dredge":
			return "will DREDGE growth within %d" % it.get("radius", 2)
		"advance":
			return "advancing %d" % it["steps"]
		"flood":
			return "will flood row %d with oil" % it["row"]
		"gather":
			return "gathering heat"
		"ignite_all":
			return "will IGNITE ALL OIL"
	return "idle"


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


func _button(px: float, py: float, wd: float, ht: float, label: String, tag: String, size: int = 20) -> void:
	var r := Rect2(px, py, wd, ht)
	draw_rect(r, COL_BTN)
	draw_rect(r, COL_DIM_TEXT, false, 1.0)
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_txt(Vector2(px + (wd - tw) / 2.0, py + ht / 2.0 + size * 0.35), label, COL_TEXT, size)
	_hot(r, tag)


func _arrow_button(px: float, py: float, sz: float, dir_name: String) -> void:
	var r := Rect2(px, py, sz, sz)
	draw_rect(r, COL_BTN)
	draw_rect(r, COL_DIM_TEXT, false, 1.0)
	var c := r.get_center()
	var a := sz * 0.22
	var d: Vector2i = DIRS4[dir_name]
	var tip := c + Vector2(d.x, d.y) * a
	var base := c - Vector2(d.x, d.y) * a * 0.6
	var side := Vector2(-d.y, d.x) * a
	draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), COL_TEXT)
	_hot(r, "dir:%s" % dir_name)


func _txt(pos: Vector2, s: String, color: Color = COL_TEXT, size: int = 17) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw() -> void:
	_fit()
	hotspots.clear()
	var snap: Dictionary = game.snapshot()
	var m: Dictionary = snap["map"]
	var w: int = m["w"]
	var h: int = m["h"]
	draw_rect(Rect2(-3000, -3000, 9000, 9000), COL_BG)

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
		draw_rect(_tile_rect(m["stairs"]).grow(-1), COL_GOLD, false, 3.0)
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
			draw_rect(Rect2(r.position + Vector2(3, -5), Vector2(TILE - 6, 4)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(r.position + Vector2(3, -5), Vector2((TILE - 6) * frac, 4)), COL_RED)

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
		for d in DIRS4.values():
			draw_rect(_tile_rect(snap["player"]["pos"] + d).grow(-2), COL_TARGET, false, 1.5)

	var log_y := MAP_Y + h * TILE + 6
	_draw_log(snap, log_y)
	var panel_y := log_y + LOG_H
	_draw_panel(snap, panel_y)
	_draw_dpad(snap, panel_y + PANEL_BUDGET)

	if not tooltip.is_empty():
		_draw_tooltip()
	if snap["phase"] == "draft":
		_draw_draft(snap, w, h)
	if snap["over"]:
		_draw_over(snap, w, h)
	if mode == "intro":
		_draw_intro(w, h)
	elif mode == "help":
		_draw_help(w, h)


func _draw_tooltip() -> void:
	var r := _tile_rect(tooltip_tile)
	var bw := 0.0
	for line in tooltip:
		bw = maxf(bw, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x)
	bw += 24
	var bh := tooltip.size() * 24.0 + 14
	var bx := clampf(r.position.x - bw / 2.0 + TILE / 2.0, 4, _content_size().x - bw - 4)
	var by := r.position.y - bh - 8
	if by < 4:
		by = r.position.y + TILE + 8
	draw_rect(Rect2(bx, by, bw, bh), Color(0.03, 0.05, 0.04, 0.97))
	draw_rect(Rect2(bx, by, bw, bh), COL_GOLD, false, 1.5)
	var y := by + 24
	for i in tooltip.size():
		_txt(Vector2(bx + 12, y), tooltip[i], COL_TEXT if i == 0 else COL_DIM_TEXT, 17)
		y += 24


func _draw_log(snap: Dictionary, ly: float) -> void:
	var lines: Array = []
	for ev in snap["events"]:
		var s := _ev_text(ev)
		if s != "":
			lines.append(s)
	var start: int = maxi(0, lines.size() - LOG_LINES)
	var y := ly + 18
	for i in range(start, lines.size()):
		_txt(Vector2(MAP_X, y), lines[i], COL_DIM_TEXT if i < lines.size() - 1 else COL_TEXT, 16)
		y += 21


func _draw_panel(snap: Dictionary, py: float) -> void:
	var pl: Dictionary = snap["player"]
	var cw := _content_size().x
	var col2_x := cw / 2.0 + 6
	# --- column 1: you ---
	var x := float(MAP_X)
	var y := py + 22
	_txt(Vector2(x, y), "TENDER  seed %d" % seed_v, COL_GOLD, 18); y += 24
	var objective := "Goal: reach the gold-ringed stairs  (floor %d/7)" % snap["floor"]
	if snap["floor"] == 7:
		objective = "Goal: DESTROY THE BOSS"
	_txt(Vector2(x, y), objective, COL_GOLD, 17); y += 24
	var smog_note := "smog %d - rises every turn, keep moving" % snap["smog"]
	if snap["dim"] > 0:
		smog_note = "smog %d - SKIES DIM %d, regen down" % [snap["smog"], snap["dim"]]
	_txt(Vector2(x, y), smog_note, COL_DIM_TEXT if snap["dim"] == 0 else COL_RED, 15); y += 26
	_txt(Vector2(x, y), "HP %d/%d    shield %d" % [pl["hp"], pl["max_hp"], pl["shield"]],
		COL_TEXT if pl["hp"] > 3 else COL_RED, 21); y += 25
	_txt(Vector2(x, y), "charge %d   bank %d   bloom %d" % [pl["charge"], pl["bank"], snap["bloom"]], COL_TEXT, 18); y += 28
	_txt(Vector2(x, y), "ABILITIES - tap to cast:", COL_DIM_TEXT, 14); y += 21
	for i in pl["kit"].size():
		var aid: String = pl["kit"][i]
		var adef: Dictionary = Content.ABILITIES[aid]
		var gum := ""
		if pl["gummed"].has(i):
			gum = "  GUMMED %d" % pl["gummed"][i]
		var col := COL_TEXT if int(pl["charge"]) >= int(adef["cost"]) and not pl["gummed"].has(i) else COL_DIM_TEXT
		_hot(Rect2(x - 4, y - 18, cw / 2.0 - 10, 25), "ability:%d" % i)
		_txt(Vector2(x, y), "%d  %s  (%d)%s" % [i + 1, adef["name"], adef["cost"], gum], col, 19); y += 25
	if not pl["grafts"].is_empty():
		var names: Array = []
		for g in pl["grafts"]:
			names.append(Content.GRAFTS[g]["name"])
		_txt(Vector2(x, y), "grafts: %s" % ", ".join(names), COL_DIM_TEXT, 14); y += 19
	if pl["pos"] == snap["map"]["shrine"] and not snap["shop"].is_empty():
		y += 4
		_txt(Vector2(x, y), "SHRINE - tap to buy:", COL_GOLD, 17); y += 23
		if snap["shop"].get("heal", false):
			_hot(Rect2(x - 4, y - 17, cw / 2.0 - 10, 22), "buy:heal")
			_txt(Vector2(x, y), "  heal 4 HP (%d bloom)" % game.shop_cost("heal"), COL_TEXT, 17); y += 22
		if snap["shop"].has("ability"):
			_hot(Rect2(x - 4, y - 17, cw / 2.0 - 10, 22), "buy:ability")
			_txt(Vector2(x, y), "  learn %s (%d bloom)" % [snap["shop"]["ability"], game.shop_cost("ability")], COL_TEXT, 17); y += 22
		if snap["shop"].has("graft"):
			_hot(Rect2(x - 4, y - 17, cw / 2.0 - 10, 22), "buy:graft")
			_txt(Vector2(x, y), "  graft: %s (%d bloom)" % [Content.GRAFTS[snap["shop"]["graft"]]["name"], game.shop_cost("graft")], COL_TEXT, 17); y += 22
	# --- column 2: them ---
	var y2 := py + 22
	_txt(Vector2(col2_x, y2), "THREATS  (hold a tile for info):", COL_DIM_TEXT, 14); y2 += 21
	var shown := 0
	for e in snap["enemies"]:
		if shown >= 7:
			_txt(Vector2(col2_x, y2), "… and %d more" % (snap["enemies"].size() - shown), COL_DIM_TEXT, 15)
			break
		var elite := "  ELITE" if e.get("elite", false) else ""
		_txt(Vector2(col2_x, y2), "%s  hp %d%s" % [_ename(e["kind"]), e["hp"], elite], COL_TEXT, 17); y2 += 21
		_txt(Vector2(col2_x + 12, y2), _intent_words(e), COL_DIM_TEXT, 14); y2 += 21
		shown += 1
	if flash != "":
		y2 += 6
		_txt(Vector2(col2_x, y2), flash, COL_GOLD, 17); y2 += 22
	match mode:
		"cleanse":
			_txt(Vector2(col2_x, y2 + 6), "CLEANSE: tap/aim at corruption beside you", COL_TARGET, 16)
		"target_dir":
			_txt(Vector2(col2_x, y2 + 6), "AIM with the D-pad or tap beside you", COL_TARGET, 16)
		"target_tile":
			_txt(Vector2(col2_x, y2 + 6), "AIM: tap a highlighted tile", COL_TARGET, 16)


func _draw_dpad(snap: Dictionary, py: float) -> void:
	var cw := _content_size().x
	var b := 92.0
	var gap := 6.0
	var dx := float(MAP_X) + 10
	var dy := py + 10
	_arrow_button(dx + b + gap, dy, b, "up")
	_arrow_button(dx, dy + b + gap, b, "left")
	_button(dx + b + gap, dy + b + gap, b, b, "END", "end_turn", 20)
	_arrow_button(dx + (b + gap) * 2, dy + b + gap, b, "right")
	_arrow_button(dx + b + gap, dy + (b + gap) * 2, b, "down")
	var bx := cw - 230.0
	var bw := 220.0
	var by := dy
	_button(bx, by, bw, 62, "CLEANSE", "cleanse", 20); by += 70
	if not _legal_of("descend").is_empty():
		_button(bx, by, bw, 62, "DESCEND", "descend", 20); by += 70
	_button(bx, by, bw, 62, "HELP / LEGEND", "help", 18)


func _overlay_rect(w: int, h: int, ow: float, oh: float) -> Rect2:
	var cs := _content_size()
	return Rect2((cs.x - ow) / 2.0, maxf((MAP_Y * 2 + h * TILE - oh) / 2.0, 8.0), ow, oh)


func _draw_draft(snap: Dictionary, w: int, h: int) -> void:
	var r := _overlay_rect(w, h, minf(600, _content_size().x - 20), 340)
	draw_rect(r, Color(0.05, 0.08, 0.06, 0.97))
	draw_rect(r, COL_GOLD, false, 2.0)
	var y := r.position.y + 36
	_txt(Vector2(r.position.x + 20, y), "DESCENT DRAFT - tap an ability to add it", COL_GOLD, 20); y += 34
	for i in snap["draft_offers"].size():
		var aid: String = snap["draft_offers"][i]
		var adef: Dictionary = Content.ABILITIES[aid]
		if mode != "draft_drop":
			_hot(Rect2(r.position.x + 12, y - 19, r.size.x - 24, 27), "draft:%d" % i)
		_txt(Vector2(r.position.x + 20, y), "%d   %s   (cost %d)" % [i + 1, adef["name"], adef["cost"]], COL_TEXT, 20); y += 28
	if mode != "draft_drop":
		_hot(Rect2(r.position.x + 12, y - 18, r.size.x - 24, 25), "skip_draft")
		_txt(Vector2(r.position.x + 20, y), "0   skip - take nothing", COL_DIM_TEXT, 18); y += 26
	if mode == "draft_drop":
		y += 8
		_txt(Vector2(r.position.x + 20, y), "Kit is full - tap what to drop:", COL_RED, 19); y += 28
		for i in snap["player"]["kit"].size():
			_hot(Rect2(r.position.x + 24, y - 19, r.size.x - 48, 26), "drop:%d" % i)
			_txt(Vector2(r.position.x + 32, y), "%d   %s" % [i + 1, snap["player"]["kit"][i]], COL_TEXT, 19); y += 27


func _draw_over(snap: Dictionary, w: int, h: int) -> void:
	var r := _overlay_rect(w, h, minf(560, _content_size().x - 20), 210)
	draw_rect(r, Color(0.05, 0.08, 0.06, 0.97))
	draw_rect(r, COL_GOLD if snap["won"] else COL_RED, false, 2.0)
	var msg := "THE FURNACE IS COLD - YOU WIN" if snap["won"] else "YOU DIED - %s" % snap["death_cause"]
	_txt(Vector2(r.position.x + 24, r.position.y + 54), msg, COL_GOLD if snap["won"] else COL_RED, 25)
	_txt(Vector2(r.position.x + 24, r.position.y + 96), "floor %d - turn %d - bloom %d - seed %d" % [snap["floor"], snap["turn"], snap["bloom"], seed_v], COL_TEXT, 18)
	_txt(Vector2(r.position.x + 24, r.position.y + 146), "tap anywhere for a new run  (R replays this seed)", COL_DIM_TEXT, 17)


func _draw_intro(w: int, h: int) -> void:
	var r := _overlay_rect(w, h, minf(720, _content_size().x - 16), 500)
	draw_rect(r, Color(0.04, 0.07, 0.05, 0.98))
	draw_rect(r, COL_GOLD, false, 2.0)
	var x := r.position.x + 26
	var y := r.position.y + 50
	_txt(Vector2(x, y), "TENDER", COL_GOLD, 32); y += 42
	_txt(Vector2(x, y), "The combine poisoned the world. You are a Tender.", COL_TEXT, 19); y += 27
	_txt(Vector2(x, y), "Descend all 7 floors and shut down the Furnace.", COL_TEXT, 19); y += 40
	for line in [
		"TAP a tile next to you (or use the D-pad) to move.",
		"Move into an enemy to attack it. Tap yourself: end turn.",
		"RED tiles are incoming damage next turn. Stay off them.",
		"The GOLD-RINGED stairs are the way down. Move fast -",
		"    smog rises every turn, and deep smog kills.",
		"CLEANSE oil and goo for bloom; spend it at shrines.",
		"Green growth heals you while you stand on it.",
		"HOLD your finger on anything to see what it is.",
	]:
		_txt(Vector2(x, y), line, COL_TEXT, 18); y += 28
	y += 14
	_txt(Vector2(x, y), "- tap to begin -", COL_GOLD, 21)


func _draw_help(w: int, h: int) -> void:
	var cs := _content_size()
	var two_col: bool = cs.x >= 940
	var rows := int(ceil(LEGEND.size() / (2.0 if two_col else 1.0)))
	var col_w := 450.0
	var r := Rect2((cs.x - (col_w * (2 if two_col else 1) + 40)) / 2.0, 8, col_w * (2 if two_col else 1) + 40, 82 + rows * 46.0)
	draw_rect(r, Color(0.04, 0.07, 0.05, 0.98))
	draw_rect(r, COL_GOLD, false, 2.0)
	_txt(Vector2(r.position.x + 24, r.position.y + 40), "LEGEND  (tap anywhere to close)", COL_GOLD, 22)
	for i in LEGEND.size():
		var col := i / rows
		var row := i % rows
		var x := r.position.x + 24 + col * col_w
		var y := r.position.y + 60 + row * 46.0
		var tx := Art.tex(LEGEND[i][0], 40)
		if tx != null:
			draw_texture(tx, Vector2(x, y))
		_txt(Vector2(x + 50, y + 18), LEGEND[i][1], COL_TEXT, 17)
		_txt(Vector2(x + 50, y + 37), LEGEND[i][2], COL_DIM_TEXT, 13)
