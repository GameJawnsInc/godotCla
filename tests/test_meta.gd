extends SceneTree
## Meta-progression checks:
## 1) a simulated optimizer career walks the unlock ladder (packages, tiers)
##    and must own every package by run 40 (unlock SET, not run numbers); the
##    loop feeds full `Game.run_summary()` records, the shape the shell sends
## 2) profile save/load roundtrips, and load_from filters ids no longer in
##    Content out of a hand-written profile
## 3) every mutator runs without errors and stays sane
## 4) structural asserts (review §6.1 / §7.6): each package lands in the draft
##    pool without touching the base pool; each mutator's declared invariant
##    holds on a fresh game (expectation table lives HERE, not in content);
##    game_config clamps unknown requests; a tier-0-only career names exactly
##    the milestones it can never reach; the roster covers the playtest personas
## 5) profile bookkeeping the summary made possible (review §6.3, C4): the
##    history cap, every milestone predicate on constructed summaries, the
##    unknown-kind dispatch path, and dailies staying out of the career
## 6) the Block A run-setup layer (review §6.1): the loadout rows, the
##    loadout/package/requires rules game_config enforces, daily_config as a
##    pure function of the seed over frozen lists, and every loadout actually
##    being winnable by the optimizer
## 8) the fun pass's run-stats fold (meta/run_stats.gd): fold and replay
##    determinism over real bot runs (summary AND every step's ctx), the bloom
##    cross-check, an independent recount, hand-fed units, the score, the
##    near-miss rules and the highlight order; then the career records and
##    score bests in meta/profile.gd. The career loop in 1) is also the
##    interface pin: every summary it records is the shell's exact merge, and
##    each must carry every Content.RUN_STAT_KEYS key as an int.
## 9) the career layer: progress() per predicate, next_goals() (grouping, the
##    tier fold, ranking, the report's delta), the unseen NEW-badge store and
##    its display helpers, and the daily streak / tries / ranked first finish.
## 10) feats (Content.FEATS): every row met and missed by one on fixtures
##    built from its own req, earned once, dated off the summary, dailies
##    untouched; the career totals / bosses / casts folds; feat_progress,
##    next_feats and the NEXT fallback; goal_rows. The career loop in 1) must
##    earn at least CAREER_MIN_FEATS feats and its save/load roundtrip in 2)
##    covers every feat store.
## Run: godot --headless --path . --script tests/test_meta.gd

