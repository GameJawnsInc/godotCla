extends RefCounted
## Verb family: AREAS - effects that fill a manhattan diamond. The diamond IS
## the rule, so every verb here lights the exact floor tiles it covered, ring
## by ring, on the ground under the creatures (the "area" wash), and closes the
## area's outline once its front arrives; the verb's own motion rides on top.
##   aoe_damage      a nova rolls out ring by ring, dressed by the ability's
##                   element: a sunfire corona with rays (ignite / fire - a
##                   longer ignite_ttl leaves deep embers), a geyser column
##                   raining down (water), a violet spore burst (mobility),
##                   refracted rainbow light (sun without fire)
##   aoe_status      a cloud billows tile by tile - sparkling pollen dust
##                   (stun), drifting violet puffs (spore); LOBBED first when
##                   it is centred on a target tile
##   wash_all        a tide surges out four ways, washing and shoving
##   push_all        a ground-shock ring thumps the four neighbours back
##   clear_smoke     a whirlwind spirals out and lifts the smoke away
##   convert_radius  a wave of life rewrites filth into the effect's kind
##                   (green growth, or brown bark stakes for a blocking kind)
##   grow_radius     a seed is lobbed, roots spread and sprouts pop ring by ring
## Rings arrive in order: a tile at manhattan distance d from the centre is
## reached at t + lead + d * RING_MS, and so is everything that happens on it.
## Flavour comes from data only - the op, the effect's numbers and keys, the
## ability's tags and palette, status ids and terrain kinds.

const Content := preload("res://sim/content.gd")
const L := preload("res://shell/anim_lib.gd")
const D := preload("res://shell/anim_draw.gd")
const FxLines := preload("res://shell/fx_lines.gd")

const OPS := ["aoe_damage", "aoe_status", "wash_all", "push_all", "clear_smoke", "convert_radius", "grow_radius"]
const KINDS := ["area", "nova", "ember", "cloud", "dust", "tide", "shock", "swirl", "smoke_lift",
	"rewrite", "seed_lob", "roots_net", "sprout"]

const RING_MS := 75     # per ring the front advances
const LOB_MS := 260     # a thrown seed / pod / sap bead in flight
const HOLD_MS := 330    # the covered tiles stay lit this long after the last ring
## A nova's anticipation before ring 0, per look.
const NOVA_LEAD := {"sunfire": 110, "geyser": 170, "spores": 90, "prism": 120, "plain": 80}
## A thrown seed's body (the sprout on it takes the ability's palette).
const SEED_COL := Color("d9b36a")
const DIRT_COL := Color("6b4f33")


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


# --- shared building blocks --------------------------------------------------------

## The floor tiles of the diamond (walls carry nothing), nearest ring first,
## as [tile, ring].
static func _cover(snap: Dictionary, center: Vector2i, r: int) -> Array:
	var out: Array = []
	for p in L.diamond(center, maxi(0, r)):
		if not L.wall(snap, p):
			out.append([p, L.man(p, center)])
	return out


## The coverage wash on the ground layer: each tile flashes as its ring is
## reached and stays faintly lit; the outline of the whole covered set draws
## itself as the front reaches each outer edge.
static func _area(c: Dictionary, center: Vector2i, tiles: Array, t0: int, lead: int, rms: int,
		fill: Color, rim: Color, hold: int, alpha: float = 1.0, rainbow: bool = false) -> void:
	if tiles.is_empty():
		return
	var cover := {}
	var maxd := 0
	for tp in tiles:
		cover[tp[0]] = true
		maxd = maxi(maxd, int(tp[1]))
	var edges: Array = []
	for tp in tiles:
		var p: Vector2i = tp[0]
		for d in L.DIRS:
			if cover.has(p + d):
				continue
			var n := Vector2(d)
			var s := Vector2(-n.y, n.x)
			var mid := Vector2(p) + n * 0.5
			edges.append([mid - s * 0.5, mid + s * 0.5, int(tp[1])])
	L.clip(c, {"kind": "area", "t0": t0, "dur": lead + maxd * rms + hold, "at": center, "tiles": tiles,
		"edges": edges, "lead": lead, "ring_ms": rms, "col": fill, "rim": rim, "alpha": alpha,
		"rainbow": rainbow, "layer": "ground"})


## The wall tiles within manhattan `r` of `center` (a front clips at them).
static func _walls_near(snap: Dictionary, center: Vector2i, r: int) -> Dictionary:
	var out := {}
	for p in L.diamond(center, r):
		if L.wall(snap, p):
			out[p] = true
	return out


## Claim every event of the cast on a tile within `r` of `center` at the time
## the ring reaches it (t is when ring 0 is reached); hits recoil away from
## the centre. Returns the claimed indices.
static func _claim_rings(c: Dictionary, center: Vector2i, r: int, t: int, types: Array, rms: int = RING_MS) -> Array:
	var evs: Array = c["events"]
	var aid := String(c["aid"])
	var out: Array = []
	for i in L.unclaimed(c, types):
		var ev: Dictionary = evs[i]
		var tile = null
		var tt0 := String(ev["t"])
		if tt0 == "damage":
			if String(ev.get("who", "")) == "player" or String(ev.get("src", "")) != aid:
				continue
			var e = c["pre_en"].get(ev.get("id"))
			if e != null:
				tile = e["pos"]
		elif tt0 == "status" or tt0 == "resisted" or tt0 == "immune":
			var e2 = c["pre_en"].get(ev.get("id"))
			if e2 != null:
				tile = e2["pos"]
		else:
			tile = ev.get("tile")
		if not (tile is Vector2i) or L.man(tile, center) > r:
			continue
		var tt := t + L.man(tile, center) * rms
		L.claim(c, i, tt + (15 if tt0 == "damage" else 0), L.dir_of(center, tile))
		if ev.get("tile") is Vector2i:
			L.reveal(c, ev["tile"], tt)
		out.append(i)
	return out


## The step carried a verdant surge (the cast drank the growth underfoot).
static func _surged(c: Dictionary) -> bool:
	for ev in c["events"]:
		if String(ev.get("t", "")) == "surge":
			return true
	return false


## The effect's own `if` rider visibly failed: a `dim` predicate that the
## post-step stage does not meet (the sim skipped the effect).
static func _gated_off(c: Dictionary) -> bool:
	for pred in c["eff"].get("if", []):
		if pred is Dictionary and pred.has("dim") and c["post"].has("dim") \
				and int(c["post"]["dim"]) != int(pred["dim"]):
			return true
	return false


## An enemy an earlier effect of this cast already killed (its killing blow is
## claimed): a later push must not shove its ghost.
static func _died_already(c: Dictionary, id) -> bool:
	var evs: Array = c["events"]
	for i in range(1, evs.size()):
		if String(evs[i].get("t", "")) == "death" and evs[i].get("id") == id and L.claimed(c, i - 1):
			return true
	return false


# --- builders -----------------------------------------------------------------------

## A nova's look, from the ability's data: ignite or a fire tag is sunfire;
## otherwise the first element tag decides.
static func _nova_style(c: Dictionary) -> String:
	var tags: Array = c["adef"].get("tags", [])
	if bool(c["eff"].get("ignite", false)) or tags.has("fire"):
		return "sunfire"
	for el in L.ELEMENT_ORDER:
		if tags.has(el):
			match el:
				"sun":
					return "prism"
				"water":
					return "geyser"
				"mobility":
					return "spores"
			return "plain"
	return "plain"


static func _nova(c: Dictionary) -> int:
	var t: int = c["t"]
	var eff: Dictionary = c["eff"]
	var center: Vector2i = c["ppos"]
	var r := int(eff.get("radius", 1))
	var dmg := int(eff.get("dmg", 1))
	var style := _nova_style(c)
	var pal: Dictionary = c["pal"]
	if _gated_off(c):
		# the rider's condition failed: a glint, and nothing rolls out
		L.clip(c, {"kind": "nova", "t0": t, "dur": 320, "at": center, "r": 0, "style": style,
			"lead": 160, "ring_ms": RING_MS, "dmg": dmg, "fizzle": true})
		return t + 180
	var lead: int = int(NOVA_LEAD.get(style, 80))
	var t0 := t + lead
	var tiles := _cover(c["pre"], center, r)
	# a longer burn (ignite_ttl) glows deeper: redder tiles, longer tongues,
	# and embers left smouldering where it caught
	var ttl := int(eff.get("ignite_ttl", -1))
	var deep := ttl > 0 and bool(eff.get("ignite", false))
	_area(c, center, tiles, t, lead, RING_MS, pal["c"] if deep else pal["a"], pal["b"], HOLD_MS,
		0.8 if style == "spores" else 0.9, style == "prism")
	var tail := 380 if style == "geyser" else 300
	L.clip(c, {"kind": "nova", "t0": t, "dur": lead + r * RING_MS + tail, "at": center, "r": r,
		"style": style, "lead": lead, "ring_ms": RING_MS, "dmg": dmg, "tiles": tiles,
		"ignite": bool(eff.get("ignite", false)), "deep": deep, "verdant": _surged(c),
		"walls": _walls_near(c["pre"], center, r + 2)})
	var ign := L.unclaimed(c, ["ignite"])
	_claim_rings(c, center, r, t0, ["damage", "ignite", "hook"])
	if ttl > 0:
		for i in ign:
			if L.claimed(c, i) and c["events"][i].get("tile") is Vector2i:
				L.clip(c, {"kind": "ember", "t0": int(c["times"][i]), "dur": 380 + ttl * 110,
					"at": c["events"][i]["tile"], "ttl": ttl, "layer": "ground"})
	c["reel"]["shakes"].append({"t0": t0, "mag": 1.0 + 0.6 * float(r) + 0.4 * float(dmg)})
	return t0 + r * RING_MS + (90 if style == "geyser" else 110)


