extends SceneTree
## Draw smoke test: the ONLY test that runs the shell's _draw code. Every
## other shell test calls the input and layout functions headless and never
## renders a frame, so a draw-time error (a font size that reaches 0, a bad
## index in a badge table, a null texture, a type error in the vignette, a
## reel clip the painter cannot draw) would only ever show up on a phone.
## This hosts shell/main.gd inside a SubViewport that renders every frame, at
## several real phone and desktop sizes, with animations at "full" - so the
## step animation reel (shell/anim*.gd, shell/fx_*.gd) paints under the error
## logger on every step - and drives real frames through every screen the
## shell draws: the menu and settings, the career menu (NEW / WON badges), the
## DAILY sheet, the CAREER sheet (every tab, a middle and a last page, NEW
## feats), tutorial steps, an optimizer game played through _act with
## tooltips raised on every enemy, vent and the tender the camera shows (and a
## whole-floor peek every 25 actions), a lethal state (vignette, outline,
## guard flash, escape glow), a danger board (tether, gum slots, SKIES chips),
## a floor title card naming its crew and a vent tooltip naming its release
## and a walled vent's naming none (Block E), an enemy turn frozen mid-reel
## (the held telegraph), a chained reel (an out-of-charge move), two kills in
## one turn (the reel's ghosts, the DOUBLE KILL reel word, the streak flame),
## a kill's streak flame still drawing the held count before its death beat,
## the camera's peek and its edge markers, armed direction and tile aims with
## their preview labels, a toast in the context line, the boss floor (core
## shield ring up and down, a phase banner), the shrine, forge, draft and
## drop sheets, the log, help pages and intro, and the end of a run: both
## game-over sheets set from outside, a killing blow still on its way (every
## danger readout held, the SKIES chips and the item glow included), a
## survived enemy turn mid-reel (the chip, edges, outline and END all on the
## turn ended, not the next), the end beat (a smog death through _act - once
## frozen mid-wilt, the death reel painting under the beat, and three times
## after the wilt, at full, at quick and after a skip tap, the tender not
## drawn - and a first win through _act with its gold bursts, and after its
## reel the winner still drawn), the sheet
## fading in locked, the live sheet with its unlock
## rows, the unlock pager over it (first and last page), a career ping banner
## beside an objective line carrying the career hint, and a tutorial death.
## Each phase asserts it reached the state its draw code needs.
##
## Gate: an OS Logger counts every engine error, push_error and SCRIPT ERROR
## raised while it runs; any one fails the test (exit 1). The reel gates read
## what main._draw_map handed the painter (_reel_draws, the clip kinds, layers
## and words live on those frames - a clip with a tile recorded only when the
## painter itself asked its recording `vis` about that tile (_paint_reel), a
## tileless one by the mirror beside it - the streak flames drawn and the
## count drawn, the telegraph tiles a frame used and the numbers, tethers and
## badges drawn from them, the HP verdicts the chip and the vignette drew,
## the outline, END's border, the escape glow, the SKIES chips and the
## context line drawn, whether the tender was drawn, the tender's tile the
## end beat's lines stepped off), never the shell's reel state: a draw that
## stopped feeding the painter, a painter that stopped painting, or a draw
## that painted the live telegraph mid-reel, fails here.
## Run: godot --headless --path . --script tests/test_draw.gd
##
## Time: every shell clock read goes through main's _now(), so a phase that
## needs one exact frame of an animation pins `clock_override` for its
## frames; _next_phase un-pins it before every setup.
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
const Regress := preload("res://tests/regress_lib.gd")

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
## The crew-card and vent-tip phases build their games on
## ShellTest.PACK_CONFIG (tests/test_shell.gd), the ONE config under which a
## game draws encounter packs and biome reinforcements (Block E, stage 9), so
## this test draws on exactly the config test_shell's gates check.


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
var phase_beat_draws := 0
var phase_flame_draws := 0  # main._flame_draws when the current phase began
var seen_reel_draws := 0    # main._reel_draws already folded into reel_frames
var phase_errors := 0   # log_counter.errors when the current phase began
var fails: Array = []
## what _draw_map handed the painter on a drawn frame (main._reel_kinds_drawn):
## every clip kind live on it, plus "ghost" (a dead machine's ghost drawn) and
## "word" (a ctx word, _reel_word)
var fx_seen := {}
## ...and the reel layers those clips were painted in (main._reel_layers_drawn:
## a layer counts only when the painter itself asked _paint_reel's recording
## `vis` about one of its clips' tiles): a ground or an air pass that stops
## painting stops being recorded
var layers_seen := {}
var reel_frames := 0        # draws that painted a playing reel (main._reel_draws)
var phase_reel_frames := 0  # ...in the current phase
var phase_frames := 0       # frames drawn in the current phase
var lethal_frames := 0
var tips := 0
## tooltips not raised because the tile is outside the camera's zone (main's
## camera frames part of the floor; a hold there is not a hold on the map)
var tips_skipped := 0
## whole-floor peek frames drawn during the bot game, and the action count of
## the last one (one per 25 actions)
var peek_frames := 0
var peeked_at := -1
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
	seen_reel_draws = 0  # a fresh shell counts its reel draws from 0
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
	phase_beat_draws = sh._beat_draws if sh != null else 0
	phase_flame_draws = sh._flame_draws if sh != null else 0
	if sh != null:
		sh._reel_kinds_drawn = {}  # per phase: a check reads what ITS frames painted
		sh._reel_layers_drawn = {}
		sh._reel_words_drawn = {}
	phase_errors = log_counter.errors
	phase_reel_frames = 0
	phase_frames = 0
	phase_arg = ph["arg"]
	sh.clock_override = -1  # a phase that pins the clock pins it for its own frames only
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
	phase_frames += 1
	# what the frames that just rendered painted, from main._draw_map's own
	# record: every draw that handed the painter a playing reel, and the clip
	# kinds live on it (never the reel state, which a draw can ignore)
	if sh != null:
		var rd: int = sh._reel_draws - seen_reel_draws
		seen_reel_draws = sh._reel_draws
		reel_frames += rd
		phase_reel_frames += rd
		for k in sh._reel_kinds_drawn:
			fx_seen[k] = true
		for k in sh._reel_layers_drawn:
			layers_seen[k] = true
	if left > 0 and log_counter.errors > phase_errors:
		left = 0  # an error is already a failure: end the phase, do not crawl on
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
	for k in ["float", "ghost", "word"]:
		if not fx_seen.has(k):
			fails.append("_draw_map never handed the painter a live %s (%s)" % [k, str(fx_seen.keys())])
	for k in ["ground", "air"]:
		if not layers_seen.has(k):
			fails.append("_draw_map never painted a live %s clip (layers %s)" % [k, str(layers_seen.keys())])
	for f in fails:
		print("FAIL: " + f)
	if log_counter.errors > 0:
		print("draw smoke: %d engine/script error(s), first %d:" % [log_counter.errors, log_counter.first.size()])
		for m in log_counter.first:
			print("  " + m)
	if fails.is_empty() and log_counter.errors == 0:
		var kinds: Array = fx_seen.keys()
		kinds.sort()
		print("draw smoke: OK (%d frames, %d viewports, 0 errors) - %d draws, %d reel frames, %d tooltips (%d enemy, %d tender, %d off-camera skipped), %d peek frames, %d lethal frames, %.1fs" % [
			frames, VIEWPORTS.size(), draws, reel_frames, tips, enemy_tips, tender_tips, tips_skipped, peek_frames, lethal_frames, ms / 1000.0])
		print("draw smoke: reel clip kinds drawn (%d): %s" % [kinds.size(), ", ".join(kinds)])
		quit(0)
	else:
		print("draw smoke: FAILED (%d frames, %d viewports, %d errors, %d failed checks)" % [
			frames, VIEWPORTS.size(), log_counter.errors, fails.size()])
		quit(1)
	return true


