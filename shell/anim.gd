extends RefCounted
## Step animation director (docs/SHELL.md "Animations"). The sim resolves a
## step() instantly; this turns what that step DID into a short timed reel the
## shell plays back, so a cast reads as a cast and an enemy turn reads as each
## machine taking its turn in order.
##
##   Anim.plan(pre, action, events, post, speed) -> reel
##
## `pre` / `post` are Game.snapshot() before and after the step, `events` the
## step's return value. The director is PURE: it never touches the Game
## object, the clock or the scene tree, never mutates its inputs, and the same
## inputs always plan the same reel - so tests/test_anim.gd asserts on it
## headless, and the sim stays unaware that anything animates (style guide
## §4). Nothing here decides a rule: every position a reel ENDS on is the
## position the post snapshot holds.
##
## Structure: a planner per action kind assigns each event a time (and, for a
## hit, a direction) and lays down the verb's own clips and motion segments;
## ability effects are built op by op by the verb family that owns the op
## (shell/fx_lines.gd, fx_areas.gd, fx_self.gd) and enemy intents by
## shell/fx_enemy.gd. A generic pass then turns every event into its standard
## feedback (damage numbers, hit flashes, recoil, deaths, spawns) at the time
## it was given. `tests/test_anim.gd` fails when an effect op or an intent
## type has no builder, the same way the content lint fails on an unknown op.

const Content := preload("res://sim/content.gd")
const L := preload("res://shell/anim_lib.gd")
const FxLines := preload("res://shell/fx_lines.gd")
const FxAreas := preload("res://shell/fx_areas.gd")
const FxSelf := preload("res://shell/fx_self.gd")
const FxEnemy := preload("res://shell/fx_enemy.gd")

## Ability-op families, scanned in order for the builder that owns an op.
const OP_FAMILIES := [FxLines, FxAreas, FxSelf]

## Speed presets for the ANIMATION setting: a multiplier on every reel time.
## "off" keeps only the information (damage numbers), at t = 0.
const SPEEDS := {"full": 1.0, "quick": 0.55, "off": 0.0}

## Events that belong to the environment phase of an end_turn (after every
## enemy acted): hazards, the smog clock, vents, the next turn's regen.
const ENV_TYPES := ["smog_dim", "choke", "seal_burst", "reinforcement", "vents_clogged",
	"heal", "ash", "item_pickup", "satchel_full", "quota_reclamp"]
## Events that are a consequence of the event right before them in the stream.
const FOLLOW_TYPES := ["death", "split", "bounty", "smoke_burst", "boss_phase", "win", "hook",
	"hook_capped", "status", "resisted", "immune", "staggered", "core_shielded", "player_death",
	"rider", "stairs_awaken", "floor_restored", "room_bloom", "quota_reclamp"]
## Pseudo-intents fx_enemy handles for an enemy whose intent never ran.
const BLOCKED_VERB := "blocked"
const SCREENED_VERB := "screened"


# --- planning ------------------------------------------------------------------

static func empty_reel() -> Dictionary:
	return {"clips": [], "tracks": {}, "ghosts": [], "spawns": {}, "shakes": [], "tswap": {}, "hp": {}, "len": 0}


static func plan(pre: Dictionary, action: Dictionary, events: Array, post: Dictionary, speed: float = 1.0) -> Dictionary:
	var reel := empty_reel()
	if pre.is_empty() or post.is_empty() or not pre.has("player") or not post.has("player"):
		return reel
	if int(pre.get("floor", 0)) != int(post.get("floor", 0)):
		return reel  # a descent: the floor fade-in is the animation
	var c := ctx(pre, action, events, post, reel)
	var t_end := 0
	match String(action.get("type", "")):
		"move":
			t_end = _plan_move(c)
		"strike":
			t_end = _plan_strike(c)
		"ability":
			t_end = _plan_ability(c)
		"cleanse":
			t_end = _plan_cleanse(c)
		"use_item":
			t_end = _plan_item(c)
		"end_turn":
			t_end = _plan_enemy_phase(c)
		_:
			t_end = 0
	_feedback(c, t_end)
	_ghosts_and_spawns(c, t_end)
	_reveals(c, t_end)
	reel["len"] = _length(reel)
	if speed != 1.0:
		_scale(reel, speed)
	return reel


## The build context every planner and verb builder shares.
static func ctx(pre: Dictionary, action: Dictionary, events: Array, post: Dictionary, reel: Dictionary) -> Dictionary:
	var n := events.size()
	var times: Array = []
	var dirs: Array = []
	var quiet: Array = []
	times.resize(n)
	dirs.resize(n)
	quiet.resize(n)
	for i in n:
		times[i] = -1
		dirs[i] = null
		quiet[i] = false
	var pre_en := {}
	for e in pre["enemies"]:
		pre_en[e["id"]] = e
	var post_en := {}
	for e in post["enemies"]:
		post_en[e["id"]] = e
	# every tile whose terrain kind differs between the boards; builders say
	# when each flips (L.reveal), the rest flip at the step's natural moment
	var tswap := {}
	for p in pre["terrain"].keys():
		var a := L.tkind(pre, p)
		var b := L.tkind(post, p)
		if a != b:
			tswap[p] = {"pre": a, "post": b}
	for p in post["terrain"].keys():
		if not pre["terrain"].has(p):
			tswap[p] = {"pre": "", "post": L.tkind(post, p)}
	reel["tswap"] = tswap
	var p0: Vector2i = pre["player"]["pos"]
	return {
		"pre": pre, "post": post, "action": action, "events": events, "reel": reel,
		"times": times, "dirs": dirs, "quiet": quiet, "t": 0, "ev0": 0, "ev1": n,
		"pre_en": pre_en, "post_en": post_en, "p0": p0, "p1": post["player"]["pos"],
		"ppos": p0, "pal": L.PAL_DEFAULT, "aid": "", "adef": {}, "eff": {},
		"target": action.get("target"), "hit": L.T_HIT,
	}


