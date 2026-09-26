extends RefCounted
## Verb family: LINES - effects that travel a straight line from the tender.
##   lance      light gathers into a glint at the tender's front, then a
##              lance of sunlight races down the line - white-hot core, gold
##              body, orange edge, heat shimmer and motes - lighting the oil it
##              crosses and bursting on the body it stops at. A `pierce` beam
##              is a needle that punches THROUGH every body (a flash bar on
##              each, sparks out the far side); more damage (noon) is a wider,
##              brighter beam and a bigger burst, and a clear-sky bonus shows
##              as a corona round the tender while it gathers
##   pull       a tendril coils back, lashes out in a travelling wave, its leaf
##              hook bites and wraps the target, and the target is reeled in
##              with the tip riding it; then the lash cracks down on it. More
##              damage is a thicker, thornier vine and a bigger crack
##   pull_line  a three-tined rake reaches the whole line, digs in and is
##              dragged back, collecting every body it passes and furrowing
##              the ground behind it
##   wash_push  a pressurised stream with a foaming head and spray: washed
##              tiles splash clean as it passes, the first body is shoved and
##              slides with the stream on its back, and the slam splashes
##              exactly when the collision damage lands. push/collision set
##              the stream's weight, range its length
##   push_line  wind streamlines and tumbling leaves and dust race down the
##              line, blow cleared smoke away and shove the first body; a
##              heavier shove is a thicker bundle carrying more debris
##   dash_dir   the tender rides a rising gust: dust kicked up behind, a
##              column of wind at lift-off (taller for more range), a helix
##              round the rider, speed lines and afterimages, a landing puff
## build(op, c) lays the clips/segments and claims events (see shell/anim.gd);
## paint(cv, clip, k, V) draws this family's KINDS. shove() is shared with
## the areas family and keeps its original look there (the plain spark).
##
## Every clip carries `span`, its length in FULL-SPEED ms, and the painters
## read time as k * span: the director rescales a clip's t0/dur (and every
## track) for the quick setting, so internal beats stored in full-speed ms
## (a beam's travel, a vine's keyframes) stay locked to the bodies they ride.

const L := preload("res://shell/anim_lib.gd")
const D := preload("res://shell/anim_draw.gd")
const Art := preload("res://shell/svg_art.gd")
const Content := preload("res://sim/content.gd")

const OPS := ["lance", "pull", "pull_line", "wash_push", "push_line", "dash_dir"]
const KINDS := ["beam", "lance_glint", "lance_hit", "vine", "vine_crack", "vine_furrow", "jet", "jet_head",
	"line_slam", "gust", "gust_puff", "dash_trail", "dash_dust"]

const GLINT_MS := 120   # the lance's glint gathers (inside the cast wind-up)
const BEAM_MS := 24     # per tile the beam's head travels
const BEAM_HOLD := 110  # the beam burns at full strength once it lands
const BEAM_FADE := 150  # then its tail races after its head
const VINE_COIL := 60   # the vine draws back before it strikes
const VINE_MS := 42     # per tile the vine reaches
const VINE_BITE := 70   # the hook bites and wraps before the haul
const VINE_SNAP := 150  # the vine whips back to the hand
const RAKE_DIG := 60    # the rake's tines dig in at full reach
const JET_MS := 34
const JET_HOLD := 70    # the stream keeps pressing after the shove settles
const JET_CUT := 140    # then the tail detaches and chases the head
const JAM_MS := 60      # a body shoved into something it cannot move strains this long
const GUST_MS := 30
const SHOVE_MS := 70    # per tile a shoved or reeled body slides
const DASH_MS := 60     # per tile the tender rides the updraft

const DUST := Color(0.74, 0.68, 0.56)
const LEAF := Color(0.62, 0.78, 0.36)
const INK := Color(0.04, 0.08, 0.04)


static func build(op: String, c: Dictionary) -> int:
	match op:
		"lance":
			return _lance(c)
		"pull":
			return _pull(c)
		"pull_line":
			return _pull_line(c)
		"wash_push":
			return _wash(c, true)
		"push_line":
			return _wash(c, false)
		"dash_dir":
			return _dash(c)
	return int(c["t"])


static func _dir(c: Dictionary) -> Vector2i:
	var d = c.get("target")
	return d if d is Vector2i else Vector2i(1, 0)


## A clip whose painter reads full-speed time (see the header).
static func _clip(c: Dictionary, d: Dictionary) -> Dictionary:
	d["span"] = int(d.get("dur", 300))
	return L.clip(c, d)


# --- lance ----------------------------------------------------------------------

## The beam's weight: the damage it deals as the sim ran it (noon's clear-sky
## bonus included), so a heavier variant draws a heavier beam.
static func _lance_power(c: Dictionary) -> int:
	var eff: Dictionary = c["eff"]
	var p := int(eff.get("dmg", 2))
	if int(c["pre"].get("dim", 0)) == 0:
		p += int(eff.get("clear_smog_bonus", 0))
	return p


static func _lance(c: Dictionary) -> int:
	var t: int = c["t"]
	var o: Vector2i = c["ppos"]
	var d := _dir(c)
	var dv := Vector2(d)
	var eff: Dictionary = c["eff"]
	var pierce := bool(eff.get("pierce", false))
	var rng := int(c["adef"].get("range", 3))
	var tiles := L.line(c["pre"], o, d, rng, not pierce, true)
	var n := tiles.size()
	var power := _lance_power(c)
	var sun := int(eff.get("clear_smog_bonus", 0)) > 0 and int(c["pre"].get("dim", 0)) == 0
	var last: Vector2i = tiles[n - 1] if n > 0 else o
	var bodies: Array = []
	for p in tiles:
		if L.enemy_at(c["pre"], p) != null:
			bodies.append(p)
	# how the shaft ends: in a body's face, against a wall or a beam-blocking
	# tile (smoke), or tapering off into open air at the end of its range
	var start := 0.3
	var stop := "air"
	var reach := float(n) + 0.42
	if not pierce and not bodies.is_empty():
		stop = "body"
		reach = float(n) - 0.3
	elif n < rng:
		stop = "wall" if L.wall(c["pre"], last + d) else "block"
		reach = float(n) + 0.5
	var tf := t + 20
	var travel := maxi(40, int((reach - start) * BEAM_MS))
	var g0 := maxi(0, tf - GLINT_MS)
	_clip(c, {"kind": "lance_glint", "t0": g0, "dur": tf - g0 + 170, "fire": tf - g0, "at": o,
		"pos": Vector2(o) + dv * 0.34, "center": Vector2(o), "dir": dv, "power": power, "sun": sun})
	_clip(c, {"kind": "beam", "t0": tf, "dur": travel + BEAM_HOLD + BEAM_FADE, "layer": "ground",
		"from": Vector2(o) + dv * start, "to": Vector2(o) + dv * reach, "dir": dv, "travel": travel,
		"power": power, "pierce": pierce, "at": o})
	var when := {}
	for j in n:
		when[tiles[j]] = tf + int((float(j + 1) - start) * BEAM_MS)
	# a body is struck the moment the head reaches its near face
	var face := {}
	for p in bodies:
		face[p] = tf + int((float(L.man(o, p)) - 0.3 - start) * BEAM_MS)
	_claim_on_line(c, when, dv, face)
	for i in range(int(c.get("ev0", 0)), int(c.get("ev1", c["events"].size()))):
		var ev: Dictionary = c["events"][i]
		if String(ev.get("t", "")) == "ignite" and when.has(ev.get("tile")):
			_clip(c, {"kind": "lance_hit", "t0": int(when[ev["tile"]]) - 10, "dur": 260, "at": ev["tile"],
				"pos": Vector2(ev["tile"]), "dir": dv, "power": power, "style": "ignite"})
	for p in bodies:
		var th: int = face[p]
		_clip(c, {"kind": "lance_hit", "t0": th, "dur": 320, "at": p,
			"pos": Vector2(p) + (Vector2.ZERO if pierce else -dv * 0.3), "dir": dv, "power": power,
			"style": "pierce" if pierce else "stop"})
		if power >= 3:
			c["reel"]["shakes"].append({"t0": th, "mag": 1.0 + 0.6 * float(power)})
	if stop == "wall" or stop == "block":
		_clip(c, {"kind": "lance_hit", "t0": tf + travel, "dur": 280, "at": last,
			"pos": Vector2(o) + dv * reach, "dir": dv, "power": power, "style": stop})
	return tf + travel + 90


