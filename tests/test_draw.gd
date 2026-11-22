extends SceneTree
## Draw smoke test: the ONLY test that runs the shell's _draw code. Every
## other shell test calls the input and layout functions headless and never
## renders a frame, so a draw-time error (a font size that reaches 0, a bad
## index in a badge table, a null texture, a type error in the vignette)
## would only ever show up on a phone. This hosts shell/main.gd inside a
## SubViewport that renders every frame, at several real phone and desktop
## sizes, and drives real frames through every screen the shell draws: the
## menu and settings, the career menu (NEW / WON badges) and the DAILY sheet,
## tutorial steps, an optimizer game played through _act
## with tooltips raised on every enemy, vent and the tender, a lethal state
## (vignette, outline, guard flash, escape glow), a danger board (tether, gum
## slots, SKIES chips), a kill (ghost, kill weight, streak flame), the boss
## floor (core shield ring up and down, a phase banner), the shrine, forge,
## draft and drop sheets, the log, help pages and intro, and the end of a run:
## both game-over sheets set from outside, the end beat (a smog death through
## _act, and a first win), the sheet fading in locked, the live sheet with its
## unlock rows, and a tutorial death. Each phase asserts it reached the state
## its draw code needs.
##
## Gate: an OS Logger counts every engine error, push_error and SCRIPT ERROR
## raised while it runs; any one fails the test (exit 1).
## Run: godot --headless --path . --script tests/test_draw.gd
##
## Nothing real is written: the shell reads and saves its career at a scratch
## profile_path, its run save at a scratch run_save_path (both set before
## _ready, which loads the one and restores the other), the run save handle is
## closed at once and _game_is_run stays false (so no run is recorded and no
## log archived), runs_dir points at scratch too, and SHELL_SEED is cleared so
## _ready never starts a run. The settings live at a scratch cfg_path too:
## the DAILY tap saves them once when a legacy seed_mode notice is pending, and
## the player's own tender.cfg must neither steer nor absorb a test run.

const Shell := preload("res://shell/main.gd")
const Game := preload("res://sim/game.gd")
const Content := preload("res://sim/content.gd")
const Tutorial := preload("res://shell/tutorial.gd")
const Danger := preload("res://shell/danger.gd")
const Names := preload("res://shell/names.gd")
const Feedback := preload("res://shell/feedback.gd")
const Roster := preload("res://bots/roster.gd")
const Profile := preload("res://meta/profile.gd")

const ShellTest := preload("res://tests/test_shell.gd")

## Four named phone/desktop shapes, then every shape the card gate sweeps
## (tests/test_shell.gd CARD_VIEWPORTS), so a size the cards are held to is a
## size the whole screen is drawn at.
const NAMED_VIEWPORTS := [Vector2i(1080, 2400), Vector2i(720, 1600), Vector2i(1440, 3200), Vector2i(1920, 1080)]
const SCRATCH_PROFILE := "user://test_draw_profile.json"
const SCRATCH_RUNS := "user://test_draw_runs"
const SCRATCH_RUN_SAVE := "user://test_draw_run.save"
const SCRATCH_CFG := "user://test_draw_settings.cfg"
## optimizer actions on the first viewport, then on every other one (the
## first sweep is the long one; the rest re-check the same draw paths at
## their own sizes)
const BOT_ACTIONS_FIRST := 300
const BOT_ACTIONS_REST := 90
const FULL_KIT := ["solar_lance", "seed_bomb", "mycelium_dash", "vine_whip", "thorn_shield"]


## Counts every error the engine reports while the test runs.
class ErrorCounter extends Logger:
	var errors := 0
	var warnings := 0
	var first: Array = []
	var _mx := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mx.lock()
		if error_type == ERROR_TYPE_WARNING:
			warnings += 1
		else:
			errors += 1
			if first.size() < 20:
				first.append("%s:%d %s: %s %s" % [file, line, function, code, rationale])
		_mx.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