static func _plan_move(c: Dictionary) -> int:
	var mv = L.moved(c, "player")
	if mv != null:
		L.move(c, "player", [mv[0], mv[1]], 0, L.T_MOVE, 0.16)
		L.seg(c, "player", {"kind": "squash", "t0": L.T_MOVE - 20, "dur": 120})
	for i in L.unclaimed(c, ["move"]):
		L.claim(c, i, 0)
	# whatever the tile did to the tender (fire, goo, a supply) lands on arrival
	for i in L.unclaimed(c):
		L.claim(c, i, int(L.T_MOVE * 0.75))
	return L.T_MOVE


static func _plan_strike(c: Dictionary) -> int:
	var evs: Array = c["events"]
	var p0: Vector2i = c["p0"]
	for i in evs.size():
		if String(evs[i].get("t", "")) != "strike":
			continue
		L.claim(c, i, 0)
		var e = c["pre_en"].get(evs[i].get("id"))
		if e == null:
			break
		var tgt: Vector2i = e["pos"]
		var d := L.dir_of(p0, tgt)
		L.seg(c, "player", {"kind": "lunge", "t0": 0, "dur": L.T_STRIKE, "dir": d, "reach": 0.38})
		L.clip(c, {"kind": "slash", "t0": 70, "dur": 240, "at": tgt, "dir": d, "pal": L.pal_of("growth")})
		for j in range(i + 1, evs.size()):
			var ev: Dictionary = evs[j]
			if String(ev.get("t", "")) == "damage" and String(ev.get("who", "")) == "player":
				L.claim(c, j, L.T_STRIKE_HIT + 20, -d)  # spikes bite back
				L.clip(c, {"kind": "spark", "t0": L.T_STRIKE_HIT + 10, "dur": 220, "at": tgt,
					"col": Color("c3c8ce"), "n": 6})
			elif ev.get("id") == e["id"]:
				L.claim(c, j, L.T_STRIKE_HIT, d)
		break
	for i in L.unclaimed(c):
		L.claim(c, i, L.T_STRIKE_HIT)
	return L.T_STRIKE


static func _plan_cleanse(c: Dictionary) -> int:
	var evs: Array = c["events"]
	var t_hit := 150
	for i in evs.size():
		if String(evs[i].get("t", "")) != "cleanse":
			continue
		var tile: Vector2i = evs[i]["tile"]
		var d := L.dir_of(c["p0"], tile)
		L.seg(c, "player", {"kind": "lunge", "t0": 0, "dur": 260, "dir": d, "reach": 0.22})
		L.clip(c, {"kind": "scrub", "t0": 40, "dur": 420, "at": tile, "layer": "air"})
		L.claim(c, i, t_hit)
		L.reveal(c, tile, t_hit)
	for i in L.unclaimed(c):
		L.claim(c, i, t_hit + 60)
	return 460


static func _plan_item(c: Dictionary) -> int:
	var evs: Array = c["events"]
	for i in evs.size():
		if String(evs[i].get("t", "")) != "item_use":
			continue
		L.claim(c, i, 0)
		L.seg(c, "player", {"kind": "cast", "t0": 0, "dur": 220, "col": Color("e8c840")})
		L.clip(c, {"kind": "item", "t0": 0, "dur": 520, "at": c["p0"], "id": String(evs[i].get("id", ""))})
		# a stun vial goes off like a pollen cloud
		var stunned := 0
		for j in range(i + 1, evs.size()):
			if String(evs[j].get("t", "")) == "status":
				stunned += 1
		if stunned > 0:
			L.clip(c, {"kind": "ring", "t0": 180, "dur": 420, "at": c["p0"], "r0": 0.3, "r1": 2.5,
				"col": L.status_col("stun"), "w": 0.12, "layer": "ground"})
	for i in L.unclaimed(c):
		L.claim(c, i, 240)
	return 480


