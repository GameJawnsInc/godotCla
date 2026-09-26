extends RefCounted
## Verb family: PLACEMENTS and SELF - effects aimed at one tile or at the
## tender. Every verb is a beat of anticipation, a travelling or growing
## motion, a crisp impact at exactly the ms its sim event is claimed, and a
## quick clear, so the board reads again well inside 0.6 s of the hit.
##   create_terrain  a seed pod is lobbed, splits, and the terrain bursts out
##                   of it (billowing cloud, flame, a sprout or a root wall,
##                   by what the TERRAIN row says the kind does); cast on the
##                   tender's own tile it is thrown off the body instead, with
##                   bark chaff
##   grow_wall       a root runs under the floor to the target, then roots
##                   heave up tile by tile with dirt flying; aimed at a body
##                   (a cage) they lean in and a coil cinches round its feet
##   apply_status    a glob arcs onto the target and splats: sticky sap for a
##                   status that holds, a ball of spores for one that ticks
##   damage          the floor cracks and glows under the target - veins run
##                   in from whatever its `per` rider counts - then a thorn
##                   spike ERUPTS through it on the hit
##   teleport        by the target shape: to growth, the tender sinks into
##                   spores, a glowing root-thread runs under the floor and it
##                   blooms back up; to a bare tile, it dives into a hole, a
##                   mound tunnels across and it bursts out in a spray of dirt
##   plant_origin    a sprout pushes up where the tender left
##   shield          bark plates snap shut round the tender, then shimmer blue
##   thorns          vines coil tight, spikes burst out, then settle to a crown
##   anchor          a hop and a stomp: roots drive into the floor, dust rolls
##   undim           a sunbeam drops through the haze and parts it
##   status_target   a rider's status lands on what the parent touched
## Sizes, counts and tempo come from the effect's numbers (amount, dmg, turns,
## ttl, the rider's cap), the ability's target shape and palette, status and
## terrain rows - never from an ability id or an enemy kind.

const Content := preload("res://sim/content.gd")
const L := preload("res://shell/anim_lib.gd")
const D := preload("res://shell/anim_draw.gd")
const Art := preload("res://shell/svg_art.gd")

const OPS := ["create_terrain", "grow_wall", "apply_status", "damage", "teleport", "plant_origin",
	"shield", "thorns", "anchor", "undim", "status_target"]
const KINDS := ["pod_lob", "terrain_burst", "root_run", "root_heave", "root_cinch", "sap_glob", "sap_splat",
	"floor_crack", "thorn_erupt", "clod_burst", "tender_warp", "under_thread", "trail_sprout",
	"bark_shell", "thorn_crown", "root_anchor", "sun_shaft", "sun_pool"]

## Materials. The ability palette (c.pal) rides on top of these; they are what
## things are MADE of, so they stay put whatever element cast them.
const DIRT := Color("6b4f33")
const DIRT_LIGHT := Color("a8845a")
const SOIL := Color(0.07, 0.05, 0.035)
const BARK := Color("8a6a3e")
const BARK_DARK := Color("47301b")
const BARK_LIGHT := Color("e0bd84")
const POD := Color("7d8c3c")
const LEAF := Color("6cc95c")
const THORN := Color("3f7a33")
const SHIELD := Color("7fb6d9")
const SHIELD_HI := Color("e8f7ff")
const STONE := Color("9a9c96")
const HAZE := Color(0.50, 0.43, 0.36)

const LOB_MS := 170       # a lobbed pod or glob in flight ...
const LOB_TILE_MS := 35   # ... plus this per tile of distance
const RUN_MS := 45        # per tile a root runs under the floor to its wall
const HEAVE_MS := 75      # a root wall's rings heave this far apart
const CRACK_MS := 170     # the floor cracks this long before a spike erupts
const SNAP_MS := 150      # bark plates fly in, then snap shut


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
			return _shield(c)
		"thorns":
			return _thorns(c)
		"anchor":
			return _anchor(c)
		"undim":
			return _undim(c)
		"status_target":
			return _rider_status(c)
	return int(c["t"])


# --- builders ----------------------------------------------------------------------

static func _target(c: Dictionary) -> Vector2i:
	var tg = c.get("target")
	return tg if tg is Vector2i else c["ppos"]


static func _on_tile(ev: Dictionary, tile: Vector2i) -> bool:
	return ev.get("tile") is Vector2i and ev["tile"] == tile


## How a terrain kind bursts into being, read off its TERRAIN row: a cloud
## for a kind that screens or blocks beams, flame for one that burns whatever
## enters, a wall for one that blocks, a sprout for one that heals.
static func _look(kind: String) -> String:
	if bool(Content.terrain(kind, "screens", false)) or bool(Content.terrain(kind, "blocks_beam", false)):
		return "cloud"
	if int(Content.terrain(kind, "enter_dmg_enemy", 0)) > 0:
		return "flame"
	if bool(Content.terrain(kind, "blocks", false)):
		return "wall"
	if int(Content.terrain(kind, "heal", 0)) > 0:
		return "sprout"
	return "cloud"


static func _terrain(c: Dictionary) -> int:
	var t: int = c["t"]
	var tile := _target(c)
	var eff: Dictionary = c["eff"]
	var kind := String(eff.get("kind", "smoke"))
	var ttl := int(eff.get("ttl", 3))
	var col: Color = L.TERRAIN_COL.get(kind, Color("9aa0a4"))
	var here: bool = tile == c["ppos"]
	var t_land := t + 30
	if not here:
		var dist := maxi(1, L.man(c["ppos"], tile))
		var fly := LOB_MS + LOB_TILE_MS * dist
		L.seg(c, "player", {"kind": "lunge", "t0": t - 30, "dur": 220, "dir": L.dir_of(c["ppos"], tile), "reach": 0.14})
		L.clip(c, {"kind": "pod_lob", "t0": t, "dur": fly + 80, "fly": fly, "from": c["ppos"], "to": tile,
			"h": 0.8 + 0.12 * float(dist), "col": col, "at": tile})
		t_land = t + fly
	_burst_terrain(c, tile, _look(kind), col, ttl, here, t_land)
	for i in L.unclaimed(c, ["terrain", "hook", "ignite"]):
		if _on_tile(c["events"][i], tile):
			L.claim(c, i, t_land)
	L.reveal(c, tile, t_land + 90)
	return t_land + 200


## The burst a new terrain tile makes as it appears at `t_land`.
static func _burst_terrain(c: Dictionary, tile: Vector2i, look: String, col: Color, ttl: int, here: bool, t_land: int) -> void:
	match look:
		"wall":
			L.clip(c, {"kind": "root_heave", "t0": maxi(0, t_land - 60), "dur": 560, "at": tile, "lean": Vector2.ZERO, "ttl": ttl})
			L.clip(c, {"kind": "clod_burst", "t0": t_land, "dur": 460, "at": tile, "n": 6, "puffs": 3, "h": 0.8, "spread": 0.5})
		"sprout":
			L.clip(c, {"kind": "trail_sprout", "t0": t_land, "dur": 520, "at": tile, "col": col})
		_:
			L.clip(c, {"kind": "terrain_burst", "t0": t_land, "dur": 460 + 45 * ttl, "at": tile, "col": col,
				"look": look, "size": 0.85 + 0.07 * float(ttl), "n": mini(8 + ttl, 14), "here": here})


static func _wall(c: Dictionary) -> int:
	var t: int = c["t"]
	var center := _target(c)
	var ttl := int(c["eff"].get("ttl", 4))
	var body = L.enemy_at(c["pre"], center)
	var sw: Dictionary = c["reel"]["tswap"]
	var tiles: Array = []
	for p in L.diamond(center, 1):
		if sw.has(p) and not sw[p].has("t") and bool(Content.terrain(String(sw[p]["post"]), "blocks", false)):
			tiles.append(p)
	var run := RUN_MS * maxi(1, L.man(c["ppos"], center))
	L.clip(c, {"kind": "root_run", "t0": t, "dur": run + 260, "run": run, "from": c["ppos"], "to": center,
		"at": center, "layer": "ground"})
	var t0 := t + run
	var t_last := t0
	for j in tiles.size():
		var p: Vector2i = tiles[j]
		# a wall rises ring by ring from its centre; a cage closes all round
		var tt := t0 + (j * 40 if body != null else L.man(p, center) * HEAVE_MS)
		var lean := Vector2(center - p) if body != null else Vector2.ZERO
		L.clip(c, {"kind": "root_heave", "t0": tt, "dur": 560, "at": p, "lean": lean, "ttl": ttl})
		L.clip(c, {"kind": "clod_burst", "t0": tt + 60, "dur": 460, "at": p, "n": 6, "puffs": 3, "h": 0.8,
			"spread": 0.5, "seed": j})
		L.reveal(c, p, tt + 190)
		t_last = maxi(t_last, tt)
	for i in L.unclaimed(c, ["roots"]):
		L.claim(c, i, t0 + 90)
	if not tiles.is_empty():
		c["reel"]["shakes"].append({"t0": t0 + 80, "mag": minf(1.8 + 0.6 * float(tiles.size()), 4.5)})
	if body != null:
		var tc := t_last + 170
		L.clip(c, {"kind": "root_cinch", "t0": tc, "dur": 480, "at": center})
		L.seg(c, body["id"], {"kind": "struggle", "t0": tc + 90, "dur": 340})
		return tc + 170
	return t_last + 230


static func _glob(c: Dictionary) -> int:
	var t: int = c["t"]
	var tile := _target(c)
	var eff: Dictionary = c["eff"]
	var status := String(eff.get("status", ""))
	var turns := int(eff.get("turns", 1))
	var col := L.status_col(status)
	# a status that ticks is carried as spores; one that holds, as sticky sap
	var cloud := int(Content.STATUSES.get(status, {}).get("tick_dmg", 0)) > 0
	var dist := maxi(1, L.man(c["ppos"], tile))
	var fly := mini(LOB_MS - 20 + 40 * dist, 360)
	var size := 0.8 + 0.1 * float(mini(turns, 5))
	L.seg(c, "player", {"kind": "lunge", "t0": t - 20, "dur": 220, "dir": L.dir_of(c["ppos"], tile), "reach": 0.16})
	L.clip(c, {"kind": "sap_glob", "t0": t, "dur": fly + 320, "fly": fly, "from": c["ppos"], "to": tile,
		"col": col, "cloud": cloud, "size": size, "h": 0.55 + 0.1 * float(dist), "at": tile})
	var t_hit := t + fly
	L.clip(c, {"kind": "sap_splat", "t0": t_hit, "dur": 380 + 40 * mini(turns, 5), "at": tile, "col": col,
		"cloud": cloud, "size": size, "layer": "ground"})
	for i in L.unclaimed(c, ["status", "resisted", "immune", "hook"]):
		var ev: Dictionary = c["events"][i]
		var pe = c["pre_en"].get(ev.get("id"))
		if (pe != null and pe["pos"] == tile) or _on_tile(ev, tile):
			L.claim(c, i, t_hit + 20)
	var e = L.enemy_at(c["pre"], tile)
	if e != null:
		# the glob's weight lands on it, and the colour clings a moment
		L.seg(c, e["id"], {"kind": "squash", "t0": t_hit, "dur": 200})
		L.seg(c, e["id"], {"kind": "tint", "t0": t_hit, "dur": 460, "col": col.lerp(Color.WHITE, 0.2)})
	return t_hit + 140


