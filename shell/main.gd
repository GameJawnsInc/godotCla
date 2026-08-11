extends Node2D
## The human shell (style guide §1/§4): draws the sim's snapshot and forwards
## input as step() actions. The sim never knows this exists.
##
## Mobile-first, two-scale layout: the MAP scales to fit its zone (whole floor
## always visible), while all UI is sized in fractions of the physical screen,
## so text and buttons stay finger-sized no matter how big the floor is.
## Zones, top to bottom: status strip · map · ability bar · context line ·
## D-pad + actions. Draft/shop/legend/log/death are full-screen sheets.
## Long-press any tile for a tooltip. Keyboard still works (docs/SHELL.md).

const Game := preload("res://sim/game.gd")
const Content := preload("res://sim/content.gd")
const Art := preload("res://shell/svg_art.gd")
const Tutorial := preload("res://shell/tutorial.gd")
const AudioKit := preload("res://shell/audio.gd")

const CFG_PATH := "user://tender.cfg"

# zone fractions of screen height
const Z_STATUS := 0.062
const Z_MAP_END := 0.56
const Z_AB_END := 0.66
const Z_CTX_END := 0.70

const COL_BG := Color("11161a")
const COL_FLOOR := Color("31402f")
const COL_FLOOR_ALT := Color("2b392b")
const COL_WALL := Color("3a434b")
const COL_WALL_TOP := Color("485259")
const COL_MOSS := Color("55704a")
const COL_CREAM := Color("e6edd8")
const COL_THREAT := Color(0.88, 0.25, 0.15, 0.30)
const COL_TARGET := Color(0.45, 0.95, 0.45, 0.9)
const COL_TEXT := Color("d8e0d4")
const COL_DIM_TEXT := Color("97a29a")
const COL_GOLD := Color("e8c840")
const COL_RED := Color("e04b3a")
const COL_BTN := Color(0.16, 0.22, 0.18)
const COL_SHEET := Color(0.04, 0.07, 0.05, 1.0)

## sprite id, display name, one-line blurb — legend sheet and hold-tooltips
const LEGEND := [
	["player", "You, the Tender", "descend, cleanse, survive"],
	["stairs", "Stairs", "the way down - your goal each floor"],
	["shrine", "Shrine", "stand here to open the shop"],
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
var screen := "menu"  # menu | game | tutorial
var mode := "normal"  # normal | target_dir | target_tile | cleanse | draft_drop | intro | help | shop | log | settings
var mode_slot := -1
var mode_targets: Array = []
var mode_pick := -1
var flash := ""
var font: Font
var hotspots: Array = []
var seen_intro := false
var log_lines: Array = []  # persistent readable history
var tut_step := 0
var tut_done := false
var help_page := 0
var zoom_room := false     # camera toggle: fit the current room, not the floor
var inspect_live := false  # magnifier toggle: hover/drag shows tooltips instantly
var _game_is_run := false  # current `game` is a real run (RESUME-able)

# settings (persisted to user://tender.cfg)
var hold_ms := 420
var seed_mode := "random"  # random | daily
var intro_mode := "once"   # once | always | never
var sfx_on := true
var music_on := true

var audio: Node

var _sb: StyleBoxFlat
var _sb_gold: StyleBoxFlat
var _sb_card: StyleBoxFlat

var _press_pos := Vector2.ZERO
var _press_ms := 0
var _held := false
var tooltip: Array = []
var tooltip_tile := Vector2i(-1, -1)

# layout state recomputed each draw, used by input mapping
var _ts := 40.0
var _mox := 0.0
var _moy := 0.0
var _status_end := 0.0
var _vx0 := 0
var _vy0 := 0
var _vx1 := 999
var _vy1 := 999

const ANIM_MS := 140
var _anim_from := {}  # "player" / enemy id -> Vector2 tile pos before the step
var _anim_ms := -99999


func _ready() -> void:
	font = ThemeDB.fallback_font
	_mk_styles()
	audio = AudioKit.new()
	add_child(audio)
	_load_settings()
	audio.sfx_on = sfx_on
	audio.music_on = music_on
	set_process(true)
	var env := OS.get_environment("SHELL_SEED")
	if env != "":
		seed_v = int(env)
		screen = "game"
		_new_game()
	queue_redraw()


func _roll_seed() -> void:
	if seed_mode == "daily":
		seed_v = hash(Time.get_date_string_from_system(true)) & 0x7FFFFFFF
	else:
		seed_v = (int(Time.get_unix_time_from_system()) * 1103515245 + Time.get_ticks_msec()) % 1000000


func _new_game() -> void:
	game = Game.new(seed_v)
	_game_is_run = true
	mode = "normal"
	if intro_mode == "always" or (intro_mode == "once" and not seen_intro):
		seen_intro = true
		mode = "intro"
	flash = ""
	tooltip = []
	log_lines = []
	queue_redraw()


func _start_tutorial() -> void:
	screen = "tutorial"
	game = Game.new(1, Tutorial.game_config())
	_game_is_run = false
	tut_step = 0
	tut_done = false
	mode = "normal"
	flash = ""
	tooltip = []
	log_lines = []
	queue_redraw()


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) == OK:
		hold_ms = int(cf.get_value("ui", "hold_ms", 420))
		seed_mode = String(cf.get_value("ui", "seed_mode", "random"))
		intro_mode = String(cf.get_value("ui", "intro_mode", "once"))
		sfx_on = bool(cf.get_value("ui", "sfx_on", true))
		music_on = bool(cf.get_value("ui", "music_on", true))


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("ui", "hold_ms", hold_ms)
	cf.set_value("ui", "seed_mode", seed_mode)
	cf.set_value("ui", "intro_mode", intro_mode)
	cf.set_value("ui", "sfx_on", sfx_on)
	cf.set_value("ui", "music_on", music_on)
	cf.save(CFG_PATH)


func _act(a: Dictionary) -> void:
	if game == null or game.over:
		return
	var prev := {"player": Vector2(game.player["pos"])}
	var prev_floor: int = game.floor_num
	for e in game.enemies:
		prev[e["id"]] = Vector2(e["pos"])
	if screen == "tutorial" and not tut_done:
		var st: Dictionary = Tutorial.STEPS[tut_step]
		var kind := String(a.get("type", ""))
		var advances := Tutorial.matches(st, a)
		# strict by default: only the taught action works. Steps that need the
		# player to walk somewhere first opt into free navigation (allow_nav).
		var nav_ok: bool = st.get("allow_nav", false) and kind in ["move", "end_turn", "strike"]
		if not advances and not nav_ok:
			_flash("follow the guide for now")
			return
		_play_events(game.step(a))
		if advances:
			if st.get("until_dead", false):
				if game.enemies.is_empty():
					tut_step += 1
			else:
				tut_step += 1
			if tut_step >= Tutorial.STEPS.size():
				tut_done = true
		elif st.get("until_dead", false) and game.enemies.is_empty():
			tut_step += 1
			if tut_step >= Tutorial.STEPS.size():
				tut_done = true
		mode = "normal"
		mode_targets = []
		flash = ""
		tooltip = []
		queue_redraw()
		return
	var keep_shop := mode == "shop" and String(a.get("type", "")) == "buy"
	var evs: Array = game.step(a)
	_arm_anim(prev, prev_floor)
	for ev in evs:
		var s := _ev_text(ev)
		if s != "" and (log_lines.is_empty() or log_lines.back() != s):
			log_lines.append(s)
	if log_lines.size() > 60:
		log_lines = log_lines.slice(log_lines.size() - 60)
	_play_events(evs)
	mode = "normal"
	if keep_shop and game.player["pos"] == game.map["shrine"] and not game.shop.is_empty():
		mode = "shop"
	mode_targets = []
	flash = ""
	tooltip = []
	queue_redraw()


