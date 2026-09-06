extends SceneTree
## Structural checks on the sim-ignored ability metadata in sim/content.gd:
## 1) every ABILITIES entry has tags from TAGS and a role from ROLES
## 2) every "+" form carries its base's tags/role
## 3) ARCHETYPES cores and package requirements reference real ids
## 4) every draftable ability is in some archetype core, or is mobility/utility
## 5) base_id() round-trips; archetypes_for(DRAFT_POOL) = the package-free set
## 7) SHOP_COSTS prices every shrine service (press, forge); every base ITEMS
##    id has a "+" form (the press can upcycle anything the world hands out)
## 8) the effect grammar (docs/PROGRESSION_REVIEW.md 6.3, Block C1a): every
##    effect dict keeps to the closed op/rider vocabulary, the riders keep to
##    the closed predicate and count sets, and the data tables
##    (Content.TERRAIN / REACTIONS / STATUSES / SURGE_DEFAULT) are complete and
##    self-consistent. A self-test feeds the same lint deliberately bad rows
##    (they must be rejected) and the Block C2 rider rows from the review
##    (they must pass), so this check cannot rot into "accepts everything".
## Run: godot --headless --path . --script tests/test_content.gd

const Content := preload("res://sim/content.gd")

# --- effect-grammar vocabulary (section 8) ------------------------------------
## Every op Game._apply_effect implements, mapped to the keys that op reads.
## An effect dict may carry these, "op", and the rider keys below - nothing
## else, so a typo fails the lint instead of silently no-opping in play.
const OP_KEYS := {
	"lance": ["dmg", "clear_smog_bonus", "ignite"],
	"grow_radius": ["radius"],
	"pull": ["dist", "dmg"],
	"wash_push": ["push", "collision_dmg"],
	"wash_all": ["push", "collision_dmg"],
	"push_line": ["dist", "clear_smoke"],
	"push_all": ["dist"],
	"dash_dir": [],
	"create_terrain": ["kind", "ttl"],
	"clear_smoke": ["radius"],
	"teleport": [],
	"grow_wall": ["ttl"],
	"shield": ["amount"],
	"thorns": ["dmg", "turns"],
	"anchor": ["turns"],
	"undim": ["amount"],
	"aoe_status": ["status", "turns", "radius"],
	"aoe_damage": ["dmg", "radius", "ignite"],
	"convert_radius": ["radius"],
	"apply_status": ["status", "turns"],
	"damage": ["dmg"],
	"status_target": ["status", "turns", "who"],
}
## Optional keys any effect may carry ("surge" is an ability-level key that the
## review's grammar lists with the riders; accepted either way, shape-checked).
const RIDER_KEYS := ["if", "per", "bonus", "then", "surge"]
## Ops whose damage runs through Game._bonus_dmg.
const BONUS_OPS := ["aoe_damage", "lance", "damage", "wash_push", "wash_all", "push_line", "push_all", "pull"]
## Ops that read the parent outcome and are therefore legal only inside "then".
const THEN_ONLY_OPS := ["status_target"]
const STATUS_OPS := ["aoe_status", "apply_status", "status_target"]
const WHO_VALUES := ["affected", "on_planted"]
const IF_PREDS := ["target_on", "target_adjacent", "self_on", "dim", "casts_this_turn_min"]
const IF_PREDS_THEN := ["outcome", "outcome_crossed"]  # then-effect "if" only
const OUTCOME_COUNTERS := ["hit", "ignited", "pushed", "collided", "converted", "planted", "washed", "statused"]
const PER_COUNTS := ["growth_adjacent_target", "fire_within_self", "oil_in_line", "enemies_adjacent_target"]
const PER_KEYS := ["count", "radius", "cap", "add"]
const PER_RADIUS_COUNTS := ["fire_within_self"]  # the only count Game._rider_per radius-limits
## Keys every Content.TERRAIN row must carry (Game reads each one).
const TERRAIN_REQUIRED := [
	"corruption", "shields_core", "flammable", "washable", "bloom", "ttl", "decays",
	"enter_dmg_player", "enter_dmg_enemy", "enter_src", "tick_dmg_player", "tick_dmg_enemy",
	"blocks", "blocks_beam", "heal", "burns_to", "convertible",
]
## "cooldown" stays optional: only the rows that want stagger-style
## immunity (root, since Block C1b) carry one, but where it appears it
## must be a positive int - a 0 or a float would silently disable it.
const STATUS_REQUIRED := ["stack", "blocks", "tick_dmg", "cap"]
## Every enemy intent type Game._execute_intent can be handed; a status may
## only block one of these (or "*", every intent).
const INTENT_TYPES := [
	"idle", "fuse", "summon", "ooze", "stoke", "drag", "move", "gum", "drain",
	"attack", "advance", "slam", "dredge", "quake", "flood", "gather", "ignite_all",
]