const Content := preload("res://sim/content.gd")
const Game := preload("res://sim/game.gd")
const Profile := preload("res://meta/profile.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const Roster := preload("res://bots/roster.gd")
const RunStats := preload("res://meta/run_stats.gd")

const CAREER_RUNS := 40
## Feats the 40-run optimizer career must earn (measured: comfortably more;
## spec_meta §1 measured >= 8 by run 6 on the default optimizer).
const CAREER_MIN_FEATS := 5
const TIER0_CAREER_RUNS := 63
const MUTATOR_SEEDS := 8
## Winnability floor per starting loadout (review §6.1 item 7): the optimizer
## over seeds 1..LOADOUT_SEEDS must clear LOADOUT_MIN_WINS with each
## package-free loadout, and SKYRUNNER_MIN_WINS with skyrunner (which only
## exists with its package). These are "is this playable at all" gates, not
## balance targets - docs/BALANCE.md owns the bands, and the 30-seed measure
## of each loadout is the Measure phase's job, not this suite's.
const LOADOUT_SEEDS := 20
const LOADOUT_MIN_WINS := 3
const SKYRUNNER_MIN_WINS := 1
## Milestones a career that never leaves tier 0 cannot reach: exactly the ones
## gated on tier_wins (Content.MILESTONES). Everything else is a reachability
## witness - a tier-0 optimizer career lands `upgrades_only` (a win holding a
## Tangle Bomb), `wide_draft` (60 effective Grow Spikes; the career casts ~440),
## `no_lance` and `lasher` (wins whose final kit dropped Solar Lance / kept
## Vine Whip - a draft pick over a full kit can do both, sim/game.gd
## _act_draft), and every Block A loadout row. An exact set, so a milestone
## that quietly becomes unreachable fails here.
## The run count is a reachability budget, not a target. Block D6 moved the
## last witness once: with every base "+" forked in two, the draft deals a
## parity-picked variant where it used to deal the single "+" form, which
## reshuffles which wins drop the lance - `no_lance` (a win whose final kit
## dropped Solar Lance) landed at seed 31 there, where under D4 `lasher` was
## last at seed 23, so 36 left five runs of margin.
## CUTTING THE D5 GROWTH RESONANCE MOVED IT AGAIN, and this is the clearest
## reading of how far a passive can reach: deep_loam paid +1 charge on the
## turns begun on growth, so the optimizer's growth-heavy careers played
## differently top to bottom, and the seed-31 witness (a win on
## [moss_filter+prism, seed_bomb, mycelium_dash, sun_flare+corona,
## grow_spike+throng]) is not a win any more. The next lance-free win is seed
## 58, so 63 keeps the same five runs of margin. A bot-routing, draft or
## content change moves which seed witnesses what - raise the count, do not
## move a reachable milestone into the unreachable set (measured over 60 runs
## on the cut tree: every milestone but the three tier-gated ones lands, the
## last four at seeds 5 / 9 / 13 / 58 and nothing after 58).
const TIER0_UNREACHABLE := ["aeolian", "brittle", "parched"]

## Fixture milestone table for the dispatch check (Content.MILESTONES is
## const, so the profile's `milestone_rows` seam stands in for it): one row per
## dispatchable kind plus one whose kind nothing dispatches on.
const FIXTURE_MILESTONES := [
	{"id": "fx_package", "kind": "package", "requires": {}, "desc": "free"},
	{"id": "fx_mutator", "kind": "mutator", "requires": {"wins": 1}, "desc": "a win"},
	{"id": "fx_loadout", "kind": "loadout", "requires": {"wins": 1}, "desc": "a win"},
	{"id": "fx_graft", "kind": "graft", "requires": {"grafts_owned_at_win": 2}, "desc": "2 grafts"},
	{"id": "fx_bogus", "kind": "sigil", "requires": {}, "desc": "unknown kind"},
]


var failures := 0
## interface-pin failures already reported (the career loop runs ~100 times)
var _pin_seen := {}
var _pin_runs := 0


func _init() -> void:
	# 1) career simulation: always play the highest unlocked tier
	var profile = Profile.new()
	var unlock_log: Array = []
	for s in range(1, CAREER_RUNS + 1):
		var t: int = profile.unlocked_tier
		var summary := _career_summary(s, _career_config(profile, t))
		var news: Array = profile.record_run(summary)
		for id in news:
			unlock_log.append("run %d: %s" % [s, id])
	print("career: %d runs, %d wins, best floor %d, reached tier %d" % [
		profile.runs, profile.wins, profile.best_floor, profile.unlocked_tier])
	for line in unlock_log:
		print("  unlock at %s" % line)
	if profile.unlocked_packages.is_empty():
		_fail("no packages unlocked across %d runs" % CAREER_RUNS)
	if profile.unlocked_tier == 0 and profile.wins > 0:
		_fail("wins recorded but tier never unlocked")
	# the unlock SET by run 40: every package must be owned; mutators are reported
	var missing_pkgs: Array = []
	for pkg in Content.PACKAGES:
		if not profile.unlocked_packages.has(pkg):
			missing_pkgs.append(pkg)
	if not missing_pkgs.is_empty():
		_fail("packages not unlocked by run %d: %s" % [CAREER_RUNS, str(missing_pkgs)])
	var missing_muts: Array = []
	for mut in Content.MUTATORS:
		if not profile.unlocked_mutators.has(mut):
			missing_muts.append(mut)
	print("career unlock set: packages %s, mutators %s%s" % [
		str(profile.unlocked_packages), str(profile.unlocked_mutators),
		"" if missing_muts.is_empty() else "  (mutators still locked: %s)" % str(missing_muts)])
	# the summary-fed career fills the C4 bookkeeping
	if profile.history.size() != mini(CAREER_RUNS, Profile.HISTORY_MAX):
		_fail("career history %d entries, expected %d" % [profile.history.size(), mini(CAREER_RUNS, Profile.HISTORY_MAX)])
	if profile.casts_by_base.is_empty():
		_fail("career recorded no effective casts (summaries not reaching the profile?)")
	print("career record: history %d, casts over %d bases, grow_spike %d" % [
		profile.history.size(), profile.casts_by_base.size(), int(profile.casts_by_base.get("grow_spike", 0))])
	# the feats a real career earns (the shell's exact merge, dated)
	print("career feats: %d of %d by run %d %s; totals %s; bosses %s; bases cast %d" % [
		profile.feats.size(), Content.FEATS.size(), CAREER_RUNS, str(profile.feats.keys()),
		str(profile.totals), str(profile.bosses_beaten), profile.cast_ever.size()])
	if profile.feats.size() < CAREER_MIN_FEATS:
		_fail("the career earned %d feats by run %d, want at least %d" % [profile.feats.size(), CAREER_RUNS, CAREER_MIN_FEATS])
	for fid in profile.feats:
		if String(profile.feats[fid]["date"]) != "2026-01-01":
			_fail("feat %s is not dated off the summary (%s)" % [fid, str(profile.feats[fid])])
			break
	if profile.totals.is_empty() or profile.cast_ever.is_empty():
		_fail("the career folded no totals or casts (%s / %s)" % [str(profile.totals), str(profile.cast_ever)])

	# 2) save/load roundtrip (the career layer's stores included: the NEW
	# badges the career loop left in `unseen`, plus a daily's tries, first and
	# best results, one of them carrying a score)
	if profile.unseen.is_empty():
		_fail("a 40-run career left nothing unseen (record_run is not filing unlocks)")
	profile.note_daily_try(777)
	profile.note_daily_try(777)
	profile.record_daily({"won": false, "floor": 3, "turns": 60, "seed": 777, "score": 410})
	profile.record_daily({"won": true, "floor": 7, "turns": 140, "seed": 777, "score": 1900})
	var path := "user://test_profile.json"
	profile.save(path)
	var loaded = Profile.load_from(path)
	var saved_d: Dictionary = profile.to_dict()
	var back_d: Dictionary = loaded.to_dict()
	var diffs: Array = []
	for k in saved_d:
		if str(saved_d[k]) != str(back_d.get(k, null)):
			diffs.append(k)
	for k in back_d:
		if not saved_d.has(k):
			diffs.append("extra:" + String(k))
	if not diffs.is_empty():
		_fail("profile save/load mismatch on %s" % str(diffs))
		for k in diffs:
			print("    saved  %s = %s" % [k, str(saved_d.get(k, null)).substr(0, 300)])
			print("    loaded %s = %s" % [k, str(back_d.get(k, null)).substr(0, 300)])
	else:
		print("profile save/load roundtrip: OK (%d keys)" % saved_d.size())
	_check_load_filters()

	# 3) each mutator smoke-tested
	for mut in Content.MUTATORS:
		var m := Sweep.measure(MUTATOR_SEEDS, {"mutators": [mut]})
		print("mutator %-14s %d/%d wins, avg floor %.1f" % [mut, m["wins"], MUTATOR_SEEDS, m["avg_floor"]])

	# 4a) packages: ids land in the pool, the base pool is otherwise untouched
	for pkg in Content.PACKAGES:
		var pool: Array = Game.new(1, {"packages": [pkg]}).draft_pool
		var msg := _package_pool_problem(pkg, pool)
		if msg != "":
			_fail("package %s: %s" % [pkg, msg])
	print("package pools: OK (%d packages)" % Content.PACKAGES.size())

	# 4b) mutator invariant table (in the test, not in content)
	for mut in Content.MUTATORS:
		var msg := _mutator_invariant_problem(mut)
		if msg != "":
			_fail("mutator %s invariant: %s" % [mut, msg])
	print("mutator invariants: OK (%d mutators)" % Content.MUTATORS.size())

	# 4c) game_config clamps: tier to what is unlocked, unknown mutators dropped
	var clamped: Dictionary = profile.game_config(9, ["nonexistent"])
	if int(clamped["tier"]) != profile.unlocked_tier or int(clamped["tier"]) > Content.TIERS.size():
		_fail("game_config(9, ...) tier %d, unlocked %d" % [int(clamped["tier"]), profile.unlocked_tier])
	if not clamped["mutators"].is_empty():
		_fail("game_config(9, ['nonexistent']) returned mutators %s" % str(clamped["mutators"]))
	if clamped.keys() != ["packages", "tier", "mutators", "loadout"]:
		_fail("game_config shape changed: %s" % str(clamped.keys()))
	var fresh: Dictionary = Profile.new().game_config(9, ["kit_of_3"])
	if int(fresh["tier"]) != 0 or not fresh["mutators"].is_empty() or not fresh["packages"].is_empty():
		_fail("fresh profile game_config(9, ['kit_of_3']) = %s" % str(fresh))
	print("game_config clamp: OK (tier %d -> %d, mutators dropped)" % [9, int(clamped["tier"])])

	# 4d) a career that never leaves tier 0: the unreachable set is exact
	var p0 = Profile.new()
	for s in range(1, TIER0_CAREER_RUNS + 1):
		p0.record_run(_career_summary(s, _career_config(p0, 0)))
	var unreachable: Array = []
	for m in Content.MILESTONES:
		var id := String(m["id"])
		if not p0.unlocked_packages.has(id) and not p0.unlocked_mutators.has(id) \
			and not p0.unlocked_loadouts.has(id) and not p0.unlocked_grafts.has(id):
			unreachable.append(id)
	unreachable.sort()
	var want: Array = TIER0_UNREACHABLE.duplicate()
	want.sort()
	print("tier-0 career: %d runs, %d wins, best floor %d, grow_spike casts %d, locked milestones %s" % [
		p0.runs, p0.wins, p0.best_floor, int(p0.casts_by_base.get("grow_spike", 0)), str(unreachable)])
	if unreachable != want:
		_fail("tier-0 career locked set %s, expected %s" % [str(unreachable), str(want)])
	# a casts milestone has to be a bar the bot career can actually clear
	var casts_bar := 0
	for m in Content.MILESTONES:
		var req: Dictionary = m["requires"]
		if req.has("casts"):
			casts_bar = maxi(casts_bar, int(req["casts"].get("grow_spike", 0)))
	var cast_have := int(p0.casts_by_base.get("grow_spike", 0))
	if casts_bar > 0 and cast_have < casts_bar:
		_fail("the casts milestone wants %d grow_spikes; a tier-0 career lands %d" % [casts_bar, cast_have])

	# 4e) the roster covers every persona playtest runs by default
	for name in Roster.LEGACY:
		if not Roster.has(name):
			_fail("playtest persona '%s' missing from Roster.BOTS" % name)
	print("roster: %d personas, legacy %s: OK" % [Roster.names().size(), str(Roster.LEGACY)])

	# 5) C4 profile bookkeeping
	_check_history_cap()
	_check_predicates()
	_check_dispatch()
	_check_daily()

	# 6) Block A run setup
	_check_loadouts()
	_check_game_config()
	_check_daily_config()
	_check_loadout_winnable()

	# 7) profile io that has to survive a phone: a file that is not a profile,
	# a tier from a build with more tiers, and a save that is interrupted
	_check_bad_profile_files()
	_check_wrong_type_profile()
	_check_tier_clamp()
	_check_atomic_save()

	# 8) fun pass: the run-stats fold, the score, records
	print("run-stats interface pin: %d career summaries checked, %d key problem(s)" % [_pin_runs, _pin_seen.size()])
	_check_run_stats()
	_check_score_bests()
	_check_records()

	# 9) fun pass, career layer: the goal ladder, NEW badges, the daily streak
	_check_progress()
	_check_next_goals()
	_check_unseen()
	_check_daily_streak()

	# 10) fun pass, career B: feats
	_check_feats()
	_check_feat_folds()
	_check_feat_progress()
	_check_feat_backfill()
	_check_goal_rows()
	# 11) fun pass, career C: the in-run ping data
	_check_run_ref()

	if failures == 0:
		print("meta: OK")
	quit(1 if failures > 0 else 0)


func _fail(msg: String) -> void:
	failures += 1
	print("FAIL: %s" % msg)


## `got` must equal `want`; counts and reports a mismatch.
func _expect(got, want, label: String) -> void:
	if got != want:
		_fail("%s: got %s, expected %s" % [label, str(got), str(want)])


## The config a career plays at `tier`: the tender loadout and the first
## package it owns - a run commits to ONE package now (review §6.1 item 3),
## so the simulated career exercises the same shape a real one does.
func _career_config(profile, tier: int) -> Dictionary:
	var pkg := "" if profile.unlocked_packages.is_empty() else String(profile.unlocked_packages[0])
	return profile.game_config(tier, [], "tender", pkg)


## One optimizer run, handing back the record the SHELL would send: the sim's
## own run_summary() merged with the RunStats fold fed after every step, plus
## the cosmetic score (shell/main.gd _record_finished_run's exact merge). The
## loop mirrors Sweep.run_loop - set_sim, the MAX_ACTIONS / MAX_TURNS guard -
## so the career plays exactly the games it always did. Each summary is also
## the cross-cluster interface pin: every Content.RUN_STAT_KEYS key an int,
## bosses_killed an Array, score an int, and run_summary() and the fold's
## summary() share no key (a merge must never overwrite the sim's record).
func _career_summary(seed_v: int, cfg: Dictionary) -> Dictionary:
	var g = Game.new(seed_v, cfg)
	var bot = Roster.make("optimizer", seed_v)
	if bot.has_method("set_sim"):
		bot.set_sim(g)
	var st = RunStats.new()
	st.begin(g)
	var actions := 0
	while not g.over and actions < Sweep.MAX_ACTIONS and g.total_turns < Sweep.MAX_TURNS:
		var act: Dictionary = bot.choose_action(g.snapshot(), g.legal_actions())
		st.feed(g, g.step(act))
		actions += 1
	var summary: Dictionary = g.run_summary()
	var folded: Dictionary = st.summary()
	for k in summary:
		if folded.has(k):
			_pin("run_summary and RunStats.summary both carry '%s'" % k)
	summary.merge(folded)
	summary["tier"] = int(cfg.get("tier", 0))
	summary["score"] = int(RunStats.score(summary)["total"])
	summary["score_v"] = Content.RUN_SCORE_VERSION
	summary["date"] = "2026-01-01"
	for k in Content.RUN_STAT_KEYS:
		if not (summary.get(k, null) is int):
			_pin("summary key '%s' is not an int (%s)" % [k, str(summary.get(k, null))])
	if not (summary.get("bosses_killed", null) is Array):
		_pin("summary bosses_killed is not an Array")
	if not (summary.get("score", null) is int):
		_pin("summary score is not an int")
	for row in Content.RUN_SCORE:
		if not summary.has(String(row["key"])):
			_pin("RUN_SCORE key '%s' is missing from a merged summary (it would always score 0)" % String(row["key"]))
	_pin_runs += 1
	return summary


## One interface-pin failure, reported once however many runs repeat it.
func _pin(msg: String) -> void:
	if _pin_seen.has(msg):
		return
	_pin_seen[msg] = true
	_fail("interface pin: " + msg)


# --- 2b) load_from filters ids Content no longer carries ----------------------

func _check_load_filters() -> void:
	var dirty := {
		"runs": 3, "wins": 1, "tier_wins": 0, "best_floor": 7, "unlocked_tier": 1,
		"unlocked_packages": ["mycology", "ghost_package"],
		"unlocked_mutators": ["kit_of_3", "ghost_mutator"],
		"unlocked_grafts": ["deep_cells", "ghost_graft"],
		"unlocked_loadouts": ["tidewarden", "ghost_loadout"],
		"casts_by_base": {"grow_spike": 12, "ghost_ability": 99},
		"daily_best": {"42": {"won": true, "floor": 9, "turns": 100}},
		"history": [{
			"won": true, "floor": 9, "tier": 0, "turns": 80, "seed": 5,
			"kit": ["solar_lance", "ghost_ability", "seed_bomb+"],
			"grafts": ["deep_cells", "ghost_graft"],
		}],
		# career layer: junk in every new store
		"unseen": ["mycology", "hydraulics", "ghost_package", "tier:1", "tier:5", "tier:x",
			"feat:ghost_feat", "feat:heavy_hand", "feat:green_thumb", 7, "mycology"],
		"daily_tries": {"42": 3.0, "43": "lots", "not_a_seed": 2, "44": -1},
		"daily_first": {"42": {"won": false, "floor": 4, "turns": 50, "score": "high"},
			"x": {"won": true, "floor": 9, "turns": 1}, "45": "junk"},
		# career B: junk in every feat store
		"feats": {"green_thumb": {"date": "2026-01-02", "run": 2.0}, "ghost_feat": {"date": "x", "run": 1},
			"heavy_hand": "junk", "barefoot": {"date": 5, "run": "two"}},
		"totals": {"kills": 120.0, "ghost_key": 9, "cleanses": "lots", "rooms_bloomed": -3},
		"bosses_beaten": ["overseer", "drill_bot", "ghost_boss", 4, "overseer"],
		"cast_ever": ["vine_whip", "ghost_ability", "seed_bomb+tangle", "seed_bomb", 3, "grow_spike+"],
	}
	var path := "user://test_profile_dirty.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(dirty))
	f.close()
	var p = Profile.load_from(path)
	_expect(p.unlocked_packages, ["mycology"], "load_from drops an unknown package")
	_expect(p.unlocked_mutators, ["kit_of_3"], "load_from drops an unknown mutator")
	_expect(p.unlocked_grafts, ["deep_cells"], "load_from drops an unknown graft")
	_expect(p.unlocked_loadouts, ["tidewarden"], "load_from keeps a known loadout and drops an unknown one")
	_expect(str(p.casts_by_base), str({"grow_spike": 12}), "load_from drops casts for an unknown ability")
	_expect(p.history.size(), 1, "load_from keeps a history entry with unknown ids")
	# Block D6 renamed every "<base>+" row: a career saved before it stores the
	# dead id "seed_bomb+", which Profile._migrate_ability_id maps to that
	# base's FIRST variant (the one that reproduces the pre-D6 row), so the win
	# a player really earned still satisfies won_with
	_expect(p.history[0]["kit"], ["solar_lance", "seed_bomb+tangle"],
		"load_from filters the ids inside a history entry and migrates a pre-D6 + id")
	_expect(p.history[0]["grafts"], ["deep_cells"], "load_from filters a history entry's grafts")
	_expect(int(p.history[0]["floor"]), 9, "load_from keeps the entry's scalars")
	_expect(str(p.daily_best), str({"42": {"won": true, "floor": 9, "turns": 100}}), "load_from carries daily_best")
	# the filtered profile still evaluates predicates over what survived
	_expect(p._meets({"won_with": ["seed_bomb+tangle"]}), true, "migrated history still satisfies won_with")
	# the career layer's stores: an unseen id must name something owned now
	# (hydraulics is not unlocked, tier 5 is past unlocked_tier, an unearned
	# or unknown feat goes), each once; tries are positive ints keyed by a seed;
	# a daily result is rebuilt, its non-number score dropped
	_expect(p.unseen, ["mycology", "tier:1", "feat:green_thumb"],
		"load_from filters unseen to what the career owns (an unearned or unknown feat goes)")
	# the feat stores: a known feat with a dict entry loads (a bad date or run
	# reads its default), totals keep positive ints of known keys, bosses keep
	# boss-trait kinds once, cast_ever keeps live BASE ids once (a variant or a
	# pre-D6 "+" id folds to its base)
	_expect(str(p.feats), str({"barefoot": {"date": "", "run": 0}, "green_thumb": {"date": "2026-01-02", "run": 2}}),
		"load_from filters feats to known ids with dictionary entries")
	_expect(str(p.totals), str({"kills": 120}), "load_from keeps only positive int totals of known keys")
	_expect(p.bosses_beaten, ["overseer"], "load_from keeps only boss kinds, once")
	_expect(p.cast_ever, ["vine_whip", "seed_bomb", "grow_spike"], "load_from keeps live base ids, folded, once")
	_expect(str(p.daily_tries), str({"42": 3}), "load_from keeps only int tries keyed by a seed")
	_expect(str(p.daily_first), str({"42": {"won": false, "floor": 4, "turns": 50}}),
		"load_from rebuilds daily_first and drops a non-number score")
	print("load_from filters unknown ids: OK")


# --- 5) C4 profile bookkeeping ------------------------------------------------

func _check_history_cap() -> void:
	var p = Profile.new()
	var n: int = Profile.HISTORY_MAX + 20
	for i in range(n):
		p.record_run({"won": false, "floor": 1 + i % 3, "tier": 0, "seed": i, "turns": i})
	_expect(p.history.size(), Profile.HISTORY_MAX, "history capped")
	_expect(p.runs, n, "runs counts every recorded run")
	_expect(int(p.history[0]["seed"]), n - Profile.HISTORY_MAX, "oldest history entry dropped")
	_expect(int(p.history[p.history.size() - 1]["seed"]), n - 1, "newest history entry last")
	print("history cap: OK (%d runs -> %d entries)" % [n, p.history.size()])


func _check_predicates() -> void:
	# won_with / wins_without / grafts_owned_at_win over one recorded win
	var p = Profile.new()
	p.record_run({"won": true, "floor": 9, "tier": 0, "turns": 120, "seed": 1,
		"kit": ["solar_lance+noon", "seed_bomb", "grow_spike"], "grafts": ["deep_cells"]})
	_expect(p._meets({"won_with": ["solar_lance"]}), true, "won_with: a variant satisfies its base")
	_expect(p._meets({"won_with": ["solar_lance+noon"]}), true, "won_with: the exact variant id")
	_expect(p._meets({"won_with": ["solar_lance+pierce"]}), false, "won_with: the SIBLING variant does not satisfy it")
	_expect(p._meets({"won_with": ["seed_bomb+tangle"]}), false, "won_with: a base does not satisfy a variant id")
	_expect(p._meets({"won_with": ["solar_lance", "grow_spike"]}), true, "won_with: every id, one run")
	_expect(p._meets({"won_with": ["solar_lance", "vine_whip"]}), false, "won_with: one id missing")
	_expect(p._meets({"wins_without": ["solar_lance"]}), false, "wins_without: the win held it as a variant")
	_expect(p._meets({"wins_without": ["vine_whip", "water_jet"]}), true, "wins_without: held none of them")
	_expect(p._meets({"grafts_owned_at_win": 1}), true, "grafts_owned_at_win: 1 held")
	_expect(p._meets({"grafts_owned_at_win": 2}), false, "grafts_owned_at_win: only 1 held")
	# a loss satisfies no history predicate
	var q = Profile.new()
	q.record_run({"won": false, "floor": 4, "tier": 0, "kit": ["vine_whip"],
		"grafts": ["deep_cells", "thick_bark"]})
	_expect(q._meets({"won_with": ["vine_whip"]}), false, "won_with ignores a loss")
	_expect(q._meets({"wins_without": ["solar_lance"]}), false, "wins_without ignores a loss")
	_expect(q._meets({"grafts_owned_at_win": 2}), false, "grafts_owned_at_win ignores a loss")
	# a later win, without the id, satisfies wins_without
	q.record_run({"won": true, "floor": 9, "tier": 0, "kit": ["vine_whip", "grow_spike"], "grafts": []})
	_expect(q._meets({"wins_without": ["solar_lance"]}), true, "wins_without: a win with none of them")
	_expect(q._meets({"grafts_owned_at_win": 1}), false, "grafts_owned_at_win: the win held none")
	# casts: effective casts summed across runs
	var c = Profile.new()
	c.record_run({"won": false, "floor": 2, "tier": 0, "effective_uses_by_base": {"grow_spike": 25}})
	_expect(c._meets({"casts": {"grow_spike": 60}}), false, "casts: 25 of 60")
	c.record_run({"won": false, "floor": 2, "tier": 0, "effective_uses_by_base": {"grow_spike": 35, "vine_whip": 4}})
	_expect(int(c.casts_by_base.get("grow_spike", 0)), 60, "casts_by_base sums across runs")
	_expect(c._meets({"casts": {"grow_spike": 60}}), true, "casts: 25 + 35 clears 60")
	_expect(c._meets({"casts": {"grow_spike": 61}}), false, "casts: one short")
	_expect(c._meets({"casts": {"grow_spike": 60, "vine_whip": 5}}), false, "casts: every id must clear its bar")
	# the legacy {won, floor, tier} record still works
	var l = Profile.new()
	l.record_run({"won": true, "floor": 9, "tier": 1})
	_expect(l.wins, 1, "legacy record counts the win")
	_expect(l.tier_wins, 1, "legacy record counts the tier win")
	_expect(l.best_floor, 9, "legacy record tracks the floor")
	_expect(l.history[0]["kit"], [], "legacy record stores an empty kit")
	_expect(bool(l.history[0].get("has_kit", true)), false, "legacy record is marked as carrying no kit")
	_expect(l._meets({"wins_without": ["solar_lance"]}), false, "legacy record never satisfies wins_without (no kit known)")
	_expect(l.unlocked_mutators.has("no_lance"), false, "legacy win does not unlock no_lance")
	# ...and stays kit-less across a save and a reload: load_from runs the
	# stored entry back through _compact, where the reloaded `kit: []` key
	# used to flip has_kit to true and let the next claim grant no_lance
	var legacy_path := "user://test_profile_legacy_kit.json"
	l.save(legacy_path)
	var lb = Profile.load_from(legacy_path)
	DirAccess.remove_absolute(legacy_path)
	_expect(bool(lb.history[0].get("has_kit", true)), false, "legacy record keeps has_kit false across save + reload")
	_expect(lb._meets({"wins_without": ["solar_lance"]}), false, "reloaded legacy record never satisfies wins_without")
	lb.record_run({"won": false, "floor": 2, "tier": 0})
	_expect(lb.unlocked_mutators.has("no_lance"), false, "reloaded legacy win does not unlock no_lance on the next claim")
	_expect(str(l.casts_by_base), str({}), "legacy record stores no casts")
	# the three new milestone rows read exactly these predicates
	var seen := {}
	for m in Content.MILESTONES:
		seen[String(m["id"])] = m
	_expect(seen.has("no_lance") and seen.has("wide_draft") and seen.has("upgrades_only"), true,
		"MILESTONES carries the three C4 rows")
	for id in ["no_lance", "wide_draft", "upgrades_only"]:
		var row: Dictionary = seen[id]
		_expect(String(row["kind"]), "mutator", "milestone %s kind" % id)
		_expect(Content.MUTATORS.has(id), true, "milestone %s names a real mutator" % id)
		_expect(String(row["desc"]) != "", true, "milestone %s has a desc" % id)
	print("milestone predicates: OK")


func _check_dispatch() -> void:
	var p = Profile.new()
	p.milestone_rows = FIXTURE_MILESTONES.duplicate(true)
	print("  (each record below prints the expected unknown-kind push_error for fx_bogus)")
	var news: Array = p.record_run({"won": false, "floor": 3, "tier": 0})
	_expect(news, ["fx_package"], "dispatch: only the free package unlocks first")
	_expect(p.unlocked_packages, ["fx_package"], "dispatch: package -> unlocked_packages")
	news = p.record_run({"won": true, "floor": 9, "tier": 0, "kit": ["seed_bomb"],
		"grafts": ["deep_cells", "thick_bark"]})
	_expect(news, ["fx_mutator", "fx_loadout", "fx_graft"], "dispatch: the three known kinds unlock")
	_expect(p.unlocked_mutators, ["fx_mutator"], "dispatch: mutator -> unlocked_mutators")
	_expect(p.unlocked_loadouts, ["fx_loadout"], "dispatch: loadout -> unlocked_loadouts")
	_expect(p.unlocked_grafts, ["fx_graft"], "dispatch: graft -> unlocked_grafts")
	_expect(p._owned("fx_bogus"), false, "dispatch: an unknown kind unlocks nothing")
	# a real profile never has to dispatch an unknown kind
	for m in Content.MILESTONES:
		if not ["package", "mutator", "loadout", "graft"].has(String(m["kind"])):
			_fail("MILESTONES row %s has undispatchable kind '%s'" % [String(m["id"]), String(m["kind"])])
	print("milestone kind dispatch: OK")


func _check_daily() -> void:
	var p = Profile.new()
	p.record_daily({"won": false, "floor": 4, "turns": 90, "seed": 777})
	p.record_daily({"won": true, "floor": 9, "turns": 200, "seed": 777})
	p.record_daily({"won": true, "floor": 9, "turns": 150, "seed": 777})  # better: fewer turns
	p.record_daily({"won": false, "floor": 12, "turns": 10, "seed": 777})  # a loss never beats a win
	p.record_daily({"won": false, "floor": 3, "turns": 40, "seed": 778})
	_expect(p.runs, 0, "daily does not count as a run")
	_expect(p.wins, 0, "daily does not count as a win")
	_expect(p.best_floor, 0, "daily does not move best_floor")
	_expect(p.unlocked_tier, 0, "daily unlocks no tier")
	_expect(p.history, [], "daily writes no history")
	_expect(p.unlocked_packages, [], "daily unlocks no package")
	_expect(str(p.daily_best["777"]), str({"won": true, "floor": 9, "turns": 150}), "daily keeps the best result")
	_expect(str(p.daily_best["778"]), str({"won": false, "floor": 3, "turns": 40}), "daily files each seed")
	# and it survives the codec
	var path := "user://test_profile_daily.json"
	p.save(path)
	var back = Profile.load_from(path)
	_expect(str(back.daily_best), str(p.daily_best), "daily_best round-trips")
	print("daily records: OK (%d seeds filed, career untouched)" % p.daily_best.size())


# --- 6) Block A: loadouts, run setup, dailies ---------------------------------

## Every Content.LOADOUTS row as the meta layer reads it: three known
## abilities, exactly one of them mobility, and tender still the starting kit
## (tests/test_content.gd lints the rest of the row).
func _check_loadouts() -> void:
	for lid in Content.LOADOUTS:
		var kit: Array = Content.LOADOUTS[lid]["kit"]
		_expect(kit.size(), 3, "loadout %s kit size" % lid)
		var mob := 0
		for aid in kit:
			if not Content.ABILITIES.has(String(aid)):
				_fail("loadout %s names unknown ability %s" % [lid, str(aid)])
			elif String(Content.ABILITIES[String(aid)]["role"]) == "mobility":
				mob += 1
		_expect(mob, 1, "loadout %s mobility abilities" % lid)
	_expect(Content.LOADOUTS["tender"]["kit"], Content.STARTING_KIT, "tender plays the starting kit")
	print("loadouts: %d rows, each 3 known abilities with exactly one mobility" % Content.LOADOUTS.size())


## The career gate around a run config: a loadout must be tender or unlocked
## AND have its package requirement met, and a run commits to at most one
## unlocked package (never the whole shelf).
func _check_game_config() -> void:
	var p = Profile.new()
	var c0: Dictionary = p.game_config(0, [], "tidewarden", "mycology")
	_expect(String(c0["loadout"]), "tender", "game_config: a locked loadout falls back to tender")
	_expect(c0["packages"], [], "game_config: a locked package is dropped")
	_expect(c0.has("kit"), false, "game_config never sends a kit (the loadout carries it)")
	_expect(String(p.game_config(0, [], "no_such_loadout")["loadout"]), "tender",
		"game_config: an unknown loadout id plays tender")
	p.unlocked_loadouts = ["tidewarden", "skyrunner"]
	p.unlocked_packages = ["mycology"]
	_expect(String(p.game_config(0, [], "tidewarden")["loadout"]), "tidewarden",
		"game_config: an unlocked loadout is played")
	_expect(String(p.game_config(0, [], "skyrunner")["loadout"]), "tender",
		"game_config: an unlocked loadout with an unmet package requirement falls back")
	_expect(p.available_loadouts(), ["tender", "tidewarden"], "available_loadouts hides the unmet one")
	p.unlocked_packages = ["mycology", "aeolian"]
	_expect(String(p.game_config(0, [], "skyrunner")["loadout"]), "skyrunner",
		"game_config: the requirement met, the loadout is played")
	_expect(p.available_loadouts(), ["tender", "tidewarden", "skyrunner"],
		"available_loadouts: tender plus the unlocked loadouts whose requires are met")
	_expect(p.game_config(0, [], "tender", "mycology")["packages"], ["mycology"],
		"game_config commits the asked-for package")
	_expect(p.game_config(0, [], "tender", "hydraulics")["packages"], [],
		"game_config drops a locked package")
	_expect(p.game_config(0, [], "tender", "")["packages"], [], "game_config: no package asked, none committed")
	# one package per run: the pool is base + 3, never base + every package
	var pool: Array = Game.new(1, p.game_config(0, [], "tender", "mycology")).draft_pool
	_expect(pool.size(), Content.DRAFT_POOL.size() + Content.PACKAGES["mycology"].size(),
		"a committed package pools 3 ids, not every package's")
	var kit: Array = Game.new(1, p.game_config(0, [], "skyrunner", "aeolian")).player["kit"]
	_expect(kit, Content.LOADOUTS["skyrunner"]["kit"], "the config's loadout reaches the sim's kit")
	print("game_config: OK (loadout gate, one package per run)")


## The daily is career-agnostic and frozen: `daily_config` is a pure function
## of the seed, every pick comes off the profile's own DAILY_* lists (never a
## live Content table), and the config it makes plays in the sim.
func _check_daily_config() -> void:
	var d1: Dictionary = Profile.daily_config(12345)
	_expect(d1.keys(), ["loadout", "package", "mutator", "tier"], "daily_config shape")
	_expect(int(d1["tier"]), 0, "a daily is always tier 0")
	_expect(str(Profile.daily_config(12345)), str(d1), "daily_config is a pure function of the seed")
	var off_list := 0
	var loadouts := {}
	var packages := {}
	var mutators := {}
	for s in range(1, 401):
		var d: Dictionary = Profile.daily_config(s)
		if not Profile.DAILY_LOADOUTS.has(String(d["loadout"])) \
			or not Profile.DAILY_PACKAGES.has(String(d["package"])) \
			or not Profile.DAILY_MUTATORS.has(String(d["mutator"])) or int(d["tier"]) != 0:
			off_list += 1
		loadouts[d["loadout"]] = true
		packages[d["package"]] = true
		mutators[d["mutator"]] = true
	_expect(off_list, 0, "every daily picks off the frozen lists at tier 0")
	_expect(loadouts.size(), Profile.DAILY_LOADOUTS.size(), "400 seeds reach every daily loadout")
	_expect(packages.size(), Profile.DAILY_PACKAGES.size(), "...every package choice, none included")
	_expect(mutators.size(), Profile.DAILY_MUTATORS.size(), "...every mutator choice, none included")
	# the frozen lists name real content, and nothing on them needs an unlock
	for lid in Profile.DAILY_LOADOUTS:
		if not Content.LOADOUTS.has(lid):
			_fail("DAILY_LOADOUTS names unknown loadout %s" % lid)
		elif not Content.LOADOUTS[lid]["requires"].get("packages", []).is_empty():
			_fail("daily loadout %s needs a package unlock" % lid)
	for pkg in Profile.DAILY_PACKAGES:
		if pkg != "" and not Content.PACKAGES.has(String(pkg)):
			_fail("DAILY_PACKAGES names unknown package %s" % str(pkg))
	for mut in Profile.DAILY_MUTATORS:
		if mut != "" and not Content.MUTATORS.has(String(mut)):
			_fail("DAILY_MUTATORS names unknown mutator %s" % str(mut))
	# and the run config it makes is exactly those three choices
	for s in [7, 99, 4242]:
		var d: Dictionary = Profile.daily_config(s)
		var g = Game.new(s, Profile.daily_game_config(s))
		_expect(g.loadout, String(d["loadout"]), "daily seed %d: the sim plays its loadout" % s)
		_expect(g.player["kit"], Content.LOADOUTS[d["loadout"]]["kit"], "daily seed %d: its kit" % s)
		_expect(g.packages, [] if String(d["package"]) == "" else [String(d["package"])],
			"daily seed %d: its package" % s)
		_expect(g.mutators, [] if String(d["mutator"]) == "" else [String(d["mutator"])],
			"daily seed %d: its mutator" % s)
		_expect(g.tier, 0, "daily seed %d: tier 0" % s)
	print("daily_config: OK (pure over %d loadouts x %d packages x %d mutators, frozen)" % [
		Profile.DAILY_LOADOUTS.size(), Profile.DAILY_PACKAGES.size(), Profile.DAILY_MUTATORS.size()])


## Every loadout has to be playable, not just legal: the optimizer over seeds
## 1..LOADOUT_SEEDS must win with each of them. A loadout that needs a package
## is measured with that package committed, at the lower skyrunner bar.
func _check_loadout_winnable() -> void:
	var seeds := Sweep.seed_list_from(LOADOUT_SEEDS, 1)
	for lid in Content.LOADOUTS:
		var cfg := {"loadout": lid}
		var need := LOADOUT_MIN_WINS
		var reqs: Array = Content.LOADOUTS[lid]["requires"].get("packages", [])
		if not reqs.is_empty():
			cfg["packages"] = reqs.duplicate()
			need = SKYRUNNER_MIN_WINS
		var m := Sweep.measure(seeds, cfg, "optimizer")
		print("loadout %-12s %d/%d wins, avg floor %.1f%s" % [lid, int(m["wins"]), seeds.size(),
			float(m["avg_floor"]), "" if reqs.is_empty() else "  (packages %s)" % str(reqs)])
		if int(m["wins"]) < need:
			_fail("loadout %s: %d/%d optimizer wins over seeds 1..%d, needs %d" % [
				lid, int(m["wins"]), seeds.size(), LOADOUT_SEEDS, need])
	print("loadout winnability: %d loadouts, optimizer seeds 1..%d" % [Content.LOADOUTS.size(), LOADOUT_SEEDS])


## "" when `pool` is DRAFT_POOL followed by the package's ids (each present
## exactly once), else a description of the problem.
func _package_pool_problem(pkg: String, pool: Array) -> String:
	var ids: Array = Content.PACKAGES[pkg]
	for aid in ids:
		if not pool.has(aid):
			return "id %s missing from draft_pool %s" % [aid, str(pool)]
	var base: Array = []
	for aid in pool:
		if not ids.has(aid):
			base.append(aid)
	if base != Content.DRAFT_POOL:
		return "pool minus package ids %s != DRAFT_POOL" % str(base)
	if pool.size() != Content.DRAFT_POOL.size() + ids.size():
		return "pool size %d, expected %d" % [pool.size(), Content.DRAFT_POOL.size() + ids.size()]
	return ""


## Declared invariant per mutator on a fresh game; "" when it holds. A
## mutator without a row here fails: new content must add its expectation.
## `_kit_max` is a sim-private helper; reading it from a test is fine (the
## sim exposes no public cap and the test never writes state).
func _mutator_invariant_problem(mut: String) -> String:
	var cfg := {"mutators": [mut]}
	match mut:
		"kit_of_3":
			var g = Game.new(1, cfg)
			if g._kit_max() != 3:
				return "_kit_max() == %d, expected 3" % g._kit_max()
			if Game.new(1)._kit_max() != Content.KIT_MAX:
				return "base game _kit_max() != KIT_MAX"
		"boarded":
			var g = Game.new(1, cfg.merged({"bloom": 20}))
			if not g.shop.is_empty():
				return "floor-1 shop is %s, expected {}" % str(g.shop)
			if Game.new(1).shop.is_empty():
				return "base game floor-1 shop is empty too (check proves nothing)"
			# a boarded shrine boards the press and the forge too: nothing to
			# buy, upcycle or upcycle_ability even with bloom, items and a kit
			g.player["pos"] = g.map["shrine"]
			g.player["items"] = ["balm_fruit", "sun_capsule"]
			g.player["hp"] = 5
			for a in g.legal_actions():
				var t := String(a.get("type", ""))
				if t == "buy" or t == "upcycle" or t == "upcycle_ability":
					return "boarded shrine still offers %s" % str(a)
			var open_g = Game.new(1, {"bloom": 20})
			open_g.player["pos"] = open_g.map["shrine"]
			open_g.player["items"] = ["balm_fruit", "sun_capsule"]
			var kinds := {}
			for a in open_g.legal_actions():
				kinds[String(a.get("type", ""))] = true
			if not (kinds.has("buy") and kinds.has("upcycle") and kinds.has("upcycle_ability")):
				return "open shrine offers %s (check proves nothing)" % str(kinds.keys())
		"parched":
			# end a turn with the full 3 charge left: nothing may carry over
			var g = Game.new(1, cfg)
			var before: int = g.player["charge"]
			g.step({"type": "end_turn"})
			var regen: int = maxi(1, Content.BASE_REGEN - g.dim)
			if g.player["bank"] != 0 or g.player["charge"] != regen:
				return "after end_turn with %d charge: bank %d charge %d, expected bank 0 charge %d" % [
					before, g.player["bank"], g.player["charge"], regen]
			var base = Game.new(1)
			base.step({"type": "end_turn"})
			if base.player["charge"] <= regen:
				return "base game did not bank charge (%d), check proves nothing" % base.player["charge"]
		"brittle":
			var g = Game.new(1, cfg)
			if g.player["max_hp"] != Content.PLAYER_HP - 3 or g.player["hp"] != Content.PLAYER_HP - 3:
				return "hp %d/%d, expected %d/%d" % [g.player["hp"], g.player["max_hp"], Content.PLAYER_HP - 3, Content.PLAYER_HP - 3]
		"double_oil":
			for s in range(1, 6):
				var g = Game.new(s, cfg)
				var base = Game.new(s)
				if int(g.floor_def(1)["oil"]) != int(Content.FLOORS[0]["oil"]) * 2:
					return "floor_def(1).oil %d, expected %d" % [int(g.floor_def(1)["oil"]), int(Content.FLOORS[0]["oil"]) * 2]
				if _oil_count(g) < _oil_count(base):
					return "seed %d: %d oil tiles < base game's %d" % [s, _oil_count(g), _oil_count(base)]
		"overtime":
			var g = Game.new(1, cfg)
			var fdef: Dictionary = g.floor_def(1)
			# Block E1: a floor's roster is the drawn pack (floor_def), never a FLOORS key
			var base_enemies: Dictionary = Game.new(1).floor_def(1)["enemies"]
			var common := ""
			var common_n := 0
			for kind in base_enemies:
				if int(base_enemies[kind]) > common_n:
					common_n = int(base_enemies[kind])
					common = kind
			if int(fdef["enemies"][common]) != common_n + 1:
				return "floor_def(1).enemies[%s] == %d, expected %d" % [common, int(fdef["enemies"][common]), common_n + 1]
			if g.floor_def(Content.FLOORS.size())["enemies"] != Game.new(1).floor_def(Content.FLOORS.size())["enemies"]:
				return "boss floor enemies changed by overtime"
		"no_lance":
			# gone from the starting kit, the draft pool and (through the pool)
			# the shrine's ability stock; the base game holds it in both
			var g = Game.new(1, cfg)
			if g.player["kit"] != ["seed_bomb", "mycelium_dash"]:
				return "kit %s, expected [seed_bomb, mycelium_dash]" % str(g.player["kit"])
			if not Game.new(1).player["kit"].has("solar_lance"):
				return "base game kit lacks solar_lance (check proves nothing)"
			if not Content.DRAFT_POOL.has("solar_lance"):
				return "DRAFT_POOL lacks solar_lance (check proves nothing)"
			for aid in g.draft_pool:
				if Content.base_id(String(aid)) == "solar_lance":
					return "draft_pool still holds %s" % str(aid)
			if g.draft_pool.size() != Content.DRAFT_POOL.size() - 1:
				return "draft_pool size %d, expected %d" % [g.draft_pool.size(), Content.DRAFT_POOL.size() - 1]
			for s in range(1, 11):
				var gs = Game.new(s, cfg)
				if String(gs.shop.get("ability", "")) == "solar_lance":
					return "seed %d: boarded-free shrine still stocks solar_lance" % s
		"open_pool":
			# the old draft-from-everything pool, now a deliberate choice: every
			# package ability joins the pool and nothing else changes
			var g = Game.new(1, cfg)
			var extra: Array = []
			for pkg in Content.PACKAGES:
				for aid in Content.PACKAGES[pkg]:
					if not g.draft_pool.has(aid):
						return "draft_pool lacks package id %s" % aid
					extra.append(aid)
			var base_ids: Array = []
			for aid in g.draft_pool:
				if not extra.has(aid):
					base_ids.append(aid)
			if base_ids != Content.DRAFT_POOL:
				return "pool minus the package ids %s != DRAFT_POOL" % str(base_ids)
			if g.draft_pool.size() != Content.DRAFT_POOL.size() + extra.size():
				return "draft_pool size %d, expected %d" % [g.draft_pool.size(), Content.DRAFT_POOL.size() + extra.size()]
			var base_g = Game.new(1)
			for aid in extra:
				if base_g.draft_pool.has(aid):
					return "base game already pools %s (check proves nothing)" % aid
		"wide_draft":
			var wide := _first_draft(2, cfg)
			var offers: Array = wide["offers"]
			if offers.size() != 4:
				return "first draft offers %d (%s), expected 4" % [offers.size(), str(offers)]
			# the extra offer is a WILD slot appended to DRAFT_SLOTS' three
			# roles - the count alone would pass with the role table ignored
			var slots: Array = wide["slots"]
			if slots.size() != offers.size():
				return "wide draft reported %d slots for %d offers" % [slots.size(), offers.size()]
			if slots != ["affinity", "upgrade", "wild", "wild"]:
				return "wide draft slots %s, expected [affinity, upgrade, wild, wild]" % str(slots)
			var base := _first_draft(2, {})
			if base["offers"].size() != 3:
				return "base game first draft offers %d (check proves nothing)" % base["offers"].size()
			if base["slots"] != ["affinity", "upgrade", "wild"]:
				return "base game first draft slots %s (check proves nothing)" % str(base["slots"])
		"upgrades_only":
			var g = Game.new(2, cfg)
			var offers := _first_draft_offers(2, cfg)
			if offers.is_empty():
				return "first draft offered nothing"
			for aid in offers:
				var s := String(aid)
				# Block D6: an upgrade id is "<base>+<variant>", so ends_with("+")
				# and trim_suffix("+") both fail silently on one
				if not Content.is_upgrade(s):
					return "offer %s is not an upgrade form (offers %s)" % [s, str(offers)]
				if not g.player["kit"].has(Content.base_id(s)):
					return "offer %s upgrades an ability the kit does not hold" % s
			# a kit of nothing but + forms leaves no candidate: the draft is skipped
			var full := Game.new(2, {"mutators": [mut],
				"kit": ["solar_lance+noon", "seed_bomb+tangle", "mycelium_dash+trail"]})
			full.player["pos"] = full.map["stairs"]
			full.greened = full.green_need
			full.step({"type": "descend"})
			if full.phase != "play" or full.floor_num != 2:
				return "an all-+ kit did not skip the draft: phase %s floor %d" % [full.phase, full.floor_num]
		"spinning_shrine":
			# the switch: a stocked shrine with bloom lists the reroll only
			# under the mutator, and the base game's derived rerolls_left is 0
			var g = Game.new(1, cfg.merged({"bloom": 20}))
			g.player["pos"] = g.map["shrine"]
			var listed := false
			for a in g.legal_actions():
				if String(a.get("type", "")) == "reroll":
					listed = true
			if not listed:
				return "spinning shrine lists no reroll on a stocked shrine with 20 bloom"
			if int(g.snapshot()["shop"].get("rerolls_left", 0)) != Content.SHOP_REROLL_CAP:
				return "rerolls_left %s, expected %d" % [str(g.snapshot()["shop"].get("rerolls_left")), Content.SHOP_REROLL_CAP]
			var base_g = Game.new(1, {"bloom": 20})
			base_g.player["pos"] = base_g.map["shrine"]
			for a in base_g.legal_actions():
				if String(a.get("type", "")) == "reroll":
					return "base game lists a reroll (check proves nothing)"
			if int(base_g.snapshot()["shop"].get("rerolls_left", -1)) != 0:
				return "base game rerolls_left %s, expected 0" % str(base_g.snapshot()["shop"].get("rerolls_left"))
		"fixed_shift":
			# Block E: the classic-crew control - every floor fields pack 0 and
			# every vent releases reinforce[0] (the drill bot); the base game
			# fields some other crew somewhere, or the check proves nothing
			var base_differs := false
			for s in range(1, 11):
				var g = Game.new(s, cfg)
				var base = Game.new(s)
				for n in range(1, Content.FLOORS.size()):
					var classic: Dictionary = Content.FLOORS[n - 1]["encounters"][0]["enemies"]
					if str(g.floor_def(n)["enemies"]) != str(classic):
						return "seed %d floor %d fields %s, expected the classic %s" % [s, n, str(g.floor_def(n)["enemies"]), str(classic)]
					if str(base.floor_def(n)["enemies"]) != str(classic):
						base_differs = true
			if not base_differs:
				return "base game fields the classic crew everywhere in seeds 1..10 (check proves nothing)"
			var fs = Game.new(1, cfg)
			var base1 = Game.new(1)
			var rotated := false
			for n in range(1, Content.FLOORS.size() + 1):
				var fdef: Dictionary = fs.floor_def(n)
				for w in range(0, 6):
					for v in range(0, 3):
						if fs.reinforce_kind(fdef, w, v) != "drill_bot":
							return "floor %d wave %d vent %d releases %s, expected drill_bot" % [n, w, v, fs.reinforce_kind(fdef, w, v)]
						if base1.reinforce_kind(fdef, w, v) != "drill_bot":
							rotated = true
			if not rotated:
				return "base game's vents release only drill bots (check proves nothing)"
		_:
			return "no invariant row in tests/test_meta.gd for mutator '%s'" % mut
	return ""


## The offers of the first descent draft on `seed_v` under `cfg` (the quota is
## handed to the player so the run does not have to be played out).
func _first_draft_offers(seed_v: int, cfg: Dictionary) -> Array:
	return _first_draft(seed_v, cfg)["offers"]


## The first descent draft of a run: {offers, slots}, so a row can check the
## roles a mutator's roll reported and not only how many cards it dealt.
func _first_draft(seed_v: int, cfg: Dictionary) -> Dictionary:
	var g = Game.new(seed_v, cfg)
	g.player["pos"] = g.map["stairs"]
	g.greened = g.green_need
	g.step({"type": "descend"})
	return {"offers": g.draft_offers.duplicate(), "slots": g.draft_slots.duplicate()}


func _oil_count(g) -> int:
	var n := 0
	for t in g.terrain:
		if g.terrain[t]["kind"] == "oil":
			n += 1
	return n


# --- 7) profile io a phone can break ------------------------------------------

## A saved profile is a file on a device the player controls, so it can be
## anything: truncated by a kill, replaced by a sync client, or simply a
## different app's JSON. None of that may cost more than the career.
##
## load_from guarded `data == null` (unparseable) but not "parsed into
## something that is not a profile": a JSON ARRAY reached data.get("runs", 0),
## which is a hard error on an Array - load_from returned null, the shell
## assigned that null to `profile`, and the app could not boot at all until
## the player cleared its data. Every one of these must hand back a USABLE
## fresh career instead.
func _check_bad_profile_files() -> void:
	var path := "user://test_profile_bad.json"
	# two of these fixtures are not JSON at all, so Godot's own parser prints an
	# error for each while this passes - that noise is the test working
	print("load_from: 8 fixtures, two of which the JSON parser rejects out loud")
	for body in ["[1, 2, 3]", "[]", "\"a string\"", "42", "true", "", "{not json", "null"]:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(body)
		f.close()
		var p = Profile.load_from(path)
		if p == null:
			_fail("load_from(%s) returned null - the shell cannot boot on that" % body)
			continue
		_expect(p.runs, 0, "load_from(%s) hands back a fresh career" % body)
		_expect(p.unlocked_tier, 0, "load_from(%s) unlocks nothing" % body)
		_expect(p.available_loadouts(), ["tender"], "load_from(%s) can still fill the menu" % body)
		_expect(p.game_config(0, [], "tender", "").get("loadout", ""), "tender",
			"load_from(%s) can still start a run" % body)
	DirAccess.remove_absolute(path)
	print("load_from survives a file that is not a profile: OK")


## A profile that IS a Dictionary but whose values have the wrong JSON type -
## a hand edit, a different build, a corrupt sync. `int(null)`, `int([1])`,
## `bool(null)` and `String(null)` are runtime errors, and a runtime error
## inside load_from returns null out of it; every numeric, bool and string
## slot (the career scalars, history entries, casts, daily_best, records) is
## therefore read through a type guard. For each bad value every slot carries
## it, and the career that comes back must load, save, reload and record.
func _check_wrong_type_profile() -> void:
	var path := "user://test_profile_types.json"
	var n := 0
	for bad in [null, [1, 2], "x", {"a": 1}, true]:
		var entry := {}
		for k in ["won", "floor", "tier", "turns", "seed", "kit", "grafts", "loadout",
				"death_cause", "bloom", "mutators", "packages", "score"]:
			entry[k] = bad
		var rec_e := {"v": bad, "run": bad, "loadout": bad, "tier": bad}
		var data := {
			"runs": bad, "wins": bad, "tier_wins": bad, "best_floor": bad, "unlocked_tier": bad,
			"unlocked_packages": [bad, "mycology"], "unlocked_mutators": bad,
			"unlocked_grafts": [bad], "unlocked_loadouts": [bad, "tidewarden"],
			"casts_by_base": {"grow_spike": bad, "seed_bomb": 3},
			"history": [entry, bad, {"kit": [bad, "solar_lance"], "won": true, "floor": 7}],
			"daily_best": {"42": {"won": bad, "floor": bad, "turns": bad}, "43": bad},
			"daily_first": {"42": {"won": bad, "floor": bad, "turns": bad, "score": bad}, "43": bad},
			"daily_tries": {"42": bad, "44": 2},
			"unseen": [bad, "mycology"],
			"feats": {"green_thumb": {"date": bad, "run": bad}, "two_for_one": bad},
			"totals": {"kills": bad, "cleanses": 4},
			"bosses_beaten": [bad, "overseer"],
			"cast_ever": [bad, "vine_whip"],
			"records": {
				"best": {"kills": rec_e, "score": {"v": 300, "run": bad, "loadout": bad, "tier": bad}, "bloom_earned": bad},
				"loadouts": {"tender": {"best_floor": bad, "best_score": bad, "best_tier_won": bad,
					"runs": bad, "wins": bad}, "spiker": bad},
				"score_v": bad,
			},
		}
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(data))
		f.close()
		var p = Profile.load_from(path)
		var label := "load_from with every slot = %s" % JSON.stringify(bad)
		if p == null:
			_fail("%s returned null - the shell cannot boot on that" % label)
			continue
		n += 1
		_expect([p.runs, p.wins, p.tier_wins, p.best_floor, p.unlocked_tier], [0, 0, 0, 0, 0],
			"%s: the scalars read their default" % label)
		_expect(p.unlocked_packages, ["mycology"], "%s: the package list keeps its good id" % label)
		_expect(p.unlocked_loadouts, ["tidewarden"], "%s: the loadout list keeps its good id" % label)
		_expect(int(p.casts_by_base.get("seed_bomb", -1)), 3, "%s: a good cast count survives" % label)
		var is_d: bool = bad is Dictionary  # a dict-shaped "bad" value is a (garbage) entry: it loads
		_expect(p.history.size(), 3 if is_d else 2, "%s: dictionary history entries load, the bad one is dropped" % label)
		_expect(p.history[0]["kit"], [], "%s: a bad kit loads as an empty one" % label)
		_expect(p.history[-1]["kit"], ["solar_lance"], "%s: a kit keeps its good id" % label)
		_expect(p.history[0]["death_cause"] is String and p.history[0]["floor"] is int, true,
			"%s: the entry's strings and numbers have their types" % label)
		_expect(p.daily_best.keys(), ["42", "43"] if is_d else ["42"], "%s: a dictionary daily loads, a bad one is dropped" % label)
		_expect(p.daily_first.keys(), ["42", "43"] if is_d else ["42"], "%s: daily_first loads the same way" % label)
		_expect(p.daily_first["42"].has("score"), false, "%s: a bad daily score is dropped" % label)
		_expect(str(p.daily_tries), str({"44": 2}), "%s: a bad try count is dropped" % label)
		_expect(p.unseen, ["mycology"], "%s: unseen keeps its good, owned id" % label)
		_expect(p.records["best"].keys(), [],
			"%s: a record without a real value is dropped, and a bad score_v drops the score" % label)
		_expect(p.records["loadouts"].keys(), ["spiker", "tender"] if is_d else ["tender"], "%s: a dictionary loadout record loads" % label)
		_expect(int(p.records["loadouts"]["tender"]["best_tier_won"]), -1,
			"%s: a loadout record's numbers read their defaults" % label)
		_expect(p.feats.keys(), ["green_thumb", "two_for_one"] if is_d else ["green_thumb"],
			"%s: a dictionary feat entry loads, a bad one is dropped" % label)
		_expect(p.feats["green_thumb"]["date"] is String and p.feats["green_thumb"]["run"] is int, true,
			"%s: a feat entry's date and run have their types" % label)
		_expect([str(p.totals), p.bosses_beaten, p.cast_ever], [str({"cleanses": 4}), ["overseer"], ["vine_whip"]],
			"%s: totals, bosses and casts keep their good entries" % label)
		_expect(p.available_loadouts().has("tender"), true, "%s: the menu still fills" % label)
		_expect(bool(p.history[0]["has_kit"]), false, "%s: a garbage kit is no kit (never an empty one)" % label)
		var muts_before: Array = p.unlocked_mutators.duplicate()
		p.record_run({"won": false, "floor": 2, "tier": 0, "turns": 30, "seed": 5})
		_expect(p.unlocked_mutators, muts_before, "%s: the garbage entries unlock no mutator" % label)
		p.save(path)
		var back = Profile.load_from(path)
		_expect(back != null and back.runs == p.runs and back.history.size() == p.history.size(), true,
			"%s: the career saves and reloads after a run" % label)
	DirAccess.remove_absolute(path)
	print("load_from survives wrong-typed values in every slot (%d / 5 shapes): OK" % n)