## Claim the cast's events that happen ON the line at the moment the effect
## reaches each tile: hits (with the line's direction; at `face` when given),
## ignitions, washes, cleared smoke and the hooks those set off.
static func _claim_on_line(c: Dictionary, when: Dictionary, d: Vector2, face: Dictionary = {}) -> void:
	var evs: Array = c["events"]
	var aid := String(c["aid"])
	for i in L.unclaimed(c, ["damage", "ignite", "wash", "smoke_cleared", "hook"]):
		var ev: Dictionary = evs[i]
		var tt := String(ev["t"])
		if tt == "damage":
			if String(ev.get("who", "")) == "player" or String(ev.get("src", "")) != aid:
				continue
			var e = c["pre_en"].get(ev.get("id"))
			if e != null and face.has(e["pos"]):
				L.claim(c, i, int(face[e["pos"]]), d)
			elif e != null and when.has(e["pos"]):
				L.claim(c, i, int(when[e["pos"]]) + 15, d)
		elif ev.get("tile") is Vector2i and when.has(ev["tile"]):
			L.claim(c, i, int(when[ev["tile"]]))
			L.reveal(c, ev["tile"], int(when[ev["tile"]]))


# --- vine -----------------------------------------------------------------------

static func _pull(c: Dictionary) -> int:
	var t: int = c["t"]
	var o: Vector2i = c["ppos"]
	var tgt = c.get("target")
	if not (tgt is Vector2i):
		return t
	var e = L.enemy_at(c["pre"], tgt)
	var dv := L.dir_of(o, tgt)
	if dv == Vector2.ZERO:
		dv = Vector2.UP
	var s := Vector2(-dv.y, dv.x)
	var hand := Vector2(o) + dv * 0.2
	var land: Vector2i = tgt
	if e != null:
		land = _pull_land(c, e, o, _occupancy(c))
	var steps := L.man(tgt, land)
	var t_hook := t + VINE_COIL + maxi(1, L.man(o, tgt)) * VINE_MS
	var t_drag := t_hook + VINE_BITE
	var t_land := t_drag + steps * SHOVE_MS
	var t_crack := t_land + (20 if steps > 0 else 60)
	var t_free := t_crack + 30
	var keys: Array = [
		[0, hand, 0],
		[VINE_COIL, Vector2(o) - dv * 0.2 + s * 0.28, 1],
		[t_hook - t, Vector2(tgt), 1],
		[t_drag - t, Vector2(tgt), 0],
		[t_land - t, Vector2(land), 0],
		[t_free - t, Vector2(land), 0],
		[t_free - t + VINE_SNAP, hand, 2],
	]
	var power := int(c["eff"].get("dmg", 2))
	_clip(c, {"kind": "vine", "t0": t, "dur": t_free - t + VINE_SNAP + 30, "at": o, "hand": hand, "keys": keys,
		"bite": t_hook - t, "free": t_free - t, "dir": dv, "power": power,
		"catches": [{"hook": t_hook - t, "free": t_free - t, "coil": true, "at": Vector2(tgt)}]})
	if e != null:
		_reel_in(c, e, tgt, land, t_hook, t_drag, t_crack, dv)
		_clip(c, {"kind": "vine_crack", "t0": t_crack - 70, "dur": 330, "at": land, "hit": 70, "dir": dv,
			"power": power})
	return t_crack + 60


## The body hooked at `from` is jerked, hauled to `land` from t_drag and
## cracked at t_crack; its events land on those beats.
static func _reel_in(c: Dictionary, e: Dictionary, from: Vector2i, land: Vector2i, t_hook: int, t_drag: int,
		t_crack: int, away: Vector2) -> void:
	var steps := L.man(from, land)
	L.seg(c, e["id"], {"kind": "shake", "t0": t_hook, "dur": VINE_BITE + 20, "amt": 0.05})
	if steps > 0:
		L.move(c, e["id"], L.path(c["pre"], from, land), t_drag, steps * SHOVE_MS, 0.0)
		L.seg(c, e["id"], {"kind": "squash", "t0": t_drag + steps * SHOVE_MS - 10, "dur": 110})
	else:
		# it will not come: it strains against the vine
		L.seg(c, e["id"], {"kind": "lunge", "t0": t_hook, "dur": t_crack - t_hook, "dir": -away, "reach": 0.16})
	for i in L.unclaimed(c, ["damage", "status", "hook", "staggered"]):
		var ev: Dictionary = c["events"][i]
		if ev.get("id") != e["id"]:
			continue
		var src := String(ev.get("src", ""))
		if String(ev["t"]) == "staggered":
			L.claim(c, i, t_drag + steps * SHOVE_MS)
		elif String(ev["t"]) == "damage" and src.contains(":"):
			# terrain crossed mid-haul bites on the way
			L.claim(c, i, t_drag + steps * SHOVE_MS / 2, -away)
		else:
			L.claim(c, i, t_crack, away)


static func _pull_line(c: Dictionary) -> int:
	var t: int = c["t"]
	var o: Vector2i = c["ppos"]
	var d := _dir(c)
	var dv := Vector2(d)
	var s := Vector2(-dv.y, dv.x)
	var tiles := L.line(c["pre"], o, d, int(c["adef"].get("range", 3)), false, false)
	var far_d := maxi(1, tiles.size())
	var hand := Vector2(o) + dv * 0.2
	var t_far := t + VINE_COIL + far_d * VINE_MS
	var t_ret := t_far + RAKE_DIG
	# the head comes home at a body's haul speed, so what it catches rides it
	var t_home := t_ret + int((float(far_d) - 0.2) * SHOVE_MS)
	var keys: Array = [
		[0, hand, 0],
		[VINE_COIL, Vector2(o) - dv * 0.2 + s * 0.28, 1],
		[t_far - t, Vector2(o) + dv * (float(far_d) + 0.15), 1],
		[t_ret - t, Vector2(o) + dv * float(far_d), 3],
		[t_home - t, hand, 0],
	]
	var power := int(c["eff"].get("dmg", 2))
	var catches: Array = []
	var t_end := t_home
	var occ := _occupancy(c)
	for p in tiles:
		var e = L.enemy_at(c["pre"], p)
		if e == null:
			continue
		var land := _pull_land(c, e, o, occ)
		var t_b := t_ret + (far_d - L.man(o, p)) * SHOVE_MS
		var steps := L.man(p, land)
		var t_crack := t_b + steps * SHOVE_MS + (15 if steps > 0 else 50)
		catches.append({"hook": t_b - t, "free": t_b + steps * SHOVE_MS - t, "coil": false, "at": Vector2(p)})
		_reel_in(c, e, p, land, t_b, t_b, t_crack, dv)
		_clip(c, {"kind": "vine_crack", "t0": t_crack - 60, "dur": 300, "at": land, "hit": 60, "dir": dv,
			"power": power, "small": true})
		t_end = maxi(t_end, t_crack + 40)
	_clip(c, {"kind": "vine", "t0": t, "dur": t_home - t + 60, "at": o, "hand": hand, "keys": keys,
		"bite": t_far - t, "free": t_home - t, "dir": dv, "power": power, "rake": true, "catches": catches})
	_clip(c, {"kind": "vine_furrow", "t0": t_ret, "dur": t_home - t_ret + 360, "layer": "ground", "at": o,
		"far": Vector2(o) + dv * (float(far_d) + 0.3), "keys": keys, "t_ret": t_ret - t, "dir": dv,
		"origin": t_ret - t})
	return t_end


## Every enemy's tile on the pre board, for pulls that walk bodies in turn.
static func _occupancy(c: Dictionary) -> Dictionary:
	var occ := {}
	for e in c["pre"]["enemies"]:
		occ[e["pos"]] = e["id"]
	return occ


## Where a pulled enemy ends: its post tile, or - when the pull killed it -
## the sim's own haul replayed (Game._pull_one): step toward the tender while
## it is not adjacent and the next tile is open, paying each tile's entry
## damage, and dying where that runs out. `occ` is the board as the pulls
## before this one left it (a rake hauls nearest first) and is updated.
static func _pull_land(c: Dictionary, e: Dictionary, o: Vector2i, occ: Dictionary) -> Vector2i:
	var from: Vector2i = e["pos"]
	var p := from
	var pe = c["post_en"].get(e["id"])
	if pe != null:
		p = pe["pos"]
	elif not L.massive(String(e["kind"])):
		var d := Vector2i(signi(o.x - p.x), signi(o.y - p.y))
		var hp := int(e.get("hp", 1))
		for i in int(c["eff"].get("dist", 2)):
			if L.man(p, o) <= 1:
				break
			var nxt := p + d
			if L.wall(c["pre"], nxt) or nxt == o or occ.get(nxt, e["id"]) != e["id"]:
				break
			var tk := L.tkind(c["pre"], nxt)
			if tk != "" and bool(Content.terrain(tk, "blocks", false)):
				break
			p = nxt
			hp -= int(Content.terrain(tk, "enter_dmg_enemy", 0))
			if hp <= 0:
				break
	occ.erase(from)
	occ[p] = e["id"]
	return p


