extends RefCounted
## Verb family: LINES - effects that travel a straight line from the tender.
##   lance      a sunbeam races down the line, lighting what it crosses
##   pull       a vine lashes out, hooks the target and reels it in
##   pull_line  the vine rakes the whole line, dragging everyone on it
##   wash_push  a water jet scours the line and shoves the first body
##   push_line  a gust streams down the line, clearing smoke, shoving a body
##   dash_dir   the tender rides a gust along the line
## build(op, c) lays the clips/segments and claims events (see shell/anim.gd);
## paint(cv, clip, k, V) draws this family's KINDS.

const L := preload("res://shell/anim_lib.gd")
const D := preload("res://shell/anim_draw.gd")

const OPS := ["lance", "pull", "pull_line", "wash_push", "push_line", "dash_dir"]
const KINDS := ["beam", "vine", "jet", "gust", "dash_trail"]

const BEAM_MS := 26     # per tile the lance travels
const VINE_MS := 45     # per tile the vine reaches
const JET_MS := 32
const GUST_MS := 30
const SHOVE_MS := 70    # per tile a shoved body slides


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


static func _lance(c: Dictionary) -> int:
	var t: int = c["t"]
	var o: Vector2i = c["ppos"]
	var d := _dir(c)
	var pierce := bool(c["eff"].get("pierce", false))
	var tiles := L.line(c["pre"], o, d, int(c["adef"].get("range", 3)), not pierce, true)
	var n := tiles.size()
	var end: Vector2i = tiles[n - 1] if n > 0 else o
	var travel := maxi(1, n) * BEAM_MS
	L.clip(c, {"kind": "beam", "t0": t, "dur": travel + 300, "from": o, "to": end, "dir": d,
		"travel": travel, "pierce": pierce, "at": o})
	var when := {}
	for j in n:
		when[tiles[j]] = t + (j + 1) * BEAM_MS
	_claim_on_line(c, when, Vector2(d))
	return t + travel + 120


## Claim the cast's events that happen ON the line at the moment the effect
## reaches each tile: hits (with the line's direction), ignitions, washes,
## cleared smoke and the hooks those set off.
static func _claim_on_line(c: Dictionary, when: Dictionary, d: Vector2) -> void:
	var evs: Array = c["events"]
	var aid := String(c["aid"])
	for i in L.unclaimed(c, ["damage", "ignite", "wash", "smoke_cleared", "hook"]):
		var ev: Dictionary = evs[i]
		var tt := String(ev["t"])
		if tt == "damage":
			if String(ev.get("who", "")) == "player" or String(ev.get("src", "")) != aid:
				continue
			var e = c["pre_en"].get(ev.get("id"))
			if e != null and when.has(e["pos"]):
				L.claim(c, i, int(when[e["pos"]]) + 15, d)
		elif ev.get("tile") is Vector2i and when.has(ev["tile"]):
			L.claim(c, i, int(when[ev["tile"]]))
			L.reveal(c, ev["tile"], int(when[ev["tile"]]))


static func _pull(c: Dictionary) -> int:
	var t: int = c["t"]
	var o: Vector2i = c["ppos"]
	var tgt = c.get("target")
	if not (tgt is Vector2i):
		return t
	var e = L.enemy_at(c["pre"], tgt)
	var dist := maxi(1, L.man(o, tgt))
	var reach := dist * VINE_MS
	var land: Vector2i = tgt
	if e != null:
		land = _landing(c, e, o)
	var drag := L.man(tgt, land) * SHOVE_MS
	L.clip(c, {"kind": "vine", "t0": t, "dur": reach + drag + 240, "from": o, "tips": [[tgt, land]],
		"reach": reach, "drag": drag, "at": o})
	if e != null:
		_reel_in(c, e, tgt, land, t + reach, drag, o)
	return t + reach + drag + 140


