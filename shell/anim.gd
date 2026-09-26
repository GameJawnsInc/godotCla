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
## Events after which a tile-entry event still belongs to the hauling machine.
const HAUL_FOLLOW := ["drag", "item_pickup", "satchel_full", "damage"]
## Intents that swing at the tender: one blow each per phase.
const DAMAGING_INTENTS := ["attack", "slam", "quake"]
## Pseudo-intents fx_enemy handles for an enemy whose intent never ran.
const BLOCKED_VERB := "blocked"
const SCREENED_VERB := "screened"


# --- planning ------------------------------------------------------------------

static func empty_reel() -> Dictionary:
	return {"clips": [], "tracks": {}, "ghosts": [], "spawns": {}, "shakes": [], "tswap": {}, "hp": {},
		"ev_t": [], "dim": {}, "len": 0}


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
	# when each event lands (the shell holds its banners for them) and when
	# the skies change (a moss filter parts the haze as its beam lands)
	reel["ev_t"] = (c["times"] as Array).duplicate()
	var dims: Array = []
	for i in events.size():
		var tt := String(events[i].get("t", ""))
		if (tt == "undim" or tt == "smog_dim") and events[i].has("dim"):
			dims.append([int(c["times"][i]), int(events[i]["dim"])])
	reel["dim"] = {"pre": int(pre.get("dim", 0)), "at": dims}
	_land_all(c)
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
	var land := L.T_MOVE
	if mv != null:
		# a crouch that springs into a hop (stretched in the air), then a squash
		# and a puff of dust where the feet come down
		var hop0 := 40
		land = hop0 + L.T_MOVE
		L.seg(c, "player", {"kind": "squash", "t0": 0, "dur": 90})
		L.move(c, "player", [mv[0], mv[1]], hop0, L.T_MOVE, 0.2)
		L.seg(c, "player", {"kind": "squash", "t0": land - 25, "dur": 130})
		L.clip(c, {"kind": "land_dust", "t0": land - 15, "dur": 320, "at": mv[1], "dir": L.dir_of(mv[0], mv[1]),
			"layer": "ground"})
	for i in L.unclaimed(c, ["move"]):
		L.claim(c, i, 0)
	# whatever the tile did to the tender (fire, goo, a supply) lands on arrival
	for i in L.unclaimed(c):
		L.claim(c, i, land - 20)
	return land


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
		# a wind-back, then the lunge: the leafy blade crosses the target just
		# as the blow lands (T_STRIKE_HIT) and sheds its leaves past it
		L.seg(c, "player", {"kind": "lunge", "t0": 0, "dur": L.T_STRIKE, "dir": d, "reach": 0.42})
		L.clip(c, {"kind": "slash", "t0": L.T_STRIKE_HIT - 40, "dur": 300, "at": tgt, "dir": d,
			"pal": L.pal_of("growth")})
		for j in range(i + 1, evs.size()):
			var ev: Dictionary = evs[j]
			if String(ev.get("t", "")) == "damage" and String(ev.get("who", "")) == "player":
				# spikes bite back: the blade rings off them and the tender recoils
				L.claim(c, j, L.T_STRIKE_HIT + 30, -d)
				L.clip(c, {"kind": "spark", "t0": L.T_STRIKE_HIT + 5, "dur": 240,
					"at": Vector2(tgt) - d * 0.45, "col": Color("dfe4ea"), "n": 7})
			elif L.same_id(ev.get("id"), e["id"]):
				L.claim(c, j, L.T_STRIKE_HIT, d)
		break
	for i in L.unclaimed(c):
		L.claim(c, i, L.T_STRIKE_HIT)
	return L.T_STRIKE


static func _plan_cleanse(c: Dictionary) -> int:
	var evs: Array = c["events"]
	var t_hit := 240
	for i in evs.size():
		if String(evs[i].get("t", "")) != "cleanse":
			continue
		var tile: Vector2i = evs[i]["tile"]
		var d := L.dir_of(c["p0"], tile)
		# two scrubbing strokes at the tile; the filth lifts, the tile turns
		# (t_hit) and what was scrubbed off rises as gold
		L.seg(c, "player", {"kind": "lunge", "t0": 0, "dur": 170, "dir": d, "reach": 0.24})
		L.seg(c, "player", {"kind": "lunge", "t0": 140, "dur": 180, "dir": d, "reach": 0.17})
		L.clip(c, {"kind": "scrub", "t0": 20, "dur": 560, "at": tile, "layer": "air"})
		L.claim(c, i, t_hit)
		L.reveal(c, tile, t_hit)
	for i in L.unclaimed(c):
		L.claim(c, i, t_hit + 60)
	return t_hit + 120


