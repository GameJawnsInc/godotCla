extends RefCounted
## Career profile: persistent meta-progression across runs. Lives outside the
## sim (the sim stays pure); the app layer records finished runs here and asks
## for the next run's config. Milestones are data in Content.MILESTONES.
##
## `record_run` takes a `Game.run_summary()` dict, but every key past
## {won, floor, tier} defaults, so pre-C4 callers keep working. Beyond the
## running totals the profile keeps two things a summary makes possible:
## a capped HISTORY_MAX-entry log of compact per-run records (what the kit and
## the grafts were at the end, newest last) and `casts_by_base`, effective
## casts summed across every recorded run. Milestone predicates read those.
##
## Daily-challenge runs never touch the career: `record_daily` files the best
## result per daily seed in `daily_best` and records nothing else, and
## `daily_config` derives a daily's whole run config from its seed alone -
## no career state, no live content tables (see DAILY_* below).

const Content := preload("res://sim/content.gd")

## Per-run records kept for the history predicates; older entries are dropped.
const HISTORY_MAX := 50

## Frozen daily lists (docs/PROGRESSION_REVIEW.md §6.1, Block A). A daily's
## loadout / package / mutator are picked off THESE lists, never off the live
## Content tables: a table that grows later must not move an earlier date's
## challenge onto different content (or onto content that did not exist when
## the date was played). "" means "none" on the package and mutator axes.
const DAILY_LOADOUTS := ["tender", "tidewarden", "flarekeeper", "spiker", "lasher"]
const DAILY_PACKAGES := ["mycology", "hydraulics", "aeolian", ""]
const DAILY_MUTATORS := ["kit_of_3", "double_oil", "brittle", "parched", "overtime", "boarded", ""]

var runs := 0
var wins := 0
var tier_wins := 0
var best_floor := 0
var unlocked_tier := 0
var unlocked_packages: Array = []
var unlocked_mutators: Array = []
## Starting loadouts the career has earned (Content.LOADOUTS ids); "tender"
## is always playable and is never listed here. Read by game_config and by
## the shell's LOADOUT row.
var unlocked_loadouts: Array = []
## Milestone bucket with no consumer yet (kind "graft").
var unlocked_grafts: Array = []
## Compact per-run records {won, floor, tier, turns, seed, kit, grafts,
## has_kit, loadout, death_cause, bloom, mutators, packages, score} (see
## _compact), newest last, at most HISTORY_MAX of them.
var history: Array = []
## Ability base id -> effective casts summed over every recorded run.
var casts_by_base: Dictionary = {}
## str(daily seed) -> best {won, floor, turns} for that day.
var daily_best: Dictionary = {}
## Test seam only: when non-empty, these rows stand in for Content.MILESTONES.
var milestone_rows: Array = []

## Category records (fun pass, cosmetic: a record buys nothing). RECORD_SHOW is
## the curated subset a player is told about - the only keys whose beating
## lands in last_report.records - as [key, label] in display order.
const RECORD_SHOW := [["score", "Best score"], ["kills", "Most machines felled"],
	["biggest_hit_amt", "Biggest hit"], ["best_multi_kill", "Most felled in one turn"],
	["rooms_bloomed", "Most rooms bloomed"], ["bloom_earned", "Most bloom earned"],
	["combos", "Most combos"], ["fastest_win", "Fastest win"]]
## Career records over CAREER runs (dailies never touch them):
##   best[key] = _rec(v, run, loadout, tier) for every Content.RUN_STAT_KEYS
##     key but closest_hp (a max), "score" (a max) and "fastest_win" (the
##     fewest turns over WINS); only a value > 0 is ever stored
##   loadouts[lid] = _loadout_rec() per Content.LOADOUTS id played
##   score_v = the Content.RUN_SCORE_VERSION the score bests were made under;
##     a different version drops the score bests (and only those), because a
##     changed table never compares across versions
var records: Dictionary = {"best": {}, "loadouts": {}, "score_v": 0}
## What the last record_run did, for the game-over sheet. NOT saved:
## {run, unlocks ("tier:N" first when a tier opened, then milestone ids),
##  feats (none yet), records ([{key, v, was}] for RECORD_SHOW keys beaten
##  where an earlier record existed - run 1 never spams NEW RECORD), next}
var last_report: Dictionary = {}


