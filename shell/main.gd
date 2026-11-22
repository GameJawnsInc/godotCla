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
const RunStats := preload("res://meta/run_stats.gd")
const Names := preload("res://shell/names.gd")
const Feedback := preload("res://shell/feedback.gd")
const Danger := preload("res://shell/danger.gd")
const RunEnd := preload("res://shell/run_end.gd")
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
	["vent", "Vent", "releases enemies as the smog rises - the number counts down"],
	["supply", "Supply pod", "step on it to stock your satchel (2 slots)"],
	["oil", "Oil", "corruption - cleanse from beside it for bloom. Burns"],
	["goo", "Goo", "corruption - cleanse for bloom. Hurts to step in"],
	["rich_goo", "Rich goo", "corruption - cleanse for extra bloom. Hurts to step in"],
	["ash", "Ash", "corruption from burnt oil - cleanse for bloom. Never shields the core"],
	["growth", "Growth", "stand on it: heal 1 HP a turn"],
	["fire", "Fire", "burns whoever stands in it. Leaves ash"],
	["smoke", "Smoke", "blocks beams. Screens tar/drain/grapple from 2+ tiles away"],
	["roots", "Roots", "blocks enemies for a while"],
	# the danger readouts (shell/danger.gd): the two SKIES countdown chips, then
	# one row per intent badge and per blocked-intent glyph - test_shell holds
	# every Danger.BADGE / BLOCK_ICON icon to a row here
	["ic_choke", "Choke countdown", "turns until the smog starts choking you"],
	["ic_dim", "Dimming countdown", "turns until the sky dims - less charge"],
	["in_attack", "Strike", "hits the red tile next turn for the number"],
	["in_slam", "Slam", "hits the red cross next turn for the number"],
	["in_quake", "Quake", "hits every tile around it for the number"],
	["in_drain", "Drain", "takes banked charge from range"],
	["in_gum", "Tar", "gums the ability slot outlined in brown"],
	["in_drag", "Grapple", "drags you along the line toward it"],
	["in_advance", "Advance", "lumbers that many tiles toward you"],
	["in_summon", "Summon", "spawns a sludgeling when the count runs out"],
	["in_ooze", "Ooze", "spills oil when the count runs out"],
	["in_stoke", "Stoke", "thickens the smog when the count runs out"],
	["in_fuse", "Weld", "two machines fuse into a hulk - break the pair"],
	["in_dredge", "Dredge", "turns your growth in reach back into goo"],
	["in_flood", "Flood", "floods the striped row with oil"],
	["in_gather", "Gather", "the boss gathers heat"],
	["in_ignite", "Ignite all", "every glowing oil tile catches fire"],
	["in_stunned", "Stunned", "loses its next action"],
	["in_rooted", "Rooted", "cannot move, advance or drag"],
	["in_screened", "Lost in smoke", "its tar, drain or grapple will miss you"],
	["in_anchored", "Anchored", "your roots hold - the grapple fails"],
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
var mode := "normal"  # normal | target_dir | target_tile | cleanse | draft_drop | up_keep | up_scrap | up_variant | intro | help | shop | log | settings | daily | career
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
## Where the live run's action log is written and restored from. RUN_SAVE_PATH
## in the app; a headless test points it at scratch BEFORE _ready, which
## restores (and may delete) whatever save it finds there.
var run_save_path := RUN_SAVE_PATH

# settings (persisted to user://tender.cfg)
var hold_ms := 420
## What the live run is: "career" (PLAY - recorded to the profile) or "daily"
## (the DAILY sheet's PLAY - filed to the daily board only). It replaced the
## old global seed-mode setting: a run carries its own kind, in its run-save
## header too, so a resumed or retried run is filed where it started.
var run_kind := "career"
## The old cfg "seed_mode" key. Its only use is routing a run save from before
## the daily got its own button (a header with no "kind"), and the one-time
## menu notice below. `_save_settings` carries it forward while it is "daily"
## (a settings change must not re-file a header-less daily to the career) and
## `_start_run` drops it for good: the run save it writes names its own kind.
var _legacy_seed_mode := "random"
## "the daily now has its own button": shown on the menu until the player
## starts a run or opens the DAILY sheet, then never again - the dismissal is
## persisted (cfg "legacy_notice_seen", or the seed_mode key gone).
var _legacy_notice := false
## Where the settings are read and saved. Tests point it at a scratch file
## before `_ready`, as they do `profile_path`, so a test never rewrites the
## player's own settings.
var cfg_path := CFG_PATH
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
## them into a run config through profile.game_config; for a daily run
## (run_kind == "daily") the seed's own Profile.daily_config replaces them.
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
## The feedback layer's live state (shell/feedback.gd computes, this applies).
const LOG_KEEP := 60       # log lines kept; log_cats is trimmed with them
const BANNER_MS := 1600    # one banner's life (wall clock)
const LUNGE_OUT := 45      # the tender's lean into a strike, ms out...
const LUNGE_BACK := 70     # ...and back
var log_cats: Array = []   # parallel to log_lines: a Feedback.LOG_COL category per line
var _banner_col := COL_GOLD
var _banner_q: Array = []  # pending {lines, col, prio}, prio desc, max 3
var _sfx_q: Array = []     # delayed sounds {id, pitch, at} (the combo chime)
var _frozen_total := 0     # hit-stop: ms the fx clock has been held in all
var _freeze_start := -1
var _freeze_end := -1
var _lunge_dir := Vector2.ZERO
var _lunge_ms := -99999
var _lunge_hold := 0
var _run_save: FileAccess = null  # open append handle for the live run's log
## Danger readability (shell/danger.gd): Danger.compute(game) - the three sim
## forecasts plus their verdicts - cached per state change, because the
## end-turn forecast steps a clone (~2ms, and the lethal escape search ~6ms):
## never per frame. `_danger_rev` is bumped after every step and on every new
## or restored game; `_danger_at` is the rev the cache was built at and
## `_danger_for` the game it was built from.
var _danger := {}
var _danger_rev := 0
var _danger_at := -1
var _danger_for = null
## The lethal guard's armed press: {sig: Danger.guard_sig, ms}. Empty = unarmed.
var _guard := {}
## The lowest choke countdown already announced on this floor (Danger.cues'
## hysteresis; Danger.NO_CUE = none). Reset with the danger cache.
var _choke_cued := Danger.NO_CUE
var _flash_red := false  # the flash on screen is a guard refusal: draw it red
## Where the career profile is read and written. PROFILE_PATH in the app; the
## headless tests point it at a scratch file BEFORE _ready, so no test ever
## writes a player's real career.
var profile_path := PROFILE_PATH
## The run's statistics fold (meta/run_stats.gd): one per game, tutorial
## included, fed after every step. `_stats_for` is the game it folds, so a
## game swapped in from outside (tests, tools) gets a fresh fold.
var stats = null
var _stats_for = null
## The career's bests as they stood BEFORE the finished run was recorded
## (Profile.bests_snapshot), or {"daily": that seed's previous best} on a
## daily - the only source of any "was" the game-over sheet prints.
var _over_prev: Dictionary = {}
## The finished run's merged summary and the profile's last_report for it.
var _run_summary: Dictionary = {}
var _run_report: Dictionary = {}
## The game _record_finished_run filed: the four fields above (and
## _run_unlocks / _daily_report) describe THAT game only, so a game swapped in
## from outside (a test, a tool) never borrows another run's record.
var _recorded_for = null
## The end of a run (fun pass): when the live game ends in _act, the map stays
## up for OVER_BEAT_MS with the end banner, then the sheet fades in over
## OVER_FADE_MS; taps and keys are ignored until OVER_LOCK_MS (0.3 s after the
## sheet is opaque), so a finger still hammering the D-pad cannot skip the
## death or start the next run by accident. Back/ESC stay instant (the run is
## already recorded).
const OVER_BEAT_MS := 1200
const OVER_FADE_MS := 400
const OVER_LOCK_MS := 1900
## Wall-clock ms the live game ended at this session; -1 = unknown (a game
## set over from outside, a resumed save): no beat, no lock, sheet at once.
var _over_ms := -1
## The game the beat and the sheet facts belong to (stale when `game` moved).
var _over_for = null
## The game-over sheet's facts (_build_over_info), built once per ended game.
var _over_info: Dictionary = {}
## What profile.record_daily said about the finished daily ({ranked, new_best,
## tries}); {} after a career run.
var _daily_report: Dictionary = {}
## The DAILY entry's cached facts ({date, seed, streak}), recomputed by
## _refresh_daily_info when the UTC date moves or a daily is tried or filed -
## never per frame (the menu redraws every frame for its vista).
var _daily_info: Dictionary = {}
## The run save's header ({} when there is no save of this version), cached for
## the path in _save_head_path and dropped by _save_head_dirty at every site
## that writes or removes the save: the DAILY sheet asks on every frame, and a
## file open per frame is not free on a phone.
var _save_head_cache: Dictionary = {}
var _save_head_path := ""
## The DAILY sheet's PLAY was tapped once while another run is resumable: the
## next tap starts the daily and abandons that run. Cleared when the sheet opens.
var _daily_armed := false
## The menu's PLAY was tapped once while a daily try is resumable (its try is
## already counted): the next tap abandons it. Any other tap disarms it.
var _play_armed := false
## The CAREER sheet (mode "career" on the menu): GOALS / FEATS / RECORDS, paged
## CARDS_PER_PAGE cards at a time (layout, so a shell const, not a Profile one).
const CARDS_PER_PAGE := 5
const CAREER_TABS := ["goals", "feats", "records"]
var career_tab := "goals"
var career_page := 0
## The "feat:" ids that were unseen when the FEATS tab was opened. Opening the
## tab clears them from the profile at once (and saves), so this is what keeps
## them reading NEW on their cards until the sheet is opened again.
var _career_fresh: Array = []


func _ready() -> void:
	font = ThemeDB.fallback_font
	profile = Profile.load_from(profile_path)
	_mk_styles()
	audio = AudioKit.new()
	add_child(audio)
	_load_settings()
	_clamp_selection()
	_refresh_daily_info()
	audio.sfx_on = sfx_on
	audio.music_on = music_on
	set_process(true)
	var env := OS.get_environment("SHELL_SEED")
	if env != "":
		# through _start_run like every run start, so the legacy seed_mode key
		# is dropped here too (the save it writes names its kind)
		_start_run("career", maxi(0, int(env)))
	elif FileAccess.file_exists(run_save_path):
		_load_run()  # Android reclaimed the app mid-run: replay it back
	queue_redraw()


## Today's daily seed (UTC date): the same number for everyone, so the DAILY
## sheet can show today's config before PLAY. Profile.daily_seed_for is the
## one formula (tests/daily_run.gd calls it too).
func _daily_seed() -> int:
	return Profile.daily_seed_for(Time.get_date_string_from_system(true))


func _roll_seed() -> void:
	if run_kind == "daily":
		seed_v = _daily_seed()
	else:
		seed_v = (int(Time.get_unix_time_from_system()) * 1103515245 + Time.get_ticks_msec()) % 1000000


## Start a run of `kind` ("career" or "daily") - the ONE way PLAY, the DAILY
## sheet, R and N start a run. `keep_seed` replays that seed (R: retry), else
## the seed is rolled (today's date for a daily). Every daily start counts as a
## try - a retry included - and is saved at once, because the try count is
## part of what the DAILY sheet reports.
func _start_run(kind: String, keep_seed: int = -1) -> void:
	run_kind = "daily" if kind == "daily" else "career"
	if keep_seed >= 0:
		seed_v = keep_seed
	else:
		_roll_seed()
	if run_kind == "daily":
		profile.note_daily_try(seed_v)
		profile.save(profile_path)
		_refresh_daily_info()
	_legacy_notice = false
	screen = "game"
	_new_game()
	if _legacy_seed_mode == "daily":
		# the save just written carries "kind": no header-less save is left
		# for the old key to route, so drop it (and the notice) for good
		_legacy_seed_mode = "random"
		_save_settings()


## Recompute the DAILY entry's facts: today's date and seed, and the streak.
func _refresh_daily_info() -> void:
	var date := Time.get_date_string_from_system(true)
	_daily_info = {"date": date, "seed": Profile.daily_seed_for(date),
		"streak": profile.daily_streak(int(Time.get_unix_time_from_system()))}


## The cached DAILY facts, refreshed when the UTC date has moved since.
func _daily_now() -> Dictionary:
	if _daily_info.is_empty() or String(_daily_info.get("date", "")) != Time.get_date_string_from_system(true):
		_refresh_daily_info()
	return _daily_info


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


## The config a run starts with: the menu's own choices through the career
## gate, or - for a daily - the seed's own frozen daily config, which no
## career unlock touches (a daily needs nothing unlocked).
func _run_config() -> Dictionary:
	if run_kind == "daily":
		return Profile.daily_game_config(seed_v)
	var muts: Array = [] if sel_mutator == "" else [sel_mutator]
	return profile.game_config(sel_tier, muts, sel_loadout, sel_package)


func _new_game() -> void:
	_clamp_selection()
	var cfg: Dictionary = _run_config()
	run_tier = int(cfg.get("tier", 0))
	game = Game.new(seed_v, cfg)
	_reset_over()
	_new_stats()
	_draft_focus_spent = false  # a fresh run never inherits the last one's focus
	_game_is_run = true
	_run_recorded = false
	_run_unlocks = []
	save_lost = false  # the notice stands until the player starts a fresh run
	if _run_save != null:
		_run_save.close()
	_run_save = FileAccess.open(run_save_path, FileAccess.WRITE)
	_save_head_dirty()
	if _run_save != null:
		# "kind" is shell state, not sim state: tests/import_run.gd reads only
		# v / seed / tier / config, so RUN_SAVE_VERSION does not move for it
		_run_save.store_line(var_to_str({"v": RUN_SAVE_VERSION, "seed": seed_v, "tier": run_tier,
			"config": cfg, "kind": run_kind}).replace("\n", " "))
		_run_save.flush()
	mode = "normal"
	if intro_mode == "always" or (intro_mode == "once" and not seen_intro):
		seen_intro = true
		mode = "intro"
	flash = ""
	tooltip = []
	_reset_feedback()
	_reset_danger()
	queue_redraw()


func _start_tutorial() -> void:
	screen = "tutorial"
	game = Game.new(1, Tutorial.game_config())
	_reset_over()
	_new_stats()
	_draft_focus_spent = false
	_game_is_run = false
	tut_step = 0
	tut_done = false
	mode = "normal"
	flash = ""
	tooltip = []
	_reset_feedback()
	_reset_danger()
	queue_redraw()


## A new game starts with an empty log and no banner, chime or lean left over
## from the last one.
func _reset_feedback() -> void:
	log_lines = []
	log_cats = []
	_banner = []
	_banner_q = []
	_sfx_q = []
	_lunge_dir = Vector2.ZERO


## A new (or restored) game: the danger cache is stale and no guard press may
## carry over from the last one.
func _reset_danger() -> void:
	_danger_rev += 1
	_guard = {}
	_flash_red = false
	_choke_cued = Danger.NO_CUE


## The danger layer's view of the live game (Danger.compute), recomputed only
## when the state moved (`_danger_rev`) or the game was swapped. _draw,
## _process and the tooltips read it; only the guard forces a recompute,
## because the tests mutate `game` by hand between presses.
func _danger_state(force := false) -> Dictionary:
	if game == null:
		return {}
	if force or _danger_at != _danger_rev or _danger_for != game:
		_danger = Danger.compute(game)
		_danger_at = _danger_rev
		_danger_for = game
	return _danger