# --- fixtures -------------------------------------------------------------------

## A fresh game the shell plays, with nothing recorded and nothing written.
## Like every in-shell game swap (_new_game, _start_tutorial, _load_run) it
## drops the last game's reel and camera: a stale reel of another board would
## draw that board's rooms and poses over this one.
func _play(g) -> void:
	sh.game = g
	sh._reset_reel()
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
	# main's camera frames part of the floor and _show_tooltip reads a tile
	# only from inside its zone (the same point test): a tile off screen is
	# skipped, never a miss
	if not sh._cam_zone.has_point(_tile_px(t)):
		tips_skipped += 1
		return
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


## The reel's ctx-word float clip saying `text` (Shell._reel_word), or {}.
func _reel_word(text: String) -> Dictionary:
	for cl in sh._reel.get("clips", []):
		if String(cl.get("kind", "")) == "float" and bool(cl.get("word", false)) and String(cl.get("text", "")) == text:
			return cl
	return {}


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
		["career sheet (goals)", 2, "_career_setup", "_career_check", "", ["goals", 0]],
		["career sheet (goals, page 2)", 2, "_career_setup", "_career_check", "", ["goals", 1]],
		["career sheet (feats, fresh)", 2, "_career_setup", "_career_check", "", ["feats", 0]],
		["career sheet (feats, last page)", 2, "_career_setup", "_career_check", "", ["feats", 4]],
		["career sheet (records)", 2, "_career_setup", "_career_check", "", ["records", 0]],
		["career sheet (records, last page)", 2, "_career_setup", "_career_check", "", ["records", 2]],
		["tutorial", 8, "_tutorial_setup", "_tutorial_check", "_tutorial_step", null],
		["tutorial done", 2, "_tutorial_done_setup", "_tutorial_done_check", "", null],
		["bot game", 100000, "_bot_setup", "_bot_check", "_bot_each", null],
		["lethal", 4, "_lethal_setup", "_lethal_check", "_lethal_each", null],
		["danger board", 3, "_danger_board_setup", "_danger_board_check", "", null],
		["floor card (crew)", 3, "_crew_card_setup", "_crew_card_check", "_crew_card_each", null],
		["vent tooltip (release)", 3, "_vent_tip_setup", "_vent_tip_check", "_vent_tip_each", null],
		["vent tooltip (covered)", 3, "_vent_cover_setup", "_vent_cover_check", "_vent_tip_each", null],
		["reel mid-step (enemy turn)", 3, "_reel_mid_setup", "_reel_mid_check", "", null],
		["chained reel (out of charge)", 3, "_chain_setup", "_chain_check", "", null],
		["animations quick", 3, "_anim_mode_setup", "_anim_mode_check", "", "quick"],
		["animations off", 3, "_anim_mode_setup", "_anim_mode_check", "", "off"],
		["kill", 3, "_kill_setup", "_kill_check", "", null],
		["streak flame held to the death beat", 3, "_flame_held_setup", "_flame_held_check", "", null],
		["camera peek", 3, "_peek_setup", "_peek_check", "", null],
		["edge markers", 3, "_edge_setup", "_edge_check", "", null],
		["aim preview (direction)", 3, "_aim_dir_setup", "_aim_dir_check", "", null],
		["aim preview (tile)", 3, "_aim_tile_setup", "_aim_tile_check", "", null],
		["toast", 3, "_toast_setup", "_toast_check", "", null],
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
		["career ping + objective hint", 3, "_ping_setup", "_ping_check", "", null],
		["game over (died)", 3, "_over_setup", "_over_check", "", false],
		["game over (won)", 3, "_over_setup", "_over_check", "", true],
		["killing blow pending", 3, "_blow_setup", "_blow_check", "", null],
		["enemy turn survived (reel playing)", 3, "_survive_setup", "_survive_check", "", null],
		["end beat (died, wilt playing)", 3, "_wilt_setup", "_wilt_check", "", false],
		["end beat (died, wilt over)", 3, "_wilt_over_setup", "_wilt_over_check", "", "full"],
		["end beat (died, quick, wilt over)", 3, "_wilt_over_setup", "_wilt_over_check", "", "quick"],
		["end beat (died, wilt skipped)", 3, "_wilt_over_setup", "_wilt_over_check", "", "skip"],
		["end beat (died)", 3, "_beat_setup", "_beat_check", "", false],
		["over sheet (fading, locked)", 2, "_fade_setup", "_fade_check", "_fade_setup", null],
		["over sheet (recorded, live)", 2, "_live_setup", "_live_check", "", null],
		["end beat (won)", 3, "_beat_setup", "_beat_check", "", true],
		["end beat (won, reel over)", 3, "_won_over_setup", "_won_over_check", "", true],
		["over sheet (first win)", 2, "_live_setup", "_live_check", "", null],
		["unlock pager", 2, "_pager_setup", "_pager_check", "", 0],
		["unlock pager (last page)", 2, "_pager_setup", "_pager_check", "", 99],
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
	if sh.mode != "settings":
		return "settings sheet not up"
	var n: int = sh._settings_rows().size()
	return "" if n == 7 else "the settings sheet has %d rows, wanted 7 (hold, intro, sound, music, vibration, animations, camera)" % n


func _tutorial_setup() -> void:
	if saved_profile != null:
		sh.profile = saved_profile  # the career phases above lent the shell a profile
		saved_profile = null
	sh.mode = "normal"
	sh._start_tutorial()


## The menu with everything a career puts on it: a NEW badge on every cycler
## and on CAREER, a WON badge on the loadout, a named difficulty, the footer
## with its feats count, the legacy daily notice - and, for the CAREER sheet
## phases, earned feats (one unseen) and records. The
## profile is a stand-in; the one path here that writes it (opening the FEATS
## tab clears its NEW badges) writes the scratch profile_path.
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
	p.records["best"]["score"] = p._rec(1200, 9, "tender", 1)
	p.records["best"]["fastest_win"] = p._rec(140, 7, "tender", 0)
	p.feats = {"green_thumb": p._feat_rec("2026-01-02", 4), "resonant": p._feat_rec("2026-01-05", 9)}
	p.unseen.append("feat:green_thumb")
	p.totals = {"kills": 140}
	p.bosses_beaten = ["furnace_core"]
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
	return "" if badges >= 5 else "the career menu drew only %d badges (NEW on four cyclers and CAREER)" % badges


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


