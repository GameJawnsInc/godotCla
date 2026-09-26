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
##
## The overlays draw the POST-step board's statuses and buffs, which the sim
## has already applied when the reel starts. So they would show a stun before
## the vial that causes it has left the satchel: the ground pass therefore
## notes every status/buff change the reel has not landed yet (from the
## status_pop / buff_pop clips, whose times the reel's speed already scaled)
## and the overlays show the PRE value until it lands.

const L := preload("res://shell/anim_lib.gd")
const D := preload("res://shell/anim_draw.gd")
const Art := preload("res://shell/svg_art.gd")
const FxLines := preload("res://shell/fx_lines.gd")
const FxAreas := preload("res://shell/fx_areas.gd")
const FxSelf := preload("res://shell/fx_self.gd")
const FxEnemy := preload("res://shell/fx_enemy.gd")

const FAMILIES := [FxLines, FxAreas, FxSelf, FxEnemy]
const CORE_KINDS := ["float", "burst", "puff", "ring", "spark", "status_pop", "slash", "scrub",
	"motes", "item", "cast_ring", "surge", "flare", "splash", "tile_pop", "portal",
	"impact", "dust", "petals", "buff_pop"]

## Outline ink: near-black with a green cast, so light shapes and numbers keep
## an edge on the dark green floor.
const INK := Color(0.035, 0.05, 0.035)
const GOLD := Color("e8c840")
const GOLD_HI := Color("fff4c2")
const LEAF := Color("6cc95c")
const LEAF_HI := Color("d2f7b4")
const LEAF_DARK := Color("2f6b2c")
const BARK := Color("8a6a3e")
const BARK_DARK := Color("47301b")
const BARK_LIGHT := Color("e0bd84")
const SHIELD := Color("7fb6d9")
const SHIELD_HI := Color("e8f7ff")
const PETAL := Color(0.93, 0.66, 0.80)
const OUTLINE_DIRS := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
	Vector2(0.7, 0.7), Vector2(-0.7, 0.7), Vector2(0.7, -0.7), Vector2(-0.7, -0.7)]
## Tender buff -> the snapshot's player key that holds it.
const BUFF_KEYS := {"shield": "shield", "thorns": "thorns_turns", "anchor": "anchor_turns"}

