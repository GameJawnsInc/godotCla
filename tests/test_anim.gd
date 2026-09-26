extends SceneTree
## Animation suite (docs/SHELL.md "Animations"), headless. The director
## (shell/anim.gd) is pure data over snapshots, so everything a reel promises
## can be asserted without a display:
##   1. coverage: every effect op an ability can carry, every enemy intent
##      type, has a builder - a new op or intent with no animation fails here,
##      the way the content lint fails an unknown op
##   2. every staged scene (tests/anim_scenes.gd: the tender's verbs, all
##      Content.ABILITIES rows, every intent) plans a reel that is pure
##      (inputs untouched), deterministic, lands every creature exactly where
##      the post snapshot has it, hides the dead and the not-yet-spawned,
##      flips every changed tile inside the reel, draws the ability's verb,
##      and stays inside the time budget at each speed
##   3. every clip of every reel paints through a recording canvas at five
##      points of its life with finite coordinates, and every pose is sane
##   4. the shell plays a reel on each step, cycles and persists the setting,
##      and holds the HP a blow has not reached yet
##   5. a soak over real bot-played runs (ANIM_SOAK_SEEDS, default 4 seeds x
##      2 personas): every step's reel lands every creature, hides the dead,
##      flips its tiles, paints finite geometry and fits the budget - the
##      enemy-phase event attribution meets whole packs, bosses and deaths
##      it was never staged for
## Run: godot --headless --path . --script tests/test_anim.gd
## To SEE the animations: tests/capture_anim.gd (needs xvfb-run).

const Anim := preload("res://shell/anim.gd")
const L := preload("res://shell/anim_lib.gd")
const Paint := preload("res://shell/anim_paint.gd")
const FxEnemy := preload("res://shell/fx_enemy.gd")
const Scenes := preload("res://tests/anim_scenes.gd")
const Content := preload("res://sim/content.gd")
const ContentLint := preload("res://tests/test_content.gd")
const Shell := preload("res://shell/main.gd")
const Game := preload("res://sim/game.gd")
const Roster := preload("res://bots/roster.gd")
const Tutorial := preload("res://shell/tutorial.gd")

## Reel budgets (ms). Numbers keep their reading time at every speed, so the
## quick budget is the full one scaled plus a float's life.
const MAX_LEN_FULL := 2400
const SEG_KINDS := ["path", "squash", "lunge", "recoil", "tint", "flash", "cast", "struggle", "die", "pop",
	"warp_out", "warp_in", "hide", "shake"]

var fails := 0
var checks := 0
var errs: ErrCount


## Counts every engine/script error raised while the suite runs: a GDScript
## runtime error aborts only the function it happens in, so without this a
## builder that dies halfway through a reel would still let the suite pass.
class ErrCount:
	extends Logger
	var n := 0
	var first: Array = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		n += 1
		if first.size() < 5:
			first.append("%s:%d %s %s" % [file, line, code, rationale])

	func _log_message(message: String, error: bool) -> void:
		pass


class RecCanvas:
	extends RefCounted
	var calls := 0
	var bad := 0
	var sig := ""  # every call's arguments, to compare two paints exactly

	func _v(args: Array) -> void:
		calls += 1
		sig += str(args) + ";"
		for a in args:
			if a is Vector2 and not (is_finite(a.x) and is_finite(a.y)):
				bad += 1
			elif a is float and not is_finite(a):
				bad += 1
			elif a is PackedVector2Array:
				for q in a:
					if not (is_finite(q.x) and is_finite(q.y)):
						bad += 1

	func draw_circle(p, r, col, filled = true, width = -1.0, aa = false) -> void:
		_v([p, float(r)])

	func draw_line(a, b, col, width = -1.0, aa = false) -> void:
		_v([a, b, float(width)])

	func draw_arc(c, r, a0, a1, n, col, width = -1.0, aa = false) -> void:
		_v([c, float(r), float(a0), float(a1), float(width)])

	func draw_polyline(pts, col, width = -1.0, aa = false) -> void:
		_v([pts, float(width)])

	func draw_colored_polygon(pts, col, uvs = PackedVector2Array(), tex = null) -> void:
		_v([pts])

	func draw_polygon(pts, cols, uvs = PackedVector2Array(), tex = null) -> void:
		_v([pts])

	func draw_rect(r, col, filled = true, width = -1.0, aa = false) -> void:
		_v([r.position, r.size])

	func draw_string(font, p, s, align = 0, w = -1.0, size = 16, col = Color.WHITE) -> void:
		_v([p])

	func draw_texture(tex, p, mod = Color.WHITE) -> void:
		_v([p])

	func draw_set_transform(p, rot = 0.0, sc = Vector2.ONE) -> void:
		_v([p, float(rot), sc])


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL: " + what)