var log_counter := ErrorCounter.new()
var VIEWPORTS: Array = []
var vp: SubViewport
var sh
var vi := -1            # current viewport index
var phases: Array = []  # [{name, setup, frames, each, check}]
var pi := -1
var left := 0           # frames left in the current phase
var frames := 0
var draws := 0
var phase_draws := 0
var fails: Array = []
var fx_seen := {}
var lethal_frames := 0
var tips := 0
## tooltips aimed at an enemy or the tender, and how many came back naming it
var entity_tips := 0
var enemy_tips := 0
var tender_tips := 0
var tip_misses: Array = []
var tips_filled_at := -1
var bot
var bot_left := 0
var tip_queue: Array = []
var t_start := 0


func _initialize() -> void:
	OS.add_logger(log_counter)
	OS.set_environment("SHELL_SEED", "")  # else _ready starts (and saves) a run
	t_start = Time.get_ticks_msec()
	VIEWPORTS = NAMED_VIEWPORTS.duplicate()
	for v in ShellTest.CARD_VIEWPORTS:
		var vv := Vector2i(int(v.x), int(v.y))
		if not VIEWPORTS.has(vv):
			VIEWPORTS.append(vv)
	# the first shell is built on the first frame, once the tree is running
	# (a node added during _initialize has not had its _ready yet)


func _fail(msg: String) -> void:
	fails.append("[%dx%d %s] %s" % [VIEWPORTS[vi].x, VIEWPORTS[vi].y,
		String(phases[pi]["name"]) if pi >= 0 and pi < phases.size() else "-", msg])


func _next_viewport() -> bool:
	if sh != null:
		sh.queue_free()
		sh = null
	if vp != null:
		vp.queue_free()
		vp = null
	vi += 1
	if vi >= VIEWPORTS.size():
		return false
	vp = SubViewport.new()
	vp.size = VIEWPORTS[vi]
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	sh = Shell.new()
	sh.profile_path = SCRATCH_PROFILE  # before _ready (add_child): it loads from here
	sh.runs_dir = SCRATCH_RUNS
	sh.run_save_path = SCRATCH_RUN_SAVE  # before _ready too: it restores (or deletes) a save it finds
	sh.cfg_path = SCRATCH_CFG  # ...and its settings: boots on the defaults, saves nothing real
	DirAccess.remove_absolute(SCRATCH_CFG)
	vp.add_child(sh)
	# silent: a sound still playing when the shell is freed leaks its playback
	# at exit (engine cleanup noise, not a draw fault), and nothing here listens
	sh.audio.sfx_on = false
	sh.audio.set_music(false)
	if sh._run_save != null:
		sh._run_save.close()
		sh._run_save = null
	sh._game_is_run = false
	sh.draw.connect(func(): draws += 1)
	phases = _build_phases()
	pi = -1
	_next_phase()
	return true


func _next_phase() -> bool:
	pi += 1
	if pi >= phases.size():
		return false
	var ph: Dictionary = phases[pi]
	sh.queue_redraw()
	phase_draws = draws
	phase_arg = ph["arg"]
	call(String(ph["setup"]))
	left = int(ph["frames"])
	sh.queue_redraw()
	return true


func _end_phase() -> void:
	var ph: Dictionary = phases[pi]
	if draws == phase_draws:
		_fail("no frame was drawn")
	if String(ph["check"]) != "":
		var why: String = call(String(ph["check"]))
		if why != "":
			_fail(why)


func _process(_dt: float) -> bool:
	if vi < 0:
		_next_viewport()
		return false
	frames += 1
	# what the frame that just rendered showed
	if sh != null and sh.game != null:
		for f in sh._fx:
			fx_seen[String(f["kind"])] = true
	if left > 0:
		var ph: Dictionary = phases[pi]
		if String(ph["each"]) != "":
			call(String(ph["each"]))
		left -= 1
		sh.queue_redraw()
		return false
	_end_phase()
	if _next_phase():
		return false
	if _next_viewport():
		return false
	return _finish()