# --- jet / gust -----------------------------------------------------------------

static func _wash(c: Dictionary, water: bool) -> int:
	var t: int = c["t"]
	var o: Vector2i = c["ppos"]
	var d := _dir(c)
	var dv := Vector2(d)
	var eff: Dictionary = c["eff"]
	var rng := int(c["adef"].get("range", 2))
	var tiles := L.line(c["pre"], o, d, rng, false, false)
	var n := tiles.size()
	var per := JET_MS if water else GUST_MS
	var body = null
	var bj := -1
	for j in n:
		var e = L.enemy_at(c["pre"], tiles[j])
		if e != null:
			body = e
			bj = j
			break
	var start := 0.34
	var end_d := float(n) + (0.5 if n < rng else 0.42)
	var when := {}
	for j in n:
		when[tiles[j]] = t + int((float(j + 1) - start) * per)
	# the gust stops at the first body (the sim clears no smoke beyond it)
	if not water and body != null:
		for j in range(bj + 1, n):
			when.erase(tiles[j])
	_claim_on_line(c, when, dv)
	if not water:
		_blow_smoke(c, dv, when)
	var push := int(eff.get("push", eff.get("dist", 1)))
	var coll := int(eff.get("collision_dmg", 1))
	var weight := push + coll
	var keys: Array = [[0, Vector2(o) + dv * start, 0]]
	var t_main := t + maxi(40, int((end_d - start) * per))
	var over := {}
	var t_hit := -1
	var t_stop := -1
	if body == null:
		keys.append([t_main - t, Vector2(o) + dv * end_d, 0])
	else:
		var face_d := float(bj + 1) - 0.36
		t_hit = t + int((face_d - start) * per)
		var r := _shove_ex(c, body, d, push, t_hit, JAM_MS, {"wet": water, "power": coll if water else 1})
		t_stop = int(r["stop"])
		var land: Vector2i = r["land"]
		keys.append([t_hit - t, Vector2(o) + dv * face_d, 0])
		keys.append([t_stop - t, Vector2(land) - dv * 0.36, 0])
		t_main = t_stop
		# water spills past a body it can shove and keeps washing the line
		# (the sim washes every tile of it); a massive one stops it dead
		if water and bj < n - 1 and not L.massive(String(body["kind"])):
			over = {"from": float(bj + 1) + 0.36, "to": end_d}
	var cut := t_main - t + JET_HOLD
	var dur := cut + JET_CUT + 40
	var w := (0.16 + 0.03 * float(weight)) if water else (0.28 + 0.04 * float(weight))
	var common := {"t0": t, "dur": dur, "at": o, "from": Vector2(o) + dv * start, "dir": dv, "keys": keys,
		"cut": cut, "w": w, "hit": t_hit - t if t_hit >= 0 else -1, "stop": t_stop - t if t_stop >= 0 else -1,
		"start": start, "per": per, "over": over, "weight": weight}
	if water:
		var jet := common.duplicate()
		jet["kind"] = "jet"
		jet["layer"] = "ground"
		_clip(c, jet)
		var hd := common.duplicate()
		hd["kind"] = "jet_head"
		_clip(c, hd)
	else:
		var gu := common.duplicate()
		gu["kind"] = "gust"
		_clip(c, gu)
	return t_main + (160 if body == null else 120)


## The gust claims its cleared smoke itself: the puff is blown down the line
## instead of rising where it stood.
static func _blow_smoke(c: Dictionary, dv: Vector2, when: Dictionary) -> void:
	var evs: Array = c["events"]
	for i in range(int(c.get("ev0", 0)), int(c.get("ev1", evs.size()))):
		var ev: Dictionary = evs[i]
		if String(ev.get("t", "")) != "smoke_cleared" or not L.claimed(c, i) or c["quiet"][i]:
			continue
		if not when.has(ev.get("tile")) or int(c["times"][i]) != int(when[ev["tile"]]):
			continue
		L.quiet(c, i)
		_clip(c, {"kind": "gust_puff", "t0": int(c["times"][i]), "dur": 520, "at": ev["tile"], "dir": dv})


## Shove `e` along d from time t_hit: slide to its post tile (or its death
## tile), collision damage at the stop. Returns when the shove settles.
## (The areas family shoves through this too; its look is unchanged.)
static func shove(c: Dictionary, e: Dictionary, d: Vector2i, dist: int, t_hit: int) -> int:
	return int(_shove_ex(c, e, d, dist, t_hit, 0, {})["end"])


## The shove itself. `jam` > 0: a body that collides without moving strains
## into the blocker that long before the slam. `style` (empty: the plain
## spark) {wet, power}: this family's slam - a splash or a dust burst at the
## contact face, weighted by the collision damage.
static func _shove_ex(c: Dictionary, e: Dictionary, d: Vector2i, dist: int, t_hit: int, jam: int,
		style: Dictionary) -> Dictionary:
	var from: Vector2i = e["pos"]
	var pe = c["post_en"].get(e["id"])
	var land: Vector2i = from
	if pe != null:
		land = pe["pos"]
	elif not L.massive(String(e["kind"])):
		land = L.push_end(c["pre"], from, d, dist, e["id"], c["ppos"])
	var slide := L.man(from, land) * SHOVE_MS
	if land != from:
		L.move(c, e["id"], [from, land], t_hit, slide, 0.0)
	var dv := Vector2(d)
	var collided := false
	for i in L.unclaimed(c, ["damage"]):
		var ev0: Dictionary = c["events"][i]
		if String(ev0.get("src", "")).begins_with("collision:") and _near_land(c, ev0, e, land):
			collided = true
	var t_stop := t_hit + slide
	var heavy := L.massive(String(e["kind"]))
	if jam > 0 and collided and land == from:
		t_stop = t_hit + jam
		if not heavy:
			# jammed against what is behind it: it strains into it
			L.seg(c, e["id"], {"kind": "lunge", "t0": t_hit, "dur": jam + 140, "dir": dv, "reach": 0.14})
	if jam > 0 and land == from and heavy:
		# too heavy to move: the push only buffets it
		L.seg(c, e["id"], {"kind": "shake", "t0": t_hit, "dur": 180, "amt": 0.05})
	for i in L.unclaimed(c, ["damage", "hook", "status"]):
		var ev: Dictionary = c["events"][i]
		var src := String(ev.get("src", ""))
		if String(ev["t"]) == "damage" and src.begins_with("collision:"):
			# the shoved body and whatever it slammed into
			if _near_land(c, ev, e, land):
				L.claim(c, i, t_stop, dv)
				if ev.get("id") == e["id"] and style.is_empty():
					L.clip(c, {"kind": "spark", "t0": t_stop, "dur": 260, "at": land + d,
						"col": Color("e6edd8"), "n": 7})
		elif ev.get("id") == e["id"] and src.contains(":"):
			L.claim(c, i, t_hit + slide / 2, dv)
		elif String(ev["t"]) == "hook" and ev.get("tile") == land:
			L.claim(c, i, t_stop)
	if collided and not style.is_empty():
		var pw := int(style.get("power", 1))
		# the slam sits where the body met what stopped it; an immovable body
		# takes the blow on the face the push hit
		_clip(c, {"kind": "line_slam", "t0": t_stop, "dur": 360, "at": land,
			"pos": Vector2(land) + dv * (-0.42 if heavy and land == from else 0.46),
			"dir": dv, "power": pw, "wet": bool(style.get("wet", false))})
		L.seg(c, e["id"], {"kind": "squash", "t0": t_stop, "dur": 120})
		if pw >= 3:
			c["reel"]["shakes"].append({"t0": t_stop, "mag": 1.2 * float(pw) - 0.6})
	return {"stop": t_stop, "land": land, "collided": collided, "end": t_stop + 120}


static func _near_land(c: Dictionary, ev: Dictionary, e: Dictionary, land: Vector2i) -> bool:
	if ev.get("id") == e["id"]:
		return true
	return c["pre_en"].has(ev.get("id")) and L.man(c["pre_en"][ev["id"]]["pos"], land) <= 1


# --- dash -----------------------------------------------------------------------