## unlocked_tier is an INDEX into Content.TIERS, and the one unlock load_from
## has no table to filter against. A profile written by a build with more
## tiers (or kept while TIERS shrank) used to come back verbatim; the shell
## then clamped its DIFFICULTY row to that number and read Content.TIERS[99],
## which throws and leaves the menu with no rows at all - no PLAY, no QUIT.
func _check_tier_clamp() -> void:
	var path := "user://test_profile_tier.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"runs": 4, "wins": 2, "unlocked_tier": 99}))
	f.close()
	var p = Profile.load_from(path)
	_expect(p.unlocked_tier, Content.TIERS.size(), "load_from clamps a tier past the end of the table")
	_expect(p.runs, 4, "...and keeps the rest of the career")
	_expect(int(p.game_config(99).get("tier", -1)), Content.TIERS.size(),
		"...so the run config it builds names a tier that exists")
	DirAccess.remove_absolute(path)
	print("unlocked_tier clamps to Content.TIERS: OK")


## The career is saved exactly when a run ends - the moment a phone is most
## likely to take the app away - and the write used to be open(WRITE) +
## store_string + close straight onto the live file: an interrupted save
## replaced a whole career with half a file, silently and with no notice.
## The write is atomic now (temp file, then rename), which this pins from the
## inside: `to_dict()` runs while the save is in flight, so a probe that reads
## the target back from there sees exactly what a kill at that instant would
## leave behind. Under the old write that is an EMPTY file.
func _check_atomic_save() -> void:
	var path := "user://test_profile_atomic.json"
	var good = Profile.new()
	good.runs = 7
	good.wins = 3
	good.best_floor = 5
	good.save(path)
	var whole := FileAccess.get_file_as_string(path)
	_expect(whole.length() > 0, true, "the good career is on disk")
	var probe = _SaveProbe.new()
	probe.probe_path = path
	probe.runs = 99
	probe.save(path)
	_expect(probe.seen_mid_save, whole, "a save in flight has not touched the career it replaces")
	_expect(FileAccess.file_exists(path + ".tmp"), false, "the temp file is renamed away, never left behind")
	_expect(Profile.load_from(path).runs, 99, "...and the finished save does replace it")
	# what an interrupted save actually leaves on the device: a partial temp
	# file beside a whole profile. The career loads from the whole one.
	var tf := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	tf.store_string(whole.substr(0, maxi(1, whole.length() / 3)))  # a half-written save
	tf.close()
	_expect(Profile.load_from(path).runs, 99, "a half-written temp file beside the profile costs nothing")
	good.save(path)
	_expect(Profile.load_from(path).runs, 7, "the next save goes through over the stray temp")
	_expect(FileAccess.file_exists(path + ".tmp"), false, "...and leaves nothing behind either")
	DirAccess.remove_absolute(path)
	print("profile save is atomic: OK")


