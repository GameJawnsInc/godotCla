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
const AudioKit := preload("res://shell/audio.gd")
const Game := preload("res://sim/game.gd")
const ImportRun := preload("res://tests/import_run.gd")
const Regress := preload("res://tests/regress_lib.gd")
const AsciiView := preload("res://sim/ascii_view.gd")
const Profile := preload("res://meta/profile.gd")
const RunStatsT := preload("res://meta/run_stats.gd")
const Roster := preload("res://bots/roster.gd")
const Names := preload("res://shell/names.gd")
const Feedback := preload("res://shell/feedback.gd")
const MapGen := preload("res://sim/mapgen.gd")

## A kit that fills every slot with slot 0 held by a mobility ability - the one
## the forge may never scrap (sim/game.gd _is_mobility).
const FULL_KIT := ["mycelium_dash", "solar_lance", "seed_bomb", "vine_whip", "thorn_shield"]
const TMP_SAVE := "user://test_import_run.save"
## Every _bare_shell reads and writes its career here, never the player's real
## profile (Shell.PROFILE_PATH); the body (_run_body) deletes it at the end.
const TEST_PROFILE := "user://test_shell_profile.json"
## every _bare_shell restores (and writes) its run save here, never the real one
const TEST_RUN_SAVE := "user://test_shell_run.save"
## ...and reads and writes its settings here, never the player's tender.cfg:
## every set: tap saves them, and a test must not leave the player's
## difficulty, loadout or package changed (nor drop a legacy seed_mode key)
const TEST_CFG := "user://test_shell_settings.cfg"
## ...and archives a finished run's log here, never into the player's runs dir
const TEST_RUNS := "user://test_shell_runs"
## the shell's default runs dir (main.gd `runs_dir`), checked untouched at the end
const REAL_RUNS := "user://runs"
const TMP_JSON := "user://test_import_record.json"

var fails := 0


## Counts every engine error, push_error and SCRIPT ERROR raised while the
## body runs (tests/test_draw.gd keeps the same gate). A SCRIPT ERROR inside a
## _check_* helper aborts only that helper, so without this the body would
## run on and print OK; one in the body itself aborts the body before quit(),
## and the process used to sit idle forever. Either way it is exit 1 now.
class ErrorCounter extends Logger:
	var errors := 0
	var first: Array = []
	var _mx := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_mx.lock()
		errors += 1
		if first.size() < 20:
			first.append("%s:%d %s: %s %s" % [file, line, function, code, rationale])
		_mx.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


var log_counter := ErrorCounter.new()
var _started := false   # the body was entered (first frame)
var _body_done := false  # ...and reached its own quit()


func _initialize() -> void:
	OS.add_logger(log_counter)


## The body runs from the first frame, not from _init: if it is aborted
## part-way (a SCRIPT ERROR in the body never reaches quit()), the next frame
## fails the run with exit 1 instead of idling forever.
func _process(_dt: float) -> bool:
	if not _started:
		_started = true
		_run_body()
		return _body_done
	if _body_done:
		return true
	print("FAIL: the test body was aborted before it finished (%d engine/script error(s)):" % log_counter.errors)
	for m in log_counter.first:
		print("  " + m)
	OS.remove_logger(log_counter)
	quit(1)
	return true


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + what)


func _run_body() -> void:
	# 1. every sprite rasterizes; every enemy/terrain/legend id has art
	for id in Art.ART:
		var t = Art.tex(id, 36)
		_check(t != null and t.get_width() == 36, "sprite %s rasterizes" % id)
	for kind in Content.ENEMIES:
		_check(Art.ART.has(kind), "enemy %s has a sprite" % kind)
	for row in Shell.LEGEND:
		_check(Art.ART.has(row[0]), "legend id %s has a sprite" % row[0])
	# every terrain the sim can put on the map is drawable and printable -
	# a new Content.TERRAIN row (C1b: ash) must not render as a blank tile
	var legend_ids := {}
	for row in Shell.LEGEND:
		legend_ids[String(row[0])] = String(row[1])
	for kind in Content.TERRAIN:
		_check(Art.ART.has(kind), "terrain %s has a sprite" % kind)
		_check(AsciiView.TERRAIN_CH.has(kind), "terrain %s has an ASCII glyph" % kind)
		_check(legend_ids.has(kind), "terrain %s has a legend row" % kind)
	_check(Art.ART.has("ash"), "ash has a sprite")
	_check(Art.tex("ash", 36) != null, "ash sprite rasterizes")
	_check(legend_ids.get("ash", "") == "Ash", "legend names ash")
	_check(AsciiView.TERRAIN_CH.get("ash", "") == ",", "ash prints as ,")

	# 1b. the whole audio bank synthesizes, and the music loop renders
	var ak = AudioKit.new()
	ak._rng.seed = 7
	ak.build_bank()
	_check(ak._bank.size() >= 15, "sfx bank has %d sounds" % ak._bank.size())
	for id in ak._bank:
		_check(ak._bank[id].data.size() > 100, "sfx %s has samples" % id)
	var mus = ak.render_music_stream()
	_check(mus != null and mus.data.size() > 100000, "music loop renders")
	# the music's noise bed has its own seeded generator: a bank that drew (or
	# did not draw) any number of sounds first leaves the music byte-identical
	var ak_m = AudioKit.new()
	_check(ak_m.render_music_stream().data == mus.data, "the music renders the same with or without the bank built first")
	ak_m.free()
	for sid in ["combo", "multikill", "card", "shielded", "whoomph", "arrive"]:
		_check(ak._bank.has(sid), "the fun-pass sound %s is in the bank" % sid)
	ak.free()
	# repeated sounds walk a fixed pitch cycle (no rng: the bank stays byte-identical)
	var ak2 = AudioKit.new()
	var jit: Array = []
	for i in 9:
		jit.append(ak2.jitter("step"))
	var want_jit: Array = AudioKit.JITTER.duplicate()
	want_jit.append(AudioKit.JITTER[0])
	_check(jit == want_jit, "jitter('step') cycles the JITTER table: %s" % str(jit))
	_check(ak2.jitter("boss") == 1.0, "an id outside JITTER_IDS plays at pitch 1.0")
	ak2.play("step", 1.2)  # out of the tree: returns quietly
	_check(true, "play(id, pitch) on an out-of-tree kit returns without error")
	ak2.free()

	# 2. menu boots, PLAY starts a run, input handlers drive the sim
	OS.set_environment("SHELL_SEED", "")
	# a clean scratch slot: no stale run, settings or career from a crashed run
	for pth in [TEST_RUN_SAVE, TEST_CFG, TEST_PROFILE]:
		DirAccess.remove_absolute(pth)
	# ...and the player's own files, checked untouched at the very end: every
	# shell this test builds reads and writes scratch paths only
	var real_before := _real_files()
	var shell = _iso_shell()
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
	shell._tap("zoom")
	_check(shell.zoom_room, "camera button toggles room zoom")
	_check(not shell.game.map.get("rooms", []).is_empty(), "generated floors expose rooms")
	shell._tap("zoom")
	shell._tap("inspect")
	_check(shell.inspect_live, "magnifier button toggles live inspect")
	shell._tap("inspect")

	# 3. the scripted tutorial plays through end to end
	shell._tap("menu")
	shell._tap("tutorial")
	_check(shell.screen == "tutorial" and shell.game != null, "tutorial starts")
	_check(not shell.game.enemies.is_empty(), "tutorial room has its enemy")
	# regression: an out-of-charge move must never auto-end a forced step
	shell._act({"type": "move", "dir": Vector2i(1, 0)})
	shell._act({"type": "move", "dir": Vector2i(1, 0)})
	_check(shell.tut_step == 2, "two moves reach the end-turn step")
	shell._move_or_strike(Vector2i(1, 0))  # spends the last charge, no advance
	var turns_b: int = shell.game.total_turns
	var step_b: int = shell.tut_step
	shell._move_or_strike(Vector2i(1, 0))  # dry: must flash, not end the turn
	_check(shell.tut_step == step_b and shell.game.total_turns == turns_b,
		"auto-move cannot skip a forced end-turn step")
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
	_check(not shell.game.map.get("bloomed", []).is_empty(), "tutorial room bloomed on the way")
	_check(bool(shell.game.map.get("restored", false)), "tutorial floor got restored")
	shell._tap("menu")
	_check(shell.screen == "menu", "tutorial returns to the menu")

	# 4. a run reaches a draft and draft picking works
	var shell2 = _iso_shell()
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
	# 5. upcycling flows through the shell (shrine press + ability forge)
	var shell3 = _iso_shell()
	shell3._ready()
	shell3._tap("play")
	shell3._key(KEY_SPACE)
	shell3.game.player["pos"] = shell3.game.map["shrine"]
	shell3.game.player["items"] = ["sun_capsule", "balm_fruit"]
	shell3.game.bloom = 10
	shell3._tap("upcycle:0")
	_check(shell3.game.player["items"] == ["sun_capsule+"], "shrine press upcycles an item")
	shell3._tap("forge")
	_check(shell3.mode == "up_keep", "forge card enters keep-select")
	shell3._ability_press(0)
	_check(shell3.mode == "up_scrap", "keep picked, scrap-select next")
	var ksz: int = shell3.game.player["kit"].size()
	shell3._ability_press(2)  # mycelium_dash: the mobility slot is never scrap
	_check(shell3.game.player["kit"].size() == ksz and shell3.mode == "up_scrap",
		"the forge refuses to scrap the mobility ability")
	_check(shell3.flash == "can't scrap your mobility ability", "...and says why")
	shell3._ability_press(1)
	# Block D6: solar_lance is a FORKED base, so the sim lists one forge action
	# per (keep, scrap, variant) triple and the scrap tap opens the fork sheet
	# instead of forging. The kit is unchanged until a variant is tapped.
	_check(shell3.mode == "up_variant" and shell3.game.player["kit"].size() == ksz,
		"a forked base opens the fork sheet on the scrap tap")
	_check(shell3._forge_actions(0, 1).size() == 2,
		"the fork sheet offers both variants of a forked base")
	shell3._tap("forgevar:0")
	# Content.is_upgrade, never ends_with("+"): a variant id is "<base>+<word>"
	_check(shell3.game.player["kit"].size() == ksz - 1
			and Content.is_upgrade(String(shell3.game.player["kit"][0]))
			and Content.base_id(String(shell3.game.player["kit"][0])) == "solar_lance",
		"forge upgrades one ability into the chosen variant and scraps another")
	_check(not shell3.game.shop.has("forge"), "one forge per floor: the card is spent")
	_check(not _tags(shell3).has("forge"), "the forge card disappears after one forge")
	shell3._tap("forge")
	_check(shell3.mode == "normal" and shell3.flash == "the forge is cold",
		"a spent forge cannot be entered again")
	shell3.free()

	# 5b. a PACKAGE base has ONE variant, so the scrap tap forges at once and
	# the fork sheet never opens - the other half of the D6 forge branch
	var shell3b = _iso_shell()
	shell3b._ready()
	shell3b._tap("play")
	shell3b._key(KEY_SPACE)
	shell3b.game.player["pos"] = shell3b.game.map["shrine"]
	shell3b.game.player["kit"] = ["spore_cloud", "seed_bomb", "mycelium_dash"]
	shell3b.game.bloom = 10
	shell3b._tap("forge")
	shell3b._ability_press(0)
	shell3b._ability_press(1)
	_check(shell3b.mode == "normal" and shell3b.game.player["kit"][0] == "spore_cloud+",
		"a one-variant (package) base forges on the scrap tap: %s" % str(shell3b.game.player["kit"]))
	shell3b.free()

	# 6. a killed app resumes byte-exact: replay from the on-disk action log
	var shell4 = _iso_shell()
	shell4._ready()
	shell4._tap("play")
	shell4._key(KEY_SPACE)
	for i in 6:
		shell4._key(KEY_SPACE)  # end turns
	for a in shell4._legal_of("move"):
		shell4._act(a)
		break
	var saved_hash: String = shell4.game.state_hash()
	var saved_turns: int = shell4.game.total_turns
	shell4.free()  # simulate Android reclaiming the app (no clean shutdown)
	var shell5 = _iso_shell()
	shell5._ready()
	_check(shell5.game != null and shell5._game_is_run, "killed run auto-restores on boot")
	_check(shell5.game.total_turns == saved_turns, "restored run is at the same turn")
	_check(shell5.game.state_hash() == saved_hash, "restored run is byte-exact (replay determinism)")
	_check(shell5.log_lines.size() == shell5.log_cats.size(),
		"the rebuilt log keeps a category per line (%d / %d)" % [shell5.log_lines.size(), shell5.log_cats.size()])
	var raw_ids := false
	for ln in shell5.log_lines:
		raw_ids = raw_ids or String(ln).contains("_")
	_check(not raw_ids, "the rebuilt log names things, never raw ids: %s" % str(shell5.log_lines))
	shell5._tap("resume")
	_check(shell5.screen == "game", "RESUME enters the restored run")
	shell5.free()

	# 6b. that same log is a regression pair: tests/import_run.gd replays it
	_check(Shell.RUN_SAVE_VERSION == Game.SIM_VERSION, "the shell stamps Game.SIM_VERSION")
	var export_path := OS.get_environment("SHELL_EXPORT_SAVE")
	if export_path != "":
		DirAccess.copy_absolute(TEST_RUN_SAVE, export_path)
	var parsed := ImportRun.parse_save(TEST_RUN_SAVE)
	_check(bool(parsed.get("ok", false)), "import_run parses a real shell save (%s)" % parsed.get("err", ""))
	if bool(parsed.get("ok", false)):
		_check(parsed["actions"].size() == 7, "every action reached the log (%d)" % parsed["actions"].size())
		var rec := ImportRun.build_record(parsed, "shell smoke import")
		_check(int(rec["expect"]["turns"]) == saved_turns, "the imported record replays to the same turn")
		_check(String(rec["hash"]) == saved_hash, "the imported record replays byte-exact")
		_check(int(rec["sim_version"]) == Game.SIM_VERSION, "the record stamps the sim version")
		_check(int(rec["_illegal"]) == 0 and int(rec["_errors"]) == 0, "a shell log replays without illegals")
		_check(Regress.save_record(TMP_JSON, rec), "the record writes as JSON")
		var back := Regress.load_record(TMP_JSON)
		_check(int(back.get("seed", -1)) == int(rec["seed"])
			and back.get("game_actions", []).size() == rec["actions"].size(),
			"the record round-trips through the regression codec")
		_check(not back.has("_illegal"), "reporting-only keys stay out of the record")
		DirAccess.remove_absolute(TMP_JSON)
	DirAccess.remove_absolute(TEST_RUN_SAVE)

	# 6c. a log from an older sim is refused, and the loss is announced once
	var sf := FileAccess.open(TMP_SAVE, FileAccess.WRITE)
	sf.store_line(var_to_str({"v": Game.SIM_VERSION + 1, "seed": 5, "tier": 0, "config": {}}).replace("\n", " "))
	sf.store_line(var_to_str({"type": "end_turn"}).replace("\n", " "))
	sf.close()
	var stale := ImportRun.parse_save(TMP_SAVE)
	_check(not bool(stale.get("ok", true)) and String(stale.get("err", "")).contains("sim_version"),
		"import_run refuses a save from another sim version")
	DirAccess.copy_absolute(TMP_SAVE, TEST_RUN_SAVE)
	var shell6 = _iso_shell()
	shell6._ready()
	_check(shell6.save_lost, "a version-mismatched save raises the lost-run notice")
	_check(not FileAccess.file_exists(TEST_RUN_SAVE), "the stale save is discarded")
	shell6._tap("play")
	_check(not shell6.save_lost, "a new run clears the notice")
	if shell6._run_save != null:
		shell6._run_save.close()
		shell6._run_save = null
	shell6.free()
	DirAccess.remove_absolute(TMP_SAVE)
	DirAccess.remove_absolute(TEST_RUN_SAVE)

	# 7. the shrine sheet: two graft offers, exactly one pick
	var shop1 = _bare_shell()
	shop1.game = Game.new(4242, {"bloom": 30})
	_check(shop1.game.map["shrine"] != Vector2i(-1, -1), "floor 1 has a shrine")
	shop1.game.player["pos"] = shop1.game.map["shrine"]
	var offers: Array = shop1.game.shop.get("grafts", [])
	_check(offers.size() == 2, "the shrine offers two grafts (got %d)" % offers.size())
	shop1._tap("shop")
	_check(shop1.mode == "shop", "standing on the shrine opens the sheet")
	var tags := _tags(shop1)
	_check(tags.has("buy:graft:0") and tags.has("buy:graft:1"), "both grafts get a card")
	_check(tags.has("buy:heal") and tags.has("buy:ability") and tags.has("buy:item"),
		"heal / ability / item cards are on the sheet")
	# each graft card carries that offer's own price (snapshot shop.graft_prices),
	# never a flat graft price: a lever card is dearer than a stat-graft card
	var gsnap: Dictionary = shop1.game.snapshot()
	var gprices: Array = gsnap["shop"].get("graft_prices", [])
	_check(gprices.size() == offers.size(), "the snapshot prices every graft offer: %s" % str(gprices))
	var gcards: Array = shop1._shop_cards(gsnap)
	for i in offers.size():
		var gid := String(offers[i])
		var want_price: int = shop1.game.shop_cost("graft", gid)
		# the price is a card FIELD now, not words inside the name: the sheet
		# draws it as a number beside the bloom sprite, so a seven-offer shrine
		# spends its width on what each offer does instead of on "  -  N bloom"
		var got_name := ""
		var got_price := -1
		for c in gcards:
			if String(c[3]) == "buy:graft:%d" % i:
				got_name = String(c[1])
				got_price = int(c[4])
		_check(int(gprices[i]) == want_price and got_price == want_price
				and got_name == String(Content.GRAFTS[gid]["name"]),
			"graft card %d shows its own price (want %s at %d, got %s at %d)" % [
				i, Content.GRAFTS[gid]["name"], want_price, got_name, got_price])
	print("shrine cards: %s at %s bloom" % [str(offers), str(gprices)])
	var want := String(offers[1]) if offers.size() > 1 else ""
	shop1._tap("buy:graft:1")
	_check(shop1.game.player["grafts"].has(want), "the second graft card buys that graft")
	_check(not shop1.game.shop.has("grafts"), "one pick closes the graft counter")
	_check(shop1.mode == "shop", "the sheet stays open after a purchase")
	var tags2 := _tags(shop1)
	_check(not tags2.has("buy:graft:0") and not tags2.has("buy:graft:1"),
		"both graft cards leave with the pick")
	shop1.game.shop = {}
	_check(_tags(shop1).is_empty(), "a boarded shrine draws no cards at all")
	shop1.free()

	# 7b. the graft keys: G takes the first offer, J the second
	var shop2 = _bare_shell()
	shop2.game = Game.new(99, {"bloom": 30})
	shop2.game.player["pos"] = shop2.game.map["shrine"]
	var j_offers: Array = shop2.game.shop.get("grafts", [])
	shop2.mode = "shop"
	shop2._key(KEY_J)
	_check(j_offers.size() > 1 and shop2.game.player["grafts"].has(String(j_offers[1])),
		"J buys the second graft")
	shop2.game = Game.new(100, {"bloom": 30})
	shop2.game.player["pos"] = shop2.game.map["shrine"]
	var g_offers: Array = shop2.game.shop.get("grafts", [])
	shop2.mode = "shop"
	shop2._key(KEY_G)
	_check(not g_offers.is_empty() and shop2.game.player["grafts"].has(String(g_offers[0])),
		"G buys the first graft")
	shop2.free()

	# 8. a full kit cannot buy the ability at all - the card is simply not for sale
	var shop3 = _bare_shell()
	shop3.game = Game.new(4242, {"bloom": 30, "kit": FULL_KIT})
	shop3.game.player["pos"] = shop3.game.map["shrine"]
	var offer_aid := String(shop3.game.shop.get("ability", ""))
	_check(offer_aid != "", "the shrine stocks an ability")
	var kit_before: Array = shop3.game.player["kit"].duplicate()
	var bloom_before: int = shop3.game.bloom
	shop3._tap("shop")
	shop3._tap("buy:ability")
	_check(shop3.mode == "shop", "a full kit leaves the sheet open on the ability card")
	_check(shop3.flash == "can't buy that", "...and says the card is not for sale")
	_check(shop3.game.player["kit"] == kit_before, "the full kit is untouched")
	_check(shop3.game.bloom == bloom_before, "no bloom is spent")
	_check(shop3.game.shop.has("ability"), "the ability card stays stocked")
	shop3._key(KEY_B)
	_check(shop3.game.player["kit"] == kit_before and shop3.game.bloom == bloom_before,
		"the B key buys nothing either")
	shop3.free()

	# 8b. the full-kit ability card is still drawn, with its plain description
	var shop4 = _bare_shell()
	shop4.game = Game.new(4242, {"bloom": 30, "kit": FULL_KIT})
	shop4.game.player["pos"] = shop4.game.map["shrine"]
	var acard := ""
	for c in shop4._shop_cards(shop4.game.snapshot()):
		if String(c[3]) == "buy:ability":
			acard = String(c[2])
	_check(acard != "", "the shop sheet still draws the ability card at a full kit")
	_check(not acard.to_lower().contains("replaces"), "...with no slot-replacement promise")
	shop4.free()

	# 8b2. a free slot still buys the ability outright
	var shop5 = _bare_shell()
	shop5.game = Game.new(4242, {"bloom": 30, "kit": ["mycelium_dash", "solar_lance"]})
	shop5.game.player["pos"] = shop5.game.map["shrine"]
	var free_aid := String(shop5.game.shop.get("ability", ""))
	shop5._tap("shop")
	shop5._tap("buy:ability")
	_check(shop5.game.player["kit"].size() == 3 and String(shop5.game.player["kit"][2]) == free_aid,
		"a free kit slot buys the ability outright")
	_check(not shop5.game.shop.has("ability"), "the ability card is spent")
	shop5.free()

	# 8c. the log speaks the new event shapes
	var evsh = _bare_shell()
	evsh.game = Game.new(1, {})
	_check(evsh._ev_text({"t": "damage", "who": "player", "amt": 2, "src": "fire:solar_lance"})
		== "You take 2 dmg (fire)", "a qualified damage source reads as the bare source")
	_check(evsh._ev_text({"t": "damage", "who": "player", "amt": 1, "src": "goo"})
		== "You take 1 dmg (goo)", "an unqualified source is untouched")
	_check(evsh._ev_text({"t": "damage", "who": "drill_bot", "amt": 3}) == "Drill Bot takes 3",
		"an enemy damage line with no src names no source")
	_check(evsh._ev_text({"t": "damage", "who": "player", "amt": 2, "src": "drill_bot"})
		== "You take 2 dmg (Drill Bot)", "an enemy source reads as its name")
	_check(evsh._ev_text({"t": "damage", "who": "drill_bot", "amt": 3, "src": "solar_lance"})
		== "Drill Bot takes 3 (Solar Lance)", "an ability hit names the ability")
	_check(evsh._ev_text({"t": "damage", "who": "drill_bot", "amt": 3, "src": "strike"})
		== "Drill Bot takes 3", "a plain strike names no source")
	_check(evsh._ev_text({"t": "damage", "who": "drill_bot", "amt": 3, "src": "collision:water_jet"})
		== "Drill Bot takes 3 (collision)", "a collision reads as a collision")
	_check(evsh._ev_text({"t": "player_death", "cause": "drill_bot"}) == "You die (Drill Bot)",
		"the death line names the killer")
	_check(evsh._ev_text({"t": "draft_upgrade", "id": "solar_lance+noon"}) == "Upgraded to Noon Lance",
		"an upgrade names the variant, not its id")
	var rp: Vector2i = evsh.game.player["pos"] + _open_dir(evsh.game)
	var rbot: Dictionary = _park_enemy(evsh.game, rp)
	rbot["kind"] = "drill_bot"
	_check(evsh._ev_text({"t": "rooted", "id": rbot["id"]}) == "Drill Bot is rooted in place",
		"a rooted line names the enemy: %s" % evsh._ev_text({"t": "rooted", "id": rbot["id"]}))
	rbot["pos"] = Vector2i(-9, -9)
	evsh.game._spawn("coal_golem", rp)
	_check(evsh._ev_text({"t": "reinforcement", "tile": rp}) == "A vent releases a Coal Golem",
		"a reinforcement names what came out of the vent: %s" % evsh._ev_text({"t": "reinforcement", "tile": rp}))
	# Block E2 (stage 9): the event's own kind wins; without one, a NEW enemy
	# on the tile (above); with neither, "a machine"
	_check(evsh._ev_text({"t": "reinforcement", "tile": rp, "kind": "rust_hound"}) == "A vent releases a Rust Hound",
		"a reinforcement's kind names it, whatever stands on the tile: %s"
		% evsh._ev_text({"t": "reinforcement", "tile": rp, "kind": "rust_hound"}))
	_check(evsh._ev_text({"t": "reinforcement", "tile": Vector2i(-40, -40)}) == "A vent releases a machine",
		"no kind and nothing on the tile: a machine (%s)" % evsh._ev_text({"t": "reinforcement", "tile": Vector2i(-40, -40)}))
	# one step can release different kinds at different vents: one line per
	# kind, counted (mutation: aggregate by the step instead of by the kind)
	var rmix: Array = Feedback.log_entries([{"t": "reinforcement", "tile": Vector2i(-40, -40), "kind": "rust_hound"},
		{"t": "reinforcement", "tile": Vector2i(-41, -40), "kind": "drill_bot"},
		{"t": "reinforcement", "tile": Vector2i(-42, -40), "kind": "rust_hound"}], {}, evsh.game, {}).map(func(l): return l["text"])
	_check(rmix == ["Vents release 2 Rust Hounds", "A vent releases a Drill Bot"],
		"a mixed wave reads one line per kind: %s" % str(rmix))
	# Block E1 (stage 9): the floor line names the crew the floor drew
	_check(evsh._ev_text({"t": "floor", "floor": 1, "name": "Strip Mine I", "encounter": "hound_and_handler"})
		== "— Strip Mine I · Hound and Handler —", "the floor line names its crew: %s"
		% evsh._ev_text({"t": "floor", "floor": 1, "name": "Strip Mine I", "encounter": "hound_and_handler"}))
	_check(evsh._ev_text({"t": "floor", "floor": 1, "name": "Strip Mine I"}) == "— Strip Mine I —",
		"a floor event with no crew keeps the bare line")
	_check(evsh._ev_text({"t": "floor", "floor": 7, "name": "The Furnace", "encounter": ""}) == "— The Furnace —",
		"an empty crew id keeps the bare line")
	_check(evsh._ev_text({"t": "buy", "item": "graft", "id": "bloom_surge", "discarded": "carapace"})
		== "Bought Bloom Surge (discarded Carapace)", "a graft buy names the discarded offer")
	_check(evsh._ev_text({"t": "buy", "item": "ability", "id": "sun_flare"})
		== "Bought Sun Flare", "an ability buy names what was bought")
	_check(evsh._ev_text({"t": "buy", "item": "graft", "id": "carapace", "discarded": ""})
		== "Bought Carapace", "a lone graft offer has nothing to discard")
	_check(evsh._ev_text({"t": "quota_reclamp", "need": 3, "was": 5}).contains("3"),
		"the re-clamped quota reaches the log")
	evsh.free()

	# 9. finished logs are archived, and the folder keeps only the newest few
	var arch = _bare_shell()
	arch.runs_dir = "user://test_runs"
	arch.seed_v = 987654
	arch.game = Game.new(1, {})
	var lf := FileAccess.open(arch.run_save_path, FileAccess.WRITE)  # the scratch live slot
	lf.store_line("stand-in log")
	lf.close()
	arch._archive_run()
	_check(not FileAccess.file_exists(arch.run_save_path), "the finished log leaves the live slot")
	var archived := ""
	for n in _dir_files(arch.runs_dir):
		if n.begins_with("run_987654_"):
			archived = n
	_check(archived.ends_with("_died.save"), "the log is archived as %s" % archived)
	for i in 12:
		var pf := FileAccess.open("%s/run_%d_20200101_died.save" % [arch.runs_dir, 700 + i], FileAccess.WRITE)
		pf.store_line("filler")
		pf.close()
	arch._prune_runs()
	_check(_dir_files(arch.runs_dir).size() == Shell.RUNS_KEEP,
		"retention keeps %d logs (got %d)" % [Shell.RUNS_KEEP, _dir_files(arch.runs_dir).size()])
	for n in _dir_files(arch.runs_dir):
		DirAccess.remove_absolute(arch.runs_dir + "/" + n)
	DirAccess.remove_absolute(arch.runs_dir)
	arch.free()

	# 10. the game-over site: a career run is recorded from the sim's own
	# summary merged with the stats fold, a daily only scores its seed and
	# unlocks nothing - and neither touches the player's real profile
	var prof_path: String = Shell.PROFILE_PATH
	var prof_before := FileAccess.get_file_as_string(prof_path) if FileAccess.file_exists(prof_path) else ""
	var rec = _bare_shell()
	rec.profile = Profile.new()
	rec._game_is_run = true
	rec._run_recorded = false
	rec.run_tier = 0
	rec.run_kind = "career"
	rec.game = Game.new(4242, {})
	rec.game.over = true
	rec._record_finished_run()
	_check(rec.profile.runs == 1 and rec.profile.history.size() == 1,
		"a finished run reaches the career profile")
	_check(int(rec.profile.history[0]["seed"]) == 4242 and rec.profile.history[0]["kit"] == Content.STARTING_KIT,
		"the record is the sim's run_summary (seed and kit), not a stub")
	_check(rec.profile.daily_best.is_empty(), "a random run files no daily result")
	_check(rec.stats != null and rec._stats_for == rec.game,
		"a game assigned from outside gets its own stats fold")
	_check(rec._run_summary.has("kills") and rec._run_summary.has("seed")
		and rec._run_summary["score"] is int and int(rec._run_summary["score_v"]) == Content.RUN_SCORE_VERSION,
		"the recorded summary is run_summary + the fold + the score (%s)" % str(rec._run_summary.keys()))
	_check(int(rec._run_summary["score"]) == int(RunStatsT.score(rec._run_summary)["total"])
		and int(rec.profile.history[0]["score"]) == int(rec._run_summary["score"]),
		"the stored score is the score of that summary")
	_check(int(rec._over_prev.get("runs", -1)) == 0 and int(rec._over_prev.get("best_floor", -1)) == 0,
		"the bests the sheet compares against were taken BEFORE the record (%s)" % str(rec._over_prev))
	_check(rec._run_report == rec.profile.last_report and rec._run_unlocks == rec._run_report["unlocks"],
		"the unlocks come from the profile's report")
	_check(FileAccess.file_exists(TEST_PROFILE), "the career is saved to the shell's profile_path")
	_check(String(rec._run_summary.get("run_kind", "")) == "career" and not rec._run_summary.has("seed_mode"),
		"the summary carries the run's own kind, not a global seed mode")
	_check(rec.profile.last_report.has("next") and not rec.profile.last_report["next"].is_empty()
		and rec.profile.last_report["next"][0].has("delta"),
		"the report carries the next goal with its delta (%s)" % str(rec.profile.last_report.get("next", [])))
	rec.run_kind = "daily"
	rec._run_recorded = false
	rec.game = Game.new(77, {})
	rec.game.over = true
	rec._record_finished_run()
	_check(rec.profile.runs == 1 and rec.profile.history.size() == 1, "a daily run is not a career run")
	_check(rec.profile.daily_best.has("77"), "a daily run files that seed's result")
	_check(rec._run_unlocks.is_empty(), "a daily unlocks nothing")
	_check(rec._over_prev.has("daily") and rec._over_prev["daily"].is_empty(),
		"a first daily finish compares against no earlier best (%s)" % str(rec._over_prev))
	_check(bool(rec._daily_report.get("ranked", false)) and rec.profile.daily_first.has("77"),
		"a first daily finish is the ranked one (%s)" % str(rec._daily_report))
	# a second daily on the same seed compares against the first result, read
	# under the key record_daily writes (the game's seed) whatever seed_v says
	var first_daily: Dictionary = rec.profile.daily_best["77"].duplicate()
	rec.seed_v = 77
	rec._run_recorded = false
	rec.game = Game.new(77, {})
	rec.game.over = true
	rec._record_finished_run()
	_check(rec._over_prev.get("daily", {}) == first_daily and not first_daily.is_empty(),
		"a second daily on seed 77 compares against the first (%s vs %s)" % [str(rec._over_prev), str(first_daily)])
	rec.seed_v = 78
	rec._run_recorded = false
	rec.game = Game.new(77, {})
	rec.game.over = true
	rec._record_finished_run()
	_check(rec._over_prev.get("daily", {}) == first_daily,
		"the daily best is looked up by the game's seed, not seed_v (%s)" % str(rec._over_prev))
	rec.free()
	var prof_after := FileAccess.get_file_as_string(prof_path) if FileAccess.file_exists(prof_path) else ""
	var prof_safe := prof_after == prof_before
	_check(prof_safe, "the game-over test never writes the player's real profile")
	if not prof_safe:
		# the routing regressed: put the player's career back before anything else
		if prof_before == "":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(prof_path))
		else:
			var pf := FileAccess.open(prof_path, FileAccess.WRITE)
			if pf != null:
				pf.store_string(prof_before)
				pf.close()

	# 11. the title screen's run-setup rows (Block A): three cyclers gated by
	# the career, the config PLAY builds out of them and the status line that
	# names it; then the daily, which is its own menu entry and sheet now (the
	# settings toggle that swapped the rows for a TODAY line is gone)
	var menu = _bare_shell()
	menu.profile = Profile.new()
	menu.run_kind = "career"
	menu._clamp_selection()
	var rows0 := _rows(menu)
	_check(rows0.has("LOADOUT: Tender") and rows0.has("PACKAGE: none") and rows0.has("MUTATOR: none"),
		"a fresh career shows tender / none / none (%s)" % str(rows0))
	_check(rows0.has("DAILY") and not str(rows0).contains("TODAY"),
		"the daily is a menu entry, not a TODAY line (%s)" % str(rows0))
	menu._tap("set:loadout")
	menu._tap("set:package")
	menu._tap("set:mutator")
	_check(menu.sel_loadout == "tender" and menu.sel_package == "" and menu.sel_mutator == "",
		"with nothing unlocked the rows have nothing to cycle to")
	_check(str(menu._run_config()) == str({"packages": [], "tier": 0, "mutators": [], "loadout": "tender"}),
		"a fresh career still plays the default config (%s)" % str(menu._run_config()))
	menu.profile.unlocked_packages = ["mycology", "hydraulics"]
	menu.profile.unlocked_mutators = ["brittle"]
	menu.profile.unlocked_loadouts = ["tidewarden"]
	menu._tap("set:loadout")
	menu._tap("set:package")
	menu._tap("set:mutator")
	_check(menu.sel_loadout == "tidewarden", "LOADOUT cycles onto the unlocked loadout (%s)" % menu.sel_loadout)
	_check(menu.sel_package == "mycology", "PACKAGE cycles off none onto an unlocked package (%s)" % menu.sel_package)
	_check(menu.sel_mutator == "brittle", "MUTATOR cycles off none onto an unlocked mutator (%s)" % menu.sel_mutator)
	var rows1 := _rows(menu)
	_check(rows1.has("LOADOUT: Tidewarden") and rows1.has("PACKAGE: Mycology")
		and rows1.has("MUTATOR: Brittle Tender"), "the rows name what is selected (%s)" % str(rows1))
	var cfg1: Dictionary = menu._run_config()
	_check(String(cfg1["loadout"]) == "tidewarden" and cfg1["packages"] == ["mycology"]
		and cfg1["mutators"] == ["brittle"], "the cyclers reach the config PLAY builds (%s)" % str(cfg1))
	menu.seed_v = 4242
	menu._new_game()
	_check(menu.game.player["kit"] == Content.LOADOUTS["tidewarden"]["kit"],
		"PLAY starts the run on the chosen loadout (%s)" % str(menu.game.player["kit"]))
	_check(menu.game.packages == ["mycology"] and menu.game.mutators == ["brittle"],
		"...with the chosen package and mutator")
	_check(menu._config_line(menu.game.snapshot()) == "Tidewarden · Mycology · Brittle Tender",
		"the status line names loadout, package and mutator (%s)" % menu._config_line(menu.game.snapshot()))
	menu.profile.unlocked_loadouts = []
	menu._clamp_selection()
	_check(menu.sel_loadout == "tender", "losing the unlock drops the selection back to tender")
	# the settings sheet has no seed toggle left: PLAY is always a career run
	var stags: Array = []
	for r in menu._settings_rows():
		stags.append(String(r[1]))
	_check(not stags.has("set:seed") and stags.has("set:hold") and stags.has("set:intro"),
		"the settings rows carry no seed toggle (%s)" % str(stags))
	# the DAILY entry: its sheet names today's config, its PLAY is the daily
	var day = _bare_shell()
	day.profile = Profile.new()  # a daily needs nothing unlocked
	day.screen = "menu"
	day.mode = "normal"
	var dseed: int = day._daily_seed()
	_check(dseed == Profile.daily_seed_for(Time.get_date_string_from_system(true)),
		"the shell's daily seed is Profile.daily_seed_for(today) (%d)" % dseed)
	day._tap("daily")
	_check(day.mode == "daily" and day.screen == "menu", "DAILY opens the daily sheet (%s)" % day.mode)
	var dc: Dictionary = Profile.daily_config(dseed)
	var sheet: Dictionary = day._daily_sheet(dseed)
	var names_on: Array = []
	for c in sheet["cards"]:
		names_on.append(String(c[1]))
	_check(names_on.has(String(Content.LOADOUTS[dc["loadout"]]["name"])),
		"the sheet names the day's loadout (%s)" % str(names_on))
	_check(String(dc["package"]) == "" or names_on.has(String(Content.PACKAGE_INFO[dc["package"]]["name"])),
		"...its package (%s)" % str(names_on))
	_check(String(dc["mutator"]) == "" or names_on.has(String(Content.MUTATORS[dc["mutator"]]["name"])),
		"...and its mutator (%s)" % str(names_on))
	_check(String(sheet["play"]) == "PLAY TODAY'S RUN" and String(sheet["result"]).begins_with("No finish yet"),
		"an unplayed daily offers the ranked run (%s / %s)" % [sheet["play"], sheet["result"]])
	day._tap("daily_play")
	_check(day.run_kind == "daily" and day.screen == "game" and day.seed_v == dseed,
		"the sheet's PLAY starts today's daily (%s, %d)" % [day.run_kind, day.seed_v])
	_check(str(day._run_config()) == str(Profile.daily_game_config(dseed)),
		"...on the daily config (%s)" % str(day._run_config()))
	_check(int(day.profile.daily_tries.get(Profile.daily_key(dseed), 0)) == 1,
		"...and counts a try (%s)" % str(day.profile.daily_tries))
	_check(String(day._daily_sheet(dseed)["result"]).begins_with("1 try"),
		"a started daily reads as a try with no finish (%s)" % day._daily_sheet(dseed)["result"])
	# back on the menu with that try still live, the sheet RESUMES it: a fresh
	# start would overwrite the save and count a second try
	var live_day = day.game
	day.screen = "menu"
	day._tap("daily")
	var rsh: Dictionary = day._daily_sheet(dseed)
	_check(String(rsh["play"]) == "RESUME TODAY'S TRY" and String(rsh["play_tag"]) == "daily_resume",
		"a daily try in progress is offered as a resume (%s / %s)" % [rsh["play"], rsh["play_tag"]])
	day._key(KEY_ENTER)
	_check(day.screen == "game" and day.mode == "normal" and day.game == live_day
		and int(day.profile.daily_tries.get(Profile.daily_key(dseed), 0)) == 1,
		"...which re-enters the same try and counts no new one (%s)" % str(day.profile.daily_tries))
	# the same from the run save alone (the tutorial displaced the live run)
	var hold_game = day.game
	day._game_is_run = false
	_check(String(day._daily_sheet(dseed)["play_tag"]) == "daily_resume",
		"...read from the run save's header when the live game is not the run")
	_check(String(day._daily_sheet(dseed + 1)["play_tag"]) == "daily_play",
		"...and only for that seed's daily")
	day._game_is_run = true
	day.game = hold_game
	# R retries the daily (another try); N leaves it for a career run
	day.mode = "normal"  # a first run opens on the intro, which eats a key
	day._key(KEY_R)
	_check(day.run_kind == "daily" and day.seed_v == dseed
		and int(day.profile.daily_tries.get(Profile.daily_key(dseed), 0)) == 2,
		"R retries the daily as another try (%s)" % str(day.profile.daily_tries))
	day.mode = "normal"
	day._key(KEY_N)
	_check(day.run_kind == "career" and day.seed_v == dseed + 1, "N moves on to a career run on the next seed")
	# a finished daily's over sheet has no tap-anywhere (stage 6): a tap off
	# its buttons starts nothing, and its NEW RUN is a career run (C25), never
	# another daily try on today's seed
	day._start_run("daily", dseed)
	var tries_now := int(day.profile.daily_tries.get(Profile.daily_key(dseed), 0))
	var over_day = day.game
	day.game.over = true
	day.mode = "normal"
	day.hotspots.clear()
	day._click(Vector2(-10, -10))
	_check(day.game == over_day and day.run_kind == "daily"
		and int(day.profile.daily_tries.get(Profile.daily_key(dseed), 0)) == tries_now,
		"a tap off the buttons of a daily's over sheet starts nothing (%s)" % day.run_kind)
	day._tap("new_run")
	_check(day.run_kind == "career" and day.game != over_day
		and int(day.profile.daily_tries.get(Profile.daily_key(dseed), 0)) == tries_now,
		"NEW RUN on a daily's over sheet starts a career run and counts no try (%s, %s)" % [day.run_kind,
			str(day.profile.daily_tries)])
	day.screen = "menu"
	day._tap("play")
	_check(day.run_kind == "career", "PLAY is always a career run")
	# with that career run live, the DAILY sheet warns that a start abandons it
	# and PLAY takes a second tap (one save: a fresh daily overwrites it)
	var live_career = day.game
	var tries_before := int(day.profile.daily_tries.get(Profile.daily_key(dseed), 0))
	day.screen = "menu"
	day._tap("daily")
	var ash: Dictionary = day._daily_sheet(dseed)
	_check(bool(ash["note_warn"]) and String(ash["note"]).contains("abandons"),
		"a live career run puts the abandon warning on the daily sheet (%s)" % ash["note"])
	day._tap("daily_play")
	_check(day.game == live_career and day.run_kind == "career" and day.mode == "daily"
		and int(day.profile.daily_tries.get(Profile.daily_key(dseed), 0)) == tries_before,
		"...the first PLAY tap starts nothing and counts no try")
	_check(String(day._daily_sheet(dseed)["play"]) == "TAP AGAIN TO ABANDON",
		"...and the button asks for a second tap (%s)" % day._daily_sheet(dseed)["play"])
	day._tap("close")
	day._tap("daily")
	_check(String(day._daily_sheet(dseed)["play"]) != "TAP AGAIN TO ABANDON",
		"...reopening the sheet disarms it")
	day._tap("daily_play")
	day._tap("daily_play")
	_check(day.run_kind == "daily" and day.game != live_career and day.screen == "game",
		"...and the second tap starts the daily (%s)" % day.run_kind)
	# the menu's PLAY guards that live try the same way: its try is already
	# counted, and a career start overwrites the one run save
	var live_try = day.game
	day.screen = "menu"
	day.mode = "normal"
	day._tap("play")
	_check(day.game == live_try and day.run_kind == "daily" and day.screen == "menu"
		and String(day._menu_rows().filter(func(r): return String(r[1]) == "play")[0][0]) == Shell.PLAY_ARMED_LABEL,
		"PLAY over a live daily try starts nothing and asks for a second tap")
	_check(Shell.PLAY_ARMED_LABEL.contains("TODAY'S TRY"), "the armed PLAY names the loss (%s)" % Shell.PLAY_ARMED_LABEL)
	# ...but only a try on TODAY'S seed is today's: yesterday's unfinished try
	# (or a legacy save routed as a daily) reads the date-free form
	# (mutation: return PLAY_ARMED_LABEL unconditionally)
	day.seed_v = dseed + 1
	_check(String(day._menu_rows().filter(func(r): return String(r[1]) == "play")[0][0]) == Shell.PLAY_ARMED_OLD_LABEL
		and not Shell.PLAY_ARMED_OLD_LABEL.contains("TODAY"),
		"an armed PLAY over an older daily try does not call it today's (%s)" % day._play_armed_label())
	day.seed_v = dseed
	day._tap("settings")
	day.mode = "normal"
	_check(String(day._menu_rows().filter(func(r): return String(r[1]) == "play")[0][0]) == "PLAY",
		"...any other tap disarms it")
	# a tap that hits no button disarms it too (mutation: drop the disarm in
	# _click's menu branch), and so does ESC / Back at the menu root (mutation:
	# drop it in _back's menu arm) - else a later single PLAY tap abandons the try
	day._tap("play")
	day.hotspots.clear()
	day._click(Vector2(3, 3))
	_check(not day._play_armed and day.game == live_try, "an off-button tap on the menu disarms PLAY")
	day._tap("play")
	_check(day._play_armed, "fixture: PLAY armed again")
	day._key(KEY_ESCAPE)
	_check(not day._play_armed and day.screen == "menu", "ESC at the menu root disarms PLAY")
	day._tap("play")
	day._back(false)
	_check(not day._play_armed, "Back at the menu root disarms PLAY")
	day._tap("play")
	_check(day.game == live_try and day.run_kind == "daily" and day._play_armed,
		"...so the next PLAY tap only re-arms it")
	day._tap("play")
	_check(day.run_kind == "career" and day.game != live_try and day.screen == "game",
		"...and the second tap starts a career run (%s)" % day.run_kind)
	# the same warning off the run save's cached header when the live game is
	# not a run: the header is re-read after every write of the save
	day._start_run("career")
	day._game_is_run = false
	_check(bool(day._daily_sheet(dseed)["note_warn"]), "the header of a saved career run warns as well")
	day._game_is_run = true
	# a seed whose daily wants all three, played on a career that unlocked none
	var dseed2 := 0
	for s in range(1, 500):
		var d2: Dictionary = Profile.daily_config(s)
		if String(d2["package"]) != "" and String(d2["mutator"]) != "" and String(d2["loadout"]) != "tender":
			dseed2 = s
			break
	_check(dseed2 > 0, "some daily seed wants a package, a mutator and a non-tender loadout")
	if dseed2 > 0:
		var d3: Dictionary = Profile.daily_config(dseed2)
		_check(day._daily_sheet(dseed2)["cards"].size() == 3, "a full daily sheet shows three cards")
		day.screen = "menu"
		day._start_run("daily", dseed2)
		_check(day.game.loadout == String(d3["loadout"]) and day.game.packages == [String(d3["package"])]
			and day.game.mutators == [String(d3["mutator"])],
			"a daily run carries the seed's own config with nothing unlocked (%s)" % str(Profile.daily_config(dseed2)))
		_check(day.game.player["kit"] == Content.LOADOUTS[d3["loadout"]]["kit"],
			"...including its starting kit")
	# a run save written before the daily had its own button: no "kind" in
	# its header, so the old cfg toggle routes it - and it files to the board
	var lg = _bare_shell()
	lg.profile = Profile.new()
	lg.runs_dir = "user://test_shell_legacy_runs"
	var lf2 := FileAccess.open(TEST_RUN_SAVE, FileAccess.WRITE)
	lf2.store_line(var_to_str({"v": Shell.RUN_SAVE_VERSION, "seed": 31337, "tier": 0,
		"config": Profile.daily_game_config(31337)}).replace("\n", " "))
	lf2.store_line(var_to_str({"type": "end_turn"}))
	lf2.close()
	lg._legacy_seed_mode = "daily"
	lg._load_run()
	_check(lg.run_kind == "daily" and lg.game != null and lg.seed_v == 31337,
		"a kind-less save resumes as a daily under the legacy toggle (%s)" % lg.run_kind)
	lg.game.over = true
	lg._game_is_run = true
	lg._run_recorded = false
	lg._record_finished_run()
	_check(lg.profile.daily_best.has("31337") and lg.profile.runs == 0,
		"...and files to the daily board, not the career (%s)" % str(lg.profile.daily_best.keys()))
	for n in _dir_files(lg.runs_dir):
		DirAccess.remove_absolute(lg.runs_dir + "/" + n)
	DirAccess.remove_absolute(lg.runs_dir)
	# ...while the same save under the default toggle is a career run
	lg._legacy_seed_mode = "random"
	var lf3 := FileAccess.open(TEST_RUN_SAVE, FileAccess.WRITE)
	lf3.store_line(var_to_str({"v": Shell.RUN_SAVE_VERSION, "seed": 31338, "tier": 0, "config": {}}).replace("\n", " "))
	lf3.close()
	lg._load_run()
	_check(lg.run_kind == "career", "a kind-less save with no legacy toggle resumes as a career run")
	# and a save that names its kind wins over the legacy toggle
	lg._legacy_seed_mode = "daily"
	lg._start_run("career", 4242)
	lg._run_save.close()
	lg._run_save = null
	lg._load_run()
	_check(lg.run_kind == "career", "a header's own kind beats the legacy toggle")
	# a resumed DAILY leaves the career's DIFFICULTY alone: a daily's tier is
	# its seed's (0), and the next career run starts at the player's own choice
	# (mutation: restore the unconditional `sel_tier = run_tier` in _load_run)
	lg.profile.unlocked_tier = 2
	lg.sel_tier = 2
	lg._start_run("daily", 31337)
	lg._run_save.close()
	lg._run_save = null
	lg._load_run()
	_check(lg.run_kind == "daily" and lg.run_tier == 0 and lg.sel_tier == 2,
		"a resumed daily keeps the menu's difficulty (kind %s, run tier %d, menu %d)" % [lg.run_kind, lg.run_tier, lg.sel_tier])
	lg._start_run("career")
	_check(lg.run_kind == "career" and lg.run_tier == 2,
		"...so the next career run starts at difficulty 2 (%d)" % lg.run_tier)
	lg._run_save.close()
	lg._run_save = null
	lg.sel_tier = 0
	lg._load_run()
	_check(lg.run_kind == "career" and lg.sel_tier == 2,
		"a resumed career run still sets the menu to its own difficulty (%d)" % lg.sel_tier)
	for sh in [menu, day, lg]:
		if sh._run_save != null:
			sh._run_save.close()
			sh._run_save = null
		sh.free()
	DirAccess.remove_absolute(TEST_RUN_SAVE)  # the runs above wrote the scratch slot

	# --- Block D5: the resonance surface ------------------------------------
	# The shell must never re-derive the threshold rule; _resonance_state only
	# counts, and the ACTIVE flag has to come from the sim. These are the only
	# reachable checks headless (nothing calls a _draw*), so they pin the two
	# things the drawing code reads: the state rows and the card note.
	var rs = _bare_shell()
	for kit in [["seed_bomb", "overgrowth", "grow_spike"], ["solar_lance", "sun_flare", "mycelium_dash"],
			["water_jet", "vine_whip", "seed_bomb"], Content.LOADOUTS["tender"]["kit"]]:
		rs.game = Game.new(1, {"kit": kit, "pool": kit})
		var snap: Dictionary = rs.game.snapshot()
		var lit: Array = []
		for r in rs._resonance_state(snap):
			if bool(r["active"]):
				lit.append(String(r["id"]))
		_check(lit == rs.game._resonances(),
			"the shell's active set is the sim's, never re-derived: %s vs %s (%s)" % [
				str(lit), str(rs.game._resonances()), str(kit)])
	# counts fold a graft in, and a variant carries its base's tags
	rs.game = Game.new(1, {"kit": ["solar_lance", "sun_flare+corona", "mycelium_dash"], "grafts": ["oil_tithe"]})
	var fsnap: Dictionary = rs.game.snapshot()
	var fire_row := {}
	for r in rs._resonance_state(fsnap):
		if String(r["tag"]) == "fire":
			fire_row = r
	_check(int(fire_row.get("count", 0)) == 3 and bool(fire_row.get("active", false)),
		"the strip counts a variant and a graft toward the threshold: %s" % str(fire_row))
	_check(rs._resonance_line(fsnap).contains("FIRE 3/3"),
		"a lit row is upper-cased in the strip: %s" % rs._resonance_line(fsnap))
	# the swap arithmetic: a same-element drop must NOT badge BREAKS. Fire is
	# the one element that ships a row and only two BASES carry it, so a kit at
	# the threshold holds a sibling - the shape a forge or a locked kit makes.
	rs.game = Game.new(1, {"kit": ["solar_lance", "solar_lance+noon", "sun_flare", "seed_bomb", "mycelium_dash"]})
	var dsnap: Dictionary = rs.game.snapshot()
	# the word BREAKS lives on the card BADGE now (_drop_cards sets it from this
	# same note), so the note itself names the row and the count and nothing twice
	_check(rs._resonance_note(dsnap, rs._ability_tags("solar_lance"), true, []) == "Cinder Grip out (fire 2/3)",
		"dropping a fire card for an off-element pick breaks Cinder Grip: %s" % rs._resonance_note(
			dsnap, rs._ability_tags("solar_lance"), true, []))
	_check(rs._resonance_note(dsnap, rs._ability_tags("solar_lance"), true,
			rs._ability_tags("sun_flare+smoulder")) == "",
		"...and does not when the card being taken carries the same tag: %s" % rs._resonance_note(
			dsnap, rs._ability_tags("solar_lance"), true, rs._ability_tags("sun_flare+smoulder")))
	# an offer that would cross a threshold on a FULL kit owes a drop first
	rs.game = Game.new(1, {"kit": ["solar_lance", "sun_flare", "seed_bomb", "overgrowth", "mycelium_dash"]})
	var osnap: Dictionary = rs.game.snapshot()
	_check(rs._resonance_note(osnap, rs._ability_tags("solar_lance+pierce"), false, [], true).contains("would light")
			and rs._resonance_note(osnap, rs._ability_tags("solar_lance+pierce"), false).contains("lights"),
		"a threshold-crossing offer says 'would light' while a drop is still owed: %s" % rs._resonance_note(
			osnap, rs._ability_tags("solar_lance+pierce"), false, [], true))
	print("d5 shell: %s" % rs._resonance_line(fsnap))
	if rs._run_save != null:
		rs._run_save.close()
		rs._run_save = null
	rs.free()

	_check_back()
	_check_aim_cancel()
	_check_modal_dpad()
	_check_cleanse_hint()
	_check_card_text()
	_check_tier_clamp()
	_check_resume_stats()
	_check_names()
	_check_feedback()
	_check_danger_readouts()
	_check_lethal_guard()
	_check_intent_badges()
	_check_new_badges()
	_check_legacy_notice()
	_check_tutorial_keys()
	_check_menu_layout()
	_check_daily_layout()
	_check_career_sheet()
	_check_career_layout()
	_check_run_end()
	_check_over_facts()
	_check_over_text()
	_check_unlock_pager()
	_check_career_pings()
	_check_objective_line()
	_check_encounters()

	shell.free()
	shell2.free()
	_check(_real_files() == real_before,
		"no test shell wrote the player's real settings, profile, run save or runs dir")
	DirAccess.remove_absolute(TEST_PROFILE)
	DirAccess.remove_absolute(TEST_PROFILE + ".tmp")
	DirAccess.remove_absolute(TEST_CFG)
	for n in _dir_files(TEST_RUNS):
		DirAccess.remove_absolute(TEST_RUNS + "/" + n)
	DirAccess.remove_absolute(TEST_RUNS)
	if log_counter.errors > 0:
		fails += 1
		print("FAIL: %d engine/script error(s) while the body ran, first %d:" % [log_counter.errors, log_counter.first.size()])
		for m in log_counter.first:
			print("  " + m)
	print("FAILURES: %d" % fails if fails > 0 else "shell smoke: OK")
	_body_done = true
	OS.remove_logger(log_counter)
	quit(1 if fails > 0 else 0)