## Changes the current reel has not landed yet: [{who, key, pre, pos, t0}].
## Rebuilt by every ground pass; read by the overlays that follow it.
static var _hold: Array = []
## White silhouettes of creature sprites, by texture instance id.
static var _sil := {}


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
	if layer == "ground":
		_hold = _holds(reel, rt)
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
			_float(cv, cl, k, V)
		"burst":
			# a gold (or given colour) sparkle burst: a white-hot core, a ring
			# and eight twinkles thrown out, the big ones catching the light
			var c := D.px(V, cl["at"])
			var col: Color = cl.get("col", GOLD)
			var e := D.ease_out(k)
			var a := D.tail(k, 0.4)
			if k < 0.22:
				var f := 1.0 - k / 0.22
				D.glow(cv, c, t * (0.3 + 0.25 * (1.0 - f)), D.ca(col.lerp(Color.WHITE, 0.55), 0.6 * f))
			D.ring(cv, c, t * (0.18 + 0.55 * e), D.ca(col, 0.8 * (1.0 - k)), t * 0.06 * (1.0 - k))
			for i in 8:
				var ang := TAU * (float(i) + 0.4 * D.h01(i + 3)) / 8.0 - 0.3
				var r := t * (0.15 + (0.42 + 0.18 * D.h01(i * 5 + 1)) * e)
				var q := c + Vector2(cos(ang), sin(ang)) * r + Vector2(0, t * 0.18 * k * k)
				var big := i % 2 == 0
				D.twinkle(cv, q, t * (0.11 if big else 0.07) * (1.0 - 0.55 * k),
					D.ca(col.lerp(Color.WHITE, 0.45) if big else col, a))
		"puff":
			# a soft cloud that billows up and thins; `debris` throws bolts
			var c := D.px(V, cl["at"])
			var col: Color = cl.get("col", Color(0.62, 0.64, 0.66))
			var e := D.ease_out(k)
			var a := 0.62 * pow(1.0 - k, 1.3)
			for i in 5:
				var ang := TAU * float(i) / 5.0 + D.h01(i + 11) * 0.9
				var q := c + Vector2(cos(ang) * t * 0.3 * e, sin(ang) * t * 0.16 * e - t * (0.05 + 0.32 * e))
				var r := t * (0.11 + 0.15 * e) * (0.75 + 0.5 * D.h01(i * 7 + 2))
				cv.draw_circle(q + Vector2(0, r * 0.3), r, D.ca(col.darkened(0.5), a * 0.6))
				cv.draw_circle(q, r, D.ca(col, a))
			if bool(cl.get("debris", false)):
				var dc: Color = cl.get("debris_col", Color(0.42, 0.44, 0.47))
				var da := 1.0 - D.win(k, 0.45, 0.85)
				for i in 6:
					var ang := -PI * (0.08 + 0.84 * D.h01(i * 13 + 1))
					var v := Vector2(cos(ang), sin(ang)) * t * (0.45 + 0.4 * D.h01(i * 3 + 7))
					var q := c + v * D.ease_out(D.win(k, 0.0, 0.6)) + Vector2(0, t * 0.8 * k * k)
					var sz := t * (0.035 + 0.025 * D.h01(i + 29))
					cv.draw_rect(Rect2(q - Vector2(sz, sz), Vector2(sz, sz) * 2.0), D.ca(dc, da))
		"ring":
			var c := D.px(V, cl["at"])
			var col: Color = cl.get("col", Color.WHITE)
			var r := lerpf(float(cl.get("r0", 0.2)), float(cl.get("r1", 1.0)), D.ease_out(k)) * t
			var w := float(cl.get("w", 0.08)) * t * (1.0 - 0.5 * k)
			D.ring(cv, c, r, D.ca(INK, 0.35 * (1.0 - k)), w + 2.0)
			D.ring(cv, c, r, D.ca(col, 1.0 - k), w)
		"spark":
			# hot streaks thrown out of a point, a white core for the first beat
			var c := D.px(V, cl["at"])
			var col: Color = cl.get("col", Color.WHITE)
			var n := int(cl.get("n", 6))
			if k < 0.25:
				D.twinkle(cv, c, t * 0.22 * (1.0 - k / 0.25), D.ca(Color.WHITE, 0.95))
			for i in n:
				var ang := TAU * (float(i) + D.h01(i + n * 7)) / float(n)
				var dv := Vector2(cos(ang), sin(ang))
				var r0 := t * (0.1 + 0.42 * D.ease_out(k))
				var r1 := r0 + t * 0.2 * (1.0 - k)
				D.line(cv, c + dv * r0, c + dv * r1, D.ca(col, 1.0 - k), t * 0.055 * (1.0 - 0.4 * k))
		"status_pop":
			status_pop(cv, V, D.px(V, cl["at"]), String(cl.get("status", "")), k)
		"slash":
			_slash(cv, cl, k, V)
		"scrub":
			_scrub(cv, cl, k, V)
		"motes":
			# glowing seeds of light: rising (heals, surges) or travelling a -> b
			var a := D.px(V, cl["from"])
			var b := D.px(V, cl["to"])
			var col: Color = cl.get("col", LEAF)
			var n := int(cl.get("n", 6))
			var rise := bool(cl.get("rise", false))
			for i in n:
				var u := D.win(k, float(i) / float(n) * 0.35, float(i) / float(n) * 0.35 + 0.65)
				if u <= 0.0 or u >= 1.0:
					continue
				var jit := Vector2(D.h01(i * 3 + 1) - 0.5, D.h01(i * 5 + 2) - 0.5) * t * 0.62
				var q: Vector2
				if rise:
					q = a + Vector2(jit.x, jit.y * 0.4) + Vector2(sin(u * 6.0 + float(i)) * t * 0.08,
						t * 0.34 - t * 1.05 * D.ease_out(u))
				else:
					q = (a + jit).lerp(b, D.ease_io(u)) + Vector2(0, -t * 0.3 * sin(u * PI))
				var al := minf(1.0, sin(u * PI) * 1.6)
				cv.draw_circle(q, t * 0.11 * (1.0 - 0.4 * u), D.ca(col, 0.28 * al))
				cv.draw_circle(q, t * 0.055 * (1.0 - 0.4 * u), D.ca(col.lerp(Color.WHITE, 0.55), al))
		"item":
			_item(cv, cl, k, V)
		"cast_ring":
			# the wind-up at the tender's feet: motes of the ability's colour
			# are drawn in along the ground, then a bright ring releases
			var c := D.px(V, cl["at"]) + Vector2(0, t * 0.32)
			var pal: Dictionary = cl.get("pal", L.PAL_DEFAULT)
			var g := D.win(k, 0.0, 0.42)
			if g < 1.0:
				for i in 7:
					var ang := TAU * float(i) / 7.0 + k * 2.4
					var r := t * 0.62 * (1.0 - D.ease_in(g))
					var q := c + Vector2(cos(ang), sin(ang) * 0.42) * r
					cv.draw_circle(q, t * 0.06, D.ca(pal["c"], 0.5 * (1.0 - g * 0.5)))
					cv.draw_circle(q, t * 0.035, D.ca(pal["b"], 0.95))
			var rel := D.win(k, 0.36, 1.0)
			if rel > 0.0:
				var r2 := t * (0.18 + 0.5 * D.ease_out(rel))
				cv.draw_set_transform(c, 0.0, Vector2(1.0, 0.42))
				D.ring(cv, Vector2.ZERO, r2, D.ca(pal["c"], 0.7 * (1.0 - rel)), t * 0.12 * (1.0 - 0.5 * rel))
				D.ring(cv, Vector2.ZERO, r2, D.ca(pal["b"], 1.0 - rel), t * 0.06 * (1.0 - 0.5 * rel))
				cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"surge":
			# the growth underfoot pours up into the cast: leaves spiral in and up
			var c := D.px(V, cl["at"])
			D.glow(cv, c, t * 0.55 * D.pulse(k), D.ca(LEAF, 0.45))
			for i in 8:
				var ang := TAU * float(i) / 8.0 + k * 4.5
				var r := t * (0.52 - 0.36 * D.ease_in(k))
				var q := c + Vector2(cos(ang) * r, sin(ang) * r * 0.45 + t * (0.3 - 0.75 * k))
				var la := D.pulse(D.win(k, 0.0, 1.0)) * 1.2
				D.leaf(cv, q, ang + PI * 0.5, t * 0.22, D.ca(LEAF_DARK, 0.8 * la))
				D.leaf(cv, q, ang + PI * 0.5, t * 0.16, D.ca(LEAF_HI.lerp(LEAF, 0.4), la))
		"flare":
			# a tile catching fire: three tongues leap up out of a hot glow
			var c := D.px(V, cl["at"])
			var col: Color = cl.get("col", Color("ef933a"))
			var up := D.ease_out(D.win(k, 0.0, 0.28))
			var a := D.tail(k, 0.3)
			D.glow(cv, c, t * (0.3 + 0.35 * up), D.ca(col, 0.65 * a))
			for i in 3:
				var x := (float(i) - 1.0) * t * 0.18
				var h := t * (0.25 + 0.7 * up * (1.0 - 0.3 * absf(float(i) - 1.0)))
				var base := c + Vector2(x, t * 0.3)
				var tip := c + Vector2(x * 0.5 + sin(k * 9.0 + float(i)) * t * 0.05, t * 0.3 - h)
				D.spike(cv, base, tip, t * 0.26, D.ca(Color("b8441e"), a))
				D.spike(cv, base, base.lerp(tip, 0.85), t * 0.17, D.ca(Color("fdf0a8") if i == 1 else col, a))
		"splash":
			# water lands: droplets arc out and fall, a bright ring spreads
			var c := D.px(V, cl["at"])
			var water := Color("7ec8e0")
			for i in 7:
				var ang := -PI * (0.1 + 0.8 * float(i) / 6.0)
				var r := t * (0.4 + 0.12 * D.h01(i + 5)) * D.ease_out(k)
				var q := c + Vector2(cos(ang), sin(ang)) * r + Vector2(0, t * 0.55 * k * k)
				cv.draw_circle(q, t * 0.06 * (1.0 - 0.6 * k), D.ca(Color("2f6f9a"), 0.6 * (1.0 - k)))
				cv.draw_circle(q, t * 0.042 * (1.0 - 0.6 * k), D.ca(water.lerp(Color.WHITE, 0.3), 1.0 - k))
			cv.draw_set_transform(c + Vector2(0, t * 0.22), 0.0, Vector2(1.0, 0.45))
			D.ring(cv, Vector2.ZERO, t * 0.48 * D.ease_out(k), D.ca(Color("d6f1fb"), 0.85 * (1.0 - k)), t * 0.07)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"tile_pop":
			# the tile answers: a soft bloom of its new colour swells and fades
			var c := D.px(V, cl["at"])
			var col: Color = cl.get("col", LEAF)
			var e := D.ease_out(k)
			var fa := 1.0 - D.ease_out(k)
			cv.draw_circle(c, t * (0.2 + 0.28 * e), D.ca(col.lerp(Color.WHITE, 0.3), 0.32 * fa))
			D.ring(cv, c, t * (0.26 + 0.28 * e), D.ca(col.lerp(Color.WHITE, 0.6), 0.85 * fa), t * 0.06 * fa + 1.0)
		"portal":
			# a machine arrives: a dark vent opens on the floor, sparks rise out
			var c := D.px(V, cl["at"])
			var col: Color = cl.get("col", Color("e04b3a"))
			var o := D.pulse(k)
			cv.draw_set_transform(c + Vector2(0, t * 0.3), 0.0, Vector2(1.0, 0.42))
			cv.draw_circle(Vector2.ZERO, t * 0.36 * o, Color(0.04, 0.02, 0.02, 0.6 * o))
			D.ring(cv, Vector2.ZERO, t * 0.44 * o, D.ca(col, 0.95 * o), t * 0.09)
			D.ring(cv, Vector2.ZERO, t * 0.44 * o, D.ca(col.lerp(Color.WHITE, 0.5), 0.8 * o), t * 0.035)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			for i in 5:
				var ang := TAU * float(i) / 5.0 - k * 5.0
				cv.draw_circle(c + Vector2(cos(ang) * t * 0.36, sin(ang) * t * 0.15 + t * 0.3 - t * 0.55 * k),
					t * 0.045, D.ca(col.lerp(Color.WHITE, 0.3), 1.0 - k))
		"impact":
			# the instant a blow lands: a white-hot star bursting on the side
			# the blow came from - four long rays, four short, gone in a blink
			var d: Vector2 = cl.get("dir", Vector2.ZERO)
			var c := D.px(V, cl["at"]) - d * t * 0.18
			var col: Color = cl.get("col", Color.WHITE)
			var e := D.ease_out(k)
			var a := 1.0 - D.ease_in(k)
			for i in 8:
				var ang := PI * 0.25 + TAU * float(i) / 8.0 + d.angle()
				var dv := Vector2(cos(ang), sin(ang))
				var ln := t * (0.2 + (0.26 if i % 2 == 0 else 0.1) * e)
				D.spike(cv, c + dv * t * 0.05, c + dv * ln, t * (0.09 if i % 2 == 0 else 0.06) * (1.0 - 0.6 * k),
					D.ca(col, a))
			D.twinkle(cv, c, t * 0.3 * (1.0 - e), D.ca(Color.WHITE, a))
		"dust":
			# a landing kicks up a little dust behind the feet
			var c := D.px(V, cl["at"]) + Vector2(0, t * 0.36)
			var d: Vector2 = cl.get("dir", Vector2.ZERO)
			var e := D.ease_out(k)
			var dc := Color(0.86, 0.82, 0.66)
			for i in 6:
				var side := -1.0 if i % 2 == 0 else 1.0
				var row := float(i / 2)
				var sp := Vector2(side * (0.16 + 0.16 * row), -0.03 - 0.07 * row)
				var q := c + (sp - d * 0.22) * t * (0.3 + 0.7 * e)
				cv.draw_circle(q, t * (0.05 + 0.07 * e) * (1.0 - 0.2 * row), D.ca(dc, 0.6 * (1.0 - k)))
		"petals":
			_petals(cv, cl, k, V)
		"buff_pop":
			_buff_pop(cv, cl, k, V)


