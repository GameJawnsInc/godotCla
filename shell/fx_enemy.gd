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
##
## The look is industrial: these are machines in a polluted world, so a turn
## is drills and sparks, hydraulics, oil, smoke and magnets. Every verb has a
## wind-up, one travelling or expanding motion and a crisp impact at the
## exact moment its event lands, then clears within about half a second.
## Flavour comes from DATA, never from an enemy kind: the gait a machine
## walks with is read off its idle style (itself read off the row's traits)
## and the row's `slow` flag, a spit's range off the row, a strain's look off
## the status id, a slam's size off the intent's numbers.
##
## A verb that lands something may start a little after its slot (_start):
## impacts fall one BEAT_MS apart, in the machines' own order, so a pack's
## turn reads machine by machine, and a verb aimed at the tender waits for a
## crane's haul to finish. c.hit stays relative to the slot, c.t.
##
## Some events cannot be attributed by the director's cursor - they carry no
## enemy id (gummed, shield_absorb, flood, ignite_all), or name only the
## attacker's KIND (the tender's damage: a pack of drill bots all match the
## first one), or name the victim of a hook the verb set off. The verb that
## caused one TAKES it (_take_event / _take_blow / _take_absorb), in stream
## order, which is the machines' order; a machine that left the board before
## its turn (_gone) draws nothing.
##
## Clip kinds are prefixed "en_" so they never collide with another family's.

const Content := preload("res://sim/content.gd")
const L := preload("res://shell/anim_lib.gd")
const D := preload("res://shell/anim_draw.gd")
const Art := preload("res://shell/svg_art.gd")

const INTENTS := ["idle", "move", "advance", "attack", "slam", "quake", "flood", "ignite_all", "gather",
	"ooze", "stoke", "drag", "dredge", "summon", "gum", "drain", "fuse", "blocked", "screened"]
const KINDS := ["en_impact", "en_smear", "en_dust", "en_slam", "en_debris", "en_quake", "en_flood",
	"en_glob", "en_heat", "en_ember", "en_gather", "en_smoke", "en_chain", "en_siphon", "en_tar",
	"en_tendril", "en_weld", "en_body", "en_strain", "en_fizzle", "en_word"]

## Palettes: a body, b hot highlight, c dark edge.
const MACHINE := {"a": Color("e04b3a"), "b": Color("ffd0c8"), "c": Color("5d5348")}
const HOT := {"a": Color("ffb347"), "b": Color("fff3c4"), "c": Color("d0602a")}
const HEAT := {"a": Color("ef933a"), "b": Color("fdf0a8"), "c": Color("b8441e")}
const OIL := {"a": Color("221a26"), "b": Color("b9a3d6"), "c": Color("0c0a08")}
const SLUDGE := {"a": Color("2b2233"), "b": Color("e8913a"), "c": Color("0e0b09")}
const TAR := {"a": Color("2a1f18"), "b": Color("f0a860"), "c": Color("120d0a")}
const MAGNET := {"a": Color("7ec8e0"), "b": Color("e8f8ff"), "c": Color("c23b30")}
const CHARGE := {"a": Color("f7c948"), "b": Color("fffbe0"), "c": Color("ff6a5a")}
const MUD := {"a": Color("7a6634"), "b": Color("c4b070"), "c": Color("2e2616")}
const STEEL := Color("b4bec6")
const STEEL_DARK := Color("4c565e")
const DUST := Color("c2b496")
const ROCK := [Color("7a6650"), Color("b3a080"), Color("54463a")]
const SMOKE_DARK := Color("46423e")
const SMOKE_LIGHT := Color("9aa0a4")
const LEAF := Color("86dc62")
const WARN := Color("e04b3a")
const SHIELD := Color("7fb6d9")

## Events that follow from the one right before them (a death after the blow,
## a status after a hook): they land 30 ms after it.
const FOLLOWS := ["death", "split", "bounty", "smoke_burst", "boss_phase", "status", "resisted",
	"immune", "hook", "hook_capped", "player_death", "core_shielded"]

## How a machine crosses a tile. step: ms per tile; hop: arc height (tiles);
## land: landing squash ms; thump: screen shake per footfall; dust: puff size.
const GAITS := {
	"hop": {"step": 150, "hop": 0.17, "land": 110, "thump": 0.0, "dust": 0.0},
	"bound": {"step": 118, "hop": 0.32, "land": 90, "thump": 0.0, "dust": 0.6},
	"glide": {"step": 180, "hop": 0.0, "land": 0, "thump": 0.0, "dust": 0.0},
	"slither": {"step": 205, "hop": 0.0, "land": 0, "thump": 0.0, "dust": 0.0},
	"scuttle": {"step": 112, "hop": 0.08, "land": 70, "thump": 0.0, "dust": 0.3},
	"stomp": {"step": 210, "hop": 0.10, "land": 150, "thump": 2.5, "dust": 0.9},
	"march": {"step": 235, "hop": 0.14, "land": 170, "thump": 5.0, "dust": 1.3},
}
## The idle loop already says how a machine carries itself (shell/anim_lib.gd
## IDLE_BY_TRAIT, from the row's traits); its gait follows from it.
const GAIT_BY_IDLE := {"heave": "march", "pant": "bound", "hover": "glide", "ooze": "slither",
	"skitter": "scuttle"}

## Budgets for the verbs that sweep the whole board (ms).
const FLOOD_SWEEP_MS := 520
const IGNITE_SWEEP_MS := 620

## One machine at a time: the director spaces the slots' STARTS, but a spit
## lands later than a bite, so a verb waits (at most BEAT_WAIT_MAX) for its
## impact to fall a beat after the previous machine's. Never past
## BEAT_LATEST, which keeps a whole pack inside the reel budget.
const BEAT_MS := 120
const BEAT_WAIT_MAX := 260
const BEAT_LATEST := 1100
## Slots overlap, so a machine after a crane would otherwise spit at, bite or
## chase the tile the tender is being HAULED to before it gets there: a verb
## aimed at the tender lands, and a walker sets off, only once the haul is
## done - but never later than this, so a crane at the back of a pack cannot
## push the turn past its budget.
const HAUL_LATEST := 1300

## Words a verb puts on the tender ("gummed", "-2 charge") pop up UNDER its
## feet, one row each, clear of the damage numbers rising over its head - so
## a pack's results never print over each other.
const WORD_ROW := 0.4
## A word reads for as long as a damage number does.
const WORD_MS := L.T_FLOAT

## Events an ignition's hooks set off (a resonance's root, an ember graft's
## bite and whatever those kill): _ignite_all times them to the tile that
## caught.
const HOOK_RUN := ["hook", "hook_capped", "damage", "death", "split", "bounty", "status", "resisted",
	"immune", "staggered", "smoke_burst", "core_shielded", "boss_phase", "player_death", "win"]


static func build(verb: String, c: Dictionary) -> int:
	c["pal"] = MACHINE
	if _gone(c):
		# it left the board before its turn came (welded into a partner, or
		# killed by what an earlier machine set off): the pre board still
		# shows its telegraph, but it never acted - drawing that intent would
		# show an attack, a spit or a walk that did not happen
		_claim_rest(c, int(c["t"]) + 60, Vector2(0, 1))
		c["hit"] = 60
		return int(c["t"])
	match verb:
		"move":
			return _walk(c, "")
		"advance":
			return _walk(c, "march")
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
			return _gather(c)
		"ooze":
			return _ooze(c)
		"stoke":
			return _stoke(c)
		"drag":
			return _drag(c)
		"dredge":
			return _dredge(c)
		"summon":
			return _summon(c)
		"gum":
			return _gum(c)
		"drain":
			return _drain(c)
		"fuse":
			return _fuse(c)
		"blocked":
			return _blocked(c)
		"screened":
			return _screened(c)
	_claim_rest(c, int(c["t"]) + 60, Vector2(0, 1))
	c["hit"] = 60
	return int(c["t"]) + 60


# --- shared builder helpers --------------------------------------------------------

static func _ppos(c: Dictionary) -> Vector2i:
	return c.get("ppos", c["p0"])


## True when this machine left the board before its own turn: a partner
## welded it in (the sim removes the eaten one, so it never acts), or its
## death was already drawn by an earlier machine's verb (claimed by that
## slot - an ignition hook that killed it, say).
static func _gone(c: Dictionary) -> bool:
	if c.get("post_e") != null or not c.has("e"):
		return false
	var id = c["e"]["id"]
	var evs: Array = c["events"]
	for i in evs.size():
		var tt := String(evs[i].get("t", ""))
		if tt == "assimilate" and L.same_id(evs[i].get("eaten"), id):
			return true
		if tt == "death" and L.same_id(evs[i].get("id"), id) and L.claimed(c, i):
			return true
	return false


## When this verb starts, given `off`, its own start-to-impact time: late
## enough that its impact lands a beat after the previous machine's (see
## BEAT_MS). Records its impact for the machine after it. A verb that `aims`
## at the tender also lands only after any haul this phase has finished (see
## HAUL_LATEST).
static func _start(c: Dictionary, off: int, aims: bool = true) -> int:
	var t: int = c["t"]
	var last := int(c.get("_en_beat", -100000))
	var hit := t + off
	var want := last + BEAT_MS
	if hit < want and hit < BEAT_LATEST:
		t += mini(mini(want - hit, BEAT_WAIT_MAX), BEAT_LATEST - hit)
	var haul := int(c.get("_en_haul", -1))
	if aims and haul >= 0:
		# after a haul the aimed verbs queue behind it, still a beat apart
		# (the haul, not the pack, is what made them late)
		var land := maxi(t + off, mini(maxi(haul + 40, last + BEAT_MS), HAUL_LATEST))
		t = land - off
	c["_en_beat"] = maxi(last, t + off)
	return t


## Pop a verb's words under the tender on their own row (see WORD_ROW); the
## event's generic float is silenced. A row is free again once the word on it
## has faded, so a busy turn stacks only the words that are really on screen
## together instead of walking every later word further down (and off the
## view).
static func _say(c: Dictionary, i: int, t: int, text: String, col: Color) -> void:
	L.quiet(c, i)
	var ends: Array = c.get("_en_rows", [])
	var row := 0
	while row < ends.size() and int(ends[row]) > t:
		row += 1
	if row == ends.size():
		ends.append(0)
	ends[row] = t + WORD_MS
	c["_en_rows"] = ends
	L.clip(c, {"kind": "en_word", "t0": t, "dur": WORD_MS, "at": _ppos(c), "row": row, "text": text, "col": col,
		"read": true})


static func _row(e: Dictionary) -> Dictionary:
	return Content.ENEMIES.get(String(e["kind"]), {})


static func gait_of(kind: String) -> String:
	var style := L.idle_style(kind)
	if GAIT_BY_IDLE.has(style):
		return GAIT_BY_IDLE[style]
	if bool(Content.ENEMIES.get(kind, {}).get("slow", false)):
		return "stomp"
	return "hop"


static func _dir_or_down(a: Vector2i, b: Vector2i) -> Vector2:
	var d := L.dir_of(a, b)
	return Vector2(0, 1) if d == Vector2.ZERO else d


## One step from `a` toward `b` along the longer axis.
static func _step_toward(a: Vector2i, b: Vector2i) -> Vector2i:
	var dl := b - a
	if dl == Vector2i.ZERO:
		return Vector2i(0, 1)
	if absi(dl.x) >= absi(dl.y):
		return Vector2i(signi(dl.x), 0)
	return Vector2i(0, signi(dl.y))


static func _own_of(c: Dictionary, tt: String) -> Array:
	var out: Array = []
	for i in c["own"]:
		if String(c["events"][i].get("t", "")) == tt:
			out.append(i)
	return out


## The next event of type `tt` anywhere in the step no verb has taken yet.
## For events whose `id` is not the enemy's (a "gummed" names the ability it
## gums), the director cannot attribute them to a machine; the verb that
## caused one takes it here, in stream order.
## `key`/`val` narrow it further: a gum takes only the "gummed" whose slot is
## the slot it telegraphed.
static func _take_event(c: Dictionary, tt: String, key: String = "", val = null) -> int:
	if not c.has("_en_taken"):
		c["_en_taken"] = {}
	var taken: Dictionary = c["_en_taken"]
	var evs: Array = c["events"]
	for i in evs.size():
		if String(evs[i].get("t", "")) != tt or taken.has(i):
			continue
		if key != "" and not (evs[i].has(key) and typeof(evs[i][key]) == typeof(val) and evs[i][key] == val):
			continue
		taken[i] = true
		return i
	return -1


## This machine's event of type `tt`: its own when the director gave it one,
## else the next one nobody took. Events with no enemy id (flood, ignite_all)
## are attributed by a cursor the director can lose - a hook's damage on a
## later machine moves it past the one that really acted.
static func _own_or_take(c: Dictionary, tt: String) -> int:
	var own := _own_of(c, tt)
	if not own.is_empty():
		if not c.has("_en_taken"):
			c["_en_taken"] = {}
		c["_en_taken"][own[0]] = true
		return own[0]
	return _take_event(c, tt)


## Tiles of view directly above `p` (0..cap). Above the view's top edge sits
## the status strip, so tall effects (a smoke column, a lob's apex, a ring)
## bend or shrink instead of drawing over it. With no `vis` (the headless
## suite's view) every tile counts as seen.
static func _up(V: Dictionary, p: Vector2i, cap: int) -> int:
	if not V.has("vis"):
		return cap
	var vis: Callable = V["vis"]
	var n := 0
	while n < cap and bool(vis.call(p + Vector2i(0, -(n + 1)))):
		n += 1
	return n