## A profile that reads the file it is replacing back at the exact moment
## save() is serialising it. `to_dict()` is called from inside save(), so
## `seen_mid_save` is what a kill mid-save would leave on disk.
class _SaveProbe extends Profile:
	var probe_path := ""
	var seen_mid_save := "<never serialised>"

	func to_dict() -> Dictionary:
		seen_mid_save = FileAccess.get_file_as_string(probe_path)
		return super()


# --- 8) fun pass: the run-stats fold ------------------------------------------

## Fold determinism, the bloom cross-check and the independent recount over
## real bot runs, then the hand-fed units, the score, near_miss and highlights.
func _check_run_stats() -> void:
	var runs_checked := 0
	var steps_checked := 0
	for spec in [["optimizer", [1, 2, 3]], ["sprout", [1, 2, 3]], ["magpie", [1, 2]]]:
		for sd in spec[1]:
			steps_checked += _check_fold_run(String(spec[0]), int(sd))
			runs_checked += 1
	print("run-stats fold: %d bot runs, %d steps - replay, bloom cross-check and recount: OK" % [runs_checked, steps_checked])
	_check_fold_units()
	_check_score_formula()
	_check_near_miss()
	_check_highlights()


## Drive one bot game feeding stats A, then replay its actions into a fresh
## game feeding stats B: the summaries and every step's ctx must be equal
## (this is the resume guarantee). Per step, the event-derived bloom gain must
## equal ctx.bloom_gain - a new bloom source, or the cleanse event's "bloom"
## turning into a gain, fails here - and the counters must match a recount.
func _check_fold_run(bot_name: String, seed_v: int) -> int:
	var label := "%s s%d" % [bot_name, seed_v]
	var g = Game.new(seed_v, {})
	var bot = Roster.make(bot_name, seed_v)
	if bot.has_method("set_sim"):
		bot.set_sim(g)
	var st = RunStats.new()
	st.begin(g)
	var actions: Array = []
	var ctxs: Array = []
	var n := {"death": 0, "room_bloom": 0, "cleanse": 0, "bounty": 0, "combo": 0, "taken": 0}
	var bad_bloom := 0
	var bad_cleanse := 0
	while not g.over and actions.size() < Sweep.MAX_ACTIONS and g.total_turns < Sweep.MAX_TURNS:
		var act: Dictionary = bot.choose_action(g.snapshot(), g.legal_actions())
		actions.append(act)
		var before: int = g.bloom
		var evs: Array = g.step(act)
		var ctx: Dictionary = st.feed(g, evs)
		ctxs.append(str(ctx))
		if ctx != st.ctx:
			_fail("%s: feed() returned a ctx that is not stats.ctx" % label)
		var ev_gain := 0
		var cl := 0
		for ev in evs:
			var t := String(ev.get("t", ""))
			match t:
				"cleanse":
					cl = int(ev["bloom"]) - before
					ev_gain += cl
					n["cleanse"] += 1
				"room_bloom":
					ev_gain += int(ev["bonus"])
					n["room_bloom"] += 1
				"floor_restored":
					ev_gain += int(ev["bonus"])
				"bounty":
					ev_gain += Content.ELITE_BOUNTY
					n["bounty"] += 1
				"death":
					n["death"] += 1
				"rider", "hook", "surge":
					n["combo"] += 1
				"damage":
					if String(ev["who"]) == "player":
						n["taken"] += int(ev["amt"])
					elif String(ev.get("src", "")).begins_with("collision:"):
						n["combo"] += 1
		if ev_gain != int(ctx["bloom_gain"]):
			bad_bloom += 1
			if bad_bloom == 1:
				_fail("%s step %d: events pay %d bloom, ctx.bloom_gain %d (%s)" % [
					label, actions.size(), ev_gain, int(ctx["bloom_gain"]), str(evs).substr(0, 300)])
		if cl != int(ctx["cleanse_gain"]):
			bad_cleanse += 1
			if bad_cleanse == 1:
				_fail("%s step %d: cleanse paid %d, ctx.cleanse_gain %d" % [label, actions.size(), cl, int(ctx["cleanse_gain"])])
	var sa: Dictionary = st.summary()
	_expect(int(sa["kills"]), n["death"], "%s: kills == death events" % label)
	_expect(int(sa["rooms_bloomed"]), n["room_bloom"], "%s: rooms_bloomed == room_bloom events" % label)
	_expect(int(sa["cleanses"]), n["cleanse"], "%s: cleanses == cleanse events" % label)
	_expect(int(sa["elites_killed"]), n["bounty"], "%s: elites_killed == bounty events" % label)
	_expect(int(sa["combos"]), n["combo"], "%s: combos == riders + hooks + surges + collision hits" % label)
	_expect(int(sa["damage_taken"]), n["taken"], "%s: damage_taken == the player's damage events" % label)
	var kinds := 0
	for k in sa["kills_by_kind"]:
		kinds += int(sa["kills_by_kind"][k])
	_expect(kinds, int(sa["kills"]), "%s: kills_by_kind sums to kills" % label)
	_expect(int(sa["resonances_lit"]), sa["resonance_first"].size(), "%s: resonances_lit is resonance_first's size" % label)
	_expect(int(sa["biggest_hit_amt"]), int(sa["biggest_hit"]["amt"]), "%s: biggest_hit_amt is the nested amt" % label)
	_expect(int(sa["closest_hp"]), int(sa["closest_call"]["hp"]), "%s: closest_hp is the nested hp" % label)
	if g.over and not g.won:
		_expect(String(sa["killer"]["cause"]), String(g.death_cause), "%s: killer.cause is the death cause" % label)
	# the replay: a fresh game and a fresh fold over the same actions
	var g2 = Game.new(seed_v, {})
	var st2 = RunStats.new()
	st2.begin(g2)
	var ctx_diff := -1
	for i in actions.size():
		var c2: Dictionary = st2.feed(g2, g2.step(actions[i]))
		if ctx_diff < 0 and str(c2) != ctxs[i]:
			ctx_diff = i
	if ctx_diff >= 0:
		_fail("%s: replayed ctx differs at step %d" % [label, ctx_diff])
	_expect(str(st2.summary()), str(sa), "%s: a replayed fold's summary" % label)
	return actions.size()