## Record a finished run and return newly unlocked milestone ids. `summary` is
## a `Game.run_summary()` dict - in the shell merged with RunStats.summary()
## and stamped with `score` / `score_v` - and the legacy {won, floor, tier}
## shape still works (history then records an empty kit and no casts for that
## run, and no record moves). Also folds the run into `records` and leaves
## `last_report` for the game-over sheet.
func record_run(summary: Dictionary) -> Array:
	var entry := _compact(summary)
	var prev_tier := unlocked_tier
	runs += 1
	best_floor = maxi(best_floor, int(entry["floor"]))
	if entry["won"]:
		wins += 1
		if int(entry["tier"]) >= 1:
			tier_wins += 1
		var next_tier: int = int(entry["tier"]) + 1
		if next_tier > unlocked_tier and next_tier <= Content.TIERS.size():
			unlocked_tier = next_tier
	var casts = summary.get("effective_uses_by_base", {})
	if casts is Dictionary:
		for aid in casts:
			var base := Content.base_id(String(aid))
			casts_by_base[base] = int(casts_by_base.get(base, 0)) + int(casts[aid])
	history.append(entry)
	if history.size() > HISTORY_MAX:
		history = history.slice(history.size() - HISTORY_MAX)
	var beaten := _fold_records(summary, entry)
	var news := _claim()
	var unlocks: Array = []
	if unlocked_tier > prev_tier:
		unlocks.append("tier:%d" % unlocked_tier)
	unlocks.append_array(news)
	last_report = {"run": runs, "unlocks": unlocks, "feats": [], "records": beaten, "next": []}
	return news


## The record keys: every flat run stat but closest_hp (a max), plus "score"
## (a max). "fastest_win" (a min over wins) is handled on its own.
static func _record_max_keys() -> Array:
	var out: Array = []
	for k in Content.RUN_STAT_KEYS:
		if k != "closest_hp":
			out.append(String(k))
	out.append("score")
	return out


## One stored record. Keys in sorted order, and the SAME constructor builds a
## record and reloads one, so a saved profile and its reload str() the same.
static func _rec(v: int, run: int, loadout: String, tier: int) -> Dictionary:
	return {"loadout": loadout, "run": run, "tier": tier, "v": v}


## One loadout's row, sorted keys; best_tier_won -1 means never won.
static func _loadout_rec(best_floor := 0, best_score := 0, best_tier_won := -1, n_runs := 0, n_wins := 0) -> Dictionary:
	return {"best_floor": best_floor, "best_score": best_score, "best_tier_won": best_tier_won,
		"runs": n_runs, "wins": n_wins}


## Fold one career run into `records`; returns the RECORD_SHOW keys it beat
## ([{key, v, was}], RECORD_SHOW order) where an earlier record existed.
## Called by record_run after `runs` moved, so a record names its own run.
func _fold_records(summary: Dictionary, entry: Dictionary) -> Array:
	# a summary without score_v (the legacy shapes) carries no score either,
	# so it never moves the version: only a scored summary can reset bests
	if summary.has("score_v"):
		var sv := int(summary["score_v"])
		if sv != int(records["score_v"]):
			_drop_score_bests()
			records["score_v"] = sv
	elif int(records["score_v"]) == 0:
		records["score_v"] = Content.RUN_SCORE_VERSION
	var lid := String(entry["loadout"])
	var tier := int(entry["tier"])
	var won := bool(entry["won"])
	var score := int(entry["score"])
	if Content.LOADOUTS.has(lid):
		var lr: Dictionary = records["loadouts"].get(lid, _loadout_rec())
		lr["runs"] = int(lr["runs"]) + 1
		lr["best_floor"] = maxi(int(lr["best_floor"]), int(entry["floor"]))
		lr["best_score"] = maxi(int(lr["best_score"]), score)
		if won:
			lr["wins"] = int(lr["wins"]) + 1
			lr["best_tier_won"] = maxi(int(lr["best_tier_won"]), tier)
		records["loadouts"][lid] = lr
	var best: Dictionary = records["best"]
	var beaten := {}
	for key in _record_max_keys():
		var v := int(summary.get(key, 0))
		if v <= 0:
			continue
		if best.has(key) and v <= int(best[key]["v"]):
			continue
		if best.has(key):
			beaten[key] = {"key": key, "v": v, "was": int(best[key]["v"])}
		best[key] = _rec(v, runs, lid, tier)
	var turns := int(entry["turns"])
	if won and turns > 0 and (not best.has("fastest_win") or turns < int(best["fastest_win"]["v"])):
		if best.has("fastest_win"):
			beaten["fastest_win"] = {"key": "fastest_win", "v": turns, "was": int(best["fastest_win"]["v"])}
		best["fastest_win"] = _rec(turns, runs, lid, tier)
	var out: Array = []
	for row in RECORD_SHOW:
		if beaten.has(row[0]):
			out.append(beaten[row[0]])
	return out