## May an IMPLICIT end turn go ahead? (A D-pad press or cleanse tap that ran
## out of charge, or a tap on the tender's own tile.) When the forecast says
## that end turn kills, the first press is refused with the reason - in red,
## with the warn tick - and a second press within Danger.GUARD_MS, with
## nothing changed in between (Danger.guard_sig), goes through. END TURN, the
## D-pad's END, SPACE and ENTER are never asked: pressing END is a decision.
## Off outside a live run's play phase, so the tutorial never asks.
func _guard_lets_end() -> bool:
	if screen != "game" or game == null or game.over or game.phase != "play":
		return true
	var d := _danger_state(true)
	if not bool(d.get("lethal", false)):
		_guard = {}
		return true
	var sig: Array = Danger.guard_sig(game)
	var now := Time.get_ticks_msec()
	if not _guard.is_empty() and _guard["sig"] == sig and now - int(_guard["ms"]) <= Danger.GUARD_MS:
		_guard = {}
		return true
	_guard = {"sig": sig, "ms": now}
	_flash_danger(Danger.guard_flash(d))
	if audio != null:
		audio.play("warn")
	return false


## Restore the interrupted run: rebuild the game from its seed + config and
## replay the recorded actions. Determinism makes this byte-exact; a version
## mismatch or finished run just clears the save.
func _load_run() -> void:
	var f := FileAccess.open(run_save_path, FileAccess.READ)
	if f == null:
		return
	var head = str_to_var(f.get_line())
	if not (head is Dictionary) or int(head.get("v", -1)) != RUN_SAVE_VERSION:
		# the sim moved under the log: replaying it would diverge silently, so
		# the save goes - but the player is told why their run vanished
		f.close()
		DirAccess.remove_absolute(run_save_path)
		_save_head_dirty()
		save_lost = true
		return
	var g = Game.new(int(head["seed"]), Dictionary(head["config"]))
	# the stats fold rides the replay, so a resumed run keeps exactly the
	# stats it had (same seed + same actions = same fold, ctx included)
	var st = RunStats.new()
	st.begin(g)
	while not f.eof_reached() and not g.over:
		var line := f.get_line()
		if line.strip_edges() == "":
			continue
		var act = str_to_var(line)
		if act is Dictionary:
			st.feed(g, g.step(act))
	f.close()
	if g.over:
		DirAccess.remove_absolute(run_save_path)
		_save_head_dirty()
		return
	game = g
	_reset_over()
	stats = st
	_stats_for = g
	seed_v = int(head["seed"])
	# where the run is filed when it ends: its own header, or - for a save
	# written before the daily had its own button - the old global toggle
	var kind = head.get("kind", "daily" if _legacy_seed_mode == "daily" else "career")
	run_kind = "daily" if str(kind) == "daily" else "career"
	run_tier = int(head.get("tier", 0))
	sel_tier = run_tier
	_game_is_run = true
	_run_recorded = false
	_run_unlocks = []
	mode = "normal"
	_reset_feedback()
	_reset_danger()  # replayed through g.step, not _act: no cue fires for the replay
	# the snapshot's event tail, read context-free: no pre-step facts survive
	# a restart, so a cleanse reads "Cleansed · green x/y" without its gain
	var tail: Array = game.snapshot()["events"]
	for ev in tail:
		if String(ev.get("t", "")) == "draft_offer":
			_draft_focus_spent = bool(ev.get("focus", false))
	for ln in Feedback.log_entries(tail, {}, game, {}):
		_log(String(ln["text"]), String(ln["cat"]))
	_run_save = FileAccess.open(run_save_path, FileAccess.READ_WRITE)
	if _run_save != null:
		_run_save.seek_end()


## A fresh stats fold for the game just created.
func _new_stats() -> void:
	stats = RunStats.new()
	stats.begin(game)
	_stats_for = game


## The fold for the CURRENT game: a game assigned from outside (a test, a
## tool) gets its own fresh fold instead of feeding another game's.
func _ensure_stats() -> void:
	if stats == null or _stats_for != game:
		_new_stats()


## Is the live run the daily challenge? (The one place that asks.)
func _run_is_daily() -> bool:
	return run_kind == "daily"


## Game-over site: the run's own record (Game.run_summary() merged with the
## stats fold, stamped with the tier and run kind the shell chose and the
## cosmetic score) goes to the career profile - or to the daily board when the
## seed came from the daily challenge, since a daily scores its seed and
## unlocks nothing. The bests the sheet compares against are snapshotted
## FIRST: record_run moves them. Then the action log is closed and archived.
## Called once per run, from _act.
func _record_finished_run() -> void:
	_run_recorded = true
	_ensure_stats()
	var summary: Dictionary = game.run_summary()
	summary.merge(stats.summary())  # the two key sets are disjoint (tests/test_meta.gd)
	summary["tier"] = run_tier
	summary["run_kind"] = run_kind
	summary["date"] = Time.get_date_string_from_system(true)
	summary["score"] = int(RunStats.score(summary)["total"])
	summary["score_v"] = Content.RUN_SCORE_VERSION
	_run_summary = summary
	_recorded_for = game
	_run_unlocks = []
	_run_report = {}
	_daily_report = {}
	if _run_is_daily():
		# the key record_daily writes (the game's own seed), never seed_v
		_over_prev = {"daily": profile.daily_best.get(Profile.daily_key(summary.get("seed")), {}).duplicate()}
		_daily_report = profile.record_daily(summary)
	else:
		_over_prev = profile.bests_snapshot(String(summary.get("loadout", "tender")))
		profile.record_run(summary)
		_run_report = profile.last_report
		_run_unlocks = _run_report["unlocks"]  # "tier:N" first, then milestone ids
	profile.save(profile_path)
	_refresh_daily_info()  # a finished daily moves the streak
	if _run_save != null:
		_run_save.close()
		_run_save = null
	_archive_run()


# --- the end of a run (fun pass) -------------------------------------------------

## Forget the last game's ending: no beat, no lock, no sheet facts, and no
## record or "was" values. Called whenever a new game takes the screen.
func _reset_over() -> void:
	_over_ms = -1
	_over_for = null
	_over_info = {}
	_over_prev = {}
	_run_summary = {}
	_run_report = {}
	_run_unlocks = []
	_daily_report = {}
	_recorded_for = null


## Did the CURRENT game end in _act this session (so it has a beat and a lock)?
func _over_live() -> bool:
	return _over_ms >= 0 and _over_for == game


## Where the end of the run is: "" (not over), "beat" (the map stays up with
## the end banner), "fade" (the sheet fading in) or "sheet". A game that ended
## outside _act (set over by a test, or a resumed save) goes straight to the sheet.
func _over_phase(now: int = -1) -> String:
	if game == null or not game.over:
		return ""
	if not _over_live():
		return "sheet"
	var age := (Time.get_ticks_msec() if now < 0 else now) - _over_ms
	if age < OVER_BEAT_MS:
		return "beat"
	if age < OVER_BEAT_MS + OVER_FADE_MS:
		return "fade"
	return "sheet"


## Are taps and keys (but Back/ESC and MENU) still ignored after the end?
func _over_locked(now: int = -1) -> bool:
	if screen == "menu" or game == null or not game.over or not _over_live():
		return false
	return (Time.get_ticks_msec() if now < 0 else now) - _over_ms < OVER_LOCK_MS


## The live game just ended (from _act, after the step's own feedback): start
## the beat clock, clear every banner (the end banner owns the screen) and land
## three staggered bursts - gold on a win, red on a death - on the tender, or
## on a win on the boss's last tile.
func _begin_over(evs: Array, pre: Dictionary) -> void:
	_over_ms = Time.get_ticks_msec()
	_over_for = game
	_over_info = {}
	_banner = []
	_banner_q = []
	var won := bool(game.won)
	var p := Vector2(game.player["pos"])
	if won:
		for ev in evs:
			if String(ev.get("t", "")) == "death" \
					and Content.ENEMIES.get(String(ev.get("who", "")), {}).get("traits", []).has("boss"):
				p = Feedback.ev_pos(ev, pre, game)
	var t0 := _fx_now()
	for i in 3:
		_fx.append({"kind": "burst", "pos": p, "col": COL_GOLD if won else COL_RED, "t0": t0 + i * 260})
	if _fx.size() > 40:
		_fx = _fx.slice(_fx.size() - 40)  # the same cap _feedback keeps
	_shake(7.0 if won else 10.0)


## Is the ended game a daily (it has no unlocks and no NEXT, and RETRY DAILY)?
func _over_is_daily() -> bool:
	if screen == "tutorial":
		return false
	if _recorded_for == game and not _run_summary.is_empty():
		return String(_run_summary.get("run_kind", "career")) == "daily"
	return _game_is_run and _run_is_daily()


## The over sheet's buttons: explicit, never tap-anywhere. A daily keeps NEW
## RUN (a career run: run_kind made that safe) beside RETRY DAILY.
func _over_buttons() -> Array:
	if screen == "tutorial":
		return [["TUTORIAL AGAIN", "tutorial"], ["MENU", "menu"]]
	if _over_is_daily():
		return [["NEW RUN", "new_run"], ["RETRY DAILY", "retry_seed"], ["MENU", "menu"]]
	return [["NEW RUN", "new_run"], ["RETRY SEED", "retry_seed"], ["MENU", "menu"]]


## Every fact the beat and the sheet draw, in words (shell/run_end.gd), built
## once per ended game. A recorded run reads the summary it was filed with and
## the bests snapshotted BEFORE the record; a tutorial or a bare game builds
## the same summary unrecorded and shows no score, best, unlock, goal or seed.
func _build_over_info() -> Dictionary:
	_ensure_stats()
	var recorded: bool = _recorded_for == game and not _run_summary.is_empty()
	var summary: Dictionary
	if recorded:
		summary = _run_summary
	else:
		summary = game.run_summary()
		summary.merge(stats.summary())
		summary["tier"] = run_tier
		summary["score"] = int(RunStats.score(summary)["total"])
	var snap: Dictionary = game.snapshot()
	var tut := screen == "tutorial"
	var daily := _over_is_daily()
	var prev: Dictionary = _over_prev if recorded else {}
	var prev_floor := int(prev.get("daily", {}).get("floor", 0)) if daily else int(prev.get("best_floor", 0))
	var won := bool(snap["won"])
	var kit: Array = []
	var eff: Dictionary = summary.get("effective_uses_by_base", {})
	for aid in summary.get("kit", []):
		kit.append({"icon": _ability_icon(String(aid)), "count": int(eff.get(Content.base_id(String(aid)), 0)),
			"up": Content.is_upgrade(String(aid))})
	var chips: Array = []
	# the score record is the sheet's own NEW BEST line, so a chip repeating it
	# would take the top slot from a real highlight
	var recs: Array = (_run_report.get("records", []) as Array).filter(
		func(r): return not (r is Dictionary and String(r.get("key", "")) == "score")) if recorded else []
	for h in RunStats.highlights(summary, 3, recs):
		var ct := RunEnd.chip_text(h)
		if ct != "":
			chips.append(ct)
	var info := {
		"won": won, "tutorial": tut, "daily": daily,
		"banner": RunEnd.end_banner(summary, snap),
		"title": "THE FURNACE IS COLD" if won else "YOU DIED",
		"cause": RunEnd.cause_line(summary, snap),
		"near": RunEnd.near_miss_text(RunStats.near_miss(snap, summary, prev_floor)),
		"stats": RunEnd.stats_line(summary),
		"kit": kit, "grafts": RunEnd.grafts_line(summary), "chips": chips,
		"score": "", "score_parts": "", "best": ["", false], "floor_best": "",
		"unlocks": [], "next": "", "seed": "", "buttons": _over_buttons(),
	}
	if tut:
		return info
	var sc: Dictionary = RunStats.score(summary)
	info["score"] = RunEnd.score_title(sc)
	info["score_parts"] = RunEnd.score_parts_text(sc)
	info["best"] = RunEnd.best_line(summary, prev, daily, _daily_report if recorded else {})
	info["floor_best"] = RunEnd.floor_best_line(summary, prev, daily)
	if recorded and not daily:
		# the unlocks ("tier:N" first, then milestones), then the feats this
		# run earned ("FEAT  ·  <Name>") - _run_unlocks itself stays exactly
		# last_report.unlocks
		var ann: Array = _run_unlocks.duplicate()
		for fid in _run_report.get("feats", []):
			ann.append("feat:" + String(fid))
		info["unlocks"] = RunEnd.unlock_lines(ann, profile.unlocked_packages)
		var nxt: Array = _run_report.get("next", [])
		if not nxt.is_empty():
			info["next"] = RunEnd.next_goal_text(nxt[0])
	info["seed"] = RunEnd.seed_line(int(summary.get("seed", seed_v)), summary, daily, _config_line(snap))
	return info


## The sheet facts for the CURRENT game, built lazily (a game set over from
## outside _act has none yet, and a game swapped in drops the old ones).
func _over_info_now() -> Dictionary:
	if _over_for != game:
		_over_ms = -1
		_over_for = game
		_over_info = {}
	if _over_info.is_empty():
		_over_info = _build_over_info()
	return _over_info


## A finished run's action log is a replayable record, not litter: move it to
## runs_dir as run_<seed>_<yyyymmdd>_<won|died>.save and keep the newest
## RUNS_KEEP. tests/import_run.gd turns one into a regression pair.
func _archive_run() -> void:
	if not FileAccess.file_exists(run_save_path):
		return
	var d := Time.get_date_dict_from_system()
	var outcome := "won" if (game != null and game.won) else "died"
	var dest := "%s/run_%d_%04d%02d%02d_%s.save" % [
		runs_dir, seed_v, int(d["year"]), int(d["month"]), int(d["day"]), outcome]
	DirAccess.make_dir_recursive_absolute(runs_dir)
	if FileAccess.file_exists(dest):
		DirAccess.remove_absolute(dest)  # same seed, same day: the newer log wins
	if DirAccess.rename_absolute(run_save_path, dest) != OK:
		DirAccess.copy_absolute(run_save_path, dest)
	DirAccess.remove_absolute(run_save_path)  # no-op after a successful rename
	_save_head_dirty()
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
	if cf.load(cfg_path) == OK:
		hold_ms = int(cf.get_value("ui", "hold_ms", 420))
		# carried forward only while it still routes something (see _legacy_seed_mode)
		_legacy_seed_mode = str(cf.get_value("ui", "seed_mode", "random"))
		_legacy_notice = _legacy_seed_mode == "daily" \
			and not bool(cf.get_value("ui", "legacy_notice_seen", false))
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
	cf.set_value("ui", "intro_mode", intro_mode)
	cf.set_value("ui", "sfx_on", sfx_on)
	cf.set_value("ui", "music_on", music_on)
	cf.set_value("ui", "tier", sel_tier)
	cf.set_value("ui", "loadout", sel_loadout)
	cf.set_value("ui", "package", sel_package)
	cf.set_value("ui", "mutator", sel_mutator)
	if _legacy_seed_mode == "daily":
		cf.set_value("ui", "seed_mode", "daily")
		if not _legacy_notice:
			cf.set_value("ui", "legacy_notice_seen", true)
	cf.save(cfg_path)