## Hand-fed events on a real game, with total_turns / floor_num / hp nudged
## between feeds: the turn rule, streaks, the killer, ties, closest call, the
## room-clear rule, floors unhurt and the cleanse gain.
func _check_fold_units() -> void:
	var g = Game.new(1, {})
	var st = RunStats.new()
	st.begin(g)
	var c: Dictionary = st.feed(g, [{"t": "death", "who": "drill_bot", "id": 901}])
	_expect([int(c["turn_kills_prev"]), int(c["turn_kills"]), bool(c["turn_closed"])], [0, 1, false], "unit: first kill of a turn")
	_expect(int(c["kill_streak"]), 1, "unit: the open turn counts toward the streak once it has a kill")
	c = st.feed(g, [{"t": "death", "who": "drill_bot", "id": 902}])
	_expect([int(c["turn_kills_prev"]), int(c["turn_kills"])], [1, 2], "unit: second kill of the turn crosses 2")
	g.total_turns += 1
	c = st.feed(g, [])
	_expect([bool(c["turn_closed"]), int(c["turn_kills"]), st.best_multi_kill], [true, 2, 2], "unit: closing the turn banks the multi-kill")
	_expect([st.streak_closed, st.open_turn_kills], [1, 0], "unit: one closed turn with kills")
	st.feed(g, [{"t": "death", "who": "drill_bot", "id": 903}])
	g.total_turns += 1
	c = st.feed(g, [])
	_expect([st.streak_closed, int(c["kill_streak"]), st.best_kill_streak], [2, 2, 2], "unit: a second kill turn extends the streak")
	g.total_turns += 1
	c = st.feed(g, [])
	_expect([st.streak_closed, int(c["kill_streak"]), st.best_kill_streak], [0, 0, 2], "unit: a turn with no kill resets the streak, not the best")
	st.feed(g, [{"t": "death", "who": "drill_bot", "id": 904}])
	g.floor_num += 1
	c = st.feed(g, [])
	_expect([bool(c["turn_closed"]), int(c["turn_kills"]), st.streak_closed], [true, 1, 1], "unit: a floor change closes the turn")
	g.floor_num -= 1
	st.feed(g, [])
	# biggest hit: strict > keeps the first of a tie
	c = st.feed(g, [{"t": "damage", "who": "drill_bot", "id": 905, "amt": 4, "src": "strike"}])
	_expect(int(c["big_hit"]), 4, "unit: a new run-best hit is flagged")
	c = st.feed(g, [{"t": "damage", "who": "oil_sludge", "id": 906, "amt": 4, "src": "solar_lance"}])
	_expect(int(c["big_hit"]), 0, "unit: a tie is not a new best")
	_expect(str(st.biggest_hit), str({"amt": 4, "src": "strike", "target": "drill_bot", "floor": 1}), "unit: the tie keeps the first hit")
	# the cleanse gain is measured against the bloom before the step
	var b0: int = g.bloom
	g.bloom = b0 + 3
	c = st.feed(g, [{"t": "cleanse", "tile": Vector2i(1, 1), "kind": "oil", "bloom": g.bloom}])
	_expect([int(c["cleanse_gain"]), int(c["bloom_gain"])], [3, 3], "unit: a cleanse paying 3 reads +3, not the running total")
	g.bloom = b0
	c = st.feed(g, [])
	_expect(int(c["bloom_gain"]), 0, "unit: a spend is not a negative gain")
	# floors unhurt: a descend with no player damage on the floor counts
	st.feed(g, [{"t": "descend", "to_floor": 2}])
	st.feed(g, [{"t": "damage", "who": "player", "amt": 1, "src": "drill_bot"}])
	st.feed(g, [{"t": "descend", "to_floor": 3}])
	st.feed(g, [{"t": "shield_absorb", "amt": 2}])
	st.feed(g, [{"t": "descend", "to_floor": 4}])
	_expect(st.floors_unhurt, 2, "unit: floors unhurt (a hurt floor breaks it, a shielded hit does not)")
	# closest call: unchanged on the death step, counted on a winning one (C8)
	var hp0 := int(st.closest_call["hp"])
	g.player["hp"] = 0
	c = st.feed(g, [{"t": "damage", "who": "player", "amt": 9, "src": "drill_bot"}])
	_expect(int(st.closest_call["hp"]), hp0, "unit: the death step never sets the closest call")
	# the lowest hp INSIDE a step: a hit to 1 that growth heals back to 2 in
	# the same end turn is a fall to 1 (mutation: read only the hp after the
	# step and this stays at 2)
	g.player["hp"] = 3
	st.feed(g, [])
	g.player["hp"] = 2
	c = st.feed(g, [{"t": "damage", "who": "player", "amt": 2, "src": "drill_bot"}, {"t": "heal", "amt": 1}])
	_expect([int(st.closest_call["hp"]), bool(c["closest_call"])], [1, true],
		"unit: a hit to 1 healed back to 2 in the same step is a closest call of 1")
	# a walk that does not land on the hp after the step (an hp change no
	# event names the amount of) is not trusted: the hp after it stands
	var stw = RunStats.new()
	g.player["hp"] = 5
	stw.begin(g)
	g.player["hp"] = 4
	c = stw.feed(g, [{"t": "damage", "who": "player", "amt": 4, "src": "drill_bot"}, {"t": "descend", "to_floor": 2}])
	_expect(int(stw.closest_call["hp"]), 4, "unit: an unreconciled walk falls back to the hp after the step")
	g.player["hp"] = 1
	g.over = true
	g.won = true
	c = st.feed(g, [{"t": "win"}])
	_expect([int(st.closest_call["hp"]), bool(c["closest_call"]), bool(c["turn_closed"])], [1, false, true],
		"unit: a win taken at 1 HP keeps the closest call at 1")
	st.closest_call = {"hp": 9, "floor": 1}
	c = st.feed(g, [{"t": "win"}])
	_expect([int(st.closest_call["hp"]), bool(c["closest_call"]), bool(c["turn_closed"])], [1, true, true],
		"unit: a win taken at 1 HP is the closest call")
	# killer: an enemy cause names its kind; spikes resolve through the strike
	var gk = Game.new(1, {})
	gk.enemies[0]["kind"] = "rust_hound"
	var sk = RunStats.new()
	sk.begin(gk)
	var eid = gk.enemies[0]["id"]
	sk.feed(gk, [{"t": "strike", "id": eid}, {"t": "damage", "who": "rust_hound", "id": eid, "amt": 2, "src": "strike"},
		{"t": "damage", "who": "player", "amt": 1, "src": "spikes"}, {"t": "player_death", "cause": "spikes"}])
	_expect(str(sk.killer), str({"cause": "spikes", "kind": "rust_hound"}), "unit: spikes resolve their killer from the step's strike")
	sk.feed(gk, [{"t": "player_death", "cause": "drill_bot"}])
	_expect(str(sk.killer), str({"cause": "drill_bot", "kind": "drill_bot"}), "unit: an enemy cause is its own kind")
	sk.feed(gk, [{"t": "player_death", "cause": "smog"}])
	_expect(str(sk.killer), str({"cause": "smog", "kind": ""}), "unit: smog has no kind")
	# room clear: the room the tender stood in, emptied by this step's kill
	_check_room_clear_units()
	print("run-stats units: turn close, streaks, killer, ties, cleanse gain, floors unhurt, closest call, room clear: OK")


func _check_room_clear_units() -> void:
	var g = Game.new(3, {})
	var rooms: Array = g.map["rooms"]
	if rooms.size() < 2:
		_fail("unit room clear: seed 3 floor 1 has %d rooms" % rooms.size())
		return
	var r0: Rect2i = rooms[0]
	var inside: Vector2i = r0.position
	var other: Vector2i = Rect2i(rooms[1]).position
	g.player["pos"] = r0.get_center()
	for e in g.enemies:
		e["pos"] = Vector2i(-9, -9)
	var victim: Dictionary = g.enemies[0]
	var bystander: Dictionary = g.enemies[1]
	victim["pos"] = inside
	var st = RunStats.new()
	st.begin(g)
	g.enemies.erase(victim)
	var c: Dictionary = st.feed(g, [{"t": "death", "who": victim["kind"], "id": victim["id"]}])
	_expect(bool(c["room_cleared"]), true, "unit room clear: the last machine in the tender's room falls")
	_expect(st.room_clears, 1, "unit room clear: counted")
	_expect(str(c["killed"]), str([{"id": victim["id"], "kind": victim["kind"], "pos": inside}]), "unit room clear: killed carries the last-known tile")
	# a live machine still in the room: no clear
	g.enemies.append(victim)
	bystander["pos"] = r0.position + Vector2i(1, 0)
	st.feed(g, [])
	g.enemies.erase(victim)
	c = st.feed(g, [{"t": "death", "who": victim["kind"], "id": victim["id"]}])
	_expect(bool(c["room_cleared"]), false, "unit room clear: not while another machine stands in the room")
	# the kill was in another room: no clear of this one
	bystander["pos"] = Vector2i(-9, -9)
	victim["pos"] = other
	g.enemies.append(victim)
	st.feed(g, [])
	g.enemies.erase(victim)
	c = st.feed(g, [{"t": "death", "who": victim["kind"], "id": victim["id"]}])
	_expect(bool(c["room_cleared"]), false, "unit room clear: a kill elsewhere does not clear the tender's room")
	# room R comes from the tender's PRE-step tile first, then the post-step
	# tile: a corridor tile outside every room (grown by 1, as the fold grows it)
	var corridor := Vector2i(-20, -20)
	for y in range(g.map["h"]):
		for x in range(g.map["w"]):
			var t := Vector2i(x, y)
			var in_room := false
			for r in rooms:
				if Rect2i(r).grow(1).has_point(t):
					in_room = true
					break
			if not in_room:
				corridor = t
				break
		if corridor != Vector2i(-20, -20):
			break
	# (a) the tender walks OUT into the corridor on the killing step
	victim["pos"] = inside
	g.enemies.append(victim)
	g.player["pos"] = r0.get_center()
	st.feed(g, [])
	g.enemies.erase(victim)
	g.player["pos"] = corridor
	c = st.feed(g, [{"t": "death", "who": victim["kind"], "id": victim["id"]}])
	_expect(bool(c["room_cleared"]), true, "unit room clear: the tender leaves the room on the killing step (pre-step tile)")
	# (b) the tender steps IN from the corridor on the killing step
	g.enemies.append(victim)
	g.player["pos"] = corridor
	st.feed(g, [])
	g.enemies.erase(victim)
	g.player["pos"] = r0.get_center()
	c = st.feed(g, [{"t": "death", "who": victim["kind"], "id": victim["id"]}])
	_expect(bool(c["room_cleared"]), true, "unit room clear: the tender enters the room on the killing step (post-step fallback)")


func _check_score_formula() -> void:
	var s := {"floor": 3, "won": false, "kills": 10, "bloom_earned": 20, "combos": 4,
		"rooms_bloomed": 2, "floors_restored": 1, "tier": 0}
	var hand := 3 * 100 + 0 + 10 * 5 + 20 * 2 + 4 * 3 + 2 * 10 + 1 * 50
	var sc: Dictionary = RunStats.score(s)
	_expect(int(sc["total"]), hand, "score: a fixture equals the hand sum")
	_expect(int(sc["base"]), hand, "score: base is the sum at tier 0")
	_expect(sc["parts"].size(), Content.RUN_SCORE.size(), "score: one part per RUN_SCORE row")
	_expect(String(sc["parts"][0][0]), "floor", "score: parts in table order")
	s["tier"] = 2
	sc = RunStats.score(s)
	_expect([int(sc["quarters"]), int(sc["total"])], [6, hand * 6 / 4], "score: tier 2 is base*6/4")
	s["won"] = true
	s["tier"] = 0
	_expect(int(RunStats.score(s)["total"]), hand + 500, "score: a win counts its row once")
	_expect(int(RunStats.score({})["total"]), 0, "score: an empty summary scores 0")
	print("run score: fixture %d, tier-2 %d: OK" % [hand, hand * 6 / 4])


## near_miss from a real snapshot edited per rule.
func _check_near_miss() -> void:
	var g = Game.new(2, {})
	var base: Dictionary = g.snapshot()
	var s := {"closest_call": {"hp": 9, "floor": 1}}
	# the win arm
	var w := base.duplicate(true)
	w["won"] = true
	_expect(String(RunStats.near_miss(w, s, 0)["kind"]), "", "near_miss: a comfortable win says nothing")
	_expect(str(RunStats.near_miss(w, {"closest_call": {"hp": 2, "floor": 6}}, 0)),
		str({"kind": "closest_call", "hp": 2, "floor": 6}), "near_miss: a win at 2 HP is a closest call")
	# 1) a boss still standing on its floor
	var b := base.duplicate(true)
	b["floor"] = Content.FLOORS.size()
	b["enemies"] = [{"id": 1, "kind": "furnace_core", "hp": 3, "pos": Vector2i(2, 2)}]
	_expect(str(RunStats.near_miss(b, s, 0)), str({"kind": "boss_hp", "boss": "furnace_core", "hp": 3}),
		"near_miss: the boss had 3 HP left")
	# 2) the stairs awake and close (BFS route, not straight-line)
	var dist := _bfs_from(base, base["map"]["stairs"])
	var near := Vector2i(-1, -1)
	var far := Vector2i(-1, -1)
	for p in dist:
		if int(dist[p]) == 5 and near.x < 0:
			near = p
		if int(dist[p]) > RunStats.NEAR_STAIRS_MAX and far.x < 0:
			far = p
	var st := base.duplicate(true)
	st["green_need"] = 3
	st["greened"] = 3
	st["player"]["hp"] = 2
	st["player"]["pos"] = near
	_expect(str(RunStats.near_miss(st, s, 0)), str({"kind": "stairs", "steps": 5}), "near_miss: the stairs were 5 steps away")
	st["player"]["pos"] = base["map"]["stairs"]
	_expect(int(RunStats.near_miss(st, s, 0).get("steps", -1)), 0, "near_miss: dying on the stairs is 0 steps")
	if far.x >= 0:
		st["player"]["pos"] = far
		_expect(String(RunStats.near_miss(st, s, 0)["kind"]), "", "near_miss: stairs past NEAR_STAIRS_MAX are no near-miss")
	else:
		_fail("near_miss: seed 2 floor 1 has no tile past %d steps from the stairs" % RunStats.NEAR_STAIRS_MAX)
	# 3) the quota short by 1 or 2, not 3
	var q := base.duplicate(true)
	q["player"]["hp"] = 2
	q["green_need"] = 4
	for short in [1, 2]:
		q["greened"] = 4 - short
		_expect(str(RunStats.near_miss(q, s, 0)), str({"kind": "quota", "short": short}), "near_miss: %d cleanses short" % short)
	q["greened"] = 1
	_expect(String(RunStats.near_miss(q, s, 0)["kind"]), "", "near_miss: 3 short is no near-miss")
	# 4/5) the career's deepest floor
	q["floor"] = 3
	_expect(str(RunStats.near_miss(q, s, 4)), str({"kind": "best_short", "best": 4}), "near_miss: one floor short of the best")
	q["floor"] = 4
	_expect(str(RunStats.near_miss(q, s, 4)), str({"kind": "best_level", "best": 4}), "near_miss: died on the best floor")
	_expect(String(RunStats.near_miss(q, s, 1)["kind"]), "", "near_miss: a best of 1 is no yardstick")
	# 6) exactly 0 HP, but never for smog, and only when the caller proved that
	# one more HP survives the killing step (shell/main.gd _one_hp_saves)
	q["player"]["hp"] = 0
	q["death_cause"] = "drill_bot"
	_expect(String(RunStats.near_miss(q, s, 0, true)["kind"]), "exact", "near_miss: a Drill Bot took the last HP exactly")
	_expect(String(RunStats.near_miss(q, s, 0)["kind"]), "",
		"near_miss: exactly 0 HP with no proof that 1 more HP survives says nothing (the default)")
	_expect(String(RunStats.near_miss(q, s, 0, false)["kind"]), "",
		"near_miss: exactly 0 HP when 1 more HP still dies on that step says nothing")
	q["death_cause"] = "smog"
	_expect(String(RunStats.near_miss(q, s, 0, true)["kind"]), "", "near_miss: smog is never said")
	q["player"]["hp"] = -2
	q["death_cause"] = "drill_bot"
	_expect(String(RunStats.near_miss(q, s, 0, true)["kind"]), "", "near_miss: overkill is not exact")
	print("near_miss: win/boss/stairs/quota/best/exact rules: OK")