static func _spike(c: Dictionary) -> int:
	var t: int = c["t"]
	var tile := _target(c)
	var eff: Dictionary = c["eff"]
	var per: Dictionary = eff.get("per", {}) if eff.get("per") is Dictionary else {}
	var feeds := _feeds(c, tile, per)
	var e = L.enemy_at(c["pre"], tile)
	var hits: Array = L.cast_hits(c, e["id"]) if e != null else []
	var amt := int(eff.get("dmg", 3))
	for i in hits:
		amt = maxi(amt, int(c["events"][i].get("amt", 0)))
	var t_hit := t + CRACK_MS
	L.clip(c, {"kind": "floor_crack", "t0": t, "dur": CRACK_MS + 330, "crack": CRACK_MS, "at": tile,
		"feeds": feeds, "layer": "ground"})
	L.clip(c, {"kind": "thorn_erupt", "t0": t_hit - 35, "dur": 400, "lead": 35, "at": tile, "amt": amt,
		"cap": int(per.get("cap", 0)), "crowd": String(per.get("count", "")).begins_with("enemies"),
		"layer": "ground"})
	L.clip(c, {"kind": "clod_burst", "t0": t_hit, "dur": 480, "at": tile, "n": 5 + amt, "puffs": 4, "h": 1.0,
		"spread": 0.9, "flash": true})
	c["reel"]["shakes"].append({"t0": t_hit, "mag": 1.5 + 0.6 * float(amt)})
	if e != null:
		# it feels the ground go: a tremble, then a harder one just before
		L.seg(c, e["id"], {"kind": "shake", "t0": t + 50, "dur": 60, "amt": 0.03})
		L.seg(c, e["id"], {"kind": "shake", "t0": t + 115, "dur": 60, "amt": 0.06})
		for i in hits:
			L.claim(c, i, t_hit, Vector2(0, -1))
	for i in L.unclaimed(c, ["rider"]):
		var ev: Dictionary = c["events"][i]
		if String(ev.get("kind", "")) == "per" and String(ev.get("id", "")) == String(c["aid"]):
			# the count paid: the veins flare gold as they reach the target
			L.claim(c, i, t_hit - 40)
			L.clip(c, {"kind": "spark", "t0": t_hit - 40, "dur": 300, "at": tile, "col": Color("e8c840"), "n": 8})
	return t_hit + 130


## Tiles next to the target holding what a `per` rider counts (its count
## names it: a terrain kind, or enemies), at most the rider's cap - the spike
## draws veins in from each.
static func _feeds(c: Dictionary, tile: Vector2i, per: Dictionary) -> Array:
	var out: Array = []
	if per.is_empty():
		return out
	var what := String(per.get("count", "")).get_slice("_", 0)
	var cap := int(per.get("cap", 4))
	for d in L.DIRS:
		var p: Vector2i = tile + d
		var hit := false
		if what == "enemies":
			hit = L.enemy_at(c["pre"], p) != null
		elif Content.TERRAIN.has(what):
			hit = L.tkind(c["pre"], p) == what
		if hit and out.size() < cap:
			out.append(p)
	return out


static func _warp(c: Dictionary) -> int:
	var t: int = c["t"]
	var o: Vector2i = c["ppos"]
	var to := _target(c)
	var iev := -1
	for i in L.unclaimed(c, ["teleport"]):
		if c["events"][i].get("to") is Vector2i:
			to = c["events"][i]["to"]
		iev = i
		break
	# the target shape decides the road: growth is reached THROUGH the
	# mycelium, a bare tile has to be dug to
	var dig := String(c["adef"].get("target", "")) != "growth"
	var style := "dig" if dig else "mycel"
	var dist := L.man(o, to)
	var sink := 220 if dig else 200
	var travel := mini((110 + 55 * dist) if dig else (90 + 45 * dist), 460)
	var rise := 300 if dig else 280
	var t_go := t + sink - 40
	var t_arr := t_go + travel
	L.seg(c, "player", {"kind": "hide", "t0": t, "dur": t_arr + rise - t})
	if o != to:
		L.move(c, "player", [o, to], t_go, travel)
	L.clip(c, {"kind": "tender_warp", "t0": t, "dur": sink, "at": o, "mode": "out", "style": style})
	L.clip(c, {"kind": "under_thread", "t0": t_go - 40, "dur": 40 + travel + 320, "go": 40, "travel": travel,
		"from": o, "to": to, "style": style, "at": to, "layer": "ground"})
	L.clip(c, {"kind": "tender_warp", "t0": t_arr, "dur": rise, "at": to, "mode": "in", "style": style})
	if dig:
		L.clip(c, {"kind": "clod_burst", "t0": t + int(sink * 0.4), "dur": 420, "at": o, "n": 7, "puffs": 3,
			"h": 0.7, "spread": 0.9})
		L.clip(c, {"kind": "clod_burst", "t0": t_arr + int(rise * 0.25), "dur": 480, "at": to, "n": 11, "puffs": 5,
			"h": 1.05, "spread": 0.8, "seed": 5})
		c["reel"]["shakes"].append({"t0": t_arr + int(rise * 0.25), "mag": 2.5})
	if iev >= 0:
		L.claim(c, iev, t_arr)
	c["warp"] = {"from": o, "to": to, "left": t + sink, "arrive": t_arr}
	c["ppos"] = to
	# whatever the arrival tile does to the tender lands as it surfaces
	for i in L.unclaimed(c, ["damage", "item_pickup", "heal"]):
		var ev: Dictionary = c["events"][i]
		if String(ev["t"]) != "damage" or String(ev.get("who", "")) == "player":
			L.claim(c, i, t_arr + rise / 2)
	return t_arr + rise / 2


static func _plant_origin(c: Dictionary) -> int:
	var t: int = c["t"]
	var w: Dictionary = c.get("warp", {})
	var o: Vector2i = w.get("from", c["p0"])
	# the sprout pushes up just as the thread leaves the tile
	var t_s := maxi(0, int(w.get("left", t - 160)) + 40)
	var sw: Dictionary = c["reel"]["tswap"]
	var kind := String(c["eff"].get("kind", "growth"))
	if sw.has(o) and not sw[o].has("t"):
		kind = String(sw[o]["post"])
		var col: Color = L.TERRAIN_COL.get(kind, LEAF)
		_burst_terrain(c, o, _look(kind), col, int(c["eff"].get("ttl", 3)), false, t_s)
		L.reveal(c, o, t_s + 140)
	for i in L.unclaimed(c, ["terrain", "hook"]):
		if _on_tile(c["events"][i], o):
			L.claim(c, i, t_s + 60)
	return t


static func _shield(c: Dictionary) -> int:
	var t: int = c["t"]
	var amt := int(c["eff"].get("amount", 1))
	L.clip(c, {"kind": "bark_shell", "t0": t, "dur": 620, "at": c["ppos"], "amount": amt, "snap": SNAP_MS})
	var ts := t + SNAP_MS
	for i in L.unclaimed(c, ["shield"]):
		L.claim(c, i, ts)
	L.seg(c, "player", {"kind": "squash", "t0": ts - 20, "dur": 150})
	c["reel"]["shakes"].append({"t0": ts, "mag": 1.0 + 0.5 * float(amt)})
	return ts + 120


static func _thorns(c: Dictionary) -> int:
	var t: int = c["t"]
	var eff: Dictionary = c["eff"]
	var dmg := int(eff.get("dmg", 2))
	var turns := int(eff.get("turns", 3))
	# a harder coat coils faster and snaps out sharper; a longer one lingers
	var burst := maxi(45, 95 - 8 * dmg)
	L.clip(c, {"kind": "thorn_crown", "t0": t, "dur": 400 + 45 * mini(turns, 8), "at": c["ppos"], "dmg": dmg,
		"turns": turns, "burst": burst})
	for i in L.unclaimed(c, ["thorns"]):
		L.claim(c, i, t + burst + 20)
	L.seg(c, "player", {"kind": "squash", "t0": t, "dur": burst * 2})
	c["reel"]["shakes"].append({"t0": t + burst, "mag": 0.8 + 0.45 * float(dmg)})
	return t + burst + 160


static func _anchor(c: Dictionary) -> int:
	var t: int = c["t"]
	var turns := int(c["eff"].get("turns", 4))
	var pp: Vector2i = c["ppos"]
	var t_th := t + 170
	# a little hop, then the stomp the roots drive in on
	L.move(c, "player", [pp, pp], t, t_th - t, 0.22)
	L.seg(c, "player", {"kind": "squash", "t0": t_th - 10, "dur": 200})
	L.clip(c, {"kind": "root_anchor", "t0": t_th - 40, "dur": 640, "lead": 40, "at": pp, "turns": turns,
		"layer": "ground"})
	L.clip(c, {"kind": "clod_burst", "t0": t_th, "dur": 460, "at": pp, "n": 4, "puffs": 6, "h": 0.45, "spread": 1.2})
	for i in L.unclaimed(c, ["anchor"]):
		L.claim(c, i, t_th)
	c["reel"]["shakes"].append({"t0": t_th, "mag": 1.8 + 0.3 * float(turns)})
	return t_th + 110


static func _undim(c: Dictionary) -> int:
	var t: int = c["t"]
	var land := 150
	var lifted := false
	for i in L.unclaimed(c, ["undim"]):
		lifted = true
		L.claim(c, i, t + land)
	var amt := int(c["eff"].get("amount", 1))
	L.clip(c, {"kind": "sun_shaft", "t0": t, "dur": 640 if lifted else 460, "land": land, "at": c["ppos"],
		"amount": amt, "lifted": lifted})
	L.clip(c, {"kind": "sun_pool", "t0": t + land - 20, "dur": 520, "at": c["ppos"], "layer": "ground",
		"amount": amt})
	L.seg(c, "player", {"kind": "flash", "t0": t + land, "dur": 140})
	return t + land + 180


static func _rider_status(c: Dictionary) -> int:
	var t: int = c["t"]
	for i in L.unclaimed(c, ["status", "resisted", "immune"]):
		L.claim(c, i, t + 40)
		var ev: Dictionary = c["events"][i]
		if String(ev["t"]) == "status" and c["pre_en"].has(ev.get("id")):
			L.seg(c, ev["id"], {"kind": "tint", "t0": t + 40, "dur": 380,
				"col": L.status_col(String(ev.get("status", ""))).lerp(Color.WHITE, 0.25)})
	return t + 120


# --- paint -----------------------------------------------------------------------