## Map a step's events to at most three synthesized sounds, worst first.
func _play_events(evs: Array) -> void:
	if audio == null:
		return
	var picks: Array = []
	for ev in evs:
		var t := String(ev.get("t", ""))
		var id := ""
		match t:
			"player_death": id = "death"
			"boss_phase": id = "boss"
			"damage": id = "hurt" if ev.get("who", "") == "player" else ""
			"death": id = "kill"
			"strike": id = "hit"
			"ability": id = "cast"
			"cleanse": id = "sparkle"
			"heal": id = "heal"
			"buy", "draft_upgrade": id = "coin"
			"drag": id = "drag"
			"reinforcement", "summon": id = "vent"
			"smog_dim", "choke", "stoke": id = "dim"
			"floor": id = "descend"
			"move": id = "step" if ev.get("who", "") == "player" else ""
		if id != "" and not picks.has(id):
			picks.append(id)
	if game != null and game.won:
		picks = ["win"]
	elif picks.has("death"):
		picks = ["death"]
	for i in mini(3, picks.size()):
		audio.play(picks[i])


func _arm_anim(prev: Dictionary, prev_floor: int) -> void:
	if game.floor_num != prev_floor:
		_anim_from = {}
		return
	_anim_from = prev
	_anim_ms = Time.get_ticks_msec()


## Where to draw a creature right now: sliding from its previous tile for a
## beat after each step. Long jumps (teleports, dashes) snap instead.
func _anim_pos(key, cur: Vector2i) -> Vector2:
	var t := (Time.get_ticks_msec() - _anim_ms) / float(ANIM_MS)
	if t >= 1.0 or not _anim_from.has(key):
		return Vector2(cur)
	var from: Vector2 = _anim_from[key]
	if from.distance_to(Vector2(cur)) > 3.0:
		return Vector2(cur)
	return from.lerp(Vector2(cur), clampf(t, 0.0, 1.0))


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
			_press_pos = ev.position
			_press_ms = Time.get_ticks_msec()
			_held = true
		else:
			var had_tip := not tooltip.is_empty() and not inspect_live
			_held = false
			if had_tip:
				tooltip = []
				queue_redraw()
			elif Time.get_ticks_msec() - _press_ms < hold_ms:
				_click(ev.position)
	elif ev is InputEventMouseMotion:
		if inspect_live and screen != "menu" and game != null and not game.over and mode == "normal":
			var t := _map_tile(ev.position)
			if t != tooltip_tile:
				_show_tooltip(ev.position)  # only replaces when there is something to say
		if _held and ev.position.distance_to(_press_pos) > 30.0:
			_held = false


func _process(_dt: float) -> void:
	if screen == "menu":
		return
	if _held and tooltip.is_empty() and Time.get_ticks_msec() - _press_ms >= hold_ms:
		_show_tooltip(_press_pos)
	var animating: bool = Time.get_ticks_msec() - _anim_ms < ANIM_MS + 40
	var smoggy: bool = game != null and not game.over and (int(game.smog) > 0 or int(game.dim) > 0)
	if animating or smoggy:
		queue_redraw()


func _map_tile(pos: Vector2) -> Vector2i:
	return Vector2i(int((pos.x - _mox) / _ts), int((pos.y - _moy) / _ts))


func _legend_of(id: String) -> Array:
	for row in LEGEND:
		if row[0] == id:
			return row
	return []


func _show_tooltip(pos: Vector2) -> void:
	if mode == "intro" or mode == "help" or mode == "log" or game.over:
		return
	# holding an ability button explains the ability
	for hsp in hotspots:
		if hsp["rect"].has_point(pos) and String(hsp["tag"]).begins_with("ability:"):
			var slot := int(String(hsp["tag"]).get_slice(":", 1))
			var aid: String = game.player["kit"][slot]
			var adef: Dictionary = Content.ABILITIES[aid]
			tooltip = ["%s - costs %d charge" % [adef["name"], adef["cost"]], _ability_desc(aid)]
			tooltip_tile = Vector2i(-1, -1)
			queue_redraw()
			return
	var snap: Dictionary = game.snapshot()
	var t := _map_tile(pos)
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
	if screen == "menu":
		if mode == "settings":
			mode = "normal"
			queue_redraw()
		elif k == KEY_ENTER or k == KEY_SPACE:
			_tap("play")
		return
	if screen == "tutorial" and tut_done:
		_tap("menu")
		return
	if mode == "help":
		if help_page < _help_pages() - 1:
			help_page += 1
		else:
			mode = "normal"
		queue_redraw()
		return
	if mode == "intro" or mode == "log" or mode == "shop":
		if mode == "shop" and k == KEY_H:
			_buy("heal")
			return
		if mode == "shop" and k == KEY_B:
			_buy("ability")
			return
		if mode == "shop" and k == KEY_G:
			_buy("graft")
			return
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
		if mode == "normal":
			_tap("menu")
		else:
			mode = "normal"
			mode_targets = []
			flash = ""
			queue_redraw()
		return
	if k == KEY_L:
		mode = "help"
		help_page = 0
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
			_tap("shop")
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			_ability_press(k - KEY_1)
		KEY_Z:
			_tap("zoom")
		KEY_I:
			_tap("inspect")
		KEY_R:
			_new_game()
		KEY_N:
			seed_v += 1
			_new_game()


func _dir_input(d: Vector2i) -> void:
	match mode:
		"target_dir":
			_try_ability_target(mode_slot, d)
		"cleanse":
			_cleanse_at(game.player["pos"] + d)
		_:
			_move_or_strike(d)


## Cleanse a tile; if the target is valid but charge ran dry, end the turn
## first and then cleanse (same convenience as movement).
func _cleanse_at(target: Vector2i) -> void:
	for a in _legal_of("cleanse"):
		if a["target"] == target:
			_act(a)
			return
	var pp: Vector2i = game.player["pos"]
	var kind: String = game.terrain.get(target, {}).get("kind", "")
	var corrupt: bool = kind in ["oil", "goo", "rich_goo"]
	if corrupt and absi(target.x - pp.x) + absi(target.y - pp.y) == 1:
		if screen == "tutorial":
			_flash("out of charge - press END to refill")
			return
		_act({"type": "end_turn"})
		if game.over:
			return
		for a in _legal_of("cleanse"):
			if a["target"] == target:
				_act(a)
				return
	else:
		_flash("aim at corruption right next to you")


func _move_or_strike(d: Vector2i) -> void:
	for a in _legal_of("strike"):
		if a["dir"] == d:
			_act(a)
			return
	for a in _legal_of("move"):
		if a["dir"] == d:
			_act(a)
			return
	# in the tutorial, running dry is the lesson - never auto-end a turn there,
	# because the synthetic end_turn would advance "end your turn" steps
	if screen == "tutorial":
		_flash("out of charge - press END to refill")
		return
	# the way is open but charge ran dry: end the turn, then go
	var m: Dictionary = game.map
	var dest: Vector2i = game.player["pos"] + d
	var open: bool = dest.x >= 0 and dest.y >= 0 and dest.x < int(m["w"]) and dest.y < int(m["h"]) \
		and int(m["tiles"][dest.y * int(m["w"]) + dest.x]) == 1
	if open:
		_act({"type": "end_turn"})
		if game.over:
			return
		for a in _legal_of("strike"):
			if a["dir"] == d:
				_act(a)
				return
		for a in _legal_of("move"):
			if a["dir"] == d:
				_act(a)
				return
		return
	_flash("blocked")


func _buy(item: String) -> void:
	for a in _legal_of("buy"):
		if a["item"] == item:
			_act(a)
			return
	_flash("can't buy that")