## Route lengths from `goal` over floor tiles (the test's own BFS).
func _bfs_from(snap: Dictionary, goal: Vector2i) -> Dictionary:
	var m: Dictionary = snap["map"]
	var w := int(m["w"])
	var h := int(m["h"])
	var dist := {goal: 0}
	var q: Array = [goal]
	var i := 0
	while i < q.size():
		var p: Vector2i = q[i]
		i += 1
		for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var nb: Vector2i = p + d
			if nb.x < 0 or nb.y < 0 or nb.x >= w or nb.y >= h or dist.has(nb):
				continue
			if int(m["tiles"][nb.y * w + nb.x]) != 1:
				continue
			var tr: Dictionary = snap["terrain"]
			if tr.has(nb) and bool(Content.terrain(String(tr[nb]["kind"]), "blocks", false)):
				continue
			dist[nb] = int(dist[p]) + 1
			q.append(nb)
	return dist


func _check_highlights() -> void:
	var rid: String = String(Content.RESONANCES.keys()[0])
	var s := {"floors_restored": 1, "resonance_first": {rid: {"floor": 3, "turn": 40}},
		"best_multi_kill": 3, "biggest_hit": {"amt": 6, "src": "solar_lance", "target": "drill_bot", "floor": 2},
		"best_kill_streak": 4, "rooms_bloomed": 6, "combos": 12, "elites_killed": 2, "kills": 30, "cleanses": 9}
	var ids := func(hs: Array) -> Array:
		var out: Array = []
		for h in hs:
			out.append(String(h["id"]))
		return out
	_expect(ids.call(RunStats.highlights(s)), ["restored", "resonance", "multi"], "highlights: top three in priority order")
	var rec := [{"key": "score", "v": 900, "was": 700}]
	var hr: Array = RunStats.highlights(s, 3, rec)
	_expect(ids.call(hr), ["restored", "resonance", "record"], "highlights: a beaten record sits right after the resonance")
	_expect(str(hr[2]), str({"id": "record", "key": "score", "v": 900, "was": 700}), "highlights: the record chip carries key, v and was")
	var all_ids: Array = ids.call(RunStats.highlights(s, 20, rec))
	_expect(all_ids, ["restored", "resonance", "record", "multi", "big_hit", "streak", "rooms", "combos", "elites", "kills", "cleanses"],
		"highlights: every candidate once, in order")
	_expect(RunStats.highlights(s, 1).size(), 1, "highlights: max_n caps the list")
	var low := {"best_multi_kill": 2, "biggest_hit": {"amt": 3, "src": "strike", "target": "drill_bot", "floor": 1},
		"rooms_bloomed": 1, "combos": 1, "kills": 4}
	_expect(ids.call(RunStats.highlights(low)), ["multi", "big_hit", "rooms"], "highlights: the lower bars fill in when nothing big happened")
	_expect(ids.call(RunStats.highlights({"cleanses": 2})), ["cleanses"], "highlights: a run with only cleanses still gets a chip")
	_expect(RunStats.highlights({}).size(), 0, "highlights: an empty run gets none")
	print("highlights: order, record slot, max_n, distinct ids: OK")


# --- 8b) records and score bests in meta/profile.gd ---------------------------

## A summary with just what the record fold reads.
func _rec_summary(score: int, extra: Dictionary = {}) -> Dictionary:
	var s := {"won": false, "floor": 3, "tier": 0, "turns": 80, "seed": 1, "loadout": "spiker",
		"score": score, "score_v": Content.RUN_SCORE_VERSION, "kills": 10}
	s.merge(extra, true)
	return s


func _check_score_bests() -> void:
	var p = Profile.new()
	p.record_run(_rec_summary(500, {"floor": 3}))
	var before: Dictionary = p.bests_snapshot("spiker")
	p.record_run(_rec_summary(900, {"floor": 5}))
	_expect(str(before), str({"runs": 1, "wins": 0, "best_floor": 3, "best_score": 500, "best_score_loadout": 500, "loadout": "spiker"}),
		"bests_snapshot taken before a record keeps the old values")
	var after: Dictionary = p.bests_snapshot("spiker")
	_expect([int(after["best_score"]), int(after["best_floor"]), int(after["runs"])], [900, 5, 2], "bests_snapshot after the record")
	_expect(int(p.bests_snapshot("tender")["best_score_loadout"]), 0, "bests_snapshot: a loadout never played has no best")
	_expect(int(p.history.back()["score"]), 900, "_compact keeps the score")
	_expect(String(p.history.back()["loadout"]), "spiker", "_compact keeps the loadout")
	# dailies never touch the career's records or runs
	var rec_before := str(p.records)
	p.record_daily(_rec_summary(5000, {"seed": 77}))
	_expect(str(p.records), rec_before, "record_daily never touches records")
	_expect(p.runs, 2, "record_daily never counts a run")
	# the codec
	var path := "user://test_profile_records.json"
	p.save(path)
	var back = Profile.load_from(path)
	_expect(str(back.records), str(p.records), "records round-trip")
	DirAccess.remove_absolute(path)
	print("score bests: snapshot before record, compact, daily isolation, codec: OK")


func _check_records() -> void:
	var p = Profile.new()
	p.record_run(_rec_summary(100))
	_expect(p.last_report["records"], [], "records: run 1 reports nothing (no NEW RECORD spam)")
	p.record_run(_rec_summary(90))
	_expect(p.last_report["records"], [], "records: a lower score reports nothing")
	p.record_run(_rec_summary(120))
	_expect(str(p.last_report["records"]), str([{"key": "score", "v": 120, "was": 100}]), "records: 120 beats 100")
	_expect(int(p.records["best"]["score"]["v"]), 120, "records: the best score is stored")
	_expect(str(p.records["best"]["score"]), str({"loadout": "spiker", "run": 3, "tier": 0, "v": 120}), "records: the entry names its run")
	_expect(int(p.last_report["run"]), 3, "last_report.run is the run count")
	_expect(p.last_report.keys(), ["run", "unlocks", "feats", "records", "next"], "last_report shape")
	# a stat record beaten together with the score: RECORD_SHOW order
	p.record_run(_rec_summary(130, {"kills": 25, "combos": 4}))
	_expect(str(p.last_report["records"]), str([{"key": "score", "v": 130, "was": 120}, {"key": "kills", "v": 25, "was": 10}]),
		"records: several beaten in RECORD_SHOW order; a first-ever combos record is not reported")
	_expect(p.records["best"].has("combos"), true, "records: ...but it is stored")
	# fastest win: wins only, a minimum
	p.record_run(_rec_summary(10, {"turns": 30}))
	_expect(p.records["best"].has("fastest_win"), false, "records: a loss never sets the fastest win")
	p.record_run(_rec_summary(10, {"won": true, "turns": 200, "tier": 1}))
	_expect(int(p.records["best"]["fastest_win"]["v"]), 200, "records: the first win sets it")
	p.record_run(_rec_summary(10, {"won": true, "turns": 150}))
	_expect(int(p.records["best"]["fastest_win"]["v"]), 150, "records: a faster win lowers it")
	_expect(str(p.last_report["records"]), str([{"key": "fastest_win", "v": 150, "was": 200}]), "records: a faster win is reported")
	p.record_run(_rec_summary(10, {"won": true, "turns": 180}))
	_expect(int(p.records["best"]["fastest_win"]["v"]), 150, "records: a slower win leaves it")
	# per-loadout rows
	var lr: Dictionary = p.records["loadouts"]["spiker"]
	_expect(str(lr), str({"best_floor": 3, "best_score": 130, "best_tier_won": 1, "runs": 8, "wins": 3}), "records: the spiker row")
	p.record_run(_rec_summary(40, {"loadout": "tidewarden", "floor": 6}))
	_expect(str(p.records["loadouts"]["tidewarden"]), str({"best_floor": 6, "best_score": 40, "best_tier_won": -1, "runs": 1, "wins": 0}),
		"records: a second loadout gets its own row (never won = -1)")
	p.record_run(_rec_summary(40, {"loadout": "ghost_loadout"}))
	_expect(p.records["loadouts"].has("ghost_loadout"), false, "records: an unknown loadout gets no row")
	_expect(String(p.history.back()["loadout"]), "", "_compact: an unknown loadout is stored as \"\"")
	# a score_v change drops the score bests and nothing else
	var kills_best := int(p.records["best"]["kills"]["v"])
	p.record_run(_rec_summary(60, {"score_v": Content.RUN_SCORE_VERSION + 1, "kills": 1}))
	_expect(int(p.records["best"]["score"]["v"]), 60, "records: a new score version starts the score best over")
	_expect(p.last_report["records"], [], "records: ...and never reports a fake NEW BEST across versions")
	_expect(int(p.records["best"]["kills"]["v"]), kills_best, "records: other records survive a score version change")
	_expect(int(p.records["loadouts"]["tidewarden"]["best_score"]), 0, "records: the loadout score bests reset too")
	_expect(int(p.records["loadouts"]["spiker"]["best_score"]), 60, "records: ...and refill from the new version")
	_expect(int(p.records["score_v"]), Content.RUN_SCORE_VERSION + 1, "records: the new version is stored")
	# a legacy summary moves no record
	var r0 := str(p.records["best"])
	p.record_run({"won": false, "floor": 2, "tier": 0})
	_expect(str(p.records["best"]), r0, "records: a legacy {won, floor, tier} summary moves no record")
	# unlocks: "tier:N" first when the run opened a tier, then milestone ids
	var u = Profile.new()
	var news: Array = u.record_run({"won": true, "floor": 7, "tier": 0, "kit": ["seed_bomb"], "grafts": []})
	_expect(u.last_report["unlocks"][0], "tier:1", "last_report.unlocks: the tier comes first")
	_expect(u.last_report["unlocks"].slice(1), news, "last_report.unlocks: then the milestone ids record_run returns")
	u.record_run({"won": false, "floor": 2, "tier": 0})
	_expect(u.last_report["unlocks"], [], "last_report.unlocks: a run that opens nothing")
	# load_from: an old profile has no records; unknown keys and loadouts go
	var oldp := "user://test_profile_old.json"
	var f := FileAccess.open(oldp, FileAccess.WRITE)
	f.store_string(JSON.stringify({"runs": 4, "wins": 1, "best_floor": 7}))
	f.close()
	var old = Profile.load_from(oldp)
	_expect(str(old.records), str({"best": {}, "loadouts": {}, "score_v": 0}), "an old profile loads with empty records")
	_expect(old.runs, 4, "...and keeps everything else")
	var dirty := {"runs": 2, "records": {"score_v": Content.RUN_SCORE_VERSION,
		"best": {"score": {"v": 300.0, "run": 2.0, "tier": 0.0, "loadout": "spiker"},
			"kills": {"v": 12, "run": 1, "tier": 0, "loadout": "ghost_loadout"},
			"closest_hp": {"v": 1, "run": 1, "tier": 0, "loadout": "tender"},
			"ghost_key": {"v": 5, "run": 1, "tier": 0, "loadout": "tender"},
			"combos": "not a record"},
		"loadouts": {"spiker": {"best_floor": 4.0, "best_score": 300, "best_tier_won": -1, "runs": 2, "wins": 0},
			"ghost_loadout": {"best_floor": 9, "best_score": 1, "best_tier_won": 0, "runs": 1, "wins": 1}}}}
	f = FileAccess.open(oldp, FileAccess.WRITE)
	f.store_string(JSON.stringify(dirty))
	f.close()
	var dp = Profile.load_from(oldp)
	_expect(dp.records["best"].keys(), ["kills", "score"], "load_from keeps only record keys (closest_hp, unknown and malformed go)")
	_expect(str(dp.records["best"]["score"]), str({"loadout": "spiker", "run": 2, "tier": 0, "v": 300}), "load_from int()s a record")
	_expect(String(dp.records["best"]["kills"]["loadout"]), "", "load_from blanks an unknown loadout inside a record")
	_expect(dp.records["loadouts"].keys(), ["spiker"], "load_from drops an unknown loadout row")
	_expect(dp.records["loadouts"]["spiker"]["best_floor"] is int, true, "load_from int()s a loadout row")
	dirty["records"]["score_v"] = 0
	f = FileAccess.open(oldp, FileAccess.WRITE)
	f.store_string(JSON.stringify(dirty))
	f.close()
	var vp = Profile.load_from(oldp)
	_expect(vp.records["best"].has("score"), false, "load_from: score bests from another score version are dropped")
	_expect(vp.records["best"].has("kills"), true, "load_from: ...and nothing else is")
	_expect(int(vp.records["loadouts"]["spiker"]["best_score"]), 0, "load_from: the loadout score best is dropped too")
	_expect(int(vp.records["loadouts"]["spiker"]["best_floor"]), 4, "load_from: ...but not the loadout's floor")
	DirAccess.remove_absolute(oldp)
	print("records: report rule, fastest win, loadout rows, score version, unlock order, load filters: OK")


# --- 9) fun pass, career layer ------------------------------------------------

## progress(row): one fixture per predicate key, the owned case, and a
## two-key row whose headline is its harder half.
func _check_progress() -> void:
	var p = Profile.new()
	p.best_floor = 2
	var pr: Dictionary = p.progress({"id": "x", "requires": {"best_floor": 5}})
	_expect([pr["have"], pr["need"], pr["text"], pr["done"]], [2, 5, "best floor 2/5", false], "progress: best_floor")
	_expect(pr["frac"], 0.4, "progress: frac")
	p.wins = 3
	_expect(p.progress({"id": "x", "requires": {"wins": 2}})["have"], 2, "progress: have is capped at need")
	p.tier_wins = 1
	_expect(p.progress({"id": "x", "requires": {"tier_wins": 2}})["text"], "wins at difficulty 1+ 1/2", "progress: tier_wins")
	p.casts_by_base = {"grow_spike": 12, "vine_whip": 40}
	var pc: Dictionary = p.progress({"id": "x", "requires": {"casts": {"grow_spike": 30, "vine_whip": 10}}})
	_expect([pc["have"], pc["need"]], [22, 40], "progress: a multi-ability casts row sums the capped parts")
	_expect(pc["text"], "Grow Spike 12/30  ·  Vine Whip 10/10", "progress: casts names each ability")
	# won_with: 0 until a win holds the id; the hint counts the runs that held it
	var pw: Dictionary = p.progress({"id": "x", "requires": {"won_with": ["vine_whip"]}})
	_expect([pw["have"], pw["need"], pw["text"], pw["hint"]], [0, 1, "not yet", ""], "progress: won_with with no history")
	p.record_run({"won": false, "floor": 4, "tier": 0, "kit": ["vine_whip", "seed_bomb"], "grafts": []})
	pw = p.progress({"id": "x", "requires": {"won_with": ["vine_whip"]}})
	_expect([pw["have"], pw["hint"]], [0, "held it in 1 run (best floor 4)"], "progress: won_with hint off a loss")
	p.record_run({"won": true, "floor": 7, "tier": 0, "kit": ["vine_whip+lash", "seed_bomb"], "grafts": ["deep_cells"]})
	pw = p.progress({"id": "x", "requires": {"won_with": ["vine_whip"]}})
	_expect([pw["have"], pw["hint"]], [1, "held it in 2 runs (best floor 7)"], "progress: won_with after a win holding a variant")
	var pn: Dictionary = p.progress({"id": "x", "requires": {"wins_without": ["solar_lance"]}})
	_expect([pn["have"], pn["text"]], [1, "without Solar Lance: best floor 7 in 2 runs"], "progress: wins_without")
	var pg: Dictionary = p.progress({"id": "x", "requires": {"grafts_owned_at_win": 2}})
	_expect([pg["have"], pg["need"], pg["text"]], [1, 2, "most grafts at a win 1/2"], "progress: grafts_owned_at_win (no shipped row)")
	# the headline of a two-key row is its smallest fraction, parts in key order
	var p2: Dictionary = p.progress({"id": "x", "requires": {"casts": {"grow_spike": 30}, "best_floor": 8}})
	_expect([p2["key"], p2["have"], p2["need"]], ["casts", 12, 30], "progress: a two-key row heads with its harder half")
	_expect([p2["parts"][0]["key"], p2["parts"][1]["key"]], ["best_floor", "casts"], "progress: parts in GOAL_KEY_ORDER")
	# an owned row reads done
	p.unlocked_loadouts = ["tidewarden"]
	var po: Dictionary = p.progress({"id": "tidewarden", "requires": {"best_floor": 30}})
	_expect([po["done"], po["have"] == po["need"], po["text"]], [true, true, "done"], "progress: an owned row is done")
	print("goal progress: every predicate, the owned case and the two-key headline: OK")


