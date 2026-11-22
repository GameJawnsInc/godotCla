extends RefCounted
## The shell's moment-to-moment feedback layer (fun pass): one step's events,
## turned into what the player sees and hears. Pure static functions over
## (events, pre, game, ctx):
##
##   events  what game.step() returned
##   pre     facts from BEFORE the step (main._pre_step): {pos, kinds, bloom,
##           hp, max_hp, shield, floor, total_turns}; {} on the resume path
##   game    the live game AFTER the step - read, never written: no step, no
##           clone, no rng (it reads enemies, player, greened, green_need, won,
##           map, tag_counts())
##   ctx     the RunStats StepCtx for the step (meta/run_stats.gd feed); {}
##           when there is none, and then there is no multi-kill, room clear,
##           streak, awaken banner or cleanse number - everything else works
##
## step() returns {callouts, fx, banners, log, sounds, shake, hitstop, lunge};
## main._feedback applies it. Feedback never invents an outcome: every word it
## puts on the map names something the event stream says happened. Names come
## from shell/names.gd and nowhere else.

const Content := preload("res://sim/content.gd")
const Names := preload("res://shell/names.gd")

const HITSTOP_MS := 70
const CALLOUT_CAP := 4          # regular callouts per step (big ones never count)
const CALLOUT_MS := 1100        # callout life (fx clock)
const BIG_MS := 1300
const STACK_MS := 110           # damage numbers on one tile fan out in time
const CALLOUT_STACK_MS := 160   # words on one tile fan out in time...
const CALLOUT_LIFT := 0.42      # ...and stack upward by this many tiles each
const IGNITE_BURST_CAP := 6
const CHIME_STEPS := [0, 2, 4, 7]   # semitones: the rising combo chain (max 4 notes)
const CHIME_FIRST_MS := 120
const CHIME_GAP_MS := 90
const ROOM_CLEAR_SEMIS := 12        # one extra chime note an octave up

const GOLD := Color("e8c840")
const CREAM := Color("e6edd8")
const RED := Color("e04b3a")
const DIM := Color("97a29a")
const GREEN := Color("8fdc6a")
const CYAN := Color("7fe3f0")
const BLOCK := Color("7fb6d9")
const FIRE := Color("ff9a3c")
const CLEAR := Color("b8e07a")
const BOSS := Color("ff7a5a")
const VIOLET := Color("d9b8f0")
const IGNITE_COL := Color("ff8a2a")

## one banner queue (main._push_banner); a higher number shows first
const BANNER_PRIO := {"boss": 90, "danger": 85, "resonance": 80, "restored": 60, "stairs": 50, "career": 10}

const PER_WORDS := {   # Content per.count -> [callout word, log phrase]
	"growth_adjacent_target": ["GROWTH", "growth beside the target"],
	"fire_within_self": ["FIRE", "fire near you"],
	"oil_in_line": ["OIL", "oil in the line"],
	"enemies_adjacent_target": ["CROWD", "enemies beside the target"],
}
const TARGET_ON_WORDS := {   # bonus.if[0].target_on[0] -> [word, phrase]
	"fire": ["BURNING", "target burning"], "oil": ["OILED", "target in oil"],
	"growth": ["TANGLED", "target in growth"], "smoke": ["SMOKED", "target in smoke"],
}
const UNIT := {"dmg": "dmg", "push": "push", "collision_dmg": "crash", "radius": "reach",
	"dist": "reach", "turns": "turns", "ttl": "burn"}
const STATUS_WORDS := {  # status -> [callout, verb, past, colour]
	"root": ["ROOTED", "roots", "rooted", Color("b5d67a")],
	"stun": ["STUNNED", "stuns", "stunned", Color("f0e08a")],
	"spore": ["SPORED", "spores", "spored", Color("c9a0dc")],
}
const HOOK_LANDING_OPS := ["damage_at", "status_at", "terrain_at"]
## mirrors sim/game.gd _damage_enemy + _compute_boss_intent: change both together
const BOSS_PHASE_LINES := {
	"furnace_core": {2: ["THE FURNACE STOKES", "a coal golem joins · it now ignites all oil"],
		3: ["THE CORE CLOGS ITS VENTS", "goo shields it: cleanse or grow beside it"]},
	"overseer": {2: ["THE OVERSEER QUICKENS", "advances 3 · quakes all around it up close"],
		3: ["THE OVERSEER CLOGS ITS VENTS", "goo shields it: cleanse or grow beside it"]},
	"the_dredge": {2: ["THE DREDGE HUNGERS", "drags you twice · dredges growth within 3"],
		3: ["THE DREDGE CLOGS ITS VENTS", "goo shields it: cleanse or grow beside it"]},
}
const SOUND_OF := {   # event type -> sound id ("damage"/"move" only when who == "player")
	"player_death": "death", "boss_phase": "boss", "damage": "hurt", "death": "kill",
	"strike": "hit", "ability": "cast", "cleanse": "sparkle", "heal": "heal",
	"buy": "coin", "item_pickup": "coin", "bounty": "coin", "tithe": "coin",
	"draft_pick": "card", "draft_upgrade": "card", "room_bloom": "heal",
	"floor_restored": "heal", "stairs_awaken": "sparkle", "verdant": "sparkle",
	"seal_burst": "vent", "reinforcement": "vent", "summon": "vent", "item_use": "cast",
	"assimilate": "drag", "drag": "drag", "upcycle": "sparkle", "upcycle_ability": "sparkle",
	"smog_dim": "dim", "choke": "dim", "stoke": "dim", "descend": "descend",
	"floor": "arrive", "move": "step", "ignite": "whoomph", "ignite_all": "whoomph",
	"core_shielded": "shielded", "shield_absorb": "shielded",
}
const SOUND_PRIO := {"win": 100, "death": 100, "boss": 90, "warn": 87, "hurt": 85, "multikill": 80,
	"shielded": 75, "kill": 70, "descend": 65, "card": 60, "combo": 60, "whoomph": 55,
	"vent": 50, "dim": 48, "drag": 46, "sparkle": 44, "heal": 42, "coin": 40, "cast": 30,
	"hit": 28, "arrive": 26, "step": 5}            # unknown id: 10
