extends RefCounted
## The end of a run in words (fun pass). Static functions only: no Node, no
## font, no game state - each takes the merged run summary (Game.run_summary()
## + RunStats.summary(), stamped with `score`), the final snapshot or a piece
## of the profile's report, and returns the string the game-over sheet and
## the end-of-run beat draw. Kept apart from shell/main.gd so every sentence
## is testable without a Shell. Names come from shell/names.gd, the one names
## module; unlock names from meta/profile.gd's display helpers.
##
## "·" (U+00B7) is the separator the rest of the shell already uses; a
## two-space pad each side keeps the parts apart on a phone.

const Content := preload("res://sim/content.gd")
const Names := preload("res://shell/names.gd")
const Profile := preload("res://meta/profile.gd")

const SEP := "  ·  "


## The floor's display name ("Pipeworks"); "" off the table.
static func floor_name(n: int) -> String:
	if n >= 1 and n <= Content.FLOORS.size():
		return String(Content.FLOORS[n - 1].get("name", ""))
	return ""


## Is `id` a graft or a resonance (the two sources a player owns)?
static func _own_source(id: String) -> bool:
	return Content.GRAFTS.has(id) or Content.RESONANCES.has(id)


## What ended the run: the folded killer's cause, else the summary's
## death_cause. RunStats.summary() always carries killer.cause ("" when no
## player_death was folded - a game set over from outside), so a plain
## .get(key, fallback) would never reach the fallback.
static func _cause_of(s: Dictionary) -> String:
	var killer = s.get("killer", {})
	var cause := String(killer.get("cause", "")) if killer is Dictionary else ""
	return cause if cause != "" else String(s.get("death_cause", ""))


## The end-of-run beat's two lines, drawn over the map before the sheet:
## [line0 (the moment), line1 (what it was)]. A lost run wilts - the tender
## rests, it is never killed off - and line 1 says what ended it.
static func end_banner(s: Dictionary, snap: Dictionary) -> Array:
	if bool(s.get("won", snap.get("won", false))):
		return ["THE FURNACE IS COLD", "the valley breathes again"]
	var killer = s.get("killer", {})
	var kk := String(killer.get("kind", "")) if killer is Dictionary else ""
	return ["YOU WILTED", cause_text(_cause_of(s), kk)]


## How the run ended, in a few gentle words, mid-sentence: "felled by a
## Drill Bot", "lost in the smog" - what felled the tender, never a raw id. A
## qualified source ("fire:solar_lance") reads as its bare source.
static func cause_text(cause: String, killer_kind: String = "") -> String:
	var base := cause.get_slice(":", 0)
	if Content.ENEMIES.has(base):
		return "felled by " + Names.a_name(base)
	match base:
		"smog":
			return "lost in the smog"
		"fire":
			return "caught in the fire"
		"goo", "rich_goo":
			return "stuck in the goo"
		"spikes":
			if Content.ENEMIES.has(killer_kind):
				return "worn down by %s's spikes" % Names.a_name(killer_kind)
			return "worn down by spikes"
		"":
			return "the light went out"
	if _own_source(base):
		return "caught by your own " + Names.source_name(base)
	return "felled by " + Names.src_name(base)


## The sheet's second line: the boss you scrapped, or what killed you and where.
static func cause_line(s: Dictionary, snap: Dictionary) -> String:
	if bool(s.get("won", snap.get("won", false))):
		var bosses: Array = s.get("bosses_killed", [])
		if bosses.is_empty():
			return "the valley breathes again"
		return "%s is scrap%sthe valley breathes again" % [Names.boss_name(String(bosses.back())), SEP]
	var killer: Dictionary = s.get("killer", {})
	var cause := _cause_of(s)
	var where := floor_name(int(s.get("floor", snap.get("floor", 0))))
	var t := cause_text(cause, String(killer.get("kind", "")))
	return t if where == "" else t + SEP + where


## RunStats.near_miss in words; "" when there is nothing to say.
static func near_miss_text(nm: Dictionary) -> String:
	match String(nm.get("kind", "")):
		"boss_hp":
			return "%s had %d HP left" % [Names.boss_name(String(nm.get("boss", ""))), int(nm.get("hp", 0))]
		"stairs":
			var d := int(nm.get("steps", 0))
			if d <= 0:
				return "you fell on the open stairs"
			return "the stairs were 1 step away" if d == 1 else "the stairs were %d steps away" % d
		"quota":
			var n := int(nm.get("short", 0))
			return "1 cleanse short of waking the stairs" if n == 1 else "%d cleanses short of waking the stairs" % n
		"best_short":
			return "one floor short of your best (floor %d)" % int(nm.get("best", 0))
		"best_level":
			return "level with your best floor (%d)" % int(nm.get("best", 0))
		"exact":
			return "1 more HP would have saved you"
		"closest_call":
			var fn := floor_name(int(nm.get("floor", 0)))
			return "closest call: %d HP%s" % [int(nm.get("hp", 0)), (" on " + fn) if fn != "" else ""]
	return ""