func _init() -> void:
	var failures: Array = []

	# 1) tags / role vocabulary
	for aid in Content.ABILITIES.keys():
		var adef: Dictionary = Content.ABILITIES[aid]
		if not adef.has("tags") or not (adef["tags"] is Array) or adef["tags"].is_empty():
			failures.append("%s: missing or empty tags" % aid)
		else:
			for t in adef["tags"]:
				if not Content.TAGS.has(t):
					failures.append("%s: tag '%s' not in TAGS" % [aid, t])
		if not adef.has("role") or not Content.ROLES.has(adef["role"]):
			failures.append("%s: role '%s' not in ROLES" % [aid, str(adef.get("role", "<none>"))])

	# 2) "+" forms mirror their base
	var plus_count := 0
	for aid in Content.ABILITIES.keys():
		var base: String = Content.base_id(aid)
		if base == aid:
			continue
		plus_count += 1
		if not Content.ABILITIES.has(base):
			failures.append("%s: base '%s' missing from ABILITIES" % [aid, base])
			continue
		var adef: Dictionary = Content.ABILITIES[aid]
		var bdef: Dictionary = Content.ABILITIES[base]
		if adef.get("tags", []) != bdef.get("tags", []):
			failures.append("%s: tags %s differ from base %s" % [aid, str(adef.get("tags")), str(bdef.get("tags"))])
		if adef.get("role", "") != bdef.get("role", ""):
			failures.append("%s: role '%s' differs from base '%s'" % [aid, str(adef.get("role")), str(bdef.get("role"))])

	# 3) archetype references
	var core_ids := {}
	for arch_id in Content.ARCHETYPES.keys():
		var arch: Dictionary = Content.ARCHETYPES[arch_id]
		for key in ["name", "core", "requires"]:
			if not arch.has(key):
				failures.append("archetype %s: missing '%s'" % [arch_id, key])
		if arch.get("core", []).is_empty():
			failures.append("archetype %s: empty core" % arch_id)
		for aid in arch.get("core", []):
			core_ids[aid] = true
			if not Content.ABILITIES.has(aid):
				failures.append("archetype %s: core id '%s' not in ABILITIES" % [arch_id, aid])
			elif Content.base_id(aid) != aid:
				failures.append("archetype %s: core id '%s' is a '+' form" % [arch_id, aid])
		var req: Dictionary = arch.get("requires", {})
		for pkg in req.get("packages", []):
			if not Content.PACKAGES.has(pkg):
				failures.append("archetype %s: required package '%s' not in PACKAGES" % [arch_id, pkg])

	# 4) coverage of draftable abilities
	var draftable: Array = Content.DRAFT_POOL.duplicate()
	for pkg in Content.PACKAGES.keys():
		for aid in Content.PACKAGES[pkg]:
			if not draftable.has(aid):
				draftable.append(aid)
	var uncovered: Array = []
	for aid in draftable:
		if core_ids.has(aid):
			continue
		uncovered.append(aid)
		var role: String = str(Content.ABILITIES[aid].get("role", ""))
		if role != "mobility" and role != "utility":
			failures.append("%s (role %s) appears in no archetype core" % [aid, role])
	print("abilities: %d (%d '+' forms), archetypes: %d, draftable: %d" % [
		Content.ABILITIES.size(), plus_count, Content.ARCHETYPES.size(), draftable.size()])
	print("uncovered by any archetype core (mobility/utility allowed): %s" % str(uncovered))

	# 5) base_id round-trips
	for aid in Content.ABILITIES.keys():
		var base: String = Content.base_id(aid)
		if base.find("+") >= 0:
			failures.append("base_id(%s) = '%s' still carries '+'" % [aid, base])
		if Content.base_id(base) != base:
			failures.append("base_id not idempotent on '%s'" % aid)
		if not aid.begins_with(base) or (aid != base and aid != base + "+"):
			failures.append("base_id(%s) = '%s' does not round-trip" % [aid, base])

	# 6) archetypes_for(DRAFT_POOL) is exactly the package-free set, in key order
	var expected: Array = []
	for arch_id in Content.ARCHETYPES.keys():
		if Content.ARCHETYPES[arch_id]["requires"].get("packages", []).is_empty():
			expected.append(arch_id)
	var got: Array = Content.archetypes_for(Content.DRAFT_POOL)
	if got != expected:
		failures.append("archetypes_for(DRAFT_POOL) = %s, expected %s" % [str(got), str(expected)])
	# every package-gated archetype becomes available once its package is in the pool
	for arch_id in Content.ARCHETYPES.keys():
		var pkgs: Array = Content.ARCHETYPES[arch_id]["requires"].get("packages", [])
		if pkgs.is_empty():
			continue
		var pool: Array = Content.DRAFT_POOL.duplicate()
		for pkg in pkgs:
			if Content.PACKAGES.has(pkg):
				pool.append_array(Content.PACKAGES[pkg])
		if not Content.archetypes_for(pool).has(arch_id):
			failures.append("archetypes_for(pool + %s) lacks %s" % [str(pkgs), arch_id])
	print("archetypes_for(DRAFT_POOL): %s" % str(got))

	# 7) shop price list and item upcycle coverage
	for svc in ["heal", "ability", "graft", "item", "press", "forge"]:
		if not Content.SHOP_COSTS.has(svc) or int(Content.SHOP_COSTS[svc]) <= 0:
			failures.append("SHOP_COSTS lacks a positive price for '%s'" % svc)
	var base_items := 0
	for iid in Content.ITEMS.keys():
		if String(iid).ends_with("+"):
			if not Content.ITEMS.has(String(iid).trim_suffix("+")):
				failures.append("item '%s' has no base form" % iid)
			continue
		base_items += 1
		if not Content.ITEMS.has(iid + "+"):
			failures.append("item '%s' has no '+' form for the press" % iid)
	print("shop costs: %s; items: %d base, %d total" % [str(Content.SHOP_COSTS), base_items, Content.ITEMS.size()])

	# 8) effect grammar: content rows, data tables, and the lint's own self-test
	failures.append_array(_lint_effects(Content.ABILITIES))
	failures.append_array(_lint_tables())
	failures.append_array(_lint_selftest())
	print("effect grammar: %d ability rows over %d ops; terrain %d, reactions %d, statuses %d" % [
		Content.ABILITIES.size(), OP_KEYS.size(), Content.TERRAIN.size(),
		Content.REACTIONS.size(), Content.STATUSES.size()])

	if failures.is_empty():
		print("content: OK")
		quit(0)
	else:
		for f in failures:
			print("FAIL: %s" % f)
		print("content: %d failure(s)" % failures.size())
		quit(1)