const LOG_COL := {"hurt": RED, "reward": GOLD, "heal": GREEN, "combo": VIOLET,
	"boss": BOSS, "info": Color("d8e0d4")}
## event type -> log category, for the types whose line is unchanged
const LOG_CAT := {"choke": "hurt", "room_bloom": "reward", "item_pickup": "reward",
	"buy": "reward", "stairs_awaken": "reward", "floor_restored": "reward", "heal": "heal",
	"vents_clogged": "boss", "dredge": "boss", "ignite_all": "boss", "flood": "boss",
	"screened": "combo"}
## what a screened intent is called in the log (the raw type is the fallback)
const SCREEN_WORDS := {"gum": "tar", "drain": "drain", "drag": "grapple"}


# --- the whole step -----------------------------------------------------------

static func step(evs: Array, pre: Dictionary, game, ctx: Dictionary, now: int, extra_sounds: Array = []) -> Dictionary:
	var calls := callouts(evs, pre, game, ctx)
	var hs := hitstop(evs)
	return {
		"callouts": calls,
		"fx": fx(evs, pre, game, ctx, now, calls, hs),
		"banners": banners(evs, pre, game, ctx),
		"log": log_entries(evs, pre, game, ctx),
		"sounds": sounds(evs, game, ctx, calls, hs, extra_sounds),
		"shake": shake(evs, ctx),
		"hitstop": hs,
		"lunge": lunge(evs, pre, game),
	}


# --- lookups ------------------------------------------------------------------

## The kind of enemy `id`: the live one, else the pre-step record, else "".
static func kind_of(id, pre: Dictionary, game) -> String:
	if not (id is int):
		return ""  # an enemy id is an int; an ability event's id is a String
	for e in game.enemies:
		if _same(e["id"], id):
			return String(e["kind"])
	return String(pre.get("kinds", {}).get(id, ""))


## Variant-safe id equality: events carry int enemy ids and String ability
## ids under the same key, and comparing the two kinds throws.
static func _same(a, b) -> bool:
	return typeof(a) == typeof(b) and a == b


## Best-known tile for an event's subject: the player, a live enemy, or the
## pre-step position of something that just died; (-9, -9) when unknown.
static func ev_pos(ev: Dictionary, pre: Dictionary, game) -> Vector2:
	if String(ev.get("who", "")) == "player":
		return Vector2(game.player["pos"])
	var id = ev.get("id", null)
	if id is int:
		for e in game.enemies:
			if _same(e["id"], id):
				return Vector2(e["pos"])
		var pp: Dictionary = pre.get("pos", {})
		if pp.has(id):
			return Vector2(pp[id])
	return Vector2(-9, -9)


static func _ppos(game) -> Vector2:
	return Vector2(game.player["pos"])


## A sentence-starting enemy name: "Drill Bot", but "The Furnace Core".
static func _subj(kind: String) -> String:
	if Content.ENEMIES.get(kind, {}).get("traits", []).has("boss"):
		return Names.boss_name(kind)
	return Names.ename(kind)


static func _is_boss(kind: String) -> bool:
	return Content.ENEMIES.get(kind, {}).get("traits", []).has("boss")


static func _source_row(sid: String) -> Dictionary:
	if Content.RESONANCES.has(sid):
		return Content.RESONANCES[sid]
	if Content.GRAFTS.has(sid):
		return Content.GRAFTS[sid]
	return Content.ABILITIES.get(sid, {})


static func _per_of(aid: String) -> Dictionary:
	for eff in Content.ABILITIES.get(aid, {}).get("effects", []):
		if eff.has("per"):
			return eff["per"]
	return {}


static func _bonus_of(aid: String) -> Dictionary:
	for eff in Content.ABILITIES.get(aid, {}).get("effects", []):
		if eff.has("bonus"):
			return eff["bonus"]
	return {}


static func _per_key(per: Dictionary) -> String:
	var add: Dictionary = per.get("add", {})
	return String(add.keys()[0]) if not add.is_empty() else "dmg"


static func _bonus_words(aid: String) -> Array:
	var b := _bonus_of(aid)
	var conds: Array = b.get("if", [])
	if not conds.is_empty():
		var on: Array = Dictionary(conds[0]).get("target_on", [])
		if not on.is_empty() and TARGET_ON_WORDS.has(String(on[0])):
			return TARGET_ON_WORDS[String(on[0])]
	return ["BONUS", "bonus"]


## The charge a standing-on-growth cast saved, mirroring Game.ability_cost:
## a cost >= 2 drops by the surge's cost delta, never below 1.
static func _verdant_saving(aid: String) -> int:
	var adef: Dictionary = Content.ABILITIES.get(aid, {})
	var base := int(adef.get("cost", 1))
	var delta := int(Dictionary(adef.get("surge", Content.SURGE_DEFAULT)).get("cost", 0))
	return base - maxi(1, base + delta) if base >= 2 else 0


## The held graft's oil_cast_discount (Oil Tithe), and its name.
static func _tithe(game) -> Array:
	for gid in game.player.get("grafts", []):
		var row: Dictionary = Content.GRAFTS.get(String(gid), {})
		if Dictionary(row.get("mod", {})).has("oil_cast_discount"):
			return [String(row["name"]), int(row["mod"]["oil_cast_discount"])]
	return ["Tithe", 1]


static func _first_of(evs: Array, t: String) -> int:
	for i in evs.size():
		if String(evs[i].get("t", "")) == t:
			return i
	return -1


static func _multi(ctx: Dictionary) -> int:
	if int(ctx.get("step_kills", 0)) > 0 and int(ctx.get("turn_kills", 0)) >= 2:
		return int(ctx["turn_kills"])
	return 0


static func _streak(ctx: Dictionary) -> int:
	if int(ctx.get("step_kills", 0)) > 0 and int(ctx.get("turn_kills_prev", 0)) == 0 \
			and int(ctx.get("kill_streak", 0)) >= 3:
		return int(ctx["kill_streak"])
	return 0


# --- who is responsible for each status ---------------------------------------