static func _dash(c: Dictionary) -> int:
	var t: int = c["t"]
	var o: Vector2i = c["ppos"]
	var dv := Vector2(_dir(c))
	var to := o
	for i in L.unclaimed(c, ["dash"]):
		to = c["events"][i]["to"]
		L.claim(c, i, t)
		break
	var n := L.man(o, to)
	var go := t + 50
	var dur := maxi(1, n) * DASH_MS + 70
	var hop := 0.26 + 0.05 * float(mini(n, 4))
	# one rising arc for the whole ride (a blocked dash hops in place)
	L.move(c, "player", [o, to], go, dur, hop)
	L.seg(c, "player", {"kind": "squash", "t0": go + dur - 15, "dur": 140})
	_clip(c, {"kind": "dash_dust", "t0": t, "dur": 440, "layer": "ground", "at": o, "dir": -dv, "kick": true})
	_clip(c, {"kind": "dash_trail", "t0": go, "dur": dur + 240, "at": o, "from": Vector2(o), "to": Vector2(to),
		"dir": dv, "travel": dur, "hop": hop, "reach": int(c["adef"].get("range", 3))})
	_clip(c, {"kind": "dash_dust", "t0": go + dur - 20, "dur": 400, "layer": "ground", "at": to, "dir": dv,
		"kick": false})
	c["ppos"] = to
	# whatever the tiles did to the tender on the way lands as it arrives
	for i in L.unclaimed(c, ["damage", "item_pickup", "heal"]):
		if String(c["events"][i].get("who", "player")) == "player" or String(c["events"][i]["t"]) != "damage":
			L.claim(c, i, go + dur)
	return go + dur + 60


# --- paint ------------------------------------------------------------------------