func _init() -> void:
	errs = ErrCount.new()
	OS.add_logger(errs)
	_check_coverage()
	var n := 0
	for sc in Scenes.all_scenes():
		_check_scene(sc)
		n += 1
	_check_idle()
	_check_attribution()
	_check_shell()
	_check_soak()
	_check(errs.n == 0, "no engine or script errors while planning and painting (%d: %s)" % [errs.n, str(errs.first)])
	print("anim: %d scenes, %d checks" % [n, checks])
	if fails > 0:
		print("anim: %d FAILED" % fails)
		quit(1)
	else:
		print("anim: OK")
		quit(0)


## --- 1. coverage ----------------------------------------------------------------
func _ops_of(effects: Array, into: Dictionary) -> void:
	for eff in effects:
		into[String(eff["op"])] = true
		_ops_of(eff.get("then", []), into)


func _check_coverage() -> void:
	var ops := {}
	for aid in Content.ABILITIES:
		_ops_of(Content.ABILITIES[aid]["effects"], ops)
	for op in ContentLint.OP_KEYS:
		ops[op] = true
	for op in ops:
		_check(Anim.family_for_op(op) != null, "effect op '%s' has an animation builder" % op)
	for fam in Anim.OP_FAMILIES:
		for op in fam.OPS:
			_check(ops.has(op), "builder op '%s' is a real effect op (dead vocabulary otherwise)" % op)
	for it in ContentLint.INTENT_TYPES:
		_check(FxEnemy.INTENTS.has(it), "intent '%s' has an animation builder" % it)
	for it in [Anim.BLOCKED_VERB, Anim.SCREENED_VERB]:
		_check(FxEnemy.INTENTS.has(it), "pseudo-intent '%s' has a builder" % it)
	# every clip kind is owned exactly once
	var owner := {}
	for k in Paint.CORE_KINDS:
		owner[k] = "core"
	for fam in Paint.FAMILIES:
		for k in fam.KINDS:
			_check(not owner.has(k), "clip kind '%s' has one painter (also %s)" % [k, owner.get(k, "")])
			owner[k] = fam.resource_path
	for fam in Anim.OP_FAMILIES:
		_check(Paint.FAMILIES.has(fam), "%s is painted" % fam.resource_path)
	_check(Scenes.INTENT_SCENES.size() >= ContentLint.INTENT_TYPES.size() - 1 + 2,
		"every intent (bar idle) and both failures have a staged scene")
	for it in ContentLint.INTENT_TYPES:
		if it != "idle":
			_check(Scenes.INTENT_SCENES.has(it), "intent '%s' has a staged scene" % it)


