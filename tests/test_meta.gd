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
## Run: godot --headless --path . --script tests/test_meta.gd

const Content := preload("res://sim/content.gd")
const Game := preload("res://sim/game.gd")
const Profile := preload("res://meta/profile.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const Roster := preload("res://bots/roster.gd")

const CAREER_RUNS := 40
const TIER0_CAREER_RUNS := 20
const MUTATOR_SEEDS := 8
## Milestones a career that never leaves tier 0 cannot reach: everything gated
## on tier_wins (Content.MILESTONES), plus `no_lance`. The two C4 milestones
## that are NOT here are the reachability witnesses - a tier-0 optimizer career
## lands `upgrades_only` (a win holding Seed Bomb+) and `wide_draft` (60
## effective Grow Spikes; 20 tier-0 runs cast ~160) on its own. `no_lance`
## wants a win whose final kit dropped Solar Lance, which the optimizer never
## does: intentionally hard, not unreachable - a draft pick over a full kit can
## drop it (sim/game.gd _act_draft), and the predicate is covered directly in
## _check_predicates below.
const TIER0_UNREACHABLE := ["aeolian", "brittle", "parched", "no_lance"]

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


func _init() -> void:
	# 1) career simulation: always play the highest unlocked tier
	var profile = Profile.new()
	var unlock_log: Array = []
	for s in range(1, CAREER_RUNS + 1):
		var t: int = profile.unlocked_tier
		var summary := _career_summary(s, profile.game_config(t))
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

	# 2) save/load roundtrip
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
	if clamped.keys() != ["packages", "tier", "mutators"]:
		_fail("game_config shape changed: %s" % str(clamped.keys()))
	var fresh: Dictionary = Profile.new().game_config(9, ["kit_of_3"])
	if int(fresh["tier"]) != 0 or not fresh["mutators"].is_empty() or not fresh["packages"].is_empty():
		_fail("fresh profile game_config(9, ['kit_of_3']) = %s" % str(fresh))
	print("game_config clamp: OK (tier %d -> %d, mutators dropped)" % [9, int(clamped["tier"])])

	# 4d) a career that never leaves tier 0: the unreachable set is exact
	var p0 = Profile.new()
	for s in range(1, TIER0_CAREER_RUNS + 1):
		p0.record_run(_career_summary(s, p0.game_config(0)))
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


## One optimizer run, handing back the sim's own end-of-run record. Same loop
## and bot as Sweep.run_one, which returns its own dict instead of the game.
func _career_summary(seed_v: int, cfg: Dictionary) -> Dictionary:
	var g = Game.new(seed_v, cfg)
	Sweep.run_loop(g, Roster.make("optimizer", seed_v))
	return g.run_summary()


# --- 2b) load_from filters ids Content no longer carries ----------------------

func _check_load_filters() -> void:
	var dirty := {
		"runs": 3, "wins": 1, "tier_wins": 0, "best_floor": 7, "unlocked_tier": 1,
		"unlocked_packages": ["mycology", "ghost_package"],
		"unlocked_mutators": ["kit_of_3", "ghost_mutator"],
		"unlocked_grafts": ["deep_cells", "ghost_graft"],
		"unlocked_loadouts": ["ghost_loadout"],
		"casts_by_base": {"grow_spike": 12, "ghost_ability": 99},
		"daily_best": {"42": {"won": true, "floor": 9, "turns": 100}},
		"history": [{
			"won": true, "floor": 9, "tier": 0, "turns": 80, "seed": 5,
			"kit": ["solar_lance", "ghost_ability", "seed_bomb+"],
			"grafts": ["deep_cells", "ghost_graft"],
		}],
	}
	var path := "user://test_profile_dirty.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(dirty))
	f.close()
	var p = Profile.load_from(path)
	_expect(p.unlocked_packages, ["mycology"], "load_from drops an unknown package")
	_expect(p.unlocked_mutators, ["kit_of_3"], "load_from drops an unknown mutator")
	_expect(p.unlocked_grafts, ["deep_cells"], "load_from drops an unknown graft")
	_expect(p.unlocked_loadouts, [], "load_from drops loadouts (no Content.LOADOUTS yet)")
	_expect(str(p.casts_by_base), str({"grow_spike": 12}), "load_from drops casts for an unknown ability")
	_expect(p.history.size(), 1, "load_from keeps a history entry with unknown ids")
	_expect(p.history[0]["kit"], ["solar_lance", "seed_bomb+"], "load_from filters the ids inside a history entry")
	_expect(p.history[0]["grafts"], ["deep_cells"], "load_from filters a history entry's grafts")
	_expect(int(p.history[0]["floor"]), 9, "load_from keeps the entry's scalars")
	_expect(str(p.daily_best), str({"42": {"won": true, "floor": 9, "turns": 100}}), "load_from carries daily_best")
	# the filtered profile still evaluates predicates over what survived
	_expect(p._meets({"won_with": ["seed_bomb+"]}), true, "filtered history still satisfies won_with")
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
		"kit": ["solar_lance+", "seed_bomb", "grow_spike"], "grafts": ["deep_cells"]})
	_expect(p._meets({"won_with": ["solar_lance"]}), true, "won_with: a + form satisfies its base")
	_expect(p._meets({"won_with": ["solar_lance+"]}), true, "won_with: the exact + id")
	_expect(p._meets({"won_with": ["seed_bomb+"]}), false, "won_with: a base does not satisfy a + id")
	_expect(p._meets({"won_with": ["solar_lance", "grow_spike"]}), true, "won_with: every id, one run")
	_expect(p._meets({"won_with": ["solar_lance", "vine_whip"]}), false, "won_with: one id missing")
	_expect(p._meets({"wins_without": ["solar_lance"]}), false, "wins_without: the win held it as a + form")
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
			var base_enemies: Dictionary = Content.FLOORS[0]["enemies"]
			var common := ""
			var common_n := 0
			for kind in base_enemies:
				if int(base_enemies[kind]) > common_n:
					common_n = int(base_enemies[kind])
					common = kind
			if int(fdef["enemies"][common]) != common_n + 1:
				return "floor_def(1).enemies[%s] == %d, expected %d" % [common, int(fdef["enemies"][common]), common_n + 1]
			if g.floor_def(Content.FLOORS.size())["enemies"] != Content.FLOORS[Content.FLOORS.size() - 1]["enemies"]:
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
		"wide_draft":
			var offers := _first_draft_offers(2, cfg)
			if offers.size() != 4:
				return "first draft offers %d (%s), expected 4" % [offers.size(), str(offers)]
			var base_offers := _first_draft_offers(2, {})
			if base_offers.size() != 3:
				return "base game first draft offers %d (check proves nothing)" % base_offers.size()
		"upgrades_only":
			var g = Game.new(2, cfg)
			var offers := _first_draft_offers(2, cfg)
			if offers.is_empty():
				return "first draft offered nothing"
			for aid in offers:
				var s := String(aid)
				if not s.ends_with("+"):
					return "offer %s is not a + form (offers %s)" % [s, str(offers)]
				if not g.player["kit"].has(s.trim_suffix("+")):
					return "offer %s upgrades an ability the kit does not hold" % s
			# a kit of nothing but + forms leaves no candidate: the draft is skipped
			var full := Game.new(2, {"mutators": [mut], "kit": ["solar_lance+", "seed_bomb+", "mycelium_dash+"]})
			full.player["pos"] = full.map["stairs"]
			full.greened = full.green_need
			full.step({"type": "descend"})
			if full.phase != "play" or full.floor_num != 2:
				return "an all-+ kit did not skip the draft: phase %s floor %d" % [full.phase, full.floor_num]
		_:
			return "no invariant row in tests/test_meta.gd for mutator '%s'" % mut
	return ""


## The offers of the first descent draft on `seed_v` under `cfg` (the quota is
## handed to the player so the run does not have to be played out).
func _first_draft_offers(seed_v: int, cfg: Dictionary) -> Array:
	var g = Game.new(seed_v, cfg)
	g.player["pos"] = g.map["stairs"]
	g.greened = g.green_need
	g.step({"type": "descend"})
	return g.draft_offers.duplicate()


func _oil_count(g) -> int:
	var n := 0
	for t in g.terrain:
		if g.terrain[t]["kind"] == "oil":
			n += 1
	return n