func _act(a: Dictionary) -> void:
	if game == null or game.over:
		return
	_ensure_stats()  # before the step: a fold begun after it would miss the step's bloom
	var pre := _pre_step()
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
		_ensure_stats()
		var tctx: Dictionary = stats.feed(game, tevs)
		_danger_rev += 1  # the tutorial draws the forecast too, but never cues
		_arm_anim(pre["pos"], int(pre["floor"]))
		_feedback(tevs, pre, tctx)
		if game.over and not _over_live():
			_begin_over(tevs, pre)  # a tutorial death gets its beat too; nothing is recorded
			_over_info = _build_over_info()
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
	var pre_d: Dictionary = _danger_state()
	var evs: Array = game.step(a)
	if _game_is_run and _run_save != null:
		_run_save.store_line(var_to_str(a).replace("\n", " "))
		_run_save.flush()
	_ensure_stats()
	var ctx: Dictionary = stats.feed(game, evs)
	_danger_rev += 1
	# danger transitions (lethal switching on, the choke window): a warn tick
	# in the step's sound cap and, at choke 1, a banner (empty when over/draft)
	var cue: Dictionary = Danger.cues(pre_d, _danger_state(), _choke_cued)
	_choke_cued = int(cue["announced"])
	_arm_anim(pre["pos"], int(pre["floor"]))
	for ev in evs:
		if String(ev.get("t", "")) == "draft_offer":
			_draft_focus_spent = bool(ev.get("focus", false))
	_feedback(evs, pre, ctx, cue.get("sounds", []))
	if not Array(cue.get("banner", [])).is_empty():
		_push_banner(cue["banner"], Danger.COL_AMBER, int(Feedback.BANNER_PRIO["danger"]))
	# the end beat starts AFTER the step's own feedback (its bursts, its death
	# sound) and clears the banners it queued; the record runs between the two
	# so the sheet's facts read the bests from BEFORE it
	var ended: bool = game.over and not _over_live()
	if ended:
		_begin_over(evs, pre)
	if game.over and _game_is_run and not _run_recorded:
		_record_finished_run()
	if ended:
		_over_info = _build_over_info()
	mode = "normal"
	if keep_shop and game.player["pos"] == game.map["shrine"] and not game.shop.is_empty():
		mode = "shop"
	mode_targets = []
	flash = ""
	tooltip = []
	queue_redraw()


## Facts from BEFORE a step, for the feedback layer: where everything stood
## (the same dict _arm_anim slides from), what each enemy was, and the
## tender's numbers - a body that dies in the step is gone from game.enemies
## by the time its puff, ghost and log line are drawn.
func _pre_step() -> Dictionary:
	var pos := {"player": Vector2(game.player["pos"])}
	var kinds := {}
	for e in game.enemies:
		pos[e["id"]] = Vector2(e["pos"])
		kinds[e["id"]] = String(e["kind"])
	return {
		"pos": pos, "kinds": kinds, "bloom": int(game.bloom),
		"hp": int(game.player["hp"]), "max_hp": int(game.player["max_hp"]),
		"shield": int(game.player.get("shield", 0)),
		"floor": int(game.floor_num), "total_turns": int(game.total_turns),
	}


## Apply one step's feedback (shell/feedback.gd): map effects, shake, the
## hit-stop, the tender's lunge, banners, log lines and sounds. Returned so a
## test can read what the step produced.
func _feedback(evs: Array, pre: Dictionary, ctx: Dictionary, extra_sounds: Array = []) -> Dictionary:
	var res: Dictionary = Feedback.step(evs, pre, game, ctx, _fx_now(), extra_sounds)
	_fx.append_array(res["fx"])
	if _fx.size() > 40:
		_fx = _fx.slice(_fx.size() - 40)
	if float(res["shake"]) > 0.0:
		_shake(float(res["shake"]))
	if bool(res["hitstop"]):
		_hit_stop(Feedback.HITSTOP_MS)
	if Vector2(res["lunge"]) != Vector2.ZERO:
		_lunge_dir = res["lunge"]
		_lunge_ms = Time.get_ticks_msec()
		_lunge_hold = Feedback.HITSTOP_MS if bool(res["hitstop"]) else 0
	for b in res["banners"]:
		_push_banner(b["lines"], b["col"], int(b["prio"]))
	for ln in res["log"]:
		_log(String(ln["text"]), String(ln["cat"]))
	_play_picks(res["sounds"])
	return res


## The single append point of the event log: repeats count up ("x3") instead
## of vanishing, and both arrays keep the newest LOG_KEEP lines.
func _log(s: String, cat: String = "info") -> void:
	Feedback.log_push(log_lines, log_cats, s, cat)
	if log_lines.size() > LOG_KEEP:
		var cut := log_lines.size() - LOG_KEEP
		log_lines = log_lines.slice(cut)
		log_cats = log_cats.slice(cut)


## The one banner path: shows at once when no banner is live, else waits in a
## queue (priority first, then arrival; at most 3 waiting).
func _push_banner(lines: Array, col: Color = COL_GOLD, prio: int = 0) -> void:
	if lines.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - _banner_ms >= BANNER_MS or _banner.is_empty():
		_banner = lines.duplicate()
		_banner_col = col
		_banner_ms = now
		return
	var at := _banner_q.size()
	for i in _banner_q.size():
		if int(_banner_q[i]["prio"]) < prio:
			at = i
			break
	_banner_q.insert(at, {"lines": lines.duplicate(), "col": col, "prio": prio})
	if _banner_q.size() > 3:
		_banner_q.resize(3)


## From _process: the next queued banner takes over once the live one is done.
func _tick_banner() -> void:
	if _banner_q.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - _banner_ms < BANNER_MS:
		return
	var b: Dictionary = _banner_q.pop_front()
	_banner = b["lines"]
	_banner_col = b["col"]
	_banner_ms = now


## Play the feedback layer's sound picks: now, or (the chime) after its delay.
func _play_picks(picks: Array) -> void:
	if audio == null:
		return
	var now := Time.get_ticks_msec()
	for p in picks:
		if int(p.get("delay", 0)) <= 0:
			audio.play(String(p["id"]), float(p.get("pitch", 1.0)))
		else:
			_sfx_q.append({"id": String(p["id"]), "pitch": float(p.get("pitch", 1.0)), "at": now + int(p["delay"])})


## The fx clock: wall time minus every hit-stop so far, held still while one
## is running. Floats, callouts and the slide animation run on it, so a kill
## freezes them for a beat; input never waits on it.
func _fx_now() -> int:
	var t := Time.get_ticks_msec()
	if _freeze_start >= 0:
		if t < _freeze_end:
			return _freeze_start - _frozen_total
		_frozen_total += _freeze_end - _freeze_start
		_freeze_start = -1
	return t - _frozen_total


func _hit_stop(ms: int) -> void:
	_fx_now()  # settle an expired freeze
	var t := Time.get_ticks_msec()
	if _freeze_start >= 0:
		_freeze_end = maxi(_freeze_end, t + ms)
		return
	_freeze_start = t
	_freeze_end = t + ms


## The tender's lean into a strike, in tiles: out over LUNGE_OUT, held through
## the hit-stop, back over LUNGE_BACK (wall clock, a quarter tile at most).
func _lunge_off() -> Vector2:
	var dt := Time.get_ticks_msec() - _lunge_ms
	if _lunge_dir == Vector2.ZERO or dt < 0:
		return Vector2.ZERO
	var k := 0.0
	if dt < LUNGE_OUT:
		k = float(dt) / LUNGE_OUT
	elif dt < LUNGE_OUT + _lunge_hold:
		k = 1.0
	elif dt < LUNGE_OUT + _lunge_hold + LUNGE_BACK:
		k = 1.0 - float(dt - LUNGE_OUT - _lunge_hold) / LUNGE_BACK
	return _lunge_dir * 0.25 * k


## Compatibility wrapper: one step's sounds (computed even headless, where
## nothing plays), played and returned.
func _play_events(evs: Array, extra: Array = []) -> Array:
	var picks: Array = Feedback.step(evs, {}, game, {}, _fx_now(), extra)["sounds"]
	_play_picks(picks)
	return picks


## Compatibility wrapper: the map effects, shake and banners of a step with no
## fold context.
func _spawn_fx(evs: Array, prev: Dictionary) -> void:
	var res: Dictionary = Feedback.step(evs, {"pos": prev}, game, {}, _fx_now())
	_fx.append_array(res["fx"])
	if _fx.size() > 40:
		_fx = _fx.slice(_fx.size() - 40)
	if float(res["shake"]) > 0.0:
		_shake(float(res["shake"]))
	for b in res["banners"]:
		_push_banner(b["lines"], b["col"], int(b["prio"]))


## Best-known tile for an event's subject (Feedback.ev_pos).
func _fx_pos(ev: Dictionary, prev: Dictionary) -> Vector2:
	return Feedback.ev_pos(ev, {"pos": prev}, game)


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
	_anim_ms = _fx_now()


## Where to draw a creature right now: sliding from its previous tile for a
## beat after each step. Long jumps (teleports, dashes) snap instead.
func _anim_pos(key, cur: Vector2i) -> Vector2:
	var t := (_fx_now() - _anim_ms) / float(ANIM_MS)
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
		if mode == "settings" or mode == "daily" or mode == "career":
			var closed := mode
			mode = "normal"
			queue_redraw()
			return closed
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
	# delayed sounds (the combo chime) fire on the wall clock, menu or not
	if not _sfx_q.is_empty():
		var snow := Time.get_ticks_msec()
		var due: Array = _sfx_q.filter(func(q): return int(q["at"]) <= snow)
		if not due.is_empty():
			_sfx_q = _sfx_q.filter(func(q): return int(q["at"]) > snow)
			if audio != null:
				for q in due:
					audio.play(String(q["id"]), float(q["pitch"]))
	if screen == "menu":
		queue_redraw()  # spores drift across the title vista
		return
	if _held and tooltip.is_empty() and Time.get_ticks_msec() - _press_ms >= hold_ms:
		_show_tooltip(_press_pos)
	_tick_banner()
	var fxt := _fx_now()
	var animating: bool = fxt - _anim_ms < ANIM_MS + 40
	var smoggy: bool = game != null and not game.over and (int(game.smog) > 0 or int(game.dim) > 0)
	if not _fx.is_empty():
		_fx = _fx.filter(func(f): return fxt - int(f["t0"]) < int(f.get("dur", FX_MS)))
		animating = true
	if Time.get_ticks_msec() - _floor_fade_ms < 1450:
		animating = true
	if Time.get_ticks_msec() - _banner_ms < BANNER_MS + 50:
		animating = true
	if Time.get_ticks_msec() - _lunge_ms < LUNGE_OUT + _lunge_hold + LUNGE_BACK:
		animating = true
	if _freeze_start >= 0 or not _sfx_q.is_empty() or not _banner_q.is_empty():
		animating = true
	if game != null and not game.over and (String(_danger.get("hp", "ok")) != "ok"
			or Danger.sky_alert(_danger.get("sky", {})) != ""):
		animating = true  # danger vignette / lethal outline / amber sky pulse
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
	var dz := _danger_state()
	for e in snap["enemies"]:
		if e["pos"] == t:
			var row := _legend_of(e["kind"])
			lines.append("%s - hp %d%s" % [Names.ename(e["kind"]), e["hp"], "  ELITE" if e.get("elite", false) else ""])
			lines.append(_intent_words(e))
			lines.append_array(_danger_tip(e, dz))
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
		var fc: Dictionary = dz.get("fc", {})
		if int(fc.get("dmg", 0)) > 0:
			lines.insert(1, "ending here: %d incoming%s" % [int(fc["dmg"]),
				" - LETHAL" if bool(fc.get("dies", false)) else ""])
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
		if snap["map"]["vents"].has(t):
			# a vent under growth is sealed whatever the terrain row says
			if snap["terrain"].has(t) and String(snap["terrain"][t]["kind"]) == "growth":
				lines.append("sealed - absorbs the next release")
			else:
				var vin := int(dz.get("sky", {}).get("spawn_in", -1))
				if vin > 1:
					lines.append("releases in %d turns" % vin)
				elif vin == 1:
					lines.append("releases next turn")
	if lines.is_empty():
		return
	tooltip = lines
	tooltip_tile = t
	queue_redraw()


## What the danger layer adds to an enemy's tooltip: why its intent will not
## land (its telegraph entry's block), and for a stoker how much sooner it
## brings the choke (the smog walk with and without the stokers counted).
func _danger_tip(e: Dictionary, dz: Dictionary) -> Array:
	var out: Array = []
	for ent in dz.get("tele", {}).get("enemies", []):
		if ent["id"] != e["id"]:
			continue
		match String(ent["blocked"]):
			"stun":
				out.append("stunned - loses this action")
			"root":
				out.append("rooted - cannot move, advance or drag")
			"screened":
				out.append("lost in the smoke - it will miss you")
			"anchor":
				out.append("your anchor holds - the grapple fails")
		break
	# keyed on the ROW (the `stokes` trait), not the current intent: a slow
	# stoker on its idle turn still pulls the choke in. sky vs sky_calm removes
	# EVERY stoker at once, so with more than one alive the total is shared.
	if _is_stoker(String(e.get("kind", ""))):
		var c := int(dz.get("sky", {}).get("choke_in", -1))
		var calm := int(dz.get("sky_calm", {}).get("choke_in", -1))
		if c > 0 and calm > c:
			var n_stokers := 0
			for o in game.enemies:
				if _is_stoker(String(o["kind"])):
					n_stokers += 1
			if n_stokers > 1:
				out.append("stokers bring the choke %d turns sooner" % (calm - c))
			else:
				out.append("brings the choke %d turns sooner" % (calm - c))
	return out


func _is_stoker(kind: String) -> bool:
	return Content.ENEMIES.get(kind, {}).get("traits", []).has("stokes")


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
		elif mode == "daily":
			# the DAILY sheet takes ENTER as its own PLAY; ESC (above) closes it
			# and every other key is ignored
			if k == KEY_ENTER or k == KEY_SPACE:
				_tap(String(_daily_sheet(int(_daily_now()["seed"]))["play_tag"]))
		elif mode == "career":
			# LEFT / RIGHT page the CAREER sheet; ESC (above) closes it and
			# every other key is ignored - it must never start a run
			if k == KEY_LEFT:
				_career_turn(-1)
			elif k == KEY_RIGHT:
				_career_turn(1)
		elif k == KEY_ENTER or k == KEY_SPACE:
			_tap("play")
		return
	if _over_locked():
		return  # the end beat: a key still held from the last move must not skip it
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
		if screen == "tutorial":
			# a tutorial death retries the tutorial; there is no "next seed"
			if k == KEY_R:
				_tap("tutorial")
			return
		if k == KEY_R:
			_start_run(run_kind, seed_v)  # retry: a daily retry is another try
		elif k == KEY_N:
			_start_run("career", seed_v + 1)
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
			if screen == "tutorial":
				_tap("tutorial")  # mid-tutorial R restarts it, as a tutorial death's R does
				return
			_start_run(run_kind, seed_v)
		KEY_N:
			if screen == "tutorial":
				return  # no "next seed" in the tutorial: N must not leave it for a run
			_start_run("career", seed_v + 1)


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
		if not _guard_lets_end():
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
		if not _guard_lets_end():
			return
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
		# a sheet over the menu (settings, daily) closes on an off-button tap
		# for settings; the DAILY sheet takes only its own buttons
		if mode == "settings":
			mode = "normal"
			queue_redraw()
		return
	if _over_locked():
		return  # the end beat and the first moments of the sheet take no taps
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
		# no tap-anywhere: a new run starts only from the sheet's own buttons
		# (the hotspots above), so a stray tap can never throw a result away
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
				if _guard_lets_end():
					_act({"type": "end_turn"})
			elif absi(t.x - pp.x) + absi(t.y - pp.y) == 1:
				_move_or_strike(t - pp)