static func _plan_ability(c: Dictionary) -> int:
	var evs: Array = c["events"]
	var ia := -1
	for i in evs.size():
		if String(evs[i].get("t", "")) == "ability":
			ia = i
			break
	if ia < 0:
		return 0  # refused: nothing happened
	var aid := String(evs[ia].get("id", ""))
	var adef: Dictionary = Content.ABILITIES.get(aid, {})
	c["aid"] = aid
	c["adef"] = adef
	c["pal"] = L.pal_for(aid)
	c["target"] = evs[ia].get("target", c["action"].get("target"))
	var pal: Dictionary = c["pal"]
	var p0: Vector2i = c["p0"]
	# the cast begins: whatever happened before the ability event (a verdant
	# surge drinking the growth underfoot, the oil tithe) is part of the wind-up
	for i in range(ia):
		L.claim(c, i, 0)
		if String(evs[i].get("t", "")) == "verdant":
			L.quiet(c, i)
			L.clip(c, {"kind": "motes", "t0": 0, "dur": 360, "from": p0, "to": p0,
				"col": Color("8fdc6a"), "n": 8, "rise": true, "layer": "air"})
			L.reveal(c, p0, 60)
	L.claim(c, ia, 0)
	L.seg(c, "player", {"kind": "cast", "t0": 0, "dur": L.T_WINDUP + 90, "col": pal["a"]})
	L.clip(c, {"kind": "cast_ring", "t0": 0, "dur": 340, "at": p0, "layer": "ground"})
	var surge := {}
	for i in range(ia + 1, evs.size()):
		if String(evs[i].get("t", "")) != "surge":
			continue
		L.claim(c, i, L.T_WINDUP - 30)
		var sd: Dictionary = adef.get("surge", Content.SURGE_DEFAULT)
		for k in evs[i].get("keys", []):
			if sd.has(k):
				surge[k] = sd[k]
		L.clip(c, {"kind": "surge", "t0": L.T_WINDUP - 30, "dur": 380, "at": p0})
	c["ev0"] = ia + 1
	var t := L.T_WINDUP
	for eff in adef.get("effects", []):
		t = _build_effect(c, L.surged(eff, surge), t, surge)
	# riders are the combo moments: a small gold flourish at the tender
	for i in L.unclaimed(c, ["rider"]):
		L.claim(c, i, maxi(L.T_WINDUP, t - 120))
		L.clip(c, {"kind": "spark", "t0": maxi(L.T_WINDUP, t - 120), "dur": 300,
			"at": c["ppos"], "col": Color("e8c840"), "n": 8})
	return t


## Build one effect with the family that owns its op; its `then` list runs
## from the parent's impact. Returns when its main motion ends.
static func _build_effect(c: Dictionary, eff: Dictionary, t: int, surge: Dictionary) -> int:
	c["eff"] = eff
	c["t"] = t
	c["hit"] = L.T_HIT
	var op := String(eff.get("op", ""))
	var fam = family_for_op(op)
	var t_end := t + 220
	if fam != null:
		t_end = int(fam.build(op, c))
	else:
		L.clip(c, {"kind": "ring", "t0": t, "dur": 320, "at": c["ppos"], "r0": 0.2, "r1": 1.2,
			"col": c["pal"]["a"], "w": 0.1, "layer": "ground"})
	if eff.has("then"):
		var t_then := maxi(t, t_end - 90)
		for sub in eff["then"]:
			t_end = maxi(t_end, _build_effect(c, L.surged(sub, surge), t_then, surge))
	return t_end


static func family_for_op(op: String):
	for fam in OP_FAMILIES:
		if fam.OPS.has(op):
			return fam
	return null


# --- the enemy phase -----------------------------------------------------------

## end_turn: every enemy executes its telegraphed intent in list order, then
## the environment ticks. Each enemy gets a slot on the timeline; the event
## stream is attributed to slots with a monotone cursor over the PRE enemy
## list (the sim's own execution order), and whatever cannot be attributed to
## an enemy belongs to the environment phase that follows the last slot.
static func _plan_enemy_phase(c: Dictionary) -> int:
	var ens: Array = c["pre"]["enemies"]
	var owners := _attribute(c, ens)
	var evs: Array = c["events"]
	# who gets a slot: anything that telegraphed an action, emitted an event
	# or moved - an idle enemy that did nothing gets none
	var acting: Array = []
	for k in ens.size():
		var e: Dictionary = ens[k]
		var itype := String(e["intent"].get("type", "idle"))
		var owns := owners.has(k)
		if itype != "idle" or owns or L.moved(c, e["id"]) != null:
			acting.append(k)
	var n := acting.size()
	var gap := clampi(760 / maxi(n, 1), 45, 135)
	var t := 60
	var t_env := 60
	for k in acting:
		var e: Dictionary = ens[k]
		c["t"] = t
		c["hit"] = L.T_HIT
		c["e"] = e
		c["post_e"] = c["post_en"].get(e["id"])
		c["own"] = owners.get(k, [])
		c["ev0"] = 0
		c["ev1"] = evs.size()
		var verb := String(e["intent"].get("type", "idle"))
		for i in c["own"]:
			var tt := String(evs[i].get("t", ""))
			if tt == SCREENED_VERB:
				verb = SCREENED_VERB
			elif _is_blocked_event(tt):
				verb = BLOCKED_VERB
		c["verb_ev"] = -1
		var t_end: int = t + L.T_ENEMY
		if FxEnemy.INTENTS.has(verb):
			t_end = int(FxEnemy.build(verb, c))
		# anything the verb did not claim lands at its impact
		for i in c["own"]:
			if not L.claimed(c, i):
				L.claim(c, i, t + int(c["hit"]))
		# a creature that changed tile without the verb drawing it still walks
		var mv = L.moved(c, e["id"])
		if mv != null and not c["reel"]["tracks"].has(e["id"]):
			L.move(c, e["id"], L.path(c["pre"], mv[0], mv[1]), t, L.T_ENEMY - 60, 0.12)
		t_env = maxi(t_env, t_end)
		t += gap
	# the environment phase: hazards, the smog clock, vents, next turn's regen
	for i in evs.size():
		if L.claimed(c, i):
			continue
		var tt := String(evs[i].get("t", ""))
		var dt := 0
		if tt == "heal" or tt == "item_pickup":
			dt = 160
		elif tt == "reinforcement" or tt == "seal_burst":
			dt = 90
		L.claim(c, i, t_env + dt)
	return t_env + 200


