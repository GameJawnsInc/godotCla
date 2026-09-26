extends RefCounted
## The animation painter: draws a reel's clips at reel time t, one LAYER at a
## time, plus the persistent creature overlays (enemy statuses, the tender's
## buffs) that loop between steps. The shell calls it from _draw_map:
##
##   Paint.paint(self, reel, rt, "ground", V)   # under creatures
##   Paint.paint(self, reel, rt, "air", V)      # over creatures
##
## Generic kinds (numbers, flashes, bursts, puffs, status pops...) are drawn
## here; every other kind belongs to the verb family that emits it
## (shell/fx_*.gd, each listing its KINDS). tests/test_anim.gd paints every
## kind a reel can hold through a recording canvas, so a kind with no painter
## fails the suite instead of silently drawing nothing.

const L := preload("res://shell/anim_lib.gd")
const D := preload("res://shell/anim_draw.gd")
const Art := preload("res://shell/svg_art.gd")
const FxLines := preload("res://shell/fx_lines.gd")
const FxAreas := preload("res://shell/fx_areas.gd")
const FxSelf := preload("res://shell/fx_self.gd")
const FxEnemy := preload("res://shell/fx_enemy.gd")

const FAMILIES := [FxLines, FxAreas, FxSelf, FxEnemy]
const CORE_KINDS := ["float", "burst", "puff", "ring", "spark", "status_pop", "slash", "scrub",
	"motes", "item", "cast_ring", "surge", "flare", "splash", "tile_pop", "portal"]


static func owner_of(kind: String):
	if CORE_KINDS.has(kind):
		return null
	for fam in FAMILIES:
		if fam.KINDS.has(kind):
			return fam
	return null


static func known(kind: String) -> bool:
	return CORE_KINDS.has(kind) or owner_of(kind) != null


static func paint(cv, reel: Dictionary, rt: float, layer: String, V: Dictionary) -> void:
	if reel.is_empty():
		return
	for cl in reel.get("clips", []):
		if String(cl.get("layer", "air")) != layer:
			continue
		var age := rt - float(cl["t0"])
		var dur := maxf(1.0, float(cl["dur"]))
		if age < 0.0 or age > dur:
			continue
		if V.has("vis") and cl.has("at") and not (V["vis"] as Callable).call(Vector2i(Vector2(cl["at"]).round())):
			continue
		paint_clip(cv, cl, age / dur, V)


