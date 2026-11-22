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

## A kit that fills every slot with slot 0 held by a mobility ability - the one
## the forge may never scrap (sim/game.gd _is_mobility).
const FULL_KIT := ["mycelium_dash", "solar_lance", "seed_bomb", "vine_whip", "thorn_shield"]
const TMP_SAVE := "user://test_import_run.save"
## Every _bare_shell reads and writes its career here, never the player's real
## profile (Shell.PROFILE_PATH); _init deletes it at the end.
const TEST_PROFILE := "user://test_shell_profile.json"
## every _bare_shell restores (and writes) its run save here, never the real one
const TEST_RUN_SAVE := "user://test_shell_run.save"
## ...and reads and writes its settings here, never the player's tender.cfg:
## every set: tap saves them, and a test must not leave the player's
## difficulty, loadout or package changed (nor drop a legacy seed_mode key)
const TEST_CFG := "user://test_shell_settings.cfg"
const TMP_JSON := "user://test_import_record.json"

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
	# a tap on a finished daily's over sheet is NEW RUN: a career run (C25),
	# never another daily try on today's seed
	day._start_run("daily", dseed)
	var tries_now := int(day.profile.daily_tries.get(Profile.daily_key(dseed), 0))
	day.game.over = true
	day.mode = "normal"
	day.hotspots.clear()
	day._click(Vector2(-10, -10))
	_check(day.run_kind == "career" and int(day.profile.daily_tries.get(Profile.daily_key(dseed), 0)) == tries_now,
		"a tap on a daily's over sheet starts a career run and counts no try (%s, %s)" % [day.run_kind,
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
		and String(day._menu_rows().filter(func(r): return String(r[1]) == "play")[0][0]) == "TAP AGAIN TO ABANDON",
		"PLAY over a live daily try starts nothing and asks for a second tap")
	day._tap("settings")
	day.mode = "normal"
	_check(String(day._menu_rows().filter(func(r): return String(r[1]) == "play")[0][0]) == "PLAY",
		"...any other tap disarms it")
	day._tap("play")
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

	shell.free()
	shell2.free()
	_check(_real_files() == real_before,
		"no test shell wrote the player's real settings, profile or run save")
	DirAccess.remove_absolute(TEST_PROFILE)
	DirAccess.remove_absolute(TEST_PROFILE + ".tmp")
	DirAccess.remove_absolute(TEST_CFG)
	print("FAILURES: %d" % fails if fails > 0 else "shell smoke: OK")
	quit(1 if fails > 0 else 0)


## A shell whose settings, career and run save all live at the scratch paths
## (set before `_ready`, which loads from them). Unlike _bare_shell it deletes
## nothing and keeps its live run, so one shell's save can restore in the next.
func _iso_shell():
	var sh = Shell.new()
	sh.profile_path = TEST_PROFILE
	sh.run_save_path = TEST_RUN_SAVE
	sh.cfg_path = TEST_CFG
	return sh


## The player's real settings, profile and run save, as text ("" = absent).
func _real_files() -> Array:
	var out: Array = []
	for pth in [Shell.CFG_PATH, Shell.PROFILE_PATH, Shell.RUN_SAVE_PATH]:
		out.append(FileAccess.get_file_as_string(pth) if FileAccess.file_exists(pth) else "")
	return out


## A shell with no live run attached: these tests drive `game` directly, so
## nothing may be appended to (or restored from) the on-disk run log.
func _bare_shell(keep_save := false):
	var sh = Shell.new()
	sh.profile_path = TEST_PROFILE  # before _ready: it loads from here
	sh.run_save_path = TEST_RUN_SAVE  # ...and restores (or deletes) a run save from here
	sh.cfg_path = TEST_CFG  # ...and its settings: every bare shell boots on the defaults
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
	print("meta card text: %d daily cards x %d viewports, worst %.4f%% of vh (%s)" % [
		meta.size(), CARD_VIEWPORTS.size(), m_worst * 100.0, m_worst_at])
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
	var dzw: Dictionary = Danger.compute(gw)
	var ew: Dictionary = Danger.escapes(gw)
	var cw = gw.clone()
	cw.step({"type": "strike", "dir": wd[0]})
	_check(bool(dzw["lethal"]) and cw.over and cw.won, "fixture: lethal, and the strike on the 1-HP boss wins the run")
	_check(bool(ew["strike"]), "a boss-killing strike counts as a strike escape (%s)" % str(ew))

	var sh = _bare_shell()
	# fit gate: the worst context line (the two longest enemy names, +9) and the
	# four guard flashes, at the context line's own size in its own box
	var names: Array = []
	for k in Content.ENEMIES:
		names.append(String(Content.ENEMIES[k]["name"]))
	names.sort_custom(func(a, b): return a.length() > b.length())
	var worst_ctx := "! INCOMING 99 - LETHAL  ·  %s, %s +9" % [names[0], names[1]]
	var fit_lines: Array = [worst_ctx, "Smog chokes NEXT TURN - descend to escape it"]
	for esc in [{"move": true}, {"strike": true}, {"item": [0]}, {"descend": true}, {}]:
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
	ml.profile.unseen = ["tier:%d" % Content.TIERS.size(), "spinning_shrine", "hydraulics", "skyrunner"]
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
	_check(badges >= 4 * CARD_VIEWPORTS.size(), "the maxed menu carries its badges (%d)" % badges)
	_check(small_badge == 0, "%d menu badge(s) below %.2f%% of vh" % [small_badge, CARD_MIN_VH * 100.0])
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
