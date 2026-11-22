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
## result per daily seed in `daily_best` (plus the ranked first finish in
## `daily_first` and the attempts in `daily_tries`) and records nothing else, and
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

## Career layer (fun pass, cosmetic): what the menu badges NEW and what the
## daily keeps beside its best.
## Days daily_streak scans back for the longest streak.
const DAILY_LOOKBACK := 400
## The goal ladder's predicate order: progress() lists a row's parts in it and
## next_goals() breaks frac ties with it (a floor to reach before a win).
const GOAL_KEY_ORDER := ["best_floor", "wins", "tier_wins", "casts", "won_with",
	"wins_without", "grafts_owned_at_win"]
## Ids announced but not yet looked at - milestone ids, "tier:N" and
## "feat:<id>" - newest last, no duplicates. Drives the menu's NEW badges;
## cycling onto the thing (mark_seen) clears it, and opening the CAREER
## sheet's FEATS tab clears every "feat:" entry.
var unseen: Array = []
## str(daily seed) -> STARTED attempts (note_daily_try, at PLAY).
var daily_tries: Dictionary = {}
## str(daily seed) -> the FIRST finished result, the ranked one (same shape as
## daily_best, which keeps improving).
var daily_first: Dictionary = {}

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
##  feats (ids newly earned, Content.FEATS order), records ([{key, v, was}]
##  for RECORD_SHOW keys beaten where an earlier record existed - run 1 never
##  spams NEW RECORD), next (next_goals(1), or next_feats(1) once every goal
##  is owned, each with "delta" - always 0 on a run-scope stat_min feat,
##  whose have is the best run rather than a running count)}
var last_report: Dictionary = {}

## Cosmetic feats (fun pass, Content.FEATS; a feat buys nothing). Folded by
## CAREER runs only - record_daily touches none of these:
## feat id -> _feat_rec(date, run): the UTC date the shell stamped on the
## summary (the profile reads no clock) and the run that earned it.
var feats: Dictionary = {}
## Content.FEAT_TOTAL_KEYS -> that summary key summed over career runs (only
## keys that ever moved are stored).
var totals: Dictionary = {}
## Boss kinds (ENEMIES rows with the "boss" trait) shut down in career runs,
## first kill first.
var bosses_beaten: Array = []
## Base ability ids with at least one RAW cast (uses_by_base) in a career run -
## raw, not effective: a self-only ability (thorn_shield, bramble_coat) never
## counts as effective, and "cast it" is what Field Botanist asks.
var cast_ever: Array = []


## Record a finished run and return newly unlocked milestone ids. `summary` is
## a `Game.run_summary()` dict - in the shell merged with RunStats.summary()
## and stamped with `score` / `score_v` / `date` - and the legacy {won, floor,
## tier} shape still works (history then records an empty kit and no casts for
## that run, and no record, total or feat moves). After the milestones it
## folds the career feat stores (_fold_career), the records (_fold_records),
## earns feats (_claim_feats, dated off the summary - the profile reads no
## clock), files the unlocks and new feats as unseen, and leaves
## `last_report` for the game-over sheet.
func record_run(summary: Dictionary) -> Array:
	var entry := _compact(summary)
	var prev_tier := unlocked_tier
	var goals_before := next_goals(1 << 20)
	var feats_before := next_feats(1 << 20)
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
	var news := _claim()
	_fold_career(summary)
	var beaten := _fold_records(summary, entry)
	var new_feats := _claim_feats(summary, _as_str(summary.get("date")))
	var unlocks: Array = []
	if unlocked_tier > prev_tier:
		unlocks.append("tier:%d" % unlocked_tier)
	unlocks.append_array(news)
	var announce: Array = unlocks.duplicate()
	for fid in new_feats:
		announce.append("feat:" + String(fid))
	for id in announce:
		if not unseen.has(id):
			unseen.append(id)
	# the next goal; once every milestone and difficulty is owned, the next
	# feat with a number to chase stands in (same shape, delta and all)
	var nxt := _with_delta(next_goals(1), goals_before)
	if nxt.is_empty():
		nxt = _with_delta(next_feats(1), feats_before)
		# a run-scope (stat_min) feat's have is the career's BEST run, so a
		# rise in it is not "this run's contribution": no delta there
		for g in nxt:
			if String(g["key"]) == "stat_min":
				g["delta"] = 0
	last_report = {"run": runs, "unlocks": unlocks, "feats": new_feats, "records": beaten,
		"next": nxt}
	return news


