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
## result per daily seed in `daily_best` and records nothing else.

const Content := preload("res://sim/content.gd")

## Per-run records kept for the history predicates; older entries are dropped.
const HISTORY_MAX := 50

var runs := 0
var wins := 0
var tier_wins := 0
var best_floor := 0
var unlocked_tier := 0
var unlocked_packages: Array = []
var unlocked_mutators: Array = []
## Milestone buckets with no consumer yet (kinds "loadout" and "graft").
var unlocked_loadouts: Array = []
var unlocked_grafts: Array = []
## Compact per-run records {won, floor, tier, turns, seed, kit, grafts},
## newest last, at most HISTORY_MAX of them.
var history: Array = []
## Ability base id -> effective casts summed over every recorded run.
var casts_by_base: Dictionary = {}
## str(daily seed) -> best {won, floor, turns} for that day.
var daily_best: Dictionary = {}
## Test seam only: when non-empty, these rows stand in for Content.MILESTONES.
var milestone_rows: Array = []


## Record a finished run and return newly unlocked ids. `summary` is a
## `Game.run_summary()` dict; the legacy {won, floor, tier} shape still works
## (history then records an empty kit and no casts for that run).
func record_run(summary: Dictionary) -> Array:
	var entry := _compact(summary)
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
	return _claim()


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
		"kit": _known_ids(summary.get("kit", []), Content.ABILITIES),
		"grafts": _known_ids(summary.get("grafts", []), Content.GRAFTS),
		# a legacy {won, floor, tier} record carries no kit: it must never
		# satisfy a wins_without predicate by looking like an empty kit
		"has_kit": summary.has("kit"),
	}


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


## Does `kit` hold `want`? An exact id always counts; a "+" form also counts
## as its base ("solar_lance+" satisfies "solar_lance", but "seed_bomb+" is
## satisfied only by "seed_bomb+" itself).
static func _holds(kit: Array, want: String) -> bool:
	for aid in kit:
		var s := String(aid)
		if s == want or Content.base_id(s) == want:
			return true
	return false


## Config for the next run at the requested tier (clamped to what is unlocked).
func game_config(req_tier: int = 0, req_mutators: Array = []) -> Dictionary:
	var muts: Array = []
	for m in req_mutators:
		if unlocked_mutators.has(m):
			muts.append(m)
	return {
		"packages": unlocked_packages.duplicate(),
		"tier": clampi(req_tier, 0, unlocked_tier),
		"mutators": muts,
	}


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
	}


## `d` with its top-level keys in sorted order.
static func _sorted(d: Dictionary) -> Dictionary:
	var keys: Array = d.keys()
	keys.sort()
	var out: Dictionary = {}
	for k in keys:
		out[k] = d[k]
	return out


func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(to_dict()))
	f.close()


static func load_from(path: String):  # -> Profile (or fresh if missing)
	var profile = new()
	if not FileAccess.file_exists(path):
		return profile
	var f := FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data == null:
		return profile
	profile.runs = int(data.get("runs", 0))
	profile.wins = int(data.get("wins", 0))
	profile.tier_wins = int(data.get("tier_wins", 0))
	profile.best_floor = int(data.get("best_floor", 0))
	profile.unlocked_tier = int(data.get("unlocked_tier", 0))
	# renamed or removed content must never brick a saved career: every stored
	# id is filtered against the tables that exist right now.
	profile.unlocked_packages = _known_ids(data.get("unlocked_packages", []), Content.PACKAGES)
	profile.unlocked_mutators = _known_ids(data.get("unlocked_mutators", []), Content.MUTATORS)
	profile.unlocked_grafts = _known_ids(data.get("unlocked_grafts", []), Content.GRAFTS)
	profile.unlocked_loadouts = _known_ids(data.get("unlocked_loadouts", []), {})  # no Content.LOADOUTS yet
	var casts: Dictionary = {}
	var stored_casts = data.get("casts_by_base", {})
	if stored_casts is Dictionary:
		for aid in stored_casts:
			if Content.ABILITIES.has(String(aid)):
				casts[Content.base_id(String(aid))] = int(stored_casts[aid])
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
	return profile


## `ids` kept in order, dropping anything `known` (a Dictionary of valid ids)
## does not carry.
static func _known_ids(ids, known) -> Array:
	var out: Array = []
	if not (ids is Array):
		return out
	for id in ids:
		if known.has(String(id)):
			out.append(String(id))
	return out