## A consumable: it pops out of the satchel and is used. What it DID is read
## off the snapshots (an item emits only item_use - and the statuses it lands,
## which the stream puts BEFORE it), never off its id: statuses or smog lifted
## burst it overhead, anything else is swallowed; hp, charge and shield gained
## each get their number, and the HP bar climbs only when it lands.
static func _plan_item(c: Dictionary) -> int:
	var evs: Array = c["events"]
	var p0: Vector2i = c["p0"]
	var pre_p: Dictionary = c["pre"]["player"]
	var post_p: Dictionary = c["post"]["player"]
	var t_end := 480
	for i in evs.size():
		if String(evs[i].get("t", "")) != "item_use":
			continue
		L.claim(c, i, 0)
		var hits: Array = []
		var far := 1.0
		for j in evs.size():
			if String(evs[j].get("t", "")) == "status" and not L.claimed(c, j):
				var pe = c["pre_en"].get(evs[j].get("id"))
				if pe != null:
					hits.append(j)
					far = maxf(far, Vector2(p0).distance_to(Vector2(pe["pos"])))
		var dhp := int(post_p.get("hp", 0)) - int(pre_p.get("hp", 0))
		var dmax := int(post_p.get("max_hp", 0)) - int(pre_p.get("max_hp", 0))
		var dch := int(post_p.get("charge", 0)) - int(pre_p.get("charge", 0))
		var dsh := int(post_p.get("shield", 0)) - int(pre_p.get("shield", 0))
		var dsmog := int(c["post"].get("smog", 0)) - int(c["pre"].get("smog", 0))
		var col := Color("e8c840")
		if not hits.is_empty():
			col = L.status_col(String(evs[hits[0]].get("status", "")))
		elif dhp > 0:
			col = Color("8fdc6a")
		elif dsh > 0:
			col = Color("7fb6d9")
		elif dsmog < 0:
			col = Color("d6f1fb")
		var burst := not hits.is_empty() or dsmog < 0
		# the painter's beats: a shatter breaks 0.52-0.58 into the clip, a
		# swallowed item has sunk into the tender 0.85 in
		var dur := 600 if burst else 540
		var t_use := int(dur * 0.53) if burst else int(dur * 0.85)
		L.seg(c, "player", {"kind": "cast", "t0": 0, "dur": 260, "col": col})
		L.clip(c, {"kind": "item", "t0": 0, "dur": dur, "at": p0, "id": String(evs[i].get("id", "")),
			"use": "shatter" if burst else "consume", "col": col})
		# what the item gave the tender is said in one stack over its head
		# (Ironheart heals, raises max HP and shields in the same breath)
		var said := [0]
		var say := func(t: int, text: String, fcol: Color) -> void:
			L.clip(c, {"kind": "float", "t0": t + int(said[0]) * L.FLOAT_STACK, "dur": L.T_FLOAT, "at": Vector2(p0),
				"text": text, "col": fcol, "n": int(said[0])})
			said[0] = int(said[0]) + 1
		if not hits.is_empty():
			# the cloud rolls out from overhead and each creature is caught the
			# moment the front reaches it: the ring eases out, r = r0 + (r1 - r0)
			# * (1 - (1 - k)^2), so k at a creature's distance is 1 - sqrt(1 - x)
			var r0 := 0.4
			var reach := far + 0.5
			var ring_ms := 420
			L.clip(c, {"kind": "ring", "t0": t_use, "dur": ring_ms, "at": p0, "r0": r0, "r1": reach,
				"col": col, "w": 0.09, "layer": "ground"})
			for j in hits:
				var pe = c["pre_en"].get(evs[j].get("id"))
				var x := clampf((Vector2(p0).distance_to(Vector2(pe["pos"])) - r0) / (reach - r0), 0.0, 1.0)
				var t_hit := t_use + int(float(ring_ms) * (1.0 - sqrt(1.0 - x)))
				# a stream of motes rides out with it: the first lands with the stun
				var m0 := t_use - 20
				L.clip(c, {"kind": "motes", "t0": m0, "dur": maxi(120, int(float(t_hit - m0) / 0.65)), "from": p0,
					"to": pe["pos"], "col": col, "n": 4})
				L.claim(c, j, t_hit)
		if dsmog < 0:
			L.clip(c, {"kind": "ring", "t0": t_use, "dur": 520, "at": p0, "r0": 0.4, "r1": 3.5,
				"col": col, "w": 0.1, "layer": "air"})
			say.call(t_use + 40, "%d smog" % dsmog, col)
		if dhp > 0:
			_hp_change(c["reel"], "player", t_use, dhp)
			say.call(t_use, "+%d" % dhp, Color("8fdc6a"))
			L.clip(c, {"kind": "motes", "t0": t_use - 80, "dur": 640, "from": p0, "to": p0,
				"col": Color("8fdc6a"), "n": 7, "rise": true})
			L.clip(c, {"kind": "ring", "t0": t_use, "dur": 360, "at": p0, "r0": 0.2, "r1": 0.75,
				"col": Color("b8f09a"), "w": 0.07, "layer": "ground"})
			L.seg(c, "player", {"kind": "cast", "t0": t_use - 40, "dur": 300, "col": Color("8fdc6a")})
			L.seg(c, "player", {"kind": "tint", "t0": t_use, "dur": 360, "col": Color(0.82, 1.0, 0.62)})
		if dmax > 0:
			say.call(t_use, "+%d max" % dmax, Color("8fdc6a"))
		if dch > 0:
			L.clip(c, {"kind": "motes", "t0": t_use - 60, "dur": 560, "from": p0, "to": p0,
				"col": Color("f7c948"), "n": 6, "rise": true})
			say.call(t_use, "+%d charge" % dch, Color("f7c948"))
		if dsh > 0:
			L.clip(c, {"kind": "buff_pop", "t0": t_use, "dur": 300, "at": p0, "buff": "shield",
				"who": "player", "pre": int(pre_p.get("shield", 0))})
			say.call(t_use + 40, "shield %d" % int(post_p.get("shield", 0)), Color("7fb6d9"))
		t_end = maxi(t_end, t_use + 160)
	for i in L.unclaimed(c):
		L.claim(c, i, 240)
	return t_end


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