func _ability_press(slot: int) -> void:
	if slot >= game.player["kit"].size():
		return
	var acts: Array = []
	for a in _legal_of("ability"):
		if int(a["slot"]) == slot:
			acts.append(a)
	if acts.is_empty():
		_flash("%s: no target / no charge / gummed" % Content.ABILITIES[game.player["kit"][slot]]["name"])
		return
	var aid: String = game.player["kit"][slot]
	var ttype: String = Content.ABILITIES[aid]["target"]
	if ttype == "dir" or ttype == "enemy_line":
		mode = "target_dir"
		mode_slot = slot
		_flash("AIM %s: D-pad or tap beside you" % Content.ABILITIES[aid]["name"])
	elif acts.size() == 1:
		_act(acts[0])
	else:
		mode = "target_tile"
		mode_slot = slot
		mode_targets = []
		for a in acts:
			mode_targets.append(a["target"])
		_flash("AIM %s: tap a green tile" % Content.ABILITIES[aid]["name"])
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
	if screen == "menu":
		for hsp in hotspots:
			if hsp["rect"].has_point(pos):
				_tap(hsp["tag"])
				return
		if mode == "settings":
			mode = "normal"
			queue_redraw()
		return
	if screen == "tutorial" and tut_done:
		_tap("menu")
		return
	if mode == "help":
		if help_page < _help_pages() - 1:
			help_page += 1
		else:
			mode = "normal"
		queue_redraw()
		return
	if mode == "intro" or mode == "log":
		mode = "normal"
		queue_redraw()
		return
	for hsp in hotspots:
		if hsp["rect"].has_point(pos):
			_tap(hsp["tag"])
			return
	if mode == "shop":
		mode = "normal"
		queue_redraw()
		return
	if game.over:
		if screen == "tutorial":
			_tap("menu")
		else:
			_roll_seed()
			_new_game()
		return
	if game.phase == "draft":
		return
	var t := _map_tile(pos)
	var pp: Vector2i = game.player["pos"]
	match mode:
		"target_tile":
			if mode_targets.has(t):
				_try_ability_target(mode_slot, t)
		"cleanse":
			_cleanse_at(t)
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
	if audio != null:
		audio.play("tap")
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
		var can := not _legal_of("cleanse").is_empty()
		if not can and game != null:
			for d in DIRS4.values():
				if String(game.terrain.get(game.player["pos"] + d, {}).get("kind", "")) in ["oil", "goo", "rich_goo"]:
					can = true
					break
		if can:
			mode = "cleanse"
			queue_redraw()
		else:
			_flash("no corruption beside you")
	elif tag == "descend":
		if not _legal_of("descend").is_empty():
			_act({"type": "descend"})
	elif tag == "shop":
		if game.player["pos"] == game.map["shrine"] and not game.shop.is_empty():
			mode = "shop"
			queue_redraw()
	elif tag == "zoom":
		zoom_room = not zoom_room
		queue_redraw()
	elif tag == "inspect":
		inspect_live = not inspect_live
		tooltip = []
		queue_redraw()
	elif tag == "help":
		mode = "help"
		help_page = 0
		queue_redraw()
	elif tag == "log":
		mode = "log"
		queue_redraw()
	elif tag == "close":
		mode = "normal"
		queue_redraw()
	elif tag == "skip_draft":
		_act({"type": "draft", "pick": -1})
	elif tag == "draft_back":
		mode = "normal"
		queue_redraw()
	elif tag == "play":
		_roll_seed()
		screen = "game"
		_new_game()
	elif tag == "resume":
		if game != null and not game.over and screen != "tutorial":
			screen = "game"
			queue_redraw()
	elif tag == "tutorial":
		_start_tutorial()
	elif tag == "settings":
		mode = "settings"
		queue_redraw()
	elif tag == "menu":
		screen = "menu"
		mode = "normal"
		tooltip = []
		queue_redraw()
	elif tag == "quit":
		if is_inside_tree():
			get_tree().quit()
	elif tag.begins_with("set:"):
		match tag.get_slice(":", 1):
			"sfx":
				sfx_on = not sfx_on
				audio.sfx_on = sfx_on
			"music":
				music_on = not music_on
				audio.set_music(music_on)
			"hold":
				hold_ms = {300: 420, 420: 650, 650: 300}.get(hold_ms, 420)
			"seed":
				seed_mode = "daily" if seed_mode == "random" else "random"
			"intro":
				intro_mode = {"once": "always", "always": "never", "never": "once"}.get(intro_mode, "once")
		_save_settings()
		queue_redraw()


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
			return "Tar gums up an ability"
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

func _vis(p: Vector2i) -> bool:
	return p.x >= _vx0 and p.x <= _vx1 and p.y >= _vy0 and p.y <= _vy1


## The room the player stands in (grown by one for its doorways), or a small
## window around them when they're in a corridor.
func _room_view(m: Dictionary) -> Rect2i:
	var pp: Vector2i = game.player["pos"]
	for r in m.get("rooms", []):
		var rr: Rect2i = r
		if rr.grow(1).has_point(pp):
			return rr.grow(1)
	return Rect2i(pp.x - 4, pp.y - 3, 9, 7)


func _threat_tiles(snap: Dictionary) -> Dictionary:
	var t := {}
	for e in snap["enemies"]:
		var it: Dictionary = e["intent"]
		match String(it.get("type", "")):
			"attack":
				t[it["tile"]] = true
			"slam":
				t[it["tile"]] = true
				for d in DIRS4.values():
					t[it["tile"] + d] = true
			"quake":
				for d in DIRS4.values():
					t[e["pos"] + d] = true
	return t


func _tile_rect(p: Vector2i) -> Rect2:
	return Rect2(_mox + p.x * _ts, _moy + p.y * _ts, _ts, _ts)


func _tile_rect_f(p: Vector2) -> Rect2:
	return Rect2(_mox + p.x * _ts, _moy + p.y * _ts, _ts, _ts)


func _sprite_f(id: String, p: Vector2) -> void:
	var tx := Art.tex(id, int(_ts))
	if tx != null:
		draw_texture(tx, Vector2(_mox + p.x * _ts, _moy + p.y * _ts))


func _shadow_f(p: Vector2) -> void:
	var r := _tile_rect_f(p)
	draw_set_transform(Vector2(r.get_center().x, r.position.y + _ts * 0.86), 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, _ts * 0.36, Color(0, 0, 0, 0.32))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _sprite(id: String, p: Vector2i) -> void:
	var tx := Art.tex(id, int(_ts))
	if tx != null:
		draw_texture(tx, Vector2(_mox + p.x * _ts, _moy + p.y * _ts))


## Soft ground shadow that lifts creatures off the tiles.
func _shadow(p: Vector2i) -> void:
	var r := _tile_rect(p)
	draw_set_transform(Vector2(r.get_center().x, r.position.y + _ts * 0.86), 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, _ts * 0.36, Color(0, 0, 0, 0.32))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _hot(r: Rect2, tag: String) -> void:
	hotspots.append({"rect": r, "tag": tag})


func _txt(pos: Vector2, s: String, color: Color = COL_TEXT, size: int = 20) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _txt_c(cx: float, ypos: float, s: String, color: Color, size: int) -> void:
	var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(cx - tw / 2.0, ypos), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Shrink a font size until the string fits max_w — no more clipped lines.
func _fit_size(s: String, size: int, max_w: float) -> int:
	while size > 9 and font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
		size -= 1
	return size


func _txt_fit(pos: Vector2, s: String, color: Color, size: int, max_w: float) -> void:
	_txt(pos, s, color, _fit_size(s, size, max_w))


func _txt_c_fit(cx: float, ypos: float, s: String, color: Color, size: int, max_w: float) -> void:
	_txt_c(cx, ypos, s, color, _fit_size(s, size, max_w))


## Top inset so notches / punch-hole cameras don't cover the status strip.
func _safe_top(vh: float) -> float:
	var pad := vh * 0.012
	if is_inside_tree():
		var sa := DisplayServer.get_display_safe_area()
		var wp := DisplayServer.window_get_position()
		pad = maxf(pad, float(sa.position.y - wp.y))
	return minf(pad, vh * 0.06)