func _check_next_goals() -> void:
	var fresh = Profile.new()
	var g0: Array = fresh.next_goals(1)
	_expect(g0[0]["ids"], ["tidewarden"], "next_goals: a fresh career's first goal is the floor-3 row")
	_expect([g0[0]["desc"], g0[0]["names"]], ["Reach the Refinery Gate", ["Tidewarden"]], "next_goals: desc and names")
	_expect(str(fresh.next_goals(3)), str(fresh.next_goals(3)), "next_goals: pure (same profile, same list)")
	# after a floor-5 legacy run the floor rows are owned: the one-win wall leads
	var p = Profile.new()
	p.record_run({"won": false, "floor": 5, "tier": 0})
	var g1: Dictionary = p.next_goals(1)[0]
	_expect(g1["desc"], "Shut down the Furnace", "next_goals: after floor 5 the first win leads")
	for id in ["hydraulics", "kit_of_3", "double_oil", "open_pool", "spinning_shrine", "skyrunner", "tier:1"]:
		if not g1["ids"].has(id):
			_fail("next_goals: the one-win goal is missing %s (%s)" % [id, str(g1["ids"])])
	_expect(g1["ids"].size(), 7, "next_goals: six milestones and difficulty 1 in ONE goal")
	_expect(g1["names"].has("Slick Combine") and g1["names"].has("difficulty 1"), true,
		"next_goals: names come from Content (double_oil reads Slick Combine)")
	for n in g1["names"]:
		if String(n).contains("_"):
			_fail("next_goals: a raw id leaked into a name: %s" % n)
	# tier 1: difficulty 2 rides the one-tier-win group, never on its own too
	var t1 = Profile.new()
	t1.unlocked_tier = 1
	t1.wins = 1
	t1._claim()
	var groups: Array = t1.next_goals(99)
	var carriers := 0
	for g in groups:
		if g["ids"].has("tier:2"):
			carriers += 1
			_expect(g["key"], "tier_wins", "next_goals: tier 2 rides the tier_wins group")
			_expect(g["ids"].size() > 1, true, "next_goals: ...not a standalone duplicate")
	_expect(carriers, 1, "next_goals: difficulty 2 appears exactly once")
	# past tier 1 it is its own goal
	var t3 = Profile.new()
	t3.unlocked_tier = 3
	t3.wins = 3
	t3.tier_wins = 2
	t3._claim()
	var standalone := false
	for g in t3.next_goals(99):
		if g["ids"] == ["tier:4"]:
			standalone = g["desc"] == "Win at difficulty 3"
	_expect(standalone, true, "next_goals: past tier 1 the next difficulty is its own goal")
	# everything owned at the top tier: nothing left
	var maxed = Profile.new()
	maxed.unlocked_tier = Content.TIERS.size()
	for m in Content.MILESTONES:
		maxed._bucket(String(m["kind"])).append(String(m["id"]))
	_expect(maxed.next_goals(3), [], "next_goals: a maxed career has none")
	# the report's delta: what this run gained on the goal it shows next
	var dp = Profile.new()
	dp.best_floor = 5
	dp.unlocked_loadouts = ["tidewarden", "flarekeeper"]
	dp.unlocked_packages = ["mycology"]
	dp.casts_by_base = {"grow_spike": 8}
	dp.record_run({"won": false, "floor": 4, "tier": 0, "kit": ["grow_spike", "seed_bomb"], "grafts": [],
		"effective_uses_by_base": {"grow_spike": 9}})
	var nx: Dictionary = dp.last_report["next"][0]
	_expect([nx["ids"], nx["have"], nx["need"], nx["delta"]], [["spiker"], 17, 30, 9],
		"last_report.next[0]: Land 30 Grow Spikes 17/30 with +9 this run")
	print("next goals: fresh, the one-win group + tier fold, tier 1 / tier 3, maxed, purity, delta: OK")


func _check_unseen() -> void:
	var p = Profile.new()
	p.record_run({"won": true, "floor": 7, "tier": 0, "kit": ["seed_bomb", "vine_whip"], "grafts": []})
	for id in ["tier:1", "hydraulics", "kit_of_3", "skyrunner", "lasher"]:
		if not p.unseen.has(id):
			_fail("unseen: a first win should leave %s unseen (%s)" % [id, str(p.unseen)])
	_expect(p.unseen[0], "tier:1", "unseen: the tier comes first, as in last_report.unlocks")
	var before: int = p.unseen.size()
	p.record_run({"won": false, "floor": 2, "tier": 0})
	_expect(p.unseen.size(), before, "unseen: a run that opens nothing adds nothing")
	_expect(p.mark_seen("kit_of_3"), true, "mark_seen: true when it was unseen")
	_expect(p.mark_seen("kit_of_3"), false, "mark_seen: false the second time")
	_expect(p.unseen_of("tier"), ["tier:1"], "unseen_of: tier")
	_expect(p.unseen_of("package"), ["mycology", "hydraulics"], "unseen_of: package (floor 7 and the win)")
	# a gated loadout earns no badge until its package opens it
	_expect(p.unseen_of("loadout").has("skyrunner"), false, "unseen_of: a Skyrunner waiting on Aeolian is hidden")
	_expect(p.unseen_of("loadout").has("lasher"), true, "unseen_of: a playable loadout shows")
	p.unlocked_packages.append("aeolian")
	_expect(p.unseen_of("loadout").has("skyrunner"), true, "unseen_of: ...until Aeolian is unlocked")
	# dailies never badge anything
	var u0: Array = p.unseen.duplicate()
	p.record_daily({"won": true, "floor": 7, "turns": 99, "seed": 5})
	_expect(p.unseen, u0, "record_daily adds nothing to unseen")
	# the codec keeps it (filtered against what is owned)
	var path := "user://test_profile_unseen.json"
	p.save(path)
	var back = Profile.load_from(path)
	_expect(back.unseen, p.unseen, "unseen round-trips")
	DirAccess.remove_absolute(path)
	# display helpers
	_expect([Profile.unlock_kind("tier:3"), Profile.unlock_kind("feat:x"), Profile.unlock_kind("double_oil"),
		Profile.unlock_kind("aeolian"), Profile.unlock_kind("skyrunner"), Profile.unlock_kind("deep_cells"),
		Profile.unlock_kind("ghost")], ["tier", "feat", "mutator", "package", "loadout", "graft", ""], "unlock_kind")
	_expect([Profile.unlock_name("tier:3"), Profile.unlock_name("double_oil"), Profile.unlock_name("aeolian"),
		Profile.unlock_name("skyrunner")], ["difficulty 3", "Slick Combine", "Aeolian", "Skyrunner"], "unlock_name")
	_expect([Profile.join_names(["A"]), Profile.join_names(["A", "B"]), Profile.join_names(["A", "B", "C", "D", "E"])],
		["A", "A and B", "A, B and 3 more"], "join_names")
	_expect([Profile.gate_of("skyrunner", []), Profile.gate_of("skyrunner", ["aeolian"]), Profile.gate_of("tender", [])],
		["Aeolian", "", ""], "gate_of")
	print("unseen: record, mark_seen, unseen_of (gated loadout), daily isolation, codec, helpers: OK")


func _check_daily_streak() -> void:
	var today := 1795000000  # a fixed instant: the streak reads no clock
	var p = Profile.new()
	for k in [0, 1, 2, 4]:
		var sd := Profile.daily_seed_for(Time.get_date_string_from_unix_time(today - 86400 * k))
		p.record_daily({"won": false, "floor": 3, "turns": 50, "seed": sd})
	var st: Dictionary = p.daily_streak(today)
	_expect([st["current"], st["longest"], st["played_today"], st["days"]], [3, 3, true, 4],
		"daily_streak: today and the two days before")
	_expect(p.daily_streak(today + 86400)["current"], 3, "daily_streak: alive until a whole day is missed")
	_expect(p.daily_streak(today + 86400)["played_today"], false, "daily_streak: ...but today is not played")
	_expect(p.daily_streak(today + 2 * 86400)["current"], 0, "daily_streak: a missed day breaks it")
	_expect(p.daily_streak(today + 2 * 86400)["longest"], 3, "daily_streak: the longest stays")
	_expect(Profile.daily_seed_for("2026-11-22"), hash("2026-11-22") & 0x7FFFFFFF, "daily_seed_for is the old formula")
	# tries, the ranked first finish, and the report record_daily returns
	var d = Profile.new()
	d.note_daily_try(9)
	var r1: Dictionary = d.record_daily({"won": false, "floor": 3, "turns": 50, "seed": 9})
	_expect(str(r1), str({"ranked": true, "new_best": false, "tries": 1}), "record_daily: the first finish is ranked")
	d.note_daily_try(9)
	var r2: Dictionary = d.record_daily({"won": false, "floor": 5, "turns": 70, "seed": 9})
	_expect(str(r2), str({"ranked": false, "new_best": true, "tries": 2}), "record_daily: a better finish is a new best")
	var r3: Dictionary = d.record_daily({"won": false, "floor": 2, "turns": 70, "seed": 9})
	_expect(str(r3), str({"ranked": false, "new_best": false, "tries": 2}), "record_daily: a worse finish is neither")
	_expect(str(d.daily_first["9"]), str({"won": false, "floor": 3, "turns": 50}), "daily_first keeps the first finish")
	_expect(int(d.daily_best["9"]["floor"]), 5, "daily_best keeps improving")
	_expect([d.runs, d.history, d.unseen], [0, [], []], "the daily leaves the career alone")
	# a profile from before daily_first: its best stands in as the ranked
	# finish, so a worse retry is neither ranked nor filed as the first
	var lg = Profile.new()
	lg.daily_best = {"9": {"won": true, "floor": 7, "turns": 80}}
	var rl: Dictionary = lg.record_daily({"won": false, "floor": 2, "turns": 30, "seed": 9})
	_expect(bool(rl["ranked"]), false, "record_daily: a legacy best is the ranked result, not the next finish")
	_expect(str(lg.daily_first["9"]), str({"won": true, "floor": 7, "turns": 80}),
		"record_daily: daily_first takes the legacy best")
	var lpath := "user://test_profile_legacy_daily.json"
	var lf := FileAccess.open(lpath, FileAccess.WRITE)
	lf.store_string(JSON.stringify({"daily_best": {"5": {"won": false, "floor": 4, "turns": 60}}}))
	lf.close()
	var lp = Profile.load_from(lpath)
	_expect(str(lp.daily_first), str({"5": {"won": false, "floor": 4, "turns": 60}}),
		"load_from backfills daily_first from a legacy daily_best")
	DirAccess.remove_absolute(lpath)
	var ds = Profile.new()
	ds.record_daily({"won": true, "floor": 7, "turns": 90, "seed": 3, "score": 1500})
	_expect(str(ds.daily_best["3"]), str({"won": true, "floor": 7, "turns": 90, "score": 1500}),
		"record_daily stores a score only when the summary has one")
	print("daily streak: current / longest / missed day, tries, ranked first, new best, score: OK")


# --- 10) fun pass, career B: feats -------------------------------------------------

## A summary every fixture starts from: a career loss that meets nothing.
func _feat_base() -> Dictionary:
	return {"won": false, "floor": 3, "tier": 0, "turns": 50, "seed": 1, "loadout": "tender",
		"kit": ["seed_bomb"], "grafts": [], "score": 100, "score_v": Content.RUN_SCORE_VERSION,
		"date": "2026-03-04", "bosses_killed": [], "uses_by_base": {}}


## A fresh profile and summary that meet ONE req key exactly (`miss` false) or
## miss it by one (`miss` true), built from the key's own value - so a new
## FEATS row is covered with no edit here, and a req key with no arm fails.
## Returns false for a req key with no fixture arm.
func _feat_fixture(p, s: Dictionary, k: String, v, miss: bool) -> bool:
	match k:
		"won":
			s["won"] = (not bool(v)) if miss else bool(v)
		"min_tier":
			s["tier"] = int(v) - 1 if miss else int(v)
		"max_turns":
			s["turns"] = int(v) + 1 if miss else int(v)
		"max_grafts":
			var gids: Array = Content.GRAFTS.keys()
			s["grafts"] = gids.slice(0, int(v) + 1) if miss else gids.slice(0, int(v))
		"stat_min":
			for sk in v:
				s[sk] = int(v[sk]) - 1 if miss else int(v[sk])
		"stat_max":
			for sk in v:
				s[sk] = int(v[sk]) + 1 if miss else int(v[sk])
		"boss":
			s["bosses_killed"] = [] if miss else [String(v)]
		"total_min":
			# the career holds n - 1; this run adds 1 (met) or 0 (missed)
			for tk in v:
				p.totals[tk] = int(v[tk]) - 1
				s[tk] = 0 if miss else 1
		"all_bosses":
			var bs: Array = Profile.boss_set()
			p.bosses_beaten = bs.slice(0, bs.size() - 1)
			s["bosses_killed"] = [] if miss else [bs.back()]
		"all_loadouts_won":
			var lids: Array = Content.LOADOUTS.keys()
			for lid in lids.slice(0, lids.size() - 1):
				p.records["loadouts"][lid] = Profile._loadout_rec(7, 0, 0, 1, 1)
			s["loadout"] = lids.back()
			s["won"] = not miss
		"all_bases_cast":
			var bases: Array = Profile.base_set()
			p.cast_ever = bases.slice(0, bases.size() - 1)
			s["uses_by_base"] = {} if miss else {bases.back(): 1}
		_:
			return false
	return true


## The feat req keys whose bar is a SET (or a named member of one): their
## missed-by-one fixture also has a contributing form (_feat_contrib_miss).
const SET_FEAT_KEYS := ["boss", "all_bosses", "all_loadouts_won", "all_bases_cast"]


## A set key one short while this run DOES add to it: a different boss, the
## career's next-to-last boss, a win with a loadout that already has one, a
## cast of a base already cast.
func _feat_contrib_miss(p, s: Dictionary, k: String, v) -> void:
	match k:
		"boss":
			var others: Array = Profile.boss_set().filter(func(b): return String(b) != String(v))
			s["bosses_killed"] = [others[0]]
		"all_bosses":
			var bs: Array = Profile.boss_set()
			p.bosses_beaten = bs.slice(0, bs.size() - 2)
			s["bosses_killed"] = [bs[bs.size() - 2]]
		"all_loadouts_won":
			var lids: Array = Content.LOADOUTS.keys()
			for lid in lids.slice(0, lids.size() - 1):
				p.records["loadouts"][lid] = Profile._loadout_rec(7, 0, 0, 1, 1)
			s["loadout"] = lids[0]
			s["won"] = true
		"all_bases_cast":
			var bases: Array = Profile.base_set()
			p.cast_ever = bases.slice(0, bases.size() - 1)
			s["uses_by_base"] = {bases[0]: 1}


func _check_feats() -> void:
	var met := 0
	var missed := 0
	var contrib := 0
	for fid in Content.FEATS:
		var req: Dictionary = Content.FEATS[fid]["req"]
		# met: every key at its exact bar
		var p = Profile.new()
		var s := _feat_base()
		var known := true
		for k in req:
			if not _feat_fixture(p, s, String(k), req[k], false):
				_fail("feat %s: req key '%s' has no fixture arm (add one, and an arm in Profile._feat_met)" % [fid, k])
				known = false
		if not known:
			continue
		p.record_run(s)
		if p.feats.has(fid) and p.last_report["feats"].has(fid):
			met += 1
		else:
			_fail("feat %s: a run meeting %s exactly did not earn it" % [fid, str(req)])
		# missed by one: each key on its own, the others still met
		for miss_k in req:
			var pm = Profile.new()
			var sm := _feat_base()
			for k in req:
				_feat_fixture(pm, sm, String(k), req[k], k == miss_k)
			pm.record_run(sm)
			if pm.feats.has(fid):
				_fail("feat %s: a run missing '%s' by one still earned it" % [fid, miss_k])
			else:
				missed += 1
			# a set key missed by one while the run DOES contribute: an arm
			# that reads only this run (any boss, "killed a boss", "won",
			# "cast something") passes the plain miss above and fails this one
			if not SET_FEAT_KEYS.has(String(miss_k)):
				continue
			var pc = Profile.new()
			var sc := _feat_base()
			for k in req:
				if k == miss_k:
					_feat_contrib_miss(pc, sc, String(k), req[k])
				else:
					_feat_fixture(pc, sc, String(k), req[k], false)
			pc.record_run(sc)
			if pc.feats.has(fid):
				_fail("feat %s: a run that contributes to '%s' but leaves it one short still earned it" % [fid, miss_k])
			else:
				contrib += 1
	# earned once only, dated off the summary, and named in the report once
	var p1 = Profile.new()
	var s1 := _feat_base()
	s1["rooms_bloomed"] = 6
	p1.record_run(s1)
	_expect(str(p1.feats.get("green_thumb", {})), str({"date": "2026-03-04", "run": 1}), "feat: stored as {date, run}")
	_expect(p1.unseen.has("feat:green_thumb"), true, "feat: a new feat is filed unseen")
	var s2 := _feat_base()
	s2["rooms_bloomed"] = 9
	s2["date"] = "2026-03-05"
	p1.record_run(s2)
	_expect(str(p1.feats["green_thumb"]), str({"date": "2026-03-04", "run": 1}), "feat: earned once, never re-dated")
	_expect(p1.last_report["feats"].has("green_thumb"), false, "feat: a second qualifying run does not report it again")
	_expect(p1.last_report["unlocks"].has("feat:green_thumb"), false, "feat: feats never ride in last_report.unlocks")
	# a legacy summary says nothing, so it earns nothing by saying nothing
	var lg = Profile.new()
	lg.record_run({"won": true, "floor": 7, "tier": 0})
	_expect(lg.feats.has("barefoot") or lg.feats.has("swift_season"), false,
		"feat: a legacy {won, floor, tier} win earns no turns or grafts feat")
	# dailies touch no feat store
	var d = Profile.new()
	var before := [str(d.feats), str(d.records), str(d.totals), str(d.unseen), str(d.bosses_beaten), str(d.cast_ever)]
	var ds := _feat_base()
	ds.merge({"won": true, "rooms_bloomed": 9, "kills": 300, "bosses_killed": ["overseer"], "uses_by_base": {"vine_whip": 3}}, true)
	d.record_daily(ds)
	_expect([str(d.feats), str(d.records), str(d.totals), str(d.unseen), str(d.bosses_beaten), str(d.cast_ever)], before,
		"record_daily leaves feats, records, totals, unseen, bosses and casts untouched")
	_expect(contrib >= SET_FEAT_KEYS.size(), true, "feats: every set key has a contributing miss (%d)" % contrib)
	print("feats: %d rows met at the bar, %d single-key misses and %d contributing set misses rejected, once only, dated, legacy and daily isolation: OK" % [met, missed, contrib])