static func _is_blocked_event(tt: String) -> bool:
	for sname in Content.STATUSES:
		if String(Content.STATUSES[sname].get("blocked_event", sname)) == tt:
			return true
	return false


## event index -> owning PRE-list enemy index, as {k: [event indices]}.
## Events that cannot belong to an intent (hazard ticks, the smog clock,
## vents, regen) flip the walk into the environment phase for good.
static func _attribute(c: Dictionary, ens: Array) -> Dictionary:
	var evs: Array = c["events"]
	var idx := {}
	for k in ens.size():
		idx[ens[k]["id"]] = k
	var out := {}
	var cursor := 0
	var env := false
	var prev := -1
	var last_by_id := {}
	for i in evs.size():
		var ev: Dictionary = evs[i]
		var tt := String(ev.get("t", ""))
		var o := -1
		if not env:
			o = _owner_of(c, ev, tt, ens, idx, cursor, prev, last_by_id)
			if o == -2:
				env = true
				o = -1
		if o >= 0:
			cursor = o
			if not out.has(o):
				out[o] = []
			out[o].append(i)
			if ev.has("id") and idx.has(ev["id"]):
				last_by_id[ev["id"]] = o
		prev = o
	return out


static func _owner_of(c: Dictionary, ev: Dictionary, tt: String, ens: Array, idx: Dictionary,
		cursor: int, prev: int, last_by_id: Dictionary) -> int:
	if ENV_TYPES.has(tt):
		return -2
	var id = ev.get("id", null)
	var mine: bool = id != null and not (id is String) and idx.has(id) and int(idx[id]) >= cursor
	match tt:
		"damage":
			var src := String(ev.get("src", ""))
			if String(ev.get("who", "")) == "player":
				for k in range(cursor, ens.size()):
					if String(ens[k]["kind"]) == src:
						return k
				return -2  # fire, goo, smog: the world, not a machine
			if not mine:
				return -2 if (id != null and idx.has(id)) else prev
			if src == "thorns":
				return int(idx[id])
			# terrain entered mid-move belongs to the mover; a tick is the world
			if src.contains(":") or Content.STATUSES.has(src):
				var moved: bool = L.moved(c, id) != null or not c["post_en"].has(id) \
					and ["move", "advance"].has(String(ens[idx[id]]["intent"].get("type", "")))
				if Content.STATUSES.has(src) or not moved:
					return -2
			return int(idx[id])
		"death", "split":
			if id != null and last_by_id.has(id):
				return int(last_by_id[id])
			return prev
		"flood", "ignite_all":
			for k in range(cursor, ens.size()):
				if String(ens[k]["intent"].get("type", "")) == tt:
					return k
			return prev
		"ignite":
			for k in range(cursor, ens.size()):
				var pe = c["post_en"].get(ens[k]["id"])
				if pe != null and pe["pos"] == ev.get("tile") and L.moved(c, ens[k]["id"]) != null:
					return k
			return prev
	if mine:
		return int(idx[id])
	return prev


# --- the generic pass ------------------------------------------------------------

