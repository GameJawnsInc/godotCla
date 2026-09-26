extends RefCounted
## Verb family: AREAS - effects that fill a manhattan diamond.
##   aoe_damage      a nova rolls out ring by ring (sun flare, geyser, scatter)
##   aoe_status      a pollen / spore cloud billows (thrown first when centred
##                   on a target tile)
##   wash_all        a tide surges out four ways, shoving what it meets
##   push_all        a shock ring bursts, shoving the neighbours back
##   clear_smoke     a whirlwind spirals out and lifts the smoke
##   convert_radius  a green (or root) wave rewrites the filth
##   grow_radius     a seed is lobbed and bursts into a ring of sprouts
## Rings arrive in order: a tile at manhattan distance d from the centre is
## reached at t + d * RING_MS, and so is everything that happens on it.

const L := preload("res://shell/anim_lib.gd")
const D := preload("res://shell/anim_draw.gd")
const FxLines := preload("res://shell/fx_lines.gd")

const OPS := ["aoe_damage", "aoe_status", "wash_all", "push_all", "clear_smoke", "convert_radius", "grow_radius"]
const KINDS := ["nova", "cloud", "tide", "shock", "swirl", "conversion", "seed_lob", "sprout"]

const RING_MS := 75
const LOB_MS := 230


static func build(op: String, c: Dictionary) -> int:
	match op:
		"aoe_damage":
			return _nova(c)
		"aoe_status":
			return _cloud(c)
		"wash_all":
			return _tide(c)
		"push_all":
			return _shock(c)
		"clear_smoke":
			return _swirl(c)
		"convert_radius":
			return _convert(c)
		"grow_radius":
			return _grow(c)
	return int(c["t"])


## Claim every event of the cast on a tile within `r` of `center` at the time
## the ring reaches it; hits recoil away from the centre.
static func _claim_rings(c: Dictionary, center: Vector2i, r: int, t: int, types: Array) -> void:
	var evs: Array = c["events"]
	var aid := String(c["aid"])
	for i in L.unclaimed(c, types):
		var ev: Dictionary = evs[i]
		var tile = null
		if String(ev["t"]) == "damage":
			if String(ev.get("who", "")) == "player" or String(ev.get("src", "")) != aid:
				continue
			var e = c["pre_en"].get(ev.get("id"))
			if e != null:
				tile = e["pos"]
		elif String(ev["t"]) == "status":
			var e2 = c["pre_en"].get(ev.get("id"))
			if e2 != null:
				tile = e2["pos"]
		else:
			tile = ev.get("tile")
		if not (tile is Vector2i) or L.man(tile, center) > r:
			continue
		var tt := t + L.man(tile, center) * RING_MS
		L.claim(c, i, tt + (15 if String(ev["t"]) == "damage" else 0), L.dir_of(center, tile))
		if ev.get("tile") is Vector2i:
			L.reveal(c, ev["tile"], tt)


static func _nova(c: Dictionary) -> int:
	var t: int = c["t"]
	var center: Vector2i = c["ppos"]
	var r := int(c["eff"].get("radius", 1))
	L.clip(c, {"kind": "nova", "t0": t, "dur": r * RING_MS + 380, "at": center, "r": r,
		"ring_ms": RING_MS, "fire": bool(c["eff"].get("ignite", false)), "layer": "ground"})
	L.clip(c, {"kind": "ring", "t0": t, "dur": r * RING_MS + 240, "at": center, "r0": 0.3, "r1": float(r) + 0.6,
		"col": c["pal"]["b"], "w": 0.1})
	_claim_rings(c, center, r, t, ["damage", "ignite", "hook"])
	return t + r * RING_MS + 160


static func _cloud(c: Dictionary) -> int:
	var t: int = c["t"]
	var eff: Dictionary = c["eff"]
	var r := int(eff.get("radius", 1))
	var center: Vector2i = c["ppos"]
	if String(eff.get("center", "self")) == "target" and c.get("target") is Vector2i:
		center = c["target"]
	var status := String(eff.get("status", ""))
	var t_land := t
	if center != c["ppos"]:
		L.clip(c, {"kind": "seed_lob", "t0": t, "dur": LOB_MS, "from": c["ppos"], "to": center,
			"col": L.status_col(status), "at": center})
		t_land = t + LOB_MS
	L.clip(c, {"kind": "cloud", "t0": t_land, "dur": r * RING_MS + 620, "at": center, "r": r,
		"status": status, "ring_ms": RING_MS})
	_claim_rings(c, center, r, t_land, ["status", "resisted", "immune"])
	# statuses the cloud landed were already drawn by it: keep their pops
	# (they name the status on the creature) but no extra ring
	return t_land + r * RING_MS + 220