static func _cloud(c: Dictionary) -> int:
	var t: int = c["t"]
	var eff: Dictionary = c["eff"]
	var r := int(eff.get("radius", 1))
	var center: Vector2i = c["ppos"]
	if String(eff.get("center", "self")) == "target" and c.get("target") is Vector2i:
		center = c["target"]
	var status := String(eff.get("status", ""))
	var col := L.status_col(status)
	var turns := maxi(1, int(eff.get("turns", 1)))
	var t_land := t
	if center != c["ppos"]:
		L.clip(c, {"kind": "seed_lob", "t0": t, "dur": LOB_MS, "from": c["ppos"], "to": center,
			"col": col, "style": "pod", "at": center})
		t_land = t + LOB_MS
	var lead := 60
	var tiles := _cover(c["pre"], center, r)
	var hold := 360 + 90 * turns
	_area(c, center, tiles, t_land, lead, RING_MS, col, col.lightened(0.35), hold - 60, 0.75)
	var cl := {"t0": t_land, "dur": lead + r * RING_MS + hold, "at": center, "tiles": tiles,
		"status": status, "turns": turns, "lead": lead, "ring_ms": RING_MS, "col": col}
	var ground := cl.duplicate()
	ground["kind"] = "cloud"
	ground["layer"] = "ground"
	L.clip(c, ground)
	var air := cl.duplicate()
	air["kind"] = "dust"
	L.clip(c, air)
	_claim_rings(c, center, r, t_land + lead, ["status", "resisted", "immune"])
	return t_land + lead + r * RING_MS + 160


static func _tide(c: Dictionary) -> int:
	var t: int = c["t"]
	var o: Vector2i = c["ppos"]
	var pal: Dictionary = c["pal"]
	var rng := int(c["adef"].get("range", 2))
	var push := int(c["eff"].get("push", 1))
	var lead := 60
	var tiles: Array = [[o, 0]]
	var lens: Array = []
	for d in L.DIRS:
		var line := L.line(c["pre"], o, d, rng, false, false)
		lens.append(line.size())
		for j in line.size():
			tiles.append([line[j], j + 1])
	_area(c, o, tiles, t, lead, RING_MS, pal["a"], pal["b"], 300, 0.9)
	var base := {"t0": t, "dur": lead + rng * RING_MS + 420, "at": o, "lens": lens, "r": rng,
		"lead": lead, "ring_ms": RING_MS, "push": push}
	var band := base.duplicate()
	band["kind"] = "tide"
	band["part"] = "band"
	band["layer"] = "ground"
	L.clip(c, band)
	var crest := base.duplicate()
	crest["kind"] = "tide"
	crest["part"] = "crest"
	L.clip(c, crest)
	_claim_rings(c, o, rng, t + lead, ["wash", "hook"])
	var t_end := t + lead + rng * RING_MS + 160
	for d in L.DIRS:
		for p in L.line(c["pre"], o, d, rng, false, false):
			var e = L.enemy_at(c["pre"], p)
			if e != null:
				t_end = maxi(t_end, FxLines.shove(c, e, d, push, t + lead + L.man(o, p) * RING_MS))
				break
	return t_end


static func _shock(c: Dictionary) -> int:
	var t: int = c["t"]
	var o: Vector2i = c["ppos"]
	var pal: Dictionary = c["pal"]
	var dist := int(c["eff"].get("dist", 1))
	var lead := 70
	var t_hit := t + lead
	_area(c, o, _cover(c["pre"], o, 1), t, lead, 45, pal["a"], pal["b"], 240, 0.8)
	L.clip(c, {"kind": "shock", "t0": t, "dur": lead + 480, "at": o, "lead": lead, "dist": dist,
		"layer": "ground"})
	L.seg(c, "player", {"kind": "squash", "t0": t_hit - 30, "dur": 170})
	c["reel"]["shakes"].append({"t0": t_hit, "mag": 2.0 + float(dist)})
	var t_end := t_hit + 200
	for d in L.DIRS:
		var e = L.enemy_at(c["pre"], o + d)
		if e != null and c["pre_en"].has(e["id"]) and not _died_already(c, e["id"]):
			t_end = maxi(t_end, FxLines.shove(c, e, d, dist, t_hit + 45))
	return t_end


static func _swirl(c: Dictionary) -> int:
	var t: int = c["t"]
	var o: Vector2i = c["ppos"]
	var pal: Dictionary = c["pal"]
	var r := int(c["eff"].get("radius", 2))
	var lead := 90
	_area(c, o, _cover(c["pre"], o, r), t, lead, RING_MS, pal["a"], pal["b"], 260, 0.55)
	# on the ground layer: the funnel turns behind the tender, its top above
	# the head, and the streamers pass under the bodies they buffet
	L.clip(c, {"kind": "swirl", "t0": t, "dur": lead + r * RING_MS + 340, "at": o, "r": r,
		"lead": lead, "ring_ms": RING_MS, "layer": "ground"})
	# each smoke tile the wind reaches is lifted away (drawn here, not as a puff)
	var evs: Array = c["events"]
	for i in L.unclaimed(c, ["smoke_cleared"]):
		var p = evs[i].get("tile")
		if not (p is Vector2i) or L.man(p, o) > r:
			continue
		var ta := t + lead + L.man(p, o) * RING_MS
		L.claim(c, i, ta)
		L.quiet(c, i)
		L.reveal(c, p, ta)
		L.clip(c, {"kind": "smoke_lift", "t0": ta, "dur": 600, "at": p, "from": o,
			"col": L.TERRAIN_COL.get("smoke", Color("9aa0a4"))})
	return t + lead + r * RING_MS + 60


static func _convert(c: Dictionary) -> int:
	var t: int = c["t"]
	var eff: Dictionary = c["eff"]
	var center: Vector2i = c["target"] if c.get("target") is Vector2i else c["ppos"]
	var r := int(eff.get("radius", 1))
	var kind := String(eff.get("kind", "growth"))
	var col: Color = L.TERRAIN_COL.get(kind, Color("6cc95c"))
	var blocks := bool(Content.terrain(kind, "blocks", false))
	var t_land := t
	if center != c["ppos"] and c.get("areas_landed") != center:
		L.clip(c, {"kind": "seed_lob", "t0": t, "dur": LOB_MS, "from": c["ppos"], "to": center,
			"col": col, "style": "sap", "at": center})
		t_land = t + LOB_MS
	c["areas_landed"] = center
	var lead := 50
	var tiles := _cover(c["pre"], center, r)
	_area(c, center, tiles, t_land, lead, RING_MS, col, col.lightened(0.45), 320, 0.85)
	var evs: Array = c["events"]
	for i in L.unclaimed(c, ["convert"]):
		var p = evs[i].get("tile")
		if not (p is Vector2i) or L.man(p, center) > r:
			continue
		var ta := t_land + lead + L.man(p, center) * RING_MS
		L.claim(c, i, ta)
		L.quiet(c, i)
		L.reveal(c, p, ta + 110)
		L.clip(c, {"kind": "rewrite", "t0": ta, "dur": 560, "at": p, "col": col, "blocks": blocks,
			"from_col": L.TERRAIN_COL.get(L.tkind(c["pre"], p), Color("3a2e3f")), "layer": "ground"})
	return t_land + lead + r * RING_MS + 160


