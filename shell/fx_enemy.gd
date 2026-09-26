extends RefCounted
## Verb family: ENEMY INTENTS - what each machine's turn looks like. The
## director (shell/anim.gd _plan_enemy_phase) hands each acting enemy a slot:
##   c.t      slot start (ms)         c.e       the enemy as it was (pre)
##   c.post_e the enemy after, or null  c.own    event indices it caused
## A builder draws the intent, moves the body, claims its own events (the
## ones it leaves are claimed at c.t + c.hit) and returns when it settles.
## INTENTS covers every type Game._execute_intent runs (tests/test_content.gd
## INTENT_TYPES) plus "blocked" (a status swallowed the intent) and
## "screened" (smoke swallowed it).

const Content := preload("res://sim/content.gd")
const L := preload("res://shell/anim_lib.gd")
const D := preload("res://shell/anim_draw.gd")

const INTENTS := ["idle", "move", "advance", "attack", "slam", "quake", "flood", "ignite_all", "gather",
	"ooze", "stoke", "drag", "dredge", "summon", "gum", "drain", "fuse", "blocked", "screened"]
const KINDS := ["bite", "slam_wave", "quake_rings", "flood_wave", "ignite_wave", "gather_glow", "ooze_drip",
	"stoke_puff", "chain", "siphon", "tar_glob", "dredge_tendrils", "weld", "fizzle", "struggle_mark"]

const STEP_MS := 150
const MACHINE := {"a": Color("e04b3a"), "b": Color("ffd0c8"), "c": Color("5d5348")}


static func build(verb: String, c: Dictionary) -> int:
	c["pal"] = MACHINE
	match verb:
		"move":
			return _walk(c, 0.14, false)
		"advance":
			return _walk(c, 0.22, true)
		"attack":
			return _attack(c)
		"slam":
			return _slam(c)
		"quake":
			return _quake(c)
		"flood":
			return _flood(c)
		"ignite_all":
			return _ignite_all(c)
		"gather":
			return _simple(c, "gather_glow", 520, 300)
		"ooze":
			return _ooze(c)
		"stoke":
			return _simple(c, "stoke_puff", 560, 200)
		"drag":
			return _drag(c)
		"dredge":
			return _dredge(c)
		"summon":
			return _simple(c, "gather_glow", 420, 200)
		"gum":
			return _projectile(c, "tar_glob", Color("3a2e24"))
		"drain":
			return _projectile(c, "siphon", Color("f7c948"))
		"fuse":
			return _fuse(c)
		"blocked":
			return _blocked(c)
		"screened":
			return _screened(c)
	return int(c["t"]) + 120


static func _pos(c: Dictionary) -> Vector2i:
	return c["e"]["pos"]


static func _ppos(c: Dictionary) -> Vector2i:
	return c["p0"]


## Walk the enemy from its pre tile to its post tile, hop by hop. A mover that
## died on the way (walked into fire) is walked onto the burning tile first.
static func _walk(c: Dictionary, hop: float, stomp: bool) -> int:
	var t: int = c["t"]
	var e: Dictionary = c["e"]
	var from: Vector2i = e["pos"]
	var to := from
	if c["post_e"] != null:
		to = c["post_e"]["pos"]
	else:
		to = _death_step(c, from)
	var pts := L.path(c["pre"], from, to)
	var hops := pts.size() - 1
	if hops <= 0:
		return t + 80
	var dur := hops * STEP_MS
	if Content.ENEMIES.get(String(e["kind"]), {}).get("traits", []).has("fast"):
		dur = hops * 105
	L.move(c, e["id"], pts, t, dur, hop)
	L.seg(c, e["id"], {"kind": "squash", "t0": t + dur - 30, "dur": 130})
	if stomp:
		for j in hops:
			c["reel"]["shakes"].append({"t0": t + (j + 1) * STEP_MS - 20, "mag": 4.0})
	# an oil trail appears as the body leaves each tile
	var sw: Dictionary = c["reel"]["tswap"]
	for j in hops:
		var p: Vector2i = pts[j]
		if sw.has(p) and String(sw[p]["post"]) == "oil":
			L.reveal(c, p, t + j * STEP_MS + STEP_MS / 2)
	# what the tiles do to it lands on arrival
	for i in c["own"]:
		if not L.claimed(c, i):
			L.claim(c, i, t + dur)
	c["hit"] = dur
	return t + dur + 60