## Solarpunk button skin: rounded moss-green panels, brass borders on the
## primary actions, soft drop shadow - grown, not stamped.
func _mk_styles() -> void:
	_sb = StyleBoxFlat.new()
	_sb.bg_color = Color("2e4632")
	_sb.set_corner_radius_all(16)
	_sb.set_border_width_all(2)
	_sb.border_color = Color("79a865")
	_sb.shadow_color = Color(0, 0, 0, 0.35)
	_sb.shadow_size = 5
	_sb.shadow_offset = Vector2(0, 3)
	_sb_gold = _sb.duplicate()
	_sb_gold.border_color = Color("e0b74d")
	_sb_gold.bg_color = Color("40482a")
	_sb_card = _sb.duplicate()
	_sb_card.bg_color = Color("25382b")
	_sb_card.border_color = Color("5c8253")


func _box(r: Rect2, style: StyleBoxFlat) -> void:
	style.set_corner_radius_all(int(clampf(r.size.y * 0.22, 8, 22)))
	draw_style_box(style, r)
	# soft sun-sheen along the top edge
	draw_rect(Rect2(r.position.x + r.size.y * 0.25, r.position.y + 2.5,
		maxf(r.size.x - r.size.y * 0.5, 4.0), 2.0), Color(0.9, 1.0, 0.8, 0.10))


func _button(r: Rect2, label: String, tag: String, size: int, border: Color = COL_DIM_TEXT) -> void:
	_box(r, _sb_gold if border == COL_GOLD else _sb)
	if border == COL_RED:
		draw_rect(r.grow(-2), COL_RED, false, 2.0)
	var fs2 := _fit_size(label, size, r.size.x * 0.92)
	_txt_c(r.get_center().x, r.get_center().y + fs2 * 0.35, label, COL_TEXT, fs2)
	_hot(r, tag)


func _icon_button(r: Rect2, icon: String, tag: String, active: bool) -> void:
	_box(r, _sb_gold if active else _sb)
	var isz := int(r.size.x * 0.6)
	var tx := Art.tex(icon, isz)
	if tx != null:
		draw_texture(tx, r.position + (r.size - Vector2(isz, isz)) / 2.0)
	_hot(r, tag)


func _arrow_button(r: Rect2, dir_name: String) -> void:
	_box(r, _sb)
	var c := r.get_center()
	var a := r.size.x * 0.22
	var d: Vector2i = DIRS4[dir_name]
	var tip := c + Vector2(d.x, d.y) * a
	var base := c - Vector2(d.x, d.y) * a * 0.6
	var side := Vector2(-d.y, d.x) * a
	draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), COL_CREAM)
	_hot(r, "dir:%s" % dir_name)


func _draw() -> void:
	hotspots.clear()
	var vw := get_viewport_rect().size.x
	var vh := get_viewport_rect().size.y
	draw_rect(Rect2(0, 0, vw, vh), COL_BG)
	if screen == "menu":
		_draw_menu(vw, vh)
		if mode == "settings":
			_draw_settings(vw, vh)
		return
	var snap: Dictionary = game.snapshot()

	_draw_status(snap, vw, vh)
	_draw_map(snap, vw, vh)
	_draw_ability_bar(snap, vw, vh)
	_draw_context(snap, vw, vh)
	_draw_controls(snap, vw, vh)

	if screen == "tutorial":
		_draw_tut_banner(vw, vh)
	if not tooltip.is_empty():
		_draw_tooltip(vw, vh)
	if snap["phase"] == "draft" and screen != "tutorial":
		_draw_draft(snap, vw, vh)
	if mode == "shop":
		_draw_shop(snap, vw, vh)
	elif mode == "log":
		_draw_logsheet(vw, vh)
	elif mode == "help":
		_draw_help(vw, vh)
	elif mode == "intro":
		_draw_intro(vw, vh)
	if screen == "tutorial" and tut_done:
		_draw_tut_done(vw, vh)
	elif snap["over"]:
		_draw_over(snap, vw, vh)


func _draw_menu(vw: float, vh: float) -> void:
	# title vignette: the tender flanked by what it fights
	_txt_c(vw / 2.0, vh * 0.17, "T E N D E R", COL_GOLD, int(vh * 0.065))
	_txt_c(vw / 2.0, vh * 0.21, "a solarpunk roguelike", COL_DIM_TEXT, int(vh * 0.021))
	var big := vh * 0.11
	var cy := vh * 0.27
	var tx := Art.tex("player", int(big))
	if tx != null:
		draw_texture(tx, Vector2(vw / 2.0 - big / 2.0, cy))
	var small := vh * 0.05
	for spec in [["growth", -0.32], ["drill_bot", -0.18], ["smokestack", 0.18 - 0.046], ["oil", 0.32 - 0.046]]:
		var t2 := Art.tex(spec[0], int(small))
		if t2 != null:
			draw_texture(t2, Vector2(vw / 2.0 + vw * spec[1], cy + big - small), Color(1, 1, 1, 0.75))
	draw_rect(Rect2(vw * 0.2, cy + big + vh * 0.03, vw * 0.6, 2), Color(0.34, 0.44, 0.36))

	var bw := vw * 0.62
	var bh := vh * 0.072
	var bx := (vw - bw) / 2.0
	var y := vh * 0.46
	if game != null and not game.over and _game_is_run:
		_button(Rect2(bx, y, bw, bh), "RESUME RUN", "resume", int(bh * 0.38), COL_GOLD)
		y += bh + vh * 0.024
	_button(Rect2(bx, y, bw, bh), "PLAY", "play", int(bh * 0.42), COL_GOLD)
	y += bh + vh * 0.024
	_button(Rect2(bx, y, bw, bh), "TUTORIAL", "tutorial", int(bh * 0.38))
	y += bh + vh * 0.024
	_button(Rect2(bx, y, bw, bh), "SETTINGS", "settings", int(bh * 0.38))
	y += bh + vh * 0.024
	_button(Rect2(bx, y, bw, bh), "QUIT", "quit", int(bh * 0.38))
	_txt_c(vw / 2.0, vh * 0.96, "seed mode: %s" % seed_mode, COL_DIM_TEXT, int(vh * 0.016))


func _draw_settings(vw: float, vh: float) -> void:
	hotspots.clear()
	var y := _sheet(vw, vh, "SETTINGS")
	var bw := vw * 0.88
	var bh := vh * 0.08
	var names := {300: "short", 420: "normal", 650: "long"}
	_button(Rect2(vw * 0.06, y, bw, bh), "Hold-to-inspect delay:  %s" % names.get(hold_ms, "normal"), "set:hold", int(bh * 0.3))
	y += bh + vh * 0.025
	_button(Rect2(vw * 0.06, y, bw, bh), "Run seed:  %s" % ("random every run" if seed_mode == "random" else "daily (same for everyone)"), "set:seed", int(bh * 0.28))
	y += bh + vh * 0.025
	_button(Rect2(vw * 0.06, y, bw, bh), "Intro tips:  %s" % intro_mode, "set:intro", int(bh * 0.3))
	y += bh + vh * 0.025
	_button(Rect2(vw * 0.06, y, bw, bh), "Sound effects:  %s" % ("on" if sfx_on else "off"), "set:sfx", int(bh * 0.3))
	y += bh + vh * 0.025
	_button(Rect2(vw * 0.06, y, bw, bh), "Music:  %s" % ("on" if music_on else "off"), "set:music", int(bh * 0.3))
	y += bh + vh * 0.05
	_button(Rect2(vw * 0.06, y, bw, bh), "BACK", "close", int(bh * 0.34))