## `after` (next_goals rows) each with "delta": the have this run gained on
## the same goal in `before` (matched by its first id; 0 for a goal that is
## new). "Land 30 Grow Spikes 17/30 (+9 this run)" reads the 9 from here.
static func _with_delta(after: Array, before: Array) -> Array:
	var was := {}
	for g in before:
		was[String(g["ids"][0])] = int(g["have"])
	var out: Array = []
	for g in after:
		var row: Dictionary = g.duplicate(true)
		var k := String(row["ids"][0])
		row["delta"] = maxi(0, int(row["have"]) - int(was[k])) if was.has(k) else 0
		out.append(row)
	return out


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
		var sv := _as_int(summary["score_v"], 0)
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
		var v := _as_int(summary.get(key), 0)
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


# --- feats (fun pass, cosmetic) ---------------------------------------------------

## The sets the career feats read, derived from content - never literals, so a
## fourth boss or a sixteenth base joins the feat with no edit here.
## The final floor's bosses (Content.FLOORS' last row).
static func boss_set() -> Array:
	return Content.FLOORS[Content.FLOORS.size() - 1].get("bosses", []).duplicate()


## The base abilities a career can cast: DRAFT_POOL plus STARTING_KIT (15).
static func base_set() -> Array:
	var out: Array = Content.DRAFT_POOL.duplicate()
	for aid in Content.STARTING_KIT:
		if not out.has(aid):
			out.append(aid)
	return out


## Is `kind` an ENEMIES row with the "boss" trait?
static func _is_boss(kind: String) -> bool:
	return Content.ENEMIES.get(kind, {}).get("traits", []).has("boss")


## One earned feat, sorted keys (record path and load_from share it).
static func _feat_rec(date: String, run: int) -> Dictionary:
	return {"date": date, "run": run}


## Fold one career run into the feat stores: the FEAT_TOTAL_KEYS sums, the
## bosses it shut down and the bases it cast at all. A legacy summary carries
## none of these keys and folds nothing.
func _fold_career(summary: Dictionary) -> void:
	for k in Content.FEAT_TOTAL_KEYS:
		var v := _as_int(summary.get(k), 0)
		if v > 0:
			totals[k] = int(totals.get(k, 0)) + v
	var bosses = summary.get("bosses_killed", [])
	if bosses is Array:
		for b in bosses:
			var kind := _as_str(b)
			if _is_boss(kind) and not bosses_beaten.has(kind):
				bosses_beaten.append(kind)
	var uses = summary.get("uses_by_base", {})
	if uses is Dictionary:
		for aid in uses:
			var base := Content.base_id(_as_str(aid))
			if Content.ABILITIES.has(base) and _as_int(uses[aid], 0) > 0 and not cast_ever.has(base):
				cast_ever.append(base)


## Earn every feat this run (and the career it just joined) now meets; each is
## earned once, ever. Returns the new ids in Content.FEATS order.
func _claim_feats(summary: Dictionary, date: String) -> Array:
	var out: Array = []
	for fid in Content.FEATS:
		if feats.has(fid):
			continue
		if _feat_met(Content.FEATS[fid]["req"], summary):
			feats[fid] = _feat_rec(date, runs)
			out.append(fid)
	return out


## Every key of `req` must hold. One arm per Content.FEAT_REQ_KEYS entry; an
## unknown key never holds (tests/test_content.gd rejects one first). A run
## key the summary does not carry fails rather than defaulting into a pass, so
## a legacy {won, floor, tier} summary earns no "in 100 turns" or "holding no
## grafts" feat by saying nothing.
func _feat_met(req: Dictionary, summary: Dictionary) -> bool:
	for k in req:
		var v = req[k]
		match String(k):
			"won":
				if _as_bool(summary.get("won"), false) != bool(v):
					return false
			"min_tier":
				if _as_int(summary.get("tier"), 0) < int(v):
					return false
			"max_turns":
				var t := _as_int(summary.get("turns"), 0)
				if t < 1 or t > int(v):
					return false
			"max_grafts":
				var g = summary.get("grafts")
				if not (g is Array) or g.size() > int(v):
					return false
			"stat_min":
				for sk in v:
					if _as_int(summary.get(sk), 0) < int(v[sk]):
						return false
			"stat_max":
				for sk in v:
					if _as_int(summary.get(sk), 1 << 30) > int(v[sk]):
						return false
			"boss":
				var bk = summary.get("bosses_killed", [])
				if not (bk is Array) or not bk.has(String(v)):
					return false
			"total_min":
				for tk in v:
					if int(totals.get(tk, 0)) < int(v[tk]):
						return false
			"all_bosses":
				for b in boss_set():
					if not bosses_beaten.has(b):
						return false
			"all_loadouts_won":
				for lid in Content.LOADOUTS:
					if int(records["loadouts"].get(lid, {}).get("wins", 0)) < 1:
						return false
			"all_bases_cast":
				for b in base_set():
					if not cast_ever.has(b):
						return false
			_:
				return false
	return true