## The event index a hook at `i` LANDED on, or -1. The dispatcher runs a row's
## effects right after its `hook` event, so a landed effect's first event is
## always i+1; an immune / resisted / shielded target, an empty tile or a body
## that already left is no landing, and gets no callout and no line.
static func _hook_landing(evs: Array, i: int, game) -> int:
	if i + 1 >= evs.size():
		return -1
	var h: Dictionary = evs[i]
	var nx: Dictionary = evs[i + 1]
	var sid := String(h.get("id", ""))
	for row in _source_row(sid).get("hooks", []):
		if String(row.get("on", "")) != String(h.get("on", "")):
			continue
		for eff in row.get("effects", []):
			match String(eff.get("op", "")):
				"damage_at":
					if String(nx.get("t", "")) == "damage" and String(nx.get("src", "")) == sid:
						return i + 1
				"status_at":
					if String(nx.get("t", "")) == "status" and String(nx.get("status", "")) == String(eff.get("status", "")):
						for e in game.enemies:
							if _same(e["id"], nx.get("id")) and h.get("tile") != null and e["pos"] != h["tile"]:
								return -1
						return i + 1
				"terrain_at":
					if String(nx.get("t", "")) == "terrain" and nx.get("tile") == h.get("tile"):
						return i + 1
	return -1


## Claims over one step: a status index -> "hook" | "then", and a hook /
## then-rider index -> the index it claimed (an int; a then-rider maps to its
## LAST claimed status). A then-rider claims the run of unclaimed `status`
## events right before it (_apply_effect emits the rider after its sub-effect),
## so Undertow + Pinning Jet (`hook | status | status | rider then`) splits as
## the hook taking the first status and the rider the second.
static func claims(evs: Array, game) -> Dictionary:
	var c := {}
	for i in evs.size():
		var t := String(evs[i].get("t", ""))
		if t == "hook":
			var j := _hook_landing(evs, i, game)
			if j >= 0:
				c[j] = "hook"
				c[i] = j
		elif t == "rider" and String(evs[i].get("kind", "")) == "then":
			var k := i - 1
			while k >= 0 and String(evs[k].get("t", "")) == "status" and not c.has(k):
				c[k] = "then"
				if not c.has(i):
					c[i] = k
				k -= 1
	return c


## The statuses a then-rider at `i` claimed, in event order.
static func _then_claimed(evs: Array, i: int, cl: Dictionary) -> Array:
	var out: Array = []
	if not (cl.get(i) is int):
		return out
	var k := i - 1
	while k >= 0 and String(cl.get(k, "")) == "then" and String(evs[k].get("t", "")) == "status":
		out.push_front(k)
		k -= 1
	return out


static func _next_damage(evs: Array, i: int, aid: String) -> int:
	for j in range(i + 1, mini(evs.size(), i + 4)):
		var ev: Dictionary = evs[j]
		if String(ev.get("t", "")) == "damage" and String(ev.get("who", "")) != "player":
			var s := String(ev.get("src", ""))
			if s == aid or s == "collision:" + aid:
				return j
	return -1


# --- callouts -----------------------------------------------------------------

static func _call(text: String, pos: Vector2, col: Color, prio: int, combo := false, big := false, src := "") -> Dictionary:
	return {"text": text, "pos": pos, "col": col, "prio": prio, "combo": combo, "big": big, "src": src}


## The step's words over the map, kept and in display order (prio desc,
## stable): every big one plus the first CALLOUT_CAP regular ones, one per
## text and tile. A dropped callout still gets its log line.
static func callouts(evs: Array, pre: Dictionary, game, ctx: Dictionary) -> Array:
	var cl := claims(evs, game)
	var out: Array = []
	var has_surge := _first_of(evs, "surge") >= 0
	var vi := _first_of(evs, "verdant")
	var verdant_tile = evs[vi].get("tile") if vi >= 0 else null
	var seen_ignite := false
	var last_kill := _ppos(game)
	for i in evs.size():
		var ev: Dictionary = evs[i]
		var t := String(ev.get("t", ""))
		match t:
			"hook":
				if cl.get(i) is int:
					var sid := String(ev.get("id", ""))
					var hp: Vector2 = Vector2(ev["tile"]) if ev.get("tile") != null else ev_pos(evs[cl[i]], pre, game)
					out.append(_call(Names.source_name(sid).to_upper(), hp, GOLD,
						90 if Content.RESONANCES.has(sid) else 80, true, false, sid))
			"rider":
				var aid := String(ev.get("id", ""))
				match String(ev.get("kind", "")):
					"per":
						var per := _per_of(aid)
						var w: Array = PER_WORDS.get(String(per.get("count", "")), [String(per.get("count", "")).to_upper(), ""])
						var key := _per_key(per)
						var j := _next_damage(evs, i, aid)
						var p := ev_pos(evs[j], pre, game) if j >= 0 else _ppos(game)
						out.append(_call("%s +%d %s" % [w[0], int(ev.get("amt", 0)), UNIT.get(key, key)], p, GOLD, 70, true, false, aid))
					"bonus":
						var j2 := _next_damage(evs, i, aid)
						var p2 := ev_pos(evs[j2], pre, game) if j2 >= 0 else _ppos(game)
						out.append(_call("%s +%d dmg" % [_bonus_words(aid)[0], int(ev.get("amt", 0))], p2, GOLD, 70, true, false, aid))
					"then":
						var ks := _then_claimed(evs, i, cl)
						if ks.is_empty():
							out.append(_call("COMBO", _ppos(game), GOLD, 70, true, false, aid))
						for k in ks:
							var st: Dictionary = evs[k]
							var sw: Array = STATUS_WORDS.get(String(st.get("status", "")), [String(st.get("status", "")).to_upper()])
							out.append(_call(String(sw[0]) + "!", ev_pos(st, pre, game), GOLD, 70, true, false, aid))
			"surge":
				var adef: Dictionary = Content.ABILITIES.get(String(ev.get("id", "")), {})
				var keys: Array = ev.get("keys", [])
				if not keys.is_empty():
					var k0 := String(keys[0])
					var v := int(Dictionary(adef.get("surge", {})).get(k0, 1))
					var sp: Vector2 = Vector2(verdant_tile) if verdant_tile != null else _ppos(game)
					out.append(_call("SURGE +%d %s" % [v, UNIT.get(k0, k0)], sp, GOLD, 65, true, false, String(ev.get("id", ""))))
			"verdant":
				if not has_surge and ev.get("tile") != null:
					out.append(_call("VERDANT", Vector2(ev["tile"]), GREEN, 30))
			"status":
				if not cl.has(i):
					var sw2: Array = STATUS_WORDS.get(String(ev.get("status", "")), [String(ev.get("status", "")).to_upper(), "", "", DIM])
					out.append(_call(String(sw2[0]), ev_pos(ev, pre, game), sw2[3], 40))
			"immune", "resisted":
				out.append(_call(t.to_upper(), ev_pos(ev, pre, game), DIM, 20))
			"shield_absorb":
				out.append(_call("BLOCKED %d" % int(ev.get("amt", 0)), _ppos(game), BLOCK, 45))
			"ignite":
				if not seen_ignite and ev.get("tile") != null:
					seen_ignite = true
					out.append(_call("IGNITE", Vector2(ev["tile"]), FIRE, 35))
			"tithe":
				out.append(_call("TITHE -%d" % int(_tithe(game)[1]), _ppos(game), GOLD, 30))
			"bounty":
				out.append(_call("BOUNTY +%d" % Content.ELITE_BOUNTY, last_kill, GOLD, 50))
			"core_shielded":
				out.append(_call("SHIELDED", ev_pos(ev, pre, game), CYAN, 88))
			"damage":
				if String(ev.get("src", "")).begins_with("collision:"):
					out.append(_call("COLLISION", ev_pos(ev, pre, game), GOLD, 60, true, false, String(ev["src"])))
			"death":
				var dp := ev_pos(ev, pre, game)
				if dp.x > -0.5:
					last_kill = dp
	var mk := _multi(ctx)
	if mk > 0:
		var words := {2: "DOUBLE KILL", 3: "TRIPLE KILL"}
		out.append(_call(words.get(mk, "%d KILLS" % mk), last_kill, GOLD, 100, false, true))
	if bool(ctx.get("room_cleared", false)):
		out.append(_call("ROOM CLEAR", _ppos(game), CLEAR, 98, false, true))
	var sk := _streak(ctx)
	if sk > 0:
		out.append(_call("STREAK %d" % sk, _ppos(game), FIRE, 55))
	# dedupe, priority sort (stable), cap the regular ones
	var seen := {}
	var uniq: Array = []
	for c in out:
		if Vector2(c["pos"]).x < -0.5:
			continue  # nowhere to draw it; its log line still prints
		var key2 := String(c["text"]) + "@" + str(c["pos"])
		if not seen.has(key2):
			seen[key2] = true
			uniq.append(c)
	var idx: Array = range(uniq.size())
	idx.sort_custom(func(a, b):
		var pa := int(uniq[a]["prio"])
		var pb := int(uniq[b]["prio"])
		return pa > pb or (pa == pb and a < b))
	var kept: Array = []
	var regular := 0
	for ii in idx:
		var c2: Dictionary = uniq[ii]
		if not bool(c2["big"]):
			if regular >= CALLOUT_CAP:
				continue
			regular += 1
		kept.append(c2)
	return kept