func _tap(tag: String) -> void:
	if _over_locked() and tag != "menu":
		return  # MENU (Back's own path) is the one tap the end beat lets through
	if audio != null:
		audio.play("tap")
	var play_armed := _play_armed
	_play_armed = false
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
		if not play_armed and String(_resumable_run().get("kind", "")) == "daily":
			_play_armed = true  # a daily try in progress: PLAY asks for a second tap
			queue_redraw()
		else:
			_start_run("career")
	elif tag == "daily":
		if _legacy_notice:
			_legacy_notice = false
			_save_settings()  # the notice is said once, not once per boot
		_refresh_daily_info()
		_daily_armed = false
		mode = "daily"
		queue_redraw()
	elif tag == "daily_play":
		if not _daily_armed and _daily_play_abandons(int(_daily_now()["seed"])):
			_daily_armed = true  # the sheet now asks for a second tap
			queue_redraw()
		else:
			_daily_armed = false
			_start_run("daily")
	elif tag == "career":
		career_tab = "goals"
		career_page = 0
		_career_fresh = []
		mode = "career"
		queue_redraw()
	elif tag.begins_with("career_tab:"):
		_career_select(tag.get_slice(":", 1))
	elif tag.begins_with("career_page:"):
		_career_turn(tag.get_slice(":", 1).to_int())
	elif tag == "daily_resume":
		mode = "normal"  # the sheet closes behind the resumed try
		_tap("resume")
	elif tag == "resume":
		if (game == null or not _game_is_run or game.over) and FileAccess.file_exists(run_save_path):
			_load_run()  # the live run was displaced (e.g. by the tutorial)
		if game != null and not game.over and _game_is_run:
			screen = "game"
			queue_redraw()
	elif tag == "tutorial":
		_start_tutorial()
	elif tag == "new_run":
		_start_run("career")  # NEW RUN is always a career run, even off a daily
	elif tag == "retry_seed":
		_start_run(run_kind, seed_v)  # the same seed again (a daily retry is another try)
	elif tag == "settings":
		mode = "settings"
		queue_redraw()
	elif tag == "menu":
		screen = "menu"
		mode = "normal"
		tooltip = []
		_daily_now()
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
				_seen("tier:%d" % sel_tier)
			"loadout":
				sel_loadout = String(_cycle(profile.available_loadouts(), sel_loadout))
				_seen(sel_loadout)
			"package":
				sel_package = String(_cycle(_with_none(profile.unlocked_packages), sel_package))
				_seen(sel_package)
			"mutator":
				sel_mutator = String(_cycle(_with_none(profile.unlocked_mutators), sel_mutator))
				_seen(sel_mutator)
			"hold":
				hold_ms = {300: 420, 420: 650, 650: 300}.get(hold_ms, 420)
			"intro":
				intro_mode = {"once": "always", "always": "never", "never": "once"}.get(intro_mode, "once")
		_save_settings()
		queue_redraw()


## The player cycled onto `id`: its NEW badge goes, and the profile is saved
## only when that changed something.
func _seen(id: String) -> void:
	if id != "" and profile.mark_seen(id):
		profile.save(profile_path)


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


## The title screen's rows as data: [label, tap tag, highlighted, badge,
## group]. Rows that share a non-empty group share one line (DAILY / CAREER;
## TUTORIAL / SETTINGS / QUIT share the last). `badge` is drawn small and gold
## at the row's right edge: NEW while the career has something on that row
## the player has not cycled onto (or, for CAREER, looked at) yet, and on the
## LOADOUT row a WON / WON D<n> for the selected loadout. Built
## here so a headless test reads exactly what the menu offers.
func _menu_rows() -> Array:
	var rows: Array = []
	var has_resume: bool = (game != null and not game.over and _game_is_run) \
		or FileAccess.file_exists(run_save_path)
	if has_resume:
		rows.append(["RESUME RUN", "resume", true, "", ""])
	rows.append(["TAP AGAIN TO ABANDON" if _play_armed else "PLAY", "play", true, "", ""])
	var di := _daily_now()
	rows.append(["DAILY", "daily", not bool(di["streak"]["played_today"]), "", "a"])
	rows.append(["CAREER", "career", false, _new_badge("feat"), "a"])
	if int(profile.unlocked_tier) > 0:
		var tn := "base run" if sel_tier == 0 else String(Content.TIERS[sel_tier - 1]["name"])
		rows.append(["DIFFICULTY %d: %s" % [sel_tier, tn], "set:tier", false,
			_new_badge("tier"), ""])
	var lbadge := _new_badge("loadout")
	if lbadge == "":
		var won_tier := int(profile.records["loadouts"].get(sel_loadout, {}).get("best_tier_won", -1))
		if won_tier >= 1:
			lbadge = "WON D%d" % won_tier
		elif won_tier == 0:
			lbadge = "WON"
	rows.append(["LOADOUT: %s" % Names.choice_name("loadout", sel_loadout), "set:loadout", false, lbadge, ""])
	rows.append(["PACKAGE: %s" % _package_name(sel_package), "set:package", false, _new_badge("package"), ""])
	rows.append(["MUTATOR: %s" % Names.choice_name("mutator", sel_mutator), "set:mutator", false,
		_new_badge("mutator"), ""])
	rows.append(["TUTORIAL", "tutorial", false, "", "b"])
	rows.append(["SETTINGS", "settings", false, "", "b"])
	rows.append(["QUIT", "quit", false, "", "b"])
	return rows


func _new_badge(kind: String) -> String:
	return "NEW" if not profile.unseen_of(kind).is_empty() else ""


## A package's display name: Profile.unlock_name, the one source the unlock
## text and the DAILY sheet share ("none" for no package).
static func _package_name(id: String) -> String:
	return "none" if id == "" else Profile.unlock_name(id)


## Where every menu row lands, as data (_draw_menu draws this and nothing
## else, and tests/test_shell.gd holds every label to a readable size at every
## phone shape): [{rect, label, tag, gold, badge, size, badge_size}]. The
## block is 0.80vw wide - at the old 0.62vw a long DIFFICULTY name with a
## badge shrank to ~1.06% of the screen height - the rows fill the space
## between the title art and the footer, and a grouped line splits its width.
func _menu_layout(vw: float, vh: float) -> Array:
	var rows: Array = _menu_rows()
	var lines: Array = []
	for row in rows:
		var grp := String(row[4])
		if grp != "" and not lines.is_empty() and String(lines[-1][0][4]) == grp:
			lines[-1].append(row)
		else:
			lines.append([row])
	var top := vh * 0.46
	var bottom := vh * 0.935
	var gap := vh * 0.016
	var n := lines.size()
	var bh := minf(vh * 0.072, (bottom - top - gap * (n - 1)) / n)
	var bw := vw * 0.80
	var bx := (vw - bw) / 2.0
	var cgap := vw * 0.02
	var y := top + (bottom - top - (bh * n + gap * (n - 1))) / 2.0
	# the badge is the only word that names an unlock here: held to the card floor
	var bsz := maxi(int(bh * 0.24), ceili(vh * 0.0115))
	var out: Array = []
	for line in lines:
		var k: int = line.size()
		var cw := (bw - cgap * (k - 1)) / k
		for i in k:
			var row: Array = line[i]
			var r := Rect2(bx + i * (cw + cgap), y, cw, bh)
			var badge := String(row[3])
			var badge_w := 0.0
			if badge != "":
				badge_w = font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, bsz).x + bh * 0.2
			out.append({"rect": r, "label": String(row[0]), "tag": String(row[1]), "gold": bool(row[2]),
				"badge": badge, "size": _fit_size(String(row[0]), int(bh * 0.38), cw * 0.92 - badge_w),
				"badge_size": bsz, "badge_w": badge_w})
		y += bh + gap
	return out


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
	_flash_red = false
	queue_redraw()


## A guard refusal: the same context-line slot as _flash, drawn red.
func _flash_danger(msg: String) -> void:
	flash = msg
	_flash_red = true
	queue_redraw()


# --- event log in words -------------------------------------------------------

## One event in words, context-free (Feedback.ev_text: the log's templates).
func _ev_text(ev: Dictionary) -> String:
	return Feedback.ev_text(ev, game)


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


## The red tiles: {tile: summed damage} straight from the sim's own
## Game.telegraph() (via the danger cache), so a stunned, rooted or screened
## attacker paints nothing - the old shell-side mirror ignored statuses and
## painted a false red tile under every stunned striker. `snap` is unused and
## kept for the callers' signature.
func _threat_tiles(_snap: Dictionary) -> Dictionary:
	return _danger_state().get("tele", {}).get("tiles", {})


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
		elif mode == "daily":
			_draw_daily(vw, vh)
		elif mode == "career":
			_draw_career(vw, vh)
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
		if _over_phase() == "beat":
			_draw_over_beat(vw, vh)
		else:
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
	elif _legacy_notice:
		# the old settings toggle is gone; say once where the daily went
		_txt_c_fit(vw / 2.0, vh * 0.228, "the daily now has its own button",
			COL_GOLD, int(vh * 0.019), vw * 0.9)

	# the rows are data first (_menu_layout), sized to the space above the footer
	_clamp_selection()
	for m in _menu_layout(vw, vh):
		var r: Rect2 = m["rect"]
		_box(r, _sb_gold if bool(m["gold"]) else _sb)
		var fs2 := int(m["size"])
		var bw_: float = float(m["badge_w"])
		_txt_c((r.position.x + r.end.x - bw_) / 2.0, r.get_center().y + fs2 * 0.35,
			String(m["label"]), COL_TEXT, fs2)
		if String(m["badge"]) != "":
			var bsz := int(m["badge_size"])
			var tw := font.get_string_size(String(m["badge"]), HORIZONTAL_ALIGNMENT_LEFT, -1, bsz).x
			_txt(Vector2(r.end.x - tw - r.size.y * 0.12, r.get_center().y + bsz * 0.35),
				String(m["badge"]), COL_GOLD, bsz)
		_hot(r, String(m["tag"]))
	if int(profile.runs) > 0:
		_txt_c_fit(vw / 2.0, vh * 0.972, "runs %d  ·  wins %d  ·  best floor %d  ·  feats %d/%d" % [
			profile.runs, profile.wins, profile.best_floor, profile.feats.size(), Content.FEATS.size()],
			COL_DIM_TEXT, int(vh * 0.016), vw * 0.92)


## The settings sheet's toggles as data: [label, tap tag]. (The old "Run
## seed" toggle is gone - PLAY is always a career run and the daily is the
## menu's DAILY entry.)
func _settings_rows() -> Array:
	var names := {300: "short", 420: "normal", 650: "long"}
	return [
		["Hold delay:  %s" % names.get(hold_ms, "normal"), "set:hold"],
		["Intro tips:  %s" % intro_mode, "set:intro"],
		["Sound effects:  %s" % ("on" if sfx_on else "off"), "set:sfx"],
		["Music:  %s" % ("on" if music_on else "off"), "set:music"],
	]


func _draw_settings(vw: float, vh: float) -> void:
	hotspots.clear()
	var y := _sheet(vw, vh, "SETTINGS")
	var bw := vw * 0.88
	var bh := vh * 0.08
	for row in _settings_rows():
		_button(Rect2(vw * 0.06, y, bw, bh), String(row[0]), String(row[1]), int(bh * 0.3))
		y += bh + vh * 0.025
	y += vh * 0.005
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


## The DAILY sheet as data, for `seed_v` (today's daily seed in the app; any
## seed in the tests): {head, cards: [[icon, name, desc, tag, badge]], result,
## streak, note, play, play_tag} - play_tag "daily_resume" (label RESUME
## TODAY'S TRY) while a try on that seed is still resumable, else
## "daily_play". The cards are the day's loadout, package and mutator,
## straight off Profile.daily_config (the frozen lists, so an old date never
## changes); the lines are what the profile filed for that seed - the first
## finish is the RANKED one and every later finish only improves the best.
func _daily_sheet(seed_v: int) -> Dictionary:
	var d: Dictionary = Profile.daily_config(seed_v)
	var di := _daily_now()
	var when := String(di["date"]) if int(di["seed"]) == seed_v else "seed %d" % seed_v
	var cards: Array = []
	var lid := String(d["loadout"])
	var ldef: Dictionary = Content.LOADOUTS[lid]
	cards.append([_ability_icon(String(ldef["kit"][0])), String(ldef["name"]), String(ldef["desc"]), "", "LOADOUT"])
	var pkg := String(d["package"])
	if pkg != "":
		var anames: Array = []
		for aid in Content.PACKAGES[pkg]:
			anames.append(Names.aname(aid))
		cards.append([_ability_icon(String(Content.PACKAGES[pkg][0])), _package_name(pkg),
			"%s  ·  %s" % [Content.PACKAGE_INFO[pkg]["desc"], ", ".join(anames)], "", "PACKAGE"])
	var mut := String(d["mutator"])
	if mut != "":
		cards.append(["ic_mutator", String(Content.MUTATORS[mut]["name"]),
			String(Content.MUTATORS[mut]["desc"]), "", "MUTATOR"])
	var key := Profile.daily_key(seed_v)
	var tries := int(profile.daily_tries.get(key, 0))
	var best: Dictionary = profile.daily_best.get(key, {})
	var first: Dictionary = profile.daily_first.get(key, best)
	var result := ""
	if best.is_empty():
		if tries == 0:
			result = "No finish yet  ·  your first finish is your ranked result"
		else:
			result = "%d %s, no finish yet" % [tries, "try" if tries == 1 else "tries"]
	else:
		result = "ranked: %s  ·  best: %s  ·  %d %s" % [_daily_result_text(first), _daily_result_text(best),
			maxi(tries, 1), "try" if maxi(tries, 1) == 1 else "tries"]
	var resume := _daily_try_live(seed_v)
	# a fresh start overwrites the one run save: another resumable run (a
	# career run, or an older daily) is lost unrecorded, so the sheet says so
	# and PLAY takes a second tap
	var abandons := not resume and _daily_play_abandons(seed_v)
	var play := "RESUME TODAY'S TRY" if resume else ("PLAY TODAY'S RUN" if best.is_empty() else "PLAY AGAIN  ·  unranked")
	if abandons and _daily_armed:
		play = "TAP AGAIN TO ABANDON"
	var st: Dictionary = di["streak"]
	var streak := "finish today's run to start a streak"
	if int(st["current"]) >= 1:
		streak = "streak %d day%s  ·  longest %d" % [int(st["current"]), "" if int(st["current"]) == 1 else "s",
			int(st["longest"])]
	elif int(st["longest"]) >= 1:
		streak = "streak broken  ·  longest %d" % int(st["longest"])
	return {
		"head": "%s  ·  the same run for everyone" % when,
		"cards": cards, "result": result, "streak": streak,
		"note": "starting this abandons your unfinished run" if abandons else "dailies never count toward your career",
		"note_warn": abandons,
		# a try still in progress is resumed, never thrown away by a fresh start
		"play": play,
		"play_tag": "daily_resume" if resume else "daily_play",
		"finished": not best.is_empty(), "streak_on": int(st["current"]) >= 1,
	}