# --- 8) effect-grammar lint ---------------------------------------------------

## Lints every effect dict of an ABILITIES-shaped table. Returns the failure
## strings (each one starts with the ability id) rather than printing, so the
## self-test below can run it on fixtures.
func _lint_effects(abilities: Dictionary) -> Array:
	var out: Array = []
	for aid in abilities.keys():
		var adef: Dictionary = abilities[aid]
		if adef.has("surge"):
			out.append_array(_lint_surge("%s: surge" % aid, adef["surge"]))
		var effs = adef.get("effects", [])
		if not (effs is Array) or (effs as Array).is_empty():
			out.append("%s: missing or empty effects" % aid)
			continue
		for i in range((effs as Array).size()):
			out.append_array(_lint_effect(effs[i], "%s effect %d" % [aid, i], false))
	return out


## One effect dict. `in_then` is true for the members of a parent "then" list:
## they may use the outcome predicates and the then-only ops, and may not carry
## a "then" of their own.
func _lint_effect(eff, where: String, in_then: bool) -> Array:
	var out: Array = []
	if not (eff is Dictionary):
		return ["%s: effect is not a dictionary" % where]
	var op := String(eff.get("op", ""))
	if not OP_KEYS.has(op):
		return ["%s: unknown op '%s'" % [where, op]]
	if THEN_ONLY_OPS.has(op) and not in_then:
		out.append("%s: op '%s' reads the parent outcome and is then-only" % [where, op])
	var own: Array = OP_KEYS[op]
	for k in eff:
		var key := String(k)
		if key == "op" or own.has(key) or RIDER_KEYS.has(key):
			continue
		out.append("%s: key '%s' is not part of op '%s' %s" % [where, key, op, str(own)])
	if STATUS_OPS.has(op) and not Content.STATUSES.has(String(eff.get("status", ""))):
		out.append("%s: status '%s' not in Content.STATUSES" % [where, str(eff.get("status", ""))])
	if op == "status_target" and not WHO_VALUES.has(String(eff.get("who", "affected"))):
		out.append("%s: who '%s' not in %s" % [where, str(eff.get("who")), str(WHO_VALUES)])
	if op == "create_terrain" and not Content.TERRAIN.has(String(eff.get("kind", ""))):
		out.append("%s: create_terrain kind '%s' not in Content.TERRAIN" % [where, str(eff.get("kind", ""))])
	if eff.has("surge"):
		out.append_array(_lint_surge("%s surge" % where, eff["surge"]))
	if eff.has("if"):
		out.append_array(_lint_if(eff["if"], "%s if" % where, in_then))
	if eff.has("per"):
		out.append_array(_lint_per(eff["per"], op, "%s per" % where))
	if eff.has("bonus"):
		out.append_array(_lint_bonus(eff["bonus"], op, "%s bonus" % where))
	if eff.has("then"):
		if in_then:
			out.append("%s: nested then" % where)
		elif not (eff["then"] is Array) or (eff["then"] as Array).is_empty():
			out.append("%s: then must be a non-empty array of effects" % where)
		else:
			var subs: Array = eff["then"]
			for i in range(subs.size()):
				out.append_array(_lint_effect(subs[i], "%s then %d" % [where, i], true))
	return out