# --- map effects --------------------------------------------------------------

## Is the damage event at `i` the blow that killed its target (a later death of
## the same id with no other damage to it in between)?
static func _killing_blow(evs: Array, i: int) -> bool:
	var id = evs[i].get("id", null)
	if not (id is int):
		return false
	for j in range(i + 1, evs.size()):
		var t := String(evs[j].get("t", ""))
		if not _same(evs[j].get("id", null), id):
			continue
		if t == "death":
			return true
		if t == "damage":
			return false
	return false


static func fx(evs: Array, pre: Dictionary, game, ctx: Dictionary, now: int, calls: Array, _hitstop: bool) -> Array:
	var out: Array = []
	var stack := {}  # tile -> count, so numbers landing together fan out in time
	var ignites := 0
	for i in evs.size():
		var ev: Dictionary = evs[i]
		match String(ev.get("t", "")):
			"damage":
				var p := ev_pos(ev, pre, game)
				if p.x < -0.5:
					continue
				var k := str(p)
				stack[k] = int(stack.get(k, -1)) + 1
				var amt := int(ev.get("amt", 0))
				var mine := String(ev.get("who", "")) == "player"
				var f := {"kind": "float", "pos": p, "text": "-%d" % amt, "t0": now + int(stack[k]) * STACK_MS}
				if not mine and _killing_blow(evs, i):
					f.merge({"col": GOLD, "scale": 1.5, "bold": true})
				else:
					f.merge({"col": RED if mine else CREAM, "scale": 1.0 + 0.1 * clampf(float(amt - 1), 0.0, 5.0),
						"bold": amt >= (3 if mine else 4)})
				out.append(f)
				out.append({"kind": "flash", "pos": p, "col": Color(1, 1, 1), "t0": now})
			"heal":
				out.append({"kind": "float", "pos": _ppos(game), "text": "+%d" % int(ev.get("amt", 0)), "col": GREEN, "t0": now})
			"shield":
				out.append({"kind": "float", "pos": _ppos(game), "text": "shield", "col": BLOCK, "t0": now})
			"cleanse":
				var cp := Vector2(ev["tile"])
				out.append({"kind": "burst", "pos": cp, "col": GOLD, "t0": now})
				# the event's bloom is the running TOTAL: the gain is the fold's
				if ctx.has("cleanse_gain"):
					var g := int(ctx["cleanse_gain"])
					out.append({"kind": "float", "pos": cp, "text": "+%d" % g, "col": GOLD if g > 0 else DIM, "t0": now})
			"death":
				var dp := ev_pos(ev, pre, game)
				if dp.x > -0.5:
					out.append({"kind": "puff", "pos": dp, "col": Color(0.62, 0.64, 0.66), "t0": now})
					var sk := kind_of(ev.get("id"), pre, game)
					if sk == "":
						sk = String(ev.get("who", ""))
					out.append({"kind": "ghost", "pos": dp, "sprite": sk, "t0": now, "dur": 60})
			"room_bloom":
				var bp := _ppos(game)
				out.append({"kind": "burst", "pos": bp, "col": Color(0.91, 0.70, 0.82), "t0": now})
				out.append({"kind": "float", "pos": bp, "text": "BLOOM +%d" % int(ev.get("bonus", 2)), "col": GOLD, "t0": now + 120})
			"stairs_awaken":
				if ev.get("tile") != null:
					out.append({"kind": "burst", "pos": Vector2(ev["tile"]), "col": GOLD, "t0": now})
			"floor_restored":
				out.append({"kind": "burst", "pos": _ppos(game), "col": Color(0.6, 0.9, 0.5), "t0": now})
			"verdant":
				if ev.get("tile") != null:
					out.append({"kind": "burst", "pos": Vector2(ev["tile"]), "col": Color(0.55, 0.9, 0.45), "t0": now})
			"ignite":
				if ignites < IGNITE_BURST_CAP and ev.get("tile") != null:
					ignites += 1
					out.append({"kind": "burst", "pos": Vector2(ev["tile"]), "col": IGNITE_COL, "t0": now})
			"core_shielded":
				var bpos := ev_pos(ev, pre, game)
				if bpos.x > -0.5:
					out.append({"kind": "ring", "pos": bpos, "col": CYAN, "t0": now, "dur": 650})
	var per_tile := {}
	for c in calls:
		var big := bool(c["big"])
		var f2 := {"kind": "callout", "pos": c["pos"], "text": c["text"], "col": c["col"], "bold": true,
			"dur": BIG_MS if big else CALLOUT_MS, "scale": 1.35 if big else 1.0}
		if big:
			var clear := String(c["text"]) == "ROOM CLEAR"
			f2["t0"] = now + (280 if clear else 160)
			f2["lift"] = 0.5 if clear else 0.0
		else:
			var key := str(c["pos"])
			var n := int(per_tile.get(key, 0))
			per_tile[key] = n + 1
			f2["t0"] = now + CALLOUT_STACK_MS * n
			f2["lift"] = CALLOUT_LIFT * n
		out.append(f2)
	return out