func _finish() -> bool:
	OS.remove_logger(log_counter)
	DirAccess.remove_absolute(SCRATCH_PROFILE)
	DirAccess.remove_absolute(SCRATCH_PROFILE + ".tmp")
	DirAccess.remove_absolute(SCRATCH_RUN_SAVE)
	DirAccess.remove_absolute(SCRATCH_CFG)
	var ms := Time.get_ticks_msec() - t_start
	if not fx_seen.has("callout") or not fx_seen.has("ghost"):
		fails.append("the frames never held a live callout and a ghost (%s)" % str(fx_seen.keys()))
	for f in fails:
		print("FAIL: " + f)
	if log_counter.errors > 0:
		print("draw smoke: %d engine/script error(s), first %d:" % [log_counter.errors, log_counter.first.size()])
		for m in log_counter.first:
			print("  " + m)
	if fails.is_empty() and log_counter.errors == 0:
		print("draw smoke: OK (%d frames, %d viewports, 0 errors) - %d draws, %d tooltips (%d enemy, %d tender), %d lethal frames, fx %s, %.1fs" % [
			frames, VIEWPORTS.size(), draws, tips, enemy_tips, tender_tips, lethal_frames, str(fx_seen.keys()), ms / 1000.0])
		quit(0)
	else:
		print("draw smoke: FAILED (%d frames, %d viewports, %d errors, %d failed checks)" % [
			frames, VIEWPORTS.size(), log_counter.errors, fails.size()])
		quit(1)
	return true


# --- fixtures -------------------------------------------------------------------

## A fresh game the shell plays, with nothing recorded and nothing written.
func _play(g) -> void:
	sh.game = g
	sh.screen = "game"
	sh.mode = "normal"
	sh._game_is_run = false
	sh.tooltip = []
	sh.flash = ""
	sh._new_stats()
	sh._reset_feedback()
	sh._reset_danger()


func _open_dirs(g) -> Array:
	var out: Array = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if g._open(g.player["pos"] + d):
			out.append(d)
	return out


## Game 4242, every enemy and all terrain cleared, smog 0.
func _bare_game(cfg: Dictionary = {}):
	var g = Game.new(4242, cfg)
	g.terrain.clear()
	g.enemies.clear()
	g.smog = 0
	return g


## The screen point at the centre of map tile `t` (valid after one frame).
func _tile_px(t: Vector2i) -> Vector2:
	return Vector2(sh._mox + (t.x + 0.5) * sh._ts, sh._moy + (t.y + 0.5) * sh._ts)


## Raise the tooltip on tile `t`. `want` is what its first line must start
## with when the tip was aimed at an enemy (its name) or the tender ("You - "):
## a miss means the tip landed on a board that no longer has them there.
func _raise_tip(t: Vector2i, want := "") -> void:
	sh.tooltip = []
	sh._show_tooltip(_tile_px(t))
	tips += 1
	if want == "":
		return
	entity_tips += 1
	var head: String = String(sh.tooltip[0]) if not sh.tooltip.is_empty() else ""
	if not head.begins_with(want):
		tip_misses.append("%s at %s: '%s'" % [want, str(t), head])
	elif want == "You - ":
		tender_tips += 1
	else:
		enemy_tips += 1


func _has_fx(kind: String) -> bool:
	for f in sh._fx:
		if String(f["kind"]) == kind:
			return true
	return false


# --- the phases -------------------------------------------------------------------