static func _seen(V: Dictionary, p: Vector2i) -> bool:
	return not V.has("vis") or bool((V["vis"] as Callable).call(p))


static func _tile_of(p) -> Vector2i:
	return Vector2i(Vector2(p).round())


## Which way a plume leans when the view gives it no room to rise: `prefer`
## (+1 right, -1 left) unless a wall stands there and not on the other side.
static func _lean_side(c: Dictionary, at: Vector2i, prefer: int) -> int:
	var s := 1 if prefer >= 0 else -1
	if L.wall(c["pre"], at + Vector2i(s, 0)) and not L.wall(c["pre"], at + Vector2i(-s, 0)):
		return -s
	return s


## Where a creature stands right now in the reel being built: the end of its
## last path segment, else `fallback`.
static func _pos_now(c: Dictionary, key, fallback: Vector2i) -> Vector2i:
	var segs = c["reel"]["tracks"].get(key)
	if segs == null:
		return fallback
	var at := fallback
	for s in segs:
		if String(s["kind"]) == "path":
			var pts: Array = s["pts"]
			at = Vector2i((pts[pts.size() - 1] as Vector2).round())
	return at


## Claim every event of this enemy the verb did not claim itself: a blow to
## the tender at the impact (recoiling along `d`), thorns biting back a beat
## later (the attacker recoils and sparks green), a consequence right after
## its cause, anything else just after the impact. `me_at` is where the
## attacker stands at the impact (a slamming boss is on its landing arm, not
## home) - the thorn sparks fly off it there.
static func _claim_rest(c: Dictionary, t_hit: int, d: Vector2, me_at = null) -> void:
	var e: Dictionary = c.get("e", {})
	var evs: Array = c["events"]
	if me_at == null and not e.is_empty():
		me_at = e["pos"]
	for i in c.get("own", []):
		if L.claimed(c, i):
			continue
		var ev: Dictionary = evs[i]
		var tt := String(ev.get("t", ""))
		if tt == "damage" and String(ev.get("who", "")) == "player":
			L.claim(c, i, t_hit, d)
		elif tt == "damage" and not e.is_empty() and L.same_id(ev.get("id"), e["id"]):
			L.claim(c, i, t_hit + 60, -d)
			if String(ev.get("src", "")) == "thorns":
				L.clip(c, {"kind": "en_impact", "t0": t_hit + 50, "dur": 300, "at": me_at, "dir": -d,
					"dmg": int(ev.get("amt", 1)), "hit": true, "pal": L.pal_of("displace")})
		elif i > 0 and FOLLOWS.has(tt) and L.claimed(c, i - 1):
			L.claim(c, i, int(c["times"][i - 1]) + 30)
		else:
			L.claim(c, i, t_hit + 30)


## A blow that connects while the tender's shield is up: the sim emits
## {t: "shield_absorb", amt} - no enemy id, so the director hands it to
## whichever machine emitted the event before it and it lands at THAT
## machine's impact (or the phase's end). Take it in stream order while the
## shield the pre board had lasts, and land it on this blow. Returns what the
## shield absorbed (0 when the blow never touched one).
static func _take_absorb(c: Dictionary, t_hit: int) -> int:
	if not c.has("_en_shield"):
		c["_en_shield"] = int(c["pre"]["player"].get("shield", 0))
	if int(c["_en_shield"]) <= 0:
		return 0
	var i := _take_event(c, "shield_absorb")
	if i < 0:
		return 0
	var amt := maxi(1, int(c["events"][i].get("amt", 1)))
	c["_en_shield"] = int(c["_en_shield"]) - amt
	L.claim(c, i, t_hit)
	# the word goes under the feet with the other verb words, clear of the
	# number the rest of the blow may still put over the head
	_say(c, i, t_hit, "blocked", SHIELD)
	return amt


## A blow that connects: take ITS damage event - the next {damage, who:
## player, src: this machine's kind} nobody took - and land it on this
## impact. The director matches a blow to the first machine of that kind at
## or after its cursor, and a blow moves the cursor only TO that machine, so
## the second drill bot's bite is handed to the first one and pops (stacked)
## on the first lunge while the second lunge reads as a miss. Taking them in
## machine order puts each bite on its own lunge; what follows from it (the
## tender falling) follows it. Returns true when a damage event was taken.
static func _take_blow(c: Dictionary, t_hit: int, d: Vector2) -> bool:
	if not c.has("_en_taken"):
		c["_en_taken"] = {}
	var taken: Dictionary = c["_en_taken"]
	var kind := String(c["e"]["kind"])
	var evs: Array = c["events"]
	for i in evs.size():
		var ev: Dictionary = evs[i]
		if taken.has(i) or String(ev.get("t", "")) != "damage" or String(ev.get("who", "")) != "player" \
				or String(ev.get("src", "")) != kind:
			continue
		taken[i] = true
		L.claim(c, i, t_hit, d)
		var j := i + 1
		while j < evs.size() and ["player_death", "hook", "hook_capped"].has(String(evs[j].get("t", ""))):
			L.claim(c, j, t_hit + 30)
			j += 1
		return true
	return false


## The blow of a machine whose intent carries `dmg`: the shield takes what it
## can, the rest is a damage event this blow takes. Returns [hit, shielded].
static func _blow(c: Dictionary, t_hit: int, d: Vector2, dmg: int) -> Array:
	var absorbed := _take_absorb(c, t_hit)
	var landed := false
	if dmg - absorbed > 0:
		landed = _take_blow(c, t_hit, d)
	return [landed or absorbed > 0, absorbed > 0]


static func _cross(c: Dictionary, center: Vector2i) -> Array:
	var out: Array = [center]
	for d in L.DIRS:
		var q: Vector2i = center + d
		if not L.wall(c["pre"], q):
			out.append(q)
	return out


# --- movement ------------------------------------------------------------------

## Walk the enemy from its pre tile to its post tile in its own gait. A mover
## that died on the way (walked into fire) is walked onto the burning tile.
static func _walk(c: Dictionary, force: String) -> int:
	var t: int = c["t"]
	var e: Dictionary = c["e"]
	var id = e["id"]
	var from: Vector2i = e["pos"]
	var to := from
	if c["post_e"] != null:
		to = c["post_e"]["pos"]
	else:
		to = _death_step(c, from)
	var pts := L.path(c["pre"], from, to)
	var hops := pts.size() - 1
	if hops <= 0:
		_claim_rest(c, t + 80, Vector2(0, 1))
		c["hit"] = 80
		return t + 80
	# a machine chasing a tender a crane is still hauling sets off once it
	# lands (the sim moved it after the haul, toward the tender's new tile)
	var haul := int(c.get("_en_haul", -1))
	if haul >= 0:
		t = maxi(t, mini(haul - 40, HAUL_LATEST))
	var gname := force if force != "" else gait_of(String(e["kind"]))
	var g: Dictionary = GAITS[gname]
	var step := int(g["step"])
	var dur := hops * step
	match gname:
		"glide":
			# no hop: the drone eases off, cruises and settles
			L.move(c, id, _eased_path(pts, hops * 4), t, dur, 0.0)
		"slither":
			# a surge per tile, the body flattening as it gathers for the next
			L.move(c, id, _eased_legs(pts, 3), t, dur, 0.0)
			for j in hops:
				L.seg(c, id, {"kind": "squash", "t0": t + j * step - step / 4, "dur": step / 2 + 50})
			L.seg(c, id, {"kind": "squash", "t0": t + dur - step / 4, "dur": step / 2 + 50})
		_:
			L.move(c, id, pts, t, dur, float(g["hop"]))
			for j in hops:
				var land := t + (j + 1) * step
				L.seg(c, id, {"kind": "squash", "t0": land - 25, "dur": int(g["land"])})
				if float(g["thump"]) > 0.0:
					c["reel"]["shakes"].append({"t0": land, "mag": float(g["thump"])})
				if float(g["dust"]) > 0.0:
					L.clip(c, {"kind": "en_dust", "t0": land - 20, "dur": 340, "at": pts[j + 1],
						"mag": float(g["dust"]), "layer": "ground"})
	# an oil trail is laid as the body leaves each tile
	var sw: Dictionary = c["reel"]["tswap"]
	for j in hops:
		var p: Vector2i = pts[j]
		if sw.has(p) and not sw[p].has("t") and String(sw[p]["post"]) == "oil" and String(sw[p]["pre"]) == "":
			L.reveal(c, p, t + j * step + step / 2)
	# what a tile does to it lands as it steps onto that tile
	var evs: Array = c["events"]
	var hurt := _hurt_index(c, pts)
	var back := L.dir_of(pts[hurt], pts[hurt - 1])
	for i in c["own"]:
		if L.claimed(c, i):
			continue
		var ev: Dictionary = evs[i]
		var tile = ev.get("tile")
		if tile is Vector2i and pts.has(tile):
			L.claim(c, i, t + pts.find(tile) * step)
		elif String(ev.get("t", "")) == "damage" and L.same_id(ev.get("id"), id):
			L.claim(c, i, t + hurt * step, back)
	_claim_rest(c, t + dur, _dir_or_down(from, to))
	c["hit"] = t + dur - int(c["t"])
	return t + dur + 40


## The first tile along the path whose terrain hurts on entry (else the last).
static func _hurt_index(c: Dictionary, pts: Array) -> int:
	for j in range(1, pts.size()):
		if int(Content.terrain(L.tkind(c["pre"], pts[j]), "enter_dmg_enemy", 0)) > 0:
			return j
	return pts.size() - 1


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


## `pts` resampled into n+1 points eased in-out over the WHOLE path (a path
## segment runs its points at a constant rate, so spacing is speed).
static func _eased_path(pts: Array, n: int) -> Array:
	var hops := pts.size() - 1
	var out: Array = []
	for i in n + 1:
		var s := D.ease_io(float(i) / float(n)) * float(hops)
		var j := mini(int(s), hops - 1)
		out.append(Vector2(pts[j]).lerp(Vector2(pts[j + 1]), s - float(j)))
	return out


## Each leg of `pts` split into sub+1 eased pieces: a surge per tile.
static func _eased_legs(pts: Array, sub: int) -> Array:
	var out: Array = [Vector2(pts[0])]
	for j in range(pts.size() - 1):
		for i in range(1, sub + 2):
			out.append(Vector2(pts[j]).lerp(Vector2(pts[j + 1]), D.ease_io(float(i) / float(sub + 1))))
	return out


# --- melee and the bosses' blows ------------------------------------------------------

## Wind-up (the machine leans back), a lunge, and grinding sparks on the
## tender at the lunge's apex - the moment the number lands.
static func _attack(c: Dictionary) -> int:
	var e: Dictionary = c["e"]
	var tile = e["intent"].get("tile", _ppos(c))
	if not (tile is Vector2i):
		tile = _ppos(c)
	var d := _dir_or_down(e["pos"], tile)
	var dmg := int(e["intent"].get("dmg", 1))
	# crouch and lean back, then snap forward: the lunge peaks at the impact
	var t := _start(c, 267)
	L.seg(c, e["id"], {"kind": "squash", "t0": t, "dur": 220})
	L.seg(c, e["id"], {"kind": "lunge", "t0": t, "dur": 300, "dir": -d, "reach": 0.3})
	L.seg(c, e["id"], {"kind": "lunge", "t0": t + 190, "dur": 220, "dir": d, "reach": 0.6})
	var t_hit := t + 267
	var blow: Array = _blow(c, t_hit, d, dmg) if tile == _ppos(c) else [false, false]
	L.clip(c, {"kind": "en_smear", "t0": t + 200, "dur": 130, "at": e["pos"], "dir": d})
	L.clip(c, {"kind": "en_impact", "t0": t_hit, "dur": 380, "at": tile, "dir": d, "dmg": dmg,
		"hit": blow[0], "shield": blow[1], "pal": HOT})
	_claim_rest(c, t_hit, d)
	c["hit"] = t_hit - int(c["t"])
	return t_hit + 160


## The boss crouches, leaps onto the nearest arm of its telegraphed cross,
## crashes down (shockwave, cracks, debris, the cross flashing) and hops back.
static func _slam(c: Dictionary) -> int:
	var t: int = c["t"]
	var e: Dictionary = c["e"]
	var id = e["id"]
	var tile = e["intent"].get("tile", _ppos(c))
	if not (tile is Vector2i):
		tile = _ppos(c)
	var boss: Vector2i = e["pos"]
	var land := boss
	if L.man(boss, tile) > 1:
		var best := 999
		for q in [tile] + _arms(tile):
			if L.wall(c["pre"], q):
				continue
			if L.man(boss, q) < best:
				best = L.man(boss, q)
				land = q
	var dmg := int(e["intent"].get("dmg", 3))
	var air := 290 + 45 * L.man(boss, land)
	t = _start(c, 110 + air)
	var t_up := t + 110
	var t_imp := t_up + air
	L.seg(c, id, {"kind": "squash", "t0": t, "dur": 140})
	L.seg(c, id, {"kind": "path", "t0": t_up, "dur": air, "pts": [Vector2(boss), Vector2(land)], "hop": 1.05})
	L.seg(c, id, {"kind": "squash", "t0": t_imp - 10, "dur": 220})
	L.seg(c, id, {"kind": "squash", "t0": t_imp - 10, "dur": 150})
	if land != boss:
		L.seg(c, id, {"kind": "path", "t0": t_imp + 190, "dur": 260, "pts": [Vector2(land), Vector2(boss)], "hop": 0.3})
		L.seg(c, id, {"kind": "squash", "t0": t_imp + 440, "dur": 120})
	var cross := _cross(c, tile)
	if cross.has(_ppos(c)):
		_blow(c, t_imp, _dir_or_down(land, _ppos(c)), dmg)
	L.clip(c, {"kind": "en_slam", "t0": t, "dur": (t_imp - t) + 470, "at": tile, "land": land,
		"imp": t_imp - t, "tiles": cross, "dmg": dmg, "layer": "ground"})
	L.clip(c, {"kind": "en_debris", "t0": t_imp, "dur": 600, "at": tile, "tiles": cross, "n": 10 + dmg})
	c["reel"]["shakes"].append({"t0": t_imp, "mag": 6.0 + float(dmg)})
	_claim_rest(c, t_imp, _dir_or_down(land, _ppos(c)), land)
	c["hit"] = t_imp - int(c["t"])
	return t_imp + 220