## Every event, at the time its planner gave it, gets its standard feedback:
## numbers, hit flashes and recoil, deaths, spawns, status pops, shakes.
static func _feedback(c: Dictionary, t_end: int) -> void:
	var evs: Array = c["events"]
	var reel: Dictionary = c["reel"]
	var stack := {}  # victim key -> floats already queued (they fan out in time)
	# an unclaimed event that FOLLOWS from the one before it (a death after the
	# killing blow, a status a hook landed, the bounty) happens right after it;
	# anything else unclaimed happens when the step's main motion ends
	for i in evs.size():
		if L.claimed(c, i):
			continue
		if i > 0 and FOLLOW_TYPES.has(String(evs[i].get("t", ""))):
			L.claim(c, i, int(c["times"][i - 1]) + 30)
		else:
			L.claim(c, i, t_end)
	for i in evs.size():
		var ev: Dictionary = evs[i]
		var t: int = int(c["times"][i])
		if c["quiet"][i]:
			continue
		match String(ev.get("t", "")):
			"damage":
				var mine := String(ev.get("who", "")) == "player"
				var key = "player" if mine else ev.get("id")
				_hp_change(reel, key, t, -int(ev.get("amt", 0)))
				var at := _pos_at(c, key, t)
				var nq := int(stack.get(key, 0))
				stack[key] = nq + 1
				L.clip(c, {"kind": "float", "t0": t + nq * L.FLOAT_STACK, "dur": L.T_FLOAT, "at": at,
					"text": "-%d" % int(ev.get("amt", 0)),
					"col": Color("e04b3a") if mine else Color("e6edd8")})
				var d = c["dirs"][i]
				if d == null:
					d = L.dir_of(c["p0"] if not mine else Vector2i(at.round()), Vector2i(at.round()))
				L.seg(c, key, {"kind": "recoil", "t0": t, "dur": L.T_RECOIL, "dir": d,
					"amt": 0.16 if not mine else 0.12})
				if mine:
					reel["shakes"].append({"t0": t, "mag": 2.0 + minf(float(int(ev.get("amt", 0))) * 1.2, 6.0)})
					L.seg(c, "player", {"kind": "tint", "t0": t, "dur": 300, "col": Color(1.0, 0.45, 0.4)})
			"shield_absorb":
				L.clip(c, {"kind": "float", "t0": t, "dur": L.T_FLOAT, "at": _pos_at(c, "player", t),
					"text": "blocked", "col": Color("7fb6d9")})
			"heal":
				_hp_change(reel, "player", t, int(ev.get("amt", 0)))
				var hp := _pos_at(c, "player", t)
				L.clip(c, {"kind": "float", "t0": t, "dur": L.T_FLOAT, "at": hp,
					"text": "+%d" % int(ev.get("amt", 0)), "col": Color("8fdc6a")})
				L.clip(c, {"kind": "motes", "t0": t, "dur": 520, "from": Vector2i(hp.round()), "to": Vector2i(hp.round()),
					"col": Color("8fdc6a"), "n": 5, "rise": true})
			"shield":
				L.clip(c, {"kind": "float", "t0": t + 60, "dur": L.T_FLOAT, "at": _pos_at(c, "player", t),
					"text": "shield %d" % int(ev.get("total", 0)), "col": Color("7fb6d9")})
			"cleanse":
				var cp: Vector2i = ev["tile"]
				L.clip(c, {"kind": "burst", "t0": t, "dur": 700, "at": cp, "col": Color("e8c840")})
				L.clip(c, {"kind": "float", "t0": t, "dur": L.T_FLOAT, "at": Vector2(cp),
					"text": "+%d" % int(ev.get("bloom", 1)), "col": Color("e8c840")})
			"death":
				var dk = ev.get("id")
				L.seg(c, dk, {"kind": "die", "t0": t + 40, "dur": L.T_DIE})
				L.clip(c, {"kind": "puff", "t0": t + 60, "dur": 700, "at": _pos_at(c, dk, t),
					"col": Color(0.62, 0.64, 0.66)})
			"player_death":
				L.seg(c, "player", {"kind": "die", "t0": t + 80, "dur": 900})
			"status":
				L.clip(c, {"kind": "status_pop", "t0": t, "dur": L.T_STATUS,
					"at": _pos_at(c, ev.get("id"), t), "status": String(ev.get("status", ""))})
			"resisted", "immune":
				L.clip(c, {"kind": "float", "t0": t, "dur": L.T_FLOAT, "at": _pos_at(c, ev.get("id"), t),
					"text": String(ev.get("t", "")), "col": Color("97a29a")})
			"room_bloom":
				var bp := _pos_at(c, "player", t)
				L.clip(c, {"kind": "burst", "t0": t, "dur": 700, "at": bp, "col": Color(0.91, 0.70, 0.82)})
				L.clip(c, {"kind": "float", "t0": t + 120, "dur": L.T_FLOAT, "at": bp,
					"text": "BLOOM +%d" % int(ev.get("bonus", 2)), "col": Color("e8c840")})
			"bounty":
				L.clip(c, {"kind": "float", "t0": t + 80, "dur": L.T_FLOAT, "at": _pos_at(c, "player", t),
					"text": "+%d bloom" % int(ev.get("bloom", 0)), "col": Color("e8c840")})
			"stairs_awaken":
				if ev.has("tile"):
					L.clip(c, {"kind": "burst", "t0": t, "dur": 700, "at": ev["tile"], "col": Color("e8c840")})
			"floor_restored":
				L.clip(c, {"kind": "burst", "t0": t, "dur": 700, "at": _pos_at(c, "player", t),
					"col": Color(0.6, 0.9, 0.5)})
			"ignite":
				L.clip(c, {"kind": "flare", "t0": t, "dur": 420, "at": ev["tile"], "col": Color("ef933a")})
			"wash":
				L.clip(c, {"kind": "splash", "t0": t, "dur": 420, "at": ev["tile"]})
			"smoke_cleared":
				L.clip(c, {"kind": "puff", "t0": t, "dur": 520, "at": Vector2(ev["tile"]),
					"col": Color(0.6, 0.62, 0.62)})
			"convert":
				L.clip(c, {"kind": "tile_pop", "t0": t, "dur": 420, "at": ev["tile"],
					"col": L.TERRAIN_COL.get(L.tkind(c["post"], ev["tile"]), Color("6cc95c")), "layer": "ground"})
			"hook":
				if ev.has("tile") and ev["tile"] is Vector2i:
					L.clip(c, {"kind": "spark", "t0": t, "dur": 340, "at": ev["tile"],
						"col": Color("ef933a"), "n": 6})
			"tithe":
				L.clip(c, {"kind": "float", "t0": t, "dur": L.T_FLOAT, "at": _pos_at(c, "player", t),
					"text": "tithe", "col": Color("e8c840")})
			"gummed":
				L.clip(c, {"kind": "float", "t0": t + 40, "dur": L.T_FLOAT, "at": _pos_at(c, "player", t),
					"text": "gummed", "col": Color("c9a63c")})
			"drain":
				L.clip(c, {"kind": "float", "t0": t + 60, "dur": L.T_FLOAT, "at": _pos_at(c, "player", t),
					"text": "-%d charge" % int(ev.get("amt", 0)), "col": Color("f7c948")})
			"anchored":
				L.clip(c, {"kind": "float", "t0": t, "dur": L.T_FLOAT, "at": _pos_at(c, "player", t),
					"text": "anchored", "col": Color("dcb880")})
			"item_pickup":
				L.clip(c, {"kind": "item", "t0": t, "dur": 520, "at": c["p1"], "id": String(ev.get("id", ""))})
			"boss_phase", "ignite_all", "flood", "smoke_burst", "assimilate":
				reel["shakes"].append({"t0": t, "mag": L.SHAKE_BIG})


