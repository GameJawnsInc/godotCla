extends RefCounted
## Verb family: PLACEMENTS and SELF - effects aimed at one tile or at the
## tender.
##   create_terrain  a pod is lobbed and bursts into smoke (or flame)
##   grow_wall       roots heave up out of the floor, tile by tile
##   apply_status    a glob of sap / spores arcs onto the target
##   damage          a thorn spike erupts under the target
##   teleport        the tender dissolves into spores and reforms there
##   plant_origin    the tile the tender left sprouts behind it
##   shield          bark plates close around the tender
##   thorns          thorns burst outward and settle into a crown
##   anchor          roots drive down from the tender's feet
##   undim           a shaft of sunlight parts the haze
##   status_target   a rider's status lands on what the parent touched

const L := preload("res://shell/anim_lib.gd")
const D := preload("res://shell/anim_draw.gd")

const OPS := ["create_terrain", "grow_wall", "apply_status", "damage", "teleport", "plant_origin",
	"shield", "thorns", "anchor", "undim", "status_target"]
const KINDS := ["pod", "billow", "roots_rise", "glob", "spike_up", "warp", "bark", "thorn_burst",
	"anchor_drive", "sunbeam"]

const LOB_MS := 220


static func build(op: String, c: Dictionary) -> int:
	match op:
		"create_terrain":
			return _terrain(c)
		"grow_wall":
			return _wall(c)
		"apply_status":
			return _glob(c)
		"damage":
			return _spike(c)
		"teleport":
			return _warp(c)
		"plant_origin":
			return _plant_origin(c)
		"shield":
			return _self_verb(c, "bark", ["shield"], 460)
		"thorns":
			return _self_verb(c, "thorn_burst", ["thorns"], 440)
		"anchor":
			return _self_verb(c, "anchor_drive", ["anchor"], 460)
		"undim":
			return _self_verb(c, "sunbeam", ["undim"], 560)
		"status_target":
			return _rider_status(c)
	return int(c["t"])


static func _target(c: Dictionary) -> Vector2i:
	var tg = c.get("target")
	return tg if tg is Vector2i else c["ppos"]


static func _terrain(c: Dictionary) -> int:
	var t: int = c["t"]
	var tile := _target(c)
	var kind := String(c["eff"].get("kind", "smoke"))
	var t_land := t
	if tile != c["ppos"]:
		L.clip(c, {"kind": "pod", "t0": t, "dur": LOB_MS, "from": c["ppos"], "to": tile,
			"col": L.TERRAIN_COL.get(kind, Color("9aa0a4")), "at": tile})
		t_land = t + LOB_MS
	L.clip(c, {"kind": "billow", "t0": t_land, "dur": 620, "at": tile, "into": kind,
		"col": L.TERRAIN_COL.get(kind, Color("9aa0a4"))})
	for i in L.unclaimed(c, ["terrain", "hook"]):
		if c["events"][i].get("tile") == tile:
			L.claim(c, i, t_land)
	L.reveal(c, tile, t_land + 60)
	return t_land + 260


static func _wall(c: Dictionary) -> int:
	var t: int = c["t"]
	var center := _target(c)
	var sw: Dictionary = c["reel"]["tswap"]
	var n := 0
	for p in L.diamond(center, 1):
		if sw.has(p) and String(sw[p]["post"]) == "roots" and not sw[p].has("t"):
			var tt := t + 40 + L.man(p, center) * 90
			L.clip(c, {"kind": "roots_rise", "t0": tt, "dur": 440, "at": p, "layer": "air"})
			L.reveal(c, p, tt + 160)
			n += 1
	for i in L.unclaimed(c, ["roots"]):
		L.claim(c, i, t + 40)
	if n > 0:
		c["reel"]["shakes"].append({"t0": t + 60, "mag": 3.0})
	return t + 40 + 90 + 260