func _draw_tut_banner(vw: float, vh: float) -> void:
	if tut_done:
		return
	var st: Dictionary = Tutorial.STEPS[tut_step]
	var lines: Array = st["say"]
	var fsz := int(vh * 0.0215)
	var lh := fsz * 1.5
	var bh := lines.size() * lh + vh * 0.045
	var by := vh * Z_MAP_END - bh - vh * 0.004
	draw_rect(Rect2(vw * 0.02, by, vw * 0.96, bh), Color(0.05, 0.09, 0.06, 0.97))
	draw_rect(Rect2(vw * 0.02, by, vw * 0.96, bh), COL_GOLD, false, 2.0)
	_txt(Vector2(vw * 0.05, by + vh * 0.028), "GUIDE  %d/%d" % [tut_step + 1, Tutorial.STEPS.size()], COL_GOLD, int(vh * 0.016))
	var ty := by + vh * 0.03 + lh * 0.8
	for line in lines:
		_txt_fit(Vector2(vw * 0.05, ty), line, COL_TEXT, fsz, vw * 0.9)
		ty += lh
	var xr := Rect2(vw * 0.86, by + vh * 0.008, vw * 0.11, vh * 0.032)
	_button(xr, "EXIT", "menu", int(vh * 0.016))
	# pulse the stairs when the guide points there
	if st.get("guide_to_stairs", false) and game.map["stairs"] != Vector2i(-1, -1) and _vis(game.map["stairs"]):
		var pulse := 2.0 + 2.0 * absf(sin(Time.get_ticks_msec() / 300.0))
		draw_rect(_tile_rect(game.map["stairs"]).grow(3), COL_GOLD, false, pulse)
		queue_redraw()


func _draw_tut_done(vw: float, vh: float) -> void:
	hotspots.clear()
	draw_rect(Rect2(0, 0, vw, vh), COL_SHEET)
	_txt_c(vw / 2.0, vh * 0.22, "TUTORIAL COMPLETE", COL_GOLD, int(vh * 0.04))
	var y := vh * 0.32
	for line in Tutorial.DONE:
		if line != "":
			_txt_c_fit(vw / 2.0, y, line, COL_TEXT, int(vh * 0.023), vw * 0.92)
		y += vh * 0.04
	y += vh * 0.05
	_button(Rect2(vw * 0.19, y, vw * 0.62, vh * 0.072), "BACK TO MENU", "menu", int(vh * 0.028), COL_GOLD)


func _chip(x: float, ypos: float, icon: String, value: String, vw: float, vh: float, col: Color = COL_TEXT) -> float:
	var isz := vh * 0.032
	var tx := Art.tex(icon, int(isz))
	if tx != null:
		draw_texture(tx, Vector2(x, ypos - isz * 0.78))
	var fsz := int(vh * 0.026)
	_txt(Vector2(x + isz + vw * 0.008, ypos), value, col, fsz)
	return x + isz + vw * 0.008 + font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x + vw * 0.035