static func _tide(c: Dictionary) -> int:
	var t: int = c["t"]
	var o: Vector2i = c["ppos"]
	var rng := int(c["adef"].get("range", 2))
	L.clip(c, {"kind": "tide", "t0": t, "dur": rng * RING_MS + 460, "at": o, "r": rng, "ring_ms": RING_MS,
		"layer": "ground"})
	_claim_rings(c, o, rng, t, ["wash", "hook"])
	var t_end := t + rng * RING_MS + 180
	var push := int(c["eff"].get("push", 1))
	for d in L.DIRS:
		for p in L.line(c["pre"], o, d, rng, false, false):
			var e = L.enemy_at(c["pre"], p)
			if e != null:
				t_end = maxi(t_end, FxLines.shove(c, e, d, push, t + L.man(o, p) * RING_MS))
				break
	return t_end


static func _shock(c: Dictionary) -> int:
	var t: int = c["t"]
	var o: Vector2i = c["ppos"]
	var dist := int(c["eff"].get("dist", 1))
	L.clip(c, {"kind": "shock", "t0": t, "dur": 420, "at": o, "layer": "ground"})
	var t_end := t + 240
	for d in L.DIRS:
		var e = L.enemy_at(c["pre"], o + d)
		if e != null and c["pre_en"].has(e["id"]):
			t_end = maxi(t_end, FxLines.shove(c, e, d, dist, t + 70))
	return t_end


static func _swirl(c: Dictionary) -> int:
	var t: int = c["t"]
	var o: Vector2i = c["ppos"]
	var r := int(c["eff"].get("radius", 2))
	L.clip(c, {"kind": "swirl", "t0": t, "dur": r * RING_MS + 480, "at": o, "r": r, "ring_ms": RING_MS})
	_claim_rings(c, o, r, t, ["smoke_cleared"])
	return t + r * RING_MS + 160


static func _convert(c: Dictionary) -> int:
	var t: int = c["t"]
	var eff: Dictionary = c["eff"]
	var center: Vector2i = c["target"] if c.get("target") is Vector2i else c["ppos"]
	var r := int(eff.get("radius", 1))
	var kind := String(eff.get("kind", "growth"))
	var t_land := t
	if center != c["ppos"]:
		L.clip(c, {"kind": "seed_lob", "t0": t, "dur": LOB_MS, "from": c["ppos"], "to": center,
			"col": L.TERRAIN_COL.get(kind, Color("6cc95c")), "at": center})
		t_land = t + LOB_MS
	L.clip(c, {"kind": "conversion", "t0": t_land, "dur": r * RING_MS + 480, "at": center, "r": r,
		"ring_ms": RING_MS, "col": L.TERRAIN_COL.get(kind, Color("6cc95c")), "into": kind, "layer": "ground"})
	_claim_rings(c, center, r, t_land, ["convert"])
	return t_land + r * RING_MS + 180


static func _grow(c: Dictionary) -> int:
	var t: int = c["t"]
	var center: Vector2i = c["target"] if c.get("target") is Vector2i else c["ppos"]
	var r := int(c["eff"].get("radius", 1))
	var t_land := t
	if center != c["ppos"]:
		L.clip(c, {"kind": "seed_lob", "t0": t, "dur": LOB_MS, "from": c["ppos"], "to": center,
			"col": Color("6cc95c"), "at": center, "seed": true})
		t_land = t + LOB_MS
	# every tile that turned into growth around the centre sprouts in ring order
	var sprouts: Array = []
	var sw: Dictionary = c["reel"]["tswap"]
	for p in L.diamond(center, r):
		if sw.has(p) and String(sw[p]["post"]) == "growth" and not sw[p].has("t"):
			var tt := t_land + L.man(p, center) * RING_MS
			sprouts.append(p)
			L.reveal(c, p, tt + 60)
			L.clip(c, {"kind": "sprout", "t0": tt, "dur": 420, "at": p, "layer": "air"})
	L.clip(c, {"kind": "ring", "t0": t_land, "dur": r * RING_MS + 300, "at": center, "r0": 0.2,
		"r1": float(r) + 0.5, "col": Color("b4e89a"), "w": 0.08, "layer": "ground"})
	for i in L.unclaimed(c, ["growth", "hook"]):
		L.claim(c, i, t_land)
	# a tangle's roots take whoever stands on the fresh growth
	for i in L.unclaimed(c, ["status", "resisted", "immune"]):
		var e = c["pre_en"].get(c["events"][i].get("id"))
		if e != null and sprouts.has(e["pos"]):
			L.claim(c, i, t_land + L.man(e["pos"], center) * RING_MS + 140)
	return t_land + r * RING_MS + 200