static func _hp_change(reel: Dictionary, key, t: int, delta: int) -> void:
	if not reel["hp"].has(key):
		reel["hp"][key] = []
	reel["hp"][key].append([t, delta])


## Enemies that left the board are drawn as ghosts until their die segment
## ends; enemies that joined it are hidden until they pop in.
static func _ghosts_and_spawns(c: Dictionary, t_end: int) -> void:
	var reel: Dictionary = c["reel"]
	var evs: Array = c["events"]
	for id in c["pre_en"]:
		if c["post_en"].has(id):
			continue
		var e: Dictionary = c["pre_en"][id]
		var segs: Array = reel["tracks"].get(id, [])
		var t_die := -1
		for s in segs:
			if String(s["kind"]) == "die":
				t_die = int(s["t0"])
		if t_die < 0:
			# no death event (a welded partner, a floor change): fade out
			t_die = t_end
			L.seg(c, id, {"kind": "die", "t0": t_die, "dur": L.T_DIE})
		reel["ghosts"].append({
			"id": id, "kind": e["kind"], "elite": e.get("elite", false),
			"pos": _pos_at(c, id, t_die), "t_die": t_die,
		})
	for id in c["post_en"]:
		if c["pre_en"].has(id):
			continue
		var t_in := t_end
		var pos: Vector2i = c["post_en"][id]["pos"]
		for i in evs.size():
			var ev: Dictionary = evs[i]
			var tt := String(ev.get("t", ""))
			if (tt == "summon" or tt == "split") and ev.get("child") == id:
				t_in = int(c["times"][i]) + 60
				break
			if tt == "reinforcement" and ev.get("tile") == pos:
				t_in = int(c["times"][i]) + 60
				break
		reel["spawns"][id] = t_in
		L.seg(c, id, {"kind": "pop", "t0": t_in, "dur": L.T_POP})
		L.clip(c, {"kind": "portal", "t0": maxi(0, t_in - 80), "dur": 460, "at": pos, "layer": "ground",
			"col": Color("e04b3a")})


## Terrain that changed flips when the event that changed it lands; a change
## no event names (a fire burning to ash, an oil trail, a dredge) flips at the
## end of the step's main motion.
static func _reveals(c: Dictionary, t_end: int) -> void:
	var evs: Array = c["events"]
	var sw: Dictionary = c["reel"]["tswap"]
	for i in evs.size():
		var ev: Dictionary = evs[i]
		var tile = ev.get("tile")
		if tile is Vector2i and sw.has(tile) and not sw[tile].has("t"):
			sw[tile]["t"] = int(c["times"][i])
	for p in sw:
		if not sw[p].has("t"):
			sw[p]["t"] = t_end


static func _length(reel: Dictionary) -> int:
	var n := 0
	for cl in reel["clips"]:
		n = maxi(n, int(cl["t0"]) + int(cl["dur"]))
	for key in reel["tracks"]:
		for s in reel["tracks"][key]:
			n = maxi(n, int(s["t0"]) + int(s["dur"]))
	for s in reel["shakes"]:
		n = maxi(n, int(s["t0"]) + 320)
	return n


## Rescale every time in the reel. Speed 0 ("off") keeps only the numbers.
static func _scale(reel: Dictionary, k: float) -> void:
	if k <= 0.0:
		var keep: Array = []
		for cl in reel["clips"]:
			if String(cl["kind"]) == "float":
				cl["t0"] = 0
				keep.append(cl)
		reel["clips"] = keep
		reel["tracks"] = {}
		reel["ghosts"] = []
		reel["spawns"] = {}
		reel["shakes"] = []
		reel["hp"] = {}
		for p in reel["tswap"]:
			reel["tswap"][p]["t"] = 0
		reel["len"] = L.T_FLOAT if not keep.is_empty() else 0
		return
	for cl in reel["clips"]:
		cl["t0"] = int(float(cl["t0"]) * k)
		# numbers keep their reading time
		if String(cl["kind"]) != "float":
			cl["dur"] = maxi(1, int(float(cl["dur"]) * k))
	for key in reel["tracks"]:
		for s in reel["tracks"][key]:
			s["t0"] = int(float(s["t0"]) * k)
			s["dur"] = maxi(1, int(float(s["dur"]) * k))
	for g in reel["ghosts"]:
		g["t_die"] = int(float(g["t_die"]) * k)
	for id in reel["spawns"]:
		reel["spawns"][id] = int(float(reel["spawns"][id]) * k)
	for s in reel["shakes"]:
		s["t0"] = int(float(s["t0"]) * k)
	for key in reel["hp"]:
		for h in reel["hp"][key]:
			h[0] = int(float(h[0]) * k)
	for p in reel["tswap"]:
		reel["tswap"][p]["t"] = int(float(reel["tswap"][p]["t"]) * k)
	reel["len"] = _length(reel)