## Best guess at the tile a dead mover died on: an adjacent burning tile
## nearer the tender, else where it stood.
static func _death_step(c: Dictionary, from: Vector2i) -> Vector2i:
	var best := from
	var bd := L.man(from, _ppos(c))
	for d in L.DIRS:
		var p: Vector2i = from + d
		if int(Content.terrain(L.tkind(c["pre"], p), "enter_dmg_enemy", 0)) > 0 and L.man(p, _ppos(c)) < bd:
			best = p
			bd = L.man(p, _ppos(c))
	return best


static func _attack(c: Dictionary) -> int:
	var t: int = c["t"]
	var e: Dictionary = c["e"]
	var tile = e["intent"].get("tile", _ppos(c))
	if not (tile is Vector2i):
		tile = _ppos(c)
	var d := L.dir_of(e["pos"], tile)
	L.seg(c, e["id"], {"kind": "lunge", "t0": t, "dur": 260, "dir": d, "reach": 0.42})
	L.clip(c, {"kind": "bite", "t0": t + 70, "dur": 260, "at": tile, "dir": d})
	_claim_hits(c, t + 110, d)
	c["hit"] = 110
	return t + 280


## The enemy's own events: damage to the tender (recoils along the blow),
## thorns biting back (recoils the attacker), and the rest at t_hit.
static func _claim_hits(c: Dictionary, t_hit: int, d: Vector2) -> void:
	var e: Dictionary = c["e"]
	for i in c["own"]:
		if L.claimed(c, i):
			continue
		var ev: Dictionary = c["events"][i]
		if String(ev.get("t", "")) == "damage" and String(ev.get("who", "")) == "player":
			L.claim(c, i, t_hit, d)
		elif String(ev.get("t", "")) == "damage" and ev.get("id") == e["id"]:
			L.claim(c, i, t_hit + 60, -d)
			if String(ev.get("src", "")) == "thorns":
				L.clip(c, {"kind": "spark", "t0": t_hit + 50, "dur": 260, "at": e["pos"],
					"col": Color("57b34a"), "n": 7})
		else:
			L.claim(c, i, t_hit + 30)


static func _slam(c: Dictionary) -> int:
	var t: int = c["t"]
	var e: Dictionary = c["e"]
	var tile = e["intent"].get("tile", _ppos(c))
	if not (tile is Vector2i):
		tile = _ppos(c)
	L.seg(c, e["id"], {"kind": "path", "t0": t, "dur": 240, "pts": [Vector2(e["pos"]), Vector2(e["pos"])], "hop": 0.5})
	L.seg(c, e["id"], {"kind": "squash", "t0": t + 230, "dur": 160})
	L.clip(c, {"kind": "slam_wave", "t0": t + 230, "dur": 420, "at": tile, "layer": "ground"})
	c["reel"]["shakes"].append({"t0": t + 230, "mag": 6.0})
	_claim_hits(c, t + 240, L.dir_of(tile, _ppos(c)) if tile != _ppos(c) else Vector2(0, 1))
	c["hit"] = 240
	return t + 420


static func _quake(c: Dictionary) -> int:
	var t: int = c["t"]
	var e: Dictionary = c["e"]
	L.seg(c, e["id"], {"kind": "shake", "t0": t, "dur": 300, "amt": 0.06})
	L.clip(c, {"kind": "quake_rings", "t0": t + 80, "dur": 520, "at": e["pos"], "layer": "ground"})
	c["reel"]["shakes"].append({"t0": t + 100, "mag": 7.0})
	_claim_hits(c, t + 170, L.dir_of(e["pos"], _ppos(c)))
	c["hit"] = 170
	return t + 420