## An "if" list: predicate dicts from the closed set, AND-ed. `allow_outcome`
## is true only for the "if" of a then-effect, the one place where the parent
## outcome exists (a "bonus" is judged per enemy with no outcome in hand, so
## its own predicates never get it either).
func _lint_if(preds, where: String, allow_outcome: bool) -> Array:
	var out: Array = []
	if not (preds is Array) or (preds as Array).is_empty():
		return ["%s: must be a non-empty array of predicate dicts" % where]
	for pred in preds:
		if not (pred is Dictionary):
			out.append("%s: predicate is not a dictionary" % where)
			continue
		for k in pred:
			var key := String(k)
			var v = pred[k]
			if IF_PREDS_THEN.has(key):
				if not allow_outcome:
					out.append("%s: predicate '%s' is legal only inside a then-effect's if" % [where, key])
					continue
			elif not IF_PREDS.has(key):
				out.append("%s: unknown predicate '%s' %s" % [where, key, str(IF_PREDS + IF_PREDS_THEN)])
				continue
			match key:
				"target_on", "target_adjacent":
					if not (v is Array) or (v as Array).is_empty():
						out.append("%s: %s wants a non-empty array of terrain kinds" % [where, key])
					else:
						for kind in v:
							if not Content.TERRAIN.has(String(kind)):
								out.append("%s: %s kind '%s' not in Content.TERRAIN" % [where, key, str(kind)])
				"self_on", "outcome_crossed":
					if not Content.TERRAIN.has(String(v)):
						out.append("%s: %s kind '%s' not in Content.TERRAIN" % [where, key, str(v)])
				"dim", "casts_this_turn_min":
					if not (v is int):
						out.append("%s: %s wants an int, got %s" % [where, key, str(v)])
				"outcome":
					if not OUTCOME_COUNTERS.has(String(v)):
						out.append("%s: outcome '%s' is not an outcome counter %s" % [where, str(v), str(OUTCOME_COUNTERS)])
	return out