static func _is_machine_kind(ens: Array, kind: String) -> bool:
	for e in ens:
		if String(e["kind"]) == kind:
			return true
	return false


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
	var blown := {}  # machines whose one blow of the phase has landed
	var prev_t := ""
	for i in evs.size():
		var ev: Dictionary = evs[i]
		var tt := String(ev.get("t", ""))
		var o := -1
		if not env:
			o = _owner_of(c, ev, tt, ens, idx, cursor, prev, last_by_id, blown, prev_t)
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
		prev_t = tt
	return out


## Each machine lands at most one blow a phase, so a pack of one kind is
## credited bite by bite in list order (`blown`), and the part of a blow the
## shield soaked up (an id-less shield_absorb, emitted just before the damage
## it reduced) belongs to the same machine as the damage after it.
static func _owner_of(c: Dictionary, ev: Dictionary, tt: String, ens: Array, idx: Dictionary,
		cursor: int, prev: int, last_by_id: Dictionary, blown: Dictionary, prev_t: String) -> int:
	# a haul drops the tender onto a tile, and what that tile does to it (goo,
	# fire, a supply pickup) comes between one drag and the next: it belongs
	# to the machine hauling, never to the environment phase
	if prev >= 0 and HAUL_FOLLOW.has(prev_t) and String(ens[prev]["intent"].get("type", "")) == "drag":
		if tt == "item_pickup" or tt == "satchel_full" \
				or (tt == "damage" and String(ev.get("who", "")) == "player" and not _is_machine_kind(ens, String(ev.get("src", "")))):
			return prev
	if ENV_TYPES.has(tt):
		return -2
	var id = ev.get("id", null)
	var mine: bool = id != null and not (id is String) and idx.has(id) and int(idx[id]) >= cursor
	match tt:
		"shield_absorb":
			for k in range(cursor, ens.size()):
				if not blown.has(k) and DAMAGING_INTENTS.has(String(ens[k]["intent"].get("type", ""))):
					blown[k] = true
					return k
			return prev
		"damage":
			var src := String(ev.get("src", ""))
			if String(ev.get("who", "")) == "player":
				if prev_t == "shield_absorb" and prev >= 0 and String(ens[prev]["kind"]) == src:
					return prev  # the rest of the blow the shield soaked
				var first := -1
				for k in range(cursor, ens.size()):
					if String(ens[k]["kind"]) != src:
						continue
					if first < 0:
						first = k
					if not blown.has(k):
						blown[k] = true
						return k
				return first if first >= 0 else -2  # fire, goo, smog: the world
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
	# Numbers and words on one body stack: one that lands while the last is
	# still fresh waits a beat and fans out beside it (a shield that blocks
	# half a blow says "blocked" AND "-1"); one that lands later starts fresh,
	# exactly when its own blow does. Keyed by "player", an enemy id or a tile.
	var stack := {}
	# A number rises into the tile above its body; when someone stands there
	# it would sit on THEIR feet and read as their damage, so it stays low,
	# on its own body, instead.
	var taken := {}
	for e in c["post"]["enemies"]:
		taken[e["pos"]] = true
	for id in c["pre_en"]:
		if not c["post_en"].has(id):
			taken[c["pre_en"][id]["pos"]] = true
	var say := func(key, t: int, at: Vector2, text: String, col: Color) -> void:
		var st: Array = stack.get(key, [-100000, -1])
		var t0: int = maxi(t, int(st[0]) + L.FLOAT_STACK)
		var n: int = int(st[1]) + 1 if t0 - int(st[0]) < int(L.T_FLOAT * 0.5) else 0
		stack[key] = [t0, n]
		var above := Vector2i(at.round()) + Vector2i(0, -1)
		var low: bool = taken.has(above) or Vector2i(_pos_at(c, "player", t0).round()) == above
		L.clip(c, {"kind": "float", "t0": t0, "dur": L.T_FLOAT, "at": at, "text": text, "n": n, "col": col,
			"low": low})
	var last_hit := {}  # victim key -> direction of its latest blow (a death tips away from it)
	var pl0: Dictionary = c["pre"]["player"]
	# the tender's buffs and HP as the stream changes them, so each overlay
	# change can hold its old value until it lands (shell/anim_paint.gd), and a
	# heal the cap cut short never shows the bar dipping before it climbs
	var shield_run := int(pl0.get("shield", 0))
	var hp_run := int(pl0.get("hp", 0))
	var hp_max := int(c["post"]["player"].get("max_hp", pl0.get("max_hp", 0)))
	# every enemy status as the stream changes it (Content.STATUSES stack
	# rules), so a second pop of one status holds the FIRST pop's value, not
	# the pre-step one
	var st_run := {}
	var own_cleanse := String(c["action"].get("type", "")) == "cleanse"
	var restored := false
	for i in evs.size():
		var ev: Dictionary = evs[i]
		var t: int = int(c["times"][i])
		var et := String(ev.get("t", ""))
		var pre_st := 0
		if et == "status":
			var sk := "%s|%s" % [str(ev.get("id")), String(ev.get("status", ""))]
			var pe0 = c["pre_en"].get(ev.get("id"))
			pre_st = int(st_run.get(sk, 0 if pe0 == null else int(pe0.get("status", {}).get(String(ev.get("status", "")), 0))))
			var sdef: Dictionary = Content.STATUSES.get(String(ev.get("status", "")), {})
			var turns := int(ev.get("turns", 0))
			if String(sdef.get("stack", "max")) == "add":
				var cap := int(sdef.get("cap", 0))
				st_run[sk] = mini(pre_st + turns, cap) if cap > 0 else pre_st + turns
			else:
				st_run[sk] = maxi(pre_st, turns)
		if c["quiet"][i]:
			match et:
				"shield":
					shield_run = int(ev.get("total", shield_run))
				"shield_absorb":
					shield_run -= int(ev.get("amt", 0))
				"damage":
					if String(ev.get("who", "")) == "player":
						hp_run -= int(ev.get("amt", 0))
				"heal":
					hp_run = mini(hp_max, hp_run + int(ev.get("amt", 0)))
			continue
		match et:
			"damage":
				var mine := String(ev.get("who", "")) == "player"
				var key = "player" if mine else ev.get("id")
				var amt := int(ev.get("amt", 0))
				_hp_change(reel, key, t, -amt)
				if mine:
					hp_run -= amt
				var at := _pos_at(c, key, t)
				say.call(key, t, at, "-%d" % amt, Color("ff5a45") if mine else Color("fff6e0"))
				var d = c["dirs"][i]
				if d == null:
					d = L.dir_of(c["p0"] if not mine else Vector2i(at.round()), Vector2i(at.round()))
				last_hit[key] = d
				# the blow lands: a white-hot flash and a snap on the side it came
				# from, the body knocked back (harder hits rock it further)
				L.seg(c, key, {"kind": "recoil", "t0": t, "dur": L.T_RECOIL, "dir": d,
					"amt": (0.12 if mine else 0.14) + 0.02 * minf(float(amt), 4.0)})
				L.clip(c, {"kind": "impact", "t0": t, "dur": 150, "at": at, "dir": d,
					"col": Color("ffd0c4") if mine else Color.WHITE})
				if mine:
					reel["shakes"].append({"t0": t, "mag": 2.0 + minf(float(amt) * 1.2, 6.0)})
					# white first (the recoil), then a hurt RED that holds and
					# snaps back rather than fading through orange
					L.seg(c, "player", {"kind": "tint", "t0": t, "dur": 380, "col": Color(1.0, 0.16, 0.14), "hold": 0.5})
			"shield_absorb":
				var sp := _pos_at(c, "player", t)
				say.call("player", t, sp, "blocked", Color("a8d4ee"))
				L.clip(c, {"kind": "buff_pop", "t0": t, "dur": 360, "at": sp, "buff": "shield", "break": true,
					"who": "player", "pre": shield_run})
				shield_run -= int(ev.get("amt", 0))
			"heal":
				# what the bar really gains: a heal is capped at max HP
				var gain := clampi(int(ev.get("amt", 0)), 0, maxi(0, hp_max - hp_run))
				hp_run += gain
				_hp_change(reel, "player", t, gain)
				var hp := _pos_at(c, "player", t)
				if gain > 0:
					say.call("player", t, hp, "+%d" % gain, Color("8fdc6a"))
				L.clip(c, {"kind": "motes", "t0": maxi(0, t - 80), "dur": 640, "from": Vector2i(hp.round()), "to": Vector2i(hp.round()),
					"col": Color("8fdc6a"), "n": 7, "rise": true})
				L.clip(c, {"kind": "ring", "t0": t, "dur": 360, "at": hp, "r0": 0.2, "r1": 0.75,
					"col": Color("b8f09a"), "w": 0.07, "layer": "ground"})
				L.seg(c, "player", {"kind": "cast", "t0": maxi(0, t - 40), "dur": 300, "col": Color("8fdc6a")})
				L.seg(c, "player", {"kind": "tint", "t0": t, "dur": 360, "col": Color(0.82, 1.0, 0.62)})
			"shield":
				var sp := _pos_at(c, "player", t)
				say.call("player", t + 60, sp, "shield %d" % int(ev.get("total", 0)), Color("a8d4ee"))
				L.clip(c, {"kind": "buff_pop", "t0": t, "dur": 300, "at": sp, "buff": "shield",
					"who": "player", "pre": shield_run})
				shield_run = int(ev.get("total", shield_run))
			"thorns", "anchor":
				L.clip(c, {"kind": "buff_pop", "t0": t, "dur": 300, "at": _pos_at(c, "player", t), "buff": et,
					"who": "player", "pre": int(pl0.get(et + "_turns", 0))})
			"cleanse":
				var cp: Vector2i = ev["tile"]
				if not own_cleanse:
					L.clip(c, {"kind": "burst", "t0": t, "dur": 600, "at": cp, "col": Color("e8c840")})
				L.clip(c, {"kind": "tile_pop", "t0": t, "dur": 340, "at": cp, "layer": "ground",
					"col": L.TERRAIN_COL.get(L.tkind(c["post"], cp), Color("6cc95c"))})
				say.call(cp, t + 20, Vector2(cp), "+%d" % int(ev.get("bloom", 1)), Color("f7d85a"))
			"death":
				var dk = ev.get("id")
				var dd = last_hit.get(dk, Vector2.ZERO)
				var dp := _pos_at(c, dk, t)
				L.seg(c, dk, {"kind": "die", "t0": t + 30, "dur": L.T_DIE, "dir": dd})
				L.clip(c, {"kind": "puff", "t0": t + 110, "dur": 540, "at": dp,
					"col": Color(0.6, 0.62, 0.64), "debris": true})
			"player_death":
				var wilt := 1000
				L.seg(c, "player", {"kind": "die", "t0": t + 80, "dur": wilt, "style": "wilt",
					"dir": last_hit.get("player", Vector2.ZERO)})
				L.clip(c, {"kind": "petals", "t0": t + 80 + int(wilt * 0.3), "dur": 900,
					"at": _pos_at(c, "player", t), "n": 12})
			"status":
				var sid = ev.get("id")
				L.clip(c, {"kind": "status_pop", "t0": t, "dur": L.T_STATUS, "at": _pos_at(c, sid, t),
					"status": String(ev.get("status", "")), "who": sid, "pre": pre_st})
			"resisted", "immune":
				var rid = ev.get("id")
				say.call(rid, t, _pos_at(c, rid, t), et, Color("c4ccc6"))
			"room_bloom":
				# the room answers the tender: petals thrown round it, and the
				# bonus said ABOVE the tender's own numbers (the cleanse's +1 sits
				# on the tile beside it)
				var bp := _pos_at(c, "player", t)
				L.clip(c, {"kind": "burst", "t0": t, "dur": 700, "at": bp, "col": Color(0.93, 0.66, 0.80)})
				# the pod the room drops (a new tile that carries an item) springs
				# up with the bloom instead of appearing when the step ends, and
				# the bonus is said over it - the room's reward in one place
				var said_at := bp + Vector2(0, -0.55)
				var sw_all: Dictionary = reel["tswap"]
				for p in sw_all:
					var td = c["post"]["terrain"].get(p)
					if String(sw_all[p]["pre"]) == "" and not sw_all[p].has("t") and td is Dictionary and td.has("item"):
						L.reveal(c, p, t + 200)
						L.clip(c, {"kind": "tile_pop", "t0": t + 200, "dur": 380, "at": p, "col": Color("f7d85a"),
							"layer": "ground"})
						L.clip(c, {"kind": "spark", "t0": t + 200, "dur": 320, "at": p, "col": Color("f7d85a"), "n": 6})
						said_at = Vector2(p)
						break
				say.call("bloom", t + 200, said_at, "BLOOM +%d" % int(ev.get("bonus", 2)), Color("f7d85a"))
			"bounty":
				say.call("player", t + 80, _pos_at(c, "player", t), "+%d bloom" % int(ev.get("bloom", 0)), Color("f7d85a"))
			"stairs_awaken":
				if ev.get("tile") is Vector2i and (ev["tile"] as Vector2i).x >= 0:
					L.clip(c, {"kind": "burst", "t0": t, "dur": 700, "at": ev["tile"], "col": Color("e8c840")})
			"floor_restored":
				# the whole floor turns: a wave of green rolls out from the tender
				# along the ground (not a second burst stacked on the room's)
				if not restored:
					restored = true
					var fp := _pos_at(c, "player", t)
					L.clip(c, {"kind": "ring", "t0": t + 60, "dur": 640, "at": fp, "r0": 0.6, "r1": 4.5,
						"col": Color(0.66, 0.93, 0.52), "w": 0.11, "layer": "ground"})
					L.clip(c, {"kind": "ring", "t0": t + 180, "dur": 600, "at": fp, "r0": 0.5, "r1": 3.4,
						"col": Color(0.82, 0.97, 0.7), "w": 0.06, "layer": "ground"})
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
				say.call("player", t, _pos_at(c, "player", t), "tithe", Color("f7d85a"))
			"gummed":
				say.call("player", t + 40, _pos_at(c, "player", t), "gummed", Color("d9b54a"))
			"drain":
				say.call("player", t + 60, _pos_at(c, "player", t), "-%d charge" % int(ev.get("amt", 0)), Color("f7c948"))
			"anchored":
				say.call("player", t, _pos_at(c, "player", t), "anchored", Color("dcb880"))
			"item_pickup":
				L.clip(c, {"kind": "item", "t0": t, "dur": 520, "at": c["p1"], "id": String(ev.get("id", "")),
					"use": "pickup"})
			"boss_phase", "ignite_all", "flood", "smoke_burst", "assimilate":
				reel["shakes"].append({"t0": t, "mag": L.SHAKE_BIG})
	# A status that runs out during the step (a stun spent on the struggle it
	# caused, spores that ticked their last, a stunned machine killed) is
	# already gone from the post board, so the overlay - which draws the post
	# board - would drop it at t = 0, before the struggle it explains. A hold
	# clip keeps drawing it until the moment it is spent.
	for id in c["pre_en"]:
		var pe: Dictionary = c["pre_en"][id]
		var post_e = c["post_en"].get(id)
		var keep := {}
		var until := -1
		for st in pe.get("status", {}):
			if not Content.STATUSES.has(st) or int(pe["status"][st]) <= 0:
				continue
			if post_e != null and int(post_e.get("status", {}).get(st, 0)) > 0:
				continue
			var spent := -1
			var blocked_ev := String(Content.STATUSES[st].get("blocked_event", st))
			for i in evs.size():
				var ev: Dictionary = evs[i]
				if not L.same_id(ev.get("id"), id):
					continue
				var et := String(ev.get("t", ""))
				if et == blocked_ev:
					spent = maxi(spent, int(c["times"][i]) + 380)
				elif et == "damage" and String(ev.get("src", "")) == st:
					spent = maxi(spent, int(c["times"][i]) + 160)
				elif et == "death":
					spent = maxi(spent, int(c["times"][i]) + 30)
			if spent < 0:
				spent = t_end
			keep[st] = int(pe["status"][st])
			until = maxi(until, spent)
		if not keep.is_empty() and until > 0:
			L.clip(c, {"kind": "status_hold", "t0": 0, "dur": until, "at": Vector2(pe["pos"]), "who": id,
				"status": keep, "layer": "air"})


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