static func _flood(c: Dictionary) -> int:
	var t: int = c["t"]
	var e: Dictionary = c["e"]
	var row := int(e["intent"].get("row", e["pos"].y))
	var w := int(c["pre"]["map"]["w"])
	L.seg(c, e["id"], {"kind": "shake", "t0": t, "dur": 260, "amt": 0.05})
	L.clip(c, {"kind": "flood_wave", "t0": t + 60, "dur": 700, "at": Vector2i(e["pos"].x, row), "row": row, "w": w,
		"from_x": e["pos"].x, "layer": "ground"})
	var sw: Dictionary = c["reel"]["tswap"]
	for p in sw:
		if p.y == row and String(sw[p]["post"]) == "oil" and not sw[p].has("t"):
			L.reveal(c, p, t + 60 + absi(p.x - e["pos"].x) * 30)
	_claim_hits(c, t + 200, Vector2(0, 1))
	c["hit"] = 200
	return t + 560


static func _ignite_all(c: Dictionary) -> int:
	var t: int = c["t"]
	var e: Dictionary = c["e"]
	L.clip(c, {"kind": "gather_glow", "t0": t, "dur": 300, "at": e["pos"], "col": Color("ef933a")})
	var sw: Dictionary = c["reel"]["tswap"]
	var tiles: Array = []
	for p in sw:
		if String(sw[p]["post"]) == "fire" and not sw[p].has("t"):
			tiles.append(p)
	for p in tiles:
		var tt: int = t + 220 + L.man(p, e["pos"]) * 40
		L.reveal(c, p, tt)
		L.clip(c, {"kind": "flare", "t0": tt, "dur": 420, "at": p, "col": Color("ef933a")})
	L.clip(c, {"kind": "ignite_wave", "t0": t + 200, "dur": 520, "at": e["pos"], "layer": "ground"})
	_claim_hits(c, t + 240, Vector2(0, 1))
	c["hit"] = 240
	return t + 600


static func _simple(c: Dictionary, kind: String, dur: int, hit: int) -> int:
	var t: int = c["t"]
	var e: Dictionary = c["e"]
	L.seg(c, e["id"], {"kind": "shake", "t0": t, "dur": mini(dur, 320), "amt": 0.04})
	L.clip(c, {"kind": kind, "t0": t, "dur": dur, "at": e["pos"]})
	_claim_hits(c, t + hit, Vector2(0, -1))
	c["hit"] = hit
	return t + dur - 120


static func _ooze(c: Dictionary) -> int:
	var t: int = c["t"]
	var e: Dictionary = c["e"]
	var landed := false
	for i in c["own"]:
		var ev: Dictionary = c["events"][i]
		if String(ev.get("t", "")) == "ooze" and ev.get("tile") is Vector2i:
			L.clip(c, {"kind": "ooze_drip", "t0": t, "dur": 460, "from": e["pos"], "to": ev["tile"], "at": ev["tile"]})
			L.claim(c, i, t + 300)
			L.reveal(c, ev["tile"], t + 300)
			landed = true
	L.seg(c, e["id"], {"kind": "squash", "t0": t, "dur": 220 if landed else 160})
	return t + (420 if landed else 200)


