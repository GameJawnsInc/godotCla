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
const Profile := preload("res://meta/profile.gd")
const PROFILE_PATH := "user://tender_profile.json"
const RUN_SAVE_PATH := "user://tender_run.save"
# Replay compatibility rides on the sim's own version: a stale log replayed
# across a sim change diverges silently, so bump Game.SIM_VERSION there and
# every stamp (this save, regression records, autopsy dumps) follows.
const RUN_SAVE_VERSION := Game.SIM_VERSION
## Finished run logs are kept, not deleted: a real death is a replayable
## (seed, config, actions) pair - see tests/import_run.gd. This many survive.
const RUNS_KEEP := 10

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

## per-biome map palette: floor checker, wall body/top, two speckle colors.
## descending should feel like travelling, not repainting the same corridor.
const BIOME_PAL := {
	"strip_mine": {"f1": Color("31402f"), "f2": Color("2b392b"), "w": Color("3a434b"),
		"wt": Color("485259"), "s1": Color("55704a"), "s2": Color(0.42, 0.47, 0.42)},
	"refinery": {"f1": Color("2c3a3c"), "f2": Color("263336"), "w": Color("424b58"),
		"wt": Color("566476"), "s1": Color("4a7364"), "s2": Color(0.48, 0.35, 0.25)},
	"furnace": {"f1": Color("3e332b"), "f2": Color("372d27"), "w": Color("4a3b35"),
		"wt": Color("5e463a"), "s1": Color("9a5c30"), "s2": Color(0.42, 0.38, 0.35)},
}

## sprite id, display name, one-line blurb — legend sheet and hold-tooltips
const LEGEND := [
	["player", "You, the Tender", "descend, cleanse, survive"],
	["stairs", "Stairs", "the way down"],
	["shrine", "Shrine", "stand here to shop"],
	["vent", "Vent", "releases enemies as the smog rises"],
	["supply", "Supply pod", "step on it to stock your satchel (2 slots)"],
	["oil", "Oil", "corruption - cleanse from beside it for bloom. Burns"],
	["goo", "Goo", "corruption - cleanse for bloom. Hurts to step in"],
	["rich_goo", "Rich goo", "corruption - cleanse for extra bloom. Hurts to step in"],
	["ash", "Ash", "corruption from burnt oil - cleanse for bloom. Never shields the core"],
	["growth", "Growth", "stand on it: heal 1 HP a turn"],
	["fire", "Fire", "burns whoever stands in it. Leaves ash"],
	["smoke", "Smoke", "blocks beams. Screens tar/drain/grapple from 2+ tiles away"],
	["roots", "Roots", "blocks enemies for a while"],
	["drill_bot", "Drill Bot", "melee - shows its strike a turn ahead"],
	["oil_sludge", "Oil Sludge", "slow, leaves oil, splits when killed"],
	["sludgeling", "Sludgeling", "weak spawn"],
	["leech_drone", "Leech Drone", "drains banked charge from range"],
	["tar_spitter", "Tar Spitter", "gums one of your abilities"],
	["coal_golem", "Coal Golem", "SPIKED: melee costs you 1 HP. Bursts into smoke"],
	["welded_hulk", "Welded Hulk", "two drill bots welded - spiked and heavy"],
	["extractor_engine", "Extractor", "summons sludgelings - kill it first"],
	["rust_hound", "Rust Hound", "SPIKED - moves twice"],
	["cinder_mite", "Cinder Mite", "ignites oil"],
	["pump_jack", "Pump Jack", "pumps fresh oil"],
	["smokestack", "Smokestack", "speeds up the smog clock"],
	["magnet_crane", "Magnet Crane", "drags you toward it every turn"],
	["furnace_core", "Furnace Core", "floor 7 boss"],
	["overseer", "The Overseer", "floor 7 boss"],
	["the_dredge", "The Dredge", "floor 7 boss - eats your growth"],
]

const DIRS4 := {
	"up": Vector2i(0, -1), "down": Vector2i(0, 1),
	"left": Vector2i(-1, 0), "right": Vector2i(1, 0),
}

## Draft slot roles (Content.DRAFT_SLOT_REPORTS) as card badges: one word per
## role, drawn gold on the card. Presentation only - the sim reports the role
## and the sheet just names it, so a role with no entry here draws no badge
## rather than a wrong one.
const DRAFT_SLOT_LABEL := {
	"affinity": "AFFINITY",
	"upgrade": "UPGRADE",
	"wild": "WILD",
	"focus": "FOCUS",
}

var game
var seed_v := 0
var screen := "menu"  # menu | game | tutorial
var mode := "normal"  # normal | target_dir | target_tile | cleanse | draft_drop | up_keep | up_scrap | up_variant | intro | help | shop | log | settings
## Did the roll that produced the draft on screen spend an armed focus? Read
## off the draft_offer event, because a focus slot that found no candidate
## yields no FOCUS card and the snapshot cannot tell that from an ordinary
## draft. False after a resume mid-draft (no event seen), where the card
## itself is the only evidence left.
var _draft_focus_spent := false
var mode_slot := -1
var mode_targets: Array = []
var mode_pick := -1
## The forge's scrap slot, held between the up_scrap tap and the up_variant
## sheet (Block D6: a base forks into two named variants, so a forge is a
## three-tap choice - keep, scrap, then which fork).
var mode_scrap := -1
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
var save_lost := false     # a saved run was discarded by a version bump (menu notice)
## Where finished run logs are archived. A var, not a const, so a test can
## point the archive at scratch space instead of the player's own runs.
var runs_dir := "user://runs"

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

const FX_MS := 700
var _fx: Array = []  # transient map effects {kind, pos: Vector2 tile, text, col, t0}
var _floor_fade_ms := -99999  # descend wipe: new floor fades in from dark
var profile  # meta career: unlocks tiers/packages across runs (meta/profile.gd)
## The four run choices the title screen makes, all persisted in tender.cfg
## and all clamped to what the career unlocked (_clamp_selection). PLAY turns
## them into a run config through profile.game_config; in daily seed mode the
## seed's own Profile.daily_config replaces them for that run.
var sel_tier := 0        # difficulty, clamped to profile.unlocked_tier
var sel_loadout := "tender"  # Content.LOADOUTS id: the starting kit
var sel_package := ""    # the one package committed to the run ("" = none)
var sel_mutator := ""    # the one mutator the run carries ("" = none)
var run_tier := 0  # tier the live run actually started at
var _run_recorded := false
var _run_unlocks: Array = []
var _shake_ms := -99999
var _shake_mag := 0.0
var _banner: Array = []
var _banner_ms := -99999
var _run_save: FileAccess = null  # open append handle for the live run's log


func _ready() -> void:
	font = ThemeDB.fallback_font
	profile = Profile.load_from(PROFILE_PATH)
	_mk_styles()
	audio = AudioKit.new()
	add_child(audio)
	_load_settings()
	_clamp_selection()
	audio.sfx_on = sfx_on
	audio.music_on = music_on
	set_process(true)
	var env := OS.get_environment("SHELL_SEED")
	if env != "":
		seed_v = int(env)
		screen = "game"
		_new_game()
	elif FileAccess.file_exists(RUN_SAVE_PATH):
		_load_run()  # Android reclaimed the app mid-run: replay it back
	queue_redraw()


## Today's daily seed (UTC date): the same number for everyone, so the menu
## can show today's config before PLAY rolls the seed.
func _daily_seed() -> int:
	return hash(Time.get_date_string_from_system(true)) & 0x7FFFFFFF


func _roll_seed() -> void:
	if seed_mode == "daily":
		seed_v = _daily_seed()
	else:
		seed_v = (int(Time.get_unix_time_from_system()) * 1103515245 + Time.get_ticks_msec()) % 1000000


## Keep the menu's run choices inside what the career actually unlocked: the
## cfg file is written by whatever build ran last, and load_from can drop an
## unlock when content is renamed. Called on boot, on every menu draw and
## before a run starts, so an impossible selection can never reach the sim.
func _clamp_selection() -> void:
	sel_tier = clampi(sel_tier, 0, _max_tier())
	if not profile.available_loadouts().has(sel_loadout):
		sel_loadout = "tender"
	if not profile.unlocked_packages.has(sel_package):
		sel_package = ""
	if not profile.unlocked_mutators.has(sel_mutator):
		sel_mutator = ""


## The highest difficulty the DIFFICULTY row may show. The career gate is
## profile.unlocked_tier, but that number is the one unlock load_from cannot
## filter against Content, and a profile written by a build with more tiers
## (or kept while Content.TIERS shrank) hands back a tier that is not in the
## table: _menu_rows reads Content.TIERS[sel_tier - 1] for the row's name, and
## an out-of-range read there empties the whole menu - no PLAY, no QUIT. So
## the table's own size is the second bound, at the one place that picks the
## number rather than at every place that reads it.
func _max_tier() -> int:
	return mini(int(profile.unlocked_tier), Content.TIERS.size())


## The config PLAY starts a run with: the menu's own choices through the
## career gate, or - in daily seed mode - the seed's own frozen daily config,
## which no career unlock touches (a daily needs nothing unlocked).
func _run_config() -> Dictionary:
	if seed_mode == "daily":
		return Profile.daily_game_config(seed_v)
	var muts: Array = [] if sel_mutator == "" else [sel_mutator]
	return profile.game_config(sel_tier, muts, sel_loadout, sel_package)


func _new_game() -> void:
	_clamp_selection()
	var cfg: Dictionary = _run_config()
	run_tier = int(cfg.get("tier", 0))
	game = Game.new(seed_v, cfg)
	_draft_focus_spent = false  # a fresh run never inherits the last one's focus
	_game_is_run = true
	_run_recorded = false
	_run_unlocks = []
	save_lost = false  # the notice stands until the player starts a fresh run
	if _run_save != null:
		_run_save.close()
	_run_save = FileAccess.open(RUN_SAVE_PATH, FileAccess.WRITE)
	if _run_save != null:
		_run_save.store_line(var_to_str({"v": RUN_SAVE_VERSION, "seed": seed_v, "tier": run_tier, "config": cfg}).replace("\n", " "))
		_run_save.flush()
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
	_draft_focus_spent = false
	_game_is_run = false
	tut_step = 0
	tut_done = false
	mode = "normal"
	flash = ""
	tooltip = []
	log_lines = []
	queue_redraw()


## Restore the interrupted run: rebuild the game from its seed + config and
## replay the recorded actions. Determinism makes this byte-exact; a version
## mismatch or finished run just clears the save.
func _load_run() -> void:
	var f := FileAccess.open(RUN_SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var head = str_to_var(f.get_line())
	if not (head is Dictionary) or int(head.get("v", -1)) != RUN_SAVE_VERSION:
		# the sim moved under the log: replaying it would diverge silently, so
		# the save goes - but the player is told why their run vanished
		f.close()
		DirAccess.remove_absolute(RUN_SAVE_PATH)
		save_lost = true
		return
	var g = Game.new(int(head["seed"]), Dictionary(head["config"]))
	while not f.eof_reached() and not g.over:
		var line := f.get_line()
		if line.strip_edges() == "":
			continue
		var act = str_to_var(line)
		if act is Dictionary:
			g.step(act)
	f.close()
	if g.over:
		DirAccess.remove_absolute(RUN_SAVE_PATH)
		return
	game = g
	seed_v = int(head["seed"])
	run_tier = int(head.get("tier", 0))
	sel_tier = run_tier
	_game_is_run = true
	_run_recorded = false
	_run_unlocks = []
	mode = "normal"
	log_lines = []
	for ev in game.snapshot()["events"]:
		if String(ev.get("t", "")) == "draft_offer":
			_draft_focus_spent = bool(ev.get("focus", false))
		var s := _ev_text(ev)
		if s != "" and (log_lines.is_empty() or log_lines.back() != s):
			log_lines.append(s)
	_run_save = FileAccess.open(RUN_SAVE_PATH, FileAccess.READ_WRITE)
	if _run_save != null:
		_run_save.seek_end()


## Game-over site: the run's own record (Game.run_summary(), stamped with the
## tier and seed mode the shell chose) goes to the career profile - or to the
## daily board when the seed came from the daily challenge, since a daily
## scores its seed and unlocks nothing. Then the action log is closed and
## archived. Called once per run, from _act.
func _record_finished_run() -> void:
	_run_recorded = true
	var summary: Dictionary = game.run_summary()
	summary["tier"] = run_tier
	summary["seed_mode"] = seed_mode
	_run_unlocks = []
	if seed_mode == "daily":
		profile.record_daily(summary)
	else:
		var prev_ut: int = int(profile.unlocked_tier)
		_run_unlocks = profile.record_run(summary)
		if int(profile.unlocked_tier) > prev_ut:
			_run_unlocks.push_front("tier:%d" % int(profile.unlocked_tier))
	profile.save(PROFILE_PATH)
	if _run_save != null:
		_run_save.close()
		_run_save = null
	_archive_run()


## A finished run's action log is a replayable record, not litter: move it to
## runs_dir as run_<seed>_<yyyymmdd>_<won|died>.save and keep the newest
## RUNS_KEEP. tests/import_run.gd turns one into a regression pair.
func _archive_run() -> void:
	if not FileAccess.file_exists(RUN_SAVE_PATH):
		return
	var d := Time.get_date_dict_from_system()
	var outcome := "won" if (game != null and game.won) else "died"
	var dest := "%s/run_%d_%04d%02d%02d_%s.save" % [
		runs_dir, seed_v, int(d["year"]), int(d["month"]), int(d["day"]), outcome]
	DirAccess.make_dir_recursive_absolute(runs_dir)
	if FileAccess.file_exists(dest):
		DirAccess.remove_absolute(dest)  # same seed, same day: the newer log wins
	if DirAccess.rename_absolute(RUN_SAVE_PATH, dest) != OK:
		DirAccess.copy_absolute(RUN_SAVE_PATH, dest)
	DirAccess.remove_absolute(RUN_SAVE_PATH)  # no-op after a successful rename
	_prune_runs()


## Keep the newest RUNS_KEEP logs. Ordered by (modified time, name) so the
## sweep is deterministic even when several land in the same second.
func _prune_runs() -> void:
	var dir := DirAccess.open(runs_dir)
	if dir == null:
		return
	var keys: Array = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".save"):
			keys.append("%020d|%s" % [FileAccess.get_modified_time(runs_dir + "/" + name), name])
		name = dir.get_next()
	dir.list_dir_end()
	keys.sort()  # oldest first
	while keys.size() > RUNS_KEEP:
		var k := String(keys.pop_front())
		DirAccess.remove_absolute(runs_dir + "/" + k.substr(k.find("|") + 1))


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) == OK:
		hold_ms = int(cf.get_value("ui", "hold_ms", 420))
		seed_mode = String(cf.get_value("ui", "seed_mode", "random"))
		intro_mode = String(cf.get_value("ui", "intro_mode", "once"))
		sfx_on = bool(cf.get_value("ui", "sfx_on", true))
		music_on = bool(cf.get_value("ui", "music_on", true))
		sel_tier = int(cf.get_value("ui", "tier", 0))
		sel_loadout = String(cf.get_value("ui", "loadout", "tender"))
		sel_package = String(cf.get_value("ui", "package", ""))
		sel_mutator = String(cf.get_value("ui", "mutator", ""))


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("ui", "hold_ms", hold_ms)
	cf.set_value("ui", "seed_mode", seed_mode)
	cf.set_value("ui", "intro_mode", intro_mode)
	cf.set_value("ui", "sfx_on", sfx_on)
	cf.set_value("ui", "music_on", music_on)
	cf.set_value("ui", "tier", sel_tier)
	cf.set_value("ui", "loadout", sel_loadout)
	cf.set_value("ui", "package", sel_package)
	cf.set_value("ui", "mutator", sel_mutator)
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
		var tevs: Array = game.step(a)
		_arm_anim(prev, prev_floor)
		_spawn_fx(tevs, prev)
		_play_events(tevs)
		if advances:
			if st.get("until_dead", false):
				if _tut_cleared(st["until_dead"]):
					tut_step += 1
			else:
				tut_step += 1
			if tut_step >= Tutorial.STEPS.size():
				tut_done = true
		elif st.get("until_dead", false) and _tut_cleared(st["until_dead"]):
			tut_step += 1
			if tut_step >= Tutorial.STEPS.size():
				tut_done = true
		mode = "normal"
		mode_targets = []
		flash = ""
		tooltip = []
		queue_redraw()
		return
	# a purchase or a reroll made from the sheet reopens it
	var keep_shop := mode == "shop" and ["buy", "reroll"].has(String(a.get("type", "")))
	var evs: Array = game.step(a)
	if _game_is_run and _run_save != null:
		_run_save.store_line(var_to_str(a).replace("\n", " "))
		_run_save.flush()
	_arm_anim(prev, prev_floor)
	_spawn_fx(evs, prev)
	if game.over and _game_is_run and not _run_recorded:
		_record_finished_run()
	for ev in evs:
		if String(ev.get("t", "")) == "draft_offer":
			_draft_focus_spent = bool(ev.get("focus", false))
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
			"buy", "draft_upgrade", "item_pickup": id = "coin"
			"room_bloom": id = "heal"
			"stairs_awaken": id = "sparkle"
			"verdant": id = "sparkle"
			"seal_burst": id = "vent"
			"floor_restored": id = "heal"
			"item_use": id = "cast"
			"assimilate": id = "drag"
			"upcycle", "upcycle_ability": id = "sparkle"
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


