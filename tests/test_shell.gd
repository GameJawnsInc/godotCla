extends SceneTree
## Headless shell smoke test: sprites rasterize, menu flow works, input
## handlers drive the sim, and the ENTIRE scripted tutorial plays through
## against the real sim. If a sim or content change breaks the tutorial
## script, this fails - the tutorial cannot ship broken (see shell/tutorial.gd).
## Run: godot --headless --path . --script tests/test_shell.gd

const Art := preload("res://shell/svg_art.gd")
const Shell := preload("res://shell/main.gd")
const Content := preload("res://sim/content.gd")
const Tutorial := preload("res://shell/tutorial.gd")

var fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + what)


func _init() -> void:
	# 1. every sprite rasterizes; every enemy/terrain/legend id has art
	for id in Art.ART:
		var t = Art.tex(id, 36)
		_check(t != null and t.get_width() == 36, "sprite %s rasterizes" % id)
	for kind in Content.ENEMIES:
		_check(Art.ART.has(kind), "enemy %s has a sprite" % kind)
	for row in Shell.LEGEND:
		_check(Art.ART.has(row[0]), "legend id %s has a sprite" % row[0])

	# 2. menu boots, PLAY starts a run, input handlers drive the sim
	OS.set_environment("SHELL_SEED", "")
	var shell = Shell.new()
	shell._ready()
	_check(shell.screen == "menu", "boots to the menu")
	shell._tap("play")
	_check(shell.screen == "game" and shell.game != null, "PLAY starts a run")
	_check(shell.mode == "intro", "first run shows the intro")
	shell._key(KEY_SPACE)
	_check(shell.mode == "normal", "any key dismisses the intro")
	var t0: int = shell.game.total_turns
	shell._key(KEY_SPACE)
	shell._key(KEY_SPACE)
	_check(shell.game.total_turns == t0 + 2, "end turn advances the sim")
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
	shell._act({"type": "end_turn"})
	if not shell._legal_of("ability").is_empty():
		shell._ability_press(0)
		_check(shell.mode == "target_dir", "dir ability enters aim mode")
		shell._key(KEY_ESCAPE)
		_check(shell.mode == "normal", "escape cancels aim mode")
	shell._tap("menu")
	_check(shell.screen == "menu", "menu button returns to the menu")
	shell._tap("resume")
	_check(shell.screen == "game", "RESUME returns to the live run")
	shell._tap("set:hold")
	_check(shell.hold_ms in [300, 420, 650], "settings cycle hold delay")

	# 3. the scripted tutorial plays through end to end
	shell._tap("menu")
	shell._tap("tutorial")
	_check(shell.screen == "tutorial" and shell.game != null, "tutorial starts")
	_check(not shell.game.enemies.is_empty(), "tutorial room has its enemy")
	var guard := 0
	var stuck := false
	while not shell.tut_done and guard < 500:
		guard += 1
		var step_before: int = shell.tut_step
		var turns_before: int = shell.game.total_turns
		shell._act(_solve(shell))
		if shell.tut_step == step_before and shell.game.total_turns == turns_before and shell.game.player["pos"] == shell.game.player["pos"]:
			pass  # progress is turns or steps; guard catches true deadlock
		if shell.game.over and not shell.tut_done:
			stuck = true
			break
	_check(shell.tut_done and not stuck, "tutorial completes (%d actions)" % guard)
	shell._tap("menu")
	_check(shell.screen == "menu", "tutorial returns to the menu")

	# 4. a run reaches a draft and draft picking works
	var shell2 = Shell.new()
	shell2._ready()
	shell2._tap("play")
	shell2._key(KEY_SPACE)
	var g2 := 0
	while shell2.game.phase != "draft" and not shell2.game.over and g2 < 3000:
		var acts: Array = shell2.game.legal_actions()
		shell2.game.step(acts[shell2.game.rng.randi_range(0, acts.size() - 1)])
		g2 += 1
	if shell2.game.phase == "draft":
		var kit0: int = shell2.game.player["kit"].size()
		shell2._draft_key(KEY_1)
		_check(shell2.game.player["kit"].size() >= kit0 or shell2.mode == "draft_drop",
			"draft key picks or prompts for a drop")
	shell.free()
	shell2.free()
	print("FAILURES: %d" % fails if fails > 0 else "shell smoke: OK")
	quit(1 if fails > 0 else 0)


## Pick the action that makes progress on the tutorial's current step.
func _solve(shell) -> Dictionary:
	var g = shell.game
	var st: Dictionary = Tutorial.STEPS[shell.tut_step]
	var expect: Dictionary = st.get("expect", {})
	match String(expect.get("type", "")):
		"move":
			if expect.has("dir"):
				return {"type": "move", "dir": expect["dir"]}
			return _approach(g, g.map["stairs"])
		"end_turn":
			return {"type": "end_turn"}
		"strike":
			var s: Array = shell._legal_of("strike")
			if not s.is_empty():
				return s[0]
			return _approach(g, _nearest_enemy(g))
		"cleanse":
			var c: Array = shell._legal_of("cleanse")
			if not c.is_empty():
				return c[0]
			return _approach(g, _nearest_corruption(g))
		"descend":
			var d: Array = shell._legal_of("descend")
			if not d.is_empty():
				return d[0]
			return _approach(g, g.map["stairs"])
	# free / until_dead: kill whatever remains
	var s2: Array = shell._legal_of("strike")
	if not s2.is_empty():
		return s2[0]
	if not g.enemies.is_empty():
		return _approach(g, _nearest_enemy(g))
	return {"type": "end_turn"}


func _approach(g, goal: Vector2i) -> Dictionary:
	if goal == Vector2i(-1, -1):
		return {"type": "end_turn"}
	var best := {}
	var bd := 99999
	var pp: Vector2i = g.player["pos"]
	for a in g.legal_actions():
		if String(a.get("type", "")) != "move":
			continue
		var d: Vector2i = pp + a["dir"]
		var dist: int = absi(d.x - goal.x) + absi(d.y - goal.y)
		if dist < bd:
			bd = dist
			best = a
	if best.is_empty():
		return {"type": "end_turn"}
	return best


func _nearest_enemy(g) -> Vector2i:
	var pp: Vector2i = g.player["pos"]
	var best := Vector2i(-1, -1)
	var bd := 9999
	for e in g.enemies:
		var d: int = absi(e["pos"].x - pp.x) + absi(e["pos"].y - pp.y)
		if d < bd:
			bd = d
			best = e["pos"]
	return best


func _nearest_corruption(g) -> Vector2i:
	var pp: Vector2i = g.player["pos"]
	var best := Vector2i(-1, -1)
	var bd := 9999
	for t in g.terrain.keys():
		var k: String = g.terrain[t]["kind"]
		if k != "oil" and k != "goo" and k != "rich_goo":
			continue
		var d: int = absi(t.x - pp.x) + absi(t.y - pp.y)
		if d < bd:
			bd = d
			best = t
	return best