## Each phase: [name, frames, setup, check, each, arg] - method names on this
## script ("" = none); `arg` reaches setup through `phase_arg`.
func _build_phases() -> Array:
	var rows: Array = [
		["menu", 3, "_menu_setup", "_menu_check", "", null],
		["settings", 2, "_settings_setup", "_settings_check", "", null],
		["menu (career badges)", 3, "_menu_badges_setup", "_menu_badges_check", "", null],
		["daily sheet", 2, "_daily_setup", "_daily_check", "", false],
		["daily sheet (finished)", 2, "_daily_setup", "_daily_check", "", true],
		["tutorial", 8, "_tutorial_setup", "_tutorial_check", "_tutorial_step", null],
		["tutorial done", 2, "_tutorial_done_setup", "_tutorial_done_check", "", null],
		["bot game", 100000, "_bot_setup", "_bot_check", "_bot_each", null],
		["lethal", 4, "_lethal_setup", "_lethal_check", "_lethal_each", null],
		["danger board", 3, "_danger_board_setup", "_danger_board_check", "", null],
		["kill", 3, "_kill_setup", "_kill_check", "", null],
		["boss shield up", 3, "_boss_setup", "_boss_check_up", "", null],
		["boss shield down", 3, "_boss_drop_shield", "_boss_check_down", "", null],
		["shrine sheet", 3, "_shop_setup", "_mode_check", "", "shop"],
		["forge keep", 2, "_forge_keep", "_mode_check", "", "up_keep"],
		["forge scrap", 2, "_forge_scrap", "_mode_check", "", "up_scrap"],
		["forge variant", 2, "_forge_variant", "_mode_check", "", "up_variant"],
		["forged", 2, "_forge_pick", "_forged_check", "", null],
		["draft sheet", 3, "_draft_setup", "_draft_check", "", null],
		["drop sheet", 3, "_drop_setup", "_mode_check", "", "draft_drop"],
		["drafted", 2, "_drop_pick", "_drafted_check", "", null],
		["log sheet", 2, "_sheet_setup", "_mode_check", "", "log"],
		["help page 0", 2, "_help_setup", "_help_check", "", 0],
		["help page 1", 2, "_help_setup", "_help_check", "", 1],
		["help page 2", 2, "_help_setup", "_help_check", "", 2],
		["help page 3", 2, "_help_setup", "_help_check", "", 3],
		["intro", 2, "_sheet_setup", "_mode_check", "", "intro"],
		["game over (died)", 3, "_over_setup", "_over_check", "", false],
		["game over (won)", 3, "_over_setup", "_over_check", "", true],
		["end beat (died)", 3, "_beat_setup", "_beat_check", "", false],
		["over sheet (fading, locked)", 2, "_fade_setup", "_fade_check", "", null],
		["over sheet (recorded, live)", 2, "_live_setup", "_live_check", "", null],
		["end beat (won)", 3, "_beat_setup", "_beat_check", "", true],
		["over sheet (first win)", 2, "_live_setup", "_live_check", "", null],
		["tutorial death sheet", 2, "_tut_death_setup", "_tut_death_check", "", null],
	]
	var out: Array = []
	for r in rows:
		out.append({"name": r[0], "frames": r[1], "setup": r[2], "check": r[3], "each": r[4], "arg": r[5]})
	return out


var phase_arg = null


func _menu_setup() -> void:
	sh.screen = "menu"
	sh.mode = "normal"


func _menu_check() -> String:
	if sh.screen != "menu":
		return "not on the menu"
	if sh.hotspots.is_empty():
		return "the menu frame laid out no buttons (did _draw run?)"
	return ""


func _settings_setup() -> void:
	sh.mode = "settings"


func _settings_check() -> String:
	return "" if sh.mode == "settings" else "settings sheet not up"


func _tutorial_setup() -> void:
	if saved_profile != null:
		sh.profile = saved_profile  # the career phases above lent the shell a profile
		saved_profile = null
	sh.mode = "normal"
	sh._start_tutorial()


## The menu with everything a career puts on it: a NEW badge on every cycler,
## a WON badge on the loadout, a named difficulty, the footer, the legacy
## daily notice. The profile is a stand-in (never saved: nothing here cycles
## a row, which is the only path that writes it).
var saved_profile = null


func _career_profile():
	var p = Profile.new()
	p.runs = 12
	p.wins = 2
	p.best_floor = 7
	p.unlocked_tier = 2
	p.unlocked_packages = ["mycology", "aeolian"]
	p.unlocked_mutators = ["brittle", "spinning_shrine"]
	p.unlocked_loadouts = ["tidewarden", "skyrunner"]
	p.unseen = ["tier:2", "aeolian", "spinning_shrine", "skyrunner"]
	p.records["loadouts"]["tender"] = p._loadout_rec(7, 1200, 1, 10, 2)
	return p