static func _arms(center: Vector2i) -> Array:
	var out: Array = []
	for d in L.DIRS:
		out.append(center + d)
	return out


## A hop in place and a stomp: the ground rings, cracks run out through the
## four tiles the quake reaches and chunks of floor jump.
static func _quake(c: Dictionary) -> int:
	var t := _start(c, 310)
	var e: Dictionary = c["e"]
	var id = e["id"]
	var boss: Vector2i = e["pos"]
	L.seg(c, id, {"kind": "squash", "t0": t, "dur": 130})
	L.seg(c, id, {"kind": "path", "t0": t + 90, "dur": 220, "pts": [Vector2(boss), Vector2(boss)], "hop": 0.45})
	var t_imp := t + 310
	L.seg(c, id, {"kind": "squash", "t0": t_imp - 10, "dur": 220})
	L.seg(c, id, {"kind": "squash", "t0": t_imp - 10, "dur": 150})
	var ring: Array = []
	for q in _arms(boss):
		if not L.wall(c["pre"], q):
			ring.append(q)
	if L.man(boss, _ppos(c)) == 1:
		_blow(c, t_imp, _dir_or_down(boss, _ppos(c)), int(e["intent"].get("dmg", 2)))
	L.clip(c, {"kind": "en_quake", "t0": t_imp - 10, "dur": 560, "at": boss, "tiles": ring, "layer": "ground"})
	L.clip(c, {"kind": "en_debris", "t0": t_imp, "dur": 560, "at": boss, "tiles": ring, "n": 12})
	c["reel"]["shakes"].append({"t0": t_imp, "mag": 7.5})
	_claim_rest(c, t_imp, _dir_or_down(boss, _ppos(c)))
	c["hit"] = t_imp - int(c["t"])
	return t_imp + 200


# --- board-wide boss verbs ---------------------------------------------------------

## The core convulses and gushes oil onto its row; two crests race out along
## it and every tile turns to oil as a crest passes.
static func _flood(c: Dictionary) -> int:
	var e: Dictionary = c["e"]
	var id = e["id"]
	var boss: Vector2i = e["pos"]
	var row := int(e["intent"].get("row", boss.y))
	var w := int(c["pre"]["map"]["w"])
	# the tiles this flood writes: oil on the row that no machine acting
	# after the core laid (a later sludge's trail tile was occupied when the
	# flood ran, so the sim skipped it - its own walk reveals it)
	var later := {}
	var seen_me := false
	for pe in c["pre"]["enemies"]:
		if seen_me:
			later[pe["pos"]] = true
		elif L.same_id(pe["id"], id):
			seen_me = true
	var xs: Array = []
	var sw: Dictionary = c["reel"]["tswap"]
	for p in sw:
		if p.y == row and String(sw[p]["post"]) == "oil" and not sw[p].has("t") and not later.has(p):
			xs.append(p.x)
	# it pours onto the flooded tile nearest the core's column (never a wall);
	# a core standing on the row gushes out of itself
	var bx := boss.x
	if boss.y != row and not xs.is_empty():
		var best := 1 << 20
		for x in xs:
			if absi(int(x) - boss.x) < best:
				best = absi(int(x) - boss.x)
				bx = int(x)
	var drop := Vector2i(bx, row)
	var fly := 70 + 40 * L.man(boss, drop) if boss != drop else 0
	var t := _start(c, 140 + fly, false)
	L.seg(c, id, {"kind": "shake", "t0": t, "dur": 220, "amt": 0.07})
	L.seg(c, id, {"kind": "cast", "t0": t + 40, "dur": 280})
	var t_land := t + 140 + fly
	if fly > 0:
		# a gush of oil pours from the core down onto the row
		L.clip(c, {"kind": "en_glob", "t0": t + 140, "dur": fly + 300, "at": drop, "from": boss, "to": drop,
			"fly": fly, "size": 1.5, "stream": true, "pal": OIL})
	# the crests run to the walls of the stretch they poured into and break
	# there; the sim floods the WHOLE row, so tiles past those walls (other
	# rooms, out of view) flip as the crest breaks rather than pacing the
	# reel across the whole map
	var lo := bx
	while lo - 1 >= 1 and not L.wall(c["pre"], Vector2i(lo - 1, row)):
		lo -= 1
	var hi := bx
	while hi + 1 <= w - 2 and not L.wall(c["pre"], Vector2i(hi + 1, row)):
		hi += 1
	var far := maxi(1, maxi(bx - lo, hi - bx))
	var per := clampi(FLOOD_SWEEP_MS / far, 12, 48)
	for x in xs:
		var dx := absi(int(x) - bx)
		if int(x) < lo:
			dx = bx - lo + 1
		elif int(x) > hi:
			dx = hi - bx + 1
		L.reveal(c, Vector2i(int(x), row), t_land + dx * per + per / 2)
	L.clip(c, {"kind": "en_flood", "t0": t_land - 20, "dur": 20 + far * per + 360, "at": drop, "row": row,
		"from_x": bx, "x_min": lo, "x_max": hi, "per": per, "lead": 20, "xs": xs, "layer": "ground"})
	var fi := _own_or_take(c, "flood")
	if fi >= 0:
		L.claim(c, fi, t_land)
	_claim_rest(c, t_land, Vector2(0, 1))
	c["hit"] = t_land - int(c["t"])
	return t_land + mini(far * per, 360) + 80


## The furnace flares white-hot and flings embers: every slick catches in a
## wave spreading out from it, nearest first.
static func _ignite_all(c: Dictionary) -> int:
	var t := _start(c, 210, false)
	var e: Dictionary = c["e"]
	var id = e["id"]
	var boss: Vector2i = e["pos"]
	L.seg(c, id, {"kind": "cast", "t0": t, "dur": 320})
	L.seg(c, id, {"kind": "tint", "t0": t + 140, "dur": 460, "col": Color(1.0, 0.62, 0.36)})
	L.seg(c, id, {"kind": "flash", "t0": t + 200, "dur": 180})
	L.clip(c, {"kind": "en_heat", "t0": t, "dur": 560, "at": boss, "pal": HEAT})
	var t_go := t + 210
	var sw: Dictionary = c["reel"]["tswap"]
	# its slicks: tiles that were flammable and are burning now, bar any an
	# "ignite" event names (ignite_all emits none - that is another igniter,
	# a cinder mite's step, whose own walk reveals it)
	var named := {}
	for ev in c["events"]:
		if String(ev.get("t", "")) == "ignite" and ev.get("tile") is Vector2i:
			named[ev["tile"]] = true
	var tiles: Array = []
	for p in sw:
		if String(sw[p]["post"]) == "fire" and not sw[p].has("t") and not named.has(p) \
				and bool(Content.terrain(String(sw[p]["pre"]), "flammable", false)):
			tiles.append(p)
	var far := 1
	for p in tiles:
		far = maxi(far, L.man(p, boss))
	var per := clampi(IGNITE_SWEEP_MS / far, 14, 42)
	var at_tile := {}
	var last := t_go
	for p in tiles:
		var fly := 110 + L.man(p, boss) * per
		var ta := t_go + fly
		at_tile[p] = ta
		last = maxi(last, ta)
		L.reveal(c, p, ta)
		L.clip(c, {"kind": "en_ember", "t0": t_go, "dur": fly + 320, "at": p, "from": boss, "to": p,
			"fly": fly, "pal": HEAT})
	var evs: Array = c["events"]
	var ia := _own_or_take(c, "ignite_all")
	if ia >= 0:
		L.claim(c, ia, t_go)
		# every slick that caught ran the ignite hooks (a resonance's root, an
		# ember graft's bite) BEFORE the sim emitted ignite_all; those events
		# name the enemy they hit, so the director hands them to that machine
		# and they would land at its slot, before the fireball got there. They
		# land when their own tile catches: walk the run back from ignite_all
		# and time each hook to its tile and its consequences just after it.
		var s := ia
		while s > 0 and HOOK_RUN.has(String(evs[s - 1].get("t", ""))):
			s -= 1
		var cur := -1
		for i in range(s, ia):
			var ev: Dictionary = evs[i]
			var tt := String(ev.get("t", ""))
			if tt == "hook":
				# a hook on a tile this verb did not light is some other
				# machine's tail: not ours, nor what follows it
				cur = int(at_tile[ev["tile"]]) if ev.get("tile") is Vector2i and at_tile.has(ev["tile"]) else -1
				if cur >= 0:
					L.claim(c, i, cur)
			elif cur >= 0:
				L.claim(c, i, cur + 30, Vector2(0, -1) if tt == "damage" else null)
	for i in c["own"]:
		if L.claimed(c, i):
			continue
		var tile = evs[i].get("tile")
		if tile is Vector2i and at_tile.has(tile):
			L.claim(c, i, at_tile[tile])
	_claim_rest(c, t_go, Vector2(0, 1))
	c["hit"] = t_go - int(c["t"])
	return mini(last, t_go + 360) + 80


## Heat spirals into the core and it glows brighter and brighter: a charge
## the player reads as "next turn, something big".
static func _gather(c: Dictionary) -> int:
	var t := _start(c, 470, false)
	var e: Dictionary = c["e"]
	L.seg(c, e["id"], {"kind": "cast", "t0": t, "dur": 540})
	L.seg(c, e["id"], {"kind": "shake", "t0": t + 200, "dur": 300, "amt": 0.03})
	L.seg(c, e["id"], {"kind": "tint", "t0": t + 300, "dur": 420, "col": Color(1.0, 0.7, 0.45)})
	L.seg(c, e["id"], {"kind": "flash", "t0": t + 470, "dur": 200})
	L.clip(c, {"kind": "en_gather", "t0": t, "dur": 640, "at": e["pos"], "pal": HEAT})
	_claim_rest(c, t + 470, Vector2(0, -1))
	c["hit"] = t + 470 - int(c["t"])
	return t + 540


## The Dredge sends mud tendrils to every growth tile in reach: each grabs,
## the growth tears up into goo, and the torn leaves ride back to heal it.
static func _dredge(c: Dictionary) -> int:
	var e: Dictionary = c["e"]
	var id = e["id"]
	var boss: Vector2i = e["pos"]
	var sw: Dictionary = c["reel"]["tswap"]
	var tiles: Array = []
	var near := 3
	for p in sw:
		if String(sw[p]["pre"]) == "growth" and String(sw[p]["post"]) == "goo" and not sw[p].has("t"):
			tiles.append(p)
			near = mini(near, L.man(p, boss))
	var t := _start(c, 160 + near * 55, false) if not tiles.is_empty() else int(c["t"])
	L.seg(c, id, {"kind": "cast", "t0": t, "dur": 320})
	var first := t + 400
	var back := t + 200
	for p in tiles:
		var reach := 160 + L.man(p, boss) * 55
		first = mini(first, t + reach)
		back = maxi(back, t + reach + 300)
		L.reveal(c, p, t + reach)
		L.clip(c, {"kind": "en_tendril", "t0": t, "dur": reach + 420, "at": p, "from": boss, "to": p,
			"grab": reach, "back": reach + 150, "layer": "ground"})
	for i in _own_of(c, "dredge"):
		L.claim(c, i, first)
	# the heal lands when the leaves arrive: the bar rises then, not before
	var pe = c["post_e"]
	if pe != null and int(pe["hp"]) > int(e["hp"]):
		var gain := int(pe["hp"]) - int(e["hp"])
		if not c["reel"]["hp"].has(id):
			c["reel"]["hp"][id] = []
		c["reel"]["hp"][id].append([back, gain])
		L.clip(c, {"kind": "float", "t0": back, "dur": L.T_FLOAT, "at": Vector2(boss), "text": "+%d" % gain,
			"col": Color("8fdc6a")})
		L.seg(c, id, {"kind": "tint", "t0": back, "dur": 360, "col": Color(0.7, 1.0, 0.6)})
		L.seg(c, id, {"kind": "squash", "t0": back - 20, "dur": 160})
	_claim_rest(c, first, Vector2(0, 1))
	c["hit"] = first - int(c["t"])
	return mini(back, t + 700)


# --- the stationary machines -------------------------------------------------------