func _drop_score_bests() -> void:
	records["best"].erase("score")
	for lid in records["loadouts"]:
		records["loadouts"][lid]["best_score"] = 0


## The career's bests as they stand NOW - a view over `records`. The shell
## takes it BEFORE record_run, so every "was" the game-over sheet prints (NEW
## BEST, DEEPEST YET, the near-miss floor) is the value before this run.
## -> {runs, wins, best_floor, best_score, best_score_loadout, loadout}
func bests_snapshot(loadout: String) -> Dictionary:
	var best: Dictionary = records["best"]
	var lr: Dictionary = records["loadouts"].get(loadout, {})
	return {
		"runs": runs, "wins": wins, "best_floor": best_floor,
		"best_score": int(best["score"]["v"]) if best.has("score") else 0,
		"best_score_loadout": int(lr.get("best_score", 0)),
		"loadout": loadout,
	}


## Daily challenge result: best-per-seed only, never career progress.
func record_daily(summary: Dictionary) -> void:
	var key := str(int(summary.get("seed", 0)))
	var rec := {
		"won": bool(summary.get("won", false)),
		"floor": int(summary.get("floor", 0)),
		"turns": int(summary.get("turns", 0)),
	}
	if not daily_best.has(key) or _daily_better(rec, daily_best[key]):
		daily_best[key] = rec


## A win beats a loss, then a deeper floor, then fewer turns.
static func _daily_better(a: Dictionary, b: Dictionary) -> bool:
	if bool(a["won"]) != bool(b["won"]):
		return bool(a["won"])
	if int(a["floor"]) != int(b["floor"]):
		return int(a["floor"]) > int(b["floor"])
	return int(a["turns"]) < int(b["turns"])


## The stored shape of one run: the scalars the ladder needs plus the two
## lists the history predicates read. Unknown ids are dropped on the way in.
func _compact(summary: Dictionary) -> Dictionary:
	return {
		"won": bool(summary.get("won", false)),
		"floor": int(summary.get("floor", 0)),
		"tier": int(summary.get("tier", 0)),
		"turns": int(summary.get("turns", 0)),
		"seed": int(summary.get("seed", 0)),
		"kit": _known_ability_ids(summary.get("kit", [])),
		"grafts": _known_ids(summary.get("grafts", []), Content.GRAFTS),
		# a legacy {won, floor, tier} record carries no kit: it must never
		# satisfy a wins_without predicate by looking like an empty kit
		"has_kit": summary.has("kit"),
		# fun pass (appended so the record path and load_from keep one key
		# order): what the run was and what it scored
		"loadout": _known_loadout(summary.get("loadout", "")),
		"death_cause": String(summary.get("death_cause", "")),
		"bloom": int(summary.get("bloom", 0)),
		"mutators": _known_ids(summary.get("mutators", []), Content.MUTATORS),
		"packages": _known_ids(summary.get("packages", []), Content.PACKAGES),
		"score": int(summary.get("score", 0)),
	}


## A Content.LOADOUTS id, or "" for anything else.
static func _known_loadout(lid) -> String:
	var s := str(lid) if lid != null else ""
	return s if Content.LOADOUTS.has(s) else ""