## Screen shake: the strongest of a hit on the tender, a board-wide event and
## the step's kills (the fold's count, else the death events).
static func shake(evs: Array, ctx: Dictionary) -> float:
	var mag := 0.0
	var deaths := 0
	for ev in evs:
		match String(ev.get("t", "")):
			"damage":
				if String(ev.get("who", "")) == "player":
					mag = maxf(mag, 2.0 + minf(float(int(ev.get("amt", 0))) * 1.2, 6.0))
			"boss_phase", "ignite_all", "flood", "smoke_burst":
				mag = maxf(mag, 9.0)
			"death":
				deaths += 1
	var kills := int(ctx["step_kills"]) if ctx.has("step_kills") else deaths
	if kills > 0:
		mag = maxf(mag, minf(2.5 + 1.5 * float(kills - 1), 6.0))
	return mag


## A kill, or any hit of 4 or more, freezes the fx clock for HITSTOP_MS.
static func hitstop(evs: Array) -> bool:
	for ev in evs:
		var t := String(ev.get("t", ""))
		if t == "death" or (t == "damage" and int(ev.get("amt", 0)) >= 4):
			return true
	return false


## The tender leans into its first strike: a unit vector toward the struck
## enemy, or ZERO.
static func lunge(evs: Array, pre: Dictionary, game) -> Vector2:
	for ev in evs:
		if String(ev.get("t", "")) == "strike":
			var tp := ev_pos(ev, pre, game)
			if tp.x < -0.5:
				return Vector2.ZERO
			var d := tp - _ppos(game)
			return d.normalized() if d.length() > 0.0 else Vector2.ZERO
	return Vector2.ZERO


# --- banners ------------------------------------------------------------------

static func banners(evs: Array, _pre: Dictionary, game, ctx: Dictionary) -> Array:
	var out: Array = []
	var phase := 0
	for ev in evs:
		match String(ev.get("t", "")):
			"stairs_awaken":
				out.append({"lines": ["THE STAIRS AWAKEN"], "col": GOLD, "prio": BANNER_PRIO["stairs"]})
			"floor_restored":
				out.append({"lines": ["FLOOR RESTORED", "the skies clear · +%d bloom" % int(ev.get("bonus", 5))],
					"col": GOLD, "prio": BANNER_PRIO["restored"]})
			"boss_phase":
				phase = maxi(phase, int(ev.get("phase", 0)))
	if phase > 0:
		var boss := ""
		for e in game.enemies:
			if _is_boss(String(e["kind"])):
				boss = String(e["kind"])
				break
		if boss != "":  # no live boss: it died, and the win says the rest
			var lines: Array = BOSS_PHASE_LINES.get(boss, {}).get(phase, ["BOSS PHASE %d" % phase])
			out.append({"lines": lines.duplicate(), "col": BOSS, "prio": BANNER_PRIO["boss"]})
	var counts: Dictionary = game.tag_counts() if not Array(ctx.get("res_new", [])).is_empty() else {}
	for rid in ctx.get("res_new", []):
		var row: Dictionary = Content.RESONANCES.get(String(rid), {})
		if row.is_empty():
			continue
		var tag := String(row["tag"])
		out.append({"lines": ["%s AWAKENS" % String(row["name"]).to_upper(),
			"%s %d/%d - %s" % [tag, int(counts.get(tag, 0)), int(row["need"]), String(row["desc"]).split(" · ")[0]]],
			"col": GOLD, "prio": BANNER_PRIO["resonance"]})
	var idx: Array = range(out.size())
	idx.sort_custom(func(a, b):
		var pa := int(out[a]["prio"])
		var pb := int(out[b]["prio"])
		return pa > pb or (pa == pb and a < b))
	var sorted: Array = []
	for ii in idx:
		sorted.append(out[ii])
	return sorted


# --- the log ------------------------------------------------------------------

## Purchase ids in words ("bloom_surge" -> "Bloom Surge").
static func shop_name(item: String, id: String) -> String:
	match item:
		"heal":
			return "a heal"
		"graft":
			return String(Content.GRAFTS.get(id, {}).get("name", id.replace("_", " ")))
		"ability":
			return Names.aname(id)
		"item":
			return String(Content.ITEMS.get(id, {}).get("name", id.replace("_", " ")))
	return id.replace("_", " ") if id != "" else item


static func _item_name(id: String) -> String:
	return String(Content.ITEMS.get(id, {}).get("name", id.replace("_", " ")))


