extends RefCounted
## Per-run statistics: ONE fold over a run's step events (fun pass). The shell
## feeds it after every step - in `_act` and in `_load_run`'s replay, so a
## resumed run rebuilds exactly the stats an uninterrupted one had - and every
## consumer reads it: the game-over sheet, the career records, and the per-step
## `ctx` the feedback layer turns into callouts. Nothing re-derives a kill
## count, a streak or a room clear anywhere else, so a callout and a recap can
## never disagree.
##
## Pure: no Node, no Time, no rng, never a sim mutation. It reads the events a
## step returned plus a few public fields of the game after it (bloom,
## total_turns, floor_num, over, player, enemies, map, `resonances()`), and
## those are all deterministic, so the same seed and action list fold to the
## same summary and the same ctx at every step (tests/test_meta.gd pins it).
##
## `Game.run_summary()` is untouched: the shell MERGES `summary()` into it,
## and the two key sets are disjoint by construction (tested).

const Content := preload("res://sim/content.gd")

## near_miss: past this many route steps "the stairs were 14 away" is no near-miss
const NEAR_STAIRS_MAX := 10
## near_miss: at most this many cleanses short of waking the stairs
const NEAR_QUOTA_MAX := 2
## near_miss: a win's lowest HP worth naming as a closest call
const NEAR_CLOSE_HP := 3

# --- public counters (read-only by convention; summary() returns them) -------
var kills := 0
var kills_by_kind := {}
var elites_killed := 0
var bosses_killed: Array = []
var best_multi_kill := 0
var best_kill_streak := 0
## the run's biggest single hit on an enemy; strict > keeps the first on a tie
var biggest_hit := {"amt": 0, "src": "", "target": "", "floor": 0}
## the run's lowest HP while alive: begin() seeds it with the start hp, and a
## step updates it whenever the tender is still standing after it - a WINNING
## step included, so a win taken at 1 HP on the final blow registers
var closest_call := {"hp": 0, "floor": 0}
var combos := 0
var combos_by := {"rider": 0, "hook": 0, "surge": 0, "collision": 0}
var rooms_bloomed := 0
var room_clears := 0
var floors_restored := 0
## floors left by a `descend` with no player `damage` event on them (a hit the
## shield absorbed whole emits no damage event, so it does not break this)
var floors_unhurt := 0
var bloom_earned := 0
var cleanses := 0
var damage_dealt := 0
var damage_taken := 0
var shield_absorbed := 0
var statuses_landed := 0
## resonance id -> {floor, turn} of the step it first lit (begin() checks too)
var resonance_first := {}
## what ended the run: the raw death cause, and the enemy kind behind it when
## there is one (spikes resolve through the step's strike target)
var killer := {"cause": "", "kind": ""}
## kills in the player turn that is still open
var open_turn_kills := 0
## consecutive CLOSED player turns with at least one kill
var streak_closed := 0
## the last feed's StepCtx (also its return value); {} before the first feed
var ctx: Dictionary = {}

# --- private fold state ------------------------------------------------------
var _last_bloom := 0
var _last_turns := 0
var _last_floor := 0
var _ppos := Vector2i(-1, -1)   # the tender's tile before the step being fed
var _floor_hurt := false
var _pos := {}                  # enemy id -> Vector2i, as of the last feed
var _kind := {}                 # enemy id -> kind, as of the last feed


## Seed the fold from a fresh (or freshly replayed-to-start) game.
func begin(game) -> void:
	_last_bloom = int(game.bloom)
	_last_turns = int(game.total_turns)
	_last_floor = int(game.floor_num)
	_ppos = game.player["pos"]
	_floor_hurt = false
	closest_call = {"hp": int(game.player["hp"]), "floor": int(game.floor_num)}
	_snap_enemies(game)
	_check_resonance(game)