## Milestone rows to evaluate. `milestone_rows` is a test seam: Content.
## MILESTONES is const, so a fixture list is the way to drive the dispatch
## (the unknown-kind path included). It is never saved or loaded.
func _milestones() -> Array:
	return milestone_rows if not milestone_rows.is_empty() else Content.MILESTONES


## Award every milestone whose requirements are now met; unknown kinds are
## reported and skipped so a bad row can never silently vanish into a bucket.
func _claim() -> Array:
	var news: Array = []
	for m in _milestones():
		var id := String(m["id"])
		if _owned(id):
			continue
		if not _meets(m.get("requires", {})):
			continue
		var bucket = _bucket(String(m.get("kind", "")))
		if bucket == null:
			push_error("profile: milestone '%s' has unknown kind '%s'" % [id, str(m.get("kind", ""))])
			continue
		bucket.append(id)
		news.append(id)
	return news


## The unlock array for a milestone kind, or null when the kind is unknown.
## GDScript arrays are references, so callers append straight into the member.
func _bucket(kind: String):
	match kind:
		"package":
			return unlocked_packages
		"mutator":
			return unlocked_mutators
		"loadout":
			return unlocked_loadouts
		"graft":
			return unlocked_grafts
	return null


func _owned(id: String) -> bool:
	return unlocked_packages.has(id) or unlocked_mutators.has(id) \
		or unlocked_loadouts.has(id) or unlocked_grafts.has(id)


## Predicate evaluation. Block D5 (resonances) deliberately added NOTHING here.
## A resonance is a pure function of the kit and the grafts, and both are
## already stored per run by _compact, so "won a fire build" is already
## expressible as `won_with: [solar_lance, sun_flare]` - with the exact cards
## named, which is what an unlock ladder wants to teach. A `resonated: [ids]`
## predicate would instead put a second copy of the threshold rule in meta/ (or
## make Game.run_summary carry the active set), and it would add a fourth id
## namespace to the load_from filter that keeps renamed content from bricking a
## profile. It also has no customer: every MILESTONES row unlocks a package, a
## mutator, a loadout or a graft, and D5 ships none of those. If a later block
## wants a resonance milestone, the cheap shape is a `won_with` over the cards
## that light it, not a new predicate.
func _meets(req: Dictionary) -> bool:
	if best_floor < int(req.get("best_floor", 0)):
		return false
	if wins < int(req.get("wins", 0)):
		return false
	if tier_wins < int(req.get("tier_wins", 0)):
		return false
	var casts: Dictionary = req.get("casts", {})
	for aid in casts:
		if int(casts_by_base.get(Content.base_id(String(aid)), 0)) < int(casts[aid]):
			return false
	var with_ids: Array = req.get("won_with", [])
	if not with_ids.is_empty() and _win_holding(with_ids, true) == null:
		return false
	var without_ids: Array = req.get("wins_without", [])
	if not without_ids.is_empty() and _win_holding(without_ids, false) == null:
		return false
	var n_grafts := int(req.get("grafts_owned_at_win", 0))
	if n_grafts > 0:
		var found := false
		for e in history:
			if bool(e["won"]) and e["grafts"].size() >= n_grafts:
				found = true
		if not found:
			return false
	return true


## The first recorded win whose kit holds every id in `ids` (`all_of` true) or
## none of them (`all_of` false); null when there is none.
func _win_holding(ids: Array, all_of: bool):
	for e in history:
		if not bool(e["won"]):
			continue
		if not bool(e.get("has_kit", true)):
			continue
		var hits := 0
		for id in ids:
			if _holds(e["kit"], String(id)):
				hits += 1
		if (all_of and hits == ids.size()) or (not all_of and hits == 0):
			return e
	return null


## Does `kit` hold `want`? An exact id always counts; an upgrade also counts
## as its base ("solar_lance+noon" satisfies "solar_lance", but
## "seed_bomb+tangle" is satisfied only by "seed_bomb+tangle" itself).
## Block D6 needed no change here: Content.base_id already cuts at the first
## "+", so a "<base>+<variant>" id folds exactly as a "<base>+" one did.
static func _holds(kit: Array, want: String) -> bool:
	for aid in kit:
		var s := String(aid)
		if s == want or Content.base_id(s) == want:
			return true
	return false