## Turn a step's events into transient map effects: floating numbers over
## whoever was hit, white hit flashes, gold cleanse bursts, grey death puffs.
func _spawn_fx(evs: Array, prev: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	var stack := {}  # tile -> count, so numbers landing together fan out in time
	for ev in evs:
		match String(ev.get("t", "")):
			"damage":
				var p := _fx_pos(ev, prev)
				if p.x < -0.5:
					continue
				var k := str(p)
				stack[k] = int(stack.get(k, -1)) + 1
				var mine: bool = ev.get("who", "") == "player"
				_fx.append({"kind": "float", "pos": p, "text": "-%d" % int(ev["amt"]),
					"col": COL_RED if mine else COL_CREAM, "t0": now + int(stack[k]) * 110})
				_fx.append({"kind": "flash", "pos": p, "col": Color(1, 1, 1), "t0": now})
				if mine:
					_shake(2.0 + minf(float(int(ev["amt"])) * 1.2, 6.0))
			"heal":
				_fx.append({"kind": "float", "pos": Vector2(game.player["pos"]),
					"text": "+%d" % int(ev["amt"]), "col": Color("8fdc6a"), "t0": now})
			"shield":
				_fx.append({"kind": "float", "pos": Vector2(game.player["pos"]),
					"text": "shield", "col": Color("7fb6d9"), "t0": now})
			"cleanse":
				var cp := Vector2(ev["tile"])
				_fx.append({"kind": "burst", "pos": cp, "col": COL_GOLD, "t0": now})
				_fx.append({"kind": "float", "pos": cp, "text": "+%d" % int(ev.get("bloom", 1)),
					"col": COL_GOLD, "t0": now})
			"death":
				var dp := _fx_pos(ev, prev)
				if dp.x > -0.5:
					_fx.append({"kind": "puff", "pos": dp, "col": Color(0.62, 0.64, 0.66), "t0": now})
			"room_bloom":
				var bp := Vector2(game.player["pos"])
				_fx.append({"kind": "burst", "pos": bp, "col": Color(0.91, 0.70, 0.82), "t0": now})
				_fx.append({"kind": "float", "pos": bp, "text": "BLOOM +%d" % int(ev.get("bonus", 2)),
					"col": COL_GOLD, "t0": now + 120})
			"stairs_awaken":
				_banner = ["THE STAIRS AWAKEN"]
				_banner_ms = now
				if ev.has("tile"):
					_fx.append({"kind": "burst", "pos": Vector2(ev["tile"]), "col": COL_GOLD, "t0": now})
			"floor_restored":
				_banner = ["FLOOR RESTORED", "the skies clear"]
				_banner_ms = now
				_fx.append({"kind": "burst", "pos": Vector2(game.player["pos"]), "col": Color(0.6, 0.9, 0.5), "t0": now})
			"verdant":
				if ev.has("tile"):
					_fx.append({"kind": "burst", "pos": Vector2(ev["tile"]), "col": Color(0.55, 0.9, 0.45), "t0": now})
			"boss_phase", "ignite_all", "flood", "smoke_burst":
				_shake(9.0)
	if _fx.size() > 40:
		_fx = _fx.slice(_fx.size() - 40)


## Best-known tile for an event's subject: the player, a live enemy, or the
## pre-step position of something that just died.
func _fx_pos(ev: Dictionary, prev: Dictionary) -> Vector2:
	if ev.get("who", "") == "player":
		return Vector2(game.player["pos"])
	var id = ev.get("id", null)
	if id != null:
		for e in game.enemies:
			if e["id"] == id:
				return Vector2(e["pos"])
		if prev.has(id):
			return prev[id]
	return Vector2(-9, -9)


## Brief screen shake; magnitudes from concurrent hits keep the strongest.
func _shake(mag: float) -> void:
	if Time.get_ticks_msec() - _shake_ms > 320:
		_shake_mag = 0.0
	_shake_ms = Time.get_ticks_msec()
	_shake_mag = maxf(_shake_mag, mag)


## Tutorial until_dead condition: `true` waits for an empty floor, a String
## waits until no enemy of that kind remains (lets later steps keep their
## own target alive through earlier sandbox steps).
func _tut_cleared(cond) -> bool:
	if cond is String:
		for e in game.enemies:
			if String(e["kind"]) == String(cond):
				return false
		return true
	return game.enemies.is_empty()


func _arm_anim(prev: Dictionary, prev_floor: int) -> void:
	if game.floor_num != prev_floor:
		_anim_from = {}
		_fx = []
		_floor_fade_ms = Time.get_ticks_msec()
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

## Android's Back button and back gesture. project.godot sets
## application/config/quit_on_go_back to false - without it the OS kills the
## app on the first Back press, from any screen - so the whole rule lives here,
## and it is the SAME rule ESC follows: one step up one level. Nothing else in
## the shell may implement "back"; a second copy would drift from this one.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back(true)  # the menu is the root, and Android's root gesture quits


## Go UP one level, and return the level that was left (the return value is
## how a headless test can pin the root case without quitting the runner).
## Every modal state the shell can be in has exactly one way out and it is
## this function: ESC, the Back button and the sheets' own BACK/CLOSE buttons
## all end up here or in the tap tag it calls, so the touch build and the
## keyboard build can never disagree about what "back" means.
##
## `quit_at_root` is the one place the two callers differ. Back at the MENU is
## the root of the app and Android's convention is to leave it (the run, if
## any, is saved per action and RESUME restores it byte-exact), while ESC on a
## desktop has never quit from the menu and still does not.
func _back(quit_at_root: bool = false) -> String:
	# a held tooltip is drawn over everything, so it is what Back closes first
	if not tooltip.is_empty():
		tooltip = []
		tooltip_tile = Vector2i(-1, -1)
		# ...and the HOLD that raised it goes with it. _process re-shows a
		# tooltip for as long as _held is true and hold_ms has passed, so
		# clearing only the text let the very next frame put the same tooltip
		# back - and every Back after that was eaten by it in turn, for as
		# long as the finger (or the mouse button) stayed down. Dropping the
		# hold here is also what stops the eventual release from counting as a
		# tap: _unhandled_input only calls _click for a press SHORTER than
		# hold_ms, and this one is already longer.
		_held = false
		queue_redraw()
		return "tooltip"
	if screen == "menu":
		if mode == "settings":
			mode = "normal"
			queue_redraw()
			return "settings"
		if quit_at_root:
			_tap("quit")  # is_inside_tree-guarded, so a test can call it
			return "quit"
		return "root"
	if game == null or game.over or (screen == "tutorial" and tut_done):
		# the end-of-run sheet and the tutorial's last card are read-only: the
		# run is already recorded and archived, so there is nothing to lose
		_tap("menu")
		return "menu"
	var was := mode
	match was:
		"up_variant":
			_tap("forge_back")  # the fork sheet's own BACK: return to the scrap tap
			return was
		"up_scrap":
			mode = "up_keep"  # one tap back up the forge's three-tap choice
			mode_pick = -1
			flash = ""
			queue_redraw()
			return was
		"up_keep":
			# the forge was entered off the shrine sheet, so that is where
			# backing out of it lands - free, and the kit is untouched
			mode = "normal"
			flash = ""
			_tap("shop")
			queue_redraw()
			return was
		"draft_drop":
			_tap("draft_back")  # back to the offer cards, nothing picked
			return was
		"target_dir", "target_tile", "cleanse":
			_cancel_aim()
			return was
		"shop", "log", "help", "intro", "settings":
			mode = "normal"
			flash = ""
			queue_redraw()
			return was
	# mode is "normal" from here: no sheet is up
	if game.phase == "draft":
		# the draft is the sim's own phase, not a shell sheet - only a pick or
		# a skip closes it - so Back leaves for the menu; the run save carries
		# the pending draft and RESUME comes back to this same sheet
		_tap("menu")
		return "menu"
	if zoom_room:
		zoom_room = false  # back out to the whole-floor camera first
		queue_redraw()
		return "zoom"
	_tap("menu")
	return "menu"


## Drop a targeting mode without spending anything. Entering an aim costs
## nothing, so leaving one must cost nothing either: ESC, the Back button, a
## D-pad press and a second tap on the aiming slot all land here.
func _cancel_aim() -> void:
	mode = "normal"
	mode_targets = []
	mode_slot = -1
	flash = ""
	queue_redraw()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		_key(ev.keycode)
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_press_pos = ev.position
			_press_ms = Time.get_ticks_msec()
			_held = true
			queue_redraw()  # pressed-state shading on buttons
		else:
			var had_tip := not tooltip.is_empty() and not inspect_live
			_held = false
			if had_tip:
				tooltip = []
			elif Time.get_ticks_msec() - _press_ms < hold_ms:
				_click(ev.position)
			queue_redraw()
	elif ev is InputEventMouseMotion:
		if inspect_live and screen != "menu" and game != null and not game.over and mode == "normal":
			var t := _map_tile(ev.position)
			if t != tooltip_tile:
				_show_tooltip(ev.position)  # only replaces when there is something to say
		if _held and ev.position.distance_to(_press_pos) > 30.0:
			_held = false


func _process(_dt: float) -> void:
	if screen == "menu":
		queue_redraw()  # spores drift across the title vista
		return
	if _held and tooltip.is_empty() and Time.get_ticks_msec() - _press_ms >= hold_ms:
		_show_tooltip(_press_pos)
	var animating: bool = Time.get_ticks_msec() - _anim_ms < ANIM_MS + 40
	var smoggy: bool = game != null and not game.over and (int(game.smog) > 0 or int(game.dim) > 0)
	if not _fx.is_empty():
		var fnow := Time.get_ticks_msec()
		_fx = _fx.filter(func(f): return fnow - int(f["t0"]) < FX_MS)
		animating = true
	if Time.get_ticks_msec() - _floor_fade_ms < 1450:
		animating = true
	if Time.get_ticks_msec() - _banner_ms < 1650:
		animating = true
	if game != null and not game.over and int(game.player["hp"]) <= maxi(2, int(game.player["max_hp"]) / 4):
		animating = true  # danger vignette pulse
	if Time.get_ticks_msec() - _shake_ms < 360:
		animating = true
	if game != null and game.over:
		animating = true  # win/loss screens drift
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
		if hsp["rect"].has_point(pos) and String(hsp["tag"]).begins_with("item:"):
			var islot := int(String(hsp["tag"]).get_slice(":", 1))
			if islot < game.player["items"].size():
				var idef: Dictionary = Content.ITEMS[game.player["items"][islot]]
				tooltip = ["%s - tap to use (no turn)" % idef["name"], idef["desc"]]
				tooltip_tile = Vector2i(-1, -1)
				queue_redraw()
				return
		if hsp["rect"].has_point(pos) and String(hsp["tag"]).begins_with("ability:"):
			var slot := int(String(hsp["tag"]).get_slice(":", 1))
			var aid: String = game.player["kit"][slot]
			var adef: Dictionary = Content.ABILITIES[aid]
			var tc: int = game.ability_cost(aid)
			var thdr := "%s - %d charge" % [adef["name"], tc]
			# Game._surges, not a cost comparison: since Block D1 a surge may be a
			# STAT bump with no discount (Grow Spike +1 dmg, Water Jet +1 push) and
			# it still spends the tile - the old test said nothing about those
			if game._surges(adef):
				thdr += "  ·  surges, spends the tile"
			tooltip = [thdr, _ability_desc(aid)]
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
			if e["traits"].has("spiked") or e.get("elite", false):
				lines.append("SPIKED - melee costs you 1 HP")
			# what the row refuses to walk through, straight off the data
			var avoid: Array = Content.ENEMIES.get(e["kind"], {}).get("avoid", [])
			if not avoid.is_empty():
				lines.append("avoids: %s - detours, unless the way round is long" % ", ".join(avoid))
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
	# ESC is the keyboard's Back, and it is the SAME handler the Android Back
	# button uses (KEY_BACK is here too: some devices deliver the hardware
	# button as a key event rather than as the window notification).
	if k == KEY_ESCAPE or k == KEY_BACK:
		_back(k == KEY_BACK)
		return
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
			_buy("ability")  # full kit: nothing to buy, just a flash
			return
		if mode == "shop" and k == KEY_G:
			_buy_graft(0)
			return
		if mode == "shop" and k == KEY_J:
			_buy_graft(1)  # the shrine offers two grafts; J takes the second
			return
		if mode == "shop" and k == KEY_R:
			_reroll()  # inside the sheet R redraws the counter, outside it restarts
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
		"target_tile":
			# a tile aim cannot be aimed with a direction, and falling through
			# to _move_or_strike here MOVED the tender - and struck whatever
			# stood beside it - out of a mode the player was still in, with no
			# free way back on a touchscreen. Reaching for a direction means
			# "get me out of this": cancel, free, no turn, no strike.
			_cancel_aim()
			_flash("aim cancelled")
		"cleanse":
			_cleanse_at(game.player["pos"] + d)
		"up_keep", "up_scrap", "up_variant":
			# the forge's three taps are a modal choice, and the two selection
			# steps draw no sheet - so the D-pad is still on screen right
			# beside the SHRINE SHOP button the context line points at, and
			# falling through here MOVED the tender and struck whatever stood
			# next to it, for a charge and a turn, out of a choice the player
			# was still in. Same rule as a tile aim: reaching for a direction
			# in a modal state means "get me out of this", and it is free.
			_flash("finish the forge choice, or step back")
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
	var corrupt: bool = Content.is_corruption(kind)
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
		_flash(_cleanse_hint())


## Why CLEANSE just refused. "no corruption beside you" was the only answer,
## and it is a lie in the two cases that actually happen: the tender STANDING on
## the slick (cleanse reaches a neighbour, never the tile underfoot) and a slick
## the tender's own lance set alight (fire is not corruption until it burns down
## to ash). Both read as a dead end - the tutorial's last cleanse step allows no
## ability, so a player told there is nothing there has nothing left to try.
func _cleanse_hint() -> String:
	if game == null:
		return "no corruption beside you"
	var here := String(game.terrain.get(game.player["pos"], {}).get("kind", ""))
	if Content.is_corruption(here):
		return "you're standing on it - step off first"
	for d in DIRS4.values():
		if String(game.terrain.get(game.player["pos"] + d, {}).get("kind", "")) == "fire":
			return "still burning - wait for the ash"
	return "no corruption beside you"


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


## Buy heal / ability / item. A full kit has no room for the ability card:
## the sim stops offering it, so the tap just says so.
func _buy(item: String) -> void:
	for a in _legal_of("buy"):
		if String(a.get("item", "")) != item:
			continue
		_act(a)
		return
	_flash("can't buy that")


## The shrine offers two grafts and sells one; `pick` indexes shop.grafts.
func _buy_graft(pick: int) -> void:
	for a in _legal_of("buy"):
		if String(a.get("item", "")) == "graft" and int(a.get("pick", -1)) == pick:
			_act(a)
			return
	_flash("can't buy that")


## Redraw the shrine counter (Block D2). Every rule - on the shrine, a
## re-drawable slot still stocked, the per-floor cap, the escalating price -
## is the sim's, so the shell just looks for the action and flashes when the
## card is dead.
func _reroll() -> void:
	for a in _legal_of("reroll"):
		_act(a)
		return
	_flash("can't reroll")


## The one bit of ability metadata the shell reads, mirroring the sim rule:
## a mobility ability is never a legal forge scrap (sim/game.gd _is_mobility).
func _is_mobility(aid: String) -> bool:
	return String(Content.ABILITIES.get(aid, {}).get("role", "")) == "mobility"


## The legal forge actions for one (keep, scrap) pair, in legal_actions order -
## which is Content.variants_of order, so entry 0 is always the variant that
## reproduces the pre-Block-D6 "+" row. Straight off the sim: the shell never
## builds a forge the sim would reject, and never names a variant id itself.
func _forge_actions(keep: int, scrap: int) -> Array:
	var out: Array = []
	for a in _legal_of("upcycle_ability"):
		if int(a.get("keep", -1)) == keep and int(a.get("scrap", -1)) == scrap:
			out.append(a)
	return out


func _ability_press(slot: int) -> void:
	if slot >= game.player["kit"].size():
		return
	# toggle: tapping the slot you are already aiming with puts the aim down.
	# No new button, and it is where the finger already is - the aim was armed
	# from this same slot. Tapping a DIFFERENT slot still switches aim.
	if (mode == "target_dir" or mode == "target_tile") and mode_slot == slot:
		_cancel_aim()
		_flash("aim cancelled")
		return
	if mode == "up_variant":
		# the forge's fork sheet owns the screen: keep and scrap are already
		# chosen, so a kit tap here would silently cast instead
		_flash("pick which way it grows, or BACK")
		return
	if mode == "up_keep":
		var can_keep := false
		for a in _legal_of("upcycle_ability"):
			if int(a.get("keep", -1)) == slot:
				can_keep = true
				break
		if not can_keep:
			_flash("that one can't be forged further")
			return
		mode_pick = slot
		mode = "up_scrap"
		queue_redraw()
		return
	if mode == "up_scrap":
		if slot == mode_pick:
			_flash("pick a DIFFERENT one to scrap")
			return
		# Block D6: the sim lists one forge action per (keep, scrap, VARIANT)
		# triple, so a forked base offers two. One match acts at once (a package
		# ability has a single "+" form); two or more open the fork sheet.
		var acts_v := _forge_actions(mode_pick, slot)
		if acts_v.size() == 1:
			_act(acts_v[0])
			return
		if acts_v.size() > 1:
			mode_scrap = slot
			mode = "up_variant"
			flash = ""
			queue_redraw()
			return
		if _is_mobility(String(game.player["kit"][slot])):
			_flash("can't scrap your mobility ability")
		else:
			_flash("can't scrap that")
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
		# the flash names the way OUT as well as the way in: on a phone there
		# is no ESC key, so the cancel has to be written on the screen
		_flash("AIM %s: D-pad or tap beside you  ·  slot cancels" % Content.ABILITIES[aid]["name"])
	elif acts.size() == 1:
		_act(acts[0])
	else:
		mode = "target_tile"
		mode_slot = slot
		mode_targets = []
		for a in acts:
			mode_targets.append(a["target"])
		_flash("AIM %s: tap a green tile  ·  D-pad or slot cancels" % Content.ABILITIES[aid]["name"])
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
	elif tag.begins_with("item:"):
		var islot := int(tag.get_slice(":", 1))
		if islot < game.player["items"].size():
			_act({"type": "use_item", "slot": islot})
	elif tag.begins_with("buy:graft:"):
		_buy_graft(int(tag.get_slice(":", 2)))
	elif tag.begins_with("buy:"):
		_buy(tag.get_slice(":", 1))
	elif tag.begins_with("upcycle:"):
		var keep := int(tag.get_slice(":", 1))
		var pressed := false
		for a in _legal_of("upcycle"):
			if int(a.get("keep", -1)) == keep:
				_act(a)
				pressed = true
				break
		if not pressed:
			_flash("the press is closed")
	elif tag == "reroll":
		_reroll()
	elif tag.begins_with("forgevar:"):
		var vi := int(tag.get_slice(":", 1))
		var picked := false
		for a in _forge_actions(mode_pick, mode_scrap):
			if int(a.get("variant", 0)) == vi:
				_act(a)
				picked = true
				break
		if not picked:
			_flash("the forge is cold")
			mode = "normal"
			queue_redraw()
	elif tag == "forge_back":
		mode = "up_scrap"
		flash = ""
		queue_redraw()
	elif tag == "forge":
		if _legal_of("upcycle_ability").is_empty():
			_flash("the forge is cold")
		else:
			mode = "up_keep"
			flash = ""
			queue_redraw()
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
				if Content.is_corruption(String(game.terrain.get(game.player["pos"] + d, {}).get("kind", ""))):
					can = true
					break
		if can:
			mode = "cleanse"
			queue_redraw()
		else:
			_flash(_cleanse_hint())
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
		if (game == null or not _game_is_run or game.over) and FileAccess.file_exists(RUN_SAVE_PATH):
			_load_run()  # the live run was displaced (e.g. by the tutorial)
		if game != null and not game.over and _game_is_run:
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
			"tier":
				sel_tier = (sel_tier + 1) % (_max_tier() + 1)
			"loadout":
				sel_loadout = String(_cycle(profile.available_loadouts(), sel_loadout))
			"package":
				sel_package = String(_cycle(_with_none(profile.unlocked_packages), sel_package))
			"mutator":
				sel_mutator = String(_cycle(_with_none(profile.unlocked_mutators), sel_mutator))
			"hold":
				hold_ms = {300: 420, 420: 650, 650: 300}.get(hold_ms, 420)
			"seed":
				seed_mode = "daily" if seed_mode == "random" else "random"
			"intro":
				intro_mode = {"once": "always", "always": "never", "never": "once"}.get(intro_mode, "once")
		_save_settings()
		queue_redraw()


## The entry after `cur` in `opts`, wrapping round; the first entry when `cur`
## has fallen out of the list (an unlock the career no longer has).
static func _cycle(opts: Array, cur):
	if opts.is_empty():
		return cur
	return opts[(opts.find(cur) + 1) % opts.size()]


## `ids` with the "none" choice ("") in front - the package and mutator rows
## always offer opting out.
static func _with_none(ids: Array) -> Array:
	var out: Array = [""]
	out.append_array(ids)
	return out


## Display name for a run choice: loadouts and mutators carry one in Content,
## a package is just its id, and "" is the opted-out row.
static func _choice_name(kind: String, id: String) -> String:
	if id == "":
		return "none"
	match kind:
		"loadout":
			return String(Content.LOADOUTS[id]["name"]) if Content.LOADOUTS.has(id) else id
		"mutator":
			return String(Content.MUTATORS[id]["name"]) if Content.MUTATORS.has(id) else id
	return id.capitalize()


## The title screen's row stack as data: [label, tap tag, highlighted]. A row
## with an empty tag is a line of text, not a button (the daily config line).
## Built here so a headless test can read exactly what the menu offers.
func _menu_rows() -> Array:
	var rows: Array = []
	var has_resume: bool = (game != null and not game.over and _game_is_run) \
		or FileAccess.file_exists(RUN_SAVE_PATH)
	if has_resume:
		rows.append(["RESUME RUN", "resume", true])
	rows.append(["PLAY", "play", true])
	if int(profile.unlocked_tier) > 0:
		var tn := "base run" if sel_tier == 0 else String(Content.TIERS[sel_tier - 1]["name"])
		rows.append(["DIFFICULTY %d: %s" % [sel_tier, tn], "set:tier", false])
	if seed_mode == "daily":
		# a daily's loadout, package and mutator come from the seed, not from
		# the menu: one line saying what today hands everyone
		var d: Dictionary = Profile.daily_config(_daily_seed())
		rows.append(["TODAY: %s · %s · %s" % [
			_choice_name("loadout", String(d["loadout"])),
			_choice_name("package", String(d["package"])),
			_choice_name("mutator", String(d["mutator"]))], "", false])
	else:
		rows.append(["LOADOUT: %s" % _choice_name("loadout", sel_loadout), "set:loadout", false])
		rows.append(["PACKAGE: %s" % _choice_name("package", sel_package), "set:package", false])
		rows.append(["MUTATOR: %s" % _choice_name("mutator", sel_mutator), "set:mutator", false])
	rows.append(["TUTORIAL", "tutorial", false])
	rows.append(["SETTINGS", "settings", false])
	rows.append(["QUIT", "quit", false])
	return rows


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


## The name of the enemy an event names by id (the screen event reports the
## enemy, not its kind); "Something" if it has already left the board.
func _ename_by_id(id) -> String:
	for e in game.enemies:
		if e["id"] == id:
			return _ename(String(e["kind"]))
	return "Something"


## What a screened intent is called in the log. The raw type is the fallback,
## so a new Content.SCREENED_INTENTS entry still reads as a sentence.
func _screen_word(itype: String) -> String:
	match itype:
		"gum": return "tar"
		"drain": return "drain"
		"drag": return "grapple"
	return itype


## Purchase ids in words for the log ("bloom_surge" -> "Bloom Surge").
func _shop_name(item: String, id: String) -> String:
	match item:
		"heal":
			return "a heal"
		"graft":
			return String(Content.GRAFTS.get(id, {}).get("name", id))
		"ability":
			return String(Content.ABILITIES.get(id, {}).get("name", id))
		"item":
			return String(Content.ITEMS.get(id, {}).get("name", id))
	return id if id != "" else item


func _ev_text(ev: Dictionary) -> String:
	match String(ev.get("t", "")):
		"damage":
			if ev.get("who", "") == "player":
				# defensive: qualified sources ("fire:solar_lance") read as "fire"
				var src := String(ev.get("src", "?"))
				var ci := src.find(":")
				return "You take %d dmg (%s)" % [ev["amt"], src.substr(0, ci) if ci >= 0 else src]
			return "%s takes %d" % [_ename(ev["who"]), ev["amt"]]
		"death":
			return "%s destroyed" % _ename(ev["who"])
		"player_death":
			return "You die (%s)" % ev.get("cause", "?")
		"heal":
			return "Growth heals you +%d" % ev["amt"]
		"cleanse":
			return "Cleansed +bloom - the air thins"
		"room_bloom":
			return "Room BLOOMS - +%d bloom and a supply pod" % ev.get("bonus", 2)
		"item_pickup":
			return "Picked up %s" % Content.ITEMS[ev["id"]]["name"]
		"item_use":
			return "%s used" % Content.ITEMS[ev["id"]]["name"]
		"satchel_full":
			return "Satchel full (2 slots)"
		"stairs_dormant":
			return "Stairs dormant - green the floor (%d/%d)" % [ev.get("have", 0), ev.get("need", 0)]
		"stairs_awaken":
			return "The floor greens - THE STAIRS AWAKEN"
		"quota_reclamp":
			return "Corruption burned away - gate now needs %d" % ev.get("need", 0)
		"seal_burst":
			return "Overgrown vent chokes - spawn absorbed"
		"floor_restored":
			return "FLOOR RESTORED - skies clear (+%d bloom)" % ev.get("bonus", 5)
		"verdant":
			return "Verdant surge - the growth feeds your cast"
		"assimilate":
			return "The machines WELD into a hulk"
		"upcycle":
			return "Upcycled: %s" % Content.ITEMS[ev["id"]]["name"]
		"upcycle_ability":
			return "Forged %s" % Content.ABILITIES[ev["id"]]["name"]
		"upcycle_scrap":
			return "Scrapped %s for parts" % Content.ABILITIES[ev["id"]]["name"]
		"choke":
			return "The smog chokes you"
		"smog_dim":
			return "Skies dim - charge regen drops"
		"reinforcement":
			return "A vent releases a drill bot"
		"gummed":
			return "Tar gums up an ability"
		"screened":
			return "%s's %s is lost in the smoke" % [
				_ename_by_id(ev.get("id", -1)), _screen_word(String(ev.get("intent", "")))]
		"drain":
			return "Drone drains %d banked charge" % ev["amt"]
		"drag":
			return "You are dragged"
		"stoke":
			return "Smokestack thickens the smog"
		"boss_phase":
			return "BOSS PHASE %d" % ev["phase"]
		"vents_clogged":
			return "The boss clogs the vents with goo"
		"core_shielded":
			return "Core shielded - cleanse the corruption round it"
		"dredge":
			return "The Dredge eats %d growth and heals" % ev["tiles"]
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
			var what := _shop_name(String(ev.get("item", "")), String(ev.get("id", "")))
			if String(ev.get("discarded", "")) != "":
				return "Bought %s (discarded %s)" % [what, _shop_name("graft", String(ev["discarded"]))]
			return "Bought %s" % what
		"reroll":
			return "Rerolled (-%d bloom)" % int(ev.get("cost", 0))
		"draft_upgrade":
			return "Upgraded to %s" % str(ev["id"])
		"draft_skip":
			return "Skipped - next draft adds a focus offer"
		"shield":
			return "Shield up (%d)" % ev["total"]
		"thorns":
			return "Thorns up (%d dmg)" % ev["dmg"]
		"anchor":
			return "Anchored - drags can't move you"
		"undim":
			return "Air clears - regen recovers"
		"immune":
			return "The boss shrugs it off"
		"stunned":
			return "Enemy stunned"
		"staggered":
			return "Staggered - wind-up lost"
		"rooted":
			return "Enemy rooted in place"
		"resisted":
			return "Root cooldown - the snare slides off"
		"ash":
			return "The fire burns down to ash"
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
		"fuse":
			return "WELDING - kill or shove one of the pair"
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


## Greedy word wrap into at most `lines` lines of `max_w`, shrinking the font
## only when wrapping alone cannot do it. Returns {lines, size} so the caller
## draws at the size that actually fitted. _txt_fit is the one-line version and
## goes all the way down to 9px, which is what made a long card description
## unreadable on a phone; tests/test_shell.gd _check_card_text holds every
## shipped description to a size this can wrap without shrinking much.
func _wrap(s: String, size: int, max_w: float, lines: int) -> Dictionary:
	var words := s.split(" ", false)
	while size > 9:
		var out: Array = []
		var cur := ""
		for w in words:
			var test: String = String(w) if cur == "" else cur + " " + String(w)
			if font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
				cur = test
			else:
				if cur != "":
					out.append(cur)
				cur = String(w)
		if cur != "":
			out.append(cur)
		if out.size() <= lines:
			return {"lines": out, "size": size}
		size -= 1
	return {"lines": [s], "size": size}


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
	# pressed-state shading while a finger is down on this box
	if _held and r.has_point(_press_pos):
		draw_rect(r.grow(-2), Color(0, 0, 0, 0.22))


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
	elif mode == "up_variant":
		_draw_forge_variants(vw, vh)
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
	# painted vista: jade sky, a low sun, the dead combine's stacks on the
	# skyline, and the canopy reclaiming the valley beneath them
	var sh := vh * 0.42
	draw_rect(Rect2(0, 0, vw, sh), Color("233c37"))
	draw_rect(Rect2(0, sh * 0.35, vw, sh * 0.65), Color("2b4a40"))
	draw_rect(Rect2(0, sh * 0.62, vw, sh * 0.38), Color("35584a"))
	var tsec := Time.get_ticks_msec() / 1000.0
	var sun := Vector2(vw * 0.82, sh * 0.52)
	draw_circle(sun, vw * 0.13, Color(0.95, 0.88, 0.55, 0.10))
	draw_circle(sun, vw * 0.095, Color(0.95, 0.88, 0.55, 0.16))
	draw_circle(sun, vw * 0.062, Color("f2e4a0"))
	for spec in [[0.10, 0.30, 0.052], [0.175, 0.22, 0.040], [0.30, 0.34, 0.036]]:
		var stx: float = vw * spec[0]
		var sty: float = sh * spec[1]
		draw_rect(Rect2(stx, sty, vw * spec[2], sh * 0.67 - sty), Color("1d2b2c"))
		draw_rect(Rect2(stx - vw * 0.006, sty, vw * (spec[2] + 0.012), sh * 0.035), Color("182325"))
	for i in 3:
		var wob := sin(tsec * 0.8 + float(i) * 1.9)
		draw_circle(Vector2(vw * (0.196 + 0.012 * wob), sh * (0.17 - 0.045 * float(i))),
			vw * (0.010 + 0.006 * float(i)), Color(0.52, 0.46, 0.4, 0.12))
	for spec2 in [[0.12, 0.86, 0.30, Color("2e4632")], [0.46, 0.92, 0.34, Color("3a5a3c")],
			[0.82, 0.88, 0.28, Color("476b44")], [0.30, 1.02, 0.40, Color("31502f")],
			[0.68, 1.04, 0.42, Color("3c5f38")]]:
		draw_circle(Vector2(vw * spec2[0], sh * spec2[1]), vw * spec2[2], spec2[3])
	for i in 14:
		var hsh := i * 2654435761
		draw_circle(Vector2(vw * (0.04 + 0.92 * float(hsh % 97) / 97.0),
			sh * (0.72 + 0.24 * float(hsh % 53) / 53.0)), vw * 0.006, Color(0.55, 0.72, 0.45, 0.5))
	draw_rect(Rect2(0, sh, vw, vh - sh), COL_BG)
	var fade_top := sh - vh * 0.05
	draw_polygon(
		PackedVector2Array([Vector2(0, fade_top), Vector2(vw, fade_top), Vector2(vw, sh), Vector2(0, sh)]),
		PackedColorArray([Color(COL_BG, 0.0), Color(COL_BG, 0.0), Color(COL_BG, 1.0), Color(COL_BG, 1.0)]))
	for i in 12:
		var ph := float(i) * 0.83
		var rise := fposmod(tsec * (0.03 + 0.015 * float(i % 3)) + ph, 1.0)
		draw_circle(Vector2(vw * fposmod(ph * 0.41 + sin(tsec * 0.4 + ph) * 0.02, 1.0), sh * (1.0 - rise)),
			vw * (0.0035 + 0.002 * float(i % 2)), Color(0.93, 0.90, 0.70, 0.35 * (1.0 - rise)))
	# the tender stands on the ridge, growth at their feet
	var big := vh * 0.085
	var tx := Art.tex("player", int(big))
	if tx != null:
		draw_texture(tx, Vector2(vw / 2.0 - big / 2.0, sh * 0.62 - big * 0.9))
	var small := vh * 0.038
	for spec3 in [["growth", -0.17], ["growth", 0.13]]:
		var t2 := Art.tex(String(spec3[0]), int(small))
		if t2 != null:
			draw_texture(t2, Vector2(vw / 2.0 + vw * spec3[1], sh * 0.62 - small * 0.9), Color(1, 1, 1, 0.9))
	_txt_c(vw / 2.0 + 2, vh * 0.155 + 2, "T E N D E R", Color(0, 0, 0, 0.55), int(vh * 0.065))
	_txt_c(vw / 2.0, vh * 0.155, "T E N D E R", COL_GOLD, int(vh * 0.065))
	_txt_c(vw / 2.0, vh * 0.195, "a solarpunk roguelike", COL_CREAM, int(vh * 0.021))
	if save_lost:
		# review §6.0: a version bump used to eat the run without a word
		_txt_c_fit(vw / 2.0, vh * 0.228, "your saved run was lost to an update",
			COL_GOLD, int(vh * 0.019), vw * 0.9)

	var bw := vw * 0.62
	var bx := (vw - bw) / 2.0
	# build the row list first, then size the stack to the space above the footer
	_clamp_selection()
	var rows: Array = _menu_rows()
	var top := vh * 0.46
	var bottom := vh * 0.935
	var gap := vh * 0.016
	var bh := minf(vh * 0.072, (bottom - top - gap * (rows.size() - 1)) / rows.size())
	var y := top + (bottom - top - (bh * rows.size() + gap * (rows.size() - 1))) / 2.0
	for row in rows:
		if String(row[1]) == "":
			_txt_c_fit(vw / 2.0, y + bh * 0.66, String(row[0]), COL_CREAM, int(bh * 0.30), bw)
		else:
			_button(Rect2(bx, y, bw, bh), String(row[0]), String(row[1]), int(bh * 0.38),
				COL_GOLD if bool(row[2]) else COL_DIM_TEXT)
		y += bh + gap
	var career := "%s seed" % seed_mode
	if int(profile.runs) > 0:
		career += "  ·  runs %d · wins %d · best %d" % [profile.runs, profile.wins, profile.best_floor]
	_txt_c_fit(vw / 2.0, vh * 0.972, career, COL_DIM_TEXT, int(vh * 0.016), vw * 0.92)


func _draw_settings(vw: float, vh: float) -> void:
	hotspots.clear()
	var y := _sheet(vw, vh, "SETTINGS")
	var bw := vw * 0.88
	var bh := vh * 0.08
	var names := {300: "short", 420: "normal", 650: "long"}
	_button(Rect2(vw * 0.06, y, bw, bh), "Hold delay:  %s" % names.get(hold_ms, "normal"), "set:hold", int(bh * 0.3))
	y += bh + vh * 0.025
	_button(Rect2(vw * 0.06, y, bw, bh), "Run seed:  %s" % ("random every run" if seed_mode == "random" else "daily (same for all)"), "set:seed", int(bh * 0.28))
	y += bh + vh * 0.025
	_button(Rect2(vw * 0.06, y, bw, bh), "Intro tips:  %s" % intro_mode, "set:intro", int(bh * 0.3))
	y += bh + vh * 0.025
	_button(Rect2(vw * 0.06, y, bw, bh), "Sound effects:  %s" % ("on" if sfx_on else "off"), "set:sfx", int(bh * 0.3))
	y += bh + vh * 0.025
	_button(Rect2(vw * 0.06, y, bw, bh), "Music:  %s" % ("on" if music_on else "off"), "set:music", int(bh * 0.3))
	y += bh + vh * 0.03
	# the globalized path is absolute, so the whole line used to shrink to the
	# 9px _fit_size floor whatever the label said - the tail is the useful half
	var rp := ProjectSettings.globalize_path(runs_dir)
	var rparts := rp.split("/", false)
	if rparts.size() > 2:
		rp = ".../%s/%s" % [rparts[rparts.size() - 2], rparts[rparts.size() - 1]]
	_txt_fit(Vector2(vw * 0.06, y + vh * 0.02), "runs saved to %s" % rp,
		COL_DIM_TEXT, int(vh * 0.018), bw)
	y += vh * 0.05
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


## Block D5 resonance readout, one entry per Content.RESONANCES row in table
## order: {id, name, desc, tag, need, count, active}. A resonance is free,
## permanent and automatic, so the player has to be able to SEE the counts and
## the thresholds - "fire 2 of 3" - or the whole element is invisible until it
## silently starts working.
##
## `active` is read from snapshot()["resonances"], the sim's own derived
## answer; only `count` is computed here, over the same two sources the sim
## counts (the kit rows' tags and the held grafts' tags), so the shell never
## re-implements the threshold rule - it only shows how far along the count is.
## A variant row carries its base's tags verbatim, so the row is read straight
## with the base row as the fallback.
func _resonance_state(snap: Dictionary) -> Array:
	var pl: Dictionary = snap["player"]
	var counts := {}
	for aid in pl["kit"]:
		var row: Dictionary = Content.ABILITIES.get(String(aid),
			Content.ABILITIES.get(Content.base_id(String(aid)), {}))
		for tag in row.get("tags", []):
			counts[tag] = int(counts.get(tag, 0)) + 1
	for gid in pl.get("grafts", []):
		for tag in Content.GRAFTS.get(String(gid), {}).get("tags", []):
			counts[tag] = int(counts.get(tag, 0)) + 1
	var active: Array = snap.get("resonances", [])
	var out: Array = []
	for rid in Content.RESONANCES:
		var r: Dictionary = Content.RESONANCES[rid]
		out.append({
			"id": String(rid), "name": String(r["name"]), "desc": String(r["desc"]),
			"tag": String(r["tag"]), "need": int(r["need"]),
			"count": int(counts.get(String(r["tag"]), 0)), "active": active.has(String(rid)),
		})
	return out


## The elements strip under the skies bar: every resonance the run has any
## claim on. A lit row reads "FIRE 3/3 Cinder Grip"; a row one card short reads
## "fire 2/3 Cinder Grip", which is the state the player has to be able to see
## to aim a draft at it. Rows the run holds nothing for are dropped, so an
## empty strip costs no space at all - and with fire the only element that
## ships a row, that IS a state a run reaches: a kit holding neither fire card
## draws no strip until it drafts one or buys a fire graft.
func _resonance_line(snap: Dictionary) -> String:
	var parts: Array = []
	for r in _resonance_state(snap):
		if int(r["count"]) <= 0:
			continue
		var tag := String(r["tag"])
		parts.append("%s %d/%d %s" % [
			tag.to_upper() if r["active"] else tag, r["count"], r["need"], r["name"]])
	return " · ".join(parts)


## The one-clause note a card earns from the resonance table: what taking it
## (or, with `losing` set, dropping it) does to an element. "" when the card
## touches no resonance tag - most cards, most of the time.
##   +fire 3/3 - lights Cinder Grip     the card that crosses the threshold
##   +fire 3/3 - would light Cinder Grip  the same, but the kit is full and
##                                        the drop is not chosen yet
##   +fire 2/3 Cinder Grip              progress toward one
##   BREAKS Cinder Grip (fire 2/3)      a drop that puts a lit row out
##
## A draft on a FULL kit is a SWAP, so neither half of it can be read off one
## card. `swap_tags` carries the tags of the OTHER card in the swap and the
## arithmetic nets both sides - the same sum bots/optimizer.gd
## _drop_breaks_resonance does. Without it the drop sheet badges BREAKS on a
## same-element swap (drop one growth card, take another: the count never
## moves). It is only ever known on the drop sheet, where the pick is already
## made; on the offer sheet the drop is still unchosen, so a card that would
## cross a threshold says "would light" and leaves the arithmetic to the
## sheet that has both halves.
func _resonance_note(snap: Dictionary, tags: Array, losing: bool,
		swap_tags: Array = [], unresolved_swap: bool = false) -> String:
	var parts: Array = []
	for r in _resonance_state(snap):
		var tag := String(r["tag"])
		if not tags.has(tag):
			continue
		var need := int(r["need"])
		var n: int = int(r["count"]) + (-1 if losing else 1)
		if swap_tags.has(tag):
			n += 1 if losing else -1
		if losing:
			if bool(r["active"]) and n < need:
				parts.append("%s out (%s %d/%d)" % [r["name"], tag, n, need])
		elif bool(r["active"]):
			continue  # already lit; a fourth fire card buys nothing
		elif n >= need:
			parts.append("+%s %d/%d %s %s" % [
				tag, n, need, "would light" if unresolved_swap else "lights", r["name"]])
		else:
			parts.append("+%s %d/%d %s" % [tag, n, need, r["name"]])
	return "  ·  ".join(parts)


## Tags of an ability id: its own row, the base row as the fallback (a Block D6
## variant carries its base's tags verbatim, so the two agree).
func _ability_tags(aid: String) -> Array:
	return Content.ABILITIES.get(aid, Content.ABILITIES.get(Content.base_id(aid), {})).get("tags", [])


## The run's config in one line, from the sim's own snapshot: which loadout is
## being played, then the package and the mutator that shaped the run. Drawn
## under the skies bar so what a run is set to is never a mystery mid-floor.
func _config_line(snap: Dictionary) -> String:
	var parts: Array = [_choice_name("loadout", String(snap.get("loadout", "tender")))]
	for pkg in snap.get("packages", []):
		parts.append(_choice_name("package", String(pkg)))
	for m in snap.get("mutators", []):
		parts.append(_choice_name("mutator", String(m)))
	return " · ".join(parts)


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
	_txt_fit(Vector2(mx + vw * 0.075, y2 + mh + vh * 0.0155), _config_line(snap),
		COL_DIM_TEXT, int(vh * 0.0125), vw * 0.55)
	draw_rect(Rect2(mx, y2, mw, mh), Color("6fae9c"))
	draw_rect(Rect2(mx, y2, mw, mh * 0.45), Color("8cc7ae"))
	draw_circle(Vector2(mx + mw * 0.93, y2 + mh * 0.42), mh * 0.30, Color("f2e4a0"))
	var sw := mw * frac
	if sw > 0.5:
		var tsec := Time.get_ticks_msec() / 1000.0
		var scol := Color("453b33")
		draw_rect(Rect2(mx, y2, sw, mh), scol)
		for i in 3:
			var br := mh * (0.42 + 0.16 * float(i % 2))
			var bx := sw + mx + sin(tsec * (1.1 + float(i) * 0.7) + float(i) * 2.1) * mh * 0.22
			var by := y2 + mh * (0.22 + 0.28 * float(i))
			draw_circle(Vector2(bx, by), br, scol)
			draw_circle(Vector2(bx - br * 0.7, by - mh * 0.1), br * 0.7, Color("564839"))
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
	# the floor and green readouts are RIGHT-aligned, so they have to be measured
	# before "! INCOMING" is drawn - it used to start at a fixed x with no width
	# budget at all and ran straight through them (~280px of overlap at
	# 1080x2400, on the one line that is telling you something is about to hit)
	var fl := "floor %d/7" % snap["floor"]
	var fsz := int(vh * 0.02)
	var fw := font.get_string_size(fl, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	_txt(Vector2(vw - fw - vw * 0.025, y2 + mh), fl, COL_GOLD, fsz)
	var right_edge := vw - fw - vw * 0.045
	if int(snap["green_need"]) > 0:
		var gl := "green %d/%d" % [snap["greened"], snap["green_need"]]
		var done: bool = int(snap["greened"]) >= int(snap["green_need"])
		var gw := font.get_string_size(gl, HORIZONTAL_ALIGNMENT_LEFT, -1, int(vh * 0.016)).x
		_txt(Vector2(vw - fw - gw - vw * 0.055, y2 + mh), gl,
			Color(0.6, 0.85, 0.55) if not done else COL_DIM_TEXT, int(vh * 0.016))
		right_edge = vw - fw - gw - vw * 0.075
	if _threat_tiles(snap).has(pl["pos"]):
		var ix := mx + mw + vw * 0.02
		_txt_fit(Vector2(ix, y2 + mh), "! INCOMING", COL_RED, int(vh * 0.021),
			maxf(right_edge - ix, vw * 0.06))
	_status_end = pad + row_h * 1.35 + mh + vh * 0.022
	# Block D5: the elements strip, drawn under the config line - a lit tag in
	# caps, a tag still short of its threshold in lower case with its count.
	# Nothing is drawn (and no space is taken) while the run holds no card of
	# any resonating element.
	var rline := _resonance_line(snap)
	if rline != "":
		_txt(Vector2(mx, y2 + mh + vh * 0.031), "ELEMENTS", COL_DIM_TEXT, int(vh * 0.0125))
		_txt_fit(Vector2(mx + vw * 0.075, y2 + mh + vh * 0.031), rline,
			COL_GOLD if not snap.get("resonances", []).is_empty() else COL_DIM_TEXT,
			int(vh * 0.0125), vw * 0.85)
		_status_end += vh * 0.0155


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
	var sage := float(Time.get_ticks_msec() - _shake_ms) / 320.0
	if sage < 1.0:
		var amp := _shake_mag * (1.0 - sage)
		_mox += sin(float(Time.get_ticks_msec()) * 0.09) * amp
		_moy += cos(float(Time.get_ticks_msec()) * 0.115) * amp

	var pal: Dictionary = BIOME_PAL.get(
		String(game.floor_def(game.floor_num).get("biome", "strip_mine")), BIOME_PAL["strip_mine"])
	var brects: Array = []
	for ri in m.get("bloomed", []):
		brects.append(m["rooms"][ri])
	# the ground takes sides: corruption stains its neighbours dark
	var blight := {}
	for bt in snap["terrain"].keys():
		var bk := String(snap["terrain"][bt]["kind"])
		if Content.is_corruption(bk):
			blight[bt] = true
			for d in DIRS4.values():
				blight[bt + d] = true
	for y in range(_vy0, _vy1 + 1):
		for x in range(_vx0, _vx1 + 1):
			var p := Vector2i(x, y)
			var r := _tile_rect(p)
			if m["tiles"][y * w + x] == 1:
				draw_rect(r, pal["f1"] if (x + y) % 2 == 0 else pal["f2"])
				var hsh := (x * 73856093) ^ (y * 19349663)
				if hsh % 7 == 0:
					var ox := 0.2 + float(hsh % 5) * 0.13
					var oy := 0.25 + float(hsh % 3) * 0.2
					draw_circle(r.position + Vector2(_ts * ox, _ts * oy), _ts * 0.05, pal["s1"])
					draw_circle(r.position + Vector2(_ts * (ox + 0.11), _ts * (oy + 0.07)), _ts * 0.035, pal["s1"])
				elif hsh % 11 == 3:
					draw_circle(r.position + Vector2(_ts * 0.7, _ts * 0.6), _ts * 0.04, pal["s2"])
				if blight.has(p):
					var bx0 := 0.25 + float(hsh % 5) * 0.11
					var by0 := 0.3 + float(hsh % 3) * 0.18
					draw_circle(r.position + Vector2(_ts * bx0, _ts * by0), _ts * 0.16, Color(0.1, 0.08, 0.07, 0.22))
					draw_circle(r.position + Vector2(_ts * (bx0 + 0.3), _ts * (by0 + 0.2)), _ts * 0.10, Color(0.12, 0.08, 0.1, 0.20))
				for br in brects:
					if br.has_point(p):
						draw_rect(r, Color(0.45, 0.75, 0.38, 0.10))
						if hsh % 5 == 1:
							draw_circle(r.position + Vector2(_ts * (0.3 + float(hsh % 3) * 0.2), _ts * 0.42),
								_ts * 0.05, Color(0.91, 0.70, 0.82, 0.85))
							draw_circle(r.position + Vector2(_ts * (0.3 + float(hsh % 3) * 0.2), _ts * 0.42),
								_ts * 0.02, Color(0.95, 0.9, 0.55))
						break
			else:
				draw_rect(r, pal["w"])
				# highlight only exposed wall tops, not every wall row; walls
				# beside a bloomed room get overgrown instead
				var vine := false
				for br0 in brects:
					if br0.grow(1).has_point(p):
						vine = true
						break
				var wtc: Color = Color(0.33, 0.5, 0.3) if vine else pal["wt"]
				if y + 1 < h and m["tiles"][(y + 1) * w + x] == 1:
					draw_rect(Rect2(r.position + Vector2(0, _ts * 0.82), Vector2(_ts, _ts * 0.18)), wtc)
				if y > 0 and m["tiles"][(y - 1) * w + x] == 1:
					draw_rect(Rect2(r.position, Vector2(_ts, maxf(_ts * 0.1, 2))), wtc)

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
			var tk := String(snap["terrain"][t]["kind"])
			if tk == "fire":
				var fl := 0.14 + 0.09 * sin(Time.get_ticks_msec() / 130.0 + float(t.x * 3 + t.y * 5))
				draw_circle(_tile_rect(t).get_center(), _ts * 0.62, Color(0.95, 0.55, 0.2, fl))
			if tk == "growth":
				# alive: each plant sways on its own phase; some carry a flower
				var gph := float(t.x * 7 + t.y * 11)
				var ctr := _tile_rect(t).get_center()
				draw_set_transform(ctr, sin(Time.get_ticks_msec() / 900.0 + gph) * 0.055, Vector2.ONE)
				var gtx := Art.tex("growth", int(_ts))
				if gtx != null:
					draw_texture(gtx, Vector2(-_ts / 2.0, -_ts / 2.0))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				if ((t.x * 73856093) ^ (t.y * 19349663)) % 4 == 0:
					draw_circle(ctr + Vector2(_ts * 0.26, -_ts * 0.18), _ts * 0.055, Color(0.91, 0.70, 0.82))
					draw_circle(ctr + Vector2(_ts * 0.26, -_ts * 0.18), _ts * 0.022, Color(0.95, 0.9, 0.55))
			else:
				_sprite(tk, t)
			if Content.is_corruption(tk):
				var shm := 0.04 + 0.04 * sin(Time.get_ticks_msec() / 600.0 + float(t.x * 5 + t.y * 3))
				draw_circle(_tile_rect(t).get_center() + Vector2(-_ts * 0.15, -_ts * 0.1),
					_ts * 0.10, Color(0.62, 0.55, 0.68, shm))
				# filth exhales: a slow dark wisp curls up from the corruption
				var wph := fposmod(Time.get_ticks_msec() / 3000.0 + float(t.x * 11 + t.y * 5) * 0.23, 1.0)
				if wph < 0.45:
					draw_circle(_tile_rect(t).get_center() + Vector2(_ts * 0.12 * sin(wph * 11.0), -_ts * (0.15 + wph * 0.9)),
						_ts * (0.05 + wph * 0.09), Color(0.16, 0.12, 0.14, 0.4 * (1.0 - wph / 0.45)))
			elif tk == "growth":
				# life breathes: a warm mote drifts up from some plants
				if ((t.x * 40503) ^ (t.y * 76261)) % 3 == 0:
					var mph := fposmod(Time.get_ticks_msec() / 2600.0 + float(t.x * 3 + t.y * 13) * 0.37, 1.0)
					if mph < 0.6:
						draw_circle(_tile_rect(t).get_center() + Vector2(_ts * 0.14 * sin(mph * 8.0), -_ts * (0.1 + mph * 0.8)),
							_ts * 0.035, Color(0.95, 0.92, 0.65, 0.7 * (1.0 - mph / 0.6)))
	for v in m["vents"]:
		if _vis(v):
			_sprite("vent", v)
			if snap["terrain"].has(v) and String(snap["terrain"][v]["kind"]) == "growth":
				# sealed: the growth chokes the grate (drawn again over the vent)
				_sprite("growth", v)
				draw_rect(_tile_rect(v).grow(-2), Color(0.42, 0.72, 0.35, 0.85), false, 2.0)
				continue
			var vph := fposmod(Time.get_ticks_msec() / 2000.0 + float(v.x * 7 + v.y * 13) * 0.31, 1.0)
			if vph < 0.55:
				draw_circle(_tile_rect(v).get_center() + Vector2(_ts * 0.1 * sin(vph * 9.0), -_ts * (0.2 + vph * 0.8)),
					_ts * (0.06 + vph * 0.10), Color(0.58, 0.52, 0.46, 0.35 * (1.0 - vph / 0.55)))
	if m["stairs"] != Vector2i(-1, -1) and _vis(m["stairs"]):
		_sprite("stairs", m["stairs"])
		if int(snap["greened"]) < int(snap["green_need"]):
			# dormant: grey ring, vines creeping over the steps
			draw_rect(_tile_rect(m["stairs"]).grow(-1), Color(0.45, 0.5, 0.45, 0.8), false, 2.0)
			var sc := _tile_rect(m["stairs"]).position
			draw_arc(sc + Vector2(_ts * 0.25, _ts * 0.8), _ts * 0.18, PI, TAU, 6, Color(0.35, 0.55, 0.3), 2.0)
			draw_arc(sc + Vector2(_ts * 0.7, _ts * 0.65), _ts * 0.14, PI, TAU, 6, Color(0.35, 0.55, 0.3), 2.0)
		else:
			draw_rect(_tile_rect(m["stairs"]).grow(-1), COL_GOLD, false,
				2.2 + 1.2 * sin(Time.get_ticks_msec() / 400.0))
	if m["shrine"] != Vector2i(-1, -1) and _vis(m["shrine"]):
		_sprite("shrine", m["shrine"])
		var twk := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 350.0)
		draw_circle(_tile_rect(m["shrine"]).position + Vector2(_ts * 0.82, _ts * 0.18),
			_ts * 0.05, Color(0.95, 0.9, 0.6, 0.25 + 0.55 * twk))

	var thc := COL_THREAT
	thc.a = 0.22 + 0.12 * sin(Time.get_ticks_msec() / 240.0)
	for t in _threat_tiles(snap):
		if _vis(t):
			draw_rect(_tile_rect(t), thc)
	for e0 in snap["enemies"]:
		if String(e0["intent"].get("type", "")) != "fuse":
			continue
		for e1 in snap["enemies"]:
			if e1["id"] == e0["intent"].get("with", -1) and (_vis(e0["pos"]) or _vis(e1["pos"])):
				var wa := 0.5 + 0.4 * absf(sin(Time.get_ticks_msec() / 180.0))
				draw_line(_tile_rect(e0["pos"]).get_center(), _tile_rect(e1["pos"]).get_center(),
					Color(0.91, 0.45, 0.16, wa), 3.0)

	for e in snap["enemies"]:
		if not _vis(e["pos"]):
			continue
		var ap := _anim_pos(e["id"], e["pos"])
		_shadow_f(ap)
		_sprite_f(e["kind"], ap)
		var r := _tile_rect_f(ap)
		if e.get("elite", false):
			draw_rect(r.grow(-1), COL_GOLD, false, 2.0)
		if e["traits"].has("spiked") or e.get("elite", false):
			for sp in 4:
				var sang := TAU * float(sp) / 4.0 + PI / 4.0
				draw_circle(r.get_center() + Vector2(cos(sang), sin(sang)) * _ts * 0.44, _ts * 0.045, Color(0.75, 0.78, 0.8))
		var edef: Dictionary = Content.ENEMIES[e["kind"]]
		var maxhp: int = int(edef["hp"]) + (Content.ELITE_HP_BONUS if e.get("elite", false) else 0)
		if e["hp"] < maxhp or edef["traits"].has("boss"):
			var frac: float = clampf(float(e["hp"]) / maxf(1.0, float(maxhp)), 0.0, 1.0)
			draw_rect(Rect2(r.position + Vector2(2, -4), Vector2(_ts - 4, 3)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(r.position + Vector2(2, -4), Vector2((_ts - 4) * frac, 3)), COL_RED)

	var pap := _anim_pos("player", snap["player"]["pos"])
	_shadow_f(pap)
	var bob := pap + Vector2(0, -0.02 - 0.02 * sin(Time.get_ticks_msec() / 480.0))
	_sprite_f("player", bob)
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
			var hcol := Color(0.44, 0.38, 0.33, minf(0.035 * float(dimlvl), 0.11))
			if choked:
				hcol = Color(0.62, 0.42, 0.38, minf(0.045 * float(dimlvl), 0.13))
			draw_circle(Vector2(hx, hy), hr, hcol)

	# life returns: butterflies over bloomed rooms
	var lts := Time.get_ticks_msec() / 1000.0
	for bi in brects.size():
		var br2: Rect2i = brects[bi]
		for k in 2:
			var bph := float(bi * 13 + k * 7)
			var btx := float(br2.position.x) + (0.5 + 0.42 * sin(lts * 0.31 + bph)) * float(br2.size.x)
			var bty := float(br2.position.y) + (0.5 + 0.42 * sin(lts * 0.23 + bph * 1.7)) * float(br2.size.y)
			if not _vis(Vector2i(int(btx), int(bty))):
				continue
			var wingc := Vector2(_mox + btx * _ts, _moy + bty * _ts + sin(lts * 2.0 + bph) * _ts * 0.1)
			var flap := 0.3 + 0.7 * absf(sin(lts * 7.0 + bph))
			var bcol2 := Color(0.95, 0.75, 0.45, 0.95) if k == 0 else Color(0.91, 0.66, 0.80, 0.95)
			draw_circle(wingc + Vector2(-_ts * 0.055 * flap, 0), _ts * 0.045, bcol2)
			draw_circle(wingc + Vector2(_ts * 0.055 * flap, 0), _ts * 0.045, bcol2)
	# and fireflies drift once the skies dim - life glowing against the smog
	if int(snap["dim"]) >= 1 and not game.over:
		for i in 6:
			var fph := float(i) * 1.31
			var fx2 := _mox + (float(_vx0) + (0.5 + 0.46 * sin(lts * 0.17 + fph * 2.3)) * float(_vx1 - _vx0)) * _ts
			var fy2 := _moy + (float(_vy0) + (0.5 + 0.44 * sin(lts * 0.13 + fph * 1.4)) * float(_vy1 - _vy0)) * _ts
			var glow := 0.4 + 0.6 * absf(sin(lts * 1.1 + fph * 3.0))
			draw_circle(Vector2(fx2, fy2), _ts * 0.10, Color(0.95, 0.85, 0.4, 0.10 * glow))
			draw_circle(Vector2(fx2, fy2), _ts * 0.028, Color(0.98, 0.92, 0.6, 0.85 * glow))

	# transient combat feedback: flashes, bursts, puffs, floating numbers
	var fnow := Time.get_ticks_msec()
	for fx in _fx:
		var age := float(fnow - int(fx["t0"])) / FX_MS
		if age < 0.0 or age > 1.0:
			continue
		var fp: Vector2 = fx["pos"]
		if not _vis(Vector2i(int(fp.x), int(fp.y))):
			continue
		var fr := _tile_rect_f(fp)
		var c: Vector2 = fr.get_center()
		match String(fx["kind"]):
			"flash":
				if age < 0.35:
					draw_rect(fr, Color(1, 1, 1, 0.38 * (1.0 - age / 0.35)))
			"burst":
				var bcol: Color = fx["col"]
				bcol.a = 1.0 - age
				var rad := _ts * (0.25 + age * 0.55)
				for i in 6:
					var ang := TAU * float(i) / 6.0 + age * 1.8
					draw_circle(c + Vector2(cos(ang), sin(ang)) * rad, _ts * 0.06 * (1.0 - age * 0.5), bcol)
			"puff":
				var pcol: Color = fx["col"]
				pcol.a = 0.5 * (1.0 - age)
				draw_circle(c + Vector2(0, -_ts * age * 0.4), _ts * (0.2 + age * 0.35), pcol)
				draw_circle(c + Vector2(-_ts * 0.22, -_ts * age * 0.55), _ts * (0.12 + age * 0.25), pcol)
				draw_circle(c + Vector2(_ts * 0.2, -_ts * age * 0.3), _ts * (0.1 + age * 0.22), pcol)
			"float":
				var fcol: Color = fx["col"]
				fcol.a = 1.0 if age < 0.55 else 1.0 - (age - 0.55) / 0.45
				var fsz2 := int(_ts * 0.42)
				var s2 := String(fx["text"])
				var fy := fr.position.y - _ts * (0.15 + age * 0.75)
				var tw2 := font.get_string_size(s2, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz2).x
				draw_string(font, Vector2(c.x - tw2 / 2.0 + 1, fy + 1), s2, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz2, Color(0, 0, 0, fcol.a * 0.8))
				draw_string(font, Vector2(c.x - tw2 / 2.0, fy), s2, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz2, fcol)

	if mode == "target_tile":
		for t in mode_targets:
			if _vis(t):
				draw_rect(_tile_rect(t).grow(-1), COL_TARGET, false, 2.5)
	elif mode == "target_dir" or mode == "cleanse":
		for d in DIRS4.values():
			draw_rect(_tile_rect(snap["player"]["pos"] + d).grow(-1), COL_TARGET, false, 2.0)

	# soft vignette around the tile field for depth
	var mr := Rect2(_mox + _vx0 * _ts, _moy + _vy0 * _ts,
		float(_vx1 - _vx0 + 1) * _ts, float(_vy1 - _vy0 + 1) * _ts)
	var vd := _ts * 0.9
	var vc := Color(0, 0, 0, 0.28)
	var v0 := Color(0, 0, 0, 0.0)
	draw_polygon(PackedVector2Array([mr.position, Vector2(mr.position.x + vd, mr.position.y + vd),
		Vector2(mr.position.x + vd, mr.end.y - vd), Vector2(mr.position.x, mr.end.y)]),
		PackedColorArray([vc, v0, v0, vc]))
	draw_polygon(PackedVector2Array([Vector2(mr.end.x, mr.position.y), Vector2(mr.end.x - vd, mr.position.y + vd),
		Vector2(mr.end.x - vd, mr.end.y - vd), mr.end]),
		PackedColorArray([vc, v0, v0, vc]))
	draw_polygon(PackedVector2Array([mr.position, Vector2(mr.end.x, mr.position.y),
		Vector2(mr.end.x - vd, mr.position.y + vd), Vector2(mr.position.x + vd, mr.position.y + vd)]),
		PackedColorArray([vc, vc, v0, v0]))
	draw_polygon(PackedVector2Array([Vector2(mr.position.x, mr.end.y), Vector2(mr.position.x + vd, mr.end.y - vd),
		Vector2(mr.end.x - vd, mr.end.y - vd), mr.end]),
		PackedColorArray([vc, v0, v0, vc]))

	# boss banner: name and a real health bar across the top of the map
	for e in snap["enemies"]:
		var edef2: Dictionary = Content.ENEMIES[e["kind"]]
		if not edef2["traits"].has("boss"):
			continue
		var bw2 := vw * 0.88
		var bx2 := (vw - bw2) / 2.0
		var by2 := _status_end + vh * 0.030
		var bh2 := vh * 0.014
		var bfrac := clampf(float(e["hp"]) / maxf(1.0, float(edef2["hp"])), 0.0, 1.0)
		draw_rect(Rect2(bx2 - vw * 0.015, by2 - vh * 0.024, bw2 + vw * 0.03, bh2 + vh * 0.031), Color(0.03, 0.05, 0.04, 0.82))
		_txt(Vector2(bx2, by2 - vh * 0.006), String(edef2["name"]).to_upper(), COL_RED, int(vh * 0.017))
		var hps := "%d / %d" % [int(e["hp"]), int(edef2["hp"])]
		var hpw := font.get_string_size(hps, HORIZONTAL_ALIGNMENT_LEFT, -1, int(vh * 0.014)).x
		_txt(Vector2(bx2 + bw2 - hpw, by2 - vh * 0.006), hps, COL_TEXT, int(vh * 0.014))
		draw_rect(Rect2(bx2, by2, bw2, bh2), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bx2, by2, bw2 * bfrac, bh2), COL_RED)
		draw_rect(Rect2(bx2, by2, bw2, bh2), Color(0.9, 0.4, 0.3, 0.7), false, 1.5)
		break

	# danger vignette: the edges bleed red while the tender is nearly down
	var pl0: Dictionary = snap["player"]
	if int(pl0["hp"]) <= maxi(2, int(pl0["max_hp"]) / 4) and not game.over:
		var da := 0.10 + 0.07 * sin(Time.get_ticks_msec() / 300.0)
		var dc := Color(0.85, 0.2, 0.12, da)
		var d0 := Color(0.85, 0.2, 0.12, 0.0)
		var dd := _ts * 1.6
		draw_polygon(PackedVector2Array([mr.position, Vector2(mr.position.x + dd, mr.position.y + dd),
			Vector2(mr.position.x + dd, mr.end.y - dd), Vector2(mr.position.x, mr.end.y)]),
			PackedColorArray([dc, d0, d0, dc]))
		draw_polygon(PackedVector2Array([Vector2(mr.end.x, mr.position.y), Vector2(mr.end.x - dd, mr.position.y + dd),
			Vector2(mr.end.x - dd, mr.end.y - dd), mr.end]),
			PackedColorArray([dc, d0, d0, dc]))
		draw_polygon(PackedVector2Array([mr.position, Vector2(mr.end.x, mr.position.y),
			Vector2(mr.end.x - dd, mr.position.y + dd), Vector2(mr.position.x + dd, mr.position.y + dd)]),
			PackedColorArray([dc, dc, d0, d0]))
		draw_polygon(PackedVector2Array([Vector2(mr.position.x, mr.end.y), Vector2(mr.position.x + dd, mr.end.y - dd),
			Vector2(mr.end.x - dd, mr.end.y - dd), mr.end]),
			PackedColorArray([dc, d0, d0, dc]))

	# each new floor fades in from the dark of the descent
	var fage := float(Time.get_ticks_msec() - _floor_fade_ms) / 450.0
	if fage < 1.0:
		draw_rect(Rect2(0, _status_end, vw, vh * Z_MAP_END - _status_end),
			Color(0.02, 0.03, 0.03, 1.0 - maxf(fage, 0.0)))

	# and its name hangs over the map for a moment
	var spl := float(Time.get_ticks_msec() - _floor_fade_ms) / 1400.0
	if spl >= 0.0 and spl < 1.0:
		var sa := 1.0 if spl < 0.55 else 1.0 - (spl - 0.55) / 0.45
		var scy := (mr.position.y + mr.end.y) / 2.0
		var nm := String(snap["floor_name"]).to_upper()
		var nsz := int(vh * 0.032)
		_txt_c(vw / 2.0 + 2, scy + 2, nm, Color(0, 0, 0, 0.6 * sa), nsz)
		_txt_c(vw / 2.0, scy, nm, Color(COL_GOLD, sa), nsz)
		_txt_c(vw / 2.0, scy + vh * 0.028, "floor %d of 7" % snap["floor"], Color(COL_CREAM, sa * 0.85), int(vh * 0.018))
		_txt_c(vw / 2.0, scy + vh * 0.052, "cleanse %d to wake the stairs" % snap["green_need"],
			Color(0.6, 0.85, 0.55, sa * 0.9), int(vh * 0.016))

	# event banners (stairs awaken, floor restored)
	var bage := float(Time.get_ticks_msec() - _banner_ms) / 1600.0
	if bage >= 0.0 and bage < 1.0 and not _banner.is_empty():
		var ba := 1.0 if bage < 0.6 else 1.0 - (bage - 0.6) / 0.4
		var bcy := (mr.position.y + mr.end.y) / 2.0 - vh * 0.05
		_txt_c(vw / 2.0 + 2, bcy + 2, String(_banner[0]), Color(0, 0, 0, 0.6 * ba), int(vh * 0.03))
		_txt_c(vw / 2.0, bcy, String(_banner[0]), Color(COL_GOLD, ba), int(vh * 0.03))
		if _banner.size() > 1:
			_txt_c(vw / 2.0, bcy + vh * 0.026, String(_banner[1]), Color(COL_CREAM, ba * 0.9), int(vh * 0.017))


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
		var live_cost: int = game.ability_cost(aid)
		var verdant: bool = live_cost < int(adef["cost"])
		var usable: bool = int(pl["charge"]) >= live_cost and not pl["gummed"].has(i)
		var aiming: bool = (mode == "target_dir" or mode == "target_tile") and mode_slot == i
		_box(r, _sb_gold if aiming else _sb)
		var icon := _ability_icon(aid)
		var isz := int(b * 0.68)
		var tx := Art.tex(icon, isz)
		if tx != null:
			draw_texture(tx, r.position + Vector2((b - isz) / 2.0, b * 0.04), Color(1, 1, 1, 1.0 if usable else 0.32))
		# cost pips
		for c in live_cost:
			var pipc := COL_GOLD if usable else COL_DIM_TEXT
			if verdant:
				pipc = Color(0.55, 0.9, 0.45) if usable else Color(0.4, 0.55, 0.38)
			draw_circle(r.position + Vector2(b * 0.12 + c * b * 0.14, b * 0.88), b * 0.05, pipc)
		# Content.is_upgrade, never ends_with("+"): "solar_lance+noon" is an
		# upgrade and does not end in "+"
		if Content.is_upgrade(aid):
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
		# a touch build has no ESC key, so these name what a FINGER can tap:
		# the SHRINE SHOP button is still drawn beside the D-pad through both
		# selection steps (it is free, and it changes nothing), and the fork
		# sheet carries its own BACK. Android's Back button walks the same
		# steps (_back), one level per press.
		"up_keep":
			msg = "Tap the ability to grow  ·  SHRINE SHOP backs out"
			col = COL_GOLD
		"up_scrap":
			msg = "Tap the one to SCRAP  ·  SHRINE SHOP backs out"
			col = COL_GOLD
		"up_variant":
			msg = "Which way does it grow?  ·  BACK to redo the scrap"
			col = COL_GOLD
		"cleanse":
			msg = "Tap corruption beside you (or D-pad)"
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
				msg = "DESTROY THE BOSS  ·  tap for log"
			elif int(snap["greened"]) < int(snap["green_need"]):
				msg = "Stairs dormant - cleanse %d/%d to green the floor" % [snap["greened"], snap["green_need"]]
				col = Color(0.6, 0.85, 0.55)
			else:
				msg = "Reach the gold-ringed stairs  ·  tap for log"
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
	# the D-pad's empty top corners host the view toggles; the bottom corners
	# are the satchel - one-tap consumables (hold for what they do)
	_icon_button(Rect2(dx, dy, b, b), "ic_camera", "zoom", zoom_room)
	_icon_button(Rect2(dx + (b + gap) * 2, dy, b, b), "ic_lens", "inspect", inspect_live)
	var items: Array = game.player["items"]
	for i in 2:
		var ir := Rect2(dx + (b + gap) * 2 * i, dy + (b + gap) * 2, b, b)
		if i < items.size():
			# ITEM ids, not ability ids: Content.ITEMS keeps the plain "+"
			# convention (the shrine press is not forked by Block D6), so
			# trim_suffix / ends_with on "+" stay exactly right here.
			_icon_button(ir, "it_" + String(items[i]).trim_suffix("+"), "item:%d" % i, false)
			if String(items[i]).ends_with("+"):
				_txt(Vector2(ir.position.x + ir.size.x * 0.74, ir.position.y + ir.size.y * 0.3), "+", COL_GOLD, int(ir.size.y * 0.3))
		else:
			draw_rect(ir.grow(-b * 0.06), Color(1, 1, 1, 0.04))
			draw_rect(ir.grow(-b * 0.06), Color(0.35, 0.44, 0.36, 0.45), false, 1.5)

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
	# WRAP, don't shrink. Fitting each line to one _txt_fit line put the same
	# ABILITY_DESC row a card shows at 34px into this box at 25px - and because
	# the lines share one size, the widest one dragged the enemy's name and HP
	# down with it. Two lines per tooltip line, at the size the box asked for.
	var fsz := int(vh * 0.021)
	var rows: Array = []
	for line in tooltip:
		var w := _wrap(String(line), fsz, vw * 0.86, 2)
		fsz = mini(fsz, int(w["size"]))
	for i in tooltip.size():
		for l in _wrap(String(tooltip[i]), fsz, vw * 0.86, 2)["lines"]:
			rows.append([String(l), i])
	var bw := 0.0
	for row in rows:
		bw = maxf(bw, font.get_string_size(String(row[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x)
	bw += vw * 0.04
	var lh := fsz * 1.5
	var bh := rows.size() * lh + vh * 0.018
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
	for row in rows:
		_txt(Vector2(bx + vw * 0.02, y), String(row[0]),
			COL_TEXT if int(row[1]) == 0 else COL_DIM_TEXT, fsz)
		y += lh


## Keep a sheet's trailing button inside the sheet's own panel. A button whose
## y accumulates behind a variable number of cards walks off the bottom: the
## drop sheet's BACK (five kit cards, which is the only shape that sheet has)
## landed 32px below the frame and 52px from the screen edge at 1080x2400 -
## inside Android's home-gesture strip, on the one control that leaves a sheet
## the player is FORCED to resolve. The shrine's CLOSE never moved because it
## is pinned at a constant vh*0.885; these are pinned to the same floor.
func _sheet_button_y(y: float, h: float, vh: float) -> float:
	return minf(y, vh * 0.955 - h)


func _sheet(vw: float, vh: float, title: String) -> float:
	draw_rect(Rect2(0, 0, vw, vh), COL_SHEET)
	# panel frame with a sun-sheen top edge and sprouting corner accents
	var fr := Rect2(vw * 0.025, vh * 0.035, vw * 0.95, vh * 0.93)
	draw_rect(fr, Color(0.07, 0.11, 0.08, 0.9))
	draw_rect(fr, Color(0.35, 0.48, 0.35, 0.8), false, 2.0)
	draw_rect(Rect2(fr.position.x + 8, fr.position.y + 3, fr.size.x - 16, 2), Color(0.9, 1.0, 0.8, 0.10))
	var lt := Art.tex("growth", int(vh * 0.026))
	if lt != null:
		draw_texture(lt, fr.position + Vector2(vw * 0.02, vh * 0.012), Color(1, 1, 1, 0.8))
		draw_texture(lt, Vector2(fr.end.x - vw * 0.02 - vh * 0.026, fr.position.y + vh * 0.012), Color(1, 1, 1, 0.8))
	_txt_c_fit(vw / 2.0, vh * 0.095, title, COL_GOLD, int(vh * 0.034), vw * 0.82)
	draw_rect(Rect2(vw * 0.2, vh * 0.115, vw * 0.6, 2), Color(0.91, 0.78, 0.25, 0.55))
	return vh * 0.16


## Sprite key for an ability id. The art is per BASE ability, so the id is
## folded with Content.base_id and NEVER with trim_suffix("+"): since Block D6
## an upgrade id is "<base>+<variant>", which trim_suffix returns unchanged -
## every variant would miss its icon and fall back to "ab_default".
func _ability_icon(aid: String) -> String:
	var icon := "ab_" + Content.base_id(aid)
	return icon if Art.ART.has(icon) else "ab_default"


func _ability_desc(aid: String) -> String:
	# exact id first (every variant carries its own line), base as fallback -
	# base_id, never trim_suffix("+"): Block D6 variant ids do not end in "+"
	return Content.ABILITY_DESC.get(aid, Content.ABILITY_DESC.get(Content.base_id(aid), ""))


## A choice card: icon and name on the head row, the effect WRAPPED underneath
## across the card's full width. The description used to be one _txt_fit line,
## and _fit_size shrinks to 9px to make a long line fit - on a phone shop of
## seven offers that is unreadable, which is the whole reason for the wrap.
## The head row carries the numbers as glyphs rather than words: `pips` is a
## charge cost drawn as the dots the ability bar already uses for it, and the
## right edge carries EITHER `badge` (the draft's slot label) or `price` (the
## shrine's bloom cost beside the bloom sprite), never both.
func _card(r: Rect2, icon: String, name_: String, desc: String, tag: String, vh: float,
		badge: String = "", pips: int = 0, price: int = -1, afford: bool = true,
		up: bool = false) -> void:
	_box(r, _sb_card)
	var L := _card_layout(r, icon, name_, desc, badge, pips, price, up)
	var ic: Dictionary = L["icon"]
	if ic["size"] > 0:
		var tx := Art.tex(String(ic["id"]), int(ic["size"]))
		if tx != null:
			draw_texture(tx, ic["pos"])
	var nm: Dictionary = L["name"]
	_txt(nm["pos"], String(nm["text"]), COL_TEXT, int(nm["size"]))
	var pp: Dictionary = L["pips"]
	for c in int(pp["n"]):
		draw_circle(Vector2(float(pp["pos"].x) + c * float(pp["step"]), float(pp["pos"].y)),
			float(pp["radius"]), COL_GOLD)
	if L.has("up"):
		_txt(L["up"]["pos"], "+", COL_GOLD, int(L["up"]["size"]))
	if L.has("badge"):
		_txt(L["badge"]["pos"], String(L["badge"]["text"]), COL_GOLD, int(L["badge"]["size"]))
	if L.has("price"):
		var pr: Dictionary = L["price"]
		var ptx := Art.tex("ic_bloom", int(pr["icon_size"]))
		if ptx != null:
			draw_texture(ptx, pr["icon_pos"], Color(1, 1, 1, 1.0 if afford else 0.45))
		_txt(pr["pos"], String(pr["text"]), COL_GOLD if afford else COL_RED, int(pr["size"]))
	var de: Dictionary = L["desc"]
	var ly: float = float(de["pos"].y)
	for line in de["lines"]:
		_txt(Vector2(float(de["pos"].x), ly), String(line), COL_DIM_TEXT, int(de["size"]))
		ly += float(de["line_h"])
	_hot(r, tag)


## Where every piece of a card lands, as data - the shell draws this dict and
## nothing else, so tests/test_shell.gd can assert on the SIZE a description
## ends up at (the owner's "text very small on screens") without a display, and
## tests/render_sheet.gd can draw the same dict as an SVG screenshot. Two
## renderers, one layout: sim/game.gd earns its ASCII view the same way.
func _card_layout(r: Rect2, icon: String, name_: String, desc: String,
		badge: String = "", pips: int = 0, price: int = -1, up: bool = false) -> Dictionary:
	var h := r.size.y
	var pad := h * 0.09
	var isz := int(h * 0.40) if Art.ART.has(icon) else 0
	var name_x := r.position.x + pad
	if isz > 0:
		name_x += isz + h * 0.14
	var right := r.position.x + r.size.x - pad
	var base_y := r.position.y + h * 0.35
	var out := {
		"icon": {"id": icon, "pos": r.position + Vector2(pad, h * 0.05), "size": isz},
	}
	if badge != "":
		var bsz := _fit_size(badge, int(h * 0.22), r.size.x * 0.36)
		right -= font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, bsz).x
		out["badge"] = {"text": badge, "pos": Vector2(right, base_y), "size": bsz}
		right -= h * 0.1
	elif price >= 0:
		# a price you cannot meet is drawn red, so a thin purse reads off the
		# card instead of off a refusal after the tap
		var psz := int(h * 0.26)
		right -= psz
		var ipos := Vector2(right, base_y - psz * 0.82)
		right -= h * 0.04
		var ps := str(price)
		right -= font.get_string_size(ps, HORIZONTAL_ALIGNMENT_LEFT, -1, psz).x
		out["price"] = {"text": ps, "pos": Vector2(right, base_y), "size": psz,
			"icon_pos": ipos, "icon_size": psz}
		right -= h * 0.1
	# reserve what the head row draws AFTER the name - the gap, the pips and the
	# upgrade "+" - before fitting the name into what is left. Reserving only
	# "pips * h*0.15" (and flooring the allowance at h*0.6) let _fit_size grow a
	# long name right up to the badge and then drew the "+" past it: 19 of the 39
	# upgrade cards collided at 1080x2400 and 30 at 1080x2640, none at 16:9,
	# because the tail is sized in h and h/vw grows with the aspect ratio
	var plus_sz := int(h * 0.28)
	var tail := 0.0
	if pips > 0 or up:
		tail = h * 0.13 + pips * h * 0.14
		if up:
			tail += h * 0.02 + font.get_string_size("+", HORIZONTAL_ALIGNMENT_LEFT, -1, plus_sz).x
	var nsz := _fit_size(name_, int(h * 0.28), maxf(right - name_x - tail, h * 0.2))
	out["name"] = {"text": name_, "pos": Vector2(name_x, base_y), "size": nsz}
	# cost pips: the same dots, in the same gold, as the ability bar draws under
	# every slot - the number is never spelled out twice
	var px := name_x + font.get_string_size(name_, HORIZONTAL_ALIGNMENT_LEFT, -1, nsz).x + h * 0.13
	out["pips"] = {"n": pips, "pos": Vector2(px, base_y - h * 0.09),
		"step": h * 0.14, "radius": h * 0.045}
	# the same gold "+" the ability bar puts on a grown slot, so the word
	# "upgrade" never has to be spelled out on a card that is short of width
	if up:
		out["up"] = {"pos": Vector2(px + pips * h * 0.14 + h * 0.02, base_y), "size": plus_sz}
	var wrapped := _wrap(desc, int(h * 0.19), r.size.x - pad * 2.0, 2)
	var dlines: Array = wrapped["lines"]
	var dsz: int = int(wrapped["size"])
	var lh := float(dsz) * 1.2
	out["desc"] = {
		"lines": dlines, "size": dsz, "line_h": lh, "nominal": int(h * 0.19),
		"pos": Vector2(r.position.x + pad,
			r.position.y + h * 0.47 + (h * 0.47 - lh * dlines.size()) / 2.0 + float(dsz)),
	}
	return out


## The shrine sheet as data: one [icon, name, desc, tag, price, pips] row per
## offer, in sheet order. The price is a number the card draws beside the bloom
## sprite, not words inside the name - a seven-offer shrine has no width to
## spend on "  -  4 bloom" seven times. Split out of the drawing so the headless test can assert what
## a shrine offers (and what it stops offering). Every row's tag resolves
## through game.legal_actions() when tapped - the shell never hand-builds a
## purchase the sim would reject.
func _shop_cards(snap: Dictionary) -> Array:
	var shop: Dictionary = snap["shop"]
	var pl: Dictionary = snap["player"]
	var cards: Array = []
	if shop.get("heal", false):
		cards.append(["ic_hp", "Heal", "+4 HP, up to your max",
			"buy:heal", game.shop_cost("heal"), 0])
	if shop.has("ability"):
		var aid: String = shop["ability"]
		var icon := _ability_icon(aid)
		var adesc := _ability_desc(aid)
		cards.append([icon, String(Content.ABILITIES[aid]["name"]), adesc, "buy:ability",
			game.shop_cost("ability"), int(Content.ABILITIES[aid]["cost"])])
	var offers: Array = shop.get("grafts", [])
	# every graft is priced from its own Content.GRAFTS row, so the two offers
	# rarely cost the same: the sim publishes the per-offer prices as
	# shop.graft_prices and the card shows this graft's price, never a flat one
	var gprices: Array = shop.get("graft_prices", [])
	for i in offers.size():
		var gid: String = offers[i]
		var gcost: int = int(gprices[i]) if i < gprices.size() else game.shop_cost("graft", gid)
		var gdesc: String = "Permanent  ·  %s" % Content.GRAFTS[gid]["desc"]
		# a graft carries tags too, so a shrine purchase is the other way an
		# element is crossed (Block D5) - undertow takes a hydraulics kit from
		# displace 1 to displace 2 with no kit change at all
		var gnote := _resonance_note(snap, Content.GRAFTS[gid].get("tags", []), false)
		if gnote != "":
			gdesc += "  ·  %s" % gnote
		if offers.size() > 1:
			gdesc += "  ·  take one only"
		cards.append(["shrine", String(Content.GRAFTS[gid]["name"]), gdesc,
			"buy:graft:%d" % i, gcost, 0])
	if shop.has("item") and pl["items"].size() < Content.ITEM_CAP:
		var iid: String = shop["item"]
		cards.append(["it_" + iid, String(Content.ITEMS[iid]["name"]),
			"One use  ·  %s" % Content.ITEMS[iid]["desc"], "buy:item", game.shop_cost("item"), 0])
	# the two shrine services come straight out of legal_actions(): a boarded
	# shrine, a forge already spent this floor or a thin purse yields nothing,
	# and the card list follows without repeating a single sim rule
	var pits: Array = pl["items"]
	for a in _legal_of("upcycle"):
		var k := int(a.get("keep", -1))
		if k < 0 or k >= pits.size():
			continue
		var kid := String(pits[k])
		var mat := String(pits[1 - k])
		# kid + "+" is an ITEM id: the press is not forked, so Content.ITEMS
		# keeps the plain "+" convention (Block D6 forked abilities only)
		cards.append(["it_" + kid, "Press " + String(Content.ITEMS[kid]["name"]),
			"Spend your %s to make %s" % [Content.ITEMS[mat]["name"], Content.ITEMS[kid + "+"]["name"]],
			"upcycle:%d" % k, game.shop_cost("press"), 0])
	if not _legal_of("upcycle_ability").is_empty():
		cards.append(["ab_default", "Forge an ability",
			"Grow one ability, scrap another. Once per floor",
			"forge", game.shop_cost("forge"), 0])
	# the repeatable sink: the card shows while a re-drawable slot is stocked
	# (a bought-out counter can never be redrawn) and prices itself from the
	# derived snapshot keys - the price climbs with every spin
	# (a shrine that can never spin - the Spinning Shrine mutator off - shows
	# no card: rerolls_left reads 0 with nothing spun)
	var rleft := int(shop.get("rerolls_left", 0))
	var rspun := int(shop.get("rerolls", 0))
	if (shop.has("ability") or shop.has("grafts") or shop.has("item")) and (rleft > 0 or rspun > 0):
		var rprice := int(shop.get("reroll_price", 0))
		var rdesc := "Redraws the ability, graft and item offers  ·  %d spin%s left" % [
			rleft, "" if rleft == 1 else "s"]
		if rleft <= 0:
			rdesc = "No spins left this floor"
		elif snap["bloom"] < rprice:
			rdesc = "Not enough bloom to spin"
		cards.append(["ic_bloom", "Reroll", rdesc, "reroll", rprice, 0])
	return cards


## The draft sheet as data: one [icon, name, desc, tag, badge, pips, upgrade]
## row per offer, in sheet order - the same split _shop_cards makes, so the
## headless test and tests/render_sheet.gd read the sheet without drawing it.
func _draft_cards(snap: Dictionary) -> Array:
	var slots: Array = snap.get("draft_slots", [])
	var cards: Array = []
	for i in snap["draft_offers"].size():
		var aid: String = snap["draft_offers"][i]
		var adef: Dictionary = Content.ABILITIES[aid]
		var role := String(slots[i]) if i < slots.size() else ""
		# Block D5: what this card does to an element, straight off the resonance
		# table - the card is where a threshold is crossed, so it is where the
		# count has to be legible
		var cdesc := _ability_desc(aid)
		var note := _resonance_note(snap, _ability_tags(aid), false, [],
			snap["player"]["kit"].size() >= Content.KIT_MAX)
		if note != "":
			cdesc = "%s  ·  %s" % [cdesc, note]
		cards.append([_ability_icon(aid), String(adef["name"]), cdesc, "draft:%d" % i,
			String(DRAFT_SLOT_LABEL.get(role, "")), int(adef["cost"]), Content.is_upgrade(aid)])
	return cards


## The same, for the drop sheet a full kit forces.
func _drop_cards(snap: Dictionary) -> Array:
	var cards: Array = []
	var offers_d: Array = snap.get("draft_offers", [])
	var taking: Array = _ability_tags(String(offers_d[mode_pick])) \
		if mode_pick >= 0 and mode_pick < offers_d.size() else []
	for i in snap["player"]["kit"].size():
		var kid: String = snap["player"]["kit"][i]
		# Block D5: dropping a card can put a lit element OUT, and that is the
		# one consequence of a drop the kit list cannot otherwise show
		var ddesc := _ability_desc(kid)
		var dnote := _resonance_note(snap, _ability_tags(kid), true, taking)
		if dnote != "":
			ddesc = "%s  ·  %s" % [ddesc, dnote]
		cards.append([_ability_icon(kid), String(Content.ABILITIES[kid]["name"]), ddesc,
			"drop:%d" % i, "BREAKS" if dnote != "" else "",
			int(Content.ABILITIES[kid]["cost"]), Content.is_upgrade(kid)])
	return cards


func _draw_shop(snap: Dictionary, vw: float, vh: float) -> void:
	hotspots.clear()
	var y := _sheet(vw, vh, "SHRINE SHOP")
	_txt(Vector2(vw * 0.06, y), "bloom  %d" % snap["bloom"], COL_GOLD, int(vh * 0.026))
	y += vh * 0.05
	var cards := _shop_cards(snap)
	var bot := vh * 0.86  # the CLOSE button lives below this
	var gap := vh * 0.02
	var ch := vh * 0.105
	if not cards.is_empty():
		ch = minf(ch, maxf(vh * 0.06, (bot - y - gap * (cards.size() - 1)) / cards.size()))
	for c in cards:
		var cprice := int(c[4])
		_card(Rect2(vw * 0.05, y, vw * 0.9, ch), String(c[0]), String(c[1]), String(c[2]),
			String(c[3]), vh, "", int(c[5]), cprice, int(snap["bloom"]) >= cprice)
		y += ch + gap
	if cards.is_empty():
		_txt(Vector2(vw * 0.06, y + vh * 0.04), "Boarded up - nothing for sale.", COL_DIM_TEXT, int(vh * 0.024))
	_button(Rect2(vw * 0.25, vh * 0.885, vw * 0.5, vh * 0.07), "CLOSE", "close", int(vh * 0.026))


## The forge's fork sheet (Block D6). A base ability upgrades into one of two
## named variants and the shrine sells both, so once keep and scrap are picked
## the last question is which way it grows. The cards come straight off the
## legal forge actions for that (keep, scrap) pair, so the sheet can only ever
## offer a fork the sim would accept - and the sibling a floor's parity draft
## cannot deal is always here.
func _draw_forge_variants(vw: float, vh: float) -> void:
	hotspots.clear()
	var y := _sheet(vw, vh, "THE FORGE")
	var kit: Array = game.player["kit"]
	var acts := _forge_actions(mode_pick, mode_scrap)
	var kid := String(kit[mode_pick]) if mode_pick >= 0 and mode_pick < kit.size() else ""
	var sid := String(kit[mode_scrap]) if mode_scrap >= 0 and mode_scrap < kit.size() else ""
	_txt_fit(Vector2(vw * 0.06, y), "Scrap %s, grow %s. Pick one:" % [
		Content.ABILITIES.get(sid, {}).get("name", sid),
		Content.ABILITIES.get(kid, {}).get("name", kid)],
		COL_TEXT, int(vh * 0.024), vw * 0.88)
	y += vh * 0.055
	var variants: Array = Content.variants_of(Content.base_id(kid))
	var bh := vh * 0.115
	for a in acts:
		var vi := int(a.get("variant", 0))
		if vi < 0 or vi >= variants.size():
			continue
		var vid := String(variants[vi])
		var adef: Dictionary = Content.ABILITIES[vid]
		_card(Rect2(vw * 0.05, y, vw * 0.9, bh), _ability_icon(vid), String(adef["name"]),
			_ability_desc(vid), "forgevar:%d" % vi, vh, "", int(adef["cost"]), -1, true, true)
		y += bh + vh * 0.02
	y += vh * 0.015
	_button(Rect2(vw * 0.25, _sheet_button_y(y, bh * 0.6, vh), vw * 0.5, bh * 0.6),
		"BACK", "forge_back", int(bh * 0.24))


func _draw_logsheet(vw: float, vh: float) -> void:
	hotspots.clear()
	var y := _sheet(vw, vh, "EVENT LOG  (tap to close)")
	var fsz := int(vh * 0.021)
	var start: int = maxi(0, log_lines.size() - 28)
	for i in range(start, log_lines.size()):
		_txt(Vector2(vw * 0.06, y), log_lines[i], COL_TEXT if i == log_lines.size() - 1 else COL_DIM_TEXT, fsz)
		y += fsz * 1.45


## The descent draft (Block D4). Each card carries the slot that rolled it -
## AFFINITY (shares a tag with your kit and grafts), UPGRADE (the "+" form of
## something you hold), WILD (anything in the pool) or FOCUS (the extra
## affinity offer a previous skip bought). The roles are read straight off
## snapshot().draft_slots, so the sheet can never label a card as something
## the sim did not roll it as. Whether the roll SPENT a focus is a different
## question - a focus slot with no candidate left yields no card - and that
## comes off the draft_offer event (_draft_focus_spent), so a skip that
## bought nothing says so instead of reading as an ordinary draft.
func _draw_draft(snap: Dictionary, vw: float, vh: float) -> void:
	hotspots.clear()
	var y := _sheet(vw, vh, "DESCENT DRAFT")
	var slots: Array = snap.get("draft_slots", [])
	# a FOCUS card on the sheet vs a focus the roll spent: the second is the
	# truth about the skip, and only the draft_offer event carries it
	var focused: bool = slots.has("focus")
	var spent: bool = focused or _draft_focus_spent
	# the head names the labels the sheet actually carries: Upgrades Only deals
	# nothing but UPGRADE cards, and pointing at AFFINITY there would be a lie
	var head := "Take one down with you:"
	if focused:
		head = "Your skip bought the FOCUS offer:"
	elif spent:
		head = "Nothing left to focus on - no extra offer:"
	elif slots.has("affinity"):
		head = "Take one down with you. AFFINITY matches your build:"
	_txt_fit(Vector2(vw * 0.06, y), head, COL_TEXT, int(vh * 0.024), vw * 0.88); y += vh * 0.038
	# the run's elements, so the counts a card moves are on the same sheet as
	# the cards (Block D5). Nothing is drawn - and the head keeps exactly its
	# old spacing - when no element is started, and the drop sheet skips the
	# strip because it is the taller of the two (five kit cards) and its cards
	# carry the BREAKS badge anyway.
	var rline := _resonance_line(snap)
	if rline != "" and mode != "draft_drop":
		_txt_fit(Vector2(vw * 0.06, y), "ELEMENTS  %s" % rline,
			COL_GOLD if not snap.get("resonances", []).is_empty() else COL_DIM_TEXT,
			int(vh * 0.019), vw * 0.88)
		y += vh * 0.028
	else:
		y += vh * 0.017
	var bh := vh * 0.105
	if mode != "draft_drop":
		for c in _draft_cards(snap):
			_card(Rect2(vw * 0.05, y, vw * 0.9, bh), String(c[0]), String(c[1]), String(c[2]),
				String(c[3]), vh, String(c[4]), int(c[5]), -1, true, bool(c[6]))
			y += bh + vh * 0.02
		y += vh * 0.015
		_button(Rect2(vw * 0.25, _sheet_button_y(y, bh * 0.65, vh), vw * 0.5, bh * 0.65),
			"skip again - +1 affinity next draft" if spent
				else "skip - +1 affinity offer next draft",
			"skip_draft", int(bh * 0.24))
	else:
		_txt_fit(Vector2(vw * 0.06, y), "Kit full - tap what to DROP:", COL_RED, int(vh * 0.024), vw * 0.88); y += vh * 0.05
		for c in _drop_cards(snap):
			_card(Rect2(vw * 0.05, y, vw * 0.9, bh), String(c[0]), String(c[1]), String(c[2]),
				String(c[3]), vh, String(c[4]), int(c[5]), -1, true, bool(c[6]))
			y += bh + vh * 0.02
		y += vh * 0.02
		_button(Rect2(vw * 0.25, _sheet_button_y(y, bh * 0.65, vh), vw * 0.5, bh * 0.65),
			"BACK", "draft_back", int(bh * 0.26))


func _draw_over(snap: Dictionary, vw: float, vh: float) -> void:
	hotspots.clear()
	draw_rect(Rect2(0, 0, vw, vh), COL_SHEET)
	var won: bool = snap["won"]
	var tsec := Time.get_ticks_msec() / 1000.0
	if won:
		var sun := Vector2(vw / 2.0, vh * 0.185)
		draw_circle(sun, vw * 0.20, Color(0.95, 0.88, 0.55, 0.08))
		draw_circle(sun, vw * 0.14, Color(0.95, 0.88, 0.55, 0.12))
		draw_circle(sun, vw * 0.08, Color("f2e4a0"))
		for i in 10:  # petals drift down through the clear air
			var ph := float(i) * 1.7
			var fall := fposmod(tsec * (0.05 + 0.02 * float(i % 3)) + ph, 1.0)
			draw_circle(Vector2(vw * fposmod(ph * 0.37 + sin(tsec * 0.6 + ph) * 0.03, 1.0), vh * 0.55 * fall),
				vw * 0.006, Color(0.91, 0.62, 0.80, 0.7 * (1.0 - fall)))
	else:
		for i in 5:  # the smog closes over the screen
			var drift := fposmod(tsec * (0.02 + 0.01 * float(i % 2)) + float(i) * 0.23, 1.2) - 0.1
			draw_circle(Vector2(vw * drift, vh * (0.08 + 0.06 * float(i))), vw * 0.16, Color(0.42, 0.36, 0.32, 0.08))
		var skt := Art.tex("ic_choke", int(vh * 0.055))
		if skt != null:
			draw_texture(skt, Vector2(vw / 2.0 - vh * 0.0275, vh * 0.165))
	var oy := vh * 0.30
	_txt_c(vw / 2.0, oy, "THE FURNACE IS COLD" if won else "YOU DIED", COL_GOLD if won else COL_RED, int(vh * 0.042))
	oy += vh * 0.055
	_txt_c_fit(vw / 2.0, oy, "the valley breathes again" if won else "cause: %s" % snap["death_cause"], COL_TEXT, int(vh * 0.024), vw * 0.9)
	oy += vh * 0.07
	_txt_c(vw / 2.0, oy, "floor %d · turn %d · bloom %d" % [snap["floor"], snap["turn"], snap["bloom"]], COL_TEXT, int(vh * 0.024))
	oy += vh * 0.04
	var seedline := "seed %d" % seed_v
	if run_tier > 0:
		seedline += "  ·  difficulty %d" % run_tier
	_txt_c(vw / 2.0, oy, seedline, COL_DIM_TEXT, int(vh * 0.02))
	# Block D5: what the run's build ended up being, from the sim's own active
	# set - the free permanents a player earns are worth naming at the end
	var lit: Array = []
	for r in _resonance_state(snap):
		if bool(r["active"]):
			lit.append(String(r["name"]))
	if not lit.is_empty():
		oy += vh * 0.032
		_txt_c_fit(vw / 2.0, oy, "resonating: %s" % ", ".join(lit), COL_GOLD, int(vh * 0.021), vw * 0.92)
	oy += vh * 0.05
	for u in _run_unlocks.slice(0, 4):
		var us := String(u)
		var label := ""
		if us.begins_with("tier:"):
			var tn2 := String(Content.TIERS[int(us.substr(5)) - 1]["name"])
			label = "NEW DIFFICULTY UNLOCKED: %s" % tn2.to_upper()
		else:
			label = "UNLOCKED: %s" % us.replace("_", " ").to_upper()
		_txt_c_fit(vw / 2.0, oy, label, COL_GOLD, int(vh * 0.021), vw * 0.92)
		oy += vh * 0.032
	oy = maxf(oy + vh * 0.03, vh * 0.64)
	_txt_c(vw / 2.0, oy, "- tap anywhere for a new run -", COL_GOLD, int(vh * 0.026))
	_button(Rect2(vw * 0.3, oy + vh * 0.05, vw * 0.4, vh * 0.06), "MENU", "menu", int(vh * 0.024))


func _draw_intro(vw: float, vh: float) -> void:
	hotspots.clear()
	draw_rect(Rect2(0, 0, vw, vh), COL_SHEET)
	var x := vw * 0.07
	var y := vh * 0.1
	draw_circle(Vector2(vw * 0.82, vh * 0.085), vw * 0.09, Color(0.95, 0.88, 0.55, 0.10))
	draw_circle(Vector2(vw * 0.82, vh * 0.085), vw * 0.055, Color("f2e4a0"))
	var pt := Art.tex("player", int(vh * 0.055))
	if pt != null:
		draw_texture(pt, Vector2(vw * 0.66, vh * 0.055))
	_txt(Vector2(x, y), "TENDER", COL_GOLD, int(vh * 0.05)); y += vh * 0.07
	for pair in [
		["The combine poisoned the world. You are a Tender.", COL_TEXT],
		["Descend all 7 floors and shut down the Furnace.", COL_TEXT],
		["", COL_TEXT],
		["MOVE with the D-pad, or tap a tile beside you.", COL_TEXT],
		["Move into an enemy to attack it.", COL_TEXT],
		["RED tiles are incoming damage. Stay off.", COL_TEXT],
		["The GOLD-RINGED stairs are the way down.", COL_TEXT],
		["", COL_TEXT],
		["Smog rises every turn. Deep smog kills - move fast.", COL_GOLD],
		["", COL_TEXT],
		["CLEANSE oil and goo: bloom AND thinner smog.", COL_TEXT],
		["Shrines offer TWO grafts at their own prices - take one only.", COL_TEXT],
		["Cleanse a WHOLE room: bonus bloom and a supply pod.", COL_TEXT],
		["The stairs stay DORMANT until you green the floor.", COL_GOLD],
		["Cast FROM growth: it surges the ability, and the tile is spent.", COL_TEXT],
		["Punching SPIKED enemies costs you 1 HP. Use abilities.", COL_TEXT],
		["Shrines UPCYCLE: press 2 items into 1, forge an ability into a variant.", COL_TEXT],
		["Drill bots in pairs WELD into hulks - split them up.", COL_RED],
		["Growth heals you while you stand on it.", COL_TEXT],
		# the intro is exactly as long as the screen: this line took the blank
		# that used to sit above the HOLD line rather than adding a 22nd row
		["ELEMENTS: enough cards of one and it RESONATES all run.", COL_GOLD],
		["HOLD anything to see what it is.", COL_GOLD],
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