## A shell whose settings, career and run save all live at the scratch paths
## (set before `_ready`, which loads from them). Unlike _bare_shell it deletes
## nothing and keeps its live run, so one shell's save can restore in the next.
func _iso_shell():
	var sh = Shell.new()
	sh.profile_path = TEST_PROFILE
	sh.run_save_path = TEST_RUN_SAVE
	sh.cfg_path = TEST_CFG
	sh.runs_dir = TEST_RUNS
	return sh


## The player's real settings, profile and run save, as text ("" = absent),
## and the names in the real runs dir.
func _real_files() -> Array:
	var out: Array = []
	for pth in [Shell.CFG_PATH, Shell.PROFILE_PATH, Shell.RUN_SAVE_PATH]:
		out.append(FileAccess.get_file_as_string(pth) if FileAccess.file_exists(pth) else "")
	out.append(_dir_files(REAL_RUNS))
	return out


## A shell with no live run attached: these tests drive `game` directly, so
## nothing may be appended to (or restored from) the on-disk run log.
func _bare_shell(keep_save := false):
	var sh = Shell.new()
	sh.profile_path = TEST_PROFILE  # before _ready: it loads from here
	sh.run_save_path = TEST_RUN_SAVE  # ...and restores (or deletes) a run save from here
	sh.cfg_path = TEST_CFG  # ...and its settings: every bare shell boots on the defaults
	sh.runs_dir = TEST_RUNS  # ...and archives a finished run's log at scratch too
	DirAccess.remove_absolute(TEST_CFG)
	if not keep_save:
		DirAccess.remove_absolute(TEST_RUN_SAVE)  # an earlier shell's run is not restored here
	sh._ready()
	if sh._run_save != null:
		sh._run_save.close()
		sh._run_save = null
	sh._game_is_run = false
	sh.screen = "game"
	sh.mode = "normal"
	return sh


## --- CLEANSE tells the truth about why it refused ----------------------------
## "no corruption beside you" was the only refusal, and it is a lie in the two
## cases that happen: standing ON the slick (cleanse reaches a neighbour, never
## the tile underfoot) and a slick your own lance set alight (fire is not
## corruption until it burns down to ash). The tutorial's last cleanse step
## allows no ability, so a player told there is nothing there has nothing left
## to try - which is what a soft lock feels like from the outside.
func _check_cleanse_hint() -> void:
	var sh = _bare_shell()
	sh.game = Game.new(4242, {"bloom": 5})
	var g = sh.game
	var p: Vector2i = g.player["pos"]
	for t in g.terrain.keys().duplicate():
		if Content.is_corruption(String(g.terrain[t]["kind"])) and _man(t, p) <= 2:
			g.terrain.erase(t)
	# a) nothing anywhere near: the plain answer, unchanged
	sh._tap("cleanse")
	_check(sh.mode != "cleanse" and sh.flash == "no corruption beside you",
		"CLEANSE with nothing beside you says so (got %s)" % sh.flash)
	# b) standing ON it - the case that reads as a dead end
	g.terrain[p] = {"kind": "oil"}
	sh._tap("cleanse")
	_check(sh.mode != "cleanse" and sh.flash.contains("standing on it"),
		"CLEANSE while standing on the slick says to step off (got %s)" % sh.flash)
	# c) the slick is burning - the state the tutorial's own lance step makes
	g.terrain.erase(p)
	g.terrain[p + Vector2i(1, 0)] = {"kind": "fire", "ttl": 2}
	sh._tap("cleanse")
	_check(sh.mode != "cleanse" and sh.flash.contains("ash"),
		"CLEANSE beside a burning slick names the ash to wait for (got %s)" % sh.flash)
	# d) and the ash it leaves really is cleansable, which is what (c) promises
	g.terrain[p + Vector2i(1, 0)] = {"kind": "ash"}
	sh._tap("cleanse")
	_check(sh.mode == "cleanse", "CLEANSE opens on the ash the fire left")
	sh.free()