## The backstop behind every builder: a creature whose last drawn position is
## not the tile the post snapshot holds is walked there after its last
## segment, so no reel can ever leave a body drawn off its sim tile.
static func _land_all(c: Dictionary) -> void:
	var tracks: Dictionary = c["reel"]["tracks"]
	var goals := {"player": Vector2(c["p1"])}
	for id in c["post_en"]:
		goals[id] = Vector2(c["post_en"][id]["pos"])
	for key in goals:
		if not tracks.has(key):
			continue
		var last = null
		var end := 0
		for s in tracks[key]:
			if String(s["kind"]) == "path":
				var s_end := int(s["t0"]) + int(s["dur"])
				if s_end >= end:
					end = s_end
					last = (s["pts"] as Array)[(s["pts"] as Array).size() - 1]
		if last != null and (last as Vector2).distance_to(goals[key]) > 0.01:
			tracks[key].append({"kind": "path", "t0": end, "dur": 120, "pts": [last, goals[key]], "hop": 0.0})


static func _length(reel: Dictionary) -> int:
	var n := 0
	for cl in reel["clips"]:
		n = maxi(n, int(cl["t0"]) + int(cl["dur"]))
	for key in reel["tracks"]:
		for s in reel["tracks"][key]:
			n = maxi(n, int(s["t0"]) + int(s["dur"]))
	for s in reel["shakes"]:
		n = maxi(n, int(s["t0"]) + 320)
	# a tile flip is part of the reel: playback must still be running when
	# the last one lands, or the board would sit on its pre-step look
	for p in reel["tswap"]:
		n = maxi(n, int(reel["tswap"][p].get("t", 0)) + 1)
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
		reel["dim"] = {}
		for i in reel["ev_t"].size():
			reel["ev_t"][i] = 0
		for p in reel["tswap"]:
			reel["tswap"][p]["t"] = 0
		reel["len"] = L.T_FLOAT if not keep.is_empty() else 0
		return
	for cl in reel["clips"]:
		cl["t0"] = int(float(cl["t0"]) * k)
		# numbers and words keep their reading time
		if String(cl["kind"]) != "float" and not bool(cl.get("read", false)):
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
	for i in reel["ev_t"].size():
		reel["ev_t"][i] = int(float(reel["ev_t"][i]) * k)
	for d in reel.get("dim", {}).get("at", []):
		d[0] = int(float(d[0]) * k)
	reel["len"] = _length(reel)