static func _pull_line(c: Dictionary) -> int:
	var t: int = c["t"]
	var o: Vector2i = c["ppos"]
	var d := _dir(c)
	var tiles := L.line(c["pre"], o, d, int(c["adef"].get("range", 3)), false, false)
	var far: Vector2i = tiles[tiles.size() - 1] if not tiles.is_empty() else o + d
	var tips: Array = []
	var bodies: Array = []
	for p in tiles:
		var e = L.enemy_at(c["pre"], p)
		if e != null:
			bodies.append(e)
			far = p
	var reach := maxi(1, L.man(o, far)) * VINE_MS
	var drag := 0
	for e in bodies:
		var land := _landing(c, e, o)
		tips.append([e["pos"], land])
		drag = maxi(drag, L.man(e["pos"], land) * SHOVE_MS)
	if tips.is_empty():
		tips.append([far, far])
	L.clip(c, {"kind": "vine", "t0": t, "dur": reach + drag + 280, "from": o, "tips": tips,
		"reach": reach, "drag": drag, "at": o, "rake": true})
	for j in bodies.size():
		var e: Dictionary = bodies[j]
		_reel_in(c, e, e["pos"], tips[j][1], t + reach + j * 40, drag, o)
	return t + reach + drag + 160


## Where a pulled enemy ends: its post tile, or (if the drag killed it) the
## sim's walk toward the tender on the pre board.
static func _landing(c: Dictionary, e: Dictionary, o: Vector2i) -> Vector2i:
	var pe = c["post_en"].get(e["id"])
	if pe != null:
		return pe["pos"]
	if L.massive(String(e["kind"])):
		return e["pos"]
	var d := Vector2i(signi(o.x - e["pos"].x), signi(o.y - e["pos"].y))
	return L.push_end(c["pre"], e["pos"], d, int(c["eff"].get("dist", 2)), e["id"], o)


static func _reel_in(c: Dictionary, e: Dictionary, from: Vector2i, land: Vector2i, t_hook: int, drag: int, o: Vector2i) -> void:
	if land != from:
		L.move(c, e["id"], L.path(c["pre"], from, land), t_hook, maxi(drag, 60), 0.0)
	var toward := L.dir_of(from, o)
	for i in L.unclaimed(c, ["damage", "status", "hook"]):
		var ev: Dictionary = c["events"][i]
		if ev.get("id") != e["id"]:
			continue
		var src := String(ev.get("src", ""))
		# terrain crossed mid-drag bites on the way; the lash lands at the end
		L.claim(c, i, t_hook + (drag / 2 if src.contains(":") else drag + 20), toward)


static func _wash(c: Dictionary, water: bool) -> int:
	var t: int = c["t"]
	var o: Vector2i = c["ppos"]
	var d := _dir(c)
	var tiles := L.line(c["pre"], o, d, int(c["adef"].get("range", 2)), false, false)
	var per := JET_MS if water else GUST_MS
	var n := tiles.size()
	var travel := maxi(1, n) * per
	var when := {}
	var body = null
	for j in n:
		when[tiles[j]] = t + (j + 1) * per
		if body == null and L.enemy_at(c["pre"], tiles[j]) != null:
			body = L.enemy_at(c["pre"], tiles[j])
	var end: Vector2i = tiles[n - 1] if n > 0 else o
	L.clip(c, {"kind": "jet" if water else "gust", "t0": t, "dur": travel + 340, "from": o, "to": end,
		"dir": d, "travel": travel, "at": o})
	_claim_on_line(c, when, Vector2(d))
	var t_end := t + travel + 160
	if body != null:
		var t_hit: int = when[body["pos"]]
		var dist := int(c["eff"].get("push", c["eff"].get("dist", 1)))
		t_end = maxi(t_end, shove(c, body, d, dist, t_hit))
	return t_end


## Shove `e` along d from time t_hit: slide to its post tile (or its death
## tile), collision damage at the stop. Returns when the shove settles.
static func shove(c: Dictionary, e: Dictionary, d: Vector2i, dist: int, t_hit: int) -> int:
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
	var t_stop := t_hit + slide
	var dv := Vector2(d)
	for i in L.unclaimed(c, ["damage", "hook", "status"]):
		var ev: Dictionary = c["events"][i]
		var src := String(ev.get("src", ""))
		if String(ev["t"]) == "damage" and src.begins_with("collision:"):
			# the shoved body and whatever it slammed into
			if ev.get("id") == e["id"] or (c["pre_en"].has(ev.get("id")) and L.man(c["pre_en"][ev["id"]]["pos"], land) <= 1):
				L.claim(c, i, t_stop, dv)
				if ev.get("id") == e["id"]:
					L.clip(c, {"kind": "spark", "t0": t_stop, "dur": 260, "at": land + d,
						"col": Color("e6edd8"), "n": 7})
		elif ev.get("id") == e["id"] and src.contains(":"):
			L.claim(c, i, t_hit + slide / 2, dv)
		elif String(ev["t"]) == "hook" and ev.get("tile") == land:
			L.claim(c, i, t_stop)
	return t_stop + 120