## True while a daily try on `seed` is still resumable: the live run, or - when
## the live game is not a run (the tutorial displaced it) - the run save's own
## header. The DAILY sheet then offers RESUME instead of a fresh start, which
## would overwrite the save and count a second try.
func _daily_try_live(seed: int) -> bool:
	var r := _resumable_run()
	return String(r.get("kind", "")) == "daily" and int(r.get("seed", -1)) == seed


## True when starting `seed`'s daily would throw away another resumable run
## (a career run, or a daily on another seed) - the start overwrites the save.
func _daily_play_abandons(seed: int) -> bool:
	return not _resumable_run().is_empty() and not _daily_try_live(seed)


## The run a RESUME would bring back, as {kind, seed}, or {} when there is
## none: the live run, or - when the live game is not a run (the tutorial
## displaced it) - the run save's cached header.
func _resumable_run() -> Dictionary:
	if game != null and _game_is_run and not game.over:
		return {"kind": run_kind, "seed": seed_v}
	var head := _save_head()
	if head.is_empty():
		return {}
	var kind = head.get("kind", "daily" if _legacy_seed_mode == "daily" else "career")
	return {"kind": str(kind), "seed": int(head.get("seed", -1))}


## The run save's header, read once per write (see _save_head_cache).
func _save_head() -> Dictionary:
	if _save_head_path == run_save_path:
		return _save_head_cache
	_save_head_path = run_save_path
	_save_head_cache = {}
	if FileAccess.file_exists(run_save_path):
		var f := FileAccess.open(run_save_path, FileAccess.READ)
		if f != null:
			var head = str_to_var(f.get_line())
			f.close()
			if head is Dictionary and int(head.get("v", -1)) == RUN_SAVE_VERSION:
				_save_head_cache = head
	return _save_head_cache


## The run save was written or removed: the next _save_head reads it afresh.
func _save_head_dirty() -> void:
	_save_head_path = ""


static func _daily_result_text(r: Dictionary) -> String:
	if bool(r.get("won", false)):
		return "won in %d turns" % int(r.get("turns", 0))
	return "floor %d" % int(r.get("floor", 0))


## Where the DAILY sheet's pieces land, as data (_draw_daily draws it;
## tests/test_shell.gd checks every size and the button row at every phone
## shape): {lines: [{text, x, y, size, col}], cards: [{rect, row}],
## buttons: [{rect, label, tag, size, gold}]}. The button row goes through
## _sheet_button_y like every sheet's trailing row.
func _daily_layout(vw: float, vh: float, info: Dictionary) -> Dictionary:
	var y := vh * 0.16
	var w := vw * 0.88
	var lines: Array = []
	var spec := [
		[String(info["head"]), 0.022, COL_CREAM, 0.03],
		[String(info["result"]), 0.021, COL_GOLD if bool(info["finished"]) else COL_TEXT, 0.038],
		[String(info["streak"]), 0.021, COL_GOLD if bool(info["streak_on"]) else COL_TEXT, 0.036],
		[String(info["note"]), 0.018, COL_RED if bool(info.get("note_warn", false)) else COL_DIM_TEXT, 0.034],
	]
	for sp in spec:
		y += vh * float(sp[3])
		lines.append({"text": sp[0], "x": vw / 2.0, "y": y,
			"size": _fit_size(String(sp[0]), int(vh * float(sp[1])), w), "col": sp[2]})
	y += vh * 0.03
	var ch := vh * 0.105
	var cards: Array = []
	for c in info["cards"]:
		cards.append({"rect": Rect2(vw * 0.05, y, vw * 0.9, ch), "row": c})
		y += ch + vh * 0.015
	y += vh * 0.01
	var bh := vh * 0.065
	var by := _sheet_button_y(y, bh, vh)
	var buttons: Array = []
	for b in [[Rect2(vw * 0.06, by, vw * 0.30, bh), "BACK", "close", false],
			[Rect2(vw * 0.40, by, vw * 0.54, bh), String(info["play"]), String(info.get("play_tag", "daily_play")), true]]:
		var br: Rect2 = b[0]
		buttons.append({"rect": br, "label": b[1], "tag": b[2], "gold": b[3],
			"size": _fit_size(String(b[1]), int(bh * 0.34), br.size.x * 0.92)})
	return {"lines": lines, "cards": cards, "buttons": buttons}


func _draw_daily(vw: float, vh: float) -> void:
	hotspots.clear()
	_sheet(vw, vh, "DAILY CHALLENGE")
	var L := _daily_layout(vw, vh, _daily_sheet(int(_daily_now()["seed"])))
	for ln in L["lines"]:
		_txt_c(float(ln["x"]), float(ln["y"]), String(ln["text"]), ln["col"], int(ln["size"]))
	for c in L["cards"]:
		var row: Array = c["row"]
		_card(c["rect"], String(row[0]), String(row[1]), String(row[2]), String(row[3]), vh, String(row[4]))
	for b in L["buttons"]:
		var br: Rect2 = b["rect"]
		_box(br, _sb_gold if bool(b["gold"]) else _sb)
		var fs := int(b["size"])
		_txt_c(br.get_center().x, br.get_center().y + fs * 0.35, String(b["label"]), COL_TEXT, fs)
		_hot(br, String(b["tag"]))


# --- the CAREER sheet (fun pass) ---------------------------------------------------

## Switch the CAREER sheet to tab `t` (page 0). Opening FEATS is looking at
## the feats, so every "feat:" NEW badge goes - remembered in _career_fresh so
## the cards themselves still say NEW this visit - and the profile is saved
## only when that changed something.
func _career_select(t: String) -> void:
	if not CAREER_TABS.has(t):
		return
	career_tab = t
	career_page = 0
	if t == "feats":
		var fresh: Array = profile.unseen_of("feat")
		if not fresh.is_empty():
			for id in fresh:
				if not _career_fresh.has(id):
					_career_fresh.append(id)
				profile.mark_seen(String(id))
			profile.save(profile_path)
	queue_redraw()


## Page the CAREER sheet by `d`, clamped to its pages.
func _career_turn(d: int) -> void:
	var pages := int(_career_cards(career_tab, 0)["pages"])
	career_page = clampi(career_page + d, 0, pages - 1)
	queue_redraw()


## The CAREER sheet's head line.
func _career_head() -> String:
	return "runs %d  ·  wins %d  ·  best floor %d  ·  feats %d/%d" % [profile.runs, profile.wins,
		profile.best_floor, profile.feats.size(), Content.FEATS.size()]


## The icon an unlock id wears: a loadout or package by its first ability, a
## mutator, difficulty or feat by its own glyph.
func _unlock_icon(id: String) -> String:
	match Profile.unlock_kind(id):
		"loadout":
			return _ability_icon(String(Content.LOADOUTS[id]["kit"][0]))
		"package":
			return _ability_icon(String(Content.PACKAGES[id][0]))
		"mutator":
			return "ic_mutator"
		"tier":
			return "ic_tier"
		"feat":
			return "ic_feat"
	return "ab_default"


## A milestone row's desc ("" off the table).
static func _milestone_desc(id: String) -> String:
	for m in Content.MILESTONES:
		if String(m["id"]) == id:
			return String(m.get("desc", ""))
	return ""