func _draw_status(snap: Dictionary, vw: float, vh: float) -> void:
	var pl: Dictionary = snap["player"]
	var pad := _safe_top(vh)
	var row_h := vh * 0.036
	# row 1: vitals left, menu/help buttons right
	var y := pad + row_h * 0.72
	var x := vw * 0.025
	x = _chip(x, y, "ic_hp", "%d/%d" % [pl["hp"], pl["max_hp"]], vw, vh, COL_TEXT if int(pl["hp"]) > 3 else COL_RED)
	if int(pl["shield"]) > 0:
		x = _chip(x, y, "ic_shield", str(pl["shield"]), vw, vh)
	x = _chip(x, y, "ic_charge", "%d" % pl["charge"], vw, vh)
	x = _chip(x, y, "ic_bloom", str(snap["bloom"]), vw, vh)
	var btn_h := row_h * 1.05
	_button(Rect2(vw - vw * 0.095, pad, vw * 0.075, btn_h), "?", "help", int(vh * 0.024))
	_button(Rect2(vw - vw * 0.185, pad, vw * 0.075, btn_h), "=", "menu", int(vh * 0.024))
	# row 2: the sky window - clean jade skies being swallowed by the smoke
	# front as smog rises; suns mark the dim thresholds, the skull marks choke
	var y2 := pad + row_h * 1.35
	var mx := vw * 0.025
	var mh := vh * 0.024
	var fdef: Dictionary = game.floor_def(game.floor_num)
	var choke: float = float(fdef.get("smog_choke", 40))
	var mw := vw * 0.5
	var span := choke * 1.15
	var frac: float = clampf(snap["smog"] / span, 0.0, 1.0)
	_txt(Vector2(mx, y2 + mh + vh * 0.0155), "SKIES", COL_DIM_TEXT, int(vh * 0.0125))
	draw_rect(Rect2(mx, y2, mw, mh), Color("6fae9c"))
	draw_rect(Rect2(mx, y2, mw, mh * 0.45), Color("8cc7ae"))
	draw_circle(Vector2(mx + mw * 0.93, y2 + mh * 0.42), mh * 0.30, Color("f2e4a0"))
	var sw := mw * frac
	if sw > 0.5:
		var tsec := Time.get_ticks_msec() / 1000.0
		var scol := Color("3d3a41")
		draw_rect(Rect2(mx, y2, sw, mh), scol)
		for i in 3:
			var br := mh * (0.42 + 0.16 * float(i % 2))
			var bx := sw + mx + sin(tsec * (1.1 + float(i) * 0.7) + float(i) * 2.1) * mh * 0.22
			var by := y2 + mh * (0.22 + 0.28 * float(i))
			draw_circle(Vector2(bx, by), br, scol)
			draw_circle(Vector2(bx - br * 0.7, by - mh * 0.1), br * 0.7, Color("4a4650"))
	for dv in fdef.get("smog_dim", []):
		var tick := mx + mw * clampf(float(dv) / span, 0.0, 1.0)
		var dsz := int(mh * 1.5)
		var dtx := Art.tex("ic_dim", dsz)
		if dtx != null:
			draw_texture(dtx, Vector2(tick - dsz / 2.0, y2 + (mh - dsz) / 2.0))
	var csz := int(mh * 1.5)
	var ctx := Art.tex("ic_choke", csz)
	if ctx != null:
		draw_texture(ctx, Vector2(mx + mw / 1.15 - csz / 2.0, y2 + (mh - csz) / 2.0))
	draw_rect(Rect2(mx, y2, mw, mh), Color(0, 0, 0, 0.35), false, 1.0)
	if snap["smog"] >= choke:
		var pulse := 0.45 + 0.35 * sin(Time.get_ticks_msec() / 180.0)
		draw_rect(Rect2(mx - 2, y2 - 2, mw + 4, mh + 4), Color(0.88, 0.29, 0.23, pulse), false, 2.0)
	if _threat_tiles(snap).has(pl["pos"]):
		_txt(Vector2(mx + mw + vw * 0.03, y2 + mh), "! INCOMING", COL_RED, int(vh * 0.021))
	var fl := "floor %d/7" % snap["floor"]
	var fsz := int(vh * 0.02)
	var fw := font.get_string_size(fl, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	_txt(Vector2(vw - fw - vw * 0.025, y2 + mh), fl, COL_GOLD, fsz)
	_status_end = pad + row_h * 1.35 + mh + vh * 0.022


func _draw_map(snap: Dictionary, vw: float, vh: float) -> void:
	var m: Dictionary = snap["map"]
	var w: int = m["w"]
	var h: int = m["h"]
	var zone_y := _status_end + vh * 0.004
	var zone_h := vh * Z_MAP_END - zone_y
	var vx0 := 0
	var vy0 := 0
	var vtw := w
	var vth := h
	if zoom_room:
		var vp := _room_view(m)
		vtw = mini(maxi(vp.size.x, 9), w)
		vth = mini(maxi(vp.size.y, 7), h)
		var pp0: Vector2i = game.player["pos"]
		vx0 = clampi(vp.get_center().x - vtw / 2, 0, w - vtw)
		vy0 = clampi(vp.get_center().y - vth / 2, 0, h - vth)
		vx0 = clampi(vx0, maxi(0, pp0.x - vtw + 1), mini(pp0.x, w - vtw))
		vy0 = clampi(vy0, maxi(0, pp0.y - vth + 1), mini(pp0.y, h - vth))
	_vx0 = vx0
	_vy0 = vy0
	_vx1 = vx0 + vtw - 1
	_vy1 = vy0 + vth - 1
	_ts = minf(minf(vw * 0.996 / vtw, zone_h / vth), vw / 8.0)
	_mox = (vw - vtw * _ts) / 2.0 - vx0 * _ts
	_moy = zone_y + (zone_h - vth * _ts) / 2.0 - vy0 * _ts
	if not zoom_room:
		_moy = zone_y  # anchored under the status strip; slack below feeds the log

	for y in range(_vy0, _vy1 + 1):
		for x in range(_vx0, _vx1 + 1):
			var p := Vector2i(x, y)
			var r := _tile_rect(p)
			if m["tiles"][y * w + x] == 1:
				draw_rect(r, COL_FLOOR if (x + y) % 2 == 0 else COL_FLOOR_ALT)
				var hsh := (x * 73856093) ^ (y * 19349663)
				if hsh % 7 == 0:
					var ox := 0.2 + float(hsh % 5) * 0.13
					var oy := 0.25 + float(hsh % 3) * 0.2
					draw_circle(r.position + Vector2(_ts * ox, _ts * oy), _ts * 0.05, COL_MOSS)
					draw_circle(r.position + Vector2(_ts * (ox + 0.11), _ts * (oy + 0.07)), _ts * 0.035, COL_MOSS)
				elif hsh % 11 == 3:
					draw_circle(r.position + Vector2(_ts * 0.7, _ts * 0.6), _ts * 0.04, Color(0.42, 0.47, 0.42))
			else:
				draw_rect(r, COL_WALL)
				# highlight only exposed wall tops, not every wall row
				if y + 1 < h and m["tiles"][(y + 1) * w + x] == 1:
					draw_rect(Rect2(r.position + Vector2(0, _ts * 0.82), Vector2(_ts, _ts * 0.18)), COL_WALL_TOP)
				if y > 0 and m["tiles"][(y - 1) * w + x] == 1:
					draw_rect(Rect2(r.position, Vector2(_ts, maxf(_ts * 0.1, 2))), COL_WALL_TOP)

	# recent events fill whatever space this floor leaves under the map
	var log_top := _moy + (_vy1 + 1) * _ts + vh * 0.012
	var log_space := vh * Z_MAP_END - log_top
	var lfs := int(vh * 0.018)
	var fit := int(log_space / (lfs * 1.4))
	if fit > 0 and not log_lines.is_empty():
		var start: int = maxi(0, log_lines.size() - fit)
		var ly := log_top + lfs
		for i in range(start, log_lines.size()):
			_txt(Vector2(vw * 0.025, ly), log_lines[i], COL_TEXT if i == log_lines.size() - 1 else COL_DIM_TEXT, lfs)
			ly += lfs * 1.4

	for t in snap["terrain"].keys():
		if _vis(t):
			_sprite(snap["terrain"][t]["kind"], t)
	for v in m["vents"]:
		if _vis(v):
			_sprite("vent", v)
	if m["stairs"] != Vector2i(-1, -1) and _vis(m["stairs"]):
		_sprite("stairs", m["stairs"])
		draw_rect(_tile_rect(m["stairs"]).grow(-1), COL_GOLD, false, 3.0)
	if m["shrine"] != Vector2i(-1, -1) and _vis(m["shrine"]):
		_sprite("shrine", m["shrine"])

	for t in _threat_tiles(snap):
		if _vis(t):
			draw_rect(_tile_rect(t), COL_THREAT)

	for e in snap["enemies"]:
		if not _vis(e["pos"]):
			continue
		var ap := _anim_pos(e["id"], e["pos"])
		_shadow_f(ap)
		_sprite_f(e["kind"], ap)
		var r := _tile_rect_f(ap)
		if e.get("elite", false):
			draw_rect(r.grow(-1), COL_GOLD, false, 2.0)
		var edef: Dictionary = Content.ENEMIES[e["kind"]]
		var maxhp: int = int(edef["hp"]) + (Content.ELITE_HP_BONUS if e.get("elite", false) else 0)
		if e["hp"] < maxhp or edef["traits"].has("boss"):
			var frac: float = clampf(float(e["hp"]) / maxf(1.0, float(maxhp)), 0.0, 1.0)
			draw_rect(Rect2(r.position + Vector2(2, -4), Vector2(_ts - 4, 3)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(r.position + Vector2(2, -4), Vector2((_ts - 4) * frac, 3)), COL_RED)

	var pap := _anim_pos("player", snap["player"]["pos"])
	_shadow_f(pap)
	_sprite_f("player", pap)
	var pr := _tile_rect_f(pap)
	draw_rect(pr.grow(1), Color(0.56, 0.86, 0.42, 0.85), false, 2.0)
	if int(snap["player"].get("anchor_turns", 0)) > 0:
		draw_rect(pr.grow(-2), Color("7a5a34"), false, 2.0)
	if int(snap["player"].get("thorns_turns", 0)) > 0:
		draw_rect(pr.grow(-4), Color("57b34a"), false, 1.5)

	# ambient haze drifts across the world once the skies dim
	var dimlvl: int = int(snap["dim"])
	if dimlvl > 0:
		var hz := Rect2(_mox + _vx0 * _ts, _moy + _vy0 * _ts,
			(_vx1 - _vx0 + 1) * _ts, (_vy1 - _vy0 + 1) * _ts)
		var hsec := Time.get_ticks_msec() / 1000.0
		var choked: bool = int(snap["smog"]) >= int(game.floor_def(game.floor_num).get("smog_choke", 40))
		for i in 6:
			var hr := hz.size.x * (0.09 + 0.045 * float(i % 3))
			var spd := 8.0 + 3.5 * float(i % 4)
			var hx := hz.position.x - hr + fposmod(float(i) * hz.size.x * 0.37 + hsec * spd, hz.size.x + hr * 2.0)
			var hy := hz.position.y + hz.size.y * (0.12 + 0.15 * float(i)) + sin(hsec * 0.5 + float(i) * 1.7) * _ts * 0.4
			var hcol := Color(0.55, 0.55, 0.58, minf(0.035 * float(dimlvl), 0.11))
			if choked:
				hcol = Color(0.62, 0.42, 0.38, minf(0.045 * float(dimlvl), 0.13))
			draw_circle(Vector2(hx, hy), hr, hcol)

	if mode == "target_tile":
		for t in mode_targets:
			if _vis(t):
				draw_rect(_tile_rect(t).grow(-1), COL_TARGET, false, 2.5)
	elif mode == "target_dir" or mode == "cleanse":
		for d in DIRS4.values():
			draw_rect(_tile_rect(snap["player"]["pos"] + d).grow(-1), COL_TARGET, false, 2.0)


func _draw_ability_bar(snap: Dictionary, vw: float, vh: float) -> void:
	var pl: Dictionary = snap["player"]
	var n: int = pl["kit"].size()
	var gap := vw * 0.018
	var b := minf(vh * (Z_AB_END - Z_MAP_END) * 0.86, (vw * 0.95 - (n - 1) * gap) / n)
	var total := n * b + (n - 1) * gap
	var x := (vw - total) / 2.0
	var y := vh * Z_MAP_END + (vh * (Z_AB_END - Z_MAP_END) - b) / 2.0
	for i in n:
		var aid: String = pl["kit"][i]
		var adef: Dictionary = Content.ABILITIES[aid]
		var r := Rect2(x, y, b, b)
		var usable: bool = int(pl["charge"]) >= int(adef["cost"]) and not pl["gummed"].has(i)
		var aiming: bool = (mode == "target_dir" or mode == "target_tile") and mode_slot == i
		_box(r, _sb_gold if aiming else _sb)
		var icon := "ab_" + aid.trim_suffix("+")
		if not Art.ART.has(icon):
			icon = "ab_default"
		var isz := int(b * 0.68)
		var tx := Art.tex(icon, isz)
		if tx != null:
			draw_texture(tx, r.position + Vector2((b - isz) / 2.0, b * 0.04), Color(1, 1, 1, 1.0 if usable else 0.32))
		# cost pips
		for c in int(adef["cost"]):
			draw_circle(r.position + Vector2(b * 0.12 + c * b * 0.14, b * 0.88), b * 0.05, COL_GOLD if usable else COL_DIM_TEXT)
		if aid.ends_with("+"):
			_txt(Vector2(r.position.x + b * 0.8, r.position.y + b * 0.24), "+", COL_GOLD, int(b * 0.3))
		if pl["gummed"].has(i):
			_txt_c(r.get_center().x, r.get_center().y + b * 0.12, "GUM %d" % pl["gummed"][i], COL_RED, int(b * 0.22))
		_hot(r, "ability:%d" % i)
		x += b + gap


func _draw_context(snap: Dictionary, vw: float, vh: float) -> void:
	var y := vh * Z_AB_END + (vh * (Z_CTX_END - Z_AB_END)) * 0.62
	var msg := ""
	var col := COL_DIM_TEXT
	match mode:
		"cleanse":
			msg = "CLEANSE: tap corruption beside you (or D-pad)"
			col = COL_TARGET
		"target_dir":
			msg = flash
			col = COL_TARGET
		"target_tile":
			msg = flash
			col = COL_TARGET
		_:
			if flash != "":
				msg = flash
				col = COL_GOLD
			elif screen == "tutorial":
				msg = ""
			elif snap["floor"] == 7:
				msg = "Objective: DESTROY THE BOSS  (tap here for the log)"
			else:
				msg = "Objective: reach the gold-ringed stairs  (tap for log)"
	_txt_fit(Vector2(vw * 0.025, y), msg, col, int(vh * 0.022), vw * 0.95)
	_hot(Rect2(0, vh * Z_AB_END, vw, vh * (Z_CTX_END - Z_AB_END)), "log")


func _draw_controls(snap: Dictionary, vw: float, vh: float) -> void:
	var top := vh * Z_CTX_END
	var zone_h := vh - top
	var b := minf(vw * 0.145, zone_h * 0.3)
	var gap := vw * 0.012
	var dx := vw * 0.035
	var dy := top + (zone_h - (b * 3 + gap * 2)) / 2.0
	_arrow_button(Rect2(dx + b + gap, dy, b, b), "up")
	_arrow_button(Rect2(dx, dy + b + gap, b, b), "left")
	_button(Rect2(dx + b + gap, dy + b + gap, b, b), "END", "end_turn", int(b * 0.28))
	_arrow_button(Rect2(dx + (b + gap) * 2, dy + b + gap, b, b), "right")
	_arrow_button(Rect2(dx + b + gap, dy + (b + gap) * 2, b, b), "down")
	# the D-pad's empty top corners host the view toggles (bottom corners
	# stay free for future features)
	_icon_button(Rect2(dx, dy, b, b), "ic_camera", "zoom", zoom_room)
	_icon_button(Rect2(dx + (b + gap) * 2, dy, b, b), "ic_lens", "inspect", inspect_live)

	var bw := vw * 0.36
	var bx := vw - bw - vw * 0.035
	var bh := zone_h * 0.185
	var by := dy
	if not _legal_of("descend").is_empty():
		_button(Rect2(bx, by, bw, bh), "DESCEND", "descend", int(bh * 0.42), COL_GOLD)
		by += bh + zone_h * 0.03
	elif game.player["pos"] == game.map["shrine"] and not game.shop.is_empty():
		_button(Rect2(bx, by, bw, bh), "SHRINE SHOP", "shop", int(bh * 0.4), COL_GOLD)
		by += bh + zone_h * 0.03
	_button(Rect2(bx, by, bw, bh), "CLEANSE", "cleanse", int(bh * 0.4))
	by += bh + zone_h * 0.03
	_button(Rect2(bx, by, bw, bh), "END TURN", "end_turn", int(bh * 0.42))
	by += bh + zone_h * 0.03
	if screen != "tutorial":
		_txt(Vector2(bx, by + bh * 0.5), "seed %d" % seed_v, COL_DIM_TEXT, int(vh * 0.014))


func _draw_tooltip(vw: float, vh: float) -> void:
	var fsz := int(vh * 0.021)
	for line in tooltip:
		fsz = _fit_size(line, fsz, vw * 0.9)
	var bw := 0.0
	for line in tooltip:
		bw = maxf(bw, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x)
	bw += vw * 0.04
	var lh := fsz * 1.5
	var bh := tooltip.size() * lh + vh * 0.018
	var anchor := Vector2(vw / 2.0, vh * 0.3)
	if tooltip_tile != Vector2i(-1, -1):
		var r := _tile_rect(tooltip_tile)
		anchor = Vector2(r.get_center().x, r.position.y)
	var bx := clampf(anchor.x - bw / 2.0, 6, vw - bw - 6)
	var by := anchor.y - bh - vh * 0.012
	if by < _status_end:
		by = anchor.y + _ts + vh * 0.012
	draw_rect(Rect2(bx, by, bw, bh), Color(0.03, 0.05, 0.04, 0.97))
	draw_rect(Rect2(bx, by, bw, bh), COL_GOLD, false, 1.5)
	var y := by + lh * 0.85
	for i in tooltip.size():
		_txt(Vector2(bx + vw * 0.02, y), tooltip[i], COL_TEXT if i == 0 else COL_DIM_TEXT, fsz)
		y += lh


func _sheet(vw: float, vh: float, title: String) -> float:
	draw_rect(Rect2(0, 0, vw, vh), COL_SHEET)
	_txt(Vector2(vw * 0.06, vh * 0.09), title, COL_GOLD, int(vh * 0.034))
	return vh * 0.16


func _ability_desc(aid: String) -> String:
	return Content.ABILITY_DESC.get(aid.trim_suffix("+"), "")


## A choice card: icon, title with cost, and the effect explained inline -
## the whole card is the tap target, so no extra info taps needed.
func _card(r: Rect2, icon: String, title: String, desc: String, tag: String, vh: float) -> void:
	_box(r, _sb_card)
	var isz := int(r.size.y * 0.62)
	var tx := Art.tex(icon, isz)
	var text_x := r.position.x + r.size.y * 0.28
	if tx != null:
		draw_texture(tx, r.position + Vector2(r.size.y * 0.19, (r.size.y - isz) / 2.0))
		text_x = r.position.x + r.size.y * 1.05
	var max_w := r.position.x + r.size.x - text_x - vh * 0.01
	_txt_fit(Vector2(text_x, r.position.y + r.size.y * 0.42), title, COL_TEXT, int(r.size.y * 0.27), max_w)
	_txt_fit(Vector2(text_x, r.position.y + r.size.y * 0.76), desc, COL_DIM_TEXT, int(r.size.y * 0.2), max_w)
	_hot(r, tag)


func _draw_shop(snap: Dictionary, vw: float, vh: float) -> void:
	hotspots.clear()
	var y := _sheet(vw, vh, "SHRINE SHOP")
	_txt(Vector2(vw * 0.06, y), "your bloom: %d" % snap["bloom"], COL_GOLD, int(vh * 0.026)); y += vh * 0.055
	var ch := vh * 0.105
	if snap["shop"].get("heal", false):
		_card(Rect2(vw * 0.05, y, vw * 0.9, ch), "ic_hp",
			"Heal  —  %d bloom" % game.shop_cost("heal"),
			"Restore 4 HP (up to your maximum)", "buy:heal", vh)
		y += ch + vh * 0.022
	if snap["shop"].has("ability"):
		var aid: String = snap["shop"]["ability"]
		var icon := "ab_" + aid.trim_suffix("+")
		if not Art.ART.has(icon):
			icon = "ab_default"
		_card(Rect2(vw * 0.05, y, vw * 0.9, ch), icon,
			"%s  —  %d bloom" % [Content.ABILITIES[aid]["name"], game.shop_cost("ability")],
			_ability_desc(aid), "buy:ability", vh)
		y += ch + vh * 0.022
	if snap["shop"].has("graft"):
		var gid: String = snap["shop"]["graft"]
		_card(Rect2(vw * 0.05, y, vw * 0.9, ch), "shrine",
			"%s  —  %d bloom" % [Content.GRAFTS[gid]["name"], game.shop_cost("graft")],
			"Graft (permanent): %s" % Content.GRAFTS[gid]["desc"], "buy:graft", vh)
		y += ch + vh * 0.022
	y += vh * 0.04
	_button(Rect2(vw * 0.25, y, vw * 0.5, vh * 0.07), "CLOSE", "close", int(vh * 0.026))


func _draw_logsheet(vw: float, vh: float) -> void:
	hotspots.clear()
	var y := _sheet(vw, vh, "EVENT LOG  (tap to close)")
	var fsz := int(vh * 0.021)
	var start: int = maxi(0, log_lines.size() - 28)
	for i in range(start, log_lines.size()):
		_txt(Vector2(vw * 0.06, y), log_lines[i], COL_TEXT if i == log_lines.size() - 1 else COL_DIM_TEXT, fsz)
		y += fsz * 1.45


func _draw_draft(snap: Dictionary, vw: float, vh: float) -> void:
	hotspots.clear()
	var y := _sheet(vw, vh, "DESCENT DRAFT")
	_txt_fit(Vector2(vw * 0.06, y), "Choose one ability to take down with you:", COL_TEXT, int(vh * 0.024), vw * 0.88); y += vh * 0.055
	var bh := vh * 0.105
	if mode != "draft_drop":
		for i in snap["draft_offers"].size():
			var aid: String = snap["draft_offers"][i]
			var adef: Dictionary = Content.ABILITIES[aid]
			var icon := "ab_" + aid.trim_suffix("+")
			if not Art.ART.has(icon):
				icon = "ab_default"
			var up := "  (upgrade)" if aid.ends_with("+") else ""
			_card(Rect2(vw * 0.05, y, vw * 0.9, bh), icon,
				"%s  —  %d charge%s" % [adef["name"], adef["cost"], up],
				_ability_desc(aid), "draft:%d" % i, vh)
			y += bh + vh * 0.02
		y += vh * 0.015
		_button(Rect2(vw * 0.25, y, vw * 0.5, bh * 0.65), "skip - take nothing", "skip_draft", int(bh * 0.24))
	else:
		_txt_fit(Vector2(vw * 0.06, y), "Kit is full - tap what to DROP for it:", COL_RED, int(vh * 0.024), vw * 0.88); y += vh * 0.05
		for i in snap["player"]["kit"].size():
			var kid: String = snap["player"]["kit"][i]
			var kicon := "ab_" + kid.trim_suffix("+")
			if not Art.ART.has(kicon):
				kicon = "ab_default"
			_card(Rect2(vw * 0.05, y, vw * 0.9, bh), kicon,
				Content.ABILITIES[kid]["name"], _ability_desc(kid), "drop:%d" % i, vh)
			y += bh + vh * 0.02
		y += vh * 0.02
		_button(Rect2(vw * 0.25, y, vw * 0.5, bh * 0.65), "BACK", "draft_back", int(bh * 0.26))


func _draw_over(snap: Dictionary, vw: float, vh: float) -> void:
	hotspots.clear()
	draw_rect(Rect2(0, 0, vw, vh), COL_SHEET)
	var won: bool = snap["won"]
	_txt_c(vw / 2.0, vh * 0.3, "THE FURNACE IS COLD" if won else "YOU DIED", COL_GOLD if won else COL_RED, int(vh * 0.042))
	_txt_c(vw / 2.0, vh * 0.37, "the valley breathes again" if won else "cause: %s" % snap["death_cause"], COL_TEXT, int(vh * 0.024))
	_txt_c(vw / 2.0, vh * 0.46, "floor %d · turn %d · bloom %d" % [snap["floor"], snap["turn"], snap["bloom"]], COL_TEXT, int(vh * 0.024))
	_txt_c(vw / 2.0, vh * 0.51, "seed %d" % seed_v, COL_DIM_TEXT, int(vh * 0.02))
	_txt_c(vw / 2.0, vh * 0.62, "- tap anywhere for a new run -", COL_GOLD, int(vh * 0.026))
	_button(Rect2(vw * 0.3, vh * 0.72, vw * 0.4, vh * 0.06), "MENU", "menu", int(vh * 0.024))


func _draw_intro(vw: float, vh: float) -> void:
	hotspots.clear()
	draw_rect(Rect2(0, 0, vw, vh), COL_SHEET)
	var x := vw * 0.07
	var y := vh * 0.1
	_txt(Vector2(x, y), "TENDER", COL_GOLD, int(vh * 0.05)); y += vh * 0.07
	for pair in [
		["The combine poisoned the world. You are a Tender.", COL_TEXT],
		["Descend all 7 floors and shut down the Furnace.", COL_TEXT],
		["", COL_TEXT],
		["MOVE with the D-pad, or tap a tile next to you.", COL_TEXT],
		["Move into an enemy to attack it.", COL_TEXT],
		["RED tiles are incoming damage. Stay off them.", COL_TEXT],
		["The GOLD-RINGED stairs are the way down.", COL_TEXT],
		["", COL_TEXT],
		["Move fast: smog rises every turn, and deep smog kills.", COL_GOLD],
		["", COL_TEXT],
		["CLEANSE oil and goo for bloom; spend it at shrines.", COL_TEXT],
		["Green growth heals you while you stand on it.", COL_TEXT],
		["", COL_TEXT],
		["HOLD your finger on anything to see what it is.", COL_GOLD],
	]:
		if pair[0] != "":
			_txt_fit(Vector2(x, y), pair[0], pair[1], int(vh * 0.0235), vw * 0.88)
		y += vh * 0.037
	y += vh * 0.04
	_txt_c(vw / 2.0, y, "- tap to begin -", COL_GOLD, int(vh * 0.03))


const HELP_PAGE_SIZE := 13


func _help_pages() -> int:
	return int(ceil(LEGEND.size() / float(HELP_PAGE_SIZE)))


func _draw_help(vw: float, vh: float) -> void:
	hotspots.clear()
	var pages := _help_pages()
	var next_hint := "tap for more" if help_page < pages - 1 else "tap to close"
	var y := _sheet(vw, vh, "LEGEND  %d/%d  (%s)" % [help_page + 1, pages, next_hint])
	var start := help_page * HELP_PAGE_SIZE
	var count := mini(HELP_PAGE_SIZE, LEGEND.size() - start)
	var row_h := (vh - y - vh * 0.03) / HELP_PAGE_SIZE
	for i in count:
		var row: Array = LEGEND[start + i]
		var yy := y + i * row_h
		var isz := int(minf(row_h * 0.72, vh * 0.038))
		var tx := Art.tex(row[0], isz)
		if tx != null:
			draw_texture(tx, Vector2(vw * 0.05, yy))
		var text_x := vw * 0.05 + isz * 1.35
		_txt_fit(Vector2(text_x, yy + row_h * 0.38), row[1], COL_TEXT, int(minf(vh * 0.023, row_h * 0.34)), vw * 0.95 - text_x)
		_txt_fit(Vector2(text_x, yy + row_h * 0.76), row[2], COL_DIM_TEXT, int(minf(vh * 0.0165, row_h * 0.27)), vw * 0.95 - text_x)
