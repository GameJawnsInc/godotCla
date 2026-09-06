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

## A kit that fills every slot with slot 0 held by a mobility ability - the one
## the forge may never scrap (sim/game.gd _is_mobility).
const FULL_KIT := ["mycelium_dash", "solar_lance", "seed_bomb", "vine_whip", "thorn_shield"]
const TMP_SAVE := "user://test_import_run.save"
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
	ak.free()

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
	# 5. upcycling flows through the shell (shrine press + ability forge)
	var shell3 = Shell.new()
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
	_check(shell3.flash == "cannot scrap your mobility ability", "...and says why")
	shell3._ability_press(1)
	_check(shell3.game.player["kit"].size() == ksz - 1 and String(shell3.game.player["kit"][0]).ends_with("+"),
		"forge upgrades one ability and scraps another")
	_check(not shell3.game.shop.has("forge"), "one forge per floor: the card is spent")
	_check(not _tags(shell3).has("forge"), "the forge card disappears after one forge")
	shell3._tap("forge")
	_check(shell3.mode == "normal" and shell3.flash == "the forge is cold",
		"a spent forge cannot be entered again")
	shell3.free()

	# 6. a killed app resumes byte-exact: replay from the on-disk action log
	var shell4 = Shell.new()
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
	var shell5 = Shell.new()
	shell5._ready()
	_check(shell5.game != null and shell5._game_is_run, "killed run auto-restores on boot")
	_check(shell5.game.total_turns == saved_turns, "restored run is at the same turn")
	_check(shell5.game.state_hash() == saved_hash, "restored run is byte-exact (replay determinism)")
	shell5._tap("resume")
	_check(shell5.screen == "game", "RESUME enters the restored run")
	shell5.free()

	# 6b. that same log is a regression pair: tests/import_run.gd replays it
	_check(Shell.RUN_SAVE_VERSION == Game.SIM_VERSION, "the shell stamps Game.SIM_VERSION")
	var export_path := OS.get_environment("SHELL_EXPORT_SAVE")
	if export_path != "":
		DirAccess.copy_absolute("user://tender_run.save", export_path)
	var parsed := ImportRun.parse_save("user://tender_run.save")
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
	DirAccess.remove_absolute("user://tender_run.save")

	# 6c. a log from an older sim is refused, and the loss is announced once
	var sf := FileAccess.open(TMP_SAVE, FileAccess.WRITE)
	sf.store_line(var_to_str({"v": Game.SIM_VERSION + 1, "seed": 5, "tier": 0, "config": {}}).replace("\n", " "))
	sf.store_line(var_to_str({"type": "end_turn"}).replace("\n", " "))
	sf.close()
	var stale := ImportRun.parse_save(TMP_SAVE)
	_check(not bool(stale.get("ok", true)) and String(stale.get("err", "")).contains("sim_version"),
		"import_run refuses a save from another sim version")
	DirAccess.copy_absolute(TMP_SAVE, "user://tender_run.save")
	var shell6 = Shell.new()
	shell6._ready()
	_check(shell6.save_lost, "a version-mismatched save raises the lost-run notice")
	_check(not FileAccess.file_exists("user://tender_run.save"), "the stale save is discarded")
	shell6._tap("play")
	_check(not shell6.save_lost, "a new run clears the notice")
	if shell6._run_save != null:
		shell6._run_save.close()
		shell6._run_save = null
	shell6.free()
	DirAccess.remove_absolute(TMP_SAVE)
	DirAccess.remove_absolute("user://tender_run.save")

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
		== "You take 2 damage (fire)", "a qualified damage source reads as the bare source")
	_check(evsh._ev_text({"t": "damage", "who": "player", "amt": 1, "src": "goo"})
		== "You take 1 damage (goo)", "an unqualified source is untouched")
	_check(evsh._ev_text({"t": "damage", "who": "drill_bot", "amt": 3}) == "Drill Bot takes 3",
		"enemy damage lines never show a source")
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
	var lf := FileAccess.open("user://tender_run.save", FileAccess.WRITE)
	lf.store_line("stand-in log")
	lf.close()
	arch._archive_run()
	_check(not FileAccess.file_exists("user://tender_run.save"), "the finished log leaves the live slot")
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
	# summary, a daily only scores its seed and unlocks nothing
	var prof_path: String = Shell.PROFILE_PATH
	var prof_before := FileAccess.get_file_as_string(prof_path) if FileAccess.file_exists(prof_path) else ""
	var rec = _bare_shell()
	rec.profile = Profile.new()
	rec._game_is_run = true
	rec._run_recorded = false
	rec.run_tier = 0
	rec.seed_mode = "random"
	rec.game = Game.new(4242, {})
	rec.game.over = true
	rec._record_finished_run()
	_check(rec.profile.runs == 1 and rec.profile.history.size() == 1,
		"a finished run reaches the career profile")
	_check(int(rec.profile.history[0]["seed"]) == 4242 and rec.profile.history[0]["kit"] == Content.STARTING_KIT,
		"the record is the sim's run_summary (seed and kit), not a stub")
	_check(rec.profile.daily_best.is_empty(), "a random run files no daily result")
	rec.seed_mode = "daily"
	rec._run_recorded = false
	rec.game = Game.new(77, {})
	rec.game.over = true
	rec._record_finished_run()
	_check(rec.profile.runs == 1 and rec.profile.history.size() == 1, "a daily run is not a career run")
	_check(rec.profile.daily_best.has("77"), "a daily run files that seed's result")
	_check(rec._run_unlocks.is_empty(), "a daily unlocks nothing")
	rec.free()
	if prof_before == "":
		DirAccess.remove_absolute(prof_path)
	else:
		var rf := FileAccess.open(prof_path, FileAccess.WRITE)
		rf.store_string(prof_before)
		rf.close()

	# 11. the title screen's run-setup rows (Block A): three cyclers gated by
	# the career, the config PLAY builds out of them, the status line that
	# names it, and the daily line that replaces the rows entirely
	var cfg_before := FileAccess.get_file_as_string(Shell.CFG_PATH) if FileAccess.file_exists(Shell.CFG_PATH) else ""
	var menu = _bare_shell()
	menu.profile = Profile.new()
	menu.seed_mode = "random"
	menu._clamp_selection()
	var rows0 := _rows(menu)
	_check(rows0.has("LOADOUT: Tender") and rows0.has("PACKAGE: none") and rows0.has("MUTATOR: none"),
		"a fresh career shows tender / none / none (%s)" % str(rows0))
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
	# daily mode: the seed's own config replaces the three rows
	var day = _bare_shell()
	day.profile = Profile.new()  # a daily needs nothing unlocked
	day.seed_mode = "daily"
	var dseed: int = day._daily_seed()
	var dc: Dictionary = Profile.daily_config(dseed)
	var drows := _rows(day)
	var today := ""
	for label in drows:
		if label.begins_with("TODAY: "):
			today = label
	_check(today != "", "daily mode shows the day's config line (%s)" % str(drows))
	_check(today.contains(String(Content.LOADOUTS[dc["loadout"]]["name"])),
		"...naming the daily's loadout (%s)" % today)
	for label in drows:
		_check(not label.begins_with("LOADOUT:") and not label.begins_with("PACKAGE:")
			and not label.begins_with("MUTATOR:"), "daily mode hides the cyclers (%s)" % label)
	day._roll_seed()  # what PLAY does first: in daily mode the date is the seed
	_check(day.seed_v == dseed, "daily mode rolls the day's seed (%d)" % day.seed_v)
	_check(str(day._run_config()) == str(Profile.daily_game_config(dseed)),
		"PLAY uses the daily config (%s)" % str(day._run_config()))
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
		day.seed_v = dseed2
		day._new_game()
		_check(day.game.loadout == String(d3["loadout"]) and day.game.packages == [String(d3["package"])]
			and day.game.mutators == [String(d3["mutator"])],
			"a daily run carries the seed's own config with nothing unlocked (%s)" % str(Profile.daily_config(dseed2)))
		_check(day.game.player["kit"] == Content.LOADOUTS[d3["loadout"]]["kit"],
			"...including its starting kit")
	for sh in [menu, day]:
		if sh._run_save != null:
			sh._run_save.close()
			sh._run_save = null
		sh.free()
	DirAccess.remove_absolute("user://tender_run.save")
	if cfg_before == "":
		DirAccess.remove_absolute(Shell.CFG_PATH)
	else:
		var cfgf := FileAccess.open(Shell.CFG_PATH, FileAccess.WRITE)
		cfgf.store_string(cfg_before)
		cfgf.close()

	shell.free()
	shell2.free()
	print("FAILURES: %d" % fails if fails > 0 else "shell smoke: OK")
	quit(1 if fails > 0 else 0)


## A shell with no live run attached: these tests drive `game` directly, so
## nothing may be appended to (or restored from) the on-disk run log.
func _bare_shell():
	var sh = Shell.new()
	sh._ready()
	if sh._run_save != null:
		sh._run_save.close()
		sh._run_save = null
	sh._game_is_run = false
	sh.screen = "game"
	sh.mode = "normal"
	return sh


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