## "1 win" / "3 wins".
static func _plural(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


## The first package loadout `lid` still waits on, as an id ("" when none).
func _gate_pkg(lid: String) -> String:
	for pkg in Content.LOADOUTS.get(lid, {}).get("requires", {}).get("packages", []):
		if not profile.unlocked_packages.has(pkg):
			return String(pkg)
	return ""


## Where a record was set: "run 12  ·  Tender  ·  difficulty 2".
static func _record_where(r: Dictionary) -> String:
	var parts: Array = ["run %d" % int(r.get("run", 0))]
	var lid := String(r.get("loadout", ""))
	if Content.LOADOUTS.has(lid):
		parts.append(String(Content.LOADOUTS[lid]["name"]))
	var t := int(r.get("tier", 0))
	parts.append("difficulty %d" % t if t > 0 else "base run")
	return "  ·  ".join(parts)


## The CAREER sheet as data, one tab and page at a time: {cards: [[icon, name,
## desc, tag, badge, frac]], pages, page, tab}. `frac` (0..1) is the progress
## bar drawn under the card; -1 draws none. Tabs:
##   goals    the difficulty ladder, then every milestone - unowned ranked by
##            Profile.goal_rows (the next_goals rank), owned last as DONE
##   feats    every Content.FEATS row in table order: NEW / EARNED (with the
##            run that earned it) or its progress
##   records  Profile.RECORD_SHOW, one card per loadout, the daily streak
## The page is clamped, so a stale career_page never reads past the end.
func _career_cards(tab: String, page: int) -> Dictionary:
	var cards: Array = []
	match tab:
		"feats":
			for fid in Content.FEATS:
				var row: Dictionary = Content.FEATS[fid]
				if profile.feats.has(fid):
					var fresh: bool = _career_fresh.has("feat:" + fid) or profile.unseen.has("feat:" + fid)
					cards.append(["ic_feat", String(row["name"]),
						"%s  ·  run %d" % [row["desc"], int(profile.feats[fid]["run"])], "",
						"NEW" if fresh else "EARNED", 1.0])
				else:
					var fp: Dictionary = profile.feat_progress(fid)
					cards.append(["ic_feat", String(row["name"]), String(row["desc"]), "",
						String(fp["text"]) if int(fp["need"]) > 1 else "", float(fp["frac"])])
		"records":
			var best: Dictionary = profile.records["best"]
			for rs in Profile.RECORD_SHOW:
				var key := String(rs[0])
				if best.has(key):
					var r: Dictionary = best[key]
					var where := _record_where(r)
					cards.append(["ic_feat", String(rs[1]),
						("turns  ·  " + where) if key == "fastest_win" else where, "",
						"%d" % int(r["v"]), -1.0])
				else:
					cards.append(["ic_feat", String(rs[1]), "no record yet", "", "-", -1.0])
			for lid in Content.LOADOUTS:
				var ld: Dictionary = Content.LOADOUTS[lid]
				var lr: Dictionary = profile.records["loadouts"].get(lid, {})
				var unlocked: bool = lid == "tender" or profile.unlocked_loadouts.has(lid)
				var badge := ""
				var desc := ""
				var n_runs := int(lr.get("runs", 0))
				if not unlocked:
					badge = "LOCKED"
					desc = _milestone_desc(lid)
				else:
					var bt := int(lr.get("best_tier_won", -1))
					if bt >= 1:
						badge = "WON D%d" % bt
					elif bt == 0:
						badge = "WON"
					elif n_runs > 0:
						badge = "FLOOR %d" % int(lr.get("best_floor", 0))
					if n_runs > 0:
						desc = "best score %d  ·  best floor %d  ·  %s in %s" % [int(lr.get("best_score", 0)),
							int(lr.get("best_floor", 0)), _plural(int(lr.get("wins", 0)), "win", "wins"),
							_plural(n_runs, "run", "runs")]
					else:
						desc = "not played yet"
					var gp := _gate_pkg(lid)
					if gp != "":
						desc += "  ·  needs %s: %s" % [Profile.unlock_name(gp), _milestone_desc(gp)]
				cards.append([_unlock_icon(lid), String(ld["name"]), desc, "", badge, -1.0])
			var st: Dictionary = _daily_now()["streak"]
			cards.append(["ic_feat", "Daily streak", "longest %d  ·  %s finished" % [int(st["longest"]),
				_plural(int(st["days"]), "daily", "dailies")], "", "%d" % int(st["current"]), -1.0])
		_:
			var u := int(profile.unlocked_tier)
			var nt := Content.TIERS.size()
			var ladder := ""
			if u == 0:
				ladder = "Shut down the Furnace to open difficulty 1"
			elif u < nt:
				ladder = "next: win at difficulty %d to open %s" % [u, Content.TIERS[u]["name"]]
			else:
				ladder = "every difficulty is open"
				for lid in profile.records["loadouts"]:
					if int(profile.records["loadouts"][lid]["best_tier_won"]) >= nt:
						ladder += "  ·  won at %d" % nt
						break
			cards.append(["ic_tier", "Difficulty ladder", ladder, "", "%d/%d" % [u, nt], float(u) / float(nt)])
			for e in profile.goal_rows():
				var id := String(e["id"])
				var pr: Dictionary = e["p"]
				var kind := Profile.unlock_kind(id)
				var nm := Profile.unlock_name(id)
				var desc := "%s  ·  %s" % [e["row"].get("desc", ""), kind]
				if bool(e["owned"]):
					var gp := _gate_pkg(id) if kind == "loadout" else ""
					if gp != "":
						nm += " (needs %s)" % Profile.unlock_name(gp)
						desc += "  ·  needs %s: %s" % [Profile.unlock_name(gp), _milestone_desc(gp)]
					cards.append([_unlock_icon(id), nm, desc, "", "DONE", 1.0])
				else:
					var binary: bool = ["won_with", "wins_without"].has(String(pr["key"]))
					if String(pr["hint"]) != "":
						desc += "  ·  " + String(pr["hint"])
					cards.append([_unlock_icon(id), nm, desc, "",
						"" if binary else "%d/%d" % [int(pr["have"]), int(pr["need"])], float(pr["frac"])])
	var pages := maxi(1, ceili(float(cards.size()) / CARDS_PER_PAGE))
	var pg := clampi(page, 0, pages - 1)
	return {"cards": cards.slice(pg * CARDS_PER_PAGE, (pg + 1) * CARDS_PER_PAGE), "pages": pages,
		"page": pg, "tab": tab}


## Where the CAREER sheet's pieces land, as data (_draw_career draws it;
## tests/test_shell.gd holds the sizes and the geometry at every phone shape):
## {head: {text, x, y, size}, tabs: [{rect, label, tag, active, size}],
## cards: [{rect, row}], bars: [{track, fill}], buttons: [{rect, label, tag,
## size, gold}]}. Five cards of 0.105vh from 0.27vh end at 0.855vh; each
## progress bar sits in the GAP under its card (inside it, it would cut the
## description's descenders) and the trailing row goes through
## _sheet_button_y - which leaves no room for a page line above it, so the
## page count rides in the BACK label ("BACK  ·  2/4").
func _career_layout(vw: float, vh: float, info: Dictionary) -> Dictionary:
	var y := vh * 0.16
	var head := _career_head()
	var out := {"head": {"text": head, "x": vw / 2.0, "y": y + vh * 0.025,
		"size": _fit_size(head, int(vh * 0.022), vw * 0.88)}}
	y += vh * 0.04
	var tw := vw * 0.28
	var tgap := vw * 0.03
	var th := vh * 0.055
	var tx := (vw - (tw * 3.0 + tgap * 2.0)) / 2.0
	var tabs: Array = []
	var new_feats: bool = not profile.unseen_of("feat").is_empty()
	for i in CAREER_TABS.size():
		var t := String(CAREER_TABS[i])
		var label := t.to_upper()
		if t == "feats" and new_feats:
			label += " NEW"
		var r := Rect2(tx + i * (tw + tgap), y, tw, th)
		tabs.append({"rect": r, "label": label, "tag": "career_tab:" + t,
			"active": t == String(info.get("tab", career_tab)), "size": _fit_size(label, int(th * 0.4), tw * 0.9)})
	out["tabs"] = tabs
	y += vh * 0.07
	var ch := vh * 0.105
	var cards: Array = []
	var bars: Array = []
	for c in info["cards"]:
		var r := Rect2(vw * 0.05, y, vw * 0.9, ch)
		cards.append({"rect": r, "row": c})
		var frac := float(c[5])
		if frac >= 0.0:
			var track := Rect2(r.position.x + ch * 0.25, r.end.y + vh * 0.003, r.size.x - ch * 0.5, vh * 0.006)
			var fill := track
			fill.size.x = track.size.x * clampf(frac, 0.0, 1.0)
			bars.append({"track": track, "fill": fill})
		y += ch + vh * 0.015
	out["cards"] = cards
	out["bars"] = bars
	# the button row sits where five cards end, whatever this page holds
	y = vh * (0.27 + 5 * 0.105 + 5 * 0.015) + vh * 0.005
	var bh := vh * 0.065
	var by := _sheet_button_y(y, bh, vh)
	var pages := int(info.get("pages", 1))
	var pg := int(info.get("page", 0))
	var back := "BACK" if pages <= 1 else "BACK  ·  %d/%d" % [pg + 1, pages]
	var specs: Array = []
	if pg > 0:
		specs.append([Rect2(vw * 0.06, by, vw * 0.18, bh), "<", "career_page:-1", false])
	specs.append([Rect2(vw * 0.27, by, vw * 0.46, bh), back, "close", true])
	if pg < pages - 1:
		specs.append([Rect2(vw * 0.76, by, vw * 0.18, bh), ">", "career_page:+1", false])
	var buttons: Array = []
	for b in specs:
		var br: Rect2 = b[0]
		buttons.append({"rect": br, "label": b[1], "tag": b[2], "gold": b[3],
			"size": _fit_size(String(b[1]), int(bh * 0.34), br.size.x * 0.92)})
	out["buttons"] = buttons
	return out


func _draw_career(vw: float, vh: float) -> void:
	hotspots.clear()
	_sheet(vw, vh, "CAREER")
	var info := _career_cards(career_tab, career_page)
	career_page = int(info["page"])
	var L := _career_layout(vw, vh, info)
	var hd: Dictionary = L["head"]
	_txt_c(float(hd["x"]), float(hd["y"]), String(hd["text"]), COL_CREAM, int(hd["size"]))
	for t in L["tabs"]:
		var tr: Rect2 = t["rect"]
		_box(tr, _sb_gold if bool(t["active"]) else _sb)
		var fs := int(t["size"])
		_txt_c(tr.get_center().x, tr.get_center().y + fs * 0.35, String(t["label"]),
			COL_GOLD if bool(t["active"]) else COL_TEXT, fs)
		_hot(tr, String(t["tag"]))
	for c in L["cards"]:
		var row: Array = c["row"]
		_card(c["rect"], String(row[0]), String(row[1]), String(row[2]), String(row[3]), vh, String(row[4]))
	for b in L["bars"]:
		draw_rect(b["track"], Color(1, 1, 1, 0.12))
		if b["fill"].size.x > 0.0:
			draw_rect(b["fill"], COL_GOLD)
	for b in L["buttons"]:
		var br: Rect2 = b["rect"]
		_box(br, _sb_gold if bool(b["gold"]) else _sb)
		var fs := int(b["size"])
		_txt_c(br.get_center().x, br.get_center().y + fs * 0.35, String(b["label"]), COL_TEXT, fs)
		_hot(br, String(b["tag"]))


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
	var parts: Array = [Names.choice_name("loadout", String(snap.get("loadout", "tender")))]
	for pkg in snap.get("packages", []):
		parts.append(_package_name(String(pkg)))
	for m in snap.get("mutators", []):
		parts.append(Names.choice_name("mutator", String(m)))
	return " · ".join(parts)


func _draw_status(snap: Dictionary, vw: float, vh: float) -> void:
	var pl: Dictionary = snap["player"]
	var pad := _safe_top(vh)
	var row_h := vh * 0.036
	# row 1: vitals left, menu/help buttons right
	var y := pad + row_h * 0.72
	var x := vw * 0.025
	# one HP-danger rule (Danger.hp_state): red when low OR when ending the
	# turn here would kill - the same verdict the vignette and the pulse use
	var dz := _danger_state()
	var hp_col := COL_RED if String(dz.get("hp", "ok")) != "ok" else COL_TEXT
	x = _chip(x, y, "ic_hp", "%d/%d" % [pl["hp"], pl["max_hp"]], vw, vh, hp_col)
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
	# label row: SKIES, the countdown chips (choke, vents, dim), then the run's
	# config line RIGHT-aligned in whatever the chips leave (_sky_row_layout)
	var sky_y := y2 + mh + vh * 0.0155
	_txt(Vector2(mx, sky_y), "SKIES", COL_DIM_TEXT, int(vh * 0.0125))
	var sky: Dictionary = dz.get("sky", {})
	var lay := _sky_row_layout(vw, vh, sky_y, Danger.sky_chips(sky))
	for c in lay["chips"]:
		var ir: Rect2 = c["icon_rect"]
		var itx := Art.tex(String(c["icon"]), int(ir.size.x))
		if itx != null:
			draw_texture(itx, ir.position)
		_txt(c["text_pos"], String(c["text"]), c["col"], int(c["nsz"]))
	var cfg := _config_line(snap)
	var cfg_box := vw * 0.975 - float(lay["cfg_x0"])
	var cfg_sz := _fit_size(cfg, int(vh * 0.0125), cfg_box)
	var cfg_w := font.get_string_size(cfg, HORIZONTAL_ALIGNMENT_LEFT, -1, cfg_sz).x
	_txt(Vector2(maxf(float(lay["cfg_x0"]), vw * 0.975 - cfg_w), sky_y), cfg, COL_DIM_TEXT, cfg_sz)
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
	elif Danger.sky_alert(sky) == "amber":
		# the choke is 5 turns off or closer: the bar warns before it bites
		var apulse := 0.45 + 0.35 * sin(Time.get_ticks_msec() / 180.0)
		draw_rect(Rect2(mx - 2, y2 - 2, mw + 4, mh + 4), Color(0.91, 0.64, 0.23, apulse), false, 2.0)
	# the floor and green readouts, right-aligned. (The old "! INCOMING" that
	# was squeezed between them and the bar - 9px and overlapping on a tall
	# phone - is now the context line's job, at full size: Danger.context_line.)
	var fl := "floor %d/7" % snap["floor"]
	var fsz := int(vh * 0.02)
	var fw := font.get_string_size(fl, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	_txt(Vector2(vw - fw - vw * 0.025, y2 + mh), fl, COL_GOLD, fsz)
	if int(snap["green_need"]) > 0:
		var gl := "green %d/%d" % [snap["greened"], snap["green_need"]]
		var done: bool = int(snap["greened"]) >= int(snap["green_need"])
		var gw := font.get_string_size(gl, HORIZONTAL_ALIGNMENT_LEFT, -1, int(vh * 0.016)).x
		_txt(Vector2(vw - fw - gw - vw * 0.055, y2 + mh), gl,
			Color(0.6, 0.85, 0.55) if not done else COL_DIM_TEXT, int(vh * 0.016))
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


## The SKIES label row as data: each countdown chip's icon rect, number
## position and size, then where the chips end and where the right-aligned
## config line may start. `y` is the row's text baseline. Measured worst case
## (chips 60/12/9) ends the chips by 0.41vw and leaves the config line at
## least 0.55vw - never narrower than the box it had before the chips; the
## icon tops clear the bar at every CARD_VIEWPORTS shape (test_shell).
func _sky_row_layout(vw: float, vh: float, y: float, chips: Array) -> Dictionary:
	var mx := vw * 0.025
	var x := mx + font.get_string_size("SKIES", HORIZONTAL_ALIGNMENT_LEFT, -1, int(vh * 0.0125)).x + vw * 0.012
	var isz := int(vh * 0.015)
	var nsz := int(vh * 0.0145)
	var out: Array = []
	for c in chips:
		var text := String(c["text"])
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, nsz).x
		out.append({"icon_rect": Rect2(x, y - isz * 0.85, isz, isz),
			"text_pos": Vector2(x + isz + vw * 0.005, y), "nsz": nsz, "text": text,
			"icon": String(c["icon"]), "col": c["col"]})
		x += isz + vw * 0.005 + tw + vw * 0.018
	return {"chips": out, "end_x": x, "cfg_x0": x + vw * 0.02}


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
			_txt_fit(Vector2(vw * 0.025, ly), log_lines[i], _log_col(i), lfs, vw * 0.95)
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
	var dz := _danger_state()
	var tele: Dictionary = dz.get("tele", {})
	var vmarks := {}
	for vm in Danger.vent_marks(snap, dz.get("sky", {})):
		vmarks[vm["pos"]] = vm
	for v in m["vents"]:
		if _vis(v):
			_sprite("vent", v)
			if vmarks.has(v):
				# the release countdown, on the grate itself (red ring at 1)
				var vm: Dictionary = vmarks[v]
				var vcol := Danger.COL_AMBER
				if bool(vm["urgent"]):
					vcol = Danger.COL_RED
					draw_arc(_tile_rect(v).get_center(), _ts * 0.46, 0, TAU, 20,
						Color(Danger.COL_RED, 0.5 + 0.4 * sin(Time.get_ticks_msec() / 140.0)), 2.5)
				elif bool(vm["sealed"]):
					vcol = Danger.COL_SEALED
				var vsz := maxi(1, int(_ts * 0.42))
				var vr := _tile_rect(v)
				_txt_c(vr.get_center().x + 1, vr.get_center().y + vsz * 0.35 + 1, String(vm["text"]), Color(0, 0, 0, 0.8), vsz)
				_txt_c(vr.get_center().x, vr.get_center().y + vsz * 0.35, String(vm["text"]), vcol, vsz)
			if snap["terrain"].has(v) and String(snap["terrain"][v]["kind"]) == "growth":
				# sealed: the growth chokes the grate (drawn again over the vent)
				_sprite("growth", v)
				draw_rect(_tile_rect(v).grow(-2), Color(0.42, 0.72, 0.35, 0.85), false, 2.0)
				if vmarks.has(v):
					var svr := _tile_rect(v)
					var ssz := maxi(1, int(_ts * 0.42))
					_txt_c(svr.get_center().x, svr.get_center().y + ssz * 0.35, String(vmarks[v]["text"]), Danger.COL_SEALED, ssz)
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
	# what each red tile costs, summed over every attacker aiming at it (not on
	# the tender's own tile: the INCOMING line speaks for that one)
	if _ts >= 18.0:
		var nsz := int(_ts * 0.30)
		for t in Danger.tile_numbers(tele, snap["player"]["pos"]):
			if not _vis(t):
				continue
			var tr := _tile_rect(t)
			var ns := str(int(tele["tiles"][t]))
			var nw := font.get_string_size(ns, HORIZONTAL_ALIGNMENT_LEFT, -1, nsz).x
			var np := tr.end - Vector2(nw + _ts * 0.08, _ts * 0.08)
			_txt(np + Vector2(1, 1), ns, Color(0, 0, 0, 0.85), nsz)
			_txt(np, ns, Color(1, 0.86, 0.8), nsz)
	# tiles a non-damage intent will change: the flood row, every oil tile an
	# ignite-all will light, every growth tile a dredge will eat
	for mk in Danger.marks(tele):
		if not _vis(mk["pos"]):
			continue
		var mcol := Color(0.42, 0.32, 0.52, 0.30)
		match String(mk["kind"]):
			"ignite":
				mcol = Color(0.95, 0.55, 0.2, 0.18 + 0.14 * sin(Time.get_ticks_msec() / 160.0))
			"dredge":
				mcol = Color(0.45, 0.33, 0.18, 0.28)
		draw_rect(_tile_rect(mk["pos"]), mcol)
	for e0 in snap["enemies"]:
		if String(e0["intent"].get("type", "")) != "fuse":
			continue
		for e1 in snap["enemies"]:
			if e1["id"] == e0["intent"].get("with", -1) and (_vis(e0["pos"]) or _vis(e1["pos"])):
				var wa := 0.5 + 0.4 * absf(sin(Time.get_ticks_msec() / 180.0))
				draw_line(_tile_rect(e0["pos"]).get_center(), _tile_rect(e1["pos"]).get_center(),
					Color(0.91, 0.45, 0.16, wa), 3.0)
	# a grapple's tether: crane to tender, dashed, with a ring on the landing
	# tile; grey and ringless when the drag is blocked (anchored, rooted...)
	for tt in Danger.tethers(tele, snap["player"]["pos"]):
		if not (_vis(tt["from"]) or _vis(tt["to"])):
			continue
		var tcol := Color(0.6, 0.62, 0.64, 0.5)
		var tw := 2.0
		if bool(tt["live"]):
			tcol = Color(Color("7ec8e0"), 0.55 + 0.35 * absf(sin(Time.get_ticks_msec() / 180.0)))
			tw = 3.0
		draw_dashed_line(_tile_rect(tt["from"]).get_center(), _tile_rect(tt["to"]).get_center(), tcol, tw, 6.0)
		if tt["land"] != null and _vis(tt["land"]):
			draw_arc(_tile_rect(tt["land"]).get_center(), _ts * 0.32, 0, TAU, 16, tcol, 2.5)

	var badge_of := {}
	for bd in Danger.badges(snap, tele):
		badge_of[bd["id"]] = bd
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
		if edef["traits"].has("boss") and game.core_shield_up(int(e["id"])):
			# the core is shielded: say so BEFORE a hit is wasted on it
			draw_arc(r.get_center(), _ts * 0.56, 0, TAU, 32,
				Color(Feedback.CYAN, 0.55 + 0.3 * sin(Time.get_ticks_msec() / 220.0)), 2.5)
		var maxhp: int = int(edef["hp"]) + (Content.ELITE_HP_BONUS if e.get("elite", false) else 0)
		if e["hp"] < maxhp or edef["traits"].has("boss"):
			var frac: float = clampf(float(e["hp"]) / maxf(1.0, float(maxhp)), 0.0, 1.0)
			draw_rect(Rect2(r.position + Vector2(2, -4), Vector2(_ts - 4, 3)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(r.position + Vector2(2, -4), Vector2((_ts - 4) * frac, 3)), COL_RED)
		if badge_of.has(e["id"]):
			_draw_badge(r, badge_of[e["id"]])

	var pap := _anim_pos("player", snap["player"]["pos"]) + _lunge_off()
	_shadow_f(pap)
	var bob := pap + Vector2(0, -0.02 - 0.02 * sin(Time.get_ticks_msec() / 480.0))
	_sprite_f("player", bob)
	var pr := _tile_rect_f(pap)
	# the outline is the end-turn forecast: red pulsing when ending here kills,
	# amber when something lands but you live, the usual green otherwise
	if bool(dz.get("lethal", false)):
		draw_rect(pr.grow(1), Color(0.88, 0.25, 0.15, 0.55 + 0.4 * absf(sin(Time.get_ticks_msec() / 150.0))), false, 3.0)
	elif int(dz.get("fc", {}).get("dmg", 0)) > 0:
		draw_rect(pr.grow(1), Danger.COL_AMBER, false, 2.0)
	else:
		draw_rect(pr.grow(1), Color(0.56, 0.86, 0.42, 0.85), false, 2.0)
	if int(snap["player"].get("anchor_turns", 0)) > 0:
		draw_rect(pr.grow(-2), Color("7a5a34"), false, 2.0)
	if int(snap["player"].get("thorns_turns", 0)) > 0:
		draw_rect(pr.grow(-4), Color("57b34a"), false, 1.5)
	# the kill streak: a flame and a count once two turns running have a kill;
	# it dims while this turn's kill is still owed (end the turn and it breaks)
	if stats != null and _stats_for == game:
		var sv: int = int(stats.streak_closed) + (1 if int(stats.open_turn_kills) > 0 else 0)
		if sv >= 2 and _ts >= 8.0:
			var fa := 1.0 if int(stats.open_turn_kills) > 0 else 0.45 + 0.2 * sin(Time.get_ticks_msec() / 200.0)
			var ftx := Art.tex("fire", int(_ts * 0.42))
			var fpos := pr.position + Vector2(_ts * 0.66, -_ts * 0.22)
			if ftx != null:
				draw_texture(ftx, fpos, Color(1, 1, 1, fa))
			_txt(fpos + Vector2(_ts * 0.40, _ts * 0.32), str(sv), Color(COL_GOLD, fa), int(_ts * 0.30))

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

	# the visible map rect: callouts clamp inside it, the vignette frames it
	var mr := Rect2(_mox + _vx0 * _ts, _moy + _vy0 * _ts,
		float(_vx1 - _vx0 + 1) * _ts, float(_vy1 - _vy0 + 1) * _ts)
	# transient combat feedback: flashes, bursts, puffs, floating numbers,
	# callouts, rings and the white ghost of a kill - all on the fx clock, so a
	# hit-stop holds them still
	var fnow := _fx_now()
	for fx in _fx:
		var dur := float(fx.get("dur", FX_MS))
		var age := float(fnow - int(fx["t0"])) / dur
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
				var fsz2 := maxi(1, int(_ts * 0.42 * float(fx.get("scale", 1.0))))
				var s2 := String(fx["text"])
				var fy := fr.position.y - _ts * (0.15 + age * 0.75)
				var tw2 := font.get_string_size(s2, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz2).x
				draw_string(font, Vector2(c.x - tw2 / 2.0 + 1, fy + 1), s2, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz2, Color(0, 0, 0, fcol.a * 0.8))
				draw_string(font, Vector2(c.x - tw2 / 2.0, fy), s2, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz2, fcol)
				if bool(fx.get("bold", false)):
					draw_string(font, Vector2(c.x - tw2 / 2.0 + maxf(1.0, fsz2 / 18.0), fy), s2, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz2, fcol)
			"callout":
				var ccol: Color = fx["col"]
				ccol.a = 1.0 if age < 0.65 else 1.0 - (age - 0.65) / 0.35
				var pop := 0.75 + 0.25 * clampf(age * dur / 90.0, 0.0, 1.0)
				var csz := maxi(1, int(maxf(_ts * 0.40, vh * 0.0118) * float(fx.get("scale", 1.0)) * pop))
				var cs := String(fx["text"])
				var ctw := font.get_string_size(cs, HORIZONTAL_ALIGNMENT_LEFT, -1, csz).x
				var cy := maxf(fr.position.y - _ts * (0.55 + float(fx.get("lift", 0.0)) + age * 0.55), mr.position.y + csz)
				var cx := clampf(c.x - ctw / 2.0, mr.position.x + 2, maxf(mr.position.x + 2, mr.end.x - ctw - 2))
				draw_string(font, Vector2(cx + 1.5, cy + 1.5), cs, HORIZONTAL_ALIGNMENT_LEFT, -1, csz, Color(0, 0, 0, 0.85 * ccol.a))
				draw_string(font, Vector2(cx, cy), cs, HORIZONTAL_ALIGNMENT_LEFT, -1, csz, ccol)
				draw_string(font, Vector2(cx + maxf(1.0, csz / 18.0), cy), cs, HORIZONTAL_ALIGNMENT_LEFT, -1, csz, ccol)
			"ring":
				var rcol: Color = fx["col"]
				rcol.a = 1.0 - age
				draw_arc(c, _ts * (0.45 + 0.35 * age), 0, TAU, 28, rcol, 3.0)
			"ghost":
				var gtx := Art.tex(String(fx.get("sprite", "")), int(_ts))
				if gtx != null:
					draw_texture(gtx, fr.position, Color(1, 1, 1, 1.0 - age))
				draw_rect(fr, Color(1, 1, 1, 0.45 * (1.0 - age)))

	if mode == "target_tile":
		for t in mode_targets:
			if _vis(t):
				draw_rect(_tile_rect(t).grow(-1), COL_TARGET, false, 2.5)
	elif mode == "target_dir" or mode == "cleanse":
		for d in DIRS4.values():
			draw_rect(_tile_rect(snap["player"]["pos"] + d).grow(-1), COL_TARGET, false, 2.0)

	# soft vignette around the tile field for depth
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
		var shielded: bool = game.core_shield_up(int(e["id"]))
		var hps := "%d / %d" % [int(e["hp"]), int(edef2["hp"])]
		var hpw := font.get_string_size(hps, HORIZONTAL_ALIGNMENT_LEFT, -1, int(vh * 0.014)).x
		_txt(Vector2(bx2 + bw2 - hpw, by2 - vh * 0.006), hps, COL_TEXT, int(vh * 0.014))
		if shielded:
			var shw := font.get_string_size("SHIELDED  ", HORIZONTAL_ALIGNMENT_LEFT, -1, int(vh * 0.014)).x
			_txt(Vector2(bx2 + bw2 - hpw - shw, by2 - vh * 0.006), "SHIELDED  ", Feedback.CYAN, int(vh * 0.014))
		draw_rect(Rect2(bx2, by2, bw2, bh2), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bx2, by2, bw2 * bfrac, bh2), COL_RED)
		if shielded:
			draw_rect(Rect2(bx2, by2, bw2, bh2), Feedback.CYAN, false, 2.5)
		else:
			draw_rect(Rect2(bx2, by2, bw2, bh2), Color(0.9, 0.4, 0.3, 0.7), false, 1.5)
		break

	# danger vignette: the edges bleed red while the tender is nearly down
	var hp_st := String(dz.get("hp", "ok"))
	if hp_st != "ok" and not game.over:
		var da := 0.10 + 0.07 * sin(Time.get_ticks_msec() / 300.0)
		if hp_st == "lethal":
			da = 0.16 + 0.10 * sin(Time.get_ticks_msec() / 170.0)
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
		var card := _floor_card_lines(snap)
		var nsz := int(vh * 0.032)
		_txt_c(vw / 2.0 + 2, scy + 2, card[0], Color(0, 0, 0, 0.6 * sa), nsz)
		_txt_c(vw / 2.0, scy, card[0], Color(COL_GOLD, sa), nsz)
		_txt_c(vw / 2.0, scy + vh * 0.028, card[1], Color(COL_CREAM, sa * 0.85), int(vh * 0.018))
		if card.size() > 2:
			_txt_c(vw / 2.0, scy + vh * 0.052, card[2], Color(0.6, 0.85, 0.55, sa * 0.9), int(vh * 0.016))

	# event banners (one queue: boss phases, awakenings, restored, stairs)
	var bage := float(Time.get_ticks_msec() - _banner_ms) / float(BANNER_MS)
	if bage >= 0.0 and bage < 1.0 and not _banner.is_empty():
		var ba := 1.0 if bage < 0.6 else 1.0 - (bage - 0.6) / 0.4
		var bcy := (mr.position.y + mr.end.y) / 2.0 - vh * 0.05
		_txt_c_fit(vw / 2.0 + 2, bcy + 2, String(_banner[0]), Color(0, 0, 0, 0.6 * ba), int(vh * 0.03), vw * 0.94)
		_txt_c_fit(vw / 2.0, bcy, String(_banner[0]), Color(_banner_col, ba), int(vh * 0.03), vw * 0.94)
		if _banner.size() > 1:
			_txt_c_fit(vw / 2.0, bcy + vh * 0.026, String(_banner[1]), Color(COL_CREAM, ba * 0.9), int(vh * 0.017), vw * 0.92)


## One intent badge at an enemy's top-right corner (Danger.badges): a dark
## disc ringed in the intent's category colour carrying its glyph, the number
## (damage, countdown, steps) just left of it. A ring at half strength is an
## intent that is not aimed at the tender where it stands; a blocked intent
## wears its block glyph (stars, roots, smoke, anchor) and no number.
func _draw_badge(r: Rect2, bd: Dictionary) -> void:
	var c := r.position + Vector2(_ts * 0.80, _ts * 0.20)
	var col: Color = bd["col"]
	draw_circle(c, _ts * 0.19, Color(0.06, 0.08, 0.07, 0.85))
	var ring := col
	if not bool(bd["live"]) and String(bd["cat"]) != "blocked":
		ring.a = 0.5
	draw_arc(c, _ts * 0.19, 0, TAU, 20, ring, 1.5)
	var isz := maxi(8, int(_ts * 0.30))
	var itx := Art.tex(String(bd["icon"]), isz)
	if itx != null:
		draw_texture(itx, c - Vector2(isz, isz) / 2.0)
	var text := String(bd["text"])
	if text != "" and _ts >= 18.0:
		var nsz := int(_ts * 0.28)
		var nw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, nsz).x
		var np := Vector2(c.x - _ts * 0.21 - nw, r.position.y + _ts * 0.30)
		_txt(np + Vector2(1, 1), text, Color(0, 0, 0, 0.85), nsz)
		_txt(np, text, col, nsz)


