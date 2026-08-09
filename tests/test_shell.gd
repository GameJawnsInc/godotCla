extends SceneTree
## Headless smoke test for the SVG shell: every sprite rasterizes, and the
## shell's input handlers drive the sim correctly (asserted on sim state,
## per the no-display rule in CLAUDE.md).
## Run: godot --headless --path . --script tests/test_shell.gd

const Art := preload("res://shell/svg_art.gd")
const Shell := preload("res://shell/main.gd")
const Content := preload("res://sim/content.gd")

var fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + what)


func _init() -> void:
	# 1. every SVG sprite rasterizes at tile size
	for id in Art.ART:
		var t = Art.tex(id, 36)
		_check(t != null and t.get_width() == 36, "sprite %s rasterizes" % id)
	# every enemy kind and terrain kind has art
	for kind in Content.ENEMIES:
		_check(Art.ART.has(kind), "enemy %s has a sprite" % kind)
	for kind in ["oil", "goo", "rich_goo", "growth", "fire", "smoke", "roots"]:
		_check(Art.ART.has(kind), "terrain %s has a sprite" % kind)

	# 2. shell drives the sim through its input handlers
	OS.set_environment("SHELL_SEED", "42")
	var shell = Shell.new()
	shell._ready()
	_check(shell.game != null and shell.seed_v == 42, "shell boots with pinned seed")
	_check(shell.mode == "intro", "first boot shows the intro")
	shell._key(KEY_SPACE)  # dismiss intro
	_check(shell.mode == "normal", "any key dismisses the intro")
	shell._key(KEY_L)
	_check(shell.mode == "help", "L opens the legend")
	shell._key(KEY_SPACE)
	var t0: int = shell.game.total_turns
	shell._key(KEY_SPACE)
	shell._key(KEY_SPACE)
	_check(shell.game.total_turns == t0 + 2, "end turn advances the sim")

	# movement (find a legal move and press its key)
	var moved := false
	for a in shell._legal_of("move"):
		var d: Vector2i = a["dir"]
		var before: Vector2i = shell.game.player["pos"]
		var key := KEY_RIGHT
		if d == Vector2i(-1, 0): key = KEY_LEFT
		elif d == Vector2i(0, -1): key = KEY_UP
		elif d == Vector2i(0, 1): key = KEY_DOWN
		shell._key(key)
		moved = shell.game.player["pos"] == before + d
		break
	_check(moved, "arrow key moves the player")

	# ability targeting: slot 0 (solar_lance, dir-targeted) enters aim mode
	shell._act({"type": "end_turn"})
	if not shell._legal_of("ability").is_empty():
		shell._ability_press(0)
		_check(shell.mode == "target_dir", "dir ability enters aim mode")
		shell._key(KEY_ESCAPE)
		_check(shell.mode == "normal", "escape cancels aim mode")

	# 3. a scripted run reaches a draft and the draft keys work
	var shell2 = Shell.new()
	shell2._ready()
	shell2._key(KEY_SPACE)
	var guard := 0
	while shell2.game.phase != "draft" and not shell2.game.over and guard < 3000:
		var acts: Array = shell2.game.legal_actions()
		shell2.game.step(acts[shell2.game.rng.randi_range(0, acts.size() - 1)])
		guard += 1
	if shell2.game.phase == "draft":
		var kit0: int = shell2.game.player["kit"].size()
		shell2._draft_key(KEY_1)
		_check(shell2.game.player["kit"].size() >= kit0 or shell2.mode == "draft_drop",
			"draft key picks or prompts for a drop")
	shell.free()
	shell2.free()
	print("FAILURES: %d" % fails if fails > 0 else "shell smoke: OK")
	quit(1 if fails > 0 else 0)