## Fold one step's events. Returns the StepCtx and also stores it in `ctx`.
## The ctx is never saved, so its Vector2i values are fine:
##   step_kills       enemies that died this step
##   turn_kills       kills in the player turn this step belongs to, this step
##                    included; on a closing step, the closed turn's total
##   turn_kills_prev  the same count before this step (DOUBLE = crossing 2)
##   turn_closed      the turn ended: total_turns moved, the floor changed, or
##                    the game ended (a lethal enemy phase returns before
##                    total_turns moves, so "over" has to close it too)
##   kill_streak      consecutive turns with a kill; the open turn counts once
##                    it has one
##   room_cleared     this step's kills emptied the room the tender stood in
##   cleanse_gain     bloom this step's cleanse paid (0: none, or enemy oil)
##   bounty_gain      elite bounty this step
##   bloom_gain       bloom gained this step (never negative: a spend is not
##                    a loss)
##   big_hit          the new run-best hit set this step, else 0
##   res_new          resonance ids first lit this step
##   closest_call     a new run-low HP this step (tender still standing)
##   killed           [{id, kind, pos}] with last-known positions
func feed(game, events: Array) -> Dictionary:
	var step_kills := 0
	var turn_prev := open_turn_kills
	var cleanse_gain := 0
	var bounty_gain := 0
	var big_hit := 0
	var killed: Array = []
	var strike_id = null
	for ev in events:
		var t := String(ev.get("t", ""))
		match t:
			"damage":
				var amt := int(ev.get("amt", 0))
				var who := String(ev.get("who", ""))
				var src := String(ev.get("src", ""))
				if who == "player":
					damage_taken += amt
					_floor_hurt = true
				else:
					damage_dealt += amt
					if amt > int(biggest_hit["amt"]):
						biggest_hit = {"amt": amt, "src": src, "target": who, "floor": int(game.floor_num)}
						big_hit = amt
					if src.begins_with("collision:"):
						combos += 1
						combos_by["collision"] += 1
			"death":
				var k := String(ev.get("who", ""))
				var id = ev.get("id", -1)
				kills += 1
				step_kills += 1
				kills_by_kind[k] = int(kills_by_kind.get(k, 0)) + 1
				killed.append({"id": id, "kind": k, "pos": _pos.get(id, Vector2i(-9, -9))})
				if Content.ENEMIES.get(k, {}).get("traits", []).has("boss"):
					bosses_killed.append(k)
			"bounty":
				elites_killed += 1
				bounty_gain += Content.ELITE_BOUNTY
			"rider", "hook", "surge":
				combos += 1
				combos_by[t] += 1
			"status":
				statuses_landed += 1
			"shield_absorb":
				shield_absorbed += int(ev.get("amt", 0))
			"room_bloom":
				rooms_bloomed += 1
			"floor_restored":
				floors_restored += 1
			"cleanse":
				cleanses += 1
				# the event's "bloom" is the running TOTAL (sim/game.gd
				# _act_cleanse), so the gain is measured against the balance
				# before the step: nothing earlier in a cleanse step moves
				# bloom, and no hook can cleanse
				cleanse_gain = int(ev.get("bloom", 0)) - _last_bloom
			"descend":
				if not _floor_hurt:
					floors_unhurt += 1
				_floor_hurt = false
			"strike":
				strike_id = ev.get("id", null)
			"player_death":
				var cause := String(ev.get("cause", ""))
				var kind := ""
				if Content.ENEMIES.has(cause):
					kind = cause
				elif cause == "spikes" and strike_id != null:
					# _act_strike emits the strike before the spikes bite
					kind = String(_kind.get(strike_id, ""))
				killer = {"cause": cause, "kind": kind}
	# bloom earned is the step's DELTA, floored at 0, not a sum of event
	# fields: the cleanse event carries a running total, and a delta cannot
	# miss a bloom source the event list does not name (tests/tally.gd's rule)
	var gain := maxi(0, int(game.bloom) - _last_bloom)
	bloom_earned += gain
	_last_bloom = int(game.bloom)
	var floor_same := int(game.floor_num) == _last_floor
	var room_cleared := false
	if step_kills > 0 and not game.over and floor_same:
		room_cleared = _room_cleared(game, killed)
	if room_cleared:
		room_clears += 1
	open_turn_kills += step_kills
	var closed: bool = game.over or int(game.total_turns) != _last_turns or not floor_same
	var turn_kills := open_turn_kills
	var streak_now := streak_closed + (1 if open_turn_kills > 0 else 0)
	if closed:
		best_multi_kill = maxi(best_multi_kill, open_turn_kills)
		streak_closed = streak_closed + 1 if open_turn_kills > 0 else 0
		best_kill_streak = maxi(best_kill_streak, streak_closed)
		streak_now = streak_closed
		open_turn_kills = 0
	var new_close := false
	var hp := int(game.player["hp"])
	if hp > 0 and hp < int(closest_call["hp"]):
		closest_call = {"hp": hp, "floor": int(game.floor_num)}
		new_close = true
	var lit := _check_resonance(game)
	ctx = {
		"step_kills": step_kills, "turn_kills": turn_kills, "turn_kills_prev": turn_prev,
		"turn_closed": closed, "kill_streak": streak_now, "room_cleared": room_cleared,
		"cleanse_gain": cleanse_gain, "bounty_gain": bounty_gain, "bloom_gain": gain,
		"big_hit": big_hit, "res_new": lit, "closest_call": new_close, "killed": killed,
	}
	_last_turns = int(game.total_turns)
	_last_floor = int(game.floor_num)
	_ppos = game.player["pos"]
	_snap_enemies(game)
	return ctx