func _menu_badges_setup() -> void:
	if saved_profile == null:
		saved_profile = sh.profile
	sh.profile = _career_profile()
	sh.screen = "menu"
	sh.mode = "normal"
	sh.sel_tier = 2
	sh.sel_loadout = "tender"
	sh._legacy_notice = true


func _menu_badges_check() -> String:
	var why := _menu_check()
	if why != "":
		return why
	var badges := 0
	for row in sh._menu_rows():
		if String(row[3]) != "":
			badges += 1
	return "" if badges >= 4 else "the career menu drew only %d badges" % badges


## The DAILY sheet, unplayed (arg false) and finished with a streak (true).
func _daily_setup() -> void:
	sh._legacy_notice = false
	sh.screen = "menu"
	sh._tap("daily")
	if bool(phase_arg):
		var today: int = sh._daily_seed()
		sh.profile.note_daily_try(today)
		sh.profile.record_daily({"won": true, "floor": 7, "turns": 140, "seed": today})
		sh._refresh_daily_info()


func _daily_check() -> String:
	if sh.mode != "daily":
		return "daily sheet not up (%s)" % sh.mode
	for h in sh.hotspots:
		if String(h["tag"]) == "daily_play":
			return ""
	return "the daily sheet laid out no PLAY button"


func _tutorial_check() -> String:
	return "" if sh.screen == "tutorial" and sh.tut_step >= 2 else "the tutorial did not advance (step %d)" % sh.tut_step


func _tutorial_done_setup() -> void:
	sh.tut_done = true


func _tutorial_done_check() -> String:
	return "" if sh.tut_done else "tutorial not done"


func _bot_check() -> String:
	if tips == 0:
		return "no tooltip was raised"
	if not tip_misses.is_empty():
		return "%d of %d enemy/tender tooltips missed their tile (%s)" % [
			tip_misses.size(), entity_tips, str(tip_misses.slice(0, 3))]
	if enemy_tips == 0 or tender_tips == 0:
		return "the bot game raised %d enemy and %d tender tooltips (need both)" % [enemy_tips, tender_tips]
	if sh.game.total_turns < 10:
		return "the bot game barely moved (%d turns)" % sh.game.total_turns
	return ""


func _lethal_each() -> void:
	if bool(sh._danger_state().get("lethal", false)):
		lethal_frames += 1


func _kill_check() -> String:
	return "" if fx_seen.has("ghost") else "the kill left no ghost"


func _boss_check_up() -> String:
	return _boss_check(true)


func _boss_check_down() -> String:
	return _boss_check(false)


func _mode_check() -> String:
	return "" if sh.mode == String(phase_arg) else "mode %s not reached (%s)" % [str(phase_arg), sh.mode]


func _forge_keep() -> void:
	sh._tap("forge")


func _forge_scrap() -> void:
	sh._ability_press(0)


func _forge_variant() -> void:
	sh._ability_press(1)


func _forge_pick() -> void:
	sh._tap("forgevar:1")


func _forged_check() -> String:
	if sh.mode == "up_variant" or not Content.is_upgrade(String(sh.game.player["kit"][0])):
		return "the fork did not forge (%s, %s)" % [sh.mode, str(sh.game.player["kit"])]
	return ""


func _draft_check() -> String:
	return "" if sh.game.phase == "draft" else "no draft (%s)" % sh.game.phase


func _drop_setup() -> void:
	sh._draft_pick(0)


func _drop_pick() -> void:
	sh._draft_key(KEY_2)


func _drafted_check() -> String:
	return "" if sh.game.phase == "play" else "the drop did not resolve the draft (%s)" % sh.game.phase


func _sheet_setup() -> void:
	sh.mode = String(phase_arg)


func _help_setup() -> void:
	sh.mode = "help"
	sh.help_page = int(phase_arg)


func _help_check() -> String:
	return "" if sh.mode == "help" and sh._help_pages() == 4 else "help page %s not up" % str(phase_arg)


func _over_check() -> String:
	return "" if sh.game.over and sh.game.won == bool(phase_arg) else "not over as wanted"