## Two pump strokes, then the jack spits a glob of oil onto a neighbour tile.
static func _ooze(c: Dictionary) -> int:
	var e: Dictionary = c["e"]
	var id = e["id"]
	var spits := _own_of(c, "ooze")
	var t := _start(c, 420, false) if not spits.is_empty() else int(c["t"])
	# two deep pump strokes (stacked squashes press twice as far)
	for k in 2:
		L.seg(c, id, {"kind": "squash", "t0": t + k * 130, "dur": 130})
		L.seg(c, id, {"kind": "squash", "t0": t + k * 130, "dur": 130})
	L.seg(c, id, {"kind": "cast", "t0": t + 200, "dur": 240})
	var end := t + 280
	for i in spits:
		var ev: Dictionary = c["events"][i]
		if not (ev.get("tile") is Vector2i):
			continue
		# a short, high lob: a neighbour tile is close, so the glob goes UP and
		# drops (a flat 240 ms arc to the next tile read as a hovering ball)
		var fly := 190
		var t_land := t + 230 + fly
		L.clip(c, {"kind": "en_glob", "t0": t + 230, "dur": fly + 320, "at": ev["tile"], "from": e["pos"],
			"to": ev["tile"], "fly": fly, "size": 1.35, "pal": OIL})
		L.claim(c, i, t_land)
		L.reveal(c, ev["tile"], t_land)
		end = t_land + 80
	_claim_rest(c, end, Vector2(0, 1))
	c["hit"] = end - int(c["t"])
	return end


## The smokestack shudders and belches a column of smoke; a stoke that fires
## this turn (the smog clock runs an extra tick) belches a big one.
static func _stoke(c: Dictionary) -> int:
	var e: Dictionary = c["e"]
	var id = e["id"]
	var fired := _own_of(c, "stoke")
	var big := not fired.is_empty()
	var t := _start(c, 190, false) if big else int(c["t"])
	var lean := _lean_side(c, e["pos"], 1)
	L.seg(c, id, {"kind": "shake", "t0": t, "dur": 200, "amt": 0.05})
	L.seg(c, id, {"kind": "cast", "t0": t + 90, "dur": 300})
	L.clip(c, {"kind": "en_smoke", "t0": t + 140, "dur": 760 if big else 520, "at": e["pos"], "big": big,
		"lean": lean})
	for i in fired:
		L.claim(c, i, t + 190)
		# the label rises on the side the plume does not bend to
		L.clip(c, {"kind": "float", "t0": t + 240, "dur": L.T_FLOAT,
			"at": Vector2(e["pos"]) + Vector2(-0.95 * float(lean), 0.55), "text": "+smog", "col": Color("c8ced2")})
	_claim_rest(c, t + 190, Vector2(0, -1))
	c["hit"] = t + 190 - int(c["t"])
	return t + 420


## The engine shudders, puffs, and spits a sludge glob onto the tile the new
## sludgeling rises from (the director opens its portal and pops it there).
static func _summon(c: Dictionary) -> int:
	var e: Dictionary = c["e"]
	var t := _start(c, 390, false) if not _own_of(c, "summon").is_empty() else int(c["t"])
	var id = e["id"]
	# the exhaust bends away from the tile the sludgeling rises on (hard over
	# when that tile is right above the stack)
	var away := 1
	var bend := 0.0
	for i in _own_of(c, "summon"):
		var ch = c["post_en"].get(c["events"][i].get("child"))
		if ch == null:
			continue
		if ch["pos"].x > e["pos"].x:
			away = -1
		if ch["pos"].x == e["pos"].x and ch["pos"].y < e["pos"].y:
			bend = 0.55
	L.seg(c, id, {"kind": "shake", "t0": t, "dur": 300, "amt": 0.06})
	L.seg(c, id, {"kind": "cast", "t0": t + 150, "dur": 280})
	L.clip(c, {"kind": "en_smoke", "t0": t, "dur": 560, "at": e["pos"], "big": false,
		"lean": _lean_side(c, e["pos"], away), "bend": bend})
	var end := t + 300
	for i in _own_of(c, "summon"):
		var child = c["post_en"].get(c["events"][i].get("child"))
		if child == null:
			L.claim(c, i, t + 260)
			continue
		var fly := 170
		var t_spit := t + 220
		L.clip(c, {"kind": "en_glob", "t0": t_spit, "dur": fly + 220, "at": child["pos"], "from": e["pos"],
			"to": child["pos"], "fly": fly, "size": 0.85, "pal": SLUDGE})
		# the director pops the child 60 ms after this claim: on the landing
		L.claim(c, i, t_spit + fly - 60)
		end = t_spit + fly + 60
	_claim_rest(c, end, Vector2(0, 1))
	c["hit"] = end - int(c["t"])
	return end


# --- ranged machines ----------------------------------------------------------------

## A magnet crane: the head charges, the chain shoots out and clamps onto the
## tender, and yanks it in tile by tile. Anchored roots hold: the chain
## strains and snaps.
static func _drag(c: Dictionary) -> int:
	var e: Dictionary = c["e"]
	var id = e["id"]
	var crane: Vector2i = e["pos"]
	var p0 := _ppos(c)
	var d := _dir_or_down(crane, p0)
	var pts: Array = [p0]
	var drags: Array = []
	var held := -1
	for i in c["own"]:
		var ev: Dictionary = c["events"][i]
		var tt := String(ev.get("t", ""))
		if tt == "drag" and ev.get("to") is Vector2i:
			pts.append(ev["to"])
			drags.append(i)
		elif tt == "anchored":
			held = i
	var t := _start(c, 190 + L.man(crane, p0) * 35)
	L.seg(c, id, {"kind": "lunge", "t0": t, "dur": 220, "dir": -d, "reach": 0.14})
	var t_shoot := t + 120
	var t_clamp := t_shoot + 70 + L.man(crane, p0) * 35
	var t_pull := t_clamp + 90
	var step := 130
	var n := drags.size()
	var end := t_clamp + 120
	if n > 0:
		L.move(c, "player", pts, t_pull, n * step, 0.0)
		for j in n:
			L.claim(c, drags[j], t_pull + (j + 1) * step)
		L.seg(c, "player", {"kind": "squash", "t0": t_pull + n * step - 20, "dur": 120})
		L.seg(c, id, {"kind": "lunge", "t0": t_pull - 20, "dur": 240, "dir": -d, "reach": 0.12})
		end = t_pull + n * step
		c["ppos"] = pts[pts.size() - 1]
		c["_en_haul"] = maxi(int(c.get("_en_haul", -1)), end)
	if held >= 0:
		L.claim(c, held, t_clamp + 40)
		L.seg(c, "player", {"kind": "shake", "t0": t_clamp, "dur": 320, "amt": 0.05})
		end = t_clamp + 320
	if n > 0 or held >= 0:
		# the clamp bites: only when it reached the tender (a chain that falls
		# short never touched it)
		L.seg(c, "player", {"kind": "flash", "t0": t_clamp, "dur": 120})
	var fpts: Array = []
	for q in pts:
		fpts.append(Vector2(q))
	L.clip(c, {"kind": "en_chain", "t0": t, "dur": (end - t) + 200, "at": crane, "from": crane, "pts": fpts,
		"shoot": t_shoot - t, "clamp": t_clamp - t, "pull": t_pull - t, "step": step, "held": held >= 0,
		"missed": n == 0 and held < 0, "pal": MAGNET})
	_claim_rest(c, end, L.dir_of(p0, crane))
	c["hit"] = end - int(c["t"])
	return end + 60


## The spitter inhales, then lobs a glob of tar that splats on the tender and
## drips; out of range, the glob falls short onto the floor.
static func _gum(c: Dictionary) -> int:
	var e: Dictionary = c["e"]
	var id = e["id"]
	var me: Vector2i = e["pos"]
	var p := _ppos(c)
	var d := _dir_or_down(me, p)
	var reach := int(_row(e).get("gum_range", 3))
	var idx := -1
	if L.man(me, p) <= reach:
		# the gummed event names the ability, not the spitter: take the next
		# one for the slot this spitter telegraphed, in stream order
		var slot = e["intent"].get("slot")
		idx = _take_event(c, "gummed", "slot", slot) if slot != null else _take_event(c, "gummed")
	var to := p
	if idx < 0:
		to = me
		for k in 2:
			var nx := to + _step_toward(to, p)
			if L.wall(c["pre"], nx) or nx == p:
				break
			to = nx
	var fly := 170 + L.man(me, to) * 45
	# inhale, then spit
	var t := _start(c, 170 + fly)
	L.seg(c, id, {"kind": "squash", "t0": t, "dur": 170})
	L.seg(c, id, {"kind": "squash", "t0": t + 20, "dur": 130})
	L.seg(c, id, {"kind": "lunge", "t0": t + 130, "dur": 220, "dir": d, "reach": 0.22})
	var t_go := t + 170
	var t_hit := t_go + fly
	L.clip(c, {"kind": "en_tar", "t0": t_go, "dur": fly + 540, "at": to, "from": me, "to": to, "fly": fly,
		"hit": idx >= 0, "pal": TAR})
	if idx >= 0:
		L.claim(c, idx, t_hit)
		_say(c, idx, t_hit + 40, "gummed", Color("d9b44a"))
		L.seg(c, "player", {"kind": "squash", "t0": t_hit - 10, "dur": 170})
		L.seg(c, "player", {"kind": "tint", "t0": t_hit, "dur": 560, "col": Color(0.6, 0.5, 0.42)})
	_claim_rest(c, t_hit, d)
	c["hit"] = t_hit - int(c["t"])
	return t_hit + 120


## The drone leans in and a siphon beam links it to the tender: charge
## sparks are ripped out of the tender and sucked along it into the drone.
static func _drain(c: Dictionary) -> int:
	var e: Dictionary = c["e"]
	var id = e["id"]
	var p := _ppos(c)
	var d := _dir_or_down(e["pos"], p)
	var evs := _own_of(c, "drain")
	var t := _start(c, 170) if not evs.is_empty() else int(c["t"])
	L.seg(c, id, {"kind": "lunge", "t0": t, "dur": 360, "dir": d, "reach": 0.14})
	if evs.is_empty():
		L.seg(c, id, {"kind": "shake", "t0": t, "dur": 200, "amt": 0.03})
		_claim_rest(c, t + 160, d)
		c["hit"] = 160
		return t + 160
	var amt := int(c["events"][evs[0]].get("amt", 0))
	var n := clampi(amt * 3, 0, 9)
	var link := 110
	var gap := 55
	var travel := 260
	var t_first := t + link + travel
	var dur := link + maxi(0, n - 1) * gap + travel + 200
	L.clip(c, {"kind": "en_siphon", "t0": t, "dur": dur, "at": e["pos"], "from": e["pos"], "to": p, "n": n,
		"link": link, "gap": gap, "travel": travel, "pal": CHARGE})
	L.claim(c, evs[0], t + link + 60)
	if amt > 0:
		_say(c, evs[0], t + link + 60, "-%d charge" % amt, Color("f7c948"))
	else:
		_say(c, evs[0], t + link + 60, "no charge", Color("b8bec2"))
	if n > 0:
		L.seg(c, "player", {"kind": "shake", "t0": t + link, "dur": 280, "amt": 0.03})
		L.seg(c, id, {"kind": "tint", "t0": t_first, "dur": 420, "col": Color(1.0, 0.92, 0.55)})
		L.seg(c, id, {"kind": "flash", "t0": t_first, "dur": 160})
	_claim_rest(c, t + link + 60, d)
	c["hit"] = t + link + 60 - int(c["t"])
	return t + mini(dur, 560)


## Two drill bots weld into a hulk: the torch sparks at the seam while the
## partner slides in, a white-hot flash, and the hulk pops out of it. Until
## then the welder is drawn as what it was (the post board already calls it a
## hulk, which is hidden until its pop).
static func _fuse(c: Dictionary) -> int:
	var e: Dictionary = c["e"]
	var t := _start(c, 380, false) if not _own_of(c, "assimilate").is_empty() else int(c["t"])
	var id = e["id"]
	var me: Vector2i = e["pos"]
	var merge := t + 380
	for i in _own_of(c, "assimilate"):
		var ev: Dictionary = c["events"][i]
		var pe = c["pre_en"].get(ev.get("eaten"))
		var from := me + Vector2i(1, 0)
		if pe != null:
			from = _pos_now(c, pe["id"], pe["pos"])
			L.move(c, pe["id"], [from, me], t + 150, 210, 0.1)
			L.seg(c, pe["id"], {"kind": "die", "t0": merge - 10, "dur": 90})
		L.clip(c, {"kind": "en_body", "t0": 0, "dur": merge, "at": me, "sprite": String(e["kind"]),
			"buzz": t, "toward": L.dir_of(me, from), "layer": "ground"})
		L.clip(c, {"kind": "en_weld", "t0": t, "dur": (merge - t) + 440, "at": me, "from": from,
			"slide0": 150, "slide1": 360, "merge": merge - t, "pal": HOT})
		L.seg(c, id, {"kind": "pop", "t0": merge, "dur": 300})
		L.claim(c, i, merge)
		_claim_rest(c, merge, Vector2(0, 1))
		c["hit"] = merge - int(c["t"])
		return merge + 200
	# the partner was not beside it: a torch flicker and nothing more
	L.seg(c, id, {"kind": "shake", "t0": t, "dur": 220, "amt": 0.04})
	L.clip(c, {"kind": "en_weld", "t0": t, "dur": 300, "at": me, "from": me, "slide0": 0, "slide1": 0,
		"merge": 9999, "pal": HOT})
	_claim_rest(c, t + 120, Vector2(0, 1))
	c["hit"] = 120
	return t + 220


## A status swallowed the intent: the machine revs and strains against it -
## steam venting, effort marks, and the status clamping down.
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
	var tile = e["intent"].get("tile", _ppos(c))
	if not (tile is Vector2i):
		tile = _ppos(c)
	var d := _dir_or_down(e["pos"], tile)
	L.seg(c, e["id"], {"kind": "struggle", "t0": t, "dur": 440})
	L.seg(c, e["id"], {"kind": "tint", "t0": t, "dur": 440, "col": L.status_col(status).lerp(Color.WHITE, 0.35)})
	L.clip(c, {"kind": "en_strain", "t0": t, "dur": 520, "at": e["pos"], "status": status, "dir": d})
	_claim_rest(c, t + 120, d)
	c["hit"] = 120
	return t + 360