## The CAREER sheet on tab / page `phase_arg` ([tab, page]).
func _career_setup() -> void:
	sh.screen = "menu"
	sh.mode = "normal"
	sh._tap("career")
	sh._tap("career_tab:" + String(phase_arg[0]))
	for i in int(phase_arg[1]):
		sh._tap("career_page:+1")


func _career_check() -> String:
	if sh.mode != "career":
		return "career sheet not up (%s)" % sh.mode
	if sh.career_tab != String(phase_arg[0]) or sh.career_page != int(phase_arg[1]):
		return "career sheet on %s p%d, wanted %s p%d" % [sh.career_tab, sh.career_page, phase_arg[0], int(phase_arg[1])]
	for h in sh.hotspots:
		if String(h["tag"]) == "close":
			return ""
	return "the career sheet laid out no BACK button"


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
	if peek_frames == 0:
		return "the bot game drew no whole-floor peek"
	if reel_frames == 0:
		return "the bot game painted no frame with a playing reel"
	if sh.game.total_turns < 10:
		return "the bot game barely moved (%d turns)" % sh.game.total_turns
	return ""


func _lethal_each() -> void:
	if bool(sh._danger_state().get("lethal", false)):
		lethal_frames += 1


func _kill_check() -> String:
	if _reel_word("DOUBLE KILL").is_empty():
		return "the second kill of the turn floated no DOUBLE KILL reel word"
	if phase_reel_frames < draws - phase_draws:
		return "the reel was not painted on every pinned kill frame (%d of %d draws)" % [phase_reel_frames, draws - phase_draws]
	if not sh._reel_kinds_drawn.has("ghost"):
		return "the kill frames drew no ghost (%s)" % str(sh._reel_kinds_drawn.keys())
	if not sh._reel_words_drawn.has("DOUBLE KILL"):
		return "the kill frames painted no DOUBLE KILL word (%s)" % str(sh._reel_words_drawn.keys())
	var flames: int = sh._flame_draws - phase_flame_draws
	if flames < draws - phase_draws:
		return "the streak flame was not drawn on every kill frame (%d of %d draws, tile %.1f px)" % [flames, draws - phase_draws, sh._ts]
	# the count it drew is the one _streak_shown holds at this beat
	var stk: Array = sh._streak_shown()
	var want_sv := int(stk[0]) + (1 if int(stk[1]) > 0 else 0)
	if sh._flame_value_drawn != want_sv:
		return "the streak flame drew %d, not the %d _streak_shown holds" % [sh._flame_value_drawn, want_sv]
	return ""


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
	peeked_at = -1


## One frame of the bot game: a queued tooltip, else one action through _act
## (every 25 actions one frame of the whole-floor peek, then the tooltip queue
## refills with every enemy, vent and the tender, so each the camera shows is
## raised and drawn at least once on the way).
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
		if peeked_at != bot_left:
			# one frame of the camera's whole-floor peek (Z / the camera
			# button); the next action ends it, as it does for a player
			peeked_at = bot_left
			sh.cam_overview = true
			peek_frames += 1
			return
		sh.cam_overview = false
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
	# count the action BEFORE taking it: an error inside choose_action or _act
	# aborts this call, and a decrement after it would never run - the phase
	# would then crawl to its frame cap on every viewport before failing
	bot_left -= 1
	sh._act(bot.choose_action(sh.game.snapshot(), sh.game.legal_actions()))


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


var _crew_name := ""


## A generated floor that drew a crew, its title card held up: line 2 must
## carry the pack's name (read from game.encounter, never a literal) before it
## is drawn, through _txt_c_fit at 0.9vw.
func _crew_card_setup() -> void:
	var g = Game.new(5, ShellTest.PACK_CONFIG.duplicate(true))
	g._enter_floor(3)
	_play(g)
	_crew_name = String(g.encounter(3).get("name", ""))
	var card: Array = sh._floor_card_lines(g.snapshot())
	if _crew_name == "" or not String(card[1]).ends_with("·  " + _crew_name):
		_fail("the title card's line 2 does not name the crew '%s' (%s)" % [_crew_name, " | ".join(card)])
	_crew_card_each()


## Keep the card mid-hang (fully opaque) on every frame of the phase.
func _crew_card_each() -> void:
	sh._floor_fade_ms = sh._now() - int(sh.FLOOR_CARD_MS * 0.5)


func _crew_card_check() -> String:
	var age: int = sh._now() - int(sh._floor_fade_ms)
	if age < 0 or age >= sh.FLOOR_CARD_MS:
		return "the title card was not up (%d ms)" % age
	var card: Array = sh._floor_card_lines(sh.game.snapshot())
	if not String(card[1]).contains(_crew_name):
		return "the drawn card's line 2 lost the crew name (%s)" % String(card[1])
	return ""


var _vent_tip_at := Vector2i(-1, -1)
var _vent_tip_want := ""


## A floor with a several-kind reinforce list, the tooltip raised on its
## SECOND vent: the line names reinforce_kind's answer for that vent and the
## smog forecast's spawn_wave.
func _vent_tip_setup() -> void:
	var g = Game.new(5, ShellTest.PACK_CONFIG.duplicate(true))
	g._enter_floor(4)
	var vents: Array = g.map["vents"]
	var vix: int = mini(1, vents.size() - 1)
	_vent_tip_at = vents[vix]
	g.terrain.erase(_vent_tip_at)
	for e in g.enemies:
		if e["pos"] == _vent_tip_at:
			e["pos"] = Vector2i(-9, -9)
	_play(g)
	var sky: Dictionary = sh._danger_state()["sky"]
	var kind: String = g.reinforce_kind(g.floor_def(4), int(sky.get("spawn_wave", -1)), vix)
	_vent_tip_want = "releases " + Names.a_name(kind) if int(sky.get("spawn_wave", -1)) >= 0 and kind != "" else ""
	if _vent_tip_want == "" or Content.FLOORS[3]["reinforce"].size() < 2:
		_fail("fixture: no wave forecast on floor 4's vent %d (%s)" % [vix, str(sky)])
	_vent_tip_each()


## Raise it on every frame: the tile's screen point is valid once a frame of
## THIS game has been laid out.
func _vent_tip_each() -> void:
	_raise_tip(_vent_tip_at)


func _vent_tip_check() -> String:
	if sh.tooltip_tile != _vent_tip_at:
		return "the vent tooltip did not rise on %s" % str(_vent_tip_at)
	for l in sh.tooltip:
		if String(l).begins_with(_vent_tip_want):
			return ""
	return "the vent tooltip does not name its release '%s' (%s)" % [_vent_tip_want, str(sh.tooltip)]


## The same vent with Roots over it: Game._tick_smog skips a vent that is not
## _open, so the tooltip draws the covered line and names no release.
func _vent_cover_setup() -> void:
	var g = Game.new(5, ShellTest.PACK_CONFIG.duplicate(true))
	g._enter_floor(4)
	var vents: Array = g.map["vents"]
	_vent_tip_at = vents[mini(1, vents.size() - 1)]
	for e in g.enemies:
		if e["pos"] == _vent_tip_at:
			e["pos"] = Vector2i(-9, -9)
	g.terrain[_vent_tip_at] = {"kind": "roots", "ttl": 3}
	_play(g)
	if Danger.vent_state(g.snapshot(), _vent_tip_at) != "covered":
		_fail("fixture: roots do not cover floor 4's vent %s" % str(_vent_tip_at))
	_vent_tip_want = Shell.VENT_COVERED_LINE
	_vent_tip_each()