## --- 2 + 3. every scene ---------------------------------------------------------
func _check_scene(sc: Dictionary) -> void:
	var nm := String(sc.get("name", "?"))
	if sc.is_empty() or sc.get("action") == null:
		_check(false, "%s: scene stages a legal action" % nm)
		return
	var g = sc["game"]
	var pre: Dictionary = g.snapshot()
	var pre_s := str(pre)
	var evs: Array = g.step(sc["action"])
	var evs_s := str(evs)
	var post: Dictionary = g.snapshot()
	var post_s := str(post)
	for ev in evs:
		_check(String(ev.get("t", "")) != "illegal", "%s: the staged action is legal (%s)" % [nm, str(ev)])
	var reel := Anim.plan(pre, sc["action"], evs, post)
	_check(str(pre) == pre_s and str(post) == post_s and str(evs) == evs_s, "%s: plan() leaves its inputs untouched" % nm)
	_check(str(Anim.plan(pre, sc["action"], evs, post)) == str(reel), "%s: plan() is deterministic" % nm)
	var ln := int(reel["len"])
	_check(ln > 0, "%s: the step animates (len %d)" % [nm, ln])
	_check(ln <= MAX_LEN_FULL, "%s: reel fits the budget (%d <= %d ms)" % [nm, ln, MAX_LEN_FULL])
	var end_t := float(ln) + 1.0
	# landing: every creature ends exactly where the sim put it
	for e in post["enemies"]:
		var cur := Vector2(e["pos"])
		_check(Anim.pos_at(reel, e["id"], end_t, cur) == cur, "%s: enemy %d lands on its post tile" % [nm, e["id"]])
		var ps := Anim.pose(reel, e["id"], end_t, cur)
		_check(ps["visible"] and is_equal_approx(float(ps["alpha"]), 1.0), "%s: enemy %d is visible at the end" % [nm, e["id"]])
	_check(Anim.pos_at(reel, "player", end_t, Vector2(post["player"]["pos"])) == Vector2(post["player"]["pos"]),
		"%s: the tender lands on its post tile" % nm)
	var pps := Anim.pose(reel, "player", end_t, Vector2(post["player"]["pos"]))
	_check(pps["visible"] == (not bool(post.get("over", false)) or bool(post.get("won", false))),
		"%s: the tender is visible at the end unless dead" % nm)
	# the departed are ghosts that vanish; the arrived pop in
	var post_ids := {}
	for e in post["enemies"]:
		post_ids[e["id"]] = true
	var pre_ids := {}
	for e in pre["enemies"]:
		pre_ids[e["id"]] = true
		if not post_ids.has(e["id"]):
			var found := false
			for gh in reel["ghosts"]:
				if gh["id"] == e["id"]:
					found = true
					_check(not Anim.pose(reel, e["id"], end_t, Vector2(gh["pos"]))["visible"], "%s: ghost %d vanishes" % [nm, e["id"]])
					_check(Anim.pose(reel, e["id"], 0.0, Vector2(gh["pos"]))["visible"], "%s: ghost %d is there at t=0" % [nm, e["id"]])
			_check(found, "%s: enemy %d that left the board is drawn as a ghost" % [nm, e["id"]])
	for e in post["enemies"]:
		if not pre_ids.has(e["id"]):
			_check(reel["spawns"].has(e["id"]), "%s: new enemy %d has a spawn time" % [nm, e["id"]])
			_check(not Anim.pose(reel, e["id"], -1.0, Vector2(e["pos"]))["visible"], "%s: new enemy %d is hidden before it spawns" % [nm, e["id"]])
	# terrain flips inside the reel
	for p in reel["tswap"]:
		var sw: Dictionary = reel["tswap"][p]
		_check(sw.has("t") and int(sw["t"]) >= 0 and int(sw["t"]) <= ln, "%s: tile %s flips inside the reel" % [nm, str(p)])
		_check(String(Anim.terrain_at(reel, p, end_t)) == L.tkind(post, p), "%s: tile %s ends as the post kind" % [nm, str(p)])
	# the verb: an ability draws at least one clip of each family its ops use
	var kinds := {}
	for cl in reel["clips"]:
		kinds[String(cl["kind"])] = true
		_check(Paint.known(String(cl["kind"])), "%s: clip kind '%s' has a painter" % [nm, cl["kind"]])
		_check(int(cl["dur"]) > 0 and ["ground", "air"].has(String(cl.get("layer", ""))), "%s: clip '%s' is well formed" % [nm, cl["kind"]])
	if nm.begins_with("ability:"):
		var aid := nm.substr(8)
		var ops := {}
		_ops_of(Content.ABILITIES[aid]["effects"], ops)
		for op in ops:
			if op == "status_target" or op == "plant_origin":
				continue  # riders: drawn by the generic status pop / the sprout they leave
			var fam = Anim.family_for_op(op)
			if fam == null:
				continue  # already failed in coverage
			var drew := false
			for k in kinds:
				if fam.KINDS.has(k):
					drew = true
			_check(drew, "%s: op '%s' draws its verb" % [nm, op])
	if nm.begins_with("intent:"):
		var moved_any: bool = reel["tracks"].size() > 0
		var enemy_clip := false
		for k in kinds:
			if FxEnemy.KINDS.has(k):
				enemy_clip = true
		_check(moved_any or enemy_clip, "%s: the intent is drawn" % nm)
	for key in reel["tracks"]:
		for s in reel["tracks"][key]:
			_check(SEG_KINDS.has(String(s["kind"])), "%s: segment kind '%s' is known" % [nm, s["kind"]])
	# paint every clip at five points of its life through a recording canvas
	var V := {"ts": 40.0, "ox": 10.0, "oy": 20.0, "font": ThemeDB.fallback_font, "now": 12345.0}
	for cl in reel["clips"]:
		var cv := RecCanvas.new()
		for k in [0.0, 0.25, 0.5, 0.75, 1.0]:
			Paint.paint_clip(cv, cl, k, V)
		_check(cv.bad == 0, "%s: clip '%s' paints finite geometry" % [nm, cl["kind"]])
		var mid := RecCanvas.new()
		Paint.paint_clip(mid, cl, 0.4, V)
		_check(mid.calls > 0, "%s: clip '%s' draws something mid-life" % [nm, cl["kind"]])
	# poses stay sane through the whole reel
	for key in reel["tracks"]:
		for i in 25:
			var t := float(ln) * float(i) / 24.0
			var ps := Anim.pose(reel, key, t, Vector2(4, 4))
			var ok: bool = is_finite(ps["pos"].x) and is_finite(ps["off"].x) and float(ps["sx"]) > 0.0 \
				and float(ps["sy"]) > 0.0 and float(ps["alpha"]) >= 0.0 and float(ps["alpha"]) <= 1.0
			_check(ok, "%s: pose of %s at %dms is sane" % [nm, str(key), int(t)])
	# speeds: quick keeps the order of things and shortens them; off keeps
	# only the numbers
	var quick := Anim.plan(pre, sc["action"], evs, post, Anim.SPEEDS["quick"])
	# speed invariance: a painter reads time as k * span, so the same clip at
	# the same point of its life draws the same thing at every speed - a
	# painter that read k * dur would draw its impact late at quick
	if quick["clips"].size() == reel["clips"].size():
		for ci in reel["clips"].size():
			var a := RecCanvas.new()
			var b := RecCanvas.new()
			for kk in [0.2, 0.5, 0.8]:
				Paint.paint_clip(a, reel["clips"][ci], kk, V)
				Paint.paint_clip(b, quick["clips"][ci], kk, V)
			_check(a.sig == b.sig, "%s: clip '%s' paints the same at quick speed" % [nm, reel["clips"][ci]["kind"]])
	else:
		_check(false, "%s: quick plans the same clips as full" % nm)
	_check(int(quick["len"]) <= int(float(ln) * 0.6) + L.T_FLOAT + 20, "%s: quick is quicker (%d vs %d)" % [nm, quick["len"], ln])
	var off := Anim.plan(pre, sc["action"], evs, post, Anim.SPEEDS["off"])
	var only_numbers: bool = off["tracks"].is_empty() and off["ghosts"].is_empty()
	for cl in off["clips"]:
		if String(cl["kind"]) != "float" or int(cl["t0"]) != 0:
			only_numbers = false
	_check(only_numbers, "%s: 'off' keeps only the numbers" % nm)
	# HP: a bar holds its pre-step value until the blow lands
	for e in pre["enemies"]:
		var pe = L.enemy_by_id(post, e["id"])
		if pe != null and int(pe["hp"]) < int(e["hp"]):
			_check(Anim.hp_shown(reel, e["id"], -1.0, int(pe["hp"])) == int(e["hp"]), "%s: enemy %d shows its old HP before the hit" % [nm, e["id"]])
			_check(Anim.hp_shown(reel, e["id"], end_t, int(pe["hp"])) == int(pe["hp"]), "%s: enemy %d shows its new HP after" % [nm, e["id"]])