static func _glob(c: Dictionary) -> int:
	var t: int = c["t"]
	var tile := _target(c)
	var status := String(c["eff"].get("status", ""))
	var dist := maxi(1, L.man(c["ppos"], tile))
	var fly := 120 + dist * 40
	L.clip(c, {"kind": "glob", "t0": t, "dur": fly + 320, "from": c["ppos"], "to": tile, "fly": fly,
		"col": L.status_col(status), "at": tile})
	for i in L.unclaimed(c, ["status", "resisted", "immune", "hook"]):
		var ev: Dictionary = c["events"][i]
		var e = c["pre_en"].get(ev.get("id"))
		if (e != null and e["pos"] == tile) or ev.get("tile") == tile:
			L.claim(c, i, t + fly + 20)
	return t + fly + 160


static func _spike(c: Dictionary) -> int:
	var t: int = c["t"]
	var tile := _target(c)
	L.clip(c, {"kind": "spike_up", "t0": t, "dur": 560, "at": tile, "rise_ms": 170})
	var e = L.enemy_at(c["pre"], tile)
	if e != null:
		for i in L.cast_hits(c, e["id"]):
			L.claim(c, i, t + 180, Vector2(0, -1))
	return t + 300


static func _warp(c: Dictionary) -> int:
	var t: int = c["t"]
	var o: Vector2i = c["ppos"]
	var to := _target(c)
	for i in L.unclaimed(c, ["teleport"]):
		to = c["events"][i]["to"]
		L.claim(c, i, t + 200)
		break
	L.seg(c, "player", {"kind": "warp_out", "t0": t, "dur": 190})
	L.move(c, "player", [o, to], t + 190, 10, 0.0)
	L.seg(c, "player", {"kind": "warp_in", "t0": t + 210, "dur": 220})
	L.clip(c, {"kind": "warp", "t0": t, "dur": 520, "from": o, "to": to, "at": o})
	c["ppos"] = to
	for i in L.unclaimed(c, ["damage", "item_pickup", "heal"]):
		var ev: Dictionary = c["events"][i]
		if String(ev["t"]) != "damage" or String(ev.get("who", "")) == "player":
			L.claim(c, i, t + 240)
	return t + 430


static func _plant_origin(c: Dictionary) -> int:
	var t: int = c["t"]
	var o: Vector2i = c.get("origin", c["p0"])
	var sw: Dictionary = c["reel"]["tswap"]
	if sw.has(o):
		L.clip(c, {"kind": "billow", "t0": t - 120, "dur": 520, "at": o,
			"into": String(sw[o]["post"]), "col": L.TERRAIN_COL.get(String(sw[o]["post"]), Color("6cc95c"))})
		L.reveal(c, o, t - 60)
	for i in L.unclaimed(c, ["terrain", "hook"]):
		if c["events"][i].get("tile") == o:
			L.claim(c, i, t - 60)
	return t


static func _self_verb(c: Dictionary, kind: String, evs: Array, dur: int) -> int:
	var t: int = c["t"]
	L.clip(c, {"kind": kind, "t0": t, "dur": dur, "at": c["ppos"]})
	for i in L.unclaimed(c, evs):
		L.claim(c, i, t + dur / 3)
	if kind == "anchor_drive":
		L.seg(c, "player", {"kind": "squash", "t0": t + 60, "dur": 200})
		c["reel"]["shakes"].append({"t0": t + 80, "mag": 2.5})
	return t + dur / 2 + 60


static func _rider_status(c: Dictionary) -> int:
	var t: int = c["t"]
	for i in L.unclaimed(c, ["status", "resisted", "immune"]):
		L.claim(c, i, t + 40)
	return t + 120


# --- paint -----------------------------------------------------------------------