## Two reels back to back: `b` is a step taken by the same input right after
## `a` (an out-of-charge tap ends the turn, then moves), offset to start when
## `a` ends and merged in. b's pre board is a's post board, so every
## creature's segments simply continue; a tile both steps changed shows a's
## old kind until a's flip and b's final kind after it.
static func chain(a: Dictionary, b: Dictionary) -> Dictionary:
	if a.is_empty():
		return b
	if b.is_empty():
		return a
	var off := int(a.get("len", 0))
	var out: Dictionary = a.duplicate(true)
	for cl in b["clips"]:
		var c2: Dictionary = cl.duplicate(true)
		c2["t0"] = int(c2["t0"]) + off
		out["clips"].append(c2)
	for key in b["tracks"]:
		if not out["tracks"].has(key):
			out["tracks"][key] = []
		for s in b["tracks"][key]:
			var s2: Dictionary = s.duplicate(true)
			s2["t0"] = int(s2["t0"]) + off
			out["tracks"][key].append(s2)
	for g in b["ghosts"]:
		var g2: Dictionary = g.duplicate(true)
		g2["t_die"] = int(g2["t_die"]) + off
		out["ghosts"].append(g2)
	for id in b["spawns"]:
		out["spawns"][id] = int(b["spawns"][id]) + off
	for s in b["shakes"]:
		out["shakes"].append({"t0": int(s["t0"]) + off, "mag": s["mag"]})
	for p in b["tswap"]:
		var sb: Dictionary = b["tswap"][p]
		if out["tswap"].has(p):
			out["tswap"][p]["post"] = sb["post"]
		else:
			out["tswap"][p] = {"pre": sb["pre"], "post": sb["post"], "t": int(sb.get("t", 0)) + off}
	for key in b.get("hp", {}):
		if not out["hp"].has(key):
			out["hp"][key] = []
		for h in b["hp"][key]:
			out["hp"][key].append([int(h[0]) + off, h[1]])
	for t in b.get("ev_t", []):
		out["ev_t"].append(int(t) + off)
	if out.get("dim", {}).is_empty():
		out["dim"] = b.get("dim", {}).duplicate(true)
	else:
		for d in b.get("dim", {}).get("at", []):
			out["dim"]["at"].append([int(d[0]) + off, d[1]])
	out["len"] = _length(out)
	return out


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
##   wash   a colour laid OVER the body (its alpha is the strength): a hurt
##          red, a heal green, any strongly coloured tint segment
##   aura   a glow AROUND the body (alpha = strength): a cast's wind-up
##   visible  false while hidden (not yet spawned, dissolved, dead)
static func pose(reel: Dictionary, key, t: float, cur: Vector2) -> Dictionary:
	var out := {"pos": cur, "lift": 0.0, "off": Vector2.ZERO, "sx": 1.0, "sy": 1.0, "rot": 0.0,
		"alpha": 1.0, "flash": 0.0, "tint": Color(1, 1, 1), "visible": true,
		"wash": Color(1, 1, 1, 0), "aura": Color(1, 1, 1, 0)}
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
					# stretched while rising and falling, rounder at the top
					var v := absf(sin(f * TAU))
					out["sy"] *= 1.0 + 0.15 * v + 0.03 * arc
					out["sx"] *= 1.0 - 0.08 * v
			"squash":
				var q := sin(k * PI)
				out["sy"] *= 1.0 - 0.18 * q
				out["sx"] *= 1.0 + 0.13 * q
			"lunge":
				# a wind-back, a snap forward (peak a third in), a hold, the return
				var a := 0.0
				if k < 0.14:
					a = -0.28 * sin(k / 0.14 * PI * 0.5)
				elif k < 0.34:
					a = lerpf(-0.28, 1.0, _ease_out((k - 0.14) / 0.2))
				elif k < 0.44:
					a = 1.0
				else:
					a = 1.0 - _ease_io((k - 0.44) / 0.56)
				var dv: Vector2 = s["dir"]
				out["off"] += dv * float(s.get("reach", 0.3)) * a
				if a >= 0.0:
					if absf(dv.x) >= absf(dv.y):
						out["sx"] *= 1.0 + 0.12 * a
						out["sy"] *= 1.0 - 0.05 * a
					else:
						out["sy"] *= 1.0 + 0.12 * a
						out["sx"] *= 1.0 - 0.05 * a
				else:
					out["sy"] *= 1.0 + 0.35 * a  # the crouch before the spring
					out["sx"] *= 1.0 - 0.25 * a
				out["rot"] += dv.x * 0.12 * a
			"recoil":
				# knocked back along the blow, squashed and rocked by it, and
				# white-hot for the first frames
				var r := (k / 0.16) if k < 0.16 else 1.0 - _ease_io((k - 0.16) / 0.84)
				r = clampf(r, 0.0, 1.0)
				var dv: Vector2 = s["dir"]
				out["off"] += dv * float(s.get("amt", 0.15)) * r
				out["sx"] *= 1.0 + 0.08 * r
				out["sy"] *= 1.0 - 0.08 * r
				out["rot"] += dv.x * 0.14 * r
				out["flash"] = maxf(out["flash"], 1.0 if k < 0.2 else clampf(1.0 - (k - 0.2) / 0.32, 0.0, 1.0))
			"tint":
				var col: Color = s["col"]
				# a strongly coloured tint is laid OVER the body (a multiply alone
				# turns a red hurt brown on a green tender); a dull one darkens
				var sat := maxf(col.r, maxf(col.g, col.b)) - minf(col.r, minf(col.g, col.b))
				if s.has("hold"):
					# a HURT: the body is pulled toward the colour (the multiply
					# kills the green under a red) and the colour laid over it at
					# full strength until `hold`, then it snaps back in a few
					# frames - a slow fade of red over green reads orange, then
					# olive, for a quarter of a second
					var env := 1.0 - _ease_io((k - float(s["hold"])) / 0.22)
					out["tint"] = (out["tint"] as Color) * Color(1, 1, 1).lerp(col, 0.6 * env)
					var wh := 0.86 * sat * env
					if wh > (out["wash"] as Color).a:
						out["wash"] = Color(col.r, col.g, col.b, wh)
				else:
					out["tint"] = col.lerp(Color(1, 1, 1), maxf(k, sat))
					var wa := 0.9 * sat * (1.0 - _ease_io((k - 0.2) / 0.8))
					if wa > (out["wash"] as Color).a:
						out["wash"] = Color(col.r, col.g, col.b, wa)
			"flash":
				out["flash"] = maxf(out["flash"], 1.0 if k < 0.3 else 1.0 - (k - 0.3) / 0.7)
			"cast":
				# gather (squash, the glow of the ability's colour rising), then
				# release (stretch up), then settle
				var aa := 0.0
				if k < 0.45:
					var g := sin(k / 0.45 * PI * 0.5)
					out["sy"] *= 1.0 - 0.13 * g
					out["sx"] *= 1.0 + 0.10 * g
					aa = 0.85 * g
				else:
					var r2 := sin((k - 0.45) / 0.55 * PI)
					out["sy"] *= 1.0 + 0.14 * r2
					out["sx"] *= 1.0 - 0.07 * r2
					out["lift"] += 0.06 * r2
					aa = 0.85 * (1.0 - (k - 0.45) / 0.55)
				if s.has("col") and aa > (out["aura"] as Color).a:
					var cc: Color = s["col"]
					out["aura"] = Color(cc.r, cc.g, cc.b, aa)
			"struggle":
				out["off"] += Vector2(sin(k * PI * 7.0) * 0.09 * (1.0 - k), 0)
			"die":
				var dd: Vector2 = s.get("dir", Vector2.ZERO)
				var side := -1.0 if dd.x < -0.01 else 1.0
				if String(s.get("style", "")) == "wilt":
					# the tender wilts: it droops and yellows, collapses, fades
					var droop := _ease_io(k / 0.3)
					var fu := clampf((k - 0.3) / 0.38, 0.0, 1.0)
					var fall := fu * fu
					out["rot"] += side * (0.3 * droop + 0.95 * fall)
					out["sy"] *= (1.0 - 0.12 * droop) * (1.0 - 0.5 * fall)
					out["sx"] *= 1.0 + 0.22 * fall
					out["tint"] = (out["tint"] as Color) * Color(1, 1, 1).lerp(Color(0.78, 0.66, 0.36), droop)
					out["alpha"] *= 1.0 - clampf((k - 0.62) / 0.38, 0.0, 1.0)
				elif k < 0.16:
					# a machine dies: it swells white for a beat...
					var sw := sin(k / 0.16 * PI)
					out["sx"] *= 1.0 + 0.1 * sw
					out["sy"] *= 1.0 + 0.1 * sw
					out["flash"] = maxf(out["flash"], 0.65)
				else:
					# ...then tips over away from the blow, crumples and fades
					var u := (k - 0.16) / 0.84
					var e := u * u
					out["rot"] += side * 1.2 * _ease_io(u)
					out["sy"] *= 1.0 - 0.6 * e
					out["sx"] *= 1.0 - 0.3 * e
					out["off"] += dd * 0.1 * _ease_out(u)
					out["alpha"] *= 1.0 - clampf((u - 0.25) / 0.75, 0.0, 1.0)
					out["flash"] = maxf(out["flash"], 0.65 * clampf(1.0 - u / 0.2, 0.0, 1.0))
			"pop":
				# springs out of nothing, overshoots, settles; white as it appears
				var p := 1.15 * _ease_out(k / 0.6) if k < 0.6 else 1.15 - 0.15 * _ease_io((k - 0.6) / 0.4)
				out["sx"] *= maxf(0.05, p)
				out["sy"] *= maxf(0.05, p)
				out["alpha"] *= minf(1.0, k * 4.0)
				out["flash"] = maxf(out["flash"], clampf(1.0 - k / 0.45, 0.0, 1.0))
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