func _check_idle() -> void:
	var styles := {}
	for kind in Content.ENEMIES:
		styles[L.idle_style(kind)] = true
	styles["player"] = true
	for st in styles:
		for i in 12:
			var d := Anim.idle(st, 0.37 * float(i), 1000.0 + 97.0 * float(i))
			_check(is_finite(float(d["lift"])) and float(d["sx"]) > 0.8 and float(d["sy"]) > 0.8, "idle '%s' stays in bounds" % st)


## --- 4. the shell plays reels -----------------------------------------------------
func _check_shell() -> void:
	var sh = Shell.new()
	sh._ready()
	if sh._run_save != null:
		sh._run_save.close()
		sh._run_save = null
	sh._game_is_run = false
	var keep_mode: String = sh.anim_mode
	var sc: Dictionary = Scenes.basic_scene("strike")
	sh.game = sc["game"]
	sh.screen = "game"
	sh.mode = "normal"
	sh.anim_mode = "full"
	sh.clock_override = 50000
	sh._act(sc["action"])
	_check(not sh._reel.is_empty() and Anim.playing(sh._reel, sh._reel_t()), "a step starts a reel in the shell")
	sh.clock_override = 50000 + int(sh._reel["len"]) + 100
	_check(not Anim.playing(sh._reel, sh._reel_t()), "the reel ends")
	# a second step while numbers are in the air carries them over
	var sc2: Dictionary = Scenes.basic_scene("strike")
	sh.game = sc2["game"]
	sh.clock_override = 60000
	sh._act(sc2["action"])
	sh.clock_override = 60100
	sh._act({"type": "end_turn"})
	var floats := 0
	for cl in sh._reel["clips"]:
		if String(cl["kind"]) == "float" and int(cl["t0"]) < 0:
			floats += 1
	_check(floats >= 1, "numbers still in the air survive the next step (%d carried)" % floats)
	# the setting cycles full -> quick -> off -> full and is read by plan()
	sh.anim_mode = "full"
	sh._tap("set:anim")
	_check(sh.anim_mode == "quick", "animations: full -> quick")
	sh._tap("set:anim")
	_check(sh.anim_mode == "off", "animations: quick -> off")
	var sc3: Dictionary = Scenes.basic_scene("move")
	sh.game = sc3["game"]
	sh._act(sc3["action"])
	_check(sh._reel.get("tracks", {}).is_empty(), "animations off: the tender does not slide")
	sh._tap("set:anim")
	_check(sh.anim_mode == "full", "animations: off -> full")
	# the setting persists: a fresh shell reads it back
	sh.anim_mode = "quick"
	sh._save_settings()
	var sh2 = Shell.new()
	sh2._load_settings()
	_check(sh2.anim_mode == "quick", "the animation setting is saved and read back")
	sh2.free()
	sh.anim_mode = "full"
	# an out-of-charge tap ends the turn and then moves: ONE input, so the
	# enemy turn's reel plays first and the move is chained after it
	var mv: Dictionary = Scenes.intent_scene("move")
	sh.game = mv["game"]
	sh.game.player["charge"] = 0
	sh.clock_override = 70000
	sh._move_or_strike(Vector2i(0, -1))
	var tr: Dictionary = sh._reel.get("tracks", {})
	var moved_enemy := false
	for key in tr:
		if not (key is String):
			moved_enemy = true
	_check(moved_enemy and tr.has("player"), "an out-of-charge move chains the enemy turn's reel and the move (%s)" % str(tr.keys()))
	_check(Anim.pos_at(sh._reel, "player", float(sh._reel["len"]) + 1.0, Vector2(sh.game.player["pos"])) == Vector2(sh.game.player["pos"]),
		"the chained reel lands the tender")
	# the killing blow: the sheet waits for it, a tap during it only finishes
	# it, and the next game never inherits it
	var dth: Dictionary = Scenes.basic_scene("death")
	sh.game = dth["game"]
	sh._game_is_run = false
	sh.clock_override = 80000
	sh._act(dth["action"])
	_check(sh.game.over and Anim.playing(sh._reel, sh._reel_t()), "the death reel plays")
	var dead_game = sh.game
	sh._click(Vector2(5, 5))
	_check(sh.game == dead_game and not Anim.playing(sh._reel, sh._reel_t()),
		"a tap during the death reel finishes it and does not start a new run")
	sh._new_game()
	_check(sh._reel.is_empty(), "a new game starts with no reel")
	_check(Anim.pose(sh._reel, "player", sh._reel_t(), Vector2(sh.game.player["pos"]))["visible"], "the new run's tender is visible")
	# a descent has no reel: the floor fade is the animation
	var ff: Dictionary = Tutorial.room_config("#######\n#.@>..#\n#.....#\n#######", Scenes.FDEF)
	var dg = Game.new(7, {"kit": ["solar_lance"], "fixed_floor": ff})
	dg.greened = maxi(dg.green_need, 0)
	dg.player["pos"] = dg.map["stairs"]
	sh.game = dg
	sh.clock_override = 90000
	sh._act({"type": "descend"})
	_check(int(sh._reel.get("len", 0)) == 0, "descending onto the draft plays no reel")
	if dg.phase == "draft":
		sh._act({"type": "draft", "pick": -1})  # the floor changes on the draft
	_check(dg.floor_num == 2 and sh._reel.is_empty() and sh._floor_fade_ms == 90000,
		"a descent plays the floor fade, not a reel (floor %d)" % dg.floor_num)
	sh.anim_mode = keep_mode
	sh._save_settings()
	sh.clock_override = -1
	sh.free()