static func paint(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	match String(cl["kind"]):
		"beam":
			_paint_beam(cv, cl, k, V)
		"lance_glint":
			_paint_glint(cv, cl, k, V)
		"lance_hit":
			_paint_lance_hit(cv, cl, k, V)
		"vine":
			_paint_vine(cv, cl, k, V)
		"vine_crack":
			_paint_crack(cv, cl, k, V)
		"vine_furrow":
			_paint_furrow(cv, cl, k, V)
		"jet":
			_paint_jet(cv, cl, k, V)
		"jet_head":
			_paint_jet_head(cv, cl, k, V)
		"line_slam":
			_paint_slam(cv, cl, k, V)
		"gust":
			_paint_gust(cv, cl, k, V)
		"gust_puff":
			_paint_gust_puff(cv, cl, k, V)
		"dash_trail":
			_paint_dash(cv, cl, k, V)
		"dash_dust":
			_paint_dust(cv, cl, k, V)


static func _span(cl: Dictionary) -> float:
	return maxf(1.0, float(cl.get("span", cl["dur"])))


static func _ease(u: float, how: int) -> float:
	match how:
		1:
			return D.ease_out(u)
		2:
			return D.ease_in(u)
		3:
			return D.ease_io(u)
	return clampf(u, 0.0, 1.0)


## Keyframed position (tile space): keys = [[ms, Vector2, ease], ...], the ease
## shaping the segment that ends at that key.
static func _key_at(keys: Array, ms: float) -> Vector2:
	var k0: Array = keys[0]
	if ms <= float(k0[0]):
		return k0[1]
	for i in range(1, keys.size()):
		var k1: Array = keys[i]
		if ms <= float(k1[0]):
			var a: Array = keys[i - 1]
			var u := (ms - float(a[0])) / maxf(1.0, float(k1[0]) - float(a[0]))
			return (a[1] as Vector2).lerp(k1[1], _ease(u, int(k1[2])))
	return keys[keys.size() - 1][1]


static func _perp(dv: Vector2) -> Vector2:
	return Vector2(-dv.y, dv.x)


## A four-point star rotated by rot.
static func _star4(cv, p: Vector2, r: float, rot: float, col: Color) -> void:
	if r < 0.8 or col.a <= 0.01:
		return
	var pts := PackedVector2Array()
	for i in 8:
		var ang := rot + TAU * float(i) / 8.0
		var rr := r if i % 2 == 0 else r * 0.22
		pts.append(p + Vector2(cos(ang), sin(ang)) * rr)
	cv.draw_colored_polygon(pts, col)


## A band a -> b, `w` wide, tapering to a point `tip` long at b and `tail`
## long at a: the shape of a lance of light.
static func _lance_band(cv, a: Vector2, b: Vector2, w: float, tip: float, tail: float, col: Color) -> void:
	var ln := a.distance_to(b)
	if ln < 2.0 or w < 0.5 or col.a <= 0.01:
		return
	var f := (b - a) / ln
	var s := _perp(f) * w * 0.5
	tip = minf(tip, ln * 0.45)
	tail = clampf(tail, 1.0, ln * 0.3)
	cv.draw_colored_polygon(PackedVector2Array([a, a + f * tail + s, b - f * tip + s, b, b - f * tip - s,
		a + f * tail - s]), col)


static func _paint_beam(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var ms := k * _span(cl)
	var travel := maxf(1.0, float(cl["travel"]))
	var dv: Vector2 = cl["dir"]
	var s := _perp(dv)
	var a := D.px(V, cl["from"])
	var b := D.px(V, cl["to"])
	var head := a.lerp(b, clampf(ms / travel, 0.0, 1.0))
	var fu := D.ease_in(clampf((ms - travel - BEAM_HOLD) / BEAM_FADE, 0.0, 1.0))
	var tail := a.lerp(b, fu)
	var power := float(cl.get("power", 2))
	var pierce := bool(cl.get("pierce", false))
	var w := t * (0.12 + 0.04 * power) * (0.78 if pierce else 1.0)
	w *= (1.0 - 0.6 * fu) * (1.0 + 0.07 * sin(ms * 0.11))
	var al := 1.0 - fu * fu
	var tip := t * (0.62 if pierce else 0.34)
	_lance_band(cv, tail, head + dv * t * 0.05, w * 2.3, tip * 1.3, w, D.ca(pal["c"], 0.42 * al))
	_lance_band(cv, tail, head, w, tip, w * 0.8, D.ca(pal["a"], al))
	_lance_band(cv, tail, head, w * 0.5, tip * 0.85, w * 0.5, D.ca(pal["b"], al))
	D.line(cv, tail + dv * w * 0.4, head - dv * tip * 0.6, D.ca(Color.WHITE, al), maxf(1.5, w * 0.17))
	var ln := tail.distance_to(head)
	if ln > t * 0.3:
		# heat shimmer rippling off both edges
		for side in [-1.0, 1.0]:
			var pts := PackedVector2Array()
			for i in 11:
				var u := float(i) / 10.0
				var q := tail.lerp(head - dv * tip, u)
				pts.append(q + s * side * (w * 0.95 + t * 0.03 * sin(u * 13.0 - ms * 0.035 + side)))
			cv.draw_polyline(pts, D.ca(pal["a"], 0.4 * al), maxf(1.0, t * 0.025), true)
		# motes shed along the shaft
		for i in 8:
			var u := fposmod(D.h01(i * 7 + 3) + ms * 0.0022 * (0.7 + 0.6 * D.h01(i + 40)), 1.0)
			var q := tail.lerp(head, u) + s * ((D.h01(i * 5 + 1) - 0.5) * w * 2.2 + sin(ms * 0.02 + float(i)) * t * 0.04)
			cv.draw_circle(q, t * (0.022 + 0.014 * D.h01(i + 9)), D.ca(pal["b"], 0.95 * al))
	if ms < travel + 50.0:
		# the racing head: a hot star, a lens streak for the needle
		var hr := t * (0.24 + 0.04 * power)
		D.glow(cv, head, hr, D.ca(pal["b"], 0.8))
		_star4(cv, head, hr * 1.25, ms * 0.012, D.ca(Color.WHITE, 0.95))
		if pierce:
			D.line(cv, head - dv * t * 0.7, head + dv * t * 0.35, D.ca(Color.WHITE, 0.8), maxf(1.0, t * 0.035))


static func _paint_glint(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var span := _span(cl)
	var ms := k * span
	var fire := maxf(1.0, float(cl["fire"]))
	var p := D.px(V, cl["pos"])
	var power := float(cl.get("power", 2))
	var grow := 1.0 + 0.12 * (power - 2.0)
	if bool(cl.get("sun", false)):
		# clear skies: a corona turns round the tender while the light gathers
		var cc := D.px(V, cl["center"])
		var ca := D.pulse(k) * 0.9
		for i in 10:
			var ang := TAU * float(i) / 10.0 + ms * 0.004
			var dir2 := Vector2(cos(ang), sin(ang))
			D.line(cv, cc + dir2 * t * 0.5, cc + dir2 * t * (0.62 + 0.06 * float(i % 2)), D.ca(pal["a"], ca),
				maxf(1.0, t * 0.045))
		D.ring(cv, cc, t * 0.47, D.ca(pal["b"], ca * 0.6), t * 0.025)
	if ms < fire:
		var g := ms / fire
		# light is drawn in to a point: motes spiral in, trailing streaks
		for i in 8:
			var ang := TAU * float(i) / 8.0 + g * 2.6 + D.h01(i) * 0.5
			var r := t * (0.8 - 0.72 * D.ease_in(g)) * (0.8 + 0.4 * D.h01(i * 3 + 1)) * grow
			var q := p + Vector2(cos(ang), sin(ang)) * r
			D.line(cv, q, q + Vector2(cos(ang), sin(ang)) * t * 0.14 * (1.0 - g), D.ca(pal["a"], 0.7 * g + 0.2), maxf(1.0, t * 0.03))
			cv.draw_circle(q, t * (0.04 + 0.025 * g), D.ca(pal["b"], 0.5 + 0.5 * g))
		D.glow(cv, p, t * (0.16 + 0.26 * g) * grow, D.ca(pal["a"], 0.4 + 0.45 * g))
		_star4(cv, p, t * (0.14 + 0.3 * g) * grow, g * 1.2, D.ca(Color.WHITE, 0.6 + 0.4 * g))
	else:
		# the release: a hot star snaps open at the muzzle and dies
		var f := clampf((ms - fire) / maxf(1.0, span - fire), 0.0, 1.0)
		var sz := t * (0.36 + 0.07 * power) * (1.0 - 0.55 * f)
		D.glow(cv, p, sz, D.ca(pal["a"], 0.75 * (1.0 - f)))
		_star4(cv, p, sz * 1.2, 0.0, D.ca(Color.WHITE, 1.0 - f))
		_star4(cv, p, sz * 0.7, PI * 0.25, D.ca(pal["b"], 0.8 * (1.0 - f)))
		D.ring(cv, p, t * (0.14 + 0.36 * D.ease_out(f)), D.ca(pal["b"], 0.85 * (1.0 - f)), t * 0.04)


static func _paint_lance_hit(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var dv: Vector2 = cl["dir"]
	var s := _perp(dv)
	var p := D.px(V, cl["pos"])
	var power := float(cl.get("power", 2))
	var style := String(cl.get("style", "stop"))
	var a := 1.0 - k
	var fl := 1.0 - D.win(k, 0.0, 0.3)
	if style == "ignite":
		# the slick flashes over as the beam crosses it; embers leap up
		D.glow(cv, p, t * (0.2 + 0.2 * D.ease_out(k)), D.ca(pal["b"], 0.8 * fl))
		for i in 6:
			var x := (D.h01(i * 5 + 2) - 0.5) * t * 0.7
			var rise := t * (0.1 + 0.6 * D.ease_out(k)) * (0.6 + 0.5 * D.h01(i + 11))
			cv.draw_circle(p + Vector2(x + sin(k * 9.0 + float(i)) * t * 0.05, t * 0.15 - rise), t * 0.035 * (1.0 - 0.5 * k),
				D.ca(pal["b"] if i % 2 else pal["c"], a))
		return
	if style == "block":
		# smoke swallows the light: it only diffuses into the haze
		D.glow(cv, p, t * (0.25 + 0.3 * D.ease_out(k)), D.ca(pal["a"], 0.55 * a), 4)
		D.glow(cv, p, t * 0.16 * fl + 1.0, D.ca(pal["b"], 0.7 * fl))
		return
	var big := 1.0 + 0.16 * (power - 2.0)
	if fl > 0.0:
		D.glow(cv, p, t * 0.24 * big * (0.6 + 0.4 * fl), D.ca(Color.WHITE, 0.9 * fl))
	# rays burst from the point of impact
	var nr := 6 + int(power)
	for i in nr:
		var ang := TAU * float(i) / float(nr) + D.h01(i + 17) * 0.5
		var dir2 := Vector2(cos(ang), sin(ang))
		var r0 := t * (0.08 + 0.26 * D.ease_out(k)) * big
		var r1 := r0 + t * (0.14 + 0.06 * power) * (1.0 - k)
		D.line(cv, p + dir2 * r0, p + dir2 * r1, D.ca(pal["b"] if i % 2 == 0 else pal["a"], a), maxf(1.0, t * 0.05 * (1.0 - 0.5 * k)))
	D.ring(cv, p, t * (0.12 + 0.42 * D.ease_out(k)) * big, D.ca(pal["c"], 0.9 * a), t * 0.05 * (1.0 - 0.6 * k))
	# sparks: thrown back at the caster off a body or a wall, blown out the
	# far side by a piercing beam
	var back := dv if style == "pierce" else -dv
	var base := p + (dv * t * 0.3 if style == "pierce" else Vector2.ZERO)
	for i in 7:
		var spread := (D.h01(i * 13 + 5) - 0.5) * 1.9
		var dir3 := back * cos(spread) + s * sin(spread)
		var dist := t * (0.12 + 0.6 * D.ease_out(k)) * (0.55 + 0.6 * D.h01(i * 7 + 2))
		var q := base + dir3 * dist + Vector2(0, t * 0.3 * k * k)
		D.line(cv, q, q - dir3 * t * 0.13 * (1.0 - k), D.ca(pal["b"] if i % 3 else Color.WHITE, a), maxf(1.0, t * 0.04))
	if style == "pierce":
		# punched through: a flash bar across the beam where it enters and exits
		var bar := t * (0.3 + 0.04 * power) * (0.4 + 0.6 * fl)
		D.line(cv, p - dv * t * 0.3 - s * bar, p - dv * t * 0.3 + s * bar, D.ca(Color.WHITE, 0.95 * fl), maxf(1.5, t * 0.07))
		D.line(cv, p + dv * t * 0.3 - s * bar * 0.8, p + dv * t * 0.3 + s * bar * 0.8, D.ca(pal["b"], 0.9 * a), maxf(1.0, t * 0.05))


# --- vine painters ---------------------------------------------------------------

## The vine's centreline a -> b: a travelling wave pinned at the hand and
## free toward the tip.
static func _vine_pts(a: Vector2, b: Vector2, amp: float, phase: float, n: int = 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var dv := b - a
	var ln := dv.length()
	if ln < 1.0:
		return pts
	var s := _perp(dv / ln)
	var waves := clampf(ln / 55.0, 0.8, 2.2)
	for i in n + 1:
		var u := float(i) / float(n)
		var env := sin(minf(u * 1.25, 1.0) * PI * 0.5) * (1.0 - 0.35 * u)
		pts.append(a + dv * u + s * amp * env * sin(u * waves * TAU - phase))
	return pts


static func _paint_vine(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var span := _span(cl)
	var ms := k * span
	var keys: Array = cl["keys"]
	var hand := D.px(V, cl["hand"])
	var tipt := _key_at(keys, ms)
	var tip := D.px(V, tipt)
	var power := float(cl.get("power", 2))
	var rake := bool(cl.get("rake", false))
	var bite := float(cl["bite"])
	var free := float(cl["free"])
	var w := t * (0.07 + 0.018 * power)
	var fade := 1.0 - D.win(ms, span - 70.0, span)
	# slack: a whip wave in flight, taut while hauling, loose as it snaps back
	var amp: float
	if ms < bite:
		amp = t * 0.17 * (1.0 - 0.55 * ms / maxf(1.0, bite))
	elif ms < free:
		amp = t * 0.035
	else:
		amp = t * 0.13 * D.pulse(clampf((ms - free) / float(VINE_SNAP), 0.0, 1.0))
	var pts := _vine_pts(hand, tip, amp, ms * 0.04)
	var dv: Vector2 = cl["dir"]
	var ang_tip := dv.angle()
	if pts.size() >= 2:
		ang_tip = (pts[pts.size() - 1] - pts[pts.size() - 2]).angle()
		cv.draw_polyline(pts, D.ca(INK, 0.5 * fade), w + t * 0.06, true)
		cv.draw_polyline(pts, D.ca(pal["c"], fade), w, true)
		var hi := PackedVector2Array()
		for q in pts:
			hi.append(q + Vector2(-0.35, -0.35) * w * 0.35)
		cv.draw_polyline(hi, D.ca(pal["a"], fade), w * 0.55, true)
		cv.draw_polyline(hi, D.ca(pal["b"], 0.7 * fade), maxf(1.0, w * 0.16), true)
		var m := pts.size() - 1
		var ln := hand.distance_to(tip)
		if ln > t * 0.6:
			# leaves along the stem, thorns on a heavy vine
			for j in 3:
				var idx := int(float(m) * (0.3 + 0.22 * float(j)))
				var q := pts[idx]
				var tan := (pts[mini(idx + 1, m)] - pts[maxi(idx - 1, 0)]).angle()
				var side := 1.0 if j % 2 == 0 else -1.0
				D.leaf(cv, q + Vector2(cos(tan + side * PI * 0.5), sin(tan + side * PI * 0.5)) * w * 0.9,
					tan + side * 0.9, t * 0.2, D.ca(pal["a"], fade))
			if power >= 3.0:
				for j in 6:
					var idx2 := int(float(m) * (0.18 + 0.12 * float(j)))
					var q2 := pts[idx2]
					var tan2 := (pts[mini(idx2 + 1, m)] - pts[maxi(idx2 - 1, 0)]).normalized()
					var nrm := _perp(tan2) * (1.0 if j % 2 == 0 else -1.0)
					D.spike(cv, q2 + nrm * w * 0.3, q2 + nrm * (w * 0.5 + t * 0.09) + tan2 * t * 0.04, t * 0.055,
						D.ca(pal["b"], fade))
	if rake:
		_paint_tines(cv, tip, ang_tip, ms, bite, w, t, pal, fade)
	else:
		# the leaf hook at the tip
		D.leaf(cv, tip, ang_tip, t * 0.32, D.ca(pal["b"], fade))
		cv.draw_arc(tip + Vector2(cos(ang_tip), sin(ang_tip)) * t * 0.08, t * 0.11, ang_tip - PI * 0.2, ang_tip + PI * 0.9, 7,
			D.ca(pal["c"], fade), maxf(1.0, w * 0.6), true)
	for cat in cl.get("catches", []):
		var h := float(cat["hook"])
		var fr := float(cat["free"])
		# the bite: a snap of light where the hook takes hold
		if ms >= h and ms < h + 130.0:
			var bk := (ms - h) / 130.0
			var bp := D.px(V, cat["at"])
			_star4(cv, bp + Vector2(cos(ang_tip), sin(ang_tip)) * -t * 0.2, t * 0.3 * (1.0 - bk), bk, D.ca(Color.WHITE, 1.0 - bk))
		# the coils let go just before the lash cracks, so the crack reads clean
		if bool(cat.get("coil", false)) and ms >= h and ms < fr:
			_paint_coil(cv, tip, t, w, pal, clampf((ms - h) / float(VINE_BITE), 0.0, 1.0), 1.0 - D.win(ms, fr - 110.0, fr - 40.0))


## Three tines splay at the rake's head and curl back into hooks once they dig.
static func _paint_tines(cv, head: Vector2, ang: float, ms: float, bite: float, w: float, t: float, pal: Dictionary, fade: float) -> void:
	var f := Vector2(cos(ang), sin(ang))
	var s := _perp(f)
	var curl := D.ease_io(clampf((ms - bite + 40.0) / 90.0, 0.0, 1.0))
	for i in 3:
		var side := float(i) - 1.0
		var mid := head + s * side * t * 0.2 + f * t * 0.12
		var end := head + s * side * t * 0.34 + f * t * (0.26 - 0.44 * curl)
		var pts := PackedVector2Array([head, mid, end])
		cv.draw_polyline(pts, D.ca(INK, 0.5 * fade), w * 0.8 + t * 0.05, true)
		cv.draw_polyline(pts, D.ca(pal["c"], fade), w * 0.8, true)
		cv.draw_polyline(pts, D.ca(pal["a"], fade), maxf(1.0, w * 0.4), true)
		D.leaf(cv, end, (end - mid).angle(), t * 0.17, D.ca(pal["b"], fade))


## The hook's coils cinching round the caught body's waist, tightening as it
## bites. Only the front of each loop is drawn, so the body shows through.
static func _paint_coil(cv, c: Vector2, t: float, w: float, pal: Dictionary, g: float, a: float) -> void:
	if a <= 0.01:
		return
	for j in 2:
		var cy := c + Vector2(0, t * (0.04 + 0.2 * float(j)))
		var rx := t * (0.5 - 0.14 * g) * (1.0 - 0.1 * float(j))
		var a0 := -0.25 + 0.3 * float(j)
		var pts := _ellipse_arc(cy, rx, rx * 0.36, a0, a0 + (PI + 0.5) * (0.35 + 0.65 * g), 12)
		cv.draw_polyline(pts, D.ca(INK, 0.55 * a), w * 0.55 + t * 0.05, true)
		cv.draw_polyline(pts, D.ca(pal["a"], a), maxf(1.0, w * 0.55), true)
		cv.draw_polyline(pts, D.ca(pal["b"], 0.7 * a), maxf(1.0, w * 0.18), true)


static func _ellipse_arc(c: Vector2, rx: float, ry: float, a0: float, a1: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var ang := lerpf(a0, a1, float(i) / float(n))
		pts.append(c + Vector2(cos(ang) * rx, sin(ang) * ry))
	return pts


## The lash cracking down: a whip arc swings across the body and lands at
## `hit` (the damage beat) with a white crack and leaf shards.
static func _paint_crack(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var span := _span(cl)
	var ms := k * span
	var hit := maxf(1.0, float(cl["hit"]))
	var dv: Vector2 = cl["dir"]
	var p := D.px(V, cl["at"])
	var power := float(cl.get("power", 2))
	var sc := (0.8 if bool(cl.get("small", false)) else 1.0) * (1.0 + 0.14 * (power - 2.0))
	var base := dv.angle() + PI
	var sw := D.ease_in(clampf(ms / hit, 0.0, 1.0))
	var fa := 1.0 - D.win(ms, hit, hit + 110.0)
	# the arc: swung from the caster's side across the body
	var piv := p - dv * t * 0.55
	var pts := PackedVector2Array()
	for i in 10:
		var u := float(i) / 9.0 * sw
		var ang := base + PI - 1.1 + u * 2.2
		pts.append(piv + Vector2(cos(ang), sin(ang)) * t * 0.62 * sc)
	if sw > 0.05 and fa > 0.0:
		cv.draw_polyline(pts, D.ca(pal["c"], fa), t * 0.1 * sc, true)
		cv.draw_polyline(pts, D.ca(pal["b"], fa), t * 0.04 * sc, true)
	if ms >= hit:
		var f := clampf((ms - hit) / maxf(1.0, span - hit), 0.0, 1.0)
		var a := 1.0 - f
		# the crack itself: a white snap at the face that is gone in a blink
		var sa := 1.0 - clampf((ms - hit) / 90.0, 0.0, 1.0)
		_star4(cv, p - dv * t * 0.24, t * 0.3 * sc * (1.0 + 0.3 * (1.0 - sa)), 0.4, D.ca(Color.WHITE, sa))
		var nr := 4 + int(power)
		for i in nr:
			var ang2 := TAU * float(i) / float(nr) + 0.3
			var dir2 := Vector2(cos(ang2), sin(ang2))
			D.line(cv, p + dir2 * t * (0.15 + 0.3 * D.ease_out(f)) * sc, p + dir2 * t * (0.3 + 0.35 * D.ease_out(f)) * sc,
				D.ca(pal["b"], a), maxf(1.0, t * 0.045))
		for i in 4:
			var ang3 := TAU * D.h01(i * 11 + 3)
			var q := p + Vector2(cos(ang3), sin(ang3)) * t * (0.2 + 0.5 * D.ease_out(f)) * sc + Vector2(0, t * 0.3 * f * f)
			D.leaf(cv, q, ang3 + f * 7.0, t * 0.14 * sc, D.ca(LEAF, a))
	else:
		# the lash is coming: a faint glint where it will land
		D.glow(cv, p, t * 0.12 * sw + 1.0, D.ca(pal["b"], 0.5 * sw))


## Furrows the rake's tines tear in the ground as it is dragged home.
static func _paint_furrow(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var span := _span(cl)
	var ms := float(cl["origin"]) + k * span
	var dv: Vector2 = cl["dir"]
	var s := _perp(dv)
	var far := D.px(V, cl["far"])
	var head := D.px(V, _key_at(cl["keys"], ms))
	var a := 1.0 - D.win(k, 0.4, 1.0)
	if far.distance_to(head) < 2.0:
		head = far - dv * 2.0
	for i in 3:
		var off := s * (float(i) - 1.0) * t * 0.22
		D.line(cv, far + off, head + off, D.ca(Color(0.07, 0.06, 0.04), 0.5 * a), maxf(1.0, t * 0.065))
		D.line(cv, far + off - s * t * 0.04, head + off - s * t * 0.04, D.ca(DUST, 0.14 * a), maxf(1.0, t * 0.02))


# --- jet / gust painters -----------------------------------------------------------

## A stream band a -> b with rippling edges, flaring from `flare` x w at the
## nozzle to w at the head, with an antialiased rim.
static func _stream_band(cv, a: Vector2, b: Vector2, w: float, phase: float, col: Color, flare: float = 0.4) -> void:
	var ln := a.distance_to(b)
	if ln < 2.0 or w < 0.5 or col.a <= 0.01:
		return
	var f := (b - a) / ln
	var s := _perp(f)
	var n := 12
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in n + 1:
		var u := float(i) / float(n)
		var hw := w * 0.5 * (flare + (1.0 - flare) * sqrt(u))
		var q := a + f * ln * u
		left.append(q + s * hw * (1.0 + 0.06 * sin(u * ln * 0.19 - phase)))
		right.append(q - s * hw * (1.0 + 0.06 * sin(u * ln * 0.15 - phase * 1.3 + 1.0)))
	right.reverse()
	left.append_array(right)
	cv.draw_colored_polygon(left, col)
	left.append(left[0])
	cv.draw_polyline(left, col, 1.0, true)


## The stream's (or gust's) head and tail at ms: the head rides the keys, the
## tail leaves the nozzle once the stream is cut.
static func _ends(cl: Dictionary, V: Dictionary, ms: float) -> Array:
	var head := D.px(V, _key_at(cl["keys"], ms))
	var noz := D.px(V, cl["from"])
	var cu := D.ease_in(clampf((ms - float(cl["cut"])) / float(JET_CUT), 0.0, 1.0))
	return [noz.lerp(head, cu), head, cu]


static func _paint_jet(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var ms := k * _span(cl)
	var dv: Vector2 = cl["dir"]
	var s := _perp(dv)
	var e := _ends(cl, V, ms)
	var tail: Vector2 = e[0]
	var head: Vector2 = e[1]
	var cu: float = e[2]
	var al := 1.0 - cu * cu
	var w := t * float(cl["w"]) * 1.8 * (1.0 - 0.45 * cu)
	var over: Dictionary = cl.get("over", {})
	if not over.is_empty():
		# the sheet that spills past the body and keeps washing the line
		var o0 := D.px(V, cl["from"]) + dv * t * (float(over["from"]) - float(cl["start"]))
		var reach := (ms / float(cl["per"])) + float(cl["start"])
		var o1 := D.px(V, cl["from"]) + dv * t * (minf(reach, float(over["to"])) - float(cl["start"]))
		if reach > float(over["from"]) and o0.distance_to(o1) > 2.0:
			_stream_band(cv, o0, o1, w * 0.5, ms * 0.05, D.ca(pal["a"], 0.55 * al))
			D.line(cv, o0, o1, D.ca(pal["b"], 0.6 * al), maxf(1.0, w * 0.08))
	if tail.distance_to(head) > 2.0:
		_stream_band(cv, tail, head, w * 1.18, ms * 0.05, D.ca(pal["c"], 0.9 * al))
		_stream_band(cv, tail, head, w * 0.86, ms * 0.05 + 1.3, D.ca(pal["a"], al))
		D.line(cv, tail + dv * t * 0.05, head - dv * t * 0.05, D.ca(pal["b"], 0.85 * al), maxf(1.0, w * 0.16))
		# pressure: foam streaks rushing down the stream
		var ln := tail.distance_to(head)
		for i in 7:
			var u := fposmod(D.h01(i * 5 + 1) + ms * 0.0045 * (0.8 + 0.4 * D.h01(i)), 1.0)
			var q := tail.lerp(head, u) + s * (D.h01(i * 3 + 2) - 0.5) * w * 0.6
			D.line(cv, q, q + dv * minf(t * 0.22, ln * (1.0 - u)), D.ca(Color.WHITE, 0.85 * al), maxf(1.0, t * 0.035))


static func _paint_jet_head(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var ms := k * _span(cl)
	var dv: Vector2 = cl["dir"]
	var s := _perp(dv)
	var e := _ends(cl, V, ms)
	var head: Vector2 = e[1]
	var cu: float = e[2]
	var al := 1.0 - cu
	var w := t * float(cl["w"]) * 1.8
	var hit := float(cl["hit"])
	var pressing := hit >= 0.0 and ms >= hit and ms < float(cl["cut"]) + 40.0
	# foam boiling at the head
	for i in 5:
		var ang := TAU * D.h01(i * 9 + 4) + ms * 0.02 * (1.0 if i % 2 else -1.0)
		var q := head + Vector2(cos(ang), sin(ang)) * w * 0.3 * (0.6 + 0.4 * sin(ms * 0.05 + float(i)))
		cv.draw_circle(q, w * (0.2 + 0.08 * D.h01(i + 3)) * (1.0 - 0.5 * cu), D.ca(Color.WHITE if i % 2 == 0 else pal["b"], 0.9 * al))
	# spray: forward and to the sides in flight, flung back off a body it presses
	var nd := 12 if pressing else 8
	for i in nd:
		var life := fposmod((ms + D.h01(i * 7 + 1) * 180.0) / 180.0, 1.0)
		var lat := (D.h01(i * 13 + 2) - 0.5) * 2.0
		var fwd := (-0.55 - 0.4 * D.h01(i + 20)) if pressing else (0.2 + 0.5 * D.h01(i + 20))
		var dir2 := (dv * fwd + s * lat * (1.1 if pressing else 0.6)).normalized()
		var q := head + dir2 * t * (0.1 + 0.55 * life) + Vector2(0, t * 0.35 * life * life)
		cv.draw_circle(q, t * 0.04 * (1.0 - 0.6 * life), D.ca(pal["b"] if i % 3 else Color.WHITE, al * (1.0 - life)))


static func _paint_slam(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var dv: Vector2 = cl["dir"]
	var s := _perp(dv)
	var p := D.px(V, cl["pos"])
	var pw := float(cl.get("power", 1))
	var big := 0.66 + 0.13 * pw
	var a := 1.0 - k
	var fl := 1.0 - D.win(k, 0.0, 0.25)
	if fl > 0.0:
		D.glow(cv, p, t * 0.26 * big * (0.5 + 0.5 * fl), D.ca(Color.WHITE, 0.9 * fl))
	# the crack of impact: short hard rays across the contact face
	for i in 6:
		var ang := s.angle() + (PI if i % 2 == 1 else 0.0) + (D.h01(i + 3) - 0.5) * 1.3
		var dir2 := Vector2(cos(ang), sin(ang))
		var r0 := t * (0.06 + 0.25 * D.ease_out(k)) * big
		D.line(cv, p + dir2 * r0, p + dir2 * (r0 + t * 0.2 * big * (1.0 - k)), D.ca(Color.WHITE, a), maxf(1.0, t * 0.05))
	if bool(cl.get("wet", false)):
		# a crown of spray thrown up off the contact
		for i in 11:
			var ang2 := TAU * float(i) / 11.0 + D.h01(i) * 0.4
			var dir3 := Vector2(cos(ang2), sin(ang2) * 0.7) - dv * 0.35
			var q := p + dir3 * t * (0.12 + 0.48 * D.ease_out(k)) * big + Vector2(0, t * 0.45 * k * k)
			cv.draw_circle(q, t * 0.05 * (1.0 - 0.5 * k) * big, D.ca(pal["b"] if i % 2 else Color.WHITE, a))
		var rr := t * (0.14 + 0.36 * D.ease_out(k)) * big
		cv.draw_polyline(_ellipse_arc(p, rr, rr * 0.5, 0.0, TAU, 18), D.ca(pal["a"], 0.85 * a), maxf(1.0, t * 0.045 * (1.0 - 0.5 * k)), true)
	else:
		# a dust burst
		for i in 6:
			var ang3 := TAU * float(i) / 6.0 + 0.4
			var q2 := p + Vector2(cos(ang3), sin(ang3) * 0.6) * t * (0.1 + 0.4 * D.ease_out(k)) * big - dv * t * 0.1
			cv.draw_circle(q2, t * (0.1 + 0.12 * k) * big, D.ca(DUST, 0.5 * a))


static func _paint_gust(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var ms := k * _span(cl)
	var dv: Vector2 = cl["dir"]
	var s := _perp(dv)
	var e := _ends(cl, V, ms)
	var tail: Vector2 = e[0]
	var front: Vector2 = e[1]
	var cu: float = e[2]
	var al := 1.0 - cu
	var noz := D.px(V, cl["from"])
	var ln := noz.distance_to(front)
	var tail_d := noz.distance_to(tail)
	var wide := t * float(cl["w"])
	var blocked := float(cl["hit"]) >= 0.0 and ms >= float(cl["hit"])
	# a heavier gust (more shove) is a thicker bundle carrying more debris
	var weight := int(cl.get("weight", 4))
	var nl := clampi(2 + weight, 4, 9)
	# streamlines: dashes of wind flowing out to the front, parting round a body
	for i in nl:
		var lat := (float(i) - float(nl - 1) * 0.5) / (float(nl - 1) * 0.5)
		var dash := t * (0.55 + 0.35 * D.h01(i + 5))
		var x := fposmod(ms * t / 26.0 + D.h01(i * 7 + 1) * (ln + dash), ln + dash)
		var x0 := clampf(x - dash, tail_d, ln)
		var x1 := clampf(x, tail_d, ln)
		if x1 - x0 < 2.0:
			continue
		var pts := PackedVector2Array()
		for j in 6:
			var xx := lerpf(x0, x1, float(j) / 5.0)
			var part := 0.0
			if blocked:
				part = clampf(1.0 - (ln - xx) / (t * 0.6), 0.0, 1.0)
			var off := lat * wide * (1.0 + 0.9 * part) + t * 0.03 * sin(xx * 0.08 + ms * 0.02 + float(i))
			pts.append(noz + dv * xx + s * off)
		var env := sin(clampf(x1 / maxf(1.0, ln), 0.0, 1.0) * PI) * 0.6 + 0.4
		cv.draw_polyline(pts, D.ca(pal["c"], 0.55 * al * env), maxf(1.0, t * 0.075), true)
		cv.draw_polyline(pts, D.ca(pal["b"], 0.95 * al * env), maxf(1.0, t * 0.035), true)
		var hp := pts[pts.size() - 1]
		cv.draw_arc(hp - s * t * 0.06 * signf(lat + 0.01), t * 0.06, dv.angle() - PI * 0.5, dv.angle() + PI * 0.7, 6,
			D.ca(pal["b"], 0.8 * al * env), maxf(1.0, t * 0.03), true)
	# the gust front: a bright bow while it travels
	if not blocked and ms < float(cl["keys"][cl["keys"].size() - 1][0]) + 30.0:
		cv.draw_arc(front - dv * t * 0.25, t * 0.38, dv.angle() - 0.9, dv.angle() + 0.9, 9, D.ca(pal["b"], 0.8), maxf(1.0, t * 0.05), true)
	# debris tumbling along with the wind: leaves and dust
	for i in clampi(3 + weight, 5, 10):
		var lag := t * (0.15 + 0.9 * D.h01(i * 3 + 7))
		var dx := clampf(ln - lag, tail_d, ln)
		var off2 := (D.h01(i * 5 + 3) - 0.5) * wide * 2.2 + sin(ms * 0.03 + float(i) * 2.0) * t * 0.08
		var q := noz + dv * dx + s * off2
		if i % 2 == 0:
			D.leaf(cv, q, ms * 0.025 * (1.0 + D.h01(i)) + float(i), t * 0.17, D.ca(LEAF, 0.95 * al))
		else:
			cv.draw_circle(q, t * 0.035, D.ca(DUST, 0.9 * al))


static func _paint_gust_puff(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var dv: Vector2 = cl["dir"]
	var s := _perp(dv)
	var p := D.px(V, cl["at"])
	var col: Color = L.TERRAIN_COL.get("smoke", Color(0.6, 0.62, 0.62))
	var a := 1.0 - k
	for i in 4:
		var fwd := t * (0.1 + (0.9 + 0.3 * D.h01(i)) * D.ease_out(k))
		var lat := (D.h01(i * 7 + 2) - 0.5) * t * 0.6 * (1.0 + k)
		var q := p + dv * fwd + s * lat
		cv.draw_circle(q, t * (0.18 + 0.22 * k) * (0.8 + 0.3 * D.h01(i + 4)), D.ca(col, 0.5 * a))
	D.line(cv, p - dv * t * 0.2, p + dv * t * (0.2 + 0.8 * D.ease_out(k)), D.ca(Color.WHITE, 0.5 * a), maxf(1.0, t * 0.03))


# --- dash painters -----------------------------------------------------------------

static func _paint_dash(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var ms := k * _span(cl)
	var travel := maxf(1.0, float(cl["travel"]))
	var a: Vector2 = cl["from"]
	var b: Vector2 = cl["to"]
	var dv: Vector2 = cl["dir"]
	var s := _perp(dv)
	var hop := float(cl.get("hop", 0.3))
	var u := clampf(ms / travel, 0.0, 1.0)
	var fade := 1.0 - D.win(ms, travel, _span(cl))
	var cur := D.px(V, a.lerp(b, u)) - Vector2(0, hop * sin(u * PI) * t)
	# lift-off: a column of wind streaks bursting up off the ground, taller
	# and denser for an updraft with more reach
	var col_k := clampf(ms / 260.0, 0.0, 1.0)
	var reach := float(cl.get("reach", 3))
	if col_k < 1.0:
		var base := D.px(V, a) + Vector2(0, t * 0.4)
		var nc := clampi(int(reach) + 2, 4, 8)
		for i in nc:
			var x := (float(i) - float(nc - 1) * 0.5) * t * 0.68 / float(nc - 1)
			var y0 := t * (0.1 + (0.6 + 0.1 * reach) * D.ease_out(col_k)) * (0.7 + 0.5 * D.h01(i + 3))
			var y1 := y0 + t * (0.25 + 0.2 * D.h01(i)) * (1.0 - col_k)
			D.line(cv, base + Vector2(x, -y0), base + Vector2(x * 1.2, -y1), D.ca(pal["b"], 0.85 * (1.0 - col_k)), maxf(1.0, t * 0.035))
	# afterimages of the tender strung along the ride
	var tex = Art.tex("player", int(t))
	if tex != null and a.distance_to(b) > 0.01:
		for j in 3:
			var uj := u - 0.16 * float(j + 1)
			if uj <= 0.0:
				continue
			var q := D.tile_rect(V, a.lerp(b, uj)).position - Vector2(0, hop * sin(uj * PI) * t)
			cv.draw_texture(tex, q, Color(pal["b"].r, pal["b"].g, pal["b"].b, (0.5 - 0.15 * float(j)) * fade))
	# speed lines streaming off behind
	var back := -dv if a.distance_to(b) > 0.01 else Vector2.DOWN
	var side := _perp(back)
	for i in 4:
		var lat := (float(i) - 1.5) * t * 0.2
		var l0 := t * (0.3 + 0.12 * D.h01(i))
		var l1 := l0 + t * (0.5 + 0.4 * D.h01(i + 7)) * (0.4 + 0.6 * u)
		var p0 := cur + side * lat + back * l0
		var p1 := cur + side * lat + back * l1
		D.line(cv, p0, p1, D.ca(pal["c"], 0.5 * fade), maxf(1.0, t * 0.07))
		D.line(cv, p0, p1, D.ca(pal["b"], 0.95 * fade), maxf(1.0, t * 0.03))
	# the updraft itself: loops of wind rising round the rider
	for i in 3:
		var ph := fposmod(ms / 240.0 + float(i) / 3.0, 1.0)
		var cy := cur + Vector2(0, t * (0.4 - 0.85 * ph))
		var aa := sin(ph * PI) * fade
		cv.draw_set_transform(cy, 0.0, Vector2(1.0, 0.32))
		cv.draw_arc(Vector2.ZERO, t * (0.44 - 0.12 * ph), PI * (0.15 + ph), PI * (1.25 + ph), 10, D.ca(pal["b"], 0.9 * aa),
			maxf(1.0, t * 0.05), true)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	D.twinkle(cv, cur + dv * t * 0.42 + s * t * 0.1, t * 0.12 * fade * (1.0 - u * 0.5), D.ca(Color.WHITE, 0.9 * fade))


static func _paint_dust(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var p := D.px(V, cl["at"]) + Vector2(0, t * 0.32)
	var dv: Vector2 = cl["dir"]
	var kick := bool(cl.get("kick", false))
	var a := 1.0 - k
	for i in 7:
		var ang := TAU * float(i) / 7.0 + D.h01(i + 30) * 0.5
		var dir2 := Vector2(cos(ang), sin(ang) * 0.45)
		if kick:
			# kicked back, away from where the tender is going
			dir2 = (dir2 + dv * 0.9).normalized() * Vector2(1.0, 0.6)
		var r := t * (0.12 + 0.45 * D.ease_out(k)) * (0.7 + 0.5 * D.h01(i))
		var q := p + dir2 * r - Vector2(0, t * 0.2 * k)
		cv.draw_circle(q, t * (0.08 + 0.1 * k), D.ca(DUST, 0.55 * a))
	for i in 4:
		var ang2 := PI + PI * (0.15 + 0.7 * D.h01(i * 5 + 1))
		var q2 := D.arc_point(p, p + Vector2(cos(ang2), 0.2) * t * 0.6, D.ease_out(k), t * 0.3)
		cv.draw_circle(q2, t * 0.03, D.ca(Color(0.55, 0.48, 0.38), a))