func _tutorial_step() -> void:
	if sh.tut_done:
		return
	var st: Dictionary = Tutorial.STEPS[sh.tut_step]
	for a in sh.game.legal_actions():
		if Tutorial.matches(st, a):
			sh._act(a)
			return
	if bool(st.get("allow_nav", false)):
		for a in sh.game.legal_actions():
			if String(a.get("type", "")) in ["move", "end_turn"]:
				sh._act(a)
				return


func _bot_setup() -> void:
	sh.screen = "game"
	var seed_v := 3 + vi
	_play(Game.new(seed_v, {"loadout": "flarekeeper", "grafts": ["ember_sap", "compost"]}))
	bot = Roster.make("optimizer", seed_v)
	if bot.has_method("set_sim"):
		bot.set_sim(sh.game)
	bot_left = BOT_ACTIONS_FIRST if vi == 0 else BOT_ACTIONS_REST
	tip_queue = []
	tips_filled_at = -1


## One frame of the bot game: a queued tooltip, else one action through _act
## (every 25 actions the tooltip queue refills with every enemy, vent and the
## tender, so each is raised and drawn at least once on the way).
func _bot_each() -> void:
	if sh.game.over or bot_left <= 0:
		left = 0
		return
	if not tip_queue.is_empty():
		var q: Array = tip_queue.pop_front()
		_raise_tip(q[0], q[1])
		return
	sh.tooltip = []
	if bot_left % 25 == 0 and tips_filled_at != bot_left and sh.game.phase == "play":
		# queue them and act only once they have drained, so every tip is
		# raised on the board it was aimed at (not one action later)
		tips_filled_at = bot_left
		for e in sh.game.enemies:
			tip_queue.append([Vector2i(e["pos"]), Names.ename(e["kind"])])
		for v in sh.game.map["vents"]:
			tip_queue.append([Vector2i(v), ""])
		tip_queue.append([Vector2i(sh.game.player["pos"]), "You - "])
		return
	if bool(sh._danger_state().get("lethal", false)):
		lethal_frames += 1
	sh.mode = "normal"
	sh._act(bot.choose_action(sh.game.snapshot(), sh.game.legal_actions()))
	bot_left -= 1


## Lethal: a drill bot strikes for 3 at 2 HP, no charge, a balm fruit that
## saves - the vignette, the lethal outline, the guard's red flash and the
## satchel's escape glow all draw.
func _lethal_setup() -> void:
	var g = _bare_game()
	var dirs := _open_dirs(g)
	var a: Dictionary = g._spawn("drill_bot", g.player["pos"] + dirs[0])
	a["intent"] = {"type": "attack", "tile": g.player["pos"], "dmg": 3}
	g.player["charge"] = 0
	g.player["hp"] = 2
	g.player["items"] = ["balm_fruit"]
	_play(g)
	sh._dir_input(dirs[1])  # a dry press: the guard refuses it with the reason


func _lethal_check() -> String:
	var dz: Dictionary = sh._danger_state()
	if not bool(dz.get("lethal", false)):
		return "the fixture is not lethal"
	if String(dz.get("hp", "")) != "lethal":
		return "the HP state is not lethal (%s)" % str(dz.get("hp"))
	if not (sh._flash_red and String(sh.flash).begins_with("LETHAL")):
		return "the guard flash is not up (%s)" % sh.flash
	if dz.get("escapes", {}).get("item", []) != [0]:
		return "the balm fruit is not the glowing escape (%s)" % str(dz.get("escapes"))
	return ""