## A "per" rider: a closed count, an optional radius only where the sim reads
## one, an int cap, and adds that name keys the op itself reads.
func _lint_per(per, op: String, where: String) -> Array:
	if not (per is Dictionary):
		return ["%s: per must be a dictionary" % where]
	var out: Array = []
	for k in per:
		if not PER_KEYS.has(String(k)):
			out.append("%s: unknown key '%s' %s" % [where, str(k), str(PER_KEYS)])
	var count := String(per.get("count", ""))
	if not PER_COUNTS.has(count):
		out.append("%s: count '%s' not in %s" % [where, count, str(PER_COUNTS)])
	if per.has("radius") and not PER_RADIUS_COUNTS.has(count):
		out.append("%s: radius applies only to %s" % [where, str(PER_RADIUS_COUNTS)])
	if not (per.get("cap", 0) is int):
		out.append("%s: cap must be an int" % where)
	var add = per.get("add", {})
	if not (add is Dictionary) or (add as Dictionary).is_empty():
		out.append("%s: add must be a non-empty dictionary" % where)
	else:
		var own: Array = OP_KEYS.get(op, [])
		for k in add:
			if not own.has(String(k)):
				out.append("%s: add key '%s' is not a key of op '%s' %s" % [where, str(k), op, str(own)])
			if not (add[k] is int):
				out.append("%s: add['%s'] must be an int" % [where, str(k)])
	return out


## A "bonus" rider: flat damage on an op whose hits run through _bonus_dmg.
func _lint_bonus(bonus, op: String, where: String) -> Array:
	if not (bonus is Dictionary):
		return ["%s: bonus must be a dictionary" % where]
	var out: Array = []
	if not BONUS_OPS.has(op):
		out.append("%s: op '%s' never reads a bonus (only %s do)" % [where, op, str(BONUS_OPS)])
	for k in bonus:
		if String(k) != "dmg" and String(k) != "if":
			out.append("%s: unknown key '%s' (dmg, if)" % [where, str(k)])
	if not (bonus.get("dmg", 0) is int):
		out.append("%s: dmg must be an int" % where)
	if bonus.has("if"):
		out.append_array(_lint_if(bonus["if"], "%s if" % where, false))
	return out


func _lint_surge(where: String, surge) -> Array:
	if not (surge is Dictionary):
		return ["%s: surge must be a dictionary" % where]
	var out: Array = []
	for k in surge:
		if String(k) != "cost":
			out.append("%s: unknown key '%s' (only 'cost')" % [where, str(k)])
	if not (surge.get("cost", 0) is int):
		out.append("%s: cost must be an int" % where)
	return out