## --- 5. soak: real runs ----------------------------------------------------------
func _check_soak() -> void:
	var seeds := 4
	if OS.get_environment("ANIM_SOAK_SEEDS") != "":
		seeds = int(OS.get_environment("ANIM_SOAK_SEEDS"))
	var steps := 0
	var worst := 0
	var worst_at := ""
	var V := {"ts": 40.0, "ox": 0.0, "oy": 0.0, "font": ThemeDB.fallback_font, "now": 0.0}
	var before := fails
	for persona in ["optimizer", "wanderer"]:
		for sd in range(1, seeds + 1):
			var g = Game.new(sd)
			var bot = Roster.make(persona, sd)
			if bot.has_method("set_sim"):
				bot.set_sim(g)
			for n in 400:
				if g.over:
					break
				var pre: Dictionary = g.snapshot()
				var a: Dictionary = bot.choose_action(pre, g.legal_actions())
				var evs: Array = g.step(a)
				var post: Dictionary = g.snapshot()
				var reel := Anim.plan(pre, a, evs, post)
				steps += 1
				var tag := "%s s%d step %d (%s)" % [persona, sd, n, String(a.get("type", ""))]
				var ln := int(reel["len"])
				if ln > worst:
					worst = ln
					worst_at = tag
				_soak_one(tag, reel, pre, post, V)
				if fails - before > 20:
					print("soak: stopping early after 20 failures")
					return
	print("soak: %d real steps, longest reel %d ms (%s)" % [steps, worst, worst_at])
	_check(worst <= MAX_LEN_FULL, "soak: every real reel fits the budget (worst %d ms at %s)" % [worst, worst_at])