func _vent_cover_check() -> String:
	if sh.tooltip_tile != _vent_tip_at:
		return "the covered vent's tooltip did not rise on %s" % str(_vent_tip_at)
	for l in sh.tooltip:
		if String(l).begins_with("releases"):
			return "the covered vent's tooltip names a release (%s)" % str(sh.tooltip)
	if not sh.tooltip.has(_vent_tip_want):
		return "the covered vent's tooltip lost '%s' (%s)" % [_vent_tip_want, str(sh.tooltip)]
	return ""


## Two kills in one turn through _act: two 1-HP drill bots struck down on two
## sides of the tender, with a streak standing so the flame draws too. The
## second kill's reel carries the first one's ghost on (Anim.carry), plays
## its own, and floats DOUBLE KILL as a ctx word (_reel_word); the clock is
## pinned just after that word rises (160 ms after the death beat), while the
## second machine's ghost is still dying (AnimLib.T_DIE, 420 ms), so every
## frame of the phase paints the word, the ghost and the flame.
func _kill_setup() -> void:
	var g = _bare_game()
	var dirs := _open_dirs(g)
	if dirs.size() < 2:
		_fail("fixture: the tender has fewer than two open sides")
		return
	for i in 2:
		var e: Dictionary = g._spawn("drill_bot", g.player["pos"] + dirs[i])
		e["hp"] = 1
		e["intent"] = {"type": "idle"}
	g.player["charge"] = 3
	_play(g)
	sh.stats.streak_closed = 3
	sh._act({"type": "strike", "dir": dirs[0]})
	sh._act({"type": "strike", "dir": dirs[1]})
	if not g.enemies.is_empty():
		_fail("fixture: the two strikes left %d machine(s) standing" % g.enemies.size())
	var w := _reel_word("DOUBLE KILL")
	if not w.is_empty():
		sh.clock_override = sh._reel_ms + int(w["t0"]) + 60


## The streak flame between a kill's strike and its death beat: streak 2
## closed, no kill yet this turn, one strike kills a 1-HP drill bot, the clock
## pinned a millisecond before the death beat. The live fold already counts
## the kill (2 + 1 = 3), but the flame must still draw the 2 it showed before
## the step (_streak_shown) - it ticks up on the death beat, with the ghost
## and the STREAK word.
var _flame_live_sv := -1


func _flame_held_setup() -> void:
	var g = _bare_game()
	var dirs := _open_dirs(g)
	var e: Dictionary = g._spawn("drill_bot", g.player["pos"] + dirs[0])
	e["hp"] = 1
	e["intent"] = {"type": "idle"}
	g.player["charge"] = 3
	_play(g)
	sh.stats.streak_closed = 2
	sh.stats.open_turn_kills = 0
	sh._flame_value_drawn = 0
	sh.clock_override = 640000
	sh._act({"type": "strike", "dir": dirs[0]})
	_flame_live_sv = int(sh.stats.streak_closed) + (1 if int(sh.stats.open_turn_kills) > 0 else 0)
	var dt := -1
	var ev_t: Array = sh._reel.get("ev_t", [])
	for i in mini(sh._reel_evs.size(), ev_t.size()):
		if dt < 0 and String(sh._reel_evs[i].get("t", "")) == "death":
			dt = int(ev_t[i])
	sh.clock_override = sh._reel_ms + maxi(dt - 1, 0)


func _flame_held_check() -> String:
	if not sh.game.enemies.is_empty():
		return "fixture: the strike left the machine standing"
	var stk: Array = sh._streak_shown()
	var held_sv := int(stk[0]) + (1 if int(stk[1]) > 0 else 0)
	if held_sv == _flame_live_sv or held_sv != 2:
		return "fixture: held %d and live %d streaks, so the check has no teeth" % [held_sv, _flame_live_sv]
	var flames: int = sh._flame_draws - phase_flame_draws
	if flames < draws - phase_draws:
		return "the streak flame was not drawn on every frame (%d of %d draws)" % [flames, draws - phase_draws]
	if sh._flame_value_drawn != held_sv:
		return "before the death beat the streak flame drew %d, not the %d it held (live %d)" \
			% [sh._flame_value_drawn, held_sv, _flame_live_sv]
	return ""


## The won run's beat again, the clock pinned after its reel has ended (the
## fade): only a LOST run's tender is hidden once its reel is over
## (_tender_pose), so the winner must still be drawn on the map under the
## beat's tint and the fading sheet.
func _won_over_setup() -> void:
	sh.clock_override = sh._reel_ms + int(sh._reel.get("len", 0)) + 60


func _won_over_check() -> String:
	if not sh.game.over or not sh.game.won:
		return "fixture: the run is not a win"
	if sh._reel_left() > 0:
		return "the win's reel is still playing (%d ms left)" % sh._reel_left()
	if not ["beat", "fade"].has(sh._over_phase()):
		return "not in the beat or the fade (%s)" % sh._over_phase()
	if not sh._tender_drawn:
		return "after the win's reel (%s) the frame did not draw the tender who won" % sh._over_phase()
	return ""


## The enemy turn frozen mid-reel: two drill bots strike the tender on an end
## turn and the clock is pinned between their two blows, so every frame
## paints the reel's poses and numbers, the HELD HP chip and the HELD
## telegraph (the pre-step board's red tiles, _tele_view over _reel_tele)
## while the blows are carried out. A third bot aims at a tile beside the
## tender (a red tile with a number of its own) and a magnet crane in line
## telegraphs a drag (a tether), so the held numbers, tethers and badges all
## differ from the live ones; at 5 HP the held chip reads 4 ("ok") while the
## live board is at 3 and the next turn's forecast kills ("lethal").
func _reel_mid_setup() -> void:
	var g = _bare_game()
	var pp: Vector2i = g.player["pos"]
	var dirs := _open_dirs(g)
	for i in mini(2, dirs.size()):
		var a: Dictionary = g._spawn("drill_bot", pp + dirs[i])
		a["intent"] = {"type": "attack", "tile": pp, "dmg": 1}
	# the crane: three open tiles in a line on a free side, dragging once
	for d in dirs.slice(2):
		if g._open(pp + d * 2) and g._open(pp + d * 3):
			var c: Dictionary = g._spawn("magnet_crane", pp + d * 3)
			c["intent"] = {"type": "drag", "times": 1}
			break
	# the third bot: two tiles off the tender, aiming at a floor tile beside
	# it that is not the tender's own
	var placed := false
	for y in range(pp.y - 4, pp.y + 5):
		for x in range(pp.x - 4, pp.x + 5):
			var bp := Vector2i(x, y)
			if placed or absi(bp.x - pp.x) + absi(bp.y - pp.y) < 3 or not g._open(bp):
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var tt: Vector2i = bp + d
				if not placed and g._open(tt) and absi(tt.x - pp.x) + absi(tt.y - pp.y) >= 2:
					var b: Dictionary = g._spawn("drill_bot", bp)
					b["intent"] = {"type": "attack", "tile": tt, "dmg": 3}
					placed = true
	g.player["hp"] = 5
	_play(g)
	sh._act({"type": "end_turn"})
	var hits: Array = []
	for h in sh._reel.get("hp", {}).get("player", []):
		if not hits.has(int(h[0])):
			hits.append(int(h[0]))
	var rlen := int(sh._reel.get("len", 0))
	var pin := int(rlen * 0.5)
	if hits.size() >= 2:
		pin = (int(hits[0]) + int(hits[1])) / 2
	sh.clock_override = sh._reel_ms + pin