static func _grow(c: Dictionary) -> int:
	var t: int = c["t"]
	var center: Vector2i = c["target"] if c.get("target") is Vector2i else c["ppos"]
	var r := int(c["eff"].get("radius", 1))
	var pal: Dictionary = c["pal"]
	var t_land := t
	var thrown: bool = center != c["ppos"]
	if thrown:
		L.clip(c, {"kind": "seed_lob", "t0": t, "dur": LOB_MS, "from": c["ppos"], "to": center,
			"col": pal["a"], "style": "seed", "at": center})
		t_land = t + LOB_MS
	c["areas_landed"] = center
	var lead := 40
	var t0 := t_land + lead
	var tiles := _cover(c["pre"], center, r)
	_area(c, center, tiles, t_land, lead, RING_MS, pal["a"], pal["b"], 320, 0.75)
	L.clip(c, {"kind": "roots_net", "t0": t_land, "dur": lead + r * RING_MS + 380, "at": center,
		"tiles": tiles, "lead": lead, "ring_ms": RING_MS, "thrown": thrown, "verdant": _surged(c),
		"layer": "ground"})
	# every bare tile that turned into growth sprouts as its ring is reached
	# (a slick another effect of this cast converts is that effect's to draw)
	var sprouts: Array = []
	var sw: Dictionary = c["reel"]["tswap"]
	for tp in tiles:
		var p: Vector2i = tp[0]
		if sw.has(p) and String(sw[p]["post"]) == "growth" and String(sw[p]["pre"]) == "" and not sw[p].has("t"):
			var tt := t0 + int(tp[1]) * RING_MS
			sprouts.append(p)
			L.reveal(c, p, tt + 60)
			L.clip(c, {"kind": "sprout", "t0": tt, "dur": 480, "at": p, "layer": "ground"})
	for i in L.unclaimed(c, ["growth", "hook"]):
		L.claim(c, i, t0)
	# a tangle's roots take whoever stands on the fresh growth
	for i in L.unclaimed(c, ["status", "resisted", "immune"]):
		var e = c["pre_en"].get(c["events"][i].get("id"))
		if e != null and sprouts.has(e["pos"]):
			L.claim(c, i, t0 + L.man(e["pos"], center) * RING_MS + 130)
	return t0 + r * RING_MS + 200


# --- paint -----------------------------------------------------------------------