static func paint(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	match String(cl["kind"]):
		"pod_lob":
			_p_pod(cv, cl, k, V)
		"terrain_burst":
			_p_burst(cv, cl, k, V)
		"root_run":
			_p_run(cv, cl, k, V)
		"root_heave":
			_p_heave(cv, cl, k, V)
		"root_cinch":
			_p_cinch(cv, cl, k, V)
		"sap_glob":
			_p_glob(cv, cl, k, V)
		"sap_splat":
			_p_splat(cv, cl, k, V)
		"floor_crack":
			_p_crack(cv, cl, k, V)
		"thorn_erupt":
			_p_erupt(cv, cl, k, V)
		"clod_burst":
			_p_clods(cv, cl, k, V)
		"tender_warp":
			_p_warp(cv, cl, k, V)
		"under_thread":
			_p_thread(cv, cl, k, V)
		"trail_sprout":
			_p_sprout(cv, cl, k, V)
		"bark_shell":
			_p_shell(cv, cl, k, V)
		"thorn_crown":
			_p_crown(cv, cl, k, V)
		"root_anchor":
			_p_anchor(cv, cl, k, V)
		"sun_shaft":
			_p_shaft(cv, cl, k, V)
		"sun_pool":
			_p_pool(cv, cl, k, V)


# --- drawing helpers ---------------------------------------------------------------

## Where a creature on tile p stands (its feet) and the middle of its body.
static func _feet(V: Dictionary, p) -> Vector2:
	var r := D.tile_rect(V, p)
	return Vector2(r.get_center().x, r.position.y + r.size.y * 0.9)


static func _mid(V: Dictionary, p) -> Vector2:
	var r := D.tile_rect(V, p)
	return Vector2(r.get_center().x, r.position.y + r.size.y * 0.5)


## Per-tile scatter seed, so two clips on different tiles do not match.
static func _seed(p) -> int:
	var q := Vector2i(Vector2(p).round())
	return absi(q.x * 73 + q.y * 151) % 997


## A lob a -> b at u with an apex `h` px high. A throw along the screen's
## vertical cannot show its height, so it also bows out sideways (toward the
## side it is thrown to) - the more vertical the throw, the more it bows.
static func _lob(a: Vector2, b: Vector2, u: float, h: float) -> Vector2:
	var d := b - a
	var vert := 1.0 - absf(d.x) / maxf(1.0, d.length())
	var side := -1.0 if d.x < -0.5 else 1.0
	return D.arc_point(a, b, u, h) + Vector2(side * h * 0.5 * vert * 4.0 * u * (1.0 - u), 0)


## Overshooting ease (0 -> ~1.08 -> 1): things that spring out of the floor.
static func _back(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	var c1 := 1.4
	var y := x - 1.0
	return 1.0 + (c1 + 1.0) * y * y * y + c1 * y * y


static func _ell(cv, c: Vector2, rx: float, ry: float, col: Color) -> void:
	if rx < 0.5 or ry < 0.25 or col.a <= 0.01:
		return
	cv.draw_set_transform(c, 0.0, Vector2(1.0, ry / rx))
	cv.draw_circle(Vector2.ZERO, rx, col)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _ell_ring(cv, c: Vector2, rx: float, ry: float, col: Color, w: float) -> void:
	if rx < 0.5 or ry < 0.25 or col.a <= 0.01:
		return
	cv.draw_set_transform(c, 0.0, Vector2(1.0, ry / rx))
	D.ring(cv, Vector2.ZERO, rx, col, w)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A thick arc segment (a bark plate): the band between radii r0 and r1.
static func _band(cv, c: Vector2, r0: float, r1: float, a0: float, a1: float, col: Color) -> void:
	if col.a <= 0.01 or r1 - r0 < 0.5 or a1 - a0 < 0.02:
		return
	var pts := PackedVector2Array()
	for i in 7:
		var a := lerpf(a0, a1, float(i) / 6.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r1)
	for i in 7:
		var a := lerpf(a1, a0, float(i) / 6.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r0)
	cv.draw_colored_polygon(pts, col)


## A lump of earth: an irregular pentagon (always a simple polygon).
static func _clod(cv, p: Vector2, s: float, rot: float, col: Color) -> void:
	if s < 0.8 or col.a <= 0.01:
		return
	var pts := PackedVector2Array()
	for i in 5:
		var a := rot + TAU * float(i) / 5.0
		pts.append(p + Vector2(cos(a), sin(a)) * s * (0.7 + 0.4 * D.h01(i * 7 + 3)))
	cv.draw_colored_polygon(pts, col)


## A spinning flake (bark chaff, splinters).
static func _flake(cv, p: Vector2, s: float, rot: float, col: Color) -> void:
	if s < 0.8 or col.a <= 0.01:
		return
	var f := Vector2(cos(rot), sin(rot)) * s
	var g := Vector2(-f.y, f.x) * 0.45
	cv.draw_colored_polygon(PackedVector2Array([p - f - g, p + f - g, p + f + g, p - f + g]), col)


## A stroke along `pts` tapering from width w0 to w1 (roots). Falls back to a
## plain polyline if the outline would not triangulate (a very tight bend).
static func _taper(cv, pts: PackedVector2Array, w0: float, w1: float, col: Color) -> void:
	var n := pts.size()
	if n < 2 or col.a <= 0.01 or w0 < 0.5:
		return
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in n:
		var d: Vector2 = pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
		if d.length() < 0.01:
			return
		var s := Vector2(-d.y, d.x).normalized() * maxf(0.6, lerpf(w0, w1, float(i) / float(n - 1))) * 0.5
		left.append(pts[i] + s)
		right.append(pts[i] - s)
	right.reverse()
	var poly := left + right
	if Geometry2D.triangulate_polygon(poly).is_empty():
		cv.draw_polyline(pts, col, maxf(1.0, (w0 + w1) * 0.5), true)
		return
	cv.draw_colored_polygon(poly, col)


## A thorn from base to tip: dark edge, body, a lit stripe.
static func _thorn(cv, base: Vector2, tip: Vector2, w: float, edge: Color, body: Color, hi: Color) -> void:
	var d := tip - base
	if d.length() < 1.5:
		return
	var s := Vector2(-d.y, d.x).normalized()
	D.tri(cv, base - s * w * 0.5, base + s * w * 0.5, tip, edge)
	D.tri(cv, base - s * w * 0.3 + d * 0.04, base + s * w * 0.3 + d * 0.04, base + d * 0.92, body)
	D.line(cv, base - s * w * 0.1 + d * 0.1, base + d * 0.78, hi, maxf(1.0, w * 0.13))


## The tender's own sprite, drawn by a verb that has taken its body over (the
## player track is hidden meanwhile): scaled from the feet like the shell's
## _draw_body, lifted, faded, with a coloured glow over it.
static func _tender(cv, V: Dictionary, tile, sx: float, sy: float, lift: float, alpha: float, glow: float, gcol: Color) -> void:
	var t := D.ts(V)
	var r := D.tile_rect(V, tile)
	var gx := r.get_center().x
	var sh := clampf(sx, 0.2, 1.4) * clampf(1.0 - lift * 0.9, 0.4, 1.0)
	_ell(cv, Vector2(gx, r.position.y + t * 0.86), t * 0.34 * sh, t * 0.14 * sh, Color(0, 0, 0, 0.3 * clampf(alpha, 0.0, 1.0)))
	if alpha <= 0.02 or sx < 0.02 or sy < 0.02:
		return
	var tx = Art.tex("player", int(t))
	if tx == null:
		return
	cv.draw_set_transform(Vector2(gx, r.position.y + t * 0.92 - lift * t), 0.0, Vector2(sx, sy))
	var at := Vector2(-t / 2.0, -t * 0.92)
	cv.draw_texture(tx, at, Color(1, 1, 1, alpha))
	if glow > 0.02:
		var g := 1.0 + 2.0 * glow
		cv.draw_texture(tx, at, Color(gcol.r * g, gcol.g * g, gcol.b * g, glow * alpha * 0.8))
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- painters ------------------------------------------------------------------------

## A seed pod lobbed end over end, trailing wisps of what is inside it; it
## lands, squashes and splits with a flare of its seam.
static func _p_pod(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var ms := k * float(cl["dur"])
	var fly := maxf(1.0, float(cl["fly"]))
	var u := clampf(ms / fly, 0.0, 1.0)
	var col: Color = cl.get("col", Color("9aa0a4"))
	var pal: Dictionary = cl["pal"]
	var a := _mid(V, cl["from"]) + Vector2(0, -t * 0.12)
	var b := _feet(V, cl["to"]) + Vector2(0, -t * 0.16)
	var h := t * float(cl.get("h", 0.8))
	var arc := 4.0 * u * (1.0 - u)
	var ground := _feet(V, cl["from"]).lerp(_feet(V, cl["to"]), u)
	_ell(cv, ground, t * 0.14 * (1.0 - 0.4 * arc), t * 0.06 * (1.0 - 0.4 * arc), Color(0, 0, 0, 0.3))
	if u < 1.0:
		for j in 5:
			var uj := u - 0.06 * float(j + 1)
			if uj <= 0.0:
				break
			var q := _lob(a, b, uj, h) + Vector2(0, -t * 0.03 * float(j))
			cv.draw_circle(q, t * (0.05 + 0.022 * float(j)), D.ca(col.lightened(0.45), 0.6 * (1.0 - float(j) / 5.0)))
		_pod_body(cv, _lob(a, b, u, h), t, u * 9.0, 1.0, 1.0, col, 1.0)
	else:
		var v := clampf((ms - fly) / maxf(1.0, float(cl["dur"]) - fly), 0.0, 1.0)
		_pod_body(cv, b + Vector2(0, t * 0.05 * v), t, 0.0, 1.0 + 0.7 * v, 1.0 - 0.55 * v, col, 1.0 - v)
		D.glow(cv, b, t * (0.2 + 0.25 * v), D.ca(pal["b"], 0.8 * (1.0 - v)), 2)


static func _pod_body(cv, p: Vector2, t: float, rot: float, sx: float, sy: float, col: Color, a: float) -> void:
	if a <= 0.01:
		return
	cv.draw_set_transform(p, rot, Vector2(sx, sy * 0.8))
	cv.draw_circle(Vector2.ZERO, t * 0.17, D.ca(POD.darkened(0.5), a))
	cv.draw_circle(Vector2.ZERO, t * 0.135, D.ca(POD, a))
	# the seam, glowing with what the pod carries
	cv.draw_line(Vector2(-t * 0.13, 0), Vector2(t * 0.13, 0), D.ca(col.lightened(0.55), a), maxf(1.0, t * 0.05), true)
	cv.draw_circle(Vector2(-t * 0.05, -t * 0.07), t * 0.04, D.ca(Color.WHITE, 0.8 * a))
	cv.draw_line(Vector2(0, -t * 0.13), Vector2(t * 0.04, -t * 0.24), D.ca(POD.darkened(0.3), a), maxf(1.0, t * 0.045), true)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## New terrain bursting out: a flash, a shock ring on the floor, then billows
## (or flame tongues) that swell, rise and thin out over the tile the real
## terrain has just appeared on. Thrown off the tender's own body it rings
## the tender instead of covering it, and flings bark chaff.
static func _p_burst(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var at = cl["at"]
	var foot := _feet(V, at)
	var c := foot + Vector2(0, -t * 0.34)
	var col: Color = cl.get("col", Color("9aa0a4"))
	var sz := float(cl.get("size", 1.0))
	var here := bool(cl.get("here", false))
	var seed := _seed(at)
	var f := D.win(k, 0.0, 0.2)
	if f < 1.0:
		D.glow(cv, c, t * (0.2 + 0.4 * D.ease_out(f)), D.ca(col.lightened(0.7), 0.75 * (1.0 - f)), 3)
	var rk := D.win(k, 0.0, 0.45)
	if rk < 1.0:
		var re := D.ease_out(rk) * (1.3 if here else 1.0)
		_ell_ring(cv, foot, t * (0.2 + 0.75 * re), t * (0.08 + 0.3 * re), D.ca(col.lightened(0.5), 0.85 * (1.0 - rk)), t * 0.06)
	if String(cl.get("look", "cloud")) == "flame":
		_flames(cv, foot, t, k, sz, seed, col)
		return
	var n := int(cl.get("n", 10))
	var hi := col.lightened(0.75)
	# a burst on open floor swells from the middle (three puffs keep its
	# heart full); thrown off the tender it rolls OUT as a ring, clear of it
	var core := 0 if here else 3
	# three passes - every shaded underside, then every body, then every
	# highlight - so no puff's shadow lands on a neighbour's lit side
	for lay in 3:
		for i in n + core:
			var h1 := D.h01(seed + i * 13)
			var h2 := D.h01(seed + i * 29 + 5)
			var ang := TAU * (float(i) + 0.4 * h1) / float(n)
			var g := D.ease_out(D.win(k, 0.03 * h2, 0.5 + 0.05 * h2))
			var r0 := t * (0.42 if here else 0.05)
			var r1 := t * sz * ((0.55 + 0.3 * h1) if here else (0.3 + 0.26 * h1))
			if i >= n:
				r1 = t * 0.1 * sz
			var q := c + Vector2(cos(ang), sin(ang) * 0.62) * lerpf(r0, r1, g) + Vector2(0, -t * (0.05 + 0.22 * h2) * g)
			var pr := t * ((0.07 + (0.07 + 0.05 * h2) * g) if here else (0.08 + (0.11 + 0.07 * h2) * sz * g))
			var a := minf(1.0, k * 14.0) * D.tail(k, (0.3 if here else 0.4) + 0.22 * h1) * (0.8 if here else 1.0)
			if lay == 0:
				cv.draw_circle(q + Vector2(0, pr * 0.28), pr, D.ca(col.darkened(0.35), 0.55 * a))
			elif lay == 1:
				cv.draw_circle(q, pr * 0.9, D.ca(col.lightened(0.2), 0.85 * a))
			else:
				cv.draw_circle(q + Vector2(-pr * 0.3, -pr * 0.32), pr * 0.42, D.ca(hi, 0.6 * a))
	if here:
		for i in 8:
			var ang2 := TAU * (float(i) + 0.5 * D.h01(seed + i * 5)) / 8.0
			var u := D.ease_out(D.win(k, 0.0, 0.6))
			var q2 := c + Vector2(cos(ang2), sin(ang2) * 0.7) * t * (0.3 + 0.8 * u) + Vector2(0, t * 0.35 * u * u)
			_flake(cv, q2, t * 0.07, k * 9.0 + float(i), D.ca(BARK_LIGHT if i % 2 == 0 else BARK, D.tail(k, 0.35)))


static func _flames(cv, foot: Vector2, t: float, k: float, sz: float, seed: int, col: Color) -> void:
	var up := D.ease_out(D.win(k, 0.0, 0.3))
	var a := D.tail(k, 0.45)
	D.glow(cv, foot + Vector2(0, -t * 0.3), t * 0.45 * sz * up, D.ca(col, 0.6 * a), 3)
	for i in 5:
		var x := (float(i) - 2.0) * t * 0.14 * sz
		var hh := t * (0.35 + 0.35 * D.h01(seed + i * 3)) * sz * up * (1.0 - 0.15 * absf(float(i) - 2.0))
		var base := foot + Vector2(x, -t * 0.02)
		var tip := base + Vector2(x * 0.3 + sin(k * 12.0 + float(i)) * t * 0.05, -hh)
		D.spike(cv, base, tip, t * 0.2, D.ca(col, a))
		D.spike(cv, base, base.lerp(tip, 0.6), t * 0.1, D.ca(col.lightened(0.6), a))


## A root running under the floor from the tender to where the wall will
## rise: a crack opens behind a travelling ridge of earth.
static func _p_run(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var ms := k * float(cl["dur"])
	var run := maxf(1.0, float(cl["run"]))
	var u := D.ease_io(clampf(ms / run, 0.0, 1.0))
	var fade := 1.0 - clampf((ms - run) / maxf(1.0, float(cl["dur"]) - run), 0.0, 1.0)
	var a := _feet(V, cl["from"]) + Vector2(0, -t * 0.04)
	var b := _feet(V, cl["to"]) + Vector2(0, -t * 0.3)
	var d := b - a
	if d.length() < 1.0:
		D.glow(cv, a, t * 0.3 * fade, D.ca(BARK_LIGHT, 0.5), 2)
		return
	var s := Vector2(-d.y, d.x).normalized()
	var seed := _seed(cl["to"])
	var n := 10
	var pts := PackedVector2Array()
	var hf := u * float(n)
	var head := a
	for i in n + 1:
		var f := float(i) / float(n)
		var p := a.lerp(b, f) + s * (D.h01(seed + i * 11) - 0.5) * t * 0.16 * sin(f * PI)
		if float(i) <= hf:
			pts.append(p)
			head = p
		else:
			var prev: Vector2 = pts[pts.size() - 1] if pts.size() > 0 else a
			head = prev.lerp(p, hf - floorf(hf))
			pts.append(head)
			break
	if pts.size() >= 2:
		cv.draw_polyline(pts, D.ca(SOIL, 0.75 * fade), t * 0.08, true)
		cv.draw_polyline(pts, D.ca(BARK, 0.9 * fade), t * 0.035, true)
	if u < 1.0:
		_ell(cv, head + Vector2(0, t * 0.02), t * 0.2, t * 0.09, D.ca(Color.BLACK, 0.3))
		_ell(cv, head + Vector2(0, -t * 0.02), t * 0.17, t * 0.085, DIRT)
		_ell(cv, head + Vector2(-t * 0.03, -t * 0.05), t * 0.09, t * 0.035, DIRT_LIGHT)


## Roots heaving up out of one floor tile: the floor splits and bulges, then
## twisting roots spring up (overshoot) with a spray of dirt, hold, and fade
## over the real root terrain that has appeared beneath them. `lean` tips
## them toward a caged body; a longer-lived wall grows more, thicker roots.
static func _p_heave(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var at = cl["at"]
	var r := D.tile_rect(V, at)
	var base := Vector2(r.get_center().x, r.position.y + t * 0.9)
	var seed := _seed(at)
	var lean: Vector2 = cl.get("lean", Vector2.ZERO)
	var ttl := float(cl.get("ttl", 4))
	var crack := D.ease_out(D.win(k, 0.0, 0.22))
	var grow := _back(D.win(k, 0.12, 0.42))
	var fade := D.tail(k, 0.62)
	for i in 4:
		var ang := PI * (0.1 + 0.8 * D.h01(seed + i * 17)) + (PI if i % 2 == 0 else 0.0)
		var dv := Vector2(cos(ang), sin(ang) * 0.45)
		var p1 := base + dv * t * 0.24 * crack
		var p2 := p1 + dv.rotated(0.8 * (D.h01(seed + i) - 0.5)) * t * 0.2 * crack
		D.line(cv, base, p1, D.ca(SOIL, 0.85 * fade), t * 0.05)
		D.line(cv, p1, p2, D.ca(SOIL, 0.85 * fade), t * 0.03)
	var bul := D.pulse(D.win(k, 0.0, 0.28))
	_ell(cv, base + Vector2(0, -t * 0.04 * bul), t * 0.32 * bul, t * 0.13 * bul, D.ca(DIRT, 0.95))
	_ell(cv, base + Vector2(-t * 0.05, -t * 0.08 * bul), t * 0.15 * bul, t * 0.05 * bul, D.ca(DIRT_LIGHT, 0.9))
	if grow <= 0.01:
		return
	# a longer-lived wall heaves more roots, and thicker ones
	var n := clampi(1 + int(ttl / 2.0), 3, 5)
	for i in n:
		var fx := (float(i) + 0.5) / float(n) - 0.5
		var h1 := D.h01(seed + i * 7 + 1)
		var hgt := t * (0.6 + 0.22 * h1) * grow
		var b0 := base + Vector2(fx * t * 0.72, t * 0.03 * absf(fx))
		var tip := b0 + Vector2(fx * t * 0.2, -hgt) + lean * t * 0.3 * grow
		var dd := tip - b0
		if dd.length() < 1.5:
			continue
		var sv := Vector2(-dd.y, dd.x).normalized()
		var w := t * (0.17 + 0.012 * ttl) * (1.0 - 0.35 * absf(fx))
		var pts := PackedVector2Array()
		for j in 5:
			var f := float(j) / 4.0
			pts.append(b0.lerp(tip, f) + sv * sin(f * PI * 1.3 + h1 * 6.0) * t * 0.07 * f)
		_taper(cv, pts, w * 1.35, w * 0.3, D.ca(BARK_DARK, fade))
		_taper(cv, pts, w, w * 0.18, D.ca(BARK, fade))
		# a knot, and the light catching one side
		_ell(cv, pts[2], w * 0.22, w * 0.16, D.ca(BARK_DARK, 0.9 * fade))
		D.line(cv, pts[1] - sv * w * 0.25, pts[3] - sv * w * 0.12, D.ca(BARK_LIGHT, 0.75 * fade), maxf(1.0, t * 0.022))


## A cage closing: a coil of root cinches round the body's feet and bars
## curl up in front of it, with a glint where it snaps tight.
static func _p_cinch(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var at = cl["at"]
	var pal: Dictionary = cl["pal"]
	var fc := _feet(V, at) + Vector2(0, -t * 0.05)
	var ci := D.ease_in(D.win(k, 0.0, 0.3))
	var fade := D.tail(k, 0.55)
	var rx := t * lerpf(0.72, 0.38, ci)
	var ry := rx * 0.4
	_ell_ring(cv, fc, rx, ry, D.ca(BARK_DARK, fade), t * 0.12)
	_ell_ring(cv, fc, rx, ry, D.ca(BARK, fade), t * 0.07)
	_ell_ring(cv, fc + Vector2(0, -t * 0.01), rx, ry, D.ca(BARK_LIGHT, 0.8 * fade), t * 0.025)
	for i in 4:
		var ang := PI * (0.12 + 0.76 * float(i) / 3.0)
		var b0 := fc + Vector2(cos(ang) * rx, sin(ang) * ry)
		var up := D.ease_out(D.win(k, 0.18 + 0.04 * float(i), 0.48 + 0.04 * float(i)))
		if up <= 0.01:
			continue
		var tip := b0 + Vector2(-cos(ang) * t * 0.14, -t * 0.55 * up)
		var mid := b0.lerp(tip, 0.5) + Vector2(cos(ang) * t * 0.07, 0)
		var pts := PackedVector2Array([b0, mid, tip])
		_taper(cv, pts, t * 0.13, t * 0.03, D.ca(BARK_DARK, fade))
		_taper(cv, pts, t * 0.08, t * 0.02, D.ca(BARK, fade))
	var sn := D.win(k, 0.28, 0.55)
	if sn > 0.0 and sn < 1.0:
		for s in [-1.0, 1.0]:
			D.twinkle(cv, fc + Vector2(s * rx, 0), t * 0.16 * D.pulse(sn), D.ca(pal["b"], 1.0))


## A glob in flight - sticky sap stretched along its path, or a tumbling ball
## of spores - then the splat: a ring, drops flung up and falling, and sticky
## strands from the body to the floor that thin and snap (or a spore puff).
static func _p_glob(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var ms := k * float(cl["dur"])
	var fly := maxf(1.0, float(cl["fly"]))
	var a := _mid(V, cl["from"]) + Vector2(0, -t * 0.1)
	var b := _mid(V, cl["to"]) + Vector2(0, t * 0.05)
	var col: Color = cl.get("col", Color("c9a63c"))
	var sz := float(cl.get("size", 1.0))
	var cloud := bool(cl.get("cloud", false))
	var h := t * float(cl.get("h", 0.5))
	if ms < fly:
		var u := ms / fly
		var q := _lob(a, b, u, h)
		var vel := _lob(a, b, minf(1.0, u + 0.03), h) - q
		for j in 5:
			var uj := u - 0.05 * float(j + 1)
			if uj <= 0.0:
				break
			cv.draw_circle(_lob(a, b, uj, h), t * (0.07 - 0.01 * float(j)) * sz, D.ca(col, 0.6 * (1.0 - float(j) / 5.0)))
		if cloud:
			D.glow(cv, q, t * 0.3 * sz, D.ca(col.lightened(0.4), 0.45), 2)
			for j in 5:
				var ang := TAU * float(j) / 5.0 + u * 9.0
				var qq := q + Vector2(cos(ang), sin(ang)) * t * 0.085 * sz
				cv.draw_circle(qq, t * 0.085 * sz, col.darkened(0.4))
				cv.draw_circle(qq + Vector2(-t * 0.015, -t * 0.02), t * 0.058 * sz, col.lightened(0.3))
			cv.draw_circle(q, t * 0.06 * sz, col.lightened(0.55))
		else:
			var st := clampf(vel.length() / (t * 0.1), 0.0, 0.6)
			cv.draw_set_transform(q, vel.angle() if vel.length() > 0.01 else 0.0, Vector2(1.0 + st, 1.0 - st * 0.4))
			cv.draw_circle(Vector2.ZERO, t * 0.16 * sz, col.darkened(0.5))
			cv.draw_circle(Vector2.ZERO, t * 0.125 * sz, col)
			cv.draw_circle(Vector2(-t * 0.04, -t * 0.045) * sz, t * 0.05 * sz, Color(1, 1, 1, 0.85))
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var v := clampf((ms - fly) / maxf(1.0, float(cl["dur"]) - fly), 0.0, 1.0)
	var e := D.ease_out(v)
	D.ring(cv, b, t * (0.2 + 0.42 * e), D.ca(col.lightened(0.45), 0.95 * (1.0 - v)), t * 0.065 * (1.0 - 0.5 * v))
	if v < 0.25:
		D.glow(cv, b, t * 0.36, D.ca(col.lightened(0.55), 0.85 * (1.0 - v / 0.25)), 2)
	for i in 7:
		var ang := -PI * (0.05 + 0.9 * float(i) / 6.0)
		var q2 := b + Vector2(cos(ang), sin(ang) * 0.8) * t * 0.52 * e * (0.8 + 0.3 * D.h01(i)) + Vector2(0, t * 0.6 * v * v)
		cv.draw_circle(q2, t * 0.06 * sz * (1.0 - 0.5 * v), D.ca(col, 1.0 - v))
	if cloud:
		for i in 8:
			var ang3 := TAU * D.h01(i * 11 + 3)
			var rr := t * (0.15 + 0.4 * e) * (0.6 + 0.4 * D.h01(i))
			cv.draw_circle(b + Vector2(cos(ang3), sin(ang3) * 0.8) * rr, t * (0.07 + 0.08 * e), D.ca(col, 0.5 * (1.0 - v)))
	else:
		var sn := D.win(v, 0.0, 0.75)
		for i in 3:
			var x := (float(i) - 1.0) * t * 0.26
			var top := b + Vector2(x * 0.5, -t * 0.02)
			var bot := b + Vector2(x, t * 0.42)
			D.line(cv, top, top.lerp(bot, 1.0 - 0.45 * sn), D.ca(col.darkened(0.15), 0.95 * (1.0 - sn)), t * 0.05 * (1.0 - sn) + 1.0)


## The puddle a glob leaves under its target (under the creature).
static func _p_splat(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var f := _feet(V, cl["at"]) + Vector2(0, -t * 0.04)
	var col: Color = cl.get("col", Color("c9a63c"))
	var sz := float(cl.get("size", 1.0))
	var e := D.ease_out(D.win(k, 0.0, 0.3))
	var fade := D.tail(k, 0.5)
	if bool(cl.get("cloud", false)):
		_ell(cv, f, t * 0.46 * e * sz, t * 0.18 * e * sz, D.ca(col, 0.35 * fade))
		_ell_ring(cv, f, t * 0.46 * e * sz, t * 0.18 * e * sz, D.ca(col.lightened(0.3), 0.6 * fade), t * 0.04)
		return
	_ell(cv, f, t * 0.46 * e * sz, t * 0.18 * e * sz, D.ca(col.darkened(0.4), 0.8 * fade))
	_ell(cv, f + Vector2(0, -t * 0.01), t * 0.37 * e * sz, t * 0.13 * e * sz, D.ca(col, 0.85 * fade))
	_ell(cv, f + Vector2(-t * 0.12, -t * 0.035), t * 0.1 * e, t * 0.03 * e, D.ca(Color.WHITE, 0.6 * fade))
	for i in 5:
		var ang := TAU * (float(i) + 0.3 * D.h01(i * 5)) / 5.0
		var q := f + Vector2(cos(ang) * t * 0.55, sin(ang) * t * 0.22) * e
		_ell(cv, q, t * 0.05 * e, t * 0.025 * e, D.ca(col, 0.85 * fade))


## The floor cracking under a spike's target: veins of light run in from what
## feeds it, a glow gathers, and jagged cracks radiate lit from below.
static func _p_crack(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var at = cl["at"]
	var ms := k * float(cl["dur"])
	var cr := maxf(1.0, float(cl["crack"]))
	var ck := clampf(ms / cr, 0.0, 1.0)
	var fade := 1.0 - clampf((ms - cr) / maxf(1.0, float(cl["dur"]) - cr), 0.0, 1.0)
	var pal: Dictionary = cl["pal"]
	var c := _feet(V, at) + Vector2(0, -t * 0.06)
	var seed := _seed(at)
	for fp0 in cl.get("feeds", []):
		var fp := _feet(V, fp0) + Vector2(0, -t * 0.14)
		var head := fp.lerp(c, D.ease_io(D.win(ck, 0.0, 0.8)))
		D.wavy(cv, fp, head, t * 0.07, 1.5, float(seed), D.ca(pal["c"], 0.85 * fade), t * 0.11, 10)
		D.wavy(cv, fp, head, t * 0.07, 1.5, float(seed), D.ca(pal["b"], fade), t * 0.05, 10)
		if ck < 1.0:
			D.glow(cv, head, t * 0.16, D.ca(pal["b"], 0.85), 2)
	_ell(cv, c, t * (0.25 + 0.3 * ck), t * (0.1 + 0.12 * ck), D.ca(pal["a"], 0.45 * ck * fade))
	D.glow(cv, c, t * (0.2 + 0.3 * ck), D.ca(pal["b"], 0.5 * ck * fade), 3)
	for i in 7:
		var h1 := D.h01(seed + i * 19)
		var ang := TAU * (float(i) + 0.5 * h1) / 7.0
		var ln := t * (0.45 + 0.25 * h1) * D.ease_out(ck)
		if ln < 1.0:
			continue
		var d1 := Vector2(cos(ang), sin(ang) * 0.5)
		var p1 := c + d1 * ln * 0.55
		var p2 := p1 + d1.rotated((h1 - 0.5) * 0.9) * ln * 0.5
		var pts := PackedVector2Array([c, p1, p2])
		cv.draw_polyline(pts, D.ca(SOIL, 0.9 * fade), t * 0.085, true)
		cv.draw_polyline(pts, D.ca(pal["b"], ck * fade), t * 0.035, true)


## The thorn spike erupting (drawn UNDER the creature: it punches up through
## the body and out above its head). `lead` ms in, it is most of the way up -
## that is the hit. Barbs by the rider's cap; a crowd-counting rider throws a
## fan of thorns out at the neighbours instead of two flanking spikes.
static func _p_erupt(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var at = cl["at"]
	var ms := k * float(cl["dur"])
	var pal: Dictionary = cl["pal"]
	var amt := float(cl.get("amt", 3))
	var cap := float(cl.get("cap", 1))
	var crowd := bool(cl.get("crowd", false))
	var up := D.ease_out(clampf(ms / 65.0, 0.0, 1.0))
	var down := D.ease_in(D.win(ms, 200.0, float(cl["dur"])))
	var g := up * (1.0 - down)
	var base := _feet(V, at) + Vector2(0, t * 0.04)
	var H := t * (1.0 + 0.12 * amt + 0.08 * cap)
	var W := t * (0.46 + 0.04 * amt)
	var edge: Color = pal["c"]
	var body: Color = pal["a"]
	var hi: Color = pal["b"]
	var ns := 5 if crowd else 2 + int(cap)
	for j in ns:
		var sg := D.ease_out(clampf((ms - 10.0 * float(j)) / 80.0, 0.0, 1.0)) * (1.0 - down)
		if sg <= 0.01:
			continue
		var bx: Vector2
		var tip: Vector2
		if crowd:
			var ang := -PI * (0.06 + 0.88 * float(j) / float(ns - 1))
			bx = base + Vector2(cos(ang) * t * 0.3, 0)
			tip = bx + Vector2(cos(ang) * t * 0.62, sin(ang) * t * 0.55 - t * 0.14) * sg
		else:
			var side := -1.0 if j % 2 == 0 else 1.0
			var f := float(j / 2) + 1.0
			bx = base + Vector2(side * t * (0.14 + 0.1 * f), 0)
			tip = bx + Vector2(side * t * (0.3 + 0.08 * f), -H * (0.58 - 0.1 * f)) * sg
		_thorn(cv, bx, tip, t * 0.22, edge, body, hi)
	var mh := H * (0.75 if crowd else 1.0) * g
	if mh > 1.0:
		# leaning a touch off-centre, so its glint clears the damage number
		var tip2 := base + Vector2(t * 0.14 * g, -mh)
		_thorn(cv, base, tip2, W, edge, body, hi)
		for j in int(cap) + 1:
			var fb := 0.45 + 0.15 * float(j)
			var sd := -1.0 if j % 2 == 0 else 1.0
			var p := base.lerp(tip2, fb)
			var half := W * 0.5 * (1.0 - fb)
			D.tri(cv, p + Vector2(sd * half * 0.6, t * 0.03), p + Vector2(sd * half * 0.6, -t * 0.1),
				p + Vector2(sd * (half + t * 0.17), -t * 0.15), edge)
		var gl := D.win(ms, 20.0, 130.0)
		if gl > 0.0 and gl < 1.0:
			D.twinkle(cv, tip2, t * 0.3 * D.pulse(gl), D.ca(Color.WHITE, 0.95))


## Debris: lumps of earth flung up in arcs and falling back, and dust puffs
## rolling out along the floor. `flash` adds the white pop of an impact.
static func _p_clods(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var at = cl["at"]
	var c := _feet(V, at) + Vector2(0, -t * 0.1)
	var seed := _seed(at) + int(cl.get("seed", 0)) * 101
	var col: Color = cl.get("col", DIRT)
	var hf := float(cl.get("h", 1.0))
	var spread := float(cl.get("spread", 0.6))
	var n := int(cl.get("n", 6))
	var np := int(cl.get("puffs", 0))
	if bool(cl.get("flash", false)) and k < 0.22:
		D.glow(cv, c + Vector2(0, -t * 0.35), t * 0.5 * (1.0 - k / 0.22), D.ca(Color.WHITE, 0.75), 2)
	var g := D.ease_out(k)
	for i in np:
		var ang := TAU * (float(i) + D.h01(seed + i * 3)) / float(np)
		var q := c + Vector2(cos(ang) * t * (0.22 + 0.42 * g), sin(ang) * t * 0.14 * g - t * 0.12 * g)
		cv.draw_circle(q, t * (0.08 + 0.13 * g), D.ca(DIRT_LIGHT.lightened(0.25), 0.45 * (1.0 - k)))
	for i in n:
		var h1 := D.h01(seed + i * 7 + 1)
		var h2 := D.h01(seed + i * 13 + 2)
		var h3 := D.h01(seed + i * 23 + 3)
		var ang := -PI * 0.5 + (h1 - 0.5) * PI * (0.5 + spread)
		var sp := t * (0.7 + 0.6 * h2) * hf
		var u := D.win(k, 0.08 * h3, 0.85 + 0.1 * h3)
		if u <= 0.0:
			continue
		var p := c + Vector2(cos(ang) * sp * u * 1.2, sin(ang) * sp * u * 1.6 + t * 1.5 * hf * u * u)
		_clod(cv, p, t * (0.045 + 0.035 * h3), u * 7.0 + h1 * 5.0, D.ca(col.lerp(DIRT_LIGHT, h2 * 0.6), D.tail(u, 0.55)))


## The tender's body leaving or reaching a tile (the shell's own body is
## hidden meanwhile). mycel/out: a stretch, then it melts down into the floor
## as spores that swirl up and are drawn down after it. mycel/in: the growth
## tile unfurls its leaves and the tender grows up out of it, glowing. dig/
## out: a crouch and a dive into a hole it opens. dig/in: the floor heaves,
## bursts, and the tender springs out and lands.
static func _p_warp(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var at = cl["at"]
	var pal: Dictionary = cl["pal"]
	var feet := _feet(V, at) + Vector2(0, t * 0.02)
	var dig := String(cl.get("style", "")) == "dig"
	var out := String(cl.get("mode", "out")) == "out"
	var seed := _seed(at)
	if out and not dig:
		var ant := D.win(k, 0.0, 0.3)
		var sink := D.ease_in(D.win(k, 0.22, 1.0))
		_ell(cv, feet, t * (0.16 + 0.22 * sink), t * (0.06 + 0.09 * sink), D.ca(pal["c"], 0.8 * sink))
		_ell_ring(cv, feet, t * (0.18 + 0.24 * sink), t * (0.07 + 0.1 * sink), D.ca(pal["a"], 0.95 * sink), t * 0.05)
		_tender(cv, V, at, 1.0 + 0.35 * sink - 0.06 * D.pulse(ant), (1.0 + 0.1 * D.pulse(ant)) * (1.0 - 0.95 * sink),
			0.0, 1.0 - 0.6 * sink, 0.25 + 0.75 * sink, pal["b"])
		for i in 12:
			var h1 := D.h01(seed + i * 5)
			var h2 := D.h01(seed + i * 11 + 1)
			var h3 := D.h01(seed + i * 17 + 2)
			var st := feet + Vector2((h1 - 0.5) * t * 0.55, -t * (0.15 + 0.6 * h2))
			var rise := D.ease_out(D.win(k, 0.2, 0.6))
			var suck := D.ease_in(D.win(k, 0.45 + 0.15 * h3, 1.0))
			var p := st + Vector2((h1 - 0.5) * t * 0.5 * rise, -t * 0.22 * rise)
			p = p.lerp(feet, suck)
			var a := D.win(k, 0.2, 0.4) * (1.0 - 0.7 * suck)
			cv.draw_circle(p, t * 0.042 * (1.0 - 0.5 * suck), D.ca(pal["b"] if i % 3 != 0 else pal["a"], a))
	elif not out and not dig:
		var bloom := D.ease_out(D.win(k, 0.0, 0.4))
		var grow := _back(D.win(k, 0.08, 0.72))
		var lf := D.tail(k, 0.45)
		for i in 6:
			var ang := TAU * float(i) / 6.0 + 0.3
			var q := feet + Vector2(cos(ang) * t * 0.36, sin(ang) * t * 0.15) * bloom
			D.leaf(cv, q, ang, t * 0.3 * bloom, D.ca(LEAF if i % 2 == 0 else LEAF.lightened(0.3), lf))
		var rk := D.ease_out(D.win(k, 0.0, 0.6))
		_ell_ring(cv, feet, t * (0.2 + 0.55 * rk), t * (0.08 + 0.22 * rk), D.ca(pal["b"], 0.9 * (1.0 - rk)), t * 0.05)
		for i in 10:
			var h1 := D.h01(seed + i * 7 + 4)
			var u := D.win(k, 0.05 * float(i % 5), 0.5 + 0.05 * float(i % 5))
			if u <= 0.0 or u >= 1.0:
				continue
			var q2 := feet + Vector2((h1 - 0.5) * t * 0.7 * (1.0 - u), -t * (0.1 + 0.75 * u))
			cv.draw_circle(q2, t * 0.04, D.ca(pal["b"], D.pulse(u)))
		_tender(cv, V, at, lerpf(1.35, 1.0, D.ease_out(D.win(k, 0.08, 0.72))), maxf(0.02, grow), 0.0,
			minf(1.0, 0.35 + k * 2.5), 1.0 - D.win(k, 0.35, 1.0), pal["b"])
	elif out:
		var crouch := D.pulse(D.win(k, 0.0, 0.4))
		var dive := D.ease_in(D.win(k, 0.3, 1.0))
		var hole := D.ease_out(D.win(k, 0.12, 0.45))
		_ell(cv, feet, t * 0.36 * hole, t * 0.15 * hole, D.ca(SOIL, 0.95))
		_ell_ring(cv, feet, t * 0.38 * hole, t * 0.16 * hole, D.ca(DIRT_LIGHT, 0.95), t * 0.07)
		var sc := 1.0 - 0.85 * dive
		_tender(cv, V, at, (1.0 + 0.14 * crouch) * sc, (1.0 - 0.2 * crouch) * sc, -0.14 * dive, 1.0 - 0.4 * dive, 0.0, pal["b"])
	else:
		var bul := D.pulse(D.win(k, 0.0, 0.3))
		var pop := D.win(k, 0.25, 0.8)
		var hole := 1.0 - D.ease_in(D.win(k, 0.45, 1.0))
		if k < 0.27:
			for i in 4:
				var ang := TAU * (float(i) + D.h01(seed + i)) / 4.0
				D.line(cv, feet, feet + Vector2(cos(ang) * t * 0.35, sin(ang) * t * 0.15) * bul, D.ca(SOIL, 0.9), t * 0.045)
			_ell(cv, feet + Vector2(0, -t * 0.05 * bul), t * 0.34 * bul, t * 0.16 * bul, DIRT)
			_ell(cv, feet + Vector2(-t * 0.05, -t * 0.1 * bul), t * 0.16 * bul, t * 0.06 * bul, DIRT_LIGHT)
		else:
			_ell(cv, feet, t * 0.36 * hole, t * 0.15 * hole, D.ca(SOIL, 0.95))
			_ell_ring(cv, feet, t * 0.38 * hole, t * 0.16 * hole, D.ca(DIRT_LIGHT, 0.95), t * 0.07)
			var land := D.pulse(D.win(k, 0.78, 1.0))
			var arc := sin(pop * PI)
			var sy := (0.35 + 0.65 * D.ease_out(D.win(k, 0.25, 0.45))) * (1.0 + 0.14 * arc) * (1.0 - 0.16 * land)
			var sx := (1.0 - 0.08 * arc) * (1.0 + 0.14 * land)
			_tender(cv, V, at, sx, sy, 0.36 * arc, minf(1.0, (k - 0.25) * 8.0), 0.0, pal["b"])


## The road between the two tiles, under the floor. mycel: a glowing root-
## thread snakes from the old tile to the new one with hyphae branching off
## behind its bright head, then fades. dig: the hole closes behind, and a
## mound of earth heaves across, leaving a crack that fades.
static func _p_thread(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var ms := k * float(cl["dur"])
	var go := float(cl.get("go", 0))
	var travel := maxf(1.0, float(cl["travel"]))
	var u := D.ease_io(clampf((ms - go) / travel, 0.0, 1.0))
	var after := clampf((ms - go - travel) / maxf(1.0, float(cl["dur"]) - go - travel), 0.0, 1.0)
	var fade := 1.0 - after
	var pal: Dictionary = cl["pal"]
	var a := _feet(V, cl["from"]) + Vector2(0, -t * 0.06)
	var b := _feet(V, cl["to"]) + Vector2(0, -t * 0.06)
	var dig := String(cl.get("style", "")) == "dig"
	var seed := _seed(cl["to"]) + _seed(cl["from"])
	if dig:
		var hc := 1.0 - D.win(ms, 0.0, 240.0)
		_ell(cv, a, t * 0.36 * hc, t * 0.15 * hc, D.ca(SOIL, 0.95))
		_ell_ring(cv, a, t * 0.38 * hc, t * 0.16 * hc, D.ca(DIRT_LIGHT, 0.95), t * 0.07)
	var d := b - a
	if d.length() < 1.0:
		D.glow(cv, a, t * 0.3 * fade, D.ca(pal["a"], 0.6), 2)
		return
	var s := Vector2(-d.y, d.x).normalized()
	var n := clampi(int(d.length() / (t * 0.25)), 6, 22)
	var amp := t * (0.05 if dig else 0.14)
	var all := PackedVector2Array()
	for i in n + 1:
		var f := float(i) / float(n)
		var wob := sin(f * PI * 2.3 + float(seed)) * amp * sin(f * PI) \
			+ (D.h01(seed + i * 7) - 0.5) * t * (0.1 if dig else 0.05) * sin(f * PI)
		all.append(a.lerp(b, f) + s * wob)
	var hf := u * float(n)
	var hi := mini(int(hf), n)
	var pts := PackedVector2Array()
	for i in hi + 1:
		pts.append(all[i])
	var head: Vector2 = all[hi].lerp(all[mini(hi + 1, n)], hf - float(hi))
	if u < 1.0:
		pts.append(head)
	if dig:
		# the tunnel: a ridge of turned-up earth that swells toward the moving
		# mound like a wake, with a crack down its spine; it settles and thins
		if pts.size() >= 2 and fade > 0.01:
			var wh := t * (0.52 if u < 1.0 else 0.26) * (0.4 + 0.6 * fade)
			var wt := t * 0.1 * fade + 1.0
			var ridge := PackedVector2Array()
			for p in pts:
				ridge.append(p + Vector2(0, -t * 0.035))
			_taper(cv, pts, wt, wh, D.ca(DIRT, 0.95 * fade))
			_taper(cv, ridge, wt * 0.5, wh * 0.45, D.ca(DIRT_LIGHT, 0.9 * fade))
			cv.draw_polyline(pts, D.ca(SOIL, 0.85 * fade), t * 0.03, true)
		if u > 0.0 and u < 1.0:
			# the mound: a dome of earth heaving along, shedding crumbs
			var bob := absf(sin(ms * 0.05)) * t * 0.04
			var rx := t * 0.34
			var ry := t * 0.26 + bob
			_ell(cv, head + Vector2(0, t * 0.02), rx * 1.12, t * 0.13, D.ca(Color.BLACK, 0.35))
			var dome := PackedVector2Array()
			for i in 9:
				var ang := PI + PI * float(i) / 8.0
				dome.append(head + Vector2(cos(ang) * rx, sin(ang) * ry))
			cv.draw_colored_polygon(dome, DIRT)
			cv.draw_arc(head + Vector2(0, -ry * 0.1), rx * 0.72, PI * 1.12, PI * 1.55, 6, D.ca(DIRT_LIGHT, 0.95), t * 0.07, true)
			D.line(cv, head + Vector2(-rx * 0.1, -ry * 0.9), head + Vector2(rx * 0.25, -ry * 0.35), D.ca(SOIL, 0.8), t * 0.03)
			for i in 4:
				var ph := fposmod(ms * 0.006 + float(i) / 4.0, 1.0)
				var sd := -1.0 if i % 2 == 0 else 1.0
				var q := head + Vector2(sd * t * (0.15 + 0.22 * ph), -t * 0.15 - t * 0.35 * sin(ph * PI))
				_clod(cv, q, t * 0.05, ph * 6.0, D.ca(DIRT_LIGHT, 1.0 - ph))
		return
	if pts.size() >= 2:
		cv.draw_polyline(pts, D.ca(pal["c"], 0.6 * fade), t * 0.14, true)
		cv.draw_polyline(pts, D.ca(pal["a"], 0.9 * fade), t * 0.07, true)
		cv.draw_polyline(pts, D.ca(pal["b"], fade), t * 0.03, true)
	var dn := d.normalized()
	for j in 7:
		var f2 := (float(j) + 0.6) / 7.5
		if u < f2:
			break
		var p0: Vector2 = all[mini(int(f2 * float(n)), n)]
		var gg := D.ease_out(clampf((u - f2) * 5.0, 0.0, 1.0))
		var side := 1.0 if j % 2 == 0 else -1.0
		var dir := (s * side + dn * (D.h01(seed + j) - 0.3)).normalized()
		var p1 := p0 + dir * t * (0.16 + 0.12 * D.h01(seed + j * 3)) * gg
		D.line(cv, p0, p1, D.ca(pal["a"], 0.85 * fade), t * 0.03)
		cv.draw_circle(p1, t * 0.03 * gg, D.ca(pal["b"], 0.9 * fade))
	if u > 0.0 and u < 1.0:
		D.glow(cv, head, t * 0.28, D.ca(pal["b"], 0.9), 3)
		D.twinkle(cv, head, t * 0.17, Color(1, 1, 1, 0.95))
	if u >= 1.0:
		D.glow(cv, b, t * 0.42 * fade, D.ca(pal["a"], 0.55), 2)


## A sprout pushing up out of a tile: spores settle, the floor greens in a
## ring, a stem springs up and two leaves unfold, a glint - then it fades
## into the real terrain that has appeared under it.
static func _p_sprout(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var at = cl["at"]
	var base := _feet(V, at) + Vector2(0, -t * 0.08)
	var col: Color = cl.get("col", LEAF)
	var pal: Dictionary = cl["pal"]
	var g := _back(D.win(k, 0.05, 0.42))
	var unf := D.ease_out(D.win(k, 0.2, 0.55))
	var fade := D.tail(k, 0.62)
	var rk := D.ease_out(D.win(k, 0.1, 0.6))
	_ell_ring(cv, base, t * (0.14 + 0.4 * rk), t * (0.06 + 0.16 * rk), D.ca(col.lightened(0.35), 0.9 * (1.0 - rk)), t * 0.05)
	for i in 5:
		var u := D.win(k, 0.04 * float(i), 0.3 + 0.04 * float(i))
		if u <= 0.0 or u >= 1.0:
			continue
		var q := base + Vector2((D.h01(i * 3 + 1) - 0.5) * t * 0.5, -t * 0.6 * (1.0 - u))
		cv.draw_circle(q, t * 0.04, D.ca(pal["b"], 0.9))
	if g <= 0.02:
		return
	var top := base + Vector2(t * 0.03 * sin(k * 6.0), -t * 0.42 * g)
	D.line(cv, base, top, D.ca(col.darkened(0.4), fade), t * 0.08)
	D.line(cv, base, top, D.ca(col, fade), t * 0.04)
	for sd in [-1.0, 1.0]:
		var ang: float = -PI * 0.5 + sd * (0.25 + 1.0 * unf)
		D.leaf(cv, top + Vector2(cos(ang), sin(ang)) * t * 0.13 * unf, ang, t * 0.32 * unf,
			D.ca(col.lightened(0.2) if sd > 0.0 else col, fade))
	var gl := D.win(k, 0.3, 0.75)
	if gl > 0.0 and gl < 1.0:
		D.twinkle(cv, top + Vector2(t * 0.2, -t * 0.1), t * 0.13 * D.pulse(gl), D.ca(pal["b"], 1.0))


## Bark plates fly in round the tender, spinning, and SNAP shut into a shell
## (seams flare, splinters fly, a ring); then a blue shimmer sweeps over the
## shell and it melts into the standing shield. More shield, more and heavier
## plates.
static func _p_shell(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var c := _mid(V, cl["at"])
	var ms := k * float(cl["dur"])
	var snap := maxf(1.0, float(cl.get("snap", SNAP_MS)))
	var amt := clampi(int(cl.get("amount", 2)), 1, 5)
	var n := 1 + 2 * amt
	var th := t * (0.13 + 0.04 * float(amt))
	var rr := t * 0.5
	var u := clampf(ms / snap, 0.0, 1.0)
	var fly := D.ease_in(u)
	var bk := clampf((ms - snap) / 140.0, 0.0, 1.0)
	var bounce := sin(bk * PI) * (1.0 - bk) if ms >= snap else 0.0
	var r := lerpf(t * 1.15, rr, fly) - t * 0.06 * bounce
	var spin := (1.0 - fly) * 1.5
	var sh := D.win(ms, snap + 60.0, float(cl["dur"]))
	var fade := 1.0 - D.ease_in(D.win(sh, 0.3, 1.0))
	var blue := D.win(sh, 0.0, 0.5)
	var a_in := clampf(u * 4.0, 0.0, 1.0) * fade
	var half := PI / float(n) * 0.88
	var body := BARK.lerp(SHIELD, 0.75 * blue)
	var edge := BARK_DARK.lerp(SHIELD.darkened(0.45), 0.75 * blue)
	var rim := BARK_LIGHT.lerp(SHIELD_HI, blue)
	for i in n:
		var md := -PI * 0.5 + TAU * float(i) / float(n) + spin
		_band(cv, c, r - th * 0.5, r + th * 0.5, md - half, md + half, D.ca(edge, a_in))
		_band(cv, c, r - th * 0.32, r + th * 0.34, md - half * 0.88, md + half * 0.88, D.ca(body, a_in))
		# grain along the plate, and its lit outer rim
		cv.draw_arc(c, r - th * 0.02, md - half * 0.6, md + half * 0.5, 5, D.ca(edge, 0.7 * a_in), maxf(1.0, t * 0.022), true)
		cv.draw_arc(c, r + th * 0.24, md - half * 0.72, md + half * 0.72, 6, D.ca(rim, a_in), maxf(1.0, t * 0.035), true)
	if ms >= snap and ms < snap + 200.0:
		# the snap: each seam flares and spits a splinter
		var s := (ms - snap) / 200.0
		for i in n:
			var ang := -PI * 0.5 + TAU * (float(i) + 0.5) / float(n)
			var dv := Vector2(cos(ang), sin(ang))
			D.twinkle(cv, c + dv * rr, t * 0.2 * (1.0 - s), D.ca(Color.WHITE, 1.0 - s))
			_flake(cv, c + dv * (rr + t * 0.6 * D.ease_out(s)), t * 0.06, s * 8.0 + float(i), D.ca(BARK_LIGHT, 1.0 - s))
		D.ring(cv, c, rr + th * 0.5 + t * 0.4 * D.ease_out(s), D.ca(BARK_LIGHT, 0.8 * (1.0 - s)), t * 0.04)
	if sh > 0.0 and sh < 1.0:
		var sa := D.pulse(sh)
		cv.draw_circle(c, rr * 0.95, D.ca(SHIELD, 0.2 * sa))
		var ang2 := -PI * 0.8 + sh * TAU * 0.85
		cv.draw_arc(c, rr + th * 0.1, ang2 - 0.7, ang2 + 0.7, 10, D.ca(SHIELD_HI, 0.95 * sa), t * 0.075, true)
		D.ring(cv, c, rr + t * (0.05 + 0.35 * D.ease_out(sh)), D.ca(SHIELD, 0.85 * (1.0 - sh)), t * 0.05)


## Thorns: vines coil tight round the tender, then spikes BURST out with a
## glint and a shock ring, and draw back into a slowly turning crown that
## fades into the standing coat. Harder thorns are more, longer, thinner and
## whiter at the tip; a longer coat braids a thicker crown and lingers.
static func _p_crown(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var c := _mid(V, cl["at"])
	var ms := k * float(cl["dur"])
	var pal: Dictionary = cl["pal"]
	var dmg := float(cl.get("dmg", 2))
	var turns := float(cl.get("turns", 3))
	var bt := maxf(1.0, float(cl.get("burst", 70)))
	var n := clampi(6 + 2 * int(dmg), 8, 16)
	var reach := t * (0.26 + 0.075 * dmg)
	var w := t * maxf(0.11, 0.22 - 0.018 * dmg)
	var r0 := t * 0.36
	var coil := D.ease_in(clampf(ms / bt, 0.0, 1.0))
	var shoot := D.ease_out(clampf((ms - bt) / 60.0, 0.0, 1.0))
	var settle := D.ease_io(D.win(ms, bt + 80.0, bt + 250.0))
	var fade := 1.0 - D.ease_in(D.win(ms, bt + 190.0 + 25.0 * turns, float(cl["dur"])))
	var rot := ms * 0.0005 * (1.0 + 0.2 * turns)
	var body := THORN.lerp(LEAF, 0.4)
	var edge := BARK_DARK
	var hi := LEAF.lightened(0.25)
	# a harder coat's points go white-hot as they burst
	var tipc: Color = (pal["b"] as Color).lerp(Color.WHITE, clampf((dmg - 2.0) / 3.0, 0.0, 1.0))
	if ms < bt + 50.0:
		var cr := r0 * (1.2 - 0.3 * coil)
		D.ring(cv, c, cr, D.ca(edge, 0.9), t * 0.12)
		D.ring(cv, c, cr, D.ca(body, 0.95), t * 0.06)
	var crown := D.ease_out(D.win(ms, bt, bt + 150.0))
	if crown > 0.0:
		D.ring(cv, c, r0, D.ca(edge, 0.9 * fade * crown), t * (0.07 + 0.012 * turns))
		D.ring(cv, c, r0, D.ca(body, fade * crown), t * (0.035 + 0.008 * turns))
	for i in n:
		var ang := -PI * 0.5 + TAU * float(i) / float(n) + rot
		var dv := Vector2(cos(ang), sin(ang))
		var jag := 0.8 + 0.4 * D.h01(i * 7 + 3)
		var ln := t * 0.08 * (1.0 - 0.5 * coil)
		if ms >= bt:
			ln = t * 0.08 + reach * jag * shoot * (1.0 - 0.68 * settle)
		var bs := c + dv * r0
		_thorn(cv, bs, bs + dv * ln, w * (1.0 - 0.2 * settle), D.ca(edge, fade), D.ca(body, fade), D.ca(hi, fade))
	var bk := D.win(ms, bt, bt + 200.0)
	if bk > 0.0 and bk < 1.0:
		D.ring(cv, c, r0 + reach * (0.5 + 0.9 * D.ease_out(bk)), D.ca(hi, 0.85 * (1.0 - bk)), t * 0.045 * (1.0 - bk) + 1.0)
		if bk < 0.5:
			var tw := 1.0 - bk / 0.5
			for i in n:
				var ang2 := -PI * 0.5 + TAU * float(i) / float(n) + rot
				var jag2 := 0.8 + 0.4 * D.h01(i * 7 + 3)
				var tip := c + Vector2(cos(ang2), sin(ang2)) * (r0 + t * 0.08 + reach * jag2 * shoot)
				D.twinkle(cv, tip, t * (0.07 + 0.012 * dmg) * tw, D.ca(tipc, 0.95))


## Anchor: at the stomp (`lead` ms in) roots spear out from the feet into the
## floor, biting in at the tips, and a dust ring rolls out; a longer anchor
## drives more and longer roots, and past the base four turns cracks stone
## slabs up round the ring.
static func _p_anchor(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var at = cl["at"]
	var foot := _feet(V, at) + Vector2(0, -t * 0.02)
	var ms := k * float(cl["dur"])
	var lead := float(cl.get("lead", 40))
	var turns := float(cl.get("turns", 4))
	var seed := _seed(at)
	var drive := D.ease_out(D.win(ms, lead - 15.0, lead + 80.0))
	var fade := 1.0 - D.ease_in(D.win(ms, lead + 260.0, float(cl["dur"])))
	var n := clampi(3 + int(turns), 5, 10)
	var ln := t * (0.55 + 0.06 * minf(turns, 8.0))
	var th := D.win(ms, lead, lead + 330.0)
	if th > 0.0 and th < 1.0:
		var e := D.ease_out(th)
		_ell(cv, foot, t * (0.3 + 0.95 * e), t * (0.12 + 0.4 * e), D.ca(DIRT_LIGHT, 0.3 * (1.0 - th)))
		_ell_ring(cv, foot, t * (0.3 + 0.95 * e), t * (0.12 + 0.4 * e), D.ca(DIRT_LIGHT.lightened(0.2), 0.95 * (1.0 - th)), t * 0.1 * (1.0 - th) + 1.0)
		if th < 0.2:
			_ell(cv, foot, t * 0.45, t * 0.2, D.ca(BARK_LIGHT, 0.8 * (1.0 - th / 0.2)))
	var slabs := clampi(int(turns) - 4, 0, 4)
	for i in slabs:
		var ang := PI * (-0.08 + 1.16 * (float(i) + 0.5) / float(slabs))
		var p := foot + Vector2(cos(ang) * t * 0.7, sin(ang) * t * 0.32)
		var up := _back(D.win(ms, lead + 10.0 * float(i), lead + 130.0 + 10.0 * float(i)))
		var hh := t * (0.4 + 0.12 * D.h01(seed + i)) * up
		if hh > 1.0:
			var sd := 1.0 if cos(ang) > 0.0 else -1.0
			D.line(cv, foot, p, D.ca(SOIL, 0.8 * fade), t * 0.04)
			var slab := PackedVector2Array([p + Vector2(-t * 0.17, t * 0.03), p + Vector2(t * 0.17, t * 0.03),
				p + Vector2(t * 0.1 + sd * t * 0.07, -hh), p + Vector2(-t * 0.09 + sd * t * 0.07, -hh * 0.78)])
			cv.draw_colored_polygon(slab, D.ca(STONE.darkened(0.6), fade))
			var inner := PackedVector2Array([p + Vector2(-t * 0.12, 0), p + Vector2(t * 0.12, 0),
				p + Vector2(t * 0.07 + sd * t * 0.07, -hh * 0.9), p + Vector2(-t * 0.06 + sd * t * 0.07, -hh * 0.72)])
			cv.draw_colored_polygon(inner, D.ca(STONE, fade))
			D.line(cv, p + Vector2(-t * 0.06 + sd * t * 0.07, -hh * 0.7), p + Vector2(t * 0.07 + sd * t * 0.07, -hh * 0.88),
				D.ca(STONE.lightened(0.5), fade), t * 0.04)
	if drive <= 0.01:
		return
	for i in n:
		var h1 := D.h01(seed + i * 9)
		var ang := PI * (-0.15 + 1.3 * (float(i) + 0.5) / float(n))
		var dv := Vector2(cos(ang), sin(ang) * 0.5)
		var tip := foot + dv * ln * (0.75 + 0.35 * h1) * drive
		var dd := tip - foot
		if dd.length() < 1.5:
			continue
		var sv := Vector2(-dd.y, dd.x).normalized()
		var pts := PackedVector2Array()
		for j in 4:
			var f := float(j) / 3.0
			pts.append(foot.lerp(tip, f) + sv * sin(f * PI + h1 * 4.0) * t * 0.05 * f)
		_taper(cv, pts, t * 0.17, t * 0.04, D.ca(BARK_DARK, fade))
		_taper(cv, pts, t * 0.1, t * 0.025, D.ca(BARK.lightened(0.15), fade))
		D.line(cv, pts[0] - sv * t * 0.02, pts[2] - sv * t * 0.015, D.ca(BARK_LIGHT, 0.85 * fade), t * 0.025)
		if drive > 0.9:
			_ell(cv, tip, t * 0.06, t * 0.03, D.ca(SOIL, 0.85 * fade))


## A sunbeam dropping from the top of the map onto the tender: the smog
## haze round it is pushed back as it lands (only when the cast lifted a
## stage; when the sky was already clear there is nothing to part), a bloom
## of warm light and a burst of rays, motes drifting down the light.
static func _p_shaft(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var at = cl["at"]
	var c := _mid(V, at)
	var foot := _feet(V, at)
	var ms := k * float(cl["dur"])
	var land := maxf(1.0, float(cl.get("land", 150)))
	var pal: Dictionary = cl["pal"]
	var amt := float(cl.get("amount", 1))
	var lifted := bool(cl.get("lifted", true))
	var desc := D.ease_in(clampf(ms / land, 0.0, 1.0))
	var after := D.win(ms, land, float(cl["dur"]))
	var fade := 1.0 - D.ease_out(D.win(after, 0.15, 0.85))
	if lifted:
		var push := D.ease_out(after)
		for i in 10:
			var h1 := D.h01(i * 7 + 2)
			var ang := TAU * (float(i) + 0.3 * h1) / 10.0
			var rr := t * (0.6 + 0.35 * h1 + 1.5 * push)
			var q := c + Vector2(cos(ang), sin(ang) * 0.62) * rr
			var a := D.win(ms, 0.0, land * 0.6) * (1.0 - push)
			cv.draw_circle(q, t * (0.24 + 0.1 * h1), D.ca(HAZE, 0.45 * a))
	var top_y := maxf(foot.y - t * 5.0, float(V["oy"]))
	var top := Vector2(foot.x - (foot.y - top_y) * 0.14, top_y)
	var bot := top.lerp(foot + Vector2(0, t * 0.05), desc)
	var w1 := t * (0.3 + 0.08 * amt) * (1.0 + 0.4 * D.ease_out(after))
	var w0 := w1 * 0.5
	if bot.y - top.y > 1.0 and fade > 0.01:
		cv.draw_colored_polygon(PackedVector2Array([top - Vector2(w0, 0), top + Vector2(w0, 0),
			bot + Vector2(w1, 0), bot - Vector2(w1, 0)]), D.ca(pal["a"], 0.3 * fade))
		cv.draw_colored_polygon(PackedVector2Array([top - Vector2(w0 * 0.4, 0), top + Vector2(w0 * 0.4, 0),
			bot + Vector2(w1 * 0.36, 0), bot - Vector2(w1 * 0.36, 0)]), D.ca(pal["b"], 0.45 * fade))
		for i in 7:
			var uu := fposmod(D.h01(i * 5 + 1) + ms * 0.0022, 1.0)
			var q2 := top.lerp(bot, uu) + Vector2((D.h01(i * 3) - 0.5) * lerpf(w0, w1, uu) * 1.4, 0)
			D.twinkle(cv, q2, t * 0.07, D.ca(Color.WHITE, 0.9 * fade * D.pulse(uu)))
	if ms < land:
		D.glow(cv, bot, t * 0.22 * desc, D.ca(pal["b"], 0.9), 2)
	if after > 0.0 and after < 1.0:
		var bl := D.pulse(D.win(after, 0.0, 0.6))
		D.glow(cv, c, t * (0.35 + 0.4 * bl), D.ca(pal["b"], 0.6 * bl), 3)
		for i in 8:
			var ang2 := TAU * float(i) / 8.0 + after * 0.6
			var dv := Vector2(cos(ang2), sin(ang2))
			var r0 := t * (0.4 + 0.3 * D.ease_out(after))
			D.line(cv, c + dv * r0, c + dv * (r0 + t * 0.3 * (1.0 - after)), D.ca(pal["a"], 0.95 * (1.0 - after)), t * 0.05)


## The warm pool of light the beam leaves on the floor, rolling out.
static func _p_pool(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var foot := _feet(V, cl["at"])
	var pal: Dictionary = cl["pal"]
	var amt := float(cl.get("amount", 1))
	var e := D.ease_out(k)
	var big := 1.0 + 0.2 * (amt - 1.0)
	_ell(cv, foot, t * (0.35 + 0.35 * e), t * (0.15 + 0.15 * e), D.ca(pal["b"], 0.5 * (1.0 - k)))
	_ell_ring(cv, foot, t * (0.3 + 1.4 * e) * big, t * (0.13 + 0.6 * e) * big, D.ca(pal["a"], 0.95 * (1.0 - k)), t * 0.07)
	_ell_ring(cv, foot, t * (0.2 + 0.85 * e) * big, t * (0.09 + 0.36 * e) * big, D.ca(pal["b"], 0.8 * (1.0 - k)), t * 0.035)