## The floor's title card: name, "floor N of 7", and what wakes the stairs -
## on the boss floor "defeat the Overseer" (it has no quota, so the old line
## read "cleanse 0 to wake the stairs"), and no third line on a floor that
## needs nothing.
func _floor_card_lines(snap: Dictionary) -> Array:
	var out: Array = [String(snap["floor_name"]).to_upper(), "floor %d of 7" % int(snap["floor"])]
	if int(snap["green_need"]) > 0:
		out.append("cleanse %d to wake the stairs" % int(snap["green_need"]))
	else:
		for e in snap["enemies"]:
			if Content.ENEMIES.get(String(e["kind"]), {}).get("traits", []).has("boss"):
				out.append("defeat " + Names.the_name(String(e["kind"])))
				break
	return out


## A log line's colour: its category's at full strength on the newest line;
## older lines dim (an info line to the plain dim grey).
func _log_col(i: int) -> Color:
	var cat := String(log_cats[i]) if i < log_cats.size() else "info"
	var col: Color = Feedback.LOG_COL.get(cat, COL_TEXT)
	if i == log_lines.size() - 1:
		return col
	return COL_DIM_TEXT if cat == "info" else col.lerp(COL_DIM_TEXT, 0.55)


func _draw_ability_bar(snap: Dictionary, vw: float, vh: float) -> void:
	var pl: Dictionary = snap["player"]
	var n: int = pl["kit"].size()
	var gap := vw * 0.018
	var b := minf(vh * (Z_AB_END - Z_MAP_END) * 0.86, (vw * 0.95 - (n - 1) * gap) / n)
	var total := n * b + (n - 1) * gap
	var x := (vw - total) / 2.0
	var y := vh * Z_MAP_END + (vh * (Z_AB_END - Z_MAP_END) - b) / 2.0
	var gum_next: Array = Danger.gum_slots(snap, _danger_state().get("tele", {}))
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
		elif gum_next.has(i):
			# a live tar shot will gum THIS slot if the turn ends now
			var gr := r.grow(-b * 0.03)
			var gcol := Color("8a6a3a")
			for edge in [[gr.position, Vector2(gr.end.x, gr.position.y)], [Vector2(gr.end.x, gr.position.y), gr.end],
					[gr.end, Vector2(gr.position.x, gr.end.y)], [Vector2(gr.position.x, gr.end.y), gr.position]]:
				draw_dashed_line(edge[0], edge[1], gcol, 2.5, b * 0.08)
			var gtx := Art.tex("in_gum", int(b * 0.26))
			if gtx != null:
				draw_texture(gtx, r.position + Vector2(b * 0.04, b * 0.04))
		_hot(r, "ability:%d" % i)
		x += b + gap


func _draw_context(snap: Dictionary, vw: float, vh: float) -> void:
	var y := vh * Z_AB_END + (vh * (Z_CTX_END - Z_AB_END)) * 0.62
	var cm := _context_msg(snap)
	var col: Color = cm["col"]
	if bool(cm["pulse"]):
		col.a = 0.65 + 0.35 * sin(Time.get_ticks_msec() / 160.0)
	_txt_fit(Vector2(vw * 0.025, y), String(cm["text"]), col, int(vh * 0.022), vw * 0.95)
	_hot(Rect2(0, vh * Z_AB_END, vw, vh * (Z_CTX_END - Z_AB_END)), "log")


## The context line as data, {text, col, pulse}: the ONE priority chain for the
## line above the D-pad. Mode prompts first, then a flash (red when it is a
## lethal-guard refusal), then the danger layer's line (Danger.context_line:
## incoming damage, the choke countdown, the vents - never in the tutorial),
## then the floor's standing hint.
func _context_msg(snap: Dictionary) -> Dictionary:
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
			# a dry cleanse the lethal guard refused stays in cleanse mode (the
			# second press is the confirmation), so the refusal must show HERE
			# or the tap reads as a dead button
			if flash != "" and _flash_red:
				return {"text": flash, "col": COL_RED, "pulse": false}
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
				return {"text": flash, "col": COL_RED if _flash_red else COL_GOLD, "pulse": false}
			if screen == "tutorial":
				return {"text": "", "col": col, "pulse": false}
			var dl: Dictionary = Danger.context_line(_danger_state(), Danger.stairs_awake(snap))
			if not dl.is_empty():
				return dl
			if snap["floor"] == 7:
				msg = "DESTROY THE BOSS  ·  tap for log"
			elif int(snap["greened"]) < int(snap["green_need"]):
				msg = "Stairs dormant - cleanse %d/%d to green the floor" % [snap["greened"], snap["green_need"]]
				col = Color(0.6, 0.85, 0.55)
			else:
				msg = "Reach the gold-ringed stairs  ·  tap for log"
	return {"text": msg, "col": col, "pulse": false}


func _draw_controls(snap: Dictionary, vw: float, vh: float) -> void:
	var top := vh * Z_CTX_END
	var zone_h := vh - top
	var b := minf(vw * 0.145, zone_h * 0.3)
	var gap := vw * 0.012
	var dx := vw * 0.035
	var dy := top + (zone_h - (b * 3 + gap * 2)) / 2.0
	_arrow_button(Rect2(dx + b + gap, dy, b, b), "up")
	_arrow_button(Rect2(dx, dy + b + gap, b, b), "left")
	# END and END TURN go red when ending the turn here kills - they still work
	# with one press (never guarded), the border only says what that press does
	var dz := _danger_state()
	var lethal := bool(dz.get("lethal", false))
	var end_border := COL_RED if lethal else COL_DIM_TEXT
	_button(Rect2(dx + b + gap, dy + b + gap, b, b), "END", "end_turn", int(b * 0.28), end_border)
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
			if lethal and dz.get("escapes", {}).get("item", []).has(i):
				# this item, used now, survives the end turn: it glows
				draw_rect(ir.grow(-b * 0.03), Color(COL_GOLD, 0.5 + 0.4 * sin(Time.get_ticks_msec() / 170.0)), false, 3.0)
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
	_button(Rect2(bx, by, bw, bh), "END TURN", "end_turn", int(bh * 0.42), end_border)
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
		_txt_fit(Vector2(vw * 0.06, y), log_lines[i], _log_col(i), fsz, vw * 0.88)
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