## One event's line and category, ignoring claims and aggregation (those are
## log_entries' job). "" = no line.
static func _line(ev: Dictionary, pre: Dictionary, game, ctx: Dictionary, evs: Array, i: int) -> Array:
	var t := String(ev.get("t", ""))
	var cat := String(LOG_CAT.get(t, "info"))
	var s := ""
	match t:
		"damage":
			var src := String(ev.get("src", ""))
			if String(ev.get("who", "")) == "player":
				return ["You take %d dmg (%s)" % [int(ev.get("amt", 0)), Names.src_name(src if src != "" else "?")], "hurt"]
			s = "%s takes %d" % [_subj(String(ev.get("who", ""))), int(ev.get("amt", 0))]
			if src.begins_with("collision:"):
				return [s + " (collision)", "combo"]
			if src != "" and src != "strike":
				s += " (%s)" % Names.src_name(src)
		"death":
			s = "%s destroyed" % _subj(String(ev.get("who", "")))
		"player_death":
			return ["You die (%s)" % Names.src_name(String(ev.get("cause", "?"))), "hurt"]
		"heal":
			s = "Growth heals you +%d" % int(ev.get("amt", 0))
		"cleanse":
			var green := " · green %d/%d" % [int(game.greened), int(game.green_need)] if int(game.green_need) > 0 else ""
			if not ctx.has("cleanse_gain"):
				s = "Cleansed" + green
			elif int(ctx["cleanse_gain"]) > 0:
				s = "Cleansed +%d bloom%s" % [int(ctx["cleanse_gain"]), green]
			else:
				s = "Cleansed - enemy-made %s pays no bloom%s" % [String(ev.get("kind", "oil")).replace("_", " "), green]
			cat = "reward"
		"room_bloom":
			s = "Room BLOOMS - +%d bloom and a supply pod" % int(ev.get("bonus", 2))
		"item_pickup":
			s = "Picked up %s" % _item_name(String(ev.get("id", "")))
		"item_use":
			var irow: Dictionary = Content.ITEMS.get(String(ev.get("id", "")), {})
			s = "%s used - %s" % [_item_name(String(ev.get("id", ""))), String(irow.get("desc", ""))] if irow.has("desc") \
				else "%s used" % _item_name(String(ev.get("id", "")))
		"satchel_full":
			s = "Satchel full (2 slots)"
		"stairs_dormant":
			s = "Stairs dormant - green the floor (%d/%d)" % [int(ev.get("have", 0)), int(ev.get("need", 0))]
		"stairs_awaken":
			s = "The floor greens - THE STAIRS AWAKEN"
		"quota_reclamp":
			s = "Corruption burned away - gate now needs %d" % int(ev.get("need", 0))
		"seal_burst":
			s = "Overgrown vent chokes - spawn absorbed"
		"floor_restored":
			s = "FLOOR RESTORED - skies clear (+%d bloom)" % int(ev.get("bonus", 5))
		"assimilate":
			s = "The machines WELD into a hulk"
		"upcycle":
			s = "Upcycled: %s" % _item_name(String(ev.get("id", "")))
		"upcycle_ability":
			s = "Forged %s" % Names.aname(ev.get("id", ""))
		"upcycle_scrap":
			s = "Scrapped %s for parts" % Names.aname(ev.get("id", ""))
		"choke":
			s = "The smog chokes you"
		"smog_dim":
			s = "Skies dim - charge regen drops"
		"gummed":
			return ["Tar gums up %s" % Names.aname(ev.get("id", "")), "hurt"]
		"screened":
			var it := String(ev.get("intent", ""))
			s = "%s's %s is lost in the smoke" % [_subj(kind_of(ev.get("id"), pre, game)), String(SCREEN_WORDS.get(it, it))]
		"drain":
			return ["%s drains %d banked charge" % [_subj(kind_of(ev.get("id"), pre, game)), int(ev.get("amt", 0))], "hurt"]
		"drag":
			return ["%s drags you" % _subj(kind_of(ev.get("id"), pre, game)), "hurt"]
		"stoke":
			s = "Smokestack thickens the smog"
		"boss_phase":
			var ph := int(ev.get("phase", 0))
			var bk := ""
			for e in game.enemies:
				if _is_boss(String(e["kind"])):
					bk = String(e["kind"])
					break
			var pl: Array = BOSS_PHASE_LINES.get(bk, {}).get(ph, [])
			s = "%s: %s" % [Names.boss_name(bk), String(pl[1])] if pl.size() > 1 else "BOSS PHASE %d" % ph
			cat = "boss"
		"vents_clogged":
			s = "The boss clogs the vents with goo"
		"core_shielded":
			return ["%s is shielded: cleanse or grow beside it" % _subj(kind_of(ev.get("id"), pre, game)), "boss"]
		"dredge":
			s = "The Dredge eats %d growth and heals" % int(ev.get("tiles", 0))
		"summon":
			s = "%s summons %s" % [_subj(kind_of(ev.get("id"), pre, game)), Names.a_name(kind_of(ev.get("child"), pre, game))]
		"split":
			s = "%s splits" % _subj(kind_of(ev.get("id"), pre, game))
		"ooze":
			s = "%s oozes oil" % _subj(kind_of(ev.get("id"), pre, game))
		"ignite_all":
			s = "ALL OIL IGNITES"
		"flood":
			s = "Oil floods the arena"
		"smoke_burst":
			s = "The golem bursts into smoke"
		"buy":
			var what := shop_name(String(ev.get("item", "")), String(ev.get("id", "")))
			if String(ev.get("discarded", "")) != "":
				s = "Bought %s (discarded %s)" % [what, shop_name("graft", String(ev["discarded"]))]
			else:
				s = "Bought %s" % what
		"reroll":
			s = "Rerolled (-%d bloom)" % int(ev.get("cost", 0))
		"draft_upgrade":
			s = "Upgraded to %s" % Names.aname(ev.get("id", ""))
		"draft_pick":
			s = "Drafted %s" % Names.aname(ev.get("id", ""))
		"draft_drop":
			s = "Dropped %s" % Names.aname(ev.get("id", ""))
		"draft_skip":
			s = "Skipped - next draft adds a focus offer"
		"shield":
			s = "Shield up (%d)" % int(ev.get("total", 0))
		"thorns":
			s = "Thorns up (%d dmg)" % int(ev.get("dmg", 0))
		"anchor":
			s = "Anchored - drags can't move you"
		"undim":
			s = "Air clears - regen recovers"
		"immune":
			s = "%s shrugs it off" % _subj(kind_of(ev.get("id"), pre, game))
		"stunned":
			s = "%s is stunned" % _subj(kind_of(ev.get("id"), pre, game))
		"staggered":
			s = "%s staggers - wind-up lost" % _subj(kind_of(ev.get("id"), pre, game))
		"rooted":
			s = "%s is rooted in place" % _subj(kind_of(ev.get("id"), pre, game))
		"resisted":
			var stn := String(ev.get("status", "root"))
			s = "%s shakes off the %s (cooldown)" % [_subj(kind_of(ev.get("id"), pre, game)), String(Names.SRC_WORDS.get(stn, stn))]
		"status":
			var nm := _subj(kind_of(ev.get("id"), pre, game))
			var st := String(ev.get("status", ""))
			var turns := int(ev.get("turns", 0))
			if st == "spore":
				s = "%s is spored (+%d)" % [nm, turns]
			else:
				var w: Array = STATUS_WORDS.get(st, ["", "", st.replace("_", " ")])
				s = "%s %s for %d turn%s" % [nm, String(w[2]), turns, "" if turns == 1 else "s"]
		"shield_absorb":
			s = "Your shield blocks %d" % int(ev.get("amt", 0))
		"bounty":
			# the event carries the running total; the bounty is the constant
			return ["Elite bounty +%d bloom" % Content.ELITE_BOUNTY, "reward"]
		"tithe":
			var tt := _tithe(game)
			return ["%s: %s costs %d less" % [String(tt[0]), Names.aname(ev.get("id", "")), int(tt[1])], "combo"]
		"descend":
			if pre.has("hp"):
				s = "You descend: +%d max HP, +%d HP" % [Content.DESCEND_MAX_HP_BONUS, int(game.player["hp"]) - int(pre["hp"])]
			else:
				s = "You descend"
			cat = "heal"
		"floor":
			s = "— %s —" % str(ev.get("name", "next floor"))
		"illegal":
			s = "Can't do that"
		"surge":
			var adef: Dictionary = Content.ABILITIES.get(String(ev.get("id", "")), {})
			var parts: Array = []
			for k in ev.get("keys", []):
				parts.append("+%d %s" % [int(Dictionary(adef.get("surge", {})).get(k, 1)), String(UNIT.get(k, k))])
			var d := _verdant_saving(String(ev.get("id", "")))
			return ["Verdant surge: %s %s%s" % [Names.aname(ev.get("id", "")), ", ".join(parts),
				", costs %d less" % d if d > 0 else ""], "combo"]
		"verdant":
			if _first_of(evs, "surge") >= 0:
				return ["", "info"]
			var nxt := ""
			for j in range(i + 1, evs.size()):
				if String(evs[j].get("t", "")) == "ability":
					nxt = String(evs[j].get("id", ""))
					break
			if nxt == "":
				return ["Verdant surge - the growth feeds your cast", "combo"]
			var dv := _verdant_saving(nxt)
			if dv <= 0:
				return ["Verdant: the growth feeds %s" % Names.aname(nxt), "combo"]
			return ["Verdant: %s costs %d less" % [Names.aname(nxt), dv], "combo"]
	return [s, cat]