## The data tables themselves: complete TERRAIN rows, REACTIONS that reference
## real kinds through exactly one trigger, STATUSES that block real intents.
func _lint_tables() -> Array:
	var out: Array = []
	for kind in Content.TERRAIN.keys():
		var row: Dictionary = Content.TERRAIN[kind]
		for key in TERRAIN_REQUIRED:
			if not row.has(key):
				out.append("TERRAIN %s: missing '%s'" % [kind, key])
		var burns := String(row.get("burns_to", ""))
		if burns != "" and not Content.TERRAIN.has(burns):
			out.append("TERRAIN %s: burns_to '%s' not in TERRAIN" % [kind, burns])
		if bool(row.get("decays", false)) and int(row.get("ttl", 0)) < 0:
			out.append("TERRAIN %s: decays with a negative ttl" % kind)
		# convert_radius only ever turns corruption into growth, so a
		# convertible row that is not corruption would be dead data
		if row.has("convertible") and not (row["convertible"] is bool):
			out.append("TERRAIN %s: convertible must be a bool" % kind)
		elif bool(row.get("convertible", false)) and not bool(row.get("corruption", false)):
			out.append("TERRAIN %s: convertible without corruption" % kind)
	var seen := {}
	for row in Content.REACTIONS:
		var rid := String(row.get("id", ""))
		if rid == "" or seen.has(rid):
			out.append("REACTIONS: missing or duplicate id '%s'" % rid)
		seen[rid] = true
		if not Content.TERRAIN.has(String(row.get("from", ""))):
			out.append("REACTIONS %s: from '%s' not in TERRAIN" % [rid, str(row.get("from", ""))])
		var triggers := 0
		for trig in ["adjacent", "on_expire", "on_wash"]:
			if row.has(trig):
				triggers += 1
		if triggers != 1:
			out.append("REACTIONS %s: wants exactly one trigger (adjacent | on_expire | on_wash), has %d" % [rid, triggers])
		if row.has("adjacent") and not Content.TERRAIN.has(String(row["adjacent"])):
			out.append("REACTIONS %s: adjacent '%s' not in TERRAIN" % [rid, str(row["adjacent"])])
		var result := String(row.get("result", ""))
		if result != "" and not Content.TERRAIN.has(result):
			out.append("REACTIONS %s: result '%s' not in TERRAIN" % [rid, result])
		if not (row.get("enabled", null) is bool):
			out.append("REACTIONS %s: enabled must be a bool" % rid)
	for sname in Content.STATUSES.keys():
		var st: Dictionary = Content.STATUSES[sname]
		for key in STATUS_REQUIRED:
			if not st.has(key):
				out.append("STATUSES %s: missing '%s'" % [sname, key])
		var stack := String(st.get("stack", ""))
		if stack != "max" and stack != "add":
			out.append("STATUSES %s: stack '%s' is not max|add" % [sname, stack])
		var blocks: Array = st.get("blocks", [])
		for b in blocks:
			if String(b) != "*" and not INTENT_TYPES.has(String(b)):
				out.append("STATUSES %s: blocks '%s', which is not an enemy intent type" % [sname, str(b)])
		if not blocks.is_empty() and String(st.get("blocked_event", "")) == "":
			out.append("STATUSES %s: blocks %s without a blocked_event" % [sname, str(blocks)])
		if st.has("cooldown") and not (st["cooldown"] is int and int(st["cooldown"]) > 0):
			out.append("STATUSES %s: cooldown must be a positive int" % sname)
	out.append_array(_lint_surge("SURGE_DEFAULT", Content.SURGE_DEFAULT))
	# burns_to (read by Content.counts_as_corruption) and the enabled on_expire
	# REACTIONS row (what the sim actually writes at burnout) must agree, or the
	# pending-corruption count silently diverges from play
	for kind in Content.TERRAIN:
		var burns2 := String(Content.TERRAIN[kind].get("burns_to", ""))
		var expire_result := ""
		var expire_rows := 0
		for row2 in Content.REACTIONS:
			if String(row2.get("from", "")) == kind and row2.has("on_expire") and bool(row2.get("enabled", false)):
				expire_rows += 1
				expire_result = String(row2.get("result", ""))
		if expire_rows > 1:
			out.append("REACTIONS: %d enabled on_expire rows for '%s' (want at most one)" % [expire_rows, kind])
		if burns2 != expire_result:
			out.append("TERRAIN %s: burns_to '%s' disagrees with the enabled on_expire REACTIONS result '%s'" % [kind, burns2, expire_result])
	return out


## Rows the lint MUST reject, one violation each; the id is the failure prefix.
## Kept here rather than in content so the check never needs a broken game.
const BAD_ROWS := {
	"xa_unknown_op": {"effects": [{"op": "melt", "dmg": 1}]},
	"xb_stray_key": {"effects": [{"op": "damage", "dmg": 1, "radius": 2}]},
	"xc_status_name": {"effects": [{"op": "apply_status", "status": "curse", "turns": 1}]},
	"xd_terrain_kind": {"effects": [{"op": "create_terrain", "kind": "lava", "ttl": 2}]},
	"xe_pred_name": {"effects": [{"op": "damage", "dmg": 1, "if": [{"target_near": ["oil"]}]}]},
	"xf_pred_kind": {"effects": [{"op": "damage", "dmg": 1, "if": [{"target_on": ["lava"]}]}]},
	"xg_outcome_outside_then": {"effects": [{"op": "damage", "dmg": 1, "if": [{"outcome": "hit"}]}]},
	"xh_outcome_counter": {"effects": [{"op": "damage", "dmg": 1, "then": [
		{"op": "status_target", "status": "stun", "turns": 1, "if": [{"outcome": "melted"}]}]}]},
	"xi_per_count": {"effects": [{"op": "damage", "dmg": 1, "per": {"count": "stars", "cap": 2, "add": {"dmg": 1}}}]},
	"xj_per_radius": {"effects": [{"op": "damage", "dmg": 1, "per": {
		"count": "oil_in_line", "radius": 2, "cap": 2, "add": {"dmg": 1}}}]},
	"xk_per_add_key": {"effects": [{"op": "damage", "dmg": 1, "per": {
		"count": "oil_in_line", "cap": 2, "add": {"push": 1}}}]},
	"xl_bonus_op": {"effects": [{"op": "shield", "amount": 2, "bonus": {"dmg": 1}}]},
	"xm_bonus_key": {"effects": [{"op": "damage", "dmg": 1, "bonus": {"dmg": 1, "chance": 50}}]},
	"xn_bonus_outcome": {"effects": [{"op": "damage", "dmg": 1, "bonus": {"dmg": 1, "if": [{"outcome": "hit"}]}}]},
	"xo_nested_then": {"effects": [{"op": "damage", "dmg": 1, "then": [
		{"op": "status_target", "status": "stun", "turns": 1, "then": [{"op": "damage", "dmg": 1}]}]}]},
	"xp_then_only_op": {"effects": [{"op": "status_target", "status": "stun", "turns": 1}]},
	"xq_who": {"effects": [{"op": "grow_radius", "radius": 1, "then": [
		{"op": "status_target", "status": "root", "turns": 1, "who": "everyone"}]}]},
	"xr_surge": {"surge": {"cost": "free"}, "effects": [{"op": "damage", "dmg": 1}]},
	"xs_no_effects": {"effects": []},
}