static func paint(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	match String(cl["kind"]):
		"pod":
			_paint_pod(cv, cl, k, V)
		"billow":
			_paint_billow(cv, cl, k, V)
		"roots_rise":
			_paint_roots(cv, cl, k, V)
		"glob":
			_paint_glob(cv, cl, k, V)
		"spike_up":
			_paint_spike(cv, cl, k, V)
		"warp":
			_paint_warp(cv, cl, k, V)
		"bark":
			_paint_bark(cv, cl, k, V)
		"thorn_burst":
			_paint_thorns(cv, cl, k, V)
		"anchor_drive":
			_paint_anchor(cv, cl, k, V)
		"sunbeam":
			_paint_sunbeam(cv, cl, k, V)


static func _paint_pod(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var a := D.px(V, cl["from"])
	var b := D.px(V, cl["to"])
	var col: Color = cl.get("col", Color("9aa0a4"))
	var q := D.arc_point(a, b, D.ease_io(k), t * 0.8)
	cv.draw_circle(a.lerp(b, k) + Vector2(0, t * 0.3), t * 0.09, Color(0, 0, 0, 0.25))
	cv.draw_circle(q, t * 0.15, col.darkened(0.35))
	cv.draw_circle(q, t * 0.11, col.lightened(0.2))
	D.line(cv, q, q + Vector2(0, -t * 0.12), Color("4a9a3d"), t * 0.04)


static func _paint_billow(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var c := D.px(V, cl["at"])
	var col: Color = cl.get("col", Color("9aa0a4"))
	var fade := D.tail(k, 0.5)
	var g := D.ease_out(k)
	for i in 7:
		var ang := TAU * float(i) / 7.0 + D.h01(i) * 0.6
		var q := c + Vector2(cos(ang), sin(ang) * 0.7) * t * (0.1 + 0.42 * g) + Vector2(0, -t * 0.2 * g)
		cv.draw_circle(q, t * (0.12 + 0.16 * g), D.ca(col.lightened(0.15), 0.55 * fade))
	if String(cl.get("into", "")) == "fire":
		D.glow(cv, c, t * 0.5 * (1.0 - k), D.ca(Color("fdf0a8"), 0.8))


static func _paint_roots(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var r := D.tile_rect(V, cl["at"])
	var base := Vector2(r.get_center().x, r.end.y - t * 0.08)
	var g := D.ease_out(D.win(k, 0.0, 0.5))
	var fade := D.tail(k, 0.6)
	var bark := Color("8a6a3e")
	# the floor cracks, then the roots heave up and twist
	for i in 3:
		var x := (float(i) - 1.0) * t * 0.28
		D.line(cv, base + Vector2(x - t * 0.1, 0), base + Vector2(x + t * 0.1, -t * 0.05), D.ca(Color(0.08, 0.06, 0.04), 0.7 * fade), t * 0.04)
	for i in 4:
		var x := (float(i) - 1.5) * t * 0.22
		var tip := base + Vector2(x * 0.6, -t * (0.55 + 0.3 * D.h01(i + 3)) * g)
		D.wavy(cv, base + Vector2(x, 0), tip, t * 0.06, 1.0, float(i) * 1.7, D.ca(bark.darkened(0.3), fade), t * 0.13, 8)
		D.wavy(cv, base + Vector2(x, 0), tip, t * 0.06, 1.0, float(i) * 1.7, D.ca(bark.lightened(0.2), fade), t * 0.06, 8)
	if k < 0.3:
		for i in 5:
			var ang := -PI * (0.15 + 0.7 * float(i) / 4.0)
			cv.draw_circle(base + Vector2(cos(ang), sin(ang)) * t * 0.45 * (k / 0.3), t * 0.035, D.ca(Color("6b5a44"), 1.0 - k / 0.3))


static func _paint_glob(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var ms := k * float(cl["dur"])
	var fly := maxf(1.0, float(cl["fly"]))
	var a := D.px(V, cl["from"])
	var b := D.px(V, cl["to"])
	var col: Color = cl.get("col", Color("c9a63c"))
	if ms < fly:
		var u := D.ease_in(ms / fly) * 0.3 + (ms / fly) * 0.7
		var q := D.arc_point(a, b, u, t * 0.45)
		for j in 4:
			var uj := u - float(j + 1) * 0.05
			if uj > 0.0:
				cv.draw_circle(D.arc_point(a, b, uj, t * 0.45), t * 0.07 * (1.0 - float(j) * 0.2), D.ca(col, 0.45))
		cv.draw_circle(q, t * 0.13, col.darkened(0.25))
		cv.draw_circle(q + Vector2(-t * 0.03, -t * 0.04), t * 0.05, col.lightened(0.5))
	else:
		# splat: drips fly out, a sticky puddle spreads under the target
		var u := clampf((ms - fly) / maxf(1.0, float(cl["dur"]) - fly), 0.0, 1.0)
		cv.draw_set_transform(b + Vector2(0, t * 0.3), 0.0, Vector2(1.0, 0.45))
		cv.draw_circle(Vector2.ZERO, t * (0.2 + 0.2 * D.ease_out(u)), D.ca(col, 0.6 * (1.0 - u)))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for i in 6:
			var ang := TAU * float(i) / 6.0 + 0.3
			cv.draw_circle(b + Vector2(cos(ang), sin(ang)) * t * 0.4 * D.ease_out(u), t * 0.05 * (1.0 - u), D.ca(col, 1.0 - u))


static func _paint_spike(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var ms := k * float(cl["dur"])
	var rise := maxf(1.0, float(cl.get("rise_ms", 170)))
	var r := D.tile_rect(V, cl["at"])
	var base := Vector2(r.get_center().x, r.end.y - t * 0.06)
	var fade := D.tail(k, 0.6)
	# a crack runs across the floor, then the spike punches up through it
	var crack := clampf(ms / rise, 0.0, 1.0)
	D.line(cv, base - Vector2(t * 0.4 * crack, 0), base + Vector2(t * 0.4 * crack, -t * 0.04), D.ca(Color(0.1, 0.08, 0.05), 0.8 * fade), t * 0.05)
	if ms > rise * 0.6:
		var u := D.ease_out(clampf((ms - rise * 0.6) / (rise * 0.6), 0.0, 1.0))
		var h := t * 0.95 * u * (1.0 - 0.3 * D.win(k, 0.6, 1.0))
		D.spike(cv, base + Vector2(-t * 0.02, 0), base + Vector2(0, -h), t * 0.34, D.ca(Color("2f6b2c"), fade))
		D.spike(cv, base + Vector2(t * 0.02, 0), base + Vector2(t * 0.03, -h * 0.94), t * 0.2, D.ca(Color("6cc95c"), fade))
		D.spike(cv, base + Vector2(-t * 0.22, 0), base + Vector2(-t * 0.28, -h * 0.5), t * 0.14, D.ca(Color("3f8f3a"), fade))
		D.spike(cv, base + Vector2(t * 0.22, 0), base + Vector2(t * 0.3, -h * 0.45), t * 0.14, D.ca(Color("3f8f3a"), fade))
		for i in 5:
			var ang := -PI * (0.1 + 0.8 * float(i) / 4.0)
			cv.draw_circle(base + Vector2(cos(ang), sin(ang)) * t * 0.5 * u, t * 0.035, D.ca(Color("6b5a44"), 1.0 - u))


static func _paint_warp(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var a := D.px(V, cl["from"])
	var b := D.px(V, cl["to"])
	var out := D.win(k, 0.0, 0.4)
	var inn := D.win(k, 0.4, 1.0)
	# spores scatter up from the old tile, stream along the mycelium, and
	# gather back into the tender at the new one
	for i in 10:
		var ang := TAU * D.h01(i * 5 + 1)
		var r := t * (0.1 + 0.4 * D.h01(i * 3 + 7))
		if out > 0.0 and out < 1.0:
			cv.draw_circle(a + Vector2(cos(ang), sin(ang)) * r * (0.5 + out) + Vector2(0, -t * 0.4 * out),
				t * 0.05, D.ca(pal["a"], 1.0 - out))
		if inn > 0.0 and inn < 1.0:
			cv.draw_circle(b + Vector2(cos(ang), sin(ang)) * r * (1.4 - inn * 1.3), t * 0.05, D.ca(pal["b"], inn * (1.0 - inn) * 3.0))
	var mid := D.win(k, 0.15, 0.65)
	if mid > 0.0 and mid < 1.0:
		var q := D.arc_point(a, b, D.ease_io(mid), t * 0.4)
		D.glow(cv, q, t * 0.22, D.ca(pal["a"], 0.7))
		D.line(cv, a.lerp(q, 0.6), q, D.ca(pal["b"], 0.6), t * 0.05)
	cv.draw_set_transform(b + Vector2(0, t * 0.3), 0.0, Vector2(1.0, 0.45))
	D.ring(cv, Vector2.ZERO, t * 0.45 * D.pulse(inn), D.ca(pal["a"], 0.8 * D.pulse(inn)), t * 0.07)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _paint_bark(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var c := D.px(V, cl["at"])
	var close := D.ease_out(D.win(k, 0.0, 0.5))
	var fade := D.tail(k, 0.7)
	var bark := Color("8a6a3e")
	var blue := Color("7fb6d9")
	for i in 6:
		var ang := TAU * float(i) / 6.0 + (1.0 - close) * 1.2
		var r := t * (1.1 - 0.62 * close)
		D.leaf(cv, c + Vector2(cos(ang), sin(ang)) * r, ang + PI * 0.5, t * 0.34, D.ca(bark.lightened(0.15), fade))
	if k > 0.45:
		var u := D.win(k, 0.45, 1.0)
		D.ring(cv, c, t * (0.5 + 0.1 * u), D.ca(blue, 0.9 * (1.0 - u)), t * 0.07)
		D.glow(cv, c, t * 0.55, D.ca(blue, 0.35 * (1.0 - u)))


static func _paint_thorns(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var c := D.px(V, cl["at"])
	var burst := D.ease_out(D.win(k, 0.0, 0.35))
	var settle := D.win(k, 0.35, 1.0)
	var fade := D.tail(k, 0.75)
	for i in 12:
		var ang := TAU * float(i) / 12.0
		var dv := Vector2(cos(ang), sin(ang))
		var len := t * (0.3 + 0.55 * burst - 0.35 * settle)
		D.spike(cv, c + dv * t * 0.32, c + dv * (t * 0.32 + len), t * 0.1, D.ca(Color("3f8f3a") if i % 2 == 0 else Color("6cc95c"), fade))


static func _paint_anchor(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var c := D.px(V, cl["at"])
	var foot := c + Vector2(0, t * 0.38)
	var g := D.ease_out(D.win(k, 0.1, 0.6))
	var fade := D.tail(k, 0.7)
	var bark := Color("8a6a3e")
	for i in 6:
		var ang := PI * (0.05 + 0.9 * float(i) / 5.0)
		var tip := foot + Vector2(cos(ang) * t * 0.75, sin(ang) * t * 0.3) * g
		D.wavy(cv, foot, tip, t * 0.04, 1.0, float(i), D.ca(bark, fade), t * 0.08, 8)
	cv.draw_set_transform(foot, 0.0, Vector2(1.0, 0.35))
	D.ring(cv, Vector2.ZERO, t * (0.3 + 0.5 * D.ease_out(k)), D.ca(bark.lightened(0.3), 0.8 * (1.0 - k)), t * 0.08)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _paint_sunbeam(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var c := D.px(V, cl["at"])
	var pal: Dictionary = cl["pal"]
	var on := D.pulse(k)
	var top := c + Vector2(-t * 0.8, -t * 4.0)
	var w := t * 0.5 * on
	var pts := PackedVector2Array([top + Vector2(-w * 0.6, 0), top + Vector2(w * 0.6, 0),
		c + Vector2(w, t * 0.3), c + Vector2(-w, t * 0.3)])
	if w > 1.0:
		cv.draw_colored_polygon(pts, D.ca(pal["b"], 0.3 * on))
	D.glow(cv, c, t * 0.7 * on, D.ca(pal["a"], 0.5))
	D.ring(cv, c, t * (0.4 + 1.4 * D.ease_out(k)), D.ca(pal["b"], 0.7 * (1.0 - k)), t * 0.06)
	for i in 6:
		var u := fposmod(D.h01(i * 9 + 4) + k * 0.8, 1.0)
		cv.draw_circle(top.lerp(c, u) + Vector2((D.h01(i) - 0.5) * w, 0), t * 0.04, D.ca(pal["b"], on))