## How far the career is along one feat: {have, need, frac, text}. Numeric
## where the feat has one number to chase - a lone stat_min reads the career
## record for that key (the best one run has done), total_min the career
## total, the all_* sets how many are done - else 0/1. An earned feat reads
## have == need; an unearned one is capped at need - 1 (a record that predates
## feats can stand at the bar without the feat ever having been claimed).
func feat_progress(fid: String) -> Dictionary:
	var req: Dictionary = Content.FEATS.get(fid, {}).get("req", {})
	var have := 0
	var need := 1
	if req.size() == 1:
		var k := String(req.keys()[0])
		var v = req[k]
		match k:
			"stat_min", "total_min":
				if v is Dictionary and v.size() == 1:
					var sk := String(v.keys()[0])
					need = maxi(1, int(v[sk]))
					if k == "stat_min":
						have = int(records["best"][sk]["v"]) if records["best"].has(sk) else 0
					else:
						have = int(totals.get(sk, 0))
			"all_bosses":
				need = boss_set().size()
				for b in boss_set():
					if bosses_beaten.has(b):
						have += 1
			"all_loadouts_won":
				need = Content.LOADOUTS.size()
				for lid in Content.LOADOUTS:
					if int(records["loadouts"].get(lid, {}).get("wins", 0)) >= 1:
						have += 1
			"all_bases_cast":
				need = base_set().size()
				for b in base_set():
					if cast_ever.has(b):
						have += 1
	need = maxi(1, need)
	if feats.has(fid):
		have = need
	else:
		have = mini(have, need - 1)
	return {"have": have, "need": need, "frac": float(have) / float(need), "text": "%d/%d" % [have, need]}


## The next `n` feats worth chasing: unearned feats with a number above 1 to
## reach, ranked by fraction done (descending) then table order - in the SAME
## shape as next_goals ({desc, ids: ["feat:<id>"], names: [feat name], have,
## need, frac, key, text, hint}), so the game-over sheet's NEXT line reads
## either. The fallback once next_goals is empty (a maxed career).
func next_feats(n: int) -> Array:
	var cands: Array = []
	var idx := 0
	for fid in Content.FEATS:
		idx += 1
		if feats.has(fid):
			continue
		var fp := feat_progress(fid)
		if int(fp["need"]) <= 1:
			continue
		var row: Dictionary = Content.FEATS[fid]
		cands.append({"desc": String(row["desc"]), "ids": ["feat:" + fid], "names": [String(row["name"])],
			"have": int(fp["have"]), "need": int(fp["need"]), "frac": float(fp["frac"]),
			"key": String(row["req"].keys()[0]), "text": String(fp["text"]), "hint": "",
			"rank": [-float(fp["frac"]), idx]})
	cands.sort_custom(func(a, b):
		if a["rank"][0] != b["rank"][0]:
			return a["rank"][0] < b["rank"][0]
		return a["rank"][1] < b["rank"][1])
	var out: Array = []
	for c in cands.slice(0, n):
		c.erase("rank")
		out.append(c)
	return out


## Daily challenge result: best-per-seed only, never career progress (no
## run, no record, no unlock, no NEW badge). The first finish on a seed is
## also kept in daily_first - the RANKED result, the one a shared daily is
## compared on - while daily_best keeps improving. Returns what the game-over
## sheet says about it: {ranked (this was the first finish), new_best (an
## earlier best was beaten), tries (attempts started on this seed)}.
func record_daily(summary: Dictionary) -> Dictionary:
	var key := daily_key(summary.get("seed"))
	# the score rides along only when the summary has one, so a legacy
	# {won, floor, turns} result keeps exactly its old stored shape
	var rec := _daily_rec(summary.get("won"), summary.get("floor"), summary.get("turns"),
		summary.get("score") if summary.has("score") else null)
	# a profile from before daily_first existed holds a best and no ranked
	# finish: that best stands in as the ranked one (the earliest result on
	# file), so a worse retry today is never filed as the first finish
	if daily_best.has(key) and not daily_first.has(key):
		daily_first[key] = daily_best[key].duplicate()
	var ranked := not daily_first.has(key)
	if ranked:
		daily_first[key] = rec.duplicate()
	var new_best := false
	if not daily_best.has(key):
		daily_best[key] = rec
	elif _daily_better(rec, daily_best[key]):
		daily_best[key] = rec
		new_best = true
	return {"ranked": ranked, "new_best": new_best, "tries": int(daily_tries.get(key, 0))}