## Danger board: a grapple (tether), a tar spitter's gum (gum slot), the
## choke in the amber window (SKIES chips + bar alert) and a vent countdown.
func _danger_board_setup() -> void:
	var g = _bare_game()
	var pp: Vector2i = g.player["pos"]
	var dl := Vector2i.ZERO
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if g._open(pp + d) and g._open(pp + d * 2) and g._open(pp + d * 3):
			dl = d
			break
	var crane: Dictionary = g._spawn("magnet_crane", pp + dl * 3)
	crane["intent"] = {"type": "drag"}
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if d != dl and g._open(pp + d * 2):
			var sp: Dictionary = g._spawn("tar_spitter", pp + d * 2)
			sp["intent"] = {"type": "gum", "slot": 1}
			break
	# raise the smog until the skies bar alerts AND a vent counts down on the map
	g.smog = int(g.floor_def(1)["smog_choke"]) - 3
	for i in 20:
		var sky: Dictionary = g.smog_forecast(Danger.SKY_HORIZON, true)
		if Danger.sky_alert(sky) != "" and not Danger.vent_marks(g.snapshot(), sky).is_empty():
			break
		g.smog += 1
	_play(g)
	_raise_tip(pp + dl * 3)


func _danger_board_check() -> String:
	var dz: Dictionary = sh._danger_state()
	var pp: Vector2i = sh.game.player["pos"]
	if Danger.tethers(dz["tele"], pp).is_empty():
		return "no tether"
	if Danger.gum_slots(sh.game.snapshot(), dz["tele"]).is_empty():
		return "no gum slot"
	if Danger.sky_alert(dz["sky"]) == "" or Danger.sky_chips(dz["sky"]).is_empty():
		return "the skies bar is not alerting (%s)" % str(dz["sky"])
	if Danger.vent_marks(sh.game.snapshot(), dz["sky"]).is_empty():
		return "no vent countdown on the map (%s)" % str(dz["sky"])
	if sh.tooltip.is_empty():
		return "the crane's tooltip did not rise"
	return ""


## A kill through _act: a 1-HP drill bot struck down beside the tender, with a
## two-turn streak standing so the flame draws too.
func _kill_setup() -> void:
	var g = _bare_game()
	var dirs := _open_dirs(g)
	var e: Dictionary = g._spawn("drill_bot", g.player["pos"] + dirs[0])
	e["hp"] = 1
	e["intent"] = {"type": "idle"}
	g.player["charge"] = 3
	_play(g)
	sh.stats.streak_closed = 3
	sh._act({"type": "strike", "dir": dirs[0]})
	if not _has_fx("ghost"):
		_fail("the kill made no ghost fx (%s)" % str(sh._fx.map(func(f): return f["kind"])))


var _boss: Dictionary = {}
var _goo := Vector2i(-1, -1)


## Floor 7 with the boss beside the tender at its gate HP and goo beside it:
## the core shield ring draws; a strike floats SHIELDED; a phase banner.
func _boss_setup() -> void:
	var g = Game.new(3)
	g._enter_floor(7)
	g.terrain.clear()
	_boss = {}
	for e in g.enemies.duplicate():
		if Content.ENEMIES[e["kind"]]["traits"].has("boss"):
			_boss = e
		else:
			g.enemies.erase(e)
	var dirs := _open_dirs(g)
	_boss["pos"] = g.player["pos"] + dirs[0]
	_boss["hp"] = int(Content.ENEMIES[_boss["kind"]].get("gate_hp", 6))
	_boss["intent"] = {"type": "idle"}
	_goo = Vector2i(-1, -1)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var t: Vector2i = _boss["pos"] + d
		if t != g.player["pos"] and g._open(t):
			_goo = t
			break
	g.terrain[_goo] = {"kind": "goo"}
	g.player["charge"] = 3
	_play(g)
	sh._act({"type": "strike", "dir": dirs[0]})
	sh._feedback([{"t": "boss_phase", "phase": 2}], sh._pre_step(), {})


func _boss_drop_shield() -> void:
	var g = sh.game
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var t: Vector2i = _boss["pos"] + d
		if t != g.player["pos"] and t != _goo and g._open(t):
			g.terrain[t] = {"kind": "growth"}
			break
	sh._danger_rev += 1


func _boss_check(up: bool) -> String:
	if sh.game.floor_num != 7 or not sh.game.enemies.has(_boss):
		return "not on the boss floor with its boss"
	if sh.game.core_shield_up(int(_boss["id"])) != up:
		return "the core shield is not %s" % ("up" if up else "down")
	if up and sh._banner.is_empty() and sh._banner_q.is_empty():
		return "no boss phase banner"
	return ""