## Smoke swallowed a ranged intent: the machine fires, the shot flies into
## the smoke beside the tender and comes apart, and a '?' pops over it.
static func _screened(c: Dictionary) -> int:
	var e: Dictionary = c["e"]
	var me: Vector2i = e["pos"]
	var p := _ppos(c)
	var intent := String(e["intent"].get("type", ""))
	var idx := -1
	for i in c["own"]:
		if String(c["events"][i].get("t", "")) == "screened":
			idx = i
			intent = String(c["events"][i].get("intent", intent))
	# where it dies: the screening tile nearest the machine (the sim's rule is
	# the tender's tile or a neighbour), a little short of its centre
	var q := p
	var best := 999
	for s in [p] + _arms(p):
		if bool(Content.terrain(L.tkind(c["pre"], s), "screens", false)) and L.man(me, s) < best:
			best = L.man(me, s)
			q = s
	var d := _dir_or_down(me, p)
	var stop := Vector2(q) - d * 0.35
	var fly := 110 + int(Vector2(me).distance_to(stop) * 40.0)
	var t := _start(c, 160 + fly)
	L.seg(c, e["id"], {"kind": "lunge", "t0": t, "dur": 180, "dir": -d, "reach": 0.12})
	L.seg(c, e["id"], {"kind": "lunge", "t0": t + 120, "dur": 200, "dir": d, "reach": 0.18})
	var t_go := t + 160
	L.clip(c, {"kind": "en_fizzle", "t0": t_go, "dur": fly + 560, "at": me, "from": me, "to": stop, "fly": fly,
		"intent": intent})
	if idx >= 0:
		L.claim(c, idx, t_go + fly)
	_claim_rest(c, t_go + fly, d)
	c["hit"] = t_go + fly - int(c["t"])
	return t_go + fly + 200


# --- paint -----------------------------------------------------------------------