## One stored daily result, in the ONE key order the record path and load_from
## share. `score` is kept only when it is a number.
static func _daily_rec(won, floor_v, turns, score = null) -> Dictionary:
	var out := {"won": _as_bool(won, false), "floor": _as_int(floor_v, 0), "turns": _as_int(turns, 0)}
	if score is int or score is float:
		out["score"] = int(score)
	return out


## A daily attempt was started on `seed_v` (the shell calls it at PLAY, so a
## retry counts as a try whether or not it ends).
func note_daily_try(seed_v: int) -> void:
	var key := daily_key(seed_v)
	daily_tries[key] = int(daily_tries.get(key, 0)) + 1


## The daily seed for a UTC date string ("2026-11-22"): the ONE formula - the
## shell's _daily_seed, tests/daily_run.gd and daily_streak all call it.
static func daily_seed_for(date: String) -> int:
	return hash(date) & 0x7FFFFFFF


## The daily streak as of `today_unix` (passed in: this touches no clock and
## stores nothing - a streak is re-derived by re-hashing each date):
## {current, longest, played_today, days}. A day counts when daily_best holds
## a finish for that date's seed. `current` counts back from today when today
## is played, else from yesterday, so a streak stays alive until a whole day
## is missed; `longest` is the longest run inside DAILY_LOOKBACK days; `days`
## is how many dailies were ever finished.
func daily_streak(today_unix: int) -> Dictionary:
	var hits: Array = []
	for k in DAILY_LOOKBACK:
		var date := Time.get_date_string_from_unix_time(today_unix - 86400 * k)
		hits.append(daily_best.has(daily_key(daily_seed_for(date))))
	var played_today: bool = hits[0]
	var current := 0
	var i := 0 if played_today else 1
	while i < hits.size() and hits[i]:
		current += 1
		i += 1
	var longest := 0
	var run := 0
	for h in hits:
		run = run + 1 if h else 0
		longest = maxi(longest, run)
	return {"current": current, "longest": longest, "played_today": played_today,
		"days": daily_best.size()}


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
	var kit := _known_ability_ids(summary.get("kit", []))
	return {
		"won": _as_bool(summary.get("won"), false),
		"floor": _as_int(summary.get("floor"), 0),
		"tier": _as_int(summary.get("tier"), 0),
		"turns": _as_int(summary.get("turns"), 0),
		"seed": _as_int(summary.get("seed"), 0),
		"kit": kit,
		"grafts": _known_ids(summary.get("grafts", []), Content.GRAFTS),
		# a legacy {won, floor, tier} record carries no kit: it must never
		# satisfy a wins_without predicate by looking like an empty kit. A
		# stored entry keeps its own flag (load_from runs every entry back
		# through here, and the reloaded `kit: []` key must not flip it), and
		# a kit that is not a real array, or holds no known id (a corrupt file,
		# renamed content - a real run never ends with an empty kit), counts
		# as no kit
		"has_kit": _as_bool(summary.get("has_kit"), true) and summary.get("kit") is Array \
			and not kit.is_empty(),
		# fun pass (appended so the record path and load_from keep one key
		# order): what the run was and what it scored
		"loadout": _known_loadout(summary.get("loadout", "")),
		"death_cause": _as_str(summary.get("death_cause")),
		"bloom": _as_int(summary.get("bloom"), 0),
		"mutators": _known_ids(summary.get("mutators", []), Content.MUTATORS),
		"packages": _known_ids(summary.get("packages", []), Content.PACKAGES),
		"score": _as_int(summary.get("score"), 0),
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


# --- the goal ladder (fun pass) -----------------------------------------------

## How far the career is along one milestone row:
## {have, need, done, frac, key, text, hint, parts: [{key, have, need, text}]}.
## `have` is capped at `need`. `parts` holds one entry per requires key in
## GOAL_KEY_ORDER; the headline (have, need, key, text) is the part with the
## SMALLEST have/need fraction, so a two-key row shows its harder half. A
## binary key (won_with / wins_without) is 0/1 and its text is the hint read
## off the history ("held it in 3 runs (best floor 5)") or "not yet". An owned
## row reads done, have == need, text "done".
func progress(row: Dictionary) -> Dictionary:
	var req: Dictionary = row.get("requires", {})
	var parts: Array = []
	var hint := ""
	for k in GOAL_KEY_ORDER:
		if not req.has(k):
			continue
		var v = req[k]
		var have := 0
		var need := 1
		var text := ""
		match k:
			"best_floor":
				need = maxi(1, int(v))
				have = mini(best_floor, need)
				text = "best floor %d/%d" % [have, need]
			"wins":
				need = maxi(1, int(v))
				have = mini(wins, need)
				text = "wins %d/%d" % [have, need]
			"tier_wins":
				need = maxi(1, int(v))
				have = mini(tier_wins, need)
				text = "wins at difficulty 1+ %d/%d" % [have, need]
			"casts":
				need = 0
				var bits: Array = []
				for aid in v:
					var n := int(v[aid])
					var h := mini(int(casts_by_base.get(Content.base_id(String(aid)), 0)), n)
					need += n
					have += h
					bits.append("%s %d/%d" % [_ability_name(String(aid)), h, n])
				need = maxi(1, need)
				text = "  ·  ".join(bits)
			"won_with", "wins_without":
				var all_of: bool = k == "won_with"
				have = 1 if _win_holding(v, all_of) != null else 0
				hint = _binary_hint(v, all_of)
				text = hint if hint != "" else "not yet"
			"grafts_owned_at_win":
				need = maxi(1, int(v))
				for e in history:
					if bool(e["won"]):
						have = maxi(have, mini(e["grafts"].size(), need))
				text = "most grafts at a win %d/%d" % [have, need]
		parts.append({"key": k, "have": have, "need": need, "text": text})
	var head := {"key": "", "have": 0, "need": 1, "text": "not yet"}
	var best_f := 2.0
	for p in parts:
		var f := float(p["have"]) / float(p["need"])
		if f < best_f:
			best_f = f
			head = p
	var need_h := int(head["need"])
	if _owned(String(row.get("id", ""))):
		return {"have": need_h, "need": need_h, "done": true, "frac": 1.0, "key": String(head["key"]),
			"text": "done", "hint": hint, "parts": parts}
	var have_h := int(head["have"])
	return {"have": have_h, "need": need_h, "done": false, "frac": float(have_h) / float(need_h),
		"key": String(head["key"]), "text": String(head["text"]), "hint": hint, "parts": parts}


## What the history says about a binary goal: how close the runs that HELD
## the cards (won_with) or went WITHOUT them (wins_without) got. "" when no
## recorded run qualifies (legacy kit-less records never do).
func _binary_hint(ids: Array, all_of: bool) -> String:
	var n := 0
	var deepest := 0
	for e in history:
		if not bool(e.get("has_kit", true)):
			continue
		var hits := 0
		for id in ids:
			if _holds(e["kit"], String(id)):
				hits += 1
		if (all_of and hits == ids.size()) or (not all_of and hits == 0):
			n += 1
			deepest = maxi(deepest, int(e["floor"]))
	if n == 0:
		return ""
	if all_of:
		return "held it in %d run%s (best floor %d)" % [n, "" if n == 1 else "s", deepest]
	var names: Array = []
	for id in ids:
		names.append(_ability_name(String(id)))
	return "without %s: best floor %d in %d run%s" % [join_names(names), deepest, n, "" if n == 1 else "s"]


static func _ability_name(aid: String) -> String:
	if Content.ABILITIES.has(aid):
		return String(Content.ABILITIES[aid]["name"])
	return aid.replace("_", " ").capitalize()


## The next `n` goals, best first: [{desc, ids, names, have, need, frac, key,
## text, hint}]. Unowned milestones are grouped by their requires (in table
## order; the desc is the group's first row's), so the six rows behind "Shut
## down the Furnace" are ONE goal naming six unlocks. The next difficulty
## folds in where the predicate is the same: at tier 0 "tier:1" joins the
## one-win group, at tier 1 "tier:2" joins the one-tier-win group, and past
## that it is its own "Win at difficulty N" goal - so the ladder never lists
## a goal twice. Ranked by fraction done (descending), then GOAL_KEY_ORDER,
## then need, then table order. Pure: the same profile gives the same list.
func next_goals(n: int) -> Array:
	var groups := {}
	var order: Array = []
	for m in _milestones():
		var id := String(m["id"])
		if _owned(id):
			continue
		var gk := str(m.get("requires", {}))
		if not groups.has(gk):
			groups[gk] = {"desc": String(m.get("desc", "")), "ids": [], "row": m}
			order.append(gk)
		groups[gk]["ids"].append(id)
	var cands: Array = []
	var u := unlocked_tier
	var tier_id := "tier:%d" % (u + 1) if u < Content.TIERS.size() else ""
	for idx in order.size():
		var g: Dictionary = groups[order[idx]]
		var p := progress(g["row"])
		var ids: Array = g["ids"].duplicate()
		var gkey := String(p["key"])
		if tier_id != "" and int(p["need"]) - int(p["have"]) == 1 \
				and g["row"].get("requires", {}).size() == 1 \
				and ((u == 0 and gkey == "wins") or (u == 1 and gkey == "tier_wins")):
			ids.append(tier_id)
			tier_id = ""
		cands.append(_goal(String(g["desc"]), ids, p, idx))
	if tier_id != "" and u >= 1:
		cands.append(_goal("Win at difficulty %d" % u, [tier_id],
			{"have": 0, "need": 1, "frac": 0.0, "key": "tier_wins", "text": "not yet", "hint": ""}, 999))
	cands.sort_custom(func(a, b):
		for i in 4:
			if a["rank"][i] != b["rank"][i]:
				return a["rank"][i] < b["rank"][i]
		return false)
	var out: Array = []
	for c in cands.slice(0, n):
		c.erase("rank")
		out.append(c)
	return out


## Every milestone the way the CAREER sheet lists it, one entry per row (no
## grouping): the unowned rows first, ranked by the same key next_goals ranks
## its groups by ([-frac, GOAL_KEY_ORDER, need, table index]), then the owned
## rows in table order. -> [{id, row, p: progress(row), owned}]
func goal_rows() -> Array:
	var open: Array = []
	var owned: Array = []
	var idx := 0
	for m in _milestones():
		var id := String(m["id"])
		var pr := progress(m)
		var e := {"id": id, "row": m, "p": pr, "owned": _owned(id),
			"rank": [-float(pr["frac"]), GOAL_KEY_ORDER.find(String(pr["key"])), int(pr["need"]), idx]}
		idx += 1
		if e["owned"]:
			owned.append(e)
		else:
			open.append(e)
	open.sort_custom(func(a, b):
		for i in 4:
			if a["rank"][i] != b["rank"][i]:
				return a["rank"][i] < b["rank"][i]
		return false)
	var out: Array = []
	for e in open + owned:
		e.erase("rank")
		out.append(e)
	return out


static func _goal(desc: String, ids: Array, p: Dictionary, idx: int) -> Dictionary:
	var names: Array = []
	for id in ids:
		names.append(unlock_name(String(id)))
	var frac := float(p["frac"])
	return {"desc": desc, "ids": ids, "names": names, "have": int(p["have"]), "need": int(p["need"]),
		"frac": frac, "key": String(p["key"]), "text": String(p["text"]), "hint": String(p["hint"]),
		"rank": [-frac, GOAL_KEY_ORDER.find(String(p["key"])), int(p["need"]), idx]}


# --- display helpers (static, pure) ---------------------------------------------

## What an unlock id is: "tier" / "feat" by prefix, else the MILESTONES row's
## kind, else by table membership; "" when it is nothing at all.
static func unlock_kind(id: String) -> String:
	if id.begins_with("tier:"):
		return "tier"
	if id.begins_with("feat:"):
		return "feat"
	for m in Content.MILESTONES:
		if String(m["id"]) == id:
			return String(m.get("kind", ""))
	if Content.PACKAGES.has(id):
		return "package"
	if Content.MUTATORS.has(id):
		return "mutator"
	if Content.LOADOUTS.has(id):
		return "loadout"
	if Content.GRAFTS.has(id):
		return "graft"
	return ""


## The player-facing name of an unlock id - never the raw id: "tier:2" ->
## "difficulty 2", a package -> its Content.PACKAGE_INFO name, a loadout,
## mutator or graft -> its table's name ("double_oil" -> "Slick Combine"),
## "feat:x" -> Content.FEATS[x].name.
static func unlock_name(id: String) -> String:
	if id.begins_with("tier:"):
		return "difficulty %s" % id.substr(5)
	if id.begins_with("feat:"):
		var fid := id.substr(5)
		if Content.FEATS.has(fid):
			return String(Content.FEATS[fid]["name"])
		return fid.replace("_", " ").capitalize()
	if Content.PACKAGE_INFO.has(id):
		return String(Content.PACKAGE_INFO[id]["name"])
	for table in [Content.LOADOUTS, Content.MUTATORS, Content.GRAFTS]:
		if table.has(id):
			return String(table[id]["name"])
	return id.replace("_", " ").capitalize()


## "A", "A and B", or "A, B and 3 more" (at most `max_names` named).
static func join_names(names: Array, max_names := 2) -> String:
	if names.is_empty():
		return ""
	if names.size() == 1:
		return String(names[0])
	if names.size() == 2 and max_names >= 2:
		return "%s and %s" % [names[0], names[1]]
	var shown: Array = []
	for i in mini(maxi(1, max_names), names.size()):
		shown.append(String(names[i]))
	var rest := names.size() - shown.size()
	if rest == 0:
		var last := String(shown.pop_back())
		return "%s and %s" % [", ".join(shown), last]
	return "%s and %d more" % [", ".join(shown), rest]


## "" when loadout `lid` can be played with `unlocked_packages`, else the name
## of the first package it still needs ("Skyrunner (needs Aeolian)").
static func gate_of(lid: String, unlocked_packages: Array) -> String:
	if not Content.LOADOUTS.has(lid):
		return ""
	for pkg in Content.LOADOUTS[lid]["requires"].get("packages", []):
		if not unlocked_packages.has(pkg):
			return unlock_name(String(pkg))
	return ""


# --- NEW badges -------------------------------------------------------------------

## The player looked at `id` (cycled onto it in the menu): drop it from
## `unseen`. True when it was there, so the caller saves only on a change.
func mark_seen(id: String) -> bool:
	if not unseen.has(id):
		return false
	unseen.erase(id)
	return true


## The unseen ids of one kind ("tier", "package", "mutator", "loadout",
## "feat"), oldest first. A loadout counts only once it is PLAYABLE
## (available_loadouts), so a Skyrunner still waiting on Aeolian earns no
## badge until the package opens it.
func unseen_of(kind: String) -> Array:
	var out: Array = []
	var avail: Array = available_loadouts() if kind == "loadout" else []
	for id in unseen:
		if unlock_kind(String(id)) != kind:
			continue
		if kind == "loadout" and not avail.has(id):
			continue
		out.append(id)
	return out


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
		"daily_first": _sorted(daily_first.duplicate(true)),
		"daily_tries": _sorted(daily_tries),
		"unseen": unseen.duplicate(),
		"records": {
			"best": _sorted(records["best"].duplicate(true)),
			"loadouts": _sorted(records["loadouts"].duplicate(true)),
			"score_v": int(records["score_v"]),
		},
		"feats": _sorted(feats.duplicate(true)),
		"totals": _sorted(totals),
		"bosses_beaten": bosses_beaten.duplicate(),
		"cast_ever": cast_ever.duplicate(),
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
	profile.runs = _as_int(data.get("runs"), 0)
	profile.wins = _as_int(data.get("wins"), 0)
	profile.tier_wins = _as_int(data.get("tier_wins"), 0)
	profile.best_floor = _as_int(data.get("best_floor"), 0)
	# the one unlock with no Content table to filter against: it is an INDEX
	# into Content.TIERS, so a profile written by a build with more tiers (or
	# kept while TIERS shrank) would hand the menu a tier that cannot be named
	profile.unlocked_tier = clampi(_as_int(data.get("unlocked_tier"), 0), 0, Content.TIERS.size())
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
			var cid := _migrate_ability_id(_as_str(aid))
			if cid != "":
				casts[Content.base_id(cid)] = _as_int(stored_casts[aid], 0)
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
	profile.daily_best = _load_daily(data.get("daily_best", {}))
	profile.daily_first = _load_daily(data.get("daily_first", {}))
	for k in profile.daily_best:  # pre-daily_first: the best stands in as ranked
		if not profile.daily_first.has(k):
			profile.daily_first[k] = profile.daily_best[k].duplicate()
	var tries: Dictionary = {}
	var stored_tries = data.get("daily_tries", {})
	if stored_tries is Dictionary:
		for k in stored_tries:
			var n := _as_int(stored_tries[k], -1)
			if _as_str(k).is_valid_int() and n > 0:
				tries[_as_str(k)] = n
	profile.daily_tries = tries
	profile.records = _load_records(data.get("records", {}))
	# the feat stores: ids filtered against Content.FEATS, keys against
	# FEAT_TOTAL_KEYS, kinds against the boss-trait rows and ids against the
	# live base abilities, every number through a type guard
	var fts: Dictionary = {}
	var stored_feats = data.get("feats", {})
	if stored_feats is Dictionary:
		for k in stored_feats:
			var fid := _as_str(k)
			var e = stored_feats[k]
			if Content.FEATS.has(fid) and e is Dictionary:
				fts[fid] = _feat_rec(_as_str(e.get("date")), maxi(0, _as_int(e.get("run"), 0)))
	profile.feats = fts
	var tots: Dictionary = {}
	var stored_totals = data.get("totals", {})
	if stored_totals is Dictionary:
		for k in stored_totals:
			var tk := _as_str(k)
			var n := _as_int(stored_totals[k], 0)
			if Content.FEAT_TOTAL_KEYS.has(tk) and n > 0:
				tots[tk] = n
	profile.totals = tots
	var bb: Array = []
	var stored_bb = data.get("bosses_beaten", [])
	if stored_bb is Array:
		for b in stored_bb:
			var kind := _as_str(b)
			if _is_boss(kind) and not bb.has(kind):
				bb.append(kind)
	profile.bosses_beaten = bb
	var ce: Array = []
	var stored_ce = data.get("cast_ever", [])
	if stored_ce is Array:
		for a in stored_ce:
			var base := Content.base_id(_migrate_ability_id(_as_str(a)))
			if base != "" and Content.ABILITIES.has(base) and not ce.has(base):
				ce.append(base)
	profile.cast_ever = ce
	# after the unlocks and feats are filtered: an unseen id must name
	# something this career owns NOW (a renamed milestone, a tier past
	# unlocked_tier or a feat not earned would badge a row with nothing new)
	var seen_ok: Array = []
	var stored_unseen = data.get("unseen", [])
	if stored_unseen is Array:
		for e in stored_unseen:
			var id := _as_str(e)
			if id == "" or seen_ok.has(id):
				continue
			if id.begins_with("tier:"):
				var t := id.substr(5)
				if t.is_valid_int() and int(t) >= 1 and int(t) <= profile.unlocked_tier:
					seen_ok.append(id)
			elif id.begins_with("feat:"):
				if profile.feats.has(id.substr(5)):
					seen_ok.append(id)
			elif profile._owned(id):
				seen_ok.append(id)
	profile.unseen = seen_ok
	return profile


## A saved daily_best / daily_first: keys are seeds (str of an int), each
## entry rebuilt through _daily_rec so a reload str()s like the original.
static func _load_daily(stored) -> Dictionary:
	var out: Dictionary = {}
	if not (stored is Dictionary):
		return out
	for k in stored:
		var v = stored[k]
		if v is Dictionary and _as_str(k).is_valid_int():
			out[_as_str(k)] = _daily_rec(v.get("won"), v.get("floor"), v.get("turns"), v.get("score"))
	return out


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
			if keep.has(str(k)) and e is Dictionary and _as_int(e.get("v"), 0) > 0:
				out["best"][str(k)] = _rec(_as_int(e.get("v"), 0), _as_int(e.get("run"), 0),
					_known_loadout(e.get("loadout", "")), _as_int(e.get("tier"), 0))
	var sl = stored.get("loadouts", {})
	if sl is Dictionary:
		for lid in sl:
			var r = sl[lid]
			if Content.LOADOUTS.has(str(lid)) and r is Dictionary:
				out["loadouts"][str(lid)] = _loadout_rec(_as_int(r.get("best_floor"), 0),
					_as_int(r.get("best_score"), 0), _as_int(r.get("best_tier_won"), -1),
					_as_int(r.get("runs"), 0), _as_int(r.get("wins"), 0))
	out["score_v"] = _as_int(stored.get("score_v"), 0)
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
		var mid := _migrate_ability_id(_as_str(id))
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
		var sid := _as_str(id)
		if sid != "" and known.has(sid):
			out.append(sid)
	return out


## Type-guarded reads for anything that came out of a JSON file or a summary
## dict: `int(null)`, `int([1])`, `bool(null)` and `String(null)` are runtime
## errors in GDScript, and a runtime error inside load_from returns null out of
## it - the brick case load_from exists to prevent. Each returns the default
## (or "") unless the value already has a usable type. JSON numbers are floats.
static func _as_int(v, default: int) -> int:
	if v is int or v is float:
		return int(v)
	return default


static func _as_bool(v, default: bool) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	return default


## "" for anything but a String or StringName (never str(null) == "<null>",
## which an id filter would then try to match).
static func _as_str(v) -> String:
	if v is String or v is StringName:
		return String(v)
	return ""


## The daily_best key for a seed: the ONE spelling record_daily writes and
## every reader (the shell's game-over sheet) must look up.
static func daily_key(seed_v) -> String:
	return str(_as_int(seed_v, 0))