## The step's log lines, in event order: [{text, cat}]. Landed hooks and
## then-riders name their source in place of the status line they claimed;
## ignites, ash and reinforcements fold into one line each at the first
## occurrence; multi-kill, room clear and awakenings close the step.
static func log_entries(evs: Array, pre: Dictionary, game, ctx: Dictionary) -> Array:
	var cl := claims(evs, game)
	var out: Array = []
	var agg := {}       # "ignite" / "ash" -> index in out
	var reinf := {}     # kind -> count
	for i in evs.size():
		var ev: Dictionary = evs[i]
		var t := String(ev.get("t", ""))
		match t:
			"hook":
				if cl.get(i) is int:
					var land: Dictionary = evs[cl[i]]
					var nm := Names.source_name(ev.get("id", ""))
					match String(land.get("t", "")):
						"status":
							var sw: Array = STATUS_WORDS.get(String(land.get("status", "")), ["", "affects", ""])
							out.append({"text": "%s %s %s" % [nm, sw[1], Names.the_name(kind_of(land.get("id"), pre, game))], "cat": "combo"})
						"terrain":
							out.append({"text": "%s: %s springs up%s" % [nm, String(land.get("kind", "")).replace("_", " "),
								" where it fell" if String(ev.get("on", "")) == "kill" else ""], "cat": "combo"})
					# a damage landing needs no line: the damage line ends "(Ember Sap)"
				continue
			"rider":
				var aid := String(ev.get("id", ""))
				match String(ev.get("kind", "")):
					"per":
						var per := _per_of(aid)
						var key := _per_key(per)
						out.append({"text": "%s: +%d %s (%s)" % [Names.aname(aid), int(ev.get("amt", 0)), UNIT.get(key, key),
							PER_WORDS.get(String(per.get("count", "")), ["", "a count"])[1]], "cat": "combo"})
					"bonus":
						out.append({"text": "%s: +%d dmg (%s)" % [Names.aname(aid), int(ev.get("amt", 0)), _bonus_words(aid)[1]], "cat": "combo"})
					"then":
						var ks := _then_claimed(evs, i, cl)
						if ks.is_empty():
							out.append({"text": "%s: combo" % Names.aname(aid), "cat": "combo"})
						for k in ks:
							var st: Dictionary = evs[k]
							var sw2: Array = STATUS_WORDS.get(String(st.get("status", "")), ["", "affects", ""])
							out.append({"text": "%s %s %s" % [Names.aname(aid), sw2[1], Names.the_name(kind_of(st.get("id"), pre, game))], "cat": "combo"})
				continue
			"status":
				if cl.has(i):
					continue  # its hook or rider names it
			"ignite", "ash":
				if agg.has(t):
					out[agg[t]]["n"] += 1
				else:
					agg[t] = out.size()
					out.append({"text": "", "cat": "info", "agg": t, "n": 1})
				continue
			"reinforcement":
				var rk := String(ev.get("kind", ""))
				if rk == "":
					var tile = ev.get("tile")
					for e in game.enemies:
						if tile != null and e["pos"] == tile and (pre.is_empty() or not pre.get("kinds", {}).has(e["id"])):
							rk = String(e["kind"])
							break
				if not reinf.has(rk):
					reinf[rk] = 0
					out.append({"text": "", "cat": "info", "agg": "reinf", "kind": rk})
				reinf[rk] += 1
				continue
		var ln := _line(ev, pre, game, ctx, evs, i)
		if String(ln[0]) != "":
			out.append({"text": String(ln[0]), "cat": String(ln[1])})
	for e2 in out:
		if not e2.has("agg"):
			continue
		var a := String(e2["agg"])
		if a == "ignite":
			var n := int(e2["n"])
			e2["text"] = "Oil ignites" if n == 1 else "Oil ignites (%d tiles)" % n
		elif a == "ash":
			var n2 := int(e2["n"])
			e2["text"] = "The fire burns down to ash" if n2 == 1 else "%d fires burn down to ash" % n2
		else:
			var rk2 := String(e2["kind"])
			var cnt := int(reinf[rk2])
			if rk2 == "":
				e2["text"] = "A vent releases a machine" if cnt == 1 else "Vents release %d machines" % cnt
			else:
				e2["text"] = ("A vent releases %s" % Names.a_name(rk2)) if cnt == 1 else ("Vents release %d %ss" % [cnt, Names.ename(rk2)])
		e2.erase("agg")
		e2.erase("n")
		e2.erase("kind")
	var mk := _multi(ctx)
	if mk > 0:
		out.append({"text": {2: "Double kill", 3: "Triple kill"}.get(mk, "%d kills this turn" % mk), "cat": "combo"})
	if bool(ctx.get("room_cleared", false)):
		out.append({"text": "Room clear", "cat": "combo"})
	var counts: Dictionary = game.tag_counts() if not Array(ctx.get("res_new", [])).is_empty() else {}
	for rid in ctx.get("res_new", []):
		var row: Dictionary = Content.RESONANCES.get(String(rid), {})
		if not row.is_empty():
			var tag := String(row["tag"])
			out.append({"text": "%s awakens - %s %d/%d" % [String(row["name"]), tag, int(counts.get(tag, 0)), int(row["need"])], "cat": "combo"})
	return out