static func _drag(c: Dictionary) -> int:
	var t: int = c["t"]
	var e: Dictionary = c["e"]
	var pts: Array = [_ppos(c)]
	var j := 0
	for i in c["own"]:
		var ev: Dictionary = c["events"][i]
		if String(ev.get("t", "")) == "drag" and ev.get("to") is Vector2i:
			pts.append(ev["to"])
			L.claim(c, i, t + 180 + j * 150)
			j += 1
		elif String(ev.get("t", "")) == "anchored":
			L.claim(c, i, t + 200)
	L.clip(c, {"kind": "chain", "t0": t, "dur": 260 + maxi(1, j) * 150 + 120, "from": e["pos"], "to": _ppos(c),
		"pull_ms": 180, "held": j == 0, "at": e["pos"]})
	if pts.size() >= 2:
		L.move(c, "player", pts, t + 180, (pts.size() - 1) * 150, 0.0)
	_claim_hits(c, t + 180 + j * 150, L.dir_of(_ppos(c), e["pos"]))
	c["hit"] = 180 + j * 150
	return t + 260 + maxi(1, j) * 150


static func _dredge(c: Dictionary) -> int:
	var t: int = c["t"]
	var e: Dictionary = c["e"]
	var sw: Dictionary = c["reel"]["tswap"]
	var tiles: Array = []
	for p in sw:
		if String(sw[p]["pre"]) == "growth" and String(sw[p]["post"]) == "goo" and not sw[p].has("t"):
			tiles.append(p)
			L.reveal(c, p, t + 200 + L.man(p, e["pos"]) * 60)
	L.clip(c, {"kind": "dredge_tendrils", "t0": t, "dur": 620, "at": e["pos"], "tiles": tiles})
	_claim_hits(c, t + 360, Vector2(0, -1))
	c["hit"] = 360
	return t + 560


## A ranged intent: something flies from the enemy to the tender (a tar glob)
## or streams from the tender to the enemy (a charge siphon).
static func _projectile(c: Dictionary, kind: String, col: Color) -> int:
	var t: int = c["t"]
	var e: Dictionary = c["e"]
	var fired := false
	for i in c["own"]:
		var tt := String(c["events"][i].get("t", ""))
		if tt == "gummed" or tt == "drain":
			fired = true
	if not fired:
		# out of range: the machine winds up and nothing comes of it
		L.seg(c, e["id"], {"kind": "shake", "t0": t, "dur": 200, "amt": 0.03})
		return t + 160
	var dist := maxi(1, L.man(e["pos"], _ppos(c)))
	var fly := 140 + dist * 40
	L.seg(c, e["id"], {"kind": "lunge", "t0": t, "dur": 200, "dir": L.dir_of(e["pos"], _ppos(c)), "reach": 0.15})
	L.clip(c, {"kind": kind, "t0": t + 40, "dur": fly + 300, "from": e["pos"], "to": _ppos(c), "fly": fly,
		"col": col, "at": e["pos"]})
	_claim_hits(c, t + 40 + fly, L.dir_of(e["pos"], _ppos(c)))
	c["hit"] = 40 + fly
	return t + 40 + fly + 120


static func _fuse(c: Dictionary) -> int:
	var t: int = c["t"]
	var e: Dictionary = c["e"]
	for i in c["own"]:
		var ev: Dictionary = c["events"][i]
		if String(ev.get("t", "")) != "assimilate":
			continue
		var eaten = c["pre_en"].get(ev.get("eaten"))
		if eaten != null:
			L.move(c, eaten["id"], [eaten["pos"], e["pos"]], t + 60, 240, 0.1)
			L.seg(c, eaten["id"], {"kind": "die", "t0": t + 280, "dur": 120})
		L.claim(c, i, t + 300)
		L.clip(c, {"kind": "weld", "t0": t + 200, "dur": 520, "at": e["pos"]})
		L.seg(c, e["id"], {"kind": "pop", "t0": t + 300, "dur": 260})
	c["hit"] = 300
	return t + 560


static func _blocked(c: Dictionary) -> int:
	var t: int = c["t"]
	var e: Dictionary = c["e"]
	var status := ""
	for i in c["own"]:
		var tt := String(c["events"][i].get("t", ""))
		for sname in Content.STATUSES:
			if String(Content.STATUSES[sname].get("blocked_event", sname)) == tt:
				status = sname
				L.claim(c, i, t + 40)
				L.quiet(c, i)
	L.seg(c, e["id"], {"kind": "struggle", "t0": t, "dur": 360})
	L.clip(c, {"kind": "struggle_mark", "t0": t, "dur": 480, "at": e["pos"], "status": status})
	return t + 320