func _check_feat_folds() -> void:
	var p = Profile.new()
	var s := _feat_base()
	s.merge({"kills": 30, "cleanses": 12, "rooms_bloomed": 0, "bosses_killed": ["the_dredge", "drill_bot"],
		"uses_by_base": {"vine_whip": 2, "solar_lance": 0, "seed_bomb": 1}}, true)
	p.record_run(s)
	p.record_run(s)
	_expect(str(p.totals), str({"kills": 60, "cleanses": 24}), "totals: summed over career runs, zero keys not stored")
	_expect(p.bosses_beaten, ["the_dredge"], "bosses_beaten: boss kinds only, once")
	_expect(p.cast_ever, ["vine_whip", "seed_bomb"], "cast_ever: raw casts > 0, once")
	var v := _feat_base()
	v["uses_by_base"] = {"seed_bomb+tangle": 2}
	var pv = Profile.new()
	pv.record_run(v)
	_expect(pv.cast_ever, ["seed_bomb"], "cast_ever folds a variant to its base")
	_expect(Profile.boss_set(), Content.FLOORS[Content.FLOORS.size() - 1]["bosses"], "boss_set is the last floor's bosses")
	_expect(Profile.base_set().size(), 15, "base_set is DRAFT_POOL + STARTING_KIT (15)")
	# the codec keeps every store
	var path := "user://test_profile_feats.json"
	p.save(path)
	var back = Profile.load_from(path)
	var pd: Dictionary = p.to_dict()
	var bd: Dictionary = back.to_dict()
	_expect([str(bd["feats"]), str(bd["totals"]), bd["bosses_beaten"], bd["cast_ever"]],
		[str(pd["feats"]), str(pd["totals"]), pd["bosses_beaten"], pd["cast_ever"]], "feat stores round-trip")
	DirAccess.remove_absolute(path)
	print("feat folds: totals, bosses, casts (variants folded), derived sets, codec: OK")


func _check_feat_progress() -> void:
	var p = Profile.new()
	_expect(str(p.feat_progress("green_thumb")), str({"have": 0, "need": 5, "frac": 0.0, "text": "0/5"}),
		"feat_progress: a lone stat_min reads the career record")
	p.record_run(_rec_summary(10, {"rooms_bloomed": 3}))
	_expect(int(p.feat_progress("green_thumb")["have"]), 3, "feat_progress: ...the best one run did")
	p.totals = {"kills": 100}
	_expect([p.feat_progress("scrap_heap")["have"], p.feat_progress("scrap_heap")["need"]], [100, 250],
		"feat_progress: total_min reads the career total")
	p.bosses_beaten = ["overseer"]
	_expect(p.feat_progress("warden_of_wardens")["text"], "1/3", "feat_progress: all_bosses counts the set")
	p.cast_ever = ["vine_whip", "seed_bomb"]
	_expect(p.feat_progress("field_botanist")["text"], "2/15", "feat_progress: all_bases_cast counts the set")
	_expect(p.feat_progress("six_ways_home")["need"], Content.LOADOUTS.size(), "feat_progress: all_loadouts_won counts loadouts")
	_expect([p.feat_progress("barefoot")["have"], p.feat_progress("barefoot")["need"]], [0, 1],
		"feat_progress: a multi-key feat is binary")
	p.feats["barefoot"] = Profile._feat_rec("2026-01-01", 1)
	_expect(p.feat_progress("barefoot")["frac"], 1.0, "feat_progress: an earned feat is done")
	# next_feats: numeric needs only, frac descending, the next_goals shape
	var nf: Array = p.next_feats(99)
	for g in nf:
		if int(g["need"]) <= 1 or not String(g["ids"][0]).begins_with("feat:"):
			_fail("next_feats lists a binary or non-feat goal: %s" % str(g))
		if g.keys() != ["desc", "ids", "names", "have", "need", "frac", "key", "text", "hint"]:
			_fail("next_feats row shape: %s" % str(g.keys()))
			break
	_expect(String(nf[0]["ids"][0]), "feat:green_thumb", "next_feats: the closest feat first (3/5)")
	for i in range(1, nf.size()):
		if float(nf[i]["frac"]) > float(nf[i - 1]["frac"]):
			_fail("next_feats is not ranked by fraction")
			break
	_expect(str(p.next_feats(2)), str(p.next_feats(2)), "next_feats: pure")
	# the NEXT fallback: a maxed career's report names the next feat, with delta
	var mx = Profile.new()
	mx.unlocked_tier = Content.TIERS.size()
	for m in Content.MILESTONES:
		mx._bucket(String(m["kind"])).append(String(m["id"]))
	mx.records["best"]["rooms_bloomed"] = Profile._rec(2, 1, "tender", 0)
	var ms := _feat_base()
	ms["rooms_bloomed"] = 4
	mx.record_run(ms)
	var nx: Dictionary = mx.last_report["next"][0]
	_expect([nx["ids"], nx["have"], nx["need"], nx["delta"]], [["feat:green_thumb"], 4, 5, 0],
		"last_report.next falls back to the next feat once every goal is owned; a run-scope feat's have is the best run, so no delta")
	# a cumulative feat keeps its delta: the career total this run added to
	var tx = Profile.new()
	tx.unlocked_tier = Content.TIERS.size()
	for m in Content.MILESTONES:
		tx._bucket(String(m["kind"])).append(String(m["id"]))
	tx.totals = {"kills": 240}
	var ts := _feat_base()
	ts["kills"] = 7
	var tbefore: Array = tx.next_feats(1 << 20)
	tx.record_run(ts)
	var scrap := {}
	for a in Profile._with_delta(tx.next_feats(1 << 20), tbefore):
		if String(a["ids"][0]) == "feat:scrap_heap":
			scrap = a
	_expect([scrap.get("have"), scrap.get("delta")], [247, 7], "a total_min feat's delta is what this run added")
	# a record that predates feats can stand at the bar: unearned reads need - 1
	var old_p = Profile.new()
	old_p.records["best"]["rooms_bloomed"] = Profile._rec(5, 1, "tender", 0)
	_expect(old_p.feat_progress("green_thumb")["text"], "4/5", "feat_progress: an unearned feat never reads done")
	_expect([Profile.unlock_name("feat:heavy_hand"), Profile.unlock_kind("feat:heavy_hand")], ["Heavy Hand", "feat"],
		"unlock_name names a feat from Content.FEATS")
	print("feat progress: stat/total/set/binary, next_feats ranking and shape, the NEXT fallback: OK")


## A career saved before feats (records since stage 2, no feats store): on
## load, every lone stat_min feat its stored record already meets is claimed
## silently - undated, credited to the record's run, never filed unseen - so
## the FEATS tab, the RECORDS tab and next_feats agree. A record under the
## bar claims nothing. (Mutation: drop the backfill loop in load_from and
## Heavy Hand reads 5/6 beside a RECORDS biggest hit of 9, and leads next_feats.)
func _check_feat_backfill() -> void:
	var p = Profile.new()
	p.runs = 4
	p.records["score_v"] = Content.RUN_SCORE_VERSION
	p.records["best"]["biggest_hit_amt"] = Profile._rec(9, 4, "tender", 0)
	p.records["best"]["rooms_bloomed"] = Profile._rec(5, 3, "tender", 0)
	p.records["best"]["combos"] = Profile._rec(19, 2, "tender", 0)
	var d: Dictionary = p.to_dict()
	d.erase("feats")
	d.erase("totals")
	d.erase("bosses_beaten")
	d.erase("cast_ever")
	d["unseen"] = []
	var path := "user://test_profile_prefeat.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	var q = Profile.load_from(path)
	DirAccess.remove_absolute(path)
	_expect(str(q.feats.get("heavy_hand", {})), str({"date": "", "run": 4}),
		"backfill: a record at the bar claims its feat, undated, on the record's run")
	_expect(str(q.feats.get("green_thumb", {})), str({"date": "", "run": 3}), "backfill: exactly at the bar counts")
	_expect(q.feats.has("chain_reaction"), false, "backfill: a record one under the bar claims nothing")
	_expect(q.unseen.is_empty(), true, "backfill: a silent claim is never filed unseen")
	_expect(q.feat_progress("heavy_hand")["text"], "6/6", "backfill: FEATS agrees with RECORDS")
	_expect(q.feat_progress("chain_reaction")["text"], "19/20", "backfill: an unmet feat still reads its record")
	var nf_ids: Array = q.next_feats(1 << 20).map(func(r): return String(r["ids"][0]))
	_expect(nf_ids.has("feat:heavy_hand") or nf_ids.has("feat:green_thumb"), false,
		"backfill: next_feats never asks for a feat the records show done")
	_expect(nf_ids[0], "feat:chain_reaction", "backfill: the nearest unmet feat leads next_feats")
	# a feat already stored keeps its own date and run
	var d2 := d.duplicate(true)
	d2["feats"] = {"heavy_hand": {"date": "2026-02-02", "run": 1}}
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d2))
	f.close()
	var q2 = Profile.load_from(path)
	DirAccess.remove_absolute(path)
	_expect(str(q2.feats["heavy_hand"]), str({"date": "2026-02-02", "run": 1}), "backfill: a stored feat is never re-dated")
	print("feat backfill: a pre-feat career's records claim their feats on load, silently: OK")


func _check_goal_rows() -> void:
	var p = Profile.new()
	p.best_floor = 4
	p.unlocked_loadouts = ["tidewarden", "flarekeeper"]
	var rows: Array = p.goal_rows()
	_expect(rows.size(), Content.MILESTONES.size(), "goal_rows: one entry per milestone")
	var seen_owned := false
	for e in rows:
		if bool(e["owned"]):
			seen_owned = true
		elif seen_owned:
			_fail("goal_rows: an unowned row after the owned ones")
			break
	_expect(String(rows[0]["id"]), "mycology", "goal_rows: the closest unowned row first (floor 4/5)")
	_expect([String(rows[-2]["id"]), String(rows[-1]["id"])], ["tidewarden", "flarekeeper"],
		"goal_rows: owned rows last, in table order")
	print("goal rows: every milestone, unowned ranked then owned in table order: OK")


## --- in-run pings (career part 3) ----------------------------------------------
## run_ref is a pure snapshot of what a run can still earn; ping_events turns
## it plus the run's floor and effective casts into banners, each key once;
## pings_fired_now is what a resumed run has already earned; objective_hint the
## objective line's career part.
func _check_run_ref() -> void:
	var p = Profile.new()
	var ref: Dictionary = p.run_ref()
	_expect(ref["floors"], {3: ["Tidewarden"], 4: ["Flarekeeper"], 5: ["Mycology"]},
		"run_ref: a fresh career's milestone floors, by display name")
	var casts := {}
	for c in ref["casts"]:
		casts[int(c["need"])] = [String(c["base"]), int(c["had"]), c["names"]]
	_expect(casts, {30: ["grow_spike", 0, ["Spiker"]], 60: ["grow_spike", 0, ["Wide Draft"]]},
		"run_ref: the single-ability casts rows")
	_expect([int(ref["runs"]), int(ref["best_floor"])], [0, 0], "run_ref: runs and best floor")
	# owned rows and floors already reached drop out; best_floor IS the snapshot's
	var q = Profile.new()
	q.runs = 6
	q.best_floor = 4
	q.unlocked_loadouts = ["tidewarden", "flarekeeper"]
	q.casts_by_base = {"grow_spike": 41}
	q.unlocked_loadouts.append("spiker")
	var qr: Dictionary = q.run_ref()
	_expect(qr["floors"], {5: ["Mycology"]}, "run_ref: owned and reached floors drop out")
	_expect(qr["casts"].size(), 1, "run_ref: an owned casts row drops out")
	_expect(int(qr["casts"][0]["had"]), 41, "run_ref: the casts row carries the career count")
	for lid in Content.LOADOUTS:
		_expect(int(qr["best_floor"]), int(q.bests_snapshot(String(lid))["best_floor"]),
			"run_ref best_floor == bests_snapshot(%s).best_floor" % lid)
	# merged by (base, need); a two-key row is never a ping
	var m = Profile.new()
	m.milestone_rows = [
		{"id": "kit_of_3", "kind": "mutator", "requires": {"casts": {"vine_whip": 5}}, "desc": "a"},
		{"id": "double_oil", "kind": "mutator", "requires": {"casts": {"vine_whip+lash": 5}}, "desc": "b"},
		{"id": "brittle", "kind": "mutator", "requires": {"best_floor": 2, "wins": 1}, "desc": "c"},
		{"id": "parched", "kind": "mutator", "requires": {"casts": {"vine_whip": 2, "seed_bomb": 2}}, "desc": "d"},
	]
	var mr: Dictionary = m.run_ref()
	_expect(mr["floors"], {}, "run_ref: a two-key floor row is not a floor ping")
	_expect(mr["casts"].size(), 1, "run_ref: same base and need merge, a two-ability row is skipped")
	_expect(mr["casts"][0]["names"], ["Kit of Three", "Slick Combine"], "run_ref: merged names")
	var ev: Array = Profile.ping_events(mr, 1, {"vine_whip": 5}, {})
	_expect(ev.size(), 1, "ping: one merged cast banner")
	if ev.size() == 1:
		_expect(ev[0]["lines"], ["VINE WHIP 5/5", "Kit of Three and Slick Combine unlock when this run ends"],
			"ping: a plural unlock reads 'unlock'")
	# the three kinds, each once
	_expect(Profile.ping_events({}, 3, {"grow_spike": 99}, {}), [], "ping: an empty ref earns nothing")
	_expect(Profile.ping_events(ref, 2, {}, {}), [], "ping: floor 2 on a fresh career is nothing")
	ev = Profile.ping_events(ref, 3, {}, {})
	_expect(ev.size() == 1 and ev[0]["lines"] == ["FLOOR 3", "Tidewarden unlocks when this run ends"], true,
		"ping: a first-ever run reaching floor 3 announces Tidewarden (%s)" % str(ev))
	var deep := {"runs": 1, "best_floor": 3, "floors": {}, "casts": []}
	ev = Profile.ping_events(deep, 4, {}, {})
	_expect(ev.size() == 1 and String(ev[0]["lines"][0]) == "DEEPEST YET"
		and String(ev[0]["lines"][1]) == "floor 4  ·  " + String(Content.FLOORS[3]["name"]), true,
		"ping: DEEPEST YET names the floor (%s)" % str(ev))
	var fired := {}
	for e in ev:
		for k in e["keys"]:
			fired[k] = true
	_expect(Profile.ping_events(deep, 4, {}, fired), [], "ping: DEEPEST YET fires once")
	_expect(Profile.ping_events(deep, 5, {}, fired), [], "ping: ...and not again a floor deeper")
	_expect(Profile.ping_events({"runs": 0, "best_floor": 0, "floors": {}, "casts": []}, 4, {}, {}), [],
		"ping: no DEEPEST YET on a first-ever run")
	var both := {"runs": 2, "best_floor": 2, "floors": {3: ["Tidewarden"]}, "casts": []}
	ev = Profile.ping_events(both, 3, {}, {})
	_expect(ev.size(), 1, "ping: DEEPEST YET on a milestone floor is ONE banner")
	if ev.size() == 1:
		_expect(ev[0]["lines"], ["DEEPEST YET", "Tidewarden unlocks when this run ends"], "ping: the merged banner's words")
		_expect(ev[0]["keys"], ["deepest", "floor:3"], "ping: the merged banner carries both keys")
	var g = Profile.new()
	g.casts_by_base = {"grow_spike": 25}
	var gr: Dictionary = g.run_ref()
	_expect(Profile.ping_events(gr, 1, {"grow_spike": 4}, {}), [], "ping: 29/30 casts is not yet")
	ev = Profile.ping_events(gr, 1, {"grow_spike": 5}, {})
	_expect(ev.size() == 1 and ev[0]["lines"] == ["GROW SPIKE 30/30", "Spiker unlocks when this run ends"], true,
		"ping: the cast count reached (%s)" % str(ev))
	# resume: everything already earned is marked, nothing re-announces
	var now := Profile.pings_fired_now(gr, 4, {"grow_spike": 10})
	_expect(now.has("cast:grow_spike:30") and now.has("floor:3") and now.has("floor:4")
		and not now.has("cast:grow_spike:60") and not now.has("floor:5"), true,
		"pings_fired_now: what a resumed run already earned (%s)" % str(now.keys()))
	_expect(Profile.ping_events(gr, 4, {"grow_spike": 10}, now), [], "ping: nothing re-fires after a resume")
	# the objective line's career part
	_expect(Profile.objective_hint(ref, 4), "floor 5 unlocks Mycology", "objective_hint: the next floor's unlock")
	_expect(Profile.objective_hint(ref, 5), "", "objective_hint: no milestone on the next floor")
	_expect(Profile.objective_hint({}, 2), "", "objective_hint: an empty ref says nothing")
	_expect(Profile.objective_hint({"floors": {3: ["A", "B"]}}, 2), "floor 3 unlocks A and 1 more",
		"objective_hint: one name, then a count")
	print("run ref: floors, casts, DEEPEST YET, the merged banner, resume and the objective hint: OK")
