extends SceneTree
## Full-screen shots of the REAL shell in the states a player reads: the
## menu, the intro card, every tutorial step, a live floor, the shrine, the
## draft, the legend, the log and both end cards. The agent's way to judge
## text density and the camera without a phone in hand.
##
## Needs a display, so run it under a virtual one with the GL renderer:
##   xvfb-run -a -s "-screen 0 540x1200x24" godot --rendering-driver opengl3 \
##     --path . --resolution 540x1200 --script tests/capture_screens.gd
## Env:
##   SCREENS=all | menu,intro,tutorial,play,tooltip,camera,shop,draft,legend,log,won,died
##   SCREENS_OUT=<dir>   (default user://screens)
##   SCREENS_SEED=<n>    the run the live shots are taken from (default 4242)
##   SCREENS_STEPS=<n>   optimizer actions played before the "play" shots (default 40)
## Prints one line per PNG written.

const Game := preload("res://sim/game.gd")
const Roster := preload("res://bots/roster.gd")
const ShellTest := preload("res://tests/test_shell.gd")

var shell
var out_dir := ""


func _init() -> void:
	call_deferred("_run")


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return d if v == "" else v


func _run() -> void:
	shell = load("res://shell/main.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	if shell._run_save != null:
		shell._run_save.close()
		shell._run_save = null
	shell.audio.sfx_on = false
	shell.audio.set_music(false)
	out_dir = _env("SCREENS_OUT", "user://screens")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var want := _env("SCREENS", "all").split(",", false)
	var all := want.has("all")
	var seed_v := int(_env("SCREENS_SEED", "4242"))
	if all or want.has("menu"):
		shell.screen = "menu"
		shell.mode = "normal"
		await _shot("menu")
		shell.mode = "settings"
		await _shot("settings")
		shell.mode = "normal"
	if all or want.has("intro"):
		_fresh(seed_v)
		shell.mode = "intro"
		await _shot("intro")
	if all or want.has("tutorial"):
		await _tutorial()
	if all or want.has("play") or want.has("tooltip"):
		_fresh(seed_v)
		await _shot("play_start")
		_bot_play(int(_env("SCREENS_STEPS", "40")), func(g): return g.phase != "play")
		await _shot("play_mid")
		if all or want.has("tooltip"):
			# hold the first machine the camera shows (one off screen has
			# nothing under the finger to hold)
			for e in shell.game.enemies:
				var at: Vector2 = shell._tile_rect(e["pos"]).get_center()
				if shell._cam_zone.has_point(at):
					shell._show_tooltip(at)
					await _shot("tooltip_enemy")
					shell.tooltip = []
					break
	if all or want.has("camera"):
		# the camera's states: the default follow view mid-floor, a pinch in,
		# a pinch all the way out, and the whole-floor peek
		_fresh(seed_v)
		_bot_play(int(_env("SCREENS_STEPS", "40")), func(g): return g.phase != "play")
		var keep: float = shell.cam_cols
		shell._cam_reset()
		await _shot("cam_follow")
		shell.cam_cols = shell.CAM_COLS_MIN
		shell._cam = {}
		await _shot("cam_close")
		shell.cam_cols = shell.CAM_COLS_MAX
		shell._cam = {}
		await _shot("cam_far")
		shell.cam_cols = keep
		shell.cam_overview = true
		shell._cam = {}
		await _shot("cam_peek")
		shell._cam_reset()
	if all or want.has("shop"):
		_fresh(seed_v)
		shell.game.bloom = 30
		shell.game.player["pos"] = shell.game.map["shrine"]
		shell.mode = "shop"
		await _shot("shop")
	if all or want.has("draft"):
		_fresh(seed_v)
		_bot_play(3000, func(g): return g.phase == "draft")
		if shell.game.phase == "draft":
			await _shot("draft")
			shell.game.player["kit"] = ["mycelium_dash", "solar_lance", "seed_bomb", "vine_whip", "thorn_shield"]
			shell.mode = "draft_drop"
			shell.mode_pick = 0
			await _shot("drop")
			shell.mode = "normal"
		else:
			print("SKIP draft: the bot never reached one on seed %d" % seed_v)
	if all or want.has("legend"):
		_fresh(seed_v)
		shell.mode = "help"
		shell.help_page = 0
		await _shot("legend")
	if all or want.has("log"):
		_fresh(seed_v)
		_bot_play(30, func(g): return g.phase != "play")
		shell.mode = "log"
		await _shot("log")
	if all or want.has("died"):
		_fresh(seed_v)
		shell.game.over = true
		shell.game.death_cause = "drill_bot"
		await _shot("died")
	if all or want.has("won"):
		_fresh(seed_v)
		shell.game.over = true
		shell.game.won = true
		await _shot("won")
	print("screens written to %s" % ProjectSettings.globalize_path(out_dir))
	quit()


## A run on `seed_v` with nothing playing: no reel, no fade, no banner.
func _fresh(seed_v: int) -> void:
	shell._reset_reel()
	shell.screen = "game"
	shell.game = Game.new(seed_v, {})
	shell.seed_v = seed_v
	shell._game_is_run = false
	shell.mode = "normal"
	shell.tooltip = []
	shell.flash = ""
	shell.log_lines = []
	shell._floor_fade_ms = -99999
	shell._banner_ms = -99999


## Play up to `n` optimizer actions through the shell (so the log fills the
## way a player's would), stopping early when `stop` says so.
func _bot_play(n: int, stop: Callable) -> void:
	var bot = Roster.make("optimizer", int(shell.seed_v))
	for i in n:
		var g = shell.game
		if g.over or stop.call(g):
			break
		shell._act(bot.choose_action(g.snapshot(), g.legal_actions()))
		shell._reel = {}
		shell._floor_fade_ms = -99999
		shell._banner_ms = -99999
		shell.mode = "normal"


func _tutorial() -> void:
	shell._start_tutorial()
	var i := 0
	while not shell.tut_done and i < 400:
		var st: int = shell.tut_step
		await _shot("tut_%02d" % st)
		var guard := 0
		while shell.tut_step == st and not shell.tut_done and guard < 60:
			shell._act(ShellTest._solve(shell))
			shell._reel = {}
			shell._banner_ms = -99999
			guard += 1
		i += 1
	await _shot("tut_done")


func _shot(name: String) -> void:
	for f in 2:
		shell.queue_redraw()
		await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("%-16s -> %s" % [name, ProjectSettings.globalize_path(path)])