static func paint(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	match String(cl["kind"]):
		"area":
			_paint_area(cv, cl, k, V)
		"nova":
			_paint_nova(cv, cl, k, V)
		"ember":
			_paint_ember(cv, cl, k, V)
		"cloud":
			_paint_cloud(cv, cl, k, V)
		"dust":
			_paint_dust(cv, cl, k, V)
		"tide":
			_paint_tide(cv, cl, k, V)
		"shock":
			_paint_shock(cv, cl, k, V)
		"swirl":
			_paint_swirl(cv, cl, k, V)
		"smoke_lift":
			_paint_smoke_lift(cv, cl, k, V)
		"rewrite":
			_paint_rewrite(cv, cl, k, V)
		"seed_lob":
			_paint_lob(cv, cl, k, V)
		"roots_net":
			_paint_roots(cv, cl, k, V)
		"sprout":
			_paint_sprout(cv, cl, k, V)


## A point on the smooth diamond of pixel radius R around c, perimeter
## parameter s (0..1 clockwise from the top corner), and its outward normal.
static func _perim(c: Vector2, R: float, s: float) -> Vector2:
	var s4 := fposmod(s, 1.0) * 4.0
	var side := mini(int(s4), 3)
	return c + _corner(side).lerp(_corner(side + 1), s4 - float(side)) * R


static func _perim_n(s: float) -> Vector2:
	var side := mini(int(fposmod(s, 1.0) * 4.0), 3)
	return (_corner(side) + _corner(side + 1)).normalized()


static func _corner(i: int) -> Vector2:
	match posmod(i, 4):
		0:
			return Vector2(0, -1)
		1:
			return Vector2(1, 0)
		2:
			return Vector2(0, 1)
	return Vector2(-1, 0)


## Pixel distance from the centre to a diamond of pixel radius R along `ang`.
static func _reach(R: float, ang: float) -> float:
	return R / maxf(0.001, absf(cos(ang)) + absf(sin(ang)))


## The tile a pixel lies on.
static func _tile_of(V: Dictionary, q: Vector2) -> Vector2i:
	var ts := D.ts(V)
	return Vector2i(int(floor((q.x - float(V["ox"])) / ts)), int(floor((q.y - float(V["oy"])) / ts)))


static func _in_rock(V: Dictionary, walls: Dictionary, q: Vector2) -> bool:
	return not walls.is_empty() and walls.has(_tile_of(V, q))


## The smooth diamond front of pixel radius R as runs of points, broken
## wherever it crosses a wall tile: the area never reaches into the rock, so
## neither does its light.
static func _front_runs(V: Dictionary, c: Vector2, R: float, walls: Dictionary) -> Array:
	var runs: Array = []
	if R < 1.0:
		return runs
	var n := 4 * clampi(int(ceil(R / D.ts(V) * 2.0)), 2, 12)
	var cur := PackedVector2Array()
	var prev := _perim(c, R, 0.0)
	for i in range(1, n + 1):
		var nxt := _perim(c, R, float(i) / float(n)) if i < n else _perim(c, R, 0.0)
		if _in_rock(V, walls, (prev + nxt) * 0.5):
			if cur.size() >= 2:
				runs.append(cur)
			cur = PackedVector2Array()
		else:
			if cur.is_empty():
				cur.append(prev)
			cur.append(nxt)
		prev = nxt
	if cur.size() >= 2:
		runs.append(cur)
	return runs


static func _runs_line(cv, runs: Array, col: Color, w: float) -> void:
	if col.a <= 0.01:
		return
	for run in runs:
		cv.draw_polyline(run, col, maxf(1.0, w), true)


static func _paint_area(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var dur := float(cl["dur"])
	var ms := k * dur
	var lead := float(cl["lead"])
	var rms := float(cl["ring_ms"])
	var col: Color = cl["col"]
	var rim: Color = cl["rim"]
	var al := float(cl.get("alpha", 1.0))
	var fade := clampf((dur - ms) / 240.0, 0.0, 1.0)
	var rainbow := bool(cl.get("rainbow", false))
	var ctr := Vector2(cl["at"])
	var ins := t * 0.06
	for tp in cl["tiles"]:
		var u := ms - (lead + float(tp[1]) * rms)
		if u < 0.0:
			continue
		var p: Vector2i = tp[0]
		var fc := col
		if rainbow:
			var dv := Vector2(p) - ctr
			fc = Color.from_hsv(fposmod(dv.angle() / TAU + ms * 0.0006, 1.0), 0.55, 1.0)
		var fl := 1.0 - D.ease_out(D.win(u, 0.0, 240.0))
		var rr := D.tile_rect(V, p).grow(-ins)
		cv.draw_rect(rr, D.ca(fc, al * (0.13 + 0.37 * fl) * fade))
		if fl > 0.02:
			cv.draw_rect(rr, D.ca(rim, al * 0.95 * fl * fade), false, maxf(1.0, t * 0.05))
	for e in cl["edges"]:
		var u2 := ms - (lead + float(e[2]) * rms)
		if u2 < 0.0:
			continue
		D.line(cv, D.px(V, e[0]), D.px(V, e[1]), D.ca(rim, al * 0.85 * D.win(u2, 0.0, 70.0) * fade), t * 0.06)


static func _paint_nova(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var dur := float(cl["dur"])
	var ms := k * dur
	var lead := float(cl["lead"])
	var rms := float(cl["ring_ms"])
	var r := float(cl["r"])
	var c := D.px(V, cl["at"])
	var dmg := float(cl.get("dmg", 1))
	var style := String(cl.get("style", "plain"))
	if bool(cl.get("fizzle", false)):
		# a glint that goes nowhere: the condition was not met
		var q := c + Vector2(0, -t * 0.55)
		var a0 := D.pulse(k)
		D.glow(cv, q, t * 0.3 * a0, D.ca(pal["b"], 0.5))
		D.twinkle(cv, q, t * 0.2 * a0, D.ca(pal["b"], a0))
		cv.draw_circle(q + Vector2(0, -t * 0.3 * k), t * (0.08 + 0.12 * k), Color(0.6, 0.62, 0.62, 0.5 * (1.0 - k)))
		return
	var g := D.win(ms, 0.0, lead)
	var f := clampf((ms - lead) / rms, 0.0, r)
	var t_full := lead + r * rms
	# the front: rolls out ring by ring, then pushes a little past the last
	# ring and dies fast, leaving the tiles and their outline to say what it
	# covered; the lingering parts (the sun overhead, drifting spores) fade on
	# `out`
	var po := D.win(ms, t_full, t_full + 170.0)
	var R := (f + 0.5 + 0.45 * D.ease_out(po)) * t
	var lf := 1.0 - po
	var out := D.win(ms, t_full + 30.0, dur)
	var walls: Dictionary = cl.get("walls", {})
	var runs: Array = _front_runs(V, c, R, walls) if ms >= lead and lf > 0.0 else []
	match style:
		"sunfire":
			_nova_sun(cv, cl, V, walls, runs, c, t, pal, ms, lead, R, lf, g, out, dmg)
		"geyser":
			_nova_geyser(cv, cl, V, c, t, pal, ms, lead, rms, t_full, g, dmg)
		"spores":
			_nova_spores(cv, cl, V, walls, runs, c, t, pal, ms, lead, R, lf, g, out, dmg)
		"prism":
			_nova_prism(cv, V, walls, c, t, ms, lead, R, lf, g, out, dmg)
		_:
			_nova_plain(cv, runs, c, t, pal, ms, lead, lf)
	if bool(cl.get("verdant", false)) and ms >= lead and lf > 0.0:
		# the surge rides the front: leaves wheel out on it
		for i in 12:
			var s := (float(i) + 0.3) / 12.0 + ms * 0.00012
			var n := _perim_n(s)
			if _in_rock(V, walls, _perim(c, R, s)):
				continue
			D.leaf(cv, _perim(c, R, s) + n * t * 0.16, n.angle() + sin(ms * 0.02 + float(i)) * 0.5,
				t * 0.34, D.ca(Color("2f6b2c"), 0.9 * lf))
			D.leaf(cv, _perim(c, R, s) + n * t * 0.16, n.angle() + sin(ms * 0.02 + float(i)) * 0.5,
				t * 0.26, D.ca(Color("8fdc6a"), lf))


## Sunfire: the sun gathers over the tender's head, bursts, and a corona of
## flame tongues rolls out on the diamond with rays behind it. More damage
## means longer tongues and heavier rays; a longer burn (ignite_ttl) burns
## a deeper red.
static func _nova_sun(cv, cl: Dictionary, V: Dictionary, walls: Dictionary, runs: Array, c: Vector2, t: float, pal: Dictionary, ms: float,
		lead: float, R: float, lf: float, g: float, out: float, dmg: float) -> void:
	var sun := c + Vector2(0, -t * 0.55)
	var deep := bool(cl.get("deep", false))
	var hot: Color = pal["c"].darkened(0.3) if deep else pal["c"]
	if ms < lead:
		var ge := D.ease_in(g)
		D.glow(cv, sun, t * (0.2 + 0.4 * ge), D.ca(pal["a"], 0.6))
		cv.draw_circle(sun, t * (0.07 + 0.14 * ge), D.ca(pal["b"], 0.95))
		for i in 8:
			var ang := TAU * float(i) / 8.0 + ms * 0.008
			var dv := Vector2(cos(ang), sin(ang))
			var r0 := t * (1.0 - 0.72 * ge)
			D.line(cv, sun + dv * r0, sun + dv * (r0 + t * 0.26), D.ca(pal["a"], 0.5 + 0.5 * g), t * 0.07)
			D.line(cv, sun + dv * r0, sun + dv * (r0 + t * 0.26), D.ca(pal["b"], 0.5 + 0.5 * g), t * 0.03)
		return
	var burst := 1.0 - D.win(ms, lead, lead + 160.0)
	var live := 1.0 - out
	# the flash of the burst, then the sun overhead cools
	if burst > 0.0:
		D.glow(cv, c, t * (0.5 + 0.6 * (1.0 - burst)), D.ca(pal["b"], 0.6 * burst))
	D.glow(cv, sun, t * 0.34 * live, D.ca(pal["a"], 0.6))
	cv.draw_circle(sun, t * 0.17 * live, D.ca(pal["b"], live))
	D.star(cv, sun, t * 0.38 * live, D.ca(pal["b"], 0.8 * live), 8, ms * 0.004, t * 0.035)
	if lf <= 0.0:
		return
	# rays race out to the corona
	var nr := 8 + 2 * int(dmg)
	for i in nr:
		var ang := TAU * (float(i) + 0.5) / float(nr) + ms * 0.0007
		var dv := Vector2(cos(ang), sin(ang))
		var reach := _reach(R, ang) - t * 0.1
		if reach > t * 0.5 and not _in_rock(V, walls, c + dv * reach):
			D.line(cv, c + dv * t * 0.45, c + dv * reach, D.ca(pal["b"], 0.55 * lf), t * (0.025 + 0.02 * dmg))
	# the corona: a burning diamond front with flame tongues licking outward
	_runs_line(cv, runs, D.ca(hot, 0.6 * lf), t * 0.3)
	_runs_line(cv, runs, D.ca(pal["a"], 0.95 * lf), t * 0.14)
	_runs_line(cv, runs, D.ca(pal["b"], lf), t * 0.05)
	var nt := 12 + 4 * int(cl["r"])
	for i in nt:
		var s := (float(i) + 0.5) / float(nt) + ms * 0.00005
		var fl := 0.6 + 0.4 * sin(ms * 0.03 + float(i) * 2.1)
		var base := _perim(c, R, s)
		if _in_rock(V, walls, base):
			continue
		var tip := base + _perim_n(s) * t * (0.16 + 0.08 * dmg + (0.08 if deep else 0.0)) * fl
		D.spike(cv, base, tip, t * 0.17, D.ca(hot if i % 2 == 0 else pal["a"], 0.95 * lf))
	if bool(cl.get("ignite", false)) and R > t:
		# embers thrown off the front
		for i in 6:
			var s2 := D.h01(i * 5 + 3)
			var q := _perim(c, R, s2) + _perim_n(s2) * t * (0.2 + 0.3 * D.h01(i * 7 + 1))
			if _in_rock(V, walls, q):
				continue
			cv.draw_circle(q, t * 0.045, D.ca(pal["b"], 0.9 * lf))


## Water: ripples draw in at the feet, a column bursts up, and its spray rains
## down onto every covered tile ring by ring, splashing as it lands.
static func _nova_geyser(cv, cl: Dictionary, V: Dictionary, c: Vector2, t: float, pal: Dictionary, ms: float,
		lead: float, rms: float, t_full: float, g: float, dmg: float) -> void:
	var feet := c + Vector2(0, t * 0.3)
	var rise := D.ease_out(D.win(ms, lead * 0.35, lead))
	var fall := D.ease_in(D.win(ms, t_full + 50.0, t_full + 280.0))
	# anticipation: rings drawing in on the ground
	if ms < lead:
		cv.draw_set_transform(feet, 0.0, Vector2(1.0, 0.45))
		for j in 2:
			var rr := t * (0.9 - 0.6 * D.win(ms, float(j) * 40.0, lead))
			D.ring(cv, Vector2.ZERO, rr, D.ca(pal["b"], 0.35 + 0.4 * g), t * 0.06)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var top_full := feet + Vector2(0, -t * (1.75 + 0.15 * dmg))
	var h := t * (1.75 + 0.15 * dmg) * rise * (1.0 - fall)
	if h > 2.0:
		var w := t * (0.19 + 0.04 * dmg)
		var wob := sin(ms * 0.045) * t * 0.03
		var top := feet + Vector2(wob, -h)
		cv.draw_colored_polygon(PackedVector2Array([feet + Vector2(-w * 1.5, 0), top + Vector2(-w, 0),
			top + Vector2(w, 0), feet + Vector2(w * 1.5, 0)]), D.ca(pal["c"], 0.5))
		cv.draw_colored_polygon(PackedVector2Array([feet + Vector2(-w * 1.15, 0), top + Vector2(-w * 0.7, 0),
			top + Vector2(w * 0.7, 0), feet + Vector2(w * 1.15, 0)]), D.ca(pal["a"], 0.7))
		D.line(cv, feet, top, D.ca(pal["b"], 0.9), w * 0.5)
		for j in 5:
			var ang := PI + PI * float(j) / 4.0 + sin(ms * 0.02 + float(j)) * 0.2
			cv.draw_circle(top + Vector2(cos(ang) * w * 1.1, sin(ang) * w * 0.7), w * (0.5 + 0.12 * float(j % 2)),
				D.ca(pal["b"], 0.85))
	# the foot of the column
	var fo := D.win(ms, lead * 0.35, t_full + 280.0)
	if fo > 0.0 and fo < 1.0:
		cv.draw_set_transform(feet, 0.0, Vector2(1.0, 0.45))
		D.ring(cv, Vector2.ZERO, t * (0.3 + 0.35 * fo), D.ca(pal["b"], 0.8 * (1.0 - fo)), t * 0.08)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the rain: drops arc off the crown and land ring by ring
	var tiles: Array = cl.get("tiles", [])
	var per := 2 if tiles.size() <= 9 else 1
	for tp in tiles:
		var d := int(tp[1])
		if d < 1:
			continue
		var land_t := lead + float(d) * rms
		var launch_t := lead - 40.0
		var p: Vector2i = tp[0]
		for j in per:
			var n := p.x * 31 + p.y * 17 + j * 7
			var dst := D.px(V, p) + Vector2(D.h01(n) - 0.5, D.h01(n + 1) - 0.5) * t * 0.4
			var u := (ms - launch_t) / maxf(1.0, land_t - launch_t)
			if u > 0.0 and u < 1.0:
				var q := D.arc_point(top_full, dst, D.ease_in(u), t * 0.35)
				var q0 := D.arc_point(top_full, dst, D.ease_in(maxf(0.0, u - 0.12)), t * 0.35)
				D.line(cv, q0, q, D.ca(pal["a"], 0.8), t * 0.07)
				cv.draw_circle(q, t * 0.075, D.ca(pal["b"], 0.95))
			elif u >= 1.0:
				var s := (ms - land_t) / 240.0
				if s < 1.0:
					cv.draw_set_transform(dst + Vector2(0, t * 0.15), 0.0, Vector2(1.0, 0.45))
					D.ring(cv, Vector2.ZERO, t * (0.12 + 0.3 * D.ease_out(s)), D.ca(pal["b"], 0.95 * (1.0 - s)), t * 0.06)
					cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
					for m in 2:
						var sa := -PI * (0.3 + 0.4 * float(m))
						cv.draw_circle(dst + Vector2(cos(sa), sin(sa)) * t * 0.3 * s + Vector2(0, t * 0.4 * s * s),
							t * 0.045, D.ca(pal["b"], 1.0 - s))


## Mobility: spores condense, then burst out to the diamond's edge in every
## direction and drift up as they settle.
static func _nova_spores(cv, cl: Dictionary, V: Dictionary, walls: Dictionary, runs: Array, c: Vector2, t: float, pal: Dictionary, ms: float,
		lead: float, R: float, lf: float, g: float, out: float, dmg: float) -> void:
	if ms < lead:
		for i in 7:
			var ang := TAU * float(i) / 7.0 - ms * 0.012
			var rr := t * (0.9 * (1.0 - D.ease_in(g)) + 0.1)
			cv.draw_circle(c + Vector2(cos(ang), sin(ang)) * rr, t * 0.08, D.ca(pal["c"], 0.5 + 0.5 * g))
			cv.draw_circle(c + Vector2(cos(ang), sin(ang)) * rr, t * 0.055, D.ca(pal["a"], 0.5 + 0.5 * g))
		D.glow(cv, c, t * 0.35 * g, D.ca(pal["b"], 0.5))
		return
	var live := 1.0 - out
	var pop := 1.0 - D.win(ms, lead, lead + 200.0)
	if pop > 0.0:
		D.glow(cv, c, t * (0.35 + 0.45 * (1.0 - pop)), D.ca(pal["a"], 0.6 * pop))
	_runs_line(cv, runs, D.ca(pal["c"], 0.5 * lf), t * 0.16)
	_runs_line(cv, runs, D.ca(pal["b"], 0.8 * lf), t * 0.05)
	var n := 16 + 4 * int(cl["r"])
	var reach_r := R - t * 0.12
	for i in n:
		var ang := TAU * (float(i) + D.h01(i * 3 + 1)) / float(n)
		var dv := Vector2(cos(ang), sin(ang))
		var reach := _reach(reach_r, ang) * (0.72 + 0.28 * D.h01(i * 5 + 2))
		var q := c + dv * reach + Vector2(sin(ms * 0.01 + float(i)) * t * 0.04, -t * 0.35 * out)
		if _in_rock(V, walls, c + dv * reach):
			continue
		var sz := t * (0.07 + 0.03 * dmg) * (0.7 + 0.5 * D.h01(i * 11))
		cv.draw_circle(q, sz * 1.4, D.ca(pal["c"], 0.7 * live))
		cv.draw_circle(q, sz, D.ca(pal["a"], live))
		cv.draw_circle(q + Vector2(-sz * 0.3, -sz * 0.3), sz * 0.4, D.ca(pal["b"], live))


## Sun without fire: a prism glints over the tender and splits the light into
## a rainbow that fans out to the diamond, its front shifting hue.
static func _nova_prism(cv, V: Dictionary, walls: Dictionary, c: Vector2, t: float, ms: float, lead: float, R: float, lf: float, g: float,
		out: float, dmg: float) -> void:
	var q := c + Vector2(0, -t * 0.6)
	var live := 1.0 - out
	var spin := absf(cos(ms * 0.012))
	var cw := t * (0.07 + 0.13 * spin)
	var ch := t * 0.26
	var show := minf(1.0, g * 2.0) * live
	# the light shaft falling into the crystal, then the crystal itself
	if ms < lead + 120.0:
		var sh := 1.0 - D.win(ms, lead, lead + 120.0)
		D.line(cv, q + Vector2(0, -t * 1.4), q, D.ca(Color(1, 1, 0.95), 0.7 * g * sh), t * 0.12)
	cv.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -ch * 1.12), q + Vector2(cw * 1.2, 0),
		q + Vector2(0, ch * 1.12), q + Vector2(-cw * 1.2, 0)]), D.ca(Color(0.35, 0.45, 0.6), 0.8 * show))
	cv.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -ch), q + Vector2(cw, 0), q + Vector2(0, ch),
		q + Vector2(-cw, 0)]), D.ca(Color(0.92, 0.97, 1.0), 0.95 * show))
	D.twinkle(cv, q + Vector2(t * 0.1, -t * 0.12), t * 0.16 * (0.6 + 0.4 * sin(ms * 0.02)), D.ca(Color.WHITE, show))
	if ms < lead or lf <= 0.0:
		return
	for i in 7:
		var ang := -PI * 0.5 + TAU * (float(i) + 0.5) / 7.0 + ms * 0.0012
		var dv := Vector2(cos(ang), sin(ang))
		var col := Color.from_hsv(float(i) / 7.0, 0.65, 1.0)
		var reach := _reach(R, ang)
		D.line(cv, q + dv * t * 0.15, c + dv * reach, D.ca(col, 0.3 * lf), t * (0.16 + 0.03 * dmg))
		D.line(cv, q + dv * t * 0.15, c + dv * reach, D.ca(col, 0.9 * lf), t * 0.05)
	# the front in shifting spectrum
	var seg := 16
	for i in seg:
		var s0 := float(i) / float(seg)
		var s1 := float(i + 1) / float(seg)
		var col2 := Color.from_hsv(fposmod(s0 + ms * 0.0008, 1.0), 0.6, 1.0)
		var pa := _perim(c, R, s0)
		var pb := _perim(c, R, s1 - 0.0001)
		if not _in_rock(V, walls, (pa + pb) * 0.5):
			D.line(cv, pa, pb, D.ca(col2, 0.95 * lf), t * 0.09)
	for i in 4:
		if not _in_rock(V, walls, c + _corner(i) * R):
			D.twinkle(cv, c + _corner(i) * R, t * 0.16 * lf, D.ca(Color.WHITE, lf))


