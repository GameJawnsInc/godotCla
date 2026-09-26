extends RefCounted
## Shared helpers for the step-animation director (shell/anim.gd) and the verb
## family modules (shell/fx_*.gd). Everything here is a pure function over
## sim SNAPSHOTS and plain dicts: nothing reads the Game object, the clock,
## input or the scene tree, so a reel can be planned and asserted on headless
## (tests/test_anim.gd) exactly as the shell plans it.
##
## Vocabulary (docs/SHELL.md "Animations"):
##   reel     what one step() looks like: {clips, tracks, ghosts, spawns,
##            shakes, tswap, len}. Times are integer ms from the step.
##   clip     one painted effect {kind, t0, dur, layer, pal, ...geometry}.
##            Geometry is in TILE space (Vector2i / Vector2 tile coords);
##            the painter owns pixels.
##   track    per creature ("player" or an enemy id) list of motion SEGMENTS
##            {kind, t0, dur, ...}; Anim.pose() folds them into where and how
##            to draw the creature at time t.
##   ctx (c)  the build context a verb builder receives (see Anim.ctx()).

const Content := preload("res://sim/content.gd")

## Timings, ms at full speed. Everything else is a multiple of these.
const T_MOVE := 150
const T_STRIKE := 230
const T_STRIKE_HIT := 95
const T_WINDUP := 110
const T_FLOAT := 750
const T_FLASH := 220
const T_RECOIL := 210
const T_DIE := 460
const T_POP := 340
const T_STATUS := 560
const T_ENEMY := 300
const T_HIT := 120        # default impact point inside an enemy's slot
const FLOAT_STACK := 110  # numbers landing on one creature fan out in time

## Screen shake magnitudes (pixels).
const SHAKE_BIG := 9.0

## The sim's four directions, in the sim's order (sim/game.gd DIRS).
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## An ability's colours come from its FIRST tag in this order - data, never an
## id literal, so a new ability is coloured by the tags it ships with.
const ELEMENT_ORDER := ["sun", "fire", "water", "wind", "smoke", "control", "bark",
	"growth", "displace", "mobility"]
## a: body colour, b: hot highlight, c: dark edge.
const ELEMENTS := {
	"sun": {"a": Color("f7c948"), "b": Color("fff6cf"), "c": Color("e8722a")},
	"fire": {"a": Color("ef933a"), "b": Color("fdf0a8"), "c": Color("b8441e")},
	"water": {"a": Color("5aa7d8"), "b": Color("d6f1fb"), "c": Color("2f6f9a")},
	"wind": {"a": Color("c8e0d0"), "b": Color("ffffff"), "c": Color("7fa898")},
	"smoke": {"a": Color("9aa0a4"), "b": Color("dde2e4"), "c": Color("565f66")},
	"control": {"a": Color("e8c840"), "b": Color("fbf1a8"), "c": Color("a8862a")},
	"bark": {"a": Color("8a6a3e"), "b": Color("dcb880"), "c": Color("4e3620")},
	"growth": {"a": Color("6cc95c"), "b": Color("d2f7b4"), "c": Color("2f6b2c")},
	"displace": {"a": Color("57b34a"), "b": Color("b4e89a"), "c": Color("2a5526")},
	"mobility": {"a": Color("b48ad8"), "b": Color("efe2ff"), "c": Color("5e4a86")},
}
const PAL_DEFAULT := {"a": Color("8fdc6a"), "b": Color("e6edd8"), "c": Color("3f8f3a")}

## Status colours (Content.STATUSES ids). Unknown statuses fall back to cream.
const STATUS_COL := {"stun": Color("f0d968"), "root": Color("c9a63c"), "spore": Color("b39ae6")}

## Terrain kinds' own colours, for reveal flourishes (ignite, convert, ooze).
const TERRAIN_COL := {
	"fire": Color("ef933a"), "growth": Color("6cc95c"), "roots": Color("8a6a3e"),
	"smoke": Color("9aa0a4"), "oil": Color("3a2e3f"), "goo": Color("8a7a3f"),
	"rich_goo": Color("e8c840"), "ash": Color("75726b"),
}

## Idle loop per enemy: derived from traits, with a per-kind override for rows
## whose traits say nothing about how they move. A new enemy row with none of
## these falls back to "bob" - it breathes, it never stands frozen.
const IDLE_BY_TRAIT := [
	["boss", "heave"], ["drains", "hover"], ["fast", "pant"], ["oil_trail", "ooze"],
	["splits", "ooze"], ["summons", "chug"], ["oozes", "chug"], ["stokes", "chug"],
	["igniter", "skitter"], ["drags", "sway"],
]
const IDLE_BY_KIND := {"sludgeling": "ooze"}


# --- palettes -----------------------------------------------------------------

static func pal_for(aid: String) -> Dictionary:
	var adef: Dictionary = Content.ABILITIES.get(aid, {})
	var tags: Array = adef.get("tags", [])
	for el in ELEMENT_ORDER:
		if tags.has(el):
			return ELEMENTS[el]
	return PAL_DEFAULT