static func paint(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	match String(cl["kind"]):
		"en_impact":
			_p_impact(cv, cl, k, V)
		"en_smear":
			_p_smear(cv, cl, k, V)
		"en_dust":
			_p_dust(cv, cl, k, V)
		"en_slam":
			_p_slam(cv, cl, k, V)
		"en_debris":
			_p_debris(cv, cl, k, V)
		"en_quake":
			_p_quake(cv, cl, k, V)
		"en_flood":
			_p_flood(cv, cl, k, V)
		"en_glob":
			_p_glob(cv, cl, k, V)
		"en_heat":
			_p_heat(cv, cl, k, V)
		"en_ember":
			_p_ember(cv, cl, k, V)
		"en_gather":
			_p_gather(cv, cl, k, V)
		"en_smoke":
			_p_smoke(cv, cl, k, V)
		"en_chain":
			_p_chain(cv, cl, k, V)
		"en_siphon":
			_p_siphon(cv, cl, k, V)
		"en_tar":
			_p_tar(cv, cl, k, V)
		"en_tendril":
			_p_tendril(cv, cl, k, V)
		"en_weld":
			_p_weld(cv, cl, k, V)
		"en_body":
			_p_body(cv, cl, k, V)
		"en_strain":
			_p_strain(cv, cl, k, V)
		"en_fizzle":
			_p_fizzle(cv, cl, k, V)
		"en_word":
			_p_word(cv, cl, k, V)


# --- paint helpers ---------------------------------------------------------------

static func _pal(cl: Dictionary, fallback: Dictionary) -> Dictionary:
	var p = cl.get("pal")
	return p if p is Dictionary and p.has("a") else fallback


static func _polar(ang: float, r: float) -> Vector2:
	return Vector2(cos(ang), sin(ang)) * r


## n hot streaks thrown from p inside a cone (`dir`, +-spread radians) and
## pulled down by gravity; u runs 0..1 through their flight.
static func _sparks(cv, p: Vector2, dir: Vector2, spread: float, n: int, reach: float, u: float, t: float,
		sd0: int, hot: Color, cool: Color, w: float) -> void:
	if u <= 0.0 or u >= 1.0:
		return
	var base := dir.angle()
	for i in n:
		var a := base + (D.h01(sd0 + i * 7) - 0.5) * 2.0 * spread
		var sp := 0.55 + 0.45 * D.h01(sd0 + i * 13 + 1)
		var v := Vector2(cos(a), sin(a))
		var dist := reach * sp * D.ease_out(u)
		var fall := t * 0.45 * u * u
		var head := p + v * dist + Vector2(0, fall)
		var tail := p + v * maxf(0.0, dist - t * 0.3 * (1.0 - u * 0.6)) + Vector2(0, fall * 0.7)
		D.line(cv, tail, head, D.ca(hot.lerp(cool, u), 1.0 - u * u), w)


## How high (tiles) a lob between two tiles may arc before its apex would
## leave the view (see _up).
static func _lob_room(V: Dictionary, a, b) -> float:
	var up := mini(_up(V, _tile_of(a), 2), _up(V, _tile_of(b), 2))
	return float(up) + 0.25


## A small rock chunk: an irregular quad.
static func _chunk(cv, p: Vector2, s: float, rot: float, col: Color) -> void:
	if s < 1.0 or col.a <= 0.01:
		return
	var pts := PackedVector2Array()
	for j in 4:
		var a := rot + TAU * float(j) / 4.0 + 0.35 * float(j % 2)
		pts.append(p + Vector2(cos(a), sin(a)) * s * (0.75 + 0.35 * float(j % 2)))
	cv.draw_colored_polygon(pts, col)


## A jagged crack from a out along `dir` (pixels), `sd0` picks its shape.
static func _crack(cv, a: Vector2, dir: Vector2, length: float, t: float, sd0: int, col: Color, w: float) -> void:
	if length < 2.0 or col.a <= 0.01:
		return
	var s := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([a])
	var n := 5
	for i in range(1, n + 1):
		var u := float(i) / float(n)
		var j := (D.h01(sd0 + i * 5) - 0.5) * t * 0.22 * (1.0 if i < n else 0.4)
		pts.append(a + dir * length * u + s * j)
	cv.draw_polyline(pts, col, maxf(1.0, w), true)


## A filled blob with a light rim and a glint: oil, tar, sludge in flight.
static func _blob(cv, p: Vector2, r: float, pal: Dictionary, a: float, t: float) -> void:
	if r < 0.8:
		return
	cv.draw_circle(p, r * 1.18, D.ca(pal["c"], 0.55 * a))
	cv.draw_circle(p, r, D.ca(pal["a"], a))
	cv.draw_arc(p, r * 0.92, PI * 0.95, PI * 1.75, 8, D.ca(pal["b"], 0.95 * a), maxf(1.2, t * 0.035), true)
	cv.draw_circle(p + Vector2(-r * 0.35, -r * 0.4), maxf(1.0, r * 0.22), D.ca(pal["b"], a))


## A tiny lightning bolt at p, `s` px tall.
static func _bolt(cv, p: Vector2, s: float, col: Color, core: Color) -> void:
	if s < 1.5 or col.a <= 0.01:
		return
	var pts := PackedVector2Array([p + Vector2(s * 0.15, -s * 0.5), p + Vector2(-s * 0.2, s * 0.05),
		p + Vector2(s * 0.12, s * 0.02), p + Vector2(-s * 0.12, s * 0.5)])
	cv.draw_polyline(pts, col, maxf(1.5, s * 0.28), true)
	cv.draw_polyline(pts, core, maxf(1.0, s * 0.1), true)


# --- paint: melee -------------------------------------------------------------------

static func _p_impact(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal := _pal(cl, HOT)
	var d: Vector2 = cl.get("dir", Vector2(1, 0))
	var hit := bool(cl.get("hit", true))
	var sc := (0.85 + 0.1 * clampf(float(cl.get("dmg", 1)), 1.0, 6.0)) * (1.0 if hit else 0.6)
	# the contact point: the face of the victim's tile the blow came through
	var c := D.px(V, cl["at"]) - d * t * 0.28
	var s := Vector2(-d.y, d.x)
	if k < 0.3:
		var u := k / 0.3
		D.glow(cv, c, t * 0.5 * sc * (1.0 - 0.4 * u), D.ca(pal["b"], 0.95 * (1.0 - u)))
		D.star(cv, c, t * (0.26 + 0.38 * u) * sc, D.ca(Color.WHITE, 1.0 - u), 4, d.angle() + PI * 0.25, t * 0.08)
		D.star(cv, c, t * (0.16 + 0.24 * u) * sc, D.ca(pal["a"], 1.0 - u), 4, d.angle(), t * 0.06)
	D.ring(cv, c, t * (0.16 + 0.4 * D.ease_out(k)) * sc, D.ca(pal["b"], 0.9 * (1.0 - k)), t * 0.07 * (1.0 - k))
	var n := int(5 + 2 * sc)
	# grinding sparks spray off both sides of the contact and fall - short of
	# the view's top edge when the victim stands on the top row
	var reach := t * minf(1.2 * sc, float(_up(V, _tile_of(cl["at"]), 2)) + 0.55)
	_sparks(cv, c, s - d * 0.4, 0.6, n, reach, k, t, 11, pal["b"], pal["a"], t * 0.07)
	_sparks(cv, c, -s - d * 0.4, 0.6, n, reach, k, t, 37, pal["b"], pal["a"], t * 0.07)
	_sparks(cv, c, -d, 0.5, 3, minf(t * 0.8 * sc, reach), k, t, 63, Color.WHITE, pal["b"], t * 0.06)
	if bool(cl.get("shield", false)):
		# the shield takes it: a blue shell flares on the side the blow came from
		var ang := (-d).angle()
		var sa := 1.0 - D.ease_in(k)
		cv.draw_arc(D.px(V, cl["at"]), t * (0.46 + 0.06 * k), ang - 1.2, ang + 1.2, 14, D.ca(SHIELD, 0.95 * sa),
			maxf(2.0, t * 0.09 * sa), true)
		cv.draw_arc(D.px(V, cl["at"]), t * (0.46 + 0.06 * k), ang - 0.7, ang + 0.7, 10, D.ca(Color.WHITE, 0.8 * sa),
			maxf(1.0, t * 0.035), true)
	if not hit:
		for i in 3:
			cv.draw_circle(c + Vector2((float(i) - 1.0) * t * 0.2 * (0.5 + k), t * 0.2 - t * 0.15 * k),
				t * (0.07 + 0.1 * k), D.ca(DUST, 0.5 * (1.0 - k)))


static func _p_smear(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var d: Vector2 = cl.get("dir", Vector2(1, 0))
	var a := D.px(V, cl["at"])
	var s := Vector2(-d.y, d.x)
	for j in 3:
		var off := s * t * (float(j) - 1.0) * 0.2
		var u := D.win(k, 0.08 * float(j), 0.7 + 0.08 * float(j))
		var head := a + d * t * (0.05 + 0.5 * D.ease_out(u)) + off
		var tail := a - d * t * (0.35 - 0.3 * u) + off
		D.line(cv, tail, head, D.ca(Color("e6edf2"), 0.75 * (1.0 - u)), t * 0.04)


static func _p_dust(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var m := float(cl.get("mag", 1.0))
	var c := D.px(V, cl["at"]) + Vector2(0, t * 0.36)
	var u := D.ease_out(k)
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		var far := 1.0 if i < 2 else 0.6
		var q := c + Vector2(side * t * (0.12 + 0.34 * u * m) * far, -t * (0.02 + 0.1 * u) * float(i / 2 + 1))
		cv.draw_circle(q, t * (0.06 + 0.09 * u) * (0.7 + 0.3 * m), D.ca(DUST, 0.6 * (1.0 - k)))


# --- paint: boss blows --------------------------------------------------------------

static func _p_slam(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var ms := k * float(cl["dur"])
	var imp := float(cl["imp"])
	var tiles: Array = cl.get("tiles", [])
	var c := D.px(V, cl["at"])
	if ms < imp:
		# the warning: the cross throbs harder as the boss comes down, and a
		# reticle closes on the tile it will land on
		var u := ms / imp
		var a := 0.16 + 0.3 * u + 0.1 * sin(ms * 0.05)
		for p in tiles:
			cv.draw_rect(D.tile_rect(V, p).grow(-t * 0.05), D.ca(WARN, a))
		var land := D.px(V, cl["land"]) + Vector2(0, t * 0.3)
		cv.draw_set_transform(land, 0.0, Vector2(1.0, 0.45))
		cv.draw_circle(Vector2.ZERO, t * (0.25 + 0.3 * u), Color(0, 0, 0, 0.18 + 0.3 * u))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var r := t * (1.05 - 0.55 * D.ease_in(u))
		var lc := D.px(V, cl["land"])
		for j in 4:
			var ang := PI * 0.25 + float(j) * PI * 0.5
			var q := lc + _polar(ang, r)
			D.line(cv, q, q + _polar(ang + PI * 0.75, t * 0.22), D.ca(MACHINE["b"], 0.4 + 0.5 * u), t * 0.05)
			D.line(cv, q, q + _polar(ang - PI * 0.75, t * 0.22), D.ca(MACHINE["b"], 0.4 + 0.5 * u), t * 0.05)
		return
	var v := clampf((ms - imp) / maxf(1.0, float(cl["dur"]) - imp), 0.0, 1.0)
	var f := 1.0 - v
	var hot := HOT["b"].lerp(WARN, minf(1.0, v * 3.0))
	for p in tiles:
		cv.draw_rect(D.tile_rect(V, p).grow(-t * 0.04), D.ca(hot, 0.7 * f * f))
	var grow := D.ease_out(minf(1.0, v * 3.5))
	# the shockwave and the crack running up stop at the view's top edge
	var room := float(_up(V, _tile_of(cl["at"]), 2)) + 0.6
	for j in 4:
		var dv := Vector2(L.DIRS[j])
		var reach := minf(1.35, room - 0.3) if L.DIRS[j].y < 0 else 1.35
		_crack(cv, c, dv, t * reach * grow, t, 17 + j * 31, D.ca(Color("1a120c"), 0.9 * f), t * 0.07)
		_crack(cv, c + dv * t * 0.5, dv.rotated(0.9), t * 0.4 * grow, t, 71 + j * 13, D.ca(Color("1a120c"), 0.8 * f), t * 0.05)
	var r1 := minf(2.0, room)
	D.ring(cv, c, t * (0.35 + (r1 - 0.35) * D.ease_out(v)), D.ca(MACHINE["b"], 0.9 * f), t * 0.16 * f)
	D.ring(cv, c, t * (0.2 + (r1 * 0.6 - 0.2) * D.ease_out(v)), D.ca(HOT["a"], 0.7 * f), t * 0.08 * f)


static func _p_debris(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var tiles: Array = cl.get("tiles", [cl["at"]])
	if tiles.is_empty():
		tiles = [cl["at"]]
	var n := int(cl.get("n", 12))
	for i in n:
		var u := D.win(k, 0.03 * float(i % 3), 1.0)
		var p := D.px(V, tiles[i % tiles.size()]) + Vector2((D.h01(i * 5 + 1) - 0.5) * t * 0.6, t * 0.25)
		var vx := (D.h01(i * 11 + 3) - 0.5) * t * 1.3
		var vy := t * (0.75 + 0.75 * D.h01(i * 17 + 5))
		var q := p + Vector2(vx * u, -vy * u + vy * 1.25 * u * u)
		var s := t * (0.08 + 0.07 * D.h01(i * 23 + 7))
		var col: Color = ROCK[i % ROCK.size()]
		var a := 1.0 - D.win(u, 0.65, 1.0)
		_chunk(cv, q, s * 1.2, u * 7.0 + float(i), D.ca(Color("1a120c"), 0.7 * a))
		_chunk(cv, q, s, u * 7.0 + float(i), D.ca(col, a))
	# a burst of dust where it hit
	var c := D.px(V, cl["at"]) + Vector2(0, t * 0.3)
	for i in 5:
		var ang := PI + PI * float(i) / 4.0
		cv.draw_circle(c + _polar(ang, t * (0.3 + 0.7 * D.ease_out(k))), t * (0.1 + 0.16 * k),
			D.ca(DUST, 0.45 * (1.0 - k)))


static func _p_quake(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var c := D.px(V, cl["at"])
	var f := 1.0 - k
	# the four tiles the quake reaches flash, then cracks run out through them
	for p in cl.get("tiles", []):
		cv.draw_rect(D.tile_rect(V, p).grow(-t * 0.05), D.ca(HOT["b"].lerp(WARN, minf(1.0, k * 3.0)), 0.6 * f * f))
	var grow := D.ease_out(minf(1.0, k * 3.0))
	for j in 4:
		_crack(cv, c + Vector2(L.DIRS[j]) * t * 0.3, Vector2(L.DIRS[j]).rotated(0.25 * (D.h01(j) - 0.5)),
			t * 1.2 * grow, t, 5 + j * 19, D.ca(Color("1a120c"), 0.9 * f), t * 0.07)
	var g := c + Vector2(0, t * 0.3)
	cv.draw_set_transform(g, 0.0, Vector2(1.0, 0.55))
	for j in 3:
		var u := D.win(k, float(j) * 0.14, float(j) * 0.14 + 0.62)
		if u > 0.0 and u < 1.0:
			D.ring(cv, Vector2.ZERO, t * (0.45 + 1.45 * D.ease_out(u)), D.ca(DUST if j > 0 else MACHINE["b"], 0.9 * (1.0 - u)),
				t * 0.13 * (1.0 - u))
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- paint: board-wide ---------------------------------------------------------------

static func _p_flood(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var ms := k * float(cl["dur"]) - float(cl.get("lead", 0))
	var per := maxf(1.0, float(cl["per"]))
	var row := int(cl["row"])
	var fx := float(cl["from_x"])
	var run := maxf(0.0, ms / per)
	var fade := D.tail(k, 0.7)
	# the fresh oil gleams as it spreads, then settles into the tiles
	for x in cl.get("xs", []):
		var dx := absf(float(x) - fx)
		if dx > run:
			continue
		var since := (run - dx) * per
		var a := clampf(1.0 - since / 320.0, 0.0, 1.0)
		if a <= 0.02 or not _seen(V, Vector2i(int(x), row)):
			continue
		var r := D.tile_rect(V, Vector2(x, row))
		cv.draw_rect(r.grow(-t * 0.04), D.ca(OIL["a"], 0.5 * a * fade))
	var y := D.px(V, Vector2(fx, row)).y
	for side in [-1.0, 1.0]:
		var sd: float = side
		var lim := float(cl["x_min"]) - 0.4 if sd < 0.0 else float(cl["x_max"]) + 0.4
		var head := fx + sd * run
		var past := (head - lim) * sd
		if past > 0.0:
			head = lim
		var bx := D.px(V, Vector2(head, row)).x
		var b := Vector2(bx, y)
		if not _seen(V, Vector2i(roundi(head), row)):
			continue
		if past <= 0.0:
			# the crest: a rounded hump of oil leaning into its run, a sheen
			# along its back, a pale lip curling over the front and spray ahead
			var bob := sin(ms * 0.03) * t * 0.04
			var poly := PackedVector2Array()
			for i in 13:
				var u := float(i) / 12.0
				var hump := sin(u * PI)
				# the top leans forward: the higher a point, the further ahead
				var x := lerpf(-0.62, 0.3, u) + 0.22 * hump
				poly.append(b + Vector2(sd * t * x, t * 0.36 - t * (0.66 * hump) - bob * hump))
			cv.draw_colored_polygon(poly, D.ca(OIL["c"], 0.9))
			var inner := PackedVector2Array()
			for i in 13:
				inner.append(b + (poly[i] - b) * 0.8 + Vector2(-sd * t * 0.04, t * 0.08))
			cv.draw_colored_polygon(inner, D.ca(OIL["a"], 1.0))
			var back := PackedVector2Array()
			for i in range(3, 8):
				back.append(inner[i] + Vector2(-sd * t * 0.02, t * 0.04))
			cv.draw_polyline(back, D.ca(OIL["b"], 0.9), maxf(1.5, t * 0.05), true)
			# the foam lip curling over the front
			for i in 3:
				var q: Vector2 = poly[6 + i]
				cv.draw_circle(q + Vector2(sd * t * 0.03, 0), t * (0.075 - 0.015 * float(i)), D.ca(Color("e8e0f4"), 0.95))
			var lip: Vector2 = poly[7]
			for i in 4:
				var ph := fposmod(ms / 150.0 + float(i) * 0.25, 1.0)
				cv.draw_circle(lip + Vector2(sd * t * (0.12 + 0.4 * ph), -t * 0.22 * sin(ph * PI) + t * 0.3 * ph),
					t * 0.05 * (1.0 - ph), D.ca(OIL["b"], 0.95))
		else:
			# the crest breaks on the wall and spatters up
			var u := clampf(past * per / 260.0, 0.0, 1.0)
			for i in 5:
				var ang := -PI * 0.5 + (float(i) - 2.0) * 0.35 - sd * 0.4
				cv.draw_circle(b + _polar(ang, t * 0.6 * D.ease_out(u)) + Vector2(0, t * 0.5 * u * u), t * 0.06 * (1.0 - u),
					D.ca(OIL["b"], 1.0 - u))
			cv.draw_circle(b, t * 0.2 * (1.0 - u), D.ca(OIL["a"], 0.8 * (1.0 - u)))


## A glob thrown in an arc (oil, sludge): flight, then a splat with droplets.
static func _p_glob(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal := _pal(cl, OIL)
	var size := float(cl.get("size", 1.0))
	var ms := k * float(cl["dur"])
	var fly := maxf(1.0, float(cl["fly"]))
	var a := D.px(V, cl["from"]) + Vector2(0, -t * 0.25)
	var b := D.px(V, cl["to"])
	# a lob that clearly goes up and comes down, but never over the view's top
	var h := minf(t * (0.62 + 0.08 * a.distance_to(b) / t), _lob_room(V, cl["from"], cl["to"]) * t)
	if bool(cl.get("stream", false)):
		# a gush: a thick rope of oil whose tail follows its head down
		var u1 := minf(1.0, ms / fly)
		var u0 := clampf((ms - fly * 0.45) / fly, 0.0, 1.0)
		if u1 - u0 > 0.02:
			var rope := PackedVector2Array()
			for j in 9:
				rope.append(D.arc_point(a, b, lerpf(u0, u1, float(j) / 8.0), h * 0.4))
			cv.draw_polyline(rope, D.ca(pal["c"], 0.9), maxf(2.0, t * 0.26 * size), true)
			cv.draw_polyline(rope, D.ca(pal["a"], 1.0), maxf(2.0, t * 0.18 * size), true)
			var shine := PackedVector2Array()
			for j in 9:
				shine.append(rope[j] + Vector2(-t * 0.04 * size, 0))
			cv.draw_polyline(shine, D.ca(pal["b"], 0.8), maxf(1.0, t * 0.04), true)
		if ms < fly:
			_blob(cv, D.arc_point(a, b, u1, h * 0.4), t * 0.14 * size, pal, 1.0, t)
			return
	elif ms < fly:
		var u := ms / fly
		for j in 2:
			var ub := u - 0.07 * float(j + 1)
			if ub > 0.0:
				cv.draw_circle(D.arc_point(a, b, ub, h), t * (0.06 - 0.015 * float(j)) * size, D.ca(pal["a"], 0.85))
		_blob(cv, D.arc_point(a, b, u, h), t * 0.15 * size, pal, 1.0, t)
		return
	var s := clampf((ms - fly) / maxf(1.0, float(cl["dur"]) - fly), 0.0, 1.0)
	var f := 1.0 - s
	var g := b + Vector2(0, t * 0.12)
	cv.draw_set_transform(g, 0.0, Vector2(1.0, 0.5))
	cv.draw_circle(Vector2.ZERO, t * 0.42 * size * D.ease_out(minf(1.0, s * 4.0)), D.ca(pal["a"], 0.8 * f))
	D.ring(cv, Vector2.ZERO, t * 0.46 * size * D.ease_out(minf(1.0, s * 3.0)), D.ca(pal["b"], 0.8 * f), t * 0.06)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in 6:
		var ang := -PI * (0.1 + 0.8 * float(i) / 5.0)
		var q := g + _polar(ang, t * 0.5 * size * D.ease_out(s)) + Vector2(0, t * 0.6 * s * s)
		cv.draw_circle(q, t * 0.055 * size * f, D.ca(pal["b"] if i % 2 == 0 else pal["a"], f))


static func _p_heat(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal := _pal(cl, HEAT)
	var c := D.px(V, cl["at"])
	# sparks and the heat ring stay inside the view (see _up)
	var room := float(_up(V, _tile_of(cl["at"]), 2)) + 0.5
	var g := D.pulse(D.win(k, 0.0, 0.85))
	D.glow(cv, c, t * (0.45 + 0.55 * g), D.ca(pal["a"], 0.65 * g))
	cv.draw_circle(c, t * 0.14 * (0.4 + g), D.ca(pal["b"], g))
	var rise := clampf(room - 0.3, 0.5, 1.2)
	for i in 8:
		var u := D.win(k, float(i) * 0.06, float(i) * 0.06 + 0.5)
		if u <= 0.0 or u >= 1.0:
			continue
		var x := (D.h01(i * 7 + 3) - 0.5) * t * 0.9
		D.twinkle(cv, c + Vector2(x + sin(u * 7.0 + float(i)) * t * 0.08, -t * rise * u), t * 0.08 * (1.0 - u),
			D.ca(pal["b"].lerp(pal["a"], u), 1.0 - u))
	var w := D.win(k, 0.3, 0.9)
	if w > 0.0 and w < 1.0:
		var rr := minf(1.5, room)
		D.ring(cv, c, t * (0.4 + (rr - 0.4) * D.ease_out(w)), D.ca(pal["a"], 0.9 * (1.0 - w)), t * 0.12 * (1.0 - w))


static func _p_ember(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal := _pal(cl, HEAT)
	var ms := k * float(cl["dur"])
	var fly := maxf(1.0, float(cl["fly"]))
	var a := D.px(V, cl["from"])
	var b := D.px(V, cl["to"])
	var h := minf(t * (0.45 + 0.08 * a.distance_to(b) / t), _lob_room(V, cl["from"], cl["to"]) * t)
	if ms < fly:
		var u := ms / fly
		# a fireball with a flame tail streaming back along its arc
		var tail := PackedVector2Array()
		for j in 7:
			tail.append(D.arc_point(a, b, maxf(0.0, u - 0.16 * float(6 - j) / 6.0), h))
		cv.draw_polyline(tail, D.ca(pal["c"], 0.55), maxf(2.0, t * 0.16), true)
		cv.draw_polyline(tail, D.ca(pal["a"], 0.9), maxf(1.5, t * 0.09), true)
		var q := D.arc_point(a, b, u, h)
		D.glow(cv, q, t * 0.26, D.ca(pal["a"], 0.85))
		cv.draw_circle(q, t * 0.1, pal["b"])
		return
	# the slick catches: a flash, tongues of flame leaping up, a heat ring
	var s := clampf((ms - fly) / maxf(1.0, float(cl["dur"]) - fly), 0.0, 1.0)
	var f := 1.0 - s
	D.glow(cv, b, t * (0.3 + 0.3 * D.ease_out(s)), D.ca(pal["b"], 0.8 * f))
	for i in 4:
		var x := (float(i) - 1.5) * t * 0.17
		var ht := t * (0.35 + 0.35 * D.pulse(minf(1.0, s * 1.4))) * (1.0 - 0.25 * absf(float(i) - 1.5))
		D.spike(cv, b + Vector2(x, t * 0.28), b + Vector2(x * 0.7, t * 0.28 - ht), t * 0.2, D.ca(pal["a"] if i % 3 == 0 else pal["b"], f))
	D.ring(cv, b, t * (0.25 + 0.45 * D.ease_out(s)), D.ca(pal["a"], 0.9 * f), t * 0.07 * f)


static func _p_gather(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal := _pal(cl, HEAT)
	var c := D.px(V, cl["at"])
	var ms := k * float(cl["dur"])
	var g := D.ease_in(minf(1.0, k / 0.75))
	var rel := D.win(k, 0.73, 1.0)
	var beat := 0.5 + 0.5 * sin(ms * (0.02 + 0.03 * g))
	D.glow(cv, c, t * (0.3 + 0.45 * g) * (1.0 - 0.5 * rel), D.ca(pal["a"], (0.35 + 0.5 * g) * (0.8 + 0.2 * beat)))
	cv.draw_circle(c, t * (0.07 + 0.1 * g + 0.02 * beat) * (1.0 - rel), D.ca(pal["b"], 0.95))
	# a ring of heat tightening round the core
	if rel <= 0.0:
		D.ring(cv, c, t * (0.95 - 0.5 * g), D.ca(pal["a"], 0.4 + 0.5 * g), t * (0.04 + 0.05 * g))
	# heat streaks drawn in to the core from all round (from inside the view)
	var reach := minf(1.4, float(_up(V, _tile_of(cl["at"]), 2)) + 0.45)
	for i in 12:
		var st := D.h01(i * 13 + 2) * 0.4
		var u := D.win(k, st, st + 0.4)
		if u <= 0.0 or u >= 1.0:
			continue
		var ang := D.h01(i * 29 + 7) * TAU + u * 1.4
		var r := t * reach * (1.0 - D.ease_in(u))
		var head := c + _polar(ang, r)
		var tail := c + _polar(ang - 0.25, r + t * 0.3)
		# a hot streak: an orange body with a white-hot core line, brightest
		# as it nears the core
		D.line(cv, head, tail, D.ca(pal["a"], 0.6 * u + 0.35), t * 0.075)
		D.line(cv, head, head.lerp(tail, 0.5), D.ca(pal["b"], 0.5 + 0.5 * u), t * 0.035)
		cv.draw_circle(head, t * 0.05, D.ca(pal["b"], 0.7 + 0.3 * u))
	if rel > 0.0 and rel < 1.0:
		D.ring(cv, c, t * (0.3 + 0.9 * D.ease_out(rel)), D.ca(pal["b"], 1.0 - rel), t * 0.12 * (1.0 - rel))
		D.glow(cv, c, t * 0.5 * (1.0 - rel), D.ca(pal["b"], 0.7 * (1.0 - rel)))


static func _p_smoke(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var big := bool(cl.get("big", false))
	var top := D.px(V, cl["at"]) + Vector2(0, -t * 0.48)
	var n := 9 if big else 4
	var want := 1.4 if big else 0.75
	var grow := 0.3 if big else 0.16
	# the column may not climb past the view's top edge (the status strip
	# sits there, and a stack on the top row would belch its whole column
	# into it): what it cannot rise it drifts sideways, a plume in the wind
	var room := float(_up(V, _tile_of(cl["at"]), 2)) + 0.02
	var rise := clampf(room - 0.2 - (0.14 + grow) * 0.8, 0.25, want)
	var bent := float(cl.get("bend", 0.0)) > 0.0
	var lean := maxf((want - rise) * 0.9, float(cl.get("bend", 0.0))) * float(cl.get("lean", 1))
	if bent:
		rise *= 0.7
	# the ember glow at the mouth as it belches
	var gm := D.pulse(D.win(k, 0.0, 0.45))
	D.glow(cv, top, t * 0.22 * gm, D.ca(HEAT["a"], 0.7 * gm))
	for i in n:
		var st := float(i) * (0.06 if big else 0.1)
		var u := D.win(k, st, st + 0.6)
		if u <= 0.0 or u >= 1.0:
			continue
		var drift := (D.h01(i * 9 + 1) - 0.5) * t * 0.5 * u
		# a plume in the wind bends late; one told to bend (off a spawn tile)
		# leans from the mouth
		var side_u := D.ease_out(u) if bent else D.ease_in(u)
		var q := top + Vector2(drift + lean * t * side_u, -t * (0.1 + rise * D.ease_out(u)))
		var r := t * (0.14 + grow * u)
		var a := 0.9 * (1.0 - u * u)
		cv.draw_circle(q, r * 1.08, D.ca(Color("262422"), 0.6 * a))
		cv.draw_circle(q, r, D.ca(SMOKE_DARK, a))
		cv.draw_circle(q + Vector2(-r * 0.25, -r * 0.3), r * 0.6, D.ca(SMOKE_LIGHT, 0.6 * a))
	if big:
		for i in 4:
			var u := D.win(k, 0.02 + float(i) * 0.05, 0.4 + float(i) * 0.05)
			if u > 0.0 and u < 1.0:
				cv.draw_circle(top + Vector2((D.h01(i * 3) - 0.5) * t * 0.4 + lean * t * 0.7 * u * u, -t * rise * u),
					t * 0.035, D.ca(HEAT["b"], 1.0 - u))


# --- paint: ranged -------------------------------------------------------------------

static func _p_chain(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal := _pal(cl, MAGNET)
	var dur := float(cl["dur"])
	var ms := k * dur
	var shoot := float(cl["shoot"])
	var clamp_ms := float(cl["clamp"])
	var pull := float(cl["pull"])
	var step := maxf(1.0, float(cl["step"]))
	var pts: Array = cl["pts"]
	var crane := D.px(V, cl["from"]) + Vector2(0, -t * 0.12)
	# where the tender is being hauled right now
	var tp: Vector2 = pts[0]
	if pts.size() > 1 and ms > pull:
		var f := (ms - pull) / step
		var j := mini(int(f), pts.size() - 2)
		tp = (pts[j] as Vector2).lerp(pts[j + 1], clampf(f - float(j), 0.0, 1.0))
	var tpx := D.px(V, tp)
	var missed := bool(cl.get("missed", false))
	var held := bool(cl.get("held", false))
	var fade := 1.0 - D.win(ms, dur - 190.0, dur)
	# the magnet head charges before it fires
	var ch := D.win(ms, 0.0, shoot)
	D.glow(cv, crane, t * (0.16 + 0.12 * ch), D.ca(pal["a"], 0.45 * fade))
	if ms < shoot:
		for i in 4:
			var ang := TAU * float(i) / 4.0 + ms * 0.02
			D.line(cv, crane + _polar(ang, t * 0.4 * (1.0 - ch)), crane + _polar(ang, t * 0.28 * (1.0 - ch)),
				D.ca(pal["b"], 0.9), t * 0.04)
		return
	var head := tpx
	if ms < clamp_ms:
		var u := D.ease_out((ms - shoot) / maxf(1.0, clamp_ms - shoot))
		head = crane.lerp(tpx, u * (0.8 if missed else 1.0))
	elif missed:
		head = crane.lerp(tpx, 0.8) + Vector2(0, t * 0.5 * D.ease_in(D.win(ms, clamp_ms, dur)))
	var dv := head - crane
	var dl := dv.length()
	if dl < 1.0:
		return
	var dn := dv / dl
	var sn := Vector2(-dn.y, dn.x)
	var strain := 0.0
	if held and ms > clamp_ms:
		strain = t * 0.05 * sin(ms * 0.09)
	# the magnetic field hugging the chain, then the links
	D.line(cv, crane, head, D.ca(pal["a"], 0.3 * fade), t * 0.24)
	D.wavy(cv, crane, head, t * 0.13, maxf(1.0, dl / t), ms * 0.03, D.ca(pal["b"], 0.55 * fade), t * 0.03, 16)
	var n := clampi(int(dl / (t * 0.17)), 1, 40)
	for i in n:
		var u := (float(i) + 0.5) / float(n)
		var q := crane + dv * u + sn * (strain * sin(u * PI) + t * 0.06 * sin(u * PI) * (1.0 - D.win(ms, clamp_ms, pull)))
		if i % 2 == 0:
			D.line(cv, q - dn * t * 0.08, q + dn * t * 0.08, D.ca(STEEL_DARK, fade), t * 0.09)
			D.line(cv, q - dn * t * 0.07, q + dn * t * 0.07, D.ca(STEEL, fade), t * 0.045)
		else:
			D.ring(cv, q, t * 0.055, D.ca(STEEL, fade), t * 0.035)
	# the clamp: a red horseshoe magnet biting on
	var ang0 := dn.angle()
	cv.draw_arc(head - dn * t * 0.06, t * 0.15, ang0 + PI * 0.5, ang0 + PI * 1.5, 10, D.ca(pal["c"], fade), maxf(2.0, t * 0.09), true)
	for sd in [-1.0, 1.0]:
		var tip: Vector2 = head - dn * t * 0.06 + sn * float(sd) * t * 0.15
		D.line(cv, tip, tip + dn * t * 0.1, D.ca(STEEL, fade), t * 0.08)
	if ms >= clamp_ms and ms < clamp_ms + 200.0:
		var cu := (ms - clamp_ms) / 200.0
		D.ring(cv, head, t * (0.2 + 0.4 * D.ease_out(cu)), D.ca(pal["b"], 1.0 - cu), t * 0.07)
	if held and ms > clamp_ms:
		# roots hold the tender: earth-coloured grips flare at its feet
		var hu := D.win(ms, clamp_ms, clamp_ms + 320.0)
		var feet := tpx + Vector2(0, t * 0.36)
		for i in 5:
			var ang := PI + PI * float(i) / 4.0
			D.line(cv, feet, feet + _polar(ang, t * 0.32 * D.ease_out(hu)), D.ca(Color("a8845a"), (1.0 - hu) * fade), t * 0.06)
		if ms > dur - 260.0:
			_sparks(cv, head, -dn, 1.2, 6, t * 0.6, D.win(ms, dur - 260.0, dur), t, 53, pal["b"], pal["a"], t * 0.045)


static func _p_siphon(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal := _pal(cl, CHARGE)
	var dur := float(cl["dur"])
	var ms := k * dur
	var a := D.px(V, cl["from"])
	var b := D.px(V, cl["to"])
	var link := float(cl["link"])
	var gap := float(cl["gap"])
	var travel := maxf(1.0, float(cl["travel"]))
	var n := int(cl["n"])
	var on := D.win(ms, 0.0, link) * (1.0 - D.win(ms, dur - 160.0, dur))
	var flick := 0.55 + 0.3 * sin(ms * 0.08)
	# the siphon beam, drone to tender, and a charge-drawing ring on the tender
	D.wavy(cv, a, a.lerp(b, D.ease_out(D.win(ms, 0.0, link))), t * 0.07, 2.5, ms * 0.025, D.ca(pal["c"], on * flick), t * 0.07, 16)
	D.line(cv, a, a.lerp(b, D.ease_out(D.win(ms, 0.0, link))), D.ca(pal["b"], 0.5 * on), t * 0.025)
	if ms > link and n > 0:
		var ru := fposmod((ms - link) / 240.0, 1.0)
		D.ring(cv, b, t * (0.45 - 0.25 * ru), D.ca(pal["a"], 0.7 * ru * on), t * 0.05)
	var dn := (a - b).normalized()
	var sn := Vector2(-dn.y, dn.x)
	var got := 0.0
	for i in n:
		var st := link + float(i) * gap
		var u := (ms - st) / travel
		if u >= 1.0:
			got = maxf(got, 1.0 - clampf((u - 1.0) * travel / 200.0, 0.0, 1.0))
		if u <= 0.0 or u >= 1.0:
			continue
		var jit := (D.h01(i * 7 + 1) - 0.5) * t * 0.5 * (1.0 - u)
		var q := b.lerp(a, D.ease_in(u)) + sn * (jit + sin(u * PI * 2.0 + float(i)) * t * 0.06)
		D.glow(cv, q, t * 0.16, D.ca(pal["a"], 0.35))
		_bolt(cv, q, t * 0.28 * (1.0 - 0.25 * u), D.ca(pal["a"], 1.0), D.ca(pal["b"], 1.0))
	if got > 0.0:
		D.glow(cv, a, t * 0.35, D.ca(pal["a"], 0.6 * got))


static func _p_tar(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal := _pal(cl, TAR)
	var ms := k * float(cl["dur"])
	var fly := maxf(1.0, float(cl["fly"]))
	var a := D.px(V, cl["from"]) + Vector2(0, t * 0.08)
	var b := D.px(V, cl["to"])
	var hit := bool(cl.get("hit", true))
	var h := minf(t * (0.45 + 0.12 * a.distance_to(b) / t), _lob_room(V, cl["from"], cl["to"]) * t)
	if ms < fly:
		var u := ms / fly
		for j in 3:
			var ub := u - 0.06 * float(j + 1)
			if ub > 0.0:
				cv.draw_circle(D.arc_point(a, b, ub, h), t * (0.07 - 0.015 * float(j)), D.ca(pal["a"], 0.9))
		_blob(cv, D.arc_point(a, b, u, h), t * 0.17, pal, 1.0, t)
		return
	var s := clampf((ms - fly) / maxf(1.0, float(cl["dur"]) - fly), 0.0, 1.0)
	var f := D.tail(s, 0.5)
	var burst := D.ease_out(minf(1.0, s * 5.0))
	if not hit:
		var g := b + Vector2(0, t * 0.2)
		cv.draw_set_transform(g, 0.0, Vector2(1.0, 0.45))
		cv.draw_circle(Vector2.ZERO, t * 0.3 * burst, D.ca(pal["a"], 0.85 * f))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for i in 5:
			var ang := -PI * (0.1 + 0.8 * float(i) / 4.0)
			cv.draw_circle(g + _polar(ang, t * 0.4 * burst), t * 0.05, D.ca(pal["a"], f))
		return
	# splat: tar thrown out round the tender and stuck there, drips running down
	var c := b + Vector2(0, -t * 0.05)
	# the splat itself: a dark flash on the tender that thins out fast
	cv.draw_circle(c, t * 0.26 * burst, D.ca(pal["a"], 0.7 * (1.0 - D.win(s, 0.0, 0.3))))
	D.ring(cv, c, t * (0.22 + 0.3 * burst), D.ca(pal["b"], 0.9 * (1.0 - minf(1.0, s * 3.0))), t * 0.06)
	for i in 8:
		var ang := TAU * float(i) / 8.0 + D.h01(i * 5) * 0.6
		var r := t * (0.24 + 0.3 * burst) * (0.75 + 0.35 * D.h01(i * 3 + 1))
		var q := c + _polar(ang, r) + Vector2(0, t * 0.1 * s)
		cv.draw_circle(q, t * (0.065 + 0.035 * D.h01(i)), D.ca(pal["a"], f))
		if i % 2 == 0:
			cv.draw_circle(q + Vector2(-t * 0.015, -t * 0.02), t * 0.022, D.ca(pal["b"], f))
	# a few drips run down off the tender's sides
	for j in 2:
		var x := (float(j) * 2.0 - 1.0) * t * 0.2
		var top := c + Vector2(x, t * 0.05)
		var drip := top + Vector2(0, t * (0.08 + 0.26 * D.ease_out(s) * (0.6 + 0.4 * D.h01(j + 9))))
		D.line(cv, top, drip, D.ca(pal["a"], 0.9 * f), t * 0.06)
		cv.draw_circle(drip, t * 0.045, D.ca(pal["a"], 0.9 * f))


static func _p_tendril(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var dur := float(cl["dur"])
	var ms := k * dur
	var grab := maxf(1.0, float(cl["grab"]))
	var back := float(cl["back"])
	var a := D.px(V, cl["from"]) + Vector2(0, t * 0.25)
	var b := D.px(V, cl["to"]) + Vector2(0, t * 0.12)
	var ext := 1.0
	if ms < grab:
		ext = D.ease_out(ms / grab)
	elif ms > back:
		ext = 1.0 - D.ease_in(clampf((ms - back) / maxf(1.0, dur - back), 0.0, 1.0))
	var tip := a.lerp(b, ext)
	var waves := maxf(1.0, a.distance_to(b) / t)
	D.wavy(cv, a, tip, t * 0.12, waves, ms * 0.012, D.ca(MUD["c"], 0.95), t * 0.14, 14)
	D.wavy(cv, a, tip, t * 0.12, waves, ms * 0.012, D.ca(MUD["a"], 0.95), t * 0.06, 14)
	cv.draw_circle(tip, t * 0.08, D.ca(MUD["b"], 0.95))
	if ms >= grab:
		# the growth tears up: leaves flung, then ridden back to the boss
		var g := D.win(ms, grab, grab + 300.0)
		if g < 1.0:
			for i in 5:
				var ang := -PI * (0.15 + 0.7 * float(i) / 4.0)
				D.leaf(cv, b + _polar(ang, t * 0.45 * D.ease_out(g)) + Vector2(0, t * 0.3 * g * g), ang + g * 3.0,
					t * 0.2, D.ca(LEAF, 1.0 - g))
		for j in 3:
			var u := D.win(ms, grab + 80.0 + float(j) * 45.0, back + 180.0 + float(j) * 45.0)
			if u > 0.0 and u < 1.0:
				cv.draw_circle(b.lerp(a, D.ease_in(u)), t * 0.06, D.ca(LEAF, 0.95))


# --- paint: fuse, blocked, screened ----------------------------------------------------

static func _p_weld(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var pal := _pal(cl, HOT)
	var ms := k * float(cl["dur"])
	var A := D.px(V, cl["at"])
	var P0 := D.px(V, cl["from"])
	var s0 := float(cl["slide0"])
	var s1 := float(cl["slide1"])
	var merge := float(cl["merge"])
	var pp := P0
	if ms > s0 and s1 > s0:
		pp = P0.lerp(A, clampf((ms - s0) / (s1 - s0), 0.0, 1.0))
	if ms < merge:
		# the torch at the seam: a blue-white point spraying sparks
		var seam := A.lerp(pp, 0.5) + Vector2(0, -t * 0.05)
		var fl := 0.75 + 0.25 * sin(ms * 0.11)
		D.glow(cv, seam, t * 0.2 * fl, D.ca(Color("bfe8ff"), 0.9))
		cv.draw_circle(seam, t * 0.06, Color.WHITE)
		for i in 7:
			var u := fposmod(ms / 230.0 + D.h01(i * 3 + 1), 1.0)
			var ang := -PI * 0.5 + (D.h01(i * 7 + 2) - 0.5) * 2.6
			var v := _polar(ang, t * 0.55 * u) + Vector2(0, t * 0.7 * u * u)
			D.line(cv, seam + v * 0.8, seam + v, D.ca(pal["b"].lerp(pal["a"], u), 1.0 - u), t * 0.045)
		return
	var s := clampf((ms - merge) / maxf(1.0, float(cl["dur"]) - merge), 0.0, 1.0)
	var f := 1.0 - s
	D.glow(cv, A, t * (0.65 - 0.25 * s), D.ca(Color("fff6cf"), 0.9 * f))
	D.ring(cv, A, t * (0.3 + 0.8 * D.ease_out(s)), D.ca(pal["a"], f), t * 0.1 * f)
	_sparks(cv, A, Vector2(0, -1), PI, 12, t * 1.1, s, t, 91, pal["b"], pal["a"], t * 0.05)


## A stand-in body: the welder as it looked before it became a hulk.
static func _p_body(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var ms := k * float(cl["dur"])
	var r := D.tile_rect(V, cl["at"])
	var buzz := D.win(ms, float(cl.get("buzz", 0)), float(cl["dur"]))
	var toward: Vector2 = cl.get("toward", Vector2.ZERO)
	var off := Vector2(sin(ms * 0.11) * t * 0.03 * buzz, 0) + toward * t * 0.1 * D.ease_in(buzz)
	cv.draw_set_transform(Vector2(r.get_center().x, r.position.y + t * 0.86) + off, 0.0, Vector2(1.0, 0.42))
	cv.draw_circle(Vector2.ZERO, t * 0.36, Color(0, 0, 0, 0.32))
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var tx = Art.tex(String(cl.get("sprite", "")), int(t))
	if tx != null:
		cv.draw_texture(tx, r.position + off)
		var hot := D.win(buzz, 0.7, 1.0)
		if hot > 0.02:
			cv.draw_texture(tx, r.position + off, Color(1.0 + 3.0 * hot, 1.0 + 2.0 * hot, 1.0 + hot, hot * 0.85))


static func _p_strain(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var ms := k * float(cl["dur"])
	var c := D.px(V, cl["at"])
	var status := String(cl.get("status", ""))
	var col := L.status_col(status)
	var d: Vector2 = cl.get("dir", Vector2(1, 0))
	var f := D.tail(k, 0.6)
	# it throws itself toward what it meant to do: chevrons strain that way
	for j in 2:
		var u := fposmod(ms / 260.0 + float(j) * 0.5, 1.0)
		var q := c + d * t * (0.5 + 0.25 * u)
		var s := Vector2(-d.y, d.x)
		D.line(cv, q - d * t * 0.12 + s * t * 0.13, q, D.ca(Color("e6edf2"), (1.0 - u) * f), t * 0.05)
		D.line(cv, q - d * t * 0.12 - s * t * 0.13, q, D.ca(Color("e6edf2"), (1.0 - u) * f), t * 0.05)
	# steam vents from both flanks
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		var u := fposmod(ms / 300.0 + float(i) * 0.27, 1.0)
		cv.draw_circle(c + Vector2(side * t * (0.4 + 0.25 * u), -t * (0.05 + 0.35 * u)), t * (0.05 + 0.08 * u),
			D.ca(Color("dde2e4"), 0.65 * (1.0 - u) * f))
	match status:
		"stun":
			# crackling across the head
			for i in 3:
				var ang := -PI * 0.5 + (float(i) - 1.0) * 0.9 + sin(ms * 0.03 + float(i)) * 0.2
				var p0 := c + Vector2(0, -t * 0.2) + _polar(ang, t * 0.3)
				var p1 := p0 + _polar(ang + 0.6, t * 0.14)
				var p2 := p1 + _polar(ang - 0.5, t * 0.14)
				cv.draw_polyline(PackedVector2Array([p0, p1, p2]), D.ca(col, f * (0.6 + 0.4 * sin(ms * 0.07 + float(i)))),
					maxf(1.5, t * 0.05), true)
		"root":
			# the roots bite down: a ring clenching round the feet
			var feet := c + Vector2(0, t * 0.38)
			var clench := 1.0 - 0.18 * absf(sin(ms * 0.025))
			cv.draw_set_transform(feet, 0.0, Vector2(1.0, 0.35))
			D.ring(cv, Vector2.ZERO, t * 0.42 * clench, D.ca(Color("8a6a3e"), f), t * 0.1)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			for i in 4:
				var x := (float(i) - 1.5) * t * 0.2
				D.line(cv, feet + Vector2(x * 1.3, t * 0.02), feet + Vector2(x * 0.7, -t * 0.32 * clench), D.ca(col, f), t * 0.06)
		_:
			D.ring(cv, c, t * (0.45 + 0.05 * sin(ms * 0.05)), D.ca(col, 0.9 * f), t * 0.07)


static func _p_fizzle(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var ms := k * float(cl["dur"])
	var fly := maxf(1.0, float(cl["fly"]))
	var a := D.px(V, cl["from"])
	var b := D.px(V, cl["to"])
	var intent := String(cl.get("intent", ""))
	var pal: Dictionary = {"gum": TAR, "drain": CHARGE, "drag": MAGNET}.get(intent, {"a": Color("9aa0a4"), "b": Color("e6edf2"), "c": Color("565f66")})
	if ms < fly:
		var u := D.ease_out(ms / fly)
		var q := a.lerp(b, u)
		if intent == "gum":
			q = D.arc_point(a, b, u, t * 0.4)
		if intent == "drag" or intent == "drain":
			D.line(cv, a, q, D.ca(pal["a"], 0.6), t * 0.05)
		_blob(cv, q, t * 0.14, pal, 1.0, t)
	else:
		# the smoke swallows it: grey puffs swirl in and close over it
		var s := clampf((ms - fly) / maxf(1.0, float(cl["dur"]) - fly), 0.0, 1.0)
		var f := 1.0 - s
		if s < 0.35:
			_blob(cv, b, t * 0.14 * (1.0 - s / 0.35), pal, 1.0 - s / 0.35, t)
		for i in 5:
			var ang := TAU * float(i) / 5.0 + s * 3.0
			var r := t * (0.3 - 0.15 * D.ease_out(s))
			cv.draw_circle(b + _polar(ang, r) + Vector2(0, -t * 0.25 * s), t * (0.12 + 0.08 * s), D.ca(Color("9aa0a4"), 0.85 * f))
	# a '?' pops over the machine the moment its shot is lost
	var pu := D.win(ms, fly - 40.0, fly + 120.0)
	if pu > 0.0:
		var pop := 1.0 + 0.4 * (1.0 - D.ease_out(pu))
		var bob := sin(ms * 0.012) * t * 0.04
		D.text(cv, V, a + Vector2(0, -t * 0.62 + bob), "?", D.ca(Color("f0f3f4"), D.tail(k, 0.7)), int(t * 0.5 * pop))


## Words under the tender: they pop in, hold still and fade.
static func _p_word(cv, cl: Dictionary, k: float, V: Dictionary) -> void:
	var t := D.ts(V)
	var row := float(cl.get("row", 0))
	var p := D.px(V, cl["at"]) + Vector2(0, t * (0.8 + WORD_ROW * row) - t * 0.1 * D.ease_out(k))
	var pop := 1.0 + 0.35 * (1.0 - D.ease_out(D.win(k, 0.0, 0.15)))
	var col: Color = cl.get("col", Color.WHITE)
	D.text(cv, V, p, String(cl.get("text", "")), D.ca(col, D.tail(k, 0.65)), maxi(8, int(t * 0.36 * pop)))