func _reel_mid_check() -> String:
	if int(sh._reel.get("len", 0)) <= 0:
		return "the enemy turn planned no reel"
	if phase_reel_frames < draws - phase_draws:
		return "the reel was not painted on every pinned frame (%d of %d draws)" % [phase_reel_frames, draws - phase_draws]
	var ts: Dictionary = sh._threat_snap(sh.game.snapshot())
	if not bool(ts.get("held", false)):
		return "mid-reel, the telegraph is not the held pre-step view"
	# the draw used the HELD telegraph (red tiles, numbers, marks, tethers and
	# badges all read that one view), and the held one differs from the live
	# one here, so a draw that read the live telegraph cannot pass
	var held: Dictionary = sh._threat_tiles(ts)
	var live: Dictionary = sh._danger_state().get("tele", {}).get("tiles", {})
	if held == live:
		return "fixture: the held and live telegraphs agree (%s), so the check has no teeth" % str(held)
	if sh._tele_drawn != held:
		return "mid-reel, the frame drew the telegraph %s, not the held %s" % [str(sh._tele_drawn), str(held)]
	# ...and the numbers, tethers and badges the frame drew are the HELD
	# view's too (each differs from the live view's on this fixture, so a draw
	# site that read the live telegraph fails here)
	var pp: Vector2i = sh.game.player["pos"]
	var htv: Dictionary = sh._tele_view(ts)
	var ltv: Dictionary = sh._danger_state().get("tele", {})
	var want_n: Dictionary = Danger.tile_numbers(htv, pp)
	var want_t: Array = Danger.tethers(htv, pp)
	var want_b := {}
	for bd in Danger.badges(ts, htv):
		want_b[bd["id"]] = bd
	var live_b := {}
	for bd in Danger.badges(ts, ltv):
		live_b[bd["id"]] = bd
	if want_n == Danger.tile_numbers(ltv, pp) or want_t == Danger.tethers(ltv, pp) or want_b == live_b:
		return "fixture: a held view agrees with the live one (numbers %s, tethers %s, badges %d), so the check has no teeth" % [
			str(want_n), str(want_t), want_b.size()]
	if sh._numbers_drawn != want_n:
		return "mid-reel, the frame drew the tile numbers %s, not the held %s" % [str(sh._numbers_drawn), str(want_n)]
	if sh._tethers_drawn != want_t:
		return "mid-reel, the frame drew the tethers %s, not the held %s" % [str(sh._tethers_drawn), str(want_t)]
	if sh._badges_drawn != want_b:
		return "mid-reel, the frame drew the badges %s, not the held %s" % [str(sh._badges_drawn), str(want_b)]
	# the HP chip and the vignette drew the HELD verdict (_hp_state_shown),
	# which differs from the live one here: 4 of 10 held against 3 live, and
	# the next turn's forecast lethal
	var held_hp: String = sh._hp_state_shown()
	var live_hp: String = Danger.hp_state(int(sh.game.player["hp"]), int(sh.game.player["max_hp"]),
		bool(sh._danger_state().get("lethal", false)))
	if held_hp == live_hp:
		return "fixture: the held HP verdict agrees with the live one (%s), so the check has no teeth" % held_hp
	if sh._hp_chip_drawn != held_hp or sh._hp_vignette_drawn != held_hp:
		return "mid-reel, the chip drew %s and the vignette %s, not the held %s" % [
			sh._hp_chip_drawn, sh._hp_vignette_drawn, held_hp]
	return ""


## The other two Animations settings over the same enemy turn, with a
## stunned machine beside the strikers: "quick" plays every motion faster,
## "off" draws no motion, no idle loop and no status overlay - the block
## glyph is then the only cue - and both are draw paths of their own.
func _anim_mode_setup() -> void:
	var g = _bare_game()
	var dirs := _open_dirs(g)
	for i in dirs.size():
		var a: Dictionary = g._spawn("drill_bot", g.player["pos"] + dirs[i])
		a["intent"] = {"type": "attack", "tile": g.player["pos"], "dmg": 1}
		if i == dirs.size() - 1:
			a["status"]["stun"] = 2
	g.player["hp"] = int(g.player["max_hp"])
	_play(g)
	sh.anim_mode = String(phase_arg)
	sh._act({"type": "end_turn"})


func _anim_mode_check() -> String:
	var was: String = sh.anim_mode
	sh.anim_mode = "full"  # set directly, never through set:anim: nothing is saved
	if was != String(phase_arg):
		return "the animation setting moved during the phase (%s)" % was
	return ""


## A chained reel: charge dry, a D-pad press ends the turn (a drill bot walks
## in) and then moves - one input, two steps, and the move's reel is chained
## onto the end turn's (_act_chained) instead of cutting it off.
func _chain_setup() -> void:
	var g = _bare_game()
	var pp: Vector2i = g.player["pos"]
	var dirs := _open_dirs(g)
	var walker := Vector2i(-1, -1)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if d != dirs[0] and g._open(pp + d * 3) and g._open(pp + d * 2):
			walker = pp + d * 3
			break
	if walker.x >= 0:
		g._spawn("drill_bot", walker)
	g.player["charge"] = 0
	# what the two steps emit, off a clone (the sim is deterministic): a
	# chained reel holds both steps' events, a fresh one only the move's
	var c = g.clone()
	_chain_want = c.step({"type": "end_turn"}).size()
	for a in c.legal_actions():
		if String(a.get("type", "")) in ["strike", "move"] and a.get("dir") == dirs[0]:
			_chain_want += c.step(a).size()
			break
	_play(g)
	sh._dir_input(dirs[0])


var _chain_want := 0


func _chain_check() -> String:
	if sh._reel_evs.size() != _chain_want:
		return "the move did not chain onto the end turn's reel (%d reel events, both steps emit %d)" % [sh._reel_evs.size(), _chain_want]
	if phase_reel_frames == 0:
		return "the chained reel was never painted"
	return ""


## The camera's whole-floor peek (Z / the camera button) on a full floor.
func _peek_setup() -> void:
	_play(Game.new(4242, {}))
	sh.cam_overview = true  # after _play: _reset_reel -> _cam_reset ends any peek