static func pal_of(el: String) -> Dictionary:
	return ELEMENTS.get(el, PAL_DEFAULT)


static func status_col(status: String) -> Color:
	return STATUS_COL.get(status, Color("e6edd8"))


static func idle_style(kind: String) -> String:
	if IDLE_BY_KIND.has(kind):
		return IDLE_BY_KIND[kind]
	var traits: Array = Content.ENEMIES.get(kind, {}).get("traits", [])
	for row in IDLE_BY_TRAIT:
		if traits.has(row[0]):
			return row[1]
	return "bob"


# --- snapshot geometry ----------------------------------------------------------

static func man(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func wall(snap: Dictionary, p: Vector2i) -> bool:
	var m: Dictionary = snap["map"]
	if p.x < 0 or p.y < 0 or p.x >= int(m["w"]) or p.y >= int(m["h"]):
		return true
	return int(m["tiles"][p.y * int(m["w"]) + p.x]) != 1


static func tkind(snap: Dictionary, p: Vector2i) -> String:
	var t = snap["terrain"].get(p)
	return "" if t == null else String(t.get("kind", ""))


static func enemy_at(snap: Dictionary, p: Vector2i) -> Variant:
	for e in snap["enemies"]:
		if e["pos"] == p:
			return e
	return null


static func enemy_by_id(snap: Dictionary, id) -> Variant:
	for e in snap["enemies"]:
		if e["id"] == id:
			return e
	return null


static func massive(kind: String) -> bool:
	return Content.ENEMIES.get(kind, {}).get("traits", []).has("massive")


## The sim's _open(): floor, no enemy (other than `ignore_id`), not the
## player, no blocking terrain.
static func open(snap: Dictionary, p: Vector2i, ignore_id = null, player_pos = null) -> bool:
	if wall(snap, p):
		return false
	var e = enemy_at(snap, p)
	if e != null and e["id"] != ignore_id:
		return false
	var pp: Vector2i = snap["player"]["pos"] if player_pos == null else player_pos
	if p == pp:
		return false
	var k := tkind(snap, p)
	return k == "" or not bool(Content.terrain(k, "blocks", false))


## Tiles a straight walk from `origin` visits along `dir`, at most `n` long.
## A wall ends it (exclusive); `beam` also ends it on a blocks_beam tile
## (exclusive) exactly as the lance does; `stop_enemy` includes the first
## enemy's tile and stops there.
static func line(snap: Dictionary, origin: Vector2i, dir: Vector2i, n: int, stop_enemy: bool, beam: bool) -> Array:
	var out: Array = []
	var p := origin
	for i in range(n):
		p += dir
		if wall(snap, p):
			break
		if beam and bool(Content.terrain(tkind(snap, p), "blocks_beam", false)):
			break
		out.append(p)
		if stop_enemy and enemy_at(snap, p) != null:
			break
	return out


## Every tile within manhattan `r` of `c` (floor or not), nearest first.
static func diamond(c: Vector2i, r: int) -> Array:
	var out: Array = []
	for d in range(r + 1):
		for dy in range(-d, d + 1):
			var dx := d - absi(dy)
			out.append(c + Vector2i(dx, dy))
			if dx != 0:
				out.append(c + Vector2i(-dx, dy))
	return out


## A manhattan path a -> b (both inclusive) that prefers floor: x first when
## that corner is floor, else y first. Only used to draw a multi-step move
## the sim reported as a before/after pair.
static func path(snap: Dictionary, a: Vector2i, b: Vector2i) -> Array:
	var out: Array = [a]
	if a == b:
		return out
	var corner_x := Vector2i(b.x, a.y)
	var x_first := not wall(snap, corner_x)
	var p := a
	var guard := 0
	while p != b and guard < 64:
		guard += 1
		var step := Vector2i.ZERO
		if x_first and p.x != b.x or not x_first and p.y == b.y:
			step = Vector2i(signi(b.x - p.x), 0)
		else:
			step = Vector2i(0, signi(b.y - p.y))
		p += step
		out.append(p)
	return out


## Where a shove along `dir` would stop an enemy standing at `from` (the sim's
## _push_enemy walk on the PRE board). Used only to place the corpse of an
## enemy the push killed, since the post snapshot no longer holds it.
static func push_end(snap: Dictionary, from: Vector2i, dir: Vector2i, dist: int, id, player_pos: Vector2i) -> Vector2i:
	var p := from
	for i in range(dist):
		var nxt := p + dir
		if not open(snap, nxt, id, player_pos):
			break
		p = nxt
		# a fatal tile (fire) ends the walk: the corpse lies where it burned
		if int(Content.terrain(tkind(snap, p), "enter_dmg_enemy", 0)) > 0:
			break
	return p


# --- build context helpers ------------------------------------------------------

## Append a clip. Defaults: t0 = c.t, layer "air", pal = c.pal. Returns it.
static func clip(c: Dictionary, d: Dictionary) -> Dictionary:
	if not d.has("t0"):
		d["t0"] = int(c.get("t", 0))
	if not d.has("layer"):
		d["layer"] = "air"
	if not d.has("pal"):
		d["pal"] = c.get("pal", PAL_DEFAULT)
	d["t0"] = int(d["t0"])
	d["dur"] = int(d.get("dur", 300))
	c["reel"]["clips"].append(d)
	return d


## Append a motion segment to a creature's track ("player" or an enemy id).
static func seg(c: Dictionary, key, d: Dictionary) -> Dictionary:
	if not d.has("t0"):
		d["t0"] = int(c.get("t", 0))
	d["t0"] = int(d["t0"])
	d["dur"] = int(d.get("dur", 200))
	var tracks: Dictionary = c["reel"]["tracks"]
	if not tracks.has(key):
		tracks[key] = []
	tracks[key].append(d)
	return d


## A path segment: slide (hop 0) or hop along `pts` (tile coords).
static func move(c: Dictionary, key, pts: Array, t0: int, dur: int, hop: float = 0.0) -> void:
	if pts.size() < 2:
		return
	var fpts: Array = []
	for p in pts:
		fpts.append(Vector2(p))
	seg(c, key, {"kind": "path", "t0": t0, "dur": dur, "pts": fpts, "hop": hop})


## Claim event i: it happens at time t (and, for a hit, came from `dir`).
static func claim(c: Dictionary, i: int, t: int, dir = null) -> void:
	c["times"][i] = int(t)
	if dir != null:
		c["dirs"][i] = Vector2(dir)


static func claimed(c: Dictionary, i: int) -> bool:
	return int(c["times"][i]) >= 0


## Suppress the generic feedback for event i (the verb draws its own).
static func quiet(c: Dictionary, i: int) -> void:
	c["quiet"][i] = true


## Unclaimed event indices in the builder's window [c.ev0, c.ev1) whose type
## is in `types` (any type when empty).
static func unclaimed(c: Dictionary, types: Array = []) -> Array:
	var out: Array = []
	var evs: Array = c["events"]
	for i in range(int(c.get("ev0", 0)), int(c.get("ev1", evs.size()))):
		if int(c["times"][i]) >= 0:
			continue
		if types.is_empty() or types.has(String(evs[i].get("t", ""))):
			out.append(i)
	return out


## The tile an event is about: its own `tile`, else its subject's position
## (enemy id -> pre position, or the post position of a live one).
static func ev_tile(c: Dictionary, ev: Dictionary) -> Variant:
	if ev.has("tile") and ev["tile"] is Vector2i:
		return ev["tile"]
	if ev.has("to") and ev["to"] is Vector2i:
		return ev["to"]
	if String(ev.get("who", "")) == "player":
		return c["p1"]
	var id = ev.get("id", null)
	if id != null:
		if c["post_en"].has(id):
			return c["post_en"][id]["pos"]
		if c["pre_en"].has(id):
			return c["pre_en"][id]["pos"]
	return null


## Terrain at `p` flips at time t (a verb that plants, burns or washes a tile
## sets when the change becomes visible; the painter shows the pre-step kind
## until then).
static func reveal(c: Dictionary, p: Vector2i, t: int) -> void:
	var sw: Dictionary = c["reel"]["tswap"]
	if sw.has(p) and not sw[p].has("t"):
		sw[p]["t"] = int(t)


## [from, to] of a creature that changed tile between the snapshots (enemy id
## or "player"); null when it did not move or is not on both boards.
static func moved(c: Dictionary, key) -> Variant:
	if key is String and key == "player":
		return null if c["p0"] == c["p1"] else [c["p0"], c["p1"]]
	if c["pre_en"].has(key) and c["post_en"].has(key):
		var a: Vector2i = c["pre_en"][key]["pos"]
		var b: Vector2i = c["post_en"][key]["pos"]
		return null if a == b else [a, b]
	return null


## Damage events in the builder window whose src is this cast (the ability
## id, or a collision it caused), for the enemy `id` (any enemy when null).
static func cast_hits(c: Dictionary, id = null) -> Array:
	var out: Array = []
	var aid := String(c.get("aid", ""))
	var evs: Array = c["events"]
	for i in unclaimed(c, ["damage"]):
		var ev: Dictionary = evs[i]
		if String(ev.get("who", "")) == "player":
			continue
		var src := String(ev.get("src", ""))
		if src != aid and src != "collision:" + aid:
			continue
		if id != null and ev.get("id") != id:
			continue
		out.append(i)
	return out


## The effect dict as the sim ran it: surge stat deltas added (Game._surges /
## _apply_effect), so a surged seed bomb's diamond is drawn two rings wide.
static func surged(eff: Dictionary, surge: Dictionary) -> Dictionary:
	if surge.is_empty():
		return eff
	var out := eff.duplicate()
	for k in surge:
		if eff.has(k) and not (String(k) == "cost"):
			out[k] = int(eff[k]) + int(surge[k])
	return out


static func dir_of(a: Vector2i, b: Vector2i) -> Vector2:
	var d := Vector2(b - a)
	return Vector2.ZERO if d.length() < 0.001 else d.normalized()