## The game-over sheet's rows, in display order: [id, prio, size (fraction of
## vh), max lines (1 = fit on one line, 0 = the kit's icon row), width
## (fraction of vw), extra gap before (fraction of vh)]. When the rows do not
## fit between OVER_TOP and OVER_BOTTOM, the present row with the LARGEST prio
## is dropped until they do - so on the smallest phone the seed line and the
## third chip go first, and the title, cause, score and best never go.
## tests/test_shell.gd _check_over_text holds every row to CARD_MIN_VH at every
## CARD_VIEWPORTS shape and nothing with prio <= 13 dropped in the worst case.
const OVER_ROWS := [
	["title", 1, 0.042, 1, 0.90, 0.0],
	["cause", 2, 0.022, 2, 0.88, 0.0],
	["near", 5, 0.024, 2, 0.88, 0.0],
	["stats", 7, 0.021, 2, 0.90, 0.0],
	["kit", 9, 0.017, 0, 0.0, 0.0],
	["grafts", 13, 0.018, 2, 0.88, 0.0],
	["chip0", 11, 0.018, 1, 0.72, 0.0],
	["chip1", 12, 0.018, 1, 0.72, 0.0],
	["chip2", 16, 0.018, 1, 0.72, 0.0],
	["score", 3, 0.036, 1, 0.90, 0.012],
	["best", 4, 0.021, 1, 0.90, 0.0],
	["floor_best", 10, 0.021, 1, 0.90, 0.0],
	["parts", 15, 0.016, 2, 0.88, 0.0],
	["unlock0", 6, 0.021, 1, 0.92, 0.012],
	["unlock1", 6, 0.021, 1, 0.92, 0.0],
	["unlock2", 14, 0.021, 1, 0.92, 0.0],
	["unlock3", 14, 0.021, 1, 0.92, 0.0],
	["next", 8, 0.019, 2, 0.88, 0.0],
	["seed", 17, 0.016, 1, 0.90, 0.0],
]
const OVER_TOP := 0.11     # the content block, under the sun / smog art
const OVER_BOTTOM := 0.86  # ...and above the button row
const OVER_GAP := 0.008    # after every row
const OVER_CHIP_H := 0.028
const OVER_BTN_H := 0.065


## One row's text, out of the sheet facts.
func _over_row_text(info: Dictionary, id: String) -> String:
	if id.begins_with("chip"):
		var chips: Array = info.get("chips", [])
		var ci := int(id.substr(4))
		return String(chips[ci]) if ci < chips.size() else ""
	if id.begins_with("unlock"):
		var ul: Array = info.get("unlocks", [])
		var ui := int(id.substr(6))
		return String(ul[ui]) if ui < ul.size() else ""
	match id:
		"best":
			var b: Array = info.get("best", ["", false])
			return String(b[0]) if not b.is_empty() else ""
		"parts":
			return String(info.get("score_parts", ""))
	return String(info.get(id, ""))


## One row's colour.
func _over_row_col(info: Dictionary, id: String) -> Color:
	var won := bool(info.get("won", false))
	if id.begins_with("unlock") or id.begins_with("chip"):
		return COL_GOLD
	match id:
		"title":
			return COL_GOLD if won else COL_RED
		"near":
			return COL_CREAM if won else COL_GOLD
		"score", "floor_best":
			return COL_GOLD
		"best":
			var b: Array = info.get("best", ["", false])
			return COL_GOLD if b.size() > 1 and bool(b[1]) else COL_DIM_TEXT
		"grafts", "parts", "seed":
			return COL_DIM_TEXT
		"next":
			return COL_CREAM
	return COL_TEXT


## The game-over sheet as data (the _card_layout pattern: layout first, the
## drawing and the geometry gate both read it). -> {items, buttons, dropped,
## bottom, button_top}. A text item is {id, kind "text", prio, lines, size,
## line_h, y (first baseline), cx, col}; the kit {id, kind "kit", prio, icons:
## [{icon, pos, size, count, count_pos, count_size, up}]}; a chip {id, kind
## "chip", prio, rect, text, size}; a button {rect, label, tag, size, primary}.
func _over_layout(info: Dictionary, vw: float, vh: float) -> Dictionary:
	var gap := vh * OVER_GAP
	var rows: Array = []
	var seen_unlock := false
	for r in OVER_ROWS:
		var id := String(r[0])
		var pre := vh * float(r[5])
		if id.begins_with("unlock"):
			pre = 0.0 if seen_unlock else vh * 0.012
		var it := {"id": id, "prio": int(r[1])}
		if id == "kit":
			var kit: Array = info.get("kit", [])
			if kit.is_empty():
				continue
			var isz := minf(vh * 0.042, vw * 0.15)
			var csz := int(vh * float(r[2]))
			it["kind"] = "kit"
			it["isz"] = isz
			it["csz"] = csz
			it["h"] = pre + isz + csz * 1.3 + gap
			it["pre"] = pre
			it["kit"] = kit
			rows.append(it)
			continue
		var text := _over_row_text(info, id)
		if text == "":
			continue
		if id.begins_with("unlock"):
			seen_unlock = true
		var size := int(vh * float(r[2]))
		if id.begins_with("chip"):
			it["kind"] = "chip"
			it["text"] = text
			it["size"] = _fit_size(text, size, vw * float(r[4]))
			it["h"] = pre + vh * (OVER_CHIP_H + 0.006)
			it["pre"] = pre
			rows.append(it)
			continue
		var lines: Array = [text]
		if int(r[3]) > 1:
			var wr := _wrap(text, size, vw * float(r[4]), int(r[3]))
			lines = wr["lines"]
			size = int(wr["size"])
		else:
			size = _fit_size(text, size, vw * float(r[4]))
		it["kind"] = "text"
		it["lines"] = lines
		it["size"] = size
		it["line_h"] = size * 1.2
		it["col"] = _over_row_col(info, id)
		it["h"] = pre + lines.size() * size * 1.2 + gap
		it["pre"] = pre
		rows.append(it)
	# the priority drop: the least important present row goes first
	var budget := vh * (OVER_BOTTOM - OVER_TOP)
	var total := 0.0
	for it in rows:
		total += float(it["h"])
	var dropped: Array = []
	while total > budget and not rows.is_empty():
		var wi := 0
		for k in rows.size():
			if int(rows[k]["prio"]) > int(rows[wi]["prio"]):
				wi = k
		total -= float(rows[wi]["h"])
		dropped.append(String(rows[wi]["id"]))
		rows.remove_at(wi)
	var items: Array = []
	var y := vh * OVER_TOP
	for it in rows:
		var top: float = y + float(it["pre"])
		match String(it["kind"]):
			"text":
				it["y"] = top + float(it["size"])
				it["cx"] = vw / 2.0
			"chip":
				it["rect"] = Rect2(vw * 0.11, top, vw * 0.78, vh * OVER_CHIP_H)
			"kit":
				var isz: float = it["isz"]
				var kit: Array = it["kit"]
				var step := isz + vw * 0.03
				var x0 := vw / 2.0 - (step * kit.size() - vw * 0.03) / 2.0
				var icons: Array = []
				for k in kit.size():
					var kd: Dictionary = kit[k]
					var px := x0 + step * k
					icons.append({"icon": String(kd["icon"]), "pos": Vector2(px, top), "size": isz,
						"count": "x%d" % int(kd["count"]), "count_size": int(it["csz"]),
						"count_pos": Vector2(px + isz / 2.0, top + isz + float(it["csz"]) * 1.05),
						"up": bool(kd["up"])})
				it["icons"] = icons
		y += float(it["h"])
		items.append(it)
	var bh := vh * OVER_BTN_H
	var by := _sheet_button_y(vh * 0.875, bh, vh)
	var btns: Array = info.get("buttons", [])
	var n := maxi(1, btns.size())
	var bw := (vw * 0.9 - vw * 0.03 * (n - 1)) / n
	var buttons: Array = []
	for k in btns.size():
		var br := Rect2(vw * 0.05 + (bw + vw * 0.03) * k, by, bw, bh)
		var label := String(btns[k][0])
		buttons.append({"rect": br, "label": label, "tag": String(btns[k][1]),
			"size": _fit_size(label, int(bh * 0.36), bw * 0.92), "primary": k == 0 and String(btns[k][1]) != "menu"})
	return {"items": items, "buttons": buttons, "dropped": dropped, "bottom": y, "button_top": by}


## The end beat's two banner lines, centred in the map band [top, bottom]:
## [{text, size, y, col}].
func _over_beat_layout(info: Dictionary, vw: float, vh: float, top: float, bottom: float) -> Array:
	var ban: Array = info.get("banner", ["", ""])
	var won := bool(info.get("won", false))
	var l0 := String(ban[0]) if ban.size() > 0 else ""
	var l1 := String(ban[1]) if ban.size() > 1 else ""
	var s0 := _fit_size(l0, int(vh * 0.034), vw * 0.92)
	var s1 := _fit_size(l1, int(vh * 0.018), vw * 0.92)
	var mid := (top + bottom) / 2.0
	return [{"text": l0, "size": s0, "y": mid, "col": COL_GOLD if won else COL_RED},
		{"text": l1, "size": s1, "y": mid + vh * 0.032, "col": COL_CREAM}]


## The end beat: the map stays up, tinted (a gold wash on a win, smog-brown on
## a death), the controls dim behind a veil and take no taps, and the banner
## names the moment ("THE DRILL BOT TAKES YOU").
func _draw_over_beat(vw: float, vh: float) -> void:
	var info := _over_info_now()
	var age := float(Time.get_ticks_msec() - _over_ms)
	var t := clampf(age / OVER_BEAT_MS, 0.0, 1.0)
	var won := bool(info.get("won", false))
	var map_end := vh * Z_MAP_END
	draw_rect(Rect2(0, _status_end, vw, maxf(0.0, map_end - _status_end)),
		Color(0.95, 0.88, 0.55, 0.16 * t) if won else Color(0.10, 0.07, 0.06, 0.45 * t))
	draw_rect(Rect2(0, map_end, vw, vh - map_end), Color(COL_SHEET.r, COL_SHEET.g, COL_SHEET.b, 0.6 * t))
	hotspots.clear()
	var a := clampf(age / 150.0, 0.0, 1.0)
	for ln in _over_beat_layout(info, vw, vh, _status_end, map_end):
		var s := String(ln["text"])
		if s == "":
			continue
		var sz := int(ln["size"])
		var col: Color = ln["col"]
		col.a = a
		_txt_c(vw / 2.0 + 2, float(ln["y"]) + 2, s, Color(0, 0, 0, 0.8 * a), sz)
		_txt_c(vw / 2.0, float(ln["y"]), s, col, sz)


## The game-over sheet: what happened, how close it was, what the run was,
## its score against your best, what it unlocked and what is next - then the
## explicit buttons. Fades in after the beat; the buttons stay dead (drawn dim,
## no hotspot) until the lock lifts.
func _draw_over(snap: Dictionary, vw: float, vh: float) -> void:
	hotspots.clear()
	var info := _over_info_now()
	var a := 1.0
	if _over_phase() == "fade":
		a = clampf(float(Time.get_ticks_msec() - _over_ms - OVER_BEAT_MS) / OVER_FADE_MS, 0.0, 1.0)
	draw_rect(Rect2(0, 0, vw, vh), Color(COL_SHEET.r, COL_SHEET.g, COL_SHEET.b, a))
	var won: bool = snap["won"]
	var tsec := Time.get_ticks_msec() / 1000.0
	if won:
		var sun := Vector2(vw / 2.0, vh * 0.07)
		var r := vh * 0.028
		draw_circle(sun, r * 2.6, Color(0.95, 0.88, 0.55, 0.08 * a))
		draw_circle(sun, r * 1.7, Color(0.95, 0.88, 0.55, 0.12 * a))
		draw_circle(sun, r, Color(0.95, 0.89, 0.63, a))
		for i in 10:  # petals drift down through the clear air
			var ph := float(i) * 1.7
			var fall := fposmod(tsec * (0.05 + 0.02 * float(i % 3)) + ph, 1.0)
			draw_circle(Vector2(vw * fposmod(ph * 0.37 + sin(tsec * 0.6 + ph) * 0.03, 1.0), vh * 0.55 * fall),
				vw * 0.006, Color(0.91, 0.62, 0.80, 0.5 * a * (1.0 - fall)))
	else:
		for i in 5:  # the smog closes over the screen
			var drift := fposmod(tsec * (0.02 + 0.01 * float(i % 2)) + float(i) * 0.23, 1.2) - 0.1
			draw_circle(Vector2(vw * drift, vh * (0.04 + 0.02 * float(i))), vw * 0.16, Color(0.42, 0.36, 0.32, 0.08 * a))
		var isz := int(vh * 0.05)
		var skt := Art.tex("ic_choke", isz)
		if skt != null:
			draw_texture(skt, Vector2(vw / 2.0 - isz / 2.0, vh * 0.07 - isz / 2.0), Color(1, 1, 1, a))
	var lay := _over_layout(info, vw, vh)
	for it in lay["items"]:
		match String(it["kind"]):
			"text":
				var col: Color = it["col"]
				col.a *= a
				var ly: float = it["y"]
				for ln in it["lines"]:
					_txt_c(float(it["cx"]), ly, String(ln), col, int(it["size"]))
					ly += float(it["line_h"])
			"chip":
				var cr: Rect2 = it["rect"]
				draw_rect(cr, Color(0.15, 0.22, 0.17, 0.9 * a))
				draw_rect(cr, Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 0.6 * a), false, 1.5)
				var csz := int(it["size"])
				_txt_c(cr.get_center().x, cr.get_center().y + csz * 0.35, String(it["text"]),
					Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, a), csz)
			"kit":
				for ic in it["icons"]:
					var isz2 := int(ic["size"])
					var tex := Art.tex(String(ic["icon"]), isz2)
					if tex != null:
						draw_texture(tex, ic["pos"], Color(1, 1, 1, a))
					var cs := int(ic["count_size"])
					var cp: Vector2 = ic["count_pos"]
					_txt_c(cp.x, cp.y, String(ic["count"]), Color(COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, a), cs)
					if bool(ic["up"]):
						var pp: Vector2 = ic["pos"]
						_txt(Vector2(pp.x + isz2 - cs * 0.3, pp.y + cs * 0.8), "+",
							Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, a), cs)
	var locked := _over_locked()
	for b in lay["buttons"]:
		var br: Rect2 = b["rect"]
		if locked:
			# dead until the lock lifts: no hotspot, and drawn as if disabled
			draw_rect(br, Color(COL_BTN.r, COL_BTN.g, COL_BTN.b, 0.85 * a))
			draw_rect(br, Color(COL_DIM_TEXT.r, COL_DIM_TEXT.g, COL_DIM_TEXT.b, 0.5 * a), false, 2.0)
			var ls := int(b["size"])
			_txt_c(br.get_center().x, br.get_center().y + ls * 0.35, String(b["label"]),
				Color(COL_DIM_TEXT.r, COL_DIM_TEXT.g, COL_DIM_TEXT.b, a), ls)
		else:
			_button(br, String(b["label"]), String(b["tag"]), int(b["size"]),
				COL_GOLD if bool(b["primary"]) else COL_DIM_TEXT)


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