# --- clip painters ----------------------------------------------------------------

## A number or a word rising off a creature. Numbers slam in large with a dark
## edge and settle; more of them on one body fan out left and right. `n` is
## the float's place in that stack.
static func _float(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var col: Color = cl.get("col", Color.WHITE)
	var s := String(cl.get("text", ""))
	var n := int(cl.get("n", 0))
	var big := _is_number(s)
	var p := D.px(V, cl["at"])
	if n > 0:
		p += Vector2((0.26 if n % 2 == 1 else -0.26) * t, -0.16 * t * float(n))
	var rise := D.ease_out(D.win(k, 0.0, 0.45))
	var y := p.y - t * (0.4 + 0.24 * rise + 0.08 * k)
	var pop := 1.0 + 0.55 * (1.0 - D.ease_out(D.win(k, 0.0, 0.13)))
	var mag := 1.0
	if big:
		mag = clampf(0.9 + 0.12 * float(absi(s.to_int())), 1.0, 1.45)
	var sz := maxi(9, int(t * (0.46 if big else 0.3) * mag * pop))
	var a := D.tail(k, 0.62)
	_text_o(cv, V, Vector2(p.x, y), s, D.ca(col, a), sz)


static func _is_number(s: String) -> bool:
	return s.length() >= 2 and (s[0] == "-" or s[0] == "+") and s.substr(1).is_valid_int()


## Centred text with an eight-way dark edge (numbers must read on any floor).
static func _text_o(cv, V: Dictionary, p: Vector2, s: String, col: Color, size: int) -> void:
	var font = V.get("font")
	if font == null or s == "" or col.a <= 0.01:
		return
	var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var o := Vector2(p.x - w * 0.5, p.y + float(size) * 0.36)
	var ow := maxf(1.2, float(size) * 0.085)
	var ink := Color(INK.r, INK.g, INK.b, col.a * 0.9)
	for d in OUTLINE_DIRS:
		cv.draw_string(font, o + (d as Vector2) * ow, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)
	cv.draw_string(font, o, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## The tender's strike: a leafy blade sweeps ACROSS the target - a crescent
## whose head crosses the body's centre a tenth into the clip, which the
## planner lines up with the blow - then sheds three leaves along the swing.
static func _slash(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var c := D.px(V, cl["at"])
	var d: Vector2 = cl.get("dir", Vector2.RIGHT)
	if d.length() < 0.01:
		d = Vector2.RIGHT
	var pal: Dictionary = cl.get("pal", L.PAL_DEFAULT)
	var side := Vector2(-d.y, d.x)
	var sweep := D.ease_out(D.win(k, 0.0, 0.3))
	var a := D.tail(k, 0.35)
	# the blade's arc is centred behind the target so it cuts through its middle
	var ctr := c - d * t * 0.55
	var rad := t * 0.62
	var span := 1.7
	var a0 := d.angle() - span * 0.5
	var a1 := a0 + span * sweep
	var trail := maxf(a0, a1 - span * (0.6 + 0.4 * D.win(k, 0.25, 1.0)))
	if a1 - trail > 0.15 and a > 0.01:
		var outer := PackedVector2Array()
		var inner := PackedVector2Array()
		for i in 9:
			var u := float(i) / 8.0
			var ang := lerpf(trail, a1, u)
			var dv := Vector2(cos(ang), sin(ang))
			# thin at the tail, full at the head
			var th := t * (0.03 + 0.2 * sqrt(u)) * (1.0 - 0.45 * k)
			outer.append(ctr + dv * (rad + th * 0.6))
			inner.append(ctr + dv * (rad - th * 0.4))
		var edge := PackedVector2Array(outer)
		var fill := PackedVector2Array(outer)
		inner.reverse()
		fill.append_array(inner)
		cv.draw_colored_polygon(fill, D.ca(pal["c"], 0.75 * a))
		var core := PackedVector2Array()
		for i in 9:
			core.append((edge[i] + inner[8 - i]) * 0.5)
		cv.draw_polyline(core, D.ca(pal["a"].lerp(pal["b"], 0.4), a), maxf(1.5, t * 0.07 * (1.0 - 0.4 * k)), true)
		cv.draw_polyline(edge, D.ca(pal["b"].lerp(Color.WHITE, 0.4), a), maxf(1.0, t * 0.035), true)
	# the bite: white-hot where the blade meets the body
	if k > 0.06 and k < 0.36:
		var f := D.pulse(D.win(k, 0.06, 0.36))
		D.glow(cv, c, t * 0.34 * f, D.ca(Color.WHITE, 0.5))
	# leaves shorn off, flung along the swing and fluttering down
	if k > 0.14:
		var u := D.win(k, 0.14, 1.0)
		for i in 3:
			var spread := (float(i) - 1.0) * 0.6
			var v := (d + side * spread).normalized()
			var q := c + v * t * (0.2 + 0.5 * D.ease_out(u)) \
				+ Vector2(sin(u * 7.0 + float(i) * 2.0) * t * 0.06, t * 0.3 * u * u)
			var la := 1.0 - D.ease_in(u)
			var ang := v.angle() + u * 5.0 + float(i)
			D.leaf(cv, q, ang, t * 0.22, D.ca(pal["c"], 0.85 * la))
			D.leaf(cv, q, ang, t * 0.15, D.ca(pal["a"].lerp(pal["b"], 0.35), la))


## Cleansing: the tender scrubs - two bright strokes whirl round the tile
## while the filth lifts off it in dark flecks - and as the tile turns, what
## was scrubbed off rises as gold.
static func _scrub(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var c := D.px(V, cl["at"])
	var sw := D.win(k, 0.0, 0.48)
	if sw < 1.0:
		var sa := minf(1.0, D.pulse(sw) * 1.5)
		for j in 2:
			var ph := float(j) * PI + D.ease_io(sw) * TAU * 1.8
			var pts := PackedVector2Array()
			for i in 9:
				var ang := ph - float(8 - i) * 0.2
				pts.append(c + Vector2(cos(ang) * t * 0.38, sin(ang) * t * 0.27 + t * 0.04))
			cv.draw_polyline(pts, D.ca(INK, 0.4 * sa), t * 0.15, true)
			cv.draw_polyline(pts, D.ca(GOLD, 0.9 * sa), t * 0.09, true)
			cv.draw_polyline(pts.slice(4), D.ca(GOLD_HI, sa), t * 0.05, true)
			cv.draw_circle(pts[8], t * 0.07, D.ca(Color.WHITE, sa))
		# the muck lifts off in dark flecks that catch the light as they rise
		for i in 7:
			var u := D.win(k, 0.03 + 0.05 * float(i), 0.36 + 0.05 * float(i))
			if u <= 0.0 or u >= 1.0:
				continue
			var q := c + Vector2((D.h01(i * 11 + 2) - 0.5) * t * 0.7, t * 0.1 - t * 0.7 * D.ease_out(u))
			var fr := t * 0.08 * (1.0 - 0.55 * u)
			var fc := Color(0.14, 0.1, 0.15).lerp(GOLD, D.ease_in(u))
			cv.draw_circle(q, fr + 1.5, D.ca(Color(0.6, 0.55, 0.62), 0.5 * (1.0 - u)))
			cv.draw_circle(q, fr, D.ca(fc, 0.95 * (1.0 - u * u)))
	# the tile turns: a warm glow, and gold rising off it
	var gw := D.win(k, 0.3, 0.7)
	if gw > 0.0 and gw < 1.0:
		D.glow(cv, c, t * 0.5 * D.pulse(gw), D.ca(GOLD, 0.4))
	var g := D.win(k, 0.32, 1.0)
	if g > 0.0 and g < 1.0:
		for i in 8:
			var ph := D.win(g, float(i) * 0.06, float(i) * 0.06 + 0.58)
			if ph <= 0.0 or ph >= 1.0:
				continue
			var q := c + Vector2((D.h01(i * 7 + 5) - 0.5) * t * 0.75 + sin(ph * 6.0 + float(i)) * t * 0.05,
				t * 0.15 - t * (0.1 + 0.75 * D.ease_out(ph)))
			D.twinkle(cv, q, t * (0.14 if i % 2 == 0 else 0.1) * D.pulse(ph), D.ca(GOLD_HI if i % 2 == 0 else GOLD, 1.0))


## A consumable leaves the satchel: it pops out at the tender's hip, springs
## up over its head with a glint, then is used - `use` "consume" (it shrinks
## into the tender), "shatter" (it bursts overhead in shards) or "pickup" (it
## rises off the floor and drops into the satchel).
static func _item(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var c := D.px(V, cl["at"])
	var use := String(cl.get("use", "consume"))
	var sz := int(t * 0.72)
	var tx = Art.tex("it_" + String(cl.get("id", "")).trim_suffix("+"), maxi(8, sz))  # items keep the plain "+"
	var hip := c + Vector2(t * 0.28, t * 0.16)
	var top := c + Vector2(0, -t * 0.78)
	var col: Color = cl.get("col", GOLD_HI)
	var q := top
	var sc := 1.0
	var a := 1.0
	if use == "pickup":
		# off the floor, up, and into the bag
		var up := D.ease_out(D.win(k, 0.0, 0.35))
		var into := D.ease_in(D.win(k, 0.6, 1.0))
		q = c.lerp(top, up).lerp(hip, into)
		sc = (0.4 + 0.75 * up) * (1.0 - 0.7 * into)
		a = 1.0 - D.win(k, 0.85, 1.0)
	else:
		var out := D.win(k, 0.0, 0.3)
		q = D.arc_point(hip, top, D.ease_out(out), t * 0.25)
		sc = 0.35 + 0.8 * D.ease_out(out) - 0.15 * D.win(k, 0.3, 0.4)
		if use == "shatter":
			var br := D.win(k, 0.52, 0.58)
			a = 1.0 - br
			sc *= 1.0 + 0.2 * br
			var sh := D.win(k, 0.52, 1.0)
			if sh > 0.0 and sh < 1.0:
				var e := D.ease_out(sh)
				D.ring(cv, top, t * (0.15 + 0.6 * e), D.ca(col, 0.9 * (1.0 - sh)), t * 0.08 * (1.0 - sh) + 1.0)
				for i in 8:
					var ang := TAU * (float(i) + 0.5 * D.h01(i + 17)) / 8.0
					var p2 := top + Vector2(cos(ang), sin(ang)) * t * (0.12 + 0.6 * e) + Vector2(0, t * 0.5 * sh * sh)
					var s2 := t * 0.07 * (1.0 - sh)
					D.tri(cv, p2 + Vector2(0, -s2), p2 + Vector2(s2 * 0.8, s2 * 0.6), p2 + Vector2(-s2 * 0.7, s2 * 0.5),
						D.ca(Color(0.85, 0.95, 1.0) if i % 2 == 0 else col, 1.0 - sh))
		else:
			var inn := D.ease_in(D.win(k, 0.5, 0.86))
			q = q.lerp(c + Vector2(0, -t * 0.1), inn)
			sc *= 1.0 - 0.8 * inn
			a = 1.0 - D.win(k, 0.8, 0.9)
			var gl := D.win(k, 0.84, 1.0)
			if gl > 0.0 and gl < 1.0:
				D.ring(cv, c, t * (0.25 + 0.4 * D.ease_out(gl)), D.ca(col, 0.9 * (1.0 - gl)), t * 0.07 * (1.0 - gl) + 1.0)
	if a <= 0.01 or sc <= 0.02:
		return
	# a glint behind it while it is up
	D.glow(cv, q, t * 0.42 * sc, D.ca(col, 0.35 * a))
	if D.win(k, 0.2, 0.5) > 0.0 and k < 0.5:
		D.twinkle(cv, q + Vector2(t * 0.24, -t * 0.22) * sc, t * 0.13 * D.pulse(D.win(k, 0.2, 0.5)), D.ca(Color.WHITE, a))
	if tx != null:
		var half := Vector2(float(sz), float(sz)) * 0.5
		cv.draw_set_transform(q, sin(k * 9.0) * 0.12 * (1.0 - k), Vector2(sc, sc))
		cv.draw_texture(tx, -half, Color(1, 1, 1, a))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		cv.draw_circle(q, t * 0.16 * sc, D.ca(col, a))


## The tender wilts: as it collapses its petals and leaves burst loose, spin
## out and flutter down.
static func _petals(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var c := D.px(V, cl["at"]) + Vector2(0, -t * 0.1)
	var n := int(cl.get("n", 12))
	for i in n:
		var h := D.h01(i * 19 + 7)
		var ang := -PI * (0.05 + 0.9 * (float(i) + 0.5 * h) / float(n))
		var v := Vector2(cos(ang), sin(ang)) * t * (0.35 + 0.5 * D.h01(i * 5 + 3))
		var u := D.win(k, 0.03 * float(i % 4), 1.0)
		if u <= 0.0:
			continue
		# thrown out, then drifting down with a sideways flutter
		var q := c + v * D.ease_out(D.win(u, 0.0, 0.45)) + Vector2(sin(u * 9.0 + h * 6.0) * t * 0.1, t * 0.7 * D.ease_in(u))
		var a := 1.0 - D.ease_in(D.win(u, 0.55, 1.0))
		var col := PETAL if i % 3 != 0 else LEAF
		var spin := u * (5.0 + 4.0 * h) + h * TAU
		D.leaf(cv, q, spin, t * (0.17 + 0.05 * h), D.ca(col.darkened(0.45), 0.7 * a))
		D.leaf(cv, q, spin, t * (0.12 + 0.04 * h), D.ca(col, a))


## A buff lands on the tender (or a shield plate breaks): a quick flourish in
## its colour. It also marks WHEN the overlay may start showing the new value.
static func _buff_pop(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var c := D.px(V, cl["at"])
	var buff := String(cl.get("buff", ""))
	var e := D.ease_out(k)
	var a := 1.0 - k
	match buff:
		"shield":
			if bool(cl.get("break", false)):
				# plates crack off and fall away
				for i in 5:
					var ang := -PI * 0.5 + TAU * float(i) / 5.0 + 0.3
					var dv := Vector2(cos(ang), sin(ang))
					var q := c + dv * t * (0.42 + 0.3 * e) + Vector2(0, t * 0.6 * k * k)
					var s2 := t * 0.1 * (1.0 - 0.5 * k)
					D.tri(cv, q + dv * s2, q - dv * s2 + Vector2(-dv.y, dv.x) * s2, q - Vector2(-dv.y, dv.x) * s2,
						D.ca(SHIELD.lerp(Color.WHITE, 0.3), a))
				D.ring(cv, c, t * (0.46 + 0.1 * e), D.ca(SHIELD_HI, 0.8 * a), t * 0.05)
			else:
				D.ring(cv, c, t * (0.62 - 0.14 * e), D.ca(SHIELD_HI, 0.9 * a), t * 0.07 * a + 1.0)
		"thorns":
			for i in 8:
				var ang := TAU * float(i) / 8.0 + k
				var dv := Vector2(cos(ang), sin(ang))
				D.spike(cv, c + dv * t * 0.4, c + dv * t * (0.5 + 0.2 * e), t * 0.1, D.ca(LEAF_HI, a))
		_:
			cv.draw_set_transform(c + Vector2(0, t * 0.38), 0.0, Vector2(1.0, 0.4))
			D.ring(cv, Vector2.ZERO, t * (0.3 + 0.45 * e), D.ca(BARK_LIGHT, 0.9 * a), t * 0.08)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- statuses -------------------------------------------------------------------

## A status landing on a creature. A ring in the status colour snaps IN onto
## the body (it grabs), then: stun stars burst off the head and settle into
## the orbit the overlay keeps, roots erupt and coil up the legs, spores puff
## out in a violet cloud.
static func status_pop(cv, V: Dictionary, c: Vector2, status: String, k: float) -> void:
	var t := D.ts(V)
	var col := L.status_col(status)
	var a := D.tail(k, 0.6)
	var grab := D.ease_out(D.win(k, 0.0, 0.2))
	if k < 0.35:
		var rr := t * (0.8 - 0.42 * grab)
		D.ring(cv, c, rr, D.ca(INK, 0.4 * (1.0 - k / 0.35)), t * 0.12)
		D.ring(cv, c, rr, D.ca(col, 0.95 * (1.0 - k / 0.35)), t * 0.065)
	match status:
		"stun":
			if k < 0.3:
				D.twinkle(cv, c + Vector2(0, -t * 0.42), t * 0.3 * D.pulse(D.win(k, 0.05, 0.3)), D.ca(Color.WHITE, 0.95))
			var out := 1.0 - D.ease_out(D.win(k, 0.12, 0.55))
			for i in 3:
				var ang := TAU * float(i) / 3.0 + k * 7.0
				var rad := t * (0.3 + 0.25 * out)
				var q := c + Vector2(cos(ang) * rad, -t * 0.46 + sin(ang) * rad * 0.28)
				_star5(cv, q, t * (0.11 + 0.08 * out) * grab, D.ca(col, a), ang)
		"root":
			# roots break the ground and whip up round the legs (never over the
			# face: the overlay's binding takes over as they settle)
			var grow := D.ease_out(D.win(k, 0.05, 0.4))
			var ra := D.tail(k, 0.45)
			for i in 4:
				var x := (float(i) - 1.5) * t * 0.2
				var base := c + Vector2(x * 1.4, t * 0.44)
				var tip := base + Vector2(-x * 0.6, -t * 0.46 * grow)
				D.wavy(cv, base, tip, t * 0.06, 1.2, float(i) * 1.7, D.ca(BARK_DARK, ra), t * 0.09, 7)
				D.wavy(cv, base, tip, t * 0.06, 1.2, float(i) * 1.7, D.ca(BARK.lerp(BARK_LIGHT, 0.35), ra), t * 0.045, 7)
			# clods thrown up where they broke the ground
			if k < 0.5:
				for i in 4:
					var ang := -PI * (0.15 + 0.7 * float(i) / 3.0)
					var q := c + Vector2(0, t * 0.42) + Vector2(cos(ang), sin(ang)) * t * 0.45 * D.ease_out(k / 0.5) \
						+ Vector2(0, t * 0.5 * k * k)
					cv.draw_circle(q, t * 0.045, D.ca(BARK_DARK, 1.0 - k / 0.5))
		"spore":
			var e := D.ease_out(k)
			var sa := D.tail(k, 0.3)
			for i in 7:
				var ang := TAU * (float(i) + 0.3 * D.h01(i * 11 + 3)) / 7.0
				var r := t * (0.26 + 0.34 * e) * (0.8 + 0.2 * D.h01(i))
				var q := c + Vector2(cos(ang), sin(ang) * 0.8) * r + Vector2(0, -t * 0.1 * e)
				cv.draw_circle(q, t * (0.06 + 0.06 * e), D.ca(col, 0.4 * sa))
				cv.draw_circle(q, t * 0.035, D.ca(col.lerp(Color.WHITE, 0.45), sa))
		_:
			D.twinkle(cv, c + Vector2(0, -t * 0.42), t * 0.14, D.ca(col, a))


## Persistent loop over an enemy while a status holds (between steps): stun
## stars orbit the head, roots bind the feet, spores drift up off the body.
static func status_overlay(cv, V: Dictionary, c: Vector2, status: Dictionary, now: float) -> void:
	var st := status
	if not _hold.is_empty():
		var q := _tile_of(V, c)
		var copied := false
		for h in _hold:
			if h["who"] is String or (h["pos"] as Vector2).distance_to(q) > 0.7:
				continue
			if not copied:
				st = status.duplicate()
				copied = true
			st[h["key"]] = h["pre"]
	var t := D.ts(V)
	var s := now / 1000.0
	if int(st.get("stun", 0)) > 0:
		var col := L.status_col("stun")
		for i in 3:
			var ang := TAU * float(i) / 3.0 + s * 2.6
			var depth := 0.5 + 0.5 * sin(ang)  # 0 behind the head, 1 in front
			var q := c + Vector2(cos(ang) * t * 0.3, -t * 0.46 + sin(ang) * t * 0.085)
			_star5(cv, q, t * (0.075 + 0.035 * depth), D.ca(col, 0.55 + 0.45 * depth), s * 3.0 + float(i))
	if int(st.get("root", 0)) > 0:
		var feet := c + Vector2(0, t * 0.4)
		cv.draw_set_transform(feet, 0.0, Vector2(1.0, 0.34))
		D.ring(cv, Vector2.ZERO, t * 0.33, D.ca(BARK_DARK, 0.9), t * 0.11)
		D.ring(cv, Vector2.ZERO, t * 0.33, D.ca(BARK, 0.95), t * 0.055)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for i in 3:
			var x := (float(i) - 1.0) * t * 0.24
			var base := feet + Vector2(x, t * 0.02)
			var tip := base + Vector2(-x * 0.35, -t * (0.3 + 0.03 * sin(s * 2.0 + float(i))))
			D.wavy(cv, base, tip, t * 0.05, 1.0, float(i) * 2.0, D.ca(BARK_DARK, 0.95), t * 0.09, 6)
			D.wavy(cv, base, tip, t * 0.05, 1.0, float(i) * 2.0, D.ca(BARK.lerp(BARK_LIGHT, 0.3), 0.95), t * 0.045, 6)
	var spores := int(st.get("spore", 0))
	if spores > 0:
		var sc := L.status_col("spore")
		for i in mini(2 + spores, 7):
			# each spore drifts up off the body on its own 2.2 s cycle
			var ph := fposmod(s / 2.2 + D.h01(i * 17 + 3), 1.0)
			var x := (D.h01(i * 5 + 1) - 0.5) * t * 0.7 + sin(ph * 5.0 + float(i)) * t * 0.06
			var q := c + Vector2(x, t * 0.2 - t * 0.6 * ph)
			var al := D.pulse(ph)
			cv.draw_circle(q, t * 0.07, D.ca(sc, 0.3 * al))
			cv.draw_circle(q, t * 0.035, D.ca(sc.lerp(Color.WHITE, 0.35), 0.95 * al))


## Persistent loop over the tender for its active buffs: blue-glazed bark
## plates ring it for shield (one per point, up to six), a slow collar of
## thorns for thorns, roots fanned into the ground for anchor.
static func buff_overlay(cv, V: Dictionary, c: Vector2, pl: Dictionary, now: float) -> void:
	var p := pl
	var copied := false
	for h in _hold:
		if h["who"] is String and BUFF_KEYS.has(h["key"]):
			if not copied:
				p = pl.duplicate()
				copied = true
			p[BUFF_KEYS[h["key"]]] = h["pre"]
	var t := D.ts(V)
	var s := now / 1000.0
	var shield := int(p.get("shield", 0))
	if shield > 0:
		var n := mini(shield, 6)
		var r := t * 0.5
		var half := PI / float(maxi(n, 3)) * 0.62
		var glint := fposmod(s / 2.6, 1.0)
		for i in n:
			var md := -PI * 0.5 + TAU * float(i) / float(n) + s * 0.25
			_band(cv, c, r - t * 0.07, r + t * 0.07, md - half, md + half, D.ca(BARK_DARK.lerp(SHIELD.darkened(0.45), 0.7), 0.7))
			_band(cv, c, r - t * 0.045, r + t * 0.05, md - half * 0.85, md + half * 0.85, D.ca(SHIELD, 0.62))
			var gl := 1.0 - clampf(absf(fposmod(md / TAU - glint + 0.5, 1.0) - 0.5) * 8.0, 0.0, 1.0)
			cv.draw_arc(c, r + t * 0.035, md - half * 0.7, md + half * 0.7, 5, D.ca(SHIELD_HI, 0.5 + 0.45 * gl),
				maxf(1.0, t * 0.03), true)
	if int(p.get("thorns_turns", 0)) > 0:
		for i in 8:
			var ang := -PI * 0.5 + TAU * float(i) / 8.0 - s * 0.35
			var dv := Vector2(cos(ang), sin(ang))
			var base := c + dv * t * 0.4
			D.spike(cv, base, c + dv * t * 0.58, t * 0.12, D.ca(LEAF_DARK, 0.95))
			D.spike(cv, base, c + dv * t * 0.54, t * 0.06, D.ca(LEAF.lerp(LEAF_HI, 0.3), 0.95))
	if int(p.get("anchor_turns", 0)) > 0:
		var foot := c + Vector2(0, t * 0.42)
		var br := 0.92 + 0.08 * sin(s * 1.6)
		for i in 5:
			var ang := PI * (-0.1 + 1.2 * (float(i) + 0.5) / 5.0)
			var tip := foot + Vector2(cos(ang), sin(ang) * 0.45) * t * 0.48 * br
			D.wavy(cv, foot, tip, t * 0.03, 1.0, float(i) * 1.3, D.ca(BARK_DARK, 0.95), t * 0.09, 5)
			D.wavy(cv, foot, tip, t * 0.03, 1.0, float(i) * 1.3, D.ca(BARK.lerp(BARK_LIGHT, 0.3), 0.95), t * 0.045, 5)


# --- shared shapes and the silhouette -----------------------------------------------

## A five-point star centred on p (outer radius r), rotated by rot.
static func _star5(cv, p: Vector2, r: float, col: Color, rot: float) -> void:
	if r < 1.0 or col.a <= 0.01:
		return
	var pts := PackedVector2Array()
	for i in 10:
		var ang := rot - PI * 0.5 + PI * float(i) / 5.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(p + Vector2(cos(ang), sin(ang)) * rr)
	var ink := PackedVector2Array()
	for q in pts:
		ink.append(p + (q - p) * 1.35)
	cv.draw_colored_polygon(ink, D.ca(INK, col.a * 0.55))
	cv.draw_colored_polygon(pts, col)


## A curved band: the ring between radii r0 and r1 from angle a0 to a1.
static func _band(cv, c: Vector2, r0: float, r1: float, a0: float, a1: float, col: Color) -> void:
	if col.a <= 0.01 or r1 - r0 < 0.5 or a1 - a0 < 0.02:
		return
	var pts := PackedVector2Array()
	for i in 6:
		var a := lerpf(a0, a1, float(i) / 5.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r1)
	for i in 6:
		var a := lerpf(a1, a0, float(i) / 5.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r0)
	cv.draw_colored_polygon(pts, col)


## Tile-space position of a body centre drawn at pixel c (the overlays get
## pixels; the holds are kept in tiles).
static func _tile_of(V: Dictionary, c: Vector2) -> Vector2:
	var t := D.ts(V)
	return Vector2((c.x - float(V["ox"])) / t - 0.5, (c.y - float(V["oy"])) / t - 0.5)


## The status/buff changes the reel at time rt has not landed yet. A change
## lands a fifth of the way into its pop (when the ring grabs); until then the
## overlay keeps showing the value from before the step (`pre`).
static func _holds(reel: Dictionary, rt: float) -> Array:
	var out: Array = []
	if reel.is_empty() or rt > float(reel.get("len", 0)) + 40.0:
		return out
	for cl in reel.get("clips", []):
		var kind := String(cl["kind"])
		if kind != "status_pop" and kind != "buff_pop":
			continue
		if not cl.has("who"):
			continue
		var t0 := float(cl["t0"])
		if rt >= t0 + float(cl["dur"]) * 0.2:
			continue
		var who = cl["who"]
		var key := String(cl.get("status", cl.get("buff", "")))
		var pos := Vector2(cl["at"])
		if not (who is String):
			pos = _track_pos(reel, who, rt, pos)
		var h := {"who": who, "key": key, "pre": int(cl.get("pre", 0)), "pos": pos, "t0": t0}
		var dup := -1
		for i in out.size():
			if L.same_id(out[i]["who"], who) and String(out[i]["key"]) == key:
				dup = i
		# the earliest pending change of a key decides what shows now
		if dup < 0:
			out.append(h)
		elif t0 < float(out[dup]["t0"]):
			out[dup] = h
	return out


## A creature's tile-space position at reel time t from its path segments
## (the same fold shell/anim.gd pos_at() does).
static func _track_pos(reel: Dictionary, key, t: float, cur: Vector2) -> Vector2:
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
			var m := pts.size() - 1
			var u := clampf((t - t0) / dur, 0.0, 1.0) * float(m)
			var j := mini(int(u), m - 1)
			base = (pts[j] as Vector2).lerp(pts[j + 1], u - float(j))
			break
		base = pts[pts.size() - 1]
	return cur if base == null else base


## A white copy of a creature sprite (same alpha), cached per texture. Drawn
## over the sprite it turns the body white-hot (a hit flash) or washes it one
## colour (a hurt tint, a cast's glow): a modulate above 1 whitens only as far
## as each pixel's own brightness allows, so the dark outlines and eyes stayed
## green through the old flash.
static func silhouette(tx: Texture2D) -> Texture2D:
	if tx == null:
		return null
	var key := tx.get_instance_id()
	if _sil.has(key):
		return _sil[key]
	var img: Image = tx.get_image()
	if img == null or img.is_empty():
		_sil[key] = null
		return null
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	for i in range(0, data.size(), 4):
		data[i] = 255
		data[i + 1] = 255
		data[i + 2] = 255
	var out := ImageTexture.create_from_image(Image.create_from_data(img.get_width(), img.get_height(), false,
		Image.FORMAT_RGBA8, data))
	_sil[key] = out
	return out