# --- paint -----------------------------------------------------------------------

static func paint(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	match String(cl["kind"]):
		"nova":
			_paint_nova(cv, cl, k, V)
		"cloud":
			_paint_cloud(cv, cl, k, V)
		"tide":
			_paint_tide(cv, cl, k, V)
		"shock":
			_paint_shock(cv, cl, k, V)
		"swirl":
			_paint_swirl(cv, cl, k, V)
		"conversion":
			_paint_conversion(cv, cl, k, V)
		"seed_lob":
			_paint_lob(cv, cl, k, V)
		"sprout":
			_paint_sprout(cv, cl, k, V)


## The ring radius (tiles, float) the wave front has reached at k.
static func _front(cl: Dictionary, k: float) -> float:
	var ms := k * float(cl["dur"])
	return ms / float(cl.get("ring_ms", RING_MS))


static func _paint_nova(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var r := float(cl["r"])
	var f := minf(_front(cl, k), r)
	var fade := D.tail(k, 0.6)
	var c := D.px(V, cl["at"])
	cv.draw_colored_polygon(D.diamond(V, cl["at"], f), D.ca(pal["a"], 0.28 * fade))
	var edge := D.diamond(V, cl["at"], f)
	edge.append(edge[0])
	cv.draw_polyline(edge, D.ca(pal["b"], 0.9 * fade), maxf(1.0, t * 0.08), true)
	D.glow(cv, c, t * (0.5 + 0.2 * f) * fade, D.ca(pal["b"], 0.6))
	if bool(cl.get("fire", false)):
		for i in 12:
			var ang := TAU * float(i) / 12.0 + k * 0.8
			var r0 := t * 0.35
			var r1 := t * (0.5 + f * 0.95)
			D.line(cv, c + Vector2(cos(ang), sin(ang)) * r0, c + Vector2(cos(ang), sin(ang)) * r1,
				D.ca(pal["a"], 0.55 * fade), t * 0.05)


static func _paint_cloud(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var col := L.status_col(String(cl.get("status", "")))
	var r := float(cl["r"])
	var f := minf(_front(cl, k), r)
	var fade := D.tail(k, 0.55)
	var c := D.px(V, cl["at"])
	for i in 18:
		var ang := TAU * D.h01(i * 7 + 1)
		var dist := D.h01(i * 13 + 5) * (f + 0.4) * t
		var q := c + Vector2(cos(ang), sin(ang)) * dist + Vector2(0, -t * 0.2 * k)
		cv.draw_circle(q, t * (0.14 + 0.12 * D.h01(i)), D.ca(col, 0.32 * fade))
	for i in 10:
		var ang := TAU * D.h01(i * 29 + 9) + k * 1.5
		var q := c + Vector2(cos(ang), sin(ang)) * (f + 0.3) * t * D.h01(i * 3 + 2)
		D.twinkle(cv, q, t * 0.07, D.ca(col.lightened(0.4), fade))


static func _paint_tide(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var r := float(cl["r"])
	var f := minf(_front(cl, k), r + 0.4)
	var fade := D.tail(k, 0.6)
	var c := D.px(V, cl["at"])
	for d in L.DIRS:
		var dv := Vector2(d)
		var head := c + dv * f * t
		D.wavy(cv, c, head, t * 0.1, 2.0, -k * 12.0, D.ca(pal["a"], 0.9 * fade), t * 0.3, 14)
		D.wavy(cv, c, head, t * 0.06, 2.0, -k * 12.0 + 1.0, D.ca(pal["b"], fade), t * 0.1, 14)
		D.ring(cv, head, t * 0.18, D.ca(pal["b"], 0.8 * fade), t * 0.04)
	cv.draw_set_transform(c, 0.0, Vector2(1.0, 0.55))
	D.ring(cv, Vector2.ZERO, t * (0.3 + f * 0.6), D.ca(pal["a"], 0.6 * fade), t * 0.08)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _paint_shock(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var c := D.px(V, cl["at"])
	var r := t * (0.3 + 1.1 * D.ease_out(k))
	D.ring(cv, c, r, D.ca(pal["b"], 1.0 - k), t * 0.14 * (1.0 - k))
	D.ring(cv, c, r * 0.7, D.ca(pal["a"], 0.7 * (1.0 - k)), t * 0.08)
	for d in L.DIRS:
		var dv := Vector2(d)
		D.spike(cv, c + dv * t * 0.3, c + dv * (t * 0.35 + r * 0.8), t * 0.18 * (1.0 - k), D.ca(pal["a"], 1.0 - k))


static func _paint_swirl(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var r := float(cl["r"])
	var f := minf(_front(cl, k), r + 0.5)
	var fade := D.tail(k, 0.6)
	var c := D.px(V, cl["at"])
	for j in 3:
		var pts := PackedVector2Array()
		for i in 24:
			var u := float(i) / 23.0
			var ang := u * TAU * 1.2 + k * 7.0 + TAU * float(j) / 3.0
			pts.append(c + Vector2(cos(ang), sin(ang)) * u * f * t)
		cv.draw_polyline(pts, D.ca(pal["b"] if j == 0 else pal["a"], 0.8 * fade), maxf(1.0, t * 0.05), true)


static func _paint_conversion(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var col: Color = cl.get("col", Color("6cc95c"))
	var r := float(cl["r"])
	var f := minf(_front(cl, k), r)
	var fade := D.tail(k, 0.65)
	cv.draw_colored_polygon(D.diamond(V, cl["at"], f), D.ca(col, 0.22 * fade))
	var edge := D.diamond(V, cl["at"], f)
	edge.append(edge[0])
	cv.draw_polyline(edge, D.ca(col.lightened(0.4), 0.9 * fade), maxf(1.0, t * 0.06), true)
	var c := D.px(V, cl["at"])
	for i in 10:
		var ang := TAU * float(i) / 10.0
		D.leaf(cv, c + Vector2(cos(ang), sin(ang)) * (f + 0.2) * t * 0.9, ang, t * 0.18, D.ca(col.lightened(0.2), fade))


static func _paint_lob(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var a := D.px(V, cl["from"])
	var b := D.px(V, cl["to"])
	var col: Color = cl.get("col", Color("6cc95c"))
	var h := t * (0.6 + 0.15 * a.distance_to(b) / t)
	var u := D.ease_io(k)
	var q := D.arc_point(a, b, u, h)
	# a faint arc trail, a shadow on the ground, the seed spinning
	for j in 5:
		var uj := u - float(j + 1) * 0.06
		if uj > 0.0:
			cv.draw_circle(D.arc_point(a, b, uj, h), t * 0.05 * (1.0 - float(j) * 0.18), D.ca(col, 0.5 - float(j) * 0.09))
	cv.draw_circle(a.lerp(b, u) + Vector2(0, t * 0.3), t * 0.1, Color(0, 0, 0, 0.25))
	cv.draw_circle(q, t * 0.14, col.darkened(0.3))
	cv.draw_circle(q, t * 0.1, col)
	if bool(cl.get("seed", false)):
		D.leaf(cv, q + Vector2(0, -t * 0.12), -PI * 0.5 + k * 9.0, t * 0.16, Color("8fdc6a"))


static func _paint_sprout(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var base := D.px(V, cl["at"]) + Vector2(0, t * 0.3)
	var g := D.ease_out(D.win(k, 0.0, 0.55))
	var over := 1.0 + 0.25 * D.pulse(D.win(k, 0.35, 0.8))
	var a := D.tail(k, 0.75)
	var top := base + Vector2(0, -t * 0.45 * g * over)
	D.line(cv, base, top, D.ca(Color("3f8f3a"), a), t * 0.06)
	D.leaf(cv, top + Vector2(-t * 0.1, 0), PI * 1.15, t * 0.26 * g, D.ca(Color("6cc95c"), a))
	D.leaf(cv, top + Vector2(t * 0.1, -t * 0.03), -PI * 0.15, t * 0.26 * g, D.ca(Color("8fdc6a"), a))
	# a puff of pollen as it pops
	if k > 0.35:
		var u := D.win(k, 0.35, 1.0)
		for i in 4:
			var ang := -PI * (0.2 + 0.2 * float(i))
			cv.draw_circle(top + Vector2(cos(ang), sin(ang)) * t * 0.35 * u, t * 0.03, D.ca(Color("f0d968"), 1.0 - u))