## The dim stage to SHOW at reel time t: the pre-step stage until an undim or
## smog_dim event lands, so the haze parts when the sunbeam reaches it.
static func dim_shown(reel: Dictionary, t: float, dim_now: int) -> int:
	var d: Dictionary = reel.get("dim", {})
	if d.is_empty() or not playing(reel, t):
		return dim_now
	var shown := int(d.get("pre", dim_now))
	for e in d.get("at", []):
		if float(e[0]) <= t:
			shown = int(e[1])
	return shown


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
## function of the wall clock `now` (ms) and a per-creature phase. Small on
## purpose: the board has to read as alive without anything drawing the eye
## away from what is about to happen.
static func idle(style: String, phase: float, now: float) -> Dictionary:
	var s := now / 1000.0 + phase
	var out := {"lift": 0.0, "sx": 1.0, "sy": 1.0, "rot": 0.0, "dx": 0.0}
	match style:
		"player":
			# a slow breath and a sapling's sway in a breeze
			var b := sin(s * TAU / 3.2)
			out["lift"] = 0.015 + 0.015 * b
			out["sy"] = 1.0 + 0.028 * b
			out["sx"] = 1.0 - 0.014 * b
			out["rot"] = 0.022 * sin(s * TAU / 4.7)
		"heave":
			# a boss: a slow, heavy swell of the whole hull
			var h := sin(s * TAU / 2.4)
			out["sy"] = 1.0 + 0.04 * h
			out["sx"] = 1.0 + 0.022 * h
		"hover":
			out["lift"] = 0.1 + 0.05 * sin(s * TAU / 1.3)
			out["rot"] = 0.05 * sin(s * TAU / 2.3)
			out["dx"] = 0.02 * sin(s * TAU / 3.1)
		"pant":
			# quick shallow breaths
			var p := absf(sin(s * TAU / 0.9))
			out["sy"] = 1.0 + 0.035 * p
			out["sx"] = 1.0 - 0.012 * p
			out["lift"] = 0.012 * p
		"ooze":
			# a blob that never quite settles
			var o := sin(s * TAU / 1.5)
			var o2 := sin(s * TAU / 0.75 + 1.0)
			out["sy"] = 1.0 + 0.06 * o + 0.012 * o2
			out["sx"] = 1.0 - 0.05 * o
		"chug":
			# an engine idling, and every so often a piston kick
			var ch := sin(s * TAU / 0.4)
			var kick := pow(maxf(0.0, sin(s * TAU / 1.7)), 12.0)
			out["dx"] = 0.01 * ch
			out["sy"] = 1.0 + 0.012 * absf(ch) + 0.045 * kick
			out["sx"] = 1.0 - 0.025 * kick
			out["lift"] = 0.015 * kick
		"skitter":
			# still, then a burst of scrabbling legs
			var cyc := fposmod(s / 1.9, 1.0)
			var burst := sin(cyc / 0.3 * PI) if cyc < 0.3 else 0.0
			out["dx"] = 0.035 * sin(s * TAU / 0.18) * burst
			out["lift"] = 0.02 * absf(sin(s * TAU / 0.18)) * burst
			out["sy"] = 1.0 + 0.012 * sin(s * TAU / 1.2)
		"sway":
			out["rot"] = 0.05 * sin(s * TAU / 2.2)
			out["dx"] = 0.01 * sin(s * TAU / 2.2 - 0.5)
		"lumber":
			# heavy plating: a slow shift of weight from foot to foot
			var w := sin(s * TAU / 2.8)
			out["rot"] = 0.025 * w
			out["dx"] = 0.012 * w
			out["sy"] = 1.0 + 0.02 * absf(sin(s * TAU / 2.8))
		"gulp":
			# a spitter working up a mouthful: a swallow every couple of seconds
			var cyc := fposmod(s / 2.1, 1.0)
			var g := sin(cyc / 0.22 * PI) if cyc < 0.22 else 0.0
			var bb := sin(s * TAU / 1.6)
			out["sy"] = 1.0 - 0.05 * g + 0.012 * bb
			out["sx"] = 1.0 + 0.06 * g
			out["lift"] = 0.01 + 0.01 * bb
		_:
			var bb := sin(s * TAU / 1.8)
			out["lift"] = 0.012 + 0.012 * bb
			out["sy"] = 1.0 + 0.018 * bb
			out["rot"] = 0.015 * sin(s * TAU / 3.7)
	return out


static func _ease_out(k: float) -> float:
	return 1.0 - (1.0 - k) * (1.0 - k)


static func _ease_io(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)