## The one room-clear rule. The room R is the map room (grown by 1 for its
## doorways, the shell's _room_view rule) holding the tender's tile BEFORE the
## step, else the one holding it after; in a corridor there is none. R is
## cleared when a body this step killed was last seen in it and no live enemy
## stands in it. The boss floor has no rooms, so it never clears one.
func _room_cleared(game, killed: Array) -> bool:
	var rooms: Array = game.map.get("rooms", [])
	var room = null
	for p in [_ppos, game.player["pos"]]:
		for r in rooms:
			var rr: Rect2i = Rect2i(r).grow(1)
			if rr.has_point(p):
				room = rr
				break
		if room != null:
			break
	if room == null:
		return false
	var dead_in := false
	for k in killed:
		if room.has_point(k["pos"]):
			dead_in = true
			break
	if not dead_in:
		return false
	for e in game.enemies:
		if room.has_point(e["pos"]):
			return false
	return true


func _snap_enemies(game) -> void:
	_pos = {}
	_kind = {}
	for e in game.enemies:
		_pos[e["id"]] = e["pos"]
		_kind[e["id"]] = e["kind"]


## Record any resonance that is lit for the first time; returns those ids.
## Reads the sim's own active set (Game.resonances()), never a re-derivation.
func _check_resonance(game) -> Array:
	var out: Array = []
	for rid in game.resonances():
		if not resonance_first.has(rid):
			resonance_first[rid] = {"floor": int(game.floor_num), "turn": int(game.total_turns)}
			out.append(String(rid))
	return out


## Every counter, JSON-safe and deep-copied. Carries the nested dicts AND the
## flat ints the career reads (`Content.RUN_STAT_KEYS`), so a feat or record
## never has to dig. No key collides with Game.run_summary()'s.
func summary() -> Dictionary:
	return {
		"kills": kills, "kills_by_kind": kills_by_kind.duplicate(),
		"elites_killed": elites_killed, "bosses_killed": bosses_killed.duplicate(),
		"best_multi_kill": best_multi_kill, "best_kill_streak": best_kill_streak,
		"biggest_hit": biggest_hit.duplicate(), "biggest_hit_amt": int(biggest_hit["amt"]),
		"closest_call": closest_call.duplicate(), "closest_hp": int(closest_call["hp"]),
		"combos": combos, "combos_by": combos_by.duplicate(),
		"rooms_bloomed": rooms_bloomed, "room_clears": room_clears,
		"floors_restored": floors_restored, "floors_unhurt": floors_unhurt,
		"bloom_earned": bloom_earned, "cleanses": cleanses,
		"damage_dealt": damage_dealt, "damage_taken": damage_taken,
		"shield_absorbed": shield_absorbed, "statuses_landed": statuses_landed,
		"resonance_first": resonance_first.duplicate(true), "resonances_lit": resonance_first.size(),
		"killer": killer.duplicate(),
	}