## Rows the lint MUST accept: the Block C2 rider rows exactly as the review
## writes them, plus a surge row and the two counts C2 does not use.
const GOOD_ROWS := {
	"ga_grow_spike": {"effects": [{"op": "damage", "dmg": 3, "per": {
		"count": "growth_adjacent_target", "cap": 2, "add": {"dmg": 1}}}]},
	"gb_sun_flare": {"effects": [{"op": "aoe_damage", "dmg": 2, "radius": 2, "ignite": true,
		"bonus": {"dmg": 1, "if": [{"target_on": ["fire"]}]}}]},
	"gc_water_jet": {"effects": [{"op": "wash_push", "push": 2, "collision_dmg": 2, "then": [
		{"op": "status_target", "status": "root", "turns": 1, "if": [{"outcome": "collided"}]}]}]},
	"gd_vine_whip": {"effects": [{"op": "pull", "dist": 2, "dmg": 2, "then": [
		{"op": "status_target", "status": "stun", "turns": 1, "if": [{"outcome_crossed": "fire"}]}]}]},
	"ge_seed_bomb": {"effects": [{"op": "grow_radius", "radius": 1, "then": [
		{"op": "status_target", "status": "root", "turns": 1, "who": "on_planted"}]}]},
	"gf_surge_lance": {"surge": {"cost": -2}, "effects": [{"op": "lance", "dmg": 2,
		"clear_smog_bonus": 0, "ignite": true, "per": {"count": "oil_in_line", "cap": 3, "add": {"dmg": 1}},
		"if": [{"self_on": "growth"}, {"dim": 0, "casts_this_turn_min": 1}]}]},
	"gg_fire_within": {"effects": [{"op": "aoe_damage", "dmg": 1, "radius": 2, "per": {
		"count": "fire_within_self", "radius": 2, "cap": 4, "add": {"dmg": 1}}}]},
	"gh_enemies_adjacent": {"effects": [{"op": "damage", "dmg": 1, "per": {
		"count": "enemies_adjacent_target", "cap": 2, "add": {"dmg": 1}}, "bonus": {"dmg": 1,
		"if": [{"target_adjacent": ["growth", "roots"]}]}}]},
}


## The lint checking itself: every BAD_ROWS id must be named by at least one
## failure, and GOOD_ROWS must come back clean.
func _lint_selftest() -> Array:
	var out: Array = []
	var bad: Array = _lint_effects(BAD_ROWS)
	for aid in BAD_ROWS.keys():
		var caught := false
		for f in bad:
			if String(f).begins_with(String(aid)):
				caught = true
		if not caught:
			out.append("lint self-test: '%s' is a deliberate violation the lint accepted" % aid)
	var good: Array = _lint_effects(GOOD_ROWS)
	for f in good:
		out.append("lint self-test: rider fixture rejected: %s" % f)
	print("effect-grammar self-test: %d bad rows -> %d failures; %d rider rows -> %d failures" % [
		BAD_ROWS.size(), bad.size(), GOOD_ROWS.size(), good.size()])
	return out