func _soak_one(tag: String, reel: Dictionary, pre: Dictionary, post: Dictionary, V: Dictionary) -> void:
	if reel["clips"].is_empty() and reel["tracks"].is_empty():
		return
	var end_t := float(reel["len"]) + 1.0
	for e in post["enemies"]:
		var cur := Vector2(e["pos"])
		if Anim.pos_at(reel, e["id"], end_t, cur) != cur or not Anim.pose(reel, e["id"], end_t, cur)["visible"]:
			_check(false, "soak %s: enemy %d ends on its post tile, visible" % [tag, e["id"]])
	var pp := Vector2(post["player"]["pos"])
	if Anim.pos_at(reel, "player", end_t, pp) != pp:
		_check(false, "soak %s: the tender ends on its post tile" % tag)
	var alive := {}
	for e in post["enemies"]:
		alive[e["id"]] = true
	for gh in reel["ghosts"]:
		if alive.has(gh["id"]) or Anim.pose(reel, gh["id"], end_t, Vector2(gh["pos"]))["visible"]:
			_check(false, "soak %s: ghost %d is really gone and vanishes" % [tag, gh["id"]])
	for p in reel["tswap"]:
		if String(Anim.terrain_at(reel, p, end_t)) != L.tkind(post, p):
			_check(false, "soak %s: tile %s ends as the post kind" % [tag, str(p)])
	for cl in reel["clips"]:
		var cv := RecCanvas.new()
		Paint.paint_clip(cv, cl, 0.5, V)
		if cv.bad > 0 or not Paint.known(String(cl["kind"])):
			_check(false, "soak %s: clip '%s' paints finite geometry" % [tag, cl["kind"]])