# --- statics: pure, data in and data out (the words live in the shell) ------

## The cosmetic run score of a merged summary (run_summary + summary() + the
## shell's tier): every Content.RUN_SCORE row in table order, `pts * value`
## (a bool counts 1/0), then each difficulty tier adds
## RUN_SCORE_TIER_QUARTERS quarters. Integer arithmetic throughout.
## -> {total, base, tier, quarters, parts: [[id, pts], ...]} (every row listed;
## the sheet prints the non-zero ones)
static func score(s: Dictionary) -> Dictionary:
	var parts: Array = []
	var base := 0
	for row in Content.RUN_SCORE:
		var v = s.get(String(row["key"]), 0)
		var n := 0
		if v is bool:
			n = 1 if v else 0
		elif v is int or v is float:
			n = int(v)
		var pts := int(row["pts"]) * n
		parts.append([String(row["id"]), pts])
		base += pts
	var tier := maxi(0, int(s.get("tier", 0)))
	var quarters := 4 + tier * Content.RUN_SCORE_TIER_QUARTERS
	return {"total": base * quarters / 4, "base": base, "tier": tier, "quarters": quarters, "parts": parts}


## How close a finished run came: the first matching rule wins.
## A win: {kind: "closest_call", hp, floor} when it dipped to NEAR_CLOSE_HP or
## lower, else {kind: ""}. A death:
##   1 boss_hp    {boss, hp}   the floor has a boss and it is still standing
##   2 stairs     {steps}      the stairs were awake and <= NEAR_STAIRS_MAX route
##                             steps away (BFS over floor tiles, blocking
##                             terrain excluded, enemies ignored)
##   3 quota      {short}      1..NEAR_QUOTA_MAX cleanses short of waking them
##   4 best_short {best}       one floor short of the career's deepest
##   5 best_level {best}       died on the career's deepest floor
##   6 exact                   killed at exactly 0 HP by anything but smog
##                             (smog chips 1, so every smog death is exact)
##   7 ""                      nothing to say
## `snap` is the final Game.snapshot(); `prev_best_floor` the career's (or the
## daily's) best BEFORE this run.
static func near_miss(snap: Dictionary, s: Dictionary, prev_best_floor: int) -> Dictionary:
	if bool(snap.get("won", false)):
		var cc: Dictionary = s.get("closest_call", {})
		var chp := int(cc.get("hp", NEAR_CLOSE_HP + 1))
		if chp <= NEAR_CLOSE_HP:
			return {"kind": "closest_call", "hp": chp, "floor": int(cc.get("floor", 0))}
		return {"kind": ""}
	var floor_n := int(snap.get("floor", 0))
	var fdef: Dictionary = Content.FLOORS[floor_n - 1] if floor_n >= 1 and floor_n <= Content.FLOORS.size() else {}
	if bool(fdef.get("boss", false)):
		for e in snap.get("enemies", []):
			var kind := String(e.get("kind", ""))
			if Content.ENEMIES.get(kind, {}).get("traits", []).has("boss"):
				return {"kind": "boss_hp", "boss": kind, "hp": int(e.get("hp", 0))}
	var need := int(snap.get("green_need", 0))
	var have := int(snap.get("greened", 0))
	if need > 0 and have >= need:
		var d := _route_steps(snap)
		if d >= 0 and d <= NEAR_STAIRS_MAX:
			return {"kind": "stairs", "steps": d}
	if need - have > 0 and need - have <= NEAR_QUOTA_MAX:
		return {"kind": "quota", "short": need - have}
	if prev_best_floor >= 2 and floor_n == prev_best_floor - 1:
		return {"kind": "best_short", "best": prev_best_floor}
	if prev_best_floor >= 2 and floor_n == prev_best_floor:
		return {"kind": "best_level", "best": prev_best_floor}
	var player: Dictionary = snap.get("player", {})
	if String(snap.get("death_cause", "")) != "smog" and int(player.get("hp", -1)) == 0:
		return {"kind": "exact"}
	return {"kind": ""}


