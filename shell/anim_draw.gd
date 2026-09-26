extends RefCounted
## Drawing helpers for the animation painter (shell/anim_paint.gd) and the
## verb families (shell/fx_*.gd).
##
## `cv` is any object with CanvasItem's draw_* methods: the shell's Node2D
## while it is inside its own _draw(), or the recording canvas
## tests/test_anim.gd paints through headless. Helpers never read the clock -
## `k` (0..1 through a clip) and V.now (ms, for loops that outlive a clip) are
## handed in.
##
## V (the view) = {ts: tile size px, ox/oy: pixel origin of tile (0, 0),
## font, now: ms, vis: optional Callable(Vector2i) -> bool - the room
## camera's crop: Paint.paint skips a clip whose `at` tile it rejects and
## fx_enemy keeps tall effects under the status strip with it; absent (the
## headless suite) means every tile is seen}. Tile coordinates are
## Vector2/Vector2i; px() is the CENTRE of that tile.

static func px(V: Dictionary, p) -> Vector2:
	var q := Vector2(p)
	var ts := float(V["ts"])
	return Vector2(float(V["ox"]) + (q.x + 0.5) * ts, float(V["oy"]) + (q.y + 0.5) * ts)


static func ts(V: Dictionary) -> float:
	return float(V["ts"])


static func ca(col: Color, a: float) -> Color:
	return Color(col.r, col.g, col.b, col.a * clampf(a, 0.0, 1.0))


static func ease_out(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return 1.0 - (1.0 - k) * (1.0 - k)


static func ease_in(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k


static func ease_io(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


## 0 -> 1 -> 0 over k.
static func pulse(k: float) -> float:
	return sin(clampf(k, 0.0, 1.0) * PI)


## 1 until `from`, then fading linearly to 0 at k = 1.
static func tail(k: float, from: float) -> float:
	if k < from:
		return 1.0
	return clampf(1.0 - (k - from) / maxf(0.0001, 1.0 - from), 0.0, 1.0)


## k remapped to the window [a, b], clamped to 0..1.
static func win(k: float, a: float, b: float) -> float:
	return clampf((k - a) / maxf(0.0001, b - a), 0.0, 1.0)


## Deterministic pseudo-random 0..1 for particle n (no rng: a replayed reel
## paints the same sparks).
static func h01(n: int) -> float:
	var x := (n * 374761393 + 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	return float(x % 10007) / 10007.0


## A soft glow: stacked circles, faint and wide to bright and small.
static func glow(cv, p: Vector2, r: float, col: Color, layers: int = 3) -> void:
	if r <= 0.2:
		return
	for i in layers:
		var f := 1.0 - float(i) / float(layers)
		cv.draw_circle(p, r * f, ca(col, col.a * (0.22 + 0.5 * (1.0 - f))))


static func ring(cv, p: Vector2, r: float, col: Color, w: float) -> void:
	if r <= 0.5 or col.a <= 0.01:
		return
	cv.draw_arc(p, r, 0.0, TAU, maxi(12, int(r * 0.8)), col, maxf(1.0, w), true)


static func line(cv, a: Vector2, b: Vector2, col: Color, w: float) -> void:
	if col.a <= 0.01 or a.distance_to(b) < 0.5:
		return
	cv.draw_line(a, b, col, maxf(1.0, w), true)


## n rays from p, each `r` long, rotated by rot.
static func star(cv, p: Vector2, r: float, col: Color, n: int = 4, rot: float = 0.0, w: float = 2.0) -> void:
	for i in n:
		var a := rot + TAU * float(i) / float(n)
		line(cv, p, p + Vector2(cos(a), sin(a)) * r, col, w)


## A small four-point sparkle.
static func twinkle(cv, p: Vector2, r: float, col: Color) -> void:
	if r < 0.8:
		return
	var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r * 0.25, -r * 0.25), p + Vector2(r, 0),
		p + Vector2(r * 0.25, r * 0.25), p + Vector2(0, r), p + Vector2(-r * 0.25, r * 0.25),
		p + Vector2(-r, 0), p + Vector2(-r * 0.25, -r * 0.25)])
	cv.draw_colored_polygon(pts, col)


## A leaf: pointed ellipse at p, pointing along `ang`.
static func leaf(cv, p: Vector2, ang: float, size: float, col: Color) -> void:
	if size < 1.0:
		return
	var f := Vector2(cos(ang), sin(ang))
	var s := Vector2(-f.y, f.x)
	var pts := PackedVector2Array()
	for i in 9:
		var u := float(i) / 8.0
		pts.append(p + f * size * (u - 0.5) + s * size * 0.32 * sin(u * PI))
	for i in range(1, 8):
		var u := 1.0 - float(i) / 8.0
		pts.append(p + f * size * (u - 0.5) - s * size * 0.32 * sin(u * PI))
	cv.draw_colored_polygon(pts, col)


## A filled triangle; skipped when degenerate (triangulation would fail).
static func tri(cv, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	if absf((b - a).cross(c - a)) < 1.0 or col.a <= 0.01:
		return
	cv.draw_colored_polygon(PackedVector2Array([a, b, c]), col)


## A spike rising from `base` to `tip`, `w` wide at the base.
static func spike(cv, base: Vector2, tip: Vector2, w: float, col: Color) -> void:
	var d := (tip - base)
	if d.length() < 1.0:
		return
	var s := Vector2(-d.y, d.x).normalized() * w * 0.5
	tri(cv, base - s, base + s, tip, col)


## A wavy line a -> b: `amp` px, `waves` periods, phase in radians.
static func wavy(cv, a: Vector2, b: Vector2, amp: float, waves: float, phase: float, col: Color, w: float, n: int = 18) -> void:
	if a.distance_to(b) < 1.0 or col.a <= 0.01:
		return
	var d := b - a
	var s := Vector2(-d.y, d.x).normalized()
	var pts := PackedVector2Array()
	for i in n + 1:
		var u := float(i) / float(n)
		# the wave pinches to nothing at both ends
		pts.append(a + d * u + s * amp * sin(u * waves * TAU + phase) * sin(u * PI))
	cv.draw_polyline(pts, col, maxf(1.0, w), true)


## The manhattan diamond of radius r tiles around tile `c`, in pixels (its
## outer edge sits half a tile beyond the last ring's centres).
static func diamond(V: Dictionary, c: Vector2, r: float) -> PackedVector2Array:
	var p := px(V, c)
	var e := (r + 0.5) * ts(V)
	return PackedVector2Array([p + Vector2(0, -e), p + Vector2(e, 0), p + Vector2(0, e), p + Vector2(-e, 0)])


static func tile_rect(V: Dictionary, p) -> Rect2:
	var q := Vector2(p)
	var t := ts(V)
	return Rect2(float(V["ox"]) + q.x * t, float(V["oy"]) + q.y * t, t, t)


## A parabolic lob a -> b at u (0..1), `h` px high at the apex.
static func arc_point(a: Vector2, b: Vector2, u: float, h: float) -> Vector2:
	return a.lerp(b, u) + Vector2(0, -h * 4.0 * u * (1.0 - u))


## Centered text with a drop shadow.
static func text(cv, V: Dictionary, p: Vector2, s: String, col: Color, size: int) -> void:
	var font = V.get("font")
	if font == null or s == "" or col.a <= 0.01:
		return
	var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	cv.draw_string(font, Vector2(p.x - w / 2.0 + 1, p.y + 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, col.a * 0.8))
	cv.draw_string(font, Vector2(p.x - w / 2.0, p.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