## Config for the next run: the tier, mutators, loadout and single package the
## menu asked for, each clamped to what the career has actually unlocked. The
## sim gets no "kit" key - the loadout carries the starting kit.
##
## One package per run (docs/PROGRESSION_REVIEW.md §6.1, Block A): a package is
## a run-scoped commitment, so the draft pool is 14 or 17 ids, never 23. The
## old everything-at-once pool is now a deliberate choice, the `open_pool`
## mutator. An unknown or locked package is simply dropped ("none").
func game_config(req_tier: int = 0, req_mutators: Array = [], req_loadout: String = "tender", req_package: String = "") -> Dictionary:
	var muts: Array = []
	for m in req_mutators:
		if unlocked_mutators.has(m):
			muts.append(m)
	var pkgs: Array = []
	if unlocked_packages.has(req_package):
		pkgs.append(String(req_package))
	return {
		"packages": pkgs,
		"tier": clampi(req_tier, 0, unlocked_tier),
		"mutators": muts,
		"loadout": _pick_loadout(String(req_loadout)),
	}


## `want` when the career may play it, else "tender". The id must be known,
## must be tender or unlocked, and its Content.LOADOUTS requires.packages must
## all be unlocked - the sim applies whatever loadout it is handed and only
## warns on an unknown id, so the requirement gate lives here.
func _pick_loadout(want: String) -> String:
	if not Content.LOADOUTS.has(want):
		return "tender"
	if want != "tender" and not unlocked_loadouts.has(want):
		return "tender"
	for pkg in Content.LOADOUTS[want]["requires"].get("packages", []):
		if not unlocked_packages.has(pkg):
			return "tender"
	return want


## The loadout ids a menu may offer: tender plus every unlocked loadout whose
## package requirements this career has met. Preserves LOADOUTS order.
func available_loadouts() -> Array:
	var out: Array = []
	for lid in Content.loadouts_for(unlocked_packages):
		if lid == "tender" or unlocked_loadouts.has(lid):
			out.append(lid)
	return out


## The daily challenge's choices, a pure function of the seed over the frozen
## DAILY_* lists: {loadout, package, mutator, tier}. Career-agnostic by
## construction - a daily needs nothing unlocked and unlocks nothing.
static func daily_config(seed_v: int) -> Dictionary:
	return {
		"loadout": DAILY_LOADOUTS[_daily_pick(seed_v, "loadout", DAILY_LOADOUTS.size())],
		"package": DAILY_PACKAGES[_daily_pick(seed_v, "package", DAILY_PACKAGES.size())],
		"mutator": DAILY_MUTATORS[_daily_pick(seed_v, "mutator", DAILY_MUTATORS.size())],
		"tier": 0,
	}


## That same daily as a sim run config (`Game.new(seed, ...)`): the three
## choices spelled the way the sim reads them. One place, so the shell and
## tests/daily_run.gd cannot drift apart on what today's run is.
static func daily_game_config(seed_v: int) -> Dictionary:
	var d := daily_config(seed_v)
	var out := {
		"packages": [], "tier": int(d["tier"]), "mutators": [],
		"loadout": String(d["loadout"]),
	}
	if String(d["package"]) != "":
		out["packages"] = [String(d["package"])]
	if String(d["mutator"]) != "":
		out["mutators"] = [String(d["mutator"])]
	return out


## Index for one daily axis: a hash of (seed, axis name), so the three picks
## are independent - lengthening one list never shifts the others.
static func _daily_pick(seed_v: int, axis: String, n: int) -> int:
	return (hash("%d:%s" % [seed_v, axis]) & 0x7FFFFFFF) % n