static func paint_clip(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var kind := String(cl["kind"])
	var fam = owner_of(kind)
	if fam != null:
		fam.paint(cv, cl, k, V)
		return
	var t := D.ts(V)
	match kind:
		"float":
			var col: Color = cl.get("col", Color.WHITE)
			var p := D.px(V, cl["at"])
			var a := D.tail(k, 0.55)
			var pop := 1.0 + 0.35 * (1.0 - D.ease_out(D.win(k, 0.0, 0.18)))
			var sz := int(t * 0.42 * pop)
			D.text(cv, V, Vector2(p.x, p.y - t * (0.62 + 0.75 * D.ease_out(k))), String(cl.get("text", "")),
				D.ca(col, a), maxi(8, sz))
		"burst":
			var c := D.px(V, cl["at"])
			var col: Color = cl.get("col", Color("e8c840"))
			var rad := t * (0.25 + k * 0.55)
			for i in 6:
				var ang := TAU * float(i) / 6.0 + k * 1.8
				cv.draw_circle(c + Vector2(cos(ang), sin(ang)) * rad, t * 0.06 * (1.0 - k * 0.5), D.ca(col, 1.0 - k))
			if k < 0.3:
				D.glow(cv, c, t * 0.45 * (1.0 - k / 0.3), D.ca(col, 0.5))
		"puff":
			var c := D.px(V, cl["at"])
			var col: Color = cl.get("col", Color(0.62, 0.64, 0.66))
			var pc := D.ca(col, 0.5 * (1.0 - k))
			cv.draw_circle(c + Vector2(0, -t * k * 0.4), t * (0.2 + k * 0.35), pc)
			cv.draw_circle(c + Vector2(-t * 0.22, -t * k * 0.55), t * (0.12 + k * 0.25), pc)
			cv.draw_circle(c + Vector2(t * 0.2, -t * k * 0.3), t * (0.1 + k * 0.22), pc)
		"ring":
			var c := D.px(V, cl["at"])
			var col: Color = cl.get("col", Color.WHITE)
			var r := lerpf(float(cl.get("r0", 0.2)), float(cl.get("r1", 1.0)), D.ease_out(k)) * t
			D.ring(cv, c, r, D.ca(col, 1.0 - k), float(cl.get("w", 0.08)) * t * (1.0 - 0.5 * k))
		"spark":
			var c := D.px(V, cl["at"])
			var col: Color = cl.get("col", Color.WHITE)
			var n := int(cl.get("n", 6))
			for i in n:
				var ang := TAU * (float(i) + D.h01(i + n * 7)) / float(n)
				var r0 := t * (0.1 + 0.45 * D.ease_out(k))
				var r1 := r0 + t * 0.18 * (1.0 - k)
				D.line(cv, c + Vector2(cos(ang), sin(ang)) * r0, c + Vector2(cos(ang), sin(ang)) * r1,
					D.ca(col, 1.0 - k), t * 0.05)
		"status_pop":
			status_pop(cv, V, D.px(V, cl["at"]), String(cl.get("status", "")), k)
		"slash":
			var c := D.px(V, cl["at"])
			var d: Vector2 = cl.get("dir", Vector2.RIGHT)
			var pal: Dictionary = cl.get("pal", L.PAL_DEFAULT)
			var base := d.angle()
			var sweep := D.ease_out(D.win(k, 0.0, 0.45))
			var a := D.tail(k, 0.35)
			for j in 3:
				var off := (float(j) - 1.0) * t * 0.14
				var s := Vector2(-d.y, d.x) * off
				var pts := PackedVector2Array()
				for i in 9:
					var u := float(i) / 8.0 * sweep
					var ang := base - 1.1 + u * 2.2
					pts.append(c + s + Vector2(cos(ang), sin(ang)) * t * 0.36 - d * t * 0.12)
				if pts.size() >= 2 and sweep > 0.05:
					cv.draw_polyline(pts, D.ca(pal["b"] if j == 1 else pal["a"], a), t * (0.08 if j == 1 else 0.05), true)
			if k < 0.4:
				D.glow(cv, c, t * 0.32 * (1.0 - k / 0.4), D.ca(Color.WHITE, 0.6))
		"scrub":
			var c := D.px(V, cl["at"])
			var gold := Color("e8c840")
			for i in 7:
				var ph := D.h01(i * 13 + 5) * TAU
				var ang := ph + k * 5.0
				var r := t * (0.12 + 0.28 * D.h01(i * 7 + 1))
				var q := c + Vector2(cos(ang), sin(ang) * 0.6) * r + Vector2(0, -t * 0.25 * k)
				D.twinkle(cv, q, t * 0.08 * D.pulse(D.win(k, float(i) * 0.06, float(i) * 0.06 + 0.6)), D.ca(gold, 0.95))
			# the filth lifts and dissolves
			for i in 3:
				var q := c + Vector2((float(i) - 1.0) * t * 0.2, t * 0.1 - t * 0.5 * D.ease_out(k))
				cv.draw_circle(q, t * 0.09 * (1.0 - k), Color(0.16, 0.12, 0.14, 0.5 * (1.0 - k)))
		"motes":
			var a := D.px(V, cl["from"])
			var b := D.px(V, cl["to"])
			var col: Color = cl.get("col", Color("8fdc6a"))
			var n := int(cl.get("n", 6))
			var rise := bool(cl.get("rise", false))
			for i in n:
				var u := D.win(k, float(i) / float(n) * 0.35, float(i) / float(n) * 0.35 + 0.65)
				if u <= 0.0 or u >= 1.0:
					continue
				var jit := Vector2(D.h01(i * 3 + 1) - 0.5, D.h01(i * 5 + 2) - 0.5) * t * 0.7
				var q: Vector2
				if rise:
					q = a + jit + Vector2(sin(u * 6.0 + float(i)) * t * 0.08, -t * (0.1 + 0.8 * u))
				else:
					q = (a + jit).lerp(b, D.ease_io(u)) + Vector2(0, -t * 0.3 * sin(u * PI))
				cv.draw_circle(q, t * 0.05 * (1.0 - 0.5 * u), D.ca(col, 0.9 * sin(u * PI)))
		"item":
			var c := D.px(V, cl["at"])
			var tx = Art.tex("it_" + String(cl.get("id", "")).trim_suffix("+"), int(t * 0.8))
			var u := D.ease_out(D.win(k, 0.0, 0.35))
			var q := c + Vector2(0, -t * (0.3 + 0.55 * u))
			var a := D.tail(k, 0.6)
			D.glow(cv, q, t * 0.45, D.ca(Color("fff4c2"), 0.35 * a))
			if tx != null:
				cv.draw_texture(tx, q - Vector2(t * 0.4, t * 0.4), Color(1, 1, 1, a))
		"cast_ring":
			var c := D.px(V, cl["at"]) + Vector2(0, t * 0.3)
			var pal: Dictionary = cl.get("pal", L.PAL_DEFAULT)
			# energy gathers in, then the ring releases outward
			var g := D.win(k, 0.0, 0.4)
			for i in 6:
				var ang := TAU * float(i) / 6.0 + k * 3.0
				var r := t * 0.55 * (1.0 - D.ease_in(g))
				if g < 1.0:
					cv.draw_circle(c + Vector2(cos(ang), sin(ang) * 0.45) * r, t * 0.045, D.ca(pal["b"], 0.9))
			var rel := D.win(k, 0.35, 1.0)
			if rel > 0.0:
				var r2 := t * (0.2 + 0.45 * D.ease_out(rel))
				cv.draw_set_transform(c, 0.0, Vector2(1.0, 0.45))
				D.ring(cv, Vector2.ZERO, r2, D.ca(pal["a"], 1.0 - rel), t * 0.07)
				cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"surge":
			var c := D.px(V, cl["at"])
			var green := Color("8fdc6a")
			D.glow(cv, c, t * 0.6 * D.pulse(k), D.ca(green, 0.5))
			for i in 8:
				var ang := TAU * float(i) / 8.0 + k * 4.0
				var r := t * (0.5 - 0.35 * k)
				D.leaf(cv, c + Vector2(cos(ang), sin(ang)) * r + Vector2(0, -t * 0.4 * k), ang + PI * 0.5,
					t * 0.18, D.ca(green, 1.0 - k))
		"flare":
			var c := D.px(V, cl["at"])
			var col: Color = cl.get("col", Color("ef933a"))
			var up := D.ease_out(D.win(k, 0.0, 0.3))
			var a := D.tail(k, 0.3)
			D.glow(cv, c, t * (0.35 + 0.35 * up), D.ca(col, 0.7 * a))
			for i in 3:
				var x := (float(i) - 1.0) * t * 0.18
				D.spike(cv, c + Vector2(x, t * 0.3), c + Vector2(x * 0.6, t * (0.3 - 0.9 * up * (1.0 - 0.25 * absf(float(i) - 1.0)))),
					t * 0.22, D.ca(Color("fdf0a8") if i == 1 else col, a))
		"splash":
			var c := D.px(V, cl["at"])
			var water := Color("7ec8e0")
			for i in 7:
				var ang := -PI * (0.1 + 0.8 * float(i) / 6.0)
				var r := t * 0.45 * D.ease_out(k)
				var q := c + Vector2(cos(ang), sin(ang)) * r + Vector2(0, t * 0.5 * k * k)
				cv.draw_circle(q, t * 0.055 * (1.0 - 0.6 * k), D.ca(water, 1.0 - k))
			D.ring(cv, c + Vector2(0, t * 0.2), t * 0.4 * D.ease_out(k), D.ca(Color("d6f1fb"), 0.8 * (1.0 - k)), t * 0.04)
		"tile_pop":
			var r := D.tile_rect(V, cl["at"])
			var col: Color = cl.get("col", Color("6cc95c"))
			var g := 1.0 + 0.25 * D.pulse(k)
			var rr := Rect2(r.get_center() - r.size * g * 0.5, r.size * g)
			cv.draw_rect(rr, D.ca(col, 0.45 * (1.0 - k)))
			cv.draw_rect(rr, D.ca(Color.WHITE, 0.5 * (1.0 - k)), false, maxf(1.0, t * 0.04))
		"portal":
			var c := D.px(V, cl["at"])
			var col: Color = cl.get("col", Color("e04b3a"))
			var o := D.pulse(k)
			cv.draw_set_transform(c + Vector2(0, t * 0.3), 0.0, Vector2(1.0, 0.45))
			D.ring(cv, Vector2.ZERO, t * 0.45 * o, D.ca(col, 0.9 * o), t * 0.08)
			cv.draw_circle(Vector2.ZERO, t * 0.3 * o, Color(0.05, 0.03, 0.03, 0.55 * o))
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			for i in 5:
				var ang := TAU * float(i) / 5.0 - k * 5.0
				cv.draw_circle(c + Vector2(cos(ang) * t * 0.4, sin(ang) * t * 0.18 + t * 0.3 - t * 0.5 * k),
					t * 0.04, D.ca(col, 1.0 - k))


## A status landing on a creature: stun stars burst and settle into orbit,
## roots coil up from the feet, spores puff out in a violet cloud.
static func status_pop(cv, V: Dictionary, c: Vector2, status: String, k: float) -> void:
	var t := D.ts(V)
	var col := L.status_col(status)
	var a := D.tail(k, 0.6)
	D.ring(cv, c, t * (0.25 + 0.4 * D.ease_out(k)), D.ca(col, 0.8 * (1.0 - k)), t * 0.05)
	match status:
		"stun":
			for i in 3:
				var ang := TAU * float(i) / 3.0 + k * 6.0
				var q := c + Vector2(cos(ang) * t * 0.32, -t * 0.42 + sin(ang) * t * 0.1)
				D.twinkle(cv, q, t * 0.11 * (1.0 + 0.6 * (1.0 - D.ease_out(D.win(k, 0.0, 0.3)))), D.ca(col, a))
		"root":
			var grow := D.ease_out(D.win(k, 0.0, 0.45))
			for i in 4:
				var x := (float(i) - 1.5) * t * 0.2
				var base := c + Vector2(x, t * 0.42)
				D.wavy(cv, base, base + Vector2(x * 0.3, -t * 0.55 * grow), t * 0.05, 1.2, float(i),
					D.ca(Color("8a6a3e"), a), t * 0.07, 8)
		"spore":
			for i in 8:
				var ang := TAU * D.h01(i * 11 + 3)
				var r := t * (0.15 + 0.4 * D.ease_out(k)) * (0.6 + 0.4 * D.h01(i))
				cv.draw_circle(c + Vector2(cos(ang), sin(ang)) * r, t * 0.05, D.ca(col, a))
		_:
			D.twinkle(cv, c + Vector2(0, -t * 0.4), t * 0.12, D.ca(col, a))


## Persistent loop over an enemy while a status holds (between steps): stun
## stars orbit the head, roots bind the feet, spores drift around the body.
static func status_overlay(cv, V: Dictionary, c: Vector2, status: Dictionary, now: float) -> void:
	var t := D.ts(V)
	var s := now / 1000.0
	if int(status.get("stun", 0)) > 0:
		var col := L.status_col("stun")
		for i in 3:
			var ang := TAU * float(i) / 3.0 + s * 3.2
			D.twinkle(cv, c + Vector2(cos(ang) * t * 0.3, -t * 0.44 + sin(ang) * t * 0.08), t * 0.085, D.ca(col, 0.95))
	if int(status.get("root", 0)) > 0:
		var rc := Color("8a6a3e")
		for i in 3:
			var x := (float(i) - 1.0) * t * 0.22
			var base := c + Vector2(x, t * 0.44)
			D.wavy(cv, base, base + Vector2(-x * 0.4, -t * 0.34), t * 0.05, 1.0, s * 2.0 + float(i), D.ca(rc, 0.95), t * 0.06, 8)
		cv.draw_set_transform(c + Vector2(0, t * 0.38), 0.0, Vector2(1.0, 0.35))
		D.ring(cv, Vector2.ZERO, t * 0.34, D.ca(rc, 0.8), t * 0.06)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var spores := int(status.get("spore", 0))
	if spores > 0:
		var sc := L.status_col("spore")
		for i in mini(2 + spores, 8):
			var ph := D.h01(i * 17 + 3) * TAU
			var q := c + Vector2(cos(ph + s * 0.9) * t * 0.36, sin(ph * 1.3 + s * 0.7) * t * 0.3 - t * 0.05)
			cv.draw_circle(q, t * 0.04, D.ca(sc, 0.8))


## Persistent loop over the tender for its active buffs: bark plates for
## shield, a slow thorn crown for thorns, roots gripping the ground for anchor.
static func buff_overlay(cv, V: Dictionary, c: Vector2, pl: Dictionary, now: float) -> void:
	var t := D.ts(V)
	var s := now / 1000.0
	var shield := int(pl.get("shield", 0))
	if shield > 0:
		var bc := Color("7fb6d9")
		var n := mini(shield, 6)
		for i in n:
			var ang := s * 0.8 + TAU * float(i) / float(n)
			var q := c + Vector2(cos(ang), sin(ang) * 0.55) * t * 0.46
			D.leaf(cv, q, ang + PI * 0.5, t * 0.2, D.ca(bc, 0.55 + 0.25 * sin(s * 3.0 + float(i))))
	if int(pl.get("thorns_turns", 0)) > 0:
		var tc := Color("57b34a")
		for i in 8:
			var ang := -s * 0.6 + TAU * float(i) / 8.0
			var dirv := Vector2(cos(ang), sin(ang))
			D.spike(cv, c + dirv * t * 0.4, c + dirv * t * 0.54, t * 0.08, D.ca(tc, 0.9))
	if int(pl.get("anchor_turns", 0)) > 0:
		var rc := Color("8a6a3e")
		for i in 4:
			var sx := (float(i) - 1.5) * t * 0.2
			var base := c + Vector2(sx * 0.5, t * 0.36)
			D.wavy(cv, base, base + Vector2(sx * 1.3, t * 0.16), t * 0.03, 1.0, float(i) + s, D.ca(rc, 0.9), t * 0.06, 6)