# --- playback --------------------------------------------------------------------

## Where a creature is at reel time t (tile space): its path segments folded
## in time order; before the first it stands at the first point, after the
## last at the last point, and with none at `cur`.
static func pos_at(reel: Dictionary, key, t: float, cur: Vector2) -> Vector2:
	var segs = reel.get("tracks", {}).get(key)
	if segs == null:
		return cur
	var base = null
	for s in segs:
		if String(s["kind"]) != "path":
			continue
		var t0 := float(s["t0"])
		var dur := maxf(1.0, float(s["dur"]))
		var pts: Array = s["pts"]
		if t < t0:
			if base == null:
				base = pts[0]
			break
		if t < t0 + dur:
			base = _path_point(pts, (t - t0) / dur)
			break
		base = pts[pts.size() - 1]
	return cur if base == null else base


static func _path_point(pts: Array, k: float) -> Vector2:
	var m := pts.size() - 1
	var u := clampf(k, 0.0, 1.0) * float(m)
	var j := mini(int(u), m - 1)
	var f := u - float(j)
	return (pts[j] as Vector2).lerp(pts[j + 1], f)


## Position the director itself reads while building (feedback anchors).
static func _pos_at(c: Dictionary, key, t: int) -> Vector2:
	var cur := Vector2(-9, -9)
	if key is String and key == "player":
		cur = Vector2(c["p1"])
	elif c["post_en"].has(key):
		cur = Vector2(c["post_en"][key]["pos"])
	elif c["pre_en"].has(key):
		cur = Vector2(c["pre_en"][key]["pos"])
	return pos_at(c["reel"], key, float(t), cur)


## How to draw a creature at reel time t: position plus the transient body
## language of its segments. `cur` is its post-step tile.
##   pos    tile-space position (float)       lift  tiles above the ground
##   off    tile-space offset (lunge, recoil)  sx/sy scale   rot  radians
##   alpha  opacity   flash 0..1 white-hot     tint  multiply colour
##   visible  false while hidden (not yet spawned, dissolved, dead)
static func pose(reel: Dictionary, key, t: float, cur: Vector2) -> Dictionary:
	var out := {"pos": cur, "lift": 0.0, "off": Vector2.ZERO, "sx": 1.0, "sy": 1.0, "rot": 0.0,
		"alpha": 1.0, "flash": 0.0, "tint": Color(1, 1, 1), "visible": true}
	var segs = reel.get("tracks", {}).get(key)
	if segs == null:
		return out
	out["pos"] = pos_at(reel, key, t, cur)
	var warped := false
	for s in segs:
		var t0 := float(s["t0"])
		var dur := maxf(1.0, float(s["dur"]))
		var k := (t - t0) / dur
		var kind := String(s["kind"])
		if kind == "pop" and k < 0.0:
			out["visible"] = false
		if kind == "die" and k >= 1.0:
			out["visible"] = false
		if kind == "warp_out" and k >= 1.0:
			warped = true
		if kind == "warp_in" and k >= 0.0:
			warped = false
		if k < 0.0 or k >= 1.0:
			continue
		match kind:
			"path":
				var hop := float(s.get("hop", 0.0))
				if hop > 0.0:
					var m := float((s["pts"] as Array).size() - 1)
					var f := fposmod(k * m, 1.0)
					var arc := sin(f * PI)
					out["lift"] += hop * arc
					out["sy"] *= 1.0 + 0.10 * arc
					out["sx"] *= 1.0 - 0.06 * arc
			"squash":
				var q := sin(k * PI)
				out["sy"] *= 1.0 - 0.16 * q
				out["sx"] *= 1.0 + 0.12 * q
			"lunge":
				var a := (k / 0.35) if k < 0.35 else 1.0 - _ease_io((k - 0.35) / 0.65)
				a = clampf(a, 0.0, 1.0)
				out["off"] += (s["dir"] as Vector2) * float(s.get("reach", 0.3)) * a
				out["sx"] *= 1.0 + 0.08 * a
			"recoil":
				var r := (k / 0.2) if k < 0.2 else 1.0 - _ease_io((k - 0.2) / 0.8)
				out["off"] += (s["dir"] as Vector2) * float(s.get("amt", 0.15)) * clampf(r, 0.0, 1.0)
				out["flash"] = maxf(out["flash"], 1.0 - k / 0.55)
			"tint":
				out["tint"] = (s["col"] as Color).lerp(Color(1, 1, 1), k)
			"flash":
				out["flash"] = maxf(out["flash"], 1.0 - k)
			"cast":
				# gather (squash) then release (stretch up), then settle
				if k < 0.45:
					var g := sin(k / 0.45 * PI * 0.5)
					out["sy"] *= 1.0 - 0.13 * g
					out["sx"] *= 1.0 + 0.10 * g
				else:
					var r2 := sin((k - 0.45) / 0.55 * PI)
					out["sy"] *= 1.0 + 0.14 * r2
					out["sx"] *= 1.0 - 0.07 * r2
					out["lift"] += 0.06 * r2
			"struggle":
				out["off"] += Vector2(sin(k * PI * 7.0) * 0.09 * (1.0 - k), 0)
			"die":
				out["sx"] *= 1.0 - 0.6 * k
				out["sy"] *= 1.0 - 0.75 * k
				out["rot"] += k * 0.9
				out["alpha"] *= 1.0 - k
				out["flash"] = maxf(out["flash"], 0.7 * (1.0 - k / 0.3))
			"pop":
				var p := k * 1.15 if k < 0.7 else 1.15 - 0.15 * (k - 0.7) / 0.3
				out["sx"] *= maxf(0.05, p)
				out["sy"] *= maxf(0.05, p)
				out["alpha"] *= minf(1.0, k * 3.0)
			"warp_out":
				out["sx"] *= 1.0 - 0.8 * k
				out["sy"] *= 1.0 + 0.5 * k
				out["alpha"] *= 1.0 - k
				out["lift"] += 0.2 * k
			"warp_in":
				out["sx"] *= 0.2 + 0.8 * _ease_out(k)
				out["sy"] *= 1.5 - 0.5 * _ease_out(k)
				out["alpha"] *= k
			"hide":
				out["visible"] = false
			"shake":
				out["off"] += Vector2(sin(k * PI * 10.0), cos(k * PI * 8.0)) * float(s.get("amt", 0.05)) * (1.0 - k)
	if warped:
		out["visible"] = false
	return out