static func _dash(c: Dictionary) -> int:
	var t: int = c["t"]
	var o: Vector2i = c["ppos"]
	var to := o
	for i in L.unclaimed(c, ["dash"]):
		to = c["events"][i]["to"]
		L.claim(c, i, t)
		break
	var n := L.man(o, to)
	var dur := maxi(1, n) * 45 + 40
	if to != o:
		L.move(c, "player", L.path(c["pre"], o, to), t, dur, 0.05)
	L.clip(c, {"kind": "dash_trail", "t0": t, "dur": dur + 260, "from": o, "to": to, "travel": dur, "at": o})
	c["ppos"] = to
	# whatever the tiles did to the tender on the way lands as it arrives
	for i in L.unclaimed(c, ["damage", "item_pickup", "heal"]):
		if String(c["events"][i].get("who", "player")) == "player" or String(c["events"][i]["t"]) != "damage":
			L.claim(c, i, t + dur)
	return t + dur + 60


# --- paint -----------------------------------------------------------------------

static func paint(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	match String(cl["kind"]):
		"beam":
			_paint_beam(cv, cl, k, V)
		"vine":
			_paint_vine(cv, cl, k, V)
		"jet":
			_paint_jet(cv, cl, k, V)
		"gust":
			_paint_gust(cv, cl, k, V)
		"dash_trail":
			_paint_dash(cv, cl, k, V)


static func _paint_beam(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var dur := float(cl["dur"])
	var ms := k * dur
	var travel := float(cl["travel"])
	var a := D.px(V, cl["from"])
	var dv: Vector2 = Vector2(cl["dir"])
	var b := D.px(V, cl["to"]) + dv * t * 0.35
	var head := a.lerp(b, D.ease_out(clampf(ms / travel, 0.0, 1.0)))
	var fade := clampf(1.0 - (ms - travel) / maxf(1.0, dur - travel), 0.0, 1.0)
	var wid := t * (0.34 if bool(cl.get("pierce", false)) else 0.28) * (0.4 + 0.6 * fade)
	# muzzle glow at the tender, the shaft, a white-hot core, the head
	D.glow(cv, a, t * 0.42 * fade, D.ca(pal["a"], 0.7))
	D.line(cv, a, head, D.ca(pal["c"], 0.45 * fade), wid * 1.6)
	D.line(cv, a, head, D.ca(pal["a"], 0.9 * fade), wid)
	D.line(cv, a, head, D.ca(pal["b"], fade), wid * 0.38)
	# sun motes shed along the shaft
	var len := a.distance_to(head)
	if len > 1.0:
		var s := Vector2(-dv.y, dv.x)
		for i in 6:
			var u := D.h01(i * 7 + 3)
			var q := a.lerp(head, u) + s * (D.h01(i * 5 + 1) - 0.5) * t * 0.5 * (1.0 - fade + 0.3)
			cv.draw_circle(q, t * 0.04, D.ca(pal["b"], fade * 0.9))
	if ms < travel + 80.0:
		D.glow(cv, head, t * 0.3, D.ca(pal["b"], 0.9))
		D.star(cv, head, t * 0.32, D.ca(pal["b"], 0.9), 4, ms * 0.02, t * 0.05)
	elif fade > 0.0:
		D.glow(cv, head, t * 0.45 * fade, D.ca(pal["c"], 0.6))


static func _paint_vine(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var ms := k * float(cl["dur"])
	var reach := float(cl["reach"])
	var drag := maxf(1.0, float(cl["drag"]))
	var a := D.px(V, cl["from"])
	var fade := D.tail(k, 0.82)
	for tip in cl["tips"]:
		var hook_px := D.px(V, tip[0])
		var land_px := D.px(V, tip[1])
		var end: Vector2
		if ms < reach:
			end = a.lerp(hook_px, D.ease_out(ms / reach))
		elif ms < reach + drag:
			end = hook_px.lerp(land_px, D.ease_io((ms - reach) / drag))
		else:
			# snap back to the hand
			end = land_px.lerp(a, D.ease_in(clampf((ms - reach - drag) / 180.0, 0.0, 1.0)))
		var amp := t * 0.14 * (1.0 if ms < reach else 0.4)
		D.wavy(cv, a, end, amp, 2.0, ms * 0.02, D.ca(pal["c"], fade), t * 0.13, 20)
		D.wavy(cv, a, end, amp, 2.0, ms * 0.02, D.ca(pal["a"], fade), t * 0.08, 20)
		var ang := (end - a).angle()
		D.leaf(cv, end, ang, t * 0.3, D.ca(pal["b"], fade))
		for j in 3:
			var u := 0.25 + 0.25 * float(j)
			D.leaf(cv, a.lerp(end, u), ang + (0.9 if j % 2 == 0 else -0.9), t * 0.16, D.ca(pal["a"], fade))


static func _paint_jet(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var ms := k * float(cl["dur"])
	var travel := float(cl["travel"])
	var dv: Vector2 = Vector2(cl["dir"])
	var a := D.px(V, cl["from"]) + dv * t * 0.3
	var b := D.px(V, cl["to"]) + dv * t * 0.4
	var head := a.lerp(b, clampf(ms / travel, 0.0, 1.0))
	var fade := D.tail(k, 0.55)
	var s := Vector2(-dv.y, dv.x)
	D.wavy(cv, a, head, t * 0.08, 3.0, -ms * 0.03, D.ca(pal["c"], 0.7 * fade), t * 0.34, 22)
	D.wavy(cv, a, head, t * 0.06, 3.0, -ms * 0.03 + 1.0, D.ca(pal["a"], 0.95 * fade), t * 0.22, 22)
	D.wavy(cv, a, head, t * 0.04, 4.0, -ms * 0.04 + 2.0, D.ca(pal["b"], fade), t * 0.08, 22)
	# spray off the head
	for i in 6:
		var u := D.h01(i * 13 + 2)
		var q := head + dv * t * 0.2 * u + s * (u - 0.5) * t * 0.7 * D.ease_out(clampf(ms / travel, 0.0, 1.0))
		cv.draw_circle(q, t * 0.05 * fade, D.ca(pal["b"], fade))


static func _paint_gust(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var ms := k * float(cl["dur"])
	var travel := float(cl["travel"])
	var dv: Vector2 = Vector2(cl["dir"])
	var s := Vector2(-dv.y, dv.x)
	var a := D.px(V, cl["from"])
	var b := D.px(V, cl["to"]) + dv * t * 0.5
	var fade := D.tail(k, 0.5)
	# streamlines racing ahead of each other, with a curl at the head
	for i in 4:
		var lag := float(i) * 0.12
		var u := clampf(ms / travel - lag, 0.0, 1.0)
		var off := s * (float(i) - 1.5) * t * 0.18
		var head := a.lerp(b, D.ease_out(u)) + off
		var tailp := a.lerp(b, maxf(0.0, D.ease_out(u) - 0.45)) + off
		D.line(cv, tailp, head, D.ca(pal["b"] if i % 2 == 0 else pal["a"], 0.85 * fade), t * 0.05)
		if u > 0.0 and u < 1.0:
			cv.draw_arc(head - s * t * 0.08, t * 0.08, dv.angle() - PI * 0.5, dv.angle() + PI, 8,
				D.ca(pal["b"], fade), maxf(1.0, t * 0.04), true)


static func _paint_dash(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var ms := k * float(cl["dur"])
	var travel := maxf(1.0, float(cl["travel"]))
	var a := D.px(V, cl["from"])
	var b := D.px(V, cl["to"])
	var u := clampf(ms / travel, 0.0, 1.0)
	var head := a.lerp(b, u)
	var fade := D.tail(k, 0.45)
	var dv := (b - a).normalized() if a.distance_to(b) > 1.0 else Vector2.RIGHT
	var s := Vector2(-dv.y, dv.x)
	for i in 3:
		var off := s * (float(i) - 1.0) * t * 0.22
		D.line(cv, a + off, head + off - dv * t * 0.25, D.ca(pal["b"] if i == 1 else pal["a"], 0.7 * fade), t * 0.05)
	# afterimages
	for j in 3:
		var q := a.lerp(head, float(j + 1) / 4.0)
		cv.draw_circle(q, t * 0.22, D.ca(pal["a"], 0.18 * fade))
	D.ring(cv, a, t * (0.2 + 0.4 * D.ease_out(k)), D.ca(pal["b"], 0.8 * (1.0 - k)), t * 0.05)