func _peek_check() -> String:
	if not sh.cam_overview:
		return "the peek ended with no action taken"
	var m: Dictionary = sh.game.map
	var z: Rect2 = sh._cam_zone
	var shown := Rect2((z.position.x - sh._mox) / sh._ts, (z.position.y - sh._moy) / sh._ts, z.size.x / sh._ts, z.size.y / sh._ts)
	if not shown.grow(0.01).encloses(Rect2(0, 0, float(m["w"]), float(m["h"]))):
		return "the peek does not show the whole floor (%s of %dx%d)" % [str(shown), int(m["w"]), int(m["h"])]
	if not sh._edge_pois(sh.game.snapshot(), z).is_empty():
		return "the peek drew edge markers"
	return ""


## Edge markers: the tender on the open tile farthest from the stairs, the
## camera zoomed all the way in, so the stairs (and the nearest corruption)
## sit off screen and get a marker on the view's edge.
func _edge_setup() -> void:
	var g = Game.new(4242, {})
	var m: Dictionary = g.map
	var st: Vector2i = m["stairs"]
	var best := Vector2i(-1, -1)
	var bd := -1
	for y in int(m["h"]):
		for x in int(m["w"]):
			var t := Vector2i(x, y)
			if not g._open(t) or t == st:
				continue
			var d: int = absi(t.x - st.x) + absi(t.y - st.y)
			if d > bd:
				bd = d
				best = t
	g.player["pos"] = best
	_play(g)
	sh.cam_cols = Shell.CAM_COLS_MIN


func _edge_check() -> String:
	var pois: Array = sh._edge_pois(sh.game.snapshot(), sh._cam_zone)
	sh.cam_cols = Shell.CAM_COLS_DEFAULT  # the scratch cfg's zoom: leave it as the next phase expects
	for p in pois:
		if String(p["icon"]) == "stairs":
			return ""
	return "no edge marker for the off-screen stairs (%s)" % str(pois)


## An armed direction aim with its preview: the lance aimed past a drill bot
## labels it with what the cast would deal.
func _aim_dir_setup() -> void:
	var g = _bare_game()
	var d: Vector2i = _open_dirs(g)[0]
	var e: Dictionary = g._spawn("drill_bot", g.player["pos"] + d)
	e["hp"] = 5
	e["intent"] = {"type": "idle"}
	g.player["charge"] = 5
	_play(g)
	sh._ability_press(0)  # solar_lance: 2 down a line


func _aim_dir_check() -> String:
	if sh.mode != "target_dir":
		return "the lance did not arm a direction aim (%s)" % sh.mode
	var labels: Array = sh._preview_labels()
	if not labels.any(func(l): return String(l["text"]) == "-2"):
		return "the direction aim labels nobody with the lance's 2 (%s)" % str(labels)
	return ""


## An armed tile aim with its preview: two snare targets, each tile reads
## "rooted", and the camera widens its frame to every target.
func _aim_tile_setup() -> void:
	var g = _bare_game({"kit": ["sap_snare", "seed_bomb", "mycelium_dash"]})
	var pp: Vector2i = g.player["pos"]
	var run := Vector2i.ZERO
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if g._open(pp + d) and g._open(pp + d * 2):
			run = d
			break
	for k in [1, 2]:
		var e: Dictionary = g._spawn("drill_bot", pp + run * k)
		e["intent"] = {"type": "idle"}
	g.player["charge"] = 5
	_play(g)
	sh._ability_press(0)


func _aim_tile_check() -> String:
	if sh.mode != "target_tile":
		return "two snare targets did not arm a tile aim (%s)" % sh.mode
	var labels: Array = sh._preview_labels()
	if labels.size() != 2 or not labels.all(func(l): return String(l["text"]) == "rooted"):
		return "the tile aim does not label both targets 'rooted' (%s)" % str(labels)
	return ""


## A toast in the context line, from a real step: the d5_cinder_grip board
## through _act (the lance lights the oil under a coal golem and Cinder Grip
## roots it), the clock pinned just after the hook's beat, when the toast
## naming the resonance is up.
func _toast_setup() -> void:
	var cfg := {"fixed_floor": {"fdef": {"green_need": 0, "smog_choke": 999, "smog_dim": [900, 950],
		"smog_spawn": [999], "smog_spawn_every": 0},
		"room": ["##########", "#.......>#", "#@..G....#", "#........#", "##########"],
		"terrain": [{"kind": "oil", "pos": [4, 2]}]},
		"grafts": ["oil_tithe"], "kit": ["solar_lance", "sun_flare", "mycelium_dash"],
		"pool": ["solar_lance", "sun_flare", "mycelium_dash"]}
	_play(Game.new(1, Regress.config_from_json(cfg)))
	sh._act({"type": "ability", "slot": 0, "target": Vector2i(1, 0)})
	if sh._toast == "":
		_fail("fixture: the cinder grip step toasted nothing")
	sh.clock_override = int(sh._toast_ms) + 100


func _toast_check() -> String:
	if not sh._toast_live():
		return "the toast is not live on the pinned frame ('%s' at %d)" % [sh._toast, int(sh._toast_ms)]
	var cm: Dictionary = sh._context_msg(sh.game.snapshot(), float(VIEWPORTS[vi].x), float(VIEWPORTS[vi].y))
	if String(cm["text"]) != sh._toast:
		return "the context line is not the toast ('%s', toast '%s')" % [cm["text"], sh._toast]
	return ""


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
		# floor 7 with its boss alone at 1 HP beside the tender: the strike
		# wins through _act, so the beat starts on a real reel and its three
		# gold bursts land as reel clips on the boss's death beat. The clock
		# is pinned on the second burst, inside the beat
		var gw = Game.new(3)
		gw._enter_floor(7)
		gw.terrain.clear()
		var boss: Dictionary = {}
		for e in gw.enemies.duplicate():
			if Content.ENEMIES[e["kind"]]["traits"].has("boss"):
				boss = e
			else:
				gw.enemies.erase(e)
		gw.smog = 0
		var wd := _open_dirs(gw)
		boss["pos"] = gw.player["pos"] + wd[0]
		boss["hp"] = 1
		boss["intent"] = {"type": "idle"}
		_play(gw)
		sh._game_is_run = true
		sh._run_recorded = false
		sh.clock_override = 600000
		sh._act({"type": "strike", "dir": wd[0]})
		var b0 := -1
		for cl in sh._reel.get("clips", []):
			if String(cl.get("kind", "")) == "burst" and (b0 < 0 or int(cl["t0"]) < b0):
				b0 = int(cl["t0"])
		sh.clock_override = sh._reel_ms + maxi(b0, 0) + 300
	else:
		g.smog = int(g.floor_def(1)["smog_choke"]) - 1
		g.player["hp"] = 1
		_play(g)
		sh._game_is_run = true
		sh._run_recorded = false
		sh._act({"type": "end_turn"})
	sh._game_is_run = false