## The HP to SHOW for a creature at reel time t: its post-step HP with every
## change that has not landed yet undone, so a bar drops when the blow lands.
static func hp_shown(reel: Dictionary, key, t: float, hp_now: int) -> int:
	var hp := hp_now
	for h in reel.get("hp", {}).get(key, []):
		if float(h[0]) > t:
			hp -= int(h[1])
	return hp


## True while any part of the reel is still playing at time t.
static func playing(reel: Dictionary, t: float) -> bool:
	return not reel.is_empty() and t < float(reel.get("len", 0)) + 40.0


## Screen shake amplitude (pixels) at reel time t: each shake decays over 320ms,
## concurrent shakes keep the strongest.
static func shake_at(reel: Dictionary, t: float) -> float:
	var amp := 0.0
	for s in reel.get("shakes", []):
		var a := (t - float(s["t0"])) / 320.0
		if a >= 0.0 and a < 1.0:
			amp = maxf(amp, float(s["mag"]) * (1.0 - a))
	return amp


## Terrain kind to DRAW at `p` at reel time t: the pre-step kind until the
## change lands. Returns null when the tile did not change this step.
static func terrain_at(reel: Dictionary, p: Vector2i, t: float):
	var sw = reel.get("tswap", {}).get(p)
	if sw == null:
		return null
	return String(sw["pre"]) if t < float(sw.get("t", 0)) else String(sw["post"])


## The idle loop: creatures breathe, hover, pant or chug between steps. Pure
## function of the wall clock `now` (ms) and a per-creature phase.
static func idle(style: String, phase: float, now: float) -> Dictionary:
	var s := now / 1000.0 + phase
	var out := {"lift": 0.0, "sx": 1.0, "sy": 1.0, "rot": 0.0, "dx": 0.0}
	match style:
		"player":
			var b := sin(s * TAU / 3.0)
			out["lift"] = 0.02 + 0.02 * b
			out["sy"] = 1.0 + 0.025 * b
			out["sx"] = 1.0 - 0.012 * b
		"heave":
			var h := sin(s * TAU / 1.8)
			out["sy"] = 1.0 + 0.035 * h
			out["sx"] = 1.0 + 0.02 * h
		"hover":
			out["lift"] = 0.08 + 0.05 * sin(s * TAU / 1.1)
			out["rot"] = 0.05 * sin(s * TAU / 2.3)
		"pant":
			var p := absf(sin(s * TAU / 0.5))
			out["sy"] = 1.0 + 0.03 * p
			out["lift"] = 0.01 * p
		"ooze":
			var o := sin(s * TAU / 1.4)
			out["sy"] = 1.0 + 0.06 * o
			out["sx"] = 1.0 - 0.05 * o
		"chug":
			var ch := sin(s * TAU / 0.35)
			out["dx"] = 0.012 * ch
			out["sy"] = 1.0 + 0.012 * absf(ch)
		"skitter":
			out["dx"] = 0.03 * sin(s * TAU / 0.7) * sin(s * TAU / 0.23)
			out["lift"] = 0.02 * absf(sin(s * TAU / 0.23))
		"sway":
			out["rot"] = 0.045 * sin(s * TAU / 2.0)
		_:
			var bb := sin(s * TAU / 1.6)
			out["lift"] = 0.012 + 0.012 * bb
			out["sy"] = 1.0 + 0.015 * bb
	return out


static func _ease_out(k: float) -> float:
	return 1.0 - (1.0 - k) * (1.0 - k)


static func _ease_io(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)