## The single-event, context-free formatter: one event's line, or "".
static func ev_text(ev: Dictionary, game, pre: Dictionary = {}) -> String:
	var ln := log_entries([ev], pre, game, {})
	return String(ln[0]["text"]) if not ln.is_empty() else ""


## The log's "xN" counter: a line equal to the last one bumps its count
## instead of repeating ("Oil ignites x3"); `cats` stays parallel to `lines`.
static func log_push(lines: Array, cats: Array, s: String, cat: String) -> void:
	if s == "":
		return
	while cats.size() < lines.size():
		cats.append("info")
	if not lines.is_empty():
		var last := String(lines.back())
		if last == s:
			lines[lines.size() - 1] = s + " x2"
			return
		var p := s + " x"
		if last.begins_with(p) and last.substr(p.length()).is_valid_int():
			lines[lines.size() - 1] = p + str(int(last.substr(p.length())) + 1)
			return
	lines.append(s)
	cats.append(cat)


# --- sound --------------------------------------------------------------------

## At most three sounds, worst first (SOUND_PRIO), plus the combo chime chain.
## `extra` are ids another layer wants in the same cap (the danger layer's
## warn). A win or a death silences everything else, chime included.
static func sounds(evs: Array, game, ctx: Dictionary, calls: Array, _hitstop: bool, extra: Array = []) -> Array:
	var picks: Array = []
	var ids := {}
	for ev in evs:
		var t := String(ev.get("t", ""))
		if (t == "damage" or t == "move") and String(ev.get("who", "")) != "player":
			continue
		var id := String(SOUND_OF.get(t, ""))
		if id == "" or ids.has(id):
			continue
		ids[id] = true
		var pitch := 1.0
		if id == "kill":
			pitch = clampf(1.0 + 0.06 * float(int(ctx.get("turn_kills", 1)) - 1), 1.0, 1.3)
		elif t == "shield_absorb":
			pitch = 1.26
		picks.append({"id": id, "pitch": pitch, "delay": 0, "prio": int(SOUND_PRIO.get(id, 10))})
	for x in extra:
		var xid := String(x)
		if xid != "" and not ids.has(xid):
			ids[xid] = true
			picks.append({"id": xid, "pitch": 1.0, "delay": 0, "prio": int(SOUND_PRIO.get(xid, 10))})
	if _multi(ctx) > 0 and not ids.has("multikill"):
		picks.append({"id": "multikill", "pitch": 1.0, "delay": 0, "prio": int(SOUND_PRIO["multikill"])})
	var idx: Array = range(picks.size())
	idx.sort_custom(func(a, b):
		var pa := int(picks[a]["prio"])
		var pb := int(picks[b]["prio"])
		return pa > pb or (pa == pb and a < b))
	var out: Array = []
	for i in mini(3, idx.size()):
		out.append(picks[idx[i]])
	if game != null and bool(game.won):
		return [{"id": "win", "pitch": 1.0, "delay": 0, "prio": 100}]
	for p in out:
		if String(p["id"]) == "death":
			return [p]
	var k := 0
	for c in calls:
		if bool(c["combo"]) and k < CHIME_STEPS.size():
			out.append({"id": "combo", "pitch": pow(2.0, float(CHIME_STEPS[k]) / 12.0),
				"delay": CHIME_FIRST_MS + CHIME_GAP_MS * k, "prio": int(SOUND_PRIO["combo"])})
			k += 1
	if bool(ctx.get("room_cleared", false)):
		out.append({"id": "combo", "pitch": pow(2.0, float(ROOM_CLEAR_SEMIS) / 12.0),
			"delay": CHIME_FIRST_MS + CHIME_GAP_MS * k, "prio": int(SOUND_PRIO["combo"])})
	return out