## The killing blow still on its way: 5 of 10 HP and one drill bot striking
## for 5 on an end turn through _act, the clock pinned a millisecond before
## the blow lands. The finished game's own forecast is empty, so every danger
## readout this frame drew - the HP chip, the red edges, the tender's
## outline, END's border, the context line's Incoming warning, the SKIES
## chips and the glow on the satchel's Iron Seed (+3 shield would have
## carried the turn) - must be the HELD pre-step one (_death_held), never the
## calm a finished game reads.
func _blow_setup() -> void:
	var g = _bare_game()
	var pp: Vector2i = g.player["pos"]
	var b: Dictionary = g._spawn("drill_bot", pp + _open_dirs(g)[0])
	b["intent"] = {"type": "attack", "tile": pp, "dmg": 5}
	g.player["hp"] = 5
	g.player["items"] = ["iron_seed"]
	_play(g)
	sh.clock_override = 610000
	sh._act({"type": "end_turn"})
	var blow := -1
	for h in sh._reel.get("hp", {}).get("player", []):
		if blow < 0:
			blow = int(h[0])
	sh.clock_override = sh._reel_ms + maxi(blow - 1, 0)


func _blow_check() -> String:
	if not sh.game.over or sh.game.won:
		return "fixture: the blow does not kill"
	if bool(sh._danger_state().get("lethal", false)):
		return "fixture: the finished game still reads a lethal forecast, so the check has no teeth"
	if not sh._death_held():
		return "the frames are not between the tap and the blow"
	if sh._hp_chip_drawn != "lethal" or sh._hp_vignette_drawn != "lethal":
		return "before the blow the chip drew %s and the edges %s, not the held lethal" % [sh._hp_chip_drawn, sh._hp_vignette_drawn]
	if sh._outline_drawn != "lethal" or not sh._end_lethal_drawn:
		return "before the blow the outline drew %s and END red %s, not the held lethal" % [sh._outline_drawn, sh._end_lethal_drawn]
	if not sh._ctx_drawn.contains("LETHAL"):
		return "before the blow the context line drew '%s', not the held Incoming warning" % sh._ctx_drawn
	# the SKIES chips: the held board's (the finished game has none of its own)
	var held_chips: Array = []
	for c in Danger.sky_chips(sh._reel_danger.get("sky", {})):
		held_chips.append(String(c["text"]))
	var live_chips: Array = []
	for c in Danger.sky_chips(sh._danger_state().get("sky", {})):
		live_chips.append(String(c["text"]))
	if held_chips.is_empty() or held_chips == live_chips:
		return "fixture: the held and live SKIES chips agree (%s), so the check has no teeth" % str(held_chips)
	if sh._sky_chips_drawn != held_chips:
		return "before the blow the SKIES row drew %s, not the held %s" % [str(sh._sky_chips_drawn), str(held_chips)]
	# ...and the escape glow: the held board's escape (the Iron Seed, slot 0)
	if Danger.glow_items(sh._reel_danger.get("escapes", {})) != [0]:
		return "fixture: the held board names no item escape (%s)" % str(sh._reel_danger.get("escapes", {}))
	if sh._glow_drawn != [0]:
		return "before the blow the satchel glowed %s, not the held escape [0]" % str(sh._glow_drawn)
	return ""


## A survivable enemy turn whose aftermath IS lethal: 4 of 10 HP, one drill
## bot striking for 2 (and for 2 again next turn), an end turn through _act,
## the clock pinned a millisecond before the blow lands. The live forecast is
## already lethal, but while the reel plays the turn the player ended, every
## readout of the tender's own fate draws that turn's verdict
## (_verdict_danger): the HP chip and edges "ok" on the 4 they show, the
## outline amber (2 lands, you live), END calm - one verdict, never an outline
## and END already red beside a calm chip. Then, the reel over, all of them go
## lethal together.
func _survive_setup() -> void:
	var g = _bare_game()
	var pp: Vector2i = g.player["pos"]
	var b: Dictionary = g._spawn("drill_bot", pp + _open_dirs(g)[0])
	b["intent"] = {"type": "attack", "tile": pp, "dmg": 2}
	g.player["hp"] = 4
	g.player["max_hp"] = 10
	_play(g)
	sh.clock_override = 620000
	sh._act({"type": "end_turn"})
	var blow := -1
	for h in sh._reel.get("hp", {}).get("player", []):
		if blow < 0:
			blow = int(h[0])
	_survive_blow = blow
	sh.clock_override = sh._reel_ms + maxi(blow - 1, 0)


var _survive_blow := -1


func _survive_check() -> String:
	if sh.game.over or int(sh.game.player["hp"]) != 2:
		return "fixture: the blow does not leave the tender at 2 (%s, %d HP)" % [sh.game.over, int(sh.game.player["hp"])]
	if not bool(sh._danger_state().get("lethal", false)):
		return "fixture: the live forecast is not lethal, so the check has no teeth"
	if _survive_blow <= 1 or sh._reel_left() <= 0 or not sh._turn_reel_held():
		return "the frames are not inside the enemy turn's reel before the blow (blow %d, %d ms left)" % [_survive_blow, sh._reel_left()]
	if sh._hp_chip_drawn != "ok" or sh._hp_vignette_drawn != "ok":
		return "mid-reel the chip drew %s and the edges %s, not the held ok" % [sh._hp_chip_drawn, sh._hp_vignette_drawn]
	if sh._outline_drawn != "amber" or sh._end_lethal_drawn:
		return "mid-reel the outline drew %s and END red %s beside a calm chip - not the turn the player ended" \
			% [sh._outline_drawn, sh._end_lethal_drawn]
	# the reel over: the next turn's lethal verdict everywhere at once
	sh.clock_override = sh._reel_ms + int(sh._reel.get("len", 0)) + 50
	if sh._turn_reel_held() or sh._hp_state_shown() != "lethal" or not bool(sh._verdict_danger().get("lethal", false)):
		return "after the reel the verdict is not lethal everywhere (chip %s, verdict %s)" \
			% [sh._hp_state_shown(), sh._verdict_danger().get("lethal", false)]
	return ""


## The smog death again, after its wilt: at "full" once the reel has run out
## on its own (the fade), at "quick" (the wilt ends inside the beat) and at
## "full" after a tap finished it during the beat. A finished reel is history,
## so the default pose would stand the wilted tender back up under the beat
## and the fading sheet; the frame must not draw it (_tender_drawn).
var _wilt_how := ""


func _wilt_over_setup() -> void:
	_wilt_how = String(phase_arg)
	var how := _wilt_how
	if how == "quick":
		sh.anim_mode = "quick"
	phase_arg = false  # _beat_setup's died arm
	_beat_setup()
	var len := int(sh._reel.get("len", 0))
	if how == "skip":
		sh.clock_override = sh._over_ms + 60
		sh._skip_death_reel()
	else:
		sh.clock_override = sh._reel_ms + len + 60
	sh.anim_mode = "full"  # set directly, never through set:anim: nothing is saved


func _wilt_over_check() -> String:
	var ph: String = sh._over_phase()
	if not ["beat", "fade"].has(ph):
		return "not in the beat or the fade (%s)" % ph
	if sh._reel_left() > 0:
		return "the wilt is still playing (%d ms left)" % sh._reel_left()
	if sh._tender_drawn:
		return "after the wilt (%s, %s) the frame drew the tender standing again" % [_wilt_how, ph]
	return ""