func to_dict() -> Dictionary:
	return {
		"runs": runs, "wins": wins, "tier_wins": tier_wins, "best_floor": best_floor,
		"unlocked_tier": unlocked_tier,
		"unlocked_packages": unlocked_packages.duplicate(),
		"unlocked_mutators": unlocked_mutators.duplicate(),
		"unlocked_loadouts": unlocked_loadouts.duplicate(),
		"unlocked_grafts": unlocked_grafts.duplicate(),
		"history": history.duplicate(true),
		# JSON.stringify sorts object keys, so the id-keyed dictionaries are
		# emitted sorted too - otherwise a saved profile and the profile loaded
		# back from it would differ only in key order.
		"casts_by_base": _sorted(casts_by_base),
		"daily_best": _sorted(daily_best.duplicate(true)),
		"records": {
			"best": _sorted(records["best"].duplicate(true)),
			"loadouts": _sorted(records["loadouts"].duplicate(true)),
			"score_v": int(records["score_v"]),
		},
	}


## `d` with its top-level keys in sorted order.
static func _sorted(d: Dictionary) -> Dictionary:
	var keys: Array = d.keys()
	keys.sort()
	var out: Dictionary = {}
	for k in keys:
		out[k] = d[k]
	return out


## Write the career. ATOMICALLY: the career is saved exactly when a run ends,
## which on a phone is exactly when the OS is most likely to take the app away,
## and a truncated write used to replace a good profile with half a file -
## silently resetting the career, with no notice (the RUN save has one; this
## has none, because there is nothing left to say it about).
##
## So the JSON goes to a temp file beside the target and is renamed over it
## only once it is complete and closed. A rename is atomic on the platforms
## this ships to, so an interrupted save leaves the OLD profile whole; the
## worst case is a stray .tmp, which the next save overwrites. Nothing here
## opens `path` for writing at all.
func save(path: String) -> void:
	var text := JSON.stringify(to_dict())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("profile: cannot open %s (%d) - career not saved" % [tmp, FileAccess.get_open_error()])
		return
	f.store_string(text)
	f.flush()
	var err := f.get_error()
	f.close()
	if err != OK:
		# a short write (a full disk is the realistic one) never gets to
		# stand in for the career that is still on disk
		DirAccess.remove_absolute(tmp)
		push_error("profile: write failed (%d) - the saved career is untouched" % err)
		return
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		push_error("profile: cannot replace %s - the saved career is untouched" % path)


static func load_from(path: String):  # -> Profile (or fresh if missing)
	var profile = new()
	if not FileAccess.file_exists(path):
		return profile
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return profile
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	# A profile that cannot be read may cost the player their career; it must
	# never cost them the app. Reading `.get(...)` off anything but a Dictionary
	# is a hard error that returns null out of here, and the shell assigns that
	# null to `profile` - after which the game cannot boot at all until the
	# player clears app data. JSON.parse_string hands back null for garbage,
	# and a plain Array / float / String for valid JSON that simply is not a
	# profile, so the test is "is it a Dictionary", not "is it null".
	if not (data is Dictionary):
		return profile
	profile.runs = int(data.get("runs", 0))
	profile.wins = int(data.get("wins", 0))
	profile.tier_wins = int(data.get("tier_wins", 0))
	profile.best_floor = int(data.get("best_floor", 0))
	# the one unlock with no Content table to filter against: it is an INDEX
	# into Content.TIERS, so a profile written by a build with more tiers (or
	# kept while TIERS shrank) would hand the menu a tier that cannot be named
	profile.unlocked_tier = clampi(int(data.get("unlocked_tier", 0)), 0, Content.TIERS.size())
	# renamed or removed content must never brick a saved career: every stored
	# id is filtered against the tables that exist right now.
	profile.unlocked_packages = _known_ids(data.get("unlocked_packages", []), Content.PACKAGES)
	profile.unlocked_mutators = _known_ids(data.get("unlocked_mutators", []), Content.MUTATORS)
	profile.unlocked_grafts = _known_ids(data.get("unlocked_grafts", []), Content.GRAFTS)
	profile.unlocked_loadouts = _known_ids(data.get("unlocked_loadouts", []), Content.LOADOUTS)
	var casts: Dictionary = {}
	var stored_casts = data.get("casts_by_base", {})
	if stored_casts is Dictionary:
		for aid in stored_casts:
			var cid := _migrate_ability_id(String(aid))
			if cid != "":
				casts[Content.base_id(cid)] = int(stored_casts[aid])
	profile.casts_by_base = casts
	var hist: Array = []
	var stored_hist = data.get("history", [])
	if stored_hist is Array:
		for e in stored_hist:
			if e is Dictionary:
				hist.append(profile._compact(e))  # keeps the run, filters its ids
	if hist.size() > HISTORY_MAX:
		hist = hist.slice(hist.size() - HISTORY_MAX)
	profile.history = hist
	var daily: Dictionary = {}
	var stored_daily = data.get("daily_best", {})
	if stored_daily is Dictionary:
		for k in stored_daily:
			var v = stored_daily[k]
			if v is Dictionary:
				daily[str(k)] = {"won": bool(v.get("won", false)),
					"floor": int(v.get("floor", 0)), "turns": int(v.get("turns", 0))}
	profile.daily_best = daily
	profile.records = _load_records(data.get("records", {}))
	return profile