static func _nova_plain(cv, runs: Array, c: Vector2, t: float, pal: Dictionary, ms: float, lead: float, lf: float) -> void:
	if ms < lead:
		D.glow(cv, c, t * 0.4 * D.win(ms, 0.0, lead), D.ca(pal["b"], 0.5))
		return
	_runs_line(cv, runs, D.ca(pal["c"], 0.5 * lf), t * 0.22)
	_runs_line(cv, runs, D.ca(pal["b"], lf), t * 0.07)


## A long burn: the tile smoulders - a bed of deep red coals under the flame,
## throbbing, with embers climbing off it. Longer ttl, hotter bed.
static func _paint_ember(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var c := D.px(V, cl["at"])
	var ms := k * float(cl["dur"])
	var heat := minf(1.0, float(cl.get("ttl", 2)) / 4.0)
	var a := D.win(k, 0.0, 0.08) * D.tail(k, 0.6)
	var throb := 0.85 + 0.15 * sin(ms * 0.02)
	D.glow(cv, c + Vector2(0, t * 0.1), t * (0.55 + 0.1 * heat) * throb, D.ca(Color("c0301a"), (0.5 + 0.3 * heat) * a), 3)
	cv.draw_set_transform(c + Vector2(0, t * 0.28), 0.0, Vector2(1.0, 0.42))
	cv.draw_circle(Vector2.ZERO, t * 0.44, D.ca(Color("4a1006"), 0.8 * a))
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in 6:
		# coals glowing and dimming on their own beat
		var ang := TAU * D.h01(i * 17 + 3)
		var rr := t * 0.34 * sqrt(D.h01(i * 29 + 11))
		var q0 := c + Vector2(0, t * 0.28) + Vector2(cos(ang) * rr, sin(ang) * rr * 0.42)
		var gl := 0.55 + 0.45 * sin(ms * 0.012 + float(i) * 1.9)
		cv.draw_circle(q0, t * 0.075, D.ca(Color("ff6a1a"), a * (0.6 + 0.4 * gl)))
		cv.draw_circle(q0, t * 0.04, D.ca(Color("ffe08a"), a * gl))
	for i in 7:
		var ph := fposmod(ms / 560.0 + D.h01(i * 13 + 7), 1.0)
		var q := c + Vector2((D.h01(i * 7 + 2) - 0.5) * t * 0.7 + sin(ph * 6.0 + float(i)) * t * 0.07,
			t * 0.25 - ph * t * 1.1)
		cv.draw_circle(q, t * 0.05 * (1.0 - 0.5 * ph), D.ca(Color("ffcf6a"), a * (1.0 - ph)))


static func _paint_cloud(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var dur := float(cl["dur"])
	var ms := k * dur
	var lead := float(cl["lead"])
	var rms := float(cl["ring_ms"])
	var col: Color = cl["col"]
	var turns := float(cl.get("turns", 1))
	var spore := String(cl.get("status", "")) == "spore"
	var fade := clampf((dur - ms) / 300.0, 0.0, 1.0)
	var dens := minf(1.0, 0.75 + 0.15 * turns)
	var ctr := D.px(V, cl["at"])
	# the pod pops where the cloud is born
	var pop := D.win(ms, 0.0, lead + 160.0)
	if pop < 1.0:
		D.glow(cv, ctr, t * (0.3 + 0.5 * D.ease_out(pop)), D.ca(col.lightened(0.3), 0.6 * (1.0 - pop)))
	for tp in cl["tiles"]:
		var u := ms - (lead + float(tp[1]) * rms)
		if u < 0.0:
			continue
		var p: Vector2i = tp[0]
		var gr := D.ease_out(D.win(u, 0.0, 280.0))
		var base := D.px(V, p)
		for j in 2:
			var n := p.x * 29 + p.y * 13 + j * 5
			var off := Vector2(D.h01(n) - 0.5, D.h01(n + 1) - 0.4) * t * 0.55
			var drift := Vector2(sin(ms * 0.004 + float(n)) * t * 0.08, -t * (0.3 if spore else 0.12) * (u / 900.0))
			var rad := t * (0.14 + 0.16 * gr + 0.05 * D.h01(n + 2))
			var pc: Color = col.darkened(0.1) if j == 0 else col.lightened(0.25)
			cv.draw_circle(base + off + drift, rad, D.ca(pc, 0.34 * dens * gr * fade))


## The motes in the cloud, over the creatures: pollen glitters, spores drift.
static func _paint_dust(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var dur := float(cl["dur"])
	var ms := k * dur
	var lead := float(cl["lead"])
	var rms := float(cl["ring_ms"])
	var col: Color = cl["col"]
	var spore := String(cl.get("status", "")) == "spore"
	var fade := clampf((dur - ms) / 260.0, 0.0, 1.0)
	var turns := int(cl.get("turns", 1))
	var per := 1 if cl["tiles"].size() > 13 else 2
	if turns > 1 and cl["tiles"].size() <= 13:
		per = 3
	for tp in cl["tiles"]:
		var u := ms - (lead + float(tp[1]) * rms)
		if u < 0.0:
			continue
		var p: Vector2i = tp[0]
		var base := D.px(V, p)
		for j in per:
			var n := p.x * 41 + p.y * 23 + j * 11
			var off := Vector2(D.h01(n) - 0.5, D.h01(n + 3) - 0.5) * t * 0.8
			if spore:
				var rise := fposmod(u / 1100.0 + D.h01(n + 5), 1.0)
				var q := base + off + Vector2(sin(u * 0.008 + float(n)) * t * 0.1, -rise * t * 0.5)
				var a := fade * D.win(u, 0.0, 120.0) * (1.0 - rise * 0.6)
				cv.draw_circle(q, t * 0.07, D.ca(col.darkened(0.45), 0.9 * a))
				cv.draw_circle(q, t * 0.045, D.ca(col.lightened(0.3), a))
			else:
				var ph := fposmod(u / 340.0 + D.h01(n + 5), 1.0)
				var q2 := base + off + Vector2(0, -t * 0.25 * (u / 900.0))
				var burst := 1.0 - D.win(u, 0.0, 180.0)
				var sz := t * (0.07 + 0.08 * D.pulse(ph) + 0.1 * burst)
				D.twinkle(cv, q2, sz, D.ca(col.lightened(0.45), fade))


## The tide: water floods out four ways under the bodies ("band"), and a
## foaming crest rides each head over them ("crest").
static func _paint_tide(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var dur := float(cl["dur"])
	var ms := k * dur
	var lead := float(cl["lead"])
	var rms := float(cl["ring_ms"])
	var c := D.px(V, cl["at"])
	var push := float(cl.get("push", 1))
	var crest := String(cl.get("part", "band")) == "crest"
	var lens: Array = cl["lens"]
	var fade := clampf((dur - ms) / 280.0, 0.0, 1.0)
	if crest and ms < lead + 200.0:
		# the swell rising around the tender
		var sw := D.win(ms, 0.0, lead + 200.0)
		cv.draw_set_transform(c + Vector2(0, t * 0.25), 0.0, Vector2(1.0, 0.45))
		D.ring(cv, Vector2.ZERO, t * (0.3 + 0.5 * D.ease_out(sw)), D.ca(pal["b"], 0.9 * (1.0 - sw)), t * 0.1)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in 4:
		var n := float(lens[i])
		if n <= 0.0:
			continue
		var dv := Vector2(L.DIRS[i])
		var s := Vector2(-dv.y, dv.x)
		var f := clampf((ms - lead) / rms, 0.0, n + 0.35)
		if f <= 0.05:
			continue
		var head := c + dv * f * t
		var arrived := ms - (lead + (n + 0.35) * rms)
		if not crest:
			# a wedge of water widening toward its head, streaked with foam
			if f < 0.2:
				continue
			var a := fade * (1.0 - 0.5 * D.win(arrived, 0.0, 200.0))
			var from := c + dv * t * 0.15
			var w0 := t * 0.2
			var w1 := t * (0.4 + 0.05 * push)
			cv.draw_colored_polygon(PackedVector2Array([from + s * w0, head + s * w1, head - s * w1, from - s * w0]),
				D.ca(pal["c"], 0.55 * a))
			cv.draw_colored_polygon(PackedVector2Array([from + s * w0 * 0.7, head + s * w1 * 0.75,
				head - s * w1 * 0.75, from - s * w0 * 0.7]), D.ca(pal["a"], 0.75 * a))
			for j in 2:
				var off := s * (float(j) - 0.5) * w1 * 0.7
				D.wavy(cv, from + off * 0.4, head + off, t * 0.06, maxf(1.0, f * 1.4), -ms * 0.025 + float(i + j * 3),
					D.ca(pal["b"], 0.85 * a), t * 0.05, 10)
			continue
		if arrived < 0.0:
			# a shallow foaming crest across the head, spray thrown ahead of it
			if f < 1.0:
				continue
			var w := t * (0.5 + 0.06 * push)
			var back := head - dv * t * 0.42
			var span := 0.62
			cv.draw_arc(back, w, dv.angle() - span, dv.angle() + span, 10, D.ca(pal["c"], 0.7), maxf(1.0, t * 0.17), true)
			cv.draw_arc(back, w, dv.angle() - span, dv.angle() + span, 10, D.ca(pal["b"], 0.95), maxf(1.0, t * 0.08), true)
			for j in 4:
				var ang := dv.angle() + (float(j) - 1.5) / 1.5 * span
				var q := back + Vector2(cos(ang), sin(ang)) * w + Vector2(0, -t * 0.06 * absf(sin(ms * 0.03 + float(j))))
				cv.draw_circle(q, t * 0.065, D.ca(pal["b"], 0.95))
			for j in 3:
				var q3 := head + dv * t * (0.2 + 0.1 * float(j)) + s * (float(j) - 1.0) * t * 0.22 \
					+ Vector2(0, -t * 0.12 * absf(sin(ms * 0.025 + float(j) * 1.7)))
				cv.draw_circle(q3, t * 0.045, D.ca(pal["b"], 0.8))
		else:
			# spent against the end of its run: it bursts into spray
			var u := D.win(arrived, 0.0, 300.0)
			if u < 1.0:
				for j in 5:
					var ang := dv.angle() + (float(j) - 2.0) * 0.5
					var q2 := head + Vector2(cos(ang), sin(ang)) * t * 0.45 * D.ease_out(u) + Vector2(0, t * 0.35 * u * u)
					cv.draw_circle(q2, t * 0.055 * (1.0 - 0.5 * u), D.ca(pal["b"], 1.0 - u))


## A ground shock: the tender stomps, a squat ring slams out across the four
## neighbours, the ground cracks and dust jumps.
static func _paint_shock(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var ms := k * float(cl["dur"])
	var lead := float(cl["lead"])
	var dist := float(cl.get("dist", 1))
	var c := D.px(V, cl["at"])
	var feet := c + Vector2(0, t * 0.3)
	if ms < lead:
		# the stomp gathers: a dark pool drawing in under the feet
		var g := D.win(ms, 0.0, lead)
		cv.draw_set_transform(feet, 0.0, Vector2(1.0, 0.42))
		cv.draw_circle(Vector2.ZERO, t * (0.5 - 0.25 * g), D.ca(pal["c"], 0.25 + 0.35 * g))
		D.ring(cv, Vector2.ZERO, t * (0.75 - 0.4 * g), D.ca(pal["b"], 0.3 + 0.5 * g), t * 0.05)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var u := ms - lead
	var gr := D.ease_out(D.win(u, 0.0, 330.0))
	var a := 1.0 - D.win(u, 40.0, 420.0)
	var rr := t * (0.3 + (1.05 + 0.25 * dist) * gr)
	cv.draw_set_transform(feet, 0.0, Vector2(1.0, 0.5))
	D.ring(cv, Vector2.ZERO, rr, D.ca(pal["c"], 0.7 * a), t * 0.26 * (1.0 - 0.6 * gr))
	D.ring(cv, Vector2.ZERO, rr, D.ca(pal["b"], a), t * 0.09)
	D.ring(cv, Vector2.ZERO, rr * 0.62, D.ca(pal["a"], 0.6 * a), t * 0.05)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# cracks run out along the four directions
	var cr := D.ease_out(D.win(u, 0.0, 140.0))
	for i in 4:
		var dv := Vector2(L.DIRS[i])
		var s := Vector2(-dv.y, dv.x)
		var p0 := c + dv * t * 0.28
		var p1 := p0 + dv * t * 0.28 * cr + s * t * 0.07
		var p2 := p1 + dv * t * 0.3 * cr - s * t * 0.1
		var crack := PackedVector2Array([p0, p1, p2])
		cv.draw_polyline(crack, D.ca(pal["c"].darkened(0.4), 0.9 * a), maxf(1.0, t * 0.11), true)
		cv.draw_polyline(crack, D.ca(pal["b"], 0.95 * a), maxf(1.0, t * 0.045), true)
		# dust jumps on the neighbour
		var q := c + dv * t + Vector2(0, t * 0.22)
		var du := D.win(u, 30.0, 380.0)
		if du > 0.0 and du < 1.0:
			for j in 2:
				var off := Vector2((float(j) - 0.5) * t * 0.36, -t * (0.1 + 0.35 * D.ease_out(du)) * (1.0 + 0.3 * float(j)))
				cv.draw_circle(q + off, t * (0.1 + 0.08 * du), D.ca(pal["a"], 0.55 * (1.0 - du)))


## A whirlwind: a spinning funnel at the tender and streamers spiralling out
## across the covered diamond.
static func _paint_swirl(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var dur := float(cl["dur"])
	var ms := k * dur
	var lead := float(cl["lead"])
	var rms := float(cl["ring_ms"])
	var r := float(cl["r"])
	var c := D.px(V, cl["at"])
	var f := clampf((ms - lead) / rms, 0.0, r)
	var up := D.ease_out(D.win(ms, 0.0, lead))
	var live := clampf((dur - ms) / 280.0, 0.0, 1.0)
	var spin := ms * 0.016
	# the funnel: stacked spinning rings, narrow at the feet, wide overhead
	for j in 4:
		var fj := float(j) / 3.0
		var y := t * (0.34 - 1.25 * fj * up)
		var w := t * (0.2 + 0.5 * fj) * (0.5 + 0.5 * up)
		cv.draw_set_transform(c + Vector2(sin(spin * 0.7 + fj) * t * 0.04, y), 0.0, Vector2(1.0, 0.32))
		cv.draw_arc(Vector2.ZERO, w, spin + fj * 2.0, spin + fj * 2.0 + 4.4, 14, D.ca(pal["c"], 0.6 * live),
			maxf(1.0, t * 0.13), true)
		cv.draw_arc(Vector2.ZERO, w, spin + fj * 2.0, spin + fj * 2.0 + 4.4, 14, D.ca(pal["b"], 0.95 * live),
			maxf(1.0, t * 0.06), true)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if ms < lead:
		return
	# streamers ride out with the front, curling round the tender along
	# scaled copies of the diamond, so the wind never outruns the area
	var Rd := (f + 0.5) * t
	for i in 6:
		var fi := float(i) / 5.0
		var frac := 0.4 + 0.6 * fi
		var a0 := TAU * float(i) / 6.0 + spin * (1.2 - 0.5 * fi)
		var pts := PackedVector2Array()
		for j in 9:
			var a := a0 + 1.15 * float(j) / 8.0
			var rho := maxf(t * 0.55, frac * (0.5 * _reach(Rd, a) + 0.42 * Rd))
			pts.append(c + Vector2(cos(a), sin(a)) * rho)
		cv.draw_polyline(pts, D.ca(pal["c"], 0.45 * live), maxf(1.0, t * 0.11), true)
		cv.draw_polyline(pts, D.ca(pal["b"], 0.9 * live), maxf(1.0, t * 0.045), true)
		cv.draw_circle(pts[8], t * 0.05, D.ca(pal["b"], live))


## A smoke tile the wind reached: its puffs are torn up and away, spinning.
static func _paint_smoke_lift(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var col: Color = cl.get("col", Color("9aa0a4"))
	var c := D.px(V, cl["at"])
	var away := (c - D.px(V, cl["from"])).normalized() if Vector2(cl["at"]) != Vector2(cl["from"]) else Vector2.UP
	var u := D.ease_out(k)
	for i in 3:
		var ph := TAU * float(i) / 3.0 + k * 7.0
		var q := c + Vector2(cos(ph), sin(ph) * 0.6) * t * (0.18 + 0.3 * u) + away * t * 0.5 * u \
			+ Vector2(0, -t * 0.9 * u)
		var rad := t * (0.25 + 0.06 * float(i % 2)) * (1.0 - 0.4 * u)
		cv.draw_circle(q, rad, D.ca(col.darkened(0.25), 0.6 * (1.0 - k)))
		cv.draw_circle(q + Vector2(-rad * 0.25, -rad * 0.25), rad * 0.6, D.ca(col.lightened(0.25), 0.65 * (1.0 - k)))


## Filth rewritten: the corruption boils away inside a closing ring of the
## new kind, then life springs up - leaves, or bark stakes for a kind that
## blocks.
static func _paint_rewrite(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var col: Color = cl.get("col", Color("6cc95c"))
	var fcol: Color = cl.get("from_col", Color("3a2e3f"))
	var c := D.px(V, cl["at"])
	var u1 := D.win(k, 0.0, 0.3)
	if u1 < 1.0:
		cv.draw_circle(c + Vector2(0, t * 0.08), t * 0.36 * (1.0 - D.ease_in(u1)), D.ca(fcol.darkened(0.2), 0.8 * (1.0 - u1)))
		for i in 3:
			var ph := D.h01(i * 5 + 1)
			var bq := c + Vector2((ph - 0.5) * t * 0.4, t * 0.1 - t * 0.35 * u1 * (0.5 + ph))
			cv.draw_circle(bq, t * 0.06 * (1.0 - u1), D.ca(fcol.lightened(0.25), 0.8 * (1.0 - u1)))
	D.ring(cv, c, t * (0.55 - 0.3 * D.ease_in(D.win(k, 0.0, 0.25))), D.ca(col.lightened(0.45), 0.95 * D.tail(k, 0.3)), t * 0.08)
	var u2 := D.win(k, 0.2, 0.62)
	var a := D.tail(k, 0.62)
	if u2 <= 0.0:
		return
	var g := D.ease_out(u2)
	var base := c + Vector2(0, t * 0.3)
	if bool(cl.get("blocks", false)):
		for i in 3:
			var x := (float(i) - 1.0) * t * 0.24
			var hgt := t * (0.55 + 0.1 * float(i % 2)) * g
			D.spike(cv, base + Vector2(x, 0), base + Vector2(x * 0.8, -hgt), t * 0.2, D.ca(col.darkened(0.35), a))
			D.spike(cv, base + Vector2(x, 0), base + Vector2(x * 0.8, -hgt * 0.92), t * 0.12, D.ca(col.lightened(0.3), a))
	else:
		for i in 4:
			var ang := -PI * 0.5 + (float(i) - 1.5) * 0.55
			var q := base + Vector2(cos(ang), sin(ang)) * t * 0.3 * g
			D.leaf(cv, q, ang, t * 0.34 * g, D.ca(col.darkened(0.3), a))
			D.leaf(cv, q, ang, t * 0.26 * g, D.ca(col.lightened(0.35) if i % 2 == 0 else col, a))
	if u2 < 0.6:
		D.glow(cv, c, t * 0.45 * (1.0 - u2 / 0.6), D.ca(col.lightened(0.6), 0.5))


## A thrown seed (grow), pod (a cloud centred on its target) or sap bead
## (convert): big, dark-rimmed and glowing so it reads over the grass, with a
## trail, a ground shadow and a landing ring on the target.
static func _paint_lob(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var a := D.px(V, cl["from"])
	var b := D.px(V, cl["to"])
	var col: Color = cl.get("col", Color("6cc95c"))
	var pal: Dictionary = cl.get("pal", L.PAL_DEFAULT)
	var style := String(cl.get("style", "seed"))
	var h := t * (0.8 + 0.2 * a.distance_to(b) / t)
	var u := k
	var arc := 4.0 * u * (1.0 - u)
	var q := D.arc_point(a, b, u, h)
	# where it will land
	cv.draw_set_transform(b + Vector2(0, t * 0.26), 0.0, Vector2(1.0, 0.45))
	cv.draw_circle(Vector2.ZERO, t * 0.4, D.ca(col, 0.12 + 0.2 * u))
	D.ring(cv, Vector2.ZERO, t * (0.46 - 0.1 * u), D.ca(col.lightened(0.45), 0.3 + 0.6 * u), t * 0.07)
	cv.draw_set_transform(a.lerp(b, u) + Vector2(0, t * 0.3), 0.0, Vector2(1.0, 0.45))
	cv.draw_circle(Vector2.ZERO, t * (0.17 - 0.06 * arc), Color(0, 0, 0, 0.32))
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for j in 6:
		var uj := u - float(j + 1) * 0.045
		if uj > 0.0:
			cv.draw_circle(D.arc_point(a, b, uj, h), t * (0.075 - 0.01 * float(j)), D.ca(col.lightened(0.5), 0.75 - 0.11 * float(j)))
	var sz := t * (0.18 + 0.07 * arc)
	D.glow(cv, q, sz * 2.1, D.ca(col.lightened(0.5), 0.4))
	match style:
		"seed":
			cv.draw_set_transform(q, k * 8.0, Vector2(1.0, 0.8))
			cv.draw_circle(Vector2.ZERO, sz * 1.22, SEED_COL.darkened(0.6))
			cv.draw_circle(Vector2.ZERO, sz, SEED_COL)
			cv.draw_circle(Vector2(-sz * 0.3, -sz * 0.3), sz * 0.32, Color(1, 1, 0.9, 0.85))
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var la := -PI * 0.5 + sin(k * 16.0) * 0.5
			D.leaf(cv, q + Vector2(cos(la), sin(la)) * sz * 1.1, la, sz * 1.5, pal["c"])
			D.leaf(cv, q + Vector2(cos(la), sin(la)) * sz * 1.1, la, sz * 1.15, pal["b"])
		"pod":
			cv.draw_circle(q, sz * 1.2, col.darkened(0.5))
			cv.draw_circle(q, sz, col)
			cv.draw_circle(q + Vector2(-sz * 0.3, -sz * 0.3), sz * 0.35, D.ca(Color.WHITE, 0.8))
			for i in 3:
				var ang := TAU * float(i) / 3.0 + k * 9.0
				D.twinkle(cv, q + Vector2(cos(ang), sin(ang)) * sz * 1.7, t * 0.08, D.ca(col.lightened(0.5), 0.95))
		_:
			cv.draw_circle(q, sz * 1.2, col.darkened(0.5))
			cv.draw_circle(q, sz, col.lightened(0.15))
			D.tri(cv, q + Vector2(-sz * 0.7, -sz * 0.5), q + Vector2(sz * 0.7, -sz * 0.5), q + Vector2(0, -sz * 1.9),
				col.lightened(0.15))
			cv.draw_circle(q + Vector2(-sz * 0.3, -sz * 0.25), sz * 0.3, D.ca(Color.WHITE, 0.8))


static func _parent(p: Vector2i, ctr: Vector2i) -> Vector2i:
	var dv := p - ctr
	if absi(dv.x) >= absi(dv.y):
		return p - Vector2i(signi(dv.x), 0)
	return p - Vector2i(0, signi(dv.y))


## Where the seed lands (or the tender plants): a burst of soil, then pale
## roots run out ring by ring to every covered tile.
static func _paint_roots(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl["pal"]
	var dur := float(cl["dur"])
	var ms := k * dur
	var lead := float(cl["lead"])
	var rms := float(cl["ring_ms"])
	var ctr: Vector2i = cl["at"]
	var c := D.px(V, ctr)
	var fade := clampf((dur - ms) / 240.0, 0.0, 1.0)
	var u0 := ms / 300.0
	if u0 < 1.0:
		cv.draw_set_transform(c + Vector2(0, t * 0.2), 0.0, Vector2(1.0, 0.5))
		D.ring(cv, Vector2.ZERO, t * (0.2 + 0.55 * D.ease_out(u0)), D.ca(pal["b"], 1.0 - u0), t * 0.09)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var clod: Color = DIRT_COL if bool(cl.get("thrown", false)) else pal["b"]
		for i in 6:
			var ang := -PI * (0.1 + 0.8 * float(i) / 5.0)
			var q := c + Vector2(cos(ang), sin(ang)) * t * 0.5 * D.ease_out(u0) + Vector2(0, t * 0.1 + t * 0.6 * u0 * u0)
			cv.draw_circle(q, t * 0.055 * (1.0 - 0.5 * u0), D.ca(clod, 1.0 - u0))
	for tp in cl["tiles"]:
		var d := int(tp[1])
		if d == 0:
			continue
		var p: Vector2i = tp[0]
		var arrive := lead + float(d) * rms
		var u := D.win(ms, arrive - rms, arrive)
		if u <= 0.0:
			continue
		# a root runs out to the tile, then sinks back once its sprout is up
		var ra := fade * (1.0 - D.win(ms, arrive + 140.0, arrive + 380.0))
		if ra <= 0.0:
			continue
		var pa := D.px(V, _parent(p, ctr)) + Vector2(0, t * 0.22)
		var pb := D.px(V, p) + Vector2(0, t * 0.22)
		var end := pa.lerp(pb, u)
		D.wavy(cv, pa, end, t * 0.06, 1.5, float(p.x * 3 + p.y * 7), D.ca(pal["c"], 0.7 * ra), t * 0.075, 8)
		D.wavy(cv, pa, end, t * 0.06, 1.5, float(p.x * 3 + p.y * 7), D.ca(pal["b"], 0.8 * ra), t * 0.035, 8)
	if bool(cl.get("verdant", false)):
		var R := (clampf((ms - lead) / rms, 0.0, float(cl["tiles"][cl["tiles"].size() - 1][1])) + 0.5) * t
		for i in 8:
			var s := (float(i) + 0.5) / 8.0 + ms * 0.0002
			D.leaf(cv, _perim(c, R, s), _perim_n(s).angle(), t * 0.22, D.ca(Color("8fdc6a"), 0.9 * fade))


static func _paint_sprout(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal: Dictionary = cl.get("pal", L.PAL_DEFAULT)
	var base := D.px(V, cl["at"]) + Vector2(0, t * 0.32)
	var g := D.ease_out(D.win(k, 0.0, 0.42))
	var over := 1.0 + 0.3 * D.pulse(D.win(k, 0.28, 0.7))
	var a := D.tail(k, 0.68)
	var top := base + Vector2(0, -t * 0.52 * g * over)
	D.line(cv, base, top, D.ca(pal["c"], a), t * 0.1)
	D.line(cv, base, top, D.ca(pal["a"], a), t * 0.05)
	var ls := t * 0.36 * g * over
	var lp := top + Vector2(-t * 0.13, t * 0.03)
	var rp := top + Vector2(t * 0.13, -t * 0.02)
	D.leaf(cv, lp, PI * 1.12, ls * 1.2, D.ca(pal["c"], a))
	D.leaf(cv, lp, PI * 1.12, ls, D.ca(pal["a"], a))
	D.leaf(cv, rp, -PI * 0.12, ls * 1.2, D.ca(pal["c"], a))
	D.leaf(cv, rp, -PI * 0.12, ls, D.ca(pal["b"], a))
	# a flash and a puff of pollen as it pops
	var u := D.win(k, 0.3, 0.9)
	if u > 0.0 and u < 1.0:
		D.glow(cv, top, t * 0.3 * (1.0 - u), D.ca(pal["b"], 0.6))
		for i in 4:
			var ang := -PI * (0.15 + 0.23 * float(i))
			cv.draw_circle(top + Vector2(cos(ang), sin(ang)) * t * 0.4 * u, t * 0.04, D.ca(Color("f0d968"), 1.0 - u))