static func _screened(c: Dictionary) -> int:
	var t: int = c["t"]
	var e: Dictionary = c["e"]
	for i in c["own"]:
		if String(c["events"][i].get("t", "")) == "screened":
			L.claim(c, i, t + 120)
	L.seg(c, e["id"], {"kind": "shake", "t0": t, "dur": 240, "amt": 0.04})
	L.clip(c, {"kind": "fizzle", "t0": t + 60, "dur": 520, "at": e["pos"], "to": _ppos(c)})
	return t + 360


# --- paint -----------------------------------------------------------------------

static func paint(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	match String(cl["kind"]):
		"bite":
			var c := D.px(V, cl["at"])
			var d: Vector2 = cl.get("dir", Vector2.RIGHT)
			var s := Vector2(-d.y, d.x)
			var close := D.ease_in(D.win(k, 0.0, 0.35))
			var fade := D.tail(k, 0.35)
			for sd in [-1.0, 1.0]:
				var side: float = sd
				var root := c - d * t * 0.45 + s * side * t * (0.4 - 0.3 * close)
				for j in 3:
					var off := s * side * t * 0.05 * float(j)
					D.spike(cv, root + off + d * t * 0.1 * float(j), root + off + d * t * (0.35 + 0.1 * float(j)) - s * side * t * 0.15 * close,
						t * 0.08, D.ca(Color("e6edd8"), fade))
			if k > 0.3:
				var u := D.win(k, 0.3, 1.0)
				D.star(cv, c, t * (0.2 + 0.25 * u), D.ca(Color("e04b3a"), 1.0 - u), 6, 0.3, t * 0.06)
		"slam_wave":
			var c := D.px(V, cl["at"])
			var u := D.ease_out(k)
			var fade := 1.0 - k
			for d in L.DIRS:
				var dv := Vector2(d)
				var r := D.tile_rect(V, Vector2(cl["at"]) + dv)
				cv.draw_rect(r.grow(-t * 0.1 * (1.0 - u)), D.ca(Color("e04b3a"), 0.35 * fade))
			cv.draw_rect(D.tile_rect(V, cl["at"]), D.ca(Color("ff8a70"), 0.45 * fade))
			D.ring(cv, c, t * (0.3 + 1.3 * u), D.ca(Color("ffd0c8"), fade), t * 0.12 * fade)
			for i in 8:
				var ang := TAU * float(i) / 8.0
				cv.draw_circle(c + Vector2(cos(ang), sin(ang)) * t * (0.4 + 0.9 * u) + Vector2(0, -t * 0.3 * sin(u * PI)),
					t * 0.05, D.ca(Color("6b5a44"), fade))
		"quake_rings":
			var c := D.px(V, cl["at"])
			for j in 3:
				var u := D.win(k, float(j) * 0.15, float(j) * 0.15 + 0.7)
				if u > 0.0 and u < 1.0:
					cv.draw_set_transform(c + Vector2(0, t * 0.25), 0.0, Vector2(1.0, 0.6))
					D.ring(cv, Vector2.ZERO, t * (0.4 + 1.3 * u), D.ca(Color("c9a63c"), 1.0 - u), t * 0.1 * (1.0 - u))
					cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"flood_wave":
			var row := int(cl["row"])
			var w := int(cl["w"])
			var x0 := float(cl["from_x"])
			var reach := k * float(w)
			var fade := D.tail(k, 0.7)
			for x in range(1, w - 1):
				var dx := absf(float(x) - x0)
				if dx > reach:
					continue
				var r := D.tile_rect(V, Vector2(x, row))
				var crest := 1.0 - clampf((reach - dx) / 3.0, 0.0, 1.0)
				cv.draw_rect(r, D.ca(Color("241c18"), 0.35 * fade))
				cv.draw_circle(r.get_center() + Vector2(0, -t * 0.15 * crest), t * 0.18 * crest, D.ca(Color("6b5a78"), 0.7 * crest * fade))
		"ignite_wave":
			var c := D.px(V, cl["at"])
			D.ring(cv, c, t * (0.5 + 5.0 * D.ease_out(k)), D.ca(Color("ef933a"), 0.6 * (1.0 - k)), t * 0.2 * (1.0 - k))
		"gather_glow":
			var c := D.px(V, cl["at"])
			var col: Color = cl.get("col", Color("e04b3a"))
			var g := D.pulse(k)
			D.glow(cv, c, t * (0.35 + 0.3 * g), D.ca(col, 0.6 * g))
			for i in 6:
				var ang := TAU * float(i) / 6.0 + k * 3.0
				var r := t * 0.8 * (1.0 - k)
				cv.draw_circle(c + Vector2(cos(ang), sin(ang)) * r, t * 0.04, D.ca(col.lightened(0.3), g))
		"ooze_drip":
			var a := D.px(V, cl["from"])
			var b := D.px(V, cl["to"])
			var u := D.ease_io(D.win(k, 0.0, 0.6))
			var q := D.arc_point(a, b, u, t * 0.35)
			var fade := D.tail(k, 0.6)
			cv.draw_circle(q, t * 0.14, D.ca(Color("241c18"), fade))
			cv.draw_circle(q + Vector2(-t * 0.04, -t * 0.04), t * 0.05, D.ca(Color("8a76a0"), fade))
			if k > 0.6:
				var s := D.win(k, 0.6, 1.0)
				cv.draw_set_transform(b + Vector2(0, t * 0.2), 0.0, Vector2(1.0, 0.5))
				cv.draw_circle(Vector2.ZERO, t * 0.4 * D.ease_out(s), D.ca(Color("3a2e3f"), 0.6 * (1.0 - s)))
				cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"stoke_puff":
			var c := D.px(V, cl["at"]) + Vector2(0, -t * 0.45)
			for i in 5:
				var u := D.win(k, float(i) * 0.1, float(i) * 0.1 + 0.6)
				if u > 0.0 and u < 1.0:
					cv.draw_circle(c + Vector2(sin(float(i) * 2.0) * t * 0.2 * u, -t * 0.9 * u), t * (0.12 + 0.2 * u),
						D.ca(Color("6b6f72"), 0.7 * (1.0 - u)))
			D.glow(cv, c + Vector2(0, t * 0.1), t * 0.3 * D.pulse(k), D.ca(Color("ef933a"), 0.5))
		"chain":
			var a := D.px(V, cl["from"])
			var ms := k * float(cl["dur"])
			var pull := float(cl.get("pull_ms", 180))
			var b := D.px(V, cl["to"])
			var u := clampf(ms / pull, 0.0, 1.0)
			var end := a.lerp(b, D.ease_out(u))
			var fade := D.tail(k, 0.75)
			var n := int(a.distance_to(end) / (t * 0.2))
			for i in n:
				var q := a.lerp(end, (float(i) + 0.5) / maxf(1.0, float(n)))
				D.ring(cv, q, t * 0.07, D.ca(Color("9aa7b0"), fade), t * 0.035)
			D.glow(cv, end, t * 0.2, D.ca(Color("7ec8e0"), 0.8 * fade))
			if bool(cl.get("held", false)) and u >= 1.0:
				D.star(cv, end, t * 0.3, D.ca(Color("dcb880"), fade), 6, 0.0, t * 0.05)
		"siphon", "tar_glob":
			var a := D.px(V, cl["from"])
			var b := D.px(V, cl["to"])
			var col: Color = cl.get("col", Color("3a2e24"))
			var ms := k * float(cl["dur"])
			var fly := maxf(1.0, float(cl["fly"]))
			if String(cl["kind"]) == "tar_glob":
				if ms < fly:
					var q := D.arc_point(a, b, ms / fly, t * 0.5)
					cv.draw_circle(q, t * 0.14, col)
					cv.draw_circle(q + Vector2(-t * 0.04, -t * 0.05), t * 0.05, Color("8a7a5e"))
				else:
					var s := clampf((ms - fly) / maxf(1.0, float(cl["dur"]) - fly), 0.0, 1.0)
					for i in 6:
						var ang := TAU * float(i) / 6.0
						cv.draw_circle(b + Vector2(cos(ang), sin(ang)) * t * 0.35 * D.ease_out(s), t * 0.06 * (1.0 - s), D.ca(col, 1.0 - s))
			else:
				# charge motes pulled out of the tender into the drone
				for i in 7:
					var u := D.win(ms / fly, float(i) * 0.08, float(i) * 0.08 + 0.6)
					if u > 0.0 and u < 1.0:
						var q := b.lerp(a, D.ease_in(u)) + Vector2(sin(u * 9.0 + float(i)) * t * 0.1, 0)
						D.twinkle(cv, q, t * 0.08, D.ca(col, 1.0 - u * 0.5))
				D.line(cv, a, b, D.ca(Color("e04b3a"), 0.3 * D.pulse(k)), t * 0.04)
		"dredge_tendrils":
			var c := D.px(V, cl["at"])
			var fade := D.tail(k, 0.6)
			for p in cl.get("tiles", []):
				var q := D.px(V, p)
				var u := D.ease_out(D.win(k, 0.0, 0.5))
				D.wavy(cv, c, c.lerp(q, u), t * 0.1, 1.5, k * 8.0, D.ca(Color("655626"), fade), t * 0.09, 12)
			D.glow(cv, c, t * 0.4 * D.pulse(k), D.ca(Color("8a7a3f"), 0.6))
		"weld":
			var c := D.px(V, cl["at"])
			D.glow(cv, c, t * 0.5 * (1.0 - k), D.ca(Color("fdf0a8"), 0.8))
			for i in 10:
				var ang := TAU * D.h01(i * 7)
				var r := t * (0.2 + 0.6 * D.ease_out(k)) * (0.5 + 0.5 * D.h01(i * 3 + 1))
				cv.draw_circle(c + Vector2(cos(ang), sin(ang)) * r + Vector2(0, t * 0.4 * k * k), t * 0.04, D.ca(Color("e8722a"), 1.0 - k))
		"fizzle":
			var c := D.px(V, cl["at"])
			var fade := 1.0 - k
			for i in 4:
				var u := D.win(k, float(i) * 0.1, float(i) * 0.1 + 0.7)
				cv.draw_circle(c + Vector2((float(i) - 1.5) * t * 0.15, -t * (0.3 + 0.4 * u)), t * (0.08 + 0.1 * u),
					D.ca(Color("9aa0a4"), 0.7 * (1.0 - u)))
			D.text(cv, V, c + Vector2(0, -t * (0.55 + 0.2 * k)), "?", D.ca(Color("dde2e4"), fade), int(t * 0.5))
		"struggle_mark":
			var c := D.px(V, cl["at"])
			var col := L.status_col(String(cl.get("status", "")))
			D.ring(cv, c, t * (0.4 + 0.1 * sin(k * PI * 6.0)), D.ca(col, 0.9 * (1.0 - k)), t * 0.07)
			for i in 4:
				var ang := TAU * float(i) / 4.0 + PI * 0.25
				D.line(cv, c + Vector2(cos(ang), sin(ang)) * t * 0.45, c + Vector2(cos(ang), sin(ang)) * t * 0.62,
					D.ca(col, 1.0 - k), t * 0.06)