## The shrine sheet under spinning_shrine (the reroll card draws too).
func _shop_setup() -> void:
	var g = Game.new(4242, {"bloom": 40, "mutators": ["spinning_shrine"]})
	g.player["pos"] = g.map["shrine"]
	_play(g)
	sh._tap("shop")


## A descent into a draft with a full kit, so a pick opens the drop sheet.
func _draft_setup() -> void:
	var g = Game.new(4242, {"kit": FULL_KIT})
	g.player["pos"] = g.map["stairs"]
	g.greened = g.green_need
	_play(g)
	sh._act({"type": "descend"})


func _over_setup() -> void:
	var won := bool(phase_arg)
	var g = Game.new(4242, {})
	g.over = true
	g.won = won
	g.death_cause = "drill_bot"
	_play(g)  # set over from outside _act: no beat, the sheet at once, unrecorded


## The end of a run through the real path. Died: a smog death through _act on
## a recorded career run (a fresh profile, so the sheet carries a score, a best
## line and a NEXT goal) - the beat starts. Won: a first win filed through
## _record_finished_run, then the beat started by hand (no headless recipe
## wins through _act in one step), so the sheet after it carries unlock rows.
## No run save exists, so nothing is archived; the profile is the scratch one.
func _beat_setup() -> void:
	var won := bool(phase_arg)
	DirAccess.remove_absolute(SCRATCH_RUN_SAVE)
	var g = _bare_game()
	sh.profile = Profile.new()
	sh.run_kind = "career"
	if won:
		g.floor_num = 7
		g.over = true
		g.won = true
		_play(g)
		sh._game_is_run = true
		sh._run_recorded = false
		sh._begin_over([], sh._pre_step())
		sh._record_finished_run()
		sh._over_info = sh._build_over_info()
	else:
		g.smog = int(g.floor_def(1)["smog_choke"]) - 1
		g.player["hp"] = 1
		_play(g)
		sh._game_is_run = true
		sh._run_recorded = false
		sh._act({"type": "end_turn"})
	sh._game_is_run = false


func _beat_check() -> String:
	if not sh.game.over or sh.game.won != bool(phase_arg):
		return "the run did not end as wanted"
	if sh._over_phase() != "beat":
		return "not in the beat (%s)" % sh._over_phase()
	if not sh.hotspots.is_empty():
		return "the beat left %d hotspot(s) live" % sh.hotspots.size()
	return "" if sh._run_recorded and String(sh._over_info.get("score", "")) != "" else "the run was not recorded"


## Skip into the fade: the sheet draws translucent with dead buttons.
func _fade_setup() -> void:
	sh._over_ms = Time.get_ticks_msec() - Shell.OVER_BEAT_MS - 40


func _fade_check() -> String:
	if not sh._over_locked():
		return "the fade is not locked"
	return "" if sh.hotspots.is_empty() else "a locked sheet drew %d live button(s)" % sh.hotspots.size()


## Past the lock: the full sheet with live buttons.
func _live_setup() -> void:
	sh._over_ms = Time.get_ticks_msec() - Shell.OVER_LOCK_MS - 10


func _live_check() -> String:
	if sh._over_phase() != "sheet" or sh._over_locked():
		return "the sheet is not up and live (%s)" % sh._over_phase()
	var tags: Array = sh.hotspots.map(func(h): return String(h["tag"]))
	if not (tags.has("new_run") and tags.has("retry_seed") and tags.has("menu")):
		return "the sheet's buttons are not live (%s)" % str(tags)
	if sh.game.won and sh._over_info.get("unlocks", []).is_empty():
		return "a first win drew no unlock rows"
	return ""


func _tut_death_setup() -> void:
	sh._start_tutorial()
	sh.game.over = true


func _tut_death_check() -> String:
	var tags: Array = sh.hotspots.map(func(h): return String(h["tag"]))
	return "" if tags.has("tutorial") and tags.has("menu") else "no TUTORIAL AGAIN / MENU (%s)" % str(tags)