## "floor 5 of 7  ·  63 turns  ·  24 kills  ·  41 bloom earned" - the run's
## TOTAL turns (run_summary().turns), never the floor's turn counter.
static func stats_line(s: Dictionary) -> String:
	var t := int(s.get("turns", 0))
	var k := int(s.get("kills", 0))
	return "floor %d of %d%s%s%s%s%s%d bloom earned" % [int(s.get("floor", 0)), Content.FLOORS.size(), SEP,
		"1 turn" if t == 1 else "%d turns" % t, SEP,
		"1 kill" if k == 1 else "%d kills" % k, SEP, int(s.get("bloom_earned", 0))]


## "grafts  Compost · Ember Sap", or "" when the run held none.
static func grafts_line(s: Dictionary) -> String:
	var names: Array = []
	for g in s.get("grafts", []):
		names.append(String(Content.GRAFTS.get(String(g), {}).get("name", String(g).replace("_", " "))))
	if names.is_empty():
		return ""
	return "grafts  " + " · ".join(names)


## The label a record key carries (Profile.RECORD_SHOW), lower-cased.
static func _record_label(key: String) -> String:
	for row in Profile.RECORD_SHOW:
		if String(row[0]) == key:
			return String(row[1]).to_lower()
	return key.replace("_", " ")


## One highlight chip (RunStats.highlights entry) in words.
static func chip_text(h: Dictionary) -> String:
	var n := int(h.get("n", 0))
	match String(h.get("id", "")):
		"restored":
			return "floor restored" if n == 1 else "%d floors restored" % n
		"resonance":
			return "%s lit on floor %d" % [Names.source_name(String(h.get("rid", ""))), int(h.get("floor", 0))]
		"record":
			var key := String(h.get("key", ""))
			var unit := " turns" if key == "fastest_win" else ""
			return "record%s%s %d%s (was %d)" % [SEP, _record_label(key), int(h.get("v", 0)), unit, int(h.get("was", 0))]
		"multi":
			return "double kill" if n == 2 else "%d kills in one turn" % n
		"big_hit":
			var src := Names.src_long(String(h.get("src", "")))
			return "biggest hit %d%s" % [n, (SEP + src) if src != "" else ""]
		"streak":
			return "%d-turn kill streak" % n
		"rooms":
			return "1 room bloomed" if n == 1 else "%d rooms bloomed" % n
		"combos":
			return "1 combo" if n == 1 else "%d combos" % n
		"elites":
			return "%d elites scrapped" % n
		"kills":
			return "1 machine scrapped" if n == 1 else "%d machines scrapped" % n
		"cleanses":
			return "1 tile cleansed" if n == 1 else "%d tiles cleansed" % n
	return ""


## "SCORE 1234" (a plain int: no locale separators).
static func score_title(sc: Dictionary) -> String:
	return "SCORE %d" % int(sc.get("total", 0))


## Every non-zero part of the score, so the number is never a mystery:
## "floor 500  ·  kills 120  ·  bloom 82", then the difficulty multiplier.
static func score_parts_text(sc: Dictionary) -> String:
	var parts: Array = []
	for p in sc.get("parts", []):
		if int(p[1]) != 0:
			parts.append("%s %d" % [String(p[0]), int(p[1])])
	var tier := int(sc.get("tier", 0))
	if tier > 0:
		parts.append("x%s difficulty %d" % [String.num(int(sc.get("quarters", 4)) / 4.0, 2), tier])
	return SEP.join(parts)


## A daily result in words: "a win in 63 turns" or "floor 4".
static func daily_desc(rec: Dictionary) -> String:
	if bool(rec.get("won", false)):
		return "a win in %d turns" % int(rec.get("turns", 0))
	return "floor %d" % int(rec.get("floor", 0))


## The line under the score: [text, gold]. `prev` is what the shell took
## BEFORE recording (profile.bests_snapshot, or {"daily": that seed's best});
## empty for a run that was never recorded (tutorial, a bare game). The daily
## arm reads profile.record_daily's report.
static func best_line(s: Dictionary, prev: Dictionary, daily: bool, daily_report: Dictionary = {}) -> Array:
	if prev.is_empty():
		return ["", false]
	if daily:
		var was: Dictionary = prev.get("daily", {})
		if bool(daily_report.get("ranked", false)) or was.is_empty():
			return ["RANKED%syour first finish today" % SEP, true]
		if bool(daily_report.get("new_best", false)):
			return ["NEW DAILY BEST%swas %s" % [SEP, daily_desc(was)], true]
		var tries := int(daily_report.get("tries", 0))
		var tail := ""
		if tries > 0:
			tail = SEP + ("1 try" if tries == 1 else "%d tries" % tries)
		return ["today's best: %s%s" % [daily_desc(was), tail], false]
	var score := int(s.get("score", 0))
	var best := int(prev.get("best_score", 0))
	if best <= 0:
		return ["your first score%sbeat it next run" % SEP, true]
	if score > best:
		return ["NEW BEST%swas %d" % [SEP, best], true]
	var lbest := int(prev.get("best_score_loadout", 0))
	if lbest > 0 and score > lbest:
		var lid := String(prev.get("loadout", s.get("loadout", "")))
		var lname := String(Content.LOADOUTS.get(lid, {}).get("name", lid)).to_upper()
		return ["NEW BEST FOR %s%swas %d" % [lname, SEP, lbest], true]
	return ["best %d%sthis run %d%%" % [best, SEP, score * 100 / best], false]