func _man(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## --- card text stays readable on a phone -------------------------------------
## The owner's report was "text very small on screens, even moreso in the shop
## where they are 6 or more options". The cause was _txt_fit: one line, shrunk
## to as little as 9px to make a long description fit. _card wraps to two lines
## now, but that only helps while the descriptions themselves stay short.
##
## The FIRST version of this gate measured one card at one viewport and was
## nearly worthless: it picked the seven-offer shrine because that card is the
## shortest, but a description's budget is set by WIDTH while the nominal it is
## compared against is int(h * 0.19), which falls with height - so at n = 7 the
## two happen to meet and "no shrinking" is free. It also never built a card
## with the upgrade "+", which is the only thing on the head row that collides,
## and it measured raw table rows rather than the strings the sheets compose.
## It passed while 19 of the 39 upgrade cards drew their "+" through the slot
## badge at 1080x2400 and while the eight-offer shrine drew 29px text.
##
## So: every card geometry a sheet can produce (shrine 1..8 offers, draft/drop,
## forge), across the phone shapes people have, over the composed strings, and
## the gate is APPARENT size - a fraction of viewport height - because that is
## what "too small" means on a screen whose pixels are not a fixed size.
const CARD_VIEWPORTS := [Vector2(540, 1200), Vector2(720, 1280), Vector2(1080, 1920),
	Vector2(1080, 2400), Vector2(1080, 2640), Vector2(1440, 3200),
	Vector2(1600, 2560), Vector2(2400, 1080)]
## Measured on the tree first, per the gate discipline: the worst case is the
## eight-offer shrine at 0.01167 of viewport height, so this line holds today.
const CARD_MIN_VH := 0.0115
const CARD_MAX_LINES := 2

func _check_card_text() -> void:
	var sh = _bare_shell()
	var rows: Array = []
	for aid in Content.ABILITY_DESC:
		var d := String(Content.ABILITY_DESC[aid])
		rows.append([aid, d])
		# what the draft and drop sheets actually compose (_draft_cards /
		# _drop_cards append the resonance note), not the bare table row
		rows.append([aid + " +note", "%s  ·  +fire 3/3 would light Cinder Grip" % d])
		rows.append([aid + " +breaks", "%s  ·  Cinder Grip out (fire 2/3)" % d])
	for gid in Content.GRAFTS:
		rows.append([gid, "Permanent  ·  %s  ·  +fire 2/3 Cinder Grip  ·  take one only"
			% Content.GRAFTS[gid]["desc"]])
	for iid in Content.ITEMS:
		rows.append([iid, "One use  ·  %s" % Content.ITEMS[iid]["desc"]])
	for rid in Content.RESONANCES:
		rows.append([rid, String(Content.RESONANCES[rid]["desc"])])
	var worst := 9.9
	var worst_at := ""
	var too_small := 0
	var too_many := 0
	var collisions := 0
	var worst_over := 0.0
	var worst_col := ""
	for vp in CARD_VIEWPORTS:
		var vw: float = vp.x
		var vh: float = vp.y
		var top: float = vh * 0.16 + vh * 0.05
		var heights: Array = []
		# _draw_shop's own arithmetic, for every offer count _shop_cards can emit:
		# heal + ability + 2 grafts + 2 press + forge + reroll is 8 (the item card
		# cannot coexist with the press cards), and 8 is a late-career board - the
		# player with the most to read gets the smallest type
		for n in range(1, 9):
			heights.append(minf(vh * 0.105, maxf(vh * 0.06,
				(vh * 0.86 - top - vh * 0.02 * (n - 1)) / n)))
		heights.append(vh * 0.105)  # draft and drop
		heights.append(vh * 0.115)  # the forge's fork sheet
		for h in heights:
			var r := Rect2(vw * 0.05, top, vw * 0.9, h)
			for row in rows:
				var L := sh._card_layout(r, "ab_default", "Mycelium Dash", String(row[1]), "", 2)
				var de: Dictionary = L["desc"]
				var frac: float = float(de["size"]) / vh
				if de["lines"].size() > CARD_MAX_LINES:
					too_many += 1
				if frac < CARD_MIN_VH:
					too_small += 1
				if frac < worst:
					worst = frac
					worst_at = "%s at %dx%d, card %dpx -> %dpx" % [
						row[0], int(vw), int(vh), int(h), int(de["size"])]
			# the head row must clear whatever sits on the card's right edge. The
			# name is _fit_size'd, so a long one grows until it meets its allowance
			# and the pips and the "+" are drawn AFTER it - reserve or collide.
			for aid2 in Content.ABILITIES:
				var nm := String(Content.ABILITIES[aid2]["name"])
				var upg: bool = Content.is_upgrade(aid2)
				for badge in ["UPGRADE", "AFFINITY", "BREAKS", ""]:
					var L2 := sh._card_layout(r, "ab_default", nm, "x", badge,
						int(Content.ABILITIES[aid2]["cost"]), 12 if badge == "" else -1, upg)
					var end_x: float = float(L2["name"]["pos"].x) + sh.font.get_string_size(
						nm, HORIZONTAL_ALIGNMENT_LEFT, -1, int(L2["name"]["size"])).x
					if L2.has("up"):
						end_x = float(L2["up"]["pos"].x) + sh.font.get_string_size(
							"+", HORIZONTAL_ALIGNMENT_LEFT, -1, int(L2["up"]["size"])).x
					elif int(L2["pips"]["n"]) > 0:
						end_x = float(L2["pips"]["pos"].x) \
							+ (int(L2["pips"]["n"]) - 1) * float(L2["pips"]["step"]) \
							+ float(L2["pips"]["radius"])
					var lim: float = r.position.x + r.size.x
					if L2.has("badge"):
						lim = float(L2["badge"]["pos"].x)
					elif L2.has("price"):
						lim = float(L2["price"]["icon_pos"].x)
					if end_x > lim:
						collisions += 1
						if end_x - lim > worst_over:
							worst_over = end_x - lim
							worst_col = "%s + %s at %dx%d card %dpx" % [nm, badge, int(vw), int(vh), int(h)]
	_check(too_small == 0, "%d card description(s) below %.2f%% of viewport height (worst: %s)" % [
		too_small, CARD_MIN_VH * 100.0, worst_at])
	_check(too_many == 0, "%d card description(s) need more than %d lines" % [too_many, CARD_MAX_LINES])
	_check(collisions == 0, "%d head row(s) overrun the badge or price by up to %.0fpx (worst: %s)" % [
		collisions, worst_over, worst_col])
	# and the last description line has to land inside the card
	var tight := sh._card_layout(Rect2(0, 0, 1080 * 0.9, 2400 * 0.105), "ab_default",
		"Mycelium Dash", String(Content.ABILITY_DESC["mycelium_dash"]), "AFFINITY", 2)
	var de2: Dictionary = tight["desc"]
	var last: float = float(de2["pos"].y) + float(de2["line_h"]) * (de2["lines"].size() - 1)
	_check(last + float(de2["size"]) * 0.3 <= 2400 * 0.105,
		"the last description line lands inside the card")
	print("card text: %d strings x %d viewports x 10 card geometries, worst %.4f%% of vh (%s)" % [
		rows.size(), CARD_VIEWPORTS.size(), worst * 100.0, worst_at])
	# the career layer's cards (the DAILY sheet today) sit at the draft's
	# geometry, h = 0.105vh, with their real icons, names and badges - and a
	# meta card's NAME is held to the same floor as its description, because
	# a name like "Skyrunner (needs Aeolian)" is the whole point of the card
	var meta: Array = []
	for sd in range(1, 31):
		for c in sh._daily_sheet(sd)["cards"]:
			meta.append(c)
	# ...and every CAREER sheet card, every tab and page, for a fresh career,
	# one mid-way (hints, partial progress, a gated loadout) and a maxed one
	# (every feat earned, the longest numbers a record can show)
	var n_daily := meta.size()
	var keep_profile = sh.profile
	for cp in _career_profiles():
		sh.profile = cp
		for tab in Shell.CAREER_TABS:
			var pages: int = int(sh._career_cards(tab, 0)["pages"])
			for pg in pages:
				for c in sh._career_cards(tab, pg)["cards"]:
					meta.append(c)
	# ...and every unlock pager card (stage 8): every milestone id, every
	# difficulty and every feat, against all three careers (a gated Skyrunner
	# on the fresh and mid-way ones, the package that opens it on the maxed)
	var n_career := meta.size() - n_daily
	var all_ids: Array = []
	for m in Content.MILESTONES:
		all_ids.append(String(m["id"]))
	for ti in Content.TIERS.size():
		all_ids.append("tier:%d" % (ti + 1))
	for fid in Content.FEATS:
		all_ids.append("feat:" + String(fid))
	for cp in _career_profiles():
		sh.profile = cp
		for c in sh._unlock_cards(all_ids):
			meta.append(c)
	sh.profile = keep_profile
	var m_small := 0
	var m_lines := 0
	var m_name := 0
	var m_col := 0
	var m_worst := 9.9
	var m_worst_at := ""
	for vp in CARD_VIEWPORTS:
		var vw: float = vp.x
		var vh: float = vp.y
		var r := Rect2(vw * 0.05, vh * 0.3, vw * 0.9, vh * 0.105)
		for c in meta:
			var L := sh._card_layout(r, String(c[0]), String(c[1]), String(c[2]), String(c[4]))
			var dfrac: float = float(L["desc"]["size"]) / vh
			var nfrac: float = float(L["name"]["size"]) / vh
			if dfrac < CARD_MIN_VH:
				m_small += 1
			if L["desc"]["lines"].size() > CARD_MAX_LINES:
				m_lines += 1
			if nfrac < CARD_MIN_VH:
				m_name += 1
			if minf(dfrac, nfrac) < m_worst:
				m_worst = minf(dfrac, nfrac)
				m_worst_at = "%s at %dx%d" % [c[1], int(vw), int(vh)]
			var end_x: float = float(L["name"]["pos"].x) + sh.font.get_string_size(String(c[1]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(L["name"]["size"])).x
			if L.has("badge") and end_x > float(L["badge"]["pos"].x):
				m_col += 1
	_check(m_small == 0, "%d meta card description(s) below %.2f%% vh" % [m_small, CARD_MIN_VH * 100.0])
	_check(m_lines == 0, "%d meta card description(s) need more than %d lines" % [m_lines, CARD_MAX_LINES])
	_check(m_name == 0, "%d meta card name(s) below %.2f%% vh (worst %s)" % [m_name, CARD_MIN_VH * 100.0, m_worst_at])
	_check(m_col == 0, "%d meta card name(s) run into their badge" % m_col)
	print("meta card text: %d daily + %d career + %d unlock cards x %d viewports, worst %.4f%% of vh (%s)" % [
		n_daily, n_career, meta.size() - n_daily - n_career, CARD_VIEWPORTS.size(), m_worst * 100.0, m_worst_at])
	sh.free()


## --- the Back button ---------------------------------------------------------
## Android's Back button (and gesture) used to KILL the app from any screen:
## application/config/quit_on_go_back defaults to true and nothing in the
## project handled NOTIFICATION_WM_GO_BACK_REQUEST. It is now one level up per
## press, through the single handler ESC also uses (shell/main.gd _back), so
## these drive the notification itself - the wiring is half of what is pinned.
func _check_back() -> void:
	# without the project.godot line the OS quits before the shell is asked
	_check(bool(ProjectSettings.get_setting("application/config/quit_on_go_back", true)) == false,
		"project.godot leaves the Back button to the shell")
	var bk = _bare_shell()
	bk.game = Game.new(4242, {"bloom": 30})
	# every sheet and overlay closes back to the map, and stays in the run
	for m in ["shop", "log", "help", "intro"]:
		bk.mode = m
		_back(bk)
		_check(bk.mode == "normal" and bk.screen == "game",
			"Back closes the %s sheet back to the map (mode %s)" % [m, bk.mode])
	# a held tooltip is over everything, so it goes first and nothing else moves
	bk.mode = "normal"
	bk.tooltip = ["Drill Bot - hp 3"]
	_check(bk._back(true) == "tooltip" and bk.tooltip.is_empty() and bk.screen == "game",
		"Back drops a held tooltip before anything else")
	# ...and it must STAY dropped. _process re-raises a tooltip for as long as
	# the press that raised it is still down and hold_ms has passed, so a Back
	# that cleared only the text was undone on the very next frame - and every
	# Back after it was eaten by the same tooltip in turn, so the button did
	# nothing at all while a finger rested on the map. _back drops the hold too.
	bk._ts = 40.0
	bk._mox = 0.0
	bk._moy = 0.0
	bk._vx0 = 0
	bk._vy0 = 0
	bk._vx1 = 999
	bk._vy1 = 999
	var bp: Vector2i = bk.game.player["pos"]
	bk._press_pos = Vector2(bp.x * 40.0 + 20.0, bp.y * 40.0 + 20.0)
	bk._show_tooltip(bk._press_pos)
	_check(not bk.tooltip.is_empty(), "a hold on the tender really raises a tooltip")
	bk._held = true
	bk._press_ms = Time.get_ticks_msec() - 5000  # the hold fired long ago
	_check(bk._back(true) == "tooltip", "Back drops the held tooltip")
	bk._process(0.1)
	_check(bk.tooltip.is_empty() and not bk._held,
		"...and the next frame does not put it straight back (%s)" % str(bk.tooltip))
	_check(bk._back(true) != "tooltip", "...so the next Back is not eaten by it too")
	bk.screen = "game"
	# the room camera is a view state, so Back zooms out before it leaves
	bk.zoom_room = true
	_check(bk._back(true) == "zoom" and not bk.zoom_room and bk.screen == "game",
		"Back leaves the room camera before it leaves the run")
	# the draft's drop sheet returns to the offer cards, having picked nothing
	bk.mode = "draft_drop"
	bk.mode_pick = 1
	var kit_b: Array = bk.game.player["kit"].duplicate()
	_back(bk)
	_check(bk.mode == "normal" and bk.game.player["kit"] == kit_b,
		"Back on the drop sheet returns to the offer cards without dropping")
	# the forge is a three-tap choice, so Back walks it back one tap at a time
	# and lands on the shrine sheet the forge card was tapped from
	bk.game.player["pos"] = bk.game.map["shrine"]
	bk._tap("shop")
	bk._tap("forge")
	bk._ability_press(0)
	bk._ability_press(1)
	_check(bk.mode == "up_variant", "the forge reaches its fork sheet (%s)" % bk.mode)
	_back(bk)
	_check(bk.mode == "up_scrap", "Back on the fork sheet returns to the scrap tap (%s)" % bk.mode)
	_back(bk)
	_check(bk.mode == "up_keep" and bk.mode_pick == -1,
		"Back on the scrap tap returns to the keep tap (%s)" % bk.mode)
	_back(bk)
	_check(bk.mode == "shop", "Back on the keep tap returns to the shrine sheet (%s)" % bk.mode)
	_check(bk.game.player["kit"] == kit_b and bk.game.shop.has("forge"),
		"...with the kit untouched and the forge still on offer")
	# the descent draft is the sim's phase, not a shell sheet: it cannot be
	# closed, so Back leaves for the menu (the run save carries the draft)
	bk.mode = "normal"
	bk.game.phase = "draft"
	_check(bk._back(true) == "menu" and bk.screen == "menu" and bk.game.phase == "draft",
		"Back in the descent draft leaves for the menu with the draft still pending")
	bk.screen = "game"
	bk.game.phase = "play"
	# normal play, the game-over sheet and the tutorial all go up to the menu
	_check(bk._back(true) == "menu" and bk.screen == "menu", "Back in normal play goes to the menu")
	bk.screen = "game"
	bk.game.over = true
	_check(bk._back(true) == "menu" and bk.screen == "menu", "Back on the over sheet goes to the menu")
	bk.screen = "tutorial"
	bk.game = Game.new(1, Tutorial.game_config())
	_check(bk._back(true) == "menu" and bk.screen == "menu", "Back in the tutorial goes to the menu")
	# the menu is the root: ONLY here does Back quit, and only for Back - ESC
	# on a desktop has never quit from the menu and still does not
	bk._tap("settings")
	_check(bk.mode == "settings", "the settings sheet opens")
	_check(bk._back(true) == "settings" and bk.mode == "normal" and bk.screen == "menu",
		"Back closes the settings sheet instead of quitting")
	bk._tap("daily")
	_check(bk.mode == "daily", "the daily sheet opens")
	var tries_b: Dictionary = bk.profile.daily_tries.duplicate()
	bk._key(KEY_X)
	_check(bk.mode == "daily", "a stray key leaves the daily sheet up")
	_check(bk._back(true) == "daily" and bk.mode == "normal" and bk.screen == "menu"
		and bk.profile.daily_tries == tries_b,
		"Back closes the daily sheet instead of quitting, starting nothing")
	bk._tap("daily")
	bk._key(KEY_ESCAPE)
	_check(bk.mode == "normal" and bk.screen == "menu", "ESC closes the daily sheet too")
	bk._tap("career")
	_check(bk.mode == "career", "the CAREER sheet opens")
	bk._tap("career_tab:records")
	bk._key(KEY_ENTER)
	bk._key(KEY_X)
	_check(bk.mode == "career" and bk.screen == "menu", "ENTER and a stray key leave the CAREER sheet up, starting nothing")
	_check(bk._back(true) == "career" and bk.mode == "normal" and bk.screen == "menu",
		"Back closes the CAREER sheet instead of quitting")
	bk._tap("career")
	bk._key(KEY_ESCAPE)
	_check(bk.mode == "normal" and bk.screen == "menu", "ESC closes the CAREER sheet too")
	_check(bk._back(false) == "root" and bk.screen == "menu", "ESC at the menu does not quit")
	_check(bk._back(true) == "quit", "Back at the menu is the one press that quits")
	# ESC is the same handler, so its gaps close with it: it used to page the
	# legend forward for ever and to do nothing at all on the over sheet
	bk.screen = "game"
	bk.game = Game.new(4242, {})
	bk.mode = "help"
	bk.help_page = 0
	bk._key(KEY_ESCAPE)
	_check(bk.mode == "normal", "ESC closes the legend instead of paging it (%s)" % bk.mode)
	bk.game.over = true
	bk._key(KEY_ESCAPE)
	_check(bk.screen == "menu", "ESC on the over sheet goes to the menu")
	bk.free()


## --- cancelling an aim --------------------------------------------------------
## A tile aim had NO free cancel on a touchscreen: tapping your own tile did
## nothing, CLEANSE flashed, END TURN cost a turn, and a D-pad press fell
## through to _move_or_strike - it MOVED you, and struck whatever stood beside
## you. Three ways out now, all free: the Back button, a D-pad press, and a
## second tap on the slot you armed. Every check below asserts the enemy's HP,
## the tender's position, the charge and the turn counter are all untouched.
func _check_aim_cancel() -> void:
	for way in ["back", "dpad", "dpad_button", "slot", "esc"]:
		var sh = _bare_shell()
		sh.game = Game.new(4242, {})
		var g = sh.game
		g.player["charge"] = 5
		var d := _open_dir(g)
		var en: Dictionary = _park_enemy(g, g.player["pos"] + d)
		sh._ability_press(1)  # seed_bomb: a TILE ability, so this is a tile aim
		_check(sh.mode == "target_tile", "%s: the tile ability arms a tile aim (%s)" % [way, sh.mode])
		_check(sh.flash.contains("cancel"), "%s: the aim flash names the cancel (%s)" % [way, sh.flash])
		var pos0: Vector2i = g.player["pos"]
		var hp0: int = int(en["hp"])
		var ch0: int = int(g.player["charge"])
		var tn0: int = g.total_turns
		match way:
			"back": sh._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
			"dpad": sh._dir_input(d)
			"dpad_button": sh._tap("dir:" + _dir_tag(d))
			"slot": sh._ability_press(1)
			"esc": sh._key(KEY_ESCAPE)
		# still IN the run: a cancel that dropped the player out to the menu
		# would leave mode "normal" too, and that is not a cancel
		_check(sh.mode == "normal" and sh.screen == "game",
			"%s cancels a tile aim and stays in the run (%s / %s)" % [way, sh.mode, sh.screen])
		_check(g.player["pos"] == pos0, "%s does not move the tender" % way)
		_check(int(en["hp"]) == hp0, "%s does not strike the enemy beside you (%d -> %d)" % [way, hp0, int(en["hp"])])
		_check(int(g.player["charge"]) == ch0 and g.total_turns == tn0,
			"%s costs no charge and no turn" % way)
		# the same three ways out of a DIRECTION aim, where a D-pad press is
		# the aim itself: there the slot tap and Back are what cancel
		sh._ability_press(0)  # solar_lance: a direction ability
		_check(sh.mode == "target_dir", "%s: the dir ability arms a dir aim (%s)" % [way, sh.mode])
		if way == "dpad" or way == "dpad_button":
			sh._ability_press(0)
		elif way == "back":
			sh._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		elif way == "esc":
			sh._key(KEY_ESCAPE)
		else:
			sh._ability_press(0)
		_check(sh.mode == "normal" and sh.screen == "game" and g.player["pos"] == pos0
				and int(en["hp"]) == hp0 and g.total_turns == tn0,
			"%s cancels a direction aim for free too" % way)
		sh.free()
	# tapping a DIFFERENT slot still switches the aim - the toggle is the slot
	# you armed, not any slot
	var sw = _bare_shell()
	sw.game = Game.new(4242, {})
	sw.game.player["charge"] = 5
	sw._ability_press(1)
	sw._ability_press(0)
	_check(sw.mode == "target_dir" and sw.mode_slot == 0,
		"tapping another slot re-aims instead of cancelling (%s %d)" % [sw.mode, sw.mode_slot])
	sw.free()


## --- a direction in a modal state ---------------------------------------------
## The forge is a three-tap modal choice, and its two SELECTION steps draw no
## sheet - so the D-pad and the arrow keys are still live right beside the
## SHRINE SHOP button the context line points at. Falling through to
## _move_or_strike there moved the tender, struck whatever stood next to it,
## spent a charge and dropped the forge, all out of a choice the player was
## still making. Same rule as a tile aim: a direction in a modal state means
## "get me out of this", and it is free. The forge is left standing, so the
## choice can simply be finished.
func _check_modal_dpad() -> void:
	for step in ["up_keep", "up_scrap", "up_variant"]:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var sh = _bare_shell()
			sh.game = Game.new(4242, {"bloom": 30})
			var g = sh.game
			g.player["pos"] = g.map["shrine"]
			g.player["charge"] = 5
			sh._tap("shop")
			sh._tap("forge")
			if step != "up_keep":
				sh._ability_press(0)
			if step == "up_variant":
				sh._ability_press(1)
			if sh.mode != step:
				sh.free()
				continue
			var en: Dictionary = _park_enemy(g, g.player["pos"] + d)
			var pos0: Vector2i = g.player["pos"]
			var hp0: int = int(en["hp"])
			var ch0: int = int(g.player["charge"])
			var tn0: int = g.total_turns
			var kit0: Array = g.player["kit"].duplicate()
			# both routes a real player has: the arrow key and the D-pad button
			# (the button is on screen because these steps draw no sheet)
			sh._key({Vector2i(1, 0): KEY_RIGHT, Vector2i(-1, 0): KEY_LEFT,
				Vector2i(0, 1): KEY_DOWN, Vector2i(0, -1): KEY_UP}[d])
			sh._tap("dir:" + _dir_tag(d))
			_check(g.player["pos"] == pos0 and int(en["hp"]) == hp0
					and int(g.player["charge"]) == ch0 and g.total_turns == tn0,
				"%s: a %s D-pad press moves nothing and costs nothing (%s %d %d %d)"
					% [step, _dir_tag(d), str(g.player["pos"]), int(en["hp"]),
						int(g.player["charge"]), g.total_turns])
			_check(sh.mode == step and g.player["kit"] == kit0,
				"%s: ...and the forge choice is still standing (%s)" % [step, sh.mode])
			sh.free()


## --- the difficulty row's second bound ----------------------------------------
## unlocked_tier is an INDEX into Content.TIERS and the one unlock load_from
## cannot filter against a table. A profile carrying a tier past the table's
## end used to clamp sel_tier to that number and then read Content.TIERS[99]
## in _menu_rows, which threw and returned ZERO rows - a menu with no PLAY and
## no QUIT, on a build that cannot be recovered from without clearing data.
func _check_tier_clamp() -> void:
	var tc = _bare_shell()
	tc.screen = "menu"
	tc.profile = Profile.new()
	tc.profile.unlocked_tier = 99  # a save from a build with more tiers
	tc.sel_tier = 99
	tc._clamp_selection()
	_check(tc.sel_tier <= Content.TIERS.size(), "an over-range tier clamps to the table (%d)" % tc.sel_tier)
	var rows := _rows(tc)
	_check(rows.has("PLAY") and rows.has("QUIT"), "...and the menu still offers PLAY and QUIT (%s)" % str(rows))
	var named := false
	for r in rows:
		if String(r).begins_with("DIFFICULTY"):
			named = true
	_check(named, "...and names the difficulty row it clamped to (%s)" % str(rows))
	# the cycler cannot walk back out of the table either
	for i in Content.TIERS.size() + 3:
		tc._tap("set:tier")
		_check(tc.sel_tier <= Content.TIERS.size(), "the DIFFICULTY cycler stays in the table (%d)" % tc.sel_tier)
	tc.free()


## Drive the Android Back button the way the OS does.
func _back(sh) -> void:
	sh._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)


## A direction with open floor next to the tender, so an enemy can be parked
## there and a D-pad press in that direction would really move or strike.
func _open_dir(g) -> Vector2i:
	var m: Dictionary = g.map
	var pp: Vector2i = g.player["pos"]
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var t: Vector2i = pp + d
		if t.x >= 0 and t.y >= 0 and t.x < int(m["w"]) and t.y < int(m["h"]) \
				and int(m["tiles"][t.y * int(m["w"]) + t.x]) == 1:
			return d
	return Vector2i(1, 0)


## Move one enemy onto `p` and every other one off the board, so the only
## thing a stray strike could hit is the one whose HP is being watched.
func _park_enemy(g, p: Vector2i) -> Dictionary:
	for e in g.enemies:
		e["pos"] = Vector2i(-9, -9)
	var en: Dictionary = g.enemies[0]
	en["pos"] = p
	return en


func _dir_tag(d: Vector2i) -> String:
	if d == Vector2i(1, 0):
		return "right"
	if d == Vector2i(-1, 0):
		return "left"
	if d == Vector2i(0, 1):
		return "down"
	return "up"


## The title screen's row labels, in menu order.
func _rows(sh) -> Array:
	var out: Array = []
	for row in sh._menu_rows():
		out.append(String(row[0]))
	return out


## The shrine sheet's tap tags, in sheet order.
func _tags(sh) -> Array:
	var out: Array = []
	for c in sh._shop_cards(sh.game.snapshot()):
		out.append(String(c[3]))
	return out


func _dir_files(path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(path)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not d.current_is_dir():
			out.append(n)
		n = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


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
		"ability":
			var slot := int(expect.get("slot", 0))
			var opts: Array = []
			for a in shell._legal_of("ability"):
				if int(a["slot"]) == slot:
					opts.append(a)
			if slot == 0:
				# lance: pick a direction with an enemy in the beam, else close in
				var pp2: Vector2i = g.player["pos"]
				for a in opts:
					var d2: Vector2i = a["target"]
					for i in range(1, 4):
						if _enemy_pos_at(g, pp2 + d2 * i):
							return a
				if not g.enemies.is_empty():
					return _approach(g, _nearest_enemy(g))
				return {"type": "end_turn"}
			# other slots: step onto adjacent growth first (verdant), then cast
			if g.terrain.get(g.player["pos"], {}).get("kind", "") != "growth":
				for a2 in g.legal_actions():
					if String(a2.get("type", "")) == "move" and 							g.terrain.get(g.player["pos"] + a2["dir"], {}).get("kind", "") == "growth":
						return a2
			if not opts.is_empty():
				return opts[0]
			return {"type": "end_turn"}
		"use_item":
			var ui: Array = shell._legal_of("use_item")
			if not ui.is_empty():
				return ui[0]
			for tt in g.terrain.keys():
				if String(g.terrain[tt]["kind"]) == "supply":
					return _approach(g, tt)
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


func _enemy_pos_at(g, p: Vector2i) -> bool:
	for e in g.enemies:
		if e["pos"] == p:
			return true
	return false


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


## --- a resumed run keeps its stats --------------------------------------------
## Android can take the app away mid-run; _load_run replays the action log, and
## the stats fold rides that replay. Write a save of a sprout run's first
## actions, resume it, and the shell's fold must equal a direct fold over the
## same actions - otherwise a resumed run would end on a game-over sheet that
## forgot everything before the interruption.
func _check_resume_stats() -> void:
	var seed_v := 11
	var g = Game.new(seed_v, {})
	var bot = Roster.make("sprout", seed_v)
	if bot.has_method("set_sim"):
		bot.set_sim(g)
	var st = RunStatsT.new()
	st.begin(g)
	var acts: Array = []
	while acts.size() < 150 and not g.over:
		var a: Dictionary = bot.choose_action(g.snapshot(), g.legal_actions())
		var evs: Array = g.step(a)
		if g.over:
			break  # a finished run is not resumed; keep the log one step short
		acts.append(a)
		st.feed(g, evs)
	var save_path: String = TEST_RUN_SAVE  # where _bare_shell restores from
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	f.store_line(var_to_str({"v": Shell.RUN_SAVE_VERSION, "seed": seed_v, "tier": 0, "config": {}}).replace("\n", " "))
	for a in acts:
		f.store_line(var_to_str(a).replace("\n", " "))
	f.close()
	var sh = _bare_shell(true)
	sh._load_run()
	_check(sh.game != null and not sh.game.over and sh.game.total_turns == g.total_turns,
		"the resumed run is the same game (%d actions)" % acts.size())
	_check(sh.stats != null and sh._stats_for == sh.game, "the resumed run carries a stats fold")
	if sh.stats != null:
		_check(str(sh.stats.summary()) == str(st.summary()),
			"a resumed run keeps its stats: %s vs %s" % [str(sh.stats.summary()).substr(0, 200), str(st.summary()).substr(0, 200)])
		_check(str(sh.stats.ctx) == str(st.ctx), "...down to the last step's ctx")
		_check(int(sh.stats.kills) > 0, "the resumed fold is not trivially empty (kills %d)" % int(sh.stats.kills))
	if sh._run_save != null:
		sh._run_save.close()
		sh._run_save = null
	sh.free()
	DirAccess.remove_absolute(save_path)
	print("resume stats: %d actions replayed, fold identical (kills %d, bloom earned %d)" % [
		acts.size(), int(st.kills), int(st.bloom_earned)])


## --- shell/names.gd: the one names module ------------------------------------
## The log's brackets use the SHORT source name (8c pins "(fire)"), a recap's
## attribution the LONG one; both come from here and nowhere else.
func _check_names() -> void:
	var short := {"fire:solar_lance": "fire", "collision:water_jet": "collision", "drill_bot": "Drill Bot",
		"ember_sap": "Ember Sap", "spore": "spores", "goo": "goo"}
	var long := {"fire:solar_lance": "Solar Lance fire", "collision:water_jet": "Water Jet slam",
		"drill_bot": "Drill Bot", "ember_sap": "Ember Sap", "spore": "spores", "goo": "goo", "fire:env": "fire"}
	for src in short:
		_check(Names.src_name(src) == short[src], "src_name(%s) == %s (got %s)" % [src, short[src], Names.src_name(src)])
	for src2 in long:
		_check(Names.src_long(src2) == long[src2], "src_long(%s) == %s (got %s)" % [src2, long[src2], Names.src_long(src2)])
	_check(Names.the_name("overseer") == "the Overseer", "the_name lowercases a leading The: %s" % Names.the_name("overseer"))
	_check(Names.the_name("drill_bot") == "the Drill Bot", "the_name adds the article")
	_check(Names.the_name("nope") == "it", "an unknown kind is 'it'")
	_check(Names.boss_name("overseer") == "The Overseer" and Names.boss_name("furnace_core") == "The Furnace Core",
		"boss_name starts a sentence: %s / %s" % [Names.boss_name("overseer"), Names.boss_name("furnace_core")])
	_check(Names.a_name("oil_sludge") == "an Oil Sludge", "a_name picks 'an' before a vowel")
	_check(Names.a_name("drill_bot") == "a Drill Bot", "a_name picks 'a' otherwise")
	_check(Names.a_name("") == "a machine", "a_name of nothing is a machine")
	_check(Names.a_name("overseer") == "the Overseer", "there is only one boss: a_name says 'the'")
	_check(Names.aname("solar_lance+noon") == "Noon Lance", "aname reads the ABILITIES row")
	_check(Names.source_name("cinder_grip") == "Cinder Grip" and Names.source_name("compost") == "Compost",
		"source_name reads resonances and grafts")
	# the floor title card: the boss floor names its boss and never asks for 0 cleanses
	var fs = _bare_shell()
	fs.game = Game.new(5, {})
	fs.game._enter_floor(7)
	var card: Array = fs._floor_card_lines(fs.game.snapshot())
	var joined := " | ".join(card)
	_check(joined.contains("defeat the") and not joined.contains("cleanse 0"),
		"floor 7's title card says who to defeat: %s" % joined)
	fs.game = Game.new(5, {})
	var card1: Array = fs._floor_card_lines(fs.game.snapshot())
	_check(card1.size() == 3 and String(card1[2]).begins_with("cleanse "),
		"a quota floor's card still asks for its cleanses: %s" % " | ".join(card1))
	fs.free()


## A Game.new(4242) board with enemy 0 turned into a drill bot parked beside
## the tender and every other enemy off the board: [game, enemy, tile].
func _fb_board() -> Array:
	var g = Game.new(4242, {})
	var t: Vector2i = g.player["pos"] + _open_dir(g)
	var e: Dictionary = _park_enemy(g, t)
	e["kind"] = "drill_bot"
	e["hp"] = 3
	return [g, e, t]


func _texts(calls: Array) -> Array:
	var out: Array = []
	for c in calls:
		out.append(String(c["text"]))
	return out


func _log_texts(res: Dictionary) -> Array:
	var out: Array = []
	for ln in res["log"]:
		out.append(String(ln["text"]))
	return out


func _any_has(lines: Array, needle: String) -> bool:
	for l in lines:
		if String(l).contains(needle):
			return true
	return false


func _fx_of(fxs: Array, kind: String) -> Array:
	return fxs.filter(func(f): return String(f["kind"]) == kind)


## --- the feedback layer (shell/feedback.gd) ----------------------------------
## Every payoff the sim resolves is named where it happens, the cleanse float
## tells the truth, kills land with weight, the boss explains itself, the log
## reads like a story and the sound cap really is worst-first. All asserted as
## data: render_frame.gd draws no fx, and there is no display here.
func _check_feedback() -> void:
	var sh = _bare_shell()

	# 1. cleanse gain through _act: the float is the GAIN, never the running total
	var b1 := _fb_board()
	var g1 = b1[0]
	(b1[1] as Dictionary)["pos"] = Vector2i(-9, -9)
	var ct: Vector2i = b1[2]
	g1.terrain[ct] = {"kind": "oil"}
	g1.bloom = 10
	g1.player["charge"] = 3
	sh.game = g1
	sh._fx = []
	sh._act({"type": "cleanse", "target": ct})
	var floats: Array = _fx_of(sh._fx, "float").map(func(f): return [String(f["text"]), f["col"]])
	_check(floats.has(["+1", Feedback.GOLD]) and not _any_has(floats.map(func(f): return f[0]), "+11"),
		"the cleanse float is the real gain +1 in gold, not the balance: %s" % str(floats))
	var cl_line := ""
	for l in sh.log_lines:
		if String(l).begins_with("Cleansed"):
			cl_line = String(l)
	_check(cl_line.begins_with("Cleansed +1 bloom · green 1/"), "the cleanse line says what it paid: %s" % cl_line)
	g1.terrain[ct] = {"kind": "oil", "bloom": 0}
	g1.player["charge"] = 3
	sh._fx = []
	sh._act({"type": "cleanse", "target": ct})
	var floats2: Array = _fx_of(sh._fx, "float").map(func(f): return [String(f["text"]), f["col"]])
	_check(floats2.has(["+0", Feedback.DIM]), "enemy-made oil floats a grey +0: %s" % str(floats2))
	_check(_any_has(sh.log_lines, "enemy-made oil pays no bloom"), "...and the log says why: %s" % str(sh.log_lines))

	# 2. a landed hook is named where it lands
	var b2 := _fb_board()
	var g2 = b2[0]
	var e2: Dictionary = b2[1]
	var t2: Vector2i = b2[2]
	sh.game = g2
	var pre2: Dictionary = sh._pre_step()
	var r2: Dictionary = Feedback.step([{"t": "ignite", "tile": t2}, {"t": "hook", "id": "cinder_grip", "on": "ignite", "tile": t2},
		{"t": "status", "id": e2["id"], "status": "root", "turns": 1}], pre2, g2, {}, 1000)
	var cg: Array = r2["callouts"].filter(func(c): return String(c["text"]) == "CINDER GRIP")
	_check(cg.size() == 1 and Vector2(cg[0]["pos"]) == Vector2(t2) and cg[0]["col"] == Feedback.GOLD,
		"a landed resonance hook calls out CINDER GRIP in gold at its tile: %s" % str(_texts(r2["callouts"])))
	_check(_any_has(_log_texts(r2), "Cinder Grip roots the Drill Bot") and not _any_has(_log_texts(r2), "rooted for"),
		"the log names the hook, not a bare status: %s" % str(_log_texts(r2)))
	_check(r2["sounds"].any(func(p): return String(p["id"]) == "combo"), "a combo rings the chime")

	# 3. a hook on an empty tile is no landing
	var r3: Dictionary = Feedback.step([{"t": "ignite", "tile": t2}, {"t": "hook", "id": "ember_sap", "on": "ignite", "tile": t2},
		{"t": "ignite", "tile": t2 + Vector2i(5, 0)}], pre2, g2, {}, 1000)
	_check(not _texts(r3["callouts"]).has("EMBER SAP") and not _any_has(_log_texts(r3), "Ember Sap"),
		"an unlanded hook claims nothing: %s / %s" % [str(_texts(r3["callouts"])), str(_log_texts(r3))])

	# 4. rider per
	var r4: Dictionary = Feedback.step([{"t": "ability", "id": "grow_spike", "target": t2}, {"t": "rider", "id": "grow_spike", "kind": "per", "amt": 1},
		{"t": "damage", "who": "drill_bot", "id": e2["id"], "amt": 4, "src": "grow_spike"}], pre2, g2, {}, 1000)
	var gp: Array = r4["callouts"].filter(func(c): return String(c["text"]) == "GROWTH +1 dmg")
	_check(gp.size() == 1 and Vector2(gp[0]["pos"]) == Vector2(t2), "a per rider calls GROWTH +1 dmg at the enemy: %s" % str(_texts(r4["callouts"])))
	_check(_log_texts(r4).has("Grow Spike: +1 dmg (growth beside the target)"), "...and logs why: %s" % str(_log_texts(r4)))

	# 5. rider bonus
	var r5: Dictionary = Feedback.step([{"t": "ability", "id": "sun_flare", "target": null}, {"t": "rider", "id": "sun_flare", "kind": "bonus", "amt": 1},
		{"t": "damage", "who": "drill_bot", "id": e2["id"], "amt": 2, "src": "sun_flare"}], pre2, g2, {}, 1000)
	_check(_texts(r5["callouts"]).has("BURNING +1 dmg") and _log_texts(r5).has("Sun Flare: +1 dmg (target burning)"),
		"a bonus rider reads BURNING +1 dmg: %s / %s" % [str(_texts(r5["callouts"])), str(_log_texts(r5))])

	# 6. rider then claims its status: one callout, the combo one
	var r6: Dictionary = Feedback.step([{"t": "ability", "id": "seed_bomb+tangle", "target": t2}, {"t": "growth", "tile": t2},
		{"t": "status", "id": e2["id"], "status": "root", "turns": 1}, {"t": "rider", "id": "seed_bomb+tangle", "kind": "then", "amt": 1}],
		pre2, g2, {}, 1000)
	var at_e: Array = r6["callouts"].filter(func(c): return Vector2(c["pos"]) == Vector2(t2))
	_check(at_e.size() == 1 and String(at_e[0]["text"]) == "ROOTED!" and at_e[0]["col"] == Feedback.GOLD,
		"a then-rider's status is one gold ROOTED!: %s" % str(_texts(r6["callouts"])))
	_check(_log_texts(r6).has("Tangle Bomb roots the Drill Bot"), "...logged as the ability's doing: %s" % str(_log_texts(r6)))

	# 7. surge and verdant
	var pp: Vector2i = g2.player["pos"]
	var r7: Dictionary = Feedback.step([{"t": "verdant", "tile": pp}, {"t": "ability", "id": "grow_spike", "target": t2},
		{"t": "surge", "id": "grow_spike", "keys": ["dmg"]}], pre2, g2, {}, 1000)
	var sg: Array = r7["callouts"].filter(func(c): return String(c["text"]) == "SURGE +1 dmg")
	_check(sg.size() == 1 and Vector2(sg[0]["pos"]) == Vector2(pp) and not _texts(r7["callouts"]).has("VERDANT"),
		"a surge reads SURGE +1 dmg at the growth, no VERDANT: %s" % str(_texts(r7["callouts"])))
	var r7b: Dictionary = Feedback.step([{"t": "verdant", "tile": pp}, {"t": "ability", "id": "seed_bomb", "target": t2}], pre2, g2, {}, 1000)
	_check(_texts(r7b["callouts"]).has("VERDANT") and _log_texts(r7b).has("Verdant: Seed Bomb costs 1 less"),
		"a discount-only verdant reads VERDANT: %s / %s" % [str(_texts(r7b["callouts"])), str(_log_texts(r7b))])

	# 8. collision, block, ignite, tithe
	var r8: Dictionary = Feedback.step([{"t": "damage", "who": "drill_bot", "id": e2["id"], "amt": 1, "src": "collision:water_jet"}],
		pre2, g2, {}, 1000)
	_check(_texts(r8["callouts"]).has("COLLISION"), "a collision calls COLLISION")
	var r8b: Dictionary = Feedback.step([{"t": "shield_absorb", "amt": 1}], pre2, g2, {}, 1000)
	_check(_texts(r8b["callouts"]).has("BLOCKED 1") and _log_texts(r8b).has("Your shield blocks 1"), "a block reads BLOCKED 1")
	var r8c: Dictionary = Feedback.step([{"t": "ignite", "tile": t2}, {"t": "ignite", "tile": t2 + Vector2i(1, 0)},
		{"t": "ignite", "tile": t2 + Vector2i(2, 0)}], pre2, g2, {}, 1000)
	var bursts: Array = _fx_of(r8c["fx"], "burst").filter(func(f): return f["col"] == Color("ff8a2a"))
	_check(_texts(r8c["callouts"]).count("IGNITE") == 1 and bursts.size() == 3 and _log_texts(r8c).has("Oil ignites (3 tiles)"),
		"three ignites: one IGNITE, three bursts, one folded line: %s / %d / %s" % [str(_texts(r8c["callouts"])), bursts.size(), str(_log_texts(r8c))])
	g2.player["grafts"] = ["oil_tithe"]
	var r8d: Dictionary = Feedback.step([{"t": "tithe", "id": "solar_lance"}], pre2, g2, {}, 1000)
	_check(_texts(r8d["callouts"]).has("TITHE -1") and _log_texts(r8d).has("Oil Tithe: Solar Lance costs 1 less"),
		"a tithe names the graft: %s" % str(_log_texts(r8d)))
	g2.player["grafts"] = []

	# 9. the bounty is the constant, never the running total the event carries
	var pre9: Dictionary = pre2.duplicate(true)
	pre9["pos"][777] = Vector2(3, 4)
	pre9["kinds"][777] = "drill_bot"
	var r9: Dictionary = Feedback.step([{"t": "damage", "who": "drill_bot", "id": 777, "amt": 1, "src": "strike"},
		{"t": "death", "who": "drill_bot", "id": 777}, {"t": "bounty", "bloom": 99}], pre9, g2, {}, 1000)
	var bty: Array = r9["callouts"].filter(func(c): return String(c["text"]) == "BOUNTY +%d" % Content.ELITE_BOUNTY)
	_check(bty.size() == 1 and Vector2(bty[0]["pos"]) == Vector2(3, 4), "the bounty floats where the elite fell: %s" % str(_texts(r9["callouts"])))
	_check(_log_texts(r9).has("Elite bounty +%d bloom" % Content.ELITE_BOUNTY), "...and logs the bounty")
	_check(not _any_has(_texts(r9["callouts"]) + _log_texts(r9), "99"), "the running total 99 appears nowhere")

	# 10. the cap keeps four regular callouts, resonance first
	var cap_evs: Array = [{"t": "shield_absorb", "amt": 1}, {"t": "immune", "id": e2["id"]},
		{"t": "ignite", "tile": t2 + Vector2i(3, 0)}, {"t": "tithe", "id": "solar_lance"},
		{"t": "damage", "who": "drill_bot", "id": e2["id"], "amt": 1, "src": "collision:water_jet"},
		{"t": "verdant", "tile": pp}, {"t": "resisted", "id": e2["id"], "status": "root"},
		{"t": "ignite", "tile": t2}, {"t": "hook", "id": "cinder_grip", "on": "ignite", "tile": t2},
		{"t": "status", "id": e2["id"], "status": "root", "turns": 1}]
	var all10: Array = Feedback.callouts(cap_evs, pre2, g2, {})
	var reg10: Array = all10.filter(func(c): return not bool(c["big"]))
	_check(reg10.size() <= Feedback.CALLOUT_CAP and String(all10[0]["text"]) == "CINDER GRIP",
		"8 callouts: at most %d kept, the resonance first: %s" % [Feedback.CALLOUT_CAP, str(_texts(all10))])

	# 11. the chime climbs, and a room clear adds the octave
	var three: Array = []
	for i in 3:
		three.append({"text": "C%d" % i, "pos": Vector2(i, 0), "col": Feedback.GOLD, "prio": 70, "combo": true, "big": false})
	var ch: Array = Feedback.sounds([], g2, {}, three, false).filter(func(p): return String(p["id"]) == "combo")
	var pitches: Array = ch.map(func(p): return float(p["pitch"]))
	var delays: Array = ch.map(func(p): return int(p["delay"]))
	_check(ch.size() == 3 and absf(pitches[0] - 1.0) < 0.001 and absf(pitches[1] - 1.1225) < 0.001
		and absf(pitches[2] - 1.2599) < 0.001 and delays == [120, 210, 300],
		"three combos chime up the scale: %s at %s" % [str(pitches), str(delays)])
	var ch4: Array = Feedback.sounds([], g2, {"room_cleared": true}, three, false).filter(func(p): return String(p["id"]) == "combo")
	_check(ch4.size() == 4 and absf(float(ch4[3]["pitch"]) - 2.0) < 0.001, "a room clear adds an octave note")

	# 12. the cap is worst-first, through the _play_events wrapper
	sh.game = g2
	var base12: Array = [{"t": "move", "who": "player", "to": pp}, {"t": "ability", "id": "seed_bomb", "target": t2},
		{"t": "damage", "who": "player", "amt": 1, "src": "drill_bot"}, {"t": "death", "who": "drill_bot", "id": 9999},
		{"t": "boss_phase", "phase": 2}]
	var ids12: Array = sh._play_events(base12).map(func(p): return String(p["id"]))
	_check(ids12 == ["boss", "hurt", "kill"], "three sounds, worst first: %s" % str(ids12))
	var ids12b: Array = sh._play_events(base12 + [{"t": "player_death", "cause": "drill_bot"}]).map(func(p): return String(p["id"]))
	_check(ids12b == ["death"], "a death silences the rest: %s" % str(ids12b))
	g2.won = true
	var ids12c: Array = sh._play_events(base12).map(func(p): return String(p["id"]))
	g2.won = false
	_check(ids12c == ["win"], "a win plays the fanfare alone: %s" % str(ids12c))

	# 13. kill weight through _act: gold blow, ghost, hit-stop, lunge, shake
	var b13 := _fb_board()
	var g13 = b13[0]
	var e13: Dictionary = b13[1]
	e13["hp"] = 1
	g13.player["charge"] = 3
	var d13: Vector2i = Vector2i(b13[2]) - Vector2i(g13.player["pos"])
	var sh13 = _bare_shell()
	sh13.game = g13
	sh13._act({"type": "strike", "dir": d13})
	var blow: Array = _fx_of(sh13._fx, "float").filter(func(f): return String(f["text"]) == "-1")
	_check(blow.size() == 1 and blow[0]["col"] == Feedback.GOLD and float(blow[0]["scale"]) == 1.5 and bool(blow[0]["bold"]),
		"the killing blow is gold, bold and 1.5x: %s" % str(blow))
	var ghosts: Array = _fx_of(sh13._fx, "ghost")
	_check(ghosts.size() == 1 and Vector2(ghosts[0]["pos"]) == Vector2(b13[2]), "the dead machine leaves a ghost on its tile")
	_check(sh13._freeze_end - sh13._freeze_start == Feedback.HITSTOP_MS, "a kill freezes the fx clock for %d ms" % Feedback.HITSTOP_MS)
	_check(sh13._lunge_dir == Vector2(d13), "the tender lunges toward the strike: %s" % str(sh13._lunge_dir))
	_check(sh13._shake_mag >= 2.5, "a kill shakes the screen (%.2f)" % sh13._shake_mag)
	sh13.free()
	var r13: Dictionary = Feedback.step([{"t": "damage", "who": "drill_bot", "id": e2["id"], "amt": 2, "src": "strike"}], pre2, g2, {}, 1000)
	var nf: Array = _fx_of(r13["fx"], "float")
	_check(not bool(r13["hitstop"]) and nf.size() == 1 and absf(float(nf[0]["scale"]) - 1.1) < 0.001 and not bool(nf[0]["bold"]),
		"a non-lethal 2 is no hit-stop, scale 1.1, not bold: %s" % str(nf))

	# 14. multi-kill, room clear and streak come from the fold's ctx
	_check(_texts(Feedback.callouts([], pre2, g2, {"step_kills": 1, "turn_kills": 2})).has("DOUBLE KILL"), "two in a turn: DOUBLE KILL")
	var dk: Array = Feedback.step([], pre2, g2, {"step_kills": 1, "turn_kills": 2}, 1000)["fx"].filter(
		func(f): return String(f["kind"]) == "callout" and String(f["text"]) == "DOUBLE KILL")
	_check(dk.size() == 1 and float(dk[0]["scale"]) == 1.35, "DOUBLE KILL is a big callout")
	_check(_texts(Feedback.callouts([], pre2, g2, {"step_kills": 1, "turn_kills": 3})).has("TRIPLE KILL"), "three: TRIPLE KILL")
	_check(Feedback.callouts([], pre2, g2, {"step_kills": 0, "turn_kills": 2}).is_empty(), "no kill this step: no callout")
	_check(_texts(Feedback.callouts([], pre2, g2, {"room_cleared": true})).has("ROOM CLEAR"), "room_cleared: ROOM CLEAR")
	_check(_texts(Feedback.callouts([], pre2, g2, {"step_kills": 1, "turn_kills": 1, "kill_streak": 3})).has("STREAK 3"),
		"the first kill of a third turn running: STREAK 3")

	# 15. a resonance lighting for the first time gets its banner
	g2.player["kit"] = ["solar_lance", "sun_flare", "seed_bomb"]
	g2.player["grafts"] = ["oil_tithe"]
	var bn: Array = Feedback.banners([], pre2, g2, {"res_new": ["cinder_grip"]})
	_check(not bn.is_empty() and String(bn[0]["lines"][0]) == "CINDER GRIP AWAKENS" and String(bn[0]["lines"][1]).begins_with("fire 3/3"),
		"the awakening banner names the resonance and its count: %s" % str(bn))
	g2.player["grafts"] = []

	# 16. the boss shield is visible before the hit is wasted
	var g16 = Game.new(4242, {})
	g16.enemies.clear()
	var d16: Vector2i = _open_dir(g16)
	var bp: Vector2i = Vector2i(g16.player["pos"]) + d16
	var boss: Dictionary = g16._spawn("overseer", bp)
	boss["hp"] = 5
	var goo_t := Vector2i(-1, -1)
	for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nb: Vector2i = bp + dd
		g16.terrain.erase(nb)
		if goo_t == Vector2i(-1, -1) and nb != Vector2i(g16.player["pos"]) and g16._tile(nb) == 1:
			goo_t = nb
	g16.terrain[goo_t] = {"kind": "goo"}
	_check(g16.core_shield_up(int(boss["id"])), "a gated boss with goo beside it and no growth is shielded")
	g16.player["charge"] = 3
	sh.game = g16
	var pre16: Dictionary = sh._pre_step()
	var ev16: Array = g16.step({"type": "strike", "dir": d16})
	_check(ev16.any(func(ev): return String(ev.get("t", "")) == "core_shielded"), "striking it emits core_shielded")
	var r16: Dictionary = Feedback.step(ev16, pre16, g16, {}, 1000)
	var shc: Array = r16["callouts"].filter(func(c): return String(c["text"]) == "SHIELDED")
	_check(shc.size() == 1 and shc[0]["col"] == Feedback.CYAN and not _fx_of(r16["fx"], "ring").is_empty(),
		"a wasted hit floats a cyan SHIELDED and a ring: %s" % str(_texts(r16["callouts"])))
	_check(_log_texts(r16).has("The Overseer is shielded: cleanse or grow beside it"), "...and says how to break it: %s" % str(_log_texts(r16)))
	for dd2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nb2: Vector2i = bp + dd2
		if nb2 != goo_t and nb2 != Vector2i(g16.player["pos"]) and g16._tile(nb2) == 1:
			g16.terrain[nb2] = {"kind": "growth"}
			break
	_check(not g16.core_shield_up(int(boss["id"])), "growth beside the boss drops the shield")
	var bph: Array = Feedback.banners([{"t": "boss_phase", "phase": 2}], pre16, g16, {})
	_check(not bph.is_empty() and String(bph[0]["lines"][0]) == "THE OVERSEER QUICKENS" and bph[0]["col"] == Feedback.BOSS,
		"a boss phase says what changed: %s" % str(bph))
	var two_ph: Array = [{"t": "boss_phase", "phase": 2}, {"t": "boss_phase", "phase": 3}]
	var bph2: Array = Feedback.banners(two_ph, pre16, g16, {})
	var ph_lines: Array = Feedback.log_entries(two_ph, pre16, g16, {})
	_check(bph2.size() == 1 and String(bph2[0]["lines"][0]) == "THE OVERSEER CLOGS ITS VENTS" and ph_lines.size() == 2,
		"two phases in a step: one banner (the higher), two log lines: %s / %s" % [str(bph2), str(ph_lines)])

	# 17. a reinforcement names its real kind
	var b17 := _fb_board()
	var g17 = b17[0]
	(b17[1] as Dictionary)["pos"] = Vector2i(-9, -9)
	sh.game = g17
	var pre17: Dictionary = sh._pre_step()
	var v1: Vector2i = b17[2]
	g17._spawn("coal_golem", v1)
	_check(Feedback.log_entries([{"t": "reinforcement", "tile": v1}], pre17, g17, {}).map(func(l): return l["text"])
		== ["A vent releases a Coal Golem"], "the furnace's golem is named as it arrives")
	var g17b = _fb_board()[0]
	for e in g17b.enemies:
		e["pos"] = Vector2i(-9, -9)
	sh.game = g17b
	var pre17b: Dictionary = sh._pre_step()
	var pp17: Vector2i = g17b.player["pos"]
	g17b._spawn("drill_bot", pp17 + Vector2i(30, 30))
	g17b._spawn("drill_bot", pp17 + Vector2i(31, 30))
	var lines17: Array = Feedback.log_entries([{"t": "reinforcement", "tile": pp17 + Vector2i(30, 30)},
		{"t": "reinforcement", "tile": pp17 + Vector2i(31, 30)}], pre17b, g17b, {}).map(func(l): return l["text"])
	_check(lines17 == ["Vents release 2 Drill Bots"], "two of a kind fold into one line: %s" % str(lines17))
	# a summoned child destroyed in the same step is named from its own death event
	var eng: Dictionary = g17b._spawn("extractor_engine", pp17 + Vector2i(30, 31))
	var pre17c: Dictionary = sh._pre_step()
	var sum17: Array = Feedback.log_entries([{"t": "summon", "id": eng["id"], "child": 9999},
		{"t": "death", "who": "sludgeling", "id": 9999}], pre17c, g17b, {}).map(func(l): return l["text"])
	_check(sum17.size() >= 1 and String(sum17[0]) == "Extractor Engine summons a Sludgeling",
		"a child spawned and killed in one step is still named: %s" % str(sum17))

	# 18. repeats count up instead of vanishing
	var ll: Array = []
	var lc: Array = []
	for s18 in ["A", "A", "A", "B", "B"]:
		Feedback.log_push(ll, lc, s18, "info")
	_check(ll == ["A x3", "B x2"] and lc.size() == ll.size(), "log_push counts repeats: %s / %s" % [str(ll), str(lc)])
	# through the real path: two illegal steps, _act -> _feedback -> _log
	var sh18 = _bare_shell()
	sh18.game = Game.new(4242, {})
	var n18: int = sh18.log_lines.size()
	_check(not sh18.game.legal_actions().any(func(a): return String(a.get("type", "")) == "descend"),
		"descend is illegal on a fresh floor (the probe the merge test spends)")
	sh18._act({"type": "descend"})
	sh18._act({"type": "descend"})
	_check(sh18.log_lines.size() == n18 + 1 and String(sh18.log_lines.back()) == "Can't do that x2"
		and sh18.log_cats.size() == sh18.log_lines.size(),
		"two illegal actions through _act merge into one line: %s" % str(sh18.log_lines))
	sh18.free()

	# 18b. two then-riders in one step: a claim is "then" for a status and an
	# INT for a rider index, and the walk back from the second rider meets the
	# first rider's int claim (String(int) used to throw there)
	var g18b = _fb_board()[0]
	var e18b: Dictionary = g18b.enemies[0]
	sh.game = g18b
	var pre18b: Dictionary = sh._pre_step()
	var two_then: Array = [
		{"t": "status", "id": e18b["id"], "status": "root", "turns": 1},
		{"t": "rider", "id": "seed_bomb+tangle", "kind": "then", "amt": 1},
		{"t": "status", "id": e18b["id"], "status": "stun", "turns": 1},
		{"t": "rider", "id": "vine_whip+lash", "kind": "then", "amt": 1},
	]
	var cl18b: Dictionary = Feedback.claims(two_then, g18b)
	_check(cl18b.get(0) == "then" and cl18b.get(1) == 0 and cl18b.get(2) == "then" and cl18b.get(3) == 2,
		"each then-rider claims its own status: %s" % str(cl18b))
	_check(Feedback._then_claimed(two_then, 3, cl18b) == [2] and Feedback._then_claimed(two_then, 1, cl18b) == [0],
		"the walk back stops at the earlier rider's int claim")
	var r18b: Dictionary = Feedback.step(two_then, pre18b, g18b, {}, 1000)
	var t18b: Array = _texts(r18b["callouts"])
	var l18b: Array = _log_texts(r18b)
	_check(t18b.has("ROOTED!") or t18b.any(func(t): return String(t).begins_with("ROOTED")),
		"two then-riders in a step still float their statuses: %s" % str(t18b))
	_check(l18b.size() == 2, "...and log one line each: %s" % str(l18b))

	# 19. vocabulary tripwire: every word table covers the shipped content
	for aid in Content.ABILITIES:
		var row: Dictionary = Content.ABILITIES[aid]
		for eff in row.get("effects", []):
			if eff.has("per"):
				_check(Feedback.PER_WORDS.has(String(eff["per"].get("count", ""))), "PER_WORDS covers %s's count" % aid)
				for k in eff["per"].get("add", {}):
					_check(Feedback.UNIT.has(String(k)), "UNIT covers %s's per add key %s" % [aid, k])
			if eff.has("bonus"):
				var conds: Array = eff["bonus"].get("if", [])
				if not conds.is_empty() and Dictionary(conds[0]).has("target_on"):
					_check(Feedback.TARGET_ON_WORDS.has(String(conds[0]["target_on"][0])), "TARGET_ON_WORDS covers %s" % aid)
		for sk in Dictionary(row.get("surge", {})):
			if String(sk) != "cost":  # cost prices the cast; only stat keys reach a surge event
				_check(Feedback.UNIT.has(String(sk)), "UNIT covers %s's surge key %s" % [aid, sk])
	for st in Content.STATUSES:
		_check(Feedback.STATUS_WORDS.has(String(st)), "STATUS_WORDS covers status %s" % st)
	for table in [Content.GRAFTS, Content.RESONANCES, Content.ABILITIES]:
		for sid in table:
			for hrow in table[sid].get("hooks", []):
				for heff in hrow.get("effects", []):
					_check(Feedback.HOOK_LANDING_OPS.has(String(heff.get("op", ""))),
						"hook op %s of %s has a landing signature" % [heff.get("op", ""), sid])
	for kind in Content.ENEMIES:
		if Content.ENEMIES[kind]["traits"].has("boss"):
			_check(Feedback.BOSS_PHASE_LINES.has(kind) and Feedback.BOSS_PHASE_LINES[kind].has(2)
				and Feedback.BOSS_PHASE_LINES[kind].has(3), "boss %s has phase 2 and 3 words" % kind)
	# every boss phase log line, composed with its boss's own name, fits the
	# log (test 20's bot runs never reach floor 7, so this is the boss floor's
	# only length pin) and reads with one separator, never "X: y: z"
	for bk in Feedback.BOSS_PHASE_LINES:
		_check(Content.ENEMIES.has(bk), "BOSS_PHASE_LINES row %s names a real boss" % bk)
		for ph in Feedback.BOSS_PHASE_LINES[bk]:
			var bl: String = Feedback.boss_line(String(bk), int(ph))
			_check(bl.length() <= Feedback.LOG_LINE_MAX and bl.begins_with(Names.boss_name(bk) + " - ")
				and bl.count(":") <= 1,
				"boss phase line fits %d chars with one separator: '%s' (%d)" % [Feedback.LOG_LINE_MAX, bl, bl.length()])
			var shl: String = "%s is shielded: cleanse or grow beside it" % Names.subj(bk)
			_check(shl.length() <= Feedback.LOG_LINE_MAX, "the core-shield line fits for %s: %s" % [bk, shl])
	# ...and every BOSS_PHASE_JOINS alternative (the phase said without the
	# machine that did not come) composes the same way
	for bk in Feedback.BOSS_PHASE_JOINS:
		for ph in Feedback.BOSS_PHASE_JOINS[bk]:
			var jl: String = Feedback.boss_line(String(bk), int(ph), [])
			_check(Feedback.BOSS_PHASE_LINES.has(bk) and Feedback.BOSS_PHASE_LINES[bk].has(ph)
				and jl.length() <= Feedback.LOG_LINE_MAX and jl.begins_with(Names.boss_name(bk) + " - ")
				and jl != Feedback.boss_line(String(bk), int(ph)),
				"the no-reinforcement phase line fits and differs: '%s' (%d)" % [jl, jl.length()])

	# 20. bot-driven: real games through _act
	var any_callout := false
	var fx_ok := true
	var raw := ""
	var long_line := ""
	var cats_ok := true
	for seed_v in [1, 2]:
		var sh20 = _bare_shell()
		sh20.game = Game.new(seed_v, {"loadout": "flarekeeper", "grafts": ["ember_sap", "compost"]})
		var bot = Roster.make("optimizer", seed_v)
		if bot.has_method("set_sim"):
			bot.set_sim(sh20.game)
		var n := 0
		while n < 400 and not sh20.game.over:
			sh20.mode = "normal"
			sh20._act(bot.choose_action(sh20.game.snapshot(), sh20.game.legal_actions()))
			n += 1
			fx_ok = fx_ok and sh20._fx.size() <= 40
			for f in sh20._fx:
				any_callout = any_callout or String(f["kind"]) == "callout"
			# after EVERY step, not once at the end: the log keeps only the
			# newest LOG_KEEP lines, and every line a step writes (or bumps to
			# "xN") is in it right after that step (mutation: append a raw pack
			# id to the floor-2 line - read only at the end, that line is long
			# trimmed away and the gate passes)
			for l in sh20.log_lines:
				if String(l).contains("_") and raw == "":
					raw = String(l)
				if String(l).length() > Feedback.LOG_LINE_MAX and long_line == "":
					long_line = String(l)
			cats_ok = cats_ok and sh20.log_lines.size() == sh20.log_cats.size()
		sh20.free()
	_check(any_callout, "real games produce callouts")
	_check(fx_ok, "the fx list never grows past 40")
	_check(raw == "", "no raw id reaches the log: %s" % raw)
	_check(long_line == "", "no log line runs past 60 chars: %s" % long_line)
	_check(cats_ok, "the log keeps one category per line")
	sh.free()
	print("feedback: 20 cases, chime %s, bot runs clean" % str(pitches))


## --- danger readability (shell/danger.gd) ------------------------------------
## The sim's three forecasts are pinned in tests/test_grammar.gd "fq"; these
## pin what the shell makes of them: the verdicts, the words, the sizes the
## words draw at, the chips' layout, the lethal guard and the intent badges.

## Every open direction from the tender, in DIRS order.
func _open_dirs(g) -> Array:
	var out: Array = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if g._open(g.player["pos"] + d):
			out.append(d)
	return out


## Game 4242 with one drill bot beside the tender striking it for `dmg`,
## charge `charge`, every other enemy and all terrain cleared, smog at 0.
## Returns [game, a free direction to step, the attacker's direction].
func _lethal_fixture(dmg: int, charge: int) -> Array:
	var g = Game.new(4242)
	g.terrain.clear()
	g.enemies.clear()
	g.smog = 0
	var dirs := _open_dirs(g)
	var dhit: Vector2i = dirs[0]
	var dmove: Vector2i = dirs[1]
	var a: Dictionary = g._spawn("drill_bot", g.player["pos"] + dhit)
	a["intent"] = {"type": "attack", "tile": g.player["pos"], "dmg": dmg}
	g.player["charge"] = charge
	return [g, dmove, dhit]


## Game 4242 at 2 HP with `n` drill bots beside the tender, each striking it
## for 2, every other enemy and all terrain cleared, smog 0 and no quota (so
## no earlier near-miss rule speaks before the exact one).
func _exact_fixture(n: int):
	var g = Game.new(4242)
	g.terrain.clear()
	g.enemies.clear()
	g.smog = 0
	g.green_need = 0
	g.player["hp"] = 2
	var dirs := _open_dirs(g)
	for i in n:
		var b: Dictionary = g._spawn("drill_bot", g.player["pos"] + dirs[i])
		b["intent"] = {"type": "attack", "tile": g.player["pos"], "dmg": 2}
	return g


## Floor 7 with only its boss (1 HP, idle) beside the tender and a drill bot
## on another side about to hit for 99, no terrain, no smog: striking the boss
## wins, striking the drill bot still dies. [game, boss, minion, dirs]
func _boss_minion_fixture() -> Array:
	var gw := Game.new(3)
	gw._enter_floor(7)
	gw.terrain.clear()
	var boss_w: Dictionary = {}
	for e in gw.enemies.duplicate():
		if Content.ENEMIES[e["kind"]]["traits"].has("boss"):
			boss_w = e
		else:
			gw.enemies.erase(e)
	var wd: Array = _open_dirs(gw)
	_check(not boss_w.is_empty() and wd.size() >= 2, "fixture: floor 7 has its boss and two open sides")
	boss_w["pos"] = gw.player["pos"] + wd[0]
	boss_w["hp"] = 1
	boss_w["intent"] = {"type": "idle"}
	var killer: Dictionary = gw._spawn("drill_bot", gw.player["pos"] + wd[1])
	killer["intent"] = {"type": "attack", "tile": gw.player["pos"], "dmg": 99}
	gw.smog = 0
	return [gw, boss_w, killer, wd]


## The ONE config under which a game draws encounter packs and biome
## reinforcements (Block E, stage 9). That is the default config: the
## pre-registered measurement passed on every line and the block ships
## default-on (docs/BALANCE.md, 2026-11-22). Were it ever moved behind a
## mutator, only this line changes (every stage-9 check below builds its
## games through _pack_config(), and tests/test_draw.gd reads this same
## constant as ShellTest.PACK_CONFIG).
const PACK_CONFIG := {}


func _pack_config() -> Dictionary:
	return PACK_CONFIG.duplicate(true)


## The screen point at the centre of map tile `t` on shell `sh`.
func _tile_px(sh, t: Vector2i) -> Vector2:
	return Vector2(sh._mox + (t.x + 0.5) * sh._ts, sh._moy + (t.y + 0.5) * sh._ts)


## A bare shell playing `g`, with the danger cache invalidated.
func _danger_shell(g):
	var sh = _bare_shell()
	sh.game = g
	sh._danger_rev += 1
	return sh


func _check_danger_readouts() -> void:
	const Danger := preload("res://shell/danger.gd")
	# one HP rule: hp <= max(3, max_hp / 4); a lethal forecast outranks it
	for r in [[3, 10, "low"], [4, 10, "ok"], [4, 16, "low"], [5, 16, "ok"], [3, 7, "low"],
			[4, 7, "ok"], [2, 7, "low"], [9, 10, "ok"]]:
		_check(Danger.hp_state(r[0], r[1], false) == r[2], "hp %d/%d is %s" % [r[0], r[1], r[2]])
	_check(Danger.hp_state(9, 10, true) == "lethal", "a lethal forecast outranks full HP")
	# the SKIES chips and the bar's alert
	var chips: Array = Danger.sky_chips({"choke_in": 5, "choking": false, "spawn_in": 11, "spawn_open": 1,
		"spawn_sealed": 0, "dim_in": -1})
	_check(chips.size() == 2 and chips[0]["icon"] == "ic_choke" and chips[0]["text"] == "5"
		and chips[0]["col"] == Danger.COL_AMBER and chips[1]["icon"] == "vent" and chips[1]["text"] == "11"
		and chips[1]["col"] == Danger.COL_TEXT, "chips: choke 5 amber, vent 11 cream (%s)" % str(chips))
	_check(Danger.sky_alert({"choke_in": 5}) == "amber" and Danger.sky_alert({"choke_in": 6}) == ""
		and Danger.sky_alert({"choking": true, "choke_in": 2}) == "red", "sky alert: amber at 5, none at 6, red while choking")
	chips = Danger.sky_chips({"choke_in": 2, "choking": true, "spawn_in": 3, "spawn_open": 0, "spawn_sealed": 1, "dim_in": 4})
	_check(chips.size() == 3 and chips[0]["col"] == Danger.COL_RED and chips[1]["col"] == Danger.COL_SEALED
		and chips[2]["key"] == "dim", "choking chip red, sealed vents green, the dim chip within 9")
	chips = Danger.sky_chips({"choke_in": 1, "spawn_in": 1, "spawn_open": 2, "dim_in": 12})
	_check(chips.size() == 2 and chips[0]["col"] == Danger.COL_RED and chips[1]["col"] == Danger.COL_AMBER,
		"choke 1 red, vent 1 amber, no dim chip beyond 9 turns")
	chips = Danger.sky_chips({"choke_in": 9, "spawn_in": 4, "spawn_open": 0, "spawn_sealed": 0, "dim_in": -1})
	_check(chips[1]["col"] == Danger.COL_DIM, "every vent occupied: the vent chip greys")
	# the context line, word for word
	var d := {"ok": true, "fc": {"dmg": 3, "absorbed": 0, "by_src": {"drill_bot": 2, "smog": 1}, "dies": true}, "sky": {}}
	var cl: Dictionary = Danger.context_line(d, false)
	_check(cl["text"] == "! INCOMING 3 - LETHAL  ·  Drill Bot, smog" and cl["col"] == Danger.COL_RED and cl["pulse"],
		"lethal line names its sources, red and pulsing (%s)" % cl["text"])
	d["fc"] = {"dmg": 2, "absorbed": 0, "by_src": {"drill_bot": 2}, "dies": false}
	_check(Danger.context_line(d, false)["text"] == "! INCOMING 2  ·  Drill Bot", "incoming, not lethal")
	d["fc"] = {"dmg": 4, "absorbed": 0, "by_src": {"drill_bot": 1, "rust_hound": 1, "smog": 1, "fire:solar_lance": 1}, "dies": false}
	_check(Danger.context_line(d, false)["text"] == "! INCOMING 4  ·  Drill Bot, fire +2",
		"four sources: two named (ties by id, the short form), then +2 (%s)" % Danger.context_line(d, false)["text"])
	d["fc"] = {"dmg": 2, "absorbed": 2, "by_src": {}, "dies": false}
	_check(Danger.context_line(d, false)["text"] == "! INCOMING 2 - shield holds", "shield holds")
	d["fc"] = {"dmg": 0, "absorbed": 0, "by_src": {}, "dies": false}
	d["sky"] = {"choke_in": 3, "choking": false, "spawn_in": 9, "spawn_open": 1}
	_check(Danger.context_line(d, false)["text"] == "Smog chokes in 3 - cleansing thins it", "choke soon, stairs asleep")
	_check(Danger.context_line(d, true)["text"] == "Smog chokes in 3 - descend to escape it", "choke soon, stairs awake")
	d["sky"]["choke_in"] = 1
	_check(Danger.context_line(d, true)["text"] == "Smog chokes NEXT TURN - descend to escape it"
		and Danger.context_line(d, false)["text"] == "Smog chokes NEXT TURN - cleansing thins it", "choke next turn")
	# the boss floor has no stairs (green 0/0): never "descend to escape it"
	d["sky"]["choke_in"] = 3
	var g7 := Game.new(3)
	g7._enter_floor(7)
	var d7 := 0
	for a in g7.legal_actions():
		if String(a.get("type", "")) == "descend":
			d7 += 1
	_check(int(g7.snapshot()["green_need"]) == 0 and d7 == 0, "fixture: floor 7 needs no green and has no descent")
	_check(not Danger.stairs_awake(g7.snapshot()), "boss floor: green 0/0, but no stairs tile, so no stairs awake")
	_check(Danger.context_line(d, Danger.stairs_awake(g7.snapshot()))["text"] == "Smog chokes in 3 - cleansing thins it",
		"boss floor: no descent offered (%s)" % Danger.context_line(d, Danger.stairs_awake(g7.snapshot()))["text"])
	# ...and from its fifth cleanse on a boss-floor cleanse pays no relief
	# (Game._act_cleanse: green_need 0 + 4), so the remedy stops pointing at
	# one: "cleanse it all" while the floor restore (smog -8) is still to come,
	# "no longer" once it has happened - read off the live compute (mutation:
	# return true from cleanse_thins, or word every remedy "cleansing thins
	# it", and the dry arena still promises a cleanse that does nothing)
	var rem_want := {3: ["Smog chokes in 3 - cleansing thins it", "Smog chokes in 3 - cleansing thins it"],
		4: ["Smog chokes in 3 - cleanse it all to thin it", "Smog chokes in 3 - cleanses no longer thin it"]}
	for have in rem_want:
		for ri in 2:
			var gr := Game.new(3)
			gr._enter_floor(7)
			gr.enemies.clear()
			gr.terrain.clear()
			gr.greened = have
			gr.map["restored"] = ri == 1
			gr.smog = int(gr.floor_def(7)["smog_choke"]) - 3
			var rl := String(Danger.context_line(Danger.compute(gr), Danger.stairs_awake(gr.snapshot())).get("text", ""))
			_check(rl == String(rem_want[have][ri]),
				"boss floor, %d cleanses, restored %s: '%s' (got '%s')" % [have, str(ri == 1), rem_want[have][ri], rl])
	# the relief mirror against the sim's own cleanse: on floor 1 with other
	# corruption left (no restore), a cleanse lowers the smog exactly when
	# Danger.cleanse_thins says so (mutation: move the tier edge in either)
	var gm := Game.new(4242)
	gm.enemies.clear()
	var oil_t: Vector2i = gm.player["pos"] + _open_dirs(gm)[0]
	gm.terrain[oil_t] = {"kind": "oil"}
	gm.player["charge"] = 9
	_check(gm._count_corruption() >= 2, "fixture: corruption besides the cleansed tile, so no restore (%d)" % gm._count_corruption())
	var mirror_bad: Array = []
	var mirror_n := 0
	for need in [0, 3]:
		for have in range(0, 9):
			var gc = gm.clone()
			gc.green_need = need
			gc.greened = have
			gc.smog = 20
			gc.step({"type": "cleanse", "target": oil_t})
			mirror_n += 1
			if int(gc.greened) != have + 1 or (int(gc.smog) < 20) != Danger.cleanse_thins(have, need):
				mirror_bad.append("%d/%d: smog %d, greened %d" % [have, need, int(gc.smog), int(gc.greened)])
	_check(mirror_bad.is_empty() and mirror_n == 18,
		"Danger.cleanse_thins mirrors _act_cleanse's relief on %d real cleanses (%s)" % [mirror_n, str(mirror_bad)])
	# an ordinary floor whose quota was RECLAMPED to 0 (the corruption went
	# without a cleanse): green_need 0, the stairs awake - the descent is offered
	var gq := Game.new(3)
	for t in gq.terrain.keys().duplicate():
		if Content.is_corruption(String(gq.terrain[t]["kind"])):
			gq.terrain.erase(t)
	gq._reclamp_quota()
	var sq: Dictionary = gq.snapshot()
	_check(int(sq["floor"]) == 1 and int(sq["green_need"]) == 0 and int(sq["greened"]) == 0,
		"fixture: floor 1 reclamped to green 0/0 (%d/%d)" % [int(sq["greened"]), int(sq["green_need"])])
	gq.player["pos"] = gq.map["stairs"]
	_check(gq.legal_actions().any(func(a): return String(a.get("type", "")) == "descend"),
		"fixture: the reclamped floor's stairs really take a descent")
	_check(Danger.stairs_awake(sq) and Danger.context_line(d, Danger.stairs_awake(sq))["text"] == "Smog chokes in 3 - descend to escape it",
		"reclamped green 0/0 on an ordinary floor: descend to escape it")
	d["sky"] = {"choke_in": 20, "choking": false, "spawn_in": 1, "spawn_open": 1}
	_check(Danger.context_line(d, true)["text"] == "The vents release next turn", "vents next turn")
	d["sky"]["spawn_open"] = 0
	_check(Danger.context_line(d, true).is_empty(), "every vent sealed or taken: nothing to say")
	_check(Danger.context_line({"ok": false}, false).is_empty(), "over or drafting: nothing to say")
	# the guard's words, by escape
	var gd := {"fc": {"dmg": 3}, "escapes": {"move": true, "item": [0], "descend": true}}
	_check(Danger.guard_flash(gd) == "LETHAL (3) - step off, or tap again to end turn", "guard: step off first")
	gd["escapes"] = {"move": false, "strike": true, "item": [0], "descend": true}
	_check(Danger.guard_flash(gd) == "LETHAL (3) - strike first, or tap again to end turn", "guard: only a strike saves")
	gd["escapes"] = {"move": false, "item": [1], "descend": true}
	_check(Danger.guard_flash(gd) == "LETHAL (3) - use the glowing item, or tap again", "guard: then the item")
	gd["escapes"] = {"move": false, "item": [], "descend": true}
	_check(Danger.guard_flash(gd) == "LETHAL (3) - descend, or tap again to end turn", "guard: then descend")
	gd["escapes"] = {}
	_check(Danger.guard_flash(gd) == "LETHAL (3) - tap again to end the turn", "guard: nothing saves you")
	# a WINNING escape is named before stepping off (mutation: drop the `win`
	# match at the top of guard_flash and both of these read "step off")
	gd["escapes"] = {"move": true, "strike": true, "item": [0], "descend": true, "win": "strike"}
	_check(Danger.guard_flash(gd) == "LETHAL (3) - strike to win, or tap again to end turn",
		"guard: a boss-killing strike is advised first (%s)" % Danger.guard_flash(gd))
	gd["escapes"] = {"move": true, "strike": false, "item": [1], "descend": false, "win": "item"}
	_check(Danger.guard_flash(gd) == "LETHAL (3) - the glowing item wins, or tap again",
		"guard: a winning item is advised first (%s)" % Danger.guard_flash(gd))
	# the words claim an UNNAMED win only where the player cannot pick the
	# wrong blow: with two legal strikes (boss and minion adjacent) the flash
	# names the target (mutation: drop the `strike_dirs` arm and this reads
	# "strike to win"), with no target to name it falls back to step off >
	# strike first, and with a winning item only that slot glows (mutation:
	# glow_items returns every surviving item and this lights slot 0 too)
	gd["escapes"] = {"move": true, "strike": true, "item": [], "descend": false, "win": "strike",
		"strike_dirs": 2, "win_kind": "overseer"}
	_check(Danger.guard_flash(gd) == "LETHAL (3) - strike the Overseer to win, or tap again",
		"guard: two legal strikes name the winning target (%s)" % Danger.guard_flash(gd))
	gd["escapes"] = {"move": true, "strike": true, "item": [], "descend": false, "win": "strike", "strike_dirs": 2}
	_check(Danger.guard_flash(gd) == "LETHAL (3) - step off, or tap again to end turn",
		"guard: two legal strikes and no target to name fall back to step off (%s)" % Danger.guard_flash(gd))
	gd["escapes"] = {"move": false, "strike": true, "item": [], "descend": false, "win": "strike", "strike_dirs": 2}
	_check(Danger.guard_flash(gd) == "LETHAL (3) - strike first, or tap again to end turn",
		"guard: ...then to strike first (%s)" % Danger.guard_flash(gd))
	var es_w := {"move": false, "strike": false, "item": [0, 1], "descend": false, "win": "item", "win_item": 1}
	_check(Danger.glow_items(es_w) == [1], "only the winning item glows (%s)" % str(Danger.glow_items(es_w)))
	es_w["win"] = ""
	_check(Danger.glow_items(es_w) == [0, 1], "with no win every surviving item glows")
	# cues: transitions only
	var p0 := {"ok": true, "floor": 1, "lethal": false, "sky": {"choke_in": 6, "choking": false}}
	var p1 := {"ok": true, "floor": 1, "lethal": false, "sky": {"choke_in": 5, "choking": false}}
	_check(Danger.cues(p0, p1)["sounds"] == ["warn"] and Danger.cues(p0, p1)["banner"].is_empty(), "entering the amber window ticks")
	_check(Danger.cues(p1, {"ok": true, "floor": 1, "lethal": false, "sky": {"choke_in": 4}})["sounds"].is_empty(), "staying in it does not")
	var c1: Dictionary = Danger.cues({"ok": true, "floor": 1, "sky": {"choke_in": 2}}, {"ok": true, "floor": 1, "sky": {"choke_in": 1}})
	_check(c1["banner"] == ["THE SMOG THICKENS", "it chokes from next turn"] and c1["sounds"] == ["warn"], "choke next turn: banner + one tick")
	_check(Danger.cues({"ok": true, "floor": 1, "lethal": false, "sky": {}}, {"ok": true, "floor": 1, "lethal": true, "sky": {}})["sounds"] == ["warn"],
		"lethal switching on ticks")
	_check(Danger.cues({"ok": true, "floor": 1, "lethal": true, "sky": {}}, {"ok": true, "floor": 1, "lethal": true, "sky": {}})["sounds"].is_empty(),
		"lethal staying on does not")
	_check(Danger.cues({"ok": true, "floor": 1, "sky": {"choking": true, "choke_in": 2}}, {"ok": true, "floor": 1, "sky": {"choking": true, "choke_in": 1}})["sounds"].is_empty(),
		"no choke cue while already choking")
	_check(Danger.cues({"ok": true, "floor": 1, "lethal": true, "sky": {"choke_in": 4}}, {"ok": true, "floor": 2, "lethal": true, "sky": {"choke_in": 4}})["sounds"] == ["warn"],
		"a new floor forgets the old one: lethal and the window both count as entered, one tick")
	_check(Danger.cues(p0, {"ok": false})["sounds"].is_empty(), "nothing cues once the game is over or drafting")
	# hysteresis: a cue fires only on a NEW minimum of the choke countdown on
	# this floor, so a cleanse relief and the end turn after it stay quiet
	var sk := func(n): return {"ok": true, "floor": 1, "lethal": false, "sky": {"choke_in": n, "choking": false}}
	var hc: Dictionary = Danger.cues(sk.call(2), sk.call(1), Danger.NO_CUE)
	_check(hc["banner"] == ["THE SMOG THICKENS", "it chokes from next turn"] and int(hc["announced"]) == 1,
		"hysteresis: reaching 1 banners and remembers 1")
	var relief: Dictionary = Danger.cues(sk.call(1), sk.call(3), int(hc["announced"]))
	_check(relief["sounds"].is_empty() and relief["banner"].is_empty() and int(relief["announced"]) == 1,
		"hysteresis: the cleanse relief (1 -> 3) is silent")
	var back: Dictionary = Danger.cues(sk.call(3), sk.call(1), int(relief["announced"]))
	_check(back["sounds"].is_empty() and back["banner"].is_empty(),
		"hysteresis: the end turn back to 1 does not banner or tick again (%s)" % str(back))
	var w1: Dictionary = Danger.cues(sk.call(6), sk.call(5), Danger.NO_CUE)
	var w2: Dictionary = Danger.cues(sk.call(5), sk.call(7), int(w1["announced"]))
	var w3: Dictionary = Danger.cues(sk.call(7), sk.call(6), int(w2["announced"]))
	var w4: Dictionary = Danger.cues(sk.call(6), sk.call(5), int(w3["announced"]))
	_check(w1["sounds"] == ["warn"] and w2["sounds"].is_empty() and w3["sounds"].is_empty() and w4["sounds"].is_empty(),
		"hysteresis: leaving the window on a relief and re-entering it does not tick twice")
	var w5: Dictionary = Danger.cues(sk.call(2), sk.call(1), int(w4["announced"]))
	_check(w5["banner"].size() == 2, "hysteresis: a NEW minimum (1) still banners")
	var nf: Dictionary = Danger.cues(sk.call(2), {"ok": true, "floor": 2, "sky": {"choke_in": 1}}, 1)
	_check(nf["banner"].size() == 2, "hysteresis: a new floor forgets what the last one announced")
	var rs: Dictionary = Danger.cues(sk.call(3), sk.call(2), Danger.NO_CUE)
	_check(rs["sounds"].is_empty() and int(rs["announced"]) == 2,
		"hysteresis: a countdown already standing before the step (a reset, a resume) counts as announced")
	# escapes: a WINNING action is an escape of its kind (the boss-killing strike)
	var bmw := _boss_minion_fixture()
	var gw = bmw[0]
	var boss_w: Dictionary = bmw[1]
	var killer: Dictionary = bmw[2]
	var wd: Array = bmw[3]
	var dzw: Dictionary = Danger.compute(gw)
	var ew: Dictionary = Danger.escapes(gw)
	var cw = gw.clone()
	cw.step({"type": "strike", "dir": wd[0]})
	_check(bool(dzw["lethal"]) and cw.over and cw.won, "fixture: lethal, and the strike on the 1-HP boss wins the run")
	_check(bool(ew["strike"]), "a boss-killing strike counts as a strike escape (%s)" % str(ew))
	# ...and is the one the guard names (mutation: drop the `win` assignment in
	# Danger.escapes; the unit rows above hold it ahead of a surviving step)
	_check(String(ew.get("win", "")) == "strike" and String(ew.get("win_kind", "")) == String(boss_w["kind"]),
		"the winning strike is marked as the win, on the boss's tile (%s)" % str(ew))
	dzw["escapes"] = ew
	# the drill bot beside the tender is a SECOND legal strike - and striking
	# it leaves the tender to die - so the flash must name the boss, never
	# say a bare "strike to win" (the residual: `strikes` counted only the
	# surviving directions, read 1 here and gave the bare words; mutation:
	# count strike_dirs after the forecast filter)
	var cl_minion = gw.clone()
	cl_minion.step({"type": "strike", "dir": wd[1]})
	_check(not (cl_minion.over and cl_minion.won)
		and (cl_minion.over or bool(cl_minion.end_turn_forecast()["dies"])),
		"fixture: the strike on the minion does not save the tender")
	_check(int(ew.get("strike_dirs", 0)) == 2,
		"every legal strike direction is counted, the losing one too (%s)" % str(ew))
	var want_named := "strike %s to win" % Names.the_name(String(boss_w["kind"]))
	_check(Danger.guard_flash(dzw).contains(want_named) and not Danger.guard_flash(dzw).contains("strike to win,"),
		"boss and a minion adjacent: the live flash names the boss (%s)" % Danger.guard_flash(dzw))
	# ...and with the minion gone the winning strike is the only one: bare
	# words (lethal now from the smog: 1 HP, the choke one tick away)
	gw.enemies.erase(killer)
	gw.player["hp"] = 1
	gw.smog = int(gw.floor_def(int(gw.floor_num))["smog_choke"]) - 1
	var dzw1: Dictionary = Danger.compute(gw)
	var ew1: Dictionary = Danger.escapes(gw)
	_check(bool(dzw1["lethal"]) and int(ew1.get("strike_dirs", 0)) == 1
		and String(ew1.get("win", "")) == "strike",
		"fixture: lethal from the smog, the boss the only legal strike (%s)" % str(ew1))
	dzw1["escapes"] = ew1
	_check(Danger.guard_flash(dzw1).contains("strike to win"),
		"one legal strike and it wins: the live guard flash says strike to win (%s)" % Danger.guard_flash(dzw1))

	var sh = _bare_shell()
	# fit gate: the worst context line (the two longest enemy names, +9) and the
	# five guard flashes (plus the two winning ones) and the NEXT TURN choke
	# line, at the context line's own size in its own box
	var names: Array = []
	for k in Content.ENEMIES:
		names.append(String(Content.ENEMIES[k]["name"]))
	names.sort_custom(func(a, b): return a.length() > b.length())
	var worst_ctx := "! INCOMING 99 - LETHAL  ·  %s, %s +9" % [names[0], names[1]]
	var fit_lines: Array = [worst_ctx, "Smog chokes NEXT TURN - descend to escape it",
		"Smog chokes NEXT TURN - cleanse it all to thin it", "Smog chokes NEXT TURN - cleanses no longer thin it"]
	var esc_rows: Array = [{"move": true}, {"strike": true}, {"item": [0]}, {"descend": true}, {},
			{"win": "strike"}, {"win": "strike", "strike_dirs": 2}, {"win": "item"}]
	# the named-target flash, once per boss row (the longest name is the worst)
	for bk in Content.ENEMIES:
		if Content.ENEMIES[bk]["traits"].has("boss"):
			esc_rows.append({"win": "strike", "strike_dirs": 2, "win_kind": bk})
	for esc in esc_rows:
		fit_lines.append(Danger.guard_flash({"fc": {"dmg": 99}, "escapes": esc}))
	var worst_fit := 1.0
	var worst_what := ""
	var lay_ok := true
	var lay_bad := ""
	var three := Danger.sky_chips({"choke_in": 60, "spawn_in": 12, "spawn_open": 1, "dim_in": 9})
	for vp in CARD_VIEWPORTS:
		var vw: float = vp.x
		var vh: float = vp.y
		for s in fit_lines:
			var f := float(sh._fit_size(String(s), int(vh * 0.022), vw * 0.95)) / vh
			if f < worst_fit:
				worst_fit = f
				worst_what = "%s at %dx%d" % [s, vw, vh]
		# layout gate: chips 60/12/9 (the widest the clock makes)
		var y2: float = sh._safe_top(vh) + vh * 0.036 * 1.35
		var mh := vh * 0.024
		var lay: Dictionary = sh._sky_row_layout(vw, vh, y2 + mh + vh * 0.0155, three)
		var ok: bool = lay["chips"].size() == 3 and float(lay["end_x"]) <= vw * 0.55 \
			and float(lay["cfg_x0"]) + 1.0 <= vw * 0.975 - vw * 0.2
		for c in lay["chips"]:
			ok = ok and float(c["nsz"]) / vh >= CARD_MIN_VH and Rect2(c["icon_rect"]).position.y >= y2 + mh
		if not ok and lay_bad == "":
			lay_bad = "%dx%d: %s" % [vw, vh, str(lay)]
		lay_ok = lay_ok and ok
	_check(worst_fit >= CARD_MIN_VH, "danger lines draw at >= %.2f%% of vh (worst %.3f%%: %s)" % [
		CARD_MIN_VH * 100.0, worst_fit * 100.0, worst_what])
	_check(lay_ok, "the SKIES chips fit their row at every viewport: %s" % lay_bad)

	# the danger cue reaches the banner queue at danger priority, and its tick
	# rides the step's sound cap: boss > warn > hurt
	var g = Game.new(4242)
	g.enemies.clear()
	g.terrain.clear()
	g.smog = int(g.floor_def(1)["smog_choke"]) - 2
	sh.game = g
	sh._danger_rev += 1
	_check(int(sh._danger_state()["sky"]["choke_in"]) == 2, "fixture: the choke is two end turns off")
	sh._banner = ["something else"]
	sh._banner_ms = Time.get_ticks_msec()
	sh._banner_q = []
	sh._act({"type": "end_turn"})
	var queued := false
	for qb in sh._banner_q:
		queued = queued or (qb["lines"] == ["THE SMOG THICKENS", "it chokes from next turn"]
			and int(qb["prio"]) == int(Feedback.BANNER_PRIO["danger"]) and qb["col"] == Danger.COL_AMBER)
	_check(queued, "choke 1: THE SMOG THICKENS waits in the banner queue at danger priority (%s)" % str(sh._banner_q))
	_check(sh._choke_cued == 1, "the shell remembers the choke countdown it announced (%d)" % sh._choke_cued)
	# a cleanse relief, then the end turns that bring it back to 1: no second
	# banner and no second tick (Danger.cues' hysteresis, through _act)
	var spy := SfxSpy.new()
	var real_audio = sh.audio
	sh.audio = spy
	var ot := Vector2i.ZERO
	for od in _open_dirs(g):
		ot = g.player["pos"] + od
		break
	g.terrain[ot] = {"kind": "oil"}
	# a second slick far off, so the cleanse does not restore the floor (which
	# clears the skies outright and would test nothing)
	var far_room: Rect2i = g.map["rooms"][g.map["rooms"].size() - 1]
	g.terrain[far_room.get_center()] = {"kind": "oil"}
	g.player["charge"] = 3
	sh._banner_q = []
	sh._act({"type": "cleanse", "target": ot})
	var c_after := int(sh._danger_state()["sky"]["choke_in"])
	_check(c_after > 1, "fixture: the cleanse pushed the choke back (%d)" % c_after)
	var guard_n := 0
	while int(sh._danger_state()["sky"]["choke_in"]) > 1 and guard_n < 6:
		sh._act({"type": "end_turn"})
		guard_n += 1
	_check(int(sh._danger_state()["sky"]["choke_in"]) == 1, "fixture: the end turns bring the choke back to 1")
	var refired := false
	for qb in sh._banner_q:
		refired = refired or qb["lines"] == ["THE SMOG THICKENS", "it chokes from next turn"]
	refired = refired or sh._banner == ["THE SMOG THICKENS", "it chokes from next turn"]
	_check(not refired and not spy.played.has("warn"),
		"a cleanse relief and the end turn after it re-fire neither the banner nor the tick (%s / %s)" % [str(sh._banner_q), str(spy.played)])
	sh.audio = real_audio
	spy.free()
	sh._reset_danger()
	_check(sh._choke_cued == Danger.NO_CUE, "a new or restored game forgets the announced countdown")
	var ids: Array = sh._play_events([{"t": "damage", "who": "player", "amt": 1, "src": "drill_bot"},
		{"t": "boss_phase", "phase": 2}], ["warn"]).map(func(p): return String(p["id"]))
	_check(ids == ["boss", "warn", "hurt"], "the warn tick ranks boss > warn > hurt: %s" % str(ids))
	sh.free()
	print("danger readouts: worst line %.3f%% of vh" % [worst_fit * 100.0])


func _check_lethal_guard() -> void:
	const Danger := preload("res://shell/danger.gd")
	# a dry D-pad press into a lethal strike is refused once, with the reason
	var fx := _lethal_fixture(99, 0)
	var g = fx[0]
	var sh = _danger_shell(g)
	var pp: Vector2i = g.player["pos"]
	var t0: int = g.total_turns
	sh._dir_input(fx[1])
	_check(g.total_turns == t0 and g.player["pos"] == pp and not g.over,
		"dry D-pad into a lethal strike: refused, nothing moved")
	_check(sh.flash.begins_with("LETHAL (99)") and sh._flash_red and not sh._guard.is_empty(),
		"...the flash says why, in red (%s)" % sh.flash)
	var cm: Dictionary = sh._context_msg(g.snapshot())
	_check(cm["text"] == sh.flash and cm["col"] == Shell.COL_RED, "...and the context line draws it red")
	sh._dir_input(fx[1])
	_check(g.over and g.total_turns == t0, "a second press inside the window ends the turn (and the strike lands)")
	sh.free()
	fx = _lethal_fixture(99, 0)
	g = fx[0]
	sh = _danger_shell(g)
	t0 = g.total_turns
	sh._dir_input(fx[1])
	sh._guard["ms"] = int(sh._guard["ms"]) - Danger.GUARD_MS - 1
	sh._dir_input(fx[1])
	_check(not g.over and g.total_turns == t0 and not sh._guard.is_empty(), "a press after the window asks again")
	sh.free()
	for how in ["tap", "space", "enter"]:
		fx = _lethal_fixture(99, 0)
		g = fx[0]
		sh = _danger_shell(g)
		match how:
			"tap": sh._tap("end_turn")
			"space": sh._key(KEY_SPACE)
			"enter": sh._key(KEY_ENTER)
		_check(g.over, "END TURN is never guarded (%s)" % how)
		sh.free()
	fx = _lethal_fixture(1, 0)
	g = fx[0]
	sh = _danger_shell(g)
	pp = g.player["pos"]
	t0 = g.total_turns
	sh._dir_input(fx[1])
	_check(g.total_turns == t0 + 1 and g.player["pos"] == pp + fx[1] and not g.over,
		"not lethal: the dry press ends the turn and steps, as before")
	sh.free()
	# a balm fruit that saves: the flash points at it, it glows, and once eaten
	# the press goes through
	fx = _lethal_fixture(3, 0)
	g = fx[0]
	g.player["hp"] = 2
	g.player["items"] = ["balm_fruit"]
	sh = _danger_shell(g)
	t0 = g.total_turns
	sh._dir_input(fx[1])
	_check(sh.flash.contains("glowing item") and sh._danger_state()["escapes"]["item"] == [0],
		"dry, lethal, a balm fruit saves: the flash points at it (%s)" % sh.flash)
	sh._tap("item:0")
	sh._dir_input(fx[1])
	_check(not g.over and g.total_turns == t0 + 1, "after the fruit the strike is no longer lethal: the press goes through")
	sh.free()
	# an action between the two presses re-arms the guard (still lethal)
	fx = _lethal_fixture(99, 0)
	g = fx[0]
	g.player["items"] = ["iron_seed"]
	sh = _danger_shell(g)
	t0 = g.total_turns
	sh._dir_input(fx[1])
	sh._tap("item:0")
	sh._dir_input(fx[1])
	_check(not g.over and g.total_turns == t0, "an action between the presses re-arms the guard")
	sh.free()
	# a tap on your own tile with charge left: refused, step off offered
	fx = _lethal_fixture(99, 3)
	g = fx[0]
	sh = _danger_shell(g)
	pp = g.player["pos"]
	sh.hotspots = []
	sh._click(Vector2(sh._mox + (pp.x + 0.5) * sh._ts, sh._moy + (pp.y + 0.5) * sh._ts))
	_check(not g.over and sh.flash.contains("step off"), "tap on yourself with charge: refused, step off offered (%s)" % sh.flash)
	sh._click(Vector2(sh._mox + (pp.x + 0.5) * sh._ts, sh._moy + (pp.y + 0.5) * sh._ts))
	_check(g.over, "...and the second tap ends the turn")
	sh.free()
	# the boss at 1 HP and a minion both adjacent, the minion's strike leaving
	# the tender to die: a tap on your own tile is refused and the flash names
	# the boss - never the bare "strike to win" that lets the player pick the
	# minion (the residual; mutation: count strike_dirs after the forecast
	# filter and this flash reads "strike to win")
	var bm := _boss_minion_fixture()
	g = bm[0]
	g.player["charge"] = 3
	sh = _danger_shell(g)
	pp = g.player["pos"]
	t0 = g.total_turns
	sh.hotspots = []
	sh._click(Vector2(sh._mox + (pp.x + 0.5) * sh._ts, sh._moy + (pp.y + 0.5) * sh._ts))
	_check(not g.over and g.total_turns == t0
		and sh.flash.contains("strike %s to win" % Names.the_name(String(bm[1]["kind"])))
		and not sh.flash.contains("strike to win"),
		"boss + minion adjacent: the guard names the boss to strike (%s)" % sh.flash)
	sh.free()
	# a dry cleanse that would auto-end the turn
	fx = _lethal_fixture(99, 0)
	g = fx[0]
	g.terrain[g.player["pos"] + fx[1]] = {"kind": "oil"}
	sh = _danger_shell(g)
	sh.mode = "cleanse"
	t0 = g.total_turns
	sh._cleanse_at(g.player["pos"] + fx[1])
	_check(not g.over and g.total_turns == t0 and sh.flash.begins_with("LETHAL"), "dry cleanse into a lethal strike: refused")
	_check(sh.mode == "cleanse" and String(sh._context_msg(g.snapshot())["text"]).begins_with("LETHAL"),
		"...and the refusal shows on the context line while still aiming the cleanse (%s)" % sh._context_msg(g.snapshot())["text"])
	sh.free()
	# the tutorial never guards; the context line leads with the forecast
	fx = _lethal_fixture(99, 0)
	g = fx[0]
	sh = _danger_shell(g)
	_check(String(sh._context_msg(g.snapshot())["text"]).begins_with("! INCOMING 99 - LETHAL"),
		"the context line leads with the lethal forecast: %s" % sh._context_msg(g.snapshot())["text"])
	sh.screen = "tutorial"
	_check(sh._guard_lets_end(), "the tutorial never guards")
	_check(sh._context_msg(g.snapshot())["text"] == "", "...and draws no danger line")
	sh.free()
	print("lethal guard: refuse once, confirm within %d ms, END never asked" % Danger.GUARD_MS)


func _check_intent_badges() -> void:
	const Danger := preload("res://shell/danger.gd")
	const TestContent := preload("res://tests/test_content.gd")
	for t in TestContent.INTENT_TYPES:
		_check(Danger.BADGE.has(t) or Danger.NO_BADGE.has(t), "intent %s has a badge decision" % t)
	for t in Danger.BADGE:
		_check(TestContent.INTENT_TYPES.has(t), "badge row %s is a real intent type" % t)
	var legend := {}
	for row in Shell.LEGEND:
		legend[String(row[0])] = true
	var icons: Array = []
	for t in Danger.BADGE:
		icons.append(String(Danger.BADGE[t]["icon"]))
	for t in Danger.BLOCK_ICON:
		icons.append(String(Danger.BLOCK_ICON[t]))
	for ic in icons + ["ic_choke", "ic_dim"]:
		_check(Art.ART.has(ic), "badge icon %s has art" % ic)
		_check(legend.has(ic), "badge icon %s has a LEGEND row" % ic)
	for sname in Content.STATUSES:
		if not Content.STATUSES[sname].get("blocks", []).is_empty():
			_check(Danger.BLOCK_ICON.has(sname), "blocking status %s has a glyph" % sname)
	var hp_sh = _iso_shell()
	_check(hp_sh._help_pages() == 4, "the legend is four pages with the badge rows")
	hp_sh.free()

	# live state: a strike and a smokestack
	var fx := _lethal_fixture(2, 3)
	var g = fx[0]
	var pp: Vector2i = g.player["pos"]
	var st: Vector2i = pp + fx[1] * 3 if g._open(pp + fx[1] * 3) else pp + fx[1] * 2
	var stack: Dictionary = g._spawn("smokestack", st)
	stack["intent"] = {"type": "stoke", "in": 2}
	var bs: Array = Danger.badges(g.snapshot(), g.telegraph())
	_check(bs.size() == 2 and bs[0]["icon"] == "in_attack" and bs[0]["text"] == "2" and bs[0]["live"]
		and bs[1]["icon"] == "in_stoke" and bs[1]["text"] == "2", "badges: strike 2 (live), stoke in 2 (%s)" % str(bs))
	# the stoker tooltip line keys on the ROW's stokes trait, not the intent
	# standing this turn, and with two stokers alive it words the total as shared
	var tip_sh = _danger_shell(g)
	var g_smog: int = g.smog
	g.smog = int(g.floor_def(int(g.floor_num))["smog_choke"]) - 4
	tip_sh._danger_rev += 1
	var dzt: Dictionary = tip_sh._danger_state()
	var cc := int(dzt["sky"]["choke_in"])
	var calm := int(dzt["sky_calm"]["choke_in"])
	_check(cc > 0 and calm > cc, "fixture: the smokestack pulls the choke in (%d vs calm %d)" % [cc, calm])
	var want_tip := "brings the choke %d turns sooner" % (calm - cc)
	_check(tip_sh._danger_tip(stack, dzt).has(want_tip), "a stoking smokestack's tooltip: %s" % str(tip_sh._danger_tip(stack, dzt)))
	var idle_stack: Dictionary = stack.duplicate(true)
	idle_stack["intent"] = {"type": "idle"}
	_check(tip_sh._danger_tip(idle_stack, dzt).has(want_tip),
		"...and on its idle turn it still names the pull (the row, not the intent)")
	var st2 := Vector2i(-1, -1)
	for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if g._open(st + dd) and st + dd != pp:
			st2 = st + dd
			break
	var stack2: Dictionary = g._spawn("smokestack", st2)
	stack2["intent"] = {"type": "stoke", "in": 2}
	tip_sh._danger_rev += 1
	var dz2: Dictionary = tip_sh._danger_state()
	var c2 := int(dz2["sky"]["choke_in"])
	var calm2 := int(dz2["sky_calm"]["choke_in"])
	var tip2: Array = tip_sh._danger_tip(stack, dz2)
	_check(calm2 > c2 and tip2.has("stokers bring the choke %d turns sooner" % (calm2 - c2))
		and not tip2.any(func(l): return String(l).begins_with("brings")),
		"two stokers: the total is worded as shared (%s)" % str(tip2))
	# the calm walk finds NO choke inside its horizon while the stokers bring
	# one: the line still shows, naming the horizon (mutation: restore the
	# `calm > c` condition alone and neither line appears)
	var choke_v := int(g.floor_def(int(g.floor_num))["smog_choke"])
	var far_ok := false
	for gap in range(Danger.SKY_HORIZON + 1, Danger.SKY_HORIZON * 3):
		g.smog = choke_v - gap
		tip_sh._danger_rev += 1
		var dzf: Dictionary = tip_sh._danger_state()
		var cf := int(dzf["sky"]["choke_in"])
		if cf > 0 and int(dzf["sky_calm"]["choke_in"]) < 0:
			far_ok = true
			var want2 := "stokers bring the choke in %d turns - none for %d+ without them" % [cf, Danger.SKY_HORIZON]
			_check(tip_sh._danger_tip(stack, dzf).has(want2),
				"two stokers, no calm choke: %s (want %s)" % [str(tip_sh._danger_tip(stack, dzf)), want2])
			g.enemies.erase(stack2)
			tip_sh._danger_rev += 1
			var dz1: Dictionary = tip_sh._danger_state()
			var c1 := int(dz1["sky"]["choke_in"])
			if c1 > 0 and int(dz1["sky_calm"]["choke_in"]) < 0:
				var want1 := "brings the choke in %d turns - none for %d+ without it" % [c1, Danger.SKY_HORIZON]
				_check(tip_sh._danger_tip(stack, dz1).has(want1),
					"one stoker, no calm choke: %s (want %s)" % [str(tip_sh._danger_tip(stack, dz1)), want1])
			g.enemies.append(stack2)
			break
	_check(far_ok, "fixture: a smog level where only the stokers bring the choke inside the horizon")
	# both forms fit the tooltip's own wrap (<= 2 lines, nothing shrunk under
	# CARD_MIN_VH) at every viewport, with the widest numbers
	var tip_fit_bad := 0
	for vp in CARD_VIEWPORTS:
		for ln in [tip_sh._stoker_line(59, -1, 2), tip_sh._stoker_line(59, -1, 1), tip_sh._stoker_line(9, 59, 2)]:
			var wr: Dictionary = tip_sh._wrap(String(ln), int(vp.y * 0.021), vp.x * 0.86, 2)
			if wr["lines"].size() > 2 or float(wr["size"]) / vp.y < CARD_MIN_VH:
				tip_fit_bad += 1
	_check(tip_fit_bad == 0, "the stoker lines fit the tooltip at every viewport (%d bad)" % tip_fit_bad)
	g.enemies.erase(stack2)
	g.smog = g_smog
	tip_sh.free()
	g.enemies[0]["status"] = {"stun": 1}
	var tele: Dictionary = g.telegraph()
	bs = Danger.badges(g.snapshot(), tele)
	_check(bs[0]["icon"] == "in_stunned" and bs[0]["text"] == "" and not bs[0]["live"], "a stunned attacker wears the stun glyph")
	_check(Danger.tile_numbers(tele, pp).is_empty(), "...and paints no number")
	var sh = _danger_shell(g)
	_check(sh._threat_tiles(g.snapshot()).is_empty(), "...and no red tile: the shell reads the sim's telegraph")
	sh.free()
	g.enemies[0]["status"] = {}
	_check(Danger.tile_numbers(g.telegraph(), pp).is_empty() and g.telegraph()["tiles"].get(pp, 0) == 2,
		"the tender's own tile carries no number (the INCOMING line speaks for it)")

	# a grapple: tether to the landing tile, ringless when anchored
	g = Game.new(4242)
	g.enemies.clear()
	g.terrain.clear()
	pp = g.player["pos"]
	var dl := Vector2i.ZERO
	for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if g._open(pp + dd) and g._open(pp + dd * 2) and g._open(pp + dd * 3):
			dl = dd
			break
	_check(dl != Vector2i.ZERO, "fixture: three open tiles in a line")
	var crane: Dictionary = g._spawn("magnet_crane", pp + dl * 3)
	crane["intent"] = {"type": "drag"}
	var th: Array = Danger.tethers(g.telegraph(), pp)
	_check(th.size() == 1 and th[0]["land"] == pp + dl and th[0]["live"] and th[0]["to"] == pp,
		"tether: crane to tender, landing one tile closer (%s)" % str(th))
	g.player["anchor_turns"] = 1
	th = Danger.tethers(g.telegraph(), pp)
	bs = Danger.badges(g.snapshot(), g.telegraph())
	_check(th[0]["land"] == null and not th[0]["live"] and bs[0]["icon"] == "in_anchored",
		"anchored: the tether goes dead and ringless, and the badge wears the anchor (%s)" % str(th))
	g.player["anchor_turns"] = 0
	crane["intent"] = {"type": "drag", "times": 2}
	bs = Danger.badges(g.snapshot(), g.telegraph())
	_check(bs[0]["icon"] == "in_drag" and bs[0]["text"] == "2", "a double drag shows its 2")
	crane["intent"] = {"type": "drag"}
	_check(Danger.badges(g.snapshot(), g.telegraph())[0]["text"] == "", "a single drag shows no number")

	# vents count down on the map from 5; urgent at 1; a sealed vent says so
	g = Game.new(4242)
	g.enemies.clear()
	g.terrain.clear()
	g.smog = 0
	var sky: Dictionary = g.smog_forecast()
	g.smog = int(sky["spawn_in"]) - 3
	sky = g.smog_forecast()
	var vm: Array = Danger.vent_marks(g.snapshot(), sky)
	_check(int(sky["spawn_in"]) == 3 and vm.size() == g.map["vents"].size() and vm[0]["text"] == "3"
		and not vm[0]["urgent"], "vent marks at 3: the number, not urgent (%s)" % str(vm))
	g.smog += 2
	g.terrain[g.map["vents"][0]] = {"kind": "growth"}
	sky = g.smog_forecast()
	vm = Danger.vent_marks(g.snapshot(), sky)
	_check(vm[0]["sealed"] and not vm[0]["urgent"] and (vm.size() == 1 or vm[1]["urgent"]),
		"vent marks at 1: open vents urgent, the sealed one flagged (%s)" % str(vm))
	# a COVERED vent (Roots, a machine, the tender on it) releases nothing while
	# covered: no urgent ring, flagged covered - the grate agrees with the SKIES
	# chip, whose spawn_open counts exactly the urgent marks (mutation: read
	# only the growth seal in vent_marks, as before, and these go red)
	var v0: Vector2i = g.map["vents"][0]
	var cover_cases := {"roots": func(): g.terrain[v0] = {"kind": "roots", "ttl": 9},
		"machine": func(): g._spawn("drill_bot", v0),
		"tender": func(): g.player["pos"] = v0}
	var ppos0: Vector2i = g.player["pos"]
	for cname in cover_cases:
		g.terrain.clear()
		g.enemies.clear()
		g.player["pos"] = ppos0
		cover_cases[cname].call()
		sky = g.smog_forecast()
		vm = Danger.vent_marks(g.snapshot(), sky)
		var n_urgent := 0
		for mk in vm:
			if bool(mk["urgent"]):
				n_urgent += 1
		_check(int(sky["spawn_in"]) == 1 and Danger.vent_state(g.snapshot(), v0) == "covered"
			and bool(vm[0].get("covered", false)) and not vm[0]["urgent"] and not vm[0]["sealed"]
			and n_urgent == int(sky["spawn_open"]),
			"vent marks at 1: a vent covered by %s is flagged covered, never urgent, and the urgent marks are the chip's %d open vents (%s)" % [
				cname, int(sky["spawn_open"]), str(vm)])
	g.terrain.clear()
	g.enemies.clear()
	g.player["pos"] = ppos0
	g.smog = 0
	_check(Danger.vent_marks(g.snapshot(), g.smog_forecast()).is_empty(), "no vent marks beyond 5 turns")

	# a tar shot outlines the slot it will gum; smoke beside you screens it
	g = Game.new(4242)
	g.enemies.clear()
	g.terrain.clear()
	pp = g.player["pos"]
	var sp := Vector2i(-1, -1)
	for y in int(g.map["h"]):
		for x in int(g.map["w"]):
			var p := Vector2i(x, y)
			if sp == Vector2i(-1, -1) and g._open(p) and absi(p.x - pp.x) + absi(p.y - pp.y) == 2:
				sp = p
	var spit: Dictionary = g._spawn("tar_spitter", sp)
	spit["intent"] = {"type": "gum", "slot": 1}
	_check(Danger.gum_slots(g.snapshot(), g.telegraph()) == [1], "a live tar shot outlines slot 1")
	for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if g._open(pp + dd):
			g.terrain[pp + dd] = {"kind": "smoke", "ttl": 3}
			break
	_check(Danger.gum_slots(g.snapshot(), g.telegraph()).is_empty()
		and Danger.badges(g.snapshot(), g.telegraph())[0]["icon"] == "in_screened",
		"smoke beside you screens it: no outline, the smoke glyph")
	print("intent badges: %d intents, %d badge rows, %d block glyphs" % [TestContent.INTENT_TYPES.size(),
		Danger.BADGE.size(), Danger.BLOCK_ICON.size()])


## A stand-in for the audio node: records every sound id the shell plays.
class SfxSpy extends Node:
	var played: Array = []

	func play(id: String, _pitch := 1.0) -> void:
		played.append(id)


## --- NEW badges on the menu --------------------------------------------------
## An unlock the player has not looked at yet badges its menu row NEW until
## they cycle onto it; a loadout still waiting on its package earns no badge
## (nothing to cycle onto); the LOADOUT row names a win with the selected kit.
func _check_new_badges() -> void:
	var nb = _bare_shell()
	nb.screen = "menu"
	nb.profile = Profile.new()
	nb.profile.unlocked_loadouts = ["tidewarden"]
	nb.profile.unseen = ["tidewarden"]
	nb.sel_loadout = "tender"
	DirAccess.remove_absolute(TEST_PROFILE)
	_check(_badge_of(nb, "set:loadout") == "NEW", "an unseen loadout badges the LOADOUT row NEW (%s)" % _badge_of(nb, "set:loadout"))
	nb._tap("set:loadout")
	_check(nb.sel_loadout == "tidewarden" and _badge_of(nb, "set:loadout") == "",
		"cycling onto it clears the badge (%s)" % _badge_of(nb, "set:loadout"))
	_check(nb.profile.unseen.is_empty() and FileAccess.file_exists(TEST_PROFILE),
		"...and the profile is saved to profile_path")
	# a gated loadout: unlocked and unseen, but its package is not
	nb.profile.unlocked_loadouts = ["tidewarden", "skyrunner"]
	nb.profile.unseen = ["skyrunner"]
	_check(_badge_of(nb, "set:loadout") != "NEW", "a Skyrunner waiting on Aeolian earns no badge")
	nb.profile.unlocked_packages = ["aeolian"]
	_check(_badge_of(nb, "set:loadout") == "NEW", "...until Aeolian opens it")
	nb.profile.unseen = []
	# wins with the selected loadout
	nb.sel_loadout = "tidewarden"
	nb.profile.records["loadouts"]["tidewarden"] = Profile._loadout_rec(7, 900, 0, 3, 1)
	_check(_badge_of(nb, "set:loadout") == "WON", "a loadout won at the base run reads WON (%s)" % _badge_of(nb, "set:loadout"))
	nb.profile.records["loadouts"]["tidewarden"] = Profile._loadout_rec(7, 900, 2, 3, 2)
	_check(_badge_of(nb, "set:loadout") == "WON D2", "...and at a difficulty, WON D2 (%s)" % _badge_of(nb, "set:loadout"))
	# the other cyclers: package, mutator and difficulty
	nb.profile.unlocked_mutators = ["brittle"]
	nb.profile.unlocked_tier = 2
	nb.profile.unseen = ["brittle", "aeolian", "tier:2"]
	_check(_badge_of(nb, "set:mutator") == "NEW" and _badge_of(nb, "set:package") == "NEW"
		and _badge_of(nb, "set:tier") == "NEW", "unseen package, mutator and difficulty badge their rows")
	nb.sel_tier = 0
	nb._tap("set:tier")  # onto difficulty 1: tier 2 is still unseen
	_check(_badge_of(nb, "set:tier") == "NEW", "difficulty 1 does not clear a NEW difficulty 2")
	nb._tap("set:tier")
	nb._tap("set:package")
	nb._tap("set:mutator")
	_check(_badge_of(nb, "set:tier") == "" and _badge_of(nb, "set:package") == ""
		and _badge_of(nb, "set:mutator") == "" and nb.profile.unseen.is_empty(),
		"cycling onto each clears its badge (%s)" % str(nb.profile.unseen))
	nb.free()


## The legacy notice ("the daily now has its own button") is said ONCE: it
## used to come back on every boot, because only a settings change dropped the
## old seed_mode key. A settings change must still carry the key forward while
## it routes something, or a resumed header-less daily would file to the career.
func _check_legacy_notice() -> void:
	var ln = _bare_shell()
	ln.profile = Profile.new()
	ln.screen = "menu"
	ln.mode = "normal"
	var cf := ConfigFile.new()
	cf.set_value("ui", "seed_mode", "daily")
	cf.save(TEST_CFG)
	ln._load_settings()
	_check(ln._legacy_notice and ln._legacy_seed_mode == "daily", "an old daily cfg raises the notice")
	ln.mode = "settings"
	ln._tap("set:hold")
	ln.mode = "normal"
	var c1 := ConfigFile.new()
	c1.load(TEST_CFG)
	_check(str(c1.get_value("ui", "seed_mode", "")) == "daily",
		"a settings change carries the legacy key forward while it still routes a save")
	ln._load_settings()
	_check(ln._legacy_notice, "...and does not dismiss the notice")
	ln._tap("daily")
	ln._load_settings()
	_check(not ln._legacy_notice and ln._legacy_seed_mode == "daily",
		"opening DAILY dismisses the notice for good, keeping the routing")
	ln.mode = "normal"
	ln._load_settings()
	ln._legacy_notice = true  # a boot that never opened DAILY: PLAY dismisses it too
	ln._start_run("career", 5151)
	if ln._run_save != null:
		ln._run_save.close()
		ln._run_save = null
	ln._load_settings()
	var c2 := ConfigFile.new()
	c2.load(TEST_CFG)
	_check(not ln._legacy_notice and ln._legacy_seed_mode == "random" and not c2.has_section_key("ui", "seed_mode"),
		"starting a run drops the legacy key: the notice never comes back")
	ln.free()
	DirAccess.remove_absolute(TEST_RUN_SAVE)
	DirAccess.remove_absolute(TEST_CFG)


## R and N mid-tutorial: R restarts the tutorial (as a tutorial death's R
## does) and N does nothing. Both used to leave it for a run on the LAST run's
## kind and seed - a daily try counted and the live run's save overwritten.
func _check_tutorial_keys() -> void:
	var tk = _bare_shell()
	tk.profile = Profile.new()
	tk.run_kind = "daily"
	tk.seed_v = 777
	tk._tap("tutorial")
	tk.mode = "normal"
	tk._key(KEY_N)
	_check(tk.screen == "tutorial" and tk.run_kind == "daily" and tk.seed_v == 777 and tk.profile.daily_tries.is_empty(),
		"N mid-tutorial stays in the tutorial (%s, %s)" % [tk.screen, str(tk.profile.daily_tries)])
	tk.tut_step = 2
	tk._key(KEY_R)
	_check(tk.screen == "tutorial" and tk.tut_step == 0 and tk.seed_v == 777 and tk.profile.daily_tries.is_empty()
		and not FileAccess.file_exists(TEST_RUN_SAVE),
		"R mid-tutorial restarts the tutorial, no run started (%s, step %d)" % [tk.screen, tk.tut_step])
	if tk._run_save != null:
		tk._run_save.close()
		tk._run_save = null
	tk.free()
	DirAccess.remove_absolute(TEST_RUN_SAVE)


func _badge_of(sh, tag: String) -> String:
	for row in sh._menu_rows():
		if String(row[1]) == tag:
			return String(row[3])
	return "<no row>"


## --- the menu stays readable on every phone ----------------------------------
## With the most a career can put on it - RESUME, a named difficulty, a badge
## on every cycler, the longest names - every label is at least 1.5% of the
## screen height and every row lands inside the viewport, at every shape the
## card gate sweeps. The labels used to sit in a 0.62vw block, where a long
## difficulty name with a badge fell to ~1.06%.
func _check_menu_layout() -> void:
	var ml = _bare_shell()
	ml.screen = "menu"
	ml.profile = Profile.new()
	ml.profile.unlocked_tier = Content.TIERS.size()
	ml.profile.unlocked_packages = Content.PACKAGES.keys()
	ml.profile.unlocked_mutators = Content.MUTATORS.keys()
	ml.profile.unlocked_loadouts = Content.LOADOUTS.keys().filter(func(l): return l != "tender")
	var nfid: String = Content.FEATS.keys()[0]
	ml.profile.feats[nfid] = Profile._feat_rec("2026-01-01", 1)
	ml.profile.unseen = ["tier:%d" % Content.TIERS.size(), "spinning_shrine", "hydraulics", "skyrunner",
		"feat:" + nfid]
	# the longest name each cycler can show
	var longest := func(ids: Array, name_of: Callable) -> String:
		var best := ""
		for id in ids:
			if String(name_of.call(id)).length() > String(name_of.call(best)).length() or best == "":
				best = id
		return best
	ml.sel_tier = 0
	var tn := 0
	for i in Content.TIERS.size():
		if String(Content.TIERS[i]["name"]).length() > String(Content.TIERS[tn]["name"]).length():
			tn = i
	ml.sel_tier = tn + 1
	ml.sel_mutator = longest.call(Content.MUTATORS.keys(), func(id): return Content.MUTATORS.get(id, {}).get("name", ""))
	ml.sel_package = longest.call(Content.PACKAGES.keys(), func(id): return Profile.unlock_name(id) if id != "" else "")
	ml.sel_loadout = "skyrunner"
	# a live run on the shell makes RESUME show
	ml.game = Game.new(4242, {})
	ml._game_is_run = true
	var tags: Array = []
	for row in ml._menu_rows():
		tags.append(String(row[1]))
	_check(tags.has("resume") and tags.has("set:tier") and tags.has("daily"),
		"the maxed menu shows RESUME, DIFFICULTY and DAILY (%s)" % str(tags))
	_check(_badge_of(ml, "career") == "NEW", "an unseen feat badges CAREER NEW (%s)" % _badge_of(ml, "career"))
	var small := 0
	var outside := 0
	var worst := 9.9
	var worst_at := ""
	var badges := 0
	var small_badge := 0
	for vp in CARD_VIEWPORTS:
		var vw: float = vp.x
		var vh: float = vp.y
		var view := Rect2(0, 0, vw, vh)
		for m in ml._menu_layout(vw, vh):
			var frac: float = float(m["size"]) / vh
			if frac < 0.015:
				small += 1
			if frac < worst:
				worst = frac
				worst_at = "%s at %dx%d" % [m["label"], int(vw), int(vh)]
			if not view.encloses(m["rect"]):
				outside += 1
			if String(m["badge"]) != "":
				badges += 1
				var lw: float = ml.font.get_string_size(String(m["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(m["size"])).x
				var cx: float = (m["rect"].position.x + m["rect"].end.x - float(m["badge_w"])) / 2.0
				var bw: float = ml.font.get_string_size(String(m["badge"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(m["badge_size"])).x
				if cx + lw / 2.0 > m["rect"].end.x - bw - m["rect"].size.y * 0.12:
					outside += 1
				if float(m["badge_size"]) / vh < CARD_MIN_VH:
					small_badge += 1
	_check(small == 0, "%d menu label(s) below 1.5%% of the screen height (worst %s)" % [small, worst_at])
	_check(outside == 0, "%d menu row(s) leave the viewport or run into their badge" % outside)
	_check(badges >= 5 * CARD_VIEWPORTS.size(), "the maxed menu carries its badges (%d)" % badges)
	_check(small_badge == 0, "%d menu badge(s) below %.2f%% of vh" % [small_badge, CARD_MIN_VH * 100.0])
	# BOTH armed PLAY labels name the loss and still draw at >= 1.5% vh inside
	# the viewport at every shape: TODAY'S over a live try on today's daily
	# seed, the date-free form over any other daily try (yesterday's, or a
	# legacy save routed as a daily)
	ml._play_armed = true
	var armed_bad := 0
	var armed_seen := 0
	var kind_was: String = ml.run_kind
	var seed_was: int = ml.seed_v
	var today_seed: int = int(ml._daily_now()["seed"])
	for want in [[today_seed, Shell.PLAY_ARMED_LABEL], [today_seed + 1, Shell.PLAY_ARMED_OLD_LABEL]]:
		ml.run_kind = "daily"
		ml.seed_v = int(want[0])
		for vp in CARD_VIEWPORTS:
			var view := Rect2(0, 0, vp.x, vp.y)
			for m in ml._menu_layout(vp.x, vp.y):
				if String(m["tag"]) != "play":
					continue
				armed_seen += 1
				if String(m["label"]) != String(want[1]) or float(m["size"]) / vp.y < 0.015 \
						or not view.encloses(m["rect"]) \
						or ml.font.get_string_size(String(m["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(m["size"])).x > m["rect"].size.x:
					armed_bad += 1
	ml.run_kind = kind_was
	ml.seed_v = seed_was
	ml._play_armed = false
	_check(armed_seen == 2 * CARD_VIEWPORTS.size() and armed_bad == 0,
		"both armed PLAY labels fit their row at every viewport (%d bad of %d)" % [armed_bad, armed_seen])
	print("menu layout: %d viewports, worst label %.4f%% of vh (%s)" % [CARD_VIEWPORTS.size(), worst * 100.0, worst_at])
	ml.game = null
	ml.free()


## --- the DAILY sheet fits ----------------------------------------------------
## Its lines stay readable, its cards stay inside the panel and its button row
## goes through _sheet_button_y, for every state the sheet can be in (no try,
## tries without a finish, finished with a streak) and every phone shape.
func _check_daily_layout() -> void:
	var dl = _bare_shell()
	dl.screen = "menu"
	dl.profile = Profile.new()
	var today: int = dl._daily_seed()
	var states: Array = []
	states.append(dl._daily_sheet(today))
	dl.profile.note_daily_try(today)
	dl.profile.note_daily_try(today)
	states.append(dl._daily_sheet(today))
	dl.profile.record_daily({"won": false, "floor": 4, "turns": 120, "seed": today})
	dl.profile.record_daily({"won": true, "floor": 7, "turns": 133, "seed": today})
	dl._refresh_daily_info()
	var fin: Dictionary = dl._daily_sheet(today)
	states.append(fin)
	# a live career run: the red abandon note, armed and unarmed
	dl._start_run("career")
	dl.screen = "menu"
	dl._tap("daily")
	var warn: Dictionary = dl._daily_sheet(today)
	_check(bool(warn["note_warn"]), "a live career run warns on the daily sheet")
	states.append(warn)
	dl._tap("daily_play")
	var armed: Dictionary = dl._daily_sheet(today)
	_check(String(armed["play"]) == "TAP AGAIN TO ABANDON", "...and arms on the first tap (%s)" % armed["play"])
	states.append(armed)
	if dl._run_save != null:
		dl._run_save.close()
		dl._run_save = null
	_check(String(fin["result"]) == "ranked: floor 4  ·  best: won in 133 turns  ·  2 tries",
		"a finished daily reads ranked then best (%s)" % fin["result"])
	_check(String(fin["play"]).contains("unranked") and String(fin["streak"]).begins_with("streak 1 day"),
		"...offers an unranked replay and starts a streak (%s / %s)" % [fin["play"], fin["streak"]])
	# the fullest daily the frozen lists can deal: three cards
	for sd in range(1, 400):
		var dcf: Dictionary = Profile.daily_config(sd)
		if String(dcf["package"]) != "" and String(dcf["mutator"]) != "":
			states.append(dl._daily_sheet(sd))
			break
	var bad := 0
	var worst := 9.9
	var worst_at := ""
	for vp in CARD_VIEWPORTS:
		var vw: float = vp.x
		var vh: float = vp.y
		for info in states:
			var L: Dictionary = dl._daily_layout(vw, vh, info)
			for ln in L["lines"]:
				var f: float = float(ln["size"]) / vh
				if f < worst:
					worst = f
					worst_at = "'%s' at %dx%d" % [ln["text"], int(vw), int(vh)]
				if f < CARD_MIN_VH:
					bad += 1
			var last_card := 0.0
			for c in L["cards"]:
				last_card = maxf(last_card, c["rect"].end.y)
			for b in L["buttons"]:
				var br: Rect2 = b["rect"]
				if br.end.y > vh * 0.955 + 0.01 or br.position.y < last_card \
						or float(b["size"]) / vh < CARD_MIN_VH:
					bad += 1
	_check(bad == 0, "%d daily sheet piece(s) too small, overlapping or past vh*0.955 (worst line %s)" % [bad, worst_at])
	print("daily sheet: %d states x %d viewports, worst line %.4f%% of vh (%s)" % [
		states.size(), CARD_VIEWPORTS.size(), worst * 100.0, worst_at])
	dl.free()



# --- the end of a run (stage 6) ---------------------------------------------------

const RUNEND_RUNS := "user://test_shell_runend_runs"


## The tender at 1 HP one smog tick short of the choke, nothing else on the
## floor: the next end turn kills it by smog.
func _smog_doom(g) -> void:
	g.terrain.clear()
	g.enemies.clear()
	g.smog = int(g.floor_def(int(g.floor_num))["smog_choke"]) - 1
	g.player["hp"] = 1
	g.player["shield"] = 0


func _clear_runend_runs() -> void:
	for n in _dir_files(RUNEND_RUNS):
		DirAccess.remove_absolute(RUNEND_RUNS + "/" + n)
	DirAccess.remove_absolute(RUNEND_RUNS)


## The beat and the lock: a death through _act holds the map up with the end
## banner and ignores every tap and key but Back/ESC/MENU until OVER_LOCK_MS;
## then only the sheet's own buttons start a run (no tap-anywhere).
func _check_run_end() -> void:
	const RunEnd := preload("res://shell/run_end.gd")
	var sh = _bare_shell()
	sh.runs_dir = RUNEND_RUNS
	sh.profile = Profile.new()
	sh.seed_v = 4242
	sh.run_kind = "career"
	sh.game = Game.new(4242, {})
	sh._game_is_run = true
	sh._run_recorded = false
	_smog_doom(sh.game)
	sh._push_banner(["A BANNER"], Shell.COL_GOLD, 10)
	sh._act({"type": "end_turn"})
	_check(sh.game.over and not sh.game.won and sh.game.death_cause == "smog", "the smog recipe kills the tender")
	_check(sh._over_ms >= 0 and sh._over_phase() == "beat" and sh._over_locked(),
		"a death through _act starts the beat, locked (%s)" % sh._over_phase())
	_check(String(sh._over_info.get("banner", [""])[0]) == "THE SMOG TAKES YOU",
		"the beat's banner names the smog (%s)" % str(sh._over_info.get("banner", [])))
	_check(sh._banner.is_empty() and sh._banner_q.is_empty(), "the end beat clears every other banner")
	_check(sh.profile.runs == 1 and sh._run_recorded, "the run was recorded at the end, beat or no beat")
	var bursts := 0
	for f in sh._fx:
		if String(f["kind"]) == "burst" and Color(f["col"]) == Shell.COL_RED:
			bursts += 1
	_check(bursts == 3, "three red bursts on a death (%d)" % bursts)
	var at: int = sh._over_ms
	_check(sh._over_phase(at + Shell.OVER_BEAT_MS) == "fade" and sh._over_phase(at + Shell.OVER_BEAT_MS
		+ Shell.OVER_FADE_MS) == "sheet" and sh._over_locked(at + Shell.OVER_LOCK_MS - 1)
		and not sh._over_locked(at + Shell.OVER_LOCK_MS), "beat -> fade -> sheet, unlocked at OVER_LOCK_MS")
	var g0 = sh.game
	var seed0: int = sh.seed_v
	# a LIVE hotspot under every click, and a MENU one - the one tag _tap lets
	# through the lock - so it is _click's own lock that holds (mutation: drop
	# `if _over_locked(): return` from _click and these clicks reach the menu)
	sh.hotspots = [{"rect": Rect2(0, 0, 9999, 9999), "tag": "menu"}]
	for pt in [Vector2(5, 5), Vector2(270, 600), Vector2(270, 1100), Vector2(500, 1150)]:
		sh._click(pt)
	_check(sh.screen == "game" and sh.game == g0, "a click on a live hotspot during the beat does nothing")
	sh.hotspots = [{"rect": Rect2(0, 0, 9999, 9999), "tag": "new_run"}]
	for pt in [Vector2(5, 5), Vector2(500, 1150)]:
		sh._click(pt)
	sh.hotspots.clear()
	sh._key(KEY_R)
	sh._key(KEY_N)
	sh._key(KEY_SPACE)
	sh._tap("new_run")
	sh._tap("retry_seed")
	sh._tap("tutorial")
	_check(sh.game == g0 and sh.seed_v == seed0 and sh.screen == "game",
		"taps, keys and buttons during the beat start nothing")
	sh._key(KEY_ESCAPE)
	_check(sh.screen == "menu", "ESC during the beat goes straight to the menu (the run is recorded)")
	sh.screen = "game"
	sh._over_ms -= Shell.OVER_LOCK_MS + 10
	_check(sh._over_phase() == "sheet" and not sh._over_locked(), "after the lock the sheet is up and live")
	sh.hotspots.clear()
	sh._click(Vector2(5, 5))
	_check(sh.game == g0, "a tap off the buttons starts nothing: there is no tap-anywhere")
	sh._tap("retry_seed")
	_check(sh.game != g0 and sh.seed_v == seed0 and not sh.game.over and sh._over_ms == -1
		and sh.stats.kills == 0 and sh._over_info.is_empty() and sh._run_summary.is_empty(),
		"RETRY SEED: the same seed, a fresh game, no beat, a fresh fold and no stale record")
	sh.mode = "normal"
	_smog_doom(sh.game)
	sh._act({"type": "end_turn"})
	_check(sh.game.over and sh._over_locked(), "a second death starts a second beat")
	sh._over_ms -= Shell.OVER_LOCK_MS + 10
	var g1 = sh.game
	sh._tap("new_run")
	_check(sh.game != g1 and not sh.game.over and sh.run_kind == "career", "NEW RUN starts a fresh career run")
	_check(sh.profile.runs == 2, "both deaths were recorded once each (%d)" % sh.profile.runs)
	# a drill bot's strike: the cause and the banner name it in words
	var g = Game.new(4242, {})
	g.terrain.clear()
	g.enemies.clear()
	g.smog = 0
	var dirs := _open_dirs(g)
	var bot: Dictionary = g._spawn("drill_bot", g.player["pos"] + dirs[0])
	bot["intent"] = {"type": "attack", "tile": g.player["pos"], "dmg": 99}
	sh.game = g
	sh._game_is_run = false
	sh.mode = "normal"
	sh._act({"type": "end_turn"})
	var info: Dictionary = sh._over_info
	_check(g.over and String(info.get("cause", "")).contains("Drill Bot") and not String(info.get("cause", "")).contains("drill_bot"),
		"the cause names the Drill Bot in words (%s)" % info.get("cause", ""))
	_check(String(info["banner"][0]) == "THE DRILL BOT TAKES YOU", "...and so does the banner (%s)" % str(info["banner"]))
	_check(not String(info.get("cause", "")).contains("cause:"), "no raw 'cause:' line is left")
	# "1 more HP would have saved you" only when it would have: the sim stops a
	# step at the first lethal blow, so a death at exactly 0 HP can hide a
	# second attacker still due on it. One drill bot hitting 2 at 2 HP: 3 HP
	# lives. Two: 3 HP still dies to the second (mutation: make _one_hp_saves
	# return true, or drop near_miss's one_hp_saves conjunct, and the two-bot
	# sheet lies; make it return false and the one-bot sheet goes quiet)
	for nb in [1, 2]:
		var ge = _exact_fixture(nb)
		sh.game = ge
		sh._game_is_run = false
		sh.mode = "normal"
		sh._act({"type": "end_turn"})
		var near := String(sh._over_info.get("near", ""))
		var want := "1 more HP would have saved you" if nb == 1 else ""
		_check(ge.over and not ge.won and int(ge.player["hp"]) == 0 and ge.death_cause == "drill_bot" and near == want,
			"%d drill bot(s) at exactly 0 HP: the near-miss line is '%s' (got '%s', hp %d)" % [
				nb, want, near, int(ge.player["hp"])])
	if sh._run_save != null:
		sh._run_save.close()
		sh._run_save = null
	sh.free()
	_clear_runend_runs()
	DirAccess.remove_absolute(TEST_RUN_SAVE)
	# the words, pinned
	_check(RunEnd.unlock_label("skyrunner", []) == "UNLOCKED  ·  Skyrunner loadout (needs Aeolian)",
		"a gated loadout says what it needs (%s)" % RunEnd.unlock_label("skyrunner", []))
	_check(RunEnd.unlock_label("skyrunner", ["aeolian"]) == "UNLOCKED  ·  Skyrunner loadout"
		and RunEnd.unlock_label("double_oil", []) == "UNLOCKED  ·  Slick Combine mutator"
		and RunEnd.unlock_label("mycology", []) == "UNLOCKED  ·  Mycology package"
		and RunEnd.unlock_label("tier:1", []) == "NEW DIFFICULTY  ·  " + String(Content.TIERS[0]["name"]),
		"unlock lines name the kind and the content's own name")
	var ul: Array = RunEnd.unlock_lines(["tier:1", "hydraulics", "kit_of_3", "double_oil", "skyrunner"], [])
	_check(ul.size() == 4 and String(ul[3]) == "+2 more  ·  tap for all",
		"three unlock lines, then +2 more and the pager's cue (%s)" % str(ul))
	# a summary whose folded killer is empty (a game set over from outside:
	# RunStats always carries killer.cause, "" without a player_death) falls
	# back to death_cause (mutation: restore killer.get("cause", fallback))
	var bare_s := {"won": false, "floor": 2, "killer": {"cause": "", "kind": ""}, "death_cause": "drill_bot"}
	_check(String(RunEnd.end_banner(bare_s, {})[0]) == "THE DRILL BOT TAKES YOU"
		and RunEnd.cause_line(bare_s, {}).begins_with("struck down by a Drill Bot"),
		"an empty folded killer falls back to death_cause (%s / %s)" % [
			str(RunEnd.end_banner(bare_s, {})), RunEnd.cause_line(bare_s, {})])
	_check(RunEnd.cause_text("spikes", "welded_hulk") == "cut on a Welded Hulk's spikes"
		and RunEnd.cause_text("smog") == "choked by the smog" and RunEnd.cause_text("fire") == "burned in the flames",
		"cause words (%s)" % RunEnd.cause_text("spikes", "welded_hulk"))
	_check(RunEnd.near_miss_text({"kind": "stairs", "steps": 1}) == "the stairs were 1 step away"
		and RunEnd.near_miss_text({"kind": "quota", "short": 2}) == "2 cleanses short of waking the stairs"
		and RunEnd.near_miss_text({"kind": "exact"}) == "1 more HP would have saved you"
		and RunEnd.near_miss_text({"kind": ""}) == "", "near-miss words")
	_check(RunEnd.score_parts_text({"parts": [["floor", 500], ["win", 0], ["kills", 40]], "tier": 2, "quarters": 6})
		== "floor 500  ·  kills 40  ·  x1.5 difficulty 2", "score parts skip zeros and show the multiplier")
	_check(RunEnd.chip_text({"id": "record", "key": "kills", "v": 41, "was": 30}) == "record  ·  most machines felled 41 (was 30)",
		"the record chip (%s)" % RunEnd.chip_text({"id": "record", "key": "kills", "v": 41, "was": 30}))
	var goal := {"desc": "Land 30 Grow Spikes", "ids": ["wide_draft"], "names": ["Wide Draft"], "have": 17, "need": 30, "delta": 9}
	_check(RunEnd.next_goal_text(goal) == "NEXT  ·  Land 30 Grow Spikes  ·  17/30 (+9 this run)  ·  unlocks Wide Draft",
		"the NEXT line (%s)" % RunEnd.next_goal_text(goal))
	var goal1 := {"desc": "Shut down the Furnace", "ids": ["hydraulics", "kit_of_3", "double_oil"],
		"names": ["Hydraulics", "Kit of Three", "Slick Combine"], "have": 0, "need": 1, "delta": 0}
	_check(RunEnd.next_goal_text(goal1) == "NEXT  ·  Shut down the Furnace  ·  unlocks Hydraulics, Kit of Three and 1 more",
		"a one-off goal shows no 0/1 (%s)" % RunEnd.next_goal_text(goal1))
	_check(RunEnd.best_line({"score": 900}, {"daily": {"won": false, "floor": 3, "turns": 50}}, true,
			{"ranked": false, "new_best": false, "tries": 3})[0] == "today's best: floor 3  ·  3 tries"
		and RunEnd.best_line({"score": 900}, {"daily": {}}, true, {"ranked": true})[0] == "RANKED  ·  your first finish today"
		and RunEnd.best_line({"score": 900}, {"best_score": 0, "runs": 0}, false)[0] == "your first score  ·  beat it next run"
		and RunEnd.best_line({"score": 450}, {"best_score": 900, "runs": 4}, false)[0] == "best 900  ·  this run 50%",
		"the best line's daily and career arms")


## What the sheet says, against a real record: total turns, NEW BEST and
## DEEPEST YET read from the bests BEFORE the record, the daily's buttons,
## a first win's unlocks and NEXT, and a tutorial death.
func _check_over_facts() -> void:
	const RunEnd := preload("res://shell/run_end.gd")
	var sh = _bare_shell()
	sh.runs_dir = RUNEND_RUNS
	sh.profile = Profile.new()
	var g = Game.new(4242, {})
	g.total_turns = 63
	g.turn = 20
	g.over = true
	sh.game = g
	var info: Dictionary = sh._over_info_now()
	_check(String(info["stats"]).contains("63 turns") and not String(info["stats"]).contains("turn 20"),
		"the stats line counts the run's turns, not the floor's (%s)" % info["stats"])
	_check(String(info["seed"]).begins_with("seed 4242") and info["unlocks"].is_empty() and String(info["next"]) == ""
		and String(info["best"][0]) == "", "an unrecorded game shows no best, unlocks or goal")
	_check(info["buttons"] == [["NEW RUN", "new_run"], ["RETRY SEED", "retry_seed"], ["MENU", "menu"]],
		"a career sheet's buttons (%s)" % str(info["buttons"]))
	# NEW BEST and DEEPEST YET, while the profile has already moved
	var p = Profile.new()
	p.runs = 5
	p.best_floor = 3
	p.records["score_v"] = Content.RUN_SCORE_VERSION
	p.records["best"]["score"] = Profile._rec(450, 5, "tender", 0)
	sh.profile = p
	g = Game.new(4242, {})
	g.floor_num = 5
	g.over = true
	sh.game = g
	sh.run_kind = "career"
	sh._game_is_run = true
	sh._run_recorded = false
	sh._record_finished_run()
	info = sh._over_info_now()
	_check(String(info["best"][0]).begins_with("NEW BEST") and bool(info["best"][1]),
		"a score over the old best reads NEW BEST (%s)" % str(info["best"]))
	var score_rec := false
	for r in sh._run_report.get("records", []):
		score_rec = score_rec or String(r.get("key", "")) == "score"
	var score_chip := false
	for c in info["chips"]:
		score_chip = score_chip or String(c).contains("best score")
	_check(score_rec and not score_chip,
		"the score record is the NEW BEST line, never also a chip (%s)" % str(info["chips"]))
	_check(String(info["floor_best"]) == "DEEPEST YET  ·  floor 5 (was 3)" and p.best_floor == 5,
		"DEEPEST YET names the old best while the profile already holds the new one (%s)" % info["floor_best"])
	# a first win: its unlocks, YOUR FIRST WIN and the next goal
	sh.profile = Profile.new()
	g = Game.new(4242, {})
	g.floor_num = 7
	g.won = true
	g.over = true
	sh.game = g
	sh._run_recorded = false
	sh._record_finished_run()
	info = sh._over_info_now()
	_check(String(info["title"]) == "THE FURNACE IS COLD" and String(info["floor_best"]) == "YOUR FIRST WIN",
		"a first win (%s / %s)" % [info["title"], info["floor_best"]])
	_check(not info["unlocks"].is_empty() and String(info["unlocks"][0]) == "NEW DIFFICULTY  ·  " + String(Content.TIERS[0]["name"]),
		"its unlocks, the difficulty first (%s)" % str(info["unlocks"]))
	_check(String(info["next"]).begins_with("NEXT  ·  "), "...and the next goal (%s)" % info["next"])
	_check(String(info["banner"][0]) == "THE FURNACE FALLS", "the win's beat banner")
	# the feats the run earned ride behind the unlocks: counted in the overflow
	# (mutation: drop the feat loop in _build_over_info and the count shrinks)
	var n_ann: int = sh._run_unlocks.size() + (sh._run_report.get("feats", []) as Array).size()
	_check((sh._run_report.get("feats", []) as Array).has("barefoot") and int(info.get("unlock_n", 0)) == n_ann
		and String(info["unlocks"].back()) == RunEnd.unlock_more(n_ann - 3),
		"a first win's feats count in the unlock rows (%d: %s)" % [n_ann, str(info["unlocks"])])
	# a maxed career: every milestone and difficulty owned, so the feats ARE
	# the unlock rows and the NEXT line falls back to a feat
	var mx = Profile.new()
	for m in Content.MILESTONES:
		var bk = mx._bucket(String(m["kind"]))
		if bk != null and not bk.has(String(m["id"])):
			bk.append(String(m["id"]))
	mx.unlocked_tier = Content.TIERS.size()
	sh.profile = mx
	g = Game.new(4242, {})
	g.floor_num = 7
	g.won = true
	g.over = true
	sh.game = g
	sh._run_recorded = false
	sh._record_finished_run()
	info = sh._over_info_now()
	var mfeats: Array = sh._run_report.get("feats", [])
	_check(sh._run_unlocks.is_empty() and not mfeats.is_empty()
		and String(info["unlocks"][0]) == "FEAT  ·  " + String(Content.FEATS[mfeats[0]]["name"])
		and info["unlocks"].has("FEAT  ·  Barefoot"),
		"a maxed career's new feats are its unlock rows (%s)" % str(info["unlocks"]))
	_check(String(info["next"]).contains("  ·  feat "), "...and its NEXT names a feat (%s)" % info["next"])
	# a daily: the three-button row, no unlocks, no goal
	sh.run_kind = "daily"
	g = Game.new(77, {})
	g.over = true
	sh.game = g
	sh.seed_v = 77
	sh._run_recorded = false
	sh._record_finished_run()
	info = sh._over_info_now()
	_check(info["buttons"] == [["NEW RUN", "new_run"], ["RETRY DAILY", "retry_seed"], ["MENU", "menu"]],
		"a daily's buttons are NEW RUN / RETRY DAILY / MENU (%s)" % str(info["buttons"]))
	_check(info["unlocks"].is_empty() and String(info["next"]) == "" and String(info["seed"]).ends_with("daily"),
		"a daily shows no unlock rows and no goal (%s)" % str(info["unlocks"]))
	_check(String(info["best"][0]) == "RANKED  ·  your first finish today", "a first daily finish is ranked (%s)" % str(info["best"]))
	# a tutorial death THROUGH _act: the tutorial branch starts its own beat
	# and builds its sheet (mutation: drop _begin_over / _build_over_info from
	# _act's tutorial branch and neither the beat nor TUTORIAL AGAIN is there)
	var runs_t: int = sh.profile.runs
	sh._start_tutorial()
	sh._act({"type": "move", "dir": Vector2i(1, 0)})
	sh._act({"type": "move", "dir": Vector2i(1, 0)})
	_check(sh.tut_step == 2, "fixture: the tutorial's end-turn step (%d)" % sh.tut_step)
	var tg = sh.game
	var tdirs := _open_dirs(tg)
	var tbot: Dictionary = tg._spawn("drill_bot", tg.player["pos"] + tdirs[0])
	tbot["intent"] = {"type": "attack", "tile": tg.player["pos"], "dmg": 99}
	sh._act({"type": "end_turn"})
	_check(tg.over and not tg.won and sh._over_phase() == "beat" and sh._over_locked(),
		"a tutorial death through _act starts the beat (%s)" % sh._over_phase())
	_check(sh._over_info.get("buttons", []) == [["TUTORIAL AGAIN", "tutorial"], ["MENU", "menu"]]
		and String(sh._over_info["banner"][0]) == "THE DRILL BOT TAKES YOU" and sh.profile.runs == runs_t,
		"...its sheet offers TUTORIAL AGAIN, names the killer and records nothing (%s)" % str(sh._over_info.get("buttons", [])))
	# a tutorial death set from outside: TUTORIAL AGAIN, and nothing scored
	sh._start_tutorial()
	sh.game.over = true
	info = sh._over_info_now()
	_check(info["buttons"] == [["TUTORIAL AGAIN", "tutorial"], ["MENU", "menu"]] and String(info["score"]) == ""
		and String(info["seed"]) == "", "a tutorial death offers TUTORIAL AGAIN and scores nothing (%s)" % str(info["buttons"]))
	sh._over_ms = -1
	sh._tap("tutorial")
	_check(sh.screen == "tutorial" and not sh.game.over and sh._over_info.is_empty(), "TUTORIAL AGAIN restarts it")
	if sh._run_save != null:
		sh._run_save.close()
		sh._run_save = null
	sh.free()
	_clear_runend_runs()


## The longest sheet the content can produce and a typical one, at every
## CARD_VIEWPORTS shape: every row at >= CARD_MIN_VH and <= 2 lines, the
## buttons legible, inside the gesture strip and apart, nothing with prio <= 13
## dropped in the worst case and nothing dropped at all in the typical one;
## and the beat's first line legible for every cause the banner can name.
func _check_over_text() -> void:
	const RunEnd := preload("res://shell/run_end.gd")
	var sh = _bare_shell()
	var worst_s := {"won": false, "floor": 6, "turns": 400, "kills": 160, "bloom_earned": 120, "tier": 8,
		"killer": {"cause": "spikes", "kind": "welded_hulk"}, "death_cause": "spikes", "score": 99999}
	var gn: Array = Content.GRAFTS.keys()
	gn.sort_custom(func(a, b): return String(Content.GRAFTS[a]["name"]).length() > String(Content.GRAFTS[b]["name"]).length())
	worst_s["grafts"] = gn.slice(0, 6)
	var chips: Array = []
	for rs in Profile.RECORD_SHOW:
		chips.append(RunEnd.chip_text({"id": "record", "key": String(rs[0]), "v": 9999, "was": 9998}))
	for rid in Content.RESONANCES:
		chips.append(RunEnd.chip_text({"id": "resonance", "rid": rid, "floor": 7}))
	for aid in Content.ABILITIES:
		chips.append(RunEnd.chip_text({"id": "big_hit", "n": 99, "src": "collision:" + String(aid)}))
		chips.append(RunEnd.chip_text({"id": "big_hit", "n": 99, "src": "fire:" + String(aid)}))
	var fnt: Font = sh.font
	chips.sort_custom(func(a, b):
		return fnt.get_string_size(a, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x > fnt.get_string_size(b, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x)
	var lname := ""
	var longest_lid := "tender"
	for lid in Content.LOADOUTS:
		if String(Content.LOADOUTS[lid]["name"]).length() > lname.length():
			lname = String(Content.LOADOUTS[lid]["name"])
			longest_lid = String(lid)
	var mname := ""
	for mid in Content.MUTATORS:
		if String(Content.MUTATORS[mid]["name"]).length() > mname.length():
			mname = String(Content.MUTATORS[mid]["name"])
	var tier_ids: Array = []
	var longest_tier := 1
	for ti in Content.TIERS.size():
		if String(Content.TIERS[ti]["name"]).length() > String(Content.TIERS[longest_tier - 1]["name"]).length():
			longest_tier = ti + 1
	tier_ids.append("tier:%d" % longest_tier)
	var long_desc := ""
	for m in Content.MILESTONES:
		if String(m.get("desc", "")).length() > long_desc.length():
			long_desc = String(m["desc"])
	var parts: Array = []
	for row in Content.RUN_SCORE:
		parts.append([String(row["id"]), 9999])
	var worst := {
		"won": false, "title": "YOU DIED", "cause": RunEnd.cause_line(worst_s, {}),
		"near": RunEnd.near_miss_text({"kind": "best_short", "best": 7}),
		"stats": RunEnd.stats_line(worst_s),
		"kit": [{"icon": "ab_default", "count": 999, "up": true}, {"icon": "ab_default", "count": 999, "up": true},
			{"icon": "ab_default", "count": 999, "up": true}, {"icon": "ab_default", "count": 999, "up": true},
			{"icon": "ab_default", "count": 999, "up": true}],
		"grafts": RunEnd.grafts_line(worst_s), "chips": chips.slice(0, 3),
		"score": RunEnd.score_title({"total": 99999}),
		"score_parts": RunEnd.score_parts_text({"parts": parts, "tier": 8, "quarters": 12}),
		"best": RunEnd.best_line({"score": 99999}, {"best_score": 999999, "best_score_loadout": 9999,
			"loadout": longest_lid, "runs": 9}, false),
		"floor_best": "DEEPEST YET  ·  floor 6 (was 5)",
		"unlocks": RunEnd.unlock_lines(tier_ids + ["skyrunner", "double_oil", "mycology", "overtime"], []),
		"next": RunEnd.next_goal_text({"desc": long_desc, "ids": ["a", "b", "c"], "names": ["Slick Combine",
			"Kit of Three", "Hydraulics"], "have": 999, "need": 1000, "delta": 99}),
		"seed": RunEnd.seed_line(999999, worst_s, true, "%s · %s · %s" % [lname, "Hydraulics", mname]),
		"buttons": [["NEW RUN", "new_run"], ["RETRY DAILY", "retry_seed"], ["MENU", "menu"]],
	}
	var typical := {
		"won": false, "title": "YOU DIED", "cause": "struck down by a Drill Bot  ·  Pipeworks",
		"near": "2 cleanses short of waking the stairs",
		"stats": "floor 5 of 7  ·  63 turns  ·  24 kills  ·  41 bloom earned",
		"kit": [{"icon": "ab_solar_lance", "count": 12, "up": true}, {"icon": "ab_seed_bomb", "count": 9, "up": false},
			{"icon": "ab_mycelium_dash", "count": 4, "up": false}, {"icon": "ab_vine_whip", "count": 7, "up": false}],
		"grafts": "grafts  Compost", "chips": ["biggest hit 5  ·  Noon Lance", "6 rooms bloomed", "4-turn kill streak"],
		"score": "SCORE 1234", "score_parts": "floor 500  ·  kills 120  ·  bloom 82  ·  combos 45  ·  rooms 60",
		"best": ["best 1449  ·  this run 85%", false], "floor_best": "",
		"unlocks": ["UNLOCKED  ·  Mycology package"],
		"next": "NEXT  ·  Shut down the Furnace  ·  unlocks Hydraulics, Kit of Three and 5 more",
		"seed": "seed 123456  ·  Tender", "buttons": [["NEW RUN", "new_run"], ["RETRY SEED", "retry_seed"], ["MENU", "menu"]],
	}
	# the "+n more" row counts what the sheet REALLY hides: on a short screen
	# the priority drop takes an unlock row, and the last kept one is rebuilt
	# with the new count (mutation: skip _over_fix_overflow in _over_layout and
	# the sheet shows a label, or a stale "+2 more", with three hidden)
	var long_line := "struck down by a Welded Hulk's spikes on the longest floor name there is  ·  Pipeworks deep"
	var u_ids := ["tier:1", "skyrunner", "double_oil", "mycology", "overtime"]
	var crowded := {"won": false, "title": "YOU DIED", "cause": long_line, "near": long_line, "stats": long_line,
		"grafts": long_line, "kit": [{"icon": "ab_default", "count": 999, "up": true}],
		"chips": ["a chip that is long", "another chip", "third"], "score": "SCORE 99999", "score_parts": long_line,
		"best": ["best 1449  ·  this run 85%", false], "floor_best": "DEEPEST YET  ·  floor 6 (was 5)",
		"unlocks": RunEnd.unlock_lines(u_ids, []), "unlock_n": u_ids.size(), "next": long_line, "seed": "seed 1",
		"buttons": [["NEW RUN", "new_run"], ["MENU", "menu"]]}
	var short_lay: Dictionary = sh._over_layout(crowded, 1080, 1250)
	var kept_u: Array = []
	for it in short_lay["items"]:
		if String(it["id"]).begins_with("unlock"):
			kept_u.append(String(it["lines"][0]))
	var u_dropped: bool = short_lay["dropped"].any(func(d): return String(d).begins_with("unlock"))
	_check(u_dropped and kept_u.size() >= 2 and kept_u.back() == RunEnd.unlock_more(u_ids.size() - (kept_u.size() - 1))
		and kept_u.slice(0, kept_u.size() - 1).all(func(l): return not String(l).begins_with("+")),
		"a dropped unlock row is counted in the rebuilt '+n more' (%s, dropped %s)" % [str(kept_u), str(short_lay["dropped"])])
	# a wrapped row keeps RunEnd's two-space pad around its separator, as the
	# one-line rows do (mutation: _over_text_fit wraps without keep_pad)
	var padded: Dictionary = crowded.duplicate()
	padded["stats"] = "floor 5 of 7  ·  263 turns  ·  124 kills  ·  141 bloom earned  ·  12 rooms bloomed  ·  3 floors restored"
	var pad_lay: Dictionary = sh._over_layout(padded, 1080, 2400)
	var pad_ok := false
	for it in pad_lay["items"]:
		if String(it["id"]) == "stats":
			pad_ok = String(" ".join(it["lines"])).contains("·")
			for ln in it["lines"]:
				var l := String(ln)
				pad_ok = pad_ok and l.replace("  ·  ", "").find("·") == -1 \
					and not l.begins_with("·") and not l.ends_with("·")
	var one_wrap: Dictionary = sh._wrap("floor 5 of 7  ·  63 turns  ·  24 kills", 40, 10000.0, 2, true)
	_check(pad_ok and one_wrap["lines"] == ["floor 5 of 7  ·  63 turns  ·  24 kills"]
		and sh._wrap("aaa  ·  bbb", 40, sh.font.get_string_size("aaa  ·", HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x, 2, true)["lines"] == ["aaa", "bbb"],
		"the over sheet's wrap keeps the '  ·  ' pad and never leaves a bare dot at a line end (%s)" % str(one_wrap["lines"]))
	var prio := {}
	for r in Shell.OVER_ROWS:
		prio[String(r[0])] = int(r[1])
	var small := 0
	var worst_frac := 1.0
	var worst_at := ""
	var bad_btn := 0
	var worst_drops: Array = []
	for vp in CARD_VIEWPORTS:
		var vw: float = vp.x
		var vh: float = vp.y
		for pair in [["worst", worst], ["typical", typical]]:
			var lay: Dictionary = sh._over_layout(pair[1], vw, vh)
			for it in lay["items"]:
				var sz := 0
				match String(it["kind"]):
					"text":
						sz = int(it["size"])
						if it["lines"].size() > 2:
							small += 1
							print("over row %s wraps to %d lines at %dx%d" % [it["id"], it["lines"].size(), vw, vh])
					"chip":
						sz = int(it["size"])
					"kit":
						sz = int(it["icons"][0]["count_size"])
				var f := float(sz) / vh
				if f < worst_frac:
					worst_frac = f
					worst_at = "%s %s %dx%d" % [pair[0], it["id"], vw, vh]
				if f < CARD_MIN_VH:
					small += 1
					print("over row %s at %.3f%% of vh at %dx%d: '%s'" % [it["id"], f * 100.0, vw, vh,
						str(it.get("text", it.get("lines", "")))])
			var rects: Array = []
			for b in lay["buttons"]:
				var br: Rect2 = b["rect"]
				if float(b["size"]) / vh < CARD_MIN_VH or br.end.y > vh * 0.955 + 0.01 or br.position.x < 0 or br.end.x > vw:
					bad_btn += 1
				for o in rects:
					if Rect2(o).intersects(br):
						bad_btn += 1
				rects.append(br)
			if float(lay["bottom"]) > float(lay["button_top"]) + 0.01:
				bad_btn += 1
			if pair[0] == "worst":
				for id in lay["dropped"]:
					if int(prio[String(id)]) <= 13:
						worst_drops.append("%s at %dx%d" % [id, vw, vh])
			else:
				_check(lay["dropped"].is_empty(), "a typical sheet drops nothing at %dx%d (%s)" % [vw, vh, str(lay["dropped"])])
	_check(small == 0, "%d over-sheet row(s) below %.2f%% of vh or over 2 lines (worst %.3f%%: %s)" % [
		small, CARD_MIN_VH * 100.0, worst_frac * 100.0, worst_at])
	_check(bad_btn == 0, "%d over-sheet button fault(s): small, in the gesture strip, overlapping or under the content" % bad_btn)
	_check(worst_drops.is_empty(), "the worst sheet keeps every row with prio <= 13 (%s)" % str(worst_drops))
	# the beat's first line, for every cause the banner can name
	var causes: Array = ["smog", "spikes", "fire", "goo", ""]
	causes.append_array(Content.ENEMIES.keys())
	causes.append_array(Content.GRAFTS.keys())
	causes.append_array(Content.RESONANCES.keys())
	var beat_small := 0
	var beat_worst := 1.0
	var beat_at := ""
	for vp in CARD_VIEWPORTS:
		var vw: float = vp.x
		var vh: float = vp.y
		for c in causes:
			var ban: Array = RunEnd.end_banner({"won": false, "floor": 6, "killer": {"cause": c, "kind": ""}}, {})
			var bl: Array = sh._over_beat_layout({"banner": ban, "won": false}, vw, vh, vh * 0.06, vh * Shell.Z_MAP_END)
			for k in 2:
				var f := float(bl[k]["size"]) / vh
				if f < beat_worst:
					beat_worst = f
					beat_at = "'%s' %dx%d" % [bl[k]["text"], vw, vh]
				if f < CARD_MIN_VH:
					beat_small += 1
	_check(beat_small == 0, "%d end-beat line(s) below %.2f%% of vh (worst %s)" % [beat_small, CARD_MIN_VH * 100.0, beat_at])
	print("over sheet: %d viewports, worst row %.3f%% of vh (%s), beat %.3f%% (%s)" % [
		CARD_VIEWPORTS.size(), worst_frac * 100.0, worst_at, beat_worst * 100.0, beat_at])
	sh.free()


# --- the CAREER sheet (stage 7) ---------------------------------------------------

## Three careers the CAREER sheet must read well for: fresh, mid-way (history
## hints, partial casts, a loadout owned but gated on its package, some feats
## earned and unseen, records) and maxed (everything owned and earned, the
## longest numbers a record can show).
func _career_profiles() -> Array:
	var fresh = Profile.new()
	var mid = Profile.new()
	mid.runs = 14
	mid.wins = 1
	mid.best_floor = 7
	mid.unlocked_tier = 1
	mid.casts_by_base = {"grow_spike": 41}
	for i in 14:
		# thirteen lance-free losses holding a Tangle Bomb (hints for no_lance
		# and upgrades_only) and one win that held the lance and Vine Whip
		var kit: Array = ["solar_lance", "vine_whip", "mycelium_dash"] if i == 3 \
			else ["vine_whip", "seed_bomb+tangle", "mycelium_dash"]
		mid.history.append(mid._compact({"won": i == 3, "floor": 6 if i != 3 else 7, "tier": 0, "turns": 120,
			"seed": i, "kit": kit, "grafts": [], "loadout": "tender"}))
	mid._claim()
	mid.unlocked_loadouts.append("skyrunner")  # owned, but Aeolian is not
	mid.feats = {"green_thumb": Profile._feat_rec("2026-01-02", 4), "two_for_one": Profile._feat_rec("2026-01-03", 6)}
	mid.unseen = ["feat:green_thumb"]
	mid.totals = {"kills": 180, "rooms_bloomed": 44}
	mid.bosses_beaten = ["overseer"]
	mid.cast_ever = ["vine_whip", "seed_bomb", "solar_lance"]
	mid.records["best"]["score"] = Profile._rec(2140, 9, "tender", 0)
	mid.records["best"]["rooms_bloomed"] = Profile._rec(4, 9, "tender", 0)
	mid.records["best"]["fastest_win"] = Profile._rec(131, 4, "tender", 0)
	mid.records["loadouts"]["tender"] = Profile._loadout_rec(7, 2140, 0, 14, 1)
	var mx = Profile.new()
	mx.runs = 9999
	mx.wins = 999
	mx.best_floor = 7
	mx.unlocked_tier = Content.TIERS.size()
	for m in Content.MILESTONES:
		mx._bucket(String(m["kind"])).append(String(m["id"]))
	for fid in Content.FEATS:
		mx.feats[fid] = Profile._feat_rec("2026-12-31", 9999)
	mx.unseen = ["feat:overcharged", "feat:six_ways_home"]
	for row in Profile.RECORD_SHOW:
		mx.records["best"][row[0]] = Profile._rec(99999, 9999, "flarekeeper", Content.TIERS.size())
	for lid in Content.LOADOUTS:
		mx.records["loadouts"][lid] = Profile._loadout_rec(7, 99999, Content.TIERS.size(), 9999, 999)
	return [fresh, mid, mx]


func _check_career_sheet() -> void:
	var cs = _bare_shell()
	cs.screen = "menu"
	cs.mode = "normal"
	cs.profile = Profile.new()
	DirAccess.remove_absolute(TEST_PROFILE)
	# the menu row: CAREER shares DAILY's line
	var groups := {}
	for row in cs._menu_rows():
		groups[String(row[1])] = String(row[4])
	_check(groups.has("career") and groups["career"] == groups.get("daily", "?") and groups["career"] != "",
		"the menu carries CAREER on DAILY's line (%s)" % str(groups))
	cs._tap("career")
	_check(cs.mode == "career" and cs.career_tab == "goals" and cs.career_page == 0,
		"CAREER opens on GOALS, page 0 (%s %s %d)" % [cs.mode, cs.career_tab, cs.career_page])
	var g0: Dictionary = cs._career_cards("goals", 0)
	_check(g0["cards"].size() == Shell.CARDS_PER_PAGE and String(g0["cards"][0][1]) == "Difficulty ladder"
		and String(g0["cards"][0][4]) == "0/%d" % Content.TIERS.size(),
		"GOALS: five cards a page, the difficulty ladder first (%s)" % str(g0["cards"][0]))
	_check(String(g0["cards"][0][2]) == "Shut down the Furnace to open difficulty 1",
		"a fresh ladder says how to open difficulty 1 (%s)" % g0["cards"][0][2])
	var n_ms: int = Content.MILESTONES.size()
	_check(int(g0["pages"]) == ceili((n_ms + 1) / 5.0), "GOALS pages: ladder + %d milestones -> %d (%d)" % [
		n_ms, ceili((n_ms + 1) / 5.0), int(g0["pages"])])
	_check(String(g0["cards"][1][1]) == "Tidewarden" and String(g0["cards"][1][4]) == "0/3",
		"the first goal is the closest milestone, named and counted (%s)" % str(g0["cards"][1]))
	for pg in int(g0["pages"]):
		for c in cs._career_cards("goals", pg)["cards"]:
			if String(c[1]).contains("_"):
				_check(false, "a raw id leaked onto a GOALS card: %s" % c[1])
	# paging clamps at both ends, by tap and by key
	cs._tap("career_page:-1")
	_check(cs.career_page == 0, "paging back from page 0 stays on page 0")
	for i in 9:
		cs._tap("career_page:+1")
	_check(cs.career_page == int(g0["pages"]) - 1, "paging forward stops on the last page (%d)" % cs.career_page)
	cs._key(KEY_LEFT)
	_check(cs.career_page == int(g0["pages"]) - 2, "LEFT pages back (%d)" % cs.career_page)
	cs._key(KEY_RIGHT)
	_check(cs.career_page == int(g0["pages"]) - 1, "RIGHT pages forward (%d)" % cs.career_page)
	_check(int(cs._career_cards("goals", 99)["page"]) == int(g0["pages"]) - 1, "a stale page is clamped")
	# tabs switch and reset the page; an unknown tab changes nothing
	cs._tap("career_tab:records")
	_check(cs.career_tab == "records" and cs.career_page == 0, "a tab switch resets the page")
	cs._tap("career_tab:bogus")
	_check(cs.career_tab == "records", "an unknown tab is ignored")
	var r0: Dictionary = cs._career_cards("records", 0)
	var n_rec: int = Profile.RECORD_SHOW.size() + Content.LOADOUTS.size() + 1
	_check(int(r0["pages"]) == ceili(n_rec / 5.0) and String(r0["cards"][0][4]) == "-"
		and String(r0["cards"][0][2]) == "no record yet", "RECORDS: %d cards, a fresh one reads no record yet" % n_rec)
	# FEATS: NEW for an unseen earned feat, EARNED for a seen one, progress
	# otherwise; opening the tab clears the badges and saves
	cs.profile.feats = {"green_thumb": Profile._feat_rec("2026-01-02", 3), "barefoot": Profile._feat_rec("2026-01-01", 1)}
	cs.profile.unseen = ["feat:green_thumb"]
	cs.profile.records["best"]["best_multi_kill"] = Profile._rec(1, 2, "tender", 0)
	_check(_badge_of(cs, "career") == "NEW", "an unseen feat badges the CAREER row NEW (%s)" % _badge_of(cs, "career"))
	var tl: Array = cs._career_layout(1080, 2400, cs._career_cards("goals", 0))["tabs"]
	_check(String(tl[1]["label"]) == "FEATS NEW", "...and the FEATS tab (%s)" % tl[1]["label"])
	cs._tap("career_tab:feats")
	var f0: Dictionary = cs._career_cards("feats", 0)
	var by_name := {}
	for pg in int(f0["pages"]):
		for c in cs._career_cards("feats", pg)["cards"]:
			by_name[String(c[1])] = c
	_check(by_name.size() == Content.FEATS.size() and int(f0["pages"]) == ceili(Content.FEATS.size() / 5.0),
		"FEATS: one card per feat (%d)" % by_name.size())
	_check(String(by_name["Green Thumb"][4]) == "NEW" and String(by_name["Green Thumb"][2]).ends_with("run 3"),
		"an earned feat opened fresh reads NEW and names its run (%s)" % str(by_name["Green Thumb"]))
	_check(String(by_name["Barefoot"][4]) == "EARNED", "a seen earned feat reads EARNED")
	_check(String(by_name["Two for One"][4]) == "1/2" and float(by_name["Two for One"][5]) == 0.5,
		"an unearned feat shows its progress off the career record (%s)" % str(by_name["Two for One"]))
	_check(String(by_name["Barefoot"][4]) == "EARNED" and String(by_name["Overcharged"][4]) == "",
		"a binary unearned feat has no count")
	_check(cs.profile.unseen_of("feat").is_empty() and FileAccess.file_exists(TEST_PROFILE),
		"opening FEATS clears the feat badges and saves to profile_path")
	_check(_badge_of(cs, "career") == "", "...so the CAREER row badge goes")
	cs._tap("close")
	cs._tap("career")
	cs._tap("career_tab:feats")
	var again: Array = cs._career_cards("feats", 0)["cards"]
	_check(String(again[0][4]) == "EARNED", "the next visit reads EARNED (%s)" % again[0][4])
	# a loadout owned but waiting on its package says so; records name their run
	var mid = _career_profiles()[1]
	cs.profile = mid
	var gated := ""
	for pg in int(cs._career_cards("goals", 0)["pages"]):
		for c in cs._career_cards("goals", pg)["cards"]:
			if String(c[1]).begins_with("Skyrunner"):
				gated = "%s | %s | %s" % [c[1], c[4], c[2]]
	_check(gated.begins_with("Skyrunner (needs Aeolian) | DONE") and gated.contains("needs Aeolian: Win at difficulty 1"),
		"an owned, gated loadout names its package (%s)" % gated)
	var hint := false
	for pg in int(cs._career_cards("goals", 0)["pages"]):
		for c in cs._career_cards("goals", pg)["cards"]:
			if String(c[2]).contains("without Solar Lance: best floor"):
				hint = String(c[4]) == ""
	_check(hint, "a binary goal carries its history hint and no count")
	var rec: Dictionary = {}
	for pg in int(cs._career_cards("records", 0)["pages"]):
		for c in cs._career_cards("records", pg)["cards"]:
			rec[String(c[1])] = c
	_check(String(rec["Best score"][4]) == "2140" and String(rec["Best score"][2]) == "run 9  ·  Tender  ·  base run",
		"a record names its value, run, loadout and difficulty (%s)" % str(rec["Best score"]))
	_check(String(rec["Fastest win"][2]).begins_with("turns  ·  run 4"), "the fastest win is in turns")
	_check(String(rec["Tender"][4]) == "WON" and String(rec["Tender"][2]).contains("1 win in 14 runs"),
		"a loadout card reads WON and its wins in runs (%s)" % str(rec["Tender"]))
	cs.profile = Profile.new()
	var fresh_rec: Dictionary = {}
	for pg in int(cs._career_cards("records", 0)["pages"]):
		for c in cs._career_cards("records", pg)["cards"]:
			fresh_rec[String(c[1])] = c
	_check(String(fresh_rec["Flarekeeper"][4]) == "LOCKED" and String(fresh_rec["Flarekeeper"][2]) == "Reach the Cracking Yard",
		"a locked loadout reads LOCKED with its milestone (%s)" % str(fresh_rec["Flarekeeper"]))
	_check(String(fresh_rec["Tender"][4]) == "" and String(fresh_rec["Tender"][2]) == "not played yet",
		"a loadout never played has no badge (%s)" % str(fresh_rec["Tender"]))
	_check(rec.has("Daily streak"), "the RECORDS tab ends on the daily streak")
	cs.free()


## The CAREER sheet's geometry at every phone shape, for every tab and page of
## every test career: head, tabs, card names and descriptions, and buttons at
## >= CARD_MIN_VH; cards below the tab row; each progress bar in the gap under
## its card; the last bar above the button row; the row through
## _sheet_button_y (bottom <= vh * 0.955) with no two buttons overlapping.
func _check_career_layout() -> void:
	var cl = _bare_shell()
	cl.screen = "menu"
	var bad := 0
	var first_bad := ""
	var n := 0
	for cp in _career_profiles():
		cl.profile = cp
		for tab in Shell.CAREER_TABS:
			for pg in int(cl._career_cards(tab, 0)["pages"]):
				var info: Dictionary = cl._career_cards(tab, pg)
				for vp in CARD_VIEWPORTS:
					var vw: float = vp.x
					var vh: float = vp.y
					var L: Dictionary = cl._career_layout(vw, vh, info)
					n += 1
					var why := ""
					if float(L["head"]["size"]) / vh < CARD_MIN_VH:
						why = "head %dpx" % int(L["head"]["size"])
					var tab_end := 0.0
					for t in L["tabs"]:
						tab_end = maxf(tab_end, t["rect"].end.y)
						if float(t["size"]) / vh < CARD_MIN_VH:
							why = "tab %s %dpx" % [t["label"], int(t["size"])]
					var last_end := 0.0
					for i in L["cards"].size():
						var r: Rect2 = L["cards"][i]["rect"]
						if r.position.y < tab_end:
							why = "card under the tabs"
						last_end = maxf(last_end, r.end.y)
					for b in L["bars"]:
						last_end = maxf(last_end, b["track"].end.y)
					var btop := 99999.0
					for i in L["buttons"].size():
						var br: Rect2 = L["buttons"][i]["rect"]
						btop = minf(btop, br.position.y)
						if br.end.y > vh * 0.955 + 0.01:
							why = "button past vh*0.955"
						if float(L["buttons"][i]["size"]) / vh < CARD_MIN_VH:
							why = "button %s %dpx" % [L["buttons"][i]["label"], int(L["buttons"][i]["size"])]
						for j in range(i + 1, L["buttons"].size()):
							if br.intersects(L["buttons"][j]["rect"]):
								why = "buttons overlap"
					if last_end >= btop:
						why = "the last card or bar (%.1f) reaches the button row (%.1f)" % [last_end, btop]
					if why != "":
						bad += 1
						if first_bad == "":
							first_bad = "%s p%d at %dx%d: %s" % [tab, pg, int(vw), int(vh), why]
	_check(bad == 0, "%d CAREER layout(s) broken (first: %s)" % [bad, first_bad])
	# the page count rides in BACK, never a line of its own
	cl.profile = Profile.new()
	var L2: Dictionary = cl._career_layout(1080, 2400, cl._career_cards("goals", 1))
	var labels: Array = []
	for b in L2["buttons"]:
		labels.append(String(b["label"]))
	_check(labels == ["<", "BACK  ·  2/4", ">"], "page 2 of 4: [<] [BACK  ·  2/4] [>] (%s)" % str(labels))
	print("career sheet layout: %d tab-page x viewport layouts checked" % n)
	cl.free()


# --- the unlock pager, the in-run pings and the objective line (stage 8) -----------

## A first win files many unlocks: the over sheet shows three and "+n more ·
## tap for all", the unlock rows are the tap target, and the pager lists every
## unlock and feat as a card - tier first, real names, the gated loadout saying
## what it needs. The pager takes only its own buttons, pages and clamps, and
## Back returns to the over sheet before the next Back leaves for the menu.
func _check_unlock_pager() -> void:
	var sh = _bare_shell()
	sh.runs_dir = RUNEND_RUNS
	sh.profile = Profile.new()
	sh.run_kind = "career"
	sh.seed_v = 4242
	var g = Game.new(4242, {})
	g.floor_num = 7
	g.won = true
	g.over = true
	sh.game = g
	sh._game_is_run = true
	sh._run_recorded = false
	sh._record_finished_run()
	var ids: Array = sh._unlock_ids()
	_check(sh._run_unlocks == sh.profile.last_report["unlocks"] and String(sh._run_unlocks[0]) == "tier:1",
		"_run_unlocks is last_report.unlocks, the difficulty first (%s)" % str(sh._run_unlocks))
	_check(ids.size() == sh._run_unlocks.size() + sh._run_report.get("feats", []).size() and ids.size() > 5,
		"the pager lists every unlock and every feat (%d)" % ids.size())
	var cards: Array = sh._unlock_cards(ids)
	_check(cards.size() == ids.size(), "one pager card per id")
	var by_id := {}
	for i in ids.size():
		by_id[String(ids[i])] = cards[i]
		_check(not String(cards[i][1]).contains("_") and String(cards[i][1]) != "",
			"pager card %s is named in words (%s)" % [ids[i], cards[i][1]])
		_check(String(cards[i][4]) != "", "pager card %s wears a kind badge" % ids[i])
	_check(by_id.has("double_oil") and String(by_id["double_oil"][1]) == "Slick Combine",
		"double_oil reads Slick Combine on its card")
	_check(by_id.has("skyrunner") and String(by_id["skyrunner"][1]) == "Skyrunner (needs Aeolian)"
		and String(by_id["skyrunner"][2]).contains("Aeolian"),
		"a gated loadout's card says what it needs (%s)" % str(by_id.get("skyrunner", [])))
	_check(String(by_id["tier:1"][1]) == String(Content.TIERS[0]["name"]) and String(by_id["tier:1"][4]) == "TIER 1",
		"a difficulty card is named for the tier and badged TIER 1")
	# with Aeolian open, Aeolian's card says it opens Skyrunner
	var p2 = Profile.new()
	p2.unlocked_loadouts = ["skyrunner"]
	p2.unlocked_packages = ["aeolian"]
	sh.profile = p2
	var ac: Array = sh._unlock_cards(["aeolian", "skyrunner"])
	_check(String(ac[0][2]).ends_with("opens Skyrunner") and String(ac[1][1]) == "Skyrunner",
		"the package that makes a loadout playable says so (%s / %s)" % [ac[0][2], ac[1][1]])
	sh.profile = Profile.load_from(TEST_PROFILE)
	sh.profile.last_report = {}
	# the over sheet: three rows, then the pager's cue; the rows are its tap target
	var info: Dictionary = sh._over_info_now()
	var ul: Array = info["unlocks"]
	_check(ul.size() == 4 and String(ul[3]) == "+%d more  ·  tap for all" % (ids.size() - 3),
		"the over sheet shows three unlocks, then '+n more  ·  tap for all' (%s)" % str(ul))
	var rect_bad := 0
	for vp in CARD_VIEWPORTS:
		var vw: float = vp.x
		var vh: float = vp.y
		var lay: Dictionary = sh._over_layout(info, vw, vh)
		var ur: Rect2 = lay["unlock_rect"]
		if ur.size.y <= 0.0 or ur.position.x < 0 or ur.end.x > vw or ur.position.y < 0 or ur.end.y > float(lay["button_top"]):
			rect_bad += 1
		for b in lay["buttons"]:
			if Rect2(b["rect"]).intersects(ur):
				rect_bad += 1
		var shown := 0
		for it in lay["items"]:
			if String(it["id"]).begins_with("unlock"):
				shown += 1
				var top: float = float(it["y"]) - float(it["size"])
				if not ur.has_point(Vector2(vw / 2.0, top + float(it["size"]) * 0.5)):
					rect_bad += 1
		if shown == 0:
			rect_bad += 1
	_check(rect_bad == 0, "the unlock rows' tap target covers every drawn row, clear of the buttons, at every viewport (%d faults)" % rect_bad)
	# the pager opens, takes only its own buttons, pages and clamps
	var g0 = sh.game
	var seed0: int = sh.seed_v
	sh._tap("unlocks")
	_check(sh.mode == "unlocks" and sh.unlock_page == 0, "tapping the unlock rows opens the pager")
	var vw0 := 1080.0
	var vh0 := 2400.0
	sh.hotspots.clear()
	for b in sh._over_layout(info, vw0, vh0)["buttons"]:
		sh.hotspots.append({"rect": b["rect"], "tag": b["tag"]})  # the sheet behind, not yet redrawn
	for b in sh.hotspots.duplicate():
		sh._click(Rect2(b["rect"]).get_center())
	sh._click(Vector2(5, 5))
	sh._key(KEY_N)
	sh._key(KEY_R)
	_check(sh.mode == "unlocks" and sh.game == g0 and sh.seed_v == seed0 and sh.screen == "game",
		"a tap on the sheet behind, off-card or a run key starts nothing from the pager")
	var pinfo: Dictionary = sh._unlock_page_info(0)
	var pages: int = int(pinfo["pages"])
	_check(pages == ceili(float(ids.size()) / Shell.CARDS_PER_PAGE) and pinfo["cards"].size() == mini(5, ids.size()),
		"five cards a page, %d page(s)" % pages)
	var pl: Dictionary = sh._unlocks_layout(vw0, vh0, pinfo)
	sh.hotspots.clear()
	for b in pl["buttons"]:
		sh.hotspots.append({"rect": b["rect"], "tag": b["tag"]})
	var tags0: Array = sh.hotspots.map(func(h): return String(h["tag"]))
	_check(tags0 == ["close", "unlock_page:+1"], "page 1's row is DONE and > (%s)" % str(tags0))
	sh._click(Rect2(sh.hotspots[1]["rect"]).get_center())
	_check(sh.unlock_page == 1 and sh.mode == "unlocks", "> turns the page")
	for i in pages + 2:
		sh._key(KEY_RIGHT)
	_check(sh.unlock_page == pages - 1, "paging clamps at the last page")
	for i in pages + 2:
		sh._tap("unlock_page:-1")
	_check(sh.unlock_page == 0, "...and at the first")
	sh._back()
	_check(sh.mode == "normal" and sh.game.over and sh.screen == "game", "Back leaves the pager for the over sheet")
	_check(sh._back() == "menu" and sh.screen == "menu", "...and the next Back goes to the menu")
	sh.screen = "game"
	sh._tap("unlocks")
	_check(sh.mode == "unlocks", "the pager reopens after a trip to the menu")
	sh._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(sh.mode == "normal" and sh.screen == "game", "Android's Back closes the pager into the sheet")
	sh._tap("unlocks")
	_check(sh.mode == "unlocks", "...and opens again for ENTER")
	sh._key(KEY_ENTER)
	_check(sh.mode == "normal", "ENTER is the pager's DONE")
	# the geometry, every page, every phone shape
	var geo_bad := 0
	for vp in CARD_VIEWPORTS:
		var vw: float = vp.x
		var vh: float = vp.y
		for pg in pages:
			var L: Dictionary = sh._unlocks_layout(vw, vh, sh._unlock_page_info(pg))
			var last_card := 0.0
			for c in L["cards"]:
				last_card = maxf(last_card, Rect2(c["rect"]).end.y)
			var row_top := 9999.0
			var rects: Array = []
			for b in L["buttons"]:
				var br: Rect2 = b["rect"]
				row_top = minf(row_top, br.position.y)
				if br.end.y > vh * 0.955 + 0.01 or float(b["size"]) / vh < CARD_MIN_VH or br.position.x < 0 or br.end.x > vw:
					geo_bad += 1
				for o in rects:
					if Rect2(o).intersects(br):
						geo_bad += 1
				rects.append(br)
			var pline: Dictionary = L["page_line"]
			if String(pline["text"]) != "":
				var py: float = float(pline["y"])
				if py - float(pline["size"]) < last_card or py + float(pline["size"]) * 0.3 > row_top \
						or float(pline["size"]) / vh < CARD_MIN_VH:
					geo_bad += 1
			if last_card > row_top:
				geo_bad += 1
	_check(geo_bad == 0, "the pager's cards, page line and button row fit at every viewport (%d faults)" % geo_bad)
	# a daily (nothing unlocked) and a locked sheet never open it
	sh.game = Game.new(77, {})
	sh.game.over = true
	sh._run_unlocks = []
	sh._run_report = {}
	sh._tap("unlocks")
	_check(sh.mode == "normal", "no unlocks: the pager does not open")
	if sh._run_save != null:
		sh._run_save.close()
		sh._run_save = null
	sh.free()
	_clear_runend_runs()
	print("unlock pager: %d cards over %d page(s), only its own buttons, Back to the sheet" % [ids.size(), pages])


## Pings through the real paths: a run driven by a bot through _act earns a
## casts ping and DEEPEST YET as banners at career priority, once; a resumed
## run marks what it already earned and never re-announces; the tutorial and
## a daily carry no ref.
func _check_career_pings() -> void:
	var seed_v := 11
	# where a sprout run on this seed gets to: its first effective base
	var probe = Game.new(seed_v, {})
	var pbot = Roster.make("sprout", seed_v)
	var acts: Array = []
	var base := ""
	while acts.size() < 400 and not probe.over and (base == "" or int(probe.floor_num) < 2):
		var a: Dictionary = pbot.choose_action(probe.snapshot(), probe.legal_actions())
		probe.step(a)
		if probe.over:
			break
		acts.append(a)
		if base == "":
			for b in probe.effective_uses:
				if int(probe.effective_uses[b]) > 0:
					base = String(b)
					break
	_check(base != "" and int(probe.floor_num) >= 2,
		"the probe run casts something effective and reaches floor 2 (%s, floor %d)" % [base, int(probe.floor_num)])
	var mk_profile := func():
		var p = Profile.new()
		p.runs = 1
		p.best_floor = 1
		p.milestone_rows = [{"id": "spiker", "kind": "loadout", "requires": {"casts": {base: 3}}, "desc": "x"}]
		p.casts_by_base = {base: 2}
		return p
	# live: through _act, banner by banner
	var sh = _bare_shell()
	sh.profile = mk_profile.call()
	sh.seed_v = seed_v
	sh.run_kind = "career"
	sh._new_game()
	_check(not sh._career_ref.is_empty() and sh._pings_fired.is_empty(), "a career run starts with a ref and nothing fired")
	var want_cast := "cast:%s:3" % base
	var cast_lines: Array = []
	var deep_lines: Array = []
	var career_banners := 0
	var deep_prio := -1
	var deep_shown := false
	for a in acts:
		sh._banner = []
		sh._banner_q = []
		sh._banner_ms = -99999
		var had_cast: bool = sh._pings_fired.has(want_cast)
		var had_deep: bool = sh._pings_fired.has("deepest")
		sh._act(a)
		var seen: Array = [sh._banner]
		for q in sh._banner_q:
			seen.append(q["lines"])
			if not had_deep and q["lines"].size() == 2 and String(q["lines"][0]) == "DEEPEST YET":
				deep_prio = int(q["prio"])
		if not had_deep and sh._banner.size() == 2 and String(sh._banner[0]) == "DEEPEST YET":
			deep_shown = true
		for ln in seen:
			if ln.size() == 2 and String(ln[1]).ends_with("unlocks when this run ends"):
				career_banners += 1
				if not had_cast:
					cast_lines = ln
			if ln.size() == 2 and String(ln[0]) == "DEEPEST YET":
				career_banners += 1
				if not had_deep:
					deep_lines = ln
		if sh.game.over:
			break
	_check(sh._pings_fired.has(want_cast) and cast_lines == ["%s 3/3" % Profile._ability_name(base).to_upper(),
		"Spiker unlocks when this run ends"], "the third cast pings the unlock (%s)" % str(cast_lines))
	_check(sh._pings_fired.has("deepest") and String(deep_lines[1] if deep_lines.size() > 1 else "").begins_with("floor 2"),
		"floor 2 on a best of 1 is DEEPEST YET (%s)" % str(deep_lines))
	_check(career_banners == 2, "each ping is announced exactly once (%d)" % career_banners)
	_check(int(Feedback.BANNER_PRIO["career"]) < int(Feedback.BANNER_PRIO["stairs"]), "pings queue at the lowest priority")
	# _act pushes the ping AT career priority: on the floor-change step it waits
	# in the queue behind the title card instead of showing (mutation: push it
	# at BANNER_PRIO.boss and it shows at once; at 0 its queue prio is wrong)
	_check(deep_prio == int(Feedback.BANNER_PRIO["career"]) and not deep_shown,
		"DEEPEST YET is held in the queue at career priority on its step (prio %d, shown %s)" % [deep_prio, str(deep_shown)])
	_check(int(sh._career_ref["best_floor"]) == int(sh.profile.bests_snapshot(sh.sel_loadout)["best_floor"]),
		"the ref's best floor IS bests_snapshot's (C10)")
	# a ping lands with the floor title card: it waits in the queue until the
	# card has gone, and a higher-priority banner is never held
	sh._banner = []
	sh._banner_q = []
	sh._banner_ms = -99999
	sh._floor_fade_ms = Time.get_ticks_msec()
	sh._push_banner(["DEEPEST YET", "floor 2"], Shell.COL_GOLD, int(Feedback.BANNER_PRIO["career"]))
	var held_q: bool = sh._banner.is_empty() and sh._banner_q.size() == 1
	sh._tick_banner()
	held_q = held_q and sh._banner.is_empty()
	sh._floor_fade_ms = Time.get_ticks_msec() - sh.FLOOR_CARD_MS - 1
	sh._tick_banner()
	_check(held_q and sh._banner == ["DEEPEST YET", "floor 2"] and sh._banner_q.is_empty(),
		"a career ping waits out the floor title card, then shows (%s / %s)" % [str(sh._banner), str(sh._banner_q)])
	sh._banner = []
	sh._floor_fade_ms = Time.get_ticks_msec()
	sh._push_banner(["THE STAIRS AWAKEN"], Shell.COL_GOLD, int(Feedback.BANNER_PRIO["stairs"]))
	_check(sh._banner == ["THE STAIRS AWAKEN"], "only career priority waits for the card")
	if sh._run_save != null:
		sh._run_save.close()
		sh._run_save = null
	sh.free()
	# resume: the same log, replayed - nothing it already earned re-fires
	var rs = _bare_shell(true)
	rs.profile = mk_profile.call()
	rs._load_run()
	_check(rs.game != null and not rs.game.over and rs.run_kind == "career", "the logged run resumes")
	_check(rs._pings_fired.has(want_cast) and rs._pings_fired.has("deepest"),
		"a resumed run marks the pings it already earned (%s)" % str(rs._pings_fired.keys()))
	_check(Profile.ping_events(rs._career_ref, int(rs.game.floor_num), rs.game.effective_uses, rs._pings_fired).is_empty(),
		"...so none re-fires")
	rs._game_is_run = true
	rs._banner = []
	rs._banner_q = []
	var more: Array = rs._legal_of("end_turn")
	if not more.is_empty() and rs.game.phase == "play":
		rs._act(more[0])
	var again := false
	for ln in [rs._banner] + rs._banner_q.map(func(q): return q["lines"]):
		if ln.size() == 2 and (String(ln[0]) == "DEEPEST YET" or String(ln[1]).ends_with("when this run ends")):
			again = true
	_check(not again, "the next step after a resume announces nothing old")
	if rs._run_save != null:
		rs._run_save.close()
		rs._run_save = null
	rs.free()
	DirAccess.remove_absolute(TEST_RUN_SAVE)
	# the tutorial and a daily: no ref, no pings
	var ds = _bare_shell()
	ds._start_tutorial()
	_check(ds._career_ref.is_empty(), "the tutorial carries no career ref")
	ds._start_run("daily")
	_check(ds.run_kind == "daily" and ds._career_ref.is_empty(), "a daily carries no career ref")
	ds._start_run("career")
	_check(not ds._career_ref.is_empty(), "a career run does")
	if ds._run_save != null:
		ds._run_save.close()
		ds._run_save = null
	ds.free()
	DirAccess.remove_absolute(TEST_RUN_SAVE)
	print("career pings: %s 3/3 and DEEPEST YET once each, none after a resume, none in the tutorial or a daily" % base)


## The objective line: the floor's goal first, the career hint beside it on a
## career run ("floor 5 unlocks Mycology"), "tap for log" only alone - and
## every combination draws at >= OBJECTIVE_MIN_VH at every phone shape.
func _check_objective_line() -> void:
	var sh = _bare_shell()
	sh.profile = Profile.new()
	sh.game = Game.new(4242, {})
	sh.game.floor_num = 4
	sh._game_is_run = true
	sh.screen = "game"
	sh._career_ref = sh.profile.run_ref()
	var snap: Dictionary = sh.game.snapshot()
	snap["greened"] = int(snap["green_need"])
	var ob: Dictionary = sh._objective_line(snap)
	_check(String(ob["text"]) == "Reach the gold-ringed stairs  ·  floor 5 unlocks Mycology",
		"floor 4, stairs awake: the career hint rides with the goal (%s)" % ob["text"])
	var dsnap: Dictionary = snap.duplicate()
	dsnap["greened"] = 1
	dsnap["green_need"] = 5
	ob = sh._objective_line(dsnap)
	_check(String(ob["text"]) == "cleanse 1/5 to wake the stairs  ·  floor 5 unlocks Mycology",
		"the quota shortens beside the hint (%s)" % ob["text"])
	# no ref (a daily, the tutorial, a game set from outside): the old lines exactly
	var keep_ref: Dictionary = sh._career_ref
	sh._career_ref = {}
	_check(String(sh._objective_line(snap)["text"]) == "Reach the gold-ringed stairs  ·  tap for log"
		and String(sh._objective_line(dsnap)["text"]) == "Stairs dormant - cleanse 1/5 to green the floor",
		"without a career hint the line is what it always was")
	var bsnap: Dictionary = snap.duplicate()
	bsnap["floor"] = Content.FLOORS.size()
	_check(String(sh._objective_line(bsnap)["text"]) == "DESTROY THE BOSS  ·  tap for log", "the boss floor's line")
	sh._career_ref = keep_ref
	_check(String(sh._objective_line(bsnap)["text"]) == "DESTROY THE BOSS  ·  tap for log",
		"no milestone past the boss floor: no hint there")
	# the context line's last arm IS the objective line (no danger on an empty floor)
	sh.game.enemies.clear()
	sh._danger_rev += 1
	var cm: Dictionary = sh._context_msg(snap, 1080, 2400)
	_check(String(cm["text"]) == String(sh._objective_line(snap, 1080, 2400)["text"]),
		"_context_msg ends in _objective_line (%s)" % cm["text"])
	# the fit: every hint the shipped content can show (a fresh career's
	# milestone floors) beside the longest quota the floor table asks for, at
	# every phone shape - the hint must stay ON at >= OBJECTIVE_MIN_VH
	var max_need := 1
	for fr in Content.FLOORS:
		max_need = maxi(max_need, int(fr.get("green_need", 0)))
	var hint_floors: Array = keep_ref["floors"].keys()
	# ...and past what fits - the longest name any milestone carries, and all
	# six loadouts on one floor - the hint is DROPPED, never drawn under the floor
	var lname := ""
	for m in Content.MILESTONES:
		var nm := Profile.unlock_name(String(m["id"]))
		if nm.length() > lname.length():
			lname = nm
	var crowd: Array = []
	for lid in Content.LOADOUTS:
		crowd.append(String(Content.LOADOUTS[lid]["name"]))
	var drop_bad := 0
	var hint_dropped := 0
	var log_bad := 0
	var bad := 0
	var worst := 9.9
	var worst_at := ""
	for vp in CARD_VIEWPORTS:
		var vw: float = vp.x
		var vh: float = vp.y
		sh._career_ref = keep_ref
		for hf in hint_floors:
			for sn in [snap, dsnap]:
				var big: Dictionary = sn.duplicate()
				big["floor"] = int(hf) - 1
				if int(big["greened"]) < int(big["green_need"]):
					big["greened"] = max_need - 1
					big["green_need"] = max_need
				var o: Dictionary = sh._objective_line(big, vw, vh)
				var f := float(sh._fit_size(String(o["text"]), int(vh * 0.022), vw * 0.95)) / vh
				if f < worst:
					worst = f
					worst_at = "'%s' at %dx%d" % [o["text"], int(vw), int(vh)]
				if f < Shell.OBJECTIVE_MIN_VH:
					bad += 1
				if not String(o["text"]).contains("floor %d unlocks" % int(hf)):
					bad += 1
					print("objective line dropped its career hint at %dx%d: %s" % [vw, vh, o["text"]])
		for names in [[lname], crowd]:
			sh._career_ref = {"runs": 0, "best_floor": 0, "floors": {5: names}, "casts": []}
			var big2: Dictionary = dsnap.duplicate()
			big2["greened"] = 99
			big2["green_need"] = 100
			var oc: Dictionary = sh._objective_line(big2, vw, vh)
			if float(sh._fit_size(String(oc["text"]), int(vh * 0.022), vw * 0.95)) / vh < Shell.OBJECTIVE_MIN_VH:
				drop_bad += 1
			# on a stairs-awake floor a dropped hint gives the goal back its
			# "tap for log" (mutation: delete the had_hint restore in _objective_line)
			var aw: Dictionary = snap.duplicate()
			aw["floor"] = 4
			var oa: Dictionary = sh._objective_line(aw, vw, vh)
			if not String(oa["text"]).contains("unlocks"):
				hint_dropped += 1
				if String(oa["text"]) != "Reach the gold-ringed stairs  ·  tap for log":
					log_bad += 1
					print("a dropped hint left the stairs line bare at %dx%d: %s" % [vw, vh, oa["text"]])
	_check(drop_bad == 0, "a hint too long to fit is dropped, never drawn under the floor (%d)" % drop_bad)
	_check(hint_dropped > 0 and log_bad == 0,
		"a dropped hint restores 'tap for log' beside the stairs goal (%d dropped, %d bare)" % [hint_dropped, log_bad])
	_check(bad == 0, "%d objective line(s) under %.1f%% of vh or without the career hint (worst %s)" % [
		bad, Shell.OBJECTIVE_MIN_VH * 100.0, worst_at])
	sh.free()
	print("objective line: hint kept at %d viewports, worst %.3f%% of vh (%s)" % [CARD_VIEWPORTS.size(), worst * 100.0, worst_at])


## --- Block E (stage 9): encounter packs and biome reinforcements -----------
## The crew a floor drew is named on its title card (line 2) and its floor log
## line; a vent's tooltip names what it releases, read from the sim's own
## reinforce_kind of the smog forecast's spawn_wave, for THAT vent. Every
## expected name is read from the sim (game.encounter / reinforce_kind), never
## a literal, so a later data lever cannot break these checks. Plus the fit
## gates: the floor log line, the title card's line 2 and the vent line.
func _check_encounters() -> void:
	const Danger := preload("res://shell/danger.gd")
	var cfg := _pack_config()
	# the title card names the pack on a generated floor (mutation: drop the
	# crew from _floor_card_lines and both of these read "floor N of 7")
	var fs = _bare_shell()
	var named := 0
	for seed_i in [5, 11]:
		for fl in [1, 3]:
			fs.game = Game.new(seed_i, cfg)
			if fl != 1:
				fs.game._enter_floor(fl)
			var enc: Dictionary = fs.game.encounter(fl)
			_check(String(enc.get("name", "")) != "", "fixture: seed %d floor %d draws a pack under the pack config" % [seed_i, fl])
			var card: Array = fs._floor_card_lines(fs.game.snapshot())
			_check(String(card[1]) == "floor %d of 7  ·  %s" % [fl, String(enc.get("name", ""))],
				"the title card names the crew on floor %d: %s" % [fl, " | ".join(card)])
			named += 1
			# ...and the floor's own event carries the id the log names
			if fl != 1:
				var fev: Dictionary = {}
				for ev in fs.game._step_events:
					if String(ev.get("t", "")) == "floor":
						fev = ev
				_check(String(fev.get("encounter", "")) == String(enc["id"])
					and Feedback.ev_text(fev, fs.game) == "— %s · %s —" % [String(fev.get("name", "")), String(enc["name"])],
					"the floor %d event's log line names the crew (%s)" % [fl, Feedback.ev_text(fev, fs.game)])
	# ...and not on the tutorial's scripted floor or the boss floor
	fs.game = Game.new(1, Tutorial.game_config())
	_check(fs.game.encounter(1).is_empty(), "fixture: the tutorial floor draws no pack")
	var tcard: Array = fs._floor_card_lines(fs.game.snapshot())
	_check(String(tcard[1]) == "floor 1 of 7", "the tutorial's title card names no crew: %s" % " | ".join(tcard))
	fs.game = Game.new(5, cfg)
	fs.game._enter_floor(7)
	var bcard: Array = fs._floor_card_lines(fs.game.snapshot())
	_check(String(bcard[1]) == "floor 7 of 7" and " | ".join(bcard).contains("defeat the"),
		"the boss floor's title card names no crew and still says who to defeat: %s" % " | ".join(bcard))
	fs.free()
	# floor 1's crew through the REAL start path: Game.new emits floor 1's
	# `floor` event before any _act ever runs, so _new_game logs it and raises
	# the title card itself - and with the intro tips up the card waits for
	# them to close (mutation: drop the log loop, the card arming or the
	# _process release, and floor 1's crew is named nowhere)
	for intro in ["never", "always"]:
		var f1 = _bare_shell()
		f1.profile = Profile.new()
		f1.intro_mode = intro
		f1.seen_intro = false
		f1._start_run("career", 88)
		var crew1 := String(f1.game.encounter(1).get("name", ""))
		var card_up := func() -> bool:
			var age: int = Time.get_ticks_msec() - int(f1._floor_fade_ms)
			return age >= 0 and age < Shell.FLOOR_CARD_MS
		_check(crew1 == "Hound and Handler" and _any_has(f1.log_lines, "— Strip Mine I · " + crew1 + " —"),
			"intro %s: a fresh run's log names floor 1's crew (%s): %s" % [intro, crew1, str(f1.log_lines)])
		if intro == "never":
			_check(card_up.call() and String(f1._floor_card_lines(f1.game.snapshot())[1]).ends_with(crew1),
				"a fresh run raises floor 1's title card, naming its crew")
		else:
			_check(f1.mode == "intro" and not card_up.call(), "under the intro tips floor 1's card waits (mode %s)" % f1.mode)
			f1._back(false)
			f1._process(0.016)
			_check(f1.mode == "normal" and card_up.call(), "...and rises the moment they close")
		if f1._run_save != null:
			f1._run_save.close()
			f1._run_save = null
		f1.free()
	DirAccess.remove_absolute(TEST_RUN_SAVE)

	# the boss phase-2 golem: the sim's reinforcement event now carries its
	# kind, and the log names the golem from it
	var golem_seen := false
	for seed_b in range(1, 40):
		var gb := Game.new(seed_b, cfg)
		gb._enter_floor(7)
		var core: Dictionary = {}
		for e in gb.enemies:
			if String(e["kind"]) == "furnace_core":
				core = e
		if core.is_empty():
			continue
		gb._step_events = []
		gb._damage_enemy(core, int(core["hp"]) - 12, "strike")
		var rev: Array = gb._step_events.filter(func(ev): return String(ev.get("t", "")) == "reinforcement")
		_check(rev.size() == 1 and String(rev[0].get("kind", "")) == "coal_golem",
			"the furnace's phase-2 reinforcement event carries its kind (%s)" % str(rev))
		var gl: Array = Feedback.log_entries(rev, {}, gb, {}).map(func(l): return l["text"])
		_check(gl == ["A vent releases a Coal Golem"], "...and the log names the golem from it: %s" % str(gl))
		# the phase words announce the golem only when it came: the sim spawns
		# it on the first _open vent, so with every vent covered there is none
		# (mutation: drop the BOSS_PHASE_JOINS read and the covered arena still
		# says "a coal golem joins")
		var stp: Array = gb._step_events.duplicate()
		var pb: Array = Feedback.banners(stp, {}, gb, {})
		var plog: Array = Feedback.log_entries(stp, {}, gb, {}).map(func(l): return String(l["text"]))
		_check(not pb.is_empty() and String(pb[0]["lines"][1]).contains("a coal golem joins")
			and _any_has(plog, "a coal golem joins"),
			"a golem on the board: the phase words announce it (%s / %s)" % [str(pb), str(plog)])
		var gnc := Game.new(seed_b, cfg)
		gnc._enter_floor(7)
		var core_nc: Dictionary = {}
		for e in gnc.enemies:
			if String(e["kind"]) == "furnace_core":
				core_nc = e
		for vv in gnc.map["vents"]:
			if gnc._open(vv):
				gnc._spawn("drill_bot", vv)
		gnc._step_events = []
		gnc._damage_enemy(core_nc, int(core_nc["hp"]) - 12, "strike")
		var stn: Array = gnc._step_events.duplicate()
		var golems := gnc.enemies.filter(func(e): return String(e["kind"]) == "coal_golem").size()
		var nb: Array = Feedback.banners(stn, {}, gnc, {})
		var nlog: Array = Feedback.log_entries(stn, {}, gnc, {}).map(func(l): return String(l["text"]))
		_check(stn.any(func(ev): return String(ev.get("t", "")) == "boss_phase" and int(ev.get("phase", 0)) == 2)
			and golems == 0 and not nb.is_empty() and not String(nb[0]["lines"][1]).contains("golem")
			and String(nb[0]["lines"][0]) == "THE FURNACE STOKES" and not _any_has(nlog, "golem")
			and _any_has(nlog, "now ignites all oil"),
			"every vent covered: phase 2 brings no golem, and the words announce none (%d golems; %s / %s)" % [
				golems, str(nb), str(nlog)])
		golem_seen = true
		break
	_check(golem_seen, "fixture: a seed whose boss floor is the Furnace Core")

	# the vent tooltip on a fresh default game: floor 1's reinforce list is
	# [drill_bot] (mutation: drop the kind from _vent_line and this reads
	# "releases in N turns")
	var g1 := Game.new(4242, cfg)
	var vsh = _danger_shell(g1)
	vsh.hotspots = []
	var v1: Vector2i = g1.map["vents"][0]
	g1.terrain.erase(v1)
	for e in g1.enemies:
		if e["pos"] == v1:
			e["pos"] = Vector2i(-9, -9)
	vsh._danger_rev += 1
	vsh._show_tooltip(_tile_px(vsh, v1))
	_check(vsh.tooltip_tile == v1 and _any_has(vsh.tooltip, "releases a Drill Bot"),
		"a fresh game's vent tooltip names its release: %s" % str(vsh.tooltip))
	_check(String(Content.FLOORS[0]["reinforce"][0]) == "drill_bot", "fixture: floor 1 releases drill bots")
	# a wall over the vent: _tick_smog skips a vent that is not _open (Roots
	# "blocks"), so the tooltip names NO release there - it says the vent is
	# covered (mutation: drop the covered arm and this reads "releases a Drill
	# Bot" for a machine that will not come)
	g1.terrain[v1] = {"kind": "roots", "ttl": 3}
	_check(not g1._open(v1) and bool(Content.terrain("roots", "blocks", false)), "fixture: roots block the vent")
	vsh._danger_rev += 1
	vsh._show_tooltip(_tile_px(vsh, v1))
	_check(vsh.tooltip_tile == v1 and vsh.tooltip.has(Shell.VENT_COVERED_LINE)
		and not _any_has(vsh.tooltip, "releases a") and not _any_has(vsh.tooltip, "releases in")
		and not _any_has(vsh.tooltip, "releases next"),
		"a walled vent's tooltip says it releases nothing while covered: %s" % str(vsh.tooltip))
	# ...and the real smog tick agrees: walk the smog to the wave and the
	# walled vent spawns nothing while the open ones do (floor 4: several
	# vents, so the open half of the claim is tested too)
	var gw := Game.new(5, cfg)
	gw._enter_floor(4)
	gw.enemies.clear()
	gw.terrain.clear()
	_check(gw.map["vents"].size() >= 2, "fixture: seed 5 floor 4 has several vents (%d)" % gw.map["vents"].size())
	var vw: Vector2i = gw.map["vents"][0]
	gw.terrain[vw] = {"kind": "roots", "ttl": 99}
	var fcw: Dictionary = gw.smog_forecast()
	gw.smog = int(fcw["spawn_at"]) - 1
	gw._step_events = []
	gw._tick_smog()
	var at_wall := 0
	var reinf := 0
	for ev in gw._step_events:
		if String(ev.get("t", "")) == "reinforcement":
			reinf += 1
			if ev["tile"] == vw:
				at_wall += 1
	_check(at_wall == 0 and Danger.vent_state(gw.snapshot(), vw) == "covered" and reinf > 0,
		"the sim agrees: the walled vent releases nothing on the wave (%d there, %d elsewhere)" % [at_wall, reinf])
	g1.terrain.erase(v1)
	vsh.free()
	# Danger.vent_state against the sim's own _open and growth test, over
	# generated floors with each vent covered by every terrain kind, a machine
	# on it, the tender on it, its tile turned to wall, and bare (mutation:
	# drop any conjunct of the mirror - the tile, the tender, a machine, the
	# "blocks" read - and it disagrees here; a generated vent is always floor,
	# so the "wall" setup is the only one the tile conjunct decides)
	var vs_n := 0
	var vs_bad: Array = []
	var vs_seen := {}
	for seed_v in [1, 2, 3]:
		for fv in range(1, 7):
			var gv := Game.new(seed_v, cfg)
			gv._enter_floor(fv)
			for vvi in gv.map["vents"].size():
				var vv: Vector2i = gv.map["vents"][vvi]
				var setups: Array = ["bare", "enemy", "player", "wall"]
				for tk in Content.TERRAIN:
					setups.append("t:" + String(tk))
				for su in setups:
					var gc = gv.clone()
					gc.terrain.erase(vv)
					for e in gc.enemies:
						if e["pos"] == vv:
							e["pos"] = Vector2i(-9, -9)
					if su == "enemy":
						gc._spawn("drill_bot", vv)
					elif su == "player":
						gc.player["pos"] = vv
					elif su == "wall":
						gc.map["tiles"][vv.y * int(gc.map["w"]) + vv.x] = MapGen.T_WALL
					elif String(su).begins_with("t:"):
						gc.terrain[vv] = {"kind": String(su).substr(2), "ttl": 3}
					var want := "open"
					if not gc._open(vv):
						want = "covered"
					elif gc._terrain_kind(vv) == "growth":
						want = "sealed"
					var got := Danger.vent_state(gc.snapshot(), vv)
					vs_n += 1
					vs_seen[got] = true
					if got != want and vs_bad.size() < 4:
						vs_bad.append("seed %d f%d vent %d %s: %s, sim %s" % [seed_v, fv, vvi, su, got, want])
	_check(vs_bad.is_empty() and vs_seen.size() == 3,
		"Danger.vent_state mirrors _open and the growth seal on %d vent states (%s seen; %s)" % [vs_n, str(vs_seen.keys()), str(vs_bad)])
	# no wave inside the horizon, or no kind: the old words (and none at all
	# with nothing due)
	var ksh = _bare_shell()
	ksh.game = Game.new(4242, cfg)
	_check(ksh._vent_kind({"spawn_wave": -1}, 0) == "", "no wave in the forecast: no kind")
	_check(ksh._vent_line("", 4) == "releases in 4 turns" and ksh._vent_line("", 1) == "releases next turn"
		and ksh._vent_line("", -1) == "", "without a kind the vent line keeps its old words")
	_check(ksh._vent_line("rust_hound", 4) == "releases a Rust Hound in 4 turns"
		and ksh._vent_line("oil_sludge", 1) == "releases an Oil Sludge next turn",
		"the vent line's two forms: %s / %s" % [ksh._vent_line("rust_hound", 4), ksh._vent_line("oil_sludge", 1)])
	ksh.free()

	# a floor whose reinforce list has several kinds, on a wave where two
	# vents release DIFFERENT kinds: each vent's tooltip names reinforce_kind's
	# answer for THAT vent (mutation: pass vi 0 for every vent)
	var found := false
	for seed_m in range(1, 30):
		if found:
			break
		for fm in range(3, 7):
			if found:
				break
			if Content.FLOORS[fm - 1].get("reinforce", []).size() < 2:
				continue
			var gm := Game.new(seed_m, cfg)
			gm._enter_floor(fm)
			var vents: Array = gm.map["vents"]
			var ok_v: Array = []
			for vi in vents.size():
				var vt: Vector2i = vents[vi]
				if gm._open(vt) and not (gm.terrain.has(vt) and String(gm.terrain[vt]["kind"]) == "growth"):
					ok_v.append(vi)
			if ok_v.size() < 2:
				continue
			for sm in range(0, 60):
				gm.smog = sm
				var fc: Dictionary = gm.smog_forecast()
				var w := int(fc["spawn_wave"])
				if w < 0 or int(fc["spawn_in"]) < 1:
					continue
				var fdef: Dictionary = gm.floor_def(fm)
				var ka := gm.reinforce_kind(fdef, w, ok_v[0])
				var kb := gm.reinforce_kind(fdef, w, ok_v[1])
				if ka == kb:
					continue
				found = true
				var msh = _danger_shell(gm)
				msh.hotspots = []
				for pair in [[ok_v[0], ka], [ok_v[1], kb]]:
					var vt2: Vector2i = vents[int(pair[0])]
					msh._show_tooltip(_tile_px(msh, vt2))
					var sky: Dictionary = msh._danger_state()["sky"]
					var want := msh._vent_line(String(pair[1]), int(sky["spawn_in"]))
					_check(msh.tooltip_tile == vt2 and int(sky["spawn_wave"]) == w and msh.tooltip.has(want)
						and want.contains(Names.a_name(String(pair[1]))),
						"seed %d floor %d smog %d: vent %d's tooltip names its own release %s (%s)"
						% [seed_m, fm, sm, int(pair[0]), String(pair[1]), str(msh.tooltip)])
				msh.free()
				break
	_check(found, "fixture: a floor, wave and two vents releasing different kinds")

	# fit gates, in the style of the others
	# (1) every (floor name, pack name) floor log line fits LOG_LINE_MAX
	var log_bad := 0
	var log_worst := ""
	var tsh = _bare_shell()
	tsh.game = Game.new(1, cfg)
	for row in Content.FLOORS:
		for pk in row.get("encounters", []):
			var ln := Feedback.ev_text({"t": "floor", "floor": 1, "name": row["name"], "encounter": pk["id"]}, tsh.game)
			if ln.length() > log_worst.length():
				log_worst = ln
			if ln.length() > Feedback.LOG_LINE_MAX or not ln.contains(String(pk["name"])):
				log_bad += 1
	_check(log_bad == 0, "every crew's floor log line fits %d chars (%d bad, longest '%s')" % [Feedback.LOG_LINE_MAX, log_bad, log_worst])
	# (2) every title-card line 2, with the longest pack name on its floor (by
	# drawn width), draws at >= CARD_MIN_VH inside 0.9vw at every viewport
	var card_worst := 1.0
	var card_what := ""
	for n in Content.FLOORS.size():
		var widest := ""
		var wpx := -1.0
		for pk2 in Content.FLOORS[n].get("encounters", []):
			var cand := Shell.FLOOR_CARD_CREW % [n + 1, String(pk2["name"])]
			var px: float = tsh.font.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			if px > wpx:
				wpx = px
				widest = cand
		if widest == "":
			continue
		for vp in CARD_VIEWPORTS:
			var fr: float = float(tsh._fit_size(widest, int(vp.y * 0.018), vp.x * 0.9)) / vp.y
			if fr < card_worst:
				card_worst = fr
				card_what = "%s at %dx%d" % [widest, vp.x, vp.y]
	_check(card_worst >= CARD_MIN_VH, "the title card's crew line draws at %.3f%% of vh, under %.2f%% (%s)"
		% [card_worst * 100.0, CARD_MIN_VH * 100.0, card_what])
	# (3) every vent tooltip line, for every kind any floor releases and the
	# widest countdown, keeps the tooltip's own wrap: <= 2 lines, nothing
	# shrunk under CARD_MIN_VH
	var kinds := {}
	for row2 in Content.FLOORS:
		for k in row2.get("reinforce", []):
			kinds[String(k)] = true
	var vent_bad := 0
	for vp2 in CARD_VIEWPORTS:
		for k2 in kinds:
			for vin in [Danger.SKY_HORIZON, 1]:
				var vl: String = tsh._vent_line(String(k2), vin)
				var wr: Dictionary = tsh._wrap(vl, int(vp2.y * 0.021), vp2.x * 0.86, 2)
				if wr["lines"].size() > 2 or float(wr["size"]) / vp2.y < CARD_MIN_VH:
					vent_bad += 1
		var cwr: Dictionary = tsh._wrap(Shell.VENT_COVERED_LINE, int(vp2.y * 0.021), vp2.x * 0.86, 2)
		if cwr["lines"].size() > 2 or float(cwr["size"]) / vp2.y < CARD_MIN_VH:
			vent_bad += 1
	_check(vent_bad == 0, "the vent lines (and the covered line) fit the tooltip at every viewport (%d bad)" % vent_bad)
	tsh.free()
	print("encounters: %d crew cards, crew line worst %.3f%% of vh (%s), longest log line %d chars, %d vent kinds, %d vent states mirrored"
		% [named, card_worst * 100.0, card_what, log_worst.length(), kinds.size(), vs_n])