## The smog death again, the clock pinned halfway through the death reel:
## the wilt plays INSIDE the end beat (_begin_over shifts the beat so it ends
## no earlier than the reel), so every frame paints the reel under the beat's
## tint, veil and banner, with no live hotspot.
func _wilt_setup() -> void:
	_beat_setup()
	sh.clock_override = sh._reel_ms + int(int(sh._reel.get("len", 0)) * 0.5)


func _wilt_check() -> String:
	var why := _beat_check()
	if why != "":
		return why
	if sh._reel_left() <= 0 or phase_reel_frames < draws - phase_draws:
		return "the death reel was not painted under the beat (%d of %d draws, %d ms left)" % [
			phase_reel_frames, draws - phase_draws, sh._reel_left()]
	var beats: int = sh._beat_draws - phase_beat_draws
	if beats < draws - phase_draws:
		return "the beat was not drawn over the playing wilt (%d of %d frames)" % [beats, draws - phase_draws]
	# the banner steps off the tender's tile AT ITS CALL SITE: the rect the
	# draw handed _over_beat_layout is the tender's tile, and the lines it
	# drew keep their ink (line 0's cap height to line 1's descenders) off it
	var tile: Rect2 = sh._tile_rect(Vector2i(sh.game.player["pos"]))
	var av: Rect2 = sh._beat_avoid_drawn
	if av.size.y <= 0.0 or not av.position.is_equal_approx(tile.position) or not av.size.is_equal_approx(tile.size):
		return "the beat stepped off %s, not the tender's tile %s" % [str(av), str(tile)]
	var bl: Array = sh._beat_lines_drawn
	if bl.size() < 2:
		return "the beat drew %d line(s)" % bl.size()
	var ink0 := float(bl[0]["y"]) - float(bl[0]["size"]) * 0.8
	var ink1 := float(bl[1]["y"]) + float(bl[1]["size"]) * 0.3
	if ink0 < tile.end.y and ink1 > tile.position.y:
		return "the beat's lines (ink %.0f..%.0f) cover the tender's tile (%.0f..%.0f)" % [
			ink0, ink1, tile.position.y, tile.end.y]
	return ""


func _beat_check() -> String:
	if not sh.game.over or sh.game.won != bool(phase_arg):
		return "the run did not end as wanted"
	if sh._over_phase() != "beat":
		return "not in the beat (%s)" % sh._over_phase()
	if not sh.hotspots.is_empty():
		return "the beat left %d hotspot(s) live" % sh.hotspots.size()
	if bool(phase_arg) and not sh._reel_kinds_drawn.has("burst"):
		return "the win's beat painted no gold burst (%s)" % str(sh._reel_kinds_drawn.keys())
	return "" if sh._run_recorded and String(sh._over_info.get("score", "")) != "" else "the run was not recorded"


## Skip into the fade (re-pinned every frame, so every frame of the phase IS
## the fade): the beat's tint and veil under the sheet fading in, translucent,
## with dead buttons.
func _fade_setup() -> void:
	sh._over_ms = sh._now() - Shell.OVER_BEAT_MS - 40


func _fade_check() -> String:
	if sh._over_phase() != "fade":
		return "not in the fade (%s)" % sh._over_phase()
	if not sh._over_locked():
		return "the fade is not locked"
	# every fade frame drew the beat's tint and veil under the sheet (mutation:
	# drop the `oph == "fade"` branch in main._draw and this fails)
	var beats: int = sh._beat_draws - phase_beat_draws
	if beats <= 0 or beats < draws - phase_draws:
		return "the beat's tint and veil were not drawn under the fade (%d of %d frames)" % [beats, draws - phase_draws]
	return "" if sh.hotspots.is_empty() else "a locked sheet drew %d live button(s)" % sh.hotspots.size()


## Past the lock: the full sheet with live buttons.
func _live_setup() -> void:
	sh._over_ms = sh._now() - Shell.OVER_LOCK_MS - 10


func _live_check() -> String:
	if sh._over_phase() != "sheet" or sh._over_locked():
		return "the sheet is not up and live (%s)" % sh._over_phase()
	var tags: Array = sh.hotspots.map(func(h): return String(h["tag"]))
	if not (tags.has("new_run") and tags.has("retry_seed") and tags.has("menu")):
		return "the sheet's buttons are not live (%s)" % str(tags)
	if sh.game.won and sh._over_info.get("unlocks", []).is_empty():
		return "a first win drew no unlock rows"
	if sh.game.won and not tags.has("unlocks"):
		return "a first win's unlock rows are not a live tap target (%s)" % str(tags)
	return ""


## The unlock pager over the first win's sheet, on page `phase_arg` (clamped:
## 99 is the last page, which carries < and DONE).
func _pager_setup() -> void:
	sh._tap("unlocks")
	for i in int(phase_arg):
		sh._tap("unlock_page:+1")


func _pager_check() -> String:
	if sh.mode != "unlocks":
		return "the pager is not up (%s)" % sh.mode
	var tags: Array = sh.hotspots.map(func(h): return String(h["tag"]))
	if not tags.has("close") or tags.has("new_run"):
		return "the pager's own row is not what is live (%s)" % str(tags)
	var pages: int = int(sh._unlock_page_info(0)["pages"])
	if int(phase_arg) > 0 and (pages < 2 or sh.unlock_page != pages - 1 or not tags.has("unlock_page:-1")):
		return "not on the last of several pages (%d of %d, %s)" % [sh.unlock_page + 1, pages, str(tags)]
	return ""


## A career run's floor 4 on an empty board: the objective line carries the
## career hint ("floor 5 unlocks Mycology") and a ping banner is up.
func _ping_setup() -> void:
	var g = _bare_game()
	g.floor_num = 4
	_play(g)
	sh._game_is_run = true  # the hint is a run's; nothing is acted, so nothing is recorded
	sh._career_ref = Profile.new().run_ref()
	var ev: Array = Profile.ping_events({"runs": 1, "best_floor": 3, "floors": {}, "casts": []}, 4, {}, {})
	# a career ping waits out the floor title card (_career_held); draw it as
	# it shows once an earlier phase's card has gone
	sh._floor_fade_ms = sh._now() - sh.FLOOR_CARD_MS - 1
	sh._push_banner(ev[0]["lines"], Shell.COL_GOLD, int(Feedback.BANNER_PRIO["career"]))


func _ping_check() -> String:
	var why := ""
	var cm: Dictionary = sh._context_msg(sh.game.snapshot(), float(VIEWPORTS[vi].x), float(VIEWPORTS[vi].y))
	if not String(cm["text"]).contains("floor 5 unlocks Mycology"):
		why = "the objective line has no career hint (%s)" % cm["text"]
	elif sh._banner.is_empty() or String(sh._banner[0]) != "DEEPEST YET":
		why = "the ping banner is not up (%s)" % str(sh._banner)
	sh._game_is_run = false
	sh._career_ref = {}
	return why


func _tut_death_setup() -> void:
	sh._start_tutorial()
	sh.game.over = true


func _tut_death_check() -> String:
	var tags: Array = sh.hotspots.map(func(h): return String(h["tag"]))
	return "" if tags.has("tutorial") and tags.has("menu") else "no TUTORIAL AGAIN / MENU (%s)" % str(tags)