## YOUR FIRST WIN / DEEPEST YET, against the bests BEFORE this run (career only).
static func floor_best_line(s: Dictionary, prev: Dictionary, daily: bool) -> String:
	if daily or prev.is_empty():
		return ""
	if bool(s.get("won", false)) and int(prev.get("wins", 0)) == 0:
		return "YOUR FIRST WIN"
	var f := int(s.get("floor", 0))
	var was := int(prev.get("best_floor", 0))
	if int(prev.get("runs", 0)) > 0 and f > was:
		return "DEEPEST YET%sfloor %d (was %d)" % [SEP, f, was]
	return ""


## One unlock in words: what kind of thing opened, and its name.
static func unlock_label(id: String, unlocked_packages: Array) -> String:
	match Profile.unlock_kind(id):
		"tier":
			var n := int(id.substr(5))
			var tname := String(Content.TIERS[n - 1]["name"]) if n >= 1 and n <= Content.TIERS.size() else "difficulty %d" % n
			return "NEW DIFFICULTY%s%s" % [SEP, tname]
		"loadout":
			var gate := Profile.gate_of(id, unlocked_packages)
			if gate != "":
				return "UNLOCKED%s%s loadout (needs %s)" % [SEP, Profile.unlock_name(id), gate]
			return "UNLOCKED%s%s loadout" % [SEP, Profile.unlock_name(id)]
		"package":
			return "UNLOCKED%s%s package" % [SEP, Profile.unlock_name(id)]
		"mutator":
			return "UNLOCKED%s%s mutator" % [SEP, Profile.unlock_name(id)]
		"graft":
			return "UNLOCKED%s%s graft" % [SEP, Profile.unlock_name(id)]
		"feat":
			return "FEAT%s%s" % [SEP, Profile.unlock_name(id)]
	return "UNLOCKED%s%s" % [SEP, Profile.unlock_name(id)]


## The first `max_n` unlock labels, then "+n more  ·  tap for all" when there
## are more: the unlock rows are the tap target that opens the pager (every
## unlock and feat as a card, main._draw_unlocks).
static func unlock_lines(ids: Array, unlocked_packages: Array, max_n := 3) -> Array:
	var out: Array = []
	for i in mini(max_n, ids.size()):
		out.append(unlock_label(String(ids[i]), unlocked_packages))
	if ids.size() > max_n:
		out.append(unlock_more(ids.size() - max_n))
	return out


## The overflow row under the unlock lines: "+2 more  ·  tap for all". The
## sheet rebuilds it from the rows it actually kept after its priority drop.
static func unlock_more(n: int) -> String:
	return "+%d more%stap for all" % [n, SEP]


## The next goal (profile.last_report.next[0]: a next_goals row plus
## "delta"): "NEXT  ·  Land 30 Grow Spikes  ·  17/30 (+9 this run)  ·
## unlocks Wide Draft". Numbers only when the goal needs more than one of
## something; a feat goal names the feat instead of what it unlocks.
static func next_goal_text(goal: Dictionary) -> String:
	if goal.is_empty():
		return ""
	var out := "NEXT" + SEP + String(goal.get("desc", ""))
	var need := int(goal.get("need", 0))
	if need > 1:
		out += "%s%d/%d" % [SEP, int(goal.get("have", 0)), need]
		var delta := int(goal.get("delta", 0))
		if delta > 0:
			out += " (+%d this run)" % delta
	var ids: Array = goal.get("ids", [])
	var names: Array = goal.get("names", [])
	if not ids.is_empty() and String(ids[0]).begins_with("feat:"):
		out += "%sfeat %s" % [SEP, String(names[0]) if not names.is_empty() else Profile.unlock_name(String(ids[0]))]
	elif not names.is_empty():
		out += "%sunlocks %s" % [SEP, Profile.join_names(names, 2)]
	return out


## "seed 123456  ·  Tender · Mycology", plus the difficulty and "daily".
static func seed_line(seed_v: int, s: Dictionary, daily: bool, config_line: String) -> String:
	var out := "seed %d" % seed_v
	if config_line != "":
		out += SEP + config_line
	var t := int(s.get("tier", 0))
	if t > 0:
		out += "%sdifficulty %d" % [SEP, t]
	if daily:
		out += SEP + "daily"
	return out