## BFS route length from the tender to the stairs over floor tiles, minus
## terrain whose Content.TERRAIN row blocks; enemies are ignored. -1 when the
## stairs cannot be reached.
static func _route_steps(snap: Dictionary) -> int:
	var m: Dictionary = snap.get("map", {})
	var w := int(m.get("w", 0))
	var h := int(m.get("h", 0))
	var tiles: Array = Array(m.get("tiles", []))
	var terr: Dictionary = snap.get("terrain", {})
	var start: Vector2i = snap.get("player", {}).get("pos", Vector2i(-1, -1))
	var goal: Vector2i = m.get("stairs", Vector2i(-1, -1))
	if w <= 0 or h <= 0 or tiles.size() < w * h:
		return -1
	var dist := {start: 0}
	var q: Array = [start]
	var qi := 0
	while qi < q.size():
		var p: Vector2i = q[qi]
		qi += 1
		if p == goal:
			return int(dist[p])
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = p + d
			if dist.has(n) or n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			if int(tiles[n.y * w + n.x]) != 1:
				continue
			if terr.has(n) and bool(Content.terrain(String(terr[n].get("kind", "")), "blocks", false)):
				continue
			dist[n] = int(dist[p]) + 1
			q.append(n)
	return -1


## Up to `max_n` highlight chips for the game-over sheet, in priority order,
## one per id. `new_records` is the profile's last_report.records (records this
## run beat); its first entry is a candidate right after the resonance chip.
## Each entry is data ({id, ...}); shell/run_end.gd words it.
static func highlights(s: Dictionary, max_n := 3, new_records: Array = []) -> Array:
	var cands: Array = []
	var restored := int(s.get("floors_restored", 0))
	var multi := int(s.get("best_multi_kill", 0))
	var bh: Dictionary = s.get("biggest_hit", {})
	var hit := int(bh.get("amt", 0))
	var streak := int(s.get("best_kill_streak", 0))
	var rooms := int(s.get("rooms_bloomed", 0))
	var combos_n := int(s.get("combos", 0))
	var elites := int(s.get("elites_killed", 0))
	var big := {"id": "big_hit", "n": hit, "src": String(bh.get("src", "")), "target": String(bh.get("target", ""))}
	if restored >= 1:
		cands.append({"id": "restored", "n": restored})
	var first: Dictionary = s.get("resonance_first", {})
	for rid in Content.RESONANCES:
		if first.has(rid):
			cands.append({"id": "resonance", "rid": String(rid), "floor": int(first[rid].get("floor", 0))})
			break
	if not new_records.is_empty() and new_records[0] is Dictionary:
		var r: Dictionary = new_records[0]
		cands.append({"id": "record", "key": String(r.get("key", "")), "v": int(r.get("v", 0)),
			"was": int(r.get("was", 0))})
	if multi >= 3:
		cands.append({"id": "multi", "n": multi})
	if hit >= 5:
		cands.append(big)
	if streak >= 4:
		cands.append({"id": "streak", "n": streak})
	if rooms >= 5:
		cands.append({"id": "rooms", "n": rooms})
	if combos_n >= 10:
		cands.append({"id": "combos", "n": combos_n})
	if elites >= 2:
		cands.append({"id": "elites", "n": elites})
	if multi == 2:
		cands.append({"id": "multi", "n": multi})
	if hit >= 3:
		cands.append(big)
	if rooms >= 1:
		cands.append({"id": "rooms", "n": rooms})
	if combos_n >= 1:
		cands.append({"id": "combos", "n": combos_n})
	if int(s.get("kills", 0)) >= 1:
		cands.append({"id": "kills", "n": int(s.get("kills", 0))})
	if int(s.get("cleanses", 0)) >= 1:
		cands.append({"id": "cleanses", "n": int(s.get("cleanses", 0))})
	var out: Array = []
	var seen := {}
	for c in cands:
		if out.size() >= max_n:
			break
		if seen.has(c["id"]):
			continue
		seen[c["id"]] = true
		out.append(c)
	return out