## The enemy phase credits each machine ONE blow: in a pack of one kind the
## first bite must not swallow the others', and a blow the shield soaked
## belongs to the machine that swung it. (fx_enemy re-claims blows in stream
## order too, which would hide a director regression in the reel itself.)
func _check_attribution() -> void:
	# a haul over goo: the goo bite between the two drags stays with the crane
	var hs: Dictionary = Scenes.extra_scene("x:haul_goo")
	var hg = hs["game"]
	var hpre: Dictionary = hg.snapshot()
	var hevs: Array = hg.step(hs["action"])
	var hc := Anim.ctx(hpre, hs["action"], hevs, hg.snapshot(), Anim.empty_reel())
	var hown: Dictionary = Anim._attribute(hc, hpre["enemies"])
	var drags := 0
	for i in hown.get(0, []):
		if String(hevs[i].get("t", "")) == "drag":
			drags += 1
	_check(drags == 2, "x:haul_goo: both drags belong to the crane, the goo between them too (%d)" % drags)
	for nm in ["x:pack", "x:shielded"]:
		var sc: Dictionary = Scenes.extra_scene(nm)
		var g = sc["game"]
		var pre: Dictionary = g.snapshot()
		var evs: Array = g.step(sc["action"])
		var post: Dictionary = g.snapshot()
		var c := Anim.ctx(pre, sc["action"], evs, post, Anim.empty_reel())
		var owners: Dictionary = Anim._attribute(c, pre["enemies"])
		var swung := 0
		for k in pre["enemies"].size():
			if String(pre["enemies"][k]["intent"].get("type", "")) != "attack":
				continue
			swung += 1
			var blows := 0
			for i in owners.get(k, []):
				var tt := String(evs[i].get("t", ""))
				if tt == "shield_absorb" or (tt == "damage" and String(evs[i].get("who", "")) == "player"):
					if tt == "shield_absorb" or i == 0 or String(evs[i - 1].get("t", "")) != "shield_absorb":
						blows += 1
			_check(blows == 1, "%s: machine %d is credited exactly its own blow (%d)" % [nm, k, blows])
		_check(swung >= 2, "%s: stages at least two attackers (%d)" % [nm, swung])