## `records` from a saved profile: every key, loadout and number checked
## (JSON hands numbers back as floats), each entry rebuilt through its own
## constructor. A profile from before the fun pass has none and loads empty.
## When the stored score_v is not the live Content.RUN_SCORE_VERSION the
## score bests are dropped - a changed score table never compares - and
## every other record stands.
static func _load_records(stored) -> Dictionary:
	var out := {"best": {}, "loadouts": {}, "score_v": 0}
	if not (stored is Dictionary):
		return out
	var keep: Array = _record_max_keys()
	keep.append("fastest_win")
	var sb = stored.get("best", {})
	if sb is Dictionary:
		for k in sb:
			var e = sb[k]
			if keep.has(String(k)) and e is Dictionary and int(e.get("v", 0)) > 0:
				out["best"][String(k)] = _rec(int(e.get("v", 0)), int(e.get("run", 0)),
					_known_loadout(e.get("loadout", "")), int(e.get("tier", 0)))
	var sl = stored.get("loadouts", {})
	if sl is Dictionary:
		for lid in sl:
			var r = sl[lid]
			if Content.LOADOUTS.has(String(lid)) and r is Dictionary:
				out["loadouts"][String(lid)] = _loadout_rec(int(r.get("best_floor", 0)),
					int(r.get("best_score", 0)), int(r.get("best_tier_won", -1)),
					int(r.get("runs", 0)), int(r.get("wins", 0)))
	out["score_v"] = int(stored.get("score_v", 0))
	if int(out["score_v"]) != Content.RUN_SCORE_VERSION:
		out["best"].erase("score")
		for lid in out["loadouts"]:
			out["loadouts"][lid]["best_score"] = 0
	return out


## `ids` kept in order, dropping anything `known` (a Dictionary of valid ids)
## does not carry.
## Ability ids from a stored record, filtered and migrated. Block D6 renamed
## every base "+" row to "<base>+<variant>", so a career saved before it holds
## ids like "seed_bomb+" that are no longer Content.ABILITIES keys: dropping
## them would silently un-satisfy a won_with milestone that the run really did
## earn. A stored "<base>+" is therefore mapped to that base's FIRST variant -
## derived through Content.variants_of, never a hand-written rename table, and
## first because the table lists the variant that reproduces the pre-D6 row
## first (sim/content.gd says the order is load-bearing). A variant id itself
## is a live key and passes straight through.
static func _known_ability_ids(ids) -> Array:
	var out: Array = []
	if not (ids is Array):
		return out
	for id in ids:
		var mid := _migrate_ability_id(String(id))
		if mid != "":
			out.append(mid)
	return out


## One stored ability id -> the live id it means, "" when there is none.
static func _migrate_ability_id(aid: String) -> String:
	if Content.ABILITIES.has(aid):
		return aid
	if aid.ends_with("+"):
		# pre-D6 upgrade id: "<base>+" with nothing after the "+"
		var vs: Array = Content.variants_of(Content.base_id(aid))
		if not vs.is_empty():
			return String(vs[0])
	return ""


static func _known_ids(ids, known) -> Array:
	var out: Array = []
	if not (ids is Array):
		return out
	for id in ids:
		if known.has(String(id)):
			out.append(String(id))
	return out
